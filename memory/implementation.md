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

- **Unit tests**: Lexer (29 tests), Parser (61 tests), Analyzer (67 tests), Transpiler (48 tests)
- **Total**: 215 tests (215 passing, 0 skipped)
- **No mocks**: Tests use real components
- **End-to-end**: hello.nl and simple.nl examples prove full pipeline
- **Test files**: `tests/LexerTests.cs`, `tests/ParserTests.cs`, `tests/AnalyzerTests.cs`, `tests/TranspilerTests.cs`
- **Comprehensive coverage**: External types, method overloading, lambda inference, indexers, match/with expressions, default parameters, named arguments, async/await, iterators, using statements, switch statements, spread operator, class modifiers (partial/abstract/sealed/virtual), type aliases, attributes, extension methods, static classes, structs, readonly fields, safe cast (as), is pattern, null-coalescing assignment (??=), this/base keywords, multiple interface implementation, generic constraints, multi-line template strings, duck interfaces with structural typing, properties with custom get/set, nested types, null-conditional indexing (?[]), **pattern matching guards (when clauses) (NEW!)**

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

### v1.21 (Import System - Phase 1: Syntax and Parsing) 🚧 IN PROGRESS
1. **Import keyword**: ✅ Added `Import` token type
   - Added to Token.cs (line 23) and Lexer keywords dictionary
   - Lexer recognizes "import" keyword
2. **Import AST nodes**: ✅ Created FileImport and NamespaceImport statements
   - FileImport for file-based imports: `import "path/to/file" [as Alias]`
   - NamespaceImport for .NET namespace imports: `import System.Linq [as Alias]`
   - Both support optional aliasing with `as` keyword
3. **Parser support**: ✅ Implemented ParseImport() method
   - Detects file imports (string literal) vs namespace imports (qualified name)
   - Handles optional `as Alias` syntax for both types
   - Imports parsed after using directives, before declarations
4. **CompilationUnit updated**: ✅ Added Imports list
   - CompilationUnit now contains: Namespace, Usings, **Imports**, Declarations
   - Imports stored as List<Statement> (can be FileImport or NamespaceImport)
5. **Test coverage**: ✅ 6 new tests (1 lexer + 5 parser) = 249 total
   - `TestImportKeyword` (Lexer): Verifies import keyword recognition
   - `TestFileImport` (Parser): Simple file import
   - `TestFileImportWithAlias` (Parser): File import with alias
   - `TestNamespaceImport` (Parser): Namespace import
   - `TestNamespaceImportWithAlias` (Parser): Namespace import with alias
   - `TestMultipleImports` (Parser): Multiple mixed imports
6. **Status**: ✅ Syntax and parsing complete, all tests passing
7. **Next steps** (Phase 2):
   - Create FileResolver class for path resolution
   - Implement symbol import logic in Analyzer
   - Add collision detection for imported symbols
   - Implement circular import detection
   - Update Transpiler to emit C# using statements for namespace imports
   - Write integration tests with actual multi-file scenarios

### v1.20 (Advanced Pattern Matching) ✅
1. **Relational Patterns**: ✅ Pattern matching with comparison operators
   - Added `RelationalPattern` AST node (Expressions.cs:186-190)
   - Syntax: `< 13, >= 65, == value, != value` in match expressions
   - Parser support with precedence handling (Parser.cs:1330-1348)
   - Analyzer validates relational pattern expressions (Analyzer.cs:818-823)
   - Transpiler emits C# 9+ relational patterns (Transpiler.cs:1288-1292)
2. **Logical Patterns**: ✅ Combining patterns with and/or/not
   - Added `AndPattern`, `OrPattern`, `NotPattern` AST nodes (Expressions.cs:193-209)
   - Added keywords: `and`, `or`, `not` for pattern matching (Token.cs:58-60, Lexer.cs:62-64)
   - Parser with correct precedence: or > and > not (Parser.cs:1284-1328)
   - Analyzer validates both/all sub-patterns (Analyzer.cs:825-840)
   - Transpiler emits C# and/or/not patterns (Transpiler.cs:1294-1310)
3. **Positional Patterns**: ✅ Tuple deconstruction in match patterns
   - Added `PositionalPattern` AST node (Expressions.cs:211-214)
   - Syntax: `(pattern1, pattern2, ...)` for tuple matching
   - Parser support (Parser.cs:1354-1368)
   - Analyzer validates each sub-pattern (Analyzer.cs:842-849)
   - Transpiler emits C# positional patterns (Transpiler.cs:1312-1317)
4. **Critical syntax fix**: ✅ Match expressions now require commas between cases
   - **Problem**: Without delimiters, parser couldn't distinguish between case expression ending and next pattern starting
   - **Example issue**: `< 13 => "child" >= 65` was ambiguous - is `>= 65` part of expression or new pattern?
   - **Solution**: Require commas between cases, matching C# switch expression syntax (Parser.cs:2154-2155)
   - **Syntax**: `match x { pattern1 => expr1, pattern2 => expr2, _ => default }`
   - Updated all 26 test methods across ParserTests, TranspilerTests, and AnalyzerTests
5. **Test coverage**: ✅ 12 new tests added (6 parser + 6 transpiler) = 243 total, all passing
   - `TestRelationalPattern`, `TestAndPattern`, `TestOrPattern` (Parser)
   - `TestNotPattern`, `TestPositionalPattern`, `TestComplexCombinedPatterns` (Parser)
   - Corresponding transpilation tests for all patterns
   - All existing match expression tests updated to use comma syntax

### v1.19 (Expression-Bodied Members)
1. **Expression-bodied properties**: ✅ Concise syntax for computed properties
   - Added `ExpressionBody` field to `PropertyDeclaration` (Declarations.cs:155)
   - Syntax: `PropName: type => expression`
   - Type must be explicitly declared (C# compatible - no type inference for members)
   - Parser detects `=>` after type annotation (Parser.cs:684-690)
   - Analyzer validates expression type matches property type (Analyzer.cs:296-304)
   - Transpiler emits C# expression-bodied property syntax (Transpiler.cs:551-556)
2. **Expression-bodied methods**: ✅ Concise syntax for single-expression methods
   - Added `ExpressionBody` field to `FunctionDeclaration` (Declarations.cs:36)
   - Syntax: `func MethodName(...) => expression`
   - Parser detects `=>` after parameters/constraints (Parser.cs:222-226)
   - Analyzer validates expression type matches return type (Analyzer.cs:143-151)
   - Transpiler emits C# expression-bodied method syntax (Transpiler.cs:194-198)
3. **Test coverage**: ✅ 8 new tests (4 parser + 4 transpiler)
   - `TestExpressionBodiedProperty`, `TestExpressionBodiedPropertyWithExplicitType` (Parser)
   - `TestExpressionBodiedMethod`, `TestExpressionBodiedMethodWithComplexExpression` (Parser)
   - `TestExpressionBodiedPropertyTranspilation`, `TestExpressionBodiedPropertyWithTypeTranspilation` (Transpiler)
   - `TestExpressionBodiedMethodTranspilation`, `TestExpressionBodiedMethodComplexTranspilation` (Transpiler)
4. **Example**: ✅ `examples/expression_bodied_members.nl`
   - Demonstrates Person class with computed FullName and Age properties
   - Calculator with expression-bodied Add/Multiply methods
   - Rectangle with Area, Perimeter, and IsSquare computed properties
   - Successfully compiles and runs
5. **Test count**: ✅ 231 tests total, all passing (31 lexer + 68 parser + 67 analyzer + 55 transpiler)

### v1.18 (Print, Nameof, Typeof)
1. **Print statement**: ✅ Built-in print function for console output
   - Added `Print` keyword token (Token.cs:55)
   - Added `PrintStatement` AST node (Statements.cs:135-139)
   - Syntax: `print "Hello"` or `print $"Value: {x}"`
   - No parentheses required
   - Transpiles to `Console.WriteLine()`
   - Parser support (Parser.cs:1086-1094)
   - Analyzer validates expression (Analyzer.cs:449-451)
   - Transpiler emits Console.WriteLine (Transpiler.cs:699-701)
2. **Nameof operator**: ✅ Get identifier name as string
   - Added `Nameof` keyword token (Token.cs:53)
   - Added `NameofExpression` AST node (Expressions.cs:216-220)
   - Syntax: `nameof(variable)` or `nameof(obj.Property)`
   - Returns string name of identifier
   - Parser support (Parser.cs:1904-1911)
   - Analyzer returns string type (Analyzer.cs:1277-1283)
   - Transpiler extracts final identifier name (Transpiler.cs:1175-1192)
3. **Typeof operator**: ✅ Get Type object for reflection
   - `Typeof` keyword already existed (Token.cs:52)
   - `TypeOfExpression` already in AST (Expressions.cs:210-214)
   - Enhanced analyzer support (Analyzer.cs:1269-1275)
   - Returns System.Type via ReflectionTypeInfo
   - Works with primitives, classes, generic types
   - Transpiles to C# `typeof()`
4. **Test coverage**: ✅ 8 new tests (2 lexer + 3 parser + 3 transpiler)
   - `TestPrintKeyword`, `TestNameofKeyword` (Lexer)
   - `TestPrintStatement`, `TestNameofExpression`, `TestTypeofExpression` (Parser)
   - `TestPrintStatementTranspilation`, `TestNameofTranspilation`, `TestTypeofTranspilation` (Transpiler)
5. **Example**: ✅ `examples/print_nameof_typeof.nl`
   - Demonstrates print statements without parentheses
   - Shows nameof usage for identifier names
   - Shows typeof for type reflection
   - Successfully compiles and runs
6. **Test count**: ✅ 223 tests total, all passing (31 lexer + 64 parser + 67 analyzer + 51 transpiler)

### v1.17 (Pattern Matching Guards)
1. **Lexer enhancement**: ✅ Added When keyword token
   - Added `When` token type to recognize `when` keyword (Token.cs:55)
   - Lexer now tokenizes `when` for guard clauses in match expressions
2. **AST enhancement**: ✅ Added Guard field to MatchCase
   - Updated `MatchCase` record to include optional `Expression? Guard` field
   - Allows patterns to have additional boolean conditions
   - Syntax: `pattern when condition => expression`
3. **Parser enhancement**: ✅ Support for guard clauses
   - Updated `ParseMatchExpression` to parse guard after pattern (Parser.cs:2014-2019)
   - Guard expression parsed as normal expression between pattern and arrow
   - Checks for `when` keyword after pattern, before `=>`
4. **Analyzer enhancement**: ✅ Guard expression validation
   - Guards must be boolean type (type checked in Analyzer.cs:1279-1288)
   - Guard expressions have access to pattern-bound variables
   - Exhaustiveness checking conservatively skipped when guards present
   - Reports error if guard expression is not boolean
5. **Transpiler enhancement**: ✅ C# when clause generation
   - Guard expressions transpile to C# `when` clauses in switch expressions
   - Updated `TranspileMatchExpression` to include guard in output (Transpiler.cs:1171-1184)
   - Fixed `IdentifierPattern` transpilation to emit `var` prefix for variable capture
   - Qualified names (e.g., Result.Success) don't get `var` prefix (Transpiler.cs:1215-1227)
6. **Comprehensive test coverage**: ✅ 9 new tests (1 lexer + 2 parser + 4 analyzer + 2 transpiler)
   - `TestWhenKeyword` (Lexer): Verifies `when` keyword recognition
   - `TestMatchExpressionWithGuard` (Parser): Guards with identifier patterns
   - `TestMatchExpressionWithUnionPatternAndGuard` (Parser): Guards with union patterns
   - `MatchExpression_WithGuard_Valid` (Analyzer): Integer matching with guards
   - `MatchExpression_GuardNotBool_Error` (Analyzer): Non-boolean guards rejected
   - `MatchExpression_GuardWithPatternVariable_Valid` (Analyzer): Pattern variables in guards
   - `MatchExpression_WithGuard_SkipsExhaustivenessCheck` (Analyzer): Conservative checking
   - `TestMatchExpressionWithGuardTranspilation`: C# when clause output
   - `TestMatchExpressionWithUnionPatternAndGuardTranspilation`: Union + guard output
7. **End-to-end example**: ✅ `examples/guards_simple.nl`
   - Number classification with range-based guards
   - FizzBuzz implementation using match with guards
   - Grade calculator demonstrating guard patterns
   - Successfully compiles and runs
8. **Test count**: ✅ 215 tests total, all passing (29 lexer + 61 parser + 67 analyzer + 48 transpiler)

### v1.16 (Null-Conditional Indexing Operator)
1. **Lexer enhancement**: ✅ Added QuestionBracket token type
   - Added `QuestionBracket` token type to recognize `?[` (Token.cs:100)
   - Lexer tokenizes `?[` as distinct operator (Lexer.cs:341-345)
   - Follows same pattern as `QuestionDot` (`?.`) for consistency
2. **Parser enhancement**: ✅ Support for null-conditional indexing
   - Updated `ParsePostfixExpression` to handle both `[` and `?[` (Parser.cs:1756)
   - Sets `IsNullConditional` flag to true when `?[` is detected
   - AST already had `IsNullConditional` field on `IndexAccessExpression` (forward-thinking!)
3. **Transpiler enhancement**: ✅ C# code generation for ?[]
   - Refactored inline indexing to `TranspileIndexAccess` method (Transpiler.cs:1044-1050)
   - Emits `?[` or `[` based on `IsNullConditional` flag
   - Mirrors `TranspileMemberAccess` pattern for consistency
4. **Comprehensive test coverage**: ✅ 3 new tests (1 lexer + 1 parser + 1 transpiler)
   - `TestNullConditionalIndexing` (Lexer): Verifies `?[` token recognition
   - `TestNullConditionalIndexing` (Parser): Verifies AST with `IsNullConditional=true`
   - `TestNullConditionalIndexingTranspilation`: Verifies C# output contains `?[`
5. **Test count**: ✅ 206 tests total, all passing (28 lexer + 59 parser + 63 analyzer + 46 transpiler)

### v1.15 (Properties and Nested Types)
1. **Property get/set return type tracking**: ✅ Fixed analyzer to properly handle return statements in properties
   - Property getters set `_currentReturnType` to property type
   - Property setters set `_currentReturnType` to void
   - Return statements now work correctly inside property accessors
   - Fixes "Return statement outside of function" error
2. **Nested type support in parser**: ✅ MAJOR feature - classes can now contain other types
   - Added checks for type keywords (class, struct, record, enum, union, interface) in ParseMemberDeclaration
   - Nested types are parsed just like top-level types
   - Enables proper encapsulation and organization of types
3. **Nested type transpilation fixes**: ✅ Critical bug fixes for C# generation
   - Fixed `_currentTypeName` tracking to save/restore when entering/exiting nested types
   - Nested constructors now emit correct class name instead of "UnknownType"
   - Nested types with PascalCase automatically get public visibility (C# requirement)
   - Fixed visibility inference for nested enums, classes, structs, records
4. **Increment/decrement transpilation**: ✅ Fixed extra parentheses bug
   - Pre/post increment/decrement no longer wrapped in parentheses
   - `x++` transpiles as `x++` not `(x++)`
   - Fixes invalid C# code `(x++);` when used as statement
5. **Error handling with void functions**: ✅ Fixed transpilation for discarded results
   - `_, err := VoidFunc()` now just calls function: `VoidFunc();`
   - Previously tried invalid assignment: `_ = VoidFunc();` (can't assign void to object)
   - Result variable declaration skipped when using discard pattern `_`
6. **Comprehensive test coverage**: ✅ 10 new tests (5 parser + 5 transpiler)
   - TestPropertyWithGetSet, TestPropertyWithGetOnly, TestPropertyWithSetOnly
   - TestPropertyGetOnlyTranspilation, TestPropertySetOnlyTranspilation
   - TestNestedClass, TestNestedEnum (parser)
   - TestNestedClassTranspilation, TestNestedEnumTranspilation, TestNestedRecordTranspilation
7. **End-to-end example**: ✅ `examples/properties_and_nested_types.nl`
   - BankAccount class with custom properties (Balance with validation)
   - Nested enum (Status: Active, Frozen, Closed)
   - Nested class (Transaction)
   - Error handling with void function (Deposit/Withdraw)
   - Successfully compiles and runs
8. **Test count**: ✅ 203 tests total, all passing (27 lexer + 58 parser + 63 analyzer + 45 transpiler)

### v1.14 (Match Expression Exhaustiveness Checking)
1. **Match expression analysis fully implemented**: ✅ MAJOR feature - compiler-enforced exhaustive pattern matching
   - Added `AnalyzeMatchExpression` method to analyze match expressions
   - Creates scopes for each match case to properly bind pattern variables
   - Type checks all case expressions for compatibility
   - Checks exhaustiveness AFTER pattern analysis to report specific errors first
2. **Pattern analysis enhanced**: ✅ Handles all pattern types correctly
   - IdentifierPattern: Binds variables OR validates qualified union cases without properties
   - LiteralPattern: Type checks literals
   - UnionCasePattern: Validates union cases exist and binds property patterns to variables
   - Extracts case names from qualified patterns (Result.Success → Success)
3. **Exhaustiveness checking**: ✅ Compiler enforces all union cases are covered
   - `CheckMatchExhaustiveness` validates all union cases are matched
   - Reports helpful error messages listing missing cases
   - Supports wildcard pattern (_) as catch-all
   - Handles both UnionCasePattern and qualified IdentifierPattern
4. **Union case type resolution fixed**: ✅ CRITICAL bug fix for pattern matching
   - `new Result.Success { ... }` now correctly infers type as `Result` (the union type)
   - Previously incorrectly inferred as `Result.Success` (the case), breaking pattern matching
   - Added special handling in `AnalyzeNewExpression` to detect union case instantiation
5. **Comprehensive test coverage**: ✅ 10 new analyzer tests for match expressions
   - Tests cover: exhaustive matching, missing cases, wildcard patterns, invalid cases/properties
   - Tests validate: pattern binding, type compatibility, error reporting
   - All scenarios properly tested and validated
6. **End-to-end example**: ✅ `examples/match_exhaustiveness.nl`
   - Demonstrates exhaustive matching on HttpResponse union (4 cases)
   - Shows wildcard pattern usage for partial matching
   - Proves property destructuring in patterns works correctly
   - Successfully transpiles to C# switch expressions
7. **Test count**: ✅ 193 tests total, all passing (27 lexer + 53 parser + 63 analyzer + 40 transpiler)

### v1.13 (Duck Interface Structural Typing)
1. **Duck interface structural typing fully implemented**: ✅ MAJOR feature - Go-style duck typing for .NET
   - Added `ImplementsDuckInterface` method in Analyzer to check structural compatibility
   - Added `MethodSignaturesMatch` helper to compare method signatures
   - Updated `IsAssignable` to check duck interface compatibility
   - Duck interfaces validate at compile-time with proper error messages
2. **Function parameter type checking**: ✅ Enhanced type safety for all function calls
   - Updated `AnalyzeCall` to validate argument types against parameter types
   - Reports errors when types don't match (critical for duck interface validation)
   - Checks argument count and types
3. **Transpiler automatic interface implementation**: ✅ CRITICAL for C# compilation
   - Duck interfaces now transpile as `internal interface` (instead of being skipped)
   - Classes/structs/records automatically implement duck interfaces they structurally match
   - Added `ClassImplementsDuckInterface` and `MethodSignaturesMatch` in Transpiler
   - Updated class, struct, and record transpilation to add duck interface implementations
   - Ensures generated C# compiles correctly with explicit interface declarations
4. **Comprehensive test coverage**: ✅ 10 new analyzer tests for duck interfaces
   - Tests cover: class/struct/record implementation, missing methods, wrong return types, wrong parameter types/counts
   - Tests validate variable assignment and return values with duck interfaces
   - All error cases properly tested and validated
5. **End-to-end example**: ✅ `examples/duck_interfaces.nl`
   - Demonstrates IReader, IWriter, IReadWriter duck interfaces
   - Shows FileReader, MemoryStore, NetworkStream implementing without explicit declaration
   - Proves duck typing works in all contexts (function calls, variables, return values)
   - Successfully compiles and runs
6. **Test count**: ✅ 183 tests total, all passing (27 lexer + 53 parser + 63 analyzer + 40 transpiler)

### v1.12 (Comprehensive Test Coverage)
1. **Added 22 new tests for improved coverage**: ✅ Comprehensive testing of existing features
   - Added 12 new parser tests for indexer usage, safe cast, is pattern, ??=, this/base, multiple interfaces, constraints, overloading, multi-line strings
   - Added 10 new transpiler tests for matching features
   - All features were already implemented and working - tests document and verify behavior
   - Total test count increased from 151 to 173 (27 lexer + 53 parser + 53 analyzer + 40 transpiler)
2. **Parser tests added**:
   - TestIndexerUsage: Array and dictionary indexer access (`arr[0]`, `dict["key"]`)
   - TestIndexAccessWithConditional: Basic indexer usage verification
   - TestSafeCastOperator: Safe cast operator `as` for type conversion
   - TestIsPattern: Type checking with `is` operator and pattern matching
   - TestNullCoalescingAssignment: `??=` operator for conditional assignment
   - TestThisKeyword: `this.field` member access and `return this`
   - TestBaseKeyword: `base.Method()` calls to parent class
   - TestConstructorDeclaration: Constructor parameter parsing
   - TestMultipleInterfaceImplementation: Class with base class + multiple interfaces
   - TestGenericConstraints: `where T : IComparable` constraint syntax
   - TestMethodOverloading: Multiple methods with same name, different signatures
   - TestMultiLineTemplateString: Triple-quoted string literals
3. **Transpiler tests added**:
   - TestIndexerUsageTranspilation: Verify C# indexer output
   - TestSafeCastTranspilation: Verify `as` operator in C#
   - TestIsPatternTranspilation: Verify `is` pattern in C#
   - TestNullCoalescingAssignmentTranspilation: Verify `??=` in C#
   - TestThisKeywordTranspilation: Verify `this` keyword in C#
   - TestBaseKeywordTranspilation: Verify `base` keyword in C#
   - TestMultipleInterfaceImplementationTranspilation: Verify inheritance list
   - TestGenericConstraintsTranspilation: Verify `where` clause
   - TestMethodOverloadingTranspilation: Verify multiple methods
   - TestMultiLineTemplateStringTranspilation: Verify multi-line string output
4. **Build status**: ✅ All 173 tests passing, build successful with no warnings

### v1.11 (Readonly Field Improvements)
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
