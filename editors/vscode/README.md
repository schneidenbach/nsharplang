# N# Language Support for VS Code

Syntax highlighting and language support for N# (.nl files).

## Features

- **Syntax Highlighting** - Full syntax highlighting for N# language features
- **Bracket Matching** - Automatic bracket, parenthesis, and quote matching
- **Comment Support** - Line comments (//) and block comments (/* */)
- **Code Folding** - Fold code blocks and regions

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

### From VSIX (Local Development)
```bash
# Package the extension
cd editors/vscode
npx vsce package

# Install in VS Code
code --install-extension nsharp-0.1.0.vsix
```

### From Marketplace (coming soon)
Search for "N#" in the VS Code Extensions marketplace

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

## Future Features

- Language Server Protocol (LSP) support for:
  - IntelliSense / Auto-completion
  - Go to Definition
  - Find All References
  - Rename Symbol
  - Real-time error checking

## Contributing

Contributions welcome! See the main [repository](https://github.com/anthropics/NewCLILang) for details.

## License

MIT
