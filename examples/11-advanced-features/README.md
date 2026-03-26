# Advanced Features

Each directory in this folder is a standalone N# example project focused on one advanced language feature.

This layout keeps the examples isolated from each other so they build, run, and diagnose independently in the CLI and in VS Code.

## Projects

- `CheckedUnchecked` - checked and unchecked arithmetic expressions
- `ConversionOperators` - implicit and explicit user-defined conversions
- `FileScopedSimple` - a small file-scoped type example
- `FileScopedTypes` - a larger file-scoped type example with internal helper types
- `InterpolatedRawStrings` - interpolated raw string literals
- `LockStatement` - thread-safe code with `lock`
- `OperatorOverloading` - operator overload declarations
- `PreprocessorDirectives` - regions and conditional compilation

## Running An Example

```bash
cd examples/11-advanced-features/ConversionOperators
dotnet run
```

You can also build all example projects from the repo root with:

```bash
./scripts/test-all.sh
```
