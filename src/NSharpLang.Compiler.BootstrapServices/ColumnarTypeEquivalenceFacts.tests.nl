namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

// THE CONTRACT FOR THE PORTED EMIT-TIME TYPE IDENTITY (015-B10).
//
// `ColumnarTypeEquivalenceFacts` came out of `ColumnarIlEmitter.cs` whole. The C# owner keeps three
// call-shape forwarders and no copy of the rule, so every arm below is now pinned in N# for the first
// time — the C# original had no unit contract at all, only the corpus.
enum TypeEquivalenceProbeEnum {
    Zero = 0,
    One = 1
}

func TypeEquivalenceBuilder(name: string, assemblyIdentity: string, arity: int): Type {
    return TypeOfCreateBuilder(name, assemblyIdentity, arity)
}

func TypeEquivalenceClosed(definition: Type, argument: Type): Type {
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

test "type equivalence separates distinct declarations and matches a type with itself" {
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(int), typeof(int))
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(int), typeof(long))
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(string), typeof(object))

    builder := TypeEquivalenceBuilder("EquivalenceSelf", "ColumnarTypeEquivalenceTests.Self", 0)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(builder, builder)

    other := TypeEquivalenceBuilder("EquivalenceOther", "ColumnarTypeEquivalenceTests.Other", 0)
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(builder, other)

    // A builder is never equivalent to a baked type, in either argument order.
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(builder, typeof(int))
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(int), builder)
}

// THE REASON THE FUNCTION EXISTS. `MakeGenericType` over a `TypeBuilder` does not cache and
// `TypeBuilderInstantiation` equality is referential, so two independent closures of one definition are
// DISTINCT objects describing the SAME type. The `assert !SameObject` line is the premise, measured
// rather than assumed — without it a passing equivalence assertion could just be reference equality.
test "type equivalence equates two distinct closed instantiations of one builder-headed generic" {
    definition := TypeEquivalenceBuilder("EquivalenceBox", "ColumnarTypeEquivalenceTests.Box", 1)

    first := TypeEquivalenceClosed(definition, typeof(int))
    second := TypeEquivalenceClosed(definition, typeof(int))
    assert !ColumnarConstructionPlanner.SameObject(first, second)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(first, second)

    // The ARGUMENT still decides: a different closure of the same definition is a different type.
    third := TypeEquivalenceClosed(definition, typeof(long))
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(first, third)

    // And so does the DEFINITION: the open definition is not one of its closures.
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(first, definition)

    // Nested closures recurse: `Box<Box<int>>` built twice is one type.
    nestedFirst := TypeEquivalenceClosed(definition, first)
    nestedSecond := TypeEquivalenceClosed(definition, second)
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(nestedFirst, nestedSecond)
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(nestedFirst, first)
}

// The SZ-array and by-ref arms, over UNBAKED builders — the shapes whose `IsSZArray`/`GetElementType`
// reads are the ones the guards exist for. `MakeArrayType`/`MakeByRefType` over a builder also produce
// distinct objects per call, so these are recursions rather than reference matches.
test "type equivalence recurses through by-ref and SZ-array shapes over unbaked builders" {
    element := TypeEquivalenceBuilder("EquivalenceElement", "ColumnarTypeEquivalenceTests.Element", 0)

    arrayFirst := element.MakeArrayType()
    arraySecond := element.MakeArrayType()
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(arrayFirst, arraySecond)

    byRefFirst := element.MakeByRefType()
    byRefSecond := element.MakeByRefType()
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(byRefFirst, byRefSecond)

    // The two composite arms do not leak into each other, and neither equates a composite with its
    // element — each arm requires BOTH sides to carry the same shape.
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(arrayFirst, byRefFirst)
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(arrayFirst, element)
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(byRefFirst, element)

    // A baked array is still an ordinary equality.
    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(int[]), typeof(int[]))
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(int[]), typeof(long[]))
}

// ⚠ THE MODULE HALF OF DECLARED IDENTITY IS LOAD-BEARING, AND THIS IS THE BLOCK THAT SAYS SO.
// Two builders can carry the SAME `FullName` in DIFFERENT dynamic assemblies — one process emits many,
// and this test host emits one per case — so a name-only test would silently equate two unrelated
// types. Dropping the module read is the exact way this predicate could be weakened without any other
// contract noticing, so the premise (equal names) is asserted before the verdict (not equivalent).
test "declared identity refuses two same-named builders from different modules" {
    first := TypeEquivalenceBuilder("EquivalenceTwin", "ColumnarTypeEquivalenceTests.TwinLeft", 0)
    second := TypeEquivalenceBuilder("EquivalenceTwin", "ColumnarTypeEquivalenceTests.TwinRight", 0)

    assert !ColumnarConstructionPlanner.SameObject(first, second)
    assert first.get_FullName() == second.get_FullName()
    assert !ColumnarTypeEquivalenceFacts.SameDeclaredIdentity(first, second)
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(first, second)

    // The same builder against itself passes both halves, so the refusal above is the MODULE's.
    assert ColumnarTypeEquivalenceFacts.SameDeclaredIdentity(first, first)
}

// The guarded reads, each answered for a baked shape and for an unbaked builder-rooted one. These are
// the three members the C# emitter still forwards to (two of them from its `params` lowering), so their
// answers are a public contract rather than an internal detail.
test "the guarded reflection reads answer for baked and unbaked shapes" {
    assert ColumnarTypeEquivalenceFacts.IsSzArrayType(typeof(int[]))
    assert !ColumnarTypeEquivalenceFacts.IsSzArrayType(typeof(int))
    assert !ColumnarTypeEquivalenceFacts.IsSzArrayType(typeof(string))

    element := TypeEquivalenceBuilder("EquivalenceGuard", "ColumnarTypeEquivalenceTests.Guard", 0)
    assert ColumnarTypeEquivalenceFacts.IsSzArrayType(element.MakeArrayType())
    assert !ColumnarTypeEquivalenceFacts.IsSzArrayType(element)

    assert ColumnarTypeEquivalenceFacts.IsByRefType(typeof(int).MakeByRefType())
    assert !ColumnarTypeEquivalenceFacts.IsByRefType(typeof(int))
    assert ColumnarTypeEquivalenceFacts.IsByRefType(element.MakeByRefType())

    assert ColumnarTypeEquivalenceFacts.TryGetElementType(typeof(int[])) == typeof(int)
    assert ColumnarTypeEquivalenceFacts.TryGetElementType(typeof(int)) == null
    assert ColumnarTypeEquivalenceFacts.TryGetElementType(element) == null
}

// The enum arm runs BEFORE every other arm, so an enum is never compared as a generic or as a builder.
test "enum identity is answered by the enum arm rather than the generic one" {
    assert ColumnarTypeEquivalenceFacts.IsSameEnumType(typeof(TypeEquivalenceProbeEnum), typeof(TypeEquivalenceProbeEnum))
    assert !ColumnarTypeEquivalenceFacts.IsSameEnumType(typeof(TypeEquivalenceProbeEnum), typeof(ColumnarRangePlannerProbeEnum))

    // A non-enum pair is refused BY THIS FUNCTION even when the two types are equal, because it is the
    // enum question and not the equality question.
    assert !ColumnarTypeEquivalenceFacts.IsSameEnumType(typeof(int), typeof(int))

    assert ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(TypeEquivalenceProbeEnum), typeof(TypeEquivalenceProbeEnum))
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(TypeEquivalenceProbeEnum), typeof(ColumnarRangePlannerProbeEnum))

    // An enum against its own underlying type is refused by the enum arm — one side being an enum is
    // enough to take that arm, which is what stops `int` and an int-backed enum being one type here.
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(TypeEquivalenceProbeEnum), typeof(int))
    assert !ColumnarTypeEquivalenceFacts.TypesEquivalent(typeof(int), typeof(TypeEquivalenceProbeEnum))
}
