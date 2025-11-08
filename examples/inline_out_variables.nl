// Inline Out Variable Declarations (C# 7+)
// Demonstrates declaring variables inline with out parameters

using System.Collections.Generic

// TryParse pattern - very common in .NET
func TryParseInt(input: string, out result: int): bool {
    // In real implementation, would parse the string
    // For demo, check if input is numeric-looking
    if input.Length > 0 && input.Length < 10 {
        result = input.Length * 10
        return true
    }
    result = 0
    return false
}

// TryGetValue pattern - dictionary lookups
func TryGetFromCache(key: string, out value: string): bool {
    // Simulate cache lookup
    if key == "user" {
        value = "John Doe"
        return true
    } else if key == "role" {
        value = "Admin"
        return true
    }
    value = ""
    return false
}

// Complex example with multiple out parameters
func TryParsePoint(input: string, out x: double, out y: double): bool {
    // Simulate parsing "x,y" format
    if input.Length > 3 {
        x = 10.5
        y = 20.3
        return true
    }
    x = 0.0
    y = 0.0
    return false
}

func Main() {
    print "=== Inline Out Variable Declarations ==="
    print ""

    // Example 1: out var (type inferred)
    print "1. Type inference with 'out var':"
    if TryParseInt("12345", out var number) {
        print $"  Successfully parsed: {number}"
    } else {
        print "  Failed to parse"
    }
    print ""

    // Example 2: out with explicit type
    print "2. Explicit type with 'out int':"
    if TryParseInt("abc", out int value) {
        print $"  Successfully parsed: {value}"
    } else {
        print "  Failed to parse (expected)"
    }
    print ""

    // Example 3: Using in conditions
    print "3. Inline out vars in if conditions:"
    if TryGetFromCache("user", out var username) {
        print $"  Found user: {username}"
    }
    print ""

    // Example 4: Multiple out parameters
    print "4. Multiple out parameters:"
    if TryParsePoint("10.5,20.3", out var px, out var py) {
        print $"  Point: ({px}, {py})"
    }
    print ""

    // Example 5: Explicit types for multiple parameters
    print "5. Explicit types for multiple out parameters:"
    if TryParsePoint("coordinates", out double coordX, out double coordY) {
        print $"  Coordinates: X={coordX}, Y={coordY}"
    }
    print ""

    // Example 6: Variable is available after if statement
    print "6. Variable scope - available after if:"
    if TryGetFromCache("role", out var userRole) {
        print $"  Role inside if: {userRole}"
    }
    // Variable is still in scope here
    print $"  Role outside if: {userRole}"
    print ""

    // Example 7: Combining with .NET BCL (when available)
    // This demonstrates the pattern for TryParse, TryGetValue, etc.
    print "7. Pattern compatibility with .NET BCL:"
    print "  This syntax is compatible with:"
    print "  - int.TryParse(\"123\", out var n)"
    print "  - dict.TryGetValue(\"key\", out var v)"
    print "  - DateTime.TryParse(\"2024-01-01\", out var dt)"
    print ""

    print "=== All Examples Complete ==="
}
