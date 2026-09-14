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

Functions follow N#'s convention-based visibility, and the unit of privacy is the **namespace, not
the file**. A `camelCase` top-level function is visible to every file that declares the same
namespace — splitting a namespace across files is the ordinary way to write one — and to nothing
outside it. Naming it from another namespace is [NL308](errors/NL308.md), whether or not that
namespace imported yours.

```n#
// Public function (PascalCase) — visible everywhere, exported from the assembly
func ProcessData(input: string): string {
    return input.ToUpper()
}

// Namespace-private function (camelCase) — visible to every file of this namespace
func validateInput(input: string): bool {
    return !string.IsNullOrEmpty(input)
}

// Interop escape hatches when a .NET boundary really needs them
internal func InternalMethod() { }
protected func ProtectedMethod() { }

// Do not write public/private in ordinary N#; casing carries that meaning.
```

A second file of the same namespace needs no import and no qualification to call either of them:

```n#
// FILE Validate.nl
namespace App.Text

func validateInput(input: string): bool {
    return !string.IsNullOrEmpty(input)

### Which namespace a free function belongs to

A top-level `func` belongs to the namespace its file declares, exactly as a `class` does. Two files
in **different** namespaces may each declare a `Helper`, and neither hides the other:

```n#
// FILE reporting.nl
namespace Reporting

func Helper(): string {
    return "reporting"
}

func Describe(): string {
    return Helper()          // Reporting.Helper
}
```

```n#
// FILE Process.nl — same namespace, different file
namespace App.Text

import System.Collections.Generic
import System.Linq

func ProcessAll(inputs: List<string>): List<string> {
    return inputs.Where(validateInput).ToList()     // the method group resolves too
}
```


// FILE dashboard.nl
namespace Dashboard

func Helper(): string {
    return "dashboard"
}

func Describe(): string {
    return Helper()          // Dashboard.Helper — a different function
}
```

A bare call is looked up in exactly the order a bare **type** name is
([NL209](./errors/NL209.md) describes the same order):

1. the calling file's own declarations, whatever their casing;
2. the file's own namespace — whatever the casing there, too;
3. each **enclosing** namespace outward, ending at the global namespace — exported declarations only;
4. the file's `import`s, in import order — exported declarations only. Two imports that both supply
   the name is [NL209](./errors/NL209.md), and the file has to drop one of them.

A camelCase top-level function is **namespace-private**: every file that declares the same namespace
reaches it with no import and no export, and no other namespace does — the same rule a camelCase
`class` follows. A visibility word overrides the casing in both directions, as everywhere else in
N# — `public func helper()` is reachable from other namespaces and `internal func Helper()` is not.
Unlike types, a free function is *not* auto-discovered across namespaces — `import` the namespace
that declares it.

### What a free function looks like from .NET

Free functions are emitted as **static methods on a `Program` class inside their own namespace**, so
`func Helper()` in `namespace Reporting` is `Reporting.Program.Helper` and the same spelling in
`namespace Dashboard` is `Dashboard.Program.Helper`. A file that declares no namespace puts its
functions on the global `Program`. A C# consumer calls them the obvious way:

```csharp
var text = Reporting.Program.Helper();
```

Only namespaces that actually declare free functions (or whose bodies need a home for a lifted
lambda) get a holder, so a library does not grow an empty global `Program`.

**Your own `class Program` keeps its name.** If the namespace already declares a type called
`Program`, the holder yields and is spelled `<Program>` instead — a name no N# source can write, so
it is always free. Nothing is rejected, and your type's CLR name is untouched; only the place a C#
consumer reaches the free functions changes.

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

#### Nullability across `out` and `ref`

The two modifiers differ in what the callee is allowed to assume, so they differ in what the caller
has to prove.

An **`out` argument's variable may have any nullability**. The callee has to assign it before it
returns and never reads what was there, so a `string?` variable is a legal `out string` argument —
and after the call the variable holds whatever the PARAMETER says it holds:

```n#
func trySplit(text: string, out head: string, out tail: string): bool { ... }

head: string? = default
tail: string? = default
if !trySplit(line, out head, out tail) {
    return head          // `string` here: the parameter is `out string`, so the callee left one
}
```

A parameter declared `out string?` leaves the variable maybe-null instead, and the caller checks it
as usual.

A **`ref` argument has to match in both directions**, because the callee can read the value as well
as write it. Passing a `string?` variable to a `ref string` parameter is an error (NL202) and so is
the reverse.

Nullability is the only thing `out` forgives. `int?` is `Nullable<int>` and `int` is not, so an
`int?` variable is not an `out int` argument in either spelling.

#### Saying more than the type can

A signature can also declare what it leaves behind, using the standard .NET nullability
postcondition attributes. N# reads them off .NET metadata and off its own declarations:

| Attribute | On | Means |
|---|---|---|
| `[NotNull]` | any parameter | the argument is not null once the call returns, on every path |
| `[MaybeNull]` | an `out`/`ref` parameter | the variable may be null afterwards |
| `[NotNullWhen(b)]` | any parameter | the argument is not null in the branch where the call returned `b` |
| `[MaybeNullWhen(b)]` | any parameter | the argument may be null in the branch where the call returned `b` |

```n#
import System.Diagnostics.CodeAnalysis

func tryLookup(entries: List<Entry>, label: string, [NotNullWhen(true)] out found: Entry?): bool {
    ...
}

found: Entry? = default
if tryLookup(entries, "alpha", out found) {
    return found.Label      // `found` is `Entry` here — the attribute said so
}
```

The branch an attribute does not name keeps whatever the declaration alone already said, which is
what makes the BCL's own spelling work: `Dictionary<K, V>.TryGetValue` declares
`[MaybeNullWhen(false)] out V value`, so the value is present in the `true` branch and maybe-null in
the `false` one. `string.IsNullOrEmpty` declares `[NotNullWhen(false)]`, so its argument is proved
non-null in the branch where it answered `false`:

```n#
func textLength(text: string?): int {
    if string.IsNullOrEmpty(text) {
        return 0
    }

    return text.Length      // `string` here
}
```

These read the same way through `&&` chains, through a negated guard (`if !tryLookup(...) { return }`)
and through a ternary, because they are ordinary flow facts once the call has produced them.

`[DoesNotReturn]` and `[DoesNotReturnIf]` are not read yet: a call to a method that never returns does
not currently end the flow that follows it.

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

### Where a body ends

A non-void function must return on every path. A loop does **not** count as returning, because it may
run zero times — so the `return` after the loop is the one that runs on the empty collection, and it is
required:

```n#
func firstOrFallback(values: List<int>): int {
    for value in values {
        return value
    }

    return -1
}
```

That shape emits: a loop body that never falls through is ordinary. So is the scan loop whose every
path either returns or `continue`s, in all four spellings (`for x in xs`, `for x in array`,
`for c in text`, and the counted `for i := 0; …`).

The one loop whose **end point is unreachable** is the endless one — a `while` whose condition is the
constant `true`, or a `for` with no condition — and only when no reachable `break` targets it. That
loop needs no return after it:

```n#
func attemptsUntil(threshold: int): int {
    attempt := 0
    while true {
        attempt = attempt + 1
        if attempt >= threshold {
            return attempt
        }
    }
}
```

### A signature that never returns

A function that always throws can say so with `[DoesNotReturn]`, and N# believes it: a call to such
a function **ends the path it is written on**, exactly as a `throw` does. The caller below needs no
`return` after the call, and a statement written after one is reported as unreachable (`NL312`).

```n#
import System
import System.Diagnostics.CodeAnalysis

[DoesNotReturn]
func fail(message: string) {
    throw new InvalidOperationException(message)
}

func pick(value: int): string {
    if value > 0 {
        return "positive"
    }

    fail("not positive")
}
```

This is stronger than C#, which reads the attribute only for its nullable analysis and still demands
a `return` after the call.

`[DoesNotReturnIf(bool)]` says the same thing about **one branch**: the call returns only when the
argument took the other value, so the code after it knows what the argument proved. It is a guard
clause the signature spells, and it narrows exactly as `assert` does.

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

Both attributes are read from a signature you declare and from one in a referenced assembly, and both
reach the emitted metadata. The annotation is a **contract**: a member that carries `[DoesNotReturn]`
and returns anyway throws an `InvalidOperationException` naming it, rather than silently falling out
of a function that promised a value.

One limit: at emission the attribute is read for members the project itself declares. A body whose
last statement is a `[DoesNotReturn]` call into a *referenced assembly* still type-checks and is
refused at emission — write a `throw` after it until that surface lands.

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

#### `ValueTuple<...>` Is The Same Type

`System.ValueTuple<T1, T2>` and `(T1, T2)` are one type written two ways, exactly as in C#. Either
spelling may be used in any position, a value flows between them freely, and both answer the same
`System.ValueTuple` at the CLR level:

```n#
let written: ValueTuple<string, int> = ("a", 1)   // the ValueTuple spelling
let tupled: (string, int) = written                // the tuple spelling
let created: (string, int) = ValueTuple.Create("a", 1)
```

Element names are still an annotation on the position, so a `ValueTuple<...>` spelling simply
declares none. `ValueTuple<T>` — a one-element tuple — has no tuple syntax in N# or in C#, and keeps
its `Item1`.

The two spellings are interchangeable in **every** position, including nested inside a generic
argument and in a parameter or a return type:

```n#
func TakeRows(rows: List<ValueTuple<string, int>>): int => rows.Count

func Rows(): List<(string, int)> => new List<(string, int)>()

TakeRows(Rows())                                   // one type, two spellings
```

#### Element Names Are An Annotation, Never An Identity

Because element names have no CLR identity, two tuple types that differ **only** in their names are
one type. A value flows between them in every position — assignment, argument, return, `ref`, `out`,
and a generic argument — and each position keeps reading the names **it** declared:

```n#
func Bump(ref row: (Item: string, Count: int)) {
    row = (row.Item, row.Count + 1)
}

row: (Left: string, Right: int) = ("a", 1)
Bump(ref row)                                      // names differ; the type does not
Console.WriteLine(row.Right)                       // reads the name this position declared

groups := new Dictionary<string, (Item: string, Ranges: List<int>)>()
found: (Label: string, Lines: List<int>) = default
if groups.TryGetValue("k", out found) {
    Console.WriteLine(found.Lines.Count)           // and so does the `out` target
}
```

A tuple **literal** written without names converts to a named tuple type the same way; the names on a
literal are labels on a value, and the value's type is the declared one.

#### Where The Names Reach

A named tuple's element names follow the value wherever the declaring position can be found, not just
where the tuple is written directly:

```n#
rows: List<(Item: string, Count: int)> = new List<(Item: string, Count: int)>()
rows.Add(("c", 3))
Console.WriteLine(rows[0].Item)                   // out of an indexer

groups := new Dictionary<string, (Item: string, Ranges: List<int>)>()
Console.WriteLine(groups["k"].Ranges.Count)       // out of a dictionary's value position
Console.WriteLine(groups.Values.First().Ranges.Count)  // and through a chain that declares nothing

for group in groups.Values {                      // and onto a foreach variable
    Console.WriteLine(group.Item)
}
```

Storing a value in a **local** is not a place a name can be lost, so the same chain broken over
several statements reads exactly as the single expression does — which is what a generated or
translated body usually writes:

```n#
vals := groups.Values                             // declares no names of its own
first := vals.First()
Console.WriteLine(first.Ranges.Count)             // still the dictionary's value names
```

A **generic function's inferred return** is the argument it was inferred from, names and all, because
a tuple type includes its element names:

```n#
func Echo<T>(value: T): T => value

row: (Item: string, Count: int) = ("a", 4)
Console.WriteLine(Echo(row).Count)
```

Two parameter positions declared with the same type parameter cannot say which argument the result
came from, so such a call says nothing and the element is read positionally.

A **field** and a **property** may be declared with a tuple type, and their names are written to
metadata the same way a return's and a parameter's are:

```n#
class Holder {
    Pair: (Item: string, Count: int) = ("", 0)
    Bounds: (Min: int, Max: int) => (3, 9)
}

Console.WriteLine(holder.Pair.Item)
Console.WriteLine(holder.Bounds.Max)
```

A field or property is a **link** in the chain, not a dead end — a value read out of one carries the
names that member's written type declared:

```n#
class GroupHolder {
    Pairs: Dictionary<string, (Item: string, Ranges: List<int>)>
    Rows: (Item: string, Count: int)[]
}

Console.WriteLine(holder.Pairs["k"].Ranges.Count)
Console.WriteLine(holder.Rows[1].Item)
```

An **array** may have a tuple element type, like every other declared position, and its element names
ride on the declaring position just the same:

```n#
rows: (Item: string, Count: int)[] = [("a", 1), ("b", 5)]
rows[1] = ("cd", 7)
Console.WriteLine(rows[1].Item)
```

The one rule that decides all of this: names come from the position that DECLARED them, and a
receiver whose written type mentions the same tuple shape twice with different names cannot say which
position a value came from — that value is read positionally (`ItemN`).

#### Deconstruction

A tuple is unpacked into several names at once. `:=` DECLARES the targets; `=` writes targets that
already exist; `_` discards an element. The parenthesised and bare spellings are the same statement:

```n#
(item, count) := makeRow()        // declares item and count
item, count := makeRow()          // the same statement, written bare
(_, count) := makeRow()           // the first element is discarded

item := ""
count := 0
(item, count) = makeRow()         // writes the two names declared above
```

A type that is not a tuple deconstructs too, when it declares an accessible instance
`Deconstruct(out ...)` whose out-parameter count matches the target count — the rule C# applies. It
holds for a type from a referenced assembly and for one declared here alike, which is what makes a
dictionary walk read the way it should:

```n#
for pair in scores {
    (name, score) := pair          // KeyValuePair<string, int>.Deconstruct
    Console.WriteLine($"{name}: {score}")
}
```

A source that is neither a tuple nor deconstructable reports NL103, and so does a target count that
does not match the element count.

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

A lambda's result fixes the type parameter through whatever the result's type actually **is** — its
interfaces and its base chain included, and whether the type was declared in your project or read out
of a referenced assembly. A `List<TextEdit>` reaches a `Func<T, IEnumerable<TResult>>` because a
`List<T>` is an `IEnumerable<T>`:

```n#
// `Edits` may be a `List<TextEdit>`, an `IReadOnlyList<TextEdit>` or a referenced assembly's own
// collection; `TResult` is `TextEdit` either way.
allEdits := actions.SelectMany(action => action.Edits).ToList()
```

**A lambda with a BLOCK body takes part in phase two the same way**: its result is the type its
`return` statements give, so a block is never a reason to write the type argument out.

```n#
// `TResult` is `Span`, and the call is a `List<Span>` — the `return` inside the block is what
// says so.
spans := names.Select(name => {
    line0 := name.Length
    return new Span(line0, line0 + 1)
}).ToList()
```

Every `return` the block itself executes counts, wherever it is written — inside an `if`, a loop or a
`try` — and the result is the type they all reach: an identical type, the base one when a derived and
a base arm meet, and the others' type when one arm is `null`. A `return` written inside a **nested**
lambda or local function belongs to that body, not to this one. Two arms that share nothing report
the disagreement rather than picking one.

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

This works even when the delegate's **return** position is one of the things still being inferred.
The group's overloads are filtered by the delegate's input types — which the earlier arguments and
the receiver have already fixed — and the one survivor's return type is what the type parameter
takes:

```n#
class Widen {
    static func Of(value: int): long => value * 10
    static func Of(value: string): long => value.Length

    // `TSource` is `int` from the receiver, so `Of(int)` is the overload; its `long` return
    // is what makes the call a `long[]`.
    static func Longs(values: int[]): long[] => values.Select(Of).ToArray()
}
```

A method group may also name a **static method of any type**, including one from a referenced
assembly. The receiver there is a type rather than a value, so the delegate has no target to bind:

```n#
import System.IO

// `Directory.Exists` and `File.Exists` are method groups exactly as your own functions are.
existing := roots.Where(Directory.Exists).ToArray()
isEmpty: Func<string, bool> = String.IsNullOrEmpty
```

A group whose name is overloaded still picks the single applicable overload — `Int32.Parse` as a
`Func<string, int>` is `Parse(string)` — and a generic method (`Array.Empty<T>`) or one with a
`ref`/`out` parameter (`Int32.TryParse`) is not a method group a delegate position can take.

A method group may also be named through a **value**, and then the delegate is bound to that value:
the receiver is the delegate's target, so two receivers give two delegates, and a `virtual` method
binds the one the receiver actually has.

```n#
greeter := new Greeter("hi ")
greet: Func<string, string> = greeter.Greet    // bound to `greeter`
assert greet("bob") == "hi bob"

// Wherever a lambda is accepted, so is a receiver-bound group.
decorated := names.Select(greeter.Greet).ToList()
```

### When two arguments disagree only about `?`

A type parameter met by both `X` and `X?` is fixed to `X?`. The two are not a contradiction: `X`
converts to `X?` and `X?` does not convert back, so the nullable one is the type both arguments
reach — the same rule `flag ? value : null` uses to decide a conditional's type.

```n#
func AssertSame<T>(expected: T, actual: T) { /* ... */ }

severity: Level = Level.Error
reported: Level? = ReadSeverity()

AssertSame(severity, reported)     // T is `Level?`, and `severity` lifts into it
```

This applies wherever the type parameter is inferred, including generic methods declared in a
referenced assembly. It does not weaken the result: the position that was already nullable keeps its
nullability, and the one that was not is the one that widens.

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

The type the delegate is closed over may be **one of your own**, including in a `void`-returning
position. A delegate's shape comes from its own definition, so an instantiation over a class or
struct this compilation is still writing names exactly the signature it says it does:

```n#
class PriceArgs {
    Symbol: string
    Price: int
    constructor(symbol: string, price: int) { Symbol = symbol  Price = price }
}

sink: Action<PriceArgs> = args => {
    print args.Symbol
}

expensive: Predicate<PriceArgs> = args => args.Price > 100
byPrice: Comparison<PriceArgs> = (left, right) => right.Price - left.Price
onChange: EventHandler<PriceArgs> = (sender, args) => {
    print args.Price
}
```

### Calling a delegate held in a member

A delegate stored in a field or a property is called through its owner exactly as a method is — the
name resolves to the delegate's value and the call is that delegate's `Invoke`:

```n#
class Handlers {
    Load: Func<int>
    Map: Func<int, int>
    Doubled: Func<int, int> => Map

    constructor(load: Func<int>, map: Func<int, int>) {
        Load = load
        Map = map
    }
}

func TotalThrough(handlers: Handlers): int {
    return handlers.Load() + handlers.Map(4) + handlers.Doubled(2)
}
```

A method of the same name wins over a field of that name, which is C#'s own member lookup. The value
read is the CURRENT one, so a handler replaced after the object was built is the handler that runs.

**A member that cannot be called does not hide a method of the same name.** `List<T>.Count` is an
`int` property and `Enumerable.Count<TSource>` is an extension method; only the second is
invocable, so both spellings mean what they say:

```n#
total := words.Count                        // the property
nonEmpty := words.Count(w => w.Length > 0)  // the extension
```

Writing `()` after a member whose value is not a delegate is [`NL413`](./errors/NL413.md).

**Any expression whose value is a delegate can be called where it stands** — a call's own result, an
element of a list, a ternary. The argument list applies to the value, not to a name:

```n#
func Make(prefix: string): Func<string, string> {
    return s => prefix + s
}

greeting := Make("hello, ")("world")   // call the delegate `Make` handed back
first := handlers[0](event)            // and the one the list holds
```

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

### A lambda inside a method may read the object it is written in

A lambda written inside an instance method closes over that instance, so the enclosing type's fields,
properties and methods are in scope inside it — with `this.` or without, and however the lambda's own
type came to be known:

```n#
class Holder {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func Reader(): Func<int> {
        return () => this.Value      // a delegate target names the shape
    }

    func Inferred(): int {
        read := () => Value + 1      // ...and so does the lambda's own body
        return read()
    }

    func CountMatching(values: List<int>): int {
        return values.FindAll(v => v == this.Value).Count
    }
}
```

Each delegate binds to **that instance**: two `Holder`s hand out two readers that answer their own
`Value`, and a later write to `Value` is seen by a reader made before it. The compiler emits such a
lambda as a private instance method on the enclosing type and binds the delegate straight to the
receiver, so reading the object costs no closure allocation at all; a lambda that reads nothing
outside itself stays a static method, as before.

A lambda inside a **constructor body** binds the instance the same way: inside a class's own
constructor `this` IS the object being constructed, so `this.greet = () => this.Name + "!"` stores a
delegate that reads the finished object, exactly as the same line in a method does. A lambda written
directly at a constructor's ARGUMENT (`new Runner(() => "hi")`) builds its delegate there too.

A lambda inside a **`struct`'s** method or constructor cannot bind the instance — a delegate over a
value type's `this` would carry a copy with different mutation semantics — and reports
[`NL103`](./errors/NL103.md). Read what you need into a local first and capture that.

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

### Async Lambdas

A lambda takes the `async` keyword too, and it means the same thing it means on a function: the body
produces the **result** the target delegate's task carries, and the delegate's own signature is
unchanged.

```n#
import System
import System.Threading.Tasks

func makeLoader(): Func<string, Task<int>> {
    return async path => {
        contents := await File.ReadAllTextAsync(path)
        return contents.Length
    }
}
```

All three parameter spellings take it — `async () => …`, `async x => …`, `async (a, b) => …` — with
either an expression body or a block body, and the target may be any delegate returning `Task`,
`Task<T>`, `ValueTask` or `ValueTask<T>`. An async lambda captures like any other lambda: enclosing
locals, `this`, and a fresh copy of each loop iteration's own locals.

Its type is the **target's task family over the body's result**, so an `async` lambda decides an open
result position exactly as a plain one does:

```n#
// The body answers `int`; the lambda is a `Func<Task<int>>`, and the call is a `Task<int>`.
running := Task.Run(async () => {
    return 11
})
```

**An exception raised inside the body lands on the returned task**, not on the caller that invoked
the delegate:

```n#
failing: Func<Task<int>> = async () => {
    await Task.Delay(1)
    throw new InvalidOperationException("nope")
}

task := failing()        // returns normally
print task.IsFaulted     // True
```

A **local function** can be `async` as well. Like a top-level `async func` it declares its *inner*
type, and the method it compiles to returns the wrap:

```n#
func loadAll(paths: string[]): int {
    async func lengthOf(path: string): int {
        contents := await File.ReadAllTextAsync(path)
        return contents.Length
    }

    total := 0
    for path in paths {
        total = total + await lengthOf(path)
    }
    return total
}
```

Two diagnostics guard the keyword. Writing `async` where the target returns no task is
[`NL335`'s mirror, `NL334`](./errors/NL334.md) — there is no `async void` lambda in N#, because
`await` is lowered synchronously and the keyword would change nothing. Leaving it off when the target
wants a task is [`NL335`](./errors/NL335.md).

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

## Iterators (`func*`)

A generator is declared with `func*` and returns `IEnumerable<T>`. Each `yield` produces one element
and suspends; `yield break` ends the sequence. The body does not run at all until something enumerates
the result, and it resumes exactly where it paused.

```n#
import System.Collections.Generic

func* countTo(n: int): IEnumerable<int> {
    i := 0
    while i < n {
        yield i
        i = i + 1
    }
}

for value in countTo(3) {
    print value   // 0, 1, 2
}
```

### An iterator body is an ordinary function body

Everything you can write in a plain function you can write inside a `func*`. Locals live on the
generated state machine instead of the stack, and that is the only difference:

```n#
import System
import System.Collections.Generic
import System.IO

func* trimmedLines(path: string): IEnumerable<string> {
    for line in File.ReadAllLines(path) {       // a call as the sequence source
        if line.Length > 0 {                    // a member read in a condition
            yield line.Trim()                   // an instance call as the yielded value
        }
    }
}

func* doubled(count: int): IEnumerable<int> {
    values := new List<int>()                   // `new`, and a hoisted local
    for i := 0; i < count; i += 1 {
        values.Add(i * 2)                       // a call statement
        yield values[i]                         // an indexer
    }
}

func* rows(): IEnumerable<object[]> {
    yield ["symbols", 1, ["symbols", "--project"]]   // array literals, target-typed and boxed
}
```

Calls (static, instance, extension, generic), `new`, object initializers, array and collection
literals, indexers, member access, `checked`/`unchecked`, conditionals and every ordinary operator are
planned by the same owner that plans them in a plain function, so overload resolution, argument
evaluation order, conversions and exceptions behave identically. A yielded value takes the same
conversion a `return` of that value would take — boxing, a reference upcast, or the element type a
target-typed literal needs.

That includes the three **branch-merge** forms: `??`, the conditional `? :`, and `throw` written as
an expression.

```n#
import System
import System.Collections.Generic

func* resolved(names: string?[], counts: int?[]): IEnumerable<string> {
    for i := 0; i < names.Length; i += 1 {
        yield names[i] ?? "(none)"                       // reference `??`
        yield (counts[i] ?? 0).ToString()                // `Nullable<T>` `??` — worth the element type
        yield counts[i] > 0 ? "positive" : "other"       // a conditional
        yield names[i] ?? throw new InvalidOperationException("name " + i.ToString())
    }
}
```

`x ?? throw e` is worth `x` with its nullability removed, and `cond ? v : throw e` is worth `v` — the
throwing side produces no value, so the other side decides the type. The exception surfaces from the
`MoveNext` that reached it, after the elements before it have already been produced.

`for..in` inside a generator enumerates any sequence: an array, a `List<T>`, a call result, or another
generator. The enumerator is disposed when the loop ends, when the consumer stops early, and when the
sequence itself is disposed. The loop variable may carry a written type — `for v: int in objects` —
and each element is converted to it once per iteration, exactly the way a cast converts: a downcast
out of `object`, an unboxing, or a numeric conversion. An element that is not what the annotation
claimed raises `InvalidCastException` from `MoveNext`.

A lambda inside a generator captures the body's own bindings — a parameter, a local declared outside
every loop, and (in an instance generator) the enclosing type's members — and may be handed to
anything that takes a delegate:

```n#
import System
import System.Collections.Generic

func* matchesAtLeast(items: List<string>, minimum: int): IEnumerable<int> {
    longEnough: Predicate<string> = s => s.Length >= minimum
    matches := items.FindAll(longEnough)
    yield matches.Count
}
```

The lambda needs a delegate type to convert to — a written local type as above, a parameter whose
type names one, or the element type when it is `yield`ed (`yield () => total`) — and it is lowered as
a method on the generator's own state machine, so the capture costs no extra allocation.

Its body may be a **block**. A block body's statements are planned into that same method: expression
statements, local declarations, assignments to a captured binding or a member, and a `return` as the
last statement.

### Subscribing with `on` / `off` inside a generator

`on` and `off` work inside a `func*` exactly as they do anywhere else, and the point of writing them
there is that the subscription may **span a suspension**: the handle is an ordinary local, so the
machine hoists it into a field like every other local.

```n#
import System.Collections.Generic
import System.Collections.ObjectModel

func* watchWhileYielding(list: ObservableCollection<string>): IEnumerable<int> {
    seen := 0
    sub := on list.CollectionChanged (sender, args) => {
        seen = seen + 1
    }
    yield 1
    list.Add("during")
    yield seen          // 1 — the handler ran
    off sub
    list.Add("after")
    yield seen          // still 1 — the handler is detached
}
```

The handler may be an inline lambda (block-bodied or not), a delegate value, or a top-level `func`
named directly. The receiver is any expression whose value owns the event, or a type name for a static
one. A virtual `remove` accessor is taken over the receiver, so an event overridden by a derived type
detaches through the override — the same dispatch the subscription used.

A STATIC of a type this program declares is read and written inside a generator exactly as it is
outside one — `Counter.Total`, `Registry.Current = Registry.Current + 2` — including a static reached
through a derived type name, which binds the one declaration the base carries.

An assignment may target an indexer or a member as well as a local: `table[key] = value`,
`box.Field = value`, `builder.Length = 2`, `values[i] = v`. The member a name selects, the indexer an
index list selects and the conversion the stored value takes are the same answers the identical
statement gets outside a generator, and the store lands on the object the generator was handed — so it
is observable after the sequence has been enumerated, and not before. An instance generator may write
its enclosing type's members too.

### Cleanup: `try`/`finally` around a `yield`

A generator may suspend inside a `try` whose only handler is a `finally`, and the handler runs on
every way the enumeration can end:

```n#
import System.Collections.Generic
import System.IO

func* trimmedLines(path: string): IEnumerable<string> {
    reader := new StreamReader(path)
    try {
        line := reader.ReadLine()
        while line != null {
            yield line.Trim()
            line = reader.ReadLine()
        }
    } finally {
        reader.Dispose()
    }
}
```

The `finally` runs when the body finishes, when an exception passes through it, and when a consumer
stops enumerating part-way and disposes the enumerator — which is what `for..in` does when its body
`break`s or throws. It does **not** run when the generator merely suspends at a `yield`. Nested
regions unwind innermost first, exactly as they do in a plain function.

A resource that is only being *released* needs none of that ceremony: write
[`using`](./language-tour.md), which is this `try`/`finally` and releases on exactly the same three
paths.

```n#
func* firstTwoLines(path: string): IEnumerable<string?> {
    using reader := new StreamReader(path) {
        yield reader.ReadLine()
        yield reader.ReadLine()
    }
}
```

`catch` and `finally` handlers that contain no `yield` are ordinary protected regions and may be
written anywhere in a generator body.

A `using` resource may be a **struct** as well as a class. The machine holds the resource in one of
its own fields and releases it through that field's address with a `constrained.` call, so a struct
that counts its disposals observes exactly one — the same lowering a plain function writes over a
local.

```n#
import System
import System.Collections.Generic

struct Tick: IDisposable {
    Log: List<string>
    constructor(log: List<string>) {
        Log = log
    }
    func Dispose() {
        Log.Add("released")
    }
}

func* ticks(log: List<string>): IEnumerable<int> {
    using t := new Tick(log) {
        yield 1
        yield 2
    }
}
```

### What a generator body may not contain

- `return <value>` — a generator produces values with `yield` and stops with `yield break`.
- a `yield` inside a `try` that declares a `catch`, or inside a `catch` or `finally` handler
  ([NL332](./errors/NL332.md)) — a suspension has to be resumable, and only a `finally` can be
  re-entered that way.
- a `return` anywhere but the END of a block-bodied lambda's body, and an assignment inside one whose
  target is neither a captured binding nor a member.
- `await using` — releasing asynchronously needs an `await` inside a handler, where a suspension has
  no resume point to come back to. This is the same wall `await foreach` meets in a generator body.
- a lambda that captures a variable declared INSIDE a loop — a generator holds one field per local,
  so every iteration would share it rather than getting the fresh binding the language promises.
- `await` outside an `async func*`, and — inside one — an `await` NESTED in a larger expression;
  bind it first (`value := await ...`).
- a `try` statement inside an `async func*` body, and `lock` inside any generator body.
- `await foreach` INSIDE a generator body: releasing the inner enumerator needs an `await` in a
  handler. Consume the sequence outside the generator, or enumerate a synchronous sequence with
  `for..in` inside it.
- a COMPOUND assignment (`+=`, `-=`, …) whose target is an indexer or a member; write the plain form
  (`table[key] = table[key] + 1`).

### Async generators

`async func*` returns `IAsyncEnumerable<T>` and is consumed with `await foreach`. The same
ordinary-expression surface applies.

An `await` inside one may be a statement, or the whole value of a declaration, an assignment or a
`yield`:

```n#
import System.Collections.Generic
import System.Threading.Tasks

async func* rows(): IAsyncEnumerable<string> {
    header := await Task.FromResult("id,name")
    yield header
    await Task.Delay(1)
    yield await Task.FromResult("1,ada")
}
```

The awaited operand may be any awaitable — a `Task`, a `Task<T>`, a `ValueTask<T>`, or a type of your
own — because the compiler asks the operand's own type for `GetAwaiter()`, and that awaiter for
`IsCompleted`, `OnCompleted(Action)` and `GetResult()`. An `await` nested inside a larger expression
(`total + await f()`) is not lowered yet; bind it first.

`for..in` over any sequence works inside an async generator as well, and the enumerator it opens is
released when the loop ends, when an exception passes through, and when a consumer stops the
`await foreach` part-way.

```n#
import System.Collections.Generic

async func* doubledAsync(count: int): IAsyncEnumerable<int> {
    values := new List<int>()
    for i := 0; i < count; i += 1 {
        values.Add(i * 2)
        yield values[i]
    }
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

A `void` expression body **performs** its expression rather than returning it, so the expression
must itself produce nothing:

```n#
func append(sink: List<int>, value: int): void => sink.Add(value)
```

Handing a `void` expression body a value is an error (NL202) — say what the function returns, or
drop the value.

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
func processData(input: string, label: string): string {
    // A local function that captures nothing
    func validate(s: string): bool {
        return !string.IsNullOrEmpty(s)
    }

    // A local function that CAPTURES `label` from the enclosing function
    func transform(s: string): string {
        return $"{label}: {s}"
    }

    if !validate(input) {
        return "Invalid"
    }

    return transform(input)
}
```

### Expression-Bodied Local Functions

A local function takes the same `=>` body a top-level function does, `void` bodies included:

```n#
func report(values: List<int>, label: string): string {
    func doubled(x: int): int => x * 2
    func push(x: int): void => values.Add(x)

    push(doubled(values.Count))
    return $"{label}: {values.Count}"
}
```

The body ends where the expression ends, so it may continue on the next line, and a `static` local
function may use one too.

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

### Scope: a local function is visible in its whole block

A local function's name is in scope for the **entire block that declares it** — above its own
declaration, below it, and inside its sibling local functions. You do not have to order local
functions by who calls whom, and two of them may call each other:

```n#
func isEven(n: int): bool {
    func even(x: int): bool {
        if x == 0 {
            return true
        }
        return odd(x - 1)      // `odd` is declared below — still in scope
    }

    func odd(x: int): bool {
        if x == 0 {
            return false
        }
        return even(x - 1)
    }

    return even(n)
}
```

Because the declaration is not code that runs in the enclosing block, it may also sit **after** the
`return` that calls it — a common way to keep the interesting line at the top:

```n#
func classify(n: int): string {
    return describe(n)

    func describe(x: int): string {
        return x > 0 ? "positive" : "not positive"
    }
}
```

A local function declared inside a **nested** block belongs to that block, and is not visible
outside it:

```n#
func classify(n: int): int {
    if n > 0 {
        func inner(x: int): int {
            return x
        }
        return inner(n)
    }

    return inner(n)            // ERROR NL412: Function 'inner' not found
}
```

Calling a local function reads every variable its body reads, so those variables must already have
values **at the call** — even when the call is written above the declaration:

```n#
func total(): int {
    let seed: int
    v := scaled()              // ERROR NL304: 'seed' is read by local function 'scaled'
    seed = 5

    func scaled(): int {
        return seed * 2
    }

    return v
}
```

Move the assignment above the call — or give `seed` a value where it is declared — and the call is
fine. The rule follows calls between local functions too: if `outer` calls `inner` and `inner` reads
`seed`, calling `outer` is what gets reported.

### Capture: a local function and a lambda close over the same way

A local function may read and write the parameters and locals of the function around it. The binding
it captures is **one storage location**, not a copy: a write the local function makes is visible
afterwards, and a write made between the declaration and the call is visible inside.

```n#
func walk(items: List<string>): int {
    total := 0
    seen := new List<string>()

    func visit(value: string) {
        if seen.Contains(value) {
            return
        }

        seen.Add(value)
        total = total + value.Length          // writes the enclosing `total`
        if value.Length > 1 {
            visit(value.Substring(1))
        }
    }

    for item in items {
        visit(item)
    }

    return total                              // sees every write `visit` made
}
```

Two local functions that call each other share the same captures, so mutual recursion through
captured state works the way ordinary recursion does.

**What the compiler emits.** A local function that captures nothing stays a plain private method. A
local function that captures becomes a method of one **closure object** created for the scope that
declares it — the same object a capturing lambda in that scope would use — so the two forms have one
cost model and one set of rules. Converting a capturing local function to a delegate (`let f:
Func<int, int> = add`, `return add`, or passing it as an argument) binds the delegate to that same
object, so the delegate keeps sharing the storage after the enclosing call returns.

```n#
func makeAdder(seed: int): Func<int, int> {
    offset := seed

    func add(value: int): int {
        return value + offset
    }

    return add                                // the delegate carries `offset` with it
}
```

**Capturing `this`.** Inside a method, a local function may use the enclosing object's members with
no receiver, exactly as the method body does:

```n#
class Walker {
    Count: int

    func Run(items: List<string>) {
        func bump(value: string) {
            Count = Count + value.Length
        }

        for item in items {
            bump(item)
        }
    }
}
```

A local function in a **struct** that uses `this` receives the receiver **by reference**, which is
C#'s rule: it is compiled as an instance method of the struct, so it reads the same value the caller
holds rather than a copy.

**A `ref`, `out` or `in` parameter cannot be captured.** Those are pointers into the caller's frame
and the closure object outlives them, so a local function that reads one is reported as
[`NL331`](./errors/NL331.md). Copy it into an ordinary local, capture that, and assign the result
back after the call.

**Per-iteration capture.** A binding declared inside a loop is a new binding on every iteration, so
closures created in different iterations capture different storage:

```n#
adders := new List<Func<int>>()
for i := 0; i < 3; i++ {
    step := i * 10
    adders.Add(() => step)                    // 0, 10, 20 — not 20, 20, 20
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

### Which overload a call means

When more than one overload accepts a call, N# picks between them with the same rule C# uses
(ECMA-334 §12.6.4.3, "better function member"), and it applies to overloads you declared and to
overloads read out of a referenced assembly alike:

> A candidate is **better** than another when, for **every** argument, its parameter is at least as
> good a conversion target, and for **at least one** argument it is strictly better.

A parameter is the better conversion target when:

1. **It is the argument's own type.** `print(value: string)` beats `print(value: object)` for a
   `string`, and a generic `T` bound to the argument's type beats a declared `object`.
2. **It is the more specific of the two.** With neither parameter being the argument's own type, the
   one that converts to the other — and not back — wins. `Shape` beats `object` for a `Square`;
   `IEnumerable<Task<int>>` beats `IEnumerable<Task>` for a `List<Task<int>>`; `int` beats `long` for
   a `short`.

Only when the conversions cannot separate two candidates do the remaining rules run, in this order: a
**non-generic** signature beats a generic one whose parameters are the same types after
substitution, a call in **normal form** beats one that had to expand a `params` tail, and a signature
that fills **fewer defaults** beats one that fills more.

```n#
import System.Collections.Generic
import System.Threading.Tasks

func awaitAll(work: List<Task<int>>): int[] {
    // `WhenAll(IEnumerable<Task>): Task` and `WhenAll<TResult>(IEnumerable<Task<TResult>>): Task<TResult[]>`
    // both accept this argument. The generic one's parameter is the more specific type, so the call
    // is `Task<int[]>` and `.Result` is an `int[]`.
    return Task.WhenAll(work).Result
}
```

Declaration order is **not** a tiebreak, and neither is the order a referenced assembly's metadata
happens to list its methods in. When two candidates are still tied after every rule above, the call
is ambiguous and N# reports [NL414](./errors/NL414.md) rather than choosing for you — see that page
for the three ways to say which overload you meant.

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
