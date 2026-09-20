using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/selectionRange requests for smart selection expansion.
/// For each requested position, builds a parent chain of AST nodes containing
/// that position, from innermost to outermost, allowing the editor to expand
/// or shrink selection through syntactic boundaries.
///
/// WHICH frames contain the caret, how far each one reaches, and the order they come in are
/// N#-owned by <c>EditorSelectionRangeFacts</c> — including the whole-file frame that is always
/// the outermost one. What is left here is the protocol: threading the chain into OmniSharp's
/// nested SelectionRange, whose parent links N# cannot build.
/// </summary>
public class SelectionRangeHandler : SelectionRangeHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<SelectionRangeHandler> _logger;

    public SelectionRangeHandler(DocumentManager documentManager, ILogger<SelectionRangeHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<SelectionRange>?> Handle(
        SelectionRangeParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Container<SelectionRange>?>(null);
        }

        var sourceLines = doc.Text.Split('\n');
        var wholeFile = CodeIntel.EditorSelectionRangeFacts.WholeFileRow(sourceLines);
        var results = new List<SelectionRange>();

        foreach (var position in request.Positions)
        {
            var selectionRange = new SelectionRange { Range = ToRange(wholeFile) };

            foreach (var row in CodeIntel.EditorSelectionRangeFacts.ContainingRows(
                doc.CompilationUnit, position.Line, sourceLines))
            {
                selectionRange = new SelectionRange { Range = ToRange(row), Parent = selectionRange };
            }

            results.Add(selectionRange);
        }

        _logger.LogDebug("Returning {Count} selection ranges for {Uri}", results.Count, uri);
        return Task.FromResult<Container<SelectionRange>?>(new Container<SelectionRange>(results));
    }

    protected override SelectionRangeRegistrationOptions CreateRegistrationOptions(
        SelectionRangeCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new SelectionRangeRegistrationOptions();
    }

    private static LspRange ToRange(CodeIntel.EditorSelectionRangeRow row)
    {
        return new LspRange(row.StartLine, 0, row.EndLine, row.EndCharacter);
    }
}
