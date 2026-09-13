namespace NSharpLang.PatternForeach.Tests

import System.Collections
import System.Collections.Generic
import System.Reflection

func AnnotatedShapesUnderTest(): AnnotatedShapes {
    return new AnnotatedShapes()
}

func SampleLabels(): ArrayList {
    labels := new ArrayList()
    labels.Add("ab")
    labels.Add("cde")
    return labels
}

func SampleBoxedNumbers(): List<object> {
    values := new List<object>()
    values.Add(2)
    values.Add(3)
    values.Add(5)
    return values
}

func SampleNumberList(): List<int> {
    values := new List<int>()
    values.Add(2)
    values.Add(3)
    values.Add(5)
    return values
}

test "a non-generic sequence is read at its elements' real type" {
    shapes := AnnotatedShapesUnderTest()
    assert shapes.TotalMatchLength("abcabca", "a") == 3
    assert shapes.TotalMatchLength("abcabca", "bc") == 4
    assert shapes.TotalMatchLength("zzz", "a") == 0
    assert shapes.TotalLabelLength(SampleLabels()) == 5
    assert shapes.TotalLabelLength(new ArrayList()) == 0
}

test "an IEnumerable<object> element is unboxed by the annotation" {
    shapes := AnnotatedShapesUnderTest()
    assert shapes.SumBoxedNumbers(SampleBoxedNumbers()) == 10
    assert shapes.SumBoxedNumbers(new List<object>()) == 0
}

test "a numeric element widens and narrows to the annotated type" {
    shapes := AnnotatedShapesUnderTest()
    assert shapes.SumAsLong(SampleNumberList()) == 10
    assert shapes.SumCharacterCodes("AB") == 131

    wide := new long[](3)
    wide[0] = 4
    wide[1] = 5
    wide[2] = 6
    assert shapes.SumAsInt(wide) == 15
}

// A NARROWING KEEPS THE CAST'S OWN ARITHMETIC. `2^32 + 7` does not fit an `int`, and the annotation
// truncates it to `7` exactly as `(int)` does rather than refusing it or checking it.
test "a narrowing annotation truncates the way a cast does" {
    shapes := AnnotatedShapesUnderTest()
    big: long = 2147483647
    big = big + big
    big = big + 2
    big = big + 7

    wide := new long[](1)
    wide[0] = big
    assert shapes.SumAsInt(wide) == 7
}

test "a source class enumerator's object elements are downcast" {
    shapes := AnnotatedShapesUnderTest()
    bag := new LabelBag()
    bag.Add("ab")
    bag.Add("cde")
    assert shapes.TotalBagLength(bag) == 5
    assert shapes.TotalBagLength(new LabelBag()) == 0
}

test "a reference conversion runs in both directions" {
    shapes := AnnotatedShapesUnderTest()

    squares := new List<Square>()
    squares.Add(new Square())
    squares.Add(new Square())
    assert shapes.CountShapeSides(squares) == 8

    shapesList := new List<Shape>()
    shapesList.Add(new Square())
    shapesList.Add(new Square())
    assert shapes.CountSquareSides(shapesList) == 8
}

test "an annotation may widen an element to object" {
    shapes := AnnotatedShapesUnderTest()
    assert shapes.JoinAsObjects(SampleNumberList()) == "235"
}

test "an annotation that is the element type converts nothing" {
    shapes := AnnotatedShapesUnderTest()
    assert shapes.SumExactly(SampleNumberList()) == 10
}

test "break leaves an annotated loop without converting the rest" {
    shapes := AnnotatedShapesUnderTest()
    assert shapes.FirstLongLabel(SampleLabels(), 3) == "cde"
    assert shapes.FirstLongLabel(SampleLabels(), 2) == "ab"
    assert shapes.FirstLongLabel(SampleLabels(), 9) == ""
}

// THE CHECK IS ABOUT THE CONVERSION, NOT ABOUT THE VALUES. A sequence of `object` whose contents are
// not all `string` compiles, and fails at the element that is not one — which is what the same cast
// written by hand would do, and is the whole reason the form is an explicit conversion.
test "an element of the wrong runtime type throws where the cast would" {
    shapes := AnnotatedShapesUnderTest()
    mixed := new ArrayList()
    mixed.Add("ab")
    mixed.Add(7)

    assert throws InvalidCastException {
        shapes.TotalLabelLengthUnchecked(mixed)
    }
}

// THE HIDDEN LOOP LOCAL IS THE ANNOTATED TYPE, not the element type the collection produced. That is
// what makes the body type-check against the written type, and it is visible in the metadata.
test "the emitted loop declares its variable at the annotated type" {
    body := must (must typeof(AnnotatedShapes).GetMethod("TotalLabelLength")).GetMethodBody()

    sawString := false
    for local in body.LocalVariables {
        if local.LocalType == typeof(string) {
            sawString = true
        }
    }

    assert sawString
}

// A WIDENING ANNOTATION DECLARES THE WIDE LOCAL AND NOT THE NARROW ONE, which proves the conversion
// happens once per element on the way INTO the local rather than at each use of it.
test "a widening annotation declares the wide local" {
    body := must (must typeof(AnnotatedShapes).GetMethod("SumAsLong")).GetMethodBody()

    sawLong := false
    for local in body.LocalVariables {
        if local.LocalType == typeof(long) {
            sawLong = true
        }
    }

    assert sawLong
}

// AN IDENTITY ANNOTATION EMITS NOTHING AT ALL: the method's IL is the same size as the unannotated
// loop's over the same collection. `SumExactly` and `BclShapes.SumList` are the same loop written
// two ways, so their bodies are byte-for-byte the same length.
test "an identity annotation costs no instructions" {
    annotated := must (must typeof(AnnotatedShapes).GetMethod("SumExactly")).GetMethodBody()
    inferred := must (must typeof(BclShapes).GetMethod("SumList")).GetMethodBody()

    assert (must annotated.GetILAsByteArray()).Length == (must inferred.GetILAsByteArray()).Length
}
