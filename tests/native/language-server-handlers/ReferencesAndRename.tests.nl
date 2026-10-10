namespace NSharpLang.LanguageServerHandlers.Tests

import System
import System.IO
import OmniSharp.Extensions.JsonRpc.Server

test "find references on an empty line answers an empty list" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := """
func main(): void
    let x := 1"""
    LshOpen(docs, uri, source)

    references := LshReferences(docs, uri, 0, 0, true)

    assert references != null
    assert LshLocationCount(references) == 0
}

test "find references for a document that was never opened answers an empty list" {
    docs := LshNewDocs()

    references := LshReferences(docs, "file:///nonexistent.nl", 0, 0, true)

    assert references != null
    assert LshLocationCount(references) == 0
}

test "find references collects cross-file usages through the compiler project snapshot" {
    docs := LshNewDocs()
    examples := LshExamplesDir()
    programPath := Path.Combine(examples, "17-issue-tracker", "backend", "Program.nl")
    uri := LshFileUri(programPath)
    source := File.ReadAllText(programPath)
    LshOpen(docs, uri, source)

    useLine := LshSourceLine(source, "new IssueService", "IssueService")
    useCharacter := LshLineColumn(source, useLine, "IssueService")
    references := LshReferences(docs, uri, useLine, useCharacter, true)

    assert references != null
    assert LshLocationCount(references) > 0
    // The usage site in Program.nl must be collected, not only the declaration.
    assert LshHasLocationUri(references, uri)
}

test "navigation on duplicate type names picks the namespace-correct declaration" {
    docs := LshNewDocs()
    types := LshNewTypes()
    root := LshTempRoot("nsharp-lsp-type-use-")
    try {
        LshWrite(root, "project.yml", LshRaw(
            """
name: TempTypeUseNavigation
targetFramework: net10.0
"""
        ))

        fooWidgetSource := LshRaw(
            """
namespace TempTypeUseNavigation.Foo

record Widget {
    Value: string
}
"""
        )
        fooWidgetPath := LshWrite(root, Path.Combine("Foo", "Widget.nl"), fooWidgetSource)

        barWidgetSource := LshRaw(
            """
namespace TempTypeUseNavigation.Bar

record Widget {
    Value: int
}
"""
        )
        LshWrite(root, Path.Combine("Bar", "Widget.nl"), barWidgetSource)

        fooUseSource := LshRaw(
            """
namespace TempTypeUseNavigation.Foo
import System.Collections.Generic

func Read(items: List<Widget>, maybe: Widget?, many: Widget[], mapper: Func<Widget, string>): string {
    return ""
}
"""
        )
        fooUsePath := LshWrite(root, Path.Combine("Foo", "UseWidget.nl"), fooUseSource)

        fooWidgetUri := LshFileUri(fooWidgetPath)
        fooUseUri := LshFileUri(fooUsePath)

        LshOpen(docs, fooWidgetUri, fooWidgetSource)
        LshOpen(docs, LshFileUri(Path.Combine(root, "Bar", "Widget.nl")), barWidgetSource)
        LshOpen(docs, fooUseUri, fooUseSource)

        useLine := 3
        typeUseColumn := LshLineColumn(fooUseSource, useLine, "Widget")
        assert typeUseColumn >= 0

        definition := LshDefinition(docs, fooUseUri, useLine, typeUseColumn)
        assert definition != null
        definitionLocation := LshSingleLocation(definition)
        assert definitionLocation.Uri.ToString().EndsWith("/Foo/Widget.nl", StringComparison.Ordinal)
        assert definitionLocation.Range.Start.Line == 2

        hover := LshHover(docs, types, fooUseUri, useLine, typeUseColumn)
        assert hover != null
        assert LshHoverMarkdown(hover).Contains("Widget", StringComparison.Ordinal)

        references := LshReferences(docs, fooUseUri, useLine, typeUseColumn, true)
        assert references != null
        assert LshHasLocationEndingWith(references, "/Foo/Widget.nl")
        assert LshHasLocationEndingWith(references, "/Foo/UseWidget.nl")
        assert !LshHasLocationEndingWith(references, "/Bar/Widget.nl")

        declarationColumn := LshLineColumn(fooWidgetSource, 2, "Widget")
        edit := LshRename(docs, fooWidgetUri, 2, declarationColumn, "RenamedWidget")
        assert edit != null
        assert edit.Changes != null

        // Rename should edit type-use sites in Foo/UseWidget.nl.
        assert LshChangesUri(edit, fooUseUri)
        assert LshHasEdit(LshEditsFor(edit, fooUseUri), "RenamedWidget", useLine)
        assert !LshAnyUriEndsWith(LshChangedUris(edit), "/Bar/Widget.nl")
    } finally {
        LshDeleteTree(root)
    }
}

test "find references on duplicate members uses the unsaved open-buffer semantic snapshot" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-unsaved-refs-")
    try {
        LshWrite(root, "project.yml", LshRaw(
            """
name: TempUnsavedRefsTest
targetFramework: net10.0
"""
        ))

        fooWidgetPath := LshWrite(root, Path.Combine("Foo", "Widget.nl"), LshRaw(
            """
namespace TempUnsavedRefsTest.Foo

record Widget {
    Value: string
}
"""
        ))
        fooUsePath := LshWrite(root, Path.Combine("Foo", "UseWidget.nl"), LshRaw(
            """
namespace TempUnsavedRefsTest.Foo

func Read(widget: Widget): string {
    return widget.Value
}
"""
        ))
        LshWrite(root, Path.Combine("Bar", "Widget.nl"), LshRaw(
            """
namespace TempUnsavedRefsTest.Bar

record Widget {
    Value: int
}
"""
        ))
        barUsePath := LshWrite(root, Path.Combine("Bar", "UseWidget.nl"), LshRaw(
            """
namespace TempUnsavedRefsTest.Bar

func Read(widget: Widget): int {
    return widget.Value
}
"""
        ))

        fooWidgetUri := LshFileUri(fooWidgetPath)
        fooUseUri := LshFileUri(fooUsePath)
        barUseUri := LshFileUri(barUsePath)

        LshOpen(docs, fooWidgetUri, LshRaw(
            """
namespace TempUnsavedRefsTest.Foo

record Widget {
    UnsavedValue: string
}
"""
        ))
        LshOpen(docs, fooUseUri, LshRaw(
            """
namespace TempUnsavedRefsTest.Foo

func Read(widget: Widget): string {
    return widget.UnsavedValue
}
"""
        ))
        LshOpen(docs, barUseUri, File.ReadAllText(barUsePath))

        references := LshReferences(docs, fooWidgetUri, 3, 5, true)

        assert references != null
        assert LshHasLocationAt(references, fooWidgetUri, 3)
        assert LshHasLocationAt(references, fooUseUri, 3)
        assert !LshHasLocationUri(references, barUseUri)
    } finally {
        LshDeleteTree(root)
    }
}

test "go to definition on duplicate members uses the unsaved open-buffer semantic snapshot" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-unsaved-def-")
    try {
        LshWrite(root, "project.yml", LshRaw(
            """
name: TempUnsavedDefTest
targetFramework: net10.0
"""
        ))

        fooWidgetPath := LshWrite(root, Path.Combine("Foo", "Widget.nl"), LshRaw(
            """
namespace TempUnsavedDefTest.Foo

record Widget {
    Value: string
}
"""
        ))
        fooUsePath := LshWrite(root, Path.Combine("Foo", "UseWidget.nl"), LshRaw(
            """
namespace TempUnsavedDefTest.Foo

func Read(widget: Widget): string {
    return widget.Value
}
"""
        ))
        LshWrite(root, Path.Combine("Bar", "Widget.nl"), LshRaw(
            """
namespace TempUnsavedDefTest.Bar

record Widget {
    UnsavedValue: int
}
"""
        ))

        fooWidgetUri := LshFileUri(fooWidgetPath)
        fooUseUri := LshFileUri(fooUsePath)

        LshOpen(docs, fooWidgetUri, LshRaw(
            """
namespace TempUnsavedDefTest.Foo

record Widget {
    UnsavedValue: string
}
"""
        ))
        LshOpen(docs, fooUseUri, LshRaw(
            """
namespace TempUnsavedDefTest.Foo

record Decoy {
    UnsavedValue: string
}

func Read(widget: Widget): string {
    return widget.UnsavedValue
}
"""
        ))

        definition := LshDefinition(docs, fooUseUri, 7, 18)

        assert definition != null
        location := LshSingleLocation(definition)
        assert location.Uri.ToString() == fooWidgetUri
        assert location.Range.Start.Line == 3
        assert location.Range.Start.Character == 4
    } finally {
        LshDeleteTree(root)
    }
}

test "rename on duplicate members edits only the unsaved namespace that owns the symbol" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-unsaved-rename-")
    try {
        LshWrite(root, "project.yml", LshRaw(
            """
name: TempUnsavedRenameTest
targetFramework: net10.0
"""
        ))

        fooWidgetPath := LshWrite(root, Path.Combine("Foo", "Widget.nl"), LshRaw(
            """
namespace TempUnsavedRenameTest.Foo

record Widget {
    Value: string
}
"""
        ))
        fooUsePath := LshWrite(root, Path.Combine("Foo", "UseWidget.nl"), LshRaw(
            """
namespace TempUnsavedRenameTest.Foo

func Read(widget: Widget): string {
    return widget.Value
}
"""
        ))
        LshWrite(root, Path.Combine("Bar", "Widget.nl"), LshRaw(
            """
namespace TempUnsavedRenameTest.Bar

record Widget {
    UnsavedValue: int
}
"""
        ))
        barUsePath := LshWrite(root, Path.Combine("Bar", "UseWidget.nl"), LshRaw(
            """
namespace TempUnsavedRenameTest.Bar

func Read(widget: Widget): int {
    return widget.UnsavedValue
}
"""
        ))

        fooWidgetUri := LshFileUri(fooWidgetPath)
        fooUseUri := LshFileUri(fooUsePath)
        barUseUri := LshFileUri(barUsePath)

        LshOpen(docs, fooWidgetUri, LshRaw(
            """
namespace TempUnsavedRenameTest.Foo

record Widget {
    UnsavedValue: string
}
"""
        ))
        LshOpen(docs, fooUseUri, LshRaw(
            """
namespace TempUnsavedRenameTest.Foo

func Read(widget: Widget): string {
    return widget.UnsavedValue
}
"""
        ))
        LshOpen(docs, barUseUri, File.ReadAllText(barUsePath))

        edit := LshRename(docs, fooWidgetUri, 3, 5, "FreshValue")

        assert edit != null
        assert edit.Changes != null
        assert LshChangesUri(edit, fooWidgetUri)
        assert LshChangesUri(edit, fooUseUri)
        assert !LshChangesUri(edit, barUseUri)
        assert LshAllEdits(edit).Count == 2
    } finally {
        LshDeleteTree(root)
    }
}

test "excluding the declaration never widens the reference set" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := """
func main(): void
    let x := 1
    let y := x + 2
    print(x)"""
    LshOpen(docs, uri, source)

    withDeclaration := LshReferences(docs, uri, 2, 8, true)
    withoutDeclaration := LshReferences(docs, uri, 2, 8, false)

    assert withDeclaration != null
    assert withoutDeclaration != null
    // References excluding the declaration must be <= references including it.
    assert LshLocationCount(withoutDeclaration) <= LshLocationCount(withDeclaration)
}

test "rename of a cross-file member edits the declaration file through the project snapshot" {
    docs := LshNewDocs()
    examples := LshExamplesDir()
    programPath := Path.Combine(examples, "17-issue-tracker", "backend", "Program.nl")
    servicePath := Path.Combine(examples, "17-issue-tracker", "backend", "Service.nl")
    programUri := LshFileUri(programPath)
    serviceUri := LshFileUri(servicePath)

    LshOpen(docs, programUri, File.ReadAllText(programPath))
    LshOpen(docs, serviceUri, File.ReadAllText(servicePath))

    // GetAll is declared at line 68 column 10 (1-based) in Service.nl.
    edit := LshRename(docs, serviceUri, 67, 9, "FetchAll")

    assert edit != null
    assert edit.Changes != null
    // Rename should include the declaration file.
    assert LshChangesUri(edit, serviceUri)
    assert LshHasEditAt(LshEditsFor(edit, serviceUri), "FetchAll", 67, 9)
}

test "rename refuses a text-only fallback when the project snapshot is degraded" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-rename-degraded-")
    try {
        LshWrite(root, "project.yml", "name: [broken")
        source := """
func main(): void
    let value := 1
    print(value)"""
        programPath := LshWrite(root, "Program.nl", source)
        uri := LshFileUri(programPath)
        LshOpen(docs, uri, source)

        failure := LshRenameFailure(docs, uri, 2, 8, "renamed")

        requestFailed := failure as RequestFailedException
        assert requestFailed != null
        assert requestFailed.ErrorCode == ErrorCodes.RequestFailed
        assert requestFailed.Message.Contains("semantic project analysis is degraded", StringComparison.Ordinal)
        assert requestFailed.Message.Contains("refusing text-only rename", StringComparison.Ordinal)
    } finally {
        LshDeleteTree(root)
    }
}

test "rename refuses a semantic fallback for a word that only appears in a comment" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-rename-comment-")
    try {
        LshWrite(root, "project.yml", LshRaw(
            """
name: TempRenameCommentTest
targetFramework: net10.0
"""
        ))

        source := LshRaw(
            """
namespace TempRenameCommentTest

func Main(): void
    let value := 1
    // value should not bind to the local above
    print(value)
"""
        )
        programPath := LshWrite(root, "Program.nl", source)
        uri := LshFileUri(programPath)
        LshOpen(docs, uri, source)

        commentLine := LshMarkerLine(source, "// value")
        assert commentLine >= 0
        commentColumn := LshLineColumn(source, commentLine, "value")
        assert commentColumn >= 0

        failure := LshRenameFailure(docs, uri, commentLine, commentColumn, "renamed")

        requestFailed := failure as RequestFailedException
        assert requestFailed != null
        assert requestFailed.ErrorCode == ErrorCodes.RequestFailed
        assert requestFailed.Message.Contains("semantic resolution could not safely identify", StringComparison.Ordinal)
        assert requestFailed.Message.Contains("No edits were applied", StringComparison.Ordinal)
    } finally {
        LshDeleteTree(root)
    }
}

test "rename of a shadowed local function leaves the outer declaration alone" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-rename-shadow-")
    try {
        LshWrite(root, "project.yml", LshRaw(
            """
name: TempRenameShadowTest
targetFramework: net10.0
"""
        ))

        source := LshRaw(
            """
namespace TempRenameShadowTest

func Main(): void
    func Helper(): void
        print("inner")
    Helper()

func Helper(): void
    print("outer")
"""
        )
        programPath := LshWrite(root, "Program.nl", source)
        uri := LshFileUri(programPath)
        LshOpen(docs, uri, source)

        innerDeclarationLine := LshMarkerLine(source, "func Helper(): void")
        assert innerDeclarationLine >= 0
        innerDeclarationColumn := LshLineColumn(source, innerDeclarationLine, "Helper")
        assert innerDeclarationColumn >= 0

        edit := LshRename(docs, uri, innerDeclarationLine, innerDeclarationColumn, "InnerHelper")

        assert edit != null
        assert edit.Changes != null
        assert LshChangedUris(edit).Count == 1

        edits := LshAllEdits(edit)
        assert edits.Count == 2
        index := 0
        while index < edits.Count {
            assert edits[index].NewText == "InnerHelper"
            index = index + 1
        }
        assert LshHasEditOnLine(edits, 3)
        assert LshHasEditOnLine(edits, 5)
        assert !LshHasEditOnLine(edits, 7)
    } finally {
        LshDeleteTree(root)
    }
}
