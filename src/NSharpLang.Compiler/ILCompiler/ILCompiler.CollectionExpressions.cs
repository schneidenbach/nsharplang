using System;
using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    private bool TryGetCollectionExpressionEmissionType(Type? expectedType, out Type actualType, out Type elementType)
    {
        actualType = typeof(object[]);
        elementType = typeof(object);

        if (expectedType == null)
        {
            return false;
        }

        expectedType = GetByRefElementType(expectedType);
        if (expectedType == typeof(object))
        {
            return false;
        }

        if (expectedType.IsArray)
        {
            actualType = expectedType;
            elementType = expectedType.GetElementType() ?? typeof(object);
            return true;
        }

        if (!TryGetSequenceElementType(expectedType, out elementType, out _))
        {
            return false;
        }

        if (!expectedType.IsInterface && !expectedType.IsAbstract)
        {
            actualType = expectedType;
            return true;
        }

        var listType = typeof(List<>).MakeGenericType(elementType);
        if (expectedType.IsAssignableFrom(listType))
        {
            actualType = listType;
            return true;
        }

        var hashSetType = typeof(HashSet<>).MakeGenericType(elementType);
        if (expectedType.IsAssignableFrom(hashSetType))
        {
            actualType = hashSetType;
            return true;
        }

        var queueType = typeof(Queue<>).MakeGenericType(elementType);
        if (expectedType.IsAssignableFrom(queueType))
        {
            actualType = queueType;
            return true;
        }

        return false;
    }

    private void EmitCollectionExpression(ArrayLiteralExpression arrayLiteral, Type targetType, Type elementType)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        var listType = typeof(List<>).MakeGenericType(elementType);
        var enumerableType = typeof(IEnumerable<>).MakeGenericType(elementType);
        var listCtor = listType.GetConstructor(Type.EmptyTypes)
            ?? throw new InvalidOperationException($"Could not resolve constructor for {listType}");
        var listAddMethod = listType.GetMethod("Add", new[] { elementType })
            ?? throw new InvalidOperationException($"Could not resolve Add({elementType}) on {listType}");
        var addRangeMethod = listType.GetMethod("AddRange", new[] { enumerableType })
            ?? throw new InvalidOperationException($"Could not resolve AddRange({enumerableType}) on {listType}");

        _currentIL.Emit(OpCodes.Newobj, listCtor);
        var listLocal = _currentIL.DeclareLocal(listType);
        _currentIL.Emit(OpCodes.Stloc, listLocal);

        foreach (var element in arrayLiteral.Elements)
        {
            _currentIL.Emit(OpCodes.Ldloc, listLocal);
            if (element is SpreadExpression spread)
            {
                EmitExpressionWithExpectedType(spread.Expression, enumerableType);
                _currentIL.Emit(OpCodes.Callvirt, addRangeMethod);
            }
            else
            {
                EmitExpressionWithExpectedType(element, elementType);
                _currentIL.Emit(OpCodes.Callvirt, listAddMethod);
            }
        }

        if (targetType == listType)
        {
            _currentIL.Emit(OpCodes.Ldloc, listLocal);
            return;
        }

        if (targetType.IsArray)
        {
            var toArrayMethod = listType.GetMethod("ToArray", Type.EmptyTypes)
                ?? throw new InvalidOperationException($"Could not resolve ToArray() on {listType}");
            _currentIL.Emit(OpCodes.Ldloc, listLocal);
            _currentIL.Emit(OpCodes.Callvirt, toArrayMethod);
            return;
        }

        var enumerableCtor = targetType.GetConstructor(new[] { enumerableType });
        if (enumerableCtor != null)
        {
            _currentIL.Emit(OpCodes.Ldloc, listLocal);
            _currentIL.Emit(OpCodes.Newobj, enumerableCtor);
            return;
        }

        var defaultCtor = targetType.GetConstructor(Type.EmptyTypes);
        var targetAddMethod = ResolveCollectionAddMethod(targetType, elementType);
        if (defaultCtor == null || targetAddMethod == null)
        {
            throw new NotImplementedException($"Collection expressions are not yet supported for target type {targetType}");
        }

        _currentIL.Emit(OpCodes.Newobj, defaultCtor);
        var targetLocal = _currentIL.DeclareLocal(targetType);
        _currentIL.Emit(OpCodes.Stloc, targetLocal);

        var countGetter = listType.GetProperty("Count")?.GetMethod
            ?? throw new InvalidOperationException($"Could not resolve Count on {listType}");
        var itemGetter = listType.GetProperty("Item")?.GetMethod
            ?? throw new InvalidOperationException($"Could not resolve Item on {listType}");
        var indexLocal = _currentIL.DeclareLocal(typeof(int));
        var countLocal = _currentIL.DeclareLocal(typeof(int));
        var loopStartLabel = _currentIL.DefineLabel();
        var loopEndLabel = _currentIL.DefineLabel();

        _currentIL.Emit(OpCodes.Ldloc, listLocal);
        _currentIL.Emit(OpCodes.Callvirt, countGetter);
        _currentIL.Emit(OpCodes.Stloc, countLocal);

        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        _currentIL.MarkLabel(loopStartLabel);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, countLocal);
        _currentIL.Emit(OpCodes.Bge, loopEndLabel);

        _currentIL.Emit(OpCodes.Ldloc, targetLocal);
        _currentIL.Emit(OpCodes.Ldloc, listLocal);
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Callvirt, itemGetter);
        _currentIL.Emit(OpCodes.Callvirt, targetAddMethod);

        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4_1);
        _currentIL.Emit(OpCodes.Add);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);
        _currentIL.Emit(OpCodes.Br, loopStartLabel);

        _currentIL.MarkLabel(loopEndLabel);
        _currentIL.Emit(OpCodes.Ldloc, targetLocal);
    }

    private static MethodInfo? ResolveCollectionAddMethod(Type targetType, Type elementType)
    {
        return targetType.GetMethod("Add", new[] { elementType })
            ?? targetType.GetMethod("Enqueue", new[] { elementType });
    }
}
