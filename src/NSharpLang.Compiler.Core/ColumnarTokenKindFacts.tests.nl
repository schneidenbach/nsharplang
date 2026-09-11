namespace NSharpLang.Compiler

import System


// THE CANONICAL CONTRACTS FOR `ColumnarTokenKindFacts`, AND THE DRIFT PIN THAT IS THE WHOLE POINT
// OF IT EXISTING.
//
// `ColumnarProgramInputBuilder.cs` used to decide four SHAPES — is this a `ref struct`, is this
// constructor the synthesized primary constructor, may this token open a function/getter body, may
// this token open a constructor/setter body — by comparing the columnar `ck[]` column to integer
// literals `78`, `8`/`9`/`13`, `129` and `120`, in C#. Those literals are POSITIONS IN AN N# ENUM
// THAT THE C# DOES NOT IMPORT. This is the TokenType-ordinal hazard that has bitten this repo
// before: insert one case into `TokenType` and every one of those literals silently means something
// else, with nothing failing.
//
// TWO TABLES REALLY DEFINE THOSE ORDINALS, AND BOTH ARE N#. (1) `Token.nl`'s `enum TokenType`,
// whose member ORDER *is* the numbering — the tree lexer, the parser, the formatter and the LSP all
// speak it. (2) The COLUMNAR lexer, which never sees the enum: `KeywordKind` and
// `TokenizeMetadataCore` (`CompilerServices/ColumnarParserKernels.nl`) hand-write the same numbers
// into `ck[]`. The C# literals were a THIRD copy. This file deletes the third copy's excuse by
// pinning the surviving two to each other through ONE named ordinal per token:
//
//   * `Convert.ToInt32(TokenType.Ref) == ColumnarTokenKindFacts.RefKind` pins TABLE 1. Reorder the
//     enum and this fails, naming the member.
//   * `TokenKindFactsColumnarKindOf("ref") == ColumnarTokenKindFacts.RefKind` pins TABLE 2. Change
//     what the columnar lexer writes for `ref` and this fails, naming the spelling.
//   * `ColumnarTokenKindFacts.RefKind == 78` pins the owner's own literal, so an ordinal SWAP fails
//     here first rather than as a wrong answer three layers downstream.
//
// THE NEGATIVE HALF IS NOT DECORATION. `Ref` is 78 and `Out` is 79: an off-by-one in either
// direction lands on a real token, so the decisions are also proved to REJECT their neighbours.
// Without that, a swap could still satisfy every positive row.
//
// `Convert.ToInt32` is how an ordinal is read here. It is the only enum-to-int form the columnar
// backend emits — `x as int`, `int(x)`, `TokenType(78)` and `enumValue == 78` were each probed and
// each declined or failed analysis — and it is why this pin can exist at all.

// The kind the COLUMNAR lexer writes for a spelling, read out of the compacted column the parser
// kernels consume. `-1` means the tokenizer produced nothing, which is itself a failure worth
// seeing.
func TokenKindFactsColumnarKindOf(spelling: string): int {
    capacity := spelling.Length * 3 + 16
    rawKinds := new int[](capacity)
    rawStarts := new int[](capacity)
    rawValueLengths := new int[](capacity)
    kinds := new int[](capacity)
    starts := new int[](capacity)
    valueLengths := new int[](capacity)
    counts := new int[](2)
    count := TokenizeColumnarSourceInto(spelling, rawKinds, rawStarts, rawValueLengths, kinds, starts, valueLengths, counts)
    if count < 1 {
        return -1
    }

    return kinds[0]
}

test "every columnar token ordinal is the TokenType member it claims to be, and is the literal it claims to be" {
    // TABLE 1 — the enum whose member order defines the numbering.
    assert Convert.ToInt32(TokenType.Class) == ColumnarTokenKindFacts.ClassKind
    assert Convert.ToInt32(TokenType.Struct) == ColumnarTokenKindFacts.StructKind
    assert Convert.ToInt32(TokenType.Record) == ColumnarTokenKindFacts.RecordKind
    assert Convert.ToInt32(TokenType.Ref) == ColumnarTokenKindFacts.RefKind
    assert Convert.ToInt32(TokenType.Arrow) == ColumnarTokenKindFacts.ArrowKind
    assert Convert.ToInt32(TokenType.LeftBrace) == ColumnarTokenKindFacts.LeftBraceKind

    // The owner's own literals. A swap between any two of these fails HERE.
    assert ColumnarTokenKindFacts.ClassKind == 8
    assert ColumnarTokenKindFacts.StructKind == 9
    assert ColumnarTokenKindFacts.RecordKind == 13
    assert ColumnarTokenKindFacts.RefKind == 78
    assert ColumnarTokenKindFacts.ArrowKind == 120
    assert ColumnarTokenKindFacts.LeftBraceKind == 129

    // All six are distinct: a swap that preserved a pair would otherwise pass the rows above.
    assert ColumnarTokenKindFacts.ClassKind != ColumnarTokenKindFacts.StructKind
    assert ColumnarTokenKindFacts.StructKind != ColumnarTokenKindFacts.RecordKind
    assert ColumnarTokenKindFacts.RecordKind != ColumnarTokenKindFacts.RefKind
    assert ColumnarTokenKindFacts.RefKind != ColumnarTokenKindFacts.ArrowKind
    assert ColumnarTokenKindFacts.ArrowKind != ColumnarTokenKindFacts.LeftBraceKind
}

test "the columnar lexer writes those same six ordinals for the spellings they name" {
    // TABLE 2 — the hand-written numbering inside the columnar lexer, reached through the real
    // tokenizer rather than through a copy of its table.
    assert TokenKindFactsColumnarKindOf("class") == ColumnarTokenKindFacts.ClassKind
    assert TokenKindFactsColumnarKindOf("struct") == ColumnarTokenKindFacts.StructKind
    assert TokenKindFactsColumnarKindOf("record") == ColumnarTokenKindFacts.RecordKind
    assert TokenKindFactsColumnarKindOf("ref") == ColumnarTokenKindFacts.RefKind
    assert TokenKindFactsColumnarKindOf("=>") == ColumnarTokenKindFacts.ArrowKind
    assert TokenKindFactsColumnarKindOf("{") == ColumnarTokenKindFacts.LeftBraceKind

    // And the neighbours the decisions must never confuse them with.
    assert Convert.ToInt32(TokenType.Out) == 79
    assert TokenKindFactsColumnarKindOf("out") == 79
    assert Convert.ToInt32(TokenType.Interface) == 10
    assert TokenKindFactsColumnarKindOf("interface") == 10
}

test "`ref struct` is decided by TokenType.Ref, and by nothing beside it" {
    assert ColumnarTokenKindFacts.IsRefStructModifierKind(TokenKindFactsColumnarKindOf("ref"))
    assert ColumnarTokenKindFacts.IsRefStructModifierKind(Convert.ToInt32(TokenType.Ref))

    // `Out` is 78 + 1 and `Newtype` is 78 + 12: an off-by-one in either direction lands on a real
    // token, so rejecting the neighbour is what makes the positive row mean something.
    assert !ColumnarTokenKindFacts.IsRefStructModifierKind(Convert.ToInt32(TokenType.Out))
    assert !ColumnarTokenKindFacts.IsRefStructModifierKind(Convert.ToInt32(TokenType.Readonly))
    assert !ColumnarTokenKindFacts.IsRefStructModifierKind(Convert.ToInt32(TokenType.Struct))
    assert !ColumnarTokenKindFacts.IsRefStructModifierKind(Convert.ToInt32(TokenType.Identifier))
    assert !ColumnarTokenKindFacts.IsRefStructModifierKind(-1)
}

test "a synthesized primary constructor is the three declaration keywords, and only those three" {
    assert ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.Class))
    assert ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.Struct))
    assert ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.Record))
    assert ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(TokenKindFactsColumnarKindOf("class"))
    assert ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(TokenKindFactsColumnarKindOf("struct"))
    assert ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(TokenKindFactsColumnarKindOf("record"))

    // The other declaration keywords bracket 8/9/13 on both sides — `Func` is 7, `Interface` 10,
    // `Duck` 11, `Union` 12, `Enum` 14 — so a one-place shift of the enum would be caught by these.
    assert !ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.Func))
    assert !ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.Interface))
    assert !ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.Duck))
    assert !ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.Union))
    assert !ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.Enum))
    assert !ColumnarTokenKindFacts.IsSynthesizedPrimaryConstructorKind(Convert.ToInt32(TokenType.LeftParen))
}

test "a function or getter body opens with `{` or `=>`; a constructor or setter body opens with `{` only" {
    assert ColumnarTokenKindFacts.IsSupportedBodyStartKind(Convert.ToInt32(TokenType.LeftBrace))
    assert ColumnarTokenKindFacts.IsSupportedBodyStartKind(Convert.ToInt32(TokenType.Arrow))
    assert ColumnarTokenKindFacts.IsSupportedBodyStartKind(TokenKindFactsColumnarKindOf("{"))
    assert ColumnarTokenKindFacts.IsSupportedBodyStartKind(TokenKindFactsColumnarKindOf("=>"))

    assert ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(Convert.ToInt32(TokenType.LeftBrace))
    assert ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(TokenKindFactsColumnarKindOf("{"))

    // THE TWO DECISIONS ARE NOT THE SAME DECISION. An expression body opens a function or a getter
    // and must NOT open a constructor or a setter, neither of which produces a value. Collapsing
    // them would be invisible to every positive row above.
    assert !ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(Convert.ToInt32(TokenType.Arrow))

    // `RightBrace` is `LeftBrace` + 1 and `ColonAssign` is `Arrow` + 1; `Assign` (`=`) is the token
    // a mistyped expression body actually produces.
    assert !ColumnarTokenKindFacts.IsSupportedBodyStartKind(Convert.ToInt32(TokenType.RightBrace))
    assert !ColumnarTokenKindFacts.IsSupportedBodyStartKind(Convert.ToInt32(TokenType.ColonAssign))
    assert !ColumnarTokenKindFacts.IsSupportedBodyStartKind(Convert.ToInt32(TokenType.Assign))
    assert !ColumnarTokenKindFacts.IsSupportedBodyStartKind(Convert.ToInt32(TokenType.Semicolon))
    assert !ColumnarTokenKindFacts.IsSupportedBodyStartKind(-1)
    assert !ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(Convert.ToInt32(TokenType.RightBrace))
    assert !ColumnarTokenKindFacts.IsSupportedBlockBodyStartKind(-1)
}
