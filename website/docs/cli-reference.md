---
sidebar_label: CLI Reference
title: CLI Reference
---

# N# CLI Reference

Updated: 2026-06-01

`nlc` is the N# command-line interface. It is designed to feel familiar to Go and Rust developers:

- Build and run loops are project-first.
- `nlc check`, `nlc fix`, `nlc query`, and `nlc lint` default to structured JSON for automation.
- `nlc format`, `nlc test`, `nlc clean`, and `nlc watch` cover common inner-loop workflows; verify scenario-specific behavior before making release claims.
- `nlc --version` prints the installed version.

## Top-Level Commands

| Command | Purpose | Key Flags | Example |
|---------|---------|-----------|---------|
| `nlc build [file]` | Build a project or single file | `--backend`, `--project`, `--release`, `--verbose`, `--timings`, `--perf-report`, `--output`, `--define` | `nlc build` |
| `nlc run [file]` | Build and run a project or single file | `--define` | `nlc run` |
| `nlc new <name>` | Create a csproj-free N# project scaffold | `--template` (`console`, `library`, `test`, `webapi`, `systems-cli`, `systems-lib`), `--systems` | `nlc new MyApp --template console` |
| `nlc init` | Initialize N# in the current directory | none | `nlc init` |
| `nlc test` | Run `.tests.nl` suites through the xUnit/NUnit-backed N# test runner | `--project`, `--filter`, `--verbose`, `--json` | `nlc test --filter "should add"` |
| `nlc format [files...]` | Format N# source | `--project`, `--check`, `--diff`, `--stdin` | `nlc format --diff` |
| `nlc lint [files...]` | Run static analysis rules | `--project`, `--json`, `--text` | `nlc lint --json` |
| `nlc clean` | Remove local build artifacts | `--project`, `--all` | `nlc clean --all` |
| `nlc watch <check\|build\|test\|lint\|format>` | Re-run a command on file changes | `--project`, `--debounce-ms`, `--max-runs` | `nlc watch check` |
| `nlc doc` | Generate HTML API docs | `--project`, `--output`, `--open`, `--json` | `nlc doc --open` |
| `nlc completion <shell>` | Generate shell completion scripts | `bash`, `zsh`, `fish` | `nlc completion zsh` |
| `nlc check` | Fast parse + analyze without building | `--project`, `--text`, `--json`, `--use-built-references` | `nlc check --text` |
| `nlc fix` | Auto-apply code fixes | `--project`, `--file`, `--dry-run`, `--text`, `--json` | `nlc fix --dry-run` |
| `nlc query <subcommand>` | Code intelligence for humans and tools | global `--project`, `--file`, `--pos`, `--text`, `--json`, `--no-daemon` | `nlc query def --file Program.nl --pos 12:4` |
| `nlc daemon <subcommand>` | Manage the warm workspace server that `check`/`build`/`test`/`run`/`format`/`lint`/`fix` use automatically | `--project` | `nlc daemon status` |
| `nlc add <package>` | Add a NuGet dependency to `project.yml` | package spec | `nlc add Serilog@3.1.0` |
| `nlc tidy` | Identify and remove unused dependencies | `--project` | `nlc tidy` |
| `nlc remove <package>` | Remove a dependency from `project.yml` | package name | `nlc remove Serilog` |
| `nlc update [package]` | Update dependencies | optional package name | `nlc update` |
| `nlc publish` | Publish framework-dependent deployment artifacts | `--project`, `--configuration`, `--output`, current-host `--runtime` | `nlc publish -c Release --output ./dist` |
| `nlc tree` | Show dependency tree | `--project`, `--depth`, `--json` | `nlc tree --json` |
| `nlc audit` | Check dependencies for known vulnerabilities | `--project` | `nlc audit` |
| `nlc env` | Show environment and toolchain info | `--json` | `nlc env --json` |
| `nlc doctor` | Verify CLI, templates/SDK restore, language server, and VS Code extension availability | `--json`, `--require-vscode`, `--skip-vscode` | `nlc doctor --require-vscode` |
| `nlc restore` | Generate MSBuild compatibility config from `project.yml` | `--project` | `nlc restore` |
| `nlc pack` | Create a NuGet package from `project.yml` metadata | `--project`, `--output` | `nlc pack` |
| `nlc help` | Show top-level CLI help | none | `nlc help` |

## The Workspace Server (daemon-first CLI)

`nlc check`, `build`, `test`, `run`, `format`, `lint` and `fix` are executed by a **warm server per
workspace** whenever one is available. Nothing has to be started by hand: the first such command in
a workspace runs in-process as usual and starts the server in the background; every later command
finds it warm (compiler JIT-compiled, reference metadata indexed) and is typically 3-5x faster.

```bash
nlc check            # first command: in-process, starts the server in the background
nlc check            # every later command: answered by the warm server
nlc daemon status    # pid, uptime, build identity, requests served, memory
nlc daemon stop      # stop it (it also stops on its own when idle)
```

**Output is identical either way.** A routed command produces byte-for-byte the same stdout and
stderr, the same exit code and the same versioned JSON as the in-process command. The server runs it
in the client's working directory, with the client's environment variables (all of them, exactly —
a variable the client does not have is removed for that command), culture, arguments and terminal
state (`--color=auto` still sees whether *your* stderr is a terminal). Commands that read stdin
(`nlc format --stdin`) read the client's stdin, and `nlc run` starts your program in the client
process, on your terminal, so it behaves exactly as before. Ctrl-C ends the command the same way.

**The workspace** is the nearest directory above the current one that contains `.git`, otherwise the
nearest containing `project.yml`. One server serves every project under it. Outside any workspace
commands simply run in-process and nothing is created.

**Build identity.** A server is only ever used by the exact `nlc` build that started it: the
identity covers the CLI version (with its commit), the install directory, the size and timestamp of
every assembly in it, the .NET runtime version, and every `DOTNET_*`/`COMPlus_*` variable. A client
that finds a server of another build stops it, runs the command in-process, and starts a fresh one.

**Tests run isolated.** `nlc test` builds in the server but runs your tests in a separate,
single-use test-worker process (started ahead of time, so it is already warm). A test that calls
`Environment.Exit`, overflows its stack or never finishes cannot affect the server: the command ends
with the same exit code an in-process run would have, and the server keeps serving. While tests run
— in-process or not — `NLC_DAEMON_CHILD=1` is set, so any `nlc` a test starts runs in-process.

**Fallback.** If the server is busy with another client for more than 250 ms, the command runs
in-process instead (two agents never queue behind each other's long test runs). If the server dies
or stops responding mid-command, the client prints one line to stderr —
`nlc: the workspace server stopped responding; running in-process instead (...)` — and reruns the
command in-process; stdout still carries exactly one result.

| Switch | Effect |
|--------|--------|
| `--no-daemon` | Run this command in-process (accepted by every routed command) |
| `NLC_NO_DAEMON=1` | Run every command in-process |
| `CI=true` / `CI=1` | Server off by default on CI; `NLC_DAEMON=1` turns it back on |
| `NLC_DAEMON_IDLE_TIMEOUT` | Idle shutdown, e.g. `10m`, `90s` (default `30m`) |
| `NLC_DAEMON_MAX_MEMORY_MB` | Working-set cap; over it the server sheds caches and retires (default `4096`) |
| `NLC_DAEMON_WARMUP=0` | Skip the warm-up compile a new server does before taking work |
| `NLC_DAEMON_TRACE=1` | Print one `[nlc-daemon] route=...` timing line to stderr per routed command |

The server stops when idle, when its working set passes the cap, when its workspace directory is
deleted, on `nlc daemon stop`, and on SIGTERM (requests in flight finish first). It ignores the
Ctrl-C and hang-up of the terminal it was started from. Its socket is `{workspace}/.nlc/daemon.sock`
(or `{TMPDIR}/nlc-daemon/{sha256-16}/daemon.sock` when that path would exceed 100 bytes), created
owner-only (`0600`, in an owner-only directory for the fallback), so no other user can reach it. Its
log is `.nlc/daemon.log`, restarted with each server. `.nlc/` is runtime state and should not be
committed; all shipped `dotnet new` templates ignore it.

`nlc daemon start` starts the server explicitly and waits for it to answer `daemon/ping` (120-second
deadline; an early exit or a timeout reports the elapsed time, the socket path, whether the child was
alive and the last daemon output). JSON `nlc query` commands reuse a running server of the same build
for any project in its workspace.

## Query Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc query batch --requests <file>` | Execute multiple semantic queries in one response | `nlc query batch --requests requests.json` |
| `nlc query symbols` | List project symbols | `nlc query symbols --kind function` |
| `nlc query outline <file>` | File structure and imports | `nlc query outline Program.nl` |
| `nlc query ast` | Full parsed AST as stable, node-typed JSON (whole project, or one `--file`) | `nlc query ast --file Program.nl` |
| `nlc query diagnostics` | Rich diagnostics envelope; add the `--clusters` flag for versioned diagnostic-cluster JSON with `category`, `recipe`, `risk`, `files`, `relatedDiagnostics`, and `nextCommand` | `nlc query diagnostics --clusters` |
| `nlc query type --file <file> --pos <line:col>` | Type at a position | `nlc query type --file Program.nl --pos 5:12` |
| `nlc query inspect --file <file> --pos <line:col>` | Symbol, type, definition, refs, and completions in one call; add `--compact` for token-efficient agent context (`--summary` is kept as an alias) | `nlc query inspect --compact --file Program.nl --pos 5:12` |
| `nlc query definition` | Go-to-definition by position | `nlc query definition --file Program.nl --pos 5:12` |
| `nlc query def` | Alias for `definition` | `nlc query def --file Program.nl --pos 5:12` |
| `nlc query references` | Find references to a symbol | `nlc query references --file Program.nl --pos 5:12` |
| `nlc query refs` | Alias for `references` | `nlc query refs --file Program.nl --pos 5:12` |
| `nlc query completions` | LLM-optimized completions | `nlc query completions --file Program.nl --pos 5:12` |
| `nlc query doc <query>` | Look up .NET API documentation | `nlc query doc Console.WriteLine` |
| `nlc query hover` | Signature and docs at a position | `nlc query hover --file Program.nl --pos 5:12` |
| `nlc query call-graph` | Callers and callees of a function | `nlc query call-graph --function Main` |
| `nlc query implementors` | Concrete types implementing an interface | `nlc query implementors --name IShape` |
| `nlc query perf` | Explain allocation/dispatch/capture/ABI and systems effect facts at a position | `nlc query perf --file Program.nl --pos 5:12` |
| `nlc query trusted` | Report governed Systems N# `[trusted]` wrappers | `nlc query trusted` |
| `nlc query help` | Show query command help | `nlc query help` |

## Systems N# CLI Surface

Systems N# is exposed through existing stable commands rather than a separate `nlc systems` command family:

```bash
nlc new systems-cli PacketTool
nlc new systems-lib PacketCore
nlc new PacketTool --template console --systems
nlc new PacketCore --template library --systems

nlc check --systems-report
nlc build --perf-report
nlc query perf --file Program.nl --pos 12:8
nlc query trusted
```

Systems templates set `language.profile: systems`, strict mode, `aotTarget: nativeaot`, `stackBudgetBytes: 4096`, a warmup function, a sample `[hot]` span parser, a `[boundary]` adapter, `Result<T,E>` use, and `.tests.nl` smoke tests.

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
nlc check --use-built-references   # project: dependencies read from their own builds, not recompiled
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
nlc query inspect --compact --file Program.nl --pos 42:7

nlc completion bash > /etc/bash_completion.d/nlc
```

## Build, Test, And Publish Truth

- `nlc build --release` selects the Release configuration and `bin/Release/<targetFramework>` output layout unless `--output` is provided. The direct IL backend does not have a separate optimization mode yet.
- **Conditional compilation.** `#if`/`#elif`/`#else`/`#endif` are evaluated by the compiler against the set of defined symbols; only the live branch is compiled (`#region`/`#endregion` remain organizational pass-through). `DEBUG` is defined for debug builds (`nlc run`, `nlc build`, `nlc test`) and omitted under `nlc build --release`. Project-wide symbols come from `defines:` in `project.yml`; ad-hoc symbols come from `--define <symbol>` / `-d <symbol>` (repeatable, and comma/semicolon lists are accepted). Conditions support symbols, `true`/`false`, `!`, `&&`, `||`, and parentheses, matching established preprocessor semantics. Symbol names are case-sensitive.
- `nlc test --coverage` and `nlc test --coverage-report` are unavailable in the native test runner today. They exit 1 with a clear text error, or with the same message in the schemaVersion 1 JSON `error` field when `--json` is present.
- `nlc test --timings` reports where the run spent its time: the incremental build of the project with its tests, the runner over the emitted assembly, and the whole command. Text mode prints a `Test timings:` block on standard error, where `nlc build --timings` prints its own, so standard output is unchanged; with `--json` the envelope gains a `timings` object of integer milliseconds (`buildMs`, `runMs`, `totalMs`). Without the flag neither appears, so the schemaVersion 1 envelope a caller already reads is byte-for-byte the same.
- A failing `nlc test` run names every failed test before its summary: a `Failed tests (N):` block gives each failure's `test "…"` sentence, the generated method it lowered to, and the failure message indented beneath it. A passing run prints no block. `--json` carries the same facts per row as `displayName`, `name` and `errorMessage`.
- `nlc test --json` result rows carry a stable vocabulary: `outcome` is exactly `passed`, `skipped` or `failed`, and `duration` is three decimal places and an `s` formatted with the invariant culture, so the envelope reads the same on every machine regardless of locale. `displayName` and `nsharpDescription` prefer the `test "…"` sentence over the generated method name.
- A `test` block may carry attributes, which land on the method it lowers to. An attribute deriving from `Xunit.FactAttribute` decides in its own constructor whether the test runs; setting its `Skip` produces a `skipped` row whose `errorMessage` is the reason. The compiler attaches its own `[Fact]` only when the test does not already carry one, because a method with two `[Fact]`-derived attributes is a discovery error in xunit. The attribute class may be declared in any file of the project.
- `nlc publish` produces framework-dependent artifacts. Without `--runtime`, run the output with `dotnet <assembly>.dll` on a compatible .NET installation.
- `nlc publish --runtime <rid>` is supported only when `<rid>` is the current host runtime. It adds a small framework-dependent launcher beside the `.dll`.
- Cross-runtime publish requests fail before building and report both the requested RID and the current host RID.
- `nlc publish --self-contained` is planned, not implemented. It exits 1 with guidance instead of producing an artifact that only appears self-contained.


## Diagnostic Colour

`nlc build` and `nlc run` write human-readable diagnostics to standard error and colour them with
ANSI SGR sequences. Whether a run colours is decided by `DiagnosticColorPolicy`, in this precedence:

| # | Signal | Effect |
|---|---|---|
| 1 | `--color=always` / `--color` / `--color=yes` / `--color=force` | colour, whatever the rest says |
| 1 | `--color=never` / `--no-color` / `--color=no` / `--color=none` | no colour, whatever the rest says |
| 2 | `NO_COLOR` set and non-empty | no colour |
| 3 | `FORCE_COLOR` set and not `0` | colour, even into a pipe or file |
| 4 | *(default)* | colour when standard error is a terminal, plain when it is redirected |

`--color=auto`, and any `--color=<value>` that is not listed, fall back to row 4 rather than failing
the run. When several colour flags appear, the last one wins. An empty `NO_COLOR` is treated as
unset, per the [no-color.org](https://no-color.org) convention.

The machine-readable surfaces never colour, under any setting: `nlc check` and every `--json` output
are plain, and so is the diagnostic text embedded in a project-reference build failure's exception
message.

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

A routed command exits with exactly the code the in-process command would have; see
[The Workspace Server](#the-workspace-server-daemon-first-cli).
| `tree` | Dependency tree emitted | Missing project root/config or dependency resolver failure |
| `doctor` | Required install checks passed | One or more required checks failed |

An unexpected exception escaping any command exits **`2`** and prints
[NL924: internal compiler error](errors/NL924.md) to stderr. This is a bug in N#.
The process boundary uses the same plain diagnostic for text and JSON requests and leaves stdout
untouched; check the exit status before treating stdout as a complete response. Ordinary errors
handled by a command retain the exit codes and JSON envelopes documented above.

`nlc run` forwards the launched program's exit status, including `2`. In that case the number alone
does not identify an internal compiler failure: NL924 on stderr supplies that distinction.

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
      "code": "NL010",
      "severity": "error",
      "message": "The import 'import System' is not used by any code in this file",
      "file": "Program.nl",
      "line": 3,
      "column": 8,
      "length": 6,
      "sourceSnippet": "import System",
      "suggestion": "Remove 'import System' to keep your imports clean",
      "docsUrl": "https://schneidenbach.github.io/nsharplang/docs/errors/NL010"
    }
  ],
  "summary": {
    "errors": 1,
    "warnings": 0,
    "info": 0
  }
}
```

`nlc lint` **analyses the project before it lints**, the same way `nlc fix` does. Two rules are
answered by what a source file BOUND rather than by what it parsed to — `NL010` (this import is not
used) and `NL002` (this name has no import) — so a lint run that only parsed reported neither, and
`nlc lint` said "no issues" about a file `nlc check` reported two `NL010` errors on. The three
commands now read one set of analysed units and report one set of rules.

Two result codes are the command's own rather than a rule: `PARSE` (the parser refused the file, so
no rule ran on it) and `LINT` (the file could not be read at all). Both carry `severity: "error"`.
Rule rows carry `docsUrl` from the diagnostic catalog, the same link `nlc check` prints.

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

N# is near-zero-warnings: every active lint rule is a build-blocking **error**. Correctness, safety, and hygiene are enforced; pure style is handled by `nlc format`, not by diagnostics.

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

Compiler safety diagnostics are likewise build-blocking errors: `NL905` (possible null access, flow-based), `NL903` (visibility convention), and `NL907` (nullability).

Pure-style rules that used to emit `info`/`warning` diagnostics — `NL005` (use-pattern-matching), `NL008` (camel-case-local), `NL013` (prefer-interpolation), `NL014`/`NL906` (unnecessary-type-annotation), `NL015` (prefer-const), `NL018` (prefer-readonly), `NL019` (empty-block) — have been removed and folded into `nlc format`.

### Allocation, boxing and AOT diagnostics

These are reported by the **systems analyzer**, under the `NSYS` codes, and only where a systems
policy asks for them — `[hot]`, `alloc(none)`, a `[boundary]`, or an `aotTarget`. `NSYS010`
(allocation), `NSYS020` (boxing), `NSYS030` (delegate or closure construction), `NSYS040` (runtime
dispatch) and `NSYS060` (AOT/trim safety) are the codes to look for; see
[Systems Programming](./systems.md).

An earlier `NL950`–`NL954` / `NL960`–`NL963` band was documented here as "emitted by the optimizer".
Nothing ever emitted it. Those rows were retired from the catalog rather than left as documentation
for output no compiler produced.

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

`nlc check` accepts a project root or a workspace root. At a workspace root it discovers nested
`project.yml` members, checks each member as its own program, and also checks any sources owned by
the root project. Each source belongs to its nearest project root, which supplies that member's
configuration, references and `exclude` rules. Discovery skips `bin/`, `obj/`, `.git/`, nested Git
worktrees, `node_modules/` and `bootstrap/`. Member checks use bounded parallelism and share resolved
reference metadata. Text output groups diagnostics by project. Workspace JSON uses `schemaVersion: 2`
with a top-level `projects` array; each member contains `projectRoot`, `checkedFiles`, `ok`, `results`
and `summary`, plus `error` on project failure and `systemsReport` when requested. Top-level file
counts and diagnostic totals aggregate all projects; `summary.projectFailures` counts project-level
failures that returned an `error` instead of diagnostics, such as invalid configuration or an
unresolved reference. Single-project checks keep the existing version-1 shape. A source claimed by
two projects is reported as a configuration conflict.

| Feature | Go | Rust | N# Score | Notes |
|---------|----|------|----------|-------|
| Fast check | `go vet ./...` | `cargo check --workspace` | `5` | `nlc check` analyzes every workspace member and root-owned source in one invocation |
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
| Test skip | `t.Skip()` | `#[ignore]` | `4` | An attribute deriving from `FactAttribute` whose constructor sets `Skip`, written above the `test` block; `nlc test` reports the test as `skipped` with that reason. The `skip "reason"` CLAUSE parses for forward compatibility but no backend emits it — `nlc test` reports `NL323` |
| Conditional test | build tags | `#[cfg]` | `4` | The same derived-fact attribute, deciding in its own constructor; the compiler withholds its synthesized `[Fact]` when a test already carries one |
| Setup blocks | `TestMain` | `#[fixture]` | `4` | `setup { }` — one per file, runs before each test |
| JSON output | `-json` | `cargo test -- --format json` | `4` | `nlc test --json` structured envelope |
| Test coverage | `-cover` | external tools | Planned | `nlc test --coverage` exits 1 with unsupported-feature guidance today |
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
- Built-in cross-language benchmark comparison
- Machine-readable build timing reports
