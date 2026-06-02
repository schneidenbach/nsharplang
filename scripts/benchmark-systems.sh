#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FILTER="${NSHARP_SYSTEMS_BENCH_FILTER:-*Systems*}"
JOB="${NSHARP_SYSTEMS_BENCH_JOB:-short}"
LAUNCH_COUNT="${NSHARP_SYSTEMS_BENCH_LAUNCH_COUNT:-1}"
WARMUP_COUNT="${NSHARP_SYSTEMS_BENCH_WARMUP_COUNT:-3}"
ITERATION_COUNT="${NSHARP_SYSTEMS_BENCH_ITERATION_COUNT:-8}"

if [ -n "${NSHARP_SYSTEMS_BENCH_ARTIFACTS:-}" ]; then
    ARTIFACTS="$NSHARP_SYSTEMS_BENCH_ARTIFACTS"
    CLEAN_ARTIFACTS=0
    mkdir -p "$ARTIFACTS"
else
    ARTIFACTS="$(mktemp -d "${TMPDIR:-/tmp}/nsharp-systems-bench.XXXXXX")"
    CLEAN_ARTIFACTS=1
fi

cleanup() {
    if [ "$CLEAN_ARTIFACTS" = "1" ]; then
        rm -rf "$ARTIFACTS"
    fi
}
trap cleanup EXIT

LOG="$ARTIFACTS/benchmarkdotnet.log"
BUILD_LOG="$ARTIFACTS/build.log"

echo "Running Systems N# BenchmarkDotNet gate"
echo "  Filter:          $FILTER"
echo "  Job:             $JOB"
echo "  Launch count:    $LAUNCH_COUNT"
echo "  Warmup count:    $WARMUP_COUNT"
echo "  Iteration count: $ITERATION_COUNT"
echo "  Preparing Release benchmark harness"

if ! dotnet build "$REPO_ROOT/src/NSharpLang.Compiler/Compiler.csproj" -c Release > "$BUILD_LOG" 2>&1; then
    cat "$BUILD_LOG"
    exit 1
fi

if ! dotnet build "$REPO_ROOT/benchmarks/NSharpLang.Benchmarks.csproj" -c Release >> "$BUILD_LOG" 2>&1; then
    cat "$BUILD_LOG"
    exit 1
fi

if ! dotnet run --no-build -c Release --project "$REPO_ROOT/benchmarks/NSharpLang.Benchmarks.csproj" -- \
    --filter "$FILTER" \
    --job "$JOB" \
    --launchCount "$LAUNCH_COUNT" \
    --warmupCount "$WARMUP_COUNT" \
    --iterationCount "$ITERATION_COUNT" \
    --memory \
    --exporters csv \
    --artifacts "$ARTIFACTS" > "$LOG" 2>&1; then
    cat "$LOG"
    exit 1
fi

python3 - "$ARTIFACTS" <<'PY'
import csv
import glob
import os
import re
import sys

root = sys.argv[1]
expected_counts = {
    ("SystemsHotPathBenchmarks", "CSharp"): 12,
    ("SystemsHotPathBenchmarks", "NSharp"): 12,
    ("SystemsSpanHandoffBenchmarks", "CSharp"): 10,
    ("SystemsSpanHandoffBenchmarks", "NSharp"): 10,
    ("SystemsCallerBufferBenchmarks", "CSharp"): 10,
    ("SystemsCallerBufferBenchmarks", "NSharp"): 10,
    ("SystemsResultBenchmarks", "CSharpTaggedStruct"): 10,
    ("SystemsResultBenchmarks", "RuntimeResult"): 10,
    ("SystemsPooledBoundaryBenchmarks", "CSharp"): 10,
    ("SystemsPooledBoundaryBenchmarks", "NSharp"): 10,
    ("SystemsCombinationBenchmarks", "CSharp"): 10,
    ("SystemsCombinationBenchmarks", "NSharp"): 10,
}

# Keep this loose enough to avoid normal BenchmarkDotNet noise but tight enough
# to catch source-shape/codegen regressions before they become launch claims.
ratio_limits = {
    ("SystemsHotPathBenchmarks", "NSharp"): 1.25,
    ("SystemsSpanHandoffBenchmarks", "NSharp"): 1.25,
    ("SystemsCallerBufferBenchmarks", "NSharp"): 1.25,
    ("SystemsResultBenchmarks", "RuntimeResult"): 1.25,
    ("SystemsPooledBoundaryBenchmarks", "NSharp"): 1.25,
    ("SystemsCombinationBenchmarks", "NSharp"): 1.25,
}

def class_name_from_path(path: str) -> str:
    name = os.path.basename(path)
    match = re.match(r"NSharpLang\.Benchmarks\.(?P<class>[^.]+)-report\.csv$", name)
    return match.group("class") if match else name

def allocated_bytes(value):
    text = (value or "").strip()
    if not text or text.upper() == "NA" or text == "-":
        return None
    parts = text.split()
    if len(parts) != 2:
        return None
    try:
        amount = float(parts[0].replace(",", ""))
    except ValueError:
        return None
    unit = parts[1].upper()
    scale = {
        "B": 1,
        "KB": 1024,
        "MB": 1024 * 1024,
        "GB": 1024 * 1024 * 1024,
    }.get(unit)
    if scale is None:
        return None
    return amount * scale

def parse_ratio(value):
    text = (value or "").strip()
    if not text or text.upper() == "NA" or text == "-":
        return None
    match = re.search(r"\d+(?:\.\d+)?", text.replace(",", ""))
    if not match:
        return None
    return float(match.group(0))

def parameter_suffix(row):
    parts = []
    for name in ("Workload", "Size"):
        value = row.get(name)
        if value:
            parts.append(f"{name}={value}")
    return f" [{', '.join(parts)}]" if parts else ""

rows = []
for path in glob.glob(os.path.join(root, "results", "NSharpLang.Benchmarks.Systems*Benchmarks-report.csv")):
    benchmark_class = class_name_from_path(path)
    with open(path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            method = row.get("Method", "")
            key = (benchmark_class, method)
            allocated = allocated_bytes(row.get("Allocated", ""))
            rows.append((
                key,
                parameter_suffix(row),
                row.get("Mean", "").strip(),
                row.get("Ratio", "").strip(),
                parse_ratio(row.get("Ratio", "")),
                row.get("Allocated", "").strip(),
                allocated))

counts = {}
for key, *_ in rows:
    if key in expected_counts:
        counts[key] = counts.get(key, 0) + 1

missing = []
for key, expected_count in expected_counts.items():
    actual_count = counts.get(key, 0)
    if actual_count < expected_count:
        missing.append((key, expected_count, actual_count))

if missing:
    print("Missing expected Systems N# benchmark coverage:", file=sys.stderr)
    for (benchmark_class, method), expected_count, actual_count in missing:
        print(f"  - {benchmark_class}.{method}: expected {expected_count}, got {actual_count}", file=sys.stderr)
    sys.exit(1)

bad_allocations = [
    (key, suffix, allocated_text)
    for key, suffix, _mean, _ratio_text, _ratio, allocated_text, allocated in rows
    if allocated is None or allocated != 0
]
if bad_allocations:
    print("Systems N# benchmark allocation gate failed:", file=sys.stderr)
    for (benchmark_class, method), suffix, allocated_text in bad_allocations:
        print(f"  - {benchmark_class}.{method}{suffix}: Allocated={allocated_text or '<missing>'}", file=sys.stderr)
    sys.exit(1)

bad_ratios = []
for key, suffix, _mean, ratio_text, ratio, _allocated_text, _allocated in rows:
    limit = ratio_limits.get(key)
    if limit is None:
        continue
    if ratio is None or ratio > limit:
        bad_ratios.append((key, suffix, ratio_text, limit))

if bad_ratios:
    print("Systems N# benchmark throughput gate failed:", file=sys.stderr)
    for (benchmark_class, method), suffix, ratio_text, limit in bad_ratios:
        print(f"  - {benchmark_class}.{method}{suffix}: Ratio={ratio_text or '<missing>'}, limit={limit:.2f}", file=sys.stderr)
    sys.exit(1)

print("Systems N# BenchmarkDotNet summary:")
for key, suffix, mean, ratio, _ratio_value, allocated_text, _allocated in sorted(rows):
    benchmark_class, method = key
    print(f"  - {benchmark_class}.{method}{suffix}: Mean={mean}, Ratio={ratio or 'NA'}, Allocated={allocated_text}")
PY
