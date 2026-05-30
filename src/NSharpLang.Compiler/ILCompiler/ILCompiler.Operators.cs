using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    private static string GetEmittedMethodName(FunctionDeclaration function)
    {
        if (function.IsConversionOperator)
        {
            return function.IsImplicitConversion ? "op_Implicit" : "op_Explicit";
        }

        if (function.IsOperatorOverload)
        {
            var emittedName = GetClrOperatorMethodName(function.OperatorSymbol, function.Parameters.Count);
            if (emittedName != null)
            {
                return emittedName;
            }
        }

        return function.Name;
    }

    private static string? GetClrOperatorMethodName(string? operatorSymbol, int arity)
    {
        return (operatorSymbol, arity) switch
        {
            ("+", 2) => "op_Addition",
            ("-", 2) => "op_Subtraction",
            ("*", 2) => "op_Multiply",
            ("/", 2) => "op_Division",
            ("%", 2) => "op_Modulus",
            ("==", 2) => "op_Equality",
            ("!=", 2) => "op_Inequality",
            ("<", 2) => "op_LessThan",
            (">", 2) => "op_GreaterThan",
            ("<=", 2) => "op_LessThanOrEqual",
            (">=", 2) => "op_GreaterThanOrEqual",
            ("&", 2) => "op_BitwiseAnd",
            ("|", 2) => "op_BitwiseOr",
            ("^", 2) => "op_ExclusiveOr",
            ("<<", 2) => "op_LeftShift",
            (">>", 2) => "op_RightShift",
            ("+", 1) => "op_UnaryPlus",
            ("-", 1) => "op_UnaryNegation",
            ("!", 1) => "op_LogicalNot",
            ("~", 1) => "op_OnesComplement",
            ("++", 1) => "op_Increment",
            ("--", 1) => "op_Decrement",
            _ => null
        };
    }

    private static string? GetClrOperatorMethodName(BinaryOperator op)
    {
        return op switch
        {
            BinaryOperator.Add => "op_Addition",
            BinaryOperator.Subtract => "op_Subtraction",
            BinaryOperator.Multiply => "op_Multiply",
            BinaryOperator.Divide => "op_Division",
            BinaryOperator.Modulo => "op_Modulus",
            BinaryOperator.Equal => "op_Equality",
            BinaryOperator.NotEqual => "op_Inequality",
            BinaryOperator.Less => "op_LessThan",
            BinaryOperator.Greater => "op_GreaterThan",
            BinaryOperator.LessOrEqual => "op_LessThanOrEqual",
            BinaryOperator.GreaterOrEqual => "op_GreaterThanOrEqual",
            BinaryOperator.BitwiseAnd => "op_BitwiseAnd",
            BinaryOperator.BitwiseOr => "op_BitwiseOr",
            BinaryOperator.BitwiseXor => "op_ExclusiveOr",
            BinaryOperator.LeftShift => "op_LeftShift",
            BinaryOperator.RightShift => "op_RightShift",
            _ => null
        };
    }

    private static string? GetClrOperatorMethodName(UnaryOperator op)
    {
        return op switch
        {
            UnaryOperator.Negate => "op_UnaryNegation",
            UnaryOperator.Not => "op_LogicalNot",
            UnaryOperator.BitwiseNot => "op_OnesComplement",
            UnaryOperator.PreIncrement or UnaryOperator.PostIncrement => "op_Increment",
            UnaryOperator.PreDecrement or UnaryOperator.PostDecrement => "op_Decrement",
            _ => null
        };
    }

    private static string GetSourceOperatorName(BinaryOperator op)
    {
        return "operator " + (op switch
        {
            BinaryOperator.Add => "+",
            BinaryOperator.Subtract => "-",
            BinaryOperator.Multiply => "*",
            BinaryOperator.Divide => "/",
            BinaryOperator.Modulo => "%",
            BinaryOperator.Equal => "==",
            BinaryOperator.NotEqual => "!=",
            BinaryOperator.Less => "<",
            BinaryOperator.Greater => ">",
            BinaryOperator.LessOrEqual => "<=",
            BinaryOperator.GreaterOrEqual => ">=",
            BinaryOperator.BitwiseAnd => "&",
            BinaryOperator.BitwiseOr => "|",
            BinaryOperator.BitwiseXor => "^",
            BinaryOperator.LeftShift => "<<",
            BinaryOperator.RightShift => ">>",
            _ => throw new InvalidOperationException($"Binary operator {op} does not have a CLR overload name")
        });
    }

    private static string GetSourceOperatorName(UnaryOperator op)
    {
        return "operator " + (op switch
        {
            UnaryOperator.Negate => "-",
            UnaryOperator.Not => "!",
            UnaryOperator.BitwiseNot => "~",
            UnaryOperator.PreIncrement or UnaryOperator.PostIncrement => "++",
            UnaryOperator.PreDecrement or UnaryOperator.PostDecrement => "--",
            _ => throw new InvalidOperationException($"Unary operator {op} does not have a CLR overload name")
        });
    }

    private static bool IsUnsupportedRuntimeLookupType(Type type)
    {
        return type is TypeBuilder or EnumBuilder
            || type.IsGenericParameter
            || type.ContainsGenericParameters
            || RequiresTypeBuilderMemberResolution(type);
    }

    private static bool IsByRefLikeType(Type type)
    {
        try
        {
            return type.IsByRefLike;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    private bool AreTypesAssignmentCompatible(Type targetType, Type sourceType)
    {
        if (targetType == sourceType)
        {
            return true;
        }

        if (AreTypeIdentitiesEquivalent(targetType, sourceType))
        {
            return true;
        }

        if (targetType.ContainsGenericParameters || sourceType.ContainsGenericParameters)
        {
            return GetTypeKey(targetType) == GetTypeKey(sourceType);
        }

        if (IsByRefLikeType(sourceType) || IsByRefLikeType(targetType))
        {
            return false;
        }

        var hasSourceBuilder = TryGetUserTypeDefinition(sourceType, out var sourceBuilder);
        var hasTargetBuilder = TryGetUserTypeDefinition(targetType, out var targetBuilder);

        if (hasSourceBuilder && hasTargetBuilder)
        {
            if (sourceBuilder == targetBuilder)
            {
                return true;
            }

            var current = sourceBuilder.BaseType;
            while (current != null)
            {
                if (current == targetBuilder)
                {
                    return true;
                }

                current = current.BaseType;
            }

            if (GetInterfacesSafe(sourceBuilder).Any(@interface => AreTypeIdentitiesEquivalent(@interface, targetBuilder)))
            {
                return true;
            }
        }

        if (hasSourceBuilder)
        {
            var current = sourceBuilder.BaseType;
            while (current != null)
            {
                if (AreTypeIdentitiesEquivalent(current, targetType))
                {
                    return true;
                }

                current = current.BaseType;
            }

            if (GetInterfacesSafe(sourceBuilder).Any(@interface => AreTypeIdentitiesEquivalent(@interface, targetType)))
            {
                return true;
            }
        }

        if (hasSourceBuilder || hasTargetBuilder)
        {
            return false;
        }

        try
        {
            var constructedMatch = FindConstructedGenericMatch(targetType, sourceType);
            if (constructedMatch != null && AreTypeIdentitiesEquivalent(targetType, constructedMatch))
            {
                return true;
            }
        }
        catch (NotSupportedException)
        {
        }

        return !IsUnsupportedRuntimeLookupType(targetType)
            && !IsUnsupportedRuntimeLookupType(sourceType)
            && targetType.IsAssignableFrom(sourceType);
    }

    private MethodInfo? ResolveDeclaredStaticMethod(Type targetType, string sourceName, Type[] argumentTypes, Type? requiredReturnType = null)
    {
        if (!TryGetUserTypeDefinition(targetType, out var typeBuilder))
        {
            return null;
        }

        if (!_declaredMethodOverloads.TryGetValue(GetMethodKey(typeBuilder, sourceName), out var overloads))
        {
            return null;
        }

        MethodInfo? bestMethod = null;
        var bestScore = -1;

        foreach (var overload in overloads)
        {
            if (!overload.Builder.IsStatic)
            {
                continue;
            }

            var candidate = targetType == typeBuilder
                ? overload.Builder
                : TypeBuilder.GetMethod(targetType, overload.Builder);
            var score = GetStaticMethodCandidateScore(candidate, argumentTypes, requiredReturnType);
            if (score <= bestScore)
            {
                continue;
            }

            bestMethod = candidate;
            bestScore = score;
        }

        return bestMethod;
    }

    private int GetStaticMethodCandidateScore(MethodInfo candidate, IReadOnlyList<Type> argumentTypes, Type? requiredReturnType)
    {
        if (candidate.ContainsGenericParameters)
        {
            return -1;
        }

        if (requiredReturnType != null && !IsConversionTargetCompatible(candidate.ReturnType, requiredReturnType))
        {
            return -1;
        }

        var parameters = candidate.GetParameters();
        if (parameters.Length != argumentTypes.Count)
        {
            return -1;
        }

        var score = 0;
        for (int i = 0; i < parameters.Length; i++)
        {
            var parameterType = GetByRefElementType(parameters[i].ParameterType);
            var argumentType = argumentTypes[i];
            if (!IsParameterTypeCompatible(parameterType, argumentType))
            {
                return -1;
            }

            score += GetParameterMatchScore(parameterType, argumentType);
        }

        return score;
    }

    private MethodInfo? ResolveReflectionStaticMethod(Type declaringType, string emittedName, Type[] argumentTypes, Type? requiredReturnType = null)
    {
        if (declaringType is TypeBuilder
            || IsUnsupportedRuntimeLookupType(declaringType)
            || TryGetUserTypeDefinition(declaringType, out _))
        {
            return null;
        }

        MethodInfo? bestMethod = null;
        var bestScore = -1;
        MethodInfo[] candidates;
        try
        {
            candidates = declaringType.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.FlattenHierarchy);
        }
        catch (NotSupportedException)
        {
            return null;
        }

        foreach (var candidate in candidates.Where(method => method.Name == emittedName))
        {
            var score = GetStaticMethodCandidateScore(candidate, argumentTypes, requiredReturnType);
            if (score <= bestScore)
            {
                continue;
            }

            bestMethod = candidate;
            bestScore = score;
        }

        return bestMethod;
    }

    private MethodInfo? ResolveBinaryOperatorMethod(BinaryOperator op, Type leftType, Type rightType)
    {
        var emittedName = GetClrOperatorMethodName(op);
        if (emittedName == null)
        {
            return null;
        }

        var sourceName = GetSourceOperatorName(op);
        var argumentTypes = new[] { leftType, rightType };
        var candidateTypes = new List<Type> { leftType };
        if (rightType != leftType)
        {
            candidateTypes.Add(rightType);
        }

        MethodInfo? bestMethod = null;
        var bestScore = -1;

        foreach (var candidateType in candidateTypes)
        {
            var declaredCandidate = ResolveDeclaredStaticMethod(candidateType, sourceName, argumentTypes);
            var declaredScore = declaredCandidate != null
                ? GetStaticMethodCandidateScore(declaredCandidate, argumentTypes, requiredReturnType: null)
                : -1;
            if (declaredScore > bestScore)
            {
                bestMethod = declaredCandidate;
                bestScore = declaredScore;
            }

            var reflectionCandidate = ResolveReflectionStaticMethod(candidateType, emittedName, argumentTypes);
            var reflectionScore = reflectionCandidate != null
                ? GetStaticMethodCandidateScore(reflectionCandidate, argumentTypes, requiredReturnType: null)
                : -1;
            if (reflectionScore > bestScore)
            {
                bestMethod = reflectionCandidate;
                bestScore = reflectionScore;
            }
        }

        return bestMethod;
    }

    private MethodInfo? ResolveUnaryOperatorMethod(UnaryOperator op, Type operandType)
    {
        var emittedName = GetClrOperatorMethodName(op);
        if (emittedName == null)
        {
            return null;
        }

        var sourceName = GetSourceOperatorName(op);
        var argumentTypes = new[] { operandType };
        var declaredCandidate = ResolveDeclaredStaticMethod(operandType, sourceName, argumentTypes);
        var reflectionCandidate = ResolveReflectionStaticMethod(operandType, emittedName, argumentTypes);

        var declaredScore = declaredCandidate != null
            ? GetStaticMethodCandidateScore(declaredCandidate, argumentTypes, requiredReturnType: null)
            : -1;
        var reflectionScore = reflectionCandidate != null
            ? GetStaticMethodCandidateScore(reflectionCandidate, argumentTypes, requiredReturnType: null)
            : -1;

        return declaredScore >= reflectionScore ? declaredCandidate : reflectionCandidate;
    }

    private MethodInfo? ResolveConversionOperator(Type sourceType, Type targetType, bool allowExplicit)
    {
        var sourceIsUnsupported = IsUnsupportedRuntimeLookupType(sourceType) && !TryGetUserTypeDefinition(sourceType, out _);
        var targetIsUnsupported = IsUnsupportedRuntimeLookupType(targetType) && !TryGetUserTypeDefinition(targetType, out _);
        if (sourceType == targetType || sourceIsUnsupported || targetIsUnsupported)
        {
            return null;
        }

        var searchTypes = new List<Type> { sourceType };
        if (targetType != sourceType)
        {
            searchTypes.Add(targetType);
        }

        MethodInfo? bestMethod = null;
        var bestScore = -1;

        foreach (var candidateType in searchTypes)
        {
            var implicitDeclared = ResolveDeclaredStaticMethod(candidateType, "implicit operator", new[] { sourceType }, targetType);
            var implicitDeclaredScore = implicitDeclared != null
                ? GetStaticMethodCandidateScore(implicitDeclared, new[] { sourceType }, targetType)
                : -1;
            if (implicitDeclaredScore > bestScore)
            {
                bestMethod = implicitDeclared;
                bestScore = implicitDeclaredScore;
            }

            var implicitReflection = ResolveReflectionStaticMethod(candidateType, "op_Implicit", new[] { sourceType }, targetType);
            var implicitReflectionScore = implicitReflection != null
                ? GetStaticMethodCandidateScore(implicitReflection, new[] { sourceType }, targetType)
                : -1;
            if (implicitReflectionScore > bestScore)
            {
                bestMethod = implicitReflection;
                bestScore = implicitReflectionScore;
            }

            if (!allowExplicit)
            {
                continue;
            }

            var explicitDeclared = ResolveDeclaredStaticMethod(candidateType, "explicit operator", new[] { sourceType }, targetType);
            var explicitDeclaredScore = explicitDeclared != null
                ? GetStaticMethodCandidateScore(explicitDeclared, new[] { sourceType }, targetType)
                : -1;
            if (explicitDeclaredScore > bestScore)
            {
                bestMethod = explicitDeclared;
                bestScore = explicitDeclaredScore;
            }

            var explicitReflection = ResolveReflectionStaticMethod(candidateType, "op_Explicit", new[] { sourceType }, targetType);
            var explicitReflectionScore = explicitReflection != null
                ? GetStaticMethodCandidateScore(explicitReflection, new[] { sourceType }, targetType)
                : -1;
            if (explicitReflectionScore > bestScore)
            {
                bestMethod = explicitReflection;
                bestScore = explicitReflectionScore;
            }
        }

        return bestMethod;
    }

    private static bool IsConversionTargetCompatible(Type sourceType, Type targetType)
    {
        if (IsByRefLikeType(sourceType) || IsByRefLikeType(targetType))
        {
            return sourceType == targetType;
        }

        if (sourceType == targetType || AreTypeIdentitiesEquivalent(sourceType, targetType))
        {
            return true;
        }

        if (IsUnsupportedRuntimeLookupType(sourceType) || IsUnsupportedRuntimeLookupType(targetType))
        {
            return false;
        }

        if (targetType.IsAssignableFrom(sourceType))
        {
            return true;
        }

        if (TryGetEnumUnderlyingType(targetType) == sourceType)
        {
            return true;
        }

        if (TryGetEnumUnderlyingType(sourceType) == targetType)
        {
            return true;
        }

        return false;
    }

    private void EmitStaticMethodCall(MethodInfo method, params Expression[] arguments)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var parameters = method.GetParameters();
        for (int i = 0; i < arguments.Length; i++)
        {
            EmitExpressionWithExpectedType(arguments[i], GetByRefElementType(parameters[i].ParameterType));
        }

        _currentIL.Emit(OpCodes.Call, method);
    }

    private bool TryEmitUnaryOperator(UnaryExpression unary)
    {
        var method = ResolveUnaryOperatorMethod(unary.Operator, GetExpressionType(unary.Operand));
        if (method == null)
        {
            return false;
        }

        EmitStaticMethodCall(method, unary.Operand);
        return true;
    }

    private bool TryEmitBinaryOperator(BinaryExpression binary)
    {
        var method = ResolveBinaryOperatorMethod(
            binary.Operator,
            GetExpressionType(binary.Left),
            GetExpressionType(binary.Right));
        if (method == null)
        {
            return false;
        }

        EmitStaticMethodCall(method, binary.Left, binary.Right);
        return true;
    }

    private void EmitWithOverflowChecking(bool enabled, Action emit)
    {
        var previous = _overflowCheckingEnabled;
        _overflowCheckingEnabled = enabled;
        try
        {
            emit();
        }
        finally
        {
            _overflowCheckingEnabled = previous;
        }
    }

    private Type NormalizeOverflowCheckedType(Type type)
    {
        type = Nullable.GetUnderlyingType(type) ?? type;
        return TryGetEnumUnderlyingType(type) ?? type;
    }

    private bool IsOverflowCheckedIntegralType(Type type)
    {
        type = NormalizeOverflowCheckedType(type);
        return type == typeof(byte)
            || type == typeof(sbyte)
            || type == typeof(short)
            || type == typeof(ushort)
            || type == typeof(int)
            || type == typeof(uint)
            || type == typeof(long)
            || type == typeof(ulong)
            || type == typeof(char);
    }

    private bool IsUnsignedOverflowCheckedType(Type type)
    {
        type = NormalizeOverflowCheckedType(type);
        return type == typeof(byte)
            || type == typeof(ushort)
            || type == typeof(uint)
            || type == typeof(ulong)
            || type == typeof(char);
    }

    private bool TryEmitCheckedBinaryOperator(BinaryExpression binary)
    {
        if (!_overflowCheckingEnabled)
        {
            return false;
        }

        var leftType = NormalizeOverflowCheckedType(GetExpressionType(binary.Left));
        var rightType = NormalizeOverflowCheckedType(GetExpressionType(binary.Right));
        if (leftType != rightType || !IsOverflowCheckedIntegralType(leftType))
        {
            return false;
        }

        var opcode = binary.Operator switch
        {
            BinaryOperator.Add => IsUnsignedOverflowCheckedType(leftType) ? OpCodes.Add_Ovf_Un : OpCodes.Add_Ovf,
            BinaryOperator.Subtract => IsUnsignedOverflowCheckedType(leftType) ? OpCodes.Sub_Ovf_Un : OpCodes.Sub_Ovf,
            BinaryOperator.Multiply => IsUnsignedOverflowCheckedType(leftType) ? OpCodes.Mul_Ovf_Un : OpCodes.Mul_Ovf,
            _ => default
        };

        if (opcode.Value == 0)
        {
            return false;
        }

        EmitExpression(binary.Left);
        EmitExpression(binary.Right);
        _currentIL!.Emit(opcode);
        return true;
    }

    private void EmitValueCoercion(Type sourceType, Type targetType, bool allowExplicitUserDefinedConversions)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        sourceType = GetByRefElementType(sourceType);
        targetType = GetByRefElementType(targetType);

        if (sourceType == targetType)
        {
            return;
        }

        if (TryEmitRuntimeUnionConversion(sourceType, targetType, allowExplicitUserDefinedConversions))
        {
            return;
        }

        var sourceIsUnsupported = IsUnsupportedRuntimeLookupType(sourceType) && !TryGetUserTypeDefinition(sourceType, out _);
        var targetIsUnsupported = IsUnsupportedRuntimeLookupType(targetType) && !TryGetUserTypeDefinition(targetType, out _);
        if (sourceIsUnsupported || targetIsUnsupported)
        {
            return;
        }

        var sourceNullable = Nullable.GetUnderlyingType(sourceType);
        var targetNullable = Nullable.GetUnderlyingType(targetType);
        if (targetNullable != null && sourceNullable == null)
        {
            EmitValueCoercion(sourceType, targetNullable, allowExplicitUserDefinedConversions);
            var nullableCtor = targetType.GetConstructor(new[] { targetNullable });
            if (nullableCtor != null)
            {
                _currentIL.Emit(OpCodes.Newobj, nullableCtor);
            }
            return;
        }

        var sourceIsValueType = IsValueTypeLike(sourceType);
        var targetIsValueType = IsValueTypeLike(targetType);
        if (AreTypesAssignmentCompatible(targetType, sourceType))
        {
            if (sourceIsValueType && (!targetIsValueType || targetType.IsInterface))
            {
                _currentIL.Emit(OpCodes.Box, sourceType);
            }
            return;
        }

        if (TryEmitNumericConversion(sourceType, targetType))
        {
            return;
        }

        var conversionOperator = ResolveConversionOperator(sourceType, targetType, allowExplicitUserDefinedConversions);
        if (conversionOperator != null)
        {
            _currentIL.Emit(OpCodes.Call, conversionOperator);
            return;
        }

        if (targetIsValueType)
        {
            if (!sourceIsValueType)
            {
                _currentIL.Emit(OpCodes.Unbox_Any, targetType);
            }
            return;
        }

        if (sourceIsValueType)
        {
            _currentIL.Emit(OpCodes.Box, sourceType);
        }

        _currentIL.Emit(OpCodes.Castclass, targetType);
    }

    private bool TryEmitRuntimeUnionConversion(Type sourceType, Type targetType, bool allowExplicitUserDefinedConversions)
    {
        if (_currentIL == null
            || IsRuntimeUnionType(sourceType)
            || !TryGetRuntimeUnionArmTypes(targetType, out var targetArms))
        {
            return false;
        }

        var bestArmIndex = -1;
        var bestScore = 0;
        for (int i = 0; i < targetArms.Length; i++)
        {
            if (!IsParameterTypeCompatible(targetArms[i], sourceType))
            {
                continue;
            }

            var score = GetParameterMatchScore(targetArms[i], sourceType);
            if (score > bestScore)
            {
                bestArmIndex = i;
                bestScore = score;
            }
        }

        if (bestArmIndex < 0)
        {
            return false;
        }

        EmitValueCoercion(sourceType, targetArms[bestArmIndex], allowExplicitUserDefinedConversions);
        _currentIL.Emit(OpCodes.Call, GetRuntimeUnionImplicitConversionOperator(targetType, bestArmIndex));
        return true;
    }

    private bool TryGetNumericConversionOpcode(Type targetType, out OpCode opcode)
    {
        targetType = Nullable.GetUnderlyingType(targetType) ?? targetType;
        if (TryGetEnumUnderlyingType(targetType) is { } enumUnderlyingType)
        {
            targetType = enumUnderlyingType;
        }

        opcode = Type.GetTypeCode(targetType) switch
        {
            TypeCode.SByte => OpCodes.Conv_I1,
            TypeCode.Byte => OpCodes.Conv_U1,
            TypeCode.Int16 => OpCodes.Conv_I2,
            TypeCode.UInt16 => OpCodes.Conv_U2,
            TypeCode.Int32 => OpCodes.Conv_I4,
            TypeCode.UInt32 => OpCodes.Conv_U4,
            TypeCode.Int64 => OpCodes.Conv_I8,
            TypeCode.UInt64 => OpCodes.Conv_U8,
            TypeCode.Char => OpCodes.Conv_U2,
            TypeCode.Single => OpCodes.Conv_R4,
            TypeCode.Double => OpCodes.Conv_R8,
            _ => default
        };

        return opcode.Value != 0;
    }

    private bool TryGetCheckedNumericConversionOpcode(Type sourceType, Type targetType, out OpCode opcode)
    {
        sourceType = NormalizeOverflowCheckedType(sourceType);
        targetType = NormalizeOverflowCheckedType(targetType);
        var sourceUnsigned = IsUnsignedOverflowCheckedType(sourceType);

        opcode = Type.GetTypeCode(targetType) switch
        {
            TypeCode.SByte => sourceUnsigned ? OpCodes.Conv_Ovf_I1_Un : OpCodes.Conv_Ovf_I1,
            TypeCode.Byte => sourceUnsigned ? OpCodes.Conv_Ovf_U1_Un : OpCodes.Conv_Ovf_U1,
            TypeCode.Int16 => sourceUnsigned ? OpCodes.Conv_Ovf_I2_Un : OpCodes.Conv_Ovf_I2,
            TypeCode.UInt16 => sourceUnsigned ? OpCodes.Conv_Ovf_U2_Un : OpCodes.Conv_Ovf_U2,
            TypeCode.Int32 => sourceUnsigned ? OpCodes.Conv_Ovf_I4_Un : OpCodes.Conv_Ovf_I4,
            TypeCode.UInt32 => sourceUnsigned ? OpCodes.Conv_Ovf_U4_Un : OpCodes.Conv_Ovf_U4,
            TypeCode.Int64 => sourceUnsigned ? OpCodes.Conv_Ovf_I8_Un : OpCodes.Conv_Ovf_I8,
            TypeCode.UInt64 => sourceUnsigned ? OpCodes.Conv_Ovf_U8_Un : OpCodes.Conv_Ovf_U8,
            TypeCode.Char => sourceUnsigned ? OpCodes.Conv_Ovf_U2_Un : OpCodes.Conv_Ovf_U2,
            _ => default
        };

        return opcode.Value != 0;
    }

    private bool IsNumericConversionType(Type type)
    {
        var enumUnderlyingType = TryGetEnumUnderlyingType(type);
        if ((type is TypeBuilder || TryGetUserTypeDefinition(type, out _) || IsUnsupportedRuntimeLookupType(type))
            && enumUnderlyingType == null)
        {
            return false;
        }

        type = Nullable.GetUnderlyingType(type) ?? type;
        enumUnderlyingType ??= TryGetEnumUnderlyingType(type);
        if (enumUnderlyingType != null)
        {
            type = enumUnderlyingType;
        }

        return type == typeof(byte)
            || type == typeof(sbyte)
            || type == typeof(short)
            || type == typeof(ushort)
            || type == typeof(int)
            || type == typeof(uint)
            || type == typeof(long)
            || type == typeof(ulong)
            || type == typeof(char)
            || type == typeof(float)
            || type == typeof(double)
            || type == typeof(decimal);
    }

    /// <summary>
    /// Computes the C#-style binary numeric promotion target type for a primitive
    /// arithmetic/relational operator over two operands. Returns false (and leaves
    /// <paramref name="promotedType"/> null) when promotion does not apply: the
    /// operands aren't both primitive numerics, they're already the same type, the
    /// operator is a user-defined overload / shift / boolean-logical op, or either
    /// side is <see cref="decimal"/> (which is handled via its op_* methods).
    ///
    /// This mirrors ECMA-335 §III.1.5: the raw add/sub/mul/div/rem and compare
    /// opcodes require both operands to share a CLI stack type, so a mixed
    /// int/double (or short/long, etc.) expression must coerce the narrower side
    /// up to the common type before the opcode is emitted.
    /// </summary>
    private bool TryGetBinaryNumericPromotionType(BinaryOperator op, Type leftType, Type rightType, out Type promotedType)
    {
        promotedType = null!;

        // Only the arithmetic and relational operators lower to raw numeric
        // opcodes here. Shifts only promote the left operand (the shift amount
        // stays an int), boolean And/Or are logical, and bitwise ops on enums
        // have their own handling — so we keep this conservative.
        switch (op)
        {
            case BinaryOperator.Add:
            case BinaryOperator.Subtract:
            case BinaryOperator.Multiply:
            case BinaryOperator.Divide:
            case BinaryOperator.Modulo:
            case BinaryOperator.Less:
            case BinaryOperator.Greater:
            case BinaryOperator.LessOrEqual:
            case BinaryOperator.GreaterOrEqual:
            case BinaryOperator.Equal:
            case BinaryOperator.NotEqual:
                break;
            default:
                return false;
        }

        var left = Nullable.GetUnderlyingType(leftType) ?? leftType;
        var right = Nullable.GetUnderlyingType(rightType) ?? rightType;

        if (left == right)
        {
            return false;
        }

        // Enums/user types/decimal are not handled by the raw opcode path.
        if (TryGetEnumUnderlyingType(left) != null || TryGetEnumUnderlyingType(right) != null)
        {
            return false;
        }

        if (!IsPrimitiveNumericType(left) || !IsPrimitiveNumericType(right))
        {
            return false;
        }

        if (left == typeof(decimal) || right == typeof(decimal))
        {
            return false;
        }

        var common = GetBinaryNumericCommonType(left, right);
        if (common == null)
        {
            return false;
        }

        promotedType = common;
        return true;
    }

    private static bool IsPrimitiveNumericType(Type type)
    {
        return type == typeof(byte)
            || type == typeof(sbyte)
            || type == typeof(short)
            || type == typeof(ushort)
            || type == typeof(int)
            || type == typeof(uint)
            || type == typeof(long)
            || type == typeof(ulong)
            || type == typeof(char)
            || type == typeof(float)
            || type == typeof(double);
    }

    /// <summary>
    /// Returns the C# binary-numeric-promotion result type for two primitive
    /// numeric operand types, or null if no well-defined common type applies
    /// (e.g. ulong combined with a signed type, which C# also rejects).
    /// </summary>
    private static Type? GetBinaryNumericCommonType(Type left, Type right)
    {
        // Floating point dominates.
        if (left == typeof(double) || right == typeof(double))
        {
            return typeof(double);
        }
        if (left == typeof(float) || right == typeof(float))
        {
            return typeof(float);
        }

        // ulong: only combinable with other unsigned/known-non-negative types.
        if (left == typeof(ulong) || right == typeof(ulong))
        {
            var other = left == typeof(ulong) ? right : left;
            if (other == typeof(ulong)
                || other == typeof(uint)
                || other == typeof(ushort)
                || other == typeof(byte)
                || other == typeof(char))
            {
                return typeof(ulong);
            }
            return null;
        }

        if (left == typeof(long) || right == typeof(long))
        {
            return typeof(long);
        }

        // uint with a signed type that doesn't fit (int/short/sbyte) promotes to
        // long; uint with unsigned/char stays uint.
        if (left == typeof(uint) || right == typeof(uint))
        {
            var other = left == typeof(uint) ? right : left;
            if (other == typeof(uint)
                || other == typeof(ushort)
                || other == typeof(byte)
                || other == typeof(char))
            {
                return typeof(uint);
            }
            return typeof(long);
        }

        // Everything narrower (int/uint/short/ushort/sbyte/byte/char) promotes to int.
        return typeof(int);
    }

    private bool TryEmitNumericConversion(Type sourceType, Type targetType)
    {
        if (!IsNumericConversionType(sourceType) || !IsNumericConversionType(targetType))
        {
            return false;
        }

        if ((Nullable.GetUnderlyingType(sourceType) ?? sourceType) == typeof(decimal)
            || (Nullable.GetUnderlyingType(targetType) ?? targetType) == typeof(decimal))
        {
            return false;
        }

        if (_overflowCheckingEnabled && TryGetCheckedNumericConversionOpcode(sourceType, targetType, out var checkedOpcode))
        {
            _currentIL!.Emit(checkedOpcode);
            return true;
        }

        if (!TryGetNumericConversionOpcode(targetType, out var opcode))
        {
            return false;
        }

        _currentIL!.Emit(opcode);
        return true;
    }
}
