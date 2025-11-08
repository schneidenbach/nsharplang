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

- **Unit tests**: Lexer (27 tests), Parser (21 tests), Analyzer (51 tests), Transpiler (6 tests)
- **Total**: 105 tests, all passing
- **No mocks**: Tests use real components
- **End-to-end**: hello.nl and simple.nl examples prove full pipeline
- **Test files**: `tests/LexerTests.cs`, `tests/ParserTests.cs`, `tests/AnalyzerTests.cs`, `tests/TranspilerTests.cs`
- **New tests**: External type resolution, method overloading, lambda inference, indexer parsing, transpiler output validation

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

### v1.4 (Latest - Error Handling)
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
