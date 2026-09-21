using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles code completion (Ctrl+Space in VS Code).
///
/// WHAT THE MENU OFFERS AND IN WHAT ORDER is N#-owned. <c>EditorCompletionMenuFacts</c> holds the
/// language's own words, the five snippets, the six sort ranks, the grey signature line beside each
/// declared name, and the three questions about where the caret is — is it after a dot, is it on an
/// `import` line, and how much of a name has been typed. <c>CompletionReceiverFacts</c> and
/// <c>EditorCompletionFacts</c> already owned the member list after a dot. What is left here is the
/// protocol and the two services the editor keeps: OmniSharp's CompletionItem, the type resolver's
/// importable types, and the import edits that come with them.
/// </summary>
public class CompletionHandler : CompletionHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly TypeResolver _typeResolver;
    private readonly ILogger<CompletionHandler> _logger;
    private readonly CodeIntel.CompletionEngine _completionEngine = new();

    public CompletionHandler(DocumentManager documentManager, TypeResolver typeResolver, ILogger<CompletionHandler> logger)
    {
        _documentManager = documentManager;
        _typeResolver = typeResolver;
        _logger = logger;
    }

    public override Task<CompletionList> Handle(CompletionParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text != null)
        {
            var importItems = GetImportCompletionItems(doc.Text, request.Position.Line, request.Position.Character);
            if (importItems.Count > 0)
            {
                _logger.LogDebug("Providing {Count} import completion items for {Uri}", importItems.Count, uri);
                return Task.FromResult(new CompletionList(importItems));
            }
        }

        var items = new List<CompletionItem>();

        // Check if this is member completion (triggered by '.')
        // Use trigger character as primary signal — more reliable than text scanning
        // because the document text may not have the dot yet (race condition with didChange)
        var isMemberAccess = request.Context?.TriggerCharacter == "."
            || (doc?.Text != null && CodeIntel.EditorCompletionMenuFacts.IsMemberAccessAt(
                doc.Text, request.Position.Line, request.Position.Character));

        if (isMemberAccess && doc?.Text != null)
        {
            var memberItems = GetMemberCompletionItems(uri, doc, request.Position.Line, request.Position.Character);
            if (memberItems.Any())
            {
                _logger.LogDebug("Providing {Count} member completion items for {Uri}", memberItems.Count, uri);
                return Task.FromResult(new CompletionList(memberItems));
            }
        }

        var itemKeys = new HashSet<string>(StringComparer.Ordinal);
        var inScopeNames = new HashSet<string>(StringComparer.Ordinal);
        var currentPrefix = CodeIntel.EditorCompletionMenuFacts.IdentifierPrefix(
            doc?.Text, request.Position.Line, request.Position.Character);

        AddDocumentSymbolCompletionItems(doc, items, itemKeys, inScopeNames);
        AddSemanticCompletionItems(doc, request.Position.Line, request.Position.Character, items, itemKeys, inScopeNames);
        AddLanguageCompletionItems(items, itemKeys);
        AddExternalImportableCompletionItems(doc, currentPrefix, request.Position, items, itemKeys, inScopeNames);

        _logger.LogDebug("Providing {Count} completion items for {Uri}", items.Count, uri);

        return Task.FromResult(new CompletionList(items));
    }

    private List<CompletionItem> GetImportCompletionItems(string text, int line, int character)
    {
        var importPrefix = CodeIntel.EditorCompletionMenuFacts.ImportPrefixAt(text, line, character);
        if (importPrefix == null)
        {
            return new List<CompletionItem>();
        }

        return _typeResolver.GetNamespaceSuggestions(importPrefix)
            .Select(segment => new CompletionItem
            {
                Label = segment,
                Kind = CompletionItemKind.Module,
                Detail = CodeIntel.EditorCompletionMenuFacts.ImportSuggestionDetail(importPrefix, segment),
                InsertText = segment
            })
            .ToList();
    }

    /// <summary>
    /// Member completions for the receiver before the dot, from the same N# owner that answers
    /// `nlc query completions`.
    /// </summary>
    private List<CompletionItem> GetMemberCompletionItems(string uri, Models.DocumentState doc, int line, int character)
    {
        try
        {
            var result = ResolveMemberCompletions(uri, doc, line, character);
            if (result == null || result.Context != CodeIntel.CompletionContext.MemberAccess)
            {
                return new List<CompletionItem>();
            }

            return BuildMemberCompletionItems(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting member completion items");
            return new List<CompletionItem>();
        }
    }

    /// <summary>
    /// The project snapshot answers when the buffer is backed by one — the same snapshot, and so
    /// the same analyzer type universe, that definition, references and hover already use. A loose
    /// buffer outside any project falls back to the open documents' own models, which is the tier
    /// that types a receiver declared in the file being edited.
    /// </summary>
    private CodeIntel.CompletionResult? ResolveMemberCompletions(string uri, Models.DocumentState doc, int line, int character)
    {
        if (_documentManager.TryGetSynchronizedProjectSnapshot(uri, out _, out var filePath, out var snapshot))
        {
            return _completionEngine.GetCompletions(snapshot, filePath, line + 1, character + 1, includeKeywords: false);
        }

        if (doc.CompilationUnit == null)
        {
            return null;
        }

        var documents = _documentManager.GetAllDocuments().ToList();
        return CodeIntel.CompletionReceiverFacts.GetMemberAccessCompletions(
            doc.CompilationUnit, doc.SemanticModel, null, line + 1, character + 1,
            documents.Select(state => state.SemanticModel).OfType<SemanticModel>().ToList(),
            documents.Select(state => state.CompilationUnit).OfType<CompilationUnit>().ToList());
    }

    /// <summary>
    /// The owner's grouped answer as LSP items, in the owner's own order — one row per member name,
    /// flattened and ordered by the same N# owner the CLI and the playground ask.
    /// </summary>
    private static List<CompletionItem> BuildMemberCompletionItems(CodeIntel.CompletionResult result)
    {
        var items = new List<CompletionItem>();
        foreach (var member in CodeIntel.CompletionEngineKernels.FlattenCompletionGroups(result.Completions))
        {
            items.Add(new CompletionItem
            {
                Label = member.Name,
                Kind = (CompletionItemKind)CodeIntel.EditorCompletionFacts.LspCompletionItemKind(member.Kind),
                Detail = CodeIntel.EditorCompletionFacts.MemberDetailText(member),
                InsertText = member.Name,
                SortText = CodeIntel.EditorCompletionFacts.MemberSortText(items.Count)
            });
        }

        return items;
    }

    private static void AddLanguageCompletionItems(List<CompletionItem> items, HashSet<string> itemKeys)
    {
        foreach (var row in CodeIntel.EditorCompletionMenuFacts.LanguageRows())
        {
            AddUniqueCompletionItem(items, itemKeys, ToCompletionItem(row), row.Key);
        }
    }

    private static void AddDocumentSymbolCompletionItems(
        Models.DocumentState? doc,
        List<CompletionItem> items,
        HashSet<string> itemKeys,
        HashSet<string> inScopeNames)
    {
        if (doc?.CompilationUnit == null)
        {
            return;
        }

        foreach (var row in CodeIntel.EditorCompletionMenuFacts.DocumentSymbolRows(doc.CompilationUnit, doc.Text))
        {
            AddInScopeCompletionItem(items, itemKeys, inScopeNames, row.Label, ToCompletionItem(row));
        }
    }

    private static CompletionItem ToCompletionItem(CodeIntel.EditorCompletionMenuRow row)
    {
        return new CompletionItem
        {
            Label = row.Label,
            Kind = (CompletionItemKind)row.Kind,
            Detail = row.Detail,
            InsertText = row.InsertText,
            // Only a snippet declares a format; anything else leaves the field off the wire, which
            // is what the client reads as plain text and what this server has always sent.
            InsertTextFormat = row.IsSnippet ? InsertTextFormat.Snippet : default,
            Documentation = row.Documentation,
            SortText = row.SortText
        };
    }

    private void AddSemanticCompletionItems(
        Models.DocumentState? doc,
        int line,
        int character,
        List<CompletionItem> items,
        HashSet<string> itemKeys,
        HashSet<string> inScopeNames)
    {
        if (doc?.SemanticModel == null)
        {
            return;
        }

        var semanticModel = doc.SemanticModel;
        var visibleVariables = semanticModel.Scopes.Count > 0
            ? semanticModel.GetVisibleVariablesAtPosition(line + 1, character + 1)
            : new Dictionary<string, TypeInfo>(semanticModel.Variables);
        foreach (var (name, typeInfo) in semanticModel.Variables)
        {
            visibleVariables.TryAdd(name, typeInfo);
        }

        foreach (var (name, typeInfo) in visibleVariables)
        {
            if (semanticModel.Functions.ContainsKey(name))
            {
                continue;
            }

            AddInScopeCompletionItem(items, itemKeys, inScopeNames, name, new CompletionItem
            {
                Label = name,
                Kind = CompletionItemKind.Variable,
                Detail = $"variable: {typeInfo}",
                InsertText = name,
                SortText = CodeIntel.EditorCompletionMenuFacts.SortText(
                    CodeIntel.EditorCompletionMenuFacts.SortLocal, name, "variable")
            });
        }

        var memberNames = new HashSet<string>(
            CodeIntel.EditorCompletionMenuFacts.TypeMemberNames(doc.CompilationUnit, doc.Text),
            StringComparer.Ordinal);
        foreach (var (name, typeInfo) in semanticModel.Functions)
        {
            if (memberNames.Contains(name))
            {
                continue;
            }

            AddInScopeCompletionItem(items, itemKeys, inScopeNames, name, new CompletionItem
            {
                Label = name,
                Kind = CompletionItemKind.Function,
                Detail = $"func: {typeInfo}",
                InsertText = name,
                SortText = CodeIntel.EditorCompletionMenuFacts.SortText(
                    CodeIntel.EditorCompletionMenuFacts.SortLocal, name, "function")
            });
        }
    }

    private void AddExternalImportableCompletionItems(
        Models.DocumentState? doc,
        string currentPrefix,
        Position position,
        List<CompletionItem> items,
        HashSet<string> itemKeys,
        HashSet<string> inScopeNames)
    {
        var planner = new ImportEditPlanner(doc?.CompilationUnit, doc?.Text ?? "");
        foreach (var type in _typeResolver.GetImportableTypes(currentPrefix))
        {
            var isInScope = ImportEditPlanner.IsNamespaceInScope(doc?.CompilationUnit, type.Namespace);
            var edits = planner.CompletionEdits(type.Namespace, type.Name, position.Line + 1, position.Character).Select(edit => new OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit
            {
                Range = new LspRange(edit.StartLine - 1, edit.StartColumn, edit.EndLine - 1, edit.EndColumn),
                NewText = edit.NewText
            }).ToArray();
            var item = new CompletionItem
            {
                Label = type.Name,
                Kind = type.IsInterface ? CompletionItemKind.Interface
                    : type.IsEnum ? CompletionItemKind.Enum
                    : CompletionItemKind.Class,
                Detail = isInScope ? type.FullName : $"{type.FullName} (auto-import {type.Namespace})",
                InsertText = type.Name,
                TextEdit = new TextEditOrInsertReplaceEdit(edits[0]),
                AdditionalTextEdits = new TextEditContainer(edits.Skip(1)),
                SortText = CodeIntel.EditorCompletionMenuFacts.ExternalSortText(isInScope, type.Name, type.Namespace),
            };

            if (isInScope)
            {
                AddInScopeCompletionItem(items, itemKeys, inScopeNames, type.Name, item);
                continue;
            }

            if (inScopeNames.Contains(type.Name))
            {
                continue;
            }

            AddUniqueCompletionItem(items, itemKeys, item, $"external-import:{type.Name}");
        }
    }

    private static void AddInScopeCompletionItem(
        List<CompletionItem> items,
        HashSet<string> itemKeys,
        HashSet<string> inScopeNames,
        string name,
        CompletionItem item)
    {
        if (!inScopeNames.Add(name))
        {
            return;
        }

        AddUniqueCompletionItem(items, itemKeys, item, $"scope:{name}");
    }

    private static void AddUniqueCompletionItem(
        List<CompletionItem> items,
        HashSet<string> itemKeys,
        CompletionItem item,
        string key)
    {
        if (itemKeys.Add(key))
        {
            items.Add(item);
        }
    }

    public override Task<CompletionItem> Handle(CompletionItem request, CancellationToken cancellationToken)
    {
        // We don't provide resolve capabilities, so just return the item as-is
        return Task.FromResult(request);
    }

    protected override CompletionRegistrationOptions CreateRegistrationOptions(
        CompletionCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new CompletionRegistrationOptions
        {
            DocumentSelector = new TextDocumentSelector(
                new TextDocumentFilter { Language = "nsharp" }
            ),
            ResolveProvider = false,
            TriggerCharacters = new Container<string>(".", ":", " ")
        };
    }

}
