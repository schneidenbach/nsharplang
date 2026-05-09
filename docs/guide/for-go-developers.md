# N# for Go Developers

N# is "Go for .NET." If you write Go, a lot of N# will feel familiar. Here's how your Go knowledge maps over.

## What's the Same

| Go | N# | Notes |
|----|-----|-------|
| `:=` | `:=` | Short variable declaration |
| `func` | `func` | Same keyword |
| `interface{}` | `duck interface` | Structural typing |
| `result, err := f()` | `result, err := f()` | Same error pattern |
| `go fmt` | `nlc format` | One canonical style |
| `go test` | `nlc test` | Tests near code |
| No semicolons | No semicolons | Clean syntax |
| PascalCase = exported | PascalCase = exported/public, camelCase = unexported/private-by-convention | Convention-based visibility; no C# `public`/`private` noise |

## Variables

**Go:**
```go
name := "Alice"
var count int = 5
const pi = 3.14
```

**N#:**
```n#
name := "Alice"
count: int = 5
let pi := 3.14
```

`:=` works the same way. `let` is like `const` but for immutable bindings.

## Functions

**Go:**
```go
func add(a int, b int) int {
    return a + b
}

func greet(name string) {
    fmt.Println("Hello, " + name)
}
```

**N#:**
```n#
func add(a: int, b: int): int {
    return a + b
}

func greet(name: string) {
    print $"Hello, {name}"
}
```

Difference: parameters are `name: type` (colon-separated), return type comes after `)` with a colon.

## Structs and Types

**Go:**
```go
type Person struct {
    Name string
    Age  int
}

func (p Person) Greet() string {
    return fmt.Sprintf("Hi, I'm %s", p.Name)
}
```

**N#:**
```n#
// Record (value equality, like Go structs)
record Person(name: string, age: int) {
    func Greet(): string {
        return $"Hi, I'm {name}"
    }
}

// Struct (value type, stack-allocated)
struct Point(x: double, y: double)

// Class (reference type, heap-allocated)
class Service {
    Name: string

    constructor(name: string) {
        Name = name
    }
}
```

N# has more type options than Go: `struct` for value types, `record` for immutable data with value equality, and `class` for reference types. Methods go inside the type declaration.

## Interfaces

**Go:**
```go
type Reader interface {
    Read() string
}

// FileReader implicitly satisfies Reader
type FileReader struct{ path string }

func (f FileReader) Read() string {
    return "file contents"
}

func process(r Reader) {
    fmt.Println(r.Read())
}
```

**N#:**
```n#
duck interface IReader {
    func Read(): string
}

// FileReader implicitly satisfies IReader — no declaration needed
class FileReader {
    path: string

    constructor(p: string) { path = p }

    func Read(): string {
        return "file contents"
    }
}

func process(r: IReader) {
    print r.Read()
}

// Just works
process(new FileReader("/tmp/data"))
```

`duck interface` = Go interfaces. Structural typing, implicit satisfaction. N# also has regular `interface` (like Java/C#) for when you need explicit contracts.

## Error Handling

**Go:**
```go
result, err := doThing()
if err != nil {
    log.Fatal(err)
}
fmt.Println(result)
```

**N#:**
```n#
result, err := doThing()
if err != null {
    print $"Error: {err.Message}"
    return
}
print result
```

Same pattern. In N#, functions throw exceptions under the hood, but the two-variable assignment catches them as an `Exception?` — just like Go catches errors.

## Goroutines vs Async/Await

**Go:**
```go
func fetchData() string {
    // blocking call
    return http.Get(url)
}

go fetchData()
```

**N#:**
```n#
async func fetchData(): string {
    return await client.GetStringAsync(url)
}

result := await fetchData()
```

Different model: Go uses goroutines (lightweight threads), N# uses async/await (cooperative scheduling). The async/await model is explicit about what's asynchronous but gives you structured concurrency.

## Packages and Imports

**Go:**
```go
package main

import (
    "fmt"
    "strings"
)
```

**N#:**
```n#
package MyApp

import System
import System.Linq
```

`package` = `package`. `import` = `import`. N# imports are .NET namespaces.

## Enums

**Go:**
```go
type Status int

const (
    StatusActive  Status = iota
    StatusPending
    StatusDone
)
```

**N#:**
```n#
// Int enums
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2
}

// String enums (Go doesn't have these!)
enum Status {
    Active = "active",
    Pending = "pending",
    Done = "done"
}
```

N# has proper enums — both int and string. No `iota` tricks needed.

## Pattern Matching

**Go:**
```go
switch v := value.(type) {
case int:
    fmt.Println("integer")
case string:
    fmt.Println("string")
default:
    fmt.Println("other")
}
```

**N#:**
```n#
result := match value {
    0 => "zero",
    x when x > 0 => "positive",
    _ => "other"
}

// Union pattern matching (Go doesn't have this)
union Result {
    Success { value: int }
    Failure { error: string }
}

message := match result {
    Result.Success { value } => $"Got: {value}",
    Result.Failure { error } => $"Error: {error}"
}
```

N# has far richer pattern matching than Go: relational patterns, list patterns, union destructuring, and exhaustiveness checking.

## Generics

**Go:**
```go
func Map[T any, U any](items []T, f func(T) U) []U {
    result := make([]U, len(items))
    for i, item := range items {
        result[i] = f(item)
    }
    return result
}
```

**N#:**
```n#
import System.Linq

// N# has full generics with constraints
func Map<T, U>(items: T[], f: Func<T, U>): U[] {
    return items.Select(f).ToArray()
}

// Or just use LINQ directly
doubled := numbers.Select(x => x * 2).ToArray()
```

N# generics are more mature — .NET has had them since 2005. Full constraint support, variance, and deep library integration.

## Testing

**Go:**
```go
// calculator_test.go
func TestAdd(t *testing.T) {
    result := Add(2, 3)
    if result != 5 {
        t.Errorf("expected 5, got %d", result)
    }
}
```

**N#:**
```n#
// Calculator.tests.nl
test "should add two numbers" {
    result := Calculator.Add(2, 3)
    assert result == 5
}
```

Same philosophy — tests live near code, named descriptively. Run with `nlc test`.

### Table-Driven Tests (Go's Most Iconic Pattern)

**Go:**
```go
func TestAdd(t *testing.T) {
    tests := []struct {
        a, b, expected int
    }{
        {1, 2, 3},
        {0, 0, 0},
        {-1, 1, 0},
    }
    for _, tt := range tests {
        t.Run(fmt.Sprintf("%d+%d", tt.a, tt.b), func(t *testing.T) {
            if got := Add(tt.a, tt.b); got != tt.expected {
                t.Errorf("got %d, want %d", got, tt.expected)
            }
        })
    }
}
```

**N#:**
```n#
test "should add" with (a: int, b: int, expected: int) [
    (1, 2, 3),
    (0, 0, 0),
    (-1, 1, 0)
] {
    assert Add(a, b) == expected
}
```

Same data-driven philosophy, but with dedicated syntax instead of anonymous structs + loops. Transpiles to XUnit `[Theory]`/`[InlineData]`.

### Assert Messages & Throws

**Go:**
```go
t.Errorf("expected 5, got %d", result)  // custom messages
```

**N#:**
```n#
assert result == 5, "expected correct sum"
assert throws DivideByZeroException {
    Calculator.Divide(10, 0)
}
```

### Setup & Skip

```n#
setup {
    store := new TaskStore()
    service := new TaskService(store)
}

test "should add task" {
    assert service.AddTask("Test", Priority.High, tags, "") != null
}

test "needs network" skip "CI has no network" {
    // skipped
}
```

## Formatting

**Go:**
```bash
go fmt ./...
```

**N#:**
```bash
nlc format
```

One canonical style, enforced by tooling. Same philosophy as Go.

## CLI Toolchain

| Go | N# | Purpose |
|----|----|---------|
| `go build` | `dotnet build` | Compile |
| `go run` | `dotnet run` | Build + run |
| `go test` | `nlc test` | Run tests |
| `go test -run` | `nlc test --filter` | Filter tests |
| `go test -cover` | `nlc test --coverage` | Code coverage |
| `go test -json` | `nlc test --json` | Machine-readable output |
| `go fmt` | `nlc format` | Format code |
| `go vet` | `nlc lint` | Static analysis |
| `go doc` | `nlc query symbols` | Code intelligence |

## What Go Developers Will Love

- **Convention-based visibility** — PascalCase is exported/public and camelCase is unexported/private-by-convention, just like Go's exported names. C# `public`/`private` modifiers are migration debris in ordinary N#; the formatter drops redundant ones but preserves semantic escape hatches like `public legacyCamel` and `private SecretPascal` when they intentionally override casing.
- **Tight syntax** — No semicolons, no noise
- **`:=` everywhere** — Same declaration shorthand
- **`duck interface`** — Structural typing, Go's best feature
- **`result, err :=`** — The error handling pattern you know
- **Strong CLI** — `nlc` toolchain inspired by `go` command
- **Fast compilation** — Transpiles to C#, then .NET compiles (incremental builds are fast)

## What's Different (and Better)

- **Full generics with constraints** — More powerful than Go's type parameters
- **Pattern matching** — Far richer than `switch`
- **Discriminated unions** — Tagged unions with exhaustiveness checking
- **Async/await** — Structured concurrency instead of goroutines
- **LINQ** — Declarative collection processing
- **Massive ecosystem** — All of NuGet (300K+ packages)

## Next Steps

- **[Getting Started](getting-started.md)** — Create your first project
- **[Language Tour](language-tour.md)** — Every feature with examples
- **[For C# Developers](for-csharp-developers.md)** — If you also know C#
