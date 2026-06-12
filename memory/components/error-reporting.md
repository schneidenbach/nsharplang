# Error Reporting Component

**File:** `src/NSharpLang.Compiler/ErrorReporting.cs`

## Responsibility

Elm-level error messages with rich context, source snippets, type information, and actionable suggestions.

## Architecture

### Two-Tier Error Reporting

1. **Rich errors (via `ErrorMessageBuilder`)** — Elm-style with `HumanExplanation`, `ContextualHint`, type info, and docs URLs. Used for common errors.
2. **Simple errors (via `Analyzer.Error()`)** — Rust-style with source snippet and caret. Used for less common errors.

Rich errors automatically get Elm-style formatting. Simple errors get Rust-style formatting.

### Key Classes

- **`CompilerError`** — Record with rich context fields (`HumanExplanation`, `ActualType`, `ExpectedType`, `ContextualHint`, `Suggestions`, `DocsUrl`)
- **`DiagnosticCatalog`** — Central policy for diagnostic metadata, default severities, categories, and build-blocking behavior across compiler, linter, CLI, MSBuild, and LSP surfaces.
- **`ErrorMessageBuilder`** — Static factory methods that create Elm-style errors: `TypeMismatch`, `ReturnValueRequiresReturnType`, `ReturnValueInVoidFunction`, `ReturnTypeMismatch`, `UndefinedVariable`, `UndefinedFunction`, `UndefinedType`, `NonExhaustiveMatch`, `WrongArgumentCount`, `WrongArgumentType`, `ImportNotFound`, `UnexpectedToken`, `MissingReturn`, `DuplicateDeclaration`, `UndefinedMember`, `ControlTransferOutOfFinally`, `LockRequiresReferenceType`
- **`TypeConversionSuggester`** — Context-aware hints for type mismatches (string↔int, nullable, arrays)
- **`SmartSuggester`** — Typo detection via Levenshtein distance with scoring
- **`ErrorSuggestions`** — Fallback suggestions keyed by error code

### Formatting Paths

| Method | Used By | Colors | "Hint:" prefix |
|--------|---------|--------|---------------|
| `Format()` → `FormatElmStyle()` | Direct use | ANSI | Yes |
| `Format()` → `FormatRustStyle()` | Direct use (no HumanExplanation) | ANSI | No (uses "help:") |
| `FormatForTooling()` | LSP, MSBuild task | No | No (raw text) |
| `FormatForMsBuild()` | MSBuild single-line | No | No (inline) |
| `OutputFormatter.DiagnosticsToText()` | CLI `--text` | No | Yes |
| `OutputFormatter.DiagnosticsToJson()` | CLI JSON (default) | No | Raw field |

**Important:** `ContextualHint` values must NOT include "Hint: " prefix — formatters add it when needed.

### Tooling Span Contract

- Compiler diagnostics carry authoritative `Line`, `Column`, and `Length` through `CompilerError`; LSP and Playground markers use those exact spans.
- Linter diagnostics carry `Location` plus `Length`; VS Code, `nlc check`, `nlc lint`, and Playground markers must use the stored linter span instead of re-searching message text in the source line.
- Shorthand declarations such as `message := "hi"` store the identifier column, so identifier-anchored diagnostics (including hygiene diagnostics like `NL001` unused-variable) underline `message`, not the `:=` operator or the tail of the identifier.
- Name lookup diagnostics should underline the unresolved name itself: missing variables (`NL301`) and missing bare call targets (`NL412`) underline the identifier being resolved, while missing members (`NL303`) underline the requested member name, including symbols requested through file-import aliases such as `Lib.MissingThing`.
- File-import diagnostics (`NL701`, `NL702`, `NL703`, and file-import `NL010`) underline the quoted path token that the developer must edit; import collisions point at the later duplicate import path rather than `(0,0)` or the `import` keyword.
- The Playground/WASM fallback analyzer still reports built-in member typos such as `"text".ToUp()` when reflection metadata is unavailable, while suppressing diagnostics for known valid built-in members such as `ToUpper` and `Length`.
- Semantic diagnostics should mark the smallest useful token or expression: wrong argument type (`NL202`) underlines the offending argument expression, wrong argument count (`NL401`) underlines the callable name, and possible null access (`NL905`) underlines the nullable receiver path instead of punctuation such as `.` or `(`.
- No matching overload diagnostics (`NL402`) underline the callable name for both CLR/reflection and N# overload groups, and should include available candidate signatures when the compiler has them.
- General type mismatch diagnostics (`NL202`) should underline the value that has the wrong type, including local/field/assignment values, enum member initializer values, object-initializer member values (`new T { Member: value }` — the member's declared type is the expected type, with closed-generic members like `Items: List<Pt>`, `Item: T` on `Box<Pt>`, and union case properties resolved under the instantiation's substitution), expression-bodied function/property values, non-boolean `if`/`while`/`for`/ternary conditions, mismatched array elements, mismatched match arm values, assigned void calls, and invalid returned values.
- `stackalloc` lengths get full semantic analysis in every systems policy (including `[boundary]`/audit where `NSYS080` is only a warning): a non-int length (anything that doesn't widen implicitly from `byte`/`sbyte`/`short`/`ushort`/`char`) and a constant negative length are `NL202` at the length expression, and an undefined name inside the length is a normal `NL301`.
- Operator type diagnostics (`NL202`) underline the single bad operand when only one side violates the operator contract, and underline the operator token when both sides make the operator itself the smallest useful location.
- Operator declaration diagnostics underline the operator syntax, not the declaration fallback: missing `static` on an overload underlines the visible `operator` keyword, while unsupported operators and parameter-count errors underline the operator symbol/name such as `%` or `true`.
- Missing required expressions after visible statement keywords (`if`, `while`, `assert`, `print`, `throw`, `yield`, `using`, `lock`, `switch`, and `in`) underline the owning keyword so VS Code shows a visible squiggle on the actionable keyword. Missing initializer or assignment values underline the owning variable or assignment target when available instead of a one-character `:=` or `=` token.
- Diagnostic spans should prefer full visible tokens over single-character whitespace insertion slots. If a visible owning identifier or keyword exists, underline that token so IDE squiggles are easy to see.
- Missing closing brace diagnostics underline the visible owner token when available, such as a function/type name or a control-flow keyword, instead of the one-character opening brace.
- Missing closing parenthesis diagnostics underline the visible owner token when available, such as the callable name in `print("hello"` or the function name in `func main(`, instead of an invisible end-of-line insertion slot.
- Missing closing bracket diagnostics underline the visible owner token when available, such as the assigned variable in `nums := [1, 2` or the indexed receiver in `nums[0`, instead of the one-character opening bracket.
- C#-style object initializer diagnostics underline the initializer member name, such as `Name` in `new User { Name = "Ada" }`, instead of the one-character `=` token.
- Invalid `using let` tuple deconstruction diagnostics underline the tuple pattern, such as `(left, right)` in `using let (left, right) := getPair()`, instead of the following block opener or a synthetic `<error>` variable.
- Parser, analyzer, and linter diagnostics that do not pass an explicit span length infer the full visible token from the source line before publishing to CLI, LSP, or Playground. Explicit one-character spans are reserved for true insertion points or single-character punctuation diagnostics.
- Missing parameter separators such as `func greet(name string)`, member separators such as `Name string`, and function return separators such as `func answer() int` underline the owning parameter, field, or function name, not the whitespace insertion slot or following type token.
- Malformed parameter lists underline the visible token or range the developer needs to fix: `func main(: string)` underlines `string`, `func main(name:)` underlines `name`, `func main(name: string, )` underlines `name: string,`, and empty generic slots such as `<T,>` or `<>` underline the visible generic parameter list instead of a one-character `:`, `)`, or `>`.
- Missing field types, including `Name:` before another field declaration, empty generic type arguments, incomplete `new` expressions, and object initializer members missing `:` underline the field name, generic type expression, `new` keyword, or initializer member name that owns the missing syntax.
- Other parser recovery diagnostics avoid punctuation-only markers: missing control-flow bodies underline the owning `if`/`for`/`while` keyword, unsupported prefix `+` underlines the visible `+ value` segment, leading member access such as `.Name` underlines `.Name`, missing `await`/`must` operands underline the keyword, and missing lambda or ternary bodies underline the visible lambda/ternary header.
- Incomplete member access diagnostics underline the visible receiver token whenever no member name follows, including same-line continuations such as `name.()` or `name. }`, so the IDE marker is on `name` instead of a one-character `.` or `?.`.
- Parser diagnostics for invalid generic constraints underline the offending constraint token: `where T : class, struct` underlines the later `struct`, and `where T : struct, new()` underlines the redundant `new()`.
- Control-flow placement diagnostics underline the full invalid control keyword (`break`, `continue`, or `return`) when the keyword appears in a context where it cannot run.
- Unreachable-statement diagnostics underline the first unreachable statement token, so keyword-led statements such as `print`, `return`, or `throw` get full-keyword squiggles instead of a one-character marker.
- Target-typed expression diagnostics underline the expression that needs type context; targetless `default` underlines the full `default` keyword.
- Pattern diagnostics should underline the invalid pattern part, not the whole match arm: unknown union cases underline the qualified case name, missing property patterns underline the property name, and list-pattern type mismatches underline the list pattern on the first line when available.
- Declaration diagnostics should underline the duplicate or invalid declaration token, not a one-character fallback: duplicate symbols/types/cases/members underline the duplicate name, duplicate test lifecycle blocks underline the full `setup` or `teardown` keyword, invalid local variable declarations such as `const answer: int` or `let value` underline the full variable name, `params` ordering/type errors underline the params parameter name, required-after-optional errors underline the required parameter name, and invalid default values underline the default expression.
- Missing declaration names underline the visible declaration keyword, such as `func`, `class`, `struct`, `record`, `interface`, `union`, `enum`, or `type`, instead of punctuation like `(`, `{`, or `=`.
- Assignment diagnostics should underline the target or value token that must change: readonly field reassignment (`NL309`) underlines the assigned field name, whether the assignment is direct (`id = ...`) or qualified (`this.id = ...`).
- Shadowing diagnostics (`NL316`) underline the shadowing declaration's NAME (the inner local/parameter), not the `:=`/`let` keyword. Definite-assignment diagnostics for locals (`NL304`) underline the READ of the unassigned variable, not its declaration.

## Error Codes

### Lint Diagnostics (001-099)

N# is near-zero-warnings (see `docs/DESIGN.md` → Strictness). Correctness/safety/hygiene lint rules are build-blocking errors; pure-style rules have been deleted and folded into the formatter.

**Active linter rules (all build-blocking errors):**
- `NL001`: Unused variable (prefix intentional unused locals with `_`)
- `NL002`: Missing import
- `NL003`: Unnecessary null check (null check on a value-type literal)
- `NL004`: Async without await
- `NL006`: Unreachable code
- `NL010`: Unused import
- `NL011`: Empty catch (silently swallows exceptions)
- `NL012`: Unused parameter
- `NL016`: Redundant null check (null-equality check on an always-non-null expression)
- `NL020`: Shadowed variable (local shadows an outer-scope variable)

**Deleted pure-style rules** (no longer diagnostics; layout is owned by `nlc format`): `NL005` (use-pattern-matching), `NL008` (camel-case-local), `NL013` (prefer-interpolation), `NL014` (unnecessary-type-annotation), `NL015` (prefer-const), `NL018` (prefer-readonly), `NL019` (empty-block).

Targeted suppression is available via `// nlc:ignore <code>` and `.editorconfig` overrides for configurable rules; the default posture is strict.

### Syntax Errors (100-199)
- `NL101`: UnexpectedToken
- `NL102`: ExpectedToken
- `NL103`: InvalidSyntax
- `NL104`: UnexpectedEndOfFile — emitted when `Consume`/`ConsumeIdentifier` reach EOF while a token is still required (e.g. `func`, `class Foo`, or a trailing `<expected>` with no body). The span anchors on the last visible owner token (the keyword/identifier), never on the empty EOF position, and the message reads "...but reached the end of the file" instead of exposing the empty `''` token.
- `NL105`: InvalidLiteral, including unterminated string, character, triple-quoted, and interpolated raw string literals with spans on the literal opener/token
- `NL106-108`: Missing closing brace/paren/bracket, with line-break and empty-list recovery pointing at visible owner tokens when available
- `NL109`: ReservedKeywordAsName — a reserved N# keyword (e.g. `base`, `this`, `new`) used where an identifier is required (field, parameter, variable, or member name after `.`). The diagnostic names the offending keyword ("'base' is a reserved keyword in N#…"), suggests concrete non-keyword renames, and the parser **consumes** the keyword so recovery doesn't re-parse it as an expression and cascade. Note: `value`/`method`/`get`/`set` etc. are NOT N# keywords — they are valid identifiers (only reserved in ILAsm textual syntax, not CLR metadata) and parse/emit cleanly. Emitted by `ConsumeIdentifier` and the member-access-after-dot path in `ParsePostfixExpression`.
- Required-expression `NL102` diagnostics after `:=`, `=`, `print`, `throw`, `if`, `while`, `foreach in`, `await`, `must`, `=>`, ternary `?`/`:`, and similar anchors recover without consuming the next statement, including statements that VS Code auto-indents after a dangling anchor. Declaration and assignment value gaps underline the variable/target name when available; keyword anchors underline the visible keyword; binary operator operand gaps underline the incomplete expression segment such as `1 +` instead of a one-character operator. Parser-recovery placeholders for missing boolean conditions must not cascade into semantic `NL202` diagnostics on whitespace.
- Object initializer members with missing values (`new User { Name: }`) report `NL102` on the property name, not the closing brace.
- Return-value diagnostics for functions with omitted return types underline the function name, because the missing annotation is fixed at the signature rather than at a one-character returned literal.

### Type Errors (200-299)
- `NL201`: TypeNotFound — emitted at declared-type positions (parameter/return/field/property/variable annotations, type aliases, `new` expressions, generic type arguments) when a simple type name resolves through no channel (built-ins, declarations/scopes incl. generic type parameters, using aliases, MLC external types, project symbols, compiler-known generics like `Result`/`Task`/`Func` with the CLR arity-suffix probe). Includes a nearest-in-scope "Did you mean 'X'?" suggestion (Levenshtein ≤ 2). Deliberately lenient cases that do NOT report: dotted/qualified names (namespace-qualified externals, `new Union.Case`), pass-1 signature collection, and lazy cross-file member resolution (no generic type parameters in scope there). Visibility-blocked cross-file types report NL201 (they are not findable from that file); enriching that to an "exists but file-private" message is a known follow-up. Before this check, typos and missing references silently reached IL emission and crashed with a raw `InvalidOperationException`.
- `NL202`: TypeMismatch (assignment, return, argument; return diagnostics distinguish omitted return type, explicit void, and wrong non-void return type)
- `NL203`: CannotInferType
- `NL204-208`: InvalidCast, AmbiguousType, CannotResolveType, InvalidTypeArgument, GenericConstraintViolation

### Semantic Errors (300-399)
- `NL301`: UndefinedVariable
- `NL302`: UndefinedType
- `NL303`: UndefinedMember
- `NL304`: DefiniteAssignmentError — covers both constructor fields and locals. A local declared without an initializer (`let x: int`) that is read before it is definitely assigned on every path that reaches the read is an error; the squiggle underlines the offending READ of the variable.
- `NL305`: MissingReturn
- `NL306`: DuplicateDeclaration
- `NL307-311`: CircularDependency, InaccessibleMember, ReadonlyAssignment, ConstantRequired, InvalidModifier
- `NL312`: UnreachableStatement (code after return/throw/exhaustive branches)
- `NL313`: InvalidExpressionStatement (value/member expression written as a statement with no side effect)
- `NL314`: UnverifiedErrorResult (error-tuple result used before the paired error is proven null)
- `NL315`: DiscardedMustUseResult (bare call to a `[MustUse]`-annotated function/method whose result is silently discarded; use the value or discard explicitly with `_ = call()`). Span underlines the callee name.
- `NL316`: ShadowedDeclaration — a local or parameter that shadows a local/parameter from an enclosing function/block scope is a hard, build-blocking error. This compiler check is authoritative: when it fires the file has a compiler error, which suppresses the linter's `NL020` for that file, so the user sees exactly one diagnostic. Shadowing a class member (field/property) is allowed, as are discards/underscore-prefixed names and sibling blocks that reuse a name without nesting.
- `NL317`: EventRequiresOnOff — a .NET event used with `+=`/`-=`/`=` or as a bare value; events are used exclusively through `on`/`off`.
- `NL318`: InvalidEventSubscription — `off` applied to something that is not a subscription returned by `on`.
- `NL319`: ControlTransferOutOfFinally — the CS0157 analog. A `return` anywhere inside a `finally` block (depth-based: a return inside a try/lock/using nested in the finally still counts), or a `break`/`continue` whose target loop/switch was entered at a SHALLOWER finally depth, is an error — ECMA-335 forbids leaving a finally handler, and the emitted `leave` was invalid IL (InvalidProgramException on every call; closed oracle defect #20). Legal: `throw`, loops opened inside the finally, and returns inside lambdas/local functions declared in the finally (the analyzer's finally context resets at nested-body boundaries). The span underlines the full control keyword. Both IL emitters keep defense-in-depth guards (the C# ILCompiler throws "compiler bug" instead of emitting; columnar declines).
- `NL320`: LockRequiresReferenceType — the CS0185 analog. A `lock` whose lockee is a KNOWN value type (numeric/bool/char builtins, struct, enum, record struct, tuple, `T?` over a value type, reflection `IsValueType`) is an error: Monitor locks on object identity, and the pre-fix emitter's raw `stloc` into the object local was unverifiable IL that segfaulted the process inside Monitor.Enter (closed oracle defect #21). STRICTER than C# for generic type parameters: an unconstrained/non-reference-constrained `T` lockee is also rejected with a constraint-specific hint (`where T: class`), because a boxed lock never provides mutual exclusion. The predicate is deliberately conservative — Unknown/External/`GenericTypeInfo` stay silent (never reuse `!IsReferenceType(...)` raw; it answers "can this be null" and would false-positive on external reference types). The span underlines the lockee expression. EmitLock now boxes value/generic lockees defensively (`box !!T` is also the correct lowering for a class-constrained `T`).
- `NL322`: MemberWriteThroughValueCopy — the CS1612 analog. A member WRITE (plain or compound) whose receiver chain passes through a VALUE-typed hop must be rooted in real storage: a local/parameter/`this` (or a bare field of one), a FIELD chain over one of those, or an ARRAY element. Any other value-typed receiver — a List indexer result, a call result, a property result — is a temporary copy: the store would land in the copy and be silently discarded (the pre-fix pipeline accepted these and LOST the write — oracle defect #22; `EmitAddressableExpression` now builds real `ldflda`/`ldelema` address chains for the legal shapes instead of spilling nested receivers to temps). CONSERVATIVE by design: hops whose types/members cannot be resolved here (unknown generics, unresolved externals) never fire. Reference-typed receivers are storage handles — every expression shape is assignable through them. The span underlines the offending receiver expression.

### Function/Method Errors (400-499)
- `NL401`: WrongArgumentCount
- `NL402`: NoMatchingOverload
- `NL403-410`: Various parameter errors
- `NL411`: MethodGroupUsedAsValue (bare method reference used where a value is required; call it or pass it to a delegate parameter)
- `NL412`: UndefinedFunction (bare call target cannot be resolved as a function, method, or callable value)

### Pattern Matching Errors (500-599)
- `NL501`: NonExhaustiveMatch
- `NL502-505`: UnreachablePattern, InvalidPattern, PatternTypeMismatch, GuardNotBoolean

### Operator Errors (600-699)
- `NL601`: InvalidOperatorOverload, including operator overload declarations missing required `static`
- `NL602`: OperatorParameterCount

### Import/Using Errors (700-799)
- `NL701`: ImportNotFound
- `NL702-704`: ImportCollision, CircularImport, NamespaceNotFound

### Compiler Diagnostics (900-999)

Under the near-zero-warnings policy these are build-blocking **errors**, not warnings (see `docs/DESIGN.md` → Strictness):
- `NL901`: UnusedVariable
- `NL902`: UnreachableCode
- `NL903`: VisibilityConvention (promoted from warning to error)
- `NL904`: ObsoleteUsage (promoted from warning to error)
- `NL905`: PossibleNullAccess — flow-based; unguarded nullable dereference/index/call is an error. Emitted from semantic analysis (visible through `nlc check`, `nlc query diagnostics`, and LSP), not the linter.
- `NL907`: Nullability — nullability mismatch (promoted from warning to error)
- `NL923`: ReferenceLoadFailure — **advisory warning, never build-blocking** (the one deliberate exception to the errors-only policy in this range). Emitted when a reference assembly failed to load or be fully inspected AND the same analysis produced unresolved-name/type errors, so a broken reference can't masquerade as a plain "not found". Healthy compilations stay quiet even if a best-effort probe failed.

**Removed:** `NL906` (UnnecessaryTypeAnnotation) is deleted — redundant type annotations are pure style, handled by the formatter rather than a diagnostic. The `NL906` slot is retired and not reused.

## Severity Policy

N# is **near-zero-warnings** (full rationale in `docs/DESIGN.md` → Strictness). The single rule: correctness/safety/hygiene issues are build-blocking errors; pure style is handled by `nlc format`, not by diagnostics. There is intentionally no large tier of ignorable warnings.

`DiagnosticCatalog` (`src/NSharpLang.Compiler/DiagnosticCatalog.cs`) is the authoritative policy surface — default severity, category, and build-blocking behavior for every code across compiler, linter, CLI, MSBuild, and LSP.

### New strict checks

- **Strict null-flow:** an unguarded nullable dereference/index/call is an error (`NL905`). Narrowing via `if x != null`, `?.`, or `??` clears it. Null safety is flow-based, not syntactic.
- **Unused-result enforcement:** a must-use or error-returning result must be used or explicitly discarded with `_ =`; silently dropping it is an error.
- **Shadowing is a compiler error** (linter `NL020`): a local may not shadow a name in an enclosing scope.
- **Definite-assignment hardening:** non-nullable fields and `out` parameters must be assigned on every path before use (`NL304`); gaps are errors.

### Docs sync — affected NL codes

Per-error docs pages live in-repo at `website/docs/errors/<code>.md` (sidebar category "Error
Reference" in `website/sidebars.js`); `NL319`/`NL320` established the layout — new rich diagnostics
should ship a page there in the same slice.

Keep the `docs.n-sharp.dev/errors/<code>` pages aligned with these changes:

| Code | Source | Change | New severity |
|------|--------|--------|--------------|
| `NL903` VisibilityConvention | compiler | promoted | Error |
| `NL904` ObsoleteUsage | compiler | promoted | Error |
| `NL905` PossibleNullAccess | compiler | promoted + now flow-based | Error |
| `NL907` Nullability | compiler | promoted | Error |
| `NL906` UnnecessaryTypeAnnotation | compiler | **deleted** (folded into formatter) | — |
| `NL003` unnecessary-null-check | linter | promoted | Error |
| `NL004` async-without-await | linter | promoted | Error |
| `NL011` empty-catch | linter | promoted | Error |
| `NL012` unused-parameter | linter | promoted | Error |
| `NL016` redundant-null-check | linter | promoted | Error |
| `NL020` shadowed-variable | linter | promoted | Error |
| `NL005` use-pattern-matching | linter | **deleted** (formatter) | — |
| `NL008` camel-case-local | linter | **deleted** (formatter) | — |
| `NL013` prefer-interpolation | linter | **deleted** (formatter) | — |
| `NL014` unnecessary-type-annotation | linter | **deleted** (formatter) | — |
| `NL015` prefer-const | linter | **deleted** (formatter) | — |
| `NL018` prefer-readonly | linter | **deleted** (formatter) | — |
| `NL019` empty-block | linter | **deleted** (formatter) | — |

Deleted code slots are retired and not reused, so existing error-page URLs can 410/redirect rather than describe a live rule.

## Example Output (Elm-style)

```
── [NL305] ERROR ───────────────────────────── Program.nl:7:1 ──

    7 | func GetName(): string {
      | ^^^^^^^^^^^^

Not all code paths return a value of type 'string'

This function is declared to return `string`, but not all code paths return a value:

Expected: `string`

Hint: Every code path through this function must end with a `return` statement that
provides a `string` value. If you don't need to return anything, change the
return type to `void`.

Suggestion: Add a `return` statement, or change the return type to `void`

See: https://docs.n-sharp.dev/errors/NL305
```

## Testing

Error reporting tests are in `tests/ErrorReportingTests.cs` covering:
- Error code formatting and DiagnosticId
- Source snippet rendering with caret markers
- All formatting paths (Elm, Rust, Tooling, MSBuild)
- ErrorSuggestions, SmartSuggester, TypeConversionSuggester
- Levenshtein distance accuracy
- ANSI color codes
