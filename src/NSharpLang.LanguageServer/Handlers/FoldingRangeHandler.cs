using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/foldingRange requests for AST-aware code folding.
///
/// WHICH regions fold, in WHICH order, and how far each one reaches is N#-owned by
/// <c>EditorFoldingFacts</c>: the import group, every declaration with its members and block
/// statements nested beneath it, and the lexer's multi-line comments. What is left here is the
/// protocol — OmniSharp's FoldingRange and its kind vocabulary, which N# cannot name.
/// </summary>
public class FoldingRangeHandler : FoldingRangeHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<FoldingRangeHandler> _logger;

    public FoldingRangeHandler(DocumentManager documentManager, ILogger<FoldingRangeHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<FoldingRange>?> Handle(FoldingRangeRequestParam request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Container<FoldingRange>?>(null);
        }

        var ranges = new List<FoldingRange>();
        foreach (var row in CodeIntel.EditorFoldingFacts.FoldingRows(doc.CompilationUnit, doc.Text.Split('\n'), doc.Tokens))
        {
            ranges.Add(new FoldingRange
            {
                StartLine = row.StartLine,
                StartCharacter = row.StartCharacter,
                EndLine = row.EndLine,
                EndCharacter = row.EndCharacter,
                Kind = ToFoldingRangeKind(row.Kind)
            });
        }

        _logger.LogDebug("Returning {Count} folding ranges for {Uri}", ranges.Count, uri);
        return Task.FromResult<Container<FoldingRange>?>(new Container<FoldingRange>(ranges));
    }

    protected override FoldingRangeRegistrationOptions CreateRegistrationOptions(
        FoldingRangeCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new FoldingRangeRegistrationOptions();
    }

    private static FoldingRangeKind? ToFoldingRangeKind(string kind)
    {
        if (kind == CodeIntel.EditorFoldingFacts.ImportsKind)
        {
            return FoldingRangeKind.Imports;
        }

        if (kind == CodeIntel.EditorFoldingFacts.CommentKind)
        {
            return FoldingRangeKind.Comment;
        }

        return null;
    }
}
