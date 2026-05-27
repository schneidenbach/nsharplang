# C# Export Component

**File:** `src/NSharpLang.Compiler/Transpiler.cs`

## Responsibility

Converts the AST to C# source code for `nlc export csharp` and export-focused tests.

## Design Pattern

**Visitor Pattern**: Recursively traverses AST and builds C# code string.

## Output Style

- Clean, readable C#
- Proper indentation (4 spaces per level)
- Preserves code structure from N#
- Generates valid C# that compiles without warnings

## Transpilation Strategies

### Union Types
N# union → C# abstract base class with nested record cases

**N# code:**
```
union Result<T> {
    Success { value: T }
    Failure { error: string }
}
```

**Generated C#:**
```csharp
public abstract record Result<T>
{
    public sealed record Success(T Value) : Result<T>;
    public sealed record Failure(string Error) : Result<T>;
}
```

### Duck Interfaces
N# duck interface → C# internal interface

**N# code:**
```
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string => "file contents"
}
```

**Generated C#:**
```csharp
internal interface IReader
{
    string Read();
}

public class FileReader : IReader  // Automatically implements
{
    public string Read() => "file contents";
}
```

The exporter detects structural compatibility and adds interface implementation automatically.

### String Enums
N# string enum → C# static class with const strings

**N# code:**
```
enum Status: string {
    Active = "active"
    Inactive = "inactive"
}
```

**Generated C#:**
```csharp
public static class Status
{
    public const string Active = "active";
    public const string Inactive = "inactive";
}
```

### Top-Level Functions
N# top-level functions → C# internal static class

**N# code:**
```
func Add(a: int, b: int) => a + b
```

**Generated C#:**
```csharp
internal static class TopLevelFunctions
{
    public static int Add(int a, int b) => a + b;
}
```

### Type Aliases
N# type alias → C# file-scoped `using` alias directive with fully qualified type names

**N# code:**
```
type StringDict = Dictionary<string, string>
type Callback = Func<void>
```

**Generated C#:**
```csharp
using StringDict = System.Collections.Generic.Dictionary<string, string>;
using Callback = System.Action;
```

Using aliases are emitted at the top of the file, after namespace imports but before namespace/class declarations. Well-known .NET types are mapped to their fully qualified names. `Func<void>` maps to `System.Action`.

## Convention to Explicit Modifiers

N# uses naming conventions for visibility:
- `PascalCase` → public
- `camelCase` → private

The exporter converts convention-based visibility to explicit C# modifiers:
```
// N# (PascalCase = public by convention)
class Person {
    Name: string
}

// Generated C# (explicit public)
public class Person
{
    public string Name { get; set; }
}
```

## Special Cases

### String Literals
Lexer stores strings WITH quotes, so the exporter emits them as-is:
```csharp
// Token value: "hello"
// Transpiled: "hello" (no extra quotes needed)
```

### Array Literals
When an inferred declaration uses an array literal, the exporter emits an explicit array type:
```
let items := [1, 2, 3]

// Transpiles to:
int[] items = [1, 2, 3];  // NOT: var items = [1, 2, 3];
```

This avoids C# 12 collection expression ambiguity.

### Async Iterator Functions
`async func*` exports to `async IAsyncEnumerable<T>`:
```
async func* GetNumbers(): IAsyncEnumerable<int> {
    yield 1
}

// Transpiles to:
public static async IAsyncEnumerable<int> GetNumbers()
{
    yield return 1;
}
```

**Important:** NOT wrapped in `Task<>` or `ValueTask<>`.

### Error Handling Pattern
N# `result, err := Function()` exports to try-catch:
```
result, err := MightFail()

// Transpiles to:
object result;
Exception? err;
try
{
    result = MightFail();
    err = null;
}
catch (Exception ex)
{
    result = null;
    err = ex;
}
```

### Yield Break
`yield break` exports directly to C# `yield break;`:
```
yield break  // N#
yield break; // C#
```

## Indentation Management

The exporter tracks indentation level:
- `_indent`: Current indentation level
- `Indent()`: Increase level
- `Unindent()`: Decrease level
- `GetIndent()`: Returns spaces for current level

## Using Statement Generation

The exporter emits C# using statements from N# imports:
```
using System
using System.Collections.Generic

// Transpiles to:
using System;
using System.Collections.Generic;
```

Aliased imports:
```
import System.Collections.Generic as Collections

// Transpiles to:
using Collections = System.Collections.Generic;
```

Duplicate usings are filtered out.

## Testing

The C# export path has dedicated unit tests covering:
- All expression types
- All statement types
- All declaration types
- Special cases (unions, duck interfaces, string enums)
- Indentation correctness
- C# syntax validity

See `tests/TranspilerTests.cs`.

## Usage Example

```csharp
var ast = parser.ParseCompilationUnit();
var exporter = new Transpiler();
var csharpCode = exporter.Transpile(ast);

// Write to file or pass to C# compiler
File.WriteAllText("output.cs", csharpCode);
```

## Output Validation

Generated C# should:
- Compile without errors
- Compile without warnings (with nullable reference types enabled)
- Match N# semantics exactly
- Be readable by humans
