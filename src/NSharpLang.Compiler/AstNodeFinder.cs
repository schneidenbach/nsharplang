using System;
using System.Linq;
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
    {
        var visitor = new PositionVisitor(line, column);
        visitor.VisitCompilationUnit(ast);
        return visitor.FoundExpression;
    }

    /// <summary>
    /// Finds the statement at the given line and column position
    /// </summary>
    public static Statement? FindStatementAtPosition(CompilationUnit ast, int line, int column)
    {
        var visitor = new PositionVisitor(line, column);
        visitor.VisitCompilationUnit(ast);
        return visitor.FoundStatement;
    }

    private class PositionVisitor
    {
        private readonly int _targetLine;
        private readonly int _targetColumn;

        public Expression? FoundExpression { get; private set; }
        public Statement? FoundStatement { get; private set; }

        public PositionVisitor(int line, int column)
        {
            _targetLine = line;
            _targetColumn = column;
        }

        public void VisitCompilationUnit(CompilationUnit unit)
        {
            if (unit.Declarations == null) return;

            foreach (var decl in unit.Declarations)
            {
                VisitDeclaration(decl);
                if (FoundExpression != null) return;
            }
        }

        private void VisitDeclaration(Declaration decl)
        {
            switch (decl)
            {
                case FunctionDeclaration func:
                    if (func.Body != null)
                    {
                        VisitStatement(func.Body);
                    }
                    break;

                case ClassDeclaration cls:
                    if (cls.Members != null)
                    {
                        foreach (var member in cls.Members)
                        {
                            VisitDeclaration(member);
                            if (FoundExpression != null) return;
                        }
                    }
                    break;
            }
        }

        private void VisitStatement(Statement stmt)
        {
            if (IsAtPosition(stmt.Line, stmt.Column))
            {
                FoundStatement = stmt;
            }

            switch (stmt)
            {
                case BlockStatement block:
                    foreach (var s in block.Statements)
                    {
                        VisitStatement(s);
                        if (FoundExpression != null) return;
                    }
                    break;

                case ExpressionStatement exprStmt:
                    VisitExpression(exprStmt.Expression);
                    break;

                case VariableDeclarationStatement varDecl:
                    if (varDecl.Initializer != null)
                    {
                        VisitExpression(varDecl.Initializer);
                    }
                    break;

                case ReturnStatement ret:
                    if (ret.Value != null)
                    {
                        VisitExpression(ret.Value);
                    }
                    break;

                case IfStatement ifStmt:
                    VisitExpression(ifStmt.Condition);
                    VisitStatement(ifStmt.ThenStatement);
                    if (ifStmt.ElseStatement != null)
                    {
                        VisitStatement(ifStmt.ElseStatement);
                    }
                    break;

                case WhileStatement whileStmt:
                    VisitExpression(whileStmt.Condition);
                    VisitStatement(whileStmt.Body);
                    break;

                case ForStatement forStmt:
                    if (forStmt.Initializer != null)
                    {
                        VisitStatement(forStmt.Initializer);
                    }
                    if (forStmt.Condition != null)
                    {
                        VisitExpression(forStmt.Condition);
                    }
                    if (forStmt.Iterator != null)
                    {
                        VisitExpression(forStmt.Iterator);
                    }
                    VisitStatement(forStmt.Body);
                    break;

                case ForeachStatement foreachStmt:
                    VisitExpression(foreachStmt.Collection);
                    VisitStatement(foreachStmt.Body);
                    break;
            }
        }

        private void VisitExpression(Expression expr)
        {
            // Check if this expression is at our target position
            if (IsAtPosition(expr.Line, expr.Column))
            {
                FoundExpression = expr;
            }

            // Visit sub-expressions to find more specific matches
            switch (expr)
            {
                case BinaryExpression binary:
                    VisitExpression(binary.Left);
                    if (FoundExpression != null && FoundExpression != binary) return;
                    VisitExpression(binary.Right);
                    break;

                case UnaryExpression unary:
                    VisitExpression(unary.Operand);
                    break;

                case MustExpression must:
                    VisitExpression(must.Expression);
                    break;

                case CallExpression call:
                    VisitExpression(call.Callee);
                    if (FoundExpression != null && FoundExpression != call) return;
                    foreach (var arg in call.Arguments)
                    {
                        VisitExpression(arg.Value);
                        if (FoundExpression != null && FoundExpression != call) return;
                    }
                    break;

                case MemberAccessExpression memberAccess:
                    // Visit object first
                    VisitExpression(memberAccess.Object);
                    // If we found a match in the object, but we're actually at the member position,
                    // prefer the member access expression itself
                    if (IsAtPosition(expr.Line, expr.Column))
                    {
                        FoundExpression = memberAccess;
                    }
                    break;

                case IndexAccessExpression index:
                    VisitExpression(index.Object);
                    VisitExpression(index.Index);
                    break;

                case ArrayLiteralExpression array:
                    foreach (var element in array.Elements)
                    {
                        VisitExpression(element);
                        if (FoundExpression != null && FoundExpression != array) return;
                    }
                    break;

                case LambdaExpression lambda:
                    if (lambda.ExpressionBody != null)
                    {
                        VisitExpression(lambda.ExpressionBody);
                    }
                    else if (lambda.BlockBody != null)
                    {
                        VisitStatement(lambda.BlockBody);
                    }
                    break;

                case ParenthesizedExpression paren:
                    VisitExpression(paren.Inner);
                    break;
            }
        }

        private bool IsAtPosition(int line, int column)
        {
            // LSP uses 0-based line/column; lexer+parser currently store 1-based.
            // Always normalize node positions to 0-based before comparing.
            var nodeLine = Math.Max(0, line - 1);
            var nodeColumn = Math.Max(0, column - 1);
            return nodeLine == _targetLine && nodeColumn <= _targetColumn;
        }
    }
}
