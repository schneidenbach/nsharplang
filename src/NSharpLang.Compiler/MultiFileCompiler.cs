using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Handles compilation of multiple .nl files into a single assembly.
/// Uses two-pass compilation: Pass 1 collects symbols, Pass 2 analyzes and transpiles.
/// </summary>
public class MultiFileCompiler
{
    private const string DebugLogEnvVar = "NSHARP_DEBUG_LOG";
    private readonly string _projectRoot;
    private readonly ProjectConfig? _config;
    private readonly List<string> _sourceFiles;
    private readonly Dictionary<string, CompilationUnit> _compilationUnits = new();
    private readonly Dictionary<string, SemanticModel> _semanticModels = new();
    private readonly Dictionary<string, HashSet<string>> _autoResolvedNamespaces = new(); // file -> namespaces auto-resolved
    private readonly Dictionary<string, string> _transpiledFiles = new();
    private readonly List<CompilerError> _allErrors = new();
    private readonly Analyzer _sharedAnalyzer;
    private readonly bool _debugLoggingEnabled;
    private readonly BindingMap _projectBindings = new();

    /// <summary>
    /// Public read-only accessors for code intelligence tooling.
    /// These expose the intermediate products of compilation (ASTs, semantic models)
    /// without requiring a full transpile pass.
    /// </summary>
    public IReadOnlyDictionary<string, CompilationUnit> CompilationUnits => _compilationUnits;
    public IReadOnlyDictionary<string, SemanticModel> SemanticModels => _semanticModels;
    public Analyzer SharedAnalyzer => _sharedAnalyzer;
    public IReadOnlyList<CompilerError> AllErrors => _allErrors;
    public IReadOnlyList<string> SourceFiles => _sourceFiles;
    public string ProjectRoot => _projectRoot;
    public BindingMap ProjectBindings => _projectBindings;

    public MultiFileCompiler(string projectRoot, ProjectConfig? config = null)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
        _sourceFiles = DiscoverSourceFiles(projectRoot, _config);
        _debugLoggingEnabled = IsDebugLoggingEnabled();

        // Initialize shared analyzer ONCE with system assemblies and project config
        _sharedAnalyzer = new Analyzer();
        _sharedAnalyzer.LoadSystemAssemblies();
        _sharedAnalyzer.LoadFromProjectConfig(_config, _projectRoot);
    }

    public MultiFileCompiler(IEnumerable<string> sourceFiles, string projectRoot, ProjectConfig? config = null)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
        _sourceFiles = sourceFiles.ToList();
        _debugLoggingEnabled = IsDebugLoggingEnabled();

        // Initialize shared analyzer ONCE with system assemblies and project config
        _sharedAnalyzer = new Analyzer();
        _sharedAnalyzer.LoadSystemAssemblies();
        _sharedAnalyzer.LoadFromProjectConfig(_config, _projectRoot);
    }

    /// <summary>
    /// Discovers all .nl files in the project directory using ProjectConfig exclude patterns
    /// (excludes .tests.nl files)
    /// </summary>
    private static List<string> DiscoverSourceFiles(string projectRoot, ProjectConfig config)
    {
        if (!Directory.Exists(projectRoot))
        {
            return new List<string>();
        }

        // Use ProjectConfig's GetSourceFiles method which respects exclude patterns
        return config.GetSourceFiles(projectRoot, includeTests: false)
            .Select(f => Path.GetFullPath(f))
            .ToList();
    }

    /// <summary>
    /// Pass 1: Parse all source files into ASTs
    /// </summary>
    private void ParseAllFiles()
    {
        foreach (var sourceFile in _sourceFiles)
        {
            try
            {
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   Parsing {Path.GetFileName(sourceFile)}");
                var source = File.ReadAllText(sourceFile);
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Read file ({source.Length} bytes)");
                var lexer = new Lexer(source, sourceFile);
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Lexer created");
                var tokens = lexer.Tokenize();
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Tokenized ({tokens.Count} tokens)");
                var parser = new Parser(tokens, sourceFile, source);  // Pass source code
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Parser created");
                var parseResult = parser.ParseCompilationUnit();
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Parsed compilation unit");

                // Add parse errors to our error list
                _allErrors.AddRange(parseResult.Errors);

                // Store compilation unit (even if null, for consistency)
                if (parseResult.CompilationUnit != null)
                {
                    _compilationUnits[sourceFile] = parseResult.CompilationUnit;
                }
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   Done parsing {Path.GetFileName(sourceFile)}");
            }
            catch (Exception ex)
            {
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   EXCEPTION: {ex.Message}");
                _allErrors.Add(new CompilerError(
                    ErrorCode.InvalidSyntax,
                    $"Failed to parse {sourceFile}: {ex.Message}",
                    0,
                    0,
                    ErrorSeverity.Error
                ));
            }
        }
    }

    /// <summary>
    /// Build the project-level symbol table from all parsed compilation units.
    /// Maps symbol names to their ProjectSymbolInfo (including source file and namespace).
    /// This enables automatic cross-file symbol resolution without explicit imports.
    /// </summary>
    private Dictionary<string, List<ProjectSymbolInfo>> BuildProjectSymbolTable()
    {
        var table = new Dictionary<string, List<ProjectSymbolInfo>>();

        foreach (var kvp in _compilationUnits)
        {
            var sourceFile = kvp.Key;
            var compilationUnit = kvp.Value;

            var symbols = Analyzer.ExtractProjectSymbols(compilationUnit, sourceFile);
            foreach (var symbol in symbols)
            {
                if (!table.TryGetValue(symbol.Name, out var list))
                {
                    list = new List<ProjectSymbolInfo>();
                    table[symbol.Name] = list;
                }
                list.Add(symbol);
            }
        }

        return table;
    }

    /// <summary>
    /// Pass 2: Analyze all files with complete symbol table
    /// Uses a shared Analyzer instance that was initialized once with system assemblies and project config.
    /// This prevents the performance issue of reloading assemblies for each file.
    /// </summary>
    private void AnalyzeAllFiles()
    {
        // Build project symbol table for auto-discovery and set it on the shared analyzer
        var projectSymbols = BuildProjectSymbolTable();
        _sharedAnalyzer.SetProjectSymbols(projectSymbols);

        // Analyze each file using the shared analyzer instance
        // The Analyzer's import system handles cross-file references via proper import statements
        // Project symbols provide fallback auto-discovery for unimported cross-file types
        foreach (var kvp in _compilationUnits)
        {
            var sourceFile = kvp.Key;
            var compilationUnit = kvp.Value;

            try
            {
                // Use the shared analyzer (assemblies already loaded in constructor)
                var result = _sharedAnalyzer.Analyze(compilationUnit, sourceFile, _projectRoot, File.ReadAllText(sourceFile));

                // Save semantic model for transpilation phase
                _semanticModels[sourceFile] = result.SemanticModel;

                // Capture auto-resolved namespaces for transpiler using-directive generation
                var autoNs = _sharedAnalyzer.GetAutoResolvedNamespaces();
                if (autoNs.Count > 0)
                {
                    _autoResolvedNamespaces[sourceFile] = autoNs;
                }

                // Merge binding map for cross-file semantic references
                if (result.Bindings != null)
                {
                    _projectBindings.Merge(result.Bindings);
                }

                // Collect errors
                foreach (var error in result.Errors)
                {
                    _allErrors.Add(error);
                }
            }
            catch (Exception ex)
            {
                _allErrors.Add(new CompilerError(
                    ErrorCode.InvalidSyntax,
                    $"Failed to analyze {sourceFile}: {ex.Message}",
                    0,
                    0,
                    ErrorSeverity.Error
                ));
            }
        }
    }

    /// <summary>
    /// Pass 2: Transpile all files to C#
    /// </summary>
    private void TranspileAllFiles()
    {
        foreach (var kvp in _compilationUnits)
        {
            var sourceFile = kvp.Key;
            var compilationUnit = kvp.Value;

            try
            {
                // Get the semantic model for this file (if available)
                _semanticModels.TryGetValue(sourceFile, out var semanticModel);

                // Get auto-resolved namespaces for this file (if any)
                _autoResolvedNamespaces.TryGetValue(sourceFile, out var autoNamespaces);

                var transpiler = new Transpiler(compilationUnit, _config, semanticModel, sourceFile, autoNamespaces);
                var csharpCode = transpiler.Transpile();

                _transpiledFiles[sourceFile] = csharpCode;
            }
            catch (Exception ex)
            {
                _allErrors.Add(new CompilerError(
                    ErrorCode.InvalidSyntax,
                    $"Failed to transpile {sourceFile}: {ex.Message}",
                    0,
                    0,
                    ErrorSeverity.Error
                ));
            }
        }
    }

    /// <summary>
    /// Parse and analyze all files without transpiling.
    /// This is the fast path for code intelligence queries — skips the transpile phase
    /// which is unnecessary when you only need ASTs, semantic models, and diagnostics.
    /// </summary>
    public void CompileForAnalysis()
    {
        ParseAllFiles();
        if (!_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            AnalyzeAllFiles();
        }
    }

    /// <summary>
    /// Compile all files and return results
    /// </summary>
    public MultiFileCompilationResult Compile()
    {
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] Compile START");

        // Pass 1: Parse
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] ParseAllFiles START");
        ParseAllFiles();
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] ParseAllFiles END");

        // Stop if parse errors
        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] Parse errors found, returning");
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                new Dictionary<string, string>()
            );
        }

        // Pass 2: Analyze
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] AnalyzeAllFiles START");
        AnalyzeAllFiles();
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] AnalyzeAllFiles END");

        // Stop if analysis errors
        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] Analysis errors found, returning");
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                new Dictionary<string, string>()
            );
        }

        // Pass 2: Transpile
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] TranspileAllFiles START");
        TranspileAllFiles();
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] TranspileAllFiles END");

        // Return results
        var success = !_allErrors.Any(e => e.Severity == ErrorSeverity.Error);
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] Compile END (success={success})");
        return new MultiFileCompilationResult(success, _allErrors, _transpiledFiles);
    }

    private static bool IsDebugLoggingEnabled()
    {
        var value = Environment.GetEnvironmentVariable(DebugLogEnvVar);
        return string.Equals(value, "1", StringComparison.Ordinal) ||
            string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
    }

    private void AppendDebugLog(string message)
    {
        if (!_debugLoggingEnabled)
        {
            return;
        }

        var logPath = Path.Combine(_projectRoot, "compile-debug.log");
        File.AppendAllText(logPath, message + Environment.NewLine);
    }

    /// <summary>
    /// Get the entry file from config or use Program.nl by default
    /// </summary>
    public string? GetEntryFile()
    {
        if (_config?.Entry != null)
        {
            var entryPath = Path.Combine(_projectRoot, _config.Entry);
            if (File.Exists(entryPath))
            {
                return Path.GetFullPath(entryPath);
            }
        }

        // Default to Program.nl
        var defaultEntry = _sourceFiles.FirstOrDefault(f =>
            Path.GetFileName(f).Equals("Program.nl", StringComparison.OrdinalIgnoreCase));

        return defaultEntry;
    }
}

/// <summary>
/// Result of multi-file compilation
/// </summary>
public record MultiFileCompilationResult(
    bool Success,
    IEnumerable<CompilerError> Errors,
    Dictionary<string, string> TranspiledFiles
);
