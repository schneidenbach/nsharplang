using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.ILCompiler;
using NSharpLang.Compiler.Performance;

namespace NSharpLang.Compiler;

/// <summary>
/// Handles compilation of multiple .nl files into a single assembly.
/// Uses a shared parse/analyze pipeline for IL emission and C# export.
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
    private readonly Dictionary<string, HashSet<string>> _autoResolvedNamespaces = new(); // file -> namespaces auto-resolved
    private readonly Dictionary<string, string> _exportedCSharpFiles = new();
    private readonly List<CompilerError> _allErrors = new();
    private readonly Analyzer _sharedAnalyzer;
    private readonly bool _debugLoggingEnabled;
    private readonly IReadOnlyDictionary<string, string> _sourceTextOverrides;
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
    /// without requiring C# export or IL emission.
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
    /// Available after <see cref="CompileForAnalysis"/>, <see cref="ExportToCSharp"/>,
    /// or <see cref="CompileToIlAssembly"/> completes.
    /// </summary>
    public ProjectIndex ProjectIndex => new(_projectBindings, _projectTypeDeclarationFiles);

    /// <summary>
    /// Performance facts (including AOT-blocker facts) recorded during analysis, keyed by
    /// source position. Populated by <see cref="CompileForAnalysis"/>, <see cref="ExportToCSharp"/>,
    /// and <see cref="CompileToIlAssembly"/>. See docs/design/performance-compiler-refactor.md.
    /// </summary>
    public PerformanceFactStore PerformanceFacts => _performanceFacts;

    /// <summary>
    /// AOT/trimming blockers discovered across all parsed files, in deterministic
    /// (file, line, column) order. Available after any analysis pass has run.
    /// </summary>
    public IReadOnlyList<AotBlocker> AotBlockers => _aotBlockers;

    private readonly List<AotBlocker> _aotBlockers = new();

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
        : this(BuildSourceFiles(projectRoot, config ?? ProjectFileParser.CreateDefault(), sourceTextOverrides), projectRoot, config, sourceTextOverrides)
    {
    }

    public MultiFileCompiler(IEnumerable<string> sourceFiles, string projectRoot, ProjectConfig? config = null)
        : this(sourceFiles, projectRoot, config, sourceTextOverrides: null)
    {
    }

    public MultiFileCompiler(IEnumerable<string> sourceFiles, string projectRoot, ProjectConfig? config, IReadOnlyDictionary<string, string>? sourceTextOverrides)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
        _sourceTextOverrides = NormalizeSourceTextOverrides(sourceTextOverrides);
        _sourceFiles = sourceFiles
            .Select(Path.GetFullPath)
            .Concat(_sourceTextOverrides.Keys)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        _debugLoggingEnabled = IsDebugLoggingEnabled();

        // Initialize shared analyzer ONCE with system assemblies and project config
        _sharedAnalyzer = new Analyzer();
        _sharedAnalyzer.LoadSystemAssemblies();
        _sharedAnalyzer.LoadFromProjectConfig(_config, _projectRoot);
    }

    private static List<string> BuildSourceFiles(string projectRoot, ProjectConfig config, IReadOnlyDictionary<string, string>? sourceTextOverrides)
    {
        return DiscoverSourceFiles(projectRoot, config)
            .Concat(NormalizeSourceTextOverrides(sourceTextOverrides).Keys)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static IReadOnlyDictionary<string, string> NormalizeSourceTextOverrides(IReadOnlyDictionary<string, string>? sourceTextOverrides)
    {
        if (sourceTextOverrides == null || sourceTextOverrides.Count == 0)
        {
            return new Dictionary<string, string>();
        }

        return sourceTextOverrides.ToDictionary(
            kvp => Path.GetFullPath(kvp.Key),
            kvp => kvp.Value,
            StringComparer.OrdinalIgnoreCase);
    }

    private string ReadSourceText(string sourceFile)
    {
        var fullPath = Path.GetFullPath(sourceFile);
        return _sourceTextOverrides.TryGetValue(fullPath, out var text)
            ? text
            : File.ReadAllText(fullPath);
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
                var source = ReadSourceText(sourceFile);
                _sourceTexts[Path.GetFullPath(sourceFile)] = source;
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

            var sourceText = _sourceTexts.TryGetValue(sourceFile, out var text)
                ? text
                : ReadSourceText(sourceFile);
            var symbols = Analyzer.ExtractProjectSymbols(compilationUnit, sourceFile, sourceText);
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
    /// Detect circular file-import graphs before semantic analysis so project checks
    /// fail with a bounded, actionable diagnostic instead of relying on per-file
    /// shallow checks.
    /// </summary>
    private void DetectCircularFileImports()
    {
        var edgesByFile = BuildFileImportGraph();
        var visitState = new Dictionary<string, ImportVisitState>(StringComparer.OrdinalIgnoreCase);

        foreach (var sourceFile in _compilationUnits.Keys.OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
        {
            VisitImportGraph(sourceFile, edgesByFile, visitState);
        }
    }

    private Dictionary<string, List<ImportEdge>> BuildFileImportGraph()
    {
        var graph = new Dictionary<string, List<ImportEdge>>(StringComparer.OrdinalIgnoreCase);
        var sourceFileByFullPath = _compilationUnits.Keys.ToDictionary(
            Path.GetFullPath,
            path => path,
            StringComparer.OrdinalIgnoreCase);

        foreach (var (sourceFile, compilationUnit) in _compilationUnits)
        {
            var resolver = new FileResolver(_projectRoot, sourceFile);
            foreach (var fileImport in compilationUnit.FileImports.OfType<FileImport>())
            {
                var resolvedPath = ResolveImportedCompilationUnitPath(resolver, fileImport.Path, sourceFileByFullPath);
                if (resolvedPath == null)
                    continue;

                if (!graph.TryGetValue(sourceFile, out var edges))
                {
                    edges = new List<ImportEdge>();
                    graph[sourceFile] = edges;
                }

                _resolvedFileImportDiagnosticKeys.Add(BuildFileImportDiagnosticKey(sourceFile, fileImport.Line, fileImport.DiagnosticColumn));
                edges.Add(new ImportEdge(
                    sourceFile,
                    resolvedPath,
                    fileImport.Path,
                    fileImport.Line,
                    fileImport.DiagnosticColumn,
                    fileImport.DiagnosticLength));
            }
        }

        return graph;
    }

    private static string? ResolveImportedCompilationUnitPath(
        FileResolver resolver,
        string importPath,
        IReadOnlyDictionary<string, string> sourceFileByFullPath)
    {
        var resolvedPath = Path.GetFullPath(resolver.ResolveFilePath(importPath));
        return sourceFileByFullPath.TryGetValue(resolvedPath, out var sourceFile)
            ? sourceFile
            : null;
    }

    private static string BuildFileImportDiagnosticKey(string filePath, int line, int column)
    {
        return $"{Path.GetFullPath(filePath)}:{line}:{column}";
    }

    private void VisitImportGraph(
        string sourceFile,
        IReadOnlyDictionary<string, List<ImportEdge>> edgesByFile,
        Dictionary<string, ImportVisitState> visitState)
    {
        if (visitState.TryGetValue(sourceFile, out var existingState) && existingState == ImportVisitState.Visited)
            return;

        var pathStack = new List<string>();
        var pathIndexByFile = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var traversalStack = new List<ImportTraversalFrame>();

        visitState[sourceFile] = ImportVisitState.Visiting;
        pathIndexByFile[sourceFile] = 0;
        pathStack.Add(sourceFile);
        traversalStack.Add(new ImportTraversalFrame(sourceFile, GetSortedImportEdges(sourceFile, edgesByFile)));

        while (traversalStack.Count > 0)
        {
            var frame = traversalStack[^1];
            if (frame.NextEdgeIndex >= frame.Edges.Count)
            {
                traversalStack.RemoveAt(traversalStack.Count - 1);
                pathIndexByFile.Remove(frame.SourceFile);
                pathStack.RemoveAt(pathStack.Count - 1);
                visitState[frame.SourceFile] = ImportVisitState.Visited;
                continue;
            }

            var edge = frame.Edges[frame.NextEdgeIndex++];
            if (pathIndexByFile.TryGetValue(edge.TargetFile, out var cycleStartIndex))
            {
                var cyclePath = pathStack.Skip(cycleStartIndex).Concat(new[] { edge.TargetFile }).ToList();
                ReportCircularImportCycle(edge, cyclePath);
                continue;
            }

            if (visitState.TryGetValue(edge.TargetFile, out var targetState) && targetState == ImportVisitState.Visited)
                continue;

            visitState[edge.TargetFile] = ImportVisitState.Visiting;
            pathIndexByFile[edge.TargetFile] = pathStack.Count;
            pathStack.Add(edge.TargetFile);
            traversalStack.Add(new ImportTraversalFrame(edge.TargetFile, GetSortedImportEdges(edge.TargetFile, edgesByFile)));
        }
    }

    private static IReadOnlyList<ImportEdge> GetSortedImportEdges(
        string sourceFile,
        IReadOnlyDictionary<string, List<ImportEdge>> edgesByFile)
    {
        return edgesByFile.TryGetValue(sourceFile, out var edges)
            ? edges.OrderBy(edge => edge.TargetFile, StringComparer.OrdinalIgnoreCase).ToList()
            : Array.Empty<ImportEdge>();
    }

    private void ReportCircularImportCycle(ImportEdge edge, IReadOnlyList<string> cyclePath)
    {
        var displayPath = FormatCyclePath(cyclePath);
        var canonicalCycle = CanonicalizeCycle(cyclePath);
        if (!_reportedImportCycles.Add(canonicalCycle))
            return;

        foreach (var filePath in cyclePath.Take(Math.Max(0, cyclePath.Count - 1)))
        {
            _filesInReportedImportCycles.Add(Path.GetFullPath(filePath));
        }

        if (_allErrors.Count(error => error.Code == ErrorCode.CircularImport) >= MaxReportedImportCycles)
            return;

        var sourceSnippet = TryReadSourceLine(edge.SourceFile, edge.Line);
        _allErrors.Add(new CompilerError(
            ErrorCode.CircularImport,
            $"Circular import detected: {displayPath}",
            edge.Line,
            edge.Column,
            ErrorSeverity.Error)
        {
            FileName = edge.SourceFile,
            SourceSnippet = sourceSnippet,
            Length = Math.Max(1, edge.Length),
            HumanExplanation = $"File imports form a cycle: {displayPath}",
            ContextualHint =
                "Circular imports are not allowed because they make symbol resolution order ambiguous.\n" +
                $"Import path: {displayPath}",
            Suggestion = "Move shared types or functions into a separate file/package that every file can import without importing back, or invert one dependency so imports flow in one direction.",
            DocsUrl = "https://docs.n-sharp.dev/errors/NL703"
        });
    }

    private string FormatCyclePath(IReadOnlyList<string> cyclePath)
    {
        var displayNodes = cyclePath.Select(GetProjectRelativeDisplayPath).ToList();
        if (displayNodes.Count <= MaxDisplayedImportCycleNodes)
            return string.Join(" -> ", displayNodes);

        const int headCount = 6;
        const int tailCount = 3;
        var omittedCount = displayNodes.Count - headCount - tailCount;
        var boundedNodes = displayNodes
            .Take(headCount)
            .Concat(new[] { $"... ({omittedCount} more imports)" })
            .Concat(displayNodes.Skip(displayNodes.Count - tailCount));
        return string.Join(" -> ", boundedNodes);
    }

    private string GetProjectRelativeDisplayPath(string filePath)
    {
        try
        {
            return Path.GetRelativePath(_projectRoot, filePath).Replace('\\', '/');
        }
        catch
        {
            return Path.GetFileName(filePath);
        }
    }

    private static string CanonicalizeCycle(IReadOnlyList<string> cyclePath)
    {
        var nodes = cyclePath.Take(Math.Max(0, cyclePath.Count - 1))
            .Select(Path.GetFullPath)
            .ToList();
        if (nodes.Count == 0)
            return string.Empty;

        var rotations = Enumerable.Range(0, nodes.Count)
            .Select(index => string.Join("->", nodes.Skip(index).Concat(nodes.Take(index))));
        return rotations.OrderBy(value => value, StringComparer.OrdinalIgnoreCase).First();
    }

    private string? TryReadSourceLine(string filePath, int line)
    {
        if (line <= 0)
            return null;

        try
        {
            return ReadSourceText(filePath)
                .Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None)
                .Skip(line - 1)
                .FirstOrDefault();
        }
        catch
        {
            return null;
        }
    }

    private bool ShouldSuppressAnalyzerDiagnostic(CompilerError error)
    {
        if (error.Code == ErrorCode.CircularImport &&
            error.FileName != null &&
            _filesInReportedImportCycles.Contains(Path.GetFullPath(error.FileName)))
        {
            return true;
        }

        if (error.Code == ErrorCode.ImportNotFound &&
            error.FileName != null &&
            _resolvedFileImportDiagnosticKeys.Contains(BuildFileImportDiagnosticKey(error.FileName, error.Line, error.Column)))
        {
            return true;
        }

        return false;
    }

    private sealed class ImportTraversalFrame(string sourceFile, IReadOnlyList<ImportEdge> edges)
    {
        public string SourceFile { get; } = sourceFile;
        public IReadOnlyList<ImportEdge> Edges { get; } = edges;
        public int NextEdgeIndex { get; set; }
    }

    private enum ImportVisitState
    {
        Visiting,
        Visited,
    }

    private sealed record ImportEdge(string SourceFile, string TargetFile, string ImportPath, int Line, int Column, int Length);

    /// <summary>
    /// Pass 2: Analyze all files with complete symbol table
    /// Uses a shared Analyzer instance that was initialized once with system assemblies and project config.
    /// This prevents the performance issue of reloading assemblies for each file.
    /// </summary>
    private void AnalyzeAllFiles()
    {
        // Build project symbol table for auto-discovery and set it on the shared analyzer
        var projectSymbols = BuildProjectSymbolTable();
        _sharedAnalyzer.SetProjectSourceTexts(_sourceTexts);
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
                var result = _sharedAnalyzer.Analyze(compilationUnit, sourceFile, _projectRoot, ReadSourceText(sourceFile));

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

                // Collect errors. Project-level import graph resolution reports complete cycle paths
                // before analysis; suppress the analyzer's older shallow NL703 duplicates and
                // stale NL701 import-not-found errors for case-only/open-buffer imports already in the graph.
                foreach (var error in result.Errors)
                {
                    if (ShouldSuppressAnalyzerDiagnostic(error))
                        continue;

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

        // AOT-blocker analysis is a pure pass over the parsed ASTs. It always runs so the
        // facts are available to the perf report and the `--aot` diagnostic gate.
        AnalyzeAotBlockers();
    }

    /// <summary>
    /// AOT-blocker analysis pass: classifies each file's ABI surface, walks every compilation
    /// unit for reflection / dynamic-code / runtime-generic / expression-tree constructs, and
    /// records both <see cref="AotBlocker"/> facts and the corresponding
    /// <see cref="Performance.PerformanceFacts"/> into the shared store. Pure analysis — emits
    /// no IL and changes no other behavior. Deterministic by (file, line, column).
    /// </summary>
    private void AnalyzeAotBlockers()
    {
        _aotBlockers.Clear();

        foreach (var sourceFile in _compilationUnits.Keys.OrderBy(path => path, StringComparer.OrdinalIgnoreCase))
        {
            var compilationUnit = _compilationUnits[sourceFile];
            var abi = new AbiClassifier(sourceFile).Classify(compilationUnit);
            var analyzer = new AotBlockerAnalyzer(sourceFile, abi).Analyze(compilationUnit, _performanceFacts);
            _aotBlockers.AddRange(analyzer.Blockers);
        }

        _aotBlockers.Sort(static (a, b) =>
        {
            var byFile = string.Compare(a.File, b.File, StringComparison.OrdinalIgnoreCase);
            if (byFile != 0) return byFile;
            var byLine = a.Line.CompareTo(b.Line);
            return byLine != 0 ? byLine : a.Column.CompareTo(b.Column);
        });
    }

    /// <summary>
    /// Read a single source line (1-based) for diagnostic snippets, honoring source overrides.
    /// </summary>
    public string? TryReadSourceSnippet(string file, int line)
    {
        return TryReadSourceLine(file, line)?.TrimEnd();
    }

    /// <summary>
    /// Build Elm-quality diagnostics for the AOT blockers found during analysis.
    /// <paramref name="asError"/> emits them as build-blocking errors (under <c>--aot</c>);
    /// otherwise they are advisory warnings.
    /// </summary>
    public List<CompilerError> BuildAotDiagnostics(bool asError)
    {
        return AotDiagnostics.ToDiagnostics(_aotBlockers, TryReadSourceSnippet, asError);
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
        DetectCircularFileImports();
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
        DetectCircularFileImports();
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
        DetectCircularFileImports();
        AnalyzeAllFiles();

        // Under `--aot`, every AOT blocker becomes a build-blocking error before emission.
        if (AotMode)
        {
            _allErrors.AddRange(BuildAotDiagnostics(asError: true));
        }

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

            var compiler = new ILCompiler.ILCompiler(mergedCompilationUnit, assemblyName, outputPath, _config)
            {
                AotRequirements = AotRequirements.FromBlockers(_aotBlockers),
            };
            compiler.Compile();
        }
        catch (Exception ex)
        {
            AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] CompileToIlAssembly EXCEPTION: {ex}");
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
