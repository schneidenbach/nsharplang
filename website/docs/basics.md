---
sidebar_label: Basics
title: Language Basics
---

# N# Language Basics

Welcome to N#! This guide covers the fundamental syntax and features of the N# programming language.

## What is N#?

N# (pronounced "N Sharp") is a pragmatic, simple language for the .NET CLR. It shares Go's ethos of simplicity and clean syntax, but it is **not** "Go for .NET": N# pairs that small syntax with a much richer type system (discriminated unions, exhaustive pattern matching, structural typing) and an opt-in high-performance "systems" lane.

**Key Features:**
- Clean, minimal syntax (no semicolons!)
- First-class .NET interop
- Type inference with `:=`
- String enums for better APIs
- Full access to .NET libraries and NuGet packages

## Variables

N# supports both type inference and explicit type declarations.

### Type Inference with `:=`

The `:=` operator declares a variable and infers its type:

```n#
x := 5              // Inferred as int
name := "Alice"     // Inferred as string
isActive := true    // Inferred as bool
items := [1, 2, 3]  // Inferred as int[]
```

### Explicit Type Declarations

Use `: Type =` for explicit types:

```n#
y: int = 10
greeting: string = "Hello"
count: long = 1000000
price: decimal = 19.99
```

### let Keyword

Use `let` for immutable bindings:

```n#
let numbers: int[] = [1, 2, 3, 4, 5]
let pi: double = 3.14159
```

## Functions

Functions are declared with the `func` keyword.

### Basic Functions

```n#
func add(a: int, b: int): int {
    return a + b
}

func greet(name: string) {
    Console.WriteLine($"Hello, {name}!")
}
```

### Function Calls

```n#
result := add(5, 10)
greet("World")
```

### Async Functions

Use the `async` keyword for asynchronous functions:

```n#
async func fetchData(): string {
    result := await httpClient.GetStringAsync("https://api.example.com/data")
    return result
}
```

### Lambda Expressions

N# supports lambda expressions for inline functions:

```n#
doubled := numbers.Select(x => x * 2).ToList()
filtered := items.Where(item => item > 5)
```

## Control Flow

### If Statements

```n#
if x > 5 {
    Console.WriteLine("x is greater than 5")
} else if x == 5 {
    Console.WriteLine("x equals 5")
} else {
    Console.WriteLine("x is less than 5")
}
```

### While Loops

```n#
count := 0
while count < 10 {
    Console.WriteLine(count)
    count += 1
}
```

### For Loops

```n#
// For-each loop
for item in items {
    Console.WriteLine(item)
}

// Counted loop
for i := 0; i < numbers.Length; i++ {
    Console.WriteLine(numbers[i])
}
```

`foreach` is accepted as a synonym for the `for x in e` form.

#### What `for x in e` can iterate

`for x in e` follows the same rules as C#'s `foreach`, and they are structural: N# looks at what the
collection's type *has*, never at what it is called. In order:

1. An **array** — an index loop over its length, with `x` typed as the element type.
2. A **`string`** — an index loop over its characters, with `x` typed as `char`. No enumerator is
   allocated.
3. The **enumerator pattern** — an accessible parameterless `GetEnumerator()` whose result has a
   readable `Current` and a parameterless `bool MoveNext()`. `x` is typed as `Current`'s type.
4. **`IEnumerable<T>`**, and then the non-generic **`IEnumerable`** (where `x` is `object`).

The pattern is why `List<T>`, `Dictionary<K, V>` (which iterates `KeyValuePair<K, V>`),
`Span<T>`, `Stack<T>`, `Dictionary<K, V>.Keys`, `JsonElement.EnumerateArray()` and a type you wrote
yourself all iterate without implementing anything:

```n#
class Countdown {
    Start: int

    func GetEnumerator(): CountdownEnumerator {
        return new CountdownEnumerator(Start)
    }
}

for value in new Countdown(3) {   // 3, 2, 1 — Countdown implements no interface
    print value
}
```

When the enumerator is a **struct** it stays a struct: the loop keeps it in a local of its own type
and steps it in place, so iterating a `List<int>` allocates nothing. When the enumerator is
**disposable**, the loop body runs inside a `try`/`finally` and the enumerator is disposed on every
way out — falling off the end, `break`, `return`, or an exception.

A value that has none of the four shapes is an error at the collection:

```text
foreach collection must be enumerable, but this collection is 'int'

Suggestion: A foreach collection needs an accessible parameterless GetEnumerator() whose result
has a readable Current and a bool MoveNext(), or it must be an array, a string, an IEnumerable<T>
or an IEnumerable.
```

#### Writing the loop variable's type

The loop variable may carry a type, `for x: T in e`, and each element is then converted to `T` once
per iteration:

```n#
for m: Match in Regex.Matches(text, "a") {   // MatchCollection's elements are `object`
    total += m.Length
}
```

This is what makes a sequence typed by an interface *wider* than its contents usable at the type its
elements actually have. `MatchCollection` and `ArrayList` are plain `IEnumerable`s, so without the
annotation `m` would be an `object` and `.Length` could not be spelled.

The conversion is the one a **cast** performs, not the one an assignment performs — which is exactly
why the downcast above is allowed. All of these are legal:

```n#
for m: Match in Regex.Matches(text, "a") { }   // a downcast out of `object`
for v: int in boxedValues { }                  // an unboxing, from List<object>
for n: long in numbers { }                     // a numeric widening, from int[]
for value: object in numbers { }               // a boxing widening
```

Because it is a cast, the compiler checks only that the conversion *could* apply. An element whose
runtime type does not satisfy it throws `InvalidCastException` at the loop, exactly as the cast
written by hand would. A pair of types that convert in **neither** direction is refused outright:

```text
A 'int' cannot be read as a 'string'

Hint: An annotated loop variable converts each element the way a cast does — a downcast, an
unboxing, or a numeric conversion. There is no conversion between `int` and `string` in either
direction, so no element could ever take that type.
```

See [`NL330`](./errors/NL330.md). The annotated type is what the variable *is* for the rest of the
loop — hover, completion and the body all read it — so drop the annotation whenever the inferred
element type is already what you want.

## Collections

### Arrays

```n#
numbers := [1, 2, 3, 4, 5]
names: string[] = ["Alice", "Bob", "Charlie"]
let empty: int[] = []
```

### Object Initialization

```n#
person := new Person {
    Name: "Alice",
    Age: 30,
    Email: "alice@example.com"
}
```

### Anonymous Objects

```n#
data := new {
    name: "Alice",
    age: 30,
    active: true
}
```

## Types

### Classes

```n#
class Person {
    Name: string
    Age: int
    Email: string

    // Constructor
    constructor(name: string, age: int) {
        Name = name
        Age = age
        Email = ""
    }

    // Method
    func greet() {
        Console.WriteLine($"Hello, I'm {Name}")
    }
}
```

### Creating Instances

```n#
person := new Person("Alice", 30)
person.greet()

// With object initializer
person2 := new Person("Bob", 25) {
    Email: "bob@example.com"
}
```

### Enums (String Enums)

N# supports string enums for better API ergonomics:

```n#
enum Status {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}

enum Department {
    Engineering = "engineering",
    Sales = "sales",
    Marketing = "marketing",
    HR = "hr"
}
```

### Using Enums

```n#
currentStatus: string = Status.Active
dept: string = Department.Engineering
```

## Pattern Matching

N# includes powerful pattern matching with `match`:

```n#
result := match value {
    null => "Value is null",
    0 => "Value is zero",
    > 0 => "Value is positive",
    < 0 => "Value is negative",
    _ => "Unknown"
}
```

### Pattern Matching in Functions

```n#
async func GetById(id: Guid): IActionResult {
    employee := await db.Employees.FindAsync(id)

    return match employee {
        null => NotFound(),
        _ => Ok(employee)
    }
}
```

## String Interpolation

Use `$""` for string interpolation:

```n#
name := "Alice"
age := 30
message := $"Hello, {name}! You are {age} years old."
Console.WriteLine(message)
```

Backslash escapes (`\n`, `\t`, `\e`, `\x1b`, `\u0041`, ...) are listed in the
[language tour](./language-tour.md#escape-sequences). A backslash that starts no escape is an error
([NL105](./errors/NL105.md)), so double it or use a raw `"""..."""` string.

## Imports and Packages

### Import Statements

Import .NET namespaces at the top of your file:

```n#
import System
import System.Linq
import System.Collections.Generic
import Microsoft.AspNetCore.Mvc
```

### Package Declaration

Declare your package namespace:

```n#
package MyApp.Services

import System

func DoSomething() {
    Console.WriteLine("Doing something!")
}
```

## Comments

```n#
// Single-line comment

/*
 * Multi-line comment
 * Can span multiple lines
 */
```

## Nullability

N# embraces .NET's nullable types pragmatically:

```n#
// Nullable types use ?
name: string? = null
count: int? = null
maybeNames: string?[] = [null, "Alice"]
maybeArray: string[]? = null

// Non-nullable types
required: string = "must have value"
number: int = 42
```

## Attributes

N# supports .NET attributes on declarations and parameters:

```n#
[Required]
[MaxLength(100)]
FirstName: string

[HttpGet]
async func GetAll([FromRoute] id: int): IActionResult {
    // ...
}

[HttpPost]
func Create([FromBody] [Required] user: CreateUserRequest): IActionResult {
    // ...
}
```

Attribute names resolve in the declaring file's scope, with or without the `Attribute` suffix —
`[Mark]` and `[MarkAttribute]` name the same type. Attributes are emitted on classes, structs,
records, interfaces, **enums**, **enum members**, functions, methods, constructors, properties,
**fields**, and parameters. A property's attributes go on the **property** itself, which is where
`PropertyInfo.GetCustomAttributes` — and so every model-binding, serialization and validation
framework — looks for them.

A field carries its own attributes, whatever shape the field has — instance, `static`, `const`, and a
field of a `struct` alike:

```n#
class Order {
    [Required]
    Customer: string

    [Obsolete("use Total")]
    static Legacy: int = 0

    [Mark("limit")]
    const Max: int = 100
}
```

### An attribute on an enum, and on an enum member

An enum's members become **literal fields** of the emitted type, so a member carries attributes the
way a field does — and the enum declaration carries its own on the type:

```n#
import System

[Flags]
[Mark("what a request may do")]
enum Permission {
    [Mark("read only")]
    Read = 1,

    [Mark("write only")]
    [Obsolete("use ReadWrite")]
    Write = 2,

    ReadWrite = 3
}
```

A member's attributes are read back from the field:

```n#
field := must typeof(Permission).GetField("Write")
data := field.GetCustomAttributesData()
```

A member is a field, so its attributes answer to `AttributeTargets.Field` — an attribute whose
`[AttributeUsage]` excludes fields is reported by [`NL933`](./errors/NL933.md) there, exactly as it
is on a `name: int` field. `AttributeTargets.Enum` belongs to the declaration above them.

A **string-backed** enum (`enum Kind: string`) is not a CLR enum — it is a class of literal string
fields — and its members carry attributes on the same rows.

Parameter attributes are emitted as real CLR parameter metadata, so ASP.NET model-binding attributes
such as `[FromBody]` and `[FromRoute]`, plus xUnit-style parameter attributes from referenced
packages, are visible to the framework at runtime. A **constructor's** parameters carry them exactly
the way a function's do.

### An attribute on a positional constructor parameter

A **primary constructor's** parameter is one declaration that becomes two things: the constructor's
parameter, and the field that parameter stores into.

```n#
record Options([JsonIgnore] Summary: bool = false, [FromRoute] Id: int = 0) {
}
```

C# chooses between the two with a target prefix — `[property: JsonIgnore]`. N# has no target prefix
at any position, so the **attribute's own `[AttributeUsage]`** chooses:

| The attribute allows | It is written on |
|---|---|
| parameters | the **parameter** — what the source literally wrote |
| fields but not parameters | the **field** that parameter declares |
| neither | nothing; [`NL933`](./errors/NL933.md) names both rows |

So `[JsonIgnore]` — declared for properties and fields — reaches the member a serializer reads, and
`[FromRoute]` — declared for parameters — stays on the parameter a model binder reads, without either
one being spelled differently. The rule is the same for a `record`, a `record struct`, and a `class`
or `struct` with a primary constructor.

An **ordinary** parameter is not a member, so nothing changes there: an attribute declared only for
fields is still refused on a `func`'s parameter, and a constructor parameter never routes to a field
that happens to share its name.

### Attribute arguments

An attribute argument must be a **compile-time constant**. Every shape the CLR can store in a
custom-attribute blob is written:

```n#
[Mark("text", 42)]                                  // strings and numbers
[Mark(true, 'x', 1.5f, 2.25)]                       // bool, char, float, double
[Mark(Level.High)]                                  // an enum member
[Mark(AttributeTargets.Method | AttributeTargets.Class)]   // a `|` combination of them
[Mark(typeof(Order))]                               // a type
[Mark(["a", "b"])]                                  // an array of constants
[Mark(null)]                                        // a null reference
[Mark("text", Count = 42, Note = "named")]          // named arguments
[Mark("text", Count: 42, Note: "named")]            // the same, in N#'s own spelling
```

A named argument binds to a **public settable property** or a **public mutable field** of the
attribute, declared by it or inherited. Named arguments come after the positional ones. Either
separator writes one: `Name = value` is the spelling C# uses, and `Name: value` is the spelling N#
uses for a named argument everywhere else — a call, an object initializer — so both are accepted and
emit the same metadata row.

An integer constant fills any numeric parameter whose range contains it, so a `byte` parameter takes
`[Mark(5)]` and refuses `[Mark(300)]`. A `long` or `ulong` constant that does not fit in an `int`
carries its suffix (`3L`, `18446744073709551615UL`), and a `float` argument carries `f`. An **array**
argument converts the same way, one element at a time: `[Bytes([1, 2])]` fills a `byte[]` parameter
because each element is a constant a `byte` holds, and `[Bytes([1, 300])]` is refused.

An argument the constructor gives a **default** may be left off, and the default is what the metadata
carries — a custom-attribute blob has no notion of an omitted argument, so N# writes the declared
value exactly as the C# compiler does:

```n#
class MarkAttribute: Attribute {
    Level: int
    constructor(level: int = 1) {
        Level = level
    }
}

[Mark]            // the emitted row carries Level = 1
[Mark(3)]         // the emitted row carries Level = 3
```

This holds for an attribute from a referenced assembly too: its parameter defaults are read from its
own metadata.

Anything that is not a constant — a call, a variable, a `new` expression — is refused by
[`NL310`](./errors/NL310.md) rather than silently dropped.

### Declaring your own attribute

An attribute is an ordinary class that derives from `System.Attribute`, and it may be applied
anywhere in the same program that declares it:

```n#
import System

[AttributeUsage(AttributeTargets.Method, AllowMultiple = true)]
class RetryAttribute: Attribute {
    Attempts: int
    Reason: string

    constructor(attempts: int) {
        Attempts = attempts
        Reason = ""
    }
}

class Client {
    [Retry(3)]
    [Retry(5, Reason = "flaky endpoint")]
    func Fetch() {
    }
}
```

The constructor is chosen by ordinary overload resolution over the constructors the class declares;
named arguments bind to its own or its base's settable members. An attribute may derive from another
attribute, in this program or in a referenced assembly, and its constructor may chain to the base's
with arguments (`constructor(text: string): base(text) {}`) in either world.

`[AttributeUsage(...)]` on the declaration is honored, and it is inherited by derived attributes:

- applying the attribute to a declaration its targets exclude reports
  [`NL933`](./errors/NL933.md);
- applying it twice without `AllowMultiple = true` reports [`NL934`](./errors/NL934.md).

Because N# has no attribute position inside accessor braces, a **property** offers both the
`Property` and the `Method` target: an attribute declared for either may be written on a property,
and it reaches the property's accessors.

### Positions N# has no attribute for

N# has no attribute **target** prefix — `[assembly: ...]`, `[return: ...]`, `[field: ...]`. Writing
one reports [`NL935`](./errors/NL935.md), which names the position and stops there: the rest of the
declaration still parses, so one refused attribute does not cascade into a page of syntax errors.
Generic attributes (`class Mark<T>: Attribute`) are not supported either.

### `[MethodImpl]` — the attribute that is not stored as an attribute

`System.Runtime.CompilerServices.MethodImplAttribute` is a **pseudo-custom attribute**. The CLR does
not keep a custom-attribute row for it. What it says goes into the implementation-flags column of the
method definition row — the column the JIT reads when it decides whether a call may be inlined, and
the one `MethodBase.GetMethodImplementationFlags()` reads back. N# writes it there, exactly as the C#
compiler does, so it never appears in `GetCustomAttributes()` or `GetCustomAttributesData()`.

```n#
import System.Runtime.CompilerServices

readonly struct Result {
    state: byte

    [MethodImpl(MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization)]
    constructor(state: byte) {
        this.state = state
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization)]
    IsOk: bool => state == 1

    [MethodImpl(MethodImplOptions.NoInlining)]
    func Describe(): string {
        return IsOk ? "ok" : "err"
    }
}
```

It may be written on a **method**, a **free function**, an **operator**, a **generic method**, a
**constructor**, a **property** and an **indexer**. N# has no attribute position inside accessor
braces, so a property's or indexer's attributes are its **accessors'** attributes: the declaration
above marks `get_IsOk`, and a property with both accessors marks both. That is N#'s spelling of what
C# writes as a per-accessor `[MethodImpl]`.

The option may be written as a single member, as a `|` combination, or fully qualified as
`System.Runtime.CompilerServices.MethodImplOptions.NoInlining`. There is no way to name a constant of
enum type at type scope in N# — `const` is a local-variable keyword, not a field modifier — so where
C# would declare `private const MethodImplOptions HotPathImpl = ...` and reuse it, N# writes the
combination at each member.

Three mistakes are refused rather than dropped: the attribute on a declaration that has no
implementation flags ([`NL930`](./errors/NL930.md)), a value with a bit no `MethodImplOptions` member
defines ([`NL931`](./errors/NL931.md)), and a combination the CLR's type loader would reject —
`Synchronized` on a value type's member, `InternalCall` or `Unmanaged` on a member with a body
([`NL932`](./errors/NL932.md)).

## Example: Complete Program

Here's a complete N# program that demonstrates many of these features:

```n#
import System
import System.Linq

package HelloWorld

class Person {
    FirstName: string
    LastName: string
    Age: int

    constructor(firstName: string, lastName: string, age: int) {
        FirstName = firstName
        LastName = lastName
        Age = age
    }

    func getFullName(): string {
        return $"{FirstName} {LastName}"
    }

    func isAdult(): bool {
        return Age >= 18
    }
}

func main() {
    // Create some people
    people := [
        new Person("Alice", "Smith", 30),
        new Person("Bob", "Jones", 17),
        new Person("Charlie", "Brown", 25)
    ]

    Console.WriteLine("All people:")
    for person in people {
        fullName := person.getFullName()
        status := if person.isAdult() { "adult" } else { "minor" }
        Console.WriteLine($"  {fullName} - {person.Age} years old ({status})")
    }

    // Filter adults using LINQ
    adults := people.Where(p => p.isAdult()).ToList()
    Console.WriteLine($"\nFound {adults.Count} adults")
}
```

## Next Steps

- **[Functions Guide](functions.md)** - Deep dive into functions, lambdas, and async
- **[Types Guide](types.md)** - Advanced type system features
- **[Pattern Matching](pattern-matching.md)** - Master pattern matching

## Resources

- [Project README](https://github.com/schneidenbach/nsharplang/blob/main/README.md)
- [Examples](/examples)
