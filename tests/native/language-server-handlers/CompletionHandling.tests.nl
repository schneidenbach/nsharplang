namespace NSharpLang.LanguageServerHandlers.Tests

import System
import OmniSharp.Extensions.LanguageServer.Protocol.Models

test "completion offers N# keywords for a bare identifier prefix" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "f")

    completions := LshCompletions(docs, types, uri, 0, 1)

    assert LshCompletionCount(completions) > 0
    assert LshHasCompletion(completions, "func")
    assert LshHasCompletion(completions, "for")
    assert LshHasCompletion(completions, "foreach")
}

test "completion offers primitive type names" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "i")

    completions := LshCompletions(docs, types, uri, 0, 1)

    assert LshHasCompletion(completions, "int")
    assert LshHasCompletion(completions, "string")
    assert LshHasCompletion(completions, "bool")
}

test "completion offers common .NET types" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "C")

    completions := LshCompletions(docs, types, uri, 0, 1)

    assert LshHasCompletion(completions, "Console")
    assert LshHasCompletion(completions, "List")
    assert LshHasCompletion(completions, "Dictionary")
}

test "completion offers functions declared in the same document" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    source := """
func greet(name: string): string
    return "Hello, " + name

func main(): void
    """
    LshOpen(docs, uri, source)

    completions := LshCompletions(docs, types, uri, 5, 4)

    assert LshHasCompletion(completions, "greet")
    assert LshHasCompletion(completions, "main")
}

test "completion carries the leading comment block of a local function as documentation" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test/docs.nl"
    source := LshBody(
        """
// Greets someone by name.
// Returns the composed greeting.
func greet(name: string): string
    return name

func main(): void
    """
    )
    LshOpen(docs, uri, source)

    completions := LshCompletions(docs, types, uri, 6, 4)

    greet := LshSingleCompletion(completions, "greet")
    documentation := LshDocumentationText(greet.Documentation)
    assert documentation != null
    assert documentation.Contains("Greets someone by name.", StringComparison.Ordinal)
    assert documentation.Contains("Returns the composed greeting.", StringComparison.Ordinal)
}

test "completion snippet for func expands name params and return type placeholders" {
    LshAssertSnippet("func", "${1:name};${2:params};${3:void}")
}

test "completion snippet for if expands a condition placeholder" {
    LshAssertSnippet("if", "${1:condition}")
}

test "completion snippet for match expands value and pattern placeholders" {
    LshAssertSnippet("match", "${1:value};${2:pattern}")
}

test "completion snippet for for expands item and collection placeholders" {
    LshAssertSnippet("for", "${1:item};${2:collection}")
}

test "completion snippet for type expands a name placeholder" {
    LshAssertSnippet("type", "${1:Name}")
}

test "completion offers a snippet and a keyword entry for the same word" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "f")

    completions := LshCompletions(docs, types, uri, 0, 1)

    funcSnippet := LshCompletionOfKind(completions, "func", CompletionItemKind.Snippet)
    funcKeyword := LshCompletionOfKind(completions, "func", CompletionItemKind.Keyword)

    assert funcSnippet != null
    assert funcKeyword != null
}

test "completion reflects a document update rather than the opened text" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "func foo(): void")

    first := LshCompletions(docs, types, uri, 0, 0)
    assert LshHasCompletion(first, "foo")

    LshUpdate(docs, uri, "func bar(): void")

    second := LshCompletions(docs, types, uri, 0, 0)
    assert LshHasCompletion(second, "bar")
}

test "completion still answers keywords in an empty document" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "")

    completions := LshCompletions(docs, types, uri, 0, 0)

    assert LshCompletionCount(completions) > 0
    assert LshHasCompletion(completions, "func")
}

test "completion sees both outer and nested functions" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    source := """
func outer(): void
    func inner(): void
        print("nested")
    """
    LshOpen(docs, uri, source)

    completions := LshCompletions(docs, types, uri, 4, 4)

    assert LshHasCompletion(completions, "outer")
    assert LshHasCompletion(completions, "inner")
}

test "member completion on an N# class instance lists its source members" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test/nsharp-class.nl"
    LshOpen(docs, uri, LshPersonMemberSource())

    completions := LshCompletions(docs, types, uri, 12, 6)

    assert LshCompletionCount(completions) > 0
    assert LshHasCompletion(completions, "Name")
    assert LshHasCompletion(completions, "Age")
    assert LshHasCompletion(completions, "Greet")
}

test "member completion prefers source members over a same-named CLR type" {
    LshEnsureConflictingClrPersonType()

    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test/nsharp-class-clr-collision.nl"
    LshOpen(docs, uri, LshPersonMemberSource())

    completions := LshCompletions(docs, types, uri, 12, 6)

    assert LshCompletionCount(completions) > 0
    assert LshHasCompletion(completions, "Name")
    assert LshHasCompletion(completions, "Age")
    assert LshHasCompletion(completions, "Greet")
}

test "import context completion only suggests namespaces" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test/imports.nl"
    source := "import System."
    LshOpen(docs, uri, source)

    completions := LshCompletions(docs, types, uri, 0, source.Length)

    assert LshCompletionCount(completions) > 0
    for item in completions {
        assert item.Kind == CompletionItemKind.Module
    }
    assert LshHasCompletion(completions, "Collections") || LshHasCompletion(completions, "Threading")
    assert !LshHasCompletion(completions, "Action")
    assert !LshHasCompletion(completions, "Console")
}
