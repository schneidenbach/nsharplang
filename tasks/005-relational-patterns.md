# Task 005: Relational Patterns in Match Expressions

**Priority:** High (F#-level pattern matching goal)
**Dependencies:** None (extends existing match implementation)
**Estimated Effort:** Medium (3-4 hours)

## Goal
Support relational patterns in match expressions for numeric comparisons (`<`, `>`, `<=`, `>=`).

## Syntax
```
result := match age {
    < 13 => "child"
    < 20 => "teen"
    >= 65 => "senior"
    _ => "adult"
}

status := match temperature {
    < 0 => "freezing"
    < 20 => "cold"
    < 30 => "comfortable"
    >= 30 => "hot"
}
```

## Implementation Steps

### 1. AST
- Create `RelationalPattern` in `Expressions.cs`:
  ```csharp
  public record RelationalPattern(
      string Operator,  // "<", ">", "<=", ">="
      Expression Value,
      int Line,
      int Column
  ) : Pattern(Line, Column);
  ```

### 2. Parser
- Modify `ParsePattern()` to detect relational operators
- Check for `<`, `>`, `<=`, `>=` at start of pattern
- Parse operator and value expression
- Create `RelationalPattern` node

### 3. Analyzer
- Validate matched value type is comparable (numeric, IComparable, etc.)
- Validate pattern value type matches matched value type
- Type check the comparison expression
- **Exhaustiveness checking**: Cannot determine exhaustiveness with relational patterns (conservative approach - skip check)

### 4. Transpiler
- Transpile to C# relational patterns (C# 9+):
  - `< 13` → `< 13`
  - `>= 65` → `>= 65`
- Example output:
  ```csharp
  var result = age switch {
      < 13 => "child",
      < 20 => "teen",
      >= 65 => "senior",
      _ => "adult"
  };
  ```

### 5. Tests
- Parser tests:
  - Parse `< value`
  - Parse `> value`
  - Parse `<= value`
  - Parse `>= value`
  - Parse in match expression context
- Analyzer tests:
  - Type checking for numeric types
  - Error on non-comparable types
  - Exhaustiveness check skipped
- Transpiler tests:
  - Correct C# relational pattern syntax
- End-to-end test: Age classification example

## Success Criteria
- [x] `< 13` parses as relational pattern
- [x] All relational operators work (`<`, `>`, `<=`, `>=`)
- [x] Type checking validates comparable types
- [x] Transpiles to C# 9+ relational patterns
- [x] All tests pass

## Notes
- C# 9+ feature, ensure target framework supports it
- Pattern evaluation order matters (first match wins)
- Cannot guarantee exhaustiveness with relational patterns
- Works with any IComparable type, not just numbers
