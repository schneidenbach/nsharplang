# Testing

## Test Suite

**Total Tests:** 506 passing, 0 skipped

## Test Organization

### By Component
- **Lexer**: 33 tests
- **Parser**: 86 tests
- **Analyzer**: 78 tests
- **Transpiler**: 71 tests
- **Integration**: 238+ tests

### Test Files
```
tests/
├── LexerTests.cs      - Tokenization tests
├── ParserTests.cs     - Parsing tests
├── AnalyzerTests.cs   - Type checking tests
└── TranspilerTests.cs - Code generation tests
```

## Testing Strategy

### 1. No Mocks
Tests use real components, not mocks. This ensures:
- Real-world behavior validation
- Integration testing by default
- Simpler test code

### 2. Focused Tests
Each test validates one specific feature:
```csharp
[Fact]
public void TestVariableDeclaration()
{
    var source = "let x := 42";
    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var ast = parser.ParseCompilationUnit();

    var stmt = ast.Statements[0] as VariableDeclarationStatement;
    Assert.NotNull(stmt);
    Assert.Equal("x", stmt.Name);
}
```

### 3. End-to-End Validation
Integration tests validate full pipeline:
```csharp
[Fact]
public void TestFullCompilation()
{
    var source = "let x := 42";

    // Lex
    var tokens = new Lexer(source, "test").Tokenize();

    // Parse
    var ast = new Parser(tokens, "test").ParseCompilationUnit();

    // Analyze
    var result = new Analyzer().Analyze(ast, "test", "/");
    Assert.Empty(result.Errors);

    // Transpile
    var csharp = new Transpiler().Transpile(ast);
    Assert.Contains("var x = 42;", csharp);
}
```

## Test Categories

### Lexer Tests
- Keyword recognition
- Operator tokenization
- String interpolation
- Numeric literals
- Comments
- Error handling

### Parser Tests
- Statement parsing (if, for, while, etc.)
- Expression parsing (binary, unary, calls, etc.)
- Declaration parsing (class, func, record, etc.)
- Operator precedence
- Pattern parsing
- Error recovery

### Analyzer Tests
- Type inference
- Type checking
- Name resolution
- Scope management
- External type resolution
- Pattern exhaustiveness
- Definite assignment
- Duck interface validation
- Error detection

### Transpiler Tests
- Expression transpilation
- Statement transpilation
- Declaration transpilation
- Special cases (unions, duck interfaces, etc.)
- Indentation correctness
- C# syntax validity

## Running Tests

### All Tests
```bash
dotnet test tests/Tests.csproj
```

### Specific Test Class
```bash
dotnet test --filter ClassName=LexerTests
```

### Specific Test Method
```bash
dotnet test --filter FullyQualifiedName~TestVariableDeclaration
```

### With Detailed Output
```bash
dotnet test -v detailed
```

## Test Examples

### Example 1: Lexer Test
```csharp
[Fact]
public void TestStringInterpolation()
{
    var source = "$\"Hello {name}\"";
    var lexer = new Lexer(source, "test");
    var tokens = lexer.Tokenize();

    Assert.Single(tokens);
    Assert.Equal(TokenType.StringLiteral, tokens[0].Type);
    Assert.Equal("$\"Hello {name}\"", tokens[0].Value);
}
```

### Example 2: Parser Test
```csharp
[Fact]
public void TestMatchExpression()
{
    var source = "result := value match { 0 => \"zero\", _ => \"other\" }";
    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var ast = parser.ParseCompilationUnit();

    var stmt = ast.Statements[0] as VariableDeclarationStatement;
    var match = stmt.Initializer as MatchExpression;
    Assert.NotNull(match);
    Assert.Equal(2, match.Cases.Count);
}
```

### Example 3: Analyzer Test
```csharp
[Fact]
public void TestTypeMismatchError()
{
    var source = "let x: int = \"hello\"";
    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();
    var result = new Analyzer().Analyze(ast, "test", "/");

    Assert.NotEmpty(result.Errors);
    Assert.Contains("Type mismatch", result.Errors[0].Message);
}
```

### Example 4: Transpiler Test
```csharp
[Fact]
public void TestMatchExpressionTranspilation()
{
    var source = "result := value match { 0 => \"zero\", _ => \"other\" }";
    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();
    var transpiler = new Transpiler();
    var csharp = transpiler.Transpile(ast);

    Assert.Contains("value switch", csharp);
    Assert.Contains("0 => \"zero\"", csharp);
    Assert.Contains("_ => \"other\"", csharp);
}
```

## Test Coverage

### Features Tested
- ✅ All statement types
- ✅ All expression types
- ✅ All declaration types
- ✅ Type inference
- ✅ Type checking
- ✅ Pattern matching
- ✅ External types
- ✅ Duck interfaces
- ✅ Unions and enums
- ✅ Async/await
- ✅ Iterators
- ✅ Error handling
- ✅ String interpolation
- ✅ Operator overloading
- ✅ Conversion operators
- ✅ Params collections
- ✅ List patterns
- ✅ And much more...

## N# Test Files (.tests.nl)

Future feature: Write tests in N# itself:

```
// example.tests.nl
using Xunit

class CalculatorTests {
    [Fact]
    func TestAdd() {
        calc := new Calculator()
        result := calc.Add(2, 3)
        Assert.Equal(5, result)
    }
}
```

Run with:
```bash
nlc test
```

## Continuous Testing

Tests run on:
- Every commit (CI/CD)
- Before releases
- During development (watch mode)

## Test Quality Standards

1. **One assertion per test** (when possible)
2. **Descriptive test names** (TestFeature_Scenario_ExpectedBehavior)
3. **Arrange-Act-Assert pattern**
4. **No test interdependencies**
5. **Fast execution** (all tests < 5 seconds)
