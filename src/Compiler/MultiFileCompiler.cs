using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Compiler;

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
    private readonly Dictionary<string, string> _transpiledFiles = new();
    private readonly List<CompilerError> _allErrors = new();

    public MultiFileCompiler(string projectRoot, ProjectConfig? config = null)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
        _sourceFiles = DiscoverSourceFiles(projectRoot, _config);
    }

    public MultiFileCompiler(IEnumerable<string> sourceFiles, string projectRoot, ProjectConfig? config = null)
    {
        _projectRoot = projectRoot;
        _config = config;
        _sourceFiles = sourceFiles.ToList();
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
                var source = File.ReadAllText(sourceFile);
                var lexer = new Lexer(source, sourceFile);
                var tokens = lexer.Tokenize();
                var parser = new Parser(tokens, sourceFile);
                var compilationUnit = parser.ParseCompilationUnit();

                _compilationUnits[sourceFile] = compilationUnit;
            }
            catch (Exception ex)
            {
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
    /// WORKAROUND: We need to process imports from all files to make symbols available.
    /// For now, we'll compile all files into a single virtual file that can see all declarations.
    /// </summary>
    private void AnalyzeAllFiles()
    {
        // For now, analyze each file independently
        // This works because the Analyzer's import system already handles cross-file references
        // when we use proper import statements
        foreach (var kvp in _compilationUnits)
        {
            var sourceFile = kvp.Key;
            var compilationUnit = kvp.Value;

            try
            {
                var analyzer = new Analyzer();

                // Load system assemblies
                analyzer.LoadSystemAssemblies();

                // Load assemblies from project configuration
                analyzer.LoadFromProjectConfig(_config);

                var result = analyzer.Analyze(compilationUnit, sourceFile, _projectRoot);

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
                var transpiler = new Transpiler(compilationUnit, _config);
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
        // Pass 1: Parse
        ParseAllFiles();

        // Stop if parse errors
        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                new Dictionary<string, string>()
            );
        }

        // Pass 2: Analyze
        AnalyzeAllFiles();

        // Stop if analysis errors
        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                new Dictionary<string, string>()
            );
        }

        // Pass 2: Transpile
        TranspileAllFiles();

        // Return results
        var success = !_allErrors.Any(e => e.Severity == ErrorSeverity.Error);
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
