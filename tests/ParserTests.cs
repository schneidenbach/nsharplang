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
