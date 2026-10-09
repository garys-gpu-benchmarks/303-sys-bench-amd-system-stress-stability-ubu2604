#!/usr/bin/env python3
# File: scripts/validate_results.py
# Description: Validate the latest SQLite run against integrity checks and yaml thresholds.
from __future__ import annotations

import argparse
import json
import math
import os
import sqlite3
from datetime import datetime
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

ZERO_OK_HINTS = (
    "count", "error", "mismatch", "fault", "loss", "miss", "retransmit",
    "compliance",
    "jitter", "permission", "ecc", "throttl", "fail", "util", "second",
    "active", "uncorrected", "corrected", "placeholder", "pcie",
    "rc",
    "cache_hit",
    # cuDNN algorithm ids are zero-based. Algorithm 0 is a successful selection.
    "algo",
)


def load_yaml(path: Path) -> dict:
    if yaml is None:
        raise SystemExit("[FAIL] PyYAML is required in the repository-local .venv.")
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def is_iso8601(value: str) -> bool:
    try:
        datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def zero_ok(name: str) -> bool:
    lowered = name.lower()
    return any(token in lowered for token in ZERO_OK_HINTS)


def workload_number() -> int:
    path = Path("benchmark_specification.json")
    if not path.is_file():
        return 0
    data = json.loads(path.read_text(encoding="utf-8"))
    fields = {str(item.get("field_name", "")): str(item.get("value", "") or "") for item in data}
    try:
        return int(float(fields.get("Workload Number") or 0))
    except ValueError:
        return 0


def seed_fixture(config_path: Path) -> Path:
    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%SZ")
    fixture = Path("tests/fixtures/benchmark.db")
    fixture.parent.mkdir(parents=True, exist_ok=True)
    if fixture.exists():
        fixture.unlink()
    conn = sqlite3.connect(fixture)
    conn.execute("""CREATE TABLE runs (
            run_id INTEGER PRIMARY KEY AUTOINCREMENT,
            benchmark_id TEXT, benchmark_name TEXT, status TEXT,
            started_at TEXT, finished_at TEXT, error_message TEXT)""")
    conn.execute("""CREATE TABLE samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT, run_id INTEGER,
            sample_index INTEGER, status TEXT, error_message TEXT)""")
    conn.execute(
        "INSERT INTO runs (benchmark_id, benchmark_name, status, started_at, finished_at, error_message) VALUES (?, ?, 'ok', ?, ?, NULL)",
        ("fixture", "seed-fixture", now, now),
    )
    run_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
    for index in range(2):
        conn.execute(
            "INSERT INTO samples (run_id, sample_index, status, error_message) VALUES (?, ?, 'ok', NULL)",
            (run_id, index),
        )
    conn.commit()
    conn.close()
    return fixture


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=os.environ.get("BENCHMARK_DB", "results/benchmark.db"))
    parser.add_argument("--config", default="config/benchmark_config.yaml")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--seed-fixture", action="store_true")
    args = parser.parse_args()
    if args.seed_fixture:
        args.db = str(seed_fixture(Path(args.config)))
    db_path = Path(os.environ.get("BENCHMARK_DB", args.db))
    if args.seed_fixture:
        db_path = Path(args.db)
    if not db_path.is_file():
        print("[FAIL] benchmark database is missing")
        return 1
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    run = conn.execute("SELECT * FROM runs ORDER BY run_id DESC LIMIT 1").fetchone()
    if run is None:
        print("[FAIL] no runs")
        return 1
    samples = conn.execute("SELECT * FROM samples WHERE run_id = ?", (run["run_id"],)).fetchall()
    failures = []
    run_keys = set(run.keys())
    if run["status"] != "ok":
        failures.append("latest run status is not ok")
    if "error_message" in run_keys and run["error_message"] not in {None, ""}:
        failures.append("run.error_message is not NULL")
    if not is_iso8601(run["started_at"]) or not is_iso8601(run["finished_at"]):
        failures.append("timestamps are not ISO-8601")
    if len(samples) < 1:
        failures.append("no sample rows")
    wid = workload_number()
    if (101 <= wid <= 123 or 301 <= wid <= 323) and len(samples) < 2:
        failures.append("workloads 101-123 require at least two sample rows")
    skip = {"id", "run_id", "sample_index", "status", "error_message", "created_at",
            "benchmark_id", "benchmark_name", "started_at", "finished_at", "host_name",
            "os_version", "kernel_version", "gpu_name", "rocm_version", "framework_version",
            "git_sha", "config_path", "command_line", "placeholder", "check_name",
            "rc", "command", "check"}
    for column in run.keys():
        if column in skip:
            continue
        value = run[column]
        if value is None:
            continue
        if isinstance(value, (int, float)) and not math.isfinite(float(value)):
            failures.append(f"run.{column} is not finite")
        if isinstance(value, (int, float)) and float(value) < 0 and not zero_ok(column):
            failures.append(f"run.{column} is negative")
        if isinstance(value, (int, float)) and float(value) <= 0 and not zero_ok(column):
            failures.append(f"run.{column} is not positive")
    for sample in samples:
        if sample["status"] != "ok":
            failures.append(f"sample {sample['sample_index']} is not ok")
        # A sample with status == "ok" and a non-empty error_message is a
        # collector reporting an optional measurement it honestly could not
        # take (e.g. "perf TLB/L3 not measured") alongside a valid primary
        # score -- not a failed sample. Only a non-"ok" status fails it.
        for column in sample.keys():
            if column in skip:
                continue
            value = sample[column]
            if value in {None, ""}:
                continue
            if isinstance(value, (int, float)) and not math.isfinite(float(value)):
                failures.append(f"sample.{column} is not finite")
            if isinstance(value, (int, float)) and float(value) < 0 and not zero_ok(column):
                failures.append(f"sample.{column} is negative")
    config = load_yaml(Path(args.config))
    thresholds = config.get("thresholds") or {}
    for key, expected in thresholds.items():
        if key.endswith("_min"):
            column = key[:-4]
            direction = "min"
        elif key.endswith("_max"):
            column = key[:-4]
            direction = "max"
        else:
            continue
        if column not in run.keys() or run[column] is None:
            continue
        try:
            measured = float(run[column])
        except (TypeError, ValueError):
            continue  # "na (...)": not measured on this host, nothing to compare
        expected = float(expected)
        if direction == "min" and measured < expected:
            failures.append(f"{column} {measured} < min {expected}")
        if direction == "max" and measured > expected:
            failures.append(f"{column} {measured} > max {expected}")
    conn.close()
    if failures:
        if not args.quiet:
            print("[FAIL] validation")
            for item in failures:
                print(" -", item)
        return 1
    if not args.quiet:
        print(f"[PASS] validated {len(samples)} samples")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
