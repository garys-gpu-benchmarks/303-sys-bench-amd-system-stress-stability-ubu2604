#!/usr/bin/env bash
# File: run_benchmark.sh
# Description: Runs CPU-only stress-ng while polling rocm-smi/amd-smi once per second.
# Execution: bash run_benchmark.sh [--profile smoke|baseline|extended] [--validate]
# Options: --profile, --smoke, --baseline, --extended, --device, --phase, --raw-file, --config, --validate, --help
# Requirements: bash, python3, repository-local .venv
# Dependencies: common.sh, collect_workload.py
# License: Apache-2.0
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "${REPO_ROOT}")"
cd "${REPO_ROOT}"
# shellcheck disable=SC1091
source scripts/lib/common.sh
capture_benchmark_run_command_submitted "$@"

usage() {
  cat <<'USAGE'
Usage: bash run_benchmark.sh [OPTIONS]

Runs CPU-only stress-ng while polling rocm-smi/amd-smi once per second.

Profiles:
  --profile <name>              Run profile: smoke|baseline|extended (default: smoke)
  --smoke                       Run smoke profile
  --baseline                    Run baseline profile
  --extended                    Run extended profile

Execution:
  --device <gpu|cpu>            Execution device (default: gpu)
  --phase <phaseN|N>            Run one phase (phase1|phase2|phase3|phase4, or 1-4)
  --phase1                      Collection
  --phase2                      Collection alias
  --phase3                      Parse only; requires --raw-file <path>
  --phase4                      Validation only
  --raw-file <path>             Existing raw file for --phase3
  --config <file>               Config file (default: config/benchmark_config.yaml)

Validation and logging:
  --validate                    Enable result validation (default)
  --no-validate                 Skip result validation
  --quiet                       Suppress nonessential stdout
  --log-level <level>           ERROR|WARN|INFO|DEBUG (default: INFO)
  --output-format <fmt>         Override config output_format
  --save-options-file <path>    Write resolved CLI options to PATH

Workload options:
  --num-threads <value>            Override num_threads
  --cpu-load-percent <value>            Override cpu_load_percent
  --gpu-load-percent <value>            Override gpu_load_percent
  --temp-threshold <value>            Override temp_threshold
  --power-threshold <value>            Override power_threshold
  --throttle-check <value>            Override throttle_check
  --ecc-check <value>            Override ecc_check
  --duration <value>            Override duration
  --output-format <value>            Override output_format

Information:
  --specification               Print this workload's specification and exit
  --matrix-definition           Same as --specification
  --help                        Show this help and exit

Examples:
  bash run_benchmark.sh --profile smoke --validate
  bash run_benchmark.sh --baseline --device gpu
  bash run_benchmark.sh --phase3 --raw-file results/raw/<run>/raw_output.txt
USAGE
}

for _help_arg in "$@"; do
  case "${_help_arg}" in
    --help) usage; exit 0 ;;
    --specification|--matrix-definition)
      python3 scripts/print_benchmark_definition.py
      exit 0
      ;;
  esac
done

PROFILE="smoke"
DEVICE="gpu"
PHASE="all"
RAW_FILE=""
CONFIG_FILE="config/benchmark_config.yaml"
VALIDATE=1
QUIET=0
LOG_LEVEL_VALUE="INFO"
OUTPUT_FORMAT=""
SAVE_OPTIONS_FILE=""
NUM_THREADS=""
CPU_LOAD_PERCENT=""
GPU_LOAD_PERCENT=""
TEMP_THRESHOLD=""
POWER_THRESHOLD=""
THROTTLE_CHECK=""
ECC_CHECK=""
DURATION=""
OUTPUT_FORMAT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --smoke) PROFILE="smoke"; shift ;;
    --baseline) PROFILE="baseline"; shift ;;
    --extended) PROFILE="extended"; shift ;;
    --device) DEVICE="${2:-}"; shift 2 ;;
    --phase) PHASE="${2:-}"; shift 2 ;;
    --phase1|--phase2) PHASE="1"; shift ;;
    --phase3) PHASE="3"; shift ;;
    --phase4) PHASE="4"; shift ;;
    --raw-file) RAW_FILE="${2:-}"; shift 2 ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --validate) VALIDATE=1; shift ;;
    --no-validate) VALIDATE=0; shift ;;
    --quiet) QUIET=1; shift ;;
    --log-level) LOG_LEVEL_VALUE="${2:-}"; shift 2 ;;
    --output-format) OUTPUT_FORMAT="${2:-}"; shift 2 ;;
    --save-options-file) SAVE_OPTIONS_FILE="${2:-}"; shift 2 ;;
    --num-threads) NUM_THREADS="${2:-}"; shift 2 ;;
    --cpu-load-percent) CPU_LOAD_PERCENT="${2:-}"; shift 2 ;;
    --gpu-load-percent) GPU_LOAD_PERCENT="${2:-}"; shift 2 ;;
    --temp-threshold) TEMP_THRESHOLD="${2:-}"; shift 2 ;;
    --power-threshold) POWER_THRESHOLD="${2:-}"; shift 2 ;;
    --throttle-check) THROTTLE_CHECK="${2:-}"; shift 2 ;;
    --ecc-check) ECC_CHECK="${2:-}"; shift 2 ;;
    --duration) DURATION="${2:-}"; shift 2 ;;
    --output-format) OUTPUT_FORMAT="${2:-}"; shift 2 ;;
    --help|--specification|--matrix-definition) shift ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "${PHASE}" in
  all|phase1|phase2|phase3|phase4|1|2|3|4) ;;
  *) die "Unsupported --phase value: ${PHASE}" ;;
esac
if [[ "${PHASE}" == phase* ]]; then PHASE="${PHASE#phase}"; fi

set_log_level "${LOG_LEVEL_VALUE}"
begin_benchmark_run "${PROFILE}"
if [[ "${PHASE}" != "3" && "${PHASE}" != "4" ]]; then
  bash scripts/ensure_setup.sh
fi
mark_benchmark_measure_start
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python"
[[ -x "${PYTHON_BIN}" ]] || die "Missing ${PYTHON_BIN}; run bash setup.sh --assume-yes first."

yaml_get() {
  "${PYTHON_BIN}" - "${CONFIG_FILE}" "${PROFILE}" "$1" <<'PY'
import sys
from pathlib import Path
import yaml
key = sys.argv[3]
profile = sys.argv[2]
cfg = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
sweep = cfg.get("sweep") or {}
raw_value = sweep.get(key, "")
if isinstance(raw_value, dict):
    raw_value = raw_value.get(profile, next(iter(raw_value.values()), ""))
if isinstance(raw_value, list):
    raw_value = ",".join(str(item) for item in raw_value)
print("" if raw_value is None else raw_value)
PY
}

NUM_THREADS="${NUM_THREADS:-$(yaml_get num_threads)}"
CPU_LOAD_PERCENT="${CPU_LOAD_PERCENT:-$(yaml_get cpu_load_percent)}"
GPU_LOAD_PERCENT="${GPU_LOAD_PERCENT:-$(yaml_get gpu_load_percent)}"
TEMP_THRESHOLD="${TEMP_THRESHOLD:-$(yaml_get temp_threshold)}"
POWER_THRESHOLD="${POWER_THRESHOLD:-$(yaml_get power_threshold)}"
THROTTLE_CHECK="${THROTTLE_CHECK:-$(yaml_get throttle_check)}"
ECC_CHECK="${ECC_CHECK:-$(yaml_get ecc_check)}"
DURATION="${DURATION:-$(yaml_get duration)}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-$(yaml_get output_format)}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-$(yaml_get output_format)}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-csv}"

BENCHMARK_RUN_COMMAND="bash run_benchmark.sh --${PROFILE}"
[[ "${VALIDATE}" -eq 1 ]] && BENCHMARK_RUN_COMMAND+=" --validate"
[[ -n "${NUM_THREADS}" ]] && BENCHMARK_RUN_COMMAND+=" --num-threads $(printf %q "${NUM_THREADS}")"
[[ -n "${CPU_LOAD_PERCENT}" ]] && BENCHMARK_RUN_COMMAND+=" --cpu-load-percent $(printf %q "${CPU_LOAD_PERCENT}")"
[[ -n "${GPU_LOAD_PERCENT}" ]] && BENCHMARK_RUN_COMMAND+=" --gpu-load-percent $(printf %q "${GPU_LOAD_PERCENT}")"
[[ -n "${TEMP_THRESHOLD}" ]] && BENCHMARK_RUN_COMMAND+=" --temp-threshold $(printf %q "${TEMP_THRESHOLD}")"
[[ -n "${POWER_THRESHOLD}" ]] && BENCHMARK_RUN_COMMAND+=" --power-threshold $(printf %q "${POWER_THRESHOLD}")"
[[ -n "${THROTTLE_CHECK}" ]] && BENCHMARK_RUN_COMMAND+=" --throttle-check $(printf %q "${THROTTLE_CHECK}")"
[[ -n "${ECC_CHECK}" ]] && BENCHMARK_RUN_COMMAND+=" --ecc-check $(printf %q "${ECC_CHECK}")"
[[ -n "${DURATION}" ]] && BENCHMARK_RUN_COMMAND+=" --duration $(printf %q "${DURATION}")"
[[ -n "${OUTPUT_FORMAT}" ]] && BENCHMARK_RUN_COMMAND+=" --output-format $(printf %q "${OUTPUT_FORMAT}")"
set_benchmark_run_command "${BENCHMARK_RUN_COMMAND}"

HOSTNAME_VALUE="$(hostname -s 2>/dev/null || hostname)"
STAMP="$(date -u +"%Y%m%d_%H%M%S")"
if [[ -z "${RAW_FILE}" ]]; then
  RUN_DIR="${REPO_ROOT}/results/raw/${STAMP}_${REPO_NAME}_${HOSTNAME_VALUE}"
  mkdir -p "${RUN_DIR}"
  RAW_FILE="${RUN_DIR}/raw_output.txt"
else
  RUN_DIR="$(cd "$(dirname "${RAW_FILE}")" && pwd)"
fi
set_benchmark_run_dir "${RUN_DIR}"
COMMAND_LOG="${RUN_DIR}/commands_executed.sh"
{ echo "#!/usr/bin/env bash"; echo "set -euo pipefail"; } > "${COMMAND_LOG}"
chmod +x "${COMMAND_LOG}"
[[ -n "${SAVE_OPTIONS_FILE}" ]] && printf 'profile=%s\noutput_format=%s\n' "${PROFILE}" "${OUTPUT_FORMAT}" > "${SAVE_OPTIONS_FILE}"
printf 'profile=%s\ndevice=%s\noutput_format=%s\n' "${PROFILE}" "${DEVICE}" "${OUTPUT_FORMAT}" > "${RUN_DIR}/cli_options.env"
export PYTHONUNBUFFERED=1
export PATH="/opt/rocm/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64:${LD_LIBRARY_PATH:-}"
cp run_benchmark.sh "${RUN_DIR}/script.sh"
mask_environment "${RUN_DIR}/env_variables.txt"
: > "${RUN_DIR}/run.log"

run_collection() {
  log_section "Collection"
  local help collect_cmd
  local -a collect_args=(--run-dir "${RUN_DIR}" --raw-file "${RAW_FILE}" --profile "${PROFILE}")
  help="$("${PYTHON_BIN}" scripts/collect_workload.py --help 2>&1 || true)"
  grep -q -- '--config' <<<"${help}" && collect_args+=(--config "${CONFIG_FILE}")
  # A substring grep for '--device' also matches '--device-id' (it's a
  # prefix), which made the harness pass the literal word "gpu"/"cpu" as
  # --device onto a collector that only defines --device-id; argparse then
  # prefix-matched it and int("gpu") crashed before any RESULT/CSV line.
  # Require a standalone --device flag, and fall back to --device-id with a
  # numeric index when only that flag exists.
  if grep -qE -- '(^|[^-])--device([[:space:],]|$)' <<<"${help}"; then
    collect_args+=(--device "${DEVICE}")
  elif grep -qE -- '(^|[^-])--device-id([[:space:],]|$)' <<<"${help}"; then
    collect_args+=(--device-id "${DEVICE_ID:-0}")
  fi
  grep -q -- '--output-format' <<<"${help}" && collect_args+=(--output-format "${OUTPUT_FORMAT}")
  grep -q -- '--num-threads' <<<"${help}" && collect_args+=(--num-threads "${NUM_THREADS}")
  grep -q -- '--cpu-load-percent' <<<"${help}" && collect_args+=(--cpu-load-percent "${CPU_LOAD_PERCENT}")
  grep -q -- '--gpu-load-percent' <<<"${help}" && collect_args+=(--gpu-load-percent "${GPU_LOAD_PERCENT}")
  grep -q -- '--temp-threshold' <<<"${help}" && collect_args+=(--temp-threshold "${TEMP_THRESHOLD}")
  grep -q -- '--power-threshold' <<<"${help}" && collect_args+=(--power-threshold "${POWER_THRESHOLD}")
  grep -q -- '--throttle-check' <<<"${help}" && collect_args+=(--throttle-check "${THROTTLE_CHECK}")
  grep -q -- '--ecc-check' <<<"${help}" && collect_args+=(--ecc-check "${ECC_CHECK}")
  grep -q -- '--duration' <<<"${help}" && collect_args+=(--duration "${DURATION}")
  grep -q -- '--output-format' <<<"${help}" && collect_args+=(--output-format "${OUTPUT_FORMAT}")

  printf -v collect_cmd '%q ' "${PYTHON_BIN}" scripts/collect_workload.py "${collect_args[@]}"
  echo "[RUN] ${collect_cmd}"
  echo "${collect_cmd}" >> "${COMMAND_LOG}"
  set +e
  "${PYTHON_BIN}" scripts/collect_workload.py "${collect_args[@]}" 2>&1 | tee -a "${RUN_DIR}/run.log"
  command_status="${PIPESTATUS[0]}"
  set -e
  if [[ "${command_status}" -ne 0 ]]; then
    die "collection failed with status ${command_status}"
  fi
}

run_parse() {
  log_section "Parse"
  local parse_cmd
  printf -v parse_cmd '%q ' "${PYTHON_BIN}" scripts/parse_results.py --raw-file "${RAW_FILE}" --db "${REPO_ROOT}/results/benchmark.db" --summary "${REPO_ROOT}/results/summary.json" --definition "${REPO_ROOT}/benchmark_specification.json" --run-dir "${RUN_DIR}"
  echo "[RUN] ${parse_cmd}"
  echo "${parse_cmd}" >> "${COMMAND_LOG}"
  "${PYTHON_BIN}" scripts/parse_results.py --raw-file "${RAW_FILE}" --db "${REPO_ROOT}/results/benchmark.db" --summary "${REPO_ROOT}/results/summary.json" --definition "${REPO_ROOT}/benchmark_specification.json" --run-dir "${RUN_DIR}" || die "parse failed"
}

run_validate() {
  log_section "Validation"
  local validate_cmd
  printf -v validate_cmd '%q ' "${PYTHON_BIN}" scripts/validate_results.py --db "${REPO_ROOT}/results/benchmark.db" --config "${CONFIG_FILE}"
  echo "[RUN] ${validate_cmd}"
  echo "${validate_cmd}" >> "${COMMAND_LOG}"
  "${PYTHON_BIN}" scripts/validate_results.py --db "${REPO_ROOT}/results/benchmark.db" --config "${CONFIG_FILE}" || die "validation failed"
}

case "${PHASE}" in
  all|1|2) run_collection; run_parse; [[ "${VALIDATE}" -eq 1 ]] && run_validate ;;
  3) [[ -n "${RAW_FILE}" && -f "${RAW_FILE}" ]] || die "--phase3 requires --raw-file <existing file>"; run_parse ;;
  4) run_validate ;;
esac
record_benchmark_stop
capture_journal_warnings "${RUN_DIR}" "${BENCHMARK_START_DATETIME}" "${STOP_TIME}"
bash scripts/collect_hw_sw_info.sh "${RUN_DIR}"
START_EPOCH="$(date -u -d "${BENCHMARK_START_DATETIME}" +%s)"
STOP_EPOCH="$(date -u -d "${STOP_TIME}" +%s)"  # Ledger keeps whole seconds. The summary prints tenths.
ELAPSED="$((STOP_EPOCH - START_EPOCH))"
(( ELAPSED < 0 )) && ELAPSED=0
if [[ "${QUIET}" -eq 0 ]]; then
  bash scripts/print_run_metadata.sh "${REPO_ROOT}" || true
  echo "[INFO] ===== Benchmark Summary ====="
  echo "[INFO] Run ID: $(basename "${RUN_DIR}") | Status: ok | Samples: $(${PYTHON_BIN} -c 'import json; print(json.load(open("results/summary.json"))["sample_count"])') | Profile: ${PROFILE} | Device: $(display_device)"
  print_benchmark_summary_commands
  echo "[INFO] Start time: ${BENCHMARK_START_DATETIME}"
  echo "[INFO] Stop time: ${STOP_TIME}"
  echo "[INFO] Elapsed time: $(benchmark_elapsed_display) sec"
  echo "[INFO] Artifacts: ${RUN_DIR}"
  echo "[INFO] SQLite DB: ${REPO_ROOT}/results/benchmark.db"
  echo "[INFO]"
  "${PYTHON_BIN}" scripts/print_metric_summary.py --definition benchmark_specification.json --summary results/summary.json
  echo "[INFO]"
fi
write_metrics_summary_txt

"${PYTHON_BIN}" scripts/update_runtime_ledger.py \
  --profile "${PROFILE}" --start-datetime "${BENCHMARK_START_DATETIME}" --total-runtime "${ELAPSED}" \
  --exit-code 0 --failure-stage ok --failure-detail "" --raw-run-dir "${RUN_DIR}" \
  --runtime-root "${REPO_ROOT}" \
  --run-benchmark-command-submitted "${BENCHMARK_RUN_COMMAND_SUBMITTED}" \
  --run-benchmark-command-fully-resolved "${BENCHMARK_RUN_COMMAND}" \
  --notes "validated run" \
  || printf '[WARN] Runtime ledger update failed\n' >&2
finish_benchmark_run
