import System.Collections.Generic

func Main() {
    // Test if collection expressions work with explicit types
    numbers: List<int> = [1, 2, 3]
    names: HashSet<string> = ["Alice", "Bob"]

    print $"Created {numbers.Count} numbers and {names.Count} names"
    print "Test completed"
}
