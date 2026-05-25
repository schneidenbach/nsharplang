# N# CLI Reference

Updated: 2026-05-25

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
| `nlc tutorial` | Start the local interactive N# walkthrough | `--port`, `--workspace`, `--reset`, `--open`, `--dry-run` | `nlc tutorial --open` |
| `nlc add <package>` | Add a NuGet dependency to `project.yml` | package spec | `nlc add Serilog@3.1.0` |
| `nlc tidy` | Identify and remove unused dependencies | `--project` | `nlc tidy` |
| `nlc remove <package>` | Remove a dependency from `project.yml` | package name | `nlc remove Serilog` |
| `nlc update [package]` | Update dependencies | optional package name | `nlc update` |
| `nlc publish` | Publish framework-dependent deployment artifacts | `--project`, `--configuration`, `--output`, current-host `--runtime` | `nlc publish -c Release --output ./dist` |
| `nlc export csharp` | Export N# sources without changing the IL toolchain | `--project`, `--output` | `nlc export csharp --project .` |
| `nlc idiom` | Score migration idioms and C# leftovers as JSON | `--project` | `nlc idiom --project .` |
| `nlc tree` | Show dependency tree | `--project` | `nlc tree` |
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
| `nlc query diagnostics` | Rich diagnostics envelope; add the `--clusters` flag for versioned AI migration-loop JSON with `category`, `recipe`, `risk`, `files`, `relatedDiagnostics`, and `nextCommand` | `nlc query diagnostics --clusters` |
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

## Tutorial Command

`nlc tutorial` starts a loopback-only ASP.NET Core walkthrough for a first 15-minute N# tour. The browser app creates real lesson projects under the tutorial workspace and hosts a Monaco Editor workbench with N# syntax highlighting, file tabs, Monaco completions, hover, diagnostics, document formatting, and a Problems/Output panel. The editor connects to `NSharpLang.LanguageServer` through a same-origin WebSocket LSP bridge when the language server is available, while the toolbar continues to invoke the local `nlc` command for diagnostics, completions, hover, formatting, run, and test actions. The lessons cover hello world, values/functions, records/classes and visibility-by-casing, unions and pattern matching, duck interfaces, collections/LINQ, error capture, async/.NET interop, testing, and the normal `nlc` tooling loop.

```bash
nlc tutorial
nlc tutorial --open
nlc tutorial --port 5055
nlc tutorial --workspace ./.nlc/tutorial --dry-run
```

Safety and state:

- The host only accepts loopback hosts (`127.0.0.1`, `localhost`, or `::1`).
- The browser app receives a per-server session token from `/api/lessons`; mutating tutorial actions require that token on POST requests.
- Lesson files are local N# projects. Lessons with tests open both `Program.nl` and `Program.tests.nl`; edits to either tab are saved in the tutorial workspace.
- Browser IntelliSense uses the same language-server process as editor tooling when `nsharp-lsp` or the repo-built language server is available. If the LSP bridge is unavailable, the toolbar actions still use `nlc query` endpoints.
- Open the workspace in VS Code when you want the full extension workbench around the same files.
- `--reset` only recreates marked tutorial workspaces. `nlc tutorial` writes `.nsharp-tutorial-workspace` and refuses filesystem roots, the home directory, the current directory, the current repository root, and non-empty directories without the marker.
- Reset preserves unrelated files at the workspace root and only recreates managed tutorial lesson state. Without `--reset`, lesson edits are preserved.
- `--dry-run` materializes the workspaces and exits, which is useful for CI checks and package smoke tests.

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

# Local language walkthrough
nlc tutorial
nlc tutorial --workspace ./.nlc/tutorial --dry-run

# Documentation and automation
nlc doc --json
nlc export csharp --project . --output ./myapp-csharp
nlc query inspect --compact --file Program.nl --pos 42:7

# AI-assisted C# migration gate
# Start from AI-authored .nl files, then iterate on diagnostics.
nlc check --project ./migrated-nsharp --json
nlc idiom --project ./migrated-nsharp
nlc fix --project ./migrated-nsharp --dry-run --json
nlc format --check --project ./migrated-nsharp
nlc test --project ./migrated-nsharp
nlc completion bash > /etc/bash_completion.d/nlc
```

## Build, Test, And Publish Truth

- `nlc build --release` selects the Release configuration and `bin/Release/<targetFramework>` output layout unless `--output` is provided. The direct IL backend does not have a separate optimization mode yet.
- `nlc test --coverage` and `nlc test --coverage-report` are unavailable in the native test runner today. They exit 1 with a clear text error, or with the same message in the schemaVersion 1 JSON `error` field when `--json` is present.
- `nlc publish` produces framework-dependent artifacts. Without `--runtime`, run the output with `dotnet <assembly>.dll` on a compatible .NET installation.
- `nlc publish --runtime <rid>` is supported only when `<rid>` is the current host runtime. It adds a small framework-dependent launcher beside the `.dll`.
- Cross-runtime publish requests fail before building and report both the requested RID and the current host RID.
- `nlc publish --self-contained` is planned, not implemented. It exits 1 with guidance instead of producing an artifact that only appears self-contained.


## AI-Assisted C# Migration Loop

Do not treat syntax conversion as the migration contract. Start from AI-authored `.nl` files, then make the reviewable artifact the result of the full check/idiom/fix loop:

```bash
# Produce ./migrated-nsharp with an AI migration pass that writes idiomatic N# directly.
nlc check --project ./migrated-nsharp --json
nlc idiom --project ./migrated-nsharp
nlc fix --project ./migrated-nsharp --dry-run --json
nlc format --check --project ./migrated-nsharp
nlc test --project ./migrated-nsharp
```

Agent rules:

- Treat `nlc check --json` errors as the first edit queue; cluster by diagnostic/root cause before touching files.
- Treat `nlc idiom` C#-ism signals as migration debt even if the project compiles. Clear copied modifiers, semicolons, property blocks, `_field` names, null/default-forgiving suppressions, DTO classes, C# initializer syntax, and query syntax before review unless explicitly waived.
- Treat `nlc fix --dry-run --json` as a patch planner. Apply `safe` fixes automatically only after inspecting the target diff; require human/agent review for `reviewNeeded`; record rationale for `suggestionOnly` waivers.
- Re-run the loop after each cluster of changes. Passing tests with a poor idiom grade is not enough for an AI-assisted migration handoff.

There is intentionally no `nlc convert` command in the public migration loop. Never mark migrated code done until diagnostics, idiom debt, formatting, and tests are clean.

## Migration Idiom Report

`nlc idiom` emits a stable JSON report for AI agents reviewing C# to N# migrations:

```bash
nlc idiom --project .
```

The report includes a `score` from 0-100, a grade (`idiomatic`, `mostly-idiomatic`, `mixed`, `csharp-heavy`, or `needs-migration`), thresholds, and machine-readable counts for:

- remaining C#-isms: explicit modifiers, statement semicolons in `.nl`, C# property blocks, underscore fields, null/default-forgiving operators, `out` parameter flows, `TryGetValue` flows, C# `using` directives (`usingDirectives`), and C# `namespace` declarations (`namespaceDeclarations`)
- framework/API migration smells: `IActionResult`, anonymous API DTOs, LINQ query syntax, C# equals-style object initializers (`equalsInitializers`), and unsafe `.Value` access on result/option-like values
- package migration blockers: `.nl` files under package folders missing declarations (`missingPackageDeclarations`) or declaring the wrong package for their file layout (`wrongPackageDeclarations`)
- idiomatic N# adoption: records, `match` expressions, `Result` union usage, and package-style folders such as `Models` or `Services`
- migration cleanup signals: DTO-shaped classes that might become records, visibility/casing conflicts, and TODO/manual-review islands

The command scans `.nl` and non-generated `.cs` files, skips `bin`/`obj`, and returns example file/line locations for each signal so follow-up agents can patch the highest-value spots first. The JSON envelope is intentionally stable for AI agents: `schemaVersion` is currently `2`, `signals.csharpIsms` gives aggregate counts plus samples, `signals.nsharpAdoption` gives positive adoption counts, `files[]` gives per-file debt/adoption totals, `findings[]` gives one machine-checkable item per migration-quality issue (`id`, `category`, `severity`, `file`, `line`, `column`, `snippet`, `suggestion`, `fixSafety`, `docsUrl`, `clusterKey`, `confidence`), and `recommendations[]` is ordered migration guidance. Because `snippet` contains source text, share reports outside the project only after redacting proprietary code.

## Exit Codes

| Command Group | `0` | `1` |
|---------------|-----|-----|
| `build`, `run`, `new`, `clean`, `watch`, `doc`, `completion` | Success | Failure |
| `test` | Tests passed | Build or test execution failed |
| `format` | Success or already formatted | Formatting failed or `--check` found drift |
| `lint` | No issues | At least one issue was reported |
| `check` | No errors | Errors present or analysis failed |
| `fix` | Success | Failure, or `--dry-run` found pending fixes |
| `idiom` | Report emitted successfully | Report failed |
| `query` | Query succeeded | Invalid request, missing symbol, or analysis failure |
| `daemon` | Command succeeded | Daemon operation failed |
| `doctor` | Required install checks passed | One or more required checks failed |
| `tutorial` | Server stopped cleanly or dry-run succeeded | Startup, workspace, or tool invocation setup failed |

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

## Lint Rules

| Code | Severity | Description |
|------|----------|-------------|
| NL001 | warning | Unused variable |
| NL002 | error | Missing import |
| NL703 | error | Circular file import; diagnostic includes the import cycle path and a dependency-inversion/shared-file suggestion |
| NL003 | warning | Unnecessary null check on value type |
| NL004 | warning | Async function without await |
| NL005 | info | Use pattern matching |
| NL006 | warning | Unreachable code |

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
- Dependency tree visualization
- Native coverage reporting
- Benchmark execution
- Machine-readable build timing reports
