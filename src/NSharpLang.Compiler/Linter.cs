using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
    string? Suggestion = null,
    int Length = 1);

/// <summary>
/// Linter configuration from .editorconfig
/// </summary>
public class LinterConfig
{
    public Dictionary<string, DiagnosticSeverity> RuleSeverities { get; set; } = new();
    public HashSet<string> DisabledRules { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    public static LinterConfig Default()
    {
        return new LinterConfig
        {
            RuleSeverities = DiagnosticCatalog.LinterDescriptors
                .ToDictionary(descriptor => descriptor.Code, descriptor => descriptor.DefaultSeverity, StringComparer.OrdinalIgnoreCase)
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

                        // Handle dotnet_diagnostic.NL001.severity = error
                        if (key.StartsWith("dotnet_diagnostic.") && key.EndsWith(".severity"))
                        {
                            var ruleCode = key["dotnet_diagnostic.".Length..^".severity".Length];

                            var severity = value.ToLower() switch
                            {
                                "error" => DiagnosticSeverity.Error,
                                "warning" => DiagnosticSeverity.Warning,
                                "info" or "suggestion" => DiagnosticSeverity.Info,
                                "none" or "silent" => (DiagnosticSeverity?)null,
                                _ => (DiagnosticSeverity?)null
                            };

                            if (severity.HasValue)
                            {
                                config.DisabledRules.Remove(ruleCode);
                                config.RuleSeverities[ruleCode] = severity.Value;
                            }
                            else if (value.Equals("none", StringComparison.OrdinalIgnoreCase)
                                     || value.Equals("silent", StringComparison.OrdinalIgnoreCase))
                            {
                                config.DisabledRules.Add(ruleCode);
                                config.RuleSeverities.Remove(ruleCode);
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
            : DiagnosticCatalog.GetDefaultSeverity(ruleCode);
    }

    public bool IsRuleEnabled(string ruleCode)
        => !DisabledRules.Contains(ruleCode);
}

/// <summary>
/// Main linter class that analyzes code and returns diagnostics
/// </summary>
public class Linter
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
        return visitor.Diagnostics;
    }

    internal static string[] NormalizeSourceLines(string? sourceText)
        => string.IsNullOrEmpty(sourceText)
            ? Array.Empty<string>()
            : sourceText.Replace("\r\n", "\n", StringComparison.Ordinal)
                .Replace('\r', '\n')
                .Split('\n');
}

/// <summary>
/// AST visitor that performs linting checks
/// </summary>
internal class LintVisitor
{
    private readonly string? _filePath;
    private readonly LinterConfig _config;
    private readonly Dictionary<int, HashSet<string>> _suppressedDiagnosticsByLine;
    private readonly string[] _sourceLines;
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
    private readonly List<(string Namespace, int Line, int Column, int Length, bool IsFile, string? FilePath)> _allImports = new();
    private readonly HashSet<string> _allCodeIdentifiers = new();
    private readonly HashSet<string> _allMemberAccessNames = new();
    private readonly Stack<HashSet<string>> _typeMemberNameScopes = new();

    // NL012: Track parameters separately so we can report them without polluting the unused-variable check.
    // _currentFunctionParams/_currentFunctionParamUsages always refer to the innermost (current) function's frame.
    private List<(string Name, int Line, int Column)> _currentFunctionParams = new();
    private HashSet<string> _currentFunctionParamUsages = new();

    // NL012: A stack of parameter frames for every enclosing function. Reads inside a nested local
    // function or lambda must be able to credit a captured parameter of any *enclosing* function — not
    // just the innermost one — or valid closures wrongly trip the build-blocking "parameter never read".
    // The last element is the innermost frame (mirrors _currentFunctionParams/_currentFunctionParamUsages).
    private readonly List<(List<(string Name, int Line, int Column)> Params, HashSet<string> Usages, Dictionary<string, (int Line, int Column, bool Used)>? Scope)> _paramFrames = new();

    public List<Diagnostic> Diagnostics => _diagnostics;

    public LintVisitor(string? filePath = null, string? sourceText = null, LinterConfig? config = null)
    {
        _filePath = filePath;
        _config = config ?? LinterConfig.Default();
        _suppressedDiagnosticsByLine = BuildSuppressions(filePath, sourceText);
        _sourceLines = Linter.NormalizeSourceLines(sourceText);
    }

    public void Visit(CompilationUnit unit)
    {
        // Track imported namespaces for NL002 and NL010
        foreach (var import in unit.Imports)
        {
            _importedNamespaces.Add(import.Namespace);
            var (nsColumn, nsLength) = ResolveNamespaceImportSpan(import);
            _allImports.Add((import.Namespace, import.Line, nsColumn, nsLength, false, null));
        }

        foreach (var fileImport in unit.FileImports.OfType<FileImport>())
        {
            var importedSymbol = ExtractImportedFileSymbolName(fileImport);
            if (!string.IsNullOrWhiteSpace(importedSymbol))
            {
                _importedFileSymbols.Add(importedSymbol!);
                _allImports.Add((importedSymbol!, fileImport.Line, fileImport.DiagnosticColumn, fileImport.DiagnosticLength, true, fileImport.Path));
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
            if (!used
                && !_usedVariables.Contains(varName)
                && varName != "_"
                && !varName.StartsWith("_", StringComparison.Ordinal))
            {
                AddDiagnostic(
                    "NL001",
                    $"Variable '{varName}' is declared but never read",
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL001"),
                    $"If this is intentional, prefix it with '_' to indicate it's unused: '_{varName}'",
                    varName.Length);
            }
        }
    }

    private void AddDiagnostic(string code, string message, Location location, DiagnosticSeverity severity, string? suggestion = null, int length = 0)
    {
        if (!_config.IsRuleEnabled(code))
            return;

        if (IsSuppressed(code, location.Line))
            return;

        var sourceLine = SourceLine(location.Line);
        var span = DiagnosticSpanResolver.Resolve(sourceLine, location.Column, length);
        var diagnosticLocation = span.Column == location.Column
            ? location
            : location with { Column = span.Column };

        _diagnostics.Add(new Diagnostic(code, message, diagnosticLocation, severity, suggestion, span.Length));
    }

    private string SourceLine(int oneBasedLine)
        => oneBasedLine > 0 && oneBasedLine <= _sourceLines.Length
            ? _sourceLines[oneBasedLine - 1]
            : string.Empty;

    // NL010: resolve the diagnostic span for a namespace import to the imported
    // namespace path (e.g. `System.Linq`) rather than the `import` keyword. The
    // directive only records the statement (keyword) column, so we step past the
    // keyword and any whitespace to land on the first character of the path.
    private (int Column, int Length) ResolveNamespaceImportSpan(ImportDirective import)
    {
        const string keyword = "import";
        var sourceLine = SourceLine(import.Line);
        var keywordStart = import.Column - 1;

        // Without the source line we cannot locate the path. Defer to the resolver
        // (length 0) so it underlines a token rather than overshooting a short line.
        if (sourceLine.Length == 0 || keywordStart < 0 || keywordStart >= sourceLine.Length)
            return (import.Column, 0);

        var pathStart = keywordStart + keyword.Length;
        while (pathStart < sourceLine.Length && char.IsWhiteSpace(sourceLine[pathStart]))
            pathStart++;

        // Fall back to the keyword position if the line is malformed (e.g. the
        // path wraps to the next line); the resolver still underlines a token.
        if (pathStart >= sourceLine.Length)
            return (import.Column, 0);

        return (pathStart + 1, import.Namespace.Length);
    }

    private (Location Location, int Length) GetBlockOwnerDiagnosticSpan(BlockStatement block)
    {
        var sourceLine = SourceLine(block.Line);
        if (string.IsNullOrEmpty(sourceLine))
            return (new Location(block.Line, block.Column, _filePath), 1);

        var searchEnd = block.Column > 0
            ? Math.Clamp(block.Column - 1, 0, sourceLine.Length)
            : sourceLine.Length;
        var prefix = sourceLine[..searchEnd];

        var bestColumn = 0;
        var bestKeyword = string.Empty;
        foreach (var keyword in BlockOwnerKeywords)
        {
            var column = FindKeywordColumn(prefix, keyword);
            if (column > bestColumn)
            {
                bestColumn = column;
                bestKeyword = keyword;
            }
        }

        return bestColumn > 0
            ? (new Location(block.Line, bestColumn, _filePath), bestKeyword.Length)
            : (new Location(block.Line, block.Column, _filePath), 1);
    }

    private static readonly string[] BlockOwnerKeywords =
    [
        "foreach",
        "finally",
        "throws",
        "catch",
        "while",
        "switch",
        "assert",
        "using",
        "lock",
        "else",
        "func",
        "test",
        "try",
        "for",
        "if"
    ];

    private static int FindKeywordColumn(string text, string keyword)
    {
        var searchIndex = text.Length;
        while (searchIndex > 0)
        {
            var index = text.LastIndexOf(keyword, searchIndex - 1, StringComparison.Ordinal);
            if (index < 0)
                return 0;

            var beforeIsIdentifier = index > 0 && IsIdentifierPart(text[index - 1]);
            var afterIndex = index + keyword.Length;
            var afterIsIdentifier = afterIndex < text.Length && IsIdentifierPart(text[afterIndex]);
            if (!beforeIsIdentifier && !afterIsIdentifier)
                return index + 1;

            searchIndex = index;
        }

        return 0;
    }

    private static bool IsIdentifierPart(char ch)
        => char.IsLetterOrDigit(ch) || ch == '_';

    private int FindTokenColumn(int oneBasedLine, string token, int fallbackColumn)
    {
        if (string.IsNullOrWhiteSpace(token))
            return fallbackColumn;

        var sourceLine = SourceLine(oneBasedLine);
        var index = sourceLine.IndexOf(token, StringComparison.Ordinal);
        return index >= 0 ? index + 1 : fallbackColumn;
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
                VisitStatement(ctor.Body);
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

        // NL012: Save outer param tracking state and push a fresh frame for this function.
        var outerParams = _currentFunctionParams;
        var outerParamUsages = _currentFunctionParamUsages;
        _currentFunctionParams = new List<(string Name, int Line, int Column)>();
        _currentFunctionParamUsages = new HashSet<string>();
        _paramFrames.Add((_currentFunctionParams, _currentFunctionParamUsages, null));

        if (func.Body != null)
        {
            PushScope();

            // Add parameters to scope; track for NL012
            foreach (var param in func.Parameters)
            {
                var paramLine = param.Line > 0 ? param.Line : func.Line;
                var paramColumn = param.Column > 0 ? param.Column : func.Column;
                DeclareVariable(param.Name, paramLine, paramColumn);
                MarkVariableUsed(param.Name, creditEnclosingParameter: false); // Parameters exempt from NL001
                _currentFunctionParams.Add((param.Name, paramLine, paramColumn));
            }

            // NL012: record the scope that holds this function's parameters so a read can be
            // attributed to the parameter it lexically resolves to (a shadowing local binds the
            // name in a nearer scope and must not credit this parameter).
            _paramFrames[_paramFrames.Count - 1] = (_currentFunctionParams, _currentFunctionParamUsages, _declaredVariables);

            VisitStatement(func.Body);

            // NL012: Report unused parameters
            CheckUnusedParameters(func.Name);

            PopScope();
        }
        else if (func.ExpressionBody != null)
        {
            PushScope();
            foreach (var param in func.Parameters)
            {
                var paramLine = param.Line > 0 ? param.Line : func.Line;
                var paramColumn = param.Column > 0 ? param.Column : func.Column;
                DeclareVariable(param.Name, paramLine, paramColumn);
                MarkVariableUsed(param.Name, creditEnclosingParameter: false);
                _currentFunctionParams.Add((param.Name, paramLine, paramColumn));
            }
            // NL012: record the parameter scope (see the func.Body branch for rationale).
            _paramFrames[_paramFrames.Count - 1] = (_currentFunctionParams, _currentFunctionParamUsages, _declaredVariables);
            VisitExpression(func.ExpressionBody);

            // NL012: Report unused parameters
            CheckUnusedParameters(func.Name);

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
                    new Location(func.Line, FindTokenColumn(func.Line, func.Name, func.Column), _filePath),
                    _config.GetSeverity("NL004"),
                    $"Either add an 'await' expression inside '{func.Name}', or remove the 'async' modifier if this function doesn't need to be asynchronous");
            }
        }

        // Restore state
        _inAsyncFunction = wasInAsync;
        _hasAwaitInFunction = hadAwait;
        _paramFrames.RemoveAt(_paramFrames.Count - 1);
        _currentFunctionParams = outerParams;
        _currentFunctionParamUsages = outerParamUsages;
    }

    private void CheckUnusedParameters(string functionName)
    {
        if (!_config.RuleSeverities.ContainsKey("NL012"))
            return;

        foreach (var (name, line, column) in _currentFunctionParams)
        {
            // Underscore-prefixed parameters are an explicit "intentionally unused" signal
            // (e.g. an interface/override that doesn't need the value). Honor it so this
            // build-blocking error never fires for parameters the author already opted out of.
            if (name == "_" || name.StartsWith("_", StringComparison.Ordinal))
                continue;

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
        VisitWithTypeMemberScope(classDecl.Members, classDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in classDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitStruct(StructDeclaration structDecl)
    {
        VisitWithTypeMemberScope(structDecl.Members, structDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in structDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitRecord(RecordDeclaration recordDecl)
    {
        VisitWithTypeMemberScope(recordDecl.Members, recordDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in recordDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitInterface(InterfaceDeclaration interfaceDecl)
    {
        foreach (var member in interfaceDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitWithTypeMemberScope(
        List<Declaration> members,
        List<Parameter>? primaryConstructorParameters,
        Action visit)
    {
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var member in members)
        {
            switch (member)
            {
                case FieldDeclaration field:
                    names.Add(field.Name);
                    break;
                case PropertyDeclaration property:
                    names.Add(property.Name);
                    break;
                case FunctionDeclaration function:
                    names.Add(function.Name);
                    break;
            }
        }

        if (primaryConstructorParameters != null)
        {
            foreach (var parameter in primaryConstructorParameters)
            {
                names.Add(parameter.Name);
            }
        }

        _typeMemberNameScopes.Push(names);
        try
        {
            visit();
        }
        finally
        {
            _typeMemberNameScopes.Pop();
        }
    }

    private void VisitStatement(Statement statement)
    {
        switch (statement)
        {
            case VariableDeclarationStatement varDecl:
                // NL010: Track type references in variable declarations
                TrackTypeReference(varDecl.Type);
                var initializerHasParserError = ContainsParserErrorPlaceholder(varDecl.Initializer);
                // VariableDeclarationStatement stores the identifier location, including
                // shorthand declarations like `name := value`.
                var nameColumn = varDecl.Column;
                if (!initializerHasParserError)
                {
                    DeclareVariable(varDecl.Name, varDecl.Line, nameColumn);
                }

                if (varDecl.Initializer != null && !initializerHasParserError)
                {
                    VisitExpression(varDecl.Initializer);
                }
                break;

            case BlockStatement block:
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
                MarkVariableUsed(foreachStmt.VariableName, creditEnclosingParameter: false); // Loop variables are considered used
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
                    var catchBlockIsEmpty = catchClause.Block.Statements.Count == 0;

                    // NL011: Empty catch block
                    if (catchBlockIsEmpty)
                    {
                        var (location, length) = GetBlockOwnerDiagnosticSpan(catchClause.Block);
                        AddDiagnostic(
                            "NL011",
                            "This catch block is empty — exceptions will be silently swallowed",
                            location,
                            _config.GetSeverity("NL011"),
                            "Log the error, handle it, or add a comment explaining why it's safe to ignore",
                            length);
                    }

                    PushScope();
                    if (catchClause.VariableName != null)
                    {
                        DeclareVariable(catchClause.VariableName, catchClause.Block.Line, catchClause.Block.Column);
                        MarkVariableUsed(catchClause.VariableName, creditEnclosingParameter: false); // Exception variables are considered used
                    }
                    if (!catchBlockIsEmpty)
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

            case AssertStatement assertStmt:
                VisitExpression(assertStmt.Condition);
                if (assertStmt.Message != null)
                    VisitExpression(assertStmt.Message);
                break;

            case AssertThrowsStatement assertThrows:
                TrackTypeReference(assertThrows.ExceptionType);
                VisitStatement(assertThrows.Body);
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
                if (ContainsParserErrorPlaceholder(tupleDecl.Initializer))
                    break;

                foreach (var name in tupleDecl.Names)
                {
                    if (name != "_") // Don't track discards
                        DeclareVariable(name, tupleDecl.Line, tupleDecl.Column);
                }
                VisitExpression(tupleDecl.Initializer);
                break;

            case AwaitForEachStatement awaitForeach:
                // `await foreach` is a genuine await usage — record it so NL004 does not
                // misfire on async functions that only consume async streams.
                _hasAwaitInFunction = true;
                VisitExpression(awaitForeach.Collection); // Visit collection in outer scope FIRST
                PushScope();
                DeclareVariable(awaitForeach.VariableName, awaitForeach.Line, awaitForeach.Column);
                MarkVariableUsed(awaitForeach.VariableName, creditEnclosingParameter: false);
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

                    // Check for direct value-type comparisons (e.g., comparing an int literal
                    // against null). These can never be null, so the check is unnecessary.
                    if (checkedExpr is IntLiteralExpression ||
                        checkedExpr is FloatLiteralExpression ||
                        checkedExpr is CharLiteralExpression ||
                        checkedExpr is BoolLiteralExpression)
                    {
                        var typeName = checkedExpr switch
                        {
                            IntLiteralExpression => "int",
                            FloatLiteralExpression => "float",
                            CharLiteralExpression => "char",
                            BoolLiteralExpression => "bool",
                            _ => "value type"
                        };

                        // Underline the offending value-type operand, not the whole condition.
                        AddDiagnostic(
                            "NL003",
                            $"This null check is unnecessary — '{typeName}' is a value type and can never be null",
                            new Location(checkedExpr.Line, checkedExpr.Column, _filePath),
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
                VisitExpression(binary.Left);
                VisitExpression(binary.Right);
                break;

            case UnaryExpression unary:
                VisitExpression(unary.Operand);
                break;

            case MustExpression must:
                VisitExpression(must.Expression);
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
                VisitExpression(assignment.Target);
                VisitExpression(assignment.Value);
                break;

            case TernaryExpression ternary:
                VisitExpression(ternary.Condition);
                VisitExpression(ternary.ThenExpression);
                VisitExpression(ternary.ElseExpression);
                break;

            case LambdaExpression lambda:
                PushScope();
                foreach (var param in lambda.Parameters)
                {
                    DeclareVariable(param.Name, lambda.Line, lambda.Column);
                    MarkVariableUsed(param.Name, creditEnclosingParameter: false);
                }
                if (lambda.BlockBody != null)
                    VisitStatement(lambda.BlockBody);
                if (lambda.ExpressionBody != null)
                    VisitExpression(lambda.ExpressionBody);
                PopScope();
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

    private static bool ContainsParserErrorPlaceholder(Expression? expression)
    {
        return expression switch
        {
            null => false,
            IdentifierExpression { Name: "<error>" } => true,
            MemberAccessExpression { MemberName: "<error>" } => true,
            InterpolatedStringExpression interpolatedString => interpolatedString.Parts
                .OfType<InterpolatedStringHole>()
                .Any(hole => ContainsParserErrorPlaceholder(hole.Expression)),
            RangeExpression range => ContainsParserErrorPlaceholder(range.Start) ||
                                     ContainsParserErrorPlaceholder(range.End),
            MemberAccessExpression memberAccess => ContainsParserErrorPlaceholder(memberAccess.Object),
            CallExpression call => ContainsParserErrorPlaceholder(call.Callee) ||
                                   call.Arguments.Any(arg => ContainsParserErrorPlaceholder(arg.Value)),
            BinaryExpression nestedBinary => ContainsParserErrorPlaceholder(nestedBinary.Left) ||
                                             ContainsParserErrorPlaceholder(nestedBinary.Right),
            AssignmentExpression assignment => ContainsParserErrorPlaceholder(assignment.Target) ||
                                               ContainsParserErrorPlaceholder(assignment.Value),
            LambdaExpression lambda => ContainsParserErrorPlaceholder(lambda.ExpressionBody),
            UnaryExpression unary => ContainsParserErrorPlaceholder(unary.Operand),
            MustExpression must => ContainsParserErrorPlaceholder(must.Expression),
            ParenthesizedExpression parenthesized => ContainsParserErrorPlaceholder(parenthesized.Inner),
            CheckedExpression checkedExpression => ContainsParserErrorPlaceholder(checkedExpression.Expression),
            UncheckedExpression uncheckedExpression => ContainsParserErrorPlaceholder(uncheckedExpression.Expression),
            IndexAccessExpression indexAccess => ContainsParserErrorPlaceholder(indexAccess.Object) ||
                                                 ContainsParserErrorPlaceholder(indexAccess.Index),
            CastExpression cast => ContainsParserErrorPlaceholder(cast.Expression),
            IsExpression isExpression => ContainsParserErrorPlaceholder(isExpression.Expression),
            AwaitExpression awaitExpression => ContainsParserErrorPlaceholder(awaitExpression.Expression),
            ThrowExpression throwExpression => ContainsParserErrorPlaceholder(throwExpression.Expression),
            TernaryExpression ternary => ContainsParserErrorPlaceholder(ternary.Condition) ||
                                         ContainsParserErrorPlaceholder(ternary.ThenExpression) ||
                                         ContainsParserErrorPlaceholder(ternary.ElseExpression),
            ArrayLiteralExpression array => array.Elements.Any(ContainsParserErrorPlaceholder),
            TupleExpression tuple => tuple.Elements.Any(element => ContainsParserErrorPlaceholder(element.Value)),
            NewExpression @new => @new.ConstructorArguments.Any(arg => ContainsParserErrorPlaceholder(arg.Value)) ||
                                  ContainsParserErrorPlaceholder(@new.Initializer),
            ObjectInitializerExpression initializer => initializer.Properties.Any(property =>
                ContainsParserErrorPlaceholder(property.IndexExpression) ||
                ContainsParserErrorPlaceholder(property.Value)),
            WithExpression withExpression => ContainsParserErrorPlaceholder(withExpression.Target) ||
                                             withExpression.Properties.Any(property =>
                                                 ContainsParserErrorPlaceholder(property.IndexExpression) ||
                                                 ContainsParserErrorPlaceholder(property.Value)),
            SpreadExpression spread => ContainsParserErrorPlaceholder(spread.Expression),
            MatchExpression match => ContainsParserErrorPlaceholder(match.Value) ||
                                     match.Cases.Any(matchCase =>
                                         ContainsParserErrorPlaceholder(matchCase.Guard) ||
                                         ContainsParserErrorPlaceholder(matchCase.Expression)),
            NameofExpression nameofExpression => ContainsParserErrorPlaceholder(nameofExpression.Target),
            _ => false
        };
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

    private void MarkVariableUsed(string name, bool creditEnclosingParameter = true)
    {
        // NL012: Track parameter usages.
        if (creditEnclosingParameter)
        {
            // A genuine read of 'name' counts as a use of the parameter it lexically resolves to —
            // including a parameter captured by a nested local function or lambda. Resolve to the
            // nearest scope that binds the name (innermost first), then credit only the parameter
            // frame whose dedicated parameter scope IS that resolved scope. This makes captured-
            // parameter reads count (fixing the build-blocking "parameter never read" false
            // positive) while a shadowing local/loop/catch/lambda binding — which lives in a nearer
            // scope — correctly prevents the enclosing parameter from being marked read.
            Dictionary<string, (int Line, int Column, bool Used)>? resolvedScope =
                _declaredVariables.ContainsKey(name) ? _declaredVariables : null;
            if (resolvedScope == null)
            {
                foreach (var scope in _scopeStack)
                {
                    if (scope.ContainsKey(name))
                    {
                        resolvedScope = scope;
                        break;
                    }
                }
            }
            if (resolvedScope != null)
            {
                for (int i = _paramFrames.Count - 1; i >= 0; i--)
                {
                    if (ReferenceEquals(_paramFrames[i].Scope, resolvedScope)
                        && _paramFrames[i].Params.Any(p => p.Name == name))
                    {
                        _paramFrames[i].Usages.Add(name);
                        break;
                    }
                }
            }
        }
        else if (_currentFunctionParams.Any(p => p.Name == name))
        {
            // Binding/declaration site (a parameter, loop variable, catch variable, or lambda
            // parameter being introduced). Preserve the original behavior of only consulting the
            // current function's parameter table, so re-declaring a name never marks an enclosing
            // parameter as read.
            _currentFunctionParamUsages.Add(name);
        }

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
        if (_typeMemberNameScopes.Any(scope => scope.Contains(ident.Name)))
        {
            return;
        }

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
            UnionTypeReference union => union.Arms.Select(GetBaseTypeName).FirstOrDefault(name => name != null),
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
            UnionTypeReference union => union.Arms.Select(GetBaseTypeName).FirstOrDefault(name => name != null),
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
            case UnionTypeReference union:
                foreach (var arm in union.Arms)
                    TrackTypeReference(arm);
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

        foreach (var (ns, line, column, length, isFile, filePath) in _allImports)
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
                var label = isFile ? $"import \"{filePath ?? ns}\"" : $"import {ns}";
                AddDiagnostic(
                    "NL010",
                    $"The import '{label}' is not used by any code in this file",
                    new Location(line, column, _filePath),
                    _config.GetSeverity("NL010"),
                    $"Remove '{label}' to keep your imports clean",
                    length);
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

        // Only flag when the expression being checked was just created via `new` or an
        // array literal. Scalar value-type literals (int/float/char/bool) are handled by
        // NL003 instead, so we deliberately exclude them here to avoid double-reporting.
        var alwaysNonNull = checkedExpr switch
        {
            NewExpression => true,
            ArrayLiteralExpression => true,
            _ => false
        };

        if (alwaysNonNull)
        {
            var verb = binary.Operator == BinaryOperator.NotEqual ? "always true" : "always false";
            // Underline the always-non-null operand rather than the whole condition.
            AddDiagnostic(
                "NL016",
                $"This null check is redundant — the expression was just created and can never be null (this is {verb})",
                new Location(checkedExpr.Line, checkedExpr.Column, _filePath),
                _config.GetSeverity("NL016"),
                "Remove the null check — the value cannot be null");
        }
    }

}
