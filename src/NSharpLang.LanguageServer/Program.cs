using System;
using System.Diagnostics;
using System.IO.Pipelines;
using System.Linq;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Handlers;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using OmniSharp.Extensions.LanguageServer.Server;
using LspDiagnostic = OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic;

namespace NSharpLang.LanguageServer;

class Program
{
    // THE SERVER MUST NOT OUTLIVE ITS CLIENT — the second of two event-driven ends (the first is the
    // stdin pump in `Main`). A client already gone when it introduces itself is the same answer, sooner.
    static void WatchClientProcess(long? clientProcessId)
    {
        if (clientProcessId is not long clientPid) return;
        try { _ = Process.GetProcessById((int)clientPid).WaitForExitAsync().ContinueWith(_ => Environment.Exit(0), TaskScheduler.Default); }
        catch (ArgumentException) { Environment.Exit(0); }
    }

    static async Task Main(string[] args)
    {
        var logPath = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nsharp", "lsp.log");
        System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(logPath)!);

        await Console.Error.WriteLineAsync($"N# Language Server starting... (log: {logPath})");

        // stdin is PUMPED into a pipe instead of being handed to the server, because only this end can
        // see the client close it: the copy completes at EOF and the process leaves instead of orphaning.
        var clientInput = new Pipe();
        _ = Console.OpenStandardInput().CopyToAsync(clientInput.Writer.AsStream()).ContinueWith(_ => Environment.Exit(0), TaskScheduler.Default);

        try
        {
            var server = await OmniSharp.Extensions.LanguageServer.Server.LanguageServer.From(options =>
                options
                    .WithInput(clientInput.Reader)
                    .WithOutput(Console.OpenStandardOutput())
                    .ConfigureLogging(builder =>
                    {
                        builder
                            .AddFile(logPath)
                            .SetMinimumLevel(LogLevel.Debug);
                    })
                    .WithServices(services =>
                    {
                        services.AddSingleton<DocumentManager>();
                        services.AddSingleton<TypeResolver>();
                    })
                    .WithHandler<TextDocumentHandler>()
                    .WithHandler<CompletionHandler>()
                    .WithHandler<HoverHandler>()
                    .WithHandler<SignatureHelpHandler>()
                    .WithHandler<DefinitionHandler>()
                    .WithHandler<CodeActionHandler>()
                    .WithHandler<RenameHandler>()
                    .WithHandler<PrepareRenameHandler>()
                    .WithHandler<ReferencesHandler>()
                    .WithHandler<InlayHintHandler>()
                    .WithHandler<DocumentSymbolHandler>()
                    .WithHandler<SemanticTokensHandler>()
                    .WithHandler<WorkspaceSymbolHandler>()
                    .WithHandler<FoldingRangeHandler>()
                    .WithHandler<DidChangeWatchedFilesHandler>()
                    .WithHandler<DocumentFormattingHandler>()
                    .WithHandler<GoToImplementationHandler>()
                    .WithHandler<DocumentHighlightHandler>()
                    .WithHandler<SelectionRangeHandler>()
                    .WithHandler<CallHierarchyPrepareHandler>()
                    .WithHandler<CallHierarchyIncomingHandler>()
                    .WithHandler<CallHierarchyOutgoingHandler>()
                    .WithHandler<TypeHierarchyPrepareHandler>()
                    .WithHandler<TypeHierarchySupertypesHandler>()
                    .WithHandler<TypeHierarchySubtypesHandler>()
                    .WithHandler<DocumentLinkHandler>()
                    .WithHandler<OnTypeFormattingHandler>()
                    .OnInitialize((server, request, cancellationToken) =>
                    {
                        var logger = server.Services.GetRequiredService<ILogger<Program>>();
                        logger.LogInformation("N# Language Server initialized for client {ClientName} {ClientVersion}", request.ClientInfo?.Name, request.ClientInfo?.Version);
                        WatchClientProcess(request.ProcessId);
                        return Task.CompletedTask;
                    })
                    .OnInitialized((server, request, response, cancellationToken) =>
                    {
                        var logger = server.Services.GetRequiredService<ILogger<Program>>();
                        var documentManager = server.Services.GetRequiredService<DocumentManager>();

                        // Determine workspace root from initialize params
                        string? workspaceRoot = null;

                        if (request.WorkspaceFolders?.Any() == true)
                        {
                            workspaceRoot = request.WorkspaceFolders.First().Uri.GetFileSystemPath();
                        }
                        else if (request.RootUri != null)
                        {
                            workspaceRoot = request.RootUri.GetFileSystemPath();
                        }
                        else if (!string.IsNullOrEmpty(request.RootPath))
                        {
                            workspaceRoot = request.RootPath;
                        }

                        if (workspaceRoot != null)
                        {
                            logger.LogInformation("Scanning workspace for .nl files: {Root}", workspaceRoot);
                            var loadedUris = documentManager.ScanWorkspaceDirectory(workspaceRoot);

                            foreach (var uri in loadedUris)
                            {
                                var publications = documentManager.GetDiagnosticsToPublish(uri);
                                foreach (var publication in publications)
                                {
                                    var diagnostics = publication.CompilerDiagnostics.Select(LspDiagnosticConverter.FromCompilerError)
                                        .Concat(publication.LinterDiagnostics.Select(LspDiagnosticConverter.FromLinterDiagnostic));

                                    server.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
                                    {
                                        Uri = DocumentUri.From(publication.Uri),
                                        Diagnostics = new Container<LspDiagnostic>(diagnostics)
                                    });
                                }
                            }

                            logger.LogInformation("Published workspace diagnostics for {Count} files", loadedUris.Count);
                        }
                        else
                        {
                            logger.LogWarning("No workspace root provided — skipping workspace scan");
                        }

                        return Task.CompletedTask;
                    })
            );

            await Console.Error.WriteLineAsync("N# Language Server initialized successfully");

            await server.WaitForExit;
        }
        catch (Exception ex)
        {
            await Console.Error.WriteLineAsync($"Fatal error in Language Server: {ex}");
            throw;
        }
    }
}
