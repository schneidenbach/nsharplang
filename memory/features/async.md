# Async Programming

## Async/Await

N# supports C# async/await for asynchronous programming.

### Async Functions

```
func async FetchData(url: string): Task<string> {
    response := await Http.GetAsync(url)
    return await response.Content.ReadAsStringAsync()
}
```

### Await Expressions

```
result := await SomeAsyncOperation()
```

### Async Main

```
func async Main() {
    await DoWorkAsync()
}
```

### ValueTask Support

Configure default async type in `project.yml`:

```yaml
asyncDefaultType: ValueTask
```

Then async functions without explicit return type use `ValueTask`:

```
func async Process() {
    // Return type: ValueTask (not Task)
    await DoWorkAsync()
}
```

## Async Streams (IAsyncEnumerable)

Async streams combine async/await with yield for lazy asynchronous iteration.

### Async Iterator Functions

Use `async*` modifier:

```
func async* GetDataAsync(): IAsyncEnumerable<string> {
    for i := 0; i < 10; i++ {
        await Task.Delay(100)
        yield $"Item {i}"
    }
}
```

### Consuming Async Streams

Use `await foreach`:

```
func async ProcessData() {
    await foreach item in GetDataAsync() {
        print $"Got: {item}"
    }
}
```

### Benefits

- **Lazy evaluation**: Data produced on demand
- **Memory efficient**: No buffering needed
- **Cancellation support**: Works with CancellationToken
- **Composable**: Works with LINQ async extensions

### Real-World Example: Pagination

```
class ApiClient {
    func async* FetchPagesAsync(url: string): IAsyncEnumerable<Page> {
        nextUrl: string? = url

        while nextUrl != null {
            response := await Http.GetAsync(nextUrl)
            page := await response.Content.ReadFromJsonAsync<Page>()
            yield page
            nextUrl = page.NextUrl
        }
    }
}

// Usage
await foreach page in client.FetchPagesAsync("/api/data") {
    ProcessPage(page)
}
```

## Transpilation

### Regular Async Functions

**N# code:**
```
func async Fetch(): Task<string> {
    return await GetDataAsync()
}
```

**Generated C#:**
```csharp
public static async Task<string> Fetch()
{
    return await GetDataAsync();
}
```

### Async Iterators

**N# code:**
```
func async* GetNumbers(): IAsyncEnumerable<int> {
    yield 1
    yield 2
}
```

**Generated C#:**
```csharp
public static async IAsyncEnumerable<int> GetNumbers()
{
    yield return 1;
    yield return 2;
}
```

**Important:** NOT wrapped in `Task<>` or `ValueTask<>`. The `async` keyword in C# + `IAsyncEnumerable<T>` return type creates an async iterator.

## Yield Break

Early termination of iterators:

```
func async* GetItems(): IAsyncEnumerable<int> {
    for i := 0; i < 100; i++ {
        if i > 50 {
            yield break  // Stop iteration
        }
        await Task.Delay(10)
        yield i
    }
}
```

Transpiles to C# `yield break;`

## Cancellation Support

Async streams work with CancellationToken:

```
using System.Runtime.CompilerServices
using System.Threading

func async* GenerateNumbers(
    [EnumeratorCancellation] token: CancellationToken
): IAsyncEnumerable<int> {
    i := 0
    while !token.IsCancellationRequested {
        await Task.Delay(100, token)
        yield i++
    }
}
```

## Task vs ValueTask

### When to use Task
- Caching/storing async operations
- Arbitrary composition
- Default for most scenarios

### When to use ValueTask
- High-performance scenarios
- Pooled operations
- Reduced allocations

Configure in `project.yml`:
```yaml
asyncDefaultType: ValueTask  # or Task (default)
```

## Async Lambdas

```
handler := async (x) => {
    result := await ProcessAsync(x)
    return result
}
```

## Error Handling in Async

Use try-catch or N# error handling pattern:

```
// Try-catch
func async Fetch() {
    try {
        return await Http.GetAsync(url)
    } catch e {
        print $"Error: {e.Message}"
        throw
    }
}

// N# error pattern
result, err := await FetchAsync()
if err != null {
    print $"Error: {err.Message}"
}
```
