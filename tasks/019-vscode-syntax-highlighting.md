# Task 019: VS Code Syntax Highlighting Extension

**Priority:** High (Quick win for developer experience)
**Dependencies:** None
**Estimated Effort:** Small (2-3 hours)
**Status:** 🔥 NEW TASK - QUICK WIN

## Goal
Create a minimal VS Code extension that provides syntax highlighting for `.nl` files - a quick win before full LSP implementation.

## Why This First
- **Quick to implement** - Can be done in a few hours
- **Immediate value** - Makes .nl files readable in VS Code
- **No server needed** - Just TextMate grammar definition
- **Foundation for LSP** - Same extension can add LSP later
- **Professional appearance** - Syntax highlighting makes language look real

## Implementation

### Project Structure
```
editors/vscode/
├── package.json                      # Extension manifest
├── language-configuration.json       # Bracket matching, comments
├── syntaxes/
│   └── nsharp.tmLanguage.json       # TextMate grammar
├── README.md                         # Extension documentation
├── CHANGELOG.md                      # Version history
└── .vscodeignore                     # Files to exclude from package
```

### 1. package.json
```json
{
  "name": "nsharp",
  "displayName": "N# Language Support",
  "description": "Syntax highlighting for N# (.nl files)",
  "version": "0.1.0",
  "publisher": "nsharp",
  "repository": {
    "type": "git",
    "url": "https://github.com/yourusername/NewCLILang"
  },
  "engines": {
    "vscode": "^1.75.0"
  },
  "categories": [
    "Programming Languages"
  ],
  "keywords": [
    "nsharp",
    "n#",
    ".NET",
    "CLI",
    "transpiler"
  ],
  "contributes": {
    "languages": [
      {
        "id": "nsharp",
        "aliases": ["N#", "nsharp"],
        "extensions": [".nl", ".tests.nl"],
        "configuration": "./language-configuration.json",
        "icon": {
          "light": "./icons/nsharp-light.png",
          "dark": "./icons/nsharp-dark.png"
        }
      }
    ],
    "grammars": [
      {
        "language": "nsharp",
        "scopeName": "source.nsharp",
        "path": "./syntaxes/nsharp.tmLanguage.json"
      }
    ]
  },
  "icon": "icons/nsharp.png"
}
```

### 2. language-configuration.json
```json
{
  "comments": {
    "lineComment": "//",
    "blockComment": ["/*", "*/"]
  },
  "brackets": [
    ["{", "}"],
    ["[", "]"],
    ["(", ")"]
  ],
  "autoClosingPairs": [
    { "open": "{", "close": "}" },
    { "open": "[", "close": "]" },
    { "open": "(", "close": ")" },
    { "open": "\"", "close": "\"", "notIn": ["string"] },
    { "open": "'", "close": "'", "notIn": ["string", "comment"] }
  ],
  "surroundingPairs": [
    ["{", "}"],
    ["[", "]"],
    ["(", ")"],
    ["\"", "\""],
    ["'", "'"]
  ],
  "folding": {
    "markers": {
      "start": "^\\s*#region\\b",
      "end": "^\\s*#endregion\\b"
    }
  },
  "wordPattern": "(-?\\d*\\.\\d\\w*)|([^\\`\\~\\!\\@\\#\\%\\^\\&\\*\\(\\)\\-\\=\\+\\[\\{\\]\\}\\\\\\|\\;\\:\\'\\\"\\,\\.\\<\\>\\/\\?\\s]+)"
}
```

### 3. syntaxes/nsharp.tmLanguage.json
```json
{
  "$schema": "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
  "name": "N#",
  "scopeName": "source.nsharp",
  "patterns": [
    { "include": "#comments" },
    { "include": "#strings" },
    { "include": "#keywords" },
    { "include": "#types" },
    { "include": "#numbers" },
    { "include": "#operators" },
    { "include": "#functions" },
    { "include": "#attributes" }
  ],
  "repository": {
    "comments": {
      "patterns": [
        {
          "name": "comment.line.double-slash.nsharp",
          "match": "//.*$"
        },
        {
          "name": "comment.block.nsharp",
          "begin": "/\\*",
          "end": "\\*/"
        },
        {
          "name": "comment.block.documentation.nsharp",
          "begin": "///",
          "end": "$"
        }
      ]
    },
    "strings": {
      "patterns": [
        {
          "name": "string.quoted.double.interpolated.nsharp",
          "begin": "\\$\"",
          "end": "\"",
          "patterns": [
            {
              "name": "constant.character.escape.nsharp",
              "match": "\\\\."
            },
            {
              "name": "meta.interpolation.nsharp",
              "begin": "\\{",
              "end": "\\}",
              "patterns": [{ "include": "$self" }]
            }
          ]
        },
        {
          "name": "string.quoted.triple.nsharp",
          "begin": "\\$?\"\"\"",
          "end": "\"\"\""
        },
        {
          "name": "string.quoted.double.nsharp",
          "begin": "\"",
          "end": "\"",
          "patterns": [
            {
              "name": "constant.character.escape.nsharp",
              "match": "\\\\."
            }
          ]
        }
      ]
    },
    "keywords": {
      "patterns": [
        {
          "name": "keyword.control.nsharp",
          "match": "\\b(if|else|for|foreach|while|return|break|continue|match|switch|case|when|yield|await|async|throw|try|catch|finally|using|lock)\\b"
        },
        {
          "name": "keyword.other.nsharp",
          "match": "\\b(func|class|struct|record|interface|enum|union|namespace|import|using|new|this|base|static|virtual|override|abstract|sealed|partial|readonly|const|file|duck)\\b"
        },
        {
          "name": "storage.modifier.nsharp",
          "match": "\\b(public|private|internal|protected|required|init)\\b"
        },
        {
          "name": "storage.type.nsharp",
          "match": "\\b(let|var|const|type|out|ref|params)\\b"
        },
        {
          "name": "constant.language.nsharp",
          "match": "\\b(true|false|null)\\b"
        },
        {
          "name": "keyword.operator.nsharp",
          "match": "\\b(is|as|typeof|nameof|checked|unchecked|and|or|not|with|immutable)\\b"
        }
      ]
    },
    "types": {
      "patterns": [
        {
          "name": "support.type.primitive.nsharp",
          "match": "\\b(int|long|float|double|bool|string|void|object|byte|short|char|decimal|uint|ulong|ushort|sbyte)\\b"
        },
        {
          "name": "entity.name.type.nsharp",
          "match": "\\b[A-Z][a-zA-Z0-9]*\\b"
        }
      ]
    },
    "numbers": {
      "patterns": [
        {
          "name": "constant.numeric.nsharp",
          "match": "\\b\\d+(\\.\\d+)?([eE][+-]?\\d+)?[fFdDmM]?\\b"
        },
        {
          "name": "constant.numeric.hex.nsharp",
          "match": "\\b0[xX][0-9a-fA-F]+\\b"
        }
      ]
    },
    "operators": {
      "patterns": [
        {
          "name": "keyword.operator.assignment.nsharp",
          "match": ":=|="
        },
        {
          "name": "keyword.operator.comparison.nsharp",
          "match": "==|!=|<|>|<=|>="
        },
        {
          "name": "keyword.operator.arithmetic.nsharp",
          "match": "\\+|-|\\*|/|%"
        },
        {
          "name": "keyword.operator.logical.nsharp",
          "match": "&&|\\|\\||!"
        },
        {
          "name": "keyword.operator.nullable.nsharp",
          "match": "\\?\\?|\\?\\.?|\\?\\[|\\!\\."
        },
        {
          "name": "keyword.operator.lambda.nsharp",
          "match": "=>"
        }
      ]
    },
    "functions": {
      "patterns": [
        {
          "name": "entity.name.function.nsharp",
          "match": "\\b([a-z][a-zA-Z0-9]*)\\s*(?=\\()"
        },
        {
          "name": "entity.name.function.nsharp",
          "match": "\\b([A-Z][a-zA-Z0-9]*)\\s*(?=\\()"
        }
      ]
    },
    "attributes": {
      "patterns": [
        {
          "name": "meta.attribute.nsharp",
          "begin": "\\[",
          "end": "\\]",
          "patterns": [
            {
              "name": "entity.name.type.attribute.nsharp",
              "match": "[A-Z][a-zA-Z0-9]*"
            }
          ]
        }
      ]
    }
  }
}
```

### 4. README.md
```markdown
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
- String interpolation
- Attributes
- And more!

## Installation

### From VSIX
1. Download the latest `.vsix` file
2. Open VS Code
3. Go to Extensions view (Ctrl+Shift+X)
4. Click "..." menu → "Install from VSIX"
5. Select the downloaded file

### From Marketplace (coming soon)
Search for "N#" in the VS Code Extensions marketplace

## Usage

Open any `.nl` file and enjoy syntax highlighting!

## Examples

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

## Issues & Feedback

Report issues on [GitHub](https://github.com/yourusername/NewCLILang/issues)

## License

MIT
```

### 5. .vscodeignore
```
.vscode/**
.gitignore
*.md
!README.md
!CHANGELOG.md
```

## Build & Publishing

### Local Testing
```bash
cd editors/vscode

# Install dependencies (if any)
npm install

# Package extension
vsce package

# Install locally
code --install-extension nsharp-0.1.0.vsix
```

### Publish to Marketplace
```bash
# Login to publisher account
vsce login <publisher-name>

# Publish
vsce publish
```

## Success Criteria
- [ ] Extension packages successfully (.vsix file)
- [ ] Extension installs in VS Code
- [ ] .nl files are recognized with N# icon
- [ ] Syntax highlighting works for all language features:
  - [ ] Keywords (func, class, match, etc.)
  - [ ] Strings (regular, interpolated, raw)
  - [ ] Comments (line and block)
  - [ ] Numbers and literals
  - [ ] Operators
  - [ ] Types and type annotations
  - [ ] Attributes
  - [ ] Functions and methods
- [ ] Bracket matching works
- [ ] Auto-closing pairs work
- [ ] Code folding works
- [ ] Published to VS Code marketplace

## Testing Checklist
Open various example files and verify highlighting:
- [ ] examples/hello.nl - Basic highlighting
- [ ] examples/unions_and_match.nl - Union types and pattern matching
- [ ] examples/expression_bodied_members.nl - Expression syntax
- [ ] examples/records_and_interfaces.nl - Records and interfaces
- [ ] examples/interpolated_raw_strings.nl - String variations
- [ ] examples/list_patterns.nl - Complex patterns

## Notes
- This is a QUICK WIN before full LSP
- TextMate grammars are standard for VS Code
- Can be published to marketplace for free
- Good test of extension infrastructure
- Foundation for adding LSP later
- Makes N# look professional immediately
