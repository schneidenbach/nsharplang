namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// The synthesized `__NSharpEntryPoint` wrapper an ASYNC `main` needs: the CLR entry point cannot be
// `async`, so the emitted program gets a synchronous static shim that calls the async main, blocks on
// its awaiter, and forwards (or discards) the result.
//
// THIS IS THE PLAN-ROW IR's FIRST NON-ITERATOR METHOD BODY, AND THAT IS THE POINT. Every earlier
// schema-v4 body is an iterator or async-iterator state-machine member, where a body local is a
// HOISTED FIELD on the closure class because it must survive a suspend — the specialisation that made
// "locals as IL locals" look like a missing mode. This body has no state machine and nothing to hoist
// onto: its awaiter is an ORDINARY IL LOCAL, declared by the plan through `DeclarePlanLocal` and
// materialised by the executor's `ILGenerator.DeclareLocal`, addressed through `PlanLocalOperand`
// rows. It is also STATIC and parameterless, so it needs no argument row at all — which is what makes
// it plannable at this tip, where the emitter's modeled `OpCodes` surface has no short-form `ldarg.0`
// and therefore cannot reproduce a `this`-bearing body byte-for-byte.
//
// The shape is total by construction: the wrapper is SYNTHESIZED rather than parsed, so there is no
// user syntax to decline and the planner claims the whole body or nothing. A parameterised async main
// is refused UPSTREAM (the emitter declines the assembly), so this planner never sees one.
class ColumnarAsyncEntryPointPlanner {

    // The wrapper's own return type. An async main whose inner result is an exit CODE forwards it;
    // everything else (including a `Task<string>`) becomes a void entry point and the value is popped.
    // The rule lives here rather than at the DefineMethod call so the signature and the body that has
    // to satisfy it cannot drift apart.
    static func WrapperReturnType(innerReturnType: Type): Type {
        if innerReturnType == typeof(int) || innerReturnType == typeof(uint) {
            return innerReturnType
        }
        return RequiredVoidType()
    }

    // `call main(); [call|callvirt] GetAwaiter(); stloc awaiter; ldloca awaiter; call GetResult();
    // [pop]; ret`.
    //
    // `entryPoint` is a MethodBuilder whose reflection surface cannot be read back, so it enters the
    // method pool through the DECLARED-SIGNATURE overload — the same treatment the member pools give
    // every other builder handle.
    static func BuildWrapperPlan(entryPoint: MethodInfo, entryPointDeclaringType: Type, wrappedReturnType: Type, innerReturnType: Type): ColumnarCodePlan {
        if entryPoint == null || entryPointDeclaringType == null || wrappedReturnType == null || innerReturnType == null {
            throw new InvalidOperationException("An async entry-point wrapper plan needs its entry point and both return types.")
        }
        getAwaiter := RequiredParameterlessMethod(wrappedReturnType, "GetAwaiter")
        awaiterType := getAwaiter.get_ReturnType()
        getResult := RequiredParameterlessMethod(awaiterType, "GetResult")
        wrapperReturnType := WrapperReturnType(innerReturnType)

        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        noParameters := new Type[](0)
        entryPointPool := plan.AddMethodWithSignature(entryPoint, entryPointDeclaringType, noParameters, wrappedReturnType, true, false)
        awaiterLocal := plan.DeclarePlanLocal(plan.AddType(awaiterType))

        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), entryPointPool)
        // A virtual GetAwaiter is dispatched virtually; Task/ValueTask expose it non-virtually and take
        // the direct call. The awaiter is then a value in a local so its address can be taken —
        // GetResult is an instance method on a value-typed awaiter and needs a managed pointer.
        plan.AppendMethodInstruction(AwaiterCallOpCode(getAwaiter), plan.AddMethod(getAwaiter))
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), awaiterLocal)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), awaiterLocal)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(getResult))
        if ColumnarCodePlanExecutor.IsVoidType(wrapperReturnType) && !ColumnarCodePlanExecutor.IsVoidType(innerReturnType) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
        }
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(wrapperReturnType)
        return plan
    }

    static func AwaiterCallOpCode(getAwaiter: MethodInfo): short {
        if getAwaiter.get_IsVirtual() {
            return ColumnarCodePlanContract.Callvirt()
        }
        return ColumnarCodePlanContract.Call()
    }

    static func RequiredParameterlessMethod(owner: Type, name: string): MethodInfo {
        noParameters := new Type[](0)
        method := owner.GetMethod(name, noParameters)
        if method == null {
            throw new InvalidOperationException("The awaited entry-point type '" + owner.get_FullName() + "' exposes no parameterless " + name + "().")
        }
        return method
    }

    // N# has no `typeof(void)`; the void marker is resolved through the runtime type system, the same
    // idiom the iterator and construction planners use.
    static func RequiredVoidType(): Type {
        voidType := Type.GetType("System.Void")
        if voidType == null {
            throw new InvalidOperationException("System.Void was not found.")
        }
        return voidType
    }
}
