namespace NSharpLang.CensusConversions.Tests

import System
import System.Reflection

func CensusNames(): string[] {
    names := new string[](2)
    names[0] = "Alice"
    names[1] = "Bob"
    return names
}

func CensusPack(): Dog[] {
    pack := new Dog[](1)
    pack[0] = new Dog("rex")
    return pack
}

func CensusRows(): string[][] {
    row := new string[](1)
    row[0] = "a"
    rows := new string[][](1)
    rows[0] = row
    return rows
}

test "a string array is an object array in every position" {
    names := CensusNames()

    // Argument, return and assignment. Each was `Cannot pass 'string[]' as argument for parameter
    // 'values' of type 'object[]'` / `Function 'f' should return object[] but returns string[]`.
    assert CountNames(names) == 2
    assert NamesAsValues(names).Length == 2

    // The conversion is a VIEW, not a copy: the element read back through `object[]` is the same
    // reference the `string[]` holds, which is only observable by comparing identity.
    read := FirstThroughValueView(names)
    assert Object.ReferenceEquals(read, names[0])
}

test "an array of an emitted subclass is an array of its emitted base" {
    pack := CensusPack()

    // Reflection.Emit cannot answer this pair for itself while both element types are unbaked, so
    // before the fix it declined with `emit.return.type-mismatch` rather than reporting a type error.
    animals := PackAsAnimals(pack)
    assert animals.Length == 1
    assert animals[0].Name == "rex"
    assert Object.ReferenceEquals(animals[0], pack[0])
}

test "array covariance composes and reaches an implemented interface" {
    rows := RowsAsValueRows(CensusRows())
    assert rows.Length == 1
    assert rows[0].Length == 1

    comparables := NamesAsComparables(CensusNames())
    assert comparables.Length == 2
    assert comparables[0].CompareTo("Alice") == 0
}

test "a store through a covariant view is checked at run time" {
    // A value the REAL element type accepts goes through…
    names := CensusNames()
    assert StoreThroughValueView(names, "Carol") == "stored"
    assert names[0] == "Carol"

    // …and one it does not throws ArrayTypeMismatchException, leaving the array untouched. This is
    // the whole reason the conversion may only cross reference types: the two names are one object.
    boxed: object = 42
    assert StoreThroughValueView(names, boxed) == "mismatch"
    assert names[0] == "Carol"

    // The same rule over types this compilation emits: a `Dog[]` seen as an `Animal[]` still refuses
    // a bare `Animal`.
    pack := CensusPack()
    assert StoreThroughAnimalView(pack, new Dog("fido")) == "stored"
    assert pack[0].Name == "fido"
    assert StoreThroughAnimalView(pack, new Animal("generic")) == "mismatch"
    assert pack[0].Name == "fido"
}

// The free functions of a source file are emitted as static methods of one holder type that nothing
// in the source names, so a signature is read the way any other consumer reads it: through the
// assembly these tests live in.
func FreeFunctionOf(name: string): MethodInfo? {
    assembly := typeof(Animal).get_Assembly()
    for candidate in assembly.GetTypes() {
        method := candidate.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
        if method != null {
            return method
        }
    }

    return null
}

func ReturnTypeOf(name: string): Type {
    method := FreeFunctionOf(name)
    if method == null {
        return typeof(object)
    }

    return method.get_ReturnType()
}

func FirstParameterTypeOf(name: string): Type {
    method := FreeFunctionOf(name)
    if method == null {
        return typeof(object)
    }

    parameters := method.GetParameters()
    if parameters.Length != 1 {
        return typeof(object)
    }

    return parameters[0].get_ParameterType()
}

test "the emitted signatures keep their exact element types" {
    // A conversion that is a no-op must not have been implemented by widening the DECLARATION: the
    // parameter is still `string[]` and the return is still `object[]`, so another language calling
    // this assembly sees what the source says.
    assert ReturnTypeOf("NamesAsValues") == typeof(object[])
    assert FirstParameterTypeOf("NamesAsValues") == typeof(string[])

    // The emitted `Dog[]` -> `Animal[]` method likewise keeps both of this compilation's own types.
    assert ReturnTypeOf("PackAsAnimals") == typeof(Animal[])
    assert FirstParameterTypeOf("PackAsAnimals") == typeof(Dog[])
}
