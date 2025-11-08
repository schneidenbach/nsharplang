// Ref and Out Parameters Example
// Demonstrates .NET interop with ref/out parameters

using System.Collections.Generic

// Custom swap function using ref parameters
func Swap(ref a: int, ref b: int) {
    temp := a
    a = b
    b = temp
}

// TryParse pattern - common .NET idiom
func TryParseInt(input: string, out result: int): bool {
    // In real implementation, would parse the string
    // For demo, just return a hardcoded value
    result = 42
    return input.Length > 0
}

// Dictionary TryGetValue pattern
func TryGetValue(dict: Dictionary<string, int>, key: string, out value: int): bool {
    // Simulated implementation
    if key == "test" {
        value = 123
        return true
    }
    value = 0
    return false
}

// Ref parameter for in-place modification
func MultiplyByTwo(ref value: int) {
    value = value * 2
}

// Function that uses both ref and out parameters
func ProcessNumbers(ref input: int, out doubled: int, out tripled: int) {
    doubled = input * 2
    tripled = input * 3
    input = input + 1  // Modify input
}

// Main demonstration
func Main() {
    print "=== Ref Parameters Example ==="
    print ""

    // Swap demonstration
    x := 10
    y := 20
    print $"Before swap: x = {x}, y = {y}"
    Swap(ref x, ref y)
    print $"After swap:  x = {x}, y = {y}"
    print ""

    // In-place modification
    num := 5
    print $"Before multiply: num = {num}"
    MultiplyByTwo(ref num)
    print $"After multiply:  num = {num}"
    print ""

    print "=== Out Parameters Example ==="
    print ""

    // TryParse pattern (custom)
    let result1: int
    success1 := TryParseInt("123", out result1)
    print $"Parse success: {success1}, result: {result1}"

    let result2: int
    success2 := TryParseInt("", out result2)
    print $"Parse empty string: {success2}, result: {result2}"
    print ""

    // Dictionary TryGetValue pattern (custom implementation)
    dict := new Dictionary<string, int>()

    let value1: int
    found1 := TryGetValue(dict, "test", out value1)
    if found1 {
        print $"Found 'test': {value1}"
    }

    let value2: int
    found2 := TryGetValue(dict, "missing", out value2)
    if found2 {
        print $"Found 'missing': {value2}"
    } else {
        print "Key 'missing' not found in dictionary"
    }
    print ""

    print "=== Combined ref and out Example ==="
    print ""

    // Example: A function demonstrates mixing ref and out parameters
    n := 10
    let d: int
    let t: int
    print $"Before: n = {n}"
    ProcessNumbers(ref n, out d, out t)
    print $"After: n = {n}, doubled = {d}, tripled = {t}"
}
