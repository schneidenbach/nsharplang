# N# Compiler and Toolset Documentation

**Status:** Feature-complete compiler for the N# language
**Tests:** 506 passing

Welcome to the N# compiler documentation. This folder contains technical documentation organized for fast lookup and minimal context usage.

---

## Quick Start

### "How do I...?"

| Question | Answer |
|----------|--------|
| Understand the architecture? | Read [architecture.md](architecture.md) |
| Learn about a component? | See [components/](#components) folder |
| Find a feature? | See [features/](#features) folder |
| Run tests? | See [testing.md](testing.md) |
| Check limitations? | See [limitations.md](limitations.md) |

---

## Documentation Structure

### [architecture.md](architecture.md)
High-level overview of the compiler pipeline, design decisions, and project structure.

**Read this first** to understand how everything fits together.

**Topics:**
- Compiler pipeline (Lexer → Parser → Analyzer → Transpiler → C#)
- Why transpile to C# instead of emitting IL
- Component overview
- Data flow
- Build commands

---

## Components

Detailed documentation for each compiler component.

### [components/lexer.md](components/lexer.md)
Tokenization, string handling, operator recognition.

**Key details:**
- String literals stored WITH quotes
- Newline filtering
- Token types
- Error handling

### [components/parser.md](components/parser.md)
AST construction, recursive descent parsing, operator precedence.

**Key details:**
- Lambda parsing at assignment level
- For loop shorthand (`:=`)
- Operator precedence table
- AST node types

### [components/analyzer.md](components/analyzer.md)
Type checking, semantic analysis, name resolution.

**Key details:**
- Scope management
- Type inference
- External type resolution (via reflection)
- Duck interface structural typing
- Pattern exhaustiveness checking

### [components/transpiler.md](components/transpiler.md)
C# code generation from AST.

**Key details:**
- Union type → abstract base class
- Duck interface → internal interface
- String enum → static class
- Convention → explicit modifiers
- Special cases (async iterators, error handling)

### [components/cli.md](components/cli.md)
Command-line interface (build, run, transpile).

**Key details:**
- Multi-file compilation
- Error formatting
- Project configuration
- Global tool installation

### [components/error-reporting.md](components/error-reporting.md)
Professional error messages with codes and suggestions.

**Key details:**
- Error codes (NL001-NL999)
- Rust-style formatting
- Context-aware suggestions
- Color output

---

## Features

Documentation organized by feature category.

### [features/type-system.md](features/type-system.md)
Type inference, duck interfaces, external types, user-defined types.

**Topics:**
- Type inference (var, :=, arrays)
- Duck interfaces and structural typing
- External type resolution (.NET reflection)
- User-defined types (class, struct, record, union, enum)
- Type compatibility and conversions

### [features/pattern-matching.md](features/pattern-matching.md)
Match expressions, patterns, guards, exhaustiveness checking.

**Topics:**
- Pattern types (identifier, literal, union, positional, list, type)
- Pattern guards (when clauses)
- Exhaustiveness checking for unions
- Transpilation to C# switch expressions

### [features/async.md](features/async.md)
Async/await, async streams (IAsyncEnumerable).

**Topics:**
- Async functions and await expressions
- Async streams with `async*` and `await foreach`
- ValueTask configuration
- Yield break
- Cancellation support

### [features/collections.md](features/collections.md)
Arrays, collection expressions, params, iterators.

**Topics:**
- Array literals and type inference
- Collection expressions (C# 12)
- Indexing and ranges
- Params arrays and collections (C# 13)
- List patterns
- Spread operator
- Iterators with yield
- LINQ integration

### [features/interop.md](features/interop.md)
C# interop, using statements, external types, attributes.

**Topics:**
- Using statements and aliased imports
- External type resolution
- Calling C# code
- Attributes (including qualified names)
- Generics, delegates, ref/out parameters
- N# consumed by C# projects
- Type compatibility mapping

---

## Testing

### [testing.md](testing.md)
Test suite organization, strategy, and examples.

**Details:**
- 506 passing tests (33 lexer, 86 parser, 78 analyzer, 71 transpiler, 238+ integration)
- No mocks strategy
- Test examples
- Running tests
- Coverage details

---

## Limitations

### [limitations.md](limitations.md)
Current limitations and workarounds.

**Categories:**
- Type system (lambda inference, generic inference)
- Method resolution (overload by type)
- Pattern matching (guards, nested unions)
- Extension methods on literals
- Import system (circular imports)
- IDE support (LSP Phase 3+)
- Tooling (formatter, REPL)

---

## How to Find Information

### By Task

**"I need to implement a feature"**
1. Check [architecture.md](architecture.md) for overall design
2. Check relevant [components/](#components) files for implementation
3. Check [testing.md](testing.md) for test patterns
4. Check [limitations.md](limitations.md) for known issues

**"I need to understand existing code"**
1. Check [components/](#components) folder for component details
2. Check [features/](#features) folder for feature specifics
3. Search for specific terms in relevant files

**"I need to fix a bug"**
1. Identify component (Lexer, Parser, Analyzer, Transpiler)
2. Read relevant component doc in [components/](#components)
3. Check [testing.md](testing.md) for test approach
4. Check [limitations.md](limitations.md) if it's a known limitation

**"I need to add tests"**
1. Read [testing.md](testing.md) for strategy
2. Look at existing tests in `tests/` folder
3. Follow patterns from relevant test file

### By Component

| Component | File | Size | Key Topics |
|-----------|------|------|------------|
| Lexer | [components/lexer.md](components/lexer.md) | ~3KB | Tokenization, strings, operators |
| Parser | [components/parser.md](components/parser.md) | ~5KB | AST, precedence, patterns |
| Analyzer | [components/analyzer.md](components/analyzer.md) | ~6KB | Types, scopes, checking |
| Transpiler | [components/transpiler.md](components/transpiler.md) | ~5KB | C# generation, strategies |
| CLI | [components/cli.md](components/cli.md) | ~3KB | Commands, projects, tools |
| Errors | [components/error-reporting.md](components/error-reporting.md) | ~3KB | Codes, formatting, suggestions |

### By Feature

| Feature | File | Key Topics |
|---------|------|------------|
| Types | [features/type-system.md](features/type-system.md) | Inference, duck interfaces, external types |
| Patterns | [features/pattern-matching.md](features/pattern-matching.md) | Match, patterns, guards, exhaustiveness |
| Async | [features/async.md](features/async.md) | Async/await, streams, yield |
| Collections | [features/collections.md](features/collections.md) | Arrays, params, iterators, LINQ |
| Interop | [features/interop.md](features/interop.md) | C# interop, using, attributes |

---

## Context Usage

These documentation files are optimized for AI context windows:

| File | Approximate Size | When to Read |
|------|------------------|--------------|
| architecture.md | ~5KB | Always (high-level overview) |
| components/*.md | ~3-6KB each | When working on specific component |
| features/*.md | ~4-7KB each | When implementing/debugging feature |
| testing.md | ~4KB | When writing tests |
| limitations.md | ~5KB | When hitting unexpected behavior |

**Total:** ~50KB across all files (vs 133KB in old single file)

**Strategy:** Read architecture.md first, then only load specific files as needed.

---

## Related Documentation

- **../docs/DESIGN.md** - Language design and syntax specification
- **../README.md** - Project overview and getting started
- **../docs/** - User-facing documentation and guides
- **./completed-tasks/** - Archived completed tasks

---

## Questions This Documentation Answers

1. ✅ How is the compiler architected?
2. ✅ What does each component do?
3. ✅ How is [feature X] implemented?
4. ✅ How do I parse [syntax]?
5. ✅ How does type checking work?
6. ✅ How is C# code generated?
7. ✅ How do I run the compiler?
8. ✅ How do I write tests?
9. ✅ What are the current limitations?
10. ✅ How does [tricky feature] work internally?

---

*Last Updated: 2025-11-08*
*Documentation split from single 133KB file into focused files for better AI context usage*
