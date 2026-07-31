namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// The emitter's `new` chain does not model this type. The established N# idiom for an external
// instance it does not model is the reflected constructor — `ExternalAssemblyScan` builds its
// MetadataLoadContext exactly this way.
func NullabilityProbeContext(): NullabilityInfoContext {
    parameterTypes := new Type[](0)
    constructor := typeof(NullabilityInfoContext).GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("NullabilityInfoContext() was not found.")
    }

    arguments := new object?[](0)
    return (NullabilityInfoContext)constructor.Invoke(arguments)
}

func NullabilityProbeReadState(info: NullabilityInfo?): NullabilityState {
    if info == null {
        return NullabilityState.Unknown
    }

    return info.get_ReadState()
}

// `IList<T>` is what GetCustomAttributesData and ConstructorArguments answer with, and `Count`
// lives on ICollection<T>, which an interface receiver's own member lookup does not reach. Binding
// the sequence through an `object` and reading the non-generic `IList.Count` is exact — the same
// instance, the same value — and is the idiom the port uses wherever it needs a length.
func NullabilityProbeSequenceCount(sequence: object): int {
    list := (IList)sequence
    return list.Count
}

func NullabilityProbeStringParameter(methodName: string): ParameterInfo {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    method := typeof(string).GetMethod(methodName, parameterTypes)
    if method == null {
        throw new InvalidOperationException("String." + methodName + " was not found.")
    }

    parameters := method.GetParameters()
    return parameters[0]
}

test "a nullability context answers the read state of an annotated parameter" {
    context := NullabilityProbeContext()

    // String.IsNullOrEmpty(string? value) — the parameter is annotated nullable.
    nullableParameter := NullabilityProbeStringParameter("IsNullOrEmpty")
    nullableInfo := context.Create(nullableParameter)
    assert NullabilityProbeReadState(nullableInfo) == NullabilityState.Nullable

    // String.Contains(string value) — the same shape, annotated NOT nullable.
    notNullParameter := NullabilityProbeStringParameter("Contains")
    notNullInfo := context.Create(notNullParameter)
    assert NullabilityProbeReadState(notNullInfo) != NullabilityState.Nullable
    assert NullabilityProbeReadState(null) == NullabilityState.Unknown
}

test "a nullability context answers for properties and fields as well as parameters" {
    context := NullabilityProbeContext()

    lengthProperty := typeof(string).GetProperty("Length")
    if lengthProperty == null {
        throw new InvalidOperationException("String.Length was not found.")
    }

    lengthInfo := context.Create(lengthProperty)
    assert NullabilityProbeReadState(lengthInfo) != NullabilityState.Nullable

    emptyField := typeof(string).GetField("Empty")
    if emptyField == null {
        throw new InvalidOperationException("String.Empty was not found.")
    }

    emptyInfo := context.Create(emptyField)
    assert NullabilityProbeReadState(emptyInfo) != NullabilityState.Nullable
}

test "nullability info composes through element and generic-argument positions" {
    context := NullabilityProbeContext()

    dictionaryDefinition := Type.GetType(
        "System.Collections.Generic.Dictionary`2, System.Private.CoreLib")
    if dictionaryDefinition == null {
        throw new InvalidOperationException("Dictionary`2 was not found.")
    }

    closedArguments := new Type[](2)
    closedArguments[0] = typeof(string)
    closedArguments[1] = typeof(string)
    closedDictionary := dictionaryDefinition.MakeGenericType(closedArguments)
    tryGetValue := closedDictionary.GetMethod("TryGetValue")
    if tryGetValue == null {
        throw new InvalidOperationException("Dictionary.TryGetValue was not found.")
    }

    outParameter := tryGetValue.GetParameters()[1]
    assert outParameter.get_IsOut()
    assert outParameter.get_Name() == "value"

    outInfo := context.Create(outParameter)
    assert NullabilityProbeReadState(outInfo) == NullabilityState.Nullable
    // The element position is empty for a non-array reference; the walk still answers.
    assert outInfo.get_ElementType() == null

    genericArguments := outInfo.get_GenericTypeArguments()
    assert genericArguments != null
    assert genericArguments.Length == 0

    // An ARRAY parameter carries the element position instead.
    concatTypes := new Type[](1)
    concatTypes[0] = typeof(string[])
    concat := typeof(string).GetMethod("Concat", concatTypes)
    if concat == null {
        throw new InvalidOperationException("String.Concat(string[]) was not found.")
    }

    arrayParameters := concat.GetParameters()
    arrayParameter := arrayParameters[0]
    arrayInfo := context.Create(arrayParameter)
    assert arrayInfo.get_ElementType() != null
}

test "a method's return parameter is a parameter like any other" {
    context := NullabilityProbeContext()

    trimTypes := new Type[](0)
    trim := typeof(string).GetMethod("Trim", trimTypes)
    if trim == null {
        throw new InvalidOperationException("String.Trim() was not found.")
    }

    returnParameter := trim.get_ReturnParameter()
    assert returnParameter != null
    assert !returnParameter.get_IsOut()

    returnInfo := context.Create(returnParameter)
    assert NullabilityProbeReadState(returnInfo) != NullabilityState.Nullable
}

test "the underlying type of a nullable value type is reachable" {
    assert Nullable.GetUnderlyingType(typeof(int?)) == typeof(int)
    assert Nullable.GetUnderlyingType(typeof(int)) == null
    assert Nullable.GetUnderlyingType(typeof(string)) == null
}

test "custom attribute data carries the flow attributes annotation cannot express" {
    // String.IsNullOrEmpty's parameter carries [NotNullWhen(false)] — one boolean constructor
    // argument. That is the exact shape the formatter half reads, and the only reason
    // CustomAttributeData is needed at all: presence alone would not tell it WHICH value.
    flowParameter := NullabilityProbeStringParameter("IsNullOrEmpty")
    attributes := flowParameter.GetCustomAttributesData()
    count := NullabilityProbeSequenceCount(attributes)
    assert count > 0

    seenNotNullWhen := false
    notNullWhenValue := true
    index := 0
    while index < count {
        attribute := attributes.get_Item(index)
        attributeType := attribute.get_AttributeType()
        if attributeType.FullName == "System.Diagnostics.CodeAnalysis.NotNullWhenAttribute" {
            seenNotNullWhen = true
            constructorArguments := attribute.get_ConstructorArguments()
            assert NullabilityProbeSequenceCount(constructorArguments) == 1
            argument := constructorArguments.get_Item(0)
            assert argument.get_ArgumentType() == typeof(bool)
            value := argument.get_Value()
            assert value != null
            falseValue: object = false
            boxedValue: object = value ?? falseValue
            notNullWhenValue = !boxedValue.Equals(falseValue)
        }

        index = index + 1
    }

    assert seenNotNullWhen
    assert !notNullWhenValue
}

test "attribute data is readable from properties, fields and methods too" {
    lengthProperty := typeof(string).GetProperty("Length")
    if lengthProperty == null {
        throw new InvalidOperationException("String.Length was not found.")
    }

    propertyAttributes := lengthProperty.GetCustomAttributesData()
    assert NullabilityProbeSequenceCount(propertyAttributes) >= 0

    emptyField := typeof(string).GetField("Empty")
    if emptyField == null {
        throw new InvalidOperationException("String.Empty was not found.")
    }

    fieldAttributes := emptyField.GetCustomAttributesData()
    assert NullabilityProbeSequenceCount(fieldAttributes) >= 0

    // A params parameter is recognised the same way the port's IsParamsParameter recognises it.
    concatTypes := new Type[](1)
    concatTypes[0] = typeof(string[])
    concat := typeof(string).GetMethod("Concat", concatTypes)
    if concat == null {
        throw new InvalidOperationException("String.Concat(string[]) was not found.")
    }

    paramsParameter := concat.GetParameters()[0]
    paramsAttributes := paramsParameter.GetCustomAttributesData()
    paramsCount := NullabilityProbeSequenceCount(paramsAttributes)
    seenParamArray := false
    paramsIndex := 0
    while paramsIndex < paramsCount {
        paramsAttribute := paramsAttributes.get_Item(paramsIndex)
        paramsAttributeType := paramsAttribute.get_AttributeType()
        if paramsAttributeType.FullName == "System.ParamArrayAttribute" {
            seenParamArray = true
        }

        paramsIndex = paramsIndex + 1
    }

    assert seenParamArray
}

// ---------------------------------------------------------------------------------------------
// The owner's own contracts. Everything above pins the CAPABILITY (that the reflection surface
// binds and executes); everything below pins `NullabilityMetadataReflection`'s BEHAVIOUR, which is
// the reader the analyzer, the code-intelligence service and the completion engine all consume.
// ---------------------------------------------------------------------------------------------

func NullabilityRenderTypeInfo(typeInfo: TypeInfo?): string {
    if typeInfo == null {
        return "<null>"
    }

    simple := typeInfo as SimpleTypeInfo
    if simple != null {
        return "Simple(" + simple.Name + ")"
    }

    nullable := typeInfo as NullableTypeInfo
    if nullable != null {
        return "Nullable(" + NullabilityRenderTypeInfo(nullable.InnerType) + ")"
    }

    oblivious := typeInfo as ObliviousTypeInfo
    if oblivious != null {
        return "Oblivious(" + NullabilityRenderTypeInfo(oblivious.InnerType) + ")"
    }

    array := typeInfo as ArrayTypeInfo
    if array != null {
        return "Array(" + NullabilityRenderTypeInfo(array.ElementType) + ")"
    }

    generic := typeInfo as GenericTypeInfo
    if generic != null {
        rendered := "Generic(" + generic.Name + ";def="
            + NullabilityRenderTypeInfo(generic.GenericDefinition) + ";["
        index := 0
        while index < generic.TypeArguments.Count {
            if index > 0 {
                rendered = rendered + ","
            }

            rendered = rendered + NullabilityRenderTypeInfo(generic.TypeArguments[index])
            index = index + 1
        }

        return rendered + "])"
    }

    reflection := typeInfo as ReflectionTypeInfo
    if reflection != null {
        return "Reflection(" + reflection.Type.Name + ")"
    }

    return "Other"
}

func NullabilityMethodByParameterType(owner: Type, methodName: string, parameterType: Type): MethodInfo {
    parameterTypes := new Type[](1)
    parameterTypes[0] = parameterType
    method := owner.GetMethod(methodName, parameterTypes)
    if method == null {
        throw new InvalidOperationException(methodName + " was not found.")
    }

    return method
}

test "the reader maps the CLR built-ins onto the N# simple types" {
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(int))) == "Simple(int)"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(long))) == "Simple(long)"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(bool))) == "Simple(bool)"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(double))) == "Simple(double)"

    // A reference built-in has no annotation of its own when it is asked for as a bare Type, so it
    // comes back OBLIVIOUS rather than not-null. That distinction is the whole point of the wrapper.
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(string))) == "Oblivious(Simple(string))"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(object))) == "Oblivious(Simple(object))"

    // A value type can never carry reference nullability, so it is never wrapped.
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(char))) == "Simple(char)"
}

test "a nullable value type becomes a nullable over its underlying type, not an oblivious one" {
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(int?))) == "Nullable(Simple(int))"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(long?))) == "Nullable(Simple(long))"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(bool?))) == "Nullable(Simple(bool))"
}

test "an array converts element-first and every reference layer carries its own read state" {
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(string[])))
        == "Oblivious(Array(Oblivious(Simple(string))))"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(int[])))
        == "Oblivious(Array(Simple(int)))"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(int?[])))
        == "Oblivious(Array(Nullable(Simple(int))))"
}

test "a closed generic keeps its stripped name, its converted arguments and its definition" {
    dictionaryDefinition := Type.GetType(
        "System.Collections.Generic.Dictionary`2, System.Private.CoreLib")
    if dictionaryDefinition == null {
        throw new InvalidOperationException("Dictionary`2 was not found.")
    }

    closedArguments := new Type[](2)
    closedArguments[0] = typeof(string)
    closedArguments[1] = typeof(int)
    closed := dictionaryDefinition.MakeGenericType(closedArguments)

    converted := NullabilityMetadataReflection.ConvertType(closed)
    assert NullabilityRenderTypeInfo(converted)
        == "Oblivious(Generic(Dictionary;def=Reflection(Dictionary`2);[Oblivious(Simple(string)),Simple(int)]))"
}

func NullabilityStringComparisonType(): Type {
    // `typeof` over an external enum is off the columnar surface; the canonical identity is.
    resolved := Type.GetType("System.StringComparison, System.Private.CoreLib")
    if resolved == null {
        throw new InvalidOperationException("System.StringComparison was not found.")
    }

    return resolved
}

test "an unmodelled CLR type stays a reflection type rather than becoming a simple name" {
    comparisonType := NullabilityStringComparisonType()
    converted := NullabilityMetadataReflection.ConvertType(comparisonType)
    reflection := converted as ReflectionTypeInfo
    assert reflection != null
    assert reflection.Type == comparisonType
}

test "a generic parameter without an override becomes a simple type named after it" {
    listDefinition := Type.GetType("System.Collections.Generic.List`1, System.Private.CoreLib")
    if listDefinition == null {
        throw new InvalidOperationException("List`1 was not found.")
    }

    parameter := listDefinition.GetGenericArguments()[0]
    assert parameter.get_IsGenericParameter()
    // An unconstrained parameter CAN carry reference nullability and has no annotation of its own,
    // so it comes back oblivious — the same treatment `string` gets.
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(parameter))
        == "Oblivious(Simple(T))"
}

test "a by-ref type is stripped before the walk sees it" {
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(int).MakeByRefType()))
        == "Simple(int)"
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertType(typeof(string).MakeByRefType()))
        == "Oblivious(Simple(string))"
}

test "the CLR display form renders aliases, arrays and generics" {
    assert NullabilityMetadataReflection.FormatType(typeof(int)) == "int"
    assert NullabilityMetadataReflection.FormatType(typeof(string)) == "string!"
    assert NullabilityMetadataReflection.FormatType(NullabilityStringComparisonType()) == "StringComparison"

    dictionaryDefinition := Type.GetType(
        "System.Collections.Generic.Dictionary`2, System.Private.CoreLib")
    if dictionaryDefinition == null {
        throw new InvalidOperationException("Dictionary`2 was not found.")
    }

    closedArguments := new Type[](2)
    closedArguments[0] = typeof(string)
    closedArguments[1] = typeof(int)
    closed := dictionaryDefinition.MakeGenericType(closedArguments)
    reflectionTypeInfo: TypeInfo = new ReflectionTypeInfo(closed)
    assert NullabilityMetadataReflection.FormatTypeInfo(reflectionTypeInfo) == "Dictionary<string, int>"

    // A generic PARAMETER renders as its bare name and an array of it composes.
    listDefinition := Type.GetType("System.Collections.Generic.List`1, System.Private.CoreLib")
    if listDefinition == null {
        throw new InvalidOperationException("List`1 was not found.")
    }

    parameterTypeInfo: TypeInfo = new ReflectionTypeInfo(listDefinition.GetGenericArguments()[0])
    assert NullabilityMetadataReflection.FormatTypeInfo(parameterTypeInfo) == "T"
}

test "a nullable annotation on a real BCL parameter reaches the converted type" {
    nullableParameter := NullabilityProbeStringParameter("IsNullOrEmpty")
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertParameter(nullableParameter))
        == "Nullable(Simple(string))"

    notNullParameter := NullabilityProbeStringParameter("Contains")
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertParameter(notNullParameter))
        == "Simple(string)"
}

test "flow attributes are formatted ahead of the parameter modifier" {
    nullableParameter := NullabilityProbeStringParameter("IsNullOrEmpty")
    assert NullabilityMetadataReflection.FormatParameter(nullableParameter)
        == "[NotNullWhen(false)] string? value"

    dictionaryDefinition := Type.GetType(
        "System.Collections.Generic.Dictionary`2, System.Private.CoreLib")
    if dictionaryDefinition == null {
        throw new InvalidOperationException("Dictionary`2 was not found.")
    }

    closedArguments := new Type[](2)
    closedArguments[0] = typeof(string)
    closedArguments[1] = typeof(string)
    closedDictionary := dictionaryDefinition.MakeGenericType(closedArguments)
    tryGetValue := closedDictionary.GetMethod("TryGetValue")
    if tryGetValue == null {
        throw new InvalidOperationException("Dictionary.TryGetValue was not found.")
    }

    // `out` renders its modifier, and the value is nullable on the way out. `MaybeNullWhen` is
    // deliberately NOT one of the four recognised flow attributes, so it contributes no prefix.
    outParameter := tryGetValue.GetParameters()[1]
    assert NullabilityMetadataReflection.FormatParameter(outParameter) == "out string? value"
    assert NullabilityMetadataReflection.FormatParameter(tryGetValue.GetParameters()[0]) == "string key"
}

test "a params parameter is recognised through its attribute, not its array shape" {
    concat := NullabilityMethodByParameterType(typeof(string), "Concat", typeof(string[]))
    paramsParameter := concat.GetParameters()[0]
    assert NullabilityMetadataReflection.FormatParameter(paramsParameter) == "params string?[] values"

    // An array parameter in a NON-params position keeps no modifier — the recognition is the
    // attribute, not the array shape.
    joinTypes := new Type[](4)
    joinTypes[0] = typeof(char)
    joinTypes[1] = typeof(string[])
    joinTypes[2] = typeof(int)
    joinTypes[3] = typeof(int)
    plainArrayMethod := typeof(string).GetMethod("Join", joinTypes)
    if plainArrayMethod == null {
        throw new InvalidOperationException("String.Join(char, string[], int, int) was not found.")
    }

    plainArrayParameter := plainArrayMethod.GetParameters()[1]
    assert !NullabilityMetadataReflection.FormatParameter(plainArrayParameter).StartsWith("params ")
}

test "properties, fields and returns all read through the same walk" {
    lengthProperty := typeof(string).GetProperty("Length")
    if lengthProperty == null {
        throw new InvalidOperationException("String.Length was not found.")
    }

    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertProperty(lengthProperty))
        == "Simple(int)"

    emptyField := typeof(string).GetField("Empty")
    if emptyField == null {
        throw new InvalidOperationException("String.Empty was not found.")
    }

    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertField(emptyField))
        == "Simple(string)"

    trimTypes := new Type[](0)
    trim := typeof(string).GetMethod("Trim", trimTypes)
    if trim == null {
        throw new InvalidOperationException("String.Trim() was not found.")
    }

    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertReturn(trim)) == "Simple(string)"
    assert NullabilityMetadataReflection.FormatReturnType(trim) == "string"
}

test "a reflection type override answers for a generic parameter, by TypeInfo and by CLR binding" {
    listDefinition := Type.GetType("System.Collections.Generic.List`1, System.Private.CoreLib")
    if listDefinition == null {
        throw new InvalidOperationException("List`1 was not found.")
    }

    genericParameter := listDefinition.GetGenericArguments()[0]
    addTypes := new Type[](1)
    addTypes[0] = genericParameter
    add := listDefinition.GetMethod("Add", addTypes)
    if add == null {
        throw new InvalidOperationException("List<T>.Add was not found.")
    }

    parameter := add.GetParameters()[0]

    // With no override at all the walk names the parameter itself, under the read state its
    // metadata carries.
    assert NullabilityRenderTypeInfo(NullabilityMetadataReflection.ConvertParameter(parameter))
        == "Nullable(Simple(T))"

    // A TypeInfo binding replaces the conversion outright — INCLUDING the wrapper, because the
    // generic-parameter override answers ahead of the read state rather than under it.
    typeInfoOverrides := new Dictionary<Type, TypeInfo>()
    replacement: TypeInfo = new SimpleTypeInfo("OVR:T")
    typeInfoOverrides[genericParameter] = replacement
    answering := AnalyzerReflectionTypeOverride.Direct(typeInfoOverrides, null)
    assert NullabilityRenderTypeInfo(
        NullabilityMetadataReflection.ConvertParameterWithOverride(parameter, answering))
        == "Simple(OVR:T)"

    // A CLR binding answers too, and it answers with the CONVERTED runtime type rather than with a
    // reflected one — `int` comes back as the built-in.
    clrBindings := new Dictionary<Type, Type>()
    clrBindings[genericParameter] = typeof(int)
    emptyTypeInfoOverrides := new Dictionary<Type, TypeInfo>()
    bound := AnalyzerReflectionTypeOverride.Direct(emptyTypeInfoOverrides, clrBindings)
    assert NullabilityRenderTypeInfo(
        NullabilityMetadataReflection.ConvertParameterWithOverride(parameter, bound))
        == "Simple(int)"

    // AN EMPTY OVERRIDE IS NOT "NO OVERRIDE". It still ANSWERS — with the plain conversion, which
    // reads an unbound generic parameter as a REFLECTED type rather than as the walk's named one.
    // This is the C# lambda's behaviour exactly, and pinning it is what keeps "the override never
    // declines" honest.
    noBindings := new Dictionary<Type, Type>()
    emptyOverride := AnalyzerReflectionTypeOverride.Direct(emptyTypeInfoOverrides, noBindings)
    emptyRender := NullabilityRenderTypeInfo(
        NullabilityMetadataReflection.ConvertParameterWithOverride(parameter, emptyOverride))
    assert emptyRender == "Reflection(T)"

    // The override is consulted at the LEAF too — a non-generic position routes through it and
    // comes back with the plain conversion, so a bound override changes nothing there.
    notNullParameter := NullabilityProbeStringParameter("Contains")
    assert NullabilityRenderTypeInfo(
        NullabilityMetadataReflection.ConvertParameterWithOverride(notNullParameter, answering))
        == "Simple(string)"
    assert NullabilityRenderTypeInfo(
        NullabilityMetadataReflection.ConvertParameter(notNullParameter))
        == "Simple(string)"
}

test "the display form and the metadata stripper agree with the N#-owned half" {
    obliviousString: TypeInfo = new ObliviousTypeInfo(new ObliviousTypeInfo(BuiltInTypes.String))
    stripped := NullabilityMetadataReflection.StripMetadata(obliviousString)
    assert NullabilityRenderTypeInfo(stripped) == "Simple(string)"

    // An N#-owned TypeInfo never goes through the CLR display form.
    genericArguments := new List<TypeInfo>()
    genericArguments.Add(BuiltInTypes.String)
    listTypeInfo: TypeInfo = new GenericTypeInfo("List", genericArguments)
    assert NullabilityMetadataReflection.FormatTypeInfo(listTypeInfo) == "List<string>"

    // A shape the N# display half declines to render falls back to the reader's own formatting
    // rather than producing nothing.
    // (`newtype` is a reserved word, so the local cannot be spelled that way.)
    userId: TypeInfo = new NewtypeInfo("UserId", new SimpleTypeReference("int"))
    assert NullabilityTypeDisplay.TryFormatTypeInfo(userId) == null
    assert NullabilityMetadataReflection.FormatTypeInfo(userId) == "UserId"
}
