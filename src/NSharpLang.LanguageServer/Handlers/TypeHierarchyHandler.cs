using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
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
/// The protocol side of the type-hierarchy view. All three requests — preparing the node under
/// the caret, walking up to the supertypes and walking down to the subtypes — are decided by
/// <c>EditorTypeHierarchyFacts</c>, including the asymmetry between the two walks. What is left
/// here is OmniSharp's TypeHierarchyItem and the wire numbers of its symbol kinds.
/// </summary>
internal static class TypeHierarchyProtocol
{
    internal static TypeHierarchyItem ToItem(CodeIntel.EditorTypeHierarchyRow row)
    {
        var range = new LspRange(row.Line, row.StartCharacter, row.Line, row.EndCharacter);

        return new TypeHierarchyItem
        {
            Name = row.Name,
            Kind = ToSymbolKind(row.Kind),
            Uri = DocumentUri.From(row.Uri),
            Range = range,
            SelectionRange = range
        };
    }

    internal static LspSymbolKind ToSymbolKind(CodeIntel.EditorSymbolKind kind)
    {
        return kind switch
        {
            CodeIntel.EditorSymbolKind.Interface => LspSymbolKind.Interface,
            CodeIntel.EditorSymbolKind.Struct => LspSymbolKind.Struct,
            CodeIntel.EditorSymbolKind.Enum => LspSymbolKind.Enum,
            _ => LspSymbolKind.Class
        };
    }
}

/// <summary>
/// Handles textDocument/prepareTypeHierarchy requests.
/// Resolves the type at the cursor position and returns a TypeHierarchyItem for it.
/// </summary>
public class TypeHierarchyPrepareHandler : TypeHierarchyPrepareHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<TypeHierarchyPrepareHandler> _logger;

    public TypeHierarchyPrepareHandler(DocumentManager documentManager, ILogger<TypeHierarchyPrepareHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<TypeHierarchyItem>?> Handle(TypeHierarchyPrepareParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<Container<TypeHierarchyItem>?>(null);
        }

        try
        {
            var word = EditorUtilities.GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            _logger.LogDebug("Type hierarchy prepare for: {Word}", word);

            var row = CodeIntel.EditorTypeHierarchyFacts.PrepareRow(doc.Symbols, word, uri);
            if (row == null)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            return Task.FromResult<Container<TypeHierarchyItem>?>(
                new Container<TypeHierarchyItem>(TypeHierarchyProtocol.ToItem(row)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling type hierarchy prepare");
            return Task.FromResult<Container<TypeHierarchyItem>?>(null);
        }
    }

    protected override TypeHierarchyRegistrationOptions CreateRegistrationOptions(
        TypeHierarchyCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new TypeHierarchyRegistrationOptions();
    }
}

/// <summary>
/// Handles typeHierarchy/supertypes requests.
/// Given a TypeHierarchyItem, finds its base class and implemented interfaces.
/// </summary>
public class TypeHierarchySupertypesHandler : TypeHierarchySupertypesHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<TypeHierarchySupertypesHandler> _logger;

    public TypeHierarchySupertypesHandler(DocumentManager documentManager, ILogger<TypeHierarchySupertypesHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<TypeHierarchyItem>?> Handle(TypeHierarchySupertypesParams request, CancellationToken cancellationToken)
    {
        var targetName = request.Item.Name;
        var targetUri = request.Item.Uri.ToString();

        _logger.LogDebug("Type hierarchy supertypes for: {Name}", targetName);

        try
        {
            var doc = _documentManager.GetDocument(targetUri);
            if (doc?.CompilationUnit?.Declarations == null)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            var results = new List<TypeHierarchyItem>();
            foreach (var name in CodeIntel.EditorTypeHierarchyFacts.SupertypeNames(doc.CompilationUnit, targetName))
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    break;
                }

                foreach (var candidate in _documentManager.GetAllDocuments())
                {
                    var row = CodeIntel.EditorTypeHierarchyFacts.ResolveRow(candidate.Symbols, name, candidate.Uri);
                    if (row != null)
                    {
                        results.Add(TypeHierarchyProtocol.ToItem(row));
                        break;
                    }
                }
            }

            if (results.Count == 0)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            return Task.FromResult<Container<TypeHierarchyItem>?>(
                new Container<TypeHierarchyItem>(results));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling type hierarchy supertypes");
            return Task.FromResult<Container<TypeHierarchyItem>?>(null);
        }
    }
}

/// <summary>
/// Handles typeHierarchy/subtypes requests.
/// Given a TypeHierarchyItem, finds all types that inherit or implement it.
/// </summary>
public class TypeHierarchySubtypesHandler : TypeHierarchySubtypesHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<TypeHierarchySubtypesHandler> _logger;

    public TypeHierarchySubtypesHandler(DocumentManager documentManager, ILogger<TypeHierarchySubtypesHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<Container<TypeHierarchyItem>?> Handle(TypeHierarchySubtypesParams request, CancellationToken cancellationToken)
    {
        var targetName = request.Item.Name;
        var targetIsInterface = request.Item.Kind == LspSymbolKind.Interface;

        _logger.LogDebug("Type hierarchy subtypes for: {Name}", targetName);

        try
        {
            var rows = new List<CodeIntel.EditorTypeHierarchyRow>();
            foreach (var doc in _documentManager.GetAllDocuments())
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    break;
                }

                CodeIntel.EditorTypeHierarchyFacts.AppendSubtypeRows(
                    doc.CompilationUnit, doc.Uri, targetName, targetIsInterface, rows);
            }

            if (rows.Count == 0)
            {
                return Task.FromResult<Container<TypeHierarchyItem>?>(null);
            }

            var results = new List<TypeHierarchyItem>();
            foreach (var row in rows)
            {
                results.Add(TypeHierarchyProtocol.ToItem(row));
            }

            return Task.FromResult<Container<TypeHierarchyItem>?>(
                new Container<TypeHierarchyItem>(results));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling type hierarchy subtypes");
            return Task.FromResult<Container<TypeHierarchyItem>?>(null);
        }
    }
}
