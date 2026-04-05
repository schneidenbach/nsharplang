namespace NSharpInteropLib.Geometry
import System

// Class-based point for reliable interop (struct primary constructors
// have limitations with member access on other instances)
class Point {
    X: double
    Y: double

    constructor(x: double, y: double) {
        X = x
        Y = y
    }

    func DistanceTo(other: Point): double {
        dx := X - other.X
        dy := Y - other.Y
        return Math.Sqrt(dx * dx + dy * dy)
    }
}

// Interface for C# to implement
interface IShape {
    func Area(): double
    func Perimeter(): double
}

// Class implementing an interface
class Circle : IShape {
    Radius: double

    constructor(radius: double) {
        Radius = radius
    }

    func Area(): double {
        return Math.PI * Radius * Radius
    }

    func Perimeter(): double {
        return 2.0 * Math.PI * Radius
    }
}

// Class with inheritance potential
class Rectangle : IShape {
    Width: double
    Height: double

    constructor(width: double, height: double) {
        Width = width
        Height = height
    }

    func Area(): double {
        return Width * Height
    }

    func Perimeter(): double {
        return 2.0 * (Width + Height)
    }
}
