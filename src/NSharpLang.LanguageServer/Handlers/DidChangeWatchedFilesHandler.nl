namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import MediatR
import Microsoft.Extensions.Logging
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models
import OmniSharp.Extensions.LanguageServer.Protocol.Server
import OmniSharp.Extensions.LanguageServer.Protocol.Workspace

// Handles workspace/didChangeWatchedFiles notifications so that diagnostics are
// kept up-to-date when .nl files are created, changed, or deleted on disk.
class DidChangeWatchedFilesHandler: DidChangeWatchedFilesHandlerBase {
    readonly documentManager: DocumentManager
    readonly languageServer: ILanguageServerFacade
    readonly logger: ILogger<DidChangeWatchedFilesHandler>

    constructor(
        documentManager: DocumentManager,
        languageServer: ILanguageServerFacade,
        logger: ILogger<DidChangeWatchedFilesHandler>
    ) {
        this.documentManager = documentManager
        this.languageServer = languageServer
        this.logger = logger
    }

    override func Handle(request: DidChangeWatchedFilesParams, cancellationToken: CancellationToken): Task<Unit> {
        for change in request.Changes {
            filePath := change.Uri.GetFileSystemPath()
            if string.IsNullOrEmpty(filePath) || !filePath.EndsWith(".nl", StringComparison.OrdinalIgnoreCase) {
                continue
            }

            changeType := change.Type
            logger.LogInformation("File watcher event: {Type} {Path}", changeType, filePath)

            updatedUri: string? = null

            if changeType == FileChangeType.Created {
                updatedUri = documentManager.HandleFileCreatedOnDisk(filePath)
                if updatedUri != null {
                    publishDiagnostics(updatedUri)
                }
            } else if changeType == FileChangeType.Changed {
                updatedUri = documentManager.HandleFileChangedOnDisk(filePath)
                if updatedUri != null {
                    publishDiagnostics(updatedUri)
                }
            } else if changeType == FileChangeType.Deleted {
                updatedUri = documentManager.HandleFileDeletedOnDisk(filePath)
                if updatedUri != null {
                    // Clear diagnostics for deleted file
                    languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams {
                        Uri: DocumentUri.From(updatedUri),
                        Diagnostics: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>()
                    })
                }
            }
        }

        return Unit.Task
    }

    protected override func CreateRegistrationOptions(
        capability: DidChangeWatchedFilesCapability,
        clientCapabilities: ClientCapabilities
    ): DidChangeWatchedFilesRegistrationOptions {
        watcher := new FileSystemWatcher {
            GlobPattern: "**/*.nl",
            Kind: WatchKind.Create | WatchKind.Change | WatchKind.Delete
        }

        return new DidChangeWatchedFilesRegistrationOptions {
            Watchers: new Container<FileSystemWatcher>(watcher)
        }
    }

    func publishDiagnostics(uri: string) {
        publications := documentManager.GetDiagnosticsToPublish(uri)
        for publication in publications {
            allDiagnostics := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>()

            for error in publication.CompilerDiagnostics {
                allDiagnostics.Add(LspDiagnosticConverter.FromCompilerError(error))
            }

            for diagnostic in publication.LinterDiagnostics {
                allDiagnostics.Add(LspDiagnosticConverter.FromLinterDiagnostic(diagnostic))
            }

            languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams {
                Uri: DocumentUri.From(publication.Uri),
                Diagnostics: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>(allDiagnostics)
            })

            logger.LogInformation("Published {Count} diagnostics for {Uri} (file watcher)", allDiagnostics.Count, publication.Uri)
        }
    }
}
