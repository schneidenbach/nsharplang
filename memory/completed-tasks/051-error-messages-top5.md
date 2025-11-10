# Task 051: Error Messages (Top 5)

**Effort:** Medium (6-8 hours)
**Depends:** None
**Ships:** Better errors for common mistakes

## Goal

Improve error messages for the 5 most common errors.

## Top 5 Errors

1. **Undefined identifier**
2. **Type mismatch**
3. **Missing semicolon/syntax**
4. **Wrong number of arguments**
5. **Cannot find import**

## Implementation

### Before
```
Error NL103: Undefined identifier 'Foo'
  --> Program.nl:5:10
```

### After
```
error[NL103]: cannot find type 'Foo' in this scope
  --> Program.nl:5:10
   |
 5 | x := new Foo()
   |          ^^^ not found
   |
help: you might be missing an import
   | import MyNamespace
   |
note: there is a type 'Foo' in namespace 'MyNamespace'
```

## Changes

Update `src/Compiler/ErrorReporting.cs`:

```csharp
public static string FormatError(CompileError error)
{
    var sb = new StringBuilder();

    // Header
    sb.AppendLine($"error[{error.Code}]: {error.Message}");
    sb.AppendLine($"  --> {error.File}:{error.Line}:{error.Column}");
    sb.AppendLine("   |");

    // Context line
    sb.AppendLine($" {error.Line} | {GetSourceLine(error)}");
    sb.AppendLine($"   | {GetCarets(error)}");
    sb.AppendLine("   |");

    // Help text if available
    if (error.HelpText != null)
    {
        sb.AppendLine($"help: {error.HelpText}");
        if (error.Suggestion != null)
            sb.AppendLine($"   | {error.Suggestion}");
    }

    return sb.ToString();
}
```

## Done When

- [ ] Top 5 errors have better messages
- [ ] Include suggestions
- [ ] Show context
- [ ] Colored in terminal
