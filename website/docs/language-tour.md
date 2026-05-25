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

Regular interfaces require explicit implementation with `:` syntax, just like C#. They support default implementations.

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

String enums map enum members to string values — no more `const string` hacks.

```n#
enum Status {
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

Standard integer enums work like C#.

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

    // LINQ — same as C#
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

N# generics use the same `<T>` syntax as C#, with full constraint support.

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

Run the same test body with multiple sets of inputs (Go-style):

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

### Skip Tests

Mark a test as skipped with a reason:

```n#
test "needs network" skip "CI has no network" {
    response := HttpClient.Get("https://api.example.com")
    assert response.StatusCode == 200
}
```

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

Use `$"..."` for interpolated strings, same as C#.

```n#
name := "Alice"
age := 30
print $"Name: {name}, Age: {age}"
print $"Next year: {age + 1}"
print $"Pi: {3.14159:F2}"             // Pi: 3.14
```

## Imports and Packages

```n#
// Import .NET namespaces
import System
import System.Linq
import System.Collections.Generic

// Alias an import
import Json = System.Text.Json

// Declare your namespace
package MyApp.Services

class UserService {
    // ...
}
```

## Visibility

N# uses Go-style naming conventions for visibility — do not write C# `public`/`private` keywords for ordinary code. The formatter removes redundant `public`/`private` when casing already expresses the same visibility.

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
    public legacyCamel: string      // forced public for interop/migration
    private SecretPascal: string    // forced hidden despite PascalCase
    internal ConnectionString: string
    protected BaseUrl: string
}
```

Enum cases are part of the containing enum's value set. Export is controlled by the enum itself, so lowercase enum cases remain visible when the enum is exported; use casing diagnostics as style guidance, not as API hiding.

## Next Steps

- **[For C# Developers](for-csharp-developers.md)** — Side-by-side syntax comparison
- **[For Go Developers](for-go-developers.md)** — How Go concepts map to N#
- **[Pattern Matching Guide](pattern-matching.md)** — Deep dive into pattern matching
- **[Types Guide](types.md)** — Advanced type system features
- **[Examples](/examples)** — curated example projects
