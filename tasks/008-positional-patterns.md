# Task 008: Positional Patterns

**Priority:** Medium (F#-level pattern matching goal)
**Dependencies:** None
**Estimated Effort:** Medium (4-5 hours)

## Goal
Support positional patterns for tuple and deconstructable type matching.

## Syntax

### Tuple Patterns
```
result := match point {
    (0, 0) => "origin"
    (0, y) => $"on y-axis at {y}"
    (x, 0) => $"on x-axis at {x}"
    (x, y) when x == y => "on diagonal"
    (x, y) => $"at ({x}, {y})"
}
```

### With Literals and Wildcards
```
result := match coordinate {
    (0, _, _) => "on YZ plane"
    (_, 0, _) => "on XZ plane"
    (_, _, 0) => "on XY plane"
    (1, 2, 3) => "specific point"
    _ => "somewhere else"
}
```

### Nested Positional Patterns
```
result := match nestedTuple {
    ((0, 0), _) => "first point is origin"
    (_, (0, 0)) => "second point is origin"
    ((x1, y1), (x2, y2)) => "two points"
}
```

## Implementation Steps

### 1. AST
- Create `PositionalPattern` in `Expressions.cs`:
  ```csharp
  public record PositionalPattern(
      List<Pattern> Elements,  // Patterns for each position
      int Line,
      int Column
  ) : Pattern(Line, Column);
  ```

### 2. Parser
- Modify `ParsePattern()` to recognize tuple syntax
- When encountering `(`, parse as positional pattern
- Elements can be:
  - Literal patterns: `0`, `"value"`
  - Identifier patterns: `x`, `y` (bindings)
  - Wildcard: `_`
  - Nested patterns: `(nested, tuple)`
- Distinguish from parenthesized expressions

### 3. Analyzer
- Validate matched value is tuple or deconstructable type
- Check element count matches tuple arity
- Type check each element pattern against corresponding tuple element type
- Bind variables for identifier patterns
- For deconstructable types, check Deconstruct method exists

### 4. Transpiler
- Transpile to C# positional patterns (C# 8+):
  ```csharp
  var result = point switch {
      (0, 0) => "origin",
      (0, var y) => $"on y-axis at {y}",
      (var x, 0) => $"on x-axis at {x}",
      (var x, var y) when x == y => "on diagonal",
      (var x, var y) => $"at ({x}, {y})"
  };
  ```
- Use `var` for bindings, literal values directly
- Wildcard `_` → `_` in C#

### 5. Tests
- Parser tests:
  - Simple tuple pattern: `(x, y)`
  - With literals: `(0, y)`
  - With wildcards: `(_, y, _)`
  - Nested: `((a, b), c)`
- Analyzer tests:
  - Tuple arity checking
  - Type checking for elements
  - Variable binding
- Transpiler tests:
  - Correct C# positional pattern syntax
  - Variable bindings with `var`
  - Nested patterns
- End-to-end test: Point coordinate matching

## Success Criteria
- [x] `(0, 0)` matches tuple at origin
- [x] `(x, y)` binds both variables
- [x] `(_, y, _)` uses wildcard correctly
- [x] Nested positional patterns work
- [x] Transpiles to C# 8+ positional patterns
- [x] All tests pass

## Notes
- C# 8+ feature
- Works with ValueTuple and any type with Deconstruct method
- Very natural for tuple matching
- Combines well with guards for complex conditions
