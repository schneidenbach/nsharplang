# N# Language Support for VS Code

Complete language support for N# (.nl files) with comprehensive syntax highlighting, IntelliSense, and diagnostics powered by the N# Language Server.

## ✨ Features

### Syntax Highlighting (v0.3.0 - Enhanced!)
- **Comprehensive keyword coverage** - All N# keywords including `package`, `constructor`, `print`, `test`, `assert`
- **Generic type parameters** - Full support for nested generics like `Dictionary<string, List<int>>`
- **Enhanced string interpolation** - Distinct highlighting for `$`, `{`, `}`, and embedded expressions
- **Declaration highlighting** - Special colors for class, function, type declarations
- **Property type annotations** - Highlights `name: type` patterns
- **Preprocessor directives** - `#region`, `#if`, `#define`, etc.
- **Number literals** - Hexadecimal (`0xFF`), binary (`0b1010`), with type suffixes
- **Import path highlighting** - Dotted namespace paths in imports

### IntelliSense
- Auto-completion for keywords, primitive types, and user-defined symbols
- Common .NET types (Console, List, Task, etc.)
- Trigger characters: `.`, `:`, `space`

### Diagnostics
- Real-time error and warning detection
- Compilation errors shown inline

### Other Features
- **Hover Information** - Type info on hover
- **Bracket Matching** - Auto-pairing for `{}`, `[]`, `()`, `""`
- **Comment Support** - Line (`//`), block (`/* */`), and doc (`///`) comments
- **Code Folding** - Fold code blocks and `#region` sections
- **Language Server** - Full LSP support

## 🎯 Supported Language Features

- **Type System**: class, struct, record, interface, enum, union, type aliases
- **Control Flow**: if/else, for, foreach, while, match, switch
- **Pattern Matching**: with guards, list patterns, nested property patterns
- **Discriminated Unions**: with exhaustiveness checking
- **Async/Await**: Full async support
- **String Interpolation**: Regular (`$""`), raw (`"""`), and interpolated raw (`$"""`)
- **Attributes**: `[HttpGet]`, `[Required]`, etc.
- **Operators**:
  - Conversion: `implicit`, `explicit`, `operator`
  - Null-safety: `?.`, `??`, `!.`
  - Assignment: `:=`, `=`
  - Spread: `...`
- **Testing**: Built-in `test` blocks and `assert` statements

## Installation

### Prerequisites
- .NET 9.0 SDK or later
- Build the N# Language Server first:
  ```bash
  cd /path/to/NewCLILang
  dotnet build src/LanguageServer/LanguageServer.csproj
  ```

### From VSIX (Recommended)
```bash
# Install the pre-built extension
cd editors/vscode
code --install-extension nsharp-0.3.0.vsix
```

Or manually in VS Code:
1. Press `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Windows/Linux)
2. Type "Extensions: Install from VSIX"
3. Select `nsharp-0.3.0.vsix`

### Build from Source
```bash
# Build and package the extension
cd editors/vscode
npm install
npm run compile
npm run package

# Install the packaged extension
code --install-extension nsharp-0.3.0.vsix
```

### From Marketplace (coming soon)
Search for "N#" in the VS Code Extensions marketplace

## Configuration

The extension can be configured via VS Code settings:

- **nsharp.languageServer.path** - Custom path to the language server DLL (leave empty to auto-detect from workspace)
- **nsharp.trace.server** - Enable LSP communication tracing for debugging (`off` / `messages` / `verbose`)

## Usage

Open any `.nl` file and enjoy syntax highlighting!

## 📝 Example

```nsharp
// Example N# code showcasing syntax highlighting
package MyApp

import System
import System.Collections.Generic

#region Type Definitions

// Union with generics - fully highlighted!
union Result<T> {
    Success { value: T }
    Failure { error: string, code: int }
}

// Class with properties and constructor
class Person {
    FirstName: string           // Property type annotation
    LastName: string
    age: int                    // Private field (camelCase)

    // Expression-bodied property with string interpolation
    FullName: string => $"Hello, I'm {FirstName} {LastName}!"

    constructor(first: string, last: string) {
        FirstName = first
        LastName = last
        age = 0
    }
}

// Type alias
type UserId = int

#endregion

func Main() {
    // Variable declarations with type inference
    x := 42
    hex := 0xFF        // Hexadecimal literal
    bin := 0b1010      // Binary literal
    pi := 3.14

    // String interpolation highlighting
    message := $"x = {x}, hex = {hex}"
    print message      // print keyword

    // Pattern matching
    result := new Result<int>.Success(100)
    output := match result {
        Result<int>.Success { value } when value > 50 => $"High: {value}",
        Result<int>.Failure { error, code } => $"Error {code}: {error}",
        _ => "Unknown"
    }

    // Generic method calls
    list := new List<int>()
    dict := new Dictionary<string, Person>()

    // Test blocks
    test "Math works" {
        assert 2 + 2 == 4
    }
}
```

See `/tmp/syntax-test.nl` for a comprehensive highlighting test file.

## Upcoming Features

Coming soon:
- Go to Definition
- Find All References
- Rename Symbol
- Signature Help (parameter hints)
- Code Actions (quick fixes)
- Semantic Tokens (enhanced syntax highlighting)
- Document Symbols (outline view)

## Contributing

Contributions welcome! See the main [repository](https://github.com/anthropics/NewCLILang) for details.

## License

MIT
