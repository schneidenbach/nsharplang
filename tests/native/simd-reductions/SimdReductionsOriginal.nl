namespace NSharpLang.SimdReductionsOriginal

import System
import NSharpLang.Runtime

// THE C# ORIGINAL, REACHED AS AN ORDINARY EXTERNAL DEPENDENCY.
//
// `SimdReductions.nl` is a translation, and a translation is only as good as the reference it is compared
// against, so the project takes a dll dependency on `NSharpLang.Runtime` and calls the REAL
// `NSharpLang.Runtime.SimdReductions` on the same inputs. Every call site for the original lives here, in
// one small file that imports `NSharpLang.Runtime` and does nothing else, so there is exactly one place to
// check when asking "is this really the C# implementation?" -- and `OriginalType()` answers it in metadata
// terms for the tests to pin.
//
// The forwarders are deliberately thin: argument in, result out, no arithmetic, so a parity failure is
// always the two implementations disagreeing rather than this file mediating.
//
// ON THE TUPLE-RETURNING PAIR. A named tuple is a `System.ValueTuple` plus a `TupleElementNamesAttribute`;
// the names are METADATA, and the fields are positionally `Item1` / `Item2`. N# does not yet read that
// attribute off an external member (`original.Min` on the C# method's result reports NL303 -- see the
// stream report), so the two forwarders below read the CLR fields positionally and re-declare the names.
// That positional mapping is not assumed: `SimdReductions.tests.nl` reads the ORIGINAL's
// `TupleElementNamesAttribute` out of metadata and pins that element 0 is `Min`/`Count` and element 1 is
// `Max`/`LastPrevious`, so if the C# author ever reordered them, the row that justifies these two lines
// fails before the parity rows do.
func OriginalSumInt32(values: int[], start: int, end: int): int {
    return SimdReductions.SumInt32(values, start, end)
}

func OriginalSumInt64(values: long[], start: int, end: int): long {
    return SimdReductions.SumInt64(values, start, end)
}

func OriginalSumUInt32(values: uint[], start: int, end: int): uint {
    return SimdReductions.SumUInt32(values, start, end)
}

func OriginalSumUInt64(values: ulong[], start: int, end: int): ulong {
    return SimdReductions.SumUInt64(values, start, end)
}

func OriginalCountInRangeInt32(values: int[], start: int, end: int, lo: int, hi: int): int {
    return SimdReductions.CountInRangeInt32(values, start, end, lo, hi)
}

func OriginalMinInt32(values: int[], start: int, end: int, seed: int): int {
    return SimdReductions.MinInt32(values, start, end, seed)
}

func OriginalMaxInt32(values: int[], start: int, end: int, seed: int): int {
    return SimdReductions.MaxInt32(values, start, end, seed)
}

func OriginalMinMaxInt32(values: int[], start: int, end: int, seedMin: int, seedMax: int): (Min: int, Max: int) {
    original := SimdReductions.MinMaxInt32(values, start, end, seedMin, seedMax)
    return (original.Item1, original.Item2)
}

func OriginalCountTransitionsInt32(values: int[], start: int, end: int, seedPrevious: int): (Count: int, LastPrevious: int) {
    original := SimdReductions.CountTransitionsInt32(values, start, end, seedPrevious)
    return (original.Item1, original.Item2)
}

// The original's CLR type, so the metadata rows can put the two signatures side by side. Spelled with its
// full namespace on purpose: a qualified `typeof` is the one form that cannot be captured by a same-named
// source type, and `SimdReductions.tests.nl` pins that what comes back really is the other assembly's.
func OriginalType(): Type {
    return typeof(NSharpLang.Runtime.SimdReductions)
}
