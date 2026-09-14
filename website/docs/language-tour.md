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

### `default`

`default` is the zero value of whatever type the position it is written in expects — `0` for a
number, `false` for a `bool`, the null reference for a class, string or array, an all-zero struct,
and, inside a generic body, whichever of those the type argument turns out to be. It carries no type
of its own, so it is written bare and the target supplies the type:

```n#
count: int = default              // 0
name: string? = default           // null
when: DateTime = default          // 0001-01-01

func Zero<T>(): T {
    return default                // 0 for Zero<int>(), null for Zero<string?>()
}

func TryFirst(values: int[], out first: int): bool {
    if values.Length > 0 {
        first = values[0]
        return true
    }

    first = default               // the out parameter still gets a value
    return false
}
```

The same reading holds in an argument (`new Box<T>(default)`), in a `return`, and on either side of
an assignment. A `default` with no target — nothing to be the zero value *of* — is an error, not an
inference.

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

### Named arguments

Any argument may be written with the name of the parameter it is for, `name: value`. The name binds
the argument to that parameter wherever it is written, so a call reads as what it means rather than
as a row of unlabelled values. This works at every call: a free function, a method, a constructor, a
static member, a member of a .NET type, and a `base(...)` or `this(...)` constructor chain.

```n#
func connect(host: string, port: int = 8080, secure: bool = false): string {
    return $"{host}:{port}"
}

func main() {
    print connect(host: "localhost", port: 9000, secure: true)

    // The names carry the meaning, so the order they are written in is free.
    print connect(secure: true, port: 9000, host: "localhost")

    // A positional argument fills the next parameter no name has claimed.
    print connect("localhost", secure: true, port: 9000)

    // A named `out` or `ref` argument keeps its modifier after the name.
    parsed := 0
    if Int32.TryParse("42", result: out parsed) {
        print parsed
    }
}
```

Arguments are evaluated **in the order they are written**, whatever order the parameters are
declared in. In `Send(body: Build(), to: Lookup())`, `Build()` runs before `Lookup()` even though
`to` is the earlier parameter.

A name has to be a parameter of the function being called, each parameter may be given a value only
once, and every parameter without a default has to end up with one. The compiler reports each of
these by name:

```
'connect' has no parameter named 'hostname'
'connect' got multiple values for parameter 'host'
'connect' needs an argument for parameter 'host'
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

Classes are the primary type construct. Visibility is convention-based: PascalCase = exported/public, camelCase = namespace-private.

```n#
class Person {
    Name: string         // exported/public (PascalCase)
    age: int             // namespace-private (camelCase)

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
one place a member call cannot express it. The base's constructors are read wherever they live — the
same compilation or a referenced assembly — and the one the arguments name is chosen the same way in
both worlds:

```n#
class SizedList: List<string> {
    constructor(capacity: int): base(capacity) {}    // an external base, with an argument
}
```

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
| `return <value>` inside a constructor | [NL202](./errors/NL202.md) |

A constructor runs like a `void` function, so a bare `return` ends it early — the field initializers
and the base call have already happened by the time the body starts:

```n#
class Daemon {
    private running: bool
    private readonly root: string

    constructor(rootPath: string, forced: bool) {
        root = rootPath
        if forced {
            running = true
            return
        }

        // the ordinary path continues here
    }
}
```

A constructor returns nothing, so `return <value>` is an error. Note also that `running` above owes
the constructor no assignment: only a non-nullable **reference**-typed field does, because every
value type's `default` is already a valid value of it ([NL304](./errors/NL304.md)).

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

### Value Members in an Interface

An interface may declare a **value member** — the same bare `Name: Type` spelling a class uses for
its own value members. What it declares is a **get-only abstract property slot**: one `get_Name`
accessor with no body, plus the `PropertyInfo` row naming it. Every implementer fills the slot, and
callers read it through the interface exactly as they call a `func`.

```n#
interface IDocumentState {
    Uri: string

    func Touch(): int
}

class DocumentState: IDocumentState {
    Uri: string          // a field — and the reader the slot needs is synthesized over it
    touches: int

    constructor(uri: string) {
        Uri = uri
        touches = 0
    }

    func Touch(): int {
        touches = touches + 1
        return touches
    }
}

func describe(state: IDocumentState): string {
    return state.Uri        // callvirt get_Uri — the implementer's own reader
}
```

**Either spelling fills the slot.** A class writes its value members bare, so the commonest filler is
a plain field of that name; an accessor block works just as well, and the caller cannot tell them
apart:

```n#
class ComputedState: IDocumentState {
    scheme: string
    host: string

    constructor(scheme: string, host: string) {
        this.scheme = scheme
        this.host = host
    }

    Uri: string {
        get { return scheme + "://" + host }
    }

    func Touch(): int {
        return 0
    }
}
```

A struct may implement one too — the receiver is boxed at the interface, which is where the copy is
taken.

**The slot is get-only, on purpose.** N# has no body-less accessor to write, so a bare
`Name: Type` is the only spelling an interface has for a value member — and a read slot is one that
*everything* can fill, a plain field and a computed get-only property alike. A slot that also
demanded a setter would refuse implementers that every reader of the interface is satisfied by. Write
a `func` when an interface needs to hand the caller a way to change the value.

A value member is matched by NAME, like every other interface member: an implementer that does not
declare one reports [NL325](./errors/NL325.md) under the member's own name. Writing to one through
the interface reports [NL342](./errors/NL342.md) — the slot has no setter to store into. The three
inheritance words are redundant on a value member — every member an interface declares is a slot
already — and are reported with [NL311](./errors/NL311.md).

An interface may declare an event and a value member together; each emits its own metadata row, and
one class fills both:

```n#
import System

interface IChannel {
    event Changed: EventHandler

    Name: string

    func Touch()
}

class Channel: IChannel {
    event Changed: EventHandler
    Name: string

    constructor(name: string) {
        Name = name
    }

    func Touch() {
        Changed?.Invoke(this, EventArgs.Empty)
    }
}
```

### Duck Interfaces

Duck interfaces use structural typing — any type that has the right methods automatically satisfies the interface, without declaring it.

A duck interface's **value members** count in the match too. `duck interface IShaped { Size: int }`
is satisfied only by a type that can be read for a `Size` of that type — a field or a get-only
property — and the reader its slot needs is synthesized the same way a declared interface's is.

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

### Attributes on an enum and its members

An enum's members become **literal fields** of the emitted type, so a member carries attributes the
way a field does, and the declaration carries its own on the type. `[Flags]` therefore does what it
does in C#.

```n#
import System

[Flags]
enum Permission {
    Read = 1,

    [Obsolete("use ReadWrite")]
    Write = 2
}

func main() {
    print (Permission.Read | Permission.Write).ToString()    // Read, Write
    field := must typeof(Permission).GetField("Write")
    print field.GetCustomAttributesData().Count.ToString()   // 1
}
```

A member's attributes answer to `AttributeTargets.Field`; `AttributeTargets.Enum` belongs to the
declaration above them. See [Attributes](./basics.md#attributes).

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

### Re-throwing

A bare `throw` inside a `catch` re-raises the exception that handler is running for, **keeping its
original stack trace**. Use it whenever you are not changing the exception — logging it, cleaning up,
deciding it is not yours to handle.

```n#
import System

func LoadConfig(path: string): int {
    try {
        return int.Parse(ReadAll(path))
    } catch ex: FormatException {
        print $"{path} is not a number"
        throw                          // re-raises ex with the original stack intact
    }
}
```

`throw ex` is a different statement. It raises the same object again *from the handler*, which resets
the stack trace to this frame — the original failure site is lost. Reach for it only when you mean to
raise the exception anew, and prefer wrapping (`throw new InvalidOperationException(msg, ex)`) when
you want to add context.

A bare `throw` needs a handler to re-throw from. Outside a `catch`, inside a `finally` nested in the
handler, or inside a lambda or local function written in the handler (each compiles to a method of
its own), it is [`NL336`](./errors/NL336.md).

### `throw` as an expression

A `throw` produces no value, so it can stand where a value is expected only when something *else*
says what the surrounding expression is worth. N# admits it in three positions — the same three C#
does.

**As the fallback of `??`.** The left side decides the type, and the whole expression is worth that
side with its nullability removed, so flow analysis treats the result as non-null from there on:

```n#
import System

func Trimmed(name: string?): string {
    value := name ?? throw new ArgumentNullException("name")
    return value.Trim()                // `value` is `string`, never `string?`
}
```

**As an arm of a conditional.** An arm that throws contributes nothing to the join, so the other arm
decides the type; only the taken arm is evaluated:

```n#
import System

func Port(configured: int, ok: bool): int {
    return ok ? configured : throw new InvalidOperationException("no port configured")
}
```

**As an expression body** — an arrow-bodied `func`, an arrow-bodied property, or a lambda's. The
declared return type is what the body would otherwise have produced:

```n#
import System

func NotDone(): string => throw new NotImplementedException()

func Rejector(): Func<int, string> => x => throw new NotSupportedException("no")
```

Anywhere else a `throw` is a statement, not a value, and writing one in value position is
[`NL340`](./errors/NL340.md) — including inside parentheses, since `x ?? (throw e)` makes the
parentheses the position the `throw` is standing in.

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

### Async Lambdas

Write `async` in front of a lambda to make its body asynchronous. The body produces the **result**
the target delegate's task carries — not the task itself — exactly as an `async func` declares its
inner type and the signature wraps it:

```n#
import System
import System.Threading.Tasks

func makeLoader(): Func<string, Task<int>> {
    return async path => {
        contents := await readAllTextAsync(path)
        return contents.Length
    }
}
```

All three parameter spellings take the keyword — `async () => …`, `async x => …`,
`async (a, b) => …` — with either an expression body or a block body, and the target may be any
delegate returning `Task`, `Task<T>`, `ValueTask` or `ValueTask<T>`. Which family the value travels
in is the target's decision, not the body's: the same body serves `Func<Task<int>>` and
`Func<ValueTask<int>>`.

An async lambda captures like any other lambda — enclosing locals, `this`, and a fresh copy of each
loop iteration's own locals.

**An exception raised inside the body lands on the returned task**, not on the caller that invoked
the delegate:

```n#
failing: Func<Task<int>> = async () => {
    await Task.Delay(1)
    throw new InvalidOperationException("nope")
}

task := failing()        // returns normally; the task is faulted
print task.IsFaulted     // True
```

A **local function** can be `async` too. Like a top-level `async func` it declares its *inner* type,
and the method it compiles to returns the wrap — so `async func inner(): int` is called with `await`:

```n#
func loadAll(paths: string[]): int {
    async func lengthOf(path: string): int {
        contents := await readAllTextAsync(path)
        return contents.Length
    }

    total := 0
    for path in paths {
        total = total + await lengthOf(path)
    }
    return total
}
```

Leaving the keyword off when the target wants a task is [`NL335`](./errors/NL335.md), which names the
missing word rather than leaving you to read two delegate types side by side.

There is **no `async void`**: a lambda whose target returns `void` (an `Action`) has nowhere to put
its task, so N# reports [`NL334`](./errors/NL334.md) and asks you to drop the keyword or give the
target a task-like return. That page explains why N# departs from C# here, and what it buys.

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

## Lambdas and Closures

A lambda is written `x => expression` or `x => { … }`, and it can read whatever the code around it
can read: its own parameters, the enclosing function's locals and parameters, and — inside a type —
the instance's own members.

```n#
class Scaler {
    Factor: int

    constructor(factor: int) {
        Factor = factor
    }

    func Make(bonus: int): Func<int, int> {
        return x => x * Factor + bonus     // the instance AND a parameter
    }
}
```

**A capture is one storage location, not a copy.** A variable the lambda writes — or one that is
written after the lambda was built — is shared between the two, so both sides see every write:

```n#
func counter(): Func<int> {
    total := 0
    return () => {
        total = total + 1
        return total
    }
}

next := counter()
print next()    // 1
print next()    // 2
```

**A binding declared inside a loop is a new binding each time round**, so a delegate collected in the
loop closes over its own copy — the same rule C# has:

```n#
adders := new List<Func<int>>()
for i := 0; i < 3; i++ {
    step := i * 10
    adders.Add(() => step)
}
print adders[0]()   // 0, not 20
```

### Lambdas inside lambdas

A lambda written inside another lambda reaches **every** enclosing scope — its own parameters, the
outer lambda's, the function's, and the instance — to any depth, and nothing about the nesting needs
to be written down:

```n#
func curried(seed: int): Func<int, Func<int, int>> {
    return a => b => a + b + seed
}

add := curried(100)
addOne := add(1)
print addOne(2)     // 103
```

The same holds for a lambda inside a **local function**, for a local function that captures a
delegate-typed local, and for a lambda that captures a variable the inner lambda then writes: the
write is seen at every level, because there is still only one storage location.

### `this` inside a lambda

A lambda that reads an instance member captures the **instance**, not a copy of the member, so it
answers from the object as it is when the delegate runs:

```n#
class Holder {
    Factor: int
    Scaled: Func<int, int>

    constructor(factor: int, bonus: int) {
        Factor = factor
        Scaled = x => x * Factor + bonus     // legal in a constructor too
    }
}

h := new Holder(3, 10)
print h.Scaled(2)     // 16
h.Factor = 5
print h.Scaled(2)     // 20 — the field, not a snapshot of it
```

`this.Factor` and the bare `Factor` name the same member and behave identically. A **struct**'s
`this` cannot be captured: it is a pointer into the value's own storage, which a delegate would
outlive.

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

The `?.` skips **the whole rest of the chain**, not just the next link: `a?.M().B` is null when `a`
is, and the `.B` is never reached. Parentheses end the chain, exactly as in C#, so `(a?.B).C` reads
`.C` on whatever `a?.B` produced. A receiver may be a reference, a `Nullable<T>` (the access runs on
its `Value`), or an unconstrained type parameter; a plain non-nullable value type has no null to test
for and is refused. See [Types](types.md#null-conditional-operator) for the full rules.

**What is not supported yet.** `?[` null-conditional **indexing** is not compiled. Write the guard by
hand for that one.

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

A static member belongs to the TYPE, so it is in scope in every body the type owns — a static
method, an instance method and a static accessor alike — and it is a **receiver** there like any
other value:

```n#
import System.Collections.Generic

class Registry {
    static Entries: List<string> = new List<string>()

    static func Add(name: string) {
        Entries.Add(name)                 // the static field IS the receiver
    }

    func AddFromInstance(name: string) {
        Entries.Add(name)                 // the same member, from an instance body
    }

    static func Total(): int => Entries.Count
}
```

A static member the BASE declares is reached the same way from a derived type's bodies. Writing the
type name (`Registry.Entries.Add(name)`) names the same storage.

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

### Comparing two values of an open type parameter

`a == b` works when both sides are the **same** type parameter, whether or not either is written
`?`. C# refuses this outright (`CS0019`) and makes you write
`EqualityComparer<T>.Default.Equals(a, b)` by hand; N# writes it for you, because that *is* the CLR's
one comparison for a value whose kind is not known until the instantiation is chosen — it dispatches
to `IEquatable<T>.Equals` when the instantiation implements it and to `Equals` otherwise.

```n#
func Same<T>(a: T, b: T): bool => a == b

// `T?` under `where T : struct` is a real `Nullable<T>`, so this is the lifted form: two ABSENT
// values are equal, an absent one differs from every present one, and the answer is a plain `bool`.
func SameOptional<T>(a: T?, b: T?): bool where T : struct => a == b

func main() {
    absent: int? = null
    print Same(3, 3)                    // True
    print SameOptional(absent, absent)  // True
    print SameOptional(1, absent)       // False
}
```

Only equality lifts this way. `<`, `>`, `+` and the rest of the numeric operators need an operand
type that has them, and an open parameter does not — those stay `NL202`, exactly as in C#. Constrain
the parameter to a concrete type, or take a `Comparer<T>` if ordering is what you need.

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

The same rules reach the conversions a **.NET type** declares, so `name: XName = "entry"` and
`offset: DateTimeOffset = instant` work without ceremony — see
[conversion operators of .NET types](types.md#conversion-operators).

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

### Any receiver, anywhere a call goes

`on <receiver>.<Event> <handler>` is an expression wherever a call is, and the receiver is any
expression whose value (or type) owns the event — a static type, a local, a parameter, a field
with or without `this.`, a property chain, an indexed element, `base.`:

```n#
import System
import System.Collections.ObjectModel

class Watcher {
    items: ObservableCollection<string>

    constructor(source: ObservableCollection<string>) {
        items = source
    }

    func Watch(other: ObservableCollection<string>, all: ObservableCollection<string>[]) {
        a := on items.CollectionChanged (sender, args) => { print "field" }
        b := on this.items.CollectionChanged (sender, args) => { print "this.field" }
        c := on other.CollectionChanged (sender, args) => { print "parameter" }
        d := on all[0].CollectionChanged (sender, args) => { print "indexed" }
        e := on Console.CancelKeyPress (sender, args) => { args.Cancel = true }
        off a
        off b
        off c
        off d
        off e
    }
}
```

The handle is an ordinary local, so it is captured by a lambda or a local function like any other
name, and `off` inside one of those detaches the subscription the enclosing body made.

### Handlers: a lambda, a delegate value, or a method

The handler is any expression of the event's delegate type. An inline lambda is the common
spelling — its parameter types are inferred from the event — but a delegate you already hold works
too, which is what C#'s `x.E += handler` maps onto, and so does naming a function directly:

```n#
import System.Collections.ObjectModel
import System.Collections.Specialized

func Log(_sender: object?, _args: NotifyCollectionChangedEventArgs) {
    print "changed"
}

func main() {
    items := new ObservableCollection<string>()

    inline := on items.CollectionChanged (sender, args) => { print "inline" }
    named: NotifyCollectionChangedEventHandler = (sender, args) => { print "named" }
    held := on items.CollectionChanged named
    group := on items.CollectionChanged Log

    off inline
    off held
    off group
}
```

The handler must begin **on the event's own line**; a handler on the next line is reported as a
missing one rather than silently swallowing the next statement.

An event that declares a **maybe-null** position reads that annotation from the event's own
metadata, so a handler written to the same shape fits. `AssemblyLoadContext.Resolving` is
`Func<AssemblyLoadContext, AssemblyName, Assembly?>`, and a function returning `Assembly?` is a
handler for it — as is one that never returns null, because the result position is covariant:

```n#
import System.Reflection
import System.Runtime.Loader

func resolve(_context: AssemblyLoadContext, _name: AssemblyName): Assembly? {
    return null
}

func main() {
    sub := on AssemblyLoadContext.Default.Resolving resolve
    off sub
}
```

### Detaching

`off <handle>` detaches exactly the handler that handle attached — including an inline lambda,
which .NET's own `-=` cannot do without you keeping the delegate. Two subscriptions to one event
detach independently, and **`off` twice is a no-op**: the handle claims its remove accessor once,
so the second call does nothing (and never detaches somebody else's handler).

A bare `on …` statement discards the handle, which is how you subscribe for the life of the
object.

`+=`/`-=` on an event is a compile error that points you to `on`/`off` (it used to compile and
then crash at runtime). On a real `Func`/`Action` field, `+=`/`-=` still combine/remove
delegates.

## Declaring Events

Write `event Name: DelegateType` as a member of a class, struct or record. It is C#'s **field-like
event**, and it emits exactly what C# emits: private storage carrying the event's own name,
`add_Name` / `remove_Name` accessors that combine and remove handlers with
`Interlocked.CompareExchange`, and CLR `EventInfo` metadata wiring the two together — so a C# caller
can write `widget.Changed += handler` against your assembly.

```n#
import System

class Widget {
    event Changed: EventHandler

    func Rename(name: string) {
        Changed?.Invoke(this, EventArgs.Empty)
    }
}

func main() {
    widget := new Widget()
    subscription := on widget.Changed (sender, args) => { print "changed" }
    widget.Rename("new")
    off subscription
}
```

Visibility follows the same rule as every other member: `Changed` is exported, `changed` is
package-private, and a written `private` / `protected` / `internal` word wins over the casing. The
accessors take the event's visibility; the backing storage is **always private**.

`static event` works too, and is subscribed to through the declaring type's name:

```n#
class Registry {
    static event Registered: EventHandler

    static func Announce() {
        Registry.Registered?.Invoke(null, EventArgs.Empty)
    }
}

func watch() {
    subscription := on Registry.Registered (sender, args) => { print "registered" }
    Registry.Announce()
    off subscription
}
```

### Raising, inside the declaring type

Inside the type that declared it, the event's name **is** the backing delegate. All three of these
read:

```n#
class Widget {
    event Changed: EventHandler

    func Raise() {
        Changed?.Invoke(this, EventArgs.Empty)   // the usual raise: a no-op with no subscribers
    }

    func RaiseUnguarded() {
        Changed(this, EventArgs.Empty)           // C#'s rule: throws when nothing is subscribed
    }

    func HasSubscribers(): bool {
        return Changed != null
    }
}
```

`Changed?.Invoke(...)` is the one to reach for. `Changed(...)` is the same call without the guard,
and — exactly as in C# — it throws `NullReferenceException` when no handler is attached, because an
event with no subscribers is null.

### Subscribing, inside the declaring type

`on` and `off` are the one position where the name means the **event** wherever it is written, so the
declaring type subscribes to its own event exactly as an outside caller does:

```n#
class Widget {
    event Changed: EventHandler
    Seen: int

    func WatchItself(): int {
        subscription := on this.Changed (sender, args) => {
            Seen = Seen + 1
        }
        Raise()
        off subscription
        Raise()
        return Seen                              // 1 — the second raise ran after `off`
    }

    func Raise() {
        Changed?.Invoke(this, EventArgs.Empty)
    }
}
```

`on this.Changed` and `on Changed` are the **same** target: `this.Member` collapses to the bare
member read, here as everywhere else. A `static event` named bare subscribes the same way, with no
receiver at all. This is what C#'s `this.E += handler` does inside the declaring type — the field
combine — so one reading serves both spellings, and an `abstract` event (which has no backing field
to combine) needs no exception of its own.

Everything that is not an `on` / `off` target keeps the delegate reading above, so
`Changed?.Invoke(...)` and `Changed == null` are unaffected. A name that is a plain delegate rather
than an event is still refused: `on handler (sender, args) => { … }` over an `EventHandler?` field
reports [NL318](./errors/NL318.md), because `on` subscribes and a delegate field is combined with
`+=`.

### Outside the declaring type it is only an event

Everywhere else the name may be subscribed to with `on` and detached with `off`, and nothing more.
Reading it, invoking it, assigning to it and `+=` / `-=` all report
[NL337](./errors/NL337.md), which names the type that declared it. A **derived** class is outside
too, which is C#'s rule as well: it subscribes like any other caller, and raises through a method the
base declared for that purpose.

```n#
func watch(widget: Widget) {
    widget.Changed?.Invoke(null, EventArgs.Empty)   // NL337
    widget.Changed += handler                       // NL337 — use `on`
}
```

An event's type must be a delegate; anything else reports [NL338](./errors/NL338.md).

### `virtual`, `abstract` and `override`

An event's accessors are ordinary methods, so the three inheritance words mean on an event exactly
what they mean on a `func`: `virtual` opens a slot for each accessor, `abstract` opens one and
supplies no body, and `override` reuses the base's.

```n#
import System

class Signal {
    virtual event Fired: EventHandler

    virtual func RaiseOwn() {
        Fired?.Invoke(this, EventArgs.Empty)
    }
}

class LoudSignal: Signal {
    override event Fired: EventHandler

    override func RaiseOwn() {
        Fired?.Invoke(this, EventArgs.Empty)
    }
}

abstract class Pump {
    abstract event Ticked: EventHandler
}
```

An `abstract` event has **no storage**: it is a pair of slots, so the declaring type has nothing to
raise and reading the name there reports [NL337](./errors/NL337.md). A concrete class that inherits
one must fill it, or it reports [NL324](./errors/NL324.md).

:::caution An `override` event keeps its OWN handler list
This is C#'s behaviour, and it is the one thing about overriding an event that surprises people. A
subscriber reaching the event through a base reference runs the **override's** `add_`, so the handler
lands in the **override's** storage — and the base's own `Fired?.Invoke(...)`, which reads the base's
field, then sees nothing. Put the raise where the storage is: give the base a `virtual func` the
derived type overrides, as `RaiseOwn` does above.
:::

What is still refused is what the CLR cannot carry, each with [NL311](./errors/NL311.md): a
`static` event has no slot to dispatch through; a struct or record struct is sealed, so it can
neither open a slot nor take one; `abstract` needs an abstract class and `virtual` a class that is
not sealed; and `override` needs a base event of that name whose accessors are open.

### Events in an interface

An `interface` may declare an event. What it declares is a pair of **abstract accessor slots** plus
the `EventInfo` row naming them; the implementing type fills both by declaring an event of the same
name and delegate type, exactly as it fills a `func` slot by declaring that `func`:

```n#
import System

interface INotifier {
    event Changed: EventHandler

    func Touch()
}

class Widget: INotifier {
    event Changed: EventHandler

    func Touch() {
        Changed?.Invoke(this, EventArgs.Empty)
    }
}

func watch(notifier: INotifier) {
    sub := on notifier.Changed (sender, args) => { print "changed" }
    notifier.Touch()
    off sub
}
```

A type that declares the interface and not the event reports [NL325](./errors/NL325.md), under the
event's own name. The same holds for an interface a referenced assembly declares — `class Chatty:
INotifyPropertyChanged` must declare `event PropertyChanged: PropertyChangedEventHandler`, and the
accessors it emits fill that interface's slots.

The three inheritance words are redundant on an interface event — every one of them is a slot already
— and are reported with [NL311](./errors/NL311.md).

**Current limits.** An event's storage
is synthesized, so it takes no initializer and no accessor block, and an event must be written among
the type's fields — before its first `func` — like every other field-shaped member. An instance
event declared by a **struct** emits and is raised by the struct's own code, but `on` refuses to
subscribe through a struct receiver, because that receiver is a copy. Inside the type that declared
it, the event's name is its backing delegate rather than an event, so `on this.Changed …` from within
that type reports [NL318](./errors/NL318.md) — subscribe from outside, or hold the delegate directly.

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

### Flow narrowing

A null check narrows what the code it guards knows. The rule is the same one C# uses: a condition
yields two sets of facts — what it proves when it is **true** and what it proves when it is
**false** — and each branch gets its own set. A guard clause whose branch always leaves (`return`,
`throw`, `break`, `continue`) hands the *opposite* set to the code after the `if`; when neither
branch leaves, the code after the `if` gets the [join](#the-two-paths-after-an-if-join) of the two.

```n#
func describe(value: string?): int {
    if value == null { return -1 }
    return value.Length                  // `value` is known non-null here
}
```

The connectives compose the two sets rather than merging them:

| Condition | True branch knows | False branch knows |
|---|---|---|
| `a != null` | `a` non-null | `a` null |
| `a && b` | everything `a` and `b` prove | **nothing** — the negation is `!a \|\| !b` |
| `a \|\| b` | **nothing** | everything `!a` and `!b` prove |
| `!c` | what `c` proves when false | what `c` proves when true |
| `(c)` | what `c` proves | what `c` proves |

`a && b` deliberately proves nothing in its false branch: when `a` is false the branch is skipped
without `b` ever being evaluated, so `if option != null && count == null { return }` tells you
nothing about `count` afterwards. A `!`, a parenthesis, and a ternary's two arms all follow the same
lattice:

```n#
func lengthOrDefault(value: string?): int {
    return value != null ? value.Length : -1   // the then-arm knows `value` is non-null
}
```

A `?.` chain compared against null narrows the **whole chain**: `x?.M == null` being false means
both `x` and `x.M` are non-null, because a null `x` would have made the whole expression null.

```n#
func textLength(doc: Document?): int {
    if doc?.Text == null { return -1 }
    return doc.Text.Length               // both `doc` and `doc.Text` are known non-null
}
```

#### A path carries its own state

Narrowing is about a **path**, not only about a name. `doc.Error` has its own flow state, so proving
it once is enough for everything that follows:

```n#
func report(response: DaemonResponse): string {
    code := (must response.Error).Code       // the unwrap throws if it is null …
    return response.Error.Message            // … so this read is safe
}
```

Four things establish the fact, and all four work on a path exactly as they work on a local:

| Written | What it proves |
|---|---|
| `if x.P != null { … }` | `x.P` non-null inside the branch |
| `must x.P` | `x.P` non-null for everything after it — the unwrap throws otherwise |
| `x.P ?? throw …` | `x.P` non-null after it — the fallback leaves the method |
| `Assert.NotNull(x.P)` | `x.P` non-null, from a `[NotNull]` parameter on the signature |

`must` is *transparent* for this purpose: `(must x).P` names the same path `x.P` does, so
`Assert.NotNull((must response).Error)` files its fact against `response.Error` — which is what the
line after it reads.

Four things take the fact away, and one deliberately does not:

- **writing the path** — `x.P = other` — which also drops everything under it (`x.P.Q`);
- **writing any prefix** — `x = other` drops `x`, `x.P` and `x.P.Q` together;
- **passing a prefix by `ref` or `out`**, which is an assignment the callee performs;
- **leaving the scope** the fact was proved in;
- but **not** a method call on the receiver. `response.Touch()` *could* have set `Error` to null, and
  the compiler deliberately does not assume it did — this is C#'s rule, and without it a guard would
  be worth nothing past the next call.

#### A loop's back edge joins

A loop's body runs many times, so the state at the top of it is the join of the code before the loop
**and of the loop's own back edge**. A path proved before the loop and written inside it is
maybe-null at the top of every turn — including the first one, because the compiler answers one
question for all of them:

```n#
func messages(response: DaemonResponse, replacement: ResponseError?, turns: int): string {
    total := ""
    turn := 0
    while turn < turns {
        if response.Error != null {          // the guard belongs INSIDE the loop …
            total = total + response.Error.Message
        }

        response.Error = replacement         // … because this is what the back edge carries
        turn = turn + 1
    }

    return total
}
```

The join covers every write the body can make — an assignment, an `++`/`--`, a `ref`/`out` argument,
and anything a lambda or local function declared in the body writes — and, for a `for`, its update
clause as well. A `for`'s **initializer** runs once, ahead of the first test, so the facts it
establishes survive. A loop that writes nothing keeps whatever it was given.

#### The two paths after an `if` join

A guard clause deletes one of the two paths, so the code after it simply inherits the other one. When
**neither** branch leaves, both paths are live and what follows the `if` is their **join** — the
state each path reaches the closing brace in, met together:

| Written | State after the statement |
|---|---|
| `if c { S }` | `join(exit(S), what c proves when false)` |
| `if c { S } else { T }` | `join(exit(S), exit(T))` |
| `if c { S }` where `S` always leaves | what `c` proves when **false** |
| `if c { S } else { T }` where `T` always leaves | `exit(S)` |

Meeting two paths is the ordinary lattice: two paths that agree keep their answer, and two that
disagree produce **maybe-null**. That is what makes the create-if-missing idiom read the way it is
written — the then-branch reaches the brace holding the list it just made, and the implicit else path
is the path on which `TryGetValue` returned `true`, which `[MaybeNullWhen(false)]` says leaves the
`out` target non-null:

```n#
func addLine(locations: Dictionary<string, List<int>>, name: string, line: int) {
    list: List<int>? = default
    if !locations.TryGetValue(name, out list) {
        list = new List<int>()
        locations[name] = list
    }

    list.Add(line)                       // both paths reach here holding a list
}
```

The same rule is what keeps the compiler honest in the other direction. A branch that assigns a
value that *may* be null leaves the join maybe-null, and a branch that assigns on only one of the two
paths tells the code below nothing — the other path never ran it:

```n#
func count(input: List<int>?, c: bool): int {
    values: List<int>? = default
    if c {
        values = new List<int>()
    }

    return values.Count                  // NL905 — the `c == false` path never assigned
}
```

A join also never takes back a fact the surrounding flow already proved. A redundant `if x != null`
written below a guard clause leaves `x` non-null, because a path the surrounding flow can still
answer for is a path neither branch wrote to.

A `switch` is the same rule with more than two branches: what follows it is the meet of every arm
that falls out of the bottom, provided those arms are the whole of the live paths — which is what a
`default` arm makes true. An arm that always leaves contributes nothing, and a `break` inside an arm
takes the join away, because control then reaches the code below from the middle of the arm.

A `while` or `for` is left through the bottom only when its condition failed, so the condition's
**false** facts hold after the loop — unless the body contains a `break`, which leaves without
testing the condition at all:

```n#
func fill(source: List<int>?, fallback: List<int>): int {
    values := source
    while values == null {
        values = fallback
    }

    return values.Count                  // the loop was left because `values` stopped being null
}
```

### Nullable value types keep their own members

`int?` is `System.Nullable<int>`, and its own members always bind — narrowed or not:

```n#
func parse(text: string?): int? {
    if text == null { return null }
    return text.Length
}

func main() {
    print parse("abc").HasValue                 // True
    print parse(null).GetValueOrDefault()       // 0
    print parse(null).GetValueOrDefault(42)     // 42

    value := parse("abcd")
    if value == null { return }
    print value.Value                           // 4 — still binds after narrowing
    print value + 1                             // 5 — and it reads as `int` where one is wanted
}
```

A narrowed `int?` is not merely *type-checked* as an `int` — it is **read** as one. The compiler
emits `Nullable<T>.Value` at the narrowed read, so `value + 1`, `return value` on an `int` function,
and `found.Line` on a narrowed `(Uri: string, Line: int)?` all run on the unwrapped value. Assigning
to the name ends the narrowing, and so does a loop body that writes it, because the next iteration
sees whatever the last one left.

The four shapes that lower the nullable *themselves* — `value == null`, `value ?? 0`,
`value.HasValue` and `value.Value` — keep the `Nullable<T>` and stay legal on a narrowed name, which
is why the example above still reads `value.Value` after the guard. So does a narrowed property
PATH: past `if h.Slot != null`, `h.Slot.Value` is the unwrap and `h.Slot + 1` is the narrowed read,
exactly as they are for a local.

Every name `Nullable<T>` itself declares binds on the nullable rather than on `T` — `HasValue`,
`Value`, `GetValueOrDefault`, and the three it overrides: `ToString`, `Equals` and `GetHashCode`.
All of those are null-safe, so `value.ToString()` on an absent value is `""` and never throws. Any
other name is `T`'s. See [Types](types.md#nullable-value-types).

Three more things narrow the surviving flow for the same reason a guard clause does: `assert cond`
(an assert that fails throws), a call to a `[DoesNotReturnIf(bool)]` parameter, and a guard branch
that ends in `break` or `continue` rather than `return` — see
[Functions](functions.md#a-signature-that-never-returns).

`must` on a value the flow already proved non-null is reported as **NL907**, a *warning* rather than
an error. Flow state is not something a mechanical translation can know, and a human tightening a
guard should not have their build broken by a keyword that is merely no longer needed. Remove the
`must` when the warning appears.

### Conditional expressions

A conditional arm that has **no type of its own** — a bare `null`, a `default`, or a `throw` — takes
its type from what the conditional is written *at*: the declared return type, the declared type of
the local, the type of the local being assigned, or the parameter the value is passed to.

```n#
import System

func pick(flag: bool, name: string): string? => flag ? name : null
func pickValue(flag: bool, n: int): int? => flag ? n : null      // the `int` arm lifts to `int?`
func orThrow(ok: bool, failure: Exception): string? => ok ? null : throw failure

func main() {
    picked: int? = true ? 3 : null         // a declared local is a target too
    picked = false ? 3 : null              // so is the local being assigned
    print unwrap(true ? 3 : null)          // and so is a parameter
    print picked.HasValue
}

func unwrap(value: int?): int => value ?? -1
```

The *typed* arm decides nothing here; the target does. That is what lets a value arm lift (`int` →
`int?`) rather than having to match a `null` it can never equal, and what gives a `null` a type when
the only other arm raises.

The one shape with nothing to take is **both** arms throwing (`ok ? throw a : throw b`): there is no
value either way, so write the `throw` as a statement instead. C# refuses that shape too.

## Resource Management and Locking

### `using`

`using` releases a resource when its region ends — on the way out of the block, whether the block
finished, returned, or threw. It is the statement a `try`/`finally` around a `Dispose()` call would
be, written once.

```n#
import System.IO

func ReadAll(path: string): string {
    using reader := new StreamReader(path) {
        return reader.ReadToEnd()
    }
}
```

There are four ways to write it, and they differ only in what they bind and where the region ends.

**Bind and scope to a block.** `using name := resource { … }` binds the resource, makes it visible
inside the block, and releases it when the block ends. Add an annotation when the inferred type is
not the one you want — `using reader: TextReader = new StreamReader(path) { … }` — following the
ordinary variable rule: `:=` infers the type, `=` names it. (`using reader: TextReader := …` is
accepted too, and `nlc format` rewrites it to `=`.) A redundant `let` is accepted —
`using let reader := …` — and means the same thing (`nlc format` drops it).

**Bind to the rest of the enclosing block.** Leave the block off and the resource is released at the
end of the **enclosing** block, in reverse declaration order. It is the shape that keeps deeply
nested cleanup flat:

```n#
func Copy(from: string, to: string) {
    using source := new StreamReader(from)
    using target := new StreamWriter(to)
    target.Write(source.ReadToEnd())
}
// target is released first, then source.
```

**Release something already named.** `using resource { … }` takes an expression instead of a binding,
for a resource that already has a name — or none at all, when the expression is the whole story. A
block is required here: a resource nobody named and nobody scoped would be released at a point the
reader cannot see.

**Release asynchronously.** `await using` releases through `IAsyncDisposable.DisposeAsync()` instead
of `IDisposable.Dispose()`, and is written wherever `await` is legal.

```n#
async func Send(): Task {
    await using client := new HttpClient() {
        await client.GetStringAsync("https://example.com")
    }
}
```

#### The rules

- **The resource must be releasable.** Its type either implements `IDisposable` (`IAsyncDisposable`
  for `await using`) or declares a parameterless `Dispose` (`DisposeAsync`) of its own. Anything else
  is [NL333](https://schneidenbach.github.io/nsharplang/docs/errors/NL333).
- **The resource is read-only for as long as it is visible.** Rebinding the name is
  [NL309](https://schneidenbach.github.io/nsharplang/docs/errors/NL309) — the statement has to still be holding
  what it promised to release. Writing *through* the resource is ordinary mutation and stays legal.
- **A null resource is skipped, not crashed on.** `using x := MightReturnNull() { … }` runs its body
  and releases nothing.
- **A struct resource is released through its own address**, never through a box, so a `Dispose` that
  mutates the value mutates the value the statement is holding. (As in C#, the unbound
  `using someStructLocal { … }` holds a COPY of that local — the statement captures its resource when
  it begins — so bind the resource with `using r := …` when the release has to be observable
  afterwards.)
- **An exception from the release propagates.** A `finally` is not a `catch`.
- `using` works inside generators, async functions, lambdas and local functions. Inside a generator,
  the release runs when the enumeration ends — by completion, by an exception, or because the
  consumer stopped early — and never when the generator merely suspends at a `yield`. A generator
  body is the one place two shapes are refused: a STRUCT resource and `await using`
  ([why](./functions.md)).

#### One thing to watch: object initializers

A `{` immediately after the resource opens the **body**, so an object initializer in that position
has to be parenthesised:

```n#
using widget := (new Widget { Name: "a" }) {
    widget.Run()
}
```

### `lock`

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

`nameof` names something; it does not read it. Its target can be a local, a parameter, a type, a
value member, an **event**, or a **method group** — including an overloaded one and a fully qualified
one — and the answer is always the last segment's spelling. A method group inside `nameof` is not the
"method used as a value" mistake (NL411) precisely because nothing is being used as a value:

```n#
class Report {
    Title: string = ""
    event Ready: Action?

    static func Render(title: string): string => title
}

func main() {
    print nameof(Report.Render)   // Render  -- a method group, not a call
    print nameof(Report.Ready)    // Ready   -- an event, not a subscription
    print nameof(Report.Title)    // Title
}
```

`typeof` is also the one type position that accepts `void`. `void` is not a type a binding, field,
parameter or array element can hold, so it is not written anywhere else; `typeof(void)` names
`System.Void`, which is exactly the type a reflected `void` method reports as its return type.

```n#
import System

func Nothing() {
}

func main() {
    reported := typeof(Program).GetMethod("Nothing", new Type[](0))
    print reported.ReturnType == typeof(void)   // True
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

**A conditional test is an attribute, and it runs.** A `test` block lowers to a method, so it takes
attributes the way any other declaration does — and an attribute that derives from xunit's
`FactAttribute` decides, in its own constructor, whether the test runs at all. That is how a test
that needs a prerequisite is written:

```n#
import System
import Xunit

sealed class DockerFactAttribute: FactAttribute {
    public constructor() {
        if Environment.GetEnvironmentVariable("DOCKER_HOST") == null {
            Skip = "Docker is not running"
        }
    }
}

[DockerFact]
test "the container starts" {
    assert StartContainer() != null
}
```

`nlc test` reports that test as `skipped` with the reason the constructor set. The attribute class
may live in any file of the project — it is usually its own — and `Skip` is a property the external
base declares, so setting it is an ordinary assignment.

The compiler attaches its own `[Fact]` **only when the test does not already carry one**. A method
with two `[Fact]`-derived attributes is a discovery error in xunit ("has multiple [Fact]-derived
attributes"), which would drop the test from the run rather than fail it, so the attribute you wrote
is the one the method carries.

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

The same spelling reaches your own project's namespaces — and you only have to write the part
that is not already implied by where you are. The **leftmost segment** of a qualified name is looked
up the same way a bare name is: your own namespace first, then each enclosing one outward. So from
inside `MyApp`, `Models.Person` means `MyApp.Models.Person`:

```n#
package MyApp

func Create(): Models.Person {
    return Models.Person.Default          // same declaration as MyApp.Models.Person.Default
}
```

That shorthand is *lexical*, never imported: an `import` brings a namespace's **types** into your
file, not its sub-namespaces. `import System` does not make `Reflection.TypeInfo` a name.

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

An alias **adds** a name; it does not take one away. This is the one place N# differs from C#'s
`using Txt = System.Text;`, which binds the alias and nothing else: `import System.Text as Txt` is
still an import of `System.Text`, so `new StringBuilder()` keeps working beside `new Txt.StringBuilder()`.
The two spellings name the same type everywhere a type can be written — a field, a parameter, a
return type, a local annotation — so this compiles:

```n#
import System.Text as Txt

package MyApp

class Report {
    qualified: Txt.StringBuilder = new StringBuilder()
    bare: StringBuilder = new Txt.StringBuilder()
}
```

Because the plain import is still there, [NL010](errors/NL010.md) keeps an aliased import alive when
*either* spelling is written, and reports it only when neither is.

An import is "used" when something in the file **bound through it** — the compiler records which
namespace supplied each name as the name resolves, so a type, a static receiver, an attribute, a
delegate spelling and an extension method's declaring namespace all count, and a name written in FULL
(`System.Text.StringBuilder`) counts for nothing because it needs no import. The mirror of that same
fact is [NL002](errors/NL002.md): a name whose supplying namespace you did not import.

### Which declaration a bare name means

A bare name is resolved in this order, and the first channel that answers wins:

1. **Your file's own namespace.** A type declared alongside you is what the name means, whatever
   your imports bring in. Files that share a namespace see each other's types with no import.
2. **Each enclosing namespace, outward** — `App.Models.Internal` then looks in `App.Models`, then
   `App`, then the global namespace. An exported declaration out there is *nearer* than anything you
   imported, so it wins outright and there is nothing to disambiguate. This is why a file in
   `App.Models` reads a bare `Person` as `App.Person` when `App` declares one, even with
   `import System` in scope.
3. **Your imports, in the order you wrote them** — a source namespace and a .NET namespace count
   equally here. If two imports supply the same name, that is [NL209](errors/NL209.md): neither is
   closer, so the compiler asks you to say which one you mean. "Equally" is literal: two *referenced
   assembly* namespaces that both declare `Range` tie exactly as two of your own namespaces would,
   and so does one of yours against one of theirs. The tie is reported wherever the name is written —
   an annotation, a `new`, a type argument, a `typeof`, an `is`/`as`, a static receiver, or an
   attribute's brackets.
4. **Project-wide auto-discovery.** An exported type anywhere in your project is usable by its bare
   name without an import, as long as exactly one declaration has that name. This is a convenience,
   so it ranks *below* anything you imported explicitly — a `class Version` of your own in a
   namespace you never imported does not take the name `Version` away from `import System`.
5. **The referenced assemblies**, by simple name.

Steps 1 and 2 are the *lexical* half of the rule: they are about where your file sits, not about
what it asked for. Everything after them is about what the file asked for. A **sibling** namespace is
not lexical — `App.Ast` neither contains nor is contained by `App.Columnar` — so it reaches you only
through an import and competes at step 3 like any other.

When two declarations tie, or when auto-discovery picks up a name you did not mean, write the
qualified name. It is never ambiguous.

Diagnostics follow the same rule in reverse: when a type mismatch is between two different types that
share a simple name, both are printed with their namespaces — "expected `System.Range` but got
`OmniSharp.Extensions.LanguageServer.Protocol.Models.Range`" — rather than the contradiction that
printing the simple name twice would produce.

## Visibility

N# uses Go-style naming conventions for visibility — do not write `public`/`private` keywords for ordinary code. The formatter removes redundant `public`/`private` when casing already expresses the same visibility.

| Convention | Visibility |
|------------|-----------|
| `PascalCase` | exported/public |
| `camelCase` | namespace-private |

```n#
class Account {
    Balance: decimal      // exported/public (PascalCase)
    accountId: string     // namespace-private (camelCase)

    func Deposit(amount: decimal) { }   // exported/public
    func validate() { }                  // namespace-private
}
```

### The unit of privacy is the namespace, not the file

A `camelCase` name — a class member, a top-level `func`, a top-level type — is visible to **every
file that declares the same namespace** and to nothing outside it. N# has no file-private tier:
splitting one namespace across many files is the ordinary way to write it, so two halves of a
namespace must be able to see each other's helpers.

```n#
// FILE Format.nl
namespace App.Ast

func formatTypeRef(t: TypeReference): string {
    return t.Name
}
```

```n#
// FILE Render.nl — same namespace, different file, no import needed
namespace App.Ast

import System.Collections.Generic
import System.Linq

func Render(refs: List<TypeReference>): List<string> {
    return refs.Select(formatTypeRef).ToList()
}
```

Reaching `formatTypeRef` from a *different* namespace is [NL308](errors/NL308.md) — an `import`
does not buy access to what a namespace did not export. Rename it to `FormatTypeRef` to publish it.

In CLR metadata a `camelCase` top-level function is emitted `assembly` (internal) and a
`PascalCase` one `public`. The namespace boundary is a *language* rule enforced by the compiler, in
the same way C#'s `private` is a language rule inside one assembly.

### One type name per namespace, however many files it is spread over

A namespace spread over many files is still one namespace, so a type name may be declared **once** in
it. Two files that each declare `class Widget` under `namespace Catalog` are two declarations of one
identity — on the CLR a type IS its namespace, its name and its generic arity — and that is
[NL339](errors/NL339.md), reported at the second declaration with the first one's file and line.

```n#
// FILE Widgets.nl
namespace Catalog

class Widget { }
```

```n#
// FILE Parts.nl
namespace Catalog

class Widget { }          // ERROR NL339: already declared at Widgets.nl:3
```

A different **arity** is a different type, so `Widget` and `Widget<T>` may sit side by side — in one
file or across two — and a different namespace is a different scope. The same name twice in ONE file
is [NL306](errors/NL306.md).

### Explicit accessibility words

Explicit modifiers are narrow .NET interop escape hatches, not the normal way to express visibility. When they override casing, the formatter preserves them because dropping them would change the exported API:

```n#
class Service {
    public legacyCamel: string      // forced public for interop
    private SecretPascal: string    // forced hidden despite PascalCase
    internal ConnectionString: string
    protected BaseUrl: string
}
```

A written word is enforced, not decoration. On a **type member** it means what it means everywhere
else on .NET, and it reaches CLR metadata unchanged:

| Written on a member | Reachable from | Emitted as |
|---|---|---|
| `public` | anywhere | `public` |
| `internal` | the assembly being compiled | `assembly` |
| `protected` | the declaring type and the types that derive from it | `family` |
| `protected internal` | either of the two above | `famorassem` |
| `private protected` | a deriving type in the same project | `famandassem` |
| `private` | the declaring type only | `private` |

`protected` carries C#'s receiver rule as well (§7.5.4): inside a deriving type you may read
`this.Member`, a bare `Member`, `base.Member` and `other.Member` where `other` is of *your* type —
but not through a receiver typed as the base, because at run time that value could belong to some
other type in the family. Reaching past any of these is [NL308](errors/NL308.md).

```n#
class Seeded {
    protected Seed: int = 3
}

class Grower: Seeded {
    func Mine(): int { return this.Seed + Seed + base.Seed }   // all three fine
    func Sibling(other: Grower): int { return other.Seed }     // fine
    func Theirs(other: Seeded): int { return other.Seed }      // NL308
}
```

### A free function's visibility

A top-level `func` has no containing user type, so `private` on one cannot mean "this type only".
At namespace scope there are exactly **two** answers, and a written word overrides the casing:

| Written on a `func` | Meaning | Emitted as |
|---|---|---|
| `public` | exported from the package | `public` |
| *(PascalCase name, no word)* | exported from the package | `public` |
| `internal` | package-private | `assembly` |
| `private` | package-private | `assembly` |
| *(camelCase name, no word)* | package-private | `assembly` |

`assembly` rather than `private` is deliberate: a class of the same package, a lambda's display
class and a local function's closure are each a *different* CLR type, and every one of them may
legally call a package-private function. The package boundary itself is enforced by the compiler,
which reports [NL308](errors/NL308.md) when another namespace names a function its own package
never exported.

Enum cases are part of the containing enum's value set. Export is controlled by the enum itself, so lowercase enum cases remain visible when the enum is exported; use casing diagnostics as style guidance, not as API hiding.

### A referenced assembly's internals: `InternalsVisibleTo`

Everything above is about *your* code. A **referenced** assembly's `internal` types and members are
normally invisible to you — they are not names your program can spell. The one exception is the
CLR's own friend rule: an assembly can declare

```csharp
[assembly: InternalsVisibleTo("MyLibrary.Tests")]
```

and a project whose `project.yml` carries `name: MyLibrary.Tests` then sees that assembly's
`internal` types, and the `internal` members of its public types, exactly as its own code does:

```n#
namespace MyLibrary.Tests

import MyLibrary.Internals

func Reads(): int {
    state := new InternalCounter(7)   // an `internal` type of the granting reference
    return state.Reading()            // ...and an `internal` member of a public one
}
```

Nothing about the call changes: the compiler emits the same instruction a public member gets, and
the CLR re-checks the grant when it loads your assembly. The match is on your assembly's **whole
simple name**, without regard to case; a strong-name key after a comma is ignored, and a name that
merely resembles the granted one (`MyLibrary.Tests.Unit`, `MyLibrary.Test`) is not a friend. Without
a grant those names stay [NL301](errors/NL301.md) / [NL201](errors/NL201.md).

N# cannot yet WRITE such a declaration — an N# library has no way to make another assembly its
friend — so this rule is about consuming grants from assemblies compiled elsewhere. One gap remains
on the refusing side: a **fully qualified** spelling of an internal type is not reported by the
analyzer today (unresolved dotted names are deliberately lenient), so without a grant it reaches
emission rather than `NL301`. Write the bare name under an `import` to get the diagnostic.

## Next Steps

- **[For Go Developers](for-go-developers.md)** — How Go concepts map to N#
- **[Pattern Matching Guide](pattern-matching.md)** — Deep dive into pattern matching
- **[Types Guide](types.md)** — Advanced type system features
- **[Systems N#](systems.md)** — The high-performance lane: `[hot]`, `Result<T,E>`, spans, SIMD
- **[Examples](/examples/)** — curated example projects
