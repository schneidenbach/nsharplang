using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Models;
using SymbolKind = NSharpLang.LanguageServer.Models.SymbolKind;
using Microsoft.Extensions.Logging;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// Manages the state of all open documents and provides compilation services
/// </summary>
public class DocumentManager
{
    private const int MaxDocuments = 100; // Limit number of cached documents

    private readonly ConcurrentDictionary<string, DocumentState> _documents = new();
    private readonly ConcurrentDictionary<string, DateTime> _lastAccessTimes = new();
    private readonly ILogger<DocumentManager> _logger;
    private readonly Analyzer _sharedAnalyzer;
    private readonly CodeIntelligenceService _codeIntelligenceService = new();
    private readonly HashSet<string> _loadedProjectDirs = new();
    private readonly object _analyzerLock = new();
    private readonly object _projectSnapshotLock = new();
    private readonly ConcurrentDictionary<string, CachedProjectSnapshot> _projectSnapshots = new();
    private readonly ConcurrentDictionary<string, CachedProjectSnapshot> _diskProjectSnapshots = new();
    private readonly ConcurrentDictionary<string, Dictionary<string, List<ProjectSymbolInfo>>> _projectSymbolTables = new();
    private readonly ConcurrentDictionary<string, byte> _editorOpenUris = new();
    private readonly ConcurrentDictionary<string, byte> _workspaceRoots = new();

    public DocumentManager(ILogger<DocumentManager> logger)
    {
        _logger = logger;

        // Initialize shared analyzer ONCE with system assemblies
        _sharedAnalyzer = new Analyzer();
        _sharedAnalyzer.LoadSystemAssemblies();

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

    public bool IsDocumentSynchronizedWithDisk(string uri)
    {
        if (!_documents.TryGetValue(uri, out var document))
        {
            return true;
        }

        var filePath = UriToFilePath(uri);
        if (!File.Exists(filePath))
        {
            return false;
        }

        try
        {
            return string.Equals(document.Text, File.ReadAllText(filePath), StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

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

            var parser = new Parser(state.Tokens, filePath, text);  // Pass source code for error snippets
            var parseResult = parser.ParseCompilationUnit();
            state.CompilationUnit = parseResult.CompilationUnit;

            // Start with parse errors
            var diagnostics = new List<CompilerError>(parseResult.Errors);

            // Try to find and load project configuration
            var projectDir = Path.GetDirectoryName(filePath) ?? Environment.CurrentDirectory;
            var projectConfig = ProjectFileParser.ParseFromDirectory(projectDir);

            // Load assemblies from project configuration ONCE per project directory
            // Use lock to ensure thread-safe access to shared analyzer and loaded projects cache
            lock (_analyzerLock)
            {
                if (!_loadedProjectDirs.Contains(projectDir))
                {
                    _logger.LogInformation("Loading assemblies for new project directory: {ProjectDir}", projectDir);
                    _sharedAnalyzer.LoadFromProjectConfig(projectConfig, projectDir);
                    _loadedProjectDirs.Add(projectDir);
                }
            }

            // Only run analysis if we have a valid compilation unit
            if (state.CompilationUnit != null)
            {
                // Set project symbols for Go-style cross-file resolution.
                // This allows single-file analysis to resolve types from other files
                // in the same project without explicit import statements.
                var projectRoot = FindProjectRoot(filePath);
                var projectSymbols = GetOrBuildProjectSymbolTable(projectRoot);
                lock (_analyzerLock)
                {
                    _sharedAnalyzer.SetProjectSymbols(projectSymbols);
                }

                // Use shared analyzer (thread-safe because Analyze doesn't mutate state)
                var analysisResult = _sharedAnalyzer.Analyze(state.CompilationUnit, filePath, projectDir, text);
                diagnostics.AddRange(analysisResult.Errors);

                // Store semantic model and binding map for IDE features
                state.SemanticModel = analysisResult.SemanticModel;
                state.Bindings = analysisResult.Bindings;

                // Run linter for additional diagnostics
                var linterConfig = LinterConfig.FromEditorConfig(projectDir);
                var linter = new Linter(linterConfig);
                state.LinterDiagnostics = linter.Lint(state.CompilationUnit, filePath);

                // Store symbol information for later use
                state.Symbols = ExtractSymbols(state.CompilationUnit);
                state.SymbolsInfo = ExtractSymbolsInfo(state.CompilationUnit, text);
                state.SymbolLocations = ExtractSymbolLocations(state.CompilationUnit, uri, text);
            }

            state.Diagnostics = diagnostics;
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

    public List<ReferenceResult>? FindStrictDocumentReferences(string uri, int line0, int character0)
    {
        var doc = GetDocument(uri);
        if (doc?.Bindings == null || doc.Text == null)
        {
            return null;
        }

        var span = TryGetIdentifierSpanAtPosition(doc.Text, line0, character0);
        if (span == null)
        {
            return null;
        }

        var filePath = UriToFilePath(uri);
        var line = line0 + 1;
        var declaration = doc.Bindings.GetBindingAt(filePath, line, span.Value.StartColumn)
            ?? doc.Bindings.FindDeclarationsByName(span.Value.Name).FirstOrDefault(candidate =>
                string.Equals(candidate.File, filePath, StringComparison.Ordinal)
                && candidate.Line == line
                && candidate.Column == span.Value.StartColumn);

        if (declaration == null
            || !string.Equals(declaration.File, filePath, StringComparison.Ordinal))
        {
            return null;
        }

        var results = new List<ReferenceResult>
        {
            new(
                filePath,
                declaration.Line,
                declaration.Column,
                declaration.Name.Length,
                GetSourceContext(doc.Text, declaration.Line),
                IsDefinition: true)
        };

        foreach (var usage in doc.Bindings.GetReferences(declaration))
        {
            var isDefinition = usage.File == declaration.File
                && usage.Line == declaration.Line
                && usage.Column == declaration.Column;
            var overlapsDefinitionName = usage.File == declaration.File
                && usage.Line == declaration.Line
                && usage.Column >= declaration.Column
                && usage.Column < declaration.Column + declaration.Name.Length;

            if (isDefinition || overlapsDefinitionName)
            {
                continue;
            }

            if (!string.Equals(usage.File, filePath, StringComparison.Ordinal))
            {
                continue;
            }

            results.Add(new ReferenceResult(
                filePath,
                usage.Line,
                usage.Column,
                usage.Length,
                GetSourceContext(doc.Text, usage.Line),
                IsDefinition: false));
        }

        return results
            .GroupBy(r => (r.File, r.Line, r.Column))
            .Select(g => g.First())
            .OrderBy(r => r.Line)
            .ThenBy(r => r.Column)
            .ToList();
    }

    public int CountDocumentDeclarations(string uri, string name)
    {
        var doc = GetDocument(uri);
        if (doc?.Bindings != null)
        {
            var filePath = UriToFilePath(uri);
            return doc.Bindings.FindDeclarationsByName(name)
                .Count(declaration => string.Equals(declaration.File, filePath, StringComparison.Ordinal));
        }

        return doc?.SymbolLocations?.TryGetValue(name, out var locations) == true
            ? locations.Count
            : 0;
    }

    private static (int StartColumn, int EndColumn, string Name)? TryGetIdentifierSpanAtPosition(string text, int line0, int character0)
    {
        var lines = text.Split('\n');
        if (line0 < 0 || line0 >= lines.Length)
        {
            return null;
        }

        var lineText = lines[line0].TrimEnd('\r');
        if (lineText.Length == 0)
        {
            return null;
        }

        var index = Math.Clamp(character0, 0, lineText.Length - 1);
        if (!EditorUtilities.IsIdentifierChar(lineText[index]))
        {
            if (character0 > 0
                && character0 <= lineText.Length
                && !EditorUtilities.IsIdentifierChar(lineText[Math.Min(character0, lineText.Length - 1)])
                && EditorUtilities.IsIdentifierChar(lineText[character0 - 1]))
            {
                index = character0 - 1;
            }
            else
            {
                return null;
            }
        }

        var start = index;
        while (start > 0 && EditorUtilities.IsIdentifierChar(lineText[start - 1]))
        {
            start--;
        }

        var end = index;
        while (end + 1 < lineText.Length && EditorUtilities.IsIdentifierChar(lineText[end + 1]))
        {
            end++;
        }

        return (start + 1, end + 1, lineText.Substring(start, end - start + 1));
    }

    private static string GetSourceContext(string source, int line)
    {
        var lines = source.Split('\n');
        return line > 0 && line <= lines.Length
            ? lines[line - 1].TrimEnd('\r')
            : string.Empty;
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

    /// <summary>
    /// Finds definition using the disk-based project snapshot, bypassing the sync check.
    /// Used as a fallback when open buffers differ from disk but cross-file semantic
    /// definition resolution is still desired.
    /// </summary>
    public DefinitionResult? FindProjectDefinitionFromDisk(string uri, int line0, int character0)
    {
        if (!TryGetProjectSnapshotFromDisk(uri, out var projectRoot, out var filePath, out var snapshot))
        {
            return null;
        }

        return _codeIntelligenceService.FindDefinition(snapshot, filePath, line0 + 1, character0 + 1);
    }

    public string GetProjectRootForUri(string uri)
    {
        return ResolveSemanticProjectRoot(UriToFilePath(uri));
    }

    public bool HasUnsavedOpenBuffersInProject(string uri)
    {
        var projectRoot = ResolveSemanticProjectRoot(UriToFilePath(uri));
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

            if (!IsDocumentSynchronizedWithDisk(document.Uri))
            {
                return true;
            }
        }

        return false;
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

    /// <summary>
    /// Find all references to a symbol name in a document's source text.
    /// Returns 0-based line/column positions of each whole-word occurrence
    /// that is a valid identifier (not inside a string literal or comment).
    /// </summary>
    public List<(int Line, int Column, int Length)> FindAllReferences(string uri, string symbolName)
    {
        var results = new List<(int Line, int Column, int Length)>();
        var doc = GetDocument(uri);
        if (doc?.Text == null || string.IsNullOrEmpty(symbolName)) return results;

        // NOTE: BindingMap is stored for future use by handlers that need semantic resolution.
        // For FindAllReferences in the LSP context, we continue using the battle-tested text search
        // because the BindingMap doesn't yet cover all expression paths (interpolation, etc.).
        // The CLI's CodeIntelligenceService.FindReferences() uses BindingMap directly.

        // Text-based search
        var lines = doc.Text.Split('\n');
        for (int lineIdx = 0; lineIdx < lines.Length; lineIdx++)
        {
            var line = lines[lineIdx];
            int searchStart = 0;
            while (searchStart < line.Length)
            {
                int idx = line.IndexOf(symbolName, searchStart, StringComparison.Ordinal);
                if (idx < 0) break;

                // Check whole-word boundary
                bool leftBound = idx == 0 || !IsIdentChar(line[idx - 1]);
                bool rightBound = idx + symbolName.Length >= line.Length || !IsIdentChar(line[idx + symbolName.Length]);

                if (leftBound && rightBound && !IsInsideStringOrComment(line, idx))
                {
                    results.Add((lineIdx, idx, symbolName.Length));
                }

                searchStart = idx + 1;
            }
        }

        return results;
    }

    private static bool IsIdentChar(char c) => char.IsLetterOrDigit(c) || c == '_';

    private static bool IsInsideStringOrComment(string line, int position)
    {
        // Track string/comment/interpolation state up to `position`.
        // Inside an interpolated string, content between { } is CODE, not string.
        bool inString = false;
        bool isInterpolated = false;
        int interpolationDepth = 0; // nesting depth of { } inside interpolated string
        for (int i = 0; i < position && i < line.Length; i++)
        {
            var c = line[i];
            if (inString && isInterpolated && interpolationDepth > 0)
            {
                // Inside an interpolation expression — treat as code
                if (c == '{') interpolationDepth++;
                else if (c == '}') interpolationDepth--;
                // Don't check for string end while inside interpolation
            }
            else if (inString)
            {
                if (c == '\\') { i++; continue; } // skip escaped char
                if (c == '"') inString = false;
                else if (isInterpolated && c == '{')
                {
                    // Check for {{ (escaped brace, stays in string)
                    if (i + 1 < line.Length && line[i + 1] == '{') { i++; continue; }
                    interpolationDepth = 1; // entering interpolation expression
                }
            }
            else
            {
                if (c == '$' && i + 1 < line.Length && line[i + 1] == '"')
                {
                    inString = true;
                    isInterpolated = true;
                    interpolationDepth = 0;
                    i++; // skip the '"'
                }
                else if (c == '"') { inString = true; isInterpolated = false; interpolationDepth = 0; }
                else if (c == '\'') { inString = true; isInterpolated = false; interpolationDepth = 0; }
                else if (c == '/' && i + 1 < line.Length && line[i + 1] == '/') return true; // line comment
            }
        }
        // If we're in a string but inside an interpolation expression, it's code
        if (inString && isInterpolated && interpolationDepth > 0) return false;
        return inString;
    }

    private bool TryGetSynchronizedProjectSnapshot(string uri, out string projectRoot, out string filePath, out ProjectSnapshot snapshot)
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

    /// <summary>
    /// Loads a project snapshot from disk without requiring open buffers to match disk.
    /// Uses a separate cache that is not invalidated by editor keystrokes.
    /// </summary>
    private bool TryGetProjectSnapshotFromDisk(string uri, out string projectRoot, out string filePath, out ProjectSnapshot snapshot)
    {
        filePath = UriToFilePath(uri);
        projectRoot = ResolveSemanticProjectRoot(filePath);
        snapshot = null!;

        if (!File.Exists(filePath))
        {
            return false;
        }

        var stamp = ComputeProjectSnapshotStamp(projectRoot).ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (stamp == "0")
        {
            return false;
        }

        lock (_projectSnapshotLock)
        {
            if (_diskProjectSnapshots.TryGetValue(projectRoot, out var cached) && cached.Stamp == stamp)
            {
                snapshot = cached.Snapshot;
                return true;
            }

            try
            {
                snapshot = _codeIntelligenceService.LoadProject(projectRoot);
                _diskProjectSnapshots[projectRoot] = new CachedProjectSnapshot(stamp, snapshot);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to load disk-based project snapshot for {ProjectRoot}", projectRoot);
                return false;
            }
        }
    }

    private void InvalidateProjectSnapshot(string filePath)
    {
        foreach (var projectRoot in ResolvePossibleSemanticProjectRoots(filePath))
        {
            _projectSnapshots.TryRemove(projectRoot, out _);
            _projectSymbolTables.TryRemove(projectRoot, out _);
        }
    }

    /// <summary>
    /// Builds a project-wide symbol table from all parsed documents in the project.
    /// This enables Go-style cross-file symbol resolution: all PascalCase declarations
    /// are visible across files in the same project without explicit imports.
    /// </summary>
    private Dictionary<string, List<ProjectSymbolInfo>> GetOrBuildProjectSymbolTable(string projectRoot)
    {
        if (_projectSymbolTables.TryGetValue(projectRoot, out var cached))
            return cached;

        var table = new Dictionary<string, List<ProjectSymbolInfo>>();

        foreach (var doc in _documents.Values)
        {
            if (doc.CompilationUnit == null)
                continue;

            var docPath = UriToFilePath(doc.Uri);
            if (!IsPathUnderProject(docPath, projectRoot))
                continue;

            var symbols = Analyzer.ExtractProjectSymbols(doc.CompilationUnit, docPath);
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

        _projectSymbolTables[projectRoot] = table;
        _logger.LogDebug("Built project symbol table for {ProjectRoot}: {Count} symbols", projectRoot, table.Count);
        return table;
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

        return results;
    }

    private static DocumentDiagnosticsPublication BuildPublicationFromDocument(DocumentState doc)
    {
        return new DocumentDiagnosticsPublication(
            doc.Uri,
            doc.Diagnostics ?? new List<CompilerError>(),
            doc.LinterDiagnostics ?? new List<Diagnostic>());
    }

    private Dictionary<string, TypeInfo> ExtractSymbols(CompilationUnit compilationUnit)
    {
        var symbols = new Dictionary<string, TypeInfo>();

        // Extract class, struct, record, interface, enum, union declarations
        foreach (var decl in compilationUnit.Declarations)
        {
            if (decl is ClassDeclaration classDecl)
            {
                symbols[classDecl.Name] = new ClassTypeInfo(classDecl);
            }
            else if (decl is StructDeclaration structDecl)
            {
                symbols[structDecl.Name] = new StructTypeInfo(structDecl);
            }
            else if (decl is RecordDeclaration recordDecl)
            {
                symbols[recordDecl.Name] = new RecordTypeInfo(recordDecl);
            }
            else if (decl is InterfaceDeclaration interfaceDecl)
            {
                symbols[interfaceDecl.Name] = new InterfaceTypeInfo(interfaceDecl);
            }
            else if (decl is EnumDeclaration enumDecl)
            {
                symbols[enumDecl.Name] = new EnumTypeInfo(enumDecl);
            }
            else if (decl is UnionDeclaration unionDecl)
            {
                symbols[unionDecl.Name] = new UnionTypeInfo(unionDecl);
            }
        }

        return symbols;
    }

    private Dictionary<string, SymbolInfo> ExtractSymbolsInfo(CompilationUnit compilationUnit, string text)
    {
        var symbols = new Dictionary<string, SymbolInfo>();

        // Extract top-level function declarations
        foreach (var decl in compilationUnit.Declarations)
        {
            if (decl is FunctionDeclaration funcDecl)
            {
                symbols[funcDecl.Name] = CreateFunctionSymbol(funcDecl, SymbolKind.Function, text);
                ExtractLocalFunctionSymbols(symbols, funcDecl.Body, text);
            }
            else if (decl is ClassDeclaration classDecl)
            {
                symbols[classDecl.Name] = CreateTypeSymbol(classDecl, text);
            }
            else if (decl is StructDeclaration structDecl)
            {
                symbols[structDecl.Name] = CreateTypeSymbol(structDecl, text);
            }
            else if (decl is RecordDeclaration recordDecl)
            {
                symbols[recordDecl.Name] = CreateTypeSymbol(recordDecl, text);
            }
            else if (decl is InterfaceDeclaration interfaceDecl)
            {
                symbols[interfaceDecl.Name] = CreateTypeSymbol(interfaceDecl, text);
            }
            else if (decl is EnumDeclaration enumDecl)
            {
                symbols[enumDecl.Name] = CreateEnumSymbol(enumDecl, text);
            }
            else if (decl is UnionDeclaration unionDecl)
            {
                symbols[unionDecl.Name] = CreateUnionSymbol(unionDecl, text);
            }
        }

        return symbols;
    }

    private Dictionary<string, List<SymbolLocation>> ExtractSymbolLocations(CompilationUnit compilationUnit, string uri, string text)
    {
        var lines = text.Split('\n');
        var locations = new Dictionary<string, List<SymbolLocation>>(System.StringComparer.Ordinal);

        void AddLocation(string name, SymbolKind kind, int line1Based, int column1Based, int? forcedNameColumn0 = null)
        {
            if (string.IsNullOrWhiteSpace(name)) return;

            var line0 = Math.Max(0, line1Based - 1);
            var column0 = Math.Max(0, column1Based - 1);
            var nameColumn0 = forcedNameColumn0 ?? FindNameColumn(lines, line0, column0, name);

            if (!locations.TryGetValue(name, out var list))
            {
                list = new List<SymbolLocation>();
                locations[name] = list;
            }

            list.Add(new SymbolLocation(
                name,
                kind,
                uri,
                line0,
                nameColumn0,
                name.Length
            ));
        }

        void VisitDeclaration(Declaration decl)
        {
            switch (decl)
            {
                case FunctionDeclaration funcDecl:
                    AddLocation(funcDecl.Name, SymbolKind.Function, funcDecl.Line, funcDecl.Column);
                    // Track parameters for go-to-definition
                    // Parameters don't have their own line/column, so search for them on the function's line
                    {
                        var funcLine0 = Math.Max(0, funcDecl.Line - 1);
                        var searchFrom = Math.Max(0, funcDecl.Column - 1);
                        foreach (var param in funcDecl.Parameters)
                        {
                            var col = FindNameColumn(lines, funcLine0, searchFrom, param.Name);
                            AddLocation(param.Name, SymbolKind.Parameter, funcDecl.Line, funcDecl.Column, forcedNameColumn0: col);
                            searchFrom = Math.Min(lines.ElementAtOrDefault(funcLine0)?.Length ?? 0, col + param.Name.Length);
                        }
                    }
                    VisitBlock(funcDecl.Body);
                    break;

                case ClassDeclaration classDecl:
                    AddLocation(classDecl.Name, SymbolKind.Class, classDecl.Line, classDecl.Column);
                    foreach (var member in classDecl.Members) VisitDeclaration(member);
                    break;

                case StructDeclaration structDecl:
                    AddLocation(structDecl.Name, SymbolKind.Struct, structDecl.Line, structDecl.Column);
                    foreach (var member in structDecl.Members) VisitDeclaration(member);
                    break;

                case RecordDeclaration recordDecl:
                    AddLocation(recordDecl.Name, SymbolKind.Record, recordDecl.Line, recordDecl.Column);
                    foreach (var member in recordDecl.Members) VisitDeclaration(member);
                    break;

                case InterfaceDeclaration interfaceDecl:
                    AddLocation(interfaceDecl.Name, SymbolKind.Interface, interfaceDecl.Line, interfaceDecl.Column);
                    foreach (var member in interfaceDecl.Members) VisitDeclaration(member);
                    break;

                case EnumDeclaration enumDecl:
                    AddLocation(enumDecl.Name, SymbolKind.Enum, enumDecl.Line, enumDecl.Column);
                    break;

                case UnionDeclaration unionDecl:
                    AddLocation(unionDecl.Name, SymbolKind.Union, unionDecl.Line, unionDecl.Column);
                    break;

                case TypeAliasDeclaration typeAliasDecl:
                    AddLocation(typeAliasDecl.Name, SymbolKind.Class, typeAliasDecl.Line, typeAliasDecl.Column);
                    break;

                case PropertyDeclaration propDecl:
                    AddLocation(propDecl.Name, SymbolKind.Property, propDecl.Line, propDecl.Column);
                    break;

                case FieldDeclaration fieldDecl:
                    AddLocation(fieldDecl.Name, SymbolKind.Field, fieldDecl.Line, fieldDecl.Column);
                    break;
            }
        }

        void VisitStatement(Statement stmt)
        {
            switch (stmt)
            {
                case BlockStatement block:
                    VisitBlock(block);
                    break;

                case VariableDeclarationStatement varDecl:
                    AddLocation(varDecl.Name, SymbolKind.LocalVariable, varDecl.Line, varDecl.Column, forcedNameColumn0: Math.Max(0, varDecl.Column - 1));
                    break;

                case TupleDeconstructionStatement tupleDecl:
                {
                    var line0 = Math.Max(0, tupleDecl.Line - 1);
                    var searchFrom = Math.Max(0, tupleDecl.Column - 1);

                    foreach (var name in tupleDecl.Names)
                    {
                        if (name == "_") continue;

                        var col = FindNameColumn(lines, line0, searchFrom, name);
                        AddLocation(name, SymbolKind.LocalVariable, tupleDecl.Line, tupleDecl.Column, forcedNameColumn0: col);
                        searchFrom = Math.Min(lines.ElementAtOrDefault(line0)?.Length ?? 0, col + name.Length);
                    }

                    break;
                }

                case ForeachStatement foreachStmt:
                {
                    var line0 = Math.Max(0, foreachStmt.Line - 1);
                    var col = FindNameColumn(lines, line0, Math.Max(0, foreachStmt.Column - 1), foreachStmt.VariableName);
                    AddLocation(foreachStmt.VariableName, SymbolKind.LocalVariable, foreachStmt.Line, foreachStmt.Column, forcedNameColumn0: col);
                    VisitStatement(foreachStmt.Body);
                    break;
                }

                case AwaitForEachStatement awaitForeachStmt:
                {
                    var line0 = Math.Max(0, awaitForeachStmt.Line - 1);
                    var col = FindNameColumn(lines, line0, Math.Max(0, awaitForeachStmt.Column - 1), awaitForeachStmt.VariableName);
                    AddLocation(awaitForeachStmt.VariableName, SymbolKind.LocalVariable, awaitForeachStmt.Line, awaitForeachStmt.Column, forcedNameColumn0: col);
                    VisitStatement(awaitForeachStmt.Body);
                    break;
                }

                case LocalFunctionStatement localFunc:
                    AddLocation(localFunc.Function.Name, SymbolKind.Function, localFunc.Function.Line, localFunc.Function.Column);
                    VisitBlock(localFunc.Function.Body);
                    break;

                case IfStatement ifStmt:
                    VisitStatement(ifStmt.ThenStatement);
                    if (ifStmt.ElseStatement != null) VisitStatement(ifStmt.ElseStatement);
                    break;

                case ForStatement forStmt:
                    if (forStmt.Initializer != null) VisitStatement(forStmt.Initializer);
                    VisitStatement(forStmt.Body);
                    break;

                case WhileStatement whileStmt:
                    VisitStatement(whileStmt.Body);
                    break;

                case TryStatement tryStmt:
                    VisitBlock(tryStmt.TryBlock);
                    foreach (var catchClause in tryStmt.CatchClauses)
                    {
                        // Track catch variable for go-to-definition
                        // CatchClause doesn't have Line/Column, use the block's position
                        if (!string.IsNullOrEmpty(catchClause.VariableName) && catchClause.Block.Line > 0)
                        {
                            var catchLine0 = Math.Max(0, catchClause.Block.Line - 1);
                            // Search backwards from block start to find the variable name
                            var col = FindNameColumn(lines, catchLine0 > 0 ? catchLine0 - 1 : catchLine0, 0, catchClause.VariableName);
                            AddLocation(catchClause.VariableName, SymbolKind.LocalVariable,
                                catchLine0 > 0 ? catchLine0 : catchClause.Block.Line,
                                catchClause.Block.Column, forcedNameColumn0: col);
                        }
                        VisitBlock(catchClause.Block);
                    }
                    if (tryStmt.FinallyBlock != null) VisitBlock(tryStmt.FinallyBlock);
                    break;

                case UsingStatement usingStmt:
                    if (usingStmt.Declaration != null) VisitStatement(usingStmt.Declaration);
                    if (usingStmt.Body != null) VisitStatement(usingStmt.Body);
                    break;

                case LockStatement lockStmt:
                    VisitBlock(lockStmt.Body);
                    break;

                case SwitchStatement switchStmt:
                    foreach (var switchCase in switchStmt.Cases)
                    foreach (var caseStmt in switchCase.Statements)
                        VisitStatement(caseStmt);
                    break;
            }
        }

        void VisitBlock(BlockStatement? block)
        {
            if (block == null) return;
            foreach (var stmt in block.Statements) VisitStatement(stmt);
        }

        foreach (var decl in compilationUnit.Declarations)
        {
            VisitDeclaration(decl);
        }

        return locations;
    }

    private static int FindNameColumn(string[] lines, int line0, int startColumn0, string name)
    {
        if (line0 < 0 || line0 >= lines.Length) return Math.Max(0, startColumn0);

        var lineText = lines[line0];
        if (string.IsNullOrEmpty(lineText)) return Math.Max(0, startColumn0);

        var start = Math.Clamp(startColumn0, 0, lineText.Length);
        var index = lineText.IndexOf(name, start, StringComparison.Ordinal);
        if (index < 0 && start > 0)
        {
            index = lineText.IndexOf(name, StringComparison.Ordinal);
        }

        return index >= 0 ? index : Math.Max(0, startColumn0);
    }

    private void ExtractLocalFunctionSymbols(Dictionary<string, SymbolInfo> symbols, BlockStatement? body, string text)
    {
        if (body == null) return;

        foreach (var stmt in body.Statements)
        {
            ExtractLocalFunctionSymbols(symbols, stmt, text);
        }
    }

    private void ExtractLocalFunctionSymbols(Dictionary<string, SymbolInfo> symbols, Statement stmt, string text)
    {
        switch (stmt)
        {
            case LocalFunctionStatement localFunc:
                symbols[localFunc.Function.Name] = CreateFunctionSymbol(localFunc.Function, SymbolKind.Function, text);
                ExtractLocalFunctionSymbols(symbols, localFunc.Function.Body, text);
                break;

            case BlockStatement block:
                foreach (var s in block.Statements)
                {
                    ExtractLocalFunctionSymbols(symbols, s, text);
                }
                break;

            case IfStatement ifStmt:
                ExtractLocalFunctionSymbols(symbols, ifStmt.ThenStatement, text);
                if (ifStmt.ElseStatement != null)
                {
                    ExtractLocalFunctionSymbols(symbols, ifStmt.ElseStatement, text);
                }
                break;

            case ForStatement forStmt:
                if (forStmt.Initializer != null)
                {
                    ExtractLocalFunctionSymbols(symbols, forStmt.Initializer, text);
                }
                ExtractLocalFunctionSymbols(symbols, forStmt.Body, text);
                break;

            case ForeachStatement foreachStmt:
                ExtractLocalFunctionSymbols(symbols, foreachStmt.Body, text);
                break;

            case AwaitForEachStatement awaitForeachStmt:
                ExtractLocalFunctionSymbols(symbols, awaitForeachStmt.Body, text);
                break;

            case WhileStatement whileStmt:
                ExtractLocalFunctionSymbols(symbols, whileStmt.Body, text);
                break;

            case TryStatement tryStmt:
                ExtractLocalFunctionSymbols(symbols, tryStmt.TryBlock, text);
                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    ExtractLocalFunctionSymbols(symbols, catchClause.Block, text);
                }
                if (tryStmt.FinallyBlock != null)
                {
                    ExtractLocalFunctionSymbols(symbols, tryStmt.FinallyBlock, text);
                }
                break;

            case UsingStatement usingStmt:
                if (usingStmt.Declaration != null)
                {
                    ExtractLocalFunctionSymbols(symbols, usingStmt.Declaration, text);
                }
                if (usingStmt.Body != null)
                {
                    ExtractLocalFunctionSymbols(symbols, usingStmt.Body, text);
                }
                break;

            case LockStatement lockStmt:
                ExtractLocalFunctionSymbols(symbols, lockStmt.Body, text);
                break;

            case SwitchStatement switchStmt:
                foreach (var switchCase in switchStmt.Cases)
                {
                    foreach (var caseStmt in switchCase.Statements)
                    {
                        ExtractLocalFunctionSymbols(symbols, caseStmt, text);
                    }
                }
                break;
        }
    }

    private SymbolInfo CreateFunctionSymbol(FunctionDeclaration func, SymbolKind kind, string text)
    {
        return new SymbolInfo(func.Name, kind)
        {
            TypeName = func.ReturnType?.ToString(),
            Documentation = ExtractLeadingDocumentation(text, func.Line),
            Parameters = func.Parameters.Select(p => new ParameterInfo(
                p.Name,
                p.Type.ToString(),
                p.DefaultValue != null
            )).ToList(),
            Modifiers = func.Modifiers
        };
    }

    private SymbolInfo CreateTypeSymbol(ClassDeclaration classDecl, string text)
    {
        var symbol = new SymbolInfo(classDecl.Name, SymbolKind.Class)
        {
            Documentation = ExtractLeadingDocumentation(text, classDecl.Line),
            Modifiers = classDecl.Modifiers
        };
        ExtractMembers(symbol, classDecl.Members, text);
        return symbol;
    }

    private SymbolInfo CreateTypeSymbol(StructDeclaration structDecl, string text)
    {
        var symbol = new SymbolInfo(structDecl.Name, SymbolKind.Struct)
        {
            Documentation = ExtractLeadingDocumentation(text, structDecl.Line),
            Modifiers = structDecl.Modifiers
        };
        ExtractMembers(symbol, structDecl.Members, text);
        return symbol;
    }

    private SymbolInfo CreateTypeSymbol(RecordDeclaration recordDecl, string text)
    {
        var symbol = new SymbolInfo(recordDecl.Name, SymbolKind.Record)
        {
            Documentation = ExtractLeadingDocumentation(text, recordDecl.Line),
            Modifiers = recordDecl.Modifiers
        };
        ExtractMembers(symbol, recordDecl.Members, text);
        return symbol;
    }

    private SymbolInfo CreateTypeSymbol(InterfaceDeclaration interfaceDecl, string text)
    {
        var symbol = new SymbolInfo(interfaceDecl.Name, SymbolKind.Interface)
        {
            Documentation = ExtractLeadingDocumentation(text, interfaceDecl.Line),
            Modifiers = interfaceDecl.Modifiers
        };
        ExtractMembers(symbol, interfaceDecl.Members, text);
        return symbol;
    }

    private SymbolInfo CreateEnumSymbol(EnumDeclaration enumDecl, string text)
    {
        var symbol = new SymbolInfo(enumDecl.Name, SymbolKind.Enum)
        {
            Documentation = ExtractLeadingDocumentation(text, enumDecl.Line),
            Modifiers = enumDecl.Modifiers
        };

        // Add enum members
        foreach (var member in enumDecl.Members)
        {
            symbol.Members.Add(new SymbolInfo(member.Name, SymbolKind.EnumMember)
            {
                TypeName = enumDecl.Name
            });
        }

        return symbol;
    }

    private SymbolInfo CreateUnionSymbol(UnionDeclaration unionDecl, string text)
    {
        var symbol = new SymbolInfo(unionDecl.Name, SymbolKind.Union)
        {
            Documentation = ExtractLeadingDocumentation(text, unionDecl.Line),
            Modifiers = unionDecl.Modifiers
        };

        // Add union cases as members
        foreach (var case_ in unionDecl.Cases)
        {
            symbol.Members.Add(new SymbolInfo(case_.Name, SymbolKind.Class)
            {
                TypeName = unionDecl.Name
            });
        }

        return symbol;
    }

    private void ExtractMembers(SymbolInfo symbol, List<Declaration> members, string text)
    {
        foreach (var member in members)
        {
            if (member is FunctionDeclaration funcDecl)
            {
                symbol.Members.Add(CreateFunctionSymbol(funcDecl, SymbolKind.Method, text));
            }
            else if (member is PropertyDeclaration propDecl)
            {
                symbol.Members.Add(new SymbolInfo(propDecl.Name, SymbolKind.Property)
                {
                    TypeName = propDecl.Type.ToString(),
                    Documentation = ExtractLeadingDocumentation(text, propDecl.Line),
                    Modifiers = propDecl.Modifiers
                });
            }
            else if (member is FieldDeclaration fieldDecl)
            {
                symbol.Members.Add(new SymbolInfo(fieldDecl.Name, SymbolKind.Field)
                {
                    TypeName = fieldDecl.Type?.ToString(),
                    Documentation = ExtractLeadingDocumentation(text, fieldDecl.Line),
                    Modifiers = fieldDecl.Modifiers
                });
            }
            else if (member is ConstructorDeclaration ctorDecl)
            {
                symbol.Members.Add(new SymbolInfo(symbol.Name, SymbolKind.Constructor)
                {
                    Documentation = ExtractLeadingDocumentation(text, ctorDecl.Line),
                    Parameters = ctorDecl.Parameters.Select(p => new ParameterInfo(
                        p.Name,
                        p.Type.ToString(),
                        p.DefaultValue != null
                    )).ToList(),
                    Modifiers = ctorDecl.Modifiers
                });
            }
        }
    }

    private static string? ExtractLeadingDocumentation(string text, int declarationLine)
    {
        if (declarationLine <= 1)
        {
            return null;
        }

        var lines = text.Split('\n');
        var startIndex = Math.Min(declarationLine - 2, lines.Length - 1);
        var commentLines = new List<string>();

        for (var i = startIndex; i >= 0; i--)
        {
            var trimmed = lines[i].Trim();
            if (trimmed.StartsWith("///", StringComparison.Ordinal))
            {
                commentLines.Insert(0, trimmed[3..].Trim());
            }
            else if (trimmed.StartsWith("//", StringComparison.Ordinal))
            {
                commentLines.Insert(0, trimmed[2..].Trim());
            }
            else if (string.IsNullOrWhiteSpace(trimmed) && commentLines.Count == 0)
            {
                continue;
            }
            else
            {
                break;
            }
        }

        return commentLines.Count == 0
            ? null
            : string.Join("\n", commentLines).Trim();
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
