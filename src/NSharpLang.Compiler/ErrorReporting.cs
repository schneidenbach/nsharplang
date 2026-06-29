using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler;

/// <summary>
/// Result of parsing with AST and any errors encountered
/// </summary>
public record ParseResult
{
    public Ast.CompilationUnit? CompilationUnit { get; init; }
    public List<CompilerError> Errors { get; init; } = new();
    public bool Success => CompilationUnit != null && !Errors.Any(e => e.Severity == ErrorSeverity.Error);
}
