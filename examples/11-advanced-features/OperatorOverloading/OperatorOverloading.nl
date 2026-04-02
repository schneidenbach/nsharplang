// Operator Overloading Example
// This example demonstrates the syntax for operator overloading
// Note: Full runtime support requires analyzer enhancements (tracked separately)


// Simple vector class demonstrating operator overload syntax
class Vector2D {
    X: double
    Y: double

    // Binary addition operator
    static func operator +(a: Vector2D, b: Vector2D): Vector2D {
        return new Vector2D() { X: a.X + b.X, Y: a.Y + b.Y }
    }

    // Binary subtraction operator
    static func operator -(a: Vector2D, b: Vector2D): Vector2D {
        return new Vector2D() { X: a.X - b.X, Y: a.Y - b.Y }
    }

    // Scalar multiplication
    static func operator *(v: Vector2D, scalar: double): Vector2D {
        return new Vector2D() { X: v.X * scalar, Y: v.Y * scalar }
    }

    // Equality operators (must come in pairs)
    static func operator ==(a: Vector2D, b: Vector2D): bool {
        return a.X == b.X && a.Y == b.Y
    }

    static func operator !=(a: Vector2D, b: Vector2D): bool {
        return !(a == b)
    }

    func ToString(): string {
        return $"({X}, {Y})"
    }
}

// Complex numbers with expression-bodied operators
struct Complex {
    Real: double
    Imaginary: double

    // Expression-bodied operator overload
    static func operator +(a: Complex, b: Complex): Complex => new Complex() { Real: a.Real + b.Real, Imaginary: a.Imaginary + b.Imaginary }

    // Complex multiplication
    static func operator *(a: Complex, b: Complex): Complex => new Complex() { Real: a.Real * b.Real - a.Imaginary * b.Imaginary, Imaginary: a.Real * b.Imaginary + a.Imaginary * b.Real }
}

class Program {
    static func Main() {
        print "=== Operator Overloading Syntax Demo ==="
        print "This example demonstrates operator overload declarations."
        print "The generated C# code includes proper operator methods."
        print ""
        print "Check the transpiled C# output to see the generated operators!"
    }
}
