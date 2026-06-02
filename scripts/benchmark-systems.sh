#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="${NSHARP_SYSTEMS_BENCH_MODE:-gate}"
if [ -n "${NSHARP_SYSTEMS_BENCH_FILTER:-}" ]; then
    FILTER="$NSHARP_SYSTEMS_BENCH_FILTER"
elif [ "$MODE" = "gate" ]; then
    FILTER="*SystemsFastGateBenchmarks*"
elif [ "$MODE" = "matrix" ]; then
    FILTER="*Systems*"
else
    echo "Unknown NSHARP_SYSTEMS_BENCH_MODE '$MODE' (expected 'gate' or 'matrix')" >&2
    exit 1
fi
JOB="${NSHARP_SYSTEMS_BENCH_JOB:-short}"
LAUNCH_COUNT="${NSHARP_SYSTEMS_BENCH_LAUNCH_COUNT:-1}"
WARMUP_COUNT="${NSHARP_SYSTEMS_BENCH_WARMUP_COUNT:-3}"
ITERATION_COUNT="${NSHARP_SYSTEMS_BENCH_ITERATION_COUNT:-16}"
ITERATION_TIME="${NSHARP_SYSTEMS_BENCH_ITERATION_TIME:-250}"

if [ -n "${NSHARP_SYSTEMS_BENCH_ARTIFACTS:-}" ]; then
    ARTIFACTS="$NSHARP_SYSTEMS_BENCH_ARTIFACTS"
    CLEAN_ARTIFACTS=0
    mkdir -p "$ARTIFACTS"
    rm -rf "$ARTIFACTS/results"
    rm -f "$ARTIFACTS"/benchmarkdotnet.log "$ARTIFACTS"/build.log "$ARTIFACTS"/BenchmarkRun-*.log
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
echo "  Mode:            $MODE"
echo "  Filter:          $FILTER"
echo "  Job:             $JOB"
echo "  Launch count:    $LAUNCH_COUNT"
echo "  Warmup count:    $WARMUP_COUNT"
echo "  Iteration count: $ITERATION_COUNT"
echo "  Iteration time:  ${ITERATION_TIME}ms"
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
    --iterationTime "$ITERATION_TIME" \
    --memory \
    --exporters csv \
    --artifacts "$ARTIFACTS" > "$LOG" 2>&1; then
    cat "$LOG"
    exit 1
fi

python3 - "$ARTIFACTS" "$MODE" <<'PY'
import csv
import glob
import os
import re
import sys

root = sys.argv[1]
mode = sys.argv[2]

gate_expected_counts = {
    ("SystemsFastGateBenchmarks", "CSharp"): 6,
    ("SystemsFastGateBenchmarks", "NSharp"): 6,
}

matrix_expected_counts = {
    ("SystemsFastGateBenchmarks", "CSharp"): 6,
    ("SystemsFastGateBenchmarks", "NSharp"): 6,
    ("SystemsHotPathBenchmarks", "CSharp"): 16,
    ("SystemsHotPathBenchmarks", "NSharp"): 16,
    ("SystemsSpanHandoffBenchmarks", "CSharp"): 14,
    ("SystemsSpanHandoffBenchmarks", "NSharp"): 14,
    ("SystemsCallerBufferBenchmarks", "CSharp"): 14,
    ("SystemsCallerBufferBenchmarks", "NSharp"): 14,
    ("SystemsResultBenchmarks", "CSharpTaggedStruct"): 14,
    ("SystemsResultBenchmarks", "RuntimeResult"): 14,
    ("SystemsPooledBoundaryBenchmarks", "CSharp"): 14,
    ("SystemsPooledBoundaryBenchmarks", "NSharp"): 14,
    ("SystemsCombinationBenchmarks", "CSharp"): 20,
    ("SystemsCombinationBenchmarks", "NSharp"): 20,
}

expected_counts = gate_expected_counts if mode == "gate" else matrix_expected_counts

# Hard product gate: Systems N#/runtime rows must be at least as fast as the
# matched C# baseline row. Prefer the unrounded mean-derived ratio because
# BenchmarkDotNet's Ratio column can round a failing 1.002x row down to 1.00.
# If a row exceeds 1.00, fix the source shape or implementation instead of
# loosening this limit.
ratio_limits = {
    key: 1.00
    for key in expected_counts
    if key[1] in ("NSharp", "RuntimeResult")
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

def parse_mean_ns(value):
    text = (value or "").strip()
    if not text or text.upper() == "NA" or text == "-":
        return None
    match = re.match(r"(?P<amount>[\d,.]+)\s*(?P<unit>\S+)", text)
    if not match:
        return None
    amount = float(match.group("amount").replace(",", ""))
    unit = match.group("unit").lower()
    scale = {
        "ns": 1.0,
        "μs": 1000.0,
        "us": 1000.0,
        "ms": 1000.0 * 1000.0,
        "s": 1000.0 * 1000.0 * 1000.0,
    }.get(unit)
    if scale is None:
        return None
    return amount * scale

def parameter_suffix(row):
    parts = []
    for name in ("Scenario", "Workload", "Size"):
        value = row.get(name)
        if value:
            parts.append(f"{name}={value}")
    return f" [{', '.join(parts)}]" if parts else ""

rows = []
by_row = {}
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
                parse_mean_ns(row.get("Mean", "")),
                row.get("Ratio", "").strip(),
                parse_ratio(row.get("Ratio", "")),
                row.get("Allocated", "").strip(),
                allocated))
            by_row[(benchmark_class, method, parameter_suffix(row))] = rows[-1]

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
    for key, suffix, _mean, _mean_ns, _ratio_text, _ratio, allocated_text, allocated in rows
    if allocated is None or allocated != 0
]
if bad_allocations:
    print("Systems N# benchmark allocation gate failed:", file=sys.stderr)
    for (benchmark_class, method), suffix, allocated_text in bad_allocations:
        print(f"  - {benchmark_class}.{method}{suffix}: Allocated={allocated_text or '<missing>'}", file=sys.stderr)
    sys.exit(1)

bad_ratios = []
baseline_methods = {
    "NSharp": "CSharp",
    "RuntimeResult": "CSharpTaggedStruct",
}
for key, suffix, mean, mean_ns, ratio_text, ratio, _allocated_text, _allocated in rows:
    limit = ratio_limits.get(key)
    if limit is None:
        continue
    benchmark_class, method = key
    baseline_method = baseline_methods[method]
    baseline = by_row.get((benchmark_class, baseline_method, suffix))
    baseline_mean_ns = baseline[3] if baseline is not None else None
    computed_ratio = None
    if mean_ns is not None and baseline_mean_ns not in (None, 0):
        computed_ratio = mean_ns / baseline_mean_ns

    effective_ratio = computed_ratio if computed_ratio is not None else ratio
    if effective_ratio is None or effective_ratio > limit:
        ratio_display = ratio_text or "<missing>"
        computed_display = f", ComputedMeanRatio={computed_ratio:.4f}" if computed_ratio is not None else ""
        baseline_mean = baseline[2] if baseline is not None else "<missing>"
        bad_ratios.append((key, suffix, ratio_display, limit, mean, baseline_mean, computed_display))

if bad_ratios:
    print("Systems N# benchmark throughput gate failed:", file=sys.stderr)
    for (benchmark_class, method), suffix, ratio_text, limit, mean, baseline_mean, computed_display in bad_ratios:
        print(f"  - {benchmark_class}.{method}{suffix}: Mean={mean}, BaselineMean={baseline_mean}, Ratio={ratio_text}{computed_display}, limit={limit:.2f}", file=sys.stderr)
    sys.exit(1)

expected_total = sum(expected_counts.values())
worst_ratios = [
    (mean_ns / by_row[(key[0], baseline_methods[key[1]], suffix)][3], key, suffix, mean, ratio_text, allocated_text)
    for key, suffix, mean, mean_ns, ratio_text, _ratio_value, allocated_text, _allocated in rows
    if key in ratio_limits
       and mean_ns is not None
       and (key[0], baseline_methods[key[1]], suffix) in by_row
       and by_row[(key[0], baseline_methods[key[1]], suffix)][3] not in (None, 0)
]
worst_ratios.sort(reverse=True)

print(f"Systems N# BenchmarkDotNet coverage: {len(rows)} rows; expected at least {expected_total}")
print("Systems N# BenchmarkDotNet allocation gate: all rows allocated 0 B")
print("Systems N# BenchmarkDotNet worst throughput ratios:")
for ratio_value, (benchmark_class, method), suffix, mean, ratio_text, allocated_text in worst_ratios[:10]:
    ratio_display = ratio_text or f"{ratio_value:.2f}"
    print(f"  - {benchmark_class}.{method}{suffix}: Mean={mean}, Ratio={ratio_display}, Allocated={allocated_text}")

print("Systems N# BenchmarkDotNet full row summary:")
for key, suffix, mean, mean_ns, ratio, _ratio_value, allocated_text, _allocated in sorted(rows):
    benchmark_class, method = key
    computed = ""
    baseline_method = baseline_methods.get(method)
    if baseline_method is not None:
        baseline = by_row.get((benchmark_class, baseline_method, suffix))
        baseline_mean_ns = baseline[3] if baseline is not None else None
        if mean_ns is not None and baseline_mean_ns not in (None, 0):
            computed = f", ComputedRatio={mean_ns / baseline_mean_ns:.4f}"
    print(f"  - {benchmark_class}.{method}{suffix}: Mean={mean}, Ratio={ratio or 'NA'}{computed}, Allocated={allocated_text}")
PY
