// Range and Index from End Operators Demo
// Demonstrates C# 8+ range (..) and index from end (^) operators
func Main() {
    print "=== Range and Index from End Operators ==="
    print ""

    // Create a sample array
    numbers := [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    print "Original array: [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]"
    print ""

    // Index from end operator (^)
    print "--- Index from End (^) ---"
    lastItem := numbers[^1]
    print $"Last item (^1): {lastItem}"

    secondLast := numbers[^2]
    print $"Second to last (^2): {secondLast}"

    thirdLast := numbers[^3]
    print $"Third from end (^3): {thirdLast}"
    print ""

    // Range operator (..)
    print "--- Range Operator (..) ---"

    // Full range with both bounds
    slice1 := numbers[2..5]
    print $"Slice [2..5]: {slice1.Length} items"

    slice2 := numbers[0..3]
    print $"Slice [0..3]: {slice2.Length} items"

    slice3 := numbers[5..8]
    print $"Slice [5..8]: {slice3.Length} items"
    print ""

    // Range with index from end
    print "--- Combining Range and Index from End ---"

    middle := numbers[2..^2]
    print $"Middle [2..^2]: {middle.Length} items"

    lastThree := numbers[^3..^0]
    print $"Last three [^3..^0]: {lastThree.Length} items"

    firstToSecondLast := numbers[0..^2]
    print $"First to second-to-last [0..^2]: {firstToSecondLast.Length} items"
    print ""

    // Practical examples
    print "--- Practical Examples ---"

    // Get first and last elements
    first := numbers[0]
    last := numbers[^1]
    print $"First: {first}, Last: {last}"

    // Get first few and last few
    firstThree := numbers[0..3]
    lastFour := numbers[^4..^0]
    print $"First three: {firstThree.Length} items, last four: {lastFour.Length} items"

    // Split array in half (approximately)
    midpoint := 5
    firstHalf := numbers[0..midpoint]
    secondHalf := numbers[midpoint..^0]
    print $"Split at position {midpoint} into halves of {firstHalf.Length} and {secondHalf.Length}"

    print ""
    print "=== All operations completed successfully! ==="
}
