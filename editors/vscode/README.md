# N# Language Support for VS Code

> **"Go for .NET"** - A tight, pragmatic language for the CLR with Go-inspired syntax and powerful .NET features

Complete language support for N# (`.nl` files) featuring IntelliSense, diagnostics, debugging, code actions, and more.

## ✨ Features

### 🚀 IntelliSense & Code Completion
- **Smart auto-completion** for keywords, types, and symbols
- **Signature help** with parameter information
- **Hover tooltips** showing type information
- **Go to Definition** - Jump to symbol declarations
- Trigger characters: `.`, `:`, `space`

### 🎨 Syntax Highlighting
- **Comprehensive keyword coverage** - All N# keywords including `package`, `union`, `match`, `test`
- **Generic type parameters** - Full support for nested generics like `Dictionary<string, List<int>>`
- **Enhanced string interpolation** - Distinct highlighting for `$"..."` expressions
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

### 🐛 Debugging Support
- **Built-in debug configuration generator** - Command: `N#: Generate Debug Configuration`
- **Breakpoints** - Set and hit breakpoints in `.nl` files
- **Step debugging** - Step through, step over, step into
- **Watch variables** - Inspect variable values
- **Call stack** - Full stack trace support

### ⚡ Tasks & Build Integration
Automatic task generation for:
- `build` - Build your N# project (Ctrl+Shift+B)
- `run` - Run your application
- `test` - Run tests (Ctrl+Shift+T default)
- `format` - Format code with `nlc format`
- `lint` - Lint code with `nlc lint`

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
- **.NET 9.0 SDK** or later
- **N# Compiler** - Install via:
  ```bash
  dotnet tool install -g nlc
  ```

### From VS Code Marketplace
Search for "N#" in the VS Code Extensions marketplace and click Install.

### From VSIX
```bash
code --install-extension nsharp-0.6.0.vsix
```

## 🚀 Quick Start

1. **Install the extension** from the marketplace
2. **Install the N# compiler**:
   ```bash
   dotnet tool install -g nlc
   ```
3. **Create a new N# project**:
   ```bash
   dotnet new nsharp-console -n MyApp
   cd MyApp
   ```
4. **Open in VS Code**:
   ```bash
   code .
   ```
5. **Generate debug configuration**:
   - Press `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows/Linux)
   - Type "N#: Generate Debug Configuration"
6. **Start coding!** Open `Program.nl` and start writing N# code

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
  "nsharp.trace.server": "off"  // "off" | "messages" | "verbose"
}
```

## 🎯 Commands

- **N#: Generate Debug Configuration** - Creates `.vscode/launch.json` and `.vscode/tasks.json`

## 🔧 Troubleshooting

### Language Server Not Starting
1. Ensure .NET 9.0 SDK is installed: `dotnet --version`
2. Reinstall the extension
3. Check the output panel: View → Output → N# Language Server

### IntelliSense Not Working
1. Ensure your project has a `project.yml` file
2. Build the project: `dotnet build`
3. Reload VS Code window

### Debugging Not Working
1. Generate debug configuration: `N#: Generate Debug Configuration`
2. Install C# extension for .NET debugging
3. Ensure project builds successfully

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
