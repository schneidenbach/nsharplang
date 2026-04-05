namespace NSharpInteropLib

// Static utility class for testing static method calls from C#
class MathUtils {
    static func Add(a: int, b: int): int {
        return a + b
    }

    static func Multiply(a: double, b: double): double {
        return a * b
    }

    static func IsEven(n: int): bool {
        return n % 2 == 0
    }

    static func Clamp(value: int, min: int, max: int): int {
        if value < min {
            return min
        }
        if value > max {
            return max
        }
        return value
    }

    static func Factorial(n: int): long {
        if n <= 1 {
            return 1
        }
        return n * Factorial(n - 1)
    }
}
