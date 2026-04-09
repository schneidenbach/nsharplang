using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    private Type CreateDelegateType(Type[] parameterTypes, Type returnType)
    {
        if (RequiresCustomDelegateType(parameterTypes, returnType))
        {
            return CreateCustomDelegateType(parameterTypes, returnType);
        }

        if (returnType == typeof(void))
        {
            if (parameterTypes.Length == 0)
            {
                return typeof(Action);
            }

            var openActionType = typeof(Action).Assembly.GetType($"System.Action`{parameterTypes.Length}");
            if (openActionType == null)
            {
                throw new NotImplementedException($"Delegates with {parameterTypes.Length} parameters are not supported");
            }

            return openActionType.MakeGenericType(parameterTypes);
        }

        var allTypes = parameterTypes.Concat(new[] { returnType }).ToArray();
        var openFuncType = typeof(Func<>).Assembly.GetType($"System.Func`{allTypes.Length}");
        if (openFuncType == null)
        {
            throw new NotImplementedException($"Delegates with {parameterTypes.Length} parameters are not supported");
        }

        return openFuncType.MakeGenericType(allTypes);
    }

    private static bool RequiresCustomDelegateType(Type[] parameterTypes, Type returnType)
    {
        if (parameterTypes.Any(parameterType => parameterType.IsByRef) || returnType.IsByRef)
        {
            return true;
        }

        return parameterTypes.Length > 16;
    }

    private Type CreateCustomDelegateType(Type[] parameterTypes, Type returnType)
    {
        if (_moduleBuilder == null)
        {
            throw new InvalidOperationException("No module builder available for custom delegate emission");
        }

        if (parameterTypes.Any(parameterType => parameterType.ContainsGenericParameters)
            || returnType.ContainsGenericParameters)
        {
            throw new NotImplementedException("Custom delegates with open generic signature types are not yet supported in the IL compiler");
        }

        var signatureKey = new DelegateSignatureKey(parameterTypes, returnType);
        if (_customDelegateTypes.TryGetValue(signatureKey, out var existingDelegateType))
        {
            return existingDelegateType;
        }

        var delegateType = _moduleBuilder.DefineType(
            $"<>f__Delegate{_customDelegateCounter++}",
            TypeAttributes.NotPublic | TypeAttributes.Sealed | TypeAttributes.AutoClass | TypeAttributes.AnsiClass,
            typeof(MulticastDelegate));

        var constructor = delegateType.DefineConstructor(
            MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.RTSpecialName | MethodAttributes.SpecialName,
            CallingConventions.Standard,
            new[] { typeof(object), typeof(IntPtr) });
        constructor.SetImplementationFlags(MethodImplAttributes.Runtime | MethodImplAttributes.Managed);

        var invokeMethod = delegateType.DefineMethod(
            "Invoke",
            MethodAttributes.Public | MethodAttributes.HideBySig | MethodAttributes.NewSlot | MethodAttributes.Virtual,
            CallingConventions.Standard,
            returnType,
            parameterTypes);
        invokeMethod.SetImplementationFlags(MethodImplAttributes.Runtime | MethodImplAttributes.Managed);

        _generatedHelperTypes.Add(delegateType);
        _customDelegateTypes[signatureKey] = delegateType;
        _delegateConstructors[delegateType] = constructor;
        _delegateInvokeMethods[delegateType] = invokeMethod;
        return delegateType;
    }

    private ConstructorInfo GetDelegateConstructor(Type delegateType)
    {
        if (_delegateConstructors.TryGetValue(delegateType, out var constructor))
        {
            return constructor;
        }

        if (delegateType.IsGenericType
            && !delegateType.IsGenericTypeDefinition
            && RequiresTypeBuilderMemberResolution(delegateType))
        {
            try
            {
                var genericDefinition = delegateType.GetGenericTypeDefinition();
                var definitionConstructor = genericDefinition.GetConstructor(new[] { typeof(object), typeof(IntPtr) });
                if (definitionConstructor != null)
                {
                    return TypeBuilder.GetConstructor(delegateType, definitionConstructor);
                }
            }
            catch (NotSupportedException)
            {
            }
        }

        return delegateType.GetConstructor(new[] { typeof(object), typeof(IntPtr) })
            ?? throw new InvalidOperationException($"Could not resolve delegate constructor for {delegateType}");
    }

    private bool TryGetDelegateInvokeMethod(Type? type, out MethodInfo? invokeMethod)
    {
        invokeMethod = null;
        if (type == null || type == typeof(object) || type.IsGenericParameter)
        {
            return false;
        }

        if (_delegateInvokeMethods.TryGetValue(type, out invokeMethod))
        {
            return true;
        }

        if (!IsDelegateLikeType(type))
        {
            return false;
        }

        try
        {
            invokeMethod = type.GetMethod("Invoke");
            return invokeMethod != null;
        }
        catch (NotSupportedException)
        {
            if (!type.IsGenericType)
            {
                return false;
            }

            try
            {
                var genericDefinition = type.GetGenericTypeDefinition();
                var definitionInvoke = genericDefinition.GetMethod("Invoke");
                if (definitionInvoke == null)
                {
                    return false;
                }

                invokeMethod = TypeBuilder.GetMethod(type, definitionInvoke);
                return invokeMethod != null;
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }
    }

    private static bool IsDelegateLikeType(Type type)
    {
        try
        {
            if (typeof(Delegate).IsAssignableFrom(type))
            {
                return true;
            }
        }
        catch (NotSupportedException)
        {
        }

        var current = type;
        while (current != null)
        {
            var fullName = current.FullName;
            if (string.Equals(fullName, typeof(MulticastDelegate).FullName, StringComparison.Ordinal)
                || string.Equals(fullName, typeof(Delegate).FullName, StringComparison.Ordinal))
            {
                return true;
            }

            try
            {
                current = current.BaseType;
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }

        return false;
    }

    private Type GetDelegateInvokeReturnType(Type delegateType, MethodInfo invokeMethod)
    {
        return ResolveDelegateSignatureType(delegateType, invokeMethod.ReturnType);
    }

    private Type[] GetDelegateInvokeParameterTypes(Type delegateType, MethodInfo invokeMethod)
    {
        return invokeMethod.GetParameters()
            .Select(parameter => ResolveDelegateSignatureType(delegateType, parameter.ParameterType))
            .ToArray();
    }

    private static Type ResolveDelegateSignatureType(Type delegateType, Type signatureType)
    {
        if (!signatureType.ContainsGenericParameters || !delegateType.IsGenericType)
        {
            return signatureType;
        }

        Type genericDefinition;
        Type[] definitionArguments;
        Type[] actualArguments;
        try
        {
            genericDefinition = delegateType.GetGenericTypeDefinition();
            definitionArguments = genericDefinition.GetGenericArguments();
            actualArguments = delegateType.GetGenericArguments();
        }
        catch (NotSupportedException)
        {
            return signatureType;
        }

        var substitutions = new Dictionary<(string Name, int Position), Type>();
        for (int i = 0; i < definitionArguments.Length && i < actualArguments.Length; i++)
        {
            substitutions[(definitionArguments[i].Name, definitionArguments[i].GenericParameterPosition)] = actualArguments[i];
        }

        return SubstituteDelegateSignatureType(signatureType, substitutions);
    }

    private static Type SubstituteDelegateSignatureType(
        Type signatureType,
        IReadOnlyDictionary<(string Name, int Position), Type> substitutions)
    {
        if (signatureType.IsGenericParameter
            && substitutions.TryGetValue((signatureType.Name, signatureType.GenericParameterPosition), out var substitutedType))
        {
            return substitutedType;
        }

        if (signatureType.IsByRef)
        {
            return SubstituteDelegateSignatureType(signatureType.GetElementType()!, substitutions).MakeByRefType();
        }

        if (signatureType.IsArray)
        {
            return SubstituteDelegateSignatureType(signatureType.GetElementType()!, substitutions).MakeArrayType();
        }

        if (!signatureType.IsGenericType)
        {
            return signatureType;
        }

        Type genericDefinition;
        try
        {
            genericDefinition = signatureType.GetGenericTypeDefinition();
        }
        catch (NotSupportedException)
        {
            return signatureType;
        }

        var substitutedArguments = signatureType.GetGenericArguments()
            .Select(argument => SubstituteDelegateSignatureType(argument, substitutions))
            .ToArray();
        return genericDefinition.MakeGenericType(substitutedArguments);
    }
}
