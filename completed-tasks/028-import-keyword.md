# Task 028: Replace `using` with `import` Keyword

**Status:** 🔲 TODO
**Priority:** Medium
**Dependencies:** None
**Estimated Effort:** Small (2-3 hours)

## Goal

Replace `using` keyword with `import` for consistency. Use `import` for both namespaces and files.

## Current Behavior

```n#
using System
using System.Linq
using static MathUtils

class Program {
    // ...
}
```

**Problem:** C# uses `using`, but it's confusing to have both `using` and potential `import` keywords.

## Desired Behavior

```n#
import System
import System.Linq
import static MathUtils

class Program {
    // ...
}
```

For files (future):
```n#
import "./models/Person.nl"
import "../utils/StringHelpers.nl"
```

## Rationale

- **Consistency:** Most languages use `import` (Go, Python, Java, JavaScript, TypeScript)
- **Clarity:** `import` is more intuitive than `using` for bringing in dependencies
- **Future-proof:** Sets us up for file imports later
- **Less C# baggage:** `using` feels like we're just copying C#

## Implementation

### 1. Lexer Changes

**File:** `src/Compiler/Lexer.cs`

Remove `using` keyword, add `import`:

```csharp
private static readonly Dictionary<string, TokenType> Keywords = new() {
    // Remove:
    // { "using", TokenType.Using },

    // Add:
    { "import", TokenType.Import },

    // ... rest of keywords
};
```

Update token type:
```csharp
public enum TokenType {
    // Remove: Using
    Import,
    // ...
}
```

### 2. AST Changes

**File:** `src/Compiler/Ast/Declarations.cs`

Rename `UsingDirective` to `ImportDirective`:

```csharp
// Before:
public record UsingDirective(
    string Namespace,
    bool IsStatic,
    Location Location
) : AstNode(Location);

// After:
public record ImportDirective(
    string Namespace,
    bool IsStatic,
    Location Location
) : AstNode(Location);
```

Update `CompilationUnit`:
```csharp
public record CompilationUnit(
    List<ImportDirective> Imports,    // was: Usings
    PackageDeclaration? Package,
    List<Declaration> Declarations,
    Location Location
) : AstNode(Location);
```

### 3. Parser Changes

**File:** `src/Compiler/Parser.cs`

Update parsing:

```csharp
public CompilationUnit ParseCompilationUnit() {
    var imports = new List<ImportDirective>();

    // Change: TokenType.Using → TokenType.Import
    while (Current.Type == TokenType.Import) {
        imports.Add(ParseImportDirective());
    }

    PackageDeclaration? package = null;
    if (Current.Type == TokenType.Package) {
        package = ParsePackageDeclaration();
    }

    var declarations = new List<Declaration>();
    while (Current.Type != TokenType.Eof) {
        declarations.Add(ParseDeclaration());
    }

    return new CompilationUnit(imports, package, declarations, Location.None);
}

private ImportDirective ParseImportDirective() {
    Expect(TokenType.Import);  // was: TokenType.Using

    bool isStatic = false;
    if (Current.Type == TokenType.Static) {
        Advance();
        isStatic = true;
    }

    var name = ParseQualifiedName();

    return new ImportDirective(name, isStatic, Location.None);
}
```

### 4. Analyzer Changes

**File:** `src/Compiler/Analyzer.cs`

Update references:

```csharp
public AnalysisResult Analyze(CompilationUnit ast) {
    // Collect imports (was: usings)
    foreach (var import in ast.Imports) {
        ProcessImportDirective(import);
    }

    // ...
}

private void ProcessImportDirective(ImportDirective import) {
    if (import.IsStatic) {
        _staticImports.Add(import.Namespace);
    } else {
        _importedNamespaces.Add(import.Namespace);
    }
}
```

### 5. Transpiler Changes

**File:** `src/Compiler/Transpiler.cs`

Update transpilation (still emits C# `using`):

```csharp
public string Transpile(CompilationUnit ast) {
    _output = new StringBuilder();

    // Emit C# using statements from N# import statements
    foreach (var import in ast.Imports) {
        TranspileImportDirective(import);
    }

    // ... rest of transpilation
}

private void TranspileImportDirective(ImportDirective import) {
    // N# `import` → C# `using`
    if (import.IsStatic) {
        _output.AppendLine($"using static {import.Namespace};");
    } else {
        _output.AppendLine($"using {import.Namespace};");
    }
}
```

### 6. Update All Examples

**Need to update all `.nl` files:**

Find and replace:
```bash
find examples -name "*.nl" -exec sed -i '' 's/^using /import /g' {} \;
```

Before:
```n#
using System
using System.Linq
```

After:
```n#
import System
import System.Linq
```

### 7. Update Tests

**Files to update:**
- `tests/LexerTests.cs` - Test `import` token
- `tests/ParserTests.cs` - Test `ImportDirective` parsing
- `tests/TranspilerTests.cs` - Test transpilation to C# `using`
- `tests/AnalyzerTests.cs` - Test import resolution

Example test:
```csharp
[Fact]
public void TestImportDirective() {
    var source = @"
        import System
        import static MyUtils
    ";

    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();

    Assert.Equal(2, ast.Imports.Count);
    Assert.Equal("System", ast.Imports[0].Namespace);
    Assert.False(ast.Imports[0].IsStatic);
    Assert.Equal("MyUtils", ast.Imports[1].Namespace);
    Assert.True(ast.Imports[1].IsStatic);
}

[Fact]
public void TestImportTranspilesToUsing() {
    var source = @"
        import System
        import static Console
    ";

    var csharp = Transpile(source);

    Assert.Contains("using System;", csharp);
    Assert.Contains("using static Console;", csharp);
}
```

## Documentation Updates

**Files to update:**
- `DESIGN.md` - Change all `using` to `import`
- `README.md` - Update examples
- `memory/components/parser.md` - Update import directive docs
- `memory/components/analyzer.md` - Update import resolution
- `memory/features/interop.md` - Update .NET interop examples

**Example update:**
```markdown
### Imports

Import .NET namespaces with the `import` keyword:

// Import namespace
import System
import System.Collections.Generic

// Import static class
import static System.Console
import static System.Math

Functions and types from static imports can be used without qualification:

WriteLine("Hello")  // Console.WriteLine
Sqrt(16)            // Math.Sqrt
```

## Testing Checklist

- [ ] Lexer recognizes `import` keyword
- [ ] Parser parses `import` directives correctly
- [ ] Parser parses `import static` correctly
- [ ] Transpiler emits C# `using` statements
- [ ] Analyzer resolves imported namespaces
- [ ] Analyzer resolves static imports
- [ ] All existing tests updated and pass
- [ ] All examples updated to use `import`
- [ ] Documentation updated

## Success Criteria

- [ ] `import` keyword works for namespaces
- [ ] `import static` works for static classes
- [ ] Transpiles to correct C# `using` statements
- [ ] All tests pass
- [ ] All examples use `import` instead of `using`
- [ ] Documentation updated
- [ ] No breaking changes to functionality

## Migration

Since this is a breaking change for existing N# code:

1. Update all examples first
2. Update all tests
3. Make the language change
4. Verify everything still works

## Future: File Imports

Once this is done, we can add file imports later:

```n#
import "./models/Person.nl"       // Relative import
import "../utils/Helpers.nl"      // Parent directory
import "shared/Constants.nl"      // From project root
```

This would:
1. Parse the file
2. Add its declarations to the current compilation
3. Resolve symbols across files

But that's a separate task. For now, just replace `using` with `import`.

## Notes

- `import` is more intuitive and aligns with modern languages
- Still transpiles to C# `using` - no change in output
- Sets us up for file imports in the future
- Less "C# clone" feel, more "modern language on .NET"
