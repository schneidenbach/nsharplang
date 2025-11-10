# Task 006: Logical Patterns (and/or/not) ✅ COMPLETED

**Priority:** High (F#-level pattern matching goal)
**Dependencies:** Task 005 (relational patterns recommended first)
**Estimated Effort:** Medium (4-5 hours)
**Completed:** v1.20

## Goal
Support logical combinators in patterns for complex matching conditions.

## Syntax

### And Pattern
```
result := match value {
    > 0 and < 100 => "valid range"
    _ => "out of range"
}
```

### Or Pattern
```
result := match status {
    "active" or "pending" => "in progress"
    "completed" or "cancelled" => "finished"
    _ => "unknown"
}
```

### Not Pattern
```
result := match value {
    not 0 => "non-zero"
    _ => "zero"
}
```

### Complex Combinations
```
result := match (age, status) {
    (>= 18, "active") or (>= 16, "premium") => "allowed"
    _ => "denied"
}
```

## Implementation Steps

### 1. AST
- Create logical pattern types in `Expressions.cs`:
  ```csharp
  public record AndPattern(
      Pattern Left,
      Pattern Right,
      int Line,
      int Column
  ) : Pattern(Line, Column);

  public record OrPattern(
      Pattern Left,
      Pattern Right,
      int Line,
      int Column
  ) : Pattern(Line, Column);

  public record NotPattern(
      Pattern Inner,
      int Line,
      int Column
  ) : Pattern(Line, Column);
  ```

### 2. Lexer
- `and`, `or`, `not` keywords already exist
- Ensure they're recognized in pattern context

### 3. Parser
- Modify `ParsePattern()` with precedence:
  - Lowest: `or` (binary, left-associative)
  - Middle: `and` (binary, left-associative)
  - Highest: `not` (unary prefix)
- Example parsing:
  - `> 0 and < 100` → `AndPattern(RelationalPattern(">", 0), RelationalPattern("<", 100))`
  - `not 0` → `NotPattern(LiteralPattern(0))`

### 4. Analyzer
- Validate inner patterns type-check correctly
- And/Or: Both sides must match same type
- Not: Inner pattern must match value type
- Exhaustiveness checking: Conservative approach (skip when logical patterns present)

### 5. Transpiler
- Transpile to C# 9+ logical patterns:
  - `and` → `and`
  - `or` → `or`
  - `not` → `not`
- Example:
  ```csharp
  var result = value switch {
      > 0 and < 100 => "valid range",
      _ => "out of range"
  };
  ```

### 6. Tests
- Parser tests:
  - `and` pattern
  - `or` pattern
  - `not` pattern
  - Nested combinations
  - Precedence: `a or b and c` parses as `a or (b and c)`
- Analyzer tests:
  - Type checking for logical patterns
  - Both sides compatible types
- Transpiler tests:
  - Correct C# logical pattern syntax
  - Complex nested patterns
- End-to-end test: Range validation example

## Success Criteria
- [x] `> 0 and < 100` works as expected
- [x] `"a" or "b"` works with literals
- [x] `not 0` works as negation
- [x] Precedence: `or` < `and` < `not`
- [x] Transpiles to C# 9+ logical patterns
- [x] All tests pass

## Notes
- C# 9+ feature
- Operator precedence matches C# and most languages
- Parentheses can override precedence
- Powerful when combined with relational patterns
