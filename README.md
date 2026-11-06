# CPU + System Stress (Baseline Health) Benchmark

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![CI](https://github.com/garys-gpu-benchmarks/303-sys-bench-amd-system-stress-stability-ubu2604/actions/workflows/ci.yml/badge.svg)](https://github.com/garys-gpu-benchmarks/303-sys-bench-amd-system-stress-stability-ubu2604/actions/workflows/ci.yml)

Analyzes thermal and power under CPU stress-ng and rocBLAS load. Workload 303 of the AMD Ubuntu 26.04 bundle.

## Quick Start

On an Ubuntu 26.04 host, as root or with sudo:

```bash
git clone https://github.com/garys-gpu-benchmarks/303-sys-bench-amd-system-stress-stability-ubu2604.git
cd 303-sys-bench-amd-system-stress-stability-ubu2604
sudo bash setup.sh --assume-yes
bash run_benchmark.sh --smoke
```

`run_benchmark.sh` runs setup by itself if it has not been run yet. Each run prints its metrics when it finishes.

## Profiles and Parameters

| Parameter | Flag | smoke | baseline | extended |
|---|---|---|---|---|
| `num_threads` | `--num-threads` | 16 | 16 | 16 |
| `cpu_load_percent` | `--cpu-load-percent` | 50 | 50 | 50 |
| `gpu_load_percent` | `--gpu-load-percent` | 50 | 50 | 50 |
| `temp_threshold` | `--temp-threshold` | 100 | 100 | 100 |
| `power_threshold` | `--power-threshold` | 1000 | 1000 | 1000 |
| `duration` | `--duration` | 5 | 200 | 580 |
| `poll_interval` | `--poll-interval` | 1 | 1 | 1 |

Pick a profile with `--smoke` (default), `--baseline` or `--extended`. Any flag in the table overrides that profile's value:

```bash
bash run_benchmark.sh --baseline --num-threads 8
bash run_benchmark.sh --help        # every option
```

Profile values live in `config/benchmark_config.yaml`.

## Metrics

| # | Metric | Key |
|---|---|---|
| 1 | Peak GPU junction temperature | `peak_gpu_junction_temp_c` |
| 2 | Sustained GPU power | `sustained_gpu_power_w` |
| 3 | Uncorrectable ECC errors, RAS counter delta | `ras_uncorrectable_ecc_delta_count` |
| 4 | Thermal throttle events | `thermal_throttle_event_count` |

### Notes

- The smoke profile is a quick check with reduced sizes and iteration counts. Use `--baseline` or `--extended` for representative numbers.
- Only the CPU is stressed when gpu_load_percent is 0, the default.
- A positive value starts a PyTorch matmul.
- Duration comes from yaml (5 / 200 / 580 s).

## Output

| Path | Contents |
|---|---|
| `results/raw/YYYYMMDD_HHMMSSZ_WORKLOAD-<NNN>_SYSTEM-<hostname>/` | Raw tool output, `metrics_summary.txt`, and `hardware_info.txt`, `software_info.txt`, `errors_info.txt` |
| `results/benchmark.db` | SQLite history of every run |
| `results/summary.json` | Metrics from the most recent run |
| `/var/opt/benchmarks/runtime_ledger.csv` | One row per run, shared by every workload on the host |

Every run is checked for completeness and against any `thresholds:` or `baselines:` in `config/benchmark_config.yaml`. A run that fails the checks exits non-zero.

## Requirements

- Ubuntu 26.04, root or sudo for `setup.sh`
- AMD GPU with ROCm 10.1.0 (validated on MI300X)
- stress-ng, amd-smi, Python 3.14 (uv-managed). `setup.sh` installs what is missing; Python packages go into a repo-local `.venv`.

## Run the Whole Bundle

This workload is also part of [`bundle-amd-ubuntu-2604`](https://github.com/garys-gpu-benchmarks/bundle-amd-ubuntu-2604), which holds all 32 AMD Ubuntu 26.04 workloads as submodules:

```bash
git clone --recurse-submodules https://github.com/garys-gpu-benchmarks/bundle-amd-ubuntu-2604 /opt/benchmarks
cd /opt/benchmarks
./run_benchmark_suite.sh -w 303 --smoke     # just this workload
./run_benchmark_suite.sh --smoke            # all 32 workloads
./show_metrics.sh 303                       # this workload's runs from the ledger
```

The suite tools (`run_benchmark_suite.sh`, `get_benchmark_results.sh`, `show_ledger_runs.sh`, `show_metrics.sh`) are documented in [`gpu-bench-suite`](https://github.com/garys-gpu-benchmarks/gpu-bench-suite).

Other platforms: [AMD 24.04](https://github.com/garys-gpu-benchmarks/bundle-amd-ubuntu-2404) (101–132), [NVIDIA 24.04](https://github.com/garys-gpu-benchmarks/bundle-nvidia-ubuntu-2404) (201–232), [NVIDIA 26.04](https://github.com/garys-gpu-benchmarks/bundle-nvidia-ubuntu-2604) (401–432).

## Troubleshooting

- **The SSH session closed during setup:** the first AMD workload on a fresh host may reboot once to load the AMD GPU driver. Setup prints a 30-second warning first and resumes by itself after boot. SSH back in and run `tail -f results/reboot_resume.log`; when it prints `SETUP COMPLETE`, run your command again. Do not start `setup.sh` again while it is resuming.
- **SSH dropped for another reason:** reconnect and run `sudo bash setup.sh --assume-yes` again. It resumes; do not delete `.venv` or `.cache`.
- **A metric reads `na`:** the run could not measure it on this host. The reason is in the run's `metrics_summary.txt` and `errors_info.txt`; see also [Notes](#notes).

## Repository Layout

```text
.
├── setup.sh                      # installs dependencies and builds the benchmark
├── run_benchmark.sh              # runs one profile, parses, validates
├── show_metrics.sh               # prints this workload's ledger rows
├── SPEC.md                       # engineering specification
├── benchmark_specification.json  # workload definition
├── config/                       # profile values and thresholds
├── scripts/                      # build, collect, parse, validate
├── docs/                         # PRD and contracts
├── tests/
├── results/                      # run outputs
└── LICENSE
```

## Continuous Integration

- [CI](.github/workflows/ci.yml) runs lint and static checks on every pull request and push to `main`. It does not run the benchmark.
- [GPU Smoke Benchmark](.github/workflows/gpu-smoke.yml) runs a profile on a self-hosted runner labeled `gpu`, `amd`, `ubu2604`. It only starts by hand (**Actions → GPU Smoke Benchmark → Run workflow**), so pull requests and forks cannot run it.

Both workflows call shared steps in [`shared-workflows@v1`](https://github.com/garys-gpu-benchmarks/shared-workflows).
