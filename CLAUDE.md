You are an expert .NET developer who is working on a new language for the CLR - codename N# (short for NewLang Sharp).

**Language Philosophy**: "Go for .NET" - A tight, pragmatic language targeting .NET/CLI that prioritizes:
- **Simplicity**: Go-level tightness with minimal constructs
- **Pragmatism**: Embraces .NET realities (including null)
- **Interop**: First-class C# interoperability with sane type emissions
- **Concreteness**: Encourages concrete implementations over abstractions
- **Type System**: Improve .NET's type system while maintaining seamless C# interop

## Memory lookup

The memory/README.md is the table of contents for your documentation - if you need to look something up, start in the memory/README.md and then find the file that could answer your question.

## Rules

ALWAYS: KEEP THE PROJECT CODE REALLY CLEAN. If you have temporary code, DELETE IT AFTER YOU're DONE!
ALWAYS: Clean up unnecessary code as you go, and run your tests after cleaning up the code.
ALWAYS: After implementing functionality or solving problems, run the FULL test suite using `./scripts/test-all.sh`. This is MANDATORY.
ALWAYS: RUN `./scripts/test-all.sh` BEFORE COMMITTING ANY CODE. If it fails, fix the failures first!
ALWAYS: The test-all.sh script:
  - Runs all unit tests (`dotnet test`)
  - Rebuilds the compiler and SDK
  - Installs the latest SDK to local NuGet feed
  - Tests dotnet new template creation
  - Builds ALL example projects with `dotnet build`
  - Validates everything works end-to-end
ALWAYS: CHECK YOUR OWN WORK
ALWAYS: CHECK YOUR OWN ASSUMPTIONS
ALWAYS: `git commit` after you've written any code AND verified `./test-all.sh` passes!!

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
    <TargetFramework>net9.0</TargetFramework>  <!-- NO! This goes in project.yml -->
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>  <!-- HACK! Fix the SDK instead -->
  </PropertyGroup>
</Project>
```

If you find yourself adding properties to .csproj, you're doing it wrong. Fix the MSBuild SDK to read from project.yml instead.
The ONLY exception is if you need to work around a temporary MSBuild limitation during development.