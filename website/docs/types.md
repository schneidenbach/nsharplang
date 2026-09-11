---
sidebar_label: Types
title: Types
---

# Types in N#

This guide covers the type system in N#, including classes, structs, records, discriminated unions, duck interfaces, and enums.

## Table of Contents

- [Basic Types](#basic-types)
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

// Deconstruction
(first, last, age) := person
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
  Arrays of your own types, of reference types and of the primitive types are unaffected. The same
  limit applies to an array of an external generic closed over your own type parameter
  (`List<T>[]`); `T[]` itself is unaffected.
- A **COLLECTION whose element is an array of one of your own types** — `List<Plain[]>`,
  `Dictionary<string, Plain[]>` — is not admitted; the collection lowerings keep a narrower element
  rule than the general one. `Plain[]` as an ordinary generic argument (`Func<Plain[], bool>`) is
  unaffected, and so is `Plain[]` itself.
- **Implementing `IEnumerable<T>` on your own class** compiles, but the emitted type cannot be
  loaded: `IEnumerable<T>` inherits the non-generic `IEnumerable.GetEnumerator()`, which differs from
  the generic one only by return type, and N# has no explicit interface implementation to spell it.
  This is not specific to your own type argument — `class Bag: IEnumerable<int>` has the same
  problem. Return `IEnumerable<T>` from a method instead of implementing it.
- A **lambda assigned to a delegate FIELD inside a constructor** is not emitted, for any delegate
  (`Func<int, bool>` too). Build it in a local, or return it from a function.
- A **generic method an `interface` declares** — `interface IHas { func Get<T>(): T }` — is not
  compiled yet. A generic method on a `class`, `struct` or `record` is unaffected.
- A method type parameter mentioned **only in a delegate's RESULT** is not inferred from the
  lambda's body: `outcome.Match(v => v.ToString(), e => e)` needs `Match<string>(...)` written out.
  The same limit applies to a generic FREE function with a `Func<TValue, TResult>` parameter.

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

### Null-conditional Operator

```n#
user: User? = GetUser()
name := user?.Name  // null if user is null

// Chaining
city := user?.Address?.City
```

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
