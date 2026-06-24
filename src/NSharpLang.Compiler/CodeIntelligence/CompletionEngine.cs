using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Completion context types — what kind of completion is being requested.
/// </summary>
public enum CompletionContext
{
    MemberAccess,   // After a dot: Console.|
    Identifier,     // Typing an identifier: Con|
    Namespace,      // After a namespace dot: System.|
    Unknown
}

/// <summary>
/// A single completion item with LLM-friendly metadata.
/// </summary>
public record CompletionItem(
    string Name,
    string Kind,        // "method", "property", "field", "variable", "function", "class", "keyword", etc.
    string? Type,       // Return type or value type
    string? Parameters, // For methods/functions: "(string value, int count)"
    string? Documentation,
    bool IsStatic);

/// <summary>
/// Result of a completion request, grouped by category for LLM consumption.
/// </summary>
public record CompletionResult(
    CompletionContext Context,
    string? Receiver,       // For member_access: "Console", "myVar"
    string? ReceiverType,   // For member_access: "System.Console", "string"
    Dictionary<string, List<CompletionItem>> Completions);  // Grouped: "methods", "properties", "variables", etc.

/// <summary>
/// Shared completion engine for both CLI and (eventually) LSP.
/// Provides LLM-optimized completions grouped by category.
/// </summary>
public class CompletionEngine
{
    private static readonly string[] NSharpKeywords = {
        "func", "class", "struct", "record", "interface", "enum", "union",
        "if", "else", "for", "foreach", "while", "return", "break",
        "continue", "match", "switch", "case", "when", "yield", "await", "async",
        "throw", "try", "catch", "finally", "lock", "must", "new", "this", "base",
        "import", "namespace", "print", "test", "assert",
        "true", "false", "null", "is", "as", "typeof", "nameof"
    };

    private static readonly string[] Modifiers = {
        "pub", "static", "virtual", "override", "abstract", "sealed",
        "partial", "readonly", "const", "required", "init", "async"
    };

    private static readonly string[] PrimitiveTypes = {
        "int", "long", "float", "double", "bool", "string", "void", "object",
        "byte", "short", "char", "decimal", "uint", "ulong", "ushort", "sbyte"
    };

    /// <summary>
    /// Get completions at a position in a project.
    /// By default, identifier completions exclude keywords/primitives/modifiers (LLMs don't need them).
    /// Set includeKeywords=true to include them (for human/IDE use).
    /// </summary>
    public CompletionResult GetCompletions(ProjectSnapshot snapshot, string file, int line, int col, bool includeKeywords = false)
    {
        var (filePath, cu) = FindCompilationUnit(snapshot, file);
        if (cu == null)
        {
            return EmptyResult(CompletionContext.Unknown);
        }

        snapshot.SemanticModels.TryGetValue(filePath, out var semanticModel);

        // Try to determine context from source text
        string? sourceText = null;
        if (!snapshot.SourceTexts.TryGetValue(filePath, out sourceText))
        {
            sourceText = File.ReadAllText(filePath);
        }

        if (sourceText == null)
        {
            return EmptyResult(CompletionContext.Unknown);
        }

        if (!TryExtractCompletionPrefix(snapshot, filePath, sourceText, line, col, out var beforeCursor))
        {
            return EmptyResult(CompletionContext.Unknown);
        }

        var completionReceiver = CompletionEngineKernels.ClassifyCompletionReceiver(beforeCursor);
        if (completionReceiver.IsMemberAccess)
        {
            return GetMemberAccessCompletions(
                cu,
                semanticModel,
                completionReceiver.Receiver,
                line,
                col,
                snapshot);
        }

        // General identifier context
        return GetIdentifierCompletions(cu, semanticModel, beforeCursor, snapshot, includeKeywords, line, col);
    }

    // ── Member Access Completions ───────────────────────────────────────

    private static bool TryExtractCompletionPrefix(
        ProjectSnapshot snapshot,
        string filePath,
        string sourceText,
        int line,
        int col,
        [NotNullWhen(true)] out string? beforeCursor)
    {
        if (!CodeIntelligenceSourceTextKernels.TryExtractCompletionPrefix(
                snapshot,
                filePath,
                sourceText,
                line,
                col,
                out var dogfoodPrefix))
            throw new InvalidOperationException("N# completion prefix kernel rejected the source.");

        beforeCursor = dogfoodPrefix;
        return beforeCursor != null;
    }

    private CompletionResult GetMemberAccessCompletions(
        CompilationUnit cu,
        SemanticModel? semanticModel,
        string? precomputedReceiver,
        int line,
        int col,
        ProjectSnapshot snapshot)
    {
        var memberAccess = FindMemberAccessAtPosition(cu, line, col);
        var receiver = precomputedReceiver ?? FormatReceiverExpression(memberAccess?.Object);

        var completions = new Dictionary<string, List<CompletionItem>>();

        // Source-defined types win over CLR types with the same simple name.
        // This matters for playground samples that define ordinary names like
        // Console while still keeping System.Console available when no local type
        // owns the name.
        if (receiver != null && IsStaticAccess(receiver, semanticModel) && ResolveSourceTypeByName(receiver, snapshot) is { } sourceTypeInfo)
        {
            var memberResult = ResolveMemberCompletionsFromTypeInfo(
                sourceTypeInfo,
                receiver,
                snapshot,
                completions,
                MemberFilter.StaticOnly);
            if (memberResult != null) return memberResult;
        }

        // Resolve the full receiver expression semantically. This is the path for chains
        // such as message.ToUpper().| or factory.Create().| where the receiver is not a
        // plain identifier and must come from Analyzer-recorded expression types.
        if (semanticModel != null && memberAccess != null)
        {
            var resolver = new ExpressionTypeResolver(semanticModel);
            var receiverType = resolver.ResolveExpressionTypeInfo(memberAccess.Object);
            if (receiverType != null && !BuiltInTypes.IsUnknown(receiverType))
            {
                var displayReceiver = receiver ?? FormatReceiverExpression(memberAccess.Object) ?? "<expression>";
                var memberResult = ResolveMemberCompletionsFromTypeInfo(
                    receiverType,
                    displayReceiver,
                    snapshot,
                    completions,
                    MemberFilter.InstanceOnly);
                if (memberResult != null) return memberResult;
            }
        }

        if (receiver == null)
        {
            return EmptyResult(CompletionContext.MemberAccess);
        }

        // Try to resolve receiver as a variable from semantic model (position-aware, then flat)
        if (semanticModel != null)
        {
            var typeInfo = LookupIdentifierAtPosition(semanticModel, receiver, line, col)
                          ?? semanticModel.LookupIdentifier(receiver);
            if (typeInfo != null)
            {
                var memberResult = ResolveMemberCompletionsFromTypeInfo(
                    typeInfo,
                    receiver,
                    snapshot,
                    completions,
                    MemberFilter.InstanceOnly);
                if (memberResult != null) return memberResult;
            }
        }

        return EmptyResult(CompletionContext.MemberAccess);
    }

    private static TypeInfo? LookupIdentifierAtPosition(SemanticModel semanticModel, string name, int line, int column)
    {
        return semanticModel.LookupIdentifierAtPosition(name, line, column);
    }

    // ── General Identifier Completions ──────────────────────────────────

    private CompletionResult GetIdentifierCompletions(CompilationUnit cu, SemanticModel? semanticModel,
        string beforeCursor, ProjectSnapshot snapshot, bool includeKeywords = false, int line = 0, int col = 0)
    {
        var completions = new Dictionary<string, List<CompletionItem>>();

        // Variables and parameters from semantic model (position-aware when possible)
        if (semanticModel != null)
        {
            Dictionary<string, TypeInfo> visibleVars;
            if (line > 0 && semanticModel.Scopes.Count > 0)
            {
                visibleVars = semanticModel.GetVisibleVariablesAtPosition(line, col);
            }
            else
            {
                visibleVars = new Dictionary<string, TypeInfo>(semanticModel.Variables);
            }

            var variables = new List<CompletionItem>();
            foreach (var (name, typeInfo) in visibleVars)
            {
                if (semanticModel.Functions.ContainsKey(name)) continue; // shown as functions
                variables.Add(new CompletionItem(name, "variable", FormatTypeInfo(typeInfo), null, null, false));
            }
            if (variables.Count > 0)
                completions["variables"] = variables;

            var functions = new List<CompletionItem>();
            foreach (var (name, typeInfo) in semanticModel.Functions)
            {
                var paramStr = typeInfo is FunctionTypeInfo funcType && funcType.Declaration != null
                    ? FormatParameters(funcType.Declaration.Parameters)
                    : null;
                functions.Add(new CompletionItem(name, "function", FormatTypeInfo(typeInfo), paramStr, null, false));
            }
            if (functions.Count > 0)
                completions["functions"] = functions;
        }

        // Types from declarations
        var types = new List<CompletionItem>();
        foreach (var decl in cu.Declarations)
        {
            var item = DeclarationToCompletionItem(decl);
            if (item != null)
                types.Add(item);
        }
        if (types.Count > 0)
            completions["types"] = types;

        // Keywords, primitive types, and modifiers are omitted by default for LLM use.
        // LLMs already know these — including them wastes tokens.
        if (includeKeywords)
        {
            completions["keywords"] = NSharpKeywords.Select(k =>
                new CompletionItem(k, "keyword", null, null, null, false)).ToList();
            completions["primitiveTypes"] = PrimitiveTypes.Select(t =>
                new CompletionItem(t, "type", null, null, null, false)).ToList();
            completions["modifiers"] = Modifiers.Select(m =>
                new CompletionItem(m, "modifier", null, null, null, false)).ToList();
        }

        return new CompletionResult(CompletionContext.Identifier, null, null, completions);
    }

    private CompletionResult? ResolveMemberCompletionsFromTypeInfo(
        TypeInfo typeInfo,
        string receiver,
        ProjectSnapshot snapshot,
        Dictionary<string, List<CompletionItem>> completions,
        MemberFilter filter)
    {
        var typeName = FormatTypeInfo(typeInfo);

        // Prefer source-defined N# members over CLR types with the same simple name.
        // The Language Server already follows this rule; the shared playground/CLI
        // engine needs the same behavior so `Person.` does not accidentally bind to
        // an unrelated loaded CLR type named Person.
        var nsharpMembers = GetNSharpTypeMembers(typeInfo, snapshot, filter);
        if (nsharpMembers.Count > 0)
        {
            AddGroupedCompletionsByKind(nsharpMembers, completions);
            return new CompletionResult(CompletionContext.MemberAccess, receiver, typeName, completions);
        }

        return null;
    }

    /// <summary>
    /// Convert a TypeReference (AST) to a TypeInfo (semantic) for completion resolution.
    /// </summary>
    private static TypeInfo ResolveTypeReferenceToTypeInfo(TypeReference typeRef, ProjectSnapshot snapshot)
    {
        return typeRef switch
        {
            SimpleTypeReference s => new SimpleTypeInfo(s.Name),
            GenericTypeReference g => new GenericTypeInfo(g.Name,
                g.TypeArguments.Select(a => ResolveTypeReferenceToTypeInfo(a, snapshot)).ToList()),
            ArrayTypeReference a => new ArrayTypeInfo(ResolveTypeReferenceToTypeInfo(a.ElementType, snapshot)),
            NullableTypeReference n => new NullableTypeInfo(ResolveTypeReferenceToTypeInfo(n.InnerType, snapshot)),
            UnionTypeReference u => new UnionTypeInfo(FlattenUnionTypeReference(u).Select(a => ResolveTypeReferenceToTypeInfo(a, snapshot)).ToList()),
            _ => new SimpleTypeInfo("unknown")
        };
    }

    private static IEnumerable<TypeReference> FlattenUnionTypeReference(TypeReference typeRef)
    {
        if (typeRef is UnionTypeReference union)
        {
            foreach (var arm in union.Arms)
            {
                foreach (var nested in FlattenUnionTypeReference(arm))
                    yield return nested;
            }
        }
        else
        {
            yield return typeRef;
        }
    }

    private static MemberAccessExpression? FindMemberAccessAtPosition(CompilationUnit cu, int line, int col)
    {
        foreach (var candidateColumn in GetNearbyColumns(col, maxDistance: 3))
        {
            var expr = AstNodeFinder.FindExpressionAtPosition(cu, line - 1, candidateColumn - 1)
                ?? AstNodeFinder.FindExpressionAtPosition(cu, line, candidateColumn);

            if (expr is MemberAccessExpression memberAccess)
                return memberAccess;

            if (expr is CallExpression { Callee: MemberAccessExpression callMemberAccess })
                return callMemberAccess;
        }

        return null;
    }

    private static IEnumerable<int> GetNearbyColumns(int col, int maxDistance)
    {
        if (col > 0)
            yield return col;

        for (var distance = 1; distance <= maxDistance; distance++)
        {
            if (col - distance > 0)
                yield return col - distance;
            yield return col + distance;
        }
    }

    private static string? FormatReceiverExpression(Expression? expression)
    {
        return expression switch
        {
            IdentifierExpression id => id.Name,
            MemberAccessExpression memberAccess => FormatMemberAccessReceiver(memberAccess),
            CallExpression call => FormatReceiverExpression(call.Callee) is { } callee ? $"{callee}()" : null,
            ParenthesizedExpression paren => FormatReceiverExpression(paren.Inner),
            StringLiteralExpression literal => literal.Value,
            InterpolatedStringExpression interpolated => FormatInterpolatedStringReceiver(interpolated),
            CharLiteralExpression literal => literal.Value,
            IntLiteralExpression literal => literal.Value,
            FloatLiteralExpression literal => literal.Value,
            BoolLiteralExpression literal => literal.Value ? "true" : "false",
            NullLiteralExpression => "null",
            ThisExpression => "this",
            BaseExpression => "base",
            _ => null
        };
    }

    private static string FormatInterpolatedStringReceiver(InterpolatedStringExpression expression)
    {
        var text = string.Concat(expression.Parts.Select(part => part switch
        {
            InterpolatedStringText literal => literal.Text,
            InterpolatedStringHole => "{...}",
            _ => string.Empty
        }));

        return expression.IsRaw ? $"$\"\"\"{text}\"\"\"" : $"$\"{text}\"";
    }

    private static string? FormatMemberAccessReceiver(MemberAccessExpression memberAccess)
    {
        var receiver = FormatReceiverExpression(memberAccess.Object);
        if (receiver == null || string.IsNullOrEmpty(memberAccess.MemberName) || memberAccess.MemberName == "<error>")
            return receiver;

        return $"{receiver}.{memberAccess.MemberName}";
    }

    // ── Type Member Resolution ──────────────────────────────────────────

    private enum MemberFilter { All, StaticOnly, InstanceOnly }
    private List<CompletionItem> GetNSharpTypeMembers(TypeInfo typeInfo, ProjectSnapshot snapshot, MemberFilter filter)
    {
        var items = new List<CompletionItem>();
        var declaration = ResolveNSharpTypeDeclaration(typeInfo, snapshot);
        List<Declaration>? members = declaration switch
        {
            ClassDeclaration c => c.Members,
            StructDeclaration s => s.Members,
            RecordDeclaration r => r.Members,
            InterfaceDeclaration i => i.Members,
            _ => null
        };

        if (members == null) return items;

        foreach (var member in members)
        {
            var item = DeclarationToCompletionItem(member, memberContext: true);
            if (item != null) items.Add(item);
        }

        return items;
    }

    private static TypeInfo? ResolveSourceTypeByName(string name, ProjectSnapshot snapshot)
        => ResolveNSharpTypeDeclaration(new SimpleTypeInfo(name), snapshot) switch
        {
            ClassDeclaration c => new ClassTypeInfo(c),
            StructDeclaration s => new StructTypeInfo(s),
            RecordDeclaration r => new RecordTypeInfo(r),
            InterfaceDeclaration i => new InterfaceTypeInfo(i),
            UnionDeclaration u => new UnionTypeInfo(u),
            EnumDeclaration e => new EnumTypeInfo(e),
            _ => null
        };

    private static Declaration? ResolveNSharpTypeDeclaration(TypeInfo typeInfo, ProjectSnapshot snapshot)
    {
        switch (typeInfo)
        {
            case ClassTypeInfo c:
                return c.Declaration;
            case StructTypeInfo s:
                return s.Declaration;
            case RecordTypeInfo r:
                return r.Declaration;
            case InterfaceTypeInfo i:
                return i.Declaration;
            case UnionTypeInfo u:
                return u.Declaration;
        }

        var typeName = FormatTypeInfo(typeInfo);
        var simpleName = typeName.Contains('.', StringComparison.Ordinal)
            ? typeName.Split('.').Last()
            : typeName;

        foreach (var declaration in snapshot.CompilationUnits.Values.SelectMany(unit => unit.Declarations))
        {
            var candidateName = declaration switch
            {
                ClassDeclaration c => c.Name,
                StructDeclaration s => s.Name,
                RecordDeclaration r => r.Name,
                InterfaceDeclaration i => i.Name,
                UnionDeclaration u => u.Name,
                EnumDeclaration e => e.Name,
                _ => null
            };

            if (candidateName == null)
            {
                continue;
            }

            if (string.Equals(candidateName, typeName, StringComparison.Ordinal) ||
                string.Equals(candidateName, simpleName, StringComparison.Ordinal) ||
                candidateName.EndsWith("." + simpleName, StringComparison.Ordinal))
            {
                return declaration;
            }
        }

        return null;
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private bool IsStaticAccess(string name, SemanticModel? semanticModel)
    {
        // If the name is exported and isn't a variable, it's likely a static type access
        if (VisibilityConventions.IsExportedIdentifier(name))
        {
            if (semanticModel != null)
            {
                var lookup = semanticModel.LookupIdentifier(name);
                if (lookup is ClassTypeInfo or StructTypeInfo or EnumTypeInfo)
                    return true;
                if (lookup != null)
                    return false; // It's a variable
            }
            return true; // Default: uppercase = type = static
        }
        return false;
    }

    private static CompletionItem? DeclarationToCompletionItem(Declaration decl, bool memberContext = false) => decl switch
    {
        FunctionDeclaration f => new CompletionItem(f.Name, memberContext ? "method" : "function",
            CodeIntelligenceService.FormatTypeReferencePublic(f.ReturnType),
            FormatParameters(f.Parameters), null, f.Modifiers.HasFlag(Ast.Modifiers.Static)),
        ClassDeclaration c => new CompletionItem(c.Name, "class", null, null, null, false),
        StructDeclaration s => new CompletionItem(s.Name, "struct", null, null, null, false),
        RecordDeclaration r => new CompletionItem(r.Name, "record", null, null, null, false),
        InterfaceDeclaration i => new CompletionItem(i.Name, "interface", null, null, null, false),
        EnumDeclaration e => new CompletionItem(e.Name, "enum", null, null, null, false),
        UnionDeclaration u => new CompletionItem(u.Name, "union", null, null, null, false),
        FieldDeclaration fd => new CompletionItem(fd.Name, "property",
            CodeIntelligenceService.FormatTypeReferencePublic(fd.Type), null, null, false),
        PropertyDeclaration pd => new CompletionItem(pd.Name, "property",
            CodeIntelligenceService.FormatTypeReferencePublic(pd.Type), null, null, false),
        _ => null
    };

    private static string FormatParameters(List<Parameter> parameters)
    {
        var parts = parameters.Select(p =>
        {
            var typeStr = CodeIntelligenceService.FormatTypeReferencePublic(p.Type);
            return p.DefaultValue != null ? $"{p.Name} {typeStr} = ..." : $"{p.Name} {typeStr}";
        });
        return $"({string.Join(", ", parts)})";
    }

    private static string FormatTypeInfo(TypeInfo typeInfo)
        => typeInfo is FunctionTypeInfo { Declaration.ReturnType: not null } function
            ? CodeIntelligenceService.FormatTypeReferencePublic(function.Declaration.ReturnType)
            : NullabilityMetadata.FormatTypeInfo(typeInfo);

    private (string filePath, CompilationUnit? cu) FindCompilationUnit(ProjectSnapshot snapshot, string file)
    {
        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            if (MatchesFilePath(filePath, file))
                return (filePath, cu);
        }
        var fullPath = Path.GetFullPath(Path.Combine(snapshot.ProjectRoot, file));
        if (snapshot.CompilationUnits.TryGetValue(fullPath, out var found))
            return (fullPath, found);
        return (file, null);
    }

    /// <summary>
    /// Matches a full file path against a query, respecting path segment boundaries.
    /// "Program.nl" matches "/project/Program.nl" but NOT "/project/OldProgram.nl".
    /// </summary>
    private static bool MatchesFilePath(string fullPath, string queryPath)
    {
        var normalizedFull = fullPath.Replace('\\', '/');
        var normalizedQuery = queryPath.Replace('\\', '/');

        if (normalizedFull.Equals(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            return true;

        if (!normalizedFull.EndsWith(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            return false;

        var charBefore = normalizedFull[normalizedFull.Length - normalizedQuery.Length - 1];
        return charBefore == '/';
    }

    private static void AddGroupedCompletionsByKind(
        List<CompletionItem> items,
        Dictionary<string, List<CompletionItem>> completions)
    {
        CompletionEngineKernels.AddGroupedCompletionItemsByKind(items, completions);
    }

    internal static string PluralizeCompletionKind(string kind) => kind switch
    {
        "property" => "properties",
        "class" => "classes",
        _ => kind + "s"
    };

    private static CompletionResult EmptyResult(CompletionContext context)
    {
        return new CompletionResult(context, null, null, new Dictionary<string, List<CompletionItem>>());
    }
}
