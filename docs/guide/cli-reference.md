# N# CLI Reference

Updated: 2026-05-26

`nlc` is the N# command-line interface. It is designed to feel familiar to Go and Rust developers:

- Build and run loops are project-first.
- `nlc check`, `nlc fix`, `nlc query`, and `nlc lint` default to structured JSON for automation.
- `nlc format`, `nlc test`, `nlc clean`, and `nlc watch` cover common inner-loop workflows; verify scenario-specific behavior before making release claims.
- `nlc --version` prints the installed version.

## Top-Level Commands

| Command | Purpose | Key Flags | Example |
|---------|---------|-----------|---------|
| `nlc build [file]` | Build a project or single file | `--backend`, `--release`, `--verbose`, `--timings`, `--output` | `nlc build` |
| `nlc run [file]` | Build and run a project or single file | none | `nlc run` |
| `nlc new <name>` | Create a csproj-free N# project scaffold | `--template` (`console`, `library`, `test`, `webapi`) | `nlc new MyApp --template console` |
| `nlc init` | Initialize N# in the current directory | none | `nlc init` |
| `nlc test` | Run `.tests.nl` suites through the xUnit/NUnit-backed N# test runner | `--project`, `--filter`, `--verbose`, `--json` | `nlc test --filter "should add"` |
| `nlc format [files...]` | Format N# source | `--project`, `--check`, `--diff`, `--stdin` | `nlc format --diff` |
| `nlc lint [files...]` | Run static analysis rules | `--project`, `--json`, `--text` | `nlc lint --json` |
| `nlc bench` | Run benchmarks | `--project`, `--json` | `nlc bench` |
| `nlc clean` | Remove local build artifacts | `--project`, `--all` | `nlc clean --all` |
| `nlc watch <check\|build\|test\|lint\|format>` | Re-run a command on file changes | `--project`, `--debounce-ms`, `--max-runs` | `nlc watch check` |
| `nlc doc` | Generate HTML API docs | `--project`, `--output`, `--open`, `--json` | `nlc doc --open` |
| `nlc completion <shell>` | Generate shell completion scripts | `bash`, `zsh`, `fish` | `nlc completion zsh` |
| `nlc check` | Fast parse + analyze without building | `--project`, `--text`, `--json` | `nlc check --text` |
| `nlc fix` | Auto-apply code fixes | `--project`, `--file`, `--dry-run`, `--text`, `--json` | `nlc fix --dry-run` |
| `nlc query <subcommand>` | Code intelligence for humans and tools | global `--project`, `--file`, `--pos`, `--text`, `--json`, `--no-daemon` | `nlc query def --file Program.nl --pos 12:4` |
| `nlc daemon <subcommand>` | Manage the background analysis daemon | `--project` | `nlc daemon status` |
| `nlc add <package>` | Add a NuGet dependency to `project.yml` | package spec | `nlc add Serilog@3.1.0` |
| `nlc tidy` | Identify and remove unused dependencies | `--project` | `nlc tidy` |
| `nlc remove <package>` | Remove a dependency from `project.yml` | package name | `nlc remove Serilog` |
| `nlc update [package]` | Update dependencies | optional package name | `nlc update` |
| `nlc publish` | Publish framework-dependent deployment artifacts | `--project`, `--configuration`, `--output`, current-host `--runtime` | `nlc publish -c Release --output ./dist` |
| `nlc export csharp` | Export N# sources without changing the IL toolchain | `--project`, `--output` | `nlc export csharp --project .` |
| `nlc tree` | Show dependency tree | `--project`, `--depth`, `--json` | `nlc tree --json` |
| `nlc audit` | Check dependencies for known vulnerabilities | `--project` | `nlc audit` |
| `nlc env` | Show environment and toolchain info | `--json` | `nlc env --json` |
| `nlc doctor` | Verify CLI, templates/SDK restore, language server, and VS Code extension availability | `--json`, `--require-vscode`, `--skip-vscode` | `nlc doctor --require-vscode` |
| `nlc restore` | Generate MSBuild compatibility config from `project.yml` | `--project` | `nlc restore` |
| `nlc pack` | Create a NuGet package from `project.yml` metadata | `--project`, `--output` | `nlc pack` |
| `nlc help` | Show top-level CLI help | none | `nlc help` |

## Query Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc query batch --requests <file>` | Execute multiple semantic queries in one response | `nlc query batch --requests requests.json` |
| `nlc query symbols` | List project symbols | `nlc query symbols --kind function` |
| `nlc query outline <file>` | File structure and imports | `nlc query outline Program.nl` |
| `nlc query diagnostics` | Rich diagnostics envelope; add the `--clusters` flag for versioned diagnostic-cluster JSON with `category`, `recipe`, `risk`, `files`, `relatedDiagnostics`, and `nextCommand` | `nlc query diagnostics --clusters` |
| `nlc query type --file <file> --pos <line:col>` | Type at a position | `nlc query type --file Program.nl --pos 5:12` |
| `nlc query inspect --file <file> --pos <line:col>` | Symbol, type, definition, refs, and completions in one call; add `--compact` for token-efficient agent context (`--summary` is kept as an alias) | `nlc query inspect --compact --file Program.nl --pos 5:12` |
| `nlc query definition` | Go-to-definition by position or name | `nlc query definition --name Person` |
| `nlc query def` | Alias for `definition` | `nlc query def --file Program.nl --pos 5:12` |
| `nlc query references` | Find references to a symbol | `nlc query references --file Program.nl --pos 5:12` |
| `nlc query refs` | Alias for `references` | `nlc query refs --file Program.nl --pos 5:12` |
| `nlc query completions` | LLM-optimized completions | `nlc query completions --file Program.nl --pos 5:12` |
| `nlc query doc <query>` | Look up .NET API documentation | `nlc query doc Console.WriteLine` |
| `nlc query hover` | Signature and docs at a position | `nlc query hover --file Program.nl --pos 5:12` |
| `nlc query call-graph` | Callers and callees of a function | `nlc query call-graph --function Main` |
| `nlc query implementors` | Concrete types implementing an interface | `nlc query implementors --name IShape` |
| `nlc query help` | Show query command help | `nlc query help` |

## Browser Playground

The public website ships a WebAssembly-hosted compiler workbench. `/playground` is the free-form sample explorer with Monaco syntax highlighting, diagnostics, formatting, completions, hover, file tabs, share links, and browser-subset `Run` output. `/tutorial` uses the same workbench for a guided story with gated exercises.

Browser `Run` intentionally supports tutorial-scale code only: functions, `print`, simple control flow, records/classes, object initializers, selected string/numeric helpers, and selected match patterns. Local `nlc` remains the toolchain for full CLR execution, build, test execution, NuGet restore, filesystem workflows, and editor integration.

## Examples

```bash
# Build and run
nlc build
nlc run

# Tight development loop
nlc check
nlc fix --dry-run
nlc format --check
nlc test --filter "should add"

# Watch mode
nlc watch check
nlc watch test --filter "should add"

# Installation verification
nlc doctor
nlc doctor --json --require-vscode

# Documentation and automation
nlc doc --json
nlc export csharp --project . --output ./myapp-csharp
nlc query inspect --compact --file Program.nl --pos 42:7

nlc completion bash > /etc/bash_completion.d/nlc
```

## Build, Test, And Publish Truth

- `nlc build --release` selects the Release configuration and `bin/Release/<targetFramework>` output layout unless `--output` is provided. The direct IL backend does not have a separate optimization mode yet.
- `nlc test --coverage` and `nlc test --coverage-report` are unavailable in the native test runner today. They exit 1 with a clear text error, or with the same message in the schemaVersion 1 JSON `error` field when `--json` is present.
- `nlc publish` produces framework-dependent artifacts. Without `--runtime`, run the output with `dotnet <assembly>.dll` on a compatible .NET installation.
- `nlc publish --runtime <rid>` is supported only when `<rid>` is the current host runtime. It adds a small framework-dependent launcher beside the `.dll`.
- Cross-runtime publish requests fail before building and report both the requested RID and the current host RID.
- `nlc publish --self-contained` is planned, not implemented. It exits 1 with guidance instead of producing an artifact that only appears self-contained.


## Exit Codes

| Command Group | `0` | `1` |
|---------------|-----|-----|
| `build`, `run`, `new`, `clean`, `watch`, `doc`, `completion` | Success | Failure |
| `test` | Tests passed | Build or test execution failed |
| `format` | Success or already formatted | Formatting failed or `--check` found drift |
| `lint` | No issues | At least one issue was reported |
| `check` | No errors | Errors present or analysis failed |
| `fix` | Success | Failure, or `--dry-run` found pending fixes |
| `query` | Query succeeded | Invalid request, missing symbol, or analysis failure |
| `daemon` | Command succeeded | Daemon operation failed |
| `tree` | Dependency tree emitted | Missing project root/config or dependency resolver failure |
| `doctor` | Required install checks passed | One or more required checks failed |

## JSON Examples

`nlc check`:

```json
{
  "schemaVersion": 1,
  "command": "check",
  "ok": true,
  "projectRoot": "/abs/path/project",
  "checkedFiles": 3,
  "results": [],
  "summary": {
    "errors": 0,
    "warnings": 0,
    "info": 0
  }
}
```

`nlc doc --json`:

```json
{
  "schemaVersion": 1,
  "command": "doc",
  "ok": true,
  "projectRoot": "/abs/path/project",
  "outputDir": "/abs/path/project/nsharp/docs",
  "result": {
    "indexPath": "/abs/path/project/nsharp/docs/index.html",
    "pageCount": 7,
    "pages": [
      {
        "name": "Add",
        "kind": "function",
        "path": "symbols/functionaddprogram.html"
      }
    ]
  }
}
```

`nlc lint --json`:

```json
{
  "schemaVersion": 1,
  "command": "lint",
  "ok": false,
  "projectRoot": "/abs/path/project",
  "lintedFiles": 3,
  "results": [
    {
      "code": "NL001",
      "severity": "warning",
      "message": "Unused variable 'value'",
      "file": "Program.nl",
      "line": 2,
      "column": 5
    }
  ],
  "summary": {
    "errors": 0,
    "warnings": 1,
    "info": 0
  }
}
```

`nlc tree --json`:

```json
{
  "schemaVersion": 2,
  "command": "tree",
  "ok": true,
  "projectRoot": "/abs/path/project",
  "project": {
    "name": "WebApi",
    "targetFramework": "net10.0",
    "source": "project.yml"
  },
  "maxDepth": 2147483647,
  "capabilities": {
    "directDependencies": true,
    "transitiveNuGetDependencies": false
  },
  "dependencies": [
    {
      "name": "Swashbuckle.AspNetCore",
      "kind": "nuget",
      "version": "7.2.0",
      "scope": "runtime",
      "transitive": false,
      "dependencies": []
    }
  ],
  "transitiveDependencies": [],
  "summary": {
    "direct": 1,
    "transitive": 0,
    "total": 1
  },
  "limitations": [
    "project.yml output lists direct runtime dependencies only. Transitive NuGet dependencies require an MSBuild project file so dotnet can resolve the package graph."
  ]
}
```

`nlc tree` is active for csproj-free projects: it reads direct runtime dependencies from `project.yml`. When a minimal MSBuild project file is present and `dotnet list package` succeeds, it also includes transitive NuGet packages; otherwise it still returns direct dependencies with a `limitations[]` note. Tree JSON schema version `2` replaces the earlier raw `packages` wrapper with stable `dependencies`, `transitiveDependencies`, `capabilities`, and `limitations` fields.

## Lint Rules

N# is near-zero-warnings: every active lint rule is a build-blocking **error**. Correctness, safety, and hygiene are enforced; pure style is handled by `nlc format`, not by diagnostics. See `docs/DESIGN.md` → Strictness.

| Code | Severity | Description |
|------|----------|-------------|
| NL001 | error | Unused variable |
| NL002 | error | Missing import |
| NL703 | error | Circular file import; diagnostic includes the import cycle path and a dependency-inversion/shared-file suggestion |
| NL003 | error | Unnecessary null check on value type |
| NL004 | error | Async function without await |
| NL006 | error | Unreachable code |
| NL010 | error | Unused import |
| NL011 | error | Empty catch block |
| NL012 | error | Unused parameter |
| NL016 | error | Redundant null check on an always-non-null expression |
| NL020 | error | Shadowed variable |

Compiler safety diagnostics are likewise build-blocking errors: `NL905` (possible null access, flow-based), `NL903` (visibility convention), `NL904` (obsolete usage), and `NL907` (nullability).

Pure-style rules that used to emit `info`/`warning` diagnostics — `NL005` (use-pattern-matching), `NL008` (camel-case-local), `NL013` (prefer-interpolation), `NL014`/`NL906` (unnecessary-type-annotation), `NL015` (prefer-const), `NL018` (prefer-readonly), `NL019` (empty-block) — have been removed and folded into `nlc format`.

## Inline Lint Suppression

Specific lints can be suppressed on the next line or the current line:

```nsharp
// nlc:ignore NL001
unusedVar := 42
```

This currently applies to CLI lint consumers such as `nlc lint`, `nlc check`, and `nlc fix`.

## Go/Rust Parity Audit

Scoring: `5` means essentially at parity for the workflow, `3` means usable but incomplete, `1` means missing.

### Build & Run

| Feature | Go | Rust | N# Score | Notes |
|---------|----|------|----------|-------|
| Build project | `go build` | `cargo build` | `5` | `nlc build` works for project roots |
| Run project | `go run .` | `cargo run` | `5` | `nlc run` supports project execution |
| Build single file | `go build file.go` | n/a | `5` | `nlc build file.nl` |
| Cross-compile | `GOOS=linux go build` | `cargo build --target` | `1` | Unsupported in `nlc publish`; cross-runtime requests fail with guidance |
| Release build | implicit | `cargo build --release` | `4` | `nlc build --release` selects Release configuration/output layout; no separate IL optimizer yet |
| Clean | `go clean` | `cargo clean` | `5` | `nlc clean`, `nlc clean --all` |
| Verbose output | `-v` | `-v` | `4` | `nlc build --verbose` is available; short `-v` alias is not |
| Build timing | shell `time` / `--timings` | `--timings` | `4` | `nlc build --timings` emits phase timings; no JSON timing schema yet |

### Type Check

| Feature | Go | Rust | N# Score | Notes |
|---------|----|------|----------|-------|
| Fast check | `go vet` | `cargo check` | `5` | `nlc check` is project-aware and fast |
| JSON output | n/a | n/a | `5` | Default structured envelope |
| Human output | default | default | `5` | `nlc check --text` |
| Single file | `go vet file.go` | n/a | `4` | `nlc check --project` is strong; single-file check is still less direct |
| Watch mode | external | external | `5` | `nlc watch check` |

### Auto-Fix / Format

| Feature | Go | Rust | N# Score | Notes |
|---------|----|------|----------|-------|
| Auto-fix | `gofmt -w` | `cargo clippy --fix` | `4` | `nlc fix` supports current fixable diagnostics |
| Dry run | n/a | partial | `5` | `nlc fix --dry-run` |
| Fix categories | formatting only | lint + format | `3` | Current fix catalog is still small |
| Format all | `gofmt -w .` | `cargo fmt` | `5` | `nlc format` |
| Check only | `gofmt -d` | `cargo fmt --check` | `5` | `nlc format --check` |
| Stdin | `gofmt` | `rustfmt --stdin` | `5` | `nlc format --stdin` |
| Diff output | `gofmt -d` | `cargo fmt --check` | `5` | `nlc format --diff` |

### Test / Lint / Tooling

| Feature | Go | Rust | N# Score | Notes |
|---------|----|------|----------|-------|
| Run tests | `go test ./...` | `cargo test` | `5` | `nlc test` runs `.tests.nl` suites |
| Run single test | `-run` | name filter | `5` | `nlc test --filter` |
| Verbose | `-v` | `-- --nocapture` | `4` | `nlc test --verbose` shows individual test results |
| Table-driven tests | struct slices | `#[case]` | `5` | `test "desc" with (params) [cases] { }` |
| Test skip | `t.Skip()` | `#[ignore]` | `5` | `test "desc" skip "reason" { }` |
| Setup blocks | `TestMain` | `#[fixture]` | `4` | `setup { }` — one per file, runs before each test |
| JSON output | `-json` | `cargo test -- --format json` | `4` | `nlc test --json` structured envelope |
| Test coverage | `-cover` | external tools | Planned | `nlc test --coverage` exits 1 with unsupported-feature guidance today |
| Benchmark | `-bench` | `cargo bench` | `1` | Future work |
| Lint | `go vet` | `cargo clippy` | `5` | `nlc lint` with `--json`/`--text`; lints also in `nlc check` |
| Suppress lint | `//nolint` | `#[allow]` | `5` | `// nlc:ignore NL001` |
| API docs | `godoc` | `cargo doc` | `4` | `nlc doc` now generates project HTML docs |
| Shell completions | common | common | `5` | `nlc completion bash|zsh|fish` |

## Known Gaps

These remain intentionally out of scope for this pass:

- Cross-runtime and self-contained publish
- A separate IL optimizer for release builds
- Dependency tree visualization, including nested package-to-package edges for csproj-free `project.yml` dependency trees without an MSBuild project file
- Native coverage reporting
- Benchmark execution
- Machine-readable build timing reports
