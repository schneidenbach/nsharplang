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

- **Unit tests**: Lexer (32 tests), Parser (85 tests), Analyzer (78 tests), Transpiler (70 tests)
- **Total**: 300 tests (300 passing, 0 skipped)
- **No mocks**: Tests use real components
- **End-to-end**: hello.nl and simple.nl examples prove full pipeline
- **Test files**: `tests/LexerTests.cs`, `tests/ParserTests.cs`, `tests/AnalyzerTests.cs`, `tests/TranspilerTests.cs`
- **Comprehensive coverage**: External types, method overloading, lambda inference, indexers, match/with expressions, default parameters, named arguments, async/await, iterators, using statements, switch statements, spread operator, class modifiers (partial/abstract/sealed/virtual), type aliases, attributes, extension methods, static classes, structs, readonly fields, safe cast (as), is pattern, null-coalescing assignment (??=), this/base keywords, multiple interface implementation, generic constraints, multi-line template strings, duck interfaces with structural typing, properties with custom get/set, nested types, null-conditional indexing (?[]), pattern matching guards (when clauses), **nested property patterns (NEW!)**

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

### v1.35 (Constructor Chaining) ✅ COMPLETE - LATEST!
1. **AST enhancement**: ✅ Added Initializer field to ConstructorDeclaration
   - Added `Expression? Initializer` field to ConstructorDeclaration record
   - Stores `this()` or `base()` call expression for constructor chaining
2. **Parser support**: ✅ Parse `: this()` and `: base()` syntax
   - After parsing constructor parameters, checks for optional `:` token
   - Parses `this(args)` or `base(args)` as CallExpression with ThisExpression/BaseExpression
   - Creates CallExpression with appropriate callee and arguments
   - ParseArgumentList() consumes the closing paren
3. **Transpiler support**: ✅ Emit C# constructor initializer syntax
   - TranspileConstructorDeclaration checks for Initializer and emits `: this(args)` or `: base(args)`
   - TranspileConstructorInitializer helper method formats initializer with arguments
   - Supports ref/out modifiers and named arguments in initializers
   - Generates idiomatic C# constructor chaining syntax
4. **Analyzer support**: ✅ Constructor initializer validation and definite assignment
   - AnalyzeConstructorDeclaration analyzes initializer expression if present
   - Skips definite assignment check when initializer exists (initializer handles assignments)
   - Constructors with `this()` or `base()` initializers don't need to assign fields directly
5. **Test coverage**: ✅ 5 new tests (3 parser + 2 transpiler) = 331 total
   - Parser: TestConstructorWithThisInitializer, TestConstructorWithBaseInitializer, TestConstructorWithMultipleArguments
   - Transpiler: TestConstructorThisInitializerTranspilation, TestConstructorBaseInitializerTranspilation
6. **Example**: ✅ examples/constructor_chaining.nl
   - Demonstrates this() chaining with default parameters (Person class)
   - Shows base() constructor calls (Employee class inheriting Person)
   - Illustrates dependency injection pattern with simplified constructors
   - Multiple levels of chaining in single class
   - Successfully transpiles to correct C# code
7. **Build status**: ✅ All 331 tests passing

**Impact:** Essential for DI patterns and reducing constructor duplication! Enables idiomatic .NET constructor design.

**What works:**
- Constructor chaining with `this(args)` ✅
- Base constructor calls with `base(args)` ✅
- Multiple arguments with ref/out/named parameters ✅
- Definite assignment analysis skipped when initializer present ✅
- Clean C# code generation matching C# syntax exactly ✅

**Use cases:**
- Dependency injection with simplified constructors
- Default parameter values via constructor chaining
- Inheritance with base class initialization
- Reducing code duplication across multiple constructors

### v1.34 (Ref/Out Parameters) ✅ COMPLETE
1. **New keywords**: ✅ Added `ref` and `out` keywords
   - Added `Ref` and `Out` token types to Token.cs
   - Added keyword mappings to Lexer.cs
2. **AST enhancements**: ✅ ParameterModifier and ArgumentModifier enums
   - Created `ParameterModifier` enum (None, Ref, Out) in Declarations.cs
   - Created `ArgumentModifier` enum (None, Ref, Out) in Expressions.cs
   - Updated Parameter record to include Modifier field
   - Updated Argument record to include Modifier field
3. **Parser support**: ✅ ParseParameterList and ParseArgumentList handle ref/out
   - Parser checks for ref/out keywords before parameter name
   - Parser checks for ref/out keywords before argument value
   - Both modifiers correctly parsed and stored in AST
4. **Transpiler support**: ✅ Correct C# code generation
   - TranspileParameter emits `ref`/`out` modifiers before type
   - TranspileCallExpression and TranspileNewExpression emit modifiers before arguments
   - Generates idiomatic C# ref/out syntax
5. **Test coverage**: ✅ 10 new tests (2 lexer + 4 parser + 4 transpiler) = 326 total
   - Lexer: TestRefKeyword, TestOutKeyword
   - Parser: TestRefParameter, TestOutParameter, TestRefArgument, TestOutArgument
   - Transpiler: TestRefParameterTranspilation, TestOutParameterTranspilation, TestRefArgumentTranspilation, TestOutArgumentTranspilation
6. **Example**: ✅ examples/ref_out_parameters.nl
   - Demonstrates custom Swap function with ref parameters
   - Shows TryParse pattern with out parameters (common .NET idiom)
   - Demonstrates Dictionary TryGetValue pattern
   - Proves in-place modification with ref
   - Shows combining ref and out parameters in same function
   - Successfully compiles and runs
7. **Documentation**: ✅ Updated DESIGN.md
   - Added ref/out parameter section under Function Definitions
   - Removed from "Deferred Features" (now implemented!)
   - Explained ref vs out semantics
   - Provided practical examples with .NET interop
8. **Build status**: ✅ All 326 tests passing

**Impact:** Critical .NET interop feature! Enables using essential .NET APIs like `int.TryParse`, `Dictionary.TryGetValue`, etc.

**What works:**
- ref parameters for pass-by-reference (read and modify) ✅
- out parameters for output-only values ✅
- Combining ref and out in same function ✅
- Full transpilation to C# ref/out syntax ✅
- Idiomatic .NET patterns (TryParse, TryGetValue) ✅

**Known limitations:**
- Analyzer doesn't yet validate ref/out semantics (future enhancement)
- No definite assignment checking for out parameters (future enhancement)

### v1.26 (Comprehensive Multi-File Demo) ✅ COMPLETE
1. **Weather Demo Example**: ✅ Created examples/WeatherDemo/
   - Full multi-file project demonstrating real-world N# application
   - Models/WeatherForecast.nl: Record with expression-bodied property
   - Services/WeatherService.nl: Business logic with LINQ, pattern matching, guards
   - Program.nl: Main entry point with comprehensive feature showcase
   - Successfully compiles and runs with 3 files
2. **Language Features Demonstrated**: ✅ 10+ features in action
   - Records with expression-bodied properties (TemperatureF computed from TemperatureC)
   - Pattern matching with guards for temperature classification
   - LINQ operations (Range, Select, Where, ToArray, Min, Max, Average)
   - Named tuples for GetStatistics return value
   - Immutable arrays for summaries
   - Default parameter values (GetForecasts(days: int = 5))
   - Multi-file imports with namespace organization
   - String interpolation with format specifiers ($"{date:yyyy-MM-dd}")
   - Null-safe operators (??)
   - For-each loops
3. **Project Configuration**: ✅ project.yml with settings
   - targetFramework: net9.0
   - asyncDefaultType: ValueTask
   - Proper project name and version
4. **Documentation**: ✅ Comprehensive README.md
   - Usage instructions (nlc build, nlc run)
   - Feature list with checkmarks
   - Code highlights with syntax examples
   - Sample output
   - "Why This Example Matters" section
   - Next steps for enhancement
5. **End-to-End Testing**: ✅ Verified working
   - Compiles successfully via `nlc build`
   - Runs successfully via `nlc run`
   - Generates correct C# output
   - Produces expected console output
6. **Test Status**: ✅ All 270 tests still passing

**What works:**
- Complete multi-file project compilation ✅
- Cross-namespace type references ✅
- Complex LINQ expressions ✅
- Pattern matching with guards ✅
- Expression-bodied members ✅

**Impact:**
- This is the KILLER DEMO for N# - proves the language is production-ready
- Shows multi-file compilation works in real scenarios
- Demonstrates that N# can build actual applications, not just toy examples
- Template for future N# projects

**Next steps:**
- Task 014: ASP.NET Core example project
- Additional language features as needed

### v1.33 (Required and Init-Only Properties) ✅ COMPLETE - LATEST!
1. **New keywords**: ✅ Added `required` and `init` keywords
   - Added `Required` and `Init` token types to Token.cs
   - Added keyword mappings to Lexer.cs
   - Added `Required` and `Init` modifiers to Modifiers enum (Declarations.cs)
2. **Parser support**: ✅ ParseModifiers handles new modifiers
   - Updated ParseModifiers() to recognize `required` and `init` tokens
   - Both modifiers can be combined: `required init Property: type`
   - Work with both FieldDeclaration and PropertyDeclaration
3. **Transpiler support**: ✅ Correct C# code generation
   - Updated GetModifierString() to emit `required` modifier
   - Updated TranspileFieldDeclaration() to handle init-only auto-properties
     - `init` properties transpile to `{ get; init; }` instead of `{ get; set; }`
     - Both `readonly` and `init` modifiers produce init-only properties
   - Updated TranspilePropertyDeclaration() to handle init-only custom properties
     - `init` modifier changes setter to `init` instead of `set`
   - Modifiers are excluded from class-level modifier string (handled in accessors)
4. **Test coverage**: ✅ 8 new tests (2 lexer + 3 parser + 3 transpiler) = 316 total
   - Lexer: TestRequiredKeyword, TestInitKeyword
   - Parser: TestRequiredProperty, TestInitOnlyProperty, TestRequiredAndInitProperty
   - Transpiler: TestRequiredPropertyTranspilation, TestInitOnlyPropertyTranspilation, TestRequiredInitPropertyTranspilation
5. **Example**: ✅ examples/required_and_init_properties.nl
   - Demonstrates required properties (C# 11 feature)
   - Shows init-only properties (C# 9 feature)
   - Combines both modifiers for maximum safety
   - Includes Person record, User class, and Product class examples
   - Successfully compiles and runs
6. **Documentation**: ✅ Updated DESIGN.md
   - Added "Required Properties (C# 11)" section with examples
   - Added "Init-Only Properties (C# 9)" section with examples
   - Explained benefits and use cases
7. **Build status**: ✅ All 316 tests passing

**Impact:** N# now supports modern C# property features for better type safety and immutability!

**Features:**
- `required` modifier ensures properties are set during initialization (compile-time safety)
- `init` modifier creates immutable properties that work with object initializers
- Can be combined: `required init Property: type` for maximum safety
- Better than `readonly` - allows object initializer syntax

**Use cases:**
- `required`: Ensure critical data like IDs and emails are never missing
- `init`: Create immutable objects without ceremony
- `required init`: Guaranteed immutable required properties

### v1.32 (Preprocessor Directives) ✅ COMPLETE
1. **AST nodes**: ✅ Two new AST nodes for preprocessor directives
   - Created `PreprocessorDirective` statement (for inline directives within functions/blocks)
   - Created `PreprocessorDeclaration` declaration (for top-level and class member directives)
   - Both store full directive text including `#` (e.g., "#if DEBUG", "#region Helpers")
2. **Parser support**: ✅ Complete preprocessor directive parsing
   - ParseStatement handles preprocessor directives within function bodies
   - ParseDeclaration handles preprocessor directives at top level
   - ParseMemberDeclaration handles preprocessor directives within classes/structs/interfaces
   - Directives can appear anywhere in code (statements, declarations, class members)
3. **Analyzer support**: ✅ Pass-through handling
   - Preprocessor directives don't need semantic analysis
   - Added cases to AnalyzeStatement and AnalyzeDeclaration for pass-through
   - No validation performed - C# compiler handles all preprocessor logic
4. **Transpiler support**: ✅ Direct pass-through to C#
   - TranspileStatement emits preprocessor directives as-is
   - TranspileDeclaration emits preprocessor directives as-is (via TranspilePreprocessorDeclaration)
   - Preserves exact directive text with proper indentation
   - C# compiler processes all preprocessor directives natively
5. **Test coverage**: ✅ 8 new tests (4 parser + 4 transpiler) = 308 total
   - TestPreprocessorDirectiveTopLevel: Top-level #if/#endif parsing
   - TestPreprocessorDirectiveInFunction: Inline preprocessor in function body
   - TestPreprocessorRegion: #region/#endregion parsing
   - TestPreprocessorDefine: #define parsing
   - Corresponding transpiler tests verify correct C# output
6. **Example**: ✅ examples/preprocessor_directives.nl
   - Demonstrates #region/#endregion for code organization
   - Shows #if DEBUG/#else/#endif for conditional compilation
   - Works at top level, in classes, and in function bodies
   - Successfully compiles and runs
7. **Build status**: ✅ All 308 tests passing

**Impact:** N# now supports full C# preprocessor directive syntax for conditional compilation and code organization!

**Supported directives:**
- `#if`, `#else`, `#elif`, `#endif`: Conditional compilation
- `#define`, `#undef`: Symbol definition
- `#region`, `#endregion`: Code organization and folding
- `#warning`, `#error`: Custom compiler messages
- `#line`, `#nullable`, `#pragma`: Advanced directives

**Key design decision:** Pass-through approach - N# parser recognizes directives but doesn't interpret them. This ensures 100% C# compatibility and lets the C# compiler handle all preprocessor logic natively.

### v1.31 (Open-Ended Ranges) ✅ COMPLETE
1. **AST enhancement**: ✅ New RangeExpression node
   - Created dedicated `RangeExpression` record with optional `Start` and `End` fields
   - Replaces BinaryExpression.Range for cleaner handling of open-ended ranges
   - Supports all combinations: `start..end`, `..end`, `start..`, `..`
2. **Parser support**: ✅ Complete open-ended range parsing
   - Updated ParseRangeExpression to detect `..` at start of expression
   - Lookahead to determine if end expression exists (context-aware)
   - Checks for terminating tokens (], ), comma, semicolon) to detect open-ended
   - Handles: `..3` (from start), `2..` (to end), `..` (fully open), `1..5` (closed)
3. **Analyzer support**: ✅ Type checking
   - Added AnalyzeRangeExpression method
   - Analyzes Start and End expressions if present
   - Returns System.Range for all range variants
4. **Transpiler support**: ✅ C# 8+ code generation
   - Added TranspileRangeExpression method
   - Emits clean C# syntax: `..3`, `2..`, `..`, `1..5`
   - Direct mapping to C# range operators (no parens needed)
5. **Test coverage**: ✅ 6 new tests (3 parser + 3 transpiler) = 300 total
   - TestOpenEndedRangeToEnd: `arr[..3]` parsing
   - TestOpenEndedRangeFromStart: `arr[2..]` parsing
   - TestFullyOpenRange: `arr[..]` parsing
   - Transpiler tests verify correct C# output for all variants
   - Updated existing range tests to use RangeExpression instead of BinaryExpression
6. **Example**: ✅ examples/open_ended_ranges.nl
   - Comprehensive demonstration of all range variants
   - String slicing examples
   - Practical pagination example using open-ended ranges
   - Successfully compiles and runs with full functionality
7. **Build status**: ✅ All 300 tests passing

**Impact:** N# now has complete C# 8+ range support including open-ended ranges!

**Features:**
- `..end`: From start to index (e.g., `arr[..5]` = first 5 elements)
- `start..`: From index to end (e.g., `arr[5..]` = from index 5 onward)
- `..`: Full range (e.g., `arr[..]` = copy entire array)
- Can combine with index from end: `..^2`, `^3..`, `2..^2`

### v1.30 (Range and Index from End Operators) ✅ COMPLETE
1. **Token support**: ✅ Reused existing tokens
   - `BitwiseXor` token (`^`) dual-purpose: bitwise XOR and index from end (context-dependent)
   - `DotDot` token (`..`) for range operator (already existed)
2. **AST support**: ✅ Enhanced existing enums
   - Added `UnaryOperator.IndexFromEnd` for `^n` expressions
   - Reused `BinaryOperator.Range` for `start..end` expressions (already existed)
3. **Parser support**: ✅ Full parsing implementation
   - Updated ParseUnaryExpression to handle `^` as prefix unary operator for index from end
   - Range operator parsing already existed in ParseRangeExpression
   - Context-dependent: `^` is unary prefix when no left operand, binary XOR otherwise
4. **Analyzer support**: ✅ Type resolution
   - `^n` expressions return `System.Index` type
   - `start..end` expressions return `System.Range` type
   - Type lookup via LookupType for .NET types
5. **Transpiler output**: ✅ C# 8+ syntax generation
   - Index from end: `^n` transpiles to `^n`
   - Range: `start..end` transpiles to `start..end`
   - Direct mapping to C# operators
6. **Test coverage**: ✅ 6 new tests (3 parser + 3 transpiler) = 294 total
   - TestIndexFromEndExpression: Verifies `arr[^1]` and `arr[^2]` parsing
   - TestRangeExpression: Verifies `arr[1..4]` parsing
   - TestRangeWithIndexFromEnd: Verifies `arr[1..^1]` combination
   - Transpiler tests verify correct C# output
7. **Example**: ✅ examples/range_and_index.nl
   - Demonstrates index from end: `arr[^1]`, `arr[^2]`, `arr[^3]`
   - Demonstrates range: `arr[2..5]`, `arr[0..3]`
   - Demonstrates combination: `arr[2..^2]`, `arr[^3..^0]`, `arr[0..^2]`
   - Successfully compiles and runs with full functionality
8. **Build status**: ✅ All 294 tests passing

**Impact:** N# now supports modern C# 8+ range and index operators for elegant array slicing!

### v1.29 (Operator Overloading) ✅ COMPLETE
1. **Operator keyword**: ✅ Added `Operator` token type
   - Added to Token.cs and Lexer keywords dictionary
   - Enables `static func operator +` syntax
2. **AST support**: ✅ Enhanced FunctionDeclaration
   - Added `IsOperatorOverload` flag and `OperatorSymbol` field
   - Backward compatible with existing code (C# records add defaults)
3. **Parser support**: ✅ Full operator parsing
   - ParseOperatorSymbol() handles all overloadable operators
   - Supported: +, -, *, /, %, ==, !=, <, >, <=, >=, !, ~, &, |, ^, <<, >>, ++, --, true, false
   - Syntax: `static func operator +(a: Type, b: Type): Type { ... }`
4. **Analyzer validation**: ✅ Comprehensive compile-time checks
   - ValidateOperatorOverload() ensures static modifier
   - Validates parameter counts (unary = 1, binary = 2, +/- = 1 or 2)
5. **Transpiler output**: ✅ Correct C# operator syntax
   - Emits `public static ReturnType operator Symbol(params)`
   - Forces public static modifiers for operators
6. **Test coverage**: ✅ 9 new tests (4 parser + 5 transpiler) = 288 total
7. **Example**: ✅ examples/operator_overloading.nl
   - Vector2D with +, -, *, ==, != operators
   - Complex struct with expression-bodied operators
8. **Build status**: ✅ All 288 tests passing

**Impact:** N# now supports operator overloading - major C# feature for custom types!

### v1.28 (Testing, Async, and Tool Packaging) ✅ COMPLETE
1. **Testing Support - CLI Integration (Task 009)**: ✅ COMPLETE
   - Added `nlc test` command to CLI
   - Discovers .tests.nl files in project directory
   - Compiles test files with source files so tests can access symbols via imports
   - Generates test .csproj with XUnit dependencies (Microsoft.NET.Test.Sdk, xunit, xunit.runner.visualstudio)
   - Test declarations wrapped in public test class (namespace_Tests)
   - Automatically adds `using Xunit;` when tests are present
   - Tests run with `dotnet test` integration
   - Created comprehensive example: examples/TestExample/ with Calculator and 6 passing tests
2. **Async Implicit Wrapping (Task 004)**: ✅ COMPLETE
   - Transpiler now accepts ProjectConfig parameter
   - WrapAsyncReturnType() method wraps async function return types
   - Reads `language.asyncDefaultType` from project.yml (defaults to ValueTask)
   - Implicit wrapping: `func async Foo(): string` → `async ValueTask<string> Foo()`
   - Explicit wrapping bypassed: `func async Bar(): Task<string>` → `async Task<string> Bar()` (no double wrapping)
   - void async → ValueTask/Task (based on config)
   - Updated all Transpiler instantiation points (MultiFileCompiler, CLI) to pass config
3. **Global .NET Tool Configuration (Task 013)**: ✅ COMPLETE
   - Updated Cli.csproj with PackAsTool=true
   - Tool command name: nlc
   - PackageId: nlc
   - Version: 0.1.0
   - Package metadata: authors, description, license (MIT), tags, URLs
   - Successfully tested: `dotnet pack` creates nlc.0.1.0.nupkg
   - Users can install globally: `dotnet tool install -g nlc`
4. **Test status**: ✅ All 279 tests passing
5. **Examples working**: ✅
   - TestExample: 6 tests passing with Calculator
   - WeatherDemo: Multi-file project runs successfully
   - All CLI commands (build, run, test) verified

**What works:**
- Complete testing workflow: write .tests.nl files → `nlc test` → XUnit runs tests ✅
- Async functions with implicit Task/ValueTask wrapping based on project config ✅
- Global tool packaging ready for distribution ✅
- All existing functionality preserved ✅

### v1.27 (Testing Support - Core Language Features) ✅ COMPLETE
1. **Test declaration syntax**: ✅ `test "description" { ... }`
   - Added Test keyword token to lexer
   - Created TestDeclaration AST node
   - ParseTestDeclaration() method generates PascalCase method names
   - Transpiles to XUnit [Fact] methods
2. **Assert statement with smart transpilation**: ✅ Multiple assert patterns
   - Added Assert keyword token to lexer
   - Created AssertStatement AST node
   - ParseAssertStatement() method parses condition expressions
   - Smart transpilation based on expression type:
     - `assert x == y` → `Assert.Equal(y, x)`
     - `assert x != y` → `Assert.NotEqual(y, x)`
     - `assert x != null` → `Assert.NotNull(x)` (optimized)
     - `assert x > y` → `Assert.True(x > y)` (relational)
     - `assert x` → `Assert.True(x)` (boolean)
     - `assert x is Type` → `Assert.IsType<Type>(x)` (type check)
3. **Test method naming**: ✅ Intelligent conversion
   - Converts descriptions to valid C# identifiers
   - "should add two numbers" → `ShouldAddTwoNumbers()`
   - Handles special characters, punctuation, spaces
   - PascalCase generation with proper capitalization
4. **Analyzer support**: ✅ Test scope validation
   - AnalyzeTestDeclaration() creates function-like scope
   - AnalyzeAssertStatement() validates condition expressions
   - Proper statement analysis within test bodies
5. **Test coverage**: ✅ 9 new tests (2 parser + 7 transpiler)
   - TestTestDeclaration: Verifies parsing of test syntax
   - TestAssertStatement: Verifies assert parsing
   - TestTestDeclarationTranspilation: End-to-end test generation
   - TestAssertEqualTranspilation: == operator
   - TestAssertNotEqualTranspilation: != operator
   - TestAssertNotNullTranspilation: null checks
   - TestAssertGreaterThanTranspilation: relational operators
   - TestAssertBooleanTranspilation: boolean expressions
   - TestMethodNameConversion: special character handling
6. **Build status**: ✅ All 279 tests passing (270 existing + 9 new)

**What works:**
- Test declarations parse and transpile correctly ✅
- Assert statements with all major patterns ✅
- Smart XUnit assert generation ✅
- Method name conversion handles edge cases ✅

**Remaining work (Task 009):**
- CLI: Detect and compile .tests.nl files separately
- CLI: Generate test project with XUnit dependencies
- CLI: `nlc test` command to run tests
- Example: Create .tests.nl file for end-to-end validation

### v1.25 (Multi-File Compilation) ✅ COMPLETE
1. **MultiFileCompiler class**: ✅ Two-pass compilation for multiple files
   - Created MultiFileCompiler.cs with DiscoverSourceFiles, ParseAllFiles, AnalyzeAllFiles, TranspileAllFiles
   - Two-pass compilation: Pass 1 parses all files, Pass 2 analyzes and transpiles
   - Each file analyzed independently (works with existing import system)
   - Returns MultiFileCompilationResult with success status, errors, and transpiled files
2. **CLI integration**: ✅ Updated build and run commands for multi-file mode
   - BuildMultiFile method: compiles all .nl files in project directory
   - RunMultiFile method: compiles and runs multi-file projects
   - Commands work without arguments (multi-file mode) or with file argument (single-file mode)
   - Output files written to obj/generated/ with preserved directory structure
3. **Multi-file example**: ✅ Created examples/MultiFileProject/
   - Models/Person.nl: Person record, Status enum
   - Services/PersonService.nl: PersonService class using List<Person>
   - Program.nl: Main entry point, uses both models and services
   - Successfully compiles 3 files across 3 namespaces
   - Demonstrates cross-file references with import statements
4. **Import system integration**: ✅ Works seamlessly
   - Files use `import "relative/path"` for cross-file symbol access
   - Analyzer resolves imported symbols correctly
   - Each file needs proper `using` statements for .NET namespaces
5. **Help text updated**: ✅ Documents multi-file mode
6. **Test status**: ✅ All 270 tests passing (no changes to existing tests)

**What works:**
- Multi-file projects with cross-file type references ✅
- Directory structure preserved in output ✅
- Both single-file and multi-file modes ✅
- Error reporting across all files ✅

**Known limitations:**
- Each file analyzed independently (no global symbol table yet)
- Requires explicit file imports for cross-file references
- No automatic namespace-based symbol resolution
- No partial class merging
- No circular import detection
- No top-level statement ordering

**Next steps:**
- Task 009: Testing support (.tests.nl files)
- Task 004: Async implicit wrapping (use asyncDefaultType from project.yml)
- Enhanced multi-file: global symbol table, partial classes, circular import detection

### v1.24 (Project.yml Support) ✅ COMPLETE
1. **YamlDotNet dependency**: ✅ Added to Compiler project
   - Using YamlDotNet 16.3.0 for YAML parsing
   - Supports project configuration via project.yml files
2. **ProjectConfig classes**: ✅ Created data models
   - ProjectConfig: Main configuration class
   - LanguageConfig: Language-specific settings (async default type, etc.)
   - Support for name, version, entry, outputType, targetFramework, dependencies
3. **ProjectFileParser**: ✅ Implemented YAML parsing
   - Parse(yamlPath): Load project.yml from specific path
   - ParseFromDirectory(directory): Look for project.yml in directory
   - CreateDefault(): Generate default config when no project.yml exists
   - GenerateTemplate(projectName): Generate template project.yml content
4. **Validation**: ✅ Configuration validation
   - Validates outputType must be "exe" or "library"
   - Validates asyncDefaultType must be "Task" or "ValueTask"
   - Checks entry file exists (if specified)
   - Warns about target framework format
5. **CLI integration**: ✅ Updated run command
   - RunCommand looks for project.yml in source file's directory
   - GenerateCsProj helper generates .csproj with dependencies from project.yml
   - Dependencies automatically included in NuGet PackageReferences
   - Falls back to default config if no project.yml exists
6. **nlc new command**: ✅ Project scaffolding
   - Creates new project directory
   - Generates project.yml from template
   - Creates Program.nl with Main() function
   - Provides helpful instructions to user
7. **System namespace**: ✅ Auto-included
   - Transpiler now always emits `using System;` at top
   - Fixes Console.WriteLine and other System types
   - Ensures generated C# compiles without manual using statements
8. **Test coverage**: ✅ 11 new tests
   - TestParseValidProjectFile, TestParseMinimalProjectFile
   - TestParseLibraryProject, TestParseWithTaskAsyncDefault
   - TestInvalidOutputType, TestInvalidAsyncDefaultType
   - TestParseFromDirectory_Exists, TestParseFromDirectory_NotExists
   - TestCreateDefault, TestGenerateTemplate, TestEffectiveName
   - All 270 tests passing (259 existing + 11 new)
9. **End-to-end testing**: ✅
   - Created examples/SimpleProject with project.yml
   - Tested nlc new command successfully
   - Tested run command with project.yml dependencies
   - Fixed YAML template to avoid parser issues with commented dependencies

**What works:**
- project.yml parsing with full validation
- NuGet dependencies automatically included in build
- nlc new creates scaffolded projects
- nlc run uses project.yml config when present
- Language settings (asyncDefaultType) accessible for future use
- Graceful fallback when no project.yml exists

**Next steps:**
- Task 011: Multi-file compilation (use entry point from project.yml)
- Task 009: Testing support (.tests.nl files)
- Task 004: Use asyncDefaultType from project.yml for implicit wrapping

## Recent Changes

### v1.23 (Nested Property Patterns) ✅ COMPLETE
1. **AST enhancements** (Expressions.cs): ✅
   - Enhanced PropertyPattern with Pattern field for nested patterns
   - Added ObjectPattern type for standalone property matching
   - Pattern field allows recursive nesting (literals, identifiers, objects)
   - Supports unlimited nesting depth
2. **Parser improvements** (Parser.cs): ✅
   - Added ParsePropertyPatterns() helper for recursive pattern parsing
   - Support for colon syntax: `{ Name: pattern }` vs simple binding: `{ Name }`
   - Handles both `TypeName { props }` and standalone `{ props }` syntax
   - Recursive pattern parsing enables arbitrary depth
3. **Analyzer validation** (Analyzer.cs): ✅
   - Added AnalyzePropertyPatterns() for recursive pattern validation
   - Checks property existence on class/struct/record/reflection types
   - Fixed to check both FieldDeclaration and PropertyDeclaration members
   - Validates nested pattern types match property types
   - Binds variables from pattern destructuring to correct types
4. **Transpiler code generation** (Transpiler.cs): ✅
   - Added TranspileObjectPattern() for standalone property patterns
   - Added TranspilePropertyPatterns() helper for recursive transpilation
   - Emits C# 8+ nested property pattern syntax with var bindings
   - Properly handles literal vs identifier patterns
5. **Test coverage**: ✅ 8 new tests (4 parser + 4 transpiler)
   - TestNestedPropertyPatternWithLiteral
   - TestNestedPropertyPatternWithBinding
   - TestThreeLevelNestedPropertyPattern
   - TestUnionCaseWithNestedPropertyPattern
   - All transpiler tests verify correct C# output
6. **Examples**: ✅
   - examples/nested_simple_test.nl: Basic demo
   - examples/nested_property_patterns_simple.nl: Comprehensive showcase

**Syntax Examples:**
```nl
// Simple nested literal
{ Address: { City: "NYC" } } => "New Yorker"

// Nested with binding
{ Address: { City: city, State: "CA" } } => $"From {city}"

// Three-level nesting
{ HQ: { Address: { City: "NYC" } } } => "NYC HQ"

// With guards
{ Age: age, Address: { City: "NYC" } } when age < 30 => "Young"

// Union case with nested pattern
Result.Success { value: { Count: count } } => count
```

### v1.22 (Import System - Phase 2: Symbol Resolution and Analysis) ✅ COMPLETE
1. **FileResolver class**: ✅ Path resolution for file-based imports
   - Created FileResolver.cs with ResolveFilePath, ValidateImportPath methods
   - Handles relative paths (`./`, `../`) and project-root paths
   - Adds `.nl` extension automatically if not present
   - Validates file exists with helpful error messages
2. **Analyzer import processing**: ✅ Full symbol import logic
   - Added ProcessImports method to handle file and namespace imports
   - ProcessFileImport: Resolves paths, parses imported files, extracts symbols
   - ExtractPublicSymbols: Gets PascalCase (public) symbols from declarations
   - Symbols added to global scope for direct access
   - Aliased imports tracked in _importedSymbolsByAlias dictionary
   - Namespace imports work like using statements
3. **Collision detection**: ✅ Import conflict handling
   - CheckImportCollisions validates no duplicate symbols from multiple sources
   - Tracks symbol sources in _importedSymbols dictionary
   - Reports helpful errors with all conflicting file paths
   - Suggests using aliasing to resolve conflicts
4. **Member access enhancement**: ✅ Aliased import resolution
   - Updated AnalyzeMemberAccess to check import aliases first
   - `Alias.Symbol` resolves to imported symbol types
   - Works seamlessly with existing type resolution for .NET types
5. **Transpiler integration**: ✅ C# using statement generation
   - Added TranspileNamespaceImport method
   - Namespace imports → C# using statements
   - Aliased imports: `import X as Y` → `using Y = X;`
   - File imports don't emit (symbols already in scope)
6. **CLI integration**: ✅ File path support
   - Updated CompileToCSharp to pass currentFilePath and projectRoot to Analyzer
   - Enables import resolution in actual compilation
7. **Test coverage**: ✅ 2 new transpiler tests
   - TestNamespaceImportTranspilation
   - TestNamespaceImportWithAliasTranspilation
   - All 251 tests passing (32 lexer + 78 parser + 78 analyzer + 63 transpiler)
8. **Example created**: ✅ `examples/imports/` directory
   - Models.nl: Person class and Status enum
   - Program.nl: Imports and uses Models types

**Known Limitations (Future Phase 3):**
- Circular import detection not implemented
- Full multi-file transpilation (emitting all imported files together) not implemented
- Currently: Analyzer validates imports work, but transpiler only emits current file

### v1.21 (Import System - Phase 1: Syntax and Parsing) ✅ COMPLETE
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

1. **Multi-file compilation**: Extend CLI to compile multiple files (Task 011)
2. **Testing support**: Implement .tests.nl files with XUnit transpilation (Task 009)
3. **Async implicit wrapping**: Implement implicit Task/ValueTask wrapping based on project config (Task 004)
4. **Better lambda type inference**: Infer lambda parameter types from LINQ method signatures
5. **Extension method resolution**: Properly resolve extension methods like Select, Where
6. **Generic type inference**: Infer type parameters from usage context
7. **Better error messages**: Include source code context in error output
