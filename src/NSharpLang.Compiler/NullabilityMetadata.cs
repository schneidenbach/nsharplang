using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace NSharpLang.Compiler;

public static class NullabilityMetadata
{
    private const string MaybeNullAttributeName = "System.Diagnostics.CodeAnalysis.MaybeNullAttribute";
    private const string NotNullAttributeName = "System.Diagnostics.CodeAnalysis.NotNullAttribute";
    private const string NotNullWhenAttributeName = "System.Diagnostics.CodeAnalysis.NotNullWhenAttribute";

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
        var modifier = parameter.IsOut
            ? "out "
            : parameter.ParameterType.IsByRef
                ? "ref "
                : IsParamsParameter(parameter)
                    ? "params "
                    : string.Empty;
        var attributePrefix = FormatFlowAttributes(parameter.GetCustomAttributesData());
        var type = FormatTypeInfo(ConvertParameter(parameter));
        return $"{attributePrefix}{modifier}{type} {parameter.Name}";
    }

    public static string FormatParameterType(ParameterInfo parameter)
        => FormatTypeInfo(ConvertParameter(parameter));

    public static string FormatReturnType(MethodInfo method)
        => FormatTypeInfo(ConvertReturn(method));

    public static string FormatPropertyType(PropertyInfo property)
        => FormatTypeInfo(ConvertProperty(property));

    public static string FormatFieldType(FieldInfo field)
        => FormatTypeInfo(ConvertField(field));

    public static string FormatTypeInfo(TypeInfo typeInfo) => typeInfo switch
    {
        SimpleTypeInfo s => s.Name,
        ClassTypeInfo c => c.Declaration.Name,
        StructTypeInfo s => s.Declaration.Name,
        RecordTypeInfo r => r.Declaration.Name,
        InterfaceTypeInfo i => i.Declaration.Name,
        EnumTypeInfo e => e.Declaration.Name,
        UnionTypeInfo { IsAnonymous: true } u => string.Join(" | ", u.Arms.Select(FormatTypeInfo)),
        UnionTypeInfo u => u.Declaration!.Name,
        NewtypeInfo n => n.Name,
        GenericTypeInfo g => $"{g.Name}<{string.Join(", ", g.TypeArguments.Select(FormatTypeInfo))}>",
        ArrayTypeInfo a => $"{FormatTypeInfo(a.ElementType)}[]",
        NullableTypeInfo n => $"{FormatTypeInfo(n.InnerType)}?",
        ObliviousTypeInfo o => $"{FormatTypeInfo(o.InnerType)}!",
        ReflectionTypeInfo r => FormatClrTypeName(r.Type),
        ExternalTypeInfo e => e.Name,
        FunctionTypeInfo f => FormatFunctionType(f),
        UnknownTypeInfo => "unknown",
        _ => typeInfo.ToString() ?? "unknown"
    };

    public static TypeInfo StripMetadata(TypeInfo typeInfo) => typeInfo switch
    {
        ObliviousTypeInfo oblivious => StripMetadata(oblivious.InnerType),
        _ => typeInfo
    };

    private static TypeInfo ConvertType(
        Type type,
        NullabilityInfo? nullabilityInfo,
        Func<Type, TypeInfo>? typeOverride)
    {
        var effectiveType = type.IsByRef ? type.GetElementType()! : type;
        if (effectiveType.IsGenericParameter && typeOverride?.Invoke(effectiveType) is { } overriddenGenericType)
            return overriddenGenericType;

        var converted = ConvertTypeCore(effectiveType, nullabilityInfo, typeOverride);

        if (IsNullableValueType(effectiveType))
            return converted;

        if (!CanCarryReferenceNullability(effectiveType, converted))
            return converted;

        return GetReadState(nullabilityInfo) switch
        {
            NullabilityState.Nullable => EnsureNullable(converted),
            NullabilityState.Unknown => EnsureOblivious(converted),
            _ => converted
        };
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
            var name = type.Name;
            var tickIndex = name.IndexOf('`', StringComparison.Ordinal);
            if (tickIndex >= 0)
                name = name[..tickIndex];

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

        return type.FullName switch
        {
            "System.Int32" => BuiltInTypes.Int,
            "System.Int64" => BuiltInTypes.Long,
            "System.Single" => BuiltInTypes.Float,
            "System.Double" => BuiltInTypes.Double,
            "System.Decimal" => BuiltInTypes.Decimal,
            "System.Byte" => BuiltInTypes.Byte,
            "System.SByte" => BuiltInTypes.SByte,
            "System.Int16" => BuiltInTypes.Short,
            "System.UInt16" => BuiltInTypes.UShort,
            "System.UInt32" => BuiltInTypes.UInt,
            "System.UInt64" => BuiltInTypes.ULong,
            "System.Char" => BuiltInTypes.Char,
            "System.Boolean" => BuiltInTypes.Bool,
            "System.String" => BuiltInTypes.String,
            "System.Void" => BuiltInTypes.Void,
            "System.Object" => BuiltInTypes.Object,
            _ => new ReflectionTypeInfo(type)
        };
    }

    private static TypeInfo ApplyFlowAttributes(TypeInfo type, IEnumerable<CustomAttributeData> attributes)
    {
        if (HasAttribute(attributes, MaybeNullAttributeName))
            return EnsureNullable(type);

        if (HasAttribute(attributes, NotNullAttributeName))
            return EnsureNotNull(type);

        return type;
    }

    private static TypeInfo EnsureNullable(TypeInfo type) => type switch
    {
        NullableTypeInfo => type,
        ObliviousTypeInfo oblivious => new NullableTypeInfo(oblivious.InnerType),
        _ => new NullableTypeInfo(type)
    };

    private static TypeInfo EnsureOblivious(TypeInfo type) => type switch
    {
        NullableTypeInfo => type,
        ObliviousTypeInfo => type,
        _ => new ObliviousTypeInfo(type)
    };

    private static TypeInfo EnsureNotNull(TypeInfo type) => type switch
    {
        NullableTypeInfo nullable => nullable.InnerType,
        ObliviousTypeInfo oblivious => oblivious.InnerType,
        _ => type
    };

    private static NullabilityInfo? TryCreateNullabilityInfo(PropertyInfo property)
    {
        try
        {
            return new NullabilityInfoContext().Create(property);
        }
        catch
        {
            return null;
        }
    }

    private static NullabilityInfo? TryCreateNullabilityInfo(FieldInfo field)
    {
        try
        {
            return new NullabilityInfoContext().Create(field);
        }
        catch
        {
            return null;
        }
    }

    private static NullabilityInfo? TryCreateNullabilityInfo(ParameterInfo parameter)
    {
        try
        {
            return new NullabilityInfoContext().Create(parameter);
        }
        catch
        {
            return null;
        }
    }

    private static NullabilityInfo? GetFirstGenericArgument(NullabilityInfo? info)
        => info?.GenericTypeArguments is { Length: > 0 } arguments ? arguments[0] : null;

    private static NullabilityState GetReadState(NullabilityInfo? nullabilityInfo)
        => nullabilityInfo?.ReadState ?? NullabilityState.Unknown;

    private static bool CanCarryReferenceNullability(Type type, TypeInfo converted)
    {
        if (!type.IsGenericParameter)
            return !type.IsValueType;

        return CanCarryReferenceNullability(converted);
    }

    private static bool CanCarryReferenceNullability(TypeInfo typeInfo) => typeInfo switch
    {
        SimpleTypeInfo simple => simple.Name switch
        {
            "int" or "long" or "float" or "double" or "decimal"
                or "byte" or "sbyte" or "short" or "ushort"
                or "uint" or "ulong" or "char" or "bool"
                or "void" or "null" or "never" => false,
            _ => true
        },
        NullableTypeInfo => false,
        ObliviousTypeInfo oblivious => CanCarryReferenceNullability(oblivious.InnerType),
        StructTypeInfo => false,
        EnumTypeInfo => false,
        RecordTypeInfo record => !record.Declaration.IsStruct,
        ReflectionTypeInfo reflection => !reflection.Type.IsValueType,
        UnknownTypeInfo => false,
        _ => true
    };

    private static bool IsNullableValueType(Type type)
        => Nullable.GetUnderlyingType(type) != null;

    private static bool HasAttribute(IEnumerable<CustomAttributeData> attributes, string attributeName)
        => attributes.Any(attribute => string.Equals(attribute.AttributeType.FullName, attributeName, StringComparison.Ordinal));

    private static bool IsParamsParameter(ParameterInfo parameter)
    {
        try
        {
            return parameter.GetCustomAttributesData()
                .Any(attribute => attribute.AttributeType.FullName == "System.ParamArrayAttribute");
        }
        catch
        {
            return false;
        }
    }

    private static string FormatFlowAttributes(IEnumerable<CustomAttributeData> attributes)
    {
        var formatted = new List<string>();
        foreach (var attribute in attributes)
        {
            if (attribute.AttributeType.FullName == NotNullWhenAttributeName
                && attribute.ConstructorArguments.Count == 1
                && attribute.ConstructorArguments[0].Value is bool when)
            {
                formatted.Add($"[NotNullWhen({when.ToString().ToLowerInvariant()})]");
            }
            else if (attribute.AttributeType.FullName == MaybeNullAttributeName)
            {
                formatted.Add("[MaybeNull]");
            }
            else if (attribute.AttributeType.FullName == NotNullAttributeName)
            {
                formatted.Add("[NotNull]");
            }
        }

        return formatted.Count == 0 ? string.Empty : string.Join(" ", formatted) + " ";
    }

    private static string FormatFunctionType(FunctionTypeInfo function)
    {
        if (function.ParameterTypes == null || function.ReturnType == null)
            return function.Declaration?.Name ?? "function";

        return $"({string.Join(", ", function.ParameterTypes.Select(FormatTypeInfo))}) -> {FormatTypeInfo(function.ReturnType)}";
    }

    private static string FormatClrTypeName(Type type)
    {
        if (type.IsGenericParameter)
            return type.Name;

        if (type.IsByRef)
            return FormatClrTypeName(type.GetElementType()!);

        if (type.IsArray)
            return $"{FormatClrTypeName(type.GetElementType()!)}[]";

        if (type.IsGenericType)
        {
            var name = type.Name;
            var tickIndex = name.IndexOf('`', StringComparison.Ordinal);
            if (tickIndex >= 0)
                name = name[..tickIndex];

            return $"{name}<{string.Join(", ", type.GetGenericArguments().Select(FormatClrTypeName))}>";
        }

        return type.Name switch
        {
            "Boolean" => "bool",
            "Byte" => "byte",
            "SByte" => "sbyte",
            "Int16" => "short",
            "UInt16" => "ushort",
            "Int32" => "int",
            "UInt32" => "uint",
            "Int64" => "long",
            "UInt64" => "ulong",
            "Single" => "float",
            "Double" => "double",
            "Decimal" => "decimal",
            "Char" => "char",
            "String" => "string",
            "Object" => "object",
            "Void" => "void",
            _ => type.Name
        };
    }
}
