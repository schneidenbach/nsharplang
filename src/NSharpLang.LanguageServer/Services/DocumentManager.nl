namespace NSharpLang.LanguageServer.Services

import System
import System.Collections.Concurrent
import System.Collections.Generic
import System.IO
import System.Linq
import Microsoft.Extensions.Logging
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
class DocumentManager {
    readonly documents: ConcurrentDictionary<string, DocumentState>
    readonly lastAccessTimes: ConcurrentDictionary<string, DateTime>
    readonly logger: ILogger<DocumentManager>
    SharedAnalyzer: Analyzer
    readonly codeIntelligenceService: CodeIntelligenceService
    readonly loadedProjectDirs: HashSet<string>
    readonly analyzerLock: object
    readonly projectSnapshotLock: object
    readonly projectSnapshots: ConcurrentDictionary<string, CachedProjectSnapshot>
    readonly editorOpenUris: ConcurrentDictionary<string, byte>
    readonly workspaceRoots: ConcurrentDictionary<string, byte>

    constructor(logger: ILogger<DocumentManager>) {
        this.logger = logger
        documents = new ConcurrentDictionary<string, DocumentState>()
        lastAccessTimes = new ConcurrentDictionary<string, DateTime>()
        codeIntelligenceService = new CodeIntelligenceService()
        loadedProjectDirs = new HashSet<string>()
        analyzerLock = new object()
        projectSnapshotLock = new object()
        projectSnapshots = new ConcurrentDictionary<string, CachedProjectSnapshot>()
        editorOpenUris = new ConcurrentDictionary<string, byte>()
        workspaceRoots = new ConcurrentDictionary<string, byte>()

        // Initialize shared analyzer ONCE with system assemblies
        SharedAnalyzer = new Analyzer()
        SharedAnalyzer.LoadSystemAssemblies()

        logger.LogInformation("DocumentManager initialized with shared Analyzer (system assemblies loaded)")
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
        editorOpenUris.TryAdd(uri, 0)
    }

    // Handles an editor-close event. If the file belongs to a scanned workspace, reloads it from
    // disk so workspace diagnostics remain active. Otherwise, removes the document entirely.
    // Returns the URI if the document was reloaded from disk (caller should republish
    // diagnostics), or null if the document was fully removed.
    func HandleEditorClose(uri: string): string? {
        removedOpenMarker: byte = 0
        editorOpenUris.TryRemove(uri, out removedOpenMarker)

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

        if documents.ContainsKey(uri) {
            CloseDocument(uri)
            return uri
        }

        return null
    }

    // Returns whether a URI is currently tracked by the document manager.
    func HasDocument(uri: string): bool => documents.ContainsKey(uri)

    func UpdateDocument(uri: string, text: string, version: int) {
        try {
            if EditorDocumentCacheFacts.ShouldEvictBefore(documents.Count, documents.ContainsKey(uri)) {
                cacheRows := new List<EditorDocumentCacheRow>()
                for entry in lastAccessTimes {
                    cacheRows.Add(new EditorDocumentCacheRow(entry.Key, entry.Value.Ticks))
                }

                evicted := EditorDocumentCacheFacts.EvictionUri(cacheRows)
                if evicted != null {
                    evictedState: DocumentState? = null
                    evictedTime: DateTime = DateTime.MinValue
                    documents.TryRemove(evicted, out evictedState)
                    lastAccessTimes.TryRemove(evicted, out evictedTime)
                    logger.LogInformation("Evicted least recently used document: {Uri}", evicted)
                }
            }

            logger.LogInformation("Updating document: {Uri} (version {Version})", uri, version)

            state := new DocumentState(uri, text, version)
            filePath := EditorWorkspaceFacts.UriToFilePath(uri)
            invalidateProjectSnapshot(filePath)

            // Parse the document using the real filesystem path so downstream
            // import resolution never sees a file:/// URI as the current file.
            lexer := new Lexer(text, filePath)
            state.Tokens = lexer.Tokenize()
            state.Comments = lexer.Comments

            parseResult := ColumnarParserRecovery.ParseFileAst(text, filePath)
            state.CompilationUnit = parseResult.CompilationUnit

            // Start with parse errors
            diagnostics := new List<CompilerError>(parseResult.Errors)

            // Try to find and load project configuration
            projectDir := Path.GetDirectoryName(filePath) ?? Environment.CurrentDirectory
            projectConfig := ProjectFileParser.ParseFromDirectoryOrDefault(projectDir)
            analysisProjectRoot := EditorWorkspaceFacts.AnalysisProjectRoot(projectDir)

            // Load assemblies from project configuration ONCE per project directory
            // Use lock to ensure thread-safe access to shared analyzer and loaded projects cache
            lock analyzerLock {
                if !loadedProjectDirs.Contains(projectDir) {
                    logger.LogInformation("Loading assemblies for new project directory: {ProjectDir}", projectDir)
                    SharedAnalyzer.LoadFromProjectConfig(projectConfig, projectDir)
                    loadedProjectDirs.Add(projectDir)
                }
            }

            // Only run analysis if we have a valid compilation unit
            unit := state.CompilationUnit
            if unit != null {
                // Use shared analyzer (thread-safe because Analyze doesn't mutate state)
                analysisResult := SharedAnalyzer.Analyze(unit, filePath, analysisProjectRoot, text)
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
            documents[uri] = state
            lastAccessTimes[uri] = DateTime.UtcNow

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
            documents[uri] = failed
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
        invalidateProjectSnapshot(EditorWorkspaceFacts.UriToFilePath(uri))
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
            fallback := new List<DocumentDiagnosticsPublication>()
            fallback.Add(buildPublicationFromDocument(doc))
            return fallback
        }

        projectRoot := binding.ProjectRoot
        snapshot := binding.Snapshot

        openDocsInProject := documents.Values.Where(d => EditorWorkspaceFacts.IsPathUnderProject(EditorWorkspaceFacts.UriToFilePath(d.Uri), projectRoot)).OrderBy(d => d.Uri, StringComparer.Ordinal).ToList()

        publications := new List<DocumentDiagnosticsPublication>(openDocsInProject.Count)
        for openDoc in openDocsInProject {
            publications.Add(new DocumentDiagnosticsPublication(
                openDoc.Uri,
                EditorWorkspaceFacts.DiagnosticsForFile(
                    snapshot.AllErrors,
                    snapshot.ProjectRoot,
                    EditorWorkspaceFacts.UriToFilePath(openDoc.Uri)
                ),
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

        sourceTextOverrides := buildOpenBufferSourceTextOverrides(projectRoot)
        stamp := EditorWorkspaceFacts.ProjectSnapshotStamp(projectRoot, sourceTextOverrides)
        if stamp == null {
            logProjectSnapshotDegraded(EditorWorkspaceFacts.NoSourceFilesRefusal(projectRoot))
            return null
        }

        lock projectSnapshotLock {
            cached: CachedProjectSnapshot? = null
            if projectSnapshots.TryGetValue(projectRoot, out cached) && EditorDocumentCacheFacts.SnapshotCacheHit(cached.Stamp, stamp) {
                return new ProjectSnapshotBinding(projectRoot, filePath, cached.Snapshot)
            }

            try {
                loaded := codeIntelligenceService.LoadProject(projectRoot, sourceTextOverrides)
                projectSnapshots[projectRoot] = new CachedProjectSnapshot(stamp, loaded)
                logger.LogDebug(
                    "Loaded semantic project snapshot for {ProjectRoot} with {OpenBufferCount} open-buffer overrides",
                    projectRoot,
                    sourceTextOverrides.Count
                )
                return new ProjectSnapshotBinding(projectRoot, filePath, loaded)
            } catch loadFailure: Exception {
                logProjectSnapshotDegradedWith(EditorWorkspaceFacts.LoadFailedRefusal(projectRoot, loadFailure.Message), loadFailure)
                return null
            }
        }
    }

    func invalidateProjectSnapshot(filePath: string) {
        for projectRoot in EditorWorkspaceFacts.PossibleSemanticProjectRoots(filePath, workspaceRoots.Keys) {
            removed: CachedProjectSnapshot? = null
            projectSnapshots.TryRemove(projectRoot, out removed)
        }
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

            overrides[Path.GetFullPath(documentPath)] = document.Text
        }

        return overrides
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
record ProjectSnapshotBinding(ProjectRoot: string, FilePath: string, Snapshot: ProjectSnapshot) {
}

record CachedProjectSnapshot(Stamp: string, Snapshot: ProjectSnapshot) {
}

// Diagnostics payload returned by DocumentManager for publication.
record DocumentDiagnosticsPublication(Uri: string, CompilerDiagnostics: IReadOnlyList<CompilerError>, LinterDiagnostics: IReadOnlyList<Diagnostic>) {
}
