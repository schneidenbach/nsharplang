// Example demonstrating params collections (C# 13 feature)
// Params can now work with Span<T>, ReadOnlySpan<T>, and collection types

using System
using System.Collections.Generic

// 1. Basic params with array (original C# behavior)
func SumArray(params numbers: int[]): int {
    total := 0
    for num in numbers {
        total = total + num
    }
    return total
}

// 2. Params with ReadOnlySpan<T> - more efficient, no heap allocation
func SumReadOnlySpan(params numbers: ReadOnlySpan<int>): int {
    total := 0
    for i := 0; i < numbers.Length; i++ {
        total = total + numbers[i]
    }
    return total
}

// 3. Params with Span<T> - mutable span
func ModifyValues(params values: Span<int>) {
    for i := 0; i < values.Length; i++ {
        values[i] = values[i] * 2
    }
}

// 4. Params with IEnumerable<T> - maximum flexibility
func PrintAll(params items: IEnumerable<string>) {
    for item in items {
        print $"  - {item}"
    }
}

// 5. Params with List<T> - dynamic collection
func BuildList(params items: List<int>): List<int> {
    result := new List<int>()
    for item in items {
        result.Add(item)
    }
    return result
}

// 6. Params with IReadOnlyList<T> - read-only collection interface
func FormatItems(separator: string, params items: IReadOnlyList<string>): string {
    if items.Count == 0 {
        return ""
    }

    result := items[0]
    for i := 1; i < items.Count; i++ {
        result = result + separator + items[i]
    }
    return result
}

// 7. Generic params with collection type
func Transform<T>(transformer: Func<T, T>, params items: IEnumerable<T>): T[] {
    result := new List<T>()
    for item in items {
        result.Add(transformer(item))
    }
    return result.ToArray()
}

func Main() {
    print "=== Params Collections (C# 13) Examples ==="
    print ""

    // Array params (original behavior)
    print "1. Array params:"
    sum1 := SumArray(1, 2, 3, 4, 5)
    print $"   Sum(1,2,3,4,5) = {sum1}"
    print ""

    // ReadOnlySpan params (C# 13 - more efficient!)
    print "2. ReadOnlySpan<T> params (zero allocation):"
    sum2 := SumReadOnlySpan(10, 20, 30, 40)
    print $"   Sum(10,20,30,40) = {sum2}"
    print ""

    // IEnumerable params (C# 13)
    print "3. IEnumerable<T> params (flexible):"
    print "   Items:"
    PrintAll("Apple", "Banana", "Cherry", "Date")
    print ""

    // IReadOnlyList params (C# 13)
    print "4. IReadOnlyList<T> params with separator:"
    formatted := FormatItems(", ", "Alice", "Bob", "Charlie", "David")
    print $"   Result: {formatted}"
    print ""

    // Generic params with transform
    print "5. Generic transform with IEnumerable<T> params:"
    doubled := Transform(x => x * 2, 1, 2, 3, 4, 5)
    doubledStr := String.Join(", ", doubled)
    print $"   Doubled: [{doubledStr}]"
    print ""

    // List params (C# 13)
    print "6. List<T> params:"
    list := BuildList(100, 200, 300)
    print $"   Built list with {list.Count} items"
    print ""

    print "=== Benefits of Params Collections (C# 13) ==="
    print "  • ReadOnlySpan/Span: Zero heap allocation, better performance"
    print "  • IEnumerable: Works with LINQ and any collection type"
    print "  • IReadOnlyList: Indexed access with read-only guarantee"
    print "  • List/Collection types: More flexibility than arrays"
    print "  • All with the same convenient params syntax!"
}
