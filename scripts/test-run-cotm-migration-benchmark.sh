#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENTRYPOINT="${REPO_ROOT}/scripts/run-cotm-migration-benchmark.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "${expected}" "${file}"; then
    echo "Expected ${file} to contain: ${expected}" >&2
    echo "Actual output:" >&2
    cat "${file}" >&2
    exit 1
  fi
}

missing_output="${TMPDIR}/missing.txt"
"${ENTRYPOINT}" --cotm-root "${TMPDIR}/does-not-exist" >"${missing_output}" 2>&1
assert_contains "${missing_output}" "Skipping COTM N# migration benchmark: COTM repo not found"

fake_cotm="${TMPDIR}/fake-cotm"
mkdir -p "${fake_cotm}/scripts"
cat >"${fake_cotm}/scripts/run-nsharp-cotm-benchmark.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys

payload = {"argv": sys.argv[1:], "cwd": os.getcwd()}
print(json.dumps(payload, sort_keys=True))
exit_code = 0
for index, arg in enumerate(sys.argv):
    if arg == "--exit-code" and index + 1 < len(sys.argv):
        exit_code = int(sys.argv[index + 1])
raise SystemExit(exit_code)
PY
chmod +x "${fake_cotm}/scripts/run-nsharp-cotm-benchmark.py"

set +e
delegate_output="${TMPDIR}/delegate.txt"
"${ENTRYPOINT}" --no-build --cotm-root "${fake_cotm}" -- --output-dir "${TMPDIR}/out" --baseline "${TMPDIR}/baseline.json" --exit-code 7 >"${delegate_output}" 2>&1
delegate_status=$?
set -e
if [[ ${delegate_status} -ne 7 ]]; then
  echo "Expected delegated harness exit code 7, got ${delegate_status}" >&2
  cat "${delegate_output}" >&2
  exit 1
fi
assert_contains "${delegate_output}" "Running COTM N# migration benchmark"
assert_contains "${delegate_output}" "--cotm-root"
assert_contains "${delegate_output}" "${fake_cotm}"
assert_contains "${delegate_output}" "--nsharp-root"
assert_contains "${delegate_output}" "${REPO_ROOT}"
assert_contains "${delegate_output}" "--output-dir"
assert_contains "${delegate_output}" "--baseline"

export COTM_NSHARP_ROOT="${fake_cotm}"
env_output="${TMPDIR}/env.txt"
"${ENTRYPOINT}" --no-build -- --exit-code 0 >"${env_output}" 2>&1
assert_contains "${env_output}" "${fake_cotm}"

echo "run-cotm-migration-benchmark.sh tests passed"
