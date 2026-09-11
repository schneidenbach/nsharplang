---
sidebar_label: Language Tour
title: Language Tour
---

# N# Language Tour

This tour covers every major feature of N# with runnable examples. Each section is a short explanation followed by code you can paste into a `.nl` file and run.

## Variables

N# has three ways to declare variables: short declaration (`:=`), explicit type, and immutable binding (`let`).

```n#
// Type inference — the compiler figures out the type
name := "Alice"          // string
age := 30                // int
price := 19.99           // double
active := true           // bool

// Explicit type annotation
count: long = 1000000
greeting: string = "Hi"

// Immutable binding — cannot be reassigned
let pi: double = 3.14159
let maxRetries := 3
```

## Functions

Functions use the `func` keyword. Parameters are `name: type`, return type comes after the parameter list.
If a function returns a value, declare the return type. No return type means `void`.

```n#
func add(a: int, b: int): int {
    return a + b
}

// No return type needed for void functions
func greet(name: string) {
    print $"Hello, {name}!"
}

// Expression-bodied functions
func double(x: int): int => x * 2

// Default parameters
func connect(host: string, port: int = 8080): string {
    return $"{host}:{port}"
}

func main() {
    result := add(3, 5)
    print result             // 8

    greet("World")           // Hello, World!
    print double(21)         // 42
    print connect("localhost")  // localhost:8080
}
```

### Function Overloading

Declare multiple functions with the same name but different parameter lists. The compiler
resolves the call by argument count and types.

```n#
func area(side: int): int => side * side
func area(width: int, height: int): int => width * height

func main() {
    print area(5)       // 25
    print area(3, 4)    // 12
}
```

## Types

### Classes

Classes are the primary type construct. Visibility is convention-based: PascalCase = exported/public, camelCase = unexported/private-by-convention.

```n#
class Person {
    Name: string         // exported/public (PascalCase)
    age: int             // unexported/private-by-convention (camelCase)

    constructor(name: string, age: int) {
        Name = name
        this.age = age
    }

    func Greet(): string {
        return $"Hi, I'm {Name}"
    }
}

func main() {
    p := new Person("Alice", 30)
    print p.Greet()     // Hi, I'm Alice
    print p.Name        // Alice
}
```

### Inheritance: `abstract`, `virtual` and `override`

A class may derive from one other class, listed after a colon. Members are **not** virtual by default,
exactly as in C#: a base class opts a member into being replaceable with `virtual` (it supplies a body)
or `abstract` (it supplies none), and a subclass replaces it with `override`.

```n#
abstract class Shape {
    readonly name: string

    constructor(name: string) {
        this.name = name
    }

    Name: string => name

    abstract func Area(): int          // no body — every concrete subclass must supply one

    virtual func Describe(): string {  // a body a subclass MAY replace
        return "a shape"
    }
}

class Square: Shape {
    readonly side: int

    constructor(side: int) : base("square") {
        this.side = side
    }

    override func Area(): int {
        return side * side
    }

    sealed override func Describe(): string {   // no further subclass may replace this
        return "a square"
    }
}
```

A class with any `abstract` member must itself be `abstract`, and an abstract class cannot be
constructed — `new Shape("x")` is an error. An abstract class may sit anywhere in the chain, overriding
some inherited members and leaving others for its own subclasses:

```n#
abstract class Rounded: Shape {
    constructor() : base("rounded") {
    }

    override func Describe(): string {
        return "something round"
    }
    // `Area` stays abstract — `Rounded` is abstract, so it need not supply one.
}
```

Source order does not matter: a subclass may be written above its base in the same file, or in a
different file of the same project.

Generic classes take part in all of this. A generic class may derive from a non-generic base, a generic
class may close a generic base over a concrete type, and a generic class may pass its own type parameter
through to a generic base:

```n#
abstract class Box<T> {
    abstract func Render(): string
}

class StringBox: Box<string> {          // closes the base over a concrete type
    override func Render(): string {
        return "a string"
    }
}

class PairBox<T>: Box<T> {              // passes its own type parameter through
    override func Render(): string {
        return "a pair"
    }
}
```

#### `base.` — the implementation you replaced

An `override` that wants to *extend* the base's behaviour rather than discard it reaches it with
`base.`. The lookup starts at the base class, so the override does not answer itself, and the call is
dispatched **non-virtually** — which is the only thing that makes `base.Render()` inside `Render`
terminate:

```n#
class Middle: Layer {
    override func Render(): string {
        return "middle(" + base.Render() + ")"       // "middle(root)"
    }
}

class Leaf: Middle {
    override func Render(): string {
        return "leaf(" + base.Render() + ")"         // "leaf(middle(root))"
    }
}
```

`base.` is not limited to overrides — any instance member may use it — and it reads properties as well
as calling methods:

```n#
class Dog: Animal {
    func BaseName(): string {
        return base.Name                             // the base's property, not the subclass's
    }
}
```

The base may be a class declared in the same project, one from the BCL or a NuGet package, or
`System.Object` itself when no base is written (`base.ToString()` answers the runtime type's name). A
constructor chains to a base constructor with `: base(...)` in its header, which is the same idea in the
one place a member call cannot express it.

What `base.` may **not** do is appear in the arguments of that header. `base` is the same reference
`this` is — it only changes which declaration a name binds to and how a call dispatches — so reading
through it before the base constructor has run would read storage that does not exist yet:

```n#
class Derived: Base {
    constructor(): base(base.Value) {}                // rejected: no instance exists yet
}
```

`this.Value`, a bare field name, and an instance call in a chain argument are rejected for the same
reason. Compute the value from the constructor's own parameters, or from a `static` helper.

**Diagnostics.** The compiler holds you to C#'s rules:

| You wrote | You get |
| --- | --- |
| a concrete class that does not implement an inherited abstract member | [NL324](./errors/NL324.md) |
| `new` on an abstract class | [NL803](./errors/NL803.md) |
| `override` with no base member of that name, or a base member that is not `virtual`/`abstract`/`override` | [NL311](./errors/NL311.md) |
| `base.Member` where the base class has no such member | [NL303](./errors/NL303.md) |
| `this` or `base` in a `static` member or a top-level function | [NL327](./errors/NL327.md) |

Overriding a member of an **external** base class — one from the BCL or a NuGet package — works the same
way and needs no extra ceremony:

```n#
class LengthComparer: StringComparer {
    override func Compare(x: string, y: string): int {
        return x.Length - y.Length
    }
}
```

### Primary Constructors

For simple types, put constructor parameters directly on the type declaration.

```n#
class Logger(name: string) {
    func Log(message: string) {
        print $"[{name}] {message}"
    }
}

struct Point(x: double, y: double) {
    func Distance(): double {
        return Math.Sqrt(x * x + y * y)
    }
}

record Person(name: string, age: int) {
    FullInfo: string => $"{name}, age {age}"
}
```

### Records

Records are immutable data types with value equality. Use `with` to create modified copies.

```n#
record Point {
    X: int
    Y: int
}

func main() {
    p1 := new Point { X: 10, Y: 20 }
    p2 := p1 with { X: 30 }       // p1 is unchanged, p2 has X=30

    print $"p1: ({p1.X}, {p1.Y})"  // p1: (10, 20)
    print $"p2: ({p2.X}, {p2.Y})"  // p2: (30, 20)
}
```

### Structs

Structs are value types — allocated on the stack, copied by value. Use for small data.

```n#
struct Rectangle {
    Width: double
    Height: double

    func Area(): double {
        return Width * Height
    }
}
```

### Readonly Structs

Mark a struct `readonly` when none of its instance state changes after construction. The compiler
holds you to the promise — every instance field must be declared `readonly` — and in exchange it
puts `IsReadOnlyAttribute` on the emitted type, which is what lets callers pass the value around
without defensive copies.

```n#
readonly struct Point {
    readonly X: double
    readonly Y: double

    constructor(x: double, y: double) {
        X = x
        Y = y
    }

    func Distance(): double => Math.Sqrt(X * X + Y * Y)
}
```

The modifier works on generic structs, on `ref struct` and on `record struct`, and modifier order
is free — `public readonly struct` and `readonly public struct` mean the same thing:

```n#
readonly struct Box<T> {
    readonly Value: T

    constructor(value: T) {
        Value = value
    }
}

readonly ref struct Window {
    readonly Start: int
    readonly Length: int

    constructor(start: int, length: int) {
        Start = start
        Length = length
    }
}

readonly record struct Pair {
    readonly Left: int
    readonly Right: int

    constructor(left: int, right: int) {
        Left = left
        Right = right
    }
}
```

`static` and `const` fields are unaffected — they are not instance state — and a primary
constructor's captured parameters become readonly fields automatically:

```n#
readonly struct Counted(total: int, seen: int) {
    static Instances: int = 0        // fine: not instance state

    func Remaining(): int => total - seen
}
```

Two things are **not** readonly structs and are never treated as one:

- A plain `struct` that happens to have `readonly` fields. It stays a mutable struct.
- A `class`, `record`, `interface` or `enum`. Those cannot carry the word at all
  ([NL311](./errors/NL311.md)); mark their fields `readonly` individually instead.

A mutable instance field inside a `readonly struct` is [NL326](./errors/NL326.md); assigning to a
readonly field outside a constructor is [NL309](./errors/NL309.md).

## Unions

Discriminated unions let you define a type that can be one of several cases. The compiler enforces exhaustive matching.

```n#
union Result {
    Success { value: int }
    Failure { error: string, code: int }
}

func ProcessResult(r: Result): string {
    return match r {
        Result.Success { value } => $"Got: {value}",
        Result.Failure { error, code } => $"Error {code}: {error}"
    }
}

func main() {
    ok := new Result.Success(42)
    print ProcessResult(ok)          // Got: 42

    err := new Result.Failure("Not found", 404)
    print ProcessResult(err)         // Error 404: Not found
}
```

## Pattern Matching

The `match` expression supports many pattern types. The compiler checks that all cases are covered.

```n#
import System

// Literal and relational patterns
func classify(n: int): string {
    return match n {
        0 => "zero",
        x when x > 0 => "positive",
        _ => "negative"
    }
}

// List patterns
func describeList(numbers: int[]): string {
    return match numbers {
        [] => "empty",
        [single] => $"one item: {single}",
        [first, .., last] => $"first: {first}, last: {last}",
        _ => "other"
    }
}

// Union patterns with guards
union HttpResponse {
    Ok { statusCode: int, body: string }
    ClientError { statusCode: int, message: string }
    ServerError { statusCode: int, details: string }
}

func handleResponse(resp: HttpResponse): string {
    return match resp {
        HttpResponse.Ok { statusCode, body } when statusCode == 200 => $"Success: {body}",
        HttpResponse.Ok { statusCode, body } => $"OK ({statusCode}): {body}",
        HttpResponse.ClientError { statusCode, message } when statusCode == 404 => "Not found!",
        HttpResponse.ClientError { statusCode, message } => $"Client error: {message}",
        HttpResponse.ServerError { statusCode, details } => $"Server error: {details}"
    }
}
```

## Interfaces

### Regular Interfaces

Regular interfaces require explicit implementation with `:` syntax. They support default implementations.

```n#
interface IShape {
    func GetArea(): double

    func Describe(): string {
        return $"Area: {GetArea()}"
    }
}

class Circle : IShape {
    Radius: double

    constructor(radius: double) {
        Radius = radius
    }

    func GetArea(): double {
        return 3.14159 * Radius * Radius
    }
}
```

### Duck Interfaces

Duck interfaces use structural typing — any type that has the right methods automatically satisfies the interface, without declaring it.

```n#
duck interface IReader {
    func Read(): string
}

// No ": IReader" needed — FileReader matches the shape
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
    print reader.Read()
}

func main() {
    processReader(new FileReader())   // file contents
    processReader(new HttpReader())   // http contents
}
```

## Enums

### String Enums

String enums map enum members to string values, so status names stay typed instead of copied as `const string` sets. Annotate the backing type with `: string`.

```n#
enum Status: string {
    Pending = "pending",
    Active = "active",
    Done = "done"
}

func main() {
    status := Status.Active
    print status    // active
}
```

### Int Enums

Standard integer enums emit CLR enum values.

```n#
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2
}
```

## Error Handling

### Try/Catch

N# supports standard try/catch/finally:

```n#
import System

func main() {
    try {
        result := int.Parse("not a number")
    } catch ex: FormatException {
        print $"Parse error: {ex.Message}"
    }
}
```

### Tuple Error Capture

N# has a Go-inspired pattern: assign both the result and error in one line. If the function throws, the error variable captures the exception instead of crashing.

```n#
import System

func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception("Cannot divide by zero")
    }
    return a / b
}

func main() {
    // Captures exception instead of throwing
    result, err := Divide(10, 0)
    if err != null {
        print $"Error: {err.Message}"   // Error: Cannot divide by zero
    } else {
        print $"Result: {result}"
    }

    // Discard the result, just check for error
    _, err2 := Divide(5, 0)
    print err2 != null   // True
}
```

**Performance:** The success path of `result, err :=` is exception-free at runtime. The
compiler lowers the pattern to a value carrier (`err`, initialized to `null`) plus a single
exception-capture region; when the call does not throw, the catch is never entered and no
exception is thrown or unwound — the cost is essentially the call plus a null check. A CLR
exception is only paid on the failure path, when the call actually throws and `err` captures
it. This keeps ordinary `(result, err)` control flow off the expensive exception path.

## Async/Await

Async functions are declared with `async func`. The return type is automatically wrapped in `Task` or `ValueTask`.

```n#
import System.Threading.Tasks

async func fetchData(): string {
    await Task.Delay(100)
    return "data loaded"
}

async func main() {
    result := await fetchData()
    print result   // data loaded
}
```

### Async Streams

Use `async func*` for async iterators and `await foreach` to consume them.

```n#
import System
import System.Collections.Generic
import System.Threading.Tasks

async func* getNumbersAsync(): IAsyncEnumerable<int> {
    for i := 0; i < 5; i++ {
        await Task.Delay(100)
        yield i
    }
}

async func main() {
    await foreach num in getNumbersAsync() {
        print $"Got: {num}"
    }
}
```

## Collections and LINQ

N# uses array literals and has full access to LINQ through `System.Linq`.

```n#
import System.Linq

func main() {
    numbers := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    // LINQ
    evens := numbers.Where(x => x % 2 == 0).ToList()
    doubled := numbers.Select(x => x * 2).ToList()
    sum := numbers.Sum()

    print $"Evens: {string.Join(", ", evens)}"       // 2, 4, 6, 8, 10
    print $"Sum: {sum}"                               // 55

    // Ranges and indexing
    slice := numbers[2..5]
    last := numbers[^1]
    print $"Slice: {string.Join(", ", slice)}"        // 3, 4, 5
    print $"Last: {last}"                              // 10

    // For-each loop
    for num in doubled {
        print num
    }
}
```

## Generics

N# generics use `<T>` syntax with full constraint support.

```n#
import System

class Stack<T> {
    items: T[] = []
    Count: int => items.Length

    func Push(item: T) {
        items = [..items, item]
    }

    func Pop(): T {
        if items.Length == 0 {
            throw new Exception("Stack is empty")
        }
        result := items[^1]
        items = items[..^1]
        return result
    }
}

func CreateList<T>(params items: T[]): T[] {
    return items
}

func main() {
    stack := new Stack<int>()
    stack.Push(1)
    stack.Push(2)
    stack.Push(3)
    print stack.Pop()   // 3
}
```

### Members typed by a generic over your own type parameter

A member's type may be any generic — a collection, a dictionary, a delegate, an interface — closed
over the declaring type's own type parameter. Nullable annotations compose with all of them.

```n#
import System
import System.Collections.Generic

class Registry<T> {
    items: List<T> = []
    byName: Dictionary<string, T> = [:]
    onAdded: Action<T>?               // may be absent
    readonly accept: Func<T, bool>

    constructor(accept: Func<T, bool>) {
        this.accept = accept
    }

    func Add(name: string, item: T): bool {
        allowed := accept
        if !allowed(item) {
            return false
        }

        items.Add(item)
        byName[name] = item

        listener := onAdded
        if listener != null {
            listener(item)
        }
        return true
    }
}
```

`Action<T>?` and `Action<T>` are the *same* CLR type: in N#, as in C#, a nullable annotation on a
reference type is a fact the compiler tracks about the value, not a different type in metadata.
`Registry<int>` emits `onAdded` as `Action<int>` and `Registry<string>` emits it as `Action<string>`.

A method-level type parameter works the same way:

```n#
func FirstMatch<T>(items: List<T>, accept: Func<T, bool>, fallback: T): T {
    for item in items {
        chooser := accept
        if chooser(item) {
            return item
        }
    }
    return fallback
}
```

### Calling a delegate

`d(args)` and `d.Invoke(args)` are the same call — `Invoke` is an ordinary instance method of the
delegate's own type — and either spelling works wherever the delegate is held: a local, a parameter,
a captured variable, or a **field**:

```n#
class Pipeline<T> {
    readonly accept: Func<T, bool>
    onEach: Action<T>?

    constructor(accept: Func<T, bool>) {
        this.accept = accept
    }

    func Run(item: T): bool {
        if !accept(item) {              // straight off the field
            return false
        }

        this.accept.Invoke(item)        // the same call, written out
        onEach?.Invoke(item)            // and only if there is a listener
        return true
    }
}
```

A **method beats a delegate field of the same name**: if the type declares both a `Handle` method and
a `Handle` delegate field, `Handle(1)` is the method. Reach the field through `.Invoke` when you mean
the delegate.

### Calling something only when it is there

`receiver?.Member(args)` evaluates the receiver **once**, and skips the call entirely when it is
null — the member is not reached at all, not reached and ignored. It is the shape a hand-written
guard produces, without the local:

```n#
current := onEach
current?.Invoke(item)                   // exactly: if current != null { current.Invoke(item) }
```

The result follows C#'s rule. A `void` member leaves nothing behind; a reference-typed one answers
`null` when skipped; and a non-nullable value-typed one is **lifted to `T?`**, because "skipped" has
to be representable:

```n#
count: int? = counter?.Read()           // int? — null when `counter` is null
label: string? = counter?.Describe()    // string? for the same reason
```

**What is not supported yet.** The receiver must be a reference type, the `?.` must be followed by a
call (`a?.B` as a plain read is not yet lowered), and no further link may follow it in the same
chain — `a?.M().B` and `a?.B[0]` are refused rather than compiled, because a link written after a
`?.` must be skipped along with it and that lowering is not in place. Write the guard by hand for
those.

### Passing storage with `ref` and `out`

A `ref` or `out` argument passes the **caller's storage** rather than a value, so a write inside the
callee lands where the caller can see it. The storage may be a local, a parameter, or a **field** —
including one reached through `this.`:

```n#
import System.Threading

class Counter {
    count: int
    text: string?

    static func Fill(ref target: int, value: int) {
        target = value
    }

    func Reset(value: int) {
        Fill(ref count, value)               // a field's address
    }

    func Parse(input: string): bool {
        return int.TryParse(input, out count)
    }

    func Claim(): string? {
        return Interlocked.Exchange(ref text, null)
    }
}
```

The spelling is part of the call: `f(x)` and `f(ref x)` are different calls even when `x` has the
same type, and only the second binds a `ref` parameter. The element type is **exact** — a by-ref
argument aliases your storage, so `ref int` does not feed a `ref long` the way an ordinary `int` feeds
a `long` parameter.

A generic method infers its type argument from the by-ref position like any other:
`Interlocked.Exchange(ref remove, null)` binds `T` to the field's own type, and the `null` — which
carries no type of its own — converts to it.

**Not yet supported:** a `ref` argument that names a `static` field, or a composed target such as an
array element or a nested member chain. Copy to a local, pass `ref` to that, and write it back.

### Static members of a constructed generic type

Write the closed type and then the member: `Vector<int>.Count`, `EqualityComparer<string>.Default`.
The type arguments are part of the receiver, so each constructed type answers with its own
substituted member types — `Vector<int>.Zero` is a `Vector<int>` and `Vector<byte>.Zero` is a
`Vector<byte>`.

```n#
import System.Collections.Generic
import System.Numerics

func Lanes(): int {
    return Vector<int>.Count
}

func SameString(left: string, right: string): bool {
    return EqualityComparer<string>.Default.Equals(left, right)
}

func Sorted(): int {
    return Comparer<string>.Default.Compare("a", "b")
}
```

Nested, array, nullable and namespace-qualified spellings all work —
`EqualityComparer<Dictionary<string, List<int>>>.Default`, `Comparer<int[]>.Default`,
`System.Numerics.Vector<int>.Count` — and a receiver written with the wrong number of type
arguments is reported at the receiver rather than silently accepted:

```n#
func Wrong(): int {
    return Vector<int, int>.Count
    // NL207: Generic type 'Vector' takes 1 type argument(s), but 2 were provided
}
```

**The `<` is only a type-argument list when a `.` follows the matching `>`.** Everything else is
still a comparison, including the shapes that look most like one:

```n#
func Between(value: int, lower: int, upper: int): bool {
    return lower < value && value > upper   // two comparisons, not a receiver
}

func Shorter(value: int, values: int[]): bool {
    return value < values.Length            // a comparison against a member access
}
```

The same spelling reaches your own generic types; the next section is about declaring their static
members.

### Static members of your own generic types

A generic type carries static fields, properties, methods, operators and conversion operators, and
the declaration is written once with the type's own parameters in scope. The CLR gives **every
constructed type its own static storage**: `PerTypeState<int>` and `PerTypeState<string>` are two
different counters behind one declaration.

```n#
class PerTypeState<T> {
    static Count: int

    static Current: int => Count

    static func Increment(): int {
        Count = Count + 1
        return Count
    }
}

func main() {
    print PerTypeState<int>.Increment()      // 1
    print PerTypeState<int>.Increment()      // 2
    print PerTypeState<string>.Increment()   // 1 — its own slot
    print PerTypeState<int>.Count            // 2
}
```

A static method may name the type's parameters in its signature and call the type's own
constructor — including a private one, which is how a factory-only type is written:

```n#
struct Box<T> {
    Value: T

    private constructor(value: T) {
        Value = value
    }

    static func Create(value: T): Box<T> {
        return new Box<T>(value)
    }

    static func unwrap(source: Box<T>): T {
        return source.Value
    }

    func Copy(): Box<T> {
        return Create(unwrap(this))
    }
}

func main() {
    print Box<int>.Create(42).Value      // 42
    print Box<string>.Create("hi").Value // hi
}
```

Inside the type, a static member is named without a qualifier from any body the type owns — a static
one, as `Count = Count + 1` above, or an instance one, as `Create(unwrap(...))` here. Both resolve
against the **current instantiation**, so `Box<int>.Copy` calls `Box<int>.Create`.

Operators and conversion operators are static members too, so they follow the same rule. A
conversion operator declared on a generic type is the one that can only be written on the type being
converted **to** — the other end is whatever the instantiation supplies, and `int` declares nothing
about `Wrap`:

```n#
struct Wrap<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    implicit operator Wrap<T>(value: T) => new Wrap<T>(value)

    explicit operator T(wrapped: Wrap<T>) => wrapped.Value
}

struct Tagged<T> {
    Tag: int

    constructor(tag: int) {
        Tag = tag
    }

    static func operator ==(left: Tagged<T>, right: Tagged<T>): bool => left.Tag == right.Tag
    static func operator !=(left: Tagged<T>, right: Tagged<T>): bool => left.Tag != right.Tag
}

func main() {
    wrapped: Wrap<int> = 5           // implicit — no cast
    print wrapped.Value              // 5
    print (int)wrapped               // 5 — explicit, cast required
    print new Tagged<int>(1) == new Tagged<int>(1)   // true
}
```

A member the constructed type does not have is reported under the name you wrote:
`Box<int>.Missing(42)` is `NL303` naming `Box<int>`, and a wrong argument type names the
**substituted** parameter type — `Box<int>.Create("text")` says the parameter is `int`, not `T`.

### Generic methods on your own types

A `class`, `struct` or `record` may declare a generic method, whether or not the type itself is
generic. The method's type parameters are **its own** — separate from the declaring type's,
constrained separately, and emitted as real CLR method type parameters, so the method is a generic
method to C# and every other .NET language too.

```n#
struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    // `U` has nothing to do with the box's `T`.
    static func Of<U>(value: U): Box<U> {
        return new Box<U>(value)
    }

    // A signature may name BOTH scopes.
    func Map<TResult>(f: Func<T, TResult>): Box<TResult> {
        return new Box<TResult>(f(Value))
    }

    func Is<TOther>(): bool {
        return Value is TOther
    }
}

class Plain {
    func Echo<T>(value: T): T => value

    static func Wrap<T>(value: T): Box<T> => new Box<T>(value)
}

func main() {
    box := new Box<int>(3)
    plain := new Plain()

    print box.Map<string>(v => v.ToString()).Value   // "3" — type argument written
    print box.Is<int>()                              // true
    print plain.Echo(7)                              // 7 — inferred
    print Plain.Wrap(5).Value                        // 5 — inferred, static
    print Box<int>.Of(4).Value                       // 4 — on a constructed owner
}
```

A static generic method on a GENERIC owner is reached through an instantiation, so write the owner
out — `Box<int>.Of(4)` — everywhere except inside the declaring type's own code, where the
instantiation is the type's own.

Constraints are written as they are on a type, and are checked at the call site:

```n#
class Registry {
    static func Register<T>(value: T): bool where T : class => value != null
}
```

Two rules about the type-argument list itself. It is **all or nothing** — `Pick<int>(1, "a")`
against `Pick<TFirst, TSecond>` is `NL207`, and so is writing a list on a method with no type
parameters — and a method's type parameter may **not reuse a name its declaring type binds**
(`struct Box<T> { func Shadow<T>() }` is `NL316`, because inside the member only the inner `T` would
mean anything).

Two shapes are not compiled yet: a generic method declared by an **`interface`**, and inferring a
type parameter that appears **only in a delegate's result** from the lambda's body — write
`Match<string>(...)` rather than `Match(...)` for that one.

### A name and a type-parameter count together are one type

A type's identity on the CLR is its name **and** how many type parameters it declares, so a
non-generic type and a generic one of the same name are two different types and may be declared side
by side. This is the pattern a library reaches for when a generic type needs one non-generic root
that callers can hold uniformly:

```n#
class Subscription {
}

class Subscription<T>: Subscription {
    Value: T

    constructor(value: T) {
        Value = value
    }
}

func Make(): Subscription {
    return new Subscription<int>(7)   // the generic one, held as its non-generic base
}
```

A reference selects the declaration whose type-parameter count it writes: `Subscription` is the
non-generic type and `Subscription<int>` the generic one. Writing a count that no declaration has is
an error (`NL207`) that names the counts that do exist.

Two declarations collide only when they share a name **and** a type-parameter count — `class Foo {}`
twice, `class Foo<T>` twice, or a `class Foo<T>` beside a `struct Foo<U>` — and that is `NL306`.

In metadata a generic type is named the way every other .NET language spells it, with a backtick and
its arity: `Subscription` stays `Subscription`, `Subscription<T>` is emitted as ``Subscription`1``
and `Cell<TKey, TValue>` as ``Cell`2``. N# always shows you the written form — `Subscription<T>` — in
diagnostics, hovers and completions; the backtick name is what a C# consumer of your assembly sees,
and what `GetType().Name` returns at runtime.

## Properties: Required and Init-Only

Mark a property `required` to force callers to set it in the object initializer, and `init`
to make it settable only during construction (immutable afterward). `required init`
combines both.

```n#
class Product {
    required init Id: int      // must be set, immutable after creation
    init Name: string          // optional, immutable after creation
    Price: double = 0.0        // mutable

    func Describe(): string => $"#{Id} {Name} (${Price})"
}

func main() {
    p := new Product { Id: 1, Name: "Widget" }
    print p.Describe()   // #1 Widget ($0)
    // p.Id = 2          // compile error: init-only
}
```

## Indexers

Give a type `[]` access with an indexer. Declare it as `func this[key: K]: V` with `get`
and `set` accessors.

```n#
class Grid {
    storage: Dictionary<string, int> = new()

    func this[key: string]: int {
        get { return storage[key] }
        set { storage[key] = value }
    }
}

func main() {
    g := new Grid()
    g["score"] = 42
    print g["score"]    // 42
}
```

## Operator Overloading

Define operators on your own types with `static func operator <op>`. Comparison operators
must be defined in pairs (`==`/`!=`).

```n#
class Vec {
    X: int
    Y: int

    static func operator +(a: Vec, b: Vec): Vec => new Vec { X: a.X + b.X, Y: a.Y + b.Y }
    static func operator ==(a: Vec, b: Vec): bool => a.X == b.X && a.Y == b.Y
    static func operator !=(a: Vec, b: Vec): bool => !(a == b)
}

func main() {
    sum := (new Vec { X: 1, Y: 2 }) + (new Vec { X: 3, Y: 4 })
    print $"({sum.X}, {sum.Y})"   // (4, 6)
}
```

## Conversion Operators

Define `implicit` (always safe) and `explicit` (requires a cast) conversions between types.

```n#
struct Celsius {
    Value: double

    implicit operator Fahrenheit(c: Celsius) => new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }
    explicit operator Kelvin(c: Celsius) => new Kelvin { Value: c.Value + 273.15 }
}

struct Fahrenheit { Value: double }
struct Kelvin { Value: double }

func main() {
    boiling := new Celsius { Value: 100.0 }
    f: Fahrenheit = boiling       // implicit — no cast
    k := (Kelvin)boiling          // explicit — cast required
    print $"{f.Value}°F  {k.Value}K"   // 212°F  373.15K
}
```

A conversion operator is found on **either end** of the conversion — the type converted from or the
type converted to — which is what lets a wrapper declare its own inbound conversion. See
[static members of your own generic types](#static-members-of-your-own-generic-types) for the
generic form, `implicit operator Wrap<T>(value: T)`.

## Type Aliases

Create a transparent alias for a longer type — fully interchangeable with the underlying
type.

```n#
type UserId = int
type StringDict = Dictionary<string, string>
type Callback = Func<void>

func main() {
    id: UserId = 7
    print id    // 7
}
```

N# also has `newtype` for *distinct* branded types that are **not** interchangeable with
their underlying type (`type Email = newtype string`) — see the
[Types guide](types.md#newtypes-branded-types).

## Subscribing to .NET Events

Subscribe to a .NET event with `on` and detach with `off`. `on` returns a subscription handle
you can hold onto — unsubscribing a lambda just works, no need to stash the delegate.

```n#
import System

func main() {
    sub := on AppDomain.CurrentDomain.ProcessExit (sender, args) => {
        print "bye"
    }
    off sub        // detach again
}
```

`+=`/`-=` on an event is a compile error that points you to `on`/`off` (it used to compile and
then crash at runtime). On a real `Func`/`Action` field, `+=`/`-=` still combine/remove
delegates.

## Working With Nullable Values

Use `?` to mark a type nullable, and `must` to assert a nullable value is non-null,
unwrapping it (it throws if the value is actually null). N# does **not** have a
null-forgiving `!` operator — prefer explicit checks, `??`, or `must`.

```n#
func find(items: int[], target: int): int? {
    for i := 0; i < items.Length; i++ {
        if items[i] == target { return i }
    }
    return null
}

func main() {
    idx := must find([10, 20, 30], 20)   // unwrap int? -> int
    print idx                            // 1

    name: string? = "Ada"
    greeting := name ?? "stranger"       // null-coalescing
    print greeting                       // Ada
}
```

## Resource Management and Locking

`lock` takes a mutual-exclusion lock for a critical section (parentheses optional). Use it
to guard shared state across threads.

```n#
class Counter {
    count: int = 0
    sync: object = new object()

    func Increment() {
        lock sync {
            count++
        }
    }

    func Value(): int => count
}
```

The lockee must be a **reference type** — locking on a value type (`int`, a struct, an enum,
`int?`) is a compile-time error ([NL320](https://schneidenbach.github.io/nsharplang/docs/errors/NL320)). `Monitor`
locks on object identity, and a value would be boxed into a fresh object on every `lock`, so
the lock would guard nothing. The same applies to a generic `T` unless it is constrained to a
reference type (`where T: class`). Lock on a dedicated `object` field, as `Counter` does above.

Inside a `finally` block, control transfers that would leave the block — `return`, or
`break`/`continue` targeting a loop outside it — are compile-time errors
([NL319](https://schneidenbach.github.io/nsharplang/docs/errors/NL319)): the runtime must always finish running a
`finally`. `throw` is allowed, and loops opened inside the `finally` can still
`break`/`continue` normally.

## Checked and Unchecked Arithmetic

Control integer overflow behavior explicitly. `checked` throws `OverflowException` on
overflow; `unchecked` wraps (the .NET default).

```n#
func main() {
    max := 2147483647            // int.MaxValue
    print unchecked(max + 1)     // -2147483648 (wraps)

    try {
        print checked(max + 1)   // throws
    } catch ex: OverflowException {
        print "overflow caught"
    }
}
```

## Reflection Operators

`nameof` and `typeof` are compile-time operators. `typeof` resolves type names through the current
source scope, imports, aliases, and referenced assembly catalog. External classes, structs,
interfaces, enums, and closed generic types do not need a separate compiler allow-list; for example,
`typeof(Guid)`, `typeof(Math)`, and `typeof(Queue<int>)` use their resolved type identities.

```n#
class Person {
    Name: string = ""
}

func main() {
    print nameof(Person)        // Person
    print typeof(Person).Name   // Person
}
```

## File-Scoped Types

Mark a type `file` to keep it visible only within the file that declares it — useful for
internal helpers that should never leak into the public surface.

```n#
file class Helper {
    func Shout(s: string): string => s + "!"
}

func main() {
    print new Helper().Shout("hi")   // hi!
}
```

## Systems N#

For high-performance code, N# has an opt-in **systems profile** with explicit, checkable
runtime costs: `[hot]`/`[boundary]` effect contracts, allocation-free `Result<T,E>`, `alloc`
and `stackalloc`, `ref struct` and lifetime-checked spans, governed `unsafe`, and SIMD
auto-vectorization for counted-reduction kernels. See the dedicated
**[Systems N# guide](systems.md)**.

```n#
[hot]
func checksum(values: int[]): int {
    sum := 0
    len := values.Length
    for i := 0; i < len; i++ {
        sum = sum + values[i]
    }
    return sum
}
```

## Testing

Tests live in `.tests.nl` files next to the code they test. Use the `test` keyword and `assert` statements.

```n#
// Calculator.tests.nl
namespace MyApp

test "should add two numbers" {
    result := Calculator.Add(2, 3)
    assert result == 5
}
```

### Custom Assert Messages

Add a message after a comma to explain what the assertion checks:

```n#
test "should compute tax" {
    tax := Calculator.Tax(100)
    assert tax == 10, "tax on 100 should be 10"
}
```

### Assert Throws

Verify that code throws a specific exception:

```n#
test "should throw on divide by zero" {
    assert throws DivideByZeroException {
        Calculator.Divide(10, 0)
    }
}
```

### Table-Driven Tests

Run the same test body with multiple sets of inputs (Go-style). Each parameter is declared
`name: Type` after `with`, and each row supplies one literal value per parameter:

```n#
test "should add correctly" with (a: int, b: int, expected: int) [
    (1, 2, 3),
    (0, 0, 0),
    (-1, 1, 0),
    (100, -100, 0)
] {
    assert Calculator.Add(a, b) == expected
}
```

**Every row is its own test.** A row is not a loop iteration — it compiles to an independent test
that binds the row's values as locals of the declared types, so it runs, reports and fails on its
own. The four rows above are reported as four tests:

```text
should add correctly (1, 2, 3)
should add correctly (0, 0, 0)
should add correctly (-1, 1, 0)
should add correctly (100, -100, 0)
```

That name is the case's identity everywhere: `nlc test --verbose` prints it, `nlc test --json`
carries it as each result's `displayName`, and `--filter` matches against it. One bad row names
itself instead of hiding the other three behind a single failure.

Row values must be literals — `int`, `float`, `char`, `string`, `bool` or `null`. A computed
expression is reported as `NL310`, and a row whose value count does not match the parameter count is
reported as `NL202`.

### Skipping a Test

**There is no runnable skip.** N# parses a `skip "reason"` clause after a test's description for
forward compatibility, and the formatter and the editor tooling understand it, but no backend emits
it — so `nlc test` refuses a file that contains one:

```text
error NL323: test 'needs network' declares 'skip', which is parsed for forward compatibility but is not compiled by 'nlc test'
  --> Network.tests.nl:3:1
   |
  3 | test "needs network" skip "CI has no network" {
   | ^^^^
   |
help: Delete the skip clause and its reason, or comment out the whole test declaration — nlc test cannot report a skipped test.
```

To leave a test out of a run, comment out the whole declaration, or use `nlc test --filter` to
select the tests you want. A `skip` clause is not a way to keep an unfinished test in the file.

### Setup Blocks

Share setup code across all tests in a file. One `setup` block per file — runs before each test:

```n#
setup {
    store := new TaskStore()
    service := new TaskService(store)
}

test "should add task" {
    result := service.AddTask("Write tests", Priority.High, tags, "")
    assert result != null
}

test "should list tasks" {
    service.AddTask("Task 1", Priority.Low, tags, "")
    assert service.GetTasks().Count == 1
}
```

:::caution Not yet runnable
`setup` and `teardown` parse and are understood by the editor tooling, but `nlc test` does not yet
compile a file that contains one. Call the shared setup from inside each test until they land.
:::

### Smart Assert Patterns

The compiler maps common assert patterns to XUnit's best assertion methods:

| N# | XUnit |
|----|-------|
| `assert x == 5` | `Assert.Equal(5, x)` |
| `assert x != null` | `Assert.NotNull(x)` |
| `assert x == null` | `Assert.Null(x)` |
| `assert !isValid` | `Assert.False(isValid)` |
| `assert list.Contains(x)` | `Assert.Contains(x, list)` |
| `assert !list.Contains(x)` | `Assert.DoesNotContain(x, list)` |
| `assert str.StartsWith("x")` | `Assert.StartsWith("x", str)` |
| `assert str.EndsWith("x")` | `Assert.EndsWith("x", str)` |
| `assert list.Count == 0` | `Assert.Empty(list)` |
| `assert list.Count != 0` | `Assert.NotEmpty(list)` |
| `assert list.Count == 1` | `Assert.Single(list)` |
| `assert x is MyType` | `Assert.IsType<MyType>(x)` |

### Running Tests

```bash
nlc test                         # Run all tests
nlc test --filter "should add"   # Run matching tests
nlc test --json                  # Structured JSON output
nlc watch test                   # Re-run on file changes
```

## Extension Methods

Add methods to existing types using `this` on the first parameter.

```n#
func IsEmpty(this s: string): bool {
    return s.Length == 0
}

func Truncate(this s: string, maxLength: int): string {
    if s.Length <= maxLength {
        return s
    }
    return s.Substring(0, maxLength) + "..."
}

func IsEven(this n: int): bool {
    return n % 2 == 0
}

func main() {
    greeting := "Hello, World!"
    print greeting.IsEmpty()           // False
    print greeting.Truncate(5)         // Hello...

    let num: int = 42
    print num.IsEven()                 // True
}
```

## String Interpolation

Use `$"..."` for interpolated strings.

```n#
name := "Alice"
age := 30
print $"Name: {name}, Age: {age}"
print $"Next year: {age + 1}"
print $"Pi: {3.14159:F2}"             // Pi: 3.14
```

### Escape Sequences

Inside a `"..."` or `$"..."` literal (and inside a character literal), a backslash begins an escape.
N# admits exactly these, and nothing else:

| Escape | Character | Notes |
|---|---|---|
| `\'` | `'` (U+0027) | |
| `\"` | `"` (U+0022) | |
| `\\` | `\` (U+005C) | |
| `\0` | null (U+0000) | |
| `\a` | alert (U+0007) | |
| `\b` | backspace (U+0008) | |
| `\t` | tab (U+0009) | |
| `\n` | line feed (U+000A) | |
| `\v` | vertical tab (U+000B) | |
| `\f` | form feed (U+000C) | |
| `\r` | carriage return (U+000D) | |
| `\e` | escape (U+001B) | the ANSI/VT escape character |
| `\x` *H* to *HHHH* | that code unit | **one to four** hex digits, read greedily |
| `\u` *HHHH* | that code unit | **exactly four** hex digits |
| `\U` *HHHHHHHH* | that code point | **exactly eight** hex digits; above U+FFFF it becomes a surrogate pair |

Hex digits are ASCII only (`0`-`9`, `a`-`f`, `A`-`F`).

```n#
red := "\x1b[1;31m"        // ESC [ 1 ; 3 1 m  — seven characters
same := "\e[1;31m"         // the same seven
unit := "\u001b"           // and the same again
grin := "\U0001F600"       // one code point, two UTF-16 code units
```

A backslash followed by anything else is not an escape and is reported as
[NL105](./errors/NL105.md), so a Windows path or a regular expression must double its backslashes —
`"C:\\temp"`, `"\\d+"` — or use a raw string, which has no escapes at all. Note that `\t` in
`"C:\temp"` *is* a valid escape and becomes a tab, so that path is silently wrong rather than
rejected.

### Raw String Literals

Triple-quoted raw strings (`"""..."""`) span multiple lines and have no escapes at all —
quotes, backslashes and every sequence in the table above are taken literally. Prefix with `$` to interpolate.

```n#
name := "Ada"
sql := $"""
SELECT * FROM users
WHERE name = '{name}'
  AND active = true
"""
print sql
```

In a raw interpolated string, `{expr}` is an interpolation hole exactly as in `$"..."` —
including right after a colon, so JSON templating works naturally:

```n#
json := $"""
{
    "name": "{person.Name}",
    "age": {person.Age}
}
"""
```

Two leniencies make embedded JSON and templates pleasant, with no `{{` escaping needed
for structural braces:

- A `{` that opens a **multi-line** brace group — like the outer JSON braces above — is
  literal text. Only a brace group that opens and closes on one line is a hole.
- A `{` with no closing `}` before the end of the string is literal text.

To write a *single-line* literal brace group, escape with doubled braces: `{{` and `}}`
each produce one literal brace. Format specifiers work inside holes as usual:
`{price:F2}`.

## Imports and Packages

```n#
// Import .NET namespaces
import System
import System.Linq
import System.Collections.Generic

// Alias an import
import System.Text.Json as Json

// Declare your namespace
package MyApp.Services

class UserService {
    // ...
}
```

### Qualified names

A namespace-qualified name works anywhere a bare name does — as a type, as the receiver of a
static call, as the thing you construct. Nothing has to be imported for it:

```n#
package MyApp

func Report(parts: List<string>): string {
    largest := System.Math.Max(1, 2)                        // a qualified static call
    limit := System.Int32.MaxValue                          // a qualified static read
    builder := new System.Text.StringBuilder()              // a qualified construction
    day := System.DayOfWeek.Monday                          // a qualified enum member
    joined := System.String.Join(",", parts)                // any namespace depth
    return joined
}
```

The same spelling reaches your own project's namespaces:

```n#
package MyApp

func Create(): MyApp.Models.Person {
    return MyApp.Models.Person.Default
}
```

An **alias** qualifies exactly the same way — `import System.IO as Io` makes `Io.Path.Combine(a, b)`
mean `System.IO.Path.Combine(a, b)`:

```n#
import System.IO as Io
import System.Text as Txt

package MyApp

func Combine(left: string, right: string): string {
    builder := new Txt.StringBuilder()
    builder.Append(Io.Path.Combine(left, right))
    return builder.ToString()
}
```

### Which declaration a bare name means

A bare name is resolved in this order, and the first channel that answers wins:

1. **Your file's own namespace.** A type declared alongside you is what the name means, whatever
   your imports bring in. Files that share a namespace see each other's types with no import.
2. **Your imports, in the order you wrote them** — a source namespace and a .NET namespace count
   equally here. If two imports supply the same name, that is [NL209](errors/NL209.md): neither is
   closer, so the compiler asks you to say which one you mean.
3. **Project-wide auto-discovery.** An exported type anywhere in your project is usable by its bare
   name without an import, as long as exactly one declaration has that name. This is a convenience,
   so it ranks *below* anything you imported explicitly — a `class Version` of your own in a
   namespace you never imported does not take the name `Version` away from `import System`.
4. **The referenced assemblies**, by simple name.

When two declarations tie, or when auto-discovery picks up a name you did not mean, write the
qualified name. It is never ambiguous.

## Visibility

N# uses Go-style naming conventions for visibility — do not write `public`/`private` keywords for ordinary code. The formatter removes redundant `public`/`private` when casing already expresses the same visibility.

| Convention | Visibility |
|------------|-----------|
| `PascalCase` | exported/public |
| `camelCase` | unexported/private-by-convention |

```n#
class Account {
    Balance: decimal      // exported/public (PascalCase)
    accountId: string     // unexported/private-by-convention (camelCase)

    func Deposit(amount: decimal) { }   // exported/public
    func validate() { }                  // unexported/private-by-convention
}
```

Explicit modifiers are narrow .NET interop escape hatches, not the normal way to express visibility. When they override casing, the formatter preserves them because dropping them would change the exported API:

```n#
class Service {
    public legacyCamel: string      // forced public for interop
    private SecretPascal: string    // forced hidden despite PascalCase
    internal ConnectionString: string
    protected BaseUrl: string
}
```

Enum cases are part of the containing enum's value set. Export is controlled by the enum itself, so lowercase enum cases remain visible when the enum is exported; use casing diagnostics as style guidance, not as API hiding.

## Next Steps

- **[For Go Developers](for-go-developers.md)** — How Go concepts map to N#
- **[Pattern Matching Guide](pattern-matching.md)** — Deep dive into pattern matching
- **[Types Guide](types.md)** — Advanced type system features
- **[Systems N#](systems.md)** — The high-performance lane: `[hot]`, `Result<T,E>`, spans, SIMD
- **[Examples](/examples/)** — curated example projects
