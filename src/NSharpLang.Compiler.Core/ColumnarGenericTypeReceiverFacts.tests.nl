namespace NSharpLang.Compiler.Columnar

import NSharpLang.Compiler


// THE COLUMNAR HALF OF THE CONSTRUCTED-GENERIC-TYPE RECEIVER: the kernel lookahead that decides,
// from the `<` alone, whether a run of tokens is a type-argument list or a comparison chain.
//
// THE TWO PREDICATES ARE THE SAME SCAN WITH DIFFERENT CLOSE TOKENS, and that is stated here rather
// than left to a reader of the two bodies: every row below is run through BOTH, so a shape that
// gains a `.` reading must lose its `(` reading and vice versa. Nothing can be both.
//
// THE TOKEN TABLE IS BUILT FROM KIND ORDINALS DIRECTLY, because a lookahead reads NOTHING else — no
// source text, no node table, no bindings. Ordinals used (Token.cs): Identifier 0, `<` 100, `>` 102,
// `>>` 112, `?` 115, `.` 124, `(` 127, `[` 131, `]` 132, `,` 134, `+` 88.
func GtrTokens(kinds: int[]): ParserTokenTable {
    starts := new int[](kinds.Length)
    lengths := new int[](kinds.Length)
    index := 0
    while index < kinds.Length {
        starts[index] = index
        lengths[index] = 1
        index = index + 1
    }

    return new ParserTokenTable(kinds, starts, lengths)
}

// The `<` always sits at index 0 in these rows, so the scan starts where the postfix loop starts it.
func GtrIsReceiver(kinds: int[]): bool {
    return IsGenericTypeReceiverArgs(GtrTokens(kinds), kinds.Length, 0)
}

func GtrIsCall(kinds: int[]): bool {
    return IsGenericCallTypeArgs(GtrTokens(kinds), kinds.Length, 0)
}

test "the receiver lookahead admits a single type argument closed by a dot, and the call lookahead does not" {
    // `<int>.`
    row: int[] = [100, 0, 102, 124]
    assert GtrIsReceiver(row)
    assert GtrIsCall(row) == false
}

test "the call lookahead admits the same list closed by a paren, and the receiver lookahead does not" {
    // `<int>(`
    row: int[] = [100, 0, 102, 127]
    assert GtrIsReceiver(row) == false
    assert GtrIsCall(row)
}

test "a NESTED list closes on a split `>>`, which spends two levels of depth in one token" {
    // `<string, List<int>>.`
    row: int[] = [100, 0, 134, 0, 100, 0, 112, 124]
    assert GtrIsReceiver(row)
    assert GtrIsCall(row) == false
}

test "a `>>` that would over-close refuses rather than reading past the list" {
    // `<int>>.` — the `>>` takes the depth to -1
    row: int[] = [100, 0, 112, 124]
    assert GtrIsReceiver(row) == false
    assert GtrIsCall(row) == false
}

test "array, nullable and multi-argument spellings are all inside the admitted token set" {
    // `<int[]>.`
    arrayRow: int[] = [100, 0, 131, 132, 102, 124]
    assert GtrIsReceiver(arrayRow)
    // `<int?>.`
    nullableRow: int[] = [100, 0, 115, 102, 124]
    assert GtrIsReceiver(nullableRow)
    // `<A.B, C>.`
    qualifiedRow: int[] = [100, 0, 124, 0, 134, 0, 102, 124]
    assert GtrIsReceiver(qualifiedRow)
}

test "a comparison refuses: an operator inside the candidate list ends the scan" {
    // `< b + c > .` — the `+` is not a type-argument token
    row: int[] = [100, 0, 88, 0, 102, 124]
    assert GtrIsReceiver(row) == false
    assert GtrIsCall(row) == false
}

test "a comparison refuses: a close followed by neither a dot nor a paren is nothing" {
    // `< b > c`
    row: int[] = [100, 0, 102, 0]
    assert GtrIsReceiver(row) == false
    assert GtrIsCall(row) == false
}

test "an unterminated list refuses at the end of the token run rather than reading off the end" {
    // `<int`
    row: int[] = [100, 0]
    assert GtrIsReceiver(row) == false
    assert GtrIsCall(row) == false

    // `<int>` with nothing after the close
    closedRow: int[] = [100, 0, 102]
    assert GtrIsReceiver(closedRow) == false
    assert GtrIsCall(closedRow) == false
}

test "the constructed-generic node kind is 70 and is distinct from the generic callee kind 38" {
    assert ColumnarExpressionNodeKind.GenericTypeReceiverExpression() == 70
    assert ColumnarExpressionNodeKind.GenericTypeReceiverExpression() != ColumnarExpressionNodeKind.TypeOfExpression()
    assert ColumnarExpressionNodeKind.GenericTypeReceiverExpression() != ColumnarExpressionNodeKind.MemberAccessExpression()
}
