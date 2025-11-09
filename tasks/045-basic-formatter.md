# Task 045: Basic Code Formatter

**Effort:** Small (6-8 hours)
**Depends:** None
**Ships:** Formatter that fixes indentation

## Goal

Format N# code with correct indentation and spacing.

## Deliverable

Formatter class that formats AST to string.

## Implementation

Create `src/Formatter/Formatter.cs`:

```csharp
public class Formatter
{
    private int _indent = 0;
    private const string IndentString = "    "; // 4 spaces

    public string Format(CompilationUnit ast)
    {
        var sb = new StringBuilder();

        foreach (var decl in ast.Declarations)
        {
            FormatDeclaration(decl, sb);
        }

        return sb.ToString();
    }

    private void FormatDeclaration(Declaration decl, StringBuilder sb)
    {
        switch (decl)
        {
            case FunctionDeclaration func:
                Indent(sb);
                sb.Append($"func {func.Name}(");
                // ... format parameters
                sb.Append(") {");
                sb.AppendLine();
                _indent++;
                FormatBlock(func.Body, sb);
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
                break;

            // ... other declarations
        }
    }

    private void Indent(StringBuilder sb)
    {
        for (int i = 0; i < _indent; i++)
            sb.Append(IndentString);
    }
}
```

## Testing

```csharp
[Fact]
public void Format_FixesIndentation()
{
    var input = "func main(){print 5}";
    var expected = @"func main() {
    print 5
}";

    var ast = Parse(input);
    var result = new Formatter().Format(ast);

    Assert.Equal(expected, result);
}
```

## Done When

- [ ] Formats functions correctly
- [ ] Indentation is consistent
- [ ] Spacing around operators
- [ ] Tests pass
