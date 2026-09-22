namespace NSharpLang.LanguageServer.Handlers

import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles textDocument/onTypeFormatting requests to auto-indent after typing '}' or pressing Enter.
//
// WHICH line moves and WHAT it should read is N#-owned by `EditorOnTypeFormattingFacts`: the
// backwards brace match, the visual-column measurement that lets tabs and spaces compare equal, the
// tab/space split when the indent is written back, and the rule that a line already correctly
// indented produces no edit at all. What is left here is the protocol — OmniSharp's TextEdit and
// the trigger-character registration.
class OnTypeFormattingHandler: DocumentOnTypeFormattingHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<OnTypeFormattingHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<OnTypeFormattingHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: DocumentOnTypeFormattingParams, cancellationToken: CancellationToken): Task<TextEditContainer?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<TextEditContainer?>(null)
        }

        sourceLines := doc.Text.Split('\n')
        trigger := request.Character
        line := request.Position.Line
        character := request.Position.Character
        tabSize := request.Options.TabSize
        insertSpaces := request.Options.InsertSpaces

        rows := EditorOnTypeFormattingFacts.FormattingRows(sourceLines, trigger, line, tabSize, insertSpaces)

        if rows.Count == 0 {
            return Task.FromResult<TextEditContainer?>(null)
        }

        edits := new List<TextEdit>()
        for row in rows {
            edits.Add(new TextEdit {
                Range: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    row.StartLine,
                    row.StartCharacter,
                    row.EndLine,
                    row.EndCharacter
                ),
                NewText: row.NewText
            })
        }

        logger.LogDebug(
            "Returning {Count} on-type formatting edits for '{Trigger}' at {Line}:{Char} in {Uri}",
            edits.Count,
            trigger,
            line,
            character,
            uri
        )

        return Task.FromResult<TextEditContainer?>(new TextEditContainer(edits))
    }

    protected override func CreateRegistrationOptions(
        capability: DocumentOnTypeFormattingCapability,
        clientCapabilities: ClientCapabilities
    ): DocumentOnTypeFormattingRegistrationOptions {
        return new DocumentOnTypeFormattingRegistrationOptions {
            FirstTriggerCharacter: "}",
            MoreTriggerCharacter: new Container<string>("\n")
        }
    }
}
