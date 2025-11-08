# Error Reporting Component

**File:** `src/Compiler/ErrorReporting.cs`

## Responsibility

Professional error messages with codes, suggestions, and formatting (Rust-quality diagnostics).

## Error Codes

### Syntax Errors (100-199)
- `NL101`: Unexpected token
- `NL102`: Missing token
- `NL103`: Invalid syntax

### Type Errors (200-299)
- `NL201`: Type mismatch
- `NL202`: Undefined type
- `NL203`: Cannot infer type
- `NL204`: Invalid type conversion

### Semantic Errors (300-399)
- `NL301`: Undefined variable
- `NL302`: Undefined function
- `NL303`: Duplicate declaration
- `NL304`: Uninitialized field

### Function/Method Errors (400-499)
- `NL401`: Wrong argument count
- `NL402`: Wrong argument type
- `NL403`: Cannot resolve overload
- `NL404`: Return type mismatch

### Pattern Matching Errors (500-599)
- `NL501`: Non-exhaustive match
- `NL502`: Invalid pattern
- `NL503`: Guard must be boolean
- `NL504`: Unknown union case

### Operator Errors (600-699)
- `NL601`: Invalid operand type
- `NL602`: Cannot overload operator

### Import/Using Errors (700-799)
- `NL701`: File not found
- `NL702`: Symbol collision
- `NL703`: Circular import

### Class/Struct/Interface Errors (800-899)
- `NL801`: Interface not implemented
- `NL802`: Abstract method not implemented
- `NL803`: Invalid member access

### Warnings (900-999)
- `NL901`: Unused variable
- `NL902`: Unreachable code
- `NL903`: Non-conventional naming

## CompilerError Record

```csharp
public record CompilerError(
    ErrorCode Code,
    string Message,
    string FileName,
    int Line,
    int Column,
    string? SourceSnippet = null,
    string? Suggestion = null
);
```

## Error Formatting

Errors use Rust-style formatting:

```
error[NL201]: Type mismatch in assignment
  --> example.nl:5:10
   |
 5 |     let x: int = "hello"
   |                  ^^^^^^^ expected 'int', found 'string'
   |
   = help: Change the type annotation or use a compatible value
```

Components:
1. **Error level**: `error` or `warning`
2. **Error code**: `[NL201]`
3. **Message**: Human-readable description
4. **Location**: `filename:line:column`
5. **Source snippet**: Code with position markers
6. **Suggestion**: Helpful hint

## Suggestions

Context-aware suggestions powered by `ErrorSuggestions` class:

### Type Not Found
Uses Levenshtein distance to find similar names:
```
error[NL202]: Type 'Consol' not found
   = help: Did you mean 'Console'?
```

### Missing Return
Suggests adding return or changing to void:
```
error[NL404]: Function must return a value
   = help: Add a return statement or change return type to 'void'
```

### Non-Exhaustive Match
Lists missing union cases:
```
error[NL501]: Match expression is not exhaustive
   = help: Missing cases: Failure, Pending
```

### Wrong Naming Convention
Suggests following convention:
```
warning[NL903]: Public member 'myField' should use PascalCase
   = help: Consider renaming to 'MyField'
```

## Color Output

Terminal output uses ANSI colors:
- **Red**: Error labels, error codes
- **Yellow**: Warning labels
- **Blue**: File locations, suggestions
- **White**: Message text
- **Gray**: Source code snippets

## Multi-Error Display

CLI displays all errors found, not just the first:
```
error[NL201]: Type mismatch at line 5
error[NL301]: Undefined variable at line 8
error[NL501]: Non-exhaustive match at line 12

3 errors found, compilation aborted
```

## Testing

Error reporting has comprehensive tests covering:
- Error code assignment
- Message formatting
- Suggestion generation
- Color codes (optional, based on terminal support)

## Usage in Analyzer

```csharp
// Report error
errors.Add(CompilerError.Create(
    ErrorCode.TypeMismatch,
    $"Cannot assign '{sourceType}' to '{targetType}'",
    fileName,
    line,
    column,
    suggestion: "Change the type or use a conversion operator"
));
```

## Benefits

- **Developer-friendly**: Clear, actionable error messages
- **Professional**: Matches Rust, TypeScript error quality
- **Searchable**: Error codes enable documentation lookup
- **Helpful**: Suggestions guide users to solutions
- **Foundation for IDE**: Error codes/suggestions work with LSP
