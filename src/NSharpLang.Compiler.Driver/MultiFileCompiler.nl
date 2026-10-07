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
    // Built on first use: a compilation the up-to-date check answers never loads a single assembly.
    private _sharedAnalyzerValue: Analyzer?
    private readonly _declaredOneProgram: bool
    private _incrementalBuild: bool
    private _wasUpToDate: bool
    private _incrementalState: IncrementalCompilationState?
    private _incrementalPlan: IncrementalCompilationPlan?
    private readonly _pendingRecords: Dictionary<string, IncrementalFileRecord>
    // The texts the incremental plan was made from: every later read of a source in the same
    // compilation sees these, so a file edited mid-compilation cannot pair one text's plan with
    // another text's parse.
    private readonly _plannedTexts: Dictionary<string, string>
    // Set once `CompileForAnalysis` has run, so `ValidateAnalyzedEmission` can refuse to validate a
    // program nothing analysed.
    private _analysisCompleted: bool
    // The image the last emission produced, whether it was written (`CompileToIlAssembly`) or only
    // validated (`ValidateAnalyzedEmission`); null until an emission succeeds.
    private _emittedImage: byte[]?
    private readonly _debugLoggingEnabled: bool
    private readonly _sourceTextOverrides: IReadOnlyDictionary<string, string>
    private readonly _preprocessorSymbols: IReadOnlySet<string>
    private readonly _sourceTexts: Dictionary<string, string>
    private readonly _projectBindings: BindingMap
    private readonly _projectTypeDeclarationFiles: Dictionary<string, string>
    // The parses an analyzer's own parse of the snapshot would reproduce exactly (full path -> parse):
    // files no conditional-compilation directive changed, listed under their full path. Every analyzer
    // of the compilation is seeded with them (`Analyzer.SeedProjectParses`).
    private readonly _reusableParses: Dictionary<string, FileParseAst>
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
    private _workers: int

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
    FriendGrants: InternalsVisibleToGrants => SharedAnalyzer().GetFriendGrants()

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
            analyzer := _sharedAnalyzerValue
            if analyzer != null {
                analyzer.SoaEnabled = value
            }
        }
    }

    // WHETHER THIS COMPILATION MAY BE ANSWERED BY ITS UP-TO-DATE STAMP (`IncrementalBuildStamp`).
    // Off unless the caller asks: the stamp lives in the project's `obj/` and describes an output
    // the caller will keep, which is true of `nlc build`, `run`, `test` and a referenced project's
    // build, and not of a check (which writes nothing) or an editor's buffers.
    IncrementalBuild: bool {
        get {
            return _incrementalBuild
        }
        set {
            _incrementalBuild = value
        }
    }

    // True after `CompileToIlAssembly` answered from the stamp: nothing was parsed, analysed or
    // emitted, so the units, models, index and systems report are empty. A caller that needs those
    // (a perf report, a query) leaves `IncrementalBuild` off.
    WasUpToDate: bool => _wasUpToDate

    // THE STATE A PREVIOUS COMPILATION OF THIS PROJECT LEFT (`IncrementalCompilationState`), held by
    // a caller that compiles the same project repeatedly in one process. When it is set, the analyzer
    // it carries is reused, every file whose analysis is still valid is not re-analysed (its unit,
    // diagnostics and semantic model are taken from the state), and the state is replaced with this
    // compilation's when analysis finishes. Every pass after analysis — import cycles, the systems
    // policy, the lint, emission — still runs over the whole project.
    IncrementalState: IncrementalCompilationState? {
        get {
            return _incrementalState
        }
        set {
            _incrementalState = value
        }
    }

    // HOW MANY WORKERS EACH FAN-OUT PHASE USES -- the analysis pass and the columnar back end's
    // per-file parse: 0 (the default) lets `CompilerParallelism` decide from the project's size and
    // the machine; a positive count is used as given, capped by the number of files. A caller that
    // must exercise one path or the other -- the serial-versus-parallel differential, an estate row --
    // says so here rather than through `NSHARP_COMPILER_WORKERS`, which every compilation in the
    // process would see.
    Workers: int {
        get {
            return _workers
        }
        set {
            _workers = value
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
        _reusableParses = new Dictionary<string, FileParseAst>(StringComparer.OrdinalIgnoreCase)
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

        _sharedAnalyzerValue = null
        _declaredOneProgram = config != null
        _workers = 0
        _incrementalBuild = false
        _wasUpToDate = false
        _incrementalState = null
        _incrementalPlan = null
        _pendingRecords = new Dictionary<string, IncrementalFileRecord>(StringComparer.OrdinalIgnoreCase)
        _plannedTexts = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        _analysisCompleted = false
        _emittedImage = null
    }

    // The configuration this compiler was built with; the constructor already replaced a missing one
    // with the default, so this never constructs anything.
    private func EffectiveConfig(): ProjectConfig {
        return _config ?? ProjectFileParser.CreateDefault(null)
    }

    // One analyzer instance owns the complete repeated-call lifetime, created the first time a pass
    // needs it -- so a compilation the up-to-date stamp answers never loads a reference -- or handed
    // over by the incremental state, whose previous compilation created it.
    private func SharedAnalyzer(): Analyzer {
        existing := _sharedAnalyzerValue
        if existing != null {
            return existing
        }

        state := _incrementalState
        if state != null {
            retained := state.RetainedAnalyzer
            if retained != null {
                _sharedAnalyzerValue = retained
                return retained
            }
        }

        loadMark := CompilerPhaseTimings.Begin(_phaseProject, "load-references")
        analyzer := CreateAnalyzer()
        CompilerPhaseTimings.End(loadMark)
        _sharedAnalyzerValue = analyzer
        if state != null {
            state.RetainedAnalyzer = analyzer
        }
        return analyzer
    }

    // An analyzer for this compilation, built the one way: the shared analyzer and every parallel
    // analysis worker's come from here, so they cannot disagree about the assemblies, the project
    // references, the SoA gate or the one-program rule they analyse under.
    private func CreateAnalyzer(): Analyzer {
        analyzer := new Analyzer()
        analyzer.SoaEnabled = _soaEnabled
        analyzer.LoadSystemAssemblies()
        analyzer.LoadFromProjectConfig(EffectiveConfig(), _projectRoot)
        // A caller that hands over a project configuration compiles these files into ONE assembly —
        // a parsed `project.yml`, or a virtual project like the playground's. A caller with none (a
        // folder of standalone scripts checked as a directory) leaves the analyzer to ask the root.
        if _declaredOneProgram {
            analyzer.DeclareOneProgram()
        }
        // One compilation reads one directory tree; the analyzer may keep its view of it from one
        // file's analysis to the next. The view is keyed by the source snapshot, which every
        // compilation replaces, so an analyzer the incremental state retains re-reads the tree on the
        // next compilation.
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
        if _sourceTextOverrides.TryGetValue(fullPath, out text) {
            return text
        }
        let planned: string? = null
        if _plannedTexts.TryGetValue(fullPath, out planned) {
            return planned
        }
        return File.ReadAllText(fullPath)
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
            if TryReuseParsedFile(sourceFile) {
                continue
            }

            errorsBefore := _allErrors.Count
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
            reusableParse: FileParseAst? = null
            if (parseResult.CompilationUnit != null) {
                _compilationUnits[sourceFile] = parseResult.CompilationUnit
                // The analyzer parses the RAW snapshot text under the FULL path; this parse is that
                // parse exactly when preprocessing changed nothing and the path is already full.
                fullSourcePath := Path.GetFullPath(sourceFile)
                if string.Equals(live, source, StringComparison.Ordinal) && string.Equals(fullSourcePath, sourceFile, StringComparison.Ordinal) {
                    _reusableParses[fullSourcePath] = parseResult
                    reusableParse = parseResult
                }
            }
            RecordParsedFile(sourceFile, parseResult.CompilationUnit, errorsBefore, reusableParse)
            AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   Done parsing {Path.GetFileName(sourceFile)}")
        }
    }

    // A file whose analysis the plan reuses keeps the unit that analysis ran over — the analyzer
    // stamped its import-usage facts on it, and the lint reads them — and replays its parse
    // diagnostics in the same position a fresh parse would have reported them.
    private func TryReuseParsedFile(sourceFile: string): bool {
        plan := _incrementalPlan
        state := _incrementalState
        if plan == null || state == null {
            return false
        }

        fullPath := Path.GetFullPath(sourceFile)
        if !plan.ReusedFiles.Contains(fullPath) {
            return false
        }

        fileRecord := state.Files[fullPath]
        _sourceTexts[fullPath] = ReadSourceText(sourceFile)
        _allErrors.AddRange(fileRecord.ParseErrors)
        unit := fileRecord.Unit
        if unit != null {
            _compilationUnits[sourceFile] = unit
        }
        reusableParse := fileRecord.ReusableParse
        if reusableParse != null {
            _reusableParses[fullPath] = reusableParse
        }
        _pendingRecords[fullPath] = fileRecord
        return true
    }

    private func RecordParsedFile(sourceFile: string, unit: CompilationUnit?, errorsBefore: int, reusableParse: FileParseAst?): void {
        plan := _incrementalPlan
        if plan == null {
            return
        }

        fullPath := Path.GetFullPath(sourceFile)
        fileRecord := new IncrementalFileRecord(fullPath, plan.Summaries[fullPath])
        fileRecord.Unit = unit
        fileRecord.ReusableParse = reusableParse
        fileRecord.ParseErrors.AddRange(_allErrors.GetRange(errorsBefore, _allErrors.Count - errorsBefore))
        _pendingRecords[fullPath] = fileRecord
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
    // THE THREADING MODEL. Worker 0 is the shared analyzer (`SharedAnalyzer()`); every other worker builds its own `Analyzer`
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
        reused := new List<bool>(_compilationUnits.Count)
        plan := _incrementalPlan
        filesToAnalyze := 0
        charactersToAnalyze := 0L
        for kvp in _compilationUnits {
            fullPath := Path.GetFullPath(kvp.Key)
            isReused := plan != null && plan.ReusedFiles.Contains(fullPath)
            files.Add(kvp.Key)
            units.Add(kvp.Value)
            reused.Add(isReused)
            if !isReused {
                filesToAnalyze = filesToAnalyze + 1
                text: string? = null
                if _sourceTexts.TryGetValue(fullPath, out text) && text != null {
                    charactersToAnalyze = charactersToAnalyze + text.Length
                }
            }
        }

        // A file whose recorded analysis the incremental plan reuses is not analysed: its outcome is
        // the record's. Only the others go to the workers.
        outcomes := new MultiFileCompilerFileAnalysis[files.Count]
        pendingIndex := 0
        while pendingIndex < outcomes.Length {
            if reused[pendingIndex] {
                fileRecord := _pendingRecords[Path.GetFullPath(files[pendingIndex])]
                outcomes[pendingIndex] = new MultiFileCompiler.MultiFileCompilerFileAnalysis(fileRecord.SemanticModel, fileRecord.Bindings, fileRecord.AnalysisErrors, fileRecord.TypeDeclarationFiles, null, false)
            } else {
                outcomes[pendingIndex] = new MultiFileCompiler.MultiFileCompilerFileAnalysis(null, null, new List<CompilerError>(), new Dictionary<string, string>(), null, true)
            }
            pendingIndex = pendingIndex + 1
        }

        workerCount := CompilerParallelism.WorkerCount(filesToAnalyze, charactersToAnalyze)
        if _workers > 0 {
            workerCount = Math.Min(_workers, Math.Max(filesToAnalyze, 1))
        }
        sharedAnalyzer := SharedAnalyzer()
        if workerCount <= 1 {
            sharedAnalyzer.SetProjectSourceTexts(_sourceTexts)
            sharedAnalyzer.SeedProjectParses(_reusableParses)
            index := 0
            while index < files.Count {
                if !reused[index] {
                    outcomes[index] = AnalyzeOneFile(sharedAnalyzer, files[index], units[index])
                }
                index = index + 1
            }
        } else {
            AnalyzeFilesInParallel(sharedAnalyzer, files, units, reused, outcomes, workerCount)
        }

        analyzedFiles := 0
        reusedFiles := 0
        mergeIndex := 0
        while mergeIndex < files.Count {
            outcome := outcomes[mergeIndex]
            failure := outcome.Failure
            if failure != null {
                CompilerPhaseTimings.End(analysisMark)
                throw failure
            }
            MergeFileAnalysis(files[mergeIndex], outcome)
            if reused[mergeIndex] {
                reusedFiles = reusedFiles + 1
            } else {
                analyzedFiles = analyzedFiles + 1
                RecordAnalyzedFile(Path.GetFullPath(files[mergeIndex]), units[mergeIndex], outcome.SemanticModel, outcome.Bindings, outcome.Errors, outcome.TypeDeclarationFiles)
            }
            mergeIndex = mergeIndex + 1
        }

        CommitIncrementalState(analyzedFiles, reusedFiles)
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

    // Only the files the incremental plan does not reuse are queued; a worker still replays the
    // import loads of every earlier file, reused ones included, so its loaded-assembly list is the
    // serial run's.
    private func AnalyzeFilesInParallel(sharedAnalyzer: Analyzer, files: List<string>, units: List<CompilationUnit>, reused: List<bool>, outcomes: MultiFileCompilerFileAnalysis[], workerCount: int): void {
        queue := new ConcurrentQueue<int>()
        index := 0
        while index < files.Count {
            if !reused[index] {
                queue.Enqueue(index)
            }
            index = index + 1
        }

        // The shared analyzer takes the snapshot here, on this thread, and computes the project's
        // namespace set once; every other worker is seeded with it rather than parsing the files
        // outside the snapshot again.
        sharedAnalyzer.SetProjectSourceTexts(_sourceTexts)
        sharedAnalyzer.SeedProjectParses(_reusableParses)
        projectNamespaces := sharedAnalyzer.ProjectNamespacesFor(_projectRoot)

        threads := new List<Thread>(workerCount)
        states := new List<MultiFileCompilerAnalysisWorker>(workerCount)
        worker := 0
        while worker < workerCount {
            workerAnalyzer: Analyzer? = null
            if worker == 0 {
                workerAnalyzer = sharedAnalyzer
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
        resolved: Analyzer? = state.Analyzer
        try {
            if resolved == null {
                created := CreateAnalyzer()
                created.SetProjectSourceTexts(_sourceTexts)
                created.SeedProjectParses(_reusableParses)
                created.SeedProjectNamespaces(_projectRoot, state.ProjectNamespaces)
                resolved = created
            }
        } catch ex: Exception {
            state.Failure = ex
            return
        }
        if resolved == null {
            return
        }
        analyzer: Analyzer = resolved

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
        _analysisCompleted = true
    }

    // PROVE THAT WHAT `CompileForAnalysis` ANALYSED ALSO EMITS, AND WRITE NOTHING. `nlc check` reports
    // diagnostics only, but one class of them exists nowhere except in the code generator: a program
    // the analysis accepts and the IL back end refuses (NL103, `ColumnarEmissionDiagnostics`). Those
    // refusals are decided while the back end walks every body — the planners that pick an
    // instruction sequence are the same code that hands it to the `ILGenerator`, and the image's own
    // metadata serialisation can refuse it last — so the walk runs exactly as `CompileToIlAssembly`
    // runs it, from this compiler's own units and semantic models, and the finished image is kept in
    // memory (`EmittedImage`) instead of being written: no output file, no scratch directory, no
    // reference assembly, and `CompilerWorkCounters.AssembliesEmitted` is not counted. It reports the
    // way a build does: nothing is emitted while an analysis error stands, and a decline is appended
    // to `AllErrors`.
    func ValidateAnalyzedEmission(assemblyName: string): MultiFileCompilationResult {
        if !_analysisCompleted {
            throw new InvalidOperationException("ValidateAnalyzedEmission needs CompileForAnalysis to have run on this compiler first.")
        }

        return EmitAfterValidation(assemblyName, null, null, "", null)
    }

    // The image the last successful emission of this compiler produced (written or only validated),
    // or null when nothing was emitted.
    EmittedImage: byte[]? => _emittedImage

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
        PrepareIncrementalPlan()
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
            // The emit-only route has always had a loaded analyzer in the process by the time it
            // emits; keep it that way, because the emitter's host-assembly scan sees what is loaded.
            SharedAnalyzer()
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

        // THE UP-TO-DATE CHECK. When every input this compilation would read still has the value the
        // last successful compilation of the same output recorded, that compilation's output and
        // diagnostics ARE this one's: nothing is parsed, analysed or emitted.
        stampPath: string? = null
        stampKey := ""
        capture: IncrementalBuildInputCapture? = null
        if CanUseIncrementalStamp(outputPath) {
            stampKey = ComputeIncrementalKey(assemblyName, outputPath, validateStrictLint, validateWithLegacyAnalysis)
            stampPath = IncrementalBuildStamp.PathFor(_projectRoot, assemblyName, outputPath)
            stamp := IncrementalBuildStamp.TryRead(stampPath, stampKey)
            if stamp != null && stamp.IsCurrent() {
                _wasUpToDate = true
                _allErrors.AddRange(stamp.Diagnostics)
                return new MultiFileCompilationResult(true, _allErrors, Path.GetFullPath(outputPath))
            }

            newCapture := new IncrementalBuildInputCapture()
            newCapture.CaptureBeforeCompile(_projectRoot, EffectiveConfig(), _sourceFiles)
            capture = newCapture
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

        return EmitAfterValidation(assemblyName, outputPath, stampPath, stampKey, capture)
    }

    // The emission half of a compilation whose validation has run: refuse on any error, emit,
    // report a decline, and record the up-to-date stamp when one was asked for. A null output path
    // validates the emission without writing it (`ValidateAnalyzedEmission`).
    private func EmitAfterValidation(assemblyName: string, outputPath: string?, stampPath: string?, stampKey: string, capture: IncrementalBuildInputCapture?): MultiFileCompilationResult {
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
            if outputPath != null {
                Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? _projectRoot)
            }

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
        if success && outputPath != null {
            resultPath = outputPath
            if stampPath != null && capture != null {
                WriteIncrementalStamp(stampPath, stampKey, capture, outputPath)
            }
        }
        return new MultiFileCompilationResult(
            resultSuccess,
            resultErrors,
            resultPath
        )
    }

    // ---- the in-memory incremental state ---------------------------------------------------------

    // Decides, before anything is parsed, which files' analyses the state lets this compilation
    // reuse. A different environment (or metadata that moved on disk) resets the state first.
    private func PrepareIncrementalPlan(): void {
        state := _incrementalState
        if state == null {
            return
        }

        paths := new List<string>()
        texts := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        for sourceFile in _sourceFiles {
            fullPath := Path.GetFullPath(sourceFile)
            if !texts.ContainsKey(fullPath) {
                paths.Add(fullPath)
                texts[fullPath] = ReadSourceText(sourceFile)
            }
        }
        for planned in texts {
            _plannedTexts[planned.Key] = planned.Value
        }

        environmentKey := ComputeIncrementalEnvironmentKey()
        if environmentKey != state.EnvironmentKey || !state.MetadataIsCurrent() {
            state.Reset(environmentKey)
        }

        _incrementalPlan = IncrementalCompilationPlan.Create(state, paths, texts)
    }

    // What every per-file analysis in the state was computed under, other than the sources
    // themselves: the compiler, the configuration, the defines, the options analysis reads, and the
    // content of every non-source input the analyzer loads (references, the restore output, the
    // project file, the test-source switch).
    private func ComputeIncrementalEnvironmentKey(): string {
        key := new IncrementalKeyBuilder()
        key.Add("format", IncrementalFileSummary.FormatVersion.ToString())
        key.Add("compiler", IncrementalCompilerIdentity.Current())
        key.Add("project-root", Path.GetFullPath(_projectRoot))
        key.AddBool("aot", _aotMode)
        key.AddBool("soa", _soaEnabled)
        key.AddBool("one-program", _declaredOneProgram)
        key.Add("config", IncrementalConfigFingerprint.Describe(_config))
        symbols := new List<string>(_preprocessorSymbols)
        symbols.Sort(StringComparer.Ordinal)
        key.Add("defines", string.Join(",", symbols))
        key.Add("nuget-packages", Environment.GetEnvironmentVariable("NUGET_PACKAGES"))
        key.Add("user-profile", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile))
        key.Add("current-directory", Environment.CurrentDirectory)
        capture := new IncrementalBuildInputCapture()
        capture.CaptureEnvironment(_projectRoot, EffectiveConfig())
        for entry in capture.Entries {
            key.Add(entry.Kind.ToString() + "|" + entry.Path, entry.Value)
        }
        return key.Build()
    }

    private func RecordAnalyzedFile(fullPath: string, unit: CompilationUnit, semanticModel: SemanticModel?, bindings: BindingMap?, analysisErrors: List<CompilerError>, typeDeclarationFiles: Dictionary<string, string>): void {
        plan := _incrementalPlan
        if plan == null {
            return
        }

        fileRecord: IncrementalFileRecord = null
        if !_pendingRecords.TryGetValue(fullPath, out fileRecord) {
            return
        }

        fileRecord.Analyzed = true
        fileRecord.SemanticModel = semanticModel
        fileRecord.Bindings = bindings
        fileRecord.AnalysisErrors = new List<CompilerError>(analysisErrors)
        fileRecord.TypeDeclarationFiles = typeDeclarationFiles
        fileRecord.Dependencies = plan.DependenciesOf(fullPath)
        for importPath in IncrementalBuildInputCapture.FileImportCandidates(_projectRoot, fullPath, unit) {
            fileRecord.ImportedFileHashes[importPath] = ContentHash.OfFileOrMissing(importPath)
        }
    }

    // The state becomes this compilation's: the records of every file it parsed or reused, and
    // nothing for a file that left the project.
    private func CommitIncrementalState(analyzedFiles: int, reusedFiles: int): void {
        state := _incrementalState
        plan := _incrementalPlan
        if state == null || plan == null {
            return
        }

        analyzerWasNew := state.MetadataEntries.Count == 0
        state.Files.Clear()
        for pending in _pendingRecords {
            state.Files[pending.Key] = pending.Value
        }
        state.LastFilesAnalyzed = analyzedFiles
        state.LastFilesReused = reusedFiles
        state.LastWasFull = reusedFiles == 0
        analyzer := _sharedAnalyzerValue
        if analyzer != null && analyzerWasNew {
            capture := new IncrementalBuildInputCapture()
            capture.CaptureMetadataInputs(analyzer.MetadataInputAssemblyPaths(), analyzer.MetadataSearchDirectories())
            state.MetadataEntries.AddRange(capture.Entries)
        }
    }

    private func CanUseIncrementalStamp(outputPath: string): bool {
        if !_incrementalBuild {
            return false
        }
        // The stamp lives in the project's own `obj/`, so it is kept only for an output inside the
        // project: a build sent elsewhere (`nlc build -o /tmp/x`) leaves the source tree untouched.
        if !IncrementalBuildStamp.IsInsideProject(_projectRoot, outputPath) {
            return false
        }
        // An editor's unsaved buffers are not files the stamp could compare later.
        if _sourceTextOverrides.Count > 0 {
            return false
        }
        // A caller asking for the decline trace or the debug log wants the pipeline to run.
        if _columnarDeclineLog != null || _debugLoggingEnabled {
            return false
        }
        return IncrementalBuildPolicy.IsEnabled()
    }

    // Everything this compilation depends on that is not a file (see `IncrementalBuildInputs`).
    private func ComputeIncrementalKey(assemblyName: string, outputPath: string, validateStrictLint: bool, validateWithLegacyAnalysis: bool): string {
        key := new IncrementalKeyBuilder()
        key.Add("format", IncrementalBuildStamp.FormatVersion.ToString())
        key.Add("compiler", IncrementalCompilerIdentity.Current())
        key.Add("project-root", Path.GetFullPath(_projectRoot))
        key.Add("assembly", assemblyName)
        key.Add("output", Path.GetFullPath(outputPath))
        key.AddBool("strict-lint", validateStrictLint)
        key.AddBool("analysis", validateWithLegacyAnalysis)
        key.AddBool("aot", _aotMode)
        key.AddBool("reference-assembly", _emitReferenceAssembly)
        key.AddBool("soa", _soaEnabled)
        key.AddBool("one-program", _declaredOneProgram)
        key.Add("config", IncrementalConfigFingerprint.Describe(_config))
        symbols := new List<string>(_preprocessorSymbols)
        symbols.Sort(StringComparer.Ordinal)
        key.Add("defines", string.Join(",", symbols))
        key.Add("source-count", _sourceFiles.Count.ToString())
        for sourceFile in _sourceFiles {
            key.Add("source", Path.GetFullPath(sourceFile))
        }
        // Where the package cache is, and the directory a project with no `name:` is named after.
        key.Add("nuget-packages", Environment.GetEnvironmentVariable("NUGET_PACKAGES"))
        key.Add("user-profile", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile))
        key.Add("current-directory", Environment.CurrentDirectory)
        return key.Build()
    }

    private func WriteIncrementalStamp(stampPath: string, stampKey: string, capture: IncrementalBuildInputCapture, outputPath: string): void {
        capture.CaptureFileImports(_projectRoot, _compilationUnits)
        analyzer := _sharedAnalyzerValue
        if analyzer != null {
            capture.CaptureMetadataInputs(analyzer.MetadataInputAssemblyPaths(), analyzer.MetadataSearchDirectories())
        }

        stamp := new IncrementalBuildStamp(stampKey)
        stamp.Entries.AddRange(capture.Entries)
        stamp.AddOutput(outputPath)
        if _emitReferenceAssembly {
            stamp.AddOutput(MultiFileCompiler.ReferenceAssemblyPathFor(outputPath))
        }
        stamp.Diagnostics.AddRange(_allErrors)
        if stamp.TryWrite(stampPath) {
        }
    }

    // Emit the whole assembly through the standalone columnar backend; with no output path the image
    // is kept in memory only.
    private func TryEmitWithColumnarBackend(assemblyName: string, outputPath: string?): bool {
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
        if (!ColumnarProgramInputBuilder.TryBuildMultiFile(sources, _sourceFiles, _projectRoot, out program, _workers)) {
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
        _emittedImage = assembly
        if outputPath == null {
            return true
        }
        writeMark := CompilerPhaseTimings.Begin(_phaseProject, "emit.write")
        File.WriteAllBytes(outputPath, assembly)
        CompilerWorkCounters.Shared.CountAssemblyEmitted()
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
    private func EmitOnWideStackThread(assemblyName: string, outputPath: string?, out decline: ColumnarDeclineDiagnostic): bool {
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
    private func RunColumnarEmissionOnCurrentThread(state: MultiFileCompilerEmissionThreadState, assemblyName: string, outputPath: string?): void {
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
