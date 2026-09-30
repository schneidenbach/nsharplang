namespace NSharpLang.Compiler.Columnar

import NSharpLang.Compiler


// THE CONTRACTS FOR `ColumnarDeclarationTokenEnd` AND `ColumnarDeclarationScratchCapacity`.
//
// A per-declaration kernel's scratch is sized by the declaration's extent, so an extent that ends
// SHORT is an index-out-of-range inside the parser and an extent that runs LONG is only a larger
// allocation. Every row below therefore pins where an extent ends against the token that must be
// the first one outside it, on the shapes that could cut it short: a multi-line signature, a `?[`
// that is one token, the modifiers ahead of `func`, a local function, an expression body holding
// braces, a bodiless member and a table-driven test.
class DeclarationScratchTokens {
    Source: string
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int
    constructor(source: string, kinds: int[], starts: int[], valueLengths: int[], count: int) {
        Source = source
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }

    // The index of the `occurrence`-th token (0-based) whose text is `spelling`.
    func IndexOf(spelling: string, occurrence: int): int {
        seen := 0
        i := 0
        while i < Count {
            if ValueLengths[i] == spelling.Length && string.CompareOrdinal(Source, Starts[i], spelling, 0, spelling.Length) == 0 {
                if seen == occurrence {
                    return i
                }
                seen = seen + 1
            }
            i = i + 1
        }

        return -1
    }
}

func DeclarationScratchTokenize(source: string): DeclarationScratchTokens {
    capacity := 3 * (source.Length + 1) + 8
    rawKinds := new int[](capacity)
    rawStarts := new int[](capacity)
    rawValueLengths := new int[](capacity)
    kinds := new int[](capacity)
    starts := new int[](capacity)
    valueLengths := new int[](capacity)
    counts := new int[](2)
    count := TokenizeColumnarSourceInto(source, rawKinds, rawStarts, rawValueLengths, kinds, starts, valueLengths, counts)
    return new DeclarationScratchTokens(source, kinds, starts, valueLengths, count)
}

func DeclarationScratchClassSource(): string {
    return "class Emitter {\n" + "    private static func Multi(\n" + "        items: Type?[],\n" + "        lookup: Dictionary<string, Type>[]\n" + "    ): bool {\n" + "        first := items?[0]\n" + "        func local(): int {\n" + "            return 1\n" + "        }\n" + "        return first != null\n" + "    }\n" + "\n" + "    func Shape(): Point => new Point { X: 1, Y: 2 }\n" + "\n" + "    Name: string\n" + "\n" + "    abstract func Slot(): int\n" + "}\n" + "\n" + "func after() {\n" + "}\n"
}

test "a block-bodied function ends at its matching brace, through a multi-line signature, a `?[` and a local function" {
    tokens := DeclarationScratchTokenize(DeclarationScratchClassSource())
    funcIndex := tokens.IndexOf("func", 0)
    closing := tokens.IndexOf("}", 1)
    assert funcIndex > 0
    assert tokens.Kinds[tokens.IndexOf("?[", 0)] == ColumnarTokenKindFacts.QuestionBracketKind
    assert ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, funcIndex) == closing + 1

    // The modifiers ahead of `func` are the head of the same declaration, not the end of one.
    privateIndex := tokens.IndexOf("private", 0)
    assert ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, privateIndex) == closing + 1

    // A body's own `{` starts the same extent.
    bodyBrace := tokens.IndexOf("{", 1)
    assert ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, bodyBrace) == closing + 1

    // And the signature kernel, whose scratch is now that extent's, still finds the body.
    declarationTokens := new ParserDeclarationTokenTable(tokens.Kinds, tokens.Starts, tokens.ValueLengths)
    assert ParseDeclarationFunctionSignatureEndCore(tokens.Source, declarationTokens, tokens.Count, funcIndex) == bodyBrace
}

test "an expression body runs to the next depth-0 `func`, over the braces of an object initializer" {
    tokens := DeclarationScratchTokenize(DeclarationScratchClassSource())
    shape := tokens.IndexOf("func", 2)
    slot := tokens.IndexOf("func", 3)
    assert ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, shape) == slot

    arrow := tokens.IndexOf("=>", 0)
    assert ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, arrow) == slot
}

test "a bodiless member ends at the brace that closes the type enclosing it" {
    tokens := DeclarationScratchTokenize(DeclarationScratchClassSource())
    slot := tokens.IndexOf("func", 3)
    classClosing := tokens.IndexOf("}", 3)
    assert ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, slot) == classClosing

    // And the type itself ends at that brace.
    assert ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, tokens.IndexOf("class", 0)) == classClosing + 1
}

test "a table-driven test's extent runs from its keyword through its rows to the end of its body" {
    source := "test \"adds\" with (a: int, b: int) [\n" + "    (1, 2),\n" + "    (3, 4)\n" + "] {\n" + "    assert a < b\n" + "}\n" + "\n" + "func after() {\n" + "}\n"
    tokens := DeclarationScratchTokenize(source)
    testIndex := tokens.IndexOf("test", 0)
    bodyClosing := tokens.IndexOf("}", 0)
    assert ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, testIndex) == bodyClosing + 1
}

test "the scratch capacity is four rows per token of the extent, and never more than the whole file's" {
    tokens := DeclarationScratchTokenize(DeclarationScratchClassSource())
    funcIndex := tokens.IndexOf("func", 0)
    extent := ColumnarDeclarationTokenEnd(tokens.Kinds, tokens.Count, funcIndex) - funcIndex
    capacity := ColumnarDeclarationScratchCapacity(tokens.Kinds, tokens.Count, funcIndex)
    assert capacity == 4 * (extent + 1) + 64 || capacity == tokens.Count + 1
    assert capacity <= tokens.Count + 1

    // An extent that cannot be measured keeps the whole-file bound.
    assert ColumnarDeclarationScratchCapacity(tokens.Kinds, tokens.Count, -1) == tokens.Count + 1
    assert ColumnarDeclarationScratchCapacity(tokens.Kinds, tokens.Count, tokens.Count) == tokens.Count + 1

    // In a large file the windowed capacity is the declaration's, not the file's.
    builder := new System.Text.StringBuilder()
    builder.Append("func first() {\n    x := 1\n}\n")
    index := 0
    while index < 400 {
        builder.Append("func filler" + index.ToString() + "(): int {\n    return " + index.ToString() + "\n}\n")
        index = index + 1
    }
    large := DeclarationScratchTokenize(builder.ToString())
    firstCapacity := ColumnarDeclarationScratchCapacity(large.Kinds, large.Count, large.IndexOf("func", 0))
    assert firstCapacity < 200, firstCapacity.ToString()
    assert firstCapacity < large.Count / 10, firstCapacity.ToString() + " of " + large.Count.ToString()
}

test "scratch shared across declarations is the largest one's, and rows accumulated across them their sum within the old bound" {
    tokens := DeclarationScratchTokenize(DeclarationScratchClassSource())
    starts := new int[](4)
    starts[0] = tokens.IndexOf("func", 0)
    starts[1] = tokens.IndexOf("func", 2)
    starts[2] = tokens.IndexOf("func", 3)
    starts[3] = tokens.IndexOf("func", 4)
    largest := ColumnarLargestDeclarationScratchCapacity(tokens.Kinds, tokens.Count, starts, 4)
    index := 0
    while index < 4 {
        assert largest >= ColumnarDeclarationScratchCapacity(tokens.Kinds, tokens.Count, starts[index])
        index = index + 1
    }

    accumulated := ColumnarAccumulatedDeclarationScratchCapacity(tokens.Kinds, tokens.Count, starts, 4, (tokens.Count + 1) * 4)
    assert accumulated <= (tokens.Count + 1) * 4
    assert accumulated >= largest
}
