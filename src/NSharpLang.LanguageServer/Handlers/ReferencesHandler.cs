using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.JsonRpc.Server;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles find-all-references requests (Shift+F12 in VS Code)
/// </summary>
public class ReferencesHandler : ReferencesHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<ReferencesHandler> _logger;

    public ReferencesHandler(DocumentManager documentManager, ILogger<ReferencesHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<LocationContainer?> Handle(ReferenceParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<LocationContainer?>(new LocationContainer());
        }

        try
        {
            var word = EditorUtilities.GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<LocationContainer?>(new LocationContainer());
            }

            _logger.LogDebug("Find references for: {Word}", word);

            // Try semantic cross-file resolution via CodeIntelligenceService
            var projectReferences = _documentManager.FindProjectReferences(uri, request.Position.Line, request.Position.Character);
            if (projectReferences != null)
            {
                var projectRoot = _documentManager.GetProjectRootForUri(uri);
                var includeDeclaration = request.Context?.IncludeDeclaration ?? true;

                var locations = projectReferences
                    .Where(r => includeDeclaration || !r.IsDefinition)
                    .Select(r =>
                    {
                        var filePath = _documentManager.ResolveProjectFilePath(projectRoot, r.File);
                        return new Location
                        {
                            Uri = DocumentUri.From(new Uri(filePath).AbsoluteUri),
                            Range = new LspRange(
                                r.Line - 1,
                                r.Column - 1,
                                r.Line - 1,
                                r.Column - 1 + Math.Max(1, r.Length))
                        };
                    })
                    .ToList();

                return Task.FromResult<LocationContainer?>(new LocationContainer(locations));
            }

            // A synchronized project snapshot is authoritative for references; do
            // not degrade to text search when the binding map has no precise target.
            if (_documentManager.HasSynchronizedProjectSnapshot(uri))
            {
                return Task.FromResult<LocationContainer?>(new LocationContainer());
            }

            if (_documentManager.HasSemanticProjectContext(uri))
            {
                throw ReferencesUnavailable(
                    $"References for '{word}' are unavailable because semantic project analysis is degraded. " +
                    "Save or fix the project files and retry; refusing text-only references to avoid showing unrelated symbols.");
            }

            var documentReferences = _documentManager.FindStrictDocumentReferences(
                uri,
                request.Position.Line,
                request.Position.Character);
            if (documentReferences == null || documentReferences.Count == 0)
            {
                return Task.FromResult<LocationContainer?>(new LocationContainer());
            }

            var documentLocations = documentReferences
                .Select(r => new Location
                {
                    Uri = DocumentUri.From(uri),
                    Range = new LspRange(
                        r.Line - 1,
                        r.Column - 1,
                        r.Line - 1,
                        r.Column - 1 + Math.Max(1, r.Length))
                })
                .ToList();

            return Task.FromResult<LocationContainer?>(new LocationContainer(documentLocations));
        }
        catch (RequestFailedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling find references");
            return Task.FromResult<LocationContainer?>(new LocationContainer());
        }
    }

    protected override ReferenceRegistrationOptions CreateRegistrationOptions(
        ReferenceCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new ReferenceRegistrationOptions();
    }

    private static RequestFailedException ReferencesUnavailable(string message)
    {
        return new RequestFailedException(
            ErrorCodes.RequestFailed,
            message,
            RequestFailedException.UnknownRequestId,
            inner: null!);
    }
}
