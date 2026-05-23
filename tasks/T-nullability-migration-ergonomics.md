# Nullability Migration Ergonomics Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Make N# nullability feel stricter than C# in normal code while staying honest about .NET interop and giving migrants mechanical exits from `null!`, `default!`, `x!.Y`, nullable `.HasValue/.Value`, `null`/`NotFound` branches, and weak flow narrowing.

**Architecture:** Keep the language surface close to C# where C# is already good (`?`, `??`, `?.`, nullable metadata), add one N#-specific explicit unwrap idiom, and put most migration help in semantic diagnostics plus code fixes. The analyzer should own nullable flow states; the linter should only report style/migration diagnostics after semantic types are available.

**Tech Stack:** N# compiler/analyzer (`src/NSharpLang.Compiler`), linter/code fixes (`Linter.cs`, `CodeFix.cs`, `CodeIntelligence/FixApplicator.cs`), CLI `nlc check|lint|fix`, C# nullable metadata (`NullableAttribute`, `NullableContextAttribute`, `MaybeNull`, `NotNullWhen`, etc.).

---

## Assumptions and constraints

- N# remains null-aware, not null-free. The design doc explicitly says N# embraces .NET null and C# nullable reference types.
- `T?` stays the spelling for nullable references and nullable values. `T` is non-null by default.
- C# interop is a first-order product constraint. Any N# feature that cannot be represented to C# must either erase cleanly or emit normal C# nullable annotations.
- C# migration artifacts are treated as migration symptoms, not user intent:
  - `null!` / `default!`: suppresses definite assignment or nullable warnings instead of modeling state.
  - `x!.Y`: asserts not-null at the use site, often hiding missing flow narrowing.
  - `nullable.HasValue` / `nullable.Value`: C# value-nullable pattern that reads badly in N# and encourages unsafe `.Value`.
  - `null` / `NotFound` branches: sentinel-style absence mixed with domain outcomes.
  - weak flow narrowing: analyzer fails to carry non-null facts through idiomatic guards, early returns, match arms, and helper methods.

## Recommendation

Adopt this policy:

1. Flow narrowing is the default ergonomic path.
2. `must` is the explicit unwrap/assert idiom.
3. `match` is the preferred absence/outcome branch idiom when the type has real cases.
4. Code fixes should migrate obvious artifacts mechanically, but never rewrite domain semantics silently.
5. C# nullable annotations are imported and emitted as first-class semantic facts.

Rejected alternatives:

- Do not make `!` the N# null-forgiving operator. It conflicts visually with logical-not, recreates C#'s footgun, and encourages local suppression over better flow.
- Do not introduce `Option<T>` as the universal replacement for null. It fights the project's interop stance and makes C# APIs alien.
- Do not make `.Value` safe by magic. It hides a runtime throw behind normal member access and keeps the worst C# nullable idiom alive.

---

## Language design

### 1. Nullable type model

Represent every expression with a base type plus a null-state:

- `NotNull`: statically known non-null.
- `MaybeNull`: may be null.
- `Null`: literal null.
- `Oblivious`: external C# metadata is missing or legacy nullable context is disabled.
- `Unknown`: analyzer has insufficient type info; do not cascade noisy null diagnostics.

Rules:

- `null` is assignable only to `T?`, `Oblivious`, or unconstrained generic `T` when interop forces it.
- `T` is assignable to `T?`.
- `T?` is not assignable to `T` without narrowing, coalescing, throwing, or explicit unwrap.
- Member access on `T?` is an error or warning depending on project mode; member access on `T` is fine.
- `?.` on `T` is allowed but linted as redundant after flow proves non-null.
- `??` narrows its result to non-null if the right side is non-null.

Example:

```n#
func DisplayName(user: User?): string {
    return user?.Name ?? "Anonymous"   // result: string, not string?
}
```

### 2. Flow narrowing rules

The analyzer should narrow nullable variables and stable member paths in these cases.

#### Direct null checks

```n#
func Length(name: string?): int {
    if name == null {
        return 0
    }

    return name.Length  // name: string
}
```

Supported forms:

- `x != null` narrows `x` to `T` in the true branch.
- `x == null` narrows `x` to `Null` in the true branch and `T` in the false branch.
- `null != x` and `null == x` are equivalent.
- `if x == null { return|throw|break|continue }` narrows `x` after the block.
- `if x != null { ... } else { return|throw }` narrows `x` after the `if` only if all non-narrowed exits terminate.

#### Boolean composition

```n#
if user != null && user.Email != null {
    Send(user.Email) // user: User, user.Email: string
}
```

Rules:

- `a && b`: facts from `a` apply while analyzing `b` and the true branch.
- `a || b`: facts from the negation of `a` apply while analyzing `b` only when sound.
- `!` inverts facts for simple predicates.
- Parenthesized expressions preserve facts.

#### Pattern matching and `is`

```n#
if obj is User user {
    return user.Email // user: User
}
```

Rules:

- `x is T y` binds `y: T` as non-null when `T` is a non-nullable reference type.
- `x is not null` narrows `x` to non-null in the true branch.
- `x is null` narrows the false branch to non-null.
- Match arm bindings are non-null when the pattern excludes null.

#### Match expressions

```n#
text := match maybeName {
    null => "Anonymous",
    name => name.Trim()  // name: string
}
```

Rules:

- `null` arm handles the null case for `T?`.
- A catch-all binding after a `null` arm is `T`, not `T?`.
- A catch-all `_` before a `null` arm makes later `null` unreachable.
- Exhaustiveness for `T?` requires either a `null` arm plus non-null coverage or a catch-all.

#### Stable member-path narrowing

```n#
if order.Customer?.Address != null {
    Print(order.Customer.Address.City)
}
```

Initial implementation should support only stable paths:

- local variables;
- parameters;
- readonly fields/properties;
- repeated property access chains with no calls or indexers.

Do not narrow unstable paths:

```n#
if repo.CurrentUser != null {
    repo.Reload()
    repo.CurrentUser.Name // still maybe-null; method call may mutate state
}
```

#### Assignment invalidation

Any assignment to `x` invalidates facts about `x` and descendants (`x.Name`, `x.Address.City`).
Any assignment to `x.Name` invalidates facts about `x.Name` and descendants, but not `x` itself.
A call with `ref`/`out` invalidates the passed symbol.
A method call on an object invalidates member-path facts rooted at that object unless the method is known pure.

#### Loops

Be conservative:

- Facts from before a loop apply entering the first iteration.
- Facts established inside a loop do not automatically hold after the loop unless every exit path establishes them.
- `while x != null { ... }` narrows `x` inside the body only.

### 3. Explicit unwrap/assert idiom: `must`

Introduce `must expr` as the N# replacement for C# `expr!` and nullable `.Value`.

Meaning:

- If `expr` is `T?`, `must expr` has type `T`.
- Runtime behavior: throws `NullReferenceException` by default if `expr` is null.
- Preferred diagnostic wording should call it an assertion: "you asserted this is not null".
- `must` is expression-level syntax, parsed like unary `await`.

Examples:

```n#
name: string? = GetName()
print (must name).Length

user := must FindUser(id)
return user.Email
```

Optional message form for higher-quality failures:

```n#
user := must FindUser(id) else "user {id} should exist after validation"
```

Lowering options:

```csharp
var user = FindUser(id) ?? throw new NullReferenceException("user {id} should exist after validation");
```

Rules:

- `must x` is allowed only when `x` is nullable/oblivious/unknown. On proven non-null `x`, lint as redundant.
- `must` should not silence unrelated definite-assignment errors.
- `must` should be banned in constructors as a substitute for initializing non-nullable fields unless a clear initializer expression exists.
- `must` should carry into generated C# as a throw/coalesce expression, not C# `!`, so runtime behavior is explicit.

Why not `!`:

- `x!.Y` is exactly the artifact we want to migrate away from.
- A keyword is grepable, teachable, and less likely to appear accidentally.
- It makes code review honest: every `must` is a tiny claim.

### 4. Nullable value types: replace `.HasValue/.Value`

N# should support .NET `Nullable<T>` for interop, but steer users to pattern/coalesce/must.

Preferred forms:

```n#
// C#-style artifact
if count.HasValue {
    print count.Value
}

// N# preferred
if count is int value {
    print value
}

// or
print count ?? 0

// or, if logically guaranteed
print must count
```

Rules:

- `T?` where `T` is a value type maps to `System.Nullable<T>`.
- `x is T value` narrows `Nullable<T>` by `HasValue` and binds `value: T`.
- `match x { null => ..., value => ... }` works for nullable value types too.
- Direct `.Value` on `T?` emits a migration warning unless dominated by a proven `.HasValue` or `x != null` guard.
- Direct `.HasValue` emits an info diagnostic suggesting `is` or `match`; leave it valid for .NET familiarity.

### 5. Domain alternatives: Result/match over `null`/`NotFound`

Use null for simple absence at API boundaries. Use unions when absence is one of multiple domain outcomes.

Bad migration smell:

```n#
user := repo.Find(id)
if user == null {
    return NotFound()
}
return Ok(user)
```

Better when the domain distinguishes missing, forbidden, validation, etc.:

```n#
union Lookup<T> {
    Found { value: T }
    NotFound { id: string }
    Forbidden { reason: string }
}

response := match repo.FindUser(id) {
    Lookup.Found { value } => Ok(value),
    Lookup.NotFound { id } => NotFound($"user {id}"),
    Lookup.Forbidden { reason } => Forbidden(reason)
}
```

Guidance:

- Do not force `Result<T>` for every nullable return. That would be ceremony.
- Lint only when a `null` branch returns/throws a named sentinel (`NotFound`, `BadRequest`, `Unauthorized`, domain error object) and the non-null branch returns a success value.
- Code fix should offer to generate a local union skeleton only as `SuggestionOnly`, never auto-apply.

### 6. C# interop behavior

#### Importing C# APIs

Map C# nullable annotations into N# types:

- `string` in nullable-enabled context -> `string`.
- `string?` -> `string?`.
- `T?` for value types -> `T?` / `Nullable<T>`.
- Unannotated legacy reference type -> `T!` internally as `Oblivious`, displayed in hover as `T (oblivious)` or `T? (legacy)` depending confidence.
- `[MaybeNull] T` return -> `T?` if `T` is unconstrained or non-nullable.
- `[NotNull]`, `[DisallowNull]`, `[AllowNull]` influence parameter assignment checks.
- `[NotNullWhen(true)] out T? value` feeds flow narrowing after method calls.
- `[DoesNotReturn]` and `[DoesNotReturnIf]` feed terminating/narrowing analysis.

Example:

```csharp
public static bool TryGetUser(string id, [NotNullWhen(true)] out User? user)
```

N# flow:

```n#
if UserStore.TryGetUser(id, out user) {
    print user.Email // user: User
}
```

#### Emitting N# APIs to C#

- Emit `#nullable enable` in generated C#.
- Emit nullable reference syntax for public/internal C# surfaces (`string?`, `User?`).
- Emit attributes where syntax alone is not enough:
  - `[MaybeNull]` for generic returns where `T?` cannot express the contract cleanly.
  - `[NotNullWhen(true)]` for N# `try`/predicate helpers if the language later adds an annotation syntax.
- Do not emit C# null-forgiving `!` except inside compiler-generated code that is unreachable to source users and covered by tests.

#### Oblivious mode policy

Project option:

```yaml
language:
  nullableInterop: warn # strict | warn | oblivious
```

- `strict`: treat oblivious C# references as `T?`; users must narrow.
- `warn` default: allow assignment/member access but warn at boundaries.
- `oblivious`: C# legacy style; suppress warnings for migration-heavy projects.

---

## Tooling plan

### Diagnostics

Reserve a nullability diagnostic block so users can tune migration severity in `.editorconfig`.

- `NL030 PossibleNullDereference` (warning in `warn`, error in `strict`): member/index/call on maybe-null receiver.
- `NL031 NullableToNonNullableAssignment` (error): assigning `T?` to `T` without narrowing/coalesce/must.
- `NL032 RedundantNullCheck` (info/warning): checking a proven non-null value.
- `NL033 RedundantMust` (info): `must` on proven non-null expression.
- `NL034 PreferPatternForNullableValue` (info): `.HasValue`/`.Value` pair can become `is T value`.
- `NL035 UnsafeNullableValueAccess` (warning): `.Value` without dominating `HasValue`/non-null check.
- `NL036 PreferMatchForNullSentinelBranch` (info): branch returns `NotFound`/sentinel; consider union/match.
- `NL037 ObliviousInteropNullability` (warning): legacy C# nullable metadata missing at boundary.
- `NL038 NullForgivingArtifact` (warning): C# migration artifact `!` after nullable expression if parser accepts it.
- `NL039 DefaultNullArtifact` (warning/error): `default!` or `null!` used for non-nullable initialization.

### Code fixes

Safe fixes:

- `x!.Y` -> `(must x).Y` when parser represents null-forgiving artifacts.
- `nullable.Value` -> `must nullable` only when there is no nearby `HasValue` guard; safety `ReviewNeeded` because runtime behavior remains a throw.
- `if x == null { return fallback } return x.Y` -> keep code but analyzer should stop warning after narrowing; no text edit needed.
- `x == null ? fallback : x.Y` -> no fix initially; semantic narrowing is enough.
- `x ?? throw new Exception(...)` remains valid; no rewrite to `must` unless user requests style fix.

Review-needed fixes:

- `.HasValue`/`.Value` guarded block -> `if x is T value { ... }`.
- `if x == null { return NotFound(...) } ...` -> generate `Lookup<T>` union skeleton plus `match` example in a preview.
- `field: string = default!` -> add constructor parameter and assignment when the class has a single obvious constructor; otherwise insert `field: string?` or `field: string = ""` suggestions, not auto-apply.

Do not fix automatically:

- Changing public API `T?` to `Result<T>`.
- Removing null checks in externally observable code.
- Converting `Oblivious` C# APIs to non-null assumptions.

### CLI and editor behavior

- `nlc check` reports semantic nullability diagnostics in stable JSON.
- `nlc lint` reports migration/style diagnostics; it must consume semantic type/null-state data instead of re-inferring from syntax.
- `nlc fix --code NL034` applies safe/review-needed nullable idiom fixes.
- `nlc query type --position` includes `nullState` in JSON:

```json
{
  "schemaVersion": "1.0",
  "type": "string",
  "nullable": false,
  "nullState": "NotNull",
  "source": "flow"
}
```

- Hover should show both declared and flow type when they differ: `name: string? (currently string after null check)`.
- Code actions should expose `FixSafety` so VS Code can separate safe quick fixes from migrations.

### C# converter integration

The C# -> N# converter should preserve nullable syntax but rewrite artifacts where safe:

- `x!.Y` -> `(must x).Y`.
- `nullable.HasValue` + `nullable.Value` -> `x is T value` when type is known.
- `return null!` or `= default!` -> preserve as `must default(T?)` only as a last resort and emit `NL039`; better is to generate TODO with constructor/init recommendation.
- C# APIs returning `ActionResult<T>`/`IResult` with `NotFound()` branches should not become unions automatically; emit a suggestion comment or diagnostic.

---

## Implementation tasks

### Task 1: Add nullable flow-state data structures

**Objective:** Give the analyzer a single model for declared type, flow type, and null-state.

**Files:**
- Modify: `src/NSharpLang.Compiler/Analyzer.cs`
- Modify: `src/NSharpLang.Compiler/TypeSystem/TypeInfo.cs`
- Test: `tests/AnalyzerTests.cs`

**Steps:**
1. Add `NullState` enum: `Unknown`, `Null`, `MaybeNull`, `NotNull`, `Oblivious`.
2. Add a `FlowType`/`FlowFacts` structure keyed by symbol and stable member path.
3. Record expression null-state in `SemanticModel` alongside existing expression types.
4. Add tests for `string?` parameter dereference before any narrowing.
5. Run `dotnet test --filter AnalyzerTests`.

**Acceptance criteria:**
- Analyzer can distinguish declared `string?` from flow-proven `string`.
- Existing nullable assignment compatibility keeps working.
- No new null diagnostics are emitted yet except test-only plumbing if needed.

### Task 2: Implement direct null-check narrowing

**Objective:** Make simple guards remove false-positive nullable dereference warnings.

**Files:**
- Modify: `src/NSharpLang.Compiler/Analyzer.cs`
- Test: `tests/AnalyzerTests.cs`

**Steps:**
1. Detect `x != null`, `x == null`, and reversed forms in `if` conditions.
2. Apply true/false branch facts.
3. Preserve facts after early return/throw branches.
4. Invalidate facts on assignment.
5. Add tests for if/else, early return, and assignment invalidation.

**Acceptance criteria:**
- `if x == null { return } x.Length` is accepted.
- `x = null` after narrowing makes `x.Length` warn/error again.
- Nested scopes do not leak unsound facts.

### Task 3: Implement nullable dereference and assignment diagnostics

**Objective:** Enforce `T?` versus `T` at the places users feel it.

**Files:**
- Modify: `src/NSharpLang.Compiler/Analyzer.cs`
- Modify: `src/NSharpLang.Compiler/ErrorReporting.cs` if compiler error codes are used
- Modify: `src/NSharpLang.Compiler/Linter.cs` only if diagnostics remain lint-level
- Test: `tests/AnalyzerTests.cs`

**Steps:**
1. Emit `NL030` for member/index/call receiver with `MaybeNull`.
2. Emit `NL031` for assignment/argument/return from `T?` to `T` without proof.
3. Add project-mode hooks later; default to warning for deref and error for assignment.
4. Add Elm-style suggestions: `use ?.`, `use ??`, add null check, or `must` if intentional.
5. Verify JSON diagnostics include code, severity, location, and suggestion.

**Acceptance criteria:**
- `name: string? = null; print name.Length` reports `NL030`.
- `name: string = maybeName` reports `NL031`.
- `print name?.Length ?? 0` is accepted.

### Task 4: Parse and lower `must`

**Objective:** Replace C# null-forgiving artifacts with an explicit N# assertion expression.

**Files:**
- Modify: `src/NSharpLang.Compiler/Lexer.cs`
- Modify: `src/NSharpLang.Compiler/Parser.cs`
- Modify: `src/NSharpLang.Compiler/Ast/Expressions.cs`
- Modify: `src/NSharpLang.Compiler/Transpiler.cs`
- Modify: `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- Test: `tests/ParserTests.cs`, `tests/TranspilerTests.cs`, relevant IL tests

**Steps:**
1. Add `must` keyword/token.
2. Add `MustExpression(Expression Value, string? Message, ...)` AST node.
3. Parse `must expr` at unary precedence, same family as `await`.
4. Optionally parse `must expr else "message"`.
5. Analyze `must T? -> T`; report redundant `must` on proven non-null.
6. Lower to `expr ?? throw new NullReferenceException(message)` in C# export and equivalent IL branch/throw.

**Acceptance criteria:**
- `user := must FindUser(id)` type-checks as non-null `User`.
- `(must user).Name` emits valid C# and IL.
- `must nonNullable` reports `NL033`.

### Task 5: Add nullable value idiom diagnostics and fixes

**Objective:** Migrate `.HasValue/.Value` toward N# pattern style without breaking .NET interop.

**Files:**
- Modify: `src/NSharpLang.Compiler/Analyzer.cs`
- Modify: `src/NSharpLang.Compiler/Linter.cs`
- Modify: `src/NSharpLang.Compiler/CodeFix.cs`
- Test: `tests/LinterTests.cs`, `tests/CodeFixTests.cs`

**Steps:**
1. Recognize `Nullable<T>.HasValue` and `.Value` on `T?` value types.
2. Report `NL034` for guard/value pairs.
3. Report `NL035` for unguarded `.Value`.
4. Add code action: `if x.HasValue { use x.Value }` -> `if x is T value { use value }`.
5. Add code action: bare `x.Value` -> `must x` with `ReviewNeeded` safety.

**Acceptance criteria:**
- Guarded `.Value` does not report unsafe access but does suggest pattern style.
- Unguarded `.Value` reports unsafe access.
- Fix application preserves indentation and passes parser round-trip.

### Task 6: Add match/null exhaustiveness and narrowing

**Objective:** Make `match` the natural way to consume nullable values and mixed domain outcomes.

**Files:**
- Modify: `src/NSharpLang.Compiler/Analyzer.cs`
- Test: `tests/AnalyzerTests.cs`, `tests/PatternMatchingTests.cs`

**Steps:**
1. Treat `T?` as a two-space pattern domain: `null` and `T`.
2. Bind catch-all identifiers after a `null` arm as `T`.
3. Flag unreachable `null` arms after catch-all.
4. Ensure guarded arms do not count as full null coverage unless a later unguarded arm covers it.
5. Add tests for reference and value nullable matches.

**Acceptance criteria:**
- `match name { null => "", n => n.Trim() }` is accepted with `n: string`.
- Missing null coverage in expression contexts reports a helpful exhaustiveness error/warning.
- Existing union exhaustiveness behavior remains intact.

### Task 7: Import and emit C# nullable metadata

**Objective:** Make interop nullability precise enough that N# users trust .NET API calls.

**Files:**
- Modify: `src/NSharpLang.Compiler/TypeSystem/ReflectionTypeInfo.cs` or related reflection type files
- Modify: `src/NSharpLang.Compiler/Analyzer.cs`
- Modify: `src/NSharpLang.Compiler/Transpiler.cs`
- Test: C# interop tests under `tests/NSharpLang.CSharpInteropTests`

**Steps:**
1. Decode `NullableAttribute` and `NullableContextAttribute` from reflected members.
2. Map annotated reference return/parameter/property types to `T` or `T?`.
3. Mark missing metadata as `Oblivious` and emit `NL037` at boundaries in warn mode.
4. Decode common flow attributes: `MaybeNull`, `NotNull`, `NotNullWhen`, `DoesNotReturn`.
5. Emit `#nullable enable` and nullable syntax in generated public C#.

**Acceptance criteria:**
- Calling a C# `string? GetName()` returns N# `string?`.
- Calling a C# `string GetName()` in nullable-enabled context returns N# `string`.
- `TryGet(..., [NotNullWhen(true)] out value)` narrows `value` inside the true branch.

### Task 8: Add migration artifact lints/code fixes

**Objective:** Turn C# migration artifacts into actionable migration guidance.

**Files:**
- Modify: `src/NSharpLang.Compiler/Parser.cs` if C# artifact syntax is accepted during migration cleanup
- Modify: `src/NSharpLang.Compiler/Linter.cs`
- Modify: `src/NSharpLang.Compiler/CodeFix.cs`
- Test: `tests/LinterTests.cs`, `tests/CodeFixTests.cs`

**Steps:**
1. Detect `null!`, `default!`, and `x!.Y` if the parser/converter sees them.
2. Report `NL038` for null-forgiving use-site assertions.
3. Report `NL039` for fake initialization (`null!`/`default!`).
4. Fix `x!.Y` to `(must x).Y`.
5. For fake field initialization, offer constructor/init/property-nullability suggestions but do not auto-apply unless trivially safe.

**Acceptance criteria:**
- C# converted code does not silently preserve `!` artifacts as if they were idiomatic N#.
- Every artifact diagnostic includes one concrete next action.
- Safe fixes are idempotent.

### Task 9: Add null-sentinel branch suggestions

**Objective:** Encourage unions/match when null is hiding domain outcomes.

**Files:**
- Modify: `src/NSharpLang.Compiler/Linter.cs`
- Modify: `src/NSharpLang.Compiler/CodeFix.cs`
- Test: `tests/LinterTests.cs`, `tests/CodeFixTests.cs`

**Steps:**
1. Detect `if x == null { return NotFound(...) }` and similar sentinel branches.
2. Report `NL036` as info with examples, not a warning.
3. Offer a `SuggestionOnly` action to generate a union skeleton plus match rewrite preview.
4. Avoid reporting for simple `return null`, `return fallback`, or low-level cache lookups.

**Acceptance criteria:**
- ASP.NET-style `NotFound()` branches get a suggestion.
- Simple null coalesce code is not nagged.
- Generated union skeleton names are reasonable but marked review-only.

### Task 10: Expose null-state through CLI/LSP

**Objective:** Make nullability visible to humans and LLMs, not just enforced by diagnostics.

**Files:**
- Modify: `src/NSharpLang.Compiler/CodeIntelligence/*`
- Modify: `src/NSharpLang.Cli/Commands/*Query*` or relevant query command files
- Modify: language server hover/code-action handlers if present
- Test: `tests/CliCommandTests.cs`, LSP tests if present

**Steps:**
1. Extend type query JSON with `nullable` and `nullState`.
2. Add hover text showing flow narrowing.
3. Add code actions for NL030/NL031/NL033/NL034/NL035/NL038/NL039.
4. Keep schema version discipline: add fields in a compatible way or bump schema if required.
5. Visually verify VS Code if LSP files change.

**Acceptance criteria:**
- `nlc query type` can prove a narrowed variable is currently non-null.
- VS Code code actions distinguish safe fixes from review-needed migrations.
- Existing JSON contract tests are updated intentionally.

---

## Examples to use as golden tests

### Early-return narrowing

```n#
func Email(user: User?): string {
    if user == null {
        return "missing"
    }

    return user.Email
}
```

Expected: no nullable dereference diagnostic on `user.Email`.

### Boolean narrowing

```n#
func SendIfReady(user: User?) {
    if user != null && user.Email != null {
        Send(user.Email)
    }
}
```

Expected: `user: User`, `user.Email: string` inside the block.

### Match nullable

```n#
label := match maybeCount {
    null => "none",
    count => $"count: {count}"
}
```

Expected: `count: int` in second arm.

### Explicit assertion

```n#
user := must repo.Find(id) else $"user {id} disappeared after validation"
return user.Email
```

Expected: `user: User`; generated C# throws if null.

### C# nullable metadata

```csharp
public string? FindName(int id) => null;
public bool TryFind(int id, [NotNullWhen(true)] out User? user) { ... }
```

```n#
name := External.FindName(1)
// name: string?

if External.TryFind(1, out user) {
    print user.Email
}
```

Expected: `name` maybe-null; `user` non-null in true branch.

### Migration artifact

```csharp
var city = user!.Address!.City;
```

Converted N#:

```n#
city := (must (must user).Address).City
```

Expected: accepted but linted if a cleaner guard/match is nearby.

---

## Acceptance criteria for the full initiative

- At least 30 analyzer tests cover null-state transitions, narrowing, invalidation, match arms, nullable value types, and C# metadata import.
- At least 15 linter/code-fix tests cover migration artifacts and safe/review-needed fixes.
- `nlc check` reports possible null dereferences with actionable suggestions.
- `nlc fix` can mechanically replace `x!.Y` and common `.HasValue/.Value` patterns.
- `nlc query type` exposes `nullState` for LLM/tooling consumers.
- Generated C# has `#nullable enable` and preserves N# public nullability for C# callers.
- Documentation is updated in `docs/DESIGN.md`, `memory/features/type-system.md`, `memory/features/interop.md`, and website guide pages after implementation.
- Full verification uses `./scripts/test-all.sh` before committing implementation work.

## Adversarial review note

Codex adversarial review was attempted per repo guidance, using this plan plus `docs/DESIGN.md`, type-system/interop/analyzer/parser memory docs, `Linter.cs`, and `CodeFix.cs` as context. The Codex CLI is installed, but the review failed with `401 Unauthorized: Missing bearer or basic authentication in header` against the OpenAI Responses API. The intended review prompt focused on language design correctness, migration ergonomics, C# interop, implementation sequencing, and over/under-engineering. Because this is a design deliverable rather than code, the plan below includes its own risks/mitigations and should still receive a fresh Codex review once auth is fixed before implementation starts.

## Risks and mitigations

- Risk: flow analysis becomes unsound for mutable member paths.
  - Mitigation: first release narrows locals/parameters and stable readonly paths only.
- Risk: `must` becomes the new `!` spam.
  - Mitigation: lint redundant `must`, prefer guard/coalesce suggestions first, expose counts in migration reports.
- Risk: C# nullable metadata reflection is subtle and easy to get wrong.
  - Mitigation: build focused fixture assemblies with nullable enabled/disabled contexts and attribute-heavy APIs.
- Risk: `Result`/union suggestions become noisy.
  - Mitigation: keep NL036 info-level, sentinel-specific, and review-only.
- Risk: adding diagnostics in the linter without semantic facts repeats current weak-flow problem.
  - Mitigation: semantic null-state must live in analyzer/SemanticModel; linter consumes it.

## Sequencing

P0:
1. Flow-state model.
2. Direct null-check narrowing.
3. Dereference/assignment diagnostics.
4. `must` syntax/lowering.

P1:
5. Nullable value idioms.
6. Match/null narrowing.
7. C# nullable metadata import/emit.

P2:
8. Migration artifact fixes.
9. Null-sentinel branch suggestions.
10. CLI/LSP null-state surfacing.

Ship P0 behind a project option if needed, but do not ship `must` without at least direct null-check narrowing; otherwise users will cargo-cult assertions instead of writing normal guarded code.
