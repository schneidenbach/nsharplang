# Task 026: Package Keyword for Top-Level Functions

**Status:** 🔲 TODO
**Priority:** Medium
**Dependencies:** None
**Estimated Effort:** Medium (6-8 hours)

## Goal

Add optional `package` keyword to give top-level functions an explicit static class name, making the generated C# more predictable and usable.

## Current Behavior

Top-level functions transpile to `internal static class _TopLevel`:

```n#
func Add(a: int, b: int): int => a + b
```

Transpiles to:
```csharp
internal static class _TopLevel {
    internal static int Add(int a, int b) => a + b;
}
```

**Problems:**
- `_TopLevel` is an ugly implementation detail
- Multiple files create name collision
- C# consumers can't use functions (internal)

## Desired Behavior

### With Package Declaration

```n#
package MathUtils

func Add(a: int, b: int): int => a + b
func Multiply(a: int, b: int): int => a * b
```

Transpiles to:
```csharp
public static class MathUtils {
    public static int Add(int a, int b) => a + b;
    public static int Multiply(int a, int b) => a * b;
}
```

### Without Package Declaration

Falls back to current behavior (`_TopLevel`):

```n#
func Helper(): string => "test"
```

Transpiles to:
```csharp
internal static class _TopLevel {
    internal static string Helper() => "test";
}
```

### Multiple Files, Same Package

```n#
// File: math1.nl
package MathUtils
func Add(a: int, b: int): int => a + b

// File: math2.nl
package MathUtils
func Multiply(a: int, b: int): int => a * b
```

Transpiles to:
```csharp
// math1.g.cs
public static partial class MathUtils {
    public static int Add(int a, int b) => a + b;
}

// math2.g.cs
public static partial class MathUtils {
    public static int Multiply(int a, int b) => a * b;
}
```

## Implementation

### 1. Lexer Changes

**File:** `src/Compiler/Lexer.cs`

Add `package` keyword to keyword list:
```csharp
private static readonly Dictionary<string, TokenType> Keywords = new() {
    // ... existing keywords
    { "package", TokenType.Package },
};
```

Add token type:
```csharp
public enum TokenType {
    // ... existing types
    Package,
}
```

### 2. AST Changes

**File:** `src/Compiler/Ast/Declarations.cs`

Add `PackageDeclaration`:
```csharp
public record PackageDeclaration(
    string Name,              // e.g., "MathUtils" or "MyCompany.Utils"
    Location Location
) : Declaration(Location);
```

Update `CompilationUnit`:
```csharp
public record CompilationUnit(
    List<UsingDirective> Usings,
    PackageDeclaration? Package,     // NEW: optional package
    List<Declaration> Declarations,
    Location Location
) : AstNode(Location);
```

### 3. Parser Changes

**File:** `src/Compiler/Parser.cs`

Parse package declaration (must come after usings, before declarations):

```csharp
public CompilationUnit ParseCompilationUnit() {
    var usings = new List<UsingDirective>();
    while (Current.Type == TokenType.Using) {
        usings.Add(ParseUsingDirective());
    }

    // Parse optional package declaration
    PackageDeclaration? package = null;
    if (Current.Type == TokenType.Package) {
        package = ParsePackageDeclaration();
    }

    var declarations = new List<Declaration>();
    while (Current.Type != TokenType.Eof) {
        declarations.Add(ParseDeclaration());
    }

    return new CompilationUnit(usings, package, declarations, Location.None);
}

private PackageDeclaration ParsePackageDeclaration() {
    var packageToken = Expect(TokenType.Package);

    // Parse package name (identifier or dotted name)
    var name = Expect(TokenType.Identifier).Value;

    // Allow dotted names: package MyCompany.Utils
    while (Current.Type == TokenType.Dot) {
        Advance(); // consume dot
        name += "." + Expect(TokenType.Identifier).Value;
    }

    return new PackageDeclaration(name, packageToken.Location);
}
```

### 4. Analyzer Changes

**File:** `src/Compiler/Analyzer.cs`

- Validate package name is valid identifier
- Track package name for function resolution
- Update function resolution to look in package classes

```csharp
public AnalysisResult Analyze(CompilationUnit ast) {
    // Validate package name if present
    if (ast.Package != null) {
        ValidatePackageName(ast.Package.Name);
    }

    // Rest of analysis...
}

private void ValidatePackageName(string name) {
    // Package name must be valid C# identifier(s)
    var parts = name.Split('.');
    foreach (var part in parts) {
        if (!IsValidIdentifier(part)) {
            ReportError($"Invalid package name: '{part}'");
        }
    }
}
```

### 5. Transpiler Changes

**File:** `src/Compiler/Transpiler.cs`

Track package info and emit appropriate static class:

```csharp
private string? _currentPackage;
private Dictionary<string, bool> _packageHasMultipleFiles = new();

public string Transpile(CompilationUnit ast) {
    _output = new StringBuilder();

    // Track package
    _currentPackage = ast.Package?.Name;

    // Emit usings
    foreach (var usingDir in ast.Usings) {
        TranspileUsingDirective(usingDir);
    }

    // Collect top-level functions
    var topLevelFunctions = ast.Declarations
        .OfType<FunctionDeclaration>()
        .Where(f => !IsExtensionMethod(f))
        .ToList();

    // Collect other declarations (classes, structs, etc.)
    var typeDeclarations = ast.Declarations
        .Where(d => d is not FunctionDeclaration || IsExtensionMethod((FunctionDeclaration)d))
        .ToList();

    // Emit top-level functions in package/class
    if (topLevelFunctions.Any()) {
        EmitTopLevelClass(topLevelFunctions);
    }

    // Emit type declarations
    foreach (var decl in typeDeclarations) {
        TranspileDeclaration(decl);
    }

    return _output.ToString();
}

private void EmitTopLevelClass(List<FunctionDeclaration> functions) {
    var className = _currentPackage ?? "_TopLevel";
    var visibility = _currentPackage != null ? "public" : "internal";
    var partial = ShouldBePartial(className) ? "partial " : "";

    _output.AppendLine($"{visibility} static {partial}class {className}");
    _output.AppendLine("{");
    _indentLevel++;

    foreach (var func in functions) {
        TranspileFunctionDeclaration(func);
    }

    _indentLevel--;
    _output.AppendLine("}");
}

private bool ShouldBePartial(string className) {
    // Check if we've seen this package name before across files
    // This requires tracking across multiple transpilation calls
    // For now, always emit partial for non-_TopLevel
    return className != "_TopLevel";
}
```

### 6. Multi-File Handling

When building multiple files with same package, need to:
1. Track which packages have been seen across files
2. Mark them as `partial` in generated code
3. Ensure they're all in same namespace

**This might require changes to CLI build command** to coordinate across files.

### 7. Using Static Support

Update parser to recognize `using static`:

```csharp
private UsingDirective ParseUsingDirective() {
    Expect(TokenType.Using);

    bool isStatic = false;
    if (Current.Type == TokenType.Static) {
        Advance();
        isStatic = true;
    }

    var name = ParseQualifiedName();

    return new UsingDirective(name, isStatic, Location.None);
}
```

Update AST:
```csharp
public record UsingDirective(
    string Namespace,
    bool IsStatic,        // NEW
    Location Location
) : AstNode(Location);
```

Transpile:
```csharp
private void TranspileUsingDirective(UsingDirective usingDir) {
    if (usingDir.IsStatic) {
        _output.AppendLine($"using static {usingDir.Namespace};");
    } else {
        _output.AppendLine($"using {usingDir.Namespace};");
    }
}
```

### 8. Function Resolution in Analyzer

Update to resolve functions from packages:

```csharp
private TypeInfo? ResolveFunction(string name) {
    // 1. Local functions in current scope
    if (_currentScope.TryLookup(name, out var local)) {
        return local;
    }

    // 2. Functions in current package/file
    if (TryResolveFunctionInCurrentPackage(name, out var pkgFunc)) {
        return pkgFunc;
    }

    // 3. Static imports (using static)
    foreach (var staticUsing in _staticUsings) {
        if (TryResolveStaticMethod(staticUsing, name, out var method)) {
            return method;
        }
    }

    // 4. Extension methods
    // ... existing logic

    return null;
}
```

## Testing

### Parser Tests

```csharp
[Fact]
public void TestPackageDeclaration() {
    var source = @"
        package MathUtils

        func Add(a: int, b: int): int {
            return a + b
        }
    ";

    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();

    Assert.NotNull(ast.Package);
    Assert.Equal("MathUtils", ast.Package.Name);
}

[Fact]
public void TestDottedPackageName() {
    var source = "package MyCompany.Utils.Math";

    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();

    Assert.Equal("MyCompany.Utils.Math", ast.Package.Name);
}

[Fact]
public void TestNoPackageDeclaration() {
    var source = "func Add(a: int, b: int): int => a + b";

    var tokens = new Lexer(source, "test").Tokenize();
    var ast = new Parser(tokens, "test").ParseCompilationUnit();

    Assert.Null(ast.Package);
}
```

### Transpiler Tests

```csharp
[Fact]
public void TestPackageTranspilation() {
    var source = @"
        package MathUtils

        func Add(a: int, b: int): int => a + b
    ";

    var csharp = Transpile(source);

    Assert.Contains("public static class MathUtils", csharp);
    Assert.Contains("public static int Add(int a, int b)", csharp);
}

[Fact]
public void TestNoPackageUsesTopLevel() {
    var source = "func Add(a: int, b: int): int => a + b";

    var csharp = Transpile(source);

    Assert.Contains("internal static class _TopLevel", csharp);
}

[Fact]
public void TestUsingStaticTranspilation() {
    var source = @"
        using static MathUtils

        func Main() {
            result := Add(1, 2)
        }
    ";

    var csharp = Transpile(source);

    Assert.Contains("using static MathUtils;", csharp);
}
```

### Integration Tests

```csharp
[Fact]
public void TestPackageFunctionCall() {
    var mathUtils = @"
        package MathUtils
        func Add(a: int, b: int): int => a + b
    ";

    var main = @"
        using static MathUtils

        func Main() {
            result := Add(1, 2)
            print result
        }
    ";

    // Build both files together
    var result = BuildAndRun(new[] { mathUtils, main });

    Assert.Equal("3", result.Output.Trim());
}
```

## Documentation Updates

**Files to update:**
- `DESIGN.md` - Add package keyword documentation
- `memory/features/` - Create new file for modules/packages
- `memory/components/transpiler.md` - Document top-level function handling
- Update examples to use `package` where appropriate

## Success Criteria

- [ ] `package` keyword parsed correctly
- [ ] Package name validation works
- [ ] Top-level functions emit in correct static class
- [ ] Package name becomes class name
- [ ] No package → uses `_TopLevel`
- [ ] Multiple files with same package → `partial` classes
- [ ] `using static` works for importing packages
- [ ] Visibility: package functions are public, _TopLevel are internal
- [ ] All tests pass
- [ ] Documentation updated
- [ ] Examples updated to use package

## Examples

### Simple Package

```n#
// File: MathUtils.nl
package MathUtils

func Add(a: int, b: int): int => a + b
func Multiply(a: int, b: int): int => a * b
```

### Using Package

```n#
// File: Program.nl
using static MathUtils

func Main() {
    sum := Add(1, 2)
    print sum
}
```

### Split Across Files

```n#
// File: StringUtils1.nl
package StringUtils

func IsEmpty(s: string): bool => s.Length == 0

// File: StringUtils2.nl
package StringUtils

func Truncate(s: string, max: int): string {
    if s.Length <= max {
        return s
    }
    return s.Substring(0, max)
}
```

Both transpile to `public static partial class StringUtils { ... }`

## Notes

This makes N# honest about .NET/CLR reality: top-level functions are just static methods on a static class. The `package` keyword makes this explicit and predictable for both N# and C# consumers.
