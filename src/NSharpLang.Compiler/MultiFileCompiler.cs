using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.ILCompiler;

namespace NSharpLang.Compiler;

/// <summary>
/// Handles compilation of multiple .nl files into a single assembly.
/// Uses a shared parse/analyze pipeline for IL emission and C# export.
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
    private readonly Dictionary<string, string> _exportedCSharpFiles = new();
    private readonly List<CompilerError> _allErrors = new();
    private readonly Analyzer _sharedAnalyzer;
    private readonly bool _debugLoggingEnabled;
    private readonly BindingMap _projectBindings = new();
    private readonly Dictionary<string, string> _projectTypeDeclarationFiles = new(StringComparer.Ordinal);

    /// <summary>
    /// Public read-only accessors for code intelligence tooling.
    /// These expose the intermediate products of compilation (ASTs, semantic models)
    /// without requiring C# export or IL emission.
    /// </summary>
    public IReadOnlyDictionary<string, CompilationUnit> CompilationUnits => _compilationUnits;
    public IReadOnlyDictionary<string, SemanticModel> SemanticModels => _semanticModels;
    public Analyzer SharedAnalyzer => _sharedAnalyzer;
    public IReadOnlyList<CompilerError> AllErrors => _allErrors;
    public IReadOnlyList<string> SourceFiles => _sourceFiles;
    public string ProjectRoot => _projectRoot;

    /// <summary>
    /// The project-level semantic index built from all analyzed files.
    /// Contains the merged BindingMap and type-declaration-to-file mapping.
    /// Available after <see cref="CompileForAnalysis"/>, <see cref="ExportToCSharp"/>,
    /// or <see cref="CompileToIlAssembly"/> completes.
    /// </summary>
    public ProjectIndex ProjectIndex => new(_projectBindings, _projectTypeDeclarationFiles);

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

                // Save semantic model for C# export.
                _semanticModels[sourceFile] = result.SemanticModel;

                // Capture auto-resolved namespaces for C# using-directive generation.
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

                // Merge type-declaration-to-file mapping into the project index
                foreach (var (typeName, filePath) in _sharedAnalyzer.GetTypeDeclarationFiles())
                {
                    _projectTypeDeclarationFiles[typeName] = filePath;
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
    /// Export all files to C#.
    /// </summary>
    private void ExportAllFilesToCSharp()
    {
        // Collect all string enum names across all files so each transpiler
        // can emit correct when-guard patterns for cross-file enum references
        var allStringEnumNames = new HashSet<string>();
        foreach (var cu in _compilationUnits.Values)
            foreach (var enm in cu.Declarations.OfType<EnumDeclaration>()
                .Where(e => e.Type == EnumType.String))
                allStringEnumNames.Add(enm.Name);

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

                var exporter = new Transpiler(compilationUnit, _config, semanticModel, sourceFile, autoNamespaces, allStringEnumNames);
                var csharpCode = exporter.Transpile();

                _exportedCSharpFiles[sourceFile] = csharpCode;
            }
            catch (Exception ex)
            {
                _allErrors.Add(new CompilerError(
                    ErrorCode.InvalidSyntax,
                    $"Failed to export {sourceFile} to C#: {ex.Message}",
                    0,
                    0,
                    ErrorSeverity.Error
                ));
            }
        }
    }

    /// <summary>
    /// Parse and analyze all files without exporting or emitting IL.
    /// This is the fast path for code intelligence queries — skips code generation
    /// which is unnecessary when you only need ASTs, semantic models, and diagnostics.
    /// All files with a non-null CompilationUnit are analyzed, even if they had parse errors,
    /// so we can report both syntax and semantic diagnostics in a single pass.
    /// </summary>
    public void CompileForAnalysis()
    {
        ParseAllFiles();
        AnalyzeAllFiles();
    }

    /// <summary>
    /// Export all files to C# and return results.
    /// </summary>
    public CSharpExportResult ExportToCSharp()
    {
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] ExportToCSharp START");

        // Pass 1: Parse
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] ParseAllFiles START");
        ParseAllFiles();
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] ParseAllFiles END");

        // Pass 2: Analyze — always run, even if some files had parse errors.
        // Files that parsed successfully are analyzed so we can report both
        // syntax and semantic diagnostics in a single compilation pass.
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] AnalyzeAllFiles START");
        AnalyzeAllFiles();
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] AnalyzeAllFiles END");

        // Stop before export if there are any errors.
        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] Errors found, returning before export");
            return new CSharpExportResult(
                false,
                _allErrors,
                new Dictionary<string, string>()
            );
        }

        // Pass 3: Export to C#.
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] ExportAllFilesToCSharp START");
        ExportAllFilesToCSharp();
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] ExportAllFilesToCSharp END");

        var success = !_allErrors.Any(e => e.Severity == ErrorSeverity.Error);
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] ExportToCSharp END (success={success})");
        return new CSharpExportResult(success, _allErrors, _exportedCSharpFiles);
    }

    public MultiFileCompilationResult CompileToIlAssembly(string assemblyName, string outputPath)
    {
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] CompileToIlAssembly START");

        ParseAllFiles();
        AnalyzeAllFiles();

        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                null);
        }

        try
        {
            var mergedCompilationUnit = CreateMergedCompilationUnit();
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? _projectRoot);

            var compiler = new ILCompiler.ILCompiler(mergedCompilationUnit, assemblyName, outputPath, _config);
            compiler.Compile();
        }
        catch (Exception ex)
        {
            _allErrors.Add(new CompilerError(
                ErrorCode.InvalidSyntax,
                $"Failed to emit IL assembly '{assemblyName}': {ex.Message}",
                0,
                0,
                ErrorSeverity.Error));
        }

        var success = !_allErrors.Any(e => e.Severity == ErrorSeverity.Error);
        return new MultiFileCompilationResult(
            success,
            _allErrors,
            success ? outputPath : null);
    }

    private CompilationUnit CreateMergedCompilationUnit()
    {
        var orderedUnits = _sourceFiles
            .Select(sourceFile => _compilationUnits.TryGetValue(sourceFile, out var compilationUnit) ? compilationUnit : null)
            .Where(compilationUnit => compilationUnit != null)
            .Cast<CompilationUnit>()
            .ToList();
        return NamespaceQualifiedCompilationMerger.Merge(orderedUnits);
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
/// Result of exporting a project to C#.
/// </summary>
public record CSharpExportResult(
    bool Success,
    IEnumerable<CompilerError> Errors,
    Dictionary<string, string> ExportedFiles
);

/// <summary>
/// Result of multi-file IL compilation.
/// </summary>
public record MultiFileCompilationResult(
    bool Success,
    IEnumerable<CompilerError> Errors,
    string? OutputAssemblyPath = null
);
