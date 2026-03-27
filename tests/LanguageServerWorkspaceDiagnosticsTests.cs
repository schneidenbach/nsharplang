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
