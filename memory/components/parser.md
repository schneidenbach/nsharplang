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

ONE layer, as of task 020 slice 22: the parser's assertion layer is entirely N#.
- **Native contracts** (canonical): nine files, one per observable contract of the same owner.
  `ColumnarParserRecovery.tests.nl` pins the `ParseFilePreamble` diagnostic stream in POSITION-SORTED
  order (the CLI-shaped oracle order); `ColumnarParserErrorRecovery.tests.nl` pins the `ParseFileAst`
  contract — diagnostics in RECORDING order, whole message / snippet / explanation / hint / suggestion
  list / docs URL per diagnostic, plus the recovered declaration, statement and member censuses;
  `ColumnarParserAst.tests.nl` pins the materialized AST node-by-node against goldens inventoried from
  Parser.cs, and owns the `AstEq` reflective comparator and the `Golden.*` builders all three AST
  files use; `ColumnarParserDeclarations.tests.nl` pins WHOLE TREES over the real-world declaration
  corpus (task 020 slice 17); `ColumnarParserStatements.tests.nl` pins whole trees over the
  real-world STATEMENT and test-DSL corpus (task 020 slice 18); and `ColumnarParserPatterns.tests.nl`
  pins whole trees over the PATTERN / `match`, parameter- and argument-modifier, operator- and
  conversion-overload and constructor-initializer corpus, plus the two inline-`out` refusals, which
  are that file's negative half (task 020 slice 19); and `ColumnarParserSmallFamilies.tests.nl` pins
  whole trees over the FILE-HEADER (package / namespace / both import kinds), LITERAL and
  INTERPOLATION, ATTRIBUTE and PREPROCESSOR corpus, plus that tranche's two refusals — the
  interpolation trailing-token error and the attribute-after-parameter-name error, the arc's first
  MULTI-diagnostic negative (task 020 slice 20); and `ColumnarParserCallAccess.tests.nl` pins whole
  trees over the CALL-AND-ACCESS tier of the expression family — member access, call, index and
  range, `new` with its object and collection initializers, and the generic-call family with its
  `<`-disambiguation control — thirty contracts with no negative at all, the first all-positive
  tranche of the arc (task 020 slice 21); and `ColumnarParserKeywordLambdaType.tests.nl` pins whole
  trees over the LAST tranche — keyword and primary expressions (15), lambdas (7), type references
  (4, carrying the campaign's final negative) and operators (4) — the file that finished the
  migration (task 020 slice 22); and `ColumnarParserEventSubscription.tests.nl` pins whole trees over
  the `on` / `off` EVENT-SUBSCRIPTION corpus — the subscription as a bare expression statement, as a
  `:=` initializer and over a `this` receiver, the `off` statement, `on` / `off` used as ordinary
  identifiers, and a context control in which a local named `on` does not stop the next line parsing
  a subscription (task 020 slice 24, migrated from `tests/EventSubscriptionTests.cs`); and
  `ColumnarParserErrorHandling.tests.nl` pins whole trees over the ERROR-HANDLING corpus — 24
  fixtures of malformed and C#-shaped source, 13 of which report a diagnostic and 11 of which report
  NONE, each with its census and every diagnostic pinned WHOLE through `PeRow` (task 020 slice 25,
  migrated from `tests/ErrorHandlingTests.cs`). **That file is where the `var` fact is written down**:
  `var x = 5` is C# and not N#, so the parser reads `var` as an ordinary IdentifierExpression
  statement and `x = 5` as a separate AssignmentExpression statement — twice the statements the
  fixture's author intended, and none of them a declaration. Its other measured finds: an unterminated
  `/* … */` swallows the WHOLE file and reports NOTHING; `func main() ` with no body parses silently
  to a NULL `Body` (as against the empty BlockStatement `func main() {}` produces); 100 nested
  parentheses produce 100 real `ParenthesizedExpression` nodes with no collapsing and no depth cap;
  and a 1000-character identifier is carried whole with correct columns past 999. **The two entry points do not
  always agree on ORDER** — see the "recording order is not position order" contract — so a census's
  order tells you which entry point produced it. Run with
  `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false`.
- **There is no C# parser suite any more.** `tests/ParserTests.cs` was migrated tranche by tranche and
  DELETED in task 020 slice 22: **slice 17 took the DECLARATION family — 50 of its 212 `[Fact]`s,
  1,358 lines — slice 18 the STATEMENT family plus the test DSL — 23 more, 608 lines — slice 19 the
  four NON-EXPRESSION families (patterns and `match` 23, parameter and argument modifiers 14,
  operator and conversion overloads 6, constructor initializers 3) — 46 more, 1,397 lines — slice 20
  the four SMALL families (the file header 12, literals and interpolation 9, attributes 8, the
  preprocessor 4) — 33 more, 711 lines — slice 21 the CALL-AND-ACCESS tier of the expression family
  (postfix access 9, index-from-end and ranges 6, `new` and initializers 8, generic calls 7) — 30
  more, 998 lines — and slice 22 the remaining 30 methods and 824 lines, plus both private helpers
  (`Parse`, `AssertHasParseError`) and the class itself.** The analyzer / linter / formatter /
  completion suites still drive `ParseFileAst` indirectly, but none of them asserts on the parse tree.
  The error-case half — `tests/ParserErrorTests.cs`, 1,914 lines and 104 xUnit
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
the `ParserTests.cs` that slice 18 read, and are already pinned by `ColumnarParserAst.tests.nl`'s
tranche 10, so slice 18 added no contracts for them.

**WHAT THE PATTERN / MODIFIER / OPERATOR TRANCHE MEASURED THAT THE C# COULD NOT SEE (task 020 slice
19).** The clean-parse pin holds on all 44 positive sources too, so it has now found no defect over
**117** real-world fixtures. The margin here is total rather than incidental: the tranche's 1,397 C#
lines contain exactly **three** `.Line` and **three** `.Column` assertions, all six in
`TestPropertyPatternSourceLocations` and all about the same three property names, so every other
position in every other fixture was unstated.

**WHAT IS NEW TO THE LEDGER, AS OPPOSED TO MERELY NEW TO THE DELETED TESTS, WAS CHECKED RATHER THAN
ASSUMED** — `ColumnarParserAst.tests.nl`'s stage-N+1c tranches 9c/10/11 already pin, over synthetic
one-line sources, the `SlicePattern` anchored on the `[` rather than its `..` (:3373), the
implicit-binding property pattern `{ N }` that leaves `Pattern` null (:3494), the `TypePattern` whose
type reference is `SimpleTypeReference(name, 0, 0)` (:3444), a two-element positional pattern (:3401),
`func operator +` with its symbol and both spans (:505-506), an `implicit operator`'s whole flag word,
and `: base(x)` anchored on `base` (:1536). Those seven are **restated over the real-world corpus, not
claimed as findings.** Four things ARE new. **A parenthesized pattern is a one-element
`PositionalPattern`** — there is no parenthesized-pattern node — so `(> 0 and < 10) or (…)` nests
`AndPattern` inside `PositionalPattern` inside `OrPattern`, a shape the two-element contract could not
reach. **`static func operator +` carries `Modifiers.Static` where the conversion form carries
`Modifiers.None`**, and the declaration anchors on `func`, not on `static` and not on `operator`; both
pre-existing contracts use sources without a `static`, which is exactly why `Golden.OperatorFunc`'s
hardcoded `Modifiers.None` could not express this corpus and `Golden.OpFunc` had to be added. **The
whole ARGUMENT half is unpinned elsewhere**: `Argument` carries no position at all (`Name`, `Value`,
`Modifier` are its three registered fields), and `ref x` / `out result` / `name:` set `Modifier` and
`Name` on a node no synthetic contract had ever stated. And **the two inline-`out` refusals cost
nothing**: each reports exactly ONE `NL103`, underlining the inline DECLARATION rather than the `out`
keyword (span 7 for `out var num`, 9 for `out int value`), with a NULL suggestion list, and both
functions come back from recovery with their bodies intact.

**WHAT THE FILE-HEADER / LITERAL / ATTRIBUTE / PREPROCESSOR TRANCHE MEASURED THAT THE C# COULD NOT
SEE (task 020 slice 20).** The clean-parse pin holds on all 31 positive sources, so it has now found
no defect over **148** real-world fixtures. The margin is again total: the tranche's 711 C# lines
state exactly **seven** positions, all inside TWO interpolation methods and all on the same
hole-expression node and its receiver, and **zero** spans.

**THE HEADLINE FINDING IS A RAW-INTERPOLATION RULE THE DELETED TEST WAS SILENTLY ACCEPTING.** In a
**raw** interpolated string (`$"""…"""`), a `:` followed by optional whitespace SWALLOWS the next
brace group into the literal text run instead of opening a hole — `q: {a}` and `"age": {person.Age}`
are TEXT, while `q x{a}` and `"name": "{person.Name}"` (whose `{` follows a non-colon character) are
holes, and a `{` followed by a newline is text as well. The colon that suppresses a hole may sit on
an EARLIER line, and only the FIRST following brace group is swallowed (`q: {a} and {b}` gives text
plus one hole). An ORDINARY `$"…"` interpolated string is unaffected — `$"q: {a}"` is a hole. This is
almost certainly the format-clause scanner leaking outside a hole and it should be treated as a
suspected defect, not as intended behaviour; it is pinned as measured because the parity corpus pins
the owner. `TestInterpolatedRawString` asserted
`Assert.Single(parts.OfType<InterpolatedStringHole>())` over a four-line JSON template with TWO brace
groups and PASSED, because the second group had become text.

**AND FOUR MORE.** An N# raw string literal keeps its own indentation — `Value` carries the leading
newline, every line's leading spaces and the trailing indentation before the closing delimiter, so
C#'s indent-stripping rule does NOT apply. An attribute argument spelled with `=`
(`[FromQuery(Name = "q")]`) parses as an **AssignmentExpression** with a null `Argument.Name`, where
the colon form (`[Attr(x: 1)]`, tranche 9b) fills `Name` instead. An attribute-free parameter carries
a **NULL** `Attributes` list, not an empty one, while two bracket groups on one parameter flatten into
ONE list in source order. And the attribute-after-parameter-name refusal **cascades**: it reports
`NL102` with a repair suggestion and then SEVEN `NL101`s, leaving a body-less function and seven
synthetic `<error>` class declarations — which the deleted `AssertHasParseError` ("some message
contains this text") could not distinguish from a clean single-error recovery. Four shapes in this
tranche were already pinned next door over synthetic sources (a file-scoped namespace, a package with
an aliased import, an aliased file import's `PathColumn`/`PathLength`, and a top-level
`PreprocessorDeclaration`) and are **restated over the real-world corpus, not claimed as findings**.

**WHAT THE CALL-AND-ACCESS TRANCHE MEASURED THAT THE C# COULD NOT SEE (task 020 slice 21).** The
clean-parse pin holds on all 30 sources too, so it has now found no defect over **178** real-world
fixtures — and one of the thirty carried a WEAKER form of that claim itself
(`Assert.DoesNotContain(result.Errors, e => e.Severity == ErrorSeverity.Error)`, which a
warning-severity diagnostic satisfies and `PsCensus` does not). **The margin here is total: of the 368
claim rows the 30 deleted methods decode to, the number stating a `Line`, a `Column`, a `Span`, a
`NameLine` or a `NameColumn` is ZERO** — in 998 lines and 260 assertions — where slice 19's tranche had
six such rows and slice 20's had seven. So all 419 anchors the successor pins were unstated, and a
parser that moved every member access, index, call, range, `new`, initializer and array literal one
column right would have passed the whole deleted tranche.

**AND THE SIBLING SWEEP MOVED MOST OF THIS TRANCHE'S SHAPE RULES INTO THE RESTATEMENT COLUMN, WHICH IS
WHY IT IS PART OF THE METHOD.** `ColumnarParserAst.tests.nl`'s stage-N+1c corpus already pins, over
synthetic one-line sources, a null-conditional member access and index anchored on the **`?`** rather
than the `.`/`[` (:3310, :3341), a `let a := 1` anchored on its **NAME** rather than the keyword
(:4718), an `ObjectInitializerExpression` carrying its `NewExpression`'s anchor rather than the open
brace (:3915), an INDEXER `PropertyInitializer` whose `NameLine`/`NameColumn` are **both zero**
(:3937), an `ArrayTypeReference` whose `Span` is exactly its **element's** span (:3951 — `new T[2]`
spans `T`, not `T[]`), a `RangeExpression` anchored on its `..` in both the two-ended and open-start
forms (:3143, :3153), a nested generic type argument with split spans, and a **null** `TypeArguments`
for a non-generic call. All are restated over the real corpus and labelled as restatements.
**THREE SHAPES ARE GENUINELY NEW TO THE LEDGER**, each measured at ZERO occurrences in the estate
before this file: a **parenthesized receiver under an index access** (`(items)[0]`, and four levels
deep in `(nodes.name)[row] == "alpha"`, where the initializer also STOPS at the newline rather than
swallowing the next line's assignment); the **`^n` index-from-end unary**, which no PARSER contract anywhere
builds from source — the operator appears in the estate only over synthesised nodes, in
`OperatorFacts.tests.nl` and `AnalyzerOperatorExpressions.tests.nl` — so its caret anchor and its
composition inside a range (`arr[1..^1]`) are new to the parser ledger; and a `Properties` list
**interleaving named and indexer initializers** in source order, which the all-named / all-indexer
synthetic lists could not reach. A fourth thing the corpus adds rather than discovers is the
LEADING-DOT continuation chain, whose links anchor on their own lines — no one-line source can
express it.

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
