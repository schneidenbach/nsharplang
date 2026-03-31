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

// Explicit modifiers
public func PublicMethod() { }
private func privateMethod() { }
internal func InternalMethod() { }
protected func ProtectedMethod() { }
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

### Params Collections (C# 13)

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

```n#
// Type inferred from context
numbers := [1, 2, 3, 4, 5]
doubled := numbers.Select(x => x * 2).ToList()

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
func async fetchData(url: string): string {
    client := new HttpClient()
    result := await client.GetStringAsync(url)
    return result
}
```

### Async with Task<T>

```n#
func async processFile(path: string): Task<string> {
    content := await File.ReadAllTextAsync(path)
    return content.ToUpper()
}
```

### Async with ValueTask<T>

```n#
func async getValue(): ValueTask<int> {
    // ValueTask is optimized for synchronous completion
    await Task.Delay(100)
    return 42
}
```

### Async Void

```n#
// Only for event handlers
func async onButtonClick() {
    await Task.Delay(1000)
    Console.WriteLine("Clicked!")
}
```

### Implicit Task Wrapping

N# automatically wraps return values in Task<T>:

```n#
func async getUser(id: int): User {
    // Compiler wraps User in Task<User>
    user := await database.FindAsync(id)
    return user
}
```

### Async LINQ

```n#
func async processItems(items: List<string>): List<int> {
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
func async* generateNumbers(count: int): IAsyncEnumerable<int> {
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
func async orchestrate(): Task<int> {
    func async fetchAsync(id: int): Task<string> {
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
func async fetchAndProcess(): string {
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
    func async processAsync(): Task<int> {
        func async validateAsync(item: string): Task<bool> {
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
- **[Language Tour](language-tour.md)** - Comprehensive language overview including async

## Resources

- [Project README](https://github.com/schneidenbach/nsharplang/blob/main/README.md)
- [Examples](/examples)
- [Language Design](https://github.com/schneidenbach/nsharplang/blob/main/docs/DESIGN.md)
