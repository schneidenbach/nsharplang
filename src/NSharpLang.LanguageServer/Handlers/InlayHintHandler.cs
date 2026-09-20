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
/// Handles textDocument/inlayHint requests.
/// Shows inferred types as ghost text after := assignments where the type is not explicit.
///
/// WHICH bindings get a hint, WHERE the ghost text sits and WHAT it says are N#-owned by
/// <c>EditorInlayHintFacts</c>: the body walk, the "annotated bindings are left alone" rule, the
/// keyword-width arithmetic that places a loop variable's hint, and the display text of a bound
/// type — including the CLR primitive spellings. What is left here is the protocol: OmniSharp's
/// InlayHint and its kind and padding, which are the same for every hint this feature produces.
/// </summary>
public class InlayHintHandler : InlayHintsHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<InlayHintHandler> _logger;

    public InlayHintHandler(DocumentManager documentManager, ILogger<InlayHintHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<InlayHintContainer?> Handle(InlayHintParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.CompilationUnit == null || doc.SemanticModel == null)
        {
            return Task.FromResult<InlayHintContainer?>(new InlayHintContainer());
        }

        var range = request.Range;

        _logger.LogDebug("InlayHint request for {Uri} range {StartLine}:{StartChar}-{EndLine}:{EndChar}",
            uri, range.Start.Line, range.Start.Character, range.End.Line, range.End.Character);

        var hints = new List<InlayHint>();
        foreach (var row in CodeIntel.EditorInlayHintFacts.HintRows(
            doc.CompilationUnit, doc.SemanticModel, range.Start.Line, range.End.Line))
        {
            hints.Add(new InlayHint
            {
                Position = new Position(row.Line, row.Character),
                Label = new StringOrInlayHintLabelParts(row.Label),
                Kind = InlayHintKind.Type,
                PaddingLeft = false,
                PaddingRight = true
            });
        }

        return Task.FromResult<InlayHintContainer?>(new InlayHintContainer(hints));
    }

    public override Task<InlayHint> Handle(InlayHint request, CancellationToken cancellationToken)
    {
        // Resolve is not supported — return the hint as-is
        return Task.FromResult(request);
    }

    protected override InlayHintRegistrationOptions CreateRegistrationOptions(
        InlayHintClientCapabilities capability,
        ClientCapabilities clientCapabilities)
    {
        return new InlayHintRegistrationOptions
        {
            ResolveProvider = false
        };
    }
}
