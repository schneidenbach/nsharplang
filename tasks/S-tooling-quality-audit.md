# Task S: CLI Tooling Quality Audit — Match Go and Rust

## Context

AGENTS.md says: "a strong CLI that aims to be as reliable and good as Go and Rust." The CLI toolchain (`nlc`) has a lot of commands. But have they been stress-tested against what `go` and `cargo` actually do? This audit compares `nlc` against `go` and `cargo` feature-by-feature and fixes the gaps.

The goal: a Go developer typing `nlc` for the first time should feel *at home*. A Rust developer should think "oh, this is like cargo but for .NET."

## Phase 1: Feature Parity Audit

Run every `nlc` command and compare against the equivalent in Go and Rust. Score each on a 1-5 scale.

### Build & Run

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| Build project | `go build` | `cargo build` | `nlc build` | |
| Run project | `go run .` | `cargo run` | `nlc run` | |
| Build single file | `go build file.go` | n/a | `nlc build file.nl` | |
| Cross-compile | `GOOS=linux go build` | `cargo build --target` | ??? | |
| Release build | implicit | `cargo build --release` | ??? | |
| Clean | `go clean` | `cargo clean` | ??? | |
| Verbose output | `go build -v` | `cargo build -v` | ??? | |
| Build timing | `time go build` | `cargo build --timings` | ??? | Does nlc report compile time? |

### Type Check (no compile)

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| Fast check | `go vet` | `cargo check` | `nlc check` | |
| JSON output | n/a | n/a | `nlc check` (default) | Advantage N#! |
| Human output | default | default | `nlc check --text` | |
| Single file | `go vet file.go` | n/a | `nlc check --file F` | |
| Watch mode | n/a | `cargo watch` | ??? | Does nlc have watch? |

### Auto-fix

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| Auto-fix | `gofmt -w` (format only) | `cargo clippy --fix` | `nlc fix` | |
| Dry run | n/a | `cargo clippy --fix --dry-run`? | `nlc fix --dry-run` | |
| Fix categories | format | lint + format | ??? | How many fix categories does nlc support? |

### Format

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| Format all | `gofmt -w .` | `cargo fmt` | `nlc format` | |
| Check only | `gofmt -d .` | `cargo fmt --check` | `nlc format --check` | |
| Stdin | `gofmt` (reads stdin) | `rustfmt --stdin` | ??? | |
| Diff output | `gofmt -d` | `cargo fmt -- --check` | ??? | Show what would change |

### Test

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| Run tests | `go test ./...` | `cargo test` | `nlc test` | |
| Run single test | `go test -run TestName` | `cargo test test_name` | ??? | Filter by name? |
| Verbose | `go test -v` | `cargo test -- --nocapture` | ??? | |
| Test coverage | `go test -cover` | `cargo tarpaulin` | ??? | |
| Benchmark | `go test -bench .` | `cargo bench` | ??? | |

### Lint / Static Analysis

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| Lint | `go vet` + `golangci-lint` | `cargo clippy` | `nlc lint` | |
| Lint categories | many | many | ??? | How many lint rules? |
| Suppress lint | `//nolint:xxx` | `#[allow(xxx)]` | ??? | |

### Project Management

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| New project | `go mod init` | `cargo new` | `dotnet new nsharp-*` | |
| Dependencies | `go get pkg` | `cargo add pkg` | `dotnet add package` | |
| Update deps | `go get -u` | `cargo update` | `dotnet outdated`? | |
| Dep tree | `go mod graph` | `cargo tree` | ??? | |

### Code Intelligence

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| Find definition | `gopls` / `guru` | `rust-analyzer` | `nlc query def` | |
| Find references | `gopls` / `guru` | `rust-analyzer` | `nlc query refs` | |
| Completions | `gopls` | `rust-analyzer` | `nlc query completions` | |
| Symbol list | `go doc` | n/a | `nlc query symbols` | |
| Type at position | n/a | n/a | `nlc query type` | Advantage N#! |
| Inspect (bundle) | n/a | n/a | `nlc query inspect` | Advantage N#! |
| Doc lookup | `go doc fmt.Println` | `cargo doc --open` | `nlc query doc`? | |
| API docs gen | `godoc` | `cargo doc` | ??? | |

### Daemon / Background

| Feature | Go | Rust | N# | Notes |
|---------|-----|------|-----|-------|
| Background server | `gopls` (always) | `rust-analyzer` (always) | `nlc daemon` | |
| Start/stop | automatic | automatic | `nlc daemon start/stop` | |
| Status | `gopls version` | n/a | `nlc daemon status` | |

## Phase 2: Fix the Gaps

For each `???` in the table above, determine:
1. **Is it implemented but undocumented?** → Document it
2. **Is it missing and important?** → Implement it
3. **Is it missing and low-priority?** → Note it in NEXT.md

### Priority fixes (implement these):

**1. `nlc clean`**
Remove build artifacts. Equivalent to `cargo clean` / `go clean`.
```bash
nlc clean              # remove bin/, obj/, nsharp/ dirs
nlc clean --all        # also remove NuGet caches
```

**2. `nlc test --filter <name>`**
Run a subset of tests by name pattern. Essential for development.
```bash
nlc test --filter "should add"    # run tests matching pattern
nlc test --verbose                # show test output
```

**3. Watch mode**
Re-run check/build on file changes. Like `cargo watch`.
```bash
nlc watch check        # re-run nlc check on every .nl file change
nlc watch build        # re-run build
nlc watch test         # re-run tests
```
Implementation: use `FileSystemWatcher` to monitor `.nl` files, debounce changes, re-run the command.

**4. `nlc format --diff`**
Show what would change without changing it. Like `gofmt -d`.
```bash
nlc format --diff      # unified diff output
nlc format --check     # exit 1 if not formatted (for CI)
```

**5. `nlc doc`**
Generate API documentation for a project. Like `cargo doc` / `godoc`.
```bash
nlc doc                # generate HTML docs for current project
nlc doc --open         # generate and open in browser
nlc doc --json         # structured JSON output
```

**6. Lint suppression**
Allow suppressing specific lint warnings inline:
```n#
// nlc:ignore NL001
unusedVar := 42
```

### Lower priority (document as future work):
- Cross-compilation (depends on .NET runtime targeting)
- Release builds (depends on `dotnet publish` configuration)
- Dependency tree visualization
- Test coverage reporting
- Benchmark support

## Phase 3: CLI UX Polish

### Help text audit
Run every `nlc` command with `--help`. Verify:
- Description is clear and concise
- All flags are documented
- Examples are provided
- Exit codes are documented

Compare against `cargo --help` quality.

### Error output audit
For each command, trigger common errors:
- `nlc build` in a directory with no project → helpful error
- `nlc check --file nonexistent.nl` → clear file-not-found
- `nlc query def --pos 999:999` → clean "no symbol at position"
- `nlc daemon start` when already running → informative message
- `nlc format` on a file with syntax errors → graceful handling

Every error should:
- Use exit code 1 (not 0)
- Print to stderr (not stdout)
- Be structured JSON by default
- Have a human-readable `--text` form
- Include a suggestion when possible

### Completion scripts
Do shell completions exist?
```bash
nlc completion bash > /etc/bash_completion.d/nlc
nlc completion zsh > ~/.zsh/completions/_nlc
nlc completion fish > ~/.config/fish/completions/nlc.fish
```
If not, add them. Use the Cobra/System.CommandLine pattern of generating completions from the command tree.

## Phase 4: Documentation

Update `memory/components/cli-toolchain.md` with any new commands or flags.

Create `docs/guide/cli-reference.md` with:
- Every command, every flag
- Examples for each
- Exit code reference
- JSON schema examples
- Comparison table vs Go/Rust (the one from Phase 1, filled in)

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
