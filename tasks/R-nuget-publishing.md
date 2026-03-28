# Task R: NuGet Publishing Pipeline — Ship It

## Context

N# libraries need to be publishable to NuGet so the ecosystem can grow. Users need to be able to:
1. Create an N# library project
2. Write code
3. `dotnet pack` → get a .nupkg
4. `dotnet nuget push` → publish to nuget.org

The N# SDK (`src/NSharpLang.Sdk/`) already handles build, but the pack/publish story needs verification and documentation.

## What to do

### 1. Verify the library template

```bash
dotnet new nsharp-console -o TestLib  # Is there a library template?
```

If there's no library template, create one:
```
templates/nsharp-classlib/
├── .template.config/
│   └── template.json
├── project.yml
├── Library.nl
└── MyProject.csproj     # just `<Project Sdk="NSharpLang.Sdk" />`
```

The template should:
- Default to `outputType: library` in project.yml
- NOT have a `main()` entry point
- Include a sample public class/function
- Include a sample `.tests.nl` file

### 2. Verify `dotnet pack` works

```bash
dotnet new nsharp-classlib -o TestLib
cd TestLib
dotnet pack
```

Verify:
- The .nupkg is created
- It contains the compiled DLL (not the .nl source)
- Package metadata is correct (name, version, description from project.yml)
- Dependencies are included

### 3. Verify C# projects can consume N# packages

```bash
# Create N# library
dotnet new nsharp-classlib -o MyNSharpLib
cd MyNSharpLib
dotnet pack

# Create C# project that references it
cd ..
dotnet new console -o MyCSharpApp
cd MyCSharpApp
dotnet add package MyNSharpLib --source ../MyNSharpLib/bin/Release
```

Write C# code that:
- Creates instances of N# classes
- Calls N# functions
- Pattern matches on N# unions (via the generated class hierarchy)
- Uses N# records

This is the **ultimate interop test** — verify the promise "C# consumers can't tell the difference."

### 4. Documentation

Create `docs/guide/publishing-libraries.md`:
- How to create a library project
- How to set package metadata in project.yml
- How to pack and publish to NuGet
- How C# projects consume N# libraries
- Best practices (what to export, what to keep internal)
- Example: publishing a utility library

### 5. Update project.yml schema (if needed)

Ensure project.yml supports NuGet package metadata:
```yaml
name: MyAwesomeLib
version: 1.0.0
description: "A cool N# library"
authors: ["Spencer Schneidenbach"]
license: MIT
repository: https://github.com/schneidenbach/my-awesome-lib
tags: ["nsharp", "utility"]
outputType: library
```

If any of these fields aren't supported in the SDK, add them.

### 6. End-to-end test

Add a test to the test suite that:
1. Creates a temp N# library project
2. Writes an N# class with public API
3. Runs `dotnet pack`
4. Creates a temp C# project
5. Adds a reference to the N# package
6. Writes C# code that uses the N# types
7. Builds and runs the C# project
8. Verifies the output

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
