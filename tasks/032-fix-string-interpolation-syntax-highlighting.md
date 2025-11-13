# Task 032: Fix String Interpolation Syntax Highlighting

## Problem
In string interpolations, variables inside `{name}` are not being highlighted properly. They should be scoped as variables, not as part of the string literal.

### Code Example
```nsharp
name := "World"
greeting := $"Hello, {name}!"
```

**Expected**: `name` inside `{...}` should be highlighted as a variable (black text)
**Actual**: `name` is highlighted as part of the string (likely green/string color)

## Root Cause
The TextMate grammar in `editors/vscode/syntaxes/nsharp.tmLanguage.json` needs to properly scope string interpolation expressions. Currently, it likely treats the entire `$"Hello, {name}!"` as a single string token.

## Reference Implementation
Look at how C# and other languages handle this in their TextMate grammars:
- **C#**: `https://github.com/dotnet/csharp-tmLanguage/blob/main/grammars/csharp.tmLanguage`
- **TypeScript**: How they handle template literals `${expr}`
- **Kotlin**: How they handle string templates `$name` and `${expr}`

### C# Grammar Pattern
C# uses nested patterns like:
```json
{
    "name": "string.quoted.double.interpolated.cs",
    "begin": "\\$\"",
    "end": "\"",
    "patterns": [
        {
            "name": "meta.interpolation.cs",
            "begin": "\\{",
            "end": "\\}",
            "patterns": [
                {
                    "include": "#expression"
                }
            ]
        },
        {
            "name": "constant.character.escape",
            "match": "\\\\."
        }
    ]
}
```

## Proposed Fix
Update `editors/vscode/syntaxes/nsharp.tmLanguage.json`:

1. Find the string interpolation pattern (likely starts with `\$"`)
2. Add nested `patterns` array to handle interpolation expressions
3. Include expression scoping inside `{...}`

### Example Pattern Structure
```json
{
    "name": "string.quoted.double.interpolated.nsharp",
    "begin": "\\$\"",
    "end": "\"",
    "beginCaptures": {
        "0": { "name": "punctuation.definition.string.begin.nsharp" }
    },
    "endCaptures": {
        "0": { "name": "punctuation.definition.string.end.nsharp" }
    },
    "patterns": [
        {
            "name": "meta.interpolation.nsharp",
            "begin": "\\{",
            "end": "\\}",
            "beginCaptures": {
                "0": { "name": "punctuation.definition.interpolation.begin.nsharp" }
            },
            "endCaptures": {
                "0": { "name": "punctuation.definition.interpolation.end.nsharp" }
            },
            "patterns": [
                {
                    "include": "#expressions"
                }
            ]
        },
        {
            "name": "constant.character.escape.nsharp",
            "match": "\\\\[\\\\\"'nrt]"
        }
    ]
}
```

## Test Cases
Create a test file `test_interpolation.nl`:
```nsharp
func test() {
    name := "World"
    age := 25
    greeting := $"Hello, {name}!"
    message := $"Name: {name}, Age: {age}"
    complex := $"Result: {computeValue()}"
}
```

Expected highlighting:
- `name`, `age` inside `{...}` should use variable color
- `computeValue()` should highlight method call
- String parts should remain string color

## Files to Modify
- `editors/vscode/syntaxes/nsharp.tmLanguage.json` - Add interpolation patterns

## Testing
1. Open VS Code with the N# extension
2. Create a file with string interpolations
3. Verify that:
   - Variables inside `{...}` are highlighted as variables
   - Method calls inside `{...}` are highlighted properly
   - String parts remain string-colored
   - Escape sequences work: `$"Test \\{not_interpolated\\}"`

## Priority
MEDIUM - This is a cosmetic issue but impacts developer experience
