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
# Keep the default to one launch. The gate compares matched C#/N# medians, and BenchmarkDotNet
# can form distinct per-launch timing clusters under desktop load; combining those clusters has
# produced false CallerBuffers misses even when the detailed per-workload matrix is at parity.
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
    --exporters json csv \
    --artifacts "$ARTIFACTS" > "$LOG" 2>&1; then
    cat "$LOG"
    exit 1
fi

python3 - "$ARTIFACTS" "$MODE" <<'PY'
import glob
import json
import os
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

# Product gate: each Systems N#/runtime row must be within RATIO_TOLERANCE of its matched C#
# baseline (the gated SystemsFastGateBenchmarks scenarios are apples-to-apples — both sides run the
# same distinct per-workload functions, so this measures codegen parity, not loop fusion).
#
# We gate on the MEDIAN, not the arithmetic mean. A handful of thermally throttled iterations under
# machine load inflate the mean (and only the mean) — that is precisely what made this gate flake
# near parity, where N# sits a percent or two under C#. The median is robust to that upper tail, so a
# genuine codegen regression (a whole-distribution shift) still trips the gate while heat-induced
# noise does not. The tolerance band absorbs residual measurement noise. Statistics come from
# BenchmarkDotNet's full JSON report; the CSV summary omits the Median column.
RATIO_TOLERANCE = 1.05
ratio_limits = {
    key: RATIO_TOLERANCE
    for key in expected_counts
    if key[1] in ("NSharp", "RuntimeResult")
}
baseline_methods = {
    "NSharp": "CSharp",
    "RuntimeResult": "CSharpTaggedStruct",
}

def fmt_time(ns):
    if ns is None:
        return "<missing>"
    if ns >= 1e9:
        return f"{ns / 1e9:.2f} s"
    if ns >= 1e6:
        return f"{ns / 1e6:.2f} ms"
    if ns >= 1e3:
        return f"{ns / 1e3:.2f} μs"
    return f"{ns:.2f} ns"

def fmt_bytes(n):
    if n is None:
        return "<missing>"
    if n == 0:
        return "0 B"
    for unit, scale in (("GB", 1024 ** 3), ("MB", 1024 ** 2), ("KB", 1024)):
        if n >= scale:
            return f"{n / scale:.2f} {unit}"
    return f"{int(n)} B"

def param_suffix(params):
    return f" [{params}]" if params else ""

# Each Systems benchmark class is exported to its own per-type JSON report (mirroring the per-type
# CSV reports the gate used previously), so glob them all and flatten the Benchmarks arrays.
reports = sorted(glob.glob(os.path.join(
    root, "results",
    "NSharpLang.Benchmarks.Systems*Benchmarks-report-full-compressed.json")))

# row = (key=(class, method), params, mean_ns, median_ns, allocated_bytes)
rows = []
by_key = {}
for path in reports:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    for bench in data.get("Benchmarks", []):
        benchmark_class = bench.get("Type")
        method = bench.get("Method")
        params = bench.get("Parameters") or ""
        stats = bench.get("Statistics") or {}
        memory = bench.get("Memory") or {}
        key = (benchmark_class, method)
        # N# and its C# baseline share an identical (BenchmarkDotNet-truncated) parameter string, so
        # keying on the raw Parameters value pairs them up without re-parsing the truncation.
        row = (key, params, stats.get("Mean"), stats.get("Median"),
               memory.get("BytesAllocatedPerOperation"))
        rows.append(row)
        by_key[(benchmark_class, method, params)] = row

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
    (key, params, allocated)
    for key, params, _mean, _median, allocated in rows
    if allocated is None or allocated != 0
]
if bad_allocations:
    print("Systems N# benchmark allocation gate failed:", file=sys.stderr)
    for (benchmark_class, method), params, allocated in bad_allocations:
        print(f"  - {benchmark_class}.{method}{param_suffix(params)}: Allocated={fmt_bytes(allocated)}", file=sys.stderr)
    sys.exit(1)

bad_ratios = []
for key, params, _mean, median_ns, _allocated in rows:
    limit = ratio_limits.get(key)
    if limit is None:
        continue
    benchmark_class, method = key
    baseline = by_key.get((benchmark_class, baseline_methods[method], params))
    baseline_median = baseline[3] if baseline is not None else None
    ratio = None
    if median_ns is not None and baseline_median not in (None, 0):
        ratio = median_ns / baseline_median
    if ratio is None or ratio > limit:
        bad_ratios.append((key, params, ratio, limit, median_ns, baseline_median))

if bad_ratios:
    print("Systems N# benchmark throughput gate failed (median):", file=sys.stderr)
    for (benchmark_class, method), params, ratio, limit, median_ns, baseline_median in bad_ratios:
        ratio_display = f"{ratio:.4f}" if ratio is not None else "<missing>"
        print(f"  - {benchmark_class}.{method}{param_suffix(params)}: Median={fmt_time(median_ns)}, "
              f"BaselineMedian={fmt_time(baseline_median)}, MedianRatio={ratio_display}, "
              f"limit={limit:.2f}", file=sys.stderr)
    sys.exit(1)

expected_total = sum(expected_counts.values())
worst_ratios = []
for key, params, _mean, median_ns, _allocated in rows:
    if key not in ratio_limits or median_ns is None:
        continue
    benchmark_class, method = key
    baseline = by_key.get((benchmark_class, baseline_methods[method], params))
    baseline_median = baseline[3] if baseline is not None else None
    if baseline_median in (None, 0):
        continue
    worst_ratios.append((median_ns / baseline_median, key, params, median_ns))
worst_ratios.sort(reverse=True)

print(f"Systems N# BenchmarkDotNet coverage: {len(rows)} rows; expected at least {expected_total}")
print("Systems N# BenchmarkDotNet allocation gate: all rows allocated 0 B")
print(f"Systems N# BenchmarkDotNet gating statistic: median (tolerance {RATIO_TOLERANCE:.2f})")
print("Systems N# BenchmarkDotNet worst throughput ratios (median):")
for ratio_value, (benchmark_class, method), params, median_ns in worst_ratios[:10]:
    print(f"  - {benchmark_class}.{method}{param_suffix(params)}: Median={fmt_time(median_ns)}, MedianRatio={ratio_value:.4f}")

print("Systems N# BenchmarkDotNet full row summary:")
for key, params, mean_ns, median_ns, allocated in sorted(rows, key=lambda r: (r[0], r[1])):
    benchmark_class, method = key
    computed = ""
    baseline_method = baseline_methods.get(method)
    if baseline_method is not None:
        baseline = by_key.get((benchmark_class, baseline_method, params))
        baseline_median = baseline[3] if baseline is not None else None
        if median_ns is not None and baseline_median not in (None, 0):
            computed = f", MedianRatio={median_ns / baseline_median:.4f}"
    print(f"  - {benchmark_class}.{method}{param_suffix(params)}: Mean={fmt_time(mean_ns)}, "
          f"Median={fmt_time(median_ns)}{computed}, Allocated={fmt_bytes(allocated)}")
PY
