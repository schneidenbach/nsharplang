# Interop Guide: N# and C#

N# is designed for practical C# and .NET interoperability. This guide covers the interop paths that are intended to work and should be verified with current tests/examples before being presented as complete.

## Table of Contents

- [Design Philosophy](#design-philosophy)
- [Using .NET Libraries](#using-net-libraries)
- [C# Consuming N# Code](#c-consuming-n-code)
- [N# Consuming C# Code](#n-consuming-c-code)
- [Type Mappings](#type-mappings)
- [Best Practices](#best-practices)

## Design Philosophy

N# follows a **"C# first"** interop philosophy:

> **C# consumers should not know they're using N#-compiled code.**

This means:
- N# types emit ordinary C#-friendly CLR shapes
- No special runtime support needed
- C# consumers get ordinary CLR-visible types in covered scenarios
- No leaky abstractions

### Comparison with F#

| Feature | N# | F# |
|---------|----|----|
| **Unions** | C# class hierarchies | F# discriminated unions (opaque to C#) |
| **Records** | C# records | F# records (awkward constructors) |
| **Async** | C# Task/ValueTask | F# Async (different type system) |
| **Nullability** | C# nullable types | F# Option (not null) |
| **Properties** | C# auto-properties | F# needs explicit getters |

**Result**: C# code using N# libraries feels natural. C# code using F# libraries feels foreign.

## Using .NET Libraries

N# can use any .NET library, NuGet package, or framework:

### Basic Import

```n#
import System
import System.Linq
import System.Collections.Generic
import System.Threading.Tasks
import Microsoft.AspNetCore.Mvc
import Newtonsoft.Json
```

### Using NuGet Packages

Add to your `project.yml`:

```yaml
name: MyApp
outputType: exe
targetFramework: net10.0

dependencies:
  - Newtonsoft.Json: 13.0.3
  - Dapper: 2.0.123
  - Microsoft.EntityFrameworkCore: 9.0.0
```

Then use in N#:

```n#
import Newtonsoft.Json
import Dapper
import Microsoft.EntityFrameworkCore

func serializeUser(user: User): string {
    return JsonConvert.SerializeObject(user)
}
```

### ASP.NET Core Example

```n#
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Mvc
import Microsoft.Extensions.DependencyInjection

package MyApi

[ApiController]
[Route("api/[controller]")]
class UsersController : ControllerBase {
    [HttpGet]
    async func GetAll(): IActionResult {
        users := await db.Users.ToListAsync()
        return Ok(users)
    }

    [HttpGet("{id}")]
    async func GetById(id: Guid): IActionResult {
        user := await db.Users.FindAsync(id)
        return match user {
            null => NotFound(),
            _ => Ok(user)
        }
    }
}
```

### Entity Framework Core

```n#
import Microsoft.EntityFrameworkCore

class AppDbContext : DbContext {
    Users: DbSet<User>
    Products: DbSet<Product>

    constructor(options: DbContextOptions<AppDbContext>) : base(options) {
    }

    protected override func OnModelCreating(modelBuilder: ModelBuilder) {
        modelBuilder.Entity<User>()
            .HasIndex(u => u.Email)
            .IsUnique()
    }
}
```

## C# Consuming N# Code

N# emits CLR-visible types that are indistinguishable from hand-written C# to consumers.

### Example 1: Simple Class

**N# Code:**
```n#
class Calculator {
    func Add(a: int, b: int): int => a + b
    func Multiply(a: int, b: int): int => a * b
}
```

**C# Shape:**
```csharp
public class Calculator
{
    public int Add(int a, int b) => a + b;
    public int Multiply(int a, int b) => a * b;
}
```

**C# Consumer:**
```csharp
using MyLibrary;

var calc = new Calculator();
var result = calc.Add(5, 10);  // Ordinary C# call shape
```

### Example 2: Discriminated Union

**N# Code:**
```n#
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

func divide(a: int, b: int): Result<int> {
    if b == 0 {
        return new Result.Failure<int> { error: "Division by zero" }
    }
    return new Result.Success<int> { value: a / b }
}
```

**C# Shape:**
```csharp
public abstract class Result<T>
{
    private Result() { }

    public sealed class Success : Result<T>
    {
        public required T Value { get; init; }
    }

    public sealed class Failure : Result<T>
    {
        public required string Error { get; init; }
    }
}

public static class Math
{
    public static Result<int> Divide(int a, int b)
    {
        if (b == 0)
            return new Result<int>.Failure { Error = "Division by zero" };
        return new Result<int>.Success { Value = a / b };
    }
}
```

**C# Consumer:**
```csharp
using MyLibrary;

var result = Math.Divide(10, 2);

// C# pattern matching works!
var message = result switch
{
    Result<int>.Success s => $"Result: {s.Value}",
    Result<int>.Failure f => $"Error: {f.Error}",
    _ => "Unknown"
};
```

### Example 3: Duck Interface

**N# Code:**
```n#
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string => "file contents"
}

func processReader(reader: IReader): string {
    return reader.Read().ToUpper()
}
```

**C# Shape:**
```csharp
internal interface IReader
{
    string Read();
}

public class FileReader : IReader
{
    public string Read() => "file contents";
}

public static class Processing
{
    public static string ProcessReader(IReader reader)
    {
        return reader.Read().ToUpper();
    }
}
```

**C# Consumer:**
```csharp
// C# can implement the interface manually if needed
class NetworkReader : IReader
{
    public string Read() => "network data";
}

// Or use N# types
var fileReader = new FileReader();
var result = Processing.ProcessReader(fileReader);
```

### Example 4: Records

**N# Code:**
```n#
record Person {
    FirstName: string
    LastName: string
    Age: int
}
```

**C# Shape:**
```csharp
public record Person
{
    public required string FirstName { get; init; }
    public required string LastName { get; init; }
    public required int Age { get; init; }
}
```

**C# Consumer:**
```csharp
var person = new Person
{
    FirstName = "Alice",
    LastName = "Smith",
    Age = 30
};

// C# record features work!
var older = person with { Age = 31 };
```

## N# Consuming C# Code

N# can call any C# code without special handling:

### Example 1: Calling C# Classes

**C# Library:**
```csharp
namespace MyLibrary
{
    public class DataService
    {
        public async Task<List<User>> GetUsersAsync()
        {
            // Implementation
            return new List<User>();
        }

        public void ProcessData(string input, out string result)
        {
            result = input.ToUpper();
        }
    }
}
```

**N# Consumer:**
```n#
import MyLibrary

async func main() {
    service := new DataService()

    // Async works
    users := await service.GetUsersAsync()
    Console.WriteLine($"Found {users.Count} users")

    // Out parameters work
    result: string
    service.ProcessData("hello", out result)
    Console.WriteLine(result)  // "HELLO"
}
```

### Example 2: Using C# Generics

**C# Library:**
```csharp
public class Repository<T> where T : class
{
    private readonly List<T> _items = new();

    public void Add(T item) => _items.Add(item);

    public T? Find(Func<T, bool> predicate)
        => _items.FirstOrDefault(predicate);
}
```

**N# Consumer:**
```n#
import MyLibrary

class User {
    Id: Guid
    Name: string
}

func main() {
    repo := new Repository<User>()

    user := new User {
        Id: Guid.NewGuid(),
        Name: "Alice"
    }

    repo.Add(user)

    found := repo.Find(u => u.Name == "Alice")
    if found != null {
        Console.WriteLine($"Found: {found.Name}")
    }
}
```

### Example 3: C# Extension Methods

**C# Library:**
```csharp
public static class StringExtensions
{
    public static string Truncate(this string value, int maxLength)
    {
        if (value.Length <= maxLength)
            return value;
        return value.Substring(0, maxLength) + "...";
    }
}
```

**N# Consumer:**
```n#
import MyLibrary

func main() {
    text := "This is a very long string"
    short := text.Truncate(10)  // Extension methods just work!
    Console.WriteLine(short)  // "This is a..."
}
```

### Example 4: C# Events

**C# Library:**
```csharp
public class Button
{
    public event EventHandler? Clicked;

    public void Click()
    {
        Clicked?.Invoke(this, EventArgs.Empty);
    }
}
```

**N# Consumer:**
```n#
import MyLibrary

func main() {
    button := new Button()

    // Subscribe to event
    button.Clicked += (sender, args) => {
        Console.WriteLine("Button clicked!")
    }

    button.Click()  // "Button clicked!"
}
```

## Type Mappings

### How N# Types Map to C#

| N# Type | C# Type | Notes |
|---------|---------|-------|
| `class Person` | `public class Person` | PascalCase exports the public .NET surface |
| `class person` | `internal class person` | camelCase stays unexported/private-by-convention in N# and emits non-public CLR surface |
| `record User` | `public record User` | Records map directly |
| `union Result<T>` | `abstract class Result<T>` | Sealed nested classes for cases |
| `duck interface IReader` | `internal interface IReader` | Compile-time only, auto-implemented |
| `enum Status` | `static class Status` | String constants |
| `func Process()` | `public static void Process()` | Top-level functions are static |
| `struct Point` | `public struct Point` | Value types |

### Primitive Type Compatibility

All .NET primitives work identically:

| Type | Notes |
|------|-------|
| `int`, `long`, `short`, `byte` | Integers |
| `double`, `float`, `decimal` | Floating point |
| `bool` | Boolean |
| `string` | Reference type |
| `char` | Character |
| `Guid`, `DateTime`, etc. | All .NET types |

### Nullable Types

```n#
// Nullable reference type (C# 8+)
name: string? = null

// Nullable value type
age: int? = null
```

Maps to C#:
```csharp
string? name = null;
int? age = null;
```

### Generics

```n#
class Container<T> where T : class {
    value: T?
}
```

Maps to C#:
```csharp
public class Container<T> where T : class
{
    private T? value;
}
```

## Best Practices

### 1. Design Public APIs Carefully

N# types are consumed by C#, so design with C# consumers in mind:

```n#
// Good - C# friendly
class UserService {
    async func GetUserAsync(id: Guid): User? {
        return await db.FindAsync(id)
    }
}

// Less C# friendly - union might be unfamiliar
func getUserResult(id: Guid): Result<User> {
    // C# consumers need to understand union pattern
}
```

### 2. Use Unions for Internal Logic, Expose Simple Types for Public APIs

```n#
// Internal - use unions
union ParseResult {
    Success { value: int }
    Error { message: string }
}

func parseInternal(input: string): ParseResult {
    // Implementation
}

// Public API - C# friendly
func TryParse(input: string, out result: int): bool {
    parsed := parseInternal(input)
    return match parsed {
        ParseResult.Success { value: v } => {
            result = v
            return true
        },
        ParseResult.Error { } => {
            result = 0
            return false
        }
    }
}
```

### 3. Document Duck Interfaces for C# Consumers

```n#
/// <summary>
/// Implement this interface to provide custom reading logic.
/// C# implementations must have a public Read() method returning string.
/// </summary>
duck interface IReader {
    func Read(): string
}
```

### 4. Use Attributes for Framework Integration

```n#
import System.ComponentModel.DataAnnotations
import Microsoft.AspNetCore.Mvc

[ApiController]
[Route("api/[controller]")]
class UsersController : ControllerBase {
    [HttpGet]
    func GetAll(): IActionResult {
        // Implementation
    }

    [HttpPost]
    func Create([FromBody] user: CreateUserRequest): IActionResult {
        // Implementation
    }
}

class CreateUserRequest {
    [Required]
    [StringLength(100)]
    Name: string

    [EmailAddress]
    Email: string
}
```

### 5. Leverage C#'s Ecosystem

Don't reinvent the wheel - use existing C# libraries:

```n#
import Dapper
import Newtonsoft.Json
import FluentValidation
import AutoMapper
import Serilog

// Verify each package scenario with focused tests before release claims.
```

## Mixed Solution Example

Here's how to structure a solution with both N# and C#:

```
MySolution/
├── MySolution.sln
├── Core/                       (N# - domain logic)
│   ├── Core.csproj
│   ├── project.yml
│   ├── Models.nl              (Unions, records)
│   └── Services.nl            (Business logic)
├── Infrastructure/            (C# - existing code)
│   ├── Infrastructure.csproj
│   └── Database/
│       └── DbContext.cs
├── WebApi/                    (N# - new API)
│   ├── WebApi.csproj
│   ├── project.yml
│   ├── Controllers.nl
│   └── Program.nl
└── Tests/                     (C# - xUnit tests)
    ├── Tests.csproj
    └── CoreTests.cs           (Testing N# code from C#!)
```

**Core.csproj:**
```xml
<Project Sdk="NSharpLang.Sdk" />
```

**Tests.csproj (C#):**
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="../Core/Core.csproj" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="xunit" Version="2.4.2" />
  </ItemGroup>
</Project>
```

**CoreTests.cs:**
```csharp
using Xunit;
using Core;

public class UserServiceTests
{
    [Fact]
    public void CanCreateUser()
    {
        // Testing N# code from C#!
        var service = new UserService();
        var user = service.CreateUser("Alice", 30);

        Assert.Equal("Alice", user.Name);
        Assert.Equal(30, user.Age);
    }
}
```

## Troubleshooting

### Issue: C# Can't Find N# Types

**Solution**: Make sure the N# project is built first:

```bash
dotnet build Core/Core.csproj
dotnet build Tests/Tests.csproj
```

### Issue: Duck Interface Not Recognized

**Problem**: C# code doesn't implement duck interface automatically.

**Solution**: Duck interfaces are N#-only. For C# consumers, either:
1. Explicitly implement the interface in C#
2. Use regular interfaces in public APIs

### Issue: Union Pattern Matching in C#

**Problem**: C# switch expressions work but aren't exhaustive.

**Solution**: This is expected. N#'s exhaustiveness checking is N#-only. C# can still use the types:

```csharp
var result = Divide(10, 0);

var message = result switch
{
    Result<int>.Success s => $"Value: {s.Value}",
    Result<int>.Failure f => $"Error: {f.Error}",
    _ => "Unknown"  // C# requires this
};
```

## Next Steps

- **[C# Migration Guide](csharp-migration.md)** - Migrate from C# to N#
- **[Types Guide](types.md)** - Learn about N# type system
- **[Examples](../../examples/)** - See interop in action

## Resources

- [Project README](../../README.md)
- [Language Design](../../DESIGN.md)
- [Minimal API Example](../../examples/14-minimal-api/)
