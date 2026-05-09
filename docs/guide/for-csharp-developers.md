# N# for C# Developers

You know C#. Here's the N# equivalent for everything you'll look up.

## 1. Variable Declaration

**C#:**
```csharp
var name = "hello";
int count = 5;
const double Pi = 3.14;
```

**N#:**
```n#
name := "hello"
count: int = 5
let pi: double = 3.14
```

N# uses `:=` for type inference (like Go), `: type =` for explicit types, and `let` for immutable bindings.

## 2. Function Declaration

**C#:**
```csharp
public int Add(int a, int b)
{
    return a + b;
}

private string FormatName(string first, string last)
{
    return $"{first} {last}";
}
```

**N#:**
```n#
func Add(a: int, b: int): int {
    return a + b
}

func formatName(first: string, last: string): string {
    return $"{first} {last}"
}
```

No access modifiers — PascalCase = exported/public, camelCase = unexported/private-by-convention. Parameters use `name: type` syntax.

## 3. Class Definition

**C#:**
```csharp
public class Person
{
    public string Name { get; set; }
    public int Age { get; set; }
    private string _id;

    public Person(string name, int age)
    {
        Name = name;
        Age = age;
        _id = Guid.NewGuid().ToString();
    }

    public string GetInfo() => $"{Name}, {Age}";
}
```

**N#:**
```n#
class Person {
    Name: string
    Age: int
    id: string

    constructor(name: string, age: int) {
        Name = name
        Age = age
        id = Guid.NewGuid().ToString()
    }

    func GetInfo(): string => $"{Name}, {Age}"
}
```

## 4. Properties

**C#:**
```csharp
public string DisplayName => $"{First} {Last}";

public decimal Price
{
    get => _price;
    set
    {
        if (value < 0) throw new ArgumentException();
        price = value;
    }
}
```

**N#:**
```n#
DisplayName: string => $"{First} {Last}"

price: decimal
Price: decimal {
    get => price
    set {
        if value < 0 {
            throw new ArgumentException()
        }
        price = value
    }
}
```

## 5. Constructors

**C#:**
```csharp
public class Logger
{
    private readonly string _name;

    public Logger(string name)
    {
        _name = name;
    }
}

// C# 12 primary constructor
public class Logger(string name)
{
    public void Log(string msg) => Console.WriteLine($"[{name}] {msg}");
}
```

**N#:**
```n#
class Logger {
    name: string

    constructor(name: string) {
        this.name = name
    }
}

// Primary constructor
class Logger(name: string) {
    func Log(msg: string) {
        print $"[{name}] {msg}"
    }
}
```

## 6. Interfaces

**C#:**
```csharp
public interface IRepository<T>
{
    Task<T?> GetByIdAsync(Guid id);
    Task<List<T>> GetAllAsync();
}

public class UserRepo : IRepository<User>
{
    public async Task<User?> GetByIdAsync(Guid id) { ... }
    public async Task<List<User>> GetAllAsync() { ... }
}
```

**N#:**
```n#
interface IRepository<T> {
    async func GetByIdAsync(id: Guid): T?
    async func GetAllAsync(): List<T>
}

class UserRepo : IRepository<User> {
    async func GetByIdAsync(id: Guid): User? { ... }
    async func GetAllAsync(): List<User> { ... }
}
```

## 7. Inheritance

**C#:**
```csharp
public class Animal
{
    public virtual string Speak() => "...";
}

public class Dog : Animal
{
    public override string Speak() => "Woof!";
}
```

**N#:**
```n#
class Animal {
    virtual func Speak(): string => "..."
}

class Dog : Animal {
    override func Speak(): string => "Woof!"
}
```

## 8. Generics

**C#:**
```csharp
public class Stack<T>
{
    public void Push(T item) { ... }
    public T Pop() { ... }
}

public T Process<T>(T item) where T : IComparable
{
    return item;
}
```

**N#:**
```n#
class Stack<T> {
    func Push(item: T) { ... }
    func Pop(): T { ... }
}

func Process<T>(item: T): T where T : IComparable {
    return item
}
```

Generics are identical in capability — same `<T>` syntax, same constraints.

## 9. Async/Await

**C#:**
```csharp
public async Task<string> FetchDataAsync(string url)
{
    var client = new HttpClient();
    return await client.GetStringAsync(url);
}
```

**N#:**
```n#
async func FetchDataAsync(url: string): string {
    client := new HttpClient()
    return await client.GetStringAsync(url)
}
```

Return types are automatically wrapped in `Task<T>` or `ValueTask<T>`. No need to write `Task<string>` in the signature — just write `string`.

## 10. LINQ

**C#:**
```csharp
var results = items
    .Where(x => x > 10)
    .Select(x => x * 2)
    .OrderBy(x => x)
    .ToList();
```

**N#:**
```n#
results := items
    .Where(x => x > 10)
    .Select(x => x * 2)
    .OrderBy(x => x)
    .ToList()
```

LINQ is identical. Just drop the semicolons and `var`.

## 11. Pattern Matching

**C#:**
```csharp
var result = value switch
{
    0 => "zero",
    > 0 => "positive",
    _ => "negative"
};
```

**N#:**
```n#
result := match value {
    0 => "zero",
    > 0 => "positive",
    _ => "negative"
}
```

`match` replaces `switch` expression. Same patterns (relational, type, property, list), different keyword.

## 12. Null Handling

**C#:**
```csharp
string? name = null;
var display = name ?? "Unknown";
var length = name?.Length ?? 0;
```

**N#:**
```n#
name: string? = null
display := name ?? "Unknown"
length := name?.Length ?? 0
```

Same null-coalescing (`??`) and null-conditional (`?.`) operators. Same nullable types with `?`.

## 13. String Interpolation

**C#:**
```csharp
var msg = $"Hello, {name}! You are {age} years old.";
var formatted = $"Pi: {Math.PI:F2}";
```

**N#:**
```n#
msg := $"Hello, {name}! You are {age} years old."
formatted := $"Pi: {Math.PI:F2}"
```

Identical syntax.

## 14. Collections

**C#:**
```csharp
var numbers = new[] { 1, 2, 3 };
var list = new List<int> { 1, 2, 3 };
var dict = new Dictionary<string, int>
{
    ["Alice"] = 95,
    ["Bob"] = 87
};
```

**N#:**
```n#
numbers := [1, 2, 3]
let list: List<int> = [1, 2, 3]

dict := new Dictionary<string, int>()
dict["Alice"] = 95
dict["Bob"] = 87
```

Array literals use `[...]` without `new`. Collection expressions let `[...]` target `List<T>`, `HashSet<T>`, etc. when the type is explicit.

## 15. Error Handling

**C#:**
```csharp
try
{
    var result = DoThing();
}
catch (Exception ex)
{
    Console.WriteLine(ex.Message);
}
```

**N#:**
```n#
try {
    result := DoThing()
} catch ex: Exception {
    print ex.Message
}
```

**The Go-style tuple trick** — N#'s unique feature:

```n#
// Captures exception instead of throwing
result, err := DoThing()
if err != null {
    print $"Error: {err.Message}"
}
```

Assign to two variables and the exception is caught automatically. This is like Go's `result, err := f()` pattern, but built into the language.

## 16. Enums

**C#:**
```csharp
public enum Priority
{
    Low = 0,
    Medium = 1,
    High = 2
}

// String enums? Nope. Workaround:
public static class Status
{
    public const string Active = "active";
    public const string Inactive = "inactive";
}
```

**N#:**
```n#
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2
}

// String enums — built in!
enum Status {
    Active = "active",
    Inactive = "inactive"
}
```

N# has native string enums. No more `const string` workarounds.

## 17. Records

**C#:**
```csharp
public record Person(string Name, int Age);

var p1 = new Person("Alice", 30);
var p2 = p1 with { Name = "Bob" };
```

**N#:**
```n#
record Person(name: string, age: int)

p1 := new Person("Alice", 30)
p2 := p1 with { name: "Bob" }
```

Records work the same — value equality, `with` expressions, immutability.

## 18. Unions (NEW)

C# doesn't have discriminated unions. N# does.

**C# (manual approach):**
```csharp
public abstract class Result<T>
{
    public sealed class Success : Result<T> { public T Value { get; init; } }
    public sealed class Failure : Result<T> { public string Error { get; init; } }
}
```

**N#:**
```n#
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

// Exhaustive matching — compiler ensures all cases handled
message := match result {
    Result.Success { value } => $"Got: {value}",
    Result.Failure { error } => $"Error: {error}"
}
```

Unions emit as idiomatic C# class hierarchies, so C# code can consume them naturally.

## 19. Duck Interfaces (NEW)

C# requires explicit interface implementation. N# adds structural typing.

**N#:**
```n#
duck interface IReader {
    func Read(): string
}

// No ": IReader" declaration needed
class FileReader {
    func Read(): string => "file contents"
}

class HttpReader {
    func Read(): string => "http contents"
}

// Both work — they have the right shape
func process(r: IReader) {
    print r.Read()
}

process(new FileReader())   // file contents
process(new HttpReader())   // http contents
```

If a type has the right methods, it satisfies the interface. Like Go interfaces, but on .NET.

## 20. Visibility

**C#:**
```csharp
public class Service
{
    public string Name { get; set; }
    private int _count;
    internal string ConnectionString { get; set; }
    protected virtual void OnInit() { }
}
```

**N#:**
```n#
class Service {
    Name: string              // exported/public (PascalCase)
    count: int                // unexported/private-by-convention (camelCase)
    internal ConnectionString: string
    protected virtual func OnInit() { }
}
```

Convention-based: PascalCase = exported/public, camelCase = unexported/private-by-convention. Do not carry C# `public`/`private` into N# for ordinary code; the formatter removes redundant `public`/`private` when casing already says the same thing. Explicit modifiers are interop escape hatches that override casing, so `public legacyCamel` is exported and `private SecretPascal` is hidden; the formatter preserves those semantically necessary modifiers. Use explicit `internal`, `protected`, or `file` only for real .NET interop boundaries.

## Quick Reference

| Task | C# | N# |
|------|----|----|
| Variable | `var x = 5;` | `x := 5` |
| Explicit type | `int x = 5;` | `x: int = 5` |
| Immutable | `readonly` / no reassign | `let x := 5` |
| Function | `public int F(int a) { }` | `func F(a: int): int { }` |
| Private function | `private void F() { }` | `func f() { }` |
| Class | `public class C { }` | `class C { }` |
| Property | `public string X { get; set; }` | `X: string` |
| Constructor | `public C(string x) { }` | `constructor(x: string) { }` |
| Async | `async Task<T> F()` | `async func F(): T` |
| Lambda | `x => x * 2` | `x => x * 2` |
| Array | `new[] { 1, 2, 3 }` | `[1, 2, 3]` |
| For-each | `foreach (var x in items)` | `for x in items { }` |
| If | `if (x > 5) { }` | `if x > 5 { }` |
| Switch/Match | `x switch { 0 => "a" }` | `match x { 0 => "a" }` |
| String interp | `$"Hi {name}"` | `$"Hi {name}"` |
| Import | `using System;` | `import System` |
| Namespace | `namespace X { }` | `package X` |
| Null coalesce | `x ?? "default"` | `x ?? "default"` |
| Try/catch | `try { } catch (Exception e) { }` | `try { } catch e: Exception { }` |
| Tuple error | N/A | `result, err := F()` |

## Next Steps

- **[Getting Started](getting-started.md)** — Create your first project
- **[Language Tour](language-tour.md)** — Every feature with examples
- **[For Go Developers](for-go-developers.md)** — Go concepts mapped to N#
