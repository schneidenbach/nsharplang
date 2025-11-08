// Simple Generic Method Calls Example
// Demonstrates explicit type argument syntax

import System.Linq
import System.Collections.Generic

func Main() {
    print "Generic Method Calls Demo"
    print "========================="
    print ""

    // Example 1: Basic LINQ generic methods
    let numbers: int[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

    // Cast - explicit type conversion
    let objects = numbers.Cast<object>().ToList()
    print $"Cast {numbers.Length} integers to {objects.Count} objects"

    // Example 2: OfType with filtering
    let mixed = new List<object>()
    mixed.Add(42)
    mixed.Add("hello")
    mixed.Add(100)
    mixed.Add("world")

    let justNumbers = mixed.OfType<int>().ToList()
    let justStrings = mixed.OfType<string>().ToList()

    print $"Mixed list: {mixed.Count} items"
    print $"  - {justNumbers.Count} numbers"
    print $"  - {justStrings.Count} strings"

    // Example 3: Nested generic type
    let lists = new List<List<int>>()
    let list1: List<int> = [1, 2, 3]
    let list2: List<int> = [4, 5, 6]
    lists.Add(list1)
    lists.Add(list2)

    print $"Created {lists.Count} lists of integers"

    print ""
    print "All generic method calls worked!"
}
