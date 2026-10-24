namespace NSharpLang.Compiler

import System
import System.Collections.Concurrent
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Linq
import System.Text.Json
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

    // One file's parse result and any preprocessing diagnostics, produced independently by a cold
    // persisted-check parse worker and merged back on the caller in source order.
    private class MultiFileCompilerFileParse {
        Result: FileParseAst?
        PreprocessorErrors: List<CompilerError>
        Failure: Exception?
        WasPreparsed: bool

        constructor() {
            Result = null
            PreprocessorErrors = new List<CompilerError>()
            Failure = null
            WasPreparsed = false
        }
    }

    private class MultiFileCompilerParseWorker {
        Files: List<string>
        Sources: List<string>
        Symbols: IReadOnlySet<string>
        Outcomes: MultiFileCompilerFileParse[]
        Queue: ConcurrentQueue<int>

        constructor(files: List<string>, sources: List<string>, symbols: IReadOnlySet<string>, outcomes: MultiFileCompilerFileParse[], queue: ConcurrentQueue<int>) {
            Files = files
            Sources = sources
            Symbols = symbols
            Outcomes = outcomes
            Queue = queue
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
        // The shared analyzer's reference metadata, which a worker's own analyzer reads.
        ReferenceMetadata: SharedReferenceMetadata?

        constructor(analyzer: Analyzer?, files: List<string>, units: List<CompilationUnit>, outcomes: MultiFileCompilerFileAnalysis[], queue: ConcurrentQueue<int>, projectNamespaces: HashSet<string>, referenceMetadata: SharedReferenceMetadata?) {
            Analyzer = analyzer
            Files = files
            Units = units
            Outcomes = outcomes
            Queue = queue
            ProjectNamespaces = projectNamespaces
            Failure = null
            ReferenceMetadata = referenceMetadata
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
    private _checkStampPath: string?
    private _checkStampKey: string
    private _checkStampAnalysisReuseKey: string
    private _checkInputCapture: IncrementalBuildInputCapture?
    private _checkStampEntries: List<IncrementalInputEntry>?
    // Whether a caller handed this compiler its incremental state (`IncrementalState`); such a state,
    // and the analyzer it retains, belongs to that caller's session and outlives this compiler.
    private _incrementalStateFromCaller: bool
    private _checkStateSeededFromStamp: bool
    private _persistedCheckPartial: bool
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
    private _parsedFilesCount: int
    private readonly _debugLoggingEnabled: bool
    private readonly _sourceTextOverrides: IReadOnlyDictionary<string, string>
    private readonly _preprocessorSymbols: IReadOnlySet<string>
    private readonly _sourceTexts: Dictionary<string, string>
    private _projectBindings: BindingMap
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
    private _systemsDiagnosticsOnly: bool
    private _soaEnabled: bool
    private _columnarDeclineLog: TextWriter?
    private readonly _phaseProject: string
    private _workers: int

    CompilationUnits: IReadOnlyDictionary<string, CompilationUnit> => _compilationUnits
    SemanticModels: IReadOnlyDictionary<string, SemanticModel> => _semanticModels
    AllErrors: IReadOnlyList<CompilerError> => _allErrors
    SourceFiles: IReadOnlyList<string> => _sourceFiles
    SourceTexts: IReadOnlyDictionary<string, string> => _sourceTexts
    FilesToLint: IReadOnlyList<string> {
        get {
            plan := _incrementalPlan
            if !_persistedCheckPartial || plan == null {
                return _sourceFiles
            }

            files := new List<string>()
            for sourceFile in _sourceFiles {
                if !plan.ReusedFiles.Contains(Path.GetFullPath(sourceFile)) {
                    files.Add(sourceFile)
                }
            }
            return files
        }
    }

    // A fresh index wraps the same live stores on every read.
    ProjectIndex: ProjectIndex => new ProjectIndex(_projectBindings, _projectTypeDeclarationFiles)
    PerformanceFacts: PerformanceFactStore => _performanceFacts
    SystemsReport: SystemsReport => _systemsReport
    SystemsDiagnosticsOnly: bool {
        get {
            return _systemsDiagnosticsOnly
        }
        set {
            _systemsDiagnosticsOnly = value
        }
    }

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
    // Off unless the caller asks: this build stamp lives in the project's `obj/` and describes an
    // output the caller will keep, which is true of `nlc build`, `run`, `test` and a referenced
    // project's build. Checks use the same stamp owner through the separate result methods below;
    // editor buffers cannot use either disk result.
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

    // Reads a persisted check result before any source is parsed. The stamp uses the same input
    // capture, checksum and atomic replacement as the build stamp; the output-mode and check
    // options only distinguish which deterministic result is being replayed.
    func TryReadCheckResult(assemblyName: string, outputMode: int, useBuiltReferences: bool, backendOption: string?): IncrementalCheckResult? {
        if !CanUseIncrementalCheckStamp() {
            return null
        }

        key := ComputeCheckResultKey(assemblyName, outputMode, useBuiltReferences, backendOption)
        analysisReuseKey := ComputeCheckAnalysisReuseKey(assemblyName, outputMode, useBuiltReferences, backendOption)
        path := IncrementalBuildStamp.CheckPathFor(_projectRoot, assemblyName)
        _checkStampPath = path
        _checkStampKey = key
        _checkStampAnalysisReuseKey = analysisReuseKey
        _checkInputCapture = null
        _wasUpToDate = false

        cachedStamp := IncrementalBuildStamp.TryReadCheckStampForReuse(path, key)
        if cachedStamp == null {
            cachedStamp = IncrementalBuildStamp.TryReadCheckStampForAnalysisReuse(path, analysisReuseKey)
        }
        if cachedStamp != null && cachedStamp.IsCurrent() {
            _checkStampEntries = cachedStamp.Entries
            _wasUpToDate = true
            return new IncrementalCheckResult(
                cachedStamp.CheckOutput,
                cachedStamp.CheckDiagnosticsJson,
                cachedStamp.CheckOutputToStandardError,
                cachedStamp.CheckExitCode
            )
        }

        _checkStampEntries = null
        capture := new IncrementalBuildInputCapture()
        capture.CaptureBeforeCompile(_projectRoot, EffectiveConfig(), _sourceFiles)
        _checkInputCapture = capture

        hadIncrementalState := _incrementalState != null
        if cachedStamp != null {
            if _incrementalState == null {
                _incrementalState = new IncrementalCompilationState()
            }
            SeedPersistedCheckSummaries(cachedStamp, _incrementalState)
        }

        if cachedStamp != null && !hadIncrementalState {
            try {
                if TrySeedPersistedCheckAnalysis(cachedStamp, capture, outputMode) {
                    return null
                }
            } catch {
                // Persisted state is only an optimization. A stale or unreadable candidate must
                // fall through to the normal full check rather than fail the user's check.
                _incrementalState = null
                _plannedTexts.Clear()
                _checkStateSeededFromStamp = false
                _persistedCheckPartial = false
            }
        }

        if _incrementalState == null {
            _incrementalState = new IncrementalCompilationState()
        }
        return null
    }

    // Persists a complete versioned result after diagnostics and backend validation are final. The
    // diagnostics JSON is always retained even when the selected user-facing mode is text.
    // A CHECKED PROJECT'S REFERENCE METADATA IS RELEASED ONCE ITS RESULT IS SAVED. A workspace check
    // holds every project's compiler until the whole workspace is rendered, and each compiler's
    // analyzer holds a metadata load context with one open file per reference image it read. Across
    // a repository's ~250 projects that is ~10,000 descriptors held at once, which is the per-process
    // limit .NET runs under on macOS -- and every assembly a project's imports load on demand
    // (`FrameworkNamespaceIndex`) moves it closer. After `SaveCheckResult` has captured the
    // compilation's metadata inputs they are kept as entries, so a later save (the workspace's text
    // rendering) needs no analyzer. A caller-owned incremental state keeps the analyzer only when
    // the invocation completed successfully; every other path releases the state's owner slot before
    // closing the metadata context.
    func ReleaseReferenceMetadata(preserveRetainedAnalyzer: bool = false): void {
        capture := _checkInputCapture
        if capture != null {
            _checkStampEntries = new List<IncrementalInputEntry>(capture.Entries)
            _checkInputCapture = null
        }

        analyzer := _sharedAnalyzerValue
        if analyzer == null {
            return
        }

        state := _incrementalState
        if preserveRetainedAnalyzer && _incrementalStateFromCaller && state != null && Object.ReferenceEquals(state.RetainedAnalyzer, analyzer) {
            _sharedAnalyzerValue = null
            return
        }

        _sharedAnalyzerValue = null
        if state != null && Object.ReferenceEquals(state.RetainedAnalyzer, analyzer) {
            state.ReleaseRetainedAnalyzer()
        } else {
            analyzer.Dispose()
        }
    }

    func SaveCheckResult(output: string, diagnosticsJson: string, outputToStandardError: bool, exitCode: int): bool {
        saved := false
        try {
            result := SaveCheckResultCore(output, diagnosticsJson, outputToStandardError, exitCode, CheckJsonHasDiagnostics(diagnosticsJson))
            saved = true
            return result
        } finally {
            ReleaseReferenceMetadata(saved && exitCode == 0)
        }
    }

    private func SaveCheckResultCore(output: string, diagnosticsJson: string, outputToStandardError: bool, exitCode: int, hasDiagnostics: bool): bool {
        path := _checkStampPath
        capture := _checkInputCapture
        storedEntries := _checkStampEntries
        if path == null || (capture == null && storedEntries == null) || _checkStampKey.Length == 0 {
            return false
        }

        entries := new List<IncrementalInputEntry>()
        if capture != null {
            analyzer := _sharedAnalyzerValue
            if analyzer != null {
                capture.CaptureFileImports(_projectRoot, _compilationUnits)
                capture.CaptureMetadataInputs(analyzer.MetadataInputAssemblyPaths(), analyzer.MetadataSearchDirectories())
                entries = capture.Entries
                _checkStampEntries = entries
            } else if storedEntries != null {
                // Text-mode workspace checks first persist each member's result, then replace the
                // owning member's cache output with the aggregate. Its analyzer has already been
                // released, so preserve the complete inputs captured on the first save.
                entries = storedEntries
            } else {
                capture.CaptureFileImports(_projectRoot, _compilationUnits)
                entries = capture.Entries
                _checkStampEntries = entries
            }
        } else {
            entries = storedEntries ?? new List<IncrementalInputEntry>()
        }

        stamp := new IncrementalBuildStamp(_checkStampKey)
        stamp.CheckAnalysisReuseKey = _checkStampAnalysisReuseKey
        stamp.ResultKind = IncrementalBuildStamp.CheckResultKind
        stamp.CheckSchemaVersion = IncrementalBuildStamp.CheckResultSchemaVersion
        stamp.CheckExitCode = exitCode
        stamp.CheckOutputToStandardError = outputToStandardError
        stamp.CheckOutput = output
        stamp.CheckDiagnosticsJson = diagnosticsJson
        stamp.CheckHadDiagnostics = hasDiagnostics
        stamp.Entries.AddRange(entries)
        for pending in _pendingRecords {
            fileState := pending.Value
            saved := new IncrementalCheckFileResult(fileState.Path, fileState.Summary)
            saved.Analyzed = fileState.Analyzed
            saved.ParseErrors.AddRange(fileState.ParseErrors)
            saved.AnalysisErrors.AddRange(fileState.AnalysisErrors)
            for dependency in fileState.Dependencies {
                saved.Dependencies.Add(dependency)
            }
            for imported in fileState.ImportedFileHashes {
                saved.ImportedFileHashes[imported.Key] = imported.Value
            }
            stamp.CheckFiles.Add(saved)
        }
        return stamp.TryWrite(path ?? "")
    }

    private static func CheckJsonHasDiagnostics(diagnosticsJson: string): bool {
        try {
            using document := JsonDocument.Parse(diagnosticsJson)
            results: JsonElement = default
            if !document.RootElement.TryGetProperty("results", out results) {
                document.RootElement.TryGetProperty("diagnostics", out results)
            }
            if results.ValueKind == JsonValueKind.Array {
                return results.GetArrayLength() > 0
            }
        } catch {
            // A check whose diagnostics cannot be interpreted cannot safely seed partial analysis.
            return true
        }

        return true
    }

    // A summary is a pure function of a source path and its exact text. Even when the complete
    // check stamp is stale, summaries for unchanged sources can seed the ordinary full-check plan;
    // this avoids parsing every source once for the plan and again for semantic analysis.
    private func SeedPersistedCheckSummaries(stamp: IncrementalBuildStamp, state: IncrementalCompilationState): void {
        sourcePaths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for sourceFile in _sourceFiles {
            sourcePaths.Add(Path.GetFullPath(sourceFile))
        }

        for saved in stamp.CheckFiles {
            if saved.Summary == null {
                continue
            }
            try {
                fullPath := Path.GetFullPath(saved.Path)
                if !sourcePaths.Contains(fullPath) {
                    continue
                }
                text := File.ReadAllText(fullPath)
                _plannedTexts[fullPath] = text
                textHash := ContentHash.OfText(text)
                if string.Equals(textHash, saved.Summary.TextHash, StringComparison.Ordinal) {
                    state.SummaryCache[fullPath + "|" + textHash] = saved.Summary
                }
            } catch {
                // An unusable candidate summary only costs the normal full plan to recompute it.
                continue
            }
        }
    }

    // Seeds the existing incremental compilation owner from the last cold check. The final check
    // result is still replayed only when every input matches; this path is considered only when the
    // source set is identical, the old result is clean, and every changed file has the same parsed
    // interface. The analyzer then reparses the project declarations but analyses only changed
    // bodies, using the same plan and file records as the warm daemon path.
    private func TrySeedPersistedCheckAnalysis(stamp: IncrementalBuildStamp, capture: IncrementalBuildInputCapture, outputMode: int): bool {
        if (outputMode != 1 && outputMode != 2) || stamp.CheckHadDiagnostics || stamp.CheckFiles.Count != _sourceFiles.Count {
            return false
        }
        if !string.Equals(EffectiveConfig().Language.Profile, "default", StringComparison.OrdinalIgnoreCase) {
            return false
        }

        sourcePaths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for sourceFile in _sourceFiles {
            sourcePaths.Add(Path.GetFullPath(sourceFile))
        }

        savedByPath := new Dictionary<string, IncrementalCheckFileResult>(StringComparer.OrdinalIgnoreCase)
        currentSummaries := new Dictionary<string, IncrementalFileSummary>(StringComparer.OrdinalIgnoreCase)
        oldInputByIdentity := new Dictionary<string, IncrementalInputEntry>(StringComparer.Ordinal)
        currentInputByIdentity := new Dictionary<string, IncrementalInputEntry>(StringComparer.Ordinal)
        changedFiles := 0
        canSeedPartial := true

        for entry in stamp.Entries {
            identity := CheckInputIdentity(entry)
            if !oldInputByIdentity.ContainsKey(identity) {
                oldInputByIdentity[identity] = entry
            }
            if entry.Kind == IncrementalInputEntry.FileContent && sourcePaths.Contains(Path.GetFullPath(entry.Path)) {
                continue
            }
            if !entry.IsCurrent() {
                return false
            }
        }

        for entry in capture.Entries {
            identity := CheckInputIdentity(entry)
            currentInputByIdentity[identity] = entry
            oldEntry: IncrementalInputEntry = null
            if !oldInputByIdentity.TryGetValue(identity, out oldEntry) {
                return false
            }
            if entry.Kind == IncrementalInputEntry.FileContent && sourcePaths.Contains(Path.GetFullPath(entry.Path)) {
                continue
            }
            if !string.Equals(entry.Value, oldEntry.Value, StringComparison.Ordinal) {
                return false
            }
        }

        for saved in stamp.CheckFiles {
            fullPath := Path.GetFullPath(saved.Path)
            if !sourcePaths.Contains(fullPath) || saved.Summary == null || saved.Summary.Opaque || saved.Summary.HasAttributes || !saved.Analyzed {
                return false
            }
            if saved.ParseErrors.Count > 0 || saved.AnalysisErrors.Count > 0 || savedByPath.ContainsKey(fullPath) {
                return false
            }

            text := ReadSourceText(fullPath)
            textHash := ContentHash.OfText(text)
            summary := saved.Summary
            if !string.Equals(textHash, summary.TextHash, StringComparison.Ordinal) {
                summary = IncrementalFileSummary.Compute(fullPath, text)
                stateForSummaries := _incrementalState
                if stateForSummaries != null {
                    stateForSummaries.SummaryCache[fullPath + "|" + summary.TextHash] = summary
                    stateForSummaries.LastSummaryFilesParsed = stateForSummaries.LastSummaryFilesParsed + 1
                }
                if summary.Opaque || summary.HasAttributes || !string.Equals(summary.SurfaceHash, saved.Summary.SurfaceHash, StringComparison.Ordinal) {
                    canSeedPartial = false
                }
                changedFiles = changedFiles + 1
            } else if summary.InterfaceSkeleton == null {
                // Only unchanged files need a declaration skeleton. The edited file is parsed and
                // emitted from its full text in this run.
                canSeedPartial = false
            }
            _plannedTexts[fullPath] = text
            savedByPath[fullPath] = saved
            currentSummaries[fullPath] = summary
        }

        if savedByPath.Count != sourcePaths.Count || changedFiles == 0 {
            return false
        }
        topLevelFunctionNames := new HashSet<string>(StringComparer.Ordinal)
        for summary in currentSummaries.Values {
            if summary.HasSourceFunctionOverloads {
                return false
            }
            for functionName in summary.TopLevelFunctionNames {
                if !topLevelFunctionNames.Add(functionName) {
                    return false
                }
            }
        }
        if !canSeedPartial {
            return false
        }
        for sourcePath in sourcePaths {
            if !savedByPath.ContainsKey(sourcePath) {
                return false
            }
            sourceIdentity := IncrementalInputEntry.FileContent.ToString() + "|" + sourcePath
            if !oldInputByIdentity.ContainsKey(sourceIdentity) || !currentInputByIdentity.ContainsKey(sourceIdentity) {
                return false
            }
        }

        state := new IncrementalCompilationState()
        for savedEntry in savedByPath {
            fullPath := savedEntry.Key
            saved := savedEntry.Value
            fileState := new IncrementalFileRecord(fullPath, saved.Summary)
            fileState.Analyzed = saved.Analyzed
            fileState.ParseErrors.AddRange(saved.ParseErrors)
            fileState.AnalysisErrors.AddRange(saved.AnalysisErrors)
            for dependency in saved.Dependencies {
                fileState.Dependencies.Add(dependency)
            }
            for imported in saved.ImportedFileHashes {
                importedPath := Path.GetFullPath(imported.Key)
                if sourcePaths.Contains(importedPath) {
                    // Every source's interface was verified unchanged above. A body-only edit to a
                    // file imported by path must not invalidate the importing file's analysis.
                    fileState.ImportedFileHashes[imported.Key] = ContentHash.OfFileOrMissing(imported.Key)
                } else {
                    fileState.ImportedFileHashes[imported.Key] = imported.Value
                }
            }
            state.Files[fullPath] = fileState
            state.SummaryCache[fullPath + "|" + saved.Summary.TextHash] = saved.Summary
            currentSummary := currentSummaries[fullPath]
            state.SummaryCache[fullPath + "|" + currentSummary.TextHash] = currentSummary
        }

        _incrementalState = state
        _checkStateSeededFromStamp = true
        _persistedCheckPartial = true
        return true
    }

    private static func CheckInputIdentity(entry: IncrementalInputEntry): string {
        return entry.Kind.ToString(System.Globalization.CultureInfo.InvariantCulture) + "|" + entry.Path
    }

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
            _incrementalStateFromCaller = value != null
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
        _systemsDiagnosticsOnly = false
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
        _checkStampPath = null
        _checkStampKey = ""
        _checkStampAnalysisReuseKey = ""
        _checkInputCapture = null
        _checkStampEntries = null
        _incrementalStateFromCaller = false
        _checkStateSeededFromStamp = false
        _persistedCheckPartial = false
        _incrementalState = null
        _incrementalPlan = null
        _pendingRecords = new Dictionary<string, IncrementalFileRecord>(StringComparer.OrdinalIgnoreCase)
        _plannedTexts = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        _analysisCompleted = false
        _emittedImage = null
        _parsedFilesCount = 0
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
                // The retained analyzer kept its references; the language settings are THIS
                // compilation's, which may follow an edit to `project.yml`.
                retained.ApplyLanguageSettings(EffectiveConfig())
                _sharedAnalyzerValue = retained
                return retained
            }
        }

        loadMark := CompilerPhaseTimings.Begin(_phaseProject, "load-references")
        analyzer := CreateAnalyzer(null)
        CompilerPhaseTimings.End(loadMark)
        _sharedAnalyzerValue = analyzer
        return analyzer
    }

    // An analyzer for this compilation, built the one way: the shared analyzer and every parallel
    // analysis worker's come from here, so they cannot disagree about the assemblies, the project
    // references, the SoA gate or the one-program rule they analyse under. A worker passes the shared
    // analyzer's reference metadata and reads the files that analyzer already loaded instead of
    // opening the whole reference closure again (`SharedReferenceMetadata`).
    private func CreateAnalyzer(shared: SharedReferenceMetadata?): Analyzer {
        analyzer := new Analyzer()
        analyzer.SoaEnabled = _soaEnabled
        if shared != null {
            analyzer.LoadSystemAssemblies(shared)
        } else {
            analyzer.LoadSystemAssemblies()
        }
        analyzer.LoadFromProjectConfig(EffectiveConfig(), _projectRoot, CompilationIncludesTestSources())
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

    // Test framework references follow the files this compilation actually contains. Looking at the
    // project tree instead would make an ordinary build open test-only packages that its source list
    // excludes, and make the build's reference work depend on another machine's NuGet cache.
    private func CompilationIncludesTestSources(): bool {
        for sourceFile in _sourceFiles {
            if sourceFile.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase) {
                return true
            }
        }

        return false
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
        if _persistedCheckPartial && ParsePersistedCheckFilesInParallel() {
            return
        }

        for sourceFile in _sourceFiles {
            if TryReuseParsedFile(sourceFile) {
                continue
            }
            if TryReusePreparedSummaryParse(sourceFile) {
                continue
            }

            _parsedFilesCount = _parsedFilesCount + 1

            errorsBefore := _allErrors.Count
            AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   Parsing {Path.GetFileName(sourceFile)}")
            source := ReadSourceText(sourceFile)
            _sourceTexts[Path.GetFullPath(sourceFile)] = source
            AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]     Read file ({source.Length} bytes)")
            fullSourcePath := Path.GetFullPath(sourceFile)
            parseSource := source
            usedInterfaceSkeleton := false
            plan := _incrementalPlan
            if _persistedCheckPartial && plan != null && plan.ReusedFiles.Contains(fullSourcePath) {
                summary := plan.Summaries[fullSourcePath]
                skeleton := summary.InterfaceSkeleton
                if skeleton != null {
                    parseSource = skeleton
                    usedInterfaceSkeleton = true
                }
            }
            // Resolve conditional-compilation directives (#if/#elif/#else/#endif) so the
            // parser and all downstream stages only see the live branch. The SOURCE-level
            // overload (the one the columnar emit path already uses) blanks dead branches in
            // place, so every surviving line and column is unchanged.
            live := Preprocessor.ProcessSource(parseSource, _preprocessorSymbols, sourceFile, _allErrors)
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
                if usedInterfaceSkeleton || string.Equals(live, source, StringComparison.Ordinal) && string.Equals(fullSourcePath, sourceFile, StringComparison.Ordinal) {
                    _reusableParses[fullSourcePath] = parseResult
                    reusableParse = parseResult
                }
            }
            RecordParsedFile(sourceFile, parseResult.CompilationUnit, errorsBefore, reusableParse)
            AppendDebugLog($"[{DateTime.Now:HH:mm:ss.fff}]   Done parsing {Path.GetFileName(sourceFile)}")
        }
    }

    // A cold check has no in-memory ASTs to reuse, even though its persisted records prove that
    // every unchanged file is semantically reusable. Parse the saved declaration skeletons in
    // parallel, then merge them in project order so diagnostic ordering stays the serial ordering.
    // If a skeleton does not parse cleanly, discard every partial parse and let the ordinary full
    // parse path run with reuse disabled.
    private func ParsePersistedCheckFilesInParallel(): bool {
        plan := _incrementalPlan
        if plan == null || _sourceFiles.Count <= 1 {
            return false
        }

        files := new List<string>(_sourceFiles.Count)
        sources := new List<string>(_sourceFiles.Count)
        preparsedResults := new List<FileParseAst?>()
        totalCharacters := 0L
        sourceIndex := 0
        for sourceFile in _sourceFiles {
            preparsedResults.Add(null)
            fullPath := Path.GetFullPath(sourceFile)
            source := ReadSourceText(sourceFile)
            _sourceTexts[fullPath] = source
            parseSource := source
            if plan.ReusedFiles.Contains(fullPath) {
                summary := plan.Summaries[fullPath]
                skeleton := summary.InterfaceSkeleton
                if skeleton == null {
                    return false
                }
                parseSource = skeleton
            } else {
                summary := plan.Summaries[fullPath]
                if !summary.HasPreprocessorDirectives {
                    preparsedResults[sourceIndex] = summary.ParsedSource
                }
            }
            files.Add(sourceFile)
            sources.Add(parseSource)
            totalCharacters = totalCharacters + parseSource.Length
            sourceIndex = sourceIndex + 1
        }

        outcomes := new MultiFileCompilerFileParse[_sourceFiles.Count]
        queue := new ConcurrentQueue<int>()
        index := 0
        while index < files.Count {
            outcome := new MultiFileCompilerFileParse()
            outcomes[index] = outcome
            prepared := preparsedResults[index]
            if prepared != null {
                outcome.Result = prepared
                outcome.WasPreparsed = true
            } else {
                queue.Enqueue(index)
            }
            index = index + 1
        }

        workerCount := CompilerParallelism.WorkerCount(files.Count, totalCharacters)
        if _workers > 0 {
            workerCount = Math.Min(_workers, files.Count)
        }
        workers := new List<Thread>(workerCount)
        states := new List<MultiFileCompilerParseWorker>(workerCount)
        worker := 0
        while worker < workerCount {
            state := new MultiFileCompiler.MultiFileCompilerParseWorker(files, sources, _preprocessorSymbols, outcomes, queue)
            states.Add(state)
            work: ThreadStart = () => RunPersistedCheckParseWorker(state)
            thread := new Thread(work, 64 * 1024 * 1024)
            thread.IsBackground = true
            thread.Name = "nsharp-check-parse-" + worker.ToString()
            workers.Add(thread)
            worker = worker + 1
        }
        for started in workers {
            started.Start()
        }
        for joined in workers {
            joined.Join()
        }

        invalid := false
        for outcome in outcomes {
            if outcome.Failure != null || outcome.Result == null || outcome.Result.Errors.Count > 0 || outcome.PreprocessorErrors.Count > 0 {
                invalid = true
                break
            }
        }
        if invalid {
            plan.DisableReuse()
            _persistedCheckPartial = false
            return false
        }

        index = 0
        while index < files.Count {
            sourceFile := files[index]
            fullPath := Path.GetFullPath(sourceFile)
            outcome := outcomes[index]
            errorsBefore := _allErrors.Count
            if !outcome.WasPreparsed {
                _parsedFilesCount = _parsedFilesCount + 1
            }
            _allErrors.AddRange(outcome.PreprocessorErrors)
            parseResult := outcome.Result
            if parseResult == null {
                throw new InvalidOperationException("Persisted check parse worker produced no result for '" + sourceFile + "'.")
            }
            _allErrors.AddRange(parseResult.Errors)
            unit := parseResult.CompilationUnit
            reusableParse: FileParseAst? = null
            if unit != null {
                _compilationUnits[sourceFile] = unit
                reusableParse = parseResult
                _reusableParses[fullPath] = parseResult
            }
            RecordParsedFile(sourceFile, unit, errorsBefore, reusableParse)
            index = index + 1
        }

        return true
    }

    private func RunPersistedCheckParseWorker(state: MultiFileCompilerParseWorker): void {
        index := 0
        while state.Queue.TryDequeue(out index) {
            outcome := state.Outcomes[index]
            try {
                live := Preprocessor.ProcessSource(state.Sources[index], state.Symbols, state.Files[index], outcome.PreprocessorErrors)
                outcome.Result = ColumnarParserRecovery.ParseFileAst(live, state.Files[index])
            } catch ex: Exception {
                outcome.Failure = ex
            }
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
        if fileRecord.Unit == null {
            return false
        }
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

    // A persisted-candidate summary was parsed in this process while deciding whether its surface
    // changed. Reuse that same parse if the check must fall back to a full analysis; the full path
    // still consumes every source, but does not parse a changed source twice.
    private func TryReusePreparedSummaryParse(sourceFile: string): bool {
        plan := _incrementalPlan
        if plan == null {
            return false
        }

        fullPath := Path.GetFullPath(sourceFile)
        summary: IncrementalFileSummary = null
        if !plan.Summaries.TryGetValue(fullPath, out summary) || summary.HasPreprocessorDirectives || summary.ParsedSource == null {
            return false
        }
        source := ReadSourceText(sourceFile)
        if !string.Equals(ContentHash.OfText(source), summary.TextHash, StringComparison.Ordinal) {
            return false
        }

        parseResult := summary.ParsedSource
        if parseResult == null {
            return false
        }
        _sourceTexts[fullPath] = source
        errorsBefore := _allErrors.Count
        _allErrors.AddRange(parseResult.Errors)
        unit := parseResult.CompilationUnit
        reusableParse: FileParseAst? = null
        if unit != null {
            _compilationUnits[sourceFile] = unit
            _reusableParses[fullPath] = parseResult
            reusableParse = parseResult
        }
        RecordParsedFile(sourceFile, unit, errorsBefore, reusableParse)
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
        state := _incrementalState
        previous: IncrementalFileRecord = null
        if plan.ReusedFiles.Contains(fullPath) && state != null && state.Files.TryGetValue(fullPath, out previous) && previous.Analyzed && string.Equals(previous.Summary.TextHash, fileRecord.Summary.TextHash, StringComparison.Ordinal) {
            fileRecord.Analyzed = true
            fileRecord.AnalysisErrors.AddRange(previous.AnalysisErrors)
            for dependency in previous.Dependencies {
                fileRecord.Dependencies.Add(dependency)
            }
            for imported in previous.ImportedFileHashes {
                fileRecord.ImportedFileHashes[imported.Key] = imported.Value
            }
        }
        _pendingRecords[fullPath] = fileRecord
    }

    private func HasSourceFunctionOverloads(): bool {
        counts := new Dictionary<string, int>(StringComparer.Ordinal)
        for compilation in _compilationUnits {
            for declaration in compilation.Value.Declarations {
                function := declaration as FunctionDeclaration
                if function == null {
                    continue
                }
                count: int = 0
                counts.TryGetValue(function.Name, out count)
                count = count + 1
                if count > 1 {
                    return true
                }
                counts[function.Name] = count
            }
        }
        return false
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
        fileAnalysisTimer := Stopwatch.StartNew()
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
        spelledIndex := 0
        while spelledIndex < files.Count {
            spelledText: string? = null
            if _sourceTexts.TryGetValue(Path.GetFullPath(files[spelledIndex]), out spelledText) && spelledText != null {
                sharedAnalyzer.PreloadSpelledFrameworkNamespaces(units[spelledIndex], spelledText)
            }
            spelledIndex = spelledIndex + 1
        }
        analyzerTimer := Stopwatch.StartNew()
        if workerCount <= 1 {
            sharedAnalyzer.SetProjectSourceTexts(_sourceTexts)
            sharedAnalyzer.SeedProjectParses(_reusableParses)
            index := 0
            while index < files.Count {
                if !reused[index] {
                    outcomes[index] = AnalyzeOneFile(sharedAnalyzer, files[index], units[index])
                } else {
                    // A REUSED FILE STILL CONTRIBUTES ITS IMPORTS' LOADS, exactly as a parallel worker
                    // replays every earlier file it did not analyse: the next analysed file then sees
                    // the assembly list a full serial run would give it, and the IL back end finds every
                    // `Microsoft.NETCore.App` assembly the program's imports name already in this
                    // compilation's shared context instead of reopening the reference set.
                    sharedAnalyzer.PreloadImportedAssemblies(units[index])
                }
                index = index + 1
            }
        } else {
            AnalyzeFilesInParallel(sharedAnalyzer, files, units, reused, outcomes, workerCount)
        }
        analyzerTimer.Stop()

        mergeTimer := Stopwatch.StartNew()
        analyzedFiles := 0
        reusedFiles := 0
        state := _incrementalState
        previousProjectBindings: BindingMap? = null
        useIncrementalProjectBindings := state != null && plan != null && state.LastProjectBindings != null
        if state != null && plan != null && state.LastProjectBindings != null {
            previousProjectBindings = state.LastProjectBindings
        }
        replacementBindings := new Dictionary<string, BindingMap>(StringComparer.OrdinalIgnoreCase)
        mergeIndex := 0
        while mergeIndex < files.Count {
            outcome := outcomes[mergeIndex]
            failure := outcome.Failure
            if failure != null {
                CompilerPhaseTimings.End(analysisMark)
                throw failure
            }
            if !reused[mergeIndex] && useIncrementalProjectBindings {
                bindings := outcome.Bindings
                if bindings == null {
                    bindings = new BindingMap()
                }
                replacementBindings[Path.GetFullPath(files[mergeIndex])] = bindings
            }

            MergeFileAnalysis(files[mergeIndex], outcome, !useIncrementalProjectBindings)
            if reused[mergeIndex] {
                reusedFiles = reusedFiles + 1
            } else {
                analyzedFiles = analyzedFiles + 1
                RecordAnalyzedFile(Path.GetFullPath(files[mergeIndex]), units[mergeIndex], outcome.SemanticModel, outcome.Bindings, outcome.Errors, outcome.TypeDeclarationFiles)
            }
            mergeIndex = mergeIndex + 1
        }

        if useIncrementalProjectBindings && state != null && plan != null && previousProjectBindings != null {
            removedFiles := new List<string>()
            for previousFile in state.Files.Keys {
                if !plan.Summaries.ContainsKey(previousFile) {
                    removedFiles.Add(previousFile)
                }
            }

            previous := previousProjectBindings
            if replacementBindings.Count == 0 && removedFiles.Count == 0 {
                _projectBindings = previous
            } else {
                _projectBindings = BindingMap.ReplaceFiles(previous, replacementBindings, removedFiles)
            }
        }

        CommitIncrementalState(analyzedFiles, reusedFiles)
        mergeTimer.Stop()
        timingState: IncrementalCompilationState? = _incrementalState
        if timingState != null {
            timingState.LastFileAnalysisMilliseconds = fileAnalysisTimer.ElapsedMilliseconds
            timingState.LastFileAnalyzerMilliseconds = analyzerTimer.ElapsedMilliseconds
            timingState.LastProjectMergeMilliseconds = mergeTimer.ElapsedMilliseconds
        }
        CompilerPhaseTimings.End(analysisMark)

        systemsMark := CompilerPhaseTimings.Begin(_phaseProject, "systems-policy")
        systemsPolicyTimer := Stopwatch.StartNew()
        AnalyzeSystemsPolicy()
        if timingState != null {
            timingState.LastSystemsPolicyMilliseconds = systemsPolicyTimer.ElapsedMilliseconds
        }
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

    private func MergeFileAnalysis(sourceFile: string, outcome: MultiFileCompilerFileAnalysis, mergeBindings: bool): void {
        // Save semantic model for project-wide analysis and emission.
        semanticModel := outcome.SemanticModel
        if semanticModel != null {
            _semanticModels[sourceFile] = semanticModel
        }

        // Merge binding map for cross-file semantic references
        bindings := outcome.Bindings
        if mergeBindings && bindings != null {
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
            state := new MultiFileCompiler.MultiFileCompilerAnalysisWorker(workerAnalyzer, files, units, outcomes, queue, projectNamespaces, sharedAnalyzer.ReferenceMetadata)
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
                created := CreateAnalyzer(state.ReferenceMetadata)
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
        _systemsReport = new SystemsAnalyzer(_projectRoot, _config).Analyze(_compilationUnits, _performanceFacts, _semanticModels, _systemsDiagnosticsOnly)
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
        phaseTimer := Stopwatch.StartNew()
        PrepareIncrementalPlan()
        phaseState: IncrementalCompilationState? = _incrementalState
        if phaseState != null {
            phaseState.LastPlanMilliseconds = phaseTimer.ElapsedMilliseconds
        }
        phaseTimer.Restart()
        parseMark := CompilerPhaseTimings.Begin(_phaseProject, "parse")
        ParseAllFiles()
        if _persistedCheckPartial && HasSourceFunctionOverloads() {
            // The emitter uses per-file semantic bindings to select an overloaded source function.
            // A cold record has diagnostics and interfaces, not semantic models, so this shape must
            // go through the complete analyzer before backend validation.
            plan := _incrementalPlan
            if plan != null {
                plan.DisableReuse()
            }
            _persistedCheckPartial = false
        }
        if phaseState != null {
            phaseState.LastParseMilliseconds = phaseTimer.ElapsedMilliseconds
        }
        CompilerPhaseTimings.End(parseMark)
        phaseTimer.Restart()
        importsMark := CompilerPhaseTimings.Begin(_phaseProject, "import-graph")
        DetectCircularFileImports()
        if phaseState != null {
            phaseState.LastImportGraphMilliseconds = phaseTimer.ElapsedMilliseconds
        }
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
            if (!ReportNoBuildableSources() && !EmitOnWideStackThread(assemblyName, outputPath, out decline)) {
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

        if ReportNoBuildableSources() {
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

            emissionKey := ComputeEmissionKey(assemblyName)
            if TryReuseEmission(emissionKey, outputPath) {
                return FinishEmission(outputPath, stampPath, stampKey, capture)
            }
            errorsBeforeEmission := _allErrors.Count

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
            RecordEmission(emissionKey, errorsBeforeEmission)
        }

        return FinishEmission(outputPath, stampPath, stampKey, capture)
    }

    // The result of an emission that has run (or was answered from the state): success is the absence
    // of an error, and a successful written output records its up-to-date stamp when one was asked for.
    private func FinishEmission(outputPath: string?, stampPath: string?, stampKey: string, capture: IncrementalBuildInputCapture?): MultiFileCompilationResult {
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

    // EVERYTHING AN EMISSION READS, AS ONE KEY. The state's environment key already covers the
    // compiler, the configuration (output type, version, friend grants), the defines, the references
    // and their bytes, and the options analysis reads; the rest is this compilation's own: the
    // assembly name, the switches the back end reads, and every source in compilation order by path
    // and content. The analysis the emitter reads is a function of the same inputs, so two
    // compilations with one key emit the same image and the same refusal. The empty key means "do not
    // reuse": no warm state, a decline trace or debug log was asked for (the caller wants the walk to
    // run), or a reference assembly is to be written beside the output.
    private func ComputeEmissionKey(assemblyName: string): string {
        state := _incrementalState
        plan := _incrementalPlan
        if state == null || plan == null || _columnarDeclineLog != null || _debugLoggingEnabled || _emitReferenceAssembly {
            return ""
        }

        key := new IncrementalKeyBuilder()
        key.Add("environment", state.EnvironmentKey)
        key.Add("assembly", assemblyName)
        key.AddBool("aot", _aotMode)
        key.AddBool("soa", _soaEnabled)
        key.Add("source-count", _sourceFiles.Count.ToString())
        for sourceFile in _sourceFiles {
            fullPath := Path.GetFullPath(sourceFile)
            summary: IncrementalFileSummary = null
            if !plan.Summaries.TryGetValue(fullPath, out summary) {
                return ""
            }
            key.Add("source", fullPath)
            key.Add("text", summary.TextHash)
        }
        return key.Build()
    }

    // Answers this emission from the state when the last one ran under the same key: its diagnostics,
    // and its image -- kept in memory for a validation, written for a build.
    private func TryReuseEmission(emissionKey: string, outputPath: string?): bool {
        state := _incrementalState
        if state == null {
            return false
        }

        state.LastEmissionReused = false
        if emissionKey.Length == 0 || emissionKey != state.LastEmissionKey {
            return false
        }

        _allErrors.AddRange(state.LastEmissionErrors)
        image := state.LastEmissionImage
        if image != null {
            _emittedImage = image
            if outputPath != null {
                AtomicFile.WriteAllBytes(outputPath, image)
                CompilerWorkCounters.Shared.CountAssemblyEmitted()
            }
        }
        state.LastEmissionReused = true
        return true
    }

    // Keeps this emission's outcome for the next compilation of the state: the image when it emitted,
    // the diagnostics the emission added either way.
    private func RecordEmission(emissionKey: string, errorsBeforeEmission: int): void {
        state := _incrementalState
        if state == null {
            return
        }

        if emissionKey.Length == 0 {
            state.ForgetEmission()
            return
        }

        added := new List<CompilerError>()
        index := errorsBeforeEmission
        while index < _allErrors.Count {
            added.Add(_allErrors[index])
            index = index + 1
        }
        hasError := false
        for addedError in added {
            if addedError.Severity == ErrorSeverity.Error {
                hasError = true
            }
        }
        state.LastEmissionKey = emissionKey
        state.LastEmissionErrors = added
        state.LastEmissionImage = null
        if !hasError {
            state.LastEmissionImage = _emittedImage
        }
    }

    // Decides, before anything is parsed, which files' analyses the state lets this compilation
    // reuse. A different environment (or metadata that moved on disk) resets the state first.
    private func PrepareIncrementalPlan(): void {
        state := _incrementalState
        if state == null {
            return
        }
        _parsedFilesCount = 0
        state.LastSummaryFilesParsed = 0
        state.LastEmissionReused = false
        state.EmitParses.LastReused = 0
        state.EmitParses.LastParsed = 0

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
        if _checkStateSeededFromStamp {
            // The persisted check stamp's full input closure was checked before it seeded this
            // state. Its source records intentionally have no process-local analyzer objects.
            state.EnvironmentKey = environmentKey
            _checkStateSeededFromStamp = false
        } else if environmentKey != state.EnvironmentKey || !state.MetadataIsCurrent() {
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
        symbols := new List<string>(_preprocessorSymbols)
        symbols.Sort(StringComparer.Ordinal)
        key.Add("defines", string.Join(",", symbols))
        key.Add("nuget-packages", Environment.GetEnvironmentVariable("NUGET_PACKAGES"))
        key.Add("user-profile", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile))
        key.Add("current-directory", Environment.CurrentDirectory)
        capture := new IncrementalBuildInputCapture()
        capture.CaptureEnvironment(_projectRoot, EffectiveConfig())
        // Environment capture resolves and normalizes part of the project config (notably the
        // dependency closure). Fingerprint the value compilation will retain after that first
        // capture so the next body edit sees the same environment key.
        key.Add("config", IncrementalConfigFingerprint.Describe(_config))
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
        state.LastFilesParsed = _parsedFilesCount + state.LastSummaryFilesParsed
        state.LastWasFull = reusedFiles == 0
        state.LastProjectBindings = _projectBindings
        analyzer := _sharedAnalyzerValue
        if analyzer != null && analyzerWasNew {
            capture := new IncrementalBuildInputCapture()
            capture.CaptureMetadataInputs(analyzer.MetadataInputAssemblyPaths(), analyzer.MetadataSearchDirectories())
            state.MetadataEntries.AddRange(capture.Entries)
        }
        if analyzer != null {
            // The invocation owns a new analyzer until every file analysis has completed. The state
            // retains it from this point; command-level cleanup still releases it if emission
            // validation or result rendering subsequently fails.
            state.RetainedAnalyzer = analyzer
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

    private func CanUseIncrementalCheckStamp(): bool {
        // The workspace server owns the project's incremental session and uses it to answer later
        // edits. Persisted check results serve cold processes; the daemon keeps its in-memory path.
        if CliInvocationContext.IsRemoteInvocation() {
            return false
        }
        if _sourceTextOverrides.Count > 0 {
            return false
        }
        if _columnarDeclineLog != null || _debugLoggingEnabled {
            return false
        }
        return IncrementalBuildPolicy.IsEnabled()
    }

    // The same non-file inputs and source identity as the build stamp, plus every check option and
    // compiler environment override that can change the saved result. Project configuration is
    // fingerprinted structurally, while the exact project/reference/framework closure is verified
    // from `IncrementalBuildInputCapture` entries stored in that same stamp. Worker count is part
    // of the key even though analysis promises deterministic ordering: a changed execution policy
    // must not be allowed to replay a result produced under a different policy.
    private func ComputeCheckResultKey(assemblyName: string, outputMode: int, useBuiltReferences: bool, backendOption: string?): string {
        return ComputeCheckKey(assemblyName, outputMode, useBuiltReferences, backendOption, true)
    }

    private func ComputeCheckAnalysisReuseKey(assemblyName: string, outputMode: int, useBuiltReferences: bool, backendOption: string?): string {
        return ComputeCheckKey(assemblyName, outputMode, useBuiltReferences, backendOption, false)
    }

    private func ComputeCheckKey(assemblyName: string, outputMode: int, useBuiltReferences: bool, backendOption: string?, includeSourceSet: bool): string {
        key := new IncrementalKeyBuilder()
        key.Add("format", IncrementalBuildStamp.FormatVersion.ToString())
        key.Add("compiler", IncrementalCompilerIdentity.Current())
        key.Add("project-root", Path.GetFullPath(_projectRoot))
        key.Add("assembly", assemblyName)
        key.Add("purpose", "check")
        key.Add("output-schema", IncrementalBuildStamp.CheckResultSchemaVersion.ToString())
        key.Add("summary-format", IncrementalFileSummary.FormatVersion.ToString())
        key.Add("output-mode", outputMode.ToString())
        key.Add("backend-option", backendOption)
        key.AddBool("use-built-references", useBuiltReferences)
        key.Add("lint-policy", "check-full-v1")
        key.AddBool("aot", _aotMode)
        key.AddBool("reference-assembly", _emitReferenceAssembly)
        key.AddBool("soa", _soaEnabled)
        key.AddBool("one-program", _declaredOneProgram)
        key.Add("config", IncrementalConfigFingerprint.Describe(_config))
        symbols := new List<string>(_preprocessorSymbols)
        symbols.Sort(StringComparer.Ordinal)
        key.Add("defines", string.Join(",", symbols))
        if includeSourceSet {
            key.Add("source-count", _sourceFiles.Count.ToString())
            for sourceFile in _sourceFiles {
                key.Add("source", Path.GetFullPath(sourceFile))
            }
        }
        key.Add("nuget-packages", Environment.GetEnvironmentVariable("NUGET_PACKAGES"))
        key.Add("soa-environment", Environment.GetEnvironmentVariable(SoaFeature.EnvironmentVariable))
        key.Add("compiler-workers", Environment.GetEnvironmentVariable(CompilerParallelism.WorkerOverrideVariable))
        key.Add("user-profile", Environment.GetFolderPath(Environment.SpecialFolder.UserProfile))
        key.Add("current-directory", Environment.CurrentDirectory)
        return key.Build()
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
        ColumnarDeclineTrace.Reset()
        if (_sourceFiles.Count == 0) {
            // A project whose only sources are `*.tests.nl` reaches here: `nlc build` compiles the
            // product, test sources belong to `nlc test`/`nlc check`, and Go's `go build` refuses the
            // same shape with "no non-test Go files". Say so instead of declining without a reason.
            DeclineWithReason("emit.no-sources", "the project has no source files to compile; files named *.tests.nl are test sources that `nlc build` does not compile (run `nlc test` or `nlc check` for them)")
            return false
        }

        if _persistedCheckPartial && outputPath == null && TryEmitPersistedCheckSubset(assemblyName) {
            return true
        }

        emitParseMark := CompilerPhaseTimings.Begin(_phaseProject, "emit.parse")
        sources := new List<string>(_sourceFiles.Count)
        for sourceFile in _sourceFiles {
            let source: string? = null
            if (!_sourceTexts.TryGetValue(Path.GetFullPath(sourceFile), out source)) {
                DeclineWithReason("emit.source-unread", "the source text of '" + Path.GetFileName(sourceFile) + "' was not read before emission")
                return false
            }
            sourceText := source ?? ""
            plan := _incrementalPlan
            fullPath := Path.GetFullPath(sourceFile)
            if _persistedCheckPartial && plan != null && plan.ReusedFiles.Contains(fullPath) {
                summary := plan.Summaries[fullPath]
                skeleton := summary.InterfaceSkeleton
                if skeleton == null {
                    DeclineWithReason("emit.skeleton-missing", "the cached interface skeleton of '" + Path.GetFileName(sourceFile) + "' is missing")
                    return false
                }
                sourceText = skeleton
            }
            sources.Add(Preprocessor.ProcessSource(sourceText, _preprocessorSymbols, sourceFile, _allErrors))
        }

        outputConfig := _config
        outputType: string? = null
        if outputConfig != null {
            outputType = outputConfig.OutputType
        }
        isExecutable := ColumnarEmissionPlanner.IsExecutableOutput(outputType)
        // The persisted-check subset attempt above may have recorded declines of its own; the
        // complete walk below starts from a clean trace so they cannot be reported as its reason.
        ColumnarDeclineTrace.Reset()
        let program: NSharpLang.Compiler.Columnar.ColumnarProgramInput = null
        emitParses: ColumnarFileProgramCache? = null
        warmState := _incrementalState
        if warmState != null {
            emitParses = warmState.EmitParses
        }
        if (!ColumnarProgramInputBuilder.TryBuildMultiFile(sources, _sourceFiles, _projectRoot, out program, _workers, emitParses)) {
            CompilerPhaseTimings.End(emitParseMark)
            return false
        }
        CompilerPhaseTimings.End(emitParseMark)
        // ONE LOADED REFERENCE SET PER COMPILATION: the back end's external type scan reads the
        // shared analyzer's context (`SharedReferenceMetadata`) rather than reading the same files again.
        sharedAnalyzer := _sharedAnalyzerValue
        if sharedAnalyzer != null {
            program.ReferenceMetadata = sharedAnalyzer.ReferenceMetadata
        }
        // The emitter wraps unannotated async bodies in the same family the analyzer typed them with.
        program.AsyncDefaultFamily = AsyncTaskFamilyFacts.ForLanguage(EffectiveConfig().Language)
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
        AtomicFile.WriteAllBytes(outputPath, assembly)
        CompilerWorkCounters.Shared.CountAssemblyEmitted()
        written := TryEmitReferenceAssembly(outputPath, referenceAssemblyPaths)
        CompilerPhaseTimings.End(writeMark)
        return written
    }

    // The earlier clean check already validated unchanged bodies through the backend. Re-run code
    // generation for the changed source and the project declarations its fresh bindings need. A
    // decline retries the complete project below.
    private func TryEmitPersistedCheckSubset(assemblyName: string): bool {
        plan := _incrementalPlan
        if plan == null {
            return false
        }

        changedPath := FindSingleChangedSource(plan)
        if changedPath == null || _sourceFiles.Count <= 1 {
            return false
        }
        normalizedPath := changedPath ?? ""
        changedIndex := FindProjectSourceIndex(normalizedPath)
        if changedIndex < 0 {
            return false
        }
        selected := SelectPersistedCheckEmissionFiles(normalizedPath, plan)
        if selected == null {
            return false
        }

        let program: NSharpLang.Compiler.Columnar.ColumnarProgramInput = null
        if !TryBuildPersistedSubsetProgram(normalizedPath, changedIndex, selected, plan, out program) {
            return false
        }

        PreparePersistedSubsetProgram(program, normalizedPath, changedIndex)
        return TryEmitPersistedSubsetProgram(program, assemblyName)
    }

    private func FindSingleChangedSource(plan: IncrementalCompilationPlan): string? {
        changedPath: string? = null
        for sourceFile in _sourceFiles {
            fullPath := Path.GetFullPath(sourceFile)
            if !plan.ReusedFiles.Contains(fullPath) {
                if changedPath != null {
                    return null
                }
                changedPath = fullPath
            }
        }
        return changedPath
    }

    private func FindProjectSourceIndex(sourcePath: string): int {
        index := 0
        while index < _sourceFiles.Count {
            if string.Equals(Path.GetFullPath(_sourceFiles[index]), sourcePath, StringComparison.OrdinalIgnoreCase) {
                return index
            }
            index = index + 1
        }
        return -1
    }

    private func SelectPersistedCheckEmissionFiles(changedPath: string, plan: IncrementalCompilationPlan): HashSet<string>? {
        changedRecord: IncrementalFileRecord = null
        if !_pendingRecords.TryGetValue(changedPath, out changedRecord) || changedRecord.Bindings == null {
            return null
        }

        selected := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        processed := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        selected.Add(changedPath)
        AddBoundPersistedSourceFiles(changedPath, changedRecord, selected)
        AddImportedPersistedSourceFiles(changedPath, changedRecord, selected)
        AddNamedPersistedSourceFiles(changedPath, plan.Summaries[changedPath].ReferencedNames, plan, selected)
        outputConfig := _config
        outputType: string? = null
        if outputConfig != null {
            outputType = outputConfig.OutputType
        }
        if ColumnarEmissionPlanner.IsExecutableOutput(outputType) {
            for sourceFile in _sourceFiles {
                sourcePath := Path.GetFullPath(sourceFile)
                if plan.Summaries[sourcePath].TopLevelFunctionNames.Contains("main") {
                    selected.Add(sourcePath)
                }
            }
        }

        while processed.Count < selected.Count {
            nextPath: string? = null
            for candidatePath in selected {
                if !processed.Contains(candidatePath) {
                    nextPath = candidatePath
                    break
                }
            }
            if nextPath == null {
                break
            }

            currentPath := nextPath ?? ""
            processed.Add(currentPath)
            if string.Equals(currentPath, changedPath, StringComparison.OrdinalIgnoreCase) {
                continue
            }
            AddNamedPersistedSourceFiles(currentPath, plan.Summaries[currentPath].Mentions, plan, selected)
            currentRecord: IncrementalFileRecord = null
            if _pendingRecords.TryGetValue(currentPath, out currentRecord) {
                AddImportedPersistedSourceFiles(currentPath, currentRecord, selected)
            }
        }

        return selected
    }

    private func AddBoundPersistedSourceFiles(changedPath: string, fileRecord: IncrementalFileRecord, selected: HashSet<string>): void {
        bindings := fileRecord.Bindings
        if bindings == null {
            return
        }
        for binding in bindings.BindingEntries {
            declarationPath := binding.Value.File
            if declarationPath != null {
                AddPersistedSourcePath(changedPath, declarationPath, selected)
            }
        }
    }

    private func AddImportedPersistedSourceFiles(currentPath: string, fileRecord: IncrementalFileRecord, selected: HashSet<string>): void {
        for imported in fileRecord.ImportedFileHashes {
            AddPersistedSourcePath(currentPath, imported.Key, selected)
        }
    }

    private func AddPersistedSourcePath(currentPath: string, candidatePath: string, selected: HashSet<string>): void {
        normalizedCandidate := Path.GetFullPath(candidatePath)
        if string.Equals(normalizedCandidate, currentPath, StringComparison.OrdinalIgnoreCase) {
            return
        }
        for sourceFile in _sourceFiles {
            sourcePath := Path.GetFullPath(sourceFile)
            if string.Equals(sourcePath, normalizedCandidate, StringComparison.OrdinalIgnoreCase) {
                selected.Add(sourcePath)
                return
            }
        }
    }

    private func AddNamedPersistedSourceFiles(currentPath: string, names: HashSet<string>, plan: IncrementalCompilationPlan, selected: HashSet<string>): void {
        for sourceFile in _sourceFiles {
            sourcePath := Path.GetFullPath(sourceFile)
            if string.Equals(sourcePath, currentPath, StringComparison.OrdinalIgnoreCase) || selected.Contains(sourcePath) {
                continue
            }
            candidateSummary := plan.Summaries[sourcePath]
            for name in names {
                if candidateSummary.DeclaredNames.Contains(name) {
                    selected.Add(sourcePath)
                    break
                }
            }
        }
    }

    private func TryBuildPersistedSubsetProgram(changedPath: string, changedIndex: int, selected: HashSet<string>, plan: IncrementalCompilationPlan, out program: NSharpLang.Compiler.Columnar.ColumnarProgramInput): bool {
        program = null

        emitParseMark := CompilerPhaseTimings.Begin(_phaseProject, "emit.parse")
        let source: string? = null
        if !_sourceTexts.TryGetValue(changedPath, out source) {
            CompilerPhaseTimings.End(emitParseMark)
            return false
        }
        changedFile := _sourceFiles[changedIndex]
        preprocessorErrors := new List<CompilerError>()
        sourceText := Preprocessor.ProcessSource(source ?? "", _preprocessorSymbols, changedFile, preprocessorErrors)
        if preprocessorErrors.Count > 0 {
            CompilerPhaseTimings.End(emitParseMark)
            return false
        }
        changedEmissionText := sourceText
        changedSummary := plan.Summaries[changedPath]
        changedParse := changedSummary.ParsedSource
        changedUnit: CompilationUnit? = null
        if changedParse != null {
            changedUnit = changedParse.CompilationUnit
        }
        previousRecord: IncrementalFileRecord = null
        state := _incrementalState
        if !changedSummary.HasPreprocessorDirectives && changedUnit != null && state != null && state.Files.TryGetValue(changedPath, out previousRecord) {
            previousSummary := previousRecord.Summary
            if previousSummary != null && previousSummary.BodyHashes.Count == changedSummary.BodyHashes.Count {
                changedTokens := new Lexer(sourceText, changedFile).Tokenize()
                selectiveText := IncrementalFileSummary.BuildChangedBodyEmissionSource(
                    sourceText,
                    changedUnit ?? new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1),
                    changedTokens,
                    changedSummary.BodyHashes,
                    previousSummary.BodyHashes
                )
                if selectiveText != null {
                    changedEmissionText = selectiveText ?? sourceText
                }
            }
        }
        sources := new List<string>()
        fileNames := new List<string>()
        maxIndex := changedIndex
        sourceScanIndex := changedIndex + 1
        while sourceScanIndex < _sourceFiles.Count {
            if selected.Contains(Path.GetFullPath(_sourceFiles[sourceScanIndex])) {
                maxIndex = sourceScanIndex
            }
            sourceScanIndex = sourceScanIndex + 1
        }
        sourceIndex := 0
        while sourceIndex <= maxIndex {
            sourceFile := _sourceFiles[sourceIndex]
            if sourceIndex == changedIndex {
                sources.Add(changedEmissionText)
                fileNames.Add(sourceFile)
            } else if selected.Contains(Path.GetFullPath(sourceFile)) {
                skeleton := plan.Summaries[Path.GetFullPath(sourceFile)].InterfaceSkeleton
                if skeleton == null {
                    CompilerPhaseTimings.End(emitParseMark)
                    return false
                }
                sources.Add(skeleton)
                fileNames.Add(sourceFile)
            } else {
                placeholder := PersistedCheckPlaceholder(sourceFile, sourceIndex)
                sources.Add(placeholder)
                fileNames.Add(sourceFile)
            }
            sourceIndex = sourceIndex + 1
        }
        ColumnarDeclineTrace.Reset()
        emitParses: ColumnarFileProgramCache? = null
        warmState := _incrementalState
        if warmState != null {
            emitParses = warmState.EmitParses
        }
        if !ColumnarProgramInputBuilder.TryBuildMultiFile(sources, fileNames, _projectRoot, out program, _workers, emitParses) {
            CompilerPhaseTimings.End(emitParseMark)
            return false
        }
        CompilerPhaseTimings.End(emitParseMark)
        return true
    }

    private func PreparePersistedSubsetProgram(program: NSharpLang.Compiler.Columnar.ColumnarProgramInput, changedPath: string, changedIndex: int): void {
        sharedAnalyzer := _sharedAnalyzerValue
        if sharedAnalyzer != null {
            program.ReferenceMetadata = sharedAnalyzer.ReferenceMetadata
        }
        // The emitter wraps unannotated async bodies in the same family the analyzer typed them with.
        program.AsyncDefaultFamily = AsyncTaskFamilyFacts.ForLanguage(EffectiveConfig().Language)
        semanticModel: SemanticModel = null
        if _semanticModels.TryGetValue(changedPath, out semanticModel) {
            program.SetSemanticModelForFileId(changedIndex, semanticModel)
        }
    }

    private static func PersistedCheckPlaceholder(sourceFile: string, sourceIndex: int): string {
        indexText := sourceIndex.ToString(System.Globalization.CultureInfo.InvariantCulture)
        if sourceFile.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase) {
            return "namespace NSharpCheckPlaceholder\ntest \"cold check placeholder\" {}\n"
        }
        return "interface __NSharpCheckPlaceholder" + indexText + " {}\n"
    }

    private func TryEmitPersistedSubsetProgram(program: NSharpLang.Compiler.Columnar.ColumnarProgramInput, assemblyName: string): bool {
        outputConfig := _config
        outputType: string? = null
        if outputConfig != null {
            outputType = outputConfig.OutputType
        }
        isExecutable := ColumnarEmissionPlanner.IsExecutableOutput(outputType)
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
        if !ColumnarIlEmitter.TryEmitColumnarAssembly(assemblyName, "Program", program, isExecutable, out assembly, assemblyVersion, referenceAssemblyPaths) {
            CompilerPhaseTimings.End(codegenMark)
            return false
        }
        CompilerPhaseTimings.End(codegenMark)
        _emittedImage = assembly
        return true
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

    // NL936 -- THE PROJECT HAS NOTHING TO BUILD. `nlc build` compiles the product, and `*.tests.nl`
    // files belong to `nlc test` and `nlc check` (the way `go build` ignores `_test.go`), so a project
    // whose only sources are test files reaches emission with an empty file list. That is a fact about
    // the PROJECT, found before any code generation runs, and is reported as its own diagnostic rather
    // than as a code generator that "declined" a shape. A project with no `.nl` file at all (or none
    // left after its `exclude` patterns) gets its own wording. Returns true when it reported.
    private func ReportNoBuildableSources(): bool {
        if _sourceFiles.Count > 0 {
            return false
        }

        testFileCount := 0
        projectConfig := _config
        if projectConfig != null {
            for projectFile in projectConfig.GetSourceFiles(_projectRoot, true) {
                if ProjectSourceFileFilter.ProjectSourceFilterIsTestFile(projectFile) {
                    testFileCount++
                }
            }
        }

        explanation := "This project has no .nl source files, so there is nothing to compile."
        suggestion := "Add a .nl file next to project.yml, or check the `exclude` patterns in project.yml if the files you expected are being skipped."
        if testFileCount > 0 {
            explanation = "This project contains only test files (*.tests.nl), which `nlc build` does not compile."
            suggestion = "Run `nlc test` to run them or `nlc check` to type-check them, or add a non-test .nl file."
        }

        _allErrors.Add(new CompilerError(ErrorCode.NoSourcesToBuild, "No source files to build", 0, 0, ErrorSeverity.Error) {
            HumanExplanation: explanation,
            Suggestion: suggestion
        })
        return true
    }

    // A decline the driver itself makes (before or after the code generator ran) records its reason
    // in the same trace the generator's declines use, so no `columnar backend declined` message is
    // ever shown without one.
    private func DeclineWithReason(siteId: string, message: string): void {
        ColumnarDeclineTrace.Record(siteId, message, -1, 0, "")
    }

    private func BuildColumnarDeclineDiagnostic(): ColumnarDeclineDiagnostic {
        records := ColumnarDeclineTrace.Snapshot()
        WriteColumnarDeclineTrace(records)
        if (records.Count == 0) {
            // The driver's own early exits record a reason, and the parser and code generator record
            // at their decline sites; an exit that records nothing would otherwise print an
            // unexplained decline. Say so, so it can be reported and reduced.
            return new ColumnarDeclineDiagnostic("the code generator declined without recording where; please report this with the project that produced it", null, 0, 0, 1)
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
