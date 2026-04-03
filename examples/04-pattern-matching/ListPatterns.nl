// List Pattern Matching Example
// Demonstrates C# 11 list patterns for array and collection matching



// Example 1: Empty list check
func IsEmpty(numbers: int[]): bool {
    result := match numbers {
        [] => true,
        _ => false
    }

    return result
}

// Example 2: Single element
func ProcessSingle(items: string[]): string {
    result := match items {
        [] => "No items",
        [single] => $"One item: {single}",
        _ => "Multiple items"
    }

    return result
}

// Example 3: First and rest
func GetFirst(numbers: int[]): string {
    result := match numbers {
        [] => "Empty array",
        [first, ..] => $"First: {first}",
        _ => "Unreachable"
    }

    return result
}

// Example 4: Last element
func GetLast(numbers: int[]): string {
    result := match numbers {
        [] => "Empty array",
        [.., last] => $"Last: {last}",
        _ => "Unreachable"
    }

    return result
}

// Example 5: First and last
func GetFirstAndLast(numbers: int[]): string {
    result := match numbers {
        [] => "Empty array",
        [single] => $"Only one: {single}",
        [first, .., last] => $"First: {first}, Last: {last}",
        _ => "Unreachable"
    }

    return result
}

// Example 6: Named slice capture
func CaptureMiddle(numbers: int[]): string {
    result := match numbers {
        [] => "Empty",
        [first, .. middle, last] => $"First: {first}, Middle has {middle.Length} items, Last: {last}",
        [single] => $"Only: {single}",
        _ => "Unreachable"
    }

    return result
}

// Example 7: Exact match
func IsSpecificSequence(numbers: int[]): bool {
    result := match numbers {
        [1, 2, 3] => true,
        [4, 5, 6] => true,
        _ => false
    }

    return result
}

// Example 8: Pattern with literals and bindings
func DescribeList(numbers: int[]): string {
    result := match numbers {
        [] => "Empty list",
        [0] => "Single zero",
        [0, ..] => "Starts with zero",
        [.., 0] => "Ends with zero",
        [first, second, ..] when first == second => "Starts with duplicates",
        [x, y] => $"Pair: {x} and {y}",
        [x, y, z] => $"Triple: {x}, {y}, {z}",
        _ => "Longer list"
    }

    return result
}

// Example 9: Real-world use case - processing structured data
func ProcessData(items: int[]): string {
    result := match items {
        [] => "No data",
        [single] => $"Single value: {single}",
        [a, b] when a > b => "First is larger",
        [a, b] when a < b => "Second is larger",
        [a, b] => "Equal values",
        [first, .. rest] when first == 0 => $"Starts with zero, has {rest.Length} more items",
        [first, second, .. rest] => $"Pair: ({first}, {second}), plus {rest.Length} more",
        _ => "Unreachable"
    }

    return result
}

// Example 10: Stack-like operations
func AnalyzeStack(stack: int[]): string {
    result := match stack {
        [] => "Stack is empty",
        [top] => $"Single element on stack: {top}",
        [top, ..] when top > 100 => "Top element is large",
        [top, second, ..] when top == second => "Top two elements are equal",
        [top, .. rest] => $"Stack top: {top}, depth: {rest.Length + 1}",
        _ => "Unreachable"
    }

    return result
}

// Main function demonstrating all examples
func Main() {
    print "List Pattern Matching Examples"
    print "==============================="
    print ""

    // Example 1: Empty check
    print "Example 1: Empty list check"
    print IsEmpty([1, 2, 3])
    print IsEmpty([5])
    print ""

    // Example 2: Single element
    print "Example 2: Single element check"
    print ProcessSingle(["one"])
    print ProcessSingle(["one", "two"])
    print ProcessSingle(["a", "b", "c"])
    print ""

    // Example 3: First element
    print "Example 3: Get first element"
    print GetFirst([10])
    print GetFirst([10, 20, 30])
    print GetFirst([100, 200])
    print ""

    // Example 4: Last element
    print "Example 4: Get last element"
    print GetLast([10])
    print GetLast([10, 20, 30])
    print GetLast([1, 2, 3, 4, 5])
    print ""

    // Example 5: First and last
    print "Example 5: Get first and last"
    print GetFirstAndLast([10])
    print GetFirstAndLast([10, 20])
    print GetFirstAndLast([10, 20, 30, 40])
    print GetFirstAndLast([1, 2, 3, 4, 5, 6, 7])
    print ""

    // Example 6: Named slice
    print "Example 6: Capture middle elements"
    print CaptureMiddle([1, 2, 3, 4, 5])
    print CaptureMiddle([1, 2])
    print CaptureMiddle([1])
    print ""

    // Example 7: Exact match
    print "Example 7: Exact sequence matching"
    print IsSpecificSequence([1, 2, 3])
    print IsSpecificSequence([4, 5, 6])
    print IsSpecificSequence([1, 2, 4])
    print ""

    // Example 8: Complex patterns
    print "Example 8: Complex list patterns"
    print DescribeList([0])
    print DescribeList([0, 1, 2])
    print DescribeList([1, 2, 0])
    print DescribeList([5, 5, 3])
    print DescribeList([10, 20])
    print DescribeList([1, 2, 3, 4, 5, 6])
    print ""

    // Example 9: Processing structured data
    print "Example 9: Processing structured data"
    print ProcessData([42])
    print ProcessData([10, 5])
    print ProcessData([3, 7])
    print ProcessData([5, 5])
    print ProcessData([0, 1, 2, 3])
    print ProcessData([10, 20, 30, 40, 50])
    print ""

    // Example 10: Stack analysis
    print "Example 10: Stack analysis"
    print AnalyzeStack([42])
    print AnalyzeStack([150, 20, 10])
    print AnalyzeStack([5, 5, 3, 2])
    print AnalyzeStack([10, 20, 30, 40, 50])
}
