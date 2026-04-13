# CLI Component (Legacy Summary)

> **This doc is a short historical summary of the early CLI.**
> **For the full current CLI toolchain reference, including `nlc export csharp`, see [cli-toolchain.md](cli-toolchain.md).**

**File:** `src/NSharpLang.Cli/Program.cs`

## Original Core Commands

### `nlc build`
Compiles `.nl` files to executable/DLL via MSBuild.

```bash
nlc build              # Multi-file project
nlc build example.nl   # Single file
```

### `nlc run`
Compiles and executes.

```bash
nlc run                # Multi-file project
nlc run example.nl     # Single file
```

### `nlc export csharp`
Exports a file or whole project bundle to C# without using generated C# as the executable backend.

```bash
nlc export csharp example.nl
nlc export csharp --project . -o ./myapp-csharp
```

## Project Configuration

Projects use `project.yml` (not .csproj properties):

```yaml
name: MyApp
outputType: exe
targetFramework: net10.0
testFramework: xunit  # or "nunit"
```

The .csproj must be minimal: `<Project Sdk="NSharpLang.Sdk" />` — one line.

## Error Handling

Compilation stops at the first failing phase (parse → analysis → IL emission or explicit C# export). Errors use Elm-style formatting with source snippets, suggestions, and documentation URLs.

## Exit Codes

- **0**: Success
- **1**: Compilation errors

## Debugging

```bash
NSHARP_DEBUG_LOG=1 nlc build   # Writes compile-debug.log
```

---

*For the complete CLI reference including `nlc check`, `nlc fix`, `nlc query`, `nlc daemon`, and `nlc export csharp`, see [cli-toolchain.md](cli-toolchain.md).*
