# CLI Component (Legacy)

> **This doc covers only the original build/run/transpile commands.**
> **For the full CLI toolchain reference (check, fix, query, daemon, completions, format, lint), see [cli-toolchain.md](cli-toolchain.md).**

**File:** `src/NSharpLang.Cli/Program.cs`

## Original Commands

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

### `nlc transpile`
Prints generated C# to stdout.

```bash
nlc transpile example.nl
```

## Project Configuration

Projects use `project.yml` (not .csproj properties):

```yaml
name: MyApp
outputType: exe
targetFramework: net9.0
testFramework: xunit  # or "nunit"
```

The .csproj must be minimal: `<Project Sdk="NSharpLang.Sdk" />` — one line.

## Error Handling

Compilation stops at first error phase (parse errors → stop before analysis, analysis errors → stop before transpile). Errors use Elm-style formatting with source snippets, suggestions, and documentation URLs.

## Exit Codes

- **0**: Success
- **1**: Compilation errors

## Debugging

```bash
NSHARP_DEBUG_LOG=1 nlc build   # Writes compile-debug.log
```

---

*For the complete CLI reference including `nlc check`, `nlc fix`, `nlc query`, and `nlc daemon`, see [cli-toolchain.md](cli-toolchain.md).*
