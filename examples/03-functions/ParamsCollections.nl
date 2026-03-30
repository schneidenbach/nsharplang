// Example demonstrating params with arrays
// N# supports params with array types (int[], string[], etc.)
import System
import System.Collections.Generic


// 1. Basic params with array (standard behavior)
func SumArray(params numbers: int[]): int {
    total := 0
    for num in numbers {
        total = total + num
    }

    return total
}

// 2. Params with iteration using index
func SumWithIndex(params numbers: int[]): int {
    total := 0
    for i := 0; i < numbers.Length; i++ {
        total = total + numbers[i]
    }

    return total
}

// 3. Params with strings - print all items
func PrintAll(params items: string[]) {
    for item in items {
        print $"  - {item}"
    }
}

// 4. Build a list from params
func BuildList(params items: int[]): List<int> {
    result := new List<int>()
    for item in items {
        result.Add(item)
    }

    return result
}

// 5. Params with separator joining
func FormatItems(separator: string, params items: string[]): string {
    if items.Length == 0 {
        return ""
    }

    result := items[0]
    for i := 1; i < items.Length; i++ {
        result = result + separator + items[i]
    }

    return result
}

// 6. Params with transformation
func DoubleAll(params numbers: int[]): int[] {
    result := new List<int>()
    for num in numbers {
        result.Add(num * 2)
    }

    return result.ToArray()
}

func Main() {
    print "=== Params Array Examples ==="
    print ""

    // Array params (standard behavior)
    print "1. Array params:"
    sum1 := SumArray(1, 2, 3, 4, 5)
    print $"   Sum(1,2,3,4,5) = {sum1}"
    print ""

    // Index-based iteration
    print "2. Index-based sum:"
    sum2 := SumWithIndex(10, 20, 30, 40)
    print $"   Sum(10,20,30,40) = {sum2}"
    print ""

    // String params
    print "3. String params:"
    print "   Items:"
    PrintAll("Apple", "Banana", "Cherry", "Date")
    print ""

    // Formatted with separator
    print "4. Params with separator:"
    formatted := FormatItems(", ", "Alice", "Bob", "Charlie", "David")
    print $"   Result: {formatted}"
    print ""

    // Build list from params
    print "5. Build list from params:"
    list := BuildList(100, 200, 300)
    print $"   Built list with {list.Count} items"
    print ""

    // Double all values
    print "6. Transform params:"
    doubled := DoubleAll(1, 2, 3, 4, 5)
    doubledStr := String.Join(", ", doubled)
    print $"   Doubled: [{doubledStr}]"
    print ""

    print "=== Params arrays provide convenient variadic function syntax! ==="
}
