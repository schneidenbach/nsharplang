// Generated from Geometry.nl — this is the exact C# that N# emits.
// If the compiler output changes, update this file to match.
#nullable enable annotations

using System;

namespace NSharpInteropLib.Geometry;

public class Point
{
    public double X { get; set; }

    public double Y { get; set; }

    public Point(double x, double y)
    {
        X = x;
        Y = y;
    }

    public double DistanceTo(Point other)
    {
        var dx = (X - other.X);
        var dy = (Y - other.Y);
        return Math.Sqrt(((dx * dx) + (dy * dy)));
    }
}

public interface IShape
{
    double Area();

    double Perimeter();
}

public class Circle : IShape
{
    public double Radius { get; set; }

    public Circle(double radius)
    {
        Radius = radius;
    }

    public double Area()
    {
        return ((Math.PI * Radius) * Radius);
    }

    public double Perimeter()
    {
        return ((2.0 * Math.PI) * Radius);
    }
}

public class Rectangle : IShape
{
    public double Width { get; set; }

    public double Height { get; set; }

    public Rectangle(double width, double height)
    {
        Width = width;
        Height = height;
    }

    public double Area()
    {
        return (Width * Height);
    }

    public double Perimeter()
    {
        return (2.0 * ((Width + Height)));
    }
}
