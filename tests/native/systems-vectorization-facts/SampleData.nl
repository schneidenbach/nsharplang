namespace NSharpLang.SystemsVectorizationFacts.Tests


// THE INPUTS THE DELETED TESTS USED, REBUILT ONCE FOR ALL FOUR FACT FILES.
//
// Every generator here is the deterministic body of a `private static` helper in the deleted C# files
// (`AsciiLike`, `SignedLike`, `RunsLike`, and the four inline `for` loops that filled the reduction inputs),
// so a length that mattered there produces the same values here. Two properties are deliberate:
//
//   * NEGATIVES AND EXTREMES ARE PLANTED, not hoped for. `Randomized` plants int.MinValue and int.MaxValue;
//     `SignedLike` plants them at the interior positions 3 and 5 so the min and the max are never the seed;
//     `RunsLike` plants them adjacent to their neighbours so an extreme value is also a transition.
//   * THE INTEGER GENERATORS OVERFLOW ON PURPOSE. `UInts` wraps mod 2^32 and `ULongs` wraps mod 2^64 across a
//     1000-element sum, which is what makes the "wrapping add is associative, so the lane order cannot matter"
//     claim measurable rather than asserted.
//
// `Randomized` is a linear congruential generator rather than `System.Random`, because `new Random(seed)`
// declines on this emit path (NL103, emit.local.initializer) and an unseeded `Random` would not be a contract.
// The LCG's `state * 1103515245 + 12345` overflows every step; N# integer arithmetic wraps, which these files
// rely on and `ReductionFacts` pins directly.
class SampleData {

    // `data[k] = k * 3 - 7` — VectorizedReductionTests' primary reduction input, negative for small k.
    static func Ints(n: int): int[] {
        data := new int[n]
        for k := 0; k < n; k++ {
            data[k] = k * 3 - 7
        }
        return data
    }

    // `data[k] = k * 7 - 3` — the input of the a.Length-bound and braceless-body cases.
    static func IntsSeven(n: int): int[] {
        data := new int[n]
        for k := 0; k < n; k++ {
            data[k] = k * 7 - 3
        }
        return data
    }

    // `data[k] = k * 5 - 11` — the input of the non-zero-start cases.
    static func IntsFive(n: int): int[] {
        data := new int[n]
        for k := 0; k < n; k++ {
            data[k] = k * 5 - 11
        }
        return data
    }

    // An LCG stream with the two int extremes planted inside it, so a reduction has to survive both the
    // full signed range and the wrap that summing it produces.
    static func Randomized(n: int): int[] {
        data := new int[n]
        state := 20260901
        for k := 0; k < n; k++ {
            state = state * 1103515245 + 12345
            data[k] = state
        }
        if n > 3 {
            data[3] = int.MinValue
        }

        if n > 5 {
            data[5] = int.MaxValue
        }

        return data
    }

    // `data[k] = (long)k * 1000000007 - 7` — 64-bit magnitudes.
    static func Longs(n: int): long[] {
        data := new long[n]
        for k := 0; k < n; k++ {
            data[k] = (long)k * 1000000007 - 7
        }
        return data
    }

    // `data[k] = (uint)(k * 2000000011)` — the int multiply overflows before the cast, so the resulting
    // sequence exercises the mod-2^32 wrap of the uint accumulator.
    static func UInts(n: int): uint[] {
        data := new uint[n]
        for k := 0; k < n; k++ {
            data[k] = (uint)(k * 2000000011)
        }
        return data
    }

    // `data[k] = (ulong)k * 10^14`. Summed over 1000 elements that is ~5 * 10^19, past 2^64, so the ulong
    // accumulator wraps. (The multiplier is spelled as a product of two int-sized literals because a single
    // literal that large declines at emit.typed-local.initializer.)
    static func ULongs(n: int): ulong[] {
        data := new ulong[n]
        for k := 0; k < n; k++ {
            data[k] = (ulong)k * (ulong)100000 * (ulong)1000000000
        }
        return data
    }

    // `data[k] = k * 0.5 - 1` — the float reduction input.
    static func Floats(n: int): float[] {
        data := new float[n]
        for k := 0; k < n; k++ {
            data[k] = (float)k * 0.5f - 1.0f
        }
        return data
    }

    // `data[k] = k * 0.25 - 2` — the double reduction input.
    static func Doubles(n: int): double[] {
        data := new double[n]
        for k := 0; k < n; k++ {
            data[k] = (double)k * 0.25 - 2.0
        }
        return data
    }

    // RangePredicateCountVectorizationTests.AsciiLike: 0..255 with the two inclusive boundaries of [32, 126]
    // and their immediate neighbours planted, so an off-by-one in the masked compare is visible.
    static func AsciiLike(n: int): int[] {
        data := new int[n]
        for k := 0; k < n; k++ {
            data[k] = ((k * 17) + 3) & 0xff
        }
        if n > 0 {
            data[0] = 32
        }

        if n > 1 {
            data[1] = 126
        }

        if n > 2 {
            data[2] = 31
        }

        if n > 3 {
            data[3] = 127
        }

        return data
    }

    // The helper-edge-case cycle the deleted `CountInRangeHelperEdgeCaseTests` / `MinMaxHelperEdgeCaseTests` /
    // `CountTransitionsHelperEdgeCaseTests` used: eleven seeds spanning both int extremes, repeated. At 200
    // elements it is several vector widths plus a scalar tail on every lane width, so the answer for a range
    // never lives only on the tail.
    static func MixedExtremes(n: int): int[] {
        seeds := new int[11]
        seeds[0] = int.MinValue
        seeds[1] = -100
        seeds[2] = -50
        seeds[3] = -1
        seeds[4] = 0
        seeds[5] = 1
        seeds[6] = 50
        seeds[7] = 100
        seeds[8] = 105
        seeds[9] = 126
        seeds[10] = int.MaxValue
        data := new int[n]
        for k := 0; k < n; k++ {
            data[k] = seeds[k % 11]
        }
        return data
    }

    // MinMaxReductionVectorizationTests.SignedLike: a pseudo-signed spread whose global min and max are the
    // int extremes at interior positions, and whose seed a[0] is an ordinary interior value.
    static func SignedLike(n: int): int[] {
        data := new int[n]
        for k := 0; k < n; k++ {
            data[k] = (((k * 1103515245) + 12345) & 0x7fffffff) - 0x40000000
        }
        if n > 3 {
            data[3] = int.MinValue
        }

        if n > 5 {
            data[5] = int.MaxValue
        }

        if n > 0 {
            data[0] = 7
        }

        return data
    }

    // The long[] mirror of SignedLike, for the "a long[] array must not reach the int helper" contracts.
    static func SignedLongs(n: int): long[] {
        data := new long[n]
        for k := 0; k < n; k++ {
            data[k] = (long)((((k * 1103515245) + 12345) & 0x7fffffff) - 0x40000000)
        }
        if n > 0 {
            data[0] = (long)7
        }

        return data
    }

    // CountTransitionsVectorizationTests.RunsLike, kept byte for byte: values in 0..3 with the int extremes
    // planted mid-array. MEASURED CORRECTION to the deleted comment, which claimed "frequent repeats": this
    // LCG changes value at EVERY step, so the sequence has no adjacent repeats at all and every pair is a
    // transition. `RunsWithRepeats` below is the generator that actually exercises runs.
    static func RunsLike(n: int): int[] {
        data := new int[n]
        for k := 0; k < n; k++ {
            data[k] = (((k * 1103515245) + 12345) >> 16) & 0x3
        }
        if n > 4 {
            data[4] = int.MinValue
        }

        if n > 9 {
            data[9] = int.MaxValue
        }

        if n > 0 {
            data[0] = 7
        }

        return data
    }

    // A genuine run structure: three-element runs cycling through 0..3, with an EQUAL PAIR planted at the
    // int.MinValue extreme (positions 7 and 8) and int.MaxValue planted mid-array. `RunsLike` above is the
    // deleted generator kept byte for byte, but its LCG happens to change value at every step, so it has no
    // adjacent repeats at all; this one is what makes "counts adjacent differences, not elements" a claim
    // with teeth.
    static func RunsWithRepeats(n: int): int[] {
        data := new int[n]
        for k := 0; k < n; k++ {
            data[k] = (k / 3) & 0x3
        }
        if n > 8 {
            data[7] = int.MinValue
            data[8] = int.MinValue
        }

        if n > 20 {
            data[20] = int.MaxValue
        }

        return data
    }

    // The long[] mirror of RunsLike.
    static func RunsLongs(n: int): long[] {
        data := new long[n]
        for k := 0; k < n; k++ {
            data[k] = (long)((((k * 1103515245) + 12345) >> 16) & 0x3)
        }
        if n > 0 {
            data[0] = (long)7
        }

        return data
    }
}
