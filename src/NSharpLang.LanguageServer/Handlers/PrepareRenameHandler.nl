namespace NSharpLang.LanguageServer.Handlers

import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.JsonRpc.Server
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles textDocument/prepareRename requests.
//
// WHICH WORDS MAY NOT BE RENAMED and WHAT EACH REFUSAL SAYS are N#-owned by
// `EditorRenameGuardFacts`: the language's own words, the primitive type names, and the four
// sentences this handler and the rename handler beside it share. Where the word starts on its line
// is `EditorHoverFacts.WordRangeStartColumn`, the same answer hover uses. What is left here is the
// protocol: OmniSharp's PlaceholderRange and its request-failed error.
class PrepareRenameHandler: PrepareRenameHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<PrepareRenameHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<PrepareRenameHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: PrepareRenameParams, cancellationToken: CancellationToken): Task<RangeOrPlaceholderRange?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<RangeOrPlaceholderRange?>(null)
        }

        line := request.Position.Line
        character := request.Position.Character

        if EditorUtilities.IsPositionInsideStringLiteral(doc.Text, line, character) {
            return Task.FromResult<RangeOrPlaceholderRange?>(null)
        }

        word := EditorUtilities.GetWordAtPosition(doc.Text, line, character)
        if string.IsNullOrWhiteSpace(word) {
            return Task.FromResult<RangeOrPlaceholderRange?>(null)
        }

        // Reject keywords
        if EditorRenameGuardFacts.IsKeyword(word) {
            logger.LogDebug("Cannot rename keyword: {Word}", word)
            return Task.FromResult<RangeOrPlaceholderRange?>(null)
        }

        // Reject primitive type names
        if EditorRenameGuardFacts.IsPrimitiveTypeName(word) {
            logger.LogDebug("Cannot rename primitive type: {Word}", word)
            return Task.FromResult<RangeOrPlaceholderRange?>(null)
        }

        hasSynchronizedProjectSnapshot := documentManager.HasSynchronizedProjectSnapshot(uri)
        hasStrictProjectRenameTarget := false
        if hasSynchronizedProjectSnapshot {
            projectReferences := documentManager.FindStrictProjectReferences(uri, line, character)
            if projectReferences == null {
                throw renameRefused(EditorRenameGuardFacts.RenameUnresolvedMessage(word))
            }

            hasStrictProjectRenameTarget = true
        } else if documentManager.HasSemanticProjectContext(uri) {
            throw renameRefused(EditorRenameGuardFacts.RenameDegradedMessage(word))
        }

        // Verify the symbol exists in our analysis
        isKnownSymbol := hasStrictProjectRenameTarget
        if doc.SymbolLocations?.ContainsKey(word) == true {
            isKnownSymbol = true
        }

        if !isKnownSymbol {
            logger.LogDebug("Cannot rename unknown symbol: {Word}", word)
            return Task.FromResult<RangeOrPlaceholderRange?>(null)
        }

        if !hasSynchronizedProjectSnapshot {
            throw renameRefused(EditorRenameGuardFacts.RenameTextOnlyMessage(word))
        }

        // Return the range of the word and a placeholder
        range := getWordRange(doc.Text, line, character, word)
        placeholder := new PlaceholderRange { Range: range, Placeholder: word }
        return Task.FromResult<RangeOrPlaceholderRange?>(new RangeOrPlaceholderRange(placeholder))
    }

    protected override func CreateRegistrationOptions(
        capability: RenameCapability,
        clientCapabilities: ClientCapabilities
    ): RenameRegistrationOptions {
        return new RenameRegistrationOptions {
            PrepareProvider: true
        }
    }

    static func getWordRange(text: string, line: int, character: int, word: string): OmniSharp.Extensions.LanguageServer.Protocol.Models.Range {
        lines := text.Split('\n')
        if line >= lines.Length {
            return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(line, character, line, character)
        }

        startChar := EditorHoverFacts.WordRangeStartColumn(lines[line], character, word)
        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(line, startChar, line, startChar + word.Length)
    }

    static func renameRefused(message: string): RequestFailedException {
        return new RequestFailedException(
            ErrorCodes.RequestFailed,
            message,
            RequestFailedException.UnknownRequestId,
            null
        )
    }
}
