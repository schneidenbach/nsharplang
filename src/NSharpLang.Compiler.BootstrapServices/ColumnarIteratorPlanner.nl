namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

// Sub-slice 3a: the DECISION layer of the synchronous iterator (func*) state machine. This planner owns
// every structural decision — element type, field layout, state numbering, member/override identities,
// dispatch shape, and the precise decline classification for shapes it cannot lower. It produces FACTS
// only; sub-slice 3b builds each member body as a schema-4 code plan against exactly these facts, and the
// C# emitter host is mechanical (DefineNestedType/DefineField/DefineMethod/DefineMethodOverride/Execute).
//
// State numbering: 0 = initial (ready to start), 1..N = resume points (one per `yield return`), -1 =
// running (set while MoveNext executes), -2 = done. Field layout order (hoist ordering): the state field,
// the current field, then each captured parameter in signature order, then each hoisted local in first
// declaration order.

public class ColumnarIteratorShape {
    public Supported: bool
    public DeclineSite: string
    public DeclineMessage: string
    public TypeName: string
    public ElementCanonical: string
    public YieldReturnCount: int
    public InitialState: int
    public RunningState: int
    public DoneState: int
    public FieldCount: int
    public FieldNames: string[]
    public FieldCanonicals: string[]
    public FieldRoles: int[]
    public MemberCount: int
    public MemberNames: string[]
    public MemberSignatures: string[]
    public MemberOverrides: string[]

    constructor(
        supported: bool,
        declineSite: string,
        declineMessage: string,
        typeName: string,
        elementCanonical: string,
        yieldReturnCount: int,
        fieldCount: int,
        fieldNames: string[],
        fieldCanonicals: string[],
        fieldRoles: int[],
        memberCount: int,
        memberNames: string[],
        memberSignatures: string[],
        memberOverrides: string[]) {
        Supported = supported
        DeclineSite = declineSite
        DeclineMessage = declineMessage
        TypeName = typeName
        ElementCanonical = elementCanonical
        YieldReturnCount = yieldReturnCount
        InitialState = 0
        RunningState = -1
        DoneState = -2
        FieldCount = fieldCount
        FieldNames = fieldNames
        FieldCanonicals = fieldCanonicals
        FieldRoles = fieldRoles
        MemberCount = memberCount
        MemberNames = memberNames
        MemberSignatures = memberSignatures
        MemberOverrides = memberOverrides
    }
}

// Mutable accumulator for the single forward body walk.
class ColumnarIteratorWalkState {
    public YieldReturnCount: int
    public LocalCount: int
    public LocalNames: string[]
    public LocalCanonicals: string[]
    public Declined: bool
    public DeclineSite: string
    public DeclineMessage: string
    public ParamNames: string[]
    public ParamCanonicals: string[]

    constructor(capacity: int, paramNames: string[], paramCanonicals: string[]) {
        YieldReturnCount = 0
        LocalCount = 0
        LocalNames = new string[](capacity)
        LocalCanonicals = new string[](capacity)
        Declined = false
        DeclineSite = ""
        DeclineMessage = ""
        ParamNames = paramNames
        ParamCanonicals = paramCanonicals
    }

    public func Decline(site: string, message: string) {
        if !Declined {
            Declined = true
            DeclineSite = site
            DeclineMessage = message
        }
    }

    // The canonical type of a bound identifier: a parameter, or a local already declared earlier in the
    // walk. Returns "" when the name is unknown.
    public func LookupCanonical(name: string): string {
        i := 0
        while i < ParamNames.Length {
            if ParamNames[i] == name {
                return ParamCanonicals[i]
            }
            i = i + 1
        }
        i = 0
        while i < LocalCount {
            if LocalNames[i] == name {
                return LocalCanonicals[i]
            }
            i = i + 1
        }
        return ""
    }

    public func AddLocal(name: string, canonical: string) {
        // A parameter/local re-declaration collides with an existing hoist field.
        if LookupCanonical(name) != "" {
            Decline("emit.iterator.unsupported-shape",
                "a hoisted local shadows an existing binding ('" + name + "'); this shape is not yet lowered")
            return
        }
        LocalNames[LocalCount] = name
        LocalCanonicals[LocalCount] = canonical
        LocalCount = LocalCount + 1
    }
}

public class ColumnarIteratorPlanner {
    public static func InitialState(): int { return 0 }
    public static func RunningState(): int { return -1 }
    public static func DoneState(): int { return -2 }

    public static func StateFieldRole(): int { return 0 }
    public static func CurrentFieldRole(): int { return 1 }
    public static func CapturedParameterFieldRole(): int { return 2 }
    public static func HoistedLocalFieldRole(): int { return 3 }

    // Analyze a static top-level func* and produce its state-machine shape facts, or a precise decline.
    public static func AnalyzeShape(
        nodes: ColumnarNodeTable,
        source: string,
        bodyRoot: int,
        funcName: string,
        funcOrdinal: int,
        returnCanonical: string,
        paramNames: string[],
        paramCanonicals: string[],
        typeParamNames: string[],
        isInstance: bool): ColumnarIteratorShape {
        if isInstance {
            return Declined("emit.iterator.instance-unsupported",
                "iterator methods with an instance receiver are not yet lowered")
        }
        if typeParamNames.Length > 0 {
            return Declined("emit.iterator.generic-unsupported",
                "generic iterator functions are not yet lowered")
        }

        // Element-type inference: only a synchronous IEnumerable<X> return is covered; IAsyncEnumerable is
        // the async-iterator slice, and every other sequence return declines.
        sequenceName := SequenceNameOf(returnCanonical)
        element := SequenceElementOf(returnCanonical)
        if UnqualifiedName(sequenceName) == "IAsyncEnumerable" {
            return Declined("emit.iterator.async-unsupported",
                "async iterators (IAsyncEnumerable) are a later slice")
        }
        if element == "" || UnqualifiedName(sequenceName) != "IEnumerable" {
            return Declined("emit.iterator.return-unsupported",
                "only a typed IEnumerable<T> iterator return is lowered, not '" + returnCanonical + "'")
        }
        if NameIsTypeParameter(element, typeParamNames) {
            return Declined("emit.iterator.generic-unsupported",
                "iterators over a generic element type are not yet lowered")
        }

        capacity := nodes.Kinds.Length + 1
        state := new ColumnarIteratorWalkState(capacity, paramNames, paramCanonicals)
        WalkStatement(nodes, source, bodyRoot, state)
        if state.Declined {
            return Declined(state.DeclineSite, state.DeclineMessage)
        }

        return BuildSupportedShape(funcName, funcOrdinal, element, paramNames, paramCanonicals, state)
    }

    static func BuildSupportedShape(
        funcName: string,
        funcOrdinal: int,
        element: string,
        paramNames: string[],
        paramCanonicals: string[],
        state: ColumnarIteratorWalkState): ColumnarIteratorShape {
        fieldCount := 2 + paramNames.Length + state.LocalCount
        fieldNames := new string[](fieldCount)
        fieldCanonicals := new string[](fieldCount)
        fieldRoles := new int[](fieldCount)
        fieldNames[0] = "<>__state"
        fieldCanonicals[0] = "int"
        fieldRoles[0] = StateFieldRole()
        fieldNames[1] = "<>__current"
        fieldCanonicals[1] = element
        fieldRoles[1] = CurrentFieldRole()
        cursor := 2
        p := 0
        while p < paramNames.Length {
            fieldNames[cursor] = paramNames[p]
            fieldCanonicals[cursor] = paramCanonicals[p]
            fieldRoles[cursor] = CapturedParameterFieldRole()
            cursor = cursor + 1
            p = p + 1
        }
        l := 0
        while l < state.LocalCount {
            fieldNames[cursor] = state.LocalNames[l]
            fieldCanonicals[cursor] = state.LocalCanonicals[l]
            fieldRoles[cursor] = HoistedLocalFieldRole()
            cursor = cursor + 1
            l = l + 1
        }

        typeName := "<" + funcName + ">d__" + funcOrdinal.ToString()
        memberNames := BuildMemberNames()
        memberSignatures := BuildMemberSignatures(element)
        memberOverrides := BuildMemberOverrides()

        return new ColumnarIteratorShape(
            true, "", "", typeName, element, state.YieldReturnCount,
            fieldCount, fieldNames, fieldCanonicals, fieldRoles,
            memberNames.Length, memberNames, memberSignatures, memberOverrides)
    }

    // The eight state-machine members plus the constructor: the fixed interface surface of every
    // synchronous iterator. `both Currents` and `both GetEnumerators` are the generic + non-generic
    // interface members.
    static func BuildMemberNames(): string[] {
        names := new string[](8)
        names[0] = ".ctor"
        names[1] = "MoveNext"
        names[2] = "get_Current"
        names[3] = "System.Collections.IEnumerator.get_Current"
        names[4] = "System.Collections.IEnumerator.Reset"
        names[5] = "System.IDisposable.Dispose"
        names[6] = "GetEnumerator"
        names[7] = "System.Collections.IEnumerable.GetEnumerator"
        return names
    }

    static func BuildMemberSignatures(element: string): string[] {
        signatures := new string[](8)
        signatures[0] = "(int):void"
        signatures[1] = "():bool"
        signatures[2] = "():" + element
        signatures[3] = "():object"
        signatures[4] = "():void"
        signatures[5] = "():void"
        signatures[6] = "():IEnumerator<" + element + ">"
        signatures[7] = "():IEnumerator"
        return signatures
    }

    static func BuildMemberOverrides(): string[] {
        overrides := new string[](8)
        overrides[0] = ""
        overrides[1] = "System.Collections.IEnumerator.MoveNext"
        overrides[2] = "System.Collections.Generic.IEnumerator<T>.get_Current"
        overrides[3] = "System.Collections.IEnumerator.get_Current"
        overrides[4] = "System.Collections.IEnumerator.Reset"
        overrides[5] = "System.IDisposable.Dispose"
        overrides[6] = "System.Collections.Generic.IEnumerable<T>.GetEnumerator"
        overrides[7] = "System.Collections.IEnumerable.GetEnumerator"
        return overrides
    }

    static func Declined(site: string, message: string): ColumnarIteratorShape {
        return new ColumnarIteratorShape(
            false, site, message, "", "", 0,
            0, new string[](0), new string[](0), new int[](0),
            0, new string[](0), new string[](0), new string[](0))
    }

    // ---- body walk (single forward pass; collects locals + counts yields + classifies declines) ----

    // Walks one statement and reports whether control can FALL THROUGH to the following statement.
    // Statements after a non-falling statement in a block are dead: they are neither hoisted nor
    // counted, and the body planner drops exactly the same statements — analysis and emission stay in
    // lockstep, so every counted resume state has a reachable, marked label in the MoveNext plan.
    static func WalkStatement(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState): bool {
        if state.Declined {
            return false
        }
        kind := nodes.Kind(node)
        if kind == 25 {
            // Block: stop at the first non-falling child (everything after it is dead code).
            n := 0
            while n < nodes.ChildCount(node) {
                if state.Declined {
                    return false
                }
                if !WalkStatement(nodes, source, nodes.Child(node, n), state) {
                    return false
                }
                n = n + 1
            }
            return true
        }
        if kind == 40 {
            // TypedLocalDeclaration: value span = declared type canonical, child 0 = name, child 1 = init.
            declaredType := nodes.Text(source, node)
            nameNode := nodes.Child(node, 0)
            name := nodes.Text(source, nameNode)
            if nodes.ChildCount(node) >= 2 {
                WalkExpression(nodes, source, nodes.Child(node, 1), state)
            }
            state.AddLocal(name, declaredType)
            return true
        }
        if kind == 24 {
            // VariableDeclaration (`:=`): value span = name, child 0 = initializer (type inferred).
            name := nodes.Text(source, node)
            inferred := "?"
            if nodes.ChildCount(node) >= 1 {
                initNode := nodes.Child(node, 0)
                WalkExpression(nodes, source, initNode, state)
                inferred = InferCanonical(nodes, source, initNode, state)
            }
            if inferred == "?" {
                state.Decline("emit.iterator.unsupported-shape",
                    "the initializer type of local '" + name + "' could not be inferred for hoisting")
                return false
            }
            state.AddLocal(name, inferred)
            return true
        }
        if kind == 23 {
            // ExpressionStatement: only a simple assignment (kind 14) to a bound identifier is lowered.
            if nodes.ChildCount(node) != 1 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported expression statement in an iterator body")
                return false
            }
            inner := nodes.Child(node, 0)
            if nodes.Kind(inner) != 14 || nodes.ChildCount(inner) != 2 {
                state.Decline("emit.iterator.unsupported-shape", "only simple `=` assignments are lowered in an iterator body")
                return false
            }
            target := nodes.Child(inner, 0)
            if nodes.Kind(target) != 6 {
                state.Decline("emit.iterator.unsupported-shape", "an iterator assignment target must be a bound identifier")
                return false
            }
            name := nodes.Text(source, target)
            if state.LookupCanonical(name) == "" {
                state.Decline("emit.iterator.unsupported-shape", "assignment to an unbound identifier '" + name + "'")
                return false
            }
            WalkExpression(nodes, source, nodes.Child(inner, 1), state)
            return true
        }
        if kind == 26 {
            // While [condition, body]: the loop's false-condition exit edge always falls through,
            // whatever the body's own flow does — the body result only drives dead-code dropping.
            if nodes.ChildCount(node) != 2 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported while statement in an iterator body")
                return false
            }
            WalkExpression(nodes, source, nodes.Child(node, 0), state)
            WalkStatement(nodes, source, nodes.Child(node, 1), state)
            return !state.Declined
        }
        if kind == 27 {
            // If [condition, then, else?]: falls through when either branch does (a missing else is a
            // trivially falling branch).
            childCount := nodes.ChildCount(node)
            if childCount < 2 || childCount > 3 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported if statement in an iterator body")
                return false
            }
            WalkExpression(nodes, source, nodes.Child(node, 0), state)
            thenFalls := WalkStatement(nodes, source, nodes.Child(node, 1), state)
            elseFalls := true
            if childCount == 3 {
                elseFalls = WalkStatement(nodes, source, nodes.Child(node, 2), state)
            }
            if state.Declined {
                return false
            }
            return thenFalls || elseFalls
        }
        if kind == 72 {
            // YieldStatement: 1 child = yield return (a resume state, falls through at its resume
            // label), 0 children = yield break (transfers to the shared end label — never falls).
            if nodes.ChildCount(node) == 1 {
                WalkExpression(nodes, source, nodes.Child(node, 0), state)
                state.YieldReturnCount = state.YieldReturnCount + 1
                return true
            }
            return false
        }
        if kind == 29 {
            // Foreach / `for..in`
            state.Decline("emit.iterator.for-in-unsupported",
                "`for..in` inside an iterator body is a later slice")
            return false
        }
        state.Decline("emit.iterator.unsupported-shape",
            "an iterator body statement (node kind " + kind.ToString() + ") is not yet lowered")
        return false
    }

    static func WalkExpression(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState) {
        if state.Declined {
            return
        }
        kind := nodes.Kind(node)
        if kind == 0 || kind == 4 {
            // int / bool literal
            return
        }
        if kind == 6 {
            // identifier — must be bound (parameter or hoisted local)
            name := nodes.Text(source, node)
            if state.LookupCanonical(name) == "" {
                state.Decline("emit.iterator.unsupported-shape", "unbound identifier '" + name + "' in an iterator body")
            }
            return
        }
        if kind == 7 {
            // parenthesized
            if nodes.ChildCount(node) == 1 {
                WalkExpression(nodes, source, nodes.Child(node, 0), state)
            }
            return
        }
        if kind == 12 {
            // binary
            if nodes.ChildCount(node) != 2 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported binary expression in an iterator body")
                return
            }
            if !IsSupportedBinaryOperator(nodes.Text(source, node)) {
                state.Decline("emit.iterator.unsupported-shape",
                    "binary operator '" + nodes.Text(source, node) + "' is not yet lowered in an iterator body")
                return
            }
            WalkExpression(nodes, source, nodes.Child(node, 0), state)
            WalkExpression(nodes, source, nodes.Child(node, 1), state)
            return
        }
        if kind == 9 {
            // call — nested/recursive iterator calls and general calls are later slices
            state.Decline("emit.iterator.nested-unsupported",
                "method calls inside an iterator body are not yet lowered")
            return
        }
        state.Decline("emit.iterator.unsupported-shape",
            "an iterator body expression (node kind " + kind.ToString() + ") is not yet lowered")
    }

    // Simple canonical-string type inference over the covered expression forms: int/bool literals,
    // bound identifiers, parenthesized, and binaries (comparison => bool, otherwise the left operand's type).
    static func InferCanonical(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState): string {
        kind := nodes.Kind(node)
        if kind == 0 {
            return "int"
        }
        if kind == 4 {
            return "bool"
        }
        if kind == 6 {
            return state.LookupCanonical(nodes.Text(source, node))
        }
        if kind == 7 {
            if nodes.ChildCount(node) == 1 {
                return InferCanonical(nodes, source, nodes.Child(node, 0), state)
            }
            return "?"
        }
        if kind == 12 && nodes.ChildCount(node) == 2 {
            op := nodes.Text(source, node)
            if IsComparisonOperator(op) {
                return "bool"
            }
            left := InferCanonical(nodes, source, nodes.Child(node, 0), state)
            if left == "" {
                return "?"
            }
            return left
        }
        return "?"
    }

    static func IsComparisonOperator(op: string): bool {
        return op == "<" || op == ">" || op == "<=" || op == ">="
            || op == "==" || op == "!="
    }

    public static func IsSupportedBinaryOperator(op: string): bool {
        return op == "+" || op == "-" || op == "*" || op == "/" || op == "%"
            || op == "<" || op == ">" || op == "<=" || op == ">="
            || op == "==" || op == "!="
    }

    // ---- return-canonical parsing ----

    static func SequenceNameOf(returnCanonical: string): string {
        openIndex := IndexOfChar(returnCanonical, '<')
        if openIndex <= 0 {
            return returnCanonical
        }
        return returnCanonical.Substring(0, openIndex)
    }

    static func SequenceElementOf(returnCanonical: string): string {
        openIndex := IndexOfChar(returnCanonical, '<')
        if openIndex < 0 || returnCanonical.Length == 0 || returnCanonical[returnCanonical.Length - 1] != '>' {
            return ""
        }
        inner := returnCanonical.Substring(openIndex + 1, returnCanonical.Length - openIndex - 2)
        // A single, non-empty type argument only (multiple arguments are not a sequence element).
        if inner.Length == 0 || IndexOfTopLevelComma(inner) >= 0 {
            return ""
        }
        return inner
    }

    static func UnqualifiedName(name: string): string {
        lastDot := -1
        i := 0
        while i < name.Length {
            if name[i] == '.' {
                lastDot = i
            }
            i = i + 1
        }
        if lastDot >= 0 && lastDot + 1 < name.Length {
            return name.Substring(lastDot + 1)
        }
        return name
    }

    static func NameIsTypeParameter(name: string, typeParamNames: string[]): bool {
        i := 0
        while i < typeParamNames.Length {
            if typeParamNames[i] == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    static func IndexOfChar(value: string, target: char): int {
        i := 0
        while i < value.Length {
            if value[i] == target {
                return i
            }
            i = i + 1
        }
        return -1
    }

    static func IndexOfTopLevelComma(value: string): int {
        depth := 0
        i := 0
        while i < value.Length {
            ch := value[i]
            if ch == '<' {
                depth = depth + 1
            } else if ch == '>' {
                depth = depth - 1
            } else if ch == ',' && depth == 0 {
                return i
            }
            i = i + 1
        }
        return -1
    }
}

// ---- sub-slice 3b: member body-plan generation ----

// The handles the C# host passes back after defining the state-machine type, its fields, and methods
// from the 3a facts. Field handles are parallel to ColumnarIteratorShape.FieldNames (state, current, then
// captured parameters, then hoisted locals), so a body identifier resolves to a field by that name.
public class ColumnarIteratorEmitContext {
    public Nodes: ColumnarNodeTable
    public Source: string
    public BodyRoot: int
    public Shape: ColumnarIteratorShape
    public StateMachineType: Type
    public ElementType: Type
    public FieldNames: string[]
    public Fields: FieldInfo[]
    public Constructor: ConstructorInfo?

    constructor(
        nodes: ColumnarNodeTable,
        source: string,
        bodyRoot: int,
        shape: ColumnarIteratorShape,
        stateMachineType: Type,
        elementType: Type,
        fieldNames: string[],
        fields: FieldInfo[],
        smConstructor: ConstructorInfo? = null) {
        Nodes = nodes
        Source = source
        BodyRoot = bodyRoot
        Shape = shape
        StateMachineType = stateMachineType
        ElementType = elementType
        FieldNames = fieldNames
        Fields = fields
        Constructor = smConstructor
    }

    public func FieldForName(name: string): FieldInfo {
        i := 0
        while i < FieldNames.Length {
            if FieldNames[i] == name {
                return Fields[i]
            }
            i = i + 1
        }
        throw new InvalidOperationException("Iterator state machine has no field named '" + name + "'.")
    }

    // The state machine's `.ctor(int)` handle — required by the clone and factory plans, optional for
    // contracts that exercise only the this-relative member bodies.
    public func RequiredConstructor(): ConstructorInfo {
        handle := Constructor
        if handle == null {
            throw new InvalidOperationException("Iterator emit context carries no state-machine constructor handle.")
        }
        return handle
    }
}

// Mutable state threaded through the recursive MoveNext lowering.
class ColumnarMoveNextEmit {
    public Plan: ColumnarCodePlan
    public Context: ColumnarIteratorEmitContext
    public ThisArg: int
    public StateFieldPool: int
    public ResumeLabels: int[]
    public EndLabel: int
    public NextYield: int

    constructor(
        plan: ColumnarCodePlan,
        context: ColumnarIteratorEmitContext,
        thisArg: int,
        stateFieldPool: int,
        resumeLabels: int[],
        endLabel: int) {
        Plan = plan
        Context = context
        ThisArg = thisArg
        StateFieldPool = stateFieldPool
        ResumeLabels = resumeLabels
        EndLabel = endLabel
        NextYield = 0
    }
}

public class ColumnarIteratorBodyPlanner {
    // MoveNext(): the resumable state machine. A dispatch prologue routes each resume state to its label;
    // state 0 falls through to the body start (state set running = -1); every `yield return` stores current,
    // sets its resume state, returns true, then resumes by resetting to running; `yield break` and the
    // natural body end fall to the shared end label that returns false.
    public static func BuildMoveNextPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        stateFieldPool := plan.AddField(context.FieldForName("<>__state"))

        yieldCount := context.Shape.YieldReturnCount
        resumeLabels := new int[](yieldCount + 1)
        s := 1
        while s <= yieldCount {
            resumeLabels[s] = plan.DefineLabel()
            s = s + 1
        }
        endLabel := plan.DefineLabel()
        emit := new ColumnarMoveNextEmit(plan, context, thisArg, stateFieldPool, resumeLabels, endLabel)

        s = 1
        while s <= yieldCount {
            LoadThis(emit)
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), stateFieldPool)
            EmitInt(emit, s)
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), resumeLabels[s])
            s = s + 1
        }
        // A state that is neither 0 nor a resume point (running/done) has finished.
        LoadThis(emit)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), stateFieldPool)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), endLabel)
        StoreState(emit, ColumnarIteratorPlanner.RunningState())

        EmitStatement(emit, context.BodyRoot)

        plan.AppendMarkLabel(endLabel)
        EmitInt(emit, 0)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(bool))
        return plan
    }

    // get_Current(): return the hoisted current field.
    public static func BuildGetCurrentPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        currentPool := plan.AddField(context.FieldForName("<>__current"))
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), currentPool)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(context.ElementType)
        return plan
    }

    // System.Collections.IEnumerator.get_Current(): the object view of the hoisted current field —
    // a value-type element is boxed, a reference element returns as-is.
    public static func BuildInterfaceGetCurrentPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        currentPool := plan.AddField(context.FieldForName("<>__current"))
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), currentPool)
        if context.ElementType.get_IsValueType() {
            boxTypePool := plan.AddType(context.ElementType)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), boxTypePool)
        }
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(object))
        return plan
    }

    // System.IDisposable.Dispose(): a synchronous iterator with no hoisted finally regions (the only
    // shape this slice lowers) just marks the machine done.
    public static func BuildDisposePlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        statePool := plan.AddField(context.FieldForName("<>__state"))
        donePool := plan.AddInt32(ColumnarIteratorPlanner.DoneState())
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), donePool)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), statePool)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(VoidReturnType())
        return plan
    }

    // System.Collections.IEnumerator.Reset(): the interface contract's canonical iterator behavior —
    // throw NotSupportedException (exactly what C#-compiled iterators do).
    public static func BuildResetPlan(): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        noTypes := new Type[](0)
        resetConstructor := typeof(NotSupportedException).GetConstructor(noTypes)
        if resetConstructor == null {
            throw new InvalidOperationException("The parameterless NotSupportedException constructor was not found.")
        }
        ctorPool := plan.AddConstructor(resetConstructor)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), ctorPool)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Throw())
        plan.CompleteMethodBody(VoidReturnType())
        return plan
    }

    // GetEnumerator(): clone semantics — every call yields a FRESH machine at the initial state with the
    // captured parameters copied from the receiver; hoisted locals and current restart at default.
    public static func BuildGetEnumeratorPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        AppendEnumeratorClone(plan, context)
        plan.CompleteMethodBody(EnumeratorInterfaceTypeOf(context.ElementType))
        return plan
    }

    // System.Collections.IEnumerable.GetEnumerator(): the identical clone body; only the declared result
    // view differs (the non-generic IEnumerator).
    public static func BuildInterfaceGetEnumeratorPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        AppendEnumeratorClone(plan, context)
        plan.CompleteMethodBody(NonGenericEnumeratorType())
        return plan
    }

    // The FACTORY body for the original func* function: construct the machine at the initial state and
    // store each argument into its captured-parameter field (signature order = captured field order).
    public static func BuildFactoryPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        ctorPool := AddStateMachineConstructor(plan, context)
        statePool := plan.AddInt32(ColumnarIteratorPlanner.InitialState())
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), statePool)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), ctorPool)
        ordinal := 0
        i := 0
        while i < context.Shape.FieldRoles.Length {
            if context.Shape.FieldRoles[i] == ColumnarIteratorPlanner.CapturedParameterFieldRole() {
                argTypePool := plan.AddType(context.Fields[i].get_FieldType())
                argPool := plan.AddArgument(ordinal, argTypePool)
                fieldPool := plan.AddField(context.Fields[i])
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argPool)
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldPool)
                ordinal = ordinal + 1
            }
            i = i + 1
        }
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(EnumerableInterfaceTypeOf(context.ElementType))
        return plan
    }

    // Shared clone body: new SM(initial) + copy each captured-parameter field from `this` to the clone.
    // The receiver argument enters the pool only when a captured field exists (pools must stay fully used).
    static func AppendEnumeratorClone(plan: ColumnarCodePlan, context: ColumnarIteratorEmitContext) {
        ctorPool := AddStateMachineConstructor(plan, context)
        statePool := plan.AddInt32(ColumnarIteratorPlanner.InitialState())
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), statePool)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), ctorPool)
        if CapturedFieldCount(context) > 0 {
            smTypeIdx := plan.AddType(context.StateMachineType)
            thisArg := plan.AddArgument(0, smTypeIdx)
            i := 0
            while i < context.Shape.FieldRoles.Length {
                if context.Shape.FieldRoles[i] == ColumnarIteratorPlanner.CapturedParameterFieldRole() {
                    fieldPool := plan.AddField(context.Fields[i])
                    plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
                    plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
                    plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
                    plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldPool)
                }
                i = i + 1
            }
        }
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
    }

    static func CapturedFieldCount(context: ColumnarIteratorEmitContext): int {
        count := 0
        i := 0
        while i < context.Shape.FieldRoles.Length {
            if context.Shape.FieldRoles[i] == ColumnarIteratorPlanner.CapturedParameterFieldRole() {
                count = count + 1
            }
            i = i + 1
        }
        return count
    }

    // The `.ctor(int)` pool entry. The handle is usually an unbaked ConstructorBuilder (no reflectable
    // parameter list), so the planner-owned declared signature travels with it.
    static func AddStateMachineConstructor(plan: ColumnarCodePlan, context: ColumnarIteratorEmitContext): int {
        ctorParams := new Type[](1)
        ctorParams[0] = typeof(int)
        return plan.AddConstructorWithSignature(context.RequiredConstructor(), context.StateMachineType, ctorParams)
    }

    // N# has no `typeof(void)`; resolve the void marker through the runtime type system.
    static func VoidReturnType(): Type {
        voidType := Type.GetType("System.Void")
        if voidType == null {
            throw new InvalidOperationException("System.Void was not found.")
        }
        return voidType
    }

    static func EnumeratorInterfaceTypeOf(elementType: Type): Type {
        definition := Type.GetType("System.Collections.Generic.IEnumerator`1")
        if definition == null {
            throw new InvalidOperationException("System.Collections.Generic.IEnumerator`1 was not found.")
        }
        typeArgs := new Type[](1)
        typeArgs[0] = elementType
        return definition.MakeGenericType(typeArgs)
    }

    static func EnumerableInterfaceTypeOf(elementType: Type): Type {
        definition := Type.GetType("System.Collections.Generic.IEnumerable`1")
        if definition == null {
            throw new InvalidOperationException("System.Collections.Generic.IEnumerable`1 was not found.")
        }
        typeArgs := new Type[](1)
        typeArgs[0] = elementType
        return definition.MakeGenericType(typeArgs)
    }

    static func NonGenericEnumeratorType(): Type {
        enumeratorType := Type.GetType("System.Collections.IEnumerator")
        if enumeratorType == null {
            throw new InvalidOperationException("System.Collections.IEnumerator was not found.")
        }
        return enumeratorType
    }

    static func LoadThis(emit: ColumnarMoveNextEmit) {
        emit.Plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), emit.ThisArg)
    }

    static func EmitInt(emit: ColumnarMoveNextEmit, value: int) {
        idx := emit.Plan.AddInt32(value)
        emit.Plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), idx)
    }

    static func StoreState(emit: ColumnarMoveNextEmit, value: int) {
        LoadThis(emit)
        EmitInt(emit, value)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), emit.StateFieldPool)
    }

    static func FieldPool(emit: ColumnarMoveNextEmit, name: string): int {
        return emit.Plan.AddField(emit.Context.FieldForName(name))
    }

    // Emits one statement and reports whether control can FALL THROUGH past it. The rules mirror
    // WalkStatement exactly: blocks drop dead statements after a non-falling child, an if only emits
    // its join jump/label when the then-branch falls, and a while only emits its back edge when the
    // body falls — so the plan never contains an unreachable row or an unmarked label.
    static func EmitStatement(emit: ColumnarMoveNextEmit, node: int): bool {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        kind := nodes.Kind(node)
        if kind == 25 {
            n := 0
            while n < nodes.ChildCount(node) {
                if !EmitStatement(emit, nodes.Child(node, n)) {
                    return false
                }
                n = n + 1
            }
            return true
        }
        if kind == 40 {
            // typed local declaration: value span = type, child 0 = name, child 1 = init. A declaration
            // without an initializer hoists to a default-valued field — nothing to store.
            if nodes.ChildCount(node) >= 2 {
                name := nodes.Text(source, nodes.Child(node, 0))
                LoadThis(emit)
                EmitExpression(emit, nodes.Child(node, 1))
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, name))
            }
            return true
        }
        if kind == 24 {
            // `:=` local declaration: value span = name, child 0 = init
            name := nodes.Text(source, node)
            LoadThis(emit)
            EmitExpression(emit, nodes.Child(node, 0))
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, name))
            return true
        }
        if kind == 23 {
            // expression statement: a simple `=` assignment (kind 14) to a bound identifier
            assign := nodes.Child(node, 0)
            target := nodes.Child(assign, 0)
            name := nodes.Text(source, target)
            LoadThis(emit)
            EmitExpression(emit, nodes.Child(assign, 1))
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, name))
            return true
        }
        if kind == 26 {
            // while [condition, body]: the back edge only exists when the body can complete.
            condLabel := emit.Plan.DefineLabel()
            afterLabel := emit.Plan.DefineLabel()
            emit.Plan.AppendMarkLabel(condLabel)
            EmitExpression(emit, nodes.Child(node, 0))
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), afterLabel)
            if EmitStatement(emit, nodes.Child(node, 1)) {
                emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
            }
            emit.Plan.AppendMarkLabel(afterLabel)
            return true
        }
        if kind == 27 {
            // if [condition, then, else?]: the join label is defined and jumped to only when the
            // then-branch falls through (otherwise the jump row would be unreachable).
            elseLabel := emit.Plan.DefineLabel()
            EmitExpression(emit, nodes.Child(node, 0))
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), elseLabel)
            thenFalls := EmitStatement(emit, nodes.Child(node, 1))
            afterLabel := -1
            if thenFalls {
                afterLabel = emit.Plan.DefineLabel()
                emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), afterLabel)
            }
            emit.Plan.AppendMarkLabel(elseLabel)
            elseFalls := true
            if nodes.ChildCount(node) == 3 {
                elseFalls = EmitStatement(emit, nodes.Child(node, 2))
            }
            if afterLabel >= 0 {
                emit.Plan.AppendMarkLabel(afterLabel)
            }
            return thenFalls || elseFalls
        }
        if kind == 72 {
            if nodes.ChildCount(node) == 1 {
                EmitYieldReturn(emit, nodes.Child(node, 0))
                return true
            }
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), emit.EndLabel)
            return false
        }
        throw new InvalidOperationException(
            "Iterator MoveNext lowering reached an unsupported statement kind " + kind.ToString() + ".")
    }

    static func EmitYieldReturn(emit: ColumnarMoveNextEmit, valueNode: int) {
        emit.NextYield = emit.NextYield + 1
        resumeState := emit.NextYield
        LoadThis(emit)
        EmitExpression(emit, valueNode)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, "<>__current"))
        StoreState(emit, resumeState)
        EmitInt(emit, 1)
        emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        emit.Plan.AppendMarkLabel(emit.ResumeLabels[resumeState])
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
    }

    static func EmitExpression(emit: ColumnarMoveNextEmit, node: int) {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        kind := nodes.Kind(node)
        if kind == 0 {
            EmitInt(emit, Int32.Parse(nodes.Text(source, node)))
            return
        }
        if kind == 4 {
            if nodes.Text(source, node) == "true" {
                EmitInt(emit, 1)
            } else {
                EmitInt(emit, 0)
            }
            return
        }
        if kind == 6 {
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, nodes.Text(source, node)))
            return
        }
        if kind == 7 {
            EmitExpression(emit, nodes.Child(node, 0))
            return
        }
        if kind == 12 {
            EmitExpression(emit, nodes.Child(node, 0))
            EmitExpression(emit, nodes.Child(node, 1))
            EmitBinaryOperator(emit, nodes.Text(source, node))
            return
        }
        throw new InvalidOperationException(
            "Iterator MoveNext lowering reached an unsupported expression kind " + kind.ToString() + ".")
    }

    static func EmitBinaryOperator(emit: ColumnarMoveNextEmit, op: string) {
        if op == "+" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Add())
        } else if op == "-" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Sub())
        } else if op == "*" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Mul())
        } else if op == "/" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Div())
        } else if op == "%" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Rem())
        } else if op == "<" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Clt())
        } else if op == ">" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Cgt())
        } else if op == "==" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        } else if op == "<=" {
            // a <= b  ==  !(a > b)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Cgt())
            EmitInt(emit, 0)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        } else if op == ">=" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Clt())
            EmitInt(emit, 0)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        } else if op == "!=" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
            EmitInt(emit, 0)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        } else {
            throw new InvalidOperationException("Iterator MoveNext lowering reached an unsupported operator '" + op + "'.")
        }
    }
}
