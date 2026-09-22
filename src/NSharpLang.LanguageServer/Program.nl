namespace NSharpLang.LanguageServer

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.IO.Pipelines
import System.Linq
import System.Threading.Tasks
import Microsoft.Extensions.DependencyInjection
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Handlers
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models
import OmniSharp.Extensions.LanguageServer.Server

// THE SERVER MUST NOT OUTLIVE ITS CLIENT — the second of two event-driven ends (the first is the
// stdin pump in `main`). A client already gone when it introduces itself is the same answer, sooner.
//
// camelCase, so this is the assembly's own: nothing outside it can reach the process watch.
func watchClientProcess(clientProcessId: long?) {
    if clientProcessId == null {
        return
    }

    clientPid := (int)clientProcessId
    try {
        _ = Process.GetProcessById(clientPid).WaitForExitAsync().ContinueWith(completed => Environment.Exit(0), TaskScheduler.Default)
    } catch missing: ArgumentException {
        Environment.Exit(0)
    }
}

// The whole diagnostics payload for one publication, in the order the wire carries it: the
// compiler's own errors first, then the linter's.
func publicationDiagnostics(publication: DocumentDiagnosticsPublication): List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic> {
    diagnostics := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>()
    for error in publication.CompilerDiagnostics {
        diagnostics.Add(LspDiagnosticConverter.FromCompilerError(error))
    }

    for linterDiagnostic in publication.LinterDiagnostics {
        diagnostics.Add(LspDiagnosticConverter.FromLinterDiagnostic(linterDiagnostic))
    }

    return diagnostics
}

// The workspace root the client introduced itself with, in the precedence the protocol defines:
// the first workspace folder, then `rootUri`, then the deprecated `rootPath`.
func workspaceRootOf(request: InitializeParams): string? {
    folderPath: string? = null
    folders := request.WorkspaceFolders
    if folders != null && folders.Any() {
        folderPath = folders.First().Uri.GetFileSystemPath()
    }

    rootUriPath: string? = null
    rootUri := request.RootUri
    if rootUri != null {
        rootUriPath = rootUri.GetFileSystemPath()
    }

    return EditorWorkspaceFacts.WorkspaceRootChoice(folderPath, rootUriPath, request.RootPath)
}

// Everything the host is told, in the order the client is told it: the two streams, the log
// file, the two services, the 27 handlers and the two lifecycle callbacks.
//
// COMPILER: lsflip-1. This is a NAMED function rather than the block lambda the C# wrote inline,
// because a CAPTURING outer lambda breaks an external extension call inside a lambda nested in it:
// `logger.LogInformation(...)` in `OnInitialize` declines with
// `emit.call.instance-member-unmodeled` as soon as the enclosing `options => { ... }` reads a local
// of `main`. Naming the body captures nothing, and the registration order is the same statement
// order the C# chain had.
func configureServer(options: LanguageServerOptions, clientInput: Pipe, logPath: string): LanguageServerOptions {
    options.WithInput(clientInput.Reader)
    options.WithOutput(Console.OpenStandardOutput())
    options.ConfigureLogging(builder => {
        builder.AddFile(logPath)
        builder.SetMinimumLevel(LogLevel.Debug)
    })
    options.WithServices(services => {
        services.AddSingleton<DocumentManager>()
        services.AddSingleton<TypeResolver>()
    })
    options.WithHandler<TextDocumentHandler>()
    options.WithHandler<CompletionHandler>()
    options.WithHandler<HoverHandler>()
    options.WithHandler<SignatureHelpHandler>()
    options.WithHandler<DefinitionHandler>()
    options.WithHandler<CodeActionHandler>()
    options.WithHandler<RenameHandler>()
    options.WithHandler<PrepareRenameHandler>()
    options.WithHandler<ReferencesHandler>()
    options.WithHandler<InlayHintHandler>()
    options.WithHandler<DocumentSymbolHandler>()
    options.WithHandler<SemanticTokensHandler>()
    options.WithHandler<WorkspaceSymbolHandler>()
    options.WithHandler<FoldingRangeHandler>()
    options.WithHandler<DidChangeWatchedFilesHandler>()
    options.WithHandler<DocumentFormattingHandler>()
    options.WithHandler<GoToImplementationHandler>()
    options.WithHandler<DocumentHighlightHandler>()
    options.WithHandler<SelectionRangeHandler>()
    options.WithHandler<CallHierarchyPrepareHandler>()
    options.WithHandler<CallHierarchyIncomingHandler>()
    options.WithHandler<CallHierarchyOutgoingHandler>()
    options.WithHandler<TypeHierarchyPrepareHandler>()
    options.WithHandler<TypeHierarchySupertypesHandler>()
    options.WithHandler<TypeHierarchySubtypesHandler>()
    options.WithHandler<DocumentLinkHandler>()
    options.WithHandler<OnTypeFormattingHandler>()
    options.OnInitialize((initializingServer, request, cancellationToken) => {
        logger := initializingServer.Services.GetRequiredService<ILogger<Program>>()
        clientInfo := request.ClientInfo
        clientName := clientInfo?.Name
        clientVersion := clientInfo?.Version
        logger.LogInformation("N# Language Server initialized for client {ClientName} {ClientVersion}", clientName, clientVersion)
        watchClientProcess(request.ProcessId)
        return Task.CompletedTask
    })
    options.OnInitialized((initializedServer, request, response, cancellationToken) => {
        logger := initializedServer.Services.GetRequiredService<ILogger<Program>>()
        documentManager := initializedServer.Services.GetRequiredService<DocumentManager>()

        workspaceRoot := workspaceRootOf(request)

        if workspaceRoot != null {
            logger.LogInformation("Scanning workspace for .nl files: {Root}", workspaceRoot)
            loadedUris := documentManager.ScanWorkspaceDirectory(workspaceRoot)

            for uri in loadedUris {
                publications := documentManager.GetDiagnosticsToPublish(uri)
                for publication in publications {
                    diagnostics := publicationDiagnostics(publication)
                    initializedServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams {
                        Uri: DocumentUri.From(publication.Uri),
                        Diagnostics: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>(diagnostics)
                    })
                }
            }

            logger.LogInformation("Published workspace diagnostics for {Count} files", loadedUris.Count)
        } else {
            logger.LogWarning("No workspace root provided — skipping workspace scan")
        }

        return Task.CompletedTask
    })

    return options
}

async func main(): Task {
    userProfile := Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
    logPath := Path.Combine(userProfile, ".nsharp", "lsp.log")
    logDirectory := Path.GetDirectoryName(logPath)
    Directory.CreateDirectory(must logDirectory)

    await Console.Error.WriteLineAsync($"N# Language Server starting... (log: {logPath})")

    // stdin is PUMPED into a pipe instead of being handed to the server, because only this end can
    // see the client close it: the copy completes at EOF and the process leaves instead of orphaning.
    clientInput := new Pipe()
    _ = Console.OpenStandardInput().CopyToAsync(clientInput.Writer.AsStream()).ContinueWith(pumped => Environment.Exit(0), TaskScheduler.Default)

    try {
        server := await LanguageServer.From(options => configureServer(options, clientInput, logPath))

        await Console.Error.WriteLineAsync("N# Language Server initialized successfully")

        await server.WaitForExit
    } catch fatal: Exception {
        await Console.Error.WriteLineAsync($"Fatal error in Language Server: {fatal}")
        throw
    }
}
