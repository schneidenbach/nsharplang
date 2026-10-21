namespace NSharpLang.CensusEmitShapes.Tests

import System.Text.Json

struct ShapePoint {
    X: int
    Y: int
}

struct ShapeSegment {
    From: ShapePoint
    To: ShapePoint
}

func SumOf(p: ShapePoint): int {
    return p.X + p.Y
}

// An object initializer of a STRUCT is evaluated into a temporary and passed, returned, or nested.
func ExternalStructInitializerArgument(): int {
    doc := JsonDocument.Parse("{}", new JsonDocumentOptions { AllowTrailingCommas: true })
    return doc.RootElement.ValueKind.ToString().Length
}

func ExternalStructInitializerTrailingCommaArgument(): int {
    doc := JsonDocument.Parse("[1,2,]", new JsonDocumentOptions { AllowTrailingCommas: true })
    return doc.RootElement.GetArrayLength()
}

func SourceStructInitializerArgument(): int {
    return SumOf(new ShapePoint { X: 3, Y: 4 })
}

func SourceStructInitializerReturn(): ShapePoint {
    return new ShapePoint { X: 5, Y: 6 }
}

func NestedStructInitializer(): ShapeSegment {
    return new ShapeSegment { From: new ShapePoint { X: 1, Y: 2 }, To: new ShapePoint { X: 3, Y: 4 } }
}

// The same shape with a value read BEFORE the argument, so the initializer is not the first thing on
// the stack.
func StructInitializerAfterOtherArguments(): int {
    return string.Join(",", [1, 2]).Length + SumOf(new ShapePoint { X: 1, Y: 1 })
}
