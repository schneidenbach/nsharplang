using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    private enum GenericLocalFunctionCaptureKind
    {
        Local,
        Parameter,
        ClosureField
    }

    private sealed record GenericLocalFunctionCapture(
        string Name,
        GenericLocalFunctionCaptureKind Kind,
        Type CaptureParameterType,
        bool IsLifted,
        LocalBuilder? Local,
        int ParameterIndex,
        FieldInfo? ClosureField);

    private readonly Dictionary<FunctionDeclaration, MethodBuilder> _genericLocalFunctionBuilders = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<FunctionDeclaration, TypeBuilder> _genericLocalFunctionOwners = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<FunctionDeclaration, GenericTypeParameterBuilder[]?> _genericLocalFunctionGenericParameters = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<FunctionDeclaration, IReadOnlyList<GenericLocalFunctionCapture>> _genericLocalFunctionCaptures = new(ReferenceEqualityComparer.Instance);
    private int _localFunctionMethodCounter = 0;

    private void DeclareGenericLocalFunction(LocalFunctionStatement localFunction)
    {
        var ownerType = _currentTypeBuilder ?? _programType
            ?? throw new InvalidOperationException("No owning type available for generic local function emission");

        var localFunctionLambda = new LambdaExpression(
            localFunction.Function.Parameters,
            localFunction.Function.ExpressionBody,
            localFunction.Function.Body,
            localFunction.Line,
            localFunction.Column);
        var emitAsStatic = localFunction.Function.Modifiers.HasFlag(Modifiers.Static) || !_currentHasThis;
        var captureNames = AnalyzeCapturedVariables(localFunctionLambda);
        if (!emitAsStatic)
        {
            captureNames.Remove(ThisCaptureName);
        }

        var captures = captureNames
            .OrderBy(name => name, StringComparer.Ordinal)
            .Select(ResolveGenericLocalFunctionCapture)
            .ToArray();

        var methodAttributes = MethodAttributes.Private | MethodAttributes.HideBySig;
        if (emitAsStatic)
        {
            methodAttributes |= MethodAttributes.Static;
        }

        var methodBuilder = ownerType.DefineMethod(
            $"<{localFunction.Function.Name}>g__{_localFunctionMethodCounter++}",
            methodAttributes);

        GenericTypeParameterBuilder[]? localGenericParameters = null;
        if (localFunction.Function.TypeParameters is { Count: > 0 })
        {
            localGenericParameters = methodBuilder.DefineGenericParameters(
                localFunction.Function.TypeParameters.Select(typeParameter => typeParameter.Name).ToArray());

            if (localFunction.Function.Constraints != null)
            {
                var availableGenericParameters = CombineGenericParameters(localGenericParameters, _currentGenericParameters);
                foreach (var constraint in localFunction.Function.Constraints)
                {
                    var typeParam = localGenericParameters.FirstOrDefault(parameter => parameter.Name == constraint.TypeParameter);
                    if (typeParam != null)
                    {
                        ApplyGenericConstraints(typeParam, constraint, availableGenericParameters);
                    }
                }
            }
        }

        var combinedGenericParameters = CombineGenericParameters(localGenericParameters, _currentGenericParameters);
        var returnType = GetLocalFunctionReturnType(localFunction.Function);
        var declaredParameterTypes = localFunction.Function.Parameters
            .Select(parameter => ResolveParameterType(parameter, combinedGenericParameters))
            .ToArray();
        var parameterTypes = captures.Select(capture => capture.CaptureParameterType)
            .Concat(declaredParameterTypes)
            .ToArray();

        methodBuilder.SetReturnType(returnType);
        methodBuilder.SetParameters(parameterTypes);
        ApplyCustomAttributes(methodBuilder.SetCustomAttribute, localFunction.Function.Attributes);

        for (int i = 0; i < captures.Length; i++)
        {
            methodBuilder.DefineParameter(i + 1, ParameterAttributes.None, $"__capture_{captures[i].Name}");
        }

        for (int i = 0; i < localFunction.Function.Parameters.Count; i++)
        {
            var parameter = localFunction.Function.Parameters[i];
            var parameterBuilder = methodBuilder.DefineParameter(captures.Length + i + 1, GetParameterAttributes(parameter), parameter.Name);
            ApplyParameterAttributes(parameterBuilder, parameter);
        }

        _genericLocalFunctionBuilders[localFunction.Function] = methodBuilder;
        _genericLocalFunctionOwners[localFunction.Function] = ownerType;
        _genericLocalFunctionGenericParameters[localFunction.Function] = localGenericParameters;
        _genericLocalFunctionCaptures[localFunction.Function] = captures;
    }

    private GenericLocalFunctionCapture ResolveGenericLocalFunctionCapture(string name)
    {
        if (_locals != null && _locals.TryGetValue(name, out var local))
        {
            var isLifted = IsLiftedIdentifier(name);
            return new GenericLocalFunctionCapture(
                name,
                GenericLocalFunctionCaptureKind.Local,
                isLifted ? GetStrongBoxValueType(local.LocalType).MakeByRefType() : local.LocalType,
                isLifted,
                local,
                ParameterIndex: -1,
                ClosureField: null);
        }

        if (_parameters != null && _parameters.TryGetValue(name, out var parameterIndex))
        {
            if (_parameterTypes == null || !_parameterTypes.TryGetValue(name, out var parameterType))
            {
                throw new InvalidOperationException($"Could not resolve parameter type for captured variable {name}");
            }

            var captureType = _byRefParameters != null && _byRefParameters.Contains(name)
                ? parameterType.MakeByRefType()
                : parameterType;

            return new GenericLocalFunctionCapture(
                name,
                GenericLocalFunctionCaptureKind.Parameter,
                captureType,
                IsLifted: false,
                Local: null,
                ParameterIndex: parameterIndex,
                ClosureField: null);
        }

        if (_closureFields != null && _closureFields.TryGetValue(name, out var closureField))
        {
            var isLifted = IsLiftedClosureField(name);
            return new GenericLocalFunctionCapture(
                name,
                GenericLocalFunctionCaptureKind.ClosureField,
                isLifted ? GetStrongBoxValueType(closureField.FieldType).MakeByRefType() : closureField.FieldType,
                isLifted,
                Local: null,
                ParameterIndex: -1,
                ClosureField: closureField);
        }

        throw new InvalidOperationException($"Could not resolve captured variable {name} for generic local function");
    }

    private int RegisterGenericLocalFunctionCaptureContext(FunctionDeclaration function, int startIndex)
    {
        if (_currentIL == null || _locals == null || _parameters == null || _parameterTypes == null || _byRefParameters == null)
        {
            throw new InvalidOperationException("No capture context available for generic local function emission");
        }

        if (!_genericLocalFunctionCaptures.TryGetValue(function, out var captures))
        {
            return 0;
        }

        for (int i = 0; i < captures.Count; i++)
        {
            var capture = captures[i];
            var captureIndex = startIndex + i;

            if (capture.CaptureParameterType.IsByRef)
            {
                _parameters[capture.Name] = captureIndex;
                _parameterTypes[capture.Name] = GetByRefElementType(capture.CaptureParameterType);
                _byRefParameters.Add(capture.Name);
                continue;
            }

            if (capture.IsLifted)
            {
                var liftedLocal = _currentIL.DeclareLocal(capture.CaptureParameterType);
                _locals[capture.Name] = liftedLocal;
                _liftedIdentifiers ??= new HashSet<string>();
                _liftedIdentifiers.Add(capture.Name);
                EmitLoadArgument(captureIndex);
                _currentIL.Emit(OpCodes.Stloc, liftedLocal);
                continue;
            }

            if (_liftLocalsIntoBoxes)
            {
                var liftedCaptureLocal = DeclareNamedLocal(capture.Name, capture.CaptureParameterType);
                EmitLoadArgument(captureIndex);
                EmitInitializeNamedLocal(liftedCaptureLocal, capture.CaptureParameterType, emitDefaultValue: false, initializer: null, valueAlreadyOnStack: true);
                continue;
            }

            var captureLocal = _currentIL.DeclareLocal(capture.CaptureParameterType);
            _locals[capture.Name] = captureLocal;
            EmitLoadArgument(captureIndex);
            _currentIL.Emit(OpCodes.Stloc, captureLocal);
        }

        return captures.Count;
    }

    private void EmitGenericLocalFunctionCaptureArgument(GenericLocalFunctionCapture capture)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        switch (capture.Kind)
        {
            case GenericLocalFunctionCaptureKind.Local:
                if (capture.Local == null)
                {
                    throw new InvalidOperationException($"Captured local {capture.Name} did not have a resolved storage location");
                }

                if (capture.CaptureParameterType.IsByRef)
                {
                    if (capture.IsLifted)
                    {
                        EmitLoadLiftedLocalAddress(capture.Local);
                    }
                    else
                    {
                        _currentIL.Emit(OpCodes.Ldloca_S, capture.Local);
                    }

                    return;
                }

                _currentIL.Emit(OpCodes.Ldloc, capture.Local);
                return;

            case GenericLocalFunctionCaptureKind.Parameter:
                EmitLoadArgument(capture.ParameterIndex);
                return;

            case GenericLocalFunctionCaptureKind.ClosureField:
                if (capture.ClosureField == null)
                {
                    throw new InvalidOperationException($"Captured closure field {capture.Name} did not have a resolved backing field");
                }

                if (capture.CaptureParameterType.IsByRef)
                {
                    EmitLoadLiftedClosureFieldAddress(capture.ClosureField);
                    return;
                }

                EmitLoadArgument(0);
                _currentIL.Emit(OpCodes.Ldfld, capture.ClosureField);
                return;

            default:
                throw new InvalidOperationException($"Unsupported generic local function capture kind {capture.Kind}");
        }
    }

    private void EmitGenericLocalFunctionReceiver(MethodInfo method)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        if (method.IsStatic)
        {
            return;
        }

        if (!_currentHasThis)
        {
            throw new InvalidOperationException($"Generic local function {method.Name} requires an instance receiver in the current context");
        }

        EmitLoadArgument(0);
    }

    private Type GetGenericLocalFunctionCallReturnType(FunctionDeclaration declaration, CallExpression call)
    {
        if (declaration.ReturnType == null)
        {
            return typeof(object);
        }

        if (declaration.TypeParameters is not { Count: > 0 })
        {
            return ResolveType(declaration.ReturnType, _currentGenericParameters);
        }

        if (!TryBindGenericLocalFunctionTypeArguments(declaration, call, out var typeBindings))
        {
            return typeof(object);
        }

        return ResolveGenericLocalFunctionTypeReference(declaration.ReturnType, typeBindings);
    }

    private bool TryBindGenericLocalFunctionTypeArguments(
        FunctionDeclaration declaration,
        CallExpression call,
        out Dictionary<string, Type> typeBindings)
    {
        typeBindings = new Dictionary<string, Type>(StringComparer.Ordinal);
        var localTypeParameterNames = declaration.TypeParameters?
            .Select(typeParameter => typeParameter.Name)
            .ToHashSet(StringComparer.Ordinal)
            ?? new HashSet<string>(StringComparer.Ordinal);

        if (call.TypeArguments != null && call.TypeArguments.Count > 0)
        {
            if (declaration.TypeParameters == null || call.TypeArguments.Count != declaration.TypeParameters.Count)
            {
                return false;
            }

            for (int i = 0; i < call.TypeArguments.Count; i++)
            {
                typeBindings[declaration.TypeParameters[i].Name] = ResolveType(call.TypeArguments[i], _currentGenericParameters);
            }

            return true;
        }

        var nextPositionalArgument = 0;
        foreach (var parameter in declaration.Parameters)
        {
            Argument? suppliedArgument = null;
            if (call.Arguments.Any(argument => argument.Name != null))
            {
                suppliedArgument = call.Arguments.FirstOrDefault(argument => argument.Name == parameter.Name);
                if (suppliedArgument == null)
                {
                    while (nextPositionalArgument < call.Arguments.Count && call.Arguments[nextPositionalArgument].Name != null)
                    {
                        nextPositionalArgument++;
                    }

                    if (nextPositionalArgument < call.Arguments.Count)
                    {
                        suppliedArgument = call.Arguments[nextPositionalArgument++];
                    }
                }
            }
            else if (nextPositionalArgument < call.Arguments.Count)
            {
                suppliedArgument = call.Arguments[nextPositionalArgument++];
            }

            if (suppliedArgument == null)
            {
                continue;
            }

            if (!TryCollectGenericLocalFunctionBindings(parameter.Type, GetExpressionType(suppliedArgument.Value), localTypeParameterNames, typeBindings))
            {
                return false;
            }
        }

        if (declaration.TypeParameters == null)
        {
            return false;
        }

        foreach (var typeParameter in declaration.TypeParameters)
        {
            if (!typeBindings.ContainsKey(typeParameter.Name))
            {
                return false;
            }
        }

        return true;
    }

    private bool TryCollectGenericLocalFunctionBindings(
        TypeReference parameterType,
        Type argumentType,
        IReadOnlySet<string> localTypeParameterNames,
        Dictionary<string, Type> typeBindings)
    {
        argumentType = GetByRefElementType(argumentType);

        switch (parameterType)
        {
            case SimpleTypeReference simpleType:
                if (!localTypeParameterNames.Contains(simpleType.Name))
                {
                    return true;
                }

                if (typeBindings.TryGetValue(simpleType.Name, out var existingBinding))
                {
                    return existingBinding == argumentType;
                }

                typeBindings[simpleType.Name] = argumentType;
                return true;

            case ArrayTypeReference arrayType:
                return argumentType.IsArray
                    && argumentType.GetElementType() is { } arrayElementType
                    && TryCollectGenericLocalFunctionBindings(arrayType.ElementType, arrayElementType, localTypeParameterNames, typeBindings);

            case NullableTypeReference nullableType:
                var nullableArgumentType = Nullable.GetUnderlyingType(argumentType) ?? argumentType;
                return TryCollectGenericLocalFunctionBindings(nullableType.InnerType, nullableArgumentType, localTypeParameterNames, typeBindings);

            case TupleTypeReference tupleType:
                if (!argumentType.IsGenericType)
                {
                    return false;
                }

                var tupleArgumentTypes = argumentType.GetGenericArguments();
                if (tupleArgumentTypes.Length != tupleType.Elements.Count)
                {
                    return false;
                }

                for (int i = 0; i < tupleType.Elements.Count; i++)
                {
                    if (!TryCollectGenericLocalFunctionBindings(tupleType.Elements[i].Type, tupleArgumentTypes[i], localTypeParameterNames, typeBindings))
                    {
                        return false;
                    }
                }

                return true;

            case GenericTypeReference genericType:
                var genericDefinition = ResolveGenericTypeDefinition(genericType.Name, genericType.TypeArguments.Count);
                if (genericDefinition == null)
                {
                    return false;
                }

                var matchedArgumentType = FindConstructedGenericMatch(genericDefinition, argumentType);
                if (matchedArgumentType == null)
                {
                    return false;
                }

                var genericArgumentTypes = matchedArgumentType.GetGenericArguments();
                for (int i = 0; i < genericType.TypeArguments.Count; i++)
                {
                    if (!TryCollectGenericLocalFunctionBindings(genericType.TypeArguments[i], genericArgumentTypes[i], localTypeParameterNames, typeBindings))
                    {
                        return false;
                    }
                }

                return true;

            case FunctionTypeReference functionType:
                if (!TryGetDelegateInvokeMethod(argumentType, out var invokeMethod) || invokeMethod == null)
                {
                    return false;
                }

                var invokeParameters = invokeMethod.GetParameters();
                if (invokeParameters.Length != functionType.ParameterTypes.Count)
                {
                    return false;
                }

                for (int i = 0; i < functionType.ParameterTypes.Count; i++)
                {
                    if (!TryCollectGenericLocalFunctionBindings(functionType.ParameterTypes[i], invokeParameters[i].ParameterType, localTypeParameterNames, typeBindings))
                    {
                        return false;
                    }
                }

                return TryCollectGenericLocalFunctionBindings(functionType.ReturnType, invokeMethod.ReturnType, localTypeParameterNames, typeBindings);

            default:
                return true;
        }
    }

    private Type ResolveGenericLocalFunctionTypeReference(TypeReference typeReference, IReadOnlyDictionary<string, Type> typeBindings)
    {
        switch (typeReference)
        {
            case SimpleTypeReference simpleType when typeBindings.TryGetValue(simpleType.Name, out var boundType):
                return boundType;

            case ArrayTypeReference arrayType:
                return ResolveGenericLocalFunctionTypeReference(arrayType.ElementType, typeBindings).MakeArrayType();

            case NullableTypeReference nullableType:
                return typeof(Nullable<>).MakeGenericType(ResolveGenericLocalFunctionTypeReference(nullableType.InnerType, typeBindings));

            case TupleTypeReference tupleType:
                var tupleElementTypes = tupleType.Elements
                    .Select(element => ResolveGenericLocalFunctionTypeReference(element.Type, typeBindings))
                    .ToArray();
                return tupleElementTypes.Length switch
                {
                    1 => typeof(ValueTuple<>).MakeGenericType(tupleElementTypes),
                    2 => typeof(ValueTuple<,>).MakeGenericType(tupleElementTypes),
                    3 => typeof(ValueTuple<,,>).MakeGenericType(tupleElementTypes),
                    4 => typeof(ValueTuple<,,,>).MakeGenericType(tupleElementTypes),
                    5 => typeof(ValueTuple<,,,,>).MakeGenericType(tupleElementTypes),
                    6 => typeof(ValueTuple<,,,,,>).MakeGenericType(tupleElementTypes),
                    7 => typeof(ValueTuple<,,,,,,>).MakeGenericType(tupleElementTypes),
                    _ => typeof(object)
                };

            case GenericTypeReference genericType:
                var genericDefinition = ResolveGenericTypeDefinition(genericType.Name, genericType.TypeArguments.Count);
                if (genericDefinition == null)
                {
                    return typeof(object);
                }

                var resolvedTypeArguments = genericType.TypeArguments
                    .Select(typeArgument => ResolveGenericLocalFunctionTypeReference(typeArgument, typeBindings))
                    .ToArray();
                return genericDefinition.MakeGenericType(resolvedTypeArguments);

            case FunctionTypeReference functionType:
                var parameterTypes = functionType.ParameterTypes
                    .Select(parameterType => ResolveGenericLocalFunctionTypeReference(parameterType, typeBindings))
                    .ToArray();
                var returnType = ResolveGenericLocalFunctionTypeReference(functionType.ReturnType, typeBindings);
                return CreateDelegateType(parameterTypes, returnType);

            default:
                return ResolveType(typeReference, _currentGenericParameters);
        }
    }

    private bool TryBindGenericLocalFunctionParameters(
        IReadOnlyList<Parameter> declaredParameters,
        IReadOnlyDictionary<string, Type> typeBindings,
        IReadOnlyList<Argument> suppliedArguments,
        out IReadOnlyList<BoundCallArgument> boundArguments)
    {
        var resolvedParameterTypes = declaredParameters
            .Select(parameter =>
            {
                var parameterType = ResolveGenericLocalFunctionTypeReference(parameter.Type, typeBindings);
                return parameter.Modifier is Ast.ParameterModifier.Ref or Ast.ParameterModifier.Out
                    ? parameterType.MakeByRefType()
                    : parameterType;
            })
            .ToArray();
        var bound = new BoundCallArgument[resolvedParameterTypes.Length];
        var usesParams = declaredParameters.Count > 0 && declaredParameters[^1].Modifier == Ast.ParameterModifier.Params;
        var paramsParameterIndex = usesParams ? resolvedParameterTypes.Length - 1 : -1;
        var nextPositionalParameter = 0;
        var paramsArguments = new List<Argument>();

        foreach (var argument in suppliedArguments)
        {
            if (argument.Name != null)
            {
                var parameterIndex = Enumerable.Range(0, declaredParameters.Count)
                    .FirstOrDefault(index => declaredParameters[index].Name == argument.Name, -1);
                if (parameterIndex < 0 || parameterIndex >= declaredParameters.Count || bound[parameterIndex] != null)
                {
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
                }

                bound[parameterIndex] = new SuppliedBoundCallArgument(argument, resolvedParameterTypes[parameterIndex]);
                continue;
            }

            while (nextPositionalParameter < resolvedParameterTypes.Length
                   && nextPositionalParameter != paramsParameterIndex
                   && bound[nextPositionalParameter] != null)
            {
                nextPositionalParameter++;
            }

            if (nextPositionalParameter < resolvedParameterTypes.Length
                && nextPositionalParameter != paramsParameterIndex)
            {
                bound[nextPositionalParameter] = new SuppliedBoundCallArgument(argument, resolvedParameterTypes[nextPositionalParameter]);
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

        var regularParameterCount = usesParams ? paramsParameterIndex : resolvedParameterTypes.Length;
        for (int i = 0; i < regularParameterCount; i++)
        {
            if (bound[i] != null)
            {
                continue;
            }

            var defaultValue = declaredParameters[i].DefaultValue;
            if (defaultValue == null)
            {
                boundArguments = Array.Empty<BoundCallArgument>();
                return false;
            }

            bound[i] = new ExpressionBoundCallArgument(defaultValue, resolvedParameterTypes[i]);
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
                var paramsParameterType = resolvedParameterTypes[paramsParameterIndex];
                if (!TryGetParamsElementType(paramsParameterType, out var elementType))
                {
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
                }

                if (paramsArguments.Count == 1 && ShouldPassParamsArgumentDirectly(paramsArguments[0], paramsParameterType))
                {
                    bound[paramsParameterIndex] = new SuppliedBoundCallArgument(paramsArguments[0], paramsParameterType);
                }
                else
                {
                    bound[paramsParameterIndex] = new ParamsCollectionBoundCallArgument(paramsParameterType, elementType, paramsArguments);
                }
            }
        }

        for (int i = 0; i < resolvedParameterTypes.Length; i++)
        {
            var parameterType = resolvedParameterTypes[i];
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
                        if (outVariable.Type != null && !IsParameterTypeCompatible(expectedType, ResolveType(outVariable.Type, _currentGenericParameters)))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        break;
                    }

                    if (supplied.Argument.Value is DefaultExpression)
                    {
                        break;
                    }

                    var argumentType = GetExpressionType(supplied.Argument.Value);
                    if (!IsParameterTypeCompatible(expectedType, argumentType))
                    {
                        boundArguments = Array.Empty<BoundCallArgument>();
                        return false;
                    }

                    break;
                }

                case ExpressionBoundCallArgument expressionBound:
                    if (expressionBound.Expression is DefaultExpression)
                    {
                        break;
                    }

                    if (!IsParameterTypeCompatible(expectedType, GetExpressionType(expressionBound.Expression)))
                    {
                        boundArguments = Array.Empty<BoundCallArgument>();
                        return false;
                    }

                    break;

                case ParamsCollectionBoundCallArgument paramsBound:
                    foreach (var paramsArgument in paramsBound.Arguments)
                    {
                        if (paramsArgument.Value is SpreadExpression)
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }

                        if (!IsParameterTypeCompatible(paramsBound.ElementType, GetExpressionType(paramsArgument.Value)))
                        {
                            boundArguments = Array.Empty<BoundCallArgument>();
                            return false;
                        }
                    }

                    break;

                case null:
                    boundArguments = Array.Empty<BoundCallArgument>();
                    return false;
            }
        }

        boundArguments = bound;
        return true;
    }

    private (MethodInfo? Method, Type[]? TypeArguments) CreateGenericLocalFunctionCandidate(FunctionDeclaration declaration, MethodBuilder methodBuilder, CallExpression call)
    {
        if (declaration.TypeParameters is not { Count: > 0 })
        {
            return call.TypeArguments is { Count: > 0 }
                ? (null, null)
                : (methodBuilder, null);
        }

        Type[]? typeArguments;
        if (call.TypeArguments != null && call.TypeArguments.Count > 0)
        {
            if (call.TypeArguments.Count != declaration.TypeParameters.Count)
            {
                return (null, null);
            }

            typeArguments = call.TypeArguments
                .Select(typeArgument => ResolveType(typeArgument, _currentGenericParameters))
                .ToArray();
        }
        else
        {
            if (!TryBindGenericLocalFunctionTypeArguments(declaration, call, out var typeBindings))
            {
                return (null, null);
            }

            typeArguments = declaration.TypeParameters
                .Select(typeParameter => typeBindings[typeParameter.Name])
                .ToArray();
        }

        if (typeArguments == null)
        {
            return (null, null);
        }

        try
        {
            return (methodBuilder.MakeGenericMethod(typeArguments), typeArguments);
        }
        catch (ArgumentException)
        {
            return (null, null);
        }
    }

    private void EmitGenericLocalFunctionBody(LocalFunctionStatement localFunction)
    {
        if (!_genericLocalFunctionBuilders.TryGetValue(localFunction.Function, out var methodBuilder))
        {
            throw new InvalidOperationException($"Generic local function {localFunction.Function.Name} was not declared");
        }

        var savedIL = _currentIL;
        var savedLocals = _locals;
        var savedParameters = _parameters;
        var savedParameterTypes = _parameterTypes;
        var savedByRefParameters = _byRefParameters;
        var savedCurrentGenericParameters = _currentGenericParameters;
        var savedCurrentReturnType = _currentReturnType;
        var savedExpectedExpressionType = _expectedExpressionType;
        var savedCurrentAsyncReturnType = _currentAsyncReturnType;
        var savedCurrentAsyncResultType = _currentAsyncResultType;
        var savedCurrentAsyncReturnsValueTask = _currentAsyncReturnsValueTask;
        var savedCurrentGeneratorReturnType = _currentGeneratorReturnType;
        var savedCurrentYieldElementType = _currentYieldElementType;
        var savedCurrentYieldListLocal = _currentYieldListLocal;
        var savedCurrentYieldBreakLabel = _currentYieldBreakLabel;
        var savedCurrentTypeBuilder = _currentTypeBuilder;
        var savedClosureFields = _closureFields;
        var savedLiftLocalsIntoBoxes = _liftLocalsIntoBoxes;
        var savedLiftedIdentifiers = _liftedIdentifiers;
        var savedLiftedClosureFields = _liftedClosureFields;
        var savedPendingLocalFunctionDefinition = _pendingLocalFunctionDefinition;
        var savedLocalFunctionDeclarations = _localFunctionDeclarations;
        var savedCurrentHasThis = _currentHasThis;

        try
        {
            _currentIL = methodBuilder.GetILGenerator();
            _currentTypeBuilder = _genericLocalFunctionOwners[localFunction.Function];
            _closureFields = methodBuilder.IsStatic ? null : savedClosureFields;
            _pendingLocalFunctionDefinition = localFunction.Function;

            var combinedGenericParameters = CombineGenericParameters(
                _genericLocalFunctionGenericParameters[localFunction.Function],
                savedCurrentGenericParameters);
            _currentGenericParameters = combinedGenericParameters;

            var returnType = GetLocalFunctionReturnType(localFunction.Function);
            var bodyReturnType = returnType;
            if (localFunction.Function.Modifiers.HasFlag(Modifiers.Async)
                && TryUnwrapAsyncReturnType(returnType, out var asyncResultType, out var returnsValueTask))
            {
                _currentAsyncReturnType = returnType;
                _currentAsyncResultType = asyncResultType;
                _currentAsyncReturnsValueTask = returnsValueTask;
                bodyReturnType = asyncResultType ?? typeof(void);
            }

            InitializeBodyContext(bodyReturnType, ContainsNestedFunction(localFunction.Function.Body)
                || (localFunction.Function.ExpressionBody != null && ContainsNestedFunction(localFunction.Function.ExpressionBody)));
            _currentHasThis = !methodBuilder.IsStatic;
            _liftedClosureFields = methodBuilder.IsStatic ? null : savedLiftedClosureFields;

            if (localFunction.Function.Modifiers.HasFlag(Modifiers.Generator))
            {
                if (!TryGetSequenceElementType(returnType, out var yieldElementType, out _))
                {
                    throw new InvalidOperationException($"Generator local function {localFunction.Function.Name} must return an enumerable sequence type, but resolved to {returnType}");
                }

                _currentGeneratorReturnType = returnType;
                _currentYieldElementType = yieldElementType;
                _currentYieldBreakLabel = _currentIL.DefineLabel();
                var listType = typeof(List<>).MakeGenericType(yieldElementType);
                _currentYieldListLocal = _currentIL.DeclareLocal(listType);
                var listCtor = ResolveCollectionConstructor(listType, constructor => HasParameterCount(constructor, 0))
                    ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
                _currentIL.Emit(OpCodes.Newobj, listCtor);
                _currentIL.Emit(OpCodes.Stloc, _currentYieldListLocal);
            }

            _localFunctionDeclarations = savedLocalFunctionDeclarations != null
                ? new Dictionary<string, FunctionDeclaration>(savedLocalFunctionDeclarations)
                : new Dictionary<string, FunctionDeclaration>();
            _localFunctionDeclarations[localFunction.Function.Name] = localFunction.Function;

            var receiverOffset = methodBuilder.IsStatic ? 0 : 1;
            var captureCount = RegisterGenericLocalFunctionCaptureContext(localFunction.Function, receiverOffset);
            RegisterParameterContext(localFunction.Function.Parameters, receiverOffset + captureCount, combinedGenericParameters);

            if (localFunction.Function.Body != null)
            {
                EmitStatement(localFunction.Function.Body);
            }
            else if (localFunction.Function.ExpressionBody != null)
            {
                if (_currentAsyncReturnType != null)
                {
                    if (_currentAsyncResultType != null)
                    {
                        EmitExpressionWithExpectedType(localFunction.Function.ExpressionBody, _currentAsyncResultType);
                    }
                    else
                    {
                        EmitExpression(localFunction.Function.ExpressionBody);
                        if (GetExpressionType(localFunction.Function.ExpressionBody) != typeof(void))
                        {
                            _currentIL.Emit(OpCodes.Pop);
                        }
                    }

                    EmitWrapCurrentAsyncReturn();
                    _currentIL.Emit(OpCodes.Ret);
                }
                else
                {
                    EmitExpression(localFunction.Function.ExpressionBody);
                    _currentIL.Emit(OpCodes.Ret);
                }
            }

            if (_currentGeneratorReturnType != null)
            {
                _currentIL.MarkLabel(_currentYieldBreakLabel!.Value);
                EmitGeneratorReturnValue(_currentGeneratorReturnType, _currentYieldListLocal!);
                _currentIL.Emit(OpCodes.Ret);
            }
            else if (_currentAsyncReturnType != null && _currentAsyncResultType == null)
            {
                EmitWrapCurrentAsyncReturn();
                _currentIL.Emit(OpCodes.Ret);
            }
            else if (returnType == typeof(void))
            {
                _currentIL.Emit(OpCodes.Ret);
            }
        }
        finally
        {
            _currentIL = savedIL;
            _locals = savedLocals;
            _parameters = savedParameters;
            _parameterTypes = savedParameterTypes;
            _byRefParameters = savedByRefParameters;
            _currentGenericParameters = savedCurrentGenericParameters;
            _currentReturnType = savedCurrentReturnType;
            _expectedExpressionType = savedExpectedExpressionType;
            _currentAsyncReturnType = savedCurrentAsyncReturnType;
            _currentAsyncResultType = savedCurrentAsyncResultType;
            _currentAsyncReturnsValueTask = savedCurrentAsyncReturnsValueTask;
            _currentGeneratorReturnType = savedCurrentGeneratorReturnType;
            _currentYieldElementType = savedCurrentYieldElementType;
            _currentYieldListLocal = savedCurrentYieldListLocal;
            _currentYieldBreakLabel = savedCurrentYieldBreakLabel;
            _currentTypeBuilder = savedCurrentTypeBuilder;
            _closureFields = savedClosureFields;
            _liftLocalsIntoBoxes = savedLiftLocalsIntoBoxes;
            _liftedIdentifiers = savedLiftedIdentifiers;
            _liftedClosureFields = savedLiftedClosureFields;
            _pendingLocalFunctionDefinition = savedPendingLocalFunctionDefinition;
            _localFunctionDeclarations = savedLocalFunctionDeclarations;
            _currentHasThis = savedCurrentHasThis;
        }
    }

    private HashSet<FunctionDeclaration> GetDirectLocalFunctionDeclarations(
        BlockStatement block,
        IReadOnlyCollection<LocalFunctionStatement> localFunctions)
    {
        var localFunctionNames = localFunctions
            .Select(localFunction => localFunction.Function.Name)
            .ToHashSet(StringComparer.Ordinal);
        var escapingNames = new HashSet<string>(StringComparer.Ordinal);

        foreach (var statement in block.Statements)
        {
            if (statement is LocalFunctionStatement localFunction)
            {
                if (localFunction.Function.ExpressionBody != null)
                {
                    FindEscapingLocalFunctionReferences(localFunction.Function.ExpressionBody, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }

                if (localFunction.Function.Body != null)
                {
                    FindEscapingLocalFunctionReferences(localFunction.Function.Body, localFunctionNames, escapingNames);
                }

                continue;
            }

            FindEscapingLocalFunctionReferences(statement, localFunctionNames, escapingNames);
        }

        return new HashSet<FunctionDeclaration>(
            localFunctions
                .Where(localFunction => localFunction.Function.ReturnType != null
                    && (!escapingNames.Contains(localFunction.Function.Name)
                        || CanMaterializeLocalFunctionValueAtBoundary(localFunction)))
                .Select(localFunction => localFunction.Function),
            ReferenceEqualityComparer.Instance);
    }

    private bool CanMaterializeLocalFunctionValueAtBoundary(LocalFunctionStatement localFunction)
    {
        if (localFunction.Function.TypeParameters is { Count: > 0 })
        {
            return false;
        }

        var lambda = new LambdaExpression(
            localFunction.Function.Parameters,
            localFunction.Function.ExpressionBody,
            localFunction.Function.Body,
            localFunction.Line,
            localFunction.Column);

        var captures = AnalyzeCapturedVariables(lambda);
        if (!localFunction.Function.Modifiers.HasFlag(Modifiers.Static) && _currentHasThis)
        {
            captures.Remove(ThisCaptureName);
        }

        return captures.Count == 0;
    }

    private bool TryEmitDirectLocalFunctionDelegateValue(FunctionDeclaration declaration)
    {
        if (_currentIL == null
            || !_genericLocalFunctionBuilders.TryGetValue(declaration, out var methodBuilder)
            || !_genericLocalFunctionCaptures.TryGetValue(declaration, out var captures)
            || captures.Count != 0
            || declaration.TypeParameters is { Count: > 0 })
        {
            return false;
        }

        var delegateType = GetLocalFunctionDelegateType(declaration);
        var delegateConstructor = delegateType.GetConstructor(new[] { typeof(object), typeof(IntPtr) })
            ?? throw new InvalidOperationException($"Could not resolve delegate constructor for local function {declaration.Name}");

        if (methodBuilder.IsStatic)
        {
            _currentIL.Emit(OpCodes.Ldnull);
        }
        else
        {
            EmitGenericLocalFunctionReceiver(methodBuilder);
        }

        _currentIL.Emit(OpCodes.Ldftn, methodBuilder);
        _currentIL.Emit(OpCodes.Newobj, delegateConstructor);
        return true;
    }

    private void FindEscapingLocalFunctionReferences(
        Statement statement,
        HashSet<string> localFunctionNames,
        HashSet<string> escapingNames)
    {
        switch (statement)
        {
            case BlockStatement block:
                foreach (var innerStatement in block.Statements)
                {
                    FindEscapingLocalFunctionReferences(innerStatement, localFunctionNames, escapingNames);
                }
                break;
            case ExpressionStatement expressionStatement:
                FindEscapingLocalFunctionReferences(expressionStatement.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case VariableDeclarationStatement variableDeclaration when variableDeclaration.Initializer != null:
                FindEscapingLocalFunctionReferences(variableDeclaration.Initializer, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case TupleDeconstructionStatement tupleDeconstruction:
                FindEscapingLocalFunctionReferences(tupleDeconstruction.Initializer, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case ReturnStatement returnStatement when returnStatement.Value != null:
                FindEscapingLocalFunctionReferences(returnStatement.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case IfStatement ifStatement:
                FindEscapingLocalFunctionReferences(ifStatement.Condition, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(ifStatement.ThenStatement, localFunctionNames, escapingNames);
                if (ifStatement.ElseStatement != null)
                {
                    FindEscapingLocalFunctionReferences(ifStatement.ElseStatement, localFunctionNames, escapingNames);
                }
                break;
            case WhileStatement whileStatement:
                FindEscapingLocalFunctionReferences(whileStatement.Condition, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(whileStatement.Body, localFunctionNames, escapingNames);
                break;
            case ForStatement forStatement:
                if (forStatement.Initializer != null)
                {
                    FindEscapingLocalFunctionReferences(forStatement.Initializer, localFunctionNames, escapingNames);
                }
                if (forStatement.Condition != null)
                {
                    FindEscapingLocalFunctionReferences(forStatement.Condition, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                if (forStatement.Iterator != null)
                {
                    FindEscapingLocalFunctionReferences(forStatement.Iterator, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                FindEscapingLocalFunctionReferences(forStatement.Body, localFunctionNames, escapingNames);
                break;
            case ForeachStatement foreachStatement:
                FindEscapingLocalFunctionReferences(foreachStatement.Collection, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(foreachStatement.Body, localFunctionNames, escapingNames);
                break;
            case AwaitForEachStatement awaitForEachStatement:
                FindEscapingLocalFunctionReferences(awaitForEachStatement.Collection, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(awaitForEachStatement.Body, localFunctionNames, escapingNames);
                break;
            case ThrowStatement throwStatement:
                FindEscapingLocalFunctionReferences(throwStatement.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case TryStatement tryStatement:
                FindEscapingLocalFunctionReferences(tryStatement.TryBlock, localFunctionNames, escapingNames);
                foreach (var catchClause in tryStatement.CatchClauses)
                {
                    FindEscapingLocalFunctionReferences(catchClause.Block, localFunctionNames, escapingNames);
                }
                if (tryStatement.FinallyBlock != null)
                {
                    FindEscapingLocalFunctionReferences(tryStatement.FinallyBlock, localFunctionNames, escapingNames);
                }
                break;
            case UsingStatement usingStatement:
                if (usingStatement.Declaration?.Initializer != null)
                {
                    FindEscapingLocalFunctionReferences(usingStatement.Declaration.Initializer, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                if (usingStatement.Expression != null)
                {
                    FindEscapingLocalFunctionReferences(usingStatement.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                if (usingStatement.Body != null)
                {
                    FindEscapingLocalFunctionReferences(usingStatement.Body, localFunctionNames, escapingNames);
                }
                break;
            case LockStatement lockStatement:
                FindEscapingLocalFunctionReferences(lockStatement.LockObject, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(lockStatement.Body, localFunctionNames, escapingNames);
                break;
            case SwitchStatement switchStatement:
                FindEscapingLocalFunctionReferences(switchStatement.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                foreach (var switchCase in switchStatement.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        FindEscapingLocalFunctionReferences(caseStatement, localFunctionNames, escapingNames);
                    }
                }
                break;
            case PrintStatement printStatement:
                FindEscapingLocalFunctionReferences(printStatement.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case AssertStatement assertStatement:
                FindEscapingLocalFunctionReferences(assertStatement.Condition, localFunctionNames, escapingNames, isDirectCallCallee: false);
                if (assertStatement.Message != null)
                {
                    FindEscapingLocalFunctionReferences(assertStatement.Message, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                break;
            case AssertThrowsStatement assertThrowsStatement:
                FindEscapingLocalFunctionReferences(assertThrowsStatement.Body, localFunctionNames, escapingNames);
                break;
            case LocalFunctionStatement localFunctionStatement:
                if (localFunctionStatement.Function.ExpressionBody != null)
                {
                    FindEscapingLocalFunctionReferences(localFunctionStatement.Function.ExpressionBody, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                if (localFunctionStatement.Function.Body != null)
                {
                    FindEscapingLocalFunctionReferences(localFunctionStatement.Function.Body, localFunctionNames, escapingNames);
                }
                break;
        }
    }

    private void FindEscapingLocalFunctionReferences(
        Expression expression,
        HashSet<string> localFunctionNames,
        HashSet<string> escapingNames,
        bool isDirectCallCallee)
    {
        switch (expression)
        {
            case IdentifierExpression identifier:
                if (!isDirectCallCallee && localFunctionNames.Contains(identifier.Name))
                {
                    escapingNames.Add(identifier.Name);
                }
                break;
            case CallExpression call:
                FindEscapingLocalFunctionReferences(call.Callee, localFunctionNames, escapingNames, isDirectCallCallee: true);
                foreach (var argument in call.Arguments)
                {
                    FindEscapingLocalFunctionReferences(argument.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                break;
            case BinaryExpression binary:
                FindEscapingLocalFunctionReferences(binary.Left, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(binary.Right, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case UnaryExpression unary:
                FindEscapingLocalFunctionReferences(unary.Operand, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case AssignmentExpression assignment:
                FindEscapingLocalFunctionReferences(assignment.Target, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(assignment.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case MemberAccessExpression memberAccess:
                FindEscapingLocalFunctionReferences(memberAccess.Object, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case IndexAccessExpression indexAccess:
                FindEscapingLocalFunctionReferences(indexAccess.Object, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(indexAccess.Index, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case LambdaExpression lambda:
                if (lambda.ExpressionBody != null)
                {
                    FindEscapingLocalFunctionReferences(lambda.ExpressionBody, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                if (lambda.BlockBody != null)
                {
                    FindEscapingLocalFunctionReferences(lambda.BlockBody, localFunctionNames, escapingNames);
                }
                break;
            case ParenthesizedExpression parenthesized:
                FindEscapingLocalFunctionReferences(parenthesized.Inner, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case TernaryExpression ternary:
                FindEscapingLocalFunctionReferences(ternary.Condition, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(ternary.ThenExpression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                FindEscapingLocalFunctionReferences(ternary.ElseExpression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case ArrayLiteralExpression arrayLiteral:
                foreach (var element in arrayLiteral.Elements)
                {
                    FindEscapingLocalFunctionReferences(element, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                break;
            case SpreadExpression spread:
                FindEscapingLocalFunctionReferences(spread.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                {
                    FindEscapingLocalFunctionReferences(element.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                break;
            case InterpolatedStringExpression interpolatedString:
                foreach (var hole in interpolatedString.Parts.OfType<InterpolatedStringHole>())
                {
                    FindEscapingLocalFunctionReferences(hole.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                break;
            case RangeExpression range:
                if (range.Start != null)
                {
                    FindEscapingLocalFunctionReferences(range.Start, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                if (range.End != null)
                {
                    FindEscapingLocalFunctionReferences(range.End, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                break;
            case IsExpression isExpression:
                FindEscapingLocalFunctionReferences(isExpression.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case WithExpression withExpression:
                FindEscapingLocalFunctionReferences(withExpression.Target, localFunctionNames, escapingNames, isDirectCallCallee: false);
                foreach (var property in withExpression.Properties)
                {
                    if (property.IndexExpression != null)
                    {
                        FindEscapingLocalFunctionReferences(property.IndexExpression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                    }
                    FindEscapingLocalFunctionReferences(property.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                break;
            case AwaitExpression awaitExpression:
                FindEscapingLocalFunctionReferences(awaitExpression.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case ThrowExpression throwExpression:
                FindEscapingLocalFunctionReferences(throwExpression.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case CastExpression castExpression:
                FindEscapingLocalFunctionReferences(castExpression.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case CheckedExpression checkedExpression:
                FindEscapingLocalFunctionReferences(checkedExpression.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case UncheckedExpression uncheckedExpression:
                FindEscapingLocalFunctionReferences(uncheckedExpression.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                break;
            case MatchExpression matchExpression:
                FindEscapingLocalFunctionReferences(matchExpression.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                foreach (var matchCase in matchExpression.Cases)
                {
                    if (matchCase.Guard != null)
                    {
                        FindEscapingLocalFunctionReferences(matchCase.Guard, localFunctionNames, escapingNames, isDirectCallCallee: false);
                    }
                    FindEscapingLocalFunctionReferences(matchCase.Expression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                {
                    FindEscapingLocalFunctionReferences(argument.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                }
                if (newExpression.Initializer != null)
                {
                    foreach (var property in newExpression.Initializer.Properties)
                    {
                        if (property.IndexExpression != null)
                        {
                            FindEscapingLocalFunctionReferences(property.IndexExpression, localFunctionNames, escapingNames, isDirectCallCallee: false);
                        }
                        FindEscapingLocalFunctionReferences(property.Value, localFunctionNames, escapingNames, isDirectCallCallee: false);
                    }
                }
                break;
        }
    }

    private BoundDeclaredMethodCall? BindGenericLocalFunctionCall(IdentifierExpression ident, CallExpression call)
    {
        if (_localFunctionDeclarations == null
            || !_localFunctionDeclarations.TryGetValue(ident.Name, out var declaration)
            || !_genericLocalFunctionBuilders.TryGetValue(declaration, out var methodBuilder))
        {
            return null;
        }

        var (candidateMethod, candidateTypeArguments) = CreateGenericLocalFunctionCandidate(declaration, methodBuilder, call);
        if (candidateMethod == null)
        {
            return null;
        }

        var captures = _genericLocalFunctionCaptures.TryGetValue(declaration, out var captureList)
            ? captureList
            : Array.Empty<GenericLocalFunctionCapture>();
        var typeBindings = declaration.TypeParameters is { Count: > 0 } && candidateTypeArguments != null
            ? declaration.TypeParameters
                .Select((typeParameter, index) => (typeParameter.Name, Type: candidateTypeArguments[index]))
                .ToDictionary(entry => entry.Name, entry => entry.Type, StringComparer.Ordinal)
            : new Dictionary<string, Type>(StringComparer.Ordinal);
        if (!TryBindGenericLocalFunctionParameters(
                declaration.Parameters,
                typeBindings,
                call.Arguments,
                out var boundArguments))
        {
            return null;
        }

        var allArguments = new List<BoundCallArgument>(captures.Count + boundArguments.Count);
        allArguments.AddRange(captures.Select(capture => new CapturedGenericLocalBoundCallArgument(capture)));
        allArguments.AddRange(boundArguments);

        return new BoundDeclaredMethodCall(
            declaration,
            candidateMethod,
            allArguments,
            IsExtensionMethod: false,
            candidateTypeArguments);
    }
}
