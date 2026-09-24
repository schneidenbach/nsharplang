namespace NSharpLang.Compiler

import System.Collections.Generic

// `type` IS A CONTEXTUAL KEYWORD, AND THIS FILE IS THE ONE PLACE THAT SAYS WHAT IT LOOKS LIKE.
//
// The word opens exactly one production — a top-level type-alias declaration head, `type Name =
// Underlying` (and its `type Name = newtype Underlying` branded form). Everywhere else in the
// language it is an ordinary identifier: a member, a parameter, a local, a `for type in …` loop
// variable, and the member of `x.type`. `Lexer.KeywordTextForType` therefore has no arm for it and
// `Lexer.IsReservedKeyword` answers false, which is what keeps NL109 and the `for <keyword> in`
// report off it while both still fire for every word that IS reserved.
//
// TWO READINGS, ONE RULE. The tree parsers walk a `List<Token>`; the columnar walkers carry token
// KINDS as bare ints beside the source text. Both ask here, so the two pipelines cannot drift into
// disagreeing about where an alias declaration begins — which is the exact failure mode a word that
// is a keyword in one reading and an identifier in the other invites.
class TypeAliasKeywordFacts {

    // The word itself, written once. `Lexer` no longer holds it, so nothing else may spell it.
    static AliasKeyword: string => "type"

    static func NamesAliasKeyword(text: string): bool {
        return text == "type"
    }

    // THE HEAD IS THREE TOKENS: the word, the alias NAME, and the `=` that introduces the underlying
    // type. All three are required, because two of them are what tells the declaration apart from an
    // ordinary use of the same identifier — `type = 5` assigns to a local and `type: string` declares
    // a field, and neither may be read as a declaration head.
    static func IsAliasDeclarationHead(tokens: List<Token>, index: int): bool {
        if index < 0 || index >= tokens.Count {
            return false
        }

        if tokens[index].Type != TokenType.Identifier || !NamesAliasKeyword(tokens[index].Value) {
            return false
        }

        nameIndex := NextStructuralIndex(tokens, index)
        if nameIndex < 0 || tokens[nameIndex].Type != TokenType.Identifier {
            return false
        }

        assignIndex := NextStructuralIndex(tokens, nameIndex)
        if assignIndex < 0 {
            return false
        }

        return tokens[assignIndex].Type == TokenType.Assign
    }

    static func NextStructuralIndex(tokens: List<Token>, index: int): int {
        if index < 0 || index >= tokens.Count {
            return -1
        }

        scan := index + 1
        while scan < tokens.Count && tokens[scan].Type == TokenType.Newline {
            scan = scan + 1
        }

        if scan >= tokens.Count {
            return -1
        }

        return scan
    }

    // The columnar reading of the same three tokens. `Identifier` is kind 0, `Assign` is kind 93 and
    // `Newline` is kind 136 (Token.nl's `enum TokenType` ordinals; see ColumnarTokenKindFacts for why
    // those ordinals are the pipeline's currency).
    static func IsAliasDeclarationHeadAt(source: string, kinds: int[], starts: int[], lengths: int[], count: int, index: int): bool {
        if index < 0 || index >= count || kinds[index] != 0 {
            return false
        }

        if !SpanNamesAliasKeyword(source, starts[index], lengths[index]) {
            return false
        }

        nameIndex := NextColumnarStructuralIndex(kinds, count, index)
        if nameIndex < 0 || kinds[nameIndex] != 0 {
            return false
        }

        assignIndex := NextColumnarStructuralIndex(kinds, count, nameIndex)
        if assignIndex < 0 {
            return false
        }

        return kinds[assignIndex] == 93
    }

    static func NextColumnarStructuralIndex(kinds: int[], count: int, index: int): int {
        scan := index + 1
        while scan < count && kinds[scan] == 136 {
            scan = scan + 1
        }

        if scan >= count {
            return -1
        }

        return scan
    }

    // The span comparison is written against the source rather than materializing a string, because
    // every columnar walker that asks this question asks it of every identifier in the file.
    static func SpanNamesAliasKeyword(source: string, start: int, length: int): bool {
        if length != 4 || start < 0 || start + 4 > source.Length {
            return false
        }

        return source[start] == 't' && source[start + 1] == 'y' && source[start + 2] == 'p' && source[start + 3] == 'e'
    }
}
