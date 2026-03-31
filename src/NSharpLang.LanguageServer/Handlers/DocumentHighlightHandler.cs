using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles document highlight requests — when a user places the cursor on a symbol,
/// all occurrences of that symbol in the current file are highlighted.
/// </summary>
public class DocumentHighlightHandler : DocumentHighlightHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DocumentHighlightHandler> _logger;

    public DocumentHighlightHandler(DocumentManager documentManager, ILogger<DocumentHighlightHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<DocumentHighlightContainer?> Handle(DocumentHighlightParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer());
        }

        try
        {
            var line = request.Position.Line;
            var character = request.Position.Character;

            var word = EditorUtilities.GetWordAtPosition(doc.Text, line, character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer());
            }

            _logger.LogDebug("Document highlight for: {Word} at {Line}:{Character}", word, line, character);

            // Tier 1: Semantic highlights via BindingMap
            if (doc.Bindings != null)
            {
                var highlights = GetSemanticHighlights(doc, uri, line, character);
                if (highlights.Count > 0)
                {
                    return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer(highlights));
                }
            }

            // Tier 2: Text-based fallback
            var textReferences = _documentManager.FindAllReferences(uri, word);
            if (textReferences.Count > 0)
            {
                var textHighlights = textReferences
                    .Select(r => new DocumentHighlight
                    {
                        Kind = DocumentHighlightKind.Text,
                        Range = new LspRange(r.Line, r.Column, r.Line, r.Column + r.Length)
                    })
                    .ToList();

                return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer(textHighlights));
            }

            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling document highlight");
            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer());
        }
    }

    private List<DocumentHighlight> GetSemanticHighlights(Models.DocumentState doc, string uri, int line, int character)
    {
        var highlights = new List<DocumentHighlight>();

        // BindingMap uses 1-based line/column
        var fileName = ExtractFilePath(uri);
        var (declaration, usages) = doc.Bindings!.FindAllReferences(fileName, line + 1, character + 1);

        if (declaration == null)
        {
            return highlights;
        }

        // Add declaration highlight (Write kind) if it's in the same file
        if (IsSameFile(declaration.File, fileName))
        {
            highlights.Add(new DocumentHighlight
            {
                Kind = DocumentHighlightKind.Write,
                Range = new LspRange(
                    declaration.Line - 1,
                    declaration.Column - 1,
                    declaration.Line - 1,
                    declaration.Column - 1 + Math.Max(1, declaration.Name.Length))
            });
        }

        // Add usage highlights (Read kind) filtered to same file
        foreach (var usage in usages)
        {
            if (!IsSameFile(usage.File, fileName))
            {
                continue;
            }

            highlights.Add(new DocumentHighlight
            {
                Kind = DocumentHighlightKind.Read,
                Range = new LspRange(
                    usage.Line - 1,
                    usage.Column - 1,
                    usage.Line - 1,
                    usage.Column - 1 + Math.Max(1, usage.Length))
            });
        }

        return highlights;
    }

    private static string? ExtractFilePath(string uri)
    {
        try
        {
            return new Uri(uri).LocalPath;
        }
        catch
        {
            // If URI parsing fails, return the raw URI stripped of the file:// prefix
            if (uri.StartsWith("file:///"))
                return uri.Substring("file:///".Length);
            return uri;
        }
    }

    private static bool IsSameFile(string? file1, string? file2)
    {
        if (file1 == null || file2 == null)
            return file1 == file2;

        return string.Equals(file1, file2, StringComparison.OrdinalIgnoreCase);
    }

    protected override DocumentHighlightRegistrationOptions CreateRegistrationOptions(
        DocumentHighlightCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentHighlightRegistrationOptions();
    }
}
