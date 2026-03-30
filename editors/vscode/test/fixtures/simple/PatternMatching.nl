namespace SimpleTest

// If/else chains (control flow that always works)
func Classify(value: int): string {
    if value > 100 {
        return "large"
    } else if value > 50 {
        return "medium"
    } else if value > 0 {
        return "small positive"
    } else if value == 0 {
        return "zero"
    } else {
        return "negative"
    }
}

// For loops with various patterns
func TestForLoops() {
    numbers := [1, 2, 3, 4, 5]
    for num in numbers {
        print $"Number: {num}"
    }

    names := ["Alice", "Bob", "Charlie"]
    for name in names {
        print $"Hello, {name}!"
    }
}

// Nested control flow
func TestNestedControlFlow() {
    for i in [1, 2, 3] {
        for j in [10, 20, 30] {
            if i * j > 30 {
                print $"{i} * {j} = {i * j} (large)"
            } else {
                print $"{i} * {j} = {i * j}"
            }
        }
    }
}

// Control flow with early returns
func FindFirst(items: string[], target: string): int {
    index := 0
    for item in items {
        if item == target {
            return index
        }
        index = index + 1
    }
    return -1
}

func TestControlFlow() {
    for value in [-5, 0, 25, 75, 150] {
        cls := Classify(value)
        print $"{value}: {cls}"
    }
}
