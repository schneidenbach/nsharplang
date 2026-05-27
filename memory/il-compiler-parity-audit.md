# IL Compiler Parity Audit

## Scope

Comparison basis:
- AST surface in `src/NSharpLang.Compiler/Ast`
- Features the transpiler already handles in `src/NSharpLang.Compiler/Transpiler.cs`
- Features the direct IL backend handles in `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`

## Implemented In This Pass

- Added execution-based IL tests instead of only compile-without-throw coverage.
- Added direct IL support for:
  - `for`
  - `break`
  - `continue`
  - `throw`
  - `lock`
  - `switch`
  - `empty` statements
  - float literals
  - null literals
  - null equality/inequality for CLR references, emitted class types, and nullable value types
  - unary operators for numeric negation, logical not, bitwise not, and increment/decrement
  - tuple expressions and tuple deconstruction
  - index access
  - ternary expressions
  - array literals
  - casts (`as` and hard casts)
  - `is` expressions with binding
  - `typeof`
  - `nameof`
  - `base`
  - `checked`
  - `unchecked`
  - string concatenation in binary `+`
  - null-coalescing `??`
  - nullable value-type `??` result typing and emission
  - array, nullable, tuple, and function type resolution
  - external CLR type resolution by name/import
  - type alias resolution
  - static CLR type member access and static method calls
  - primitive CLR alias resolution for `byte`, `short`, `uint`, `ulong`, `decimal`, `char`, and related built-ins
  - `enum` declarations
  - `newtype` declarations
  - indexer declarations
  - primary constructors on classes and structs
  - value-type instance member/method dispatch needed by struct/newtype emission
  - union declarations with nested CLR case types
  - union-case and object-property pattern emission
  - `ref`/`out` parameters with explicit out variables
  - `AssertStatement`
  - `AssertThrowsStatement`
  - `SizeOfExpression`
  - target-typed `new`
  - object and indexer initializers within `new`
  - null-coalescing assignment `??=`
  - null-conditional member and index access, including nullable wrapping for value-type results
  - context-aware `default`
  - `RangeExpression` and `^`/index-from-end lowering for arrays and strings
  - spread passthrough in calls plus spread flattening in array literals
  - `with` expressions via shallow clone plus member updates
  - tuple positional patterns
  - `Deconstruct`-based positional patterns
  - array list/slice patterns, including slice bindings
  - count/indexer-based list patterns for collection-like CLR types, with slice bindings lowered to arrays
  - generated xUnit test types for `test`, `setup`, and `teardown` declarations
  - xUnit async lifecycle generation via `IAsyncLifetime` for async `setup` / `teardown`
  - generic type declarations on classes, structs, records, and interfaces
  - interface implementation override emission, including closed generic interfaces
  - statement-level preprocessor/import nodes as runtime no-ops after earlier pipeline processing
  - delegate invocation and lambda/function delegate arities beyond 4 parameters
  - local functions, including forward references, recursion, generic local functions, captured generic local functions, async/generator local functions, and delegate conversion
  - `await`, `yield`, and `await foreach`
  - params expansion for `Span<T>` and `ReadOnlySpan<T>` in addition to arrays/list-like collections
  - CLR/runtime method call binding for overload selection, named and optional arguments, params expansion, and generic method inference/explicit type arguments
  - primitive, enum, decimal, and nullable constant emission needed for CLR optional parameter defaults
  - custom attribute emission on types, methods, constructors, properties, indexers, fields, and parameters
  - declaration visibility for top-level types and methods/constructors/indexers/fields, including file-scoped enum/union visibility, plus readonly field metadata
  - required/init shorthand and combined required-init property metadata

## Remaining Declaration Gaps

- none identified in the transpiler-backed declaration surface after the current audit

## Remaining Semantic Gaps

- none identified in the transpiler-backed execution surface after the current audit

## Residual Risk

- there may still be uncovered interoperability edge cases outside the currently exercised transpiler-backed surface, such as unusual ref-return CLR APIs or unsupported open-generic delegate signatures
