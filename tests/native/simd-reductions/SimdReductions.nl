namespace NSharpLang.SimdReductions.Tests

import System.Numerics

// A COMPLETE, FAITHFUL N# TRANSLATION OF `src/NSharpLang.Runtime/SimdReductions.cs`.
//
// The C# file is the SIMD reduction library the systems codegen lowers recognized counted-reduction loops
// to. It is written in plain readable CLR helper code precisely so the SIMD logic stays auditable, and it
// is the densest `System.Numerics.Vector<T>` surface the product owns: constructed generic static
// properties (`Vector<int>.Count`, `Vector<int>.Zero`), constructed generic constructors over four element
// types (`new Vector<uint>(array, i)`, `new Vector<long>(seed)`), the generic operators `+ - & ~` and their
// compound forms, the lane indexer `folded[lane]`, the generic static methods
// `Vector.Sum` / `Vector.Min` / `Vector.Max` / `Vector.Equals` / `Vector.GreaterThanOrEqual` /
// `Vector.LessThanOrEqual`, and named tuple returns.
//
// EVERY LINE BELOW RESOLVES THROUGH ORDINARY SCOPED CLR MEMBER, CONSTRUCTOR AND OPERATOR RESOLUTION. The
// compiler models nothing about `Vector<T>`: there is no lane-count constant, no modeled-call table, no
// scalar substitution and no alternate path. If this file compiles and executes, the general mechanism
// works; the sibling `tests/native/external-generic-construction` project isolates each element of it.
//
// The translation is faithful, not merely equivalent: the same methods with the same names and signatures,
// the same guards in the same order, the same four-accumulator unrolling, the same horizontal folds, the
// same scalar tails and the same evaluation order. `SimdReductions.tests.nl` asserts value identity against
// scalar oracles AND side by side against the real `NSharpLang.Runtime.SimdReductions` on identical inputs,
// so a divergence in either direction is a failing row. The C# `for (; i <= end - step; i += step)` header
// becomes a `while` with the step written at the end of the body — the same reads, the same order, the
// same terminal value of `i`.
//
// CORRECTNESS (the C# file's own argument, preserved): integer wrapping addition is associative under
// mod 2^32 (int/uint) / mod 2^64 (long/ulong), so reducing across SIMD lanes and multiple accumulators is
// value-identical to the sequential scalar sum for ANY start/end — including `start > 0` and lengths that
// are not a multiple of `Vector<T>.Count`, which the scalar tail handles. float/double are deliberately NOT
// provided: floating-point addition is not associative.
//
// Each helper is value-identical to the scalar loop `for (i = start; i < end; i++) sum += array[i]` for
// EVERY (start, end), including the degenerate ones: an empty/negative range (`end <= start`, e.g.
// `end = int.MinValue`) returns the identity with no reads, and an out-of-bounds range (`start < 0` or
// `end > array.Length`) throws `IndexOutOfRangeException` at the exact same element the scalar loop would —
// the SIMD fast path is taken only over a provably in-bounds range.
//
// WHY THE CLASS IS `SimdReductionsPort` AND NOT `SimdReductions`. The project references the real
// `NSharpLang.Runtime` so the tests can compare the two implementations side by side, and N# resolves an
// unqualified type name to ANY same-named type declared in the compilation regardless of its namespace --
// a source `SimdReductions` here would silently shadow the imported `NSharpLang.Runtime.SimdReductions`
// everywhere in the project, turning every parity row into a comparison of the translation with itself.
// (That shadowing, and the absence of an ambiguity diagnostic for it, is reported as a gap.) The METHODS
// keep their exact names and signatures, and `SimdReductions.tests.nl` asserts that member for member
// against the original's metadata; only the container is renamed, and a permanent row pins that the
// "original" side really is the C# type from the other assembly.
static class SimdReductionsPort {

    // Sum of array[start .. end) — the value of the scalar loop `acc=0; for i in [start,end): acc += array[i]`
    // — computed with unrolled SIMD.
    static func SumInt32(array: int[], start: int, end: int): int {
        sum := 0
        i := start

        // Empty/negative range: the scalar loop `while i < end` never runs. Returning here also prevents the
        // `end - step` bound below from being computed for a hugely-negative `end` (e.g. int.MinValue), which
        // would wrap (unchecked) to a large positive value and run the SIMD loop over elements the scalar loop
        // never touches.
        if end <= start {
            return sum
        }

        // SIMD fast path only over a provably in-bounds range [start, end). If the range is out of bounds
        // (start < 0 or end > array.Length), skip it: the scalar tail below then reproduces the scalar
        // semantics exactly, including throwing IndexOutOfRangeException at the same element — whereas
        // new Vector<T>(array, i) would throw a DIFFERENT, observable type (ArgumentOutOfRangeException).
        if start >= 0 && end <= array.Length {
            lanes := Vector<int>.Count
            step := lanes * 4

            // Four independent accumulators hide add latency (the LLVM trick measured at ~4.5x vs a single
            // scalar accumulator in VectorReductionCeilingBenchmarks).
            a0 := Vector<int>.Zero
            a1 := Vector<int>.Zero
            a2 := Vector<int>.Zero
            a3 := Vector<int>.Zero
            while i <= end - step {
                a0 += new Vector<int>(array, i)
                a1 += new Vector<int>(array, i + lanes)
                a2 += new Vector<int>(array, i + lanes * 2)
                a3 += new Vector<int>(array, i + lanes * 3)
                i += step
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3)
        }

        // Scalar tail for the remaining < step elements, or the whole range when the fast path was skipped.
        while i < end {
            sum += array[i]
            i += 1
        }

        return sum
    }

    // Sum of array[start .. end) for `long` (Rust-perf P1(d)). `long` wrapping add is associative under
    // mod 2^64, so the unrolled SIMD reduction is value-identical to the scalar loop.
    static func SumInt64(array: long[], start: int, end: int): long {
        sum := 0L
        i := start

        if end <= start {
            return sum
        }

        if start >= 0 && end <= array.Length {
            lanes := Vector<long>.Count
            step := lanes * 4

            a0 := Vector<long>.Zero
            a1 := Vector<long>.Zero
            a2 := Vector<long>.Zero
            a3 := Vector<long>.Zero
            while i <= end - step {
                a0 += new Vector<long>(array, i)
                a1 += new Vector<long>(array, i + lanes)
                a2 += new Vector<long>(array, i + lanes * 2)
                a3 += new Vector<long>(array, i + lanes * 3)
                i += step
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3)
        }

        while i < end {
            sum += array[i]
            i += 1
        }

        return sum
    }

    // Sum of array[start .. end) for `uint` (Rust-perf P1(d)). Unsigned wrapping add is associative under
    // mod 2^32.
    static func SumUInt32(array: uint[], start: int, end: int): uint {
        sum := 0u
        i := start

        if end <= start {
            return sum
        }

        if start >= 0 && end <= array.Length {
            lanes := Vector<uint>.Count
            step := lanes * 4

            a0 := Vector<uint>.Zero
            a1 := Vector<uint>.Zero
            a2 := Vector<uint>.Zero
            a3 := Vector<uint>.Zero
            while i <= end - step {
                a0 += new Vector<uint>(array, i)
                a1 += new Vector<uint>(array, i + lanes)
                a2 += new Vector<uint>(array, i + lanes * 2)
                a3 += new Vector<uint>(array, i + lanes * 3)
                i += step
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3)
        }

        while i < end {
            sum += array[i]
            i += 1
        }

        return sum
    }

    // Sum of array[start .. end) for `ulong` (Rust-perf P1(d)). Unsigned wrapping add is associative under
    // mod 2^64.
    static func SumUInt64(array: ulong[], start: int, end: int): ulong {
        sum := 0uL
        i := start

        if end <= start {
            return sum
        }

        if start >= 0 && end <= array.Length {
            lanes := Vector<ulong>.Count
            step := lanes * 4

            a0 := Vector<ulong>.Zero
            a1 := Vector<ulong>.Zero
            a2 := Vector<ulong>.Zero
            a3 := Vector<ulong>.Zero
            while i <= end - step {
                a0 += new Vector<ulong>(array, i)
                a1 += new Vector<ulong>(array, i + lanes)
                a2 += new Vector<ulong>(array, i + lanes * 2)
                a3 += new Vector<ulong>(array, i + lanes * 3)
                i += step
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3)
        }

        while i < end {
            sum += array[i]
            i += 1
        }

        return sum
    }

    // Count of array[start .. end) whose value is in the inclusive range [lo, hi] — the value of the scalar
    // loop `count=0; for i in [start,end): if lo <= array[i] <= hi: count++` — computed with masked SIMD
    // (Rust-perf P2(b), the count-ascii kernel). Packed compares produce an all-ones lane mask per in-range
    // element; subtracting the mask accumulates +1 per match (across four independent accumulators to hide
    // latency), then a horizontal sum plus the scalar tail. The count is order-independent, so this is
    // value-identical to the scalar loop. The empty/negative-range early-out and the in-bounds guard match
    // SumInt32 exactly: an out-of-bounds range throws IndexOutOfRangeException at the same element via the
    // scalar tail (not the Vector ctor's ArgumentOutOfRangeException).
    static func CountInRangeInt32(array: int[], start: int, end: int, lo: int, hi: int): int {
        count := 0
        i := start

        if end <= start {
            return count
        }

        if start >= 0 && end <= array.Length {
            lanes := Vector<int>.Count
            step := lanes * 4
            vlo := new Vector<int>(lo)
            vhi := new Vector<int>(hi)

            // Four independent lane-count accumulators. A packed compare yields -1 (all bits) per in-range
            // lane; `acc -= mask` therefore adds 1 per match. Counts are order-independent, so this matches
            // the scalar sequential count exactly.
            a0 := Vector<int>.Zero
            a1 := Vector<int>.Zero
            a2 := Vector<int>.Zero
            a3 := Vector<int>.Zero
            while i <= end - step {
                v0 := new Vector<int>(array, i)
                v1 := new Vector<int>(array, i + lanes)
                v2 := new Vector<int>(array, i + lanes * 2)
                v3 := new Vector<int>(array, i + lanes * 3)
                a0 -= Vector.GreaterThanOrEqual(v0, vlo) & Vector.LessThanOrEqual(v0, vhi)
                a1 -= Vector.GreaterThanOrEqual(v1, vlo) & Vector.LessThanOrEqual(v1, vhi)
                a2 -= Vector.GreaterThanOrEqual(v2, vlo) & Vector.LessThanOrEqual(v2, vhi)
                a3 -= Vector.GreaterThanOrEqual(v3, vlo) & Vector.LessThanOrEqual(v3, vhi)
                i += step
            }

            count += Vector.Sum(a0 + a1 + a2 + a3)
        }

        while i < end {
            if array[i] >= lo && array[i] <= hi {
                count += 1
            }
            i += 1
        }

        return count
    }

    // Minimum of `seed` and array[start .. end) — the value of the scalar fold
    // `m = seed; for i in [start,end): if array[i] < m: m = array[i]` — computed with lane-wise SIMD
    // (Rust-perf P-minmax, the min-max-delta kernel). Signed integer min is associative AND commutative (a
    // total order), so `Vector.Min` across lanes and four accumulators is value-identical to the sequential
    // scalar fold for ANY (start, end). The accumulators are seeded with `seed` broadcast, so lanes that
    // never see a smaller element keep the seed. The empty/negative-range early-out and the in-bounds guard
    // match SumInt32 exactly: an out-of-bounds range throws IndexOutOfRangeException at the same element via
    // the scalar tail (not the Vector ctor's ArgumentOutOfRangeException).
    static func MinInt32(array: int[], start: int, end: int, seed: int): int {
        result := seed
        i := start

        // Empty/negative range: the scalar fold never runs, so the min is just the seed. Returning here also
        // prevents the `end - step` bound below from being computed for a hugely-negative `end` (e.g.
        // int.MinValue), which would wrap (unchecked) to a large positive value (the P1(d) overflow fix).
        if end <= start {
            return result
        }

        // SIMD fast path only over a provably in-bounds range. Otherwise the scalar tail reproduces the
        // scalar semantics exactly, including IndexOutOfRangeException at the same element.
        if start >= 0 && end <= array.Length {
            lanes := Vector<int>.Count
            step := lanes * 4

            a0 := new Vector<int>(result)
            a1 := new Vector<int>(result)
            a2 := new Vector<int>(result)
            a3 := new Vector<int>(result)
            while i <= end - step {
                a0 = Vector.Min(a0, new Vector<int>(array, i))
                a1 = Vector.Min(a1, new Vector<int>(array, i + lanes))
                a2 = Vector.Min(a2, new Vector<int>(array, i + lanes * 2))
                a3 = Vector.Min(a3, new Vector<int>(array, i + lanes * 3))
                i += step
            }

            // Horizontal min across the four accumulators, then across the lanes (no Vector.Min reduce
            // intrinsic).
            folded := Vector.Min(Vector.Min(a0, a1), Vector.Min(a2, a3))
            lane := 0
            while lane < lanes {
                if folded[lane] < result {
                    result = folded[lane]
                }
                lane += 1
            }
        }

        while i < end {
            if array[i] < result {
                result = array[i]
            }
            i += 1
        }

        return result
    }

    // Maximum of `seed` and array[start .. end) — the value of the scalar fold
    // `m = seed; for i in [start,end): if array[i] > m: m = array[i]` — computed with lane-wise SIMD
    // (Rust-perf P-minmax). The mirror of MinInt32: signed integer max is associative + commutative, so
    // `Vector.Max` across lanes and four seed-broadcast accumulators is value-identical to the scalar fold,
    // with the same empty/OOB guards.
    static func MaxInt32(array: int[], start: int, end: int, seed: int): int {
        result := seed
        i := start

        if end <= start {
            return result
        }

        if start >= 0 && end <= array.Length {
            lanes := Vector<int>.Count
            step := lanes * 4

            a0 := new Vector<int>(result)
            a1 := new Vector<int>(result)
            a2 := new Vector<int>(result)
            a3 := new Vector<int>(result)
            while i <= end - step {
                a0 = Vector.Max(a0, new Vector<int>(array, i))
                a1 = Vector.Max(a1, new Vector<int>(array, i + lanes))
                a2 = Vector.Max(a2, new Vector<int>(array, i + lanes * 2))
                a3 = Vector.Max(a3, new Vector<int>(array, i + lanes * 3))
                i += step
            }

            folded := Vector.Max(Vector.Max(a0, a1), Vector.Max(a2, a3))
            lane := 0
            while lane < lanes {
                if folded[lane] > result {
                    result = folded[lane]
                }
                lane += 1
            }
        }

        while i < end {
            if array[i] > result {
                result = array[i]
            }
            i += 1
        }

        return result
    }

    // Computes BOTH the minimum and maximum of (seedMin, seedMax) and array[start .. end) in a SINGLE pass —
    // the fused min-max-delta lowering (Rust-perf P-minmax(c)). Loading each `Vector<int>` ONCE and applying
    // both `Vector.Min` and `Vector.Max` to it halves the memory traffic of two independent MinInt32 +
    // MaxInt32 scans. Value-identical to the scalar fold
    // `mn=seedMin; mx=seedMax; for i in [start,end): if a[i]<mn mn=a[i]; if a[i]>mx mx=a[i]` (min and max
    // are independent and order-free). Same empty/negative-range early-out and in-bounds guard as
    // MinInt32/MaxInt32: an out-of-bounds range throws IndexOutOfRangeException at the same element via the
    // shared scalar tail.
    static func MinMaxInt32(array: int[], start: int, end: int, seedMin: int, seedMax: int): (Min: int, Max: int) {
        min := seedMin
        max := seedMax
        i := start

        if end <= start {
            return (min, max)
        }

        if start >= 0 && end <= array.Length {
            lanes := Vector<int>.Count
            step := lanes * 4

            mn0 := new Vector<int>(min)
            mn1 := mn0
            mn2 := mn0
            mn3 := mn0
            mx0 := new Vector<int>(max)
            mx1 := mx0
            mx2 := mx0
            mx3 := mx0
            while i <= end - step {
                // Each vector is loaded ONCE and fed to both the min and the max accumulators — the
                // single-pass win.
                v0 := new Vector<int>(array, i)
                v1 := new Vector<int>(array, i + lanes)
                v2 := new Vector<int>(array, i + lanes * 2)
                v3 := new Vector<int>(array, i + lanes * 3)
                mn0 = Vector.Min(mn0, v0)
                mn1 = Vector.Min(mn1, v1)
                mn2 = Vector.Min(mn2, v2)
                mn3 = Vector.Min(mn3, v3)
                mx0 = Vector.Max(mx0, v0)
                mx1 = Vector.Max(mx1, v1)
                mx2 = Vector.Max(mx2, v2)
                mx3 = Vector.Max(mx3, v3)
                i += step
            }

            fmin := Vector.Min(Vector.Min(mn0, mn1), Vector.Min(mn2, mn3))
            fmax := Vector.Max(Vector.Max(mx0, mx1), Vector.Max(mx2, mx3))
            lane := 0
            while lane < lanes {
                if fmin[lane] < min {
                    min = fmin[lane]
                }
                if fmax[lane] > max {
                    max = fmax[lane]
                }
                lane += 1
            }
        }

        while i < end {
            v := array[i]
            if v < min {
                min = v
            }
            if v > max {
                max = v
            }
            i += 1
        }

        return (min, max)
    }

    // Counts adjacent transitions in array[start .. end) — the value of the scalar loop
    // `count=0; prev=seedPrevious; for i in [start,end): if array[i] != prev: count++; prev=array[i]` — and
    // returns (count, lastPrevious), where lastPrevious is `prev` after the loop (array[end-1], or
    // seedPrevious when the range is empty) so the emitter can restore the carried `previous` variable for
    // any later use (Rust-perf P-ctrans, the count-transitions kernel). Computed with masked SIMD: the FIRST
    // element compares against seedPrevious (scalar), then the rest compare array[i] against array[i-1] via
    // shifted loads — a packed not-equal mask (`~Vector.Equals`) accumulated as `acc -= mask` (+1 per
    // mismatch) across four lane-accumulators, then a horizontal sum and a scalar tail. Comparisons are
    // independent, so this is value-identical to the scalar loop for ANY seed (no pre-loop init assumption
    // needed — the seed reproduces the scalar's first comparison exactly). Crucially it reads only
    // array[start..end-1] (the i=start element compares against the seed, NOT against array[start-1]). The
    // empty/negative-range early-out and in-bounds guard match the other helpers: an out-of-bounds range
    // throws IndexOutOfRangeException at the same element via the scalar path.
    static func CountTransitionsInt32(array: int[], start: int, end: int, seedPrevious: int): (Count: int, LastPrevious: int) {
        count := 0
        prev := seedPrevious
        i := start

        if end <= start {
            return (count, prev)
        }

        // SIMD fast path only over a provably in-bounds range. The whole range reads array[start..end-1]
        // (the seed replaces array[start-1]), so the guard is the same start>=0 && end<=Length as the others.
        if start >= 0 && end <= array.Length {
            // First element vs the seed (scalar) — this is the only comparison that uses seedPrevious.
            if array[start] != prev {
                count += 1
            }

            // Vectorize i in [start+1, end): array[i] != array[i-1] via shifted loads. array[i-1] for the
            // first such i is array[start] (in bounds). The masked count is order-independent.
            i = start + 1
            lanes := Vector<int>.Count
            step := lanes * 4
            a0 := Vector<int>.Zero
            a1 := Vector<int>.Zero
            a2 := Vector<int>.Zero
            a3 := Vector<int>.Zero
            while i <= end - step {
                // ~Vector.Equals(curr, prev) is all-ones per NOT-equal lane; `acc -= mask` adds 1 per
                // mismatch.
                a0 -= ~Vector.Equals(new Vector<int>(array, i), new Vector<int>(array, i - 1))
                a1 -= ~Vector.Equals(new Vector<int>(array, i + lanes), new Vector<int>(array, i - 1 + lanes))
                a2 -= ~Vector.Equals(new Vector<int>(array, i + lanes * 2), new Vector<int>(array, i - 1 + lanes * 2))
                a3 -= ~Vector.Equals(new Vector<int>(array, i + lanes * 3), new Vector<int>(array, i - 1 + lanes * 3))
                i += step
            }

            count += Vector.Sum(a0 + a1 + a2 + a3)

            // Scalar tail for the remaining elements, still comparing array[i] against array[i-1].
            while i < end {
                if array[i] != array[i - 1] {
                    count += 1
                }
                i += 1
            }

            // Terminal carried value = the last element (end-1 is in [start, Length-1] here).
            return (count, array[end - 1])
        }

        // Out-of-bounds (or otherwise): the faithful scalar loop — compares against the carried prev and
        // throws IndexOutOfRangeException at the same element the scalar loop would.
        while i < end {
            if array[i] != prev {
                count += 1
            }
            prev = array[i]
            i += 1
        }

        return (count, prev)
    }
}
