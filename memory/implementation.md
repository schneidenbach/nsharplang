# NewCLILang Implementation Notes

## Architecture Overview

```
.nl source file
    ↓
Lexer (Token stream)
    ↓
Parser (AST)
    ↓
Analyzer (Semantic analysis)
    ↓
Transpiler (C# code)
    ↓
C# Compiler (via dotnet)
    ↓
Executable
```

## Key Components

### 1. Lexer (`src/Compiler/Lexer.cs`)
- Converts source code to token stream
- Filters out newlines (for simpler parsing)
- Preserves comments in tokens but filters them during tokenization
- **String handling**: Token values include quotes (`"hello"` or `$"hello {x}"`)
- Supports all operators, keywords, and literals from DESIGN.md

### 2. Token (`src/Compiler/Token.cs`)
- Simple record with Type, Value, Line, Column, FileName
- 50+ token types defined in TokenType enum

### 3. AST (`src/Compiler/Ast/`)
- **Expressions.cs**: Binary, unary, member access, calls, lambdas, literals, etc.
- **Statements.cs**: If, for, foreach, while, return, try-catch, using, switch, etc.
- **Declarations.cs**: Functions, classes, structs, records, interfaces, unions, enums, etc.
- All nodes are immutable records with Line/Column for error reporting

### 4. Parser (`src/Compiler/Parser.cs`)
- Recursive descent parser with operator precedence climbing
- **Key insight**: Lambda expressions parsed at assignment-expression level (not primary)
  - This ensures `x := y => expr` parses correctly
- Filters newlines from token stream for cleaner parsing
- Supports all language features from DESIGN.md

### 5. Transpiler (`src/Compiler/Transpiler.cs`)
- Converts AST to C# code
- **Design decisions**:
  - Union types → abstract base class with nested records
  - Duck interfaces → not emitted (internal only)
  - String enums → class with const string fields
  - Convention-based visibility → explicit modifiers in C#
- Generates clean, indented output

### 6. Analyzer (`src/Compiler/Analyzer.cs`)
- Performs semantic analysis, type checking, and name resolution
- Implements scope management with nested scopes (global, class, function, block)
- Type inference for variables and expressions
- Definite assignment checking for non-nullable fields in constructors
- Convention-based visibility checking (PascalCase = public, camelCase = private)
- Reports errors with line/column information
- **External Type Resolution (NEW!)**:
  - Tracks using statements and namespace imports
  - Uses .NET reflection to resolve external types (System.Console, System.Linq, etc.)
  - Resolves members (properties, fields, methods) on external types
  - Handles method overloading via ReflectionMethodGroupInfo
  - Converts reflection types back to TypeInfo for analysis
- **Design**:
  - Uses `TypeInfo` hierarchy for type representation
  - Built-in types: int, long, float, double, bool, string, void, var (maps to unknown)
  - Supports class, struct, record, interface, union, enum types
  - Function return type resolution from declarations
  - ReflectionTypeInfo: Represents types loaded via reflection
  - ReflectionMethodInfo: Single method from reflection
  - ReflectionMethodGroupInfo: Overloaded methods from reflection
  - ExternalTypeInfo: Types that couldn't be fully resolved

### 7. CLI (`src/Cli/Program.cs`)
- Three commands: build, transpile, run
- Integrates Analyzer to check code before transpilation
- Reports errors/warnings with file:line:column format
- Stops compilation if errors are found
- For `run`: Creates temp project, compiles with dotnet, executes

## Important Implementation Details

### String Literals
- Lexer stores full string including quotes: `"hello"` or `$"hello {x}"`
- Transpiler uses value as-is (no quote wrapping needed)
- This simplifies interpolation handling

### Lambda Parsing
- Must be parsed BEFORE assignment expressions
- `ParseLambdaOrAssignmentExpression()` checks for:
  - Single param: `x => expr`
  - Multi param: `(x, y) => expr`
- Prevents ambiguity with identifiers

### For Loop Shorthand
- Parser detects `:=` in for-init and creates VariableDeclarationStatement
- Handles both `let i = 0` and `i := 0` forms

### Convention-based Visibility
- **Implemented in Analyzer** (warnings for non-conforming names)
- PascalCase = public, camelCase = private (by convention)
- Explicit modifiers (public, private, internal, protected) override convention
- Transpiler emits explicit modifiers in generated C#

## Testing Strategy

- **Unit tests**: Lexer (27 tests), Parser (41 tests), Analyzer (53 tests), Transpiler (30 tests)
- **Total**: 151 tests (151 passing, 0 skipped)
- **No mocks**: Tests use real components
- **End-to-end**: hello.nl and simple.nl examples prove full pipeline
- **Test files**: `tests/LexerTests.cs`, `tests/ParserTests.cs`, `tests/AnalyzerTests.cs`, `tests/TranspilerTests.cs`
- **Comprehensive coverage**: External types, method overloading, lambda inference, indexers, match/with expressions, default parameters, named arguments, async/await, iterators, using statements, switch statements, spread operator, class modifiers (partial/abstract/sealed/virtual), type aliases, attributes, extension methods, static classes, structs, readonly fields

## Build & Run

```bash
# Build compiler
dotnet build src/Compiler/Compiler.csproj

# Build CLI
dotnet build src/Cli/Cli.csproj

# Run tests
dotnet test tests/Tests.csproj

# Transpile example
dotnet run --project src/Cli/Cli.csproj transpile examples/hello.nl

# Run example
dotnet run --project src/Cli/Cli.csproj run examples/hello.nl
```

## Known Limitations

1. **Lambda type inference from context**: Lambda parameters with `var` work but type isn't inferred from LINQ method context
2. **Extension method resolution**: Extension methods not yet resolved (e.g., LINQ on arrays works via IEnumerable)
3. **Generic type inference**: Generic type parameters not fully inferred
4. **No multi-file compilation**: Only single-file programs work
5. **No project.yml support**: Dependency management not implemented
6. **Limited overload resolution**: Method overload resolution based only on argument count, not types

## Recent Changes

### v1.11 (Latest - Readonly Field Improvements)
1. **Readonly field assignment validation**: ✅ Analyzer now enforces readonly semantics
   - Added `_inConstructor` flag to track constructor context
   - `CheckReadonlyFieldAssignment` method validates assignment target
   - Error reported if readonly field assigned outside constructor
   - Enabled previously skipped test: `ReadonlyField_SetOutsideConstructor_Error`
2. **Readonly transpilation fix**: ✅ CRITICAL bug fixed - proper C# property syntax
   - Readonly fields now transpile to `{ get; init; }` instead of invalid `readonly` modifier on properties
   - Modifiers are filtered to exclude `Readonly` before transpiling
   - Init-only setters allow setting in constructors and object initializers
   - Updated transpiler test to expect new format
3. **Interface method transpilation**: ✅ Fixed to omit modifiers (implicitly public in C#)
   - Added `_inInterface` flag to track interface context
   - Interface methods transpile without modifiers (implicitly public)
   - Fixes C# compilation error for interface methods
4. **Class method visibility inference**: ✅ Methods now get visibility from naming convention
   - PascalCase methods = public (unless explicit modifier)
   - camelCase methods = private (unless explicit modifier)
   - Applies to all class/struct methods
5. **Comprehensive example**: ✅ Created `examples/records_and_interfaces.nl`
   - Demonstrates records with value equality
   - Shows with expressions for non-destructive mutation
   - Tests interface implementation with default methods
   - Includes structs and readonly fields
   - Proves end-to-end compilation and execution
6. **Test count**: ✅ 151 tests total, all passing (27 lexer + 41 parser + 53 analyzer + 30 transpiler)

### v1.10 (Missing Feature Test Coverage)
1. **Parser test additions**: ✅ Added 6 comprehensive parser tests for missing features
   - TestTypeAlias: Verifies type alias declarations (type X = Y)
   - TestAttributes: Verifies attribute syntax on classes, methods, and fields
   - TestExtensionMethod: Verifies 'this' parameter syntax for extension methods
   - TestStaticClass: Verifies static class declarations
   - TestReadonlyField: Verifies readonly modifier on fields
2. **Transpiler test additions**: ✅ Added 6 comprehensive transpiler tests
   - TestStructTranspilation: Verifies struct emission
   - TestTypeAliasTranspilation: Verifies type alias comment emission
   - TestAttributeTranspilation: Verifies attribute preservation in C#
   - TestExtensionMethodTranspilation: Verifies extension method static class wrapping
   - TestStaticClassTranspilation: Verifies static class emission
   - TestReadonlyFieldTranspilation: Verifies readonly modifier emission
3. **Analyzer test additions**: ✅ Added 2 analyzer tests for readonly fields
   - ReadonlyField_SetInConstructor_Valid: Verifies readonly can be set in constructor
   - ReadonlyField_SetOutsideConstructor_Error: SKIPPED - validation not yet implemented
   - ReadonlyField_WithInitializer_Valid: Verifies readonly with inline initializer
4. **Parser bug fixes**: ✅ Fixed 2 critical parsing bugs
   - Attribute parsing: Added missing Advance() before ParseArgumentList (line 124)
   - Array type detection: Changed to check for `[]` pattern to avoid confusion with attributes (line 706)
5. **Test count**: ✅ 151 tests total (27 lexer + 41 parser + 52 analyzer + 30 transpiler), 150 passing, 1 skipped
6. **Coverage improvement**: All features now have parser and transpiler test coverage
7. **Bug discovery**: Readonly field assignment validation needs analyzer implementation (future work)

### v1.9 (Advanced Feature Test Coverage)
1. **Parser test additions**: ✅ Added 8 comprehensive parser tests for advanced features
   - TestAsyncAwait: Verifies async modifier and await expressions
   - TestIteratorFunction: Verifies func* syntax and yield statements
   - TestUsingStatement: Verifies resource management with using blocks
   - TestSwitchStatement: Verifies case/default pattern syntax
   - TestSpreadOperator: Verifies spread syntax in array literals
   - TestPartialClass: Verifies partial modifier on classes
   - TestAbstractAndSealedClasses: Verifies abstract/sealed modifiers
   - TestVirtualMethods: Verifies virtual modifier and inheritance
2. **Transpiler test additions**: ✅ Added 9 comprehensive transpiler tests
   - TestAsyncAwaitTranspilation: Verifies async/await C# generation
   - TestIteratorFunctionTranspilation: Verifies yield return generation
   - TestUsingStatementTranspilation: Verifies using block generation
   - TestSwitchStatementTranspilation: Verifies switch case generation
   - TestSpreadOperatorTranspilation: Verifies spread handling
   - TestPartialClassTranspilation: Verifies partial modifier emission
   - TestAbstractClassTranspilation: Verifies abstract modifier emission
   - TestSealedClassTranspilation: Verifies sealed modifier emission
   - TestVirtualMethodTranspilation: Verifies virtual modifier preservation
3. **Test count**: ✅ 137 tests total (27 lexer + 35 parser + 51 analyzer + 24 transpiler)
4. **Coverage improvement**: All features specified in DESIGN.md now have test coverage
5. **No new features**: All tested features were already fully implemented in parser/transpiler

### v1.8 (Default Parameters and Named Arguments)
1. **Default parameter values**: ✅ Feature already implemented in parser and transpiler
   - Parsed in `ParseParameterList` (lines 265-270)
   - Stored in Parameter AST node with DefaultValue field
   - Transpiled to C# default parameter syntax
   - Syntax: `func Greet(name: string, greeting: string = "Hello")`
2. **Named arguments**: ✅ Feature already implemented in parser and transpiler
   - Parsed in `ParseArgumentList` (lines 1788-1798)
   - Stored in Argument AST node with Name field
   - Transpiled to C# named argument syntax
   - Syntax: `CreateUser(name: "John", age: 30)`
3. **Test coverage**: ✅ 120 tests total (27 lexer + 27 parser + 51 analyzer + 15 transpiler)
   - Added `TestDefaultParameterValues` parser test
   - Added `TestNamedArguments` parser test
   - Added `TestDefaultParameterTranspilation` transpiler test
   - Added `TestNamedArgumentTranspilation` transpiler test
4. **Functionality confirmed**: ✅ Both features work end-to-end
   - Tested with various combinations (positional, named, mixed, out-of-order)
   - Default values work correctly when arguments omitted
   - Named arguments work in any order

### v1.7 (With Expression Tests)
1. **Verified with expressions**: ✅ With expressions were already implemented and working
   - Parser support in `ParsePostfixExpression` (lines 1751-1769)
   - Transpiler support in `TranspileWithExpression`
   - Syntax: `p2 := p1 with { Age: 31 }`
2. **Test coverage**: ✅ 116 tests total (27 lexer + 25 parser + 51 analyzer + 13 transpiler)
   - Added `TestWithExpression` parser test
   - Added `TestWithExpressionTranspilation` transpiler test
3. **Functionality confirmed**: ✅ Record mutation works end-to-end
   - Created test example demonstrating with expressions
   - Successfully compiles and runs with proper C# `with` syntax

### v1.6 (Match Expression Fixes)
1. **Pattern parsing for qualified names**: ✅ CRITICAL bug fixed - patterns can now use qualified type names
   - Updated `ParsePattern` to handle dotted names like `Result.Success`
   - Added while loop to consume `.` and additional identifiers
   - Enables proper union case pattern matching
2. **Pattern transpilation improvements**: ✅ CRITICAL bug fixed - proper C# property pattern syntax
   - Updated `TranspileUnionCasePattern` to emit `{ prop: var prop }` syntax
   - When no explicit binding name, uses property name as binding
   - Generates valid C# switch expression patterns
3. **Test coverage**: ✅ 114 tests total (27 lexer + 24 parser + 51 analyzer + 12 transpiler)
   - Added `TestMatchExpression` parser test (literal patterns)
   - Added `TestMatchExpressionWithUnionPattern` parser test (union case patterns)
   - Added `TestMatchExpressionTranspilation` transpiler test
4. **Example update**: ✅ `examples/unions_and_match.nl` now uses real match expressions
   - Replaced if-else chains with proper match expressions
   - Demonstrates exhaustive pattern matching on union types
   - Successfully compiles and runs

### v1.5 (Parser and Transpiler Improvements)
1. **Qualified type names**: ✅ Support for dotted type names like `Result.Success`
   - Updated `ParseBaseTypeReference` to handle `Type.Name` syntax
   - Allows union case types to be referenced properly
2. **Cast expression fixes**: ✅ CRITICAL bug fixed - qualified type casts now work
   - Updated `IsCastExpression()` to handle qualified names
   - Reordered parser checks: cast detection before tuple/parenthesized expressions
   - New test: `TestQualifiedTypeCast` validates parsing
3. **Type alias resolution**: ✅ Type aliases now work in type checking
   - Added `ResolveTypeAlias()` helper method
   - Updated `IsAssignable()` to resolve aliases before comparison
   - `type UserId = int` now properly type-checks
4. **String enum transpilation**: ✅ CRITICAL bug fixed - proper C# emission
   - String enums now transpile to `static class` with `const string` fields
   - Int enums continue to transpile to standard C# enums
   - Prevents invalid `enum { const string ... }` syntax
5. **Top-level function wrapping**: ✅ Major transpiler improvement
   - Top-level functions now wrapped in internal static class
   - Class name: `_{Namespace}_TopLevel` or `_TopLevel`
   - Fixes C# compilation error (top-level statements after declarations)
   - Matches DESIGN.md: "internal static methods on auto-generated class"
6. **Test coverage**: ✅ 111 tests total (27 lexer + 22 parser + 51 analyzer + 11 transpiler)
   - Added `TestQualifiedTypeCast` parser test
7. **New example**: ✅ `examples/unions_and_match.nl`
   - Demonstrates discriminated unions
   - Shows int and string enums
   - Tests type aliases
   - Proves end-to-end compilation

### v1.4 (Error Handling)
1. **Automatic exception capture**: ✅ MAJOR feature - error handling with tuple deconstruction
   - Pattern: `result, err := Function()` automatically wraps call in try-catch
   - Generates: `object? result = null; Exception? err = null; try { result = ... } catch (Exception ex) { err = ex; }`
   - Parser enhanced to recognize `x, y := expr` syntax (without parens)
   - Transpiler detects pattern when second variable is exactly `err`
   - Analyzer declares `err` as `Exception?` type, result gets inferred type
2. **Improved null-coalesce operator**: ✅ Better type inference for `??` with throw expressions
   - Added `AnalyzeNullCoalesceOp` method in Analyzer
   - When right side is throw expression, returns left type (e.g., `string? ?? throw => string`)
   - Otherwise returns right type for proper fallback typing
3. **Test coverage**: ✅ 110 tests total (27 lexer + 21 parser + 51 analyzer + 11 transpiler)
   - New test: TestErrorHandlingTranspilation
   - New test: TestThrowExpressionTranspilation

### v1.3
1. **Constructor transpilation fix**: ✅ CRITICAL bug fixed - now emits class name instead of "ctor"
   - Added _currentTypeName tracking in Transpiler
   - Properly generates `ClassName(params)` syntax
2. **Property get/set accessors**: ✅ Full custom property support
   - New PropertyDeclaration AST node
   - Parser distinguishes between auto-properties (fields) and custom properties
   - Transpiler generates proper C# property syntax with get/set blocks
   - Analyzer validates property bodies and adds implicit 'value' parameter to setters
3. **Tuple deconstruction**: ✅ Variable declarations with tuple patterns
   - New TupleDeconstructionStatement AST node
   - Supports `(x, y) := expr` and `let (x, y) = expr` syntax
   - Supports discard pattern `_` for unused values
   - Parser uses lookahead to distinguish from tuple expressions
   - Transpiles to C# tuple deconstruction `(x, y) = expr;`
4. **Test coverage**: ✅ 108 tests total (27 lexer + 21 parser + 51 analyzer + 9 transpiler)

### v1.2
1. **Indexer transpilation**: ✅ CRITICAL missing feature now implemented
   - Parser fixed to detect indexers before regular functions
   - Transpiler generates correct C# `this[...]` syntax with get/set blocks
2. **Immutable arrays**: ✅ Full support for `immutable [...]` syntax
   - Parser recognizes immutable keyword before array literals
   - Transpiles to C# 12+ collection expression syntax `[...]`
   - Mutable arrays continue using `new[] { ... }`
3. **Transpiler tests**: ✅ Added comprehensive test suite with 6 tests
4. **Test coverage**: ✅ 105 tests total (27 lexer + 21 parser + 51 analyzer + 6 transpiler)

### v1.1
1. **External type resolution**: ✅ Analyzer now resolves types from using statements via reflection
2. **Member resolution**: ✅ Properties, fields, and methods on external types are resolved
3. **Method overloading**: ✅ Handles overloaded methods (basic resolution by arg count)
4. **Lambda parameters**: ✅ Lambda parameters without explicit types use `var` → `Unknown` → compatible with arithmetic

## Next Implementation Priority

1. **Better lambda type inference**: Infer lambda parameter types from LINQ method signatures
2. **Extension method resolution**: Properly resolve extension methods like Select, Where
3. **Generic type inference**: Infer type parameters from usage context
4. **Multi-file compilation**: Extend CLI to compile multiple files
5. **Project system**: Parse project.yml and manage dependencies
6. **Better error messages**: Include source code context in error output
