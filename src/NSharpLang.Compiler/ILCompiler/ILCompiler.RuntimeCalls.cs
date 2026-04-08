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

    private sealed record BoundRuntimeMethodCall(MethodInfo Method, IReadOnlyList<BoundCallArgument> Arguments);

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

        MethodInfo[] candidates;
        try
        {
            candidates = declaringType
                .GetMethods(bindingFlags)
                .Where(method => method.Name == methodName)
                .ToArray();
        }
        catch (NotSupportedException) when (declaringType.IsGenericType && !declaringType.IsGenericTypeDefinition)
        {
            candidates = declaringType.GetGenericTypeDefinition()
                .GetMethods(bindingFlags)
                .Where(method => method.Name == methodName)
                .Select(method => TypeBuilder.GetMethod(declaringType, method))
                .ToArray();
        }

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

            if (!TryBindRuntimeParameters(
                    candidateMethod.GetParameters(),
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

                boundArguments = RetargetRuntimeBoundArguments(boundArguments, candidateMethod.GetParameters());
            }

            var isGeneric = candidateMethod.IsGenericMethod;
            if (best == null
                || score > bestScore
                || (score == bestScore && bestIsGeneric && !isGeneric)
                || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams && !usesParams)
                || (score == bestScore && bestIsGeneric == isGeneric && bestUsesParams == usesParams && defaultsUsed < bestDefaultsUsed))
            {
                best = new BoundRuntimeMethodCall(candidateMethod, boundArguments);
                bestScore = score;
                bestUsesParams = usesParams;
                bestDefaultsUsed = defaultsUsed;
                bestIsGeneric = isGeneric;
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

    private bool TryBindRuntimeParameters(
        ParameterInfo[] runtimeParameters,
        IReadOnlyList<Argument> suppliedArguments,
        out IReadOnlyList<BoundCallArgument> boundArguments,
        out int score,
        out bool usesParams,
        out int defaultsUsed,
        out Dictionary<string, Type> genericBindings)
    {
        var bound = new BoundCallArgument[runtimeParameters.Length];
        score = 0;
        defaultsUsed = 0;
        genericBindings = new Dictionary<string, Type>(StringComparer.Ordinal);
        usesParams = runtimeParameters.Length > 0 && runtimeParameters[^1].IsDefined(typeof(ParamArrayAttribute), inherit: false);

        var paramsParameterIndex = usesParams ? runtimeParameters.Length - 1 : -1;
        var nextPositionalParameter = 0;
        var paramsArguments = new List<Argument>();

        foreach (var argument in suppliedArguments)
        {
            if (argument.Name != null)
            {
                var parameterIndex = Array.FindIndex(runtimeParameters, parameter => parameter.Name == argument.Name);
                if (parameterIndex < 0 || bound[parameterIndex] != null)
                {
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
                }

                bound[parameterIndex] = new SuppliedBoundCallArgument(argument, runtimeParameters[parameterIndex].ParameterType);
                continue;
            }

            while (nextPositionalParameter < runtimeParameters.Length
                   && nextPositionalParameter != paramsParameterIndex
                   && bound[nextPositionalParameter] != null)
            {
                nextPositionalParameter++;
            }

            if (nextPositionalParameter < runtimeParameters.Length
                && nextPositionalParameter != paramsParameterIndex)
            {
                bound[nextPositionalParameter] = new SuppliedBoundCallArgument(argument, runtimeParameters[nextPositionalParameter].ParameterType);
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

        var regularParameterCount = usesParams ? paramsParameterIndex : runtimeParameters.Length;
        for (int i = 0; i < regularParameterCount; i++)
        {
            if (bound[i] != null)
            {
                continue;
            }

            if (!runtimeParameters[i].HasDefaultValue)
            {
                boundArguments = Array.Empty<BoundCallArgument>();
                return false;
            }

            bound[i] = new RuntimeDefaultBoundCallArgument(runtimeParameters[i].DefaultValue, runtimeParameters[i].ParameterType);
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
                var paramsParameterType = runtimeParameters[paramsParameterIndex].ParameterType;
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

        for (int i = 0; i < runtimeParameters.Length; i++)
        {
            var parameterType = runtimeParameters[i].ParameterType;
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

                    var argumentType = GetExpressionType(supplied.Argument.Value);
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

                        var argumentType = GetExpressionType(paramsArgument.Value);
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

    private static IReadOnlyList<BoundCallArgument> RetargetRuntimeBoundArguments(
        IReadOnlyList<BoundCallArgument> boundArguments,
        ParameterInfo[] runtimeParameters)
    {
        var retargeted = new BoundCallArgument[boundArguments.Count];
        for (int i = 0; i < boundArguments.Count; i++)
        {
            retargeted[i] = boundArguments[i] switch
            {
                SuppliedBoundCallArgument supplied => new SuppliedBoundCallArgument(supplied.Argument, runtimeParameters[i].ParameterType),
                RuntimeDefaultBoundCallArgument runtimeDefault => new RuntimeDefaultBoundCallArgument(runtimeDefault.Value, runtimeParameters[i].ParameterType),
                ParamsCollectionBoundCallArgument paramsBound => new ParamsCollectionBoundCallArgument(
                    runtimeParameters[i].ParameterType,
                    TryGetParamsElementType(runtimeParameters[i].ParameterType, out var elementType) ? elementType : paramsBound.ElementType,
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

    private bool ShouldPassRuntimeParamsArgumentDirectly(Argument argument, Type parameterType, Dictionary<string, Type> genericBindings)
    {
        if (argument.Value is DefaultExpression)
        {
            return true;
        }

        var argumentType = GetExpressionType(argument.Value);
        return AreMethodArgumentTypesCompatible(parameterType, argumentType, genericBindings);
    }
}
