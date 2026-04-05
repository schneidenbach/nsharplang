using NSharpInteropLib.Geometry;
using Xunit;

namespace NSharpLang.CSharpInteropTests;

/// <summary>
/// Tests that C# code can consume N# classes and interfaces naturally.
/// </summary>
public class GeometryInteropTests
{
    [Fact]
    public void CanCreatePoint()
    {
        var p = new Point(3.0, 4.0);

        Assert.Equal(3.0, p.X);
        Assert.Equal(4.0, p.Y);
    }

    [Fact]
    public void PointDistanceCalculation()
    {
        var p1 = new Point(0.0, 0.0);
        var p2 = new Point(3.0, 4.0);

        Assert.Equal(5.0, p1.DistanceTo(p2), precision: 10);
    }

    [Fact]
    public void CanCreateCircle()
    {
        var circle = new Circle(5.0);

        Assert.Equal(5.0, circle.Radius);
        Assert.Equal(Math.PI * 25, circle.Area(), precision: 10);
        Assert.Equal(2 * Math.PI * 5, circle.Perimeter(), precision: 10);
    }

    [Fact]
    public void CanCreateRectangle()
    {
        var rect = new Rectangle(4.0, 6.0);

        Assert.Equal(4.0, rect.Width);
        Assert.Equal(6.0, rect.Height);
        Assert.Equal(24.0, rect.Area());
        Assert.Equal(20.0, rect.Perimeter());
    }

    [Fact]
    public void NSharpClassesImplementInterface()
    {
        // N# classes implementing IShape are usable through the interface
        IShape shape = new Circle(3.0);
        Assert.True(shape.Area() > 0);
        Assert.True(shape.Perimeter() > 0);

        shape = new Rectangle(2.0, 5.0);
        Assert.Equal(10.0, shape.Area());
        Assert.Equal(14.0, shape.Perimeter());
    }

    [Fact]
    public void CanImplementNSharpInterfaceFromCSharp()
    {
        // C# code can implement N#-defined interfaces
        IShape triangle = new CSharpTriangle(3.0, 4.0, 5.0);

        Assert.Equal(6.0, triangle.Area());
        Assert.Equal(12.0, triangle.Perimeter());
    }

    [Fact]
    public void PolymorphismWithNSharpInterface()
    {
        // Mix N# and C# implementations of the same N# interface
        var shapes = new IShape[]
        {
            new Circle(1.0),
            new Rectangle(2.0, 3.0),
            new CSharpTriangle(3.0, 4.0, 5.0)
        };

        double totalArea = 0;
        foreach (var shape in shapes)
        {
            totalArea += shape.Area();
        }

        Assert.True(totalArea > 0);
    }

    /// <summary>
    /// A C# implementation of N#'s IShape interface, proving cross-language interface interop.
    /// </summary>
    private class CSharpTriangle : IShape
    {
        private readonly double _a, _b, _c;

        public CSharpTriangle(double a, double b, double c)
        {
            _a = a;
            _b = b;
            _c = c;
        }

        public double Area()
        {
            // Heron's formula
            var s = (_a + _b + _c) / 2;
            return Math.Sqrt(s * (s - _a) * (s - _b) * (s - _c));
        }

        public double Perimeter() => _a + _b + _c;
    }
}
