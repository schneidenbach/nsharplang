using System;
using System.Linq;
using System.Collections.Generic;
using NewCLILang.Compiler;
using NewCLILang.Compiler.Ast;
using Xunit;

namespace NewCLILang.Tests;

public class ParserTests
{
    private static CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        return parser.ParseCompilationUnit();
    }

    [Fact]
    public void TestSimpleFunctionDeclaration()
    {
        var source = @"
            func Add(x: int, y: int): int {
                return x + y
            }
        ";

        var cu = Parse(source);
        Assert.Single(cu.Declarations);

        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.Equal("Add", funcDecl.Name);
        Assert.Equal(2, funcDecl.Parameters.Count);
        Assert.Equal("x", funcDecl.Parameters[0].Name);
        Assert.Equal("y", funcDecl.Parameters[1].Name);
        Assert.NotNull(funcDecl.ReturnType);
        Assert.NotNull(funcDecl.Body);
    }

    [Fact]
    public void TestClassDeclaration()
    {
        var source = @"
            class Person {
                Name: string
                Age: int
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;

        Assert.NotNull(classDecl);
        Assert.Equal("Person", classDecl.Name);
        Assert.Equal(2, classDecl.Members.Count);
    }

    [Fact]
    public void TestVariableDeclaration()
    {
        var source = @"
            func Test() {
                let x: int = 42
                y := ""hello""
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.NotNull(funcDecl.Body);
        Assert.Equal(2, funcDecl.Body.Statements.Count);

        var letDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(letDecl);
        Assert.Equal("x", letDecl.Name);
        Assert.Equal(VariableKind.Let, letDecl.Kind);

        var shorthandDecl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(shorthandDecl);
        Assert.Equal("y", shorthandDecl.Name);
        Assert.Equal(VariableKind.Let, shorthandDecl.Kind);
    }

    [Fact]
    public void TestIfStatement()
    {
        var source = @"
            func Test() {
                if x > 5 {
                    return true
                } else {
                    return false
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var ifStmt = funcDecl!.Body!.Statements[0] as IfStatement;

        Assert.NotNull(ifStmt);
        Assert.NotNull(ifStmt.Condition);
        Assert.NotNull(ifStmt.ThenStatement);
        Assert.NotNull(ifStmt.ElseStatement);
    }

    [Fact]
    public void TestBinaryExpression()
    {
        var source = @"
            func Test(): int {
                return 1 + 2 * 3
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var returnStmt = funcDecl!.Body!.Statements[0] as ReturnStatement;

        Assert.NotNull(returnStmt);
        Assert.NotNull(returnStmt.Value);

        var addExpr = returnStmt.Value as BinaryExpression;
        Assert.NotNull(addExpr);
        Assert.Equal(BinaryOperator.Add, addExpr.Operator);

        var mulExpr = addExpr.Right as BinaryExpression;
        Assert.NotNull(mulExpr);
        Assert.Equal(BinaryOperator.Multiply, mulExpr.Operator);
    }

    [Fact]
    public void TestArrayLiteral()
    {
        var source = @"
            func Test() {
                arr := [1, 2, 3]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var varDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;

        Assert.NotNull(varDecl);
        var arrayLiteral = varDecl.Initializer as ArrayLiteralExpression;
        Assert.NotNull(arrayLiteral);
        Assert.Equal(3, arrayLiteral.Elements.Count);
    }

    [Fact]
    public void TestLambdaExpression()
    {
        var source = @"
            func Test() {
                f := x => x * 2
                g := (x, y) => x + y
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;

        var fDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;
        var lambda1 = fDecl!.Initializer as LambdaExpression;
        Assert.NotNull(lambda1);
        Assert.Single(lambda1.Parameters);
        Assert.NotNull(lambda1.ExpressionBody);

        var gDecl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        var lambda2 = gDecl!.Initializer as LambdaExpression;
        Assert.NotNull(lambda2);
        Assert.Equal(2, lambda2.Parameters.Count);
    }

    [Fact]
    public void TestMemberAccess()
    {
        var source = @"
            func Test() {
                x := person.Name
                y := person?.Age
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;

        var xDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;
        var memberAccess1 = xDecl!.Initializer as MemberAccessExpression;
        Assert.NotNull(memberAccess1);
        Assert.Equal("Name", memberAccess1.MemberName);
        Assert.False(memberAccess1.IsNullConditional);

        var yDecl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        var memberAccess2 = yDecl!.Initializer as MemberAccessExpression;
        Assert.NotNull(memberAccess2);
        Assert.Equal("Age", memberAccess2.MemberName);
        Assert.True(memberAccess2.IsNullConditional);
    }

    [Fact]
    public void TestFunctionCall()
    {
        var source = @"
            func Test() {
                result := Add(1, 2)
                named := Create(name: ""John"", age: 30)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;

        var resultDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;
        var call1 = resultDecl!.Initializer as CallExpression;
        Assert.NotNull(call1);
        Assert.Equal(2, call1.Arguments.Count);

        var namedDecl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        var call2 = namedDecl!.Initializer as CallExpression;
        Assert.NotNull(call2);
        Assert.Equal(2, call2.Arguments.Count);
        Assert.Equal("name", call2.Arguments[0].Name);
        Assert.Equal("age", call2.Arguments[1].Name);
    }

    [Fact]
    public void TestNewExpression()
    {
        var source = @"
            func Test() {
                p := new Person(""John"") { Age: 30 }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var pDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;

        var newExpr = pDecl!.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        Assert.Single(newExpr.ConstructorArguments);
        Assert.NotNull(newExpr.Initializer);
        Assert.Single(newExpr.Initializer.Properties);
    }

    [Fact]
    public void TestNamespaceAndUsings()
    {
        var source = @"
            namespace MyApp.Services

            using System
            using System.Collections.Generic
            using Json = System.Text.Json

            func Test() {}
        ";

        var cu = Parse(source);
        Assert.NotNull(cu.Namespace);
        Assert.Equal("MyApp.Services", cu.Namespace.Name);
        Assert.Equal(3, cu.Usings.Count);
        Assert.Equal("System", cu.Usings[0].Namespace);
        Assert.Equal("System.Collections.Generic", cu.Usings[1].Namespace);
        Assert.Equal("Json", cu.Usings[2].Alias);
    }

    [Fact]
    public void TestTernaryExpression()
    {
        var source = @"
            func Test() {
                result := x > 5 ? ""big"" : ""small""
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var varDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;

        var ternary = varDecl!.Initializer as TernaryExpression;
        Assert.NotNull(ternary);
        Assert.NotNull(ternary.Condition);
        Assert.NotNull(ternary.ThenExpression);
        Assert.NotNull(ternary.ElseExpression);
    }

    [Fact]
    public void TestNullCoalescingExpression()
    {
        var source = @"
            func Test() {
                value := maybeNull ?? ""default""
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var varDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;

        var binary = varDecl!.Initializer as BinaryExpression;
        Assert.NotNull(binary);
        Assert.Equal(BinaryOperator.NullCoalesce, binary.Operator);
    }

    [Fact]
    public void TestForLoop()
    {
        var source = @"
            func Test() {
                for i := 0; i < 10; i++ {
                    print(i)
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var forStmt = funcDecl!.Body!.Statements[0] as ForStatement;

        Assert.NotNull(forStmt);
        Assert.NotNull(forStmt.Initializer);
        Assert.NotNull(forStmt.Condition);
        Assert.NotNull(forStmt.Iterator);
        Assert.NotNull(forStmt.Body);
    }

    [Fact]
    public void TestForeachLoop()
    {
        var source = @"
            func Test() {
                foreach item in items {
                    print(item)
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var foreachStmt = funcDecl!.Body!.Statements[0] as ForeachStatement;

        Assert.NotNull(foreachStmt);
        Assert.Equal("item", foreachStmt.VariableName);
        Assert.NotNull(foreachStmt.Collection);
        Assert.NotNull(foreachStmt.Body);
    }

    [Fact]
    public void TestTryCatchFinally()
    {
        var source = @"
            func Test() {
                try {
                    DoSomething()
                } catch (Exception ex) {
                    print(ex)
                } finally {
                    Cleanup()
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var tryStmt = funcDecl!.Body!.Statements[0] as TryStatement;

        Assert.NotNull(tryStmt);
        Assert.NotNull(tryStmt.TryBlock);
        Assert.Single(tryStmt.CatchClauses);
        Assert.NotNull(tryStmt.FinallyBlock);
    }

    [Fact]
    public void TestEnumDeclaration()
    {
        var source = @"
            enum Status {
                Pending,
                Active,
                Done
            }
        ";

        var cu = Parse(source);
        var enumDecl = cu.Declarations[0] as EnumDeclaration;

        Assert.NotNull(enumDecl);
        Assert.Equal("Status", enumDecl.Name);
        Assert.Equal(3, enumDecl.Members.Count);
        Assert.Equal(EnumType.Int, enumDecl.Type);
    }

    [Fact]
    public void TestUnionDeclaration()
    {
        var source = @"
            union Result {
                Success { value: int }
                Failure { error: string, code: int }
            }
        ";

        var cu = Parse(source);
        var unionDecl = cu.Declarations[0] as UnionDeclaration;

        Assert.NotNull(unionDecl);
        Assert.Equal("Result", unionDecl.Name);
        Assert.Equal(2, unionDecl.Cases.Count);
        Assert.Equal("Success", unionDecl.Cases[0].Name);
        Assert.Single(unionDecl.Cases[0].Properties!);
        Assert.Equal("Failure", unionDecl.Cases[1].Name);
        Assert.Equal(2, unionDecl.Cases[1].Properties!.Count);
    }

    [Fact]
    public void TestInterfaceDeclaration()
    {
        var source = @"
            interface IReader {
                func Read(): string
            }
        ";

        var cu = Parse(source);
        var interfaceDecl = cu.Declarations[0] as InterfaceDeclaration;

        Assert.NotNull(interfaceDecl);
        Assert.Equal("IReader", interfaceDecl.Name);
        Assert.False(interfaceDecl.IsDuckInterface);
        Assert.Single(interfaceDecl.Members);
    }

    [Fact]
    public void TestDuckInterface()
    {
        var source = @"
            duck interface IReaderDuck {
                func Read(): string
            }
        ";

        var cu = Parse(source);
        var interfaceDecl = cu.Declarations[0] as InterfaceDeclaration;

        Assert.NotNull(interfaceDecl);
        Assert.Equal("IReaderDuck", interfaceDecl.Name);
        Assert.True(interfaceDecl.IsDuckInterface);
    }

    [Fact]
    public void TestIndexerDeclaration()
    {
        var source = @"
            class Dictionary<K, V> {
                func this[key: K]: V {
                    get { return storage[key] }
                    set { storage[key] = value }
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        var indexer = classDecl.Members[0] as IndexerDeclaration;
        Assert.NotNull(indexer);
        Assert.Single(indexer.Parameters);
        Assert.Equal("key", indexer.Parameters[0].Name);
        Assert.NotNull(indexer.GetBody);
        Assert.NotNull(indexer.SetBody);
    }

    [Fact]
    public void TestQualifiedTypeCast()
    {
        var source = @"
            func Test() {
                s := (Result.Success)r
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.NotNull(funcDecl.Body);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        Assert.Equal("s", varDecl.Name);

        var castExpr = varDecl.Initializer as CastExpression;
        Assert.NotNull(castExpr);
        Assert.Equal(CastKind.Hard, castExpr.Kind);

        var typeRef = castExpr.TargetType as SimpleTypeReference;
        Assert.NotNull(typeRef);
        Assert.Equal("Result.Success", typeRef.Name);

        var targetExpr = castExpr.Expression as IdentifierExpression;
        Assert.NotNull(targetExpr);
        Assert.Equal("r", targetExpr.Name);
    }

    [Fact]
    public void TestMatchExpression()
    {
        var source = @"
            func Test() {
                result := match x {
                    1 => ""one"",
                    2 => ""two""
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);
        Assert.Equal(2, matchExpr.Cases.Count);

        var firstCase = matchExpr.Cases[0];
        Assert.IsType<LiteralPattern>(firstCase.Pattern);
        Assert.IsType<StringLiteralExpression>(firstCase.Expression);
    }

    [Fact]
    public void TestMatchExpressionWithUnionPattern()
    {
        var source = @"
            func Test() {
                msg := match result {
                    Result.Success { value } => ""ok"",
                    Result.Failure { error } => ""fail""
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);
        Assert.Equal(2, matchExpr.Cases.Count);

        var successCase = matchExpr.Cases[0];
        var successPattern = successCase.Pattern as UnionCasePattern;
        Assert.NotNull(successPattern);
        Assert.Equal("Result.Success", successPattern.CaseName);
        Assert.Single(successPattern.Properties);
        Assert.Equal("value", successPattern.Properties[0].Name);
        Assert.Null(successPattern.Properties[0].BindingName);

        var failureCase = matchExpr.Cases[1];
        var failurePattern = failureCase.Pattern as UnionCasePattern;
        Assert.NotNull(failurePattern);
        Assert.Equal("Result.Failure", failurePattern.CaseName);
        Assert.Single(failurePattern.Properties);
        Assert.Equal("error", failurePattern.Properties[0].Name);
    }

    [Fact]
    public void TestWithExpression()
    {
        var source = @"
            func Test() {
                p2 := p1 with { Age: 31 }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var withExpr = varDecl.Initializer as WithExpression;
        Assert.NotNull(withExpr);

        var targetExpr = withExpr.Target as IdentifierExpression;
        Assert.NotNull(targetExpr);
        Assert.Equal("p1", targetExpr.Name);

        Assert.Single(withExpr.Properties);
        Assert.Equal("Age", withExpr.Properties[0].Name);
    }
}
