import React from 'react';
import Layout from '@theme/Layout';
import CodeBlock from '@theme/CodeBlock';

const categories = [
  {
    title: 'Basics',
    examples: [
      {
        title: 'Hello World',
        code: `import System

func Main() {
    name := "World"
    print $"Hello, {name}!"
}`,
      },
      {
        title: 'Variables & Type Inference',
        code: `func Main() {
    x := 5                    // int (inferred)
    name := "Alice"           // string (inferred)
    isActive := true          // bool (inferred)

    y: int = 10               // explicit type
    let pi: double = 3.14159  // immutable

    let items = [1, 2, 3]    // immutable int[]
    print $"{name}: {x + y}"
}`,
      },
      {
        title: 'Control Flow',
        code: `func Main() {
    x := 42

    if x > 100 {
        print "big"
    } else if x > 10 {
        print "medium"
    } else {
        print "small"
    }

    items := [1, 2, 3, 4, 5]
    for item in items {
        print item
    }

    count := 0
    while count < 3 {
        print count
        count += 1
    }
}`,
      },
      {
        title: 'String Interpolation',
        code: `func Main() {
    name := "Alice"
    age := 30

    // Basic interpolation
    print $"Name: {name}, Age: {age}"

    // Expressions in interpolation
    print $"Next year: {age + 1}"

    // Method calls
    print $"Upper: {name.ToUpper()}"
}`,
      },
    ],
  },
  {
    title: 'Functions',
    examples: [
      {
        title: 'Basic Functions',
        code: `func Add(a: int, b: int): int {
    return a + b
}

func Greet(name: string) {
    print $"Hello, {name}!"
}

// Expression-bodied
func Double(x: int): int => x * 2

func Main() {
    print Add(3, 4)
    Greet("World")
    print Double(21)
}`,
      },
      {
        title: 'Local Functions & Closures',
        code: `import System.Linq

func ProcessData(items: int[]): int[] {
    func isValid(value: int): bool {
        return value > 0 && value < 100
    }

    return items.Where(isValid).ToArray()
}

func Main() {
    data := [5, -1, 42, 200, 17]
    valid := ProcessData(data)
    foreach v in valid {
        print v  // 5, 42, 17
    }
}`,
      },
      {
        title: 'Generic Functions',
        code: `func Identity<T>(value: T): T => value

func PrintAll<T>(items: T[]) {
    for item in items {
        print item
    }
}

func Main() {
    print Identity(42)
    print Identity("hello")
    PrintAll(["a", "b", "c"])
}`,
      },
      {
        title: 'Params & Optional',
        code: `func Sum(params numbers: int[]): int {
    total := 0
    for num in numbers {
        total += num
    }
    return total
}

func Greet(name: string, greeting: string = "Hello"): string {
    return $"{greeting}, {name}!"
}

func Main() {
    print Sum(1, 2, 3, 4, 5)
    print Greet("Alice")
    print Greet("Bob", "Hey")
}`,
      },
    ],
  },
  {
    title: 'Types',
    examples: [
      {
        title: 'Classes',
        code: `class Person {
    FirstName: string
    LastName: string
    Age: int

    constructor(firstName: string, lastName: string, age: int) {
        FirstName = firstName
        LastName = lastName
        Age = age
    }

    func FullName(): string => $"{FirstName} {LastName}"
}

func Main() {
    p := new Person("Alice", "Smith", 30)
    print p.FullName()
}`,
      },
      {
        title: 'Records',
        code: `record Point {
    X: int
    Y: int
}

func Main() {
    p1 := new Point { X: 10, Y: 20 }

    // Non-destructive mutation
    p2 := p1 with { X: 30 }

    print $"p1: ({p1.X}, {p1.Y})"
    print $"p2: ({p2.X}, {p2.Y})"

    // Value equality
    p3 := new Point { X: 10, Y: 20 }
    print $"p1 == p3: {p1 == p3}"  // true
}`,
      },
      {
        title: 'Discriminated Unions',
        code: `union HttpResponse {
    Success { statusCode: int, body: string }
    Redirect { location: string }
    ClientError { code: int, message: string }
    ServerError { code: int, details: string }
}

func Describe(r: HttpResponse): string {
    return match r {
        HttpResponse.Success { statusCode, body } =>
            $"OK ({statusCode}): {body}",
        HttpResponse.Redirect { location } =>
            $"Redirect to {location}",
        HttpResponse.ClientError { code, message } =>
            $"Client error {code}: {message}",
        HttpResponse.ServerError { code, details } =>
            $"Server error {code}: {details}"
    }
}`,
      },
      {
        title: 'Enums',
        code: `// String enum
enum Status {
    Pending = "pending",
    Active = "active",
    Done = "done"
}

// Int enum
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2
}

func Main() {
    s := Status.Active
    p := Priority.High
    print $"Status: {s}, Priority: {p}"
}`,
      },
      {
        title: 'Primary Constructors',
        code: `class Logger(name: string) {
    func Log(message: string) {
        print $"[{name}] {message}"
    }
}

func Main() {
    logger := new Logger("MyApp")
    logger.Log("Application started")
    logger.Log("Processing request...")
}`,
      },
      {
        title: 'Interfaces',
        code: `interface IShape {
    func GetArea(): double
}

class Circle : IShape {
    Radius: double

    constructor(radius: double) {
        Radius = radius
    }

    func GetArea(): double => 3.14159 * Radius * Radius
}

func PrintArea(shape: IShape) {
    print $"Area: {shape.GetArea()}"
}`,
      },
    ],
  },
  {
    title: 'Pattern Matching',
    examples: [
      {
        title: 'Literal & Relational Patterns',
        code: `func Classify(age: int): string {
    return match age {
        < 13 => "child",
        < 20 => "teenager",
        >= 20 => "adult"
    }
}

func HttpStatus(code: int): string {
    return match code {
        200 => "OK",
        404 => "Not Found",
        500 => "Server Error",
        _ => "Unknown"
    }
}`,
      },
      {
        title: 'Type & Property Patterns',
        code: `func Describe(obj: object): string {
    return match obj {
        int x => $"Integer: {x}",
        string s => $"String: {s}",
        _ => "Unknown type"
    }
}

func Greet(person: Person): string {
    return match person {
        { Age: < 13 } => "Hey kid!",
        { Age: >= 13, Name: "Alice" } => "Hi Alice!",
        _ => "Hello there"
    }
}`,
      },
      {
        title: 'List Patterns',
        code: `func Describe(nums: int[]): string {
    return match nums {
        [] => "empty",
        [x] => $"single: {x}",
        [first, ..] => $"starts with {first}",
        _ => "other"
    }
}

func Main() {
    print Describe([])          // empty
    print Describe([42])        // single: 42
    print Describe([1, 2, 3])   // starts with 1
}`,
      },
      {
        title: 'Pattern Guards',
        code: `func Categorize(value: int): string {
    return match value {
        x when x < 0 => "negative",
        0 => "zero",
        x when x > 0 and x < 100 => "small positive",
        _ => "large positive"
    }
}

func Main() {
    print Categorize(-5)   // negative
    print Categorize(0)    // zero
    print Categorize(42)   // small positive
    print Categorize(999)  // large positive
}`,
      },
    ],
  },
  {
    title: 'Async',
    examples: [
      {
        title: 'Async / Await',
        code: `import System.Threading.Tasks

func async FetchData(url: string): string {
    client := new HttpClient()
    result := await client.GetStringAsync(url)
    return result
}

func async Main() {
    data := await FetchData("https://example.com")
    print data
}`,
      },
      {
        title: 'Async Streams',
        code: `import System.Collections.Generic
import System.Threading.Tasks

func async* GetNumbersAsync(): IAsyncEnumerable<int> {
    for i := 0; i < 10; i++ {
        await Task.Delay(100)
        yield i
    }
}

func async Main() {
    await foreach num in GetNumbersAsync() {
        print $"Received: {num}"
    }
}`,
      },
    ],
  },
  {
    title: 'Collections & LINQ',
    examples: [
      {
        title: 'Collection Expressions',
        code: `import System.Collections.Generic

func Main() {
    // Array
    numbers := [1, 2, 3, 4, 5]

    // Typed collections
    let names: List<string> = ["Alice", "Bob"]
    let ids: HashSet<int> = [1, 2, 3]

    print $"Count: {names.Count}"
}`,
      },
      {
        title: 'LINQ Pipelines',
        code: `import System.Linq

func Main() {
    let numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    result := numbers
        .Where(x => x > 3)
        .Select(x => x * x)
        .OrderByDescending(x => x)
        .Take(3)
        .ToList()

    foreach n in result {
        print n  // 100, 81, 64
    }
}`,
      },
      {
        title: 'Iterators',
        code: `import System.Collections.Generic

func* Fibonacci(count: int): IEnumerable<int> {
    a := 0
    b := 1
    for i := 0; i < count; i++ {
        yield a
        temp := a
        a = b
        b = temp + b
    }
}

func Main() {
    foreach n in Fibonacci(10) {
        print n
    }
}`,
      },
      {
        title: 'Range & Index',
        code: `func Main() {
    items := ["a", "b", "c", "d", "e"]

    // Indexing from end
    last := items[^1]        // "e"
    secondLast := items[^2]  // "d"

    // Ranges
    slice := items[1..3]     // ["b", "c"]
    fromStart := items[..2]  // ["a", "b"]
    toEnd := items[3..]      // ["d", "e"]
}`,
      },
    ],
  },
  {
    title: 'C# Interop',
    examples: [
      {
        title: 'ASP.NET Minimal API',
        full: true,
        code: `import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import Microsoft.Extensions.Hosting
import System

func main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    app.MapGet("/", () => "Hello from N#!")
    app.MapGet("/time", () => DateTime.Now.ToString())
    app.MapGet("/json", () => new {
        Message: "Hello from N#",
        Timestamp: DateTime.Now,
        Language: "N#"
    })

    app.Run()
}`,
      },
      {
        title: 'Error Handling (Go-style)',
        code: `import System

func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception("divide by zero")
    }
    return a / b
}

func Main() {
    // Automatic exception capture
    result, err := Divide(10, 2)
    if err == null {
        print $"Result: {result}"
    } else {
        print $"Error: {err.Message}"
    }
}`,
      },
      {
        title: 'Using NuGet Packages',
        code: `import System.Linq

// All of .NET is available
// Add any NuGet package to project.yml
// and use it directly

func Main() {
    let numbers = [1, 2, 3, 4, 5]

    sum := numbers.Sum()
    avg := numbers.Average()

    print $"Sum: {sum}, Avg: {avg}"
}`,
      },
    ],
  },
  {
    title: 'Testing',
    examples: [
      {
        title: 'Built-in Test Syntax',
        full: true,
        code: `func Add(a: int, b: int): int => a + b

test "Add returns correct sum" {
    assert Add(2, 3) == 5
    assert Add(-1, 1) == 0
    assert Add(0, 0) == 0
}

test "Add handles large numbers" {
    result := Add(1000000, 2000000)
    assert result == 3000000
}`,
      },
    ],
  },
];

function ExampleCard({title, code, full}) {
  return (
    <div className={`example-card${full ? ' example-card--full' : ''}`}>
      <div className="example-card__header">
        <span className="example-card__title">{title}</span>
      </div>
      <div className="example-card__code">
        <CodeBlock language="nsharp">{code}</CodeBlock>
      </div>
    </div>
  );
}

export default function Examples() {
  return (
    <Layout
      title="Examples"
      description="Learn N# through real, runnable code examples.">
      <div className="examples-page">
        <div style={{marginBottom: 48}}>
          <h1 style={{fontSize: 'clamp(1.75rem, 3vw, 2.5rem)', fontWeight: 800, letterSpacing: '-0.02em', marginBottom: 8}}>
            Examples
          </h1>
          <p style={{color: 'var(--ifm-color-emphasis-600)', fontSize: '1.0625rem'}}>
            Learn N# through real, runnable code examples.
          </p>
        </div>

        {categories.map((cat, ci) => (
          <div key={ci} className="examples-category">
            <h2 className="examples-category__title">{cat.title}</h2>
            <div className="examples-grid">
              {cat.examples.map((ex, ei) => (
                <ExampleCard key={ei} {...ex} />
              ))}
            </div>
          </div>
        ))}
      </div>
    </Layout>
  );
}
