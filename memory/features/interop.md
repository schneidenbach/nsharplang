# C# Interop

N# is designed for seamless interop with C# and the .NET ecosystem.

## Using Statements

Import .NET namespaces:

```
using System
using System.Collections.Generic
using System.Linq
using System.Threading.Tasks
```

### Aliased Imports

```
using System.Collections.Generic as Collections

// Usage
let list := new Collections.List<int>()
```

Transpiles to:
```csharp
using Collections = System.Collections.Generic;
```

## External Type Resolution

N# resolves .NET types automatically via reflection.

### Example
```
using System

// Console is resolved from System namespace via reflection
Console.WriteLine("Hello")
```

### How It Works
1. Analyzer sees `using System`
2. Encounters unresolved `Console`
3. Tries `System.Console` via `Type.GetType()`
4. Loads type via reflection → `ReflectionTypeInfo`
5. Type checking proceeds normally

### Member Access
```
using System.Collections.Generic

let list := new List<int>()
list.Add(42)              // Method resolved via reflection
let count := list.Count    // Property resolved via reflection
```

## Calling C# Code

### Static Methods
```
using System

Console.WriteLine("Hello")
Math.Max(10, 20)
```

### Instance Methods
```
let text := "hello"
let upper := text.ToUpper()
```

### Properties
```
let text := "hello"
let length := text.Length
```

### Constructors
```
let list := new List<int>()
let dict := new Dictionary<string, int>()
```

## Using C# Libraries

### NuGet Packages
1. Create `project.yml`:
```yaml
targetFramework: net10.0
dependencies:
  - Newtonsoft.Json
  - Dapper
```

2. Use in N#:
```
using Newtonsoft.Json

let json := JsonConvert.SerializeObject(obj)
```

### Project References
Reference C# projects from N# projects (future feature).

## N# Consumed by C#

N# compiles to C#, so the generated code is fully consumable by C# projects.

### Example

**N# code (example.nl):**
```
class Calculator {
    func Add(a: int, b: int): int => a + b
}
```

**Generated C# (example.cs):**
```csharp
public class Calculator
{
    public int Add(int a, int b) => a + b;
}
```

**C# consumer:**
```csharp
var calc = new Calculator();
var result = calc.Add(5, 3);
```

## Attributes

Use C# attributes:

```
[Serializable]
class Person {
    Name: string
    Age: int
}

[Obsolete("Use NewMethod instead")]
func OldMethod() {
    // ...
}
```

### Qualified Attributes
```
[System.Serializable]
[System.Runtime.CompilerServices.InlineArray(10)]
[System.Diagnostics.CodeAnalysis.SuppressMessage("Style", "IDE0060")]
```

## Interfaces

Implement C# interfaces:

```
using System

class MyComparer : IComparer<int> {
    func Compare(x: int, y: int): int => x - y
}
```

## Generics

Use C# generic types:

```
using System.Collections.Generic

let list := new List<string>()
let dict := new Dictionary<string, int>()

func Identity<T>(x: T): T => x
```

## Extension Methods

### Calling C# Extension Methods
```
using System.Linq

let numbers := [1, 2, 3, 4, 5]
let evens := numbers.Where(x => x % 2 == 0)
let sum := numbers.Sum()
```

### Defining Extension Methods
```
static class StringExtensions {
    func IsEmpty(this s: string): bool => s.Length == 0
}

// Usage
let empty := "".IsEmpty()  // true
```

## Delegates and Events

### Delegates
```
using System

let handler: Action<string> = x => print x
handler("Hello")

let func: Func<int, int> = x => x * 2
let result := func(10)
```

### Events (Future Feature)
Currently not supported. Use C# interop for now.

## Ref and Out Parameters

Work with C# ref/out methods:

```
using System

// Out parameters
result, success := int.TryParse("42")
if success {
    print $"Parsed: {result}"
}

// Out parameters (inline declaration)
if int.TryParse("42", out var value) {
    print $"Value: {value}"
}

// Ref parameters
func Swap(ref a: int, ref b: int) {
    temp := a
    a = b
    b = temp
}
```

## Async Interop

Call C# async methods:

```
using System.Net.Http

async func FetchData(url: string): Task<string> {
    client := new HttpClient()
    return await client.GetStringAsync(url)
}
```

## Value Types vs Reference Types

### C# Structs
```
struct Point {
    X: double
    Y: double
}
// Allocated on stack, passed by value
```

### C# Classes
```
class Person {
    Name: string
}
// Allocated on heap, passed by reference
```

### Record Structs
```
record struct Point(x: double, y: double)
// Value type with record semantics
```

## Nullable Reference Types

N# supports C# nullable reference types:

```
let name: string? = null    // Nullable
let name: string = "Bob"    // Non-nullable
```

Analyzer checks nullability (basic checks only).

## Platform Invoke (P/Invoke)

Call native code (C/C++ DLLs):

```
using System.Runtime.InteropServices

[DllImport("user32.dll")]
func extern MessageBox(hWnd: IntPtr, text: string, caption: string, type: uint): int

// Usage
MessageBox(IntPtr.Zero, "Hello", "Title", 0)
```

## Type Compatibility

N# types map to C# types:

| N# Type | C# Type |
|---------|---------|
| `int` | `int` |
| `long` | `long` |
| `float` | `float` |
| `double` | `double` |
| `bool` | `bool` |
| `string` | `string` |
| `void` | `void` |
| `T[]` | `T[]` |
| `T?` | `T?` |
| Union | Abstract base class |
| Duck interface | Internal interface |
| String enum | Static class with const fields |

## Best Practices

1. **Use qualified attribute names** for clarity
2. **Import only needed namespaces** for faster compilation
3. **Use C# collection types** (List, Dictionary) for interop
4. **Follow .NET naming conventions** (PascalCase for public members)
5. **Use async/await** for I/O-bound operations
6. **Leverage LINQ** for collection operations
