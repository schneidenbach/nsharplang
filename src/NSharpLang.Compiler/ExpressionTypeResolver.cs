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
            CharLiteralExpression => typeof(char),
            StringLiteralExpression => typeof(string),
            InterpolatedStringExpression => typeof(string),
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
