using System;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Logging.Abstractions;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using OmniSharp.Extensions.LanguageServer.Protocol;
using Xunit;

namespace NSharpLang.Tests;

public sealed class LanguageServerWorkspaceDiagnosticsTests : IDisposable
{
    private readonly string _tempRoot;
    private readonly DocumentManager _documentManager;

    public LanguageServerWorkspaceDiagnosticsTests()
    {
        _tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-workspace-diagnostics-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_tempRoot);

        File.WriteAllText(Path.Combine(_tempRoot, "project.yml"), """
        name: WorkspaceDiagnostics
        """);

        _documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
    }

    public void Dispose()
    {
        if (Directory.Exists(_tempRoot))
        {
            Directory.Delete(_tempRoot, true);
        }
    }

    [Fact]
    public void GetDiagnosticsToPublish_WhenProjectIsSynchronized_PublishesAllOpenFiles()
    {
        var programText = """
        func Main() {
        }
        """;
        var personText = """
        func Broken() -> int {
            return "oops"
        }
        """;

        WriteFile("Program.nl", programText);
        WriteFile("Models/Person.nl", personText);

        var programUri = FileUri("Program.nl");
        var personUri = FileUri("Models/Person.nl");

        _documentManager.UpdateDocument(programUri, programText, 1);
        _documentManager.UpdateDocument(personUri, personText, 1);

        var publications = _documentManager.GetDiagnosticsToPublish(programUri);

        Assert.Equal(2, publications.Count);

        var programPublication = publications.Single(p => p.Uri == programUri);
        var personPublication = publications.Single(p => p.Uri == personUri);

        Assert.Empty(programPublication.CompilerDiagnostics);
        Assert.Contains(personPublication.CompilerDiagnostics, error => error.Severity == ErrorSeverity.Error);
    }

    [Fact]
    public void GetDiagnosticsToPublish_WhenWorkspaceIsUnsynchronized_FallsBackToCurrentDocumentOnly()
    {
        var onDiskProgramText = """
        func Main() {
        }
        """;
        var dirtyProgramText = """
        func Main() -> int {
            return "oops"
        }
        """;
        var personText = """
        func Helper() {
        }
        """;

        WriteFile("Program.nl", onDiskProgramText);
        WriteFile("Models/Person.nl", personText);

        var programUri = FileUri("Program.nl");
        var personUri = FileUri("Models/Person.nl");

        _documentManager.UpdateDocument(programUri, dirtyProgramText, 1);
        _documentManager.UpdateDocument(personUri, personText, 1);

        var publications = _documentManager.GetDiagnosticsToPublish(programUri);

        Assert.Single(publications);
        Assert.Equal(programUri, publications[0].Uri);
        Assert.Contains(publications[0].CompilerDiagnostics, error => error.Severity == ErrorSeverity.Error);
    }

    [Fact]
    public void ScanWorkspaceDirectory_LoadsAllNlFiles()
    {
        var programText = """
        func Main() {
        }
        """;
        var helperText = """
        func Helper() {
        }
        """;

        WriteFile("Program.nl", programText);
        WriteFile("Utils/Helper.nl", helperText);

        var loadedUris = _documentManager.ScanWorkspaceDirectory(_tempRoot);

        Assert.Equal(2, loadedUris.Count);
        Assert.Contains(loadedUris, u => u.Contains("Program.nl"));
        Assert.Contains(loadedUris, u => u.Contains("Helper.nl"));
    }

    [Fact]
    public void ScanWorkspaceDirectory_PublishesDiagnosticsForErrorFiles()
    {
        var goodText = """
        func Main() {
        }
        """;
        var badText = """
        func Broken() -> int {
            return "oops"
        }
        """;

        WriteFile("Good.nl", goodText);
        WriteFile("Bad.nl", badText);

        var loadedUris = _documentManager.ScanWorkspaceDirectory(_tempRoot);

        // Both files should be loaded
        Assert.Equal(2, loadedUris.Count);

        // Check that diagnostics are available for each file
        var goodUri = loadedUris.Single(u => u.Contains("Good.nl"));
        var badUri = loadedUris.Single(u => u.Contains("Bad.nl"));

        var goodPubs = _documentManager.GetDiagnosticsToPublish(goodUri);
        var badPubs = _documentManager.GetDiagnosticsToPublish(badUri);

        // Both should have publications (project-wide when synchronized)
        Assert.True(goodPubs.Count >= 1);
        Assert.True(badPubs.Count >= 1);

        // Bad file should have errors
        var badPub = badPubs.Single(p => p.Uri == badUri);
        Assert.Contains(badPub.CompilerDiagnostics, e => e.Severity == ErrorSeverity.Error);
    }

    [Fact]
    public void ScanWorkspaceDirectory_SkipsEditorOpenFiles()
    {
        var programText = """
        func Main() {
        }
        """;
        var helperText = """
        func Helper() {
        }
        """;

        WriteFile("Program.nl", programText);
        WriteFile("Helper.nl", helperText);

        var programUri = FileUri("Program.nl");

        // Simulate editor opening the file first
        _documentManager.MarkEditorOpen(programUri);
        _documentManager.UpdateDocument(programUri, programText, 1);

        var loadedUris = _documentManager.ScanWorkspaceDirectory(_tempRoot);

        // Only Helper.nl should have been loaded by the scan
        Assert.Single(loadedUris);
        Assert.Contains(loadedUris, u => u.Contains("Helper.nl"));

        // But Program.nl should still be tracked (from editor open)
        Assert.True(_documentManager.HasDocument(programUri));
    }

    [Fact]
    public void HandleEditorClose_ReloadsFromDiskWhenInWorkspace()
    {
        var programText = """
        func Main() {
        }
        """;
        var editedText = """
        func Main() -> int {
            return 42
        }
        """;

        WriteFile("Program.nl", programText);

        // Scan workspace first
        _documentManager.ScanWorkspaceDirectory(_tempRoot);

        var programUri = FileUri("Program.nl");

        // Editor opens and modifies the file
        _documentManager.MarkEditorOpen(programUri);
        _documentManager.UpdateDocument(programUri, editedText, 2);

        // Editor closes the file
        var reloadedUri = _documentManager.HandleEditorClose(programUri);

        // Should reload from disk (workspace file)
        Assert.NotNull(reloadedUri);
        Assert.Equal(programUri, reloadedUri);

        // Document should still exist with disk content
        Assert.True(_documentManager.HasDocument(programUri));
        var doc = _documentManager.GetDocument(programUri);
        Assert.Equal(programText, doc?.Text);
    }

    [Fact]
    public void HandleEditorClose_RemovesNonWorkspaceFiles()
    {
        var programText = """
        func Main() {
        }
        """;

        WriteFile("Program.nl", programText);

        var programUri = FileUri("Program.nl");

        // Open in editor WITHOUT scanning workspace first
        _documentManager.MarkEditorOpen(programUri);
        _documentManager.UpdateDocument(programUri, programText, 1);

        // Close the file
        var reloadedUri = _documentManager.HandleEditorClose(programUri);

        // Should be fully removed (not a workspace file)
        Assert.Null(reloadedUri);
        Assert.False(_documentManager.HasDocument(programUri));
    }

    [Fact]
    public void HandleFileChangedOnDisk_UpdatesWorkspaceFile()
    {
        var originalText = """
        func Main() {
        }
        """;
        var updatedText = """
        func Main() -> int {
            return 42
        }
        """;

        WriteFile("Program.nl", originalText);

        _documentManager.ScanWorkspaceDirectory(_tempRoot);

        var programUri = FileUri("Program.nl");

        // Verify original content
        var doc = _documentManager.GetDocument(programUri);
        Assert.Equal(originalText, doc?.Text);

        // Change file on disk
        WriteFile("Program.nl", updatedText);

        var filePath = Path.Combine(_tempRoot, "Program.nl");
        var changedUri = _documentManager.HandleFileChangedOnDisk(filePath);

        Assert.NotNull(changedUri);

        // Verify updated content
        doc = _documentManager.GetDocument(changedUri!);
        Assert.Equal(updatedText, doc?.Text);
    }

    [Fact]
    public void HandleFileChangedOnDisk_SkipsEditorOpenFiles()
    {
        var diskText = """
        func Main() {
        }
        """;
        var editorText = """
        func Edited() {
        }
        """;

        WriteFile("Program.nl", diskText);

        _documentManager.ScanWorkspaceDirectory(_tempRoot);

        var programUri = FileUri("Program.nl");

        // Editor opens with different content
        _documentManager.MarkEditorOpen(programUri);
        _documentManager.UpdateDocument(programUri, editorText, 2);

        // File changes on disk (e.g., git checkout)
        WriteFile("Program.nl", "func NewDisk() {}");
        var filePath = Path.Combine(_tempRoot, "Program.nl");
        var changedUri = _documentManager.HandleFileChangedOnDisk(filePath);

        // Should be skipped since editor has it open
        Assert.Null(changedUri);

        // Editor content should be preserved
        var doc = _documentManager.GetDocument(programUri);
        Assert.Equal(editorText, doc?.Text);
    }

    [Fact]
    public void HandleFileCreatedOnDisk_LoadsNewWorkspaceFile()
    {
        WriteFile("Program.nl", "func Main() {}");
        _documentManager.ScanWorkspaceDirectory(_tempRoot);

        // Create a new file
        WriteFile("NewFile.nl", "func New() {}");

        var filePath = Path.Combine(_tempRoot, "NewFile.nl");
        var createdUri = _documentManager.HandleFileCreatedOnDisk(filePath);

        Assert.NotNull(createdUri);
        Assert.True(_documentManager.HasDocument(createdUri!));
    }

    [Fact]
    public void HandleFileDeletedOnDisk_RemovesWorkspaceFile()
    {
        WriteFile("Program.nl", "func Main() {}");
        WriteFile("ToDelete.nl", "func Delete() {}");

        _documentManager.ScanWorkspaceDirectory(_tempRoot);

        var deleteUri = FileUri("ToDelete.nl");
        Assert.True(_documentManager.HasDocument(deleteUri));

        // Delete the file
        File.Delete(Path.Combine(_tempRoot, "ToDelete.nl"));
        var filePath = Path.Combine(_tempRoot, "ToDelete.nl");
        var deletedUri = _documentManager.HandleFileDeletedOnDisk(filePath);

        Assert.NotNull(deletedUri);
        Assert.False(_documentManager.HasDocument(deletedUri!));
    }

    [Fact]
    public void HandleFileDeletedOnDisk_SkipsEditorOpenFiles()
    {
        WriteFile("Program.nl", "func Main() {}");
        _documentManager.ScanWorkspaceDirectory(_tempRoot);

        var programUri = FileUri("Program.nl");
        _documentManager.MarkEditorOpen(programUri);

        var filePath = Path.Combine(_tempRoot, "Program.nl");
        File.Delete(filePath);

        var deletedUri = _documentManager.HandleFileDeletedOnDisk(filePath);

        // Should not remove since editor has it open
        Assert.Null(deletedUri);
        Assert.True(_documentManager.HasDocument(programUri));
    }

    [Fact]
    public void ScanWorkspaceDirectory_NonexistentDirectory_ReturnsEmpty()
    {
        var result = _documentManager.ScanWorkspaceDirectory("/nonexistent/path");
        Assert.Empty(result);
    }

    private void WriteFile(string relativePath, string text)
    {
        var fullPath = Path.Combine(_tempRoot, relativePath);
        var directory = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(fullPath, text);
    }

    private string FileUri(string relativePath)
    {
        return DocumentUri.FromFileSystemPath(Path.Combine(_tempRoot, relativePath)).ToString();
    }
}
