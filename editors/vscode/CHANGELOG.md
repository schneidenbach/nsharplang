# Change Log

All notable changes to the "nsharp" extension will be documented in this file.

## [0.6.0] - 2025-11-10

### Added - VS Code Polish Release (Task 048)
- **Professional extension icon** with N# branding
- **Enhanced task templates** in debug configuration generator:
  - `build` task (default build task, Ctrl+Shift+B)
  - `run` task (depends on build)
  - `test` task (default test task, Ctrl+Shift+T)
  - `format` task (runs `nlc format`)
  - `lint` task (runs `nlc lint`)
- **Marketplace-ready presentation**:
  - Complete feature showcase in README
  - Quick start guide with step-by-step instructions
  - Troubleshooting section
  - Example code highlighting all features
  - Categories updated: Programming Languages, Linters, Formatters

### Changed
- Updated README.md with comprehensive feature documentation
- Improved task.json generation with proper task groups and dependencies
- Version bumped to 0.6.0 for marketplace readiness

## [0.5.0] - 2025-11-09

### Added
- **Code formatting support**
  - Document formatting provider integrated with `nsharp format` command
  - Format on save (enabled by default)
  - Format on demand (Shift+Alt+F or right-click context menu)
  - Automatic error reporting if formatting fails
- Configuration settings:
  - `nsharp.format.enable` - Enable/disable code formatting
  - `[nsharp].editor.formatOnSave` - Default enabled for N# files

## [0.3.0] - 2025-11-08

### Added - Comprehensive Syntax Highlighting Improvements
- **Missing keywords**: `package`, `constructor`, `print`, `test`, `assert`
- **Generic type parameter highlighting** with full nesting support (e.g., `Dictionary<string, List<int>>`)
- **Enhanced string interpolation** with distinct punctuation highlighting for `$`, `{`, `}`
- **Declaration highlighting** for imports, packages, classes, functions, and type aliases
- **Property/field type annotation** highlighting (e.g., `name: string`)
- **Preprocessor directive support**: `#region`, `#endregion`, `#if`, `#define`, `#warning`, `#error`, etc.
- **Binary literals**: `0b1010`, `0b11111111`
- **Number literal suffixes**: `100L`, `50u`, `25ul`, `3.14f`, `2.5d`, `100m`
- **Import path highlighting**: Dotted namespace paths now highlighted distinctly
- **Better operator categorization**: Assignment, comparison, arithmetic, logical, nullable, lambda, spread

### Changed
- **Pattern ordering** optimized for better matching accuracy
- **String interpolation** now uses more specific scopes for better theme support
- **Generic type matching** improved to handle complex nested scenarios
- **Number literal patterns** refined to handle all .NET numeric formats

### Documentation
- Added comprehensive `SYNTAX-HIGHLIGHTING-IMPROVEMENTS.md` with examples
- Updated `README.md` with v0.3.0 features showcase
- Enhanced code examples demonstrating new highlighting capabilities

## [0.2.0] - 2024-11-08

### Added
- **Language Server Protocol (LSP) support**
  - IntelliSense with auto-completion for keywords, types, and symbols
  - Real-time diagnostics (errors and warnings)
  - Hover information showing type details
  - Full LSP client integration with N# Language Server
- Configuration settings:
  - `nsharp.languageServer.path` - Custom language server path
  - `nsharp.trace.server` - LSP communication tracing

### Changed
- Updated package description to reflect LSP support
- Extension now requires .NET 9.0 SDK to run language server
- Version bumped to 0.2.0

## [0.1.0] - 2024-11-08

### Added
- Initial release
- Syntax highlighting for N# (.nl files)
- Support for all N# language features:
  - Keywords (func, class, struct, record, union, match, etc.)
  - Strings (regular, interpolated, raw)
  - Comments (line and block)
  - Numbers and literals
  - Operators (including null-conditional, null-coalescing, spread)
  - Types and type annotations
  - Attributes
  - Functions and methods
  - Conversion operators (implicit/explicit)
- Bracket matching and auto-closing pairs
- Code folding
- Language configuration for .nl and .tests.nl files
