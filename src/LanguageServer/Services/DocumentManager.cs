using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using NewCLILang.Compiler;
using NewCLILang.Compiler.Ast;
using LanguageServer.Models;
using Microsoft.Extensions.Logging;

namespace LanguageServer.Services;

/// <summary>
/// Manages the state of all open documents and provides compilation services
/// </summary>
public class DocumentManager
{
    private readonly ConcurrentDictionary<string, DocumentState> _documents = new();
    private readonly ILogger<DocumentManager> _logger;

    public DocumentManager(ILogger<DocumentManager> logger)
    {
        _logger = logger;
    }

    public void UpdateDocument(string uri, string text, int version)
    {
        try
        {
            _logger.LogInformation("Updating document: {Uri} (version {Version})", uri, version);

            var state = new DocumentState(uri, text, version);

            // Parse the document
            var lexer = new Lexer(text, uri);
            state.Tokens = lexer.Tokenize();

            var parser = new Parser(state.Tokens, uri);
            state.CompilationUnit = parser.ParseCompilationUnit();

            // Analyze the document
            var analyzer = new Analyzer();
            var analysisResult = analyzer.Analyze(state.CompilationUnit, uri, Environment.CurrentDirectory);
            state.Diagnostics = analysisResult.Errors;

            // Store symbol information for later use
            state.Symbols = ExtractSymbols(state.CompilationUnit);

            _documents[uri] = state;

            _logger.LogInformation("Document updated successfully with {DiagnosticCount} diagnostics",
                state.Diagnostics.Count);
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
                        0,
                        0,
                        ErrorSeverity.Error
                    )
                }
            };
            _documents[uri] = state;
        }
    }

    public DocumentState? GetDocument(string uri)
    {
        _documents.TryGetValue(uri, out var doc);
        return doc;
    }

    public void CloseDocument(string uri)
    {
        _documents.TryRemove(uri, out _);
        _logger.LogInformation("Document closed: {Uri}", uri);
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
}
