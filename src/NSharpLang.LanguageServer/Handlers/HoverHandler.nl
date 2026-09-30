namespace NSharpLang.LanguageServer.Handlers

import System
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles hover information (shows type info when hovering over identifiers).
//
// Every decision about WHAT a hover says is N#-owned: the project answer comes from
// `CodeIntelligenceQueries.HoverInfo` through `DocumentManager.FindProjectHover` — the same owner
// `nlc query hover` asks — and every line of markdown comes from `EditorHoverFacts`. What is left
// here is the protocol: OmniSharp's `Hover`, `MarkupContent` and `Range`, which N# cannot name.
class HoverHandler: HoverHandlerBase {
    readonly documentManager: DocumentManager
    readonly typeResolver: TypeResolver
    readonly logger: ILogger<HoverHandler>

    constructor(documentManager: DocumentManager, typeResolver: TypeResolver, logger: ILogger<HoverHandler>) {
        this.documentManager = documentManager
        this.typeResolver = typeResolver
        this.logger = logger
    }

    override func Handle(request: HoverParams, cancellationToken: CancellationToken): Task<Hover?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<Hover?>(null)
        }

        line := request.Position.Line
        character := request.Position.Character

        logger.LogDebug("Hover request at {Line}:{Character}", line, character)

        word := EditorUtilities.GetWordAtPosition(doc.Text, line, character)

        // A keyword and a primitive answer for themselves and cannot be wrong, so they go first.
        keywordMarkdown := EditorHoverFacts.KeywordOrPrimitiveMarkdown(word)
        if keywordMarkdown != null {
            return Task.FromResult<Hover?>(createHover(keywordMarkdown, doc.Text, line, character, word))
        }

        // The project answer: the same signature, documentation, declaring type and file that
        // `nlc query hover` prints at this position.
        projectHover := documentManager.FindProjectHover(uri, line, character)
        if projectHover != null {
            return Task.FromResult<Hover?>(createHover(EditorHoverFacts.ProjectHoverMarkdown(projectHover), doc.Text, line, character, word))
        }

        // Loose buffers have no project, so the open document's own model answers for them.
        expression: Expression? = null
        unit := doc.CompilationUnit
        if unit != null && doc.SemanticModel != null {
            expression = AstNodeFinderCore.FindExpressionAtPosition(unit, line, character) as Expression
            identifier := expression as IdentifierExpression
            if identifier != null {
                identifierMarkdown := resolveIdentifier(identifier.Name, doc)
                if identifierMarkdown != null {
                    return Task.FromResult<Hover?>(createHover(identifierMarkdown, doc.Text, line, character, word))
                }
            }
        }

        isIdentifierOrAbsent := expression == null || (expression as IdentifierExpression) != null
        if !string.IsNullOrWhiteSpace(word) && doc.SemanticModel != null && isIdentifierOrAbsent {
            wordMarkdown := resolveIdentifier(word, doc)
            if wordMarkdown != null {
                return Task.FromResult<Hover?>(createHover(wordMarkdown, doc.Text, line, character, word))
            }
        }

        symbols := doc.Symbols
        if !string.IsNullOrWhiteSpace(word) && symbols != null {
            symbolTypeInfo: TypeInfo? = null
            if symbols.TryGetValue(word, out symbolTypeInfo) {
                return Task.FromResult<Hover?>(createHover(EditorHoverFacts.TypeDeclarationMarkdown(word, symbolTypeInfo), doc.Text, line, character, word))
            }
        }

        return Task.FromResult<Hover?>(null)
    }

    func resolveIdentifier(name: string, doc: DocumentState): string? {
        typeInfo := doc.SemanticModel?.LookupIdentifier(name)
        if typeInfo == null {
            return null
        }

        typeName := typeInfo.ToString() ?? ""
        systemType := typeResolver.ResolveType(typeName)
        return EditorHoverFacts.VariableMarkdown(name, typeName, systemType?.Namespace, systemType?.Assembly?.GetName().Name)
    }

    func createHover(markdown: string, text: string, line: int, character: int, word: string): Hover? {
        content := new MarkupContent {
            Kind: MarkupKind.Markdown,
            Value: markdown
        }

        range: OmniSharp.Extensions.LanguageServer.Protocol.Models.Range? = null
        if !string.IsNullOrWhiteSpace(word) {
            range = getWordRange(text, line, character, word)
        }

        return new Hover {
            Contents: new MarkedStringsOrMarkupContent(content),
            Range: range
        }
    }

    protected override func CreateRegistrationOptions(
        capability: HoverCapability,
        clientCapabilities: ClientCapabilities
    ): HoverRegistrationOptions {
        // DocumentSelector will be set automatically
        return new HoverRegistrationOptions()
    }

    func getWordRange(text: string, line: int, character: int, word: string): OmniSharp.Extensions.LanguageServer.Protocol.Models.Range {
        lines := text.Split('\n')
        if line >= lines.Length {
            return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(line, character, line, character)
        }

        startChar := EditorHoverFacts.WordRangeStartColumn(lines[line], character, word)
        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(line, startChar, line, startChar + word.Length)
    }
}
