namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Native contracts for the conversions an EXTERNAL type declares.
//
// The types under test are real referenced metadata rather than fixtures: the runtime's
// `Union<T0, T1>` declares the two-arm implicit conversions this owner exists for, and `decimal`
// declares the numeric explicit ones. Both are exactly what a user's program meets, and neither can
// be reshaped by a test that wants a different answer.
func ExternalConversionUnionOf(firstArm: Type, secondArm: Type): Type {
    definition := typeof(NSharpLang.Runtime.Union<int, string>).GetGenericTypeDefinition()
    arguments := new Type[](2)
    arguments[0] = firstArm
    arguments[1] = secondArm
    return definition.MakeGenericType(arguments)
}

func ExternalConversionParameterName(selection: ExternalConversionSelection): string {
    method := selection.Method
    if method == null {
        throw new InvalidOperationException("The selection carries no operator.")
    }

    parameters := method.GetParameters()
    if parameters.Length != 1 {
        throw new InvalidOperationException("A conversion operator has exactly one parameter.")
    }

    parameterType := parameters[0].get_ParameterType()
    return parameterType.get_Name()
}

func ExternalConversionOperatorNames(selection: ExternalConversionSelection): string {
    first := selection.Method
    second := selection.CompetingMethod
    if first == null || second == null {
        throw new InvalidOperationException("An ambiguous selection names two operators.")
    }

    firstParameters := first.GetParameters()
    secondParameters := second.GetParameters()
    return firstParameters[0].get_ParameterType().get_Name() + "|" + secondParameters[0].get_ParameterType().get_Name()
}

func ExternalConversionEmptyBuilder(): TypeBuilder {
    assemblyName := new AssemblyName("ExternalConversionProbe")
    assembly := AssemblyBuilder.DefineDynamicAssembly(assemblyName, AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule("ExternalConversionProbeModule")
    return module.DefineType("ExternalConversionProbeType")
}

test "an arm's implicit conversion is found on the TARGET, which is the only end that declares it" {
    unionType := ExternalConversionUnionOf(typeof(int), typeof(string))

    fromInt := ExternalUserDefinedConversions.ResolveImplicit(typeof(int), unionType)
    assert fromInt.IsSelected
    assert ExternalConversionParameterName(fromInt) == "Int32"

    fromText := ExternalUserDefinedConversions.ResolveImplicit(typeof(string), unionType)
    assert fromText.IsSelected
    assert ExternalConversionParameterName(fromText) == "String"
}

test "the source may WIDEN into the operator's parameter, which an exact-signature match would miss" {
    unionType := ExternalConversionUnionOf(typeof(long), typeof(string))

    fromInt := ExternalUserDefinedConversions.ResolveImplicit(typeof(int), unionType)
    assert fromInt.IsSelected
    assert ExternalConversionParameterName(fromInt) == "Int64"
}

test "a source no arm accepts is no conversion, not a nearest guess" {
    unionType := ExternalConversionUnionOf(typeof(int), typeof(string))

    fromBool := ExternalUserDefinedConversions.ResolveImplicit(typeof(bool), unionType)
    assert !fromBool.IsSelected
    assert !fromBool.IsAmbiguous
    assert fromBool.Method == null
}

test "two arms the source reaches equally are AMBIGUOUS, never an arbitrary arm" {
    // `int` widens to both `float` and `decimal`, and neither of those reaches the other by a
    // standard conversion — so §10.5.3 has no most specific source type and C# reports an error.
    unionType := ExternalConversionUnionOf(typeof(float), typeof(decimal))

    fromInt := ExternalUserDefinedConversions.ResolveImplicit(typeof(int), unionType)
    assert fromInt.IsAmbiguous
    assert !fromInt.IsSelected
    names := ExternalConversionOperatorNames(fromInt)
    assert names == "Single|Decimal" || names == "Decimal|Single"
}

test "two arms the source reaches UNEQUALLY pick the narrower one" {
    // `int` widens to both `long` and `double`, and `long` widens to `double` — so `long` is the
    // most encompassed parameter type and the `long` arm wins outright.
    unionType := ExternalConversionUnionOf(typeof(long), typeof(double))

    fromInt := ExternalUserDefinedConversions.ResolveImplicit(typeof(int), unionType)
    assert fromInt.IsSelected
    assert ExternalConversionParameterName(fromInt) == "Int64"
}

test "identity is not a user-defined conversion" {
    unionType := ExternalConversionUnionOf(typeof(int), typeof(string))

    selfConversion := ExternalUserDefinedConversions.ResolveImplicit(unionType, unionType)
    assert !selfConversion.IsSelected
    assert !selfConversion.IsAmbiguous
}

test "an EXPLICIT operator is reached only by the explicit question" {
    implicitAnswer := ExternalUserDefinedConversions.ResolveImplicit(typeof(decimal), typeof(int))
    assert !implicitAnswer.IsSelected
    assert !implicitAnswer.IsAmbiguous

    explicitAnswer := ExternalUserDefinedConversions.ResolveExplicit(typeof(decimal), typeof(int))
    assert explicitAnswer.IsSelected
    assert ExternalConversionParameterName(explicitAnswer) == "Decimal"
    selected := explicitAnswer.Method
    assert selected != null
    if selected != null {
        assert selected.get_Name() == "op_Explicit"
        assert selected.get_ReturnType() == typeof(int)
    }
}

test "the explicit question still reaches an IMPLICIT operator, because a cast may say what was implied" {
    unionType := ExternalConversionUnionOf(typeof(int), typeof(string))

    castFromInt := ExternalUserDefinedConversions.ResolveExplicit(typeof(int), unionType)
    assert castFromInt.IsSelected
    selected := castFromInt.Method
    assert selected != null
    if selected != null {
        assert selected.get_Name() == "op_Implicit"
    }
}

test "a NARROWING cast reaches the operator the implicit question refused" {
    // `implicit operator Union<long, string>(long)` does not accept a `double` implicitly, but a
    // written cast narrows `double` into `long` on the way in, which §10.5.4 admits.
    unionType := ExternalConversionUnionOf(typeof(long), typeof(string))

    implicitAnswer := ExternalUserDefinedConversions.ResolveImplicit(typeof(double), unionType)
    assert !implicitAnswer.IsSelected

    explicitAnswer := ExternalUserDefinedConversions.ResolveExplicit(typeof(double), unionType)
    assert explicitAnswer.IsSelected
    assert ExternalConversionParameterName(explicitAnswer) == "Int64"
}

test "a by-ref or pointer end declares nothing and asks nothing" {
    unionType := ExternalConversionUnionOf(typeof(int), typeof(string))

    byRefSource := ExternalUserDefinedConversions.ResolveImplicit(typeof(int).MakeByRefType(), unionType)
    assert !byRefSource.IsSelected

    byRefTarget := ExternalUserDefinedConversions.ResolveImplicit(typeof(int), unionType.MakeByRefType())
    assert !byRefTarget.IsSelected
}

test "a type still being EMITTED contributes no candidates rather than a guess" {
    builder := ExternalConversionEmptyBuilder()
    unionType := ExternalConversionUnionOf(typeof(int), typeof(string))

    builderSource := ExternalUserDefinedConversions.ResolveImplicit(builder, unionType)
    assert !builderSource.IsSelected
    assert !builderSource.IsAmbiguous

    builderTarget := ExternalUserDefinedConversions.ResolveImplicit(typeof(int), builder)
    assert !builderTarget.IsSelected
    assert !builderTarget.IsAmbiguous

    assert !ExternalUserDefinedConversions.DeclaresConversionOperators(builder)
}

test "an OPEN definition is not asked either — its members are written in parameters nothing has bound" {
    openUnion := typeof(NSharpLang.Runtime.Union<int, string>).GetGenericTypeDefinition()
    assert !ExternalUserDefinedConversions.DeclaresConversionOperators(openUnion)
    assert !ExternalUserDefinedConversions.ResolveImplicit(typeof(int), openUnion).IsSelected
}

test "the pre-filter answers for the types that actually declare operators" {
    assert !ExternalUserDefinedConversions.DeclaresConversionOperators(typeof(int))
    assert !ExternalUserDefinedConversions.DeclaresConversionOperators(typeof(bool))
    assert ExternalUserDefinedConversions.DeclaresConversionOperators(typeof(decimal))
    assert ExternalUserDefinedConversions.DeclaresConversionOperators(ExternalConversionUnionOf(typeof(int), typeof(string)))
    assert !ExternalUserDefinedConversions.DeclaresConversionOperators(null)

    // `string` DOES declare one — `implicit operator ReadOnlySpan<char>(string)` — and the filter
    // says so rather than assuming the primitives are inert.
    assert ExternalUserDefinedConversions.DeclaresConversionOperators(typeof(string))
}

test "a STANDARD conversion is identity, numeric widening, reference, boxing and their nullable lifts" {
    assert ExternalUserDefinedConversions.StandardConversionExists(typeof(int), typeof(int))
    assert ExternalUserDefinedConversions.StandardConversionExists(typeof(int), typeof(long))
    assert !ExternalUserDefinedConversions.StandardConversionExists(typeof(long), typeof(int))

    // Reference and boxing.
    assert ExternalUserDefinedConversions.StandardConversionExists(typeof(string), typeof(object))
    assert ExternalUserDefinedConversions.StandardConversionExists(typeof(int), typeof(object))
    assert !ExternalUserDefinedConversions.StandardConversionExists(typeof(object), typeof(string))

    // `T -> T?` and `S? -> T?` lift; `T? -> T` is explicit and never standard.
    nullableInt := typeof(Nullable<int>)
    nullableLong := typeof(Nullable<long>)
    assert ExternalUserDefinedConversions.StandardConversionExists(typeof(int), nullableInt)
    assert ExternalUserDefinedConversions.StandardConversionExists(typeof(int), nullableLong)
    assert ExternalUserDefinedConversions.StandardConversionExists(nullableInt, nullableLong)
    assert !ExternalUserDefinedConversions.StandardConversionExists(nullableInt, typeof(int))
    assert !ExternalUserDefinedConversions.StandardConversionExists(nullableLong, nullableInt)

    // A user-defined conversion is NOT a standard one, which is what stops the search recursing.
    assert !ExternalUserDefinedConversions.StandardConversionExists(typeof(int), ExternalConversionUnionOf(typeof(int), typeof(string)))
}

test "assignability accepts what the resolver selects and refuses what it calls ambiguous" {
    assignability := AssignabilityDefault()
    acceptingUnion: TypeInfo = new ReflectionTypeInfo(ExternalConversionUnionOf(typeof(int), typeof(string)))
    ambiguousUnion: TypeInfo = new ReflectionTypeInfo(ExternalConversionUnionOf(typeof(float), typeof(decimal)))

    assert assignability.ClassifyUserDefinedConversion(acceptingUnion, BuiltInTypes.Int).IsSelected
    assert assignability.IsAssignable(acceptingUnion, BuiltInTypes.Int)
    assert assignability.IsAssignable(acceptingUnion, BuiltInTypes.String)
    assert !assignability.IsAssignable(acceptingUnion, BuiltInTypes.Bool)

    // A tie is not a conversion: assignability answers false, and the classification says WHY.
    assert !assignability.IsAssignable(ambiguousUnion, BuiltInTypes.Int)
    assert assignability.ClassifyUserDefinedConversion(ambiguousUnion, BuiltInTypes.Int).IsAmbiguous
    assert !assignability.ClassifyUserDefinedConversion(acceptingUnion, BuiltInTypes.Bool).IsAmbiguous
}

test "a REFLECTED end's own conversion is reached, which the CLR's subtyping alone never answers" {
    assignability := AssignabilityDefault()
    dateTimeOffset: TypeInfo = new ReflectionTypeInfo(typeof(DateTimeOffset))
    dateTime: TypeInfo = new ReflectionTypeInfo(typeof(DateTime))

    // `DateTimeOffset` declares `implicit operator DateTimeOffset(DateTime)`. `IsAssignableFrom`
    // says no, and before the reflected arms became acceptance-only that no was the final answer.
    assert assignability.IsAssignable(dateTimeOffset, dateTime)
    assert !assignability.IsAssignable(dateTime, dateTimeOffset)
}

test "the built-in relation still answers first — a numeric widening is never a user-defined conversion" {
    assignability := AssignabilityDefault()
    decimalTarget: TypeInfo = BuiltInTypes.Decimal

    // `decimal` DOES declare `implicit operator decimal(int)`, but §10.2's numeric widening is the
    // conversion the language means, and it is decided several arms above the user-defined one.
    assert assignability.IsAssignable(decimalTarget, BuiltInTypes.Int)
    assert !assignability.IsAssignable(BuiltInTypes.Int, decimalTarget)
}

test "an ambiguous selection renders both operators the way the program spells them" {
    unionType := ExternalConversionUnionOf(typeof(float), typeof(decimal))
    tie := ExternalUserDefinedConversions.ResolveImplicit(typeof(int), unionType)
    assert tie.IsAmbiguous

    // Metadata names would say `Union<Single, Decimal>.op_Implicit(Single)`; the diagnostic says it
    // in the language's own words, so it reads as one sentence with the types around it.
    rendered := tie.SelectedText + " | " + tie.CompetingText
    assert rendered == "Union<float, decimal>.op_Implicit(float) | Union<float, decimal>.op_Implicit(decimal)" || rendered == "Union<float, decimal>.op_Implicit(decimal) | Union<float, decimal>.op_Implicit(float)"

    // An unresolved selection has nothing to name.
    none := ExternalUserDefinedConversions.ResolveImplicit(typeof(bool), unionType)
    assert none.SelectedText == ""
    assert none.CompetingText == ""
}

test "a type renders with its arity suffix dropped and its arguments written out" {
    assert ExternalUserDefinedConversions.TypeText(typeof(int)) == "int"
    assert ExternalUserDefinedConversions.TypeText(typeof(string)) == "string"
    assert ExternalUserDefinedConversions.TypeText(typeof(DateTime)) == "DateTime"
    assert ExternalUserDefinedConversions.TypeText(typeof(int).MakeArrayType()) == "int[]"
    assert ExternalUserDefinedConversions.TypeText(ExternalConversionUnionOf(typeof(int), typeof(string))) == "Union<int, string>"
}

test "the ambiguity report is NL202 with the sentence a tie needs, naming both operators" {
    error := ErrorMessageBuilder.AmbiguousUserDefinedConversion("App.nl", 7, 12, "    return 5", 1, "int", "Union<float, decimal>", "Union<float, decimal>.op_Implicit(float)", "Union<float, decimal>.op_Implicit(decimal)")

    assert error.Code == ErrorCode.TypeMismatch
    assert error.Message == "Converting 'int' to 'Union<float, decimal>' is ambiguous between 'Union<float, decimal>.op_Implicit(float)' and 'Union<float, decimal>.op_Implicit(decimal)'"
    assert error.ActualType == "int"
    assert error.ExpectedType == "Union<float, decimal>"
    assert error.DocsUrl == DiagnosticDocs.UrlFor("NL202")
}
