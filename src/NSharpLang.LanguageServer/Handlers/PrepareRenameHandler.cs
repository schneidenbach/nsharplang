using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.JsonRpc.Server;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/prepareRename requests.
///
/// WHICH WORDS MAY NOT BE RENAMED and WHAT EACH REFUSAL SAYS are N#-owned by
/// <c>EditorRenameGuardFacts</c>: the language's own words, the primitive type names, and the four
/// sentences this handler and the rename handler beside it share. Where the word starts on its
/// line is <c>EditorHoverFacts.WordRangeStartColumn</c>, the same answer hover uses. What is left
/// here is the protocol: OmniSharp's PlaceholderRange and its request-failed error.
/// </summary>
public class PrepareRenameHandler : PrepareRenameHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<PrepareRenameHandler> _logger;

    public PrepareRenameHandler(DocumentManager documentManager, ILogger<PrepareRenameHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<RangeOrPlaceholderRange?> Handle(PrepareRenameParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        if (EditorUtilities.IsPositionInsideStringLiteral(doc.Text, request.Position.Line, request.Position.Character))
        {
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        var word = EditorUtilities.GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
        if (string.IsNullOrWhiteSpace(word))
        {
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        // Reject keywords
        if (EditorRenameGuardFacts.IsKeyword(word))
        {
            _logger.LogDebug("Cannot rename keyword: {Word}", word);
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        // Reject primitive type names
        if (EditorRenameGuardFacts.IsPrimitiveTypeName(word))
        {
            _logger.LogDebug("Cannot rename primitive type: {Word}", word);
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        var hasSynchronizedProjectSnapshot = _documentManager.HasSynchronizedProjectSnapshot(uri);
        var hasStrictProjectRenameTarget = false;
        if (hasSynchronizedProjectSnapshot)
        {
            var projectReferences = _documentManager.FindStrictProjectReferences(uri, request.Position.Line, request.Position.Character);
            if (projectReferences == null)
            {
                throw RenameRefused(EditorRenameGuardFacts.RenameUnresolvedMessage(word));
            }

            hasStrictProjectRenameTarget = true;
        }
        else if (_documentManager.HasSemanticProjectContext(uri))
        {
            throw RenameRefused(EditorRenameGuardFacts.RenameDegradedMessage(word));
        }

        // Verify the symbol exists in our analysis
        var isKnownSymbol = hasStrictProjectRenameTarget;
        if (doc.SymbolLocations?.ContainsKey(word) == true)
            isKnownSymbol = true;

        if (!isKnownSymbol)
        {
            _logger.LogDebug("Cannot rename unknown symbol: {Word}", word);
            return Task.FromResult<RangeOrPlaceholderRange?>(null);
        }

        if (!hasSynchronizedProjectSnapshot)
        {
                throw RenameRefused(EditorRenameGuardFacts.RenameTextOnlyMessage(word));
        }

        // Return the range of the word and a placeholder
        var range = GetWordRange(doc.Text, request.Position.Line, request.Position.Character, word);
        return Task.FromResult<RangeOrPlaceholderRange?>(new RangeOrPlaceholderRange(
            new PlaceholderRange { Range = range, Placeholder = word }));
    }

    protected override RenameRegistrationOptions CreateRegistrationOptions(
        RenameCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new RenameRegistrationOptions
        {
            PrepareProvider = true
        };
    }

    private static LspRange GetWordRange(string text, int line, int character, string word)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return new LspRange(line, character, line, character);

        var startChar = EditorHoverFacts.WordRangeStartColumn(lines[line], character, word);
        return new LspRange(line, startChar, line, startChar + word.Length);
    }

    private static RequestFailedException RenameRefused(string message)
    {
        return new RequestFailedException(
            ErrorCodes.RequestFailed,
            message,
            RequestFailedException.UnknownRequestId,
            inner: null!);
    }
}
