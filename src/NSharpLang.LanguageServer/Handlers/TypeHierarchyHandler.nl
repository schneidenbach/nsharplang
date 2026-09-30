namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// The protocol side of the type-hierarchy view. All three requests — preparing the node under the
// caret, walking up to the supertypes and walking down to the subtypes — are decided by
// `EditorTypeHierarchyFacts`, including the asymmetry between the two walks. What is left here is
// OmniSharp's TypeHierarchyItem and the wire numbers of its symbol kinds.
//
// The owner's names are written in full because `SymbolKind` is declared on BOTH sides — the
// editor's vocabulary and the protocol's — and N# has no import alias.
class TypeHierarchyProtocol {
    static func ToItem(row: NSharpLang.Compiler.CodeIntelligence.EditorTypeHierarchyRow): TypeHierarchyItem {
        range := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
            row.Line,
            row.StartCharacter,
            row.Line,
            row.EndCharacter
        )

        return new TypeHierarchyItem {
            Name: row.Name,
            Kind: ToSymbolKind(row.Kind),
            Uri: DocumentUri.From(row.Uri),
            Range: range,
            SelectionRange: range
        }
    }

    static func ToSymbolKind(kind: NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind): OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind {
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Interface {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Interface
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Struct {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Struct
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolKind.Enum {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Enum
        }

        return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Class
    }
}

// Handles textDocument/prepareTypeHierarchy requests.
// Resolves the type at the cursor position and returns a TypeHierarchyItem for it.
class TypeHierarchyPrepareHandler: TypeHierarchyPrepareHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<TypeHierarchyPrepareHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<TypeHierarchyPrepareHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: TypeHierarchyPrepareParams, cancellationToken: CancellationToken): Task<Container<TypeHierarchyItem>?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<Container<TypeHierarchyItem>?>(null)
        }

        line := request.Position.Line
        character := request.Position.Character

        try {
            word := EditorUtilities.GetWordAtPosition(doc.Text, line, character)
            if string.IsNullOrWhiteSpace(word) {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null)
            }

            logger.LogDebug("Type hierarchy prepare for: {Word}", word)

            row := NSharpLang.Compiler.CodeIntelligence.EditorTypeHierarchyFacts.PrepareRow(doc.Symbols, word, uri)
            if row == null {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null)
            }

            item := TypeHierarchyProtocol.ToItem(row)
            return Task.FromResult<Container<TypeHierarchyItem>?>(new Container<TypeHierarchyItem>(item))
        } catch failure: Exception {
            logger.LogError(failure, "Error handling type hierarchy prepare")
            return Task.FromResult<Container<TypeHierarchyItem>?>(null)
        }
    }

    protected override func CreateRegistrationOptions(
        capability: TypeHierarchyCapability,
        clientCapabilities: ClientCapabilities
    ): TypeHierarchyRegistrationOptions {
        return new TypeHierarchyRegistrationOptions()
    }
}

// Handles typeHierarchy/supertypes requests.
// Given a TypeHierarchyItem, finds its base class and implemented interfaces.
class TypeHierarchySupertypesHandler: TypeHierarchySupertypesHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<TypeHierarchySupertypesHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<TypeHierarchySupertypesHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: TypeHierarchySupertypesParams, cancellationToken: CancellationToken): Task<Container<TypeHierarchyItem>?> {
        targetName := request.Item.Name
        targetUri := request.Item.Uri.ToString()

        logger.LogDebug("Type hierarchy supertypes for: {Name}", targetName)

        try {
            doc := documentManager.GetDocument(targetUri)
            if doc == null || doc.CompilationUnit == null || doc.CompilationUnit.Declarations == null {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null)
            }

            results := new List<TypeHierarchyItem>()
            for name in NSharpLang.Compiler.CodeIntelligence.EditorTypeHierarchyFacts.SupertypeNames(doc.CompilationUnit, targetName) {
                if cancellationToken.IsCancellationRequested {
                    break
                }

                for candidate in documentManager.GetAllDocuments() {
                    row := NSharpLang.Compiler.CodeIntelligence.EditorTypeHierarchyFacts.ResolveRow(candidate.Symbols, name, candidate.Uri)
                    if row != null {
                        results.Add(TypeHierarchyProtocol.ToItem(row))
                        break
                    }
                }
            }

            if results.Count == 0 {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null)
            }

            return Task.FromResult<Container<TypeHierarchyItem>?>(new Container<TypeHierarchyItem>(results))
        } catch failure: Exception {
            logger.LogError(failure, "Error handling type hierarchy supertypes")
            return Task.FromResult<Container<TypeHierarchyItem>?>(null)
        }
    }
}

// Handles typeHierarchy/subtypes requests.
// Given a TypeHierarchyItem, finds all types that inherit or implement it.
class TypeHierarchySubtypesHandler: TypeHierarchySubtypesHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<TypeHierarchySubtypesHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<TypeHierarchySubtypesHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: TypeHierarchySubtypesParams, cancellationToken: CancellationToken): Task<Container<TypeHierarchyItem>?> {
        targetName := request.Item.Name
        targetIsInterface := request.Item.Kind == OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Interface

        logger.LogDebug("Type hierarchy subtypes for: {Name}", targetName)

        try {
            rows := new List<NSharpLang.Compiler.CodeIntelligence.EditorTypeHierarchyRow>()
            for doc in documentManager.GetAllDocuments() {
                if cancellationToken.IsCancellationRequested {
                    break
                }

                NSharpLang.Compiler.CodeIntelligence.EditorTypeHierarchyFacts.AppendSubtypeRows(
                    doc.CompilationUnit,
                    doc.Uri,
                    targetName,
                    targetIsInterface,
                    rows
                )
            }

            if rows.Count == 0 {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null)
            }

            results := new List<TypeHierarchyItem>()
            for row in rows {
                results.Add(TypeHierarchyProtocol.ToItem(row))
            }

            return Task.FromResult<Container<TypeHierarchyItem>?>(new Container<TypeHierarchyItem>(results))
        } catch failure: Exception {
            logger.LogError(failure, "Error handling type hierarchy subtypes")
            return Task.FromResult<Container<TypeHierarchyItem>?>(null)
        }
    }
}
