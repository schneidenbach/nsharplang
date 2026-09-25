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

// Handles textDocument/semanticTokens/full requests.
//
// WHICH tokens are painted and WHAT each one is are N#-owned by `EditorSemanticTokenFacts`: the
// order of the identifier rules, the re-lexing of an interpolated literal's holes, the walk that
// finds the Go-style error capture, the three reasons a classified token is still not emitted, and
// the five symbol tables the classification consults, which the owner reads off the same source the
// document was parsed from. What is left here is the protocol — the LEGEND, whose order is a
// promise this server made to the client at startup.
class SemanticTokensHandler: SemanticTokensHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<SemanticTokensHandler>

    // Token types in legend order — index matters!
    static readonly TokenTypes: string[] = [
        "namespace",
        // 0
        "type",
        // 1
        "class",
        // 2
        "struct",
        // 3
        "enum",
        // 4
        "interface",
        // 5
        "typeParameter",
        // 6
        "parameter",
        // 7
        "variable",
        // 8
        "property",
        // 9
        "function",
        // 10
        "method",
        // 11
        "keyword",
        // 12
        "comment",
        // 13
        "string",
        // 14
        "number",
        // 15
        "operator",
        // 16
        "enumMember"
        // 17
    ]

    // Token modifiers in legend order — index matters!
    static readonly TokenModifiers: string[] = [
        "declaration",
        // 0
        "definition",
        // 1
        "readonly",
        // 2
        "static",
        // 3
        "async",
        // 4
        "catchResult"
        // 5
    ]

    static readonly CatchResultModifierMask: int = 32

    constructor(documentManager: DocumentManager, logger: ILogger<SemanticTokensHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    protected override func CreateRegistrationOptions(
        capability: SemanticTokensCapability,
        clientCapabilities: ClientCapabilities
    ): SemanticTokensRegistrationOptions {
        tokenTypes := new List<SemanticTokenType>()
        index := 0
        while index < TokenTypes.Length {
            // COMPILER: lsflip-2. The element and the construction are both bound to locals.
            typeName := TokenTypes[index]
            tokenType := new SemanticTokenType(typeName)
            tokenTypes.Add(tokenType)
            index = index + 1
        }

        tokenModifiers := new List<SemanticTokenModifier>()
        modifierIndex := 0
        while modifierIndex < TokenModifiers.Length {
            modifierName := TokenModifiers[modifierIndex]
            tokenModifier := new SemanticTokenModifier(modifierName)
            tokenModifiers.Add(tokenModifier)
            modifierIndex = modifierIndex + 1
        }

        return new SemanticTokensRegistrationOptions {
            Full: new SemanticTokensCapabilityRequestFull { Delta: false },
            Legend: new SemanticTokensLegend {
                TokenTypes: new Container<SemanticTokenType>(tokenTypes),
                TokenModifiers: new Container<SemanticTokenModifier>(tokenModifiers)
            }
        }
    }

    protected override func GetSemanticTokensDocument(
        request: ITextDocumentIdentifierParams,
        cancellationToken: CancellationToken
    ): Task<SemanticTokensDocument> {
        options := CreateRegistrationOptions(new SemanticTokensCapability(), new ClientCapabilities())
        return Task.FromResult(new SemanticTokensDocument(options))
    }

    protected override func Tokenize(
        builder: SemanticTokensBuilder,
        identifier: ITextDocumentIdentifierParams,
        cancellationToken: CancellationToken
    ): Task {
        uri := identifier.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null || doc.Tokens == null {
            return Task.CompletedTask
        }

        logger.LogDebug("Semantic tokens request for {Uri} with {TokenCount} tokens", uri, doc.Tokens.Count)

        for row in EditorSemanticTokenFacts.SourceTokenRows(doc.Tokens, doc.CompilationUnit, doc.SemanticModel, doc.Text) {
            if cancellationToken.IsCancellationRequested {
                break
            }

            modifiers := 0
            if row.IsCatchResult {
                modifiers = CatchResultModifierMask
            }

            builder.Push(row.Line, row.Character, row.Length, legendIndex(row.Kind), modifiers)
        }

        return Task.CompletedTask
    }

    // The owner's kind word placed in this server's legend. The legend's order is the protocol
    // contract; the word is what the owner decided.
    static func legendIndex(kind: string): int {
        index := 0
        while index < TokenTypes.Length {
            if TokenTypes[index] == kind {
                return index
            }

            index = index + 1
        }

        return 1
        // "type"
    }
}
