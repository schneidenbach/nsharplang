namespace NSharpLang.Compiler

import System.Collections.Generic

// THE CONTRACTS FOR THE ONE OWNER THAT SAYS WHAT A CONTEXTUAL `type` LOOKS LIKE.
//
// Two readings of one rule live in `TypeAliasKeywordFacts`: a `List<Token>` reading for the tree
// parsers and a token-KINDS reading for the columnar declaration walkers. The rows below ask BOTH of
// every shape, because the failure this owner exists to prevent is the two pipelines disagreeing
// about where a type-alias declaration begins — one reading the word as a declaration head and the
// other as an identifier, in the same file.
func TakfTokens(source: string): List<Token> {
    lexer := new Lexer(source, "takf.nl")
    return lexer.Tokenize()
}

// The columnar reading, asked through the real columnar tokenizer rather than through a copy of its
// table, so a change to what the columnar lexer writes for `type` fails here.
func TakfColumnarIsAliasHead(source: string, index: int): bool {
    capacity := source.Length * 3 + 16
    rawKinds := new int[](capacity)
    rawStarts := new int[](capacity)
    rawLengths := new int[](capacity)
    kinds := new int[](capacity)
    starts := new int[](capacity)
    lengths := new int[](capacity)
    counts := new int[](2)
    count := TokenizeColumnarSourceInto(source, rawKinds, rawStarts, rawLengths, kinds, starts, lengths, counts)
    if count < 1 {
        return false
    }

    return TypeAliasKeywordFacts.IsAliasDeclarationHeadAt(source, kinds, starts, lengths, count, index)
}

test "the word is spelled in exactly one place, and the lexer no longer holds it" {
    assert TypeAliasKeywordFacts.AliasKeyword == "type"
    assert TypeAliasKeywordFacts.NamesAliasKeyword("type")

    // THE DEMOTION ITSELF. `Lexer.IsReservedKeyword` is defined as "`KeywordTextForType` answers",
    // so an empty answer for `TokenType.Type` IS what makes `type` an ordinary identifier — and it
    // is what keeps NL109 and the `for <keyword> in` report off it.
    assert Lexer.KeywordTextForType(TokenType.Type) == ""
    assert !Lexer.IsReservedKeyword(TokenType.Type)
    assert Lexer.KeywordTypeForText("type") == TokenType.Identifier

    // The neighbours a demotion must not take with it.
    assert Lexer.IsReservedKeyword(TokenType.Newtype)
    assert Lexer.IsReservedKeyword(TokenType.Lock)
    assert Lexer.KeywordTypeForText("newtype") == TokenType.Newtype
}

test "a lookalike is not the word" {
    assert !TypeAliasKeywordFacts.NamesAliasKeyword("typed")
    assert !TypeAliasKeywordFacts.NamesAliasKeyword("Type")
    assert !TypeAliasKeywordFacts.NamesAliasKeyword("typ")
    assert !TypeAliasKeywordFacts.NamesAliasKeyword("_type")
    assert !TypeAliasKeywordFacts.NamesAliasKeyword("")

    // The span reading must agree with the string reading, including about length: reading four
    // characters out of a longer identifier is exactly how a lookalike becomes a false head.
    assert TypeAliasKeywordFacts.SpanNamesAliasKeyword("type", 0, 4)
    assert !TypeAliasKeywordFacts.SpanNamesAliasKeyword("typed", 0, 5)
    assert !TypeAliasKeywordFacts.SpanNamesAliasKeyword("Type", 0, 4)
    assert !TypeAliasKeywordFacts.SpanNamesAliasKeyword("typ", 0, 3)
    assert !TypeAliasKeywordFacts.SpanNamesAliasKeyword("type", 0, 5)
    assert !TypeAliasKeywordFacts.SpanNamesAliasKeyword("type", -1, 4)
}

test "the head is the word, a name and an `=` — in both readings" {
    tokens := TakfTokens("type UserId = int")
    assert TypeAliasKeywordFacts.IsAliasDeclarationHead(tokens, 0)
    assert TakfColumnarIsAliasHead("type UserId = int", 0)

    // The branded form is the same head; `newtype` sits AFTER the `=`.
    brandedTokens := TakfTokens("type Email = newtype string")
    assert TypeAliasKeywordFacts.IsAliasDeclarationHead(brandedTokens, 0)
    assert TakfColumnarIsAliasHead("type Email = newtype string", 0)
}

test "two of the three tokens are what tells a declaration from a use" {
    // A FIELD OR A PARAMETER: `type` then `:`, not a name.
    fieldTokens := TakfTokens("type: string")
    assert !TypeAliasKeywordFacts.IsAliasDeclarationHead(fieldTokens, 0)
    assert !TakfColumnarIsAliasHead("type: string", 0)

    // AN ASSIGNMENT TO A LOCAL CALLED `type`: the word then `=`, with no name between. Reading this
    // as a declaration head is the mistake that would swallow the statement.
    assignmentTokens := TakfTokens("type = 6")
    assert !TypeAliasKeywordFacts.IsAliasDeclarationHead(assignmentTokens, 0)
    assert !TakfColumnarIsAliasHead("type = 6", 0)

    // AN INFERRED DECLARATION: `:=` is its own token, not an `=`.
    inferredTokens := TakfTokens("type := 5")
    assert !TypeAliasKeywordFacts.IsAliasDeclarationHead(inferredTokens, 0)
    assert !TakfColumnarIsAliasHead("type := 5", 0)

    // A COMPARISON reads `==`, which is also not an `=`.
    comparisonTokens := TakfTokens("type == 5")
    assert !TypeAliasKeywordFacts.IsAliasDeclarationHead(comparisonTokens, 0)
    assert !TakfColumnarIsAliasHead("type == 5", 0)

    // THE WORD ALONE, at the end of the file, has no head to complete.
    loneTokens := TakfTokens("type")
    assert !TypeAliasKeywordFacts.IsAliasDeclarationHead(loneTokens, 0)
    assert !TakfColumnarIsAliasHead("type", 0)

    // AND ANOTHER IDENTIFIER IS NEVER A HEAD, whatever follows it.
    otherTokens := TakfTokens("kind Other = int")
    assert !TypeAliasKeywordFacts.IsAliasDeclarationHead(otherTokens, 0)
    assert !TakfColumnarIsAliasHead("kind Other = int", 0)
}

test "an out-of-range index answers no rather than throwing" {
    tokens := TakfTokens("type UserId = int")
    assert !TypeAliasKeywordFacts.IsAliasDeclarationHead(tokens, -1)
    assert !TypeAliasKeywordFacts.IsAliasDeclarationHead(tokens, tokens.Count)
    assert !TakfColumnarIsAliasHead("type UserId = int", -1)
    assert !TakfColumnarIsAliasHead("type UserId = int", 900)
}
