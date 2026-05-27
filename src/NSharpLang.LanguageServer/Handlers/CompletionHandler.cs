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
using LspTextEdit = OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles code completion (Ctrl+Space in VS Code)
/// </summary>
public class CompletionHandler : CompletionHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly TypeResolver _typeResolver;
    private readonly ILogger<CompletionHandler> _logger;

    // N# Keywords for completion
    private static readonly string[] Keywords = {
        "func", "class", "struct", "record", "interface", "enum", "union", "namespace",
        "using", "import", "if", "else", "for", "foreach", "while", "return", "break",
        "continue", "match", "switch", "case", "when", "yield", "await", "async",
        "throw", "try", "catch", "finally", "lock", "new", "this", "base", "static",
        "virtual", "override", "abstract", "sealed", "partial", "readonly", "const",
        "file", "duck", "public", "private", "internal", "protected", "required",
        "init", "let", "type", "out", "ref", "params", "true", "false",
        "null", "is", "as", "typeof", "nameof", "checked", "unchecked", "and",
        "or", "not", "with", "immutable", "print", "test", "assert", "implicit", "explicit",
        "setup", "teardown"
    };

    private static readonly string[] PrimitiveTypes = {
        "int", "long", "float", "double", "bool", "string", "void", "object",
        "byte", "short", "char", "decimal", "uint", "ulong", "ushort", "sbyte"
    };

    // Snippet completions for common N# constructs
    private static readonly (string Label, string Detail, string InsertText)[] Snippets = {
        ("func", "func declaration", "func ${1:name}(${2:params}): ${3:void} {\n\t$0\n}"),
        ("if", "if statement", "if ${1:condition} {\n\t$0\n}"),
        ("match", "match expression", "match ${1:value} {\n\t${2:pattern} => ${3:result},\n\t_ => ${0:default}\n}"),
        ("for", "for-in loop", "for ${1:item} in ${2:collection} {\n\t$0\n}"),
        ("type", "type alias", "type ${1:Name} = ${0:Type}"),
    };

    private const string SortLocal = "0000";
    private const string SortProjectInScope = "0100";
    private const string SortLanguage = "0500";
    private const string SortExternalInScope = "0600";
    private const string SortProjectImportable = "0800";
    private const string SortExternalImportable = "0900";

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
            || (doc?.Text != null && IsMemberCompletion(doc.Text, request.Position.Line, request.Position.Character));

        if (isMemberAccess && doc?.Text != null)
        {
            var memberItems = GetMemberCompletionItems(doc, request.Position.Line, request.Position.Character);
            if (memberItems.Any())
            {
                _logger.LogDebug("Providing {Count} member completion items for {Uri}", memberItems.Count, uri);
                return Task.FromResult(new CompletionList(memberItems));
            }
        }

        var itemKeys = new HashSet<string>(StringComparer.Ordinal);
        var inScopeNames = new HashSet<string>(StringComparer.Ordinal);
        var currentPrefix = doc?.Text != null
            ? GetCurrentIdentifierPrefix(doc.Text, request.Position.Line, request.Position.Character)
            : string.Empty;

        AddDocumentSymbolCompletionItems(doc, items, itemKeys, inScopeNames);
        AddSemanticCompletionItems(doc, request.Position.Line, request.Position.Character, items, itemKeys, inScopeNames);
        AddProjectSymbolCompletionItems(doc, currentPrefix, items, itemKeys, inScopeNames);
        AddLanguageCompletionItems(items, itemKeys);
        AddExternalImportableCompletionItems(doc, currentPrefix, items, itemKeys, inScopeNames);

        _logger.LogDebug("Providing {Count} completion items for {Uri}", items.Count, uri);

        return Task.FromResult(new CompletionList(items));
    }

    private List<CompletionItem> GetImportCompletionItems(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length)
        {
            return new List<CompletionItem>();
        }

        var lineText = lines[line];
        var beforeCursor = lineText.Substring(0, Math.Min(character, lineText.Length));
        if (!TryExtractImportPrefix(beforeCursor, out var importPrefix))
        {
            return new List<CompletionItem>();
        }

        return _typeResolver.GetNamespaceSuggestions(importPrefix)
            .Select(segment => new CompletionItem
            {
                Label = segment,
                Kind = CompletionItemKind.Module,
                Detail = string.IsNullOrWhiteSpace(importPrefix) || importPrefix.EndsWith(".", StringComparison.Ordinal)
                    ? $"namespace {(string.IsNullOrWhiteSpace(importPrefix) ? segment : importPrefix + segment)}"
                    : $"namespace {BuildCompletedImportPrefix(importPrefix, segment)}",
                InsertText = segment
            })
            .ToList();
    }

    /// <summary>
    /// Check if the completion is triggered after a dot (member access)
    /// </summary>
    private bool IsMemberCompletion(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return false;

        var lineText = lines[line];
        if (character == 0) return false;

        // Check if there's a dot before the cursor
        var beforeCursor = lineText.Substring(0, Math.Min(character, lineText.Length));
        return beforeCursor.TrimEnd().EndsWith(".");
    }

    /// <summary>
    /// Get member completion items for the expression before the dot.
    /// Uses AST-based expression type resolution (like HoverHandler) as the primary path,
    /// with text-based fallback for broken ASTs.
    /// </summary>
    private List<CompletionItem> GetMemberCompletionItems(Models.DocumentState doc, int line, int character)
    {
        var items = new List<CompletionItem>();

        try
        {
            // === PRIMARY PATH: AST-based resolution ===
            if (doc.CompilationUnit != null && doc.SemanticModel != null)
            {
                items = GetMemberCompletionViaAst(doc, line, character);
                if (items.Count > 0)
                {
                    _logger.LogDebug("AST-based completion returned {Count} items", items.Count);
                    return items;
                }
            }

            // === FALLBACK: text-based resolution ===
            items = GetMemberCompletionFallback(doc, line, character);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting member completion items");
        }

        return items;
    }

    /// <summary>
    /// AST-based member completion: find the MemberAccessExpression at cursor,
    /// resolve the Object expression's type, and return its members.
    /// </summary>
    private List<CompletionItem> GetMemberCompletionViaAst(Models.DocumentState doc, int line, int character)
    {
        // AstNodeFinder expects 0-based LSP coordinates as the target.
        // It internally converts 1-based node positions to 0-based for comparison.
        var expression = AstNodeFinder.FindExpressionAtPosition(
            doc.CompilationUnit!, line, character);

        if (expression is not MemberAccessExpression memberAccess)
        {
            _logger.LogDebug("No MemberAccessExpression found at ({Line}, {Col})", line, character);
            return new List<CompletionItem>();
        }

        _logger.LogDebug("Found MemberAccessExpression, resolving Object type for: {MemberName}",
            memberAccess.MemberName);

        // Prefer source-defined N# symbols over same-named CLR types already loaded in the test/app domain.
        // Reflection is only a fallback for framework/external types; otherwise a local `Person` can be
        // shadowed by an unrelated CLR `Person` and hide source members such as Age/Greet.
        if (memberAccess.Object is IdentifierExpression sourceId)
        {
            var sourceTypeInfo = doc.SemanticModel!.LookupIdentifier(sourceId.Name);
            if (sourceTypeInfo != null)
            {
                var nsharpMembers = GetNSharpTypeMembers(sourceTypeInfo, doc);
                if (nsharpMembers.Count > 0)
                {
                    _logger.LogDebug("Resolved '{Name}' as source N# type with {Count} members", sourceId.Name, nsharpMembers.Count);
                    return nsharpMembers;
                }
            }
        }

        var resolver = new ExpressionTypeResolver(doc.SemanticModel!);
        var objectTypeInfo = resolver.ResolveExpressionTypeInfo(memberAccess.Object);
        if (objectTypeInfo != null && !BuiltInTypes.IsUnknown(objectTypeInfo))
        {
            var nsharpMembers = GetNSharpTypeMembers(objectTypeInfo, doc);
            if (nsharpMembers.Count > 0)
            {
                _logger.LogDebug("Resolved chained receiver as N# type '{Type}' with {Count} members",
                    objectTypeInfo, nsharpMembers.Count);
                return nsharpMembers;
            }

            var clrType = ResolveClrType(objectTypeInfo);
            if (clrType != null)
            {
                var mode = IsStaticTypeAccess(memberAccess.Object, doc)
                    ? MemberAccessMode.StaticOnly
                    : MemberAccessMode.InstanceOnly;

                _logger.LogDebug("Resolved chained receiver as CLR type: {Type}, mode: {Mode}", clrType.FullName, mode);
                return MembersToCompletionItems(_typeResolver.GetMembers(clrType, mode), doc, clrType);
            }
        }

        // Try to resolve the type of the object expression (the part before the dot)
        var objectType = resolver.ResolveExpressionType(memberAccess.Object);

        if (objectType != null)
        {
            var mode = IsStaticTypeAccess(memberAccess.Object, doc)
                ? MemberAccessMode.StaticOnly
                : MemberAccessMode.InstanceOnly;

            _logger.LogDebug("Resolved to System.Type: {Type}, mode: {Mode}", objectType.FullName, mode);
            return MembersToCompletionItems(_typeResolver.GetMembers(objectType, mode), doc, objectType);
        }

        // ExpressionTypeResolver couldn't resolve — try LSP-layer fallbacks

        // Fallback 1: If Object is an identifier, try type/variable resolution FIRST (before namespace)
        // This ensures real symbols in scope take priority over namespace names (Codex review fix)
        if (memberAccess.Object is IdentifierExpression id)
        {
            // Try as .NET type name first (static access like Console.WriteLine)
            var resolvedType = _typeResolver.ResolveType(id.Name);
            if (resolvedType != null)
            {
                _logger.LogDebug("Resolved '{Name}' as static .NET type", id.Name);
                return MembersToCompletionItems(_typeResolver.GetMembers(resolvedType, MemberAccessMode.StaticOnly), doc, resolvedType);
            }

            // Try semantic model for variable type
            var typeInfo = doc.SemanticModel!.LookupIdentifier(id.Name);
            if (typeInfo != null)
            {
                // Try to resolve TypeInfo to System.Type
                var typeName = typeInfo.ToString();
                var clrType = _typeResolver.ResolveType(typeName);
                if (clrType != null)
                {
                    _logger.LogDebug("Resolved variable '{Name}' type '{TypeName}' to CLR type", id.Name, typeName);
                    return MembersToCompletionItems(_typeResolver.GetMembers(clrType, MemberAccessMode.InstanceOnly), doc, clrType);
                }

                // TypeInfo is a user-defined N# type — enumerate members from SymbolsInfo
                var nsharpMembers = GetNSharpTypeMembers(typeInfo, doc);
                if (nsharpMembers.Count > 0)
                {
                    _logger.LogDebug("Resolved '{Name}' as N# type with {Count} members", id.Name, nsharpMembers.Count);
                    return nsharpMembers;
                }
            }
        }

        // Fallback last: Namespace completion — only after symbol resolution failed
        // Gated with IsKnownNamespace to avoid expensive reflection scans (Codex review fix)
        {
            string? nsPrefix = null;
            if (memberAccess.Object is IdentifierExpression nsId)
                nsPrefix = nsId.Name;
            else
                nsPrefix = BuildNamespacePath(memberAccess);

            if (nsPrefix != null && _typeResolver.IsKnownNamespace(nsPrefix))
            {
                var nsItems = new List<CompletionItem>();
                foreach (var sub in GetSubNamespaces(nsPrefix))
                {
                    nsItems.Add(new CompletionItem
                    {
                        Label = sub,
                        Kind = CompletionItemKind.Module,
                        Detail = $"namespace {nsPrefix}.{sub}",
                        InsertText = sub
                    });
                }
                nsItems.AddRange(NamespaceTypesToCompletionItems(_typeResolver.GetTypesInNamespace(nsPrefix)));
                if (nsItems.Count > 0)
                {
                    _logger.LogDebug("Resolved '{Prefix}' as namespace with {Count} items", nsPrefix, nsItems.Count);
                    return nsItems;
                }
            }
        }

        _logger.LogDebug("Could not resolve type for member access");
        return new List<CompletionItem>();
    }

    /// <summary>
    /// Get members from a user-defined N# type (class, struct, record).
    /// Uses SemanticModel for resolved field/property types, SymbolsInfo for methods.
    /// </summary>
    private List<CompletionItem> GetNSharpTypeMembers(TypeInfo typeInfo, Models.DocumentState doc)
    {
        var items = new List<CompletionItem>();

        // Get the type name from the TypeInfo — handle all TypeInfo variants
        string? typeName = typeInfo switch
        {
            ClassTypeInfo c => c.Declaration.Name,
            StructTypeInfo s => s.Declaration.Name,
            RecordTypeInfo r => r.Declaration.Name,
            InterfaceTypeInfo i => i.Declaration.Name,
            UnionTypeInfo u => u.Declaration.Name,
            _ => typeInfo.ToString() // SimpleTypeInfo, etc. — ToString() returns the type name
        };

        // Build a lookup of resolved types from SemanticModel
        Dictionary<string, TypeInfo>? resolvedTypes = null;
        if (typeName != null && doc.SemanticModel != null)
        {
            resolvedTypes = doc.SemanticModel.GetTypeMembers(typeName);
        }

        // Use SymbolsInfo as the primary member list (has correct kinds for fields/properties/methods),
        // but enhance field/property details with resolved types from SemanticModel
        if (doc.SymbolsInfo != null && typeName != null &&
            doc.SymbolsInfo.TryGetValue(typeName, out var symbolInfo))
        {
            foreach (var member in symbolInfo.Members)
            {
                var detail = GetSymbolDetail(member);

                // Use resolved type from SemanticModel when available
                if (resolvedTypes != null && resolvedTypes.TryGetValue(member.Name, out var resolvedType))
                {
                    detail = resolvedType.ToString();
                }

                items.Add(new CompletionItem
                {
                    Label = member.Name,
                    Kind = GetCompletionItemKindFromSymbol(member.Kind),
                    Detail = detail,
                    InsertText = member.Name,
                    Documentation = !string.IsNullOrEmpty(member.Documentation)
                        ? new MarkupContent { Kind = MarkupKind.Markdown, Value = member.Documentation }
                        : null
                });
            }
        }
        else if (resolvedTypes != null)
        {
            // No SymbolsInfo available — use SemanticModel alone as fallback
            foreach (var (memberName, memberType) in resolvedTypes)
            {
                items.Add(new CompletionItem
                {
                    Label = memberName,
                    Kind = CompletionItemKind.Field,
                    Detail = memberType.ToString(),
                    InsertText = memberName
                });
            }
        }

        return items;
    }

    /// <summary>
    /// Determine if a member access is on a type (static) vs on a variable (instance)
    /// </summary>
    private bool IsStaticTypeAccess(Expression objectExpr, Models.DocumentState doc)
    {
        if (objectExpr is not IdentifierExpression id) return false;

        // If the identifier exists as a variable in the semantic model, it's instance access
        if (doc.SemanticModel?.LookupIdentifier(id.Name) != null) return false;

        // If the identifier resolves as a type name, it's static access
        return _typeResolver.ResolveType(id.Name) != null;
    }

    private Type? ResolveClrType(TypeInfo typeInfo)
    {
        return typeInfo switch
        {
            ReflectionTypeInfo reflection => reflection.Type,
            SimpleTypeInfo simple => _typeResolver.ResolveType(simple.Name),
            ArrayTypeInfo array => ResolveClrType(array.ElementType)?.MakeArrayType(),
            NullableTypeInfo nullable => ResolveNullableClrType(nullable.InnerType),
            GenericTypeInfo generic => _typeResolver.ResolveType(generic.Name)
                ?? _typeResolver.ResolveType(generic.ToString()),
            _ => _typeResolver.ResolveType(typeInfo.ToString())
        };
    }

    private Type? ResolveNullableClrType(TypeInfo innerType)
    {
        var clrInnerType = ResolveClrType(innerType);
        if (clrInnerType == null)
        {
            return null;
        }

        return clrInnerType.IsValueType
            ? typeof(Nullable<>).MakeGenericType(clrInnerType)
            : clrInnerType;
    }

    /// <summary>
    /// Convert MemberCompletionItems to LSP CompletionItems, optionally attaching auto-import edits
    /// when the resolved type's namespace isn't already imported.
    /// </summary>
    private List<CompletionItem> MembersToCompletionItems(
        List<MemberCompletionItem> members,
        Models.DocumentState? doc,
        Type? resolvedType)
    {
        TextEditContainer? autoImportEdits = null;
        if (resolvedType != null && doc != null)
        {
            var ns = _typeResolver.GetImportNamespace(resolvedType);
            if (ns != null)
            {
                autoImportEdits = BuildAutoImportEdits(doc, ns);
            }
        }

        return MembersToCompletionItems(members, autoImportEdits);
    }

    /// <summary>
    /// Convert MemberCompletionItems to LSP CompletionItems
    /// </summary>
    private static List<CompletionItem> MembersToCompletionItems(
        List<MemberCompletionItem> members,
        TextEditContainer? autoImportEdits = null)
    {
        return members.Select(member => new CompletionItem
        {
            Label = member.Name,
            Kind = member.Kind switch
            {
                MemberKind.Method => CompletionItemKind.Method,
                MemberKind.Property => CompletionItemKind.Property,
                MemberKind.Field => CompletionItemKind.Field,
                MemberKind.Event => CompletionItemKind.Event,
                _ => CompletionItemKind.Text
            },
            Detail = GetMemberCompletionDetail(member),
            InsertText = member.Name,
            Documentation = !string.IsNullOrEmpty(member.Documentation)
                ? new MarkupContent { Kind = MarkupKind.Markdown, Value = member.Documentation }
                : null,
            AdditionalTextEdits = autoImportEdits
        }).ToList();
    }

    private static string GetMemberCompletionDetail(MemberCompletionItem member)
    {
        var detail = member.Parameters != null
            ? $"{member.Name}({member.Parameters}): {member.Type}"
            : $"{member.Name}: {member.Type}";

        if (member.OverloadCount <= 1)
        {
            return detail;
        }

        var additionalOverloads = member.OverloadCount - 1;
        var overloadLabel = additionalOverloads == 1 ? "overload" : "overloads";
        return $"{detail} (+{additionalOverloads} {overloadLabel})";
    }

    /// <summary>
    /// Fallback: text-based member completion (used when AST is too broken)
    /// </summary>
    private List<CompletionItem> GetMemberCompletionFallback(Models.DocumentState doc, int line, int character)
    {
        var items = new List<CompletionItem>();
        var text = doc.Text;
        if (text == null) return items;

        var lines = text.Split('\n');
        if (line >= lines.Length) return items;

        var lineText = lines[line];
        if (character == 0) return items;

        var beforeCursor = lineText.Substring(0, Math.Min(character, lineText.Length)).TrimEnd();
        // Handle race condition: dot might not be in text yet (trigger char arrives before didChange)
        // In that case, the text before cursor IS the identifier (the dot was just typed but not in buffer)
        string beforeDot;
        if (beforeCursor.EndsWith("."))
            beforeDot = beforeCursor.Substring(0, beforeCursor.Length - 1).TrimEnd();
        else
            beforeDot = beforeCursor; // dot not in text yet — treat text before cursor as the identifier

        var identifier = ExtractIdentifier(beforeDot);
        if (string.IsNullOrEmpty(identifier)) return items;

        // Check for namespace completion first
        if (_typeResolver.IsKnownNamespace(identifier))
        {
            foreach (var sub in GetSubNamespaces(identifier))
                items.Add(new CompletionItem { Label = sub, Kind = CompletionItemKind.Module, Detail = $"namespace {identifier}.{sub}", InsertText = sub });
            items.AddRange(NamespaceTypesToCompletionItems(_typeResolver.GetTypesInNamespace(identifier)));
            if (items.Count > 0) return items;
        }

        // Try semantic model
        Type? type = null;
        TypeInfo? nsharpTypeInfo = doc.SemanticModel?.LookupIdentifier(identifier);
        if (nsharpTypeInfo != null)
        {
            var nsharpMembers = GetNSharpTypeMembers(nsharpTypeInfo, doc);
            if (nsharpMembers.Count > 0)
            {
                _logger.LogDebug("Fallback resolved '{Identifier}' as N# type with {Count} members", identifier, nsharpMembers.Count);
                return nsharpMembers;
            }

            type = _typeResolver.ResolveType(nsharpTypeInfo.ToString());
        }

        // Try as type name
        type ??= _typeResolver.ResolveType(identifier);

        if (type != null)
        {
            var mode = doc.SemanticModel?.LookupIdentifier(identifier) != null
                ? MemberAccessMode.InstanceOnly
                : MemberAccessMode.StaticOnly;
            return MembersToCompletionItems(_typeResolver.GetMembers(type, mode), doc, type);
        }

        return items;
    }

    /// <summary>
    /// Build a dotted namespace path from a chain of MemberAccessExpressions
    /// e.g., System.Collections.Generic → "System.Collections.Generic"
    /// </summary>
    private static string? BuildNamespacePath(MemberAccessExpression memberAccess)
    {
        var parts = new List<string>();
        if (!string.IsNullOrEmpty(memberAccess.MemberName) && memberAccess.MemberName != "<error>")
            parts.Add(memberAccess.MemberName);

        Expression current = memberAccess.Object;
        while (current is MemberAccessExpression inner)
        {
            if (!string.IsNullOrEmpty(inner.MemberName) && inner.MemberName != "<error>")
                parts.Insert(0, inner.MemberName);
            current = inner.Object;
        }

        if (current is IdentifierExpression rootId)
        {
            parts.Insert(0, rootId.Name);
            return string.Join(".", parts);
        }

        return null;
    }

    /// <summary>
    /// Get sub-namespace names under a prefix (e.g., "System" → ["Collections", "Threading", "Linq", ...])
    /// </summary>
    private List<string> GetSubNamespaces(string prefix)
    {
        var subNamespaces = new HashSet<string>();
        var dotPrefix = prefix + ".";

        // Check all known namespace prefixes
        foreach (var ns in new[] { "System", "System.Collections", "System.Collections.Generic",
            "System.Linq", "System.Text", "System.Threading", "System.Threading.Tasks",
            "System.IO", "System.Net", "System.Net.Http" })
        {
            if (ns.StartsWith(dotPrefix) && ns.Length > dotPrefix.Length)
            {
                var remainder = ns.Substring(dotPrefix.Length);
                var nextDot = remainder.IndexOf('.');
                subNamespaces.Add(nextDot >= 0 ? remainder.Substring(0, nextDot) : remainder);
            }
        }

        return subNamespaces.ToList();
    }

    /// <summary>
    /// Convert namespace types to CompletionItems
    /// </summary>
    private static List<CompletionItem> NamespaceTypesToCompletionItems(
        List<(string Name, string FullName, bool IsStatic, bool IsInterface, bool IsEnum)> types)
    {
        return types.Select(t => new CompletionItem
        {
            Label = t.Name,
            Kind = t.IsInterface ? CompletionItemKind.Interface
                : t.IsEnum ? CompletionItemKind.Enum
                : CompletionItemKind.Class,
            Detail = t.FullName,
            InsertText = t.Name
        }).ToList();
    }

    private void AddLanguageCompletionItems(List<CompletionItem> items, HashSet<string> itemKeys)
    {
        foreach (var keyword in Keywords)
        {
            AddUniqueCompletionItem(items, itemKeys, new CompletionItem
            {
                Label = keyword,
                Kind = CompletionItemKind.Keyword,
                Detail = "keyword",
                InsertText = keyword,
                SortText = BuildSortText(SortLanguage, keyword, "keyword")
            }, $"keyword:{keyword}");
        }

        foreach (var snippet in Snippets)
        {
            AddUniqueCompletionItem(items, itemKeys, new CompletionItem
            {
                Label = snippet.Label,
                Kind = CompletionItemKind.Snippet,
                Detail = snippet.Detail,
                InsertText = snippet.InsertText,
                InsertTextFormat = InsertTextFormat.Snippet,
                SortText = BuildSortText(SortLanguage, snippet.Label, "snippet")
            }, $"snippet:{snippet.Label}");
        }

        foreach (var primitive in PrimitiveTypes)
        {
            AddUniqueCompletionItem(items, itemKeys, new CompletionItem
            {
                Label = primitive,
                Kind = CompletionItemKind.Keyword,
                Detail = "primitive type",
                InsertText = primitive,
                SortText = BuildSortText(SortLanguage, primitive, "primitive")
            }, $"primitive:{primitive}");
        }
    }

    private void AddDocumentSymbolCompletionItems(
        Models.DocumentState? doc,
        List<CompletionItem> items,
        HashSet<string> itemKeys,
        HashSet<string> inScopeNames)
    {
        if (doc?.SymbolsInfo == null)
        {
            return;
        }

        foreach (var (name, symbolInfo) in doc.SymbolsInfo)
        {
            AddInScopeCompletionItem(items, itemKeys, inScopeNames, name, new CompletionItem
            {
                Label = name,
                Kind = GetCompletionItemKindFromSymbol(symbolInfo.Kind),
                Detail = GetSymbolDetail(symbolInfo),
                InsertText = name,
                Documentation = !string.IsNullOrEmpty(symbolInfo.Documentation) ? symbolInfo.Documentation : null,
                SortText = BuildSortText(SortLocal, name, "document")
            });
        }
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
                SortText = BuildSortText(SortLocal, name, "variable")
            });
        }

        var memberNames = GetTypeMemberNames(doc);
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
                SortText = BuildSortText(SortLocal, name, "function")
            });
        }
    }

    private void AddProjectSymbolCompletionItems(
        Models.DocumentState? doc,
        string currentPrefix,
        List<CompletionItem> items,
        HashSet<string> itemKeys,
        HashSet<string> inScopeNames)
    {
        if (doc?.CompilationUnit == null)
        {
            return;
        }

        var currentFilePath = _documentManager.GetFilePathForUri(doc.Uri);
        foreach (var symbol in _documentManager.GetProjectSymbolsForCompletion(doc.Uri)
                     .OrderBy(symbol => symbol.Name, StringComparer.Ordinal)
                     .ThenBy(symbol => symbol.Namespace ?? string.Empty, StringComparer.Ordinal)
                     .ThenBy(symbol => symbol.SourceFile, StringComparer.OrdinalIgnoreCase))
        {
            if (!NameMatchesPrefix(symbol.Name, currentPrefix))
            {
                continue;
            }

            if (string.Equals(symbol.SourceFile, currentFilePath, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var isInScope = IsProjectSymbolInScope(doc, symbol);
            if (!isInScope && !symbol.IsExported)
            {
                continue;
            }

            if (!isInScope && string.IsNullOrWhiteSpace(symbol.Namespace))
            {
                continue;
            }

            var detail = FormatProjectSymbolDetail(symbol, isInScope);
            var item = new CompletionItem
            {
                Label = symbol.Name,
                Kind = GetCompletionItemKind(symbol),
                Detail = detail,
                InsertText = symbol.Name,
                SortText = BuildSortText(isInScope ? SortProjectInScope : SortProjectImportable, symbol.Name, symbol.Namespace ?? symbol.SourceFile),
                AdditionalTextEdits = isInScope || symbol.Namespace == null
                    ? null
                    : BuildAutoImportEdits(doc, symbol.Namespace)
            };

            if (isInScope)
            {
                AddInScopeCompletionItem(items, itemKeys, inScopeNames, symbol.Name, item);
                continue;
            }

            if (inScopeNames.Contains(symbol.Name))
            {
                continue;
            }

            AddUniqueCompletionItem(items, itemKeys, item,
                $"project-import:{symbol.Name}:{symbol.Namespace}:{symbol.SourceFile}");
        }
    }

    private void AddExternalImportableCompletionItems(
        Models.DocumentState? doc,
        string currentPrefix,
        List<CompletionItem> items,
        HashSet<string> itemKeys,
        HashSet<string> inScopeNames)
    {
        foreach (var type in _typeResolver.GetImportableTypes(currentPrefix))
        {
            var isInScope = IsNamespaceInScope(doc, type.Namespace);
            var item = new CompletionItem
            {
                Label = type.Name,
                Kind = type.IsInterface ? CompletionItemKind.Interface
                    : type.IsEnum ? CompletionItemKind.Enum
                    : CompletionItemKind.Class,
                Detail = isInScope ? type.FullName : $"{type.FullName} (auto-import {type.Namespace})",
                InsertText = type.Name,
                SortText = BuildSortText(isInScope ? SortExternalInScope : SortExternalImportable, type.Name, type.Namespace),
                AdditionalTextEdits = isInScope ? null : BuildAutoImportEdits(doc, type.Namespace)
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

    private static HashSet<string> GetTypeMemberNames(Models.DocumentState doc)
    {
        var memberNames = new HashSet<string>(StringComparer.Ordinal);
        if (doc.SymbolsInfo == null)
        {
            return memberNames;
        }

        foreach (var (_, symbol) in doc.SymbolsInfo)
        {
            if (symbol.Kind is LanguageServer.Models.SymbolKind.Class or LanguageServer.Models.SymbolKind.Struct
                or LanguageServer.Models.SymbolKind.Record or LanguageServer.Models.SymbolKind.Interface)
            {
                foreach (var member in symbol.Members)
                {
                    memberNames.Add(member.Name);
                }
            }
        }

        return memberNames;
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

    private static bool NameMatchesPrefix(string name, string prefix)
    {
        return string.IsNullOrEmpty(prefix)
            || name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
    }

    private static string BuildSortText(string rank, string label, string qualifier)
    {
        return $"{rank}_{label.ToLowerInvariant()}_{qualifier.ToLowerInvariant()}";
    }

    private static string GetCurrentIdentifierPrefix(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line < 0 || line >= lines.Length)
        {
            return string.Empty;
        }

        var lineText = lines[line];
        var end = Math.Clamp(character, 0, lineText.Length);
        var start = end;
        while (start > 0 && IsIdentifierPart(lineText[start - 1]))
        {
            start--;
        }

        return lineText[start..end];
    }

    private static bool IsIdentifierPart(char value)
    {
        return char.IsLetterOrDigit(value) || value == '_';
    }

    private static bool IsProjectSymbolInScope(Models.DocumentState doc, ProjectSymbolInfo symbol)
    {
        var compilationUnit = doc.CompilationUnit;
        if (compilationUnit == null)
        {
            return false;
        }

        var currentNamespace = GetUnitNamespace(compilationUnit);
        if (string.Equals(symbol.Namespace, currentNamespace, StringComparison.Ordinal))
        {
            return true;
        }

        return symbol.Namespace != null && IsNamespaceAlreadyImported(compilationUnit, symbol.Namespace);
    }

    private static bool IsNamespaceInScope(Models.DocumentState? doc, string namespaceName)
    {
        if (doc?.CompilationUnit == null)
        {
            return false;
        }

        if (string.Equals(GetUnitNamespace(doc.CompilationUnit), namespaceName, StringComparison.Ordinal))
        {
            return true;
        }

        return IsNamespaceAlreadyImported(doc.CompilationUnit, namespaceName);
    }

    private static string? GetUnitNamespace(CompilationUnit? compilationUnit)
    {
        return compilationUnit?.Package?.Name ?? compilationUnit?.Namespace?.Name;
    }

    private static string FormatProjectSymbolDetail(ProjectSymbolInfo symbol, bool isInScope)
    {
        var source = symbol.Namespace ?? "<global>";
        return isInScope
            ? $"{symbol.Declaration.Kind} from {source}"
            : $"{symbol.Declaration.Kind} from {source} (auto-import)";
    }

    private static TextEditContainer? BuildAutoImportEdits(Models.DocumentState? doc, string importNamespace)
    {
        if (doc == null || string.IsNullOrWhiteSpace(importNamespace))
        {
            return null;
        }

        // AST-based path: use CompilationUnit for accurate insertion
        if (doc.CompilationUnit != null)
        {
            if (IsNamespaceAlreadyImported(doc.CompilationUnit, importNamespace))
            {
                return null;
            }

            var insertLine = GetNamespaceImportInsertionLine(doc.CompilationUnit);
            var edit = new LspTextEdit
            {
                Range = new LspRange(insertLine - 1, 0, insertLine - 1, 0),
                NewText = $"import {importNamespace}\n"
            };

            return new TextEditContainer(new[] { edit });
        }

        // Text-based fallback: when the AST is broken (e.g., incomplete expression after dot),
        // scan the raw source to determine import insertion point
        if (doc.Text == null)
        {
            return null;
        }

        return BuildAutoImportEditsFromText(doc.Text, importNamespace);
    }

    /// <summary>
    /// Text-based fallback for auto-import when the CompilationUnit is null (broken AST).
    /// Scans source lines to find existing imports and determine insertion point.
    /// </summary>
    private static TextEditContainer? BuildAutoImportEditsFromText(string text, string importNamespace)
    {
        var lines = text.Split('\n');
        var importStatement = $"import {importNamespace}";

        // Check if already imported via text matching
        for (var i = 0; i < lines.Length; i++)
        {
            // Trim both ends to handle CRLF line endings (trailing \r) and leading whitespace
            var trimmed = lines[i].Trim();
            // Exact match: "import System" but not "import System.Collections"
            if (trimmed.Equals(importStatement, StringComparison.Ordinal))
            {
                return null;
            }
        }

        // Find the best insertion point: after the last import/namespace/package declaration
        var insertLineZeroBased = 0;
        for (var i = 0; i < lines.Length; i++)
        {
            var trimmed = lines[i].Trim();
            if (trimmed.StartsWith("import ", StringComparison.Ordinal)
                || trimmed.StartsWith("namespace ", StringComparison.Ordinal)
                || trimmed.StartsWith("package ", StringComparison.Ordinal))
            {
                insertLineZeroBased = i + 1;
            }
        }

        var importEdit = new LspTextEdit
        {
            Range = new LspRange(insertLineZeroBased, 0, insertLineZeroBased, 0),
            NewText = $"import {importNamespace}\n"
        };

        return new TextEditContainer(new[] { importEdit });
    }

    private static bool IsNamespaceAlreadyImported(CompilationUnit compilationUnit, string importNamespace)
    {
        return compilationUnit.Imports.Any(import =>
            import.Alias == null &&
            string.Equals(import.Namespace, importNamespace, StringComparison.Ordinal));
    }

    private static int GetNamespaceImportInsertionLine(CompilationUnit compilationUnit)
    {
        var insertLine = 1;

        if (compilationUnit.Package != null)
        {
            insertLine = Math.Max(insertLine, compilationUnit.Package.Line + 1);
        }

        if (compilationUnit.Namespace != null)
        {
            insertLine = Math.Max(insertLine, compilationUnit.Namespace.Line + 1);
        }

        if (compilationUnit.Imports.Count > 0)
        {
            insertLine = Math.Max(insertLine, compilationUnit.Imports[^1].Line + 1);
        }

        if (compilationUnit.FileImports.Count > 0)
        {
            insertLine = Math.Max(insertLine, compilationUnit.FileImports
                .OfType<FileImport>()
                .Select(fileImport => fileImport.Line)
                .DefaultIfEmpty(insertLine)
                .Max() + 1);
        }

        return insertLine;
    }

    private static string ExtractIdentifier(string text)
    {
        var parts = text.Split(new[] { ' ', '\t', '(', ')', '[', ']', '{', '}', ',', ';' }, StringSplitOptions.RemoveEmptyEntries);
        return parts.LastOrDefault() ?? "";
    }

    private static bool TryExtractImportPrefix(string beforeCursor, out string importPrefix)
    {
        importPrefix = string.Empty;

        var trimmed = beforeCursor.TrimStart();
        if (!trimmed.StartsWith("import", StringComparison.Ordinal))
        {
            return false;
        }

        var remainder = trimmed["import".Length..];
        if (remainder.Length == 0 || !char.IsWhiteSpace(remainder[0]))
        {
            return false;
        }

        var importTarget = remainder.TrimStart();
        if (importTarget.StartsWith("\"", StringComparison.Ordinal))
        {
            return false;
        }

        var aliasIndex = importTarget.IndexOf(" as ", StringComparison.Ordinal);
        if (aliasIndex >= 0)
        {
            importTarget = importTarget[..aliasIndex];
        }

        importPrefix = importTarget.Trim();
        return true;
    }

    private static string BuildCompletedImportPrefix(string importPrefix, string suggestion)
    {
        if (string.IsNullOrWhiteSpace(importPrefix))
        {
            return suggestion;
        }

        if (importPrefix.EndsWith(".", StringComparison.Ordinal))
        {
            return importPrefix + suggestion;
        }

        var lastDot = importPrefix.LastIndexOf('.');
        if (lastDot < 0)
        {
            return suggestion;
        }

        return importPrefix[..(lastDot + 1)] + suggestion;
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

    private CompletionItemKind GetCompletionItemKind(TypeInfo typeInfo)
    {
        return typeInfo switch
        {
            ClassTypeInfo => CompletionItemKind.Class,
            StructTypeInfo => CompletionItemKind.Struct,
            RecordTypeInfo => CompletionItemKind.Class,
            InterfaceTypeInfo => CompletionItemKind.Interface,
            EnumTypeInfo => CompletionItemKind.Enum,
            UnionTypeInfo => CompletionItemKind.Class,
            FunctionTypeInfo => CompletionItemKind.Function,
            _ => CompletionItemKind.Variable
        };
    }

    private CompletionItemKind GetCompletionItemKind(ProjectSymbolInfo symbol)
    {
        return symbol.Declaration.Kind switch
        {
            "class" => CompletionItemKind.Class,
            "struct" => CompletionItemKind.Struct,
            "record" => CompletionItemKind.Class,
            "interface" => CompletionItemKind.Interface,
            "enum" => CompletionItemKind.Enum,
            "union" => CompletionItemKind.Class,
            "function" => CompletionItemKind.Function,
            _ => GetCompletionItemKind(symbol.Type)
        };
    }

    private CompletionItemKind GetCompletionItemKindFromSymbol(LanguageServer.Models.SymbolKind kind)
    {
        return kind switch
        {
            LanguageServer.Models.SymbolKind.Class => CompletionItemKind.Class,
            LanguageServer.Models.SymbolKind.Struct => CompletionItemKind.Struct,
            LanguageServer.Models.SymbolKind.Record => CompletionItemKind.Class,
            LanguageServer.Models.SymbolKind.Interface => CompletionItemKind.Interface,
            LanguageServer.Models.SymbolKind.Enum => CompletionItemKind.Enum,
            LanguageServer.Models.SymbolKind.Union => CompletionItemKind.Class,
            LanguageServer.Models.SymbolKind.Function => CompletionItemKind.Function,
            LanguageServer.Models.SymbolKind.Method => CompletionItemKind.Method,
            LanguageServer.Models.SymbolKind.Property => CompletionItemKind.Property,
            LanguageServer.Models.SymbolKind.Field => CompletionItemKind.Field,
            LanguageServer.Models.SymbolKind.Parameter => CompletionItemKind.Variable,
            LanguageServer.Models.SymbolKind.LocalVariable => CompletionItemKind.Variable,
            LanguageServer.Models.SymbolKind.EnumMember => CompletionItemKind.EnumMember,
            LanguageServer.Models.SymbolKind.Constructor => CompletionItemKind.Constructor,
            _ => CompletionItemKind.Variable
        };
    }

    private string GetSymbolDetail(LanguageServer.Models.SymbolInfo symbol)
    {
        var parts = new List<string>();

        // Add modifiers
        var modifiers = new List<string>();
        if (symbol.Modifiers.HasFlag(Modifiers.Public)) modifiers.Add("public");
        if (symbol.Modifiers.HasFlag(Modifiers.Private)) modifiers.Add("private");
        if (symbol.Modifiers.HasFlag(Modifiers.Protected)) modifiers.Add("protected");
        if (symbol.Modifiers.HasFlag(Modifiers.Internal)) modifiers.Add("internal");
        if (symbol.Modifiers.HasFlag(Modifiers.Static)) modifiers.Add("static");
        if (symbol.Modifiers.HasFlag(Modifiers.Abstract)) modifiers.Add("abstract");
        if (symbol.Modifiers.HasFlag(Modifiers.Virtual)) modifiers.Add("virtual");
        if (symbol.Modifiers.HasFlag(Modifiers.Override)) modifiers.Add("override");
        if (symbol.Modifiers.HasFlag(Modifiers.Sealed)) modifiers.Add("sealed");
        if (symbol.Modifiers.HasFlag(Modifiers.Async)) modifiers.Add("async");

        if (modifiers.Any())
        {
            parts.Add(string.Join(" ", modifiers));
        }

        // Add kind
        parts.Add(symbol.Kind.ToString().ToLower());

        // Add name
        parts.Add(symbol.Name);

        // Add signature for functions/methods
        if (symbol.Kind == LanguageServer.Models.SymbolKind.Function ||
            symbol.Kind == LanguageServer.Models.SymbolKind.Method ||
            symbol.Kind == LanguageServer.Models.SymbolKind.Constructor)
        {
            var paramList = string.Join(", ", symbol.Parameters.Select(p => $"{p.Name}: {p.TypeName}"));
            parts.Add($"({paramList})");

            if (!string.IsNullOrEmpty(symbol.TypeName))
            {
                parts.Add($": {symbol.TypeName}");
            }
        }
        else if (!string.IsNullOrEmpty(symbol.TypeName))
        {
            parts.Add($": {symbol.TypeName}");
        }

        return string.Join(" ", parts);
    }
}
