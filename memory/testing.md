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
├── LexerTests.cs                - Tokenization tests
├── ParserTests.cs               - Parsing tests
├── AnalyzerTests.cs             - Type checking tests
├── AnalyzerSemanticModelTests.cs - Semantic model tests
├── IntegrationTests.cs          - End-to-end pipeline tests
├── LanguageServerTests.cs       - LSP handler tests (completion, hover, definition, rename)
├── LinterTests.cs               - Linter diagnostic tests
├── ErrorReportingTests.cs       - Error formatting tests
├── CodeFixTests.cs              - Code fix provider tests
├── CodeIntelligenceTests.cs     - OutputFormatter unit tests
└── QueryIntegrationTests.cs     - CLI toolchain integration tests (uses real example projects)
```

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
- **CodeIntelligenceTests** — OutputFormatter unit tests (JSON envelope, Elm-style text)
- **CodeFixTests** — CodeFixProviders (auto-import, unused variable removal)

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
./scripts/dev.sh LexerTests
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

Plain tests and assertions are live. Check current product tests and limitations before relying
on richer lifecycle/table/skip forms; those forms are still being closed out.

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
