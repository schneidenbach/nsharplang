using System;

record Point
{
    public int X { get; set; }

    public int Y { get; set; }

}

interface IShape
{
    double GetArea()    ;

    string Describe()
    {
        return $"Area: {GetArea()}";
    }

}

class Circle : IShape
{
    public double Radius { get; set; }

    public double Pi { get; init; } = 3.14159;

    public Circle(double radius)
    {
        Radius = radius;
    }

    public double GetArea()
    {
        return ((Pi * Radius) * Radius);
    }

}

struct Rectangle
{
    public double Width { get; set; }

    public double Height { get; set; }

    public double GetArea()
    {
        return (Width * Height);
    }

}

class Square
{
    public string Name { get; set; }

    public double Side { get; set; }

    public string CreatedAt { get; init; }

    public Square(double side, string name)
    {
        Name = name;
        Side = side;
        CreatedAt = "2025-11-07";
    }

    public double CalculatePerimeter()
    {
        return (4 * Side);
    }

    public void PrintInfo()
    {
        Console.WriteLine($"Shape: {Name}");
        Console.WriteLine($"Side: {Side}");
        Console.WriteLine($"Created: {CreatedAt}");
    }

}

class Program
{
    public static void Main()
    {
        Console.WriteLine("=== Records and With Expressions ===");
        var p1 = new Point() { X = 10, Y = 20 };
        Console.WriteLine($"Point 1: ({p1.X}, {p1.Y})");
        var p2 = p1 with { X = 30 };
        Console.WriteLine($"Point 2: ({p2.X}, {p2.Y})");
        var p3 = new Point() { X = 10, Y = 20 };
        Console.WriteLine($"p1 == p3: {p1.Equals(p3)}");
        Console.WriteLine();
        Console.WriteLine("=== Interfaces ===");
        var circle = new Circle(5.0);
        Console.WriteLine($"Circle area: {circle.GetArea()}");
        Console.WriteLine(circle.Describe());
        Console.WriteLine();
        Console.WriteLine("=== Structs ===");
        var rect = new Rectangle() { Width = 10.0, Height = 5.0 };
        Console.WriteLine($"Rectangle area: {rect.GetArea()}");
        Console.WriteLine();
        Console.WriteLine("=== Classes with Readonly Fields ===");
        var square = new Square(4.0, "Square");
        square.PrintInfo();
        Console.WriteLine($"Perimeter: {square.CalculatePerimeter()}");
        Console.WriteLine($"Pi value (readonly): {circle.Pi}");
        Console.WriteLine($"CreatedAt (readonly): {square.CreatedAt}");
        Console.WriteLine();
        Console.WriteLine("=== Demo Complete ===");
    }

}

