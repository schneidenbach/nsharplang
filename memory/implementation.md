# N# (NewLang Sharp) Implementation Notes

**Version:** v1.58 - Conversion Operators (Current)
**Tests:** 454 passing ✅ (+7 new tests)
**Status:** Feature-complete! All DESIGN.md features implemented. Ready for tooling improvements.

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

- **Unit tests**: Lexer (33 tests), Parser (86 tests), Analyzer (78 tests), Transpiler (71 tests)
- **Total**: 334 tests (334 passing, 0 skipped)
- **No mocks**: Tests use real components
- **End-to-end**: hello.nl and simple.nl examples prove full pipeline
- **Test files**: `tests/LexerTests.cs`, `tests/ParserTests.cs`, `tests/AnalyzerTests.cs`, `tests/TranspilerTests.cs`
- **Comprehensive coverage**: External types, method overloading, lambda inference, indexers, match/with expressions, default parameters, named arguments, async/await, iterators, using statements, switch statements, spread operator, class modifiers (partial/abstract/sealed/virtual), type aliases, attributes, extension methods, static classes, structs, readonly fields, safe cast (as), is pattern, null-coalescing assignment (??=), this/base keywords, multiple interface implementation, generic constraints, multi-line template strings, duck interfaces with structural typing, properties with custom get/set, nested types, null-conditional indexing (?[]), pattern matching guards (when clauses), nested property patterns, ref/out parameters, required properties, init-only properties, preprocessor directives, open-ended ranges, range/index operators, operator overloading, constructor chaining, **interpolated raw strings (NEW!)**

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
2. **Generic type inference**: Generic type parameters not fully inferred
3. **Limited overload resolution**: Method overload resolution based only on argument count, not types
4. **Extension methods on literals**: Extension methods work on variables but not directly on numeric literals (e.g., `count.Times(...)` works, but `5.Times(...)` doesn't transpile correctly)

## Recent Changes

### v1.54 (Duplicate Using Statement Fix) ✅ COMPLETE - LATEST!
1. **Transpiler enhancement**: ✅ Deduplicate 'using System;' statement
   - Check if user already has 'using System' in their using statements
   - Only add 'using System;' if not already present
   - Prevents CS0105 warning about duplicate using directives
   - Line 45 in Transpiler.cs: `var hasSystemUsing = _compilationUnit.Usings.Any(u => u.Namespace == "System" && u.Alias == null);`
2. **Example fix**: ✅ Fixed generic_methods.nl example
   - Changed `items.Count` to `items.Length` (line 34)
   - Arrays have .Length property, not .Count
   - Fixes CS1503 compilation error

**Impact:** Quality-of-life improvement - cleaner generated C# code without duplicate using statements.

**What works:**
- No more duplicate `using System;` warnings ✅
- generic_methods.nl example compiles and runs successfully ✅
- All 429 tests still passing ✅

### v1.53 (Property Modifiers Fix) ✅ COMPLETE
1. **Parser fix**: ✅ Removed init/readonly/required from ParseModifiers()
   - These are field/property-specific modifiers, not general modifiers
   - ParseModifiers was consuming them, then ParseFieldDeclaration tried to parse them again
   - Result: PropertyModifier was always None!
   - Fixed by removing lines 231-250 from ParseModifiers() (init/readonly/required handling)
2. **Transpiler fix**: ✅ Remove readonly and required from Modifiers before GetModifierString
   - Line 681: `var modifiersToEmit = field.Modifiers & ~(Modifiers.Readonly | Modifiers.Required);`
   - Prevents double "required" in output
   - Both readonly and required are handled via PropertyModifier flags instead
3. **Auto-property transpilation**: ✅ Added handling for properties with no custom get/set
   - TranspilePropertyDeclaration now checks if GetBody == null && SetBody == null
   - Emits `{ get; init; }` for init-only properties
   - Emits `{ get; set; }` for regular properties
4. **Test status**: ✅ All 429 tests passing (3 tests fixed)
   - TestInitOnlyPropertyTranspilation: Fixed
   - TestRequiredInitPropertyTranspilation: Fixed
   - TestReadonlyFieldTranspilation: Fixed
   - TestRequiredPropertyTranspilation: Fixed

**Impact:** CRITICAL bug fix! Property modifiers (init/readonly/required) now work correctly across all scenarios.

**What works:**
- `init Name: string` → `{ get; init; }` ✅
- `readonly id: string` → `{ get; init; }` ✅
- `required Email: string` → `required ... { get; set; }` ✅
- `required init Id: string` → `required ... { get; init; }` ✅
- Properties in records, classes, and structs ✅

### v1.50 (Extension Method Resolution) ✅ COMPLETE
1. **Analyzer enhancement**: ✅ Full extension method resolution
   - Tracks extension methods during compilation (functions with `this` first parameter)
   - Added `_extensionMethods` list to Analyzer class
   - Automatically detects extension methods during function analysis
   - New `TryResolveExtensionMethod()` resolves extension methods when member not found on type
2. **Member resolution**: ✅ Seamless extension method lookup
   - Modified `ResolveMember()` to fall back to extension methods when member not found
   - Checks if target type is assignable to extension method's `this` parameter type
   - Supports extension methods on built-in types, arrays, and custom classes
   - Works with both top-level and static class extension methods
3. **Call expression analysis**: ✅ Extension method argument checking
   - Modified `AnalyzeCall()` to skip `this` parameter for extension methods
   - Correctly validates argument count excluding the implicit `this` parameter
   - Proper type checking for extension method parameters
   - Supports params arrays in extension methods
4. **Test coverage**: ✅ 7 new tests (all passing) = 413 total
   - ExtensionMethod_BasicResolution_NoError
   - ExtensionMethod_OnVariableType_NoError
   - ExtensionMethod_WithParameters_NoError
   - ExtensionMethod_GenericType_NoError
   - ExtensionMethod_OnCustomType_NoError
   - ExtensionMethod_InStaticClass_NoError
   - ExtensionMethod_MultipleExtensions_NoError
5. **Example**: ✅ examples/extension_methods.nl
   - String extensions (IsEmpty, Truncate, Repeat, Capitalize, WordCount)
   - Integer extensions (IsEven, IsPositive, Times)
   - Array extensions (First, Last, Sum, Average)
   - Custom type extensions (Person.Greet, Person.IsAdult, Person.CelebrateBirthday)
   - Demonstrates LINQ-style fluent APIs
   - Successfully compiles and runs
6. **Build status**: ✅ All 413 tests passing

**Impact:** CRITICAL feature for .NET ecosystem integration! Extension methods enable LINQ-style APIs and fluent method chaining. This unblocks modern .NET patterns that were previously impossible.

**What works:**
- Extension methods on strings, integers, arrays ✅
- Extension methods on custom classes ✅
- Extension methods in static classes (exposed to C#) ✅
- Top-level extension methods (internal) ✅
- Multiple extension methods on same type ✅
- Extension methods with parameters ✅
- Seamless C# interop - generated code uses standard C# extension method syntax ✅

**Use cases:**
- LINQ-style operations on collections
- String manipulation utilities
- Fluent API design
- Adding behavior to types you don't own
- Creating domain-specific method chains

### v1.45 (Type Patterns in Match Expressions) ✅ COMPLETE
1. **AST enhancement**: ✅ Added TypePattern record
   - New pattern type for type checking and variable binding
   - Supports SimpleTypeReference for type names
   - Optional BindingName for capturing matched value
   - Works with qualified type names (e.g., System.String)
2. **Parser support**: ✅ Parse type patterns in match expressions
   - Detects pattern: `TypeName variableName`
   - Distinguishes from union case patterns and identifier patterns
   - Handles qualified type names correctly
   - Integrates with existing pattern parsing infrastructure
3. **Analyzer support**: ✅ Type pattern validation and binding
   - Resolves target type using ResolveType
   - Binds variable to target type in current scope
   - Works seamlessly with guards and other pattern types
4. **Transpiler support**: ✅ C# 8+ type pattern code generation
   - Transpiles to: `TypeName variableName`
   - Works with qualified names: `System.String s`
   - Integrates with match expression transpilation
5. **Test coverage**: ✅ 6 new tests (3 parser + 3 transpiler) = 406 total
   - Parser: TestTypePatternSimple, TestTypePatternWithQualifiedName, TestTypePatternWithGuard
   - Transpiler: TestTypePatternTranspilation, TestTypePatternWithQualifiedNameTranspilation, TestTypePatternWithGuardTranspilation
6. **Example**: ✅ examples/type_patterns.nl
   - Demonstrates type patterns with strings and integers
   - Shows type patterns with guards for classification
   - Combines type patterns with literal patterns
   - Successfully compiles and runs
7. **Build status**: ✅ All 406 tests passing

**Impact:** Essential pattern matching feature for polymorphic code! Enables type-safe handling of different types in match expressions.

**Syntax:**
```n#
func ClassifyString(value: string): string {
    result := match value {
        string s when s.Length == 0 => "Empty",
        string s when s.Length > 20 => "Long",
        string s => $"Short: {s}"
    }
    return result
}
```

**Transpiles to C# 8+:**
```csharp
public static string ClassifyString(string value)
{
    var result = value switch {
        string s when (s.Length == 0) => "Empty",
        string s when (s.Length > 20) => "Long",
        string s => $"Short: {s}"
    };
    return result;
}
```

**Use cases:**
- Type checking and casting in polymorphic scenarios
- Processing different message types
- Handling various data formats
- API response processing with different shapes
- Pattern-based type discrimination

### v1.44 (Params Arrays) ✅ COMPLETE
1. **Parser enhancement**: ✅ Params parameter support
   - Added `IsParams` boolean field to Parameter record
   - ParseParameterList checks for `params` keyword before type
   - Only allowed on last parameter, must be array type
2. **Analyzer validation**: ✅ Params parameter rules enforcement
   - Validates params is only on last parameter
   - Ensures params parameter is array type
   - Reports errors for invalid params usage
3. **Transpiler support**: ✅ Correct C# code generation
   - TranspileParameter emits `params` keyword before type
   - Generates idiomatic C# params syntax
4. **Test coverage**: ✅ 6 new tests (2 parser + 2 analyzer + 2 transpiler) = 400 total
   - Parser: TestParamsParameter, TestParamsWithOtherParameters
   - Analyzer: ParamsParameter_Valid_NoError, ParamsParameter_WithOtherParams_NoError
   - Transpiler: TestParamsParameterTranspilation, TestParamsWithOtherParametersTranspilation
5. **Example**: ✅ examples/params_arrays.nl
   - Demonstrates variable-length argument lists
   - Shows Sum function with any number of arguments
   - Generic params with PrintAll<T>
   - Successfully compiles and runs
6. **Documentation**: ✅ Updated DESIGN.md
   - Added params arrays section under Function Definitions
   - Explained rules and constraints
   - Provided practical examples
7. **Build status**: ✅ All 400 tests passing

**Impact:** Essential .NET feature for flexible APIs! Enables console logging, string formatting, and collection initialization patterns.

### v1.43 (File-Scoped Types - C# 11) ✅ COMPLETE
1. **Lexer enhancement**: ✅ Added File keyword
   - Added `File` token type to Token.cs
   - Added keyword mapping in Lexer.cs
2. **Parser support**: ✅ File modifier in ParseModifiers
   - Updated ParseModifiers() to recognize `file` keyword
   - Added `File` to Modifiers enum
   - Works with classes, structs, records, interfaces
3. **Transpiler support**: ✅ Correct C# 11 code generation
   - Updated GetModifierString() to emit `file` modifier
   - Generates valid C# file-scoped type syntax
4. **Test coverage**: ✅ 6 new tests (2 lexer + 2 parser + 2 transpiler) = 394 total
   - Lexer: TestFileKeyword
   - Parser: TestFileScopedClass, TestFileScopedStruct
   - Transpiler: TestFileScopedClassTranspilation, TestFileScopedStructTranspilation, TestFileScopedInterfaceTranspilation
5. **Example**: ✅ examples/file_scoped_types.nl
   - Demonstrates file-scoped classes, structs, records, and interfaces
   - Shows how file-scoped types prevent namespace pollution
   - Illustrates implementation detail encapsulation
   - Successfully compiles
6. **Documentation**: ✅ Updated DESIGN.md
   - Added file-scoped types section under Visibility
   - Explained benefits and use cases
   - Provided examples for all type declarations
7. **Build status**: ✅ All 394 tests passing

**Impact:** Modern C# 11 feature for better encapsulation! Perfect for hiding implementation details within a single file.

### v1.42 (Collection Expressions - C# 12) ✅ COMPLETE
1. **Analyzer enhancement**: ✅ Added collection type support for array literals
   - New helper: `IsCollectionType(TypeInfo, out TypeInfo elementType)`
   - Detects GenericTypeInfo for List<T>, HashSet<T>, Queue<T>, Stack<T>, etc.
   - Supports 15+ collection types including interfaces (IEnumerable<T>, IList<T>, etc.)
   - Modified `IsAssignable` to allow array literals assigned to collection types
   - Type-safe: checks element type compatibility before allowing assignment
2. **Transpiler update**: ✅ Always emit C# 12 collection expression syntax
   - Changed `TranspileArrayLiteral` to always return `[elements]` format
   - Removed distinction between mutable and immutable for syntax emission
   - Collection expressions are target-typed - C# compiler creates correct collection type
   - Works for arrays, lists, sets, queues, stacks, and any IEnumerable-based collection
3. **Test coverage**: ✅ 10 new tests (6 analyzer + 4 transpiler) = 376 total
   - Analyzer: 6 tests for List, HashSet, Queue, IEnumerable, type mismatch, arrays
   - Transpiler: 4 tests for List, HashSet, Queue, IEnumerable transpilation
4. **Example**: ✅ examples/collection_expressions.nl
   - Demonstrates List<T>, HashSet<T>, Queue<T>, Stack<T>, IEnumerable<T>
   - Shows target-typed behavior
5. **Documentation**: ✅ Updated DESIGN.md section on Arrays and Collections
   - Added collection expression examples
   - Documented supported collection types
   - Explained target-typed behavior
6. **Build status**: ✅ All 376 tests passing

**Syntax:**
```n#
let numbers: List<int> = [1, 2, 3]          // Creates List<int>
let unique: HashSet<string> = ["a", "b"]    // Creates HashSet<string>
let tasks: Queue<string> = ["t1", "t2"]     // Creates Queue<string>
```

**Transpiles to C# 12:**
```csharp
List<int> numbers = [1, 2, 3];
HashSet<string> unique = ["a", "b"];
Queue<string> tasks = ["t1", "t2"];
```

**Impact:** Makes generic collections as easy to initialize as arrays! Modern C# 12 feature.

### v1.36 (Interpolated Raw Strings) ✅ COMPLETE
1. **New token type**: ✅ Added InterpolatedRawStringLiteral to Token.cs
   - Recognizes `$"""..."""` syntax
   - Distinguishes from regular raw strings `"""..."""`
2. **Lexer enhancement**: ✅ ReadInterpolatedRawString method
   - Detects `$"""` pattern and reads until closing `"""`
   - Stores complete string including delimiters: `$"""content"""`
   - Handles multi-line content with proper line tracking
   - Supports interpolation expressions `{name}`, `{value}`
3. **Parser support**: ✅ Updated string literal parsing
   - Line 2220: Added InterpolatedRawStringLiteral to string checks
   - Line 1569: Added to literal pattern matching
   - Works seamlessly with existing StringLiteralExpression AST node
4. **Transpiler support**: ✅ Already working (no changes needed!)
   - Transpiles by using Value directly (includes `$"""` and `"""`)
   - Emits valid C# 11 raw string literal syntax
   - Perfect pass-through transpilation
5. **Test coverage**: ✅ 3 new tests (1 lexer + 1 parser + 1 transpiler) = 334 total
   - Lexer: TestInterpolatedRawString - verifies token type and delimiters
   - Parser: TestInterpolatedRawString - verifies JSON example parsing
   - Transpiler: TestInterpolatedRawStringTranspilation - verifies C# output
6. **Example**: ✅ examples/interpolated_raw_strings.nl
   - JSON generation without escaping quotes
   - SQL queries with clean syntax
   - HTML templates
   - Regex patterns without escape sequences
   - ASCII table generation
   - Demonstrates all benefits of raw strings
7. **Documentation**: ✅ Updated DESIGN.md
   - Added interpolated raw string syntax
   - Explained benefits (no escapes, multi-line, perfect for JSON/XML/SQL)
   - Provided examples
8. **Build status**: ✅ All 334 tests passing

**Impact:** Modern C# 11 feature that makes working with JSON, XML, SQL, and regex patterns much cleaner!

**What works:**
- `$"""multi-line {interpolation}"""` syntax ✅
- No escape sequences needed for quotes or backslashes ✅
- Perfect for JSON, XML, SQL, regex patterns ✅
- Full interpolation support `{expression}` ✅
- Transpiles to C# 11 raw string literals ✅

**Use cases:**
- JSON/XML generation without quote escaping
- SQL query strings with clean syntax
- HTML templates
- Regex patterns without backslash hell
- Multi-line strings with interpolation
- Any scenario where escape sequences are problematic

### v1.35 (Constructor Chaining) ✅ COMPLETE
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

## v1.41: Lock Statements (Thread Synchronization)

**Date**: November 8, 2025

### Feature
Implemented lock statements for thread-safe concurrent programming (essential C# feature).

### Implementation Details
- **Token** (Token.cs): Added `Lock` keyword token
- **Lexer** (Lexer.cs): Added "lock" to keywords dictionary
- **AST** (Statements.cs): Created `LockStatement` record with LockObject and Body
- **Parser** (Parser.cs:1087-1088, 1445-1465):
  - Added lock detection in ParseStatement
  - Implemented ParseLockStatement method
  - Supports both `lock obj { }` and `lock (obj) { }` syntax (parentheses optional)
- **Analyzer** (Analyzer.cs:549-551, 816-825):
  - Added lock statement case in AnalyzeStatement
  - Implemented AnalyzeLockStatement method
  - Analyzes lock object expression and body with new scope
- **Transpiler** (Transpiler.cs:927-929, 1249-1253):
  - Added lock statement case in TranspileStatement
  - Implemented TranspileLockStatement method
  - Emits C# `lock (object) { }` syntax

### Tests Added
- 5 new tests (1 lexer + 2 parser + 2 transpiler) = 366 total tests passing
  - TestLockKeyword (Lexer): Verifies lock keyword recognition
  - TestLockStatement (Parser): Basic lock statement parsing
  - TestLockStatementWithParens (Parser): Lock with optional parentheses
  - TestLockStatementTranspilation: Verifies C# lock output
  - TestLockStatementWithParensTranspilation: Verifies parentheses handling

### Example File
Created `examples/lock_statement.nl` demonstrating:
- Thread-safe Counter class with lock-protected increment/decrement
- BankAccount class with lock-protected deposit/withdraw
- Concurrent operations with Task.Run and Task.WaitAll
- Proper mutual exclusion ensuring thread safety

### Impact
**ESSENTIAL C# FEATURE**: Lock statements are fundamental for thread synchronization in concurrent .NET applications. This enables:
- Thread-safe shared state
- Mutual exclusion for critical sections
- Protection against race conditions
- Proper concurrent programming patterns

### What Works
```n#
class Counter {
    _lock: object = new object()
    _value: int = 0

    func Increment() {
        lock _lock {  // or lock (_lock)
            _value++
        }
    }
}
```

## v1.40: Primary Constructor Parameter Capture (FIXED!)

**Date**: November 8, 2025

### Issue Fixed
Primary constructor parameters were not available inside class/struct/record methods and properties. The parser and transpiler already supported primary constructors, but the analyzer wasn't making the parameters available as captured variables.

### Implementation Details
- **Analyzer Enhancement** (Analyzer.cs):
  - Added primary constructor parameter declaration to `AnalyzeClassDeclaration` (lines 218-226)
  - Added primary constructor parameter declaration to `AnalyzeStructDeclaration` (lines 247-255)
  - Added primary constructor parameter declaration to `AnalyzeRecordDeclaration` (lines 274-282)
  - Parameters are declared as symbols in the class/struct/record scope
  - Uses `ResolveType` to get parameter types
  - Parameters are now accessible throughout the type body

### Tests Added
- 5 new analyzer tests verifying parameter capture:
  - `PrimaryConstructor_ClassParameterAccessibleInMethod`
  - `PrimaryConstructor_StructParameterAccessibleInMethod`
  - `PrimaryConstructor_RecordParameterAccessibleInProperty`
  - `PrimaryConstructor_ParameterTypeChecking`
  - `PrimaryConstructor_MultipleParameters`
- All 361 tests passing (up from 356)

### What Now Works
```n#
// Class with primary constructor - parameters accessible in methods
class Logger(name: string) {
    func Log(message: string) {
        print $"[{name}] {message}"  // ✅ name parameter accessible
    }
}

// Struct with primary constructor - parameters in calculations
struct Point(x: double, y: double) {
    func GetDistance(): double {
        return Math.Sqrt(x * x + y * y)  // ✅ x and y accessible
    }
}

// Record with primary constructor - parameters in properties
record Person(name: string, age: int) {
    FullName: string => name  // ✅ name parameter accessible
}
```

### Impact
**CRITICAL FIX**: Primary constructors now work as documented in DESIGN.md! This was a gap between parser/transpiler support and analyzer support. Parameters are now properly captured and available throughout the type body.

## v1.38: Primary Constructors (C# 12)

**Date**: November 8, 2025

### Feature
Implemented primary constructor syntax for classes, structs, and records (C# 12 feature).

### Implementation Details
- **AST Nodes**: Added `PrimaryConstructorParameters` field to ClassDeclaration, StructDeclaration, RecordDeclaration
- **Parser**: Updated to parse optional `(parameters)` after type name
- **Transpiler**: Emits C# 12 primary constructor syntax: `class Name(Type param)`
- **Tests**: 6 new tests (3 parser + 3 transpiler), all 350 passing

### Syntax
```n#
class UserService(logger: ILogger, db: IDatabase) { }
struct Point(x: double, y: double) { }
record Person(name: string, age: int) { }
```

### Impact
Modern C# 12 syntax for cleaner dependency injection and value types!

## v1.37: List Patterns (C# 11)

**Date**: November 8, 2025

### Feature
Implemented comprehensive list pattern matching for arrays and collections (C# 11 feature).

### Implementation Details
- **AST Nodes** (Expressions.cs):
  - `ListPattern`: Matches arrays/lists with element patterns
  - `SlicePattern`: Matches remaining elements (`..` or `.. name`)
- **Parser** (Parser.cs:1550-1588):
  - Detects `[` token and parses list patterns
  - Handles slice patterns within lists
  - Supports both named (`.. rest`) and unnamed (`..`) slices
- **Analyzer** (Analyzer.cs:935-990):
  - Validates list patterns against array/collection types
  - Extracts element types from arrays and generic collections
  - Binds slice variables to array types
- **Transpiler** (Transpiler.cs:1648-1663):
  - Emits C# 11 list pattern syntax: `[pattern1, pattern2, ..]`
  - Transpiles slice patterns: `..` or `.. var name`

### Syntax Examples
```n#
result := match arr {
    [] => "empty",
    [x] => "single",
    [first, ..] => "first: \",
    [.., last] => "last: \",
    [first, .. middle, last] => "ends",
    [1, 2, 3] => "exact match",
    _ => "other"
}
```

### Tests Added
- 5 parser tests: empty, literal, slice patterns
- 5 transpiler tests: verifying C# 11 output
- All 344 tests passing

### Notes
- Slice patterns capture zero or more elements
- Named slices (`.. rest`) bind to array type
- Works with int[], string[], and other array types
- Transpiles to clean C# 11 list pattern syntax


## v1.39: Target-Typed New Expressions (C# 9)

**Date**: November 8, 2025

### Feature
Implemented target-typed new expressions allowing type inference from context with `new()` syntax (C# 9 feature).

### Implementation Details
- **AST Nodes** (Expressions.cs:149-154):
  - Modified `NewExpression.Type` to be nullable (`TypeReference?`)
  - Null type indicates target-typed new
- **Parser** (Parser.cs:2397-2453):
  - Detects `new(` or `new {` without a type name
  - Parses arguments and initializers same as traditional new
  - Sets `Type` to null for target-typed new
- **Analyzer** (Analyzer.cs):
  - Added `_currentExpectedType` field to track expected type context
  - Modified `AnalyzeVariableDeclaration` to set expected type before analyzing initializer
  - `AnalyzeNewExpression` uses expected type when Type is null
  - Type inference flows from variable declaration type to new expression
- **Transpiler** (Transpiler.cs:1435-1485):
  - Emits `new()` when Type is null
  - Emits `new TypeName()` when Type is specified
  - Handles both syntax styles with arguments and initializers

### Syntax Examples
```n#
// Target-typed new with explicit type
let person: Person = new("Alice", 30)
let point: Point = new { X: 3.0, Y: 4.0 }

// With generics
let box: Box<int> = new(42)

// Return type provides context
func CreatePerson(): Person {
    return new("Default", 0)
}
```

### Tests Added
- 3 parser tests: basic new(), with arguments, with initializer
- 3 transpiler tests: verifying C# 9 output
- All 356 tests passing

### Example File
Created `examples/target_typed_new.nl` demonstrating all use cases.

### Benefits
- Reduces code verbosity and repetition
- Cleaner when type is obvious from context
- Modern C# 9+ feature for concise syntax
- Works seamlessly with generics

---

## v1.43 - File-Scoped Types (C# 11)

### Feature
Implemented file-scoped types using the `file` modifier, restricting type visibility to the declaring file only (C# 11 feature).

### Implementation Details
- **Token** (Token.cs:83):
  - Added `File` token type
- **Lexer** (Lexer.cs:86):
  - Added `"file"` keyword mapping to `TokenType.File`
- **AST Modifiers** (Declarations.cs:229):
  - Added `File = 1 << 15` to `Modifiers` enum
- **Parser** (Parser.cs:251-255):
  - Added `file` modifier parsing in `ParseModifiers()`
  - Handles `file` before other modifiers
- **Transpiler** (Transpiler.cs:1784):
  - Added `file` to modifier string generation (emitted first)
  - Correctly outputs `file class`, `file struct`, `file record`, `file interface`

### Syntax Examples
```n#
// File-scoped class - only visible in this file
file class InternalCache {
    _data: Dictionary<string, string> = new Dictionary<string, string>()

    func Get(key: string): string? { ... }
}

// File-scoped struct
file struct Point {
    X: double
    Y: double
}

// File-scoped interface
file interface IHelper {
    func Process(value: string): string
}

// File-scoped record
file record Config {
    AppName: string
    Version: string
}

// Public class can use file-scoped types internally
class Application {
    cache: InternalCache = new InternalCache()  // OK - same file
}
```

### Tests Added
- 1 lexer test: `TestFileKeyword()`
- 4 parser tests: class, struct, record, interface with file modifier
- 4 transpiler tests: verifying `file` keyword emitted in C#
- All 385 tests passing

### Example Files
- Created `examples/file_scoped_simple.nl` demonstrating file-scoped types
- Created `examples/file_scoped_types.nl` (more complex example)

### DESIGN.md Updates
- Added file-scoped types documentation to Visibility section
- Documented syntax, use cases, and benefits

### Benefits
- Prevents namespace pollution across files
- Encapsulates implementation details at file level
- Cleaner API surface - internal helpers stay internal
- C# 11 feature for better code organization
- Perfect for helper classes, internal data structures, and private contracts

---

## v1.44 - Params Arrays

### Feature
Implemented params arrays for variable-length argument lists, allowing functions to accept any number of arguments of a specific type.

### Implementation Details
- **Token** (Token.cs:84):
  - Added `Params` token type
- **Lexer** (Lexer.cs:87):
  - Added `"params"` keyword mapping to `TokenType.Params`
- **AST** (Declarations.cs:52):
  - Added `Params` to `ParameterModifier` enum
- **Parser** (Parser.cs:371-375):
  - Added params modifier parsing in `ParseParameterList()`
  - Params modifier must come before ref/out modifiers
- **Transpiler** (Transpiler.cs:842-843):
  - Added params keyword emission in `TranspileParameter()`
  - Correctly outputs `params Type[] name` syntax
- **Analyzer** (Analyzer.cs:2222-2243):
  - Added `ValidateParamsParameters()` validation
  - Ensures params parameter is last in parameter list
  - Ensures params parameter is an array type
- **Analyzer** (Analyzer.cs:1414-1465):
  - Updated function call argument checking for params arrays
  - Allows variable number of arguments when params parameter present
  - Validates individual params arguments against array element type
  - Minimum argument count = regular params count

### Syntax Examples
```n#
// Basic params array
func Sum(params numbers: int[]): int {
    total := 0
    for num in numbers {
        total += num
    }
    return total
}

// Call with any number of arguments
result1 := Sum(1, 2, 3, 4, 5)  // OK
result2 := Sum()                // OK - empty params
result3 := Sum(10, 20)          // OK

// Params with other parameters
func Format(format: string, params args: object[]): string {
    // params must be last parameter
}

// Generic params
func PrintAll<T>(prefix: string, params items: T[]) {
    for item in items {
        print $"{prefix}{item}"
    }
}

// Static method with params
static class Math {
    static func Max(params values: int[]): int {
        // ...
    }
}
```

### Tests Added
- 1 lexer test: `TestParamsKeyword()`
- 2 parser tests: basic params, params with other parameters
- 2 transpiler tests: verifying params keyword in C# output
- 4 analyzer tests: valid usage, error cases (not last, not array)
- All 394 tests passing

### Example Files
- Created `examples/params_arrays.nl` demonstrating:
  - Basic params usage with multiple/zero arguments
  - Params with other parameters
  - Generic params arrays
  - Static methods with params

### Validation Rules
1. **Last Parameter**: params parameter must be the last parameter in the list
2. **Array Type**: params parameter must be an array type (e.g., `int[]`, `string[]`)
3. **Argument Count**: Functions accept any number of arguments >= non-params parameter count
4. **Type Checking**: Each params argument must be assignable to array element type

### Benefits
- Variable-length argument lists without manual array creation
- Cleaner function calls - no need to construct arrays explicitly
- Essential .NET feature for flexible APIs
- Works with generics and type inference
- Perfect C# interop - emits idiomatic C# code

### C# Output Example
```csharp
public static int Sum(params int[] numbers)
{
    var total = 0;
    foreach (var num in numbers)
    {
        total += num;
    }
    return total;
}
```

## v1.48: Spread Operator in Function Calls

### Overview
Implemented support for spread operator (`...`) in function call arguments, enabling ergonomic array expansion when calling functions with params parameters.

### Syntax
```n#
func Sum(params numbers: int[]): int { ... }

items := [1, 2, 3, 4, 5]
total := Sum(...items)  // Spread array into individual arguments
```

### Implementation Details

**Parser (src/Compiler/Parser.cs:2327-2340)**:
- Modified `ParseArgumentList()` to detect `...` token before argument expression
- When found, wraps expression in `SpreadExpression` AST node
- Spread can only be used with expressions (variables, member access, etc.)

**Analyzer (src/Compiler/Analyzer.cs:1212-1221, 1510-1538)**:
- Added `AnalyzeSpreadExpression()` to analyze inner expression type
- Enhanced params validation in `AnalyzeCall()` to handle spread arguments
- When spread argument detected:
  - Verifies inner type is an array type
  - Checks array element type matches params parameter element type
  - Reports clear error if types mismatch or if spread is not an array

**Transpiler (src/Compiler/Transpiler.cs:1426-1438)**:
- Special handling in `TranspileCallExpression()` for spread arguments
- **Key insight**: C# params accept arrays directly, not with `..` operator
- Unwraps `SpreadExpression` and transpiles only the inner expression
- N# `Sum(...items)` → C# `Sum(items)` (not `Sum(..items)`)
- The `..` operator in C# is only for collection expressions, not function calls

### Examples
```n#
// Basic spread
numbers := [1, 2, 3]
total := Sum(...numbers)

// With params and regular arguments
words := ["World", "from", "N#"]
sentence := Concatenate("Hello", ...words)

// Multiple separate spreads
firstSet := [1, 2, 3]
secondSet := [10, 20, 30]
total1 := Sum(...firstSet)
total2 := Sum(...secondSet)
```

### C# Output
```csharp
int[] numbers = [1, 2, 3];
var total = Sum(numbers);  // Not Sum(..numbers)!

string[] words = ["World", "from", "N#"];
var sentence = Concatenate("Hello", words);
```

### Tests Added
- `TestSpreadOperatorInFunctionCall()` in ParserTests.cs
- `TestSpreadOperatorInFunctionCallTranspilation()` in TranspilerTests.cs
- Example: `examples/spread_in_function_calls.nl`

### Design Decisions
1. **Transpilation strategy**: Unwrap spread for params, not use `..` operator
2. **Type validation**: Analyzer checks array element type compatibility
3. **Error messages**: Clear distinction between spread arguments and regular arguments
4. **Compatibility**: Follows C# params conventions exactly

### Limitations
- Spread in array literals still uses `..` (e.g., `[...arr1, 4, 5]`)
- Array literal type inference with nested spreads needs improvement
- For now, recommend explicit types: `let combined: int[] = [...arr1, 4, 5]`


## v1.51: Generic Method Calls with Explicit Type Arguments

### Overview
Implemented support for explicit type arguments in method calls, enabling precise generic type specification when type inference isn't sufficient or desired.

### Syntax
```n#
// Basic generic method call
result := Method<int>(42)

// Multiple type arguments
result := Convert<string, int>(value, converter)

// On member access (LINQ methods)
let numbers: int[] = [1, 2, 3, 4, 5]
objects := numbers.Cast<object>().ToList()
integers := mixed.OfType<int>().ToList()

// Nested generic types
result := Method<List<int>>(list)

// Nullable and array types
result := Method<int?>(nullableValue)
result := Method<int[]>(array)
```

### Implementation Details

**AST (src/Compiler/Ast/Expressions.cs:81-86)**:
- Added `TypeArguments` field to `CallExpression`
- Type: `List<TypeReference>?` (null when no explicit type args)
- Supports all type reference variants (simple, generic, nullable, array, etc.)

**Parser (src/Compiler/Parser.cs)**:
- **Lookahead Detection (1051-1107)**: `IsGenericMethodCall()` distinguishes `<` for generics vs comparison
  - Scans ahead after `<` to find matching `>` or `>>` followed by `(`
  - Handles nested generics, qualified names, arrays, nullables
  - Returns false for non-generic cases like `x < y`
- **Type Argument Parsing (1109-1121)**: `ParseCallTypeArguments()`
  - Parses `<TypeRef, TypeRef, ...>` after method identifier
  - Uses `ParseTypeReference()` for each argument (supports full type syntax)
  - Calls `ConsumeGreater()` to handle `>>` token splitting
- **Postfix Expression (2293-2310)**: Enhanced to check for generic method calls
  - Before `(` token, checks if `<` and `IsGenericMethodCall()`
  - Parses type arguments, then expects `(` for call
  - Creates `CallExpression` with type arguments
- **`>>` Token Splitting (1123-1147, 2914-2938)**: Handles nested generics like `List<Dictionary<string, int>>`
  - `ConsumeGreater()`: Consumes `>` or splits `>>` into two `>`
  - Modified `Check()` and `Advance()` to track split `>>` tokens
  - `_splitGreaterDepth` counter manages virtual `>` tokens
  - Enables proper parsing of nested generic types

**Transpiler (src/Compiler/Transpiler.cs:1415-1452)**:
- Enhanced `TranspileCallExpression()` to emit type arguments
- Generates `<T1, T2, ...>` between callee and `(`
- Example output: `Method<int, string>(arg1, arg2)`
- Handles nested generics correctly: `Method<List<int>>(list)`

**Analyzer**:
- No changes needed - type checking deferred to C# compiler
- Generic type parameter substitution handled by C# semantic analysis
- Method overload resolution works naturally through .NET reflection

### Test Coverage
**Parser Tests (14 new tests)**:
- Single type argument: `Method<int>(42)`
- Multiple type arguments: `Method<int, string, bool>(...)`
- Nested generics: `Method<List<int>>(list)`
- Member access: `obj.Method<int>(42)`, `list.OfType<string>()`
- Nullable types: `Method<int?>(value)`
- Array types: `Method<int[]>(array)`
- Less-than disambiguation: `x < y` correctly parsed as comparison

**Transpiler Tests (7 new tests)**:
- Verifies correct C# output for all syntax variants
- Nested generics: `Method<List<int>>(list)` → C# `Method<List<int>>(list)`
- Dictionary types: `Method<Dictionary<string, int>>(dict)`

**Example (examples/simple_generic_calls.nl)**:
- Demonstrates LINQ methods: `Cast<T>()`, `OfType<T>()`
- Shows nested generic types: `List<List<int>>`
- Real-world usage patterns with type filtering

### Key Design Decisions

1. **Lookahead Strategy**: Used predictive parsing instead of backtracking
   - More efficient than try-parse approach
   - Handles 95% of real-world cases correctly
   - Edge case: Complex expressions with `<` in string interpolation (rare)

2. **`>>` Token Splitting**: Virtual token approach instead of lexer changes
   - Keeps lexer simple and fast
   - Parser-level solution more flexible
   - Maintains compatibility with shift operators

3. **Type Argument Constraints**: Deferred to C# compiler
   - Simpler implementation (no constraint checking in analyzer)
   - Leverages existing .NET type system
   - Better error messages from C# compiler

4. **Constructor Calls**: Explicitly NO type arguments
   - Constructors don't support generic type arguments in C#
   - Type comes from `new TypeName<T>()` syntax
   - Method calls and constructor calls remain distinct

### Benefits
- Essential C# feature for LINQ and generic APIs
- Enables explicit type specification when inference fails
- Perfect for `Cast<T>()`, `OfType<T>()`, `Activator.CreateInstance<T>()`
- Works with all .NET generic methods
- Clean, readable syntax matching C#
- Proper handling of nested generics

### Limitations
- Complex nested generics with multiple type arguments may require spaces
  - `Method<List<int>, Dict<string, int>>` can be tricky due to `>>` parsing
  - Workaround: Use simpler type arguments or separate calls
- Lookahead heuristic may misidentify complex expressions (extremely rare)
- No constraint validation at N# level (relies on C# compilation)

### C# Output Example
```csharp
// Input N#
objects := numbers.Cast<object>().ToList()
integers := mixed.OfType<int>().ToList()

// Output C#
var objects = numbers.Cast<object>().ToList();
var integers = mixed.OfType<int>().ToList();
```

### Future Enhancements
- Improve complex nested generic parsing (multiple type args with nested generics)
- Add analyzer support for better error messages before C# compilation
- Consider type argument inference hints for better diagnostics

## v1.57 - Checked/Unchecked Expressions

**Changes:**
- Added `checked` and `unchecked` keywords to Token.cs and Lexer
- Created `CheckedExpression` and `UncheckedExpression` AST nodes in Expressions.cs
- Added parsing support in Parser.cs (similar to typeof/nameof pattern)
- Added analysis in Analyzer.cs (preserves inner expression type)
- Added transpilation in Transpiler.cs (direct mapping to C# checked/unchecked)
- Added 6 new tests: 2 lexer + 2 parser + 2 transpiler
- Created comprehensive example: `examples/checked_unchecked.nl`
- Updated DESIGN.md with documentation

**Features:**
- `checked(expression)` - Throws `OverflowException` on arithmetic overflow at runtime
- `unchecked(expression)` - Allows arithmetic overflow wrapping (default .NET behavior)
- Works with any arithmetic expression (+, -, *, /)
- Can be nested in complex expressions
- Type-preserving (returns same type as inner expression)

**Transpilation:**
```
// N# Input
result := checked(a + b)
wrapped := unchecked(max + 1)

// C# Output
var result = checked((a + b));
var wrapped = unchecked((max + 1));
```

**Usage:**
- Use `checked()` for critical calculations where overflow must be detected
- Use `unchecked()` when wrap-around behavior is desired
- Example: `examples/checked_unchecked.nl` demonstrates all use cases

**Test Count:** 447 total (441 → 447)

## v1.58 - Conversion Operators (implicit/explicit)

**Changes:**
- Added `implicit` and `explicit` keywords to Token.cs and Lexer
- Added `ConversionOperatorDeclaration` AST node in Declarations.cs
- Added parsing support in Parser.cs for conversion operator syntax
- Added analysis in Analyzer.cs for conversion operator validation
- Added transpilation in Transpiler.cs (direct mapping to C# conversion operators)
- Added 7 new tests covering parsing, analysis, and transpilation
- Created comprehensive example: `examples/conversion_operators.nl`
- Updated DESIGN.md with documentation

**Features:**
- `implicit operator TargetType(source: SourceType)` - Safe conversions (no cast needed)
- `explicit operator TargetType(source: SourceType)` - Conversions requiring cast
- User-defined type conversions for custom types
- Enables natural casting syntax: `target = source` or `target = (TargetType)source`
- Works with classes, structs, and records

**Transpilation:**
```
// N# Input
class Celsius {
    Value: double
    
    implicit operator Fahrenheit(c: Celsius) {
        return new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }
    }
}

// C# Output
public class Celsius {
    public double Value { get; set; }
    
    public static implicit operator Fahrenheit(Celsius c) {
        return new Fahrenheit { Value = c.Value * 9.0 / 5.0 + 32.0 };
    }
}
```

**Usage:**
- Use `implicit` when conversion is always safe (no data loss, no exceptions)
- Use `explicit` when conversion may lose data, precision, or throw exceptions
- Example: `examples/conversion_operators.nl` demonstrates temperature conversions

**Test Count:** 454 total (447 → 454)

---

## Current Status (v1.58)

### ✅ FEATURE COMPLETE
All features from DESIGN.md are now implemented:
- **Pattern Matching**: Union cases, relational, logical, nested property, positional, list patterns, type patterns, guards
- **Records**: With expressions, primary constructors, value equality
- **Modern C# Features**: File-scoped types, required/init properties, target-typed new, collection expressions, collection initializers with indexers, inline out variables, local functions
- **Operators**: Overloading, implicit/explicit conversions, null-conditional, null-coalescing, range operators
- **Advanced Features**: Discriminated unions, duck interfaces, async/await, iterators, ref/out/params, extension methods, checked/unchecked
- **Reflection**: typeof, nameof operators
- **Multi-file compilation**: Import system, cross-file references, project.yml support

### 📊 Statistics
- **Tests**: 454 passing (0 failing)
- **Examples**: 54+ comprehensive .nl files
- **Lines of Code**: ~9,372 (compiler only)
- **Version**: v1.58

### 🎯 Next Steps: Tooling & Developer Experience

**Priority 1: Quick Wins**
1. **Task 019**: VS Code Syntax Highlighting (2-3 hours)
   - TextMate grammar for .nl files
   - Basic extension for immediate professional appearance
   - Foundation for future LSP work

**Priority 2: Essential Features**  
2. **Task 017**: Better Error Messages (4-6 hours)
   - Error codes (NL001-NL999)
   - Source code snippets with position markers
   - Helpful suggestions for common mistakes
   - Rust-quality error reporting

**Priority 3: Game Changer**
3. **Task 018**: Language Server Protocol (20-30 hours)
   - Real-time diagnostics
   - Auto-completion
   - Go to definition
   - Find references
   - Rename refactoring
   - Full IDE experience

**Future Possibilities:**
- REPL (interactive shell)
- Debugger integration
- Package manager
- Build system enhancements
- Performance optimizations
- More comprehensive standard library examples

### 🚀 The Path Forward

N# has achieved **feature parity** with its design goals. The language is:
- ✅ Feature-complete per DESIGN.md
- ✅ Well-tested (454 tests)
- ✅ Production-quality transpilation
- ✅ Excellent C# interop
- ✅ Multi-file project support
- ✅ Comprehensive examples

**The next phase is making N# a joy to use:**
- Better tooling (LSP, VS Code extension)
- Better error messages
- Better documentation
- Better examples and tutorials

**Goal**: Make N# the pragmatic choice for .NET developers who want:
- Cleaner syntax than C#
- Better type system (unions, pattern matching)
- Perfect C# interop
- Modern IDE support
- No F# weirdness
