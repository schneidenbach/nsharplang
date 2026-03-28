// Simple Generic Method Calls Example
// Demonstrates explicit type argument syntax
import System.Collections.Generic
import System.Linq

func Main() {
    print "Generic Method Calls Demo"
    print "========================="
    print ""

    // Example 1: Basic LINQ generic methods
    numbers: int[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    // Cast - explicit type conversion
    objects := numbers.Cast<object>().ToList()
    print $"Cast {numbers.Length} integers to {objects.Count} objects"

    // Example 2: OfType with filtering
    mixed := new List<object>()
    mixed.Add(42)
    mixed.Add("hello")
    mixed.Add(100)
    mixed.Add("world")

    justNumbers := mixed.OfType<int>().ToList()
    justStrings := mixed.OfType<string>().ToList()

    print $"Mixed list: {mixed.Count} items"
    print $"  - {justNumbers.Count} numbers"
    print $"  - {justStrings.Count} strings"

    // Example 3: Nested generic type
    lists := new List<List<int>>()
    list1: List<int> = [1, 2, 3]
    list2: List<int> = [4, 5, 6]
    lists.Add(list1)
    lists.Add(list2)

    print $"Created {lists.Count} lists of integers"

    print ""
    print "All generic method calls worked!"
}
