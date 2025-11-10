# Task 003: Expression-Bodied Members ✅ COMPLETED

**Priority:** Medium
**Dependencies:** None
**Estimated Effort:** Medium (3-4 hours)
**Completed:** v1.19

## Goal
Support expression-bodied syntax for properties and methods using `=>` for single-expression implementations.

## Syntax

### Expression-Bodied Properties
```
class Person {
    FirstName: string
    LastName: string

    // Type inferred from expression
    FullName => $"{FirstName} {LastName}"

    // Computed property
    Age => DateTime.Now.Year - BirthYear
}
```

### Expression-Bodied Methods
```
class Calculator {
    func Add(a: int, b: int) => a + b

    func Greet(name: string) => print $"Hello, {name}!"
}
```

## Implementation Steps

### 1. Parser
- Modify `ParseMemberDeclaration()` to detect `=>` after property/method signature
- For properties:
  - If no `:` type annotation, type will be inferred
  - Parse: `PropertyName => expression`
- For methods:
  - Parse: `func MethodName(...) => expression`
- Create expression-bodied AST variants or add flag to existing nodes

### 2. AST Options

**Option A:** Add flag to existing declarations
- Add `ExpressionBody: Expression?` to PropertyDeclaration
- Add `ExpressionBody: Expression?` to FunctionDeclaration

**Option B:** Create new node types
- `ExpressionBodiedProperty`
- `ExpressionBodiedMethod`

**Recommendation:** Option A (simpler, less duplication)

### 3. Analyzer
- For expression-bodied properties:
  - **Infer type from expression** if no explicit type given
  - Expression must return a value (not void)
- For expression-bodied methods:
  - Check expression type matches return type
  - If method returns void, expression can be any type (statement expression)

### 4. Transpiler
- **Properties**: Transpile to C# property with `=>` syntax
  ```csharp
  public string FullName => $"{FirstName} {LastName}";
  ```
- **Methods**: Transpile to C# method with `=>` syntax
  ```csharp
  public int Add(int a, int b) => a + b;
  ```

### 5. Tests
- Parser tests:
  - Property with inferred type
  - Property with explicit type and expression body
  - Method with expression body (value returning)
  - Method with expression body (void/statement)
- Analyzer tests:
  - Type inference works for properties
  - Type checking works for methods
- Transpiler tests:
  - Correct C# syntax generated
- End-to-end test: Class with multiple expression-bodied members

## Success Criteria
- [x] Expression-bodied properties with explicit types work
- [x] `func Add(a: int, b: int) => a + b` transpiles correctly
- [x] Type validation ensures expression matches declared type
- [x] All tests pass

## Notes
- Cleaner, more concise syntax for simple members
- **Implementation Decision**: Type inference NOT supported for properties (C# limitation)
  - C# doesn't allow `var` for class/struct members, only local variables
  - Properties require explicit type declaration for C# compatibility
  - Syntax: `PropName: type => expression` (type required)
- Same visibility rules apply (PascalCase = public, camelCase = private)

## Implementation Summary (v1.19)
- Added `ExpressionBody` field to `PropertyDeclaration` and `FunctionDeclaration`
- Parser detects `=>` and parses expression body
- Analyzer validates expression type matches declared type
- Transpiler emits C# expression-bodied syntax
- 8 new tests added, all passing
- Example: `examples/expression_bodied_members.nl`
