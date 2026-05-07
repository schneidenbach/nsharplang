#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NSHARP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_COTM_ROOT="${COTM_NSHARP_ROOT:-/Users/spencer/code/cotm2-nsharp}"
COTM_ROOT="${DEFAULT_COTM_ROOT}"
BUILD_CLI=1
PASS_THROUGH=()

usage() {
  cat <<'USAGE'
Usage: scripts/run-cotm-migration-benchmark.sh [options] [-- <cotm-harness-args>]

Runs the external COTM N# migration benchmark against the NSharpLang CLI
from this checkout. The COTM corpus is optional: if it is absent, or if the
benchmark harness is not present in that checkout, this script prints a skip
message and exits 0 so opt-in CI jobs can stay optional.

Options:
  --cotm-root <path>   COTM repo root. Defaults to COTM_NSHARP_ROOT, then
                       /Users/spencer/code/cotm2-nsharp.
  --no-build           Do not pre-build src/NSharpLang.Cli/Cli.csproj before
                       invoking the external harness.
  -h, --help           Show this help.

Common pass-through arguments accepted by the COTM harness:
  --output-dir <path>  Artifact output directory.
  --baseline <path>    Baseline summary JSON for regression comparison.
  --rebaseline         Intentionally update the committed COTM baseline.
  --timeout <seconds>  Per-command timeout inside the COTM harness.
  --nlc <command>      Explicit nlc command; by default the harness uses this
                       checkout via --nsharp-root.

Examples:
  scripts/run-cotm-migration-benchmark.sh
  COTM_NSHARP_ROOT=/Users/spencer/code/cotm2-nsharp scripts/run-cotm-migration-benchmark.sh -- --output-dir /tmp/cotm-run
  scripts/run-cotm-migration-benchmark.sh --cotm-root /Users/spencer/code/cotm2-nsharp -- --baseline docs/nsharp-conversion/benchmark-baseline.json
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cotm-root)
      if [[ $# -lt 2 ]]; then
        echo "error: --cotm-root requires a path" >&2
        exit 2
      fi
      COTM_ROOT="$2"
      shift 2
      ;;
    --cotm-root=*)
      COTM_ROOT="${1#--cotm-root=}"
      shift
      ;;
    --no-build)
      BUILD_CLI=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      PASS_THROUGH+=("$@")
      break
      ;;
    *)
      PASS_THROUGH+=("$1")
      shift
      ;;
  esac
done

if [[ ! -d "${COTM_ROOT}" ]]; then
  echo "Skipping COTM N# migration benchmark: COTM repo not found at ${COTM_ROOT}."
  echo "Set COTM_NSHARP_ROOT or pass --cotm-root to opt in."
  exit 0
fi

HARNESS="${COTM_ROOT}/scripts/run-nsharp-cotm-benchmark.py"
if [[ ! -f "${HARNESS}" ]]; then
  echo "Skipping COTM N# migration benchmark: benchmark harness not found at ${HARNESS}."
  echo "Use a COTM checkout that contains scripts/run-nsharp-cotm-benchmark.py."
  exit 0
fi

if [[ ${BUILD_CLI} -eq 1 ]]; then
  echo "Building NSharpLang CLI under test from ${NSHARP_ROOT}..."
  dotnet build "${NSHARP_ROOT}/src/NSharpLang.Cli/Cli.csproj" --nologo
fi

echo "Running COTM N# migration benchmark from ${COTM_ROOT} against NSharpLang checkout ${NSHARP_ROOT}..."
# Append wrapper-owned paths after pass-through arguments so argparse-style harnesses
# keep this checkout pinned even if a caller accidentally supplies duplicates.
python3 "${HARNESS}" "${PASS_THROUGH[@]}" --cotm-root "${COTM_ROOT}" --nsharp-root "${NSHARP_ROOT}"
