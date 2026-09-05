namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

// Native contracts for the CLR `Type` → `TypeInfo` conversion and its substitution variant.
//
// Both members were `private` in Analyzer.cs, so nothing named them: their behaviour was pinned only
// indirectly, through end-to-end diagnostics. These are their first DIRECT contracts, and they go at
// the decisions that read like plumbing and are not: the built-in table's PRIORITY over the composed
// arms, the by-ref shell being erased rather than modelled, the difference between "no override" and
// "an empty override", and the identity `ApplyReflectionBindings` preserves when nothing changed.
//
// Generic and non-primitive types are resolved by CANONICAL IDENTITY rather than through `typeof`:
// the columnar `typeof` surface does not carry most of them, and the resolved instances are the
// identical runtime ones.
func ConversionRuntimeType(canonicalName: string): Type {
    resolved := Type.GetType(canonicalName)
    if resolved == null {
        throw new InvalidOperationException("The runtime does not define '" + canonicalName + "'.")
    }

    return resolved
}

func ConversionListDefinition(): Type {
    return ConversionRuntimeType("System.Collections.Generic.List`1, System.Private.CoreLib")
}

func ConversionClosedList(argument: Type): Type {
    definition := ConversionListDefinition()
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

test "the built-in table answers every primitive by metadata name" {
    assert ConversionName(typeof(byte)) == "byte"
    assert ConversionName(typeof(sbyte)) == "sbyte"
    assert ConversionName(typeof(short)) == "short"
    assert ConversionName(typeof(ushort)) == "ushort"
    assert ConversionName(typeof(int)) == "int"
    assert ConversionName(typeof(uint)) == "uint"
    assert ConversionName(typeof(long)) == "long"
    assert ConversionName(typeof(ulong)) == "ulong"
    assert ConversionName(typeof(char)) == "char"
    assert ConversionName(typeof(float)) == "float"
    assert ConversionName(typeof(double)) == "double"
    assert ConversionName(typeof(decimal)) == "decimal"
    assert ConversionName(typeof(bool)) == "bool"
    assert ConversionName(typeof(string)) == "string"
    assert ConversionName(typeof(object)) == "object"
}

func ConversionName(clrType: Type): string {
    converted := AnalyzerReflectionTypeConversion.ConvertReflectionType(clrType)
    simple := converted as SimpleTypeInfo
    if simple == null {
        return "<not-simple>"
    }

    return simple.Name
}

test "a by-ref type is ERASED to its element, not modelled as by-ref" {
    byRefInt := typeof(int).MakeByRefType()
    converted := AnalyzerReflectionTypeConversion.ConvertReflectionType(byRefInt)
    simple := converted as SimpleTypeInfo
    assert simple != null
    assert simple.Name == "int"

    // The reason it reaches the by-ref arm at all: `int&`'s metadata name is NOT "System.Int32", so
    // the built-in table — which is consulted FIRST — does not claim it.
    assert byRefInt.get_FullName() != "System.Int32"
}

test "arrays and generics compose, and a generic head loses its arity suffix" {
    intArray := AnalyzerReflectionTypeConversion.ConvertReflectionType(typeof(int[]))
    array := intArray as ArrayTypeInfo
    assert array != null
    elementSimple := array.ElementType as SimpleTypeInfo
    assert elementSimple != null
    assert elementSimple.Name == "int"

    jagged := AnalyzerReflectionTypeConversion.ConvertReflectionType(typeof(int[][]))
    outer := jagged as ArrayTypeInfo
    assert outer != null
    inner := outer.ElementType as ArrayTypeInfo
    assert inner != null

    listOfStringType := ConversionClosedList(typeof(string))
    listOfString := AnalyzerReflectionTypeConversion.ConvertReflectionType(listOfStringType)
    generic := listOfString as GenericTypeInfo
    assert generic != null
    assert generic.Name == "List"
    assert generic.TypeArguments.Count == 1
    argumentSimple := generic.TypeArguments[0] as SimpleTypeInfo
    assert argumentSimple != null
    assert argumentSimple.Name == "string"

    // The definition it carries is the OPEN one, so nominal identity survives the conversion.
    definition := generic.GenericDefinition as ReflectionTypeInfo
    assert definition != null
    definitionType := definition.Type
    assert definitionType.get_IsGenericTypeDefinition()
}

test "an unmodelled type falls through to the reflected catch-all" {
    uriType := ConversionRuntimeType("System.Uri, System.Private.Uri")
    converted := AnalyzerReflectionTypeConversion.ConvertReflectionType(uriType)
    reflection := converted as ReflectionTypeInfo
    assert reflection != null
    reflected := reflection.Type
    assert reflected.get_FullName() == "System.Uri"

    // A bare generic PARAMETER has no built-in name and is not a composed form, so it lands here
    // too. This is what makes "an empty override" different from "no override at all".
    listDefinition := ConversionListDefinition()
    listParameters := listDefinition.GetGenericArguments()
    parameter := listParameters[0]
    parameterConverted := AnalyzerReflectionTypeConversion.ConvertReflectionType(parameter)
    parameterReflection := parameterConverted as ReflectionTypeInfo
    assert parameterReflection != null
    parameterReflected := parameterReflection.Type
    assert parameterReflected.get_IsGenericParameter()
}

test "with nothing to substitute the override walk IS the plain conversion" {
    emptyOverrides := new Dictionary<Type, TypeInfo>()
    emptyBindings := new Dictionary<Type, Type>()
    listOfInt := ConversionClosedList(typeof(int))
    plain := AnalyzerReflectionTypeConversion.ConvertReflectionType(listOfInt)
    withEmpty := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
        listOfInt,
        emptyOverrides,
        emptyBindings
    )
    withNull := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
        listOfInt,
        emptyOverrides,
        null
    )
    assert TypeInfoIdentityFacts.AreEqual(plain, withEmpty)
    assert TypeInfoIdentityFacts.AreEqual(plain, withNull)
}

test "a TypeInfo override beats a CLR binding, and both only apply at a generic parameter" {
    definition := ConversionListDefinition()
    definitionParameters := definition.GetGenericArguments()
    parameter := definitionParameters[0]

    overrides := new Dictionary<Type, TypeInfo>()
    overrides[parameter] = BuiltInTypes.String
    bindings := new Dictionary<Type, Type>()
    bindings[parameter] = typeof(int)

    both := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
        parameter,
        overrides,
        bindings
    )
    bothSimple := both as SimpleTypeInfo
    assert bothSimple != null
    assert bothSimple.Name == "string"

    onlyBinding := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
        parameter,
        new Dictionary<Type, TypeInfo>(),
        bindings
    )
    bindingSimple := onlyBinding as SimpleTypeInfo
    assert bindingSimple != null
    assert bindingSimple.Name == "int"

    // A CONCRETE type is never overridden, however full the tables are.
    concrete := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
        typeof(string),
        overrides,
        bindings
    )
    concreteSimple := concrete as SimpleTypeInfo
    assert concreteSimple != null
    assert concreteSimple.Name == "string"
}

test "the override walk descends through arrays, by-refs and generic arguments" {
    definition := ConversionListDefinition()
    definitionParameters := definition.GetGenericArguments()
    parameter := definitionParameters[0]
    overrides := new Dictionary<Type, TypeInfo>()
    overrides[parameter] = BuiltInTypes.Bool
    bindings := new Dictionary<Type, Type>()

    arrayOfParameter := parameter.MakeArrayType()
    convertedArray := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
        arrayOfParameter,
        overrides,
        bindings
    )
    array := convertedArray as ArrayTypeInfo
    assert array != null
    elementSimple := array.ElementType as SimpleTypeInfo
    assert elementSimple != null
    assert elementSimple.Name == "bool"

    byRefParameter := parameter.MakeByRefType()
    convertedByRef := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
        byRefParameter,
        overrides,
        bindings
    )
    byRefSimple := convertedByRef as SimpleTypeInfo
    assert byRefSimple != null
    assert byRefSimple.Name == "bool"

    openParameterList := ConversionClosedList(parameter)
    convertedList := AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
        openParameterList,
        overrides,
        bindings
    )
    generic := convertedList as GenericTypeInfo
    assert generic != null
    assert generic.Name == "List"
    argumentSimple := generic.TypeArguments[0] as SimpleTypeInfo
    assert argumentSimple != null
    assert argumentSimple.Name == "bool"
}

test "applying bindings answers the ORIGINAL instance when nothing changed" {
    bindings := new Dictionary<Type, Type>()
    listOfInt := ConversionClosedList(typeof(int))
    unchanged := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(listOfInt, bindings)
    assert Object.ReferenceEquals(unchanged, listOfInt)

    intArrayType := typeof(int[])
    unchangedArray := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(intArrayType, bindings)
    assert Object.ReferenceEquals(unchangedArray, intArrayType)
}

test "applying bindings rewrites a parameter through arrays, by-refs and instantiations" {
    definition := ConversionListDefinition()
    definitionParameters := definition.GetGenericArguments()
    parameter := definitionParameters[0]
    bindings := new Dictionary<Type, Type>()
    bindings[parameter] = typeof(string)

    direct := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(parameter, bindings)
    assert Object.Equals(direct, typeof(string))

    arrayApplied := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(
        parameter.MakeArrayType(),
        bindings
    )
    assert Object.Equals(arrayApplied, typeof(string[]))

    byRefApplied := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(
        parameter.MakeByRefType(),
        bindings
    )
    assert byRefApplied.get_IsByRef()
    byRefElement := byRefApplied.GetElementType()
    assert byRefElement != null
    assert Object.Equals(byRefElement, typeof(string))

    openList := ConversionClosedList(parameter)
    listApplied := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(openList, bindings)
    expectedList := ConversionClosedList(typeof(string))
    assert Object.Equals(listApplied, expectedList)
}

test "the BOUND override rule differs from the direct one exactly where it should" {
    definition := ConversionListDefinition()
    definitionParameters := definition.GetGenericArguments()
    parameter := definitionParameters[0]
    bindings := new Dictionary<Type, Type>()
    bindings[parameter] = typeof(int)
    noOverrides := new Dictionary<Type, TypeInfo>()
    listOfString := ConversionClosedList(typeof(string))
    openList := ConversionClosedList(parameter)

    // A CLOSED type with no TypeInfo overrides takes the "apply the bindings, then convert" arm.
    closed := AnalyzerReflectionTypeConversion.ConvertBoundType(
        listOfString,
        noOverrides,
        bindings,
        false
    )
    closedGeneric := closed as GenericTypeInfo
    assert closedGeneric != null
    assert closedGeneric.Name == "List"

    // An OPEN one still mentions a type parameter, so it takes the override walk.
    openApplied := AnalyzerReflectionTypeConversion.ConvertBoundType(
        openList,
        noOverrides,
        bindings,
        false
    )
    openGeneric := openApplied as GenericTypeInfo
    assert openGeneric != null
    argumentSimple := openGeneric.TypeArguments[0] as SimpleTypeInfo
    assert argumentSimple != null
    assert argumentSimple.Name == "int"

    // And declaring that TypeInfo overrides EXIST forces the override walk even for a closed type.
    forced := AnalyzerReflectionTypeConversion.ConvertBoundType(
        listOfString,
        noOverrides,
        bindings,
        true
    )
    forcedGeneric := forced as GenericTypeInfo
    assert forcedGeneric != null
    assert forcedGeneric.Name == "List"
}

// THE SUPPLIED ARGUMENT'S EXPECTED TYPE (task 017 slice 20 phase B). One decision: which spelling of
// the parameter to convert. An EXPANDED params tail records the ELEMENT type while the declaration
// still says ARRAY, so reading the parameter there would expect the array and reject every element.
test "an expanded params element is converted from its recorded element type" {
    format := ConversionFormatMethod()
    parameters := format.GetParameters()
    tail := parameters[1]
    assert tail.get_ParameterType() == typeof(object[])

    elementType := tail.get_ParameterType().GetElementType()
    assert elementType != null

    // The EXPANDED spelling: the bound argument carries the ELEMENT type.
    expanded := new SuppliedReflectionBoundArgument(
        1,
        elementType,
        ConversionArgument(),
        1
    )
    expandedType := AnalyzerReflectionTypeConversion.ConvertSuppliedArgumentType(
        expanded,
        tail,
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        false
    )
    assert !(expandedType is ArrayTypeInfo)

    // The DIRECT spelling: the bound argument carries the declared ARRAY, so the parameter is read
    // and the expected type is the array itself.
    direct := new SuppliedReflectionBoundArgument(
        1,
        tail.get_ParameterType(),
        ConversionArgument(),
        1
    )
    directType := AnalyzerReflectionTypeConversion.ConvertSuppliedArgumentType(
        direct,
        tail,
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        false
    )
    assert directType is ArrayTypeInfo
}

test "an ordinary position is converted from the parameter, not the recorded type" {
    format := ConversionFormatMethod()
    parameters := format.GetParameters()
    head := parameters[0]
    assert head.get_ParameterType() == typeof(string)

    // The recorded open type is deliberately WRONG here; a non-params position must still read the
    // PARAMETER, because that is what carries the declaration's nullability metadata.
    supplied := new SuppliedReflectionBoundArgument(
        0,
        typeof(int),
        ConversionArgument(),
        0
    )
    answered := AnalyzerReflectionTypeConversion.ConvertSuppliedArgumentType(
        supplied,
        head,
        new Dictionary<Type, Type>(),
        new Dictionary<Type, TypeInfo>(),
        false
    )
    assert ConversionTypeName(answered) == "string"
}

func ConversionFormatMethod(): MethodInfo {
    stringType := typeof(string)
    methods := stringType.GetMethods()
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == "Format" {
            parameters := candidate.GetParameters()
            if parameters.Length == 2 {
                first := parameters[0].get_ParameterType()
                second := parameters[1].get_ParameterType()
                if first == typeof(string) && second == typeof(object[]) {
                    return candidate
                }
            }
        }

        index = index + 1
    }

    throw new InvalidOperationException("string.Format(string, object[]) was not found.")
}

func ConversionArgument(): Argument {
    value: Expression = new IdentifierExpression("x", 1, 1)
    return new Argument(null, value, ArgumentModifier.None)
}

func ConversionTypeName(typeInfo: TypeInfo): string {
    asObject := typeInfo as object
    rendered := asObject.ToString()
    return rendered ?? "unknown"
}
