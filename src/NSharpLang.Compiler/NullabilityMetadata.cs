using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace NSharpLang.Compiler;

public static class NullabilityMetadata
{
    public static TypeInfo ConvertType(Type type)
        => ConvertType(type, null, null);

    public static TypeInfo ConvertType(Type type, Func<Type, TypeInfo>? typeOverride)
        => ConvertType(type, null, typeOverride);

    public static TypeInfo ConvertProperty(PropertyInfo property, Func<Type, TypeInfo>? typeOverride = null)
        => ApplyFlowAttributes(
            ConvertType(property.PropertyType, TryCreateNullabilityInfo(property), typeOverride),
            property.GetCustomAttributesData());

    public static TypeInfo ConvertField(FieldInfo field, Func<Type, TypeInfo>? typeOverride = null)
        => ApplyFlowAttributes(
            ConvertType(field.FieldType, TryCreateNullabilityInfo(field), typeOverride),
            field.GetCustomAttributesData());

    public static TypeInfo ConvertParameter(ParameterInfo parameter, Func<Type, TypeInfo>? typeOverride = null)
        => ApplyFlowAttributes(
            ConvertType(parameter.ParameterType, TryCreateNullabilityInfo(parameter), typeOverride),
            parameter.GetCustomAttributesData());

    public static TypeInfo ConvertReturn(MethodInfo method, Func<Type, TypeInfo>? typeOverride = null)
        => ApplyFlowAttributes(
            ConvertType(method.ReturnType, TryCreateNullabilityInfo(method.ReturnParameter), typeOverride),
            method.ReturnParameter.GetCustomAttributesData());

    public static string FormatType(Type type)
        => FormatTypeInfo(ConvertType(type));

    public static string FormatParameter(ParameterInfo parameter)
    {
        var attributePrefix = FormatFlowAttributes(parameter.GetCustomAttributesData());
        var type = FormatTypeInfo(ConvertParameter(parameter));
        return NullabilityMetadataCore.FormatParameter(
            parameter.IsOut,
            parameter.ParameterType.IsByRef,
            IsParamsParameter(parameter),
            attributePrefix,
            type,
            parameter.Name);
    }

    public static string FormatReturnType(MethodInfo method)
        => FormatTypeInfo(ConvertReturn(method));

    public static string FormatTypeInfo(TypeInfo typeInfo)
    {
        if (typeInfo is ReflectionTypeInfo reflection)
            return FormatClrTypeName(reflection.Type);

        return NullabilityMetadataCore.FormatTypeInfo(typeInfo);
    }

    public static TypeInfo StripMetadata(TypeInfo typeInfo)
        => NullabilityMetadataCore.StripMetadata(typeInfo);

    private static TypeInfo ConvertType(
        Type type,
        NullabilityInfo? nullabilityInfo,
        Func<Type, TypeInfo>? typeOverride)
    {
        var effectiveType = type.IsByRef ? type.GetElementType()! : type;
        if (effectiveType.IsGenericParameter && typeOverride?.Invoke(effectiveType) is { } overriddenGenericType)
            return overriddenGenericType;

        var converted = ConvertTypeCore(effectiveType, nullabilityInfo, typeOverride);
        var readState = GetReadState(nullabilityInfo);
        return NullabilityMetadataCore.ApplyReadState(
            converted,
            IsNullableValueType(effectiveType),
            CanCarryReferenceNullability(effectiveType, converted),
            readState == NullabilityState.Nullable,
            readState == NullabilityState.Unknown);
    }

    private static TypeInfo ConvertTypeCore(
        Type type,
        NullabilityInfo? nullabilityInfo,
        Func<Type, TypeInfo>? typeOverride)
    {
        if (type.IsByRef)
            return ConvertType(type.GetElementType()!, nullabilityInfo, typeOverride);

        if (IsNullableValueType(type))
        {
            var underlying = Nullable.GetUnderlyingType(type)!;
            return new NullableTypeInfo(ConvertType(underlying, GetFirstGenericArgument(nullabilityInfo), typeOverride));
        }

        if (type.IsArray)
        {
            var elementType = type.GetElementType()!;
            return new ArrayTypeInfo(ConvertType(elementType, nullabilityInfo?.ElementType, typeOverride));
        }

        if (type.IsGenericParameter)
        {
            return typeOverride?.Invoke(type) ?? new SimpleTypeInfo(type.Name);
        }

        if (type.IsGenericType)
        {
            var name = NullabilityMetadataCore.StripClrGenericArity(type.Name);

            var typeArguments = type.GetGenericArguments();
            var nullabilityArguments = nullabilityInfo?.GenericTypeArguments ?? Array.Empty<NullabilityInfo>();
            var convertedArguments = new List<TypeInfo>(typeArguments.Length);
            for (var i = 0; i < typeArguments.Length; i++)
            {
                var argumentNullability = i < nullabilityArguments.Length ? nullabilityArguments[i] : null;
                convertedArguments.Add(ConvertType(typeArguments[i], argumentNullability, typeOverride));
            }

            return new GenericTypeInfo(name, convertedArguments);
        }

        var overridden = typeOverride?.Invoke(type);
        if (overridden != null)
            return overridden;

        return NullabilityMetadataCore.ConvertBuiltInType(type.FullName) ?? new ReflectionTypeInfo(type);
    }

    private static TypeInfo ApplyFlowAttributes(TypeInfo type, IEnumerable<CustomAttributeData> attributes)
    {
        return NullabilityMetadataCore.ApplyFlowAttributeFacts(
            type,
            HasAttributeKind(attributes, NullabilityMetadataCore.GetMaybeNullAttributeKind()),
            HasAttributeKind(attributes, NullabilityMetadataCore.GetNotNullAttributeKind()));
    }

    private static NullabilityInfo? TryCreateNullabilityInfo(PropertyInfo property)
    {
        return new NullabilityInfoContext().Create(property);
    }

    private static NullabilityInfo? TryCreateNullabilityInfo(FieldInfo field)
    {
        return new NullabilityInfoContext().Create(field);
    }

    private static NullabilityInfo? TryCreateNullabilityInfo(ParameterInfo parameter)
    {
        return new NullabilityInfoContext().Create(parameter);
    }

    private static NullabilityInfo? GetFirstGenericArgument(NullabilityInfo? info)
        => info?.GenericTypeArguments is { Length: > 0 } arguments ? arguments[0] : null;

    private static NullabilityState GetReadState(NullabilityInfo? nullabilityInfo)
        => nullabilityInfo?.ReadState ?? NullabilityState.Unknown;

    private static bool CanCarryReferenceNullability(Type type, TypeInfo converted)
    {
        return NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(
            type.IsGenericParameter,
            type.IsValueType,
            CanCarryReferenceNullability(converted));
    }

    private static bool CanCarryReferenceNullability(TypeInfo typeInfo)
    {
        if (typeInfo is ReflectionTypeInfo reflection)
            return !reflection.Type.IsValueType;

        return NullabilityMetadataCore.CanCarryReferenceNullability(typeInfo);
    }

    private static bool IsNullableValueType(Type type)
        => Nullable.GetUnderlyingType(type) != null;

    private static bool HasAttributeKind(IEnumerable<CustomAttributeData> attributes, int attributeKind)
    {
        foreach (var attribute in attributes)
        {
            if (NullabilityMetadataCore.GetFlowAttributeKind(attribute.AttributeType.FullName) == attributeKind)
                return true;
        }

        return false;
    }

    private static bool IsParamsParameter(ParameterInfo parameter)
    {
        return HasAttributeKind(parameter.GetCustomAttributesData(), NullabilityMetadataCore.GetParamArrayAttributeKind());
    }

    private static string FormatFlowAttributes(IEnumerable<CustomAttributeData> attributes)
    {
        var hasNotNullWhen = false;
        var notNullWhenValue = false;
        var hasMaybeNull = false;
        var hasNotNull = false;
        foreach (var attribute in attributes)
        {
            var attributeKind = NullabilityMetadataCore.GetFlowAttributeKind(attribute.AttributeType.FullName);
            if (attributeKind == NullabilityMetadataCore.GetNotNullWhenAttributeKind()
                && attribute.ConstructorArguments.Count == 1
                && attribute.ConstructorArguments[0].Value is bool when)
            {
                hasNotNullWhen = true;
                notNullWhenValue = when;
            }
            else if (attributeKind == NullabilityMetadataCore.GetMaybeNullAttributeKind())
            {
                hasMaybeNull = true;
            }
            else if (attributeKind == NullabilityMetadataCore.GetNotNullAttributeKind())
            {
                hasNotNull = true;
            }
        }

        return NullabilityMetadataCore.FormatFlowAttributePrefix(
            hasNotNullWhen,
            notNullWhenValue,
            hasMaybeNull,
            hasNotNull);
    }

    private static string FormatClrTypeName(Type type)
    {
        if (type.IsGenericParameter)
            return type.Name;

        if (type.IsByRef)
            return FormatClrTypeName(type.GetElementType()!);

        if (type.IsArray)
            return NullabilityMetadataCore.FormatArrayClrTypeName(FormatClrTypeName(type.GetElementType()!));

        if (type.IsGenericType)
        {
            var name = NullabilityMetadataCore.StripClrGenericArity(type.Name);
            return NullabilityMetadataCore.FormatGenericClrTypeName(
                name,
                type.GetGenericArguments().Select(FormatClrTypeName).ToArray());
        }

        return NullabilityMetadataCore.FormatSimpleClrTypeName(type.Name);
    }
}
