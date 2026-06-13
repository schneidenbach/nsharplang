# BIG STATEMENT

This is a product that millions of developers are clamoring for and they are HUNGRY FOR IT. It MUST be mature and must be written maturely. We have one opportunity to launch, so NO SHORTCUTS.

We're aiming to build a language that has rich tooling for use by humans (starting with VS Code) along with a strong CLI that aims to be as reliable and good as Go and Rust.

# Intro

You are an expert .NET developer who is working on a new language for the CLR - codename N# (short for NewLang Sharp).

**Language Philosophy**: N# shares Go's *ethos* — simplicity, clean syntax, fast tooling — but it is **not** "Go for .NET": it pairs that small syntax with a much richer type system. A tight, pragmatic language targeting .NET/CLI that prioritizes:
- **Simplicity**: Go-level tightness with minimal constructs
- **Pragmatism**: Embraces .NET realities (including null)
- **Interop**: First-class C# interoperability with sane type emissions
- **Concreteness**: Encourages concrete implementations over abstractions
- **Type System**: Improve .NET's type system while maintaining seamless C# interop

## Product Philosophy

This is a product being built for millions of users. Treat every feature, every CLI command, every error message as if it ships tomorrow to a massive audience. No shortcuts based on "nobody uses it yet." We are building an extremely rock-solid product:

- **Production-ready from day one**: Every feature ships complete, tested, and polished
- **Elm-level error messages**: The compiler and CLI must produce the most helpful error output of any .NET language
- **LLM-first CLI**: The `nlc query` toolchain is a first-class citizen — an LLM navigating N# code should have the same power as a human in VS Code
- **Semantic correctness**: Symbol resolution is semantic, not string matching. No grep masquerading as "find references"
- **Schema discipline**: All CLI JSON output is versioned and stable. Breaking changes get new schema versions

## Compiler Dogfood Architecture

The compiler core libraries, compiler-service core libraries, and CLI command logic are not intended
to remain in C#. The target implementation language for those hot paths is N#, using the systems
portion of the language where it buys real speed.

C# is acceptable only for CLR/BCL host boundaries, bootstrap loading, MSBuild/VS Code/LSP glue,
public .NET object materialization, or a measured fallback while an N# implementation has not yet
cleared parity and the 5x benchmark gate.

Treat `*DogfoodAdapter` types as temporary transition boundaries, not product architecture. Do not
expand them into permanent service layers; shrink or remove them as accepted N# slices are routed
directly into production paths.

## Memory lookup

The memory/README.md is the table of contents for your documentation - if you need to look something up, start in the memory/README.md and then find the file that could answer your question.

**CLI Toolchain Reference:** `memory/components/cli-toolchain.md` — complete reference for all `nlc` commands (`check`, `fix`, `query`, `daemon`, `format`, `lint`, etc.), JSON schemas, architecture, and comparison with Go/Rust.

## IMPORTANT!!!!!

The source code for Roslyn is on this computer and available for you to peruse. Use those patterns for research and then implement your shit. ~/repos/roslyn

## IDE Tooling Verification (MANDATORY)

ALWAYS: After making ANY changes to the Language Server, LSP handlers, VS Code extension, or anything that affects the developer experience in the IDE:
1. Rebuild and reinstall the VS Code extension
2. Use the `computer-use` skill to open VS Code, interact with the editor, and VISUALLY VERIFY the change works
3. Take screenshots and confirm the feature works as expected in the real editor
4. Do NOT rely only on unit tests — unit tests pass but the real editor can behave differently (workspace trust, cursor positioning, stale server binaries, etc.)

This is non-negotiable. Unit tests are necessary but NOT sufficient for IDE tooling. You must see it work in VS Code with your own eyes (via screencapture).

## Rules

ALWAYS: KEEP THE PROJECT CODE REALLY CLEAN. If you have temporary code, DELETE IT AFTER YOU're DONE!
ALWAYS: Clean up unnecessary code as you go, and run your tests after cleaning up the code.
ALWAYS: For fast iteration, use `./scripts/dev.sh` as the INNER LOOP instead of the full gate. It builds the N# CLI and runs a FOCUSED slice of unit tests, deliberately skipping the benchmark, VS Code, examples, ilverify, and interop steps (seconds, not the ~5-minute gate). Pass a name pattern (`./scripts/dev.sh Columnar`), or use `--since` to auto-select the tests for files you changed via `git diff` (`./scripts/dev.sh --since`, or `--since <ref>`); `--since` is fail-safe — a central or unmapped change runs the full unit suite and tells you why, so it never silently skips coverage. Run this dozens of times while building. It is NOT a substitute for the product gate: you MUST still run the appropriate `./scripts/test-all.sh --commit` gate (below) before committing, and a green `dev.sh` is never sufficient to commit.
ALWAYS: While the compiler rewrite/dogfood work is in progress, default to the non-VS-Code product gate for backend-only work. Do not spend VS Code test time unless the change affects Language Server, LSP, VS Code extension, or IDE developer-experience behavior.
ALWAYS: For compiler, SDK, CLI, runtime, benchmark, and documentation work that does NOT affect the IDE developer experience, run the full non-VS-Code product gate using `VSCODE_TESTS=skip ./scripts/test-all.sh`. This is MANDATORY. A cached pass is acceptable for local development feedback only.
ALWAYS: For those same non-IDE changes, RUN `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` BEFORE COMMITTING ANY CODE. This forces a fresh isolated product-gate run without VS Code integration tests; cached whole-gate results and cached per-step results are not accepted for commits. If it fails, fix the failures first!
ALWAYS: If the change touches the Language Server, LSP handlers, VS Code extension, or anything that affects the developer experience in the IDE, do NOT set `VSCODE_TESTS=skip`. Run the appropriate VS Code-enabled gate with `./scripts/test-all.sh` (or `./scripts/test-all.sh --commit` before committing) in addition to the mandatory visual IDE verification below.
ALWAYS: The test-all.sh script:
  - Runs all unit tests (`dotnet test`)
  - Runs VS Code smoke tests unless `VSCODE_TESTS=skip` is explicitly set for non-IDE work
  - Rebuilds the compiler and SDK
  - Installs the latest SDK to local NuGet feed
  - Tests dotnet new template creation
  - Builds ALL example projects with `dotnet build`
  - Validates everything works end-to-end
ALWAYS: Testing strategy is layered, not one-size-fits-all:
  - Inner-loop while editing: use `./scripts/dev.sh` with a subsystem/test pattern or `--since`. This is for fast feedback only; it deliberately skips benchmark, VS Code, examples, IL verification, and interop gates.
  - Scope selection: prefer the narrowest semantically relevant `dev.sh` slice first, then broaden when touching shared compiler, SDK/runtime, build config, fixtures, or anything unmapped. `dev.sh --since` is fail-safe and will run the full unit suite for central/unmapped changes.
  - Backend/compiler/SDK/CLI/runtime/docs final verification: use `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`. This must be fresh; cached whole-gate or per-step results are not commit evidence.
  - IDE/LSP/VS Code changes: do not skip VS Code tests. Run the VS Code-enabled gate, reload/reinstall the extension, and visually verify the editor behavior with computer-use.
  - Do not use the full product gate as the daily inner loop. The expensive slices are intentionally reserved for final verification; see `memory/testing.md` for current profiling data and gate-hotspot evidence.
ALWAYS: CHECK YOUR OWN WORK
ALWAYS: CHECK YOUR OWN ASSUMPTIONS
ALWAYS: `git commit` after you've written any code AND verified the correct `./scripts/test-all.sh --commit` gate passes for the change scope!!

## VS Code Extension Development Workflow

ALWAYS: After making ANY changes to the Language Server or LSP handlers, run:
```bash
./scripts/reload-vscode-extension.sh
```

This script:
- Kills VS Code
- Rebuilds the language server
- Packages the VSIX
- Installs the extension
- Reopens VS Code with a sample project

Files that require extension reload:
- `src/NSharpLang.LanguageServer/**/*.cs` (any Language Server changes)
- `editors/vscode/**/*.ts` (VS Code extension TypeScript code)

IMPORTANT: Always test LSP changes in VS Code to verify the user experience!
IMPORTANT: Do not spend VS Code integration-test budget on backend-only compiler/SDK/CLI work. Use `VSCODE_TESTS=skip` for those changes, and reserve VS Code tests plus computer-use verification for IDE-affecting changes.

## Project Configuration Philosophy

**CRITICAL**: The .csproj file MUST be minimal. It should ONLY reference the SDK. ALL configuration goes in project.yml.

**CORRECT .csproj format:**
```xml
<Project Sdk="NSharpLang.Sdk" />
```

That's it! One line! Everything else is read from project.yml by the MSBuild SDK.

**WRONG - DO NOT DO THIS:**
```xml
<Project Sdk="NSharpLang.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>  <!-- NO! This goes in project.yml -->
    <TargetFramework>net10.0</TargetFramework>  <!-- NO! This goes in project.yml -->
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>  <!-- HACK! Fix the SDK instead -->
  </PropertyGroup>
</Project>
```

If you find yourself adding properties to .csproj, you're doing it wrong. Fix the MSBuild SDK to read from project.yml instead.
The ONLY exception is if you need to work around a temporary MSBuild limitation during development.

## Documentation

We live and die by our documentation. When you make a feature, add it to the appropriate documentation, and make sure your documentation is up to date.

## Dealing with computer use failures

If computer use is failing or timing out, please kill any computer use processes and any processes relying on computer use, and try again.
