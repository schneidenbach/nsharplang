# N# CLI Reference

Updated: 2026-03-29

`nlc` is the N# command-line interface. It is designed to feel familiar to Go and Rust developers:

- Build and run loops are project-first.
- `nlc check`, `nlc fix`, `nlc query`, and `nlc lint` default to structured JSON for automation.
- `nlc format`, `nlc test`, `nlc clean`, and `nlc watch` support the fast inner-loop workflows developers expect from `gofmt`, `cargo test`, and `cargo watch`.
- `nlc --version` prints the installed version.

## Top-Level Commands

| Command | Purpose | Key Flags | Example |
|---------|---------|-----------|---------|
| `nlc build [file]` | Build a project or single file | `--keep-generated` | `nlc build` |
| `nlc run [file]` | Build and run a project or single file | none | `nlc run` |
| `nlc transpile <file>` | Print generated C# | none | `nlc transpile Program.nl` |
| `nlc new <name>` | Create a new N# project scaffold | none | `nlc new MyApp` |
| `nlc test` | Run `.tests.nl` suites through xUnit | `--project`, `--filter`, `--verbose` | `nlc test --filter "should add"` |
| `nlc format [files...]` | Format N# source | `--project`, `--check`, `--diff`, `--stdin` | `nlc format --diff` |
| `nlc lint [files...]` | Run static analysis rules | `--project`, `--json`, `--text` | `nlc lint --json` |
| `nlc clean` | Remove local build artifacts | `--project`, `--all` | `nlc clean --all` |
| `nlc watch <check\|build\|test>` | Re-run a command on file changes | `--project`, `--debounce-ms`, `--max-runs` | `nlc watch check` |
| `nlc doc` | Generate HTML API docs | `--project`, `--output`, `--open`, `--json` | `nlc doc --open` |
| `nlc completion <shell>` | Generate shell completion scripts | `bash`, `zsh`, `fish` | `nlc completion zsh` |
| `nlc check` | Fast parse + analyze without building | `--project`, `--text`, `--json` | `nlc check --text` |
| `nlc fix` | Auto-apply code fixes | `--project`, `--file`, `--dry-run`, `--text`, `--json` | `nlc fix --dry-run` |
| `nlc query <subcommand>` | Code intelligence for humans and tools | global `--project`, `--file`, `--pos`, `--text`, `--json`, `--no-daemon` | `nlc query def --file Program.nl --pos 12:4` |
| `nlc daemon <subcommand>` | Manage the background analysis daemon | `--project` | `nlc daemon status` |

## Query Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc query batch --requests <file>` | Execute multiple semantic queries in one response | `nlc query batch --requests requests.json` |
| `nlc query symbols` | List project symbols | `nlc query symbols --kind function` |
| `nlc query outline <file>` | File structure and imports | `nlc query outline Program.nl` |
| `nlc query diagnostics` | Rich diagnostics envelope | `nlc query diagnostics --text` |
| `nlc query type --file <file> --pos <line:col>` | Type at a position | `nlc query type --file Program.nl --pos 5:12` |
| `nlc query inspect --file <file> --pos <line:col>` | Symbol, type, definition, refs, and completions in one call | `nlc query inspect --summary --file Program.nl --pos 5:12` |
| `nlc query definition` / `def` | Go-to-definition by position or name | `nlc query def --name Person` |
| `nlc query references` / `refs` | Find references to a symbol | `nlc query refs --file Program.nl --pos 5:12` |
| `nlc query completions` | LLM-optimized completions | `nlc query completions --file Program.nl --pos 5:12` |
| `nlc query doc <query>` | Look up .NET API documentation | `nlc query doc Console.WriteLine` |

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

# Documentation and automation
nlc doc --json
nlc query inspect --summary --file Program.nl --pos 42:7
nlc completion bash > /etc/bash_completion.d/nlc
```

## Exit Codes

| Command Group | `0` | `1` |
|---------------|-----|-----|
| `build`, `run`, `transpile`, `new`, `clean`, `watch`, `doc`, `completion` | Success | Failure |
| `test` | Tests passed | Build or test execution failed |
| `format` | Success or already formatted | Formatting failed or `--check` found drift |
| `lint` | No issues | At least one issue was reported |
| `check` | No errors | Errors present or analysis failed |
| `fix` | Success | Failure, or `--dry-run` found pending fixes |
| `query` | Query succeeded | Invalid request, missing symbol, or analysis failure |
| `daemon` | Command succeeded | Daemon operation failed |

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
| Cross-compile | `GOOS=linux go build` | `cargo build --target` | `1` | Future work; depends on .NET targeting |
| Release build | implicit | `cargo build --release` | `2` | Not exposed as a first-class `nlc` flag yet |
| Clean | `go clean` | `cargo clean` | `5` | `nlc clean`, `nlc clean --all` |
| Verbose output | `-v` | `-v` | `2` | Not a first-class `nlc build -v` path yet |
| Build timing | shell `time` / `--timings` | `--timings` | `2` | External timing works; built-in report not exposed |

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
| Run tests | `go test ./...` | `cargo test` | `4` | `nlc test` runs `.tests.nl` suites |
| Run single test | `-run` | name filter | `5` | `nlc test --filter` |
| Verbose | `-v` | `-- --nocapture` | `4` | `nlc test --verbose` increases `dotnet test` verbosity |
| Test coverage | `-cover` | external tools | `1` | Future work |
| Benchmark | `-bench` | `cargo bench` | `1` | Future work |
| Lint | `go vet` | `cargo clippy` | `5` | `nlc lint` with `--json`/`--text`; lints also in `nlc check` |
| Suppress lint | `//nolint` | `#[allow]` | `5` | `// nlc:ignore NL001` |
| API docs | `godoc` | `cargo doc` | `4` | `nlc doc` now generates project HTML docs |
| Shell completions | common | common | `5` | `nlc completion bash|zsh|fish` |

## Known Gaps

These remain intentionally out of scope for this pass:

- Cross-compilation
- First-class release builds
- Dependency tree visualization
- Coverage reporting
- Benchmark execution
- Built-in build timing reports
