# N# (NewLang Sharp)

**A pragmatic CLR language with small syntax, a rich type system, project-first tooling, and an opt-in systems performance lane.**

N# is in active development. The repository has a working compiler, SDK, CLI, templates, VS Code support, and examples, but not every product gate is launch-green yet. Treat this README as the current developer-facing map, not a claim that every planned language feature or IDE workflow is complete.

## Quick Start

### 1. One-Time Setup

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"
nlc doctor
```

This public setup path installs `nlc`, `nsharp-lsp`, the N# templates, SDK restore support, and the VS Code extension when the `code` CLI is available. It also sources `~/.nsharp/env` so this shell has the N# launcher PATH and .NET root settings, and it wires the same env file into future shells.

Contributors working from source should clone the repo and run `./install-local.sh`; that path builds `nlc`, `nsharp-lsp`, packages, templates, local launchers, and the VS Code extension from the checkout when the `code` CLI is available.

### 2. Create Project

```bash
nlc new MyApp
cd MyApp
```

**Files created:**
- `project.yml` - all project configuration lives here
- `Program.nl` - N# source
- `global.json` - SDK selection
- `NuGet.config` - package sources when using local/private packages

Fresh N# projects are intentionally `.csproj`-free. `nlc build`, `nlc run`, and `nlc test` read `project.yml` directly and do not generate MSBuild project files. A minimal `<Project Sdk="NSharpLang.Sdk" />` file remains an optional compatibility entry point for direct `dotnet build` workflows.

### 3. Build and Run

```bash
nlc build
nlc run
```

For compiler debugging before reinstalling the local tool, you can still run the CLI project directly:

```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- build
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- run
```

---

## Philosophy

- **Small syntax**: Go-inspired conveniences (`:=`, no semicolons, convention-based visibility)
- **Pragmatic .NET**: embraces the CLR, nullable reality, NuGet, and MSBuild
- **Project-first workflow**: `project.yml` owns user-facing configuration; `.csproj` stays minimal
- **Tooling matters**: `nlc check`, `nlc query`, formatting, tests, and VS Code support are product surface, not afterthoughts
- **Evidence over hype**: docs should describe what is implemented and tested, not what the language hopes to become

## Why N#?

N# borrows Go's ethos — a tighter developer experience, fast tooling, and performance as a
first-class concern — but it is **not** "Go for .NET": it pairs that small syntax with a much
richer type system and an opt-in systems lane for hot-path code. The goal is to emit types and assemblies that fit normal .NET
workflows while giving N# source a smaller, more direct shape.

| Area | N# direction |
|------|--------------|
| **Unions** | Discriminated unions that compile into CLR shapes |
| **Records/classes** | Familiar .NET object model with terser syntax |
| **Async** | `Task`/`ValueTask` interop instead of a separate async ecosystem |
| **Nullability** | Works with .NET nullable reference types and explicit checks |
| **Visibility** | Go-style casing by default, explicit modifiers for interop escapes |
| **Systems lane** | Opt-in `[hot]`/`[boundary]` cost contracts, `Result<T,E>`, spans/`ref struct`, governed `unsafe`, SIMD auto-vectorization |

## Quick Example

```nsharp
// Discriminated unions with pattern matching
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

// Duck interfaces (structural typing)
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string => "file contents"
}

func Process(r: IReader) {
    print r.Read()
}

func main() {
    // Variables with type inference
    name := "Alice"
    items := [1, 2, 3, 4, 5]
    print $"{name} has {items.Length} items"

    result := new Result.Success<int> { value: 42 }
    message := match result {
        Result.Success { value: x } => $"Got {x}",
        Result.Failure { error: e } => $"Error: {e}"
    }
    print message

    Process(new FileReader())
}
```

## Installation

### One-Liner

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"
```

This installs templates, the `nlc` CLI, the language server, a reusable `NuGet.config` under `~/.nsharp/`, and the VS Code extension when the `code` CLI is available. The installer first tries the Marketplace extension ID `nsharp.nsharp`, then falls back to the latest GitHub Release asset named `nsharp.vsix`.

### From The N# CLI

```bash
nlc new MyApp
cd MyApp

# Build and run
nlc build
nlc run
```

`nlc new` writes `project.yml`, `.nl` source, `global.json`, and `NuGet.config`; it does not write a user-authored `.csproj`. The `dotnet new nsharp-*` templates remain installed for .NET ecosystem interop, but `nlc new`, `nlc build`, `nlc run`, and `nlc test` are the first-class project path.

The `NSharpLang.Sdk` package remains available for direct `dotnet build` compatibility, but the normal `nlc` path compiles directly from `project.yml`.

### Build from Source

```bash
git clone <repo-url>
cd nsharplang
./install-local.sh
nlc doctor
```

For compiler-only debugging before reinstalling launchers, use `dotnet build` and `dotnet test tests/Tests.csproj`. Do not hard-code test totals in docs; they move quickly. Use the current `dotnet test` output for release/talk evidence.

### CLI Usage

```bash
# Compile a project or single file
nlc build [file]

# Build and run
nlc run [file]

# Fast check without building
nlc check --text

# Code intelligence for humans, editors, and agents
nlc query help

# Build with detailed output/timings for debugging
nlc build --verbose --timings
```

There is intentionally no public source-conversion workflow. Write N# directly, use `nlc check`,
`nlc fix --dry-run`, `nlc format --check`, and tests for feedback. Direct IL emission is the
product build path.

## Current CLI Surface

Current `nlc --help` lists these top-level commands:

```text
build run new init test format lint clean watch doc completion check fix query daemon add tidy remove update publish tree audit env doctor restore pack help
```

`nlc query help` lists these query commands:

```text
batch symbols outline ast diagnostics type inspect definition/def references/refs completions doc hover call-graph implementors perf trusted help
```

Shell completions are generated from the same registry. When docs drift, prefer the CLI help and `CommandRegistry` as the source of truth.

## Key Features

### Modern Syntax
- Type inference with `:=`
- No semicolons required
- String interpolation
- Pattern matching with exhaustiveness checks in supported cases
- Collection expressions and list patterns where covered by the compiler/tests

### Advanced Types
- Discriminated unions
- Duck interfaces / structural typing
- Records and classes (incl. `ref struct`)
- Generics with constraints, function/operator overloading, conversion operators
- Required/init properties, indexers, type aliases

### Systems N# (opt-in performance lane)
- `[hot]`/`[boundary]` cost contracts with the `NSYS###` effect model
- Allocation-free `Result<T,E>`, explicit `alloc`/`stackalloc`
- `ref struct`, lifetime-checked spans, governed `unsafe` + `[trusted]`
- SIMD auto-vectorization for supported reduction kernels — see [Systems N# guide](website/docs/systems.md)

### .NET Interop
- CLR assemblies where supported
- Ref/out parameters for .NET interop
- Operator overloads and extension methods in covered scenarios
- Async/await over .NET tasks

## Examples

See `examples/` for curated samples, including:
- **01-hello-world/** - small console projects
- **04-pattern-matching/** - pattern matching and exhaustiveness examples
- **05-unions/** - discriminated unions
- **12-multi-file-projects/** - multi-file apps and tests
- **14-minimal-api/** - minimal API example
- **16-task-cli/** and **17-issue-tracker/** - larger app-shaped examples

Run the repo gates before presenting examples as release evidence; examples are code, not marketing proof by themselves.

## Status

N# is an active pre-release language/toolchain. Current strengths include a working compiler pipeline, project.yml-first SDK flow, a broad `nlc` command surface, query/diagnostic JSON for tooling, and a growing VS Code experience. Current launch caveats include full-suite reliability, IDE visual verification, packaging/public-feed proof, and feature-specific edge cases documented in `memory/limitations.md` and `docs/audits/`.

Use exact command output for current counts and evidence:

```bash
dotnet test tests/Tests.csproj
./scripts/test-all.sh
```

`./scripts/test-all.sh` runs the full gate in an isolated temporary workspace
with separate HOME/temp/package state and validates a content-addressed pass
cache before returning a cached result. Use `--no-cache`, `--rebuild-cache`, or
`--clean` to force a fresh isolated run. Use `./scripts/test-all.sh --commit`
before committing; cached results are a development fast path, not a
pre-commit or release gate.

Do not claim the whole product is launch-ready/full-suite-green unless `./scripts/test-all.sh` completes cleanly in the target environment.

## CI/CD

N# projects are intended to work with standard .NET CI/CD tools. Template and example coverage exists in `ci/`, but verify the specific workflow before promising it in a release note or customer-facing page.

See [CI/CD Guide](website/docs/ci-cd.md) for current setup notes.

## Documentation

- **website/docs/language-tour.md** - the main language reference with runnable examples
- **website/docs/systems.md** - Systems N#: the opt-in high-performance lane
- **website/docs/types.md**, **functions.md**, **pattern-matching.md** - deep-dive language guides
- **website/docs/cli-reference.md** - CLI command reference aligned to current help/completions
- **memory/** - implementation notes, component docs, and known limitations
- **docs/audits/** - Systems N# adversarial review + verification evidence
- **docs/design/** - current design notes and audited systems-language documents
- **website/docs/** - the canonical language guides (the published documentation source)

## Architecture

```text
.nl source → Lexer → Parser → Analyzer → IL compiler → .NET assembly
```

The compiler emits CLR IL directly (`--backend il`, the default).
