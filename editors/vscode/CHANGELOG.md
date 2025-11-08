# Change Log

All notable changes to the "nsharp" extension will be documented in this file.

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
