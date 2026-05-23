# Type System

## Overview

N# has a rich type system with type inference, external type resolution, and structural typing.

## Type Inference

### Variable Declarations
Use `var` or `:=` for type inference:

```
let x: var = 42              // Inferred as int
let name := "Alice"          // Inferred as string
let items := [1, 2, 3]       // Inferred as int[]
```

### Array Type Inference
Array literals infer element type:

```
let numbers := [1, 2, 3]     // int[]
let names := ["a", "b"]      // string[]
```

**Important:** With `var`, transpiler emits explicit array type to avoid C# 12 collection expression ambiguity:
```
// N#: let items: var = [1, 2, 3]
// C#: int[] items = [1, 2, 3];  (NOT: var items = [1, 2, 3];)
```

### Limitations
- **Property type inference**: NOT supported (C# limitation - properties need explicit types)
- **Lambda inference**: Lambdas and method-group identifiers receive contextual parameter/return types from selected delegate parameters, including CLR delegates such as ASP.NET Core `RequestDelegate`. Lambdas still infer `Unknown` when no contextual type exists.
- **Generic inference**: Limited (type parameters not fully inferred)

## Duck Interfaces (Structural Typing)

Duck interfaces use **structural typing** instead of nominal typing.

### Declaration
```
duck interface IReader {
    func Read(): string
}
```

### Usage
Any type with matching methods automatically implements the interface:

```
class FileReader {
    func Read(): string => "file contents"
}

class NetworkReader {
    func Read(): string => "network data"
}

// Both work as IReader without explicit declaration
func ProcessReader(reader: IReader) {
    print reader.Read()
}
```

### Type Erasure (Important!)

**Duck interfaces are completely type-erased during transpilation.**

They exist **only** for N# compile-time type checking:
- Analyzer validates structural compatibility
- Transpiler **omits** duck interface declarations entirely
- Generated C# code has **no trace** of duck interfaces
- Classes don't auto-implement duck interfaces in C#

**Why?**
- Duck interfaces are an N# language feature
- C# consumers don't need to know about them
- Cleaner generated C# code
- No leakage of internal implementation details

### Structural Matching Rules
At compile-time, type matches duck interface if it has:
- All required methods
- Matching names
- Matching return types
- Matching parameter counts and types

See `memory/components/analyzer.md` for implementation details.

## External Type Resolution

N# resolves .NET types via reflection.

### Using Statements
```
using System
using System.Collections.Generic
using System.Linq
```

### Type Resolution Process
1. Encounter unresolved identifier (e.g., `Console`)
2. Search all imported namespaces:
   - `System.Console`
   - `System.Collections.Generic.Console`
   - etc.
3. Use `Type.GetType()` to load via reflection
4. Wrap in `ReflectionTypeInfo`

### Member Resolution
For external types, use reflection to:
- Get properties: `Console.WriteLine`, `list.Count`
- Get methods: `string.ToUpper()`, `List<T>.Add()`
- Handle overloads: Group methods by name → `ReflectionMethodGroupInfo`

### Method Overload Resolution
Currently **basic**: matches by argument count only.

**Limitation:** Doesn't check argument types. Future improvement needed.

## User-Defined Types

### Classes
```
class Person {
    Name: string
    Age: int

    func Greet() {
        print $"Hi, I'm {Name}"
    }
}
```

### Structs
```
struct Point {
    X: double
    Y: double
}
```

### Records (Reference Type)
```
record Person(name: string, age: int)
```

### Record Structs (Value Type)
```
record struct Point(x: double, y: double)
```

### Interfaces
```
interface IShape {
    func Area(): double
}
```

### Discriminated Unions
```
union Result<T> {
    Success { value: T }
    Failure { error: string }
}
```

Transpiled to abstract base class with nested record cases.

### Enums (Int)
```
enum Status {
    Active = 1
    Inactive = 2
}
```

### Enums (String)
```
enum Color: string {
    Red = "red"
    Blue = "blue"
}
```

Transpiled to `readonly struct` wrapping a `string Value` property, with implicit string conversion, `IEquatable<T>`, equality operators, and a nested `JsonConverter` for System.Text.Json serialization. This allows string enums to be used as parameter types, return types, and record properties.

## Type Aliases

```
type UserId = int
type StringDict = Dictionary<string, string>
type Callback = Func<void>
type Handler = Func<string, void>
type Point = (x: double, y: double)
```

Transpiled to C# file-scoped `using` alias directives with fully qualified type names for well-known .NET types:
- `type UserId = int` → `using UserId = int;`
- `type StringDict = Dictionary<string, string>` → `using StringDict = System.Collections.Generic.Dictionary<string, string>;`
- `type Callback = Func<void>` → `using Callback = System.Action;`
- `type Handler = Func<string, void>` → `using Handler = System.Action<string>;`

Using aliases are emitted at the top of the generated C# file, after namespace imports but before namespace/class declarations.

## Newtypes (Branded Types)

Newtypes create **distinct wrapper types** that are NOT interchangeable with their underlying type. Unlike type aliases (which are transparent), newtypes enforce nominal type safety at compile time.

### Declaration
```
type UserId = newtype int
type Email = newtype string
type OrderId = newtype int
```

### Construction & Unwrapping
```
id := UserId(42)           // Explicit construction
let raw: int = id.Value    // Explicit unwrapping via .Value
```

### Type Safety
Newtypes are NOT assignable to/from their underlying type or other newtypes with the same underlying type:
```
id := UserId(42)
// let x: int = id          // ERROR: Cannot assign 'UserId' to 'int'
// let id2: UserId = 42     // ERROR: Cannot assign 'int' to 'UserId'
// let oid: OrderId = id    // ERROR: Cannot assign 'UserId' to 'OrderId'
```

### C# Emission
```
type UserId = newtype int
```
Transpiles to:
```csharp
public readonly record struct UserId(int Value);
```

This gives C# consumers:
- Constructor: `new UserId(42)`
- `.Value` property for unwrapping
- Value equality (`==`, `!=`, `Equals`, `GetHashCode`)
- `ToString()`, `IEquatable<UserId>`

### Design Decisions
- **No auto-forwarded arithmetic**: `UserId + 1` is not valid — use `.Value` for math
- **No implicit conversions**: Both construction and unwrapping are explicit
- **No serialization magic**: Use library-level converters (e.g., `JsonConverter<UserId>`)
- **Visibility**: PascalCase = public, camelCase = file-private (standard N# convention)

## Nullable Types

```
let name: string? = null     // Nullable reference
let age: int? = null          // Nullable value type
```

## Generic Types

```
class Box<T> {
    Value: T
}

func Identity<T>(x: T): T => x
```

**Limitation:** Generic type inference not fully implemented.

## Implicit Conversions

User-defined implicit conversions:

```
class Celsius {
    Value: double

    implicit operator Fahrenheit(c: Celsius) {
        return new Fahrenheit { Value: c.Value * 9 / 5 + 32 }
    }
}
```

Analyzer validates implicit conversions in `IsAssignable()`.

## Type Compatibility

Types are compatible (assignable) if:
1. Exact type match
2. Inheritance (derived → base)
3. Interface implementation
4. Duck interface structural match
5. User-defined implicit conversion
6. Nullable conversion (T → T?)
7. Array covariance (Derived[] → Base[])

See `memory/components/analyzer.md` → `IsAssignable()` for details.
