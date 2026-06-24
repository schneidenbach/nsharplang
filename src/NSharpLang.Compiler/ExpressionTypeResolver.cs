using System;
using System.Linq;
using System.Reflection;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Resolves types of expressions by walking the AST and using reflection
/// </summary>
public class ExpressionTypeResolver
{
    private readonly SemanticModel _semanticModel;

    public ExpressionTypeResolver(SemanticModel semanticModel, Dictionary<string, Type>? importedTypes = null)
    {
        _semanticModel = semanticModel;
    }

    /// <summary>
    /// Resolves the semantic TypeInfo of an expression using the Analyzer's recorded
    /// </summary>
    public TypeInfo? ResolveExpressionTypeInfo(Expression expr)
    {
        var recordedType = _semanticModel.LookupTypeAtPosition(expr.Line, expr.Column);
        if (recordedType != null && !BuiltInTypes.IsUnknown(recordedType))
            return recordedType;

        return expr switch
        {
            _ => null
        };
    }

    /// <summary>
    /// Resolves the CLR type of an expression when one is available.
    /// </summary>
    public Type? ResolveExpressionType(Expression expr)
    {
        var typeInfo = ResolveExpressionTypeInfo(expr);
        var clrType = typeInfo != null ? ResolveTypeInfoToClrType(typeInfo) : null;
        if (clrType != null)
            return clrType;

        return ResolveExpressionTypeFallback(expr);
    }

    /// <summary>
    /// Resolves member info for a member access expression
    /// Returns the MemberInfo (MethodInfo, PropertyInfo, or FieldInfo)
    /// </summary>
    public MemberInfo? ResolveMemberInfo(MemberAccessExpression memberAccess)
    {
        // Resolve the type of the object being accessed
        var objectType = ResolveExpressionType(memberAccess.Object);
        if (objectType == null) return null;

        var memberName = memberAccess.MemberName;

        // Try to find method
        var methods = objectType.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
            .Where(m => m.Name == memberName)
            .ToArray();

        if (methods.Length > 0)
        {
            // Return first overload for now
            return methods[0];
        }

        // Try property
        var property = objectType.GetProperty(memberName, BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
        if (property != null) return property;

        // Try field
        var field = objectType.GetField(memberName, BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
        return field;
    }

    /// <summary>
    /// Gets all method overloads for a member access
    /// </summary>
    public MethodInfo[] GetMethodOverloads(MemberAccessExpression memberAccess)
    {
        var objectType = ResolveExpressionType(memberAccess.Object);
        if (objectType == null) return Array.Empty<MethodInfo>();

        var memberName = memberAccess.MemberName;
        return objectType.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
            .Where(m => m.Name == memberName)
            .ToArray();
    }

    private Type? ResolveExpressionTypeFallback(Expression expr)
    {
        return expr switch
        {
            _ => null
        };
    }

    private Type? ResolveTypeInfoToClrType(TypeInfo typeInfo)
    {
        return typeInfo switch
        {
            ReflectionTypeInfo reflection => reflection.Type,
            SimpleTypeInfo simple => ResolveTypeFromString(simple.Name),
            ArrayTypeInfo array => ResolveTypeInfoToClrType(array.ElementType)?.MakeArrayType(),
            NullableTypeInfo nullable => ResolveNullableTypeInfo(nullable.InnerType),
            ObliviousTypeInfo oblivious => ResolveTypeInfoToClrType(oblivious.InnerType),
            ByRefTypeInfo byRef => ResolveTypeInfoToClrType(byRef.InnerType)?.MakeByRefType(),
            GenericTypeInfo generic => ResolveGenericTypeInfo(generic),
            UnionTypeInfo { IsAnonymous: true } union when union.Arms.Count == 2
                => ResolveTypeInfoToClrType(union.Arms[0]) is { } arm0
                   && ResolveTypeInfoToClrType(union.Arms[1]) is { } arm1
                    ? typeof(NSharpLang.Runtime.Union<,>).MakeGenericType(arm0, arm1)
                    : null,
            _ => ResolveTypeFromString(typeInfo.ToString())
        };
    }

    private Type? ResolveNullableTypeInfo(TypeInfo innerType)
    {
        var clrInnerType = ResolveTypeInfoToClrType(innerType);
        if (clrInnerType == null)
            return null;

        return clrInnerType.IsValueType
            ? typeof(Nullable<>).MakeGenericType(clrInnerType)
            : clrInnerType;
    }

    private Type? ResolveGenericTypeInfo(GenericTypeInfo generic)
    {
        var typeDefinition = generic.Name switch
        {
            "Result" or "NSharpLang.Runtime.Result" when generic.TypeArguments.Count == 2 => typeof(NSharpLang.Runtime.Result<,>),
            _ => ResolveTypeFromString(generic.Name)
        };
        if (typeDefinition == null)
            return null;

        if (!typeDefinition.IsGenericTypeDefinition)
            return typeDefinition;

        var typeArguments = new List<Type>();
        foreach (var argument in generic.TypeArguments)
        {
            var clrArgument = ResolveTypeInfoToClrType(argument);
            if (clrArgument == null)
                return null;
            typeArguments.Add(clrArgument);
        }

        return typeDefinition.MakeGenericType(typeArguments.ToArray());
    }

    private Type? ResolveTypeFromString(string typeName)
    {
        // Handle array types
        if (typeName.EndsWith("[]"))
        {
            var elementTypeName = typeName.Substring(0, typeName.Length - 2);
            var elementType = ResolveTypeFromString(elementTypeName);
            return elementType?.MakeArrayType();
        }

        // Handle nullable types
        if (typeName.EndsWith("?"))
        {
            var underlyingTypeName = typeName.Substring(0, typeName.Length - 1);
            var underlyingType = ResolveTypeFromString(underlyingTypeName);
            if (underlyingType != null && underlyingType.IsValueType)
            {
                return typeof(Nullable<>).MakeGenericType(underlyingType);
            }
            return underlyingType;
        }

        // Map primitive type names
        return typeName switch
        {
            "int" => typeof(int),
            "long" => typeof(long),
            "short" => typeof(short),
            "byte" => typeof(byte),
            "float" => typeof(float),
            "double" => typeof(double),
            "decimal" => typeof(decimal),
            "bool" => typeof(bool),
            "string" => typeof(string),
            "object" => typeof(object),
            "void" => typeof(void),
            _ => Type.GetType(typeName) ?? TryResolveFromLoadedAssemblies(typeName)
        };
    }

    private Type? TryResolveFromLoadedAssemblies(string typeName)
    {
        foreach (var assembly in ExternalAssemblyScan.Loaded())
        {
            var type = assembly.GetType(typeName);
            if (type != null) return type;

            // Try with System namespace
            type = assembly.GetType($"System.{typeName}");
            if (type != null) return type;

            // Try with System.Collections.Generic
            type = assembly.GetType($"System.Collections.Generic.{typeName}");
            if (type != null) return type;
        }

        return null;
    }
}
