namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// The protocol side of the call-hierarchy view.
//
// WHICH function is declared where, WHICH function encloses a line, HOW FAR a function reaches and
// WHAT it calls are all N#-owned by `EditorCallHierarchyFacts` — one nested member walk instead of
// the three near-copies that used to live in the three handlers below. So is the GROUPING both call
// views do: which references belong to one caller node, which call sites belong to one callee, what
// a caller with no parsed declaration is called, and how wide each highlight is. What is left here
// is the protocol and the document manager: OmniSharp's CallHierarchyItem, the symbol tables the
// editor keeps, and the project-wide reference search.
//
// The owner's names are written in full because `SymbolKind` is declared on BOTH sides — the
// editor's vocabulary and the protocol's — and N# has no import alias.
class CallHierarchyProtocol {
    static func ToItem(name: string, uri: string, range: NSharpLang.Compiler.CodeIntelligence.EditorCallHierarchyRange): CallHierarchyItem {
        return new CallHierarchyItem {
            Name: name,
            Kind: OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Function,
            Uri: DocumentUri.From(uri),
            Range: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                range.StartLine,
                range.StartCharacter,
                range.EndLine,
                range.EndCharacter
            ),
            SelectionRange: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                range.StartLine,
                range.StartCharacter,
                range.StartLine,
                range.SelectionEndCharacter
            )
        }
    }

    // A node built from a symbol location alone, where the whole node IS the name — no AST was
    // consulted, so there is no wider extent to report.
    static func ToItemFromLocation(location: SymbolLocation): CallHierarchyItem {
        width := NSharpLang.Compiler.CodeIntelligence.EditorSymbolLookupFacts.SelectionWidth(location.Length)
        range := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
            location.Line,
            location.Column,
            location.Line,
            location.Column + width
        )

        return new CallHierarchyItem {
            Name: location.Name,
            Kind: OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Function,
            Uri: DocumentUri.From(location.Uri),
            Range: range,
            SelectionRange: range
        }
    }

    static func ToRange(range: NSharpLang.Compiler.CodeIntelligence.EditorCallRange): OmniSharp.Extensions.LanguageServer.Protocol.Models.Range {
        return new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
            range.Line,
            range.StartCharacter,
            range.Line,
            range.EndCharacter
        )
    }

    static func TableKind(kind: NSharpLang.LanguageServer.Models.SymbolKind): NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind => (NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind)(int)kind

    static func TableKinds(locations: List<SymbolLocation>): List<NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind> {
        kinds := new List<NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind>()
        for location in locations {
            kinds.Add(TableKind(location.Kind))
        }

        return kinds
    }

    static func TableKindsFrom(locations: IReadOnlyList<SymbolLocation>): List<NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind> {
        kinds := new List<NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind>()
        index := 0
        while index < locations.Count {
            kinds.Add(TableKind(locations[index].Kind))
            index = index + 1
        }

        return kinds
    }
}

// Handles textDocument/prepareCallHierarchy requests.
// Resolves the function at the cursor to a CallHierarchyItem so that incoming/outgoing call queries
// can follow.
class CallHierarchyPrepareHandler: CallHierarchyPrepareHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<CallHierarchyPrepareHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<CallHierarchyPrepareHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: CallHierarchyPrepareParams, cancellationToken: CancellationToken): Task<Container<CallHierarchyItem>?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<Container<CallHierarchyItem>?>(null)
        }

        line := request.Position.Line
        character := request.Position.Character

        try {
            word := EditorUtilities.GetWordAtPosition(doc.Text, line, character)
            if string.IsNullOrWhiteSpace(word) {
                return Task.FromResult<Container<CallHierarchyItem>?>(null)
            }

            logger.LogDebug("Call hierarchy prepare for: {Word}", word)

            if !isFunctionSymbol(doc, word) {
                logger.LogDebug("Symbol '{Word}' is not a function or method", word)
                return Task.FromResult<Container<CallHierarchyItem>?>(null)
            }

            table := doc.SymbolLocations
            locations: List<SymbolLocation>? = null
            if table == null || !table.TryGetValue(word, out locations) {
                return Task.FromResult<Container<CallHierarchyItem>?>(null)
            }

            declared := NSharpLang.Compiler.CodeIntelligence.EditorSymbolLookupFacts.FirstCallableIndex(
                CallHierarchyProtocol.TableKinds(locations)
            )
            if declared < 0 {
                return Task.FromResult<Container<CallHierarchyItem>?>(null)
            }

            funcLoc := locations[declared]

            // The selection range is where the editor recorded the NAME, in the symbol location's
            // own 0-based coordinates. Only the wider range comes from the AST, and only when the
            // declaration is found there — otherwise the node is exactly the name.
            width := NSharpLang.Compiler.CodeIntelligence.EditorSymbolLookupFacts.SelectionWidth(funcLoc.Length)
            selectionRange := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                funcLoc.Line,
                funcLoc.Column,
                funcLoc.Line,
                funcLoc.Column + width
            )

            declaration := NSharpLang.Compiler.CodeIntelligence.EditorCallHierarchyFacts.FunctionAtLine(
                doc.CompilationUnit,
                word,
                funcLoc.Line + 1
            )

            range := selectionRange
            if declaration != null {
                astRange := NSharpLang.Compiler.CodeIntelligence.EditorCallHierarchyFacts.FunctionRange(declaration, word, funcLoc.Line)
                range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    astRange.StartLine,
                    astRange.StartCharacter,
                    astRange.EndLine,
                    astRange.EndCharacter
                )
            }

            item := new CallHierarchyItem {
                Name: word,
                Kind: OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind.Function,
                Uri: DocumentUri.From(funcLoc.Uri),
                Range: range,
                SelectionRange: selectionRange
            }

            return Task.FromResult<Container<CallHierarchyItem>?>(new Container<CallHierarchyItem>(item))
        } catch failure: Exception {
            logger.LogError(failure, "Error handling call hierarchy prepare")
            return Task.FromResult<Container<CallHierarchyItem>?>(null)
        }
    }

    static func isFunctionSymbol(doc: DocumentState, word: string): bool {
        symbolInfo: SymbolInfo? = null
        infoTable := doc.SymbolsInfo
        if infoTable != null {
            infoTable.TryGetValue(word, out symbolInfo)
        }

        locationKinds: List<NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind>? = null
        table := doc.SymbolLocations
        if table != null {
            locations: List<SymbolLocation>? = null
            if table.TryGetValue(word, out locations) {
                locationKinds = CallHierarchyProtocol.TableKinds(locations)
            }
        }

        hasSymbolInfo := symbolInfo != null
        symbolKind := NSharpLang.Compiler.CodeIntelligence.EditorSymbolTableKind.Class
        if symbolInfo != null {
            symbolKind = CallHierarchyProtocol.TableKind(symbolInfo.Kind)
        }

        return NSharpLang.Compiler.CodeIntelligence.EditorSymbolLookupFacts.IsCallableSymbol(hasSymbolInfo, symbolKind, locationKinds)
    }

    protected override func CreateRegistrationOptions(
        capability: CallHierarchyCapability,
        clientCapabilities: ClientCapabilities
    ): CallHierarchyRegistrationOptions {
        return new CallHierarchyRegistrationOptions()
    }
}

// Handles callHierarchy/incomingCalls requests.
// Finds all functions that call the given function (callers).
class CallHierarchyIncomingHandler: CallHierarchyIncomingHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<CallHierarchyIncomingHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<CallHierarchyIncomingHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: CallHierarchyIncomingCallsParams, cancellationToken: CancellationToken): Task<Container<CallHierarchyIncomingCall>?> {
        item := request.Item
        uri := item.Uri.ToString()

        try {
            logger.LogDebug("Call hierarchy incoming calls for: {Name}", item.Name)

            start := item.SelectionRange.Start
            references := documentManager.FindProjectReferences(uri, start.Line, start.Character)

            if references != null && references.Count > 0 {
                return Task.FromResult<Container<CallHierarchyIncomingCall>?>(buildIncomingCalls(uri, references))
            }

            return Task.FromResult<Container<CallHierarchyIncomingCall>?>(new Container<CallHierarchyIncomingCall>())
        } catch failure: Exception {
            logger.LogError(failure, "Error handling call hierarchy incoming calls")
            return Task.FromResult<Container<CallHierarchyIncomingCall>?>(new Container<CallHierarchyIncomingCall>())
        }
    }

    // The owner's caller groups as the protocol's incoming calls. Each reference is paired with the
    // file it lives in and the function that encloses it — the only two questions the editor has to
    // answer, because only it can turn a compiler-relative file name into a URI and find the
    // document parsed from it.
    func buildIncomingCalls(
        originUri: string,
        references: List<NSharpLang.Compiler.CodeIntelligence.ReferenceResult>
    ): Container<CallHierarchyIncomingCall> {
        projectRoot := documentManager.GetProjectRootForUri(originUri)
        sources := new List<NSharpLang.Compiler.CodeIntelligence.EditorIncomingCallSource>()

        for reference in references {
            resolvedPath := documentManager.ResolveProjectFilePath(projectRoot, reference.File)
            fileUri := new Uri(resolvedPath).AbsoluteUri
            doc := documentManager.GetDocument(fileUri)
            enclosing := NSharpLang.Compiler.CodeIntelligence.EditorCallHierarchyFacts.EnclosingFunction(doc?.CompilationUnit, reference.Line)

            sources.Add(new NSharpLang.Compiler.CodeIntelligence.EditorIncomingCallSource(fileUri, reference, enclosing))
        }

        results := new List<CallHierarchyIncomingCall>()
        for group in NSharpLang.Compiler.CodeIntelligence.EditorCallHierarchyFacts.IncomingCallGroups(sources) {
            fromRanges := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Range>()
            for callRange in group.FromRanges {
                fromRanges.Add(CallHierarchyProtocol.ToRange(callRange))
            }

            results.Add(new CallHierarchyIncomingCall {
                From: CallHierarchyProtocol.ToItem(group.CallerName, group.FileUri, group.Range),
                FromRanges: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Range>(fromRanges)
            })
        }

        return new Container<CallHierarchyIncomingCall>(results)
    }
}

// Handles callHierarchy/outgoingCalls requests.
// Finds all functions called from within the given function (callees).
class CallHierarchyOutgoingHandler: CallHierarchyOutgoingHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<CallHierarchyOutgoingHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<CallHierarchyOutgoingHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: CallHierarchyOutgoingCallsParams, cancellationToken: CancellationToken): Task<Container<CallHierarchyOutgoingCall>?> {
        item := request.Item
        uri := item.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null || doc.CompilationUnit == null || doc.CompilationUnit.Declarations == null {
            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(new Container<CallHierarchyOutgoingCall>())
        }

        try {
            logger.LogDebug("Call hierarchy outgoing calls for: {Name}", item.Name)

            start := item.SelectionRange.Start
            declaration := NSharpLang.Compiler.CodeIntelligence.EditorCallHierarchyFacts.FunctionAtLine(
                doc.CompilationUnit,
                item.Name,
                start.Line + 1
            )

            if declaration == null {
                return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(new Container<CallHierarchyOutgoingCall>())
            }

            sites := NSharpLang.Compiler.CodeIntelligence.EditorCallHierarchyFacts.OutgoingCallSites(declaration)
            if sites.Count == 0 {
                return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(new Container<CallHierarchyOutgoingCall>())
            }

            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                new Container<CallHierarchyOutgoingCall>(buildOutgoingCalls(doc, sites))
            )
        } catch failure: Exception {
            logger.LogError(failure, "Error handling call hierarchy outgoing calls")
            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(new Container<CallHierarchyOutgoingCall>())
        }
    }

    func buildOutgoingCalls(
        doc: DocumentState,
        sites: List<NSharpLang.Compiler.CodeIntelligence.EditorCallSiteRow>
    ): List<CallHierarchyOutgoingCall> {
        results := new List<CallHierarchyOutgoingCall>()

        for group in NSharpLang.Compiler.CodeIntelligence.EditorCallHierarchyFacts.OutgoingCallGroups(sites) {
            calleeItem := resolveCalleeItem(doc, group.CalleeName)
            if calleeItem == null {
                continue
            }

            fromRanges := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Range>()
            for callRange in group.FromRanges {
                fromRanges.Add(CallHierarchyProtocol.ToRange(callRange))
            }

            results.Add(new CallHierarchyOutgoingCall {
                To: calleeItem,
                FromRanges: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Range>(fromRanges)
            })
        }

        return results
    }

    // Resolves a callee name to a node through the symbol locations the editor keeps: the origin
    // document first, then every open document.
    func resolveCalleeItem(originDoc: DocumentState, calleeName: string): CallHierarchyItem? {
        table := originDoc.SymbolLocations
        if table != null {
            locations: List<SymbolLocation>? = null
            if table.TryGetValue(calleeName, out locations) {
                here := NSharpLang.Compiler.CodeIntelligence.EditorSymbolLookupFacts.FirstCallableIndex(
                    CallHierarchyProtocol.TableKinds(locations)
                )
                if here >= 0 {
                    return CallHierarchyProtocol.ToItemFromLocation(locations[here])
                }
            }
        }

        workspace := documentManager.FindSymbolLocations(calleeName)
        best := NSharpLang.Compiler.CodeIntelligence.EditorSymbolLookupFacts.FirstCallableIndex(
            CallHierarchyProtocol.TableKindsFrom(workspace)
        )

        if best < 0 {
            return null
        }

        return CallHierarchyProtocol.ToItemFromLocation(workspace[best])
    }
}
