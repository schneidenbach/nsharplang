using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Models;
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
    private readonly HashSet<string> _loadedProjectDirs = new();
    private readonly object _analyzerLock = new();

    public DocumentManager(ILogger<DocumentManager> logger)
    {
        _logger = logger;

        // Initialize shared analyzer ONCE with system assemblies
        _sharedAnalyzer = new Analyzer();
        _sharedAnalyzer.LoadSystemAssemblies();

        _logger.LogInformation("DocumentManager initialized with shared Analyzer (system assemblies loaded)");
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

            // Parse the document
            var lexer = new Lexer(text, uri);
            state.Tokens = lexer.Tokenize();

            var parser = new Parser(state.Tokens, uri, text);  // Pass source code for error snippets
            var parseResult = parser.ParseCompilationUnit();
            state.CompilationUnit = parseResult.CompilationUnit;

            // Start with parse errors
            var diagnostics = new List<CompilerError>(parseResult.Errors);

            // Try to find and load project configuration
            var filePath = UriToFilePath(uri);
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
                // Use shared analyzer (thread-safe because Analyze doesn't mutate state)
                var analysisResult = _sharedAnalyzer.Analyze(state.CompilationUnit, uri, projectDir);
                diagnostics.AddRange(analysisResult.Errors);

                // Store semantic model for IDE features (IntelliSense, hover, etc.)
                state.SemanticModel = analysisResult.SemanticModel;

                // Run linter for additional diagnostics
                var linterConfig = LinterConfig.FromEditorConfig(projectDir);
                var linter = new Linter(linterConfig);
                state.LinterDiagnostics = linter.Lint(state.CompilationUnit, filePath);

                // Store symbol information for later use
                state.Symbols = ExtractSymbols(state.CompilationUnit);
                state.SymbolsInfo = ExtractSymbolsInfo(state.CompilationUnit);
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
        _documents.TryRemove(uri, out _);
        _lastAccessTimes.TryRemove(uri, out _);
        _logger.LogInformation("Document closed: {Uri}", uri);
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

    private Dictionary<string, SymbolInfo> ExtractSymbolsInfo(CompilationUnit compilationUnit)
    {
        var symbols = new Dictionary<string, SymbolInfo>();

        // Extract top-level function declarations
        foreach (var decl in compilationUnit.Declarations)
        {
            if (decl is FunctionDeclaration funcDecl)
            {
                symbols[funcDecl.Name] = CreateFunctionSymbol(funcDecl, SymbolKind.Function);
                ExtractLocalFunctionSymbols(symbols, funcDecl.Body);
            }
            else if (decl is ClassDeclaration classDecl)
            {
                symbols[classDecl.Name] = CreateTypeSymbol(classDecl);
            }
            else if (decl is StructDeclaration structDecl)
            {
                symbols[structDecl.Name] = CreateTypeSymbol(structDecl);
            }
            else if (decl is RecordDeclaration recordDecl)
            {
                symbols[recordDecl.Name] = CreateTypeSymbol(recordDecl);
            }
            else if (decl is InterfaceDeclaration interfaceDecl)
            {
                symbols[interfaceDecl.Name] = CreateTypeSymbol(interfaceDecl);
            }
            else if (decl is EnumDeclaration enumDecl)
            {
                symbols[enumDecl.Name] = CreateEnumSymbol(enumDecl);
            }
            else if (decl is UnionDeclaration unionDecl)
            {
                symbols[unionDecl.Name] = CreateUnionSymbol(unionDecl);
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
                    foreach (var catchClause in tryStmt.CatchClauses) VisitBlock(catchClause.Block);
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

    private void ExtractLocalFunctionSymbols(Dictionary<string, SymbolInfo> symbols, BlockStatement? body)
    {
        if (body == null) return;

        foreach (var stmt in body.Statements)
        {
            ExtractLocalFunctionSymbols(symbols, stmt);
        }
    }

    private void ExtractLocalFunctionSymbols(Dictionary<string, SymbolInfo> symbols, Statement stmt)
    {
        switch (stmt)
        {
            case LocalFunctionStatement localFunc:
                symbols[localFunc.Function.Name] = CreateFunctionSymbol(localFunc.Function, SymbolKind.Function);
                ExtractLocalFunctionSymbols(symbols, localFunc.Function.Body);
                break;

            case BlockStatement block:
                foreach (var s in block.Statements)
                {
                    ExtractLocalFunctionSymbols(symbols, s);
                }
                break;

            case IfStatement ifStmt:
                ExtractLocalFunctionSymbols(symbols, ifStmt.ThenStatement);
                if (ifStmt.ElseStatement != null)
                {
                    ExtractLocalFunctionSymbols(symbols, ifStmt.ElseStatement);
                }
                break;

            case ForStatement forStmt:
                if (forStmt.Initializer != null)
                {
                    ExtractLocalFunctionSymbols(symbols, forStmt.Initializer);
                }
                ExtractLocalFunctionSymbols(symbols, forStmt.Body);
                break;

            case ForeachStatement foreachStmt:
                ExtractLocalFunctionSymbols(symbols, foreachStmt.Body);
                break;

            case AwaitForEachStatement awaitForeachStmt:
                ExtractLocalFunctionSymbols(symbols, awaitForeachStmt.Body);
                break;

            case WhileStatement whileStmt:
                ExtractLocalFunctionSymbols(symbols, whileStmt.Body);
                break;

            case TryStatement tryStmt:
                ExtractLocalFunctionSymbols(symbols, tryStmt.TryBlock);
                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    ExtractLocalFunctionSymbols(symbols, catchClause.Block);
                }
                if (tryStmt.FinallyBlock != null)
                {
                    ExtractLocalFunctionSymbols(symbols, tryStmt.FinallyBlock);
                }
                break;

            case UsingStatement usingStmt:
                if (usingStmt.Declaration != null)
                {
                    ExtractLocalFunctionSymbols(symbols, usingStmt.Declaration);
                }
                if (usingStmt.Body != null)
                {
                    ExtractLocalFunctionSymbols(symbols, usingStmt.Body);
                }
                break;

            case LockStatement lockStmt:
                ExtractLocalFunctionSymbols(symbols, lockStmt.Body);
                break;

            case SwitchStatement switchStmt:
                foreach (var switchCase in switchStmt.Cases)
                {
                    foreach (var caseStmt in switchCase.Statements)
                    {
                        ExtractLocalFunctionSymbols(symbols, caseStmt);
                    }
                }
                break;
        }
    }

    private SymbolInfo CreateFunctionSymbol(FunctionDeclaration func, SymbolKind kind)
    {
        return new SymbolInfo(func.Name, kind)
        {
            TypeName = func.ReturnType?.ToString(),
            Parameters = func.Parameters.Select(p => new ParameterInfo(
                p.Name,
                p.Type.ToString(),
                p.DefaultValue != null
            )).ToList(),
            Modifiers = func.Modifiers
        };
    }

    private SymbolInfo CreateTypeSymbol(ClassDeclaration classDecl)
    {
        var symbol = new SymbolInfo(classDecl.Name, SymbolKind.Class)
        {
            Modifiers = classDecl.Modifiers
        };
        ExtractMembers(symbol, classDecl.Members);
        return symbol;
    }

    private SymbolInfo CreateTypeSymbol(StructDeclaration structDecl)
    {
        var symbol = new SymbolInfo(structDecl.Name, SymbolKind.Struct)
        {
            Modifiers = structDecl.Modifiers
        };
        ExtractMembers(symbol, structDecl.Members);
        return symbol;
    }

    private SymbolInfo CreateTypeSymbol(RecordDeclaration recordDecl)
    {
        var symbol = new SymbolInfo(recordDecl.Name, SymbolKind.Record)
        {
            Modifiers = recordDecl.Modifiers
        };
        ExtractMembers(symbol, recordDecl.Members);
        return symbol;
    }

    private SymbolInfo CreateTypeSymbol(InterfaceDeclaration interfaceDecl)
    {
        var symbol = new SymbolInfo(interfaceDecl.Name, SymbolKind.Interface)
        {
            Modifiers = interfaceDecl.Modifiers
        };
        ExtractMembers(symbol, interfaceDecl.Members);
        return symbol;
    }

    private SymbolInfo CreateEnumSymbol(EnumDeclaration enumDecl)
    {
        var symbol = new SymbolInfo(enumDecl.Name, SymbolKind.Enum)
        {
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

    private SymbolInfo CreateUnionSymbol(UnionDeclaration unionDecl)
    {
        var symbol = new SymbolInfo(unionDecl.Name, SymbolKind.Union)
        {
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

    private void ExtractMembers(SymbolInfo symbol, List<Declaration> members)
    {
        foreach (var member in members)
        {
            if (member is FunctionDeclaration funcDecl)
            {
                symbol.Members.Add(CreateFunctionSymbol(funcDecl, SymbolKind.Method));
            }
            else if (member is PropertyDeclaration propDecl)
            {
                symbol.Members.Add(new SymbolInfo(propDecl.Name, SymbolKind.Property)
                {
                    TypeName = propDecl.Type.ToString(),
                    Modifiers = propDecl.Modifiers
                });
            }
            else if (member is FieldDeclaration fieldDecl)
            {
                symbol.Members.Add(new SymbolInfo(fieldDecl.Name, SymbolKind.Field)
                {
                    TypeName = fieldDecl.Type?.ToString(),
                    Modifiers = fieldDecl.Modifiers
                });
            }
            else if (member is ConstructorDeclaration ctorDecl)
            {
                symbol.Members.Add(new SymbolInfo(symbol.Name, SymbolKind.Constructor)
                {
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
}
