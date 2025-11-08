# Collections

## Arrays

### Array Literals
```
let numbers := [1, 2, 3, 4, 5]
let names := ["Alice", "Bob", "Charlie"]
```

### Array Type Inference
Element type inferred from literals:
```
let items := [1, 2, 3]      // int[]
let mixed := [1, "two"]     // NOT supported (C# doesn't allow mixed types)
```

### Explicit Array Types
```
let numbers: int[] = [1, 2, 3]
```

### Empty Arrays
```
let empty: int[] = []
```

## Collection Expressions (C# 12)

N# array literals transpile to C# 12 collection expressions:

**N# code:**
```
let items := [1, 2, 3]
```

**Generated C#:**
```csharp
int[] items = [1, 2, 3];
```

## Indexing

### Array Access
```
let first := items[0]
let last := items[^1]        // Index from end
```

### Ranges
```
let slice := items[1..3]     // Items at index 1 and 2
let fromStart := items[2..]  // From index 2 to end
let toEnd := items[..3]      // From start to index 2
```

## Null-Conditional Indexing

```
let value := dict?["key"]    // Returns null if dict is null
```

## Collection Initializers with Indexers

Initialize dictionaries with indexer syntax (C# 6):

```
let dict := new Dictionary<string, int> {
    ["Alice"] = 90,
    ["Bob"] = 85,
    ["Charlie"] = 95
}
```

Transpiles to C# indexer initializer syntax.

## Params Arrays

Functions can accept variable arguments:

```
func Sum(params values: int[]): int {
    total := 0
    for v in values {
        total += v
    }
    return total
}

// Call with any number of arguments
result := Sum(1, 2, 3, 4, 5)
```

## Params Collections (C# 13)

Params supports modern collection types:

```
func Sum(params values: ReadOnlySpan<int>): int {
    // Zero-allocation, high-performance
}

func Process(params items: IEnumerable<string>) {
    // Works with LINQ
}

func Handle(params data: List<int>) {
    // Works with List
}
```

Supported types:
- Arrays: `T[]`
- Spans: `Span<T>`, `ReadOnlySpan<T>`
- Interfaces: `IEnumerable<T>`, `IReadOnlyList<T>`, `IList<T>`, `ICollection<T>`
- Collections: `List<T>`, `HashSet<T>`, `Queue<T>`, `Stack<T>`
- Memory: `Memory<T>`, `ReadOnlyMemory<T>`, `ArraySegment<T>`

## List Patterns

Match on list/array structure:

```
result := list match {
    [] => "empty",
    [x] => $"single: {x}",
    [first, ..] => $"starts with {first}",
    [.., last] => $"ends with {last}",
    [first, .. middle, last] => $"first={first}, last={last}",
    [1, 2, 3] => "exact sequence"
}
```

### Slice Patterns
- `[]`: Empty list
- `[x]`: Single element
- `[first, ..]`: First element + rest
- `[.., last]`: Rest + last element
- `[first, .. rest, last]`: First, middle, last
- `[.. rest]`: Capture all elements

## Spread Operator

Spread arrays in function calls:

```
let numbers := [1, 2, 3]
Sum(...numbers)              // Equivalent to Sum(1, 2, 3)
```

## Iterators (Lazy Collections)

Create lazy sequences with `yield`:

```
func* GetNumbers(): IEnumerable<int> {
    for i := 0; i < 10; i++ {
        yield i
    }
}

// Usage (lazy evaluation)
for num in GetNumbers() {
    print num
}
```

### Yield Break
```
func* GetUntilNegative(items: int[]): IEnumerable<int> {
    for item in items {
        if item < 0 {
            yield break
        }
        yield item
    }
}
```

## LINQ Integration

N# works with .NET LINQ:

```
using System.Linq

let numbers := [1, 2, 3, 4, 5]
let evens := numbers.Where(x => x % 2 == 0).ToArray()
let doubled := numbers.Select(x => x * 2).ToList()
let sum := numbers.Sum()
```

## Immutable Collections

Work with .NET immutable collections:

```
using System.Collections.Immutable

let list := ImmutableList.Create(1, 2, 3)
let newList := list.Add(4)   // Returns new list
```

## Dictionary Operations

```
let dict := new Dictionary<string, int> {
    ["Alice"] = 90,
    ["Bob"] = 85
}

// Add
dict.Add("Charlie", 95)
dict["Diana"] = 92

// Access
let score := dict["Alice"]
let exists := dict.ContainsKey("Bob")

// Try get value
result, found := dict.TryGetValue("Alice")
if found {
    print $"Score: {result}"
}
```

## Generic Collections

```
let list := new List<string>()
list.Add("item1")
list.Add("item2")

let set := new HashSet<int>([1, 2, 3, 3])  // Deduplicates

let queue := new Queue<int>()
queue.Enqueue(1)
let item := queue.Dequeue()

let stack := new Stack<int>()
stack.Push(1)
let top := stack.Pop()
```

## Collection Performance Tips

1. **Use ReadOnlySpan<T> for params** - Zero allocation
2. **Use arrays for fixed-size collections** - Fastest access
3. **Use List<T> for dynamic collections** - Good all-around
4. **Use HashSet<T> for uniqueness** - O(1) lookups
5. **Use iterators for large datasets** - Lazy evaluation
6. **Use LINQ carefully** - Can create temporary allocations
