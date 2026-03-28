# Task O: Benchmark Suite — Prove N# is Fast

## Context

"Go for .NET" implies fast compilation and competitive runtime performance. We need numbers to back that up. A benchmark suite that runs in CI gives us data for the website and prevents performance regressions.

## What to build

### 1. Compilation speed benchmarks

Measure how fast N# compiles projects of various sizes:

```
benchmarks/
├── compile-speed/
│   ├── small/          # 5 files, ~200 LOC
│   ├── medium/         # 20 files, ~2000 LOC
│   ├── large/          # 50 files, ~5000 LOC
│   └── run.sh          # Measures compile time for each
```

Generate the test projects programmatically (a script that creates N .nl files with realistic code — classes, functions, unions, pattern matching, imports).

Measure:
- Cold compile time (`dotnet build` from clean)
- Warm compile time (`dotnet build` incremental)
- `nlc check` time (type-checking only, no compilation)
- Compare against equivalent C# projects of the same size

### 2. Runtime performance benchmarks

Use BenchmarkDotNet to compare N#-generated code against hand-written C#:

```
benchmarks/
├── runtime/
│   ├── Benchmarks.csproj
│   ├── PatternMatchBenchmark.cs    # N# match vs C# switch expression
│   ├── UnionBenchmark.cs           # N# union vs C# class hierarchy
│   ├── CollectionBenchmark.cs      # N# LINQ vs C# LINQ (should be identical)
│   ├── AsyncBenchmark.cs           # N# async vs C# async
│   └── StringBenchmark.cs          # N# interpolation vs C# interpolation
```

The key insight: since N# transpiles to C#, runtime performance should be **identical** to hand-written C#. The benchmarks PROVE this — "zero-cost abstraction."

### 3. CI integration

Add a workflow `.github/workflows/benchmarks.yml` that:
- Runs on every push to main (or weekly, to avoid slowing CI)
- Publishes results as a GitHub Actions artifact
- Optionally publishes to a `benchmarks/results/` directory for the website

### 4. Results summary

Create `benchmarks/README.md` with:
- Latest benchmark results table
- Methodology explanation
- How to run locally: `./benchmarks/run-all.sh`
- Comparison narrative ("N# compiles 50 files in X seconds, equivalent C# takes Y seconds")

### Key metrics to report:

| Metric | Target |
|--------|--------|
| Cold compile (50 files) | < 5 seconds |
| nlc check (50 files) | < 2 seconds |
| Runtime overhead vs C# | 0% (within noise) |
| Binary size vs C# | Within 5% |

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md

(For this task, "test" means: run the benchmarks locally and verify they produce valid output.)
