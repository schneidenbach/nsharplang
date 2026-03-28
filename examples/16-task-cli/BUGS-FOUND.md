# Bugs Found During Task CLI Stress Test

Issues discovered while building a non-trivial N# CLI application (examples/16-task-cli).

## Compiler Bugs

### BUG-1: `new Type[] { ... }` array initializer syntax not supported
**Severity**: Medium
**File**: Services/Store.nl

The parser interprets `{` after `new string[]` as an object initializer and expects property names:
```nl
// BROKEN: Parser error NL102 "Expected property name"
parts := trimmed.Split(new string[] { "|" }, StringSplitOptions.None)
```

**Workaround**: Assign the delimiter to a variable first, then use the string overload of `Split`:
```nl
pipeDelim := "|"
parts := trimmed.Split(pipeDelim)
```

**Expected**: `new Type[] { value1, value2 }` should be valid syntax for creating arrays.

---

### BUG-2: Async return type validation incorrect for `Task<T>` methods
**Severity**: High
**File**: Services/Store.nl, Services/TaskService.nl

The N# analyzer requires the return expression type to match the full `Task<T>` return type, even though async methods in C# automatically wrap the return value:
```nl
// BROKEN: NL202 "actual: List<TaskItem>, expected: Task<List<TaskItem>>"
func async Load(): Task<List<TaskItem>> {
    return new List<TaskItem>()  // This should be valid in async context
}
```

**Workaround**: Use `return await Task.FromResult(value)` to satisfy the type checker:
```nl
func async Load(): Task<List<TaskItem>> {
    empty := new List<TaskItem>()
    return await Task.FromResult(empty)
}
```

**Expected**: In async methods, `return T` should be valid when the return type is `Task<T>`.

---

### BUG-3: Void async methods (`Task` return) report "not all code paths return"
**Severity**: High
**File**: Services/Store.nl, Services/TaskService.nl

Async methods that return `Task` (void async) require an explicit return value, but there's nothing meaningful to return:
```nl
// BROKEN: NL305 "Not all code paths return a value of type 'Task'"
func async Save(tasks: List<TaskItem>): Task {
    await File.WriteAllLinesAsync(filePath, lines)
    // No return needed - this is void async
}
```

**Workaround**: Change return type to `Task<bool>` and return a dummy value:
```nl
func async Save(tasks: List<TaskItem>): Task<bool> {
    await File.WriteAllLinesAsync(filePath, lines)
    return await Task.FromResult(true)
}
```

**Expected**: `func async Foo(): Task` should not require a return statement.

---

### BUG-4: `int.TryParse` not recognized outside `if` context
**Severity**: Medium
**File**: Commands/DoneCommand.nl, Commands/DeleteCommand.nl

Calling `int.TryParse(s, out result)` as a standalone expression fails with "Variable 'int' not found". It appears to only work inside an `if` condition:
```nl
// BROKEN: NL301 "Variable 'int' not found"
success := int.TryParse(s, out result)

// Also broken with Int32:
if Int32.TryParse(s, out parsed) {  // NL301 "Variable 'parsed' not found"
    return parsed
}
```

The `out` variable declaration pattern doesn't work — the compiler doesn't recognize `out varName` as an implicit variable declaration.

**Workaround**: Use try-catch with `Int32.Parse` instead:
```nl
result := -1
try {
    result = Int32.Parse(s)
} catch {
    result = -1
}
return result
```

**Expected**: `out varName` should declare a new variable (like C#'s `out var`).

---

### BUG-5: `try-catch` not recognized for exhaustive return analysis
**Severity**: Low
**File**: Commands/DoneCommand.nl, Commands/DeleteCommand.nl

A function with `return` in both `try` and `catch` blocks reports "not all code paths return a value":
```nl
// BROKEN: NL305 "Not all code paths return a value of type 'int'"
static func ParseId(s: string): int {
    try {
        return Int32.Parse(s)
    } catch {
        return -1
    }
}
```

**Workaround**: Assign to a variable in both branches, then return after:
```nl
result := -1
try {
    result = Int32.Parse(s)
} catch {
    result = -1
}
return result
```

**Expected**: If all branches of try-catch return, the function should be considered exhaustive.

---

### BUG-6: Match expression variable name collision with destructured union fields
**Severity**: Medium
**File**: Services/Formatter.nl

When a match expression destructures union fields, the field name cannot match the outer variable name. This generates a C# CS0136 error:
```nl
// BROKEN: CS0136 "A local named 'message' cannot be declared in this scope"
message := match result {
    CommandResult.Success { message } => message,
    CommandResult.Error { message } => $"Error: {message}",
    _ => "Unknown result"
}
```

**Workaround**: Use a different name for the outer variable:
```nl
output := match result {
    CommandResult.Success { message } => message,
    CommandResult.Error { message } => $"Error: {message}",
    _ => "Unknown result"
}
```

**Expected**: The transpiler should generate unique variable names for destructured fields to avoid shadowing.

---

### BUG-7: No char literal support
**Severity**: Low

The lexer has no `CharLiteral` token type, meaning character literals like `'|'` are not supported. This matters for methods like `String.Split(char)`:
```nl
// Not possible: no char literal syntax
parts := line.Split('|')
```

**Workaround**: Use string overloads via variables:
```nl
delim := "|"
parts := line.Split(delim)
```

**Expected**: Support `'x'` char literal syntax, especially for C# interop with methods that take `char` parameters.

---

### BUG-8: Tests in exe projects require `.csproj` workaround
**Severity**: Medium

When a `.tests.nl` file exists in an `exe` project, the test SDK generates a conflicting `Program.cs` entry point. This requires adding `<GenerateProgramFile>false</GenerateProgramFile>` to the .csproj:
```xml
<!-- Required workaround -->
<Project Sdk="NSharpLang.Sdk/0.1.0">
  <PropertyGroup>
    <GenerateProgramFile>false</GenerateProgramFile>
  </PropertyGroup>
</Project>
```

**Expected**: The N# SDK should automatically set `GenerateProgramFile=false` when it detects both an entry point and test files. Or, tests in exe projects should "just work."

---

### BUG-9: SDK version must be specified in `.csproj`
**Severity**: Low

`<Project Sdk="NSharpLang.Sdk" />` fails with "no version specified". The NuGet SDK resolver requires an explicit version:
```xml
<!-- BROKEN -->
<Project Sdk="NSharpLang.Sdk" />

<!-- WORKS -->
<Project Sdk="NSharpLang.Sdk/0.1.0" />
```

This is inconsistent with other examples (e.g., 15-dogfood-project) that use the bare SDK name and work because they have cached restore info.

**Expected**: Either use a `global.json` to pin the SDK version, or document that the version must be specified.

---

## Syntax / Ergonomics Issues

### ERGO-1: Catch clause uses C# syntax, not N# syntax
The catch clause uses `catch (Type varName) { }` (type-first, C# style) rather than the N# parameter convention of `catch (varName: Type) { }`. This is inconsistent with the rest of the language.

### ERGO-2: No string-based `Split` convenience
Splitting strings requires workarounds since there are no char literals and `new string[] { }` initializers don't work. A built-in split function or method would be helpful.

### ERGO-3: Lambda type inference limitations affect LINQ
Complex LINQ chains with lambdas (like `tags.Select(t => $"#{t}")`) may fail due to lambda type inference limitations. Manual loops are needed as fallbacks.

---

## Features That Worked Well

- **Discriminated unions**: `union Status { Todo, InProgress, Done }` worked perfectly for modeling state
- **Pattern matching on unions**: `match status { Status.Todo => ... }` is clean and readable
- **Records with `with` expressions**: `task with { Status: new Status.Done {} }` is ergonomic
- **Multi-file projects**: Namespace-based imports and file imports both work well
- **Enum integration**: Int enums work seamlessly with pattern matching and C# interop
- **Async/await**: Once workarounds are applied, async I/O works correctly
- **String interpolation**: `$"Created task #{id}: {title}"` works throughout
- **Test framework**: `test "description" { assert ... }` is clean and tests all pass
- **LINQ basics**: `.ToList()`, `.Contains()`, basic queries work well
- **Type aliases**: `type TaskId = int` works as documentation
