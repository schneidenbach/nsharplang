using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using System.Collections.Generic;

namespace NSharpLang.LanguageServer.Models;

/// <summary>
/// Represents the state of an open document in the LSP server
/// </summary>
public class DocumentState
{
    public string Uri { get; init; }
    public string Text { get; init; }
    public int Version { get; init; }
    public List<Token>? Tokens { get; set; }
    public CompilationUnit? CompilationUnit { get; set; }
    public List<CompilerError>? Diagnostics { get; set; }
    public List<Diagnostic>? LinterDiagnostics { get; set; }  // Linter diagnostics from static analysis
    public Dictionary<string, TypeInfo>? Symbols { get; set; }
    public Dictionary<string, SymbolInfo>? SymbolsInfo { get; set; }  // Enhanced symbol info for intellisense
    public Dictionary<string, List<SymbolLocation>>? SymbolLocations { get; set; } // Declaration locations for navigation
    public SemanticModel? SemanticModel { get; set; }  // Semantic model with resolved types for IDE features
    public BindingMap? Bindings { get; set; }  // Binding map for semantic references (from Analyzer)

    // Convenience properties
    public CompilationUnit? Ast => CompilationUnit;
    public string? Source => Text;

    public DocumentState(string uri, string text, int version)
    {
        Uri = uri;
        Text = text;
        Version = version;
    }
}
