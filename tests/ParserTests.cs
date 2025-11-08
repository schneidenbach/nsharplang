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
                    Console.WriteLine(i)
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
                    Console.WriteLine(item)
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
                    Console.WriteLine(ex)
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

    [Fact]
    public void TestDefaultParameterValues()
    {
        var source = @"
            func Greet(name: string, greeting: string = ""Hello"") {
                return greeting
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.Equal(2, funcDecl.Parameters.Count);

        var nameParam = funcDecl.Parameters[0];
        Assert.Equal("name", nameParam.Name);
        Assert.Null(nameParam.DefaultValue);

        var greetingParam = funcDecl.Parameters[1];
        Assert.Equal("greeting", greetingParam.Name);
        Assert.NotNull(greetingParam.DefaultValue);
        Assert.IsType<StringLiteralExpression>(greetingParam.DefaultValue);
    }

    [Fact]
    public void TestNamedArguments()
    {
        var source = @"
            func Test() {
                CreateUser(name: ""John"", age: 30)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var exprStmt = funcDecl.Body.Statements[0] as ExpressionStatement;
        Assert.NotNull(exprStmt);

        var callExpr = exprStmt.Expression as CallExpression;
        Assert.NotNull(callExpr);
        Assert.Equal(2, callExpr.Arguments.Count);

        Assert.Equal("name", callExpr.Arguments[0].Name);
        Assert.Equal("age", callExpr.Arguments[1].Name);
    }

    [Fact]
    public void TestAsyncAwait()
    {
        var source = @"
            async func FetchData(): Task<string> {
                result := await GetDataAsync()
                return result
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.Equal("FetchData", funcDecl.Name);
        Assert.True(funcDecl.Modifiers.HasFlag(Modifiers.Async));

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var awaitExpr = varDecl.Initializer as AwaitExpression;
        Assert.NotNull(awaitExpr);

        var callExpr = awaitExpr.Expression as CallExpression;
        Assert.NotNull(callExpr);
    }

    [Fact]
    public void TestIteratorFunction()
    {
        var source = @"
            func* GetNumbers(): IEnumerable<int> {
                yield 1
                yield 2
                yield 3
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.Equal("GetNumbers", funcDecl.Name);
        Assert.True(funcDecl.Modifiers.HasFlag(Modifiers.Generator));
        Assert.Equal(3, funcDecl.Body.Statements.Count);

        // Check yield statements
        for (int i = 0; i < 3; i++)
        {
            var yieldStmt = funcDecl.Body.Statements[i] as YieldStatement;
            Assert.NotNull(yieldStmt);
            Assert.NotNull(yieldStmt.Value);
        }
    }

    [Fact]
    public void TestYieldBreak()
    {
        var source = @"
            func* GetNumbers(): IEnumerable<int> {
                yield 1
                yield break
                yield 2
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.True(funcDecl.Modifiers.HasFlag(Modifiers.Generator));
        Assert.Equal(3, funcDecl.Body!.Statements.Count);

        // First yield has value
        var yield1 = funcDecl.Body.Statements[0] as YieldStatement;
        Assert.NotNull(yield1);
        Assert.NotNull(yield1.Value);

        // Second is yield break (no value)
        var yieldBreak = funcDecl.Body.Statements[1] as YieldStatement;
        Assert.NotNull(yieldBreak);
        Assert.Null(yieldBreak.Value);

        // Third yield has value
        var yield2 = funcDecl.Body.Statements[2] as YieldStatement;
        Assert.NotNull(yield2);
        Assert.NotNull(yield2.Value);
    }

    [Fact]
    public void TestUsingStatement()
    {
        var source = @"
            func Test() {
                using stream := File.OpenRead(""file.txt"") {
                    data := stream.Read()
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var usingStmt = funcDecl.Body.Statements[0] as UsingStatement;
        Assert.NotNull(usingStmt);
        Assert.NotNull(usingStmt.Declaration);
        Assert.Equal("stream", usingStmt.Declaration.Name);
        Assert.NotNull(usingStmt.Body);

        var blockStmt = usingStmt.Body as BlockStatement;
        Assert.NotNull(blockStmt);
        Assert.Single(blockStmt.Statements);
    }

    [Fact]
    public void TestLockStatement()
    {
        var source = @"
            func Increment() {
                lock _lockObject {
                    _counter++
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var lockStmt = funcDecl.Body.Statements[0] as LockStatement;
        Assert.NotNull(lockStmt);
        Assert.NotNull(lockStmt.LockObject);
        Assert.NotNull(lockStmt.Body);

        var blockStmt = lockStmt.Body as BlockStatement;
        Assert.NotNull(blockStmt);
        Assert.Single(blockStmt.Statements);
    }

    [Fact]
    public void TestLockStatementWithParens()
    {
        var source = @"
            func Increment() {
                lock (_lockObject) {
                    _counter++
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var lockStmt = funcDecl.Body.Statements[0] as LockStatement;
        Assert.NotNull(lockStmt);
        Assert.NotNull(lockStmt.LockObject);
        Assert.NotNull(lockStmt.Body);
    }

    [Fact]
    public void TestSwitchStatement()
    {
        var source = @"
            func Test(value: int) {
                switch value {
                    case 1 => Console.WriteLine(""One"")
                    case 2 => Console.WriteLine(""Two"")
                    default => Console.WriteLine(""Other"")
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var switchStmt = funcDecl.Body.Statements[0] as SwitchStatement;
        Assert.NotNull(switchStmt);
        Assert.NotNull(switchStmt.Value);
        Assert.Equal(3, switchStmt.Cases.Count);

        // Check first two cases have patterns
        Assert.NotNull(switchStmt.Cases[0].Pattern);
        Assert.NotNull(switchStmt.Cases[1].Pattern);

        // Check default case (pattern is null for default)
        Assert.Null(switchStmt.Cases[2].Pattern);
    }

    [Fact]
    public void TestSpreadOperator()
    {
        var source = @"
            func Test() {
                arr1 := [1, 2, 3]
                arr2 := [...arr1, 4, 5]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var arr2Decl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(arr2Decl);

        var arrayLiteral = arr2Decl.Initializer as ArrayLiteralExpression;
        Assert.NotNull(arrayLiteral);
        Assert.Equal(3, arrayLiteral.Elements.Count);

        var spreadExpr = arrayLiteral.Elements[0] as SpreadExpression;
        Assert.NotNull(spreadExpr);
    }

    [Fact]
    public void TestSpreadOperatorInFunctionCall()
    {
        var source = @"
            func Sum(params numbers: int[]): int {
                return 0
            }

            func Test() {
                items := [1, 2, 3]
                result := Sum(...items)
            }
        ";

        var cu = Parse(source);
        var testFunc = cu.Declarations[1] as FunctionDeclaration;
        Assert.NotNull(testFunc);

        var resultDecl = testFunc.Body.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(resultDecl);

        var callExpr = resultDecl.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        Assert.Single(callExpr.Arguments);

        var spreadArg = callExpr.Arguments[0].Value as SpreadExpression;
        Assert.NotNull(spreadArg);

        var innerExpr = spreadArg.Expression as IdentifierExpression;
        Assert.NotNull(innerExpr);
        Assert.Equal("items", innerExpr.Name);
    }

    [Fact]
    public void TestPartialClass()
    {
        var source = @"
            partial class User {
                Name: string
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal("User", classDecl.Name);
        Assert.True(classDecl.Modifiers.HasFlag(Modifiers.Partial));
    }

    [Fact]
    public void TestAbstractAndSealedClasses()
    {
        var source = @"
            abstract class Animal {
                abstract func MakeSound()
            }

            sealed class FinalClass {
                Name: string
            }
        ";

        var cu = Parse(source);

        var abstractClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(abstractClass);
        Assert.Equal("Animal", abstractClass.Name);
        Assert.True(abstractClass.Modifiers.HasFlag(Modifiers.Abstract));

        var abstractMethod = abstractClass.Members[0] as FunctionDeclaration;
        Assert.NotNull(abstractMethod);
        Assert.True(abstractMethod.Modifiers.HasFlag(Modifiers.Abstract));

        var sealedClass = cu.Declarations[1] as ClassDeclaration;
        Assert.NotNull(sealedClass);
        Assert.Equal("FinalClass", sealedClass.Name);
        Assert.True(sealedClass.Modifiers.HasFlag(Modifiers.Sealed));
    }

    [Fact]
    public void TestVirtualMethods()
    {
        var source = @"
            class Animal {
                virtual func MakeSound() {
                    Console.WriteLine(""Sound"")
                }
            }

            class Dog : Animal {
                func MakeSound() {
                    Console.WriteLine(""Bark"")
                }
            }
        ";

        var cu = Parse(source);

        var baseClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(baseClass);

        var virtualMethod = baseClass.Members[0] as FunctionDeclaration;
        Assert.NotNull(virtualMethod);
        Assert.True(virtualMethod.Modifiers.HasFlag(Modifiers.Virtual));

        var derivedClass = cu.Declarations[1] as ClassDeclaration;
        Assert.NotNull(derivedClass);
        Assert.NotNull(derivedClass.BaseClass);

        var overrideMethod = derivedClass.Members[0] as FunctionDeclaration;
        Assert.NotNull(overrideMethod);
    }

    [Fact]
    public void TestTypeAlias()
    {
        var source = @"
            type UserId = int
            type Handler = Func<string, void>
            type StringDict = Dictionary<string, string>
        ";

        var cu = Parse(source);
        Assert.Equal(3, cu.Declarations.Count);

        var alias1 = cu.Declarations[0] as TypeAliasDeclaration;
        Assert.NotNull(alias1);
        Assert.Equal("UserId", alias1.Name);
        Assert.IsType<SimpleTypeReference>(alias1.Type);
        Assert.Equal("int", ((SimpleTypeReference)alias1.Type).Name);

        var alias2 = cu.Declarations[1] as TypeAliasDeclaration;
        Assert.NotNull(alias2);
        Assert.Equal("Handler", alias2.Name);
        Assert.IsType<FunctionTypeReference>(alias2.Type); // Func<...> is a function type

        var alias3 = cu.Declarations[2] as TypeAliasDeclaration;
        Assert.NotNull(alias3);
        Assert.Equal("StringDict", alias3.Name);
        Assert.IsType<GenericTypeReference>(alias3.Type);
    }

    [Fact]
    public void TestAttributes()
    {
        var source = @"
            [Serializable]
            class Person {
                [JsonProperty(""user_name"")]
                UserName: string

                [Required]
                Email: string
            }

            [HttpGet(""/api/users"")]
            func GetUsers(): User[] {
                return []
            }
        ";

        var cu = Parse(source);
        Assert.Equal(2, cu.Declarations.Count);

        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Single(classDecl.Attributes);
        Assert.Equal("Serializable", classDecl.Attributes[0].Name);

        var field1 = classDecl.Members[0] as FieldDeclaration;
        Assert.NotNull(field1);
        Assert.Single(field1.Attributes);
        Assert.Equal("JsonProperty", field1.Attributes[0].Name);
        Assert.Single(field1.Attributes[0].Arguments);

        var field2 = classDecl.Members[1] as FieldDeclaration;
        Assert.NotNull(field2);
        Assert.Single(field2.Attributes);
        Assert.Equal("Required", field2.Attributes[0].Name);

        var funcDecl = cu.Declarations[1] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.Single(funcDecl.Attributes);
        Assert.Equal("HttpGet", funcDecl.Attributes[0].Name);
        Assert.Single(funcDecl.Attributes[0].Arguments);
    }

    [Fact]
    public void TestQualifiedAttributes()
    {
        var source = @"
            [System.Serializable]
            class Person {
                Name: string
            }

            [System.Runtime.CompilerServices.InlineArray(10)]
            struct Buffer {
                element: int
            }

            [System.Diagnostics.CodeAnalysis.SuppressMessage(""Category"", ""CheckId"")]
            func DoWork() {
            }
        ";

        var cu = Parse(source);
        Assert.Equal(3, cu.Declarations.Count);

        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Single(classDecl.Attributes);
        Assert.Equal("System.Serializable", classDecl.Attributes[0].Name);

        var structDecl = cu.Declarations[1] as StructDeclaration;
        Assert.NotNull(structDecl);
        Assert.Single(structDecl.Attributes);
        Assert.Equal("System.Runtime.CompilerServices.InlineArray", structDecl.Attributes[0].Name);
        Assert.Single(structDecl.Attributes[0].Arguments);

        var funcDecl = cu.Declarations[2] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.Single(funcDecl.Attributes);
        Assert.Equal("System.Diagnostics.CodeAnalysis.SuppressMessage", funcDecl.Attributes[0].Name);
        Assert.Equal(2, funcDecl.Attributes[0].Arguments.Count);
    }

    [Fact]
    public void TestExtensionMethod()
    {
        var source = @"
            func IsEmpty(this s: string): bool {
                return s.Length == 0
            }

            static class StringExtensions {
                static func ToUpperFirst(this s: string): string {
                    return s.Substring(0, 1).ToUpper() + s.Substring(1)
                }
            }
        ";

        var cu = Parse(source);
        Assert.Equal(2, cu.Declarations.Count);

        var topLevelFunc = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(topLevelFunc);
        Assert.Equal("IsEmpty", topLevelFunc.Name);
        Assert.Single(topLevelFunc.Parameters);
        Assert.True(topLevelFunc.Parameters[0].IsThis);
        Assert.Equal("s", topLevelFunc.Parameters[0].Name);

        var staticClass = cu.Declarations[1] as ClassDeclaration;
        Assert.NotNull(staticClass);
        Assert.True(staticClass.Modifiers.HasFlag(Modifiers.Static));

        var staticMethod = staticClass.Members[0] as FunctionDeclaration;
        Assert.NotNull(staticMethod);
        Assert.True(staticMethod.Modifiers.HasFlag(Modifiers.Static));
        Assert.Single(staticMethod.Parameters);
        Assert.True(staticMethod.Parameters[0].IsThis);
    }

    [Fact]
    public void TestStaticClass()
    {
        var source = @"
            static class Helpers {
                static func DoThing() {
                    Console.WriteLine(""done"")
                }

                static func Calculate(x: int): int {
                    return x * 2
                }
            }
        ";

        var cu = Parse(source);
        Assert.Single(cu.Declarations);

        var staticClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(staticClass);
        Assert.Equal("Helpers", staticClass.Name);
        Assert.True(staticClass.Modifiers.HasFlag(Modifiers.Static));
        Assert.Equal(2, staticClass.Members.Count);

        foreach (var member in staticClass.Members)
        {
            var method = member as FunctionDeclaration;
            Assert.NotNull(method);
            Assert.True(method.Modifiers.HasFlag(Modifiers.Static));
        }
    }

    [Fact]
    public void TestReadonlyField()
    {
        var source = @"
            class MyClass {
                readonly id: string

                constructor() {
                    id = Guid.NewGuid().ToString()
                }
            }
        ";

        var cu = Parse(source);
        Assert.Single(cu.Declarations);

        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        var field = classDecl.Members[0] as FieldDeclaration;
        Assert.NotNull(field);
        Assert.Equal("id", field.Name);
        Assert.True(field.Modifiers.HasFlag(Modifiers.Readonly));
    }

    [Fact]
    public void TestIndexerUsage()
    {
        var source = @"
            func Test() {
                arr := [1, 2, 3]
                x := arr[0]
                dict := new Dictionary<string, int>()
                dict[""key""] = 42
                y := dict[""key""]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.Equal(5, funcDecl.Body!.Statements.Count);

        // Check arr[0] indexer
        var xDecl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(xDecl);
        var indexAccess = xDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        var arrIdent = indexAccess.Object as IdentifierExpression;
        Assert.NotNull(arrIdent);
        Assert.Equal("arr", arrIdent.Name);

        // Check dict["key"] = 42 assignment
        var dictAssign = funcDecl.Body.Statements[3] as ExpressionStatement;
        Assert.NotNull(dictAssign);
        var assignExpr = dictAssign.Expression as AssignmentExpression;
        Assert.NotNull(assignExpr);
        var dictIndexAccess = assignExpr.Target as IndexAccessExpression;
        Assert.NotNull(dictIndexAccess);
    }

    [Fact]
    public void TestIndexAccessWithConditional()
    {
        var source = @"
            func Test() {
                let arr = [1, 2, 3]
                x := arr[0]
                y := arr[1]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        // Check arr[0]
        var xDecl = funcDecl.Body!.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(xDecl);
        var indexAccess = xDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        Assert.False(indexAccess.IsNullConditional);
    }

    [Fact]
    public void TestNullConditionalIndexing()
    {
        var source = @"
            func Test() {
                arr := GetArray()
                x := arr?[0]
                dict := GetDict()
                y := dict?[""key""]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        // Check arr?[0]
        var xDecl = funcDecl.Body!.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(xDecl);
        var indexAccess = xDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        Assert.True(indexAccess.IsNullConditional);
        var arrIdent = indexAccess.Object as IdentifierExpression;
        Assert.NotNull(arrIdent);
        Assert.Equal("arr", arrIdent.Name);

        // Check dict?["key"]
        var yDecl = funcDecl.Body.Statements[3] as VariableDeclarationStatement;
        Assert.NotNull(yDecl);
        var dictIndexAccess = yDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(dictIndexAccess);
        Assert.True(dictIndexAccess.IsNullConditional);
    }

    [Fact]
    public void TestSafeCastOperator()
    {
        var source = @"
            func Test() {
                let obj = GetObject()
                str := obj as string
                person := obj as Person
                num := value as int
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        // Check obj as string
        var strDecl = funcDecl.Body!.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(strDecl);
        var safeCast = strDecl.Initializer as CastExpression;
        Assert.NotNull(safeCast);
        Assert.Equal(CastKind.Safe, safeCast.Kind);
        var simpleType = safeCast.TargetType as SimpleTypeReference;
        Assert.NotNull(simpleType);
        Assert.Equal("string", simpleType.Name);
    }

    [Fact]
    public void TestIsPattern()
    {
        var source = @"
            func Test() {
                if obj is string s {
                    Console.WriteLine(s)
                }

                if value is int {
                    Console.WriteLine(""is int"")
                }

                result := obj is Person
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        // Check if obj is string s
        var ifStmt1 = funcDecl.Body!.Statements[0] as IfStatement;
        Assert.NotNull(ifStmt1);
        var isExpr1 = ifStmt1.Condition as IsExpression;
        Assert.NotNull(isExpr1);
        var objIdent = isExpr1.Expression as IdentifierExpression;
        Assert.NotNull(objIdent);
        Assert.Equal("obj", objIdent.Name);
        Assert.NotNull(isExpr1.VariableName);
        Assert.Equal("s", isExpr1.VariableName);

        // Check if value is int (no variable)
        var ifStmt2 = funcDecl.Body.Statements[1] as IfStatement;
        Assert.NotNull(ifStmt2);
        var isExpr2 = ifStmt2.Condition as IsExpression;
        Assert.NotNull(isExpr2);
        Assert.NotNull(isExpr2.Type);
    }

    [Fact]
    public void TestNullCoalescingAssignment()
    {
        var source = @"
            func Test() {
                let cache = null
                cache ??= ExpensiveOperation()

                let dict = null
                dict ??= new Dictionary<string, int>()
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        // Check cache ??= ExpensiveOperation()
        var assignStmt = funcDecl.Body!.Statements[1] as ExpressionStatement;
        Assert.NotNull(assignStmt);
        var assignExpr = assignStmt.Expression as AssignmentExpression;
        Assert.NotNull(assignExpr);
        Assert.Equal(AssignmentOperator.NullCoalesceAssign, assignExpr.Operator);
        var cacheIdent = assignExpr.Target as IdentifierExpression;
        Assert.NotNull(cacheIdent);
        Assert.Equal("cache", cacheIdent.Name);
    }

    [Fact]
    public void TestThisKeyword()
    {
        var source = @"
            class MyClass {
                name: string

                func SetName(name: string) {
                    this.name = name
                }

                func GetThis(): MyClass {
                    return this
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        // Check this.name = name
        var setNameMethod = classDecl.Members[1] as FunctionDeclaration;
        Assert.NotNull(setNameMethod);
        var assignStmt = setNameMethod.Body!.Statements[0] as ExpressionStatement;
        Assert.NotNull(assignStmt);
        var assignExpr = assignStmt.Expression as AssignmentExpression;
        Assert.NotNull(assignExpr);
        var memberAccess = assignExpr.Target as MemberAccessExpression;
        Assert.NotNull(memberAccess);
        var thisExpr = memberAccess.Object as ThisExpression;
        Assert.NotNull(thisExpr);

        // Check return this
        var getThisMethod = classDecl.Members[2] as FunctionDeclaration;
        Assert.NotNull(getThisMethod);
        var returnStmt = getThisMethod.Body!.Statements[0] as ReturnStatement;
        Assert.NotNull(returnStmt);
        var returnThis = returnStmt.Value as ThisExpression;
        Assert.NotNull(returnThis);
    }

    [Fact]
    public void TestBaseKeyword()
    {
        var source = @"
            class Animal {
                virtual func MakeSound() {
                    Console.WriteLine(""Sound"")
                }
            }

            class Dog : Animal {
                func MakeSound() {
                    base.MakeSound()
                    Console.WriteLine(""Bark"")
                }
            }
        ";

        var cu = Parse(source);
        var dogClass = cu.Declarations[1] as ClassDeclaration;
        Assert.NotNull(dogClass);

        var makeSoundMethod = dogClass.Members[0] as FunctionDeclaration;
        Assert.NotNull(makeSoundMethod);

        // Check base.MakeSound()
        var baseCallStmt = makeSoundMethod.Body!.Statements[0] as ExpressionStatement;
        Assert.NotNull(baseCallStmt);
        var callExpr = baseCallStmt.Expression as CallExpression;
        Assert.NotNull(callExpr);
        var baseMemberAccess = callExpr.Callee as MemberAccessExpression;
        Assert.NotNull(baseMemberAccess);
        var baseExpr = baseMemberAccess.Object as BaseExpression;
        Assert.NotNull(baseExpr);
    }

    [Fact]
    public void TestConstructorDeclaration()
    {
        var source = @"
            class Person {
                Name: string
                Age: int

                constructor(name: string, age: int) {
                    Name = name
                    Age = age
                }
            }
        ";

        var cu = Parse(source);

        var personClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(personClass);
        var ctor = personClass.Members[2] as ConstructorDeclaration;
        Assert.NotNull(ctor);
        Assert.Equal(2, ctor.Parameters.Count);
        Assert.Equal("name", ctor.Parameters[0].Name);
        Assert.Equal("age", ctor.Parameters[1].Name);
    }

    [Fact]
    public void TestMultipleInterfaceImplementation()
    {
        var source = @"
            class MyClass : BaseClass, IFoo, IBar, IBaz {
                Name: string
            }

            class SimpleClass : IFoo, IBar {
                Id: int
            }
        ";

        var cu = Parse(source);

        // Check class with base class and interfaces
        var myClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(myClass);
        Assert.Equal("MyClass", myClass.Name);
        Assert.NotNull(myClass.BaseClass);
        Assert.Equal("BaseClass", ((SimpleTypeReference)myClass.BaseClass).Name);
        Assert.Equal(3, myClass.Interfaces.Count);
        Assert.Equal("IFoo", ((SimpleTypeReference)myClass.Interfaces[0]).Name);
        Assert.Equal("IBar", ((SimpleTypeReference)myClass.Interfaces[1]).Name);
        Assert.Equal("IBaz", ((SimpleTypeReference)myClass.Interfaces[2]).Name);

        // Check class with interfaces (parser treats first as base class since it can't tell)
        var simpleClass = cu.Declarations[1] as ClassDeclaration;
        Assert.NotNull(simpleClass);
        // Parser puts IFoo as base class (can't distinguish without type info)
        Assert.NotNull(simpleClass.BaseClass);
        Assert.Equal("IFoo", ((SimpleTypeReference)simpleClass.BaseClass).Name);
        Assert.Single(simpleClass.Interfaces);
        Assert.Equal("IBar", ((SimpleTypeReference)simpleClass.Interfaces[0]).Name);
    }

    [Fact]
    public void TestGenericConstraints()
    {
        var source = @"
            func Process<T>(item: T): T where T : IComparable {
                return item
            }

            func Transform<K, V>(key: K, value: V): V where K : IKey where V : IValue {
                return value
            }
        ";

        var cu = Parse(source);

        // Check function with single constraint
        var processFunc = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(processFunc);
        Assert.Single(processFunc.TypeParameters);
        Assert.Single(processFunc.Constraints);
        var constraint1 = processFunc.Constraints[0];
        Assert.Equal("T", constraint1.TypeParameter);
        Assert.Single(constraint1.Constraints);

        // Check function with multiple type parameters and constraints
        var transformFunc = cu.Declarations[1] as FunctionDeclaration;
        Assert.NotNull(transformFunc);
        Assert.Equal(2, transformFunc.TypeParameters.Count);
        Assert.Equal(2, transformFunc.Constraints.Count);
    }

    [Fact]
    public void TestMethodOverloading()
    {
        var source = @"
            class Calculator {
                func Add(x: int): int {
                    return x + 1
                }

                func Add(x: int, y: int): int {
                    return x + y
                }

                func Add(x: double, y: double): double {
                    return x + y
                }
            }
        ";

        var cu = Parse(source);
        var calcClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(calcClass);
        Assert.Equal(3, calcClass.Members.Count);

        var method1 = calcClass.Members[0] as FunctionDeclaration;
        var method2 = calcClass.Members[1] as FunctionDeclaration;
        var method3 = calcClass.Members[2] as FunctionDeclaration;

        Assert.Equal("Add", method1!.Name);
        Assert.Equal("Add", method2!.Name);
        Assert.Equal("Add", method3!.Name);

        Assert.Single(method1.Parameters);
        Assert.Equal(2, method2.Parameters.Count);
        Assert.Equal(2, method3.Parameters.Count);
    }

    [Fact]
    public void TestPropertyWithGetSet()
    {
        var source = @"
            class Counter {
                count: int

                Count: int {
                    get { return count }
                    set { count = value }
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal(2, classDecl.Members.Count);

        // First member should be a field
        var field = classDecl.Members[0] as FieldDeclaration;
        Assert.NotNull(field);
        Assert.Equal("count", field.Name);

        // Second member should be a property with get/set
        var property = classDecl.Members[1] as PropertyDeclaration;
        Assert.NotNull(property);
        Assert.Equal("Count", property.Name);
        Assert.NotNull(property.GetBody);
        Assert.NotNull(property.SetBody);
    }

    [Fact]
    public void TestPropertyWithGetOnly()
    {
        var source = @"
            class Data {
                value: int

                Value: int {
                    get { return value }
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        var property = classDecl.Members[1] as PropertyDeclaration;
        Assert.NotNull(property);
        Assert.Equal("Value", property.Name);
        Assert.NotNull(property.GetBody);
        Assert.Null(property.SetBody);
    }

    [Fact]
    public void TestPropertyWithSetOnly()
    {
        var source = @"
            class Logger {
                message: string

                Message: string {
                    set {
                        message = value
                        Console.WriteLine(value)
                    }
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        var property = classDecl.Members[1] as PropertyDeclaration;
        Assert.NotNull(property);
        Assert.Equal("Message", property.Name);
        Assert.Null(property.GetBody);
        Assert.NotNull(property.SetBody);
    }

    [Fact]
    public void TestNestedClass()
    {
        var source = @"
            class Outer {
                Name: string

                class Inner {
                    Value: int
                }
            }
        ";

        var cu = Parse(source);
        var outerClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(outerClass);
        Assert.Equal("Outer", outerClass.Name);
        Assert.Equal(2, outerClass.Members.Count);

        var field = outerClass.Members[0] as FieldDeclaration;
        Assert.NotNull(field);
        Assert.Equal("Name", field.Name);

        var innerClass = outerClass.Members[1] as ClassDeclaration;
        Assert.NotNull(innerClass);
        Assert.Equal("Inner", innerClass.Name);
        Assert.Single(innerClass.Members);
    }

    [Fact]
    public void TestNestedEnum()
    {
        var source = @"
            class Container {
                enum Status {
                    Active,
                    Inactive
                }

                CurrentStatus: Status
            }
        ";

        var cu = Parse(source);
        var containerClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(containerClass);
        Assert.Equal(2, containerClass.Members.Count);

        var nestedEnum = containerClass.Members[0] as EnumDeclaration;
        Assert.NotNull(nestedEnum);
        Assert.Equal("Status", nestedEnum.Name);
        Assert.Equal(2, nestedEnum.Members.Count);

        var field = containerClass.Members[1] as FieldDeclaration;
        Assert.NotNull(field);
        Assert.Equal("CurrentStatus", field.Name);
    }

    [Fact]
    public void TestMultiLineTemplateString()
    {
        var source = @"
            func Test() {
                template := """"""
                This is a multi-line
                string literal
                with multiple lines
                """"""
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        var stringLiteral = varDecl.Initializer as StringLiteralExpression;
        Assert.NotNull(stringLiteral);
        Assert.Contains("multi-line", stringLiteral.Value);
    }

    [Fact]
    public void TestMatchExpressionWithGuard()
    {
        var source = @"
            func Test() {
                result := match x {
                    n when n > 0 => ""positive"",
                    n when n < 0 => ""negative"",
                    _ => ""zero""
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
        Assert.Equal(3, matchExpr.Cases.Count);

        // First case: n when n > 0
        var firstCase = matchExpr.Cases[0];
        Assert.IsType<IdentifierPattern>(firstCase.Pattern);
        Assert.NotNull(firstCase.Guard);
        Assert.IsType<BinaryExpression>(firstCase.Guard);

        // Second case: n when n < 0
        var secondCase = matchExpr.Cases[1];
        Assert.IsType<IdentifierPattern>(secondCase.Pattern);
        Assert.NotNull(secondCase.Guard);
        Assert.IsType<BinaryExpression>(secondCase.Guard);

        // Third case: _ (no guard)
        var thirdCase = matchExpr.Cases[2];
        Assert.IsType<IdentifierPattern>(thirdCase.Pattern);
        Assert.Null(thirdCase.Guard);
    }

    [Fact]
    public void TestMatchExpressionWithUnionPatternAndGuard()
    {
        var source = @"
            func Test() {
                msg := match result {
                    Result.Success { value } when value > 10 => ""big success"",
                    Result.Success { value } => ""small success"",
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
        Assert.Equal(3, matchExpr.Cases.Count);

        // First case has guard
        var firstCase = matchExpr.Cases[0];
        Assert.IsType<UnionCasePattern>(firstCase.Pattern);
        Assert.NotNull(firstCase.Guard);

        // Second case has no guard
        var secondCase = matchExpr.Cases[1];
        Assert.IsType<UnionCasePattern>(secondCase.Pattern);
        Assert.Null(secondCase.Guard);

        // Third case has no guard
        var thirdCase = matchExpr.Cases[2];
        Assert.IsType<UnionCasePattern>(thirdCase.Pattern);
        Assert.Null(thirdCase.Guard);
    }

    [Fact]
    public void TestPrintStatement()
    {
        var source = @"
func main() {
    print ""Hello""
    print $""Value: {x}""
}
        ";

        var cu = Parse(source);
        var func = Assert.Single(cu.Declarations.OfType<FunctionDeclaration>());
        var block = Assert.IsType<BlockStatement>(func.Body);
        Assert.Equal(2, block.Statements.Count);

        var printStmt1 = Assert.IsType<PrintStatement>(block.Statements[0]);
        Assert.IsType<StringLiteralExpression>(printStmt1.Value);

        var printStmt2 = Assert.IsType<PrintStatement>(block.Statements[1]);
        Assert.IsType<StringLiteralExpression>(printStmt2.Value);
    }

    [Fact]
    public void TestNameofExpression()
    {
        var source = @"
func main() {
    name := nameof(myVariable)
    prop := nameof(person.Name)
}
        ";

        var cu = Parse(source);
        var func = Assert.Single(cu.Declarations.OfType<FunctionDeclaration>());
        var block = Assert.IsType<BlockStatement>(func.Body);
        Assert.Equal(2, block.Statements.Count);

        // Test nameof(myVariable)
        var varDecl1 = Assert.IsType<VariableDeclarationStatement>(block.Statements[0]);
        var nameof1 = Assert.IsType<NameofExpression>(varDecl1.Initializer);
        Assert.IsType<IdentifierExpression>(nameof1.Target);

        // Test nameof(person.Name)
        var varDecl2 = Assert.IsType<VariableDeclarationStatement>(block.Statements[1]);
        var nameof2 = Assert.IsType<NameofExpression>(varDecl2.Initializer);
        Assert.IsType<MemberAccessExpression>(nameof2.Target);
    }

    [Fact]
    public void TestTypeofExpression()
    {
        var source = @"
func main() {
    t1 := typeof(int)
    t2 := typeof(Person)
    t3 := typeof(List<string>)
}
        ";

        var cu = Parse(source);
        var func = Assert.Single(cu.Declarations.OfType<FunctionDeclaration>());
        var block = Assert.IsType<BlockStatement>(func.Body);
        Assert.Equal(3, block.Statements.Count);

        // Test typeof(int)
        var varDecl1 = Assert.IsType<VariableDeclarationStatement>(block.Statements[0]);
        var typeof1 = Assert.IsType<TypeOfExpression>(varDecl1.Initializer);
        var simpleType1 = Assert.IsType<SimpleTypeReference>(typeof1.Type);
        Assert.Equal("int", simpleType1.Name);

        // Test typeof(Person)
        var varDecl2 = Assert.IsType<VariableDeclarationStatement>(block.Statements[1]);
        var typeof2 = Assert.IsType<TypeOfExpression>(varDecl2.Initializer);
        var simpleType2 = Assert.IsType<SimpleTypeReference>(typeof2.Type);
        Assert.Equal("Person", simpleType2.Name);

        // Test typeof(List<string>)
        var varDecl3 = Assert.IsType<VariableDeclarationStatement>(block.Statements[2]);
        var typeof3 = Assert.IsType<TypeOfExpression>(varDecl3.Initializer);
        var genericType = Assert.IsType<GenericTypeReference>(typeof3.Type);
        Assert.Equal("List", genericType.Name);
    }

    [Fact]
    public void TestCheckedExpression()
    {
        var source = @"
func main() {
    result := checked(a + b)
    overflow := checked(int.MaxValue + 1)
}
        ";

        var cu = Parse(source);
        var func = Assert.Single(cu.Declarations.OfType<FunctionDeclaration>());
        var block = Assert.IsType<BlockStatement>(func.Body);
        Assert.Equal(2, block.Statements.Count);

        // Test checked(a + b)
        var varDecl1 = Assert.IsType<VariableDeclarationStatement>(block.Statements[0]);
        var checked1 = Assert.IsType<CheckedExpression>(varDecl1.Initializer);
        var binary1 = Assert.IsType<BinaryExpression>(checked1.Expression);
        Assert.Equal(BinaryOperator.Add, binary1.Operator);

        // Test checked(int.MaxValue + 1)
        var varDecl2 = Assert.IsType<VariableDeclarationStatement>(block.Statements[1]);
        var checked2 = Assert.IsType<CheckedExpression>(varDecl2.Initializer);
        var binary2 = Assert.IsType<BinaryExpression>(checked2.Expression);
        Assert.Equal(BinaryOperator.Add, binary2.Operator);
    }

    [Fact]
    public void TestUncheckedExpression()
    {
        var source = @"
func main() {
    result := unchecked(a - b)
    wrap := unchecked(int.MinValue - 1)
}
        ";

        var cu = Parse(source);
        var func = Assert.Single(cu.Declarations.OfType<FunctionDeclaration>());
        var block = Assert.IsType<BlockStatement>(func.Body);
        Assert.Equal(2, block.Statements.Count);

        // Test unchecked(a - b)
        var varDecl1 = Assert.IsType<VariableDeclarationStatement>(block.Statements[0]);
        var unchecked1 = Assert.IsType<UncheckedExpression>(varDecl1.Initializer);
        var binary1 = Assert.IsType<BinaryExpression>(unchecked1.Expression);
        Assert.Equal(BinaryOperator.Subtract, binary1.Operator);

        // Test unchecked(int.MinValue - 1)
        var varDecl2 = Assert.IsType<VariableDeclarationStatement>(block.Statements[1]);
        var unchecked2 = Assert.IsType<UncheckedExpression>(varDecl2.Initializer);
        var binary2 = Assert.IsType<BinaryExpression>(unchecked2.Expression);
        Assert.Equal(BinaryOperator.Subtract, binary2.Operator);
    }

    [Fact]
    public void TestExpressionBodiedProperty()
    {
        var source = @"
            class Person {
                FirstName: string
                LastName: string
                FullName: string => FirstName + "" "" + LastName
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal(3, classDecl.Members.Count);

        // FullName should be a PropertyDeclaration with ExpressionBody
        var prop = classDecl.Members[2] as PropertyDeclaration;
        Assert.NotNull(prop);
        Assert.Equal("FullName", prop.Name);
        Assert.NotNull(prop.Type);  // Explicit type required
        var simpleType = Assert.IsType<SimpleTypeReference>(prop.Type);
        Assert.Equal("string", simpleType.Name);
        Assert.Null(prop.GetBody);
        Assert.Null(prop.SetBody);
        Assert.NotNull(prop.ExpressionBody);

        var binaryExpr = Assert.IsType<BinaryExpression>(prop.ExpressionBody);
        Assert.Equal(BinaryOperator.Add, binaryExpr.Operator);
    }

    [Fact]
    public void TestExpressionBodiedPropertyWithExplicitType()
    {
        var source = @"
            class Calculator {
                Value: int
                DoubleValue: int => Value * 2
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal(2, classDecl.Members.Count);

        var prop = classDecl.Members[1] as PropertyDeclaration;
        Assert.NotNull(prop);
        Assert.Equal("DoubleValue", prop.Name);
        Assert.NotNull(prop.Type);  // Explicit type
        var simpleType = Assert.IsType<SimpleTypeReference>(prop.Type);
        Assert.Equal("int", simpleType.Name);
        Assert.NotNull(prop.ExpressionBody);
    }

    [Fact]
    public void TestExpressionBodiedMethod()
    {
        var source = @"
            class Calculator {
                func Add(a: int, b: int): int => a + b
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Single(classDecl.Members);

        var func = classDecl.Members[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Equal("Add", func.Name);
        Assert.Equal(2, func.Parameters.Count);
        Assert.NotNull(func.ReturnType);
        Assert.Null(func.Body);  // No block body
        Assert.NotNull(func.ExpressionBody);

        var binaryExpr = Assert.IsType<BinaryExpression>(func.ExpressionBody);
        Assert.Equal(BinaryOperator.Add, binaryExpr.Operator);
    }

    [Fact]
    public void TestExpressionBodiedMethodWithComplexExpression()
    {
        var source = @"
            class Calculator {
                func Square(x: int): int => x * x
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Single(classDecl.Members);

        var func = classDecl.Members[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Equal("Square", func.Name);
        Assert.NotNull(func.ReturnType);
        Assert.NotNull(func.ExpressionBody);
    }

    [Fact]
    public void TestRelationalPattern()
    {
        var source = "func classify(age: int): string {\n" +
                     "    result := match age {\n" +
                     "        < 13 => \"child\",\n" +
                     "        >= 65 => \"senior\",\n" +
                     "        _ => \"adult\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);
        Assert.Equal(3, matchExpr.Cases.Count);

        // First case: < 13
        var firstCase = matchExpr.Cases[0];
        var firstPattern = Assert.IsType<RelationalPattern>(firstCase.Pattern);
        Assert.Equal("<", firstPattern.Operator);
        Assert.IsType<IntLiteralExpression>(firstPattern.Value);

        // Second case: >= 65
        var secondCase = matchExpr.Cases[1];
        var secondPattern = Assert.IsType<RelationalPattern>(secondCase.Pattern);
        Assert.Equal(">=", secondPattern.Operator);
        Assert.IsType<IntLiteralExpression>(secondPattern.Value);

        // Third case: wildcard
        var thirdCase = matchExpr.Cases[2];
        Assert.IsType<IdentifierPattern>(thirdCase.Pattern);
    }

    [Fact]
    public void TestAndPattern()
    {
        var source = @"
            func check(x: int): bool {
                result := match x {
                    > 0 and < 100 => true,
                    _ => false
                }
                return result
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var andPattern = Assert.IsType<AndPattern>(firstCase.Pattern);
        Assert.IsType<RelationalPattern>(andPattern.Left);
        Assert.IsType<RelationalPattern>(andPattern.Right);
    }

    [Fact]
    public void TestOrPattern()
    {
        var source = @"
            func check(x: int): bool {
                result := match x {
                    < 0 or > 100 => true,
                    _ => false
                }
                return result
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var orPattern = Assert.IsType<OrPattern>(firstCase.Pattern);
        Assert.IsType<RelationalPattern>(orPattern.Left);
        Assert.IsType<RelationalPattern>(orPattern.Right);
    }

    [Fact]
    public void TestNotPattern()
    {
        var source = @"
            func check(x: int): bool {
                result := match x {
                    not 0 => true,
                    _ => false
                }
                return result
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var notPattern = Assert.IsType<NotPattern>(firstCase.Pattern);
        Assert.IsType<LiteralPattern>(notPattern.Pattern);
    }

    [Fact]
    public void TestPositionalPattern()
    {
        var source = "func check(point: (int, int)): string {\n" +
                     "    result := match point {\n" +
                     "        (0, 0) => \"origin\",\n" +
                     "        (0, _) => \"y-axis\",\n" +
                     "        (_, 0) => \"x-axis\",\n" +
                     "        _ => \"other\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);
        Assert.Equal(4, matchExpr.Cases.Count);

        // First case: (0, 0)
        var firstCase = matchExpr.Cases[0];
        var positionalPattern = Assert.IsType<PositionalPattern>(firstCase.Pattern);
        Assert.Equal(2, positionalPattern.Patterns.Count);
        Assert.IsType<LiteralPattern>(positionalPattern.Patterns[0]);
        Assert.IsType<LiteralPattern>(positionalPattern.Patterns[1]);
    }

    [Fact]
    public void TestListPatternEmpty()
    {
        var source = "func check(arr: int[]): bool {\n" +
                     "    result := match arr {\n" +
                     "        [] => true,\n" +
                     "        _ => false\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var listPattern = Assert.IsType<ListPattern>(firstCase.Pattern);
        Assert.Empty(listPattern.Elements);
    }

    [Fact]
    public void TestListPatternLiteral()
    {
        var source = "func check(arr: int[]): bool {\n" +
                     "    result := match arr {\n" +
                     "        [1, 2, 3] => true,\n" +
                     "        _ => false\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var listPattern = Assert.IsType<ListPattern>(firstCase.Pattern);
        Assert.Equal(3, listPattern.Elements.Count);
        Assert.All(listPattern.Elements, e => Assert.IsType<LiteralPattern>(e));
    }

    [Fact]
    public void TestListPatternWithSlice()
    {
        var source = "func check(arr: int[]): int {\n" +
                     "    result := match arr {\n" +
                     "        [first, ..] => first,\n" +
                     "        _ => 0\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var listPattern = Assert.IsType<ListPattern>(firstCase.Pattern);
        Assert.Equal(2, listPattern.Elements.Count);

        var firstElement = Assert.IsType<IdentifierPattern>(listPattern.Elements[0]);
        Assert.Equal("first", firstElement.Name);

        var slicePattern = Assert.IsType<SlicePattern>(listPattern.Elements[1]);
        Assert.Null(slicePattern.BindingName);
    }

    [Fact]
    public void TestListPatternWithNamedSlice()
    {
        var source = "func check(arr: int[]): int[] {\n" +
                     "    result := match arr {\n" +
                     "        [first, .. rest] => rest,\n" +
                     "        _ => []\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var listPattern = Assert.IsType<ListPattern>(firstCase.Pattern);
        Assert.Equal(2, listPattern.Elements.Count);

        var slicePattern = Assert.IsType<SlicePattern>(listPattern.Elements[1]);
        Assert.Equal("rest", slicePattern.BindingName);
    }

    [Fact]
    public void TestListPatternWithMiddleSlice()
    {
        var source = "func check(arr: int[]): (int, int) {\n" +
                     "    result := match arr {\n" +
                     "        [first, .. middle, last] => (first, last),\n" +
                     "        _ => (0, 0)\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var listPattern = Assert.IsType<ListPattern>(firstCase.Pattern);
        Assert.Equal(3, listPattern.Elements.Count);

        Assert.IsType<IdentifierPattern>(listPattern.Elements[0]);
        var slicePattern = Assert.IsType<SlicePattern>(listPattern.Elements[1]);
        Assert.Equal("middle", slicePattern.BindingName);
        Assert.IsType<IdentifierPattern>(listPattern.Elements[2]);
    }

    [Fact]
    public void TestComplexCombinedPatterns()
    {
        var source = "func check(value: int): string {\n" +
                     "    result := match value {\n" +
                     "        (> 0 and < 10) or (> 90 and < 100) => \"valid\",\n" +
                     "        not (>= 50 and <= 60) => \"not middle\",\n" +
                     "        _ => \"other\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);
        Assert.Equal(3, matchExpr.Cases.Count);

        // First case: complex or pattern with parenthesized and patterns
        var firstCase = matchExpr.Cases[0];
        var orPattern = Assert.IsType<OrPattern>(firstCase.Pattern);
        Assert.IsType<PositionalPattern>(orPattern.Left);  // Parenthesized and pattern
        Assert.IsType<PositionalPattern>(orPattern.Right); // Parenthesized and pattern

        // Second case: not pattern with relational
        var secondCase = matchExpr.Cases[1];
        var notPattern = Assert.IsType<NotPattern>(secondCase.Pattern);
        Assert.IsType<PositionalPattern>(notPattern.Pattern);
    }

    [Fact]
    public void TestTypePatternSimple()
    {
        var source = "func check(obj: object): string {\n" +
                     "    result := match obj {\n" +
                     "        string s => s,\n" +
                     "        int n => n.ToString(),\n" +
                     "        _ => \"unknown\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);
        Assert.Equal(3, matchExpr.Cases.Count);

        // First case: string s
        var firstCase = matchExpr.Cases[0];
        var typePattern1 = Assert.IsType<TypePattern>(firstCase.Pattern);
        Assert.IsType<SimpleTypeReference>(typePattern1.Type);
        var simpleType1 = (SimpleTypeReference)typePattern1.Type;
        Assert.Equal("string", simpleType1.Name);
        Assert.Equal("s", typePattern1.BindingName);

        // Second case: int n
        var secondCase = matchExpr.Cases[1];
        var typePattern2 = Assert.IsType<TypePattern>(secondCase.Pattern);
        Assert.IsType<SimpleTypeReference>(typePattern2.Type);
        var simpleType2 = (SimpleTypeReference)typePattern2.Type;
        Assert.Equal("int", simpleType2.Name);
        Assert.Equal("n", typePattern2.BindingName);
    }

    [Fact]
    public void TestTypePatternWithQualifiedName()
    {
        var source = "func check(obj: object): string {\n" +
                     "    result := match obj {\n" +
                     "        System.String s => s,\n" +
                     "        _ => \"unknown\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var typePattern = Assert.IsType<TypePattern>(firstCase.Pattern);
        var simpleType = Assert.IsType<SimpleTypeReference>(typePattern.Type);
        Assert.Equal("System.String", simpleType.Name);
        Assert.Equal("s", typePattern.BindingName);
    }

    [Fact]
    public void TestTypePatternWithGuard()
    {
        var source = "func check(obj: object): string {\n" +
                     "    result := match obj {\n" +
                     "        string s when s.Length > 5 => \"long\",\n" +
                     "        string s => \"short\",\n" +
                     "        _ => \"not string\"\n" +
                     "    }\n" +
                     "    return result\n" +
                     "}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var firstCase = matchExpr.Cases[0];
        var typePattern = Assert.IsType<TypePattern>(firstCase.Pattern);
        Assert.Equal("s", typePattern.BindingName);
        Assert.NotNull(firstCase.Guard); // Has guard clause
    }

    [Fact]
    public void TestFileImport()
    {
        var source = @"
            import ""Models/Person""
        ";

        var cu = Parse(source);
        Assert.Single(cu.Imports);

        var fileImport = cu.Imports[0] as FileImport;
        Assert.NotNull(fileImport);
        Assert.Equal("Models/Person", fileImport.Path);
        Assert.Null(fileImport.Alias);
    }

    [Fact]
    public void TestFileImportWithAlias()
    {
        var source = @"
            import ""Services/Auth"" as AuthService
        ";

        var cu = Parse(source);
        Assert.Single(cu.Imports);

        var fileImport = cu.Imports[0] as FileImport;
        Assert.NotNull(fileImport);
        Assert.Equal("Services/Auth", fileImport.Path);
        Assert.Equal("AuthService", fileImport.Alias);
    }

    [Fact]
    public void TestNamespaceImport()
    {
        var source = @"
            import System.Collections.Generic
        ";

        var cu = Parse(source);
        Assert.Single(cu.Imports);

        var nsImport = cu.Imports[0] as NamespaceImport;
        Assert.NotNull(nsImport);
        Assert.Equal("System.Collections.Generic", nsImport.Namespace);
        Assert.Null(nsImport.Alias);
    }

    [Fact]
    public void TestNamespaceImportWithAlias()
    {
        var source = @"
            import System.Text.Json as Json
        ";

        var cu = Parse(source);
        Assert.Single(cu.Imports);

        var nsImport = cu.Imports[0] as NamespaceImport;
        Assert.NotNull(nsImport);
        Assert.Equal("System.Text.Json", nsImport.Namespace);
        Assert.Equal("Json", nsImport.Alias);
    }

    [Fact]
    public void TestMultipleImports()
    {
        var source = @"
            import ""Models/Person""
            import System.Linq
            import ""Services/Auth"" as AuthService
        ";

        var cu = Parse(source);
        Assert.Equal(3, cu.Imports.Count);

        var fileImport1 = cu.Imports[0] as FileImport;
        Assert.NotNull(fileImport1);
        Assert.Equal("Models/Person", fileImport1.Path);

        var nsImport = cu.Imports[1] as NamespaceImport;
        Assert.NotNull(nsImport);
        Assert.Equal("System.Linq", nsImport.Namespace);

        var fileImport2 = cu.Imports[2] as FileImport;
        Assert.NotNull(fileImport2);
        Assert.Equal("Services/Auth", fileImport2.Path);
        Assert.Equal("AuthService", fileImport2.Alias);
    }

    [Fact]
    public void TestNestedPropertyPatternWithLiteral()
    {
        var source = @"
            func Test() {
                result := match person {
                    { Address: { City: ""NYC"" } } => ""New Yorker""
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
        Assert.Single(matchExpr.Cases);

        var matchCase = matchExpr.Cases[0];
        var objectPattern = matchCase.Pattern as ObjectPattern;
        Assert.NotNull(objectPattern);
        Assert.Single(objectPattern.Properties);

        // Verify Address property has nested pattern
        var addressProp = objectPattern.Properties[0];
        Assert.Equal("Address", addressProp.Name);
        Assert.NotNull(addressProp.Pattern);
        Assert.Null(addressProp.BindingName);

        // Verify nested object pattern
        var nestedObj = addressProp.Pattern as ObjectPattern;
        Assert.NotNull(nestedObj);
        Assert.Single(nestedObj.Properties);

        // Verify City property has literal pattern
        var cityProp = nestedObj.Properties[0];
        Assert.Equal("City", cityProp.Name);
        Assert.NotNull(cityProp.Pattern);

        var cityLiteral = cityProp.Pattern as LiteralPattern;
        Assert.NotNull(cityLiteral);
    }

    [Fact]
    public void TestNestedPropertyPatternWithBinding()
    {
        var source = @"
            func Test() {
                result := match person {
                    { Address: { City: city, State: ""NY"" } } => city
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

        var objectPattern = matchExpr.Cases[0].Pattern as ObjectPattern;
        Assert.NotNull(objectPattern);

        var addressProp = objectPattern.Properties[0];
        var nestedObj = addressProp.Pattern as ObjectPattern;
        Assert.NotNull(nestedObj);
        Assert.Equal(2, nestedObj.Properties.Count);

        // City property with identifier binding
        var cityProp = nestedObj.Properties[0];
        Assert.Equal("City", cityProp.Name);
        Assert.NotNull(cityProp.Pattern);
        var cityIdent = cityProp.Pattern as IdentifierPattern;
        Assert.NotNull(cityIdent);
        Assert.Equal("city", cityIdent.Name);

        // State property with literal
        var stateProp = nestedObj.Properties[1];
        Assert.Equal("State", stateProp.Name);
        Assert.NotNull(stateProp.Pattern);
        var stateLiteral = stateProp.Pattern as LiteralPattern;
        Assert.NotNull(stateLiteral);
    }

    [Fact]
    public void TestThreeLevelNestedPropertyPattern()
    {
        var source = @"
            func Test() {
                result := match company {
                    { HQ: { Address: { City: ""NYC"" } } } => ""NYC HQ""
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var objectPattern = matchExpr.Cases[0].Pattern as ObjectPattern;
        Assert.NotNull(objectPattern);

        // Level 1: HQ property
        var hqProp = objectPattern.Properties[0];
        Assert.Equal("HQ", hqProp.Name);
        var level2 = hqProp.Pattern as ObjectPattern;
        Assert.NotNull(level2);

        // Level 2: Address property
        var addressProp = level2.Properties[0];
        Assert.Equal("Address", addressProp.Name);
        var level3 = addressProp.Pattern as ObjectPattern;
        Assert.NotNull(level3);

        // Level 3: City property
        var cityProp = level3.Properties[0];
        Assert.Equal("City", cityProp.Name);
        var cityLiteral = cityProp.Pattern as LiteralPattern;
        Assert.NotNull(cityLiteral);
    }

    [Fact]
    public void TestUnionCaseWithNestedPropertyPattern()
    {
        var source = @"
            func Test() {
                result := match result {
                    Result.Success { value: { Count: count } } => count,
                    _ => 0
                }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        var matchExpr = varDecl.Initializer as MatchExpression;
        Assert.NotNull(matchExpr);

        var unionPattern = matchExpr.Cases[0].Pattern as UnionCasePattern;
        Assert.NotNull(unionPattern);
        Assert.Equal("Result.Success", unionPattern.CaseName);
        Assert.Single(unionPattern.Properties);

        // Verify value property has nested pattern
        var valueProp = unionPattern.Properties[0];
        Assert.Equal("value", valueProp.Name);
        Assert.NotNull(valueProp.Pattern);

        var nestedObj = valueProp.Pattern as ObjectPattern;
        Assert.NotNull(nestedObj);
        Assert.Single(nestedObj.Properties);

        var countProp = nestedObj.Properties[0];
        Assert.Equal("Count", countProp.Name);
        var countIdent = countProp.Pattern as IdentifierPattern;
        Assert.NotNull(countIdent);
        Assert.Equal("count", countIdent.Name);
    }

    [Fact]
    public void TestTestDeclaration()
    {
        var source = @"
test ""should add two numbers"" {
    result := Add(2, 3)
    assert result == 5
}";

        var lexer = new Lexer(source);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var unit = parser.ParseCompilationUnit();

        Assert.Single(unit.Declarations);
        var testDecl = unit.Declarations[0] as TestDeclaration;
        Assert.NotNull(testDecl);
        Assert.Equal("should add two numbers", testDecl.Description);
        Assert.Equal(2, testDecl.Body.Statements.Count);

        // Check variable declaration
        var varDecl = testDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        Assert.Equal("result", varDecl.Name);

        // Check assert statement
        var assertStmt = testDecl.Body.Statements[1] as AssertStatement;
        Assert.NotNull(assertStmt);
        var binExpr = assertStmt.Condition as BinaryExpression;
        Assert.NotNull(binExpr);
        Assert.Equal(BinaryOperator.Equal, binExpr.Operator);
    }

    [Fact]
    public void TestAssertStatement()
    {
        var source = @"
func TestFunc() {
    value := 10
    assert value > 5
    assert value != null
}";

        var lexer = new Lexer(source);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var unit = parser.ParseCompilationUnit();

        var funcDecl = unit.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.NotNull(funcDecl.Body);
        Assert.Equal(3, funcDecl.Body.Statements.Count);

        // First assert: value > 5
        var assert1 = funcDecl.Body.Statements[1] as AssertStatement;
        Assert.NotNull(assert1);
        var binExpr1 = assert1.Condition as BinaryExpression;
        Assert.NotNull(binExpr1);
        Assert.Equal(BinaryOperator.Greater, binExpr1.Operator);

        // Second assert: value != null
        var assert2 = funcDecl.Body.Statements[2] as AssertStatement;
        Assert.NotNull(assert2);
        var binExpr2 = assert2.Condition as BinaryExpression;
        Assert.NotNull(binExpr2);
        Assert.Equal(BinaryOperator.NotEqual, binExpr2.Operator);
    }

    [Fact]
    public void TestOperatorOverloadBinaryPlus()
    {
        var source = @"
            class Vector {
                X: int
                Y: int

                static func operator +(a: Vector, b: Vector): Vector {
                    return new Vector { X: a.X + b.X, Y: a.Y + b.Y }
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal("Vector", classDecl.Name);

        // Find operator overload
        var opFunc = classDecl.Members.OfType<FunctionDeclaration>().FirstOrDefault(f => f.IsOperatorOverload);
        Assert.NotNull(opFunc);
        Assert.True(opFunc.IsOperatorOverload);
        Assert.Equal("+", opFunc.OperatorSymbol);
        Assert.Equal(2, opFunc.Parameters.Count);
        Assert.Equal("a", opFunc.Parameters[0].Name);
        Assert.Equal("b", opFunc.Parameters[1].Name);
        Assert.True(opFunc.Modifiers.HasFlag(Modifiers.Static));
    }

    [Fact]
    public void TestOperatorOverloadUnaryMinus()
    {
        var source = @"
            class Vector {
                X: int
                Y: int

                static func operator -(v: Vector): Vector {
                    return new Vector { X: -v.X, Y: -v.Y }
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        var opFunc = classDecl.Members.OfType<FunctionDeclaration>().FirstOrDefault(f => f.IsOperatorOverload);
        Assert.NotNull(opFunc);
        Assert.True(opFunc.IsOperatorOverload);
        Assert.Equal("-", opFunc.OperatorSymbol);
        Assert.Equal(1, opFunc.Parameters.Count);
        Assert.Equal("v", opFunc.Parameters[0].Name);
    }

    [Fact]
    public void TestOperatorOverloadComparison()
    {
        var source = @"
            class Money {
                Amount: decimal

                static func operator ==(a: Money, b: Money): bool {
                    return a.Amount == b.Amount
                }

                static func operator !=(a: Money, b: Money): bool {
                    return a.Amount != b.Amount
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        var operators = classDecl.Members.OfType<FunctionDeclaration>().Where(f => f.IsOperatorOverload).ToList();
        Assert.Equal(2, operators.Count);

        var equalOp = operators.FirstOrDefault(f => f.OperatorSymbol == "==");
        Assert.NotNull(equalOp);
        Assert.Equal(2, equalOp.Parameters.Count);

        var notEqualOp = operators.FirstOrDefault(f => f.OperatorSymbol == "!=");
        Assert.NotNull(notEqualOp);
        Assert.Equal(2, notEqualOp.Parameters.Count);
    }

    [Fact]
    public void TestOperatorOverloadBitwise()
    {
        var source = @"
            struct Flags {
                Value: int

                static func operator &(a: Flags, b: Flags): Flags {
                    return new Flags { Value: a.Value & b.Value }
                }

                static func operator |(a: Flags, b: Flags): Flags {
                    return new Flags { Value: a.Value | b.Value }
                }
            }
        ";

        var cu = Parse(source);
        var structDecl = cu.Declarations[0] as StructDeclaration;
        Assert.NotNull(structDecl);

        var operators = structDecl.Members.OfType<FunctionDeclaration>().Where(f => f.IsOperatorOverload).ToList();
        Assert.Equal(2, operators.Count);

        var andOp = operators.FirstOrDefault(f => f.OperatorSymbol == "&");
        Assert.NotNull(andOp);

        var orOp = operators.FirstOrDefault(f => f.OperatorSymbol == "|");
        Assert.NotNull(orOp);
    }

    [Fact]
    public void TestImplicitConversionOperator()
    {
        var source = @"
            class Celsius {
                Value: double

                implicit operator Fahrenheit(c: Celsius) {
                    return new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        var conversion = classDecl.Members.OfType<FunctionDeclaration>().FirstOrDefault(f => f.IsConversionOperator);
        Assert.NotNull(conversion);
        Assert.True(conversion.IsConversionOperator);
        Assert.True(conversion.IsImplicitConversion);
        Assert.Equal("Fahrenheit", ((SimpleTypeReference)conversion.ReturnType!).Name);
        Assert.Single(conversion.Parameters);
        Assert.Equal("Celsius", ((SimpleTypeReference)conversion.Parameters[0].Type).Name);
    }

    [Fact]
    public void TestExplicitConversionOperator()
    {
        var source = @"
            struct Fraction {
                Numerator: int
                Denominator: int

                explicit operator double(f: Fraction) {
                    return f.Numerator / (double)f.Denominator
                }
            }
        ";

        var cu = Parse(source);
        var structDecl = cu.Declarations[0] as StructDeclaration;
        Assert.NotNull(structDecl);

        var conversion = structDecl.Members.OfType<FunctionDeclaration>().FirstOrDefault(f => f.IsConversionOperator);
        Assert.NotNull(conversion);
        Assert.True(conversion.IsConversionOperator);
        Assert.False(conversion.IsImplicitConversion);
        Assert.Equal("double", ((SimpleTypeReference)conversion.ReturnType!).Name);
        Assert.Single(conversion.Parameters);
        Assert.Equal("Fraction", ((SimpleTypeReference)conversion.Parameters[0].Type).Name);
    }

    [Fact]
    public void TestIndexFromEndExpression()
    {
        var source = @"
            func Test() {
                arr := [1, 2, 3, 4, 5]
                lastItem := arr[^1]
                secondLast := arr[^2]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        var vars = funcDecl.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();
        Assert.Equal(3, vars.Count);

        // Check lastItem uses index from end
        var lastItemDecl = vars[1];
        Assert.Equal("lastItem", lastItemDecl.Name);
        var indexAccess = lastItemDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);

        var indexExpr = indexAccess.Index as UnaryExpression;
        Assert.NotNull(indexExpr);
        Assert.Equal(UnaryOperator.IndexFromEnd, indexExpr.Operator);

        var indexValue = indexExpr.Operand as IntLiteralExpression;
        Assert.NotNull(indexValue);
        Assert.Equal("1", indexValue.Value);
    }

    [Fact]
    public void TestRangeExpression()
    {
        var source = @"
            func Test() {
                arr := [1, 2, 3, 4, 5]
                slice := arr[1..4]
                slice2 := arr[0..3]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        var vars = funcDecl.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();
        Assert.Equal(3, vars.Count);

        // Check slice uses range
        var sliceDecl = vars[1];
        Assert.Equal("slice", sliceDecl.Name);
        var indexAccess = sliceDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);

        var rangeExpr = indexAccess.Index as RangeExpression;
        Assert.NotNull(rangeExpr);

        var left = rangeExpr.Start as IntLiteralExpression;
        Assert.NotNull(left);
        Assert.Equal("1", left.Value);

        var right = rangeExpr.End as IntLiteralExpression;
        Assert.NotNull(right);
        Assert.Equal("4", right.Value);
    }

    [Fact]
    public void TestRangeWithIndexFromEnd()
    {
        var source = @"
            func Test() {
                arr := [1, 2, 3, 4, 5]
                middle := arr[1..^1]
                firstToSecondLast := arr[0..^2]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        var vars = funcDecl.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();
        Assert.Equal(3, vars.Count);

        // Check middle uses range with index from end
        var middleDecl = vars[1];
        Assert.Equal("middle", middleDecl.Name);
        var indexAccess = middleDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);

        var rangeExpr = indexAccess.Index as RangeExpression;
        Assert.NotNull(rangeExpr);

        var left = rangeExpr.Start as IntLiteralExpression;
        Assert.NotNull(left);
        Assert.Equal("1", left.Value);

        var right = rangeExpr.End as UnaryExpression;
        Assert.NotNull(right);
        Assert.Equal(UnaryOperator.IndexFromEnd, right.Operator);
    }

    [Fact]
    public void TestOpenEndedRangeToEnd()
    {
        var source = @"
            func Test() {
                arr := [1, 2, 3, 4, 5]
                slice := arr[..3]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        var vars = funcDecl.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();

        var sliceDecl = vars[1];
        Assert.Equal("slice", sliceDecl.Name);
        var indexAccess = sliceDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);

        var rangeExpr = indexAccess.Index as RangeExpression;
        Assert.NotNull(rangeExpr);
        Assert.Null(rangeExpr.Start);  // Open-ended start

        var end = rangeExpr.End as IntLiteralExpression;
        Assert.NotNull(end);
        Assert.Equal("3", end.Value);
    }

    [Fact]
    public void TestOpenEndedRangeFromStart()
    {
        var source = @"
            func Test() {
                arr := [1, 2, 3, 4, 5]
                slice := arr[2..]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        var vars = funcDecl.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();

        var sliceDecl = vars[1];
        Assert.Equal("slice", sliceDecl.Name);
        var indexAccess = sliceDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);

        var rangeExpr = indexAccess.Index as RangeExpression;
        Assert.NotNull(rangeExpr);

        var start = rangeExpr.Start as IntLiteralExpression;
        Assert.NotNull(start);
        Assert.Equal("2", start.Value);

        Assert.Null(rangeExpr.End);  // Open-ended end
    }

    [Fact]
    public void TestFullyOpenRange()
    {
        var source = @"
            func Test() {
                arr := [1, 2, 3, 4, 5]
                slice := arr[..]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        var vars = funcDecl.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();

        var sliceDecl = vars[1];
        Assert.Equal("slice", sliceDecl.Name);
        var indexAccess = sliceDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);

        var rangeExpr = indexAccess.Index as RangeExpression;
        Assert.NotNull(rangeExpr);
        Assert.Null(rangeExpr.Start);  // Fully open
        Assert.Null(rangeExpr.End);     // Fully open
    }

    [Fact]
    public void TestPreprocessorDirectiveTopLevel()
    {
        var source = @"
#if DEBUG
class DebugHelper {
    DebugFlag: bool = true
}
#endif
";

        var cu = Parse(source);
        Assert.Equal(3, cu.Declarations.Count);

        var preprocessor1 = cu.Declarations[0] as PreprocessorDeclaration;
        Assert.NotNull(preprocessor1);
        Assert.Equal("#if DEBUG", preprocessor1.Directive);

        var classDecl = cu.Declarations[1] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal("DebugHelper", classDecl.Name);

        var preprocessor2 = cu.Declarations[2] as PreprocessorDeclaration;
        Assert.NotNull(preprocessor2);
        Assert.Equal("#endif", preprocessor2.Directive);
    }

    [Fact]
    public void TestPreprocessorDirectiveInFunction()
    {
        var source = @"
func TestFunc() {
    #if DEBUG
    print ""Debug mode""
    #endif
}";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.NotNull(funcDecl.Body);
        Assert.Equal(3, funcDecl.Body.Statements.Count);

        var preprocessor1 = funcDecl.Body.Statements[0] as PreprocessorDirective;
        Assert.NotNull(preprocessor1);
        Assert.Equal("#if DEBUG", preprocessor1.Directive);

        var printStmt = funcDecl.Body.Statements[1] as PrintStatement;
        Assert.NotNull(printStmt);

        var preprocessor2 = funcDecl.Body.Statements[2] as PreprocessorDirective;
        Assert.NotNull(preprocessor2);
        Assert.Equal("#endif", preprocessor2.Directive);
    }

    [Fact]
    public void TestPreprocessorRegion()
    {
        var source = @"
#region Helper Functions
func Helper(): int {
    return 42
}
#endregion
";

        var cu = Parse(source);
        Assert.Equal(3, cu.Declarations.Count);

        var preprocessor1 = cu.Declarations[0] as PreprocessorDeclaration;
        Assert.NotNull(preprocessor1);
        Assert.Equal("#region Helper Functions", preprocessor1.Directive);

        var funcDecl = cu.Declarations[1] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var preprocessor2 = cu.Declarations[2] as PreprocessorDeclaration;
        Assert.NotNull(preprocessor2);
        Assert.Equal("#endregion", preprocessor2.Directive);
    }

    [Fact]
    public void TestPreprocessorDefine()
    {
        var source = @"
#define FEATURE_X
";

        var cu = Parse(source);
        Assert.Single(cu.Declarations);

        var preprocessor = cu.Declarations[0] as PreprocessorDeclaration;
        Assert.NotNull(preprocessor);
        Assert.Equal("#define FEATURE_X", preprocessor.Directive);
    }

    [Fact]
    public void TestRequiredProperty()
    {
        var source = @"
            class Person {
                required Name: string
                required Email: string
                Age: int = 0
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal("Person", classDecl.Name);

        var fields = classDecl.Members.OfType<FieldDeclaration>().ToList();
        Assert.Equal(3, fields.Count);

        var nameField = fields[0];
        Assert.Equal("Name", nameField.Name);
        Assert.True(nameField.Modifiers.HasFlag(Modifiers.Required));

        var emailField = fields[1];
        Assert.Equal("Email", emailField.Name);
        Assert.True(emailField.Modifiers.HasFlag(Modifiers.Required));

        var ageField = fields[2];
        Assert.Equal("Age", ageField.Name);
        Assert.False(ageField.Modifiers.HasFlag(Modifiers.Required));
    }

    [Fact]
    public void TestInitOnlyProperty()
    {
        var source = @"
            record Person {
                init Name: string
                init Age: int
            }
        ";

        var cu = Parse(source);
        var recordDecl = cu.Declarations[0] as RecordDeclaration;
        Assert.NotNull(recordDecl);
        Assert.Equal("Person", recordDecl.Name);

        var fields = recordDecl.Members.OfType<FieldDeclaration>().ToList();
        Assert.Equal(2, fields.Count);

        var nameField = fields[0];
        Assert.Equal("Name", nameField.Name);
        Assert.True(nameField.Modifiers.HasFlag(Modifiers.Init));

        var ageField = fields[1];
        Assert.Equal("Age", ageField.Name);
        Assert.True(ageField.Modifiers.HasFlag(Modifiers.Init));
    }

    [Fact]
    public void TestRequiredAndInitProperty()
    {
        var source = @"
            class User {
                required init Id: string
                required init Email: string
                Name: string = """"
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);

        var fields = classDecl.Members.OfType<FieldDeclaration>().ToList();
        Assert.Equal(3, fields.Count);

        var idField = fields[0];
        Assert.Equal("Id", idField.Name);
        Assert.True(idField.Modifiers.HasFlag(Modifiers.Required));
        Assert.True(idField.Modifiers.HasFlag(Modifiers.Init));

        var emailField = fields[1];
        Assert.Equal("Email", emailField.Name);
        Assert.True(emailField.Modifiers.HasFlag(Modifiers.Required));
        Assert.True(emailField.Modifiers.HasFlag(Modifiers.Init));

        var nameField = fields[2];
        Assert.Equal("Name", nameField.Name);
        Assert.False(nameField.Modifiers.HasFlag(Modifiers.Required));
        Assert.False(nameField.Modifiers.HasFlag(Modifiers.Init));
    }

    [Fact]
    public void TestRefParameter()
    {
        var source = "func Swap(ref a: int, ref b: int) { }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Equal("Swap", func.Name);
        Assert.Equal(2, func.Parameters.Count);

        Assert.Equal("a", func.Parameters[0].Name);
        Assert.Equal(ParameterModifier.Ref, func.Parameters[0].Modifier);

        Assert.Equal("b", func.Parameters[1].Name);
        Assert.Equal(ParameterModifier.Ref, func.Parameters[1].Modifier);
    }

    [Fact]
    public void TestOutParameter()
    {
        var source = "func TryParse(input: string, out result: int): bool { }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Equal("TryParse", func.Name);
        Assert.Equal(2, func.Parameters.Count);

        Assert.Equal("input", func.Parameters[0].Name);
        Assert.Equal(ParameterModifier.None, func.Parameters[0].Modifier);

        Assert.Equal("result", func.Parameters[1].Name);
        Assert.Equal(ParameterModifier.Out, func.Parameters[1].Modifier);
    }

    [Fact]
    public void TestParamsParameter()
    {
        var source = "func Sum(params numbers: int[]) { }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Equal("Sum", func.Name);
        Assert.Single(func.Parameters);

        Assert.Equal("numbers", func.Parameters[0].Name);
        Assert.Equal(ParameterModifier.Params, func.Parameters[0].Modifier);
        Assert.IsType<ArrayTypeReference>(func.Parameters[0].Type);
    }

    [Fact]
    public void TestParamsWithOtherParameters()
    {
        var source = "func Format(format: string, params args: object[]) { }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Equal("Format", func.Name);
        Assert.Equal(2, func.Parameters.Count);

        Assert.Equal("format", func.Parameters[0].Name);
        Assert.Equal(ParameterModifier.None, func.Parameters[0].Modifier);

        Assert.Equal("args", func.Parameters[1].Name);
        Assert.Equal(ParameterModifier.Params, func.Parameters[1].Modifier);
    }

    // C# 13 Params Collections Tests
    [Fact]
    public void TestParamsWithReadOnlySpan()
    {
        var source = "func Process(params items: ReadOnlySpan<int>) { }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Equal("Process", func.Name);
        Assert.Single(func.Parameters);
        Assert.Equal("items", func.Parameters[0].Name);
        Assert.Equal(ParameterModifier.Params, func.Parameters[0].Modifier);

        var genericType = Assert.IsType<GenericTypeReference>(func.Parameters[0].Type);
        Assert.Equal("ReadOnlySpan", genericType.Name);
    }

    [Fact]
    public void TestParamsWithSpan()
    {
        var source = "func Process(params items: Span<string>) { }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Single(func.Parameters);
        Assert.Equal(ParameterModifier.Params, func.Parameters[0].Modifier);

        var genericType = Assert.IsType<GenericTypeReference>(func.Parameters[0].Type);
        Assert.Equal("Span", genericType.Name);
    }

    [Fact]
    public void TestParamsWithIEnumerable()
    {
        var source = "func Sum(params numbers: IEnumerable<int>): int { return 0 }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Single(func.Parameters);
        Assert.Equal(ParameterModifier.Params, func.Parameters[0].Modifier);

        var genericType = Assert.IsType<GenericTypeReference>(func.Parameters[0].Type);
        Assert.Equal("IEnumerable", genericType.Name);
    }

    [Fact]
    public void TestParamsWithList()
    {
        var source = "func Process(params items: List<string>) { }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Single(func.Parameters);
        Assert.Equal(ParameterModifier.Params, func.Parameters[0].Modifier);

        var genericType = Assert.IsType<GenericTypeReference>(func.Parameters[0].Type);
        Assert.Equal("List", genericType.Name);
    }

    [Fact]
    public void TestParamsWithIReadOnlyList()
    {
        var source = "func Process(params items: IReadOnlyList<int>) { }";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        Assert.Single(func.Parameters);
        Assert.Equal(ParameterModifier.Params, func.Parameters[0].Modifier);

        var genericType = Assert.IsType<GenericTypeReference>(func.Parameters[0].Type);
        Assert.Equal("IReadOnlyList", genericType.Name);
    }

    [Fact]
    public void TestRefArgument()
    {
        var source = @"
            func Main() {
                x := 5
                Swap(ref x, ref x)
            }
        ";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        var block = func.Body as BlockStatement;
        Assert.NotNull(block);

        var callStmt = block.Statements[1] as ExpressionStatement;
        Assert.NotNull(callStmt);
        var call = callStmt.Expression as CallExpression;
        Assert.NotNull(call);

        Assert.Equal(2, call.Arguments.Count);
        Assert.Equal(ArgumentModifier.Ref, call.Arguments[0].Modifier);
        Assert.Equal(ArgumentModifier.Ref, call.Arguments[1].Modifier);
    }

    [Fact]
    public void TestOutArgument()
    {
        var source = @"
            func Main() {
                let result: int
                success := int.TryParse(""123"", out result)
            }
        ";
        var cu = Parse(source);
        var func = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(func);
        var block = func.Body as BlockStatement;
        Assert.NotNull(block);

        var varStmt = block.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(varStmt);
        var call = varStmt.Initializer as CallExpression;
        Assert.NotNull(call);

        Assert.Equal(2, call.Arguments.Count);
        Assert.Equal(ArgumentModifier.None, call.Arguments[0].Modifier);
        Assert.Equal(ArgumentModifier.Out, call.Arguments[1].Modifier);
    }

    [Fact]
    public void TestConstructorWithThisInitializer()
    {
        var source = @"
            class Person {
                Name: string
                Age: int

                constructor(name: string): this(name, 0) {
                }

                constructor(name: string, age: int) {
                    Name = name
                    Age = age
                }
            }
        ";

        var cu = Parse(source);
        var personClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(personClass);

        var ctor1 = personClass.Members[2] as ConstructorDeclaration;
        Assert.NotNull(ctor1);
        Assert.Single(ctor1.Parameters);
        Assert.NotNull(ctor1.Initializer);

        // Initializer should be a CallExpression with ThisExpression as callee
        var initCall = ctor1.Initializer as CallExpression;
        Assert.NotNull(initCall);
        Assert.IsType<ThisExpression>(initCall.Callee);
        Assert.Equal(2, initCall.Arguments.Count);
    }

    [Fact]
    public void TestConstructorWithBaseInitializer()
    {
        var source = @"
            class Employee : Person {
                EmployeeId: string

                constructor(name: string, id: string): base(name) {
                    EmployeeId = id
                }
            }
        ";

        var cu = Parse(source);
        var empClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(empClass);

        var ctor = empClass.Members[1] as ConstructorDeclaration;
        Assert.NotNull(ctor);
        Assert.Equal(2, ctor.Parameters.Count);
        Assert.NotNull(ctor.Initializer);

        // Initializer should be a CallExpression with BaseExpression as callee
        var initCall = ctor.Initializer as CallExpression;
        Assert.NotNull(initCall);
        Assert.IsType<BaseExpression>(initCall.Callee);
        Assert.Single(initCall.Arguments);
    }

    [Fact]
    public void TestConstructorWithMultipleArguments()
    {
        var source = @"
            class Product {
                Name: string
                Price: double
                Stock: int

                constructor(name: string): this(name, 0.0, 0) {
                }

                constructor(name: string, price: double, stock: int) {
                    Name = name
                    Price = price
                    Stock = stock
                }
            }
        ";

        var cu = Parse(source);
        var productClass = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(productClass);

        var ctor1 = productClass.Members[3] as ConstructorDeclaration;
        Assert.NotNull(ctor1);
        Assert.Single(ctor1.Parameters);
        Assert.NotNull(ctor1.Initializer);

        var initCall = ctor1.Initializer as CallExpression;
        Assert.NotNull(initCall);
        Assert.Equal(3, initCall.Arguments.Count);
    }

    [Fact]
    public void TestInterpolatedRawString()
    {
        var source = @"
            func Test() {
                json := $""""""
                {
                    ""name"": ""{person.Name}"",
                    ""age"": {person.Age}
                }
                """"""
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        var stringLiteral = varDecl.Initializer as StringLiteralExpression;
        Assert.NotNull(stringLiteral);
        Assert.StartsWith("$\"\"\"", stringLiteral.Value);
        Assert.EndsWith("\"\"\"", stringLiteral.Value);
        Assert.Contains("{person.Name}", stringLiteral.Value);
    }

    [Fact]
    public void TestClassWithPrimaryConstructor()
    {
        var source = @"
            class UserService(logger: ILogger, db: IDatabase) {
                func DoWork() {
                    logger.Log(""Working"")
                }
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal("UserService", classDecl.Name);

        Assert.NotNull(classDecl.PrimaryConstructorParameters);
        Assert.Equal(2, classDecl.PrimaryConstructorParameters.Count);
        Assert.Equal("logger", classDecl.PrimaryConstructorParameters[0].Name);
        Assert.Equal("ILogger", (classDecl.PrimaryConstructorParameters[0].Type as SimpleTypeReference)?.Name);
        Assert.Equal("db", classDecl.PrimaryConstructorParameters[1].Name);
        Assert.Equal("IDatabase", (classDecl.PrimaryConstructorParameters[1].Type as SimpleTypeReference)?.Name);
    }

    [Fact]
    public void TestStructWithPrimaryConstructor()
    {
        var source = @"
            struct Point(x: double, y: double) {
                func GetDistance(): double {
                    return Math.Sqrt(x * x + y * y)
                }
            }
        ";

        var cu = Parse(source);
        var structDecl = cu.Declarations[0] as StructDeclaration;
        Assert.NotNull(structDecl);
        Assert.Equal("Point", structDecl.Name);

        Assert.NotNull(structDecl.PrimaryConstructorParameters);
        Assert.Equal(2, structDecl.PrimaryConstructorParameters.Count);
        Assert.Equal("x", structDecl.PrimaryConstructorParameters[0].Name);
        Assert.Equal("y", structDecl.PrimaryConstructorParameters[1].Name);
    }

    [Fact]
    public void TestRecordWithPrimaryConstructor()
    {
        var source = @"
            record Person(name: string, age: int) {
                FullInfo: string => $""{name} is {age} years old""
            }
        ";

        var cu = Parse(source);
        var recordDecl = cu.Declarations[0] as RecordDeclaration;
        Assert.NotNull(recordDecl);
        Assert.Equal("Person", recordDecl.Name);

        Assert.NotNull(recordDecl.PrimaryConstructorParameters);
        Assert.Equal(2, recordDecl.PrimaryConstructorParameters.Count);
        Assert.Equal("name", recordDecl.PrimaryConstructorParameters[0].Name);
        Assert.Equal("age", recordDecl.PrimaryConstructorParameters[1].Name);
    }

    [Fact]
    public void TestRecordStruct()
    {
        var source = @"
            record struct Point {
                X: double
                Y: double
            }
        ";

        var cu = Parse(source);
        var recordDecl = cu.Declarations[0] as RecordDeclaration;
        Assert.NotNull(recordDecl);
        Assert.Equal("Point", recordDecl.Name);
        Assert.True(recordDecl.IsStruct);
    }

    [Fact]
    public void TestRecordStructWithPrimaryConstructor()
    {
        var source = @"
            record struct Point(x: double, y: double) {
                Length: double => Math.Sqrt(x * x + y * y)
            }
        ";

        var cu = Parse(source);
        var recordDecl = cu.Declarations[0] as RecordDeclaration;
        Assert.NotNull(recordDecl);
        Assert.Equal("Point", recordDecl.Name);
        Assert.True(recordDecl.IsStruct);
        Assert.NotNull(recordDecl.PrimaryConstructorParameters);
        Assert.Equal(2, recordDecl.PrimaryConstructorParameters.Count);
    }

    [Fact]
    public void TestRecordClass()
    {
        var source = @"
            record Person {
                Name: string
                Age: int
            }
        ";

        var cu = Parse(source);
        var recordDecl = cu.Declarations[0] as RecordDeclaration;
        Assert.NotNull(recordDecl);
        Assert.Equal("Person", recordDecl.Name);
        Assert.False(recordDecl.IsStruct);  // Default is record class (reference type)
    }

    [Fact]
    public void TestTargetTypedNew()
    {
        var source = @"
            func Test() {
                let p: Person = new()
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.NotNull(funcDecl.Body);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        Assert.Equal("p", varDecl.Name);

        var newExpr = varDecl.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        Assert.Null(newExpr.Type);  // Target-typed new has no type
        Assert.Empty(newExpr.ConstructorArguments);
    }

    [Fact]
    public void TestTargetTypedNewWithArguments()
    {
        var source = @"
            func Test() {
                let p: Person = new(""Alice"", 30)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.NotNull(funcDecl.Body);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var newExpr = varDecl.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        Assert.Null(newExpr.Type);  // Target-typed new
        Assert.Equal(2, newExpr.ConstructorArguments.Count);
    }

    [Fact]
    public void TestTargetTypedNewWithInitializer()
    {
        var source = @"
            func Test() {
                let p: Person = new { Name: ""Alice"", Age: 30 }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        Assert.NotNull(funcDecl.Body);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var newExpr = varDecl.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        Assert.Null(newExpr.Type);  // Target-typed new
        Assert.NotNull(newExpr.Initializer);
        Assert.Equal(2, newExpr.Initializer.Properties.Count);
    }

    [Fact]
    public void TestFileClassModifier()
    {
        var source = @"
            file class InternalHelper {
                Name: string
            }
        ";

        var cu = Parse(source);
        var classDecl = cu.Declarations[0] as ClassDeclaration;
        Assert.NotNull(classDecl);
        Assert.Equal("InternalHelper", classDecl.Name);
        Assert.True(classDecl.Modifiers.HasFlag(Modifiers.File));
    }

    [Fact]
    public void TestFileStructModifier()
    {
        var source = @"
            file struct Point {
                X: double
                Y: double
            }
        ";

        var cu = Parse(source);
        var structDecl = cu.Declarations[0] as StructDeclaration;
        Assert.NotNull(structDecl);
        Assert.Equal("Point", structDecl.Name);
        Assert.True(structDecl.Modifiers.HasFlag(Modifiers.File));
    }

    [Fact]
    public void TestFileRecordModifier()
    {
        var source = @"
            file record Person {
                Name: string
                Age: int
            }
        ";

        var cu = Parse(source);
        var recordDecl = cu.Declarations[0] as RecordDeclaration;
        Assert.NotNull(recordDecl);
        Assert.Equal("Person", recordDecl.Name);
        Assert.True(recordDecl.Modifiers.HasFlag(Modifiers.File));
    }

    [Fact]
    public void TestFileInterfaceModifier()
    {
        var source = @"
            file interface IHelper {
                func DoWork(): void
            }
        ";

        var cu = Parse(source);
        var interfaceDecl = cu.Declarations[0] as InterfaceDeclaration;
        Assert.NotNull(interfaceDecl);
        Assert.Equal("IHelper", interfaceDecl.Name);
        Assert.True(interfaceDecl.Modifiers.HasFlag(Modifiers.File));
    }

    [Fact]
    public void TestInlineOutVarDeclaration()
    {
        var source = @"
            func TryParse(input: string, out result: int): bool {
                result = 42
                return true
            }

            func Main() {
                if TryParse(""123"", out var num) {
                    print num
                }
            }
        ";

        var cu = Parse(source);
        Assert.Equal(2, cu.Declarations.Count);

        var mainFunc = cu.Declarations[1] as FunctionDeclaration;
        Assert.NotNull(mainFunc);
        Assert.Equal("Main", mainFunc.Name);

        var ifStmt = mainFunc.Body.Statements[0] as IfStatement;
        Assert.NotNull(ifStmt);

        var callExpr = ifStmt.Condition as CallExpression;
        Assert.NotNull(callExpr);
        Assert.Equal(2, callExpr.Arguments.Count);

        // Second argument should be out var num
        var outArg = callExpr.Arguments[1];
        Assert.Equal(ArgumentModifier.Out, outArg.Modifier);

        var outVarDecl = outArg.Value as OutVariableDeclarationExpression;
        Assert.NotNull(outVarDecl);
        Assert.Null(outVarDecl.Type); // var = null type
        Assert.Equal("num", outVarDecl.VariableName);
    }

    [Fact]
    public void TestInlineOutExplicitTypeDeclaration()
    {
        var source = @"
            func TryParse(input: string, out result: int): bool {
                result = 42
                return true
            }

            func Main() {
                if TryParse(""456"", out int value) {
                    print value
                }
            }
        ";

        var cu = Parse(source);
        Assert.Equal(2, cu.Declarations.Count);

        var mainFunc = cu.Declarations[1] as FunctionDeclaration;
        Assert.NotNull(mainFunc);

        var ifStmt = mainFunc.Body.Statements[0] as IfStatement;
        Assert.NotNull(ifStmt);

        var callExpr = ifStmt.Condition as CallExpression;
        Assert.NotNull(callExpr);

        // Second argument should be out int value
        var outArg = callExpr.Arguments[1];
        Assert.Equal(ArgumentModifier.Out, outArg.Modifier);

        var outVarDecl = outArg.Value as OutVariableDeclarationExpression;
        Assert.NotNull(outVarDecl);
        Assert.NotNull(outVarDecl.Type); // explicit type
        Assert.Equal("value", outVarDecl.VariableName);

        var simpleType = outVarDecl.Type as SimpleTypeReference;
        Assert.NotNull(simpleType);
        Assert.Equal("int", simpleType.Name);
    }

    [Fact]
    public void TestGenericMethodCallWithSingleTypeArgument()
    {
        var source = @"
            func Test() {
                result := Method<int>(42)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var block = funcDecl.Body as BlockStatement;
        Assert.NotNull(block);

        var varDecl = block.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var callExpr = varDecl.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        Assert.NotNull(callExpr.TypeArguments);
        Assert.Single(callExpr.TypeArguments);

        var typeArg = callExpr.TypeArguments[0] as SimpleTypeReference;
        Assert.NotNull(typeArg);
        Assert.Equal("int", typeArg.Name);

        Assert.Single(callExpr.Arguments);
    }

    [Fact]
    public void TestGenericMethodCallWithMultipleTypeArguments()
    {
        var source = @"
            func Test() {
                result := Method<int, string, bool>(42, ""hello"", true)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var block = funcDecl.Body as BlockStatement;
        Assert.NotNull(block);

        var varDecl = block.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var callExpr = varDecl.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        Assert.NotNull(callExpr.TypeArguments);
        Assert.Equal(3, callExpr.TypeArguments.Count);

        var typeArg1 = callExpr.TypeArguments[0] as SimpleTypeReference;
        Assert.NotNull(typeArg1);
        Assert.Equal("int", typeArg1.Name);

        var typeArg2 = callExpr.TypeArguments[1] as SimpleTypeReference;
        Assert.NotNull(typeArg2);
        Assert.Equal("string", typeArg2.Name);

        var typeArg3 = callExpr.TypeArguments[2] as SimpleTypeReference;
        Assert.NotNull(typeArg3);
        Assert.Equal("bool", typeArg3.Name);

        Assert.Equal(3, callExpr.Arguments.Count);
    }

    [Fact]
    public void TestGenericMethodCallWithComplexTypeArguments()
    {
        // Test single nested generic type argument
        var source = @"
            func Test() {
                result := Method<List<int>>(list)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var block = funcDecl.Body as BlockStatement;
        Assert.NotNull(block);

        var varDecl = block.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var callExpr = varDecl.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        Assert.NotNull(callExpr.TypeArguments);
        Assert.Single(callExpr.TypeArguments);

        // Type argument: List<int>
        var typeArg1 = callExpr.TypeArguments[0] as GenericTypeReference;
        Assert.NotNull(typeArg1);
        Assert.Equal("List", typeArg1.Name);
        Assert.Single(typeArg1.TypeArguments);
        var listInner = typeArg1.TypeArguments[0] as SimpleTypeReference;
        Assert.NotNull(listInner);
        Assert.Equal("int", listInner.Name);
    }

    [Fact]
    public void TestGenericMethodCallOnMemberAccess()
    {
        var source = @"
            func Test() {
                result := obj.Method<int>(42)
                result2 := list.OfType<string>()
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var block = funcDecl.Body as BlockStatement;
        Assert.NotNull(block);

        // First call
        var varDecl1 = block.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl1);

        var callExpr1 = varDecl1.Initializer as CallExpression;
        Assert.NotNull(callExpr1);
        Assert.NotNull(callExpr1.TypeArguments);
        Assert.Single(callExpr1.TypeArguments);

        var memberAccess1 = callExpr1.Callee as MemberAccessExpression;
        Assert.NotNull(memberAccess1);
        Assert.Equal("Method", memberAccess1.MemberName);

        // Second call
        var varDecl2 = block.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(varDecl2);

        var callExpr2 = varDecl2.Initializer as CallExpression;
        Assert.NotNull(callExpr2);
        Assert.NotNull(callExpr2.TypeArguments);
        Assert.Single(callExpr2.TypeArguments);

        var memberAccess2 = callExpr2.Callee as MemberAccessExpression;
        Assert.NotNull(memberAccess2);
        Assert.Equal("OfType", memberAccess2.MemberName);
    }

    [Fact]
    public void TestGenericMethodCallWithNullableTypeArgument()
    {
        var source = @"
            func Test() {
                result := Method<int?>(value)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var block = funcDecl.Body as BlockStatement;
        Assert.NotNull(block);

        var varDecl = block.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var callExpr = varDecl.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        Assert.NotNull(callExpr.TypeArguments);
        Assert.Single(callExpr.TypeArguments);

        var typeArg = callExpr.TypeArguments[0] as NullableTypeReference;
        Assert.NotNull(typeArg);
        var innerType = typeArg.InnerType as SimpleTypeReference;
        Assert.NotNull(innerType);
        Assert.Equal("int", innerType.Name);
    }

    [Fact]
    public void TestGenericMethodCallWithArrayTypeArgument()
    {
        var source = @"
            func Test() {
                result := Method<int[]>(array)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var block = funcDecl.Body as BlockStatement;
        Assert.NotNull(block);

        var varDecl = block.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var callExpr = varDecl.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        Assert.NotNull(callExpr.TypeArguments);
        Assert.Single(callExpr.TypeArguments);

        var typeArg = callExpr.TypeArguments[0] as ArrayTypeReference;
        Assert.NotNull(typeArg);
        var elementType = typeArg.ElementType as SimpleTypeReference;
        Assert.NotNull(elementType);
        Assert.Equal("int", elementType.Name);
    }

    [Fact]
    public void TestLessThanIsNotGenericMethodCall()
    {
        var source = @"
            func Test() {
                result := x < y
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var block = funcDecl.Body as BlockStatement;
        Assert.NotNull(block);

        var varDecl = block.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        // Should be a binary expression, not a call expression
        var binaryExpr = varDecl.Initializer as BinaryExpression;
        Assert.NotNull(binaryExpr);
        Assert.Equal(BinaryOperator.Less, binaryExpr.Operator);
    }

    [Fact]
    public void TestCollectionInitializerWithIndexers()
    {
        var source = @"
            func Test() {
                dict := new Dictionary<string, int> {
                    [""one""] = 1,
                    [""two""] = 2,
                    [""three""] = 3
                }
            }
        ";

        var ast = Parse(source);
        var funcDecl = ast.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var newExpr = varDecl.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        Assert.NotNull(newExpr.Initializer);
        Assert.Equal(3, newExpr.Initializer.Properties.Count);

        // First property initializer should be an indexer
        var prop1 = newExpr.Initializer.Properties[0];
        Assert.True(prop1.IsIndexerInitializer);
        Assert.NotNull(prop1.IndexExpression);
        Assert.Null(prop1.Name);

        var indexExpr1 = prop1.IndexExpression as StringLiteralExpression;
        Assert.NotNull(indexExpr1);
        Assert.Equal("\"one\"", indexExpr1.Value);

        var valueExpr1 = prop1.Value as IntLiteralExpression;
        Assert.NotNull(valueExpr1);
        Assert.Equal("1", valueExpr1.Value);

        // Second property initializer
        var prop2 = newExpr.Initializer.Properties[1];
        Assert.True(prop2.IsIndexerInitializer);
        var indexExpr2 = prop2.IndexExpression as StringLiteralExpression;
        Assert.NotNull(indexExpr2);
        Assert.Equal("\"two\"", indexExpr2.Value);

        // Third property initializer
        var prop3 = newExpr.Initializer.Properties[2];
        Assert.True(prop3.IsIndexerInitializer);
        var indexExpr3 = prop3.IndexExpression as StringLiteralExpression;
        Assert.NotNull(indexExpr3);
        Assert.Equal("\"three\"", indexExpr3.Value);
    }

    [Fact]
    public void TestMixedPropertyAndIndexerInitializers()
    {
        var source = @"
            func Test() {
                obj := new MyType {
                    Name: ""test"",
                    [""key1""] = 1,
                    Age: 30,
                    [""key2""] = 2
                }
            }
        ";

        var ast = Parse(source);
        var funcDecl = ast.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var varDecl = funcDecl.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);

        var newExpr = varDecl.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        Assert.NotNull(newExpr.Initializer);
        Assert.Equal(4, newExpr.Initializer.Properties.Count);

        // First should be property initializer
        var prop1 = newExpr.Initializer.Properties[0];
        Assert.False(prop1.IsIndexerInitializer);
        Assert.Equal("Name", prop1.Name);
        Assert.Null(prop1.IndexExpression);

        // Second should be indexer initializer
        var prop2 = newExpr.Initializer.Properties[1];
        Assert.True(prop2.IsIndexerInitializer);
        Assert.NotNull(prop2.IndexExpression);
        Assert.Null(prop2.Name);

        // Third should be property initializer
        var prop3 = newExpr.Initializer.Properties[2];
        Assert.False(prop3.IsIndexerInitializer);
        Assert.Equal("Age", prop3.Name);

        // Fourth should be indexer initializer
        var prop4 = newExpr.Initializer.Properties[3];
        Assert.True(prop4.IsIndexerInitializer);
        Assert.NotNull(prop4.IndexExpression);
    }
}

