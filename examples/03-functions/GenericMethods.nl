// Generic Method Calls Example
// Demonstrates type inference and explicit type argument syntax for generic methods
import System.Collections.Generic
import System.Linq


// Generic helper functions
func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func Identity<T>(x: T): T => x

func Pair<A, B>(a: A, b: B): string => $"({a}, {b})"

func First<T>(items: List<T>): T => items[0]

// Main entry point
func Main() {
    print "=== Generic Method Calls Example ==="
    print ""

    // Example 1: Type inference — type parameters inferred from arguments
    print "1. Type inference (no explicit type args needed):"
    inferredInt := Identity(42)
    // T inferred as int
    inferredStr := Identity("hello")
    // T inferred as string
    print $"Identity(42) = {inferredInt}"
    print $"Identity(\"hello\") = {inferredStr}"

    // Example 2: Multi-parameter type inference
    print ""
    print "2. Multi-parameter inference:"
    pairResult := Pair(1, "hello")
    // A=int, B=string inferred
    print $"Pair(1, \"hello\") = {pairResult}"

    // Example 3: Inference from generic container arguments
    print ""
    print "3. Inference from container types:"
    myList := new List<int>()
    myList.Add(10)
    myList.Add(20)
    firstItem := First(myList)
    // T=int inferred from List<int>
    print $"First(myList) = {firstItem}"

    // Example 4: Inference with params arrays
    print ""
    print "4. Inference with params:"
    numbers := CreateList(1, 2, 3, 4, 5)
    // T=int inferred from args
    strings := CreateList("a", "b", "c")
    // T=string inferred from args
    print $"CreateList(1,2,3,4,5) created list with {numbers.Count} integers"
    print $"CreateList(\"a\",\"b\",\"c\") created list with {strings.Count} strings"

    // Example 5: Explicit type args still work (required for Cast/OfType)
    print ""
    print "5. Explicit type args (when inference isn't possible):"
    items: int[] = [1, 2, 3, 4, 5]
    objects := items.Cast<object>().ToList()
    print $"Cast {items.Length} items to {objects.Count} objects"

    mixed := new List<object>()
    mixed.Add(1)
    mixed.Add("hello")
    mixed.Add(2)
    mixed.Add("world")

    integers := mixed.OfType<int>().ToList()
    justStrings := mixed.OfType<string>().ToList()
    print $"Found {integers.Count} integers and {justStrings.Count} strings in mixed list"

    // Example 6: Nested generic types
    print ""
    print "6. Nested generic type arguments:"
    matrix := new List<List<int>>()
    matrix.Add(CreateList(1, 2, 3))
    matrix.Add(CreateList(4, 5, 6))
    matrix.Add(CreateList(7, 8, 9))
    print $"Created {matrix.Count}x{matrix[0].Count} matrix"

    // Example 7: Nullable types in type arguments
    print ""
    print "7. Nullable type arguments:"
    nullableNumbers := CreateList<int?>(1, null, 3, null, 5)
    nonNull := nullableNumbers.Where(n => n != null).ToList()
    print $"List has {nullableNumbers.Count} items, {nonNull.Count} are non-null"

    // Example 8: Array types in type arguments
    print ""
    print "8. Array type arguments:"
    arrayList := CreateList<int[]>([1, 2], [3, 4], [5, 6])
    print $"Created list of {arrayList.Count} arrays"

    // Example 9: Dictionary/Complex generic types
    print ""
    print "9. Dictionary type arguments:"
    dictList := new List<Dictionary<string, int>>()
    scores := new Dictionary<string, int>()
    scores["Alice"] = 95
    scores["Bob"] = 87
    dictList.Add(scores)
    print $"Created list with {dictList.Count} dictionaries"

    print ""
    print "=== All examples completed successfully! ==="
}
