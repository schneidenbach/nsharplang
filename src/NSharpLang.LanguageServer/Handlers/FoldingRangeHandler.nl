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

// Handles textDocument/foldingRange requests for AST-aware code folding.
//
// WHICH regions fold, in WHICH order, and how far each one reaches is N#-owned by
// `EditorFoldingFacts`: the import group, every declaration with its members and block statements
// nested beneath it, and the lexer's multi-line comments. What is left here is the protocol —
// OmniSharp's FoldingRange and its kind vocabulary, which N# cannot name.
class FoldingRangeHandler: FoldingRangeHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<FoldingRangeHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<FoldingRangeHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: FoldingRangeRequestParam, cancellationToken: CancellationToken): Task<Container<FoldingRange>?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<Container<FoldingRange>?>(null)
        }

        sourceLines := doc.Text.Split('\n')
        ranges := new List<FoldingRange>()
        for row in EditorFoldingFacts.FoldingRows(doc.CompilationUnit, sourceLines, doc.Tokens) {
            ranges.Add(new FoldingRange {
                StartLine: row.StartLine,
                StartCharacter: row.StartCharacter,
                EndLine: row.EndLine,
                EndCharacter: row.EndCharacter,
                Kind: toFoldingRangeKind(row.Kind)
            })
        }

        logger.LogDebug("Returning {Count} folding ranges for {Uri}", ranges.Count, uri)
        return Task.FromResult<Container<FoldingRange>?>(new Container<FoldingRange>(ranges))
    }

    protected override func CreateRegistrationOptions(
        capability: FoldingRangeCapability,
        clientCapabilities: ClientCapabilities
    ): FoldingRangeRegistrationOptions {
        return new FoldingRangeRegistrationOptions()
    }

    static func toFoldingRangeKind(kind: string): FoldingRangeKind? {
        if kind == EditorFoldingFacts.ImportsKind {
            return FoldingRangeKind.Imports
        }

        if kind == EditorFoldingFacts.CommentKind {
            return FoldingRangeKind.Comment
        }

        return null
    }
}
