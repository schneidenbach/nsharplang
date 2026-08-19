# Parser Component

**Owner:** `src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl` (N#)

The parser is written in N#. The former C# `Parser.cs` was deleted at the end of the task-016 ownership
arc; `ColumnarParserRecovery` is the sole parse and ordered-diagnostic authority for the compiler, the
CLI, the analyzer, the formatter, the linter, code intelligence, the playground, and the language server.

## Responsibility

Converts token stream into an Abstract Syntax Tree (AST).

## Parsing Strategy

**Recursive Descent Parser** with **Operator Precedence Climbing** for expressions.

### Why This Approach?
- Simple to understand and maintain
- Easy to add new syntax
- Good error recovery
- Natural mapping from grammar to code

## Key Design Decisions

### Lambda Parsing
**Critical detail:** Lambdas must be parsed at assignment-expression level, NOT at primary level.

```
ParseLambdaOrAssignmentExpression():
    if current is identifier and next is '=>':
        return ParseLambda()
    if current is '(' and contains '=>':
        return ParseLambda()
    else:
        return ParseAssignment()
```

This ensures `x := y => expr` parses correctly as assignment, not lambda.

### For Loop Shorthand
Parser detects `:=` in for-init position and creates `VariableDeclarationStatement`.

Supports both forms:
```
for let i = 0; i < 10; i++ { }   // Explicit
for i := 0; i < 10; i++ { }       // Shorthand
```

### Operator Precedence
From highest to lowest:
1. Primary (literals, identifiers, parens)
2. Postfix (calls, indexing, member access, `?.`, `?[]`)
3. Unary (`!`, `-`, `^`, `await`)
4. Multiplicative (`*`, `/`, `%`)
5. Additive (`+`, `-`)
6. Range (`..`)
7. Relational (`<`, `>`, `<=`, `>=`)
8. Equality (`==`, `!=`)
9. Logical AND (`&&`)
10. Logical OR (`||`)
11. Null-coalescing (`??`)
12. Conditional (`? :`)
13. Lambda/Assignment (`=>`, `=`, `+=`, etc.)

## AST Node Types

See `src/NSharpLang.Compiler/Ast/` folder:

**Adding an expression node or a new Expression-typed child?** Update
`AstChildrenCore.Of` (`src/NSharpLang.Compiler.BootstrapServices/AstChildrenCore.nl`) — the N#-owned
shared exhaustive child enumeration that the typed `AstChildren.Of` C# adapter exposes to
linter, definite assignment, capture/escape scans, and performance analyzers recurse
through. `AstChildrenTests` fails until every Expression-typed slot (including slots inside
`Argument`/`PropertyInitializer`/`TupleElement`/`MatchCase`/`InterpolatedStringHole`) is
yielded; this exists because late-added children (`NewExpression.ArrayLengthExpression`,
`StackAllocExpression.LengthExpression`) twice shipped invisible to every hand-rolled walker.

### Expressions (`Expressions.cs`)
- **BinaryExpression**: `a + b`, `a && b`
- **UnaryExpression**: `!x`, `-n`, `^index`
- **CallExpression**: `Foo(a, b)`
- **MemberAccessExpression**: `obj.Property`, `obj?.Property`
- **IndexAccessExpression**: `arr[0]`, `dict?["key"]`
- **LambdaExpression**: `x => x * 2`, `(a, b) => a + b`
- **MatchExpression**: Pattern matching with guards
- **LiteralExpression**: `42`, `"hello"`, `true`

### Statements (`Statements.cs`)
- **VariableDeclarationStatement**: `let x = 42`, `x := 42`
- **IfStatement**: `if cond { } else { }`
- **ForStatement**: `for i := 0; i < 10; i++ { }`
- **ForeachStatement**: `for item in items { }`
- **WhileStatement**: `while cond { }`
- **ReturnStatement**: `return expr`
- **YieldStatement**: `yield value`, `yield break`
- **TryCatchStatement**: `try { } catch e { }`
- **UsingStatement**: `using resource { }`
- **LockStatement**: `lock obj { }`

### Declarations (`Declarations.cs`)
- **FunctionDeclaration**: Functions with modifiers (async, generator, etc.)
- **ClassDeclaration**: Classes with members
- **RecordDeclaration**: Records (reference or struct)
- **StructDeclaration**: Value types
- **InterfaceDeclaration**: Interfaces (regular or duck)
- **UnionDeclaration**: Discriminated unions
- **EnumDeclaration**: Int or string enums

## Important Parsing Details

### Attribute Parsing
Attributes must be parsed BEFORE checking for type keywords in member declarations.

Order matters:
1. Check for attributes `[...]`
2. Check for type keywords (`class`, `struct`, `record`, etc.)
3. Fall back to field/property/method parsing

### Nested Type Support
`ParseMemberDeclaration` handles nested types (classes, structs, records inside other types).

### Pattern Parsing
Patterns in match expressions support:
- Identifier patterns: `x`, `Result.Success`
- Literal patterns: `42`, `"hello"`
- Union case patterns: `Result.Success { value: x }`
- Positional patterns: `(x, y)`
- List patterns: `[first, .., last]`
- Type patterns: `int x`, `string s`

### Guard Clauses
Match patterns can have guards:
```
match value {
    x when x > 0 => "positive",
    _ => "other"
}
```

## Error Recovery

Parser uses `Consume()` / `Expect()`-style helpers:
- `Consume(TokenType)`: Advances if the token matches; otherwise reports a diagnostic and leaves the token for recovery.
- `ConsumeIdentifier(...)`: Reports an expected-identifier diagnostic and returns `<error>` when a name is missing.
- Errors include line/column from the offending token and, when source text is available, a snippet.

Current behavior:
- Collects parse diagnostics and still returns a partial `CompilationUnit`.
- Recovers at declaration, member, statement, and block boundaries.
- Uses line/column information and statement-start lookahead to avoid swallowing the next statement after a dangling operator or required-expression anchor, including editor auto-indent after `:=`.
- Suppresses cascades with panic-mode recovery, then resets at the next useful boundary.
- Emits concrete diagnostics for common editing mistakes such as incomplete member access, missing braces, missing line-ending or empty-list `)` / `]` delimiters, missing required expressions after statement/declaration anchors, malformed string/character/raw string literals, dangling binary operators, and unsupported `=` inside N# object initializers.

Partial ASTs use placeholder nodes such as `<error>` only to keep downstream tooling alive; analyzer and tooling paths treat these as unknown values instead of reporting secondary undefined-symbol cascades.

Package names recover **with the written text preserved**: a malformed segment written attached to the name (`package good.9bad`, `package good.9.5x`) is consumed as one word-like run and carried in `PackageDeclaration.Segments` with its span, producing no parser diagnostic — the analyzer's NL103 invalid-package-name report then names and underlines exactly what the developer wrote (`AnalyzerDeclarationPolicy.ValidatePackageName`). Only a segment with no written text behind it (end of file, reserved keyword, offender on another line) records the `<error>` placeholder; those paths keep their precise parser diagnostic, and the analyzer skips placeholder segments so the mistake is reported once, never as `'<error>'`.

## Testing

Two layers:
- **Native contracts** (canonical): five files, one per observable contract of the same owner.
  `ColumnarParserRecovery.tests.nl` pins the `ParseFilePreamble` diagnostic stream in POSITION-SORTED
  order (the CLI-shaped oracle order); `ColumnarParserErrorRecovery.tests.nl` pins the `ParseFileAst`
  contract — diagnostics in RECORDING order, whole message / snippet / explanation / hint / suggestion
  list / docs URL per diagnostic, plus the recovered declaration, statement and member censuses;
  `ColumnarParserAst.tests.nl` pins the materialized AST node-by-node against goldens inventoried from
  Parser.cs, and owns the `AstEq` reflective comparator and the `Golden.*` builders all three AST
  files use; `ColumnarParserDeclarations.tests.nl` pins WHOLE TREES over the real-world declaration
  corpus (task 020 slice 17); and `ColumnarParserStatements.tests.nl` pins whole trees over the
  real-world STATEMENT and test-DSL corpus (task 020 slice 18). **The two entry points do not
  always agree on ORDER** — see the "recording order is not position order" contract — so a census's
  order tells you which entry point produced it. Run with
  `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false`.
- **C# suite**: `tests/ParserTests.cs` (plus the analyzer / linter / formatter / completion suites)
  drives the same `ParseFileAst` entry. It is being migrated tranche by tranche: **slice 17 took the
  DECLARATION family — 50 of its 212 `[Fact]`s, 1,358 lines — and slice 18 the STATEMENT family plus
  the test DSL — 23 more, 608 lines — leaving 139 methods** covering expressions and operator
  precedence, patterns, literals and interpolation, the preprocessor and file-header families,
  attributes, parameter modifiers, operator overloads, generic calls and lambdas. The error-case half —
  `tests/ParserErrorTests.cs`, 1,914 lines and 104 xUnit
  cases — was migrated to `ColumnarParserErrorRecovery.tests.nl` and deleted in task 020 slice 16.
  **One capability did not survive the move and is recorded here rather than lost**: that file bounded
  its three malformed table-driven parses with `Task.Run` + a ten-second `Wait`, so a lost no-progress
  guard failed fast instead of hanging the run. `Task.Run`, `Stopwatch` and `Environment.TickCount64`
  all decline to emit in the BootstrapServices estate, so no wall-clock bound is expressible in a
  `.tests.nl` today; a no-progress regression in `ParseTestDeclaration` now hangs the native step.

**WHAT THE DECLARATION TRANCHE MEASURED THAT THE C# COULD NOT SEE (task 020 slice 17).** The C#
helper `Parse(source)` returns `result.CompilationUnit!` and DISCARDS `result.Errors`, so every one
of the 212 positive cases was silent about whether its "valid" source parses cleanly; the successor
pins `PdCensus(source) == ""` on all 50 of its sources and **all 50 are clean**. Four shape facts the
whole-tree pins state and the member reads could not: a type declaration's `Line`/`Column` anchor on
its KEYWORD, not on its first modifier (`partial class User` anchors at the `class`, column 21 of
column 13); `required init Id: string` sets Required|Init in **both** `Modifiers` and
`PropertyModifier`, and the C# asserted only the former; a base list splits with the FIRST entry
always becoming `BaseClass` even when it is an interface (`class SimpleClass : IFoo, IBar` puts
`IFoo` in `BaseClass`), which the C# noted in a comment but asserted only for one case; and an
expression-bodied `Name: string => …` member materializes a **PropertyDeclaration**, while `Name :=
"Alice"` materializes a **FieldDeclaration with a null `Type`** — two member kinds from two spellings
that look alike.

**WHAT THE STATEMENT TRANCHE MEASURED THAT THE C# COULD NOT SEE (task 020 slice 18).** The same
clean-parse pin (`PsCensus(source) == ""`) holds on all 23 statement sources, so the pin has now
found no defect over 73 real-world fixtures. Five shape facts the whole-tree pins state and the
member reads could not. **A `using` declaration inherits the `using` KEYWORD's anchor, not its own
name's**: in `using stream := File.OpenRead("file.txt")` the inner `VariableDeclarationStatement`
sits at column 17 with the `UsingStatement`, while `stream` starts at column 23 — and the statement's
`Expression` arm is null, which the C# never read. **`lock (obj)` materializes NO
`ParenthesizedExpression`**: `lock obj` and `lock (obj)` both put a bare `IdentifierExpression` in
`LockObject` and differ only by one column, so the deleted `Assert.NotNull(lockStmt.LockObject)`
could not tell the two spellings apart. **A negative table cell is a unary `Negate` over a POSITIVE
literal** — `(-1, 1, 0)` gives `UnaryExpression(Negate)` at the `-` over `IntLiteral "1"` — where the
C# asserted only that the row held three cells. **A post-increment anchors on its `++`, never on its
operand** (`i++` puts the node at column 38 with `i` at 37). **A `CatchClause` carries no `Line`/
`Column` at all**, and the N# `catch ex: FormatException` form produces a shape byte-identical to
C#-style `catch (Exception ex)` apart from the type's own span. The statement family's untested
kinds — `while`, `const`/`readonly` locals, `break`, `continue`, `throw`, `unsafe`, `alloc`, `allow`,
local functions, tuple deconstruction, the empty statement and `await foreach` — appear ZERO times in
`ParserTests.cs` and are already pinned by `ColumnarParserAst.tests.nl`'s tranche 10, so slice 18
added no contracts for them.

**AND `Parser.cs` IS GONE**, so `ParseFileAst` is the sole production parse entry (`FixApplicator.cs`,
`Formatter.nl`, `AnalyzerImports.nl`, `AnalyzerProjectDiscovery.nl`, `CodeIntelligenceQueries.nl`).
The pre-cutover goldens in `ColumnarParserAst.tests.nl` still pin the tree Parser.cs produced, but a
golden written AFTER the cutover has no second parser to check it, and is a behavioural snapshot
whose C#-asserted subset is a faithful restatement.

## Usage Example

```text
var parseResult = NSharpLang.Compiler.Columnar.ColumnarParserRecovery.ParseFileAst(source, "example.nl");

// parseResult is FileParseAst with:
// - CompilationUnit: CompilationUnit? (Declarations, Statements, Imports, Package, Namespace)
// - Errors: List<CompilerError> in recording order
// - Success: no CompilationUnit-absent or error-severity diagnostic
```
