namespace NSharpLang.Compiler.Columnar

import System
import System.Text


// THE FLATTENING CONTRACT FOR `TupleElementNamesAttribute`, PINNED AGAINST THE C# COMPILER.
//
// Every expected row below was read out of an assembly the C# compiler produced for the same written
// type, so these are not a restatement of the implementation: they are the other language's answer.
// The shapes that were measured, and what each one proves:
//
//   (int Min, int Max)                          -> ["Min", "Max"]              the ordinary case
//   (int, int)                                  -> no attribute                nothing named
//   (int A, int)                                -> ["A", null]                 partial naming
//   (int A, (int B, int C) D)                   -> ["A", "D", "B", "C"]        OUTER NAMES FIRST
//   ((int B, int C) D, int A)                   -> ["D", "A", "B", "C"]        order is positional
//   ((int, int) X, int Y)                       -> ["X", "Y", null, null]      unnamed nested still occupies slots
//   List<(int Min, int Max)>                    -> ["Min", "Max"]              generic argument position
//   (List<(int L1, int L2)> M, int N)           -> ["M", "N", "L1", "L2"]      names first, then INTO the argument
//   Dictionary<(int K1,int K2),(int V1,int V2)> -> ["K1","K2","V1","V2"]       both arguments, in order
//   (int Min, int Max)[]                        -> ["Min", "Max"]              array element
//   eight named elements                        -> the eight names PLUS a null the ValueTuple REST nesting
//   ten named elements                          -> the ten names PLUS three    a three-element rest
//
// THE TWO THINGS THAT ARE EASY TO GET WRONG:
//
// (1) THE WALK IS NOT DEPTH-FIRST-BY-ELEMENT. `(int A, (int B, int C) D)` is `A, D, B, C` -- a
// reader who finishes each element before moving to the next produces `A, B, C, D`, which C# reads
// back as a four-element tuple's names. Every nested row below exists to catch that.
//
// (2) A TUPLE LONGER THAN SEVEN ELEMENTS CARRIES MORE STRINGS THAN IT HAS ELEMENTS. The eighth
// `ValueTuple` field is a nested `ValueTuple` holding the tail, and that nested tuple is itself a
// tuple: it contributes one unnamed slot per element it carries. Eight elements is nine strings.

// The flattened names as one readable row: `-` for a slot the source left unnamed, and the empty
// string when nothing was named at all (the "emit no attribute" answer).
func TupleNameRow(labeledCanonical: string): string {
    names := ColumnarTupleElementNames.Flatten(labeledCanonical)
    if names == null {
        return ""
    }

    builder := new StringBuilder()
    index := 0
    while index < names.Length {
        if index > 0 {
            builder.Append('/')
        }

        if names[index].Length == 0 {
            builder.Append('-')
        } else {
            builder.Append(names[index])
        }

        index = index + 1
    }

    return builder.ToString()
}

// ---- the ordinary shapes -------------------------------------------------------------------------

test "a fully named tuple flattens to its element names in order" {
    assert TupleNameRow("(Min:int,Max:int)") == "Min/Max"
    assert TupleNameRow("(First:string,Second:int,Third:double)") == "First/Second/Third"
}

test "a tuple with no named element flattens to nothing, which is the no-attribute answer" {
    assert ColumnarTupleElementNames.Flatten("(int,int)") == null
    assert ColumnarTupleElementNames.Flatten("int") == null
    assert ColumnarTupleElementNames.Flatten("List<int>") == null
    assert ColumnarTupleElementNames.Flatten("") == null
    assert ColumnarTupleElementNames.Flatten("void") == null
}

test "a partially named tuple keeps a slot for the unnamed element" {
    assert TupleNameRow("(A:int,int)") == "A/-"
    assert TupleNameRow("(int,B:int)") == "-/B"
}

// ---- nesting -------------------------------------------------------------------------------------

test "a nested tuple contributes its names AFTER the outer tuple's, not in element order" {
    assert TupleNameRow("(A:int,D:(B:int,C:int))") == "A/D/B/C"
}

test "the outer names come first even when the nested tuple is the first element" {
    assert TupleNameRow("(D:(B:int,C:int),A:int)") == "D/A/B/C"
}

test "an unnamed nested tuple still occupies one slot per element" {
    assert TupleNameRow("(X:(int,int),Y:int)") == "X/Y/-/-"
}

test "a tuple nested two deep is reached after both levels above it" {
    assert TupleNameRow("(A:int,B:(C:int,D:(E:int,F:int)))") == "A/B/C/D/E/F"
}

// ---- generic arguments, arrays, by-ref, nullable -------------------------------------------------

test "a tuple in a generic argument position is reached through the head, which names nothing" {
    assert TupleNameRow("List<(Min:int,Max:int)>") == "Min/Max"
}

test "every generic argument is walked, in written order" {
    assert TupleNameRow("Dictionary<(K1:int,K2:int),(V1:int,V2:int)>") == "K1/K2/V1/V2"
    assert TupleNameRow("Func<(F1:int,F2:int),(G1:int,G2:int)>") == "F1/F2/G1/G2"
}

test "a tuple element that is a generic over a tuple names the element first and descends after" {
    assert TupleNameRow("(M:List<(L1:int,L2:int)>,N:int)") == "M/N/L1/L2"
}

test "array, nullable and by-ref spellings are transparent to the walk" {
    assert TupleNameRow("(Min:int,Max:int)[]") == "Min/Max"
    assert TupleNameRow("(Min:int,Max:int)?") == "Min/Max"
    assert TupleNameRow("&(Min:int,Max:int)") == "Min/Max"
    assert TupleNameRow("List<(Min:int,Max:int)>[]") == "Min/Max"
}

// ---- the ValueTuple rest nesting -----------------------------------------------------------------

test "a seven element tuple carries exactly seven strings, with no rest tuple" {
    assert TupleNameRow("(A:int,B:int,C:int,D:int,E:int,F:int,G:int)") == "A/B/C/D/E/F/G"
}

test "an eight element tuple carries nine strings, the ninth belonging to the rest tuple" {
    assert TupleNameRow("(A:int,B:int,C:int,D:int,E:int,F:int,G:int,H:int)") == "A/B/C/D/E/F/G/H/-"
}

test "a ten element tuple carries thirteen strings, three for the rest tuple's own elements" {
    assert TupleNameRow("(A:int,B:int,C:int,D:int,E:int,F:int,G:int,H:int,I:int,J:int)") == "A/B/C/D/E/F/G/H/I/J/-/-/-"
}

test "a fifteen element tuple nests a rest tuple inside a rest tuple" {
    // Fifteen names, then the eight-element rest tuple's eight slots, then ITS one-element rest.
    assert TupleNameRow("(A:int,B:int,C:int,D:int,E:int,F:int,G:int,H:int,I:int,J:int,K:int,L:int,M:int,N:int,O:int)") == "A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/-/-/-/-/-/-/-/-/-"
}

// ---- the shapes deliberately NOT descended into --------------------------------------------------

test "an anonymous union arm is not a signature position, so a tuple inside one names nothing" {
    assert ColumnarTupleElementNames.Flatten("(A:int,B:int)|string") == null
}

test "a colon that is not a bare identifier label belongs to the element type, not to the element" {
    // The nested tuple's own `c:` label sits inside the element, so the element itself is unnamed --
    // the same rule `ColumnarTypeCanonicalizer.StripTupleElementNames` applies at the top level.
    assert TupleNameRow("((c:int,d:int),int)") == "-/-/c/d"
}

// ---- HasAnyName ----------------------------------------------------------------------------------

test "HasAnyName answers the same question Flatten answers with null" {
    assert !ColumnarTupleElementNames.HasAnyName(null)
    assert !ColumnarTupleElementNames.HasAnyName(new string[](0))
    assert !ColumnarTupleElementNames.HasAnyName([ColumnarTupleElementNames.Unnamed, ColumnarTupleElementNames.Unnamed])
    assert ColumnarTupleElementNames.HasAnyName([ColumnarTupleElementNames.Unnamed, "Max"])
}

// ---- the blob ------------------------------------------------------------------------------------
//
// Each expected byte string below was read out of the C# compiler's own metadata for the matching
// written type, with `MetadataReader.GetBlobBytes` -- prologue 01 00, a four-byte little-endian
// element count, one SerString per element (0xFF for a null), and the two-byte named-argument count.

func TupleNameBlobText(bytes: byte[]): string {
    digits := "0123456789ABCDEF"
    builder := new StringBuilder()
    index := 0
    while index < bytes.Length {
        if index > 0 {
            builder.Append(' ')
        }

        value := Convert.ToInt32(bytes[index])
        builder.Append(digits[value / 16])
        builder.Append(digits[value % 16])
        index = index + 1
    }

    return builder.ToString()
}

func TupleNameBlobRow(labeledCanonical: string): string {
    names := ColumnarTupleElementNames.Flatten(labeledCanonical)
    if names == null {
        return ""
    }

    return TupleNameBlobText(ColumnarTupleElementNames.Blob(names))
}

test "the blob for a fully named pair is what the C# compiler writes for (int Min, int Max)" {
    assert TupleNameBlobRow("(Min:int,Max:int)") == "01 00 02 00 00 00 03 4D 69 6E 03 4D 61 78 00 00"
}

test "an unnamed slot is the metadata null string, exactly as C# writes (int A, int)" {
    assert TupleNameBlobRow("(A:int,int)") == "01 00 02 00 00 00 01 41 FF 00 00"
}

test "the blob for a nested pair is the flattened order C# writes for (int A, (int B, int C) D)" {
    assert TupleNameBlobRow("(A:int,D:(B:int,C:int))") == "01 00 04 00 00 00 01 41 01 44 01 42 01 43 00 00"
}

test "the blob for an eight element tuple carries the nine strings C# writes" {
    assert TupleNameBlobRow("(A:int,B:int,C:int,D:int,E:int,F:int,G:int,H:int)") == "01 00 09 00 00 00 01 41 01 42 01 43 01 44 01 45 01 46 01 47 01 48 FF 00 00"
}

test "the blob for an unnamed nested tuple carries the two nulls C# writes for ((int, int) X, int Y)" {
    assert TupleNameBlobRow("(X:(int,int),Y:int)") == "01 00 04 00 00 00 01 58 01 59 FF FF 00 00"
}

test "the element count is a plain four byte little endian integer, not a compressed one" {
    // 128 elements would take a two-byte PackedLen if the count were compressed; it does not.
    names := new string[](128)
    index := 0
    while index < names.Length {
        names[index] = ColumnarTupleElementNames.Unnamed
        index = index + 1
    }

    names[0] = "A"
    blob := ColumnarTupleElementNames.Blob(names)
    assert Convert.ToInt32(blob[2]) == 128
    assert Convert.ToInt32(blob[3]) == 0
    assert Convert.ToInt32(blob[4]) == 0
    assert Convert.ToInt32(blob[5]) == 0
}
