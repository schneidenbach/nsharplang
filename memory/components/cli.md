# CLI Component

**File:** `src/NSharpLang.Cli/Program.cs`

## Responsibility

Command-line interface for the N# compiler.

## Commands

### 1. `transpile`
Converts `.nl` file to C# source code.

```bash
nlc transpile example.nl
```

**Output:** Prints C# code to stdout

**Use case:** Inspecting generated C#, debugging transpiler

### 2. `build`
Compiles `.nl` file (or project) to executable/DLL.

```bash
nlc build example.nl           # Single file
nlc build                      # Multi-file project (discovers .nl files)
```

**Process:**
1. Lex all source files
2. Parse to AST
3. Analyze (type checking)
4. Stop if errors found
5. Transpile to C#
6. Write .cs files to temp directory
7. Create .csproj file
8. Invoke `dotnet build`
9. Copy output to current directory

**Output:** `example.exe` (or `example.dll`)

### 3. `run`
Compiles and executes `.nl` file.

```bash
nlc run example.nl              # Single file
nlc run                         # Multi-file project
```

**Process:**
1-6. Same as `build`
7. Create executable .csproj (not library)
8. Invoke `dotnet run` in temp directory

**Output:** Program output to stdout/stderr

## Multi-File Compilation

When no file argument provided:
- Discovers all `.nl` files in current directory
- Compiles them together as a project
- Respects `project.yml` if present (for configuration)

## Error Handling

When analyzer finds errors:
1. Format errors with Rust-quality diagnostics
2. Print to console with colors
3. Exit with non-zero code
4. **Do not proceed to transpilation**

## Error Formatting

Uses `ErrorReporting.cs` for professional output:

```
error[NL201]: Type mismatch in assignment
  --> example.nl:5:10
   |
 5 |     let x: int = "hello"
   |                  ^^^^^^^ expected 'int', found 'string'
   |
   = help: Change the type annotation or use a compatible value
```

## Temporary Directory Management

CLI creates temp directories for compilation:
- Located in system temp folder
- Unique name per compilation
- Contains generated .cs files and .csproj
- Cleaned up after compilation (optional: keep for debugging)

## Project Configuration

If `project.yml` exists:

```yaml
targetFramework: net9.0
asyncDefaultType: ValueTask
```

CLI uses this to:
- Set target framework in .csproj
- Configure transpiler behavior

See `memory/features/project-config.md` for details.

## Testing Support

CLI recognizes `.tests.nl` files:
- Generates XUnit test project
- References `xunit` and `xunit.runner.console` packages
- Transpiles test functions to XUnit `[Fact]` methods

Run tests:
```bash
nlc test                # Discovers and runs *.tests.nl files
```

## Global Tool Installation

Install as global .NET tool:

```bash
dotnet tool install --global NSharpLang.Cli
```

Then use anywhere:
```bash
nlc build myfile.nl
nlc run myprogram.nl
```

Uninstall:
```bash
dotnet tool uninstall --global NSharpLang.Cli
```

## Exit Codes

- **0**: Success
- **1**: Compilation errors (lexer, parser, analyzer)
- **2**: C# compilation errors (from `dotnet build`)
- **3**: Runtime errors (from program execution)

## Debugging

Set `NSHARP_DEBUG_LOG=1` to enable compiler debug logs:
- Generated C# code
- Compilation trace output in `compile-debug.log`

```bash
export NSHARP_DEBUG_LOG=1
nlc build example.nl
```

## Usage Examples

```bash
# Transpile to C#
nlc transpile examples/04-pattern-matching/GuardsSimple.nl

# Build single file
nlc build examples/04-pattern-matching/GuardsSimple.nl

# Run single file
nlc run examples/04-pattern-matching/GuardsSimple.nl

# Build multi-file project
cd examples/12-multi-file-projects/WeatherDemo
nlc build

# Run multi-file project
cd examples/12-multi-file-projects/WeatherDemo
nlc run
```
