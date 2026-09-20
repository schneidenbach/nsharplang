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
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;
using LspLocation = OmniSharp.Extensions.LanguageServer.Protocol.Models.Location;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles go-to-implementation requests (Ctrl+F12 in VS Code).
/// Finds all types that implement an interface or extend a base/abstract class.
///
/// WHETHER the caret is on something that has implementations, WHICH declarations count as one,
/// and the semantic check that keeps a same-spelled name in an unrelated file out, are all
/// N#-owned by <c>EditorImplementationFacts</c>. What is left here is the protocol — the word
/// under the caret, the walk over the open buffers with its cancellation check, and OmniSharp's
/// Location.
/// </summary>
public class GoToImplementationHandler : ImplementationHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<GoToImplementationHandler> _logger;

    public GoToImplementationHandler(DocumentManager documentManager, ILogger<GoToImplementationHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<LocationOrLocationLinks?> Handle(ImplementationParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }

        try
        {
            var word = EditorUtilities.GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            _logger.LogDebug("Go to implementation for: {Word}", word);

            var targetKind = CodeIntel.EditorImplementationFacts.TargetKind(doc.Symbols, word);
            if (targetKind == CodeIntel.EditorImplementationTarget.None)
            {
                _logger.LogDebug("Symbol '{Word}' is not an interface or class — skipping implementation search", word);
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            var rows = new List<CodeIntel.EditorImplementorRow>();
            foreach (var candidate in _documentManager.GetAllDocuments())
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    break;
                }

                CodeIntel.EditorImplementationFacts.AppendImplementorRows(
                    candidate.CompilationUnit, candidate.Symbols, candidate.Uri, word, targetKind, rows);
            }

            if (rows.Count == 0)
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            var locations = rows.Select(row => new LocationOrLocationLink(new LspLocation
            {
                Uri = DocumentUri.From(row.Uri),
                Range = new LspRange(row.Line, row.StartCharacter, row.Line, row.EndCharacter)
            }));

            return Task.FromResult<LocationOrLocationLinks?>(new LocationOrLocationLinks(locations));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling go to implementation");
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }
    }

    protected override ImplementationRegistrationOptions CreateRegistrationOptions(
        ImplementationCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new ImplementationRegistrationOptions();
    }
}
