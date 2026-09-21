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
/// walk each, with the comment-block reader and the name-column search that go with them. What is
/// left here is the editor's own state: which documents are open, which project they belong to,
/// when a snapshot is stale, and the three dictionaries the owner's rows are poured into.
/// </summary>
public class DocumentManager
{
    private const int MaxDocuments = 100; // Limit number of cached documents

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
            var uri = FilePathToUri(filePath);

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

        var filePath = UriToFilePath(uri);
        var isInWorkspace = _workspaceRoots.Keys.Any(root => IsPathUnderProject(filePath, root));

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
        var uri = FilePathToUri(filePath);

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

        if (!_workspaceRoots.Keys.Any(root => IsPathUnderProject(filePath, root)))
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
        var uri = FilePathToUri(filePath);

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
            // Enforce document limit to prevent unbounded growth
            if (_documents.Count >= MaxDocuments && !_documents.ContainsKey(uri))
            {
                // Evict the least recently accessed document
                var oldest = _lastAccessTimes.OrderBy(kvp => kvp.Value).FirstOrDefault();
                if (oldest.Key != null)
                {
                    _documents.TryRemove(oldest.Key, out _);
                    _lastAccessTimes.TryRemove(oldest.Key, out _);
                    _logger.LogInformation("Evicted least recently used document: {Uri}", oldest.Key);
                }
            }

            _logger.LogInformation("Updating document: {Uri} (version {Version})", uri, version);

            var state = new DocumentState(uri, text, version);
            var filePath = UriToFilePath(uri);
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
            var analysisProjectRoot = ResolveAnalysisProjectRoot(projectDir);

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

            state.Diagnostics = DeduplicateCompilerDiagnostics(diagnostics);
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
        InvalidateProjectSnapshot(UriToFilePath(uri));
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
        var filePath = UriToFilePath(uri);
        var projectRoot = ResolveSemanticProjectRoot(filePath);
        return File.Exists(Path.Combine(projectRoot, "project.yml"))
            || _workspaceRoots.Keys.Any(root => IsPathUnderProject(filePath, root));
    }

    public string GetProjectRootForUri(string uri)
    {
        return ResolveSemanticProjectRoot(UriToFilePath(uri));
    }

    public string ResolveProjectFilePath(string projectRoot, string relativeOrAbsolutePath)
    {
        if (Path.IsPathRooted(relativeOrAbsolutePath))
        {
            return relativeOrAbsolutePath;
        }

        return Path.GetFullPath(Path.Combine(projectRoot, relativeOrAbsolutePath));
    }

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
            .Where(d => IsPathUnderProject(UriToFilePath(d.Uri), projectRoot))
            .OrderBy(d => d.Uri, StringComparer.Ordinal)
            .ToList();

        var publications = new List<DocumentDiagnosticsPublication>(openDocsInProject.Count);
        foreach (var openDoc in openDocsInProject)
        {
            var openDocPath = UriToFilePath(openDoc.Uri);
            var compilerDiagnostics = GetCompilerDiagnosticsForFile(snapshot, openDocPath);
            publications.Add(new DocumentDiagnosticsPublication(
                openDoc.Uri,
                compilerDiagnostics,
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
        filePath = UriToFilePath(uri);
        projectRoot = ResolveSemanticProjectRoot(filePath);
        snapshot = null!;

        var requestedFilePath = filePath;
        var hasProjectFile = File.Exists(Path.Combine(projectRoot, "project.yml"));
        var isUnderKnownWorkspace = _workspaceRoots.Keys.Any(root => IsPathUnderProject(requestedFilePath, root));
        if (!hasProjectFile && !isUnderKnownWorkspace)
        {
            LogProjectSnapshotDegraded(new ProjectSnapshotDegradedState(
                projectRoot,
                ProjectSnapshotDegradedReason.NoProjectRoot,
                requestedFilePath,
                "Open buffer is not backed by a project.yml project or known workspace root"));
            return false;
        }

        if (!File.Exists(requestedFilePath)
            && !IsPathUnderProject(requestedFilePath, projectRoot)
            && !isUnderKnownWorkspace)
        {
            LogProjectSnapshotDegraded(new ProjectSnapshotDegradedState(
                projectRoot,
                ProjectSnapshotDegradedReason.OpenBufferOutsideProject,
                requestedFilePath,
                "Open buffer is not backed by a disk file, discovered project root, or known workspace root"));
            return false;
        }

        var sourceTextOverrides = BuildOpenBufferSourceTextOverrides(projectRoot);
        var stamp = ComputeProjectSnapshotStamp(projectRoot, sourceTextOverrides);
        if (stamp == null)
        {
            LogProjectSnapshotDegraded(new ProjectSnapshotDegradedState(
                projectRoot,
                ProjectSnapshotDegradedReason.NoSourceFiles,
                null,
                "Project has no source files or open buffers to analyze"));
            return false;
        }

        lock (_projectSnapshotLock)
        {
            if (_projectSnapshots.TryGetValue(projectRoot, out var cached) && cached.Stamp == stamp)
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
                LogProjectSnapshotDegraded(new ProjectSnapshotDegradedState(
                    projectRoot,
                    ProjectSnapshotDegradedReason.LoadFailed,
                    null,
                    ex.Message), ex);
                return false;
            }
        }
    }

    private void InvalidateProjectSnapshot(string filePath)
    {
        foreach (var projectRoot in ResolvePossibleSemanticProjectRoots(filePath))
        {
            _projectSnapshots.TryRemove(projectRoot, out _);
        }
    }

    private static string FindProjectRoot(string filePath)
    {
        var directory = Directory.Exists(filePath)
            ? filePath
            : Path.GetDirectoryName(filePath) ?? Environment.CurrentDirectory;

        var current = new DirectoryInfo(directory);
        while (current != null)
        {
            if (File.Exists(Path.Combine(current.FullName, "project.yml")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        return Path.GetFullPath(directory);
    }

    private static string? ResolveAnalysisProjectRoot(string projectDir)
    {
        var fullProjectDir = Path.GetFullPath(projectDir);
        if (File.Exists(Path.Combine(fullProjectDir, "project.yml")))
        {
            return fullProjectDir;
        }

        return IsFilesystemRoot(fullProjectDir) ? null : fullProjectDir;
    }

    private static bool IsFilesystemRoot(string directory)
    {
        var fullPath = Path.GetFullPath(directory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var rootPath = (Path.GetPathRoot(directory) ?? string.Empty)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

        return string.Equals(fullPath, rootPath, StringComparison.OrdinalIgnoreCase);
    }

    private string ResolveSemanticProjectRoot(string filePath)
    {
        var discoveredRoot = FindProjectRoot(filePath);
        if (File.Exists(Path.Combine(discoveredRoot, "project.yml")))
        {
            return discoveredRoot;
        }

        return FindContainingWorkspaceRoot(filePath) ?? discoveredRoot;
    }

    private IEnumerable<string> ResolvePossibleSemanticProjectRoots(string filePath)
    {
        var roots = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            FindProjectRoot(filePath)
        };

        var workspaceRoot = FindContainingWorkspaceRoot(filePath);
        if (workspaceRoot != null)
        {
            roots.Add(workspaceRoot);
        }

        return roots;
    }

    private string? FindContainingWorkspaceRoot(string filePath)
    {
        return _workspaceRoots.Keys
            .Where(root => IsPathUnderProject(filePath, root))
            .OrderByDescending(root => Path.GetFullPath(root).Length)
            .FirstOrDefault();
    }

    private static bool IsPathUnderProject(string filePath, string projectRoot)
    {
        var fullFilePath = Path.GetFullPath(filePath);
        var fullProjectRoot = Path.GetFullPath(projectRoot)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;

        return fullFilePath.StartsWith(fullProjectRoot, StringComparison.Ordinal);
    }

    private static bool PathsMatch(string left, string right)
    {
        try
        {
            var normalizedLeft = NormalizePath(Path.GetFullPath(left));
            var normalizedRight = NormalizePath(Path.GetFullPath(right));
            return string.Equals(normalizedLeft, normalizedRight, StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return string.Equals(NormalizePath(left), NormalizePath(right), StringComparison.OrdinalIgnoreCase);
        }
    }

    private static string NormalizePath(string path)
    {
        return path.Replace('\\', '/');
    }

    private string? ComputeProjectSnapshotStamp(string projectRoot, IReadOnlyDictionary<string, string> sourceTextOverrides)
    {
        var diskStamp = ComputeProjectSnapshotStamp(projectRoot);
        var hash = new HashCode();
        hash.Add(diskStamp);

        foreach (var (path, text) in sourceTextOverrides.OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase))
        {
            hash.Add(Path.GetFullPath(path), StringComparer.OrdinalIgnoreCase);
            hash.Add(text, StringComparer.Ordinal);
        }

        if (diskStamp == 0 && sourceTextOverrides.Count == 0)
        {
            return null;
        }

        return $"{diskStamp}:{sourceTextOverrides.Count}:{hash.ToHashCode()}";
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

            var documentPath = UriToFilePath(document.Uri);
            if (!IsPathUnderProject(documentPath, projectRoot))
            {
                continue;
            }

            overrides[Path.GetFullPath(documentPath)] = document.Text;
        }

        return overrides;
    }

    private void LogProjectSnapshotDegraded(ProjectSnapshotDegradedState state, Exception? exception = null)
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

    private static long ComputeProjectSnapshotStamp(string projectRoot)
    {
        long latest = 0;

        foreach (var file in ProjectConfig.EnumerateSourceFiles(projectRoot))
        {
            latest = Math.Max(latest, File.GetLastWriteTimeUtc(file).Ticks);
        }

        var projectFile = Path.Combine(projectRoot, "project.yml");
        if (File.Exists(projectFile))
        {
            latest = Math.Max(latest, File.GetLastWriteTimeUtc(projectFile).Ticks);
        }

        return latest;
    }

    private IReadOnlyList<CompilerError> GetCompilerDiagnosticsForFile(ProjectSnapshot snapshot, string filePath)
    {
        var results = new List<CompilerError>();

        foreach (var error in snapshot.AllErrors)
        {
            if (string.IsNullOrWhiteSpace(error.FileName))
            {
                continue;
            }

            var errorFilePath = ResolveProjectFilePath(snapshot.ProjectRoot, error.FileName);
            if (PathsMatch(errorFilePath, filePath))
            {
                results.Add(error);
            }
        }

        return DeduplicateCompilerDiagnostics(results);
    }

    private static List<CompilerError> DeduplicateCompilerDiagnostics(IEnumerable<CompilerError> diagnostics)
    {
        return diagnostics
            .GroupBy(diagnostic => new
            {
                diagnostic.Code,
                diagnostic.FileName,
                diagnostic.Line,
                diagnostic.Column,
                diagnostic.Message
            })
            .Select(group => group.First())
            .ToList();
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

    private string UriToFilePath(string uri)
    {
        // Convert file:// URI to local file path
        if (uri.StartsWith("file://"))
        {
            var path = uri.Substring(7); // Remove "file://"

            // On Windows, remove the leading slash from paths like /C:/...
            if (Path.DirectorySeparatorChar == '\\' && path.Length > 2 && path[0] == '/' && path[2] == ':')
            {
                path = path.Substring(1);
            }

            return Uri.UnescapeDataString(path);
        }

        return uri;
    }

    private static string FilePathToUri(string filePath)
    {
        var fullPath = Path.GetFullPath(filePath);
        return new Uri(fullPath).ToString();
    }

    private sealed record CachedProjectSnapshot(string Stamp, ProjectSnapshot Snapshot);

    private enum ProjectSnapshotDegradedReason
    {
        NoSourceFiles,
        NoProjectRoot,
        OpenBufferOutsideProject,
        LoadFailed
    }

    private sealed record ProjectSnapshotDegradedState(
        string ProjectRoot,
        ProjectSnapshotDegradedReason Reason,
        string? FilePath,
        string Message);
}

/// <summary>
/// Diagnostics payload returned by DocumentManager for publication.
/// </summary>
public sealed record DocumentDiagnosticsPublication(
    string Uri,
    IReadOnlyList<CompilerError> CompilerDiagnostics,
    IReadOnlyList<Diagnostic> LinterDiagnostics);
