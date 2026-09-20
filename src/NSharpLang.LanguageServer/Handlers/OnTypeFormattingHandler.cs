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
/// Handles textDocument/onTypeFormatting requests to auto-indent after
/// typing '}' or pressing Enter.
///
/// WHICH line moves and WHAT it should read is N#-owned by
/// <c>EditorOnTypeFormattingFacts</c>: the backwards brace match, the visual-column measurement
/// that lets tabs and spaces compare equal, the tab/space split when the indent is written back,
/// and the rule that a line already correctly indented produces no edit at all. What is left here
/// is the protocol — OmniSharp's TextEdit and the trigger-character registration.
/// </summary>
public class OnTypeFormattingHandler : DocumentOnTypeFormattingHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<OnTypeFormattingHandler> _logger;

    public OnTypeFormattingHandler(DocumentManager documentManager, ILogger<OnTypeFormattingHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<TextEditContainer?> Handle(
        DocumentOnTypeFormattingParams request,
        CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<TextEditContainer?>(null);
        }

        var rows = CodeIntel.EditorOnTypeFormattingFacts.FormattingRows(
            doc.Text.Split('\n'),
            request.Character,
            request.Position.Line,
            request.Options.TabSize,
            request.Options.InsertSpaces);

        if (rows.Count == 0)
        {
            return Task.FromResult<TextEditContainer?>(null);
        }

        var edits = new List<TextEdit>();
        foreach (var row in rows)
        {
            edits.Add(new TextEdit
            {
                Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    row.StartLine, row.StartCharacter, row.EndLine, row.EndCharacter),
                NewText = row.NewText
            });
        }

        _logger.LogDebug("Returning {Count} on-type formatting edits for '{Trigger}' at {Line}:{Char} in {Uri}",
            edits.Count, request.Character, request.Position.Line, request.Position.Character, uri);

        return Task.FromResult<TextEditContainer?>(new TextEditContainer(edits));
    }

    protected override DocumentOnTypeFormattingRegistrationOptions CreateRegistrationOptions(
        DocumentOnTypeFormattingCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentOnTypeFormattingRegistrationOptions
        {
            FirstTriggerCharacter = "}",
            MoreTriggerCharacter = new Container<string>("\n")
        };
    }
}
