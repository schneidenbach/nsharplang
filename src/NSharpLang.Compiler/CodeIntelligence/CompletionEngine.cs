using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;
using BindingFlags = System.Reflection.BindingFlags;

namespace NSharpLang.Compiler.CodeIntelligence;

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

        // Resolve the full receiver expression semantically. This is the path for chains
        // such as message.ToUpper().| or factory.Create().| where the receiver is not a
        // plain identifier and must come from Analyzer-recorded expression types.
        if (semanticModel != null && memberAccess != null)
        {
            var receiverType = semanticModel.LookupTypeAtPosition(memberAccess.Object.Line, memberAccess.Object.Column);
            if (receiverType != null && !BuiltInTypes.IsUnknown(receiverType))
            {
                var displayReceiver = receiver ?? FormatReceiverExpression(memberAccess.Object) ?? "<expression>";
                var memberResult = ResolveMemberCompletionsFromTypeInfo(
                    receiverType,
                    displayReceiver,
                    snapshot,
                    completions,
                    GetMemberFilter(displayReceiver, receiverType));
                if (memberResult != null) return memberResult;
            }
        }

        if (receiver == null)
        {
            return EmptyResult(CompletionContext.MemberAccess);
        }

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
                    GetMemberFilter(receiver, typeInfo));
                if (memberResult != null) return memberResult;
            }
        }

        var literalTypeInfo = ResolveLiteralReceiverType(receiver);
        if (literalTypeInfo != null)
        {
            var memberResult = ResolveMemberCompletionsFromTypeInfo(
                literalTypeInfo,
                receiver,
                snapshot,
                completions,
                MemberFilter.InstanceOnly);
            if (memberResult != null) return memberResult;
        }

        return EmptyResult(CompletionContext.MemberAccess);
    }

    private static TypeInfo? LookupIdentifierAtPosition(SemanticModel semanticModel, string name, int line, int column)
    {
        return semanticModel.LookupIdentifierAtPosition(name, line, column);
    }

    private static MemberFilter GetMemberFilter(string receiver, TypeInfo typeInfo)
    {
        return IsStaticTypeReceiver(receiver, typeInfo)
            ? MemberFilter.StaticOnly
            : MemberFilter.InstanceOnly;
    }

    private static bool IsStaticTypeReceiver(string receiver, TypeInfo typeInfo)
    {
        if (!VisibilityConventions.IsExportedIdentifier(receiver))
            return false;

        return typeInfo is ReflectionTypeInfo
            or ClassTypeInfo
            or StructTypeInfo
            or EnumTypeInfo
            or InterfaceTypeInfo;
    }

    private static TypeInfo? ResolveLiteralReceiverType(string receiver)
    {
        return IsStringLiteralReceiver(receiver)
            ? new SimpleTypeInfo("System.String")
            : null;
    }

    private static bool IsStringLiteralReceiver(string receiver)
    {
        var index = 0;
        while (index < receiver.Length && receiver[index] == '$')
            index++;

        return index < receiver.Length && receiver[index] == '"';
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
                variables.Add(new CompletionItem(name, "variable", CompletionTypeTextFacts.FormatTypeText(typeInfo), null, null, false));
            }
            if (variables.Count > 0)
                completions["variables"] = variables;

            var functions = new List<CompletionItem>();
            foreach (var (name, typeInfo) in semanticModel.Functions)
            {
                var paramStr = typeInfo is FunctionTypeInfo functionType
                    ? CompletionTypeTextFacts.FormatFunctionTypeParameters(functionType)
                    : null;
                functions.Add(new CompletionItem(name, "function", CompletionTypeTextFacts.FormatTypeText(typeInfo), paramStr, null, false));
            }
            if (functions.Count > 0)
                completions["functions"] = functions;
        }

        // Types from declarations
        var types = new List<CompletionItem>();
        foreach (var decl in cu.Declarations)
        {
            var item = CompletionDeclarationFacts.ToCompletionItem(decl);
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
        var typeName = CompletionTypeTextFacts.FormatTypeText(typeInfo);

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

        if (TryGetCompletionReflectionType(typeInfo, out var clrType))
        {
            var flags = BindingFlags.Public |
                (filter == MemberFilter.StaticOnly ? BindingFlags.Static :
                 filter == MemberFilter.InstanceOnly ? BindingFlags.Instance :
                 BindingFlags.Static | BindingFlags.Instance);
            var reflectionMembers = BuildReflectionMemberItems(clrType, flags);
            if (reflectionMembers.Count > 0)
            {
                AddGroupedCompletionsByKind(reflectionMembers, completions);
                return new CompletionResult(
                    CompletionContext.MemberAccess,
                    receiver,
                    clrType.FullName ?? clrType.Name,
                    completions);
            }
        }

        return null;
    }

    private static bool TryGetCompletionReflectionType(
        TypeInfo typeInfo,
        [NotNullWhen(true)] out Type? clrType)
    {
        if (typeInfo is ReflectionTypeInfo reflectionType)
        {
            clrType = reflectionType.Type;
            return true;
        }

        if (typeInfo is SimpleTypeInfo simpleType)
        {
            clrType = simpleType.Name switch
            {
                "string" or "System.String" => typeof(string),
                "int" or "System.Int32" => typeof(int),
                "long" or "System.Int64" => typeof(long),
                "bool" or "System.Boolean" => typeof(bool),
                "double" or "System.Double" => typeof(double),
                "float" or "System.Single" => typeof(float),
                "char" or "System.Char" => typeof(char),
                "object" or "System.Object" => typeof(object),
                "Console" or "System.Console" => typeof(Console),
                "Math" or "System.Math" => typeof(Math),
                "DateTime" or "System.DateTime" => typeof(DateTime),
                _ => null
            };
            return clrType != null;
        }

        if (typeInfo is GenericTypeInfo genericType)
        {
            var genericDefinition = genericType.Name switch
            {
                "List" or "System.Collections.Generic.List" => typeof(List<>),
                "IEnumerable" or "System.Collections.Generic.IEnumerable" => typeof(IEnumerable<>),
                "ICollection" or "System.Collections.Generic.ICollection" => typeof(ICollection<>),
                "IList" or "System.Collections.Generic.IList" => typeof(IList<>),
                "IReadOnlyCollection" or "System.Collections.Generic.IReadOnlyCollection" => typeof(IReadOnlyCollection<>),
                "IReadOnlyList" or "System.Collections.Generic.IReadOnlyList" => typeof(IReadOnlyList<>),
                "Dictionary" or "System.Collections.Generic.Dictionary" => typeof(Dictionary<,>),
                "IDictionary" or "System.Collections.Generic.IDictionary" => typeof(IDictionary<,>),
                "IReadOnlyDictionary" or "System.Collections.Generic.IReadOnlyDictionary" => typeof(IReadOnlyDictionary<,>),
                "HashSet" or "System.Collections.Generic.HashSet" => typeof(HashSet<>),
                "Queue" or "System.Collections.Generic.Queue" => typeof(Queue<>),
                "Stack" or "System.Collections.Generic.Stack" => typeof(Stack<>),
                "Nullable" or "System.Nullable" => typeof(Nullable<>),
                "Task" or "System.Threading.Tasks.Task" => typeof(System.Threading.Tasks.Task<>),
                "ValueTask" or "System.Threading.Tasks.ValueTask" => typeof(System.Threading.Tasks.ValueTask<>),
                _ => null
            };

            if (genericDefinition != null &&
                genericDefinition.GetGenericArguments().Length == genericType.TypeArguments.Count)
            {
                var genericArguments = genericType.TypeArguments
                    .Select(GetReflectionTypeArgumentOrObject)
                    .ToArray();
                clrType = genericDefinition.MakeGenericType(genericArguments);
                return true;
            }
        }

        clrType = null;
        return false;
    }

    private static Type GetReflectionTypeArgumentOrObject(TypeInfo typeInfo)
        => typeInfo switch
        {
            ReflectionTypeInfo reflectionType => reflectionType.Type,
            SimpleTypeInfo simpleType => simpleType.Name switch
            {
                "string" or "System.String" => typeof(string),
                "int" or "System.Int32" => typeof(int),
                "long" or "System.Int64" => typeof(long),
                "bool" or "System.Boolean" => typeof(bool),
                "double" or "System.Double" => typeof(double),
                "float" or "System.Single" => typeof(float),
                "char" or "System.Char" => typeof(char),
                "object" or "System.Object" => typeof(object),
                "decimal" or "System.Decimal" => typeof(decimal),
                "byte" or "System.Byte" => typeof(byte),
                "short" or "System.Int16" => typeof(short),
                "uint" or "System.UInt32" => typeof(uint),
                "ulong" or "System.UInt64" => typeof(ulong),
                "ushort" or "System.UInt16" => typeof(ushort),
                "sbyte" or "System.SByte" => typeof(sbyte),
                _ => typeof(object)
            },
            _ => typeof(object)
        };

    private static List<CompletionItem> BuildReflectionMemberItems(Type clrType, BindingFlags flags)
    {
        var methods = clrType.GetMethods(flags);
        var properties = clrType.GetProperties(flags);
        var fields = clrType.GetFields(flags);
        var count = methods.Length + properties.Length + fields.Length;
        var names = new string[count];
        var kinds = new string[count];
        var typeTexts = new string[count];
        var isStaticValues = new bool[count];
        var index = 0;

        foreach (var method in methods)
        {
            names[index] = method.Name;
            kinds[index] = "method";
            typeTexts[index] = CompletionTypeTextFacts.FormatClrTypeText(method.ReturnType);
            isStaticValues[index] = method.IsStatic;
            index++;
        }

        foreach (var property in properties)
        {
            if (property.DeclaringType?.FullName == "System.Object")
                continue;

            names[index] = property.Name;
            kinds[index] = "property";
            typeTexts[index] = CompletionTypeTextFacts.FormatClrTypeText(property.PropertyType);
            isStaticValues[index] = property.GetMethod?.IsStatic ?? false;
            index++;
        }

        foreach (var field in fields)
        {
            if (field.DeclaringType?.FullName == "System.Object")
                continue;

            names[index] = field.Name;
            kinds[index] = "field";
            typeTexts[index] = CompletionTypeTextFacts.FormatClrTypeText(field.FieldType);
            isStaticValues[index] = field.IsStatic;
            index++;
        }

        if (index != count)
        {
            Array.Resize(ref names, index);
            Array.Resize(ref kinds, index);
            Array.Resize(ref typeTexts, index);
            Array.Resize(ref isStaticValues, index);
        }

        return CompletionEngineKernels.BuildMemberItemsFromRows(names, kinds, typeTexts, isStaticValues);
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
            UnionTypeReference u => new AnonymousUnionTypeInfo(FlattenUnionTypeReference(u).Select(a => ResolveTypeReferenceToTypeInfo(a, snapshot)).ToList()),
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
        var members = ResolveNSharpDeclaredMembers(typeInfo, snapshot);

        if (members == null) return items;

        foreach (var member in members)
        {
            var item = CompletionDeclarationFacts.DeclaredMemberToCompletionItem(member, true);
            if (item != null) items.Add(item);
        }

        return items;
    }

    private static IReadOnlyList<DeclaredMemberInfo>? ResolveNSharpDeclaredMembers(TypeInfo typeInfo, ProjectSnapshot snapshot)
    {
        var directMembers = GetDeclaredMembers(typeInfo);
        if (directMembers != null)
            return directMembers;

        var typeName = CompletionTypeTextFacts.FormatTypeText(typeInfo);
        var simpleName = typeName.Contains('.', StringComparison.Ordinal)
            ? typeName.Split('.').Last()
            : typeName;

        foreach (var semanticModel in snapshot.SemanticModels.Values)
        {
            if (TryResolveSemanticType(semanticModel, typeName, simpleName, out var semanticType))
                return GetDeclaredMembers(semanticType);
        }

        return null;
    }

    private static bool TryResolveSemanticType(
        SemanticModel semanticModel,
        string typeName,
        string simpleName,
        [NotNullWhen(true)] out TypeInfo? typeInfo)
    {
        if (semanticModel.Types.TryGetValue(typeName, out typeInfo) ||
            semanticModel.Types.TryGetValue(simpleName, out typeInfo))
        {
            return true;
        }

        foreach (var (candidateName, candidateType) in semanticModel.Types)
        {
            if (string.Equals(candidateName, typeName, StringComparison.Ordinal) ||
                string.Equals(candidateName, simpleName, StringComparison.Ordinal) ||
                candidateName.EndsWith("." + simpleName, StringComparison.Ordinal))
            {
                typeInfo = candidateType;
                return true;
            }
        }

        typeInfo = null;
        return false;
    }

    private static IReadOnlyList<DeclaredMemberInfo>? GetDeclaredMembers(TypeInfo typeInfo) => typeInfo switch
    {
        ClassTypeInfo c => c.DeclaredMembers,
        StructTypeInfo s => s.DeclaredMembers,
        RecordTypeInfo r => r.DeclaredMembers,
        InterfaceTypeInfo i => i.DeclaredMembers,
        _ => null
    };

    // ── Helpers ──────────────────────────────────────────────────────────

    private (string filePath, CompilationUnit? cu) FindCompilationUnit(ProjectSnapshot snapshot, string file)
    {
        foreach (var (filePath, cu) in snapshot.CompilationUnits)
        {
            if (CodeIntelligenceResultKernels.MatchesFilePath(filePath, file))
                return (filePath, cu);
        }
        var fullPath = Path.GetFullPath(Path.Combine(snapshot.ProjectRoot, file));
        if (snapshot.CompilationUnits.TryGetValue(fullPath, out var found))
            return (fullPath, found);
        return (file, null);
    }

    private static void AddGroupedCompletionsByKind(
        List<CompletionItem> items,
        Dictionary<string, List<CompletionItem>> completions)
    {
        CompletionEngineKernels.AddGroupedCompletionItemsByKind(items, completions);
    }

    private static CompletionResult EmptyResult(CompletionContext context)
    {
        return new CompletionResult(context, null, null, new Dictionary<string, List<CompletionItem>>());
    }
}
