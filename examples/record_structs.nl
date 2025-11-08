using System

// Record Structs (C# 10) - Value-Type Records
//
// Record structs combine the benefits of:
// - Value semantics (struct) for performance
// - Immutability and value equality (record)
// - Concise syntax
//
// Use record structs for small, immutable data types that are
// frequently copied or compared (e.g., points, coordinates, dimensions)

// Basic record struct with properties
record struct Point {
    X: double
    Y: double
}

// Record struct with primary constructor (C# 12)
// Parameters become public properties automatically
record struct Vector2D(x: double, y: double) {
    // Computed property using primary constructor parameters
    Length: double => Math.Sqrt(x * x + y * y)

    // Custom method
    func Normalize(): Vector2D {
        len := Length
        if len == 0 {
            return new Vector2D(0, 0)
        }
        return new Vector2D(x / len, y / len)
    }

    // Expression-bodied method
    func Dot(other: Vector2D): double => (x * other.x) + (y * other.y)
}

// Record struct for RGB color (0-255 range)
record struct Color(r: byte, g: byte, b: byte) {
    // Named color constants
    static Red: Color => new Color(255, 0, 0)
    static Green: Color => new Color(0, 255, 0)
    static Blue: Color => new Color(0, 0, 255)
    static White: Color => new Color(255, 255, 255)
    static Black: Color => new Color(0, 0, 0)

    // Convert to hex string
    func ToHex(): string => $"#{r:X2}{g:X2}{b:X2}"
}

// Record struct with methods
record struct Dimensions(width: double, height: double) {
    // Read-only computed property
    Area: double => width * height

    // Method for scaling
    func Scale(scale: double): Dimensions {
        return new Dimensions(width * scale, height * scale)
    }
}

// Record struct representing a time duration
record struct Duration(seconds: int) {
    // Factory methods for readability
    static func FromMinutes(minutes: int): Duration => new Duration(minutes * 60)
    static func FromHours(hours: int): Duration => new Duration(hours * 3600)

    // Computed properties
    Minutes: int => seconds / 60
    Hours: int => seconds / 3600

    // Format as string
    func Format(): string => $"{Hours}h {Minutes % 60}m {seconds % 60}s"
}

func Main() {
    Console.WriteLine("=== Record Structs (C# 10) ===")
    Console.WriteLine()

    // Basic record struct usage
    Console.WriteLine("1. Basic Record Struct:")
    p1 := new Point { X: 3.0, Y: 4.0 }
    p2 := new Point { X: 3.0, Y: 4.0 }
    Console.WriteLine($"Point 1: ({p1.X}, {p1.Y})")
    Console.WriteLine($"Point 2: ({p2.X}, {p2.Y})")
    Console.WriteLine($"p1 == p2: {p1 == p2}")  // Value equality!
    Console.WriteLine()

    // Primary constructor
    Console.WriteLine("2. Primary Constructor:")
    v1 := new Vector2D(3.0, 4.0)
    Console.WriteLine($"Vector: ({v1.x}, {v1.y})")
    Console.WriteLine($"Length: {v1.Length}")

    normalized := v1.Normalize()
    Console.WriteLine($"Normalized: ({normalized.x:F2}, {normalized.y:F2})")
    Console.WriteLine()

    // Dot product
    v2 := new Vector2D(1.0, 0.0)
    Console.WriteLine($"Dot product: {v1.Dot(v2)}")
    Console.WriteLine()

    // Color record struct
    Console.WriteLine("3. Color Record Struct:")
    red := Color.Red
    custom := new Color(128, 64, 255)
    Console.WriteLine($"Red: {red.ToHex()}")
    Console.WriteLine($"Custom: {custom.ToHex()}")
    Console.WriteLine()

    // Methods and computed properties
    Console.WriteLine("4. Methods and Computed Properties:")
    dim := new Dimensions(10.0, 5.0)
    Console.WriteLine($"Original: {dim.width} x {dim.height}, Area: {dim.Area}")

    scaled := dim.Scale(2.0)
    Console.WriteLine($"Scaled 2x: {scaled.width} x {scaled.height}, Area: {scaled.Area}")
    Console.WriteLine()

    // Duration with factory methods
    Console.WriteLine("5. Duration with Factory Methods:")
    d1 := Duration.FromMinutes(90)
    d2 := Duration.FromHours(2)
    Console.WriteLine($"90 minutes: {d1.Format()}")
    Console.WriteLine($"2 hours: {d2.Format()}")
    Console.WriteLine()

    // With expressions (non-destructive mutation)
    Console.WriteLine("6. With Expressions:")
    color1 := new Color(255, 0, 0)
    color2 := color1 with { g: 128 }  // Change only green component
    Console.WriteLine($"Original: {color1.ToHex()}")
    Console.WriteLine($"Modified: {color2.ToHex()}")
    Console.WriteLine()

    // Performance comparison notes
    Console.WriteLine("7. Record Struct Benefits:")
    Console.WriteLine("- Value semantics: Stored on stack (faster allocation)")
    Console.WriteLine("- No GC pressure: No heap allocations for small data")
    Console.WriteLine("- Value equality: Built-in comparison by value")
    Console.WriteLine("- Immutability: Thread-safe by default")
    Console.WriteLine("- Perfect for: Points, colors, coordinates, dimensions")
    Console.WriteLine()

    Console.WriteLine("Use 'record struct' for small immutable data!")
    Console.WriteLine("Use 'record' (class) for larger objects or when reference semantics needed.")
}
