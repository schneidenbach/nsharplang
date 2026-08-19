# Testing

## Test Suite

**Total Tests:** Do not hard-code counts here. Run `dotnet test tests/Tests.csproj` for the current unit count and `./scripts/test-all.sh` for the full product gate.

## Test Organization

### By Component
- Lexer coverage
- Parser coverage
- Analyzer coverage
- Integration coverage

### Test Files
```
tests/
├── ParserTests.cs               - Parsing tests
├── AnalyzerTests.cs             - Type checking tests
├── AnalyzerSemanticModelTests.cs - Semantic model tests
├── IntegrationTests.cs          - End-to-end pipeline tests
├── LanguageServerTests.cs       - LSP handler tests (completion, hover, definition, rename)
├── CodeIntelligenceTests.cs     - the one culture-walled OutputFormatter case (see below)
└── QueryIntegrationTests.cs     - CLI toolchain integration tests (uses real example projects)
```

Tokenization has no C# assertion layer: the lexer's canonical contracts are N#, in
`src/NSharpLang.Compiler.BootstrapServices/Lexer.tests.nl`, and they run in the BootstrapServices
estate rather than in `tests/Tests.csproj`. See `memory/components/lexer.md`.

Linting has no C# assertion layer either. The linter's canonical contracts are N# and live beside
their subjects in the same estate: `Linter.tests.nl` (the declaration walk, and the end-to-end rule
contracts for NL001/NL002/NL003/NL004/NL006/NL010/NL011/NL012/NL016/NL020, suppression and resolved
spans), `DiagnosticCatalog.tests.nl` (all 99 descriptors), `LinterConfig.tests.nl` (severities,
overrides and `.editorconfig`) and `LinterBindingUsageCore.tests.nl` (the unused-binding policy).
Formatting has no C# assertion layer either. The formatter's canonical contracts are N# and live
beside their subjects in the same estate: `Formatter.tests.nl` (the nineteen declaration arms, one
at a time, against hand-built AST nodes, plus the two `FormatSafe` gates), `FormatterWalk.tests.nl`,
`FormatterWalkState.tests.nl` and `FormatterSyntaxText.tests.nl` (the body walk, the state carrier
and the leaf text), `FormatterSourceText.tests.nl` (the front door — source text in, canonical
source text out, with idempotence and the reparse round trip) and `FormatterConfig.tests.nl`
(`FormatterConfig`, `.editorconfig` reading and the `FormatterConfigKernels` int parser).

Four more subjects moved out of `tests/Tests.csproj` in 020 slice 12 and now have no C# assertion
layer at all. `NullabilityMetadataCore.tests.nl` states the CLR↔N# built-in maps as one sixteen-row
table read two ways, the 3 × 3 nullability wrapping table, and the reference-nullability eligibility
partition, beside `NullabilityTypeDisplay`'s sixteen display arms. `StringLiteralDecoder.tests.nl`
crosses all eleven escapes through the scalar seam and pins the divergence between the strict and
tolerant decoders. `OutputFormatterDiagnosticClusterKernels.tests.nl` states the diagnostic-cluster
triage layer — both tiers of the category classifier, all nine source constructs, the message
pattern, the cluster id and the escaped next command — with the serialised payload beside the other
envelopes in `OutputFormatterJsonKernels.tests.nl`. The local-function parser arms are whole-tree
goldens in `ColumnarParserAst.tests.nl`, and the four `ColumnarCompiler.TryEmitProgram` cases are
real source shapes in `tests/native/columnar-emit-facts`.

Run them with `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false`
(restore with `-p:NSharpExcludeTests=false --force-evaluate` first).

## Testing Strategy

### 1. No Mocks
Tests use real components, not mocks. This ensures:
- Real-world behavior validation
- Integration coverage where feasible
- Simpler test code

### 2. Focused Tests
Each test validates one specific feature:
```text
[Fact]
public void TestVariableDeclaration()
{
    var source = "let x := 42";
    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var ast = parser.ParseCompilationUnit();

    var stmt = ast.Statements[0] as VariableDeclarationStatement;
    Assert.NotNull(stmt);
    Assert.Equal("x", stmt.Name);
}
```

### 3. End-to-End Validation
Integration tests validate full pipeline:
```text
[Fact]
public void TestFullCompilation()
{
    var source = "let x := 42";

    // Lex
    var tokens = new Lexer(source, "test").Tokenize();

    // Parse
    var ast = new Parser(tokens, "test").ParseCompilationUnit();

    // Analyze
    var result = new Analyzer().Analyze(ast, "test", "/");
    Assert.Empty(result.Errors);

    // Compile/analyze through the current backend under test
    Assert.Empty(result.Errors);
}
```

### 4. Emitted Assemblies Load Into Collectible Scopes
Tests that reflect over or invoke an emitted assembly (columnar parity programs, compiled
BootstrapServices or CLI outputs, `MultiFileCompiler` outputs) must load it through `CollectibleAssemblyScope`
(tests/CollectibleAssemblyScope.cs):

```text
using var loadScope = CollectibleAssemblyScope.Load(asm!);                  // emitted byte[]
using var loadScope = CollectibleAssemblyScope.LoadFromFile(outputPath);    // emitted .dll
var type = loadScope.Assembly.GetType(typeName!)!;
```

Never `Assembly.Load(bytes)` or `Assembly.LoadFile(path)`: each call pins the assembly in a fresh
NON-collectible AssemblyLoadContext for the test host's lifetime. The parity suite loads hundreds of
emitted assemblies per run and grows every slice — the pinned pile intermittently OOM-crashed the
xUnit host ("Test host process crashed : Out of memory").

Rules of the scope:
- Keep every `Type`/`MethodInfo`/delegate obtained from `loadScope.Assembly` inside the `using` scope.
- `CollectibleAssemblyScopeTests` pins the contract (collectible, non-default, reclaimable after Dispose).
- The compiler side holds the matching guarantee: external-type/doc resolution enumerates loaded
  assemblies through the N# `ExternalAssemblyScan.Loaded()` owner
  (`src/NSharpLang.Compiler.BootstrapServices/ExternalAssemblyScan.nl`),
  which skips dynamic and collectible assemblies — so a briefly-loaded emitted assembly can no longer
  hijack a concurrent in-process compile's bare-name lookup (the "MemoryCopy not found on type Buffer"
  flake). Never resolve external types via a raw `AppDomain.CurrentDomain.GetAssemblies()` scan.

### 5. The Product Gate Skips Steps With Unchanged Inputs
Within a plain fresh isolated `./scripts/test-all.sh` development run, a gate step is skipped when
its ENTIRE input set is byte-identical to inputs that previously PASSED that step on the same
toolchain and environment (validated per-step cache in `tests/scripts/test-all-core.sh`; markers
written only on success). Input sets are over-inclusive — `src/**` and the gate scripts invalidate
everything, and UNIT includes `docs/` and `website/docs/` wholesale because unit tests
golden-compare and parity-check repo documentation (cli-reference.md, the diagnostic-clusters
sample, the systems audit). Step keys are also salted with the behavior-changing environment (the
same env_names as the whole-gate signature, including `NSHARP_EXPERIMENTAL_SOA`) and the installed
dotnet-ilverify tool version. Practical effect for local development: docs-only changes re-run unit
tests (~1m36s) but still skip benchmarks, interop, and the example chain; tests-only changes skip
benchmarks and the example chain. Do NOT "optimize" docs changes back out of UNIT — that exact gap
let a red docs-parity test pass the step cache during finding F9. `--commit`, `--release`,
`--fresh`, `--no-cache`, and `--clean` disable skipping and run every step. The isolated run always unsets
`NSHARP_UPDATE_DIAGNOSTIC_GOLDENS` (golden regeneration inside the discarded copy is
self-satisfying); regenerate goldens with plain `dotnet test` in the working tree. When adding a
gate step, pointing one at new input paths, or making a test read a new repo file, update the
input-set prefixes next to the step wrappers in test-all-core.sh —
`tests/GateStepInputSetGuardTests.cs` enforces coverage of repo files tests read, the env-list
sync between the two scripts, and the hash-step behavior itself.

### 7. Gate Profiling And Slicing Guidance
Current gate profiling must be refreshed after the removal of the old
wall-clock benchmark lane. Use a fresh `VSCODE_TESTS=skip ./scripts/test-all.sh
--commit` run when updating this section.

Per-test TRX profiling from the same pass showed the unit bucket is dominated by
SDK/toolchain subprocess tests and a few full IL execution cases. Those sums
exceed wall time because xUnit runs collections concurrently; the critical path
is still the slow `dotnet build`/`dotnet test` subprocess tests.

Do not pay the full gate during normal edit loops. Use:

```bash
./scripts/dev.sh --since
./scripts/dev.sh Columnar
./scripts/dev.sh 'FullyQualifiedName~SomeTest&Category!=Slow'
```

`dev.sh --since` is intentionally fail-safe: central compiler, SDK/runtime,
build, fixture, or unmapped changes run the full unit suite rather than silently
narrowing. For backend-only commit verification, the required final command is
still:

```bash
VSCODE_TESTS=skip ./scripts/test-all.sh --commit
```

The full gate avoids one known duplicate-work trap: Step 8/9 build the
example/fixture surface, then Step 10b passes the exact emitted assemblies to
`scripts/ilverify.sh --built-dirs-file` and adds `--build-native-tests` for the
selected direct-call, construction/array, and erased-enum regression assemblies.
The built-dirs mode never rebuilds examples or fixtures. Copied package and DLL
runtime assets remain verifier references rather than being mistaken for N#
outputs. Standalone `scripts/ilverify.sh` and CI build the product surface and
selected native regression assemblies themselves before verification.

## Test Categories

### Lexer Tests
- Keyword recognition
- Operator tokenization
- String interpolation
- Numeric literals
- Comments
- Error handling

### Parser Tests
- Statement parsing (if, for, while, etc.)
- Expression parsing (binary, unary, calls, etc.)
- Declaration parsing (class, func, record, etc.)
- Operator precedence
- Pattern parsing
- Error recovery

### Analyzer Tests
- Type inference
- Type checking
- Name resolution
- Scope management
- External type resolution
- Pattern exhaustiveness
- Definite assignment
- Duck interface validation
- Error detection

### Language Server Tests
- Completion (member access, namespace, N# types)
- Hover (type info display)
- Go-to-definition
- Rename (with interpolation awareness)
- FindAllReferences
- Headless VS Code extension-host smoke tests live under `editors/vscode/src/test`
- `./scripts/test-vscode-headless.sh` builds the release server, launches VS Code in extension-host mode, exercises diagnostics/completions/hover/definition/references/code actions, and writes `.context/vscode-headless-report.json`; the implementation lives under `tests/scripts/`

### Code Intelligence Tests (CLI Toolchain)
- **QueryIntegrationTests** — runs against REAL example projects:
  - `examples/01-hello-world` — single file, functions, variables
  - `examples/06-classes-and-records` — records, members, methods
  - `examples/12-multi-file-projects/MultiFileProject` — cross-file imports, namespaces
  - `examples/05-unions` — unions, error handling
- Tests: symbols, outline, diagnostics, definition (by name + line assertions), references (cross-file), completions (member access + identifier), BindingMap, JSON schema, unhappy paths
- **CodeIntelligenceTests** — one case only: the unknown-severity invariant fallback, which is
  non-vacuous only under a Turkish ambient culture and therefore cannot move (N# reaches
  `CultureInfo` in neither direction). The other 44 cases are N# contracts in the BootstrapServices
  estate — `OutputFormatterJsonKernels.tests.nl` (the versioned JSON envelopes and their exact root
  keys), `OutputFormatterTextBuilders.tests.nl` (every `--text` answer, stated as whole texts) and
  `OutputFormatterDiagnosticKernels.tests.nl` (severity arithmetic, reference deduplication, and the
  two end-to-end `CodeIntelligenceQueries.Diagnostics` contracts)
- **Completion engine** has no C# assertion layer: `CompletionEngine`'s contracts are N# in
  `tests/native/completion-engine`, a native project that drives the production `CompletionEngine`
  and `CodeIntelligenceService.LoadProject` BY REFLECTION — the route `tests/native/query-completions`
  established, and the only one available, because the engine's inputs need the C# `Analyzer` that
  lives in the assembly which DEPENDS on BootstrapServices
- **Error reporting** has no C# assertion layer: the diagnostic record, the suggestion tables and the
  Elm-style builders are stated in N#, beside their subjects in the same estate —
  `CompilerError.tests.nl` (the rust-style, tooling and MSBuild renderers as WHOLE texts, the
  diagnostic-id derivation and its override, the seven-heading Elm severity table, the inline-text
  folder), `ErrorSuggestions.tests.nl` (the whole code-to-suggestion table, the typo probe and the
  Levenshtein kernel), `ErrorSuggestionHelpers.tests.nl` (`SmartSuggester`'s RANKED answers and
  `TypeConversionSuggester`'s ordered rule table) and `ErrorMessageBuilder.tests.nl` (the docs-URL
  table, the similar-names switch and the three list renderers)
- **Code fixes** have no C# assertion layer: `CodeFixService`, its six providers and
  `CodeFixActionHelpers` are stated in `CodeFix.tests.nl` in the same estate, where every edit is
  proved by APPLYING it through `FixApplicatorCore.ApplyEdits` and re-parsing the result
- **The fix applicator** has no C# assertion layer: the four owners are stated one file each in the
  same estate — `FixApplicatorCore.tests.nl` (applied source as WHOLE text, and every rejection as
  its whole message rather than a substring, so the blamed edit is named),
  `FixApplicatorTextEditOrderer.tests.nl` (each of the five ordering keys in isolation plus a
  200-list differential sweep against an independently written oracle, over an N#-owned generator
  because `System.Random` cannot be constructed in this estate),
  `FixApplicatorValidationMessages.tests.nl` (the five rejection sentences and the index clamp) and
  `FixApplicatorEditEngine.tests.nl` (the raw return codes, the error slots, the three line-ending
  arms and the malformed-call guard)
- **The unused-binding rules** are stated end to end in `Linter.tests.nl`, where every "this
  variable is NOT reported" claim carries a control — the same source with the read removed, or with
  an unused sibling added — so a linter that reported nothing could not pass. This replaced a C#
  file in which seventeen of nineteen negative cases ran against an entirely empty diagnostic list
- **The top-25 diagnostic golden suite** has no C# assertion layer: `DiagnosticGoldenSuite.tests.nl`
  holds the curated corpus and pins it against `tests/fixtures/diagnostics/`, calling
  `OutputFormatterTextBuilders.DiagnosticsToText` directly instead of through the C# `OutputFormatter`
  forwarder. **It also records that the suite is misnamed: it holds TWENTY-FOUR diagnostics.** The
  fixtures stay covered by the validated per-step cache without a gate-script change, because the
  `native-nsharp-tests` step is keyed on `UNIT_INPUTS_HASH` and the UNIT input set already covers
  `tests/` wholesale
- **`project.yml`** has no C# assertion layer: the four owners are stated one file each in the same
  estate — `ProjectFileParser.tests.nl` (whole documents in, every field read back, and all NINE
  validation refusals plus the four `FileNotFoundException` sentences as whole messages, where the
  deleted C# reached three refusals and produced no file-not-found at all),
  `ProjectConfigModels.tests.nl` (the defaults and the source walk, with all TWELVE skipped
  directory names one at a time plus four kept neighbours as controls),
  `ProjectSourceFileFilter.tests.nl` (the glob engine arm by arm — and it records that `**/name`
  does NOT match a root-level `name/`, unlike MSBuild) and `Reference.tests.nl` (the four kinds,
  their precedence, and `Validate`, which had no direct coverage at all). `AssemblyVersionUtilities
  .tests.nl` states the package-version kernel as a TABLE rather than as a differential sweep
  against `int.TryParse`, because `CultureInfo` cannot be reached from this estate in either
  direction
- **The shipped `examples/` corpus** has no C# assertion layer: `ExampleProjectCorpus.tests.nl`
  walks all nineteen example projects through the compiler's OWN discovery
  (`MultiFileCompilerInputBuilder.BuildFromProject`), parser and linter, pinning each project's file
  count, zero parse errors and an empty lint census. **It REQUIRES every directory to exist**,
  which the deleted C# theories did not — each opened with `if (!Directory.Exists(…)) return;`. One
  of the nineteen, `11-advanced-features`, is covered by nothing else in the repository: the gate's
  Step 10a keeps a directory only when it has a `project.yml` or a top-level `.nl` file, and that
  one has neither. The remaining half of `nlc check` (semantic analysis and IL emission) stays with
  Step 10a, which runs the real binary over a superset of these directories

### Known Testing Limitation
Raw filtered `dotnet test --filter` invocations can hang in this project because of the
assembly-loading test topology. Use `./scripts/dev.sh <pattern>` for focused work and plain
`dotnet test tests/Tests.csproj` for the full unit suite.

## Running Tests

### All Tests
```bash
dotnet test tests/Tests.csproj
```

### Specific Test Class
```bash
./scripts/dev.sh ParserTests
```

### Specific Test Method
```bash
./scripts/dev.sh TestVariableDeclaration
```

### With Detailed Output
```bash
dotnet test -v detailed
```

## Test Examples

### Example 1: Lexer Test
```text
[Fact]
public void TestStringInterpolation()
{
    var source = "$\"Hello {name}\"";
    var lexer = new Lexer(source, "test");
    var tokens = lexer.Tokenize();

    Assert.Single(tokens);
    Assert.Equal(TokenType.StringLiteral, tokens[0].Type);
    Assert.Equal("$\"Hello {name}\"", tokens[0].Value);
}
```

### Example 2: Parser Test
```text
[Fact]
public void TestMatchExpression()
{
    var source = "result := match value { 0 => \"zero\", _ => \"other\" }";
    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var ast = parser.ParseCompilationUnit();

    var stmt = ast.Statements[0] as VariableDeclarationStatement;
    var match = stmt.Initializer as MatchExpression;
    Assert.NotNull(match);
    Assert.Equal(2, match.Cases.Count);
}
```

### Example 3: Analyzer Test
```text
[Fact]
public void TestTypeMismatchError()
{
    var source = "let x: int = \"hello\"";
    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();
    var result = new Analyzer().Analyze(ast, "test", "/");

    Assert.NotEmpty(result.Errors);
    Assert.Contains("Type mismatch", result.Errors[0].Message);
}
```

## Test Coverage

### Features Tested
- ✅ All statement types
- ✅ All expression types
- ✅ All declaration types
- ✅ Type inference
- ✅ Type checking
- ✅ Pattern matching
- ✅ External types
- ✅ Duck interfaces
- ✅ Unions and enums
- ✅ Async/await
- ✅ Iterators
- ✅ Error handling
- ✅ String interpolation
- ✅ Operator overloading
- ✅ Conversion operators
- ✅ Params collections
- ✅ List patterns
- ✅ And much more...

## N# Test Files (.tests.nl)

N# native tests use top-level `test` declarations and `assert` statements:

```
// example.tests.nl
namespace Example

test "adds two values" {
    result := Add(2, 3)
    assert result == 5
}
```

Run with:
```bash
nlc test --project <project-directory>
```

Table-driven tests are live too, and each ROW is an independent test:

```
test "adds" with (a: int, b: int, sum: int) [
    (1, 2, 3),
    (2, 3, 5)
] {
    assert a + b == sum
}
```

N# lowers every row into its own test declaration before emit — the row's values are bound as typed
locals of the declared parameter types — so each row emits its own method and reports under its own
name, `adds (1, 2, 3)`. Row values must be literals (`NL310` otherwise), and a row's value count
must match the parameter count (`NL202` otherwise).

`skip`, `setup` and `teardown` parse and are understood by the editor tooling, but `nlc test` still
refuses a file containing one — `skip` at emit (`parse.declaration-scan`), `setup` earlier still, in
the analyser (see the table below). Do not rely on them yet.

**Which runner capability comes next is decided by MEASURED demand, not by the task file's order.**
The close-out contract forbids shipping runner infrastructure with no consumer, so before building
one, sweep the C# test estate for tests that actually need it. The sweep taken at
`tests/native/parser-literal-facts`'s slice, over **2,818 attributed test methods in 279 classes**:

| capability | C# tests that need it | measured runner state (probed against a freshly built tip CLI) |
|---|---|---|
| table-driven cases | shipped, consumed twice | live |
| **skip** | **0** — no `[Fact(Skip=…)]`, no `SkipException`, no `[ConditionalFact]`, no trait filters anywhere. The only `Skip=` in the repo is `DockerFactAttribute`, in the Testcontainers `IntegrationTests` project the gate never runs. The 6 `if (!Directory.Exists(…)) return;` guards that used to live in `ExampleLintTests.cs` — the original finding here — **are gone: that file is deleted and its successor `ExampleProjectCorpus.tests.nl` REQUIRES all nineteen example directories, so an absent corpus now fails instead of silently passing** | declines the WHOLE FILE at `parse.declaration-scan`; an **emit-only** gap — parser, analyser, formatter, LSP, runner and JSON envelope all already carry it. **No consumer remains: the last runtime skip emulation in the estate was migrated away rather than expressed** |
| setup/teardown | 3 classes with a real ctor+`IDisposable` pair, all LSP or Docker fixtures | fails EARLIER than skip, in the **analyser**: a `setup { seed := 7 }` binding is not visible to the test body, so `NL001 Variable 'seed' is declared but never read` |
| **async `Task`** | **134** | **ALREADY SERVED.** A plain `test` body may `await`; an assertion that fails after an await FAILS, and an exception thrown inside awaited work is REPORTED with its message (probe: 3 declarations → 1 passed / 2 failed, each named). Only the `async test "…"` DECLARATION form is missing (`NL101`), and no C# test needs it |
| async `ValueTask` | 0 | same path |
| structured failure JSON | — | already in the envelope: `errorMessage` carries the failure text |
| whole-run timeout | **1 cluster, measured in 020 slice 16** — `tests/ParserErrorTests.cs`'s `Parser_MalformedTableDrivenTest_TerminatesWithErrors` bounded each of its three malformed parses with `Task.Run(...)` + `Wait(TimeSpan.FromSeconds(10))`, so a lost no-progress guard in `ParseTestDeclaration` failed FAST instead of hanging the host. That is a PER-PARSE bound inside a test body, not a per-assembly one | the per-assembly flag exists (`nlc test --timeout <duration>`, "Test timeout per assembly"), but **no in-body bound is expressible in the BootstrapServices estate: `Task.Run` declines at `emit.local.initializer`, an inline lambda in its overload set declines at `emit.body`, `System.Diagnostics.Stopwatch` is an unsupported local type, and `Environment.TickCount64` declines at `emit.typed-local.initializer` — all four measured by execution at that slice's tip.** The lambda itself is innocent: bound to an explicit `Func<int>` local it emits and invokes. The three rows migrated with their exact diagnostic censuses; the fail-fast property did not |

**So most of the remaining order is already served or unwanted, and the real remaining work in the
native-runner close-out is MIGRATION, not capability.** Note also that the gate's Step 3a validator
ALREADY accepts skips at `schemaVersion` 1 — it cross-checks `passed + failed + skipped == total` and
`outcome_counts["skipped"] == summary.skipped` — and the runner already maps xUnit's `ITestSkipped`
to a `skipped` outcome with its reason.

### Which native estate a migrated cluster belongs in

Step 3a runs **two** native estates, and they have different capability ceilings. Choose by the
ARGUMENT TYPES the cluster's subject calls take — measured by probe, not assumed:

| the cluster's subject calls take… | estate | why |
|---|---|---|
| `string` / `int` / `bool` / arrays / literals, answering primitives | **`tests/native/<name>/`**, subject reached as a `dll:` dependency, run by the LIVE CLI | tables (`with (…) […]`) are available here, so each row reports as its own test |
| an ENUM member, a CONSTRUCTED object, or anything else the emitter must resolve in the dependency assembly | **`src/NSharpLang.Compiler.BootstrapServices/<Subject>.tests.nl`**, same assembly, compiled by the PINNED toolset | a dependency-assembly enum member declines at `emit.typed-local.initializer` (and `emit.call.static-member-unmodeled` in argument position), and `new <dependency type>(…)` declines at `emit.local.initializer`; in a table row the enum member is refused earlier still, by `NL310` |

The pinned toolset predates table-driven lowering, so the BootstrapServices estate takes plain `test`
declarations with `assert` lines — which is also why its contract count moves by exactly the number
of DECLARATIONS added. Its reported total runs ~22 above a `grep -c '^test "'` census (5,071 vs 5,093
at the `OperatorFacts` slice), so measure the estate with `dotnet test` before and after and diff;
never quote the grep as the contract count.

## Validation cadence

Use the narrowest relevant inner loop while editing:

```bash
./scripts/dev.sh <pattern>
./scripts/dev.sh --since
```

Commit a coherent compiler slice after its focused evidence is green. Do not run the full
product gate between every small backend commit.

At integration checkpoints—before push/handoff, after SDK/runtime/build-script/package changes,
after broad shared compiler changes, or when focused evidence is ambiguous—run a fresh
non-VS-Code product gate:

```bash
VSCODE_TESTS=skip ./scripts/test-all.sh --commit
```

For Language Server, LSP, extension, or other IDE-affecting work, do not skip VS Code tests:

```bash
./scripts/test-all.sh --commit
./scripts/reload-vscode-extension.sh
```

Then use computer-use to verify the behavior in the installed extension and capture screenshots.
`AGENTS.md` is authoritative for the exact gate boundary.

The product-gate entrypoint runs from an isolated temporary copy of the
repository with separate HOME, temp, NuGet, and npm state. Successful isolated
runs write a content-addressed cache manifest that includes source content,
test arguments, selected environment, tool versions, and platform data; when all
of those inputs still match, follow-up invocations validate the manifest and
return the recorded green result quickly. Plain `./scripts/test-all.sh` may use
that cache for development feedback. Integration and release evidence uses
`--commit` (or `--release`) so cached results are not accepted.

The full isolated run:
1. Runs all unit tests (`dotnet test`)
2. Runs compiler-service `.tests.nl` contracts plus every `.tests.nl` project under
   `examples/` and `tests/`; template-native suites join this gate with their N# lowering owners.
   The gate requires a positive executed-test count and reconciles every native JSON outcome
   before it may cache the step, so empty or internally inconsistent runs are failures.
3. Rebuilds the compiler and SDK
4. Installs the latest SDK to local NuGet feed
5. Tests `dotnet new` template creation
6. Builds ALL example projects with `dotnet build`
7. Validates everything works end-to-end

Do not use a cached gate result as integration-checkpoint evidence.

## Continuous Testing

Tests run on:
- Every commit (CI/CD)
- Before releases
- During development (watch mode)

## Test Quality Standards

1. **One assertion per test** (when possible)
2. **Descriptive test names** (TestFeature_Scenario_ExpectedBehavior)
3. **Arrange-Act-Assert pattern**
4. **No test interdependencies**
5. **Fast focused execution** (keep individual facts small; broad integration suites may be slower)
