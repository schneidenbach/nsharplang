namespace NSharpLang.LanguageServer.Handlers

import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles textDocument/documentSymbol requests to provide the Outline panel in VS Code.
// Maps N# declarations (types, functions, fields, etc.) to LSP DocumentSymbol hierarchy.
//
// WHICH declarations appear, in WHAT order, nested under what, with what detail text, and the two
// spans — including the clamps that keep the full range containing the selection range — are
// N#-owned by `EditorDocumentSymbolFacts`. What is left here is the protocol: OmniSharp's
// DocumentSymbol and the wire numbers of its symbol kinds, which N# cannot name.
//
// The owner's names are written in full because `SymbolKind` is declared on BOTH sides — the
// editor's vocabulary and the protocol's — and N# has no import alias.
class DocumentSymbolHandler: DocumentSymbolHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<DocumentSymbolHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<DocumentSymbolHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(
        request: DocumentSymbolParams,
        cancellationToken: CancellationToken
    ): Task<SymbolInformationOrDocumentSymbolContainer?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null || doc.CompilationUnit == null {
            return Task.FromResult<SymbolInformationOrDocumentSymbolContainer?>(null)
        }

        logger.LogDebug("Document symbol request for {Uri}", uri)

        sourceLines := doc.Text?.Split('\n')
        rows := NSharpLang.Compiler.CodeIntelligence.EditorDocumentSymbolFacts.SymbolRows(doc.CompilationUnit, sourceLines)

        entries := new List<SymbolInformationOrDocumentSymbol>()
        for row in rows {
            entries.Add(new SymbolInformationOrDocumentSymbol(toDocumentSymbol(row)))
        }

        return Task.FromResult<SymbolInformationOrDocumentSymbolContainer?>(
            new SymbolInformationOrDocumentSymbolContainer(entries)
        )
    }

    protected override func CreateRegistrationOptions(
        capability: DocumentSymbolCapability,
        clientCapabilities: ClientCapabilities
    ): DocumentSymbolRegistrationOptions {
        return new DocumentSymbolRegistrationOptions()
    }

    static func toDocumentSymbol(row: NSharpLang.Compiler.CodeIntelligence.EditorDocumentSymbolRow): DocumentSymbol {
        children := new List<DocumentSymbol>()
        for child in row.Children {
            children.Add(toDocumentSymbol(child))
        }

        childContainer: Container<DocumentSymbol>? = null
        if children.Count > 0 {
            childContainer = new Container<DocumentSymbol>(children)
        }

        return new DocumentSymbol {
            Name: row.Name,
            Kind: toSymbolKind(row.Kind),
            Range: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(row.StartLine, 0, row.EndLine, row.EndCharacter),
            SelectionRange: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(row.StartLine, 0, row.StartLine, row.SelectionEndCharacter),
            Detail: row.Detail,
            Children: childContainer
        }
    }

    static func toSymbolKind(kind: NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind): OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind {
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Function {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Function
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Method {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Method
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Class {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Class
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Struct {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Struct
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Interface {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Interface
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Enum {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Enum
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.EnumMember {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.EnumMember
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Field {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Field
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Property {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Property
        }

        return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Constructor
    }
}
