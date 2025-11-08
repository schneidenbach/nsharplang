# Task 001: Print Function

**Priority:** High
**Dependencies:** None
**Estimated Effort:** Small (1-2 hours)

## Goal
Implement `print` built-in function for simplified console output (no parentheses required).

## Syntax
```
print "Hello, world!"
print $"Name: {name}, Age: {age}"
print someExpression
```

## Implementation Steps

### 1. Lexer
- Add `Print` keyword token type
- Recognize `print` keyword

### 2. Parser
- Add `ParsePrintStatement()` method
- Parse: `print <expression>`
- Create new `PrintStatement` AST node in `Statements.cs`
- No parentheses required

### 3. AST
- Create `PrintStatement` record in `Statements.cs`:
  ```csharp
  public record PrintStatement(Expression Value, int Line, int Column) : Statement(Line, Column);
  ```

### 4. Analyzer
- Analyze the expression being printed
- No special type checking needed (any type can be printed)

### 5. Transpiler
- Transpile to: `Console.WriteLine(<expression>);`
- Handle expression transpilation properly

### 6. Tests
- Lexer test: Recognize `print` keyword
- Parser test: Parse print statements with various expressions
- Transpiler test: Verify C# output is `Console.WriteLine(...)`
- End-to-end test: Create example that uses print

## Success Criteria
- [x] `print "Hello"` transpiles to `Console.WriteLine("Hello");`
- [x] `print $"Value: {x}"` works with interpolation
- [x] `print someVar` works with any expression
- [x] All tests pass

## Notes
- Always adds newline (like println in other languages)
- Replaces need for `Console.WriteLine()` in user code
- Examples should be updated to use `print` instead of `Console.WriteLine`
