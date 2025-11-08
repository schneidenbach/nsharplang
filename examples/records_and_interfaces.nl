// Demonstrates records, with expressions, interfaces, and inheritance

using System

// Record type with value equality
record Point {
    X: int
    Y: int
}

// Interface with default implementation
interface IShape {
    func GetArea(): double

    func Describe(): string {
        return $"Area: {GetArea()}"
    }
}

// Class implementing interface
class Circle : IShape {
    Radius: double
    readonly Pi: double = 3.14159

    constructor(radius: double) {
        Radius = radius
    }

    func GetArea(): double {
        return Pi * Radius * Radius
    }
}

// Struct for value types
struct Rectangle {
    Width: double
    Height: double

    func GetArea(): double {
        return Width * Height
    }
}

// Standalone class with readonly field
class Square {
    Name: string
    Side: double
    readonly CreatedAt: string

    constructor(side: double, name: string) {
        Name = name
        Side = side
        CreatedAt = "2025-11-07"
    }

    func CalculatePerimeter(): double {
        return 4 * Side
    }

    func PrintInfo() {
        Console.WriteLine($"Shape: {Name}")
        Console.WriteLine($"Side: {Side}")
        Console.WriteLine($"Created: {CreatedAt}")
    }
}

// Main program
class Program {
    static func Main() {
        Console.WriteLine("=== Records and With Expressions ===")

        // Create record instances
        p1 := new Point { X: 10, Y: 20 }
        Console.WriteLine($"Point 1: ({p1.X}, {p1.Y})")

        // Use with expression for non-destructive mutation
        p2 := p1 with { X: 30 }
        Console.WriteLine($"Point 2: ({p2.X}, {p2.Y})")

        // Value equality
        p3 := new Point { X: 10, Y: 20 }
        Console.WriteLine($"p1 == p3: {p1.Equals(p3)}")

        Console.WriteLine()
        Console.WriteLine("=== Interfaces ===")

        // Interface implementation
        circle := new Circle(5.0)
        Console.WriteLine($"Circle area: {circle.GetArea()}")

        // Default interface implementation (must call through interface in C#)
        shape := circle as IShape
        Console.WriteLine(shape.Describe())

        Console.WriteLine()
        Console.WriteLine("=== Structs ===")

        // Struct value type
        rect := new Rectangle { Width: 10.0, Height: 5.0 }
        Console.WriteLine($"Rectangle area: {rect.GetArea()}")

        Console.WriteLine()
        Console.WriteLine("=== Classes with Readonly Fields ===")

        // Classes can have readonly fields set in constructor
        square := new Square(4.0, "Square")
        square.PrintInfo()
        Console.WriteLine($"Perimeter: {square.CalculatePerimeter()}")

        // Readonly fields can be read but not modified outside constructor
        Console.WriteLine($"Pi value (readonly): {circle.Pi}")
        Console.WriteLine($"CreatedAt (readonly): {square.CreatedAt}")

        Console.WriteLine()
        Console.WriteLine("=== Demo Complete ===")
    }
}
