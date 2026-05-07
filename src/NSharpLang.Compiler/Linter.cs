using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Diagnostic severity levels
/// </summary>
public enum DiagnosticSeverity
{
    Warning,
    Error,
    Info
}

/// <summary>
/// Location information for a diagnostic
/// </summary>
public record Location(int Line, int Column, string? FilePath = null);

/// <summary>
/// Represents a linter diagnostic (warning, error, or info)
/// </summary>
public record Diagnostic(
    string Code,
    string Message,
    Location Location,
    DiagnosticSeverity Severity,
    string? Suggestion = null);

/// <summary>
/// Linter configuration from .editorconfig
/// </summary>
public class LinterConfig
{
    public Dictionary<string, DiagnosticSeverity> RuleSeverities { get; set; } = new();

    public static LinterConfig Default()
    {
        return new LinterConfig
        {
            RuleSeverities = new Dictionary<string, DiagnosticSeverity>
            {
                { "NL001", DiagnosticSeverity.Warning }, // Unused variable
                { "NL002", DiagnosticSeverity.Error },   // Missing import
                { "NL003", DiagnosticSeverity.Warning }, // Unnecessary null check
                { "NL004", DiagnosticSeverity.Warning }, // Async without await
                { "NL005", DiagnosticSeverity.Info },    // Use pattern matching
                { "NL006", DiagnosticSeverity.Warning }, // Unreachable code
                { "NL008", DiagnosticSeverity.Info },    // Camel-case local
                { "NL011", DiagnosticSeverity.Warning }, // Empty catch
                { "NL012", DiagnosticSeverity.Info },    // Unused parameter
                { "NL013", DiagnosticSeverity.Info },    // Prefer interpolation
                { "NL010", DiagnosticSeverity.Warning }, // Unused import
                { "NL014", DiagnosticSeverity.Info },    // Unnecessary type annotation
                { "NL015", DiagnosticSeverity.Info },    // Prefer const
                { "NL016", DiagnosticSeverity.Warning }, // Redundant null check
                { "NL018", DiagnosticSeverity.Info },    // Prefer readonly
                { "NL019", DiagnosticSeverity.Info },    // Empty block
                { "NL020", DiagnosticSeverity.Warning }, // Shadowed variable
                { "NL101", DiagnosticSeverity.Info },    // Migration: C# modifiers in .nl files
                { "NL102", DiagnosticSeverity.Info },    // Migration: C# auto-property accessors
                { "NL103", DiagnosticSeverity.Info },    // Migration: null-forgiving artifacts
                { "NL104", DiagnosticSeverity.Info },    // Migration: out var / TryGetValue pattern
                { "NL105", DiagnosticSeverity.Info },    // Migration: DTO class should be record candidate
                { "NL106", DiagnosticSeverity.Info },    // Migration: try/catch returning 500 boilerplate
            }
        };
    }

    public static LinterConfig FromEditorConfig(string directoryPath)
    {
        var config = Default();

        // Look for .editorconfig files starting from directoryPath and walking up
        var current = new DirectoryInfo(directoryPath);
        while (current != null)
        {
            var editorConfigPath = Path.Combine(current.FullName, ".editorconfig");
            if (File.Exists(editorConfigPath))
            {
                ParseEditorConfig(editorConfigPath, config);

                // Check for root=true
                var lines = File.ReadAllLines(editorConfigPath);
                if (lines.Any(l => l.Trim().Equals("root=true", StringComparison.OrdinalIgnoreCase) ||
                                   l.Trim().Equals("root = true", StringComparison.OrdinalIgnoreCase)))
                {
                    break; // Stop at root
                }
            }
            current = current.Parent;
        }

        return config;
    }

    private static void ParseEditorConfig(string path, LinterConfig config)
    {
        try
        {
            var lines = File.ReadAllLines(path);
            bool inNSharpSection = false;

            foreach (var line in lines)
            {
                var trimmed = line.Trim();

                // Check for [*.nl] section
                if (trimmed.StartsWith("[") && trimmed.EndsWith("]"))
                {
                    var pattern = trimmed[1..^1];
                    inNSharpSection = pattern.Contains("*.nl") || pattern.Contains(".nl");
                    continue;
                }

                // Parse rule severities in [*.nl] section
                if (inNSharpSection && trimmed.Contains("="))
                {
                    var parts = trimmed.Split('=', 2);
                    if (parts.Length == 2)
                    {
                        var key = parts[0].Trim();
                        var value = parts[1].Trim();

                        // Handle dotnet_diagnostic.NL001.severity = warning
                        if (key.StartsWith("dotnet_diagnostic.") && key.EndsWith(".severity"))
                        {
                            var ruleCode = key["dotnet_diagnostic.".Length..^".severity".Length];

                            var severity = value.ToLower() switch
                            {
                                "error" => DiagnosticSeverity.Error,
                                "warning" => DiagnosticSeverity.Warning,
                                "info" or "suggestion" => DiagnosticSeverity.Info,
                                _ => (DiagnosticSeverity?)null
                            };

                            if (severity.HasValue)
                            {
                                config.RuleSeverities[ruleCode] = severity.Value;
                            }
                        }
                    }
                }
            }
        }
        catch
        {
            // If parsing fails, use defaults
        }
    }

    public DiagnosticSeverity GetSeverity(string ruleCode)
    {
        return RuleSeverities.TryGetValue(ruleCode, out var severity)
            ? severity
            : DiagnosticSeverity.Warning;
    }
}

/// <summary>
/// Main linter class that analyzes code and returns diagnostics
/// </summary>
public partial class Linter
{
    private readonly LinterConfig _config;

    public Linter(LinterConfig? config = null)
    {
        _config = config ?? LinterConfig.Default();
    }

    public List<Diagnostic> Lint(CompilationUnit ast, string? filePath = null, string? sourceText = null)
    {
        var visitor = new LintVisitor(filePath, sourceText, _config);
        visitor.Visit(ast);

        if (!string.IsNullOrEmpty(sourceText))
        {
            var diagnostics = visitor.Diagnostics.ToList();
            diagnostics.AddRange(LintSource(sourceText, filePath));
            return diagnostics;
        }

        return visitor.Diagnostics;
    }

    /// <summary>
    /// Source-only migration lints for C# leftovers that often prevent a .nl file from parsing.
    /// Keep these conservative: diagnostics are informational scaffolding, not semantic errors.
    /// </summary>
    public List<Diagnostic> LintSource(string sourceText, string? filePath = null)
    {
        var diagnostics = new List<Diagnostic>();
        var suppressions = LintVisitor.BuildSuppressions(filePath, sourceText);
        var lines = sourceText.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');

        void Add(string code, string message, int line, int column, string suggestion)
        {
            if (suppressions.TryGetValue(line, out var codes)
                && (codes.Contains(code) || codes.Contains("*")))
                return;

            diagnostics.Add(new Diagnostic(
                code,
                message,
                new Location(line, column, filePath),
                _config.GetSeverity(code),
                suggestion));
        }

        for (var i = 0; i < lines.Length; i++)
        {
            var lineNumber = i + 1;
            var line = lines[i];
            var codePart = StripLineComment(line);

            foreach (Match match in CSharpModifierRegex().Matches(codePart))
            {
                var modifier = match.Groups[1].Value;
                Add(
                    "NL101",
                    $"C# modifier '{modifier}' looks out of place in an N# file",
                    lineNumber,
                    match.Groups[1].Index + 1,
                    modifier == "readonly"
                        ? "Prefer N# readonly/member conventions instead of carrying C# modifier syntax through migration"
                        : "Remove the C# modifier and use N# naming/casing/export conventions instead");
            }

            foreach (Match match in AutoPropertyRegex().Matches(codePart))
            {
                Add(
                    "NL102",
                    "C# auto-property accessor block '{ get; set; }' should be converted to N# property/record syntax",
                    lineNumber,
                    match.Index + 1,
                    "For DTO-shaped data, prefer an N# record; otherwise write explicit N# property syntax");
            }

            foreach (Match match in NullForgivingRegex().Matches(codePart))
            {
                Add(
                    "NL103",
                    $"Null-forgiving artifact '{match.Value}' is a C# migration leftover",
                    lineNumber,
                    match.Index + 1,
                    "Remove the trailing '!' and model nullability explicitly in N#");
            }

            if (codePart.Contains("out var ", StringComparison.Ordinal) || codePart.Contains("TryGetValue", StringComparison.Ordinal))
            {
                var column = FirstPositiveIndex(codePart.IndexOf("TryGetValue", StringComparison.Ordinal), codePart.IndexOf("out var ", StringComparison.Ordinal)) + 1;
                Add(
                    "NL104",
                    "C# out var / TryGetValue pattern is a migration candidate",
                    lineNumber,
                    column,
                    "Prefer an N# tuple/result-returning helper or a pattern that avoids out parameters");
            }
        }

        AddDtoRecordCandidates(lines, Add);
        AddTryCatch500Candidates(lines, Add);

        return diagnostics;
    }

    private static int FirstPositiveIndex(params int[] indexes)
        => indexes.Where(i => i >= 0).DefaultIfEmpty(0).Min();

    private static string StripLineComment(string line)
    {
        var inString = false;
        for (var i = 0; i < line.Length; i++)
        {
            if (line[i] == '"' && (i == 0 || line[i - 1] != '\\'))
                inString = !inString;
            if (!inString && i + 1 < line.Length && line[i] == '/' && line[i + 1] == '/')
                return line[..i];
        }

        return line;
    }

    private static void AddDtoRecordCandidates(string[] lines, Action<string, string, int, int, string> add)
    {
        for (var i = 0; i < lines.Length; i++)
        {
            var match = DtoClassRegex().Match(StripLineComment(lines[i]));
            if (!match.Success)
                continue;

            var name = match.Groups[1].Value;
            var braceDepth = lines[i].Contains('{') ? 1 : 0;
            var hasMember = false;
            var membersLookLikeProperties = true;

            for (var j = i + 1; j < lines.Length; j++)
            {
                var code = StripLineComment(lines[j]).Trim();
                if (code.Length > 0 && code != "}" && code != "};")
                {
                    hasMember = true;
                    if (!AutoPropertyRegex().IsMatch(code) && !DtoPropertyLikeRegex().IsMatch(code))
                        membersLookLikeProperties = false;
                }

                braceDepth += lines[j].Count(c => c == '{');
                braceDepth -= lines[j].Count(c => c == '}');
                if (braceDepth <= 0)
                    break;
            }

            if (hasMember && membersLookLikeProperties)
            {
                add(
                    "NL105",
                    $"DTO-shaped class '{name}' looks like an N# record candidate",
                    i + 1,
                    match.Groups[1].Index + 1,
                    "Convert data-only DTO classes to records when identity/inheritance semantics are not required");
            }
        }
    }

    private static void AddTryCatch500Candidates(string[] lines, Action<string, string, int, int, string> add)
    {
        for (var i = 0; i < lines.Length; i++)
        {
            var code = StripLineComment(lines[i]);
            if (!code.Contains("catch", StringComparison.Ordinal))
                continue;

            var window = string.Join("\n", lines.Skip(i).Take(8).Select(StripLineComment));
            if (window.Contains("StatusCode(500", StringComparison.Ordinal)
                || window.Contains("StatusCodes.Status500InternalServerError", StringComparison.Ordinal)
                || window.Contains("InternalServerError", StringComparison.Ordinal))
            {
                add(
                    "NL106",
                    "try/catch returning HTTP 500 boilerplate is a migration candidate",
                    i + 1,
                    Math.Max(1, code.IndexOf("catch", StringComparison.Ordinal) + 1),
                    "Prefer centralized error handling or an N# result/error abstraction instead of repeated catch-to-500 blocks");
            }
        }
    }

    [GeneratedRegex(@"\b(public|private|protected|override|virtual|partial|readonly)\b", RegexOptions.CultureInvariant)]
    private static partial Regex CSharpModifierRegex();

    [GeneratedRegex(@"\{\s*get\s*;\s*(set|init)\s*;\s*\}", RegexOptions.CultureInvariant)]
    private static partial Regex AutoPropertyRegex();

    [GeneratedRegex(@"\b(?:null|default|[A-Za-z_][A-Za-z0-9_]*)!", RegexOptions.CultureInvariant)]
    private static partial Regex NullForgivingRegex();

    [GeneratedRegex(@"\bclass\s+([A-Z][A-Za-z0-9_]*(?:Dto|DTO|Request|Response|Model))\b", RegexOptions.CultureInvariant)]
    private static partial Regex DtoClassRegex();

    [GeneratedRegex(@"^[A-Z][A-Za-z0-9_]*\s*:\s*[^=]+(?:=.*)?$", RegexOptions.CultureInvariant)]
    private static partial Regex DtoPropertyLikeRegex();
}

/// <summary>
/// AST visitor that performs linting checks
/// </summary>
internal class LintVisitor
{
    private readonly string? _filePath;
    private readonly LinterConfig _config;
    private readonly Dictionary<int, HashSet<string>> _suppressedDiagnosticsByLine;
    private readonly List<Diagnostic> _diagnostics = new();
    private Dictionary<string, (int Line, int Column, bool Used)> _declaredVariables = new();
    private readonly HashSet<string> _usedVariables = new();
    private readonly Stack<Dictionary<string, (int Line, int Column, bool Used)>> _scopeStack = new();
    private readonly List<string> _importedNamespaces = new();
    private readonly HashSet<string> _importedFileSymbols = new();
    private bool _hasAwaitInFunction = false;
    private bool _inAsyncFunction = false;
    private readonly HashSet<Expression> _visitingStack = new(ReferenceEqualityComparer.Instance);
    private int _recursionDepth = 0;
    private const int MAX_RECURSION_DEPTH = 100; // Lowered to detect infinite loops faster

    // NL010: Track imports and identifiers used in code for unused-import detection
    private readonly List<(string Namespace, int Line, int Column, bool IsFile, string? FilePath)> _allImports = new();
    private readonly HashSet<string> _allCodeIdentifiers = new();
    private readonly HashSet<string> _allMemberAccessNames = new();

    // NL015: Track let declarations and assignments within functions
    // Maps variable name → (Line, Col, HasInitializer, InLambda)
    private Dictionary<string, (int Line, int Column, bool HasInitializer, bool InLambda)> _letDeclarations = new();
    private readonly HashSet<string> _assignedVariables = new();
    private bool _inLambda = false;

    // NL018: Track class field assignments — (field name → (assignedInCtor, assignedElsewhere))
    private Dictionary<string, (bool InCtor, bool Elsewhere)> _classFieldAssignments = new();
    private bool _inConstructor = false;

    // NL012: Track parameters separately so we can report them without polluting the unused-variable check
    private List<(string Name, int Line, int Column)> _currentFunctionParams = new();
    private HashSet<string> _currentFunctionParamUsages = new();

    public List<Diagnostic> Diagnostics => _diagnostics;

    public LintVisitor(string? filePath = null, string? sourceText = null, LinterConfig? config = null)
    {
        _filePath = filePath;
        _config = config ?? LinterConfig.Default();
        _suppressedDiagnosticsByLine = BuildSuppressions(filePath, sourceText);
    }

    public void Visit(CompilationUnit unit)
    {
        // Track imported namespaces for NL002 and NL010
        foreach (var import in unit.Imports)
        {
            _importedNamespaces.Add(import.Namespace);
            _allImports.Add((import.Namespace, import.Line, import.Column, false, null));
        }

        foreach (var fileImport in unit.FileImports.OfType<FileImport>())
        {
            var importedSymbol = ExtractImportedFileSymbolName(fileImport);
            if (!string.IsNullOrWhiteSpace(importedSymbol))
            {
                _importedFileSymbols.Add(importedSymbol!);
                _allImports.Add((importedSymbol!, fileImport.Line, fileImport.Column, true, fileImport.Path));
            }
        }

        // Push global scope
        PushScope();

        // Visit all declarations
        foreach (var declaration in unit.Declarations)
        {
            VisitDeclaration(declaration);
        }

        // Check for unused variables in global scope
        CheckUnusedVariables();
        PopScope();

        // NL010: Check for unused imports (after visiting the whole file)
        CheckUnusedImports();
    }

    private void PushScope()
    {
        // Save current scope to stack
        _scopeStack.Push(_declaredVariables);
        // Create new empty scope for child
        _declaredVariables = new Dictionary<string, (int Line, int Column, bool Used)>();
    }

    private void PopScope()
    {
        if (_scopeStack.Count > 0)
        {
            // Check current scope for unused variables
            CheckUnusedVariables();
            // Restore parent scope
            _declaredVariables = _scopeStack.Pop();
        }
    }

    private void CheckUnusedVariables()
    {
        foreach (var kvp in _declaredVariables)
        {
            var (varName, (line, column, used)) = (kvp.Key, kvp.Value);
            if (!used && !_usedVariables.Contains(varName))
            {
                AddDiagnostic(
                    "NL001",
                    $"Variable '{varName}' is declared but never read",
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL001"),
                    $"If this is intentional, prefix it with '_' to indicate it's unused: '_{varName}'");
            }
        }
    }

    private void AddDiagnostic(string code, string message, Location location, DiagnosticSeverity severity, string? suggestion = null)
    {
        if (IsSuppressed(code, location.Line))
            return;

        _diagnostics.Add(new Diagnostic(code, message, location, severity, suggestion));
    }

    private bool IsSuppressed(string code, int line)
        => _suppressedDiagnosticsByLine.TryGetValue(line, out var codes)
           && (codes.Contains(code) || codes.Contains("*"));

    internal static Dictionary<int, HashSet<string>> BuildSuppressions(string? filePath, string? sourceText)
    {
        if (string.IsNullOrEmpty(sourceText) && !string.IsNullOrWhiteSpace(filePath) && File.Exists(filePath))
        {
            try
            {
                sourceText = File.ReadAllText(filePath);
            }
            catch
            {
                sourceText = null;
            }
        }

        var suppressions = new Dictionary<int, HashSet<string>>();
        if (string.IsNullOrEmpty(sourceText))
            return suppressions;

        var lines = sourceText.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        var pendingCodes = new List<string>();

        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            var trimmed = line.Trim();
            var codes = ParseSuppressionCodes(line);
            if (codes.Count == 0)
            {
                if (!string.IsNullOrWhiteSpace(trimmed) && !trimmed.StartsWith("//", StringComparison.Ordinal))
                    pendingCodes.Clear();
                continue;
            }

            var commentIndex = line.IndexOf("//", StringComparison.Ordinal);
            var hasCodeBeforeComment = commentIndex > 0 && !string.IsNullOrWhiteSpace(line[..commentIndex]);
            if (hasCodeBeforeComment)
            {
                AddSuppression(suppressions, i + 1, codes);
                pendingCodes.Clear();
                continue;
            }

            pendingCodes.AddRange(codes);
            var nextLine = FindNextCodeLine(lines, i + 1);
            if (nextLine > 0)
                AddSuppression(suppressions, nextLine, pendingCodes);
            pendingCodes.Clear();
        }

        return suppressions;
    }

    private static int FindNextCodeLine(string[] lines, int startIndex)
    {
        for (var i = startIndex; i < lines.Length; i++)
        {
            var trimmed = lines[i].Trim();
            if (string.IsNullOrWhiteSpace(trimmed))
                continue;

            if (trimmed.StartsWith("//", StringComparison.Ordinal))
                continue;

            return i + 1;
        }

        return -1;
    }

    private static List<string> ParseSuppressionCodes(string line)
    {
        const string marker = "nlc:ignore";
        var markerIndex = line.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (markerIndex < 0)
            return new List<string>();

        var codesPart = line[(markerIndex + marker.Length)..]
            .Trim()
            .TrimStart(':')
            .Trim();

        if (string.IsNullOrWhiteSpace(codesPart))
            return new List<string> { "*" };

        return codesPart
            .Split(new[] { ',', ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(code => code.Trim().ToUpperInvariant())
            .ToList();
    }

    private static void AddSuppression(Dictionary<int, HashSet<string>> suppressions, int line, IEnumerable<string> codes)
    {
        if (!suppressions.TryGetValue(line, out var lineCodes))
        {
            lineCodes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            suppressions[line] = lineCodes;
        }

        foreach (var code in codes)
            lineCodes.Add(code);
    }

    private void VisitDeclaration(Declaration declaration)
    {
        switch (declaration)
        {
            case FunctionDeclaration func:
                VisitFunction(func);
                break;
            case ClassDeclaration classDecl:
                VisitClass(classDecl);
                break;
            case StructDeclaration structDecl:
                VisitStruct(structDecl);
                break;
            case RecordDeclaration recordDecl:
                VisitRecord(recordDecl);
                break;
            case InterfaceDeclaration interfaceDecl:
                VisitInterface(interfaceDecl);
                break;
            case UnionDeclaration unionDecl:
                break;
            case EnumDeclaration enumDecl:
                break;
            case FieldDeclaration field:
                TrackTypeReference(field.Type);
                if (field.Initializer != null)
                    VisitExpression(field.Initializer);
                break;
            case PropertyDeclaration prop:
                TrackTypeReference(prop.Type);
                if (prop.ExpressionBody != null)
                    VisitExpression(prop.ExpressionBody);
                if (prop.GetBody != null)
                    VisitStatement(prop.GetBody);
                if (prop.SetBody != null)
                    VisitStatement(prop.SetBody);
                break;
            case ConstructorDeclaration ctor:
                var wasInCtor = _inConstructor;
                _inConstructor = true;
                VisitStatement(ctor.Body);
                _inConstructor = wasInCtor;
                break;
            case TestDeclaration test:
                if (test.TableParameters != null)
                {
                    foreach (var param in test.TableParameters)
                        TrackTypeReference(param.Type);
                }
                if (test.TableCases != null)
                {
                    foreach (var row in test.TableCases)
                        foreach (var expr in row)
                            VisitExpression(expr);
                }
                VisitStatement(test.Body);
                break;
            case SetupDeclaration setup:
                VisitStatement(setup.Body);
                break;
            case TeardownDeclaration teardown:
                VisitStatement(teardown.Body);
                break;
        }
    }

    private void VisitFunction(FunctionDeclaration func)
    {
        // NL010: Track type references in function signature
        TrackTypeReference(func.ReturnType);
        foreach (var param in func.Parameters)
            TrackTypeReference(param.Type);

        // NL004: Check for async without await
        var wasInAsync = _inAsyncFunction;
        var hadAwait = _hasAwaitInFunction;
        _inAsyncFunction = func.Modifiers.HasFlag(Modifiers.Async);
        _hasAwaitInFunction = false;

        // Async functions implicitly use Task from System.Threading.Tasks
        if (_inAsyncFunction)
            _allCodeIdentifiers.Add("Task");

        // NL012: Save outer param tracking state
        var outerParams = _currentFunctionParams;
        var outerParamUsages = _currentFunctionParamUsages;
        _currentFunctionParams = new List<(string Name, int Line, int Column)>();
        _currentFunctionParamUsages = new HashSet<string>();

        // NL015: Save outer let/assignment tracking state (per-function)
        var outerLetDeclarations = _letDeclarations;
        var outerAssignedVariables = _assignedVariables.ToHashSet();
        _letDeclarations = new Dictionary<string, (int Line, int Column, bool HasInitializer, bool InLambda)>();
        _assignedVariables.Clear();

        if (func.Body != null)
        {
            PushScope();

            // Add parameters to scope; track for NL012
            foreach (var param in func.Parameters)
            {
                DeclareVariable(param.Name, func.Line, func.Column);
                MarkVariableUsed(param.Name); // Parameters exempt from NL001
                _currentFunctionParams.Add((param.Name, func.Line, func.Column));
            }

            VisitStatement(func.Body);

            // NL012: Report unused parameters
            CheckUnusedParameters(func.Name);

            // NL015: Emit prefer-const diagnostics for this function scope
            CheckPreferConst();

            PopScope();
        }
        else if (func.ExpressionBody != null)
        {
            PushScope();
            foreach (var param in func.Parameters)
            {
                DeclareVariable(param.Name, func.Line, func.Column);
                MarkVariableUsed(param.Name);
                _currentFunctionParams.Add((param.Name, func.Line, func.Column));
            }
            VisitExpression(func.ExpressionBody);

            // NL012: Report unused parameters
            CheckUnusedParameters(func.Name);

            // NL015: Emit prefer-const diagnostics for this function scope
            CheckPreferConst();

            PopScope();
        }

        // NL004: Async method without await
        if (_inAsyncFunction && !_hasAwaitInFunction && func.Body != null)
        {
            // Check if return type is Task or Task<T> (might need async for other reasons)
            var needsAwait = true;

            // If the function returns a Task synchronously (e.g., Task.CompletedTask), that's ok
            // For now, we'll warn on all async without await
            if (needsAwait)
            {
                AddDiagnostic(
                    "NL004",
                    $"Function '{func.Name}' is marked 'async' but never uses 'await' — it will run synchronously",
                    new Location(func.Line, func.Column, _filePath),
                    _config.GetSeverity("NL004"),
                    $"Either add an 'await' expression inside '{func.Name}', or remove the 'async' modifier if this function doesn't need to be asynchronous");
            }
        }

        // Restore state
        _inAsyncFunction = wasInAsync;
        _hasAwaitInFunction = hadAwait;
        _currentFunctionParams = outerParams;
        _currentFunctionParamUsages = outerParamUsages;

        // NL015: Restore outer let/assignment tracking
        _letDeclarations = outerLetDeclarations;
        _assignedVariables.Clear();
        foreach (var v in outerAssignedVariables)
            _assignedVariables.Add(v);
    }

    private void CheckUnusedParameters(string functionName)
    {
        if (!_config.RuleSeverities.ContainsKey("NL012"))
            return;

        foreach (var (name, line, column) in _currentFunctionParams)
        {
            if (!_currentFunctionParamUsages.Contains(name))
            {
                AddDiagnostic(
                    "NL012",
                    $"Parameter '{name}' in '{functionName}' is never read — is it needed?",
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL012"),
                    $"If the parameter is required by an interface or override, prefix with '_' to suppress this: '_{name}'");
            }
        }
    }

    private void VisitClass(ClassDeclaration classDecl)
    {
        VisitClassLikeMembers(classDecl.Members, classDecl.Name, classDecl.Line, classDecl.Column);
    }

    private void VisitStruct(StructDeclaration structDecl)
    {
        // Structs don't typically have the same readonly pattern as classes, visit normally
        foreach (var member in structDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitRecord(RecordDeclaration recordDecl)
    {
        foreach (var member in recordDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitInterface(InterfaceDeclaration interfaceDecl)
    {
        foreach (var member in interfaceDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitStatement(Statement statement)
    {
        switch (statement)
        {
            case VariableDeclarationStatement varDecl:
                // NL010: Track type references in variable declarations
                TrackTypeReference(varDecl.Type);
                // Calculate column of variable name, not the keyword
                // For "let x = 1", if let starts at column 10, then x starts at column 14 (10 + "let" + space)
                // For "const x = 1", if const starts at column 10, then x starts at column 16 (10 + "const" + space)
                var keywordLength = varDecl.Kind switch
                {
                    VariableKind.Let => 3,  // "let" (also used for := shorthand)
                    VariableKind.Const => 5,  // "const"
                    VariableKind.Readonly => 8,  // "readonly"
                    _ => 3
                };
                var nameColumn = varDecl.Column + keywordLength + 1; // +1 for space after keyword
                // NL008: Camel-case local — warn if name starts with uppercase (skip _ prefixed)
                CheckCamelCaseLocal(varDecl.Name, varDecl.Line, nameColumn);
                DeclareVariable(varDecl.Name, varDecl.Line, nameColumn);
                if (varDecl.Initializer != null)
                {
                    // NL014: Unnecessary type annotation — flag obvious literal-type matches
                    if (varDecl.Type != null && varDecl.Kind == VariableKind.Let)
                        CheckUnnecessaryTypeAnnotation(varDecl.Type, varDecl.Initializer, varDecl.Line, varDecl.Column);

                    VisitExpression(varDecl.Initializer);
                }
                // NL015: Track let declarations that have an explicit type annotation.
                // We only flag explicit `let x: T = ...` patterns, not `:=` shorthand,
                // because the explicit annotation signals the developer is being deliberate
                // and should use `const` when no reassignment occurs.
                // Shorthand `:=` is too common to flag — it would be very noisy.
                if (varDecl.Kind == VariableKind.Let && varDecl.Type != null)
                    _letDeclarations[varDecl.Name] = (varDecl.Line, nameColumn, varDecl.Initializer != null, _inLambda);
                break;

            case BlockStatement block:
                // NL019: Empty block — warn if block has no statements
                // (Only fire at function-body level; we suppress for interface method stubs etc.
                //  The simplest safe check: only warn when the block is non-top-level, i.e. there
                //  IS a containing scope already, which means we are inside at least one function.)
                if (block.Statements.Count == 0 && _scopeStack.Count > 0)
                {
                    AddDiagnostic(
                        "NL019",
                        "This block is empty — it doesn't do anything",
                        new Location(block.Line, block.Column, _filePath),
                        _config.GetSeverity("NL019"),
                        "Add code to the block, or remove it if it's not needed");
                }

                PushScope();
                var unreachableReported = false;
                var restIsUnreachable = false;

                foreach (var stmt in block.Statements)
                {
                    if (restIsUnreachable)
                    {
                        if (!unreachableReported)
                        {
                            AddDiagnostic(
                                "NL006",
                                "This code will never run — there's a 'return' or 'throw' above it",
                                new Location(stmt.Line, stmt.Column, _filePath),
                                _config.GetSeverity("NL006"),
                                "Remove the unreachable code, or move it before the return/throw if it should execute");
                            unreachableReported = true;
                        }

                        // Don't cascade other diagnostics/variable usage from unreachable statements.
                        continue;
                    }

                    VisitStatement(stmt);

                    if (stmt is ReturnStatement or ThrowStatement)
                    {
                        restIsUnreachable = true;
                    }
                }
                PopScope();
                break;

            case IfStatement ifStmt:
                VisitExpression(ifStmt.Condition);
                // NL003: Check for unnecessary null checks on value types
                CheckUnnecessaryNullCheck(ifStmt.Condition);
                // NL016: Redundant null check on always-non-null expressions
                CheckRedundantNullCheckOnNewOrLiteral(ifStmt.Condition);
                VisitStatement(ifStmt.ThenStatement);
                if (ifStmt.ElseStatement != null)
                    VisitStatement(ifStmt.ElseStatement);
                break;

            case ForStatement forStmt:
                PushScope();
                if (forStmt.Initializer != null)
                    VisitStatement(forStmt.Initializer);
                if (forStmt.Condition != null)
                    VisitExpression(forStmt.Condition);
                if (forStmt.Iterator != null)
                    VisitExpression(forStmt.Iterator);
                VisitStatement(forStmt.Body);
                PopScope();
                break;

            case ForeachStatement foreachStmt:
                VisitExpression(foreachStmt.Collection); // Visit collection in outer scope FIRST
                PushScope();
                DeclareVariable(foreachStmt.VariableName, foreachStmt.Line, foreachStmt.Column);
                MarkVariableUsed(foreachStmt.VariableName); // Loop variables are considered used
                VisitStatement(foreachStmt.Body);
                PopScope();
                break;

            case WhileStatement whileStmt:
                VisitExpression(whileStmt.Condition);
                CheckUnnecessaryNullCheck(whileStmt.Condition);
                // NL016: Redundant null check on always-non-null expressions
                CheckRedundantNullCheckOnNewOrLiteral(whileStmt.Condition);
                VisitStatement(whileStmt.Body);
                break;

            case ReturnStatement returnStmt:
                if (returnStmt.Value != null)
                    VisitExpression(returnStmt.Value);
                break;

            case ExpressionStatement exprStmt:
                VisitExpression(exprStmt.Expression);
                break;

            case TryStatement tryStmt:
                VisitStatement(tryStmt.TryBlock);
                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    // NL011: Empty catch block
                    if (catchClause.Block.Statements.Count == 0)
                    {
                        AddDiagnostic(
                            "NL011",
                            "This catch block is empty — exceptions will be silently swallowed",
                            new Location(catchClause.Block.Line, catchClause.Block.Column, _filePath),
                            _config.GetSeverity("NL011"),
                            "Log the error, handle it, or add a comment explaining why it's safe to ignore");
                    }

                    PushScope();
                    if (catchClause.VariableName != null)
                    {
                        DeclareVariable(catchClause.VariableName, catchClause.Block.Line, catchClause.Block.Column);
                        MarkVariableUsed(catchClause.VariableName); // Exception variables are considered used
                    }
                    VisitStatement(catchClause.Block);
                    PopScope();
                }
                if (tryStmt.FinallyBlock != null)
                    VisitStatement(tryStmt.FinallyBlock);
                break;

            case UsingStatement usingStmt:
                PushScope();
                if (usingStmt.Declaration != null)
                    VisitStatement(usingStmt.Declaration);
                if (usingStmt.Expression != null)
                    VisitExpression(usingStmt.Expression);
                if (usingStmt.Body != null)
                    VisitStatement(usingStmt.Body);
                PopScope();
                break;

            case SwitchStatement switchStmt:
                VisitExpression(switchStmt.Value);
                foreach (var caseStmt in switchStmt.Cases)
                {
                    PushScope();
                    foreach (var stmt in caseStmt.Statements)
                    {
                        VisitStatement(stmt);
                    }
                    PopScope();
                }
                break;

            case ThrowStatement throwStmt:
                VisitExpression(throwStmt.Expression);
                break;

            case LocalFunctionStatement localFunc:
                VisitFunction(localFunc.Function);
                break;

            case PrintStatement printStmt:
                VisitExpression(printStmt.Value);
                break;

            case LockStatement lockStmt:
                VisitExpression(lockStmt.LockObject);
                VisitStatement(lockStmt.Body);
                break;

            case YieldStatement yieldStmt:
                if (yieldStmt.Value != null)
                    VisitExpression(yieldStmt.Value);
                break;

            case TupleDeconstructionStatement tupleDecl:
                foreach (var name in tupleDecl.Names)
                {
                    if (name != "_") // Don't track discards
                        DeclareVariable(name, tupleDecl.Line, tupleDecl.Column);
                }
                VisitExpression(tupleDecl.Initializer);
                break;

            case AwaitForEachStatement awaitForeach:
                VisitExpression(awaitForeach.Collection); // Visit collection in outer scope FIRST
                PushScope();
                DeclareVariable(awaitForeach.VariableName, awaitForeach.Line, awaitForeach.Column);
                MarkVariableUsed(awaitForeach.VariableName);
                VisitStatement(awaitForeach.Body);
                PopScope();
                break;
        }
    }

    private void CheckUnnecessaryNullCheck(Expression condition)
    {
        // NL003: Unnecessary Null Check
        // Check for patterns like: x != null or x == null where x is a value type
        if (condition is BinaryExpression binary)
        {
            if (binary.Operator == BinaryOperator.NotEqual || binary.Operator == BinaryOperator.Equal)
            {
                var isNullCheck = binary.Right is NullLiteralExpression || binary.Left is NullLiteralExpression;

                if (isNullCheck)
                {
                    var checkedExpr = binary.Right is NullLiteralExpression ? binary.Left : binary.Right;

                    // Check if it's comparing a value type against null
                    if (checkedExpr is IdentifierExpression ident)
                    {
                        // Check if we're comparing against known value types
                        var knownValueTypes = new[] { "int", "long", "short", "byte", "uint", "ulong", "ushort",
                            "float", "double", "decimal", "bool", "char", "sbyte" };

                        // Simple heuristic: if the identifier looks like a value type
                        // In a real implementation, this would use type information from the analyzer
                        // For now, we'll be conservative and only warn for obvious cases

                        // Check assignment patterns in the current scope
                        if (_declaredVariables.TryGetValue(ident.Name, out var varInfo))
                        {
                            // We would need type information here to be more accurate
                            // For now, we'll implement a basic version
                        }
                    }

                    // Check for direct type comparisons (e.g., comparing int literal)
                    if (checkedExpr is IntLiteralExpression ||
                        checkedExpr is FloatLiteralExpression ||
                        checkedExpr is BoolLiteralExpression)
                    {
                        var typeName = checkedExpr switch
                        {
                            IntLiteralExpression => "int",
                            FloatLiteralExpression => "float",
                            BoolLiteralExpression => "bool",
                            _ => "value type"
                        };

                        AddDiagnostic(
                            "NL003",
                            $"This null check is unnecessary — '{typeName}' is a value type and can never be null",
                            new Location(condition.Line, condition.Column, _filePath),
                            _config.GetSeverity("NL003"),
                            "You can safely remove this null check");
                    }
                }
            }
        }
    }

    private void VisitExpression(Expression expression)
    {
        // Guard against infinite recursion
        _recursionDepth++;
        if (_recursionDepth > MAX_RECURSION_DEPTH)
        {
            throw new InvalidOperationException($"Maximum recursion depth exceeded while visiting expression at line {expression.Line}, column {expression.Column}. Expression type: {expression.GetType().Name}");
        }

        // Guard against circular references by checking if this exact expression object
        // is currently on the call stack (not just visited before, but actively being visited)
        if (!_visitingStack.Add(expression))
        {
            // This expression is already on the visiting stack, indicating a circular reference
            // HACK: If it's an IdentifierExpression, still mark it as used even though we're skipping the visit
            // This ensures variables are properly tracked even in circular AST structures
            if (expression is IdentifierExpression identExpr)
            {
                MarkVariableUsed(identExpr.Name);
            }
            _recursionDepth--;
            return;
        }

        try
        {
            VisitExpressionInternal(expression);
        }
        finally
        {
            _recursionDepth--;
            _visitingStack.Remove(expression); // Remove from stack when done visiting
        }
    }

    private void VisitExpressionInternal(Expression expression)
    {
        switch (expression)
        {
            case IdentifierExpression ident:
                MarkVariableUsed(ident.Name);
                // NL010: Track all identifiers used in code for unused-import detection
                _allCodeIdentifiers.Add(ident.Name);

                // NL002: Missing Import
                // Check if identifier looks like a type that might need an import
                CheckMissingImport(ident);
                break;

            case StringLiteralExpression stringLiteral:
                // Handle string interpolation - mark variables used inside ${...} or {...}
                HandleStringInterpolation(stringLiteral.Value);
                break;

            case InterpolatedStringExpression interpolated:
                foreach (var part in interpolated.Parts)
                {
                    if (part is InterpolatedStringHole hole)
                    {
                        VisitExpression(hole.Expression);
                    }
                }
                break;

            case BinaryExpression binary:
                // NL013: Prefer string interpolation over concatenation
                if (binary.Operator == BinaryOperator.Add)
                    CheckPreferInterpolation(binary);
                VisitExpression(binary.Left);
                VisitExpression(binary.Right);
                break;

            case UnaryExpression unary:
                VisitExpression(unary.Operand);
                break;

            case CallExpression call:
                VisitExpression(call.Callee);
                foreach (var arg in call.Arguments)
                {
                    VisitExpression(arg.Value);
                }
                break;

            case NewExpression newExpr:
                // Check if the type might need an import
                if (newExpr.Type != null)
                {
                    CheckMissingImportForType(newExpr.Type, newExpr.Line, newExpr.Column);
                    // NL010: Record the type name as a used identifier
                    var newTypeName = GetBaseTypeName(newExpr.Type);
                    if (newTypeName != null)
                        _allCodeIdentifiers.Add(newTypeName);
                }
                foreach (var arg in newExpr.ConstructorArguments)
                {
                    VisitExpression(arg.Value);
                }
                if (newExpr.Initializer != null)
                {
                    foreach (var init in newExpr.Initializer.Properties)
                    {
                        VisitExpression(init.Value);
                    }
                }
                break;

            case MemberAccessExpression member:
                VisitExpression(member.Object);
                // NL010: Track member names for extension method detection
                _allMemberAccessNames.Add(member.MemberName);
                break;

            case IndexAccessExpression index:
                VisitExpression(index.Object);
                VisitExpression(index.Index);
                break;

            case AssignmentExpression assignment:
                // NL015: Track what variables are assigned to after declaration
                if (assignment.Target is IdentifierExpression assignTarget)
                    _assignedVariables.Add(assignTarget.Name);
                // NL018: Track field assignments to detect constructor-only writes
                TrackFieldAssignment(assignment.Target);
                VisitExpression(assignment.Target);
                VisitExpression(assignment.Value);
                break;

            case TernaryExpression ternary:
                VisitExpression(ternary.Condition);
                VisitExpression(ternary.ThenExpression);
                VisitExpression(ternary.ElseExpression);
                break;

            case LambdaExpression lambda:
                var wasInLambda = _inLambda;
                _inLambda = true;
                PushScope();
                foreach (var param in lambda.Parameters)
                {
                    DeclareVariable(param.Name, lambda.Line, lambda.Column);
                    MarkVariableUsed(param.Name);
                }
                if (lambda.BlockBody != null)
                    VisitStatement(lambda.BlockBody);
                if (lambda.ExpressionBody != null)
                    VisitExpression(lambda.ExpressionBody);
                PopScope();
                _inLambda = wasInLambda;
                break;

            case CastExpression cast:
                VisitExpression(cast.Expression);
                break;

            case IsExpression isExpr:
                VisitExpression(isExpr.Expression);
                break;

            case AwaitExpression awaitExpr:
                _hasAwaitInFunction = true; // Track that we're using await
                VisitExpression(awaitExpr.Expression);
                break;

            case ArrayLiteralExpression array:
                foreach (var element in array.Elements)
                {
                    VisitExpression(element);
                }
                break;

            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    VisitExpression(element.Value);
                }
                break;

            case RangeExpression range:
                if (range.Start != null)
                    VisitExpression(range.Start);
                if (range.End != null)
                    VisitExpression(range.End);
                break;

            case MatchExpression match:
                VisitExpression(match.Value);
                foreach (var matchCase in match.Cases)
                {
                    if (matchCase.Guard != null)
                        VisitExpression(matchCase.Guard);
                    VisitExpression(matchCase.Expression);
                }
                break;

            case WithExpression withExpr:
                VisitExpression(withExpr.Target);
                foreach (var prop in withExpr.Properties)
                {
                    VisitExpression(prop.Value);
                }
                break;

            case SpreadExpression spread:
                VisitExpression(spread.Expression);
                break;

            case ThrowExpression throwExpr:
                VisitExpression(throwExpr.Expression);
                break;

            case NameofExpression nameof:
                VisitExpression(nameof.Target);
                break;

            case CheckedExpression checkedExpr:
                VisitExpression(checkedExpr.Expression);
                break;

            case UncheckedExpression uncheckedExpr:
                VisitExpression(uncheckedExpr.Expression);
                break;

            case ParenthesizedExpression paren:
                VisitExpression(paren.Inner);
                break;

            default:
                // Handle any unhandled expression types (literals, etc.)
                // Most literals don't have child expressions to visit
                break;
        }
    }

    private void CheckCamelCaseLocal(string name, int line, int column)
    {
        if (!_config.RuleSeverities.ContainsKey("NL008"))
            return;
        if (string.IsNullOrEmpty(name))
            return;
        // Skip underscore-prefixed names (convention for intentionally unused / discards)
        if (name.StartsWith("_", StringComparison.Ordinal))
            return;
        if (char.IsUpper(name[0]))
        {
            AddDiagnostic(
                "NL008",
                $"Local variable '{name}' starts with an uppercase letter — locals use camelCase in N#",
                new Location(line, column, _filePath),
                _config.GetSeverity("NL008"),
                $"Rename to '{char.ToLowerInvariant(name[0])}{name[1..]}' — in N#, PascalCase is reserved for exported (public) declarations");
        }
    }

    private void CheckPreferInterpolation(BinaryExpression binary)
    {
        if (!_config.RuleSeverities.ContainsKey("NL013"))
            return;

        var leftIsString = binary.Left is StringLiteralExpression;
        var rightIsString = binary.Right is StringLiteralExpression;

        // Only fire when at least one operand is a string literal and the other is not also
        // a string literal (string literal + string literal is just concatenation, not a
        // case where interpolation helps readability).
        if ((leftIsString || rightIsString) && !(leftIsString && rightIsString))
        {
            AddDiagnostic(
                "NL013",
                "String concatenation with '+' is harder to read than interpolation",
                new Location(binary.Line, binary.Column, _filePath),
                _config.GetSeverity("NL013"),
                "Try $\"...{expr}...\" — string interpolation is easier to read and less error-prone");
        }
    }

    private void DeclareVariable(string name, int line, int column)
    {
        // NL020: Check if this name shadows a variable in an outer scope
        CheckShadowedVariable(name, line, column);

        _declaredVariables[name] = (line, column, false);
    }

    private void CheckShadowedVariable(string name, int line, int column)
    {
        if (!_config.RuleSeverities.ContainsKey("NL020"))
            return;

        // Skip discard (_) and underscore-prefixed names
        if (name == "_" || name.StartsWith("_", StringComparison.Ordinal))
            return;

        // Check all outer scopes on the stack (not the current scope, which we're declaring into)
        foreach (var scope in _scopeStack)
        {
            if (scope.ContainsKey(name))
            {
                AddDiagnostic(
                    "NL020",
                    $"Variable '{name}' shadows another '{name}' from an outer scope — this can lead to confusing bugs",
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL020"),
                    $"Consider renaming to avoid confusion with the outer '{name}'");
                return;
            }
        }
    }

    private void MarkVariableUsed(string name)
    {
        // NL012: Track parameter usages
        if (_currentFunctionParams.Any(p => p.Name == name))
            _currentFunctionParamUsages.Add(name);

        // Check current scope
        if (_declaredVariables.ContainsKey(name))
        {
            var (line, column, _) = _declaredVariables[name];
            _declaredVariables[name] = (line, column, true);
        }
        else
        {
            // Check parent scopes
            foreach (var scope in _scopeStack)
            {
                if (scope.ContainsKey(name))
                {
                    var (line, column, _) = scope[name];
                    scope[name] = (line, column, true);
                    break;
                }
            }
        }
        _usedVariables.Add(name);
    }

    private void CheckMissingImport(IdentifierExpression ident)
    {
        // NL002: Missing Import
        // Check for common types that might need imports
        var commonTypesMap = new Dictionary<string, string>
        {
            { "List", "System.Collections.Generic" },
            { "Dictionary", "System.Collections.Generic" },
            { "HashSet", "System.Collections.Generic" },
            { "Queue", "System.Collections.Generic" },
            { "Stack", "System.Collections.Generic" },
            { "LinkedList", "System.Collections.Generic" },
            { "StringBuilder", "System.Text" },
            { "Regex", "System.Text.RegularExpressions" },
            { "File", "System.IO" },
            { "Directory", "System.IO" },
            { "Path", "System.IO" },
            { "Stream", "System.IO" },
            { "HttpClient", "System.Net.Http" },
            { "JsonSerializer", "System.Text.Json" },
            { "Task", "System.Threading.Tasks" },
            { "CancellationToken", "System.Threading" },
            { "Encoding", "System.Text" },
            { "DateTime", "System" },
            { "TimeSpan", "System" },
            { "Guid", "System" },
            { "Uri", "System" },
            { "Tuple", "System" },
            { "Lazy", "System" },
            { "Action", "System" },
            { "Func", "System" },
        };

        if (commonTypesMap.TryGetValue(ident.Name, out var requiredNamespace))
        {
            if (_importedFileSymbols.Contains(ident.Name))
                return;

            // Check if the namespace is already imported
            if (!_importedNamespaces.Contains(requiredNamespace))
            {
                AddDiagnostic(
                    "NL002",
                    $"I can't find '{ident.Name}' — it looks like a missing import",
                    new Location(ident.Line, ident.Column, _filePath),
                    _config.GetSeverity("NL002"),
                    $"Add 'import {requiredNamespace}' at the top of the file");
            }
        }
    }

    private void CheckMissingImportForType(TypeReference type, int line, int column)
    {
        // Extract the base type name from the type reference
        var typeName = type switch
        {
            SimpleTypeReference simple => simple.Name,
            GenericTypeReference generic => generic.Name,
            NullableTypeReference nullable => GetBaseTypeName(nullable.InnerType),
            ArrayTypeReference array => GetBaseTypeName(array.ElementType),
            _ => null
        };

        if (typeName != null)
        {
            var commonTypesMap = new Dictionary<string, string>
            {
                { "List", "System.Collections.Generic" },
                { "Dictionary", "System.Collections.Generic" },
                { "HashSet", "System.Collections.Generic" },
                { "Queue", "System.Collections.Generic" },
                { "Stack", "System.Collections.Generic" },
                { "LinkedList", "System.Collections.Generic" },
                { "StringBuilder", "System.Text" },
                { "Regex", "System.Text.RegularExpressions" },
                { "File", "System.IO" },
                { "Directory", "System.IO" },
                { "Path", "System.IO" },
                { "Stream", "System.IO" },
                { "HttpClient", "System.Net.Http" },
                { "JsonSerializer", "System.Text.Json" },
                { "Task", "System.Threading.Tasks" },
                { "CancellationToken", "System.Threading" },
            };

            if (commonTypesMap.TryGetValue(typeName, out var requiredNamespace))
            {
                if (_importedFileSymbols.Contains(typeName))
                    return;

                if (!_importedNamespaces.Contains(requiredNamespace))
                {
                    AddDiagnostic(
                        "NL002",
                        $"I can't find '{typeName}' — it looks like a missing import",
                        new Location(line, column, _filePath),
                        _config.GetSeverity("NL002"),
                        $"Add 'import {requiredNamespace}' at the top of the file");
                }
            }
        }
    }

    private string? GetBaseTypeName(TypeReference type)
    {
        return type switch
        {
            SimpleTypeReference simple => simple.Name,
            GenericTypeReference generic => generic.Name,
            NullableTypeReference nullable => GetBaseTypeName(nullable.InnerType),
            ArrayTypeReference array => GetBaseTypeName(array.ElementType),
            _ => null
        };
    }

    /// <summary>
    /// NL010: Track all type names in a type reference as used code identifiers.
    /// This ensures that types used in field declarations, parameter types, return types, etc.
    /// are recognized as usages for unused-import detection.
    /// </summary>
    private void TrackTypeReference(TypeReference? type)
    {
        if (type == null) return;
        switch (type)
        {
            case SimpleTypeReference simple:
                _allCodeIdentifiers.Add(simple.Name);
                break;
            case GenericTypeReference generic:
                _allCodeIdentifiers.Add(generic.Name);
                foreach (var arg in generic.TypeArguments)
                    TrackTypeReference(arg);
                break;
            case NullableTypeReference nullable:
                TrackTypeReference(nullable.InnerType);
                break;
            case ArrayTypeReference array:
                TrackTypeReference(array.ElementType);
                break;
            case TupleTypeReference tuple:
                foreach (var element in tuple.Elements)
                    TrackTypeReference(element.Type);
                break;
            case FunctionTypeReference funcType:
                TrackTypeReference(funcType.ReturnType);
                foreach (var paramType in funcType.ParameterTypes)
                    TrackTypeReference(paramType);
                break;
        }
    }

    private static string? ExtractImportedFileSymbolName(FileImport fileImport)
    {
        if (!string.IsNullOrWhiteSpace(fileImport.Alias))
            return fileImport.Alias;

        var fileName = Path.GetFileNameWithoutExtension(fileImport.Path);
        return string.IsNullOrWhiteSpace(fileName) ? null : fileName;
    }

    private void HandleStringInterpolation(string value)
    {
        // Check if this is an interpolated string ($"..." or $""\"...\""")
        if (!value.StartsWith("$"))
            return;

        // Extract interpolated expressions between { and }
        // Handle both $"..." and $"""...""" formats
        int i = 0;
        if (value.StartsWith("$\"\"\""))
        {
            i = 4; // Start after $"""
        }
        else if (value.StartsWith("$\""))
        {
            i = 2; // Start after $"
        }
        else
        {
            return; // Not an interpolated string
        }

        while (i < value.Length)
        {
            if (value[i] == '{')
            {
                // Found start of interpolation
                int braceDepth = 1;
                i++;
                int exprStart = i;

                // Find the matching closing brace
                while (i < value.Length && braceDepth > 0)
                {
                    if (value[i] == '{')
                        braceDepth++;
                    else if (value[i] == '}')
                        braceDepth--;
                    i++;
                }

                // Extract the expression between braces
                if (braceDepth == 0)
                {
                    string expr = value.Substring(exprStart, i - exprStart - 1).Trim();

                    // Extract identifier(s) from the expression
                    // Simple cases: {name}, {obj.Property}, {list[0]}
                    ExtractIdentifiersFromExpression(expr);
                }
            }
            else
            {
                i++;
            }
        }
    }

    private void ExtractIdentifiersFromExpression(string expr)
    {
        // Simple identifier extraction from interpolated expressions
        // Handles: name, obj.Property, obj?.Property, list[0], obj.Method()

        // Split by common operators and extract the first identifier
        var separators = new[] { '.', '?', '[', '(', ' ', '+', '-', '*', '/', '%', '&', '|', '^', '!', '=', '<', '>', ':', ',' };

        // Find the first identifier (before any operator)
        int firstSeparator = expr.Length;
        foreach (var sep in separators)
        {
            int index = expr.IndexOf(sep);
            if (index >= 0 && index < firstSeparator)
                firstSeparator = index;
        }

        string firstIdentifier = expr.Substring(0, firstSeparator).Trim();

        // Mark the first identifier as used (this is the variable being accessed)
        if (!string.IsNullOrEmpty(firstIdentifier) && IsValidIdentifier(firstIdentifier))
        {
            MarkVariableUsed(firstIdentifier);
        }
    }

    private bool IsValidIdentifier(string name)
    {
        if (string.IsNullOrEmpty(name))
            return false;

        // Must start with letter or underscore
        if (!char.IsLetter(name[0]) && name[0] != '_')
            return false;

        // Rest must be letters, digits, or underscores
        for (int i = 1; i < name.Length; i++)
        {
            if (!char.IsLetterOrDigit(name[i]) && name[i] != '_')
                return false;
        }

        return true;
    }

    // -------------------------------------------------------------------------
    // NL010: Unused Import
    // -------------------------------------------------------------------------

    // Maps namespace → set of type names that belong to it (from the known-types map)
    private static readonly Dictionary<string, HashSet<string>> _knownNamespaceTypes =
        BuildKnownNamespaceTypes();

    private static Dictionary<string, HashSet<string>> BuildKnownNamespaceTypes()
    {
        var map = new Dictionary<string, string>
        {
            // System.Collections.Generic — concrete types
            { "List", "System.Collections.Generic" },
            { "Dictionary", "System.Collections.Generic" },
            { "HashSet", "System.Collections.Generic" },
            { "Queue", "System.Collections.Generic" },
            { "Stack", "System.Collections.Generic" },
            { "LinkedList", "System.Collections.Generic" },
            { "SortedDictionary", "System.Collections.Generic" },
            { "SortedList", "System.Collections.Generic" },
            { "SortedSet", "System.Collections.Generic" },
            { "KeyValuePair", "System.Collections.Generic" },
            // System.Collections.Generic — interfaces
            { "IEnumerable", "System.Collections.Generic" },
            { "IList", "System.Collections.Generic" },
            { "ICollection", "System.Collections.Generic" },
            { "IDictionary", "System.Collections.Generic" },
            { "ISet", "System.Collections.Generic" },
            { "IReadOnlyList", "System.Collections.Generic" },
            { "IReadOnlyCollection", "System.Collections.Generic" },
            { "IReadOnlyDictionary", "System.Collections.Generic" },
            { "IAsyncEnumerable", "System.Collections.Generic" },
            { "IEnumerator", "System.Collections.Generic" },
            { "IComparer", "System.Collections.Generic" },
            { "IEqualityComparer", "System.Collections.Generic" },

            // System.Text
            { "StringBuilder", "System.Text" },
            { "Encoding", "System.Text" },

            // System.Text.RegularExpressions
            { "Regex", "System.Text.RegularExpressions" },
            { "Match", "System.Text.RegularExpressions" },
            { "MatchCollection", "System.Text.RegularExpressions" },

            // System.IO
            { "File", "System.IO" },
            { "Directory", "System.IO" },
            { "Path", "System.IO" },
            { "Stream", "System.IO" },
            { "StreamReader", "System.IO" },
            { "StreamWriter", "System.IO" },
            { "FileStream", "System.IO" },
            { "MemoryStream", "System.IO" },
            { "BinaryReader", "System.IO" },
            { "BinaryWriter", "System.IO" },
            { "FileInfo", "System.IO" },
            { "DirectoryInfo", "System.IO" },
            { "TextReader", "System.IO" },
            { "TextWriter", "System.IO" },

            // System.Net.Http
            { "HttpClient", "System.Net.Http" },
            { "HttpResponseMessage", "System.Net.Http" },
            { "HttpRequestMessage", "System.Net.Http" },
            { "HttpContent", "System.Net.Http" },
            { "StringContent", "System.Net.Http" },

            // System.Text.Json
            { "JsonSerializer", "System.Text.Json" },
            { "JsonSerializerOptions", "System.Text.Json" },
            { "JsonNamingPolicy", "System.Text.Json" },
            { "JsonElement", "System.Text.Json" },
            { "JsonDocument", "System.Text.Json" },
            { "JsonNode", "System.Text.Json" },

            // System.Threading.Tasks
            { "Task", "System.Threading.Tasks" },
            { "ValueTask", "System.Threading.Tasks" },
            { "TaskCompletionSource", "System.Threading.Tasks" },

            // System.Threading
            { "CancellationToken", "System.Threading" },
            { "CancellationTokenSource", "System.Threading" },
            { "SemaphoreSlim", "System.Threading" },
            { "Mutex", "System.Threading" },
            { "Timer", "System.Threading" },
            { "Thread", "System.Threading" },

            // System
            { "DateTime", "System" },
            { "DateTimeOffset", "System" },
            { "TimeSpan", "System" },
            { "Guid", "System" },
            { "Uri", "System" },
            { "Tuple", "System" },
            { "Lazy", "System" },
            { "Action", "System" },
            { "Func", "System" },
            { "Console", "System" },
            { "Math", "System" },
            { "Exception", "System" },
            { "ArgumentException", "System" },
            { "ArgumentNullException", "System" },
            { "ArgumentOutOfRangeException", "System" },
            { "InvalidOperationException", "System" },
            { "NotSupportedException", "System" },
            { "NotImplementedException", "System" },
            { "FormatException", "System" },
            { "OverflowException", "System" },
            { "Random", "System" },
            { "Convert", "System" },
            { "Array", "System" },
            { "Type", "System" },
            { "Attribute", "System" },
            { "Environment", "System" },
            { "Int32", "System" },
            { "String", "System" },
            { "IDisposable", "System" },
            { "IComparable", "System" },
            { "IEquatable", "System" },
            { "EventHandler", "System" },
            { "Nullable", "System" },
            { "Span", "System" },
            { "Memory", "System" },
            { "ReadOnlySpan", "System" },
            { "ReadOnlyMemory", "System" },
            // System.Linq
            { "Enumerable", "System.Linq" },
            { "Queryable", "System.Linq" },
            { "IQueryable", "System.Linq" },
            { "IOrderedEnumerable", "System.Linq" },
            { "IGrouping", "System.Linq" },
            { "ILookup", "System.Linq" },
            { "Lookup", "System.Linq" },
        };

        var result = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var (typeName, ns) in map)
        {
            if (!result.TryGetValue(ns, out var set))
            {
                set = new HashSet<string>(StringComparer.Ordinal);
                result[ns] = set;
            }
            set.Add(typeName);
        }
        return result;
    }

    // Maps namespace → set of extension method / static method names that belong to it.
    // Used to detect import usage through method calls like .Select(), .Where(), etc.
    private static readonly Dictionary<string, HashSet<string>> _knownNamespaceMembers =
        BuildKnownNamespaceMembers();

    private static Dictionary<string, HashSet<string>> BuildKnownNamespaceMembers()
    {
        // Maps method names to their providing namespace.
        // A method name can appear in multiple namespaces — that's fine, we just mark
        // the import as used if the method name appears in member access expressions.
        var map = new (string MethodName, string Namespace)[]
        {
            // System.Linq — LINQ extension methods
            ("Select", "System.Linq"),
            ("SelectMany", "System.Linq"),
            ("Where", "System.Linq"),
            ("OrderBy", "System.Linq"),
            ("OrderByDescending", "System.Linq"),
            ("ThenBy", "System.Linq"),
            ("ThenByDescending", "System.Linq"),
            ("GroupBy", "System.Linq"),
            ("GroupJoin", "System.Linq"),
            ("Join", "System.Linq"),
            ("Distinct", "System.Linq"),
            ("DistinctBy", "System.Linq"),
            ("Union", "System.Linq"),
            ("UnionBy", "System.Linq"),
            ("Intersect", "System.Linq"),
            ("IntersectBy", "System.Linq"),
            ("Except", "System.Linq"),
            ("ExceptBy", "System.Linq"),
            ("Skip", "System.Linq"),
            ("SkipWhile", "System.Linq"),
            ("Take", "System.Linq"),
            ("TakeWhile", "System.Linq"),
            ("First", "System.Linq"),
            ("FirstOrDefault", "System.Linq"),
            ("Last", "System.Linq"),
            ("LastOrDefault", "System.Linq"),
            ("Single", "System.Linq"),
            ("SingleOrDefault", "System.Linq"),
            ("ElementAt", "System.Linq"),
            ("ElementAtOrDefault", "System.Linq"),
            ("Count", "System.Linq"),
            ("LongCount", "System.Linq"),
            ("Sum", "System.Linq"),
            ("Min", "System.Linq"),
            ("MinBy", "System.Linq"),
            ("Max", "System.Linq"),
            ("MaxBy", "System.Linq"),
            ("Average", "System.Linq"),
            ("Aggregate", "System.Linq"),
            ("Any", "System.Linq"),
            ("All", "System.Linq"),
            ("Contains", "System.Linq"),
            ("ToList", "System.Linq"),
            ("ToArray", "System.Linq"),
            ("ToDictionary", "System.Linq"),
            ("ToHashSet", "System.Linq"),
            ("ToLookup", "System.Linq"),
            ("Zip", "System.Linq"),
            ("Concat", "System.Linq"),
            ("Append", "System.Linq"),
            ("Prepend", "System.Linq"),
            ("Reverse", "System.Linq"),
            ("SequenceEqual", "System.Linq"),
            ("DefaultIfEmpty", "System.Linq"),
            ("OfType", "System.Linq"),
            ("Cast", "System.Linq"),
            ("AsEnumerable", "System.Linq"),
            ("Chunk", "System.Linq"),
            // net8+/net9+ additions
            ("SkipLast", "System.Linq"),
            ("TakeLast", "System.Linq"),
            ("TryGetNonEnumeratedCount", "System.Linq"),
            ("CountBy", "System.Linq"),
            ("AggregateBy", "System.Linq"),
            ("Index", "System.Linq"),
            ("Order", "System.Linq"),
            ("OrderDescending", "System.Linq"),
        };

        var result = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var (methodName, ns) in map)
        {
            if (!result.TryGetValue(ns, out var set))
            {
                set = new HashSet<string>(StringComparer.Ordinal);
                result[ns] = set;
            }
            set.Add(methodName);
        }
        return result;
    }

    private void CheckUnusedImports()
    {
        if (!_config.RuleSeverities.ContainsKey("NL010"))
            return;

        foreach (var (ns, line, column, isFile, filePath) in _allImports)
        {
            bool used;
            if (isFile)
            {
                // File import: resolve the imported file and check if any of its
                // exported symbols are used in this file's code identifiers.
                used = IsFileImportUsed(ns, filePath);
            }
            else
            {
                // Namespace import strategy:
                // 1. Check if any known types from this namespace appear in code identifiers.
                // 2. Check if any known extension/static methods from this namespace appear
                //    in member access expressions (e.g. .Select(), .Where()).
                // 3. If namespace is not in any known map, conservatively mark as used.
                var hasKnownTypes = _knownNamespaceTypes.TryGetValue(ns, out var knownTypes);
                var hasKnownMembers = _knownNamespaceMembers.TryGetValue(ns, out var knownMembers);

                if (hasKnownTypes || hasKnownMembers)
                {
                    used = false;
                    if (hasKnownTypes)
                        used = knownTypes!.Any(t => _allCodeIdentifiers.Contains(t));
                    if (!used && hasKnownMembers)
                        used = knownMembers!.Any(m => _allMemberAccessNames.Contains(m));
                }
                else
                {
                    // Unknown namespace — be conservative, don't flag
                    used = true;
                }
            }

            if (!used)
            {
                var label = isFile ? $"import \"{ns}\"" : $"import {ns}";
                AddDiagnostic(
                    "NL010",
                    $"The import '{label}' is not used by any code in this file",
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL010"),
                    $"Remove '{label}' to keep your imports clean");
            }
        }
    }

    private bool IsFileImportUsed(string importSymbol, string? importPath)
    {
        // If the import name itself is used as an identifier, it's used
        if (_allCodeIdentifiers.Contains(importSymbol))
            return true;

        // Try to resolve the file and check if any of its exported symbols are used
        if (importPath != null && _filePath != null)
        {
            var resolvedPath = ResolveFileImportPath(importPath);
            if (resolvedPath != null)
            {
                var exportedSymbols = ExtractExportedSymbols(resolvedPath);
                if (exportedSymbols.Count > 0)
                    return exportedSymbols.Any(s => _allCodeIdentifiers.Contains(s));
            }
        }

        // Can't resolve file — be conservative, don't flag
        return true;
    }

    private string? ResolveFileImportPath(string importPath)
    {
        if (_filePath == null)
            return null;

        var fileDir = Path.GetDirectoryName(_filePath);
        if (fileDir == null)
            return null;

        // Try with and without .nl extension
        var candidates = new[]
        {
            Path.GetFullPath(Path.Combine(fileDir, importPath)),
            Path.GetFullPath(Path.Combine(fileDir, importPath + ".nl")),
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
                return candidate;
        }

        return null;
    }

    private static List<string> ExtractExportedSymbols(string filePath)
    {
        var symbols = new List<string>();
        try
        {
            var source = File.ReadAllText(filePath);
            var lexer = new Lexer(source, filePath);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, filePath, source);
            var result = parser.ParseCompilationUnit();
            if (result.CompilationUnit == null)
                return symbols;

            foreach (var decl in result.CompilationUnit.Declarations)
            {
                var name = decl switch
                {
                    ClassDeclaration c => c.Name,
                    StructDeclaration s => s.Name,
                    RecordDeclaration r => r.Name,
                    InterfaceDeclaration i => i.Name,
                    EnumDeclaration e => e.Name,
                    UnionDeclaration u => u.Name,
                    FunctionDeclaration f => f.Name,
                    TypeAliasDeclaration t => t.Name,
                    _ => null
                };
                if (name != null)
                    symbols.Add(name);
            }
        }
        catch
        {
            // If we can't parse the file, return empty (caller will be conservative)
        }
        return symbols;
    }

    // -------------------------------------------------------------------------
    // NL014: Unnecessary Type Annotation
    // -------------------------------------------------------------------------
    private void CheckUnnecessaryTypeAnnotation(TypeReference declaredType, Expression initializer, int line, int column)
    {
        if (!_config.RuleSeverities.ContainsKey("NL014"))
            return;

        // Only flag the most obvious cases: literal value matches annotation exactly
        var (obvious, literalTypeName) = (declaredType, initializer) switch
        {
            (SimpleTypeReference { Name: "int" }, IntLiteralExpression) => (true, "int"),
            (SimpleTypeReference { Name: "string" }, StringLiteralExpression) => (true, "string"),
            (SimpleTypeReference { Name: "bool" }, BoolLiteralExpression) => (true, "bool"),
            (SimpleTypeReference { Name: "float" }, FloatLiteralExpression) => (true, "float"),
            (SimpleTypeReference { Name: "double" }, FloatLiteralExpression) => (true, "double"),
            _ => (false, (string?)null)
        };

        if (obvious && literalTypeName != null)
        {
            AddDiagnostic(
                "NL014",
                $"You don't need the type annotation here — N# already infers '{literalTypeName}' from the value",
                new Location(line, column, _filePath),
                _config.GetSeverity("NL014"),
                $"Remove ': {literalTypeName}' to keep things clean — the type is obvious from the initializer");
        }
    }

    // -------------------------------------------------------------------------
    // NL015: Prefer Const
    // -------------------------------------------------------------------------
    private void CheckPreferConst()
    {
        if (!_config.RuleSeverities.ContainsKey("NL015"))
            return;

        foreach (var kvp in _letDeclarations)
        {
            var name = kvp.Key;
            var (line, column, hasInitializer, inLambda) = kvp.Value;

            // Skip variables without initializers (they MUST be assigned later)
            if (!hasInitializer)
                continue;

            // Skip variables inside lambdas (closures capture semantics differ)
            if (inLambda)
                continue;

            // Skip if the variable was ever assigned after declaration
            if (_assignedVariables.Contains(name))
                continue;

            // Skip if the variable is never read — NL001 (unused variable) will handle that case.
            // Firing both NL001 and NL015 for the same variable is redundant noise.
            if (!_usedVariables.Contains(name))
                continue;

            AddDiagnostic(
                "NL015",
                $"Variable '{name}' is never reassigned after its declaration",
                new Location(line, column, _filePath),
                _config.GetSeverity("NL015"),
                $"Use 'const {name}' instead of 'let {name}' to make the intent clear and prevent accidental reassignment");
        }
    }

    // -------------------------------------------------------------------------
    // NL016: Redundant Null Check (conservative: only `new` / literal initialisers)
    // -------------------------------------------------------------------------
    private void CheckRedundantNullCheckOnNewOrLiteral(Expression condition)
    {
        if (!_config.RuleSeverities.ContainsKey("NL016"))
            return;

        if (condition is not BinaryExpression binary)
            return;

        if (binary.Operator != BinaryOperator.NotEqual && binary.Operator != BinaryOperator.Equal)
            return;

        var isNullCheck = binary.Right is NullLiteralExpression || binary.Left is NullLiteralExpression;
        if (!isNullCheck)
            return;

        var checkedExpr = binary.Right is NullLiteralExpression ? binary.Left : binary.Right;

        // Only flag when the expression being checked was just created via `new` or a non-null literal
        var alwaysNonNull = checkedExpr switch
        {
            NewExpression => true,
            IntLiteralExpression => true,
            FloatLiteralExpression => true,
            BoolLiteralExpression => true,
            ArrayLiteralExpression => true,
            _ => false
        };

        if (alwaysNonNull)
        {
            var verb = binary.Operator == BinaryOperator.NotEqual ? "always true" : "always false";
            AddDiagnostic(
                "NL016",
                $"This null check is redundant — the expression was just created and can never be null (this is {verb})",
                new Location(condition.Line, condition.Column, _filePath),
                _config.GetSeverity("NL016"),
                "Remove the null check — the value cannot be null");
        }
    }

    // -------------------------------------------------------------------------
    // NL018: Prefer Readonly — class members only
    // -------------------------------------------------------------------------
    private void VisitClassLikeMembers(List<Declaration> members, string typeName, int typeLine, int typeColumn)
    {
        if (!_config.RuleSeverities.ContainsKey("NL018"))
        {
            // If rule is disabled just visit normally
            foreach (var member in members)
                VisitDeclaration(member);
            return;
        }

        // Collect field names that are writable (no readonly modifier yet)
        var writableFields = new HashSet<string>();
        foreach (var member in members)
        {
            if (member is FieldDeclaration fd
                && !fd.Modifiers.HasFlag(Modifiers.Readonly)
                && !fd.Modifiers.HasFlag(Modifiers.Const)
                && !fd.PropertyModifier.HasFlag(PropertyModifier.Readonly))
            {
                writableFields.Add(fd.Name);
            }
        }

        // Reset field assignment tracking for this class scope
        var outerFieldAssignments = _classFieldAssignments;
        _classFieldAssignments = new Dictionary<string, (bool InCtor, bool Elsewhere)>();
        foreach (var f in writableFields)
            _classFieldAssignments[f] = (false, false);

        // Visit all members (constructors will set _inConstructor = true)
        foreach (var member in members)
            VisitDeclaration(member);

        // Emit NL018 for fields only assigned in ctor (or initializer) and nowhere else
        foreach (var kvp in _classFieldAssignments)
        {
            var fieldName = kvp.Key;
            var (inCtor, elsewhere) = kvp.Value;
            if (inCtor && !elsewhere)
            {
                // Find original field declaration for location
                var fieldDecl = members.OfType<FieldDeclaration>().FirstOrDefault(f => f.Name == fieldName);
                var loc = fieldDecl != null
                    ? new Location(fieldDecl.Line, fieldDecl.Column, _filePath)
                    : new Location(typeLine, typeColumn, _filePath);

                AddDiagnostic(
                    "NL018",
                    $"Field '{fieldName}' is only assigned in the constructor and never changed after that",
                    loc,
                    _config.GetSeverity("NL018"),
                    $"Mark '{fieldName}' as 'readonly' to make the intent clear and prevent accidental mutation");
            }
        }

        _classFieldAssignments = outerFieldAssignments;
    }

    private void TrackFieldAssignment(Expression target)
    {
        // Only meaningful inside a class context — check if target is a simple field name
        // or a `this.fieldName` access
        string? fieldName = target switch
        {
            IdentifierExpression id => id.Name,
            MemberAccessExpression { Object: IdentifierExpression { Name: "this" }, MemberName: var m } => m,
            _ => null
        };

        if (fieldName == null)
            return;

        if (!_classFieldAssignments.ContainsKey(fieldName))
            return;

        var (inCtor, elsewhere) = _classFieldAssignments[fieldName];
        if (_inConstructor)
            _classFieldAssignments[fieldName] = (true, elsewhere);
        else
            _classFieldAssignments[fieldName] = (inCtor, true);
    }
}
