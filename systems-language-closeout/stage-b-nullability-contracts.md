# Stage-B contracts — the reflected-nullability member surface

Task 017 slice 12 **stage A** landed the capability (the catalog rows in
`src/NSharpLang.Compiler.BootstrapServices/ColumnarExternalBindingPlans.nl`). This file holds the
contracts that EXERCISE it, staged here rather than in the project because of the bootstrap wall:
the packaged 0.1.0 toolset that builds `NSharpLang.Compiler.BootstrapServices` carries its own
snapshot of that catalog, so until it is repacked these contracts fail to compile at
`emit.declaration.method-return: 'NullabilityInfoContext' could not be resolved` — the exact decline
slice 11 recorded. A `.tests.nl` in the project would therefore break the contracts gate; a staged
`.nl`-suffixed file trips the ownership audit's `OWN009` (unknown product-adjacent file type). A
closeout `.md` is the one home that perturbs neither.

**Every contract below was verified in stage A to COMPILE AND PASS (7 / 7) against a freshly built
compiler**, which links a freshly built `BootstrapServices` and is therefore behaviourally the
post-repin toolset. An activation failure means the repin did not take, not that the shapes are
wrong.

## To activate (stage B, after the toolset repin)

1. Pack and install the SDK so the packaged toolset carries the new catalog rows.
2. Copy the block below to
   `src/NSharpLang.Compiler.BootstrapServices/NullabilityMetadataReflection.tests.nl`.
3. `dotnet test src/NSharpLang.Compiler.BootstrapServices -c Release -p:NSharpExcludeTests=false`
   (expect 1,726 + 7 = 1,733).
4. Delete this file once the contracts live in the project.

## What it pins

The whole external member surface `NullabilityMetadata.cs`'s reflection half needs. Nothing here is
a plan lookup: every member binds through the ordinary runtime direct-call resolver once its owning
type is on the columnar surface, which is the finding that kept the capability change to type rows
alone.

Three shape rules the port must keep (each one cost a decline before it was found):

- `new NullabilityInfoContext()` does not emit — the emitter's `new` chain is a name table that does
  not model this type. Construct it through `typeof(T).GetConstructor(...)` + `ConstructorInfo.Invoke`,
  the idiom `ExternalAssemblyScan.CreateMetadataLoadContext` already uses. The `object[]` argument
  array must be declared `object?[]`, or the analyzer refuses the `Invoke` overload.
- `GetCustomAttributesData()` / `ConstructorArguments` answer a closed `IList<T>`. Its `get_Item(int)`
  binds directly, but `Count` lives on `ICollection<T>` and an interface receiver's own member lookup
  reaches neither it nor `foreach`. Bind the sequence through an `object` local and read the
  non-generic `IList.Count`.
- A boxed `CustomAttributeTypedArgument.Value` cannot be unboxed with a cast, an `as`, or an
  `is` test. Compare it against a boxed constant with `Equals`.

```nsharp
namespace NSharpLang.Compiler

import System
import System.Collections
import System.Reflection

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
```
