// Demonstrates records, with expressions, interfaces, and inheritance

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
class Circle: IShape {
    readonly Radius: double
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
    readonly Name: string
    readonly Side: double
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
        print $"Shape: {Name}"
        print $"Side: {Side}"
        print $"Created: {CreatedAt}"
    }
}

// Main program
class Program {
    static func Main() {
        print "=== Records and With Expressions ==="

        // Create record instances
        p1 := new Point { X: 10, Y: 20 }
        print $"Point 1: ({p1.X}, {p1.Y})"

        // Use with expression for non-destructive mutation
        p2 := p1 with { X: 30 }
        print $"Point 2: ({p2.X}, {p2.Y})"

        // Value equality
        p3 := new Point { X: 10, Y: 20 }
        print $"p1 == p3: {p1.Equals(p3)}"

        print ""
        print "=== Interfaces ==="

        // Interface implementation
        circle := new Circle(5.0)
        print $"Circle area: {circle.GetArea()}"

        // Default interface implementation (must call through interface in C#)
        shape := circle as IShape
        print shape.Describe()

        print ""
        print "=== Structs ==="

        // Struct value type
        rect := new Rectangle { Width: 10.0, Height: 5.0 }
        print $"Rectangle area: {rect.GetArea()}"

        print ""
        print "=== Classes with Readonly Fields ==="

        // Classes can have readonly fields set in constructor
        square := new Square(4.0, "Square")
        square.PrintInfo()
        print $"Perimeter: {square.CalculatePerimeter()}"

        // Readonly fields can be read but not modified outside constructor
        print $"Pi value (readonly): {circle.Pi}"
        print $"CreatedAt (readonly): {square.CreatedAt}"

        print ""
        print "=== Demo Complete ==="
    }
}
