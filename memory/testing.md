# Testing

## Test Suite

**Total Tests:** Do not hard-code counts here. Run `dotnet test tests/Tests.csproj` for the current unit count and `./scripts/test-all.sh` for the full product gate.

## Test Organization

### By Component
- Lexer coverage
- Parser coverage
- Analyzer coverage
- C# export coverage
- Integration coverage

### Test Files
```
tests/
├── LexerTests.cs                - Tokenization tests
├── ParserTests.cs               - Parsing tests
├── AnalyzerTests.cs             - Type checking tests
├── AnalyzerSemanticModelTests.cs - Semantic model tests
├── TranspilerTests.cs           - C# export code generation tests
├── IntegrationTests.cs          - End-to-end pipeline tests
├── LanguageServerTests.cs       - LSP handler tests (completion, hover, definition, rename)
├── ILCompilerTests.cs           - IL compilation tests
├── LinterTests.cs               - Linter diagnostic tests
├── ErrorReportingTests.cs       - Error formatting tests
├── CodeFixTests.cs              - Code fix provider tests
├── CodeIntelligenceTests.cs     - OutputFormatter unit tests
└── QueryIntegrationTests.cs     - CLI toolchain integration tests (uses real example projects)
```

## Testing Strategy

### 1. No Mocks
Tests use real components, not mocks. This ensures:
- Real-world behavior validation
- Integration coverage where feasible
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

    // Compile/analyze through the current backend under test
    Assert.Empty(result.Errors);
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

### C# Export Tests
- Expression export
- Statement export
- Declaration export
- Special cases (unions, duck interfaces, etc.)
- Indentation correctness
- C# syntax validity

### Language Server Tests
- Completion (member access, namespace, N# types)
- Hover (type info display)
- Go-to-definition
- Rename (with interpolation awareness)
- FindAllReferences
- Headless VS Code extension-host smoke tests live under `editors/vscode/src/test`
- `./scripts/test-vscode-headless.sh` builds the release server, launches VS Code in extension-host mode, exercises diagnostics/completions/hover/definition/references/code actions, and writes `.context/vscode-headless-report.json`; the implementation lives under `tests/scripts/`

### Code Intelligence Tests (CLI Toolchain)
- **QueryIntegrationTests** — runs against REAL example projects:
  - `examples/01-hello-world` — single file, functions, variables
  - `examples/06-classes-and-records` — records, members, methods
  - `examples/12-multi-file-projects/MultiFileProject` — cross-file imports, namespaces
  - `examples/05-unions` — unions, error handling
- Tests: symbols, outline, diagnostics, definition (by name + line assertions), references (cross-file), completions (member access + identifier), BindingMap, JSON schema, unhappy paths
- **CodeIntelligenceTests** — OutputFormatter unit tests (JSON envelope, Elm-style text)
- **CodeFixTests** — CodeFixProviders (auto-import, unused variable removal)

### Known Testing Limitation
`dotnet test --filter` hangs when used with this project (xUnit deadlock from assembly loading — see task 034). Run the full suite with `dotnet test` instead.

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

### Example 4: C# Export Test
```csharp
[Fact]
public void TestMatchExpressionExport()
{
    var source = "result := value match { 0 => \"zero\", _ => \"other\" }";
    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();
    var exporter = new Transpiler();
    var csharp = exporter.Transpile(ast);

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

## Full Validation (MANDATORY before committing)

```bash
./scripts/test-all.sh
```

This entrypoint runs the full gate from an isolated temporary copy of the
repository with separate HOME, temp, NuGet, and npm state. Successful isolated
runs write a content-addressed cache manifest that includes source content,
test arguments, selected environment, tool versions, and platform data; when all
of those inputs still match, follow-up invocations validate the manifest and
return the recorded green result quickly. Use `--no-cache`, `--rebuild-cache`,
or `--clean` when a fresh isolated run is required.

The full isolated run:
1. Runs all unit tests (`dotnet test`)
2. Rebuilds the compiler and SDK
3. Installs the latest SDK to local NuGet feed
4. Tests `dotnet new` template creation
5. Builds ALL example projects with `dotnet build`
6. Validates everything works end-to-end

**Never commit without test-all.sh passing.**

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
