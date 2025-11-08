namespace ErrorHandlingDemo

import System

// Example function that might throw
func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception("Cannot divide by zero")
    }
    return a / b
}

// Example function that always throws
func AlwaysFails(): string {
    throw new Exception("This always fails")
}

func Main() {
    Console.WriteLine("=== Error Handling Demo ===")

    // Example 1: Automatic exception capture with try-catch
    Console.WriteLine("\n1. Safe division (success case):")
    {
        result, err := Divide(10, 2)
        if err == null {
            Console.WriteLine($"Success: 10 / 2 = {result}")
        } else {
            Console.WriteLine($"Error: {err.Message}")
        }
    }

    // Example 2: Safe division (error case)
    Console.WriteLine("\n2. Safe division (error case):")
    {
        result, err := Divide(10, 0)
        if err == null {
            Console.WriteLine($"Success: 10 / 0 = {result}")
        } else {
            Console.WriteLine($"Error caught: {err.Message}")
        }
    }

    // Example 3: String result with error handling
    Console.WriteLine("\n3. Function that always fails:")
    {
        result, err := AlwaysFails()
        if err == null {
            Console.WriteLine($"Success: {result}")
        } else {
            Console.WriteLine($"Error caught: {err.Message}")
        }
    }

    Console.WriteLine("\n=== Demo Complete ===")
}
