using System;
using System.IO;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

var source = File.ReadAllText("debug_test.ns");
var lexer = new Lexer(source, "debug_test.ns");
var tokens = lexer.Tokenize();
var parser = new Parser(tokens);
var ast = parser.ParseCompilationUnit();

Console.WriteLine("AST parsed successfully");
Console.WriteLine($"Declarations: {ast.Declarations.Count}");

// Let's check the structure
foreach (var decl in ast.Declarations)
{
    if (decl is ClassDeclaration classDecl)
    {
        Console.WriteLine($"Class: {classDecl.Name}");
        foreach (var member in classDecl.Members)
        {
            if (member is FunctionDeclaration func)
            {
                Console.WriteLine($"  Function: {func.Name}");
                if (func.Body is BlockStatement block)
                {
                    Console.WriteLine($"    Statements: {block.Statements.Count}");
                    foreach (var stmt in block.Statements)
                    {
                        Console.WriteLine($"      Statement type: {stmt.GetType().Name}");
                        if (stmt is VariableDeclarationStatement varDecl)
                        {
                            Console.WriteLine($"        Variable: {varDecl.Name}");
                            if (varDecl.Initializer != null)
                            {
                                Console.WriteLine($"        Initializer type: {varDecl.Initializer.GetType().Name}");
                                PrintExpression(varDecl.Initializer, 4);
                            }
                        }
                    }
                }
            }
        }
    }
}

Console.WriteLine("\nNow testing linter...");
var linter = new Linter();
Console.WriteLine("About to call Lint...");

// Add a counter to detect infinite loop
var startTime = DateTime.UtcNow;
try
{
    var diagnostics = linter.Lint(ast, "debug_test.ns");
    var elapsed = DateTime.UtcNow - startTime;
    Console.WriteLine($"Linting completed in {elapsed.TotalMilliseconds}ms");
    Console.WriteLine($"Diagnostics: {diagnostics.Count}");
}
catch (Exception ex)
{
    Console.WriteLine($"ERROR: {ex.Message}");
    Console.WriteLine($"Stack trace: {ex.StackTrace}");
}

void PrintExpression(Expression expr, int indent)
{
    var spaces = new string(' ', indent * 2);
    Console.WriteLine($"{spaces}Expr: {expr.GetType().Name}");

    // Only print first few levels to avoid infinite recursion
    if (indent > 10)
    {
        Console.WriteLine($"{spaces}... (truncated)");
        return;
    }

    switch (expr)
    {
        case CallExpression call:
            Console.WriteLine($"{spaces}  Callee:");
            PrintExpression(call.Callee, indent + 2);
            Console.WriteLine($"{spaces}  Arguments: {call.Arguments.Count}");
            foreach (var arg in call.Arguments)
            {
                PrintExpression(arg.Value, indent + 2);
            }
            break;
        case MemberAccessExpression member:
            Console.WriteLine($"{spaces}  Member: {member.MemberName}");
            Console.WriteLine($"{spaces}  Object:");
            PrintExpression(member.Object, indent + 2);
            break;
        case LambdaExpression lambda:
            Console.WriteLine($"{spaces}  Parameters: {lambda.Parameters.Count}");
            if (lambda.ExpressionBody != null)
            {
                Console.WriteLine($"{spaces}  ExpressionBody:");
                PrintExpression(lambda.ExpressionBody, indent + 2);
            }
            if (lambda.BlockBody != null)
            {
                Console.WriteLine($"{spaces}  BlockBody: {lambda.BlockBody.Statements.Count} statements");
            }
            break;
    }
}
