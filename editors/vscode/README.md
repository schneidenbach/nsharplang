# N# Language Support for VS Code

Complete language support for N# (.nl files) with IntelliSense, diagnostics, and more powered by the N# Language Server.

## Features

- **Syntax Highlighting** - Full syntax highlighting for N# language features
- **IntelliSense** - Auto-completion for keywords, types, and symbols
- **Diagnostics** - Real-time error and warning detection as you type
- **Hover Information** - Type information and documentation on hover
- **Bracket Matching** - Automatic bracket, parenthesis, and quote matching
- **Comment Support** - Line comments (//) and block comments (/* */)
- **Code Folding** - Fold code blocks and regions
- **Language Server** - Full LSP support for rich IDE experience

## Supported Features

- Keywords: func, class, struct, record, union, interface, enum
- Control flow: if, else, for, foreach, while, match, switch
- Pattern matching with guards
- Discriminated unions
- Async/await
- String interpolation (regular, raw, and interpolated raw strings)
- Attributes
- Operators: conversion (implicit/explicit), null-conditional, null-coalescing, spread
- And more!

## Installation

### Prerequisites
- .NET 9.0 SDK or later
- Build the N# Language Server first:
  ```bash
  cd /path/to/NewCLILang
  dotnet build src/LanguageServer/LanguageServer.csproj
  ```

### From VSIX (Local Development)
```bash
# Build and package the extension
cd editors/vscode
npm install
npm run compile
npx vsce package

# Install in VS Code
code --install-extension nsharp-0.2.0.vsix
```

### From Marketplace (coming soon)
Search for "N#" in the VS Code Extensions marketplace

## Configuration

The extension can be configured via VS Code settings:

- **nsharp.languageServer.path** - Custom path to the language server DLL (leave empty to auto-detect from workspace)
- **nsharp.trace.server** - Enable LSP communication tracing for debugging (`off` / `messages` / `verbose`)

## Usage

Open any `.nl` file and enjoy syntax highlighting!

## Example

```nsharp
// Example N# code with syntax highlighting
using System

class Person {
    Name: string
    Age: int

    func Greet() => print $"Hello, I'm {Name}!"
}

union Result {
    Success { value: int }
    Failure { error: string }
}

result := match someValue {
    Success { value } => value * 2,
    Failure { error } => 0
}
```

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
