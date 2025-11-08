# Task 002: nameof and typeof Operators

**Priority:** High
**Dependencies:** None
**Estimated Effort:** Small (2-3 hours)

## Goal
Implement `nameof` and `typeof` reflection operators for better refactoring safety and type information.

## Syntax

### nameof
```
throw new ArgumentNullException(nameof(parameter))
fieldName := nameof(person.Name)  // "Name"
propName := nameof(SomeClass)     // "SomeClass"
```

### typeof
```
type := typeof(Person)
if obj.GetType() == typeof(string) { }
genericType := typeof(List<int>)
```

## Implementation Steps

### 1. Lexer
- Add `Nameof` keyword token type
- Add `Typeof` keyword token type
- Recognize both keywords

### 2. Parser
- Add `ParseNameofExpression()` method
- Add `ParseTypeofExpression()` method
- Parse: `nameof(<identifier or member access>)`
- Parse: `typeof(<type>)`
- Both are parsed at primary expression level

### 3. AST
- Create `NameofExpression` in `Expressions.cs`:
  ```csharp
  public record NameofExpression(Expression Target, int Line, int Column) : Expression(Line, Column);
  ```
- Create `TypeofExpression` in `Expressions.cs`:
  ```csharp
  public record TypeofExpression(TypeReference Type, int Line, int Column) : Expression(Line, Column);
  ```

### 4. Analyzer
- **nameof**: Analyze target expression (must be valid identifier/member)
- Type: always `string`
- **typeof**: Validate type reference exists
- Type: `System.Type`

### 5. Transpiler
- **nameof**: Transpile to C# `nameof()` with same syntax
  - Extract final identifier name from member access chains
- **typeof**: Transpile to C# `typeof()` with same syntax

### 6. Tests
- Lexer tests: Recognize both keywords
- Parser tests:
  - `nameof(variable)`
  - `nameof(obj.Property)`
  - `typeof(int)`
  - `typeof(Person)`
  - `typeof(List<string>)`
- Transpiler tests: Verify correct C# output
- Analyzer tests: Type checking works correctly
- End-to-end test: Use in exception throwing and type checking

## Success Criteria
- [x] `nameof(parameter)` transpiles to `nameof(parameter)`
- [x] `nameof(obj.Prop)` extracts correct identifier
- [x] `typeof(Person)` transpiles to `typeof(Person)`
- [x] typeof works with generics
- [x] All tests pass

## Notes
- Direct transpilation to C# equivalents (C# 6+ feature)
- nameof improves refactoring safety
- typeof is essential for reflection scenarios
