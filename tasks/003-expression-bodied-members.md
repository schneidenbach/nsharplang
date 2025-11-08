# Task 003: Expression-Bodied Members

**Priority:** Medium
**Dependencies:** None
**Estimated Effort:** Medium (3-4 hours)

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
- [x] `FullName => $"{First} {Last}"` infers string type
- [x] `func Add(a: int, b: int) => a + b` transpiles correctly
- [x] Type inference works for property expressions
- [x] All tests pass

## Notes
- Cleaner, more concise syntax for simple members
- Type inference only for properties (methods still need return type)
- Same visibility rules apply (PascalCase = public, camelCase = private)
