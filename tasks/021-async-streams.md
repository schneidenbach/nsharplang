# Task 021: Async Streams (IAsyncEnumerable)

**Priority:** High (Modern C# feature that's very useful)
**Dependencies:** None
**Estimated Effort:** Small (1-2 days)
**Status:** 🔥 IN PROGRESS (v1.66)

## Goal
Add support for async streams using `async*` syntax to enable asynchronous iteration patterns.

## What Are Async Streams?
Async streams (C# 8+) allow you to iterate over data that arrives asynchronously, combining `async/await` with `yield return`.

## Syntax

```nsharp
// Async iterator function with async* modifier
func async* GetNumbersAsync(): IAsyncEnumerable<int> {
    for i := 0; i < 10; i++ {
        await Task.Delay(100)
        yield i
    }
}

// Consuming async streams
func async ProcessNumbers() {
    await foreach num in GetNumbersAsync() {
        print $"Got: {num}"
    }
}
```

## Implementation Steps

### 1. Lexer Changes
- `async*` should be recognized as a function modifier combination
- `await foreach` should be tokenized correctly

### 2. Parser Changes
- Parse `async*` in function declarations
- Parse `await foreach` statements
- Set `IsAsyncIterator` flag on FunctionDeclaration

### 3. AST Changes
Add to `FunctionDeclaration`:
```csharp
public bool IsAsyncIterator { get; init; }  // true if async*
```

Add `AwaitForEachStatement`:
```csharp
public record AwaitForEachStatement(
    string VariableName,
    Expression Collection,
    Statement Body,
    int Line,
    int Column
) : Statement(Line, Column);
```

### 4. Analyzer Changes
- Validate `async*` functions return `IAsyncEnumerable<T>` or `IAsyncEnumerator<T>`
- Validate `yield` is only used in iterator or async iterator functions
- Validate `await foreach` variable type matches collection element type

### 5. Transpiler Changes
- `async*` functions transpile to `async IAsyncEnumerable<T>` methods
- `await foreach` transpiles to C# `await foreach` statement
- Keep `yield` as-is (already transpiles correctly)

## Examples

### Example 1: Basic Async Stream
```nsharp
using System.Collections.Generic
using System.Threading.Tasks

func async* GetDataAsync(): IAsyncEnumerable<string> {
    data := ["hello", "world", "async", "streams"]

    for item in data {
        await Task.Delay(500)
        yield item
    }
}

func async Main() {
    print "Starting..."

    await foreach item in GetDataAsync() {
        print $"Received: {item}"
    }

    print "Done!"
}
```

**Expected C# Output:**
```csharp
public static async IAsyncEnumerable<string> GetDataAsync()
{
    var data = new string[] { "hello", "world", "async", "streams" };

    foreach (var item in data)
    {
        await Task.Delay(500);
        yield return item;
    }
}

public static async Task Main()
{
    Console.WriteLine("Starting...");

    await foreach (var item in GetDataAsync())
    {
        Console.WriteLine($"Received: {item}");
    }

    Console.WriteLine("Done!");
}
```

### Example 2: Real-World - Paginated API
```nsharp
class ApiClient {
    func async* FetchPagesAsync(url: string): IAsyncEnumerable<Page> {
        nextUrl: string? = url

        while nextUrl != null {
            response := await FetchAsync(nextUrl)
            yield response.Page
            nextUrl = response.NextUrl
        }
    }
}

func async ProcessApi() {
    client := new ApiClient()

    await foreach page in client.FetchPagesAsync("/api/data") {
        print $"Processing page {page.Number}..."
        ProcessPage(page)
    }
}
```

### Example 3: Cancellation Support
```nsharp
using System.Runtime.CompilerServices
using System.Threading

func async* GenerateNumbers(
    [EnumeratorCancellation] cancel: CancellationToken
): IAsyncEnumerable<int> {
    i := 0
    while !cancel.IsCancellationRequested {
        await Task.Delay(100, cancel)
        yield i++
    }
}
```

## Success Criteria
- [ ] `async*` syntax parses correctly
- [ ] `IsAsyncIterator` flag set on function declarations
- [ ] `await foreach` statement parses correctly
- [ ] Transpiler emits correct C# async iterator methods
- [ ] `await foreach` transpiles to C# syntax
- [ ] At least 5 comprehensive tests (parser + transpiler)
- [ ] Example file demonstrating async streams
- [ ] All existing tests still pass

## Testing

### Parser Tests
```csharp
[Fact]
public void TestAsyncIteratorParsing()
{
    var source = "func async* GetData(): IAsyncEnumerable<int> { yield 1 }";
    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var unit = parser.ParseCompilationUnit();

    var func = unit.Declarations.OfType<FunctionDeclaration>().First();
    Assert.Equal("GetData", func.Name);
    Assert.True(func.IsAsync);
    Assert.True(func.IsAsyncIterator);
}

[Fact]
public void TestAwaitForEachParsing()
{
    var source = "func async Test() { await foreach item in items { print item } }";
    var tokens = new Lexer(source, "test").Tokenize();
    var parser = new Parser(tokens, "test");
    var unit = parser.ParseCompilationUnit();

    var func = unit.Declarations.OfType<FunctionDeclaration>().First();
    var stmt = func.Body!.Statements[0] as AwaitForEachStatement;
    Assert.NotNull(stmt);
    Assert.Equal("item", stmt.VariableName);
}
```

### Transpiler Tests
```csharp
[Fact]
public void TestAsyncIteratorTranspilation()
{
    var source = @"
func async* GetNumbers(): IAsyncEnumerable<int> {
    yield 1
    yield 2
}";

    var result = Transpile(source);

    Assert.Contains("async IAsyncEnumerable<int> GetNumbers()", result);
    Assert.Contains("yield return 1", result);
    Assert.Contains("yield return 2", result);
}

[Fact]
public void TestAwaitForEachTranspilation()
{
    var source = @"
func async Process() {
    await foreach num in GetNumbers() {
        print num
    }
}";

    var result = Transpile(source);

    Assert.Contains("await foreach", result);
    Assert.Contains("var num in GetNumbers()", result);
}
```

## Benefits
- **Modern C# feature**: Keeps N# up-to-date with latest C# capabilities
- **Real-world use cases**: Pagination, streaming data, infinite sequences
- **Composable**: Works well with LINQ, cancellation tokens, etc.
- **Performance**: Enables efficient async iteration without buffering

## Notes
- Requires C# 8+ (already targeting net9.0)
- `IAsyncEnumerable<T>` is in `System.Collections.Generic`
- Works seamlessly with existing `async/await` and `yield` support
- Can combine with cancellation tokens via `[EnumeratorCancellation]` attribute
