namespace NSharpLang.LanguageServerHandlers.Tests

import System
import System.IO

test "go to definition on a cross-file type resolves through the compiler project snapshot" {
    docs := LshNewDocs()
    examples := LshExamplesDir()
    programPath := Path.Combine(examples, "17-issue-tracker", "backend", "Program.nl")
    uri := LshFileUri(programPath)
    source := File.ReadAllText(programPath)
    LshOpen(docs, uri, source)

    useLine := LshSourceLine(source, "new IssueService", "IssueService")
    useCharacter := LshLineColumn(source, useLine, "IssueService")
    definition := LshDefinition(docs, uri, useLine, useCharacter)
    assert definition != null

    servicePath := Path.Combine(examples, "17-issue-tracker", "backend", "Service.nl")
    serviceSource := File.ReadAllText(servicePath)
    declarationLine := LshSourceLine(serviceSource, "class IssueService", "IssueService")
    declarationCharacter := LshLineColumn(serviceSource, declarationLine, "IssueService")

    location := LshSingleLocation(definition)
    assert location.Uri.ToString() == LshFileUri(servicePath)
    assert location.Range.Start.Line == declarationLine
    assert location.Range.Start.Character == declarationCharacter
}

test "go to definition prefers the semantic result over a same-named local symbol" {
    docs := LshNewDocs()
    examples := LshExamplesDir()
    programPath := Path.Combine(examples, "17-issue-tracker", "backend", "Program.nl")
    uri := LshFileUri(programPath)
    source := File.ReadAllText(programPath)
    LshOpen(docs, uri, source)

    useLine := LshSourceLine(source, "new IssueService", "IssueService")
    useCharacter := LshLineColumn(source, useLine, "IssueService")
    definition := LshDefinition(docs, uri, useLine, useCharacter)
    assert definition != null

    servicePath := Path.Combine(examples, "17-issue-tracker", "backend", "Service.nl")
    serviceSource := File.ReadAllText(servicePath)
    declarationLine := LshSourceLine(serviceSource, "class IssueService", "IssueService")
    declarationCharacter := LshLineColumn(serviceSource, declarationLine, "IssueService")

    location := LshSingleLocation(definition)
    assert location.Uri.ToString() == LshFileUri(servicePath)
    assert location.Range.Start.Line == declarationLine
    assert location.Range.Start.Character == declarationCharacter
}

test "go to definition past the end of a call line answers nothing" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := LshRaw(
        """
func Main() {
    Foo()
}

func Foo(): void {
}
"""
    )
    LshOpen(docs, uri, source)

    definition := LshDefinition(docs, uri, 1, 9)

    assert definition == null
}

test "go to definition uses the open buffer when it differs from disk by a trailing comment" {
    docs := LshNewDocs()
    examples := LshExamplesDir()
    programPath := Path.Combine(examples, "17-issue-tracker", "backend", "Program.nl")
    uri := LshFileUri(programPath)
    source := File.ReadAllText(programPath)
    LshOpen(docs, uri, source + "\n// unsaved edit")

    useLine := LshSourceLine(source, "new IssueService", "IssueService")
    useCharacter := LshLineColumn(source, useLine, "IssueService")
    definition := LshDefinition(docs, uri, useLine, useCharacter)
    assert definition != null

    expected := LshFileUri(Path.Combine(examples, "17-issue-tracker", "backend", "Service.nl"))
    location := LshSingleLocation(definition)
    assert location.Uri.ToString() == expected
}

test "go to definition on a second symbol still resolves from a modified open buffer" {
    docs := LshNewDocs()
    examples := LshExamplesDir()
    programPath := Path.Combine(examples, "17-issue-tracker", "backend", "Program.nl")
    uri := LshFileUri(programPath)
    source := File.ReadAllText(programPath)
    LshOpen(docs, uri, source + "\n// modified")

    useLine := LshSourceLine(source, "new IssueStore", "IssueStore")
    useCharacter := LshLineColumn(source, useLine, "IssueStore")
    definition := LshDefinition(docs, uri, useLine, useCharacter)
    assert definition != null

    location := LshSingleLocation(definition)
    assert location.Uri.ToString().EndsWith("Database.nl", StringComparison.Ordinal)
}

test "go to definition in a scanned workspace without a project file resolves against the workspace root" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-workspace-root-")
    try {
        widgetPath := LshWrite(root, Path.Combine("Foo", "Widget.nl"), LshRaw(
            """
namespace TempWorkspaceRoot.Foo

record Widget {
    Value: string
}
"""
        ))
        usePath := LshWrite(root, Path.Combine("Foo", "UseWidget.nl"), LshRaw(
            """
namespace TempWorkspaceRoot.Foo

func Read(widget: Widget): string {
    return widget.Value
}
"""
        ))

        docs.ScanWorkspaceDirectory(root)
        useUri := LshFileUri(usePath)

        definition := LshDefinition(docs, useUri, 3, 18)

        assert definition != null
        location := LshSingleLocation(definition)
        assert location.Uri.ToString() == LshFileUri(widgetPath)
        assert location.Range.Start.Line == 3
    } finally {
        LshDeleteTree(root)
    }
}

test "a scanned workspace reads current disk content for files that were never opened" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-scan-stale-")
    try {
        programPath := LshWrite(root, "Program.nl", LshRaw(
            """
import "Helper"

func main(): void {
    Beta()
}
"""
        ))
        helperPath := LshWrite(root, "Helper.nl", LshRaw(
            """
func Alpha(): void {
    return
}
"""
        ))

        docs.ScanWorkspaceDirectory(root)

        File.WriteAllText(helperPath, LshRaw(
            """
func Beta(): void {
    return
}
"""
        ))

        programUri := LshFileUri(programPath)
        programSource := File.ReadAllText(programPath)
        LshOpen(docs, programUri, programSource)

        useLine := LshSourceLine(programSource, "Beta()", "Beta")
        useCharacter := LshLineColumn(programSource, useLine, "Beta")
        definition := LshDefinition(docs, programUri, useLine, useCharacter)

        assert definition != null
        location := LshSingleLocation(definition)
        assert location.Uri.ToString() == LshFileUri(helperPath)
        assert location.Range.Start.Line == 0
    } finally {
        LshDeleteTree(root)
    }
}

test "a degraded standalone directory with an unsaved peer refuses a stale disk snapshot" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-stale-disk-peer-")
    try {
        programPath := LshWrite(root, "Program.nl", LshRaw(
            """
func main(): void {
    alpha()
}
"""
        ))
        LshWrite(root, "Helper.nl", LshRaw(
            """
func alpha(): void {
    return
}
"""
        ))
        peerPath := LshWrite(root, "Peer.nl", LshRaw(
            """
func peer(): void {
    return
}
"""
        ))

        programUri := LshFileUri(programPath)
        peerUri := LshFileUri(peerPath)
        LshOpen(docs, programUri, File.ReadAllText(programPath))
        LshOpen(docs, peerUri, LshRaw(
            """
func peerUnsaved(): void {
    return
}
"""
        ))

        definition := LshDefinition(docs, programUri, 1, 5)

        assert definition == null
    } finally {
        LshDeleteTree(root)
    }
}

test "a project snapshot load failure is reported as a structured degraded-state warning" {
    sink := new LshLogSink()
    docs := LshCapturingDocs(sink)
    root := LshTempRoot("nsharp-lsp-degraded-")
    try {
        LshWrite(root, "project.yml", "[not valid project config")
        sourcePath := LshWrite(root, "Program.nl", LshRaw(
            """
func main(): void {
    print("broken project config")
}
"""
        ))

        uri := LshFileUri(sourcePath)
        LshOpen(docs, uri, File.ReadAllText(sourcePath))

        definition := LshDefinition(docs, uri, 1, 5)

        assert definition == null

        degraded := LshWarningsContaining(sink, "Project semantic snapshot degraded")
        assert degraded.Count > 0

        first := degraded[0]
        assert LshEventPropertyText(first, "Reason") == "LoadFailed"
        assert LshEventPropertyText(first, "ProjectRoot") == root
        message := LshEventPropertyText(first, "Message")
        assert message != null
        assert message.Length > 0
        assert first.Exception != null
    } finally {
        LshDeleteTree(root)
    }
}
