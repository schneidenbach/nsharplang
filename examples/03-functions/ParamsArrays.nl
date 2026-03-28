// Example demonstrating params arrays feature

// Basic params array - accepts variable number of arguments
func Sum(params numbers: int[]): int {
    total := 0
    for num in numbers {
        total = total + num
    }

    return total
}

// Params with other parameters
func JoinWithSeparator(separator: string, params items: string[]): string {
    if items.Length == 0 {
        return ""
    }

    result := items[0]
    i: int = 1
    while i < items.Length {
        result = result + separator + items[i]
        i = i + 1
    }

    return result
}

// Generic params array
func PrintAll<T>(prefix: string, params items: T[]) {
    for item in items {
        print $"{prefix}{item}"
    }
}

class Calculator {

    // Static method with params
    static func Average(params values: double[]): double {
        if values.Length == 0 {
            return 0.0
        }

        sum := 0.0
        for val in values {
            sum = sum + val
        }

        return sum / values.Length
    }
}

func Main() {
    print "=== Params Arrays Examples ==="

    // Call with multiple arguments
    result1 := Sum(1, 2, 3, 4, 5)
    print $"Sum(1, 2, 3, 4, 5) = {result1}"

    // Call with no arguments
    result2 := Sum()
    print $"Sum() = {result2}"

    // Call with two arguments
    result3 := Sum(10, 20)
    print $"Sum(10, 20) = {result3}"

    // Join with separator
    joined := JoinWithSeparator(", ", "Alice", "Bob", "Charlie", "David")
    print $"Joined: {joined}"

    // Join with one item
    joined2 := JoinWithSeparator(", ", "Alice")
    print $"Single item: {joined2}"

    // Generic params
    print "Numbers:"
    PrintAll("  ", 1, 2, 3, 4, 5)

    print "Names:"
    PrintAll("  ", "Alice", "Bob", "Charlie")

    // Static method with params
    avg := Calculator.Average(1.5, 2.5, 3.5, 4.5)
    print $"Average = {avg}"

    avg2 := Calculator.Average(10.0, 20.0, 30.0)
    print $"Average2 = {avg2}"
}
