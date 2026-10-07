# SPEC.md: "The Human How"; Exact technical requirements, environment setup, implementation details, etc.

## Execution Description

Runs CPU-only stress-ng while polling rocm-smi/amd-smi once per second. num_threads: stress-ng --cpu workers (16). cpu_load_percent: stress-ng --cpu-load (50). duration: smoke 5 / baseline 200 / extended 580 s. Sweep dimensions: num_threads, cpu_load_percent, gpu_load_percent, temp_threshold, power_threshold, throttle_check, ecc_check, duration.

## Parameters

| Parameter | CLI Flag | Tested Values | Default | Description |
| --- | --- | --- | --- | --- |
| num_threads | `--num-threads` | smoke=16, baseline=16, extended=16 | 16 | From Parameter list; see Execution Description With Parameters. |
| cpu_load_percent | `--cpu-load-percent` | smoke=50, baseline=50, extended=50 | 50 | From Parameter list; see Execution Description With Parameters. |
| gpu_load_percent | `--gpu-load-percent` | smoke=50, baseline=50, extended=50 | 50 | From Parameter list; see Execution Description With Parameters. |
| temp_threshold | `--temp-threshold` | smoke=75, baseline=75, extended=75 | 75 | From Parameter list; see Execution Description With Parameters. |
| power_threshold | `--power-threshold` | smoke=500, baseline=500, extended=500 | 500 | From Parameter list; see Execution Description With Parameters. |
| throttle_check | `--throttle-check` | smoke=true, baseline=true, extended=true | true | From Parameter list; see Execution Description With Parameters. |
| ecc_check | `--ecc-check` | smoke=true, baseline=true, extended=true | true | From Parameter list; see Execution Description With Parameters. |
| duration | `--duration` | smoke=5, baseline=200, extended=580 | 200 | From Parameter list; see Execution Description With Parameters. |
| output_format | `--output-format` | smoke=csv, baseline=csv, extended=csv | csv | From Parameter list; see Execution Description With Parameters. |

## Invocation

```bash
Run stress-ng --cpu, rocm-smi and/or amd-smi metric, and sysfs power1_average
```

## Raw Output Format

CSV with one time-series row per elapsed second

sample_index,second,gpu_util_pct,gpu_temp_c,gpu_power_w,ecc_uncorrected,peak_gpu_junction_temp_c,sustained_gpu_power_w,thermal_throttle_event_count,gpu_system_ecc_error_count
0,0,0,45,75,0,45,75,0,0

## Metrics

- **#1: Peak GPU junction temperature** — stored as `peak_gpu_junction_temp_c`.
- **#2: Sustained GPU power** — stored as `sustained_gpu_power_w`.
- **#3: GPU ECC error count** — stored as `gpu_system_ecc_error_count`.
- **#4: Thermal throttle events** — stored as `thermal_throttle_event_count`.

## Framework

Runs CPU-only stress-ng while polling rocm-smi/amd-smi once per second. num_threads: stress-ng --cpu workers (16). cpu_load_percent: stress-ng --cpu-load (50).

## Installation and Execution Summary

Run stress-ng --cpu <num_threads> --cpu-load <cpu_load_percent> --timeout <duration>s while polling rocm-smi/amd-smi each second, to measure peak CPU/GPU temperature and GPU power over the wall-clock window. No rocblas-bench GPU load is started

## Platform Portability

- **AMD (primary):** ```bash
Run stress-ng --cpu, rocm-smi and/or amd-smi metric, and sysfs power1_average
```
- **NVIDIA:** Primary target is AMD ROCm. NVIDIA notes in this section are reference only and are not the execution path.

## Model Context Protocols

- **Active:** None

## Execution-Loop Validation Contract

EXECUTION CHAIN: `run_benchmark.sh` ➔ raw output ➔ `scripts/parse_results.py` ➔ `results/benchmark.db` ➔ `scripts/validate_results.py`

This benchmark uses a lightweight, SQLite-integrated execution loop for result validation. All validation is performed by `scripts/validate_results.py`.

### Validation script usage

```bash
export BENCHMARK_PYTHON=/usr/bin/python3.13  # optional; select the installed interpreter

# After a live run:
".venv/bin/python" scripts/validate_results.py --db results/benchmark.db

# CI / no-GPU path (seeds fixture and validates it):
".venv/bin/python" scripts/validate_results.py --seed-fixture --quiet

# Override DB path via environment variable:
BENCHMARK_DB=tests/fixtures/benchmark.db \
  ".venv/bin/python" scripts/validate_results.py
```

### Run artifact contract

CSV with one time-series row per elapsed second

sample_index,second,gpu_util_pct,gpu_temp_c,gpu_power_w,ecc_uncorrected,peak_gpu_junction_temp_c,sustained_gpu_power_w,thermal_throttle_event_count,gpu_system_ecc_error_count
0,0,0,45,75,0,45,75,0,0

```bash
bash run_benchmark.sh --help
bash run_benchmark.sh --profile smoke --validate
bash run_benchmark.sh --profile baseline --validate
bash run_benchmark.sh --profile extended --validate
```
`run_benchmark.sh --help` prints usage and exits. The harness calls `scripts/ensure_setup.sh` when `.setup_state` is absent.

### Required integrity checks (built into `validate_results.py`)

1. Latest run exists and `runs.status = 'ok'`.
2. `run.error_message` is NULL.
3. `started_at` and `finished_at` are valid ISO-8601 UTC strings.
4. All required aggregate metrics in `runs` are non-NULL and finite.
5. All required aggregate metrics are physically sensible (positive values). Runs CPU-only stress-ng while polling rocm-smi/amd-smi once per second. num_threads: stress-ng --cpu workers (16). cpu_load_percent: stress-ng --cpu-load (50).
6. At least 2 sample rows exist for the latest `run_id` (sweep coverage).
7. No sample has `status = 'error'`.
8. Runs CPU-only stress-ng while polling rocm-smi/amd-smi once per second. num_threads: stress-ng --cpu workers (16). cpu_load_percent: stress-ng --cpu-load (50).

### Baseline / Threshold configuration (`config/benchmark_config.yaml`)

Expected ranges and gates live in `config/benchmark_config.yaml` under `baselines:` or `thresholds:`. To update them, edit that file — never edit validation code directly.

Threshold key suffixes encode comparison direction when `thresholds:` is present: `_min` → observed value must be ≥ threshold. `_max` → observed value must be ≤ threshold. Informational `baselines:` ranges are not pass/fail gates.
