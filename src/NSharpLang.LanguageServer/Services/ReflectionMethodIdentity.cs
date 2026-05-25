using System;
using System.Linq;
using System.Reflection;

namespace NSharpLang.LanguageServer.Services;

internal static class ReflectionMethodIdentity
{
    public static bool MethodsMatch(MethodInfo left, MethodInfo right)
    {
        if (ReferenceEquals(left, right))
        {
            return true;
        }

        if (HasSameMetadataIdentity(left, right))
        {
            return true;
        }

        var leftDefinition = left.IsGenericMethod ? left.GetGenericMethodDefinition() : left;
        var rightDefinition = right.IsGenericMethod ? right.GetGenericMethodDefinition() : right;

        if (!string.Equals(leftDefinition.Name, rightDefinition.Name, StringComparison.Ordinal))
        {
            return false;
        }

        if (!string.Equals(
                leftDefinition.DeclaringType?.FullName,
                rightDefinition.DeclaringType?.FullName,
                StringComparison.Ordinal))
        {
            return false;
        }

        if (leftDefinition.GetGenericArguments().Length != rightDefinition.GetGenericArguments().Length)
        {
            return false;
        }

        var leftParameters = leftDefinition.GetParameters();
        var rightParameters = rightDefinition.GetParameters();
        if (leftParameters.Length != rightParameters.Length)
        {
            return false;
        }

        for (var i = 0; i < leftParameters.Length; i++)
        {
            if (!TypesMatch(leftParameters[i].ParameterType, rightParameters[i].ParameterType))
            {
                return false;
            }
        }

        return true;
    }

    private static bool HasSameMetadataIdentity(MethodInfo left, MethodInfo right)
    {
        try
        {
            if (left.MetadataToken == right.MetadataToken && left.Module == right.Module)
            {
                return true;
            }

            var leftDefinition = left.IsGenericMethod ? left.GetGenericMethodDefinition() : left;
            var rightDefinition = right.IsGenericMethod ? right.GetGenericMethodDefinition() : right;
            return leftDefinition.MetadataToken == rightDefinition.MetadataToken
                && leftDefinition.Module == rightDefinition.Module;
        }
        catch
        {
            return false;
        }
    }

    private static bool TypesMatch(Type left, Type right)
    {
        if (left == right)
        {
            return true;
        }

        if (left.IsByRef || right.IsByRef)
        {
            return left.IsByRef
                && right.IsByRef
                && TypesMatch(left.GetElementType()!, right.GetElementType()!);
        }

        if (left.IsPointer || right.IsPointer)
        {
            return left.IsPointer
                && right.IsPointer
                && TypesMatch(left.GetElementType()!, right.GetElementType()!);
        }

        if (left.IsArray || right.IsArray)
        {
            return left.IsArray
                && right.IsArray
                && left.GetArrayRank() == right.GetArrayRank()
                && TypesMatch(left.GetElementType()!, right.GetElementType()!);
        }

        if (left.IsGenericParameter || right.IsGenericParameter)
        {
            return left.IsGenericParameter
                && right.IsGenericParameter
                && left.GenericParameterPosition == right.GenericParameterPosition
                && (left.DeclaringMethod != null) == (right.DeclaringMethod != null);
        }

        if (left.IsGenericType || right.IsGenericType)
        {
            if (!left.IsGenericType || !right.IsGenericType)
            {
                return false;
            }

            var leftDefinition = left.IsGenericTypeDefinition ? left : left.GetGenericTypeDefinition();
            var rightDefinition = right.IsGenericTypeDefinition ? right : right.GetGenericTypeDefinition();
            if (!string.Equals(leftDefinition.FullName, rightDefinition.FullName, StringComparison.Ordinal))
            {
                return false;
            }

            var leftArguments = left.GetGenericArguments();
            var rightArguments = right.GetGenericArguments();
            return leftArguments.Length == rightArguments.Length
                && leftArguments.Zip(rightArguments, TypesMatch).All(match => match);
        }

        return string.Equals(left.FullName, right.FullName, StringComparison.Ordinal);
    }
}
