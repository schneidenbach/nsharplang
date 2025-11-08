# Task 007: Nested Property Patterns

**Priority:** Medium (F#-level pattern matching goal)
**Dependencies:** None (extends existing property patterns)
**Estimated Effort:** Medium (3-4 hours)

## Goal
Support nested property patterns for deep object destructuring in match expressions.

## Syntax

### Single-Level Nesting
```
result := match person {
    { Name: "John" } => "Found John"
    _ => "Someone else"
}
```

### Deep Nesting
```
result := match person {
    { Address: { City: "NYC", State: "NY" } } => "New Yorker"
    { Address: { State: "CA" } } => "Californian"
    { Address: null } => "No address"
    _ => "Other location"
}
```

### With Variable Binding
```
result := match person {
    { Address: { City: city, State: "NY" } } => $"NY resident of {city}"
    { Address: addr } => $"Lives at {addr.City}"
    _ => "Unknown"
}
```

## Implementation Steps

### 1. AST
- Existing `UnionCasePattern` has `Properties` list
- Each property can have a pattern value
- Modify to allow nested patterns:
  ```csharp
  public record PropertyPattern(
      string Name,
      Pattern? Pattern,  // Can be another UnionCasePattern for nesting
      string? BindingName,
      int Line,
      int Column
  );
  ```

### 2. Parser
- Modify `ParsePattern()` for property patterns
- When parsing property value, recursively call `ParsePattern()`
- Support:
  - `{ Prop: value }` - literal
  - `{ Prop: varName }` - binding
  - `{ Prop: { Nested: value } }` - nested pattern
  - `{ Prop: null }` - null check

### 3. Analyzer
- Recursively validate nested patterns
- Check each property exists on the type
- Verify nested types match property types
- Create scopes for bound variables at each nesting level

### 4. Transpiler
- Transpile to C# nested property patterns:
  ```csharp
  { Address: { City: "NYC", State: "NY" } } => "New Yorker"
  ```
- Handle variable binding:
  ```csharp
  { Address: { City: var city, State: "NY" } } => $"NY resident of {city}"
  ```

### 5. Tests
- Parser tests:
  - Single-level property pattern
  - Two-level nesting
  - Three-level nesting
  - Mixed literals and bindings
  - Null patterns
- Analyzer tests:
  - Property existence validation
  - Type checking at each level
  - Variable binding scope
- Transpiler tests:
  - Correct C# nested syntax
  - Variable binding with `var`
- End-to-end test: Address matching example

## Success Criteria
- [x] `{ Address: { City: "NYC" } }` parses and type-checks
- [x] Variable binding works at nested levels
- [x] Null patterns work: `{ Prop: null }`
- [x] Transpiles to valid C# nested property patterns
- [x] All tests pass

## Notes
- C# 8+ feature (property patterns)
- Very powerful for complex object matching
- Combines well with union types
- Can nest arbitrarily deep
