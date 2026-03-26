// N# Extension Methods Example
// Demonstrates extension method resolution with LINQ-style operations

import System

// ========================================
// String Extensions
// ========================================

func IsEmpty(this s: string): bool {
    return s.Length == 0
}

func Truncate(this s: string, maxLength: int): string {
    if s.Length <= maxLength {
        return s
    }
    return s.Substring(0, maxLength) + "..."
}

func Repeat(this s: string, count: int): string {
    result := ""
    for i := 0; i < count; i++ {
        result += s
    }
    return result
}

// ========================================
// Integer Extensions
// ========================================

func IsEven(this n: int): bool {
    return n % 2 == 0
}

func IsPositive(this n: int): bool {
    return n > 0
}

func Times(this n: int, action: Func<int, void>) {
    for i := 0; i < n; i++ {
        action(i)
    }
}

// ========================================
// Array Extensions (LINQ-style)
// ========================================

func First(this arr: int[]): int {
    if arr.Length == 0 {
        throw new Exception("Array is empty")
    }
    return arr[0]
}

func Last(this arr: int[]): int {
    if arr.Length == 0 {
        throw new Exception("Array is empty")
    }
    return arr[arr.Length - 1]
}

func Sum(this arr: int[]): int {
    total := 0
    for num in arr {
        total += num
    }
    return total
}

func Average(this arr: int[]): double {
    if arr.Length == 0 {
        return 0.0
    }
    return (double)Sum(arr) / (double)arr.Length
}

// ========================================
// Custom Type Extensions
// ========================================

class Person {
    Name: string
    Age: int
}

func Greet(this p: Person): string {
    return $"Hello, I'm {p.Name}!"
}

func IsAdult(this p: Person): bool {
    return p.Age >= 18
}

func CelebrateBirthday(this p: Person) {
    p.Age = p.Age + 1
    print $"{p.Name} is now {p.Age} years old!"
}

// ========================================
// Static Class Extensions (Exposed to C#)
// ========================================

static class StringExtensions {
    static func Capitalize(this s: string): string {
        if s.Length == 0 {
            return s
        }
        return s.Substring(0, 1).ToUpper() + s.Substring(1)
    }

    static func WordCount(this s: string): int {
        if s.IsEmpty() {
            return 0
        }
        words := s.Split(" ")
        return words.Length
    }
}

// ========================================
// Main Program
// ========================================

func Main() {
    print "=== String Extensions ==="

    let greeting: string = "hello"
    print $"'{greeting}' is empty: {greeting.IsEmpty()}"
    print $"Capitalized: {greeting.Capitalize()}"
    print $"Repeated 3 times: {greeting.Repeat(3)}"

    let longText: string = "This is a very long string that needs truncation"
    print $"Truncated: {longText.Truncate(20)}"
    print $"Word count: {longText.WordCount()}"

    print ""
    print "=== Integer Extensions ==="

    let num: int = 42
    print $"{num} is even: {num.IsEven()}"
    print $"{num} is positive: {num.IsPositive()}"

    print "Counting to 5:"
    let count: int = 5
    count.Times(i => print $"  {i}")

    print ""
    print "=== Array Extensions (LINQ-style) ==="

    let numbers: int[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    print $"Numbers: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]"
    print $"First: {numbers.First()}"
    print $"Last: {numbers.Last()}"
    print $"Sum: {numbers.Sum()}"
    print $"Average: {numbers.Average():F2}"

    print ""
    print "=== Custom Type Extensions ==="

    let alice: Person = new Person { Name: "Alice", Age: 17 }
    let bob: Person = new Person { Name: "Bob", Age: 25 }

    print alice.Greet()
    print $"Alice is adult: {alice.IsAdult()}"

    print bob.Greet()
    print $"Bob is adult: {bob.IsAdult()}"

    print ""
    print "Birthday celebration:"
    alice.CelebrateBirthday()
    print $"Alice is now adult: {alice.IsAdult()}"

    print ""
    print "=== Extension Methods Work! ==="
    print "Extension methods enable LINQ-style fluent APIs"
    print "while maintaining perfect C# interoperability!"
}
