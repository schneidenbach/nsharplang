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

// Handles textDocument/selectionRange requests for smart selection expansion.
// For each requested position, builds a parent chain of AST nodes containing that position, from
// innermost to outermost, allowing the editor to expand or shrink selection through syntactic
// boundaries.
//
// WHICH frames contain the caret, how far each one reaches, and the order they come in are N#-owned
// by `EditorSelectionRangeFacts` — including the whole-file frame that is always the outermost one.
// What is left here is the protocol: threading the chain into OmniSharp's nested SelectionRange,
// whose parent links N# cannot build.
class SelectionRangeHandler: SelectionRangeHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<SelectionRangeHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<SelectionRangeHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: SelectionRangeParams, cancellationToken: CancellationToken): Task<Container<SelectionRange>?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<Container<SelectionRange>?>(null)
        }

        sourceLines := doc.Text.Split('\n')
        wholeFile := EditorSelectionRangeFacts.WholeFileRow(sourceLines)
        results := new List<SelectionRange>()

        for position in request.Positions {
            selectionRange := new SelectionRange { Range: toRange(wholeFile) }

            for row in EditorSelectionRangeFacts.ContainingRows(doc.CompilationUnit, position.Line, sourceLines) {
                selectionRange = new SelectionRange { Range: toRange(row), Parent: selectionRange }
            }

            results.Add(selectionRange)
        }

        logger.LogDebug("Returning {Count} selection ranges for {Uri}", results.Count, uri)
        return Task.FromResult<Container<SelectionRange>?>(new Container<SelectionRange>(results))
    }

    protected override func CreateRegistrationOptions(
        capability: SelectionRangeCapability,
        clientCapabilities: ClientCapabilities
    ): SelectionRangeRegistrationOptions {
        return new SelectionRangeRegistrationOptions()
    }

    static func toRange(row: EditorSelectionRangeRow): OmniSharp.Extensions.LanguageServer.Protocol.Models.Range {
        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(row.StartLine, 0, row.EndLine, row.EndCharacter)
    }
}
