# Results: 303 CPU + System Stress (Baseline Health)

**Main goal:** Analyze thermal and power under CPU stress-ng and rocBLAS load  
**Tools:** Run stress-ng --cpu, rocblas-bench, amd-smi metric, and sysfs power1_average

Reference results measured by the maintainer on the system shown in each section (generator TEMPLATE_00_141 · recorded 2026-11-14). Your own runs write `results/RESULTS_ACTUAL.md` in the same format.

> Smoke runs use deliberately small sizes. They check that the workload installs and runs end to end; their numbers are not performance results. Baseline and extended are.

<!-- profile:smoke -->
## smoke

- **System:** 1× AMD Instinct MI300X VF (196288 MB) · INTEL(R) XEON(R) PLATINUM 8568Y+ · Ubuntu 26.04.1 LTS · kernel 7.0.0-38-generic · driver 7.1.9.31600000
- **Run:** 2026-11-14T10:51:00Z · status **N/A-EXPECTED** (exit 0)
- **Time (mm:ss):** setup 04:04 · benchmark 00:13 · whole run 04:22
- **Source:** run 303_20261114_105100
- **Command:** `bash run_benchmark.sh --smoke --num-threads 16 --cpu-load-percent 50 --gpu-load-percent 50 --temp-threshold 100 --power-threshold 1000 --duration 5 --poll-interval 1`

| # | Metric | Result |
|---|---|---|
| 1 | Peak GPU junction temperature (peak_gpu_junction_temp_c) | 62.0 |
| 2 | Sustained GPU power (sustained_gpu_power_w) | 657.0 |
| 3 | Uncorrectable ECC errors, RAS counter delta (ras_uncorrectable_ecc_delta_count) | 0.0 |
| 4 | Thermal throttle events (thermal_throttle_event_count) | na (expected: throttle counter not exposed) |
<!-- /profile:smoke -->
