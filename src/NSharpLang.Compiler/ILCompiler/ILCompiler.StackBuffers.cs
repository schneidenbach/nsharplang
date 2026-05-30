using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;

namespace NSharpLang.Compiler.ILCompiler;

public partial class ILCompiler
{
    /// <summary>
    /// Per-method-body record describing a local array that has been promoted from a heap array
    /// to a stack-allocated <c>[InlineArray]</c> buffer. The local's <see cref="LocalBuilder"/>
    /// is the value-type buffer struct (a stack slot); reads and writes go through interior
    /// managed pointers (<c>Unsafe.As</c> + <c>Unsafe.Add</c>) with explicit bounds checks. No
    /// <see cref="Span{T}"/> value, helper method, or raw pointer is ever materialised, which keeps
    /// the emitted IL fully verifiable and GC-safe (a stack-local struct is never relocated and the
    /// interior byref only lives on the evaluation stack for a single load/store).
    /// </summary>
    private sealed record PromotedStackBufferStorage(
        LocalBuilder Buffer,
        Type StructType,
        Type ElementType,
        int Length);

    /// <summary>
    /// Resolved <c>Unsafe.As&lt;TFrom,TTo&gt;(ref TFrom)</c> open generic method definition.
    /// </summary>
    private static readonly MethodInfo UnsafeAsOpenMethod = typeof(Unsafe)
        .GetMethods(BindingFlags.Public | BindingFlags.Static)
        .First(method => method.Name == "As"
            && method.IsGenericMethodDefinition
            && method.GetGenericArguments().Length == 2
            && method.GetParameters().Length == 1
            && method.GetParameters()[0].ParameterType.IsByRef);

    /// <summary>
    /// Runs stack-buffer promotion analysis for the body about to be emitted and records the
    /// decisions in <see cref="_promotedBuffers"/>. Must be called after the body context and IL
    /// generator are initialised (it declares the buffer locals up front) and before the body is
    /// emitted. Bodies that are async, generators, or that capture locals never promote (the
    /// analysis returns nothing), so this is a no-op for them.
    /// </summary>
    private void InitializeStackBufferPromotions(
        BlockStatement? body,
        IReadOnlyList<Parameter> parameters,
        bool isAsync,
        bool isGenerator)
    {
        _promotedBuffers = null;

        if (body is null || _currentIL == null)
        {
            return;
        }

        // Capture lifting and stack promotion are mutually exclusive: a promoted buffer must live
        // in a plain stack slot, never a lifted box. If the body lifts any locals into boxes
        // (closure capture), skip promotion entirely to stay conservative.
        if (_liftLocalsIntoBoxes)
        {
            return;
        }

        var promotions = StackBufferPromotionAnalysis.Analyze(body, parameters, isAsync, isGenerator);
        if (promotions.Count == 0)
        {
            return;
        }

        var storage = new Dictionary<string, PromotedStackBufferStorage>(StringComparer.Ordinal);
        foreach (var promotion in promotions)
        {
            // A promoted name must not collide with a lifted/captured local.
            if (_localsToLiftIntoBoxes?.Contains(promotion.Name) == true
                || _localsToPredeclareForCapture?.Contains(promotion.Name) == true)
            {
                continue;
            }

            // A promoted name must not collide with an instance/static member (field or property) of
            // the current type. `_promotedBuffers` is method-wide and string-keyed, so without this
            // guard a member access such as `buf.Length` that should bind to a field could be
            // intercepted and lowered to the stack buffer. The analysis already requires the local to
            // be a single top-level declaration; this closes the remaining field/property case.
            if (TryResolveCurrentTypeMember(promotion.Name, out _, out _, out _, out _))
            {
                continue;
            }

            var elementType = ResolveType(new SimpleTypeReference(promotion.ElementTypeName), _currentGenericParameters);
            var structType = GetOrCreateStackBufferStructType(promotion.Length, elementType);
            var bufferLocal = _currentIL.DeclareLocal(structType);
            storage[promotion.Name] = new PromotedStackBufferStorage(bufferLocal, structType, elementType, promotion.Length);
        }

        _promotedBuffers = storage.Count > 0 ? storage : null;
    }

    /// <summary>True when <paramref name="name"/> is a stack-promoted buffer in the current body.</summary>
    private bool TryGetPromotedBuffer(string name, out PromotedStackBufferStorage storage)
    {
        if (_promotedBuffers != null && _promotedBuffers.TryGetValue(name, out var found))
        {
            storage = found;
            return true;
        }

        storage = null!;
        return false;
    }

    /// <summary>
    /// Returns (creating on first use) the synthesized <c>[InlineArray(length)]</c> value-type
    /// struct used to back a stack buffer of <paramref name="length"/> elements of
    /// <paramref name="elementType"/>. The struct has a single element field, as required by
    /// <see cref="InlineArrayAttribute"/>; the runtime lays out <paramref name="length"/> contiguous
    /// copies of it. Structs are finalised alongside the other generated helper types.
    /// </summary>
    private TypeBuilder GetOrCreateStackBufferStructType(int length, Type elementType)
    {
        var key = (length, elementType);
        if (_stackBufferStructTypes.TryGetValue(key, out var existing))
        {
            return existing;
        }

        if (_moduleBuilder == null)
        {
            throw new InvalidOperationException("Module builder has not been initialized");
        }

        var structType = _moduleBuilder.DefineType(
            $"<>StackBuffer{_stackBufferStructCounter++}",
            TypeAttributes.NotPublic | TypeAttributes.SequentialLayout | TypeAttributes.Sealed | TypeAttributes.AnsiClass | TypeAttributes.BeforeFieldInit,
            typeof(ValueType));

        // The single element field. InlineArray requires exactly one instance field.
        structType.DefineField("_element0", elementType, FieldAttributes.Private);

        var inlineArrayCtor = typeof(InlineArrayAttribute).GetConstructor(new[] { typeof(int) })
            ?? throw new InvalidOperationException("Could not resolve InlineArrayAttribute(int) constructor");
        structType.SetCustomAttribute(new CustomAttributeBuilder(inlineArrayCtor, new object[] { length }));

        _generatedHelperTypes.Add(structType);
        _stackBufferStructTypes[key] = structType;
        return structType;
    }

    /// <summary>
    /// Emits the initialization of a promoted stack buffer from its array-literal initializer:
    /// zero-initialise the struct, then store each constant-position element through an interior
    /// byref. No heap array is allocated.
    /// </summary>
    private void EmitPromotedBufferDeclaration(PromotedStackBufferStorage storage, ArrayLiteralExpression literal)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        // buffer = default
        _currentIL.Emit(OpCodes.Ldloca, storage.Buffer);
        _currentIL.Emit(OpCodes.Initobj, storage.StructType);

        for (var i = 0; i < literal.Elements.Count; i++)
        {
            // ref element[i]
            EmitPromotedBufferElementAddress(storage, EmitConstantIndex(i));
            EmitExpressionWithExpectedType(literal.Elements[i], storage.ElementType);
            EmitStoreIndirect(storage.ElementType);
        }
    }

    /// <summary>
    /// Emits a bounds-checked load of <c>buffer[index]</c> for a promoted stack buffer. The index
    /// expression is evaluated once into a temp, range-checked against the constant length, then
    /// used to compute an interior byref that is dereferenced immediately.
    /// </summary>
    private void EmitPromotedBufferIndexLoad(PromotedStackBufferStorage storage, Expression index)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var indexLocal = EvaluateIndexWithBoundsCheck(storage, index);
        EmitPromotedBufferElementAddress(storage, indexLocal);
        EmitLoadIndirect(storage.ElementType);
    }

    /// <summary>
    /// Emits a bounds-checked store of <paramref name="valueEmitter"/> into <c>buffer[index]</c>
    /// for a promoted stack buffer. Evaluation order matches array semantics: index first (with
    /// bounds check), then the value, then the store. The destination byref is only computed after
    /// the value is on the stack, so it is never held across the value's evaluation.
    /// </summary>
    private void EmitPromotedBufferIndexStore(PromotedStackBufferStorage storage, Expression index, Action valueEmitter)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var indexLocal = EvaluateIndexWithBoundsCheck(storage, index);

        // Evaluate the value into a temp so the destination byref is computed last and held only
        // momentarily across the single stind.
        var valueLocal = _currentIL.DeclareLocal(storage.ElementType);
        valueEmitter();
        _currentIL.Emit(OpCodes.Stloc, valueLocal);

        EmitPromotedBufferElementAddress(storage, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, valueLocal);
        EmitStoreIndirect(storage.ElementType);
    }

    /// <summary>Emits the constant <c>Length</c> of a promoted stack buffer.</summary>
    private void EmitPromotedBufferLength(PromotedStackBufferStorage storage)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");
        _currentIL.Emit(OpCodes.Ldc_I4, storage.Length);
    }

    /// <summary>
    /// Evaluates an index expression into an int local and emits a fail-fast bounds check
    /// (<c>(uint)index &gt;= (uint)length</c> throws <see cref="IndexOutOfRangeException"/>),
    /// matching array element-access semantics. Returns the local holding the validated index.
    /// </summary>
    private LocalBuilder EvaluateIndexWithBoundsCheck(PromotedStackBufferStorage storage, Expression index)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var indexLocal = _currentIL.DeclareLocal(typeof(int));
        EmitExpressionWithExpectedType(index, typeof(int));
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        // if ((uint)index < (uint)length) goto ok; else throw;
        var okLabel = _currentIL.DefineLabel();
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4, storage.Length);
        // Unsigned comparison folds the negative-index case into the out-of-range case.
        _currentIL.Emit(OpCodes.Blt_Un, okLabel);

        var ctor = typeof(IndexOutOfRangeException).GetConstructor(Type.EmptyTypes)
            ?? throw new InvalidOperationException("Could not resolve IndexOutOfRangeException() constructor");
        _currentIL.Emit(OpCodes.Newobj, ctor);
        _currentIL.Emit(OpCodes.Throw);

        _currentIL.MarkLabel(okLabel);
        return indexLocal;
    }

    /// <summary>
    /// Emits the interior managed pointer to element <c>index</c> of a promoted stack buffer:
    /// <c>Unsafe.Add(ref Unsafe.As&lt;TBuffer,TElement&gt;(ref buffer), index)</c>. The byref is
    /// left on the evaluation stack for an immediate ldind/stind by the caller.
    /// </summary>
    private void EmitPromotedBufferElementAddress(PromotedStackBufferStorage storage, LocalBuilder index)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldloca, storage.Buffer);
        _currentIL.Emit(OpCodes.Call, UnsafeAsOpenMethod.MakeGenericMethod(storage.StructType, storage.ElementType));
        _currentIL.Emit(OpCodes.Ldloc, index);
        _currentIL.Emit(OpCodes.Call, ResolveUnsafeAddMethod(storage.ElementType));
    }

    /// <summary>
    /// Overload of <see cref="EmitPromotedBufferElementAddress(PromotedStackBufferStorage, LocalBuilder)"/>
    /// for a constant index, used by the literal initializer where the index is statically known.
    /// </summary>
    private void EmitPromotedBufferElementAddress(PromotedStackBufferStorage storage, int constantIndex)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        _currentIL.Emit(OpCodes.Ldloca, storage.Buffer);
        _currentIL.Emit(OpCodes.Call, UnsafeAsOpenMethod.MakeGenericMethod(storage.StructType, storage.ElementType));
        _currentIL.Emit(OpCodes.Ldc_I4, constantIndex);
        _currentIL.Emit(OpCodes.Call, ResolveUnsafeAddMethod(storage.ElementType));
    }

    /// <summary>
    /// Helper: declares an int local pre-loaded with a constant, for the constant-index element
    /// address path. (Kept tiny to avoid duplicating the address-emit logic for constants.)
    /// </summary>
    private LocalBuilder EmitConstantIndex(int value)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");
        var local = _currentIL.DeclareLocal(typeof(int));
        _currentIL.Emit(OpCodes.Ldc_I4, value);
        _currentIL.Emit(OpCodes.Stloc, local);
        return local;
    }

    /// <summary>
    /// Emits a <c>buf[i] = v</c> or compound <c>buf[i] op= v</c> assignment to a promoted stack
    /// buffer, leaving the assigned value on the stack (matching the existing array-assignment
    /// contract). Index evaluation and bounds check happen first; for compound assignment the
    /// current element is read once, combined with the RHS, and the result stored.
    /// </summary>
    private void EmitPromotedBufferAssignment(
        AssignmentExpression assignment,
        IndexAccessExpression indexAccess,
        PromotedStackBufferStorage storage)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        var indexLocal = EvaluateIndexWithBoundsCheck(storage, indexAccess.Index);
        var resultLocal = _currentIL.DeclareLocal(storage.ElementType);

        if (assignment.Operator == AssignmentOperator.Assign)
        {
            if (assignment.Value is DefaultExpression)
            {
                EmitDefaultValue(storage.ElementType);
            }
            else
            {
                EmitExpressionWithExpectedType(assignment.Value, storage.ElementType);
            }

            _currentIL.Emit(OpCodes.Stloc, resultLocal);
        }
        else
        {
            // current = buffer[index]
            EmitPromotedBufferElementAddress(storage, indexLocal);
            EmitLoadIndirect(storage.ElementType);
            EmitExpressionWithExpectedType(assignment.Value, storage.ElementType);

            EmitCompoundAssignmentOperation(assignment.Operator, storage.ElementType);

            _currentIL.Emit(OpCodes.Stloc, resultLocal);
        }

        // buffer[index] = result
        EmitPromotedBufferElementAddress(storage, indexLocal);
        _currentIL.Emit(OpCodes.Ldloc, resultLocal);
        EmitStoreIndirect(storage.ElementType);

        // Leave the assigned value on the stack.
        _currentIL.Emit(OpCodes.Ldloc, resultLocal);
    }

    /// <summary>
    /// Emits an allocation-free <c>foreach</c> over a promoted stack buffer using a counted index
    /// loop and the same interior-byref element load as indexing. No enumerator, no Span, no heap
    /// array.
    /// </summary>
    private void EmitForeachForPromotedBuffer(ForeachStatement foreachStmt, PromotedStackBufferStorage storage)
    {
        if (_currentIL == null || _locals == null) throw new InvalidOperationException("No IL generator context");

        var indexLocal = _currentIL.DeclareLocal(typeof(int));
        _currentIL.Emit(OpCodes.Ldc_I4_0);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        var loopStart = _currentIL.DefineLabel();
        var continueLabel = _currentIL.DefineLabel();
        var loopEnd = _currentIL.DefineLabel();

        _currentIL.MarkLabel(loopStart);

        // if (index >= length) break;
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4, storage.Length);
        _currentIL.Emit(OpCodes.Bge, loopEnd);

        // element = buffer[index]
        EmitPromotedBufferElementAddress(storage, indexLocal);
        EmitLoadIndirect(storage.ElementType);

        LocalBuilder loopVar;
        if (_locals.TryGetValue(foreachStmt.VariableName, out var existingLoopVar))
        {
            loopVar = existingLoopVar;
        }
        else
        {
            loopVar = DeclareNamedLocal(foreachStmt.VariableName, storage.ElementType);
        }

        if (IsLiftedIdentifier(foreachStmt.VariableName))
        {
            EmitStoreLiftedLocalValue(loopVar, storage.ElementType, leaveValueOnStack: false);
        }
        else
        {
            _currentIL.Emit(OpCodes.Stloc, loopVar);
        }

        _breakLabels.Push(new BranchTarget(loopEnd, useLeave: false));
        _continueLabels.Push(new BranchTarget(continueLabel, useLeave: false));
        try
        {
            EmitStatement(foreachStmt.Body);
        }
        finally
        {
            _continueLabels.Pop();
            _breakLabels.Pop();
        }

        _currentIL.MarkLabel(continueLabel);

        // index++
        _currentIL.Emit(OpCodes.Ldloc, indexLocal);
        _currentIL.Emit(OpCodes.Ldc_I4_1);
        _currentIL.Emit(OpCodes.Add);
        _currentIL.Emit(OpCodes.Stloc, indexLocal);

        _currentIL.Emit(OpCodes.Br, loopStart);
        _currentIL.MarkLabel(loopEnd);
    }
}
