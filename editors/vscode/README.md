# N# Language Support for VS Code

> **"Go for .NET"** - A tight, pragmatic language for the CLR with Go-inspired syntax and powerful .NET features

N# (`.nl` files) VS Code support with syntax highlighting, diagnostics, completions/hover/code actions where covered, and `nlc`-backed build/run/test tasks. Verify the extension against the current checkout before launch claims.

## ✨ Features

### 🚀 IntelliSense & Code Completion
- **Smart auto-completion** for keywords, types, and symbols
- **Signature help** with parameter information
- **Hover tooltips** showing type information
- **Go to Definition** - Jump to symbol declarations
- Trigger characters: `.`, `:`, `space`

### 🎨 Syntax Highlighting
- **Keyword coverage** - Core N# keywords including `package`, `union`, `match`, `test`
- **Generic type parameters** - Nested generic syntax highlighting for cases like `Dictionary<string, List<int>>`
- **Enhanced string interpolation** - Distinct highlighting for `$"..."` expressions
- **Error tuple catch results** - `err` in `result, err := MightFail()` is marked with the `variable.catchResult` semantic token and uses a muted amber default
- **Property type annotations** - `name: type` patterns
- **Number literals** - Hexadecimal (`0xFF`), binary (`0b1010`), with type suffixes

### 🔍 Diagnostics & Linting
- **Real-time error detection** with Elm-style error messages
- **Live warnings** for code quality issues
- **Linting rules** - Unused variables, missing imports, async without await
- **Compilation errors** shown inline with helpful suggestions

### 🛠️ Code Actions & Quick Fixes
- **Add missing imports** automatically
- **Remove unused variables**
- **Remove unnecessary null checks**
- More quick fixes coming soon!

### 🧭 Run & Debug
- **F5 support** - Launch executable N# projects from a `.nl` file without VS Code searching the Marketplace
- **Breakpoints in `.nl` files** - Debug builds export a temporary C# bundle with `#line` mappings back to N# source
- **Command palette** - `N#: Run Project` and `N#: Debug Project`

Debugging uses the Microsoft C# extension CoreCLR debugger. Install `ms-dotnettools.csharp` for breakpoints and stepping.

### ⚡ Tasks & Build Integration
Automatic `nlc`-backed tasks for fresh `project.yml` templates:
- `build` - Build your N# project with `nlc build` (Ctrl+Shift+B)
- `run` - Run your application with `nlc run`
- `test` - Run tests with `nlc test`
- `debug build` - Export and build the temporary `.nsharp/debug` C# bundle used by F5

The task provider respects the `nsharp.cli.path` setting. Leave it empty to use `nlc` from `PATH`, or set it to an absolute path to a repo-local/compiler-built executable.

### 📝 Code Formatting
- **Format on save** - Enabled by default
- **Manual formatting** - Cmd+Shift+F (macOS) or Ctrl+Shift+F (Windows/Linux)
- **.editorconfig** integration for consistent style

### 📚 Language Features
- **Type System**: `class`, `struct`, `record`, `interface`, `enum`, `union`, type aliases
- **Control Flow**: `if`/`else`, `for`, `foreach`, `while`, `match`, `switch`
- **Pattern Matching**: Guards, list patterns, nested property patterns, exhaustiveness checking
- **Discriminated Unions**: Type-safe unions with exhaustive matching
- **Async/Await**: Full async support with implicit Task wrapping
- **String Interpolation**: Regular (`$""`), raw (`"""`), and interpolated raw (`$"""`)
- **Testing**: Built-in `test` blocks and `assert` statements

## 📦 Installation

### Prerequisites
- **.NET 10.0 SDK** or later
- **N# toolchain** installed with the public installer or from this repo for contributor builds.

### Public Install

The N# installer adds the VS Code extension when the `code` CLI is on PATH:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"
nlc doctor --require-vscode
```

### Contributor VSIX Install
```bash
code --install-extension nsharp-0.6.0.vsix
```

## 🚀 Quick Start

1. **Install the N# toolchain and extension** with the public installer, or use `./scripts/setup-local.sh --with-vscode` from a source checkout
2. **Ensure `nlc` is on `PATH`** or set `nsharp.cli.path`
3. **Create a new N# project**:
   ```bash
   nlc new MyApp
   cd MyApp
   ```
4. **Open in VS Code**:
   ```bash
   code .
   ```
5. **Start coding!** Open `Program.nl` and start writing N# code
6. **Build/run/test/debug from VS Code** -- use the N# tasks, `N#: Run Project`, `N#: Debug Project`, or press F5 from a `.nl` file.

## 📖 Example Code

```nsharp
// N# - Go for .NET
package MyApp

import System
import System.Collections.Generic

// Discriminated unions with exhaustive pattern matching
union Result<T> {
    Success { value: T }
    Failure { error: string, code: int }
}

// Records with properties
record Person {
    FirstName: string
    LastName: string
    Age: int

    // Expression-bodied property
    FullName: string => $"{FirstName} {LastName}"
}

func Main() {
    // Type inference with :=
    person := new Person {
        FirstName = "John",
        LastName = "Doe",
        Age = 30
    }

    // String interpolation
    print $"Hello, {person.FullName}!"

    // Pattern matching
    result := ProcessData(42)
    output := match result {
        Result<int>.Success { value } when value > 50 => $"High: {value}",
        Result<int>.Success { value } => $"Low: {value}",
        Result<int>.Failure { error, code } => $"Error {code}: {error}",
    }
    print output

    // Built-in testing
    test "Math works correctly" {
        assert 2 + 2 == 4
        assert person.Age > 0
    }
}

func ProcessData(input: int) -> Result<int> {
    if input > 0 {
        return new Result<int>.Success(input * 2)
    }
    return new Result<int>.Failure("Invalid input", -1)
}
```

## ⚙️ Configuration

Configure the extension via VS Code settings:

```json
{
  // Custom path to language server (leave empty to use bundled)
  "nsharp.languageServer.path": "",

  // Enable/disable formatting
  "nsharp.format.enable": true,

  // LSP tracing for debugging
  "nsharp.trace.server": "off",  // "off" | "messages" | "verbose"

  // Custom path to nlc (leave empty to use nlc from PATH)
  "nsharp.cli.path": ""
}
```

The extension contributes the `catchResult` semantic token modifier. To customize the default muted amber color for `err` in error tuples:

```json
{
  "editor.semanticTokenColorCustomizations": {
    "rules": {
      "variable.catchResult:nsharp": {
        "foreground": "#D19A66"
      }
    }
  }
}
```

## 🎯 Commands

- **Tasks: Run Build Task** - Runs `nlc build` for the active workspace.
- **Tasks: Run Task → nsharp: run** - Runs `nlc run`.
- **Testing: Run Tests** - Runs discovered N# tests with `nlc test --json`.

## 🔧 Troubleshooting

### Language Server Not Starting
1. Ensure .NET 9.0 SDK is installed: `dotnet --version`
2. Reinstall the extension
3. Check the output panel: View → Output → N# Language Server

### IntelliSense Not Working
1. Ensure your project has a `project.yml` file
2. Build the project: `nlc build`
3. Reload VS Code window

### Build/Run/Test Tasks Not Working
1. Ensure the project has a `project.yml` file.
2. Ensure `nlc` is on `PATH`, or set `nsharp.cli.path` to the `nlc` executable you want VS Code to use.
3. Run `nlc build` in a terminal from the workspace root to verify the same project path.

## 🤝 Contributing

Contributions welcome! Visit the [main repository](https://github.com/anthropics/NewCLILang) for:
- Bug reports and feature requests
- Contributing guidelines
- Language design documentation

## 📄 License

MIT

## 🔗 Links

- [N# Language Documentation](https://github.com/anthropics/NewCLILang/tree/main/docs)
- [GitHub Repository](https://github.com/anthropics/NewCLILang)
- [Getting Started Guide](https://github.com/anthropics/NewCLILang/blob/main/docs/README.md)
- [Language Reference](https://github.com/anthropics/NewCLILang/tree/main/docs/guide)

---

**Enjoy coding with N#!** 🚀
