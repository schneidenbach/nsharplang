using System;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.ILCompiler;

/// <summary>
/// IL emission for the <c>on</c>/<c>off</c> event-subscription keywords. <c>on</c> lowers to the
/// event's <c>add_</c> accessor (the analyzer has already rejected any <c>+=</c>/<c>-=</c> against
/// an event), and yields an <see cref="Runtime.NSharpEventSubscription"/> handle. <c>off</c> calls
/// <see cref="Runtime.NSharpEventSubscription.Unsubscribe"/> on that handle.
/// </summary>
public partial class ILCompiler
{
    private const BindingFlags EventLookupFlags =
        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        | BindingFlags.Static | BindingFlags.FlattenHierarchy;

    /// <summary>
    /// Emit a bare <c>on …</c> statement (fire-and-forget): subscribe without building a handle.
    /// Returns true so the expression-statement path skips its result-discarding pop.
    /// </summary>
    private bool EmitOnSubscriptionStatement(OnSubscriptionExpression on)
    {
        EmitOnSubscriptionCore(on, produceHandle: false);
        return true;
    }

    private void EmitOnSubscriptionCore(OnSubscriptionExpression on, bool produceHandle)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (on.Target is not MemberAccessExpression memberAccess)
        {
            throw new InvalidOperationException("`on` target must be an event member access");
        }

        var (eventInfo, isStatic) = ResolveEventForEmit(memberAccess);
        var addMethod = eventInfo.GetAddMethod(nonPublic: true)
            ?? throw new InvalidOperationException($"Event '{eventInfo.Name}' has no accessible add accessor");
        var removeMethod = eventInfo.GetRemoveMethod(nonPublic: true)
            ?? throw new InvalidOperationException($"Event '{eventInfo.Name}' has no accessible remove accessor");
        var handlerType = eventInfo.EventHandlerType
            ?? throw new InvalidOperationException($"Event '{eventInfo.Name}' has no handler type");

        // Evaluate the receiver once (instance events) and reuse it for both add_ and the bound
        // remove_ accessor, so the subscription detaches from the exact same object.
        LocalBuilder? receiverLocal = null;
        if (!isStatic)
        {
            EmitExpression(memberAccess.Object);
            receiverLocal = _currentIL.DeclareLocal(GetExpressionType(memberAccess.Object));
            _currentIL.Emit(OpCodes.Stloc, receiverLocal);
        }

        // Build the handler delegate of the event's exact handler type. Emitting with the handler
        // type as the expected type drives both the lambda's parameter-type inference and the
        // delegate-type selection, so the result is the event's delegate (not Action<object,…>).
        EmitExpressionWithExpectedType(on.Handler, handlerType);
        var handlerLocal = _currentIL.DeclareLocal(handlerType);
        _currentIL.Emit(OpCodes.Stloc, handlerLocal);

        // add_Event(handler)
        if (!isStatic)
        {
            _currentIL.Emit(OpCodes.Ldloc, receiverLocal!);
        }
        _currentIL.Emit(OpCodes.Ldloc, handlerLocal);
        _currentIL.Emit(isStatic ? OpCodes.Call : OpCodes.Callvirt, addMethod);

        if (!produceHandle)
        {
            return;
        }

        // new NSharpEventSubscription<THandler>(boundRemove, handler), where boundRemove is the
        // remove_ accessor already bound to the receiver. This keeps unsubscribe reflection-free.
        var actionType = typeof(Action<>).MakeGenericType(handlerType);
        var subscriptionType = typeof(Runtime.NSharpEventSubscription<>).MakeGenericType(handlerType);

        EmitBoundAccessorDelegate(removeMethod, actionType, isStatic, receiverLocal);
        _currentIL.Emit(OpCodes.Ldloc, handlerLocal);

        var subscriptionCtor = subscriptionType.GetConstructor(new[] { actionType, handlerType })
            ?? throw new InvalidOperationException("Could not resolve NSharpEventSubscription<> constructor");
        _currentIL.Emit(OpCodes.Newobj, subscriptionCtor);
    }

    /// <summary>
    /// Build a delegate of <paramref name="delegateType"/> (an <c>Action&lt;THandler&gt;</c>) bound to
    /// the given accessor method, mirroring how method-group conversions create bound delegates.
    /// </summary>
    private void EmitBoundAccessorDelegate(MethodInfo accessor, Type delegateType, bool isStatic, LocalBuilder? receiverLocal)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        if (isStatic)
        {
            _currentIL.Emit(OpCodes.Ldnull);
            _currentIL.Emit(OpCodes.Ldftn, accessor);
        }
        else
        {
            _currentIL.Emit(OpCodes.Ldloc, receiverLocal!);
            if (accessor.IsVirtual && !accessor.IsFinal)
            {
                _currentIL.Emit(OpCodes.Dup);
                _currentIL.Emit(OpCodes.Ldvirtftn, accessor);
            }
            else
            {
                _currentIL.Emit(OpCodes.Ldftn, accessor);
            }
        }

        _currentIL.Emit(OpCodes.Newobj, GetDelegateConstructor(delegateType));
    }

    private void EmitOff(OffStatement off)
    {
        if (_currentIL == null) throw new InvalidOperationException("No IL generator context");

        EmitExpression(off.Handle);
        var unsubscribe = typeof(Runtime.NSharpEventSubscription).GetMethod(
            nameof(Runtime.NSharpEventSubscription.Unsubscribe))
            ?? throw new InvalidOperationException("Could not resolve NSharpEventSubscription.Unsubscribe()");
        _currentIL.Emit(OpCodes.Callvirt, unsubscribe);
    }

    private (EventInfo Event, bool IsStatic) ResolveEventForEmit(MemberAccessExpression memberAccess)
    {
        var declaringType = TryResolveStaticContainer(memberAccess.Object, out var staticType)
            ? staticType
            : GetExpressionType(memberAccess.Object);

        var eventInfo = declaringType.GetEvent(memberAccess.MemberName, EventLookupFlags)
            ?? throw new InvalidOperationException($"Event '{memberAccess.MemberName}' not found on {declaringType}");

        var isStatic = eventInfo.GetAddMethod(nonPublic: true)?.IsStatic ?? false;
        return (eventInfo, isStatic);
    }
}
