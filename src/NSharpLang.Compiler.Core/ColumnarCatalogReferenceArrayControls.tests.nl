namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Construct the exact closed Dictionary and interface identities through the same CLR generic
// construction APIs that the declaration resolver sees.  This keeps these direct planner tests
// compilable before the array-declaration admission exists; the candidate changes the planner's
// answer, not the test source's signature surface.
func CatalogReferenceArrayDictionaryType(): Type {
    return AdmissibilityClosed2(
        "System.Collections.Generic.Dictionary`2",
        typeof(string),
        typeof(Type)
    )
}

func CatalogReferenceArrayInterfaceType(): Type {
    return AdmissibilityClosed2(
        "System.Collections.Generic.IReadOnlyDictionary`2",
        typeof(string),
        typeof(Type)
    )
}

// A real TypeDelegator-derived CLR type preserves the delegated foreign class's FullName, Assembly,
// value/reference shape, and generic arguments.  It changes only AssemblyQualifiedName, so a
// rejection reaches the exact catalog-identity comparison rather than an earlier structural guard.
func CatalogReferenceArrayForgedIdentityType(
    delegated: Type,
    identity: string
): Type {
    owner := TypeOfCreateBuilder(
        "CatalogReferenceArrayForgedIdentity",
        "CatalogReferenceArrayForgedIdentityAsm",
        0
    )
    ConstructionSetParent(owner, typeof(TypeDelegator))

    noParameters := new Type[](0)
    constructorParameters := new Type[](1)
    constructorParameters[0] = typeof(Type)
    constructor := owner.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        constructorParameters
    )
    constructorIl := constructor.GetILGenerator()
    parentConstructor := ExecutorRequiredConstructor(
        typeof(TypeDelegator),
        constructorParameters
    )
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Ldarg_1)
    constructorIl.Emit(OpCodes.Call, parentConstructor)
    constructorIl.Emit(OpCodes.Ret)

    identityTarget := SourceDiscoveryTimingRequiredGetter(
        typeof(Type),
        "AssemblyQualifiedName"
    )
    identityImplementation := owner.DefineMethod(
        "get_AssemblyQualifiedName",
        (MethodAttributes)2246,
        typeof(string),
        noParameters
    )
    identityIl := TypeOfMethodBuilderIL(identityImplementation)
    identityIl.Emit(OpCodes.Ldstr, identity)
    identityIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(identityImplementation, identityTarget)

    baked := IdentityBake(owner)
    bakedConstructor := ExecutorRequiredConstructor(baked, constructorParameters)
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, delegated)
    instance := bakedConstructor.Invoke(arguments)
    probe := instance as Type
    if probe == null {
        throw new InvalidOperationException("The catalog identity probe was not a Type.")
    }
    return probe
}

test "exact closed catalog references become valid SZ-array elements beyond Dictionary" {
    dictionary := CatalogReferenceArrayDictionaryType()
    dictionaryArray := dictionary.MakeArrayType()
    queue := AdmissibilityQueueOfInt()
    readOnlyDictionary := CatalogReferenceArrayInterfaceType()

    assert !dictionary.get_IsValueType()
    assert dictionaryArray.get_IsSZArray()
    assert dictionaryArray.GetElementType() == dictionary
    assert ColumnarTypeOfPlanner.IsSupportedCatalogType(dictionary)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(dictionary)
    assert ColumnarTypeOfPlanner.IsSupportedType(dictionaryArray)

    // Queue<int> is an unrelated closed reference class; IReadOnlyDictionary<string,Type> is an
    // interface.  Both must pass by their independently reproduced catalog identities, rather
    // than through a Dictionary name exception.
    assert ColumnarTypeOfPlanner.IsSupportedCatalogType(queue)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(queue)
    assert ColumnarTypeOfPlanner.IsSupportedType(queue.MakeArrayType())
    assert ColumnarTypeOfPlanner.IsSupportedCatalogType(readOnlyDictionary)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(readOnlyDictionary)
    assert ColumnarTypeOfPlanner.IsSupportedType(readOnlyDictionary.MakeArrayType())
}

test "catalog reference elements require the reproduced foreign assembly identity" {
    foreignBuilder := TypeOfCreateBuilder(
        "CatalogReferenceArrayForeign",
        "CatalogReferenceArrayForeignAsm",
        0
    )
    foreign := IdentityBake(foreignBuilder)
    foreignName := foreign.get_FullName() ?? ""
    foreignIdentity := foreign.get_AssemblyQualifiedName() ?? ""
    if foreignName.Length == 0 || foreignIdentity.Length == 0 {
        throw new InvalidOperationException("The foreign catalog type had no CLR identity.")
    }
    reproduced := foreign.get_Assembly().GetType(foreignName)
    if reproduced == null {
        throw new InvalidOperationException("The foreign catalog assembly did not reproduce its type.")
    }
    assert ExternalAssemblyScan.HasExactTypeIdentity(reproduced, foreignIdentity)
    assert ColumnarTypeOfPlanner.IsSupportedCatalogType(foreign)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(foreign)
    assert ColumnarTypeOfPlanner.IsSupportedType(foreign.MakeArrayType())

    // The same emitted TypeDelegator shape remains eligible when it reports the genuine identity.
    // This rules out a wrapper-specific early rejection as an explanation for the forged twin.
    honest := CatalogReferenceArrayForgedIdentityType(foreign, foreignIdentity)
    assert honest.get_FullName() == foreignName
    assert honest.get_AssemblyQualifiedName() == foreignIdentity
    assert ColumnarTypeOfPlanner.IsSupportedCatalogType(honest)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(honest)

    forgedIdentity := foreignName + ", CatalogReferenceArrayForgedIdentity"
    forged := CatalogReferenceArrayForgedIdentityType(
        foreign,
        forgedIdentity
    )
    assert forged.get_FullName() == foreignName
    assert forged.get_AssemblyQualifiedName() == forgedIdentity
    assert !ExternalAssemblyScan.HasExactTypeIdentity(reproduced, forgedIdentity)
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(forged)
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(forged)
}

test "a tuple is an array's element type, and a foreign value-type generic still is not" {
    // A TUPLE IS A VALUE A POSITION MAY HOLD, AND AN ARRAY IS A POSITION. The tuple syntax was
    // admitted at every declared position EXCEPT an array element, so `(Item: string, Count: int)[]`
    // declined at emit as a field's, a property's and a local's type alike -- and the labelled walk's
    // own array-element read could never be reached. An array of a tuple loads, stores and addresses
    // with the ordinary struct opcodes every other admitted value type already uses.
    tuple := typeof(ValueTuple<string, int>)
    assert tuple.get_IsValueType()
    assert ColumnarTypeOfPlanner.IsSupportedValueTuple(tuple)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(tuple)
    assert ColumnarTypeOfPlanner.IsSupportedType(tuple.MakeArrayType())

    // Nested and long tuples answer the same way, because the admission asks the tuple question and
    // nothing else.
    nested := typeof(ValueTuple<int, ValueTuple<int, int>>)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(nested)

    // The OPEN definition is not a tuple value, and neither is arity one -- `(T)` is not tuple syntax.
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(tuple.GetGenericTypeDefinition())
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(typeof(ValueTuple<int>))

    // AND THIS IS NOT A BLANKET ADMISSION OF CONSTRUCTED EXTERNAL VALUE-TYPE GENERICS: the documented
    // limit on `Vector<int>[]` is unchanged, which is what keeps the rule "a tuple" rather than "a
    // struct that happens to be generic".
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(typeof(System.Numerics.Vector<int>))
}

test "catalog reference element admission keeps unsupported runtime shapes out" {
    dictionary := CatalogReferenceArrayDictionaryType()
    openDictionary := dictionary.GetGenericTypeDefinition()
    rankTwo := dictionary.MakeArrayType(2)
    voidType := AdmissibilityRuntimeType("System.Void")

    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(dictionary.MakePointerType())
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(dictionary.MakeByRefType())
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(openDictionary)
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(dictionary.MakePointerType())
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(dictionary.MakeByRefType())
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(openDictionary)
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(voidType)
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(typeof(decimal))
    assert !rankTwo.get_IsSZArray()
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(rankTwo)
    assert !ColumnarTypeOfPlanner.IsSupportedType(rankTwo)
}

test "existing builder and generic-parameter allowances stay separate from closed builder-bound references" {
    sourceBuilder := TypeOfCreateBuilder(
        "CatalogReferenceArraySource",
        "CatalogReferenceArraySourceAsm",
        0
    )
    genericBuilder := TypeOfCreateBuilder(
        "CatalogReferenceArrayGeneric",
        "CatalogReferenceArrayGenericAsm",
        1
    )
    parameters := genericBuilder.GetGenericArguments()
    if parameters.Length != 1 {
        throw new InvalidOperationException("Expected one source generic parameter.")
    }
    parameter := parameters[0]
    sourceBuilderType: Type = sourceBuilder
    dictionaryDefinition := AdmissibilityRuntimeType(
        "System.Collections.Generic.Dictionary`2"
    )
    dictionaryArguments := new Type[](2)
    dictionaryArguments[0] = typeof(string)
    dictionaryArguments[1] = sourceBuilderType
    builderBoundDictionary := dictionaryDefinition.MakeGenericType(dictionaryArguments)

    assert ColumnarTypeOfPlanner.IsSupportedType(sourceBuilder)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(sourceBuilder)
    assert ColumnarTypeOfPlanner.IsSupportedType(parameter)
    assert ColumnarTypeOfPlanner.IsSupportedElementType(parameter)
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(builderBoundDictionary)
    assert !ColumnarTypeOfPlanner.IsSupportedElementType(builderBoundDictionary)
    assert !ColumnarTypeOfPlanner.IsSupportedType(builderBoundDictionary.MakeArrayType())
}
