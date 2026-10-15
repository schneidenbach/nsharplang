namespace NSharpLang.LanguageServer.Services

import System
import System.Collections.Concurrent
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Linq
import Microsoft.Extensions.Logging
import NSharpLang.Cli
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar
import NSharpLang.LanguageServer.Models


// Manages the state of all open documents and provides compilation services.
//
// WHAT EVERY NAME IN A FILE IS AND WHERE IT SITS is N#-owned by `EditorSymbolTableFacts` — the type
// catalog, the symbol table and the location table, one walk each, with the comment-block reader and
// the name-column search that go with them.
//
// WHERE A FILE BELONGS, WHEN A SNAPSHOT IS STALE AND WHICH DIAGNOSTICS BELONG TO IT are N#-owned by
// `EditorWorkspaceFacts` — the project-root walk, the two path comparisons, the snapshot stamp, the
// four reasons a semantic answer is refused, and the per-file diagnostic selection.
//
// What is left here is the editor's own state: which documents are open, which roots were scanned,
// the `file://` conversion, and the three dictionaries the owner's rows are poured into.
//
// THE SHARED ANALYZER MUST NOT OUTLIVE THE REFERENCES IT READ. It loads a project's references once
// per project directory into a metadata load context that keeps the bytes it read, so a referenced
// library rebuilt with a new member stayed the OLD library for the life of the server: every use of
// the new member was reported as missing until the editor restarted, and the cached project snapshot
// (stamped by sources and `project.yml` only) kept answering from the old one too. The workspace
// server had the same defect and retires itself (`DaemonLoadedReferenceGuard`); here the analyzer is
// replaced instead. Every file its context read is recorded (`ReferenceFileVersions`), and before a
// document is analysed or a snapshot is served, one that changed on disk swaps in a fresh analyzer,
// forgets which project directories were loaded and drops the cached snapshots and type catalog.
class DocumentManager {
    readonly documents: ConcurrentDictionary<string, DocumentState>
    readonly lastAccessTimes: ConcurrentDictionary<string, DateTime>
    readonly documentCacheLock: object
    readonly logger: ILogger<DocumentManager>
    SharedAnalyzer: Analyzer
    readonly codeIntelligenceService: CodeIntelligenceService
    readonly loadedProjectDirs: HashSet<string>
    readonly resolvedProjectConfigs: Dictionary<string, CachedResolvedProjectConfig>
    readonly projectSourcePathCache: ConcurrentDictionary<string, CachedProjectSourcePaths>
    readonly analyzerLock: object
    readonly projectSnapshotLock: object
    readonly projectSnapshots: ConcurrentDictionary<string, CachedProjectSnapshot>
    // One compiler-owned incremental session per semantic project. The session retains parsed
    // units and per-file binding results across editor edits, so a body change does not fall back
    // to the cold whole-project CodeIntelligenceService loader.
    readonly incrementalProjectSessions: ConcurrentDictionary<string, IncrementalProjectSession>
    readonly editorOpenUris: ConcurrentDictionary<string, byte>
    readonly workspaceRoots: ConcurrentDictionary<string, byte>
    readonly referenceVersions: ReferenceFileVersions
    // The shared analyzer's type universe as the completion and signature-help handlers read it;
    // rebuilt with the analyzer.
    typeCatalog: EditorTypeCatalog?

    constructor(logger: ILogger<DocumentManager>) {
        this.logger = logger
        documents = new ConcurrentDictionary<string, DocumentState>()
        lastAccessTimes = new ConcurrentDictionary<string, DateTime>()
        documentCacheLock = new object()
        codeIntelligenceService = new CodeIntelligenceService()
        loadedProjectDirs = new HashSet<string>()
        resolvedProjectConfigs = new Dictionary<string, CachedResolvedProjectConfig>(StringComparer.OrdinalIgnoreCase)
        projectSourcePathCache = new ConcurrentDictionary<string, CachedProjectSourcePaths>(StringComparer.OrdinalIgnoreCase)
        analyzerLock = new object()
        projectSnapshotLock = new object()
        projectSnapshots = new ConcurrentDictionary<string, CachedProjectSnapshot>()
        incrementalProjectSessions = new ConcurrentDictionary<string, IncrementalProjectSession>(StringComparer.OrdinalIgnoreCase)
        editorOpenUris = new ConcurrentDictionary<string, byte>()
        workspaceRoots = new ConcurrentDictionary<string, byte>()
        referenceVersions = new ReferenceFileVersions()
        typeCatalog = null

        // Initialize shared analyzer with system assemblies; it is replaced only when a reference it
        // read changes on disk (`RefreshStaleReferences`).
        SharedAnalyzer = new Analyzer()
        SharedAnalyzer.LoadSystemAssemblies()

        logger.LogInformation("DocumentManager initialized with shared Analyzer (system assemblies loaded)")
    }

    // A reference the shared analyzer read changed on disk: replace the analyzer, so the next
    // analysis loads the project's references again, and drop everything derived from the old one.
    // True when it did.
    func RefreshStaleReferences(): bool {
        lock analyzerLock {
            changed := referenceVersions.FindChanged()
            if changed == null {
                return false
            }

            logger.LogInformation("Referenced assembly changed on disk, reloading project references: {Path}", changed)
            fresh := new Analyzer()
            fresh.LoadSystemAssemblies()
            SharedAnalyzer = fresh
            loadedProjectDirs.Clear()
            resolvedProjectConfigs.Clear()
            referenceVersions.Clear()
            typeCatalog = null
        }

        lock projectSnapshotLock {
            projectSnapshots.Clear()
            incrementalProjectSessions.Clear()
        }
        return true
    }

    // The shared analyzer's type catalog, built on first use and again after a refresh.
    func CurrentTypeCatalog(): EditorTypeCatalog {
        lock analyzerLock {
            existing := typeCatalog
            if existing != null {
                return existing
            }

            created := SharedAnalyzer.CreateEditorTypeCatalog()
            typeCatalog = created
            return created
        }
    }

    // Records every file the shared analyzer's metadata context has read so far.
    func recordReferenceVersions(analyzer: Analyzer) {
        lock analyzerLock {
            for location in analyzer.MetadataInputAssemblyPaths() {
                referenceVersions.Record(location)
            }
        }
    }

    // Scans a workspace directory for all .nl files, loads them into the document manager,
    // and returns the URIs of all loaded files so diagnostics can be published.
    func ScanWorkspaceDirectory(rootPath: string): IReadOnlyList<string> {
        loadedUris := new List<string>()

        fullRoot := Path.GetFullPath(rootPath)
        workspaceRoots.TryAdd(fullRoot, 0)

        if !Directory.Exists(fullRoot) {
            logger.LogWarning("Workspace root does not exist: {RootPath}", fullRoot)
            return loadedUris
        }

        nlFiles: IEnumerable<string>? = null
        try {
            nlFiles = ProjectConfig.EnumerateSourceFiles(fullRoot)
        } catch enumerateFailure: Exception {
            logger.LogWarning(enumerateFailure, "Failed to enumerate .nl files in {RootPath}", fullRoot)
            return loadedUris
        }

        for filePath in must nlFiles {
            uri := EditorWorkspaceFacts.FilePathToUri(filePath)

            // Skip files already open in the editor — editor content takes precedence
            if editorOpenUris.ContainsKey(uri) {
                continue
            }

            try {
                text := File.ReadAllText(filePath)
                UpdateDocument(uri, text, 0)
                loadedUris.Add(uri)
            } catch readFailure: Exception {
                logger.LogWarning(readFailure, "Failed to load workspace file: {FilePath}", filePath)
            }
        }

        logger.LogInformation("Workspace scan loaded {Count} .nl files from {RootPath}", loadedUris.Count, fullRoot)
        return loadedUris
    }

    // Marks a document as opened in the editor. Editor-opened documents are not replaced by
    // workspace scans and are reverted to disk content on close (instead of being removed) if the
    // file belongs to a workspace.
    func MarkEditorOpen(uri: string) {
        lock documentCacheLock {
            editorOpenUris.TryAdd(uri, 0)
        }
    }

    // Handles an editor-close event. If the file belongs to a scanned workspace, reloads it from
    // disk so workspace diagnostics remain active. Otherwise, removes the document entirely.
    // Returns the URI if the document was reloaded from disk (caller should republish
    // diagnostics), or null if the document was fully removed.
    func HandleEditorClose(uri: string): string? {
        lock documentCacheLock {
            removedOpenMarker: byte = 0
            editorOpenUris.TryRemove(uri, out removedOpenMarker)
        }

        filePath := EditorWorkspaceFacts.UriToFilePath(uri)
        isInWorkspace := EditorWorkspaceFacts.ContainingWorkspaceRoot(filePath, workspaceRoots.Keys) != null

        if isInWorkspace && File.Exists(filePath) {
            // Reload from disk so workspace diagnostics stay alive
            try {
                text := File.ReadAllText(filePath)
                UpdateDocument(uri, text, 0)
                return uri
            } catch reloadFailure: Exception {
                logger.LogWarning(reloadFailure, "Failed to reload workspace file on close: {FilePath}", filePath)
            }
        }

        CloseDocument(uri)
        return null
    }

    // Handles a file change on disk. Re-reads the file and updates the document if it is not
    // currently open in the editor.
    // Returns the URI if the document was updated (caller should republish), or null.
    func HandleFileChangedOnDisk(filePath: string): string? {
        fullPath := Path.GetFullPath(filePath)
        uri := EditorWorkspaceFacts.FilePathToUri(fullPath)

        // Don't overwrite editor content
        if editorOpenUris.ContainsKey(uri) {
            return null
        }

        if !File.Exists(fullPath) {
            return null
        }

        try {
            text := File.ReadAllText(fullPath)
            // A watcher event may be the first time this file is tracked, so UpdateDocument cannot
            // compare it with an earlier buffer to decide whether the cached project changed.
            invalidateProjectSnapshot(fullPath)
            invalidateProjectSourcePaths(fullPath)
            UpdateDocument(uri, text, 0)
            return uri
        } catch reloadFailure: Exception {
            logger.LogWarning(reloadFailure, "Failed to reload changed file: {FilePath}", fullPath)
            return null
        }
    }

    // Handles a file creation on disk. Loads the new file if it's under a workspace root.
    // Returns the URI if the document was loaded (caller should publish), or null.
    func HandleFileCreatedOnDisk(filePath: string): string? {
        fullPath := Path.GetFullPath(filePath)

        if EditorWorkspaceFacts.ContainingWorkspaceRoot(fullPath, workspaceRoots.Keys) == null {
            return null
        }

        return HandleFileChangedOnDisk(fullPath)
    }

    // Handles a file deletion on disk. Removes the document if it's not open in the editor.
    // Returns the URI if the document was removed (caller should clear diagnostics), or null.
    func HandleFileDeletedOnDisk(filePath: string): string? {
        fullPath := Path.GetFullPath(filePath)
        uri := EditorWorkspaceFacts.FilePathToUri(fullPath)

        // If still open in editor, leave it alone
        if editorOpenUris.ContainsKey(uri) {
            return null
        }

        invalidateProjectSnapshot(fullPath)
        invalidateProjectSourcePaths(fullPath)

        if documents.ContainsKey(uri) {
            CloseDocument(uri)
            return uri
        }

        return null
    }

    // Returns whether a URI is currently tracked by the document manager.
    func HasDocument(uri: string): bool => documents.ContainsKey(uri)

    // A project snapshot depends on effective source text, not on the act of opening a document.
    // An existing buffer changes that input only when its text changes. A newly tracked buffer
    // changes it only when it differs from the disk file already included in the project snapshot.
    func shouldInvalidateProjectSnapshot(uri: string, filePath: string, text: string): bool {
        existing: DocumentState? = null
        if documents.TryGetValue(uri, out existing) && existing != null {
            return existing.Text != text
        }

        return EditorWorkspaceFacts.SourceTextDiffersFromDisk(filePath, text)
    }

    func UpdateDocument(uri: string, text: string, version: int) {
        updateDocument(uri, text, version)
    }

    // Workspace scans already parsed the on-disk version of a document. When the editor opens
    // that exact text, reuse its state and the current project snapshot instead of running the
    // per-document analyzer and re-stamping every project source file.
    func UpdateDocumentForOpen(uri: string, text: string, version: int): bool {
        existing: DocumentState? = null
        if documents.TryGetValue(uri, out existing) && existing != null && existing.Text == text && existing.Tokens != null {
            existing.Version = version
            lastAccessTimes[uri] = DateTime.UtcNow
            logger.LogInformation("LSP document analysis counters: documentAnalysisRuns=0 documentCacheReuses=1")
            return true
        }

        if tryRestoreProjectDocument(uri, text, version) {
            logger.LogInformation("LSP document analysis counters: documentAnalysisRuns=0 documentCacheReuses=1")
            return true
        }

        updateDocument(uri, text, version)
        logger.LogInformation("LSP document analysis counters: documentAnalysisRuns=1 documentCacheReuses=0")
        return false
    }

    // The bounded editor-document cache may have evicted a closed workspace file while the
    // IncrementalProjectSession still owns its parsed unit, binding and semantic snapshot. Restore
    // the editor-facing state from that compiler-owned record when the incoming text hash matches;
    // only lexing and editor projections are needed, not parsing or semantic analysis.
    private func tryRestoreProjectDocument(uri: string, text: string, version: int): bool {
        if !CanUseIncrementalProjectSnapshot(uri) {
            return false
        }

        RefreshStaleReferences()
        filePath := Path.GetFullPath(EditorWorkspaceFacts.UriToFilePath(uri))
        projectRoot := EditorWorkspaceFacts.SemanticProjectRoot(filePath, workspaceRoots.Keys)
        projectFile := Path.Combine(projectRoot, "project.yml")
        cached: CachedProjectSnapshot? = null
        if !projectSnapshots.TryGetValue(projectRoot, out cached) || cached == null || cached.ProjectConfigFileStamp != ProjectConfigFileStamp(projectFile) {
            return false
        }

        session: IncrementalProjectSession? = null
        if !incrementalProjectSessions.TryGetValue(projectRoot, out session) || session == null {
            return false
        }

        activeSession := session ?? throw new InvalidOperationException("Incremental project session disappeared.")
        fileRecord: IncrementalFileRecord? = null
        if !activeSession.State.Files.TryGetValue(filePath, out fileRecord) || fileRecord == null {
            return false
        }
        activeFileRecord := fileRecord ?? throw new InvalidOperationException("Incremental project file record disappeared.")
        if activeFileRecord.Summary.TextHash != ContentHash.OfText(text) || activeFileRecord.Unit == null || !activeFileRecord.Analyzed {
            return false
        }

        restored := new DocumentState(uri, text, version)
        restored.CompilationUnit = activeFileRecord.Unit
        restored.SemanticModel = activeFileRecord.SemanticModel
        restored.Bindings = activeFileRecord.Bindings
        activeSnapshot := cached ?? throw new InvalidOperationException("Cached project snapshot disappeared.")
        restored.Diagnostics = EditorWorkspaceFacts.DiagnosticsForFile(activeSnapshot.Snapshot.AllErrors, activeSnapshot.Snapshot.ProjectRoot, filePath)

        lexer := new Lexer(text, filePath)
        restored.Tokens = lexer.Tokenize()
        restored.Comments = lexer.Comments

        unit := activeFileRecord.Unit ?? throw new InvalidOperationException("The reused project file has no compilation unit.")
        projectDir := Path.GetDirectoryName(filePath) ?? projectRoot
        linter := new Linter(LinterConfig.FromEditorConfig(projectDir))
        restored.LinterDiagnostics = linter.Lint(unit, filePath, text)
        restored.Symbols = EditorSymbolTableFacts.TypeCatalog(unit)
        restored.SymbolsInfo = toSymbolsInfo(EditorSymbolTableFacts.SymbolInfoRows(unit, text))
        restored.SymbolLocations = toSymbolLocations(EditorSymbolTableFacts.SymbolLocationRows(unit, text), uri)
        storeDocument(uri, restored)
        return true
    }

    // A same-text didOpen may answer from the last valid semantic project snapshot. File-system
    // watcher events and reference changes evict that snapshot; the project file stamp catches a
    // project configuration change without walking or hashing all source files.
    func GetCachedDiagnosticsForOpen(uri: string): DocumentDiagnosticsPublication? {
        doc := GetDocument(uri)
        if doc == null {
            return null
        }

        RefreshStaleReferences()
        filePath := EditorWorkspaceFacts.UriToFilePath(uri)
        projectRoot := EditorWorkspaceFacts.SemanticProjectRoot(filePath, workspaceRoots.Keys)
        projectFile := Path.Combine(projectRoot, "project.yml")
        cached: CachedProjectSnapshot? = null
        if !projectSnapshots.TryGetValue(projectRoot, out cached) || cached == null || cached.ProjectConfigFileStamp != ProjectConfigFileStamp(projectFile) {
            return null
        }

        logger.LogInformation("LSP structural counters: projectSnapshotsBuilt=0 filesParsed=0 filesReanalyzed=0 filesReused=0 documentsHydrated=0 projectSnapshotCacheHits=1 projectDiskStampScans=0")
        return new DocumentDiagnosticsPublication(
            uri,
            EditorWorkspaceFacts.DiagnosticsForFile(cached.Snapshot.AllErrors, cached.Snapshot.ProjectRoot, filePath),
            doc.LinterDiagnostics ?? new List<Diagnostic>()
        )
    }

    // A project didChange buffer is queued without duplicate parsing and then semantically analysed
    // by the retained project session when diagnostics are requested. Loose files keep their
    // established single-document path.
    func UpdateDocumentForChange(uri: string, text: string, version: int) {
        if CanUseIncrementalProjectSnapshot(uri) {
            updateDocumentTextBuffer(uri, text, version)
        } else {
            updateDocument(uri, text, version)
        }
    }

    private func updateDocument(uri: string, text: string, version: int): void {
        try {
            logger.LogInformation("Updating document: {Uri} (version {Version})", uri, version)

            state := new DocumentState(uri, text, version)
            filePath := EditorWorkspaceFacts.UriToFilePath(uri)
            if shouldInvalidateProjectSnapshot(uri, filePath, text) {
                invalidateProjectSnapshot(filePath)
            }

            // Parse the document using the real filesystem path so downstream
            // import resolution never sees a file:/// URI as the current file.
            lexer := new Lexer(text, filePath)
            state.Tokens = lexer.Tokenize()
            state.Comments = lexer.Comments

            parseResult := ColumnarParserRecovery.ParseFileAst(text, filePath)
            state.CompilationUnit = parseResult.CompilationUnit

            // Start with parse errors
            diagnostics := new List<CompilerError>(parseResult.Errors)

            // Resolve the nearest declared project once through the same N# reference resolver the
            // CLI uses. Looking only in the file's immediate directory missed parent project.yml
            // files, and loading Analyzer references directly left framework references such as
            // Microsoft.AspNetCore.App without their full shared-framework closure.
            projectDir := Path.GetDirectoryName(filePath) ?? Environment.CurrentDirectory
            projectRoot := EditorWorkspaceFacts.FindProjectRoot(filePath)
            hasProjectConfig := File.Exists(Path.Combine(projectRoot, "project.yml"))
            isExcludedFromProject := false
            if hasProjectConfig && EditorWorkspaceFacts.ContainingWorkspaceRoot(filePath, workspaceRoots.Keys) == null {
                // Preserve the existing project-config error path below. A malformed config is
                // not evidence that this editor buffer is intentionally excluded.
                try {
                    includeTests := filePath.EndsWith(".tests.nl", StringComparison.OrdinalIgnoreCase)
                    configuredSources := ProjectSourcePathsFor(
                        projectRoot,
                        ProjectConfigFileStamp(Path.Combine(projectRoot, "project.yml")),
                        includeTests
                    )
                    isExcludedFromProject = !configuredSources.Contains(Path.GetFullPath(filePath))
                    if isExcludedFromProject {
                        hasProjectConfig = false
                    }
                    // The next config read owns the user-facing malformed-config error.
                    // nlc:ignore NL011
                } catch sourcePathFailure: Exception {
                }
            }

            referenceRoot := projectDir
            projectConfig := ProjectFileParser.ParseFromDirectoryOrDefault(projectDir)
            analysisProjectRoot := EditorWorkspaceFacts.AnalysisProjectRoot(projectDir)
            if isExcludedFromProject {
                analysisProjectRoot = null
            }

            // Load assemblies from project configuration ONCE per project directory -- and again after
            // a reference the analyzer read changed on disk (`RefreshStaleReferences`).
            // Use lock to ensure thread-safe access to shared analyzer and loaded projects cache
            RefreshStaleReferences()
            if hasProjectConfig {
                referenceRoot = projectRoot
                projectConfig = ResolvedProjectConfig(projectRoot)
                analysisProjectRoot = projectRoot
            }

            analyzer := SharedAnalyzer
            lock analyzerLock {
                analyzer = SharedAnalyzer
                if !loadedProjectDirs.Contains(referenceRoot) {
                    logger.LogInformation("Loading assemblies for project root: {ProjectDir}", referenceRoot)
                    analyzer.LoadFromProjectConfig(projectConfig, referenceRoot)
                    loadedProjectDirs.Add(referenceRoot)
                }
                // One shared analyzer serves every project in the workspace: the references above
                // load once per project, but the language settings are this document's project's.
                analyzer.ApplyLanguageSettings(projectConfig)
            }

            // Only run analysis if we have a valid compilation unit
            unit := state.CompilationUnit
            if unit != null {
                // Use shared analyzer (thread-safe because Analyze doesn't mutate state)
                analysisResult := analyzer.Analyze(unit, filePath, analysisProjectRoot, text)
                recordReferenceVersions(analyzer)
                diagnostics.AddRange(analysisResult.Errors)

                // Store semantic model and binding map for IDE features
                state.SemanticModel = analysisResult.SemanticModel
                state.Bindings = analysisResult.Bindings

                // Run linter for additional diagnostics
                linterConfig := LinterConfig.FromEditorConfig(projectDir)
                linter := new Linter(linterConfig)
                state.LinterDiagnostics = linter.Lint(unit, filePath, text)

                // Store symbol information for later use
                state.Symbols = EditorSymbolTableFacts.TypeCatalog(unit)
                state.SymbolsInfo = toSymbolsInfo(EditorSymbolTableFacts.SymbolInfoRows(unit, text))
                state.SymbolLocations = toSymbolLocations(EditorSymbolTableFacts.SymbolLocationRows(unit, text), uri)
            }

            state.Diagnostics = EditorWorkspaceFacts.DeduplicateDiagnostics(diagnostics)
            storeDocument(uri, state)

            logger.LogInformation(
                "Document updated successfully with {DiagnosticCount} diagnostics ({ParseErrors} parse errors)",
                state.Diagnostics.Count,
                parseResult.Errors.Count
            )
        } catch updateFailure: Exception {
            logger.LogError(updateFailure, "Error updating document: {Uri}", uri)

            // Store document with error state
            failed := new DocumentState(uri, text, version)
            failedDiagnostics := new List<CompilerError>()
            failedDiagnostics.Add(CompilerError.Create(
                ErrorCode.InvalidSyntax,
                "Internal error: " + updateFailure.Message,
                1,
                1,
                ErrorSeverity.Error
            ))
            failed.Diagnostics = failedDiagnostics
            storeDocument(uri, failed)
        }
    }

    // Closed documents provide the bounded cache; editor-open buffers contain live user state and
    // stay resident even when the workspace has more than the cache ceiling's number of open files.
    // The same lock protects open/close transitions so an LRU candidate cannot become protected
    // between selection and removal.
    private func storeDocument(uri: string, state: DocumentState): void {
        lock documentCacheLock {
            if EditorDocumentCacheFacts.ShouldEvictBefore(documents.Count, documents.ContainsKey(uri)) {
                cacheRows := new List<EditorDocumentCacheRow>()
                protectedUris := new List<string>()
                for openUri in editorOpenUris.Keys {
                    protectedUris.Add(openUri)
                }
                for entry in lastAccessTimes {
                    cacheRows.Add(new EditorDocumentCacheRow(entry.Key, entry.Value.Ticks))
                }

                evicted := EditorDocumentCacheFacts.EvictionUriExcluding(cacheRows, protectedUris)
                if evicted != null {
                    evictedState: DocumentState? = null
                    evictedTime: DateTime = DateTime.MinValue
                    documents.TryRemove(evicted, out evictedState)
                    lastAccessTimes.TryRemove(evicted, out evictedTime)
                    logger.LogInformation("Evicted least recently accessed closed document: {Uri}", evicted)
                }
            }

            documents[uri] = state
            lastAccessTimes[uri] = DateTime.UtcNow
        }
    }

    // Whether the incremental project snapshot owns this buffer. Excluded project files and loose
    // files retain the established single-document analysis path.
    func CanUseIncrementalProjectSnapshot(uri: string): bool {
        filePath := EditorWorkspaceFacts.UriToFilePath(uri)
        workspaceRoot := EditorWorkspaceFacts.ContainingWorkspaceRoot(filePath, workspaceRoots.Keys)
        if workspaceRoot != null {
            return true
        }

        projectRoot := EditorWorkspaceFacts.FindProjectRoot(filePath)
        projectFile := Path.Combine(projectRoot, "project.yml")
        if !File.Exists(projectFile) {
            return false
        }

        try {
            sourcePaths := ProjectSourcePathsFor(projectRoot, ProjectConfigFileStamp(projectFile), true)
            return sourcePaths.Contains(Path.GetFullPath(filePath))
        } catch sourcePathFailure: Exception {
            return false
        }
    }

    // Store a project buffer without running either the per-document Analyzer or a redundant parse.
    // The incremental compiler owns parsing and binding; its resulting AST then hydrates the editor
    // state before diagnostics are published.
    private func updateDocumentTextBuffer(uri: string, text: string, version: int): void {
        try {
            filePath := EditorWorkspaceFacts.UriToFilePath(uri)
            if shouldInvalidateProjectSnapshot(uri, filePath, text) {
                invalidateProjectSnapshot(filePath)
            }

            storeDocument(uri, new DocumentState(uri, text, version))
            logger.LogDebug("Queued project document version {Version} for incremental analysis: {Uri}", version, uri)
        } catch updateFailure: Exception {
            logger.LogError(updateFailure, "Error updating document buffer: {Uri}", uri)
            failed := new DocumentState(uri, text, version)
            failedDiagnostics := new List<CompilerError>()
            failedDiagnostics.Add(CompilerError.Create(
                ErrorCode.InvalidSyntax,
                "Internal error: " + updateFailure.Message,
                1,
                1,
                ErrorSeverity.Error
            ))
            failed.Diagnostics = failedDiagnostics
            storeDocument(uri, failed)
        }
    }

    func GetDocument(uri: string): DocumentState? {
        doc: DocumentState? = null
        if documents.TryGetValue(uri, out doc) {
            lastAccessTimes[uri] = DateTime.UtcNow
            return doc
        }

        return null
    }

    func CloseDocument(uri: string) {
        filePath := EditorWorkspaceFacts.UriToFilePath(uri)
        existing: DocumentState? = null
        shouldInvalidate := !File.Exists(filePath)
        if documents.TryGetValue(uri, out existing) && existing != null {
            shouldInvalidate = EditorWorkspaceFacts.SourceTextDiffersFromDisk(filePath, existing.Text)
        }
        if shouldInvalidate {
            invalidateProjectSnapshot(filePath)
        }

        removedState: DocumentState? = null
        removedTime: DateTime = DateTime.MinValue
        documents.TryRemove(uri, out removedState)
        lastAccessTimes.TryRemove(uri, out removedTime)
        logger.LogInformation("Document closed: {Uri}", uri)
    }

    func FindProjectDefinition(uri: string, line0: int, character0: int): DefinitionResult? {
        binding := SynchronizedProjectSnapshot(uri)
        if binding == null {
            return null
        }

        return codeIntelligenceService.FindDefinition(binding.Snapshot, binding.FilePath, line0 + 1, character0 + 1)
    }

    func FindProjectReferences(uri: string, line0: int, character0: int): List<ReferenceResult>? {
        binding := SynchronizedProjectSnapshot(uri)
        if binding == null {
            return null
        }

        results := codeIntelligenceService.FindReferences(binding.Snapshot, binding.FilePath, line0 + 1, character0 + 1)
        if results.Count > 0 {
            return results
        }

        return null
    }

    func FindProjectHover(uri: string, line0: int, character0: int): HoverResult? {
        binding := SynchronizedProjectSnapshot(uri)
        if binding == null {
            return null
        }

        return codeIntelligenceService.GetHoverInfo(binding.Snapshot, binding.FilePath, line0 + 1, character0 + 1)
    }

    func FindStrictProjectReferences(uri: string, line0: int, character0: int): List<ReferenceResult>? {
        binding := SynchronizedProjectSnapshot(uri)
        if binding == null {
            return null
        }

        results := codeIntelligenceService.FindStrictReferences(binding.Snapshot, binding.FilePath, line0 + 1, character0 + 1)
        if results.Count > 0 {
            return results
        }

        return null
    }

    func HasSynchronizedProjectSnapshot(uri: string): bool => SynchronizedProjectSnapshot(uri) != null

    func HasSemanticProjectContext(uri: string): bool {
        filePath := EditorWorkspaceFacts.UriToFilePath(uri)
        projectRoot := EditorWorkspaceFacts.SemanticProjectRoot(filePath, workspaceRoots.Keys)
        return File.Exists(Path.Combine(projectRoot, "project.yml")) || EditorWorkspaceFacts.ContainingWorkspaceRoot(filePath, workspaceRoots.Keys) != null
    }

    func GetProjectRootForUri(uri: string): string {
        return EditorWorkspaceFacts.SemanticProjectRoot(EditorWorkspaceFacts.UriToFilePath(uri), workspaceRoots.Keys)
    }

    func ResolveProjectFilePath(projectRoot: string, relativeOrAbsolutePath: string): string => EditorWorkspaceFacts.ProjectFilePath(projectRoot, relativeOrAbsolutePath)

    func FindSymbolLocations(name: string): IReadOnlyList<SymbolLocation> {
        results := new List<SymbolLocation>()

        for doc in documents.Values {
            table := doc.SymbolLocations
            if table != null {
                locations: List<SymbolLocation>? = null
                if table.TryGetValue(name, out locations) {
                    results.AddRange(locations)
                }
            }
        }

        return results
    }

    // Returns all documents currently tracked by the document manager.
    // Used by workspace-wide features like workspace symbols and semantic tokens.
    func GetAllDocuments(): IReadOnlyCollection<DocumentState> {
        return documents.Values.ToList()
    }

    // Returns the diagnostics that should be published for the current project scope.
    // When the project snapshot can be synchronized with disk, this returns one entry per open
    // document in the project so related files can be refreshed together. Otherwise, it falls back
    // to the current document only.
    func GetDiagnosticsToPublish(uri: string): IReadOnlyList<DocumentDiagnosticsPublication> {
        doc := GetDocument(uri)
        if doc == null {
            return new List<DocumentDiagnosticsPublication>()
        }

        binding := SynchronizedProjectSnapshot(uri)
        if binding == null {
            if doc.Tokens == null {
                UpdateDocument(uri, doc.Text, doc.Version)
                refreshedDoc := GetDocument(uri)
                if refreshedDoc == null {
                    return new List<DocumentDiagnosticsPublication>()
                }
                fallback := new List<DocumentDiagnosticsPublication>()
                fallback.Add(buildPublicationFromDocument(refreshedDoc))
                return fallback
            }

            fallback := new List<DocumentDiagnosticsPublication>()
            fallback.Add(buildPublicationFromDocument(doc))
            return fallback
        }

        projectRoot := binding.ProjectRoot

        openDocsInProject := documents.Values.Where(d => EditorWorkspaceFacts.IsPathUnderProject(EditorWorkspaceFacts.UriToFilePath(d.Uri), projectRoot) && binding.RefreshedFilePaths.Contains(Path.GetFullPath(EditorWorkspaceFacts.UriToFilePath(d.Uri)))).OrderBy(d => d.Uri, StringComparer.Ordinal).ToList()
        openDocsInProject = openDocsInProject.OrderBy(d => d.Uri == doc.Uri ? 0 : 1).ThenBy(d => d.Uri, StringComparer.Ordinal).ToList()

        publications := new List<DocumentDiagnosticsPublication>(openDocsInProject.Count)
        for openDoc in openDocsInProject {
            publications.Add(new DocumentDiagnosticsPublication(
                openDoc.Uri,
                openDoc.Diagnostics ?? new List<CompilerError>(),
                openDoc.LinterDiagnostics ?? new List<Diagnostic>()
            ))
        }

        if publications.Count == 0 {
            publications.Add(buildPublicationFromDocument(doc))
        }

        return publications
    }

    // The project snapshot this URI is served by, with the two paths that were computed on the way
    // to it — or null when one of the owner's four refusals applies, or the load itself failed.
    // The C# spelled this as a `bool` with three `out` parameters; the answer and the values that
    // only exist when it is yes belong together.
    func SynchronizedProjectSnapshot(uri: string): ProjectSnapshotBinding? {
        filePath := EditorWorkspaceFacts.UriToFilePath(uri)
        projectRoot := EditorWorkspaceFacts.SemanticProjectRoot(filePath, workspaceRoots.Keys)

        refusal := EditorWorkspaceFacts.SnapshotRefusal(filePath, projectRoot, workspaceRoots.Keys)
        if refusal != null {
            logProjectSnapshotDegraded(refusal)
            return null
        }

        RefreshStaleReferences()

        sourceInputTimer := Stopwatch.StartNew()
        projectFile := Path.Combine(projectRoot, "project.yml")
        projectConfigFileStamp := ProjectConfigFileStamp(projectFile)
        projectSourcePaths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        try {
            // The editor's semantic project is the same source set `nlc check` compiles. Test files
            // are ordinary N# source whose declarations and test-block bodies participate in the
            // binding index used by references, rename and navigation.
            projectSourcePaths = ProjectSourcePathsFor(projectRoot, projectConfigFileStamp, true)
        } catch sourcePathFailure: Exception {
            logProjectSnapshotDegradedWith(EditorWorkspaceFacts.LoadFailedRefusal(projectRoot, sourcePathFailure.Message), sourcePathFailure)
            return null
        }
        if !projectSourcePaths.Contains(Path.GetFullPath(filePath)) && EditorWorkspaceFacts.ContainingWorkspaceRoot(filePath, workspaceRoots.Keys) == null {
            return null
        }

        sourceTextOverrides := buildOpenBufferSourceTextOverrides(projectRoot)
        stampSourceTextOverrides := buildSnapshotStampSourceTextOverrides(sourceTextOverrides, projectSourcePaths)
        stamp := EditorWorkspaceFacts.ProjectSnapshotStamp(projectRoot, stampSourceTextOverrides)
        if stamp == null {
            logProjectSnapshotDegraded(EditorWorkspaceFacts.NoSourceFilesRefusal(projectRoot))
            return null
        }
        sourceInputsMs := sourceInputTimer.ElapsedMilliseconds

        lock projectSnapshotLock {
            cached: CachedProjectSnapshot? = null
            if projectSnapshots.TryGetValue(projectRoot, out cached) && cached.ProjectConfigFileStamp == projectConfigFileStamp && EditorDocumentCacheFacts.SnapshotCacheHit(cached.Stamp, stamp) {
                logger.LogInformation("LSP structural counters: projectSnapshotsBuilt=0 filesParsed=0 filesReanalyzed=0 filesReused=0 documentsHydrated=0 projectSnapshotCacheHits=1 projectDiskStampScans=1")
                refreshedFilePaths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                refreshedFilePaths.Add(Path.GetFullPath(filePath))
                return new ProjectSnapshotBinding(projectRoot, filePath, cached.Snapshot, refreshedFilePaths)
            }

            try {
                projectConfig: ProjectConfig? = null
                if File.Exists(projectFile) {
                    projectConfig = ResolvedProjectConfig(projectRoot)
                }

                effectiveProjectConfig := projectConfig ?? ProjectFileParser.ParseFromDirectoryOrDefault(projectRoot)
                sourceFiles := new List<string>()
                for sourcePath in projectSourcePaths {
                    sourceFiles.Add(sourcePath)
                }
                sourceFiles.Sort(StringComparer.OrdinalIgnoreCase)

                session: IncrementalProjectSession? = null
                if !incrementalProjectSessions.TryGetValue(projectRoot, out session) || session == null {
                    created := new IncrementalProjectSession(projectRoot, "NSharpLang.LanguageServer")
                    incrementalProjectSessions[projectRoot] = created
                    session = created
                }

                activeSession := session ?? throw new InvalidOperationException("Incremental project session was not created.")
                phaseTimer := Stopwatch.StartNew()
                activeSession.Analyze(effectiveProjectConfig, sourceFiles, sourceTextOverrides, true)
                sessionAnalyzeMs := phaseTimer.ElapsedMilliseconds
                phaseTimer.Restart()
                loaded := activeSession.Snapshot()
                if loaded == null {
                    throw new InvalidOperationException("Incremental project analysis did not produce a semantic snapshot.")
                }
                projectSnapshotMs := phaseTimer.ElapsedMilliseconds
                phaseTimer.Restart()
                semanticRefresh := updateOpenDocumentSemanticState(activeSession, loaded, filePath)
                documentHydrationMs := phaseTimer.ElapsedMilliseconds
                logger.LogInformation(
                    "LSP structural counters: projectSnapshotsBuilt={ProjectSnapshotsBuilt} filesParsed={FilesParsed} filesReanalyzed={FilesReanalyzed} filesReused={FilesReused} documentsHydrated={DocumentsHydrated} projectSnapshotCacheHits=0 projectDiskStampScans=1",
                    1,
                    activeSession.State.LastFilesParsed,
                    activeSession.State.LastFilesAnalyzed,
                    activeSession.State.LastFilesReused,
                    semanticRefresh.HydratedFilePaths.Count
                )
                logger.LogDebug(
                    "LSP phase timings: sourceInputsMs={SourceInputsMs} sessionAnalyzeMs={SessionAnalyzeMs} planMs={PlanMs} parseMs={ParseMs} importGraphMs={ImportGraphMs} fileAnalysisMs={FileAnalysisMs} fileAnalyzerMs={FileAnalyzerMs} projectMergeMs={ProjectMergeMs} systemsPolicyMs={SystemsPolicyMs} projectSnapshotMs={ProjectSnapshotMs} documentHydrationMs={DocumentHydrationMs}",
                    sourceInputsMs,
                    sessionAnalyzeMs,
                    activeSession.State.LastPlanMilliseconds,
                    activeSession.State.LastParseMilliseconds,
                    activeSession.State.LastImportGraphMilliseconds,
                    activeSession.State.LastFileAnalysisMilliseconds,
                    activeSession.State.LastFileAnalyzerMilliseconds,
                    activeSession.State.LastProjectMergeMilliseconds,
                    activeSession.State.LastSystemsPolicyMilliseconds,
                    projectSnapshotMs,
                    documentHydrationMs
                )
                loadedStampOverrides := buildSnapshotStampSourceTextOverrides(sourceTextOverrides, projectSourcePaths)
                loadedStamp := EditorWorkspaceFacts.ProjectSnapshotStamp(projectRoot, loadedStampOverrides)
                projectSnapshots[projectRoot] = new CachedProjectSnapshot(loadedStamp ?? stamp, projectConfigFileStamp, loaded)
                logger.LogDebug(
                    "Loaded semantic project snapshot for {ProjectRoot} with {OpenBufferCount} open-buffer overrides",
                    projectRoot,
                    sourceTextOverrides.Count
                )
                return new ProjectSnapshotBinding(projectRoot, filePath, loaded, semanticRefresh.FilePaths)
            } catch loadFailure: Exception {
                logProjectSnapshotDegradedWith(EditorWorkspaceFacts.LoadFailedRefusal(projectRoot, loadFailure.Message), loadFailure)
                return null
            }
        }
    }

    // Bring the currently tracked document states into line with the same incremental compilation
    // snapshot used for diagnostics and project queries. Per-file bindings stay with the session's
    // IncrementalFileRecord; the public snapshot carries the merged project index.
    func updateOpenDocumentSemanticState(session: IncrementalProjectSession, snapshot: ProjectSnapshot, changedFilePath: string): SemanticDocumentRefresh {
        refreshedFilePaths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        hydratedFilePaths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        sourceFilePaths := new HashSet<string>(snapshot.SourceFiles, StringComparer.OrdinalIgnoreCase)
        for document in documents.Values {
            filePath := Path.GetFullPath(EditorWorkspaceFacts.UriToFilePath(document.Uri))
            if !sourceFilePaths.Contains(filePath) {
                continue
            }

            unit: NSharpLang.Compiler.Ast.CompilationUnit? = null
            hasUnit := snapshot.CompilationUnits.TryGetValue(filePath, out unit)

            semanticModel: SemanticModel? = null
            hasSemanticModel := snapshot.SemanticModels.TryGetValue(filePath, out semanticModel)

            semanticChanged := hasSemanticModel && !Object.ReferenceEquals(document.SemanticModel, semanticModel)
            unitChanged := hasUnit && !Object.ReferenceEquals(document.CompilationUnit, unit)
            needsHydration := document.Tokens == null || semanticChanged || unitChanged

            if hasUnit {
                document.CompilationUnit = unit
            }
            if hasSemanticModel {
                document.SemanticModel = semanticModel
            }

            fileRecord: IncrementalFileRecord? = null
            if session.State.Files.TryGetValue(filePath, out fileRecord) && fileRecord != null {
                document.Bindings = fileRecord.Bindings
            }

            if !needsHydration {
                continue
            }

            // Reused semantic models mean the compiler proved this file's bindings are unchanged.
            // Keep its diagnostics, lint facts and symbol projections intact; an interface change
            // gives its reanalyzed dependents new models and refreshes those files here.
            document.Diagnostics = EditorWorkspaceFacts.DiagnosticsForFile(snapshot.AllErrors, snapshot.ProjectRoot, filePath)
            if document.Tokens == null {
                lexer := new Lexer(document.Text, filePath)
                document.Tokens = lexer.Tokenize()
                document.Comments = lexer.Comments
            }

            hydratedUnit := document.CompilationUnit
            if hydratedUnit != null {
                projectDir := Path.GetDirectoryName(filePath) ?? snapshot.ProjectRoot
                linter := new Linter(LinterConfig.FromEditorConfig(projectDir))
                document.LinterDiagnostics = linter.Lint(hydratedUnit, filePath, document.Text, snapshot.SourceTexts)
                document.Symbols = EditorSymbolTableFacts.TypeCatalog(hydratedUnit)
                document.SymbolsInfo = toSymbolsInfo(EditorSymbolTableFacts.SymbolInfoRows(hydratedUnit, document.Text))
                document.SymbolLocations = toSymbolLocations(EditorSymbolTableFacts.SymbolLocationRows(hydratedUnit, document.Text), document.Uri)
            }
            refreshedFilePaths.Add(filePath)
            hydratedFilePaths.Add(filePath)
        }

        // The triggering buffer is always part of this publication batch, including a recovered
        // parse path whose snapshot has no semantic model for it.
        refreshedFilePaths.Add(Path.GetFullPath(changedFilePath))
        return new SemanticDocumentRefresh(refreshedFilePaths, hydratedFilePaths)
    }

    func invalidateProjectSnapshot(filePath: string) {
        for projectRoot in EditorWorkspaceFacts.PossibleSemanticProjectRoots(filePath, workspaceRoots.Keys) {
            removed: CachedProjectSnapshot? = null
            projectSnapshots.TryRemove(projectRoot, out removed)
        }
    }

    func invalidateProjectSourcePaths(filePath: string) {
        for projectRoot in EditorWorkspaceFacts.PossibleSemanticProjectRoots(filePath, workspaceRoots.Keys) {
            removed: CachedProjectSourcePaths? = null
            projectSourcePathCache.TryRemove(projectRoot, out removed)
            removed = null
            projectSourcePathCache.TryRemove(projectRoot + "\u0000tests", out removed)
        }
    }

    // The resolved config is shared by the per-document analyzer and the project snapshot. Keeping
    // it here avoids repeating framework, package and project-reference resolution on every edit;
    // the project file is also tracked as a reference input so a changed config replaces this cache.
    func ResolvedProjectConfig(projectRoot: string): ProjectConfig {
        fullRoot := Path.GetFullPath(projectRoot)
        projectFile := Path.Combine(fullRoot, "project.yml")
        projectFileStamp := ProjectConfigFileStamp(projectFile)

        lock analyzerLock {
            cached: CachedResolvedProjectConfig? = null
            if resolvedProjectConfigs.TryGetValue(fullRoot, out cached) && cached.ProjectFileStamp == projectFileStamp {
                return cached.Config
            }

            config := ProjectFileParser.ParseFromDirectoryOrDefault(fullRoot)
            options := new ReferenceResolutionOptions()
            options.IncludeTests = true
            options.Quiet = true
            CompilationReferenceResolver.AddResolvedDllReferences(fullRoot, config, options)
            resolvedProjectConfigs[fullRoot] = new CachedResolvedProjectConfig(projectFileStamp, config)
            referenceVersions.Record(projectFile)
            return config
        }
    }

    static func ProjectConfigFileStamp(projectFile: string): string {
        if !File.Exists(projectFile) {
            return "missing"
        }

        info := new FileInfo(projectFile)
        return info.LastWriteTimeUtc.Ticks.ToString() + ":" + info.Length.ToString()
    }

    func ProjectSourcePathsFor(projectRoot: string, projectConfigFileStamp: string, includeTests: bool = false): HashSet<string> {
        cacheKey := projectRoot
        if includeTests {
            cacheKey = projectRoot + "\u0000tests"
        }

        cached: CachedProjectSourcePaths? = null
        if projectSourcePathCache.TryGetValue(cacheKey, out cached) && cached != null && cached.ProjectConfigFileStamp == projectConfigFileStamp {
            return cached.Paths
        }

        config := ProjectFileParser.ParseFromDirectoryOrDefault(projectRoot)
        paths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for sourcePath in config.GetSourceFiles(projectRoot, includeTests) {
            paths.Add(Path.GetFullPath(sourcePath))
        }

        projectSourcePathCache[cacheKey] = new CachedProjectSourcePaths(projectConfigFileStamp, paths)
        return paths
    }

    func buildOpenBufferSourceTextOverrides(projectRoot: string): Dictionary<string, string> {
        overrides := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)

        for openUri in editorOpenUris.Keys {
            document: DocumentState? = null
            if !documents.TryGetValue(openUri, out document) {
                continue
            }

            documentPath := EditorWorkspaceFacts.UriToFilePath(document.Uri)
            if !EditorWorkspaceFacts.IsPathUnderProject(documentPath, projectRoot) {
                continue
            }

            fullDocumentPath := Path.GetFullPath(documentPath)
            overrides[fullDocumentPath] = document.Text
        }

        return overrides
    }

    // THE SNAPSHOT CACHE KEY tracks effective source changes, while project loading still receives
    // every open buffer. That preserves the compiler's established input path and keeps excluded or
    // loose editor files in the snapshot. An unchanged buffer already in the configured source set
    // contributes no distinct input and must not churn the cache stamp on open/close.
    func buildSnapshotStampSourceTextOverrides(sourceTextOverrides: Dictionary<string, string>, projectSourcePaths: HashSet<string>): Dictionary<string, string> {
        stampOverrides := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        for entry in sourceTextOverrides {
            if projectSourcePaths.Contains(entry.Key) && !EditorWorkspaceFacts.SourceTextDiffersFromDisk(entry.Key, entry.Value) {
                continue
            }

            stampOverrides[entry.Key] = entry.Value
        }

        return stampOverrides
    }

    func logProjectSnapshotDegraded(state: EditorProjectSnapshotRefusal) {
        logger.LogWarning(
            "Project semantic snapshot degraded: {Reason}; ProjectRoot={ProjectRoot}; FilePath={FilePath}; Message={Message}",
            state.Reason,
            state.ProjectRoot,
            state.FilePath,
            state.Message
        )
    }

    func logProjectSnapshotDegradedWith(state: EditorProjectSnapshotRefusal, exception: Exception) {
        logger.LogWarning(
            exception,
            "Project semantic snapshot degraded: {Reason}; ProjectRoot={ProjectRoot}; FilePath={FilePath}; Message={Message}",
            state.Reason,
            state.ProjectRoot,
            state.FilePath,
            state.Message
        )
    }

    static func buildPublicationFromDocument(doc: DocumentState): DocumentDiagnosticsPublication {
        return new DocumentDiagnosticsPublication(
            doc.Uri,
            doc.Diagnostics ?? new List<CompilerError>(),
            doc.LinterDiagnostics ?? new List<Diagnostic>()
        )
    }

    static func toSymbolsInfo(rows: List<EditorSymbolInfoRow>): Dictionary<string, SymbolInfo> {
        symbols := new Dictionary<string, SymbolInfo>()

        for row in rows {
            symbols[row.Name] = toSymbolInfo(row)
        }

        return symbols
    }

    static func toSymbolInfo(row: EditorSymbolInfoRow): SymbolInfo {
        symbol := new SymbolInfo(row.Name, toSymbolKind(row.Kind))
        symbol.TypeName = row.TypeName
        symbol.Documentation = row.Documentation
        symbol.Modifiers = row.Modifiers

        for parameter in row.Parameters {
            symbol.Parameters.Add(new ParameterInfo(parameter.Name, parameter.TypeName ?? "", parameter.HasDefaultValue))
        }

        for member in row.Members {
            symbol.Members.Add(toSymbolInfo(member))
        }

        return symbol
    }

    static func toSymbolLocations(rows: List<EditorSymbolLocationRow>, uri: string): Dictionary<string, List<SymbolLocation>> {
        locations := new Dictionary<string, List<SymbolLocation>>(StringComparer.Ordinal)

        for row in rows {
            list: List<SymbolLocation>? = null
            if !locations.TryGetValue(row.Name, out list) {
                list = new List<SymbolLocation>()
                locations[row.Name] = list
            }

            list.Add(new SymbolLocation(row.Name, toSymbolKind(row.Kind), uri, row.Line, row.Column, row.Length))
        }

        return locations
    }

    static func toSymbolKind(kind: EditorSymbolTableKind): NSharpLang.LanguageServer.Models.SymbolKind {
        if kind == EditorSymbolTableKind.Class {
            return NSharpLang.LanguageServer.Models.SymbolKind.Class
        }
        if kind == EditorSymbolTableKind.Struct {
            return NSharpLang.LanguageServer.Models.SymbolKind.Struct
        }
        if kind == EditorSymbolTableKind.Record {
            return NSharpLang.LanguageServer.Models.SymbolKind.Record
        }
        if kind == EditorSymbolTableKind.Interface {
            return NSharpLang.LanguageServer.Models.SymbolKind.Interface
        }
        if kind == EditorSymbolTableKind.Enum {
            return NSharpLang.LanguageServer.Models.SymbolKind.Enum
        }
        if kind == EditorSymbolTableKind.Union {
            return NSharpLang.LanguageServer.Models.SymbolKind.Union
        }
        if kind == EditorSymbolTableKind.Function {
            return NSharpLang.LanguageServer.Models.SymbolKind.Function
        }
        if kind == EditorSymbolTableKind.Method {
            return NSharpLang.LanguageServer.Models.SymbolKind.Method
        }
        if kind == EditorSymbolTableKind.Property {
            return NSharpLang.LanguageServer.Models.SymbolKind.Property
        }
        if kind == EditorSymbolTableKind.Field {
            return NSharpLang.LanguageServer.Models.SymbolKind.Field
        }
        if kind == EditorSymbolTableKind.Parameter {
            return NSharpLang.LanguageServer.Models.SymbolKind.Parameter
        }
        if kind == EditorSymbolTableKind.LocalVariable {
            return NSharpLang.LanguageServer.Models.SymbolKind.LocalVariable
        }
        if kind == EditorSymbolTableKind.EnumMember {
            return NSharpLang.LanguageServer.Models.SymbolKind.EnumMember
        }

        return NSharpLang.LanguageServer.Models.SymbolKind.Constructor
    }
}

// The loaded snapshot for one URI, with the project root and file path that were computed on the
// way to it.
record ProjectSnapshotBinding(ProjectRoot: string, FilePath: string, Snapshot: ProjectSnapshot, RefreshedFilePaths: HashSet<string>) {
}

record SemanticDocumentRefresh(FilePaths: HashSet<string>, HydratedFilePaths: HashSet<string>) {
}

record CachedProjectSnapshot(Stamp: string, ProjectConfigFileStamp: string, Snapshot: ProjectSnapshot) {
}

record CachedProjectSourcePaths(ProjectConfigFileStamp: string, Paths: HashSet<string>) {
}

record CachedResolvedProjectConfig(ProjectFileStamp: string, Config: ProjectConfig) {
}

// Diagnostics payload returned by DocumentManager for publication.
record DocumentDiagnosticsPublication(Uri: string, CompilerDiagnostics: IReadOnlyList<CompilerError>, LinterDiagnostics: IReadOnlyList<Diagnostic>) {
}
