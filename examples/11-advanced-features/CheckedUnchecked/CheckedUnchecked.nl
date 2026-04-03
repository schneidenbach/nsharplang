// Checked and Unchecked Expressions Example
// Demonstrates overflow checking control in arithmetic operations
//
// NOTE: This example demonstrates the syntax and transpilation.
// To see overflow exceptions at runtime, compile and run the generated C# code.

// Helper function with checked arithmetic
func SafeAdd(x: int, y: int): int {
    return checked(x + y)
}

func Main() {
    print "=== Checked and Unchecked Expressions ==="
    print ""

    // Example 1: Default behavior (unchecked in .NET)
    print "1. Default Behavior (unchecked):"
    max := 2147483647  // int.MaxValue
    print $"int.MaxValue = {max}"

    // This wraps around in default unchecked context
    defaultOverflow := max + 1
    print $"MaxValue + 1 (default) = {defaultOverflow}"  // Wraps to MinValue (-2147483648)
    print ""

    // Example 2: Explicit unchecked - wraps around
    print "2. Unchecked Context (wraps on overflow):"
    wrapped := unchecked(max + 1)
    print $"unchecked(MaxValue + 1) = {wrapped}"  // -2147483648
    print ""

    // Example 3: Unchecked subtraction
    print "3. Unchecked Subtraction (wraps):"
    min := -2147483648  // int.MinValue
    wrappedSub := unchecked(min - 1)
    print $"unchecked(MinValue - 1) = {wrappedSub}"  // Wraps to MaxValue (2147483647)
    print ""

    // Example 4: Unchecked multiplication
    print "4. Unchecked Multiplication (wraps):"
    a := 1000000
    b := 1000000
    uncheckedResult := unchecked(a * b)
    print $"unchecked({a} * {b}) = {uncheckedResult}"
    print ""

    // Example 5: Checked context (would throw at runtime)
    print "5. Checked Context (would throw OverflowException at runtime):"
    print "Syntax: checked(int.MaxValue + 1)"
    print "This compiles but throws OverflowException when executed"
    // checkedResult := checked(max + 1)  // Uncomment to see exception at runtime
    print ""

    // Example 6: Safe operations in checked context
    print "6. Safe Operations in Checked Context:"
    safe1 := checked(100 + 200)
    safe2 := checked(500 - 250)
    safe3 := checked(10 * 20)
    print $"checked(100 + 200) = {safe1}"
    print $"checked(500 - 250) = {safe2}"
    print $"checked(10 * 20) = {safe3}"
    print ""

    // Example 7: Complex expressions
    print "7. Complex Expressions:"
    complex1 := checked((100 + 50) * 2 - 25)
    print $"checked((100 + 50) * 2 - 25) = {complex1}"

    complex2 := unchecked((max + 1) / 2)
    print $"unchecked((MaxValue + 1) / 2) = {complex2}"
    print ""

    // Example 8: Checked in function
    print "8. Checked Expression in Function:"
    safeAdd := SafeAdd(100, 200)
    print $"SafeAdd(100, 200) = {safeAdd}"
    print ""

    print "=== Summary ==="
    print "- checked(): Throws OverflowException on arithmetic overflow (at runtime)"
    print "- unchecked(): Wraps around on arithmetic overflow (default .NET behavior)"
    print "- Use checked() for critical calculations where overflow must be detected"
    print "- Use unchecked() when wrap-around behavior is desired"
    print "- To test overflow exceptions, compile this example and run the C# directly"
}
