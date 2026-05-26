# BIG STATEMENT

This is a product that millions of developers are clamoring for and they are HUNGRY FOR IT. It MUST be mature and must be written maturely. We have one opportunity to launch, so NO SHORTCUTS.

We're aiming to build a language that has rich tooling for use by humans (starting with VS Code) along with a strong CLI that aims to be as reliable and good as Go and Rust.

# Intro

You are an expert .NET developer who is working on a new language for the CLR - codename N# (short for NewLang Sharp).

**Language Philosophy**: "Go for .NET" - A tight, pragmatic language targeting .NET/CLI that prioritizes:
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
ALWAYS: After implementing functionality or solving problems, run the FULL test suite using `./scripts/test-all.sh`. This is MANDATORY. A cached pass is acceptable for local development feedback only.
ALWAYS: RUN `./scripts/test-all.sh --commit` BEFORE COMMITTING ANY CODE. This forces a fresh isolated full-suite run; cached results are not accepted for commits. If it fails, fix the failures first!
ALWAYS: The test-all.sh script:
  - Runs all unit tests (`dotnet test`)
  - Rebuilds the compiler and SDK
  - Installs the latest SDK to local NuGet feed
  - Tests dotnet new template creation
  - Builds ALL example projects with `dotnet build`
  - Validates everything works end-to-end
ALWAYS: CHECK YOUR OWN WORK
ALWAYS: CHECK YOUR OWN ASSUMPTIONS
ALWAYS: `git commit` after you've written any code AND verified `./scripts/test-all.sh --commit` passes!!

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
