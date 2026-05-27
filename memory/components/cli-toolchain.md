# N# CLI Toolchain (`nlc`)

**Status:** Active pre-release CLI with code intelligence, auto-fix, and daemon mode. Verify release claims with current help/completion output and test logs.
**Test count:** Do not hard-code; run `dotnet test tests/Tests.csproj` or `./scripts/test-all.sh` for current evidence.

The `nlc` CLI is designed for two audiences: humans at a terminal and LLMs navigating code via bash. `nlc query`, `nlc check`, `nlc fix`, and `nlc lint` all output structured JSON by default with a versioned envelope. `check`, `fix`, and `lint` use `ok`/`error` at the top level; query failures use the same structured error envelope. Add `--text` for human-readable output. `nlc --version` prints the installed version.

The executable toolchain is now IL-only:
- `il` — emit IL directly to a managed assembly

`project.yml` supports `backend: il`; when omitted, IL is the default. The CLI honors that setting for `check`, `build`, `run`, `test`, `bench`, `publish`, and `pack` through the native project.yml build path. The MSBuild SDK remains available for direct `dotnet build`, `dotnet run`, and `dotnet test` compatibility when a host tool needs a `.csproj`. C# generation remains available only as the explicit `nlc export csharp` migration/off-ramp command. C# input migration is intentionally AI-driven through diagnostics and idiom gates, not `nlc convert`; migration-quality work should prefer AI-assisted diagnostic clustering and idiom gates over treating initial migration output as final.

---

## Command Reference

### Build & Run

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc build` | Compile project through the IL backend | `nlc build` |
| `nlc build <file>` | Compile single file | `nlc build Program.nl` |
| `nlc build --backend il` | Compile with the direct IL backend | `nlc build --backend il` |
| `nlc build --release` | Build with Release configuration/output layout | `nlc build --release` |
| `nlc build --verbose` | Build with detailed native resolver/test output | `nlc build --verbose` |
| `nlc run` | Compile and run project through the IL backend | `nlc run` |
| `nlc run <file>` | Compile and run single file | `nlc run Program.nl` |
| `nlc run --backend il` | Build and run via the direct IL backend | `nlc run --backend il` |
| `nlc publish` | Publish portable framework-dependent artifacts | `nlc publish --output ./dist` |
| `nlc publish --runtime <current-rid>` | Add a framework-dependent launcher for the current host runtime only | `nlc publish --runtime osx-arm64 --output ./dist` |
| `nlc publish --self-contained` | Unsupported/planned; exits 1 with guidance | `nlc publish --self-contained` |
| `nlc publish --backend il` | Publish with the IL backend | `nlc publish --backend il --output ./dist` |
| `nlc clean` | Remove build artifacts (`bin/`, `obj/`, `.nlc/`) and legacy generated wrappers | `nlc clean` |
| `nlc clean --all` | Also clear NuGet caches | `nlc clean --all` |
| `nlc export csharp` | Export a file or project bundle to C# | `nlc export csharp --project . -o ./myapp-csharp` |
| `nlc watch <check\|build\|test\|lint\|format>` | Re-run a command on file changes | `nlc watch check` |
| `nlc check` | Fast type-check + backend verification (JSON by default) | `nlc check` |
| `nlc check --backend il` | Verify semantic analysis plus direct IL emission | `nlc check --backend il` |
| `nlc fix` | Auto-apply compiler suggestions (JSON by default) | `nlc fix` |

### C# Source Migration

There is no public `nlc convert` command in the canonical CLI contract. C#→N# migration is AI-driven: write idiomatic `.nl` directly, use `nlc check --json` diagnostic clusters as the edit queue, clear `nlc idiom` C# debt, apply reviewed `nlc fix` patches, format, and test.

### Code Intelligence (`nlc query`)

All query commands output **JSON by default** with a versioned envelope (`schemaVersion: 1`). Add `--text` for human-readable output. When a daemon is already running, JSON query commands reuse it automatically; add `--no-daemon` to force in-process analysis.

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc query symbols` | List all symbols in project | `nlc query symbols` |
| `nlc query symbols --file F` | Symbols in one file | `nlc query symbols --file Program.nl` |
| `nlc query symbols --kind K` | Filter by kind | `nlc query symbols --kind function` |
| `nlc query symbols --filter P` | Filter by glob or substring | `nlc query symbols --filter '*Person*'` |
| `nlc query outline <file>` | File structure (imports, declarations) | `nlc query outline Program.nl` |
| `nlc query diagnostics` | Errors/warnings with Elm-level context | `nlc query diagnostics` |
| `nlc query diagnostics --text` | Elm-style terminal output | `nlc query diagnostics --text` |
| `nlc query batch --requests requests.json` | Execute multiple semantic queries in one JSON response | `nlc query batch --requests requests.json` |
| `nlc query type --file F --pos L:C` | Type info at position | `nlc query type --file Program.nl --pos 5:4` |
| `nlc query inspect --file F --pos L:C` | One-shot symbol/type/definition/refs/completions bundle | `nlc query inspect --file Program.nl --pos 5:4` |
| `nlc query inspect --summary --file F --pos L:C` | Compact envelope for tooling that only needs the high-level inspection summary | `nlc query inspect --summary --file Program.nl --pos 85:22` |
| `nlc query def --file F --pos L:C` | Definition at position (semantic) | `nlc query def --file Program.nl --pos 5:12` |
| `nlc query def --name N` | Definition by name (search) | `nlc query def --name Person` |
| `nlc query refs --file F --pos L:C` | All references to symbol | `nlc query refs --file Program.nl --pos 5:12` |
| `nlc query completions --file F --pos L:C` | Completions at position | `nlc query completions --file Program.nl --pos 5:12` |
| `nlc query hover --file F --pos L:C` | Signature + docs at position (shared model with LSP) | `nlc query hover --file Program.nl --pos 5:6` |
| `nlc query call-graph --function N` | Callers and callees of a function | `nlc query call-graph --function Main` |
| `nlc query call-graph` | All call edges in the project (--limit N, default 100) | `nlc query call-graph --limit 50` |
| `nlc query implementors --name I` | Concrete types implementing an interface (by name) | `nlc query implementors --name IShape` |
| `nlc query implementors --file F --pos L:C` | Implementors of the interface at a position | `nlc query implementors --file Program.nl --pos 10:11` |

Type-use positions are first-class semantic navigation targets. `type`, `inspect`, `def`, `refs`, and `hover` resolve annotations and type arguments through the same BindingMap/SemanticModel data used by the LSP, including `Person`, `List<Person>`, `Person?`, `Person[]`, and `Func<Person, string>`. Duplicate simple type names in different namespaces/files are resolved by semantic binding, not text search.

`nlc query type` and `nlc query inspect` type results include `nullability` (`unknown`, `null`, `maybeNull`, `notNull`, or `oblivious`) so CLI automation and the LSP can reason about the same null-flow facts.

### Code Quality

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc format` | Format all .nl files | `nlc format` |
| `nlc format <files>` | Format specific files | `nlc format Program.nl` |
| `nlc format --check` | Exit 1 if formatting would change files | `nlc format --check` |
| `nlc format --diff` | Print unified diffs without writing files | `nlc format --diff` |
| `nlc format --stdin` | Format stdin to stdout | `nlc format --stdin < Program.nl` |
| `nlc lint` | Static analysis diagnostics (JSON by default) | `nlc lint` |
| `nlc lint <files>` | Lint specific files | `nlc lint Program.nl` |
| `nlc lint --json` | JSON output with structured envelope | `nlc lint --json` |
| `nlc lint --text` | Human-readable diagnostics | `nlc lint --text` |
| `nlc lint --project <dir>` | Lint a specific project | `nlc lint --project examples/17-issue-tracker/backend` |
| `nlc test` | Run .tests.nl files with the xUnit-backed N# test runner | `nlc test` |
| `nlc test --filter <name>` | Run a subset of tests | `nlc test --filter AddPerson` |
| `nlc test --verbose` | Show individual test results | `nlc test --verbose` |
| `nlc test --coverage` | Unsupported/planned native coverage; exits 1 with text or JSON guidance | `nlc test --coverage --json` |
| `nlc bench` | Run benchmarks from *.bench.nl files (BenchmarkDotNet) | `nlc bench` |
| `nlc bench --list` | Discover benchmark functions without running | `nlc bench --list` |
| `nlc bench --filter <pat>` | Run only matching benchmarks | `nlc bench --filter benchAdd` |
| `nlc bench --export <fmt>` | Export results: json, csv, markdown | `nlc bench --export json` |

### Project Management

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc new <name>` | Create new N# project | `nlc new MyApp` |
| `nlc pack` | Generate a NuGet package from project.yml metadata | `nlc pack` |
| `nlc pack --version <ver>` | Override package version | `nlc pack --version 2.0.0` |
| `nlc pack --output <dir>` | Specify output directory for .nupkg | `nlc pack --output ./artifacts` |
| `nlc pack --include-symbols` | Also produce a .snupkg symbols package | `nlc pack --include-symbols` |
| `nlc doc` | Generate project API documentation | `nlc doc` |
| `nlc doc --json` | Emit a structured doc-generation result | `nlc doc --json` |
| `nlc completion <shell>` | Generate shell completions | `nlc completion zsh` |
| `nlc daemon start` | Start background analysis daemon | `nlc daemon start` |
| `nlc daemon stop` | Stop daemon | `nlc daemon stop` |
| `nlc daemon status` | Show daemon info | `nlc daemon status` |
| `nlc tree` | Show direct dependency tree from `project.yml`; include transitive NuGet packages when MSBuild can resolve the package graph | `nlc tree --json` |

### Public Browser Playground

The public website hosts the browser workbench, not a CLI command. `/playground` is a free-form sample explorer with Monaco syntax highlighting, browser diagnostics, formatting, completions, hover, file tabs, share links, and bounded browser-subset `Run` output. `/tutorial` uses the same workbench for a guided story with gated exercises.

Browser `Run` intentionally supports tutorial-scale code only: functions, `print`, simple control flow, records/classes, object initializers, selected string/numeric helpers, and selected match patterns. Use the local `nlc` toolchain for full CLR execution, build, test execution, NuGet restore, filesystem workflows, and editor integration.

---

## Key Commands In Detail

### `nlc check` — Fast Type-Check

The N# equivalent of `cargo check`. Parses and analyzes first, then verifies IL emission without producing final app artifacts. The tightest feedback loop for development.

```bash
$ nlc check
{
  "schemaVersion": 1,
  "command": "check",
  "ok": true,
  "checkedFiles": 3,
  "projectRoot": "/abs/path/to/project",
  "results": [],
  "summary": { "errors": 0, "warnings": 0, "info": 0 }
}

$ nlc check --text   # with errors
── [NL301] ERROR ──────────────────── Program.nl:2:10 ──
    2 |     x := unknownVar
      |          ^
Undefined identifier 'unknownVar'
```

- Exit code 0 = clean, 1 = errors
- JSON by default, `--text` for Elm-style diagnostics
- Always runs parse + analysis first, then:
  - `il` backend (default): emits a temporary IL assembly to verify the direct backend succeeds

### Backend Selection

Supported backend values:
- `il` — emit IL directly and continue through the selected CLI or SDK/MSBuild flow

Current status:
- `project.yml` backend selection is respected by both the CLI and the MSBuild SDK.
- `nlc check/build/run/test/bench/publish/pack` all support `backend: il` through the native project.yml path.
- `dotnet build`, `dotnet run`, and `dotnet test` work for IL-backed SDK projects.
- Generated-C# export no longer exists as a backend or build path.
- `nlc export csharp` is the only supported product surface for C# generation.

### `nlc fix` — Auto-Apply Suggestions

The N# equivalent of `cargo clippy --fix`. Reads diagnostics, finds available code fixes, and applies them to source files.

**Safety contract** — `nlc fix` never applies destructive edits by default:
- **Default (no flags):** applies only `Safe`-level fixes
- **`--include-review-needed`:** also applies `ReviewNeeded` fixes (e.g. unused import removal, unused variable removal)
- **`SuggestionOnly`:** never written to files — reported in `results` only

```bash
$ nlc fix
{
  "schemaVersion": 2,
  "command": "fix",
  "ok": true,
  "dryRun": false,
  "includeReviewNeeded": false,
  "projectRoot": "/abs/path/to/project",
  "filesModified": 1,
  "results": [
    { "file": "Program.nl", "diagnostic": "NL002", "title": "Add import System.Text", "safety": "safe", "edits": [...] },
    { "file": "Program.nl", "diagnostic": "NL010", "title": "Remove unused import", "safety": "reviewNeeded", "edits": [...] }
  ],
  "fixesApplied": [
    { "file": "Program.nl", "diagnostic": "NL002", "title": "Add import System.Text", "safety": "safe", "edits": [...] }
  ]
}

$ nlc fix --text
Fixed 1 issue in 1 file:
  Program.nl:
    [NL002] Add import System.Text

Skipped 1 fix:
  [NL010] Remove unused import (requires --include-review-needed flag)

$ nlc fix --include-review-needed   # also applies ReviewNeeded fixes
$ nlc fix --dry-run                 # preview without applying; exits 1 if fixes are available
$ nlc fix --file F                  # fix single file
```

**`results` vs `fixesApplied`:**
- `results` — every discovered fix regardless of safety level
- `fixesApplied` — only fixes that passed the safety gate and were (or would be) written to disk

**Built-in lint rules:**

| Code | Severity | Name | Description |
|------|----------|------|-------------|
| NL001 | Error | `unused-variable` | Local variable declared but never read |
| NL002 | Error | `missing-import` | Type used without the required `import` |
| NL003 | Warning | `unnecessary-null-check` | Null check on a value-type literal |
| NL004 | Warning | `async-without-await` | `async` function never uses `await` |
| NL005 | Info | `use-pattern-matching` | Prefer `match` / `is` over if-else chains |
| NL006 | Error | `unreachable-code` | Statements after `return` or `throw` |
| NL008 | Info | `camel-case-local` | Local variable name starts with uppercase (locals use camelCase; PascalCase is for exported declarations) |
| NL010 | Error | `unused-import` | `import` statement for a namespace/file whose symbols are never used in the file. Conservative: only fires for known namespaces (e.g. `System.Collections.Generic`); unknown namespaces are never flagged. |
| NL011 | Warning | `empty-catch` | Catch block with no statements (silently swallows exceptions) |
| NL012 | Info | `unused-parameter` | Function parameter never referenced in the body |
| NL013 | Info | `prefer-interpolation` | String concatenation with `+` where one operand is a string literal |
| NL014 | Info | `unnecessary-type-annotation` | Explicit type annotation on a `let` declaration whose type is trivially obvious from a literal initializer (e.g. `let x: int = 5`) |
| NL015 | Info | `prefer-const` | `let x: T = ...` variable with explicit type annotation that is never reassigned — suggest `const` |
| NL016 | Warning | `redundant-null-check` | Null-equality check on an expression that is always non-null (`new`, array literal, numeric/bool literal) |
| NL018 | Info | `prefer-readonly` | Class field that is only ever assigned inside the `constructor` body — suggest `readonly` modifier |
| NL019 | Info | `empty-block` | Empty `{}` block in function body, `if`/`else`, loops |
| NL020 | Warning | `shadowed-variable` | Local variable declaration shadows a variable in an outer scope |
| NLM111 | Info | `unsafe-value-access` | C# migration smell: direct `.Value` unwrap can throw; prefer `must`, `match`, or an explicit guard |

Compiler diagnostics also include error `NL905` for possible null dereference/index/call access. It is emitted from semantic analysis rather than the linter and is therefore visible through `nlc check`, `nlc query diagnostics`, and LSP diagnostics.

**Currently supported auto-fixes (`nlc fix`):**

| Code | Fix | Safety | Notes |
|------|-----|--------|-------|
| NL001 | Remove unused variable declaration line | `ReviewNeeded` | Uses string matching (may match inside comments/strings) |
| NL002 | Add missing `import` statement | `Safe` | |
| NL003 | Remove unnecessary `== null` / `!= null` clause | `Safe` | |
| NL010 | Remove unused import line | `ReviewNeeded` | Known false positives in NL010 analysis |
| NL011 | Insert `// TODO: handle exception` in empty catch | `Safe` | |
| NL013 | Convert concatenation to interpolation | `SuggestionOnly` | Hint only — no edits applied |
| NL015 | Replace `let` with `const` | `Safe` | |
| NLM111 | Replace `receiver.Value` with `must receiver`; also reports a match-based rewrite suggestion | `ReviewNeeded` + `SuggestionOnly` | ReviewNeeded edit makes the throw explicit; SuggestionOnly carries no edits |
| NL905 | Use null-conditional member/index access | `ReviewNeeded` | Changes result nullability; guard/fallback/assertion alternatives are exposed as suggestion-only actions. |

**`FixSafety` levels** (on `CodeAction`):
- `Safe` — always correct to apply automatically (default `nlc fix` behavior)
- `ReviewNeeded` — likely correct but may need follow-up; requires `--include-review-needed` flag
- `SuggestionOnly` — provides a hint only; never written to files

**LSP behavior:** Safe fixes are marked `isPreferred` in the code action response. SuggestionOnly fixes are marked `disabled` with a reason. ReviewNeeded fixes are neither preferred nor disabled — they appear as normal code actions.

Inline lint suppression is also supported for specific warnings:

```nsharp
// nlc:ignore NL001
unusedVar := 42
```

**The LLM coding loop:**
```bash
# Write code → check → fix → check → done
nlc check        # see error: missing import
nlc fix          # auto-adds import
nlc check        # clean ✓
```

### `nlc query completions` — LLM-Optimized Completions

Returns completions grouped by category. Optimized for LLM consumption — keywords and primitives excluded by default (LLMs already know these).

**Identifier context** (what variables/functions are in scope):
```bash
$ nlc query completions --file Program.nl --pos 15:4
{
  "context": "identifier",
  "completions": {
    "variables": [{"name": "person", "kind": "variable", "type": "Person"}],
    "functions": [{"name": "AddPerson", "kind": "function", "type": "void"}]
  }
}
```

**Member access context** (what members does this type have):
```bash
$ nlc query completions --file PersonService.nl --pos 15:15
{
  "context": "memberaccess",
  "receiver": {"name": "people", "type": "System.Collections.Generic.List`1"},
  "completions": {
    "methods": [
      {"name": "Add", "kind": "method", "type": "void", "parameters": "(item T)"},
      {"name": "Remove", "kind": "method", "type": "bool", "parameters": "(item T)"},
      {"name": "Count", ...}
    ]
  }
}
```

Member access completion resolves the receiver expression semantically, including chained calls and properties such as `message.ToUpper().` or `factory.Create().`. CLI query results and LSP completion/hover use the analyzer's recorded expression types as the source of truth, so duplicate member names on unrelated receiver types do not collapse into name-only matches.

Add `--include-keywords` to also get keywords, primitives, and modifiers.

### `nlc query references` / `refs` — Semantic References

Returns only binding-map-backed references for the symbol at `--file --pos`. It does not grep text, scan comments, or fall back to simple-name matching; if the selected position cannot be tied to a precise compiler binding, the command returns `ok: false` with `error.code: "semanticReferencesUnavailable"`.

Successful results always include the declaration as a reference entry, so an empty result is never presented as a precise semantic answer.

```bash
$ nlc query refs --file Program.nl --pos 5:12
{
  "schemaVersion": 1,
  "command": "references",
  "ok": true,
  "symbol": { "name": "value", "kind": "local", "definedAt": { "file": "Program.nl", "line": 3, "column": 9 } },
  "count": 2,
  "results": [
    { "file": "Program.nl", "line": 3, "column": 9, "length": 5, "isDefinition": true },
    { "file": "Program.nl", "line": 4, "column": 11, "length": 5, "isDefinition": false }
  ]
}
```

### `nlc query inspect` — One Round Trip, Full Context

`inspect` is the LLM-first navigation primitive. It bundles the semantic symbol, resolved type, definition, references summary, and completions for a single cursor position.

```bash
$ nlc query inspect --file Program.nl --pos 85:22
{
  "schemaVersion": 1,
  "command": "inspect",
  "file": "Program.nl",
  "position": { "line": 85, "column": 22 },
  "result": {
    "symbol": { "name": "GetStats", "kind": "function", "definition": { "file": "Services/TaskService.nl", "line": 93, "column": 5 } },
    "type": { "resolvedType": "TaskStats", "kind": "record" },
    "definition": { "file": "Services/TaskService.nl", "line": 93, "column": 5 },
    "references": { "count": 2, "definitionCount": 1, "results": [...] },
    "completions": { "context": "memberaccess", "receiver": "service", "receiverType": "TaskService", "completions": { ... } }
  }
}
```

### `nlc query inspect --summary` — Compact, Stable Envelope

`--summary` keeps the same `schemaVersion`, `command`, `ok`, `file`, and `position` envelope, but replaces the full `result` tree with a compact `summary` object. That makes the output easier to diff, cache, and consume from automation.

```bash
$ nlc query inspect --summary --file Program.nl --pos 85:22
{
  "schemaVersion": 1,
  "command": "inspect",
  "ok": true,
  "file": "Program.nl",
  "position": { "line": 85, "column": 22 },
  "summary": {
    "symbol": { "name": "GetStats", "kind": "function" },
    "type": { "name": "GetStats", "resolvedType": "TaskStats", "kind": "record" },
    "definition": { "name": "GetStats", "kind": "function", "file": "Services/TaskService.nl", "line": 93, "column": 5 },
    "references": {
      "count": 2,
      "definitionCount": 1,
      "files": ["Program.nl", "Services/TaskService.nl"],
      "sample": [ ... ]
    },
    "completions": {
      "context": "memberaccess",
      "receiver": "service",
      "receiverType": "TaskService",
      "totalCount": 6,
      "groupCounts": { "functions": 2, "properties": 4 },
      "groups": {
        "functions": ["GetStats", "CreateTask"],
        "properties": ["Total", "Todo", "InProgress", "Done"]
      }
    }
  }
}
```

### `nlc query batch` — One Project Load, Many Queries

`batch` is the LLM-facing orchestration surface. It takes a JSON array or `{ "requests": [...] }` file, runs each request against the same project snapshot, and returns one stable envelope with per-item responses nested under `results[].response`. Each request can also carry an optional `id`, which is echoed back at `results[].id` for correlation.

```json
[
  { "command": "inspect", "file": "Program.nl", "pos": "86:39", "summary": true },
  { "command": "doc", "query": "Console.WriteLine" },
  { "command": "type", "file": "Program.nl", "pos": "83:1" }
]
```

```bash
$ nlc query batch --requests requests.json
{
  "schemaVersion": 1,
  "command": "batch",
  "ok": false,
  "projectRoot": "/repo/examples/17-issue-tracker/backend",
  "requestCount": 3,
  "successCount": 2,
  "failureCount": 1,
  "results": [
    {
      "index": 0,
      "request": { "command": "inspect", "file": "Program.nl", "pos": "86:39", "summary": true },
      "ok": true,
      "response": { "...": "full inspect --summary envelope" }
    },
    {
      "index": 2,
      "request": { "command": "type", "file": "Program.nl", "pos": "83:1" },
      "ok": false,
      "response": { "...": "full structured noSymbol error envelope" }
    }
  ]
}
```

Supported request commands:
- `symbols`
- `outline`
- `diagnostics`
- `type`
- `inspect`
- `definition` / `def`
- `references` / `refs`
- `completions`
- `doc`

### `nlc query hover` — Signature and Docs at a Position

Returns the signature, kind, definition location, and any inline doc comment for the symbol at a cursor position. Shares its semantic model with the LSP `HoverHandler`.

```bash
$ nlc query hover --file Program.nl --pos 5:6
{
  "schemaVersion": 1,
  "command": "hover",
  "ok": true,
  "file": "Program.nl",
  "position": { "line": 5, "column": 6 },
  "result": {
    "signature": "func hi(): int",
    "documentation": "A simple hello-world program demonstrating functions and string interpolation",
    "definedIn": "Program.nl",
    "kind": "function"
  }
}
```

Exit code 0 on success, 1 with a structured `noSymbol` error envelope if there is no symbol at the given position.

### `nlc query call-graph` — Callers and Callees

Walks all ASTs in the project to build a call graph. Use `--function` to focus on a specific function; omit it for a project-wide edge list. Use `--limit` (default 100) to cap result size.

```bash
$ nlc query call-graph --function Main
{
  "schemaVersion": 1,
  "command": "callGraph",
  "ok": true,
  "function": "Main",
  "callers": [],
  "callees": [
    { "name": "hi", "file": "Program.nl", "line": 19, "column": 9 }
  ],
  "truncated": false
}
```

### `nlc query implementors` — Concrete Types Implementing an Interface

Finds all class, struct, and record declarations in the project that list a given interface in their inheritance chain.

```bash
$ nlc query implementors --name IShape
{
  "schemaVersion": 1,
  "command": "implementors",
  "ok": true,
  "interface": "IShape",
  "results": [
    { "typeName": "Circle", "kind": "class", "file": "RecordsAndInterfaces.nl", "line": 21, "column": 1 }
  ]
}
```

Also supports position-based lookup (`--file F --pos L:C`) which resolves the interface at that position first.

### `nlc query symbols --filter` — Fuzzy/Glob Symbol Search

The `symbols` subcommand now accepts `--filter <pattern>`:
- Patterns containing `*` are treated as globs (`*Person*` matches any name containing `Person`)
- Bare strings are treated as case-insensitive substring matches
- Results are capped at 200

```bash
$ nlc query symbols --filter '*Person*'     # glob wildcard
$ nlc query symbols --filter Person         # substring
$ nlc query symbols --filter 'Get*'         # prefix glob
```

### `nlc format` — Canonical Formatting With CI Support

`format` now supports the standard cargo/gofmt-style workflows:

```bash
nlc format           # rewrite files in place
nlc format --check   # exit 1 if any file would change
nlc format --diff    # show unified diffs without writing files
nlc format --stdin < Program.nl
```

- `--check` is the preferred CI flag
- `--verify-no-changes` remains as a compatibility alias
- `--diff` prints unified hunks against the formatter output
- `./scripts/test-all.sh` includes a formatting gate for `examples`, `templates`, and `tests/fixtures/issue-tracker`; intentionally malformed diagnostic/migration fixtures are not part of that gate.

### `nlc tree` — Dependency Tree

`tree` is an active dependency-inspection command, not future work:

```bash
nlc tree
nlc tree --depth 1
nlc tree --json
```

Behavior:

- In csproj-free projects, `nlc tree` reads `project.yml` and lists direct runtime dependencies (`nuget`, `framework`, `project`, and `dll` references).
- If a minimal MSBuild project file is present and `dotnet list package` succeeds, `nlc tree` restores the `project.yml` projection and asks `dotnet list package --include-transitive --format json` for direct and transitive NuGet packages.
- JSON output uses schema version `2` and exposes `capabilities.transitiveNuGetDependencies` plus `limitations[]` so automation can distinguish "direct dependency list available" from "full transitive NuGet graph available."
- The command does not yet reconstruct nested package-to-package edges for csproj-free `project.yml` projects without an MSBuild project file; it names that limitation precisely instead of treating the entire command as absent.

### `nlc test` — Filtered, Developer-Friendly Test Runs

`test` now supports focused development loops:

```bash
nlc test --filter "should add"
nlc test --verbose
```

- `--filter` matches both test display names and fully-qualified test names
- `--verbose` shows individual test results without changing the test pipeline
- Native coverage is not available in `nlc test` yet. `--coverage` and `--coverage-report` are accepted only to fail honestly: exit code 1, a clear text error by default, and the same message in the schemaVersion 1 JSON `error` field when `--json` is present.

### `nlc build` — Release Builds and Verbose Output

Build supports Go/Rust-style configuration flags:

```bash
nlc build                # debug build (default)
nlc build --backend il   # direct IL build
nlc build --release      # Release configuration/output layout
nlc build --verbose      # detailed native resolver/build output
nlc build --release --verbose
```

- All builds report elapsed time on completion (e.g., `Build successful! (release) [2.3s]`)
- `il` backend parses/analyzes the project, emits a managed assembly directly, and writes `.runtimeconfig.json` for executables
- `--release` selects the Release configuration and native output layout (`bin/Release/<tfm>` unless `--output` is provided); it is not a separate IL optimizer today
- `--verbose` enables detailed native resolver/build output

### `nlc publish` — Framework-Dependent Deployment Artifacts

`nlc publish` builds through the IL backend and writes framework-dependent artifacts. Supported shapes today:

```bash
nlc publish --output ./dist
nlc publish --configuration Release --output ./dist
nlc publish --runtime <current-rid> --output ./dist
```

- Without `--runtime`, output is portable framework-dependent: run it with `dotnet <assembly>.dll` on a compatible .NET installation.
- With `--runtime`, the requested RID must equal the current host RID reported by .NET. The command adds a small framework-dependent launcher beside the `.dll`.
- Cross-runtime publishing fails before build with guidance that names both the requested RID and the current host RID.
- `--self-contained` is not implemented in `nlc publish`; it exits 1 with guidance instead of producing a directory that only looks self-contained.

### `nlc clean` — Build Artifact Cleanup

Equivalent to `cargo clean` / `go clean` for local artifacts:

```bash
nlc clean
nlc clean --all
```

- Removes `bin/`, `obj/`, `nsharp/`, and `.nlc/` directories under the project root
- `--all` also clears NuGet caches via `dotnet nuget locals all --clear`

### `nlc watch` — Re-run On Change

Watch the project tree and re-run a command after a debounce window:

```bash
nlc watch check
nlc watch build
nlc watch test --filter "should add"
```

- Watches `.nl`, `project.yml`, and `.editorconfig`
- Defaults to a 250ms debounce
- `--max-runs` is available for scripts and test harnesses

### `nlc doc` — Project API Documentation

Generate a lightweight HTML API reference directly from the project symbol graph:

```bash
nlc doc
nlc doc --open
nlc doc --json
```

- Default output directory: `./nsharp/docs`
- Generates `index.html` plus per-symbol pages
- `--json` emits a stable result envelope containing the generated paths

### `nlc query diagnostics` — Elm-Level Error Output

The richest error output of any .NET language. Every diagnostic includes source snippets, explanations, suggestions, type info, and documentation URLs.

```bash
$ nlc query diagnostics --text
── [NL202] ERROR ──────────────── Program.nl:10:12 ──
    10 |     x := "hello"
              ^^^^^^
Type mismatch: expected 'int' but got 'string'

Expected: `int`
  Actual: `string`

Hint: N# uses ':=' for declaration with inference.
Suggestion: Convert with int.Parse("hello") or change the type.
See: https://nsharp.dev/errors/NL202
```

### `nlc query symbols` — Project Overview

The first thing an LLM should call when entering a project. Returns all symbols with types, members, parameters.

```bash
$ nlc query symbols
{
  "schemaVersion": 1,
  "results": [
    {"name": "Person", "kind": "record", "file": "Models/Person.nl", "line": 4,
     "members": [
       {"name": "Name", "kind": "property", "type": "string"},
       {"name": "GetInfo", "kind": "function", "type": "string", "parameters": []}
     ]},
    {"name": "Main", "kind": "function", "file": "Program.nl", "line": 10}
  ]
}
```

---

## JSON Schema Discipline

All `nlc check`, `nlc fix`, `nlc lint`, and `nlc tree --json` commands output JSON with a versioned envelope:

```json
{
  "schemaVersion": 1,
  "command": "<command-name>",
  "ok": true,
  ...
}
```

- `schemaVersion` is always present and will increment on breaking changes
- All project-scoped file paths are normalized to forward-slash separators
- `projectRoot` is emitted as an absolute path when the command has a project root
- Coordinates are 1-based (line 1, column 1)
- `null` fields are omitted from output

`check` envelope:
- `command`
- `projectRoot`
- `checkedFiles`
- `ok`
- `results`
- `summary`

`fix` envelope:
- `command`
- `projectRoot`
- `dryRun`
- `includeReviewNeeded`
- `ok`
- `filesModified`
- `results`
- `fixesApplied`

`lint` envelope:
- `command`
- `projectRoot`
- `lintedFiles`
- `ok`
- `results`
- `summary`

`tree` envelope (`schemaVersion: 2`):
- `command`
- `ok`
- `projectRoot`
- `project`
- `maxDepth`
- `capabilities`
- `dependencies`
- `transitiveDependencies`
- `summary`
- `limitations`

Migration note: the earlier tree JSON wrapper exposed raw `dotnet list package` output under `packages` when a `.csproj` was present. Schema version `2` replaces that with stable `dependencies` / `transitiveDependencies`, explicit `capabilities`, and project.yml support for csproj-free projects.

`query` expectations:
- Success responses include `ok: true` and command-specific payloads
- Failures use `ok: false` plus `error.message`
- Position-based misses use `error.code: "noSymbol"` plus structured `error.details.file` / `error.details.position`
- Reference positions that resolve by definition fallback but not by precise binding use `error.code: "semanticReferencesUnavailable"` and do not return text-search guesses
- `outline` normalizes the file path relative to the project root
- Project-aware query results normalize file paths to project-relative form where the command can resolve them

`inspect` envelope:
- `command`
- `file`
- `position`
- `result.symbol`
- `result.type`
- `result.definition`
- `result.references`
- `result.completions`

`inspect --summary` envelope:
- `command`
- `file`
- `position`
- `summary`
- `summary.references.count` / `summary.references.definitionCount`
- `summary.completions.totalCount`
- `summary.completions.groupCounts`
- `summary.completions.groups`

`batch` envelope:
- `command`
- `projectRoot`
- `requestCount`
- `successCount`
- `failureCount`
- `results`
- `results[].request`
- `results[].ok`
- `results[].response`

## Local Contributor Install

Use [install-local.sh](/Users/spencer/repos/nsharplang/install-local.sh) as the contributor bootstrap. It builds packages from the current checkout, refreshes the local N# package cache, publishes `nlc` and `nsharp-lsp` as framework-dependent apps, installs launchers under `~/.nsharp/bin`, and writes `~/.nsharp/env` so future shells put those launchers on PATH.

```bash
./install-local.sh
```

The script:
- refreshes packages and toolset apps through the shared `scripts/lib/toolset.sh` helpers
- refreshes the local `~/.nsharp/packages` package cache used by generated projects
- verifies `nlc doctor --skip-vscode` by default
- supports `--with-vscode` when the local VS Code extension should also be packaged and installed

For a CLI-only reinstall while debugging packaging, use `./install-local.sh --skip-vscode --no-path-update`.

---

## Architecture

### Code Intelligence Stack

```
nlc query <cmd>
  → QueryCommand.cs (CLI dispatch)
    → CodeIntelligenceService (shared engine)
      → MultiFileCompiler.CompileForAnalysis()
        → Lexer → Parser → Analyzer
      → ProjectSnapshot (immutable analysis result)
        → CompilationUnits, SemanticModels, BindingMap, Errors
    → OutputFormatter (JSON or Elm-style text)
```

### Key Files

| File | Purpose |
|------|---------|
| `src/NSharpLang.Cli/Program.cs` | CLI entry point, command dispatch |
| `src/NSharpLang.Cli/Commands/QueryCommand.cs` | All `nlc query` subcommands |
| `src/NSharpLang.Cli/Commands/FixCommand.cs` | `nlc fix` command |
| `src/NSharpLang.Cli/Commands/DaemonCommand.cs` | `nlc daemon` commands |
| `src/NSharpLang.Cli/Daemon/DaemonServer.cs` | Background daemon (Unix socket) |
| `src/NSharpLang.Cli/Daemon/DaemonClient.cs` | Daemon client for QueryCommand |
| `src/NSharpLang.Compiler/CodeIntelligence/CodeIntelligenceService.cs` | Shared analysis engine |
| `src/NSharpLang.Compiler/CodeIntelligence/CompletionEngine.cs` | LLM-optimized completions |
| `src/NSharpLang.Compiler/CodeIntelligence/OutputFormatter.cs` | JSON + Elm-style formatters |
| `src/NSharpLang.Compiler/CodeIntelligence/FixApplicator.cs` | TextEdit application |
| `src/NSharpLang.Compiler/CodeIntelligence/Models.cs` | Result types (SymbolResult, etc.) |
| `src/NSharpLang.Compiler/CodeFix.cs` | TextEdit, CodeAction, CodeFixProviders |
| `src/NSharpLang.Compiler/BindingMap.cs` | Semantic symbol resolution |

### Testing

| File | What it tests |
|------|--------------|
| `tests/QueryIntegrationTests.cs` | Real example projects: symbols, outline, diagnostics, definition, references, completions, binding map, unhappy paths |
| `tests/CodeIntelligenceTests.cs` | OutputFormatter JSON/text formatting |
| `tests/CodeFixTests.cs` | CodeFixProviders (auto-import, unused variable removal) |

---

## Daemon Mode

The daemon caches project analysis and serves queries via Unix domain socket. JSON `nlc query` commands reuse it only when one is already running; the CLI does not auto-start it. The daemon auto-exits after 30 minutes idle.

```bash
nlc daemon start     # explicit start
nlc daemon stop      # explicit stop
nlc daemon status    # show pid, uptime, cached files

# Queries auto-connect to daemon when running:
nlc query symbols    # fast response from cache
nlc query refs --file Program.nl --pos 5:4
nlc query inspect --file Program.nl --pos 5:4
```

Socket: `{projectRoot}/.nlc/daemon.sock`
Protocol: JSON-RPC over Unix socket

---

## Comparison with Go and Rust

| Feature | Go | Rust | N# |
|---------|-----|------|----|
| Fast type-check | `go build` | `cargo check` | `nlc check` |
| Auto-fix | — | `cargo clippy --fix` (lints) | `nlc fix` (compiler + linter) |
| Release build | implicit | `cargo build --release` | `nlc build --release` (Release configuration/output layout; no separate IL optimizer yet) |
| Verbose build | `go build -v` | `cargo build -v` | `nlc build --verbose` |
| Build timing | external (`time`) | `cargo build --timings` | Built-in (always shown) |
| Test coverage | `go test -cover` | `cargo tarpaulin` | Planned native coverage; `nlc test --coverage` exits 1 with guidance today |
| Code intelligence CLI | Need `gopls` server | Need `rust-analyzer` server | `nlc query` (single-shot JSON) |
| Structured output | No | No | Yes (versioned JSON schemas) |
| Canonical format | `gofmt` | `rustfmt` | `nlc format` |
| Elm-level errors | No | Good but no JSON | `nlc query diagnostics` |

---

*Last Updated: 2026-03-30*
