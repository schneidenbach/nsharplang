using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
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
        "throw", "try", "catch", "finally", "lock", "new", "this", "base",
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

    // Cache of loaded assemblies for type resolution
    private List<Assembly>? _loadedAssemblies;
    private readonly Dictionary<string, Type> _typeCache = new();
    private readonly Dictionary<string, Type[]> _exportedTypesCache = new();

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
        try { sourceText = File.ReadAllText(filePath); }
        catch { }

        if (sourceText == null)
        {
            return EmptyResult(CompletionContext.Unknown);
        }

        var lines = sourceText.Split('\n');
        if (line <= 0 || line > lines.Length)
        {
            return EmptyResult(CompletionContext.Unknown);
        }

        var lineText = lines[line - 1];
        var beforeCursor = col > 0 && col <= lineText.Length ? lineText.Substring(0, col) : lineText;

        // Detect context
        if (IsMemberAccessContext(beforeCursor))
        {
            return GetMemberAccessCompletions(cu, semanticModel, beforeCursor, line, col, snapshot);
        }

        // General identifier context
        return GetIdentifierCompletions(cu, semanticModel, beforeCursor, snapshot, includeKeywords, line, col);
    }

    // ── Member Access Completions ───────────────────────────────────────

    private CompletionResult GetMemberAccessCompletions(CompilationUnit cu, SemanticModel? semanticModel,
        string beforeCursor, int line, int col, ProjectSnapshot snapshot)
    {
        // Extract the receiver name (the part before the last dot)
        var receiver = ExtractReceiver(beforeCursor);
        if (receiver == null)
        {
            return EmptyResult(CompletionContext.MemberAccess);
        }

        var completions = new Dictionary<string, List<CompletionItem>>();

        // Try to resolve receiver as a .NET type (static access)
        var resolvedType = TryResolveType(receiver, snapshot);
        if (resolvedType != null)
        {
            var isStatic = IsStaticAccess(receiver, semanticModel);
            var members = GetTypeMembers(resolvedType, isStatic ? MemberFilter.StaticOnly : MemberFilter.InstanceOnly);

            foreach (var group in members.GroupBy(m => m.Kind))
            {
                var key = Pluralize(group.Key);
                completions[key] = group.ToList();
            }

            return new CompletionResult(
                CompletionContext.MemberAccess,
                receiver,
                resolvedType.FullName,
                completions);
        }

        // Try to resolve receiver as a variable from semantic model (position-aware, then flat)
        if (semanticModel != null)
        {
            var typeInfo = semanticModel.LookupIdentifierAtPosition(receiver, line, col)
                          ?? semanticModel.LookupIdentifier(receiver);
            if (typeInfo != null)
            {
                var memberResult = ResolveMemberCompletionsFromTypeInfo(typeInfo, receiver, snapshot, completions);
                if (memberResult != null) return memberResult;
            }
        }

        // Fallback: scan AST for field/property/variable declarations matching the receiver name.
        // This covers class fields that the flat SemanticModel doesn't record.
        {
            var typeFromAst = ResolveReceiverTypeFromAst(receiver, cu, snapshot);
            if (typeFromAst != null)
            {
                var memberResult = ResolveMemberCompletionsFromTypeInfo(typeFromAst, receiver, snapshot, completions);
                if (memberResult != null) return memberResult;
            }
        }

        // Try as namespace
        if (IsKnownNamespace(receiver))
        {
            var nsItems = GetNamespaceCompletions(receiver);
            if (nsItems.Count > 0)
            {
                completions["types"] = nsItems;
                return new CompletionResult(CompletionContext.Namespace, receiver, null, completions);
            }
        }

        return EmptyResult(CompletionContext.MemberAccess);
    }

    // ── General Identifier Completions ──────────────────────────────────

    private CompletionResult GetIdentifierCompletions(CompilationUnit cu, SemanticModel? semanticModel,
        string beforeCursor, ProjectSnapshot snapshot, bool includeKeywords = false, int line = 0, int col = 0)
    {
        var completions = new Dictionary<string, List<CompletionItem>>();

        // Variables and parameters from semantic model (position-aware when possible)
        if (semanticModel != null)
        {
            var visibleVars = (line > 0 && semanticModel.Scopes.Count > 0)
                ? semanticModel.GetVisibleVariablesAtPosition(line, col)
                : new Dictionary<string, TypeInfo>(semanticModel.Variables);

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

    /// <summary>
    /// Resolve member completions from a TypeInfo — handles both .NET types (via reflection)
    /// and N# user-defined types (via AST member extraction).
    /// </summary>
    private CompletionResult? ResolveMemberCompletionsFromTypeInfo(TypeInfo typeInfo, string receiver,
        ProjectSnapshot snapshot, Dictionary<string, List<CompletionItem>> completions)
    {
        var typeName = FormatTypeInfo(typeInfo);

        // For generic types, extract the base name for CLR resolution
        var clrTypeName = typeName;
        if (typeInfo is GenericTypeInfo genericInfo)
        {
            clrTypeName = genericInfo.Name; // "List", "Dictionary", etc.
        }

        var clrType = TryResolveType(clrTypeName, snapshot);
        if (clrType != null)
        {
            var members = GetTypeMembers(clrType, MemberFilter.InstanceOnly);
            foreach (var group in members.GroupBy(m => m.Kind))
            {
                completions[Pluralize(group.Key)] = group.ToList();
            }
            return new CompletionResult(CompletionContext.MemberAccess, receiver, clrType.FullName, completions);
        }

        // N# type — extract members from declarations
        var nsharpMembers = GetNSharpTypeMembers(typeInfo, snapshot);
        if (nsharpMembers.Count > 0)
        {
            foreach (var group in nsharpMembers.GroupBy(m => m.Kind))
            {
                completions[Pluralize(group.Key)] = group.ToList();
            }
            return new CompletionResult(CompletionContext.MemberAccess, receiver, typeName, completions);
        }

        return null;
    }

    /// <summary>
    /// Scan the AST for a variable/field/property declaration matching the receiver name.
    /// This is the fallback when SemanticModel doesn't have the symbol (e.g., class fields).
    /// </summary>
    private TypeInfo? ResolveReceiverTypeFromAst(string name, CompilationUnit cu, ProjectSnapshot snapshot)
    {
        // Search all declarations for fields/properties/variables with this name
        foreach (var decl in cu.Declarations)
        {
            // Check inside class/struct/record members
            List<Declaration>? members = decl switch
            {
                ClassDeclaration c => c.Members,
                StructDeclaration s => s.Members,
                RecordDeclaration r => r.Members,
                _ => null
            };

            if (members != null)
            {
                foreach (var member in members)
                {
                    if (member is FieldDeclaration field && field.Name == name && field.Type != null)
                    {
                        return ResolveTypeReferenceToTypeInfo(field.Type, snapshot);
                    }
                    if (member is PropertyDeclaration prop && prop.Name == name)
                    {
                        return ResolveTypeReferenceToTypeInfo(prop.Type, snapshot);
                    }
                }
            }

            // Check function parameters and local variables
            if (decl is FunctionDeclaration func)
            {
                foreach (var param in func.Parameters)
                {
                    if (param.Name == name)
                    {
                        return ResolveTypeReferenceToTypeInfo(param.Type, snapshot);
                    }
                }
            }
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
            _ => new SimpleTypeInfo("unknown")
        };
    }

    // ── Type Member Resolution ──────────────────────────────────────────

    private enum MemberFilter { All, StaticOnly, InstanceOnly }

    private List<CompletionItem> GetTypeMembers(Type type, MemberFilter filter)
    {
        var items = new List<CompletionItem>();
        var bindingFlags = BindingFlags.Public |
            (filter == MemberFilter.StaticOnly ? BindingFlags.Static :
             filter == MemberFilter.InstanceOnly ? BindingFlags.Instance :
             BindingFlags.Static | BindingFlags.Instance);

        // Methods
        var methods = type.GetMethods(bindingFlags)
            .Where(m => !m.IsSpecialName && m.DeclaringType?.FullName != "System.Object")
            .GroupBy(m => m.Name)
            .ToList();

        foreach (var group in methods)
        {
            var method = group.First();
            var overloads = group.Count();
            var paramStr = FormatMethodParameters(method);
            var detail = overloads > 1 ? $"(+{overloads - 1} overloads)" : null;
            items.Add(new CompletionItem(
                method.Name,
                "method",
                FormatClrType(method.ReturnType),
                paramStr,
                detail,
                method.IsStatic));
        }

        // Properties
        foreach (var prop in type.GetProperties(bindingFlags))
        {
            if (prop.DeclaringType?.FullName == "System.Object") continue;
            items.Add(new CompletionItem(
                prop.Name,
                "property",
                FormatClrType(prop.PropertyType),
                null,
                null,
                prop.GetMethod?.IsStatic ?? false));
        }

        // Fields
        foreach (var field in type.GetFields(bindingFlags))
        {
            if (field.DeclaringType?.FullName == "System.Object") continue;
            items.Add(new CompletionItem(
                field.Name,
                "field",
                FormatClrType(field.FieldType),
                null,
                null,
                field.IsStatic));
        }

        return items;
    }

    private List<CompletionItem> GetNSharpTypeMembers(TypeInfo typeInfo, ProjectSnapshot snapshot)
    {
        var items = new List<CompletionItem>();
        List<Declaration>? members = typeInfo switch
        {
            ClassTypeInfo c => c.Declaration.Members,
            StructTypeInfo s => s.Declaration.Members,
            RecordTypeInfo r => r.Declaration.Members,
            InterfaceTypeInfo i => i.Declaration.Members,
            _ => null
        };

        if (members == null) return items;

        foreach (var member in members)
        {
            var item = DeclarationToCompletionItem(member);
            if (item != null) items.Add(item);
        }

        return items;
    }

    private List<CompletionItem> GetNamespaceCompletions(string ns)
    {
        var items = new List<CompletionItem>();
        EnsureAssembliesLoaded();

        var seen = new HashSet<string>();

        foreach (var assembly in _loadedAssemblies!)
        {
            Type[] types;
            if (!_exportedTypesCache.TryGetValue(assembly.FullName ?? "", out types!))
            {
                try { types = assembly.GetExportedTypes(); }
                catch { types = Array.Empty<Type>(); }
                _exportedTypesCache[assembly.FullName ?? ""] = types;
            }

            foreach (var type in types)
            {
                if (type.Namespace == ns && !type.IsNested)
                {
                    var cleanName = type.Name.Contains('`') ? type.Name.Split('`')[0] : type.Name;
                    if (seen.Add(cleanName))
                    {
                        items.Add(new CompletionItem(cleanName, "type", type.FullName, null, null, type.IsAbstract && type.IsSealed));
                    }
                }
            }
        }

        return items;
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private static bool IsMemberAccessContext(string beforeCursor)
    {
        var trimmed = beforeCursor.TrimEnd();
        // Direct: cursor is right after dot — "people."
        if (trimmed.EndsWith(".")) return true;

        // Indirect: cursor is after "receiver.partial" — find the last dot
        // This handles the case where an LLM queries at a position like people.Add(
        var lastDot = trimmed.LastIndexOf('.');
        if (lastDot > 0)
        {
            // Check that text before the dot is an identifier (not inside a string)
            var beforeDot = trimmed.Substring(0, lastDot).TrimEnd();
            if (beforeDot.Length > 0 && (char.IsLetterOrDigit(beforeDot[^1]) || beforeDot[^1] == '_'))
                return true;
        }

        return false;
    }

    private static string? ExtractReceiver(string beforeCursor)
    {
        var trimmed = beforeCursor.TrimEnd();

        // Find the last dot
        int dotIndex;
        if (trimmed.EndsWith("."))
        {
            dotIndex = trimmed.Length - 1;
        }
        else
        {
            dotIndex = trimmed.LastIndexOf('.');
            if (dotIndex < 0) return null;
        }

        // Get the part before the dot
        var withoutDot = trimmed.Substring(0, dotIndex).TrimEnd();

        // Walk backwards to find the receiver identifier
        var end = withoutDot.Length;
        var start = end - 1;
        while (start >= 0 && (char.IsLetterOrDigit(withoutDot[start]) || withoutDot[start] == '_' || withoutDot[start] == '.'))
        {
            start--;
        }
        start++;

        return start < end ? withoutDot.Substring(start, end - start) : null;
    }

    private bool IsStaticAccess(string name, SemanticModel? semanticModel)
    {
        // If the name starts with uppercase and isn't a variable, it's likely a static type access
        if (char.IsUpper(name[0]))
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

    private Type? TryResolveType(string name, ProjectSnapshot snapshot)
    {
        if (_typeCache.TryGetValue(name, out var cached))
            return cached;

        EnsureAssembliesLoaded();

        // Common aliases
        var fullName = name switch
        {
            "int" => "System.Int32",
            "long" => "System.Int64",
            "string" => "System.String",
            "bool" => "System.Boolean",
            "double" => "System.Double",
            "float" => "System.Single",
            "object" => "System.Object",
            "Console" => "System.Console",
            "Math" => "System.Math",
            "DateTime" => "System.DateTime",
            "List" => "System.Collections.Generic.List`1",
            "Dictionary" => "System.Collections.Generic.Dictionary`2",
            _ => name
        };

        foreach (var assembly in _loadedAssemblies!)
        {
            var type = assembly.GetType(fullName);
            if (type != null)
            {
                _typeCache[name] = type;
                return type;
            }
        }

        // Try with System. prefix
        foreach (var prefix in new[] { "System.", "System.Collections.Generic.", "System.Linq.", "System.IO.", "System.Threading.Tasks." })
        {
            foreach (var assembly in _loadedAssemblies!)
            {
                var type = assembly.GetType(prefix + name);
                if (type != null)
                {
                    _typeCache[name] = type;
                    return type;
                }
            }
        }

        return null;
    }

    private static readonly HashSet<string> WellKnownNamespaces = new()
    {
        "System", "System.Collections", "System.Collections.Generic", "System.IO",
        "System.Linq", "System.Text", "System.Threading", "System.Threading.Tasks",
        "System.Net", "System.Net.Http", "System.Reflection", "System.Diagnostics"
    };

    private bool IsKnownNamespace(string name) => WellKnownNamespaces.Contains(name);

    private void EnsureAssembliesLoaded()
    {
        if (_loadedAssemblies != null) return;
        _loadedAssemblies = new List<Assembly>();

        try
        {
            _loadedAssemblies.Add(typeof(object).Assembly);
            _loadedAssemblies.Add(typeof(Console).Assembly);
            _loadedAssemblies.Add(typeof(System.Linq.Enumerable).Assembly);
            _loadedAssemblies.Add(Assembly.Load("System.Runtime"));
        }
        catch { /* assemblies not available */ }
    }

    private static CompletionItem? DeclarationToCompletionItem(Declaration decl) => decl switch
    {
        FunctionDeclaration f => new CompletionItem(f.Name, "function",
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

    private static string FormatMethodParameters(MethodInfo method)
    {
        var parts = method.GetParameters().Select(p => $"{p.Name} {FormatClrType(p.ParameterType)}");
        return $"({string.Join(", ", parts)})";
    }

    private static string FormatClrType(Type type)
    {
        if (type.FullName == "System.Void") return "void";
        if (type.FullName == "System.Int32") return "int";
        if (type.FullName == "System.Int64") return "long";
        if (type.FullName == "System.String") return "string";
        if (type.FullName == "System.Boolean") return "bool";
        if (type.FullName == "System.Double") return "double";
        if (type.FullName == "System.Single") return "float";
        if (type.FullName == "System.Object") return "object";
        if (type.IsGenericType)
        {
            var baseName = type.Name.Split('`')[0];
            var args = string.Join(", ", type.GetGenericArguments().Select(FormatClrType));
            return $"{baseName}<{args}>";
        }
        return type.Name;
    }

    private static string FormatTypeInfo(TypeInfo typeInfo) => typeInfo switch
    {
        SimpleTypeInfo s => s.Name,
        ClassTypeInfo c => c.Declaration.Name,
        StructTypeInfo s => s.Declaration.Name,
        RecordTypeInfo r => r.Declaration.Name,
        InterfaceTypeInfo i => i.Declaration.Name,
        FunctionTypeInfo f => f.Declaration?.ReturnType != null
            ? CodeIntelligenceService.FormatTypeReferencePublic(f.Declaration.ReturnType) : "void",
        _ => typeInfo.ToString() ?? "unknown"
    };

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

    private static string Pluralize(string kind) => kind switch
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
