namespace TestExample

class Calculator {
    static func Add(a: int, b: int): int {
        return a + b
    }

    static func Subtract(a: int, b: int): int {
        return a - b
    }

    static func Multiply(a: int, b: int): int {
        return a * b
    }

    static func Divide(a: int, b: int): int {
        if b == 0 {
            throw new System.DivideByZeroException("Cannot divide by zero")
        }
        return a / b
    }
}
