# Type System

## Overview

N# has a rich type system with type inference, external type resolution, and structural typing.

## Type Inference

### Variable Declarations
Use `:=` for type inference:

```
let x := 42                  // Inferred as int
let name := "Alice"          // Inferred as string
let items := [1, 2, 3]       // Inferred as int[]
```

### Array Type Inference
Array literals infer element type:

```
let numbers := [1, 2, 3]     // int[]
let names := ["a", "b"]      // string[]
```

### Limitations
- **Property type inference**: NOT supported (C# limitation - properties need explicit types)
- **Lambda inference**: Lambdas and method-group identifiers receive contextual parameter/return types from selected delegate parameters, including CLR delegates such as ASP.NET Core `RequestDelegate`. Lambdas still infer `Unknown` when no contextual type exists.
- **Generic inference**: Limited (type parameters not fully inferred)

## Nullability Flow

Nullable types use `T?`. The analyzer tracks flow-sensitive null states for local variables and stable member paths (`x`, `request.Body`, `person.Name`) without rewriting the declared type. The states are:

- `unknown`
- `null`
- `maybeNull`
- `notNull`
- `oblivious` for external CLR surfaces whose nullable metadata has not been imported yet

Maybe-null member access, index access, or delegate calls report compiler error `NL905` with suggestions for `?.`, `?[`, `??`, guard clauses, or an explicit assertion. Direct use of `T?` as `T` is rejected unless flow has proven the value is `notNull`.

Flow narrowing is supported through direct null guards, guard clauses that return or throw, `&&`, `||`, `is` patterns, loops, nested scopes, and stable member-path checks. Assigning to a variable or member path invalidates prior facts for that path and its children.

`nlc query type` and `nlc query inspect` include a `nullability` field on type results so editor and automation surfaces can agree with compiler diagnostics.

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

#### Value-Struct Union Representation (Performance)

Small, closed, payload-free unions (every case is a bare tag, e.g. an enum-like
discriminated union) are emitted as an allocation-free `readonly struct` with an
integer discriminator tag instead of the abstract-class + nested-case-class
hierarchy. For these unions:

- The union type is a value type (`IsValueType == true`) — no object header, no
  per-case heap allocation.
- Construction (`new U.Case`) calls a static factory on the struct; the hot path
  contains no per-case `newobj`.
- `match` / pattern tests compare the integer tag, not a reference-type `isinst`.
- C# interop is preserved: the struct exposes a public `int Tag` property, the
  nested `U.Case` marker types still exist, and each marker carries a public
  `const int Tag` with the case's tag value.

Eligibility is decided by `NSharpLang.Compiler.Performance.UnionValueLayout`
(non-generic, closed, ≤ 16 cases, value-friendly). Unions that carry payloads
(e.g. `Result` above) remain on the reference class-hierarchy representation today;
extending the value-struct layout to inline case payloads is planned follow-up
work. Anything not eligible keeps the class hierarchy, so existing semantics and
interop never regress.

## Anonymous Union Types

Anonymous unions use `A | B` syntax when a value may be one of two concrete types
without introducing a named `union` declaration:

```
func Hi(greeting: PrebakedGreeting | string) {
    // ...
}

func Choose(flag: bool): int | string {
    if flag {
        return 42
    }

    return "fallback"
}
```

Anonymous unions are type references, so they are valid anywhere a type reference is
valid: parameters, returns, locals, fields, properties, aliases, casts, `is` checks,
nullable types, arrays, and generic arguments.

### Semantic Rules

- `T` is assignable to `A | B` when `T` is assignable to at least one arm.
- `A | B` is assignable to `T` when every arm is assignable to `T`.
- `A | B` is assignable to `C | D` when every source arm is assignable to at least one target arm.
- Nested anonymous unions are flattened before validation.
- Duplicate arms are rejected.
- Subsumed arms such as `object | string` are reported as warnings because the narrower arm is already covered by the wider arm.
- V1 supports two-arm anonymous unions. Larger anonymous unions report a diagnostic recommending a named `union`.

Named `union` declarations are unchanged. Use a named `union` when cases carry names,
case-specific fields, or more than two alternatives.

### Runtime and ABI

The public CLR ABI for `A | B` is `NSharpLang.Runtime.Union<A, B>`.
The runtime package is referenced by the N# SDK automatically, so user projects keep
the minimal `.csproj` form:

```xml
<Project Sdk="NSharpLang.Sdk" />
```

`NSharpLang.Runtime.Union<T0, T1>` is a readonly struct with:

- implicit conversions from both arms
- `Index`
- `Value`
- `Is<T>()`
- `TryGet<T>(out T value)`
- `As<T>()`
- `Match(...)`
- `Switch(...)`
- .NET equality and `ToString()` behavior

Public N# methods with anonymous-union parameters also emit C# overload shims so C#
callers can pass either arm directly:

```n#
public static func Describe(value: int | string): string {
    return match value {
        int number => number.ToString(),
        string text => text
    }
}
```

The CLR surface includes the canonical `Union<int, string>` method plus overloads
accepting `int` and `string`. Return types, fields, properties, and generic arguments
expose `Union<T0, T1>` directly.

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

C# interop distinguishes annotated nullable types from oblivious metadata. When a
referenced C# API has no nullable metadata, query and hover display the imported type as
`T!` to make the unknown legacy nullability explicit.

`must expr` explicitly unwraps a nullable value:

```
func RequireAge(age: int?): int {
    return must age
}
```

The expression type is the non-null inner type (`T` for `T?`). At runtime a null value throws `InvalidOperationException("must unwrap failed: value was null")`. This is an explicit operation, not a C#-style null-forgiving assertion, and the analyzer warns when `must` is redundant because the value is already known to be non-null.

Nullable values also expose the familiar presence members:

```
if age.HasValue {
    years := age.Value
}
```

Use `.HasValue` for guards. Direct unguarded `.Value` access warns because it can throw; prefer `must age` when failing is intended, or a nullable `match` when both cases matter.

```
label := match name {
    null => "missing",
    value => value.ToUpper()
}
```

In a nullable match, `null` covers the absent case and an identifier arm such as `value` binds the present value as non-null `T`. The analyzer requires nullable matches to cover both absent and present values unless an unguarded wildcard covers the remainder.

Custom messages on `must` failures are intentionally not part of the current syntax. Use an explicit guard and `throw` when the failure message is domain-specific.

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
