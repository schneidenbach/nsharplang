using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Threading.Tasks;

namespace NSharpLang.Compiler.ILCompiler;

/// <summary>
/// Async-method lowering for the IL backend.
///
/// N# does not (yet) emit real <c>IAsyncStateMachine</c> / <c>MoveNext</c> codegen. Every
/// <c>async</c> method body is lowered to run synchronously, and the result is wrapped into a
/// completed (or faulted) <c>Task</c>/<c>ValueTask</c> at the return points. This file owns the
/// pieces of that lowering that are specific to async semantics:
///
/// <list type="bullet">
/// <item>
///   <description>
///   <b>Exception-as-faulted-task parity.</b> Because the body runs synchronously, an exception
///   thrown in the body would otherwise escape the method synchronously. That violates C#
///   semantics, where an <c>async</c> method captures the exception and returns a <i>faulted</i>
///   task. <see cref="BeginAsyncFaultGuard"/> / <see cref="EndAsyncFaultGuard"/> wrap the body in a
///   <c>try/catch(Exception)</c> that converts a thrown exception into a faulted task on the
///   structured-return path, matching C# exactly.
///   </description>
/// </item>
/// <item>
///   <description>
///   <b>Pooled-builder selection plumbing.</b> <see cref="ResolveAsyncMethodBuilderType"/> and
///   <see cref="ApplyAsyncMethodBuilderAttribute"/> wire the opt-in surface for
///   <c>PoolingAsyncValueTaskMethodBuilder</c>. The attribute is only meaningful once a real state
///   machine exists, so emission is gated on that and is currently a no-op (see DEFERRED note
///   below). The selection point and project/attribute surface are in place so the state-machine
///   work can slot in without re-plumbing.
///   </description>
/// </item>
/// </list>
///
/// DEFERRED: real async state machines (<c>IAsyncStateMachine</c>/<c>MoveNext</c>, suspension at
/// <c>await</c>, pooled builders actually driving the machine) are not implemented. See
/// docs/design/performance-compiler-refactor.md (Async &amp; Iterators).
/// </summary>
public partial class ILCompiler
{
    /// <summary>
    /// When the guarded body already emitted its full completion (e.g. an expression-bodied async
    /// method), this is set so <see cref="EndAsyncFaultGuard"/> does not emit a second, unreachable
    /// fall-through completion.
    /// </summary>
    private bool _asyncFaultGuardCompletionEmitted;

    /// <summary>
    /// Emits the return for a task value already on the stack inside an async body. When the body is
    /// wrapped in the fault guard the value must be routed through the structured-return path
    /// (store + <c>leave</c>); a bare <c>ret</c> is illegal inside the protected region.
    /// </summary>
    private void EmitAsyncReturnFromValueOnStack(bool inFaultGuard)
    {
        if (_currentIL == null)
        {
            throw new InvalidOperationException("No IL generator context");
        }

        if (inFaultGuard)
        {
            EmitStructuredReturnValueOnStack();
            _asyncFaultGuardCompletionEmitted = true;
            return;
        }

        _currentIL.Emit(OpCodes.Ret);
    }

    /// <summary>
    /// Snapshot of the per-method return-flow context that must be isolated while a nested method
    /// body (lambda / local function) is emitted into its own IL generator. These fields reference
    /// the enclosing method's IL generator (labels, locals) and its protected-region depth, so they
    /// must be reset for the nested body and restored afterward — otherwise the nested body would
    /// emit returns against the wrong generator.
    /// </summary>
    private readonly record struct NestedMethodReturnContext(
        Label? ReturnLabel,
        LocalBuilder? ReturnLocal,
        bool UsesStructuredReturn,
        int ExceptionBlockDepth,
        bool AsyncFaultGuardCompletionEmitted);

    /// <summary>
    /// Captures and clears the return-flow context before emitting a nested method body. Pair with
    /// <see cref="RestoreNestedMethodReturnContext"/>.
    /// </summary>
    private NestedMethodReturnContext SaveAndResetNestedMethodReturnContext()
    {
        var saved = new NestedMethodReturnContext(
            _currentReturnLabel,
            _currentReturnLocal,
            _usesStructuredReturn,
            _exceptionBlockDepth,
            _asyncFaultGuardCompletionEmitted);

        _currentReturnLabel = null;
        _currentReturnLocal = null;
        _usesStructuredReturn = false;
        _exceptionBlockDepth = 0;
        _asyncFaultGuardCompletionEmitted = false;
        return saved;
    }

    /// <summary>Restores the return-flow context captured by <see cref="SaveAndResetNestedMethodReturnContext"/>.</summary>
    private void RestoreNestedMethodReturnContext(NestedMethodReturnContext saved)
    {
        _currentReturnLabel = saved.ReturnLabel;
        _currentReturnLocal = saved.ReturnLocal;
        _usesStructuredReturn = saved.UsesStructuredReturn;
        _exceptionBlockDepth = saved.ExceptionBlockDepth;
        _asyncFaultGuardCompletionEmitted = saved.AsyncFaultGuardCompletionEmitted;
    }

    /// <summary>
    /// Opens the async fault guard for the current method when it is an async method. Returns
    /// <c>true</c> when a guard was opened (the caller must balance it with
    /// <see cref="EndAsyncFaultGuard"/>).
    ///
    /// While the guard is open the body is inside a protected region, so every <c>return</c> already
    /// routes through the structured-return mechanism (see <c>_exceptionBlockDepth</c>). The trailing
    /// fall-through must do the same, which <see cref="EndAsyncFaultGuard"/> handles.
    /// </summary>
    private bool BeginAsyncFaultGuard()
    {
        if (_currentIL == null || _currentAsyncReturnType == null)
        {
            return false;
        }

        // The fault guard relies on the structured-return mechanism to merge the normal-completion
        // path and the catch path onto a single return label, so a return slot must exist.
        if (_currentReturnLabel == null)
        {
            return false;
        }

        _currentIL.BeginExceptionBlock();
        _exceptionBlockDepth++;
        _asyncFaultGuardCompletionEmitted = false;
        return true;
    }

    /// <summary>
    /// Emits the normal-completion fall-through (when the body can fall off the end), the
    /// <c>catch (Exception)</c> that converts a thrown exception into a faulted task, closes the
    /// protected region, and finally marks the shared structured-return target so the method
    /// returns the stored task.
    /// </summary>
    private void EndAsyncFaultGuard()
    {
        if (_currentIL == null || _currentAsyncReturnType == null || _currentReturnLabel == null)
        {
            throw new InvalidOperationException("No async fault guard context");
        }

        // Normal completion fall-through: a unit-returning async body (Task / ValueTask with no
        // result) can run off the end without an explicit return. Wrap the completed task and route
        // it through the structured return so it joins the single return label. A result-typed body
        // must always return explicitly, so no fall-through completion is emitted for it. Skip when
        // the body already emitted its full completion (e.g. an expression-bodied method).
        if (_currentAsyncResultType == null && !_asyncFaultGuardCompletionEmitted)
        {
            EmitWrapCurrentAsyncReturn();
            EmitStructuredReturnValueOnStack();
        }

        // catch (Exception ex) -> return a faulted task carrying ex, matching C# async semantics.
        _currentIL.BeginCatchBlock(typeof(Exception));
        EmitFaultedAsyncReturn();
        EmitStructuredReturnValueOnStack();

        _currentIL.EndExceptionBlock();
        _exceptionBlockDepth--;

        // Single exit: load the stored task and return.
        EmitStructuredReturnTarget();
    }

    /// <summary>
    /// Given an <see cref="Exception"/> on the evaluation stack, leaves a faulted
    /// <c>Task</c>/<c>Task&lt;T&gt;</c>/<c>ValueTask</c>/<c>ValueTask&lt;T&gt;</c> on the stack that
    /// carries that exception. Mirrors what a C# async method produces when its body throws.
    /// </summary>
    private void EmitFaultedAsyncReturn()
    {
        if (_currentIL == null || _currentAsyncReturnType == null)
        {
            throw new InvalidOperationException("No async return context");
        }

        // Stack: [Exception]
        if (_currentAsyncResultType == null)
        {
            var fromException = typeof(Task)
                .GetMethods(BindingFlags.Public | BindingFlags.Static)
                .FirstOrDefault(method =>
                    method.Name == nameof(Task.FromException)
                    && !method.IsGenericMethodDefinition
                    && method.GetParameters().Length == 1
                    && method.GetParameters()[0].ParameterType == typeof(Exception))
                ?? throw new InvalidOperationException("Could not resolve Task.FromException(Exception)");
            _currentIL.Emit(OpCodes.Call, fromException);

            if (_currentAsyncReturnsValueTask)
            {
                // new ValueTask(Task)
                var ctor = typeof(ValueTask).GetConstructor(new[] { typeof(Task) })
                    ?? throw new InvalidOperationException("Could not resolve ValueTask(Task) constructor");
                _currentIL.Emit(OpCodes.Newobj, ctor);
            }

            return;
        }

        var fromExceptionGeneric = typeof(Task)
            .GetMethods(BindingFlags.Public | BindingFlags.Static)
            .FirstOrDefault(method =>
                method.Name == nameof(Task.FromException)
                && method.IsGenericMethodDefinition
                && method.GetParameters().Length == 1
                && method.GetParameters()[0].ParameterType == typeof(Exception))
            ?.MakeGenericMethod(_currentAsyncResultType)
            ?? throw new InvalidOperationException("Could not resolve Task.FromException<T>(Exception)");
        _currentIL.Emit(OpCodes.Call, fromExceptionGeneric);

        if (_currentAsyncReturnsValueTask)
        {
            // new ValueTask<T>(Task<T>)
            var taskOfT = typeof(Task<>).MakeGenericType(_currentAsyncResultType);
            var ctor = _currentAsyncReturnType.GetConstructor(new[] { taskOfT })
                ?? throw new InvalidOperationException($"Could not resolve {_currentAsyncReturnType}(Task<T>) constructor");
            _currentIL.Emit(OpCodes.Newobj, ctor);
        }
    }

    /// <summary>
    /// Resolves the async method builder type that an async method should opt into, given the
    /// project configuration. Returns <c>null</c> when no override applies (the runtime default
    /// builder is used).
    ///
    /// This is the selection point for pooled builders. It is wired and unit-tested, but
    /// <see cref="ApplyAsyncMethodBuilderAttribute"/> only emits the attribute once a real state
    /// machine exists — see the DEFERRED note on this type.
    /// </summary>
    private Type? ResolveAsyncMethodBuilderType(Type asyncReturnType)
    {
        if (_projectConfig?.Language?.PooledAsync != true)
        {
            return null;
        }

        // PoolingAsyncValueTaskMethodBuilder only applies to ValueTask-returning methods; Task is
        // reference-typed and reuses the standard builder.
        if (asyncReturnType == typeof(ValueTask))
        {
            return typeof(System.Runtime.CompilerServices.PoolingAsyncValueTaskMethodBuilder);
        }

        if (asyncReturnType.IsGenericType
            && asyncReturnType.GetGenericTypeDefinition() == typeof(ValueTask<>))
        {
            return typeof(System.Runtime.CompilerServices.PoolingAsyncValueTaskMethodBuilder<>)
                .MakeGenericType(asyncReturnType.GetGenericArguments()[0]);
        }

        return null;
    }

    /// <summary>
    /// Applies <c>[AsyncMethodBuilder(typeof(builder))]</c> to <paramref name="methodBuilder"/> when
    /// a pooled builder has been selected.
    ///
    /// DEFERRED: the attribute is inert without a real state machine for the runtime to drive, so it
    /// is intentionally NOT emitted today. The method exists as the single wiring point so the
    /// state-machine work can flip <see cref="EmitAsyncMethodBuilderAttribute"/> on without
    /// touching call sites.
    /// </summary>
    private void ApplyAsyncMethodBuilderAttribute(MethodBuilder methodBuilder, Type asyncReturnType)
    {
        if (!EmitAsyncMethodBuilderAttribute)
        {
            return;
        }

        var builderType = ResolveAsyncMethodBuilderType(asyncReturnType);
        if (builderType == null)
        {
            return;
        }

        var ctor = typeof(System.Runtime.CompilerServices.AsyncMethodBuilderAttribute)
            .GetConstructor(new[] { typeof(Type) })
            ?? throw new InvalidOperationException("Could not resolve AsyncMethodBuilderAttribute(Type) constructor");
        methodBuilder.SetCustomAttribute(new CustomAttributeBuilder(ctor, new object[] { builderType }));
    }

    /// <summary>
    /// Gates emission of the <c>[AsyncMethodBuilder]</c> attribute. Remains <c>false</c> until real
    /// async state machines land; emitting the attribute without a state machine for the runtime to
    /// drive has no effect and could mislead tooling. Modelled as a property (not a <c>const</c>) so
    /// the inert call site stays reachable to the compiler — flipping it on is a one-line change.
    /// </summary>
    private static bool EmitAsyncMethodBuilderAttribute => false;
}
