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
    /// Resolves the semantic TypeInfo of an expression using the Analyzer's recorded
    /// expression types first, then falls back to lightweight AST/reflection resolution.
    /// </summary>
    public TypeInfo? ResolveExpressionTypeInfo(Expression expr)
    {
        var recordedType = _semanticModel.LookupTypeAtPosition(expr.Line, expr.Column);
        if (recordedType != null && !BuiltInTypes.IsUnknown(recordedType))
            return recordedType;

        return expr switch
        {
            IdentifierExpression id => ResolveIdentifierTypeInfo(id.Name),
            MemberAccessExpression memberAccess => ResolveMemberAccessTypeInfo(memberAccess),
            CallExpression call => ResolveCallTypeInfo(call),
            MustExpression must => ResolveMustTypeInfo(must),
            IntLiteralExpression => BuiltInTypes.Int,
            FloatLiteralExpression => BuiltInTypes.Double,
            CharLiteralExpression => BuiltInTypes.Char,
            StringLiteralExpression => BuiltInTypes.String,
            InterpolatedStringExpression => BuiltInTypes.String,
            BoolLiteralExpression => BuiltInTypes.Bool,
            NullLiteralExpression => BuiltInTypes.Object,
            NewExpression newExpr when newExpr.Type != null => ResolveTypeReference(newExpr.Type),
            ArrayLiteralExpression => new ReflectionTypeInfo(typeof(Array)), // Simplified fallback
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

    private TypeInfo? ResolveIdentifierTypeInfo(string name)
    {
        var typeInfo = _semanticModel.LookupIdentifier(name);
        if (typeInfo != null)
            return typeInfo;

        if (_importedTypes.TryGetValue(name, out var importedType))
            return new ReflectionTypeInfo(importedType);

        var clrType = ResolveTypeFromString(name);
        return clrType != null ? ConvertClrTypeToTypeInfo(clrType) : null;
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

    private TypeInfo? ResolveMemberAccessTypeInfo(MemberAccessExpression memberAccess)
    {
        var memberInfo = ResolveMemberInfo(memberAccess);

        return memberInfo switch
        {
            MethodInfo method => ConvertClrTypeToTypeInfo(method.ReturnType),
            PropertyInfo property => ConvertClrTypeToTypeInfo(property.PropertyType),
            FieldInfo field => ConvertClrTypeToTypeInfo(field.FieldType),
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
                // Check if it's a generic method definition
                if (method.IsGenericMethodDefinition)
                {
                    var constructedMethod = TryConstructGenericMethod(method, memberAccess, call);
                    return constructedMethod?.ReturnType ?? method.ReturnType;
                }

                return method.ReturnType;
            }
        }

        // If calling an identifier directly (e.g., hi())
        if (call.Callee is IdentifierExpression id)
        {
            // First check if it's a function in the semantic model
            if (_semanticModel.Functions.TryGetValue(id.Name, out var funcReturnType))
            {
                // Convert TypeInfo to System.Type
                return ResolveTypeFromString(funcReturnType.ToString());
            }

            // Check if it's a known type constructor
            var type = ResolveTypeFromString(id.Name);
            if (type != null) return type;
        }

        return null;
    }

    private TypeInfo? ResolveCallTypeInfo(CallExpression call)
    {
        if (call.Callee is MemberAccessExpression memberAccess)
        {
            var memberInfo = ResolveMemberInfo(memberAccess);
            if (memberInfo is MethodInfo method)
            {
                if (method.IsGenericMethodDefinition)
                {
                    var constructedMethod = TryConstructGenericMethod(method, memberAccess, call);
                    return constructedMethod != null
                        ? ConvertClrTypeToTypeInfo(constructedMethod.ReturnType)
                        : ConvertClrTypeToTypeInfo(method.ReturnType);
                }

                return ConvertClrTypeToTypeInfo(method.ReturnType);
            }
        }

        if (call.Callee is IdentifierExpression id)
        {
            if (_semanticModel.Functions.TryGetValue(id.Name, out var funcReturnType))
                return funcReturnType;

            var type = ResolveTypeFromString(id.Name);
            if (type != null)
                return ConvertClrTypeToTypeInfo(type);
        }

        return null;
    }

    private Type? ResolveExpressionTypeFallback(Expression expr)
    {
        return expr switch
        {
            IdentifierExpression id => ResolveIdentifierType(id.Name),
            MemberAccessExpression memberAccess => ResolveMemberAccessType(memberAccess),
            CallExpression call => ResolveCallType(call),
            MustExpression must => ResolveMustType(must),
            IntLiteralExpression => typeof(int),
            FloatLiteralExpression => typeof(double),
            CharLiteralExpression => typeof(char),
            StringLiteralExpression => typeof(string),
            InterpolatedStringExpression => typeof(string),
            BoolLiteralExpression => typeof(bool),
            NullLiteralExpression => typeof(object),
            ArrayLiteralExpression => typeof(Array),
            _ => null
        };
    }

    private TypeInfo? ResolveMustTypeInfo(MustExpression must)
    {
        var operandType = ResolveExpressionTypeInfo(must.Expression);
        return operandType is NullableTypeInfo nullable ? nullable.InnerType : operandType;
    }

    private Type? ResolveMustType(MustExpression must)
    {
        var operandType = ResolveExpressionType(must.Expression);
        return operandType != null ? Nullable.GetUnderlyingType(operandType) ?? operandType : null;
    }

    private TypeInfo ResolveTypeReference(TypeReference typeRef)
    {
        return typeRef switch
        {
            SimpleTypeReference s => new SimpleTypeInfo(s.Name),
            GenericTypeReference g => new GenericTypeInfo(g.Name,
                g.TypeArguments.Select(ResolveTypeReference).ToList()),
            ArrayTypeReference a => new ArrayTypeInfo(ResolveTypeReference(a.ElementType)),
            NullableTypeReference n => new NullableTypeInfo(ResolveTypeReference(n.InnerType)),
            _ => new SimpleTypeInfo(typeRef.ToString() ?? "unknown")
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
            GenericTypeInfo generic => ResolveGenericTypeInfo(generic),
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
        var typeDefinition = ResolveTypeFromString(generic.Name);
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

    private static TypeInfo ConvertClrTypeToTypeInfo(Type type)
    {
        if (type.IsByRef)
            return ConvertClrTypeToTypeInfo(type.GetElementType()!);

        if (type.IsArray)
            return new ArrayTypeInfo(ConvertClrTypeToTypeInfo(type.GetElementType()!));

        return type.FullName switch
        {
            "System.Int32" => BuiltInTypes.Int,
            "System.Int64" => BuiltInTypes.Long,
            "System.Int16" => BuiltInTypes.Short,
            "System.Byte" => BuiltInTypes.Byte,
            "System.Single" => BuiltInTypes.Float,
            "System.Double" => BuiltInTypes.Double,
            "System.Decimal" => BuiltInTypes.Decimal,
            "System.Boolean" => BuiltInTypes.Bool,
            "System.Char" => BuiltInTypes.Char,
            "System.String" => BuiltInTypes.String,
            "System.Void" => BuiltInTypes.Void,
            "System.Object" => BuiltInTypes.Object,
            _ when type.IsGenericType => new GenericTypeInfo(
                type.Name[..type.Name.IndexOf('`')],
                type.GetGenericArguments().Select(ConvertClrTypeToTypeInfo).ToList()),
            _ => new ReflectionTypeInfo(type)
        };
    }

    /// <summary>
    /// Attempts to construct a generic method with inferred type arguments
    /// </summary>
    private MethodInfo? TryConstructGenericMethod(MethodInfo genericMethod, MemberAccessExpression memberAccess, CallExpression call)
    {
        // Get the type of the object (e.g., int[] for numbers.Select)
        var objectType = ResolveExpressionType(memberAccess.Object);
        if (objectType == null) return null;

        var typeArgs = new List<Type>();
        var genericParams = genericMethod.GetGenericArguments();

        // Handle common LINQ extension methods
        if (genericMethod.Name == "Select" || genericMethod.Name == "Where" ||
            genericMethod.Name == "ToList" || genericMethod.Name == "ToArray" ||
            genericMethod.Name == "FirstOrDefault" || genericMethod.Name == "First" ||
            genericMethod.Name == "Last" || genericMethod.Name == "LastOrDefault" ||
            genericMethod.Name == "Any" || genericMethod.Name == "All" ||
            genericMethod.Name == "Count" || genericMethod.Name == "Sum")
        {
            // Infer TSource from the collection
            if (TryGetEnumerableElementType(objectType, out var elementType))
            {
                typeArgs.Add(elementType!);

                // For Select, we need TResult as well
                if (genericMethod.Name == "Select" && genericParams.Length == 2)
                {
                    // TODO: Analyze lambda to determine result type
                    // For now, assume same type (Select<int, int>)
                    typeArgs.Add(elementType!);
                }
            }
        }

        // Only construct if we have all type arguments
        if (typeArgs.Count == genericParams.Length)
        {
            try
            {
                return genericMethod.MakeGenericMethod(typeArgs.ToArray());
            }
            catch
            {
                return null;
            }
        }

        return null;
    }

    /// <summary>
    /// Tries to get the element type of an IEnumerable<T> or array
    /// </summary>
    private bool TryGetEnumerableElementType(Type type, out Type? elementType)
    {
        // Check if it's an array
        if (type.IsArray)
        {
            elementType = type.GetElementType();
            return elementType != null;
        }

        // Check if it implements IEnumerable<T>
        var enumerableInterface = type.GetInterfaces()
            .FirstOrDefault(i => i.IsGenericType &&
                               i.GetGenericTypeDefinition() == typeof(IEnumerable<>));

        if (enumerableInterface != null)
        {
            elementType = enumerableInterface.GetGenericArguments()[0];
            return true;
        }

        // Check if the type itself is IEnumerable<T>
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(IEnumerable<>))
        {
            elementType = type.GetGenericArguments()[0];
            return true;
        }

        elementType = null;
        return false;
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
