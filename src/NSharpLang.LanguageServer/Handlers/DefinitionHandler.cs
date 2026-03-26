using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using NSharpLang.LanguageServer.Models;
using ServerSymbolKind = NSharpLang.LanguageServer.Models.SymbolKind;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles go-to-definition requests (F12 in VS Code)
/// </summary>
public class DefinitionHandler : DefinitionHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DefinitionHandler> _logger;

    public DefinitionHandler(DocumentManager documentManager, ILogger<DefinitionHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<LocationOrLocationLinks?> Handle(DefinitionParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }

        try
        {
            // Get the word at the cursor position
            var word = GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            _logger.LogDebug("Go to definition for: {Word}", word);

            var projectDefinition = _documentManager.FindProjectDefinition(uri, request.Position.Line, request.Position.Character);
            if (projectDefinition != null)
            {
                var projectRoot = _documentManager.GetProjectRootForUri(uri);
                var filePath = _documentManager.ResolveProjectFilePath(projectRoot, projectDefinition.File);
                var projectLocation = new Location
                {
                    Uri = DocumentUri.From(new Uri(filePath).AbsoluteUri),
                    Range = new LspRange(
                        projectDefinition.Line - 1,
                        projectDefinition.Column - 1,
                        projectDefinition.Line - 1,
                        projectDefinition.Column - 1 + Math.Max(1, projectDefinition.Length))
                };

                return Task.FromResult<LocationOrLocationLinks?>(new LocationOrLocationLinks(projectLocation));
            }

            var candidates = _documentManager.FindSymbolLocations(word);
            if (candidates.Count == 0)
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            var best = PickBestLocation(word, candidates, doc, request.Position);
            if (best == null)
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            var location = new Location
            {
                Uri = DocumentUri.From(best.Uri),
                Range = new LspRange(best.Line, best.Column, best.Line, best.Column + Math.Max(1, best.Length))
            };

            return Task.FromResult<LocationOrLocationLinks?>(new LocationOrLocationLinks(location));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling go to definition");
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }
    }

    protected override DefinitionRegistrationOptions CreateRegistrationOptions(
        DefinitionCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DefinitionRegistrationOptions();
    }

    private string GetWordAtPosition(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return string.Empty;

        var lineText = lines[line];
        if (lineText.Length == 0) return string.Empty;
        if (character < 0 || character >= lineText.Length) return string.Empty;
        if (!IsIdentifierChar(lineText[character])) return string.Empty;

        // Find word boundaries
        int start = character;
        while (start > 0 && IsIdentifierChar(lineText[start - 1]))
        {
            start--;
        }

        int end = character;
        while (end < lineText.Length && IsIdentifierChar(lineText[end]))
        {
            end++;
        }

        return lineText.Substring(start, end - start);
    }

    private bool IsIdentifierChar(char c)
    {
        return char.IsLetterOrDigit(c) || c == '_';
    }

    private static SymbolLocation? PickBestLocation(
        string name,
        IReadOnlyList<SymbolLocation> candidates,
        DocumentState currentDoc,
        Position position)
    {
        static bool IsTypeKind(ServerSymbolKind kind) =>
            kind is ServerSymbolKind.Class
                or ServerSymbolKind.Struct
                or ServerSymbolKind.Record
                or ServerSymbolKind.Interface
                or ServerSymbolKind.Enum
                or ServerSymbolKind.Union;

        static int KindPriority(ServerSymbolKind kind) => kind switch
        {
            ServerSymbolKind.LocalVariable => 0,
            ServerSymbolKind.Parameter => 1,
            ServerSymbolKind.Field => 2,
            ServerSymbolKind.Property => 3,
            ServerSymbolKind.Method => 4,
            ServerSymbolKind.Function => 5,
            ServerSymbolKind.Class => 6,
            ServerSymbolKind.Struct => 6,
            ServerSymbolKind.Record => 6,
            ServerSymbolKind.Interface => 6,
            ServerSymbolKind.Enum => 6,
            ServerSymbolKind.Union => 6,
            _ => 10
        };

        var sameFile = candidates.Where(c => string.Equals(c.Uri, currentDoc.Uri, StringComparison.Ordinal)).ToList();

        // If semantic analysis recognizes this as a local variable, prefer the closest declaration before the cursor.
        if (currentDoc.SemanticModel?.Variables.ContainsKey(name) == true)
        {
            var localBest = sameFile
                .Where(c => c.Kind == ServerSymbolKind.LocalVariable)
                .Where(c => c.Line < position.Line || (c.Line == position.Line && c.Column <= position.Character))
                .OrderByDescending(c => c.Line)
                .ThenByDescending(c => c.Column)
                .FirstOrDefault();

            if (localBest != null) return localBest;
        }

        // If it looks like a type name, prefer type declarations.
        if (name.Length > 0 && char.IsUpper(name[0]))
        {
            var typeBest = (sameFile.Count > 0 ? sameFile : candidates)
                .Where(c => IsTypeKind(c.Kind))
                .OrderBy(c => Math.Abs(c.Line - position.Line))
                .ThenBy(c => Math.Abs(c.Column - position.Character))
                .FirstOrDefault();

            if (typeBest != null) return typeBest;
        }

        // Otherwise, prefer same-file results, then closest by (kind priority, distance).
        var pool = sameFile.Count > 0 ? sameFile : candidates;
        return pool
            .OrderBy(c => KindPriority(c.Kind))
            .ThenBy(c => Math.Abs(c.Line - position.Line))
            .ThenBy(c => Math.Abs(c.Column - position.Character))
            .FirstOrDefault();
    }
}
