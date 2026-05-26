using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using MediatR;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using OmniSharp.Extensions.LanguageServer.Protocol.Server;
using OmniSharp.Extensions.LanguageServer.Protocol.Workspace;
using LspDiagnostic = OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic;
using LspDiagnosticSeverity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity;
using LspFileSystemWatcher = OmniSharp.Extensions.LanguageServer.Protocol.Models.FileSystemWatcher;
using CompilerDiagnostic = NSharpLang.Compiler.Diagnostic;
using DiagnosticSeverity = NSharpLang.Compiler.DiagnosticSeverity;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles workspace/didChangeWatchedFiles notifications so that diagnostics are
/// kept up-to-date when .nl files are created, changed, or deleted on disk.
/// </summary>
public class DidChangeWatchedFilesHandler : DidChangeWatchedFilesHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILanguageServerFacade _languageServer;
    private readonly ILogger<DidChangeWatchedFilesHandler> _logger;

    public DidChangeWatchedFilesHandler(
        DocumentManager documentManager,
        ILanguageServerFacade languageServer,
        ILogger<DidChangeWatchedFilesHandler> logger)
    {
        _documentManager = documentManager;
        _languageServer = languageServer;
        _logger = logger;
    }

    public override Task<Unit> Handle(DidChangeWatchedFilesParams request, CancellationToken cancellationToken)
    {
        foreach (var change in request.Changes)
        {
            var filePath = change.Uri.GetFileSystemPath();
            if (string.IsNullOrEmpty(filePath) || !filePath.EndsWith(".nl", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            _logger.LogInformation("File watcher event: {Type} {Path}", change.Type, filePath);

            string? updatedUri = null;

            switch (change.Type)
            {
                case FileChangeType.Created:
                    updatedUri = _documentManager.HandleFileCreatedOnDisk(filePath);
                    if (updatedUri != null)
                    {
                        PublishDiagnostics(updatedUri);
                    }
                    break;

                case FileChangeType.Changed:
                    updatedUri = _documentManager.HandleFileChangedOnDisk(filePath);
                    if (updatedUri != null)
                    {
                        PublishDiagnostics(updatedUri);
                    }
                    break;

                case FileChangeType.Deleted:
                    updatedUri = _documentManager.HandleFileDeletedOnDisk(filePath);
                    if (updatedUri != null)
                    {
                        // Clear diagnostics for deleted file
                        _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
                        {
                            Uri = DocumentUri.From(updatedUri),
                            Diagnostics = new Container<LspDiagnostic>()
                        });
                    }
                    break;
            }
        }

        return Unit.Task;
    }

    protected override DidChangeWatchedFilesRegistrationOptions CreateRegistrationOptions(
        DidChangeWatchedFilesCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DidChangeWatchedFilesRegistrationOptions
        {
            Watchers = new Container<LspFileSystemWatcher>(
                new LspFileSystemWatcher
                {
                    GlobPattern = "**/*.nl",
                    Kind = WatchKind.Create | WatchKind.Change | WatchKind.Delete
                }
            )
        };
    }

    private void PublishDiagnostics(string uri)
    {
        var publications = _documentManager.GetDiagnosticsToPublish(uri);
        foreach (var publication in publications)
        {
            var allDiagnostics = new System.Collections.Generic.List<LspDiagnostic>();

            allDiagnostics.AddRange(publication.CompilerDiagnostics.Select(ConvertCompilerErrorToDiagnostic));
            allDiagnostics.AddRange(publication.LinterDiagnostics.Select(ConvertLinterDiagnosticToDiagnostic));

            _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
            {
                Uri = DocumentUri.From(publication.Uri),
                Diagnostics = new Container<LspDiagnostic>(allDiagnostics)
            });

            _logger.LogInformation("Published {Count} diagnostics for {Uri} (file watcher)", allDiagnostics.Count, publication.Uri);
        }
    }

    private LspDiagnostic ConvertCompilerErrorToDiagnostic(CompilerError error)
        => LspDiagnosticConverter.FromCompilerError(error);

    private LspDiagnostic ConvertLinterDiagnosticToDiagnostic(CompilerDiagnostic diagnostic)
    {
        var line = Math.Max(0, diagnostic.Location.Line - 1);
        var column = Math.Max(0, diagnostic.Location.Column - 1);

        var severity = diagnostic.Severity switch
        {
            DiagnosticSeverity.Error => LspDiagnosticSeverity.Error,
            DiagnosticSeverity.Warning => LspDiagnosticSeverity.Warning,
            DiagnosticSeverity.Info => LspDiagnosticSeverity.Information,
            _ => LspDiagnosticSeverity.Warning
        };

        int length = 1;
        var quoteMatch = System.Text.RegularExpressions.Regex.Match(diagnostic.Message, @"'([^']+)'");
        if (quoteMatch.Success)
        {
            length = quoteMatch.Groups[1].Value.Length;
        }

        return new LspDiagnostic
        {
            Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(line, column, line, column + length),
            Severity = severity,
            Code = diagnostic.Code,
            Source = "N#",
            Message = diagnostic.Message
        };
    }
}
