using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    private sealed record RuntimeDefaultBoundCallArgument(object? Value, Type ParameterType)
        : BoundCallArgument(ParameterType);

    private sealed record BoundRuntimeMethodCall(MethodInfo Method, IReadOnlyList<BoundCallArgument> Arguments, Type ReturnType);
    private sealed record BoundRuntimeConstructorCall(ConstructorInfo Constructor, IReadOnlyList<BoundCallArgument> Arguments);

    private BoundRuntimeMethodCall? BindRuntimeMethodCall(Type declaringType, string methodName, CallExpression call, BindingFlags bindingFlags)
    {
        return BindRuntimeMethodCall(declaringType, methodName, call.Arguments, call.TypeArguments, bindingFlags);
    }

    private BoundRuntimeMethodCall? BindRuntimeMethodCall(
        Type declaringType,
        string methodName,
        IReadOnlyList<Argument> arguments,
        IReadOnlyList<TypeReference>? typeArguments,
        BindingFlags bindingFlags)
    {
        if (declaringType.IsGenericParameter)
        {
            return null;
        }

        var candidates = GetRuntimeMethodCandidates(declaringType, bindingFlags)
            .Where(method => method.Name == methodName)
            .ToArray();

        return BindRuntimeMethodCandidates(declaringType, candidates, arguments, typeArguments);
    }

    private static IEnumerable<MethodInfo> GetRuntimeMethodCandidates(Type declaringType, BindingFlags bindingFlags)
    {
        try
        {
            return declaringType.GetMethods(bindingFlags);
        }
        catch (NotSupportedException) when (declaringType.IsGenericType && !declaringType.IsGenericTypeDefinition)
        {
            try
            {
                return declaringType.GetGenericTypeDefinition()
                    .GetMethods(bindingFlags);
            }
            catch (NotSupportedException)
            {
                return Array.Empty<MethodInfo>();
            }
        }
        catch (NotSupportedException)
        {
            return Array.Empty<MethodInfo>();
        }
    }

    private BoundRuntimeMethodCall? BindRuntimeExtensionMethodCall(Type receiverType, string methodName, Expression receiver, CallExpression call)
    {
        var arguments = new List<Argument>(call.Arguments.Count + 1)
        {
            new(null, receiver)
        };
        arguments.AddRange(call.Arguments);

        var candidates = AppDomain.CurrentDomain.GetAssemblies()
            .SelectMany(GetLoadableTypes)
            .Where(IsImportedExtensionContainerType)
            .SelectMany(GetRuntimeStaticMethods)
            .Where(method => method.Name == methodName)
            .Where(HasExtensionAttribute)
            .Where(method => CanBindRuntimeExtensionTarget(method, receiverType))
            .ToArray();

        return BindRuntimeMethodCandidates(receiverType, candidates, arguments, call.TypeArguments);
    }

    private bool IsImportedExtensionContainerType(Type type)
    {
        var namespaceName = TryGetRuntimeTypeNamespace(type);
        if (namespaceName == null || !IsStaticRuntimeContainerType(type))
        {
            return false;
        }

        return _compilationUnit.Imports.Any(import =>
            import.Alias == null
            && string.Equals(import.Namespace, namespaceName, StringComparison.Ordinal));
    }

    private BoundRuntimeMethodCall? BindRuntimeMethodCandidates(
        Type targetType,
        IEnumerable<MethodInfo> candidates,
        IReadOnlyList<Argument> arguments,
        IReadOnlyList<TypeReference>? typeArguments)
    {
        BoundRuntimeMethodCall? best = null;
        var bestScore = -1;
        var bestUsesParams = true;
        var bestDefaultsUsed = int.MaxValue;
        var bestIsGeneric = true;

        foreach (var candidateDefinition in candidates)
        {
            var candidateMethod = CreateRuntimeMethodCandidate(candidateDefinition, typeArguments);
            if (candidateMethod == null)
            {
                continue;
            }

            if (NeedsRuntimeTypeBuilderRetarget(targetType, candidateDefinition))
            {
                try
                {
                    candidateMethod = TypeBuilder.GetMethod(targetType, candidateMethod);
                }
                catch (ArgumentException)
                {
                    continue;
                }
            }

            if (!TryGetRuntimeMethodSignature(
                    targetType,
                    candidateMethod,
                    candidateDefinition,
                    out var runtimeParameterInfos,
                    out var runtimeParameterTypes,
                    out var runtimeReturnType))
            {
                continue;
            }

            var closedMethodBindings = GetClosedRuntimeMethodBindings(candidateMethod, candidateDefinition);
            if (closedMethodBindings.Count > 0)
            {
                runtimeParameterTypes = runtimeParameterTypes
                    .Select(type => ApplyRuntimeGenericBindings(type, closedMethodBindings))
                    .ToArray();
                runtimeReturnType = ApplyRuntimeGenericBindings(runtimeReturnType, closedMethodBindings);
            }

            if (!TryBindRuntimeParameters(
                    runtimeParameterInfos,
                    runtimeParameterTypes,
                    arguments,
                    out var boundArguments,
                    out var score,
                    out var usesParams,
                    out var defaultsUsed,
                    out var genericBindings))
            {
                continue;
            }

            if (candidateMethod.IsGenericMethodDefinition)
            {
                candidateMethod = CloseRuntimeGenericMethod(candidateMethod, genericBindings);
                if (candidateMethod == null)
                {
                    continue;
                }

                runtimeParameterTypes = runtimeParameterTypes
                    .Select(type => ApplyRuntimeGenericBindings(type, genericBindings))
                    .ToArray();
                runtimeReturnType = ApplyRuntimeGenericBindings(runtimeReturnType, genericBindings);
                boundArguments = RetargetRuntimeBoundArguments(boundArguments, runtimeParameterTypes);
            }

            var isGeneric = candidateMethod.IsGenericMethod;
            if (best == null
                || score > bestScore
                || (score == bestScore && bestIsGeneric && !isGeneric)
                || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams && !usesParams)
                || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams == usesParams && defaultsUsed < bestDefaultsUsed))
            {
                best = new BoundRuntimeMethodCall(candidateMethod, boundArguments, runtimeReturnType);
                bestScore = score;
                bestUsesParams = usesParams;
                bestDefaultsUsed = defaultsUsed;
                bestIsGeneric = isGeneric;
            }
        }

        return best;
    }

    private static Dictionary<string, Type> GetClosedRuntimeMethodBindings(MethodInfo candidateMethod, MethodInfo candidateDefinition)
    {
        var bindings = new Dictionary<string, Type>(StringComparer.Ordinal);
        if (!candidateDefinition.IsGenericMethodDefinition
            || !candidateMethod.IsGenericMethod
            || candidateMethod.IsGenericMethodDefinition)
        {
            return bindings;
        }

        var definitionArguments = candidateDefinition.GetGenericArguments();
        var actualArguments = candidateMethod.GetGenericArguments();
        for (int i = 0; i < definitionArguments.Length && i < actualArguments.Length; i++)
        {
            bindings[definitionArguments[i].Name] = actualArguments[i];
        }

        return bindings;
    }

    private static IEnumerable<Type> GetLoadableTypes(Assembly assembly)
    {
        try
        {
            return assembly.GetTypes();
        }
        catch (ReflectionTypeLoadException ex)
        {
            return ex.Types.Where(type => type != null)!;
        }
        catch
        {
            return Array.Empty<Type>();
        }
    }

    private static string? TryGetRuntimeTypeNamespace(Type type)
    {
        try
        {
            return type.Namespace;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsStaticRuntimeContainerType(Type type)
    {
        try
        {
            return type.IsSealed && type.IsAbstract;
        }
        catch
        {
            return false;
        }
    }

    private static IEnumerable<MethodInfo> GetRuntimeStaticMethods(Type type)
    {
        try
        {
            return type.GetMethods(BindingFlags.Public | BindingFlags.Static);
        }
        catch
        {
            return Array.Empty<MethodInfo>();
        }
    }

    private static bool HasExtensionAttribute(MethodInfo method)
    {
        try
        {
            return method.GetCustomAttributesData()
                .Any(attribute => attribute.AttributeType.FullName == "System.Runtime.CompilerServices.ExtensionAttribute");
        }
        catch
        {
            return false;
        }
    }

    private static bool CanBindRuntimeExtensionTarget(MethodInfo method, Type receiverType)
    {
        try
        {
            var parameters = method.GetParameters();
            if (parameters.Length == 0)
            {
                return false;
            }

            var receiverParameterType = parameters[0].ParameterType;
            return receiverParameterType.ContainsGenericParameters
                || receiverParameterType.IsAssignableFrom(receiverType);
        }
        catch
        {
            return true;
        }
    }

    private BoundRuntimeConstructorCall? BindRuntimeConstructorCall(Type declaringType, IReadOnlyList<Argument> arguments)
    {
        if (declaringType.IsGenericParameter)
        {
            return null;
        }

        ConstructorInfo[] candidates;
        try
        {
            candidates = declaringType.GetConstructors(BindingFlags.Public | BindingFlags.Instance);
        }
        catch (NotSupportedException) when (declaringType.IsGenericType && !declaringType.IsGenericTypeDefinition)
        {
            candidates = declaringType.GetGenericTypeDefinition()
                .GetConstructors(BindingFlags.Public | BindingFlags.Instance)
                .Select(constructor => TypeBuilder.GetConstructor(declaringType, constructor))
                .ToArray();
        }

        BoundRuntimeConstructorCall? best = null;
        var bestScore = -1;
        var bestUsesParams = true;
        var bestDefaultsUsed = int.MaxValue;

        foreach (var candidate in candidates)
        {
            if (!TryBindRuntimeParameters(
                    candidate.GetParameters(),
                    arguments,
                    out var boundArguments,
                    out var score,
                    out var usesParams,
                    out var defaultsUsed,
                    out _))
            {
                continue;
            }

            if (best == null
                || score > bestScore
                || (score == bestScore && bestUsesParams && !usesParams)
                || (score == bestScore && bestUsesParams == usesParams && defaultsUsed < bestDefaultsUsed))
            {
                best = new BoundRuntimeConstructorCall(candidate, boundArguments);
                bestScore = score;
                bestUsesParams = usesParams;
                bestDefaultsUsed = defaultsUsed;
            }
        }

        return best;
    }

    private MethodInfo? CreateRuntimeMethodCandidate(MethodInfo candidateDefinition, IReadOnlyList<TypeReference>? typeArguments)
    {
        if (!candidateDefinition.IsGenericMethodDefinition)
        {
            return typeArguments is { Count: > 0 } ? null : candidateDefinition;
        }

        if (typeArguments == null || typeArguments.Count == 0)
        {
            return candidateDefinition;
        }

        if (candidateDefinition.GetGenericArguments().Length != typeArguments.Count)
        {
            return null;
        }

        var resolvedTypeArguments = typeArguments
            .Select(typeArgument => ResolveType(typeArgument, _currentGenericParameters))
            .ToArray();

        try
        {
            return candidateDefinition.MakeGenericMethod(resolvedTypeArguments);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private static bool NeedsRuntimeTypeBuilderRetarget(Type targetType, MethodInfo candidateDefinition)
    {
        if (!targetType.IsGenericType || targetType.IsGenericTypeDefinition || !RequiresTypeBuilderMemberResolution(targetType))
        {
            return false;
        }

        Type? candidateDeclaringType;
        try
        {
            candidateDeclaringType = candidateDefinition.DeclaringType;
        }
        catch (NotSupportedException)
        {
            return false;
        }

        return candidateDeclaringType != null
            && candidateDeclaringType.IsGenericTypeDefinition
            && targetType.GetGenericTypeDefinition() == candidateDeclaringType;
    }

    private bool TryGetRuntimeMethodSignature(
        Type targetType,
        MethodInfo candidateMethod,
        MethodInfo candidateDefinition,
        out ParameterInfo[] runtimeParameterInfos,
        out Type[] runtimeParameterTypes,
        out Type runtimeReturnType)
    {
        try
        {
            runtimeParameterInfos = candidateMethod.GetParameters();
            runtimeParameterTypes = runtimeParameterInfos.Select(parameter => parameter.ParameterType).ToArray();
            runtimeReturnType = candidateMethod.ReturnType;
            return true;
        }
        catch (NotSupportedException)
        {
            if (!targetType.IsGenericType || targetType.IsGenericTypeDefinition || !RequiresTypeBuilderMemberResolution(targetType))
            {
                runtimeParameterInfos = Array.Empty<ParameterInfo>();
                runtimeParameterTypes = Array.Empty<Type>();
                runtimeReturnType = typeof(object);
                return false;
            }

            runtimeParameterInfos = candidateDefinition.GetParameters();
            runtimeParameterTypes = runtimeParameterInfos
                .Select(parameter => ResolveGenericSignatureType(targetType, parameter.ParameterType))
                .ToArray();
            runtimeReturnType = ResolveGenericSignatureType(targetType, candidateDefinition.ReturnType);
            return true;
        }
    }

    private bool TryBindRuntimeParameters(
        ParameterInfo[] runtimeParameterInfos,
        IReadOnlyList<Type> runtimeParameterTypes,
        IReadOnlyList<Argument> suppliedArguments,
        out IReadOnlyList<BoundCallArgument> boundArguments,
        out int score,
        out bool usesParams,
        out int defaultsUsed,
        out Dictionary<string, Type> genericBindings)
    {
        var bound = new BoundCallArgument[runtimeParameterTypes.Count];
        score = 0;
        defaultsUsed = 0;
        genericBindings = new Dictionary<string, Type>(StringComparer.Ordinal);
        usesParams = runtimeParameterInfos.Length > 0 && runtimeParameterInfos[^1].IsDefined(typeof(ParamArrayAttribute), inherit: false);

        var paramsParameterIndex = usesParams ? runtimeParameterTypes.Count - 1 : -1;
        var nextPositionalParameter = 0;
        var paramsArguments = new List<Argument>();

        foreach (var argument in suppliedArguments)
        {
            if (argument.Name != null)
            {
                var parameterIndex = Array.FindIndex(runtimeParameterInfos, parameter => parameter.Name == argument.Name);
                if (parameterIndex < 0 || bound[parameterIndex] != null)
                {
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
                }

                bound[parameterIndex] = new SuppliedBoundCallArgument(argument, runtimeParameterTypes[parameterIndex]);
                continue;
            }

            while (nextPositionalParameter < runtimeParameterTypes.Count
                   && nextPositionalParameter != paramsParameterIndex
                   && bound[nextPositionalParameter] != null)
            {
                nextPositionalParameter++;
            }

            if (nextPositionalParameter < runtimeParameterTypes.Count
                && nextPositionalParameter != paramsParameterIndex)
            {
                bound[nextPositionalParameter] = new SuppliedBoundCallArgument(argument, runtimeParameterTypes[nextPositionalParameter]);
                nextPositionalParameter++;
                continue;
            }

            if (!usesParams)
            {
                boundArguments = Array.Empty<BoundCallArgument>();
                return false;
            }

            paramsArguments.Add(argument);
        }

        var regularParameterCount = usesParams ? paramsParameterIndex : runtimeParameterTypes.Count;
        for (int i = 0; i < regularParameterCount; i++)
        {
            if (bound[i] != null)
            {
                continue;
            }

            if (!runtimeParameterInfos[i].HasDefaultValue)
            {
                boundArguments = Array.Empty<BoundCallArgument>();
                return false;
            }

            bound[i] = new RuntimeDefaultBoundCallArgument(runtimeParameterInfos[i].DefaultValue, runtimeParameterTypes[i]);
            defaultsUsed++;
        }

        if (usesParams)
        {
            if (bound[paramsParameterIndex] != null && paramsArguments.Count > 0)
            {
                boundArguments = Array.Empty<BoundCallArgument>();
                return false;
            }

            if (bound[paramsParameterIndex] == null)
            {
                var paramsParameterType = runtimeParameterTypes[paramsParameterIndex];
                if (!TryGetParamsElementType(paramsParameterType, out var elementType))
                {
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
                }

                if (paramsArguments.Count == 1 && ShouldPassRuntimeParamsArgumentDirectly(paramsArguments[0], paramsParameterType, genericBindings))
                {
                    bound[paramsParameterIndex] = new SuppliedBoundCallArgument(paramsArguments[0], paramsParameterType);
                }
                else
                {
                    bound[paramsParameterIndex] = new ParamsCollectionBoundCallArgument(paramsParameterType, elementType, paramsArguments);
                }
            }
        }

        for (int i = 0; i < runtimeParameterTypes.Count; i++)
        {
            var parameterType = runtimeParameterTypes[i];
            var expectedType = GetByRefElementType(parameterType);

            switch (bound[i])
            {
                case SuppliedBoundCallArgument supplied:
                {
                    var expectsByRef = parameterType.IsByRef;
                    var suppliedByRef = supplied.Argument.Modifier is ArgumentModifier.Ref or ArgumentModifier.Out;
                    if (expectsByRef != suppliedByRef)
                    {
                        boundArguments = Array.Empty<BoundCallArgument>();
                        return false;
                    }

                    if (supplied.Argument.Value is OutVariableDeclarationExpression outVariable)
                    {
                        if (outVariable.Type != null
                            && !AreMethodArgumentTypesCompatible(expectedType, ResolveType(outVariable.Type, _currentGenericParameters), genericBindings))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        score += 8;
                        break;
                    }

                    if (supplied.Argument.Value is DefaultExpression)
                    {
                        score += 8;
                        break;
                    }

                    if (supplied.Argument.Value is LambdaExpression lambda)
                    {
                        if (!TryBindLambdaToRuntimeParameter(expectedType, lambda, genericBindings, out var lambdaScore))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        score += lambdaScore;
                        break;
                    }

                    var argumentType = GetExpressionTypeForBinding(supplied.Argument.Value, expectedType);
                    if (!AreMethodArgumentTypesCompatible(expectedType, argumentType, genericBindings))
                    {
                        boundArguments = Array.Empty<BoundCallArgument>();
                        return false;
                    }

                    score += GetParameterMatchScore(expectedType, argumentType);
                    break;
                }

                case RuntimeDefaultBoundCallArgument:
                    score += 8;
                    break;

                case ParamsCollectionBoundCallArgument paramsBound:
                    foreach (var paramsArgument in paramsBound.Arguments)
                    {
                        if (paramsArgument.Value is SpreadExpression)
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        if (paramsArgument.Value is LambdaExpression lambda)
                        {
                            if (!TryBindLambdaToRuntimeParameter(paramsBound.ElementType, lambda, genericBindings, out var lambdaScore))
                            {
                                boundArguments = Array.Empty<BoundCallArgument>();
                                return false;
                            }

                            score += lambdaScore;
                            continue;
                        }

                        var argumentType = GetExpressionTypeForBinding(paramsArgument.Value, paramsBound.ElementType);
                        if (!AreMethodArgumentTypesCompatible(paramsBound.ElementType, argumentType, genericBindings))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        score += GetParameterMatchScore(paramsBound.ElementType, argumentType);
                    }
                    break;

                default:
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
            }
        }

        boundArguments = bound;
        return true;
    }

    private bool TryBindRuntimeParameters(
        ParameterInfo[] runtimeParameters,
        IReadOnlyList<Argument> suppliedArguments,
        out IReadOnlyList<BoundCallArgument> boundArguments,
        out int score,
        out bool usesParams,
        out int defaultsUsed,
        out Dictionary<string, Type> genericBindings)
    {
        return TryBindRuntimeParameters(
            runtimeParameters,
            runtimeParameters.Select(parameter => parameter.ParameterType).ToArray(),
            suppliedArguments,
            out boundArguments,
            out score,
            out usesParams,
            out defaultsUsed,
            out genericBindings);
    }

    private bool TryBindLambdaToRuntimeParameter(
        Type parameterType,
        LambdaExpression lambda,
        Dictionary<string, Type> genericBindings,
        out int score)
    {
        score = 0;

        parameterType = ApplyRuntimeGenericBindings(GetByRefElementType(parameterType), genericBindings);
        if (TryGetDelegateInvokeMethod(parameterType, out var invokeMethod) && invokeMethod != null)
        {
            var expectedParameterTypes = GetDelegateInvokeParameterTypes(parameterType, invokeMethod)
                .Select(type => ApplyRuntimeGenericBindings(type, genericBindings))
                .ToArray();
            if (expectedParameterTypes.Length != lambda.Parameters.Count)
            {
                return false;
            }

            var lambdaParameterTypes = new Type[lambda.Parameters.Count];
            for (int i = 0; i < lambda.Parameters.Count; i++)
            {
                var parameter = lambda.Parameters[i];
                var hasExplicitType = parameter.Type is not null
                    && parameter.Type is not SimpleTypeReference { Name: "var" };
                var lambdaParameterType = hasExplicitType
                    ? ResolveType(parameter.Type!, _currentGenericParameters)
                    : expectedParameterTypes[i];

                if (hasExplicitType && !AreMethodArgumentTypesCompatible(expectedParameterTypes[i], lambdaParameterType, genericBindings))
                {
                    return false;
                }

                lambdaParameterTypes[i] = lambdaParameterType;
                score += hasExplicitType
                    ? GetParameterMatchScore(expectedParameterTypes[i], lambdaParameterType)
                    : expectedParameterTypes[i].ContainsGenericParameters ? 4 : 8;
            }

            var expectedReturnType = ApplyRuntimeGenericBindings(GetDelegateInvokeReturnType(parameterType, invokeMethod), genericBindings);
            var lambdaReturnType = InferRuntimeLambdaReturnType(lambda, lambdaParameterTypes, expectedReturnType);
            if (expectedReturnType != typeof(void)
                && !AreMethodArgumentTypesCompatible(expectedReturnType, lambdaReturnType, genericBindings))
            {
                return false;
            }

            score += expectedReturnType == typeof(void)
                ? 8
                : GetParameterMatchScore(expectedReturnType, lambdaReturnType);
            score += 4;
            return true;
        }

        if (parameterType == typeof(Delegate) || parameterType == typeof(MulticastDelegate))
        {
            var lambdaParameterTypes = lambda.Parameters.Select(parameter =>
            {
                var hasExplicitType = parameter.Type is not null
                    && parameter.Type is not SimpleTypeReference { Name: "var" };
                return hasExplicitType
                    ? ResolveType(parameter.Type!, _currentGenericParameters)
                    : typeof(object);
            }).ToArray();

            _ = InferRuntimeLambdaReturnType(lambda, lambdaParameterTypes, expectedReturnType: null);
            score = 1 + lambda.Parameters.Count;
            return true;
        }

        return false;
    }

    private Type InferRuntimeLambdaReturnType(
        LambdaExpression lambda,
        IReadOnlyList<Type> parameterTypes,
        Type? expectedReturnType)
    {
        var savedParameters = _parameters;
        var savedParameterTypes = _parameterTypes;
        var savedByRefParameters = _byRefParameters;
        var savedExpectedExpressionType = _expectedExpressionType;

        _parameters = savedParameters != null
            ? new Dictionary<string, int>(savedParameters, StringComparer.Ordinal)
            : new Dictionary<string, int>(StringComparer.Ordinal);
        _parameterTypes = savedParameterTypes != null
            ? new Dictionary<string, Type>(savedParameterTypes, StringComparer.Ordinal)
            : new Dictionary<string, Type>(StringComparer.Ordinal);
        _byRefParameters = savedByRefParameters != null
            ? new HashSet<string>(savedByRefParameters, StringComparer.Ordinal)
            : new HashSet<string>(StringComparer.Ordinal);

        try
        {
            for (int i = 0; i < lambda.Parameters.Count && i < parameterTypes.Count; i++)
            {
                var parameter = lambda.Parameters[i];
                _parameters[parameter.Name] = i;
                _parameterTypes[parameter.Name] = parameterTypes[i];

                if (parameterTypes[i].IsByRef || parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out)
                {
                    _byRefParameters.Add(parameter.Name);
                }
            }

            _expectedExpressionType = expectedReturnType != null
                && expectedReturnType != typeof(void)
                && !expectedReturnType.ContainsGenericParameters
                    ? expectedReturnType
                    : null;

            if (lambda.ExpressionBody != null)
            {
                return GetExpressionType(lambda.ExpressionBody);
            }

            if (lambda.BlockBody != null)
            {
                return InferLambdaBlockReturnType(lambda.BlockBody);
            }

            return typeof(void);
        }
        finally
        {
            _parameters = savedParameters;
            _parameterTypes = savedParameterTypes;
            _byRefParameters = savedByRefParameters;
            _expectedExpressionType = savedExpectedExpressionType;
        }
    }

    private static IReadOnlyList<BoundCallArgument> RetargetRuntimeBoundArguments(
        IReadOnlyList<BoundCallArgument> boundArguments,
        IReadOnlyList<Type> runtimeParameterTypes)
    {
        var retargeted = new BoundCallArgument[boundArguments.Count];
        for (int i = 0; i < boundArguments.Count; i++)
        {
            retargeted[i] = boundArguments[i] switch
            {
                SuppliedBoundCallArgument supplied => new SuppliedBoundCallArgument(supplied.Argument, runtimeParameterTypes[i]),
                RuntimeDefaultBoundCallArgument runtimeDefault => new RuntimeDefaultBoundCallArgument(runtimeDefault.Value, runtimeParameterTypes[i]),
                ParamsCollectionBoundCallArgument paramsBound => new ParamsCollectionBoundCallArgument(
                    runtimeParameterTypes[i],
                    TryGetParamsElementType(runtimeParameterTypes[i], out var elementType) ? elementType : paramsBound.ElementType,
                    paramsBound.Arguments),
                _ => boundArguments[i]
            };
        }

        return retargeted;
    }

    private static MethodInfo? CloseRuntimeGenericMethod(MethodInfo genericMethodDefinition, IReadOnlyDictionary<string, Type> genericBindings)
    {
        var typeArguments = new Type[genericMethodDefinition.GetGenericArguments().Length];
        for (int i = 0; i < typeArguments.Length; i++)
        {
            var genericParameter = genericMethodDefinition.GetGenericArguments()[i];
            if (!genericBindings.TryGetValue(genericParameter.Name, out var typeArgument))
            {
                return null;
            }

            typeArguments[i] = typeArgument;
        }

        try
        {
            return genericMethodDefinition.MakeGenericMethod(typeArguments);
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private static Type ApplyRuntimeGenericBindings(Type type, IReadOnlyDictionary<string, Type> genericBindings)
    {
        if (type.IsGenericParameter && genericBindings.TryGetValue(type.Name, out var boundType))
        {
            return boundType;
        }

        if (type.IsByRef)
        {
            return ApplyRuntimeGenericBindings(type.GetElementType()!, genericBindings).MakeByRefType();
        }

        if (type.IsArray)
        {
            var elementType = ApplyRuntimeGenericBindings(type.GetElementType()!, genericBindings);
            return type.GetArrayRank() == 1 ? elementType.MakeArrayType() : elementType.MakeArrayType(type.GetArrayRank());
        }

        if (!type.IsGenericType)
        {
            return type;
        }

        Type genericTypeDefinition;
        try
        {
            genericTypeDefinition = type.GetGenericTypeDefinition();
        }
        catch (NotSupportedException)
        {
            return type;
        }

        var substitutedArguments = type.GetGenericArguments()
            .Select(argument => ApplyRuntimeGenericBindings(argument, genericBindings))
            .ToArray();

        try
        {
            return genericTypeDefinition.MakeGenericType(substitutedArguments);
        }
        catch (ArgumentException)
        {
            return type;
        }
    }

    private bool ShouldPassRuntimeParamsArgumentDirectly(Argument argument, Type parameterType, Dictionary<string, Type> genericBindings)
    {
        if (argument.Value is DefaultExpression)
        {
            return true;
        }

        if (argument.Value is LambdaExpression lambda)
        {
            return TryBindLambdaToRuntimeParameter(parameterType, lambda, genericBindings, out _);
        }

        var argumentType = GetExpressionType(argument.Value);
        return AreMethodArgumentTypesCompatible(parameterType, argumentType, genericBindings);
    }
}
