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
    private readonly Dictionary<string, Type> _importedTypes;

    public ExpressionTypeResolver(SemanticModel semanticModel, Dictionary<string, Type>? importedTypes = null)
    {
        _semanticModel = semanticModel;
        _importedTypes = importedTypes ?? new Dictionary<string, Type>();
    }

    /// <summary>
    /// Resolves the type of an expression
    /// </summary>
    public Type? ResolveExpressionType(Expression expr)
    {
        return expr switch
        {
            IdentifierExpression id => ResolveIdentifierType(id.Name),
            MemberAccessExpression memberAccess => ResolveMemberAccessType(memberAccess),
            CallExpression call => ResolveCallType(call),
            IntLiteralExpression => typeof(int),
            FloatLiteralExpression => typeof(double),
            StringLiteralExpression => typeof(string),
            BoolLiteralExpression => typeof(bool),
            NullLiteralExpression => typeof(object),
            ArrayLiteralExpression => typeof(Array), // Simplified
            _ => null
        };
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

    private Type? ResolveIdentifierType(string name)
    {
        // Check semantic model first
        var typeRef = _semanticModel.LookupIdentifier(name);
        if (typeRef != null)
        {
            return ResolveTypeFromString(typeRef.ToString());
        }

        // Check imported types
        if (_importedTypes.TryGetValue(name, out var importedType))
        {
            return importedType;
        }

        return null;
    }

    private Type? ResolveMemberAccessType(MemberAccessExpression memberAccess)
    {
        var memberInfo = ResolveMemberInfo(memberAccess);

        return memberInfo switch
        {
            MethodInfo method => method.ReturnType,
            PropertyInfo property => property.PropertyType,
            FieldInfo field => field.FieldType,
            _ => null
        };
    }

    private Type? ResolveCallType(CallExpression call)
    {
        // If calling a member access like numbers.Select(...)
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            var memberInfo = ResolveMemberInfo(memberAccess);
            if (memberInfo is MethodInfo method)
            {
                return method.ReturnType;
            }
        }

        // If calling an identifier directly
        if (call.Callee is IdentifierExpression id)
        {
            // Check if it's a known type constructor
            var type = ResolveTypeFromString(id.Name);
            if (type != null) return type;
        }

        return null;
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
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
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
