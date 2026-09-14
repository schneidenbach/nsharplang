---
sidebar_label: Types
title: Types
---

# Types in N#

This guide covers the type system in N#, including classes, structs, records, discriminated unions, duck interfaces, and enums.

## Table of Contents

- [Basic Types](#basic-types)
- [Numeric Operators](#numeric-operators)
- [Arrays](#arrays)
- [Classes](#classes)
- [Structs](#structs)
- [Records](#records)
- [Discriminated Unions](#discriminated-unions)
- [Duck Interfaces](#duck-interfaces)
- [Enums](#enums)
- [Interfaces](#interfaces)
- [Generics](#generics)
- [Using .NET Generic Types](#using-net-generic-types)
- [Nullable Types](#nullable-types)
- [Type Aliases](#type-aliases)
- [Newtypes (Branded Types)](#newtypes-branded-types)

## Basic Types

N# uses .NET's type system:

```n#
// Primitives
x: int = 42
y: long = 1000000
z: double = 3.14
w: decimal = 19.99
flag: bool = true
letter: char = 'A'

// String
name: string = "Alice"
message: string? = null  // Nullable string

// Arrays
numbers: int[] = [1, 2, 3, 4, 5]
names: string[] = ["Alice", "Bob", "Charlie"]
```

## Numeric Operators

### Binary numeric promotion

An arithmetic, bitwise or comparison operator runs in ONE type, and which one is decided by the two
operands rather than by what the result is assigned to. Everything narrower than `int` promotes to
`int`, so `byteValue + byteValue` is an `int`; the wider types promote to the wider of the pair.

Exactly two pairs have no common type at all: `decimal` with a floating-point type, and `ulong` with
a signed integral type. No single type holds every value of either pair, so there is nothing to
compute in:

```n#
func Refused(mask: ulong, flags: int): ulong {
    return mask & flags          // NL202 — cast the signed side: mask & (ulong)flags
}
```

### Integer constants adopt the type they are written against

A CONSTANT is not subject to that refusal. An integer constant whose value fits the other operand's
type converts to it, so the ordinary bit-manipulation idioms need no ceremony:

```n#
func Masked(value: ulong): ulong {
    return value & 0xFF          // the constant is a ulong here
}

func Compared(value: ulong): bool {
    return value > 5 && value != 0
}
```

The rule is the value's, not the position's: the constant may be written on either side, in any of
`&`, `|`, `^`, the arithmetic operators, the comparisons and the compound assignments, and in any
spelling (`255`, `0xFF`, `0b1111_1111`). A **suffixed** literal carries its own type and adopts
nothing — `mask & 1L` is still a `ulong` against a `long` — and a **negative** constant adopts only a
signed target.

A non-constant operand is refused, and that is the same rule read from the other side: the compiler
cannot know a variable's value, so the conversion has to be written.

The same rule applies at an **argument**, including an argument to a referenced assembly's method,
and it applies before the overload is chosen rather than after — a candidate whose parameter takes
the constant is a candidate:

```n#
import System.Collections.Concurrent
import System.Collections.Generic
import System.IO

func Track(roots: ConcurrentDictionary<string, byte>, root: string): bool {
    return roots.TryAdd(root, 0)      // TValue is `byte`; the constant converts
}

func Note(levels: Dictionary<string, byte>) {
    levels.Add("warning", 200)
}

func Pad(stream: Stream) {
    stream.WriteByte(0)
}
```

A constant does **not** decide a generic method's type arguments — `T` is bound by the standard rules
or not at all — and an overload that takes the constant's own type still wins on identity, so `f(0)`
prefers an `int` parameter to a `byte` one. Between a `byte` parameter and a `long` one, the more
specific `byte` wins, exactly as in C#.

### Shifts

`<<` and `>>` are the one binary pair whose operands are not symmetric. The **count** on the right is
always an `int`, whatever the expression is being written into, and the **result** is the promoted
type of the left operand alone:

```n#
func SetBit(words: ulong[], index: int) {
    words[index >> 6] = words[index >> 6] | (1UL << (index & 63))
}
```

`index & 63` here is an `int` because it is a shift count, not a `ulong` because the assignment
target is one. A `>>` over an unsigned left operand is the unsigned shift — the high bit zero-fills
— and over a signed one it keeps the sign.

NEITHER operand takes the surrounding target, so a suffixless literal on the left of a shift is an
`int` like any other: `value: ulong = 1 << 40` is an `int` shift, and writing it into a `ulong`
reports a type mismatch rather than silently truncating. Write the suffix — `1UL << 40` — when the
shift is meant to run in 64 bits.

## Arrays

An array is written `T[]`, indexed from zero, and sized by `.Length`. A literal `[a, b, c]` builds
one; `new T[](n)` builds an empty one of a given size.

```n#
names: string[] = ["Alice", "Bob"]
empty := new int[](3)
first := names[0]
```

### Array covariance

An array of a reference type IS an array of any type its elements convert to by a reference
conversion — `string[]` is an `object[]`, and `Dog[]` is an `Animal[]`. This holds in every position:
a return value, an argument, an assignment, a `yield` value and an element of another array.

```n#
func Count(values: object[]): int => values.Length

func Names(): object[] {
    names: string[] = ["Alice", "Bob"]
    return names            // string[] -> object[]
}
```

Two rules come with it, and both are the CLR's:

- **Only reference elements.** `int[]` is not an `object[]`. The conversion is a no-op — one array
  object viewed two ways — and a value-typed element would have to be boxed into a different
  representation, which would mean copying the array. Boxing, numeric widening and your own
  `implicit` conversion operators are likewise never carried across an array: `Celsius[]` is not a
  `Fahrenheit[]` however many conversions connect the two element types.
- **Stores through the wider view are checked at run time.** Because the two names refer to the same
  object, writing through the wider one can violate the narrower one. The CLR checks every such
  store and throws `ArrayTypeMismatchException`:

```n#
names: string[] = ["Alice"]
view: object[] = names
view[0] = "Bob"            // fine — still a string
view[0] = 42               // throws ArrayTypeMismatchException
```

Reads through the wider view never throw, and covariance composes: `string[][]` is an `object[][]`.

**Nullability is covariant the same way, and in one direction.** A reference nullable annotation is
not a CLR type — `string?` and `string` are one runtime type — so a `T[]` IS a `T?[]`, the view costs
nothing, and every element read out of it is honestly typed `T?`. This is what lets an `object[]`
reach a parameter declared `object?[]?`, such as `MethodInfo.Invoke`'s second one:

```n#
names: string[] = ["Alice"]
view: string?[] = names    // string[] -> string?[]
```

The reverse is refused: a `T?[]` may already hold a null, so reading it back as a `T[]` would promise
something the array does not have. Writing `null` through the widened view is the one hazard the rule
accepts — it is the same one the element-type covariance above accepts, and C# accepts it too (with a
warning).

### Target-typed array literals

When the surrounding code names an element type, each element of a literal converts to it — boxing a
value type, widening a reference, and accepting `null` — and the literal's type is the target's,
whatever the elements happen to be:

```n#
mixed: object[] = ["a", 1, ["b", "c"], null]
```

Targets include an annotated local or field, a return value, an argument (a `params` array
included), a `yield` value, and an element of an enclosing literal that is itself a literal. A target
that may itself be null is still a target, so `object?[]?` names `object?` as its element type the
same way `object[]` names `object`.

A literal written as an argument is measured against every candidate of an **overload set** before
one is chosen, element by element, and the candidate that takes it is the one whose element type fits
best:

```n#
class Sink {
    static func Accept(values: int[]): string => "ints"
    static func Accept(values: object[]): string => "objects"
}

Sink.Accept([1, 2, 3])     // "ints"   — an exact element type wins
Sink.Accept(["a", "b"])    // "objects" — `string` reaches `object` and reaches `int` not at all
method.Invoke(null, [args])  // object?[]? — the literal takes the parameter's element type
```

A referenced assembly's parameter is a target like any other, and its element type reaches the
literal's **elements**, so an integer constant adopts it there too:

```n#
import System
import System.Security.Cryptography
import System.Text

func Decoded(): string => Encoding.UTF8.GetString([72, 105], 0, 2)   // a byte[]

func Edges(): string => Convert.ToBase64String([0, 255])             // both ends of `byte`

func Block(sha: SHA256, output: byte[]): int {
    return sha.TransformBlock([0], 0, 1, output, 0)
}
```

Every element has to convert: `[0, 300]` is not a `byte[]`, because 300 is not a `byte`.

Where no target exists, the FIRST element decides the element type and every later one must fit it:

```n#
inferred := [1, 2, 3]      // int[]
bad := [1, "a"]            // NL202: elements must be the same type
```

## Classes

### Basic Class Declaration

```n#
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
}
```

### Primary Constructors

```n#
class Person(firstName: string, lastName: string, age: int) {
    FirstName: string = firstName
    LastName: string = lastName
    Age: int = age

    func getFullName(): string => $"{FirstName} {LastName}"
}
```

### Properties

```n#
class Product {
    // Auto-property
    Name: string

    // Auto-property with initializer
    Price: decimal = 0.0

    // Expression-bodied property
    DisplayName: string => $"{Name} (${Price})"

    // Full property with getter and setter
    stock: int
    Stock: int {
        get { return stock }
        set {
            if value < 0 {
                throw new ArgumentException("Stock cannot be negative")
            }
            stock = value
        }
    }
}
```

### Init-only Properties

Mark a property `init` to make it settable in the object initializer but immutable
afterward.

```n#
class Configuration {
    init AppName: string
    init Version: string
}

// Usage
config := new Configuration {
    AppName: "MyApp",
    Version: "1.0"
}

// config.AppName = "NewName"  // Error: init-only property
```

### Required Properties

```n#
class User {
    required Id: Guid
    required Name: string
    Email: string?  // Optional
}

// Must initialize required properties
user := new User {
    Id: Guid.NewGuid(),
    Name: "Alice"
}
```

### Members in any order

A type's members may be written in whatever order reads best — a field beside the method that uses
it, a property between two methods, an event after the code that raises it. Declaration order is
preserved where it is observable (a `[StructLayout(LayoutKind.Sequential)]` struct lays its fields
out in the order you wrote them), and means nothing where it is not:

```n#
class Counter {
    Seed: int = 3

    func Bump(): int {
        Steps = Steps + 1
        return Seed + Steps
    }

    Steps: int = 0                  // a field after the method that uses it
    Label: string => "counter"      // ...and a property after both
}
```

### Inheritance

```n#
class Animal {
    Name: string

    constructor(name: string) {
        Name = name
    }

    virtual func makeSound(): string {
        return "..."
    }
}

class Dog : Animal {
    constructor(name: string) : base(name) {
    }

    override func makeSound(): string {
        return "Woof!"
    }
}
```

### A base from a referenced assembly

The `:` clause may name a type the CLR already holds. It states a fact about your type: a `Names`
IS a `List<string>`, so every member `List<string>` declares is a member `Names` has, with the
base's type arguments already substituted.

```n#
class Names: List<string> {
    // The inherited members are in scope without a receiver, exactly as your own are.
    func Summary(): string {
        return Count.ToString() + " names"
    }
}

func use() {
    names := new Names()
    names.Add("alpha")           // Add(string), not Add(T)
    names[0] = "beta"            // the base's indexer
    print names.Count.ToString() // the base's property
    print names.Exists(name => name.Length == 4).ToString()
    lengths := names.ConvertAll<int>(name => name.Length)

    sequence: IEnumerable<string> = names   // the base's interfaces are yours too
    for name in sequence {
        print name
    }
}
```

Everything a member access can name is reached this way: properties, fields, methods (including
overloads, methods taking a lambda, and generic methods), indexers, events, and static members read
through the derived type. `base.Member` reaches the base's own implementation non-virtually;
`this.Member` and the bare name dispatch virtually. The chain is followed as written, so
`class Deeper: Names` reaches `List<string>`'s members through `Names` as well.

`: base(...)` chains to the external base's constructor, chosen by the arguments you wrote:

```n#
class TaggedError: Exception {
    Tag: string

    constructor(tag: string, message: string): base(message) {
        Tag = tag
    }

    override func ToString(): string {
        return Tag + ":" + Message      // an inherited member, named without a receiver
    }
}
```

A `protected` member of an external base is in scope too, which is what makes the extension points
of types like `Collection<T>` usable. Every spelling reaches it, and so does every kind of member —
a method, a property, or a field, at any result type:

```n#
class Bag: Collection<string> {
    func Replace(index: int, item: string) {
        this.SetItem(index, item)      // protected virtual method, through `this`
        SetItem(index, item)           // ...the same call with no receiver written
        base.ClearItems()              // ...and non-virtually, through `base`
    }

    func Held(): int {
        return this.Items.Count        // protected property, typed IList<string>
    }
}

class Writer: StringWriter {
    func TerminatorLength(): int {
        return CoreNewLine.Length      // protected FIELD, typed char[]
    }
}
```

The rule is C#'s (§7.5.4) — the receiver has to be your type or one derived from it, and `base.` is
always allowed inside the deriving type. `private` members of a referenced base are never in reach,
and neither are its `internal` and `private protected` ones **unless that assembly has made your
project a friend** — see [Reaching a reference's internals](#reaching-a-references-internals) below.

### Reaching a reference's internals

A referenced assembly can name yours in an `InternalsVisibleTo` attribute:

```csharp
// in the referenced project, for example MyLibrary.csproj
[assembly: InternalsVisibleTo("MyLibrary.Tests")]
```

When it does, a project whose `project.yml` `name:` is `MyLibrary.Tests` sees that assembly the way
its own code does: its `internal` types are types you can spell, and the `internal` members of its
public types are members you can reach. Nothing about the call changes — the compiler emits the same
instruction it emits for a public member, and the CLR re-checks the grant when it loads your
assembly.

```n#
namespace MyLibrary.Tests

import MyLibrary.Internals

func Reads(): int {
    state := new InternalCounter(7)   // an `internal` type of the granting reference
    return state.Reading()            // ...and an `internal` member of a public one
}
```

The grant is matched on your assembly's **whole simple name**, without regard to case. A strong-name
key after a comma (`"MyLibrary.Tests, PublicKey=0024..."`) is not part of the comparison. A name
that merely resembles the granted one — `MyLibrary.Tests.Unit`, `MyLibrary.Test` — is not a friend,
and an `internal` type of an assembly that granted nobody (or granted a different name) stays
[NL301](./errors/NL301.md) or [NL201](./errors/NL201.md) exactly as before.

N# does not yet EMIT an `InternalsVisibleTo` of its own: an N# library cannot currently make another
assembly its friend, so this rule is about consuming grants written by assemblies compiled elsewhere.

One gap remains on the refusing side. A **fully qualified** spelling of an internal type
(`My.Library.Internals.InternalCounter`, rather than the bare name under an `import`) is not
reported by the analyzer today — unresolved dotted names are deliberately lenient — so without a
grant it reaches emission instead of `NL301`. Write the bare name under an `import` to get the
diagnostic.

Those `protected virtual` members are extension points, so you may **override** them, and the same
three levels are the ones you may take the slot of:

```n#
class ObservedBag: Collection<string> {
    Replacements: int = 0

    override func SetItem(index: int, item: string) {
        Replacements = Replacements + 1
        base.SetItem(index, item)
    }
}
```

**An `override` takes the accessibility of the member it overrides** when you write no accessibility
word of your own. `SetItem` above is PascalCase, which would otherwise export it — but the slot
belongs to the type that opened it, and replacing a member is not a decision to publish it, so the
override is emitted `protected` like the base member. Write a word and it is honoured:
`protected override func SetItem(...)` says the same thing out loud, and `public override func
SetItem(...)` deliberately widens, which the CLR permits (only NARROWING an override is refused).

The base may also be a generic closed over a type **you** are declaring:

```n#
class Item {
    Title: string = ""
}

class Catalogue: Collection<Item> {
    func Size(): int {
        return this.Count
    }
}
```

### Abstract Classes

```n#
abstract class Shape {
    abstract func getArea(): double
    abstract func getPerimeter(): double

    func describe() {
        Console.WriteLine($"Area: {getArea()}, Perimeter: {getPerimeter()}")
    }
}

class Circle : Shape {
    Radius: double

    constructor(radius: double) {
        Radius = radius
    }

    override func getArea(): double {
        return Math.PI * Radius * Radius
    }

    override func getPerimeter(): double {
        return 2 * Math.PI * Radius
    }
}
```

### Static Members

```n#
class MathHelper {
    static Pi: double = 3.14159

    static func square(x: double): double {
        return x * x
    }
}

// Usage
result := MathHelper.square(5)
pi := MathHelper.Pi
```

### Field initializers

A field initializer is an ordinary expression — a literal, a call, a construction, an operator
chain, anything the language admits — and it is evaluated where its kind of field is initialized.

```n#
import System.Collections.Generic
import System.Runtime.CompilerServices

class Registry {
    // Static: evaluated once, in textual order, inside the type's initializer.
    static readonly HotPath: MethodImplOptions = MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization
    static readonly Limit: int = int.MaxValue
    static readonly Names: List<string> = new List<string>()
    static readonly Seed: int = Make(4)

    // Instance: evaluated at the start of every constructor.
    readonly Scale: int = 3 + 4
    readonly Label: string = "a" + "b"

    static func Make(value: int): int => value * 2
}
```

**Static field initializers** run once, in the order they are written, inside a synthesized type
initializer, before the first access to any of the type's static fields. An initializer may call the
type's own static methods and read a static field declared *earlier*; a static field declared *later*
still holds its default when an earlier initializer reads it, which is the same rule C# applies.
A `const` field is different: its value is metadata on the field itself, so it must be a compile-time
constant and it never runs as code. On a generic type, static storage belongs to the instantiation —
`Cache<int>` and `Cache<string>` each get their own fields and their own initializer run.

Every emitted class and struct carries the CLR `beforefieldinit` flag, exactly as a C# type with no
declared static constructor does: the runtime may run the type initializer at any point before the
first static-field access rather than exactly at it.

**Instance field initializers** run at the very start of *every* constructor that reaches the base
constructor — before the base constructor call, and before the constructor body. A constructor that
chains to another constructor of the same type (`: this(...)`) does not re-run them; the constructor
it delegates to already did. Because the object does not exist yet at that point, an initializer may
not name any part of the instance: `this`, `base`, and bare instance fields, methods and properties
of the declaring type are all [NL328](./errors/NL328.md). Assign such a field in a constructor
instead, or make what it needs `static`.

A `readonly` field with an initializer is `initonly` in metadata and assignable only from its
initializer or a constructor.

**A struct's instance field initializers need a constructor.** A `struct` value can be produced
without running one — `default(Point)`, an array element, an uninitialized field — so the
initializers run for the values built through a constructor and the CLR zero stands for the rest. A
struct that declares no constructor at all (primary or written) would therefore never run its
initializers, and that shape is [NL329](./errors/NL329.md).

```n#
struct Point {
    X: double = 1.0

    constructor(x: double) {
        X = x
    }
}
// new Point(3.0).X is 3.0; new Point() is not a thing; default(Point).X is 0.0
```

Static field initializers on a struct are unaffected and behave exactly as a class's do.

### Literal constant fields

Classes can expose CLR literal fields with the `const` member modifier:

```n#
class Limits {
    public const SchemaVersion: int = 2
    public const MaxItems: int = 65536
}
```

The supported constant-field form currently requires an `int` field initialized with a non-negative,
unsuffixed integer literal from `0` through `2147483647`. It emits a static literal CLR field with
the declared source visibility and a metadata constant value, and the field cannot be assigned
after declaration. Other field types, suffixed or negative literals, and computed initializers are
rejected until their constant metadata contract is supported.

## Structs

Structs are value types:

```n#
struct Point {
    X: double
    Y: double

    constructor(x: double, y: double) {
        X = x
        Y = y
    }

    func distanceFrom(other: Point): double {
        dx := X - other.X
        dy := Y - other.Y
        return Math.Sqrt(dx * dx + dy * dy)
    }
}

// Usage
p1 := new Point(0, 0)
p2 := new Point(3, 4)
distance := p1.distanceFrom(p2)  // 5.0
```

### A struct method may write its own fields

A struct's method receives `this` as a pointer to the RECEIVER'S OWN storage whenever the receiver
has storage — a local, a parameter, or a field of either — so a field it assigns is the caller's:

```n#
struct Counter {
    value: int

    func Bump(): bool {
        value = value + 1
        return value < 3
    }
}

counter := new Counter()
counter.Bump()
counter.Bump()
print counter.value       // 2 — the caller's own variable moved
```

A receiver with no storage of its own — the result of a call, a literal, a property read — is a
temporary, and mutating it changes only that temporary. That is the same rule C# applies, and it is
the reason to bind such a value to a name before calling a method that mutates it.

Value semantics still apply everywhere else: passing a struct copies it, so a method that bumps a
struct PARAMETER moves that frame's copy and not the caller's variable.

### Readonly Structs

```n#
readonly struct Vector3 {
    X: double
    Y: double
    Z: double

    constructor(x: double, y: double, z: double) {
        X = x
        Y = y
        Z = z
    }
}
```

## Records

Records are immutable reference types:

```n#
record Person {
    FirstName: string
    LastName: string
    Age: int
}

// Usage
person := new Person {
    FirstName: "Alice",
    LastName: "Smith",
    Age: 30
}

// With expressions (create modified copy)
older := person with { Age: 31 }
```

### Record Structs

```n#
record struct Point {
    X: double
    Y: double
}

// Value semantics with record features
p1 := new Point { X: 1, Y: 2 }
p2 := p1 with { X: 3 }
```

### Positional Records

```n#
record Person(string FirstName, string LastName, int Age)

// Usage
person := new Person("Alice", "Smith", 30)
Console.WriteLine(person.FirstName)  // "Alice"

// Deconstruction goes through a `Deconstruct` method. N# does not synthesize one for a record, so
// declare it when callers should be able to unpack the value:
//
//   func Deconstruct(out firstName: string, out lastName: string, out age: int) {
//       firstName = FirstName
//       lastName = LastName
//       age = Age
//   }
//
//   (first, last, age) := person
```

## Discriminated Unions

Unions are N#'s most powerful feature - they provide type-safe alternatives:

### Basic Union

```n#
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

// Usage
func divide(a: double, b: double): Result<double> {
    if b == 0 {
        return new Result.Failure<double> { error: "Division by zero" }
    }
    return new Result.Success<double> { value: a / b }
}
```

### Pattern Matching with Unions

```n#
result := divide(10, 2)

message := match result {
    Result.Success { value: v } => $"Result: {v}",
    Result.Failure { error: e } => $"Error: {e}"
}
```

### Union with Multiple Fields

```n#
union HttpResponse {
    Ok { body: string, statusCode: int }
    Error { message: string, code: int }
    Redirect { url: string, permanent: bool }
}

func handleResponse(response: HttpResponse) {
    match response {
        HttpResponse.Ok { body, statusCode } => {
            Console.WriteLine($"Success ({statusCode}): {body}")
        },
        HttpResponse.Error { message, code } => {
            Console.WriteLine($"Error {code}: {message}")
        },
        HttpResponse.Redirect { url, permanent } => {
            redirectType := if permanent { "permanent" } else { "temporary" }
            Console.WriteLine($"Redirect ({redirectType}): {url}")
        }
    }
}
```

### Option Type

```n#
union Option<T> {
    Some { value: T }
    None { }
}

func findUser(id: int): Option<User> {
    user := database.Find(id)
    if user == null {
        return new Option.None
    }
    return new Option.Some<User> { value: user }
}
```

### CLR Shape of Unions

N# unions emit CLR class hierarchies. Case payload members follow N#'s naming
conventions — PascalCase exports a public CLR field, camelCase stays
assembly-internal — so name payloads PascalCase for public CLR surfaces:

```n#
union Result<T> {
    Success { Value: T }
    Failure { Error: string }
}
```

The emitted shape is an abstract union base with sealed case types and public fields for exported payload members.

## Duck Interfaces

Duck interfaces provide structural typing - types match based on their shape:

```n#
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string {
        return "file contents"
    }
}

class HttpReader {
    func Read(): string {
        return "http contents"
    }
}

func processReader(reader: IReader) {
    content := reader.Read()
    Console.WriteLine(content)
}

// Both types work - they have the right shape!
processReader(new FileReader())
processReader(new HttpReader())

readers := new System.Collections.Generic.List<IReader>()
readers.Add(new FileReader())
readers.Add(new HttpReader())
```

Satisfaction is checked when a value flows to a duck-interface target, including
function arguments, returns, fields, and generic APIs such as `List<IReader>.Add`.
The source class does not declare `: IReader`; matching the required exported
member signatures is the contract.

### Duck Interface Constraints

```n#
duck interface IProcessor<T> {
    func Process(input: T): T
}

class StringProcessor {
    func Process(input: string): string {
        return input.ToUpper()
    }
}

func execute<T>(processor: IProcessor<T>, value: T): T {
    return processor.Process(value)
}

// Usage
result := execute<string>(new StringProcessor(), "hello")
```

### How Duck Interfaces Compile

Duck interfaces use structural checking in N# source, but they are not erased.
The compiler emits an internal CLR interface and records that exact interface on
matching N# types:

```n#
duck interface IReader {
    func Read(): string
}
```

Compiles to an internal interface:

```text
internal interface IReader
{
    string Read();
}
```

For example, the emitted shape is equivalent to:

```text
// Original N#
class FileReader {
    func Read(): string { ... }
}

// CLR shape
class FileReader : IReader
{
    public string Read() { ... }
}
```

That CLR shape makes ordinary interface dispatch reliable. A matching class
flows to `IReader` by reference conversion; a matching struct is boxed when it
becomes an interface value. N# keeps the source surface structural: you do not
write an explicit implementation clause or use a cast to claim conformance.

## Enums

N# supports both string enums and numeric enums as first-class types:

```n#
enum Status: string {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}

enum Priority {
    Low = 0,
    Medium = 1,
    High = 2
}
```

### Using Enums

String enums can be used as parameter types, return types, and record properties — just like numeric enums:

```n#
// As a parameter type
func checkActive(status: Status): bool {
    return status == Status.Active
}

// As a return type
func getDefault(): Status {
    return Status.Pending
}

// In records
record User {
    Name: string
    CurrentStatus: Status
}

// Implicit conversion to string
name: string = Status.Active  // "active"

// Pattern matching
func describe(status: Status): string {
    return match status {
        Status.Active => "Currently active",
        Status.Inactive => "Not active",
        Status.Pending => "Awaiting activation"
    }
}
```

### How Enums Compile

String enums compile to readonly structs with implicit string conversion and JSON support:

```text
[JsonConverter(typeof(StatusJsonConverter))]
public readonly struct Status : IEquatable<Status>
{
    public static readonly Status Active = new Status("active");
    public static readonly Status Inactive = new Status("inactive");
    public static readonly Status Pending = new Status("pending");

    public string Value { get; }
    public static implicit operator string(Status value) => value.Value;
    // ... equality, JSON converter
}
```

Numeric enums emit CLR enums:

```text
public enum Priority
{
    Low = 0,
    Medium = 1,
    High = 2
}
```

### What a numeric enum inherits

A numeric enum's base type is `System.Enum`, exactly as the CLR gives it, so an enum VALUE carries
that type's instance members without your declaring anything:

```n#
func Describe(priority: Priority): string {
    name := priority.ToString()             // System.Enum.ToString() — a NON-null string
    return name.ToLower()
}

func Includes(flags: Access, flag: Access): bool => flags.HasFlag(flag)
```

`ToString()` is `System.Enum`'s override and returns a non-nullable `string`, so chaining off it needs
no null check. `HasFlag`, `CompareTo`, `GetTypeCode` and `Equals` are inherited the same way, and an
enum value satisfies a parameter typed `System.Enum`, `System.ValueType` or `object`.

The bitwise operators work over two values of one enum type and keep that type — `flags & flag`,
`flags | flag`, `flags ^ flag` — so `(flags & flag) == flag` is the operator spelling of `HasFlag`.

`(int)value` converts an enum to its underlying value, and `(Priority)underlying` converts back — `as`
is the null-propagating reference test, not a numeric conversion, so it is not the operator for this.

## Interfaces

### Basic Interfaces

```n#
interface ICalculator {
    func Add(a: int, b: int): int
    func Subtract(a: int, b: int): int
}

class BasicCalculator : ICalculator {
    func Add(a: int, b: int): int => a + b
    func Subtract(a: int, b: int): int => a - b
}
```

### Interface Properties

```n#
interface IEntity {
    Id: Guid { get; }
    Name: string { get; set; }
}

class User : IEntity {
    Id: Guid { get; }
    Name: string { get; set; }

    constructor() {
        Id = Guid.NewGuid()
    }
}
```

### Generic Interfaces

```n#
interface IRepository<T> {
    func GetById(id: Guid): T?
    func GetAll(): List<T>
    func Add(entity: T): void
    func Delete(id: Guid): bool
}

class UserRepository : IRepository<User> {
    users: List<User> = new List<User>()

    func GetById(id: Guid): User? {
        return users.FirstOrDefault(u => u.Id == id)
    }

    func GetAll(): List<User> => users

    func Add(entity: User) {
        users.Add(entity)
    }

    func Delete(id: Guid): bool {
        user := GetById(id)
        if user != null {
            users.Remove(user)
            return true
        }
        return false
    }
}
```

## Generics

### Generic Classes

```n#
class Container<T> {
    value: T

    constructor(value: T) {
        this.value = value
    }

    func GetValue(): T => value
    func SetValue(newValue: T) {
        value = newValue
    }
}

// Usage
intContainer := new Container<int>(42)
stringContainer := new Container<string>("hello")
```

### Generic Constraints

A `where` clause constrains a type parameter, on a `class`, `struct`, `record`, `interface` or
`union` alike, and on functions. It is written after the base and interface list and before the body:

```n#
class Node<T>(id: int): Base, IPrintable where T : struct {
    Value: T
}
```

The constraint reaches CLR metadata, so a constrained type is a constrained type to C# and every
other .NET language, not only inside N#.

```n#
// Class constraint
class Repository<T> where T : class {
    items: List<T> = new List<T>()

    func Add(item: T) {
        items.Add(item)
    }
}

// Struct constraint
class ValueContainer<T> where T : struct {
    value: T?

    func HasValue(): bool => value != null
}

// Interface constraint
class Processor<T> where T : IComparable<T> {
    func GetMax(a: T, b: T): T {
        return if a.CompareTo(b) > 0 { a } else { b }
    }
}

// Constructor constraint
class Factory<T> where T : new() {
    func Create(): T {
        return new T()
    }
}
```

### Multiple Constraints

```n#
class Service<T> where T : class, IDisposable, new() {
    func CreateAndUse() {
        instance := new T()
        try {
            // Use instance
        } finally {
            instance.Dispose()
        }
    }
}
```

One clause per constrained parameter — a two-parameter type takes two:

```n#
class Map<K, V> where K : class where V : struct {
    Count: int
}
```

### What is checked, and where

A type argument is checked against its declaration's constraints when you **construct** the type:

```n#
class Box<T> where T : struct {
    Value: T
}

b := new Box<string>()   // ERROR NL208: `string` is not a non-nullable value type, but type
                         // parameter `T` of `Box` requires one (the `struct` constraint)
```

Two current limits, both being worked on:

- **A constraint naming a BCL interface does not emit yet.** `where T : IComparable<T>` and
  `where T : class, IDisposable, new()` — the `Processor` and `Service` examples above — are
  refused at build time, because the emitter's supported-type list does not yet admit those
  interfaces as constraint targets. Constraints naming your own interfaces and classes
  (`where T : IIdentifiable`, `where T : Shape`) do emit. The same limit applies to functions.
- **Only construction sites are checked.** A violating type argument written in a field,
  parameter, return type, local or base list is not yet reported; the constraint is still recorded
  in metadata, and the same argument is reported when you construct it.

## Using .NET Generic Types

A closed generic type from the BCL or from any referenced assembly is an ordinary type in N#. You
construct it, call its operators, index it and pass it to generic methods with no ceremony and no
special-casing in the compiler — `System.Collections.Generic.List<int>` and
`System.Numerics.Vector<int>` go through exactly the same paths.

### Constructing

Write `new`, the closed type, and the arguments. The constructor is selected by ordinary overload
resolution over the type's public constructors:

```n#
import System.Collections.Generic
import System.Numerics

func Load(values: int[], index: int): Vector<int> {
    block := new Vector<int>(values, index)   // the (T[], int) constructor
    broadcast := new Vector<int>(7)           // the (T) constructor: every lane is 7
    return block + broadcast
}

func Counts(): Dictionary<string, int> {
    return new Dictionary<string, int>(16, StringComparer.Ordinal)
}
```

A **value type** written with no arguments and no parameterless constructor is its zero value, the
same reading C# gives it:

```n#
empty := new Vector<int>()   // all lanes zero
```

Arguments evaluate left to right, exactly once each, and any exception the constructor raises reaches
you unchanged — `new Vector<int>(values, values.Length - 1)` raises the BCL's own
`ArgumentOutOfRangeException`.

### Operators

If the type declares operators, you write them:

```n#
func Mask(a: Vector<int>, b: Vector<int>): Vector<int> {
    return ~Vector.Equals(a, b) & a
}

func Elapsed(start: DateTime, finish: DateTime): TimeSpan {
    return finish - start
}
```

`+ - * / % & | ^ << >>`, the comparisons `== != < <= > >=`, and the unary `- + ! ~` all resolve to the
type's own `op_*` declarations, with C#'s overload rules — including the more-specific rule that
decides between two applicable operators. Compound assignment (`+=`, `-=`, `*=`, `/=`) uses the same
operators, on a local, a field, an array element or a collection indexer:

```n#
func SumBlocks(values: int[], lanes: int): int {
    accumulator := new Vector<int>(0)
    i := 0
    while i <= values.Length - lanes {
        accumulator += new Vector<int>(values, i)
        i = i + lanes
    }
    return Vector.Sum(accumulator)
}
```

The built-in numeric, `bool`, `char` and `string` operators are unaffected: `1 + 2` is still a single
IL instruction, not a method call.

### Conversion operators

A conversion operator is a member like any other, so the ones a referenced assembly's type declares
are the ones you get — in an annotated local, an argument, a return, and a written cast. An argument
is the case that also decides **which overload** is called: a candidate is applicable when every
argument has an implicit conversion to its parameter, and an operator a type declares about itself is
one of those:

```n#
func Outcome(result: XElement): string? {
    attribute := result.Attribute("outcome")   // implicit operator XName(string)
    return (string?)attribute                  // explicit operator string?(XAttribute)
}
```

A user-defined conversion is ranked BELOW every conversion the language defines, so an overload
reachable without one always wins, and it never takes part in inferring a generic method's type
arguments.

```n#
import System
import System.Xml.Linq
import NSharpLang.Runtime

func Tag(): XName {
    name: XName = "entry"          // implicit operator XName(string)
    return name
}

func Moment(instant: DateTime): DateTimeOffset {
    return instant                 // implicit operator DateTimeOffset(DateTime)
}

func Arm(): Union<int, string> {
    return 5                       // implicit operator Union<T0, T1>(T0)
}

func Rounded(value: double): decimal {
    return (decimal)value          // explicit operator decimal(double) — the cast is required
}
```

The operator is found on **either end** of the conversion, on the type converted from or the type
converted to, so a wrapper's own inbound conversion works even when the other end is `int`. Selection
follows C#'s rules: a built-in conversion always wins (`decimal d = 5` is numeric widening, not
`decimal.op_Implicit`), a user-defined conversion is considered once and never chained with another,
the source may widen into the operator's parameter, and when two operators are equally good the
conversion is an **error** rather than an arbitrary pick — `Union<float, decimal> u = 5` reports a
type mismatch, because `int` reaches `float` and `decimal` equally well and neither reaches the other.

An `implicit` operator is reached without a cast and an `explicit` one only with one; a cast also
reaches the implicit operators, so `(XName)"entry"` is the same conversion written out.

A **lifted** conversion is not synthesised: `S? → T?` needs an operator that actually names the
nullable types. And a conversion declared by a generic type is only reachable once that type is
closed over real types — inside `func Wrap<T>(): Union<T, string>` the conversion from `T` does not
resolve yet.

### Writing a property

A referenced assembly's **settable instance property** is an ordinary assignment target, exactly as
your own type's is:

```n#
import System.Text

func Sized(): StringBuilder {
    builder := new StringBuilder()
    builder.Capacity = 64
    return builder
}
```

Three shapes are refused, each for a reason rather than a list: an `init`-only property is not an
assignment target outside construction; a property of a **value-type** receiver is not written
through, because the write would land on the copy the read loaded (bind the struct to a local of its
own type and write that); and a type your own project is still compiling answers through the ordinary
source path instead.

### Indexers

An indexer is an ordinary member, so `receiver[index]` works on any type that declares one, and its
bounds behaviour is the type's own:

```n#
func Lane(a: Vector<int>, index: int): int {
    return a[index]
}
```

### Generic methods

A generic method's type arguments are inferred from the arguments you pass, including from a
constructed generic argument:

```n#
func Reduce(a: Vector<int>): int {
    return Vector.Sum(a)              // Sum<T> binds T = int from Vector<int>
}

func Nearest(a: Vector<long>, b: Vector<long>): Vector<long> {
    return Vector.Min(a, b)           // Min<T> binds T = long
}

func Hash(state: byte, name: string): int {
    return HashCode.Combine(state, name)   // one type parameter per argument
}
```

A type argument may be a type parameter of the declaration you are writing it in, so the same call
works inside your own generic type — the CLR resolves it once per constructed type:

```n#
struct Outcome<TOk, TErr> {
    ok: TOk
    state: byte

    constructor(value: TOk, tag: byte) {
        ok = value
        state = tag
    }

    override func GetHashCode(): int {
        return HashCode.Combine(state, ok)   // T2 binds to TOk
    }
}
```

Inference is checked, not guessed: a type parameter two arguments would bind differently is an error
rather than a silent choice, and the inferred arguments are validated against the method's declared
constraints.

#### Writing the type arguments

When inference has nothing to go on — a method whose type parameters appear only in its RESULT, or
only in a lambda's PARAMETER and nowhere else — write the list. (A type parameter in a lambda's
RESULT does not need it: the lambda's body decides it. `values.ConvertAll(v => v.ToString())` and
`Comparer<int>.Create((a, b) => a - b)` both infer, and the lists written below are shown to
document the spelling rather than because they are required.) It works on a static method, on an
instance method, and on a method of a constructed generic receiver:

```n#
import System.Collections.Generic
import System.Text.Json
import System.Threading.Tasks
import NSharpLang.Runtime

func Ages(json: string): Dictionary<string, int> {
    // A trailing optional whose default is null is filled, so `options` need not be written.
    return JsonSerializer.Deserialize<Dictionary<string, int>>(json)
}

func Texts(values: List<int>): List<string> {
    // An INSTANCE generic method; the lambda is bound against Converter<int, string>. Written out
    // here, though the lambda's own result would infer `string` on its own.
    return values.ConvertAll<string>(v => v.ToString())
}

func Ready(value: int): Task<int> {
    return Task.FromResult<int>(value)   // written where inference would also have done
}

func Descending(): Comparer<int> {
    // A static member of a CONSTRUCTED owner: the member is chosen on Comparer<int>, so the
    // lambda takes its shape from Comparison<int>.
    return Comparer<int>.Create((left, right) => right - left)
}

func Describe(u: Union<int, string>): string {
    if u.Is<int>() {
        seen := -1
        if u.TryGet<int>(out seen) {          // an `out` parameter over the written argument
            return u.As<int>().ToString() + "/" + seen.ToString()
        }
    }

    return u.Match<string>(a => a.ToString(), b => b)
}

func Wrap(value: int): Result<int, string> {
    return ResultFactory.Ok<int, string>(value)   // a generic STATIC on an external type
}
```

**A written type argument may be a type parameter of the method you are writing it in.** The call
is then left open in the same way the declaration is, and the CLR resolves it once per instantiation:

```n#
import System.Text.Json

func Read<T>(json: string, options: JsonSerializerOptions): T? {
    return JsonSerializer.Deserialize<T>(json, options)
}

func ReadFirst<T>(json: string, options: JsonSerializerOptions): T? {
    return Read<T>(json, options)          // and it travels through your own generics
}
```

The result is the external method's own return type over your parameter, so `Deserialize<T>`'s
`TValue?` is a `T?` here. Writing it into a `T` return needs the usual null handling.

**A written type argument is a whole TYPE**, not just a name: a nullable annotation, an array, a
tuple, a nested generic and a fully qualified name all belong in the list, and so does any
combination of them.

```n#
import System.Collections.Generic
import System.Linq
import System.Threading.Tasks

func NoRows(): Task<List<int>?> {
    return Task.FromResult<List<int>?>(null)              // nullable, over a nested generic
}

func NoAge(): Task<int?> {
    return Task.FromResult<int?>(null)                    // a nullable VALUE type
}

func NoNames(): Task<string[]?> {
    return Task.FromResult<string[]?>(null)               // an array
}

func EmptyPairs(): int {
    return Enumerable.Empty<(Item: int, Label: string)>().Count()   // a named tuple
}
```

A nullable REFERENCE annotation is not a CLR type, so `Task<List<int>?>` and `Task<List<int>>` are
one constructed type; a nullable VALUE type is a real construction, and `Task<int?>` is
`Task<Nullable<int>>`.

The `<` that opens the list is told apart from a comparison the way C# tells them apart: the type
argument list is read only when its matching `>` is followed directly by a `(` — a generic call — or
by a `.` — a constructed generic type receiver such as `Comparer<int>.Create`. Everything else stays a
comparison, `a < b && c > d` and `x < y.Z` included. Two shapes sit on the boundary and behave as they
do in C#: `a < b > (c)` is read as the generic call `a<b>(c)`, and `a < (b) > (c)` is a comparison,
because a one-element parenthesised group is not a tuple type.

The rest of the rules are the ones C# states, and they are the same rules your own generic methods
follow:

- The **count must match the declaration's arity**. `u.Is<int, string>()` against `Is<T>()` is
  [NL207](./errors/NL207.md), in the same words a method of your own would report.
- The written arguments are **validated against the declared constraints**, so a type argument a
  constraint refuses does not bind.
- A **trailing optional** parameter whose default is `null` is filled, which is why
  `JsonSerializer.Deserialize<T>(json)` needs no `options`.
- A **lambda argument** is bound against the SUBSTITUTED parameter type, so it knows its own
  parameter and result types; that is what makes `Match<string>(a => ..., b => ...)` and
  `Comparer<int>.Create((a, b) => a - b)` write the way they do.
- An `out` or `ref` parameter over a type parameter closes the same way: `TryGet<int>(out seen)`
  passes the address of an `int`.

Overload resolution over the written list is the ordinary one whenever the arguments have types of
their own. A call carrying a LAMBDA or a METHOD GROUP is resolved by method type inference instead:
the arguments that do have types are folded in first, each lambda is then analysed under the
parameter types that fixes, and its result closes whatever type parameter stands in the delegate's
return position (see [lambda type inference](functions.md#type-inference-in-lambdas)). Two candidates
that survive that are separated by the same tie-breaks C# uses — a candidate that would throw a
lambda's result away loses to one that keeps it (`Task.Run(() => 42)` picks `Func<TResult>` over
`Action`), between two candidates that close to the SAME signature the less generic one wins
(`Max<TSource>` over `Max<TSource, TResult>`), and last the candidate whose signature was WRITTEN
more specifically wins. That last rule is what answers `Task.Run(() => Task.FromResult(11))`:
`Run<TResult>(Func<TResult>)` and `Run<TResult>(Func<Task<TResult>>)` both close to
`Func<Task<int>>`, and `Func<Task<TResult>>` says more than `Func<TResult>`, so the call's type is
`Task<int>` rather than `Task<Task<int>>`. A lambda that EXACTLY matches one delegate also beats one
it merely converts to, which is how `Run(Func<Task>)` — a legal target for a lambda handing back a
`Task<int>` — loses to the overload that keeps the result. Anything still ambiguous is refused rather
than guessed. An `out` argument still binds only when the name leaves exactly ONE candidate at that arity.

### Over your own type parameters

Everything above holds when the type argument is a type parameter of the declaration you are writing
in. `EqualityComparer<TOk>` inside `Outcome<TOk, TErr>` is the same external type as
`EqualityComparer<int>` is outside it, so it needs no special spelling and no wrapper:

```n#
import System
import System.Collections.Generic

struct Outcome<TOk, TErr>: IEquatable<Outcome<TOk, TErr>> {
    ok: TOk
    err: TErr
    state: int

    constructor(ok: TOk, err: TErr, state: int) {
        this.ok = ok
        this.err = err
        this.state = state
    }

    func Equals(other: Outcome<TOk, TErr>): bool {
        if state != other.state {
            return false
        }
        return EqualityComparer<TOk>.Default.Equals(ok, other.ok)
    }

    func GetHashCode(): int {
        return HashCode.Combine(state, ok)

### Over your own complete types

The same three places accept an external generic closed over a COMPLETE type of your compilation —
a class, struct, record, union, nested type, an array of one, or a closed instantiation of one of
your own generics — and it does not have to be the enclosing declaration:

```n#
struct Plain: IEquatable<Plain> {
    value: int
    tag: string

    func Equals(other: Plain): bool => value == other.value
    func GetHashCode(): int => value
}

class Item: IComparable<Item> {
    rank: int
    func CompareTo(other: Item): int => other.rank - rank
}

func Report(rows: List<Plain>, seed: IEquatable<Plain>): KeyValuePair<string, Plain> {
    matcher: Func<Plain, bool> = row => row.Value > 0
    ordered: IComparer<Item> = Comparer<Item>.Default
    byName: Dictionary<string, Plain> = new Dictionary<string, Plain>()
    ...
}
```

- **A base list.** `struct Plain: IEquatable<Plain>` and `class Item: IComparable<Item>` land the
  CONSTRUCTED interface in the emitted metadata, and the BCL dispatches through it:
  `EqualityComparer<Plain>.Default.Equals` calls your `Equals`, and `List<Item>.Sort()` orders by
  your `CompareTo`. The same holds for a closed instantiation of your own generic —
  `EqualityComparer<Outcome<int, string>>.Default` reaches `Outcome<TOk, TErr>`'s implementation.
- **Locals, fields, parameters and returns.** `IEquatable<Plain>`, `IEquatable<Outcome<int, string>>`,
  `Comparer<Item>`, `Func<Plain, bool>`, `KeyValuePair<string, Plain>`, `IEnumerable<Plain>` and
  `Dictionary<string, Plain>` are ordinary member and local types. Assigning your value into a
  constructed interface it implements is the ordinary conversion — a class needs no instruction, a
  struct boxes.
- **Static receivers.** `EqualityComparer<Plain>.Default`, `Comparer<Item>.Default` and
  `Comparer<Outcome<int, string>>.Default` read the closed type's own member.

### Generic methods your own types declare

A `class`, `struct` or `record` may declare a generic method, whether or not the type itself is
generic. The method's type parameters are its own: they are separate from the declaring type's, they
may be constrained separately, and they reach CLR metadata as real method type parameters — the
method is a generic method to C# and every other .NET language, not only inside N#.

```n#
struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    // The method's `U` is nothing to do with the box's `T`.
    static func Of<U>(value: U): Box<U> {
        return new Box<U>(value)
    }

    // A signature may name BOTH scopes.
    func Map<TResult>(f: Func<T, TResult>): Box<TResult> {
        return new Box<TResult>(f(Value))
    }
}

class Plain {
    func Echo<T>(value: T): T {
        return value
    }

    static func Wrap<T>(value: T): Box<T> {
        return new Box<T>(value)
    }
}
```

Three separate places in that declaration name an external generic over its own parameters, and each
is ordinary:

- **A static receiver.** `EqualityComparer<TOk>.Default` reads the closed type's own `Default`
  property, and `.Equals(a, b)` on the result is an ordinary instance call — the substituted member
  types come out of the closed type's metadata, not out of a table.
- **A base list.** `IEquatable<Outcome<TOk, TErr>>` names the type's own constructed self. The
  interface lands in the emitted metadata as the CONSTRUCTED interface (`GetInterfaces()` reports
  `IEquatable<Outcome<int, string>>` for `Outcome<int, string>`), and `func Equals(other: Outcome<TOk,
  TErr>)` satisfies it: the BCL's own `EqualityComparer<Outcome<int, string>>.Default` picks the
  `IEquatable<T>` comparer and calls straight into it. `class Node<T>: IComparable<Node<T>>` works
  the same way, including through `Comparer<Node<string>>.Default`.
- **Fields, parameters and returns.** `List<T>`, `Dictionary<string, T>`, `IEnumerable<T>`,
  `KeyValuePair<TKey, TValue>`, `Func<T, bool>?`, `Action<T>?` and `T[]` are all ordinary member
  types on a generic class or struct, and each instantiation carries its own closed field types.

Any external generic definition works here, not a fixed set of BCL heads: the head resolves through
ordinary scoped type resolution at the arity you wrote, and the arguments are closed with the CLR's
own construction. A wrong arity is reported as an ordinary [NL207](/docs/errors/NL207), and an
interface member you do not implement is reported as an ordinary [NL325](/docs/errors/NL325) naming
the constructed interface.

Call one with its type arguments written or inferred, on either kind of owner:

```n#
func Use(): int {
    box := new Box<int>(3)
    plain := new Plain()

    mapped := box.Map<string>(v => v.ToString())   // written
    echoed := plain.Echo(7)                        // inferred
    wrapped := Plain.Wrap(5)                       // inferred, static
    made := Box<int>.Of(4)                         // inferred, on a constructed owner

    return echoed + wrapped.Value + made.Value + mapped.Value.Length
}
```

A generic method on a GENERIC owner is reached through the receiver's instantiation, so a static one
needs the owner written out — `Box<int>.Of(4)` rather than `Box.Of(4)` — everywhere except inside the
declaring type's own code, where the instantiation is the type's own.

Constraints work as they do on a type: `where U : class`, `struct`, `new()`, and your own interfaces
and classes. They are validated at the call site and recorded in metadata.

```n#
class Registry {
    static func Register<T>(value: T): bool where T : class {
        return value != null
    }
}
```

Two rules the compiler enforces about the type-argument list itself:

- It is **all or nothing**. `Pick<int>(1, "a")` against `Pick<TFirst, TSecond>` is
  [NL207](./errors/NL207.md), and so is writing a list on a method that has no type parameters.
  Omitting the list entirely is always allowed where inference can close it.
- A method's type parameter may **not reuse a name its declaring type already binds**.
  `struct Box<T> { func Shadow<T>() }` is [NL316](./errors/NL316.md): inside the member both
  spellings are legal and only the inner one means anything.

### Current limits

- An **array of a constructed external value-type generic** (`Vector<int>[]`) does not emit yet.
  Arrays of your own types, of reference types, of the primitive types and of **tuples**
  (`(Item: string, Count: int)[]`) are unaffected. The same limit applies to an array of an external
  generic closed over your own type parameter (`List<T>[]`); `T[]` itself is unaffected.
- **Implementing `IEnumerable<T>` on your own class** compiles, but the emitted type cannot be
  loaded: `IEnumerable<T>` inherits the non-generic `IEnumerable.GetEnumerator()`, which differs from
  the generic one only by return type, and N# has no explicit interface implementation to spell it.
  This is not specific to your own type argument — `class Bag: IEnumerable<int>` has the same
  problem. You do not need the interface to be iterable: a `for x in bag` loop binds an accessible
  parameterless `GetEnumerator()` directly, so declaring one is enough. Return `IEnumerable<T>` from
  a method when a caller needs the interface itself.
- A **generic method an `interface` declares** — `interface IHas { func Get<T>(): T }` — is not
  compiled yet. A generic method on a `class`, `struct` or `record` is unaffected.
- A **generic method declared on your own type** and called with a lambda — `holder.Match(v => ...)`
  — type-checks (its type arguments are inferred from the receiver, the other arguments and the
  lambda's body) but does not EMIT yet. A generic FREE function with a delegate parameter is
  unaffected, and so is every generic method on an external type; write the type argument out
  (`Match<string>(...)`) or move the call into a free function.
- **Null-conditional INDEXING** (`items?[0]`) is not compiled yet; `?.` on a member or a method is
  unaffected, and an explicit null check reads the element.
- An argument that must be **boxed into an `object` parameter of a GENERIC function**
  (`Wrap<int>(value, fallback)` where `Wrap` takes `o: object?`) is not converted yet. The same
  argument reaches a non-generic function's `object?` parameter without ceremony.
- A generic method written with its type arguments **directly on a call's RESULT**
  (`Make().As<int>()`) does not resolve; bind the receiver to a name first (`made := Make()` then
  `made.As<int>()`). An ordinary member off a call result (`Make().Index`) is unaffected.
- A **lambda or a method group as a CONSTRUCTOR argument** compiles (`new Lazy<int>(() => 1)`),
  including into an external generic closed over one of your own types — `new Lazy<Query>(MakeQuery)`
  and `new Lazy<Query>(() => new Query())` both work, and so does reading `.Value` off the result.
  The constructor is chosen by the arity written; two overloads at that arity that both admit the
  written arguments are refused rather than guessed, so write one of them out (a local of the
  declared delegate type, then `new T(thatLocal)`) if you hit that.
- A **fully qualified** external type reaches fewer positions than an imported one. Written out
  (`NSharpLang.Runtime.Result<int, string>`) it works in `typeof`, in a `:=` initializer, as a
  local's declared type and as the receiver of a generic or `out`-taking member, but not as a `type`
  alias target, a parameter type, an annotated local's initializer, or a `new` expression. Importing
  the namespace and using the simple name reaches all of those.
- `default` is written **bare**; the C#-style `default(T)` is not N# syntax — the parser reads it as
  the keyword followed by a call, and the analyzer reports a call on a maybe-null value. Annotate the
  target instead (`x: T = default`, `return default` on a typed function).
- A `[MethodImpl(...)]` attribute is **accepted and then dropped**: the source compiles with no
  diagnostic, and the emitted method's `GetMethodImplementationFlags()` is `0` whether the argument is
  a single `MethodImplOptions` value or a flags combination. Treat inlining hints as unavailable
  rather than applied.
- An attribute **target prefix** and an attribute on an **enum member** have no N# spelling.
  `[assembly: InternalsVisibleTo(...)]`, `[return: NotNull]` and `[field: NonSerialized]` name
  positions the grammar cannot write at all — N# writes every attribute directly on the declaration
  it belongs to — and an enum's members become literal fields of a type the compiler finalizes before
  any attribute in the program has been bound, so an attribute written on one would have no row to be
  attached to. Both report [`NL935`](./errors/NL935.md) at the attribute and keep parsing the
  declaration around it. A **positional constructor parameter** is the one place where a prefix would
  otherwise be needed and is not: the attribute's own `[AttributeUsage]` picks between the parameter
  and the field that parameter declares (see [Attributes](./basics.md#attributes)). Assembly-level
  attributes that the toolchain owns are written in `project.yml` rather than in source. Generic
  attributes (`class Mark<T>: Attribute`) are not supported either.
- A **catch clause's exception type must be a simple name**: `catch ex: System.InvalidOperationException`
  does not parse, `import System` plus `catch ex: InvalidOperationException` does. (A type used only
  as a catch type, only inside a `Func<…>` in a signature, only in an attribute or only as a type
  argument DOES now count as a use of its import; `NL010` no longer reports those.)
- A **defaulted parameter is filled only for a member of a referenced assembly**. Omitting the
  argument works for an external instance, static, extension or CONSTRUCTOR parameter, whose default
  the call site reads out of the callee's metadata and writes as a literal. A function, method or
  constructor declared in the SAME project does not yet offer its defaults to a call in that
  project — pass every argument, or split the declaration into explicit arities. The defaults that can be filled are the null
  reference, an integral, floating, `char`, `bool`, `string` or enum constant, and a `Nullable<T>`
  with no value; a `decimal` or `DateTime` default, and a bare `[Optional]` with no constant at all,
  still decline.
- **Reading a member off a local initialised from an external static call** declines
  (`summary := Kernels.Summarize(args)` then `summary.ShowHelp`). The same member read works off a
  parameter of that type and off a local initialised with `new`, so binding the value differently is
  the workaround.
- A collection expression whose elements have **no common type**, written against an overload set of
  the same arity declared in the SAME project, type-checks and then declines at emission
  (`Sink.Accept([1, "b", null])` where `Accept` takes both `int[]` and `object[]`). The emitter picks
  a same-arity candidate before it looks at the argument. A single candidate of that arity, and an
  overload set reached with a literal whose elements DO have a common type, are both unaffected.
- A **conditional whose arms BOTH throw** (`ok ? throw new A() : throw new B()`) declines at emission
  with [NL103](./errors/NL103.md): there is nothing for the conditional to be worth, and C# refuses
  it for the same reason. Write the throw as a statement instead. A conditional with only ONE
  typeless arm — a `null`, a `default` or a single `throw` — is decided by what the conditional is
  written *at*; see [target-typed conditional arms](./language-tour.md#conditional-expressions).
- A **bare `GetType()`** with no receiver at all reports [NL412](./errors/NL412.md): the members
  `object` declares and your type inherits are reached through a receiver, not through the bare name.
  `this.GetType()`, `other.GetType()` on a parameter or a local, and `(this as object).GetType()` all
  work, on a `class` and on a `record`. Inside a **`struct`**'s own method the `this.` spelling is not
  available for an inherited member either — take the value through a parameter or a local first.
- **Tuple element NAMES do not survive an `IGrouping.Key` hop.** `xs.GroupBy(x => (x.Code, x.Line))`
  emits and `group.Key.Item1` reads the element, but `group.Key.Code` does not: the names are
  metadata the grouping's key type does not carry, and nothing at the call site writes them down.
  Names DO survive a declared return type — `func Pairs(): List<(Code: string, Line: int)>` then
  `pair.Code` — so hand the grouped keys to a function that declares them.
- Overloaded **free functions** are not emitted: two `func Accept(...)` declarations at file scope
  with different parameter types stop the columnar backend at its declaration scan. Declare the
  overload set on a type instead. Two same-named free functions in DIFFERENT namespaces are not an
  overload set and are unaffected — they are two functions, emitted onto their own namespaces'
  `Program` holders (see [Functions](./functions.md#what-a-free-function-looks-like-from-net)).

## Nullable Types

### Nullable Reference Types

```n#
// Non-nullable (default)
name: string = "Alice"
// name = null  // Error!

// Nullable
optionalName: string? = null
optionalName = "Bob"  // OK
```

A reference `T?` is an **annotation**, not a construction: `MarkupContent?` and `MarkupContent` are
the same CLR type, and everything after the dot is whatever the class itself declares. `Value`,
`HasValue` and `GetValueOrDefault` are `Nullable<T>`'s members and exist only for a **value** `T?`;
on a reference `T?` they are ordinary names, and a class free to declare them or not.

```n#
class MarkupContent {
    Value: string
    constructor(value: string) { Value = value }
}

func Text(markup: MarkupContent?): string? {
    return markup?.Value       // string? — the CLASS's `Value`, lifted by the chain
}
```

Reading such a member is an ordinary dereference, so it follows the ordinary rules: guard it with
`?.`, a null check or `must`. `must markup` on a reference `T?` is the null assertion it always was.

### Nullable Value Types

```n#
age: int? = null
age = 25

if age != null {
    // Direct null checks narrow nullable values inside this block.
    definitelyAge: int = age
    Console.WriteLine($"Age: {definitelyAge}")
}

// Null-coalescing operator
displayAge := age ?? 0
```

**Any** non-`ref struct` value type can be the `T` in a `T?`: the scalars, `bool`, `char`, `decimal`,
`DateTime`, `Guid`, a tuple, and an enum, a struct or a struct record **you declare yourself**. A
`T?` is `System.Nullable<T>` in metadata whatever `T` is, so a C# caller sees exactly the type it
expects.

`Nullable<T>`'s own surface comes with it, also whatever `T` is — `HasValue`, `Value` and both
`GetValueOrDefault` overloads:

```n#
struct Money {
    Amount: int
}

func Spend(budget: Money?, fallback: Money): int {
    if !budget.HasValue {
        return budget.GetValueOrDefault(fallback).Amount
    }

    return budget.GetValueOrDefault().Amount
}
```

`GetValueOrDefault()` answers `T`'s own `default` when the value is absent and never throws, so it
needs no guard. `Value` does throw, so the compiler warns when you read it without proving the value
is there ([NL907](./errors/NL907.md)) — `must`, a null check or `GetValueOrDefault` are the three
ways to say what you mean.

**A name `Nullable<T>` declares binds on the nullable; every other name binds on `T`.** The two
types share three names — `ToString`, `Equals` and `GetHashCode`, which `Nullable<T>` overrides —
and those are the nullable's, exactly as they are in C#. All three are null-safe — for an ABSENT
value `v.ToString()` is `""`, `v.GetHashCode()` is `0`, and `v.Equals(other)` is true only when
`other` is null as well; none of them throws. Nothing else is on that surface, so `v.CompareTo(3)`
reads `int`'s own overloads, and `v.GetType()` is
`object`'s — it boxes, and boxing an absent nullable produces a null reference, so the compiler
reports the dereference ([NL905](./errors/NL905.md)) the program really would hit.

```n#
func Describe(v: int?): string? {
    return v.ToString()        // Nullable<int>.ToString() — "" when absent, and never a throw
}
```

`==` and `!=` are **lifted** over a nullable value type: two absent values are equal, an absent one
differs from every present one, and the answer is a plain `bool` rather than a `bool?`. One side may
be the non-nullable type.

```n#
age: int? = null
same := age == 25          // bool — false, and false again for `age == 0`
absent := age == null      // the null comparison, unchanged

ready: bool? = TryLoad()   // a lifted boolean
if ready == true {         // true ONLY when there IS a value and it is true
    // ...
}
```

That is the spelling a lifted boolean is tested with, and it narrows exactly like the boolean it
compares: `c == true` proves what `c` proves, `c == false` proves the mirror, and the two `!=`
spellings swap the branches. When the operand crosses a `?.`, only the branch the comparison
*decided* proves anything — `map?.TryGetValue(key, out value) == true` holds only when `map` was
non-null **and** the call answered true, so that branch narrows both `map` and `value`, while its
other branch is a disjunction and proves neither.

### Lifted Operators

The arithmetic (`+ - * / %`), bitwise (`& | ^`), shift (`<< >>`), comparison (`< > <= >=`) and unary
(`- ~ !`, `++`, `--`) operators are all **lifted** over a nullable value type, following C# §12.4.8.
Wherever the operator exists for `T`, it exists for `T?`, and one side may be the plain `T`.

```n#
age: int? = LoadAge()

next := age + 1            // int?  — absent when `age` is absent
doubled := age * 2         // int?
mask := flags & 0xFF       // int?  — the bitwise family lifts too
inverted := -age           // int?  — absent in, absent out
```

Two result shapes, because C# has two:

- **Arithmetic, bitwise, shift and unary** answer the **lifted** type. `int? + int` is an `int?`, and
  it is absent exactly when an operand was absent.
- **An ordering comparison answers a plain `bool`.** `a < b` is **false** when either side is
  absent — not absent — so the comparison is always decided. That also means `!(a < b)` is *not*
  `a >= b` once either side can be absent: with an absent operand **both** are false.

Only the *presence test* is lifted, never the arithmetic. Both operands are always evaluated, left
before right — a lifted operator does not short-circuit — division by a **present** zero still throws
`DivideByZeroException`, and a lifted `+` inside `checked(...)` still throws `OverflowException` on a
present overflow. An absent operand answers before the arithmetic runs, so neither throws then.

`++`, `--` and the compound forms read and write back the same `T?` storage: stepping an absent
`int?` leaves it absent rather than making it `1`.

```n#
count: int? = LoadCount()
count++                    // still absent if it was absent
count += 5                 // int? — absent stays absent
```

User-defined operators lift the same way. `decimal?`, `TimeSpan?`, a struct **you** declare, and any
other value type that declares `op_Addition`, `op_LessThan` or `op_Equality` gets the lifted form of
each; a nullable enum lifts its bitwise operators through the underlying type and keeps the enum as
the result.

```n#
elapsed: TimeSpan? = Measure()
total := elapsed + TimeSpan.FromSeconds(1)   // TimeSpan?
access: Access? = LoadAccess()
combined := access | Access.Write            // Access?

struct Cents {
    Value: int

    static func operator +(a: Cents, b: Cents): Cents => new Cents { Value: a.Value + b.Value }
}

owed: Cents? = LoadOwed()
billed := owed + new Cents { Value: 5 }      // Cents? — absent when `owed` is absent
```

#### Three-valued `bool?` logic

`&` and `|` over `bool?` follow C# §12.14's three-valued table rather than the ordinary lift: an
absent operand does **not** make the answer absent when the other operand already decides it.

| `a` | `b` | `a & b` | `a \| b` |
| --- | --- | --- | --- |
| `true` | `true` | `true` | `true` |
| `true` | `false` | `false` | `true` |
| `true` | `null` | `null` | `true` |
| `false` | `null` | `false` | `null` |
| `null` | `null` | `null` | `null` |

`^` has no such shortcut — an exclusive-or needs both values — so it is the ordinary lift.

`&&` and `||` are **not** lifted, and C# refuses them over `bool?` for the same reason: a
short-circuiting operator has to decide whether to evaluate its right side from the left side alone,
and an absent left side cannot answer that. Say what an absent value means first — `ready == true`,
`ready != false` or `ready ?? false` — or use the non-short-circuiting `&` and `|`, which evaluate
both sides and answer from the table above.

A bare `null` operand is **not** a lift: `null + 1` needs a `T?` *type*, and the null literal has
none, so it stays an error. Nothing in the lifted family is constant-folded — `(age ?? 0) + 1`
remains the way to say "treat absent as zero".

### Null-conditional Operator

`a?.B` evaluates `a` once and reads `B` only if it is not null; if it is, the **whole chain to the
right of the `?`** is skipped and the expression is null. That is why `user?.Address.City` never
throws even when `Address` is a plain access: once `user` is null, nothing after the `?` runs.

```n#
user: User? = GetUser()
name := user?.Name           // string?  — null if user is null

// Chaining: null anywhere on the way is null at the end
city := user?.Address?.City

// Calls too
text := user?.ToString() ?? "anonymous"
```

The result is **lifted**: reading a member whose type is a value type gives you the nullable of it,
because "no value" has to be expressible.

```n#
length := user?.Name?.Length      // int?, not int
count := (user?.Name?.Length) ?? 0
```

The lift belongs to the **whole chain**, not to the link that carries the `?`. Everything written to
the right of a `?` is a continuation of the same expression: it never runs with a null receiver, so
it is not a null dereference, and it is the chain's own result that ends up lifted.

```n#
count := snapshot?.Units.Count    // int?  — `.Count` is part of the chain, not a dereference of it
total := snapshot?.Units.Count ?? 0
first := snapshot?.Units[0]       // int?  — an index continues the chain too
trimmed := snapshot?.Name.Trim()  // string? — an invocation the `?` guards is lifted as well
```

Parentheses end a chain, exactly as they read: in `(user?.Address).City` the `?` guards only the
first access, and the second one runs on whatever that produced — so the member after the
parenthesis IS an ordinary dereference of a maybe-null value, and has to be guarded on its own.

`?.` also works on a nullable value (`when?.Year` on a `DateTime?` reads `Year` off the value when
there is one) and on an unconstrained type parameter, where it means the same thing for both kinds of
instantiation — never null for a value one, a real check for a reference one:

```n#
struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    override func ToString(): string => Value?.ToString() ?? "<none>"
}
```

Writing `?` on a plain, non-nullable value (`5?.ToString()`) is rejected: there is no null to test for.

### Null checks instead of null-forgiving

N# does not use null-forgiving `!` as an escape hatch. Prefer a direct check, `??`, or `match` so the proof stays in the code:

```n#
optionalName: string? = GetName()

if optionalName != null {
    // `optionalName` is narrowed to `string` in this block.
    name: string = optionalName
}

displayName := optionalName ?? "anonymous"
```

`null!`, `default!`, and blind `.Value` access are not N# style. Replace suppression with explicit nullable handling.

### Guard clauses narrow everything after them

A branch that the flow can never come back from hands what follows it the fact the branch it did not
take proved. `return` and `throw` do that, and so do `break` and `continue` — the branch is gone
either way, so the code after the `if` is reached only when the condition was false:

```n#
func TotalLength(items: string?[]): int {
    total := 0
    for item in items {
        if item == null {
            continue
        }

        // `item` is `string` here — the only way to reach this line is past the guard.
        total = total + item.Length
    }

    return total
}
```

The jump has to leave *this* branch, not something inside it. A `break` written inside a loop or a
`switch` that is itself inside the branch belongs to that loop or that switch, so the branch is still
there afterwards and nothing is narrowed:

```n#
if item == null {
    switch mode {
        case 1 => break     // leaves the `switch`, not the `if`
        default => break
    }
}

length := item.Length       // still an error: `item` is maybe-null
```

A `continue` in that same position *does* narrow, because it belongs to the enclosing loop, which is
outside the branch.

### `assert` narrows everything after it

An `assert` that fails throws, so the statement after it is reached only on the path where its
condition held — which is the guard clause `if !cond { throw }` written the other way round. It
proves exactly what an `if` proves in its then-branch, using the same vocabulary:

```n#
found := items.FirstOrDefault()

assert found != null            // `found` is `Query` from here on
name := found.Name

assert left != null && right != null      // an `&&` chain proves both halves
assert value is string text               // the pattern binds `text` and narrows it

found: Entry? = default
assert map.TryGetValue(key, out found)    // the call's own `[MaybeNullWhen(false)]` applies
label := found.Label
```

The assert's **message**, when it has one, is not narrowed: it is the expression evaluated when the
assert fails, which is the path where the condition did not hold.

### A call can be the guard

`[DoesNotReturnIf(bool)]` on a parameter says the call returns only when that argument took the other
value, which makes the call a guard clause the signature spells — `Debug.Assert(cond)` is
`[DoesNotReturnIf(false)] bool condition`. The statement after the call is narrowed by exactly what
the argument proved:

```n#
func require([DoesNotReturnIf(false)] condition: bool, message: string) {
    if !condition {
        throw new ArgumentException(message)
    }
}

func lengthOf(text: string?): int {
    require(text != null, "text is required")
    return text.Length          // `text` is `string` from here on
}
```

`[DoesNotReturn]` on the whole signature is the unconditional form: a call to such a member ends the
path it is written on, so a value function may end in one and a statement after one is dead code.
See [Functions](functions.md#a-signature-that-never-returns).

### A narrowed `T?` is read as its `T`

Narrowing is not only a type-check: the compiler emits `Nullable<T>.Value` at the narrowed read, so
arithmetic, a return, an argument, an annotated local and a member of a `?`-lifted tuple all run on
the unwrapped value.

```n#
func addOne(value: int?): int {
    if value == null {
        return 0
    }

    return value + 1                    // the narrowed read, as an `int`
}

func lineOf(found: (Uri: string, Line: int)?): int {
    if found == null {
        return -1
    }

    return found.Line                   // the tuple's own element, past the unwrap
}
```

Writing to the name ends the narrowing, and so does a loop body that writes it — the next iteration
sees whatever the last one left. The four shapes that lower the nullable *themselves* —
`value == null`, `value ?? 0`, `value.HasValue`, `value.Value` — keep the `Nullable<T>` and stay
legal on a narrowed name.

**A narrowed property PATH is narrowed the same way.** `h.Slot` is a nullable the flow can prove,
so `h.Slot.Value` past a guard is the unwrap and `h.Slot.GetValueOrDefault()` is the nullable's own
member, exactly as they are for a narrowed local. Writing any prefix of the path ends it.

```n#
class Holder {
    Slot: int?
}

func slotOrMinusOne(h: Holder): int {
    if h.Slot == null {
        return -1
    }

    return h.Slot.Value + 1             // the unwrap, then the narrowed read
}
```

### A generic member's nullability follows its type argument

When you read a member of a constructed generic whose declared type is a bare type parameter, the
answer's nullability is the **type argument's** — not "maybe, because a `T` could be anything":

```n#
func Describe(box: Lazy<string>, pending: Task<string>): int {
    // `Lazy<T>.Value` and `Task<T>.Result` are declared `T`, and the argument is `string`.
    return box.Value.Length + pending.Result.Length
}

func DescribeNullable(box: Lazy<string?>): int {
    // Here the argument is `string?`, so the guard is required.
    value := box.Value
    if value == null {
        return 0
    }

    return value.Length
}
```

The same rule reaches lambda parameters — the parameter of a `Predicate<string>` is `string`, so
`items.FindAll(s => s.Length > 0)` needs no check inside the lambda.

A member that annotates the position itself keeps its `?` through the substitution, however
non-nullable the argument is:

```n#
func FirstLongWord(items: List<string>): string {
    // `List<T>.Find` returns `T?`, so this needs a check even though the argument is `string`.
    found := items.Find(s => s.Length > 2)
    return found ?? ""
}
```

`Enumerable.First` follows the argument; `Enumerable.FirstOrDefault`, `Enumerable.LastOrDefault`,
`List<T>.Find` and a `Dictionary<K, V>.TryGetValue` `out` value are all annotated and stay maybe-null.

### `T?` on a type parameter is an annotation, and a value argument erases it

That `?` is a **reference** annotation. It says "may be the default", it has no runtime form, and a
value type substituting the parameter erases it — so the same `FirstOrDefault` that is maybe-null
over a `List<string>` is a plain `DateTime` over a `List<DateTime>`:

```n#
func LatestYear(moments: List<DateTime>): int {
    // `DateTime` is a value type, so the `?` is gone: there is no absent value to guard, and an
    // empty list answers `default(DateTime)`.
    return moments.LastOrDefault().Year
}

func LatestWord(words: List<string>): string {
    // `string` is a reference type, so the `?` stays and the guard is required.
    found := words.LastOrDefault()
    return found ?? ""
}
```

**Your own generic functions and types spell the same two things.** An unconstrained `T?` is that
annotation; `where T : struct` is a real `Nullable<T>`:

```n#
func FirstOrDefaultOf<T>(items: T[]): T? {
    if items.Length > 0 {
        return items[0]
    }

    return default                       // `default`, not `null` — `T` may be a value type
}

func FirstOrAbsent<T>(items: T[]): T? where T : struct {
    if items.Length > 0 {
        return items[0]
    }

    return null                          // a real `Nullable<T>`, so `null` is one of its values
}

func firstNumber(values: int[]): int {
    found := FirstOrAbsent(values)       // int? — the constraint made it a real Nullable<int>
    if found == null {
        return -1
    }

    return found.Value
}

Inside such a declaration the parameter's own `T?` has `Nullable<T>`'s full surface, because the
`where` clause is what says it is one:

```n#
func presenceOf<T>(a: T?): bool where T : struct {
    return a.HasValue                    // and `a.GetValueOrDefault()`, and `a.Value` past a guard
}
```

func Count(values: int[]): int {
    return FirstOrDefaultOf(values)      // int — the annotation erased
}

func Name(names: string[]): string {
    return FirstOrDefaultOf(names) ?? "" // string? — the annotation survived
}
```

Passing `null` to an unconstrained `T?` parameter that a value argument has closed is an error, for
the same reason: the parameter is an `int`, and `null` is not one.

## Type Aliases

Create transparent type aliases (interchangeable with the underlying type):

```n#
type UserId = int
type StringDict = Dictionary<string, string>
type Callback = Func<void>
```

Type aliases are compile-time only — they do not create a distinct runtime type.

## Newtypes (Branded Types)

Create **distinct wrapper types** that prevent accidental type confusion:

```n#
type UserId = newtype int
type OrderId = newtype int
type Email = newtype string
```

Unlike type aliases, newtypes are **not interchangeable** with their underlying type:

```n#
id := UserId(42)           // Call-style construction
let other = new UserId(7)  // `new` form is equivalent
let raw: int = id.Value    // Explicit unwrapping

// These are compile errors:
// let x: int = id          // ERROR: UserId is not int
// let y: UserId = 42       // ERROR: int is not UserId
// let z: OrderId = id      // ERROR: UserId is not OrderId
```

Newtypes emit concrete `readonly record struct` wrappers for .NET interop, giving
public consumers value equality, `ToString()`, and familiar value semantics.

> **Construction:** Both the call-style shorthand `UserId(42)` and the explicit
> `new UserId(42)` are supported and produce identical IL.

## Complete Example

Here's a complete example demonstrating various type features:

```n#
import System
import System.Linq
import System.Collections.Generic

package TypesExample

// Enum
enum Status {
    Active = "active",
    Inactive = "inactive"
}

// Duck interface
duck interface IIdentifiable {
    Id: Guid { get; }
}

// Record
record Address {
    Street: string
    City: string
    State: string
    ZipCode: string
}

// Class with primary constructor
class Person(id: Guid, name: string, age: int) : IIdentifiable {
    Id: Guid = id
    Name: string = name
    Age: int = age
    Address: Address?

    func describe(): string =>
        $"{Name}, {Age} years old (ID: {Id})"
}

// Union
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

// Generic class with constraints
class Repository<T> where T : IIdentifiable {
    items: List<T> = new List<T>()

    func Add(item: T) {
        items.Add(item)
    }

    func GetById(id: Guid): Result<T> {
        found := items.FirstOrDefault(i => i.Id == id)
        return match found {
            null => new Result.Failure<T> { error: "Not found" },
            _ => new Result.Success<T> { value: found }
        }
    }
}

func main() {
    // Create a repository
    repo := new Repository<Person>()

    // Create a person
    person := new Person(Guid.NewGuid(), "Alice", 30) {
        Address: new Address {
            Street: "123 Main St",
            City: "New York",
            State: "NY",
            ZipCode: "10001"
        }
    }

    // Add to repository
    repo.Add(person)

    // Retrieve and match
    result := repo.GetById(person.Id)
    match result {
        Result.Success { value: p } => {
            Console.WriteLine($"Found: {p.describe()}")
            if p.Address != null {
                Console.WriteLine($"Lives in: {p.Address.City}")
            }
        },
        Result.Failure { error: e } => {
            Console.WriteLine($"Error: {e}")
        }
    }
}
```

## Next Steps

- **[Pattern Matching](pattern-matching.md)** - Deep dive into pattern matching with unions and more
- **[Functions Guide](functions.md)** - Learn about functions, lambdas, and async

## Resources

- [Project README](https://github.com/schneidenbach/nsharplang/blob/main/README.md)
- [Examples](/examples/)
