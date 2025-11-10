# Task 009: Testing Support (.tests.nl files) ✅ COMPLETED

**Priority:** High (Developer experience)
**Dependencies:** None
**Estimated Effort:** Large (6-8 hours)
**Completed:** v1.27-v1.28

## Goal
Support inline test files (`.tests.nl`) that compile as XUnit tests with `test` syntax and smart `assert` transpilation.

## Syntax
```
// Calculator.tests.nl

test "should add two numbers correctly" {
    result := Add(2, 3)
    assert result == 5
    assert result > 0
}

test "should handle null values" {
    value := GetValue()
    assert value != null
    assert value.Length > 0
}

test "should throw exception for invalid input" {
    _, err := ProcessInvalid()
    assert err != null
}
```

## Implementation Steps

### 1. File Detection
- CLI: Detect `.tests.nl` files separately from `.nl` files
- Create separate compilation unit for tests
- Link test project to main project (reference)

### 2. Lexer
- Add `Test` keyword token
- Add `Assert` keyword token

### 3. Parser
- Add `ParseTestDeclaration()` method
- Parse: `test <string> <block>`
- Create `TestDeclaration` AST node:
  ```csharp
  public record TestDeclaration(
      string Description,
      BlockStatement Body,
      int Line,
      int Column
  ) : Declaration(Line, Column);
  ```
- Add `ParseAssertStatement()` method
- Parse: `assert <expression>`
- Create `AssertStatement` AST node:
  ```csharp
  public record AssertStatement(
      Expression Condition,
      int Line,
      int Column
  ) : Statement(Line, Column);
  ```

### 4. Analyzer
- Analyze test body like function body
- Analyze assert expressions (must evaluate to boolean or use comparison)
- Track all variable declarations in test scope

### 5. Transpiler - Smart Assert Translation
- Detect expression type in assert and map to appropriate XUnit method:
  - `assert x == y` → `Assert.Equal(y, x);`
  - `assert x != y` → `Assert.NotEqual(y, x);`
  - `assert x > y` → `Assert.True(x > y);`
  - `assert x < y` → `Assert.True(x < y);`
  - `assert x >= y` → `Assert.True(x >= y);`
  - `assert x <= y` → `Assert.True(x <= y);`
  - `assert x` → `Assert.True(x);`
  - `assert x is Type` → `Assert.IsType<Type>(x);`
  - `assert x != null` → `Assert.NotNull(x);`

- Transpile test to XUnit [Fact] method:
  ```csharp
  [Fact]
  public void ShouldAddTwoNumbersCorrectly() {
      var result = Add(2, 3);
      Assert.Equal(5, result);
      Assert.True(result > 0);
  }
  ```

### 6. CLI Integration
- `nlc build` - Compile tests into separate assembly
- `nlc test` - Run tests with `dotnet test`
- Generate test .csproj with XUnit dependencies:
  ```xml
  <PackageReference Include="xunit" Version="2.6.0" />
  <PackageReference Include="xunit.runner.visualstudio" Version="2.5.0" />
  ```

### 7. Test Method Naming
- Convert test description to valid C# method name:
  - Remove quotes
  - Convert to PascalCase
  - Remove special characters
  - Example: `"should add two numbers"` → `ShouldAddTwoNumbers`

### 8. Tests (Meta!)
- Parser tests: Parse test declarations
- Parser tests: Parse assert statements
- Transpiler tests: Various assert patterns
- Integration test: Full .tests.nl file compiles and runs

## Success Criteria
- [x] `.tests.nl` files detected by CLI
- [x] `test "description" { }` syntax works
- [x] `assert` statements transpile to correct XUnit methods
- [x] Tests can access symbols from main project
- [x] `nlc test` runs tests successfully
- [x] Test output shown in console
- [x] All tests pass

## Notes
- Tests inline with code (like Rust, Go)
- No separate test project structure needed
- Full XUnit compatibility
- Can use any XUnit features via direct C# interop if needed
