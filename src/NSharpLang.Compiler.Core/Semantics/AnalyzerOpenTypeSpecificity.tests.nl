namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Threading.Tasks
import NSharpLang.Compiler.Ast


// Native contracts for "more specific parameter types", the last tie-break in "better function
// member" and the only one that reads the signatures as WRITTEN.
//
// The reflected half is asserted over REAL open CLR types — `Func<>`'s own type parameter, and
// constructed types built over it — because the facts the walk reads (`IsGenericParameter`,
// `IsArray`, `GetGenericArguments`) are the reflection facts and nothing else would pin them.

// `Func<>`'s own type parameter, which is the only genuine open type parameter a test can name.
// The definition is reached through a CLOSED spelling because the pinned stage-0 compiler cannot
// parse an unbound `typeof(Func<>)`.
func OpenSpecificityFuncDefinition(): Type {
    return typeof(Func<int>).GetGenericTypeDefinition()
}

func OpenSpecificityTypeParameter(): Type {
    return OpenSpecificityFuncDefinition().GetGenericArguments()[0]
}

// `Func<X>` for any X, including an open one — the delegate shape every `Task.Run` overload wears.
func OpenSpecificityFunc(argument: Type): Type {
    return OpenSpecificityFuncDefinition().MakeGenericType([argument])
}

// `Task<X>`, likewise.
func OpenSpecificityTask(argument: Type): Type {
    return typeof(Task<int>).GetGenericTypeDefinition().MakeGenericType([argument])
}

func OpenSpecificityTypeList(values: Type?[]): Type?[] {
    return values
}

func OpenSpecificitySourceList(values: TypeReference?[]): TypeReference?[] {
    return values
}

func OpenSpecificityTypeParameters(names: string[]): List<TypeParameter> {
    parameters := new List<TypeParameter>()
    index := 0
    while index < names.Length {
        parameters.Add(new TypeParameter(names[index]))
        index = index + 1
    }

    return parameters
}

func OpenSpecificityGeneric(name: string, arguments: TypeReference[]): GenericTypeReference {
    typeArguments := new List<TypeReference>()
    index := 0
    while index < arguments.Length {
        typeArguments.Add(arguments[index])
        index = index + 1
    }

    return new GenericTypeReference(name, typeArguments)
}

// `Func<X>` as the SOURCE spells it: the parser keeps a written `Func<…>` as a function type, so a
// zero-parameter one is "() -> X".
func OpenSpecificityFunctionReference(returnType: TypeReference): FunctionTypeReference {
    return new FunctionTypeReference(new List<TypeReference>(), returnType)
}

test "A TYPE PARAMETER IS LESS SPECIFIC THAN A TYPE THAT IS NOT ONE" {
    assert AnalyzerOpenTypeSpecificity.CompareTypeParameterSpecificity(true, false) == AnalyzerOverloadSpecificity.RightIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareTypeParameterSpecificity(false, true) == AnalyzerOverloadSpecificity.LeftIsBetter

    // Two type parameters are the SAME claim, and two non-type-parameters are decided further down.
    assert AnalyzerOpenTypeSpecificity.CompareTypeParameterSpecificity(true, true) == AnalyzerOverloadSpecificity.NeitherIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareTypeParameterSpecificity(false, false) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "THE REFLECTED WALK ORDERS `Func<TResult>` BELOW `Func<Task<TResult>>`" {
    typeParameter := OpenSpecificityTypeParameter()
    bare := OpenSpecificityFunc(typeParameter)
    taskOfParameter := OpenSpecificityFunc(OpenSpecificityTask(typeParameter))

    // This IS `Task.Run(() => Task.FromResult(11))`: both close to `Func<Task<int>>`, and only the
    // written signatures tell them apart.
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(bare, taskOfParameter) == AnalyzerOverloadSpecificity.RightIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(taskOfParameter, bare) == AnalyzerOverloadSpecificity.LeftIsBetter

    // The same type against itself says nothing.
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(bare, bare) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "A DIFFERENT ARITY HAS NOTHING TO COMPARE ELEMENT-WISE" {
    typeParameter := OpenSpecificityTypeParameter()

    // `Func<Task>` against `Func<Task<TResult>>`: `Task` and `Task<TResult>` are both constructed
    // names, but one takes no type arguments, so this rule declines to order them. The score ladder
    // is what separates a delegate that discards the lambda's result from one that keeps it.
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(OpenSpecificityFunc(typeof(Task)), OpenSpecificityFunc(OpenSpecificityTask(typeParameter))) == AnalyzerOverloadSpecificity.NeitherIsBetter

    // Two closed, unrelated, non-generic types are likewise unordered.
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(typeof(string), typeof(int)) == AnalyzerOverloadSpecificity.NeitherIsBetter

    // A position either candidate left unfilled says nothing.
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(null, typeof(string)) == AnalyzerOverloadSpecificity.NeitherIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(typeof(string), null) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "AN ARRAY IS ORDERED BY ITS ELEMENT TYPE, AND ONLY AGAINST AN ARRAY OF THE SAME RANK" {
    typeParameter := OpenSpecificityTypeParameter()
    bareArray := typeParameter.MakeArrayType()
    taskArray := OpenSpecificityTask(typeParameter).MakeArrayType()

    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(bareArray, taskArray) == AnalyzerOverloadSpecificity.RightIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(taskArray, bareArray) == AnalyzerOverloadSpecificity.LeftIsBetter

    // Different rank, and array against non-array, are both "nothing to compare".
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(bareArray, OpenSpecificityTask(typeParameter).MakeArrayType(2)) == AnalyzerOverloadSpecificity.NeitherIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareReflectionTypes(bareArray, typeof(string)) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "A PARAMETER LIST IS FOLDED ALL-OR-NOTHING, SO A SPLIT DECISION IS NO DECISION" {
    typeParameter := OpenSpecificityTypeParameter()
    task := OpenSpecificityTask(typeParameter)

    // One position more specific, the rest silent: the candidate wins.
    assert AnalyzerOpenTypeSpecificity.CompareReflectionParameterLists(
        OpenSpecificityTypeList([null, OpenSpecificityFunc(typeParameter), typeof(string)]),
        OpenSpecificityTypeList([null, OpenSpecificityFunc(task), typeof(string)])
    ) == AnalyzerOverloadSpecificity.RightIsBetter

    // More specific at one position and less specific at another: INCOMPARABLE, which is how a
    // genuine ambiguity survives this rule rather than being broken by it.
    assert AnalyzerOpenTypeSpecificity.CompareReflectionParameterLists(
        OpenSpecificityTypeList([typeParameter, task]),
        OpenSpecificityTypeList([task, typeParameter])
    ) == AnalyzerOverloadSpecificity.NeitherIsBetter

    assert AnalyzerOpenTypeSpecificity.CompareReflectionParameterLists(
        OpenSpecificityTypeList([]),
        OpenSpecificityTypeList([])
    ) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "THE SOURCE WALK READS A TYPE PARAMETER AS A NAME THE SIGNATURE ITSELF DECLARED" {
    typeParameters := OpenSpecificityTypeParameters(["T"])

    assert AnalyzerOpenTypeSpecificity.IsSourceTypeParameter(new SimpleTypeReference("T"), typeParameters)
    assert !AnalyzerOpenTypeSpecificity.IsSourceTypeParameter(new SimpleTypeReference("string"), typeParameters)
    assert !AnalyzerOpenTypeSpecificity.IsSourceTypeParameter(OpenSpecificityGeneric("List", [new SimpleTypeReference("T")]), typeParameters)

    // A signature with no type parameters at all names none, whatever letters it wrote.
    assert !AnalyzerOpenTypeSpecificity.IsSourceTypeParameter(new SimpleTypeReference("T"), null)
}

test "THE SOURCE WALK ORDERS `Func<T>` BELOW `Func<List<T>>`" {
    // The parser keeps a written `Func<…>` as a FUNCTION type, so this is the shape the walk really
    // meets: `() -> T` against `() -> List<T>`.
    typeParameters := OpenSpecificityTypeParameters(["T"])
    bare := OpenSpecificityFunctionReference(new SimpleTypeReference("T"))
    listOfParameter := OpenSpecificityFunctionReference(OpenSpecificityGeneric("List", [new SimpleTypeReference("T")]))

    assert AnalyzerOpenTypeSpecificity.CompareSourceTypes(bare, listOfParameter, typeParameters, typeParameters) == AnalyzerOverloadSpecificity.RightIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareSourceTypes(listOfParameter, bare, typeParameters, typeParameters) == AnalyzerOverloadSpecificity.LeftIsBetter

    // A WRITTEN generic (`Wrapper<T>` against `Wrapper<List<T>>`) recurses the same way.
    assert AnalyzerOpenTypeSpecificity.CompareSourceTypes(
        OpenSpecificityGeneric("Wrapper", [new SimpleTypeReference("T")]),
        OpenSpecificityGeneric("Wrapper", [OpenSpecificityGeneric("List", [new SimpleTypeReference("T")])]),
        typeParameters,
        typeParameters
    ) == AnalyzerOverloadSpecificity.RightIsBetter

    // Arrays and nullables are the same question one level down.
    assert AnalyzerOpenTypeSpecificity.CompareSourceTypes(
        new ArrayTypeReference(new SimpleTypeReference("T")),
        new ArrayTypeReference(OpenSpecificityGeneric("List", [new SimpleTypeReference("T")])),
        typeParameters,
        typeParameters
    ) == AnalyzerOverloadSpecificity.RightIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareSourceTypes(
        new NullableTypeReference(new SimpleTypeReference("T")),
        new NullableTypeReference(OpenSpecificityGeneric("List", [new SimpleTypeReference("T")])),
        typeParameters,
        typeParameters
    ) == AnalyzerOverloadSpecificity.RightIsBetter

    // A different arity, and two shapes that are not the same kind, are unordered.
    assert AnalyzerOpenTypeSpecificity.CompareSourceTypes(
        OpenSpecificityGeneric("Wrapper", [new SimpleTypeReference("T")]),
        OpenSpecificityGeneric("Wrapper", [new SimpleTypeReference("T"), new SimpleTypeReference("T")]),
        typeParameters,
        typeParameters
    ) == AnalyzerOverloadSpecificity.NeitherIsBetter
    assert AnalyzerOpenTypeSpecificity.CompareSourceTypes(
        new ArrayTypeReference(new SimpleTypeReference("T")),
        new SimpleTypeReference("string"),
        typeParameters,
        typeParameters
    ) == AnalyzerOverloadSpecificity.NeitherIsBetter
}

test "EACH SOURCE CANDIDATE'S OWN TYPE-PARAMETER LIST DECIDES WHAT IS OPEN IN ITS SIGNATURE" {
    // `F<T>(x: T)` against `G(x: T)` where `G` declares no `T` at all: the second `T` is an ORDINARY
    // type name, so the second signature is the more specific one. The rule is about the shape each
    // declaration wrote, never about which letter it chose.
    assert AnalyzerOpenTypeSpecificity.CompareSourceTypes(
        new SimpleTypeReference("T"),
        new SimpleTypeReference("T"),
        OpenSpecificityTypeParameters(["T"]),
        OpenSpecificityTypeParameters([])
    ) == AnalyzerOverloadSpecificity.RightIsBetter

    assert AnalyzerOpenTypeSpecificity.CompareSourceParameterLists(
        OpenSpecificitySourceList([new SimpleTypeReference("T"), new SimpleTypeReference("string")]),
        OpenSpecificitySourceList([OpenSpecificityGeneric("List", [new SimpleTypeReference("U")]), new SimpleTypeReference("string")]),
        OpenSpecificityTypeParameters(["T"]),
        OpenSpecificityTypeParameters(["U"])
    ) == AnalyzerOverloadSpecificity.RightIsBetter

    // A position only one candidate filled says nothing.
    assert AnalyzerOpenTypeSpecificity.CompareSourceParameterLists(
        OpenSpecificitySourceList([null]),
        OpenSpecificitySourceList([OpenSpecificityGeneric("List", [new SimpleTypeReference("U")])]),
        OpenSpecificityTypeParameters(["T"]),
        OpenSpecificityTypeParameters(["U"])
    ) == AnalyzerOverloadSpecificity.NeitherIsBetter
}
