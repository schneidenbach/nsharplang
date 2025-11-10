# Task 052: Basic Linter (3 Rules)

**Effort:** Medium (8-10 hours)
**Depends:** None
**Ships:** Linter with 3 rules

## Goal

Implement linter with 3 basic rules.

## Rules

### NL001: Unused Variable
```n#
func main() {
    x := 5  // warning: unused variable 'x'
}
```

### NL002: Missing Import
```n#
func main() {
    list := new List<int>()  // error: 'List' not found
    // suggestion: import System.Collections.Generic
}
```

### NL003: Unnecessary Null Check
```n#
x: int = 5
if x != null {  // warning: 'int' is never null
    // ...
}
```

## Implementation

Create `src/Linter/Linter.cs`:

```csharp
public class Linter
{
    public List<Diagnostic> Lint(CompilationUnit ast)
    {
        var diagnostics = new List<Diagnostic>();

        var visitor = new LintVisitor();
        visitor.Visit(ast);

        diagnostics.AddRange(visitor.UnusedVariables);
        diagnostics.AddRange(visitor.MissingImports);
        diagnostics.AddRange(visitor.UnnecessaryNullChecks);

        return diagnostics;
    }
}

public class Diagnostic
{
    public string Code { get; set; }
    public string Message { get; set; }
    public Location Location { get; set; }
    public DiagnosticSeverity Severity { get; set; }
}

public enum DiagnosticSeverity
{
    Warning,
    Error,
    Info
}
```

## Testing

```csharp
[Fact]
public void Lint_DetectsUnusedVariable()
{
    var source = "func main() { x := 5 }";
    var diagnostics = Lint(source);

    Assert.Single(diagnostics);
    Assert.Equal("NL001", diagnostics[0].Code);
}
```

## Done When

- [ ] 3 rules implemented
- [ ] Warnings shown in output
- [ ] Tests for each rule
- [ ] Can be extended later
