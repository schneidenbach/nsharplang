# N# (NewLang Sharp)

**Go for .NET: a pragmatic CLR language with small syntax, project-first tooling, and C# interop.**

N# is in active development. The repository has a working compiler, SDK, CLI, templates, VS Code support, and examples, but not every product gate is launch-green yet. Treat this README as the current developer-facing map, not a claim that every planned language feature or IDE workflow is complete.

## Quick Start

### 1. One-Time Setup

```bash
git clone <repo-url>
cd nsharplang
./scripts/setup-local.sh
```

This local setup path is for contributors and private-feed consumers. Public package availability should be verified before using the NuGet/template commands outside this repo.

### 2. Create Project

```bash
dotnet new nsharp-console -o MyApp
cd MyApp
```

**Files created:**
- `project.yml` - all project configuration lives here
- `Program.nl` - N# source
- `global.json` - SDK selection
- `NuGet.config` - package sources when using local/private packages

Fresh N# projects are intentionally `.csproj`-free. `nlc build`, `nlc run`, and `nlc test` generate a minimal `*.g.csproj` build artifact only when MSBuild needs one.

### 3. Build and Run

```bash
nlc build
nlc run
```

For repo-local CLI testing, use:

```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- build
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- run
```

---

## Philosophy

- **Small syntax**: Go-inspired conveniences (`:=`, no semicolons, convention-based visibility)
- **Pragmatic .NET**: embraces the CLR, nullable reality, NuGet, MSBuild, and C# interop
- **Project-first workflow**: `project.yml` owns user-facing configuration; `.csproj` stays minimal
- **Tooling matters**: `nlc check`, `nlc query`, formatting, tests, and VS Code support are product surface, not afterthoughts
- **Evidence over hype**: docs should describe what is implemented and tested, not what the language hopes to become

## Why N#?

N# explores a tighter, Go-flavored developer experience for .NET while keeping C# interop as a core design constraint. The goal is to emit types and assemblies that fit normal .NET workflows while giving N# source a smaller, more direct shape.

| Area | N# direction |
|------|--------------|
| **Unions** | Discriminated unions that compile into C#-consumable shapes |
| **Records/classes** | Familiar .NET object model with terser syntax |
| **Async** | `Task`/`ValueTask` interop instead of a separate async ecosystem |
| **Nullability** | Works with .NET nullable reference types and explicit checks |
| **Visibility** | Go-style casing by default, explicit modifiers for interop escapes |

## Quick Example

```nsharp
// Variables with type inference
name := "Alice"
items := [1, 2, 3, 4, 5]

// Discriminated unions with pattern matching
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

message := result match {
    Result.Success { value: x } => $"Got {x}",
    Result.Failure { error: e } => $"Error: {e}"
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

Process(new FileReader())
```

## Installation

### One-Liner (Private Feed)

Requires the [GitHub CLI](https://cli.github.com/) authenticated with access to this repository/package feed:

```bash
bash <(gh api repos/schneidenbach/nsharplang/contents/scripts/setup-consumer.sh -H "Accept: application/vnd.github.raw")
```

This installs templates, the `nlc` CLI, the language server, and a reusable `NuGet.config` under `~/.nsharp/` for the private feed path.

### From Templates

```bash
# Install templates from the configured package source
dotnet new install NSharpLang.Templates

# Create a new console app
dotnet new nsharp-console -o MyApp
cd MyApp

# Build and run
nlc build
nlc run
```

`dotnet new nsharp-*` writes `project.yml`, `.nl` source, `global.json`, and `NuGet.config`; it does not write a user-authored `.csproj`. Use `nlc build`, `nlc run`, and `nlc test` for the fresh-project path.

The SDK (`NSharpLang.Sdk`) is restored from the configured package source when you build.

### Build from Source

```bash
git clone <repo-url>
cd nsharplang
dotnet build
dotnet test tests/Tests.csproj
```

Do not hard-code test totals in docs; they move quickly. Use the current `dotnet test` output for release/talk evidence.

### CLI Usage

```bash
# Compile a project or single file
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- build [file]

# Build and run
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- run [file]

# Fast check without building
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --text

# Code intelligence for humans, editors, and agents
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query help

# Export C# for inspection or migration review
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- export csharp --project . --output ./nsharp-csharp

# Build with detailed output/timings for debugging
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- build --verbose --timings
```

There is intentionally no public `nlc convert` command. C#→N# migration should be AI-assisted and diagnostic-driven: author idiomatic `.nl`, run `nlc check`, `nlc idiom`, `nlc fix --dry-run`, `nlc format --check`, and tests, then iterate.

## Current CLI Surface

Current `nlc --help` lists these top-level commands:

```text
build run restore publish pack clean check fix query daemon format lint test bench add tidy remove update tree audit new init export idiom watch doc env completion help
```

`nlc query help` lists these query commands:

```text
batch symbols outline diagnostics type inspect definition/def references/refs completions doc hover call-graph implementors help
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
- Records and classes
- Required/init-style .NET interop patterns

### .NET Interop
- C#-consumable generated assemblies and source where supported
- Ref/out parameters and common C# call patterns
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

Do not claim the whole product is launch-ready/full-suite-green unless `./scripts/test-all.sh` completes cleanly in the target environment.

## CI/CD

N# projects are intended to work with standard .NET CI/CD tools. Template and example coverage exists in `ci/`, but verify the specific workflow before promising it in a release note or customer-facing page.

See [CI/CD Guide](docs/guide/ci-cd.md) for current setup notes.

## Documentation

- **docs/DESIGN.md** - language design notes and intended semantics
- **docs/guide/cli-reference.md** - CLI command reference aligned to current help/completions
- **memory/** - implementation notes, component docs, and known limitations
- **docs/audits/** and **docs/talk/** - launch evidence, risk registers, and public-claim guardrails
- **docs/** - user guides and references

## Architecture

```text
.nl source → Lexer → Parser → Analyzer → IL compiler / generated C# paths → .NET assembly
```

Some workflows emit or inspect generated C#; the product direction is not a public one-shot converter.

## C# Interop Example

N# code:

```nsharp
class Calculator {
    func Add(x: int, y: int): int => x + y
}
```

C# consumer:

```csharp
var calc = new Calculator();
var result = calc.Add(2, 3);
```

Interop claims should stay tied to scenarios covered by tests/examples until broader gates are green.
