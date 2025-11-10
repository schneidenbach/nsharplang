# Changelog

All notable changes to the N# Language Support plugin for Rider will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-11-09

### Added
- Initial release of N# Language Support for Rider
- Syntax highlighting for `.nl` files
- Recognition of `project.yml` project files
- Custom icons for N# files and projects
- Build action (calls `dotnet build`)
- Rebuild action (calls `dotnet clean` + `dotnet build`)
- Run configuration type for executing N# projects
- File template for creating new N# files
- Color settings page for customizing syntax highlighting
- Project view integration with custom decorators

### Features
- **Keywords**: Full highlighting for N# keywords (func, type, union, match, etc.)
- **Literals**: String and number literal highlighting
- **Comments**: Line and block comment support
- **Operators**: Highlighting for N#-specific operators (`:=`, `=>`, etc.)
- **Build Integration**: Execute builds directly from Rider
- **Run Configurations**: Auto-generation of run configurations for N# files

### Known Limitations
- No LSP integration (planned for v0.2.0)
- Basic parser without full AST support
- No code completion beyond basic syntax
- No debugging support
- No advanced refactorings

## [Unreleased]

### Planned for 0.2.0
- Language Server Protocol (LSP) integration
- Code completion and IntelliSense
- Go to definition
- Find usages
- Error diagnostics from compiler
- Quick fixes
- Rename refactoring

### Planned for 0.3.0
- Debugging support
- Unit test runner integration
- Code folding
- Breadcrumbs navigation
- Structure view

## Links
- [GitHub Repository](https://github.com/nsharp-lang/nsharp)
- [Issue Tracker](https://github.com/nsharp-lang/nsharp/issues)
- [Documentation](https://nsharp.dev)
