// Generic Method Calls Example
// Demonstrates explicit type argument syntax for generic methods

using System
using System.Linq
using System.Collections.Generic

// Generic helper functions
func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }
    return list
}

// Main entry point
func Main() {
    print "=== Generic Method Calls Example ==="
    print ""

    // Example 1: Basic generic method call with single type argument
    print "1. Basic generic method with explicit type:"
    numbers := CreateList<int>(1, 2, 3, 4, 5)
    print $"Created list with {numbers.Count} integers"

    // Example 2: Generic method call on LINQ extension methods
    print ""
    print "2. LINQ methods with explicit types:"
    let items: int[] = [1, 2, 3, 4, 5]

    // Cast to specific type
    objects := items.Cast<object>().ToList()
    print $"Cast {items.Length} items to object"

    // OfType - filter by type
    mixed := new List<object>()
    mixed.Add(1)
    mixed.Add("hello")
    mixed.Add(2)
    mixed.Add("world")

    integers := mixed.OfType<int>().ToList()
    strings := mixed.OfType<string>().ToList()
    print $"Found {integers.Count} integers and {strings.Count} strings in mixed list"

    // Example 4: Nested generic types as type arguments
    print ""
    print "4. Nested generic type arguments:"

    // Create a list of lists
    matrix := new List<List<int>>()
    matrix.Add(CreateList<int>(1, 2, 3))
    matrix.Add(CreateList<int>(4, 5, 6))
    matrix.Add(CreateList<int>(7, 8, 9))
    print $"Created {matrix.Count}x{matrix[0].Count} matrix"

    // Example 5: Nullable types in type arguments
    print ""
    print "5. Nullable type arguments:"
    nullableNumbers := CreateList<int?>(1, null, 3, null, 5)
    nonNull := nullableNumbers.Where(n => n != null).ToList()
    print $"List has {nullableNumbers.Count} items, {nonNull.Count} are non-null"

    // Example 6: Array types in type arguments
    print ""
    print "6. Array type arguments:"
    arrayList := CreateList<int[]>([1, 2], [3, 4], [5, 6])
    print $"Created list of {arrayList.Count} arrays"

    // Example 7: Dictionary/Complex generic types
    print ""
    print "7. Dictionary type arguments:"
    dictList := new List<Dictionary<string, int>>()
    scores := new Dictionary<string, int>()
    scores["Alice"] = 95
    scores["Bob"] = 87
    dictList.Add(scores)
    print $"Created list with {dictList.Count} dictionaries"

    print ""
    print "=== All examples completed successfully! ==="
}
