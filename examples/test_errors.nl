using System

// Test file to demonstrate improved error messages

func testTypeMismatch(): int {
    return "string"  // Error: Type mismatch - should be int
}

func testMissingReturn(): int {
    Console.WriteLine("Hello")
    // Error: Missing return statement
}

func testIfCondition() {
    x := 10
    if x {  // Error: If condition must be boolean
        Console.WriteLine("Not boolean!")
    }
}

func main() {
    testTypeMismatch()
    testMissingReturn()
    testIfCondition()
    Console.WriteLine("Done!")
}
