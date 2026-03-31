using System;
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
    static async Task Main(string[] args)
    {
        // Setup logging
        var logPath = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".nsharp",
            "lsp.log"
        );

        System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(logPath)!);

        await Console.Error.WriteLineAsync($"N# Language Server starting... (log: {logPath})");

        try
        {
            var server = await OmniSharp.Extensions.LanguageServer.Server.LanguageServer.From(options =>
                options
                    .WithInput(Console.OpenStandardInput())
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
                        services.AddSingleton<XmlDocReader>();
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
                    .WithHandler<CodeLensHandler>()
                    .WithHandler<OnTypeFormattingHandler>()
                    .OnInitialize((server, request, cancellationToken) =>
                    {
                        var logger = server.Services.GetRequiredService<ILogger<Program>>();
                        logger.LogInformation("N# Language Server initialized");
                        logger.LogInformation("Client: {ClientName} {ClientVersion}",
                            request.ClientInfo?.Name,
                            request.ClientInfo?.Version);
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

                            // Publish diagnostics for all loaded files
                            foreach (var uri in loadedUris)
                            {
                                var publications = documentManager.GetDiagnosticsToPublish(uri);
                                foreach (var publication in publications)
                                {
                                    var diagnostics = new System.Collections.Generic.List<LspDiagnostic>();

                                    foreach (var error in publication.CompilerDiagnostics)
                                    {
                                        var line = Math.Max(0, error.Line - 1);
                                        var column = Math.Max(0, error.Column - 1);
                                        var length = Math.Max(1, error.Length);

                                        diagnostics.Add(new LspDiagnostic
                                        {
                                            Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                                                line, column, line, column + length),
                                            Severity = error.Severity == NSharpLang.Compiler.ErrorSeverity.Warning
                                                ? OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning
                                                : OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Error,
                                            Code = error.DiagnosticId,
                                            Source = "N#",
                                            Message = error.FormatForTooling(includeCode: true, includeLocation: false)
                                        });
                                    }

                                    foreach (var linterDiag in publication.LinterDiagnostics)
                                    {
                                        var line = Math.Max(0, linterDiag.Location.Line - 1);
                                        var column = Math.Max(0, linterDiag.Location.Column - 1);

                                        diagnostics.Add(new LspDiagnostic
                                        {
                                            Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                                                line, column, line, column + 1),
                                            Severity = linterDiag.Severity == NSharpLang.Compiler.DiagnosticSeverity.Error
                                                ? OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Error
                                                : OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning,
                                            Code = linterDiag.Code,
                                            Source = "N#",
                                            Message = linterDiag.Message
                                        });
                                    }

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
