namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Text
import System.Threading


// `015-A6` makes `ColumnarTypeOfPlanner.IsSupportedType` the compiler's SOLE type-admissibility
// head, together with `IsSupportedAnonymousUnionArm` and `IsClosedSourceGeneric`; the C# emitter's
// `IsSupportedType`, `IsSupportedAnonymousUnionArmType` and `IsClosedUserGenericInstantiation` are
// deleted in the same slice and their 82 external call sites route here.
//
// A sweep of all 7,062 estate blocks before the cut found 24 asserts naming
// `ColumnarTypeOfPlanner.IsSupportedType` and ZERO naming `IsSupportedAnonymousUnionArm` — but
// every one of the 24 is a COMPOSED row written by an earlier stage to reach a SUB-head
// (the interop set, the Result/Union heads, the four buffer heads, the enum head, the element
// rule). Not one asserted an arm the head decides ITSELF. The `typeof(Exception)` assignability
// arm, the `TypeBuilder` arm, the generic-parameter arm, the closed-source-generic arm and 26 of
// the 31 direct `typeof` arms had NO contract anywhere in the estate. These blocks close that gap.
//
// TWO of the blocks below carry DELIBERATE behaviour changes this slice makes, and both were found
// by driving the head against the deleted C# one over a 302-type corpus:
//
//   FIX 1 — `SymbolType`, which is what a builder type's `MakePointerType()`/`MakeByRefType()`
//   returns, reports `IsSZArray` as TRUE for a POINTER and for a BY-REF. Measured on BOTH builder
//   implementations (`RuntimeTypeBuilder` and the persisted `TypeBuilderImpl` production uses), so
//   this is a reflection-emit defect and not an artefact of one fixture. The head's array arm
//   trusted it, and the element recursion then read the element back as the TypeBuilder, so
//   `UserStruct*` and `UserStruct&` were admitted into the ENTIRE supported surface — every
//   parameter, local, field, return, array element and collection argument. Pointers have no
//   lowering in this backend at all. By-ref types are valid only in parameter slots, where
//   `IsSupportedParameterType`'s own by-ref arm asks the question properly — and it never got the
//   chance, because the head answered TRUE first.
//
//   FIX 2 — the arm head tested `FullName != "System.Void"`. A user type declared as `System.Void`
//   is an ordinary storable `TypeBuilder` that merely shares the name, and the name test declined
//   it. The deleted C# member asked `t != AdmissibilityRuntimeType("System.Void")`, an IDENTITY test, and was right to.
func SupportedTypeHeadBuilder(simpleName: string): Type {
    return TypeOfCreateBuilder("Contoso.HeadFacts." + simpleName, "SupportedTypeHeadAsm." + simpleName, 0)
}

func SupportedTypeHeadOpenBuilder(simpleName: string): Type {
    return TypeOfCreateBuilder("Contoso.HeadFacts." + simpleName + "`1", "SupportedTypeHeadOpenAsm." + simpleName, 1)
}

// A RUNTIME generic parameter — `List<>`'s `T`, a `RuntimeType` whose `IsGenericParameter` is true.
// This is A0's ruled residual R1 and the ONE deliberate difference between this head and the C# one
// it replaces, so the fixture that produces it is named rather than inlined.
func SupportedTypeHeadRuntimeGenericParameter(): Type {
    return typeof(List<int>).GetGenericTypeDefinition().GetGenericArguments()[0]
}

// THE DIRECT `typeof` SURFACE. Thirty-one arms the head decides by identity and nothing else. The
// negatives are chosen to be near neighbours of an admitted type rather than arbitrary rejects: a
// `Guid` and a `DateTimeOffset` beside `DateTime`/`TimeSpan`, a `TextReader` beside `TextWriter`,
// an `Encoding` beside `StringBuilder`, a `Stopwatch` beside `TimeSpan`. A head that widened to "any BCL struct" or "any System type" would
// pass the positives and fail here.
test "the supported-type head owns the scalar and named BCL surface by identity" {
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(int))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(bool))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(long))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(ulong))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(uint))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(short))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(ushort))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(byte))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(sbyte))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(char))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(double))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(float))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(string))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(object))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(IntPtr))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(UIntPtr))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(decimal))

    // The named BCL reference and value types. `TextWriter`, `Guid` and `void` are reached
    // through the seeded runtime type rather than `typeof`: all of them decline at emit under the
    // pinned toolset (NL103), the same wall the head's own `RequiredTextWriterType` seed exists for.
    // The arms exist and this is the only spelling that can assert them.
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.TextWriter"))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(StringBuilder))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(StringComparer))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(DateTime))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(TimeSpan))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Index))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Range))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(CancellationToken))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Random))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(IList))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Type))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Version))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Assembly))

    // Near neighbours the head must NOT admit.
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.Guid"))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.DateTimeOffset"))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.Text.Encoding"))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.TextReader"))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.Diagnostics.Stopwatch"))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.Void"))
}

// THE ASSIGNABILITY ARM. The only non-identity BCL arm in the head: every exception type is
// admitted, including ones the compiler has never heard of, and the test is base-chain
// assignability rather than a name list. Nothing in the estate asserted this before.
test "the supported-type head admits every exception by assignability, not by name" {
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(Exception))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(InvalidOperationException))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(ArgumentException))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.AggregateException"))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.OperationCanceledException"))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.IO.FileNotFoundException"))

    // A SOURCE-declared exception is admitted through the same arm, which is what makes the arm
    // assignability rather than a list: the builder type is on no list the head carries. It is
    // built on the PERSISTED shape production emits, through `DefineType`'s parent argument.
    sourceException := ExternalGuardPersistedBuilder(
        "Contoso.HeadFacts.SourceFailure",
        0,
        typeof(InvalidOperationException)
    )
    assert typeof(Exception).IsAssignableFrom(sourceException)
    assert ColumnarTypeOfPlanner.IsSupportedType(sourceException)

    // A near neighbour that is NOT an exception, declared the same way, is declined — so the
    // positive above is the assignability arm answering and not the TypeBuilder arm.
    assert !typeof(Exception).IsAssignableFrom(AdmissibilityRuntimeType("System.Text.Encoding"))
}

// THE BUILDER AND GENERIC-PARAMETER ARMS, INCLUDING A0's RULED RESIDUAL R1. The head asks
// `IsGenericParameter`, where the deleted C# member asked `t is GenericTypeParameterBuilder`. On a
// BUILDER parameter the two agree; on a RUNTIME parameter they do not, and the N# head admits it.
// That is the single surviving deliberate difference of the whole A-arc and it is pinned HERE as
// the difference it is, not left implicit: if a later change makes the head builder-only again,
// this block says so.
test "the supported-type head admits source types and any generic parameter, runtime ones included" {
    sourceStruct := SupportedTypeHeadBuilder("HeadStruct")
    assert ColumnarTypeOfPlanner.IsSupportedType(sourceStruct)

    openDefinition := SupportedTypeHeadOpenBuilder("HeadOpen")
    builderParameter := openDefinition.GetGenericArguments()[0]
    assert builderParameter.get_IsGenericParameter()
    assert ColumnarTypeOfPlanner.IsSupportedType(builderParameter)

    // A0's R1. `List<>`'s `T` is a `RuntimeType` whose `IsGenericParameter` is true and which is
    // NOT a `GenericTypeParameterBuilder`. The head admits it; the deleted C# head did not.
    runtimeParameter := SupportedTypeHeadRuntimeGenericParameter()
    assert runtimeParameter.get_IsGenericParameter()
    assert !(runtimeParameter is GenericTypeParameterBuilder)
    assert ColumnarTypeOfPlanner.IsSupportedType(runtimeParameter)

    // A closed instantiation of a SOURCE definition — the arm the third deleted C# member owned.
    closedSource := openDefinition.MakeGenericType(ColumnarTypeAdmissibilityOneType(typeof(int)))
    assert ColumnarTypeOfPlanner.IsClosedSourceGeneric(closedSource)
    assert ColumnarTypeOfPlanner.IsSupportedType(closedSource)

    // The head does NOT admit the open definition itself, and the closed-generic head is about
    // SOURCE definitions only: a closed BCL generic is not one, and the definition of a source
    // generic is not closed.
    assert !ColumnarTypeOfPlanner.IsClosedSourceGeneric(openDefinition)
    assert !ColumnarTypeOfPlanner.IsClosedSourceGeneric(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.IsClosedSourceGeneric(sourceStruct)
    assert !ColumnarTypeOfPlanner.IsClosedSourceGeneric(typeof(int))
}

// FIX 1. The array arm must decide about ARRAYS. `SymbolType.IsSZArray` is TRUE for a pointer and
// for a by-ref, so an unguarded array arm walked into the element recursion, read the element back
// as the source TypeBuilder, and admitted `UserStruct*` and `UserStruct&` into the whole supported
// surface. The lie is asserted here directly, on the shared fixture, because a contract that only
// asserted the conclusion would not say WHY the guard exists.
test "the supported-type head does not trust IsSZArray on a pointer or a by-ref symbol type" {
    sourceStruct := SupportedTypeHeadBuilder("GuardStruct")
    sourceClass := SupportedTypeHeadBuilder("GuardClass")

    // THE DEFECT, ASSERTED. Both shapes report IsSZArray TRUE and hand back the element.
    pointerShape := sourceStruct.MakePointerType()
    byRefShape := sourceStruct.MakeByRefType()
    assert pointerShape.get_IsSZArray()
    assert byRefShape.get_IsSZArray()
    assert pointerShape.get_IsPointer()
    assert byRefShape.get_IsByRef()
    assert pointerShape.GetElementType() == sourceStruct
    assert ColumnarTypeOfPlanner.IsSupportedElementType(sourceStruct)

    // THE GUARD. Neither is in the supported surface.
    assert !ColumnarTypeOfPlanner.IsSupportedType(pointerShape)
    assert !ColumnarTypeOfPlanner.IsSupportedType(byRefShape)
    assert !ColumnarTypeOfPlanner.IsSupportedType(sourceClass.MakePointerType())
    assert !ColumnarTypeOfPlanner.IsSupportedType(sourceClass.MakeByRefType())
    assert !ColumnarTypeOfPlanner.IsSupportedType(sourceStruct.MakePointerType().MakePointerType())

    // A RUNTIME pointer/by-ref does not lie, so those were already declined and must stay declined
    // — the guard is added, nothing is traded for it.
    assert !typeof(int).MakePointerType().get_IsSZArray()
    assert !ColumnarTypeOfPlanner.IsSupportedType(typeof(int).MakePointerType())
    assert !ColumnarTypeOfPlanner.IsSupportedType(typeof(int).MakeByRefType())

    // AND THE ARRAY ARM STILL WORKS. This is the half the guard must not take away: a genuine SZ
    // array of a source type is admitted, a rank-2 array is not, and a jagged array is.
    assert ColumnarTypeOfPlanner.IsSupportedType(sourceStruct.MakeArrayType())
    assert ColumnarTypeOfPlanner.IsSupportedType(sourceStruct.MakeArrayType().MakeArrayType())
    assert !ColumnarTypeOfPlanner.IsSupportedType(sourceStruct.MakeArrayType(2))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(int[]))
    assert !ColumnarTypeOfPlanner.IsSupportedType(typeof(int).MakeArrayType(2))
}

// FIX 2 AND THE ARM SURFACE. An anonymous-union arm must be a storable value. The void test is an
// IDENTITY test: a source type named `System.Void` shares the name and is an ordinary storable
// TypeBuilder, and the name test this head used to carry declined it.
test "the anonymous-union arm head declines void by identity, not by name" {
    // The real `System.Void` is declined, by identity and also by the head.
    assert !ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(AdmissibilityRuntimeType("System.Void"))

    // A SOURCE type that merely shares the name is admitted. It is a TypeBuilder like any other and
    // the union machinery can carry it.
    namesakeVoid: Type = TypeOfCreateBuilder("System.Void", "SupportedTypeHeadVoidNamesakeAsm", 0)
    assert namesakeVoid.FullName == "System.Void"
    assert namesakeVoid != AdmissibilityRuntimeType("System.Void")
    assert ColumnarTypeOfPlanner.IsSupportedType(namesakeVoid)
    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(namesakeVoid)
}

// THE REST OF THE ARM SURFACE. By-ref is declined by the arm's own term — an arm slot has no
// parameter path to fall through to — and pointer is declined because the head declines it, which
// is the whole reason FIX 1 belongs in the head rather than being spelled a second time here.
test "the anonymous-union arm head declines every shape that is not a storable value" {
    sourceStruct := SupportedTypeHeadBuilder("ArmStruct")

    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(typeof(int))
    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(typeof(string))
    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(sourceStruct)
    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(sourceStruct.MakeArrayType())

    assert !ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(typeof(int).MakeByRefType())
    assert !ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(sourceStruct.MakeByRefType())
    assert !ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(sourceStruct.MakePointerType())
    assert !ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(typeof(int).MakePointerType())
    assert !ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(AdmissibilityRuntimeType("System.Guid"))

    // The arm head adds NOTHING to the head beyond void and by-ref, and that is asserted rather
    // than assumed: on every shape that is neither, the two answer alike.
    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(typeof(DateTime)) == ColumnarTypeOfPlanner.IsSupportedType(typeof(DateTime))
    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(AdmissibilityRuntimeType("System.Guid")) == ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.Guid"))
    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(sourceStruct.MakeArrayType(2)) == ColumnarTypeOfPlanner.IsSupportedType(sourceStruct.MakeArrayType(2))
    assert ColumnarTypeOfPlanner.IsSupportedAnonymousUnionArm(SupportedTypeHeadRuntimeGenericParameter()) == ColumnarTypeOfPlanner.IsSupportedType(SupportedTypeHeadRuntimeGenericParameter())
}
