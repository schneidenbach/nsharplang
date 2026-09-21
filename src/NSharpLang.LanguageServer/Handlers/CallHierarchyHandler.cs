using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Models;
using NSharpLang.LanguageServer.Services;
using ServerSymbolKind = NSharpLang.LanguageServer.Models.SymbolKind;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using LspSymbolKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// The protocol side of the call-hierarchy view.
///
/// WHICH function is declared where, WHICH function encloses a line, HOW FAR a function reaches
/// and WHAT it calls are all N#-owned by <c>EditorCallHierarchyFacts</c> — one nested member walk
/// instead of the three near-copies that used to live in the three handlers below. So is the
/// GROUPING both call views do: which references belong to one caller node, which call sites
/// belong to one callee, what a caller with no parsed declaration is called, and how wide each
/// highlight is. What is left here is the protocol and the document manager: OmniSharp's
/// CallHierarchyItem, the symbol tables the editor keeps, and the project-wide reference search.
/// </summary>
internal static class CallHierarchyProtocol
{
    internal static CallHierarchyItem ToItem(string name, string uri, CodeIntel.EditorCallHierarchyRange range)
    {
        return new CallHierarchyItem
        {
            Name = name,
            Kind = LspSymbolKind.Function,
            Uri = DocumentUri.From(uri),
            Range = new LspRange(range.StartLine, range.StartCharacter, range.EndLine, range.EndCharacter),
            SelectionRange = new LspRange(range.StartLine, range.StartCharacter, range.StartLine, range.SelectionEndCharacter)
        };
    }

    /// <summary>
    /// A node built from a symbol location alone, where the whole node IS the name — no AST was
    /// consulted, so there is no wider extent to report.
    /// </summary>
    internal static CallHierarchyItem ToItem(SymbolLocation location)
    {
        var range = new LspRange(
            location.Line, location.Column,
            location.Line, location.Column + CodeIntel.EditorSymbolLookupFacts.SelectionWidth(location.Length));

        return new CallHierarchyItem
        {
            Name = location.Name,
            Kind = LspSymbolKind.Function,
            Uri = DocumentUri.From(location.Uri),
            Range = range,
            SelectionRange = range
        };
    }

    internal static LspRange ToRange(CodeIntel.EditorCallRange range)
    {
        return new LspRange(range.Line, range.StartCharacter, range.Line, range.EndCharacter);
    }

    internal static CodeIntel.EditorSymbolTableKind TableKind(ServerSymbolKind kind)
        => (CodeIntel.EditorSymbolTableKind)(int)kind;
}

/// <summary>
/// Handles textDocument/prepareCallHierarchy requests.
/// Resolves the function at the cursor to a CallHierarchyItem so that
/// incoming/outgoing call queries can follow.
/// </summary>
public class CallHierarchyPrepareHandler : CallHierarchyPrepareHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<CallHierarchyPrepareHandler> _logger;

    public CallHierarchyPrepareHandler(DocumentManager documentManager, ILogger<CallHierarchyPrepareHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<CallHierarchyItem>?> Handle(
        CallHierarchyPrepareParams request,
        CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Container<CallHierarchyItem>?>(null);
        }

        try
        {
            var word = EditorUtilities.GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<Container<CallHierarchyItem>?>(null);
            }

            _logger.LogDebug("Call hierarchy prepare for: {Word}", word);

            if (!IsFunctionSymbol(doc, word))
            {
                _logger.LogDebug("Symbol '{Word}' is not a function or method", word);
                return Task.FromResult<Container<CallHierarchyItem>?>(null);
            }

            if (doc.SymbolLocations == null
                || !doc.SymbolLocations.TryGetValue(word, out var locations))
            {
                return Task.FromResult<Container<CallHierarchyItem>?>(null);
            }

            var declared = CodeIntel.EditorSymbolLookupFacts.FirstCallableIndex(
                locations.Select(location => CallHierarchyProtocol.TableKind(location.Kind)).ToList());
            if (declared < 0)
            {
                return Task.FromResult<Container<CallHierarchyItem>?>(null);
            }
            var funcLoc = locations[declared];

            // The selection range is where the editor recorded the NAME, in the symbol location's
            // own 0-based coordinates. Only the wider range comes from the AST, and only when the
            // declaration is found there — otherwise the node is exactly the name.
            var selectionRange = new LspRange(
                funcLoc.Line, funcLoc.Column,
                funcLoc.Line, funcLoc.Column + CodeIntel.EditorSymbolLookupFacts.SelectionWidth(funcLoc.Length));

            var declaration = CodeIntel.EditorCallHierarchyFacts.FunctionAtLine(
                doc.CompilationUnit, word, funcLoc.Line + 1);

            var range = selectionRange;
            if (declaration != null)
            {
                var astRange = CodeIntel.EditorCallHierarchyFacts.FunctionRange(declaration, word, funcLoc.Line);
                range = new LspRange(astRange.StartLine, astRange.StartCharacter, astRange.EndLine, astRange.EndCharacter);
            }

            var item = new CallHierarchyItem
            {
                Name = word,
                Kind = LspSymbolKind.Function,
                Uri = DocumentUri.From(funcLoc.Uri),
                Range = range,
                SelectionRange = selectionRange
            };

            return Task.FromResult<Container<CallHierarchyItem>?>(
                new Container<CallHierarchyItem>(item));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling call hierarchy prepare");
            return Task.FromResult<Container<CallHierarchyItem>?>(null);
        }
    }

    private static bool IsFunctionSymbol(Models.DocumentState doc, string word)
    {
        Models.SymbolInfo? symbolInfo = null;
        doc.SymbolsInfo?.TryGetValue(word, out symbolInfo);
        var locationKinds = doc.SymbolLocations != null && doc.SymbolLocations.TryGetValue(word, out var locations)
            ? locations.Select(location => CallHierarchyProtocol.TableKind(location.Kind)).ToList()
            : null;

        return CodeIntel.EditorSymbolLookupFacts.IsCallableSymbol(symbolInfo != null,
            symbolInfo != null ? CallHierarchyProtocol.TableKind(symbolInfo.Kind) : default, locationKinds);
    }

    protected override CallHierarchyRegistrationOptions CreateRegistrationOptions(
        CallHierarchyCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new CallHierarchyRegistrationOptions();
    }
}

/// <summary>
/// Handles callHierarchy/incomingCalls requests.
/// Finds all functions that call the given function (callers).
/// </summary>
public class CallHierarchyIncomingHandler : CallHierarchyIncomingHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<CallHierarchyIncomingHandler> _logger;

    public CallHierarchyIncomingHandler(DocumentManager documentManager, ILogger<CallHierarchyIncomingHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<CallHierarchyIncomingCall>?> Handle(
        CallHierarchyIncomingCallsParams request,
        CancellationToken cancellationToken)
    {
        var item = request.Item;
        var uri = item.Uri.ToString();

        try
        {
            _logger.LogDebug("Call hierarchy incoming calls for: {Name}", item.Name);

            var references = _documentManager.FindProjectReferences(
                uri,
                item.SelectionRange.Start.Line,
                item.SelectionRange.Start.Character);

            if (references != null && references.Count > 0)
            {
                return Task.FromResult<Container<CallHierarchyIncomingCall>?>(
                    BuildIncomingCalls(uri, references));
            }

            return Task.FromResult<Container<CallHierarchyIncomingCall>?>(
                new Container<CallHierarchyIncomingCall>());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling call hierarchy incoming calls");
            return Task.FromResult<Container<CallHierarchyIncomingCall>?>(
                new Container<CallHierarchyIncomingCall>());
        }
    }

    /// <summary>
    /// The owner's caller groups as the protocol's incoming calls. Each reference is paired with
    /// the file it lives in and the function that encloses it — the only two questions the editor
    /// has to answer, because only it can turn a compiler-relative file name into a URI and find
    /// the document parsed from it.
    /// </summary>
    private Container<CallHierarchyIncomingCall> BuildIncomingCalls(
        string originUri,
        List<NSharpLang.Compiler.CodeIntelligence.ReferenceResult> references)
    {
        var projectRoot = _documentManager.GetProjectRootForUri(originUri);
        var sources = new List<CodeIntel.EditorIncomingCallSource>();

        foreach (var reference in references)
        {
            var fileUri = new Uri(_documentManager.ResolveProjectFilePath(projectRoot, reference.File)).AbsoluteUri;
            var doc = _documentManager.GetDocument(fileUri);

            sources.Add(new CodeIntel.EditorIncomingCallSource(
                fileUri,
                reference,
                CodeIntel.EditorCallHierarchyFacts.EnclosingFunction(doc?.CompilationUnit, reference.Line)));
        }

        var results = CodeIntel.EditorCallHierarchyFacts.IncomingCallGroups(sources)
            .Select(group => new CallHierarchyIncomingCall
            {
                From = CallHierarchyProtocol.ToItem(group.CallerName, group.FileUri, group.Range),
                FromRanges = new Container<LspRange>(group.FromRanges.Select(CallHierarchyProtocol.ToRange))
            })
            .ToList();

        return new Container<CallHierarchyIncomingCall>(results);
    }
}

/// <summary>
/// Handles callHierarchy/outgoingCalls requests.
/// Finds all functions called from within the given function (callees).
/// </summary>
public class CallHierarchyOutgoingHandler : CallHierarchyOutgoingHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<CallHierarchyOutgoingHandler> _logger;

    public CallHierarchyOutgoingHandler(DocumentManager documentManager, ILogger<CallHierarchyOutgoingHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<CallHierarchyOutgoingCall>?> Handle(
        CallHierarchyOutgoingCallsParams request,
        CancellationToken cancellationToken)
    {
        var item = request.Item;
        var uri = item.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.CompilationUnit?.Declarations == null)
        {
            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                new Container<CallHierarchyOutgoingCall>());
        }

        try
        {
            _logger.LogDebug("Call hierarchy outgoing calls for: {Name}", item.Name);

            var declaration = CodeIntel.EditorCallHierarchyFacts.FunctionAtLine(
                doc.CompilationUnit, item.Name, item.SelectionRange.Start.Line + 1);

            if (declaration == null)
            {
                return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                    new Container<CallHierarchyOutgoingCall>());
            }

            var sites = CodeIntel.EditorCallHierarchyFacts.OutgoingCallSites(declaration);
            if (sites.Count == 0)
            {
                return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                    new Container<CallHierarchyOutgoingCall>());
            }

            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                new Container<CallHierarchyOutgoingCall>(BuildOutgoingCalls(doc, sites)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling call hierarchy outgoing calls");
            return Task.FromResult<Container<CallHierarchyOutgoingCall>?>(
                new Container<CallHierarchyOutgoingCall>());
        }
    }

    private List<CallHierarchyOutgoingCall> BuildOutgoingCalls(
        Models.DocumentState doc,
        List<CodeIntel.EditorCallSiteRow> sites)
    {
        var results = new List<CallHierarchyOutgoingCall>();

        foreach (var group in CodeIntel.EditorCallHierarchyFacts.OutgoingCallGroups(sites))
        {
            var calleeItem = ResolveCalleeItem(doc, group.CalleeName);
            if (calleeItem == null)
            {
                continue;
            }

            results.Add(new CallHierarchyOutgoingCall
            {
                To = calleeItem,
                FromRanges = new Container<LspRange>(group.FromRanges.Select(CallHierarchyProtocol.ToRange))
            });
        }

        return results;
    }

    /// <summary>
    /// Resolves a callee name to a node through the symbol locations the editor keeps: the origin
    /// document first, then every open document.
    /// </summary>
    private CallHierarchyItem? ResolveCalleeItem(Models.DocumentState originDoc, string calleeName)
    {
        if (originDoc.SymbolLocations != null && originDoc.SymbolLocations.TryGetValue(calleeName, out var locations))
        {
            var here = CodeIntel.EditorSymbolLookupFacts.FirstCallableIndex(
                locations.Select(location => CallHierarchyProtocol.TableKind(location.Kind)).ToList());
            if (here >= 0)
            {
                return CallHierarchyProtocol.ToItem(locations[here]);
            }
        }

        var workspace = _documentManager.FindSymbolLocations(calleeName);
        var best = CodeIntel.EditorSymbolLookupFacts.FirstCallableIndex(
            workspace.Select(location => CallHierarchyProtocol.TableKind(location.Kind)).ToList());

        return best < 0 ? null : CallHierarchyProtocol.ToItem(workspace[best]);
    }
}
