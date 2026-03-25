# N# CLI Toolchain (`nlc`)

**Status:** Production-ready LLM-first CLI with code intelligence, auto-fix, and daemon mode.
**Test count:** 944+ tests passing, 0 failures.

The `nlc` CLI is designed for two audiences: humans at a terminal and LLMs navigating code via bash. `nlc query`, `nlc check`, and `nlc fix` all output structured JSON by default with a versioned envelope. Add `--text` for human-readable output.

---

## Command Reference

### Build & Run

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc build` | Compile all .nl files via MSBuild | `nlc build` |
| `nlc build <file>` | Compile single file | `nlc build Program.nl` |
| `nlc run` | Compile and run project | `nlc run` |
| `nlc run <file>` | Compile and run single file | `nlc run Program.nl` |
| `nlc transpile <file>` | Print generated C# to stdout | `nlc transpile Program.nl` |
| `nlc check` | Fast type-check (JSON by default) | `nlc check` |
| `nlc fix` | Auto-apply compiler suggestions (JSON by default) | `nlc fix` |

### Code Intelligence (`nlc query`)

All query commands output **JSON by default** with a versioned envelope (`schemaVersion: 1`). Add `--text` for human-readable output.

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc query symbols` | List all symbols in project | `nlc query symbols` |
| `nlc query symbols --file F` | Symbols in one file | `nlc query symbols --file Program.nl` |
| `nlc query symbols --kind K` | Filter by kind | `nlc query symbols --kind function` |
| `nlc query outline <file>` | File structure (imports, declarations) | `nlc query outline Program.nl` |
| `nlc query diagnostics` | Errors/warnings with Elm-level context | `nlc query diagnostics` |
| `nlc query diagnostics --text` | Elm-style terminal output | `nlc query diagnostics --text` |
| `nlc query type --file F --pos L:C` | Type info at position | `nlc query type --file Program.nl --pos 5:4` |
| `nlc query inspect --file F --pos L:C` | One-shot symbol/type/definition/refs/completions bundle | `nlc query inspect --file Program.nl --pos 5:4` |
| `nlc query def --file F --pos L:C` | Definition at position (semantic) | `nlc query def --file Program.nl --pos 5:12` |
| `nlc query def --name N` | Definition by name (search) | `nlc query def --name Person` |
| `nlc query refs --file F --pos L:C` | All references to symbol | `nlc query refs --file Program.nl --pos 5:12` |
| `nlc query completions --file F --pos L:C` | Completions at position | `nlc query completions --file Program.nl --pos 5:12` |

### Code Quality

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc format` | Format all .nl files | `nlc format` |
| `nlc format <files>` | Format specific files | `nlc format Program.nl` |
| `nlc lint` | Static analysis diagnostics | `nlc lint` |
| `nlc lint <files>` | Lint specific files | `nlc lint Program.nl` |
| `nlc test` | Run .tests.nl files with XUnit | `nlc test` |

### Project Management

| Command | Purpose | Example |
|---------|---------|---------|
| `nlc new <name>` | Create new N# project | `nlc new MyApp` |
| `nlc daemon start` | Start background analysis daemon | `nlc daemon start` |
| `nlc daemon stop` | Stop daemon | `nlc daemon stop` |
| `nlc daemon status` | Show daemon info | `nlc daemon status` |

---

## Key Commands In Detail

### `nlc check` — Fast Type-Check

The N# equivalent of `cargo check`. Parses and analyzes without transpiling or invoking `dotnet build`. The tightest feedback loop for development.

```bash
$ nlc check
{
  "schemaVersion": 1,
  "command": "check",
  "checkedFiles": 3,
  "ok": true,
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
- Uses `CompileForAnalysis()` internally (parse + analyze, skip transpile)

### `nlc fix` — Auto-Apply Suggestions

The N# equivalent of `cargo clippy --fix`. Reads diagnostics, finds available code fixes, and applies them to source files.

```bash
$ nlc fix
{
  "schemaVersion": 1,
  "command": "fix",
  "dryRun": false,
  "ok": true,
  "filesModified": 1,
  "fixesApplied": [
    { "file": "Program.nl", "diagnostic": "NL002", "title": "Add import System.Collections.Generic" }
  ]
}

$ nlc fix --text
Fixed 1 issue in 1 file:
  Program.nl:
    [NL002] Add import System.Collections.Generic

$ nlc fix --dry-run    # preview without applying
$ nlc fix --file F     # fix single file
```

**Currently supported fixes:**
- **NL002** — Missing import: auto-adds `import System.Collections.Generic`, `import System.IO`, etc.
- **NL001** — Unused variable: removes the declaration line

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

Add `--include-keywords` to also get keywords, primitives, and modifiers.

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
    "definition": { "name": "GetStats", "kind": "function", "file": "Services/TaskService.nl", "line": 93, "column": 5 },
    "references": { "count": 2, "definitionCount": 1, "results": [...] },
    "completions": { "context": "memberaccess", "receiver": "service", "receiverType": "TaskService", "completions": { ... } }
  }
}
```

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

All `nlc query`, `nlc check`, and `nlc fix` commands output JSON with a versioned envelope:

```json
{
  "schemaVersion": 1,
  "command": "<command-name>",
  ...
}
```

- `schemaVersion` is always present and will increment on breaking changes
- All paths are relative to project root
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
- `ok`
- `filesModified`
- `fixesApplied`

`inspect` envelope:
- `command`
- `file`
- `position`
- `result.symbol`
- `result.type`
- `result.definition`
- `result.references`
- `result.completions`

## Local Install

Use [scripts/install-local-nlc.sh](/Users/spencer/repos/nsharplang/scripts/install-local-nlc.sh) to make the current repo’s CLI the global `nlc` in one step.

```bash
./scripts/install-local-nlc.sh
```

The script:
- builds and packs the local CLI
- clears stale dotnet-tool caches for `NSharpLang.Cli`
- reinstalls the global tool from the repo package
- verifies the installed `nlc`

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

The daemon caches project analysis and serves queries via Unix domain socket. Auto-starts on first `nlc query` call, auto-exits after 30 minutes idle.

```bash
nlc daemon start     # explicit start
nlc daemon stop      # explicit stop
nlc daemon status    # show pid, uptime, cached files

# Queries auto-connect to daemon when running:
nlc query symbols    # fast response from cache
```

Socket: `{projectRoot}/.nlc/daemon.sock`
Protocol: JSON-RPC over Unix socket

---

## Comparison with Go and Rust

| Feature | Go | Rust | N# |
|---------|-----|------|----|
| Fast type-check | `go build` | `cargo check` | `nlc check` |
| Auto-fix | — | `cargo clippy --fix` (lints) | `nlc fix` (compiler + linter) |
| Code intelligence CLI | Need `gopls` server | Need `rust-analyzer` server | `nlc query` (single-shot JSON) |
| Structured output | No | No | Yes (versioned JSON schemas) |
| Canonical format | `gofmt` | `rustfmt` | `nlc format` |
| Elm-level errors | No | Good but no JSON | `nlc query diagnostics` |

---

*Last Updated: 2026-03-25*
