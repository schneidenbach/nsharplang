# Analyzer Component

**File:** `src/NSharpLang.Compiler/Analyzer.cs`

## Responsibility

Performs semantic analysis, type checking, and name resolution on the AST.

## Core Functions

1. **Type Checking**: Ensures expressions have compatible types
2. **Type Inference**: Infers types for `:=` declarations
3. **Name Resolution**: Resolves identifiers to declarations
4. **Scope Management**: Tracks nested scopes (global, class, function, block)
5. **External Type Resolution**: Resolves .NET types via reflection
6. **Error Detection**: Reports type errors, undefined names, etc.

## Scope Management

### Scope Hierarchy
```
Global Scope
└── Class Scope (per class/struct/record)
    └── Function Scope (per function)
        └── Block Scope (per { }, if, for, while, etc.)
```

### Symbol Tables
Each scope has a symbol table mapping names to types:
```csharp
Dictionary<string, TypeInfo> _currentScope;
```

Scopes are managed via:
- `EnterScope()`: Push new scope
- `ExitScope()`: Pop scope
- `DeclareSymbol(name, type)`: Add to current scope
- `LookupSymbol(name)`: Search current + parent scopes

## Type System

See `src/NSharpLang.Compiler/TypeSystem/TypeInfo.cs` for type representations:

### Built-in Types
- **PrimitiveTypeInfo**: `int`, `long`, `float`, `double`, `bool`, `string`, `void`
- **UnknownTypeInfo**: Type not yet resolved

### User-Defined Types
- **ClassTypeInfo**: From class declarations
- **StructTypeInfo**: From struct declarations
- **RecordTypeInfo**: From record declarations (reference or struct)
- **InterfaceTypeInfo**: From interface declarations
- **UnionTypeInfo**: From union declarations
- **EnumTypeInfo**: From enum declarations (int or string)

### External Types
- **ReflectionTypeInfo**: .NET types loaded via reflection (e.g., `System.Console`)
- **ReflectionMethodInfo**: Single method from external type
- **ReflectionMethodGroupInfo**: Overloaded methods (multiple signatures)
- **ExternalTypeInfo**: Unresolved external type (placeholder)

### Special Types
- **FunctionTypeInfo**: Function signatures
- **ArrayTypeInfo**: Array types (`T[]`)
- **GenericTypeInfo**: Generic types (`List<T>`)
- **NullableTypeInfo**: Nullable types (`T?`)

## External Type Resolution

The Analyzer tracks `using` statements and resolves external types via .NET reflection.

### Process
1. Parse `using System.Collections.Generic`
2. Store namespace in `_usingStatements`
3. When encountering unresolved identifier like `List`:
   - Try `System.Collections.Generic.List`
   - Use `Type.GetType()` to load via reflection
   - Wrap in `ReflectionTypeInfo`
4. Member access on external types:
   - Use reflection to get properties, fields, methods
   - Wrap in appropriate `TypeInfo` subclass

### Method Overload Resolution
For external methods with multiple overloads:
- Create `ReflectionMethodGroupInfo` with all signatures
- During call analysis, pick best match by argument count
- **Limitation:** Only checks count, not types

## Type Checking

### Assignment Compatibility
`IsAssignable(target, source)` checks if source can be assigned to target:
- Exact type match
- Inheritance (class → base class)
- Interface implementation (class → interface)
- Duck interface structural typing (see `memory/features/duck-interfaces.md`)
- User-defined implicit conversions
- Nullable conversions (`T → T?`)
- Array covariance (`Derived[] → Base[]`)

### Type Inference
For `:=` declarations:
- Infer from initializer expression type
- If array literal, infer array type from elements
- If lambda, type remains `Unknown` (limited context inference)

### Definite Assignment
For non-nullable fields:
- Must be assigned in constructor
- Analyzer tracks which fields are assigned
- Reports error if field not initialized

### Error Tuple Result Availability
For Go-style error tuples (`result, err := MightFail()`):
- The result is available only on paths where the paired `err` is proven `null`
- `if err == null { ... }` makes the result available inside the success branch
- `if err != null { return }` or `throw` makes the result available after the guard
- Using the result while `err` may be non-null reports `NL314`

## Convention-Based Visibility

Enforced by Analyzer:
- `PascalCase` identifiers → public
- `camelCase` identifiers → private
- Explicit modifiers override convention

Warnings (not errors) for non-conforming names.

## Pattern Matching Analysis

### Match Exhaustiveness Checking
For discriminated unions:
- Check all union cases are covered
- Allow wildcard `_` as catch-all
- Report missing cases if non-exhaustive

Guard handling:
- Guarded arms do not count toward coverage (only partial)
- Unguarded arms count as full coverage
- Catch-all bindings (`_` or plain identifiers) cover all remaining cases

Skipped when:
- Non-union types (can't enumerate all values)

### Pattern Type Checking
- Validates pattern variables have correct types
- Ensures property patterns match union case properties
- Type checks guard expressions (must be bool)

## Circular Import Detection

Project compilation detects circular file imports before semantic analysis:
- **Self-import**: File importing itself (A -> A)
- **Two-file cycle**: A -> B -> A
- **Longer chains**: A -> B -> C -> A and longer cycles
- Reports `ErrorCode.CircularImport` (NL703) with a bounded cycle path and a suggested refactor to extract shared declarations or invert one dependency

The analyzer still has a shallow per-file guard in `ProcessFileImport` for direct self-import and two-file cycles, but `MultiFileCompiler` owns the complete project-level graph diagnostic.

## Error Reporting

Analyzer emits `CompilerError` records with:
- **Error code**: `NL001`-`NL999` (see `ErrorReporting.cs`)
- **Message**: Human-readable description
- **Location**: File, line, column
- **Suggestions**: Helpful hints (e.g., "Did you mean X?")

## Testing

Analyzer has 78 unit tests covering:
- Type checking (primitives, classes, generics)
- Type inference
- Name resolution
- Scope management
- External type resolution
- Pattern matching exhaustiveness
- Definite assignment
- Duck interfaces
- Error detection

See `tests/AnalyzerTests.cs`.

## Usage Example

```csharp
var ast = parser.ParseCompilationUnit();
var analyzer = new Analyzer();
var result = analyzer.Analyze(ast, "example.nl", "/project/root");

if (result.Errors.Any())
{
    foreach (var error in result.Errors)
        Console.WriteLine(error.Format());
}
else
{
    // Proceed to transpilation
}
```
