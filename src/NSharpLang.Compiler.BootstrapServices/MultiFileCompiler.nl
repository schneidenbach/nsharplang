namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Linq
import System.Runtime.ExceptionServices
import System.Threading
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar
import NSharpLang.Compiler.Performance

type MultiFileCompilerSystemsReport = SystemsReport

/// <summary>
/// Handles compilation of multiple .nl files into a single assembly.
/// Uses the N# parse, analysis, lint, systems-policy, and IL-emission pipeline.
/// </summary>
class MultiFileCompiler {
    private class MultiFileCompilerEmissionThreadState {
        Emitted: bool
        Diagnostic: ColumnarDeclineDiagnostic?
        Captured: ExceptionDispatchInfo?

        constructor() {
            Emitted = false
            Diagnostic = null
            Captured = null
        }
    }

    private readonly _projectRoot: string
    private readonly _config: ProjectConfig?
    private readonly _sourceFiles: List<string>
    private readonly _compilationUnits: Dictionary<string, CompilationUnit>
    private readonly _semanticModels: Dictionary<string, SemanticModel>
    private readonly _allErrors: List<CompilerError>
    private readonly _sharedAnalyzer: Analyzer
    private readonly _debugLoggingEnabled: bool
    private readonly _sourceTextOverrides: IReadOnlyDictionary<string, string>
    private readonly _preprocessorSymbols: IReadOnlySet<string>
    private readonly _sourceTexts: Dictionary<string, string>
    private readonly _projectBindings: BindingMap
    private readonly _projectTypeDeclarationFiles: Dictionary<string, string>
    private readonly _reportedImportCycles: HashSet<string>
    private readonly _filesInReportedImportCycles: HashSet<string>
    private readonly _resolvedFileImportDiagnosticKeys: HashSet<string>
    private readonly _performanceFacts: PerformanceFactStore
    private _systemsReport: SystemsReport
    private _aotMode: bool

    CompilationUnits: IReadOnlyDictionary<string, CompilationUnit> => _compilationUnits
    SemanticModels: IReadOnlyDictionary<string, SemanticModel> => _semanticModels
    AllErrors: IReadOnlyList<CompilerError> => _allErrors
    SourceFiles: IReadOnlyList<string> => _sourceFiles
    SourceTexts: IReadOnlyDictionary<string, string> => _sourceTexts

    // A fresh index wraps the same live stores on every read.
    ProjectIndex: ProjectIndex => new ProjectIndex(_projectBindings, _projectTypeDeclarationFiles)
    PerformanceFacts: PerformanceFactStore => _performanceFacts
    SystemsReport: SystemsReport => _systemsReport

    AotMode: bool {
        get {
            return _aotMode
        }
        set {
            _aotMode = value
        }
    }

    constructor(projectRoot: string, config: ProjectConfig? = null): this(projectRoot, config, null) {
    }

    constructor(projectRoot: string, config: ProjectConfig?, sourceTextOverrides: IReadOnlyDictionary<string, string>?): this(BuildProjectInputs(projectRoot, config, sourceTextOverrides), projectRoot, config) {
    }

    constructor(sourceFiles: IEnumerable<string>, projectRoot: string, config: ProjectConfig? = null): this(sourceFiles, projectRoot, config, null) {
    }

    constructor(sourceFiles: IEnumerable<string>, projectRoot: string, config: ProjectConfig?, sourceTextOverrides: IReadOnlyDictionary<string, string>?): this(BuildExplicitInputs(sourceFiles, config, sourceTextOverrides), projectRoot, config) {
    }

    private constructor(inputs: MultiFileCompilerInputs, projectRoot: string, config: ProjectConfig?) {
        _compilationUnits = new Dictionary<string, CompilationUnit>(StringComparer.OrdinalIgnoreCase)
        _semanticModels = new Dictionary<string, SemanticModel>(StringComparer.OrdinalIgnoreCase)
        _allErrors = new List<CompilerError>()
        _sourceTexts = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        _projectBindings = new BindingMap()
        _projectTypeDeclarationFiles = new Dictionary<string, string>(StringComparer.Ordinal)
        _reportedImportCycles = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        _filesInReportedImportCycles = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        _resolvedFileImportDiagnosticKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        _performanceFacts = new PerformanceFactStore()
        _systemsReport = MultiFileCompilerSystemsReport.Empty(null)
        _aotMode = false

        _projectRoot = projectRoot
        _config = config ?? ProjectFileParser.CreateDefault(null)
        _preprocessorSymbols = inputs.PreprocessorSymbols
        _sourceTextOverrides = inputs.SourceTextOverrides
        _sourceFiles = inputs.SourceFiles
        _debugLoggingEnabled = IsDebugLoggingEnabled()

        // One analyzer instance owns the complete repeated-call lifetime.
        _sharedAnalyzer = new Analyzer()
        _sharedAnalyzer.LoadSystemAssemblies()
        _sharedAnalyzer.LoadFromProjectConfig(_config, _projectRoot)
    }

    private static func BuildProjectInputs(projectRoot: string, config: ProjectConfig?, sourceTextOverrides: IReadOnlyDictionary<string, string>?): MultiFileCompilerInputs {
        copied := CopySourceTextOverrides(sourceTextOverrides)
        paths := copied.Item1
        texts := copied.Item2
        return MultiFileCompilerInputBuilder.BuildFromProject(
            projectRoot,
            config ?? ProjectFileParser.CreateDefault(null),
            paths,
            texts
        )
    }

    private static func BuildExplicitInputs(sourceFiles: IEnumerable<string>, config: ProjectConfig?, sourceTextOverrides: IReadOnlyDictionary<string, string>?): MultiFileCompilerInputs {
        copied := CopySourceTextOverrides(sourceTextOverrides)
        paths := copied.Item1
        texts := copied.Item2
        return MultiFileCompilerInputBuilder.Build(
            sourceFiles.ToList(),
            config ?? ProjectFileParser.CreateDefault(null),
            paths,
            texts
        )
    }

    private static func CopySourceTextOverrides(sourceTextOverrides: IReadOnlyDictionary<string, string>?): (Paths: string[], Texts: string[]) {
        if sourceTextOverrides == null {
            return (Array.Empty<string>(), Array.Empty<string>())
        }
        if sourceTextOverrides.Count == 0 {
            return (Array.Empty<string>(), Array.Empty<string>())
        }

        paths := new string[sourceTextOverrides.Count]
        texts := new string[sourceTextOverrides.Count]
        index := 0
        entries: IEnumerable<KeyValuePair<string, string>> = sourceTextOverrides
        enumerator := entries.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                entry := enumerator.get_Current()
                path := entry.Key
                text := entry.Value
                paths[index] = path
                texts[index] = text
                index += 1
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }

        return (paths, texts)
    }

    private func ReadSourceText(sourceFile: string): string {
        fullPath := Path.GetFullPath(sourceFile)
        let text: string? = null
        return _sourceTextOverrides.TryGetValue(fullPath, out text) ? text : File.ReadAllText(fullPath)
    }

    private func ReadAllSourceTexts(): void {
        for sourceFile in _sourceFiles {
            fullPath := Path.GetFullPath(sourceFile)
            if (!_sourceTexts.ContainsKey(fullPath)) {
                _sourceTexts[fullPath] = ReadSourceText(sourceFile)
            }
        }
    }

    /// <summary>Pass 1: Parse all source files into ASTs</summary>
    private func ParseAllFiles(): void {
        for sourceFile in _sourceFiles {
            {
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   Parsing {Path.GetFileName(sourceFile)}")
                source := ReadSourceText(sourceFile)
                _sourceTexts[Path.GetFullPath(sourceFile)] = source
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Read file ({source.Length} bytes)")
                // Resolve conditional-compilation directives (#if/#elif/#else/#endif) so the
                // parser and all downstream stages only see the live branch. The SOURCE-level
                // overload (the one the columnar emit path already uses) blanks dead branches in
                // place, so every surviving line and column is unchanged.
                live := Preprocessor.ProcessSource(source, _preprocessorSymbols, sourceFile, _allErrors)
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Preprocessed ({live.Length} bytes)")
                parseResult := ColumnarParserRecovery.ParseFileAst(live, sourceFile)
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Parsed compilation unit")

                // Add parse errors to our error list
                _allErrors.AddRange(parseResult.Errors)

                // Store compilation unit (even if null, for consistency)
                if (parseResult.CompilationUnit != null) {
                    _compilationUnits[sourceFile] = parseResult.CompilationUnit
                }
                AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   Done parsing {Path.GetFileName(sourceFile)}")
            }
        }
    }

    /// <summary>Detect circular file-import graphs before semantic analysis so project checks
    /// fail with a bounded, actionable diagnostic instead of relying on per-file
    /// shallow checks.</summary>
    private func DetectCircularFileImports(): void {
        sourceFiles := new List<string>(_compilationUnits.Keys)
        graph := ImportGraphBuilder.Build(
            sourceFiles,
            CollectFileImportGraphEntries(),
            _projectRoot
        )
        for diagnosticKey in graph.ResolvedDiagnosticKeys {
            _resolvedFileImportDiagnosticKeys.Add(diagnosticKey)
        }

        cycles := ImportGraphCycleDetector.Detect(
            sourceFiles,
            graph.EdgesByFile,
            _projectRoot,
            10
        )
        for cycle in cycles {
            ImportCycleDiagnosticReporter.Report(
                cycle,
                _reportedImportCycles,
                _filesInReportedImportCycles,
                _allErrors,
                20,
                TryReadSourceLine(cycle.Edge.SourceFile, cycle.Edge.Line)
            )
        }
    }

    private func CollectFileImportGraphEntries(): List<FileImportGraphEntry> {
        fileImports := new List<FileImportGraphEntry>()

        for columnarKeyValuePair1 in _compilationUnits {
            sourceFile := columnarKeyValuePair1.Key
            compilationUnit := columnarKeyValuePair1.Value

            for fileImport in compilationUnit.FileImports.OfType<FileImport>() {
                fileImports.Add(new FileImportGraphEntry(
                    sourceFile,
                    fileImport.Path,
                    fileImport.Line,
                    fileImport.DiagnosticColumn,
                    fileImport.DiagnosticLength
                ))
            }
        }

        return fileImports
    }

    private func TryReadSourceLine(filePath: string, line: int): string? {
        if line <= 0 {
            return null
        }

        return CodeIntelligenceTextUtilities.GetSourceLine(ReadSourceText(filePath), line)
    }

    /// <summary>Pass 2: Analyze all files with complete symbol table.
    /// Uses a shared Analyzer instance that was initialized once with system assemblies and project config.
    /// This prevents the performance issue of reloading assemblies for each file.</summary>
    private func AnalyzeAllFiles(): void {
        _sharedAnalyzer.SetProjectSourceTexts(_sourceTexts)

        // Analyze each file using the shared analyzer instance
        // The Analyzer's import system handles cross-file references via proper import statements
        for kvp in _compilationUnits {
            sourceFile := kvp.Key
            compilationUnit := kvp.Value

            {
                // Use the shared analyzer (assemblies already loaded in constructor)
                result := _sharedAnalyzer.Analyze(compilationUnit, sourceFile, _projectRoot, ReadSourceText(sourceFile))

                // Save semantic model for project-wide analysis and emission.
                _semanticModels[sourceFile] = result.SemanticModel

                // Merge binding map for cross-file semantic references
                if (result.Bindings != null) {
                    _projectBindings.Merge(result.Bindings)
                }

                // Merge type-declaration-to-file mapping into the project index
                for columnarKeyValuePair2 in _sharedAnalyzer.GetTypeDeclarationFiles() {
                    typeName := columnarKeyValuePair2.Key
                    filePath := columnarKeyValuePair2.Value

                    _projectTypeDeclarationFiles[typeName] = filePath
                }

                // Collect errors. Project-level import graph resolution reports complete cycle paths
                // before analysis; suppress the analyzer's older shallow NL703 duplicates and
                // stale NL701 import-not-found errors for case-only/open-buffer imports already in the graph.
                for error in result.Errors {
                    if (ImportGraphDiagnosticSuppressor.ShouldSuppressAnalyzerDiagnostic(
                        error,
                        _filesInReportedImportCycles,
                        _resolvedFileImportDiagnosticKeys
                    )) {
                        continue
                    }

                    _allErrors.Add(error)
                }
            }
        }

        AnalyzeSystemsPolicy()
    }

    private func AnalyzeSystemsPolicy(): void {
        // The semantic models from the Analyzer pass drive call-site resolution: systems
        // callee facts bind to the declaration each call resolved to, never to a name match.
        // Files whose analysis failed have no model; their calls are conservatively unknown.
        _systemsReport = new SystemsAnalyzer(_projectRoot, _config).Analyze(_compilationUnits, _performanceFacts, _semanticModels)
        for finding in _systemsReport.Findings {
            _allErrors.Add(SystemsFindingDiagnostics.ToCompilerError(finding))
        }
    }

    private func AddStrictLintDiagnosticsFromParsedSources(): void {
        filesWithParseErrors := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for existingError in _allErrors {
            if existingError.Severity == ErrorSeverity.Error {
                if !string.IsNullOrWhiteSpace(existingError.FileName) {
                    filesWithParseErrors.Add(Path.GetFullPath(existingError.FileName))
                }
            }
        }

        for sourceFile in _sourceFiles {
            fullPath := Path.GetFullPath(sourceFile)
            if (filesWithParseErrors.Contains(fullPath)) {
                continue
            }

            let compilationUnit: NSharpLang.Compiler.Ast.CompilationUnit? = null
            if (!_compilationUnits.TryGetValue(sourceFile, out compilationUnit)) {
                continue
            }

            let cachedSource: string? = null
            source := _sourceTexts.TryGetValue(fullPath, out cachedSource) ? cachedSource : ReadSourceText(sourceFile)
            fileDir := Path.GetDirectoryName(fullPath) ?? _projectRoot
            linter := new Linter(LinterConfig.FromEditorConfig(fileDir))
            diagnostics := linter.Lint(compilationUnit, fullPath, source)
            for diagnostic in diagnostics {
                if diagnostic.Severity != DiagnosticSeverity.Error {
                    continue
                }
                _allErrors.Add(StrictLintDiagnostics.FromLintDiagnostic(
                    fullPath,
                    diagnostic.Code,
                    diagnostic.Message,
                    diagnostic.Location.Line,
                    diagnostic.Location.Column,
                    diagnostic.Length,
                    diagnostic.Suggestion,
                    TryReadSourceLine(fullPath, diagnostic.Location.Line)
                ))
            }
        }
    }

    /// <summary>Parse and analyze all files without exporting or emitting IL.
    /// This is the fast path for code intelligence queries — skips code generation
    /// which is unnecessary when you only need ASTs, semantic models, and diagnostics.
    /// All files with a non-null CompilationUnit are analyzed, even if they had parse errors,
    /// so we can report both syntax and semantic diagnostics in a single pass.</summary>
    func CompileForAnalysis(): void {
        let columnarDiscard0: bool = false
        RunLegacyValidationPipeline(false, out columnarDiscard0)
    }

    // Shared N# validation pipeline used by analysis and emission.
    private func RunLegacyValidationPipeline(validateStrictLint: bool, out strictLintFailed: bool): void {
        strictLintFailed = false
        ParseAllFiles()
        errorsBeforeLint := 0
        for existingError in _allErrors {
            if existingError.Severity == ErrorSeverity.Error {
                errorsBeforeLint++
            }
        }
        if (validateStrictLint) {
            AddStrictLintDiagnosticsFromParsedSources()
            hasStrictLintErrors := false
            skippedErrors := 0
            for errorAfterLint in _allErrors {
                if skippedErrors < errorsBeforeLint {
                    skippedErrors++
                    continue
                }
                if errorAfterLint.Severity == ErrorSeverity.Error {
                    hasStrictLintErrors = true
                    break
                }
            }
            if hasStrictLintErrors {
                strictLintFailed = true
                return
            }
        }

        DetectCircularFileImports()
        AnalyzeAllFiles()
    }

    func CompileToIlAssembly(assemblyName: string, outputPath: string, validateStrictLint: bool = false, validateWithLegacyAnalysis: bool = true): MultiFileCompilationResult {
        AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}] CompileToIlAssembly START")

        runLegacyValidation := validateWithLegacyAnalysis || validateStrictLint
        if (!runLegacyValidation) {
            ReadAllSourceTexts()
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? _projectRoot)
            let decline: NSharpLang.Compiler.ColumnarDeclineDiagnostic? = null
            if (!EmitOnWideStackThread(assemblyName, outputPath, out decline)) {
                _allErrors.Add(ColumnarEmissionDiagnostics.RequiredEmissionErrorFor(
                    assemblyName,
                    AotMode,
                    RequiresColumnarSoaEmission(),
                    true,
                    decline.Detail,
                    decline.FileName,
                    decline.Line,
                    decline.Column,
                    decline.SpanLength
                ))
            }

            emitOnlySuccess := true
            for emitOnlyError in _allErrors {
                if emitOnlyError.Severity == ErrorSeverity.Error {
                    emitOnlySuccess = false
                    break
                }
            }
            emitOnlyResultSuccess := emitOnlySuccess
            emitOnlyResultErrors := _allErrors
            emitOnlyResultPath: string? = null
            if emitOnlySuccess {
                emitOnlyResultPath = outputPath
            }
            return new MultiFileCompilationResult(
                emitOnlyResultSuccess,
                emitOnlyResultErrors,
                emitOnlyResultPath
            )
        }

        let strictLintFailed: bool = false
        RunLegacyValidationPipeline(validateStrictLint, out strictLintFailed)
        if (strictLintFailed) {
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                null
            )
        }

        hasValidationErrors := false
        for validationError in _allErrors {
            if validationError.Severity == ErrorSeverity.Error {
                hasValidationErrors = true
                break
            }
        }
        if hasValidationErrors {
            return new MultiFileCompilationResult(
                false,
                _allErrors,
                null
            )
        }

        {
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? _projectRoot)

            // STAGE 5 ROUTING: when the columnar backend can emit the whole program, route emission through it
            // (a standalone columnar pipeline that owns assembly emission without materializing an object AST).
            let decline: NSharpLang.Compiler.ColumnarDeclineDiagnostic? = null
            if (!EmitOnWideStackThread(assemblyName, outputPath, out decline)) {
                _allErrors.Add(ColumnarEmissionDiagnostics.RequiredEmissionErrorFor(
                    assemblyName,
                    AotMode,
                    RequiresColumnarSoaEmission(),
                    false,
                    decline.Detail,
                    decline.FileName,
                    decline.Line,
                    decline.Column,
                    decline.SpanLength
                ))
            }
        }

        success := true
        for emissionError in _allErrors {
            if emissionError.Severity == ErrorSeverity.Error {
                success = false
                break
            }
        }
        resultSuccess := success
        resultErrors := _allErrors
        resultPath: string? = null
        if success {
            resultPath = outputPath
        }
        return new MultiFileCompilationResult(
            resultSuccess,
            resultErrors,
            resultPath
        )
    }

    // Emit the whole assembly through the standalone columnar backend.
    private func TryEmitWithColumnarBackend(assemblyName: string, outputPath: string): bool {
        if (_sourceFiles.Count == 0) {
            return false
        }
        sources := new List<string>(_sourceFiles.Count)
        for sourceFile in _sourceFiles {
            let source: string? = null
            if (!_sourceTexts.TryGetValue(Path.GetFullPath(sourceFile), out source)) {
                return false
            }
            sources.Add(Preprocessor.ProcessSource(source, _preprocessorSymbols, sourceFile, _allErrors))
        }

        outputConfig := _config
        outputType: string? = null
        if outputConfig != null {
            outputType = outputConfig.OutputType
        }
        isExecutable := ColumnarEmissionPlanner.IsExecutableOutput(outputType)
        ColumnarDeclineTrace.Reset()
        let program: NSharpLang.Compiler.Columnar.ColumnarProgramInput? = null
        if (!ColumnarProgramInputBuilder.TryBuildMultiFile(sources, _sourceFiles, _projectRoot, out program)) {
            return false
        }
        // Stamp the numeric CLR version derived from the project's (possibly SemVer)
        // version string, matching the AssemblyVersion the MSBuild SDK advertises.
        versionConfig := _config
        version: string? = null
        if versionConfig != null {
            version = versionConfig.Version
        }
        assemblyVersion := AssemblyVersionUtilities.GetAssemblyVersionOrDefault(version)
        dependenciesConfig := _config
        dependencies: List<Reference>? = null
        if dependenciesConfig != null {
            dependencies = dependenciesConfig.Dependencies
        }
        referenceAssemblyPaths := ExternalAssemblyScan.ResolveReferencePaths(_projectRoot, dependencies)
        let assembly: byte[] = null
        if (!ColumnarIlEmitter.TryEmitColumnarAssembly(assemblyName, "Program", program, isExecutable, out assembly, assemblyVersion, referenceAssemblyPaths)) {
            return false
        }
        File.WriteAllBytes(outputPath, assembly)
        return true
    }

    // MSBuild task threads have ~256 KB stacks and the emitter's per-node recursion frames are large, so
    // emission runs on a dedicated 64 MB wide-stack thread. ColumnarDeclineTrace is [ThreadStatic], so the
    // decline diagnostic must also be built on that thread, while its recorded declines are still visible.
    private func EmitOnWideStackThread(assemblyName: string, outputPath: string, out decline: ColumnarDeclineDiagnostic): bool {
        state := new MultiFileCompiler.MultiFileCompilerEmissionThreadState()
        work: ThreadStart = () => RunColumnarEmissionOnCurrentThread(state, assemblyName, outputPath)
        thread := new Thread(work, 64 * 1024 * 1024)
        thread.IsBackground = true
        thread.Name = "nsharp-columnar-emit"
        thread.Start()
        thread.Join()
        capturedValue := state.Captured
        if capturedValue != null {
            capturedValue.Throw()
        }
        decline = state.Diagnostic ?? ColumnarDeclineDiagnostic.Empty
        return state.Emitted
    }

    private func RunColumnarEmissionOnCurrentThread(state: MultiFileCompilerEmissionThreadState, assemblyName: string, outputPath: string): void {
        try {
            state.Emitted = TryEmitWithColumnarBackend(assemblyName, outputPath)
            if !state.Emitted {
                state.Diagnostic = BuildColumnarDeclineDiagnostic()
            }
        } catch ex: Exception {
            state.Captured = ExceptionDispatchInfo.Capture(ex)
        }
    }

    private func RequiresColumnarSoaEmission(): bool {
        soaFeatureEnabled := SoaFeature.IsEnabled
        compilationUnits := _compilationUnits.get_Values()
        if !soaFeatureEnabled {
            return false
        }
        enumerator := compilationUnits.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                compilationUnit := enumerator.get_Current()
                if compilationUnit != null && CompilationUnitFacts.ContainsSoaRecordDeclaration(compilationUnit) {
                    return true
                }
            }
        } finally {
            enumerator.Dispose()
        }
        return false
    }

    private func BuildColumnarDeclineDiagnostic(): ColumnarDeclineDiagnostic {
        records := ColumnarDeclineTrace.Snapshot()
        WriteColumnarDeclineTrace(records)
        if (records.Count == 0) {
            return ColumnarDeclineDiagnostic.Empty
        }

        primary := records[0]
        memberName := primary.MemberName
        if (string.IsNullOrEmpty(memberName)) {
            for i := records.Count - 1; i >= 0; i-- {
                if (!string.IsNullOrEmpty(records[i].MemberName)) {
                    memberName = records[i].MemberName
                    break
                }
            }
        }

        fileLengths := GetOrderedSourceLengths()
        fileIndex := ColumnarDeclineReasonFacts.ResolveFileIndex(fileLengths, 2, primary.SpanStart, primary.SourceFileId, primary.HasSourceFileId)
        fileName: string? = null
        line := 0
        column := 0
        if (fileIndex >= 0 && fileIndex < _sourceFiles.Count) {
            sourceFile := _sourceFiles[fileIndex]
            fileName = sourceFile
            localOffset := ColumnarDeclineReasonFacts.ResolveLocalOffset(fileLengths, 2, primary.SpanStart, primary.SourceFileId, primary.HasSourceFileId)
            let source: string? = null
            if (localOffset >= 0 && _sourceTexts.TryGetValue(Path.GetFullPath(sourceFile), out source)) {
                line = ColumnarDeclineReasonFacts.LineFromOffset(source, localOffset)
                column = ColumnarDeclineReasonFacts.ColumnFromOffset(source, localOffset)
            }
        }

        reason := string.IsNullOrEmpty(memberName) ? primary : new ColumnarDeclineReason(primary.SiteId, primary.Message, primary.SpanStart, primary.SpanLength, memberName, primary.SourceFileId, primary.HasSourceFileId)
        detailFileName: string? = null
        if fileName != null {
            detailFileName = Path.GetFileName(fileName)
        }
        detail := ColumnarDeclineReasonFacts.FormatDetail(reason, detailFileName, line, column)
        return new ColumnarDeclineDiagnostic(
            detail,
            fileName,
            line,
            column,
            Math.Max(1, primary.SpanLength)
        )
    }

    private func GetOrderedSourceLengths(): int[] {
        lengths := new int[_sourceFiles.Count]
        for i := 0; i < _sourceFiles.Count; i++ {
            let source: string? = null
            if (_sourceTexts.TryGetValue(Path.GetFullPath(_sourceFiles[i]), out source)) {
                lengths[i] = source.Length
            }
        }

        return lengths
    }

    private func WriteColumnarDeclineTrace(records: IReadOnlyList<ColumnarDeclineReason>): void {
        if (records.Count == 0) {
            return
        }

        writeToStdErr := IsColumnarDeclineLoggingEnabled()
        if (!writeToStdErr && !_debugLoggingEnabled) {
            return
        }

        fileLengths := GetOrderedSourceLengths()
        for columnarRecordValue in records {
            fileName: string? = null
            line := 0
            column := 0
            fileIndex := ColumnarDeclineReasonFacts.ResolveFileIndex(fileLengths, 2, columnarRecordValue.SpanStart, columnarRecordValue.SourceFileId, columnarRecordValue.HasSourceFileId)
            if (fileIndex >= 0 && fileIndex < _sourceFiles.Count) {
                sourceFile := _sourceFiles[fileIndex]
                localOffset := ColumnarDeclineReasonFacts.ResolveLocalOffset(fileLengths, 2, columnarRecordValue.SpanStart, columnarRecordValue.SourceFileId, columnarRecordValue.HasSourceFileId)
                let source: string? = null
                if (localOffset >= 0 && _sourceTexts.TryGetValue(Path.GetFullPath(sourceFile), out source)) {
                    fileName = Path.GetFileName(sourceFile)
                    line = ColumnarDeclineReasonFacts.LineFromOffset(source, localOffset)
                    column = ColumnarDeclineReasonFacts.ColumnFromOffset(source, localOffset)
                }
            }

            traceLine := ColumnarDeclineReasonFacts.FormatTraceLine(columnarRecordValue, fileName, line, column)
            if (writeToStdErr) {
                Console.Error.WriteLine(traceLine)
            }

            if (_debugLoggingEnabled) {
                AppendDebugLog(traceLine)
            }
        }
    }

    private static func IsDebugLoggingEnabled(): bool => ColumnarEmissionPlanner.IsEnabledEnvironmentFlag(Environment.GetEnvironmentVariable("NSHARP_DEBUG_LOG"))

    private static func IsColumnarDeclineLoggingEnabled(): bool => ColumnarEmissionPlanner.IsEnabledEnvironmentFlag(Environment.GetEnvironmentVariable("NSHARP_COLUMNAR_DECLINE_LOG"))

    private func AppendDebugLog(message: string): void {
        if (!_debugLoggingEnabled) {
            return
        }

        logPath := Path.Combine(_projectRoot, "compile-debug.log")
        File.AppendAllText(logPath, message + Environment.NewLine)
    }
}
