using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.LanguageServer.Models;
using SymbolKind = NSharpLang.LanguageServer.Models.SymbolKind;
using Microsoft.Extensions.Logging;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// Manages the state of all open documents and provides compilation services.
///
/// WHAT EVERY NAME IN A FILE IS AND WHERE IT SITS is N#-owned by
/// <c>EditorSymbolTableFacts</c> — the type catalog, the symbol table and the location table, one
/// walk each, with the comment-block reader and the name-column search that go with them.
///
/// WHERE A FILE BELONGS, WHEN A SNAPSHOT IS STALE AND WHICH DIAGNOSTICS BELONG TO IT are N#-owned
/// by <c>EditorWorkspaceFacts</c> — the project-root walk, the two path comparisons, the snapshot
/// stamp, the four reasons a semantic answer is refused, and the per-file diagnostic selection.
///
/// What is left here is the editor's own state: which documents are open, which roots were
/// scanned, the `file://` conversion, and the three dictionaries the owner's rows are poured into.
/// </summary>
public class DocumentManager
{
    private readonly ConcurrentDictionary<string, DocumentState> _documents = new();
    private readonly ConcurrentDictionary<string, DateTime> _lastAccessTimes = new();
    private readonly ILogger<DocumentManager> _logger;
    public Analyzer SharedAnalyzer { get; }
    private readonly CodeIntelligenceService _codeIntelligenceService = new();
    private readonly HashSet<string> _loadedProjectDirs = new();
    private readonly object _analyzerLock = new();
    private readonly object _projectSnapshotLock = new();
    private readonly ConcurrentDictionary<string, CachedProjectSnapshot> _projectSnapshots = new();
    private readonly ConcurrentDictionary<string, byte> _editorOpenUris = new();
    private readonly ConcurrentDictionary<string, byte> _workspaceRoots = new();

    public DocumentManager(ILogger<DocumentManager> logger)
    {
        _logger = logger;

        // Initialize shared analyzer ONCE with system assemblies
        SharedAnalyzer = new Analyzer();
        SharedAnalyzer.LoadSystemAssemblies();

        _logger.LogInformation("DocumentManager initialized with shared Analyzer (system assemblies loaded)");
    }

    /// <summary>
    /// Scans a workspace directory for all .nl files, loads them into the document manager,
    /// and returns the URIs of all loaded files so diagnostics can be published.
    /// </summary>
    public IReadOnlyList<string> ScanWorkspaceDirectory(string rootPath)
    {
        var loadedUris = new List<string>();

        rootPath = Path.GetFullPath(rootPath);
        _workspaceRoots.TryAdd(rootPath, 0);

        if (!Directory.Exists(rootPath))
        {
            _logger.LogWarning("Workspace root does not exist: {RootPath}", rootPath);
            return loadedUris;
        }

        IEnumerable<string> nlFiles;
        try
        {
            nlFiles = ProjectConfig.EnumerateSourceFiles(rootPath);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to enumerate .nl files in {RootPath}", rootPath);
            return loadedUris;
        }

        foreach (var filePath in nlFiles)
        {
            var uri = EditorWorkspaceFacts.FilePathToUri(filePath);

            // Skip files already open in the editor — editor content takes precedence
            if (_editorOpenUris.ContainsKey(uri))
            {
                continue;
            }

            try
            {
                var text = File.ReadAllText(filePath);
                UpdateDocument(uri, text, 0);
                loadedUris.Add(uri);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to load workspace file: {FilePath}", filePath);
            }
        }

        _logger.LogInformation("Workspace scan loaded {Count} .nl files from {RootPath}", loadedUris.Count, rootPath);
        return loadedUris;
    }

    /// <summary>
    /// Marks a document as opened in the editor. Editor-opened documents are not
    /// replaced by workspace scans and are reverted to disk content on close
    /// (instead of being removed) if the file belongs to a workspace.
    /// </summary>
    public void MarkEditorOpen(string uri)
    {
        _editorOpenUris.TryAdd(uri, 0);
    }

    /// <summary>
    /// Handles an editor-close event. If the file belongs to a scanned workspace,
    /// reloads it from disk so workspace diagnostics remain active. Otherwise,
    /// removes the document entirely.
    /// Returns the URI if the document was reloaded from disk (caller should republish
    /// diagnostics), or null if the document was fully removed.
    /// </summary>
    public string? HandleEditorClose(string uri)
    {
        _editorOpenUris.TryRemove(uri, out _);

        var filePath = EditorWorkspaceFacts.UriToFilePath(uri);
        var isInWorkspace = EditorWorkspaceFacts.ContainingWorkspaceRoot(filePath, _workspaceRoots.Keys) != null;

        if (isInWorkspace && File.Exists(filePath))
        {
            // Reload from disk so workspace diagnostics stay alive
            try
            {
                var text = File.ReadAllText(filePath);
                UpdateDocument(uri, text, 0);
                return uri;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to reload workspace file on close: {FilePath}", filePath);
            }
        }

        CloseDocument(uri);
        return null;
    }

    /// <summary>
    /// Handles a file change on disk. Re-reads the file and updates the document
    /// if it is not currently open in the editor.
    /// Returns the URI if the document was updated (caller should republish), or null.
    /// </summary>
    public string? HandleFileChangedOnDisk(string filePath)
    {
        filePath = Path.GetFullPath(filePath);
        var uri = EditorWorkspaceFacts.FilePathToUri(filePath);

        // Don't overwrite editor content
        if (_editorOpenUris.ContainsKey(uri))
        {
            return null;
        }

        if (!File.Exists(filePath))
        {
            return null;
        }

        try
        {
            var text = File.ReadAllText(filePath);
            UpdateDocument(uri, text, 0);
            return uri;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to reload changed file: {FilePath}", filePath);
            return null;
        }
    }

    /// <summary>
    /// Handles a file creation on disk. Loads the new file if it's under a workspace root.
    /// Returns the URI if the document was loaded (caller should publish), or null.
    /// </summary>
    public string? HandleFileCreatedOnDisk(string filePath)
    {
        filePath = Path.GetFullPath(filePath);

        if (EditorWorkspaceFacts.ContainingWorkspaceRoot(filePath, _workspaceRoots.Keys) == null)
        {
            return null;
        }

        return HandleFileChangedOnDisk(filePath);
    }

    /// <summary>
    /// Handles a file deletion on disk. Removes the document if it's not open in the editor.
    /// Returns the URI if the document was removed (caller should clear diagnostics), or null.
    /// </summary>
    public string? HandleFileDeletedOnDisk(string filePath)
    {
        filePath = Path.GetFullPath(filePath);
        var uri = EditorWorkspaceFacts.FilePathToUri(filePath);

        // If still open in editor, leave it alone
        if (_editorOpenUris.ContainsKey(uri))
        {
            return null;
        }

        if (_documents.ContainsKey(uri))
        {
            CloseDocument(uri);
            return uri;
        }

        return null;
    }

    /// <summary>
    /// Returns whether a URI is currently tracked by the document manager.
    /// </summary>
    public bool HasDocument(string uri) => _documents.ContainsKey(uri);

    public void UpdateDocument(string uri, string text, int version)
    {
        try
        {
            if (EditorDocumentCacheFacts.ShouldEvictBefore(_documents.Count, _documents.ContainsKey(uri)))
            {
                var cacheRows = new List<EditorDocumentCacheRow>();
                foreach (var entry in _lastAccessTimes)
                {
                    cacheRows.Add(new EditorDocumentCacheRow(entry.Key, entry.Value.Ticks));
                }

                var evicted = EditorDocumentCacheFacts.EvictionUri(cacheRows);
                if (evicted != null)
                {
                    _documents.TryRemove(evicted, out _);
                    _lastAccessTimes.TryRemove(evicted, out _);
                    _logger.LogInformation("Evicted least recently used document: {Uri}", evicted);
                }
            }

            _logger.LogInformation("Updating document: {Uri} (version {Version})", uri, version);

            var state = new DocumentState(uri, text, version);
            var filePath = EditorWorkspaceFacts.UriToFilePath(uri);
            InvalidateProjectSnapshot(filePath);

            // Parse the document using the real filesystem path so downstream
            // import resolution never sees a file:/// URI as the current file.
            var lexer = new Lexer(text, filePath);
            state.Tokens = lexer.Tokenize();
            state.Comments = lexer.Comments;

            var parseResult = NSharpLang.Compiler.Columnar.ColumnarParserRecovery.ParseFileAst(text, filePath);
            state.CompilationUnit = parseResult.CompilationUnit;

            // Start with parse errors
            var diagnostics = new List<CompilerError>(parseResult.Errors);

            // Try to find and load project configuration
            var projectDir = Path.GetDirectoryName(filePath) ?? Environment.CurrentDirectory;
            var projectConfig = ProjectFileParser.ParseFromDirectoryOrDefault(projectDir);
            var analysisProjectRoot = EditorWorkspaceFacts.AnalysisProjectRoot(projectDir);

            // Load assemblies from project configuration ONCE per project directory
            // Use lock to ensure thread-safe access to shared analyzer and loaded projects cache
            lock (_analyzerLock)
            {
                if (!_loadedProjectDirs.Contains(projectDir))
                {
                    _logger.LogInformation("Loading assemblies for new project directory: {ProjectDir}", projectDir);
                    SharedAnalyzer.LoadFromProjectConfig(projectConfig, projectDir);
                    _loadedProjectDirs.Add(projectDir);
                }
            }

            // Only run analysis if we have a valid compilation unit
            if (state.CompilationUnit != null)
            {
                // Use shared analyzer (thread-safe because Analyze doesn't mutate state)
                var analysisResult = SharedAnalyzer.Analyze(state.CompilationUnit, filePath, analysisProjectRoot, text);
                diagnostics.AddRange(analysisResult.Errors);

                // Store semantic model and binding map for IDE features
                state.SemanticModel = analysisResult.SemanticModel;
                state.Bindings = analysisResult.Bindings;

                // Run linter for additional diagnostics
                var linterConfig = LinterConfig.FromEditorConfig(projectDir);
                var linter = new Linter(linterConfig);
                state.LinterDiagnostics = linter.Lint(state.CompilationUnit, filePath, text);

                // Store symbol information for later use
                state.Symbols = EditorSymbolTableFacts.TypeCatalog(state.CompilationUnit);
                state.SymbolsInfo = ToSymbolsInfo(
                    EditorSymbolTableFacts.SymbolInfoRows(state.CompilationUnit, text));
                state.SymbolLocations = ToSymbolLocations(
                    EditorSymbolTableFacts.SymbolLocationRows(state.CompilationUnit, text), uri);
            }

            state.Diagnostics = EditorWorkspaceFacts.DeduplicateDiagnostics(diagnostics);
            _documents[uri] = state;
            _lastAccessTimes[uri] = DateTime.UtcNow;

            _logger.LogInformation("Document updated successfully with {DiagnosticCount} diagnostics ({ParseErrors} parse errors)",
                state.Diagnostics.Count, parseResult.Errors.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating document: {Uri}", uri);

            // Store document with error state
            var state = new DocumentState(uri, text, version)
            {
                Diagnostics = new List<CompilerError>
                {
                    CompilerError.Create(
                        ErrorCode.InvalidSyntax,
                        $"Internal error: {ex.Message}",
                        1,
                        1,
                        ErrorSeverity.Error
                    )
                }
            };
            _documents[uri] = state;
        }
    }

    public DocumentState? GetDocument(string uri)
    {
        if (_documents.TryGetValue(uri, out var doc))
        {
            _lastAccessTimes[uri] = DateTime.UtcNow;
            return doc;
        }
        return null;
    }

    public void CloseDocument(string uri)
    {
        InvalidateProjectSnapshot(EditorWorkspaceFacts.UriToFilePath(uri));
        _documents.TryRemove(uri, out _);
        _lastAccessTimes.TryRemove(uri, out _);
        _logger.LogInformation("Document closed: {Uri}", uri);
    }

    public DefinitionResult? FindProjectDefinition(string uri, int line0, int character0)
    {
        if (!TryGetSynchronizedProjectSnapshot(uri, out var projectRoot, out var filePath, out var snapshot))
        {
            return null;
        }

        return _codeIntelligenceService.FindDefinition(snapshot, filePath, line0 + 1, character0 + 1);
    }

    public List<ReferenceResult>? FindProjectReferences(string uri, int line0, int character0)
    {
        if (!TryGetSynchronizedProjectSnapshot(uri, out var projectRoot, out var filePath, out var snapshot))
        {
            return null;
        }

        var results = _codeIntelligenceService.FindReferences(snapshot, filePath, line0 + 1, character0 + 1);
        return results.Count > 0 ? results : null;
    }

    public HoverResult? FindProjectHover(string uri, int line0, int character0)
    {
        if (!TryGetSynchronizedProjectSnapshot(uri, out var projectRoot, out var filePath, out var snapshot))
        {
            return null;
        }

        return _codeIntelligenceService.GetHoverInfo(snapshot, filePath, line0 + 1, character0 + 1);
    }

    public List<ReferenceResult>? FindStrictProjectReferences(string uri, int line0, int character0)
    {
        if (!TryGetSynchronizedProjectSnapshot(uri, out var projectRoot, out var filePath, out var snapshot))
        {
            return null;
        }

        var results = _codeIntelligenceService.FindStrictReferences(snapshot, filePath, line0 + 1, character0 + 1);
        return results.Count > 0 ? results : null;
    }

    public bool HasSynchronizedProjectSnapshot(string uri)
    {
        return TryGetSynchronizedProjectSnapshot(uri, out _, out _, out _);
    }

    public bool HasSemanticProjectContext(string uri)
    {
        var filePath = EditorWorkspaceFacts.UriToFilePath(uri);
        var projectRoot = EditorWorkspaceFacts.SemanticProjectRoot(filePath, _workspaceRoots.Keys);
        return File.Exists(Path.Combine(projectRoot, "project.yml"))
            || EditorWorkspaceFacts.ContainingWorkspaceRoot(filePath, _workspaceRoots.Keys) != null;
    }

    public string GetProjectRootForUri(string uri)
    {
        return EditorWorkspaceFacts.SemanticProjectRoot(EditorWorkspaceFacts.UriToFilePath(uri), _workspaceRoots.Keys);
    }

    public string ResolveProjectFilePath(string projectRoot, string relativeOrAbsolutePath)
        => EditorWorkspaceFacts.ProjectFilePath(projectRoot, relativeOrAbsolutePath);

    public IReadOnlyList<SymbolLocation> FindSymbolLocations(string name)
    {
        var results = new List<SymbolLocation>();

        foreach (var doc in _documents.Values)
        {
            if (doc.SymbolLocations != null && doc.SymbolLocations.TryGetValue(name, out var locations))
            {
                results.AddRange(locations);
            }
        }

        return results;
    }

    /// <summary>
    /// Returns all documents currently tracked by the document manager.
    /// Used by workspace-wide features like workspace symbols and semantic tokens.
    /// </summary>
    public IReadOnlyCollection<DocumentState> GetAllDocuments()
    {
        return _documents.Values.ToList();
    }

    /// <summary>
    /// Returns the diagnostics that should be published for the current project scope.
    /// When the project snapshot can be synchronized with disk, this returns one entry
    /// per open document in the project so related files can be refreshed together.
    /// Otherwise, it falls back to the current document only.
    /// </summary>
    public IReadOnlyList<DocumentDiagnosticsPublication> GetDiagnosticsToPublish(string uri)
    {
        var doc = GetDocument(uri);
        if (doc == null)
        {
            return Array.Empty<DocumentDiagnosticsPublication>();
        }

        if (!TryGetSynchronizedProjectSnapshot(uri, out var projectRoot, out _, out var snapshot))
        {
            return new[]
            {
                BuildPublicationFromDocument(doc)
            };
        }

        var openDocsInProject = _documents.Values
            .Where(d => EditorWorkspaceFacts.IsPathUnderProject(EditorWorkspaceFacts.UriToFilePath(d.Uri), projectRoot))
            .OrderBy(d => d.Uri, StringComparer.Ordinal)
            .ToList();

        var publications = new List<DocumentDiagnosticsPublication>(openDocsInProject.Count);
        foreach (var openDoc in openDocsInProject)
        {
            publications.Add(new DocumentDiagnosticsPublication(
                openDoc.Uri,
                EditorWorkspaceFacts.DiagnosticsForFile(
                    snapshot.AllErrors, snapshot.ProjectRoot, EditorWorkspaceFacts.UriToFilePath(openDoc.Uri)),
                openDoc.LinterDiagnostics ?? new List<Diagnostic>()));
        }

        if (publications.Count == 0)
        {
            publications.Add(BuildPublicationFromDocument(doc));
        }

        return publications;
    }

    public bool TryGetSynchronizedProjectSnapshot(string uri, out string projectRoot, out string filePath, out ProjectSnapshot snapshot)
    {
        filePath = EditorWorkspaceFacts.UriToFilePath(uri);
        projectRoot = EditorWorkspaceFacts.SemanticProjectRoot(filePath, _workspaceRoots.Keys);
        snapshot = null!;

        var refusal = EditorWorkspaceFacts.SnapshotRefusal(filePath, projectRoot, _workspaceRoots.Keys);
        if (refusal != null)
        {
            LogProjectSnapshotDegraded(refusal);
            return false;
        }

        var sourceTextOverrides = BuildOpenBufferSourceTextOverrides(projectRoot);
        var stamp = EditorWorkspaceFacts.ProjectSnapshotStamp(projectRoot, sourceTextOverrides);
        if (stamp == null)
        {
            LogProjectSnapshotDegraded(EditorWorkspaceFacts.NoSourceFilesRefusal(projectRoot));
            return false;
        }

        lock (_projectSnapshotLock)
        {
            if (_projectSnapshots.TryGetValue(projectRoot, out var cached)
                && EditorDocumentCacheFacts.SnapshotCacheHit(cached.Stamp, stamp))
            {
                snapshot = cached.Snapshot;
                return true;
            }

            try
            {
                snapshot = _codeIntelligenceService.LoadProject(projectRoot, sourceTextOverrides);
                _projectSnapshots[projectRoot] = new CachedProjectSnapshot(stamp, snapshot);
                _logger.LogDebug(
                    "Loaded semantic project snapshot for {ProjectRoot} with {OpenBufferCount} open-buffer overrides",
                    projectRoot,
                    sourceTextOverrides.Count);
                return true;
            }
            catch (Exception ex)
            {
                LogProjectSnapshotDegraded(EditorWorkspaceFacts.LoadFailedRefusal(projectRoot, ex.Message), ex);
                return false;
            }
        }
    }

    private void InvalidateProjectSnapshot(string filePath)
    {
        foreach (var projectRoot in EditorWorkspaceFacts.PossibleSemanticProjectRoots(filePath, _workspaceRoots.Keys))
        {
            _projectSnapshots.TryRemove(projectRoot, out _);
        }
    }

    private Dictionary<string, string> BuildOpenBufferSourceTextOverrides(string projectRoot)
    {
        var overrides = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var openUri in _editorOpenUris.Keys)
        {
            if (!_documents.TryGetValue(openUri, out var document))
            {
                continue;
            }

            var documentPath = EditorWorkspaceFacts.UriToFilePath(document.Uri);
            if (!EditorWorkspaceFacts.IsPathUnderProject(documentPath, projectRoot))
            {
                continue;
            }

            overrides[Path.GetFullPath(documentPath)] = document.Text;
        }

        return overrides;
    }

    private void LogProjectSnapshotDegraded(EditorProjectSnapshotRefusal state, Exception? exception = null)
    {
        if (exception == null)
        {
            _logger.LogWarning(
                "Project semantic snapshot degraded: {Reason}; ProjectRoot={ProjectRoot}; FilePath={FilePath}; Message={Message}",
                state.Reason,
                state.ProjectRoot,
                state.FilePath,
                state.Message);
            return;
        }

        _logger.LogWarning(
            exception,
            "Project semantic snapshot degraded: {Reason}; ProjectRoot={ProjectRoot}; FilePath={FilePath}; Message={Message}",
            state.Reason,
            state.ProjectRoot,
            state.FilePath,
            state.Message);
    }

    private static DocumentDiagnosticsPublication BuildPublicationFromDocument(DocumentState doc)
    {
        return new DocumentDiagnosticsPublication(
            doc.Uri,
            doc.Diagnostics ?? new List<CompilerError>(),
            doc.LinterDiagnostics ?? new List<Diagnostic>());
    }

    private static Dictionary<string, SymbolInfo> ToSymbolsInfo(List<EditorSymbolInfoRow> rows)
    {
        var symbols = new Dictionary<string, SymbolInfo>();

        foreach (var row in rows)
        {
            symbols[row.Name] = ToSymbolInfo(row);
        }

        return symbols;
    }

    private static SymbolInfo ToSymbolInfo(EditorSymbolInfoRow row)
    {
        var symbol = new SymbolInfo(row.Name, ToSymbolKind(row.Kind))
        {
            TypeName = row.TypeName,
            Documentation = row.Documentation,
            Parameters = row.Parameters
                .Select(parameter => new ParameterInfo(parameter.Name, parameter.TypeName!, parameter.HasDefaultValue))
                .ToList(),
            Modifiers = row.Modifiers
        };

        foreach (var member in row.Members)
        {
            symbol.Members.Add(ToSymbolInfo(member));
        }

        return symbol;
    }

    private static Dictionary<string, List<SymbolLocation>> ToSymbolLocations(
        List<EditorSymbolLocationRow> rows,
        string uri)
    {
        var locations = new Dictionary<string, List<SymbolLocation>>(StringComparer.Ordinal);

        foreach (var row in rows)
        {
            if (!locations.TryGetValue(row.Name, out var list))
            {
                list = new List<SymbolLocation>();
                locations[row.Name] = list;
            }

            list.Add(new SymbolLocation(row.Name, ToSymbolKind(row.Kind), uri, row.Line, row.Column, row.Length));
        }

        return locations;
    }

    private static SymbolKind ToSymbolKind(EditorSymbolTableKind kind)
    {
        return kind switch
        {
            EditorSymbolTableKind.Class => SymbolKind.Class,
            EditorSymbolTableKind.Struct => SymbolKind.Struct,
            EditorSymbolTableKind.Record => SymbolKind.Record,
            EditorSymbolTableKind.Interface => SymbolKind.Interface,
            EditorSymbolTableKind.Enum => SymbolKind.Enum,
            EditorSymbolTableKind.Union => SymbolKind.Union,
            EditorSymbolTableKind.Function => SymbolKind.Function,
            EditorSymbolTableKind.Method => SymbolKind.Method,
            EditorSymbolTableKind.Property => SymbolKind.Property,
            EditorSymbolTableKind.Field => SymbolKind.Field,
            EditorSymbolTableKind.Parameter => SymbolKind.Parameter,
            EditorSymbolTableKind.LocalVariable => SymbolKind.LocalVariable,
            EditorSymbolTableKind.EnumMember => SymbolKind.EnumMember,
            _ => SymbolKind.Constructor
        };
    }

    private sealed record CachedProjectSnapshot(string Stamp, ProjectSnapshot Snapshot);

}

/// <summary>
/// Diagnostics payload returned by DocumentManager for publication.
/// </summary>
public sealed record DocumentDiagnosticsPublication(
    string Uri,
    IReadOnlyList<CompilerError> CompilerDiagnostics,
    IReadOnlyList<Diagnostic> LinterDiagnostics);
