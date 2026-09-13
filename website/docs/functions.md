---
sidebar_label: Functions
title: Functions
---

# Functions in N#

This guide covers functions, lambdas, async programming, and advanced function features in N#.

## Table of Contents

- [Basic Functions](#basic-functions)
- [Function Parameters](#function-parameters)
- [Return Types](#return-types)
- [Lambda Expressions](#lambda-expressions)
- [Async Functions](#async-functions)
- [Generic Functions](#generic-functions)
- [Expression-Bodied Members](#expression-bodied-members)
- [Local Functions](#local-functions)

## Basic Functions

Functions are declared with the `func` keyword:

```n#
func greet(name: string) {
    Console.WriteLine($"Hello, {name}!")
}

func add(a: int, b: int): int {
    return a + b
}
```

Functions that return a value must declare that return type. Omitting the return type means the function returns `void`.

### Visibility

Functions follow N#'s convention-based visibility:

```n#
// Public function (PascalCase)
func ProcessData(input: string): string {
    return input.ToUpper()
}

// Private function (camelCase)
func validateInput(input: string): bool {
    return !string.IsNullOrEmpty(input)
}

// Interop escape hatches when a .NET boundary really needs them
internal func InternalMethod() { }
protected func ProtectedMethod() { }

// Do not write public/private in ordinary N#; casing carries that meaning.
```

## Function Parameters

### Basic Parameters

```n#
func calculate(x: int, y: int, operation: string): int {
    return match operation {
        "add" => x + y,
        "subtract" => x - y,
        "multiply" => x * y,
        _ => 0
    }
}
```

### Optional Parameters

```n#
func greet(name: string, greeting: string = "Hello"): string {
    return $"{greeting}, {name}!"
}

// Usage
message1 := greet("Alice")              // "Hello, Alice!"
message2 := greet("Bob", "Hi")          // "Hi, Bob!"
```

Enum members are compile-time constructor defaults too. The enum owner is bound
where the constructor is declared, so imports at a call site cannot change it.

```n#
enum DeliveryMode {
    Standard,
    Express
}

class Quote {
    Mode: DeliveryMode

    constructor(mode: DeliveryMode = DeliveryMode.Standard) {
        this.Mode = mode
    }
}
```

### Params Arrays

```n#
func sum(params numbers: int[]): int {
    total := 0
    for num in numbers {
        total += num
    }
    return total
}

// Usage
result1 := sum(1, 2, 3)           // 6
result2 := sum(1, 2, 3, 4, 5)     // 15
```

### Params Collections

N# supports params with any collection type:

```n#
func process(params items: List<string>) {
    for item in items {
        Console.WriteLine(item)
    }
}

func analyze(params data: IEnumerable<int>): int {
    return data.Sum()
}
```

### Ref and Out Parameters

```n#
func tryParse(input: string, out result: int): bool {
    return int.TryParse(input, out result)
}

func increment(ref value: int) {
    value += 1
}

// Usage
x: int
if tryParse("42", out x) {
    Console.WriteLine($"Parsed: {x}")
}

count := 10
increment(ref count)
Console.WriteLine(count)  // 11
```

## Return Types

### Explicit Return Types

```n#
func getAge(): int {
    return 25
}

func getName(): string {
    return "Alice"
}

func isValid(): bool {
    return true
}
```

### Void Functions

Functions without a return type implicitly return void:

```n#
func printMessage(msg: string) {
    Console.WriteLine(msg)
}
```

Returning a value from a void function is an error:

```n#
func answer() {
    return 42
}
```

Write `func answer(): int` when the function should return `42`.

### Nullable Return Types

```n#
func findUser(id: int): User? {
    user := database.Find(id)
    return match user {
        null => null,
        _ => user
    }
}
```

### Multiple Return Values (Tuples)

```n#
func getDimensions(): (int, int) {
    return (1920, 1080)
}

// Usage
(width, height) := getDimensions()
Console.WriteLine($"{width}x{height}")
```

#### Named Tuple Elements

Name the elements to read them back by name instead of by position. The names are part of the
declared type, so callers can use either the names or positional deconstruction:

```n#
func minMax(values: int[]): (Min: int, Max: int) {
    low := values[0]
    high := values[0]
    for i := 1; i < values.Length; i++ {
        if values[i] < low {
            low = values[i]
        }
        if values[i] > high {
            high = values[i]
        }
    }
    return (low, high)
}

bounds := minMax([3, 1, 4])
Console.WriteLine($"{bounds.Min}..{bounds.Max}")   // by name

low, high := minMax([3, 1, 4])                     // or by position
```

Named tuple returns work the same way on free functions, static methods and instance methods:

```n#
class Sample {
    static func range(values: int[]): (Min: int, Max: int) => minMax(values)

    func shifted(values: int[], offset: int): (Min: int, Max: int) {
        bounds := minMax(values)
        return (bounds.Min + offset, bounds.Max + offset)
    }
}
```

A named tuple is a `System.ValueTuple` at the CLR level, so the underlying fields are still
`Item1` / `Item2` — `bounds.Min` and `bounds.Item1` are the same field.

#### Named Tuple Elements Across Assemblies

The names are not erased. Because a named tuple has no CLR identity of its own, every .NET language
records its element names in a `System.Runtime.CompilerServices.TupleElementNamesAttribute` on the
signature POSITION — the return parameter, a parameter, a field, a property — and N# both writes and
reads that attribute. So the names survive the assembly boundary in both directions:

- A **C# consumer of an N# library** sees `(int Min, int Max)`, not a bare `ValueTuple<int, int>`.
- **N# reading a C# library** resolves the C# side's declared names, so
  `SimdReductions.MinMaxInt32(...).Min` works as well as `.Item1` does.

The attribute is written for every position a named tuple appears in, including nested tuples and
tuples inside a generic argument, and it is omitted entirely when nothing is named:

```n#
func pair(): (Min: int, Max: int)                 // Min, Max
func nested(): (A: int, D: (B: int, C: int))      // A, D, B, C — the outer names come first
func inGeneric(): List<(Min: int, Max: int)>      // Min, Max
func positional(): (int, int)                     // no attribute at all
```

Element names are metadata, not identity — exactly as in C#. `(Min: int, Max: int)` and `(int, int)`
are the same type, a value flows freely between them, and a name mismatch is never an error:

```n#
let bounds: (int, int) = minMax([3, 1, 4])        // fine: names are not part of the type
let renamed: (Low: int, High: int) = minMax([3, 1, 4])
```

#### Naming Is Per Element

Names are chosen one element at a time, in a tuple type and in a tuple literal alike — there is no
"name all of them or none" rule:

```n#
func parsePart(parts: string[]): (string?, string, IsConstructor: bool) {
    last := parts[parts.Length - 1]
    return (null, last, IsConstructor: true)      // two positional elements, one named
}

row := parsePart(["System", "Ctor"])
Console.WriteLine($"{row.Item2} {row.IsConstructor}")
```

The `TupleElementNamesAttribute` records a positional element as an empty slot, so the shape above is
written `[null, null, "IsConstructor"]` — the same array a C# `(string?, string, bool IsConstructor)`
produces.

An element written `null` takes its type from the surrounding annotation, so the literal above is a
`(string?, string, bool)` rather than a tuple with an untyped first element. A tuple also converts to
another tuple element by element, wherever every element's conversion is one the CLR spells as
identity — names erased, and a nullable annotation over a reference type erased — so
`("a", "b", IsConstructor: true)` fits a declared `(string?, string, IsConstructor: bool)`. A
conversion that would have to rebuild the tuple (`(int, int)` to `(long, long)`, `(string, string)` to
`(object, object)`) is not performed.

A name the literal writes that the target type does not have is a label on that literal and nothing
more — the value's type is the declared one, and a mismatch is never an error, exactly as with a
mismatched variable annotation above.

Two limits remain. A **field or property** may not itself be declared with a tuple type; locals,
parameters, return types and generic arguments all accept one. And an element read straight **out of
an indexer** is positional: `rows[0].Item1` compiles where `rows[0].Item` does not, even though
`rows` is a `List<(Item: string, Count: int)>` and the names are on its declaration — bind the
element to a name first (`row := rows[0]` is not enough; annotate it, `row: (Item: string, Count:
int) = rows[0]`) or use `ItemN`.

## Lambda Expressions

### Basic Lambda Syntax

```n#
// Single parameter
squared := numbers.Select(x => x * x)

// Multiple parameters
sum := values.Aggregate((acc, x) => acc + x)

// No parameters
getMessage := () => "Hello, World!"
```

### Lambda with Block Body

```n#
process := items.Select(item => {
    processed := item.Trim().ToUpper()
    return $"Processed: {processed}"
})
```

### Type Inference in Lambdas

A lambda written without parameter types takes them from the delegate it is passed to. When the
method being called is generic, that delegate is itself part of what the call is inferring, and N#
resolves the two together the same way C# does — in two phases.

**Phase one fixes what the other arguments fix.** The receiver counts, and so does every argument
that already has a type of its own:

```n#
// `values` is a `List<string>`, so `Count<TSource>`'s `TSource` is `string`,
// and the predicate's parameter is a `string` before its body is read.
values.Count(value => value.Length > 0)
```

**Phase two reads each lambda whose parameter types are now known**, and that lambda's RESULT fixes
whatever type parameter stands in the delegate's return position:

```n#
// `word.Length` is an `int`, so `Select<TSource, TResult>`'s `TResult` is `int`
// and the call's own type is `IEnumerable<int>`.
words.Select(word => word.Length)
```

The two phases repeat until nothing changes, so one lambda may fix a type parameter that a later
lambda's parameters depend on. Each lambda folds into **its own** position — two lambdas fix two
different type parameters:

```n#
// `TKey` comes from the first lambda, `TElement` from the second:
// the result is a `Dictionary<string, int>`.
names.ToDictionary(name => name, name => name.Length)
```

A lambda whose parameter types are still unknown when the phases stop is an error
([`NL203`](./errors/NL203.md)) that names the parameter. Give it a typed home, or pass it where a
delegate type is expected:

```n#
handler: Func<int, int> = value => value + 1    // fine
stray := value => value + 1                     // ERROR NL203
```

The rules are not special to LINQ. Every generic method with a delegate parameter participates —
your own functions included — and a `Func<...>`, an `Action<...>`, a user-written delegate and an
`Expression<Func<...>>` all name the same signature:

```n#
func Apply<T, R>(items: List<T>, projection: Func<T, R>): List<R> {
    mapped := new List<R>()
    for item in items {
        mapped.Add(projection(item))
    }

    return mapped
}

lengths := Apply(words, word => word.Length)    // List<int>
```

**A method group is a lambda with its signature already written.** It folds into exactly the same
two positions, so anywhere a lambda is accepted a named function of the right shape is too:

```n#
func IsLong(value: string): bool => value.Length > 3

longOnes := words.Where(IsLong)
counted := words.Count(IsLong)
```

A method group may name a **method of the type you are writing in** — a static one from any of that
type's bodies, an instance one wherever `this` exists — and not only a top-level `func`:

```n#
class Symbols {
    static func Format(name: string): string => "<" + name + ">"

    static func FormatAll(names: List<string>): List<string> {
        return names.Select(Format).ToList()
    }
}
```

When the name has **several overloads**, the delegate the position wants picks one: exactly one
applicable method converts, and two is an ambiguity rather than a choice. A group whose parameter
admits more than the delegate's does still converts — a `func Format(name: string?)` is a
`Func<string, string?>`, because a parameter that admits null admits everything a non-null one does.

### Any delegate type, not only `Func` and `Action`

A lambda converts to **whatever delegate type the position names**, and its `Invoke` is where that
signature is read from — the delegate's name is no part of the rule. Event-handler delegates,
`Predicate<T>`, `Comparison<T>`, `Converter<T, R>`, `EventHandler<T>` and a delegate a referenced
assembly declares all work the same way, in a declared local, at a delegate-typed parameter, and as a
constructor argument:

```n#
import System

cancelHandler: ConsoleCancelEventHandler = (sender, eventArgs) => {
    eventArgs.Cancel = true
}

ordering: Comparison<int> = (left, right) => right - left
Array.Sort(values, ordering)
Array.Sort(values, (left, right) => right - left)

longEnough: Predicate<string> = value => value.Length > 2
first := words.Find(longEnough)
```

A method group converts at exactly the same positions, by the same rule. N# has no `delegate`
declaration of its own: write `Func<...>` / `Action<...>` for a signature you name yourself, and use a
referenced assembly's delegate types where they are part of an API you are calling.

**A member that cannot be called does not hide a method of the same name.** `List<T>.Count` is an
`int` property and `Enumerable.Count<TSource>` is an extension method; only the second is
invocable, so both spellings mean what they say:

```n#
total := words.Count                        // the property
nonEmpty := words.Count(w => w.Length > 0)  // the extension
```

Writing `()` after a member whose value is not a delegate is [`NL413`](./errors/NL413.md).

```n#
// Explicit types
convert := items.Select((string s) => int.Parse(s))
```

### Lambda Without Parentheses (Single Parameter)

```n#
// Single parameter can omit parentheses
filtered := items.Where(x => x > 10)
mapped := names.Select(name => name.ToUpper())
```

## Async Functions

### Basic Async Functions

Declare async functions with the `async` keyword:

```n#
async func fetchData(url: string): string {
    client := new HttpClient()
    result := await client.GetStringAsync(url)
    return result
}
```

### Async with Task<T>

```n#
async func processFile(path: string): Task<string> {
    content := await File.ReadAllTextAsync(path)
    return content.ToUpper()
}
```

Explicit `Task<T>` signatures use task-like async return semantics: return the `T`
value from the body and N# wraps it in `Task<T>`. Explicit `Task` signatures
are unit-returning async methods, so no `return` statement is required after the
last `await`.

```n#
async func save(path: string, content: string): Task {
    await File.WriteAllTextAsync(path, content)
}
```

### Async with ValueTask<T>

```n#
async func getValue(): ValueTask<int> {
    // ValueTask is optimized for synchronous completion
    await Task.Delay(100)
    return 42
}
```

### Async Void

```n#
// Only for event handlers
async func onButtonClick() {
    await Task.Delay(1000)
    Console.WriteLine("Clicked!")
}
```

### Implicit Task Wrapping

N# automatically wraps return values in Task<T>:

```n#
async func getUser(id: int): User {
    // Compiler wraps User in Task<User>
    user := await database.FindAsync(id)
    return user
}
```

### Async LINQ

```n#
async func processItems(items: List<string>): List<int> {
    results := new List<int>()
    for item in items {
        value := await fetchValueAsync(item)
        results.Add(value)
    }
    return results
}
```

### Async Streams (IAsyncEnumerable)

```n#
async func* generateNumbers(count: int): IAsyncEnumerable<int> {
    for i := 0; i < count; i += 1 {
        await Task.Delay(100)
        yield i
    }
}

// Usage
await foreach num in generateNumbers(10) {
    Console.WriteLine(num)
}
```

## Generic Functions

### Basic Generic Functions

```n#
func identity<T>(value: T): T {
    return value
}

func createList<T>(): List<T> {
    return new List<T>()
}
```

### Multiple Type Parameters

```n#
func pair<T, U>(first: T, second: U): (T, U) {
    return (first, second)
}

// Usage
result := pair<string, int>("age", 25)
```

### Generic Constraints

```n#
func process<T>(item: T): string where T : IFormattable {
    return item.ToString()
}

func compare<T>(a: T, b: T): bool where T : IComparable<T> {
    return a.CompareTo(b) == 0
}
```

When the type argument is a **value type** (a `struct`), calls to a constrained
interface method dispatch through a `constrained.` prefix — the receiver is **not
boxed**, so there is no heap allocation and the struct's own method is invoked
directly:

```n#
interface Shape {
    func Area(): int
}

struct Square : Shape {
    side: int
    func Area(): int => side * side
}

func totalArea<T>(s: T): int where T : Shape {
    return s.Area()   // dispatched without boxing when T is Square
}

totalArea(new Square { side: 3 })   // 9
```

This holds even when the called method is inherited from a **base interface** of
the constraint. Given `interface Shape : HasArea`, a function constrained to
`T : Shape` can still call the inherited `Area()` without boxing:

```n#
interface HasArea { func Area(): int }
interface Shape : HasArea { func Name(): string }

struct Square : Shape {
    side: int
    func Area(): int => side * side
    func Name(): string => "square"
}

func totalArea<T>(s: T): int where T : Shape => s.Area()   // resolves HasArea.Area
```

### Multiple Constraints

```n#
func serialize<T>(obj: T): string
    where T : class, ISerializable, new() {
    // Implementation
    return JsonSerializer.Serialize(obj)
}
```

## Expression-Bodied Members

### Expression-Bodied Functions

Use `=>` for single-expression functions:

```n#
func double(x: int): int => x * 2

func getFullName(first: string, last: string): string =>
    $"{first} {last}"

func isEven(n: int): bool => n % 2 == 0
```

### Expression-Bodied Properties

```n#
class Person {
    FirstName: string
    LastName: string

    // Expression-bodied property
    FullName: string => $"{FirstName} {LastName}"
}
```

### Expression-Bodied with Match

```n#
func getStatus(code: int): string => match code {
    200 => "OK",
    404 => "Not Found",
    500 => "Server Error",
    _ => "Unknown"
}
```

## Local Functions

Define functions inside other functions:

```n#
func processData(input: string): string {
    // Local function
    func validate(s: string): bool {
        return !string.IsNullOrEmpty(s)
    }

    // Local function with closure
    func transform(s: string): string {
        prefix := "Processed"  // Captures from outer scope
        return $"{prefix}: {s}"
    }

    if !validate(input) {
        return "Invalid"
    }

    return transform(input)
}
```

### Async Local Functions

```n#
async func orchestrate(): Task<int> {
    async func fetchAsync(id: int): Task<string> {
        await Task.Delay(100)
        return $"Item {id}"
    }

    result1 := await fetchAsync(1)
    result2 := await fetchAsync(2)

    return result1.Length + result2.Length
}
```

### Generic Local Functions

```n#
func createProcessor() {
    func process<T>(value: T): string {
        return value.ToString()
    }

    x := process<int>(42)
    y := process<string>("hello")
}
```

## Function Overloading

### Basic Overloading

```n#
func print(value: int) {
    Console.WriteLine($"Int: {value}")
}

func print(value: string) {
    Console.WriteLine($"String: {value}")
}

func print(value: double) {
    Console.WriteLine($"Double: {value}")
}
```

### Overloading with Different Parameter Counts

```n#
func create(name: string): User {
    return new User { Name: name }
}

func create(name: string, age: int): User {
    return new User { Name: name, Age: age }
}
```

## Extension Methods

Define extension methods using static classes:

```n#
static class StringExtensions {
    func Truncate(this value: string, maxLength: int): string {
        if value.Length <= maxLength {
            return value
        }
        return value.Substring(0, maxLength) + "..."
    }
}

// Usage
text := "This is a long string"
short := text.Truncate(10)  // "This is a..."
```

### Calling an extension method

An extension call is resolved the way C# resolves one. The receiver's static type is converted to
the `this` parameter's type by the ordinary assignability relation, and the method's type arguments
are then inferred from the receiver and from the arguments. That is one rule, and it is why the
receiver can be almost anything:

```n#
import System.Collections.Generic
import System.Linq

class Query {
    Name: string
    constructor(name: string) {
        Name = name
    }
}

func examples(items: List<Query>, words: string[], text: string, map: Dictionary<string, int>) {
    items.First().Name          // List<Query> is an IEnumerable<Query>
    words.Count()               // an array is a sequence of its element
    text.Count(c => c == 'a')   // a string is a sequence of its characters
    map.Sum(pair => pair.Value) // a dictionary is a sequence of its pairs
}
```

The element type may be a type your own project declares — `List<Query>` above is an
`IEnumerable<Query>` exactly as `List<string>` is an `IEnumerable<string>`.

A lambda argument is typed by the parameter it is passed to, so the compiler chooses the method
first and types the lambda afterwards. A method group works wherever a lambda does.

### Writing the type arguments out

Some extensions declare a type argument that nothing in the call could infer — `Cast<T>` names the
type you are casting TO, and `Deserialize<T>` names the type you are parsing INTO. Write it:

```n#
import System.Collections
import System.Linq
import System.Text.Json

func typed(values: IEnumerable, element: JsonElement): int {
    names := values.Cast<string>().ToList()
    weight := element.Deserialize<int>()
    return names.Count + weight
}
```

Explicit type arguments SKIP inference: a candidate whose own type-parameter count differs from the
number you wrote is not a candidate at all, so writing too many or too few reports "no such method"
rather than closing the wrong one. The receiver may be a value type (`JsonElement` above) — an
extension's receiver is its first argument, so the struct's value is passed, never its address.

### Extensions over a type parameter

A type parameter constrained to an interface IS that interface for an extension call:

```n#
import System.Collections.Generic
import System.Linq

func CountOf<T>(items: T): int where T: IEnumerable<string> {
    return items.Count()
}
```

A member the CONSTRAINT itself declares wins over an extension of the same name, which is the same
precedence an ordinary receiver keeps. The constraint types a **lambda argument** at such a call too,
because the receiver it fixes is what the call's own type parameters are inferred from:

```n#
func WidestOf<T>(items: T): int where T: IEnumerable<string> {
    return items.Max(item => item.Length)     // `item` is a `string`
}
```

**One** constraint answers. A type parameter with two of them keeps its own member surface, because
choosing between the two would be a guess; write the call on a concrete receiver, or take
`IEnumerable<string>` directly, when you need one.

## Best Practices

### 1. Use Expression-Bodied Members for Simple Functions

```n#
// Good
func double(x: int): int => x * 2

// Less concise
func double(x: int): int {
    return x * 2
}
```

### 2. Prefer Async/Await Over .ContinueWith

```n#
// Good
async func fetchAndProcess(): string {
    data := await fetchDataAsync()
    return processData(data)
}

// Avoid
func fetchAndProcess(): Task<string> {
    return fetchDataAsync().ContinueWith(t => processData(t.Result))
}
```

### 3. Use Local Functions for Helper Logic

```n#
func processOrders(orders: List<Order>): List<OrderResult> {
    func isValid(order: Order): bool {
        return order.Total > 0 && order.Items.Count > 0
    }

    return orders
        .Where(isValid)
        .Select(o => new OrderResult { Id: o.Id, Status: "Processed" })
        .ToList()
}
```

### 4. Use Pattern Matching in Functions

```n#
func getDiscount(customerType: string): double => match customerType {
    "Premium" => 0.20,
    "Gold" => 0.15,
    "Silver" => 0.10,
    _ => 0.0
}
```

## Complete Example

Here's a complete example demonstrating various function features:

```n#
import System
import System.Linq
import System.Threading.Tasks
import System.Collections.Generic

package FunctionExample

class DataProcessor {
    // Expression-bodied property
    IsReady: bool => data != null

    data: List<string>

    constructor() {
        data = new List<string>()
    }

    // Basic function
    func addItem(item: string) {
        data.Add(item)
    }

    // Function with optional parameter
    func getItems(filter: string = ""): List<string> {
        if string.IsNullOrEmpty(filter) {
            return data
        }
        return data.Where(d => d.Contains(filter)).ToList()
    }

    // Generic function
    func transform<T>(mapper: Func<string, T>): List<T> {
        return data.Select(mapper).ToList()
    }

    // Async function
    async func processAsync(): Task<int> {
        async func validateAsync(item: string): Task<bool> {
            await Task.Delay(10)
            return !string.IsNullOrEmpty(item)
        }

        count := 0
        for item in data {
            if await validateAsync(item) {
                count += 1
            }
        }
        return count
    }

    // Expression-bodied function
    func getCount(): int => data.Count
}

// Extension method
static class Extensions {
    func Double(this value: int): int => value * 2
}

func main() {
    processor := new DataProcessor()
    processor.addItem("apple")
    processor.addItem("banana")
    processor.addItem("cherry")

    // Lambda expressions
    lengths := processor.transform<int>(s => s.Length)
    Console.WriteLine($"Lengths: {string.Join(", ", lengths)}")

    // Async
    count := await processor.processAsync()
    Console.WriteLine($"Valid items: {count}")

    // Extension method
    x := 5
    doubled := x.Double()
    Console.WriteLine($"Doubled: {doubled}")
}
```

## Next Steps

- **[Types Guide](types.md)** - Learn about classes, unions, records, and interfaces
- **[Pattern Matching](pattern-matching.md)** - Deep dive into pattern matching
- **[Language Tour: Async/Await](language-tour.md#asyncawait)** - Async functions and streams
- **[Systems N#](systems.md)** - `[hot]` functions, `Result<T,E>`, and the performance lane

## Resources

- [Project README](https://github.com/schneidenbach/nsharplang/blob/main/README.md)
- [Examples](/examples/)
