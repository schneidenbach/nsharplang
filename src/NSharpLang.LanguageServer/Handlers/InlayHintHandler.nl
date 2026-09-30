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

// Handles textDocument/inlayHint requests.
// Shows inferred types as ghost text after := assignments where the type is not explicit.
//
// WHICH bindings get a hint, WHERE the ghost text sits and WHAT it says are N#-owned by
// `EditorInlayHintFacts`: the body walk, the "annotated bindings are left alone" rule, the
// keyword-width arithmetic that places a loop variable's hint, and the display text of a bound type
// — including the CLR primitive spellings. What is left here is the protocol: OmniSharp's InlayHint
// and its kind and padding, which are the same for every hint this feature produces.
class InlayHintHandler: InlayHintsHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<InlayHintHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<InlayHintHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: InlayHintParams, cancellationToken: CancellationToken): Task<InlayHintContainer?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null || doc.CompilationUnit == null || doc.SemanticModel == null {
            return Task.FromResult<InlayHintContainer?>(new InlayHintContainer())
        }

        range := request.Range
        startLine := range.Start.Line
        startCharacter := range.Start.Character
        endLine := range.End.Line
        endCharacter := range.End.Character

        logger.LogDebug(
            "InlayHint request for {Uri} range {StartLine}:{StartChar}-{EndLine}:{EndChar}",
            uri,
            startLine,
            startCharacter,
            endLine,
            endCharacter
        )

        hints := new List<InlayHint>()
        for row in EditorInlayHintFacts.HintRows(doc.CompilationUnit, doc.SemanticModel, startLine, endLine) {
            hints.Add(new InlayHint {
                Position: new Position(row.Line, row.Character),
                Label: new StringOrInlayHintLabelParts(row.Label),
                Kind: InlayHintKind.Type,
                PaddingLeft: false,
                PaddingRight: true
            })
        }

        return Task.FromResult<InlayHintContainer?>(new InlayHintContainer(hints))
    }

    override func Handle(request: InlayHint, cancellationToken: CancellationToken): Task<InlayHint> {
        // Resolve is not supported — return the hint as-is
        return Task.FromResult(request)
    }

    protected override func CreateRegistrationOptions(
        capability: InlayHintClientCapabilities,
        clientCapabilities: ClientCapabilities
    ): InlayHintRegistrationOptions {
        return new InlayHintRegistrationOptions {
            ResolveProvider: false
        }
    }
}
