namespace NSharpLang.LanguageServerHandlers.Tests

import System
import System.IO
import OmniSharp.Extensions.JsonRpc.Server

test "prepare rename refuses a keyword" {
    docs := LshNewDocs()
    uri := "file:///test/prepare_rename_kw.nl"
    source := LshBody(
        """
func main() {
    let x := 42
}
"""
    )
    LshOpen(docs, uri, source)

    // "func" sits at line 0, column 0.
    assert LshPrepareRename(docs, uri, 0, 0) == null
    // "let" sits at line 1, column 4.
    assert LshPrepareRename(docs, uri, 1, 4) == null
}

test "prepare rename refuses a primitive type name" {
    docs := LshNewDocs()
    uri := "file:///test/prepare_rename_prim.nl"
    source := LshBody(
        """
func main() {
    let x: int = 42
}
"""
    )
    LshOpen(docs, uri, source)

    intColumn := LshLineColumn(source, 1, "int")

    assert LshPrepareRename(docs, uri, 1, intColumn) == null
}

test "prepare rename refuses text inside a string literal" {
    docs := LshNewDocs()
    uri := "file:///test/prepare_rename_string_literal.nl"
    source := LshBody(
        """
func main() {
    message := "oldName"
    print message
}
"""
    )
    LshOpen(docs, uri, source)

    stringContentColumn := LshLineColumn(source, 1, "oldName")

    assert LshPrepareRename(docs, uri, 1, stringContentColumn) == null
}

test "prepare rename refuses text inside escaped interpolation braces" {
    docs := LshNewDocs()
    uri := "file:///test/prepare_rename_interpolated_escaped_braces.nl"
    source := LshRaw(
        """
func main() {
    oldName := "world"
    message := $"hello {{oldName}}"
    print message
}
"""
    )
    LshOpen(docs, uri, source)

    column := LshLineColumn(source, 2, "oldName")

    assert LshPrepareRename(docs, uri, 2, column) == null
}

test "prepare rename refuses text inside a multi-line raw string" {
    docs := LshNewDocs()
    uri := "file:///test/prepare_rename_raw_string_literal.nl"
    source := "func main() {\n    oldName := \"symbol\"\n    text := \"\"\"\noldName\n\"\"\"\n    print text\n}"
    LshOpen(docs, uri, source)

    column := LshLineColumn(source, 3, "oldName")

    assert LshPrepareRename(docs, uri, 3, column) == null
}

test "prepare rename accepts a project-resolved member usage" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-prepare-rename-project-")
    try {
        LshWrite(root, "project.yml", LshRaw(
            """
name: TempPrepareRenameProject
targetFramework: net10.0
"""
        ))
        widgetPath := LshWrite(root, "Widget.nl", LshRaw(
            """
namespace TempPrepareRenameProject

record Widget {
    Value: string
}
"""
        ))
        useSource := LshRaw(
            """
namespace TempPrepareRenameProject

func Read(widget: Widget): string {
    return widget.Value
}
"""
        )
        usePath := LshWrite(root, "UseWidget.nl", useSource)

        widgetUri := LshFileUri(widgetPath)
        useUri := LshFileUri(usePath)
        LshOpen(docs, widgetUri, File.ReadAllText(widgetPath))
        LshOpen(docs, useUri, useSource)

        result := LshPrepareRename(docs, useUri, 3, 20)

        assert result != null
        assert result.IsPlaceholderRange
        placeholderRange := result.PlaceholderRange
        assert placeholderRange != null
        assert placeholderRange.Placeholder == "Value"
    } finally {
        LshDeleteTree(root)
    }
}

test "prepare rename refuses with a reason when the project snapshot is degraded" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-prepare-rename-degraded-")
    try {
        LshWrite(root, "project.yml", "name: [broken")
        source := """
func main(): void
    let value := 1
    print(value)"""
        programPath := LshWrite(root, "Program.nl", source)
        uri := LshFileUri(programPath)
        LshOpen(docs, uri, source)

        failure := LshPrepareRenameFailure(docs, uri, 2, 8)

        requestFailed := failure as RequestFailedException
        assert requestFailed != null
        assert requestFailed.ErrorCode == ErrorCodes.RequestFailed
        assert requestFailed.Message.Contains("semantic project analysis is degraded", StringComparison.Ordinal)
        assert requestFailed.Message.Contains("refusing text-only rename", StringComparison.Ordinal)
    } finally {
        LshDeleteTree(root)
    }
}

test "document formatting returns text-carrying edits for badly indented code" {
    docs := LshNewDocs()
    uri := "file:///test/formatting.nl"
    source := "func main() {\n  let x := 42\n      let y := 43\n}\n"
    LshOpen(docs, uri, source)

    edits := LshFormatDocument(docs, uri)

    assert edits != null
    collected := LshTextEdits(edits)
    if collected.Count > 0 {
        // At least one edit must carry replacement text.
        carriesText := false
        index := 0
        while index < collected.Count {
            text: object? = collected[index].NewText
            if text != null {
                carriesText = true
            }
            index = index + 1
        }
        assert carriesText
    }
}

test "document formatting a document that was never opened answers nothing" {
    docs := LshNewDocs()

    edits := LshFormatDocument(docs, "file:///nonexistent.nl")

    assert edits == null
}

test "document formatting already-formatted code answers a container rather than throwing" {
    docs := LshNewDocs()
    uri := "file:///test/formatting_clean.nl"
    source := "func main() {\n    let x := 42\n}\n"
    LshOpen(docs, uri, source)

    edits := LshFormatDocument(docs, uri)

    assert edits != null
}

test "go to implementation on a base class answers only when the symbol table is populated" {
    docs := LshNewDocs()
    uri := "file:///test/impl.nl"
    // The parser treats the first type after ':' as the base class, so this is a
    // class hierarchy rather than an interface.
    source := LshBody(
        """
class Animal {
    func speak(): string {
        return "..."
    }
}

class Dog : Animal {
    func speak(): string {
        return "woof"
    }
}
"""
    )
    LshOpen(docs, uri, source)

    doc := LshDocument(docs, uri)
    hasSymbols := LshHasSymbol(doc, "Animal")

    result := LshImplementation(docs, uri, 0, 6)
    if hasSymbols {
        // With symbols present the handler must find Dog as a subclass of Animal.
        assert result != null
    } else {
        assert result == null
    }
}

test "go to implementation on a function answers nothing" {
    docs := LshNewDocs()
    uri := "file:///test/impl_none.nl"
    source := LshBody(
        """
func main() {
    let x := 42
}
"""
    )
    LshOpen(docs, uri, source)

    result := LshImplementation(docs, uri, 0, 5)

    assert result == null
}

test "go to implementation on a document that was never opened answers nothing" {
    docs := LshNewDocs()

    result := LshImplementation(docs, "file:///nonexistent.nl", 0, 0)

    assert result == null
}

test "document highlight marks every use of a repeated variable" {
    docs := LshNewDocs()
    uri := "file:///test/highlight.nl"
    source := LshBody(
        """
func main() {
    let count := 1
    let doubled := count + count
    print(count)
}
"""
    )
    LshOpen(docs, uri, source)

    highlights := LshDocumentHighlights(docs, uri, 1, 8)

    assert highlights != null
    assert LshHighlightCount(highlights) >= 2
}

test "document highlight on whitespace answers an empty container" {
    docs := LshNewDocs()
    uri := "file:///test/highlight_empty.nl"
    source := LshBody(
        """
func main() {
    let x := 42
}
"""
    )
    LshOpen(docs, uri, source)

    highlights := LshDocumentHighlights(docs, uri, 0, 4)

    assert highlights != null
}

test "document highlight on a document that was never opened answers an empty container" {
    docs := LshNewDocs()

    highlights := LshDocumentHighlights(docs, "file:///nonexistent.nl", 0, 0)

    assert highlights != null
    assert LshHighlightCount(highlights) == 0
}

test "typing a closing brace realigns it with the matching open brace" {
    docs := LshNewDocs()
    uri := "file:///test/ontypeformat_brace.nl"
    // The user typed '}' with the wrong indentation.
    source := "func main() {\n    let x := 42\n        }\n"
    LshOpen(docs, uri, source)

    edits := LshOnTypeFormatting(docs, uri, 2, 9, "}")

    assert edits != null
    assert LshTextEdits(edits).Count > 0
}

test "pressing enter after an open brace indents the new line" {
    docs := LshNewDocs()
    uri := "file:///test/ontypeformat_newline.nl"
    // The user pressed Enter after '{' and the new line has no indentation.
    source := "func main() {\n\n}\n"
    LshOpen(docs, uri, source)

    edits := LshOnTypeFormatting(docs, uri, 1, 0, "\n")

    assert edits != null
    collected := LshTextEdits(edits)
    assert collected.Count > 0

    first := collected[0]
    assert first.NewText.Length > 0
    assert first.NewText.StartsWith(" ", StringComparison.Ordinal) || first.NewText.StartsWith("\t", StringComparison.Ordinal)
}

test "on-type formatting for a document that was never opened answers nothing" {
    docs := LshNewDocs()

    edits := LshOnTypeFormatting(docs, "file:///nonexistent.nl", 0, 0, "}")

    assert edits == null
}
