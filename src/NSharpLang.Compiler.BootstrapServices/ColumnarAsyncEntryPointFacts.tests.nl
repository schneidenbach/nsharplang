namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import System.Threading.Tasks


// `015-B1` gives the plan-row IR's LOCALS-AS-LOCALS binding mode its first NON-ITERATOR method-body
// consumer: the synthesized `__NSharpEntryPoint` wrapper an async `main` needs.
//
// The reopening decode named "the IR binds locals as hoisted fields" as the blocker on generalising
// the body planner. Measured at the tip, that is not what the IR does — `ColumnarCodePlan` has THREE
// binding classes (`FieldOperand`, `PlanLocalOperand`, `AmbientLocalOperand`), the executor already
// calls `ILGenerator.DeclareLocal` for every plan local, and the stack validator already carries a
// definite-assignment bitset for them. What was specialised to the iterator was the PLANNER: every
// schema-v4 body in the estate was a state-machine member, where a body local MUST be a hoisted field
// because it has to survive a suspend.
//
// This wrapper is the counter-example that turns the mode from a capability into a shipped route: an
// ordinary static method body, no state machine, no closure class, and an awaiter that is an ORDINARY
// IL LOCAL. The blocks below pin exactly that — that the plan binds through `PlanLocalOperand` and
// touches no field row at all — plus the `pop` row the method-body schema gains here, because a body
// is a statement sequence and can produce a value nothing consumes.
//
// A PIN SWEEP over the estate before the cut found ZERO blocks naming `__NSharpEntryPoint`,
// `ColumnarAsyncEntryPointPlanner` or the wrapper's return-type rule, and ZERO naming
// `ColumnarCodePlanContract.Pop`. The wrapper's shape was reachable only through two example
// programs' emitted IL.

// A static parameterless method returning `Task` — the exact handle shape an async `main` with no
// result presents to the wrapper. `Task.get_CompletedTask` is used rather than a fixture because the
// plan validates a declared signature against its handle, and this one is genuinely inspectable.
func AsyncEntryPointCompletedTaskHandle(): MethodInfo {
    property := typeof(Task).GetProperty("CompletedTask")
    if property == null {
        throw new InvalidOperationException("Task.CompletedTask was not found.")
    }
    getter := property.GetGetMethod()
    if getter == null {
        throw new InvalidOperationException("Task.CompletedTask has no getter.")
    }
    return getter
}

func AsyncEntryPointVoidType(): Type {
    result := Type.GetType("System.Void")
    if result == null {
        throw new InvalidOperationException("System.Void was not found.")
    }
    return result
}

func AsyncEntryPointNoTypes(): Type[] {
    return new Type[](0)
}

// The wrapper plan for a `Task`-returning async main: the whole void case, end to end.
func AsyncEntryPointVoidWrapperPlan(): ColumnarCodePlan {
    handle := AsyncEntryPointCompletedTaskHandle()
    return ColumnarAsyncEntryPointPlanner.BuildWrapperPlan(handle, typeof(Task), typeof(Task), AsyncEntryPointVoidType())
}

func AsyncEntryPointCountOperandKind(plan: ColumnarCodePlan, operandKind: int): int {
    total := 0
    i := 0
    while i < plan.OperationCount {
        if plan.OperandKinds[i] == operandKind {
            total = total + 1
        }
        i = i + 1
    }
    return total
}

func AsyncEntryPointCountOpCode(plan: ColumnarCodePlan, opCodeValue: short): int {
    total := 0
    i := 0
    while i < plan.OperationCount {
        if plan.OpCodeValues[i] == opCodeValue {
            total = total + 1
        }
        i = i + 1
    }
    return total
}

// A parameterless void DynamicMethod is the only fixture that can RUN a wrapper body: it is static
// and takes no arguments, which is exactly the wrapper's own shape.
func AsyncEntryPointVoidDynamicMethod(name: string): DynamicMethod {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := typeof(DynamicMethod).GetConstructor(constructorTypes)
    if constructorInfo == null {
        throw new InvalidOperationException("Required DynamicMethod constructor was not found.")
    }
    constructorArguments := new object[](3)
    AsyncEntryPointSetObject(constructorArguments, 0, name)
    AsyncEntryPointSetObject(constructorArguments, 1, AsyncEntryPointVoidType())
    AsyncEntryPointSetObject(constructorArguments, 2, AsyncEntryPointNoTypes())
    return (DynamicMethod)constructorInfo.Invoke(constructorArguments)
}

func AsyncEntryPointSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

// THE BINDING MODE. This is the block the slice exists for: the awaiter slot is an IL LOCAL the plan
// declares, not a field on a closure class, and the plan proves it by carrying no field row at all.
test "the async entry-point wrapper binds its awaiter as an IL local, not a hoisted field" {
    plan := AsyncEntryPointVoidWrapperPlan()

    // The mode: exactly one plan local, of the awaiter's own type, and it is the plan's local — not a
    // LocalBuilder handed in from outside (that is the AMBIENT class, a third binding).
    assert plan.PlanLocalCount == 1
    assert plan.AmbientLocalCount == 0
    awaiterType := plan.Types[plan.PlanLocalTypeIndices[0]]
    assert awaiterType.get_FullName() == "System.Runtime.CompilerServices.TaskAwaiter"

    // The negative half, and the one that says "not the iterator heritage": a state-machine body binds
    // every body slot through `Stfld`/`Ldfld` on the closure class. This body has NO field pool and no
    // field row, and no argument row either — it is static and parameterless.
    assert plan.FieldCount == 0
    assert plan.ArgumentCount == 0
    assert AsyncEntryPointCountOperandKind(plan, ColumnarCodePlanContract.FieldOperand()) == 0

    // Two rows address the local, and both are PLAN-local rows: the store of the awaiter and the
    // address load `GetResult` needs, because an awaiter is a value type and its instance call takes a
    // managed pointer.
    assert AsyncEntryPointCountOperandKind(plan, ColumnarCodePlanContract.PlanLocalOperand()) == 2
    assert AsyncEntryPointCountOpCode(plan, ColumnarCodePlanContract.Stloc()) == 1
    assert AsyncEntryPointCountOpCode(plan, ColumnarCodePlanContract.Ldloca()) == 1
    assert AsyncEntryPointCountOpCode(plan, ColumnarCodePlanContract.Ldloc()) == 0

    // And it is a METHOD BODY, not an expression fragment: the schema is v4 and the body terminates.
    assert plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    assert AsyncEntryPointCountOpCode(plan, ColumnarCodePlanContract.Ret()) == 1
}

// The wrapper's SIGNATURE rule. The CLR entry point may return void, int or uint; an async main whose
// result is any other value has that value discarded. The rule lives on the planner so the
// DefineMethod signature and the body that must satisfy it cannot drift apart.
test "the async entry-point wrapper forwards only an exit code and voids everything else" {
    assert ColumnarAsyncEntryPointPlanner.WrapperReturnType(typeof(int)) == typeof(int)
    assert ColumnarAsyncEntryPointPlanner.WrapperReturnType(typeof(uint)) == typeof(uint)

    voidType := AsyncEntryPointVoidType()
    assert ColumnarAsyncEntryPointPlanner.WrapperReturnType(voidType) == voidType
    assert ColumnarAsyncEntryPointPlanner.WrapperReturnType(typeof(string)) == voidType
    assert ColumnarAsyncEntryPointPlanner.WrapperReturnType(typeof(bool)) == voidType
    assert ColumnarAsyncEntryPointPlanner.WrapperReturnType(typeof(long)) == voidType

    // A void inner result is void either way, and the wrapper then has nothing to discard.
    voidPlan := AsyncEntryPointVoidWrapperPlan()
    assert voidPlan.ResultType == voidType
    assert AsyncEntryPointCountOpCode(voidPlan, ColumnarCodePlanContract.Pop()) == 0
}

// `pop` is the row the method-body schema gains in this slice, and it is gained because a BODY is a
// statement sequence: a call whose value nothing consumes has to be balanced explicitly, where an
// expression fragment always has a consumer for its one result.
test "the method-body schema owns pop and the expression fragments refuse it" {
    // The fragment schemas do not admit the row at all — the appender refuses it before any validator
    // sees it, exactly as it refuses `leave`, `isinst` and `stsfld`.
    fragment := new ColumnarCodePlan()
    fragment.PrepareV3()
    assert throws InvalidOperationException {
        fragment.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
    }

    // In a method body it is accepted, and its stack effect is exactly pop-one-push-nothing: a body
    // that pushes a value, discards it and returns void validates.
    balanced := new ColumnarCodePlan()
    balanced.PrepareMethodBody()
    balanced.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    balanced.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
    balanced.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    balanced.CompleteMethodBody(AsyncEntryPointVoidType())
    ColumnarCodePlanExecutor.Validate(balanced)

    // Without the discard the same body reaches `ret` one value deep in a void method, and the height
    // model says so. This is what makes the row's delta non-vacuous rather than merely present.
    unbalanced := new ColumnarCodePlan()
    unbalanced.PrepareMethodBody()
    unbalanced.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    unbalanced.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    unbalanced.CompleteMethodBody(AsyncEntryPointVoidType())
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(unbalanced)
    }
}

// The end-to-end proof: the planned body is not merely well-formed, it EXECUTES. The wrapper's own
// shape — static, parameterless, void — is reproducible in a DynamicMethod, so the plan can be
// replayed into one and invoked. Running it blocks on a completed task and returns, which is the
// whole semantic the wrapper exists to provide.
test "the async entry-point wrapper body executes as a real method" {
    plan := AsyncEntryPointVoidWrapperPlan()
    method := AsyncEntryPointVoidDynamicMethod("NSharpB1EntryPointWrapper")
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())

    target: object? = null
    result := method.Invoke(target, AsyncEntryPointNoArguments())
    assert result == null

    // A method-body plan is single-use: replay after execution is refused, so a failed emit can never
    // leave a half-written body replayable.
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Execute(plan, AsyncEntryPointVoidDynamicMethod("NSharpB1Replay").GetILGenerator())
    }
}

func AsyncEntryPointNoArguments(): object[] {
    return new object[](0)
}

// The planner refuses what it cannot plan rather than emitting a body that would not verify.
test "the async entry-point planner refuses an awaitable it cannot drive" {
    handle := AsyncEntryPointCompletedTaskHandle()
    voidType := AsyncEntryPointVoidType()

    // `int` has no GetAwaiter, so there is no awaiter type and no local to bind.
    assert throws InvalidOperationException {
        ColumnarAsyncEntryPointPlanner.BuildWrapperPlan(handle, typeof(Task), typeof(int), voidType)
    }

    // A declared signature is not TRUSTED because the planner wrote it: the plan carries the entry
    // point through the declared-signature pool because a MethodBuilder exposes no readable one, and
    // the validator still checks the declaration against whatever the handle does expose. Declaring
    // this handle against the wrong owner builds a plan and then fails validation — which is where the
    // check belongs, since the emitter reaches the executor through `Execute`, and `Execute` validates.
    mismatched := ColumnarAsyncEntryPointPlanner.BuildWrapperPlan(handle, typeof(string), typeof(Task), voidType)
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(mismatched)
    }

    // The well-formed plan validates, so the block above is about the mismatch and not about the shape.
    ColumnarCodePlanExecutor.Validate(AsyncEntryPointVoidWrapperPlan())
}
