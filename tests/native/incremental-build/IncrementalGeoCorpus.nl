namespace NSharpLang.IncrementalBuild.Tests

import System.Collections.Generic

// `geo`: the corpus project written for the differential test, so that the cross-file relations the
// dependency summaries must not miss are all present in one small program — an interface implemented
// in one file and enumerated in another, a base class in another file, an attribute declared as
// `TagAttribute` and written `[Tag]`, a union matched elsewhere, overloads across a namespace, a
// generic type, and calls made only inside string interpolations. Relative path -> source.
func GeoCorpusFiles(): Dictionary<string, string> {
    files := new Dictionary<string, string>()
    files.Add(
        "Model/Shapes.nl",
        """
namespace Geo

interface Shape {
    func Area(): double
    func Name(): string
}

class Rect: Shape {
    Width: double
    Height: double

    constructor(width: double, height: double) {
        Width = width
        Height = height
    }

    func Area(): double {
        return Width * Height
    }

    func Name(): string {
        return "rect"
    }
}

class Circle: Shape {
    Radius: double

    constructor(radius: double) {
        Radius = radius
    }

    func Area(): double {
        return 3.0 * Radius * Radius
    }

    func Name(): string {
        return "circle"
    }
}
"""
    )
    files.Add(
        "Model/Square.nl",
        """
namespace Geo

class Square: Rect {
    constructor(side: double): base(side, side) {
    }

    func Side(): double {
        return Width
    }
}
"""
    )
    files.Add(
        "Model/Tags.nl",
        """
namespace Geo

import System

class TagAttribute: Attribute {
    Label: string

    constructor(label: string) {
        Label = label
    }
}

[Tag("box")]
class Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    func Get(): T {
        return Value
    }
}
"""
    )
    files.Add(
        "Model/Units.nl",
        """
namespace Geo

enum Unit {
    Meter = 0,
    Foot = 1
}

record Measure {
    Value: double
    Kind: Unit
}

union Outcome {
    Good { value: int }
    Bad { reason: string }
}

func Feet(value: double): Measure {
    return new Measure { Value: value, Kind: Unit.Foot }
}
"""
    )
    files.Add(
        "Program.nl",
        """
namespace Geo

import Geo.Util

func main() {
    square := new Square(2.0)
    box := new Box<int>(Scale(4, 5))
    print Describe(square)
    print Describe(new Circle(1.0))
    print DescribeUnit(Feet(3.0))
    print DescribeOutcome(Judge(box.Get()))
    print $"{square.Side()}"
}
"""
    )
    files.Add(
        "Util/Calc.nl",
        """
namespace Geo.Util

import System.Collections.Generic
import Geo

func Total(shapes: List<Shape>): double {
    total := 0.0
    for shape in shapes {
        total = total + shape.Area()
    }
    return total
}

func Scale(value: int, factor: int): int {
    return value * factor
}

func Scale(value: double, factor: int): double {
    return value * factor
}

func Judge(score: int): Outcome {
    if score > 10 {
        return new Outcome.Good { value: score }
    }
    return new Outcome.Bad { reason: "low" }
}
"""
    )
    files.Add(
        "Util/Report.nl",
        """
namespace Geo.Util

import System.Collections.Generic
import Geo

func Describe(shape: Shape): string {
    shapes := new List<Shape>()
    shapes.Add(shape)
    return $"{shape.Name()} {Total(shapes)} {Scale(2, 3)}"
}

func DescribeUnit(measure: Measure): string {
    return match measure.Kind {
        Unit.Meter => "m",
        Unit.Foot => "ft"
    }
}

func DescribeOutcome(outcome: Outcome): string {
    return match outcome {
        Outcome.Good { value } => $"good {value}",
        Outcome.Bad { reason } => $"bad {reason}"
    }
}
"""
    )
    return files
}
