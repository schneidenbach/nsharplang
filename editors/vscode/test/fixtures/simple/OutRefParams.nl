namespace SimpleTest

// Functions demonstrating various parameter patterns
func DoubleValue(x: int): int {
    return x * 2
}

func TripleValue(x: int): int {
    return x * 3
}

func ComputeSum(a: int, b: int, c: int): int {
    return a + b + c
}

// Functions returning multiple values via a result class
class ComputeResult {
    Doubled: int
    Tripled: int

    constructor(doubled: int, tripled: int) {
        Doubled = doubled
        Tripled = tripled
    }
}

func ComputeMultiples(value: int): ComputeResult {
    return new ComputeResult(value * 2, value * 3)
}

// Usage
func TestParameterPatterns() {
    result := DoubleValue(21)
    print $"21 doubled = {result}"

    tripled := TripleValue(14)
    print $"14 tripled = {tripled}"

    sum := ComputeSum(1, 2, 3)
    print $"1 + 2 + 3 = {sum}"

    multiples := ComputeMultiples(5)
    print $"5 doubled = {multiples.Doubled}, tripled = {multiples.Tripled}"
}
