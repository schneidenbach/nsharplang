namespace NSharpLang.LanguageServer.Handlers

import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Models
import OmniSharp.Extensions.LanguageServer.Protocol.Workspace

// Handles workspace/symbol requests (Ctrl+T — Go to Symbol in Workspace).
//
// WHICH names a file offers, in WHAT order and WHERE each one sits are N#-owned by
// `EditorWorkspaceSymbolFacts`: the subsequence match, the one-level member expansion, the rule
// that a member is only reached through a matching type, and the coordinate arithmetic — including
// the shipped off-by-one the owner's contract now pins. What is left here is the protocol:
// OmniSharp's WorkspaceSymbol and the wire numbers of its symbol kinds.
//
// The owner's names are written in full because `SymbolKind` is declared on BOTH sides — the
// editor's vocabulary and the protocol's — and N# has no import alias.
class WorkspaceSymbolHandler: WorkspaceSymbolsHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<WorkspaceSymbolHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<WorkspaceSymbolHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: WorkspaceSymbolParams, cancellationToken: CancellationToken): Task<Container<WorkspaceSymbol>?> {
        query := request.Query ?? ""
        logger.LogDebug("Workspace symbol request: '{Query}'", query)

        symbols := new List<WorkspaceSymbol>()

        for doc in documentManager.GetAllDocuments() {
            if cancellationToken.IsCancellationRequested {
                break
            }

            for row in NSharpLang.Compiler.CodeIntelligence.EditorWorkspaceSymbolFacts.SymbolRows(doc.CompilationUnit, doc.Text, query) {
                range := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    row.Line,
                    row.StartCharacter,
                    row.Line,
                    row.EndCharacter
                )
                location := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Location {
                    Uri: DocumentUri.From(doc.Uri),
                    Range: range
                }

                symbols.Add(new WorkspaceSymbol {
                    Name: row.Name,
                    Kind: convertSymbolKind(row.Kind),
                    Location: location,
                    ContainerName: row.ContainerName
                })
            }
        }

        logger.LogDebug("Returning {Count} workspace symbols", symbols.Count)
        return Task.FromResult<Container<WorkspaceSymbol>?>(new Container<WorkspaceSymbol>(symbols))
    }

    protected override func CreateRegistrationOptions(
        capability: WorkspaceSymbolCapability,
        clientCapabilities: ClientCapabilities
    ): WorkspaceSymbolRegistrationOptions {
        return new WorkspaceSymbolRegistrationOptions()
    }

    // The owner's subsequence match, under the name nine years of callers and the
    // internals-visibility fixture know it by.
    //
    // THIS IS THE ASSEMBLY'S FRIEND-GRANT SUBJECT. It is camelCase, so N# emits it as CLR
    // `assembly`: the `Tests` project this assembly names in its `internalsVisibleTo:` can call it
    // and nothing else can. `tests/native/census-internals-visible-to` stands on exactly that.
    static func matchesQuery(name: string, query: string): bool => NSharpLang.Compiler.CodeIntelligence.EditorWorkspaceSymbolFacts.MatchesQuery(name, query)

    static func convertSymbolKind(kind: NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind): OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind {
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Class {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Class
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Struct {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Struct
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Record {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Class
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Interface {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Interface
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Enum {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Enum
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Union {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Enum
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Function {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Function
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Method {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Method
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Property {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Property
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Field {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Field
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Parameter {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Variable
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.LocalVariable {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Variable
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.EnumMember {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.EnumMember
        }
        if kind == NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Constructor {
            return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Constructor
        }

        return OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Variable
    }
}
