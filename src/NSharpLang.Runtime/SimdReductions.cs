using System.Numerics;

namespace NSharpLang.Runtime;

/// <summary>
/// SIMD reduction helpers the N# systems codegen lowers recognized counted-reduction loops to (Rust-perf
/// roadmap P1). The compiler recognizes <c>while i &lt; end { acc = acc + a[i]; i = i + 1 }</c> on an integer
/// array and emits a call to the matching <see cref="SumInt32"/> / <see cref="SumInt64"/> /
/// <see cref="SumUInt32"/> / <see cref="SumUInt64"/> helper instead of the scalar loop — turning the
/// worst-case checksum-sum kernel from ~8.8× behind native to ~2× (see
/// docs/design/systems-perf-backlog.md). Keeping the vectorization here, in plain readable/testable C#,
/// rather than as hand-emitted IL, makes the codegen change trivial (load args + call) and the SIMD logic
/// auditable.
///
/// Correctness: integer wrapping addition is associative under mod 2^32 (int/uint) / mod 2^64 (long/ulong),
/// so reducing across SIMD lanes and multiple accumulators is value-identical to the sequential scalar sum
/// for ANY start/end (including start &gt; 0 and lengths not a multiple of <see cref="Vector{T}.Count"/>,
/// which the scalar tail handles). float/double are deliberately NOT provided: FP addition is not associative.
///
/// Each helper is value-identical to the scalar loop <c>for (i = start; i &lt; end; i++) sum += array[i]</c>
/// for EVERY (start, end), including degenerate ones: an empty/negative range (<c>end &lt;= start</c>, e.g.
/// <c>end = int.MinValue</c>) returns the identity with no reads, and an out-of-bounds range (<c>start &lt; 0</c>
/// or <c>end &gt; array.Length</c>) throws <see cref="System.IndexOutOfRangeException"/> at the exact same
/// element the scalar loop would — the SIMD fast path is taken only over a provably in-bounds range.
/// </summary>
public static class SimdReductions
{
    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) — the value of
    /// the scalar loop <c>acc=0; for i in [start,end): acc += array[i]</c> — computed with unrolled SIMD.</summary>
    public static int SumInt32(int[] array, int start, int end)
    {
        var sum = 0;
        var i = start;

        // Empty/negative range: the scalar loop `while i < end` never runs. Returning here also prevents the
        // `end - step` bound below from being computed for a hugely-negative `end` (e.g. int.MinValue), which
        // would wrap (unchecked) to a large positive value and run the SIMD loop over elements the scalar loop
        // never touches.
        if (end <= start)
            return sum;

        // SIMD fast path only over a provably in-bounds range [start, end). If the range is out of bounds
        // (start < 0 or end > array.Length), skip it: the scalar tail below then reproduces the scalar
        // semantics exactly, including throwing IndexOutOfRangeException at the same element — whereas
        // new Vector<T>(array, i) would throw a DIFFERENT, observable type (ArgumentOutOfRangeException).
        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<int>.Count;
            var step = lanes * 4;

            // Four independent accumulators hide add latency (the LLVM trick measured at ~4.5× vs a single
            // scalar accumulator in VectorReductionCeilingBenchmarks).
            var a0 = Vector<int>.Zero;
            var a1 = Vector<int>.Zero;
            var a2 = Vector<int>.Zero;
            var a3 = Vector<int>.Zero;
            for (; i <= end - step; i += step)
            {
                a0 += new Vector<int>(array, i);
                a1 += new Vector<int>(array, i + lanes);
                a2 += new Vector<int>(array, i + lanes * 2);
                a3 += new Vector<int>(array, i + lanes * 3);
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3);
        }

        // Scalar tail for the remaining < step elements, or the whole range when the fast path was skipped.
        for (; i < end; i++)
            sum += array[i];

        return sum;
    }

    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) for
    /// <c>long</c> (Rust-perf P1(d)). <c>long</c> wrapping add is associative under mod 2^64, so the unrolled
    /// SIMD reduction is value-identical to the scalar loop.</summary>
    public static long SumInt64(long[] array, int start, int end)
    {
        var sum = 0L;
        var i = start;

        if (end <= start)
            return sum;

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<long>.Count;
            var step = lanes * 4;

            var a0 = Vector<long>.Zero;
            var a1 = Vector<long>.Zero;
            var a2 = Vector<long>.Zero;
            var a3 = Vector<long>.Zero;
            for (; i <= end - step; i += step)
            {
                a0 += new Vector<long>(array, i);
                a1 += new Vector<long>(array, i + lanes);
                a2 += new Vector<long>(array, i + lanes * 2);
                a3 += new Vector<long>(array, i + lanes * 3);
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3);
        }

        for (; i < end; i++)
            sum += array[i];

        return sum;
    }

    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) for
    /// <c>uint</c> (Rust-perf P1(d)). Unsigned wrapping add is associative under mod 2^32.</summary>
    public static uint SumUInt32(uint[] array, int start, int end)
    {
        var sum = 0u;
        var i = start;

        if (end <= start)
            return sum;

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<uint>.Count;
            var step = lanes * 4;

            var a0 = Vector<uint>.Zero;
            var a1 = Vector<uint>.Zero;
            var a2 = Vector<uint>.Zero;
            var a3 = Vector<uint>.Zero;
            for (; i <= end - step; i += step)
            {
                a0 += new Vector<uint>(array, i);
                a1 += new Vector<uint>(array, i + lanes);
                a2 += new Vector<uint>(array, i + lanes * 2);
                a3 += new Vector<uint>(array, i + lanes * 3);
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3);
        }

        for (; i < end; i++)
            sum += array[i];

        return sum;
    }

    /// <summary>Sum of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) for
    /// <c>ulong</c> (Rust-perf P1(d)). Unsigned wrapping add is associative under mod 2^64.</summary>
    public static ulong SumUInt64(ulong[] array, int start, int end)
    {
        var sum = 0uL;
        var i = start;

        if (end <= start)
            return sum;

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<ulong>.Count;
            var step = lanes * 4;

            var a0 = Vector<ulong>.Zero;
            var a1 = Vector<ulong>.Zero;
            var a2 = Vector<ulong>.Zero;
            var a3 = Vector<ulong>.Zero;
            for (; i <= end - step; i += step)
            {
                a0 += new Vector<ulong>(array, i);
                a1 += new Vector<ulong>(array, i + lanes);
                a2 += new Vector<ulong>(array, i + lanes * 2);
                a3 += new Vector<ulong>(array, i + lanes * 3);
            }

            sum += Vector.Sum(a0 + a1 + a2 + a3);
        }

        for (; i < end; i++)
            sum += array[i];

        return sum;
    }

    /// <summary>Count of <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) whose value
    /// is in the inclusive range [<paramref name="lo"/>, <paramref name="hi"/>] — the value of the scalar loop
    /// <c>count=0; for i in [start,end): if lo &lt;= array[i] &lt;= hi: count++</c> — computed with masked SIMD
    /// (Rust-perf P2(b), the count-ascii kernel). Packed compares produce an all-ones lane mask per in-range
    /// element; subtracting the mask accumulates +1 per match (across four independent accumulators to hide
    /// latency), then a horizontal sum plus the scalar tail. The count is order-independent, so this is
    /// value-identical to the scalar loop. The empty/negative-range early-out and the in-bounds guard match
    /// <see cref="SumInt32"/> exactly: an out-of-bounds range throws <see cref="System.IndexOutOfRangeException"/>
    /// at the same element via the scalar tail (not the Vector ctor's <c>ArgumentOutOfRangeException</c>).</summary>
    public static int CountInRangeInt32(int[] array, int start, int end, int lo, int hi)
    {
        var count = 0;
        var i = start;

        if (end <= start)
            return count;

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<int>.Count;
            var step = lanes * 4;
            var vlo = new Vector<int>(lo);
            var vhi = new Vector<int>(hi);

            // Four independent lane-count accumulators. A packed compare yields -1 (all bits) per in-range lane;
            // `acc -= mask` therefore adds 1 per match. Counts are order-independent, so this matches the scalar
            // sequential count exactly.
            var a0 = Vector<int>.Zero;
            var a1 = Vector<int>.Zero;
            var a2 = Vector<int>.Zero;
            var a3 = Vector<int>.Zero;
            for (; i <= end - step; i += step)
            {
                var v0 = new Vector<int>(array, i);
                var v1 = new Vector<int>(array, i + lanes);
                var v2 = new Vector<int>(array, i + lanes * 2);
                var v3 = new Vector<int>(array, i + lanes * 3);
                a0 -= Vector.GreaterThanOrEqual(v0, vlo) & Vector.LessThanOrEqual(v0, vhi);
                a1 -= Vector.GreaterThanOrEqual(v1, vlo) & Vector.LessThanOrEqual(v1, vhi);
                a2 -= Vector.GreaterThanOrEqual(v2, vlo) & Vector.LessThanOrEqual(v2, vhi);
                a3 -= Vector.GreaterThanOrEqual(v3, vlo) & Vector.LessThanOrEqual(v3, vhi);
            }

            count += Vector.Sum(a0 + a1 + a2 + a3);
        }

        for (; i < end; i++)
            if (array[i] >= lo && array[i] <= hi)
                count++;

        return count;
    }

    /// <summary>Minimum of <paramref name="seed"/> and <paramref name="array"/>[<paramref name="start"/> ..
    /// <paramref name="end"/>) — the value of the scalar fold <c>m = seed; for i in [start,end): if array[i] &lt; m
    /// m = array[i]</c> — computed with lane-wise SIMD (Rust-perf P-minmax, the min-max-delta kernel). Signed
    /// integer min is associative AND commutative (a total order), so <see cref="Vector.Min{T}"/> across lanes and
    /// four accumulators is value-identical to the sequential scalar fold for ANY (start, end). The accumulators
    /// are seeded with <paramref name="seed"/> broadcast, so lanes that never see a smaller element keep the seed.
    /// The empty/negative-range early-out and the in-bounds guard match <see cref="SumInt32"/> exactly: an
    /// out-of-bounds range throws <see cref="System.IndexOutOfRangeException"/> at the same element via the scalar
    /// tail (not the Vector ctor's <c>ArgumentOutOfRangeException</c>).</summary>
    public static int MinInt32(int[] array, int start, int end, int seed)
    {
        var result = seed;
        var i = start;

        // Empty/negative range: the scalar fold never runs, so the min is just the seed. Returning here also
        // prevents the `end - step` bound below from being computed for a hugely-negative `end` (e.g.
        // int.MinValue), which would wrap (unchecked) to a large positive value (the P1(d) overflow fix).
        if (end <= start)
            return result;

        // SIMD fast path only over a provably in-bounds range. Otherwise the scalar tail reproduces the scalar
        // semantics exactly, including IndexOutOfRangeException at the same element.
        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<int>.Count;
            var step = lanes * 4;

            var a0 = new Vector<int>(result);
            var a1 = new Vector<int>(result);
            var a2 = new Vector<int>(result);
            var a3 = new Vector<int>(result);
            for (; i <= end - step; i += step)
            {
                a0 = Vector.Min(a0, new Vector<int>(array, i));
                a1 = Vector.Min(a1, new Vector<int>(array, i + lanes));
                a2 = Vector.Min(a2, new Vector<int>(array, i + lanes * 2));
                a3 = Vector.Min(a3, new Vector<int>(array, i + lanes * 3));
            }

            // Horizontal min across the four accumulators, then across the lanes (no Vector.Min reduce intrinsic).
            var folded = Vector.Min(Vector.Min(a0, a1), Vector.Min(a2, a3));
            for (var lane = 0; lane < lanes; lane++)
                if (folded[lane] < result)
                    result = folded[lane];
        }

        for (; i < end; i++)
            if (array[i] < result)
                result = array[i];

        return result;
    }

    /// <summary>Maximum of <paramref name="seed"/> and <paramref name="array"/>[<paramref name="start"/> ..
    /// <paramref name="end"/>) — the value of the scalar fold <c>m = seed; for i in [start,end): if array[i] &gt; m
    /// m = array[i]</c> — computed with lane-wise SIMD (Rust-perf P-minmax). The mirror of <see cref="MinInt32"/>:
    /// signed integer max is associative + commutative, so <see cref="Vector.Max{T}"/> across lanes and four
    /// seed-broadcast accumulators is value-identical to the scalar fold, with the same empty/OOB guards.</summary>
    public static int MaxInt32(int[] array, int start, int end, int seed)
    {
        var result = seed;
        var i = start;

        if (end <= start)
            return result;

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<int>.Count;
            var step = lanes * 4;

            var a0 = new Vector<int>(result);
            var a1 = new Vector<int>(result);
            var a2 = new Vector<int>(result);
            var a3 = new Vector<int>(result);
            for (; i <= end - step; i += step)
            {
                a0 = Vector.Max(a0, new Vector<int>(array, i));
                a1 = Vector.Max(a1, new Vector<int>(array, i + lanes));
                a2 = Vector.Max(a2, new Vector<int>(array, i + lanes * 2));
                a3 = Vector.Max(a3, new Vector<int>(array, i + lanes * 3));
            }

            var folded = Vector.Max(Vector.Max(a0, a1), Vector.Max(a2, a3));
            for (var lane = 0; lane < lanes; lane++)
                if (folded[lane] > result)
                    result = folded[lane];
        }

        for (; i < end; i++)
            if (array[i] > result)
                result = array[i];

        return result;
    }

    /// <summary>Computes BOTH the minimum and maximum of (<paramref name="seedMin"/>, <paramref name="seedMax"/>)
    /// and <paramref name="array"/>[<paramref name="start"/> .. <paramref name="end"/>) in a SINGLE pass — the
    /// fused min-max-delta lowering (Rust-perf P-minmax(c)). Loading each <c>Vector&lt;int&gt;</c> ONCE and applying
    /// both <see cref="Vector.Min{T}"/> and <see cref="Vector.Max{T}"/> to it halves the memory traffic of two
    /// independent <see cref="MinInt32"/> + <see cref="MaxInt32"/> scans. Value-identical to the scalar fold
    /// <c>mn=seedMin; mx=seedMax; for i in [start,end): if a[i]&lt;mn mn=a[i]; if a[i]&gt;mx mx=a[i]</c> (min and max
    /// are independent and order-free). Same empty/negative-range early-out and in-bounds guard as
    /// <see cref="MinInt32"/>/<see cref="MaxInt32"/>: an out-of-bounds range throws
    /// <see cref="System.IndexOutOfRangeException"/> at the same element via the shared scalar tail.</summary>
    public static (int Min, int Max) MinMaxInt32(int[] array, int start, int end, int seedMin, int seedMax)
    {
        var min = seedMin;
        var max = seedMax;
        var i = start;

        if (end <= start)
            return (min, max);

        if (start >= 0 && end <= array.Length)
        {
            var lanes = Vector<int>.Count;
            var step = lanes * 4;

            var mn0 = new Vector<int>(min);
            var mn1 = mn0;
            var mn2 = mn0;
            var mn3 = mn0;
            var mx0 = new Vector<int>(max);
            var mx1 = mx0;
            var mx2 = mx0;
            var mx3 = mx0;
            for (; i <= end - step; i += step)
            {
                // Each vector is loaded ONCE and fed to both the min and the max accumulators — the single-pass win.
                var v0 = new Vector<int>(array, i);
                var v1 = new Vector<int>(array, i + lanes);
                var v2 = new Vector<int>(array, i + lanes * 2);
                var v3 = new Vector<int>(array, i + lanes * 3);
                mn0 = Vector.Min(mn0, v0);
                mn1 = Vector.Min(mn1, v1);
                mn2 = Vector.Min(mn2, v2);
                mn3 = Vector.Min(mn3, v3);
                mx0 = Vector.Max(mx0, v0);
                mx1 = Vector.Max(mx1, v1);
                mx2 = Vector.Max(mx2, v2);
                mx3 = Vector.Max(mx3, v3);
            }

            var fmin = Vector.Min(Vector.Min(mn0, mn1), Vector.Min(mn2, mn3));
            var fmax = Vector.Max(Vector.Max(mx0, mx1), Vector.Max(mx2, mx3));
            for (var lane = 0; lane < lanes; lane++)
            {
                if (fmin[lane] < min) min = fmin[lane];
                if (fmax[lane] > max) max = fmax[lane];
            }
        }

        for (; i < end; i++)
        {
            var v = array[i];
            if (v < min) min = v;
            if (v > max) max = v;
        }

        return (min, max);
    }

    /// <summary>Counts adjacent transitions in <paramref name="array"/>[<paramref name="start"/> ..
    /// <paramref name="end"/>) — the value of the scalar loop
    /// <c>count=0; prev=seedPrevious; for i in [start,end): if array[i] != prev: count++; prev=array[i]</c> —
    /// and returns <c>(count, lastPrevious)</c>, where <c>lastPrevious</c> is <c>prev</c> after the loop
    /// (<c>array[end-1]</c>, or <paramref name="seedPrevious"/> when the range is empty) so the emitter can
    /// restore the carried <c>previous</c> variable for any later use (Rust-perf P-ctrans, the count-transitions
    /// kernel). Computed with masked SIMD: the FIRST element compares against <paramref name="seedPrevious"/>
    /// (scalar), then the rest compare <c>array[i]</c> against <c>array[i-1]</c> via shifted loads — a packed
    /// not-equal mask (<c>~Vector.Equals</c>) accumulated as <c>acc -= mask</c> (+1 per mismatch) across four
    /// lane-accumulators, then a horizontal sum and a scalar tail. Comparisons are independent, so this is
    /// value-identical to the scalar loop for ANY seed (no pre-loop init assumption needed — the seed reproduces
    /// the scalar's first comparison exactly). Crucially it reads only <c>array[start..end-1]</c> (the i=start
    /// element compares against the seed, NOT against <c>array[start-1]</c>). The empty/negative-range early-out
    /// and in-bounds guard match the other helpers: an out-of-bounds range throws
    /// <see cref="System.IndexOutOfRangeException"/> at the same element via the scalar path.</summary>
    public static (int Count, int LastPrevious) CountTransitionsInt32(int[] array, int start, int end, int seedPrevious)
    {
        var count = 0;
        var prev = seedPrevious;
        var i = start;

        if (end <= start)
            return (count, prev);

        // SIMD fast path only over a provably in-bounds range. The whole range reads array[start..end-1]
        // (the seed replaces array[start-1]), so the guard is the same start>=0 && end<=Length as the others.
        if (start >= 0 && end <= array.Length)
        {
            // First element vs the seed (scalar) — this is the only comparison that uses seedPrevious.
            if (array[start] != prev)
                count++;

            // Vectorize i in [start+1, end): array[i] != array[i-1] via shifted loads. array[i-1] for the first
            // such i is array[start] (in bounds). The masked count is order-independent.
            i = start + 1;
            var lanes = Vector<int>.Count;
            var step = lanes * 4;
            var a0 = Vector<int>.Zero;
            var a1 = Vector<int>.Zero;
            var a2 = Vector<int>.Zero;
            var a3 = Vector<int>.Zero;
            for (; i <= end - step; i += step)
            {
                // ~Vector.Equals(curr, prev) is all-ones per NOT-equal lane; `acc -= mask` adds 1 per mismatch.
                a0 -= ~Vector.Equals(new Vector<int>(array, i), new Vector<int>(array, i - 1));
                a1 -= ~Vector.Equals(new Vector<int>(array, i + lanes), new Vector<int>(array, i - 1 + lanes));
                a2 -= ~Vector.Equals(new Vector<int>(array, i + lanes * 2), new Vector<int>(array, i - 1 + lanes * 2));
                a3 -= ~Vector.Equals(new Vector<int>(array, i + lanes * 3), new Vector<int>(array, i - 1 + lanes * 3));
            }

            count += Vector.Sum(a0 + a1 + a2 + a3);

            // Scalar tail for the remaining elements, still comparing array[i] against array[i-1].
            for (; i < end; i++)
                if (array[i] != array[i - 1])
                    count++;

            // Terminal carried value = the last element (end-1 is in [start, Length-1] here).
            return (count, array[end - 1]);
        }

        // Out-of-bounds (or otherwise): the faithful scalar loop — compares against the carried prev and throws
        // IndexOutOfRangeException at the same element the scalar loop would.
        for (; i < end; i++)
        {
            if (array[i] != prev)
                count++;
            prev = array[i];
        }

        return (count, prev);
    }
}
