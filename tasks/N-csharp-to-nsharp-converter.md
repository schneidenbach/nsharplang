# Task N: C# → N# Converter Tool

## Context

The #1 question every developer will ask: "Can I convert my existing C# code?" Having even a basic converter dramatically lowers the adoption barrier. It doesn't need to be perfect — 80% accuracy with manual cleanup is still a huge win.

## What to build

A new `nlc convert` CLI command that reads C# files and outputs N# equivalents.

### Usage:

```bash
# Convert a single file
nlc convert --file Program.cs --output Program.nl

# Convert a directory
nlc convert --dir ./src --output ./src-nl

# Preview without writing (dry run)
nlc convert --file Program.cs --dry-run

# Convert from stdin
cat Program.cs | nlc convert --stdin
```

### Implementation approach

Use Roslyn to parse C# into an AST, then walk the AST and emit N# syntax.

Read:
- `/Users/claude/repos/roslyn` — `Microsoft.CodeAnalysis.CSharp.SyntaxFactory` and `CSharpSyntaxWalker` for the visitor pattern
- Add `Microsoft.CodeAnalysis.CSharp` NuGet package to the CLI project

### Conversion rules (implement in priority order):

**Must have:**
1. `using X;` → `import X`
2. `var x = ...;` / `Type x = ...;` → `x := ...` / `x: Type = ...`
3. `public/private/protected` → PascalCase/camelCase convention (drop modifier)
4. Method declarations → `func Name(params): ReturnType { }`
5. Class/struct/record declarations → same keywords, N# syntax
6. Properties with `{ get; set; }` → just `Name: Type`
7. String interpolation `$"..."` → same (N# supports it)
8. `if (cond)` → `if cond` (drop parens)
9. `foreach (var x in items)` → `for x in items`
10. `for (int i = 0; ...)` → `for i := 0; ...`
11. Remove semicolons
12. `async Task<T>` → `async func ... (): T`
13. Null operators `?.` `??` `??=` → same (pass through)

**Nice to have:**
14. `switch` expression → `match` expression
15. Records with positional syntax
16. Simple lambda conversions
17. `Console.WriteLine(x)` → `print x`
18. Enum declarations
19. Interface declarations
20. Generic constraints

**Explicitly out of scope (leave TODO comments):**
- Events and delegates (N# doesn't support them)
- Unsafe code
- Complex LINQ query syntax (method syntax passes through fine)
- Attributes on parameters (not yet supported)

### Architecture:

```
src/NSharpLang.Cli/
  Commands/
    ConvertCommand.cs       # CLI argument parsing, file I/O
  Converter/
    CSharpToNSharp.cs       # Main converter, Roslyn SyntaxWalker
    ConversionRules.cs      # Individual transformation rules
    NSharpEmitter.cs        # Builds N# output string with proper formatting
```

### Test cases:

Create `tests/ConverterTests.cs` with:
- Simple class → N# class
- Record → N# record
- Method with params → N# func
- Properties → N# fields
- Variable declarations → `:=`
- If/else → parens removed
- For/foreach → N# syntax
- Using directives → imports
- String interpolation → pass through
- Full file conversion (realistic C# file → valid N# file)

**Critical**: The converted N# output must compile with `nlc check`. If it doesn't compile, the conversion is wrong.

### Error handling:

- If Roslyn can't parse the C# → clear error message with line/column
- If a C# construct has no N# equivalent → emit comment: `// TODO: Convert manually — N# doesn't support [feature]`
- Never crash, never emit invalid N#

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
