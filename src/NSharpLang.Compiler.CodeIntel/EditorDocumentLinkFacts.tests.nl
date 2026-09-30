namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler

// CONTRACTS FOR WHERE A FILE OFFERS SOMETHING TO CLICK. These came out of `DocumentLinkHandler.cs`:
// which token kinds are searched at all, the walk that places a link found on the third line of a
// block comment, the two sources reported tokens-first, and where the match is cut off.
func EdlToken(kind: TokenType, value: string, line: int, column: int): Token {
    return new Token(kind, value, line, column, "Probe.nl", true)
}

func EdlTokens(tokens: Token[]): List<Token> {
    list := new List<Token>()
    for token in tokens {
        list.Add(token)
    }
    return list
}

func EdlComments(comments: CommentTrivia[]): List<CommentTrivia> {
    list := new List<CommentTrivia>()
    for comment in comments {
        list.Add(comment)
    }
    return list
}

// ONLY THREE TOKEN KINDS CARRY LINKS. An identifier that happens to spell a URL is code, not a
// link, and the XML doc comment is NOT searched — that is the shipped answer, recorded so it
// cannot change by accident.
test "a document link is looked for in comments and string literals and nowhere else" {
    tokens := EdlTokens([
        EdlToken(TokenType.Comment, "// see https://a.example/one", 1, 1),
        EdlToken(TokenType.StringLiteral, "\"https://a.example/two\"", 2, 5),
        EdlToken(TokenType.XmlDocComment, "/// https://a.example/three", 3, 1),
        EdlToken(TokenType.Identifier, "https://a.example/four", 4, 1)
    ])

    rows := EditorDocumentLinkFacts.LinkRows(tokens, null)
    assert rows.Count == 2
    assert rows[0].Text == "https://a.example/one"
    assert rows[1].Text == "https://a.example/two"
}

// THE SPAN IS 0-BASED AND MEASURED FROM WHERE THE TOKEN ITSELF BEGINS, so a link inside a string
// literal is underlined where the reader sees it and not where the literal starts.
test "a document link is placed relative to the token that contains it" {
    tokens := EdlTokens([EdlToken(TokenType.StringLiteral, "\"go to https://a.example/x now\"", 7, 13)])
    rows := EditorDocumentLinkFacts.LinkRows(tokens, null)

    assert rows.Count == 1
    assert rows[0].StartLine == 6
    assert rows[0].EndLine == 6
    assert rows[0].StartCharacter == 19
    assert rows[0].EndCharacter == 38
}

// A NEWLINE INSIDE THE TOKEN MOVES THE ANSWER DOWN A LINE AND BACK TO COLUMN ZERO. This is the
// whole reason the walk exists: a block comment's third line is not at the comment's own column.
test "a document link on a later line of a block comment lands on that line" {
    tokens := EdlTokens([EdlToken(TokenType.MultiLineComment, "/* one\n * two https://a.example/deep\n */", 4, 5)])
    rows := EditorDocumentLinkFacts.LinkRows(tokens, null)

    assert rows.Count == 1
    assert rows[0].StartLine == 4
    assert rows[0].StartCharacter == 7
    assert rows[0].EndCharacter == 29
}

// BOTH SOURCES ARE REPORTED, TOKENS FIRST. The parser's comment trivia is kept for the formatter
// and does not always reach the token stream, so it is searched too — and a file that carries the
// same comment in both is reported twice, in that order.
test "document links come from the token stream first and the comment trivia second" {
    tokens := EdlTokens([EdlToken(TokenType.Comment, "// https://a.example/token", 1, 1)])
    comments := EdlComments([new CommentTrivia(9, 3, "// https://a.example/trivia", false)])

    rows := EditorDocumentLinkFacts.LinkRows(tokens, comments)
    assert rows.Count == 2
    assert rows[0].Text == "https://a.example/token"
    assert rows[1].Text == "https://a.example/trivia"
    assert rows[1].StartLine == 8
    assert rows[1].StartCharacter == 5
}

// NOTHING TO SEARCH IS AN EMPTY ANSWER, not a failure: a document with no tokens parsed yet and no
// comments kept still answers.
test "a document link list is empty when there is nothing to search" {
    assert EditorDocumentLinkFacts.LinkRows(null, null).Count == 0
    assert EditorDocumentLinkFacts.LinkRows(EdlTokens([]), EdlComments([])).Count == 0
}

// THE MATCH STOPS AT THE FOUR CHARACTERS THAT CLOSE A LINK IN PROSE, and at whitespace. A trailing
// period is NOT one of them, which is the shipped behaviour and the reason a sentence-final URL
// carries its full stop.
test "a document link stops at whitespace and at the four closing characters" {
    tokens := EdlTokens([
        EdlToken(TokenType.Comment, "// (https://a.example/paren) tail", 1, 1),
        EdlToken(TokenType.Comment, "// <https://a.example/angle> tail", 2, 1),
        EdlToken(TokenType.StringLiteral, "\"https://a.example/quote\"", 3, 1),
        EdlToken(TokenType.Comment, "// https://a.example/stop. tail", 4, 1),
        EdlToken(TokenType.Comment, "// http:// alone", 5, 1)
    ])

    rows := EditorDocumentLinkFacts.LinkRows(tokens, null)
    assert rows.Count == 4
    assert rows[0].Text == "https://a.example/paren"
    assert rows[1].Text == "https://a.example/angle"
    assert rows[2].Text == "https://a.example/quote"
    assert rows[3].Text == "https://a.example/stop."
}

// THE SCHEME IS `http` WITH AN OPTIONAL `s`, AND THE OPTION BACKTRACKS. `https://` matches with
// the `s` consumed, `http://` matches with it not there, and `httpss://` matches NEITHER way —
// which is the behaviour of the regular expression this walk replaces, written out.
test "a document link scheme takes an optional s and gives it back when it does not fit" {
    assert EditorDocumentLinkFacts.UrlEndAt("https://a", 0) == 9
    assert EditorDocumentLinkFacts.UrlEndAt("http://a", 0) == 8
    assert EditorDocumentLinkFacts.UrlEndAt("httpss://a", 0) == -1
    assert EditorDocumentLinkFacts.UrlEndAt("https//a", 0) == -1
    assert EditorDocumentLinkFacts.UrlEndAt("http://", 0) == -1
    assert EditorDocumentLinkFacts.UrlEndAt("https://", 0) == -1
    assert EditorDocumentLinkFacts.UrlEndAt("ftp://a", 0) == -1
    assert EditorDocumentLinkFacts.UrlEndAt("xhttps://a", 1) == 10
    assert EditorDocumentLinkFacts.UrlEndAt("htt", 0) == -1
}

// THE FOUR CLOSERS AND WHITESPACE, AND NOTHING ELSE. A comma, a full stop and a semicolon all stay
// inside the link.
test "a document link is closed by whitespace and by four characters of prose" {
    assert EditorDocumentLinkFacts.ClosesLink(' ')
    assert EditorDocumentLinkFacts.ClosesLink('\n')
    assert EditorDocumentLinkFacts.ClosesLink('\t')
    assert EditorDocumentLinkFacts.ClosesLink(')')
    assert EditorDocumentLinkFacts.ClosesLink('>')
    assert EditorDocumentLinkFacts.ClosesLink('"')
    assert EditorDocumentLinkFacts.ClosesLink('\'')
    assert !EditorDocumentLinkFacts.ClosesLink('.')
    assert !EditorDocumentLinkFacts.ClosesLink(',')
    assert !EditorDocumentLinkFacts.ClosesLink('(')
    assert !EditorDocumentLinkFacts.ClosesLink('a')
}

// EVERY LINK ON A LINE IS REPORTED, in the order it is written.
test "a document link row is produced for each match in source order" {
    tokens := EdlTokens([EdlToken(TokenType.Comment, "// https://a.example/1 and http://b.example/2", 1, 1)])
    rows := EditorDocumentLinkFacts.LinkRows(tokens, null)

    assert rows.Count == 2
    assert rows[0].Text == "https://a.example/1"
    assert rows[1].Text == "http://b.example/2"
    assert rows[1].StartCharacter == 27
}
