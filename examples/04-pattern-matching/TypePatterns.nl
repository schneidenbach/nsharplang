// Type Pattern Matching Example
// Demonstrates C# 8+ type patterns in match expressions

import System
import System.Collections.Generic

// Example 1: Type pattern matching with strings
func ClassifyString(value: string): string {
    result := match value {
        string s when s.Length == 0 => "Empty string",
        string s when s.Length > 20 => "Long string",
        string s when s.Length > 10 => "Medium string",
        string s => $"Short string: {s}"
    }
    return result
}

// Example 2: Type patterns with integers
func ClassifyNumber(value: int): string {
    result := match value {
        int n when n > 100 => "Large number",
        int n when n < 0 => "Negative number",
        int n when n == 0 => "Zero",
        int n when n > 50 => "Medium number",
        int n => $"Small number: {n}"
    }
    return result
}

// Example 3: Combining type patterns with literal patterns
func CheckValue(value: string): string {
    result := match value {
        "special" => "Special string detected",
        string s when s.StartsWith("ERROR:") => "Error message",
        string s when s.StartsWith("WARN:") => "Warning message",
        string s when s.Length > 10 => "Long string",
        string s => $"Regular string: {s}"
    }
    return result
}

// Main function demonstrating all examples
func Main() {
    print "Type Pattern Matching Examples"
    print "==============================="
    print ""

    // Example 1: String classification
    print "Example 1: String type patterns with guards"
    print ClassifyString("")
    print ClassifyString("Short")
    print ClassifyString("This is a medium length string")
    print ClassifyString("This is a very very very long string that exceeds the limit")
    print ""

    // Example 2: Number classification
    print "Example 2: Integer type patterns with guards"
    print ClassifyNumber(0)
    print ClassifyNumber(-5)
    print ClassifyNumber(25)
    print ClassifyNumber(75)
    print ClassifyNumber(150)
    print ""

    // Example 3: Combining patterns
    print "Example 3: Combining type patterns with literal patterns"
    print CheckValue("special")
    print CheckValue("ERROR: Something went wrong")
    print CheckValue("WARN: This might be an issue")
    print CheckValue("This is a very long string for testing")
    print CheckValue("short")
}
