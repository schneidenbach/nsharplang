namespace NSharpLang.LanguageServer.Models

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// Represents the state of an open document in the LSP server
class DocumentState {
    Uri: string
    Text: string
    Version: int
    Tokens: List<Token>?
    CompilationUnit: CompilationUnit?
    Diagnostics: List<CompilerError>?
    LinterDiagnostics: List<Diagnostic>?
    // Linter diagnostics from static analysis
    Symbols: Dictionary<string, TypeInfo>?
    SymbolsInfo: Dictionary<string, SymbolInfo>?
    // Enhanced symbol info for intellisense
    SymbolLocations: Dictionary<string, List<SymbolLocation>>?
    // Declaration locations for navigation
    SemanticModel: SemanticModel?
    // Semantic model with resolved types for IDE features
    Bindings: BindingMap?
    // Binding map for semantic references (from Analyzer)
    Comments: List<CommentTrivia>?
    // Comments preserved for formatting

    // Convenience properties
    Ast: CompilationUnit? => CompilationUnit
    Source: string? => Text

    constructor(uri: string, text: string, version: int) {
        Uri = uri
        Text = text
        Version = version
    }
}
