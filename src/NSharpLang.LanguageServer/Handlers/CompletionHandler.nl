namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles code completion (Ctrl+Space in VS Code).
//
// WHAT THE MENU OFFERS AND IN WHAT ORDER is N#-owned. `EditorCompletionMenuFacts` holds the
// language's own words, the five snippets, the six sort ranks, the grey signature line beside each
// declared name, and the three questions about where the caret is — is it after a dot, is it on an
// `import` line, and how much of a name has been typed. `CompletionReceiverFacts` and
// `EditorCompletionFacts` already owned the member list after a dot, and it now owns the bound
// model's own offers too — which variables are visible at a position, which functions are not
// already members, and the grey type line beside each. What is left here is the protocol and the
// two services the editor keeps: OmniSharp's CompletionItem, the type resolver's importable types,
// and the import edits that come with them.
//
// The owner's names are written in full because `CompletionContext` is declared on BOTH sides — the
// code-intelligence vocabulary and the protocol's — and N# has no import alias.
class CompletionHandler: CompletionHandlerBase {
    readonly documentManager: DocumentManager
    readonly typeResolver: TypeResolver
    readonly logger: ILogger<CompletionHandler>
    readonly completionEngine: NSharpLang.Compiler.CodeIntelligence.CompletionEngine

    constructor(documentManager: DocumentManager, typeResolver: TypeResolver, logger: ILogger<CompletionHandler>) {
        this.documentManager = documentManager
        this.typeResolver = typeResolver
        this.logger = logger
        completionEngine = new NSharpLang.Compiler.CodeIntelligence.CompletionEngine()
    }

    override func Handle(request: CompletionParams, cancellationToken: CancellationToken): Task<CompletionList> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        line := request.Position.Line
        character := request.Position.Character

        if doc != null {
            importItems := getImportCompletionItems(doc.Text, line, character)
            if importItems.Count > 0 {
                logger.LogDebug("Providing {Count} import completion items for {Uri}", importItems.Count, uri)
                return Task.FromResult(new CompletionList(importItems))
            }
        }

        items := new List<CompletionItem>()

        // Check if this is member completion (triggered by '.')
        // Use trigger character as primary signal — more reliable than text scanning
        // because the document text may not have the dot yet (race condition with didChange)
        triggerCharacter := request.Context?.TriggerCharacter
        isMemberAccess := triggerCharacter == "."
        if !isMemberAccess && doc != null {
            isMemberAccess = NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuFacts.IsMemberAccessAt(doc.Text, line, character)
        }

        if isMemberAccess && doc != null {
            memberItems := getMemberCompletionItems(uri, doc, line, character)
            if memberItems.Count > 0 {
                logger.LogDebug("Providing {Count} member completion items for {Uri}", memberItems.Count, uri)
                return Task.FromResult(new CompletionList(memberItems))
            }
        }

        itemKeys := new HashSet<string>(StringComparer.Ordinal)
        inScopeNames := new HashSet<string>(StringComparer.Ordinal)
        currentPrefix := NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuFacts.IdentifierPrefix(doc?.Text, line, character)

        addDocumentSymbolCompletionItems(doc, items, itemKeys, inScopeNames)
        addSemanticCompletionItems(doc, line, character, items, itemKeys, inScopeNames)
        addLanguageCompletionItems(items, itemKeys)
        addExternalImportableCompletionItems(doc, currentPrefix, request.Position, items, itemKeys, inScopeNames)

        logger.LogDebug("Providing {Count} completion items for {Uri}", items.Count, uri)

        return Task.FromResult(new CompletionList(items))
    }

    func getImportCompletionItems(text: string, line: int, character: int): List<CompletionItem> {
        importPrefix := NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuFacts.ImportPrefixAt(text, line, character)
        if importPrefix == null {
            return new List<CompletionItem>()
        }

        prefix := importPrefix
        items := new List<CompletionItem>()
        for segment in typeResolver.GetNamespaceSuggestions(prefix) {
            detail := NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuFacts.ImportSuggestionDetail(prefix, segment)
            items.Add(new CompletionItem {
                Label: segment,
                Kind: CompletionItemKind.Module,
                Detail: detail,
                InsertText: segment
            })
        }

        return items
    }

    // Member completions for the receiver before the dot, from the same N# owner that answers
    // `nlc query completions`.
    func getMemberCompletionItems(uri: string, doc: DocumentState, line: int, character: int): List<CompletionItem> {
        try {
            result := resolveMemberCompletions(uri, doc, line, character)
            if result == null || result.Context != NSharpLang.Compiler.CodeIntelligence.CompletionContext.MemberAccess {
                return new List<CompletionItem>()
            }

            return buildMemberCompletionItems(result)
        } catch failure: Exception {
            logger.LogError(failure, "Error getting member completion items")
            return new List<CompletionItem>()
        }
    }

    // The project snapshot answers when the buffer is backed by one — the same snapshot, and so the
    // same analyzer type universe, that definition, references and hover already use. A loose buffer
    // outside any project falls back to the open documents' own models, which is the tier that types
    // a receiver declared in the file being edited.
    func resolveMemberCompletions(uri: string, doc: DocumentState, line: int, character: int): NSharpLang.Compiler.CodeIntelligence.CompletionResult? {
        binding := documentManager.SynchronizedProjectSnapshot(uri)
        if binding != null {
            return completionEngine.GetCompletions(binding.Snapshot, binding.FilePath, line + 1, character + 1, false)
        }

        unit := doc.CompilationUnit
        if unit == null {
            return null
        }

        semanticModels := new List<SemanticModel>()
        compilationUnits := new List<CompilationUnit>()
        for state in documentManager.GetAllDocuments() {
            model := state.SemanticModel
            if model != null {
                semanticModels.Add(model)
            }

            stateUnit := state.CompilationUnit
            if stateUnit != null {
                compilationUnits.Add(stateUnit)
            }
        }

        return NSharpLang.Compiler.CodeIntelligence.CompletionReceiverFacts.GetMemberAccessCompletions(
            unit,
            doc.SemanticModel,
            null,
            line + 1,
            character + 1,
            semanticModels,
            compilationUnits
        )
    }

    // The owner's grouped answer as LSP items, in the owner's own order — one row per member name,
    // flattened and ordered by the same N# owner the CLI and the playground ask.
    static func buildMemberCompletionItems(result: NSharpLang.Compiler.CodeIntelligence.CompletionResult): List<CompletionItem> {
        items := new List<CompletionItem>()
        for member in NSharpLang.Compiler.CodeIntelligence.CompletionEngineKernels.FlattenCompletionGroups(result.Completions) {
            kind := (CompletionItemKind)NSharpLang.Compiler.CodeIntelligence.EditorCompletionFacts.LspCompletionItemKind(member.Kind)
            detail := NSharpLang.Compiler.CodeIntelligence.EditorCompletionFacts.MemberDetailText(member)
            sortText := NSharpLang.Compiler.CodeIntelligence.EditorCompletionFacts.MemberSortText(items.Count)

            items.Add(new CompletionItem {
                Label: member.Name,
                Kind: kind,
                Detail: detail,
                InsertText: member.Name,
                SortText: sortText
            })
        }

        return items
    }

    static func addLanguageCompletionItems(items: List<CompletionItem>, itemKeys: HashSet<string>) {
        for row in NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuFacts.LanguageRows() {
            addUniqueCompletionItem(items, itemKeys, toCompletionItem(row), row.Key)
        }
    }

    static func addDocumentSymbolCompletionItems(
        doc: DocumentState?,
        items: List<CompletionItem>,
        itemKeys: HashSet<string>,
        inScopeNames: HashSet<string>
    ) {
        if doc == null || doc.CompilationUnit == null {
            return
        }

        for row in NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuFacts.DocumentSymbolRows(doc.CompilationUnit, doc.Text) {
            addInScopeCompletionItem(items, itemKeys, inScopeNames, row.Label, toCompletionItem(row))
        }
    }

    static func toCompletionItem(row: NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuRow): CompletionItem {
        // Only a snippet declares a format; anything else leaves the field off the wire, which is
        // what the client reads as plain text and what this server has always sent.
        format := (InsertTextFormat)0
        if row.IsSnippet {
            format = InsertTextFormat.Snippet
        }

        kind := (CompletionItemKind)row.Kind

        return new CompletionItem {
            Label: row.Label,
            Kind: kind,
            Detail: row.Detail,
            InsertText: row.InsertText,
            InsertTextFormat: format,
            Documentation: row.Documentation,
            SortText: row.SortText
        }
    }

    // What the analyzer resolved at the caret, as the owner's rows: the variables visible from this
    // position and the functions the bound model knows, with the names a type already carries left
    // out.
    static func addSemanticCompletionItems(
        doc: DocumentState?,
        line: int,
        character: int,
        items: List<CompletionItem>,
        itemKeys: HashSet<string>,
        inScopeNames: HashSet<string>
    ) {
        semanticModel := doc?.SemanticModel
        compilationUnit := doc?.CompilationUnit
        text := doc?.Text

        for row in NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuFacts.SemanticRows(semanticModel, compilationUnit, text, line, character) {
            addInScopeCompletionItem(items, itemKeys, inScopeNames, row.Label, toCompletionItem(row))
        }
    }

    func addExternalImportableCompletionItems(
        doc: DocumentState?,
        currentPrefix: string,
        position: Position,
        items: List<CompletionItem>,
        itemKeys: HashSet<string>,
        inScopeNames: HashSet<string>
    ) {
        compilationUnit := doc?.CompilationUnit
        text := doc?.Text ?? ""
        planner := new ImportEditPlanner(compilationUnit, text)
        positionLine := position.Line
        positionCharacter := position.Character

        for importable in typeResolver.GetImportableTypes(currentPrefix) {
            isInScope := ImportEditPlanner.IsNamespaceInScope(compilationUnit, importable.Namespace)

            edits := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit>()
            for edit in planner.CompletionEdits(importable.Namespace, importable.Name, positionLine + 1, positionCharacter) {
                edits.Add(new OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit {
                    Range: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                        edit.StartLine - 1,
                        edit.StartColumn,
                        edit.EndLine - 1,
                        edit.EndColumn
                    ),
                    NewText: edit.NewText
                })
            }

            additional := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit>()
            index := 1
            while index < edits.Count {
                additional.Add(edits[index])
                index = index + 1
            }

            kind := CompletionItemKind.Class
            if importable.IsInterface {
                kind = CompletionItemKind.Interface
            } else if importable.IsEnum {
                kind = CompletionItemKind.Enum
            }

            detail := importable.FullName
            if !isInScope {
                detail = importable.FullName + " (auto-import " + importable.Namespace + ")"
            }

            sortText := NSharpLang.Compiler.CodeIntelligence.EditorCompletionMenuFacts.ExternalSortText(isInScope, importable.Name, importable.Namespace)

            item := new CompletionItem {
                Label: importable.Name,
                Kind: kind,
                Detail: detail,
                InsertText: importable.Name,
                TextEdit: new TextEditOrInsertReplaceEdit(edits[0]),
                AdditionalTextEdits: new TextEditContainer(additional),
                SortText: sortText
            }

            if isInScope {
                addInScopeCompletionItem(items, itemKeys, inScopeNames, importable.Name, item)
                continue
            }

            if inScopeNames.Contains(importable.Name) {
                continue
            }

            addUniqueCompletionItem(items, itemKeys, item, "external-import:" + importable.Name)
        }
    }

    static func addInScopeCompletionItem(
        items: List<CompletionItem>,
        itemKeys: HashSet<string>,
        inScopeNames: HashSet<string>,
        name: string,
        item: CompletionItem
    ) {
        if !inScopeNames.Add(name) {
            return
        }

        addUniqueCompletionItem(items, itemKeys, item, "scope:" + name)
    }

    static func addUniqueCompletionItem(
        items: List<CompletionItem>,
        itemKeys: HashSet<string>,
        item: CompletionItem,
        key: string
    ) {
        if itemKeys.Add(key) {
            items.Add(item)
        }
    }

    override func Handle(request: CompletionItem, cancellationToken: CancellationToken): Task<CompletionItem> {
        // We don't provide resolve capabilities, so just return the item as-is
        return Task.FromResult(request)
    }

    protected override func CreateRegistrationOptions(
        capability: CompletionCapability,
        clientCapabilities: ClientCapabilities
    ): CompletionRegistrationOptions {
        return new CompletionRegistrationOptions {
            DocumentSelector: new TextDocumentSelector(new TextDocumentFilter { Language: "nsharp" }),
            ResolveProvider: false,
            TriggerCharacters: new Container<string>(".", ":", " ")
        }
    }
}
