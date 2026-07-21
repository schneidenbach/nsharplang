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
    // Async-iterator classification facts (`async func*` returning IAsyncEnumerable<T>). IsAsync marks a
    // shape produced by the async classification path; AwaitResumeCount is the number of `await` suspension
    // points in the body. Each await, like each `yield return`, is a resume state — the state machine
    // resumes at its await-resume label after the awaited operation completes. The async state-machine
    // member surface (MoveNextAsync/DisposeAsync/GetAsyncEnumerator) and the awaiter/builder fields are the
    // async EMISSION slice; the classification here computes element type and resume counts only.
    public IsAsync: bool
    public AwaitResumeCount: int

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
        memberOverrides: string[],
        isAsync: bool,
        awaitResumeCount: int) {
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
        IsAsync = isAsync
        AwaitResumeCount = awaitResumeCount
    }
}

// Mutable accumulator for the single forward body walk.
class ColumnarIteratorWalkState {
    public YieldReturnCount: int
    public AwaitCount: int
    // True while classifying an `async func*`: `await` expressions are then legal suspension points
    // (each counts an await-resume state); in a synchronous iterator an `await` declines.
    public IsAsync: bool
    public ForInCount: int
    public EnumeratorCount: int
    public LocalCount: int
    public LocalNames: string[]
    public LocalCanonicals: string[]
    public LocalRoles: int[]
    public Declined: bool
    public DeclineSite: string
    public DeclineMessage: string
    public ParamNames: string[]
    public ParamCanonicals: string[]
    public TypeParamNames: string[]
    // Enclosing-type member facts (instance iterators only; empty otherwise): readable public fields
    // and callable public methods of the receiver's type.
    public MemberFieldNames: string[]
    public MemberFieldCanonicals: string[]
    public MemberMethodNames: string[]
    public MemberMethodReturnCanonicals: string[]

    constructor(
        capacity: int,
        paramNames: string[],
        paramCanonicals: string[],
        typeParamNames: string[],
        memberFieldNames: string[],
        memberFieldCanonicals: string[],
        memberMethodNames: string[],
        memberMethodReturnCanonicals: string[],
        isAsync: bool) {
        YieldReturnCount = 0
        AwaitCount = 0
        IsAsync = isAsync
        ForInCount = 0
        EnumeratorCount = 0
        LocalCount = 0
        LocalNames = new string[](capacity)
        LocalCanonicals = new string[](capacity)
        LocalRoles = new int[](capacity)
        Declined = false
        DeclineSite = ""
        DeclineMessage = ""
        ParamNames = paramNames
        ParamCanonicals = paramCanonicals
        TypeParamNames = typeParamNames
        MemberFieldNames = memberFieldNames
        MemberFieldCanonicals = memberFieldCanonicals
        MemberMethodNames = memberMethodNames
        MemberMethodReturnCanonicals = memberMethodReturnCanonicals
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

    // The canonical of an enclosing-type FIELD (instance mode); "" when unknown.
    public func LookupMemberFieldCanonical(name: string): string {
        i := 0
        while i < MemberFieldNames.Length {
            if MemberFieldNames[i] == name {
                return MemberFieldCanonicals[i]
            }
            i = i + 1
        }
        return ""
    }

    // The return canonical of an enclosing-type METHOD (instance mode); "" when unknown.
    public func LookupMemberMethodReturnCanonical(name: string): string {
        i := 0
        while i < MemberMethodNames.Length {
            if MemberMethodNames[i] == name {
                return MemberMethodReturnCanonicals[i]
            }
            i = i + 1
        }
        return ""
    }

    // Read resolution: parameters and locals first, then enclosing-type fields.
    public func LookupReadCanonical(name: string): string {
        bound := LookupCanonical(name)
        if bound != "" {
            return bound
        }
        return LookupMemberFieldCanonical(name)
    }

    public func NameIsTypeParameter(name: string): bool {
        i := 0
        while i < TypeParamNames.Length {
            if TypeParamNames[i] == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    public func AddLocal(name: string, canonical: string) {
        AddHoistedLocal(name, canonical, ColumnarIteratorPlanner.HoistedLocalFieldRole())
    }

    public func AddHoistedLocal(name: string, canonical: string, role: int) {
        // A local that re-declares a parameter name collides with its captured field.
        p := 0
        while p < ParamNames.Length {
            if ParamNames[p] == name {
                Decline("emit.iterator.unsupported-shape",
                    "a hoisted local shadows an existing binding ('" + name + "'); this shape is not yet lowered")
                return
            }
            p = p + 1
        }
        l := 0
        while l < LocalCount {
            if LocalNames[l] == name {
                // A SAME-TYPED re-declaration (disjoint if/else branches both declaring `value := ...`,
                // as the covered Range shape does) reuses the hoisted slot — each declaration writes the
                // field before any use in its own scope, exactly like release-codegen slot sharing. A
                // re-declaration at a DIFFERENT type cannot share a CLR field.
                if LocalCanonicals[l] == canonical && LocalRoles[l] == role {
                    return
                }
                Decline("emit.iterator.unsupported-shape",
                    "a hoisted local shadows an existing binding ('" + name + "'); this shape is not yet lowered")
                return
            }
            l = l + 1
        }
        LocalNames[LocalCount] = name
        LocalCanonicals[LocalCount] = canonical
        LocalRoles[LocalCount] = role
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
    public static func HoistedEnumeratorFieldRole(): int { return 4 }
    // Async-machine roles: one hoisted TaskAwaiter per await site (role 5, `<>__awaiter{k}` in walk
    // order), the per-pending-call TaskCompletionSource<bool> promise (role 6), the synchronous-step
    // result flag (role 7), and the re-drive Action the suspension path registers (role 8).
    public static func AwaiterFieldRole(): int { return 5 }
    public static func PromiseFieldRole(): int { return 6 }
    public static func ResultFieldRole(): int { return 7 }
    public static func ContinuationFieldRole(): int { return 8 }

    // Analyze a func* and produce its state-machine shape facts, or a precise decline. An INSTANCE
    // method supplies its receiver canonical plus the enclosing type's readable field and callable
    // method facts (public members only — the host filters); the receiver hoists as a `<>__this`
    // captured field so the factory (the method body) stores `ldarg.0` and the clone copies it.
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
        isInstance: bool,
        receiverCanonical: string = "",
        enclosingFieldNames: string[]? = null,
        enclosingFieldCanonicals: string[]? = null,
        enclosingMethodNames: string[]? = null,
        enclosingMethodReturnCanonicals: string[]? = null,
        isAsync: bool = false): ColumnarIteratorShape {
        if isInstance && receiverCanonical == "" {
            return Declined("emit.iterator.instance-unsupported",
                "iterator methods with an instance receiver are not yet lowered")
        }
        if isInstance && typeParamNames.Length > 0 {
            return Declined("emit.iterator.instance-unsupported",
                "generic instance iterator methods are not yet lowered")
        }
        if isAsync && isInstance {
            return Declined("emit.iterator.async-unsupported",
                "async iterator methods with an instance receiver are not yet lowered")
        }
        if isAsync && typeParamNames.Length > 0 {
            return Declined("emit.iterator.async-unsupported",
                "generic async iterator methods are not yet lowered")
        }

        // Element-type inference. A synchronous iterator returns IEnumerable<X>; an `async func*` returns
        // IAsyncEnumerable<X>. The element may be one of the function's own type parameters — the state
        // machine then becomes generic with the parameter flowing into the current/value fields (the host
        // mirrors the type-parameter list onto the SM).
        sequenceName := SequenceNameOf(returnCanonical)
        element := SequenceElementOf(returnCanonical)
        if isAsync {
            if UnqualifiedName(sequenceName) != "IAsyncEnumerable" || element == "" {
                return Declined("emit.iterator.async-return-unsupported",
                    "an async iterator (`async func*`) must return IAsyncEnumerable<T>, not '" + returnCanonical + "'")
            }
        } else {
            if UnqualifiedName(sequenceName) == "IAsyncEnumerable" {
                return Declined("emit.iterator.async-unsupported",
                    "IAsyncEnumerable<T> requires the 'async' modifier on the iterator")
            }
            if element == "" || UnqualifiedName(sequenceName) != "IEnumerable" {
                return Declined("emit.iterator.return-unsupported",
                    "only a typed IEnumerable<T> iterator return is lowered, not '" + returnCanonical + "'")
            }
        }

        capacity := nodes.Kinds.Length + 1
        state := new ColumnarIteratorWalkState(
            capacity, paramNames, paramCanonicals, typeParamNames,
            enclosingFieldNames ?? new string[](0),
            enclosingFieldCanonicals ?? new string[](0),
            enclosingMethodNames ?? new string[](0),
            enclosingMethodReturnCanonicals ?? new string[](0),
            isAsync)
        WalkStatement(nodes, source, bodyRoot, state)
        if state.Declined {
            return Declined(state.DeclineSite, state.DeclineMessage)
        }

        if isAsync {
            return BuildSupportedAsyncShape(funcName, funcOrdinal, element, paramNames, paramCanonicals, state)
        }
        return BuildSupportedShape(
            funcName, funcOrdinal, element, paramNames, paramCanonicals, state,
            isInstance ? receiverCanonical : "")
    }

    static func BuildSupportedShape(
        funcName: string,
        funcOrdinal: int,
        element: string,
        paramNames: string[],
        paramCanonicals: string[],
        state: ColumnarIteratorWalkState,
        receiverCanonical: string): ColumnarIteratorShape {
        receiverCount := 0
        if receiverCanonical != "" {
            receiverCount = 1
        }
        fieldCount := 2 + receiverCount + paramNames.Length + state.LocalCount
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
        if receiverCount == 1 {
            // The captured receiver leads the role-2 fields, so the factory's captured-argument
            // ordinals line up with an instance method's IL arguments (`this` = arg 0, params follow).
            fieldNames[cursor] = "<>__this"
            fieldCanonicals[cursor] = receiverCanonical
            fieldRoles[cursor] = CapturedParameterFieldRole()
            cursor = cursor + 1
        }
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
            fieldRoles[cursor] = state.LocalRoles[l]
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
            memberNames.Length, memberNames, memberSignatures, memberOverrides,
            false, 0)
    }

    // The async state-machine shape (`async func*` returning IAsyncEnumerable<T>). Field layout extends
    // the synchronous hoist order — state, current, captured parameters, hoisted locals — with the async
    // machinery: one TaskAwaiter field per await site (walk order), then the promise, the synchronous-step
    // result flag, and the re-drive continuation. Resume states interleave: the k-th suspension point in
    // body walk order (a `yield return` OR an `await`) resumes at state k+1; MoveNextCore's dispatch treats
    // both kinds identically and the body planner assigns numbers with one shared counter.
    static func BuildSupportedAsyncShape(
        funcName: string,
        funcOrdinal: int,
        element: string,
        paramNames: string[],
        paramCanonicals: string[],
        state: ColumnarIteratorWalkState): ColumnarIteratorShape {
        fieldCount := 2 + paramNames.Length + state.LocalCount + state.AwaitCount + 3
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
            fieldRoles[cursor] = state.LocalRoles[l]
            cursor = cursor + 1
            l = l + 1
        }
        a := 0
        while a < state.AwaitCount {
            fieldNames[cursor] = "<>__awaiter" + a.ToString()
            fieldCanonicals[cursor] = "TaskAwaiter"
            fieldRoles[cursor] = AwaiterFieldRole()
            cursor = cursor + 1
            a = a + 1
        }
        fieldNames[cursor] = "<>__promise"
        fieldCanonicals[cursor] = "TaskCompletionSource<bool>"
        fieldRoles[cursor] = PromiseFieldRole()
        fieldNames[cursor + 1] = "<>__result"
        fieldCanonicals[cursor + 1] = "bool"
        fieldRoles[cursor + 1] = ResultFieldRole()
        fieldNames[cursor + 2] = "<>__continuation"
        fieldCanonicals[cursor + 2] = "Action"
        fieldRoles[cursor + 2] = ContinuationFieldRole()

        typeName := "<" + funcName + ">d__" + funcOrdinal.ToString()
        memberNames := BuildAsyncMemberNames()
        memberSignatures := BuildAsyncMemberSignatures(element)
        memberOverrides := BuildAsyncMemberOverrides()
        return new ColumnarIteratorShape(
            true, "", "", typeName, element, state.YieldReturnCount,
            fieldCount, fieldNames, fieldCanonicals, fieldRoles,
            memberNames.Length, memberNames, memberSignatures, memberOverrides,
            true, state.AwaitCount)
    }

    // The six async state-machine members. MoveNextCore is the plain synchronous-step method (no
    // override): MoveNextAsync drives it directly and the registered continuation re-drives it after an
    // incomplete awaiter completes.
    static func BuildAsyncMemberNames(): string[] {
        names := new string[](6)
        names[0] = ".ctor"
        names[1] = "MoveNextCore"
        names[2] = "MoveNextAsync"
        names[3] = "get_Current"
        names[4] = "DisposeAsync"
        names[5] = "GetAsyncEnumerator"
        return names
    }

    static func BuildAsyncMemberSignatures(element: string): string[] {
        signatures := new string[](6)
        signatures[0] = "(int):void"
        signatures[1] = "():void"
        signatures[2] = "():ValueTask<bool>"
        signatures[3] = "():" + element
        signatures[4] = "():ValueTask"
        signatures[5] = "(CancellationToken):IAsyncEnumerator<" + element + ">"
        return signatures
    }

    static func BuildAsyncMemberOverrides(): string[] {
        overrides := new string[](6)
        overrides[0] = ""
        overrides[1] = ""
        overrides[2] = "System.Collections.Generic.IAsyncEnumerator<T>.MoveNextAsync"
        overrides[3] = "System.Collections.Generic.IAsyncEnumerator<T>.get_Current"
        overrides[4] = "System.IAsyncDisposable.DisposeAsync"
        overrides[5] = "System.Collections.Generic.IAsyncEnumerable<T>.GetAsyncEnumerator"
        return overrides
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
            0, new string[](0), new string[](0), new string[](0),
            false, 0)
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
            // `await <task-expr>` as a bare statement (a unit await) is a suspension point in an async
            // iterator; control falls through to the following statement at the await-resume label.
            if nodes.Kind(inner) == 53 {
                if !state.IsAsync {
                    state.Decline("emit.iterator.unsupported-shape",
                        "`await` is only valid inside an async iterator body")
                    return false
                }
                WalkUnitAwait(nodes, source, inner, state)
                return !state.Declined
            }
            // A bare `<ident>++` / `<ident>--` statement (the classic-for increment clause parses to
            // exactly this shape) — the stepped value is discarded.
            if nodes.Kind(inner) == 44 {
                WalkPostfixStep(nodes, source, inner, state)
                return !state.Declined
            }
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
                if state.LookupMemberFieldCanonical(name) != "" {
                    state.Decline("emit.iterator.unsupported-shape",
                        "assignment to enclosing member '" + name + "' is not lowered in an iterator body (reads only)")
                    return false
                }
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
        if kind == 28 {
            // For [init, cond, incr, body] — the C-style counting loop. Every clause reuses the
            // statement/expression walk unchanged: the init's local hoists like any declaration, the
            // false-condition exit edge always falls through, and the body result only drives
            // dead-code dropping (a non-falling body makes the increment dead — the emit walk skips
            // it, and no admitted increment shape carries resume points or hoists, so the two passes
            // stay in lockstep).
            if nodes.ChildCount(node) != 4 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported for statement in an iterator body")
                return false
            }
            initFalls := WalkStatement(nodes, source, nodes.Child(node, 0), state)
            if state.Declined {
                return false
            }
            WalkExpression(nodes, source, nodes.Child(node, 1), state)
            incrFalls := WalkStatement(nodes, source, nodes.Child(node, 2), state)
            if state.Declined {
                return false
            }
            if !initFalls || !incrFalls {
                // A non-falling initializer or increment (e.g. a clause-slot `yield break`) would leave
                // dead rows after itself — decline the degenerate shape instead.
                state.Decline("emit.iterator.unsupported-shape",
                    "a for initializer or increment that cannot complete is not lowered in an iterator body")
                return false
            }
            WalkStatement(nodes, source, nodes.Child(node, 3), state)
            return !state.Declined
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
            // Foreach / `for..in` [source, body], loop-var name in the value span. A hoisted ARRAY
            // identifier lowers as an index loop; a sequence source (an IEnumerable<X>/List<X>-typed
            // binding, enclosing field, or argument-free member call) hoists its enumerator into a
            // `<>__enum{k}` field inside MoveNext's fault region. Counters and synthetic names are
            // assigned here in walk order, exactly mirrored by the emit walk.
            if nodes.ChildCount(node) != 2 {
                state.Decline("emit.iterator.for-in-unsupported", "unsupported for..in statement in an iterator body")
                return false
            }
            sourceNode := nodes.Child(node, 0)
            sourceKind := nodes.Kind(sourceNode)
            sourceCanonical := ""
            if sourceKind == 6 {
                sourceName := nodes.Text(source, sourceNode)
                boundCanonical := state.LookupCanonical(sourceName)
                if boundCanonical != "" {
                    arrayElement := ArrayElementCanonicalOf(boundCanonical)
                    if arrayElement != "" {
                        if !IsLowerableArrayElementCanonical(arrayElement) {
                            state.Decline("emit.iterator.for-in-unsupported",
                                "array element type '" + arrayElement + "' is not yet lowered in an iterator for..in")
                            return false
                        }
                        state.AddLocal("<>__index" + state.ForInCount.ToString(), "int")
                        state.ForInCount = state.ForInCount + 1
                        state.AddLocal(nodes.Text(source, node), arrayElement)
                        if state.Declined {
                            return false
                        }
                        // The empty-array exit edge always falls through; the body drives dead-code dropping.
                        WalkStatement(nodes, source, nodes.Child(node, 1), state)
                        return !state.Declined
                    }
                    sourceCanonical = boundCanonical
                } else {
                    memberCanonical := state.LookupMemberFieldCanonical(sourceName)
                    if memberCanonical == "" {
                        state.Decline("emit.iterator.unsupported-shape",
                            "unbound identifier '" + sourceName + "' in an iterator body")
                        return false
                    }
                    if ArrayElementCanonicalOf(memberCanonical) != "" {
                        state.Decline("emit.iterator.for-in-unsupported",
                            "`for..in` over a member array ('" + sourceName + "') is a later slice")
                        return false
                    }
                    sourceCanonical = memberCanonical
                }
            } else if sourceKind == 9 {
                // Member-call source: `receiver.Method()` with no arguments, resolved against the
                // enclosing type's method facts (recursion resolves against the method being classified).
                if nodes.ChildCount(sourceNode) != 1 {
                    state.Decline("emit.iterator.for-in-unsupported",
                        "`for..in` over a call with arguments is a later slice")
                    return false
                }
                callee := nodes.Child(sourceNode, 0)
                if nodes.Kind(callee) != 8 || nodes.ChildCount(callee) != 1 {
                    state.Decline("emit.iterator.for-in-unsupported",
                        "`for..in` call sources must be a bound receiver's member call")
                    return false
                }
                receiverNode := nodes.Child(callee, 0)
                if nodes.Kind(receiverNode) != 6
                    || state.LookupReadCanonical(nodes.Text(source, receiverNode)) == "" {
                    state.Decline("emit.iterator.for-in-unsupported",
                        "`for..in` call sources must be a bound receiver's member call")
                    return false
                }
                methodName := nodes.Text(source, callee)
                returnCanonical := state.LookupMemberMethodReturnCanonical(methodName)
                if returnCanonical == "" {
                    state.Decline("emit.iterator.for-in-unsupported",
                        "'" + methodName + "' is not a known enclosing member method for a for..in source")
                    return false
                }
                sourceCanonical = returnCanonical
            } else {
                state.Decline("emit.iterator.for-in-unsupported",
                    "`for..in` sources must be a bound identifier or a member call; other sources are a later slice")
                return false
            }
            enumerableElement := EnumerableElementCanonicalOf(sourceCanonical)
            if enumerableElement == "" {
                state.Decline("emit.iterator.for-in-unsupported",
                    "`for..in` over a non-sequence value ('" + sourceCanonical + "') in an iterator body is a later slice")
                return false
            }
            if state.IsAsync {
                // The guarded try/FAULT enumerator layout and the async try/CATCH step core do not
                // compose yet; async bodies keep the array index loop only.
                state.Decline("emit.iterator.for-in-unsupported",
                    "`for..in` over a sequence source in an async iterator body is a later slice")
                return false
            }
            if state.NameIsTypeParameter(enumerableElement) {
                state.Decline("emit.iterator.for-in-unsupported",
                    "`for..in` over a type-parameter element sequence is a later slice")
                return false
            }
            state.AddHoistedLocal(
                "<>__enum" + state.EnumeratorCount.ToString(),
                "IEnumerator<" + enumerableElement + ">",
                HoistedEnumeratorFieldRole())
            state.EnumeratorCount = state.EnumeratorCount + 1
            state.AddLocal(nodes.Text(source, node), enumerableElement)
            if state.Declined {
                return false
            }
            // The exhausted-enumerator exit edge always falls through, like the array form.
            WalkStatement(nodes, source, nodes.Child(node, 1), state)
            return !state.Declined
        }
        if kind == 73 {
            // AwaitForeachStatement: asynchronous enumeration INSIDE an async iterator body composes two
            // machines and is a later slice (consumer-side await foreach lowering is separate).
            state.Decline("emit.iterator.async-await-unsupported",
                "`await foreach` inside an iterator body is a later slice")
            return false
        }
        if kind == 48 {
            // Throw [exception]: only `throw new <BclException>("literal")` is lowered — the covered
            // examples' guard-clause form (ldstr + newobj(string) + throw). A throw never falls through.
            if nodes.ChildCount(node) != 1 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported throw statement in an iterator body")
                return false
            }
            creation := nodes.Child(node, 0)
            if nodes.Kind(creation) != 15 || nodes.ChildCount(creation) != 2 {
                state.Decline("emit.iterator.unsupported-shape",
                    "only `throw new <BclException>(\"message\")` is lowered in an iterator body")
                return false
            }
            typeNode := nodes.Child(creation, 0)
            messageNode := nodes.Child(creation, 1)
            if nodes.Kind(typeNode) != 0
                || !IsLowerableExceptionName(nodes.Text(source, typeNode))
                || nodes.Kind(messageNode) != 3
                || !IsPlainMessageLiteral(nodes.Text(source, messageNode)) {
                state.Decline("emit.iterator.unsupported-shape",
                    "only `throw new <BclException>(\"message\")` with a plain string literal is lowered in an iterator body")
                return false
            }
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
            // identifier — a parameter, a hoisted local, or (instance mode) a readable enclosing field
            name := nodes.Text(source, node)
            if state.LookupReadCanonical(name) == "" {
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
            op := nodes.Text(source, node)
            if !IsSupportedBinaryOperator(op) {
                state.Decline("emit.iterator.unsupported-shape",
                    "binary operator '" + op + "' is not yet lowered in an iterator body")
                return
            }
            WalkExpression(nodes, source, nodes.Child(node, 0), state)
            WalkExpression(nodes, source, nodes.Child(node, 1), state)
            if state.Declined {
                return
            }
            // The emitted operators are the raw numeric opcodes, so both operands must be the SAME
            // numeric canonical (bool is admitted for equality only). Strings, type parameters, and
            // every other operand type decline rather than lower to a type-wrong opcode.
            left := InferCanonical(nodes, source, nodes.Child(node, 0), state)
            right := InferCanonical(nodes, source, nodes.Child(node, 1), state)
            if !AreLowerableBinaryOperands(left, right, op) {
                state.Decline("emit.iterator.unsupported-shape",
                    "binary operator '" + op + "' over '" + left + "'/'" + right + "' operands is not yet lowered in an iterator body")
            }
            return
        }
        if kind == 53 {
            // `await` reaches WalkExpression only in a VALUE position (initializer, yield value,
            // operand); suspension points are statement-position unit awaits handled by WalkStatement.
            if !state.IsAsync {
                state.Decline("emit.iterator.unsupported-shape",
                    "`await` is only valid inside an async iterator body")
                return
            }
            state.Decline("emit.iterator.async-await-unsupported",
                "`await` in a value position is not yet lowered in an async iterator body")
            return
        }
        if kind == 44 {
            // postfix `++`/`--` in VALUE position (`yield i++`): pushes the pre-step value, then steps
            // the binding — the same target admission as the statement form.
            WalkPostfixStep(nodes, source, node, state)
            return
        }
        if kind == 9 {
            // call — an argument-free string instance call (`s.ToUpper()` and family) is the one
            // admitted shape; nested/recursive iterator calls and general calls are later slices
            if IsAdmittedStringCall(nodes, source, node, state) {
                return
            }
            state.Decline("emit.iterator.nested-unsupported",
                "method calls inside an iterator body are not yet lowered")
            return
        }
        state.Decline("emit.iterator.unsupported-shape",
            "an iterator body expression (node kind " + kind.ToString() + ") is not yet lowered")
    }

    // `<ident>++` / `<ident>--`: a step of a bound (writable) int binding — the only stepped canonical
    // the emitted ldc.i4 arithmetic is correct for. Enclosing member targets stay read-only, exactly
    // like the assignment rule.
    static func WalkPostfixStep(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState) {
        op := nodes.Text(source, node)
        if nodes.ChildCount(node) != 1 || (op != "++" && op != "--") {
            state.Decline("emit.iterator.unsupported-shape", "unsupported postfix mutation in an iterator body")
            return
        }
        target := nodes.Child(node, 0)
        if nodes.Kind(target) != 6 {
            state.Decline("emit.iterator.unsupported-shape",
                "a postfix step target must be a bound identifier in an iterator body")
            return
        }
        name := nodes.Text(source, target)
        canonical := state.LookupCanonical(name)
        if canonical == "" {
            state.Decline("emit.iterator.unsupported-shape",
                "postfix step of an unbound or read-only identifier '" + name + "' in an iterator body")
            return
        }
        if canonical != "int" {
            state.Decline("emit.iterator.unsupported-shape",
                "postfix step over a non-int binding ('" + name + "': '" + canonical + "') is not yet lowered in an iterator body")
        }
    }

    // The admitted value-position call shape: `<string-binding>.<Method>()` with no arguments, where
    // the method is a lowerable zero-argument string instance method. Reads resolve like identifiers
    // (parameters and locals first, then enclosing-type fields).
    static func IsAdmittedStringCall(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState): bool {
        if nodes.ChildCount(node) != 1 {
            return false
        }
        callee := nodes.Child(node, 0)
        if nodes.Kind(callee) != 8 || nodes.ChildCount(callee) != 1 {
            return false
        }
        receiver := nodes.Child(callee, 0)
        if nodes.Kind(receiver) != 6 || state.LookupReadCanonical(nodes.Text(source, receiver)) != "string" {
            return false
        }
        return IsLowerableStringInstanceMethod(nodes.Text(source, callee))
    }

    // Zero-argument string→string instance methods the emit walk resolves via GetMethod(name, none).
    public static func IsLowerableStringInstanceMethod(name: string): bool {
        return name == "ToUpper" || name == "ToLower" || name == "Trim"
    }

    // A statement-position `await <operand>` (a unit await): a suspension point that resumes at its own
    // state, exactly like a `yield return`. Classification counts it and admits exactly the operand the
    // lowering emits — `Task.Delay(<int-expr>)`, the awaited shape the async examples use — so analysis
    // and emission stay in lockstep. Every other operand declines at a precise site.
    static func WalkUnitAwait(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState) {
        if nodes.ChildCount(node) != 1 {
            state.Decline("emit.iterator.async-await-unsupported",
                "malformed await expression in an async iterator body")
            return
        }
        state.AwaitCount = state.AwaitCount + 1
        operand := nodes.Child(node, 0)
        if nodes.Kind(operand) != 9 || nodes.ChildCount(operand) != 2 {
            state.Decline("emit.iterator.async-await-unsupported",
                "only `await Task.Delay(<int>)` awaited operands are lowered in an async iterator body")
            return
        }
        callee := nodes.Child(operand, 0)
        if nodes.Kind(callee) != 8 || nodes.ChildCount(callee) != 1
            || nodes.Text(source, callee) != "Delay"
            || nodes.Kind(nodes.Child(callee, 0)) != 6
            || nodes.Text(source, nodes.Child(callee, 0)) != "Task"
            || state.LookupReadCanonical("Task") != "" {
            state.Decline("emit.iterator.async-await-unsupported",
                "only `await Task.Delay(<int>)` awaited operands are lowered in an async iterator body")
            return
        }
        argNode := nodes.Child(operand, 1)
        WalkExpression(nodes, source, argNode, state)
        if !state.Declined && InferCanonical(nodes, source, argNode, state) != "int" {
            state.Decline("emit.iterator.async-await-unsupported",
                "the Task.Delay argument must be an int-typed expression in an async iterator body")
        }
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
            return state.LookupReadCanonical(nodes.Text(source, node))
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
        if kind == 44 && nodes.ChildCount(node) == 1 {
            // postfix step: the value IS the target's pre-step value.
            stepped := state.LookupCanonical(nodes.Text(source, nodes.Child(node, 0)))
            if stepped == "" {
                return "?"
            }
            return stepped
        }
        if kind == 9 && IsAdmittedStringCall(nodes, source, node, state) {
            return "string"
        }
        return "?"
    }

    static func IsComparisonOperator(op: string): bool {
        return op == "<" || op == ">" || op == "<=" || op == ">="
            || op == "==" || op == "!="
    }

    static func IsNumericCanonical(canonical: string): bool {
        return canonical == "int" || canonical == "long" || canonical == "float" || canonical == "double"
    }

    static func AreLowerableBinaryOperands(left: string, right: string, op: string): bool {
        if left == right && IsNumericCanonical(left) {
            return true
        }
        return left == "bool" && right == "bool" && (op == "==" || op == "!=")
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

    // The element canonical of a single-dimensional array canonical ("int[]" -> "int"); "" otherwise.
    public static func ArrayElementCanonicalOf(canonical: string): string {
        if canonical.Length < 3
            || canonical[canonical.Length - 2] != '['
            || canonical[canonical.Length - 1] != ']' {
            return ""
        }
        return canonical.Substring(0, canonical.Length - 2)
    }

    // The element canonical of an enumerator-lowered sequence source: "IEnumerable<X>" or "List<X>"
    // (List<T> implements IEnumerable<T>, so both route through the same interface calls); "" otherwise.
    public static func EnumerableElementCanonicalOf(canonical: string): string {
        element := GenericArgumentCanonicalOf(canonical, "IEnumerable<")
        if element != "" {
            return element
        }
        return GenericArgumentCanonicalOf(canonical, "List<")
    }

    // The element canonical of a hoisted enumerator field canonical ("IEnumerator<X>" -> "X").
    public static func EnumeratorElementCanonicalOf(canonical: string): string {
        return GenericArgumentCanonicalOf(canonical, "IEnumerator<")
    }

    static func GenericArgumentCanonicalOf(canonical: string, prefix: string): string {
        if canonical.Length <= prefix.Length + 1
            || canonical.Substring(0, prefix.Length) != prefix
            || canonical[canonical.Length - 1] != '>' {
            return ""
        }
        inner := canonical.Substring(prefix.Length, canonical.Length - prefix.Length - 1)
        if inner.Length == 0 || IndexOfChar(inner, '<') >= 0 || IndexOfTopLevelComma(inner) >= 0 {
            return ""
        }
        return inner
    }

    // True when the body contains any yield statement (kind 72) — the structural mark of a generator
    // body, used to classify type-member generators whose modifier facts do not reach the emit host.
    public static func ContainsYield(nodes: ColumnarNodeTable, node: int): bool {
        if nodes.Kind(node) == 72 {
            return true
        }
        c := 0
        while c < nodes.ChildCount(node) {
            if ContainsYield(nodes, nodes.Child(node, c)) {
                return true
            }
            c = c + 1
        }
        return false
    }

    // Array elements the MoveNext lowering has a typed ldelem opcode for.
    public static func IsLowerableArrayElementCanonical(element: string): bool {
        return element == "int" || element == "long" || element == "float" || element == "double"
            || element == "bool" || element == "char" || element == "string"
    }

    // The System-namespace exception constructions the throw lowering resolves (mirrors the C#
    // emitter's BCL exception whitelist for the System namespace).
    public static func IsLowerableExceptionName(name: string): bool {
        simple := SystemUnqualifiedExceptionName(name)
        if simple == "" {
            return false
        }
        return simple == "Exception"
            || simple == "InvalidOperationException"
            || simple == "ArgumentException"
            || simple == "ArgumentNullException"
            || simple == "ArgumentOutOfRangeException"
            || simple == "NotSupportedException"
            || simple == "NotImplementedException"
            || simple == "FormatException"
            || simple == "IndexOutOfRangeException"
            || simple == "InvalidCastException"
            || simple == "TimeoutException"
            || simple == "OverflowException"
            || simple == "DivideByZeroException"
            || simple == "ArithmeticException"
            || simple == "NullReferenceException"
    }

    // A bare exception name, or one qualified exactly by `System.`; "" for any other qualification.
    public static func SystemUnqualifiedExceptionName(name: string): string {
        simple := name
        if name.Length > 7 && name.Substring(0, 7) == "System." {
            simple = name.Substring(7)
        }
        if IndexOfChar(simple, '.') >= 0 {
            return ""
        }
        return simple
    }

    // A plain (non-interpolated) quoted string literal span, exactly what StringLiteralDecoder decodes.
    public static func IsPlainMessageLiteral(text: string): bool {
        return text.Length >= 2 && text[0] == '"' && text[text.Length - 1] == '"'
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
    // Instance-iterator extras (empty for top-level machines): the enclosing type plus its readable
    // field / callable method handles, and the canonical->runtime-type table for sequence elements.
    public EnclosingType: Type?
    public EnclosingFieldNames: string[]
    public EnclosingFields: FieldInfo[]
    public EnclosingFieldCanonicals: string[]
    public EnclosingMethodNames: string[]
    public EnclosingMethods: MethodInfo[]
    public KnownTypeNames: string[]
    public KnownTypes: Type[]
    // Async-machine extra: the MoveNextCore handle MoveNextAsync's plan drives (null for sync machines).
    public CoreMethod: MethodInfo?

    constructor(
        nodes: ColumnarNodeTable,
        source: string,
        bodyRoot: int,
        shape: ColumnarIteratorShape,
        stateMachineType: Type,
        elementType: Type,
        fieldNames: string[],
        fields: FieldInfo[],
        smConstructor: ConstructorInfo? = null,
        enclosingType: Type? = null,
        enclosingFieldNames: string[]? = null,
        enclosingFields: FieldInfo[]? = null,
        enclosingFieldCanonicals: string[]? = null,
        enclosingMethodNames: string[]? = null,
        enclosingMethods: MethodInfo[]? = null,
        knownTypeNames: string[]? = null,
        knownTypes: Type[]? = null,
        coreMethod: MethodInfo? = null) {
        Nodes = nodes
        Source = source
        BodyRoot = bodyRoot
        Shape = shape
        StateMachineType = stateMachineType
        ElementType = elementType
        FieldNames = fieldNames
        Fields = fields
        Constructor = smConstructor
        EnclosingType = enclosingType
        EnclosingFieldNames = enclosingFieldNames ?? new string[](0)
        EnclosingFields = enclosingFields ?? new FieldInfo[](0)
        EnclosingFieldCanonicals = enclosingFieldCanonicals ?? new string[](0)
        EnclosingMethodNames = enclosingMethodNames ?? new string[](0)
        EnclosingMethods = enclosingMethods ?? new MethodInfo[](0)
        KnownTypeNames = knownTypeNames ?? new string[](0)
        KnownTypes = knownTypes ?? new Type[](0)
        CoreMethod = coreMethod
    }

    public func RequiredCoreMethod(): MethodInfo {
        handle := CoreMethod
        if handle == null {
            throw new InvalidOperationException("Iterator emit context carries no MoveNextCore handle.")
        }
        return handle
    }

    public func HasHoistedField(name: string): bool {
        i := 0
        while i < FieldNames.Length {
            if FieldNames[i] == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    public func EnclosingFieldIndex(name: string): int {
        i := 0
        while i < EnclosingFieldNames.Length {
            if EnclosingFieldNames[i] == name {
                return i
            }
            i = i + 1
        }
        return 0 - 1
    }

    public func EnclosingMethodForName(name: string): MethodInfo {
        i := 0
        while i < EnclosingMethodNames.Length {
            if EnclosingMethodNames[i] == name {
                return EnclosingMethods[i]
            }
            i = i + 1
        }
        throw new InvalidOperationException("Iterator emit context has no enclosing method named '" + name + "'.")
    }

    public func KnownTypeForCanonical(canonical: string): Type? {
        i := 0
        while i < KnownTypeNames.Length {
            if KnownTypeNames[i] == canonical {
                return KnownTypes[i]
            }
            i = i + 1
        }
        return null
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

    public func FieldCanonicalForName(name: string): string {
        i := 0
        while i < FieldNames.Length {
            if FieldNames[i] == name {
                return Shape.FieldCanonicals[i]
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
    public NextForIn: int
    public NextEnumerator: int
    // Region mode (any hoisted enumerator): the whole dispatch+body sits inside a try/FAULT region,
    // so every suspend/finish path stores the result local and `leave`s to the ret outside the region
    // (ECMA forbids `ret` inside a protected region; per-call re-entry through the try start plus an
    // in-region dispatch branch is how the machine legally resumes inside the region).
    public RegionMode: bool
    public ResultLocal: int
    public RegionEndLabel: int
    // Async mode: yields and awaits share ONE resume-state counter (walk order), awaits number their
    // awaiter fields with NextAwait, and suspension/completion go through the promise/result fields.
    public IsAsync: bool
    public NextResume: int
    public NextAwait: int

    constructor(
        plan: ColumnarCodePlan,
        context: ColumnarIteratorEmitContext,
        thisArg: int,
        stateFieldPool: int,
        resumeLabels: int[],
        endLabel: int,
        regionMode: bool,
        resultLocal: int,
        regionEndLabel: int,
        isAsync: bool = false) {
        Plan = plan
        Context = context
        ThisArg = thisArg
        StateFieldPool = stateFieldPool
        ResumeLabels = resumeLabels
        EndLabel = endLabel
        NextYield = 0
        NextForIn = 0
        NextEnumerator = 0
        RegionMode = regionMode
        ResultLocal = resultLocal
        RegionEndLabel = regionEndLabel
        IsAsync = isAsync
        NextResume = 0
        NextAwait = 0
    }
}

public class ColumnarIteratorBodyPlanner {
    // MoveNext(): the resumable state machine. A dispatch prologue routes each resume state to its label;
    // state 0 falls through to the body start (state set running = -1); every `yield return` stores current,
    // sets its resume state, returns true, then resumes by resetting to running; `yield break` and the
    // natural body end reach the shared end label that returns false. A body with hoisted enumerators
    // takes the guarded layout instead (the whole dispatch+body inside a try/FAULT region).
    public static func BuildMoveNextPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        if HoistedEnumeratorFieldCount(context) > 0 {
            return BuildGuardedMoveNextPlan(context)
        }
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
        emit := new ColumnarMoveNextEmit(plan, context, thisArg, stateFieldPool, resumeLabels, endLabel, false, 0, 0)

        AppendMoveNextDispatch(emit, yieldCount)

        EmitStatement(emit, context.BodyRoot)

        plan.AppendMarkLabel(endLabel)
        EmitInt(emit, 0)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(bool))
        return plan
    }

    // The guarded MoveNext layout (Roslyn's iterator discipline): try { dispatch + body } fault
    // { dispose live enumerators }. Suspension stores the result local and `leave`s past the region
    // (leave never runs a fault handler); each MoveNext call re-enters the region at its start and the
    // in-region dispatch branches to the resume label, which is how IL legally resumes inside a
    // protected region. The done/finish path is an in-region label that leaves with result 0.
    static func BuildGuardedMoveNextPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        stateFieldPool := plan.AddField(context.FieldForName("<>__state"))
        boolTypeIdx := plan.AddType(typeof(bool))
        resultLocal := plan.DeclarePlanLocal(boolTypeIdx)

        yieldCount := context.Shape.YieldReturnCount
        resumeLabels := new int[](yieldCount + 1)
        s := 1
        while s <= yieldCount {
            resumeLabels[s] = plan.DefineLabel()
            s = s + 1
        }
        endLabel := plan.DefineLabel()
        regionEnd := plan.DefineLabel()
        emit := new ColumnarMoveNextEmit(
            plan, context, thisArg, stateFieldPool, resumeLabels, endLabel, true, resultLocal, regionEnd)

        plan.AppendBeginExceptionBlock(regionEnd)
        AppendMoveNextDispatch(emit, yieldCount)

        EmitStatement(emit, context.BodyRoot)

        plan.AppendMarkLabel(endLabel)
        EmitInt(emit, 0)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), resultLocal)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), regionEnd)

        plan.AppendBeginFaultBlock()
        AppendEnumeratorDisposals(plan, context, thisArg)
        plan.AppendEndExceptionBlock()

        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), resultLocal)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(bool))
        return plan
    }

    // MoveNextCore(): the ASYNC synchronous-step core. One drive advances the machine to its next
    // yield, its natural end, or the first incomplete awaiter. Layout: try { dispatch + body + finish }
    // catch (Exception) { route to the promise or rethrow }. Completion goes through the promise when a
    // pending MoveNextAsync exists (a suspension created it), otherwise through the result field the
    // synchronous fast path reads. Suspension stores the awaiter, sets the await-resume state, ensures
    // the promise, registers the continuation (this.<>__continuation re-drives this core), and leaves.
    public static func BuildAsyncMoveNextCorePlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        stateFieldPool := plan.AddField(context.FieldForName("<>__state"))
        exTypeIdx := plan.AddType(ExceptionRuntimeType())
        exLocal := plan.DeclarePlanLocal(exTypeIdx)

        resumeCount := context.Shape.YieldReturnCount + context.Shape.AwaitResumeCount
        resumeLabels := new int[](resumeCount + 1)
        s := 1
        while s <= resumeCount {
            resumeLabels[s] = plan.DefineLabel()
            s = s + 1
        }
        endLabel := plan.DefineLabel()
        regionEnd := plan.DefineLabel()
        emit := new ColumnarMoveNextEmit(
            plan, context, thisArg, stateFieldPool, resumeLabels, endLabel, true, 0, regionEnd, true)

        plan.AppendBeginExceptionBlock(regionEnd)
        AppendMoveNextDispatch(emit, resumeCount)

        EmitStatement(emit, context.BodyRoot)

        plan.AppendMarkLabel(endLabel)
        StoreState(emit, ColumnarIteratorPlanner.DoneState())
        EmitAsyncComplete(emit, 0)

        plan.AppendBeginCatchBlock(exTypeIdx)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), exLocal)
        StoreState(emit, ColumnarIteratorPlanner.DoneState())
        promPool := FieldPool(emit, "<>__promise")
        exViaPromise := plan.DefineLabel()
        LoadThis(emit)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), exViaPromise)
        // No pending promise: the drive was synchronous — propagate to the MoveNextAsync caller.
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), exLocal)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Throw())
        plan.AppendMarkLabel(exViaPromise)
        LoadThis(emit)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), exLocal)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(PromiseSetExceptionMethod()))
        // Fall into EndExceptionBlock: ILGenerator appends the implicit leave past the region (the
        // same fallthrough discipline as the sync fault handler's disposal tail).
        plan.AppendEndExceptionBlock()

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(VoidReturnType())
        return plan
    }

    // MoveNextAsync(): the IAsyncEnumerator<T> surface. Guard the done state, clear any completed
    // promise, drive the step core once, then select the result: a suspension left a live promise
    // (return its pending/completed Task<bool>); a synchronous completion left the result flag.
    public static func BuildMoveNextAsyncPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        statePool := plan.AddField(context.FieldForName("<>__state"))
        promPool := plan.AddField(context.FieldForName("<>__promise"))
        resPool := plan.AddField(context.FieldForName("<>__result"))
        boolCtorPool := plan.AddConstructor(ValueTaskOfBoolConstructor())
        taskCtorPool := plan.AddConstructor(ValueTaskOfTaskConstructor())
        noParams := new Type[](0)
        corePool := plan.AddMethodWithSignature(
            context.RequiredCoreMethod(), context.StateMachineType, noParams, VoidReturnType(), false, false)
        driveLabel := plan.DefineLabel()
        syncLabel := plan.DefineLabel()
        // if state == done: return new ValueTask<bool>(false)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), statePool)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(ColumnarIteratorPlanner.DoneState()))
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), driveLabel)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_0())
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), boolCtorPool)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.AppendMarkLabel(driveLabel)
        // promise = null; MoveNextCore()
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), promPool)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), corePool)
        // pending promise -> wrap its Task<bool>; otherwise wrap the synchronous result flag
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), syncLabel)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(PromiseTaskGetter()))
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), taskCtorPool)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.AppendMarkLabel(syncLabel)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), resPool)
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), boolCtorPool)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(ValueTaskOfBoolRuntimeType())
        return plan
    }

    // DisposeAsync(): mark the machine done and complete synchronously (default ValueTask). No async
    // machine holds a hoisted enumerator (the walk declines them), so there is nothing to release.
    public static func BuildDisposeAsyncPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        statePool := plan.AddField(context.FieldForName("<>__state"))
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(ColumnarIteratorPlanner.DoneState()))
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), statePool)
        vtType := ValueTaskRuntimeType()
        vtTypeIdx := plan.AddType(vtType)
        vtLocal := plan.DeclarePlanLocal(vtTypeIdx)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), vtLocal)
        plan.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), vtTypeIdx)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), vtLocal)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(vtType)
        return plan
    }

    // GetAsyncEnumerator(CancellationToken): clone semantics, exactly the sync GetEnumerator discipline
    // — every call yields a FRESH machine at the initial state with captured parameters copied. The
    // token parameter is accepted (the interface signature) and unused: no admitted body reads it yet.
    public static func BuildGetAsyncEnumeratorPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        AppendEnumeratorClone(plan, context)
        plan.CompleteMethodBody(AsyncEnumeratorInterfaceTypeOf(context.ElementType))
        return plan
    }

    // The state dispatch: each resume state branches to its label; any other non-zero state (running or
    // done) reaches the end label; state 0 falls through into a fresh run.
    static func AppendMoveNextDispatch(emit: ColumnarMoveNextEmit, yieldCount: int) {
        s := 1
        while s <= yieldCount {
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), emit.StateFieldPool)
            EmitInt(emit, s)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), emit.ResumeLabels[s])
            s = s + 1
        }
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), emit.StateFieldPool)
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), emit.EndLabel)
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
    }

    static func HoistedEnumeratorFieldCount(context: ColumnarIteratorEmitContext): int {
        count := 0
        i := 0
        while i < context.Shape.FieldRoles.Length {
            if context.Shape.FieldRoles[i] == ColumnarIteratorPlanner.HoistedEnumeratorFieldRole() {
                count = count + 1
            }
            i = i + 1
        }
        return count
    }

    // Null-checked disposal (+ null-out) of every hoisted enumerator field: the fault handler's body,
    // and the suspended-machine path inside Dispose(). Fields are null until their loop starts and are
    // nulled again on the loop's normal exit, so a null check is exactly the liveness test.
    static func AppendEnumeratorDisposals(plan: ColumnarCodePlan, context: ColumnarIteratorEmitContext, thisArg: int) {
        i := 0
        while i < context.Shape.FieldRoles.Length {
            if context.Shape.FieldRoles[i] == ColumnarIteratorPlanner.HoistedEnumeratorFieldRole() {
                fieldPool := plan.AddField(context.Fields[i])
                skipLabel := plan.DefineLabel()
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
                plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipLabel)
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
                plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(DisposableDisposeMethod()))
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldPool)
                plan.AppendMarkLabel(skipLabel)
            }
            i = i + 1
        }
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
        if context.ElementType.get_IsValueType() || context.ElementType.get_IsGenericParameter() {
            // A value element boxes to object; an unconstrained type parameter boxes unconditionally
            // (`box !T` is a no-op for reference instantiations).
            boxTypePool := plan.AddType(context.ElementType)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), boxTypePool)
        }
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(object))
        return plan
    }

    // System.IDisposable.Dispose(): dispose any live hoisted enumerator (the machine may be suspended
    // inside a guarded loop — this is the finally-equivalent path for consumer abandonment), then mark
    // the machine done.
    public static func BuildDisposePlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StateMachineType)
        thisArg := plan.AddArgument(0, smTypeIdx)
        statePool := plan.AddField(context.FieldForName("<>__state"))
        donePool := plan.AddInt32(ColumnarIteratorPlanner.DoneState())
        AppendEnumeratorDisposals(plan, context, thisArg)
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
        AppendFactoryBody(plan, context)
        plan.CompleteMethodBody(EnumerableInterfaceTypeOf(context.ElementType))
        return plan
    }

    // The async factory: the identical construct-and-capture body; only the declared result view
    // differs (the IAsyncEnumerable<T> surface the `async func*` method returns).
    public static func BuildAsyncFactoryPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        AppendFactoryBody(plan, context)
        plan.CompleteMethodBody(AsyncEnumerableInterfaceTypeOf(context.ElementType))
        return plan
    }

    static func AppendFactoryBody(plan: ColumnarCodePlan, context: ColumnarIteratorEmitContext) {
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

    // Push an identifier's value: a hoisted field directly, or (instance mode) an enclosing-type field
    // read through the captured receiver (`this.<>__this.Member`). Net stack effect +1 either way.
    static func AppendIdentifierRead(emit: ColumnarMoveNextEmit, name: string) {
        if emit.Context.HasHoistedField(name) {
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, name))
            return
        }
        memberIndex := emit.Context.EnclosingFieldIndex(name)
        if memberIndex < 0 {
            throw new InvalidOperationException(
                "Iterator MoveNext lowering reached an unbound identifier '" + name + "'.")
        }
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, "<>__this"))
        emit.Plan.AppendFieldInstruction(
            ColumnarCodePlanContract.Ldfld(), emit.Plan.AddField(emit.Context.EnclosingFields[memberIndex]))
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
            // expression statement: a unit await (async bodies), a bare postfix step (value dropped),
            // or a simple `=` assignment (kind 14) to a bound identifier
            assign := nodes.Child(node, 0)
            if nodes.Kind(assign) == 53 {
                EmitUnitAwait(emit, assign)
                return true
            }
            if nodes.Kind(assign) == 44 {
                EmitPostfixStep(emit, assign, false)
                return true
            }
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
        if kind == 28 {
            // For [init, cond, incr, body]: `init` runs once (its local is a hoisted field), then the
            // while discipline with a trailing increment — the back edge (and the increment before it)
            // only exists when the body can complete.
            EmitStatement(emit, nodes.Child(node, 0))
            condLabel := emit.Plan.DefineLabel()
            afterLabel := emit.Plan.DefineLabel()
            emit.Plan.AppendMarkLabel(condLabel)
            EmitExpression(emit, nodes.Child(node, 1))
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), afterLabel)
            if EmitStatement(emit, nodes.Child(node, 3)) {
                EmitStatement(emit, nodes.Child(node, 2))
                emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
            }
            emit.Plan.AppendMarkLabel(afterLabel)
            return true
        }
        if kind == 29 {
            // for..in [source, body]: hoisted array sources take the index loop; everything else
            // (member/call/sequence sources) the hoisted-enumerator loop — mirroring the walk.
            if nodes.Kind(nodes.Child(node, 0)) != 6 {
                return EmitEnumerableForIn(emit, node)
            }
            sourceName := nodes.Text(source, nodes.Child(node, 0))
            if !emit.Context.HasHoistedField(sourceName) {
                return EmitEnumerableForIn(emit, node)
            }
            sourceCanonical := emit.Context.FieldCanonicalForName(sourceName)
            if ColumnarIteratorPlanner.ArrayElementCanonicalOf(sourceCanonical) == "" {
                return EmitEnumerableForIn(emit, node)
            }
            indexName := "<>__index" + emit.NextForIn.ToString()
            emit.NextForIn = emit.NextForIn + 1
            varName := nodes.Text(source, node)
            arrayPool := FieldPool(emit, sourceName)
            indexPool := FieldPool(emit, indexName)
            varPool := FieldPool(emit, varName)
            // index = 0
            LoadThis(emit)
            EmitInt(emit, 0)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), indexPool)
            condLabel := emit.Plan.DefineLabel()
            afterLabel := emit.Plan.DefineLabel()
            emit.Plan.AppendMarkLabel(condLabel)
            // index < array.Length
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), indexPool)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), arrayPool)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldlen())
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.ConvI4())
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Clt())
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), afterLabel)
            // var = array[index]
            LoadThis(emit)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), arrayPool)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), indexPool)
            AppendArrayElementLoad(emit, emit.Context.FieldCanonicalForName(varName))
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), varPool)
            if EmitStatement(emit, nodes.Child(node, 1)) {
                // index = index + 1
                LoadThis(emit)
                LoadThis(emit)
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), indexPool)
                EmitInt(emit, 1)
                emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Add())
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), indexPool)
                emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
            }
            emit.Plan.AppendMarkLabel(afterLabel)
            return true
        }
        if kind == 48 {
            // throw new <BclException>("literal"): ldstr the decoded message, newobj the exception's
            // (string) constructor, throw. A throw never falls through.
            creation := nodes.Child(node, 0)
            exceptionName := nodes.Text(source, nodes.Child(creation, 0))
            messageText := nodes.Text(source, nodes.Child(creation, 1))
            messagePool := emit.Plan.AddString(StringLiteralDecoder.Decode(messageText))
            emit.Plan.AppendStringInstruction(ColumnarCodePlanContract.Ldstr(), messagePool)
            ctorPool := emit.Plan.AddConstructor(LowerableExceptionConstructor(exceptionName))
            emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), ctorPool)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Throw())
            return false
        }
        throw new InvalidOperationException(
            "Iterator MoveNext lowering reached an unsupported statement kind " + kind.ToString() + ".")
    }

    // for..in over an IEnumerable<X>/List<X> source: hoisted-enumerator loop inside the guarded
    // region. `this.enumK = source.GetEnumerator()`, then MoveNext/get_Current callvirts; the loop's
    // normal exit disposes and nulls the enumerator inline (the fault handler and Dispose() cover the
    // exceptional and suspended-abandonment paths).
    static func EmitEnumerableForIn(emit: ColumnarMoveNextEmit, node: int): bool {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        enumName := "<>__enum" + emit.NextEnumerator.ToString()
        emit.NextEnumerator = emit.NextEnumerator + 1
        varName := nodes.Text(source, node)
        enumPool := FieldPool(emit, enumName)
        varPool := FieldPool(emit, varName)
        element := emit.Context.FieldCanonicalForName(varName)
        getEnumeratorPool := AddSequenceGetEnumerator(emit, element)
        moveNextPool := emit.Plan.AddMethod(EnumeratorMoveNextMethod())
        currentPool := AddSequenceCurrentGetter(emit, element)
        disposePool := emit.Plan.AddMethod(DisposableDisposeMethod())
        // this.enum = <source>.GetEnumerator()
        LoadThis(emit)
        AppendSequenceSourceValue(emit, nodes.Child(node, 0), element)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), getEnumeratorPool)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), enumPool)
        condLabel := emit.Plan.DefineLabel()
        afterLabel := emit.Plan.DefineLabel()
        emit.Plan.AppendMarkLabel(condLabel)
        // while enum.MoveNext()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), enumPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), moveNextPool)
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), afterLabel)
        // var = enum.Current
        LoadThis(emit)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), enumPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), currentPool)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), varPool)
        if EmitStatement(emit, nodes.Child(node, 1)) {
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
        }
        emit.Plan.AppendMarkLabel(afterLabel)
        // Normal exit: dispose and null the enumerator (leave/fault handle the other paths).
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), enumPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), disposePool)
        LoadThis(emit)
        emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), enumPool)
        return true
    }

    // Runtime interface handles for the enumerator loop; elements are the walk-admitted builtins, so
    // every constructed interface is a runtime type with reflectable members.
    static func RuntimeElementTypeOf(elementCanonical: string): Type {
        if elementCanonical == "int" {
            return typeof(int)
        }
        if elementCanonical == "long" {
            return typeof(long)
        }
        if elementCanonical == "float" {
            return typeof(float)
        }
        if elementCanonical == "double" {
            return typeof(double)
        }
        if elementCanonical == "bool" {
            return typeof(bool)
        }
        if elementCanonical == "char" {
            return typeof(char)
        }
        if elementCanonical == "string" {
            return typeof(string)
        }
        throw new InvalidOperationException(
            "Iterator for..in lowering has no runtime element type for '" + elementCanonical + "'.")
    }

    // Push the sequence source value: a bound identifier/member read, or a member-call source
    // (`receiver.Method()` — the receiver read plus a callvirt of the enclosing method's handle).
    static func AppendSequenceSourceValue(emit: ColumnarMoveNextEmit, sourceNode: int, elementCanonical: string) {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        if nodes.Kind(sourceNode) == 6 {
            AppendIdentifierRead(emit, nodes.Text(source, sourceNode))
            return
        }
        callee := nodes.Child(sourceNode, 0)
        AppendIdentifierRead(emit, nodes.Text(source, nodes.Child(callee, 0)))
        enclosing := emit.Context.EnclosingType
        if enclosing == null {
            throw new InvalidOperationException("Iterator for..in call source requires an enclosing type handle.")
        }
        handle := emit.Context.EnclosingMethodForName(nodes.Text(source, callee))
        noParams := new Type[](0)
        returnType := EnumerableInterfaceTypeOf(SequenceElementRuntimeType(emit.Context, elementCanonical))
        methodPool := emit.Plan.AddMethodWithSignature(handle, enclosing, noParams, returnType, false, false)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodPool)
    }

    // The runtime Type of a sequence element canonical: a builtin, or a host-supplied known type
    // (an emitted user TypeBuilder).
    static func SequenceElementRuntimeType(context: ColumnarIteratorEmitContext, canonical: string): Type {
        if ColumnarIteratorPlanner.IsLowerableArrayElementCanonical(canonical) {
            return RuntimeElementTypeOf(canonical)
        }
        known := context.KnownTypeForCanonical(canonical)
        if known == null {
            throw new InvalidOperationException(
                "Iterator for..in lowering has no runtime type for element '" + canonical + "'.")
        }
        return known
    }

    static func IsBuilderBoundElement(elementType: Type): bool {
        return elementType is TypeBuilder || elementType is EnumBuilder || elementType.get_IsGenericParameter()
    }

    // GetEnumerator on IEnumerable<element>: a runtime handle for baked elements, a
    // TypeBuilder.GetMethod rebinding (with the declared signature) for builder-bound elements.
    static func AddSequenceGetEnumerator(emit: ColumnarMoveNextEmit, elementCanonical: string): int {
        elementType := SequenceElementRuntimeType(emit.Context, elementCanonical)
        enumerableType := EnumerableInterfaceTypeOf(elementType)
        if IsBuilderBoundElement(elementType) {
            handle := TypeBuilder.GetMethod(enumerableType, OpenSequenceMethod("System.Collections.Generic.IEnumerable`1", "GetEnumerator"))
            noParams := new Type[](0)
            return emit.Plan.AddMethodWithSignature(
                handle, enumerableType, noParams, EnumeratorInterfaceTypeOf(elementType), false, true)
        }
        method := enumerableType.GetMethod("GetEnumerator")
        if method == null {
            throw new InvalidOperationException("IEnumerable<" + elementCanonical + ">.GetEnumerator was not found.")
        }
        return emit.Plan.AddMethod(method)
    }

    static func AddSequenceCurrentGetter(emit: ColumnarMoveNextEmit, elementCanonical: string): int {
        elementType := SequenceElementRuntimeType(emit.Context, elementCanonical)
        enumeratorType := EnumeratorInterfaceTypeOf(elementType)
        if IsBuilderBoundElement(elementType) {
            handle := TypeBuilder.GetMethod(enumeratorType, OpenSequenceMethod("System.Collections.Generic.IEnumerator`1", "get_Current"))
            noParams := new Type[](0)
            return emit.Plan.AddMethodWithSignature(handle, enumeratorType, noParams, elementType, false, true)
        }
        method := enumeratorType.GetMethod("get_Current")
        if method == null {
            throw new InvalidOperationException("IEnumerator<" + elementCanonical + ">.get_Current was not found.")
        }
        return emit.Plan.AddMethod(method)
    }

    static func OpenSequenceMethod(definitionName: string, methodName: string): MethodInfo {
        definition := Type.GetType(definitionName)
        if definition == null {
            throw new InvalidOperationException(definitionName + " was not found.")
        }
        method := definition.GetMethod(methodName)
        if method == null {
            throw new InvalidOperationException(definitionName + "." + methodName + " was not found.")
        }
        return method
    }

    static func EnumeratorMoveNextMethod(): MethodInfo {
        method := NonGenericEnumeratorType().GetMethod("MoveNext")
        if method == null {
            throw new InvalidOperationException("System.Collections.IEnumerator.MoveNext was not found.")
        }
        return method
    }

    static func DisposableDisposeMethod(): MethodInfo {
        disposableType := Type.GetType("System.IDisposable")
        if disposableType == null {
            throw new InvalidOperationException("System.IDisposable was not found.")
        }
        method := disposableType.GetMethod("Dispose")
        if method == null {
            throw new InvalidOperationException("System.IDisposable.Dispose was not found.")
        }
        return method
    }

    // ---- async runtime handles (Task.Delay awaits, the promise, and the ValueTask surfaces) ----

    static func RequiredRuntimeType(name: string): Type {
        resolved := Type.GetType(name)
        if resolved == null {
            throw new InvalidOperationException(name + " was not found.")
        }
        return resolved
    }

    static func RequiredMethodOf(owner: Type, name: string): MethodInfo {
        method := owner.GetMethod(name)
        if method == null {
            throw new InvalidOperationException(owner.FullName + "." + name + " was not found.")
        }
        return method
    }

    static func BoolClosedRuntimeType(definitionName: string): Type {
        typeArgs := new Type[](1)
        typeArgs[0] = typeof(bool)
        return RequiredRuntimeType(definitionName).MakeGenericType(typeArgs)
    }

    static func ExceptionRuntimeType(): Type { return RequiredRuntimeType("System.Exception") }
    static func TaskAwaiterRuntimeType(): Type { return RequiredRuntimeType("System.Runtime.CompilerServices.TaskAwaiter") }
    static func ValueTaskRuntimeType(): Type { return RequiredRuntimeType("System.Threading.Tasks.ValueTask") }
    static func ValueTaskOfBoolRuntimeType(): Type { return BoolClosedRuntimeType("System.Threading.Tasks.ValueTask`1") }
    static func PromiseRuntimeType(): Type { return BoolClosedRuntimeType("System.Threading.Tasks.TaskCompletionSource`1") }

    static func AsyncEnumeratorInterfaceTypeOf(elementType: Type): Type {
        typeArgs := new Type[](1)
        typeArgs[0] = elementType
        return RequiredRuntimeType("System.Collections.Generic.IAsyncEnumerator`1").MakeGenericType(typeArgs)
    }

    static func AsyncEnumerableInterfaceTypeOf(elementType: Type): Type {
        typeArgs := new Type[](1)
        typeArgs[0] = elementType
        return RequiredRuntimeType("System.Collections.Generic.IAsyncEnumerable`1").MakeGenericType(typeArgs)
    }

    static func TaskDelayMethod(): MethodInfo {
        delayTypes := new Type[](1)
        delayTypes[0] = typeof(int)
        method := RequiredRuntimeType("System.Threading.Tasks.Task").GetMethod("Delay", delayTypes)
        if method == null {
            throw new InvalidOperationException("Task.Delay(int) was not found.")
        }
        return method
    }

    static func TaskGetAwaiterMethod(): MethodInfo {
        return RequiredMethodOf(RequiredRuntimeType("System.Threading.Tasks.Task"), "GetAwaiter")
    }

    static func AwaiterIsCompletedGetter(): MethodInfo { return RequiredMethodOf(TaskAwaiterRuntimeType(), "get_IsCompleted") }
    static func AwaiterGetResultMethod(): MethodInfo { return RequiredMethodOf(TaskAwaiterRuntimeType(), "GetResult") }
    static func AwaiterOnCompletedMethod(): MethodInfo { return RequiredMethodOf(TaskAwaiterRuntimeType(), "OnCompleted") }
    static func PromiseSetResultMethod(): MethodInfo { return RequiredMethodOf(PromiseRuntimeType(), "SetResult") }
    static func PromiseTaskGetter(): MethodInfo { return RequiredMethodOf(PromiseRuntimeType(), "get_Task") }

    static func PromiseSetExceptionMethod(): MethodInfo {
        exTypes := new Type[](1)
        exTypes[0] = ExceptionRuntimeType()
        method := PromiseRuntimeType().GetMethod("SetException", exTypes)
        if method == null {
            throw new InvalidOperationException("TaskCompletionSource<bool>.SetException(Exception) was not found.")
        }
        return method
    }

    static func PromiseConstructor(): ConstructorInfo {
        ctorTypes := new Type[](1)
        ctorTypes[0] = RequiredRuntimeType("System.Threading.Tasks.TaskCreationOptions")
        ctor := PromiseRuntimeType().GetConstructor(ctorTypes)
        if ctor == null {
            throw new InvalidOperationException("TaskCompletionSource<bool>(TaskCreationOptions) was not found.")
        }
        return ctor
    }

    static func ValueTaskOfBoolConstructor(): ConstructorInfo {
        ctorTypes := new Type[](1)
        ctorTypes[0] = typeof(bool)
        ctor := ValueTaskOfBoolRuntimeType().GetConstructor(ctorTypes)
        if ctor == null {
            throw new InvalidOperationException("ValueTask<bool>(bool) was not found.")
        }
        return ctor
    }

    static func ValueTaskOfTaskConstructor(): ConstructorInfo {
        ctorTypes := new Type[](1)
        ctorTypes[0] = BoolClosedRuntimeType("System.Threading.Tasks.Task`1")
        ctor := ValueTaskOfBoolRuntimeType().GetConstructor(ctorTypes)
        if ctor == null {
            throw new InvalidOperationException("ValueTask<bool>(Task<bool>) was not found.")
        }
        return ctor
    }

    // TaskCreationOptions.RunContinuationsAsynchronously: promise completions schedule the consumer's
    // continuation instead of running it inline inside the step frame.
    static func RunContinuationsAsynchronouslyFlag(): int { return 64 }

    // The typed ldelem for a lowerable array element canonical (the walk admitted exactly this set).
    static func AppendArrayElementLoad(emit: ColumnarMoveNextEmit, elementCanonical: string) {
        if elementCanonical == "int" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemI4())
        } else if elementCanonical == "long" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemI8())
        } else if elementCanonical == "float" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemR4())
        } else if elementCanonical == "double" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemR8())
        } else if elementCanonical == "bool" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemU1())
        } else if elementCanonical == "char" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemU2())
        } else if elementCanonical == "string" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdelemRef())
        } else {
            throw new InvalidOperationException(
                "Iterator for..in lowering has no element load for '" + elementCanonical + "'.")
        }
    }

    // The (string) constructor of a walk-admitted System exception name.
    static func LowerableExceptionConstructor(name: string): ConstructorInfo {
        simple := ColumnarIteratorPlanner.SystemUnqualifiedExceptionName(name)
        if simple == "" {
            throw new InvalidOperationException("Iterator throw lowering reached a non-System exception name '" + name + "'.")
        }
        exceptionType := Type.GetType("System." + simple)
        if exceptionType == null {
            throw new InvalidOperationException("System." + simple + " was not found.")
        }
        ctorTypes := new Type[](1)
        ctorTypes[0] = typeof(string)
        ctor := exceptionType.GetConstructor(ctorTypes)
        if ctor == null {
            throw new InvalidOperationException("System." + simple + " has no (string) constructor.")
        }
        return ctor
    }

    static func EmitYieldReturn(emit: ColumnarMoveNextEmit, valueNode: int) {
        if emit.IsAsync {
            EmitAsyncYieldReturn(emit, valueNode)
            return
        }
        emit.NextYield = emit.NextYield + 1
        resumeState := emit.NextYield
        LoadThis(emit)
        EmitExpression(emit, valueNode)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, "<>__current"))
        StoreState(emit, resumeState)
        EmitInt(emit, 1)
        if emit.RegionMode {
            // Suspension inside the protected region: stash the result and `leave` to the ret outside
            // (leave never runs the fault handler, so live enumerators survive the suspension).
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), emit.ResultLocal)
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), emit.RegionEndLabel)
        } else {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        }
        emit.Plan.AppendMarkLabel(emit.ResumeLabels[resumeState])
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
    }

    // Async `yield return`: store current, set the yield-resume state (the SHARED resume counter),
    // complete the pending call with true, and leave the region; the next drive resumes past it.
    static func EmitAsyncYieldReturn(emit: ColumnarMoveNextEmit, valueNode: int) {
        emit.NextResume = emit.NextResume + 1
        resumeState := emit.NextResume
        LoadThis(emit)
        EmitExpression(emit, valueNode)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, "<>__current"))
        StoreState(emit, resumeState)
        EmitAsyncComplete(emit, 1)
        emit.Plan.AppendMarkLabel(emit.ResumeLabels[resumeState])
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
    }

    // Complete one MoveNextAsync call with `value` (1 = yielded, 0 = finished) and leave the region.
    // A live promise means a suspension already returned a pending ValueTask — complete through it;
    // otherwise the drive is synchronous and the result flag feeds MoveNextAsync's fast path.
    static func EmitAsyncComplete(emit: ColumnarMoveNextEmit, value: int) {
        promPool := FieldPool(emit, "<>__promise")
        viaPromise := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), viaPromise)
        LoadThis(emit)
        EmitInt(emit, value)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, "<>__result"))
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), emit.RegionEndLabel)
        emit.Plan.AppendMarkLabel(viaPromise)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        EmitInt(emit, value)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), emit.Plan.AddMethod(PromiseSetResultMethod()))
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), emit.RegionEndLabel)
    }

    // A unit await (`await Task.Delay(<int>)` — the walk admitted exactly this shape): store the
    // awaiter, fast-path a completed one, otherwise suspend — set the await-resume state, ensure the
    // promise (TaskCreationOptions.RunContinuationsAsynchronously so completions never re-enter this
    // frame), register the re-drive continuation, and leave with the pending call unresolved. The
    // resume label re-enters through the dispatch, marks running, and falls into GetResult.
    static func EmitUnitAwait(emit: ColumnarMoveNextEmit, awaitNode: int) {
        emit.NextResume = emit.NextResume + 1
        resumeState := emit.NextResume
        awaiterName := "<>__awaiter" + emit.NextAwait.ToString()
        emit.NextAwait = emit.NextAwait + 1
        awPool := FieldPool(emit, awaiterName)
        promPool := FieldPool(emit, "<>__promise")
        operand := emit.Context.Nodes.Child(awaitNode, 0)
        // this.<>__awaiterK = Task.Delay(<arg>).GetAwaiter()
        LoadThis(emit)
        EmitExpression(emit, emit.Context.Nodes.Child(operand, 1))
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), emit.Plan.AddMethod(TaskDelayMethod()))
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), emit.Plan.AddMethod(TaskGetAwaiterMethod()))
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), awPool)
        fastLabel := emit.Plan.DefineLabel()
        havePromise := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), awPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), emit.Plan.AddMethod(AwaiterIsCompletedGetter()))
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), fastLabel)
        StoreState(emit, resumeState)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), havePromise)
        LoadThis(emit)
        EmitInt(emit, RunContinuationsAsynchronouslyFlag())
        emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), emit.Plan.AddConstructor(PromiseConstructor()))
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), promPool)
        emit.Plan.AppendMarkLabel(havePromise)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), awPool)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, "<>__continuation"))
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), emit.Plan.AddMethod(AwaiterOnCompletedMethod()))
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), emit.RegionEndLabel)
        emit.Plan.AppendMarkLabel(emit.ResumeLabels[resumeState])
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
        emit.Plan.AppendMarkLabel(fastLabel)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), awPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), emit.Plan.AddMethod(AwaiterGetResultMethod()))
        awaiterTypeIdx := emit.Plan.AddType(TaskAwaiterRuntimeType())
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), awPool)
        emit.Plan.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), awaiterTypeIdx)
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
            AppendIdentifierRead(emit, nodes.Text(source, node))
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
        if kind == 44 {
            EmitPostfixStep(emit, node, true)
            return
        }
        if kind == 9 {
            // The walk-admitted argument-free string instance call: read the receiver, callvirt.
            callee := nodes.Child(node, 0)
            AppendIdentifierRead(emit, nodes.Text(source, nodes.Child(callee, 0)))
            emit.Plan.AppendMethodInstruction(
                ColumnarCodePlanContract.Callvirt(),
                emit.Plan.AddMethod(StringInstanceMethod(nodes.Text(source, callee))))
            return
        }
        throw new InvalidOperationException(
            "Iterator MoveNext lowering reached an unsupported expression kind " + kind.ToString() + ".")
    }

    // `<ident>++` / `<ident>--` on a hoisted int field. keepValue pushes the PRE-step value first
    // (N# postfix semantics); the step itself is a load/add-or-sub/store through `this`.
    static func EmitPostfixStep(emit: ColumnarMoveNextEmit, node: int, keepValue: bool) {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        fieldPool := FieldPool(emit, nodes.Text(source, nodes.Child(node, 0)))
        if keepValue {
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
        }
        LoadThis(emit)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
        EmitInt(emit, 1)
        if nodes.Text(source, node) == "++" {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Add())
        } else {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Sub())
        }
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldPool)
    }

    // The zero-argument string instance method handle for a walk-admitted call name.
    static func StringInstanceMethod(name: string): MethodInfo {
        method := typeof(string).GetMethod(name, new Type[](0))
        if method == null {
            throw new InvalidOperationException("string." + name + "() was not found.")
        }
        return method
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
