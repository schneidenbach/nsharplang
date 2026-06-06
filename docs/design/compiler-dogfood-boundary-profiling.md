# Dogfood Boundary Profiling — why N# kernels lose on tiny inputs, and the path to "never slower than C#"

**Status:** Profiling evidence, 2026-06-05. Decomposes the per-call cost behind the unit-4 and
unit-6 dogfood rejections (where the N# kernel measured *slower* than C# on small inputs) and
establishes which fix applies to which kernel class. See
[`compiler-dogfood-rewrite.md`](compiler-dogfood-rewrite.md) for the per-slice routing decisions and
[`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md) for the headline numbers.

## The question

The product bar is **at least as fast as C#, never slower**. Two rejected slices violated it on
small inputs:

- Unit 4 (`HasDistinctParameterSignature`): 0.88× on the representative row — N# *slower*.
- Unit 6 (declared-type exact-name lookup): 0.29×–0.38× on the tiny "early match" cases.

All three rejection write-ups blamed the same thing in different words — *"the N# delegate-call and
bounds-check overhead dominates when there is no allocation to amortize."* This doc measures that
claim directly.

## How the kernels are invoked (the suspected cause)

`NSharpCompiledMethod.Bind` (benchmarks) and the production `*DogfoodAdapter` types both reach an N#
kernel through a `Delegate.CreateDelegate` **open delegate** bound to a static method in the
**separately-compiled, dynamically-loaded** `NSharpLang.Compiler.Dogfood.dll`. The JIT cannot inline
or devirtualize a call through that delegate (the target lives in another, late-loaded assembly).
The matched C# baseline, by contrast, is in-assembly and **fully inlined**. So the benchmark — and
production — compare *inlined C#* against *delegate-dispatched N#*.

## Decomposition benchmark

`benchmarks/DogfoodBoundaryOverheadBenchmarks.cs` isolates the cost. The decisive control is the
**same C# scan invoked through a `Func<>` delegate** — if C#-via-delegate ≈ N#-via-delegate, the gap
is indirection, not language.

`DogfoodDeclaredTypeLookupCrossoverBenchmarks` (.NET 10.0.5, Arm64), exact-name lookup, two modes:

**`Match=First` (early match at index 0 → constant ~1-comparison body; isolates the fixed floor):**

| Path | Mean (all sizes) | vs inlined C# |
|------|------------------|---------------|
| C# inlined (direct) | ~0.45 ns | 1.0× |
| same C# body via `Func<>` delegate | ~0.94 ns | ~2.1× |
| N# kernel via bound delegate | ~1.42 ns | ~3.2× |

**`Match=None` (target absent → full scan of `Size` elements; shows amortization):**

| Size | C# inlined | C# via delegate | N# via delegate | N# − C# gap | N# / C# |
|------|-----------|-----------------|-----------------|-------------|---------|
| 2 | 0.47 ns | 1.17 | 1.66 | +1.19 | 3.58× |
| 4 | 1.18 | 1.91 | 2.41 | +1.23 | 2.04× |
| 8 | 2.74 | 3.45 | 3.93 | +1.19 | 1.43× |
| 16 | 5.74 | 6.44 | 6.85 | +1.11 | 1.19× |
| 32 | 11.46 | 12.17 | 12.65 | +1.19 | 1.10× |
| 64 | 23.00 | 23.61 | 24.16 | +1.16 | 1.05× |
| 128 | 50.50 | 51.10 | 51.76 | +1.26 | 1.02× |
| 256 | 96.03 | 96.73 | 97.30 | +1.27 | 1.01× |

## Findings

1. **The penalty is a fixed ~1.2 ns per-call floor, not a per-element disadvantage.** The
   `N# − C#` gap is flat (~1.2 ns) across every size; the slopes are parallel. N# scans each element
   exactly as fast as C# — it pays a constant entry toll. The gap decomposes, stable at all sizes:
   - **~0.7 ns** = delegate dispatch (C#-via-delegate − C#-inlined). *The identical C# code is ~2×
     slower merely by being behind a `Func<>`.*
   - **~0.5 ns** = N# body codegen (N#-via-delegate − C#-via-delegate) — almost certainly
     un-elided array bounds checks in the emitted IL.
   The supplementary `DogfoodDelegateDispatchFloorBenchmarks` corroborates: a near-empty N# kernel
   through the bound delegate costs ~1.6 ns, while a C# const lambda devirtualizes to ~0 ns.

2. **N# only *wins* when the C# baseline is wasteful.** Here the realistic C# baseline is already an
   optimal zero-allocation primitive loop, so there is **no waste to recover** — N# asymptotes to
   1.01× (a hair slower) and **never crosses over**, even at 256. The routed wins (units 1/3/5) are
   exactly the opposite: their C# baselines allocate (`OrderBy/ToList`, per-file `Regex`, candidate
   list materialization) **even at small N**, so N# wins from size 2 upward.

3. **This is the adapter boundary, not N# the language.** The dominant ~0.7 ns is generic delegate
   indirection that any language pays; it is the `*DogfoodAdapter` transition boundary that AGENTS.md
   already flags as temporary.

## "Never slower than C#" — which lever fixes which kernel class

The three levers are complementary layers, but they own **different kernel classes**:

| Lever | Removes | Applies to | Effect |
|-------|---------|-----------|--------|
| **1. Size-threshold hybrid in the adapter** | nothing (avoids the toll on tiny inputs by running C# there) | kernels with a real crossover (C# baseline wasteful at scale) | guarantees never-slower **and** keeps the win; e.g. units 1/3/5 |
| **2. Remove the delegate boundary** (in-assembly / N#-from-N# calls so the JIT inlines) | the ~0.7 ns dispatch | kernels where C# is *already optimal* (no crossover — units 4/6) | the **only** lever that helps them; lets N# tie, then win once lever 3 lands |
| **3. Bounds-check elision in N# codegen** | the ~0.5 ns body gap | every N# kernel | narrows the floor everywhere; turns ties into wins |

Consequences:

- **Lever 1 cannot help units 4/6** — there is no win zone to switch into, because C# is already
  optimal. For those, "never slower" means either keep C# (current rejection — correct and trivially
  never-slower) **or** land lever 2 so the kernel inlines.
- **Lever 2 is the endgame.** As it (and lever 3) shrink the floor, lever 1's thresholds drop toward
  zero and the C# fallbacks can be deleted — the AGENTS.md "shrink/remove the adapters" end-state.
- **Order to combine:** lever 1 now (safety net for winnable kernels) → lever 3 (broad compiler win)
  → lever 2 (architectural endgame; the only thing that rescues optimal-baseline kernels).

## Recommended next step

Prototype **lever 2**: an in-assembly (no-delegate) call path for one optimal-baseline kernel
(declared-type lookup) and re-measure with this same decomposition. Expected result: the ~0.7 ns
dispatch disappears, leaving only the ~0.5 ns codegen gap (lever 3's target), proving whether
boundary removal lets N# reach parity on kernels where C# is already optimal.

## Reproduce

```bash
dotnet build benchmarks/NSharpLang.Benchmarks.csproj -c Release
dotnet run -c Release --project benchmarks/NSharpLang.Benchmarks.csproj --no-build -- \
  --filter "*DogfoodDeclaredTypeLookupCrossover*" "*DogfoodDelegateDispatchFloor*" --memory
```
