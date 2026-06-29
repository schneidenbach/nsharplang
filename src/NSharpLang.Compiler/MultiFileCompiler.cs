using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Columnar;
using NSharpLang.Compiler.Performance;

namespace NSharpLang.Compiler;

/// <summary>
/// Handles compilation of multiple .nl files into a single assembly.
/// Uses a shared parse/analyze pipeline for analysis and IL emission.
/// </summary>
public class MultiFileCompiler
{
    private const string DebugLogEnvVar = "NSHARP_DEBUG_LOG";
    private const int MaxDisplayedImportCycleNodes = 10;
    private const int MaxReportedImportCycles = 20;
    private readonly string _projectRoot;
    private readonly ProjectConfig? _config;
    private readonly List<string> _sourceFiles;
    private readonly Dictionary<string, CompilationUnit> _compilationUnits = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, SemanticModel> _semanticModels = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<CompilerError> _allErrors = new();
    private readonly Analyzer _sharedAnalyzer;
    private readonly bool _debugLoggingEnabled;
    private readonly IReadOnlyDictionary<string, string> _sourceTextOverrides;
    private readonly IReadOnlySet<string> _preprocessorSymbols;
    private readonly Dictionary<string, string> _sourceTexts = new(StringComparer.OrdinalIgnoreCase);
    private readonly BindingMap _projectBindings = new();
    private readonly Dictionary<string, string> _projectTypeDeclarationFiles = new(StringComparer.Ordinal);
    private readonly HashSet<string> _reportedImportCycles = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _filesInReportedImportCycles = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _resolvedFileImportDiagnosticKeys = new(StringComparer.OrdinalIgnoreCase);
    private readonly PerformanceFactStore _performanceFacts = new();

    /// <summary>
    /// Public read-only accessors for code intelligence tooling.
    /// These expose the intermediate products of compilation (ASTs, semantic models)
    /// without requiring IL emission.
    /// </summary>
    public IReadOnlyDictionary<string, CompilationUnit> CompilationUnits => _compilationUnits;
    public IReadOnlyDictionary<string, SemanticModel> SemanticModels => _semanticModels;
    public Analyzer SharedAnalyzer => _sharedAnalyzer;
    public IReadOnlyList<CompilerError> AllErrors => _allErrors;
    public IReadOnlyList<string> SourceFiles => _sourceFiles;
    public IReadOnlyDictionary<string, string> SourceTexts => _sourceTexts;
    public string ProjectRoot => _projectRoot;

    /// <summary>
    /// The project-level semantic index built from all analyzed files.
    /// Contains the merged BindingMap and type-declaration-to-file mapping.
    /// Available after <see cref="CompileForAnalysis"/> or <see cref="CompileToIlAssembly"/> completes.
    /// </summary>
    public ProjectIndex ProjectIndex => new(_projectBindings, _projectTypeDeclarationFiles);

    /// <summary>
    /// Performance facts (including AOT-blocker facts) recorded during analysis, keyed by
    /// source position. Populated by <see cref="CompileForAnalysis"/> and <see cref="CompileToIlAssembly"/>.
    /// </summary>
    public PerformanceFactStore PerformanceFacts => _performanceFacts;

    private SystemsReport _systemsReport = SystemsReport.Empty(null);

    /// <summary>
    /// Systems N# effect/policy report discovered during analysis.
    /// </summary>
    public SystemsReport SystemsReport => _systemsReport;

    /// <summary>
    /// When true, AOT-blocker facts are promoted to build-blocking errors and the IL emitter
    /// is told to annotate public APIs containing blockers with <c>[Requires*]</c> attributes.
    /// Set by <c>nlc build --aot</c> / <c>nlc check --aot</c>. Off by default so ordinary
    /// builds are never affected.
    /// </summary>
    public bool AotMode { get; set; }

    public MultiFileCompiler(string projectRoot, ProjectConfig? config = null)
        : this(projectRoot, config, sourceTextOverrides: null)
    {
}

    public MultiFileCompiler(string projectRoot, ProjectConfig? config, IReadOnlyDictionary<string, string>? sourceTextOverrides)
        : this(BuildProjectInputs(projectRoot, config, sourceTextOverrides), projectRoot, config)
    {
    }

    public MultiFileCompiler(IEnumerable<string> sourceFiles, string projectRoot, ProjectConfig? config = null)
        : this(sourceFiles, projectRoot, config, sourceTextOverrides: null)
    {
    }

    public MultiFileCompiler(IEnumerable<string> sourceFiles, string projectRoot, ProjectConfig? config, IReadOnlyDictionary<string, string>? sourceTextOverrides)
        : this(BuildExplicitInputs(sourceFiles, config, sourceTextOverrides), projectRoot, config)
    {
    }

    private MultiFileCompiler(MultiFileCompilerInputs inputs, string projectRoot, ProjectConfig? config)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
        _preprocessorSymbols = inputs.PreprocessorSymbols;
        _sourceTextOverrides = inputs.SourceTextOverrides;
        _sourceFiles = inputs.SourceFiles;
        _debugLoggingEnabled = IsDebugLoggingEnabled();

        // Initialize shared analyzer ONCE with system assemblies and project config
        _sharedAnalyzer = new Analyzer();
        _sharedAnalyzer.LoadSystemAssemblies();
        _sharedAnalyzer.LoadFromProjectConfig(_config, _projectRoot);
    }

    private static MultiFileCompilerInputs BuildProjectInputs(
        string projectRoot,
        ProjectConfig? config,
        IReadOnlyDictionary<string, string>? sourceTextOverrides)
    {
        var (paths, texts) = CopySourceTextOverrides(sourceTextOverrides);
        return MultiFileCompilerInputBuilder.BuildFromProject(
            projectRoot,
            config ?? ProjectFileParser.CreateDefault(),
            paths,
            texts);
    }

    private static MultiFileCompilerInputs BuildExplicitInputs(
        IEnumerable<string> sourceFiles,
        ProjectConfig? config,
        IReadOnlyDictionary<string, string>? sourceTextOverrides)
    {
        var (paths, texts) = CopySourceTextOverrides(sourceTextOverrides);
        return MultiFileCompilerInputBuilder.Build(
            sourceFiles.ToList(),
            config ?? ProjectFileParser.CreateDefault(),
            paths,
            texts);
    }

    private static (string[] Paths, string[] Texts) CopySourceTextOverrides(IReadOnlyDictionary<string, string>? sourceTextOverrides)
    {
        if (sourceTextOverrides == null || sourceTextOverrides.Count == 0)
        {
            return (Array.Empty<string>(), Array.Empty<string>());
        }

        var paths = new string[sourceTextOverrides.Count];
        var texts = new string[sourceTextOverrides.Count];
        var index = 0;
        foreach (var (path, text) in sourceTextOverrides)
        {
            paths[index] = path;
            texts[index] = text;
            index++;
        }

        return (paths, texts);
    }

    private string ReadSourceText(string sourceFile)
    {
        var fullPath = Path.GetFullPath(sourceFile);
        return _sourceTextOverrides.TryGetValue(fullPath, out var text)
            ? text
            : File.ReadAllText(fullPath);
    }

    private void ReadAllSourceTexts()
    {
        foreach (var sourceFile in _sourceFiles)
        {
            var fullPath = Path.GetFullPath(sourceFile);
            if (!_sourceTexts.ContainsKey(fullPath))
            {
                _sourceTexts[fullPath] = ReadSourceText(sourceFile);
            }
        }
    }

    /// <summary>
    /// Pass 1: Parse all source files into ASTs
    /// </summary>
    private void ParseAllFiles()
    {
        foreach (var sourceFile in _sourceFiles)
        {
            {
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   Parsing {Path.GetFileName(sourceFile)}");
                var source = ReadSourceText(sourceFile);
                _sourceTexts[Path.GetFullPath(sourceFile)] = source;
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Read file ({source.Length} bytes)");
                var lexer = new Lexer(source, sourceFile);
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Lexer created");
                var tokens = lexer.Tokenize();
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Tokenized ({tokens.Count} tokens)");
                // Resolve conditional-compilation directives (#if/#elif/#else/#endif) so the
                // parser and all downstream stages only see the live branch.
                tokens = Preprocessor.Process(tokens, _preprocessorSymbols, sourceFile, _allErrors);
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Preprocessed ({tokens.Count} tokens)");
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
        }
    }

    /// <summary>
    /// Detect circular file-import graphs before semantic analysis so project checks
    /// fail with a bounded, actionable diagnostic instead of relying on per-file
    /// shallow checks.
    /// </summary>
    private void DetectCircularFileImports()
    {
        var sourceFiles = _compilationUnits.Keys.ToList();
        var graph = ImportGraphBuilder.Build(
            sourceFiles,
            CollectFileImportGraphEntries(),
            _projectRoot);
        foreach (var diagnosticKey in graph.ResolvedDiagnosticKeys)
        {
            _resolvedFileImportDiagnosticKeys.Add(diagnosticKey);
        }

        var cycles = ImportGraphCycleDetector.Detect(
            sourceFiles,
            graph.EdgesByFile,
            _projectRoot,
            MaxDisplayedImportCycleNodes);
        foreach (var cycle in cycles)
        {
            ImportCycleDiagnosticReporter.Report(
                cycle,
                _reportedImportCycles,
                _filesInReportedImportCycles,
                _allErrors,
                MaxReportedImportCycles,
                TryReadSourceLine(cycle.Edge.SourceFile, cycle.Edge.Line));
        }
    }

    private List<FileImportGraphEntry> CollectFileImportGraphEntries()
    {
        var fileImports = new List<FileImportGraphEntry>();

        foreach (var (sourceFile, compilationUnit) in _compilationUnits)
        {
            foreach (var fileImport in compilationUnit.FileImports.OfType<FileImport>())
            {
                fileImports.Add(new FileImportGraphEntry(
                    sourceFile,
                    fileImport.Path,
                    fileImport.Line,
                    fileImport.DiagnosticColumn,
                    fileImport.DiagnosticLength));
            }
        }

        return fileImports;
    }

    private string? TryReadSourceLine(string filePath, int line)
    {
        if (line <= 0)
            return null;

            return CodeIntelligenceTextUtilities.GetSourceLine(ReadSourceText(filePath), line);
    }

    /// <summary>
    /// Pass 2: Analyze all files with complete symbol table
    /// Uses a shared Analyzer instance that was initialized once with system assemblies and project config.
    /// This prevents the performance issue of reloading assemblies for each file.
    /// </summary>
    private void AnalyzeAllFiles()
    {
        _sharedAnalyzer.SetProjectSourceTexts(_sourceTexts);

        // Analyze each file using the shared analyzer instance
        // The Analyzer's import system handles cross-file references via proper import statements
        foreach (var kvp in _compilationUnits)
        {
            var sourceFile = kvp.Key;
            var compilationUnit = kvp.Value;

            {
                // Use the shared analyzer (assemblies already loaded in constructor)
                var result = _sharedAnalyzer.Analyze(compilationUnit, sourceFile, _projectRoot, ReadSourceText(sourceFile));

                // Save semantic model for project-wide analysis and emission.
                _semanticModels[sourceFile] = result.SemanticModel;

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

                // Collect errors. Project-level import graph resolution reports complete cycle paths
                // before analysis; suppress the analyzer's older shallow NL703 duplicates and
                // stale NL701 import-not-found errors for case-only/open-buffer imports already in the graph.
                foreach (var error in result.Errors)
                {
                    if (ImportGraphDiagnosticSuppressor.ShouldSuppressAnalyzerDiagnostic(
                            error,
                            _filesInReportedImportCycles,
                            _resolvedFileImportDiagnosticKeys))
                        continue;

                    _allErrors.Add(error);
                }
            }
        }

        AnalyzeSystemsPolicy();
    }

    private void AnalyzeSystemsPolicy()
    {
        // The semantic models from the Analyzer pass drive call-site resolution: systems
        // callee facts bind to the declaration each call resolved to, never to a name match.
        // Files whose analysis failed have no model; their calls are conservatively unknown.
        _systemsReport = new SystemsAnalyzer(_projectRoot, _config).Analyze(_compilationUnits, _performanceFacts, _semanticModels);
        foreach (var finding in _systemsReport.Findings)
        {
            _allErrors.Add(finding.ToCompilerError());
        }
    }

    private void AddStrictLintDiagnosticsFromParsedSources()
    {
        var filesWithParseErrors = _allErrors
            .Where(error => error.Severity == ErrorSeverity.Error && !string.IsNullOrWhiteSpace(error.FileName))
            .Select(error => Path.GetFullPath(error.FileName!))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var sourceFile in _sourceFiles)
        {
            var fullPath = Path.GetFullPath(sourceFile);
            if (filesWithParseErrors.Contains(fullPath))
                continue;

            if (!_compilationUnits.TryGetValue(sourceFile, out var compilationUnit))
                continue;

            var source = _sourceTexts.TryGetValue(fullPath, out var cachedSource)
                ? cachedSource
                : ReadSourceText(sourceFile);
            var fileDir = Path.GetDirectoryName(fullPath) ?? _projectRoot;
            var linter = new Linter(LinterConfig.FromEditorConfig(fileDir));
            foreach (var diagnostic in linter.Lint(compilationUnit, fullPath, source)
                         .Where(diagnostic => diagnostic.Severity == DiagnosticSeverity.Error))
            {
                _allErrors.Add(new CompilerError(
                    ErrorCode.InvalidSyntax,
                    diagnostic.Message,
                    diagnostic.Location.Line,
                    diagnostic.Location.Column,
                    ErrorSeverity.Error)
                {
                    FileName = fullPath,
                    Length = Math.Max(diagnostic.Length, 1),
                    Suggestion = diagnostic.Suggestion,
                    SourceSnippet = TryReadSourceLine(fullPath, diagnostic.Location.Line)?.TrimEnd(),
                    DiagnosticIdOverride = diagnostic.Code,
                    DocsUrl = DiagnosticCatalog.DocsUrlFor(diagnostic.Code)
                });
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
        DetectCircularFileImports();
        AnalyzeAllFiles();
    }

    public MultiFileCompilationResult CompileToIlAssembly(
        string assemblyName,
        string outputPath,
        bool validateStrictLint = false,
        bool validateWithLegacyAnalysis = true)
    {
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] CompileToIlAssembly START");

        var runLegacyValidation = validateWithLegacyAnalysis || validateStrictLint;
        if (!runLegacyValidation)
        {
            ReadAllSourceTexts();
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? _projectRoot);
            if (!TryEmitWithColumnarBackend(assemblyName, outputPath))
            {
                _allErrors.Add(ColumnarEmissionDiagnostics.RequiredEmitOnlyEmissionError(assemblyName));
            }

            var emitOnlySuccess = !_allErrors.Any(e => e.Severity == ErrorSeverity.Error);
            return new MultiFileCompilationResult(
                emitOnlySuccess,
                _allErrors,
                emitOnlySuccess ? outputPath : null);
        }

        ParseAllFiles();
        var errorsBeforeLint = _allErrors.Count(error => error.Severity == ErrorSeverity.Error);
        if (validateStrictLint)
        {
            AddStrictLintDiagnosticsFromParsedSources();
            if (_allErrors.Skip(errorsBeforeLint).Any(error => error.Severity == ErrorSeverity.Error))
            {
                return new MultiFileCompilationResult(
                    false,
                    _allErrors,
                null);
            }
        }

        DetectCircularFileImports();
        AnalyzeAllFiles();

        if (_allErrors.Any(e => e.Severity == ErrorSeverity.Error))
        {
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                null);
        }

        {
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? _projectRoot);

            // STAGE 5 ROUTING: when the columnar backend can emit the whole program, route emission through it
            // (a standalone columnar pipeline that owns assembly emission without materializing an object AST).
            if (!TryEmitWithColumnarBackend(assemblyName, outputPath))
            {
                if (AotMode)
                {
                    _allErrors.Add(ColumnarEmissionDiagnostics.RequiredAotEmissionError(assemblyName));
                }
                else if (RequiresColumnarSoaEmission())
                {
                    _allErrors.Add(ColumnarEmissionDiagnostics.RequiredSoaEmissionError(assemblyName));
                }
                else
                {
                    _allErrors.Add(ColumnarEmissionDiagnostics.RequiredEmissionError(assemblyName));
                }
            }
        }

        var success = !_allErrors.Any(e => e.Severity == ErrorSeverity.Error);
        return new MultiFileCompilationResult(
            success,
            _allErrors,
            success ? outputPath : null);
    }

    // Try to emit the whole assembly via the standalone columnar backend. The assembly is
    // `assemblyName` and the type is "Program". A SINGLE source routes through the single-file entry; MULTIPLE sources route through the
    // multi-file merge, which unifies the files into one columnar program so cross-file public calls resolve
    // exactly as analyzer declaration resolution works across files. Returns false when there are no files,
    // a source text is unavailable, or the backend declines any function (a construct outside the systems
    // subset it models). The program has already been parsed and analyzed by this point, so the columnar
    // backend only does codegen on validated input.
    private bool TryEmitWithColumnarBackend(string assemblyName, string outputPath)
    {
        if (_sourceFiles.Count == 0)
            return false;
        var sources = new List<string>(_sourceFiles.Count);
        foreach (var sourceFile in _sourceFiles)
        {
            if (!_sourceTexts.TryGetValue(Path.GetFullPath(sourceFile), out var source))
                return false;
            sources.Add(source);
        }

        byte[] assembly;
        bool emitted = sources.Count == 1
            ? ColumnarCompiler.TryEmitProgram(sources[0], assemblyName, "Program", out assembly, out _, out _)
            : ColumnarCompiler.TryEmitProgramMultiFile(sources, assemblyName, "Program", out assembly, out _, out _);
        if (!emitted)
            return false;
        File.WriteAllBytes(outputPath, assembly);
        return true;
    }

    private bool RequiresColumnarSoaEmission()
        => SoaFeature.IsEnabled && _compilationUnits.Values.Any(unit => ContainsSoaRecordDeclaration(unit.Declarations));

    private static bool ContainsSoaRecordDeclaration(IEnumerable<Declaration> declarations)
    {
        foreach (var declaration in declarations)
        {
            switch (declaration)
            {
                case SoaRecordDeclaration:
                    return true;
                case ClassDeclaration classDeclaration when ContainsSoaRecordDeclaration(classDeclaration.Members):
                case StructDeclaration structDeclaration when ContainsSoaRecordDeclaration(structDeclaration.Members):
                case RecordDeclaration recordDeclaration when ContainsSoaRecordDeclaration(recordDeclaration.Members):
                case InterfaceDeclaration interfaceDeclaration when ContainsSoaRecordDeclaration(interfaceDeclaration.Members):
                    return true;
            }
        }

        return false;
    }

    private static bool IsDebugLoggingEnabled()
    {
        var value = Environment.GetEnvironmentVariable(DebugLogEnvVar);
        return string.Equals(value, "1", StringComparison.Ordinal) ||
            string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
    }

    private string GetProjectAssemblyName()
        => !string.IsNullOrWhiteSpace(_config?.Name)
            ? _config!.Name!
            : Path.GetFileName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(_projectRoot))) ?? "Project";

    private void AppendDebugLog(string message)
    {
        if (!_debugLoggingEnabled)
        {
            return;
        }

        var logPath = Path.Combine(_projectRoot, "compile-debug.log");
        File.AppendAllText(logPath, message + Environment.NewLine);
    }

}
