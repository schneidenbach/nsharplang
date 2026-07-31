namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection

// The reflection half of the nullability metadata reader. `NullabilityMetadataCore` already owns
// every decision that is a pure function of facts; this class owns the READING of those facts off
// CLR reflection — the `NullabilityInfoContext` walk, the `CustomAttributeData` scan and the CLR
// display form — and composes the two.
//
// Shape notes, all measured rather than assumed (see STATUS.md's slice-12 record):
//   * `new NullabilityInfoContext()` is not on the emitter's `new` chain, so the context is built
//     through its reflected constructor with an `object?[]` argument array.
//   * `GetCustomAttributesData()` and `ConstructorArguments` answer a closed `IList<T>`, whose
//     `Count` lives on `ICollection<T>` and is therefore invisible to a generic-interface receiver.
//     `SequenceCount` routes through an `object` local and the non-generic `IList` instead.
//   * A boxed value cannot be unboxed, so the `[NotNullWhen(...)]` argument is compared against a
//     boxed constant.
//
// THE TYPE OVERRIDE IS DATA, NOT A FUNCTION. A caller that needs some positions answered with the N#
// types a call site supplied hands in an `AnalyzerReflectionTypeOverride` — the bindings themselves —
// so nothing crosses a boundary and the override always ANSWERS rather than declining. (Slice 12B
// carried it as `Func<Type, object>` because the conversion it composed with was still C#; with that
// conversion N#-owned there is no boundary left to encode.)
public class NullabilityMetadataReflection {
    public static func ConvertType(clrType: Type): TypeInfo {
        return ConvertReflectedType(clrType, null, null)
    }

    // The C# original accepted a type override here too; no caller in `src/`, `tests/` or
    // `editors/` ever passed one (measured at this tree), so the dead arm did not come across.
    public static func ConvertProperty(property: PropertyInfo): TypeInfo {
        converted := ConvertReflectedType(
            property.get_PropertyType(),
            CreateNullabilityInfoForProperty(property),
            null)
        return ApplyFlowAttributes(converted, property.GetCustomAttributesData())
    }

    public static func ConvertField(field: FieldInfo): TypeInfo {
        converted := ConvertReflectedType(
            field.get_FieldType(),
            CreateNullabilityInfoForField(field),
            null)
        return ApplyFlowAttributes(converted, field.GetCustomAttributesData())
    }

    public static func ConvertParameter(parameter: ParameterInfo): TypeInfo {
        return ConvertParameterWithOverride(parameter, null)
    }

    public static func ConvertParameterWithOverride(
        parameter: ParameterInfo,
        typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        converted := ConvertReflectedType(
            parameter.get_ParameterType(),
            CreateNullabilityInfoForParameter(parameter),
            typeOverride)
        return ApplyFlowAttributes(converted, parameter.GetCustomAttributesData())
    }

    public static func ConvertReturn(method: MethodInfo): TypeInfo {
        return ConvertReturnWithOverride(method, null)
    }

    public static func ConvertReturnWithOverride(
        method: MethodInfo,
        typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        returnParameter := method.get_ReturnParameter()
        converted := ConvertReflectedType(
            method.get_ReturnType(),
            CreateNullabilityInfoForParameter(returnParameter),
            typeOverride)
        return ApplyFlowAttributes(converted, returnParameter.GetCustomAttributesData())
    }

    public static func FormatType(clrType: Type): string {
        return FormatTypeInfo(ConvertType(clrType))
    }

    public static func FormatParameter(parameter: ParameterInfo): string {
        attributePrefix := FormatFlowAttributes(parameter.GetCustomAttributesData())
        typeName := FormatTypeInfo(ConvertParameter(parameter))
        parameterType := parameter.get_ParameterType()
        return NullabilityMetadataCore.FormatParameter(
            parameter.get_IsOut(),
            parameterType.get_IsByRef(),
            IsParamsParameter(parameter),
            attributePrefix,
            typeName,
            parameter.get_Name())
    }

    public static func FormatReturnType(method: MethodInfo): string {
        return FormatTypeInfo(ConvertReturn(method))
    }

    public static func FormatTypeInfo(typeInfo: TypeInfo): string {
        reflection := typeInfo as ReflectionTypeInfo
        if reflection != null {
            return FormatClrTypeName(reflection.Type)
        }

        return NullabilityMetadataCore.FormatTypeInfo(typeInfo)
    }

    public static func StripMetadata(typeInfo: TypeInfo): TypeInfo {
        return NullabilityMetadataCore.StripMetadata(typeInfo)
    }

    static func ConvertReflectedType(
        clrType: Type,
        nullabilityInfo: NullabilityInfo?,
        typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        effectiveType := clrType
        if clrType.get_IsByRef() {
            element := clrType.GetElementType()
            if element != null {
                effectiveType = element
            }
        }

        if effectiveType.get_IsGenericParameter() && typeOverride != null {
            return typeOverride.Answer(effectiveType)
        }

        converted := ConvertReflectedTypeCore(effectiveType, nullabilityInfo, typeOverride)
        readState := GetReadState(nullabilityInfo)
        return NullabilityMetadataCore.ApplyReadState(
            converted,
            IsNullableValueType(effectiveType),
            CanReflectedTypeCarryReferenceNullability(effectiveType, converted),
            readState == NullabilityState.Nullable,
            readState == NullabilityState.Unknown)
    }

    static func ConvertReflectedTypeCore(
        clrType: Type,
        nullabilityInfo: NullabilityInfo?,
        typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        if clrType.get_IsByRef() {
            byRefElement := clrType.GetElementType()
            if byRefElement != null {
                return ConvertReflectedType(byRefElement, nullabilityInfo, typeOverride)
            }
        }

        if IsNullableValueType(clrType) {
            underlying := Nullable.GetUnderlyingType(clrType)
            if underlying != null {
                nullable: TypeInfo = new NullableTypeInfo(
                    ConvertReflectedType(
                        underlying,
                        GetFirstGenericArgument(nullabilityInfo),
                        typeOverride))
                return nullable
            }
        }

        if clrType.get_IsArray() {
            elementType := clrType.GetElementType()
            if elementType != null {
                array: TypeInfo = new ArrayTypeInfo(
                    ConvertReflectedType(elementType, GetElementNullability(nullabilityInfo), typeOverride))
                return array
            }
        }

        if clrType.get_IsGenericParameter() {
            if typeOverride != null {
                return typeOverride.Answer(clrType)
            }

            genericParameter: TypeInfo = new SimpleTypeInfo(clrType.Name)
            return genericParameter
        }

        if clrType.get_IsGenericType() {
            name := NullabilityMetadataCore.StripClrGenericArity(clrType.Name)
            typeArguments := clrType.GetGenericArguments()
            nullabilityArguments := GetGenericNullabilityArguments(nullabilityInfo)
            convertedArguments := new List<TypeInfo>()
            index := 0
            while index < typeArguments.Length {
                argumentNullability: NullabilityInfo? = null
                if index < nullabilityArguments.Length {
                    argumentNullability = nullabilityArguments[index]
                }

                convertedArguments.Add(
                    ConvertReflectedType(typeArguments[index], argumentNullability, typeOverride))
                index = index + 1
            }

            constructed: TypeInfo = ReflectionTypeInfoFactory.FromConstructedGeneric(
                name,
                convertedArguments,
                clrType)
            return constructed
        }

        if typeOverride != null {
            return typeOverride.Answer(clrType)
        }

        builtIn := NullabilityMetadataCore.ConvertBuiltInType(clrType.FullName)
        if builtIn != null {
            return builtIn
        }

        reflected: TypeInfo = new ReflectionTypeInfo(clrType)
        return reflected
    }

    static func ApplyFlowAttributes(typeInfo: TypeInfo, attributes: IList<CustomAttributeData>): TypeInfo {
        return NullabilityMetadataCore.ApplyFlowAttributeFacts(
            typeInfo,
            HasAttributeKind(attributes, NullabilityMetadataCore.GetMaybeNullAttributeKind()),
            HasAttributeKind(attributes, NullabilityMetadataCore.GetNotNullAttributeKind()))
    }

    // `NullabilityInfoContext` caches per instance, and the C# original built a fresh one per
    // request; keeping that exactly preserves the observed answers as well as the cost profile.
    static func CreateNullabilityContext(): NullabilityInfoContext {
        parameterTypes := new Type[](0)
        constructor := typeof(NullabilityInfoContext).GetConstructor(parameterTypes)
        if constructor == null {
            throw new InvalidOperationException("NullabilityInfoContext() was not found.")
        }

        arguments := new object?[](0)
        return (NullabilityInfoContext)constructor.Invoke(arguments)
    }

    static func CreateNullabilityInfoForProperty(property: PropertyInfo): NullabilityInfo? {
        context := CreateNullabilityContext()
        return context.Create(property)
    }

    static func CreateNullabilityInfoForField(field: FieldInfo): NullabilityInfo? {
        context := CreateNullabilityContext()
        return context.Create(field)
    }

    static func CreateNullabilityInfoForParameter(parameter: ParameterInfo): NullabilityInfo? {
        context := CreateNullabilityContext()
        return context.Create(parameter)
    }

    static func GetElementNullability(info: NullabilityInfo?): NullabilityInfo? {
        if info == null {
            return null
        }

        return info.get_ElementType()
    }

    static func GetGenericNullabilityArguments(info: NullabilityInfo?): NullabilityInfo[] {
        if info == null {
            return new NullabilityInfo[](0)
        }

        arguments := info.get_GenericTypeArguments()
        if arguments == null {
            return new NullabilityInfo[](0)
        }

        return arguments
    }

    static func GetFirstGenericArgument(info: NullabilityInfo?): NullabilityInfo? {
        arguments := GetGenericNullabilityArguments(info)
        if arguments.Length == 0 {
            return null
        }

        return arguments[0]
    }

    static func GetReadState(nullabilityInfo: NullabilityInfo?): NullabilityState {
        if nullabilityInfo == null {
            return NullabilityState.Unknown
        }

        return nullabilityInfo.get_ReadState()
    }

    static func CanReflectedTypeCarryReferenceNullability(clrType: Type, converted: TypeInfo): bool {
        return NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(
            clrType.get_IsGenericParameter(),
            clrType.get_IsValueType(),
            CanConvertedTypeCarryReferenceNullability(converted))
    }

    static func CanConvertedTypeCarryReferenceNullability(typeInfo: TypeInfo): bool {
        reflection := typeInfo as ReflectionTypeInfo
        if reflection != null {
            reflectedType := reflection.Type
            return !reflectedType.get_IsValueType()
        }

        return NullabilityMetadataCore.CanCarryReferenceNullability(typeInfo)
    }

    static func IsNullableValueType(clrType: Type): bool {
        return Nullable.GetUnderlyingType(clrType) != null
    }

    // `Count` is declared on `ICollection<T>`, which a generic-interface receiver's own member
    // lookup does not reach; the non-generic `IList` reached through an `object` local is the same
    // instance and the same value.
    static func SequenceCount(sequence: object): int {
        list := (IList)sequence
        return list.Count
    }

    static func HasAttributeKind(attributes: IList<CustomAttributeData>, attributeKind: int): bool {
        count := SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.get_AttributeType()
            if NullabilityMetadataCore.GetFlowAttributeKind(attributeType.FullName) == attributeKind {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func IsParamsParameter(parameter: ParameterInfo): bool {
        return HasAttributeKind(
            parameter.GetCustomAttributesData(),
            NullabilityMetadataCore.GetParamArrayAttributeKind())
    }

    static func FormatFlowAttributes(attributes: IList<CustomAttributeData>): string {
        hasNotNullWhen := false
        notNullWhenValue := false
        hasMaybeNull := false
        hasNotNull := false
        falseValue: object = false
        trueValue: object = true

        count := SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.get_AttributeType()
            attributeKind := NullabilityMetadataCore.GetFlowAttributeKind(attributeType.FullName)
            handled := false
            if attributeKind == NullabilityMetadataCore.GetNotNullWhenAttributeKind() {
                constructorArguments := attribute.get_ConstructorArguments()
                if SequenceCount(constructorArguments) == 1 {
                    argument := constructorArguments.get_Item(0)
                    argumentValue := argument.get_Value()
                    boxedValue: object = argumentValue ?? falseValue
                    // `is bool` over a boxed value: only a boxed bool equals a boxed bool, and the
                    // argument's own `ArgumentType` is NOT usable here — under a
                    // MetadataLoadContext it is a PROJECTED `System.Boolean` that is not
                    // `typeof(bool)`, while `Value` is still a live boxed CLR bool.
                    isTrue := argumentValue != null && boxedValue.Equals(trueValue)
                    isFalse := argumentValue != null && boxedValue.Equals(falseValue)
                    if isTrue || isFalse {
                        hasNotNullWhen = true
                        notNullWhenValue = isTrue
                        handled = true
                    }
                }
            }

            if !handled {
                if attributeKind == NullabilityMetadataCore.GetMaybeNullAttributeKind() {
                    hasMaybeNull = true
                } else if attributeKind == NullabilityMetadataCore.GetNotNullAttributeKind() {
                    hasNotNull = true
                }
            }

            index = index + 1
        }

        return NullabilityMetadataCore.FormatFlowAttributePrefix(
            hasNotNullWhen,
            notNullWhenValue,
            hasMaybeNull,
            hasNotNull)
    }

    static func FormatClrTypeName(clrType: Type): string {
        if clrType.get_IsGenericParameter() {
            return clrType.Name
        }

        if clrType.get_IsByRef() {
            byRefElement := clrType.GetElementType()
            if byRefElement != null {
                return FormatClrTypeName(byRefElement)
            }
        }

        if clrType.get_IsArray() {
            elementType := clrType.GetElementType()
            if elementType != null {
                return NullabilityMetadataCore.FormatArrayClrTypeName(FormatClrTypeName(elementType))
            }
        }

        if clrType.get_IsGenericType() {
            name := NullabilityMetadataCore.StripClrGenericArity(clrType.Name)
            typeArguments := clrType.GetGenericArguments()
            formattedArguments := new string[](typeArguments.Length)
            index := 0
            while index < typeArguments.Length {
                formattedArguments[index] = FormatClrTypeName(typeArguments[index])
                index = index + 1
            }

            return NullabilityMetadataCore.FormatGenericClrTypeName(name, formattedArguments)
        }

        return NullabilityMetadataCore.FormatSimpleClrTypeName(clrType.Name)
    }
}
