using System;
using System.Linq;
using System.Collections.Generic;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;
using NSharpLang.Compiler.Columnar;

namespace NSharpLang.Tests;

public class ParserTests
{
    private static CompilationUnit Parse(string source)
    {
        var result = ColumnarParserRecovery.ParseFileAst(source, "test.nl");
        return result.CompilationUnit!; // Tests expect valid syntax
    }

    private static void AssertHasParseError(string source, string expectedMessage)
    {
        var result = ColumnarParserRecovery.ParseFileAst(source, "test.nl");

        Assert.False(result.Success, "Expected parse error but got none");
        Assert.Contains(result.Errors, error => error.Message.Contains(expectedMessage));
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
        // Use returnStmt! for all following references
        Assert.NotNull(returnStmt!.Value);
        // Use returnStmt!.Value! for all following references

        var addExpr = returnStmt!.Value as BinaryExpression;
        Assert.NotNull(addExpr);
        // Use addExpr! for all following references
        Assert.Equal(BinaryOperator.Add, addExpr!.Operator);

        var mulExpr = addExpr!.Right as BinaryExpression;
        Assert.NotNull(mulExpr);
        // Use mulExpr! for all following references
        Assert.Equal(BinaryOperator.Multiply, mulExpr!.Operator);
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
        // Use varDecl! for all following references
        var arrayLiteral = varDecl!.Initializer as ArrayLiteralExpression;
        Assert.NotNull(arrayLiteral);
        // Use arrayLiteral! for all following references
        Assert.Equal(3, arrayLiteral!.Elements.Count);
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
        // Use lambda1! for all following references
        Assert.Single(lambda1!.Parameters);
        Assert.NotNull(lambda1!.ExpressionBody);
        // Use lambda1!.ExpressionBody! for all following references

        var gDecl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        var lambda2 = gDecl!.Initializer as LambdaExpression;
        Assert.NotNull(lambda2);
        // Use lambda2! for all following references
        Assert.Equal(2, lambda2!.Parameters.Count);
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
        // Use memberAccess1! for all following references
        Assert.Equal("Name", memberAccess1!.MemberName);
        Assert.False(memberAccess1!.IsNullConditional);

        var yDecl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        var memberAccess2 = yDecl!.Initializer as MemberAccessExpression;
        Assert.NotNull(memberAccess2);
        // Use memberAccess2! for all following references
        Assert.Equal("Age", memberAccess2!.MemberName);
        Assert.True(memberAccess2!.IsNullConditional);
    }

    [Fact]
    public void PostfixMemberChain_AllowsLeadingDotContinuation()
    {
        var source = @"
            func Test() {
                result := builder
                    .Entity()
                    .HasOne()
            }
        ";

        var result = ColumnarParserRecovery.ParseFileAst(source, "test.nl");
        Assert.DoesNotContain(result.Errors, error => error.Severity == ErrorSeverity.Error);

        var funcDecl = Assert.IsType<FunctionDeclaration>(result.CompilationUnit!.Declarations[0]);
        var resultDecl = Assert.IsType<VariableDeclarationStatement>(funcDecl.Body!.Statements[0]);
        var finalCall = Assert.IsType<CallExpression>(resultDecl.Initializer);
        var finalMember = Assert.IsType<MemberAccessExpression>(finalCall.Callee);
        Assert.Equal("HasOne", finalMember.MemberName);

        var innerCall = Assert.IsType<CallExpression>(finalMember.Object);
        var innerMember = Assert.IsType<MemberAccessExpression>(innerCall.Callee);
        Assert.Equal("Entity", innerMember.MemberName);
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
        // Use call1! for all following references
        Assert.Equal(2, call1!.Arguments.Count);

        var namedDecl = funcDecl.Body.Statements[1] as VariableDeclarationStatement;
        var call2 = namedDecl!.Initializer as CallExpression;
        Assert.NotNull(call2);
        // Use call2! for all following references
        Assert.Equal(2, call2!.Arguments.Count);
        Assert.Equal("name", call2!.Arguments[0].Name);
        Assert.Equal("age", call2!.Arguments[1].Name);
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
        // Use newExpr! for all following references
        Assert.Single(newExpr!.ConstructorArguments);
        Assert.NotNull(newExpr!.Initializer);
        // Use newExpr!.Initializer! for all following references
        Assert.Single(newExpr!.Initializer.Properties);
    }

    [Fact]
    public void TestSizedArrayNewExpression()
    {
        var source = @"
            func Test() {
                values := new int[256]
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var valuesDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;

        var newExpr = Assert.IsType<NewExpression>(valuesDecl!.Initializer);
        var arrayType = Assert.IsType<ArrayTypeReference>(newExpr.Type);
        Assert.IsType<SimpleTypeReference>(arrayType.ElementType);
        var length = Assert.IsType<IntLiteralExpression>(newExpr.ArrayLengthExpression);
        Assert.Equal("256", length.Value);
    }

    [Fact]
    public void TestNewExpression_ObjectInitializerWithoutEmptyConstructorParens()
    {
        var source = @"
            func Test() {
                p := new Person { Name: ""Alice"", Age: 30 }
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var pDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;

        var newExpr = pDecl!.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        Assert.Empty(newExpr!.ConstructorArguments);
        Assert.NotNull(newExpr.Initializer);
        Assert.Equal(2, newExpr.Initializer!.Properties.Count);
        Assert.Equal("Name", newExpr.Initializer.Properties[0].Name);
        Assert.Equal("Age", newExpr.Initializer.Properties[1].Name);
    }

    [Fact]
    public void TestNamespaceAndUsings()
    {
        var source = @"
            namespace MyApp.Services

            import System
            import System.Collections.Generic
            import System.Text.Json as Json

            func Test() {}
        ";

        var cu = Parse(source);
        Assert.NotNull(cu.Namespace);
        // Use cu.Namespace! for all following references
        Assert.Equal("MyApp.Services", cu.Namespace.Name);
        Assert.Equal(3, cu.Imports.Count);
        Assert.Equal("System", cu.Imports[0].Namespace);
        Assert.Equal("System.Collections.Generic", cu.Imports[1].Namespace);
        Assert.Equal("Json", cu.Imports[2].Alias);
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
        // Use ternary! for all following references
        Assert.NotNull(ternary!.Condition);
        // Use ternary!.Condition! for all following references
        Assert.NotNull(ternary!.ThenExpression);
        // Use ternary!.ThenExpression! for all following references
        Assert.NotNull(ternary!.ElseExpression);
        // Use ternary!.ElseExpression! for all following references
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
        // Use binary! for all following references
        Assert.Equal(BinaryOperator.NullCoalesce, binary!.Operator);
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
        // Use funcDecl! for all following references
        Assert.NotNull(funcDecl!.Body);
        // Use funcDecl!.Body! for all following references

        var varDecl = funcDecl!.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references
        Assert.Equal("s", varDecl!.Name);

        var castExpr = varDecl!.Initializer as CastExpression;
        Assert.NotNull(castExpr);
        // Use castExpr! for all following references
        Assert.Equal(CastKind.Hard, castExpr!.Kind);

        var typeRef = castExpr!.TargetType as SimpleTypeReference;
        Assert.NotNull(typeRef);
        // Use typeRef! for all following references
        Assert.Equal("Result.Success", typeRef!.Name);

        var targetExpr = castExpr!.Expression as IdentifierExpression;
        Assert.NotNull(targetExpr);
        // Use targetExpr! for all following references
        Assert.Equal("r", targetExpr!.Name);
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
        // Use funcDecl! for all following references

        var varDecl = funcDecl!.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var withExpr = varDecl!.Initializer as WithExpression;
        Assert.NotNull(withExpr);
        // Use withExpr! for all following references

        var targetExpr = withExpr!.Target as IdentifierExpression;
        Assert.NotNull(targetExpr);
        // Use targetExpr! for all following references
        Assert.Equal("p1", targetExpr!.Name);

        Assert.Single(withExpr!.Properties);
        Assert.Equal("Age", withExpr!.Properties[0].Name);
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
        // Use funcDecl! for all following references
        Assert.Equal("FetchData", funcDecl!.Name);
        Assert.True(funcDecl!.Modifiers.HasFlag(Modifiers.Async));

        var varDecl = funcDecl!.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var awaitExpr = varDecl!.Initializer as AwaitExpression;
        Assert.NotNull(awaitExpr);
        // Use awaitExpr! for all following references

        var callExpr = awaitExpr!.Expression as CallExpression;
        Assert.NotNull(callExpr);
        // Use callExpr! for all following references
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
        // Use funcDecl! for all following references

        var arr2Decl = funcDecl!.Body.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(arr2Decl);
        // Use arr2Decl! for all following references

        var arrayLiteral = arr2Decl!.Initializer as ArrayLiteralExpression;
        Assert.NotNull(arrayLiteral);
        // Use arrayLiteral! for all following references
        Assert.Equal(3, arrayLiteral!.Elements.Count);

        var spreadExpr = arrayLiteral!.Elements[0] as SpreadExpression;
        Assert.NotNull(spreadExpr);
        // Use spreadExpr! for all following references
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
        // Use testFunc! for all following references

        var resultDecl = testFunc!.Body.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(resultDecl);
        // Use resultDecl! for all following references

        var callExpr = resultDecl!.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        // Use callExpr! for all following references
        Assert.Single(callExpr!.Arguments);

        var spreadArg = callExpr!.Arguments[0].Value as SpreadExpression;
        Assert.NotNull(spreadArg);
        // Use spreadArg! for all following references

        var innerExpr = spreadArg!.Expression as IdentifierExpression;
        Assert.NotNull(innerExpr);
        // Use innerExpr! for all following references
        Assert.Equal("items", innerExpr!.Name);
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
        // Use classDecl! for all following references
        Assert.Single(classDecl!.Attributes);
        Assert.Equal("Serializable", classDecl!.Attributes[0].Name);

        var field1 = classDecl!.Members[0] as FieldDeclaration;
        Assert.NotNull(field1);
        // Use field1! for all following references
        Assert.Single(field1!.Attributes);
        Assert.Equal("JsonProperty", field1!.Attributes[0].Name);
        Assert.Single(field1!.Attributes[0].Arguments);

        var field2 = classDecl!.Members[1] as FieldDeclaration;
        Assert.NotNull(field2);
        // Use field2! for all following references
        Assert.Single(field2!.Attributes);
        Assert.Equal("Required", field2!.Attributes[0].Name);

        var funcDecl = cu.Declarations[1] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        // Use funcDecl! for all following references
        Assert.Single(funcDecl!.Attributes);
        Assert.Equal("HttpGet", funcDecl!.Attributes[0].Name);
        Assert.Single(funcDecl!.Attributes[0].Arguments);
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
        // Use classDecl! for all following references
        Assert.Single(classDecl!.Attributes);
        Assert.Equal("System.Serializable", classDecl!.Attributes[0].Name);

        var structDecl = cu.Declarations[1] as StructDeclaration;
        Assert.NotNull(structDecl);
        // Use structDecl! for all following references
        Assert.Single(structDecl!.Attributes);
        Assert.Equal("System.Runtime.CompilerServices.InlineArray", structDecl!.Attributes[0].Name);
        Assert.Single(structDecl!.Attributes[0].Arguments);

        var funcDecl = cu.Declarations[2] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        // Use funcDecl! for all following references
        Assert.Single(funcDecl!.Attributes);
        Assert.Equal("System.Diagnostics.CodeAnalysis.SuppressMessage", funcDecl!.Attributes[0].Name);
        Assert.Equal(2, funcDecl!.Attributes[0].Arguments.Count);
    }

    [Fact]
    public void TestParameterAttributes()
    {
        var source = @"
            func Create([FromBody] dto: TaskDto, [Required] name: string): void {
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        // First parameter has [FromBody]
        var param0 = funcDecl!.Parameters[0];
        Assert.NotNull(param0.Attributes);
        Assert.Single(param0.Attributes!);
        Assert.Equal("FromBody", param0.Attributes![0].Name);

        // Second parameter has [Required]
        var param1 = funcDecl!.Parameters[1];
        Assert.NotNull(param1.Attributes);
        Assert.Single(param1.Attributes!);
        Assert.Equal("Required", param1.Attributes![0].Name);
    }

    [Fact]
    public void TestParameterAttributesWithArguments()
    {
        var source = @"
            func Search([FromQuery(Name = ""q"")] query: string, [Range(1, 100)] page: int): void {
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var param0 = funcDecl!.Parameters[0];
        Assert.NotNull(param0.Attributes);
        Assert.Single(param0.Attributes!);
        Assert.Equal("FromQuery", param0.Attributes![0].Name);
        Assert.Single(param0.Attributes![0].Arguments);

        var param1 = funcDecl!.Parameters[1];
        Assert.NotNull(param1.Attributes);
        Assert.Single(param1.Attributes!);
        Assert.Equal("Range", param1.Attributes![0].Name);
        Assert.Equal(2, param1.Attributes![0].Arguments.Count);
    }

    [Fact]
    public void TestParameterMultipleAttributes()
    {
        var source = @"
            func Create([FromBody] [Required] dto: TaskDto): void {
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var param0 = funcDecl!.Parameters[0];
        Assert.NotNull(param0.Attributes);
        Assert.Equal(2, param0.Attributes!.Count);
        Assert.Equal("FromBody", param0.Attributes![0].Name);
        Assert.Equal("Required", param0.Attributes![1].Name);
    }

    [Fact]
    public void TestParameterAttributesWithModifiers()
    {
        var source = @"
            func Process([Required] ref data: byte[], [FromBody] params items: string[]): void {
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var param0 = funcDecl!.Parameters[0];
        Assert.NotNull(param0.Attributes);
        Assert.Equal("Required", param0.Attributes![0].Name);
        Assert.Equal(ParameterModifier.Ref, param0.Modifier);

        var param1 = funcDecl!.Parameters[1];
        Assert.NotNull(param1.Attributes);
        Assert.Equal("FromBody", param1.Attributes![0].Name);
        Assert.Equal(ParameterModifier.Params, param1.Modifier);
    }

    [Fact]
    public void TestMethodAndParameterAttributesStayScoped()
    {
        var source = @"
            [InlineData(1, 2)]
            func Theory([FromServices] service: Calculator, value: int): void {
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        Assert.NotNull(funcDecl);

        var methodAttribute = Assert.Single(funcDecl!.Attributes);
        Assert.Equal("InlineData", methodAttribute.Name);

        var parameterAttribute = Assert.Single(funcDecl.Parameters[0].Attributes!);
        Assert.Equal("FromServices", parameterAttribute.Name);
        Assert.Null(funcDecl.Parameters[1].Attributes);
    }

    [Fact]
    public void TestParameterAttributesAfterNameReportParseError()
    {
        AssertHasParseError(@"
            func Create(dto [FromBody]: TaskDto): void {
            }
        ", "Expected ':' after parameter name");
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
        // Use funcDecl! for all following references
        Assert.Equal(5, funcDecl!.Body!.Statements.Count);

        // Check arr[0] indexer
        var xDecl = funcDecl!.Body.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(xDecl);
        // Use xDecl! for all following references
        var indexAccess = xDecl!.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references
        var arrIdent = indexAccess!.Object as IdentifierExpression;
        Assert.NotNull(arrIdent);
        // Use arrIdent! for all following references
        Assert.Equal("arr", arrIdent!.Name);

        // Check dict["key"] = 42 assignment
        var dictAssign = funcDecl!.Body.Statements[3] as ExpressionStatement;
        Assert.NotNull(dictAssign);
        // Use dictAssign! for all following references
        var assignExpr = dictAssign!.Expression as AssignmentExpression;
        Assert.NotNull(assignExpr);
        // Use assignExpr! for all following references
        var dictIndexAccess = assignExpr!.Target as IndexAccessExpression;
        Assert.NotNull(dictIndexAccess);
        // Use dictIndexAccess! for all following references
    }

    [Fact]
    public void ParenthesizedExpression_AllowsIndexPostfix()
    {
        var source = """
            func Test() {
                value := (items)[0]
            }
        """;

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var valueDecl = Assert.IsType<VariableDeclarationStatement>(funcDecl.Body!.Statements[0]);
        var indexAccess = Assert.IsType<IndexAccessExpression>(valueDecl.Initializer);
        var parenthesized = Assert.IsType<ParenthesizedExpression>(indexAccess.Object);
        var identifier = Assert.IsType<IdentifierExpression>(parenthesized.Inner);

        Assert.Equal("items", identifier.Name);
        Assert.IsType<IntLiteralExpression>(indexAccess.Index);
    }

    [Fact]
    public void ParenthesizedMemberIndexEquality_InVariableInitializerParsesAsBinaryExpression()
    {
        var source = """
            func Test(nodes: NodeTable, row: int) {
                nameMatches := (nodes.name)[row] == "alpha"
            }
        """;

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var valueDecl = Assert.IsType<VariableDeclarationStatement>(funcDecl.Body!.Statements[0]);
        var binary = Assert.IsType<BinaryExpression>(valueDecl.Initializer);
        var indexAccess = Assert.IsType<IndexAccessExpression>(binary.Left);
        var parenthesized = Assert.IsType<ParenthesizedExpression>(indexAccess.Object);
        var memberAccess = Assert.IsType<MemberAccessExpression>(parenthesized.Inner);
        var receiver = Assert.IsType<IdentifierExpression>(memberAccess.Object);

        Assert.Equal(BinaryOperator.Equal, binary.Operator);
        Assert.Equal("nodes", receiver.Name);
        Assert.Equal("name", memberAccess.MemberName);
        Assert.IsType<IdentifierExpression>(indexAccess.Index);
        Assert.IsType<StringLiteralExpression>(binary.Right);
    }

    [Fact]
    public void NullEqualityInitializer_DoesNotConsumeNextLineAssignment()
    {
        var source = """
            func Test(nodes: NodeTable, row: int) {
                optionalMissing := (nodes.optionalName)[row] == null
                (nodes.optionalName)[row] = "maybe"
            }
        """;

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        Assert.Equal(2, funcDecl.Body!.Statements.Count);

        var valueDecl = Assert.IsType<VariableDeclarationStatement>(funcDecl.Body.Statements[0]);
        var nullCheck = Assert.IsType<BinaryExpression>(valueDecl.Initializer);
        Assert.Equal(BinaryOperator.Equal, nullCheck.Operator);
        Assert.IsType<NullLiteralExpression>(nullCheck.Right);

        var assignmentStatement = Assert.IsType<ExpressionStatement>(funcDecl.Body.Statements[1]);
        var assignment = Assert.IsType<AssignmentExpression>(assignmentStatement.Expression);
        var target = Assert.IsType<IndexAccessExpression>(assignment.Target);
        var parenthesized = Assert.IsType<ParenthesizedExpression>(target.Object);
        var memberAccess = Assert.IsType<MemberAccessExpression>(parenthesized.Inner);

        Assert.Equal(AssignmentOperator.Assign, assignment.Operator);
        Assert.Equal("optionalName", memberAccess.MemberName);
        Assert.IsType<StringLiteralExpression>(assignment.Value);
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
        // Use funcDecl! for all following references

        // Check arr[0]
        var xDecl = funcDecl!.Body!.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(xDecl);
        // Use xDecl! for all following references
        var indexAccess = xDecl!.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references
        Assert.False(indexAccess!.IsNullConditional);
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
        // Use funcDecl! for all following references

        // Check arr?[0]
        var xDecl = funcDecl!.Body!.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(xDecl);
        // Use xDecl! for all following references
        var indexAccess = xDecl!.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references
        Assert.True(indexAccess!.IsNullConditional);
        var arrIdent = indexAccess!.Object as IdentifierExpression;
        Assert.NotNull(arrIdent);
        // Use arrIdent! for all following references
        Assert.Equal("arr", arrIdent!.Name);

        // Check dict?["key"]
        var yDecl = funcDecl!.Body.Statements[3] as VariableDeclarationStatement;
        Assert.NotNull(yDecl);
        // Use yDecl! for all following references
        var dictIndexAccess = yDecl!.Initializer as IndexAccessExpression;
        Assert.NotNull(dictIndexAccess);
        // Use dictIndexAccess! for all following references
        Assert.True(dictIndexAccess!.IsNullConditional);
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
        // Use funcDecl! for all following references

        // Check obj as string
        var strDecl = funcDecl!.Body!.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(strDecl);
        // Use strDecl! for all following references
        var safeCast = strDecl!.Initializer as CastExpression;
        Assert.NotNull(safeCast);
        // Use safeCast! for all following references
        Assert.Equal(CastKind.Safe, safeCast!.Kind);
        var simpleType = safeCast!.TargetType as SimpleTypeReference;
        Assert.NotNull(simpleType);
        // Use simpleType! for all following references
        Assert.Equal("string", simpleType!.Name);
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
        // Use funcDecl! for all following references

        // Check if obj is string s
        var ifStmt1 = funcDecl!.Body!.Statements[0] as IfStatement;
        Assert.NotNull(ifStmt1);
        // Use ifStmt1! for all following references
        var isExpr1 = ifStmt1!.Condition as IsExpression;
        Assert.NotNull(isExpr1);
        // Use isExpr1! for all following references
        var objIdent = isExpr1!.Expression as IdentifierExpression;
        Assert.NotNull(objIdent);
        // Use objIdent! for all following references
        Assert.Equal("obj", objIdent!.Name);
        Assert.NotNull(isExpr1!.VariableName);
        // Use isExpr1!.VariableName! for all following references
        Assert.Equal("s", isExpr1!.VariableName);

        // Check if value is int (no variable)
        var ifStmt2 = funcDecl!.Body.Statements[1] as IfStatement;
        Assert.NotNull(ifStmt2);
        // Use ifStmt2! for all following references
        var isExpr2 = ifStmt2!.Condition as IsExpression;
        Assert.NotNull(isExpr2);
        // Use isExpr2! for all following references
        Assert.NotNull(isExpr2!.Type);
        // Use isExpr2!.Type! for all following references
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
        // Use funcDecl! for all following references

        // Check cache ??= ExpensiveOperation()
        var assignStmt = funcDecl!.Body!.Statements[1] as ExpressionStatement;
        Assert.NotNull(assignStmt);
        // Use assignStmt! for all following references
        var assignExpr = assignStmt!.Expression as AssignmentExpression;
        Assert.NotNull(assignExpr);
        // Use assignExpr! for all following references
        Assert.Equal(AssignmentOperator.NullCoalesceAssign, assignExpr!.Operator);
        var cacheIdent = assignExpr!.Target as IdentifierExpression;
        Assert.NotNull(cacheIdent);
        // Use cacheIdent! for all following references
        Assert.Equal("cache", cacheIdent!.Name);
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
        // Use classDecl! for all following references

        // Check this.name = name
        var setNameMethod = classDecl!.Members[1] as FunctionDeclaration;
        Assert.NotNull(setNameMethod);
        // Use setNameMethod! for all following references
        var assignStmt = setNameMethod!.Body!.Statements[0] as ExpressionStatement;
        Assert.NotNull(assignStmt);
        // Use assignStmt! for all following references
        var assignExpr = assignStmt!.Expression as AssignmentExpression;
        Assert.NotNull(assignExpr);
        // Use assignExpr! for all following references
        var memberAccess = assignExpr!.Target as MemberAccessExpression;
        Assert.NotNull(memberAccess);
        // Use memberAccess! for all following references
        var thisExpr = memberAccess!.Object as ThisExpression;
        Assert.NotNull(thisExpr);
        // Use thisExpr! for all following references

        // Check return this
        var getThisMethod = classDecl!.Members[2] as FunctionDeclaration;
        Assert.NotNull(getThisMethod);
        // Use getThisMethod! for all following references
        var returnStmt = getThisMethod!.Body!.Statements[0] as ReturnStatement;
        Assert.NotNull(returnStmt);
        // Use returnStmt! for all following references
        var returnThis = returnStmt!.Value as ThisExpression;
        Assert.NotNull(returnThis);
        // Use returnThis! for all following references
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
        // Use dogClass! for all following references

        var makeSoundMethod = dogClass!.Members[0] as FunctionDeclaration;
        Assert.NotNull(makeSoundMethod);
        // Use makeSoundMethod! for all following references

        // Check base.MakeSound()
        var baseCallStmt = makeSoundMethod!.Body!.Statements[0] as ExpressionStatement;
        Assert.NotNull(baseCallStmt);
        // Use baseCallStmt! for all following references
        var callExpr = baseCallStmt!.Expression as CallExpression;
        Assert.NotNull(callExpr);
        // Use callExpr! for all following references
        var baseMemberAccess = callExpr!.Callee as MemberAccessExpression;
        Assert.NotNull(baseMemberAccess);
        // Use baseMemberAccess! for all following references
        var baseExpr = baseMemberAccess!.Object as BaseExpression;
        Assert.NotNull(baseExpr);
        // Use baseExpr! for all following references
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
        // Use funcDecl! for all following references

        var varDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references
        var stringLiteral = varDecl!.Initializer as StringLiteralExpression;
        Assert.NotNull(stringLiteral);
        // Use stringLiteral! for all following references
        Assert.Contains("multi-line", stringLiteral!.Value);
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
    public void TestFileImport()
    {
        var source = @"
            import ""Models/Person""
        ";

        var cu = Parse(source);
        Assert.Single(cu.FileImports);

        var fileImport = cu.FileImports[0] as FileImport;
        Assert.NotNull(fileImport);
        // Use fileImport! for all following references
        Assert.Equal("Models/Person", fileImport!.Path);
        Assert.Null(fileImport!.Alias);
    }

    [Fact]
    public void TestFileImportTracksQuotedPathSpan()
    {
        var importLine = "import \"Models/Person\"";

        var cu = Parse(importLine);
        var fileImport = Assert.IsType<FileImport>(Assert.Single(cu.FileImports));

        Assert.Equal(importLine.IndexOf('"') + 1, fileImport.PathColumn);
        Assert.Equal("\"Models/Person\"".Length, fileImport.PathLength);
        Assert.Equal(fileImport.PathColumn, fileImport.DiagnosticColumn);
        Assert.Equal(fileImport.PathLength, fileImport.DiagnosticLength);
    }

    [Fact]
    public void TestFileImportWithAlias()
    {
        var source = @"
            import ""Services/Auth"" as AuthService
        ";

        var cu = Parse(source);
        Assert.Single(cu.FileImports);

        var fileImport = cu.FileImports[0] as FileImport;
        Assert.NotNull(fileImport);
        // Use fileImport! for all following references
        Assert.Equal("Services/Auth", fileImport!.Path);
        Assert.Equal("AuthService", fileImport!.Alias);
    }

    [Fact]
    public void TestNamespaceImport()
    {
        var source = @"
            import System.Collections.Generic
        ";

        var cu = Parse(source);
        Assert.Single(cu.Imports);

        var nsImport = cu.Imports[0];
        Assert.NotNull(nsImport);
        // Use nsImport! for all following references
        Assert.Equal("System.Collections.Generic", nsImport!.Namespace);
        Assert.Null(nsImport!.Alias);
    }

    [Fact]
    public void TestNamespaceImportWithAlias()
    {
        var source = @"
            import System.Text.Json as Json
        ";

        var cu = Parse(source);
        Assert.Single(cu.Imports);

        var nsImport = cu.Imports[0];
        Assert.NotNull(nsImport);
        // Use nsImport! for all following references
        Assert.Equal("System.Text.Json", nsImport!.Namespace);
        Assert.Equal("Json", nsImport!.Alias);
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
        Assert.Equal(2, cu.FileImports.Count);
        Assert.Single(cu.Imports);

        var fileImport1 = cu.FileImports[0] as FileImport;
        Assert.NotNull(fileImport1);
        // Use fileImport1! for all following references
        Assert.Equal("Models/Person", fileImport1!.Path);

        var nsImport = cu.Imports[0];
        Assert.NotNull(nsImport);
        // Use nsImport! for all following references
        Assert.Equal("System.Linq", nsImport!.Namespace);

        var fileImport2 = cu.FileImports[1] as FileImport;
        Assert.NotNull(fileImport2);
        // Use fileImport2! for all following references
        Assert.Equal("Services/Auth", fileImport2!.Path);
        Assert.Equal("AuthService", fileImport2!.Alias);
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
        // Use funcDecl! for all following references
        var vars = funcDecl!.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();
        Assert.Equal(3, vars.Count);

        // Check lastItem uses index from end
        var lastItemDecl = vars[1];
        Assert.Equal("lastItem", lastItemDecl.Name);
        var indexAccess = lastItemDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references

        var indexExpr = indexAccess!.Index as UnaryExpression;
        Assert.NotNull(indexExpr);
        // Use indexExpr! for all following references
        Assert.Equal(UnaryOperator.IndexFromEnd, indexExpr!.Operator);

        var indexValue = indexExpr!.Operand as IntLiteralExpression;
        Assert.NotNull(indexValue);
        // Use indexValue! for all following references
        Assert.Equal("1", indexValue!.Value);
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
        // Use funcDecl! for all following references
        var vars = funcDecl!.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();
        Assert.Equal(3, vars.Count);

        // Check slice uses range
        var sliceDecl = vars[1];
        Assert.Equal("slice", sliceDecl.Name);
        var indexAccess = sliceDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references

        var rangeExpr = indexAccess!.Index as RangeExpression;
        Assert.NotNull(rangeExpr);
        // Use rangeExpr! for all following references

        var left = rangeExpr!.Start as IntLiteralExpression;
        Assert.NotNull(left);
        // Use left! for all following references
        Assert.Equal("1", left!.Value);

        var right = rangeExpr!.End as IntLiteralExpression;
        Assert.NotNull(right);
        // Use right! for all following references
        Assert.Equal("4", right!.Value);
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
        // Use funcDecl! for all following references
        var vars = funcDecl!.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();
        Assert.Equal(3, vars.Count);

        // Check middle uses range with index from end
        var middleDecl = vars[1];
        Assert.Equal("middle", middleDecl.Name);
        var indexAccess = middleDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references

        var rangeExpr = indexAccess!.Index as RangeExpression;
        Assert.NotNull(rangeExpr);
        // Use rangeExpr! for all following references

        var left = rangeExpr!.Start as IntLiteralExpression;
        Assert.NotNull(left);
        // Use left! for all following references
        Assert.Equal("1", left!.Value);

        var right = rangeExpr!.End as UnaryExpression;
        Assert.NotNull(right);
        // Use right! for all following references
        Assert.Equal(UnaryOperator.IndexFromEnd, right!.Operator);
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
        // Use funcDecl! for all following references
        var vars = funcDecl!.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();

        var sliceDecl = vars[1];
        Assert.Equal("slice", sliceDecl.Name);
        var indexAccess = sliceDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references

        var rangeExpr = indexAccess!.Index as RangeExpression;
        Assert.NotNull(rangeExpr);
        // Use rangeExpr! for all following references
        Assert.Null(rangeExpr!.Start);  // Open-ended start

        var end = rangeExpr!.End as IntLiteralExpression;
        Assert.NotNull(end);
        // Use end! for all following references
        Assert.Equal("3", end!.Value);
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
        // Use funcDecl! for all following references
        var vars = funcDecl!.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();

        var sliceDecl = vars[1];
        Assert.Equal("slice", sliceDecl.Name);
        var indexAccess = sliceDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references

        var rangeExpr = indexAccess!.Index as RangeExpression;
        Assert.NotNull(rangeExpr);
        // Use rangeExpr! for all following references

        var start = rangeExpr!.Start as IntLiteralExpression;
        Assert.NotNull(start);
        // Use start! for all following references
        Assert.Equal("2", start!.Value);

        Assert.Null(rangeExpr!.End);  // Open-ended end
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
        // Use funcDecl! for all following references
        var vars = funcDecl!.Body!.Statements.OfType<VariableDeclarationStatement>().ToList();

        var sliceDecl = vars[1];
        Assert.Equal("slice", sliceDecl.Name);
        var indexAccess = sliceDecl.Initializer as IndexAccessExpression;
        Assert.NotNull(indexAccess);
        // Use indexAccess! for all following references

        var rangeExpr = indexAccess!.Index as RangeExpression;
        Assert.NotNull(rangeExpr);
        // Use rangeExpr! for all following references
        Assert.Null(rangeExpr!.Start);  // Fully open
        Assert.Null(rangeExpr!.End);     // Fully open
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
        // Use preprocessor1! for all following references
        Assert.Equal("#if DEBUG", preprocessor1!.Directive);

        var classDecl = cu.Declarations[1] as ClassDeclaration;
        Assert.NotNull(classDecl);
        // Use classDecl! for all following references
        Assert.Equal("DebugHelper", classDecl!.Name);

        var preprocessor2 = cu.Declarations[2] as PreprocessorDeclaration;
        Assert.NotNull(preprocessor2);
        // Use preprocessor2! for all following references
        Assert.Equal("#endif", preprocessor2!.Directive);
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
        // Use funcDecl! for all following references
        Assert.NotNull(funcDecl!.Body);
        // Use funcDecl!.Body! for all following references
        Assert.Equal(3, funcDecl!.Body.Statements.Count);

        var preprocessor1 = funcDecl!.Body.Statements[0] as PreprocessorDirective;
        Assert.NotNull(preprocessor1);
        // Use preprocessor1! for all following references
        Assert.Equal("#if DEBUG", preprocessor1!.Directive);

        var printStmt = funcDecl!.Body.Statements[1] as PrintStatement;
        Assert.NotNull(printStmt);
        // Use printStmt! for all following references

        var preprocessor2 = funcDecl!.Body.Statements[2] as PreprocessorDirective;
        Assert.NotNull(preprocessor2);
        // Use preprocessor2! for all following references
        Assert.Equal("#endif", preprocessor2!.Directive);
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
        // Use preprocessor1! for all following references
        Assert.Equal("#region Helper Functions", preprocessor1!.Directive);

        var funcDecl = cu.Declarations[1] as FunctionDeclaration;
        Assert.NotNull(funcDecl);
        // Use funcDecl! for all following references

        var preprocessor2 = cu.Declarations[2] as PreprocessorDeclaration;
        Assert.NotNull(preprocessor2);
        // Use preprocessor2! for all following references
        Assert.Equal("#endregion", preprocessor2!.Directive);
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
        // Use preprocessor! for all following references
        Assert.Equal("#define FEATURE_X", preprocessor!.Directive);
    }

    [Fact]
    public void TestNullableArrayPostfixOrder()
    {
        var source = "func Use(names: string?[], maybeNames: string[]?) { }";
        var result = ColumnarParserRecovery.ParseFileAst(source, "test.nl");

        Assert.True(result.Success, string.Join(", ", result.Errors.Select(error => error.Message)));
        var func = Assert.IsType<FunctionDeclaration>(result.CompilationUnit!.Declarations[0]);

        var namesArray = Assert.IsType<ArrayTypeReference>(func.Parameters[0].Type);
        var nullableElement = Assert.IsType<NullableTypeReference>(namesArray.ElementType);
        Assert.Equal("string", Assert.IsType<SimpleTypeReference>(nullableElement.InnerType).Name);

        var nullableArray = Assert.IsType<NullableTypeReference>(func.Parameters[1].Type);
        var innerArray = Assert.IsType<ArrayTypeReference>(nullableArray.InnerType);
        Assert.Equal("string", Assert.IsType<SimpleTypeReference>(innerArray.ElementType).Name);
    }

    // Params Collections Tests
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
        // Use funcDecl! for all following references

        var varDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references
        var interpolated = Assert.IsType<InterpolatedStringExpression>(varDecl!.Initializer);
        Assert.True(interpolated.IsRaw);
        var hole = Assert.Single(interpolated.Parts.OfType<InterpolatedStringHole>());
        var memberAccess = Assert.IsType<MemberAccessExpression>(hole.Expression);
        var receiver = Assert.IsType<IdentifierExpression>(memberAccess.Object);
        Assert.Equal("person", receiver.Name);
        Assert.Equal("Name", memberAccess.MemberName);
    }

    [Fact]
    public void TestInterpolatedStringHoleParsesSemanticExpressionWithSourcePosition()
    {
        var source = @"
func Test() {
    print $""Hello, {person.Name}!""
}";

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var printStmt = Assert.IsType<PrintStatement>(funcDecl.Body!.Statements[0]);
        var interpolated = Assert.IsType<InterpolatedStringExpression>(printStmt.Value);
        var hole = Assert.IsType<InterpolatedStringHole>(interpolated.Parts[1]);
        var memberAccess = Assert.IsType<MemberAccessExpression>(hole.Expression);

        Assert.Equal("Name", memberAccess.MemberName);
        var receiver = Assert.IsType<IdentifierExpression>(memberAccess.Object);
        Assert.Equal(3, memberAccess.Line);
        Assert.Equal(21, receiver.Column);
        Assert.Equal(27, memberAccess.Column);
    }

    [Fact]
    public void TestInterpolatedStringEscapedBracesRemainTextAroundSemanticHole()
    {
        var source = @"
func Test() {
    print $""{{ {name} }}""
}";

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var printStmt = Assert.IsType<PrintStatement>(funcDecl.Body!.Statements[0]);
        var interpolated = Assert.IsType<InterpolatedStringExpression>(printStmt.Value);

        Assert.Collection(interpolated.Parts,
            part => Assert.Equal("{ ", Assert.IsType<InterpolatedStringText>(part).Text),
            part => Assert.Equal("name", Assert.IsType<IdentifierExpression>(Assert.IsType<InterpolatedStringHole>(part).Expression).Name),
            part => Assert.Equal(" }", Assert.IsType<InterpolatedStringText>(part).Text));
    }

    [Fact]
    public void TestInterpolatedStringHoleParsesTopLevelTernaryAsExpressionNotFormatClause()
    {
        var source = @"
func Test() {
    print $""{ok ? yes : no}""
}";

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var printStmt = Assert.IsType<PrintStatement>(funcDecl.Body!.Statements[0]);
        var interpolated = Assert.IsType<InterpolatedStringExpression>(printStmt.Value);
        var hole = Assert.Single(interpolated.Parts.OfType<InterpolatedStringHole>());
        var ternary = Assert.IsType<TernaryExpression>(hole.Expression);

        Assert.Null(hole.FormatClause);
        Assert.Equal("ok", Assert.IsType<IdentifierExpression>(ternary.Condition).Name);
        Assert.Equal("yes", Assert.IsType<IdentifierExpression>(ternary.ThenExpression).Name);
        Assert.Equal("no", Assert.IsType<IdentifierExpression>(ternary.ElseExpression).Name);
    }

    [Fact]
    public void TestInterpolatedStringHoleKeepsNullCoalescingFormatClause()
    {
        var source = @"
func Test() {
    print $""{value ?? fallback:N2}""
}";

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var printStmt = Assert.IsType<PrintStatement>(funcDecl.Body!.Statements[0]);
        var interpolated = Assert.IsType<InterpolatedStringExpression>(printStmt.Value);
        var hole = Assert.Single(interpolated.Parts.OfType<InterpolatedStringHole>());
        var binary = Assert.IsType<BinaryExpression>(hole.Expression);

        Assert.Equal(BinaryOperator.NullCoalesce, binary.Operator);
        Assert.Equal("N2", hole.FormatClause);
        Assert.Equal("value", Assert.IsType<IdentifierExpression>(binary.Left).Name);
        Assert.Equal("fallback", Assert.IsType<IdentifierExpression>(binary.Right).Name);
    }

    [Fact]
    public void TestInterpolatedStringHoleReportsTrailingExpressionSyntax()
    {
        var source = @"
func Test() {
    print $""{name extra}""
}";

        AssertHasParseError(source, "Unexpected token 'extra' after interpolated string expression");
    }

    [Fact]
    public void TestInterpolatedRawStringHoleParsesSemanticExpressionWithMultilineSourcePosition()
    {
        var source = @"
func Test() {
    print $""""""
Hello, {person.Name}!
""""""
}";

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var printStmt = Assert.IsType<PrintStatement>(funcDecl.Body!.Statements[0]);
        var interpolated = Assert.IsType<InterpolatedStringExpression>(printStmt.Value);
        var hole = interpolated.Parts.OfType<InterpolatedStringHole>().Single();
        var memberAccess = Assert.IsType<MemberAccessExpression>(hole.Expression);
        var receiver = Assert.IsType<IdentifierExpression>(memberAccess.Object);

        Assert.Equal("Name", memberAccess.MemberName);
        Assert.Equal(4, receiver.Line);
        Assert.Equal(9, receiver.Column);
        Assert.Equal(4, memberAccess.Line);
        Assert.Equal(15, memberAccess.Column);
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
        // Use funcDecl! for all following references
        Assert.NotNull(funcDecl!.Body);
        // Use funcDecl!.Body! for all following references

        var varDecl = funcDecl!.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references
        Assert.Equal("p", varDecl!.Name);

        var newExpr = varDecl!.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        // Use newExpr! for all following references
        Assert.Null(newExpr!.Type);  // Target-typed new has no type
        Assert.Empty(newExpr!.ConstructorArguments);
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
        // Use funcDecl! for all following references
        Assert.NotNull(funcDecl!.Body);
        // Use funcDecl!.Body! for all following references

        var varDecl = funcDecl!.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var newExpr = varDecl!.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        // Use newExpr! for all following references
        Assert.Null(newExpr!.Type);  // Target-typed new
        Assert.Equal(2, newExpr!.ConstructorArguments.Count);
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
        // Use funcDecl! for all following references
        Assert.NotNull(funcDecl!.Body);
        // Use funcDecl!.Body! for all following references

        var varDecl = funcDecl!.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var newExpr = varDecl!.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        // Use newExpr! for all following references
        Assert.Null(newExpr!.Type);  // Target-typed new
        Assert.NotNull(newExpr!.Initializer);
        // Use newExpr!.Initializer! for all following references
        Assert.Equal(2, newExpr!.Initializer.Properties.Count);
    }

    [Fact]
    public void TestCharLiteralExpression()
    {
        var source = @"
            func Main() {
                delimiter := '|'
            }
        ";

        var cu = Parse(source);
        var mainFunc = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var varDecl = Assert.IsType<VariableDeclarationStatement>(mainFunc.Body!.Statements[0]);
        var charLiteral = Assert.IsType<CharLiteralExpression>(varDecl.Initializer);
        Assert.Equal("'|'", charLiteral.Value);
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
        // Use funcDecl! for all following references

        var block = funcDecl!.Body as BlockStatement;
        Assert.NotNull(block);
        // Use block! for all following references

        var varDecl = block!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var callExpr = varDecl!.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        // Use callExpr! for all following references
        Assert.NotNull(callExpr!.TypeArguments);
        // Use callExpr!.TypeArguments! for all following references
        Assert.Single(callExpr!.TypeArguments);

        var typeArg = callExpr!.TypeArguments[0] as SimpleTypeReference;
        Assert.NotNull(typeArg);
        // Use typeArg! for all following references
        Assert.Equal("int", typeArg!.Name);

        Assert.Single(callExpr!.Arguments);
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
        // Use funcDecl! for all following references

        var block = funcDecl!.Body as BlockStatement;
        Assert.NotNull(block);
        // Use block! for all following references

        var varDecl = block!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var callExpr = varDecl!.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        // Use callExpr! for all following references
        Assert.NotNull(callExpr!.TypeArguments);
        // Use callExpr!.TypeArguments! for all following references
        Assert.Equal(3, callExpr!.TypeArguments.Count);

        var typeArg1 = callExpr!.TypeArguments[0] as SimpleTypeReference;
        Assert.NotNull(typeArg1);
        // Use typeArg1! for all following references
        Assert.Equal("int", typeArg1!.Name);

        var typeArg2 = callExpr!.TypeArguments[1] as SimpleTypeReference;
        Assert.NotNull(typeArg2);
        // Use typeArg2! for all following references
        Assert.Equal("string", typeArg2!.Name);

        var typeArg3 = callExpr!.TypeArguments[2] as SimpleTypeReference;
        Assert.NotNull(typeArg3);
        // Use typeArg3! for all following references
        Assert.Equal("bool", typeArg3!.Name);

        Assert.Equal(3, callExpr!.Arguments.Count);
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
        // Use funcDecl! for all following references

        var block = funcDecl!.Body as BlockStatement;
        Assert.NotNull(block);
        // Use block! for all following references

        var varDecl = block!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var callExpr = varDecl!.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        // Use callExpr! for all following references
        Assert.NotNull(callExpr!.TypeArguments);
        // Use callExpr!.TypeArguments! for all following references
        Assert.Single(callExpr!.TypeArguments);

        // Type argument: List<int>
        var typeArg1 = callExpr!.TypeArguments[0] as GenericTypeReference;
        Assert.NotNull(typeArg1);
        // Use typeArg1! for all following references
        Assert.Equal("List", typeArg1!.Name);
        Assert.Single(typeArg1!.TypeArguments);
        var listInner = typeArg1!.TypeArguments[0] as SimpleTypeReference;
        Assert.NotNull(listInner);
        // Use listInner! for all following references
        Assert.Equal("int", listInner!.Name);
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
        // Use funcDecl! for all following references

        var block = funcDecl!.Body as BlockStatement;
        Assert.NotNull(block);
        // Use block! for all following references

        // First call
        var varDecl1 = block!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl1);
        // Use varDecl1! for all following references

        var callExpr1 = varDecl1!.Initializer as CallExpression;
        Assert.NotNull(callExpr1);
        // Use callExpr1! for all following references
        Assert.NotNull(callExpr1!.TypeArguments);
        // Use callExpr1!.TypeArguments! for all following references
        Assert.Single(callExpr1!.TypeArguments);

        var memberAccess1 = callExpr1!.Callee as MemberAccessExpression;
        Assert.NotNull(memberAccess1);
        // Use memberAccess1! for all following references
        Assert.Equal("Method", memberAccess1!.MemberName);

        // Second call
        var varDecl2 = block!.Statements[1] as VariableDeclarationStatement;
        Assert.NotNull(varDecl2);
        // Use varDecl2! for all following references

        var callExpr2 = varDecl2!.Initializer as CallExpression;
        Assert.NotNull(callExpr2);
        // Use callExpr2! for all following references
        Assert.NotNull(callExpr2!.TypeArguments);
        // Use callExpr2!.TypeArguments! for all following references
        Assert.Single(callExpr2!.TypeArguments);

        var memberAccess2 = callExpr2!.Callee as MemberAccessExpression;
        Assert.NotNull(memberAccess2);
        // Use memberAccess2! for all following references
        Assert.Equal("OfType", memberAccess2!.MemberName);
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
        // Use funcDecl! for all following references

        var block = funcDecl!.Body as BlockStatement;
        Assert.NotNull(block);
        // Use block! for all following references

        var varDecl = block!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var callExpr = varDecl!.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        // Use callExpr! for all following references
        Assert.NotNull(callExpr!.TypeArguments);
        // Use callExpr!.TypeArguments! for all following references
        Assert.Single(callExpr!.TypeArguments);

        var typeArg = callExpr!.TypeArguments[0] as NullableTypeReference;
        Assert.NotNull(typeArg);
        // Use typeArg! for all following references
        var innerType = typeArg!.InnerType as SimpleTypeReference;
        Assert.NotNull(innerType);
        // Use innerType! for all following references
        Assert.Equal("int", innerType!.Name);
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
        // Use funcDecl! for all following references

        var block = funcDecl!.Body as BlockStatement;
        Assert.NotNull(block);
        // Use block! for all following references

        var varDecl = block!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var callExpr = varDecl!.Initializer as CallExpression;
        Assert.NotNull(callExpr);
        // Use callExpr! for all following references
        Assert.NotNull(callExpr!.TypeArguments);
        // Use callExpr!.TypeArguments! for all following references
        Assert.Single(callExpr!.TypeArguments);

        var typeArg = callExpr!.TypeArguments[0] as ArrayTypeReference;
        Assert.NotNull(typeArg);
        // Use typeArg! for all following references
        var elementType = typeArg!.ElementType as SimpleTypeReference;
        Assert.NotNull(elementType);
        // Use elementType! for all following references
        Assert.Equal("int", elementType!.Name);
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
        // Use funcDecl! for all following references

        var block = funcDecl!.Body as BlockStatement;
        Assert.NotNull(block);
        // Use block! for all following references

        var varDecl = block!.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        // Should be a binary expression, not a call expression
        var binaryExpr = varDecl!.Initializer as BinaryExpression;
        Assert.NotNull(binaryExpr);
        // Use binaryExpr! for all following references
        Assert.Equal(BinaryOperator.Less, binaryExpr!.Operator);
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
        // Use funcDecl! for all following references

        var varDecl = funcDecl!.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var newExpr = varDecl!.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        // Use newExpr! for all following references
        Assert.NotNull(newExpr!.Initializer);
        // Use newExpr!.Initializer! for all following references
        Assert.Equal(3, newExpr!.Initializer.Properties.Count);

        // First property initializer should be an indexer
        var prop1 = newExpr!.Initializer.Properties[0];
        Assert.True(prop1.IsIndexerInitializer);
        Assert.NotNull(prop1.IndexExpression);
        // Use prop1.IndexExpression! for all following references
        Assert.Null(prop1.Name);

        var indexExpr1 = prop1.IndexExpression as StringLiteralExpression;
        Assert.NotNull(indexExpr1);
        // Use indexExpr1! for all following references
        Assert.Equal("\"one\"", indexExpr1!.Value);

        var valueExpr1 = prop1.Value as IntLiteralExpression;
        Assert.NotNull(valueExpr1);
        // Use valueExpr1! for all following references
        Assert.Equal("1", valueExpr1!.Value);

        // Second property initializer
        var prop2 = newExpr!.Initializer.Properties[1];
        Assert.True(prop2.IsIndexerInitializer);
        var indexExpr2 = prop2.IndexExpression as StringLiteralExpression;
        Assert.NotNull(indexExpr2);
        // Use indexExpr2! for all following references
        Assert.Equal("\"two\"", indexExpr2!.Value);

        // Third property initializer
        var prop3 = newExpr!.Initializer.Properties[2];
        Assert.True(prop3.IsIndexerInitializer);
        var indexExpr3 = prop3.IndexExpression as StringLiteralExpression;
        Assert.NotNull(indexExpr3);
        // Use indexExpr3! for all following references
        Assert.Equal("\"three\"", indexExpr3!.Value);
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
        // Use funcDecl! for all following references

        var varDecl = funcDecl!.Body.Statements[0] as VariableDeclarationStatement;
        Assert.NotNull(varDecl);
        // Use varDecl! for all following references

        var newExpr = varDecl!.Initializer as NewExpression;
        Assert.NotNull(newExpr);
        // Use newExpr! for all following references
        Assert.NotNull(newExpr!.Initializer);
        // Use newExpr!.Initializer! for all following references
        Assert.Equal(4, newExpr!.Initializer.Properties.Count);

        // First should be property initializer
        var prop1 = newExpr!.Initializer.Properties[0];
        Assert.False(prop1.IsIndexerInitializer);
        Assert.Equal("Name", prop1.Name);
        Assert.Null(prop1.IndexExpression);

        // Second should be indexer initializer
        var prop2 = newExpr!.Initializer.Properties[1];
        Assert.True(prop2.IsIndexerInitializer);
        Assert.NotNull(prop2.IndexExpression);
        // Use prop2.IndexExpression! for all following references
        Assert.Null(prop2.Name);

        // Third should be property initializer
        var prop3 = newExpr!.Initializer.Properties[2];
        Assert.False(prop3.IsIndexerInitializer);
        Assert.Equal("Age", prop3.Name);

        // Fourth should be indexer initializer
        var prop4 = newExpr!.Initializer.Properties[3];
        Assert.True(prop4.IsIndexerInitializer);
        Assert.NotNull(prop4.IndexExpression);
        // Use prop4.IndexExpression! for all following references
    }

    [Fact]
    public void TestPackageDeclaration()
    {
        var source = @"
            package MathUtils

            func Add(a: int, b: int): int {
                return a + b
            }
        ";

        var cu = Parse(source);

        Assert.NotNull(cu.Package);
        // Use cu.Package! for all following references
        Assert.Equal("MathUtils", cu.Package.Name);
        Assert.Single(cu.Declarations);
    }

    [Fact]
    public void TestPackageBeforeImports()
    {
        var source = @"
            package NSharp.Http

            import System
            import System.Collections.Generic

            record HttpRequest {
                Method: string
            }
        ";

        var cu = Parse(source);

        Assert.NotNull(cu.Package);
        Assert.Equal("NSharp.Http", cu.Package!.Name);
        Assert.Equal(2, cu.Imports.Count);
        Assert.Equal("System", cu.Imports[0].Namespace);
        Assert.Equal("System.Collections.Generic", cu.Imports[1].Namespace);
        Assert.Single(cu.Declarations);
    }

    [Fact]
    public void TestImportsBeforePackageRemainSupported()
    {
        var source = @"
            import System

            package Compat

            func main() {}
        ";

        var cu = Parse(source);

        Assert.NotNull(cu.Package);
        Assert.Equal("Compat", cu.Package!.Name);
        Assert.Single(cu.Imports);
        Assert.Single(cu.Declarations);
    }

    [Fact]
    public void TestDottedPackageName()
    {
        var source = @"
            package MyCompany.Utils.Math

            func Multiply(a: int, b: int): int {
                return a * b
            }
        ";

        var cu = Parse(source);

        Assert.NotNull(cu.Package);
        // Use cu.Package! for all following references
        Assert.Equal("MyCompany.Utils.Math", cu.Package.Name);
    }

    [Fact]
    public void TestNoPackageDeclaration()
    {
        var source = @"
            func Add(a: int, b: int): int {
                return a + b
            }
        ";

        var cu = Parse(source);

        Assert.Null(cu.Package);
    }

    // Lambda syntax tests (Task 033)

    [Fact]
    public void Lambda_SingleParamWithoutParens_Parses()
    {
        var source = @"
            import System.Linq

            func Test() {
                items := [1, 2, 3, 4, 5]
                evens := items.Where(x => x % 2 == 0)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var evensDecl = funcDecl!.Body!.Statements[1] as VariableDeclarationStatement;

        Assert.NotNull(evensDecl);
        // Use evensDecl! for all following references
        Assert.NotNull(evensDecl!.Initializer);
        // Use evensDecl!.Initializer! for all following references
    }

    [Fact]
    public void Lambda_SingleParamWithParens_StillWorks()
    {
        var source = @"
            import System.Linq

            func Test() {
                items := [1, 2, 3, 4, 5]
                evens := items.Where((x) => x % 2 == 0)
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var evensDecl = funcDecl!.Body!.Statements[1] as VariableDeclarationStatement;

        Assert.NotNull(evensDecl);
        // Use evensDecl! for all following references
        Assert.NotNull(evensDecl!.Initializer);
        // Use evensDecl!.Initializer! for all following references
    }

    [Fact]
    public void Lambda_MultipleParams_RequiresParens()
    {
        var source = @"
            func Test() {
                items := [1, 2, 3]
                indexed := items.Select((item, index) => new { Item: item, Index: index })
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var indexedDecl = funcDecl!.Body!.Statements[1] as VariableDeclarationStatement;

        Assert.NotNull(indexedDecl);
        // Use indexedDecl! for all following references
        Assert.NotNull(indexedDecl!.Initializer);
        // Use indexedDecl!.Initializer! for all following references
    }

    [Fact]
    public void Lambda_NoParams_RequiresParens()
    {
        var source = @"
            func Test() {
                Task.Run(() => { print ""Hello"" })
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;

        Assert.NotNull(funcDecl);
        // Use funcDecl! for all following references
        Assert.NotNull(funcDecl!.Body);
        // Use funcDecl!.Body! for all following references
    }

    [Fact]
    public void Lambda_SingleParamWithBlockBody()
    {
        var source = @"
            func Test() {
                items := [1, 2, 3]
                evens := items.Where(x => {
                    print x
                    return x % 2 == 0
                })
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var evensDecl = funcDecl!.Body!.Statements[1] as VariableDeclarationStatement;

        Assert.NotNull(evensDecl);
        // Use evensDecl! for all following references
        Assert.NotNull(evensDecl!.Initializer);
        // Use evensDecl!.Initializer! for all following references
    }

    [Fact]
    public void Lambda_NestedLambdas()
    {
        var source = @"
            func Test() {
                mapper := x => y => x + y
            }
        ";

        var cu = Parse(source);
        var funcDecl = cu.Declarations[0] as FunctionDeclaration;
        var mapperDecl = funcDecl!.Body!.Statements[0] as VariableDeclarationStatement;
        var outerLambda = mapperDecl!.Initializer as LambdaExpression;

        Assert.NotNull(outerLambda);
        // Use outerLambda! for all following references
        Assert.Single(outerLambda!.Parameters);
        Assert.NotNull(outerLambda!.ExpressionBody);
        // Use outerLambda!.ExpressionBody! for all following references
    }

    [Fact]
    public void TypeReferenceSpans_CoverCompositeTypeShapes()
    {
        var source = """
record Person {
    Name: string
}

func Use(items: List<Person?>[], callback: Func<Person, string>): void {
}
""";

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[1]);

        var itemsType = Assert.IsType<ArrayTypeReference>(funcDecl.Parameters[0].Type);
        Assert.Equal(new SourceSpan(5, 17, 5, 32), itemsType.Span);

        var listType = Assert.IsType<GenericTypeReference>(itemsType.ElementType);
        Assert.Equal(new SourceSpan(5, 17, 5, 30), listType.Span);
        Assert.Equal(new SourceSpan(5, 17, 5, 21), listType.NameSpan);

        var nullablePerson = Assert.IsType<NullableTypeReference>(listType.TypeArguments[0]);
        Assert.Equal(new SourceSpan(5, 22, 5, 29), nullablePerson.Span);

        var personArg = Assert.IsType<SimpleTypeReference>(nullablePerson.InnerType);
        Assert.Equal(new SourceSpan(5, 22, 5, 28), personArg.Span);

        var callbackType = Assert.IsType<FunctionTypeReference>(funcDecl.Parameters[1].Type);
        Assert.Equal(new SourceSpan(5, 44, 5, 64), callbackType.Span);

        var callbackPerson = Assert.IsType<SimpleTypeReference>(callbackType.ParameterTypes[0]);
        Assert.Equal(new SourceSpan(5, 49, 5, 55), callbackPerson.Span);
    }

    [Fact]
    public void MustExpression_ParsesAsUnaryExpression()
    {
        var source = """
func Test(input: int?) {
    value := must input
}
""";

        var cu = Parse(source);
        var funcDecl = Assert.IsType<FunctionDeclaration>(cu.Declarations[0]);
        var valueDecl = Assert.IsType<VariableDeclarationStatement>(funcDecl.Body!.Statements[0]);
        var must = Assert.IsType<MustExpression>(valueDecl.Initializer);

        Assert.IsType<IdentifierExpression>(must.Expression);
    }

    [Fact]
    public void AnonymousUnionType_ParsesInSupportedTypePositions()
    {
        var source = """
type Greeting = PrebakedGreeting | string

record Holder {
    Value: (int | string)[]
}

func Hi(greeting: PrebakedGreeting | string): List<int | string[]> {
    casted := (PrebakedGreeting | string)greeting
    ok := greeting is PrebakedGreeting | string
    return new List<int | string[]>()
}
""";

        var cu = Parse(source);

        var alias = Assert.IsType<TypeAliasDeclaration>(cu.Declarations[0]);
        var aliasUnion = Assert.IsType<UnionTypeReference>(alias.Type);
        Assert.Equal(2, aliasUnion.Arms.Count);

        var holder = Assert.IsType<RecordDeclaration>(cu.Declarations[1]);
        var valueField = Assert.IsType<FieldDeclaration>(holder.Members[0]);
        var valueArray = Assert.IsType<ArrayTypeReference>(valueField.Type);
        Assert.IsType<UnionTypeReference>(valueArray.ElementType);

        var hi = Assert.IsType<FunctionDeclaration>(cu.Declarations[2]);
        Assert.IsType<UnionTypeReference>(hi.Parameters[0].Type);

        var returnType = Assert.IsType<GenericTypeReference>(hi.ReturnType);
        var returnUnion = Assert.IsType<UnionTypeReference>(returnType.TypeArguments[0]);
        Assert.IsType<ArrayTypeReference>(returnUnion.Arms[1]);

        var castDecl = Assert.IsType<VariableDeclarationStatement>(hi.Body!.Statements[0]);
        Assert.IsType<UnionTypeReference>(Assert.IsType<CastExpression>(castDecl.Initializer).TargetType);

        var isDecl = Assert.IsType<VariableDeclarationStatement>(hi.Body.Statements[1]);
        Assert.IsType<UnionTypeReference>(Assert.IsType<IsExpression>(isDecl.Initializer).Type);
    }

    [Fact]
    public void AnonymousUnionType_ReportsMissingRightArm()
    {
        AssertHasParseError("""
func Bad(value: int |): void {
}
""", "Expected a type after '|'");
    }
}
