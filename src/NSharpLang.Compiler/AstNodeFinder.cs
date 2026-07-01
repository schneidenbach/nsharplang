using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Finds AST nodes at a specific position in the source code
/// </summary>
public class AstNodeFinder
{
    /// <summary>
    /// Finds the expression at the given line and column position
    /// </summary>
    public static Expression? FindExpressionAtPosition(CompilationUnit ast, int line, int column)
        => AstNodeFinderCore.FindExpressionAtPosition(ast, line, column) as Expression;
}
