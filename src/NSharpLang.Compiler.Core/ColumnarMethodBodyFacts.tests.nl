namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Reflection.Emit


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
// bindings passes empty maps, which is exactly what a static free function's body has. The last three
// arguments are `015-B7`'s routed facts, and passing them EMPTY here is the honest default: an empty
// exact-name index and an empty sibling map are what a free function with no source siblings actually
// has, and `false` is what `_overflowCheckingEnabled` provably holds at every `EmitBody` entry.
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
        new Dictionary<string, Type>(StringComparer.Ordinal),
        false,
        new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal),
        plan,
        null
    )
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

// The claim is FILTERED. `ColumnarBoundIdentifierPlanner` resolves seven selection kinds; `015-B4`
// claimed one and `015-B5` claims four, so the three that remain are asked here in the negative rather
// than left to an argument about what the corpus happens to contain. (`ByRefParameter` moved OUT of
// this block when B5 claimed it — see the by-ref block below. That is a pin this slice deliberately
// flipped, not one it quietly dropped.)
test "the body driver claims only the parameter selection and refuses every other binding" {
    // Type EQUALITY, from both sides.
    assert !MethodBodyFactsPlanParameterBody("x", 0, typeof(int), typeof(long), new ColumnarCodePlan())
    assert !MethodBodyFactsPlanParameterBody("x", 0, typeof(long), typeof(int), new ColumnarCodePlan())

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
        new Dictionary<string, Type>(StringComparer.Ordinal),
        null
    )

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

// ---- 015-B5 — THE APPEND-MODE EXPRESSION FRONT DOOR ----
//
// THE SLICE'S DECODE OVERTURNED TWO OF ITS OWN BRIEF'S ITEMS AND THESE BLOCKS ARE WHERE THAT IS PINNED.
// The brief said `ColumnarConditionalPlanner` was the one owner needing an append entry BUILT; its
// entries exist (`TryPlanTernary`, `TryPlanShortCircuit`) and are simply not spelled `TryAppend*`. It
// also said the current-instance pair would make three deliberately-unrouted binding facts mandatory;
// none of the three is read anywhere on the identifier path, so the pair costs nothing new.
//
// WHAT THE SLICE ACTUALLY BUILT is a TOTAL, kind-keyed expression door and three more identifier
// classes behind it. The door's claimed set is small for a MEASURED reason rather than a cautious one:
// nine of the twelve owners on the value surface assert an open schema-v3 plan and THROW on a method
// body, so every composite is a crash rather than a decline until those nine gates are widened
// together. The partition block below is what makes "total" a fact instead of a promise.

// ---- shared fixtures for the current-instance pair ----
//
// The current-instance facts are built from a RUNTIME type, exactly the way
// `ColumnarBoundIdentifierPlanner.tests.nl` builds its own — which is the only route the estate has,
// since `TryPlanBody`'s `currentInstance` parameter is a `ColumnarStructDef` over a `TypeBuilder`. The
// door takes the bindings directly, so these blocks exercise the thing this slice built.

class ColumnarMethodBodyCurrentClassProbe {
    Field: int

    constructor(value: int) {
        Field = value
    }

    Value: int => Field
}

struct ColumnarMethodBodyCurrentStructProbe {
    Field: int

    constructor(value: int) {
        Field = value
    }

    Value: int => Field
}

func MethodBodyFactsRequiredField(owner: Type, name: string): FieldInfo {
    field := owner.GetField(name)
    if field == null {
        throw new InvalidOperationException("Required current-instance field was not found.")
    }
    return field
}

func MethodBodyFactsRequiredGetter(owner: Type, name: string): MethodInfo {
    getter := owner.GetMethod(name, new Type[](0))
    if getter == null {
        throw new InvalidOperationException("Required current-instance getter was not found.")
    }
    return getter
}

func MethodBodyFactsEmptyBindings(): ColumnarFragmentBindings {
    return ColumnarFragmentBindings.FromRawFacts(
        MethodBodyFactsNoOrdinals(),
        MethodBodyFactsNoTypes(),
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
        new Dictionary<string, Type>(StringComparer.Ordinal),
        null
    )
}

// Bindings whose ONLY fact is a current instance carrying one field and one property.
func MethodBodyFactsCurrentBindings(owner: Type, isReference: bool): ColumnarFragmentBindings {
    facts := new ColumnarCurrentInstanceFacts(owner, isReference)
    facts.Fields["Field"] = MethodBodyFactsRequiredField(owner, "Field")
    facts.Properties["Value"] = new ColumnarCurrentPropertyFact(MethodBodyFactsRequiredGetter(owner, "get_Value"), typeof(int), 0)
    bindings := MethodBodyFactsEmptyBindings()
    bindings.CurrentInstance = facts
    return bindings
}

// One expression through the door, into a fresh method-body plan, terminated exactly as the driver
// terminates it. This is the driver's own value path with the body shape held constant.
func MethodBodyFactsDoorPlan(name: string, bindings: ColumnarFragmentBindings, returnType: Type, plan: ColumnarCodePlan): bool {
    nodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    plan.PrepareMethodBody()
    valueType := typeof(int)
    if !ColumnarMethodBodyPlanner.TryAppendReturnValue(nodes, name, 2, bindings, plan, out valueType) {
        return false
    }
    if valueType != returnType {
        return false
    }
    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    plan.CompleteMethodBody(returnType)
    return true
}

// ---- BLOCK 11 — THE DOOR IS TOTAL ----
//
// Totality is the door's whole safety argument, so it is asserted rather than asserted-about: for
// EVERY kind on the ledger exactly one of the two predicates holds, and the ledger is the union of
// `ColumnarExpressionNodeKind` with the kinds `ColumnarIlEmitter.EmitExpressionCore` and its
// pre-switch owners handle. A kind that fell out of both predicates would be a silent hole; a kind
// that satisfied both would mean the door claims and declines the same shape.
test "the expression door partitions its whole kind ledger with no hole and no overlap" {
    ledger := ColumnarMethodBodyPlanner.ExpressionKindLedger()
    assert ledger.Length == 34

    claimed := 0
    i := 0
    while i < ledger.Length {
        kind := ledger[i]
        isClaimed := ColumnarMethodBodyPlanner.IsClaimedExpressionKind(kind)
        isDeclined := ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(kind)
        // Exactly one — never neither (a hole) and never both (a contradiction).
        assert isClaimed != isDeclined
        if isClaimed {
            claimed = claimed + 1
        }
        i = i + 1
    }

    // FIFTEEN claimed kinds: the four scalar-literal kinds, bool, identifier, the two composites
    // 015-B6 took, the direct CALL (015-B7), the primitive BINARY (015-B9), the TERNARY (015-B12), the
    // CHECKED CONTEXT (015-B13), the MEMBER-ACCESS root (015-B14) and, in 015-B16, the PARENTHESIS
    // root and the TYPEOF root. The count is pinned so a widening cannot arrive without a block that
    // says what it claims — this assertion is the reason none of `015-B12`'s, `015-B13`'s, `015-B14`'s
    // or `015-B16`'s widenings could land silently, and it has been REWRITTEN by each of them
    // (10 -> 11 -> 12 -> 13 -> 15) rather than relaxed. Each slice's first run of this block FAILED
    // before it was updated, which is the block working — `015-B16`'s census of parenthesis pins found
    // SEVEN and this block found the EIGHTH, which is exactly the hole a census over source text
    // cannot see.
    assert claimed == 15
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.IntLiteralExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.FloatLiteralExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.CharLiteralExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.StringLiteralExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.BoolLiteralExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.IdentifierExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.UnaryExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.NameOfExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.CallExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.BinaryExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.TernaryExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.CheckedContextExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.MemberAccessExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.ParenthesizedExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.TypeOfExpression())

    // The composites that remain declined are declined one by one. Their gates are open now; what
    // holds them back is the emitter's ELEVEN-ARM root cascade, which a claim must enter arm by arm.
    // ⚠ `CallExpression` LEFT THIS LIST in 015-B7, `BinaryExpression` in 015-B9, `TernaryExpression`
    // in 015-B12, `CheckedContextExpression` in 015-B13, `MemberAccessExpression` in 015-B14 and
    // `ParenthesizedExpression` in 015-B16; all six are asserted CLAIMED above.
    //
    // ⚠ THE PARENTHESIS SENTENCE THAT STOOD HERE WAS WRONG ABOUT THE HOST. It said the owner's own
    // `UnwrapParentheses` is reached through its ROOT FACADE while the door dispatches on the OUTER
    // kind, "so `(p.V)` is the parenthesis owner's shape even though `(p).V` is the instance-member
    // owner's". `FacadeRootMayNeedFacts` unwraps BEFORE the cascade and every cascade owner's
    // `MayPlanRoot` unwraps again, so on the HOST side `(p.V)` is the instance-member owner's shape
    // too — claimed at the OUTER node. The door's kind-7 arm dispatches the CHILD through the same
    // dispatcher and reaches the same owner's `TryAppendRoot`, which unwraps as well, so the rows
    // agree by construction rather than by transcription.
    assert ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.NewExpression())
    assert ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.IndexAccessExpression())
    assert ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.CastExpression())
    assert !ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.ParenthesizedExpression())
    assert !ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.TypeOfExpression())

    // And a DECLINED kind declines at the door without touching the plan, which is what lets the
    // driver reuse one plan object across a decline.
    untouched := new ColumnarCodePlan()
    untouched.PrepareMethodBody()
    indexNodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IndexAccessExpression(), "f")
    indexType := typeof(int)
    assert !ColumnarMethodBodyPlanner.TryAppendReturnValue(indexNodes, "f", 2, MethodBodyFactsEmptyBindings(), untouched, out indexType)
    assert untouched.OperationCount == 0

    // A CLAIMED kind whose owner refuses the particular node — a call with no callee child at all —
    // rolls back just as completely. This is the arm that replaced the member-access probe above when
    // kind 9 moved sides, and it asserts the same invariant about a different mechanism.
    callNodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.CallExpression(), "f")
    callType := typeof(int)
    assert !ColumnarMethodBodyPlanner.TryAppendReturnValue(callNodes, "f", 2, MethodBodyFactsEmptyBindings(), untouched, out callType)
    assert untouched.OperationCount == 0
    assert untouched.FragmentCount == 0

    // A kind OFF the ledger entirely — 25 is a statement block, which never reaches value position —
    // is neither claimed nor declined by name, and the door still refuses it.
    assert !ColumnarMethodBodyPlanner.IsClaimedExpressionKind(25)
    assert !ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(25)
    blockNodes := MethodBodyFactsLiteralBody(25, "x")
    blockType := typeof(int)
    assert !ColumnarMethodBodyPlanner.TryAppendReturnValue(blockNodes, "x", 2, MethodBodyFactsEmptyBindings(), untouched, out blockType)
    assert untouched.OperationCount == 0
}

// ---- BLOCK 12 — THE BY-REF PARAMETER CLASS (X) ----
//
// `015-B4` pinned this shape as a DECLINE and named it a future claim class; this is that future. A
// ref/out parameter READ is `ldarg <n>` plus one typed `ldind` — two rows where the plain parameter
// class has one — and the selection carries the ELEMENT type as its result, so type equality is asked
// against the element rather than against the `T&`.
test "the body driver claims a by-ref parameter return and derefs it through the typed ldind table" {
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanParameterBody("r", 0, typeof(int).MakeByRefType(), typeof(int), plan)
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.LdindI4()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()
    // The argument slot is an ADDRESS fact, which is what keeps `ldarga` off it.
    assert plan.ArgumentCount == 1
    assert plan.ArgumentIsAddress[0]

    refTypes := new Type[](1)
    refTypes[0] = typeof(int).MakeByRefType()
    method := MethodBodyFactsDynamicMethodWith("NSharpB5ByRefBody", typeof(int), refTypes)
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsIntArguments(1, 63))) == 63

    // EQUALITY IS AGAINST THE ELEMENT. `ref int` on an `int` function claims; the same parameter on a
    // `long` function does not, and neither does a plain `int` parameter on a body that expected the
    // deref — the two classes cannot be substituted for one another.
    assert !MethodBodyFactsPlanParameterBody("r", 0, typeof(int).MakeByRefType(), typeof(long), new ColumnarCodePlan())

    // An element OUTSIDE the typed-ldind table — decimal has no `ldind` form — resolves to nothing and
    // stays with the host's `Ldobj` deref arm. The claim is the table, not "any by-ref".
    assert !MethodBodyFactsPlanParameterBody("r", 0, typeof(decimal).MakeByRefType(), typeof(decimal), new ColumnarCodePlan())
}

// ---- BLOCK 13 — THE CURRENT-FIELD CLASS (F) ----
//
// A bare instance-FIELD read inside an instance body. This is the identifier class the BUILDABLE
// corpus actually contains — `return issues` in the issue-tracker store, and the three explicit
// `get { return <backing field> }` accessor bodies in `PropertiesAndNestedTypes.nl` — which is why it
// is taken ahead of the three that need a statement loop first.
//
// ⚠ THIS BLOCK ASKS ONLY THE FIELD, AND THAT SPLIT IS THE CONTROL WALK'S DOING. Written once as a
// single "current-instance pair" block over both receivers, dropping CurrentField and dropping
// CurrentProperty broke the SAME three blocks, so neither control isolated the other — `015-B4`'s
// `W4`/`W5` lesson repeating, caught the same way. The blocks are now split by MEMBER; each still
// asks both receiver kinds, because the receiver is one class's own row decision rather than a
// second mechanism.
test "the expression door claims a current field on a reference and on a value receiver" {
    bindings := MethodBodyFactsCurrentBindings(typeof(ColumnarMethodBodyCurrentClassProbe), true)

    fieldPlan := new ColumnarCodePlan()
    assert MethodBodyFactsDoorPlan("Field", bindings, typeof(int), fieldPlan)
    assert fieldPlan.OperationCount == 3
    assert fieldPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert fieldPlan.ArgumentOrdinals[0] == 0
    assert !fieldPlan.ArgumentIsAddress[0]
    assert fieldPlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()
    assert fieldPlan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()

    probeTypes := new Type[](1)
    probeTypes[0] = typeof(ColumnarMethodBodyCurrentClassProbe)
    probeArguments := new object[](1)
    MethodBodyFactsSetArgument(probeArguments, 0, new ColumnarMethodBodyCurrentClassProbe(45))
    fieldMethod := MethodBodyFactsDynamicMethodWith("NSharpB5CurrentFieldBody", typeof(int), probeTypes)
    ColumnarCodePlanExecutor.Execute(fieldPlan, fieldMethod.GetILGenerator())
    fieldTarget: object? = null
    assert Convert.ToInt32(fieldMethod.Invoke(fieldTarget, probeArguments)) == 45

    // A VALUE receiver takes the other half of the row decision: the argument slot becomes an ADDRESS.
    // The rows are asserted rather than executed, because the interesting fact is the choice.
    valuePlan := new ColumnarCodePlan()
    assert MethodBodyFactsDoorPlan("Field", MethodBodyFactsCurrentBindings(typeof(ColumnarMethodBodyCurrentStructProbe), false), typeof(int), valuePlan)
    assert valuePlan.ArgumentCount == 1
    assert valuePlan.ArgumentOrdinals[0] == 0
    assert valuePlan.ArgumentIsAddress[0]
    assert valuePlan.OpCodeValues[1] == ColumnarCodePlanContract.Ldfld()

    // A name the current instance does not carry resolves to NOTHING rather than to a guess.
    assert !MethodBodyFactsDoorPlan("Missing", MethodBodyFactsCurrentBindings(typeof(ColumnarMethodBodyCurrentClassProbe), true), typeof(int), new ColumnarCodePlan())

    // Type EQUALITY still rules: an `int` field on a `long` body is the host's business.
    assert !MethodBodyFactsDoorPlan("Field", MethodBodyFactsCurrentBindings(typeof(ColumnarMethodBodyCurrentClassProbe), true), typeof(long), new ColumnarCodePlan())
}

// ---- BLOCK 13a — THE CURRENT-PROPERTY CLASS (R) ----
//
// Not the same class as the field: a property read is a receiver plus a getter CALL, and the CALL FORM
// is chosen by the receiver kind — `callvirt` for a reference instance, a non-virtual `call` for a
// value one. Both directions are asked, because a rule that only ever answered `callvirt` would pass a
// one-sided sweep and then emit an invalid virtual call on a struct.
test "the expression door claims a current property and picks the call form from the receiver" {
    probeTypes := new Type[](1)
    probeTypes[0] = typeof(ColumnarMethodBodyCurrentClassProbe)
    probeArguments := new object[](1)
    MethodBodyFactsSetArgument(probeArguments, 0, new ColumnarMethodBodyCurrentClassProbe(45))

    propertyPlan := new ColumnarCodePlan()
    assert MethodBodyFactsDoorPlan("Value", MethodBodyFactsCurrentBindings(typeof(ColumnarMethodBodyCurrentClassProbe), true), typeof(int), propertyPlan)
    assert propertyPlan.OperationCount == 3
    assert propertyPlan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert !propertyPlan.ArgumentIsAddress[0]
    assert propertyPlan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
    assert propertyPlan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()

    propertyMethod := MethodBodyFactsDynamicMethodWith("NSharpB5CurrentPropertyBody", typeof(int), probeTypes)
    ColumnarCodePlanExecutor.Execute(propertyPlan, propertyMethod.GetILGenerator())
    propertyTarget: object? = null
    assert Convert.ToInt32(propertyMethod.Invoke(propertyTarget, probeArguments)) == 45

    // A VALUE receiver: the address plus the non-virtual form.
    valuePlan := new ColumnarCodePlan()
    assert MethodBodyFactsDoorPlan("Value", MethodBodyFactsCurrentBindings(typeof(ColumnarMethodBodyCurrentStructProbe), false), typeof(int), valuePlan)
    assert valuePlan.ArgumentIsAddress[0]
    assert valuePlan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    // …and the two forms are genuinely distinct rows, so the pair of assertions above is a choice.
    assert ColumnarCodePlanContract.Call() != ColumnarCodePlanContract.Callvirt()

    // Type EQUALITY: an `int` property on a `long` body is the host's business.
    assert !MethodBodyFactsDoorPlan("Value", MethodBodyFactsCurrentBindings(typeof(ColumnarMethodBodyCurrentClassProbe), true), typeof(long), new ColumnarCodePlan())
}

// ---- BLOCK 14 — THE SELECTION FILTER, BOTH WAYS ----
//
// The door claims FIVE of the owner's eight selection kinds. The filter is asked directly, in both
// directions, so a widening that quietly admits all eight breaks here rather than in a corpus nobody
// has an instance in.
//
// ⚠ `Local` IS STILL REFUSED AFTER THE STATEMENT LOOP LANDED, WHICH IS THE OPPOSITE OF WHAT `015-B5`
// PREDICTED. B5 recorded `Local` as arriving "with the statement loop". It did not: `Local` names an
// AMBIENT `LocalBuilder` the emitter already made, and the driver never holds an `ILGenerator` with
// which to make one. The loop's locals live in the PLAN's pool and resolve as `PlanLocal`. The other
// two unclaimed kinds are unreachable rather than untrusted — `LiftedLocal` needs a lambda to lift
// into and `BoxedCapture` needs a closure display frame, and no claimed kind can contain a lambda.
test "the identifier filter claims exactly five selection kinds and refuses the other three" {
    assert ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.Parameter)
    assert ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.ByRefParameter)
    assert ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.CurrentField)
    assert ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.CurrentProperty)
    assert ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.PlanLocal)

    assert !ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.Local)
    assert !ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.LiftedLocal)
    assert !ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.BoxedCapture)
    assert !ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(ColumnarBoundIdentifierKind.None)

    // The filter runs on a PURE resolve, so an unclaimed selection never mutates the plan — the
    // property the driver relies on when it hands one plan object to a door that may decline.
    holder := MethodBodyFactsDynamicMethod("NSharpB5LocalFilterHolder", typeof(int))
    localBindings := MethodBodyFactsEmptyBindings()
    localBindings.Locals["n"] = holder.GetILGenerator().DeclareLocal(typeof(int))
    localNodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IdentifierExpression(), "n")
    untouched := new ColumnarCodePlan()
    untouched.PrepareMethodBody()
    localType := typeof(int)
    assert !ColumnarMethodBodyPlanner.TryAppendReturnValue(localNodes, "n", 2, localBindings, untouched, out localType)
    assert untouched.OperationCount == 0
}

// ---- 015-B6 — THE NINE-OWNER GATE WIDENING AND THE STATEMENT LOOP ----
//
// THREE THINGS LAND HERE, AND EACH OVERTURNED ITS BRIEF.
//
// 1. NINE OWNER GATES asserted an open schema-v3 plan and THREW on a method body — a hard crash out of
//    the compiler rather than a decline. They were widened in ONE move, because the value surface
//    routes by operand kind and admitting a subset would mean pre-scanning operands to predict which
//    owner they reach, which is a second copy of the dispatcher's own decision. Each gets its own block
//    below: the append entry must DECLINE on a method-body plan and still THROW on the recursive
//    schema, so a gate that quietly loses its schema test breaks exactly one block.
//
// 2. THE STATEMENT LOOP could not publish the binding the brief described. `ColumnarFragmentBindings.Locals`
//    is a `Dictionary<string, LocalBuilder>`, and a plan is built with no `ILGenerator` in reach — the
//    executor materialises locals at replay. So the published binding is a PLAN-LOCAL, and the sole
//    identifier owner gained a selection tier for it rather than the driver growing a second resolver.
//
// 3. THE FRAGMENT RULE resolved to MANY ROOTS rather than one spanning fragment, and by measurement
//    rather than taste: the v4 validator and the v4 executor never read a fragment column at all, and
//    `CompleteFragment` refuses a void result outside a schema-v3 root fragment, so a body-spanning
//    root is not even expressible for the void arity.

// ---- shared fixtures ----

// A method-body plan with ONE open root fragment — what the owners whose gates also demand an open
// fragment need before their append entry may be called at all.
func MethodBodyFactsOpenRootMethodBody(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    plan.BeginFragment(-1, ColumnarExpressionNodeKind.BinaryExpression(), 0)
    return plan
}

func MethodBodyFactsOpenRootRecursive(): ColumnarCodePlan {
    plan := new ColumnarCodePlan()
    plan.PrepareV2()
    plan.BeginFragment(-1, ColumnarExpressionNodeKind.BinaryExpression(), 0)
    return plan
}

func MethodBodyFactsHandles(): ColumnarRangeIndexHandles {
    return ColumnarRangeIndexHandles.Resolve()
}

// `{ return <operator><literal> }` — a UNARY composite: the operator node owns a nested operand
// fragment, and the operand is a scalar literal.
func MethodBodyFactsUnaryBody(operatorText: string, literalKind: int, literalText: string): ColumnarNodeTable {
    kinds := MethodBodyFactsInts4(25, 20, ColumnarExpressionNodeKind.UnaryExpression(), literalKind)
    childCounts := MethodBodyFactsInts4(1, 1, 1, 0)
    children := MethodBodyFactsInts3(1, 2, 3)
    valueStarts := MethodBodyFactsInts4(0, 0, 0, operatorText.Length)
    valueLengths := MethodBodyFactsInts4(0, 0, operatorText.Length, literalText.Length)
    return MethodBodyFactsNodes(kinds, childCounts, children, valueStarts, valueLengths, operatorText.Length + literalText.Length)
}

// `{ return -<literal> }` whose LITERAL node carries NO SPAN (`valueStart = -1`, `valueLength = 0`).
// `ColumnarNodeTable.Text` would throw on it, which is why the host guards the span before reading it
// and why 015-B11's narrowed predicate has to as well.
func MethodBodyFactsUnarySpanlessOperand(operatorText: string): ColumnarNodeTable {
    kinds := MethodBodyFactsInts4(25, 20, ColumnarExpressionNodeKind.UnaryExpression(), ColumnarExpressionNodeKind.IntLiteralExpression())
    childCounts := MethodBodyFactsInts4(1, 1, 1, 0)
    children := MethodBodyFactsInts3(1, 2, 3)
    valueStarts := MethodBodyFactsInts4(0, 0, 0, -1)
    valueLengths := MethodBodyFactsInts4(0, 0, operatorText.Length, 0)
    return MethodBodyFactsNodes(kinds, childCounts, children, valueStarts, valueLengths, operatorText.Length)
}

// `{ return nameof(<name>) }` — the target is a bare identifier.
func MethodBodyFactsNameOfBody(name: string, targetKind: int): ColumnarNodeTable {
    kinds := MethodBodyFactsInts4(25, 20, ColumnarExpressionNodeKind.NameOfExpression(), targetKind)
    childCounts := MethodBodyFactsInts4(1, 1, 1, 0)
    children := MethodBodyFactsInts3(1, 2, 3)
    valueStarts := MethodBodyFactsInts4(0, 0, 0, 0)
    valueLengths := MethodBodyFactsInts4(0, 0, 0, name.Length)
    return MethodBodyFactsNodes(kinds, childCounts, children, valueStarts, valueLengths, name.Length)
}

// `{ <name> := <literal>; return <name> }` — the smallest body that needs a binding the DRIVER made.
func MethodBodyFactsDeclareThenReturnBody(name: string, literalKind: int, literalText: string): ColumnarNodeTable {
    kinds := MethodBodyFactsInts5(25, 24, literalKind, 20, ColumnarExpressionNodeKind.IdentifierExpression())
    childCounts := MethodBodyFactsInts5(2, 1, 0, 1, 0)
    children := MethodBodyFactsInts4(1, 3, 2, 4)
    valueStarts := MethodBodyFactsInts5(0, 0, name.Length, 0, 0)
    valueLengths := MethodBodyFactsInts5(0, name.Length, literalText.Length, 0, name.Length)
    return MethodBodyFactsNodes(kinds, childCounts, children, valueStarts, valueLengths, name.Length + literalText.Length)
}

// `{ a := <literal>; b := a; return b }` — the shape that proves a LATER statement consumes what an
// EARLIER one published, which is the whole point of the loop.
func MethodBodyFactsDeclareChainBody(first: string, second: string, literalText: string): ColumnarNodeTable {
    kinds := MethodBodyFactsInts7(25, 24, 0, 24, ColumnarExpressionNodeKind.IdentifierExpression(), 20, ColumnarExpressionNodeKind.IdentifierExpression())
    childCounts := MethodBodyFactsInts7(3, 1, 0, 1, 0, 1, 0)
    children := MethodBodyFactsInts6(1, 3, 5, 2, 4, 6)
    firstStart := 0
    secondStart := first.Length
    literalStart := first.Length + second.Length
    valueStarts := MethodBodyFactsInts7(0, firstStart, literalStart, secondStart, firstStart, 0, secondStart)
    valueLengths := MethodBodyFactsInts7(0, first.Length, literalText.Length, second.Length, first.Length, 0, second.Length)
    return MethodBodyFactsNodes(kinds, childCounts, children, valueStarts, valueLengths, first.Length + second.Length + literalText.Length)
}

// `{ a := <op><literal>; return <op><literal> }` — TWO composite statements, therefore TWO root
// fragments in one method-body plan. This is the shape the single-root rule refused before this slice.
// The two operators are separate parameters because the RETURN position cannot carry `-` over an
// integer literal: the host's kind-20 arm adopts that shape itself.
func MethodBodyFactsTwoCompositeBody(name: string, firstOperator: string, firstText: string, secondOperator: string, secondText: string): ColumnarNodeTable {
    kinds := MethodBodyFactsInts7(25, 24, ColumnarExpressionNodeKind.UnaryExpression(), 0, 20, ColumnarExpressionNodeKind.UnaryExpression(), 0)
    childCounts := MethodBodyFactsInts7(2, 1, 1, 0, 1, 1, 0)
    children := MethodBodyFactsInts6(1, 4, 2, 3, 5, 6)
    firstOperatorAt := name.Length
    firstAt := firstOperatorAt + firstOperator.Length
    secondOperatorAt := firstAt + firstText.Length
    secondAt := secondOperatorAt + secondOperator.Length
    valueStarts := MethodBodyFactsInts7(0, 0, firstOperatorAt, firstAt, 0, secondOperatorAt, secondAt)
    valueLengths := MethodBodyFactsInts7(0, name.Length, firstOperator.Length, firstText.Length, 0, secondOperator.Length, secondText.Length)
    return MethodBodyFactsNodes(kinds, childCounts, children, valueStarts, valueLengths, secondAt + secondText.Length)
}

func MethodBodyFactsInts7(a: int, b: int, c: int, d: int, e: int, f: int, g: int): int[] {
    result := new int[](7)
    result[0] = a
    result[1] = b
    result[2] = c
    result[3] = d
    result[4] = e
    result[5] = f
    result[6] = g
    return result
}

// ---- BLOCKS 22-30 — THE NINE GATES, ONE BLOCK EACH ----
//
// Every block asks the SAME two questions of one owner: does its append entry reach its own logic on a
// method-body plan (decline, not crash), and does it still refuse the recursive schema? The inputs are
// deliberately shaped to be DECLINED on their merits, because what is under test is the GATE and not
// the owner. Before this slice every one of these was `assert throws` on both sides.

test "the construction owner's gate admits a method body and still refuses the recursive schema" {
    nodes := MethodBodyFactsLeaf(ColumnarExpressionNodeKind.NewExpression(), 0)
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    resultType := typeof(int)
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarConstructionPlanner.TryAppend(nodes, "n", 0, MethodBodyFactsEmptyBindings(), MethodBodyFactsHandles(), body, 0, 0, out ownership, out legacy, out resultType)
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarConstructionPlanner.TryAppend(nodes, "n", 0, MethodBodyFactsEmptyBindings(), MethodBodyFactsHandles(), recursive, 0, 0, out ownership, out legacy, out resultType)
    }
}

test "the direct-call owner's gate admits a method body and still refuses the recursive schema" {
    nodes := MethodBodyFactsLeaf(ColumnarExpressionNodeKind.CallExpression(), 1)
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacy := false
    resultType := typeof(int)
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarDirectCallPlanner.TryAppendCall(nodes, "f", 0, MethodBodyFactsEmptyBindings(), MethodBodyFactsHandles(), body, 0, 0, out ownership, out legacy, out resultType)
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarDirectCallPlanner.TryAppendCall(nodes, "f", 0, MethodBodyFactsEmptyBindings(), MethodBodyFactsHandles(), recursive, 0, 0, out ownership, out legacy, out resultType)
    }
}

test "the external static-member owner's gate admits a method body and still refuses the recursive schema" {
    nodes := MethodBodyFactsLeaf(ColumnarExpressionNodeKind.MemberAccessExpression(), 1)
    resultType := typeof(int)
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarExternalStaticMemberPlanner.TryAppendStaticMember(nodes, "m", 0, MethodBodyFactsEmptyBindings(), body, out resultType)
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarExternalStaticMemberPlanner.TryAppendStaticMember(nodes, "m", 0, MethodBodyFactsEmptyBindings(), recursive, out resultType)
    }
}

test "the instance-member owner's gate admits a method body and still refuses the recursive schema" {
    nodes := MethodBodyFactsLeaf(ColumnarExpressionNodeKind.MemberAccessExpression(), 1)
    resultType := typeof(int)
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarInstanceMemberPlanner.TryAppend(nodes, "m", 0, MethodBodyFactsEmptyBindings(), body, 0, false, out resultType)
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarInstanceMemberPlanner.TryAppend(nodes, "m", 0, MethodBodyFactsEmptyBindings(), recursive, 0, false, out resultType)
    }
}

test "the nameof owner's gate admits a method body and still refuses the recursive schema" {
    nodes := MethodBodyFactsLeaf(ColumnarExpressionNodeKind.NameOfExpression(), 0)
    resultType := typeof(string)
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarNameOfPlanner.TryAppendNameOf(nodes, "n", 0, body, out resultType)
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarNameOfPlanner.TryAppendNameOf(nodes, "n", 0, recursive, out resultType)
    }
}

test "the nullable-argument lowering's gate admits a method body and still refuses the recursive schema" {
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarNullableArgumentLowering.TryAppendValueLift(body, typeof(int), typeof(string))
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarNullableArgumentLowering.TryAppendValueLift(recursive, typeof(int), typeof(string))
    }
}

test "the unary-literal owner's gate admits a method body and still refuses the recursive schema" {
    nodes := MethodBodyFactsLeaf(ColumnarExpressionNodeKind.UnaryExpression(), 0)
    resultType := typeof(int)
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarUnaryLiteralPlanner.TryAppendUnaryLiteral(nodes, "-", 0, body, 0, out resultType)
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarUnaryLiteralPlanner.TryAppendUnaryLiteral(nodes, "-", 0, recursive, 0, out resultType)
    }
}

test "the primitive-binary owner's gate admits a method body and still refuses the recursive schema" {
    nodes := MethodBodyFactsLeaf(ColumnarExpressionNodeKind.BinaryExpression(), 0)
    resultType := typeof(int)
    nestedOwnership := ColumnarDirectCallOwnership.NotOwned
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarPrimitiveBinaryPlanner.TryAppend(nodes, "+", 0, MethodBodyFactsEmptyBindings(), MethodBodyFactsHandles(), body, 0, 0, out resultType, out nestedOwnership)
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarPrimitiveBinaryPlanner.TryAppend(nodes, "+", 0, MethodBodyFactsEmptyBindings(), MethodBodyFactsHandles(), recursive, 0, 0, out resultType, out nestedOwnership)
    }
}

test "the typeof owner's gate admits a method body and still refuses the recursive schema" {
    nodes := MethodBodyFactsLeaf(ColumnarExpressionNodeKind.TypeOfExpression(), 1)
    resultType := typeof(Type)
    body := MethodBodyFactsOpenRootMethodBody()
    assert !ColumnarTypeOfPlanner.TryAppendTypeOf(nodes, "t", 0, MethodBodyFactsEmptyBindings(), body, out resultType)
    assert body.OperationCount == 0

    recursive := MethodBodyFactsOpenRootRecursive()
    assert throws InvalidOperationException {
        ColumnarTypeOfPlanner.TryAppendTypeOf(nodes, "t", 0, MethodBodyFactsEmptyBindings(), recursive, out resultType)
    }
}

// ---- BLOCK 31 — THE COMPOSED-INPUT PROBE: A COMPOSITE CLAIMS END TO END ----
//
// The nine widenings buy nothing until a composite actually claims, and `015-B5` refused to land them
// for exactly that reason. This is the proof that they are not dead code: a UNARY over a scalar
// literal makes its owner open a nested operand fragment INSIDE the root fragment on a method-body
// plan and recurse into a second owner. Two fragments, three rows, one runnable body.
test "the door claims a unary literal composite and nests its operand fragment on a method body" {
    plan := new ColumnarCodePlan()
    nodes := MethodBodyFactsUnaryBody("~", 0, "3")
    assert MethodBodyFactsPlanBody(nodes, "~3", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), plan)

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Not()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()
    assert plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()

    // TWO fragments — the root the door opened and the operand fragment the owner nested under it.
    // This is the fragment machinery running on a schema it had never run on before.
    assert plan.FragmentCount == 2
    assert plan.FragmentParentIndices[0] == -1
    assert plan.FragmentParentIndices[1] == 0
    assert plan.OpenFragmentCount == 0

    method := MethodBodyFactsDynamicMethod("NSharpB6UnaryBody", typeof(int))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsNoArguments())) == -4

    // A FLOAT operand negates through the same owner to a `neg` row, so the claim is the owner's and
    // not one operator's — and a float child is outside the kind-20 arm's integer adoption entirely.
    negPlan := new ColumnarCodePlan()
    negNodes := MethodBodyFactsUnaryBody("-", 1, "2.5")
    assert MethodBodyFactsPlanBody(negNodes, "-2.5", typeof(double), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), negPlan)
    assert negPlan.OpCodeValues[1] == ColumnarCodePlanContract.Neg()
    assert negPlan.FragmentCount == 2

    // And a unary whose operand is NOT a literal is refused by the owner, which rolls the root fragment
    // back so the plan the driver hands on is untouched.
    declined := new ColumnarCodePlan()
    declined.PrepareMethodBody()
    declinedNodes := MethodBodyFactsUnaryBody("~", ColumnarExpressionNodeKind.IdentifierExpression(), "n")
    declinedType := typeof(int)
    assert !ColumnarMethodBodyPlanner.TryAppendReturnValue(declinedNodes, "~n", 2, MethodBodyFactsEmptyBindings(), declined, out declinedType)
    assert declined.OperationCount == 0
    assert declined.FragmentCount == 0
}

// ---- BLOCK 31b — ⚠ THE RETURN POSITION IS NOT THE VALUE POSITION ----
//
// A BYTE DIFF FOUND THIS, NOT AN ARGUMENT, and it overturns `015-B5`'s reading of its own guard. B5
// recorded the kind-20 arm's seven target-typed pre-passes as "provably unreached" because the claim
// rule is type EQUALITY. That holds for `TryEmitIntLiteralAsType`'s POSITIVE arm, which claims only
// byte/sbyte/short/ushort/uint/long/ulong — and fails for its NEGATIVE arm, which takes a unary minus
// over an unsuffixed decimal integer literal on EVERY signed target, `int` included, and emits the
// value PRE-NEGATED with no `neg` row at all.
//
// The host's kind-24 arm runs no pre-pass, so the same shape is claimable as an INITIALIZER and refused
// as a RETURN. Both directions are asserted here, because one door serving two positions is precisely
// the mistake the diff caught.
test "the return door refuses the shape the kind-20 arm adopts and the initializer door claims it" {
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5"), "-5", 2)
    // A FLOAT child, a different operator, and a bare literal are all outside the adopted shape.
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 1, "2.5"), "-2.5", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("~", 0, "3"), "~3", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsLiteralBody(0, "5"), "5", 2)

    // AS A RETURN: refused, and the plan is untouched.
    returnPlan := new ColumnarCodePlan()
    returnNodes := MethodBodyFactsUnaryBody("-", 0, "5")
    assert !MethodBodyFactsPlanBody(returnNodes, "-5", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), returnPlan)

    // AS AN INITIALIZER: claimed, and it lowers to `ldc.i4 5; neg; stloc` — which is exactly what the
    // host's own kind-24 arm writes, since it reaches the unary owner rather than an adoption pass.
    initializerPlan := new ColumnarCodePlan()
    initializerNodes := MethodBodyFactsTwoCompositeBody("n", "-", "19", "~", "3")
    assert MethodBodyFactsPlanBody(initializerNodes, "n-19~3", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), initializerPlan)
    assert initializerPlan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert initializerPlan.OpCodeValues[1] == ColumnarCodePlanContract.Neg()
    assert initializerPlan.OpCodeValues[2] == ColumnarCodePlanContract.Stloc()
}

// ---- BLOCK 31c — 015-B11: THE ADOPTED SET IS NOW THE PRE-PASS'S OWN, NOT THE WHOLE SHAPE ----
//
// `015-B5`..`015-B10` refused every `-<int literal>` return because a SUBSET of what
// `TryEmitIntLiteralAsType` adopts is a silent divergence while a SUPERSET is only a narrowing. That
// asymmetry still governs; what this block pins is that the superset is now TIGHT, and that every
// disagreement between the host's spelling and N#'s falls on the REFUSING side.
test "the adopted-return predicate reproduces the pre-pass's suffix test" {
    // UNSUFFIXED AND IN RANGE — the host adopts, so the door must keep refusing.
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5"), "-5", 2)
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "1"), "-1", 2)
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "2147483647"), "-2147483647", 2)

    // A SUFFIX — the host's own test is `text[^1] is 'u' or 'U' or 'l' or 'L' or 'm' or 'M'`, the LAST
    // character only, so `5UL` and `5LU` both fall out of the adopted set through it. The pre-pass
    // declines and the host emits ordinarily, which is the unary owner — the same owner the door
    // enters — so the door may claim these.
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5L"), "-5L", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5l"), "-5l", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5U"), "-5U", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5u"), "-5u", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5UL"), "-5UL", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5LU"), "-5LU", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5m"), "-5m", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "5M"), "-5M", 2)
}

test "the adopted-return predicate caps at int.MaxValue and every parse disagreement refuses" {
    // ⚠ THE ONE MAGNITUDE THE RANGE HALF BUYS. `ColumnarUnaryLiteralPlanner.TryAppendMinimumMagnitude`
    // claims exactly `2147483648`, emitting it PRE-NEGATED with no `neg`; the pre-pass declines it
    // (`2147483648 > int.MaxValue`) and falls through to that same owner. Nothing else between the two
    // owners is both claimable here and unadopted there.
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "2147483648"), "-2147483648", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "4000000000"), "-4000000000", 2)

    // THE CEILING IS FIXED AT int.MaxValue AND NO RETURN TYPE IS THREADED, WHICH IS A PROOF RATHER
    // THAN A SIMPLIFICATION: the pre-pass's ceiling is sbyte.MaxValue / short.MaxValue / int.MaxValue
    // by target and its four unsigned targets adopt nothing, so int.MaxValue is a superset for every
    // target — and the door's own equality rule means `int` is the only target that can ever reach
    // this predicate's answer.
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "127"), "-127", 2)
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "128"), "-128", 2)
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "32768"), "-32768", 2)

    // THE PARSE DIMENSION. `ulong.TryParse` rejects hex/binary/octal/underscored texts;
    // `NumericLiteralFacts.TryParseUnsignedIntegerMagnitude` accepts all four. Each therefore parses
    // HERE, compares in range and REFUSES — a claim given up, never a byte changed.
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "0x10"), "-0x10", 2)
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "0b101"), "-0b101", 2)
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "1_000"), "-1_000", 2)

    // A text neither parser can read is an UNPROVEN decline, and an unproven decline is not a decline.
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 0, "99999999999999999999999"), "-99999999999999999999999", 2)

    // The non-adopted operators and the float child are unchanged by the narrowing.
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("-", 1, "2.5"), "-2.5", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnaryBody("~", 0, "3"), "~3", 2)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsLiteralBody(0, "5"), "5", 2)
}

// ⚠ AN UNREADABLE SPAN REFUSES RATHER THAN CRASHING, AND THAT OBLIGATION IS NEW.
// `ColumnarNodeTable.Text` is a bare `source.Substring(valueStarts[i], valueLengths[i])`, so a
// literal node carrying no span throws out of the compiler instead of declining. Until 015-B11 this
// predicate never read the OPERAND's text and had no such exposure; the host's own
// `ValueStart(node) < 0 → return false` guard became this predicate's obligation the moment it
// started to. The block is its own so a control can isolate the guard from the two range tests.
test "the adopted-return predicate refuses a literal operand that carries no span" {
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(MethodBodyFactsUnarySpanlessOperand("-"), "-", 2)
}

test "the door now claims the minimum-magnitude return the pre-pass declines" {
    // END TO END, not merely through the predicate: `{ return -2147483648 }` on an `int` function
    // plans to `ldc.i4 -2147483648; neg; ret`, which is exactly what the host's ordinary unary arm
    // writes for the value its adoption pre-pass refuses — `EmitExpressionCore` reaches THIS owner
    // ahead of every other route, so the claim is byte-identical by construction.
    //
    // ⚠ THE `neg` IS NOT A ROUNDING ERROR AND THE POOL VALUE IS NOT A TYPO. `2147483648` cannot be
    // loaded as an `int` at all, so `TryAppendMinimumMagnitude` pools the ALREADY-NEGATED
    // `-2147483648` and lets the operator's own `neg` run over it; two's complement negation maps
    // `int.MinValue` to itself, so the pair is exact. That is the owner's existing spelling, and this
    // block pins it rather than changing it.
    plan := new ColumnarCodePlan()
    nodes := MethodBodyFactsUnaryBody("-", 0, "2147483648")
    assert MethodBodyFactsPlanBody(nodes, "-2147483648", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), plan)
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Neg()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()
    assert plan.Int32Count == 1
    assert plan.Int32Values[0] == -2147483648

    method := MethodBodyFactsDynamicMethod("NSharpB11MinMagnitudeReturn", typeof(int))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsNoArguments())) == -2147483648

    // And the in-range sibling is STILL refused, so the narrowing did not open the shape the diff
    // caught.
    refused := new ColumnarCodePlan()
    refusedNodes := MethodBodyFactsUnaryBody("-", 0, "5")
    assert !MethodBodyFactsPlanBody(refusedNodes, "-5", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), refused)
}

// ---- BLOCK 32 — THE SECOND COMPOSITE ARM ----
//
// `nameof` is the other owner whose gate the emitter reaches through its OWN facade ahead of the value
// cascade, so its claim is byte-identical against a single owner. Its gate demands an open fragment as
// well as the right schema, and the door's root fragment is what supplies one.
test "the door claims a nameof composite on a method body and refuses an unnamed target" {
    plan := new ColumnarCodePlan()
    nodes := MethodBodyFactsNameOfBody("total", ColumnarExpressionNodeKind.IdentifierExpression())
    assert MethodBodyFactsPlanBody(nodes, "total", typeof(string), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), plan)

    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert plan.StringCount == 1
    assert plan.StringValues[0] == "total"
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()
    assert plan.FragmentCount == 1

    method := MethodBodyFactsDynamicMethod("NSharpB6NameOfBody", typeof(string))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToString(method.Invoke(target, MethodBodyFactsNoArguments()), CultureInfo.InvariantCulture) == "total"

    // A `nameof` whose target is a literal is not a name at all — declined, plan untouched.
    declined := new ColumnarCodePlan()
    declined.PrepareMethodBody()
    declinedNodes := MethodBodyFactsNameOfBody("7", 0)
    declinedType := typeof(string)
    assert !ColumnarMethodBodyPlanner.TryAppendReturnValue(declinedNodes, "7", 2, MethodBodyFactsEmptyBindings(), declined, out declinedType)
    assert declined.OperationCount == 0
    assert declined.FragmentCount == 0
}

// ---- BLOCK 33 — THE FRAGMENT DECISION ----
//
// A method body is a sequence of INDEPENDENT expression trees, so its plan admits a NEW ROOT fragment
// per tree; the recursive expression schemas still admit exactly one. The relaxation is narrow on
// purpose: a new root is admitted only BETWEEN trees. With a fragment still open, a second root is the
// same error it always was, so nothing inside one tree changed.
test "a method-body plan admits many root fragments and the recursive schemas admit exactly one" {
    body := new ColumnarCodePlan()
    body.PrepareMethodBody()
    first := body.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    assert first == 0
    body.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    body.CompleteFragment(first, typeof(int))

    second := body.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    assert second == 1
    assert body.FragmentParentIndices[1] == -1
    body.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    body.CompleteFragment(second, typeof(int))
    assert body.FragmentCount == 2

    // With a fragment OPEN, a second root is still refused on the method-body schema — the relaxation
    // is between trees, never inside one.
    nested := new ColumnarCodePlan()
    nested.PrepareMethodBody()
    nested.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    assert throws InvalidOperationException {
        nested.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    }

    // The scalar expression schema keeps the single-root rule exactly as it was.
    scalar := new ColumnarCodePlan()
    scalar.PrepareV3()
    scalarRoot := scalar.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    scalar.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    scalar.CompleteFragment(scalarRoot, typeof(int))
    assert throws InvalidOperationException {
        scalar.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    }

    // And so does the recursive schema.
    recursive := new ColumnarCodePlan()
    recursive.PrepareV2()
    recursiveRoot := recursive.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    recursive.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
    recursive.CompleteFragment(recursiveRoot, typeof(int))
    assert throws InvalidOperationException {
        recursive.BeginFragment(-1, ColumnarExpressionNodeKind.IntLiteralExpression(), 0)
    }
}

// ---- BLOCK 34 — THE STATEMENT LOOP'S SMALLEST BODY ----
//
// `x := 5; return x` is the first body whose RETURN reads a name the DRIVER created. Four rows, one
// plan local, and the executor turns that pool entry into a real slot before the first row replays.
test "the statement loop claims a declaration and the return that reads it" {
    plan := new ColumnarCodePlan()
    nodes := MethodBodyFactsDeclareThenReturnBody("x", 0, "5")
    assert MethodBodyFactsPlanBody(nodes, "x5", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), plan)

    assert plan.OperationCount == 4
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Stloc()
    assert plan.OperandKinds[1] == ColumnarCodePlanContract.PlanLocalOperand()
    assert plan.OperandIndices[1] == 0
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    assert plan.OperandKinds[2] == ColumnarCodePlanContract.PlanLocalOperand()
    assert plan.OperandIndices[2] == 0
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ret()

    // ONE plan local, of the initializer's inferred type. No ambient local is touched — the driver has
    // no `ILGenerator` with which to make one.
    assert plan.PlanLocalCount == 1
    assert plan.AmbientLocalCount == 0
    assert plan.Types[plan.PlanLocalTypeIndices[0]] == typeof(int)

    method := MethodBodyFactsDynamicMethod("NSharpB6DeclareBody", typeof(int))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsNoArguments())) == 5

    // A string initializer takes the same two-row declaration through a different literal.
    stringPlan := new ColumnarCodePlan()
    stringNodes := MethodBodyFactsDeclareThenReturnBody("s", 3, "\"hi\"")
    assert MethodBodyFactsPlanBody(stringNodes, "s\"hi\"", typeof(string), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), stringPlan)
    assert stringPlan.PlanLocalCount == 1
    assert stringPlan.Types[stringPlan.PlanLocalTypeIndices[0]] == typeof(string)
    stringMethod := MethodBodyFactsDynamicMethod("NSharpB6DeclareStringBody", typeof(string))
    ColumnarCodePlanExecutor.Execute(stringPlan, stringMethod.GetILGenerator())
    stringTarget: object? = null
    assert Convert.ToString(stringMethod.Invoke(stringTarget, MethodBodyFactsNoArguments()), CultureInfo.InvariantCulture) == "hi"
}

// ---- BLOCK 35 — A LATER STATEMENT CONSUMES WHAT AN EARLIER ONE PUBLISHED ----
//
// One declaration proves the plumbing; a CHAIN proves the loop. `b := a` resolves `a` through the sole
// identifier owner's new plan-local tier, so the published binding is doing real work rather than
// merely existing.
test "the statement loop publishes bindings that later statements read" {
    plan := new ColumnarCodePlan()
    nodes := MethodBodyFactsDeclareChainBody("a", "b", "7")
    assert MethodBodyFactsPlanBody(nodes, "ab7", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), plan)

    assert plan.OperationCount == 6
    assert plan.PlanLocalCount == 2
    assert plan.OperandIndices[1] == 0
    assert plan.OperandIndices[2] == 0
    assert plan.OperandIndices[3] == 1
    assert plan.OperandIndices[4] == 1
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.Ret()

    method := MethodBodyFactsDynamicMethod("NSharpB6DeclareChainBody", typeof(int))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsNoArguments())) == 7
}

// ---- BLOCK 36 — TWO COMPOSITE STATEMENTS, TWO ROOT FRAGMENTS, ONE BODY ----
//
// This is where the loop and the fragment relaxation meet. Before this slice the SECOND composite
// statement threw "A recursive code-plan fragment must be nested under the current open fragment" out
// of the compiler; now each expression tree gets its own root.
test "the statement loop claims two composite statements in one method body" {
    plan := new ColumnarCodePlan()
    nodes := MethodBodyFactsTwoCompositeBody("n", "-", "4", "~", "9")
    assert MethodBodyFactsPlanBody(nodes, "n-4~9", typeof(int), false, MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), plan)

    // FOUR roots-and-operands: the declaration's unary root plus its operand, and the return's.
    assert plan.FragmentCount == 4
    assert plan.FragmentParentIndices[0] == -1
    assert plan.FragmentParentIndices[1] == 0
    assert plan.FragmentParentIndices[2] == -1
    assert plan.FragmentParentIndices[3] == 2
    assert plan.OpenFragmentCount == 0
    assert plan.OperationCount == 6

    method := MethodBodyFactsDynamicMethod("NSharpB6TwoCompositeBody", typeof(int))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsNoArguments())) == -10
}

// ---- BLOCK 37 — THE DECLARATION REFUSES WHAT THE HOST REFUSES ----
//
// The host's kind-24 arm declines a name the body can already see (the pipeline's NL316) and an
// initializer whose inferred type is off the supported surface. The driver must decline in exactly
// those cases, because a claim there would be a body whose bytes it cannot promise.
test "the statement loop refuses a shadowing declaration and an unclaimable local type" {
    // `p` is a PARAMETER. Re-binding it is a diagnostic, not a lowering.
    shadowPlan := new ColumnarCodePlan()
    shadowNodes := MethodBodyFactsDeclareThenReturnBody("p", 0, "5")
    assert !MethodBodyFactsPlanBody(shadowNodes, "p5", typeof(int), false, MethodBodyFactsOrdinals("p", 0), MethodBodyFactsTypes("p", typeof(int)), MethodBodyFactsLocals(), shadowPlan)

    // A name an ENCLOSING body binds is equally visible, and the emitter's own visibility test says so.
    enclosing := MethodBodyFactsEmptyBindings()
    assert !enclosing.IsVisibleBindingName("q")
    outerNames := new string[](1)
    outerNames[0] = "q"
    enclosingBound := ColumnarFragmentBindings.FromRawFacts(MethodBodyFactsNoOrdinals(), MethodBodyFactsNoTypes(), MethodBodyFactsLocals(), new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal), new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal), null, null, new ColumnarStructDef[](0), new ColumnarUnionDef[](0), new Dictionary<string, string[]>(StringComparer.Ordinal), outerNames, new string[](0), new string[](0), new Dictionary<string, Type>(StringComparer.Ordinal), null)
    assert enclosingBound.IsVisibleBindingName("q")

    // The type gate is the host's, in the host's order: an open generic parameter and an array of one
    // are admitted.
    //
    // ⚠ THE BY-REF AND POINTER ROWS BELOW PASS EVEN WITHOUT THEIR GUARD, AND A CONTROL PROVED IT. The
    // guard exists for the `SymbolType` defect — a BUILDER pointer or by-ref reports `IsSZArray` TRUE,
    // so `T*` and `T&` over a builder generic parameter would take the array arm and be claimed. The
    // estate can only hand this function RUNTIME types, and for those `ColumnarTypeOfPlanner.IsSupportedType`
    // already refuses by-ref and pointer on its own, so removing the guard changes NO answer any block
    // here can ask. These two rows therefore pin the ANSWER and not the guard; the guard's own reason
    // is written where it lives, and it is the same builder-only landmine `IsSupportedType` documents.
    assert ColumnarMethodBodyPlanner.IsClaimedLocalType(typeof(int))
    assert ColumnarMethodBodyPlanner.IsClaimedLocalType(typeof(string))
    assert ColumnarMethodBodyPlanner.IsClaimedLocalType(typeof(int[]))
    assert !ColumnarMethodBodyPlanner.IsClaimedLocalType(typeof(int).MakeByRefType())
    assert !ColumnarMethodBodyPlanner.IsClaimedLocalType(typeof(int).MakePointerType())
    assert !ColumnarMethodBodyPlanner.IsClaimedLocalType(MethodBodyFactsVoidType())
    assert !ColumnarMethodBodyPlanner.IsClaimedLocalType(typeof(Dictionary<string, int>).GetGenericTypeDefinition())
}

// ---- BLOCK 38 — THE PLAN-LOCAL SELECTION TIER ----
//
// `Locals` names an AMBIENT `LocalBuilder` the emitter already made; `PlanLocals` names a slot the plan
// owns. They are different storage tiers, so they are different selection kinds — folding the plan's
// pool index into `Ordinal` (an ARGUMENT ordinal) is how a wrong slot becomes a silent read.
test "a plan-declared local resolves as its own selection tier and refuses every overlap" {
    bindings := MethodBodyFactsEmptyBindings()
    bindings.DeclarePlanLocal("v", 3, typeof(long))
    assert bindings.PlanLocals.ContainsKey("v")
    assert bindings.IsVisibleBindingName("v")
    assert bindings.IsValueBinding("v")

    nodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IdentifierExpression(), "v")
    selection := ColumnarBoundIdentifierPlanner.EmptySelection()
    assert ColumnarBoundIdentifierPlanner.TryResolve(nodes, "v", 2, bindings, out selection)
    assert selection.Kind == ColumnarBoundIdentifierKind.PlanLocal
    assert selection.PlanLocalIndex == 3
    assert selection.Ordinal == -1
    assert selection.ResultType == typeof(long)
    assert ColumnarMethodBodyPlanner.IsClaimedIdentifierSelection(selection.Kind)

    // Publishing over a visible name is a DRIVER defect, so it throws rather than shadowing.
    assert throws InvalidOperationException {
        bindings.DeclarePlanLocal("v", 4, typeof(int))
    }

    // And so is a plan local that overlaps another live tier, which only a route around
    // `DeclarePlanLocal` could produce.
    overlapping := MethodBodyFactsEmptyBindings()
    overlapping.PlanLocals["p"] = (Index: 0, ValueType: typeof(int))
    overlapping.ParameterOrdinals["p"] = 0
    overlapping.ParameterTypes["p"] = typeof(int)
    overlapNodes := MethodBodyFactsLiteralBody(ColumnarExpressionNodeKind.IdentifierExpression(), "p")
    overlapSelection := ColumnarBoundIdentifierPlanner.EmptySelection()
    assert throws InvalidOperationException {
        ColumnarBoundIdentifierPlanner.TryResolve(overlapNodes, "p", 2, overlapping, out overlapSelection)
    }
}

// ---- 015-B7 SHARED FIXTURES — THE DIRECT-CALL COMPOSITE ----
//
// The call subtrees are built on the DIRECT-CALL owner's OWN fixture builder rather than on a second
// hand-rolled node layout, so the shape these blocks plan is the exact shape that owner's contract
// file already plans. Only the block/return/declaration wrapper above the call is new here.

func MethodBodyFactsNoSiblings(): Dictionary<string, ColumnarSiblingCallFacts> {
    return new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal)
}

func MethodBodyFactsSiblings(name: string, facts: ColumnarSiblingCallFacts): Dictionary<string, ColumnarSiblingCallFacts> {
    result := new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal)
    result[name] = facts
    return result
}

func MethodBodyFactsSiblings2(firstName: string, firstFacts: ColumnarSiblingCallFacts, secondName: string, secondFacts: ColumnarSiblingCallFacts): Dictionary<string, ColumnarSiblingCallFacts> {
    result := new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal)
    result[firstName] = firstFacts
    result[secondName] = secondFacts
    return result
}

// `{ return <Owner>.<Member>(<literal>) }`, or with a non-empty `localName`,
// `{ <localName> := <Owner>.<Member>(<literal>)  return <localName> }`. The local's token is added to
// the source FIRST so the identifier read and the declaration share one span.
func MethodBodyFactsQualifiedCallBody(ownerName: string, memberName: string, argumentText: string, argumentKind: int, localName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := builder.AddToken(localName)
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), ownerName)
    member := DirectCallAppendMember(builder, owner, memberName)
    argument := builder.AddLeaf(argumentKind, argumentText)
    call := DirectCallAppendCall(builder, member, DirectCallOneArgument(argument))
    return MethodBodyFactsWrapValueInBody(builder, call, nameStart, localName)
}

// `{ return <Member>(<name>) }` — a bare call whose ONE argument is a bare identifier. The shape the
// plan-local refusal is about, in the position where the crash was found.
func MethodBodyFactsIdentifierCallBody(memberName: string, argumentName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    callee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), memberName)
    argument := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), argumentName)
    call := DirectCallAppendCall(builder, callee, DirectCallOneArgument(argument))
    return MethodBodyFactsWrapValueInBody(builder, call, 0, "")
}

// `{ <name> := <initMember>()  return <returnMember>(<name>) }` — the exact body the `015-B7` claim-class
// corpus CRASHED on, and the body `015-B8`'s scratch-plan mirror makes claimable. The two member names
// differ because `SiblingCallables` is keyed by name and the two calls have different arities.
func MethodBodyFactsDeclareThenCallReturnBody(initMember: string, returnMember: string, localName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := builder.AddToken(localName)
    initCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), initMember)
    initCall := DirectCallAppendCall(builder, initCallee, DirectCallNoArguments())
    declaration := builder.AddNode(24, nameStart, localName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(initCall))
    returnCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), returnMember)
    argument := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), nameStart, localName.Length, nameStart, localName.Length, new int[](0))
    returnCall := DirectCallAppendCall(builder, returnCallee, DirectCallOneArgument(argument))
    statement := builder.AddNode(20, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(returnCall))
    return builder.Build(builder.AddNode(25, -1, 0, 0, builder.Source.Length, MethodBodyFactsInts2(declaration, statement)))
}

// The same shape with TWO declarations, only the SECOND of which the returned call reads. It is the
// body that exercises the mirror's all-used exemption: the scratch that types the argument carries both
// slots as vocabulary and references exactly one of them.
func MethodBodyFactsTwoDeclareThenCallReturnBody(initMember: string, returnMember: string, first: string, second: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    firstStart := builder.AddToken(first)
    secondStart := builder.AddToken(second)
    firstCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), initMember)
    firstCall := DirectCallAppendCall(builder, firstCallee, DirectCallNoArguments())
    firstDeclaration := builder.AddNode(24, firstStart, first.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(firstCall))
    secondCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), initMember)
    secondCall := DirectCallAppendCall(builder, secondCallee, DirectCallNoArguments())
    secondDeclaration := builder.AddNode(24, secondStart, second.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(secondCall))
    returnCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), returnMember)
    argument := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), secondStart, second.Length, secondStart, second.Length, new int[](0))
    returnCall := DirectCallAppendCall(builder, returnCallee, DirectCallOneArgument(argument))
    statement := builder.AddNode(20, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(returnCall))
    return builder.Build(builder.AddNode(25, -1, 0, 0, builder.Source.Length, MethodBodyFactsInts3(firstDeclaration, secondDeclaration, statement)))
}

// The same qualified shape with NO arguments, which is what a void member needs.
func MethodBodyFactsQualifiedCallBodyNoArguments(ownerName: string, memberName: string, localName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := builder.AddToken(localName)
    owner := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), ownerName)
    member := DirectCallAppendMember(builder, owner, memberName)
    call := DirectCallAppendCall(builder, member, DirectCallNoArguments())
    return MethodBodyFactsWrapValueInBody(builder, call, nameStart, localName)
}

// `{ return <Member>() }`, or the declaration form — a BARE callee, which is the shape the routed
// sibling map decides.
func MethodBodyFactsBareCallBody(memberName: string, localName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := builder.AddToken(localName)
    callee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), memberName)
    call := DirectCallAppendCall(builder, callee, DirectCallNoArguments())
    return MethodBodyFactsWrapValueInBody(builder, call, nameStart, localName)
}

// The block/return wrapper the two builders above share. An empty `localName` selects the RETURN
// position; a non-empty one selects the `:=` INITIALIZER position with a return that reads it back.
func MethodBodyFactsWrapValueInBody(builder: ColumnarRangePlannerNodeBuilder, value: int, nameStart: int, localName: string): ColumnarRangePlannerTestTree {
    if localName.Length == 0 {
        statement := builder.AddNode(20, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(value))
        return builder.Build(builder.AddNode(25, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(statement)))
    }

    declaration := builder.AddNode(24, nameStart, localName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(value))
    read := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), nameStart, localName.Length, nameStart, localName.Length, new int[](0))
    statement := builder.AddNode(20, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(read))
    return builder.Build(builder.AddNode(25, -1, 0, 0, builder.Source.Length, MethodBodyFactsInts2(declaration, statement)))
}

// The driver over a builder-made tree, whose body root is the LAST node rather than node 0, plus the
// two routed facts a call body can actually observe. `ExactSourceTypes` stays empty and the overflow
// flag stays `false` — the first has no consumer on the claimed surface and the second is provably
// `false` at every `EmitBody` entry, and both are stated rather than quietly defaulted.
func MethodBodyFactsPlanCallBody(tree: ColumnarRangePlannerTestTree, returnType: Type, sourceTypeDefinitions: ColumnarStructDef[], siblingCallables: Dictionary<string, ColumnarSiblingCallFacts>, plan: ColumnarCodePlan): bool {
    return ColumnarMethodBodyPlanner.TryPlanBody(
        tree.Nodes,
        tree.Source,
        tree.Root,
        returnType,
        false,
        MethodBodyFactsNoOrdinals(),
        MethodBodyFactsNoTypes(),
        MethodBodyFactsLocals(),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal),
        null,
        null,
        null,
        sourceTypeDefinitions,
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        new string[](0),
        new string[](0),
        new string[](0),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        false,
        siblingCallables,
        plan,
        null
    )
}

func MethodBodyFactsNoSourceTypes(): ColumnarStructDef[] {
    return new ColumnarStructDef[](0)
}

// ---- BLOCK 40 — THE DIRECT-CALL COMPOSITE IN RETURN POSITION (class C) ----
//
// The first claimed kind whose owner reaches the CASCADE rather than a pre-cascade facade:
// `EmitExpressionCore` offers boolean, unary-literal, scalar-literal and `nameof` first — none has a
// call arm — and then `ColumnarRangeIndexPlanner.TryEmitFromFacts` answers `FacadeRootMayNeedFacts`
// TRUE for kind 9, declines the construction owner (15/36/58 only) and hands the node to
// `ColumnarDirectCallPlanner`. So the door calling that owner's own `TryAppendRoot` is byte-identity
// BY CONSTRUCTION, and the rows below are the owner's rows plus the driver's `ret`.
test "the door claims a direct call as a return value and executes it" {
    tree := MethodBodyFactsQualifiedCallBody("Type", "GetType", "\"System.String\"", ColumnarExpressionNodeKind.StringLiteralExpression(), "")
    ExternalStampScope(tree, "import System")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(Type), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    assert plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()
    assert plan.Methods[plan.OperandIndices[1]].get_Name() == "GetType"
    assert plan.MethodDeclaringTypes[plan.OperandIndices[1]] == typeof(Type)
    assert plan.OpenFragmentCount == 0
    assert plan.FragmentParentIndices[0] == -1

    method := MethodBodyFactsDynamicMethod("NSharpB7CallReturnBody", typeof(Type))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Object.ReferenceEquals(method.Invoke(target, MethodBodyFactsNoArguments()), typeof(string))
}

// ---- BLOCK 41 — THE SAME CALL AS A DECLARATION INITIALIZER (class DC) ----
//
// Two claim classes, not one, because `015-B6` proved the RETURN position is not the VALUE position:
// the host's kind-20 arm runs seven target-typed pre-passes and its kind-24 arm runs none. All six
// kind-gated pre-passes exclude kind 9 (15/36/42, 42, 0-after-an-optional-minus, 58, 58, 5), so the
// two positions agree for a call — which is a fact worth ASSERTING at both ends rather than assuming,
// since the unary class does not have it.
test "the door claims a direct call as a declaration initializer and the return reads the plan local" {
    tree := MethodBodyFactsQualifiedCallBody("Type", "GetType", "\"System.String\"", ColumnarExpressionNodeKind.StringLiteralExpression(), "resolved")
    ExternalStampScope(tree, "import System")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(Type), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    assert plan.OperationCount == 5
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Stloc()
    assert plan.OperandKinds[2] == ColumnarCodePlanContract.PlanLocalOperand()
    assert plan.OperandIndices[2] == 0
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ldloc()
    assert plan.OperandIndices[3] == 0
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.Ret()

    // The plan local carries the CALL's return type, which is what makes the initializer position a
    // real consumer of the owner's result rather than a shape that merely parses.
    assert plan.PlanLocalCount == 1
    assert plan.AmbientLocalCount == 0
    assert plan.Types[plan.PlanLocalTypeIndices[0]] == typeof(Type)

    method := MethodBodyFactsDynamicMethod("NSharpB7CallDeclaredBody", typeof(Type))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Object.ReferenceEquals(method.Invoke(target, MethodBodyFactsNoArguments()), typeof(string))
}

// ---- BLOCK 42 — THE ROUTED SIBLING MAP IS A BRANCH SELECTOR, NOT A CONVENIENCE ----
//
// `015-B5` and `015-B6` deliberately left `SiblingCallables` unrouted and recorded that it becomes
// mandatory when a COMPOSITE is claimed. This is the block that makes that claim falsifiable: the SAME
// body is claimed with the map routed and DECLINED with an empty one, because
// `ColumnarDirectCallPlanner:222` routes a bare name to the sibling arm on exactly this fact and
// `:170` bails out of the whole call when no tier answers. A driver that forgot to route it would not
// crash — it would silently emit a different body — which is why the pin is a claim/decline pair.
test "the routed sibling map decides a bare call and an empty map declines it" {
    facts := DirectCallSiblingFacts("MethodBodyFactsSiblingHost", "Ping", new Type[](0), typeof(int))
    tree := MethodBodyFactsBareCallBody("Ping", "")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsSiblings("Ping", facts), plan)
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()
    assert plan.Methods[plan.OperandIndices[0]].get_Name() == "Ping"

    empty := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(tree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), empty)

    // The same asymmetry in the INITIALIZER position, so the routing is not accidentally return-only.
    declaredTree := MethodBodyFactsBareCallBody("Ping", "n")
    declared := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(declaredTree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsSiblings("Ping", facts), declared)
    assert declared.PlanLocalCount == 1
    assert declared.Types[declared.PlanLocalTypeIndices[0]] == typeof(int)
    declaredEmpty := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(declaredTree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), declaredEmpty)
}

// ---- BLOCK 43 — ⚠ A VOID CALL DECLINES INSTEAD OF LEAVING THE COMPILER ----
//
// THIS IS THE HAZARD THE `015-B6` OWNERS DID NOT HAVE, AND IT IS A THROW RATHER THAN A WRONG BYTE.
// `CompleteFragment` admits a `System.Void` result only on a schema-v3 ROOT fragment — exactly what
// `ColumnarDirectCallPlanner.Plan` always hands it, which is how a statement-position `foo()` is
// planned today. A METHOD BODY is neither v3 nor necessarily fragment 0, so `x := SomeVoidCall()` — a
// shape the parser produces and the host declines at its own supported-type gate — would have left the
// compiler through "Only a schema-v3 root code-plan fragment can declare a void result."
//
// The unary owner's result is bounded by its own syntax and `nameof`'s is always `string`; the call
// owner is the first whose result type its syntax does not bound. Both halves are asserted: the v3
// route still completes a void root, and the method-body route DECLINES with the plan rolled back.
test "a void direct call declines on a method body and still completes a schema-v3 root" {
    owner := SourceCallDefinition("MethodBodyFactsVoidCallOwner", true)
    _reset := SourceCallPublicStatic(owner, "Reset", new Type[](0), MethodBodyFactsVoidType())
    voidTree := DirectCallQualifiedTree("MethodBodyFactsVoidCallOwner", "Reset", DirectCallEmptyTexts(), DirectCallEmptyKinds())

    // v3 — unchanged, and the assertion is what makes the guard's narrowness checkable.
    v3 := DirectCallPlan(voidTree, DirectCallSingleDefinitionBindings(owner))
    assert v3.ResultType != null
    assert v3.ResultType.FullName == "System.Void"
    assert v3.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()

    // A method body — the same append, the same owner, and a DECLINE with nothing left behind.
    body := new ColumnarCodePlan()
    body.PrepareMethodBody()
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := false
    voidResult := typeof(int)
    assert !ColumnarDirectCallPlanner.TryAppendRoot(voidTree.Nodes, voidTree.Source, voidTree.Root, DirectCallSingleDefinitionBindings(owner), body, out ownership, out legacyWholeSubtreePlanning, out voidResult)
    assert body.OperationCount == 0
    assert body.FragmentCount == 0
    assert body.OpenFragmentCount == 0

    // And through the DOOR, which is the route a user body actually takes.
    declaredTree := MethodBodyFactsQualifiedCallBodyNoArguments("MethodBodyFactsVoidCallOwner", "Reset", "ignored")
    declaredPlan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(declaredTree, typeof(int), SourceCallDefinitions(owner), MethodBodyFactsNoSiblings(), declaredPlan)
}

// ---- BLOCK 44 — THE ROOT SEQUENCE IS ONE COPY, NOT TWO ----
//
// `TryAppendRoot` was FACTORED OUT of `Plan` rather than written beside it, and that is the whole
// byte-identity argument: if the door had grown its own checkpoint/fragment/append/complete sequence,
// the two would agree only as long as someone kept them agreeing. The same call planned both ways
// produces the same rows, in the same order, resolving the SAME `MethodInfo`.
test "the direct-call root sequence produces the same rows through Plan and through the door" {
    tree := DirectCallQualifiedTree("Type", "GetType", DirectCallOneText("\"System.String\""), DirectCallOneKind(ColumnarExpressionNodeKind.StringLiteralExpression()))
    ExternalStampScope(tree, "import System")

    viaPlan := DirectCallPlan(tree, ColumnarRangePlannerEmptyBindings())

    viaDoor := new ColumnarCodePlan()
    viaDoor.PrepareMethodBody()
    ownership := ColumnarDirectCallOwnership.NotOwned
    legacyWholeSubtreePlanning := false
    doorResult := typeof(int)
    assert ColumnarDirectCallPlanner.TryAppendRoot(tree.Nodes, tree.Source, tree.Root, ColumnarRangePlannerEmptyBindings(), viaDoor, out ownership, out legacyWholeSubtreePlanning, out doorResult)

    assert doorResult == viaPlan.ResultType
    assert viaDoor.OperationCount == viaPlan.OperationCount
    row := 0
    while row < viaPlan.OperationCount {
        assert viaDoor.OpCodeValues[row] == viaPlan.OpCodeValues[row]
        assert viaDoor.OperandKinds[row] == viaPlan.OperandKinds[row]
        row = row + 1
    }

    assert Object.ReferenceEquals(viaDoor.Methods[viaDoor.OperandIndices[1]], viaPlan.Methods[viaPlan.OperandIndices[1]])

    // The two differ in exactly one place, and it is the wrapper rather than the sequence: `Plan`
    // SEALS a v3 expression, the door leaves the body open for the statements after it.
    assert viaPlan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
    assert viaDoor.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    assert viaDoor.OpenFragmentCount == 0
}

// ---- BLOCK 45 — ⚠ THE SHAPE `015-B7` DECLINED WHOLE, NOW CLAIMED (015-B8) ----
//
// `n := Ping()` followed by `return Take(n)` is the body the `015-B7` claim-class corpus CRASHED the
// compiler on — `Build failed: The opcode does not use this plan-local entry.` The direct-call owner
// types each argument by planning it into a FRESH schema-v3 scratch plan, and that plan's local pool was
// empty, so `ldloc <the body's pool index>` had no index to name. `015-B7` refused the whole body;
// `015-B8` gives the scratch the body's local VOCABULARY instead, and the shape claims.
//
// The rows are the proof that nothing about the CLAIM changed shape: the declaration's call, its store,
// the read, the returned call, the `ret`. And the door's own plan is STORAGE, never a mirror — the
// mirror lives and dies inside the owner's scratch.
test "the door claims a declaration whose local is read inside the returned call" {
    initFacts := DirectCallSiblingFacts("MethodBodyFactsPlanLocalHost", "Ping", new Type[](0), typeof(int))
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    takeFacts := DirectCallSiblingFacts("MethodBodyFactsPlanLocalHost", "Take", oneInt, typeof(int))
    siblings := MethodBodyFactsSiblings2("Ping", initFacts, "Take", takeFacts)

    inside := MethodBodyFactsDeclareThenCallReturnBody("Ping", "Take", "n")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(inside, typeof(int), MethodBodyFactsNoSourceTypes(), siblings, plan)

    assert plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    assert plan.OperationCount == 5
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Stloc()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.Ret()
    assert plan.Methods[plan.OperandIndices[0]].get_Name() == "Ping"
    assert plan.Methods[plan.OperandIndices[3]].get_Name() == "Take"

    // The BODY's pool is storage. A mirror is the scratch's business alone, and a plan that carried one
    // could not be replayed at all.
    assert plan.PlanLocalCount == 1
    assert !plan.PlanLocalIsMirror[0]
    assert !plan.HasPlanLocalMirror()
    assert plan.OpenFragmentCount == 0
}

// ---- BLOCK 46 — THE MULTI-LOCAL BODY, WHICH IS THE ALL-USED EXEMPTION END TO END ----
//
// Two declarations and a return whose call reads only the SECOND. The scratch that types that argument
// carries BOTH slots as vocabulary and references exactly one, so the body cannot be claimed unless the
// pool's all-used rule distinguishes a mirror from a dead entry. It is the corner the `015-B7` record
// predicted would block a mirror — and, per the `015-B8` decode, the ONLY corner that rule blocks, since
// a single-local body's scratch satisfies all-used with its one read and dies on definite assignment
// instead.
test "the door claims two declarations when the returned call reads only the second" {
    initFacts := DirectCallSiblingFacts("MethodBodyFactsTwoLocalHost", "Ping", new Type[](0), typeof(int))
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    takeFacts := DirectCallSiblingFacts("MethodBodyFactsTwoLocalHost", "Take", oneInt, typeof(int))
    siblings := MethodBodyFactsSiblings2("Ping", initFacts, "Take", takeFacts)

    body := MethodBodyFactsTwoDeclareThenCallReturnBody("Ping", "Take", "p", "q")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(body, typeof(int), MethodBodyFactsNoSourceTypes(), siblings, plan)

    assert plan.PlanLocalCount == 2
    assert plan.OperationCount == 7
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Stloc()
    assert plan.OperandIndices[1] == 0
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Stloc()
    assert plan.OperandIndices[3] == 1
    // The read is of the SECOND slot, and the first is never read by the body at all.
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.Ldloc()
    assert plan.OperandIndices[4] == 1
    assert plan.OpCodeValues[6] == ColumnarCodePlanContract.Ret()
}

// ---- BLOCK 47 — THE VOCABULARY ITSELF: INDEXED BY POOL INDEX, AND EMPTY OFF THE DOOR'S PATH ----
//
// `ColumnarFragmentBindings.PlanLocalMirrorTypes` is what every scratch site arms its plan with. Two
// facts make the arming safe to place on the SHARED expression path: it is indexable by the enclosing
// plan's pool index (not by entry count), and it is EMPTY wherever no plan local was published — which
// is every path but the method-body door, because `DeclarePlanLocal` has exactly one production caller.
test "the plan-local mirror vocabulary is indexed by pool index and empty without plan locals" {
    bindings := MethodBodyFactsEmptyBindings()
    assert bindings.PlanLocalMirrorTypes().Length == 0

    bindings.DeclarePlanLocal("first", 0, typeof(int))
    bindings.DeclarePlanLocal("third", 2, typeof(string))
    vocabulary := bindings.PlanLocalMirrorTypes()

    // Sized by the HIGHEST index rather than by the entry count, so index 2 is index 2.
    assert vocabulary.Length == 3
    assert vocabulary[0] == typeof(int)
    assert vocabulary[2] == typeof(string)
    // The gap carries a filler. No name can spell an unpublished slot, so nothing can reference it, and
    // the mirror rule exempts it from the all-used check exactly as it exempts every other mirror.
    assert vocabulary[1] == typeof(int)

    // Armed onto a scratch, the vocabulary becomes three mirror slots at those indices.
    scratch := new ColumnarCodePlan()
    scratch.EnablePlanLocalMirror(vocabulary)
    scratch.PrepareV3()
    assert scratch.PlanLocalCount == 3
    assert scratch.Types[scratch.PlanLocalTypeIndices[2]] == typeof(string)
    assert scratch.PlanLocalIsMirror[2]
}

// `{ return <left> <operator> <right> }`. The OPERATOR's own token carries the node's value span,
// which is what `IsClaimedOperatorText` reads to decide the family.
func MethodBodyFactsBinaryBody(operatorText: string, leftKind: int, leftText: string, rightKind: int, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(leftKind, leftText)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(rightKind, rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, operatorText.Length, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    statement := builder.AddNode(20, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(binary))
    return builder.Build(builder.AddNode(25, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(statement)))
}

// `{ return <member>(<left> <operator> <right>) }` — a binary in ARGUMENT position, which is a
// different decision from the one above and is the direct-call owner's rather than the door's.
func MethodBodyFactsCallBinaryArgumentBody(memberName: string, operatorText: string, leftText: string, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    callee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), memberName)
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), leftText)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, operatorText.Length, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    call := DirectCallAppendCall(builder, callee, DirectCallOneArgument(binary))
    return MethodBodyFactsWrapValueInBody(builder, call, 0, "")
}

// `{ <local> := <initMember>()  return <returnMember>(<local>[0]) }` — the `015-B8` P5 shape: an
// ordinary int index over a plan local, in argument position.
func MethodBodyFactsDeclareThenIndexArgumentBody(initMember: string, returnMember: string, localName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := builder.AddToken(localName)
    initCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), initMember)
    initCall := DirectCallAppendCall(builder, initCallee, DirectCallNoArguments())
    declaration := builder.AddNode(24, nameStart, localName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(initCall))
    returnCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), returnMember)
    receiver := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), nameStart, localName.Length, nameStart, localName.Length, new int[](0))
    selector := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    indexAccess := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, nameStart, localName.Length, MethodBodyFactsInts2(receiver, selector))
    call := DirectCallAppendCall(builder, returnCallee, DirectCallOneArgument(indexAccess))
    statement := builder.AddNode(20, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(call))
    return builder.Build(builder.AddNode(25, -1, 0, 0, builder.Source.Length, MethodBodyFactsInts2(declaration, statement)))
}

// `{ <local> := <initMember>()  return <returnMember>(<local>[1 + 1]) }` — the same shape with a
// BINARY selector, which is what the index owner's inherited value surface buys (015-B10).
func MethodBodyFactsDeclareThenBinaryIndexArgumentBody(initMember: string, returnMember: string, localName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := builder.AddToken(localName)
    initCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), initMember)
    initCall := DirectCallAppendCall(builder, initCallee, DirectCallNoArguments())
    declaration := builder.AddNode(24, nameStart, localName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(initCall))
    returnCallee := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), returnMember)
    receiver := builder.AddNode(ColumnarExpressionNodeKind.IdentifierExpression(), nameStart, localName.Length, nameStart, localName.Length, new int[](0))
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    operatorStart := builder.AddToken("+")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    selector := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 1, operatorStart, 1, MethodBodyFactsInts2(left, right))
    indexAccess := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, nameStart, localName.Length, MethodBodyFactsInts2(receiver, selector))
    call := DirectCallAppendCall(builder, returnCallee, DirectCallOneArgument(indexAccess))
    statement := builder.AddNode(20, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(call))
    return builder.Build(builder.AddNode(25, -1, 0, 0, builder.Source.Length, MethodBodyFactsInts2(declaration, statement)))
}

// ---- BLOCK 48 — THE PRIMITIVE-BINARY COMPOSITE IN RETURN POSITION (class PB, 015-B9) ----
//
// The third owner the door enters through its own root sequence, and the first whose consumer of the
// routed OVERFLOW flag is live rather than latent. The rows are the owner's rows plus the driver's
// `ret`, and the body is EXECUTED so the claim is not merely a shape.
test "the door claims a primitive binary as a return value and executes it" {
    tree := MethodBodyFactsBinaryBody("+", ColumnarExpressionNodeKind.IntLiteralExpression(), "2", ColumnarExpressionNodeKind.IntLiteralExpression(), "3")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    assert plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    assert plan.OperationCount == 4
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Add()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ret()
    assert plan.OpenFragmentCount == 0
    assert plan.PlanLocalCount == 0

    method := MethodBodyFactsDynamicMethod("NSharpB9BinaryBody", typeof(int))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsNoArguments())) == 5

    // A SECOND operator family through the same arm, so the claim is the owner's rather than one
    // operator's — and the result type is what the door then matches against the return type.
    productPlan := new ColumnarCodePlan()
    product := MethodBodyFactsBinaryBody("*", ColumnarExpressionNodeKind.IntLiteralExpression(), "6", ColumnarExpressionNodeKind.IntLiteralExpression(), "7")
    assert MethodBodyFactsPlanCallBody(product, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), productPlan)
    assert productPlan.OpCodeValues[2] == ColumnarCodePlanContract.Mul()

    // TYPE EQUALITY IS STILL THE RULE. The same rows on a `long` body are refused by the driver, not
    // by the owner, because an int result is not a long return type.
    longPlan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsBinaryBody("+", ColumnarExpressionNodeKind.IntLiteralExpression(), "2", ColumnarExpressionNodeKind.IntLiteralExpression(), "3"), typeof(long), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), longPlan)
}

// ---- BLOCK 49 — THE BINARY ROOT SEQUENCE IS ONE SEQUENCE, NOT TWO ----
//
// The same block `015-B7` wrote for the direct-call owner, for the same reason: the door's claim is
// byte-identical BY CONSTRUCTION only if the rows it appends are the rows `Plan` produces. `Plan` and
// `TryAppendRoot` now differ in exactly the wrapper — `PrepareV3`/`CompleteV3` versus an already-open
// method body — and in nothing else.
test "the binary root sequence produces the same rows through Plan and through the door" {
    tree := MethodBodyFactsBinaryBody("-", ColumnarExpressionNodeKind.IntLiteralExpression(), "9", ColumnarExpressionNodeKind.IntLiteralExpression(), "4")
    statement := tree.Nodes.Child(tree.Root, 0)
    expression := tree.Nodes.Child(statement, 0)

    viaPlan := new ColumnarCodePlan()
    assert ColumnarPrimitiveBinaryPlanner.Plan(tree.Nodes, tree.Source, expression, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), viaPlan) == ColumnarFragmentPlanStatus.Planned

    viaDoor := new ColumnarCodePlan()
    viaDoor.PrepareMethodBody()
    doorResult := typeof(long)
    assert ColumnarPrimitiveBinaryPlanner.TryAppendRoot(tree.Nodes, tree.Source, expression, ColumnarRangePlannerEmptyBindings(), ColumnarRangeIndexHandles.Resolve(), viaDoor, out doorResult)

    assert doorResult == viaPlan.ResultType
    assert viaDoor.OperationCount == viaPlan.OperationCount
    row := 0
    while row < viaPlan.OperationCount {
        assert viaDoor.OpCodeValues[row] == viaPlan.OpCodeValues[row]
        assert viaDoor.OperandKinds[row] == viaPlan.OperandKinds[row]
        row = row + 1
    }

    assert viaPlan.SchemaVersion == ColumnarCodePlanContract.ScalarSchemaVersion()
    assert viaDoor.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    assert viaDoor.OpenFragmentCount == 0
}

// ---- BLOCK 50 — THE KIND MOVED SIDES, AND `015-B12` BROUGHT THE SHORT-CIRCUIT FAMILY WITH IT ----
//
// ⚠ THIS BLOCK IS A REWRITE, AND THE THING IT USED TO ASSERT IS WORTH RECORDING RATHER THAN ERASING.
// From `015-B9` to `015-B11` it asserted the door DECLINED a `&&` body, with the reason: "`&&`/`||`
// are kind-12 nodes the CONDITIONAL owner roots, not this one, and the door does not carry a second
// copy of that judgement". Both halves of that reason are still TRUE — what changed in `015-B12` is
// that the door now has an ARM into the conditional owner, so "not this owner's" stopped meaning "not
// claimable". The block therefore keeps its subject and inverts its verdict.
//
// What it still proves, and what no other block proves, is that ONE node kind reaches TWO owners and
// the door picks between them the way the emitter's cascade does.
test "the door claims the binary kind and now claims the short-circuit family too" {
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.BinaryExpression())
    assert !ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.BinaryExpression())

    shortCircuit := MethodBodyFactsBinaryBody("&&", ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.BoolLiteralExpression(), "false")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(shortCircuit, typeof(bool), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)
    // The conditional owner is the only kind-12 owner that branches, so the labels are the signature
    // of WHICH owner served this body — a claim alone would not distinguish them.
    assert plan.LabelCount == 2

    // The claimed family in the same position, and it takes the OTHER owner: no labels at all.
    equality := MethodBodyFactsBinaryBody("==", ColumnarExpressionNodeKind.IntLiteralExpression(), "3", ColumnarExpressionNodeKind.IntLiteralExpression(), "3")
    equalityPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(equality, typeof(bool), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), equalityPlan)
    assert equalityPlan.LabelCount == 0
}

// ---- BLOCK 51 — A BINARY *ARGUMENT* IS THE OTHER HALF, AND IT IS THE CALL OWNER'S DECISION ----
//
// `015-B8`'s `P8` (`return Callee(n + 1)`) declined at the direct-call ROOT rather than at the door,
// because every one of that owner's eight argument sites passed `allowPrimitiveBinary: false` while the
// CONSTRUCTION owner passed true for the same dispatcher. `ArgumentsAdmitPrimitiveBinary` is that
// decision with one name and one home; the rows below are the binary's rows INSIDE the call's.
test "the door claims a call whose argument is a primitive binary" {
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    facts := DirectCallSiblingFacts("MethodBodyFactsBinaryArgumentHost", "Take", oneInt, typeof(int))

    tree := MethodBodyFactsCallBinaryArgumentBody("Take", "+", "2", "3")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsSiblings("Take", facts), plan)

    assert plan.OperationCount == 5
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Add()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[3]].get_Name() == "Take"
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.Ret()

    // The rule is ONE decision, and it is the one the type side and the append side both read.
    assert ColumnarDirectCallPlanner.ArgumentsAdmitPrimitiveBinary()
}

// ---- BLOCK 52 — THE INDEX-ACCESS ARGUMENT, AND THE ROOT RULE IT DID NOT WEAKEN ----
//
// `015-B8`'s `P5` (`arr := Make()  return Take(arr[0])`). The owner never had an "index in argument
// position" rule: it had a ROOT rule (`allowOrdinaryIntIndex = parentFragment >= 0`) that its
// type-discovery scratch applied to a value that is never at a root. The scratch now DECLARES the frame
// it types in, and the two sides agree.
test "the door claims a call whose argument is an ordinary index over a plan local" {
    makeFacts := DirectCallSiblingFacts("MethodBodyFactsIndexArgumentHost", "Make", new Type[](0), typeof(int[]))
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    takeFacts := DirectCallSiblingFacts("MethodBodyFactsIndexArgumentHost", "Take", oneInt, typeof(int))
    siblings := MethodBodyFactsSiblings2("Make", makeFacts, "Take", takeFacts)

    tree := MethodBodyFactsDeclareThenIndexArgumentBody("Make", "Take", "arr")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(int), MethodBodyFactsNoSourceTypes(), siblings, plan)

    // The declaration's call and store, then the argument's three rows — the array, the ordinary int
    // selector and the element load — then the call and the `ret`.
    assert plan.OperationCount == 7
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Stloc()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    // The selector is a POOLED `ldc.i4` row; the executor is what narrows it to the compact form.
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.LdcI4()
    assert plan.Int32Values[plan.OperandIndices[3]] == 0
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.LdelemI4()
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.Call()
    assert plan.Methods[plan.OperandIndices[5]].get_Name() == "Take"
    assert plan.OpCodeValues[6] == ColumnarCodePlanContract.Ret()
    assert plan.PlanLocalCount == 1
    assert plan.Types[plan.PlanLocalTypeIndices[0]] == typeof(int[])
}

// ---- BLOCK 53 — THE ROOT RULE THE FRAME DID NOT WEAKEN ----
//
// An exemption that also swallowed the rule it exempts would be worse than the decline it replaced, so
// the separation is asserted directly rather than inferred. An ordinary int index at a REAL plan root
// still belongs to the host — the facade only owns an index root whose selector may produce
// Index/Range — and a plan with no declared frame answers the question by POSITION exactly as it always
// did. The two halves differ in ONE armed bit and in nothing else: same node, same position, same
// bindings.
test "an ordinary index still declines at a plan root and claims under a declared frame" {
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "values", 0, typeof(int[]))
    rootTree := MethodBodyFactsOrdinaryIndexTree("values", "0")

    rootPlan := new ColumnarCodePlan()
    rootPlan.PrepareV3()
    rootType := typeof(int)
    assert !ColumnarRangeIndexPlanner.TryAppendPlannableValue(rootTree.Nodes, rootTree.Source, rootTree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), rootPlan, -1, 0, out rootType)

    // The SAME node, the SAME position, on a plan that declares the frame a scratch really types in.
    framedPlan := new ColumnarCodePlan()
    framedPlan.EnableNestedValueFrame()
    framedPlan.PrepareV3()
    framedType := typeof(string)
    assert ColumnarRangeIndexPlanner.TryAppendPlannableValue(rootTree.Nodes, rootTree.Source, rootTree.Root, bindings, ColumnarRangeIndexHandles.Resolve(), framedPlan, -1, 0, out framedType)
    assert framedType == typeof(int)
}

// `<name>[<selector>]` as a bare expression tree — the root position the facade leaves to the host.
func MethodBodyFactsOrdinaryIndexTree(name: string, selectorText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    selector := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), selectorText)
    return builder.Build(builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, 0, builder.Source.Length, MethodBodyFactsInts2(receiver, selector)))
}

// ---- BLOCK 54 — A COMPOSITE INDEX SELECTOR, END TO END THROUGH THE DOOR (015-B10) ----
//
// `015-B9` left `P9` (`Callee(arr[s.Length - 4])`) declining and named the reason: the index owner typed
// its selector with the PLAIN value surface while the enclosing position used the construction one.
// The surface is inherited now, so the selector's rows sit inside the index's, inside the call's.
test "the door claims a call whose index argument carries a binary selector" {
    makeFacts := DirectCallSiblingFacts("MethodBodyFactsBinaryIndexHost", "Make", new Type[](0), typeof(int[]))
    oneInt := new Type[](1)
    oneInt[0] = typeof(int)
    takeFacts := DirectCallSiblingFacts("MethodBodyFactsBinaryIndexHost", "Take", oneInt, typeof(int))
    siblings := MethodBodyFactsSiblings2("Make", makeFacts, "Take", takeFacts)

    tree := MethodBodyFactsDeclareThenBinaryIndexArgumentBody("Make", "Take", "arr")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(int), MethodBodyFactsNoSourceTypes(), siblings, plan)

    // The declaration's call and store; then the array, the selector's two literals and its `add`, the
    // element load, the call and the `ret`.
    assert plan.OperationCount == 9
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Stloc()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.Add()
    assert plan.OpCodeValues[6] == ColumnarCodePlanContract.LdelemI4()
    assert plan.OpCodeValues[7] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[8] == ColumnarCodePlanContract.Ret()
    assert plan.OpenFragmentCount == 0
}

// ---- 015-B12: THE DOOR'S KIND-12 SPLIT, AND THE FIRST CLAIMED KIND WHOSE ROWS BRANCH ----

// ⚠ THE SPLIT IS THE WHOLE OF THE SHORT-CIRCUIT CLAIM, AND IT LIVES IN ONE PLACE ON PURPOSE.
// `a && b` and `a + b` are the SAME node kind and DIFFERENT owners. `IsClaimedExpressionKind` answers
// for the kind and deliberately says nothing about the owner; the arm inside `TryAppendValue` asks the
// operator, exactly as the emitter's cascade does. This block asserts the door routes each to the
// owner that would have served it, by observing the ROWS each owner writes rather than by naming one.
test "the expression door routes a kind-12 binary to the owner its operator selects" {
    andTree := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    andPlan := new ColumnarCodePlan()
    andPlan.PrepareMethodBody()
    andType := typeof(int)
    assert ColumnarMethodBodyPlanner.TryAppendValue(andTree.Nodes, andTree.Source, andTree.Root, MethodBodyFactsEmptyBindings(), andPlan, out andType)
    assert andType == typeof(bool)
    // The conditional owner is the only kind-12 owner that defines labels; the binary owner defines none.
    assert andPlan.LabelCount == 2

    // ⚠ THE BITWISE PROBE IS OVER *INTS*, AND THAT IS A MEASURED CONSTRAINT RATHER THAN A PREFERENCE.
    // `TryAppendBitwise` refuses an operand type that is neither int-promotable nor long/ulong/uint nor
    // a bitwise enum, and `bool` is none of those — so `true & false` declines for a TYPE reason that
    // would have masked the routing question this block exists to ask.
    bitTree := ConditionalIntBinaryTree("&", "3", "5")
    bitPlan := new ColumnarCodePlan()
    bitPlan.PrepareMethodBody()
    bitType := typeof(bool)
    assert ColumnarMethodBodyPlanner.TryAppendValue(bitTree.Nodes, bitTree.Source, bitTree.Root, MethodBodyFactsEmptyBindings(), bitPlan, out bitType)
    assert bitType == typeof(int)
    assert bitPlan.LabelCount == 0
}

// The ternary arm, and the property that made this claim worth checking at all: it is the FIRST kind
// the door claims whose rows BRANCH. `DefineLabel`/`Brfalse`/`Br`/`MarkLabel` were only ever appended
// to a schema-v3 plan before this slice, and a method body is schema v4.
test "the expression door claims a ternary onto an open method-body plan, labels and all" {
    tree := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.IntLiteralExpression(), "9")
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    resultType := typeof(int)
    assert ColumnarMethodBodyPlanner.TryAppendValue(tree.Nodes, tree.Source, tree.Root, MethodBodyFactsEmptyBindings(), plan, out resultType)
    assert resultType == typeof(int)
    assert plan.LabelCount == 2

    // Exactly one MarkLabel row per label, which is the invariant the executor's label classification
    // enforces and the reason a branch is legal in a method body rather than merely appendable to one.
    marks := 0
    i := 0
    while i < plan.OperationCount {
        if plan.OperationKinds[i] == ColumnarCodePlanContract.MarkLabelOperation() {
            marks = marks + 1
        }
        i = i + 1
    }
    assert marks == 2
}

// The same claim through the door's OTHER entry. `TryAppendLocalDeclaration` and `TryAppendReturnValue`
// share one dispatcher, so a widening reaches both — and a widening that reached only one would be a
// silent asymmetry no other contract measures.
test "the ternary claim reaches the initializer door as well as the return door" {
    tree := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.IntLiteralExpression(), "9")

    returnPlan := new ColumnarCodePlan()
    returnPlan.PrepareMethodBody()
    returnType := typeof(int)
    assert ColumnarMethodBodyPlanner.TryAppendReturnValue(tree.Nodes, tree.Source, tree.Root, MethodBodyFactsEmptyBindings(), returnPlan, out returnType)
    assert returnType == typeof(int)

    // `IsHostAdoptedReturnShape` cannot pre-empt this shape: its FIRST test demands a unary node, and a
    // ternary is not one — so the return door and the value door agree here by construction.
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(tree.Nodes, tree.Source, tree.Root)

    valuePlan := new ColumnarCodePlan()
    valuePlan.PrepareMethodBody()
    valueType := typeof(int)
    assert ColumnarMethodBodyPlanner.TryAppendValue(tree.Nodes, tree.Source, tree.Root, MethodBodyFactsEmptyBindings(), valuePlan, out valueType)
    assert valuePlan.OperationCount == returnPlan.OperationCount
}

// A ternary whose ARMS DISAGREE is refused by the owner, and the refusal must be ATOMIC at the door:
// the plan a driver hands in has to come back usable, because the driver goes on to let the host emit
// the body it just declined.
test "a mixed-arm ternary declines at the door and leaves the plan clean" {
    tree := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.StringLiteralExpression(), "s")
    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    resultType := typeof(int)
    assert !ColumnarMethodBodyPlanner.TryAppendValue(tree.Nodes, tree.Source, tree.Root, MethodBodyFactsEmptyBindings(), plan, out resultType)
    assert plan.OperationCount == 0
    assert plan.FragmentCount == 0
    assert plan.LabelCount == 0
}

// ---- 015-B13: THE CHECKED CONTEXT (class K) — THE ONE CLAIMED KIND WITH NO OWNER BEHIND IT ----

// `{ return <keyword>(<left> <operator> <right>) }`. The KEYWORD carries the kind-57 node's value
// span, which is exactly what the host's `case 57` reads to choose between the two directions.
func MethodBodyFactsCheckedBinaryBody(keyword: string, operatorText: string, leftText: string, rightText: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    keywordStart := builder.AddToken(keyword)
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), leftText)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), rightText)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, operatorText.Length, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    context := builder.AddNode(ColumnarExpressionNodeKind.CheckedContextExpression(), keywordStart, keyword.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(binary))
    return MethodBodyFactsWrapValueInBody(builder, context, 0, "")
}

// `{ return <keyword>(<left> <operator> <right>) }` over two NAMED operands, so a block can put the
// context over types no source literal in the native corpus can spell.
func MethodBodyFactsCheckedNamedBinaryBody(keyword: string, operatorText: string, leftName: string, rightName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    keywordStart := builder.AddToken(keyword)
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), leftName)
    operatorStart := builder.AddToken(operatorText)
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), rightName)
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, operatorText.Length, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    context := builder.AddNode(ColumnarExpressionNodeKind.CheckedContextExpression(), keywordStart, keyword.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(binary))
    return MethodBodyFactsWrapValueInBody(builder, context, 0, "")
}

// `{ return <outer>(<inner>(<left> + <right>)) }` — two kind-57 nodes, one inside the other.
func MethodBodyFactsNestedCheckedBody(outerKeyword: string, innerKeyword: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    outerStart := builder.AddToken(outerKeyword)
    innerStart := builder.AddToken(innerKeyword)
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    operatorStart := builder.AddToken("+")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "3")
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 1, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    inner := builder.AddNode(ColumnarExpressionNodeKind.CheckedContextExpression(), innerStart, innerKeyword.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(binary))
    outer := builder.AddNode(ColumnarExpressionNodeKind.CheckedContextExpression(), outerStart, outerKeyword.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(inner))
    return MethodBodyFactsWrapValueInBody(builder, outer, 0, "")
}

// `{ <local> := checked(1 + 2)  return 3 + 4 }` — a claimed context in the INITIALIZER position
// followed by a second statement whose binary must NOT inherit the flag.
func MethodBodyFactsCheckedDeclarationThenBinaryBody(keyword: string, localName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := builder.AddToken(localName)
    keywordStart := builder.AddToken(keyword)
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
    firstOperator := builder.AddToken("+")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    initializerBinary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), firstOperator, 1, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    context := builder.AddNode(ColumnarExpressionNodeKind.CheckedContextExpression(), keywordStart, keyword.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(initializerBinary))
    declaration := builder.AddNode(24, nameStart, localName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(context))
    tailLeft := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "3")
    secondOperator := builder.AddToken("+")
    tailRight := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "4")
    tailBinary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), secondOperator, 1, 0, builder.Source.Length, MethodBodyFactsInts2(tailLeft, tailRight))
    statement := builder.AddNode(20, -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(tailBinary))
    return builder.Build(builder.AddNode(25, -1, 0, 0, builder.Source.Length, MethodBodyFactsInts2(declaration, statement)))
}

// `{ return (<2> + <3>) }` — the parenthesised binary on its own, so a block can show that the
// `add.ovf` its `checked` twin plans is the FLAG rather than a default (015-B16).
func MethodBodyFactsParenthesisedBinaryBody(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    operatorStart := builder.AddToken("+")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "3")
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 1, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    parenthesis := builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(binary))
    return MethodBodyFactsWrapValueInBody(builder, parenthesis, 0, "")
}

// `{ return checked(<child>) }` where the child is supplied by the caller, so a block can put a shape
// under a context the door claims.
func MethodBodyFactsCheckedOverParenthesisBody(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    keywordStart := builder.AddToken("checked")
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    operatorStart := builder.AddToken("+")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "3")
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 1, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    parenthesis := builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(binary))
    context := builder.AddNode(ColumnarExpressionNodeKind.CheckedContextExpression(), keywordStart, 7, 0, builder.Source.Length, ColumnarRangePlannerChildren1(parenthesis))
    return MethodBodyFactsWrapValueInBody(builder, context, 0, "")
}

// `{ return checked(-<name>) }` — a unary over a NON-literal operand, which is the one shape where an
// active overflow flag changes the host's unary lowering.
func MethodBodyFactsCheckedNegatedIdentifierBody(name: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    keywordStart := builder.AddToken("checked")
    operatorStart := builder.AddToken("-")
    operand := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), name)
    unary := builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression(), operatorStart, 1, 0, builder.Source.Length, ColumnarRangePlannerChildren1(operand))
    context := builder.AddNode(ColumnarExpressionNodeKind.CheckedContextExpression(), keywordStart, 7, 0, builder.Source.Length, ColumnarRangePlannerChildren1(unary))
    return MethodBodyFactsWrapValueInBody(builder, context, 0, "")
}

// A kind-57 node carrying EXACTLY ONE defect: either an ABSENT keyword span or a wrong arity. Neither
// is reachable from the parser; both are reachable from a caller, and the arm must decline rather than
// throw.
//
// ⚠ THE KEYWORD TOKEN IS REAL, AND `015-B13`'s CONTROL `C3` IS WHY. The first spelling of this helper
// added no keyword token at all, so `valueLength` (7) always exceeded the three-character source and
// EVERY case — including both arity cases — was refused by the SPAN guard before the arity test ran.
// `C3` weakened the arity guard and NOTHING broke, which is how a vacuous assertion announces itself.
// With the keyword token present, `spanned` is the only knob that reaches the span guard and
// `childCount` is the only knob that reaches the arity guard.
func MethodBodyFactsMalformedCheckedBody(spanned: bool, childCount: int): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    keywordStart := builder.AddToken("checked")
    left := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "2")
    operatorStart := builder.AddToken("+")
    right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "3")
    binary := builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 1, 0, builder.Source.Length, MethodBodyFactsInts2(left, right))
    children := new int[](0)
    if childCount == 1 {
        children = ColumnarRangePlannerChildren1(binary)
    } else if childCount == 2 {
        children = MethodBodyFactsInts2(binary, binary)
    }

    valueStart := keywordStart
    if !spanned {
        valueStart = -1
    }

    context := builder.AddNode(ColumnarExpressionNodeKind.CheckedContextExpression(), valueStart, 7, 0, builder.Source.Length, children)
    return MethodBodyFactsWrapValueInBody(builder, context, 0, "")
}

// Every fragment a plan opened, against the kind of the node it points at. This is the instrument
// `015-B12`'s `C3` proved was missing, and it is deliberately a WALK rather than a spot check.
func MethodBodyFactsFragmentKindsAgree(tree: ColumnarRangePlannerTestTree, plan: ColumnarCodePlan): bool {
    index := 0
    while index < plan.FragmentCount {
        if plan.FragmentKinds[index] != tree.Nodes.Kind(plan.FragmentSourceNodeIndices[index]) {
            return false
        }

        index = index + 1
    }

    return true
}

// ---- BLOCK 56 — THE CHECKED CONTEXT WRITES THE OVERFLOW OPCODE THE HOST WRITES ----
//
// The routed flag has had exactly one production consumer since `015-B9` — `ColumnarPrimitiveBinaryPlanner`'s
// `checkedIntegral`, which chooses `add` versus `add.ovf` — and until this slice the door could never
// make it TRUE, because the driver's own `overflowCheckingEnabled` argument is provably `false` at
// every `EmitBody` call site. Kind 57 is the only thing that can turn it on, so this block is where
// the fact stops being carried and starts being exercised. The body is EXECUTED so the claim is a
// value rather than a shape.
test "the door claims a checked binary and writes the overflow opcode" {
    tree := MethodBodyFactsCheckedBinaryBody("checked", "+", "2", "3")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    assert plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    assert plan.OperationCount == 4
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.AddOvf()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ret()
    assert plan.OpenFragmentCount == 0

    method := MethodBodyFactsDynamicMethod("NSharpB13CheckedBody", typeof(int))
    ColumnarCodePlanExecutor.Execute(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToInt32(method.Invoke(target, MethodBodyFactsNoArguments())) == 5

    // A SECOND operator family through the same arm, so the claim is the CONTEXT's rather than one
    // operator's.
    productPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsCheckedBinaryBody("checked", "*", "6", "7"), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), productPlan)
    assert productPlan.OpCodeValues[2] == ColumnarCodePlanContract.MulOvf()

    // ⚠ THE UNSIGNED ARM IS ASSERTED HERE RATHER THAN IN THE NATIVE CORPUS, AND THE REASON IS A
    // MEASURED PRE-EXISTING WALL. `add.ovf.un` needs `uint` operands, and a `uint` LITERAL declines
    // columnar emission at this tip on both the pre-slice and post-slice CLI — `func UMax(): uint
    // { return 4294967295U }` alone is enough, with no `checked` anywhere. A plan built from `uint`
    // PARAMETER bindings needs no source literal, so the third opcode family is proved here.
    unsignedBindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(unsignedBindings, "u", 0, typeof(uint))
    ColumnarRangePlannerAddParameter(unsignedBindings, "v", 1, typeof(uint))
    unsignedTree := MethodBodyFactsCheckedNamedBinaryBody("checked", "+", "u", "v")
    unsignedPlan := new ColumnarCodePlan()
    unsignedPlan.PrepareMethodBody()
    unsignedType := typeof(int)
    unsignedStatement := unsignedTree.Nodes.Child(unsignedTree.Root, 0)
    assert ColumnarMethodBodyPlanner.TryAppendValue(unsignedTree.Nodes, unsignedTree.Source, unsignedTree.Nodes.Child(unsignedStatement, 0), unsignedBindings, unsignedPlan, out unsignedType)
    assert unsignedType == typeof(uint)
    assert unsignedPlan.OpCodeValues[2] == ColumnarCodePlanContract.AddOvfUn()

    // The same operands WITHOUT the context take the plain opcode, so the unsigned arm is the flag's
    // doing rather than the type's.
    plainUnsigned := new ColumnarCodePlan()
    plainUnsigned.PrepareMethodBody()
    plainUnsignedType := typeof(int)
    plainUnsignedTree := MethodBodyFactsCheckedNamedBinaryBody("unchecked", "+", "u", "v")
    plainUnsignedStatement := plainUnsignedTree.Nodes.Child(plainUnsignedTree.Root, 0)
    assert ColumnarMethodBodyPlanner.TryAppendValue(plainUnsignedTree.Nodes, plainUnsignedTree.Source, plainUnsignedTree.Nodes.Child(plainUnsignedStatement, 0), unsignedBindings, plainUnsigned, out plainUnsignedType)
    assert plainUnsigned.OpCodeValues[2] == ColumnarCodePlanContract.Add()

    // And the kind is on the CLAIMED side of the partition now, which is what routes it here at all.
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.CheckedContextExpression())
    assert !ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.CheckedContextExpression())
}

// ---- BLOCK 57 — `unchecked` IS THE SAME NODE AND THE OTHER DIRECTION ----
//
// The two keywords share one node kind, so an arm that read the kind and not the TEXT would claim both
// and lower both the same way. The difference is one opcode and it is asserted against the identical
// tree with a single token changed.
test "the unchecked keyword turns the same node back into the plain opcode" {
    plain := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsCheckedBinaryBody("unchecked", "+", "2", "3"), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plain)
    assert plain.OperationCount == 4
    assert plain.OpCodeValues[2] == ColumnarCodePlanContract.Add()

    // The DRIVER's own default is the same direction, which is why `unchecked` costs no rows: an
    // ordinary `return 2 + 3` and `return unchecked(2 + 3)` are the same four rows.
    bare := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsBinaryBody("+", ColumnarExpressionNodeKind.IntLiteralExpression(), "2", ColumnarExpressionNodeKind.IntLiteralExpression(), "3"), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), bare)
    assert bare.OperationCount == plain.OperationCount
    assert bare.OpCodeValues[2] == plain.OpCodeValues[2]
}

// ---- BLOCK 58 — THE INNER KEYWORD WINS, AND THE FLAG IS PUT BACK ----
//
// The host's `case 57` restores `_overflowCheckingEnabled` in a `finally`, so a context governs its
// own subtree and nothing after it. Two independent consequences are asserted rather than one: a
// NESTED context overrides its parent, and a claimed context in an INITIALIZER does not leak into the
// statement that follows it. The second is the one an arm that only SET the flag would fail.
test "the checked context restores the flag it set, and the inner keyword wins" {
    outerChecked := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsNestedCheckedBody("checked", "unchecked"), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), outerChecked)
    assert outerChecked.OpCodeValues[2] == ColumnarCodePlanContract.Add()

    outerUnchecked := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsNestedCheckedBody("unchecked", "checked"), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), outerUnchecked)
    assert outerUnchecked.OpCodeValues[2] == ColumnarCodePlanContract.AddOvf()

    // `m := checked(1 + 2)` then `return 3 + 4`: the initializer's binary is checked and the return's
    // is NOT, on one plan, from one bindings object.
    leak := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsCheckedDeclarationThenBinaryBody("checked", "m"), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), leak)
    assert leak.OperationCount == 8
    assert leak.OpCodeValues[2] == ColumnarCodePlanContract.AddOvf()
    assert leak.OpCodeValues[3] == ColumnarCodePlanContract.Stloc()
    assert leak.OpCodeValues[6] == ColumnarCodePlanContract.Add()
    assert leak.OpCodeValues[7] == ColumnarCodePlanContract.Ret()
    assert leak.PlanLocalCount == 1
}

// ---- BLOCK 59 — ONE SHAPE THE ARM REFUSES BY CONSTRUCTION, AND ONE THAT STOPPED BEING REFUSED ----
//
// The refusal is not a guard the arm writes; it falls out of what the door already is, and asserting
// it is how "by construction" stops being a claim a comment makes.
//
// ⚠ THE PARENTHESIS HALF OF THIS BLOCK WAS A DECLINE UNTIL `015-B16` AND IS NOW A CLAIM. `015-B13`
// wrote that the arm does not unwrap, "so `checked((2 + 3))`'s child is kind 7 — which
// `IsDeclinedExpressionKind` refuses exactly as it refuses a bare `return (2 + 3)`." The arm still
// does not unwrap and the sentence is still true in its SHAPE: kind 7 left the declined side, so
// `checked((2 + 3))` is claimed exactly as `return (2 + 3)` now is. What the block asserts is
// therefore stronger than a claim — that the FLAG SURVIVES the extra node, which is the thing a
// parenthesis arm could plausibly lose: the rows must be `add.ovf`, not `add`.
//
// The NEGATION: `checked(-x)` over a non-literal is the ONE shape where an active flag changes the
// host's unary lowering — it declares a local and writes `stloc; ldc.i4.0; ldloc; sub.ovf` instead of
// `neg` — and the door's kind-11 arm is `ColumnarUnaryLiteralPlanner`, which claims only a unary over
// a LITERAL. So the shape the door could get wrong is the shape the door cannot reach.
test "the checked arm claims a parenthesised operand without losing the flag and refuses a unary over a non-literal" {
    parenthesised := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsCheckedOverParenthesisBody(), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), parenthesised)
    assert !ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.ParenthesizedExpression())
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.ParenthesizedExpression())

    // FOUR rows, not five: the parenthesis contributes NO row of its own, which is what "the host's
    // `case 7` is one recursive call" means in the IR.
    assert parenthesised.OperationCount == 4
    assert parenthesised.OpCodeValues[2] == ColumnarCodePlanContract.AddOvf()
    assert parenthesised.OpCodeValues[3] == ColumnarCodePlanContract.Ret()

    // And the same tree WITHOUT the `checked` context is the plain opcode, so the `add.ovf` above is
    // the flag surviving the extra node rather than a default.
    plainParen := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsParenthesisedBinaryBody(), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plainParen)
    assert plainParen.OperationCount == 4
    assert plainParen.OpCodeValues[2] == ColumnarCodePlanContract.Add()

    negated := MethodBodyFactsCheckedNegatedIdentifierBody("x")
    negatedPlan := new ColumnarCodePlan()
    negatedPlan.PrepareMethodBody()
    negatedType := typeof(int)
    bindings := ColumnarRangePlannerEmptyBindings()
    ColumnarRangePlannerAddParameter(bindings, "x", 0, typeof(int))
    statement := negated.Nodes.Child(negated.Root, 0)
    assert !ColumnarMethodBodyPlanner.TryAppendValue(negated.Nodes, negated.Source, negated.Nodes.Child(statement, 0), bindings, negatedPlan, out negatedType)
    assert negatedPlan.OperationCount == 0

    // The complement, and the reason the refusal above is not a coincidence: with a LITERAL operand the
    // same owner claims the node, and it consults no flag at all — so both pipelines write `neg`.
    literal := MethodBodyFactsCheckedBinaryBody("checked", "+", "2", "3")
    literalPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(literal, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), literalPlan)
}

// ---- BLOCK 60 — THE KEYWORD IS READ, AND A MALFORMED NODE DECLINES RATHER THAN THROWS ----
//
// `ColumnarNodeTable.Text` is a bare `Substring`, so a kind-57 node with no keyword span would THROW
// out of the compiler. The host reads it unguarded because it is already committed to emitting; a
// FRONT DOOR that crashes is strictly worse than one that declines, and this is the same obligation
// `015-B11` took on when its adopted-return predicate first read an operand's text.
test "the checked arm refuses an unknown keyword, an absent span and a wrong arity" {
    unknown := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsCheckedBinaryBody("chekced", "+", "2", "3"), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), unknown)
    assert unknown.OperationCount == 0

    spanless := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsMalformedCheckedBody(false, 1), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), spanless)
    assert spanless.OperationCount == 0

    childless := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsMalformedCheckedBody(true, 0), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), childless)

    twoChildren := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsMalformedCheckedBody(true, 2), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), twoChildren)

    // ⚠ NON-VACUITY, AND `015-B13`'s `C3` IS WHY IT IS HERE. The two arity cases above are refusals,
    // and a refusal that happens for the WRONG reason looks identical to one that happens for the right
    // one. The SAME helper with the SAME keyword span and the CORRECT arity is CLAIMED, so the span is
    // demonstrably readable and the arity is demonstrably the only thing left refusing.
    wellFormed := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsMalformedCheckedBody(true, 1), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), wellFormed)
    assert wellFormed.OpCodeValues[2] == ColumnarCodePlanContract.AddOvf()
}

// ---- BLOCK 61 — THE CLAIM REACHES BOTH DOORS, AND THE RETURN DOOR CANNOT PRE-EMPT IT ----
//
// `TryAppendLocalDeclaration` and `TryAppendReturnValue` share one dispatcher, so a widening reaches
// both — and a widening that reached only one would be a silent asymmetry nothing else measures.
// `IsHostAdoptedReturnShape` also cannot pre-empt a kind-57 return: its FIRST test demands a unary
// node. That matters more here than for the other composites, because the shape UNDER the context can
// be `-5`, which the pre-pass WOULD have adopted at a bare return — and the host declines it too, for
// the same reason, since its own pre-pass gates on the OUTER node's kind.
test "the checked claim reaches the initializer door as well as the return door" {
    tree := MethodBodyFactsCheckedBinaryBody("checked", "+", "2", "3")
    statement := tree.Nodes.Child(tree.Root, 0)
    context := tree.Nodes.Child(statement, 0)
    assert tree.Nodes.Kind(context) == ColumnarExpressionNodeKind.CheckedContextExpression()
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(tree.Nodes, tree.Source, context)

    returnPlan := new ColumnarCodePlan()
    returnPlan.PrepareMethodBody()
    returnType := typeof(int)
    assert ColumnarMethodBodyPlanner.TryAppendReturnValue(tree.Nodes, tree.Source, context, MethodBodyFactsEmptyBindings(), returnPlan, out returnType)
    assert returnType == typeof(int)

    valuePlan := new ColumnarCodePlan()
    valuePlan.PrepareMethodBody()
    valueType := typeof(int)
    assert ColumnarMethodBodyPlanner.TryAppendValue(tree.Nodes, tree.Source, context, MethodBodyFactsEmptyBindings(), valuePlan, out valueType)
    assert valuePlan.OperationCount == returnPlan.OperationCount
    assert valuePlan.OpCodeValues[2] == returnPlan.OpCodeValues[2]
}

// ---- BLOCK 62 — EVERY FRAGMENT RECORDS THE KIND OF ITS OWN SOURCE NODE (015-B13, item 5) ----
//
// `015-B12`'s control `C3` hard-coded a fragment's kind to one its source node did not have and the
// WHOLE estate stayed green: `HasValidV2Fragments` asks only `FragmentKinds[i] >= 0` and never
// compares the recorded kind with `nodes.Kind(FragmentSourceNodeIndices[i])`. The complete fix would
// be a validator arm inside `ColumnarCodePlan`, and it cannot be written — a plan deliberately carries
// no node table.
//
// `015-B13` censused all 24 `BeginFragment` call sites instead: 15 DERIVE the kind from the recorded
// node, 7 pass a named ledger constant within three lines of a guard proving that same kind, and the
// one function taking the pair as PARAMETERS is called twice, both times with `nodes.Kind(candidate),
// candidate`. So no site in the tree can disagree TODAY; the exposure is a future caller. This block
// is the instrument that catches that caller — a WALK over every fragment of real door-claimed plans,
// deliberately not a spot check, driven through as many owners as the door can reach.
test "every fragment a door-claimed plan opens records the kind of its own source node" {
    checkedTree := MethodBodyFactsCheckedBinaryBody("checked", "+", "2", "3")
    checkedPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(checkedTree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), checkedPlan)
    assert checkedPlan.FragmentCount > 0
    assert MethodBodyFactsFragmentKindsAgree(checkedTree, checkedPlan)

    binaryTree := MethodBodyFactsBinaryBody("-", ColumnarExpressionNodeKind.IntLiteralExpression(), "9", ColumnarExpressionNodeKind.IntLiteralExpression(), "4")
    binaryPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(binaryTree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), binaryPlan)
    assert binaryPlan.FragmentCount > 0
    assert MethodBodyFactsFragmentKindsAgree(binaryTree, binaryPlan)

    ternaryTree := ConditionalTernaryLeafTree(ColumnarExpressionNodeKind.BoolLiteralExpression(), "true", ColumnarExpressionNodeKind.IntLiteralExpression(), "7", ColumnarExpressionNodeKind.IntLiteralExpression(), "9")
    ternaryPlan := new ColumnarCodePlan()
    ternaryPlan.PrepareMethodBody()
    ternaryType := typeof(int)
    assert ColumnarMethodBodyPlanner.TryAppendValue(ternaryTree.Nodes, ternaryTree.Source, ternaryTree.Root, MethodBodyFactsEmptyBindings(), ternaryPlan, out ternaryType)
    assert ternaryPlan.FragmentCount > 0
    assert MethodBodyFactsFragmentKindsAgree(ternaryTree, ternaryPlan)

    shortCircuitTree := ConditionalShortCircuitLiteralTree("&&", "true", "false")
    shortCircuitPlan := new ColumnarCodePlan()
    shortCircuitPlan.PrepareMethodBody()
    shortCircuitType := typeof(int)
    assert ColumnarMethodBodyPlanner.TryAppendValue(shortCircuitTree.Nodes, shortCircuitTree.Source, shortCircuitTree.Root, MethodBodyFactsEmptyBindings(), shortCircuitPlan, out shortCircuitType)
    assert shortCircuitPlan.FragmentCount > 0
    assert MethodBodyFactsFragmentKindsAgree(shortCircuitTree, shortCircuitPlan)

    // 015-B14 — THE INSTANCE-MEMBER OWNER JOINS THE WALK RATHER THAN GETTING ITS OWN CENSUS. It opens
    // TWO fragments for one root (the member access, and the receiver under it), and the receiver's is
    // opened by `TryAppend` from `nodes.Kind(UnwrapParentheses(nodes, receiver))` — a DERIVED kind
    // whose source node is derived beside it, which is exactly the pair this instrument compares.
    memberTree := MethodBodyFactsMemberBody("values", "Length", "")
    memberPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanMemberBody(memberTree, typeof(int), "values", 0, typeof(byte[]), memberPlan)
    assert memberPlan.FragmentCount > 1
    assert MethodBodyFactsFragmentKindsAgree(memberTree, memberPlan)

    // 015-B15 — THE EXTERNAL-STATIC OWNER JOINS THE WALK RATHER THAN GETTING ITS OWN CENSUS, exactly
    // as the instance-member owner did in `015-B14`. Its `BeginFragment` is one of the seven sites
    // that pass a NAMED ledger constant rather than deriving the kind, three lines under a guard
    // proving that same kind — which is precisely the site class this instrument exists to catch
    // drifting, and it now walks through the door instead of being argued about.
    staticTree := MethodBodyFactsQualifiedMemberBody("Environment", "NewLine")
    ExternalStampScope(staticTree, "import System")
    staticPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(staticTree, typeof(string), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), staticPlan)
    assert staticPlan.FragmentCount > 0
    assert MethodBodyFactsFragmentKindsAgree(staticTree, staticPlan)

    // 015-B16 — THE TYPEOF OWNER JOINS THE WALK, which is how a new owner is added to this instrument:
    // extend the list, do not re-census. `ColumnarTypeOfPlanner.TryAppendRoot`'s `BeginFragment` is
    // another of the NAMED-ledger-constant sites, three lines under the guard proving that same kind.
    typeOfTree := MethodBodyFactsTypeOfBody("int")
    typeOfPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(typeOfTree, typeof(Type), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), typeOfPlan)
    assert typeOfPlan.FragmentCount > 0
    assert MethodBodyFactsFragmentKindsAgree(typeOfTree, typeOfPlan)

    // ⚠ NON-VACUITY. The walk must be able to FAIL, or a green line proves nothing about the property
    // it names. One fragment's recorded kind is overwritten in place with a kind its source node
    // demonstrably does not have, and the same walk answers false.
    assert binaryPlan.FragmentKinds[0] == ColumnarExpressionNodeKind.BinaryExpression()
    binaryPlan.FragmentKinds[0] = ColumnarExpressionNodeKind.TernaryExpression()
    assert !MethodBodyFactsFragmentKindsAgree(binaryTree, binaryPlan)
}

// `{ return <receiver>.<member> }`, or with a non-empty `localName`,
// `{ <localName> := <receiver>.<member>  return <localName> }` — the member-access ROOT in each of the
// door's two positions (015-B14).
func MethodBodyFactsMemberBody(receiverName: string, memberName: string, localName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    nameStart := 0
    if localName.Length > 0 {
        nameStart = builder.AddToken(localName)
    }

    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)
    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    access := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
    return MethodBodyFactsWrapValueInBody(builder, access, nameStart, localName)
}

// `{ return (<receiver>).<member> }` — the same access under ONE parenthesis, so the door's dispatch
// on the OUTER kind is testable rather than argued.
func MethodBodyFactsParenthesisedMemberBody(receiverName: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)
    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    access := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
    parenthesised := builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(access))
    return MethodBodyFactsWrapValueInBody(builder, parenthesised, 0, "")
}

// `{ return <receiver>[<selector>].<member> }` where the selector is either an int LITERAL or a
// `<literal> + <literal>` BINARY. The pair is what separates a refusal that belongs to the SELECTOR
// from one that belongs to the member access.
func MethodBodyFactsIndexedMemberBody(receiverName: string, memberName: string, binarySelector: bool): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.IdentifierExpression(), receiverName)
    selector := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "0")
    if binarySelector {
        operatorStart := builder.AddToken("+")
        right := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), "1")
        selector = builder.AddNode(ColumnarExpressionNodeKind.BinaryExpression(), operatorStart, 1, operatorStart, 1, ColumnarRangePlannerChildren2(selector, right))
    }

    access := builder.AddNode(ColumnarExpressionNodeKind.IndexAccessExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren2(receiver, selector))
    memberStart := builder.AddToken(memberName)
    root := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(access))
    return MethodBodyFactsWrapValueInBody(builder, root, 0, "")
}

// `{ return <literal>.<member> }` — a SCALAR-LITERAL receiver, which can only type through
// `ColumnarInstanceMemberPlanner.TryGetComposedReceiverType`. It is the door's reachability witness
// for `S3`.
func MethodBodyFactsLiteralReceiverMemberBody(literalText: string, memberName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    receiver := builder.AddLeaf(ColumnarExpressionNodeKind.StringLiteralExpression(), literalText)
    builder.AddToken(".")
    memberStart := builder.AddToken(memberName)
    access := builder.AddNode(ColumnarExpressionNodeKind.MemberAccessExpression(), memberStart, memberName.Length, 0, builder.Source.Length, ColumnarRangePlannerChildren1(receiver))
    return MethodBodyFactsWrapValueInBody(builder, access, 0, "")
}

// `{ return <owner>.<member> }` with an IDENTIFIER owner — the shape the cascade's SEVENTH arm owns.
func MethodBodyFactsQualifiedMemberBody(ownerName: string, memberName: string): ColumnarRangePlannerTestTree {
    return MethodBodyFactsMemberBody(ownerName, memberName, "")
}

// The driver over a builder-made tree with ONE parameter binding, which is what every member-access
// root over a bound receiver needs.
func MethodBodyFactsPlanMemberBody(tree: ColumnarRangePlannerTestTree, returnType: Type, name: string, ordinal: int, parameterType: Type, plan: ColumnarCodePlan): bool {
    return ColumnarMethodBodyPlanner.TryPlanBody(
        tree.Nodes,
        tree.Source,
        tree.Root,
        returnType,
        false,
        MethodBodyFactsOrdinals(name, ordinal),
        MethodBodyFactsTypes(name, parameterType),
        MethodBodyFactsLocals(),
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
        new Dictionary<string, Type>(StringComparer.Ordinal),
        false,
        new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal),
        plan,
        null
    )
}

// ---- BLOCK 63 — THE MEMBER-ACCESS ROOT IN RETURN POSITION (class M, 015-B14) ----
//
// The FIRST claimed kind two cascade arms admit. `ColumnarExternalStaticMemberPlanner.MayPlanRoot`
// and `ColumnarInstanceMemberPlanner.MayPlanRoot` are the same unqualified `kind == MemberAccess`
// test, and `ColumnarRangeIndexPlanner.TryEmitFromFacts` asks the first at its SEVENTH arm and the
// second at its EIGHTH — so the door asks both, in that order, and claims only the second. The rows
// below are the instance-member owner's own root sequence plus the driver's `ret`, which is what
// makes them byte-identical BY CONSTRUCTION rather than by imitation.
test "the door claims an SZ-array Length root and writes the owner's three rows" {
    tree := MethodBodyFactsMemberBody("values", "Length", "")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanMemberBody(tree, typeof(int), "values", 0, typeof(byte[]), plan)

    assert plan.OperationCount == 4
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldlen()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.ConvI4()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ret()

    // The kind moved sides, and the partition still holds for it.
    assert ColumnarMethodBodyPlanner.IsClaimedExpressionKind(ColumnarExpressionNodeKind.MemberAccessExpression())
    assert !ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.MemberAccessExpression())
}

// The runtime-resolver receiver class, and the OTHER opcode: a reference receiver's property getter is
// `callvirt`, not `ldlen`. Two claim shapes through one arm.
test "the door claims a string member root through the runtime resolver" {
    tree := MethodBodyFactsMemberBody("text", "Length", "")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanMemberBody(tree, typeof(int), "text", 0, typeof(string), plan)

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()
}

// The claim reaches BOTH doors, as every claimed kind before it does: `TryAppendLocalDeclaration` and
// `TryAppendReturnValue` share one dispatcher, and a widening that reached only one would be a silent
// asymmetry nothing else measures. The declaration body carries the extra `stloc`/`ldloc` pair.
test "the member-access claim reaches the initializer door as well as the return door" {
    tree := MethodBodyFactsMemberBody("values", "Length", "count")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanMemberBody(tree, typeof(int), "values", 0, typeof(byte[]), plan)

    assert plan.OperationCount == 6
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldlen()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.ConvI4()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Stloc()
    assert plan.OpCodeValues[4] == ColumnarCodePlanContract.Ldloc()
    assert plan.OpCodeValues[5] == ColumnarCodePlanContract.Ret()
    assert plan.PlanLocalCount == 1
}

// THE CLAIM RULE IS STILL TYPE EQUALITY. `values.Length` is `int` and nothing else, so a `long`
// function carrying the identical expression declines — the host's `conv.i8` is not a row this door
// promises.
test "a member-access root whose type is not the return type declines the body" {
    tree := MethodBodyFactsMemberBody("values", "Length", "")
    plan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanMemberBody(tree, typeof(long), "values", 0, typeof(byte[]), plan)
}

// ⚠ THIS BLOCK WAS A DECLINE UNTIL `015-B16` AND IS NOW A CLAIM, AND ITS OLD COMMENT WAS WRONG ABOUT
// THE HOST. It read: *"the door dispatches on the OUTER kind, which is the parenthesis policy it
// already had. `(values).Length` is kind 7 at its root; the instance-member owner's own
// `UnwrapParentheses` is reached through its root facade, not through this dispatcher, so the
// parenthesised form is the parenthesis owner's shape."* The last clause is false of the HOST:
// `FacadeRootMayNeedFacts` unwraps before the cascade and `ColumnarInstanceMemberPlanner.MayPlanRoot`
// unwraps again, so the host claims `(values.Length)` at the OUTER node through that same owner. The
// door's kind-7 arm now dispatches the CHILD into the same owner's `TryAppendRoot`, which unwraps too
// — so the ROWS are the plain member-access rows, with NO row for the parenthesis, and the body is
// claimed. (The tree here is `Parenthesized[MemberAccess]`; `(values).Length` is the OTHER shape,
// `MemberAccess[Parenthesized[Identifier]]`, whose root is kind 8 and which `015-B14` already claimed.)
test "a parenthesised member-access root is claimed and costs no row of its own" {
    tree := MethodBodyFactsParenthesisedMemberBody("values", "Length")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanMemberBody(tree, typeof(int), "values", 0, typeof(byte[]), plan)
    assert !ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.ParenthesizedExpression())

    // The unparenthesised twin's rows, exactly: `ldarg; ldlen; conv.i4; ret`.
    assert plan.OperationCount == 4
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldarg()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ldlen()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.ConvI4()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ret()

    // And the claim rule is still type EQUALITY through the parenthesis: `long` declines.
    widened := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanMemberBody(MethodBodyFactsParenthesisedMemberBody("values", "Length"), typeof(long), "values", 0, typeof(byte[]), widened)
}

// ---- BLOCK 64 — `S3` IS REACHED, AND THE ROOT'S SURFACE IS WHAT LIMITS IT (015-B14) ----
//
// `ColumnarInstanceMemberPlanner.TryGetComposedReceiverType` — `S3` — is called ONLY from `ClaimsRoot`,
// and `ClaimsRoot` only from the cascade's eighth arm and, since this slice, from the door. `015-B12`
// and `015-B13` both reported it STRUCTURALLY UNREACHED from a claimed body; that reporting is correct
// up to this slice and false afterwards, and these two bodies are the measurement rather than the claim.
//
// A STRING-LITERAL receiver types through NOTHING ELSE: `TryGetReceiverType` wants an identifier, so the
// literal arm of `S3` is the only route to a receiver type at all.
test "the door reaches the composed-receiver type side through a literal receiver" {
    tree := MethodBodyFactsLiteralReceiverMemberBody("\"abc\"", "Length")
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()
}

// ⚠ AND THE ROOT'S SURFACE IS STILL THE PLAIN ONE, WHICH IS NOW A PRODUCTION GUARD RATHER THAN A
// SYMMETRY ARGUMENT. `values[0].Length` claims and `values[0 + 1].Length` declines, and the pair proves
// the decline belongs to the SELECTOR and not to the member access. Widening `S3` alone would make the
// TYPE side answer yes where the APPEND side answers no — and in the CASCADE that combination sets
// `nsharpOwned` and then returns false, which declines the WHOLE FUNCTION instead of falling back to
// the host. `015-B11`'s `C7` is the control that walks it.
test "the member-access root keeps the plain surface at the door as well as at the cascade" {
    ordinary := MethodBodyFactsIndexedMemberBody("names", "Length", false)
    ordinaryPlan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanMemberBody(ordinary, typeof(int), "names", 0, typeof(string[]), ordinaryPlan)

    binary := MethodBodyFactsIndexedMemberBody("names", "Length", true)
    binaryPlan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanMemberBody(binary, typeof(int), "names", 0, typeof(string[]), binaryPlan)
}

// ---- BLOCK 65 — THE CASCADE'S ORDER, AND BOTH OF ITS ARMS (class X, 015-B14 → 015-B15) ----
//
// Kind 8 is the ONE kind two cascade arms admit: `ColumnarExternalStaticMemberPlanner.MayPlanRoot` and
// `ColumnarInstanceMemberPlanner.MayPlanRoot` are the same unqualified `kind == MemberAccess` test, and
// `ColumnarRangeIndexPlanner.TryEmitFromFacts` asks the first at arm SEVEN and the second at arm EIGHT.
// `015-B14` claimed only the second and REFUSED the first, into a scratch plan; `015-B15` gives the
// first owner its own `TryAppendRoot` and the refusal becomes a CLAIM. Door kind 8 is CLOSED — there
// is no scratch plan and no refusal left in the arm.
//
// ⚠ THE ORDER IS STILL ASSERTED, NOT ASSUMED. The two owners' claim sets are disjoint at this tip —
// the external-static owner needs `!bindings.IsValueBinding(root)` while every receiver `ClaimsRoot`
// can type through `TryGetReceiverType` IS a value binding, and four of `TryGetComposedReceiverType`'s
// five arms are shapes `TryGetQualifiedName` refuses outright — so this block pins BOTH halves: that
// the seventh arm owns the root, that the eighth does NOT, and that the rows the door writes are
// therefore unambiguously the seventh arm's.
test "the door claims the member-access roots the cascade's external-static arm owns" {
    tree := MethodBodyFactsQualifiedMemberBody("StringComparison", "Ordinal")
    ExternalStampScope(tree, "import System")
    statement := tree.Nodes.Child(tree.Root, 0)
    access := tree.Nodes.Child(statement, 0)
    assert tree.Nodes.Kind(access) == ColumnarExpressionNodeKind.MemberAccessExpression()

    scratch := new ColumnarCodePlan()
    staticType := typeof(int)
    assert ColumnarExternalStaticMemberPlanner.TryGetType(tree.Nodes, tree.Source, access, MethodBodyFactsEmptyBindings(), scratch, out staticType)
    assert staticType.FullName == "System.StringComparison"

    // The EIGHTH arm refuses it, so the rows below belong to the seventh and to nothing else.
    assert !ColumnarInstanceMemberPlanner.ClaimsRoot(tree.Nodes, tree.Source, access, MethodBodyFactsEmptyBindings())

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, staticType, MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    // An enum member is a LITERAL field, so the owner reconstructs it rather than loading it:
    // `TryAppendLiteralField`'s enum arm is `Convert.ToInt32(field.GetValue(null))` + `ldc.i4`.
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()
    assert plan.Int32Count == 1
    assert plan.Int32Values[0] == 4
    assert plan.FieldCount == 0
    assert plan.MethodCount == 0
    assert plan.OpenFragmentCount == 0
    assert plan.FragmentParentIndices[0] == -1
}

// THE OTHER TWO APPENDS THIS OWNER HAS, AND THEY ARE THE ONES THE CORPUS ACTUALLY REACHES. Its five
// live corpus bodies are four static PROPERTIES (`call`) and one static readonly FIELD (`ldsfld`);
// the literal arm above is reached only by probes. Both rows are legal in the door's schema by
// construction rather than by luck: `AppendFieldInstruction` admits `Ldsfld` under
// `AllowsScalarOrMethodBodyInstructions()`, and the method-body height model's `ApplyStaticField`
// demands a NON-literal static field — which a literal field never reaches, because it becomes an
// `ldc.i4`/`ldc.i8` instead.
test "the door claims an external static property root and writes the owner's call" {
    tree := MethodBodyFactsQualifiedMemberBody("Environment", "NewLine")
    ExternalStampScope(tree, "import System")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(string), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    assert plan.SchemaVersion == ColumnarCodePlanContract.MethodBodySchemaVersion()
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()
    assert plan.MethodCount == 1
    assert plan.Methods[0].get_ReturnType() == typeof(string)
    assert plan.PlanLocalCount == 0

    method := MethodBodyFactsDynamicMethod("NSharpB15StaticPropertyBody", typeof(string))
    ColumnarCodePlanExecutor.ExecuteMethodBody(plan, method.GetILGenerator())
    target: object? = null
    assert Convert.ToString(method.Invoke(target, MethodBodyFactsNoArguments()), CultureInfo.InvariantCulture) == Environment.NewLine
}

test "the door claims an external static field root and writes the owner's ldsfld" {
    tree := MethodBodyFactsQualifiedMemberBody("OpCodes", "Ldsfld")
    ExternalStampScope(tree, "import System.Reflection.Emit")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(OpCode), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldsfld()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Ret()
    assert plan.FieldCount == 1
    assert !plan.Fields[0].get_IsLiteral()
    assert plan.Fields[0].get_IsStatic()
    assert plan.Fields[0].get_DeclaringType() == typeof(OpCodes)
}

// THE CLAIM REACHES BOTH DOORS, as every claimed kind before it does: `TryAppendLocalDeclaration` and
// `TryAppendReturnValue` share one dispatcher, and a widening that reached only one would be a silent
// asymmetry nothing else measures.
test "the external static claim reaches the initializer door as well as the return door" {
    tree := MethodBodyFactsMemberBody("Environment", "NewLine", "nl")
    ExternalStampScope(tree, "import System")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(string), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    assert plan.OperationCount == 4
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Stloc()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ldloc()
    assert plan.OpCodeValues[3] == ColumnarCodePlanContract.Ret()
    assert plan.PlanLocalCount == 1
}

// THE CLAIM RULE IS STILL TYPE EQUALITY. `Environment.NewLine` is `string` and nothing else, so an
// `object` function carrying the identical expression declines — the host's widening is not a row
// this door promises.
test "an external static root whose type is not the return type declines the body" {
    tree := MethodBodyFactsQualifiedMemberBody("Environment", "NewLine")
    ExternalStampScope(tree, "import System")

    plan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(tree, typeof(object), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    // ⚠ AND THE DECLINE LEAVES THE PLAN HALF-BUILT RATHER THAN EMPTY, WHICH IS THE DRIVER'S WRITTEN
    // CONTRACT AND NOT AN ACCIDENT: `TryPlanBody` appends the value's rows and only THEN compares
    // `valueType` with `returnType`, so the caller is expected to discard a declined plan. The `call`
    // row is here; the `ret` is not.
    assert plan.OperationCount == 1
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Call()
}

// ⚠ THE ARM OFFERS **ONE OPEN PLAN TO TWO OWNERS**, WHICH NO DOOR ARM BEFORE IT DOES, AND
// `ColumnarCodePlan.Rollback` IS WHAT MAKES THE RETRY LEGAL RATHER THAN A CRASH. In the CASCADE each
// owner's `Plan` calls `PrepareV3` and the second call resets the plan; at the door there is no
// reset. A string-literal receiver is the shape that walks it: `TryGetQualifiedName` refuses a
// literal outright, so the seventh arm opens a fragment and rolls back, and the eighth then claims
// the SAME plan through `TryGetComposedReceiverType`'s literal arm. Without `Rollback`'s
// `Status = NotOwned` the second owner's input gate would THROW instead of appending.
test "a declined external static root leaves one open plan fit for the next owner" {
    tree := MethodBodyFactsLiteralReceiverMemberBody("\"abc\"", "Length")
    statement := tree.Nodes.Child(tree.Root, 0)
    access := tree.Nodes.Child(statement, 0)

    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    declinedType := typeof(int)
    assert !ColumnarExternalStaticMemberPlanner.TryAppendRoot(tree.Nodes, tree.Source, access, MethodBodyFactsEmptyBindings(), plan, out declinedType)

    assert plan.OperationCount == 0
    assert plan.FragmentCount == 0
    assert plan.OpenFragmentCount == 0
    assert plan.Status == ColumnarFragmentPlanStatus.NotOwned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Building
    assert plan.ResultType == null

    claimedType := typeof(int)
    assert ColumnarInstanceMemberPlanner.TryAppendRoot(tree.Nodes, tree.Source, access, MethodBodyFactsEmptyBindings(), plan, out claimedType)
    assert claimedType == typeof(int)
    assert plan.OperationCount == 2
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldstr()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Callvirt()
}

// ---- BLOCK 66 — THE PARENTHESIS ROOT (class G, 015-B16) ----
//
// The door's SECOND claimed kind with no planner of its own. The host's arm is one line
// (`case 7: return EmitExpression(Child(idx, 0), out type);`) and the door's is a child-count guard
// plus one recursion through the same dispatcher the enclosing position used.
//
// ⚠ THE PROPERTY THAT MATTERS IS THAT THE PARENTHESIS COSTS NO ROW. A kind-7 node contributes no
// opcode and no fragment of its own: the rows a claimed `( <x> )` plans are the rows `<x>` plans, at
// the same indices and in the same order. That is what makes the arm byte-identical against BOTH host
// routes — `case 7`, and the cascade owner that claims the OUTER node because
// `FacadeRootMayNeedFacts` and every `MayPlanRoot` unwrap first.
func MethodBodyFactsParenthesise(builder: ColumnarRangePlannerNodeBuilder, inner: int): int {
    return builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(inner))
}

// `{ return (<literal>) }` and `{ return ((<literal>)) }` — the nesting the recursion handles.
func MethodBodyFactsParenthesisedLiteralBody(text: string, depth: int): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    node := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), text)
    i := 0
    while i < depth {
        node = MethodBodyFactsParenthesise(builder, node)
        i = i + 1
    }
    return MethodBodyFactsWrapValueInBody(builder, node, 0, "")
}

test "the parenthesis root claims its child's rows and contributes none of its own" {
    bare := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsParenthesisedLiteralBody("5", 0), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), bare)

    single := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsParenthesisedLiteralBody("5", 1), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), single)

    // THE ROWS ARE THE SAME ROWS, not merely the same count.
    assert single.OperationCount == bare.OperationCount
    assert single.OpCodeValues[0] == bare.OpCodeValues[0]
    assert single.OpCodeValues[1] == bare.OpCodeValues[1]
    assert single.FragmentCount == bare.FragmentCount

    // And the recursion nests: three parentheses are still the same two rows.
    nested := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsParenthesisedLiteralBody("5", 3), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), nested)
    assert nested.OperationCount == bare.OperationCount
    assert nested.OpCodeValues[0] == bare.OpCodeValues[0]
}

// A kind-7 node with anything other than ONE child is a shape the host's `Child(idx, 0)` would read
// past; the door DECLINES it. A narrowing, never a divergence — the guard is the arm's own and the
// host does not write it.
func MethodBodyFactsEmptyParenthesisBody(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    empty := builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression(), -1, 0, 0, builder.Source.Length, new int[](0))
    return MethodBodyFactsWrapValueInBody(builder, empty, 0, "")
}

test "a parenthesis with no child declines the body and leaves the plan untouched" {
    plan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsEmptyParenthesisBody(), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)
    assert plan.OperationCount == 0
}

// THE CHILD IS DISPATCHED, NOT ADMITTED. Kind 7 becoming claimed widens nothing else: a parenthesised
// NULL literal reaches the kind-5 refusal through the same dispatcher and declines the body — which is
// also the only safe answer at a tip where the HOST cannot compile `return (null)` at all (`NL103`,
// `emit.expression.unhandled-kind`, node kind 5).
func MethodBodyFactsParenthesisedNullBody(): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    literal := builder.AddLeaf(ColumnarExpressionNodeKind.NullLiteralExpression(), "null")
    return MethodBodyFactsWrapValueInBody(builder, MethodBodyFactsParenthesise(builder, literal), 0, "")
}

test "a parenthesised declined kind is still declined through the parenthesis" {
    plan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsParenthesisedNullBody(), typeof(string), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)
    assert plan.OperationCount == 0
    assert ColumnarMethodBodyPlanner.IsDeclinedExpressionKind(ColumnarExpressionNodeKind.NullLiteralExpression())
}

// THE CLAIM REACHES BOTH DOORS, as every claimed kind before it does. The RETURN door runs
// `IsHostAdoptedReturnShape` first and the INITIALIZER door does not, and for kind 7 that predicate
// must NOT unwrap: the host's `TryEmitIntLiteralAsType` reads the node kind unwrapped too, so
// `return (-5)` is `ldc.i4.5; neg` on BOTH sides while `return -5` is the adopted `ldc.i4.s -5` on
// both. Refusing `(-5)` here would refuse a shape the host does not adopt.
func MethodBodyFactsParenthesisedNegativeLiteralBody(text: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    operatorStart := builder.AddToken("-")
    literal := builder.AddLeaf(ColumnarExpressionNodeKind.IntLiteralExpression(), text)
    unary := builder.AddNode(ColumnarExpressionNodeKind.UnaryExpression(), operatorStart, 1, 0, builder.Source.Length, ColumnarRangePlannerChildren1(literal))
    return MethodBodyFactsWrapValueInBody(builder, MethodBodyFactsParenthesise(builder, unary), 0, "")
}

test "the parenthesised negative literal is claimed in return position with the ordinary unary rows" {
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsParenthesisedNegativeLiteralBody("5"), typeof(int), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    // `ldc.i4 5; neg; ret` — the ORDINARY unary lowering, not the pre-pass's pre-negated one.
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.LdcI4()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Neg()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()

    // And the pre-pass predicate is untouched: it still refuses the BARE shape and it does NOT unwrap.
    bare := MethodBodyFactsParenthesisedNegativeLiteralBody("5")
    bareStatement := bare.Nodes.Child(bare.Root, 0)
    parenthesis := bare.Nodes.Child(bareStatement, 0)
    assert !ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(bare.Nodes, bare.Source, parenthesis)
    assert ColumnarMethodBodyPlanner.IsHostAdoptedReturnShape(bare.Nodes, bare.Source, bare.Nodes.Child(parenthesis, 0))
}

// ---- BLOCK 67 — THE TYPEOF ROOT (class Y, 015-B16) ----
//
// The cascade's FIFTH arm, and the only UNCONDITIONAL one:
// `nsharpOwned = true; return ColumnarTypeOfPlanner.TryEmit(…)` — no `MayPlanRoot`-then-`ClaimsRoot`
// pair, no fall-through to a second owner. That is what made kind 55 separable while the composed
// instance-member receiver (the EIGHTH arm) is not: an unplannable `typeof` root already declines the
// whole FUNCTION on the host side, so a door decline can only narrow the BODY.
//
// The claim is the owner's own root sequence, factored out of `ColumnarTypeOfPlanner.Plan` by the
// `015-B6`/`015-B7`/`015-B14`/`015-B15` move for the FOURTH time — and unlike `015-B15`'s owner this
// one KEEPS the `try`/`catch`, because its `Plan` carried one.
// ⚠ THE TYPE CHILD IS KIND 0, NOT AN IDENTIFIER. `TryBuildTypeCanonical` reads the embedded type
// SUBTREE as semantic input rather than as an expression, and the owner's own tests spell the simple
// case as `AddLeaf(0, name)`. A kind-6 child builds no canonical and the root declines — measured, not
// assumed: the first version of this helper used `IdentifierExpression()` and all four blocks failed.
func MethodBodyFactsTypeOfBody(typeName: string): ColumnarRangePlannerTestTree {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    name := builder.AddLeaf(0, typeName)
    builder.AddToken(")")
    node := builder.AddNode(ColumnarExpressionNodeKind.TypeOfExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(name))
    return MethodBodyFactsWrapValueInBody(builder, node, 0, "")
}

test "the typeof root is claimed and plans the ldtoken pair the cascade plans" {
    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(MethodBodyFactsTypeOfBody("int"), typeof(Type), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)

    // `ldtoken int32; call Type.GetTypeFromHandle; ret` — three rows and no more.
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldtoken()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()
}

// THE FACTORING IS ASSERTED, NOT ASSUMED: the sequence the door enters is the sequence `Plan` runs.
// `Plan` wraps `TryAppendRoot` in `PrepareV3`/`CompleteV3` and nothing else, so a schema-v3 plan and a
// method-body plan must carry the SAME rows for the same node.
test "the typeof root sequence is the same rows through Plan and through the door" {
    tree := MethodBodyFactsTypeOfBody("int")
    statement := tree.Nodes.Child(tree.Root, 0)
    value := tree.Nodes.Child(statement, 0)

    scalar := new ColumnarCodePlan()
    assert ColumnarTypeOfPlanner.Plan(tree.Nodes, tree.Source, value, MethodBodyFactsEmptyBindings(), scalar) == ColumnarFragmentPlanStatus.Planned

    body := new ColumnarCodePlan()
    body.PrepareMethodBody()
    bodyType := typeof(Type)
    assert ColumnarTypeOfPlanner.TryAppendRoot(tree.Nodes, tree.Source, value, MethodBodyFactsEmptyBindings(), body, out bodyType)
    assert bodyType == typeof(Type)

    assert body.OperationCount == scalar.OperationCount
    assert body.OpCodeValues[0] == scalar.OpCodeValues[0]
    assert body.OpCodeValues[1] == scalar.OpCodeValues[1]
    assert body.FragmentCount == scalar.FragmentCount
}

// A ROOT THE OWNER CANNOT RESOLVE DECLINES AND LEAVES THE PLAN PRISTINE — the `Rollback` contract the
// factored sequence inherits, and the reason a decline here narrows the body rather than corrupting a
// plan another owner may still be offered.
test "an unresolvable typeof root declines and rolls the plan back to nothing" {
    tree := MethodBodyFactsTypeOfBody("NoSuchTypeName")
    statement := tree.Nodes.Child(tree.Root, 0)
    value := tree.Nodes.Child(statement, 0)

    plan := new ColumnarCodePlan()
    plan.PrepareMethodBody()
    resultType := typeof(Type)
    assert !ColumnarTypeOfPlanner.TryAppendRoot(tree.Nodes, tree.Source, value, MethodBodyFactsEmptyBindings(), plan, out resultType)

    assert plan.OperationCount == 0
    assert plan.FragmentCount == 0
    assert plan.OpenFragmentCount == 0
    assert plan.Status == ColumnarFragmentPlanStatus.NotOwned
    assert plan.Lifecycle == ColumnarCodePlanLifecycle.Building

    // And the DOOR answers that decline by declining the body, not by crashing.
    bodyPlan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsTypeOfBody("NoSuchTypeName"), typeof(Type), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), bodyPlan)
}

// THE CLAIM RULE IS STILL TYPE EQUALITY: `typeof(T)` is `System.Type` and nothing else, so a function
// declared to return `object` is the HOST's.
test "a typeof root whose type is not the return type declines the body" {
    plan := new ColumnarCodePlan()
    assert !MethodBodyFactsPlanCallBody(MethodBodyFactsTypeOfBody("int"), typeof(object), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)
}

// AND THE TWO 015-B16 KINDS COMPOSE: a parenthesised `typeof` root reaches the typeof owner through
// the kind-7 arm, and the rows are the same three.
test "a parenthesised typeof root is claimed through both new arms" {
    builder := new ColumnarRangePlannerNodeBuilder()
    builder.AddToken("typeof(")
    name := builder.AddLeaf(0, "int")
    builder.AddToken(")")
    node := builder.AddNode(ColumnarExpressionNodeKind.TypeOfExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(name))
    wrapped := builder.AddNode(ColumnarExpressionNodeKind.ParenthesizedExpression(), -1, 0, 0, builder.Source.Length, ColumnarRangePlannerChildren1(node))
    tree := MethodBodyFactsWrapValueInBody(builder, wrapped, 0, "")

    plan := new ColumnarCodePlan()
    assert MethodBodyFactsPlanCallBody(tree, typeof(Type), MethodBodyFactsNoSourceTypes(), MethodBodyFactsNoSiblings(), plan)
    assert plan.OperationCount == 3
    assert plan.OpCodeValues[0] == ColumnarCodePlanContract.Ldtoken()
    assert plan.OpCodeValues[1] == ColumnarCodePlanContract.Call()
    assert plan.OpCodeValues[2] == ColumnarCodePlanContract.Ret()
}
