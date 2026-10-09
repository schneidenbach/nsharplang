namespace NSharpLang.LanguageServerDiagnostics.Tests

import System
import System.IO
import Microsoft.Extensions.Logging.Abstractions
import NSharpLang.LanguageServer.Services

// Workspace lifecycle contracts for DocumentManager: which files a scan loads, which buffer wins
// when the editor and the disk disagree, and what each file-system event does to the tracked set.
// Every row drives the manager through its public API so it survives the language-server rewrite.
test "publishing diagnostics for an unsaved buffer also publishes every other open file" {
    root := LscNewWorkspaceRoot()
    try {
        onDiskProgramText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        dirtyProgramText := LsdDecodedSource(
            """
func Broken() -> int {
    return "oops"
}
"""
        )
        personText := LsdDecodedSource(
            """
func Helper() {
}
"""
        )

        LsdWriteFile(root, "Program.nl", onDiskProgramText)
        LsdWriteFile(root, "Models/Person.nl", personText)

        programUri := LsdFileUri(Path.Combine(root, "Program.nl"))
        personUri := LsdFileUri(Path.Combine(root, "Models", "Person.nl"))

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        manager.UpdateDocument(programUri, dirtyProgramText, 1)
        manager.UpdateDocument(personUri, personText, 1)

        publications := manager.GetDiagnosticsToPublish(programUri)
        uris := LscPublicationUris(publications)

        assert publications.Count == 2
        assert LscCountEndingWith(uris, "Program.nl") == 1
        assert LscCountEndingWith(uris, "Models/Person.nl") == 1
    } finally {
        Directory.Delete(root, true)
    }
}

test "scanning a workspace directory loads every nl file under it" {
    root := LscNewWorkspaceRoot()
    try {
        programText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        helperText := LsdDecodedSource(
            """
func Helper() {
}
"""
        )

        LsdWriteFile(root, "Program.nl", programText)
        LsdWriteFile(root, "Utils/Helper.nl", helperText)

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        loadedUris := manager.ScanWorkspaceDirectory(root)

        assert loadedUris.Count == 2
        assert LscCountContaining(loadedUris, "Program.nl") == 1
        assert LscCountContaining(loadedUris, "Helper.nl") == 1
    } finally {
        Directory.Delete(root, true)
    }
}

test "a workspace scan leaves files already open in the editor alone" {
    root := LscNewWorkspaceRoot()
    try {
        programText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        helperText := LsdDecodedSource(
            """
func Helper() {
}
"""
        )

        LsdWriteFile(root, "Program.nl", programText)
        LsdWriteFile(root, "Helper.nl", helperText)

        programUri := LsdFileUri(Path.Combine(root, "Program.nl"))

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)

        // Simulate the editor opening the file first.
        manager.MarkEditorOpen(programUri)
        manager.UpdateDocument(programUri, programText, 1)

        loadedUris := manager.ScanWorkspaceDirectory(root)

        // Only Helper.nl should have been loaded by the scan.
        assert loadedUris.Count == 1
        assert LscCountContaining(loadedUris, "Helper.nl") == 1

        // Program.nl is still tracked, from the editor open.
        assert manager.HasDocument(programUri)
    } finally {
        Directory.Delete(root, true)
    }
}

test "opening and closing an unchanged buffer reuses the project snapshot" {
    root := LscNewWorkspaceRoot()
    try {
        programText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        programPath := Path.Combine(root, "Program.nl")
        LsdWriteFile(root, "Program.nl", programText)
        programUri := LsdFileUri(programPath)

        manager := LsdNewDocumentManager()
        ignoredScan := LsdInvokeStringArgument(manager, "ScanWorkspaceDirectory", root)
        _ = ignoredScan

        diskBinding := LsdInvokeStringArgument(manager, "SynchronizedProjectSnapshot", programUri)
        if diskBinding == null {
            throw new InvalidOperationException("The disk project snapshot was not created.")
        }
        diskSnapshot := LsdRequiredProperty(diskBinding, "Snapshot")

        ignoredOpen := LsdInvokeStringArgument(manager, "MarkEditorOpen", programUri)
        _ = ignoredOpen
        LsdUpdateDocument(manager, programUri, programText)
        openBinding := LsdInvokeStringArgument(manager, "SynchronizedProjectSnapshot", programUri)
        if openBinding == null {
            throw new InvalidOperationException("The open-buffer project snapshot was not created.")
        }
        openSnapshot := LsdRequiredProperty(openBinding, "Snapshot")
        if !Object.ReferenceEquals(diskSnapshot, openSnapshot) {
            throw new InvalidOperationException("Opening the unchanged buffer replaced the project snapshot.")
        }

        closedUri := LsdInvokeStringArgument(manager, "HandleEditorClose", programUri)
        if closedUri == null || closedUri.ToString() != programUri {
            throw new InvalidOperationException("Closing the document did not return its URI.")
        }
        closedBinding := LsdInvokeStringArgument(manager, "SynchronizedProjectSnapshot", programUri)
        if closedBinding == null {
            throw new InvalidOperationException("The closed-buffer project snapshot was not created.")
        }
        closedSnapshot := LsdRequiredProperty(closedBinding, "Snapshot")
        if !Object.ReferenceEquals(diskSnapshot, closedSnapshot) {
            throw new InvalidOperationException("Closing the unchanged buffer replaced the project snapshot.")
        }
    } finally {
        Directory.Delete(root, true)
    }
}

test "a source excluded by project configuration does not join its semantic snapshot" {
    root := LscNewWorkspaceRoot()
    try {
        LsdWriteFile(root, "project.yml", "name: Product\nexclude:\n  - examples/**\n")
        LsdWriteFile(root, "Program.nl", "func Main() {}")
        examplePath := Path.Combine(root, "examples", "Example.nl")
        exampleDirectory := must Path.GetDirectoryName(examplePath)
        Directory.CreateDirectory(exampleDirectory)
        File.WriteAllText(examplePath, "func Main() {}")
        File.WriteAllText(Path.Combine(exampleDirectory, "Other.nl"), "func Main() {}")

        manager := LsdNewDocumentManager()
        exampleUri := LsdFileUri(examplePath)
        ignoredOpen := LsdInvokeStringArgument(manager, "MarkEditorOpen", exampleUri)
        _ = ignoredOpen
        LsdUpdateDocument(manager, exampleUri, "func Main() {}")

        snapshot := LsdInvokeStringArgument(manager, "SynchronizedProjectSnapshot", exampleUri)
        assert snapshot == null

        document := LsdGetDocument(manager, exampleUri)
        diagnostics := LsdCopyCompilerErrors(LsdRequiredProperty(document, "Diagnostics"))
        for diagnostic in diagnostics {
            assert !diagnostic.Message.Contains("same parameter signature", StringComparison.Ordinal)
        }
    } finally {
        Directory.Delete(root, true)
    }
}

test "closing an edited workspace file reloads it from disk instead of dropping it" {
    root := LscNewWorkspaceRoot()
    try {
        programText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        editedText := LsdDecodedSource(
            """
func Main() -> int {
    return 42
}
"""
        )

        LsdWriteFile(root, "Program.nl", programText)

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        ignoredScan := manager.ScanWorkspaceDirectory(root)
        _ = ignoredScan

        programUri := LsdFileUri(Path.Combine(root, "Program.nl"))

        // The editor opens and modifies the file, then closes it.
        manager.MarkEditorOpen(programUri)
        manager.UpdateDocument(programUri, editedText, 2)
        reloadedUri := manager.HandleEditorClose(programUri)

        assert reloadedUri != null
        assert reloadedUri == programUri

        // The document survives the close, carrying the disk content again.
        assert manager.HasDocument(programUri)
        document := manager.GetDocument(programUri)
        assert document != null
        assert document.Text == programText
    } finally {
        Directory.Delete(root, true)
    }
}

test "closing a file that belongs to no workspace removes it entirely" {
    root := LscNewWorkspaceRoot()
    try {
        programText := LsdDecodedSource(
            """
func Main() {
}
"""
        )

        LsdWriteFile(root, "Program.nl", programText)

        programUri := LsdFileUri(Path.Combine(root, "Program.nl"))

        // Opened in the editor WITHOUT a workspace scan first.
        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        manager.MarkEditorOpen(programUri)
        manager.UpdateDocument(programUri, programText, 1)

        reloadedUri := manager.HandleEditorClose(programUri)

        assert reloadedUri == null
        assert !manager.HasDocument(programUri)
    } finally {
        Directory.Delete(root, true)
    }
}

test "a workspace file changed on disk is reloaded with the new content" {
    root := LscNewWorkspaceRoot()
    try {
        originalText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        updatedText := LsdDecodedSource(
            """
func Main() -> int {
    return 42
}
"""
        )

        LsdWriteFile(root, "Program.nl", originalText)

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        ignoredScan := manager.ScanWorkspaceDirectory(root)
        _ = ignoredScan

        programUri := LsdFileUri(Path.Combine(root, "Program.nl"))

        original := manager.GetDocument(programUri)
        assert original != null
        assert original.Text == originalText

        LsdWriteFile(root, "Program.nl", updatedText)

        changedUri := manager.HandleFileChangedOnDisk(Path.Combine(root, "Program.nl"))
        assert changedUri != null

        updated := manager.GetDocument(changedUri)
        assert updated != null
        assert updated.Text == updatedText
    } finally {
        Directory.Delete(root, true)
    }
}

test "a disk change to a file open in the editor never overwrites the editor buffer" {
    root := LscNewWorkspaceRoot()
    try {
        diskText := LsdDecodedSource(
            """
func Main() {
}
"""
        )
        editorText := LsdDecodedSource(
            """
func Edited() {
}
"""
        )

        LsdWriteFile(root, "Program.nl", diskText)

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        ignoredScan := manager.ScanWorkspaceDirectory(root)
        _ = ignoredScan

        programUri := LsdFileUri(Path.Combine(root, "Program.nl"))

        // The editor opens the file with different content.
        manager.MarkEditorOpen(programUri)
        manager.UpdateDocument(programUri, editorText, 2)

        // The file then changes on disk, for example through a git checkout.
        LsdWriteFile(root, "Program.nl", "func NewDisk() {}")
        changedUri := manager.HandleFileChangedOnDisk(Path.Combine(root, "Program.nl"))

        assert changedUri == null

        document := manager.GetDocument(programUri)
        assert document != null
        assert document.Text == editorText
    } finally {
        Directory.Delete(root, true)
    }
}

test "a file created on disk inside a scanned workspace is loaded" {
    root := LscNewWorkspaceRoot()
    try {
        LsdWriteFile(root, "Program.nl", "func Main() {}")

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        ignoredScan := manager.ScanWorkspaceDirectory(root)
        _ = ignoredScan

        LsdWriteFile(root, "NewFile.nl", "func New() {}")

        createdUri := manager.HandleFileCreatedOnDisk(Path.Combine(root, "NewFile.nl"))

        assert createdUri != null
        assert manager.HasDocument(createdUri)
    } finally {
        Directory.Delete(root, true)
    }
}

test "a workspace file deleted on disk stops being tracked" {
    root := LscNewWorkspaceRoot()
    try {
        LsdWriteFile(root, "Program.nl", "func Main() {}")
        LsdWriteFile(root, "ToDelete.nl", "func Delete() {}")

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        ignoredScan := manager.ScanWorkspaceDirectory(root)
        _ = ignoredScan

        deleteUri := LsdFileUri(Path.Combine(root, "ToDelete.nl"))
        assert manager.HasDocument(deleteUri)

        File.Delete(Path.Combine(root, "ToDelete.nl"))
        deletedUri := manager.HandleFileDeletedOnDisk(Path.Combine(root, "ToDelete.nl"))

        assert deletedUri != null
        assert !manager.HasDocument(deletedUri)
    } finally {
        Directory.Delete(root, true)
    }
}

test "a file deleted on disk while open in the editor stays tracked" {
    root := LscNewWorkspaceRoot()
    try {
        LsdWriteFile(root, "Program.nl", "func Main() {}")

        manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
        ignoredScan := manager.ScanWorkspaceDirectory(root)
        _ = ignoredScan

        programUri := LsdFileUri(Path.Combine(root, "Program.nl"))
        manager.MarkEditorOpen(programUri)

        File.Delete(Path.Combine(root, "Program.nl"))
        deletedUri := manager.HandleFileDeletedOnDisk(Path.Combine(root, "Program.nl"))

        assert deletedUri == null
        assert manager.HasDocument(programUri)
    } finally {
        Directory.Delete(root, true)
    }
}

test "scanning a directory that does not exist loads nothing" {
    manager := new DocumentManager(NullLogger<DocumentManager>.Instance)
    loadedUris := manager.ScanWorkspaceDirectory("/nonexistent/path")
    assert loadedUris.Count == 0
}
