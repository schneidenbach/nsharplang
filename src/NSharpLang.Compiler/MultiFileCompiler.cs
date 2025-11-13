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
    private readonly string _projectRoot;
    private readonly ProjectConfig? _config;
    private readonly List<string> _sourceFiles;
    private readonly Dictionary<string, CompilationUnit> _compilationUnits = new();
    private readonly Dictionary<string, SemanticModel> _semanticModels = new();
    private readonly Dictionary<string, string> _transpiledFiles = new();
    private readonly List<CompilerError> _allErrors = new();
    private readonly Analyzer _sharedAnalyzer;

    public MultiFileCompiler(string projectRoot, ProjectConfig? config = null)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
        _sourceFiles = DiscoverSourceFiles(projectRoot, _config);

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
        var logPath = Path.Combine(_projectRoot, "compile-debug.log");
        foreach (var sourceFile in _sourceFiles)
        {
            try
            {
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}]   Parsing {Path.GetFileName(sourceFile)}\n");
                var source = File.ReadAllText(sourceFile);
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}]     Read file ({source.Length} bytes)\n");
                var lexer = new Lexer(source, sourceFile);
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}]     Lexer created\n");
                var tokens = lexer.Tokenize();
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}]     Tokenized ({tokens.Count} tokens)\n");
                var parser = new Parser(tokens, sourceFile, source);  // Pass source code
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}]     Parser created\n");
                var parseResult = parser.ParseCompilationUnit();
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}]     Parsed compilation unit\n");

                // Add parse errors to our error list
                _allErrors.AddRange(parseResult.Errors);

                // Store compilation unit (even if null, for consistency)
                if (parseResult.CompilationUnit != null)
                {
                    _compilationUnits[sourceFile] = parseResult.CompilationUnit;
                }
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}]   Done parsing {Path.GetFileName(sourceFile)}\n");
            }
            catch (Exception ex)
            {
                File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}]   EXCEPTION: {ex.Message}\n");
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
    /// Pass 2: Analyze all files with complete symbol table
    /// Uses a shared Analyzer instance that was initialized once with system assemblies and project config.
    /// This prevents the performance issue of reloading assemblies for each file.
    /// </summary>
    private void AnalyzeAllFiles()
    {
        // Analyze each file using the shared analyzer instance
        // The Analyzer's import system handles cross-file references via proper import statements
        foreach (var kvp in _compilationUnits)
        {
            var sourceFile = kvp.Key;
            var compilationUnit = kvp.Value;

            try
            {
                // Use the shared analyzer (assemblies already loaded in constructor)
                var result = _sharedAnalyzer.Analyze(compilationUnit, sourceFile, _projectRoot);

                // Save semantic model for transpilation phase
                _semanticModels[sourceFile] = result.SemanticModel;

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

                var transpiler = new Transpiler(compilationUnit, _config, semanticModel);
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
    /// Compile all files and return results
    /// </summary>
    public MultiFileCompilationResult Compile()
    {
        var logPath = Path.Combine(_projectRoot, "compile-debug.log");
        File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Compile START\n");

        // Pass 1: Parse
        File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] ParseAllFiles START\n");
        ParseAllFiles();
        File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] ParseAllFiles END\n");

        // Stop if parse errors
        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Parse errors found, returning\n");
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                new Dictionary<string, string>()
            );
        }

        // Pass 2: Analyze
        File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] AnalyzeAllFiles START\n");
        AnalyzeAllFiles();
        File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] AnalyzeAllFiles END\n");

        // Stop if analysis errors
        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Analysis errors found, returning\n");
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                new Dictionary<string, string>()
            );
        }

        // Pass 2: Transpile
        File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] TranspileAllFiles START\n");
        TranspileAllFiles();
        File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] TranspileAllFiles END\n");

        // Return results
        var success = !_allErrors.Any(e => e.Severity == ErrorSeverity.Error);
        File.AppendAllText(logPath, $"[{DateTime.Now:HH:mm:ss.fff}] Compile END (success={success})\n");
        return new MultiFileCompilationResult(success, _allErrors, _transpiledFiles);
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
