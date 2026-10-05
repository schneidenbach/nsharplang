namespace NSharpLang.Compiler

import System
import System.Collections.Concurrent
import System.Collections.Generic
import System.IO
import System.Linq
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

        constructor() {
            Emitted = false
            Diagnostic = null
        }
    }

    // One file's analysis outcome, the exception its analysis threw, or -- until a worker reaches
    // the file -- pending.
    private class MultiFileCompilerFileAnalysis {
        SemanticModel: SemanticModel?
        Bindings: BindingMap?
        Errors: List<CompilerError>
        TypeDeclarationFiles: Dictionary<string, string>
        Failure: Exception?
        IsPending: bool

        constructor(semanticModel: SemanticModel?, bindings: BindingMap?, errors: List<CompilerError>, typeDeclarationFiles: Dictionary<string, string>, failure: Exception?, isPending: bool) {
            SemanticModel = semanticModel
            Bindings = bindings
            Errors = errors
            TypeDeclarationFiles = typeDeclarationFiles
            Failure = failure
            IsPending = isPending
        }
    }

    // What one parallel analysis worker reads and writes. `Analyzer` is the shared analyzer for
    // worker 0 and null for the others, which build their own on their own thread.
    private class MultiFileCompilerAnalysisWorker {
        Analyzer: Analyzer?
        Files: List<string>
        Units: List<CompilationUnit>
        Outcomes: MultiFileCompilerFileAnalysis[]
        Queue: ConcurrentQueue<int>
        // The project's namespace set, computed once by the shared analyzer over the same snapshot.
        ProjectNamespaces: HashSet<string>
        // Set when the worker could not even build its analyzer; its share of the queue is then
        // left to the others.
        Failure: Exception?

        constructor(analyzer: Analyzer?, files: List<string>, units: List<CompilationUnit>, outcomes: MultiFileCompilerFileAnalysis[], queue: ConcurrentQueue<int>, projectNamespaces: HashSet<string>) {
            Analyzer = analyzer
            Files = files
            Units = units
            Outcomes = outcomes
            Queue = queue
            ProjectNamespaces = projectNamespaces
            Failure = null
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
    // The parsed units an analyzer's own parse of the snapshot would reproduce exactly (full path ->
    // unit): files no conditional-compilation directive changed, listed under their full path.
    private readonly _reusableUnits: Dictionary<string, CompilationUnit>
    private readonly _reportedImportCycles: HashSet<string>
    private readonly _filesInReportedImportCycles: HashSet<string>
    private readonly _resolvedFileImportDiagnosticKeys: HashSet<string>
    private readonly _performanceFacts: PerformanceFactStore
    private _systemsReport: SystemsReport
    private _aotMode: bool
    private _emitReferenceAssembly: bool
    private _soaEnabled: bool
    private _columnarDeclineLog: TextWriter?
    private readonly _phaseProject: string
    private readonly _declaresOneProgram: bool
    private _analysisWorkers: int

    CompilationUnits: IReadOnlyDictionary<string, CompilationUnit> => _compilationUnits
    SemanticModels: IReadOnlyDictionary<string, SemanticModel> => _semanticModels
    AllErrors: IReadOnlyList<CompilerError> => _allErrors
    SourceFiles: IReadOnlyList<string> => _sourceFiles
    SourceTexts: IReadOnlyDictionary<string, string> => _sourceTexts

    // A fresh index wraps the same live stores on every read.
    ProjectIndex: ProjectIndex => new ProjectIndex(_projectBindings, _projectTypeDeclarationFiles)
    PerformanceFacts: PerformanceFactStore => _performanceFacts
    SystemsReport: SystemsReport => _systemsReport

    // THE FRIEND GRANTS THIS COMPILATION ANALYSED UNDER. `InternalsVisibleToGrants` is deliberately
    // ONE object so that the probe, member resolution, extension discovery, attribute resolution,
    // completion and `nlc query` cannot disagree about what this compilation may name — and
    // completion could not ask it at all until the snapshot carried it out of here.
    FriendGrants: InternalsVisibleToGrants => _sharedAnalyzer.GetFriendGrants()

    AotMode: bool {
        get {
            return _aotMode
        }
        set {
            _aotMode = value
        }
    }

    // THE REFERENCE ASSEMBLY IS THE COMPILER'S OUTPUT, NOT THE BUILD TASK'S REWRITE. A caller that
    // needs one — the MSBuild SDK, which is the only consumer MSBuild's `ProduceReferenceAssembly`
    // serves — asks for it here and reads it back from `ReferenceAssemblyPathFor`. `nlc build` asks
    // for nothing, so the CLI path pays nothing.
    EmitReferenceAssembly: bool {
        get {
            return _emitReferenceAssembly
        }
        set {
            _emitReferenceAssembly = value
        }
    }

    // WHETHER THIS COMPILATION ACCEPTS THE EXPERIMENTAL `soa record` LOWERING. Decided ONCE, when the
    // compiler is built, from `NSHARP_EXPERIMENTAL_SOA` (`SoaFeature`), and carried into the analyzer
    // this compiler owns; the emission route reads the same value. A caller that wants the other
    // answer - a test proving the columnar route refuses to fall back - sets it here instead of
    // rewriting the process environment, which every other compilation in the process would see.
    SoaEnabled: bool {
        get {
            return _soaEnabled
        }
        set {
            _soaEnabled = value
            analyzer := _sharedAnalyzer
            analyzer.SoaEnabled = value
        }
    }

    // HOW MANY WORKERS THE ANALYSIS PASS USES: 0 (the default) lets `CompilerParallelism` decide
    // from the project's size and the machine; a positive count is used as given, capped by the
    // number of files. A caller that must exercise one path or the other -- the serial-versus-
    // parallel differential, an estate row -- says so here rather than through
    // `NSHARP_COMPILER_WORKERS`, which every compilation in the process would see.
    AnalysisWorkers: int {
        get {
            return _analysisWorkers
        }
        set {
            _analysisWorkers = value
        }
    }

    // WHERE THE COLUMNAR DECLINE TRACE GOES, or null for nowhere. Decided ONCE, when the compiler is
    // built: stderr when `NSHARP_COLUMNAR_DECLINE_LOG` is on, else nothing. A caller that wants the
    // trace names its own writer here instead of setting the variable and swapping `Console.Error`,
    // both of which are process-global.
    ColumnarDeclineLog: TextWriter? {
        get {
            return _columnarDeclineLog
        }
        set {
            _columnarDeclineLog = value
        }
    }

    // Beside the implementation, in a directory only the compiler writes, so that the build task's
    // copy into `obj/…/refint/` is a copy of a finished file and never a second rewrite of one.
    static func ReferenceAssemblyPathFor(outputPath: string): string {
        directory := Path.GetDirectoryName(Path.GetFullPath(outputPath)) ?? ""
        return Path.Combine(directory, "nsharpref", Path.GetFileName(outputPath))
    }

    constructor(projectRoot: string, config: ProjectConfig? = null): this(projectRoot, config, null) {
    }

    constructor(projectRoot: string, config: ProjectConfig?, sourceTextOverrides: IReadOnlyDictionary<string, string>?): this(BuildProjectInputs(projectRoot, config, sourceTextOverrides, false), projectRoot, config) {
    }

    // THE TEST-FILE ARM. `.tests.nl` files are ordinary N# source that happens to declare `test` blocks,
    // and `nlc test` compiles them with the rest of the project; a caller that wants the SAME file list
    // `nlc test` compiles — `nlc check`, so a project made of test files is not silently reported clean —
    // asks for it here rather than rediscovering the files itself.
    constructor(projectRoot: string, config: ProjectConfig?, sourceTextOverrides: IReadOnlyDictionary<string, string>?, includeTests: bool): this(BuildProjectInputs(projectRoot, config, sourceTextOverrides, includeTests), projectRoot, config) {
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
        _reusableUnits = new Dictionary<string, CompilationUnit>(StringComparer.OrdinalIgnoreCase)
        _reportedImportCycles = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        _filesInReportedImportCycles = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        _resolvedFileImportDiagnosticKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        _performanceFacts = new PerformanceFactStore()
        _systemsReport = MultiFileCompilerSystemsReport.Empty(null)
        _aotMode = false
        _emitReferenceAssembly = false
        _projectRoot = projectRoot
        _config = config ?? ProjectFileParser.CreateDefault(null)
        _preprocessorSymbols = inputs.PreprocessorSymbols
        _sourceTextOverrides = inputs.SourceTextOverrides
        _sourceFiles = inputs.SourceFiles
        _debugLoggingEnabled = IsDebugLoggingEnabled()
        _soaEnabled = SoaFeature.IsEnabled
        _columnarDeclineLog = null
        if IsColumnarDeclineLoggingEnabled() {
            _columnarDeclineLog = Console.Error
        }
        _phaseProject = PhaseProjectName(_config, projectRoot)

        // A caller that hands over a project configuration compiles these files into ONE assembly —
        // a parsed `project.yml`, or a virtual project like the playground's. A caller with none (a
        // folder of standalone scripts checked as a directory) leaves the analyzer to ask the root.
        _declaresOneProgram = config != null
        _analysisWorkers = 0

        // One analyzer instance owns the complete repeated-call lifetime.
        loadMark := CompilerPhaseTimings.Begin(_phaseProject, "load-references")
        _sharedAnalyzer = CreateAnalyzer()
        CompilerPhaseTimings.End(loadMark)
    }

    // An analyzer for this compilation, built the one way: the shared analyzer and every parallel
    // analysis worker's come from here, so they cannot disagree about the assemblies, the project
    // references, the SoA gate or the one-program rule they analyse under.
    private func CreateAnalyzer(): Analyzer {
        analyzer := new Analyzer()
        analyzer.SoaEnabled = _soaEnabled
        analyzer.LoadSystemAssemblies()
        analyzer.LoadFromProjectConfig(_config, _projectRoot)
        if _declaresOneProgram {
            analyzer.DeclareOneProgram()
        }
        // One compilation reads one directory tree; the analyzer may keep its view of it from one
        // file's analysis to the next.
        analyzer.HoldProjectDiskView()
        return analyzer
    }

    // The label `CompilerPhaseTimings` files this compilation's phases under: the project's name, else
    // its directory's.
    private static func PhaseProjectName(config: ProjectConfig, projectRoot: string): string {
        configName := config.Name
        if configName != null && configName.Length > 0 {
            return configName
        }

        return Path.GetFileName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(projectRoot)))
    }

    private static func BuildProjectInputs(projectRoot: string, config: ProjectConfig?, sourceTextOverrides: IReadOnlyDictionary<string, string>?, includeTests: bool): MultiFileCompilerInputs {
        copied := CopySourceTextOverrides(sourceTextOverrides)
        paths := copied.Item1
        texts := copied.Item2
        return MultiFileCompilerInputBuilder.BuildFromProject(
            projectRoot,
            config ?? ProjectFileParser.CreateDefault(null),
            paths,
            texts,
            includeTests
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
                    // The analyzer parses the RAW snapshot text under the FULL path; this unit is that
                    // parse exactly when preprocessing changed nothing and the path is already full.
                    fullSourcePath := Path.GetFullPath(sourceFile)
                    if string.Equals(live, source, StringComparison.Ordinal) && string.Equals(fullSourcePath, sourceFile, StringComparison.Ordinal) {
                        _reusableUnits[fullSourcePath] = parseResult.CompilationUnit
                    }
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

    // PASS 2: SEMANTIC ANALYSIS, ONE FILE AT A TIME, ON ONE OR MORE WORKERS.
    //
    // Each file is analysed against the complete project (every file's declarations) by an `Analyzer`
    // initialised once with the system assemblies and the project's references. A large project fans
    // the files out to `CompilerParallelism.WorkerCount` workers; a small one, or
    // `NSHARP_COMPILER_WORKERS=1`, analyses them on the calling thread exactly as before.
    //
    // THE THREADING MODEL. Worker 0 is `_sharedAnalyzer`; every other worker builds its own `Analyzer`
    // the way the constructor built that one, so no analyzer, metadata load context, parsed project
    // view or cache is ever touched by two threads. The workers share only immutable inputs (the
    // parsed units, which only the worker analysing a file writes to, and `_sourceTexts`) and a FIFO
    // queue of file indices; each writes its file's outcome into that file's own slot. Nothing is
    // merged into this compiler's state until every worker has finished, and then in FILE ORDER,
    // through the same merge the serial loop performs.
    //
    // WHY THE ANSWERS ARE THE SERIAL ONES. The one fact an analysis inherits from the files analysed
    // before it is the loaded-assembly list, which grows as each file's imports are walked. The queue
    // hands indices out in increasing order, so before analysing file `i` a worker replays the import
    // loads of every earlier file it did not analyse (`Analyzer.PreloadImportedAssemblies`), in file
    // order -- the list it analyses `i` against is the list a serial run would have. The merge is in
    // file order, so diagnostics, semantic models, bindings and the type-declaration index come out
    // in serial order whichever worker finished first. The differential that proves it compiles the
    // repository's corpus at one worker and at many and compares diagnostics and IL bytes.
    //
    // A file whose analysis THROWS ends the pass as the serial loop's exception did: the outcomes of
    // the files before it are merged and the earliest failure is rethrown.
    private func AnalyzeAllFiles(): void {
        analysisMark := CompilerPhaseTimings.Begin(_phaseProject, "analysis")
        files := new List<string>(_compilationUnits.Count)
        units := new List<CompilationUnit>(_compilationUnits.Count)
        totalCharacters := 0L
        for kvp in _compilationUnits {
            files.Add(kvp.Key)
            units.Add(kvp.Value)
            text: string? = null
            if _sourceTexts.TryGetValue(Path.GetFullPath(kvp.Key), out text) && text != null {
                totalCharacters = totalCharacters + text.Length
            }
        }

        outcomes := new MultiFileCompilerFileAnalysis[files.Count]
        pendingIndex := 0
        while pendingIndex < outcomes.Length {
            outcomes[pendingIndex] = new MultiFileCompiler.MultiFileCompilerFileAnalysis(null, null, new List<CompilerError>(), new Dictionary<string, string>(), null, true)
            pendingIndex = pendingIndex + 1
        }
        workerCount := CompilerParallelism.WorkerCount(files.Count, totalCharacters)
        if _analysisWorkers > 0 {
            workerCount = Math.Min(_analysisWorkers, Math.Max(files.Count, 1))
        }
        if workerCount <= 1 {
            _sharedAnalyzer.SetProjectSourceTexts(_sourceTexts)
            _sharedAnalyzer.SeedProjectCompilationUnits(_reusableUnits)
            index := 0
            while index < files.Count {
                outcomes[index] = AnalyzeOneFile(_sharedAnalyzer, files[index], units[index])
                index = index + 1
            }
        } else {
            AnalyzeFilesInParallel(files, units, outcomes, workerCount)
        }

        mergeIndex := 0
        while mergeIndex < files.Count {
            outcome := outcomes[mergeIndex]
            failure := outcome.Failure
            if failure != null {
                CompilerPhaseTimings.End(analysisMark)
                throw failure
            }
            MergeFileAnalysis(files[mergeIndex], outcome)
            mergeIndex = mergeIndex + 1
        }
        CompilerPhaseTimings.End(analysisMark)

        systemsMark := CompilerPhaseTimings.Begin(_phaseProject, "systems-policy")
        AnalyzeSystemsPolicy()
        CompilerPhaseTimings.End(systemsMark)
    }

    // One file's analysis, captured whole: the analyzer reuses its error list and its type-declaration
    // index for the next file, so both are copied before the next `Analyze` can clear them.
    private func AnalyzeOneFile(analyzer: Analyzer, sourceFile: string, compilationUnit: CompilationUnit): MultiFileCompilerFileAnalysis {
        result := analyzer.Analyze(compilationUnit, sourceFile, _projectRoot, ReadSourceText(sourceFile))
        return new MultiFileCompiler.MultiFileCompilerFileAnalysis(
            result.SemanticModel,
            result.Bindings,
            new List<CompilerError>(result.Errors),
            analyzer.GetTypeDeclarationFiles(),
            null,
            false
        )
    }

    private func MergeFileAnalysis(sourceFile: string, outcome: MultiFileCompilerFileAnalysis): void {
        // Save semantic model for project-wide analysis and emission.
        semanticModel := outcome.SemanticModel
        if semanticModel != null {
            _semanticModels[sourceFile] = semanticModel
        }

        // Merge binding map for cross-file semantic references
        bindings := outcome.Bindings
        if bindings != null {
            _projectBindings.Merge(bindings)
        }

        // Merge type-declaration-to-file mapping into the project index
        for declarationFile in outcome.TypeDeclarationFiles {
            _projectTypeDeclarationFiles[declarationFile.Key] = declarationFile.Value
        }

        // Collect errors. Project-level import graph resolution reports complete cycle paths
        // before analysis; suppress the analyzer's older shallow NL703 duplicates and
        // stale NL701 import-not-found errors for case-only/open-buffer imports already in the graph.
        for error in outcome.Errors {
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

    private func AnalyzeFilesInParallel(files: List<string>, units: List<CompilationUnit>, outcomes: MultiFileCompilerFileAnalysis[], workerCount: int): void {
        queue := new ConcurrentQueue<int>()
        index := 0
        while index < files.Count {
            queue.Enqueue(index)
            index = index + 1
        }

        // The shared analyzer takes the snapshot here, on this thread, and computes the project's
        // namespace set once; every other worker is seeded with it rather than parsing the files
        // outside the snapshot again.
        _sharedAnalyzer.SetProjectSourceTexts(_sourceTexts)
        _sharedAnalyzer.SeedProjectCompilationUnits(_reusableUnits)
        projectNamespaces := _sharedAnalyzer.ProjectNamespacesFor(_projectRoot)

        threads := new List<Thread>(workerCount)
        states := new List<MultiFileCompilerAnalysisWorker>(workerCount)
        worker := 0
        while worker < workerCount {
            workerAnalyzer: Analyzer? = null
            if worker == 0 {
                workerAnalyzer = _sharedAnalyzer
            }
            state := new MultiFileCompiler.MultiFileCompilerAnalysisWorker(workerAnalyzer, files, units, outcomes, queue, projectNamespaces)
            states.Add(state)
            work: ThreadStart = () => RunAnalysisWorker(state)
            thread := new Thread(work, 64 * 1024 * 1024)
            thread.IsBackground = true
            thread.Name = "nsharp-analysis-" + worker.ToString()
            threads.Add(thread)
            worker = worker + 1
        }

        for started in threads {
            started.Start()
        }
        for joined in threads {
            joined.Join()
        }

        // Every worker that could not build its analyzer left its files to the others; if they ALL
        // failed, a file has no outcome and the failure is the answer.
        slot := 0
        while slot < outcomes.Length {
            if outcomes[slot].IsPending {
                for failedState in states {
                    workerFailure := failedState.Failure
                    if workerFailure != null {
                        throw workerFailure
                    }
                }
                throw new InvalidOperationException("Parallel analysis produced no outcome for '" + files[slot] + "'.")
            }
            slot = slot + 1
        }
    }

    // One worker: its own analyzer (built on this thread, so the warm-up runs in parallel too), then
    // file indices from the queue in increasing order, replaying the import loads of every earlier
    // file it skipped before analysing the next. See `AnalyzeAllFiles` for why.
    private func RunAnalysisWorker(state: MultiFileCompilerAnalysisWorker): void {
        analyzer: Analyzer? = state.Analyzer
        try {
            if analyzer == null {
                created := CreateAnalyzer()
                created.SetProjectSourceTexts(_sourceTexts)
                created.SeedProjectCompilationUnits(_reusableUnits)
                created.SeedProjectNamespaces(_projectRoot, state.ProjectNamespaces)
                analyzer = created
            }
        } catch ex: Exception {
            state.Failure = ex
            return
        }

        preloaded := 0
        next := 0
        while state.Queue.TryDequeue(out next) {
            while preloaded < next {
                analyzer.PreloadImportedAssemblies(state.Units[preloaded])
                preloaded = preloaded + 1
            }

            try {
                state.Outcomes[next] = AnalyzeOneFile(analyzer, state.Files[next], state.Units[next])
            } catch ex: Exception {
                state.Outcomes[next] = new MultiFileCompiler.MultiFileCompilerFileAnalysis(null, null, new List<CompilerError>(), new Dictionary<string, string>(), ex, false)
            }
            preloaded = next + 1
        }
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

    // Every file the pipeline has not already reported an ERROR for, linted. The skip list is built
    // from the errors reported SO FAR, which now includes the analysis's: a file that does not analyse
    // has no binding facts worth judging its imports against, and the diagnostic it already has is the
    // one its author needs.
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
    //
    // THE LINT RUNS AFTER THE ANALYSIS, AND IT HAS TO. Two of the linter's rules — NL010 ("this import
    // is not used") and NL002 ("this name has no import") — are answered by what each file BOUND, and
    // those facts are stamped on a compilation unit by the ANALYZER. Linting first produced units with
    // no facts, so a strict-mode build was the one route that could not report either rule, and the
    // two most consequential lint fixes in the language — the one that deletes an import line and the
    // one that adds one — were invisible exactly where a build would have caught them.
    //
    // THE GATE IS STILL THE LINT'S. A strict-lint error still ends the pipeline before emission; what
    // changed is only that the analysis has already run when it does, so its diagnostics are reported
    // alongside rather than instead. A file the analysis reported an ERROR for is skipped by the lint
    // pass itself, which is the same rule it already applied to a file with parse errors.
    private func RunLegacyValidationPipeline(validateStrictLint: bool, out strictLintFailed: bool): void {
        strictLintFailed = false
        parseMark := CompilerPhaseTimings.Begin(_phaseProject, "parse")
        ParseAllFiles()
        CompilerPhaseTimings.End(parseMark)
        importsMark := CompilerPhaseTimings.Begin(_phaseProject, "import-graph")
        DetectCircularFileImports()
        CompilerPhaseTimings.End(importsMark)
        AnalyzeAllFiles()

        errorsBeforeLint := 0
        for existingError in _allErrors {
            if existingError.Severity == ErrorSeverity.Error {
                errorsBeforeLint++
            }
        }
        if (validateStrictLint) {
            lintMark := CompilerPhaseTimings.Begin(_phaseProject, "lint")
            AddStrictLintDiagnosticsFromParsedSources()
            CompilerPhaseTimings.End(lintMark)
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
        emitParseMark := CompilerPhaseTimings.Begin(_phaseProject, "emit.parse")
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
        let program: NSharpLang.Compiler.Columnar.ColumnarProgramInput = null
        if (!ColumnarProgramInputBuilder.TryBuildMultiFile(sources, _sourceFiles, _projectRoot, out program)) {
            CompilerPhaseTimings.End(emitParseMark)
            return false
        }
        CompilerPhaseTimings.End(emitParseMark)
        // Call-site overload selection belongs to the analyzer's BindNSharpCall walk. Carry each
        // analyzed file's semantic model into emission so a free-function call can target the exact
        // declaration BindNSharpCall selected instead of re-ranking the group's CLR signatures.
        semanticFileId := 0
        while semanticFileId < _sourceFiles.Count {
            semanticModel: SemanticModel = null
            semanticPath := Path.GetFullPath(_sourceFiles[semanticFileId])
            if _semanticModels.TryGetValue(semanticPath, out semanticModel) {
                program.SetSemanticModelForFileId(semanticFileId, semanticModel)
            }
            semanticFileId = semanticFileId + 1
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
        codegenMark := CompilerPhaseTimings.Begin(_phaseProject, "emit.codegen")
        if (!ColumnarIlEmitter.TryEmitColumnarAssembly(assemblyName, "Program", program, isExecutable, out assembly, assemblyVersion, referenceAssemblyPaths)) {
            CompilerPhaseTimings.End(codegenMark)
            return false
        }
        CompilerPhaseTimings.End(codegenMark)
        writeMark := CompilerPhaseTimings.Begin(_phaseProject, "emit.write")
        File.WriteAllBytes(outputPath, assembly)
        written := TryEmitReferenceAssembly(outputPath, referenceAssemblyPaths)
        CompilerPhaseTimings.End(writeMark)
        return written
    }

    // The surface of what was just emitted, written only when a caller asked for one.
    private func TryEmitReferenceAssembly(outputPath: string, referenceAssemblyPaths: IReadOnlyList<string>): bool {
        if !_emitReferenceAssembly {
            return true
        }

        keepInternals := false
        grantsConfig := _config
        if grantsConfig != null {
            declaredGrants := grantsConfig.InternalsVisibleTo
            if declaredGrants != null && declaredGrants.Count > 0 {
                keepInternals = true
            }
        }

        if !ColumnarReferenceAssemblyWriter.TryWrite(
            outputPath,
            MultiFileCompiler.ReferenceAssemblyPathFor(outputPath),
            referenceAssemblyPaths,
            keepInternals
        ) {
            ColumnarDeclineTrace.Record(
                "emit.reference-assembly",
                "the reference assembly for '" + Path.GetFileName(outputPath) + "' could not be written",
                -1,
                0,
                ""
            )
            return false
        }

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
        decline = state.Diagnostic ?? ColumnarDeclineDiagnostic.Empty
        return state.Emitted
    }

    // THE EMISSION THREAD'S IDENTITY, BOTH HALVES OF IT. Which `internal` members of a referenced
    // assembly this emission may reach depends on the name the assembly being emitted carries, and
    // which assemblies IT befriends is `internalsVisibleTo:` from the same project file; the back
    // end's accessibility filters and its assembly-attribute writer are static functions with no
    // compilation in hand — so both are opened as a thread-local scope here, on the very thread the
    // whole emit walk runs on, and closed when it ends. `InternalsVisibleToEmissionScope` explains
    // why the scope is thread-local.
    private func RunColumnarEmissionOnCurrentThread(state: MultiFileCompilerEmissionThreadState, assemblyName: string, outputPath: string): void {
        grantsConfig := _config
        declaredGrants: List<string>? = null
        if grantsConfig != null {
            declaredGrants = grantsConfig.InternalsVisibleTo
        }
        InternalsVisibleToEmissionScope.Begin(assemblyName, declaredGrants)
        try {
            state.Emitted = TryEmitWithColumnarBackend(assemblyName, outputPath)
            if !state.Emitted {
                state.Diagnostic = BuildColumnarDeclineDiagnostic()
            }
        } catch ex: Exception {
            // A FAULT IN THE CODE GENERATOR IS A DECLINE THAT NAMES A MEMBER, NEVER A STACK TRACE.
            // The walk that threw has already unwound by the time this frame runs, so the only thing
            // left that says WHERE in the program the compiler gave up is the member scope the emission
            // thread was inside. A reader handed "The specified method cannot be dynamic or global and
            // must be declared on a generic type definition" with no member cannot find the shape that
            // produced it; a decline carrying the member and its source span can be reduced in minutes.
            ColumnarDeclineTrace.Record(
                "emit.internal-error",
                "the code generator failed on this member: " + ex.Message,
                -1,
                0,
                ColumnarDeclineTrace.CurrentMemberName()
            )
            state.Emitted = false
            state.Diagnostic = BuildColumnarDeclineDiagnostic()
        } finally {
            InternalsVisibleToEmissionScope.End()
        }
    }

    private func RequiresColumnarSoaEmission(): bool {
        compilationUnits := _compilationUnits.Values
        if !_soaEnabled {
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

        declineLog := _columnarDeclineLog
        if (declineLog == null && !_debugLoggingEnabled) {
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
            if (declineLog != null) {
                declineLog.WriteLine(traceLine)
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
