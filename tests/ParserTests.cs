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
}
