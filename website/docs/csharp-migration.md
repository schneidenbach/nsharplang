---
sidebar_label: C# Migration Guide
title: C# Migration Guide
---

# Migrating from C# to N#

This guide helps C# developers transition to N#. If you know C#, you'll feel right at home with N#!

## Table of Contents

- [Key Differences](#key-differences)
- [Syntax Mapping](#syntax-mapping)
- [Type System Enhancements](#type-system-enhancements)
- [Migration Strategies](#migration-strategies)
- [AI-Assisted C# Migration Contract](#ai-assisted-c-migration-contract)
- [Common Patterns](#common-patterns)

## Key Differences

### What's Different

| Feature | C# | N# |
|---------|----|----|
| **Semicolons** | Required | Optional (not used) |
| **Variable Declaration** | `var x = 5;` | `x := 5` |
| **Visibility** | Explicit modifiers | Convention-based (PascalCase = exported/public, camelCase = unexported/private-by-convention) |
| **Discriminated Unions** | Manual class hierarchies | Built-in `union` keyword |
| **Structural Typing** | Not supported | `duck interface` |
| **String Enums** | Workarounds | Built-in `enum` with string values |
| **Package/Namespace** | `namespace` | `package` |

### What's the Same

- Type system (classes, structs, interfaces, generics)
- Async/await
- LINQ
- Nullable reference types
- Pattern matching
- Records
- All .NET APIs and libraries

## Syntax Mapping

### Variables

**C#:**
```csharp
var x = 5;
int y = 10;
string name = "Alice";
```

**N#:**
```n#
x := 5
y: int = 10
name := "Alice"
```

### Functions/Methods

**C#:**
```csharp
public int Add(int a, int b)
{
    return a + b;
}

private string GetName()
{
    return "Alice";
}
```

**N#:**
```n#
func Add(a: int, b: int): int {
    return a + b
}

func getName(): string {
    return "Alice"
}
```

### Classes

**C#:**
```csharp
public class Person
{
    public string Name { get; set; }
    public int Age { get; set; }

    public Person(string name, int age)
    {
        Name = name;
        Age = age;
    }

    public string GetFullInfo()
    {
        return $"{Name}, {Age} years old";
    }
}
```

**N#:**
```n#
class Person {
    Name: string
    Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    func getFullInfo(): string {
        return $"{Name}, {Age} years old"
    }
}
```

### Properties

**C#:**
```csharp
public class Product
{
    public string Name { get; set; }
    private decimal _price;
    public decimal Price
    {
        get => _price;
        set
        {
            if (value < 0)
                throw new ArgumentException("Price cannot be negative");
            price = value;
        }
    }
    public string DisplayName => $"{Name} (${Price})";
}
```

**N#:**
```n#
class Product {
    Name: string

    price: decimal
    Price: decimal {
        get => price
        set {
            if value < 0 {
                throw new ArgumentException("Price cannot be negative")
            }
            price = value
        }
    }

    DisplayName: string => $"{Name} (${Price})"
}
```

### If Statements

**C#:**
```csharp
if (x > 5)
{
    Console.WriteLine("big");
}
else if (x == 5)
{
    Console.WriteLine("medium");
}
else
{
    Console.WriteLine("small");
}
```

**N#:**
```n#
if x > 5 {
    Console.WriteLine("big")
} else if x == 5 {
    Console.WriteLine("medium")
} else {
    Console.WriteLine("small")
}
```

### Loops

**C#:**
```csharp
// For loop
for (int i = 0; i < 10; i++)
{
    Console.WriteLine(i);
}

// Foreach
foreach (var item in items)
{
    Console.WriteLine(item);
}

// While
while (count < 10)
{
    count++;
}
```

**N#:**
```n#
// For loop
for i := 0; i < 10; i += 1 {
    Console.WriteLine(i)
}

// Foreach
for item in items {
    Console.WriteLine(item)
}

// While
while count < 10 {
    count += 1
}
```

### Async/Await

**C#:**
```csharp
public async Task<string> FetchDataAsync(string url)
{
    var client = new HttpClient();
    var result = await client.GetStringAsync(url);
    return result;
}
```

**N#:**
```n#
async func fetchDataAsync(url: string): string {
    client := new HttpClient()
    result := await client.GetStringAsync(url)
    return result
}
```

### LINQ

**C#:**
```csharp
var results = items
    .Where(x => x > 10)
    .Select(x => x * 2)
    .ToList();
```

**N#:**
```n#
results := items
    .Where(x => x > 10)
    .Select(x => x * 2)
    .ToList()
```

### Namespaces/Packages

**C#:**
```csharp
using System;
using System.Linq;

namespace MyApp.Services
{
    public class MyService
    {
        // ...
    }
}
```

**N#:**
```n#
import System
import System.Linq

package MyApp.Services

class MyService {
    // ...
}
```

## Type System Enhancements

### Discriminated Unions

**C# (Manual Approach):**
```csharp
public abstract class Result<T>
{
    private Result() { }

    public sealed class Success : Result<T>
    {
        public T Value { get; init; }
    }

    public sealed class Failure : Result<T>
    {
        public string Error { get; init; }
    }
}

// Usage
var result = new Result<int>.Success { Value = 42 };

// Pattern matching
var message = result switch
{
    Result<int>.Success s => $"Got {s.Value}",
    Result<int>.Failure f => $"Error: {f.Error}",
    _ => "Unknown"
};
```

**N# (Built-in):**
```n#
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

// Usage
result := new Result.Success<int> { value: 42 }

// Pattern matching (exhaustiveness checked!)
message := match result {
    Result.Success<int> { value: v } => $"Got {v}",
    Result.Failure<int> { error: e } => $"Error: {e}"
}
```

### Structural Typing

**C# (Not supported):**
```csharp
// Can't do this in C#!
// Types must explicitly implement interfaces
```

**N# (Duck Interfaces):**
```n#
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string => "file contents"
}

class HttpReader {
    func Read(): string => "http contents"
}

func processReader(reader: IReader) {
    content := reader.Read()
    Console.WriteLine(content)
}

// Both work - they have the right shape!
processReader(new FileReader())
processReader(new HttpReader())
```

### String Enums

**C# (Workaround):**
```csharp
public static class Status
{
    public const string Active = "active";
    public const string Inactive = "inactive";
    public const string Pending = "pending";
}

// Usage
string status = Status.Active;
```

**N# (Built-in):**
```n#
enum Status {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}

// Usage
status := Status.Active
```

### Pattern Matching Enhancements

**C# Switch Expression:**
```csharp
var category = age switch
{
    < 13 => "child",
    < 20 => "teen",
    < 65 => "adult",
    _ => "senior"
};
```

**N# Match Expression:**
```n#
category := match age {
    < 13 => "child",
    < 20 => "teen",
    < 65 => "adult",
    _ => "senior"
}
```

## Migration Strategies

### Strategy 1: New Projects

Start fresh with N#:

```bash
dotnet new nsharp-console -o MyNewApp
cd MyNewApp
dotnet build
dotnet run
```

### Strategy 2: Gradual Migration

Mix C# and N# in the same solution, but do not stop at syntactic translation:

1. Add an N# project to the existing solution.
2. Reference C# projects from N# (full interop!).
3. Migrate one module/feature slice at a time.
4. Run `nlc check --project <nsharp-out> --json` to clear parse/semantic diagnostics.
5. Run `nlc idiom --project <nsharp-out>` to catch C#-shaped output such as semicolons, copied modifiers, `_field` names, property blocks, DTO classes, and null-forgiving suppressions.
6. Run `nlc fix --project <nsharp-out> --dry-run --json`; apply safe fixes, review `reviewNeeded` fixes manually, and waive suggestion-only items only with rationale.
7. Re-run check/idiom/fix/format/tests after every cluster of edits.

**Example Solution Structure:**
```
MySolution/
├── LegacyApp.csproj         (C# - existing)
├── NewFeatures/             (N# - new code)
│   ├── NewFeatures.csproj
│   └── Features.nl
└── Shared/                  (C# - shared utilities)
    └── Shared.csproj
```

### Strategy 3: Library-First

Create new libraries in N#, consume from C#:

**N# Library:**
```n#
// MyLibrary/Calculator.nl
package MyLibrary

class Calculator {
    func Add(a: int, b: int): int => a + b
    func Multiply(a: int, b: int): int => a * b
}
```

**C# Consumer:**
```csharp
// MainApp/Program.cs
using MyLibrary;

var calc = new Calculator();
var result = calc.Add(5, 10);  // Ordinary C# call shape
```

## AI-Assisted C# Migration Contract

AI-generated migration output must be idiomatic N#, not C# with lighter syntax. The full implementation contract lives in the [AI C# Migration Contract](./ai-csharp-migration-contract.md); the operating summary is:

```bash
# Produce <nsharp-out> with an AI migration pass that writes idiomatic N# directly.
# Do not rely on syntax-conversion as the migration contract.

cd <nsharp-out>
nlc check --project . --json
nlc idiom --project .
nlc fix --project . --dry-run --json
nlc format --check --project .
nlc test --project .
```

Required cleanup before review:

- Package declarations and folder/package layout match the target N# project shape; the loop flags missing or wrong `package` declarations in `.nl` files under package folders.
- C# `using` directives and `namespace` declarations are converted to N# `import`/`package` form before review.
- Public framework-discovered surface stays PascalCase; private implementation details use camelCase; copied C# `public`/`private` modifiers are removed unless interop requires them.
- Statement semicolons, C# property blocks, `_field` private naming, null-forgiving suppressions, `default!` placeholders, and C# equals-style object initializers are removed or waived with diagnostic-backed rationale.
- DTO-shaped API/request/response classes become records unless mutation or identity is required.
- Domain failure flows become unions plus exhaustive `match`; ASP.NET/EF code maps those domain results at the boundary.
- Ordinary async methods can use implicit N# return types, but xUnit/framework-discovered methods that require C# `Task` signatures must declare explicit `: Task` or `: Task<T>`; `Task<T>` bodies return bare `T` values.
- `nlc idiom` reports the score, grade, thresholds, aggregate C#-ism counts, using/namespace/package/initializer blockers, per-file occurrences, and recommendations so agents can drive the next edit cluster without scraping prose.

Completion requires zero `nlc check` errors, no remaining safe fixes in `nlc fix --dry-run --json`, no blocking `nlc idiom` C# artifacts, and passing project tests.

## Common Patterns

### Pattern 1: Repository Pattern

**C#:**
```csharp
public interface IRepository<T>
{
    Task<T?> GetByIdAsync(Guid id);
    Task<List<T>> GetAllAsync();
    Task AddAsync(T entity);
}

public class UserRepository : IRepository<User>
{
    private readonly List<User> _users = new();

    public async Task<User?> GetByIdAsync(Guid id)
    {
        await Task.Delay(10); // Simulate async
        return _users.FirstOrDefault(u => u.Id == id);
    }

    public async Task<List<User>> GetAllAsync()
    {
        await Task.Delay(10);
        return _users;
    }

    public async Task AddAsync(User entity)
    {
        await Task.Delay(10);
        _users.Add(entity);
    }
}
```

**N#:**
```n#
interface IRepository<T> {
    async func GetByIdAsync(id: Guid): T?
    async func GetAllAsync(): List<T>
    async func AddAsync(entity: T): void
}

class UserRepository : IRepository<User> {
    users: List<User> = new List<User>()

    async func GetByIdAsync(id: Guid): User? {
        await Task.Delay(10)
        return users.FirstOrDefault(u => u.Id == id)
    }

    async func GetAllAsync(): List<User> {
        await Task.Delay(10)
        return users
    }

    async func AddAsync(entity: User) {
        await Task.Delay(10)
        users.Add(entity)
    }
}
```

### Pattern 2: Builder Pattern

**C#:**
```csharp
public class PersonBuilder
{
    private string _name = "";
    private int _age = 0;
    private string _email = "";

    public PersonBuilder WithName(string name)
    {
        _name = name;
        return this;
    }

    public PersonBuilder WithAge(int age)
    {
        _age = age;
        return this;
    }

    public PersonBuilder WithEmail(string email)
    {
        _email = email;
        return this;
    }

    public Person Build()
    {
        return new Person
        {
            Name = _name,
            Age = _age,
            Email = _email
        };
    }
}
```

**N#:**
```n#
class PersonBuilder {
    name: string = ""
    age: int = 0
    email: string = ""

    func WithName(name: string): PersonBuilder {
        this.name = name
        return this
    }

    func WithAge(age: int): PersonBuilder {
        this.age = age
        return this
    }

    func WithEmail(email: string): PersonBuilder {
        this.email = email
        return this
    }

    func Build(): Person {
        return new Person {
            Name: name,
            Age: age,
            Email: email
        }
    }
}
```

### Pattern 3: Result Pattern

**C# (Manual):**
```csharp
public abstract class Result<T>
{
    private Result() { }

    public sealed class Success : Result<T>
    {
        public T Value { get; init; }
    }

    public sealed class Failure : Result<T>
    {
        public string Error { get; init; }
    }
}

public Result<User> GetUser(Guid id)
{
    var user = _db.Find(id);
    if (user == null)
        return new Result<User>.Failure { Error = "User not found" };
    return new Result<User>.Success { Value = user };
}
```

**N# (Built-in):**
```n#
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

func getUser(id: Guid): Result<User> {
    user := db.Find(id)
    if user == null {
        return new Result.Failure<User> { error: "User not found" }
    }
    return new Result.Success<User> { value: user }
}
```

### Pattern 4: Option/Maybe Pattern

**C# (Manual with Nullable):**
```csharp
public User? FindUser(Guid id)
{
    return _users.FirstOrDefault(u => u.Id == id);
}

// Usage
var user = FindUser(id);
if (user != null)
{
    Console.WriteLine(user.Name);
}
```

**N# (With Union):**
```n#
union Option<T> {
    Some { value: T }
    None { }
}

func findUser(id: Guid): Option<User> {
    user := users.FirstOrDefault(u => u.Id == id)
    if user == null {
        return new Option.None<User> { }
    }
    return new Option.Some<User> { value: user }
}

// Usage with exhaustive matching
match findUser(id) {
    Option.Some<User> { value: u } => Console.WriteLine(u.Name),
    Option.None<User> { } => Console.WriteLine("User not found")
}
```

## Quick Reference Card

| Task | C# | N# |
|------|----|----|
| Declare variable | `var x = 5;` | `x := 5` |
| Declare function | `public int Add(int a, int b) { }` | `func Add(a: int, b: int): int { }` |
| Private function | `private void Helper() { }` | `func helper() { }` |
| Class | `public class Person { }` | `class Person { }` |
| Property | `public string Name { get; set; }` | `Name: string` |
| Constructor | `public Person(string name) { }` | `constructor(name: string) { }` |
| Async method | `public async Task<string> Get() { }` | `async func get(): string { }` |
| Lambda | `x => x * 2` | `x => x * 2` |
| Array | `var arr = new[] { 1, 2, 3 };` | `arr := [1, 2, 3]` |
| For loop | `for (var i = 0; i < 10; i++) { }` | `for i := 0; i < 10; i += 1 { }` |
| Foreach | `foreach (var x in items) { }` | `for x in items { }` |
| If statement | `if (x > 5) { }` | `if x > 5 { }` |
| String interpolation | `$"Hello, {name}"` | `$"Hello, {name}"` |
| Null check | `if (x != null) { }` | `if x != null { }` |
| Pattern match | `x switch { 0 => "a", _ => "b" }` | `match x { 0 => "a", _ => "b" }` |

## Best Practices for Migration

### 1. Start Small

Migrate one module or feature at a time, not the entire codebase.

### 2. Use Interop

N# and C# are designed to coexist. Don't feel pressure to migrate everything, and verify each interop seam with the current tests/examples.

### 3. Leverage Union Types

Replace error-prone null checks with discriminated unions:

```n#
// Instead of nulls
func getUser(id: Guid): User?

// Use unions
func getUser(id: Guid): Result<User>
```

### 4. Adopt N# Conventions Before Review

Do not treat copied C# modifiers as acceptable final migration output. Use casing for ordinary visibility and reserve explicit modifiers for real .NET interop needs. The formatter drops redundant `public`/`private` when casing already means the same thing, but preserves escape hatches such as `public legacyCamel` or `private SecretPascal` because removing those would change exported API semantics:

```text
// C#-shaped migration debt
public func ProcessData() { }
private func validateInput() { }
private _logger: ILogger<Service>
```

```n#
// Review-ready N#
func ProcessData() { }      // PascalCase = exported/public
func validateInput() { }    // camelCase = unexported/private-by-convention
logger: ILogger<Service>
```

### 5. Use the Right Tool

- N# for new features needing unions, pattern matching
- C# for existing code that works fine
- Mix both in the same solution

## Next Steps

- **[Basics Guide](basics.md)** - Learn N# fundamentals
- **[Types Guide](types.md)** - Deep dive into N# type system
- **[Pattern Matching](pattern-matching.md)** - Master pattern matching
- **[Interop Guide](interop.md)** - Learn about C# interop details

## Resources

- [Project README](https://github.com/schneidenbach/nsharplang/blob/main/README.md)
- [Examples](/examples)
- [Language Design](https://github.com/schneidenbach/nsharplang/blob/main/docs/DESIGN.md)
