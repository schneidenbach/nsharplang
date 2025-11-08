// Spread Operator in Function Calls Example
// Demonstrates using the spread operator (...) to pass array elements as individual arguments

// Function that accepts variable number of arguments using params
func Sum(params numbers: int[]): int {
    total := 0
    for num in numbers {
        total += num
    }
    return total
}

// Function that concatenates strings
func Concatenate(separator: string, params parts: string[]): string {
    result := ""
    for i := 0; i < parts.Length; i++ {
        if i > 0 {
            result += separator
        }
        result += parts[i]
    }
    return result
}

// Function with regular parameters and params
func Format(prefix: string, suffix: string, params values: int[]): string {
    middle := ""
    for i := 0; i < values.Length; i++ {
        if i > 0 {
            middle += ", "
        }
        middle += values[i].ToString()
    }
    return prefix + middle + suffix
}

func Main() {
    // Example 1: Basic spread with Sum
    let numbers: int[] = [1, 2, 3, 4, 5]
    total := Sum(...numbers)
    print $"Sum of array: {total}"  // Output: Sum of array: 15

    // Example 2: Spread with more numbers
    let moreNumbers: int[] = [10, 20, 30]
    total2 := Sum(...moreNumbers)
    print $"Sum with spread: {total2}"  // Output: Sum with spread: 60

    // Example 3: Spread with string concatenation
    let words: string[] = ["Hello", "World", "from", "N#"]
    sentence := Concatenate(" ", ...words)
    print sentence  // Output: Hello World from N#

    // Example 4: Spread with prefix/suffix function
    let values: int[] = [1, 2, 3]
    formatted := Format("[", "]", ...values)
    print formatted  // Output: [1, 2, 3]

    // Example 5: Multiple arrays (spread one at a time)
    let firstSet: int[] = [1, 2, 3]
    firstSum := Sum(...firstSet)

    let secondSet: int[] = [10, 20, 30, 40]
    secondSum := Sum(...secondSet)

    print $"First sum: {firstSum}, Second sum: {secondSum}"
    // Output: First sum: 6, Second sum: 100

    // Example 6: Direct array declaration for spreading
    let directArray: int[] = [100, 200, 300]
    directSum := Sum(...directArray)
    print $"Direct array sum: {directSum}"  // Output: Direct array sum: 600

    print "\nSpread operator in function calls works perfectly!"
}
