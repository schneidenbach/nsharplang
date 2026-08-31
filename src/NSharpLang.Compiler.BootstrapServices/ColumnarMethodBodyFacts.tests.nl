namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Globalization


// `015-B3` — STATEMENT KIND 20 (`Return`) AS AN ORDINARY USER BODY SEES IT.
//
// THE SLICE'S DECODE OVERTURNED ITS OWN MANDATE AND THESE BLOCKS ARE WHERE THAT IS PINNED. The brief
// asked for a `Return` ROW, an executor arm and a height-model entry to be BUILT. All four already
// existed: `ColumnarCodePlanContract.Ret()` is 42, the executor emits it, the appender admits it under
// the method-body schema alone, and `ValidateMethodBodyStack` carries a written `ret` arm with two
// throws. Eighteen production sites already append it.
//
// THE PIN SWEEP BEHIND THIS FILE WAS WRONG ONCE, AND THE CORRECTION IS PART OF THE RECORD. It scanned
// every `.tests.nl` for the three `ret` height DIAGNOSTIC STRINGS ("wrong stack height", "fall through
// its final", "cannot appear inside a protected") and found zero — but the estate asserts on the
// exception TYPE and never quotes a validator message, so that sweep could not have found anything.
// `ColumnarCodePlanExecutor.tests.nl` already pins FOUR `ret` behaviours: a void body's `ret` executes
// (:3426), a value body's does (:3435), a body that falls off its end is refused (:3684), and a `ret`
// inside a protected region is refused (:3694).
//
// What was genuinely unpinned, and is closed here, is three things: the row's VALUE and its three
// predicate memberships, the fact that v3 AND v2 refuse the row at the APPENDER, and a VALUE result
// reached at an EMPTY stack. The blocks that overlap the four above are kept rather than trimmed,
// because the three-block ISOLATION is what lets a mutation to the row constant break the row block
// alone while a mutation to the executor arm breaks broadly — and because the protected-region block
// gains the POSITIVE counterpart nothing had: the same body with a `leave` in the `ret`'s place
// validates, which is what makes the refusal about the REGION and not about the shape.
//
// The two things this slice actually BUILT are the last three blocks: the columnar termination rule
// (kind 20's reachability half, moved out of the C# emitter whole) and the first ordinary-user-body
// DRIVER, plus the shared-owner widening that lets one literal owner serve a method body.

// ---- shared fixtures ----

func MethodBodyFactsVoidType(): Type {
    result := Type.GetType("System.Void")
    if result == null {
        throw new InvalidOperationException("System.Void was not found.")
    }
    return result
}

func MethodBodyFactsRequiredConstructor(owner: Type, parameterTypes: Type[]): ConstructorInfo {
    constructorInfo := owner.GetConstructor(parameterTypes)
    if constructorInfo == null {
        throw new InvalidOperationException("Required constructor was not found.")
    }
    return constructorInfo
}

func MethodBodyFactsSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// `new DynamicMethod(...)` is not on the modeled emit surface, so the estate reaches it the same way
// every other plan-replay block does: through its constructor handle.
func MethodBodyFactsDynamicMethod(name: string, returnType: Type): DynamicMethod {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := MethodBodyFactsRequiredConstructor(typeof(DynamicMethod), constructorTypes)
    constructorArguments := new object?[](3)
    MethodBodyFactsSetObject(constructorArguments, 0, name)
    MethodBodyFactsSetObject(constructorArguments, 1, returnType)
    MethodBodyFactsSetObject(constructorArguments, 2, new Type[](0))
    return (DynamicMethod)constructorInfo.Invoke(constructorArguments)
}

func MethodBodyFactsNoArguments(): object[] {
    return new object[](0)
}

// ---- a node table, built by hand ----
//
// `kinds` and `childCounts` are in node order; `children` is the concatenation of each node's child
// list in that same order, which is exactly the layout `ColumnarNodeTable.Child` reads. Value spans
// matter only for the literal nodes — `AlwaysReturns` never reads text.

func MethodBodyFactsNodes(kinds: int[], childCounts: int[], children: int[], valueStarts: int[], valueLengths: int[], sourceLength: int): ColumnarNodeTable {
    count := kinds.Length
    childStarts := new int[](count)
    spanStarts := new int[](count)
    spanLengths := new int[](count)
    start := 0
    i := 0
    while i < count {
        childStarts[i] = start
        start = start + childCounts[i]
        spanStarts[i] = 0
        spanLengths[i] = sourceLength
        i = i + 1
    }
    return new ColumnarNodeTable(kinds, valueStarts, valueLengths, childStarts, childCounts, children, spanStarts, spanLengths)
}

func MethodBodyFactsInts1(a: int): int[] {
    values := new int[](1)
    values[0] = a
    return values
}

func MethodBodyFactsInts2(a: int, b: int): int[] {
    values := new int[](2)
    values[0] = a
    values[1] = b
    return values
}

func MethodBodyFactsInts3(a: int, b: int, c: int): int[] {
    values := new int[](3)
    values[0] = a
    values[1] = b
    values[2] = c
    return values
}

func MethodBodyFactsInts4(a: int, b: int, c: int, d: int): int[] {
    values := new int[](4)
    values[0] = a
    values[1] = b
    values[2] = c
    values[3] = d
    return values
}

func MethodBodyFactsInts5(a: int, b: int, c: int, d: int, e: int): int[] {
    values := new int[](5)
    values[0] = a
    values[1] = b
    values[2] = c
    values[3] = d
    values[4] = e
    return values
}

func MethodBodyFactsInts6(a: int, b: int, c: int, d: int, e: int, f: int): int[] {
    values := new int[](6)
    values[0] = a
    values[1] = b
    values[2] = c
    values[3] = d
    values[4] = e
    values[5] = f
    return values
}

// A one-node statement tree of the given kind and child count, with no grandchildren — enough for the
// leaf arms of the termination rule.
func MethodBodyFactsLeaf(kind: int, childCount: int): ColumnarNodeTable {
    total := childCount + 1
    kinds := new int[](total)
    childCounts := new int[](total)
    valueStarts := new int[](total)
    valueLengths := new int[](total)
    children := new int[](childCount)
    kinds[0] = kind
    childCounts[0] = childCount
    i := 0
    while i < childCount {
        kinds[i + 1] = 23
        childCounts[i + 1] = 0
        children[i] = i + 1
        i = i + 1
    }
    return MethodBodyFactsNodes(kinds, childCounts, children, valueStarts, valueLengths, 1)
}

// `{ return <literal> }` — a block (25) whose one statement is a return (20) of one literal.
func MethodBodyFactsLiteralBody(literalKind: int, text: string): ColumnarNodeTable {
    kinds := MethodBodyFactsInts3(25, 20, literalKind)
    childCounts := MethodBodyFactsInts3(1, 1, 0)
    children := MethodBodyFactsInts2(1, 2)
    valueStarts := MethodBodyFactsInts3(0, 0, 0)
    valueLengths := MethodBodyFactsInts3(0, 0, text.Length)
    return MethodBodyFactsNodes(kinds, childCounts, children, valueStarts, valueLengths, text.Length)
}

// `{ }` — a block with no statements at all.
func MethodBodyFactsEmptyBody(): ColumnarNodeTable {
    kinds := MethodBodyFactsInts1(25)
    childCounts := MethodBodyFactsInts1(0)
    return MethodBodyFactsNodes(kinds, childCounts, new int[](0), childCounts, childCounts, 1)
}

// `{ return }` — a block whose one statement is a VALUE-LESS return.
func MethodBodyFactsBareReturnBody(): ColumnarNodeTable {
    kinds := MethodBodyFactsInts2(25, 20)
    childCounts := MethodBodyFactsInts2(1, 0)
    zeros := MethodBodyFactsInts2(0, 0)
    return MethodBodyFactsNodes(kinds, childCounts, MethodBodyFactsInts1(1), zeros, zeros, 1)
}

func MethodBodyFactsNoOrdinals(): Dictionary<string, int> {
    return new Dictionary<string, int>(StringComparer.Ordinal)
}

func MethodBodyFactsNoTypes(): Dictionary<string, Type> {
    return new Dictionary<string, Type>(StringComparer.Ordinal)
}

func MethodBodyFactsOrdinals(name: string, ordinal: int): Dictionary<string, int> {
    result := MethodBodyFactsNoOrdinals()
    result[name] = ordinal
    return result
}

func MethodBodyFactsTypes(name: string, valueType: Type): Dictionary<string, Type> {
    result := MethodBodyFactsNoTypes()
    result[name] = valueType
    return result
}

func MethodBodyFactsLocals(): Dictionary<string, LocalBuilder> {
    return new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
}

// The ONE driver entry point, with the binding facts the emitter routes. A claim class that needs no
// bindings passes empty maps, which is exactly what a static free function's body has.
func MethodBodyFactsPlanBody(nodes: ColumnarNodeTable, source: string, returnType: Type, isVoid: bool, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, plan: ColumnarCodePlan): bool {
    return ColumnarMethodBodyPlanner.TryPlanBody(
        nodes,
        source,
        0,
        returnType,
        isVoid,
        parameterOrdinals,
        parameterTypes,
        locals,
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal),
        null,
        null,
        null,
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        new string[](0),
        new string[](0),
        new string[](0),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        plan)
}

func MethodBodyFactsPlanLiteralBody(literalKind: int, text: string, returnType: Type, plan: ColumnarCodePlan): bool {
    nodes := MethodBodyFactsLiteralBody(literalKind, text)
    return MethodBodyFactsPlanBody(nodes, text, returnType, false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), plan)
}

// `{ return <name> }` planned against ONE parameter binding.
func MethodBodyFactsPlanParameterBody(name: string, ordinal: int, parameterType: Type, returnType: Type, plan: ColumnarCodePlan): bool {
    nodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    return MethodBodyFactsPlanBody(nodes, name, returnType, false, MethodBodyFactsOrdinals(name, ordinal), MethodBodyFactsTypes(name, parameterType), MethodBodyFactsLocals(), plan)
}

func MethodBodyFactsNullableOf(valueType: Type): Type {
    candidate := Type.GetType("System.Nullable`1")
    if candidate == null {
        throw new InvalidOperationException("System.Nullable`1 was not found.")
    }
    definition: Type = candidate
    arguments := new Type[](1)
    arguments[0] = valueType
    return definition.MakeGenericType(arguments)
}

func MethodBodyFactsDynamicMethodWith(name: string, returnType: Type, parameterTypes: Type[]): DynamicMethod {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    constructorInfo := MethodBodyFactsRequiredConstructor(typeof(DynamicMethod), constructorTypes)
    constructorArguments := new object?[](3)
    MethodBodyFactsSetObject(constructorArguments, 0, name)
    MethodBodyFactsSetObject(constructorArguments, 1, returnType)
    MethodBodyFactsSetObject(constructorArguments, 2, parameterTypes)
    return (DynamicMethod)constructorInfo.Invoke(constructorArguments)
}

func MethodBodyFactsIntTypes(count: int): Type[] {
    result := new Type[](count)
    i := 0
    while i < count {
        result[i] = typeof(int)
        i = i + 1
    }
    return result
}

func MethodBodyFactsSetArgument(values: object[], index: int, value: object) {
    values[index] = value
}

func MethodBodyFactsIntArguments(count: int, lastValue: int): object[] {
    result := new object[](count)
    i := 0
    while i < count {
        MethodBodyFactsSetArgument(result, i, i)
        i = i + 1
    }
    if count > 0 {
        MethodBodyFactsSetArgument(result, count - 1, lastValue)
    }
    return result
}


// ---- BLOCK 1 — THE ROW ----
//
// 0x2A = 42, and the row belongs to the method-body schema ALONE. The asymmetry is the whole content:
// an expression fragment refuses `ret` at the APPENDER, before any validator sees it, because a
// fragment computes a value for an enclosing consumer and has no method to leave.
test "the ret row is 42 and only a method body may carry it" {
    assert ColumnarCodePlanContract.Ret() == 42

    // It is a method-body no-operand opcode, and it is NOT one of the two families every schema
    // admits. Those three predicates are how the appender decides, so all three are asked.
    assert ColumnarCodePlanContract.IsMethodBodyNoOperandOpcode(ColumnarCodePlanContract.Ret())
    assert !ColumnarCodePlanContract.IsNoOperandOpcode(ColumnarCodePlanContract.Ret())
    assert !ColumnarCodePlanContract.IsScalarNoOperandOpcode(ColumnarCodePlanContract.Ret())

    // v3 — a scalar expression fragment — refuses it.
    fragment := new ColumnarCodePlan()
    fragment.PrepareV3()
    assert throws InvalidOperationException {
        fragment.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    }

    // v2 — the recursive fragment schema — refuses it too, and for the same reason.
    recursive := new ColumnarCodePlan()
    recursive.PrepareV2()
    assert throws InvalidOperationException {
        recursive.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    }

    // v4 accepts it.
    body := new ColumnarCodePlan()
    body.PrepareMethodBody()
    body.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    body.CompleteMethodBody(MethodBodyFactsVoidType())
    ColumnarCodePlanExecutor.Validate(body)
}


// ---- BLOCK 2 — THE EXECUTOR ARM ----
//
// The row becomes a real `ret` at BOTH arities. A void body returns and does not fault; a value body
// hands back the value that was on the stack, so a missing or misplaced `ret` cannot pass silently.
test "the executor's ret arm ends a real method body at both arities" {
    voidPlan := new ColumnarCodePlan()
    voidPlan.PrepareMethodBody()
    voidPlan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    voidPlan.CompleteMethodBody(MethodBodyFactsVoidType())
    voidMethod := MethodBodyFactsDynamicMethod("NSharpB3VoidRet", MethodBodyFactsVoidType())
    ColumnarCodePlanExecutor.Execute(voidPlan, voidMethod.GetILGenerator())
    voidTarget: object? = null
    assert voidMethod.Invoke(voidTarget, MethodBodyFactsNoArguments()) == null

    valuePlan := new ColumnarCodePlan()
    valuePlan.PrepareMethodBody()
    valueIndex := valuePlan.AddInt32(4242)
    valuePlan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), valueIndex)
    valuePlan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    valuePlan.CompleteMethodBody(typeof(int))
    valueMethod := MethodBodyFactsDynamicMethod("NSharpB3ValueRet", typeof(int))
    ColumnarCodePlanExecutor.Execute(valuePlan, valueMethod.GetILGenerator())
    valueTarget: object? = null
    assert Convert.ToInt32(valueMethod.Invoke(valueTarget, MethodBodyFactsNoArguments())) == 4242
}


// ---- BLOCK 3 — THE HEIGHT MODEL ----
//
// The `ret` arm in `ValidateMethodBodyStack` makes three separate demands, and each one is asked here
// on its own so a mutation to one cannot be absorbed by another. (The fourth — a VOID `ret` reached
// one value deep — is already pinned incidentally by `015-B1`'s `pop` block; it is named here rather
// than duplicated.)
test "the height model refuses every ret that does not balance its declared result" {
    // 1. A VALUE result reached at an EMPTY stack. `ret` needs exactly one value; a bare `ret` in an
    //    `int` method is invalid IL that would fault the JIT, and the model stops it first.
    starved := new ColumnarCodePlan()
    starved.PrepareMethodBody()
    starved.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    starved.CompleteMethodBody(typeof(int))
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(starved)
    }

    // 2. A body that FALLS OFF its final instruction — every path must end in ret/throw/leave. This is
    //    the check that makes the driver's trailing `ret` load-bearing rather than decorative.
    unterminated := new ColumnarCodePlan()
    unterminated.PrepareMethodBody()
    unterminatedIndex := unterminated.AddInt32(7)
    unterminated.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), unterminatedIndex)
    unterminated.CompleteMethodBody(MethodBodyFactsVoidType())
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(unterminated)
    }

    // 3. A `ret` INSIDE a protected region. CIL forbids it — the exit is a `leave` — and this is the
    //    rule the emitter's own kind-20 arm mirrors in C# when it stores and leaves instead.
    inRegion := new ColumnarCodePlan()
    inRegion.PrepareMethodBody()
    regionEnd := inRegion.DefineLabel()
    inRegion.AppendBeginExceptionBlock(regionEnd)
    inRegion.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    inRegion.AppendBeginFinallyBlock()
    inRegion.AppendEndExceptionBlock()
    inRegion.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    inRegion.CompleteMethodBody(MethodBodyFactsVoidType())
    assert throws InvalidOperationException {
        ColumnarCodePlanExecutor.Validate(inRegion)
    }

    // And the same body with a `leave` where the `ret` was validates, which is what proves the refusal
    // above is about the REGION and not about the shape.
    leaving := new ColumnarCodePlan()
    leaving.PrepareMethodBody()
    leavingEnd := leaving.DefineLabel()
    leaving.AppendBeginExceptionBlock(leavingEnd)
    leaving.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), leavingEnd)
    leaving.AppendBeginFinallyBlock()
    leaving.AppendEndExceptionBlock()
    leaving.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    leaving.CompleteMethodBody(MethodBodyFactsVoidType())
    ColumnarCodePlanExecutor.Validate(leaving)
}


// ---- BLOCK 4 — THE TERMINATION RULE ----
//
// Kind 20's reachability half, moved out of `ColumnarIlEmitter.cs` whole. Every arm the rule
// distinguishes is asked in BOTH directions, because a rule that only ever answers `true` would pass a
// one-sided sweep and then silently drop a trailing `ret` from a body that needed one.
test "the columnar termination rule answers both ways at every statement kind it distinguishes" {
    // 20 Return and 48 Throw exit unconditionally; 23 (an expression statement) never does.
    assert ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsLeaf(20, 0), 0)
    assert ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsLeaf(48, 1), 0)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsLeaf(23, 0), 0)

    // 72 Yield: `yield break` (no children) terminates; `yield <value>` continues.
    assert ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsLeaf(72, 0), 0)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsLeaf(72, 1), 0)

    // 25 Block: ANY statement returning is enough — including one that is not the last, because the
    // rest is then unreachable. An empty block does not.
    blockKinds := MethodBodyFactsInts3(25, 20, 23)
    blockCounts := MethodBodyFactsInts3(2, 0, 0)
    blockChildren := MethodBodyFactsInts2(1, 2)
    zeros := MethodBodyFactsInts3(0, 0, 0)
    assert ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(blockKinds, blockCounts, blockChildren, zeros, zeros, 1), 0)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsLeaf(25, 0), 0)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsLeaf(25, 2), 0)

    // 27 If: only an if WITH an else, both of whose branches return. A two-child if (no else) never
    // does, whatever its then-branch says.
    ifKinds := MethodBodyFactsInts4(27, 23, 20, 20)
    ifCounts := MethodBodyFactsInts4(3, 0, 0, 0)
    ifChildren := MethodBodyFactsInts3(1, 2, 3)
    ifZeros := MethodBodyFactsInts4(0, 0, 0, 0)
    assert ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(ifKinds, ifCounts, ifChildren, ifZeros, ifZeros, 1), 0)

    elseKinds := MethodBodyFactsInts4(27, 23, 20, 23)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(elseKinds, ifCounts, ifChildren, ifZeros, ifZeros, 1), 0)

    noElseKinds := MethodBodyFactsInts3(27, 23, 20)
    noElseCounts := MethodBodyFactsInts3(2, 0, 0)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(noElseKinds, noElseCounts, blockChildren, zeros, zeros, 1), 0)

    // 51 Lock exits iff its BODY (child 1, not child 0) exits.
    lockKinds := MethodBodyFactsInts3(51, 23, 20)
    assert ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(lockKinds, noElseCounts, blockChildren, zeros, zeros, 1), 0)
    lockFallsKinds := MethodBodyFactsInts3(51, 20, 23)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(lockFallsKinds, noElseCounts, blockChildren, zeros, zeros, 1), 0)
}

// 49 Try is the arm with the analyzer's asymmetric rule, so it gets its own block: the try block must
// exit, there must be at least ONE catch, EVERY catch must exit, and a FINALLY is ignored entirely.
// The zero-catch case is the one that surprises, and it is the one a mutation is most likely to get
// backwards.
test "the try arm of the termination rule demands a catch and ignores the finally" {
    // [try, catch] where both exit — the only shape that exits.
    tryKinds := MethodBodyFactsInts4(49, 20, 50, 20)
    tryCounts := MethodBodyFactsInts4(2, 0, 1, 0)
    tryChildren := MethodBodyFactsInts3(1, 2, 3)
    tryZeros := MethodBodyFactsInts4(0, 0, 0, 0)
    assert ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(tryKinds, tryCounts, tryChildren, tryZeros, tryZeros, 1), 0)

    // The TRY block itself falls through.
    tryFallsKinds := MethodBodyFactsInts4(49, 23, 50, 20)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(tryFallsKinds, tryCounts, tryChildren, tryZeros, tryZeros, 1), 0)

    // The CATCH falls through.
    catchFallsKinds := MethodBodyFactsInts4(49, 20, 50, 23)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(catchFallsKinds, tryCounts, tryChildren, tryZeros, tryZeros, 1), 0)

    // ZERO catches: `try { return } finally { return }`. The finally arrives as a trailing kind-25
    // child and the rule IGNORES it, so this does NOT always-return — probe-pinned behaviour the
    // pipeline depends on (it demands a trailing return, NL305).
    finallyKinds := MethodBodyFactsInts4(49, 20, 25, 20)
    finallyCounts := MethodBodyFactsInts4(2, 0, 1, 0)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(finallyKinds, finallyCounts, tryChildren, tryZeros, tryZeros, 1), 0)

    // TWO catches, the SECOND of which falls through — every clause has to exit, not just the first.
    // A rule that stopped at the first catch it saw would answer `true` here.
    twoKinds := MethodBodyFactsInts6(49, 20, 50, 50, 20, 23)
    twoCounts := MethodBodyFactsInts6(3, 0, 1, 1, 0, 0)
    twoChildren := MethodBodyFactsInts5(1, 2, 3, 4, 5)
    twoZeros := MethodBodyFactsInts6(0, 0, 0, 0, 0, 0)
    assert !ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(twoKinds, twoCounts, twoChildren, twoZeros, twoZeros, 1), 0)

    // The same two-catch shape with BOTH clauses exiting does return — so the refusal above is about
    // the falling clause and not about the arity.
    bothKinds := MethodBodyFactsInts6(49, 20, 50, 50, 20, 20)
    assert ColumnarMethodBodyPlanner.AlwaysReturns(MethodBodyFactsNodes(bothKinds, twoCounts, twoChildren, twoZeros, twoZeros, 1), 0)
}


// ---- BLOCK 5 — THE DRIVER ----
//
// The first ordinary USER body the plan path claims end to end. Every earlier schema-v4 producer was
// synthesized; this one arrives from parsed syntax, which is why its DECLINES matter as much as its
// claims — a body it takes wrongly is a body whose bytes it cannot promise.
test "the body driver claims a literal return and executes it" {
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanLiteralBody(0, "42", typeof(int), plan)

    // Exactly two rows: the literal and the `ret`. Nothing else belongs in the smallest user body
    // there is.
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()
    assert plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()

    method := MethodBodyFactsDynamicMethod("NSharpB3LiteralBody", typeof(int))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsNoArguments())) == 42

    // A string body takes the same route through the same literal owner.
    stringPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanLiteralBody(3, "\"hi\"", typeof(string), stringPlan)
    stringMethod := MethodBodyFactsDynamicMethod("NSharpB3StringBody", typeof(string))
    ColumnarCodePlanExecutor.Execute(stringPlan, stringMethod.GetILGenerator())
    stringTarget: object? = null
    assert Convert.ToString(stringMethod.Invoke(stringTarget, MethodBodyFactsNoArguments()), CultureInfo.InvariantCulture) == "hi"
}

// THE CLAIM RULE IS TYPE EQUALITY, AND THAT IS A DECISION RATHER THAN A LIMITATION. The host's kind-20
// arm runs seven target-typed pre-passes before the expression and seven coercions after it; equality
// is what makes all fourteen provably unreached, so a body the driver takes cannot diverge from the
// bytes the host would have written.
test "the body driver declines every shape whose bytes it cannot promise" {
    // Right literal, WRONG declared type: an unsuffixed integer literal is natural-`int`, and the
    // host's int-literal ADOPTION pre-pass would emit `ldc.i8` for a `long` function. Declining is
    // what keeps the two paths from disagreeing.
    assert !MethodBodyFactsPlanLiteralBody(0, "42", typeof(long), new ColumnarCodePlan())
    assert !MethodBodyFactsPlanLiteralBody(0, "42", typeof(short), new ColumnarCodePlan())

    // A SUFFIXED literal is natural-`long`, so it is claimed for a `long` function and refused for an
    // `int` one. The same rule, read from the other side.
    assert MethodBodyFactsPlanLiteralBody(0, "42L", typeof(long), new ColumnarCodePlan())
    assert !MethodBodyFactsPlanLiteralBody(0, "42L", typeof(int), new ColumnarCodePlan())

    // A value that is not an owned literal at all — kind 6 is an identifier read, and with NO binding
    // facts there is nothing for it to resolve to.
    assert !MethodBodyFactsPlanLiteralBody(6, "n", typeof(int), new ColumnarCodePlan())

    // A body whose block holds more than the one return.
    twoStatementKinds := MethodBodyFactsInts4(25, 23, 20, 0)
    twoStatementCounts := MethodBodyFactsInts4(2, 0, 1, 0)
    twoStatementChildren := MethodBodyFactsInts3(1, 2, 3)
    twoStatementStarts := MethodBodyFactsInts4(0, 0, 0, 0)
    twoStatementLengths := MethodBodyFactsInts4(0, 0, 0, 2)
    twoStatementNodes := MethodBodyFactsNodes(twoStatementKinds, twoStatementCounts, twoStatementChildren, twoStatementStarts, twoStatementLengths, 2)
    assert !MethodBodyFactsPlanBody(twoStatementNodes, "42", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())

    // A VALUE-LESS return reached as a VALUE body — `isVoid` is false and the return type is not void,
    // so neither arity fits and the claim is refused from both sides.
    assert !MethodBodyFactsPlanBody(MethodBodyFactsBareReturnBody(), " ", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())

    // A body root that is not a block at all — a bare expression-bodied lambda reaches the host by a
    // different route and must not be claimed here.
    assert !MethodBodyFactsPlanBody(MethodBodyFactsLeaf(20, 1), " ", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())
}


// ---- BLOCK 7 — THE BOOLEAN CLASS (015-B4) ----
//
// A bool literal is kind 4 and belongs to a DIFFERENT owner than every other literal, so it is its own
// claim class with its own byte diff. `015-B3` recorded it as a decline; it is claimed here.
//
// ⚠ WHAT IS NEW HERE IS THE BODY, NOT THE ROW CHOICE, AND THE CONTROL WALK IS WHAT ESTABLISHED THAT.
// `ColumnarCodePlan.tests.nl:137` ("boolean planner consumes the live parser node-kind ledger") has
// pinned `true` → `ldc.i4.1`, `false` → `ldc.i4.0` and the not-owned decline ALL ALONG, through the
// schema-v1 fragment surface. Mutating the owner to plan the `true` row for `false` breaks that block
// as well as this one — measured, `7,095 / 2`. What this block adds is what no v1 block could reach:
// the row lands in a schema-v4 METHOD BODY, is followed by `ret`, and the body EXECUTES.
test "the body driver claims a boolean return through the boolean owner" {
    truePlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanLiteralBody(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", typeof(bool), truePlan)
    assert truePlan.OperationCount == 2
    assert truePlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4_1()
    assert truePlan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()
    assert truePlan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()

    trueMethod := MethodBodyFactsDynamicMethod("NSharpB4BoolTrueBody", typeof(bool))
    ColumnarCodePlanExecutor.Execute(truePlan, trueMethod.GetILGenerator())
    trueTarget: object? = null
    assert Convert.ToBoolean(trueMethod.Invoke(trueTarget, MethodBodyFactsNoArguments()))

    // `false` is the OTHER row, not the same row with a different value — the owner picks between two
    // distinct short-form constants, so both are asked.
    falsePlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanLiteralBody(ColumnarExpressionNodeKind.BoolLiteralExpression(), "false", typeof(bool), falsePlan)
    assert falsePlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4_0()
    falseMethod := MethodBodyFactsDynamicMethod("NSharpB4BoolFalseBody", typeof(bool))
    ColumnarCodePlanExecutor.Execute(falsePlan, falseMethod.GetILGenerator())
    falseTarget: object? = null
    assert !Convert.ToBoolean(falseMethod.Invoke(falseTarget, MethodBodyFactsNoArguments()))

    // The claim rule is still EQUALITY: a bool literal on an `int` function is the host's business.
    assert !MethodBodyFactsPlanLiteralBody(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", typeof(int), new ColumnarCodePlan())
}

// The boolean owner's wall was STRUCTURAL rather than a predicate: schema v1 admits exactly ONE
// instruction and cannot carry a `ret` at all. So the widening is an additional append entry point,
// and this block is what proves the v1 surface it was factored out of is unchanged.
test "the boolean literal owner appends into both its schemas and keeps v1 single-instruction" {
    literalNodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true")

    // v4, flat stream, no fragment: accepted, and it can be followed by more rows.
    body := new ColumnarCodePlan()
    body.PrepareMethodBody()
    assert ColumnarBooleanLiteralPlanner.TryAppendLiteral(literalNodes, "true", 2, body)
    assert body.OperationCount == 1
    assert body.FragmentCount == 0
    body.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    assert body.OperationCount == 2

    // v1 keeps its own appender byte for byte, INCLUDING the single-instruction invariant that makes
    // it unable to hold a method body. A second row is refused.
    fragment := new ColumnarCodePlan()
    fragment.Prepare()
    assert ColumnarBooleanLiteralPlanner.TryAppendLiteral(literalNodes, "true", 2, fragment)
    assert fragment.OperationCount == 1
    assert throws InvalidOperationException {
        ColumnarBooleanLiteralPlanner.TryAppendLiteral(literalNodes, "true", 2, fragment)
    }

    // A node that is not a bool literal declines without touching the plan. The `Plan` assertions
    // below are the drift check, not a new pin — `ColumnarCodePlan.tests.nl:137` already holds the v1
    // answers, and they are re-asked HERE only to prove the refactor left ONE decision behind both
    // entry points rather than two that can diverge.
    intNodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    untouched := new ColumnarCodePlan()
    untouched.PrepareMethodBody()
    assert !ColumnarBooleanLiteralPlanner.TryAppendLiteral(intNodes, "1", 2, untouched)
    assert untouched.OperationCount == 0
    assert ColumnarBooleanLiteralPlanner.Plan(intNodes, "1", 2, new ColumnarCodePlan()) == ColumnarFragmentPlanStatus.NotOwned
    assert ColumnarBooleanLiteralPlanner.Plan(literalNodes, "true", 2, new ColumnarCodePlan()) == ColumnarFragmentPlanStatus.Planned
}


// ---- BLOCK 8 — THE PARAMETER CLASS (015-B4) ----
//
// `return <parameter>` is the first claim that needs a BINDING, and the driver does not reproduce one:
// it calls `ColumnarBoundIdentifierPlanner`, which the production expression path already routes every
// bare identifier through. That is what makes the bytes identical BY CONSTRUCTION — including the
// argument narrowing, since both sides reach `ColumnarCodePlanExecutor.EmitArgument`.
test "the body driver claims a parameter return at every ordinal and runs it" {
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanParameterBody("x", 0, typeof(int), typeof(int), plan)
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OperandKinds[0] == ColumnarCodePlanContract.ArgumentOperand()
    assert plan.ArgumentCount == 1
    assert plan.ArgumentOrdinals[0] == 0
    assert !plan.ArgumentIsAddress[0]
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()

    method := MethodBodyFactsDynamicMethodWith("NSharpB4ParamBody0", typeof(int), MethodBodyFactsIntTypes(1))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsIntArguments(1, 77))) == 77

    // ORDINAL 5 — past the four narrowed short forms, where `EmitArgument` keeps the LONG `ldarg`.
    // `015-B3`'s brief called this a hazard on the theory that the host would emit `ldarg.s`; it does
    // not, because an ordinary parameter READ never reaches the host's own `EmitLoadArgument`. Both
    // sides go through this one executor, so the claim is safe at every ordinal — asserted, not argued.
    widePlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanParameterBody("w", 5, typeof(int), typeof(int), widePlan)
    assert widePlan.ArgumentOrdinals[0] == 5
    wideMethod := MethodBodyFactsDynamicMethodWith("NSharpB4ParamBody5", typeof(int), MethodBodyFactsIntTypes(6))
    ColumnarCodePlanExecutor.Execute(widePlan, wideMethod.GetILGenerator())
    wideTarget: object? = null
    assert Convert.ToInt32(wideMethod.Invoke(wideTarget, MethodBodyFactsIntArguments(6, 91))) == 91

    // A reference-typed parameter takes the same single row.
    stringPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanParameterBody("s", 0, typeof(string), typeof(string), stringPlan)
    assert stringPlan.OperationCount == 2
}

// The claim is filtered to ONE selection kind. `ColumnarBoundIdentifierPlanner` resolves seven, and
// six of them are their own future claim classes with their own diffs — so each is asked here, in the
// negative, rather than left to an argument about what the corpus happens to contain.
test "the body driver claims only the parameter selection and refuses every other binding" {
    // Type EQUALITY, from both sides.
    assert !MethodBodyFactsPlanParameterBody("x", 0, typeof(int), typeof(long), new ColumnarCodePlan())
    assert !MethodBodyFactsPlanParameterBody("x", 0, typeof(long), typeof(int), new ColumnarCodePlan())

    // A BY-REF parameter resolves as ByRefParameter — `ldarg` plus a typed `ldind`, which is a
    // different row shape and therefore a different claim class.
    assert !MethodBodyFactsPlanParameterBody("r", 0, typeof(int).MakeByRefType(), typeof(int), new ColumnarCodePlan())

    // An ordinary LOCAL shadows nothing here: it is simply a different selection kind (`ldloc`).
    holder := MethodBodyFactsDynamicMethod("NSharpB4LocalHolder", typeof(int))
    localMap := MethodBodyFactsLocals()
    localMap["n"] = holder.GetILGenerator().DeclareLocal(typeof(int))
    localNodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IdentifierExpression(), "n")
    assert !MethodBodyFactsPlanBody(localNodes, "n", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), localMap, new ColumnarCodePlan())

    // A name with NO binding at all resolves to nothing and declines rather than guessing.
    assert !MethodBodyFactsPlanBody(localNodes, "n", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())
}

// THE NULLABLE GUARD GETS ITS OWN BLOCK, and the reason is the control walk rather than tidiness:
// with these assertions inside the block above, dropping the `Kind == Parameter` filter and dropping
// the guard broke the SAME block, so neither control isolated the other.
//
// This is the ONE host pre-pass gated on the RETURN TYPE rather than on the node kind: when the
// return type is a supported nullable, the host routes the whole return through its lifted owner
// whatever the returned expression is. Type equality HOLDS in both cases below and the claim is still
// refused — which is the point, because equality alone would have taken them.
test "the body driver refuses every claim class when the return type is a lifted nullable" {
    nullableInt := MethodBodyFactsNullableOf(typeof(int))
    assert ColumnarTypeOfPlanner.IsSupportedNullable(nullableInt)

    // The class that NEEDED the guard: a parameter and a return type that are the same `int?`.
    assert !MethodBodyFactsPlanParameterBody("x", 0, nullableInt, nullableInt, new ColumnarCodePlan())

    // …and the classes that were immune only by accident, because no literal's natural type is a
    // `Nullable<T>`. The guard covers them too, so a later widening of the claim rule cannot reopen
    // the hole from a direction nobody re-checked.
    assert !MethodBodyFactsPlanLiteralBody(ColumnarExpressionNodeKind.IntLiteralExpression(), "42", nullableInt, new ColumnarCodePlan())
    assert !MethodBodyFactsPlanLiteralBody(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", MethodBodyFactsNullableOf(typeof(bool)), new ColumnarCodePlan())

    // The guard is about the RETURN TYPE, not about nullables in general: the same parameter type on
    // a non-nullable return is refused by ordinary type equality, and a plain `int` body still claims.
    assert !MethodBodyFactsPlanParameterBody("x", 0, nullableInt, typeof(int), new ColumnarCodePlan())
    assert MethodBodyFactsPlanParameterBody("x", 0, typeof(int), typeof(int), new ColumnarCodePlan())
}

// The bound-identifier owner hit the SAME wall the scalar owner did in `015-B3`, and it is widened the
// same way. Asked from both sides so the widening cannot quietly become "any schema".
test "the bound identifier owner appends into a method body and still refuses the wrong schema" {
    identifierNodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IdentifierExpression(), "p")
    bindings := ColumnarFragmentBindings.FromRawFacts(
        MethodBodyFactsOrdinals("p", 2),
        MethodBodyFactsTypes("p", typeof(int)),
        MethodBodyFactsLocals(),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal),
        null,
        null,
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        new string[](0),
        new string[](0),
        new string[](0),
        new Dictionary<string, Type>(StringComparer.Ordinal))

    // v4, no fragment: accepted.
    body := new ColumnarCodePlan()
    body.PrepareMethodBody()
    boundType := typeof(int)
    assert ColumnarBoundIdentifierPlanner.TryAppend(identifierNodes, "p", 2, bindings, body, out boundType)
    assert boundType == typeof(int)
    assert body.OperationCount == 1
    assert body.FragmentCount == 0
    assert body.ArgumentOrdinals[0] == 2

    // v2 — the recursive fragment schema — is still refused outright, so the widening is v4-only.
    recursive := new ColumnarCodePlan()
    recursive.PrepareV2()
    recursiveType := typeof(int)
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.TryAppend(identifierNodes, "p", 2, bindings, recursive, out recursiveType)
    }

    // v1 — the boolean single-instruction schema — likewise.
    boolean := new ColumnarCodePlan()
    boolean.Prepare()
    booleanType := typeof(int)
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.TryAppend(identifierNodes, "p", 2, bindings, boolean, out booleanType)
    }
}


// ---- BLOCK 9 — THE VOID ARITY (015-B4) ----
//
// Two shapes, one byte. `{ }` reaches the host's TRAILING `ret` (the body falls through) and
// `{ return }` reaches kind 20's void arm; both are exactly `ret`, which is why they are one class.
test "the body driver claims both void shapes and refuses everything that is not a bare ret" {
    emptyPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanBody(MethodBodyFactsEmptyBody(), " ", MethodBodyFactsVoidType(), true, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), emptyPlan)
    assert emptyPlan.OperationCount == 1
    assert emptyPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ret()
    assert emptyPlan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()

    emptyMethod := MethodBodyFactsDynamicMethod("NSharpB4VoidEmptyBody", MethodBodyFactsVoidType())
    ColumnarCodePlanExecutor.Execute(emptyPlan, emptyMethod.GetILGenerator())
    emptyTarget: object? = null
    emptyMethod.Invoke(emptyTarget, MethodBodyFactsNoArguments())

    barePlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanBody(MethodBodyFactsBareReturnBody(), " ", MethodBodyFactsVoidType(), true, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), barePlan)
    assert barePlan.OperationCount == 1
    bareMethod := MethodBodyFactsDynamicMethod("NSharpB4VoidBareBody", MethodBodyFactsVoidType())
    ColumnarCodePlanExecutor.Execute(barePlan, bareMethod.GetILGenerator())
    bareTarget: object? = null
    bareMethod.Invoke(bareTarget, MethodBodyFactsNoArguments())

    // THE GATE IS BOTH HALVES. `isVoid` alone is not enough — three of the seven `EmitBody` call sites
    // pass a literal `true`, so only the RETURN TYPE reproduces the host's own `typeof(void)` test…
    assert !MethodBodyFactsPlanBody(MethodBodyFactsEmptyBody(), " ", typeof(int), true, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())
    // …and a void RETURN TYPE alone is not enough either, because a value arity over a void type is
    // not a shape the host's kind-20 arm can reach.
    assert !MethodBodyFactsPlanBody(MethodBodyFactsEmptyBody(), " ", MethodBodyFactsVoidType(), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())

    // A void body with any OTHER statement is not a bare `ret` and is left to the host.
    assert !MethodBodyFactsPlanBody(MethodBodyFactsLeaf(25, 1), " ", MethodBodyFactsVoidType(), true, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())
    // Two statements, even when both are returns.
    assert !MethodBodyFactsPlanBody(MethodBodyFactsLeaf(25, 2), " ", MethodBodyFactsVoidType(), true, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())
    // A VALUE-bearing return in a void body — the host declines it as a mismatched arity (NL103), so
    // the driver must not quietly emit a bare `ret` and discard the value.
    assert !MethodBodyFactsPlanBody(MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IntLiteralExpression(), "1"), "1", MethodBodyFactsVoidType(), true, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new ColumnarCodePlan())
}


// ---- BLOCK 10 — THE SECOND STATEMENT-SHAPE PREDICATE (015-B4) ----
//
// `ContainsReturnStatement` moved out of `ColumnarIlEmitter.cs` for the same reason `AlwaysReturns`
// did in `015-B3`: it is a pure node-table predicate with no emitter state. It is the ctor paths'
// `return`-is-forbidden guard, so a rule that answered `false` too readily would let a `return` into a
// constructor body — which is why the recursive half is asked at depth rather than only at the root.
test "the columnar return search finds a return at any depth and refuses invalid input" {
    assert ColumnarMethodBodyPlanner.ContainsReturnStatement(MethodBodyFactsLeaf(20, 0), 0)
    assert !ColumnarMethodBodyPlanner.ContainsReturnStatement(MethodBodyFactsLeaf(23, 0), 0)
    assert !ColumnarMethodBodyPlanner.ContainsReturnStatement(MethodBodyFactsLeaf(25, 2), 0)

    // NESTED, and not as the first child: block[expr, if[expr, return]].
    nestedKinds := MethodBodyFactsInts5(25, 23, 27, 23, 20)
    nestedCounts := MethodBodyFactsInts5(2, 0, 2, 0, 0)
    nestedChildren := MethodBodyFactsInts4(1, 2, 3, 4)
    nestedZeros := MethodBodyFactsInts5(0, 0, 0, 0, 0)
    nested := MethodBodyFactsNodes(nestedKinds, nestedCounts, nestedChildren, nestedZeros, nestedZeros, 1)
    assert ColumnarMethodBodyPlanner.ContainsReturnStatement(nested, 0)
    // …and the same tree with the return replaced by an expression statement does not.
    noReturnKinds := MethodBodyFactsInts5(25, 23, 27, 23, 23)
    assert !ColumnarMethodBodyPlanner.ContainsReturnStatement(MethodBodyFactsNodes(noReturnKinds, nestedCounts, nestedChildren, nestedZeros, nestedZeros, 1), 0)

    // Invalid input throws rather than answering; a silent `false` here would be a missing guard.
    assert throws InvalidOperationException {
        ColumnarMethodBodyPlanner.ContainsReturnStatement(MethodBodyFactsLeaf(20, 0), 9)
    }
}


// ---- BLOCK 6 — THE SHARED WIDENING ----
//
// A method body is schema v4, which the plan documents as a SUPERSET of v3 — but the literal owner's
// input gate demanded v3 exactly AND an open expression fragment, and v4 has no fragments at all. That
// gate was the one thing standing between "one literal owner for every expression context" (the
// owner's own header) and a method body. It is widened here, and the widening is asked from both
// sides.
test "the scalar literal owner appends into a method body and still refuses the wrong schema" {
    // v4, no fragment: accepted.
    body := new ColumnarCodePlan()
    body.PrepareMethodBody()
    literalType := typeof(int)
    literalNodes := MethodBodyFactsLiteralBody(0, "9")
    assert ColumnarScalarLiteralPlanner.TryAppendLiteral(literalNodes, "9", 2, body, out literalType)
    assert literalType == typeof(int)
    assert body.OperationCount == 1
    assert body.FragmentCount == 0

    // v3 WITHOUT an open fragment: still refused. The widening dropped the fragment requirement for v4
    // only, so v3's own invariant is untouched.
    fragmentless := new ColumnarCodePlan()
    fragmentless.PrepareV3()
    fragmentlessType := typeof(int)
    assert throws InvalidOperationException {
        ColumnarScalarLiteralPlanner.TryAppendLiteral(literalNodes, "9", 2, fragmentless, out fragmentlessType)
    }

    // v2 — the recursive fragment schema — is not a literal context at all and is refused outright.
    recursive := new ColumnarCodePlan()
    recursive.PrepareV2()
    recursiveType := typeof(int)
    assert throws InvalidOperationException {
        ColumnarScalarLiteralPlanner.TryAppendLiteral(literalNodes, "9", 2, recursive, out recursiveType)
    }
}
