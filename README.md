# N# (NewLang Sharp)

**Go for .NET: a pragmatic CLR language with small syntax, project-first tooling, and C# interop.**

N# is in active development. The repository has a working compiler, SDK, CLI, templates, VS Code support, and examples, but not every product gate is launch-green yet. Treat this README as the current developer-facing map, not a claim that every planned language feature or IDE workflow is complete.

## Quick Start

Install N# with the canonical public installer:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash
```

The installer sets up the public NSharpLang toolchain as one product surface: the `nlc` CLI, `dotnet new` templates, SDK restore support, the N# language server, and the VS Code extension when the `code` CLI is available. Users should install NSharpLang, not a stack of internal packages.

Verify the install and create a project:

```bash
nlc --version
nlc doctor
nlc new MyApp
cd MyApp
nlc run
```

Fresh projects are project.yml-first and csproj-free. `nlc build`/`nlc run` generate the minimal MSBuild entry point when needed.

---

## Installation

### One-Line Installer (macOS/Linux bash)

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash
```

Useful variants:

```bash
# Pin an exact release
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash -s -- --version 0.1.0

# Use a private/local feed during validation
./scripts/install.sh --source ./artifacts/nuget

# Remove installed N# tools/templates/extension
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash -s -- --uninstall
```

The public one-liner expects NSharpLang NuGet packages to be published to the configured source and the VS Code extension to be available as `nsharp.nsharp` in the VS Code marketplace path (or as a release VSIX via `NSHARP_VSIX_URL`). If either public artifact is not published yet, the installer fails with the exact missing artifact instead of sending users through manual internal package steps.

Windows note: this pass ships the canonical bash installer for macOS/Linux. Windows users can use WSL or run the equivalent commands manually until a PowerShell installer lands.

### Build from Source (contributors)

```bash
git clone <repo-url>
cd nsharplang
./scripts/setup-local.sh
```

This path is for contributors and private-feed consumers. Public users should start with the one-line installer above.

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
build run restore publish pack clean check fix query daemon format lint test bench add tidy remove update tree audit new init export idiom watch doc env doctor completion help
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
