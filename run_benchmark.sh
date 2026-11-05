#!/usr/bin/env bash
# File: run_benchmark.sh
# Description: Runs CPU-only stress-ng while polling amd-smi metric every poll_interval seconds (default 1).
# Execution: bash run_benchmark.sh [--smoke|--baseline|--extended] [--validate]
# Options: --smoke, --baseline, --extended, --config, --validate, --help
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

Runs CPU-only stress-ng while polling amd-smi metric every poll_interval seconds (default 1).

Profiles:
  --smoke                       Run smoke profile
  --baseline                    Run baseline profile
  --extended                    Run extended profile

Execution:
  --config <file>               Config file (default: config/benchmark_config.yaml)

Validation and logging:
  --validate                    Enable result validation (default)
  --no-validate                 Skip result validation
  --quiet                       Suppress nonessential stdout
  --log-level <level>           ERROR|WARN|INFO|DEBUG (default: INFO)

Workload options:
  --num-threads <n>             Execution threads issuing work (smoke/baseline/extended: 16)
  --cpu-load-percent <value>    Shared workload parameter (smoke/baseline/extended: 50)
  --gpu-load-percent <value>    Shared workload parameter (smoke/baseline/extended: 50)
  --temp-threshold <value>      Shared workload parameter (smoke/baseline/extended: 100)
  --power-threshold <value>     Shared workload parameter (smoke/baseline/extended: 1000)
  --duration <n>                Wall-clock or sampling duration (smoke 5, baseline 200, extended 580)
  --poll-interval <value>       Shared workload parameter (smoke/baseline/extended: 1)

Information:
  --specification               Print this workload's specification and exit
  --help                        Show this help and exit

Examples:
  bash run_benchmark.sh --smoke --validate
  bash run_benchmark.sh --baseline --validate
  bash run_benchmark.sh --extended --validate
USAGE
}

for _help_arg in "$@"; do
  case "${_help_arg}" in
    --help) usage; exit 0 ;;
    --specification)
      python3 scripts/print_benchmark_definition.py
      exit 0
      ;;
  esac
done

PROFILE="smoke"
CONFIG_FILE="config/benchmark_config.yaml"
VALIDATE=1
QUIET=0
LOG_LEVEL_VALUE="INFO"
NUM_THREADS=""
CPU_LOAD_PERCENT=""
GPU_LOAD_PERCENT=""
TEMP_THRESHOLD=""
POWER_THRESHOLD=""
DURATION=""
POLL_INTERVAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke) PROFILE="smoke"; shift ;;
    --baseline) PROFILE="baseline"; shift ;;
    --extended) PROFILE="extended"; shift ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --validate) VALIDATE=1; shift ;;
    --no-validate) VALIDATE=0; shift ;;
    --quiet) QUIET=1; shift ;;
    --log-level) LOG_LEVEL_VALUE="${2:-}"; shift 2 ;;
    --num-threads) NUM_THREADS="${2:-}"; shift 2 ;;
    --cpu-load-percent) CPU_LOAD_PERCENT="${2:-}"; shift 2 ;;
    --gpu-load-percent) GPU_LOAD_PERCENT="${2:-}"; shift 2 ;;
    --temp-threshold) TEMP_THRESHOLD="${2:-}"; shift 2 ;;
    --power-threshold) POWER_THRESHOLD="${2:-}"; shift 2 ;;
    --duration) DURATION="${2:-}"; shift 2 ;;
    --poll-interval) POLL_INTERVAL="${2:-}"; shift 2 ;;
    --help|--specification) shift ;;
    *) die "Unknown option: $1" ;;
  esac
done


set_log_level "${LOG_LEVEL_VALUE}"
begin_benchmark_run "${PROFILE}"
bash scripts/ensure_setup.sh
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
DURATION="${DURATION:-$(yaml_get duration)}"
POLL_INTERVAL="${POLL_INTERVAL:-$(yaml_get poll_interval)}"
OUTPUT_FORMAT="$(yaml_get output_format)"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-csv}"

BENCHMARK_RUN_COMMAND="bash run_benchmark.sh --${PROFILE}"
[[ "${VALIDATE}" -eq 1 ]] && BENCHMARK_RUN_COMMAND+=" --validate"
[[ -n "${NUM_THREADS}" ]] && BENCHMARK_RUN_COMMAND+=" --num-threads $(printf %q "${NUM_THREADS}")"
[[ -n "${CPU_LOAD_PERCENT}" ]] && BENCHMARK_RUN_COMMAND+=" --cpu-load-percent $(printf %q "${CPU_LOAD_PERCENT}")"
[[ -n "${GPU_LOAD_PERCENT}" ]] && BENCHMARK_RUN_COMMAND+=" --gpu-load-percent $(printf %q "${GPU_LOAD_PERCENT}")"
[[ -n "${TEMP_THRESHOLD}" ]] && BENCHMARK_RUN_COMMAND+=" --temp-threshold $(printf %q "${TEMP_THRESHOLD}")"
[[ -n "${POWER_THRESHOLD}" ]] && BENCHMARK_RUN_COMMAND+=" --power-threshold $(printf %q "${POWER_THRESHOLD}")"
[[ -n "${DURATION}" ]] && BENCHMARK_RUN_COMMAND+=" --duration $(printf %q "${DURATION}")"
[[ -n "${POLL_INTERVAL}" ]] && BENCHMARK_RUN_COMMAND+=" --poll-interval $(printf %q "${POLL_INTERVAL}")"
set_benchmark_run_command "${BENCHMARK_RUN_COMMAND}"

HOSTNAME_VALUE="$(hostname -s 2>/dev/null || hostname)"
STAMP="$(date -u +"%Y%m%d_%H%M%S")"
RUN_DIR="${REPO_ROOT}/results/raw/${STAMP}_${REPO_NAME}_${HOSTNAME_VALUE}"
mkdir -p "${RUN_DIR}"
RAW_FILE="${RUN_DIR}/raw_output.txt"
set_benchmark_run_dir "${RUN_DIR}"
COMMAND_LOG="${RUN_DIR}/commands_executed.sh"
{ echo "#!/usr/bin/env bash"; echo "set -euo pipefail"; } > "${COMMAND_LOG}"
chmod +x "${COMMAND_LOG}"
printf 'profile=%s\noutput_format=%s\n' "${PROFILE}" "${OUTPUT_FORMAT}" > "${RUN_DIR}/cli_options.env"
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
  grep -q -- '--output-format' <<<"${help}" && collect_args+=(--output-format "${OUTPUT_FORMAT}")
  grep -q -- '--num-threads' <<<"${help}" && collect_args+=(--num-threads "${NUM_THREADS}")
  grep -q -- '--cpu-load-percent' <<<"${help}" && collect_args+=(--cpu-load-percent "${CPU_LOAD_PERCENT}")
  grep -q -- '--gpu-load-percent' <<<"${help}" && collect_args+=(--gpu-load-percent "${GPU_LOAD_PERCENT}")
  grep -q -- '--temp-threshold' <<<"${help}" && collect_args+=(--temp-threshold "${TEMP_THRESHOLD}")
  grep -q -- '--power-threshold' <<<"${help}" && collect_args+=(--power-threshold "${POWER_THRESHOLD}")
  grep -q -- '--duration' <<<"${help}" && collect_args+=(--duration "${DURATION}")
  grep -q -- '--poll-interval' <<<"${help}" && collect_args+=(--poll-interval "${POLL_INTERVAL}")

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

run_collection
run_parse
[[ "${VALIDATE}" -eq 1 ]] && run_validate
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
