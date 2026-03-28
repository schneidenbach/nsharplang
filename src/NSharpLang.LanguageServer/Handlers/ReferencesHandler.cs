using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
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
            var word = GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
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

            // If we have a synchronized snapshot but got no results, the symbol doesn't exist
            if (_documentManager.HasSynchronizedProjectSnapshot(uri))
            {
                return Task.FromResult<LocationContainer?>(new LocationContainer());
            }

            // Verify the symbol exists before falling back to text search
            var isKnownSymbol = false;
            if (doc.SymbolLocations?.ContainsKey(word) == true)
                isKnownSymbol = true;
            else if (doc.SemanticModel?.LookupIdentifier(word) != null)
                isKnownSymbol = true;

            if (!isKnownSymbol)
            {
                _logger.LogDebug("Symbol '{Name}' not found in symbol locations or semantic model", word);
                return Task.FromResult<LocationContainer?>(new LocationContainer());
            }

            // Fallback: text-based single-document search
            var textReferences = _documentManager.FindAllReferences(uri, word);
            if (textReferences.Count == 0)
            {
                return Task.FromResult<LocationContainer?>(new LocationContainer());
            }

            var fallbackLocations = textReferences
                .Select(r => new Location
                {
                    Uri = DocumentUri.From(uri),
                    Range = new LspRange(r.Line, r.Column, r.Line, r.Column + r.Length)
                })
                .ToList();

            return Task.FromResult<LocationContainer?>(new LocationContainer(fallbackLocations));
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

    private static string GetWordAtPosition(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return string.Empty;

        var lineText = lines[line];
        if (lineText.Length == 0) return string.Empty;
        if (character < 0 || character >= lineText.Length) return string.Empty;
        if (!IsIdentifierChar(lineText[character])) return string.Empty;

        int start = character;
        while (start > 0 && IsIdentifierChar(lineText[start - 1]))
            start--;

        int end = character;
        while (end < lineText.Length && IsIdentifierChar(lineText[end]))
            end++;

        return lineText.Substring(start, end - start);
    }

    private static bool IsIdentifierChar(char c) => char.IsLetterOrDigit(c) || c == '_';
}
