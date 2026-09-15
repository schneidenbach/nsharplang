namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Sub-slice 3a: the DECISION layer of the synchronous iterator (func*) state machine. This planner owns
// every structural decision — element type, field layout, state numbering, member/override identities,
// dispatch shape, and the precise decline classification for shapes it cannot lower. It produces FACTS
// only; sub-slice 3b builds each member body as a schema-4 code plan against exactly these facts, and the
// C# emitter host defines and resolves handles while this N# owner applies each override at that member's
// existing attachment point.
//
// State numbering: 0 = initial (ready to start), 1..N = resume points (one per `yield return`), -1 =
// running (set while MoveNext executes), -2 = done. Field layout order (hoist ordering): the state field,
// the current field, then each captured parameter in signature order, then each hoisted local in first
// declaration order.
class ColumnarIteratorOverrideDeclaration {
    MemberOrdinal: int
    DeclarationIdentity: string
    LookupName: string
    TargetKind: ColumnarIteratorOverrideTargetKind
    ResolvedTarget: MethodInfo?
    ResolvedBinding: ColumnarIteratorMemberBinding?

    constructor(memberOrdinal: int, declarationIdentity: string, lookupName: string, targetKind: ColumnarIteratorOverrideTargetKind) {
        if memberOrdinal < 0 || declarationIdentity == null || declarationIdentity.Length == 0 || lookupName == null || lookupName.Length == 0 {
            throw new InvalidOperationException("Iterator method-override declaration facts are invalid.")
        }

        MemberOrdinal = memberOrdinal
        DeclarationIdentity = declarationIdentity
        LookupName = lookupName
        TargetKind = targetKind
        ResolvedTarget = null
        ResolvedBinding = null
    }

    func Apply(context: ColumnarIteratorOverrideContext, owner: TypeBuilder, body: MethodBuilder) {
        binding := new ColumnarIteratorMemberBinding(TargetKind, LookupName, context)
        target := binding.ValidatedTarget(context.StructuralTypeReferences)
        if owner == null || body == null || target == null {
            throw new InvalidOperationException("Iterator method-override handles cannot be null.")
        }

        ResolvedBinding = binding
        ResolvedTarget = target
        owner.DefineMethodOverride(body, target)
    }
}

class ColumnarIteratorShape {
    Supported: bool
    DeclineSite: string
    DeclineMessage: string
    TypeName: string
    ElementCanonical: string
    YieldReturnCount: int
    InitialState: int
    RunningState: int
    DoneState: int
    FieldCount: int
    FieldNames: string[]
    FieldCanonicals: string[]
    FieldRoles: int[]
    MemberCount: int
    MemberNames: string[]
    MemberSignatures: string[]
    MemberOverrideRows: ColumnarIteratorOverrideDeclaration[]
    // Async-iterator classification facts (`async func*` returning IAsyncEnumerable<T>). IsAsync marks a
    // shape produced by the async classification path; AwaitResumeCount is the number of `await` suspension
    // points in the body. Each await, like each `yield return`, is a resume state — the state machine
    // resumes at its await-resume label after the awaited operation completes. The async state-machine
    // member surface (MoveNextAsync/DisposeAsync/GetAsyncEnumerator) and the awaiter/builder fields are the
    // async EMISSION slice; the classification here computes element type and resume counts only.
    IsAsync: bool
    AwaitResumeCount: int
    // Protected-region facts, carried from classification to emission (see `ColumnarIteratorWalkState`).
    // `ResumeRegions` is indexed by resume state (1..YieldReturnCount); index 0 is unused.
    TryRegionCount: int
    TryRegionParents: int[]
    ResumeRegions: int[]
    LoopCaptureNames: string[]

    constructor(supported: bool, declineSite: string, declineMessage: string, typeName: string, elementCanonical: string, yieldReturnCount: int, fieldCount: int, fieldNames: string[], fieldCanonicals: string[], fieldRoles: int[], memberCount: int, memberNames: string[], memberSignatures: string[], memberOverrideRows: ColumnarIteratorOverrideDeclaration[], isAsync: bool, awaitResumeCount: int) {
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
        MemberOverrideRows = memberOverrideRows
        IsAsync = isAsync
        AwaitResumeCount = awaitResumeCount
        TryRegionCount = 0
        TryRegionParents = new int[](0)
        ResumeRegions = new int[](0)
        LoopCaptureNames = new string[](0)
    }

    // The innermost protected region resume state `state` suspends inside, or -1 when it suspends in
    // unprotected code. A shape with no regions answers -1 for every state without carrying a table.
    func ResumeRegionOf(state: int): int {
        if state < 0 || state >= ResumeRegions.Length {
            return 0 - 1
        }
        return ResumeRegions[state]
    }
}

// Mutable accumulator for the single forward body walk.
class ColumnarIteratorWalkState {
    YieldReturnCount: int
    AwaitCount: int
    // THE SHARED SUSPENSION COUNTER, and the index `ResumeRegions` is keyed by. A synchronous
    // generator suspends only at a `yield return`, so this equals `YieldReturnCount` there; an
    // async one interleaves `yield` and `await` in walk order and numbers them with ONE counter,
    // exactly as the emission walk's `NextResume` does. Keying the region table by the yield count
    // alone recorded the wrong region for every suspension after the first await.
    ResumeCount: int
    // True while classifying an `async func*`: `await` expressions are then legal suspension points
    // (each counts an await-resume state); in a synchronous iterator an `await` declines.
    IsAsync: bool
    ForInCount: int
    EnumeratorCount: int
    // The `await foreach` enumerators, counted apart from the synchronous ones. They are released by
    // their own hoisted handler (an awaited `DisposeAsync()`), not by the machine's blanket
    // synchronous disposal, so they take a plain hoisted-local slot rather than the enumerator role.
    AsyncEnumeratorCount: int
    CatchCount: int
    // The `using` statements whose resource is UNBOUND (`using e { … }`). A state machine's bindings
    // are FIELDS, so even a resource nobody named needs one to be read from in the handler — and the
    // two walks number those fields in the same walk order, exactly as they number try regions.
    UsingResourceCount: int
    // PROTECTED-REGION FACTS. Every `try` in the body is one region; ordinals are assigned in walk
    // order and the emission walk assigns exactly the same ones, so the two passes agree on which
    // region a resume state suspends inside. `TryRegionParents[k]` is the enclosing region (-1 at
    // the top level) and `ResumeRegions[s]` is the innermost region resume state `s` suspends in
    // (-1 when that `yield return` is not inside any `try`). The dispatch needs this because a
    // branch INTO a protected region is illegal IL: a state suspended inside a region is reached by
    // branching to the region's entry, re-entering the `try`, and dispatching again inside it.
    TryRegionCount: int
    TryRegionParents: int[]
    ResumeRegions: int[]
    CurrentRegion: int
    LocalCount: int
    LocalNames: string[]
    LocalCanonicals: string[]
    LocalRoles: int[]
    // The LOOP NESTING each hoisted local was declared at. Every local in a generator body lives in
    // ONE field of the machine, so a local declared inside a loop is the SAME storage on every
    // iteration. That is invisible until something captures it: a lambda created inside the loop
    // would see whatever the last iteration left, where the language promises a fresh binding per
    // iteration. The depth is what tells those two cases apart.
    LocalLoopDepths: int[]
    LoopCaptureCount: int
    LoopCaptureNames: string[]
    LoopDepth: int
    Declined: bool
    DeclineSite: string
    DeclineMessage: string
    ParamNames: string[]
    ParamCanonicals: string[]
    TypeParamNames: string[]
    // Enclosing-type member facts (instance iterators only; empty otherwise): readable public fields
    // and callable public methods of the receiver's type.
    MemberFieldNames: string[]
    MemberFieldCanonicals: string[]
    MemberMethodNames: string[]
    MemberMethodReturnCanonicals: string[]

    constructor(capacity: int, paramNames: string[], paramCanonicals: string[], typeParamNames: string[], memberFieldNames: string[], memberFieldCanonicals: string[], memberMethodNames: string[], memberMethodReturnCanonicals: string[], isAsync: bool) {
        YieldReturnCount = 0
        AwaitCount = 0
        ResumeCount = 0
        IsAsync = isAsync
        ForInCount = 0
        EnumeratorCount = 0
        AsyncEnumeratorCount = 0
        CatchCount = 0
        UsingResourceCount = 0
        TryRegionCount = 0
        TryRegionParents = new int[](capacity)
        ResumeRegions = new int[](capacity)
        CurrentRegion = 0 - 1
        LocalCount = 0
        LocalNames = new string[](capacity)
        LocalCanonicals = new string[](capacity)
        LocalRoles = new int[](capacity)
        LocalLoopDepths = new int[](capacity)
        LoopCaptureCount = 0
        LoopCaptureNames = new string[](capacity)
        LoopDepth = 0
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

    func Decline(site: string, message: string) {
        if !Declined {
            Declined = true
            DeclineSite = site
            DeclineMessage = message
        }
    }

    // The canonical type of a bound identifier: a parameter, or a local already declared earlier in the
    // walk. Returns "" when the name is unknown.
    func LookupCanonical(name: string): string {
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
    func LookupMemberFieldCanonical(name: string): string {
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
    func LookupMemberMethodReturnCanonical(name: string): string {
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
    func LookupReadCanonical(name: string): string {
        bound := LookupCanonical(name)
        if bound != "" {
            return bound
        }
        return LookupMemberFieldCanonical(name)
    }

    // The loop nesting the hoisted local `name` was declared at, or -1 when the name is not a
    // hoisted local at all (a parameter, an enclosing member, an unknown).
    func LocalLoopDepthOf(name: string): int {
        i := 0
        while i < LocalCount {
            if LocalNames[i] == name {
                return LocalLoopDepths[i]
            }
            i = i + 1
        }
        return 0 - 1
    }

    func RecordLoopCapture(name: string) {
        i := 0
        while i < LoopCaptureCount {
            if LoopCaptureNames[i] == name {
                return
            }
            i = i + 1
        }
        LoopCaptureNames[LoopCaptureCount] = name
        LoopCaptureCount = LoopCaptureCount + 1
    }

    func NameIsTypeParameter(name: string): bool {
        i := 0
        while i < TypeParamNames.Length {
            if TypeParamNames[i] == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    func AddLocal(name: string, canonical: string) {
        AddHoistedLocal(name, canonical, ColumnarIteratorPlanner.HoistedLocalFieldRole())
    }

    func AddHoistedLocal(name: string, canonical: string, role: int) {
        // A local that re-declares a parameter name collides with its captured field.
        p := 0
        while p < ParamNames.Length {
            if ParamNames[p] == name {
                Decline("emit.iterator.unsupported-shape", "a hoisted local shadows an existing binding ('" + name + "'); this shape is not yet lowered")
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
                Decline("emit.iterator.unsupported-shape", "a hoisted local shadows an existing binding ('" + name + "'); this shape is not yet lowered")
                return
            }
            l = l + 1
        }
        LocalNames[LocalCount] = name
        LocalCanonicals[LocalCount] = canonical
        LocalRoles[LocalCount] = role
        LocalLoopDepths[LocalCount] = LoopDepth
        LocalCount = LocalCount + 1
    }
}

class ColumnarIteratorPlanner {
    static func InitialState(): int {
        return 0
    }
    static func RunningState(): int {
        return -1
    }
    static func DoneState(): int {
        return -2
    }

    static func StateFieldRole(): int {
        return 0
    }
    static func CurrentFieldRole(): int {
        return 1
    }
    static func CapturedParameterFieldRole(): int {
        return 2
    }
    static func HoistedLocalFieldRole(): int {
        return 3
    }
    static func HoistedEnumeratorFieldRole(): int {
        return 4
    }
    // Async-machine roles: one hoisted TaskAwaiter per await site (role 5, `<>__awaiter{k}` in walk
    // order), the per-pending-call TaskCompletionSource<bool> promise (role 6), the synchronous-step
    // result flag (role 7), and the re-drive Action the suspension path registers (role 8).
    static func AwaiterFieldRole(): int {
        return 5
    }
    static func PromiseFieldRole(): int {
        return 6
    }
    static func ResultFieldRole(): int {
        return 7
    }
    static func ContinuationFieldRole(): int {
        return 8
    }
    // The dispose-mode flag (role 9, `<>__disposing`): present only on a machine that can suspend
    // inside a protected region. `Dispose` sets it and drives `MoveNext` once, so the machine resumes
    // where it suspended, immediately leaves the region, and the runtime runs every `finally` it was
    // standing inside — the same discipline the C# compiler uses for an async iterator.
    static func DisposeModeFieldRole(): int {
        return 9
    }
    static func LoopCaptureBoxFieldRole(): int {
        return 10
    }

    static func LoopCaptureBoxFieldName(name: string): string {
        return "<>__loopBox_" + name
    }

    static func LoopCaptureBoxType(valueType: Type): Type {
        definition := typeof(System.Runtime.CompilerServices.StrongBox<int>).GetGenericTypeDefinition()
        arguments := new Type[](1)
        arguments[0] = valueType
        return definition.MakeGenericType(arguments)
    }

    // Analyze a func* and produce its state-machine shape facts, or a precise decline. An INSTANCE
    // method supplies its receiver canonical plus the enclosing type's readable field and callable
    // method facts (public members only — the host filters); the receiver hoists as a `<>__this`
    // captured field so the factory (the method body) stores `ldarg.0` and the clone copies it.
    static func AnalyzeShape(nodes: ColumnarNodeTable, source: string, bodyRoot: int, funcName: string, funcOrdinal: int, returnCanonical: string, paramNames: string[], paramCanonicals: string[], typeParamNames: string[], isInstance: bool, receiverCanonical: string = "", enclosingFieldNames: string[]? = null, enclosingFieldCanonicals: string[]? = null, enclosingMethodNames: string[]? = null, enclosingMethodReturnCanonicals: string[]? = null, isAsync: bool = false): ColumnarIteratorShape {
        if isInstance && receiverCanonical == "" {
            return Declined("emit.iterator.instance-unsupported", "iterator methods with an instance receiver are not yet lowered")
        }
        if isInstance && typeParamNames.Length > 0 {
            return Declined("emit.iterator.instance-unsupported", "generic instance iterator methods are not yet lowered")
        }
        if isAsync && isInstance {
            return Declined("emit.iterator.async-unsupported", "async iterator methods with an instance receiver are not yet lowered")
        }
        if isAsync && typeParamNames.Length > 0 {
            return Declined("emit.iterator.async-unsupported", "generic async iterator methods are not yet lowered")
        }

        // Element-type inference. A synchronous iterator returns IEnumerable<X>; an `async func*` returns
        // IAsyncEnumerable<X>. The element may be one of the function's own type parameters — the state
        // machine then becomes generic with the parameter flowing into the current/value fields (the host
        // mirrors the type-parameter list onto the SM).
        sequenceName := SequenceNameOf(returnCanonical)
        element := SequenceElementOf(returnCanonical)
        if isAsync {
            if UnqualifiedName(sequenceName) != "IAsyncEnumerable" || element == "" {
                return Declined("emit.iterator.async-return-unsupported", "an async iterator (`async func*`) must return IAsyncEnumerable<T>, not '" + returnCanonical + "'")
            }
        } else {
            if UnqualifiedName(sequenceName) == "IAsyncEnumerable" {
                return Declined("emit.iterator.async-unsupported", "IAsyncEnumerable<T> requires the 'async' modifier on the iterator")
            }
            if element == "" || UnqualifiedName(sequenceName) != "IEnumerable" {
                return Declined("emit.iterator.return-unsupported", "only a typed IEnumerable<T> iterator return is lowered, not '" + returnCanonical + "'")
            }
        }

        capacity := nodes.Kinds.Length + 1
        state := new ColumnarIteratorWalkState(capacity, paramNames, paramCanonicals, typeParamNames, enclosingFieldNames ?? new string[](0), enclosingFieldCanonicals ?? new string[](0), enclosingMethodNames ?? new string[](0), enclosingMethodReturnCanonicals ?? new string[](0), isAsync)
        WalkStatement(nodes, source, bodyRoot, state)
        if state.Declined {
            return Declined(state.DeclineSite, state.DeclineMessage)
        }

        // THE DISPOSE FLAG IS A FIELD, so it is decided before either shape counts its fields — and
        // an async machine needs it for exactly the same reason a synchronous one does: a consumer
        // that abandons the sequence while the machine stands inside a `try` must still run every
        // handler it is standing in, and the machine gets back there through its own dispatch.
        if SuspendsInsideRegion(state) {
            state.AddHoistedLocal(DisposeModeFieldName(), "bool", DisposeModeFieldRole())
            if state.Declined {
                return Declined(state.DeclineSite, state.DeclineMessage)
            }
        }
        if isAsync {
            return BuildSupportedAsyncShape(funcName, funcOrdinal, element, paramNames, paramCanonicals, state)
        }
        return BuildSupportedShape(funcName, funcOrdinal, element, paramNames, paramCanonicals, state, isInstance ? receiverCanonical : "")
    }

    static func BuildSupportedShape(funcName: string, funcOrdinal: int, element: string, paramNames: string[], paramCanonicals: string[], state: ColumnarIteratorWalkState, receiverCanonical: string): ColumnarIteratorShape {
        receiverCount := 0
        if receiverCanonical != "" {
            receiverCount = 1
        }
        fieldCount := 2 + receiverCount + paramNames.Length + state.LocalCount + state.LoopCaptureCount
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
        capture := 0
        while capture < state.LoopCaptureCount {
            captureName := state.LoopCaptureNames[capture]
            fieldNames[cursor] = LoopCaptureBoxFieldName(captureName)
            fieldCanonicals[cursor] = state.LookupCanonical(captureName)
            fieldRoles[cursor] = LoopCaptureBoxFieldRole()
            cursor = cursor + 1
            capture = capture + 1
        }

        typeName := "<" + funcName + ">d__" + funcOrdinal.ToString()
        memberNames := BuildMemberNames()
        memberSignatures := BuildMemberSignatures(element)
        memberOverrideRows := BuildMemberOverrideRows()

        shape := new ColumnarIteratorShape(true, "", "", typeName, element, state.YieldReturnCount, fieldCount, fieldNames, fieldCanonicals, fieldRoles, memberNames.Length, memberNames, memberSignatures, memberOverrideRows, false, 0)
        shape.TryRegionCount = state.TryRegionCount
        shape.TryRegionParents = CopyInts(state.TryRegionParents, state.TryRegionCount)
        shape.ResumeRegions = CopyInts(state.ResumeRegions, state.ResumeCount + 1)
        shape.LoopCaptureNames = CopyStrings(state.LoopCaptureNames, state.LoopCaptureCount)
        return shape
    }

    static func CopyStrings(values: string[], count: int): string[] {
        copied := new string[](count)
        i := 0
        while i < count {
            copied[i] = values[i]
            i = i + 1
        }
        return copied
    }

    static func CopyInts(values: int[], count: int): int[] {
        copied := new int[](count)
        i := 0
        while i < count {
            copied[i] = values[i]
            i = i + 1
        }
        return copied
    }

    // True when any `yield return` suspends inside a `try`: the only machines that need a dispose
    // flag, because only they can be abandoned while standing inside a handler that must still run.
    static func SuspendsInsideRegion(state: ColumnarIteratorWalkState): bool {
        s := 1
        while s <= state.ResumeCount {
            if state.ResumeRegions[s] >= 0 {
                return true
            }
            s = s + 1
        }
        return false
    }

    static func DisposeModeFieldName(): string {
        return "<>__disposing"
    }

    // The async state-machine shape (`async func*` returning IAsyncEnumerable<T>). Field layout extends
    // the synchronous hoist order — state, current, captured parameters, hoisted locals — with the async
    // machinery: one TaskAwaiter field per await site (walk order), then the promise, the synchronous-step
    // result flag, and the re-drive continuation. Resume states interleave: the k-th suspension point in
    // body walk order (a `yield return` OR an `await`) resumes at state k+1; MoveNextCore's dispatch treats
    // both kinds identically and the body planner assigns numbers with one shared counter.
    static func BuildSupportedAsyncShape(funcName: string, funcOrdinal: int, element: string, paramNames: string[], paramCanonicals: string[], state: ColumnarIteratorWalkState): ColumnarIteratorShape {
        fieldCount := 2 + paramNames.Length + state.LocalCount + state.LoopCaptureCount + state.AwaitCount + 3
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
        capture := 0
        while capture < state.LoopCaptureCount {
            captureName := state.LoopCaptureNames[capture]
            fieldNames[cursor] = LoopCaptureBoxFieldName(captureName)
            fieldCanonicals[cursor] = state.LookupCanonical(captureName)
            fieldRoles[cursor] = LoopCaptureBoxFieldRole()
            cursor = cursor + 1
            capture = capture + 1
        }
        a := 0
        while a < state.AwaitCount {
            fieldNames[cursor] = "<>__awaiter" + a.ToString()
            // The awaiter's TYPE is whatever the awaited operand's own `GetAwaiter()` returns, and
            // that answer needs live CLR handles; the field is defined when the lowering reaches the
            // suspension point, exactly as a `:=` local's field is.
            fieldCanonicals[cursor] = UnresolvedCanonical()
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
        memberOverrideRows := BuildAsyncMemberOverrideRows()
        shape := new ColumnarIteratorShape(true, "", "", typeName, element, state.YieldReturnCount, fieldCount, fieldNames, fieldCanonicals, fieldRoles, memberNames.Length, memberNames, memberSignatures, memberOverrideRows, true, state.AwaitCount)
        // The PROTECTED-REGION FACTS, carried exactly as the synchronous shape carries them. A
        // region is a region whichever machine writes it: the dispatch still cannot branch INTO one,
        // so a suspension that lives inside a `try` is still reached by entering at the region's own
        // entry label and asking the question again one level down.
        shape.TryRegionCount = state.TryRegionCount
        shape.TryRegionParents = CopyInts(state.TryRegionParents, state.TryRegionCount)
        shape.ResumeRegions = CopyInts(state.ResumeRegions, state.ResumeCount + 1)
        shape.LoopCaptureNames = CopyStrings(state.LoopCaptureNames, state.LoopCaptureCount)
        return shape
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

    static func BuildAsyncMemberOverrideRows(): ColumnarIteratorOverrideDeclaration[] {
        rows := new ColumnarIteratorOverrideDeclaration[](6)
        rows[2] = new ColumnarIteratorOverrideDeclaration(2, "System.Collections.Generic.IAsyncEnumerator<T>.MoveNextAsync", "MoveNextAsync", ColumnarIteratorOverrideTargetKind.AsyncMoveNext)
        rows[3] = new ColumnarIteratorOverrideDeclaration(3, "System.Collections.Generic.IAsyncEnumerator<T>.get_Current", "Current", ColumnarIteratorOverrideTargetKind.AsyncCurrent)
        rows[4] = new ColumnarIteratorOverrideDeclaration(4, "System.IAsyncDisposable.DisposeAsync", "DisposeAsync", ColumnarIteratorOverrideTargetKind.AsyncDispose)
        rows[5] = new ColumnarIteratorOverrideDeclaration(5, "System.Collections.Generic.IAsyncEnumerable<T>.GetAsyncEnumerator", "GetAsyncEnumerator", ColumnarIteratorOverrideTargetKind.AsyncGetEnumerator)
        return rows
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

    static func BuildMemberOverrideRows(): ColumnarIteratorOverrideDeclaration[] {
        rows := new ColumnarIteratorOverrideDeclaration[](8)
        rows[1] = new ColumnarIteratorOverrideDeclaration(1, "System.Collections.IEnumerator.MoveNext", "MoveNext", ColumnarIteratorOverrideTargetKind.SyncMoveNext)
        rows[2] = new ColumnarIteratorOverrideDeclaration(2, "System.Collections.Generic.IEnumerator<T>.get_Current", "get_Current", ColumnarIteratorOverrideTargetKind.SyncGenericCurrent)
        rows[3] = new ColumnarIteratorOverrideDeclaration(3, "System.Collections.IEnumerator.get_Current", "Current", ColumnarIteratorOverrideTargetKind.SyncObjectCurrent)
        rows[4] = new ColumnarIteratorOverrideDeclaration(4, "System.Collections.IEnumerator.Reset", "Reset", ColumnarIteratorOverrideTargetKind.SyncReset)
        rows[5] = new ColumnarIteratorOverrideDeclaration(5, "System.IDisposable.Dispose", "Dispose", ColumnarIteratorOverrideTargetKind.SyncDispose)
        rows[6] = new ColumnarIteratorOverrideDeclaration(6, "System.Collections.Generic.IEnumerable<T>.GetEnumerator", "GetEnumerator", ColumnarIteratorOverrideTargetKind.SyncGenericGetEnumerator)
        rows[7] = new ColumnarIteratorOverrideDeclaration(7, "System.Collections.IEnumerable.GetEnumerator", "GetEnumerator", ColumnarIteratorOverrideTargetKind.SyncObjectGetEnumerator)
        return rows
    }

    static func Declined(site: string, message: string): ColumnarIteratorShape {
        return new ColumnarIteratorShape(false, site, message, "", "", 0, 0, new string[](0), new string[](0), new int[](0), 0, new string[](0), new string[](0), new ColumnarIteratorOverrideDeclaration[](0), false, 0)
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
            return WalkBlockChildrenFrom(nodes, source, node, 0, state)
        }
        if kind == 77 || kind == 81 {
            return WalkUsingStatement(nodes, source, node, state)
        }
        if kind == 40 {
            // TypedLocalDeclaration: value span = declared type canonical, child 0 = name, child 1 = init.
            declaredType := nodes.Text(source, node)
            nameNode := nodes.Child(node, 0)
            name := nodes.Text(source, nameNode)
            if nodes.ChildCount(node) >= 2 {
                WalkBoundValue(nodes, source, nodes.Child(node, 1), state)
            }
            state.AddLocal(name, declaredType)
            return true
        }
        if kind == 24 {
            // VariableDeclaration (`:=`): value span = name, child 0 = initializer. The local's TYPE is
            // whatever the one expression owner says its initializer is, and that answer needs live CLR
            // handles the classification pass does not have — so the hoisted field is declared with the
            // UNRESOLVED canonical and realization defines it from the planned initializer. Classification
            // still owns the field's NAME, ROLE and position, which is everything the state numbering and
            // the guarded-layout decision depend on.
            name := nodes.Text(source, node)
            if nodes.ChildCount(node) >= 1 {
                WalkBoundValue(nodes, source, nodes.Child(node, 0), state)
            }
            state.AddLocal(name, UnresolvedCanonical())
            return true
        }
        if kind == 23 {
            // ExpressionStatement: a unit `await` suspension, a postfix step, an assignment to a hoisted
            // binding, or ANY ordinary value expression whose result is discarded (a call statement is
            // the common one). The value forms are not classified here — the expression owner plans them
            // at realization and declines precisely if it cannot.
            if nodes.ChildCount(node) != 1 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported expression statement in an iterator body")
                return false
            }
            inner := nodes.Child(node, 0)
            // `await <task-expr>` as a bare statement (a unit await) is a suspension point in an async
            // iterator; control falls through to the following statement at the await-resume label.
            if nodes.Kind(inner) == 53 {
                if !state.IsAsync {
                    state.Decline("emit.iterator.unsupported-shape", "`await` is only valid inside an async iterator body")
                    return false
                }
                WalkAwait(nodes, source, inner, state)
                return !state.Declined
            }
            // A bare `<ident>++` / `<ident>--` statement (the classic-for increment clause parses to
            // exactly this shape) — the stepped value is discarded.
            if nodes.Kind(inner) == 44 {
                WalkPostfixStep(nodes, source, inner, state)
                return !state.Declined
            }
            if nodes.Kind(inner) == 14 {
                if nodes.ChildCount(inner) != 2 {
                    state.Decline("emit.iterator.unsupported-shape", "unsupported assignment in an iterator body")
                    return false
                }
                target := nodes.Child(inner, 0)
                if nodes.Kind(target) != 6 {
                    // A MEMBER or INDEXER target is an ordinary store — `ColumnarStoreTargetPlanner`
                    // decides which member or `set_Item` it selects, and it needs live CLR handles
                    // this pass does not have. Classification admits the shape and walks both sides
                    // for suspension points; realization answers precisely.
                    if !ColumnarStoreTargetPlanner.ClaimsTarget(nodes, target) {
                        state.Decline("emit.iterator.unsupported-shape", "an iterator assignment target must be a bound identifier, a member or an indexer")
                        return false
                    }
                    WalkExpression(nodes, source, target, state)
                    if state.Declined {
                        return false
                    }
                    WalkExpression(nodes, source, nodes.Child(inner, 1), state)
                    return !state.Declined
                }
                name := nodes.Text(source, target)
                if state.LookupCanonical(name) == "" && state.LookupMemberFieldCanonical(name) == "" {
                    state.Decline("emit.iterator.unsupported-shape", "assignment to an unbound identifier '" + name + "'")
                    return false
                }
                WalkBoundValue(nodes, source, nodes.Child(inner, 1), state)
                return true
            }
            WalkExpression(nodes, source, inner, state)
            return !state.Declined
        }
        if kind == 26 {
            // While [condition, body]: the loop's false-condition exit edge always falls through,
            // whatever the body's own flow does — the body result only drives dead-code dropping.
            if nodes.ChildCount(node) != 2 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported while statement in an iterator body")
                return false
            }
            WalkExpression(nodes, source, nodes.Child(node, 0), state)
            WalkLoopBody(nodes, source, nodes.Child(node, 1), state)
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
                state.Decline("emit.iterator.unsupported-shape", "a for initializer or increment that cannot complete is not lowered in an iterator body")
                return false
            }
            WalkLoopBody(nodes, source, nodes.Child(node, 3), state)
            return !state.Declined
        }
        if kind == 72 {
            // YieldStatement: 1 child = yield return (a resume state, falls through at its resume
            // label), 0 children = yield break (transfers to the shared end label — never falls).
            if nodes.ChildCount(node) == 1 {
                WalkBoundValue(nodes, source, nodes.Child(node, 0), state)
                state.YieldReturnCount = state.YieldReturnCount + 1
                state.ResumeCount = state.ResumeCount + 1
                state.ResumeRegions[state.ResumeCount] = state.CurrentRegion
                return true
            }
            return false
        }
        if kind == 49 {
            return WalkTryStatement(nodes, source, node, state)
        }
        if kind == 29 {
            // Foreach / `for..in` [source, body], loop-var name in the value span. A hoisted ARRAY
            // identifier lowers as an index loop over its own length; EVERY OTHER SOURCE lowers
            // through the sequence's own enumerator, hoisted into a `<>__enum{k}` field inside
            // MoveNext's fault region. The source is an ordinary expression — a call, a member read,
            // an array literal — so its element type is resolved at realization from the planned
            // value rather than guessed from a spelling here. Counters and synthetic names are
            // assigned in walk order, exactly mirrored by the emit walk.
            if nodes.ChildCount(node) != 2 {
                state.Decline("emit.iterator.for-in-unsupported", "unsupported for..in statement in an iterator body")
                return false
            }
            return WalkForIn(nodes, source, node, nodes.Child(node, 0), nodes.Child(node, 1), nodes.Text(source, node), "", state)
        }
        if kind == 73 {
            // `await foreach` composes two machines. What it needs is an AWAIT INSIDE A HANDLER — the
            // inner `IAsyncEnumerator<T>` is released by awaiting its `DisposeAsync()` on the loop's
            // normal exit, on an exception passing through the body, and when a consumer abandons the
            // outer enumeration — which is exactly what the hoisted-handler region provides.
            if !state.IsAsync {
                state.Decline("emit.iterator.async-await-unsupported", "`await foreach` is only valid inside an `async func*` body")
                return false
            }
            if nodes.ChildCount(node) != 2 {
                state.Decline("emit.iterator.for-in-unsupported", "unsupported await foreach statement in an iterator body")
                return false
            }
            return WalkAwaitForIn(nodes, source, nodes.Child(node, 0), nodes.Child(node, 1), nodes.Text(source, node), state)
        }
        if kind == 48 {
            // Throw [exception]: the thrown value is an ordinary expression — `new T(...)` with any
            // constructor arguments, a hoisted exception binding, a factory call. ZERO children is a
            // bare `throw`, the rethrow: it has no operand to hoist and reads nothing. A throw of
            // either shape never falls through.
            if nodes.ChildCount(node) == 0 {
                return false
            }
            if nodes.ChildCount(node) != 1 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported throw statement in an iterator body")
                return false
            }
            WalkExpression(nodes, source, nodes.Child(node, 0), state)
            return false
        }
        if kind == 80 {
            // `off <handle>`: one expression in statement position, exactly like `throw`'s operand.
            // Nothing about it is hoisted — the handle is an ordinary value the expression owner
            // plans — so the walk only has to read it for suspension points.
            if nodes.ChildCount(node) != 1 {
                state.Decline("emit.iterator.unsupported-shape", "`off` has no subscription handle")
                return false
            }
            WalkExpression(nodes, source, nodes.Child(node, 0), state)
            return !state.Declined
        }
        if kind == 20 {
            state.Decline("emit.iterator.unsupported-shape", "a `return` statement cannot appear in an iterator body; use `yield` to produce a value and `yield break` to stop")
            return false
        }
        if kind == 21 || kind == 22 {
            // Break / Continue: a branch to the enclosing loop's exit or step. Neither carries a
            // value, hoists a local or suspends, so the walk has nothing to record — it only has to
            // say that the path does not fall through, which is what makes the rows after it dead.
            // `LoopDepth` is the walk's own nesting count; a placement outside a loop is the
            // analyzer's NL318/NL319 to report, and the decline here is this owner's contract guard.
            if state.LoopDepth == 0 {
                state.Decline("emit.iterator.loop-branch-placement", (kind == 21 ? "`break`" : "`continue`") + " is only valid inside a loop")
            }
            return false
        }
        if kind == 76 {
            // TypedForeach: the annotation's source span is the VALUE slot, children are
            // [name (kind 6), collection, body]. The loop variable's canonical is WRITTEN, so its
            // hoisted field is defined from the annotation rather than from the element, and each
            // element is converted to it once per iteration — exactly the ordinary form's rule.
            if nodes.ChildCount(node) != 3 || nodes.Kind(nodes.Child(node, 0)) != 6 {
                state.Decline("emit.iterator.for-in-unsupported", "unsupported for..in statement in an iterator body")
                return false
            }
            return WalkForIn(nodes, source, node, nodes.Child(node, 1), nodes.Child(node, 2), nodes.Text(source, nodes.Child(node, 0)), nodes.Text(source, node), state)
        }
        state.Decline("emit.iterator.unsupported-shape", "an iterator body statement (node kind " + kind.ToString() + ") is not yet lowered")
        return false
    }

    // THE ONE `for..in` CLASSIFICATION, WRITTEN ONCE FOR BOTH SPELLINGS. `for v in e` and
    // `for v: T in e` differ in exactly one fact — whether the loop variable's type is WRITTEN — so
    // they share this walk and `declaredCanonical` carries that one difference. An annotated variable
    // hoists at its annotation (the field's type is what the author wrote); an inferred one hoists
    // UNRESOLVED and realization defines it from the element the planned source actually produces.
    static func WalkForIn(nodes: ColumnarNodeTable, source: string, node: int, sourceNode: int, bodyNode: int, varName: string, declaredCanonical: string, state: ColumnarIteratorWalkState): bool {
        if nodes.Kind(sourceNode) == 6 {
            sourceName := nodes.Text(source, sourceNode)
            arrayElement := ArrayElementCanonicalOf(state.LookupCanonical(sourceName))
            if arrayElement != "" && IsLowerableArrayElementCanonical(arrayElement) {
                state.AddLocal("<>__index" + state.ForInCount.ToString(), "int")
                state.ForInCount = state.ForInCount + 1
                // The LOOP VARIABLE is a fresh binding per iteration in the language and one field in
                // the machine, so it is recorded at the loop's own depth.
                state.LoopDepth = state.LoopDepth + 1
                state.AddLocal(varName, declaredCanonical == "" ? arrayElement : declaredCanonical)
                state.LoopDepth = state.LoopDepth - 1
                if state.Declined {
                    return false
                }
                // The empty-array exit edge always falls through; the body drives dead-code dropping.
                WalkLoopBody(nodes, source, bodyNode, state)
                return !state.Declined
            }
        }
        WalkExpression(nodes, source, sourceNode, state)
        if state.Declined {
            return false
        }
        state.AddHoistedLocal("<>__enum" + state.EnumeratorCount.ToString(), UnresolvedCanonical(), HoistedEnumeratorFieldRole())
        state.EnumeratorCount = state.EnumeratorCount + 1
        state.LoopDepth = state.LoopDepth + 1
        state.AddLocal(varName, declaredCanonical == "" ? UnresolvedCanonical() : declaredCanonical)
        state.LoopDepth = state.LoopDepth - 1
        if state.Declined {
            return false
        }
        // The exhausted-enumerator exit edge always falls through, like the array form.
        WalkLoopBody(nodes, source, bodyNode, state)
        return !state.Declined
    }

    // `await foreach x in source { … }` — A LOOP THAT IS ALSO A REGION. The enumerator is acquired
    // before the region entry (a resume branches straight to that label and must not acquire a second
    // one), the loop lives inside a protected region, and the release is the region's HOISTED handler
    // because `DisposeAsync()` has to be awaited.
    //
    // The suspension ORDER is what classification owes emission, and it is the order emission writes:
    // the loop's own `await source.MoveNextAsync()` first (its home is the loop's region), then every
    // suspension the body contains, then the release (whose home is the ENCLOSING region, because the
    // handler stands outside the region it releases).
    static func WalkAwaitForIn(nodes: ColumnarNodeTable, source: string, sourceNode: int, bodyNode: int, varName: string, state: ColumnarIteratorWalkState): bool {
        WalkExpression(nodes, source, sourceNode, state)
        if state.Declined {
            return false
        }

        state.AddLocal(AsyncEnumeratorFieldName(state.AsyncEnumeratorCount), UnresolvedCanonical())
        state.AsyncEnumeratorCount = state.AsyncEnumeratorCount + 1
        if state.Declined {
            return false
        }

        region := state.TryRegionCount
        state.TryRegionParents[region] = state.CurrentRegion
        state.TryRegionCount = state.TryRegionCount + 1
        if !DeclareHoistedHandlerFields(region, state) {
            return false
        }

        enclosing := state.CurrentRegion
        state.CurrentRegion = region
        state.AwaitCount = state.AwaitCount + 1
        state.ResumeCount = state.ResumeCount + 1
        state.ResumeRegions[state.ResumeCount] = region
        state.LoopDepth = state.LoopDepth + 1
        state.AddLocal(varName, UnresolvedCanonical())
        state.LoopDepth = state.LoopDepth - 1
        if state.Declined {
            return false
        }

        WalkLoopBody(nodes, source, bodyNode, state)
        state.CurrentRegion = enclosing
        if state.Declined {
            return false
        }

        WalkAwaitedRelease(true, state)
        return !state.Declined
    }

    // The field an `await foreach` enumerator lives in, numbered in walk order — the same contract
    // between the two passes every other synthesized slot has.
    static func AsyncEnumeratorFieldName(ordinal: int): string {
        return "<>__aenum" + ordinal.ToString()
    }

    // A `try` STATEMENT INSIDE A GENERATOR BODY — the shape C# admits, classified.
    //
    // A `yield` may appear inside a `try` that has ONLY a `finally` (the handler runs when the body
    // completes, when an exception passes through, and when a consumer abandons the enumeration and
    // calls `Dispose`), and nowhere else: not inside a `try` that also declares a `catch`, and not
    // inside a `catch` or `finally` handler. Those three placements are refused by the analyzer with
    // NL332; the classification refuses them again here so no shape can reach lowering without a
    // diagnostic, and the messages are the same sentences.
    //
    // Each `try` takes a region ordinal in walk order. A `yield return` inside one records that
    // region as its resume home, which is what lets MoveNext dispatch to a resume point that lives
    // inside a protected region (a branch straight into a region is illegal IL). Each catch clause
    // hoists the exception it binds, exactly like every other local in the body.
    // THE BLOCK WALK, ENTERED AT AN ORDINAL. A using DECLARATION (`using x := e` with no block) guards
    // THE REST OF THE BLOCK, so reaching one means everything after it belongs inside a protected
    // region — and the region has to be opened around those statements rather than around the
    // declaration. The walk therefore hands the remainder to the using walk, which opens the region
    // and calls back in at the next ordinal; the emission walk does the identical thing, so the two
    // passes agree about which region each resume state suspends inside.
    static func WalkBlockChildrenFrom(nodes: ColumnarNodeTable, source: string, node: int, from: int, state: ColumnarIteratorWalkState): bool {
        n := from
        while n < nodes.ChildCount(node) {
            if state.Declined {
                return false
            }

            child := nodes.Child(node, n)
            if (nodes.Kind(child) == 77 || nodes.Kind(child) == 81) && nodes.ChildCount(child) == 1 {
                return WalkUsingDeclarationRegion(nodes, source, node, n, state)
            }

            if !WalkStatement(nodes, source, child, state) {
                return false
            }

            n = n + 1
        }

        return true
    }

    // A `using` INSIDE A GENERATOR BODY IS A `try`/`finally` THAT WRITES ITSELF. It takes a region
    // ordinal exactly as a written `try` does, because the resume machinery cares about the region and
    // not about which keyword opened it.
    //
    // The RESOURCE is acquired OUTSIDE the region — before its entry label — so a resume, which
    // branches straight to that label, never acquires a second resource and never leaks the first.
    static func WalkUsingStatement(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState): bool {
        if nodes.ChildCount(node) != 2 {
            // A using DECLARATION reaches the block walk, which opens the region around its siblings.
            // One that reaches HERE is the brace-less body of an `if` or a loop, where the region it
            // guards is empty — a shape with no reason to exist inside a generator.
            state.Decline("emit.iterator.unsupported-shape", "a `using` declaration with no block is not lowered in this position; write `using r := … { … }` with a block")
            return false
        }

        if !BeginUsingResourceWalk(nodes, source, node, state) {
            return false
        }

        region := state.TryRegionCount
        state.TryRegionParents[region] = state.CurrentRegion
        state.TryRegionCount = state.TryRegionCount + 1
        awaited := nodes.Kind(node) == 81
        if awaited && !DeclareHoistedHandlerFields(region, state) {
            return false
        }
        enclosing := state.CurrentRegion
        state.CurrentRegion = region
        bodyFalls := WalkStatement(nodes, source, nodes.Child(node, 1), state)
        state.CurrentRegion = enclosing
        if state.Declined {
            return false
        }

        WalkAwaitedRelease(awaited, state)
        return bodyFalls
    }

    // THE RELEASE OF AN `await using` IS A SUSPENSION, and it is numbered like every other one: after
    // the body's, because that is where emission writes it. Its home region is the ENCLOSING one —
    // the handler stands OUTSIDE the region it releases, which is the whole of what hoisting means.
    static func WalkAwaitedRelease(awaited: bool, state: ColumnarIteratorWalkState) {
        if !awaited {
            return
        }
        state.AwaitCount = state.AwaitCount + 1
        state.ResumeCount = state.ResumeCount + 1
        state.ResumeRegions[state.ResumeCount] = state.CurrentRegion
    }

    static func WalkUsingDeclarationRegion(nodes: ColumnarNodeTable, source: string, blockNode: int, ordinal: int, state: ColumnarIteratorWalkState): bool {
        usingNode := nodes.Child(blockNode, ordinal)
        if !BeginUsingResourceWalk(nodes, source, usingNode, state) {
            return false
        }

        region := state.TryRegionCount
        state.TryRegionParents[region] = state.CurrentRegion
        state.TryRegionCount = state.TryRegionCount + 1
        awaited := nodes.Kind(usingNode) == 81
        if awaited && !DeclareHoistedHandlerFields(region, state) {
            return false
        }
        enclosing := state.CurrentRegion
        state.CurrentRegion = region
        restFalls := WalkBlockChildrenFrom(nodes, source, blockNode, ordinal + 1, state)
        state.CurrentRegion = enclosing
        if state.Declined {
            return false
        }

        WalkAwaitedRelease(awaited, state)
        return restFalls
    }

    // The resource, hoisted. A BOUND resource is an ordinary local declaration and is walked as one; an
    // unbound one still needs a field to be read from in the handler, so it is given a synthesized name
    // numbered in walk order.
    static func BeginUsingResourceWalk(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState): bool {
        if nodes.Kind(node) == 81 && !state.IsAsync {
            state.Decline("emit.iterator.async-await-unsupported", "`await using` is only valid inside an `async func*` body")
            return false
        }

        resourceNode := nodes.Child(node, 0)
        resourceKind := nodes.Kind(resourceNode)
        if resourceKind == 24 || resourceKind == 40 {
            return WalkStatement(nodes, source, resourceNode, state)
        }

        WalkBoundValue(nodes, source, resourceNode, state)
        if state.Declined {
            return false
        }

        state.AddLocal(UsingResourceFieldName(state.UsingResourceCount), UnresolvedCanonical())
        state.UsingResourceCount = state.UsingResourceCount + 1
        return !state.Declined
    }

    // The field an UNBOUND `using` resource lives in. Numbered in walk order, so classification and
    // emission name the same field without either one telling the other.
    static func UsingResourceFieldName(ordinal: int): string {
        return "<>__using" + ordinal.ToString()
    }

    // THE TWO FIELDS A HOISTED HANDLER NEEDS, and why a handler that awaits needs any at all.
    //
    // A suspension has to leave the method with an EMPTY evaluation stack and come back through the
    // state dispatch — and a dispatch cannot branch INTO a protected region. So an `await` written
    // inside a `finally` can never run inside the region it guards: the handler body is HOISTED out,
    // to the ordinary code just past the region's end, which is exactly what Roslyn's
    // `AsyncMethodToStateMachineRewriter.VisitTryStatement` does.
    //
    // Hoisting costs the two things a real `finally` gave for free. The exception in flight no longer
    // survives the region on its own, so a catch-all parks it in `<>__pending{k}` (an
    // `ExceptionDispatchInfo`, so the original stack trace is preserved when it is re-raised AFTER the
    // handler has run). And a branch OUT of the statement — a `yield break`, or the unwind of an
    // abandoned machine — can no longer jump straight to the body's end label, because that would
    // skip the hoisted handler entirely; it records where it was going in `<>__branch{k}` and leaves
    // to the region end instead, and the rows after the handler take the branch.
    //
    // Both live on the state machine because the handler itself may suspend: a plan local would not
    // survive the drive that resumes inside it.
    static func PendingExceptionFieldName(region: int): string {
        return "<>__pending" + region.ToString()
    }

    static func PendingBranchFieldName(region: int): string {
        return "<>__branch" + region.ToString()
    }

    static func DeclareHoistedHandlerFields(region: int, state: ColumnarIteratorWalkState): bool {
        state.AddLocal(PendingExceptionFieldName(region), UnresolvedCanonical())
        state.AddLocal(PendingBranchFieldName(region), "int")
        return !state.Declined
    }

    static func WalkTryStatement(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState): bool {
        childCount := nodes.ChildCount(node)
        if childCount < 1 || nodes.Kind(nodes.Child(node, 0)) != 25 {
            state.Decline("emit.iterator.unsupported-shape", "unsupported try statement in an iterator body")
            return false
        }
        finallyNode := 0 - 1
        handlerEnd := childCount
        if childCount >= 2 && nodes.Kind(nodes.Child(node, childCount - 1)) == 25 {
            finallyNode = nodes.Child(node, childCount - 1)
            handlerEnd = childCount - 1
        }
        catchCount := handlerEnd - 1
        tryBlock := nodes.Child(node, 0)
        if ContainsYield(nodes, tryBlock) && catchCount > 0 {
            state.Decline("emit.iterator.unsupported-shape", YieldInTryWithCatchMessage())
            return false
        }
        c := 1
        while c < handlerEnd {
            if ContainsYield(nodes, nodes.Child(node, c)) {
                state.Decline("emit.iterator.unsupported-shape", YieldInHandlerMessage("catch"))
                return false
            }
            if ContainsAwait(nodes, nodes.Child(node, c)) {
                state.Decline("emit.iterator.async-await-unsupported", AwaitInHandlerMessage("catch"))
                return false
            }
            c = c + 1
        }
        if finallyNode >= 0 && ContainsYield(nodes, finallyNode) {
            state.Decline("emit.iterator.unsupported-shape", YieldInHandlerMessage("finally"))
            return false
        }
        hoistedFinally := finallyNode >= 0 && ContainsAwait(nodes, finallyNode)
        if hoistedFinally && !state.IsAsync {
            state.Decline("emit.iterator.async-await-unsupported", AwaitInHandlerMessage("finally"))
            return false
        }
        if hoistedFinally && catchCount > 0 {
            // The hoisted form replaces the statement's own handlers with ONE catch-all that parks the
            // exception, so a `catch` clause beside an awaiting `finally` would have to be re-matched
            // by hand against the parked exception. That is a separate shape from this slice's.
            state.Decline("emit.iterator.async-await-unsupported", "an `await` inside a `finally` is not yet lowered when the same `try` also declares a `catch`")
            return false
        }
        if catchCount == 0 && finallyNode < 0 {
            state.Decline("emit.iterator.unsupported-shape", "a `try` statement needs a `catch` or a `finally` handler")
            return false
        }

        region := state.TryRegionCount
        state.TryRegionParents[region] = state.CurrentRegion
        state.TryRegionCount = state.TryRegionCount + 1
        if hoistedFinally && !DeclareHoistedHandlerFields(region, state) {
            return false
        }
        enclosing := state.CurrentRegion
        state.CurrentRegion = region
        tryFalls := WalkStatement(nodes, source, tryBlock, state)
        state.CurrentRegion = enclosing
        if state.Declined {
            return false
        }

        handlersFall := false
        c = 1
        while c < handlerEnd {
            clause := nodes.Child(node, c)
            if nodes.Kind(clause) != 50 || nodes.ChildCount(clause) < 1 {
                state.Decline("emit.iterator.unsupported-shape", "unsupported catch clause in an iterator body")
                return false
            }
            state.AddLocal(CatchBindingName(nodes, source, clause, state.CatchCount), CatchTypeCanonical(nodes, source, clause))
            state.CatchCount = state.CatchCount + 1
            if state.Declined {
                return false
            }
            if WalkStatement(nodes, source, nodes.Child(clause, nodes.ChildCount(clause) - 1), state) {
                handlersFall = true
            }
            if state.Declined {
                return false
            }
            c = c + 1
        }
        if finallyNode >= 0 {
            if !WalkStatement(nodes, source, finallyNode, state) {
                // A `finally` that cannot complete would swallow every path through the statement;
                // the analyzer already refuses control transfers out of one, so the remaining way to
                // reach this is an unconditional `throw`, which no lowering can resume from.
                state.Decline("emit.iterator.unsupported-shape", "a `finally` handler that cannot complete is not lowered in an iterator body")
                return false
            }
            if state.Declined {
                return false
            }
        }
        return tryFalls || handlersFall
    }

    // The name the caught exception is hoisted under: the clause's own variable when it binds one,
    // and a synthesized slot otherwise — the handler still needs a typed place to put the exception
    // the runtime hands it, because a state machine's bindings are fields.
    static func CatchBindingName(nodes: ColumnarNodeTable, source: string, clause: int, ordinal: int): string {
        if nodes.ChildCount(clause) == 2 && nodes.Kind(nodes.Child(clause, 0)) == 6 {
            return nodes.Text(source, nodes.Child(clause, 0))
        }
        return "<>__exception" + ordinal.ToString()
    }

    // The exception type a catch clause selects. A bare `catch` selects `System.Exception`, exactly
    // as it does in an ordinary body.
    static func CatchTypeCanonical(nodes: ColumnarNodeTable, source: string, clause: int): string {
        if nodes.ValueStart(clause) >= 0 {
            return nodes.Text(source, clause)
        }
        return "System.Exception"
    }

    static func YieldInTryWithCatchMessage(): string {
        return "a `yield` cannot appear inside a `try` that declares a `catch`; a generator may only suspend inside a `try` whose only handler is `finally`"
    }

    static func YieldInHandlerMessage(handler: string): string {
        return "a `yield` cannot appear inside a `" + handler + "` handler"
    }

    static func AwaitInHandlerMessage(handler: string): string {
        return "an `await` inside a `" + handler + "` handler is not yet lowered: a suspension there has no resume point to return to"
    }

    // THE EXPRESSION WALK NO LONGER CLASSIFIES VALUES, AND THAT IS THE POINT OF THIS OWNER.
    //
    // An iterator body's expressions are ORDINARY expressions: a call, a `new`, an array literal, an
    // indexer, a member access, a binary. Deciding which of those a body may contain is a question with
    // exactly one owner — `ColumnarMethodBodyPlanner`'s expression door and the planners behind it —
    // and that owner needs live CLR handles this pass does not have. So classification walks an
    // expression only for the two things that are the STATE MACHINE'S own business and cannot be seen
    // later: a suspension point (`await`) that consumes a resume state, and a postfix step whose target
    // must be a writable hoisted binding. Everything else is admitted here and answered, precisely, by
    // the expression owner at realization.
    static func WalkExpression(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState) {
        if state.Declined {
            return
        }
        kind := nodes.Kind(node)
        if kind == 53 {
            // `await` reaches WalkExpression only in a VALUE position (initializer, yield value,
            // operand); suspension points are statement-position unit awaits handled by WalkStatement.
            if !state.IsAsync {
                state.Decline("emit.iterator.unsupported-shape", "`await` is only valid inside an async iterator body")
                return
            }
            state.Decline("emit.iterator.async-await-unsupported", "an `await` nested inside a larger expression is not yet lowered in an async iterator body; bind it first (`value := await ...`)")
            return
        }
        if kind == 44 {
            // postfix `++`/`--` in VALUE position (`yield i++`): pushes the pre-step value, then steps
            // the binding — the same target admission as the statement form.
            WalkPostfixStep(nodes, source, node, state)
            return
        }
        if ColumnarLambdaNodeFacts.IsLambda(kind) {
            WalkLambda(nodes, source, node, state)
            return
        }
        c := 0
        while c < nodes.ChildCount(node) {
            WalkExpression(nodes, source, nodes.Child(node, c), state)
            if state.Declined {
                return
            }
            c = c + 1
        }
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
            state.Decline("emit.iterator.unsupported-shape", "a postfix step target must be a bound identifier in an iterator body")
            return
        }
        name := nodes.Text(source, target)
        canonical := state.LookupCanonical(name)
        if canonical == "" {
            state.Decline("emit.iterator.unsupported-shape", "postfix step of an unbound or read-only identifier '" + name + "' in an iterator body")
            return
        }
        // A binding whose type is resolved at realization is admitted here and type-checked there,
        // against the field's exact CLR type rather than against a spelling.
        if canonical != "int" && !IsUnresolvedCanonical(canonical) {
            state.Decline("emit.iterator.unsupported-shape", "postfix step over a non-int binding ('" + name + "': '" + canonical + "') is not yet lowered in an iterator body")
        }
    }

    // A LAMBDA INSIDE A GENERATOR BODY. Outside bindings already live on the state machine,
    // including an instance generator's captured receiver in `<>__this`. A lambda using only those
    // bindings can use the machine directly as its closure owner.
    //
    // A loop-declared capture needs different storage: classification records it so realization can
    // allocate a fresh StrongBox for each iteration and snapshot that box reference into the lambda's
    // display. Locals declared outside loops remain fields on the machine and stay shared.
    static func WalkLambda(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState) {
        childCount := nodes.ChildCount(node)
        if childCount < 1 {
            state.Decline("emit.iterator.lambda-unsupported", "malformed lambda in an iterator body")
            return
        }
        bodyNode := nodes.Child(node, childCount - 1)
        RecordCapturedLoopLocals(nodes, source, node, state)
        if ColumnarLambdaNodeFacts.IsAsyncLambda(nodes.Kind(node)) {
            // Every await in this subtree belongs to the synthesized lambda method and consumes no
            // resume state from the enclosing iterator. Keep walking for captures and mutations,
            // while leaving the lambda body's own await admission to realization.
            WalkAsyncLambdaExpression(nodes, source, bodyNode, state)
            return
        }
        WalkExpression(nodes, source, bodyNode, state)
    }

    static func WalkAsyncLambdaExpression(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState) {
        kind := nodes.Kind(node)
        if kind == 44 {
            WalkPostfixStep(nodes, source, node, state)
            return
        }
        if ColumnarLambdaNodeFacts.IsLambda(kind) {
            WalkLambda(nodes, source, node, state)
            return
        }
        child := 0
        while child < nodes.ChildCount(node) {
            WalkAsyncLambdaExpression(nodes, source, nodes.Child(node, child), state)
            if state.Declined {
                return
            }
            child = child + 1
        }
    }

    // Every name the lambda reads that is a hoisted local declared inside a loop. The lambda's own
    // parameters shadow the body's bindings and are skipped. Realization gives each recorded name a
    // fresh StrongBox per iteration, then snapshots those box references into the lambda display.
    static func RecordCapturedLoopLocals(nodes: ColumnarNodeTable, source: string, lambda: int, state: ColumnarIteratorWalkState) {
        childCount := nodes.ChildCount(lambda)
        parameterNames := new HashSet<string>(StringComparer.Ordinal)
        p := 0
        while p < childCount - 1 {
            parameterNames.Add(nodes.Text(source, nodes.Child(lambda, p)))
            p = p + 1
        }
        loopLocals := new HashSet<string>(StringComparer.Ordinal)
        local := 0
        while local < state.LocalCount {
            if state.LocalLoopDepths[local] > 0 {
                loopLocals.Add(state.LocalNames[local])
            }
            local = local + 1
        }
        captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(nodes, source, nodes.Child(lambda, childCount - 1), parameterNames, loopLocals)
        for capture in captures {
            state.RecordLoopCapture(capture)
        }
    }

    // A LOOP BODY, walked one nesting level deeper. The depth is what the lambda-capture rule reads:
    // a local declared here is one field re-used by every iteration, so a closure created here cannot
    // be given the fresh binding per iteration the language promises.
    static func WalkLoopBody(nodes: ColumnarNodeTable, source: string, bodyNode: int, state: ColumnarIteratorWalkState): bool {
        state.LoopDepth = state.LoopDepth + 1
        fell := WalkStatement(nodes, source, bodyNode, state)
        state.LoopDepth = state.LoopDepth - 1
        return fell
    }

    // A VALUE WHOSE RESULT IS BOUND — the initializer of a declaration, the right-hand side of an
    // assignment to a binding, the operand of a `yield`. These are the positions where an `await` can
    // be the WHOLE value, and therefore the positions where a suspension point has somewhere to put
    // its result: the awaited value lands in the storage the statement already names, so the
    // suspension needs no spill slot of its own. An `await` nested inside a larger expression does
    // need one, and declines with that reason rather than silently losing its result.
    static func WalkBoundValue(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState) {
        if nodes.Kind(node) == 53 {
            if !state.IsAsync {
                state.Decline("emit.iterator.unsupported-shape", "`await` is only valid inside an async iterator body")
                return
            }
            WalkAwait(nodes, source, node, state)
            return
        }
        WalkExpression(nodes, source, node, state)
    }

    // AN `await <operand>` — a suspension point that resumes at its own state, exactly like a
    // `yield return`. Classification counts it and walks the operand as the ORDINARY expression it
    // is; WHICH awaitable it names, and therefore which awaiter type the machine hoists, is a
    // question that needs live CLR handles, so the emission asks the awaitable pattern
    // (`GetAwaiter()` / `IsCompleted` / `OnCompleted(Action)` / `GetResult()`) of whatever the
    // operand's planned type turns out to be.
    static func WalkAwait(nodes: ColumnarNodeTable, source: string, node: int, state: ColumnarIteratorWalkState) {
        if nodes.ChildCount(node) != 1 {
            state.Decline("emit.iterator.async-await-unsupported", "malformed await expression in an async iterator body")
            return
        }
        state.AwaitCount = state.AwaitCount + 1
        state.ResumeCount = state.ResumeCount + 1
        state.ResumeRegions[state.ResumeCount] = state.CurrentRegion
        WalkExpression(nodes, source, nodes.Child(node, 0), state)
    }

    // THE MARKER FOR A HOISTED FIELD WHOSE TYPE REALIZATION RESOLVES. Classification owns a hoisted
    // field's name, role and position; its CLR TYPE is whatever the one expression owner says the
    // initializer (or the enumerated source) is, and that answer needs live handles. `?` is not a
    // spelling any source type can have, so it never collides with a written canonical.
    static func UnresolvedCanonical(): string {
        return "?"
    }

    static func IsUnresolvedCanonical(canonical: string): bool {
        return canonical == "?"
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
    static func ArrayElementCanonicalOf(canonical: string): string {
        if canonical.Length < 3 || canonical[canonical.Length - 2] != '[' || canonical[canonical.Length - 1] != ']' {
            return ""
        }
        return canonical.Substring(0, canonical.Length - 2)
    }

    // The element canonical of an enumerator-lowered sequence source: "IEnumerable<X>" or "List<X>"
    // (List<T> implements IEnumerable<T>, so both route through the same interface calls); "" otherwise.
    static func EnumerableElementCanonicalOf(canonical: string): string {
        element := GenericArgumentCanonicalOf(canonical, "IEnumerable<")
        if element != "" {
            return element
        }
        return GenericArgumentCanonicalOf(canonical, "List<")
    }

    // The element canonical of a hoisted enumerator field canonical ("IEnumerator<X>" -> "X").
    static func EnumeratorElementCanonicalOf(canonical: string): string {
        return GenericArgumentCanonicalOf(canonical, "IEnumerator<")
    }

    static func GenericArgumentCanonicalOf(canonical: string, prefix: string): string {
        if canonical.Length <= prefix.Length + 1 || canonical.Substring(0, prefix.Length) != prefix || canonical[canonical.Length - 1] != '>' {
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
    static func ContainsYield(nodes: ColumnarNodeTable, node: int): bool {
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

    // Does this subtree contain a suspension that is an `await`? A handler position — a `catch` or a
    // `finally` body — is where the question matters: a suspension there has no resume label to come
    // back to, because resuming would re-enter the protected region the handler is unwinding.
    static func ContainsAwait(nodes: ColumnarNodeTable, node: int): bool {
        if nodes.Kind(node) == 53 {
            return true
        }
        c := 0
        while c < nodes.ChildCount(node) {
            if ContainsAwait(nodes, nodes.Child(node, c)) {
                return true
            }
            c = c + 1
        }
        return false
    }

    // Array elements the MoveNext lowering has a typed ldelem opcode for.
    static func IsLowerableArrayElementCanonical(element: string): bool {
        return element == "int" || element == "long" || element == "float" || element == "double" || element == "bool" || element == "char" || element == "string"
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
class ColumnarIteratorEmitContext {
    Nodes: ColumnarNodeTable
    Source: string
    BodyRoot: int
    Shape: ColumnarIteratorShape
    StateMachineType: Type
    ElementType: Type
    FieldNames: string[]
    Fields: FieldInfo[]
    DefinitionFields: FieldInfo[]
    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable
    Constructor: ConstructorInfo?
    // Instance-iterator extras (empty for top-level machines): the enclosing type plus its readable
    // field / callable method handles, and the canonical->runtime-type table for sequence elements.
    EnclosingType: Type?
    EnclosingFieldNames: string[]
    EnclosingFields: FieldInfo[]
    EnclosingFieldCanonicals: string[]
    EnclosingMethodNames: string[]
    EnclosingMethods: MethodInfo[]
    // Async-machine extra: the MoveNextCore handle MoveNextAsync's plan drives (null for sync machines).
    CoreMethod: MethodInfo?
    // The machine's own MoveNext, published once the realization has defined it. `Dispose` drives it
    // in dispose mode to unwind a machine abandoned inside a protected region; a machine that cannot
    // suspend inside one never reads it.
    MoveNextMethod: MethodInfo?
    // The body's ORDINARY-EXPRESSION scope: the state machine's name bindings expressed as the one
    // fragment-binding contract, so every value in the body reaches the single expression owner.
    Scope: ColumnarIteratorBodyScope?
    // The live machine builder and — for a generic machine — the instantiation its member handles are
    // taken on. A hoisted local's CLR type is known only once its initializer has been planned, so its
    // field is DEFINED as the lowering reaches the declaration rather than ahead of the body.
    Builder: TypeBuilder?
    GenericMemberType: Type?
    SynthesizedTypes: List<TypeBuilder>?
    TypeParameters: Dictionary<string, Type>?
    GenericSpecialConstraints: int[]
    GenericBaseConstraints: Type?[]
    GenericInterfaceConstraints: Type[][]
    GenericParameters: Type[]
    SourceFileId: int
    DeclineSite: string
    DeclineMessage: string

    constructor(nodes: ColumnarNodeTable, source: string, bodyRoot: int, shape: ColumnarIteratorShape, stateMachineType: Type, elementType: Type, fieldNames: string[], fields: FieldInfo[], structuralTypeReferences: ColumnarStructuralTypeReferenceTable, smConstructor: ConstructorInfo? = null, enclosingType: Type? = null, enclosingFieldNames: string[]? = null, enclosingFields: FieldInfo[]? = null, enclosingFieldCanonicals: string[]? = null, enclosingMethodNames: string[]? = null, enclosingMethods: MethodInfo[]? = null, coreMethod: MethodInfo? = null, bodyFacts: ColumnarIteratorBodyFacts? = null, builder: TypeBuilder? = null, genericMemberType: Type? = null, typeParameters: Dictionary<string, Type>? = null, definitionFields: FieldInfo[]? = null, synthesizedTypes: List<TypeBuilder>? = null, sourceFileId: int = 0, genericSpecialConstraints: int[]? = null, genericBaseConstraints: Type?[]? = null, genericInterfaceConstraints: Type[][]? = null, genericParameters: Type[]? = null) {
        Nodes = nodes
        Source = source
        BodyRoot = bodyRoot
        Shape = shape
        StateMachineType = stateMachineType
        ElementType = elementType
        FieldNames = fieldNames
        Fields = fields
        DefinitionFields = definitionFields ?? fields
        StructuralTypeReferences = structuralTypeReferences
        Constructor = smConstructor
        EnclosingType = enclosingType
        EnclosingFieldNames = enclosingFieldNames ?? new string[](0)
        EnclosingFields = enclosingFields ?? new FieldInfo[](0)
        EnclosingFieldCanonicals = enclosingFieldCanonicals ?? new string[](0)
        EnclosingMethodNames = enclosingMethodNames ?? new string[](0)
        EnclosingMethods = enclosingMethods ?? new MethodInfo[](0)
        CoreMethod = coreMethod
        MoveNextMethod = null
        Builder = builder
        GenericMemberType = genericMemberType
        SynthesizedTypes = synthesizedTypes
        TypeParameters = typeParameters
        GenericSpecialConstraints = genericSpecialConstraints ?? System.Array.Empty<int>()
        GenericBaseConstraints = genericBaseConstraints ?? System.Array.Empty<Type?>()
        GenericInterfaceConstraints = genericInterfaceConstraints ?? System.Array.Empty<Type[]>()
        GenericParameters = genericParameters ?? System.Array.Empty<Type>()
        SourceFileId = sourceFileId
        DeclineSite = ""
        DeclineMessage = ""

        // THE BODY'S NAME BINDINGS, PUBLISHED ONCE HERE. Every field the machine already has is visible
        // to the body's own code as a field of `this`; an instance machine's enclosing members are
        // visible through the captured receiver. A machine whose program facts are not supplied — a
        // contract that exercises the member bodies rather than a program — still gets a scope, with an
        // empty declaration registry, so the ONE expression owner is reachable from every context.
        scopeTable := StructuralTypeReferences
        if scopeTable == null {
            scopeTable = new ColumnarStructuralTypeReferenceTable()
        }
        bodyScope := ColumnarIteratorBodyScope.Create(stateMachineType, bodyFacts ?? ColumnarIteratorBodyFacts.Empty(scopeTable), typeParameters)
        index := 0
        while index < FieldNames.Length && index < Fields.Length {
            if Fields[index] != null {
                bodyScope.PublishField(FieldNames[index], Fields[index])
            }
            index = index + 1
        }
        capture := 0
        while capture < Shape.LoopCaptureNames.Length {
            captureName := Shape.LoopCaptureNames[capture]
            boxName := ColumnarIteratorPlanner.LoopCaptureBoxFieldName(captureName)
            boxIndex := FieldIndex(boxName)
            valueIndex := FieldIndex(captureName)
            if boxIndex >= 0 && valueIndex >= 0 && Fields[boxIndex] != null && Fields[valueIndex] != null {
                bodyScope.PublishBoxedCapture(captureName, Fields[boxIndex], Fields[valueIndex].get_FieldType())
            }
            capture = capture + 1
        }
        if bodyScope.HasField("<>__this") {
            receiver := bodyScope.FieldHandle("<>__this")
            member := 0
            while member < EnclosingFieldNames.Length && member < EnclosingFields.Length {
                bodyScope.PublishEnclosingMember(EnclosingFieldNames[member], receiver, EnclosingFields[member])
                member = member + 1
            }
        }
        Scope = bodyScope
    }

    Declined: bool => DeclineMessage.Length > 0

    func Decline(site: string, message: string) {
        if DeclineMessage.Length == 0 {
            DeclineSite = site
            DeclineMessage = message
        }
    }

    // Whether a value of `valueType` can live in a field of `fieldType` without a conversion the store
    // itself would have to emit. Identity always; a reference widening when both handles are baked (a
    // builder-bound handle cannot answer `IsAssignableFrom` at all under persisted emit, so identity is
    // the only answer it gets).
    static func IsStorableInField(fieldType: Type, valueType: Type): bool {
        if fieldType == valueType {
            return true
        }
        // A BUILDER-BOUND handle cannot answer an assignability question at all under persisted emit —
        // `TypeBuilder` and a generic instantiation over one both throw from `IsAssignableFrom` — so
        // identity is the only answer such a pair gets.
        if fieldType == null || valueType == null || ColumnarConstructionPlanner.ContainsBuilderBoundType(fieldType) || ColumnarConstructionPlanner.ContainsBuilderBoundType(valueType) || fieldType.get_IsValueType() || valueType.get_IsValueType() {
            return false
        }
        return fieldType.IsAssignableFrom(valueType)
    }

    func RequiredScope(): ColumnarIteratorBodyScope {
        scope := Scope
        if scope == null {
            throw new InvalidOperationException("Iterator body lowering requires an expression scope.")
        }
        return scope
    }

    // Define — or reuse — the hoisted field a declaration binds, now that its value's exact CLR type is
    // known. A re-declaration of the same name in disjoint scopes shares one slot exactly when the two
    // declarations agree on the type; disagreeing declarations cannot share a CLR field and decline.
    func TryEnsureHoistedField(name: string, fieldType: Type, out field: FieldInfo): bool {
        field = null
        if fieldType == null || fieldType.FullName == "System.Void" || fieldType.get_IsByRef() || fieldType.get_IsPointer() {
            return false
        }
        index := 0
        while index < FieldNames.Length {
            if FieldNames[index] == name {
                existing := Fields[index]
                if existing != null {
                    // A slot that already exists — an explicitly typed declaration, a re-declaration in a
                    // disjoint scope, or a field the host supplied — keeps ITS type, and the value must
                    // be storable in it. `v := 1` then `v := true` in disjoint branches cannot share a
                    // CLR field and declines here; a declared `x: object = ...` holding a narrower value
                    // does, exactly as an assignment to that declaration would.
                    if !IsStorableInField(existing.get_FieldType(), fieldType) {
                        return false
                    }
                    if !TryPublishLoopCaptureBox(name, existing.get_FieldType()) {
                        return false
                    }
                    field = existing
                    return true
                }
                builder := Builder
                if builder == null {
                    throw new InvalidOperationException("Iterator body lowering requires the state-machine builder to define a hoisted field.")
                }
                defined := builder.DefineField(name, fieldType, FieldAttributes.Public)
                handle: FieldInfo = defined
                instantiation := GenericMemberType
                if instantiation != null {
                    handle = TypeBuilder.GetField(instantiation, defined)
                }
                Fields[index] = handle
                definitionHandle: FieldInfo = defined
                DefinitionFields[index] = definitionHandle
                RequiredScope().PublishField(name, handle)
                TryPublishLoopCaptureBox(name, fieldType)
                field = handle
                return true
            }
            index = index + 1
        }
        return false
    }

    private func FieldIndex(name: string): int {
        index := 0
        while index < FieldNames.Length {
            if FieldNames[index] == name {
                return index
            }
            index = index + 1
        }
        return 0 - 1
    }

    func IsLoopCaptured(name: string): bool {
        for captureName in Shape.LoopCaptureNames {
            if captureName == name {
                return true
            }
        }
        return false
    }

    private func TryPublishLoopCaptureBox(name: string, valueType: Type): bool {
        if !IsLoopCaptured(name) {
            return true
        }
        boxName := ColumnarIteratorPlanner.LoopCaptureBoxFieldName(name)
        boxIndex := FieldIndex(boxName)
        if boxIndex < 0 {
            return false
        }
        boxHandle := Fields[boxIndex]
        if boxHandle == null {
            builder := Builder
            if builder == null {
                return false
            }
            boxType := ColumnarIteratorPlanner.LoopCaptureBoxType(valueType)
            defined := builder.DefineField(boxName, boxType, FieldAttributes.Public)
            boxHandle = defined
            if GenericMemberType != null {
                boxHandle = TypeBuilder.GetField(GenericMemberType, defined)
            }
            Fields[boxIndex] = boxHandle
            definitionHandle: FieldInfo = defined
            DefinitionFields[boxIndex] = definitionHandle
            RequiredScope().PublishField(boxName, boxHandle)
        }
        RequiredScope().PublishBoxedCapture(name, boxHandle, valueType)
        return true
    }

    func TryEnsureLoopCaptureBox(name: string, valueType: Type, out field: FieldInfo): bool {
        field = null
        if !TryPublishLoopCaptureBox(name, valueType) {
            return false
        }
        field = Fields[FieldIndex(ColumnarIteratorPlanner.LoopCaptureBoxFieldName(name))]
        return field != null
    }

    func DefinitionFieldForName(name: string): FieldInfo {
        index := FieldIndex(name)
        if index < 0 || DefinitionFields[index] == null {
            throw new InvalidOperationException("Iterator state machine has no definition field named '" + name + "'.")
        }
        return DefinitionFields[index]
    }

    func RequiredCoreMethod(): MethodInfo {
        handle := CoreMethod
        if handle == null {
            throw new InvalidOperationException("Iterator emit context carries no MoveNextCore handle.")
        }
        return handle
    }

    func HasHoistedField(name: string): bool {
        i := 0
        while i < FieldNames.Length {
            if FieldNames[i] == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    func EnclosingFieldIndex(name: string): int {
        i := 0
        while i < EnclosingFieldNames.Length {
            if EnclosingFieldNames[i] == name {
                return i
            }
            i = i + 1
        }
        return 0 - 1
    }

    func EnclosingMethodForName(name: string): MethodInfo {
        i := 0
        while i < EnclosingMethodNames.Length {
            if EnclosingMethodNames[i] == name {
                return EnclosingMethods[i]
            }
            i = i + 1
        }
        throw new InvalidOperationException("Iterator emit context has no enclosing method named '" + name + "'.")
    }

    func FieldForName(name: string): FieldInfo {
        i := 0
        while i < FieldNames.Length {
            if FieldNames[i] == name {
                handle := Fields[i]
                if handle == null {
                    throw new InvalidOperationException("Iterator state-machine field '" + name + "' is read before its declaration defines it.")
                }
                return handle
            }
            i = i + 1
        }
        throw new InvalidOperationException("Iterator state machine has no field named '" + name + "'.")
    }

    func FieldCanonicalForName(name: string): string {
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
    func RequiredConstructor(): ConstructorInfo {
        handle := Constructor
        if handle == null {
            throw new InvalidOperationException("Iterator emit context carries no state-machine constructor handle.")
        }
        return handle
    }
}

class ColumnarIteratorLambdaDisplay {
    Definition: TypeBuilder
    MethodOwnerType: Type
    RuntimeOwnerType: Type
    Constructor: ConstructorInfo
    RuntimeConstructor: ConstructorInfo
    MachineField: FieldInfo
    RuntimeMachineField: FieldInfo
    CaptureNames: string[]
    CaptureFields: FieldInfo[]
    RuntimeCaptureFields: FieldInfo[]
    MachineCaptureFields: FieldInfo[]
    RuntimeMachineCaptureFields: FieldInfo[]
    EnclosingReceiverField: FieldInfo?
    RuntimeEnclosingReceiverField: FieldInfo?
    RuntimeMachineReceiverField: FieldInfo?
    TypeParameters: Dictionary<string, Type>

    constructor(definition: TypeBuilder, methodOwnerType: Type, runtimeOwnerType: Type, constructorHandle: ConstructorInfo, runtimeConstructor: ConstructorInfo, machineField: FieldInfo, runtimeMachineField: FieldInfo, captureNames: string[], captureFields: FieldInfo[], runtimeCaptureFields: FieldInfo[], machineCaptureFields: FieldInfo[], runtimeMachineCaptureFields: FieldInfo[], enclosingReceiverField: FieldInfo?, runtimeEnclosingReceiverField: FieldInfo?, runtimeMachineReceiverField: FieldInfo?, typeParameters: Dictionary<string, Type>) {
        Definition = definition
        MethodOwnerType = methodOwnerType
        RuntimeOwnerType = runtimeOwnerType
        Constructor = constructorHandle
        RuntimeConstructor = runtimeConstructor
        MachineField = machineField
        RuntimeMachineField = runtimeMachineField
        CaptureNames = captureNames
        CaptureFields = captureFields
        RuntimeCaptureFields = runtimeCaptureFields
        MachineCaptureFields = machineCaptureFields
        RuntimeMachineCaptureFields = runtimeMachineCaptureFields
        EnclosingReceiverField = enclosingReceiverField
        RuntimeEnclosingReceiverField = runtimeEnclosingReceiverField
        RuntimeMachineReceiverField = runtimeMachineReceiverField
        TypeParameters = typeParameters
    }
}

// Mutable state threaded through the recursive MoveNext lowering.
class ColumnarMoveNextEmit {
    Plan: ColumnarCodePlan
    Context: ColumnarIteratorEmitContext
    ThisArg: int
    StateFieldPool: int
    ResumeLabels: int[]
    EndLabel: int
    NextYield: int
    NextForIn: int
    NextEnumerator: int
    // Region mode (any hoisted enumerator): the whole dispatch+body sits inside a try/FAULT region,
    // so every suspend/finish path stores the result local and `leave`s to the ret outside the region
    // (ECMA forbids `ret` inside a protected region; per-call re-entry through the try start plus an
    // in-region dispatch branch is how the machine legally resumes inside the region).
    RegionMode: bool
    ResultLocal: int
    RegionEndLabel: int
    // FaultGuarded marks the outer try/FAULT wrapper: at depth 0 the code is already inside a
    // protected region, so every exit is a `leave`. RegionDepth counts the body's own `try`
    // statements, RegionEntryLabels[k] is the point just before region k's `try` (the only legal way
    // to reach a resume label inside it), and NextTryRegion assigns ordinals in the same walk order
    // classification used.
    FaultGuarded: bool
    RegionDepth: int
    RegionEntryLabels: int[]
    // THE HOISTED-HANDLER STACK. A region whose handler awaits does not close with a real `finally`:
    // the handler body stands just past the region end, in ordinary code, so every branch OUT of the
    // statement has to stop there on the way. `HoistedRegionEnds[d]` is the region end such a branch
    // leaves to and `HoistedBranchFields[d]` is the field it records its destination in; depth 0 means
    // no hoisted region is open and a branch to the body's end label is the plain one.
    HoistedRegionEnds: int[]
    HoistedBranchFields: string[]
    HoistedDepth: int
    // How many hoisted HANDLER BODIES the walk is writing inside. A handler is already an unwind, so
    // a suspension inside one must not re-issue the abandonment branch when it resumes: the machine
    // is standing in the very handler that branch exists to run.
    HoistedHandlerDepth: int
    NextTryRegion: int
    NextUsingResource: int
    // Async mode: yields and awaits share ONE resume-state counter (walk order), awaits number their
    // awaiter fields with NextAwait, and suspension/completion go through the promise/result fields.
    IsAsync: bool
    NextResume: int
    NextAwait: int
    NextAsyncEnumerator: int
    NextLambda: int
    // How many `catch` HANDLER BODIES of this MoveNext the walk is writing inside. IL `rethrow` is
    // valid only there, and a state machine's handlers are real EH clauses on this same method, so
    // the counter answers the question exactly as the ordinary body emitter's does. A generator body
    // cannot open a `finally` INSIDE a `catch` (a `try` that declares a `catch` refuses to hold a
    // suspension point at all), so there is no nested-finally barrier to track alongside it.
    CatchHandlerDepth: int
    // How many `finally` HANDLER BODIES the walk is writing inside. A branch OUT of a finally is
    // illegal IL whatever it targets, so `break`/`continue` refuses to cross one — the same guard the
    // ordinary body emitter keeps, and the analyzer has already reported NL319 for the shape.
    FinallyHandlerDepth: int
    // THE ENCLOSING LOOPS' BRANCH TARGETS, innermost LAST. `break` goes to the loop's exit label and
    // `continue` to the label standing just before its step and back edge, so a counted loop's
    // increment still runs on the continue path exactly as it does on the fall-through one. Each
    // frame also records the depths the loop was OPENED at: a branch that crosses a protected region
    // must be `leave` rather than `br`, one that would leave a `finally` cannot be written at all,
    // and one that would cross a HOISTED handler (an `await`-bearing `finally`, or the region an
    // `await foreach` keeps) has a handler to run on the way out that this branch does not know how
    // to re-issue — so that frame is marked not-lowerable and declines by name instead of silently
    // skipping the handler.
    LoopBreakLabels: List<int>
    LoopContinueLabels: List<int>
    LoopRegionDepths: List<int>
    LoopFinallyDepths: List<int>
    LoopHoistedDepths: List<int>
    LoopLowerable: List<bool>
    LoopContinueUsed: List<bool>

    constructor(plan: ColumnarCodePlan, context: ColumnarIteratorEmitContext, thisArg: int, stateFieldPool: int, resumeLabels: int[], endLabel: int, regionMode: bool, resultLocal: int, regionEndLabel: int, isAsync: bool = false, faultGuarded: bool = false, regionEntryLabels: int[]? = null) {
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
        NextAsyncEnumerator = 0
        NextLambda = 0
        FaultGuarded = faultGuarded
        RegionDepth = 0
        RegionEntryLabels = regionEntryLabels ?? new int[](0)
        HoistedRegionEnds = new int[](RegionEntryLabels.Length)
        HoistedBranchFields = new string[](RegionEntryLabels.Length)
        HoistedDepth = 0
        HoistedHandlerDepth = 0
        NextTryRegion = 0
        NextUsingResource = 0
        CatchHandlerDepth = 0
        FinallyHandlerDepth = 0
        LoopBreakLabels = new List<int>()
        LoopContinueLabels = new List<int>()
        LoopRegionDepths = new List<int>()
        LoopFinallyDepths = new List<int>()
        LoopHoistedDepths = new List<int>()
        LoopLowerable = new List<bool>()
        LoopContinueUsed = new List<bool>()
    }

    // True where the plan is standing inside a protected region, which is exactly where a branch out
    // must be a `leave` and a `ret` is illegal.
    InsideRegion: bool => FaultGuarded || RegionDepth > 0

    LoopDepth: int => LoopBreakLabels.Count

    // OPEN A LOOP FRAME. `continueLabel` is where the step and the back edge stand; for a `while` it
    // is the condition itself, because there is no step to run first.
    func PushLoop(continueLabel: int, breakLabel: int, lowerable: bool) {
        LoopBreakLabels.Add(breakLabel)
        LoopContinueLabels.Add(continueLabel)
        LoopRegionDepths.Add(RegionDepth)
        LoopFinallyDepths.Add(FinallyHandlerDepth)
        LoopHoistedDepths.Add(HoistedDepth)
        LoopLowerable.Add(lowerable)
        LoopContinueUsed.Add(false)
    }

    // Whether any `continue` in the body that just closed branched to this frame — the step and back
    // edge are emitted for a body that cannot fall through only when one did.
    func PopLoop(): bool {
        last := LoopBreakLabels.Count - 1
        used := LoopContinueUsed[last]
        LoopBreakLabels.RemoveAt(last)
        LoopContinueLabels.RemoveAt(last)
        LoopRegionDepths.RemoveAt(last)
        LoopFinallyDepths.RemoveAt(last)
        LoopHoistedDepths.RemoveAt(last)
        LoopLowerable.RemoveAt(last)
        LoopContinueUsed.RemoveAt(last)
        return used
    }
}

class ColumnarIteratorBodyPlanner {

    // MoveNext(): the resumable state machine. A dispatch prologue routes each resume state to its
    // label; state 0 falls through to the body start (state set running = -1); every `yield return`
    // stores current, sets its resume state, returns true, then resumes by resetting to running;
    // `yield break` and the natural body end reach the shared end label that returns false.
    //
    // THREE EXIT SHAPES, ONE WALK. A body with no protected region at all returns directly. A body
    // with hoisted enumerators takes the GUARDED layout — the whole dispatch and body inside a
    // try/FAULT region that disposes live enumerators — and a body that writes its own `try`
    // statements takes the same result-local discipline without the outer wrapper. Both of the
    // latter two stash the result and branch past every region rather than returning inside one,
    // because ECMA forbids `ret` in a protected region and `leave` is its only legal exit.
    static func BuildMoveNextPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        faultGuarded := HoistedEnumeratorFieldCount(context) > 0
        regionCount := context.Shape.TryRegionCount
        exitViaResult := faultGuarded || regionCount > 0

        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.StateMachineType), context.StructuralTypeReferences)
        thisArg := plan.AddArgument(0, smTypeIdx)
        stateFieldPool := plan.AddField(context.FieldForName("<>__state"))
        resultLocal := 0
        if exitViaResult {
            boolTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(typeof(bool)), context.StructuralTypeReferences)
            resultLocal = plan.DeclarePlanLocal(boolTypeIdx)
        }

        yieldCount := context.Shape.YieldReturnCount
        resumeLabels := new int[](yieldCount + 1)
        s := 1
        while s <= yieldCount {
            resumeLabels[s] = plan.DefineLabel()
            s = s + 1
        }
        endLabel := plan.DefineLabel()
        regionEnd := 0
        if exitViaResult {
            regionEnd = plan.DefineLabel()
        }
        regionEntryLabels := new int[](regionCount)
        k := 0
        while k < regionCount {
            regionEntryLabels[k] = plan.DefineLabel()
            k = k + 1
        }
        emit := new ColumnarMoveNextEmit(plan, context, thisArg, stateFieldPool, resumeLabels, endLabel, exitViaResult, resultLocal, regionEnd, false, faultGuarded, regionEntryLabels)

        if faultGuarded {
            plan.AppendBeginExceptionBlock(regionEnd)
        }
        AppendMoveNextDispatch(emit, yieldCount)

        EmitStatement(emit, context.BodyRoot)
        if context.Declined {
            // A declined body leaves the plan half-built on purpose: the caller reports the decline and
            // never executes it, and completing a plan whose labels and regions were abandoned mid-walk
            // would report the ABANDONMENT rather than the shape that could not be lowered.
            return plan
        }

        plan.AppendMarkLabel(endLabel)
        EmitInt(emit, 0)
        if !exitViaResult {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
            plan.CompleteMethodBody(typeof(bool))
            return plan
        }

        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), resultLocal)
        if faultGuarded {
            plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), regionEnd)
            plan.AppendBeginFaultBlock()
            AppendEnumeratorDisposals(plan, context, thisArg)
            plan.AppendEndExceptionBlock()
        } else {
            plan.AppendMarkLabel(regionEnd)
        }

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
    static func BuildAsyncMoveNextCorePlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.StateMachineType), context.StructuralTypeReferences)
        thisArg := plan.AddArgument(0, smTypeIdx)
        stateFieldPool := plan.AddField(context.FieldForName("<>__state"))
        exTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(ExceptionRuntimeType()), context.StructuralTypeReferences)
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
        regionCount := context.Shape.TryRegionCount
        regionEntryLabels := new int[](regionCount)
        k := 0
        while k < regionCount {
            regionEntryLabels[k] = plan.DefineLabel()
            k = k + 1
        }
        emit := new ColumnarMoveNextEmit(plan, context, thisArg, stateFieldPool, resumeLabels, endLabel, true, 0, regionEnd, true, true, regionEntryLabels)

        plan.AppendBeginExceptionBlock(regionEnd)
        AppendMoveNextDispatch(emit, resumeCount)

        EmitStatement(emit, context.BodyRoot)
        if context.Declined {
            // A declined body leaves the plan half-built on purpose: the caller reports the decline and
            // never executes it, and completing a plan whose labels and regions were abandoned mid-walk
            // would report the ABANDONMENT rather than the shape that could not be lowered.
            return plan
        }

        plan.AppendMarkLabel(endLabel)
        StoreState(emit, ColumnarIteratorPlanner.DoneState())
        // THE NORMAL END RELEASES WHAT THE BODY WAS ENUMERATING, and it is the same rows the
        // exceptional path below runs. `DisposeAsync` on an abandoned machine drives this core with
        // the dispose flag set, so the unwind reaches the end label too — which is exactly why the
        // disposal cannot live only in `DisposeAsync`: that method returns before an unwind that
        // suspended inside a handler has finished.
        AppendEnumeratorDisposals(plan, context, thisArg)
        EmitAsyncComplete(emit, 0)

        plan.AppendBeginCatchBlock(exTypeIdx)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), exLocal)
        StoreState(emit, ColumnarIteratorPlanner.DoneState())
        // The exceptional path releases whatever the body was enumerating. A synchronous machine
        // does this from a FAULT handler; the async core already has to catch — an exception has to
        // reach the pending call's promise rather than this frame's caller — so the disposal rides
        // the handler it already has.
        AppendEnumeratorDisposals(plan, context, thisArg)
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
    static func BuildMoveNextAsyncPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.StateMachineType), context.StructuralTypeReferences)
        thisArg := plan.AddArgument(0, smTypeIdx)
        statePool := plan.AddField(context.FieldForName("<>__state"))
        promPool := plan.AddField(context.FieldForName("<>__promise"))
        resPool := plan.AddField(context.FieldForName("<>__result"))
        boolCtorPool := plan.AddConstructor(ValueTaskOfBoolConstructor())
        taskCtorPool := plan.AddConstructor(ValueTaskOfTaskConstructor())
        noParams := new Type[](0)
        corePool := plan.AddMethodWithSignature(context.RequiredCoreMethod(), context.StateMachineType, noParams, VoidReturnType(), false, false)
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

    // DisposeAsync(): release whatever the body was still enumerating, mark the machine done, and
    // complete synchronously (default ValueTask). A consumer that stops an `await foreach` part-way
    // calls this while the machine is suspended inside a loop, which is exactly when a hoisted
    // enumerator is live.
    static func BuildDisposeAsyncPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.StateMachineType), context.StructuralTypeReferences)
        thisArg := plan.AddArgument(0, smTypeIdx)
        statePool := plan.AddField(context.FieldForName("<>__state"))
        AppendAsyncDisposeUnwind(plan, context, thisArg, statePool)
        AppendEnumeratorDisposals(plan, context, thisArg)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(ColumnarIteratorPlanner.DoneState()))
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), statePool)
        vtType := ValueTaskRuntimeType()
        vtTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(vtType), context.StructuralTypeReferences)
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
    static func BuildGetAsyncEnumeratorPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        AppendEnumeratorClone(plan, context)
        plan.CompleteMethodBody(AsyncEnumeratorInterfaceTypeOf(context.ElementType))
        return plan
    }

    // The state dispatch: each resume state branches to its label; any other non-zero state (running or
    // done) reaches the end label; state 0 falls through into a fresh run.
    //
    // A resume point that lives inside a `try` cannot be branched to from here — a branch INTO a
    // protected region is illegal IL — so its state branches to the ENTRY of the outermost `try` that
    // contains it. Control then enters that region normally and the region's own dispatch (emitted as
    // its first rows) repeats the question one level down, until the resume label itself is reachable
    // from inside every region it stands in.
    static func AppendMoveNextDispatch(emit: ColumnarMoveNextEmit, yieldCount: int) {
        AppendStateDispatch(emit, yieldCount, 0 - 1)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), emit.StateFieldPool)
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), emit.EndLabel)
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
    }

    // One dispatch level. `region` is the region the rows are being emitted inside (-1 for the method
    // prologue); every resume state whose home is that region — or any region nested inside it —
    // branches to the next hop on the way there.
    static func AppendStateDispatch(emit: ColumnarMoveNextEmit, yieldCount: int, region: int) {
        s := 1
        while s <= yieldCount {
            target := DispatchTargetFor(emit, s, region)
            if target >= 0 {
                LoadThis(emit)
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), emit.StateFieldPool)
                EmitInt(emit, s)
                emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
                emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), target)
            }
            s = s + 1
        }
    }

    // The label a dispatch emitted inside `region` must branch to so that resume state `s` is
    // reached: its own resume label when the state's home IS this region, the entry of the child
    // region on the path when it is nested deeper, and -1 when the state does not live under this
    // region at all (an enclosing dispatch already routed it, or will).
    static func DispatchTargetFor(emit: ColumnarMoveNextEmit, s: int, region: int): int {
        home := emit.Context.Shape.ResumeRegionOf(s)
        if home == region {
            return emit.ResumeLabels[s]
        }
        parents := emit.Context.Shape.TryRegionParents
        hop := home
        while hop >= 0 && hop < parents.Length {
            if parents[hop] == region {
                return emit.RegionEntryLabels[hop]
            }
            hop = parents[hop]
        }
        return 0 - 1
    }

    // EVERY SUSPENSION STATE OF THIS MACHINE. A synchronous generator suspends only at a `yield
    // return`; an async one also suspends at every `await`, and both kinds share one resume-state
    // numbering. A dispatch that asked only about the yields would never route a resume that
    // suspended at an await inside a protected region.
    static func TotalResumeCount(context: ColumnarIteratorEmitContext): int {
        return context.Shape.YieldReturnCount + context.Shape.AwaitResumeCount
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

    // THE ABANDONED-MACHINE UNWIND. A consumer that stops early calls `Dispose` while the machine is
    // suspended, and every `finally` it is standing inside still has to run. The machine already
    // knows how to get back to that exact point — its own state dispatch — so `Dispose` sets the
    // dispose flag and drives `MoveNext` once: the resume point marks the machine running, sees the
    // flag, and branches to the end label, which leaves every open region and lets the runtime run
    // each `finally` on the way out, innermost first. Only the states that suspended INSIDE a region
    // are driven; everything else has nothing to unwind.
    static func AppendDisposeModeUnwind(plan: ColumnarCodePlan, context: ColumnarIteratorEmitContext, thisArg: int, statePool: int) {
        moveNext := context.MoveNextMethod
        if moveNext == null || !context.HasHoistedField(ColumnarIteratorPlanner.DisposeModeFieldName()) {
            return
        }
        shape := context.Shape
        unwindLabel := plan.DefineLabel()
        skipLabel := plan.DefineLabel()
        driven := false
        s := 1
        while s <= TotalResumeCount(context) {
            if shape.ResumeRegionOf(s) >= 0 {
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), statePool)
                plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(s))
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
                plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), unwindLabel)
                driven = true
            }
            s = s + 1
        }
        if !driven {
            throw new InvalidOperationException("A machine with a dispose flag must suspend inside at least one protected region.")
        }
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), skipLabel)
        plan.AppendMarkLabel(unwindLabel)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(1))
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), plan.AddField(context.FieldForName(ColumnarIteratorPlanner.DisposeModeFieldName())))
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(moveNext))
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
        plan.AppendMarkLabel(skipLabel)
    }

    // THE ABANDONED ASYNC MACHINE. The synchronous twin above drives `MoveNext` once and throws the
    // answer away; an async machine cannot, because a handler it is standing in may itself suspend —
    // `await using`'s release and `await foreach`'s `DisposeAsync()` are both awaits in a handler
    // position. So `DisposeAsync` drives the step core with the dispose flag set and then ASKS THE
    // PROMISE: a synchronous unwind left none (the core already reached the end label, marked the
    // machine done and released its enumerators), while a suspended one left a live promise whose
    // task completes when the continuation re-drives the core through the rest of the unwind. That
    // task IS this call's ValueTask.
    //
    // Only a state that suspended INSIDE a region is driven. Everything else has nothing to unwind,
    // and the ordinary rows after this one release the enumerators and mark the machine done.
    static func AppendAsyncDisposeUnwind(plan: ColumnarCodePlan, context: ColumnarIteratorEmitContext, thisArg: int, statePool: int) {
        if !context.HasHoistedField(ColumnarIteratorPlanner.DisposeModeFieldName()) {
            return
        }
        shape := context.Shape
        unwindLabel := plan.DefineLabel()
        skipLabel := plan.DefineLabel()
        driven := false
        s := 1
        while s <= TotalResumeCount(context) {
            if shape.ResumeRegionOf(s) >= 0 {
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), statePool)
                plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(s))
                plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ceq())
                plan.AppendLabelInstruction(ColumnarCodePlanContract.Brtrue(), unwindLabel)
                driven = true
            }
            s = s + 1
        }
        if !driven {
            throw new InvalidOperationException("A machine with a dispose flag must suspend inside at least one protected region.")
        }
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), skipLabel)
        plan.AppendMarkLabel(unwindLabel)
        promPool := plan.AddField(context.FieldForName("<>__promise"))
        noParams := new Type[](0)
        corePool := plan.AddMethodWithSignature(context.RequiredCoreMethod(), context.StateMachineType, noParams, VoidReturnType(), false, false)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.LdcI4_1())
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), plan.AddField(context.FieldForName(ColumnarIteratorPlanner.DisposeModeFieldName())))
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), promPool)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), corePool)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipLabel)
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), promPool)
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), plan.AddMethod(PromiseTaskGetter()))
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructor(ValueTaskFromTaskConstructor()))
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.AppendMarkLabel(skipLabel)
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
    static func BuildGetCurrentPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.StateMachineType), context.StructuralTypeReferences)
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
    static func BuildInterfaceGetCurrentPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.StateMachineType), context.StructuralTypeReferences)
        thisArg := plan.AddArgument(0, smTypeIdx)
        currentPool := plan.AddField(context.FieldForName("<>__current"))
        plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), currentPool)
        if context.ElementType.get_IsValueType() || context.ElementType.get_IsGenericParameter() {
            // A value element boxes to object; an unconstrained type parameter boxes unconditionally
            // (`box !T` is a no-op for reference instantiations).
            boxTypePool := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.ElementType), context.StructuralTypeReferences)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Box(), boxTypePool)
        }
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(typeof(object))
        return plan
    }

    // System.IDisposable.Dispose(): dispose any live hoisted enumerator (the machine may be suspended
    // inside a guarded loop — this is the finally-equivalent path for consumer abandonment), then mark
    // the machine done.
    static func BuildDisposePlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        smTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.StateMachineType), context.StructuralTypeReferences)
        thisArg := plan.AddArgument(0, smTypeIdx)
        statePool := plan.AddField(context.FieldForName("<>__state"))
        donePool := plan.AddInt32(ColumnarIteratorPlanner.DoneState())
        AppendDisposeModeUnwind(plan, context, thisArg, statePool)
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
    static func BuildResetPlan(): ColumnarCodePlan {
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
    static func BuildGetEnumeratorPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        AppendEnumeratorClone(plan, context)
        plan.CompleteMethodBody(EnumeratorInterfaceTypeOf(context.ElementType))
        return plan
    }

    // System.Collections.IEnumerable.GetEnumerator(): the identical clone body; only the declared result
    // view differs (the non-generic IEnumerator).
    static func BuildInterfaceGetEnumeratorPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        AppendEnumeratorClone(plan, context)
        plan.CompleteMethodBody(NonGenericEnumeratorType())
        return plan
    }

    // The FACTORY body for the original func* function: construct the machine at the initial state and
    // store each argument into its captured-parameter field (signature order = captured field order).
    static func BuildFactoryPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        AppendFactoryBody(plan, context)
        plan.CompleteMethodBody(EnumerableInterfaceTypeOf(context.ElementType))
        return plan
    }

    // The async factory: the identical construct-and-capture body; only the declared result view
    // differs (the IAsyncEnumerable<T> surface the `async func*` method returns).
    static func BuildAsyncFactoryPlan(context: ColumnarIteratorEmitContext): ColumnarCodePlan {
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
                fieldType := context.Fields[i].get_FieldType()
                argTypePool := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(fieldType), context.StructuralTypeReferences)
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
            smTypeIdx := plan.AddType(context.StructuralTypeReferences.SelectRuntimeType(context.StateMachineType), context.StructuralTypeReferences)
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

    static func StrongBoxValueField(boxType: Type): FieldInfo {
        definition := typeof(System.Runtime.CompilerServices.StrongBox<int>).GetGenericTypeDefinition()
        openField := definition.GetField("Value")
        if ColumnarTypeOfPlanner.ContainsBuilderBoundType(boxType) {
            return TypeBuilder.GetField(boxType, openField)
        }
        return boxType.GetField("Value")
    }

    static func StrongBoxConstructor(boxType: Type, takesValue: bool): ConstructorInfo {
        definition := typeof(System.Runtime.CompilerServices.StrongBox<int>).GetGenericTypeDefinition()
        let openConstructor: ConstructorInfo = null
        if takesValue {
            definitionParameter := definition.GetGenericArguments()[0]
            parameters := new Type[](1)
            parameters[0] = definitionParameter
            openConstructor = definition.GetConstructor(parameters)
        } else {
            openConstructor = definition.GetConstructor(System.Type.EmptyTypes)
        }
        if ColumnarTypeOfPlanner.ContainsBuilderBoundType(boxType) {
            return TypeBuilder.GetConstructor(boxType, openConstructor)
        }
        parameters := takesValue ? new Type[](1) : System.Type.EmptyTypes
        if takesValue {
            parameters[0] = boxType.GetGenericArguments()[0]
        }
        return boxType.GetConstructor(parameters)
    }

    static func AppendFreshLoopCaptureBox(emit: ColumnarMoveNextEmit, name: string, valueNode: int, valueType: Type, hasValue: bool): bool {
        boxField: FieldInfo? = null
        if !emit.Context.TryEnsureLoopCaptureBox(name, valueType, out boxField) || boxField == null {
            emit.Context.Decline("emit.iterator.lambda-unsupported", "the per-iteration storage for '" + name + "' could not be defined")
            return false
        }
        LoadThis(emit)
        if hasValue && !AppendStoredValue(emit, valueNode, valueType) {
            return false
        }
        constructor := StrongBoxConstructor(boxField.get_FieldType(), hasValue)
        constructorParameters := System.Type.EmptyTypes
        if hasValue {
            constructorParameters = new Type[](1)
            constructorParameters[0] = valueType
        }
        emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), emit.Plan.AddConstructorWithSignature(constructor, boxField.get_FieldType(), constructorParameters))
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), emit.Plan.AddField(boxField))
        return true
    }

    static func AppendFreshLoopCaptureBoxFromStack(emit: ColumnarMoveNextEmit, name: string, valueType: Type): bool {
        boxField: FieldInfo? = null
        if !emit.Context.TryEnsureLoopCaptureBox(name, valueType, out boxField) || boxField == null {
            emit.Context.Decline("emit.iterator.lambda-unsupported", "the per-iteration storage for '" + name + "' could not be defined")
            return false
        }
        constructor := StrongBoxConstructor(boxField.get_FieldType(), true)
        parameterTypes := new Type[](1)
        parameterTypes[0] = valueType
        emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), emit.Plan.AddConstructorWithSignature(constructor, boxField.get_FieldType(), parameterTypes))
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), emit.Plan.AddField(boxField))
        return true
    }

    // A branch to a label at the BODY's own level (the shared end label). It crosses out of every
    // `try` the body wrote, so it is a `leave` exactly when one of those is open; the outer fault
    // wrapper, when there is one, encloses the end label too and is not crossed.
    static func AppendBodyExit(emit: ColumnarMoveNextEmit, label: int) {
        // A BRANCH TO THE BODY'S END CANNOT SKIP A HOISTED HANDLER. Inside a region whose handler was
        // hoisted out, the end label is no longer reachable in one hop: the exit records itself in the
        // region's branch field and leaves to that region's end, where the handler runs and the rows
        // after it re-issue the branch — in the ENCLOSING context, so a nested hoisted region repeats
        // the same hop one level out. Every other target (a plain region's own end) is unaffected.
        if label == emit.EndLabel && emit.HoistedDepth > 0 {
            depth := emit.HoistedDepth - 1
            LoadThis(emit)
            EmitInt(emit, 1)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, emit.HoistedBranchFields[depth]))
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), emit.HoistedRegionEnds[depth])
            return
        }

        emit.Plan.AppendLabelInstruction((short)(emit.RegionDepth > 0 ? ColumnarCodePlanContract.Leave() : ColumnarCodePlanContract.Br()), label)
    }

    // A branch to the label past EVERY region — where the method's single `ret` stands. It crosses
    // the outer fault wrapper as well, so any open region at all makes it a `leave`.
    static func AppendMethodExit(emit: ColumnarMoveNextEmit, label: int) {
        emit.Plan.AppendLabelInstruction((short)(emit.InsideRegion ? ColumnarCodePlanContract.Leave() : ColumnarCodePlanContract.Br()), label)
    }

    // THE ONE EXPRESSION DOOR. A value inside a `func*` body is planned by the SAME owner that plans a
    // value inside an ordinary function body — `ColumnarMethodBodyPlanner.TryAppendValue` — against
    // bindings in which this body's names resolve to the machine's fields. Nothing about a call, a
    // `new`, an array literal, an indexer or a binary is decided here.
    //
    // A decline rolls the plan back to the checkpoint so the rows this owner has already appended stay
    // well-formed, and records the failing node so the CLI can name the construct rather than the
    // sub-slice.
    static func AppendValue(emit: ColumnarMoveNextEmit, node: int, out resultType: Type): bool {
        resultType = typeof(int)
        if emit.Context.Declined {
            return false
        }
        // A POSTFIX STEP IS A WRITE, and a write to a hoisted binding is the state machine's own
        // rewrite rather than an expression the value owner can plan: `i++` reads a field, steps it and
        // stores it back. Its VALUE is the pre-step field value, which is what `yield i++` produces.
        if emit.Context.Nodes.Kind(node) == 44 {
            name := emit.Context.Nodes.Text(emit.Context.Source, emit.Context.Nodes.Child(node, 0))
            if !emit.Context.HasHoistedField(name) {
                emit.Context.Decline("emit.iterator.unsupported-shape", "a postfix step of '" + name + "' is not a hoisted binding in an iterator body")
                return false
            }
            resultType = emit.Context.FieldForName(name).get_FieldType()
            EmitPostfixStep(emit, node, true)
            return !emit.Context.Declined
        }
        // AN `on` SUBSCRIPTION IS THE GENERATOR'S OWN SHAPE, for the same reason a lambda is: the rows
        // it needs — a delegate built over a method the machine itself carries, and a `ldvirtftn` over
        // the receiver — are plan rows this owner appends, and the ONE expression door declines node
        // kind 79 wherever it is asked.
        if emit.Context.Nodes.Kind(node) == 79 {
            return AppendOnSubscription(emit, node, out resultType)
        }
        checkpoint := emit.Plan.CreateCheckpoint()
        if emit.Context.RequiredScope().TryAppendValue(emit.Context.Nodes, emit.Context.Source, node, emit.Plan, out resultType) {
            return true
        }
        emit.Plan.Rollback(checkpoint)
        emit.Context.Decline("emit.iterator.unsupported-shape", "an iterator body expression (node kind " + emit.Context.Nodes.Kind(node).ToString() + ") could not be lowered")
        return false
    }

    // A value that must arrive at a storage location of `storageType` — a hoisted field, the current
    // field a `yield` writes. The conversion is the call-argument conversion owner's, so boxing, a
    // reference upcast, a nullable lift, a constructed-generic conversion and a user-defined implicit
    // conversion all behave exactly as they do when the same value is passed to a parameter.
    static func AppendStoredValue(emit: ColumnarMoveNextEmit, node: int, storageType: Type): bool {
        if emit.Context.Declined {
            return false
        }
        if ColumnarLambdaNodeFacts.IsLambda(emit.Context.Nodes.Kind(node)) {
            return AppendLambda(emit, node, storageType)
        }
        // The iterator-owned value forms take the ordinary value path plus the storage conversion; only
        // target-typed forms need the position's type handed down.
        if emit.Context.Nodes.Kind(node) == 79 {
            subscriptionType := typeof(int)
            if !AppendValue(emit, node, out subscriptionType) {
                return false
            }
            if subscriptionType == storageType || storageType.IsAssignableFrom(subscriptionType) {
                return true
            }
            if !emit.Context.RequiredScope().TryAppendStorageConversion(emit.Plan, subscriptionType, storageType) {
                emit.Context.Decline("emit.iterator.unsupported-shape", "an iterator body value of type '" + subscriptionType.Name + "' cannot be stored as '" + storageType.Name + "'")
                return false
            }
            return true
        }
        if emit.Context.Nodes.Kind(node) == 44 {
            steppedType := typeof(int)
            if !AppendValue(emit, node, out steppedType) {
                return false
            }
            if steppedType == storageType {
                return true
            }
            if !emit.Context.RequiredScope().TryAppendStorageConversion(emit.Plan, steppedType, storageType) {
                emit.Context.Decline("emit.iterator.unsupported-shape", "an iterator body value of type '" + steppedType.Name + "' cannot be stored as '" + storageType.Name + "'")
                return false
            }
            return true
        }
        checkpoint := emit.Plan.CreateCheckpoint()
        if emit.Context.RequiredScope().TryAppendTargetTypedValue(emit.Context.Nodes, emit.Context.Source, node, emit.Plan, storageType) {
            return true
        }
        emit.Plan.Rollback(checkpoint)
        emit.Context.Decline("emit.iterator.unsupported-shape", "an iterator body value (node kind " + emit.Context.Nodes.Kind(node).ToString() + ") could not be lowered as '" + storageType.Name + "'")
        return false
    }

    // A VALUE STORED INTO ONE OF THE MACHINE'S FIELDS, which is the only place an `await` can be the
    // whole value. A suspension point branches out of the method, and ECMA requires an EMPTY
    // evaluation stack at a `leave` — so an awaited value cannot be produced with the receiver of its
    // own store already pushed. The await therefore runs FIRST, parks its result in a plan local, and
    // only then is `this` loaded and the field written. Every other value keeps the ordinary order:
    // receiver, value, store.
    static func AppendBoundFieldStore(emit: ColumnarMoveNextEmit, valueNode: int, fieldPool: int, storageType: Type): bool {
        if emit.Context.Nodes.Kind(valueNode) != 53 {
            LoadThis(emit)
            if !AppendStoredValue(emit, valueNode, storageType) {
                return false
            }
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldPool)
            return true
        }

        awaitedType := VoidReturnType()
        if !AppendAwait(emit, valueNode, out awaitedType) {
            return false
        }
        if ColumnarCodePlanExecutor.IsVoidType(awaitedType) {
            emit.Context.Decline("emit.iterator.async-await-unsupported", "this `await` produces no value to bind")
            return false
        }
        spill := emit.Plan.DeclarePlanLocal(emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(awaitedType), emit.Context.StructuralTypeReferences))
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), spill)
        LoadThis(emit)
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), spill)
        if awaitedType != storageType && !emit.Context.RequiredScope().TryAppendStorageConversion(emit.Plan, awaitedType, storageType) {
            emit.Context.Decline("emit.iterator.async-await-unsupported", "an awaited '" + awaitedType.Name + "' cannot be stored as '" + storageType.Name + "'")
            return false
        }
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldPool)
        return true
    }

    // The type a bound value produces, without appending anything that runs. An `await`'s type is what
    // its awaiter's `GetResult()` returns, which is one ordinary member lookup away from the operand's
    // own planned type.
    static func TryDiscoverBoundValueType(emit: ColumnarMoveNextEmit, node: int, out resultType: Type): bool {
        resultType = typeof(int)
        nodes := emit.Context.Nodes
        // AN `on` SUBSCRIPTION'S TYPE IS KNOWN WITHOUT PLANNING IT, and it MUST be answered that way:
        // this discovery runs the value into a plan nobody executes, and planning an `on` whose handler
        // is a lambda would define that lambda's method on the machine a second time.
        if nodes.Kind(node) == 79 {
            resultType = typeof(NSharpLang.Runtime.NSharpEventSubscription)
            return true
        }
        if nodes.Kind(node) != 53 {
            return emit.Context.RequiredScope().TryDiscoverValueType(nodes, emit.Context.Source, node, out resultType)
        }
        if nodes.ChildCount(node) != 1 {
            return false
        }
        operandType := typeof(int)
        if !emit.Context.RequiredScope().TryDiscoverValueType(nodes, emit.Context.Source, nodes.Child(node, 0), out operandType) {
            return false
        }
        getAwaiter := ParameterlessMethodOrNull(operandType, "GetAwaiter")
        if getAwaiter == null {
            return false
        }
        getResult := ParameterlessMethodOrNull(getAwaiter.get_ReturnType(), "GetResult")
        if getResult == null {
            return false
        }
        resultType = getResult.get_ReturnType()
        return !ColumnarCodePlanExecutor.IsVoidType(resultType)
    }

    // ── `on` / `off` INSIDE A GENERATOR BODY ──────────────────────────────────────────────────
    //
    // A subscription made before a `yield` and detached after it is the whole reason this belongs in a
    // generator: the handle is an ordinary local, so the machine hoists it into a field like every
    // other local, and the two halves of the feature span a suspension without knowing they did.
    //
    // THE LOWERING IS THE ORDINARY EMITTER'S, WRITTEN AS PLAN ROWS. `on` evaluates to a
    // `NSharpEventSubscription<THandler>`: attach the handler through the event's own `add_`, keep the
    // `remove_` accessor bound to this receiver as an `Action<THandler>`, and hand both to the handle.
    // A VIRTUAL remove accessor is taken with `ldvirtftn` over the receiver, so an override wins
    // exactly as it would at a call site — which is why the plan needed that row at all.
    //
    // Nothing here is an event-name table or a modelled-API list: the owner comes from ordinary scoped
    // resolution (a type name for a static event, the planned receiver's own type otherwise) and every
    // fact about the event is read off the `EventInfo` reflection already answers, or off the source
    // definition for a type this compilation is still building.
    static func AppendOnSubscription(emit: ColumnarMoveNextEmit, node: int, out resultType: Type): bool {
        resultType = typeof(int)
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        if nodes.ChildCount(node) != 2 {
            emit.Context.Decline("emit.iterator.on-shape", "`on` subscription is missing its event target or handler")
            return false
        }
        targetNode := nodes.Child(node, 0)
        handlerNode := nodes.Child(node, 1)
        eventName := ColumnarNodeTextFacts.Text(nodes, source, targetNode)
        if eventName.Length == 0 {
            emit.Context.Decline("emit.iterator.on-shape", "`on` subscription target names no event")
            return false
        }
        if nodes.Kind(targetNode) != 8 || nodes.ChildCount(targetNode) != 1 {
            // `on base.<Event>` inside a generator reaches its enclosing instance through `<>__this`,
            // but the machine carries no handle for that instance's BASE type, so the accessors cannot
            // be found. Said by shape rather than lowered to the wrong pair.
            emit.Context.Decline("emit.iterator.on-target-shape", "an `on` subscription inside a generator body must name `<receiver>.<Event>`")
            return false
        }

        receiverNode := nodes.Child(targetNode, 0)
        let ownerType: System.Type? = null
        receiverLocal := 0 - 1
        let staticOwner: System.Type? = null
        if TryResolveIteratorEventOwnerTypeName(emit, receiverNode, out staticOwner) && IteratorEventOnChain(emit, staticOwner, eventName, true) {
            ownerType = staticOwner
        } else {
            receiverType := typeof(int)
            if !AppendValue(emit, receiverNode, out receiverType) {
                return false
            }
            if receiverType.get_IsValueType() {
                emit.Context.Decline("emit.iterator.on-value-type-receiver", "an instance event cannot be bound through a value-type receiver")
                return false
            }
            receiverLocal = emit.Plan.DeclarePlanLocal(emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(receiverType), emit.Context.StructuralTypeReferences))
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), receiverLocal)
            ownerType = receiverType
        }

        let handlerType: System.Type? = null
        let addMethod: System.Reflection.MethodInfo? = null
        let removeMethod: System.Reflection.MethodInfo? = null
        if !TryResolveIteratorEventAccessors(emit, ownerType, eventName, receiverLocal < 0, out handlerType, out addMethod, out removeMethod) {
            emit.Context.Decline("emit.iterator.on-event-lookup", "no accessible event '" + eventName + "' on '" + ownerType.Name + "'")
            return false
        }
        if addMethod.get_IsStatic() != (receiverLocal < 0) {
            emit.Context.Decline("emit.iterator.on-receiver-kind", "event '" + eventName + "' does not match the receiver it was given")
            return false
        }

        if ColumnarLambdaNodeFacts.IsLambda(nodes.Kind(handlerNode)) {
            if !AppendLambda(emit, handlerNode, handlerType) {
                return false
            }
        } else if !AppendSiblingMethodGroupHandler(emit, handlerNode, handlerType) && !AppendStoredValue(emit, handlerNode, handlerType) {
            return false
        }

        handlerTypeIndex := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(handlerType), emit.Context.StructuralTypeReferences)
        handlerLocal := emit.Plan.DeclarePlanLocal(handlerTypeIndex)
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), handlerLocal)

        if receiverLocal >= 0 {
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), receiverLocal)
        }
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), handlerLocal)
        addOpCode := ColumnarCodePlanContract.Callvirt()
        if addMethod.get_IsStatic() {
            addOpCode = ColumnarCodePlanContract.Call()
        }
        emit.Plan.AppendMethodInstruction(addOpCode, emit.Plan.AddMethod(addMethod))

        // THE REMOVE ACCESSOR, BOUND TO THIS RECEIVER, as the `Action<THandler>` the handle keeps. The
        // `dup` before `ldvirtftn` is load-bearing: the opcode POPS the receiver it reads the v-table
        // from, and the delegate constructor still needs that same receiver as its first argument.
        actionType := typeof(Action<int>).GetGenericTypeDefinition().MakeGenericType([handlerType])
        actionCtor := actionType.GetConstructor([typeof(object), typeof(IntPtr)])
        if actionCtor == null {
            emit.Context.Decline("emit.iterator.on-remove-delegate", "Action<T> has no (object, IntPtr) constructor")
            return false
        }
        if receiverLocal < 0 {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
            emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Ldftn(), emit.Plan.AddMethod(removeMethod))
        } else {
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), receiverLocal)
            if removeMethod.get_IsVirtual() && !removeMethod.get_IsFinal() {
                emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Dup())
                emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Ldvirtftn(), emit.Plan.AddMethod(removeMethod))
            } else {
                emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Ldftn(), emit.Plan.AddMethod(removeMethod))
            }
        }
        emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), emit.Plan.AddConstructor(actionCtor))
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), handlerLocal)

        let openSubscription: System.Type? = null
        if !ColumnarTypeOfPlanner.TryResolveRuntimeGenericDefinition("NSharpLang.Runtime.NSharpEventSubscription`1", "NSharpLang.Runtime", out openSubscription) {
            emit.Context.Decline("emit.iterator.on-runtime-handle", "the N# runtime's event-subscription handle type could not be resolved")
            return false
        }
        subscriptionType := openSubscription.MakeGenericType([handlerType])
        subscriptionCtor := subscriptionType.GetConstructor([actionType, handlerType])
        if subscriptionCtor == null {
            emit.Context.Decline("emit.iterator.on-runtime-handle", "the N# runtime's event-subscription handle has no (Action<T>, T) constructor")
            return false
        }
        emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), emit.Plan.AddConstructor(subscriptionCtor))
        // THE STATIC TYPE IS THE NON-GENERIC ROOT, the same identity the ordinary emitter and the
        // analyzer both give the expression, so `off` measures against one thing everywhere.
        resultType = typeof(NSharpLang.Runtime.NSharpEventSubscription)
        return true
    }

    // A FREE FUNCTION NAMED AS THE HANDLER. `on list.CollectionChanged TallyHandler` converts a method
    // group to the event's delegate exactly as an inline lambda does, and inside a generator the group
    // is a SIBLING — a top-level `func`, which emits as a static method — so the delegate is built the
    // way a static one is: `ldnull; ldftn <m>; newobj <Delegate>..ctor`.
    //
    // The group is admitted only when its signature IS the delegate's `Invoke`, by exact parameter and
    // return identity. A near miss falls through to the ordinary value door, which reports the
    // mismatch against the target type rather than silently binding the wrong method.
    static func AppendSiblingMethodGroupHandler(emit: ColumnarMoveNextEmit, handlerNode: int, handlerType: Type): bool {
        nodes := emit.Context.Nodes
        if nodes.Kind(handlerNode) != 6 {
            return false
        }
        // A BINDING OF THAT SPELLING SHADOWS THE FREE FUNCTION, exactly as a local shadows one in an
        // ordinary body: a hoisted field of the machine (every parameter and local of the generator is
        // one), an enclosing member reached through the captured receiver, or a root binding the node
        // table records. Any of them and the ordinary value door answers instead.
        name := nodes.Text(emit.Context.Source, handlerNode)
        if name.Length == 0 || emit.Context.HasHoistedField(name) || emit.Context.EnclosingFieldIndex(name) >= 0 || nodes.HasAdditionalRootBinding(name) {
            return false
        }
        let sibling: NSharpLang.Compiler.Columnar.ColumnarSiblingCallFacts? = null
        if !emit.Context.RequiredScope().Facts.SiblingCallables.TryGetValue(name, out sibling) {
            return false
        }
        if sibling.TypeParameterCount != 0 || !sibling.Method.get_IsStatic() {
            return false
        }
        invoke := DelegateInvokeOrNull(handlerType)
        constructor := DelegateConstructorOrNull(handlerType)
        if invoke == null || constructor == null {
            return false
        }
        invokeParameters := invoke.GetParameters()
        if invokeParameters.Length != sibling.ParameterTypes.Length || invoke.get_ReturnType() != sibling.ReturnType {
            return false
        }
        index := 0
        while index < invokeParameters.Length {
            if invokeParameters[index].get_ParameterType() != sibling.ParameterTypes[index] || sibling.ParameterModifierKinds[index] != 0 {
                return false
            }
            index = index + 1
        }

        emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Ldftn(), emit.Plan.AddMethod(sibling.Method))
        emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), emit.Plan.AddConstructor(constructor))
        return true
    }

    // `off <handle>`: the handle is an ordinary value — a hoisted field, a parameter, a call result —
    // and `Unsubscribe()` claims the remove accessor once, which is what makes a second `off` a no-op.
    static func EmitOffStatement(emit: ColumnarMoveNextEmit, node: int): bool {
        nodes := emit.Context.Nodes
        if nodes.ChildCount(node) != 1 {
            emit.Context.Decline("emit.iterator.off-shape", "`off` has no subscription handle")
            return false
        }
        handleType := typeof(int)
        if !AppendValue(emit, nodes.Child(node, 0), out handleType) {
            return false
        }
        subscriptionRoot := typeof(NSharpLang.Runtime.NSharpEventSubscription)
        if !subscriptionRoot.IsAssignableFrom(handleType) {
            emit.Context.Decline("emit.iterator.off-handle-type", "`off` needs a subscription handle, got '" + handleType.Name + "'")
            return false
        }
        unsubscribe := subscriptionRoot.GetMethod("Unsubscribe", Type.EmptyTypes)
        if unsubscribe == null {
            emit.Context.Decline("emit.iterator.off-runtime-handle", "the N# runtime's event-subscription handle has no Unsubscribe()")
            return false
        }
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), emit.Plan.AddMethod(unsubscribe))
        return true
    }

    // WHETHER THE RECEIVER CHAIN NAMES A TYPE RATHER THAN A VALUE. A hoisted binding of the machine or
    // a sibling function of the same spelling shadows a type name, exactly as a local does in an
    // ordinary body; what is left is asked of the source registry first (a type this compilation is
    // still building has no metadata) and then of the external resolver.
    static func TryResolveIteratorEventOwnerTypeName(emit: ColumnarMoveNextEmit, receiverNode: int, out ownerType: Type): bool {
        ownerType = null
        nodes := emit.Context.Nodes
        scope := nodes.BindingScope
        ownerName := ""
        rootName := ""
        if scope == null || !ColumnarExternalStaticMemberPlanner.TryGetQualifiedName(nodes, emit.Context.Source, receiverNode, 0, out ownerName, out rootName) {
            return false
        }
        if emit.Context.HasHoistedField(rootName) || emit.Context.EnclosingFieldIndex(rootName) >= 0 || nodes.HasAdditionalRootBinding(rootName) {
            return false
        }
        facts := emit.Context.RequiredScope().Facts
        sourceOwner: Type = null
        if ownerName == rootName && facts.ExactSourceTypes.TryGetValue(rootName, out sourceOwner) {
            ownerType = sourceOwner
            return true
        }
        let resolved: System.Type? = null
        if !scope.TryResolveExternalStaticOwnerType(nodes.EnclosingTypeName, nodes.VisibleTypeParameterNames, rootName, ownerName, out resolved) {
            return false
        }
        ownerType = resolved
        return true
    }

    // Whether an event of this name and staticness exists on the owner's chain, asked without reading
    // its accessors — the static-owner probe, which must not commit to a receiver-less shape before it
    // knows there is a static event to bind.
    static func IteratorEventOnChain(emit: ColumnarMoveNextEmit, ownerType: Type, eventName: string, staticOnly: bool): bool {
        let handlerType: System.Type? = null
        let addMethod: System.Reflection.MethodInfo? = null
        let removeMethod: System.Reflection.MethodInfo? = null
        return TryResolveIteratorEventAccessors(emit, ownerType, eventName, staticOnly, out handlerType, out addMethod, out removeMethod)
    }

    // THE EVENT, FROM WHICHEVER HALF OF THE SEARCH ANSWERS. A type this compilation declares has no
    // `EventInfo` while its builder is open, so its accessors come from the definition that made them;
    // an external one arrives as metadata. Both halves supply the same three facts.
    static func TryResolveIteratorEventAccessors(emit: ColumnarMoveNextEmit, ownerType: Type, eventName: string, staticOnly: bool, out handlerType: Type, out addMethod: MethodInfo, out removeMethod: MethodInfo): bool {
        handlerType = null
        addMethod = null
        removeMethod = null
        if ownerType == null {
            return false
        }

        sourceEvent := FindIteratorSourceEventOnChain(emit, ownerType, eventName, staticOnly)
        if sourceEvent != null {
            handlerType = sourceEvent.HandlerType
            addMethod = ColumnarSourceSelfInstantiation.BindOn(ColumnarSourceSelfInstantiation.Of(ownerType), sourceEvent.Add)
            removeMethod = ColumnarSourceSelfInstantiation.BindOn(ColumnarSourceSelfInstantiation.Of(ownerType), sourceEvent.Remove)
            return handlerType != null && addMethod != null && removeMethod != null
        }

        flags := BindingFlags.Public | BindingFlags.FlattenHierarchy
        if staticOnly {
            flags = flags | BindingFlags.Static
        } else {
            flags = flags | BindingFlags.Instance
        }
        walk: Type = ownerType
        while walk != null {
            // A type still being BUILT answers no reflection question — `TypeBuilder.GetEvent` throws
            // rather than answering — so a source rung is skipped rather than asked.
            if walk as TypeBuilder == null && walk as EnumBuilder == null {
                candidate := walk.GetEvent(eventName, flags)
                if candidate != null {
                    handlerType = candidate.get_EventHandlerType()
                    addMethod = candidate.GetAddMethod(false)
                    removeMethod = candidate.GetRemoveMethod(false)
                    return handlerType != null && addMethod != null && removeMethod != null
                }
            }
            walk = walk.get_BaseType()
        }
        return false
    }

    static func FindIteratorSourceEventOnChain(emit: ColumnarMoveNextEmit, ownerType: Type, eventName: string, staticOnly: bool): ColumnarEventDef? {
        ownerBuilder := ownerType as TypeBuilder
        if ownerBuilder == null {
            return null
        }
        walk := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(emit.Context.RequiredScope().Facts.StructDefinitions, ownerBuilder)
        while walk != null {
            let candidate: NSharpLang.Compiler.Columnar.ColumnarEventDef? = null
            if walk.Events.TryGetValue(eventName, out candidate) && candidate.IsStatic == staticOnly {
                return candidate
            }
            walk = walk.BaseDef
        }
        return null
    }

    static func LambdaLoopCaptureNames(emit: ColumnarMoveNextEmit, node: int): string[] {
        nodes := emit.Context.Nodes
        childCount := nodes.ChildCount(node)
        parameters := new HashSet<string>(StringComparer.Ordinal)
        p := 0
        while p < childCount - 1 {
            parameters.Add(nodes.Text(emit.Context.Source, nodes.Child(node, p)))
            p = p + 1
        }
        loopCaptures := new HashSet<string>(StringComparer.Ordinal)
        for name in emit.Context.Shape.LoopCaptureNames {
            loopCaptures.Add(name)
        }
        if childCount < 1 {
            return System.Array.Empty<string>()
        }
        captures := ColumnarLambdaPlacementPlanner.PlanCaptureSet(nodes, emit.Context.Source, nodes.Child(node, childCount - 1), parameters, loopCaptures)
        result := new string[](captures.Count)
        captures.CopyTo(result)
        System.Array.Sort(result, StringComparer.Ordinal)
        return result
    }

    static func TryCreateLambdaDisplay(emit: ColumnarMoveNextEmit, captureNames: string[], out placement: ColumnarIteratorLambdaDisplay): bool {
        placement = null
        context := emit.Context
        builder := context.Builder
        synthesized := context.SynthesizedTypes
        if builder == null || synthesized == null {
            context.Decline("emit.iterator.lambda-unsupported", "a per-iteration lambda requires the state-machine builder and synthesized-type ledger")
            return false
        }
        moduleObject: object? = (builder as Type).get_Module()
        module := (ModuleBuilder)moduleObject
        display := module.DefineType(
            context.Shape.TypeName + "<>c__Display" + emit.NextLambda.ToString(),
            TypeAttributes.NotPublic | TypeAttributes.Class | TypeAttributes.Sealed
        )
        smParameters := context.GenericParameters
        displayParameters := System.Type.EmptyTypes
        displayTypeParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
        if smParameters.Length > 0 {
            names := new string[](smParameters.Length)
            i := 0
            while i < names.Length {
                names[i] = smParameters[i].get_Name()
                i = i + 1
            }
            displayBuilders := display.DefineGenericParameters(names)
            displayParameters = new Type[](displayBuilders.Length)
            i = 0
            while i < displayBuilders.Length {
                parameter: Type = displayBuilders[i]
                displayParameters[i] = parameter
                displayTypeParameters[names[i]] = parameter
                i = i + 1
            }
            if !CopyLambdaDisplayGenericConstraints(context, smParameters, displayBuilders, displayParameters) {
                context.Decline("emit.iterator.lambda-unsupported", "a per-iteration lambda display could not preserve its enclosing generic constraints")
                return false
            }
        }
        methodOwnerType: Type = display
        runtimeOwnerType: Type = display
        methodMachineType: Type = builder
        if displayParameters.Length > 0 {
            displayAsType: Type = display
            builderAsType: Type = builder
            methodOwnerType = displayAsType.MakeGenericType(displayParameters)
            runtimeOwnerType = displayAsType.MakeGenericType(smParameters)
            methodMachineType = builderAsType.MakeGenericType(displayParameters)
        }
        displayIdentity := context.Shape.TypeName + ".loop-display:" + emit.NextLambda.ToString()
        context.StructuralTypeReferences.RegisterSynthesizedType(context.SourceFileId, displayIdentity, emit.NextLambda, display, displayTypeParameters)
        constructor: ConstructorInfo = display.DefineDefaultConstructor(MethodAttributes.Public)
        runtimeConstructor := constructor
        if displayParameters.Length > 0 {
            runtimeConstructor = TypeBuilder.GetConstructor(runtimeOwnerType, constructor)
        }
        machineFieldBuilder := display.DefineField("<>__machine", methodMachineType, FieldAttributes.Public)
        machineField: FieldInfo = machineFieldBuilder
        runtimeMachineField: FieldInfo = machineFieldBuilder
        if displayParameters.Length > 0 {
            machineField = TypeBuilder.GetField(methodOwnerType, machineFieldBuilder)
            runtimeMachineField = TypeBuilder.GetField(runtimeOwnerType, machineFieldBuilder)
        }

        captureFields := new FieldInfo[](captureNames.Length)
        runtimeCaptureFields := new FieldInfo[](captureNames.Length)
        machineCaptureFields := new FieldInfo[](captureNames.Length)
        runtimeMachineCaptureFields := new FieldInfo[](captureNames.Length)
        capture := 0
        while capture < captureNames.Length {
            captureName := captureNames[capture]
            sourceBox: FieldInfo? = null
            valueType := context.FieldForName(captureName).get_FieldType()
            if !context.TryEnsureLoopCaptureBox(captureName, valueType, out sourceBox) || sourceBox == null {
                return false
            }
            boxDefinitionField := context.DefinitionFieldForName(ColumnarIteratorPlanner.LoopCaptureBoxFieldName(captureName))
            methodMachineCapture: FieldInfo = boxDefinitionField
            if displayParameters.Length > 0 {
                methodMachineCapture = TypeBuilder.GetField(methodMachineType, boxDefinitionField)
            }
            captureType := boxDefinitionField.get_FieldType()
            if displayParameters.Length > 0 {
                let substitutedCaptureType: Type? = null
                if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(smParameters, displayParameters, captureType, out substitutedCaptureType) || substitutedCaptureType == null {
                    return false
                }
                captureType = substitutedCaptureType
            }
            captureBuilder := display.DefineField(captureName, captureType, FieldAttributes.Public)
            captureHandle: FieldInfo = captureBuilder
            if displayParameters.Length > 0 {
                captureHandle = TypeBuilder.GetField(methodOwnerType, captureBuilder)
            }
            captureFields[capture] = captureHandle
            runtimeCaptureFields[capture] = captureHandle
            if displayParameters.Length > 0 {
                runtimeCaptureFields[capture] = TypeBuilder.GetField(runtimeOwnerType, captureBuilder)
            }
            machineCaptureFields[capture] = methodMachineCapture
            runtimeMachineCaptureFields[capture] = sourceBox
            capture = capture + 1
        }

        let receiverField: FieldInfo? = null
        let runtimeReceiverField: FieldInfo? = null
        let runtimeMachineReceiver: FieldInfo? = null
        if context.HasHoistedField("<>__this") {
            machineReceiverDefinition := context.DefinitionFieldForName("<>__this")
            methodMachineReceiver: FieldInfo = machineReceiverDefinition
            if displayParameters.Length > 0 {
                methodMachineReceiver = TypeBuilder.GetField(methodMachineType, machineReceiverDefinition)
            }
            receiverBuilder := display.DefineField("<>__this", methodMachineReceiver.get_FieldType(), FieldAttributes.Public)
            receiverHandle: FieldInfo = receiverBuilder
            if displayParameters.Length > 0 {
                receiverHandle = TypeBuilder.GetField(methodOwnerType, receiverBuilder)
            }
            receiverField = receiverHandle
            runtimeReceiverField = receiverHandle
            if displayParameters.Length > 0 {
                runtimeReceiverField = TypeBuilder.GetField(runtimeOwnerType, receiverBuilder)
            }
            runtimeMachineReceiver = context.FieldForName("<>__this")
        }
        synthesized.Add(display)
        placement = new ColumnarIteratorLambdaDisplay(display, methodOwnerType, runtimeOwnerType, constructor, runtimeConstructor, machineField, runtimeMachineField, captureNames, captureFields, runtimeCaptureFields, machineCaptureFields, runtimeMachineCaptureFields, receiverField, runtimeReceiverField, runtimeMachineReceiver, displayTypeParameters)
        return true
    }

    static func CopyLambdaDisplayGenericConstraints(context: ColumnarIteratorEmitContext, sourceParameters: Type[], destinationBuilders: GenericTypeParameterBuilder[], destinationParameters: Type[]): bool {
        if sourceParameters.Length != destinationBuilders.Length || destinationBuilders.Length != destinationParameters.Length || context.GenericSpecialConstraints.Length != destinationBuilders.Length || context.GenericBaseConstraints.Length != destinationBuilders.Length || context.GenericInterfaceConstraints.Length != destinationBuilders.Length {
            return false
        }
        index := 0
        while index < destinationBuilders.Length {
            destinationBuilders[index].SetGenericParameterAttributes((GenericParameterAttributes)ColumnarGenericConstraintPlanner.AttributeBitsFor(context.GenericSpecialConstraints[index]))
            sourceBase := context.GenericBaseConstraints[index]
            if sourceBase != null {
                let destinationBase: Type? = null
                if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(sourceParameters, destinationParameters, sourceBase, out destinationBase) || destinationBase == null {
                    return false
                }
                destinationBuilders[index].SetBaseTypeConstraint(destinationBase)
            }
            sourceInterfaces := context.GenericInterfaceConstraints[index]
            destinationInterfaces := new Type[](sourceInterfaces.Length)
            interfaceIndex := 0
            while interfaceIndex < sourceInterfaces.Length {
                let destinationInterface: Type? = null
                if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(sourceParameters, destinationParameters, sourceInterfaces[interfaceIndex], out destinationInterface) || destinationInterface == null {
                    return false
                }
                destinationInterfaces[interfaceIndex] = destinationInterface
                interfaceIndex = interfaceIndex + 1
            }
            if destinationInterfaces.Length > 0 {
                destinationBuilders[index].SetInterfaceConstraints(destinationInterfaces)
            }
            index = index + 1
        }
        return true
    }

    // A LAMBDA, AS A METHOD ON ITS EXACT CLOSURE OWNER.
    //
    // A generator has already hoisted every parameter and every local of its body into a field of its
    // own machine, so a lambda that captures only machine fields stays a private instance method on
    // that machine. A loop-declared capture instead selects a per-evaluation display that snapshots
    // the current StrongBox references and points back to the machine for ordinary outside bindings.
    //
    // The lambda's SIGNATURE is the delegate's own `Invoke`, so the target type decides the parameter
    // types and the result — the same rule an ordinary lambda conversion follows. Its body is planned
    // by the shared expression door against the selected capture scope and its own parameter slots.
    // Async wrapping is applied after selecting this owner, preserving per-iteration storage.
    static func AppendLambda(emit: ColumnarMoveNextEmit, node: int, delegateType: Type): bool {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        invoke := DelegateInvokeOrNull(delegateType)
        if invoke == null {
            emit.Context.Decline("emit.iterator.lambda-unsupported", "a lambda in an iterator body needs a delegate type to convert to, not '" + delegateType.Name + "'")
            return false
        }
        constructor := DelegateConstructorOrNull(delegateType)
        if constructor == null {
            emit.Context.Decline("emit.iterator.lambda-unsupported", "'" + delegateType.Name + "' has no (object, native int) constructor to build a lambda from")
            return false
        }
        builder := emit.Context.Builder
        if builder == null {
            emit.Context.Decline("emit.iterator.lambda-unsupported", "a lambda in an iterator body requires the state-machine builder")
            return false
        }
        captureNames := LambdaLoopCaptureNames(emit, node)
        let display: ColumnarIteratorLambdaDisplay? = null
        if captureNames.Length > 0 && !TryCreateLambdaDisplay(emit, captureNames, out display) {
            return false
        }

        invokeParameters := invoke.GetParameters()
        childCount := nodes.ChildCount(node)
        if childCount - 1 != invokeParameters.Length {
            emit.Context.Decline("emit.iterator.lambda-unsupported", "this lambda declares " + (childCount - 1).ToString() + " parameter(s) but '" + delegateType.Name + "' takes " + invokeParameters.Length.ToString())
            return false
        }
        parameterTypes := new Type[](invokeParameters.Length)
        parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
        parameterTypeMap := new Dictionary<string, Type>(StringComparer.Ordinal)
        ownerBuilder := builder
        if display != null {
            ownerBuilder = display.Definition
        }
        smParameters := emit.Context.GenericParameters
        ownerParameters := ownerBuilder.GetGenericArguments()
        p := 0
        while p < invokeParameters.Length {
            parameterType := invokeParameters[p].get_ParameterType()
            if display != null && smParameters.Length > 0 {
                substitutedParameter := parameterType
                if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(smParameters, ownerParameters, parameterType, out substitutedParameter) {
                    return false
                }
                parameterType = substitutedParameter
            }
            parameterTypes[p] = parameterType
            parameterName := nodes.Text(source, nodes.Child(node, p))
            parameterOrdinals[parameterName] = p + 1
            parameterTypeMap[parameterName] = parameterTypes[p]
            p = p + 1
        }
        returnType: Type = invoke.get_ReturnType()
        if display != null && smParameters.Length > 0 {
            substitutedReturn := returnType
            if !ColumnarGenericConstraintPlanner.TrySubstituteGenericTypeArguments(smParameters, ownerParameters, returnType, out substitutedReturn) {
                return false
            }
            returnType = substitutedReturn
        }
        bodyReturnType := returnType
        isAsync := ColumnarLambdaNodeFacts.IsAsyncLambda(nodes.Kind(node))
        if isAsync && !TryGetAsyncLambdaResultType(returnType, out bodyReturnType) {
            emit.Context.Decline("emit.iterator.lambda-async-target", "an `async` lambda inside a generator needs a delegate returning Task, Task<T>, ValueTask or ValueTask<T>")
            return false
        }

        lambdaName := "<>__lambda" + emit.NextLambda.ToString()
        emit.NextLambda = emit.NextLambda + 1
        lambdaVisibility := display == null ? MethodAttributes.Private : MethodAttributes.Assembly
        lambdaMethod := ownerBuilder.DefineMethod(lambdaName, lambdaVisibility | MethodAttributes.HideBySig, returnType, parameterTypes)
        lambdaScope := CreateLambdaBodyScope(emit, display, parameterOrdinals, parameterTypeMap)
        if lambdaScope == null || !AppendLambdaBody(emit, nodes.Child(node, childCount - 1), lambdaMethod, lambdaScope, bodyReturnType, returnType, isAsync) {
            return false
        }

        lambdaHandle: MethodInfo = lambdaMethod
        instantiation := emit.Context.GenericMemberType
        if display != null {
            if smParameters.Length > 0 {
                lambdaHandle = TypeBuilder.GetMethod(display.RuntimeOwnerType, lambdaMethod)
            }
            displayTypePool := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(display.RuntimeOwnerType), emit.Context.StructuralTypeReferences)
            displayLocal := emit.Plan.DeclarePlanLocal(displayTypePool)
            emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), emit.Plan.AddConstructorWithSignature(display.RuntimeConstructor, display.RuntimeOwnerType, System.Type.EmptyTypes))
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), displayLocal)
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), displayLocal)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), emit.Plan.AddField(display.RuntimeMachineField))
            capture := 0
            while capture < display.CaptureNames.Length {
                emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), displayLocal)
                LoadThis(emit)
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), emit.Plan.AddField(display.RuntimeMachineCaptureFields[capture]))
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), emit.Plan.AddField(display.RuntimeCaptureFields[capture]))
                capture = capture + 1
            }
            if display.RuntimeEnclosingReceiverField != null && display.RuntimeMachineReceiverField != null {
                emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), displayLocal)
                LoadThis(emit)
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), emit.Plan.AddField(display.RuntimeMachineReceiverField))
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), emit.Plan.AddField(display.RuntimeEnclosingReceiverField))
            }
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), displayLocal)
        } else if instantiation != null {
            lambdaHandle = TypeBuilder.GetMethod(instantiation, lambdaMethod)
            LoadThis(emit)
        } else {
            LoadThis(emit)
        }
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Ldftn(), emit.Plan.AddMethod(lambdaHandle))
        emit.Plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), emit.Plan.AddConstructor(constructor))
        return true
    }

    // The lambda's own body, planned into its selected machine or per-iteration display method.
    static func CreateLambdaBodyScope(emit: ColumnarMoveNextEmit, display: ColumnarIteratorLambdaDisplay?, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>): ColumnarIteratorBodyScope? {
        context := emit.Context
        if display == null {
            scope := ColumnarIteratorBodyScope.Create(context.StateMachineType, context.RequiredScope().Facts, context.TypeParameters, parameterOrdinals, parameterTypes)
            index := 0
            while index < context.FieldNames.Length && index < context.Fields.Length {
                if context.Fields[index] != null {
                    scope.PublishField(context.FieldNames[index], context.Fields[index])
                }
                index = index + 1
            }
            capture := 0
            while capture < context.Shape.LoopCaptureNames.Length {
                name := context.Shape.LoopCaptureNames[capture]
                boxField: FieldInfo? = null
                if context.TryEnsureLoopCaptureBox(name, context.FieldForName(name).get_FieldType(), out boxField) && boxField != null {
                    scope.PublishBoxedCapture(name, boxField, context.FieldForName(name).get_FieldType())
                }
                capture = capture + 1
            }
            if scope.HasField("<>__this") {
                receiver := scope.FieldHandle("<>__this")
                member := 0
                while member < context.EnclosingFieldNames.Length && member < context.EnclosingFields.Length {
                    scope.PublishEnclosingMember(context.EnclosingFieldNames[member], receiver, context.EnclosingFields[member])
                    member = member + 1
                }
            }
            return scope
        }

        scope := ColumnarIteratorBodyScope.Create(display.MethodOwnerType, context.RequiredScope().Facts, display.TypeParameters, parameterOrdinals, parameterTypes)
        index := 0
        while index < context.FieldNames.Length && index < context.Fields.Length {
            definitionField := context.DefinitionFields[index]
            capturedDirectly := false
            for captureName in display.CaptureNames {
                if captureName == context.FieldNames[index] {
                    capturedDirectly = true
                }
            }
            if definitionField != null && !capturedDirectly {
                machineField := definitionField
                if display.TypeParameters.Count > 0 {
                    machineField = TypeBuilder.GetField(display.MachineField.get_FieldType(), definitionField)
                }
                scope.PublishEnclosingMember(context.FieldNames[index], display.MachineField, machineField)
            }
            index = index + 1
        }
        capture := 0
        while capture < display.CaptureNames.Length {
            valueType := display.CaptureFields[capture].get_FieldType().GetGenericArguments()[0]
            scope.PublishBoxedCapture(display.CaptureNames[capture], display.CaptureFields[capture], valueType)
            capture = capture + 1
        }
        if display.EnclosingReceiverField != null {
            member := 0
            while member < context.EnclosingFieldNames.Length && member < context.EnclosingFields.Length {
                scope.PublishEnclosingMember(context.EnclosingFieldNames[member], display.EnclosingReceiverField, context.EnclosingFields[member])
                member = member + 1
            }
        }
        return scope
    }

    static func AppendLambdaBody(emit: ColumnarMoveNextEmit, bodyNode: int, lambdaMethod: MethodBuilder, scope: ColumnarIteratorBodyScope, bodyReturnType: Type, methodReturnType: Type, isAsync: bool): bool {
        context := emit.Context
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        if isAsync {
            if !AppendAsyncLambdaBody(emit, scope, bodyNode, plan, bodyReturnType, methodReturnType) {
                return false
            }
        } else {
            if context.Nodes.Kind(bodyNode) == 25 {
                if !AppendLambdaBlockBody(emit, scope, bodyNode, plan, bodyReturnType, false) {
                    return false
                }
            } else if !scope.TryAppendTargetTypedValue(context.Nodes, context.Source, bodyNode, plan, bodyReturnType) {
                context.Decline("emit.iterator.lambda-unsupported", "the body of a lambda in an iterator body could not be lowered as '" + bodyReturnType.Name + "'")
                return false
            }
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        }
        plan.CompleteMethodBody(methodReturnType)
        ColumnarCodePlanExecutor.Execute(plan, lambdaMethod.GetILGenerator(), context.RequiredScope().Facts.ModifiedMemberReferences)
        return true
    }

    // An async lambda keeps its selected machine or display method placement and capture
    // scope. Only its body contract changes: the written value is the task's result, every successful
    // exit wraps that value, and every synchronous exception becomes a faulted task. Await remains the
    // compiler's current blocking await inside this synthesized method, matching ordinary async lambdas.
    static func AppendAsyncLambdaBody(emit: ColumnarMoveNextEmit, scope: ColumnarIteratorBodyScope, bodyNode: int, plan: ColumnarCodePlan, bodyReturnType: Type, methodReturnType: Type): bool {
        context := emit.Context
        scope.Bindings.BlockingAwaitEnabled = true
        resultLocal := plan.DeclarePlanLocal(plan.AddType(methodReturnType))
        endLabel := plan.DefineLabel()
        plan.AppendBeginExceptionBlock(endLabel)
        if context.Nodes.Kind(bodyNode) == 25 {
            if !AppendLambdaBlockBody(emit, scope, bodyNode, plan, bodyReturnType, true) {
                return false
            }
        } else if !AppendAsyncLambdaValue(emit, scope, bodyNode, plan, bodyReturnType) {
            context.Decline("emit.iterator.lambda-unsupported", "the body of an async lambda in an iterator body could not be lowered as '" + bodyReturnType.Name + "'")
            return false
        }
        AppendCompletedAsyncLambdaReturn(plan, methodReturnType, bodyReturnType)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), resultLocal)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), endLabel)
        plan.AppendBeginCatchBlock(plan.AddType(typeof(Exception)))
        AppendFaultedAsyncLambdaReturn(plan, methodReturnType, bodyReturnType)
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), resultLocal)
        plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), endLabel)
        plan.AppendEndExceptionBlock()
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), resultLocal)
        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        return true
    }

    static func AppendAsyncLambdaValue(emit: ColumnarMoveNextEmit, scope: ColumnarIteratorBodyScope, node: int, plan: ColumnarCodePlan, targetType: Type): bool {
        nodes := emit.Context.Nodes
        if nodes.Kind(node) != 53 || nodes.ChildCount(node) != 1 {
            return scope.TryAppendTargetTypedValue(nodes, emit.Context.Source, node, plan, targetType)
        }
        awaitedType := typeof(object)
        if !AppendAsyncLambdaAwaitExpression(emit, scope, node, plan, out awaitedType) {
            return false
        }
        return awaitedType == targetType || scope.TryAppendStorageConversion(plan, awaitedType, targetType)
    }

    static func AppendAsyncLambdaAwaitExpression(emit: ColumnarMoveNextEmit, scope: ColumnarIteratorBodyScope, node: int, plan: ColumnarCodePlan, out awaitedType: Type): bool {
        awaitedType = typeof(object)
        nodes := emit.Context.Nodes
        if nodes.Kind(node) != 53 || nodes.ChildCount(node) != 1 {
            return false
        }
        operandType := typeof(object)
        if !scope.TryAppendValue(nodes, emit.Context.Source, nodes.Child(node, 0), plan, out operandType) {
            return false
        }
        return ColumnarRangeIndexPlanner.AppendBlockingAwaitOfStackValue(plan, operandType, out awaitedType)
    }

    static func TryGetAsyncLambdaResultType(returnType: Type, out resultType: Type): bool {
        resultType = ColumnarTypeOfPlanner.RequiredVoidType()
        if returnType == typeof(System.Threading.Tasks.Task) || returnType == typeof(System.Threading.Tasks.ValueTask) {
            return true
        }
        if !returnType.get_IsGenericType() {
            return false
        }
        definition := returnType.GetGenericTypeDefinition()
        if definition != typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition() && definition != typeof(System.Threading.Tasks.ValueTask<int>).GetGenericTypeDefinition() {
            return false
        }
        resultType = returnType.GetGenericArguments()[0]
        return true
    }

    static func AppendCompletedAsyncLambdaReturn(plan: ColumnarCodePlan, returnType: Type, resultType: Type) {
        if returnType == typeof(System.Threading.Tasks.Task) {
            getter := (must typeof(System.Threading.Tasks.Task).GetProperty("CompletedTask")).GetGetMethod()
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(getter))
            return
        }
        if returnType == typeof(System.Threading.Tasks.ValueTask) {
            local := plan.DeclarePlanLocal(plan.AddType(returnType))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), local)
            plan.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), plan.AddType(returnType))
            plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), local)
            return
        }
        if returnType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition() {
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(RequiredTaskFactory("FromResult", true).MakeGenericMethod([resultType])))
            return
        }
        constructorTypes: Type[] = [resultType]
        plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructor(returnType.GetConstructor(constructorTypes)))
    }

    static func AppendFaultedAsyncLambdaReturn(plan: ColumnarCodePlan, returnType: Type, resultType: Type) {
        if returnType == typeof(System.Threading.Tasks.Task) {
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(RequiredTaskFactory("FromException", false)))
            return
        }
        if returnType == typeof(System.Threading.Tasks.ValueTask) {
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(RequiredTaskFactory("FromException", false)))
            constructorTypes: Type[] = [typeof(System.Threading.Tasks.Task)]
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructor(returnType.GetConstructor(constructorTypes)))
            return
        }
        taskType := typeof(System.Threading.Tasks.Task<int>).GetGenericTypeDefinition().MakeGenericType([resultType])
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethod(RequiredTaskFactory("FromException", true).MakeGenericMethod([resultType])))
        if returnType.GetGenericTypeDefinition() == typeof(System.Threading.Tasks.ValueTask<int>).GetGenericTypeDefinition() {
            constructorTypes: Type[] = [taskType]
            plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), plan.AddConstructor(returnType.GetConstructor(constructorTypes)))
        }
    }

    static func RequiredTaskFactory(name: string, generic: bool): MethodInfo {
        for candidate in typeof(System.Threading.Tasks.Task).GetMethods(BindingFlags.Public | BindingFlags.Static) {
            if candidate.get_Name() == name && candidate.get_IsGenericMethodDefinition() == generic && candidate.GetParameters().Length == 1 {
                return candidate
            }
        }
        throw new InvalidOperationException("Required Task." + name + " factory was not found.")
    }

    // A BLOCK-BODIED LAMBDA'S STATEMENTS, PLANNED INTO ITS OWN METHOD.
    //
    // `on list.CollectionChanged (sender, args) => { seen = seen + 1 }` is the shape every event
    // handler is written in, and a generator that could not lower it could not subscribe to anything
    // with more than one expression in the handler.
    //
    // THE THREE STATEMENT FORMS A HANDLER IS MADE OF, and nothing else is guessed at:
    //
    //   * an EXPRESSION statement — a call, almost always — whose value is discarded when it has one;
    //   * an ASSIGNMENT, which writes through the selected machine field, captured machine reference,
    //     or per-iteration StrongBox. A member or indexer target goes to the ordinary store owner, and
    //     a name that is neither is declined rather than silently written somewhere else;
    //   * a LOCAL DECLARATION, which lands in the plan's own local pool — a lambda's local is the
    //     lambda's, not the machine's, so it must not be hoisted.
    //
    // A `return` is admitted only as the LAST statement, because anything earlier needs a branch to a
    // shared exit this straight-line plan does not build; a handler returning `void` needs none at all.
    static func AppendLambdaBlockBody(emit: ColumnarMoveNextEmit, scope: ColumnarIteratorBodyScope, blockNode: int, plan: ColumnarCodePlan, returnType: Type, isAsync: bool): bool {
        context := emit.Context
        nodes := context.Nodes
        source := context.Source
        statementCount := nodes.ChildCount(blockNode)
        index := 0
        while index < statementCount {
            statement := nodes.Child(blockNode, index)
            isLast := index == statementCount - 1
            if !AppendLambdaBlockStatement(emit, scope, statement, plan, returnType, isLast, isAsync) {
                return false
            }
            index = index + 1
        }

        // A body that produced no value for a value-returning delegate cannot be completed here: the
        // `ret` the caller appends would run on an empty stack.
        if !ColumnarCodePlanExecutor.IsVoidType(returnType) && !LambdaBlockEndsWithReturn(nodes, blockNode) {
            context.Decline("emit.iterator.lambda-unsupported", "a block-bodied lambda in an iterator body must end with `return` when its delegate returns '" + returnType.Name + "'")
            return false
        }
        return true
    }

    static func LambdaBlockEndsWithReturn(nodes: ColumnarNodeTable, blockNode: int): bool {
        statementCount := nodes.ChildCount(blockNode)
        if statementCount == 0 {
            return false
        }
        return nodes.Kind(nodes.Child(blockNode, statementCount - 1)) == 20
    }

    static func AppendLambdaBlockStatement(emit: ColumnarMoveNextEmit, scope: ColumnarIteratorBodyScope, statement: int, plan: ColumnarCodePlan, returnType: Type, isLast: bool, isAsync: bool): bool {
        context := emit.Context
        nodes := context.Nodes
        source := context.Source
        kind := nodes.Kind(statement)
        if kind == 25 {
            inner := 0
            while inner < nodes.ChildCount(statement) {
                if !AppendLambdaBlockStatement(emit, scope, nodes.Child(statement, inner), plan, returnType, isLast && inner == nodes.ChildCount(statement) - 1, isAsync) {
                    return false
                }
                inner = inner + 1
            }
            return true
        }
        if kind == 20 {
            if !isLast {
                context.Decline("emit.iterator.lambda-unsupported", "a `return` before the end of a block-bodied lambda in an iterator body is not yet lowered")
                return false
            }
            if nodes.ChildCount(statement) == 0 {
                return true
            }
            appendedReturn := isAsync ? AppendAsyncLambdaValue(emit, scope, nodes.Child(statement, 0), plan, returnType) : scope.TryAppendTargetTypedValue(nodes, source, nodes.Child(statement, 0), plan, returnType)
            if !appendedReturn {
                context.Decline("emit.iterator.lambda-unsupported", "the returned value of a lambda in an iterator body could not be lowered as '" + returnType.Name + "'")
                return false
            }
            return true
        }
        if kind == 24 || kind == 40 {
            if isAsync && kind == 24 && nodes.ChildCount(statement) == 1 && nodes.Kind(nodes.Child(statement, 0)) == 53 {
                name := nodes.Text(source, statement)
                if name.Length == 0 || scope.Bindings.IsVisibleBindingName(name) {
                    return false
                }
                localType := typeof(object)
                if !AppendAsyncLambdaAwaitExpression(emit, scope, nodes.Child(statement, 0), plan, out localType) || !ColumnarMethodBodyPlanner.IsClaimedLocalType(localType) {
                    return false
                }
                local := plan.DeclarePlanLocal(plan.AddType(localType))
                plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), local)
                scope.Bindings.DeclarePlanLocal(name, local, localType)
                return true
            }
            if !ColumnarMethodBodyPlanner.TryAppendLocalDeclaration(nodes, source, statement, scope.Bindings, plan) {
                context.Decline("emit.iterator.lambda-unsupported", "a local declaration inside a block-bodied lambda in an iterator body could not be lowered")
                return false
            }
            return true
        }
        if kind != 23 || nodes.ChildCount(statement) != 1 {
            context.Decline("emit.iterator.lambda-unsupported", "a statement (node kind " + kind.ToString() + ") inside a block-bodied lambda in an iterator body is not yet lowered")
            return false
        }

        inner := nodes.Child(statement, 0)
        if nodes.Kind(inner) == 14 {
            return AppendLambdaBlockAssignment(emit, scope, inner, plan)
        }

        discardedType := typeof(int)
        appendedExpression := isAsync && nodes.Kind(inner) == 53 ? AppendAsyncLambdaAwaitExpression(emit, scope, inner, plan, out discardedType) : scope.TryAppendValue(nodes, source, inner, plan, out discardedType)
        if !appendedExpression {
            context.Decline("emit.iterator.lambda-unsupported", "an expression statement inside a block-bodied lambda in an iterator body could not be lowered")
            return false
        }
        if !ColumnarCodePlanExecutor.IsVoidType(discardedType) {
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
        }
        return true
    }

    // Captured writes use the selected machine or display receiver. Allocate argument zero only
    // when it is used, sharing the identifier planner's exact argument identity and deduplication.
    static func AppendLambdaBlockAssignment(emit: ColumnarMoveNextEmit, scope: ColumnarIteratorBodyScope, assignment: int, plan: ColumnarCodePlan): bool {
        context := emit.Context
        nodes := context.Nodes
        source := context.Source
        if nodes.ChildCount(assignment) != 2 || nodes.Text(source, assignment) != "=" {
            context.Decline("emit.iterator.lambda-unsupported", "a compound assignment inside a block-bodied lambda in an iterator body is not yet lowered")
            return false
        }
        target := nodes.Child(assignment, 0)
        value := nodes.Child(assignment, 1)
        if nodes.Kind(target) == 6 {
            name := nodes.Text(source, target)
            if scope.Bindings.BoxedCaptures.ContainsKey(name) {
                boxed := scope.Bindings.BoxedCaptures[name]
                boxField := boxed.Item1
                valueType := boxed.Item2
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, scope.StateMachineType, false))
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), plan.AddField(boxField))
                if !scope.TryAppendTargetTypedValue(nodes, source, value, plan, valueType) {
                    context.Decline("emit.iterator.lambda-unsupported", "the value assigned to '" + name + "' inside a lambda in an iterator body could not be lowered")
                    return false
                }
                valueField := StrongBoxValueField(boxField.get_FieldType())
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), plan.AddFieldWithSignature(valueField, boxField.get_FieldType(), valueType, false))
                return true
            }
            if scope.Bindings.CapturedInstanceFields.ContainsKey(name) {
                captured := scope.Bindings.CapturedInstanceFields[name]
                receiverField := captured.Item1
                memberField := captured.Item2
                plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, scope.StateMachineType, false))
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), plan.AddField(receiverField))
                if !scope.TryAppendTargetTypedValue(nodes, source, value, plan, memberField.get_FieldType()) {
                    context.Decline("emit.iterator.lambda-unsupported", "the value assigned to '" + name + "' inside a lambda in an iterator body could not be lowered")
                    return false
                }
                plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), plan.AddField(memberField))
                return true
            }
            if !scope.HasField(name) {
                context.Decline("emit.iterator.lambda-unsupported", "'" + name + "' is not a binding a lambda inside an iterator body can assign to")
                return false
            }
            field := scope.FieldHandle(name)
            receiverArgument := ColumnarBoundIdentifierPlanner.GetOrAddArgument(plan, 0, scope.StateMachineType, false)
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), receiverArgument)
            if !scope.TryAppendTargetTypedValue(nodes, source, value, plan, field.get_FieldType()) {
                context.Decline("emit.iterator.lambda-unsupported", "the value assigned to '" + name + "' inside a lambda in an iterator body could not be lowered")
                return false
            }
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), plan.AddField(field))
            return true
        }

        declineReason := ""
        if !ColumnarStoreTargetPlanner.ClaimsTarget(nodes, target) || !ColumnarStoreTargetPlanner.TryAppendStore(nodes, source, target, value, scope.Bindings, plan, out declineReason) {
            context.Decline("emit.iterator.lambda-unsupported", "an assignment inside a block-bodied lambda in an iterator body could not be lowered")
            return false
        }
        return true
    }

    // A delegate's `Invoke`, which is the signature a lambda converted to it must have.
    static func DelegateInvokeOrNull(delegateType: Type): MethodInfo? {
        if delegateType == null || !typeof(Delegate).IsAssignableFrom(delegateType) {
            return null
        }
        return delegateType.GetMethod("Invoke")
    }

    // The `(object, native int)` constructor every delegate declares, which is the second half of a
    // delegate creation.
    static func DelegateConstructorOrNull(delegateType: Type): ConstructorInfo? {
        if delegateType == null || !typeof(Delegate).IsAssignableFrom(delegateType) {
            return null
        }
        parameters := new Type[](2)
        parameters[0] = typeof(object)
        parameters[1] = typeof(IntPtr)
        if ColumnarTypeOfPlanner.ContainsBuilderBoundType(delegateType) && delegateType.get_IsGenericType() && !delegateType.get_IsGenericTypeDefinition() {
            definition := delegateType.GetGenericTypeDefinition()
            openConstructor := definition.GetConstructor(parameters)
            if openConstructor == null {
                return null
            }
            return TypeBuilder.GetConstructor(delegateType, openConstructor)
        }
        return delegateType.GetConstructor(parameters)
    }

    // A condition: an ordinary value the branch rows consume as a Boolean.
    static func AppendCondition(emit: ColumnarMoveNextEmit, node: int): bool {
        conditionType := typeof(int)
        if !AppendValue(emit, node, out conditionType) {
            return false
        }
        if conditionType != typeof(bool) {
            emit.Context.Decline("emit.iterator.unsupported-shape", "an iterator body condition must be a Boolean value, not '" + conditionType.Name + "'")
            return false
        }
        return true
    }

    // Emits one statement and reports whether control can FALL THROUGH past it. The rules mirror
    // WalkStatement exactly: blocks drop dead statements after a non-falling child, an if only emits
    // its join jump/label when the then-branch falls, and a while only emits its back edge when the
    // body falls — so the plan never contains an unreachable row or an unmarked label.
    static func EmitStatement(emit: ColumnarMoveNextEmit, node: int): bool {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        if emit.Context.Declined {
            return false
        }
        kind := nodes.Kind(node)
        if kind == 25 {
            return EmitBlockChildrenFrom(emit, node, 0)
        }
        if kind == 77 || kind == 81 {
            return EmitUsingStatement(emit, node)
        }
        if kind == 40 {
            // typed local declaration: value span = type, child 0 = name, child 1 = init. The field's
            // type came from the WRITTEN canonical, so it is already defined; a declaration without an
            // initializer leaves the field at its default — nothing to store.
            if nodes.ChildCount(node) >= 2 {
                name := nodes.Text(source, nodes.Child(node, 0))
                fieldType := emit.Context.FieldForName(name).get_FieldType()
                if emit.Context.IsLoopCaptured(name) {
                    if !AppendFreshLoopCaptureBox(emit, name, nodes.Child(node, 1), fieldType, true) {
                        return false
                    }
                } else if !AppendBoundFieldStore(emit, nodes.Child(node, 1), FieldPool(emit, name), fieldType) {
                    return false
                }
            } else {
                name := nodes.Text(source, nodes.Child(node, 0))
                if emit.Context.IsLoopCaptured(name) && !AppendFreshLoopCaptureBox(emit, name, 0, emit.Context.FieldForName(name).get_FieldType(), false) {
                    return false
                }
            }
            return true
        }
        if kind == 24 {
            // `:=` local declaration: value span = name, child 0 = init. The initializer's type IS the
            // local's type, so it is discovered first (by planning the value into a plan nobody runs),
            // the field is defined from it, and only then do the real rows go down in evaluation order.
            name := nodes.Text(source, node)
            initializerType := typeof(int)
            if !TryDiscoverBoundValueType(emit, nodes.Child(node, 0), out initializerType) {
                emit.Context.Decline("emit.iterator.unsupported-shape", "the initializer of local '" + name + "' could not be lowered in an iterator body")
                return false
            }
            hoisted: FieldInfo? = null
            if !emit.Context.TryEnsureHoistedField(name, initializerType, out hoisted) {
                emit.Context.Decline("emit.iterator.unsupported-shape", "local '" + name + "' cannot be hoisted as '" + initializerType.Name + "' in an iterator body")
                return false
            }
            if emit.Context.IsLoopCaptured(name) {
                if !AppendFreshLoopCaptureBox(emit, name, nodes.Child(node, 0), initializerType, true) {
                    return false
                }
            } else if !AppendBoundFieldStore(emit, nodes.Child(node, 0), FieldPool(emit, name), initializerType) {
                return false
            }
            return true
        }
        if kind == 23 {
            // expression statement: a unit await (async bodies), a bare postfix step (value dropped),
            // an assignment to a hoisted binding, or an ordinary value whose result is discarded.
            inner := nodes.Child(node, 0)
            if nodes.Kind(inner) == 53 {
                EmitUnitAwait(emit, inner)
                return !emit.Context.Declined
            }
            if nodes.Kind(inner) == 44 {
                EmitPostfixStep(emit, inner, false)
                return !emit.Context.Declined
            }
            if nodes.Kind(inner) == 14 {
                return EmitAssignment(emit, inner)
            }
            statementType := typeof(int)
            if !AppendValue(emit, inner, out statementType) {
                return false
            }
            if !ColumnarCodePlanExecutor.IsVoidType(statementType) {
                emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
            }
            return true
        }
        if kind == 26 {
            // while [condition, body]: the back edge only exists when the body can complete. A
            // `continue` targets the condition, which is where the loop's next iteration begins.
            condLabel := emit.Plan.DefineLabel()
            afterLabel := emit.Plan.DefineLabel()
            emit.Plan.AppendMarkLabel(condLabel)
            if !AppendCondition(emit, nodes.Child(node, 0)) {
                return false
            }
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), afterLabel)
            emit.PushLoop(condLabel, afterLabel, true)
            bodyFalls := EmitStatement(emit, nodes.Child(node, 1))
            emit.PopLoop()
            if bodyFalls {
                emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
            }
            emit.Plan.AppendMarkLabel(afterLabel)
            return !emit.Context.Declined
        }
        if kind == 27 {
            // if [condition, then, else?]: the join label is defined and jumped to only when the
            // then-branch falls through (otherwise the jump row would be unreachable).
            elseLabel := emit.Plan.DefineLabel()
            if !AppendCondition(emit, nodes.Child(node, 0)) {
                return false
            }
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), elseLabel)
            thenFalls := EmitStatement(emit, nodes.Child(node, 1))
            if emit.Context.Declined {
                return false
            }
            afterLabel := -1
            if thenFalls {
                afterLabel = emit.Plan.DefineLabel()
                emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), afterLabel)
            }
            emit.Plan.AppendMarkLabel(elseLabel)
            elseFalls := true
            if nodes.ChildCount(node) == 3 {
                elseFalls = EmitStatement(emit, nodes.Child(node, 2))
                if emit.Context.Declined {
                    return false
                }
            }
            if afterLabel >= 0 {
                emit.Plan.AppendMarkLabel(afterLabel)
            }
            return thenFalls || elseFalls
        }
        if kind == 72 {
            if nodes.ChildCount(node) == 1 {
                EmitYieldReturn(emit, nodes.Child(node, 0))
                return !emit.Context.Declined
            }
            AppendBodyExit(emit, emit.EndLabel)
            return false
        }
        if kind == 49 {
            return EmitTryStatement(emit, node)
        }
        if kind == 28 {
            // For [init, cond, incr, body]: `init` runs once (its local is a hoisted field), then the
            // while discipline with a trailing increment — the back edge (and the increment before it)
            // only exists when the body can complete.
            EmitStatement(emit, nodes.Child(node, 0))
            if emit.Context.Declined {
                return false
            }
            condLabel := emit.Plan.DefineLabel()
            stepLabel := emit.Plan.DefineLabel()
            afterLabel := emit.Plan.DefineLabel()
            emit.Plan.AppendMarkLabel(condLabel)
            if !AppendCondition(emit, nodes.Child(node, 1)) {
                return false
            }
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), afterLabel)
            // A `continue` targets the STEP, not the condition: `for i := 0; i < n; i++` must still
            // step `i` on the continue path or the loop never ends.
            emit.PushLoop(stepLabel, afterLabel, true)
            bodyFalls := EmitStatement(emit, nodes.Child(node, 3))
            continued := emit.PopLoop()
            if emit.Context.Declined {
                return false
            }
            if bodyFalls || continued {
                emit.Plan.AppendMarkLabel(stepLabel)
                EmitStatement(emit, nodes.Child(node, 2))
                if emit.Context.Declined {
                    return false
                }
                emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
            }
            if emit.Context.Declined {
                return false
            }
            emit.Plan.AppendMarkLabel(afterLabel)
            return true
        }
        if kind == 29 {
            // for..in [source, body]: a hoisted ARRAY field takes the index loop; every other source
            // takes the hoisted-enumerator loop — mirroring the walk.
            return EmitForIn(emit, nodes.Child(node, 0), nodes.Child(node, 1), nodes.Text(source, node))
        }
        if kind == 73 {
            // await foreach [source, body]: the asynchronous loop, which is also a region.
            return EmitAwaitForIn(emit, nodes.Child(node, 0), nodes.Child(node, 1), nodes.Text(source, node))
        }
        if kind == 76 {
            // The ANNOTATED spelling: name in child 0, collection in child 1, body in child 2. The
            // loop variable's field was defined from the annotation, so the element is converted to
            // it — the same conversion the ordinary form performs, once per iteration.
            return EmitForIn(emit, nodes.Child(node, 1), nodes.Child(node, 2), nodes.Text(source, nodes.Child(node, 0)))
        }
        if kind == 80 {
            return EmitOffStatement(emit, node)
        }
        if kind == 48 {
            // throw <expression>: the ordinary value owner builds the exception, then `throw`. A bare
            // `throw` (zero children) is the RETHROW — the exception the enclosing catch handler is
            // running for, re-raised with its stack trace intact. Either shape ends its path.
            if nodes.ChildCount(node) == 0 {
                if emit.CatchHandlerDepth == 0 {
                    emit.Context.Decline("emit.iterator.rethrow-placement", "a bare 'throw' is only valid inside a catch handler")
                    return false
                }

                emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Rethrow())
                return false
            }

            thrownType := typeof(int)
            if !AppendValue(emit, nodes.Child(node, 0), out thrownType) {
                return false
            }
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Throw())
            return false
        }
        if kind == 21 || kind == 22 {
            return EmitLoopBranch(emit, kind == 21)
        }
        emit.Context.Decline("emit.iterator.unsupported-shape", "an iterator body statement (node kind " + kind.ToString() + ") is not yet lowered")
        return false
    }

    // `break` / `continue` INSIDE A GENERATOR BODY. Neither was lowered at all: `func*` plus a loop
    // that broke or continued declined the whole program with "an iterator body statement (node kind
    // 21/22) is not yet lowered", which took a great many ordinary sequence functions with it — a
    // directory walk that skips an unreadable directory is the shape that found it.
    //
    // The branch itself is the ordinary one: to the innermost frame's exit label for `break`, to its
    // step label for `continue` (so a counted loop's increment runs on the continue path), and
    // `leave` rather than `br` when it crosses a protected region the loop opened outside of. Two
    // placements refuse instead: out of a `finally` (illegal IL whatever the target, and NL319
    // already reports it), and across a HOISTED handler, whose body stands past the region end and
    // would be skipped by a branch that does not know to stop there.
    static func EmitLoopBranch(emit: ColumnarMoveNextEmit, isBreak: bool): bool {
        word := isBreak ? "break" : "continue"
        if emit.LoopDepth == 0 {
            emit.Context.Decline("emit.iterator.loop-branch-placement", "`" + word + "` is only valid inside a loop")
            return false
        }

        frame := emit.LoopDepth - 1
        if !emit.LoopLowerable[frame] {
            emit.Context.Decline("emit.iterator.loop-branch-placement", "a `" + word + "` out of an `await foreach` is not yet lowered in an iterator body")
            return false
        }
        if emit.FinallyHandlerDepth > emit.LoopFinallyDepths[frame] {
            emit.Context.Decline("emit.iterator.loop-branch-placement", "a `" + word + "` cannot leave a `finally` handler")
            return false
        }
        if emit.HoistedDepth > emit.LoopHoistedDepths[frame] {
            emit.Context.Decline("emit.iterator.loop-branch-placement", "a `" + word + "` out of an `await`-bearing `finally` is not yet lowered in an iterator body")
            return false
        }

        target := emit.LoopBreakLabels[frame]
        if !isBreak {
            target = emit.LoopContinueLabels[frame]
            emit.LoopContinueUsed[frame] = true
        }

        crossesRegion := emit.RegionDepth > emit.LoopRegionDepths[frame]
        emit.Plan.AppendLabelInstruction((short)(crossesRegion ? ColumnarCodePlanContract.Leave() : ColumnarCodePlanContract.Br()), target)
        return false
    }

    // The block's statement loop, entered at an ordinal — the emission mirror of
    // `WalkBlockChildrenFrom`, and it has to be the mirror: a using DECLARATION guards the REST of the
    // block in both passes, so both passes must hand the remainder to the same region.
    static func EmitBlockChildrenFrom(emit: ColumnarMoveNextEmit, node: int, from: int): bool {
        nodes := emit.Context.Nodes
        n := from
        while n < nodes.ChildCount(node) {
            child := nodes.Child(node, n)
            if (nodes.Kind(child) == 77 || nodes.Kind(child) == 81) && nodes.ChildCount(child) == 1 {
                return EmitUsingDeclarationRegion(emit, node, n)
            }

            if !EmitStatement(emit, child) {
                return false
            }

            n = n + 1
        }

        return true
    }

    // A `using` STATEMENT INSIDE A GENERATOR BODY, lowered to the region the statement means.
    //
    // THE RESOURCE IS ACQUIRED BEFORE THE REGION ENTRY LABEL, which is the whole trick: a resume
    // branches to that label, so it re-enters the `try` without re-running the acquisition, and the
    // resource the suspended machine was holding is still in its field. The handler is guarded by
    // `state < 0` exactly as a written `finally` is — a `yield return` leaves the region without
    // leaving the statement, and releasing there would dispose a resource the consumer is about to
    // come back to.
    static func EmitUsingStatement(emit: ColumnarMoveNextEmit, node: int): bool {
        nodes := emit.Context.Nodes
        if nodes.ChildCount(node) != 2 {
            emit.Context.Decline("emit.iterator.unsupported-shape", "a `using` declaration with no block is not lowered in this position; write `using r := … { … }` with a block")
            return false
        }

        resourceName := ""
        if !EmitUsingResource(emit, node, out resourceName) {
            return false
        }

        return EmitUsingRegion(emit, node, resourceName, nodes.Child(node, 1), 0 - 1, 0)
    }

    static func EmitUsingDeclarationRegion(emit: ColumnarMoveNextEmit, blockNode: int, ordinal: int): bool {
        usingNode := emit.Context.Nodes.Child(blockNode, ordinal)
        resourceName := ""
        if !EmitUsingResource(emit, usingNode, out resourceName) {
            return false
        }

        return EmitUsingRegion(emit, usingNode, resourceName, 0 - 1, blockNode, ordinal + 1)
    }

    // The resource into its field, before any region opens.
    static func EmitUsingResource(emit: ColumnarMoveNextEmit, node: int, out resourceName: string): bool {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        resourceName = ""
        resourceNode := nodes.Child(node, 0)
        resourceKind := nodes.Kind(resourceNode)
        if resourceKind == 24 || resourceKind == 40 {
            if !EmitStatement(emit, resourceNode) {
                return false
            }

            if resourceKind == 24 {
                resourceName = nodes.Text(source, resourceNode)
            } else {
                resourceName = nodes.Text(source, nodes.Child(resourceNode, 0))
            }

            return true
        }

        name := ColumnarIteratorPlanner.UsingResourceFieldName(emit.NextUsingResource)
        emit.NextUsingResource = emit.NextUsingResource + 1
        resourceType := typeof(int)
        if !TryDiscoverBoundValueType(emit, resourceNode, out resourceType) {
            emit.Context.Decline("emit.iterator.unsupported-shape", "the resource of a `using` statement could not be lowered in an iterator body")
            return false
        }

        hoisted: FieldInfo? = null
        if !emit.Context.TryEnsureHoistedField(name, resourceType, out hoisted) {
            emit.Context.Decline("emit.iterator.unsupported-shape", "a `using` resource cannot be hoisted as '" + resourceType.Name + "' in an iterator body")
            return false
        }

        if !AppendBoundFieldStore(emit, resourceNode, FieldPool(emit, name), resourceType) {
            return false
        }

        resourceName = name
        return true
    }

    // ONE region shape for both forms: `bodyNode >= 0` is the block form's body, and otherwise the
    // guarded statements are the remaining children of `blockNode` from `restFrom` — the using
    // DECLARATION, whose region is the rest of its block.
    static func EmitUsingRegion(emit: ColumnarMoveNextEmit, node: int, resourceName: string, bodyNode: int, blockNode: int, restFrom: int): bool {
        if emit.Context.Nodes.Kind(node) == 81 {
            return EmitAwaitedUsingRegion(emit, resourceName, bodyNode, blockNode, restFrom)
        }

        field := emit.Context.FieldForName(resourceName)
        // AN EMITTED RESOURCE TYPE ANSWERS FROM ITS DEFINITION, NOT FROM REFLECTION — its builder has
        // not been baked while this body is planned, so `Type.GetInterfaces()` on it can answer empty
        // and a disposable source struct would look non-disposable. This is the same definition the
        // plain-body `using` consults (`ColumnarIlEmitter.PlanUsingDisposal`), reached through the
        // body scope's own live view.
        resourceDefinition: ColumnarStructDef? = null
        ColumnarSourceDefinitionResolver.TryResolveStruct(field.get_FieldType(), emit.Context.RequiredScope().Facts.StructDefinitions, out resourceDefinition)
        disposal := ColumnarUsingResourcePlanner.Plan(field.get_FieldType(), false, resourceDefinition)
        if disposal == null {
            emit.Context.Decline("emit.iterator.unsupported-shape", "the resource of a `using` statement has no release shape in an iterator body")
            return false
        }

        region := emit.NextTryRegion
        emit.NextTryRegion = emit.NextTryRegion + 1
        emit.Plan.AppendMarkLabel(emit.RegionEntryLabels[region])
        regionEnd := emit.Plan.DefineLabel()
        emit.Plan.AppendBeginExceptionBlock(regionEnd)
        emit.RegionDepth = emit.RegionDepth + 1
        AppendStateDispatch(emit, TotalResumeCount(emit.Context), region)

        bodyFalls := false
        if bodyNode >= 0 {
            bodyFalls = EmitStatement(emit, bodyNode)
        } else {
            bodyFalls = EmitBlockChildrenFrom(emit, blockNode, restFrom)
        }

        if emit.Context.Declined {
            return false
        }

        if bodyFalls {
            AppendBodyExit(emit, regionEnd)
        }

        emit.Plan.AppendBeginFinallyBlock()
        skipLabel := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), emit.StateFieldPool)
        EmitInt(emit, 0)
        emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Clt())
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipLabel)
        AppendUsingRelease(emit, disposal, resourceName)
        emit.Plan.AppendMarkLabel(skipLabel)
        emit.Plan.AppendEndExceptionBlock()
        emit.RegionDepth = emit.RegionDepth - 1
        return bodyFalls
    }

    // `await using` — THE SAME REGION, WITH A SUSPENDING RELEASE. The resource is acquired before the
    // region entry exactly as the synchronous form acquires it, the body keeps the region, and the
    // release is HOISTED to the ordinary code just past it, because `DisposeAsync()` has to be awaited
    // and an `await` cannot run inside the region it is unwinding. Everything the hoist costs — the
    // parked exception, the recorded exit — is the machinery `EmitHoistedHandlerRegion` already owns,
    // so this arm differs from a written awaiting `finally` only in WHOSE rows the handler is.
    //
    // There is no `state < 0` guard here and there is none there: a suspension inside the body leaves
    // to the METHOD's region end, not to this one, so it never reaches the handler at all.
    static func EmitAwaitedUsingRegion(emit: ColumnarMoveNextEmit, resourceName: string, bodyNode: int, blockNode: int, restFrom: int): bool {
        field := emit.Context.FieldForName(resourceName)
        resourceDefinition: ColumnarStructDef? = null
        ColumnarSourceDefinitionResolver.TryResolveStruct(field.get_FieldType(), emit.Context.RequiredScope().Facts.StructDefinitions, out resourceDefinition)
        disposal := ColumnarUsingResourcePlanner.Plan(field.get_FieldType(), true, resourceDefinition)
        if disposal == null {
            emit.Context.Decline("emit.iterator.async-await-unsupported", "the resource of an `await using` statement has no asynchronous release shape in an iterator body")
            return false
        }

        region := emit.NextTryRegion
        emit.NextTryRegion = emit.NextTryRegion + 1
        pendingName := ColumnarIteratorPlanner.PendingExceptionFieldName(region)
        branchName := ColumnarIteratorPlanner.PendingBranchFieldName(region)
        if !BeginHoistedHandlerRegion(emit, region, pendingName, branchName) {
            return false
        }

        bodyFalls := false
        if bodyNode >= 0 {
            bodyFalls = EmitStatement(emit, bodyNode)
        } else {
            bodyFalls = EmitBlockChildrenFrom(emit, blockNode, restFrom)
        }

        if emit.Context.Declined {
            return false
        }

        EndHoistedHandlerRegion(emit, bodyFalls, pendingName)
        emit.HoistedHandlerDepth = emit.HoistedHandlerDepth + 1
        AppendAwaitedUsingRelease(emit, disposal, resourceName)
        emit.HoistedHandlerDepth = emit.HoistedHandlerDepth - 1
        if emit.Context.Declined {
            return false
        }

        AppendHoistedHandlerTail(emit, pendingName, branchName)
        return !emit.Context.Declined
    }

    // THE AWAITED RELEASE, in the same four shapes the synchronous one has — the difference is only
    // that `DisposeAsync()` leaves a ValueTask on the stack that has to be awaited, and that the
    // suspension needs `this` underneath the awaitable. A guard that skips the call skips the
    // suspension with it, which is legal: a resume state nothing reaches is simply never dispatched.
    static func AppendAwaitedUsingRelease(emit: ColumnarMoveNextEmit, disposal: ColumnarUsingDisposalPlan, resourceName: string) {
        fieldPool := FieldPool(emit, resourceName)
        methodPool := emit.Plan.AddMethod(disposal.Method)
        releaseType := disposal.Method.get_ReturnType()
        if disposal.Kind == 1 || disposal.Kind == 4 {
            LoadThis(emit)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), fieldPool)
            if disposal.Kind == 1 {
                resourceTypeIdx := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(disposal.ResourceType), emit.Context.StructuralTypeReferences)
                emit.Plan.AppendTypeInstruction(ColumnarCodePlanContract.Constrained(), resourceTypeIdx)
                emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodPool)
            } else {
                emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodPool)
            }
            AppendDiscardedAwait(emit, releaseType)
            return
        }

        if disposal.Kind == 3 {
            interfaceTypeIdx := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(disposal.InterfaceType), emit.Context.StructuralTypeReferences)
            testedLocal := emit.Plan.DeclarePlanLocal(interfaceTypeIdx)
            skipRuntime := emit.Plan.DefineLabel()
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
            emit.Plan.AppendTypeInstruction(ColumnarCodePlanContract.Isinst(), interfaceTypeIdx)
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), testedLocal)
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), testedLocal)
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipRuntime)
            LoadThis(emit)
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), testedLocal)
            emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodPool)
            AppendDiscardedAwait(emit, releaseType)
            emit.Plan.AppendMarkLabel(skipRuntime)
            return
        }

        skipDispose := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipDispose)
        LoadThis(emit)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodPool)
        AppendDiscardedAwait(emit, releaseType)
        emit.Plan.AppendMarkLabel(skipDispose)
    }

    // A synthesized await whose result nobody binds: suspend, then drop whatever `GetResult()`
    // produced. `ValueTask.GetResult()` is void and produces nothing, but a user-written
    // `DisposeAsync()` returning a `ValueTask<T>` would, and dropping it here is the same discipline
    // a statement-position `await` follows.
    static func AppendDiscardedAwait(emit: ColumnarMoveNextEmit, awaitableType: Type) {
        resultType := VoidReturnType()
        if !AppendAwaitOfStackValue(emit, awaitableType, out resultType) {
            return
        }
        if !ColumnarCodePlanExecutor.IsVoidType(resultType) {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
        }
    }

    // The release itself, over a FIELD rather than a local: a null check then the interface call for a
    // resource whose type names the interface, a run-time test for one whose static type does not, and
    // a direct call for a declared member.
    //
    // A VALUE-TYPED RESOURCE RELEASES THROUGH ITS OWN ADDRESS, which over a hoisted field is `ldflda`
    // rather than the `ldloca` a plain body writes — the resource lives on the state machine, and the
    // machine's `this` is argument 0 of `MoveNext`. `constrained.` is what makes the following
    // `callvirt` run `Dispose` on THAT storage instead of on a box of it, which is the difference
    // between a struct observing one disposal and observing none. A value type that declares
    // `Dispose` WITHOUT the interface (kind 4) has no slot to constrain to, so the address alone is
    // the receiver of a direct call. Neither shape takes a null guard: a struct is never null.
    static func AppendUsingRelease(emit: ColumnarMoveNextEmit, disposal: ColumnarUsingDisposalPlan, resourceName: string) {
        fieldPool := FieldPool(emit, resourceName)
        methodPool := emit.Plan.AddMethod(disposal.Method)
        if disposal.Kind == 1 {
            resourceTypeIdx := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(disposal.ResourceType), emit.Context.StructuralTypeReferences)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), fieldPool)
            emit.Plan.AppendTypeInstruction(ColumnarCodePlanContract.Constrained(), resourceTypeIdx)
            emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodPool)
            return
        }
        if disposal.Kind == 4 {
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), fieldPool)
            emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodPool)
            return
        }
        if disposal.Kind == 3 {
            interfaceTypeIdx := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(disposal.InterfaceType), emit.Context.StructuralTypeReferences)
            testedLocal := emit.Plan.DeclarePlanLocal(interfaceTypeIdx)
            skipRuntime := emit.Plan.DefineLabel()
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
            emit.Plan.AppendTypeInstruction(ColumnarCodePlanContract.Isinst(), interfaceTypeIdx)
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), testedLocal)
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), testedLocal)
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipRuntime)
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), testedLocal)
            emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodPool)
            emit.Plan.AppendMarkLabel(skipRuntime)
            return
        }

        skipDispose := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipDispose)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodPool)
        emit.Plan.AppendMarkLabel(skipDispose)
    }

    // THE PROTECTED REGION A GENERATOR BODY WRITES. The `try` becomes a real EH clause whose resume
    // points live INSIDE it, so the region opens with its own state dispatch: the enclosing dispatch
    // could only branch to the region's entry, and this is the hop that finishes the journey.
    //
    // The `finally` handler is guarded by the machine's own state. A handler runs on every way out of
    // a protected region, and a `yield return` leaves one — but suspending is not leaving the
    // statement, so its handler must not run. The state says which happened: a suspension stored its
    // resume state (a positive number) just before branching out, while a normal completion, an
    // exception in flight and a dispose-driven unwind are all still marked running (-1). `state < 0`
    // is therefore exactly "this exit is final", and it is the same test the C# compiler emits.
    static func EmitTryStatement(emit: ColumnarMoveNextEmit, node: int): bool {
        nodes := emit.Context.Nodes
        childCount := nodes.ChildCount(node)
        finallyNode := 0 - 1
        handlerEnd := childCount
        if childCount >= 2 && nodes.Kind(nodes.Child(node, childCount - 1)) == 25 {
            finallyNode = nodes.Child(node, childCount - 1)
            handlerEnd = childCount - 1
        }

        if finallyNode >= 0 && ColumnarIteratorPlanner.ContainsAwait(nodes, finallyNode) {
            return EmitHoistedHandlerRegion(emit, node, finallyNode)
        }

        region := emit.NextTryRegion
        emit.NextTryRegion = emit.NextTryRegion + 1
        emit.Plan.AppendMarkLabel(emit.RegionEntryLabels[region])
        regionEnd := emit.Plan.DefineLabel()
        emit.Plan.AppendBeginExceptionBlock(regionEnd)
        emit.RegionDepth = emit.RegionDepth + 1
        AppendStateDispatch(emit, TotalResumeCount(emit.Context), region)

        tryFalls := EmitStatement(emit, nodes.Child(node, 0))
        if emit.Context.Declined {
            return false
        }
        if tryFalls {
            AppendBodyExit(emit, regionEnd)
        }

        handlersFall := false
        catchOrdinal := 0
        c := 1
        while c < handlerEnd {
            clause := nodes.Child(node, c)
            catchFalls := false
            if !EmitCatchClause(emit, clause, catchOrdinal, regionEnd, out catchFalls) {
                return false
            }
            if catchFalls {
                handlersFall = true
            }
            catchOrdinal = catchOrdinal + 1
            c = c + 1
        }

        if finallyNode >= 0 {
            emit.Plan.AppendBeginFinallyBlock()
            skipLabel := emit.Plan.DefineLabel()
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), emit.StateFieldPool)
            EmitInt(emit, 0)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Clt())
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipLabel)
            emit.FinallyHandlerDepth = emit.FinallyHandlerDepth + 1
            EmitStatement(emit, finallyNode)
            emit.FinallyHandlerDepth = emit.FinallyHandlerDepth - 1
            if emit.Context.Declined {
                return false
            }
            emit.Plan.AppendMarkLabel(skipLabel)
        }

        emit.Plan.AppendEndExceptionBlock()
        emit.RegionDepth = emit.RegionDepth - 1
        return tryFalls || handlersFall
    }

    // A REGION WHOSE HANDLER SUSPENDS. The handler cannot run inside the region — a suspension leaves
    // the method with an empty stack and comes back through the state dispatch, and a dispatch cannot
    // branch INTO a protected region — so the body keeps the region and the handler is emitted just
    // PAST it, in ordinary code where an `await` is an ordinary suspension:
    //
    //     entry_k:  this.<>__pending{k} = null; this.<>__branch{k} = 0
    //               try   { <dispatch for k> <body> leave end_k }
    //               catch (Exception e) { this.<>__pending{k} = ExceptionDispatchInfo.Capture(e) }
    //     end_k:    <handler body — awaits freely>
    //               if (this.<>__pending{k} != null) this.<>__pending{k}.Throw()
    //               if (this.<>__branch{k} != 0) <re-issue the exit, one level out>
    //
    // The parked exception is re-raised AFTER the handler ran, through `ExceptionDispatchInfo` so the
    // original stack trace survives — which is the observable difference between this and a plain
    // `throw e`. A suspension inside the BODY leaves to the METHOD's region end rather than this
    // region's, so it never touches the handler, exactly as a `yield` inside a real `finally`-guarded
    // region is skipped by that handler's state guard.
    //
    // This is Roslyn's `AsyncMethodToStateMachineRewriter.VisitTryStatement` lowering, and it carries
    // Roslyn's semantics with it: a handler that itself raises replaces the parked exception, which is
    // what C# does for an exception thrown from a `finally` as well.
    static func EmitHoistedHandlerRegion(emit: ColumnarMoveNextEmit, node: int, finallyNode: int): bool {
        region := emit.NextTryRegion
        emit.NextTryRegion = emit.NextTryRegion + 1
        pendingName := ColumnarIteratorPlanner.PendingExceptionFieldName(region)
        branchName := ColumnarIteratorPlanner.PendingBranchFieldName(region)
        if !BeginHoistedHandlerRegion(emit, region, pendingName, branchName) {
            return false
        }

        bodyFalls := EmitStatement(emit, emit.Context.Nodes.Child(node, 0))
        if emit.Context.Declined {
            return false
        }

        EndHoistedHandlerRegion(emit, bodyFalls, pendingName)
        emit.HoistedHandlerDepth = emit.HoistedHandlerDepth + 1
        EmitStatement(emit, finallyNode)
        emit.HoistedHandlerDepth = emit.HoistedHandlerDepth - 1
        if emit.Context.Declined {
            return false
        }

        AppendHoistedHandlerTail(emit, pendingName, branchName)
        return !emit.Context.Declined
    }

    // The region's PROLOGUE: clear both slots, open the protected region, push it on the hoisted
    // stack so every exit out of the body routes through its end, and dispatch inside it.
    static func BeginHoistedHandlerRegion(emit: ColumnarMoveNextEmit, region: int, pendingName: string, branchName: string): bool {
        pendingField: FieldInfo? = null
        if !emit.Context.TryEnsureHoistedField(pendingName, ExceptionDispatchInfoRuntimeType(), out pendingField) {
            emit.Context.Decline("emit.iterator.async-await-unsupported", "the pending-exception slot of an awaiting handler could not be hoisted")
            return false
        }

        emit.Plan.AppendMarkLabel(emit.RegionEntryLabels[region])
        LoadThis(emit)
        emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, pendingName))
        LoadThis(emit)
        EmitInt(emit, 0)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, branchName))

        regionEnd := emit.Plan.DefineLabel()
        emit.Plan.AppendBeginExceptionBlock(regionEnd)
        emit.RegionDepth = emit.RegionDepth + 1
        emit.HoistedRegionEnds[emit.HoistedDepth] = regionEnd
        emit.HoistedBranchFields[emit.HoistedDepth] = branchName
        emit.HoistedDepth = emit.HoistedDepth + 1
        AppendStateDispatch(emit, TotalResumeCount(emit.Context), region)
        return true
    }

    // The region's EPILOGUE: leave on the falling-through path, park whatever the body raised, close
    // the region and pop it off the hoisted stack. The rows the caller writes next are the HANDLER,
    // and they stand outside the region — which is what lets them suspend.
    static func EndHoistedHandlerRegion(emit: ColumnarMoveNextEmit, bodyFalls: bool, pendingName: string) {
        depth := emit.HoistedDepth - 1
        if bodyFalls {
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), emit.HoistedRegionEnds[depth])
        }

        exTypeIdx := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(ExceptionRuntimeType()), emit.Context.StructuralTypeReferences)
        emit.Plan.AppendBeginCatchBlock(exTypeIdx)
        caught := emit.Plan.DeclarePlanLocal(exTypeIdx)
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), caught)
        LoadThis(emit)
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), caught)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), emit.Plan.AddMethod(ExceptionDispatchInfoCaptureMethod()))
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, pendingName))
        emit.Plan.AppendEndExceptionBlock()
        emit.RegionDepth = emit.RegionDepth - 1
        emit.HoistedDepth = emit.HoistedDepth - 1
    }

    // The rows after a hoisted handler: re-raise what the region parked, then take the exit it
    // recorded. Both tests are field reads because both fields had to survive a suspension inside the
    // handler itself.
    static func AppendHoistedHandlerTail(emit: ColumnarMoveNextEmit, pendingName: string, branchName: string) {
        noPending := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, pendingName))
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), noPending)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, pendingName))
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), emit.Plan.AddMethod(ExceptionDispatchInfoThrowMethod()))
        emit.Plan.AppendMarkLabel(noPending)

        noBranch := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, branchName))
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), noBranch)
        AppendBodyExit(emit, emit.EndLabel)
        emit.Plan.AppendMarkLabel(noBranch)
    }

    // One `catch` handler. The runtime hands the exception on the stack; a state machine's bindings
    // are FIELDS, so it is parked in a plan local and stored into the hoisted slot classification
    // reserved for this clause — the clause's own variable when it names one, and a synthesized slot
    // otherwise, which is what gives a bare `catch` a typed handler at all.
    static func EmitCatchClause(emit: ColumnarMoveNextEmit, clause: int, ordinal: int, regionEnd: int, out fellThrough: bool): bool {
        fellThrough = false
        nodes := emit.Context.Nodes
        if nodes.Kind(clause) != 50 || nodes.ChildCount(clause) < 1 {
            emit.Context.Decline("emit.iterator.unsupported-shape", "unsupported catch clause in an iterator body")
            return false
        }
        name := ColumnarIteratorPlanner.CatchBindingName(nodes, emit.Context.Source, clause, ordinal)
        field := emit.Context.FieldForName(name)
        exceptionType := field.get_FieldType()
        typeIdx := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(exceptionType), emit.Context.StructuralTypeReferences)
        emit.Plan.AppendBeginCatchBlock(typeIdx)
        caught := emit.Plan.DeclarePlanLocal(typeIdx)
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), caught)
        LoadThis(emit)
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), caught)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), emit.Plan.AddField(field))

        emit.CatchHandlerDepth = emit.CatchHandlerDepth + 1
        fell := EmitStatement(emit, nodes.Child(clause, nodes.ChildCount(clause) - 1))
        emit.CatchHandlerDepth = emit.CatchHandlerDepth - 1
        if emit.Context.Declined {
            return false
        }
        if fell {
            AppendBodyExit(emit, regionEnd)
        }
        fellThrough = fell
        return true
    }

    // `target = value` / `target op= value` where the target is a hoisted binding. The plain form is a
    // store; the compound form reads the field, applies the binary operator's own opcode selection for
    // the field's exact type, and stores back — the single arithmetic owner chooses the instruction.
    static func EmitAssignment(emit: ColumnarMoveNextEmit, node: int): bool {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        target := nodes.Child(node, 0)
        if nodes.Kind(target) != 6 {
            return EmitStoreTargetAssignment(emit, node, target)
        }
        name := nodes.Text(source, target)
        if !emit.Context.HasHoistedField(name) {
            return EmitEnclosingMemberAssignment(emit, node, name)
        }
        fieldType := emit.Context.FieldForName(name).get_FieldType()
        assignOperator := nodes.Text(source, node)
        if emit.Context.IsLoopCaptured(name) {
            boxField: FieldInfo? = null
            if !emit.Context.TryEnsureLoopCaptureBox(name, fieldType, out boxField) || boxField == null {
                return false
            }
            boxPool := emit.Plan.AddField(boxField)
            valuePool := emit.Plan.AddField(StrongBoxValueField(boxField.get_FieldType()))
            if assignOperator == "=" || assignOperator.Length == 0 {
                LoadThis(emit)
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), boxPool)
                if !AppendStoredValue(emit, nodes.Child(node, 1), fieldType) {
                    return false
                }
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), valuePool)
                return true
            }
            if assignOperator.Length != 2 || assignOperator[1] != '=' {
                emit.Context.Decline("emit.iterator.unsupported-shape", "the assignment operator '" + assignOperator + "' is not yet lowered in an iterator body")
                return false
            }
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), boxPool)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), boxPool)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), valuePool)
            if !AppendStoredValue(emit, nodes.Child(node, 1), fieldType) {
                return false
            }
            resultType := typeof(int)
            if !ColumnarPrimitiveBinaryPlanner.TryAppendArithmeticOperator(assignOperator.Substring(0, 1), fieldType, emit.Context.RequiredScope().Bindings, emit.Plan, out resultType) || resultType != fieldType {
                emit.Context.Decline("emit.iterator.unsupported-shape", "a compound assignment of '" + fieldType.Name + "' with '" + assignOperator + "' is not yet lowered in an iterator body")
                return false
            }
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), valuePool)
            return true
        }
        fieldPool := FieldPool(emit, name)
        if assignOperator == "=" || assignOperator.Length == 0 {
            return AppendBoundFieldStore(emit, nodes.Child(node, 1), fieldPool, fieldType)
        }
        if assignOperator.Length != 2 || assignOperator[1] != '=' {
            emit.Context.Decline("emit.iterator.unsupported-shape", "the assignment operator '" + assignOperator + "' is not yet lowered in an iterator body")
            return false
        }
        binaryOperator := assignOperator.Substring(0, 1)
        LoadThis(emit)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldPool)
        if !AppendStoredValue(emit, nodes.Child(node, 1), fieldType) {
            return false
        }
        resultType := typeof(int)
        if !ColumnarPrimitiveBinaryPlanner.TryAppendArithmeticOperator(binaryOperator, fieldType, emit.Context.RequiredScope().Bindings, emit.Plan, out resultType) || resultType != fieldType {
            emit.Context.Decline("emit.iterator.unsupported-shape", "a compound assignment of '" + fieldType.Name + "' with '" + assignOperator + "' is not yet lowered in an iterator body")
            return false
        }
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), fieldPool)
        return true
    }

    // `member = value` FROM AN INSTANCE GENERATOR, where `member` is a field of the enclosing type.
    // The machine captured its receiver as `<>__this`, so the store is the same two-hop write a
    // closure performs through the display it captured: `ldarg.0; ldfld <>__this; <value>; stfld`. The
    // READ of the same name is already the two-hop load the body scope publishes, so a write and a
    // read of one member now agree about where it lives.
    static func EmitEnclosingMemberAssignment(emit: ColumnarMoveNextEmit, node: int, name: string): bool {
        nodes := emit.Context.Nodes
        index := emit.Context.EnclosingFieldIndex(name)
        if index < 0 || !emit.Context.HasHoistedField("<>__this") {
            emit.Context.Decline("emit.iterator.unsupported-shape", "assignment to an unbound identifier '" + name + "'")
            return false
        }

        assignOperator := nodes.Text(emit.Context.Source, node)
        memberField := emit.Context.EnclosingFields[index]
        fieldType := memberField.get_FieldType()
        if memberField.get_IsInitOnly() || memberField.get_IsLiteral() {
            emit.Context.Decline("emit.iterator.unsupported-shape", "'" + name + "' is read-only and cannot be assigned")
            return false
        }

        receiverPool := FieldPool(emit, "<>__this")
        memberPool := emit.Plan.AddField(memberField)
        if assignOperator.Length != 0 && assignOperator != "=" {
            if assignOperator.Length != 2 || assignOperator[1] != '=' {
                emit.Context.Decline("emit.iterator.unsupported-shape", "the assignment operator '" + assignOperator + "' is not yet lowered in an iterator body")
                return false
            }
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), receiverPool)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), receiverPool)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), memberPool)
            if !AppendStoredValue(emit, nodes.Child(node, 1), fieldType) {
                return false
            }
            resultType := typeof(int)
            if !ColumnarPrimitiveBinaryPlanner.TryAppendArithmeticOperator(assignOperator.Substring(0, 1), fieldType, emit.Context.RequiredScope().Bindings, emit.Plan, out resultType) || resultType != fieldType {
                emit.Context.Decline("emit.iterator.unsupported-shape", "a compound assignment of '" + fieldType.Name + "' with '" + assignOperator + "' is not yet lowered in an iterator body")
                return false
            }
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), memberPool)
            return true
        }

        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), receiverPool)
        if !AppendStoredValue(emit, nodes.Child(node, 1), fieldType) {
            return false
        }
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), memberPool)
        return true
    }

    // `receiver.Member = value` / `receiver[index] = value` INSIDE A GENERATOR. The store is planned by
    // the one store owner against the machine's own bindings, so the member a name selects, the
    // `set_Item` an index list selects and the conversion the stored value takes are all the same
    // answers the identical statement gets in a plain function body. Only `=` reaches here: a compound
    // form would evaluate the receiver twice, and this owner does not yet hold the single-evaluation
    // temporaries that requires.
    static func EmitStoreTargetAssignment(emit: ColumnarMoveNextEmit, node: int, target: int): bool {
        nodes := emit.Context.Nodes
        assignOperator := nodes.Text(emit.Context.Source, node)
        if assignOperator.Length != 0 && assignOperator != "=" {
            emit.Context.Decline("emit.iterator.unsupported-shape", "a compound assignment to a member or an indexer is not yet lowered in an iterator body")
            return false
        }

        declineReason := ""
        if !ColumnarStoreTargetPlanner.TryAppendStore(nodes, emit.Context.Source, target, nodes.Child(node, 1), emit.Context.RequiredScope().Bindings, emit.Plan, out declineReason) {
            emit.Context.Decline("emit.iterator.unsupported-shape", declineReason)
            return false
        }
        return true
    }

    // THE ONE `for..in` EMISSION, for both spellings. A hoisted ARRAY identifier takes the index loop
    // over its own length; every other source takes the hoisted-enumerator loop. Which spelling was
    // written changes nothing here except the type the element is stored at, which the loop
    // variable's own field already records.
    static func EmitForIn(emit: ColumnarMoveNextEmit, sourceNode: int, bodyNode: int, varName: string): bool {
        nodes := emit.Context.Nodes
        if nodes.Kind(sourceNode) != 6 {
            return EmitEnumerableForIn(emit, sourceNode, bodyNode, varName)
        }
        sourceName := nodes.Text(emit.Context.Source, sourceNode)
        if !emit.Context.HasHoistedField(sourceName) {
            return EmitEnumerableForIn(emit, sourceNode, bodyNode, varName)
        }
        // THE SAME TEST THE WALK MADE. Classification hoists an `<>__index{k}` slot only for an
        // array element the index loop can load, so the emission has to ask the identical question:
        // an array of any other element goes through its enumerator, exactly as the walk assumed.
        arrayElement := ColumnarIteratorPlanner.ArrayElementCanonicalOf(emit.Context.FieldCanonicalForName(sourceName))
        if arrayElement == "" || !ColumnarIteratorPlanner.IsLowerableArrayElementCanonical(arrayElement) {
            return EmitEnumerableForIn(emit, sourceNode, bodyNode, varName)
        }
        return EmitArrayForIn(emit, sourceName, bodyNode, varName)
    }

    // THE TYPE THE LOOP VARIABLE IS STORED AT, and the conversion the element takes to reach it. An
    // INFERRED variable's field is defined here from the element type, so there is no conversion; an
    // ANNOTATED one's field was already defined from the type the author wrote, and the element
    // converts to it the way a cast does — a downcast out of `object`, an unboxing, or a numeric
    // conversion. A conversion that does not exist is the loop's own decline, and the analyzer has
    // already reported NL330 for the same pair.
    static func TryResolveLoopVariableStorage(emit: ColumnarMoveNextEmit, varName: string, elementType: Type, out storageType: Type): bool {
        storageType = elementType
        loopField: FieldInfo? = null
        if emit.Context.TryEnsureHoistedField(varName, elementType, out loopField) {
            return true
        }
        if !emit.Context.HasHoistedField(varName) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "the `for..in` element '" + varName + "' could not be hoisted as '" + elementType.Name + "'")
            return false
        }
        declared := emit.Context.FieldForName(varName).get_FieldType()
        if !ColumnarCastConversionPlanner.CanAppendCast(elementType, declared) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "a '" + elementType.Name + "' cannot be read as a '" + declared.Name + "' by the annotated loop variable '" + varName + "'")
            return false
        }
        storageType = declared
        return true
    }

    static func AppendLoopVariableConversion(emit: ColumnarMoveNextEmit, elementType: Type, storageType: Type): bool {
        if elementType == storageType {
            return true
        }
        if !ColumnarCastConversionPlanner.TryAppendCast(emit.Plan, elementType, storageType, emit.Context.StructuralTypeReferences) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "a '" + elementType.Name + "' cannot be read as a '" + storageType.Name + "'")
            return false
        }
        return true
    }

    // for..in over a hoisted ARRAY field: the index loop over its own length, with the element load the
    // ordinary indexer owner emits.
    static func EmitArrayForIn(emit: ColumnarMoveNextEmit, sourceName: string, bodyNode: int, varName: string): bool {
        indexName := "<>__index" + emit.NextForIn.ToString()
        emit.NextForIn = emit.NextForIn + 1
        arrayPool := FieldPool(emit, sourceName)
        indexPool := FieldPool(emit, indexName)
        arrayType := emit.Context.FieldForName(sourceName).get_FieldType()
        elementType: Type = arrayType.GetElementType()
        storageType := elementType
        if !TryResolveLoopVariableStorage(emit, varName, elementType, out storageType) {
            return false
        }
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
        ColumnarRangeIndexPlanner.AppendArrayElementLoad(emit.Plan, elementType)
        if !AppendLoopVariableConversion(emit, elementType, storageType) {
            return false
        }
        if emit.Context.IsLoopCaptured(varName) {
            if !AppendFreshLoopCaptureBoxFromStack(emit, varName, storageType) {
                return false
            }
        } else {
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, varName))
        }
        // A `continue` targets the index step, so the next element is read rather than the same one.
        stepLabel := emit.Plan.DefineLabel()
        emit.PushLoop(stepLabel, afterLabel, true)
        bodyFalls := EmitStatement(emit, bodyNode)
        continued := emit.PopLoop()
        if bodyFalls || continued {
            // index = index + 1
            emit.Plan.AppendMarkLabel(stepLabel)
            LoadThis(emit)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), indexPool)
            EmitInt(emit, 1)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Add())
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), indexPool)
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
        }
        if emit.Context.Declined {
            return false
        }
        emit.Plan.AppendMarkLabel(afterLabel)
        return true
    }

    // for..in over ANY sequence source: the hoisted-enumerator loop inside the guarded region. The
    // source is an ordinary expression planned by the one expression owner; its CLR type is what names
    // the `IEnumerable<T>` the loop enumerates. `this.enumK = <source>.GetEnumerator()`, then
    // MoveNext/get_Current callvirts; the loop's normal exit disposes and nulls the enumerator inline
    // (the fault handler and Dispose() cover the exceptional and suspended-abandonment paths).
    // `await foreach` INSIDE AN ASYNC GENERATOR — two machines composed, and the composition is the
    // hoisted-handler region:
    //
    //     this.<>__aenum{k} = <source>.GetAsyncEnumerator(default)
    //     try   { <dispatch> while (await this.<>__aenum{k}.MoveNextAsync()) { x = …Current; <body> } }
    //     catch (Exception e) { this.<>__pending{k} = ExceptionDispatchInfo.Capture(e) }
    //     end:  if (this.<>__aenum{k} != null) { await this.<>__aenum{k}.DisposeAsync(); …= null }
    //           <re-raise the parked exception / take the recorded exit>
    //
    // The enumerator is acquired BEFORE the region entry label so a resume never acquires a second
    // one, and it is released by the hoisted handler on all three paths the language promises — the
    // loop's normal exit, an exception passing through the body, and a consumer that abandons the
    // OUTER enumeration (whose `DisposeAsync` drives this machine's unwind through this very
    // handler). It is deliberately NOT a `<>__enum{k}` slot: those are released by the machine's
    // blanket synchronous disposal, which is the wrong release for an `IAsyncDisposable`.
    static func EmitAwaitForIn(emit: ColumnarMoveNextEmit, sourceNode: int, bodyNode: int, varName: string): bool {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        enumName := ColumnarIteratorPlanner.AsyncEnumeratorFieldName(emit.NextAsyncEnumerator)
        emit.NextAsyncEnumerator = emit.NextAsyncEnumerator + 1

        sourceType := typeof(int)
        if !emit.Context.RequiredScope().TryDiscoverValueType(nodes, source, sourceNode, out sourceType) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "the `await foreach` source could not be lowered in an iterator body")
            return false
        }
        elementType: Type? = null
        if !TryGetAsyncSequenceElementType(sourceType, out elementType) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "`await foreach` over '" + sourceType.Name + "' is not an async sequence an iterator body can enumerate")
            return false
        }
        enumeratorType := AsyncEnumeratorInterfaceTypeOf(elementType)
        enumeratorField: FieldInfo? = null
        if !emit.Context.TryEnsureHoistedField(enumName, enumeratorType, out enumeratorField) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "the `await foreach` enumerator over '" + elementType.Name + "' could not be hoisted")
            return false
        }
        storageType := elementType
        if !TryResolveLoopVariableStorage(emit, varName, elementType, out storageType) {
            return false
        }

        enumPool := FieldPool(emit, enumName)
        getAsyncEnumeratorPool := emit.Plan.AddMethod(AsyncSequenceGetAsyncEnumerator(elementType))
        moveNextAsyncPool := emit.Plan.AddMethod(AsyncEnumeratorMoveNextAsyncMethod(elementType))
        currentPool := emit.Plan.AddMethod(AsyncEnumeratorCurrentGetter(elementType))

        // this.aenum = <source>.GetAsyncEnumerator(default)
        LoadThis(emit)
        sequenceType := typeof(int)
        if !AppendValue(emit, sourceNode, out sequenceType) {
            return false
        }
        tokenType := CancellationTokenRuntimeType()
        tokenTypeIdx := emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(tokenType), emit.Context.StructuralTypeReferences)
        tokenLocal := emit.Plan.DeclarePlanLocal(tokenTypeIdx)
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), tokenLocal)
        emit.Plan.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), tokenTypeIdx)
        emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloc(), tokenLocal)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), getAsyncEnumeratorPool)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), enumPool)

        region := emit.NextTryRegion
        emit.NextTryRegion = emit.NextTryRegion + 1
        pendingName := ColumnarIteratorPlanner.PendingExceptionFieldName(region)
        branchName := ColumnarIteratorPlanner.PendingBranchFieldName(region)
        if !BeginHoistedHandlerRegion(emit, region, pendingName, branchName) {
            return false
        }

        condLabel := emit.Plan.DefineLabel()
        afterLabel := emit.Plan.DefineLabel()
        emit.Plan.AppendMarkLabel(condLabel)
        LoadThis(emit)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), enumPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), moveNextAsyncPool)
        movedType := VoidReturnType()
        if !AppendAwaitOfStackValue(emit, ValueTaskOfBoolRuntimeType(), out movedType) {
            return false
        }
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), afterLabel)
        LoadThis(emit)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), enumPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), currentPool)
        if !AppendLoopVariableConversion(emit, elementType, storageType) {
            return false
        }
        if emit.Context.IsLoopCaptured(varName) {
            if !AppendFreshLoopCaptureBoxFromStack(emit, varName, storageType) {
                return false
            }
        } else {
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, varName))
        }
        // THE FRAME IS PUSHED EVEN THOUGH IT CANNOT BE BRANCHED TO. This loop's exit label stands
        // INSIDE its hoisted-handler region, so a `break` cannot simply leave to it — the handler
        // past the region end has to run on the way out and this branch does not record that hop.
        // The frame is opened anyway, marked not-lowerable, so a `break` written in this body
        // declines by name rather than silently retargeting the NEXT loop out, which is a different
        // program.
        emit.PushLoop(condLabel, afterLabel, false)
        bodyFalls := EmitStatement(emit, bodyNode)
        emit.PopLoop()
        if bodyFalls {
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
        }
        if emit.Context.Declined {
            return false
        }
        emit.Plan.AppendMarkLabel(afterLabel)

        EndHoistedHandlerRegion(emit, true, pendingName)
        emit.HoistedHandlerDepth = emit.HoistedHandlerDepth + 1
        AppendAsyncEnumeratorRelease(emit, enumPool, enumeratorType)
        emit.HoistedHandlerDepth = emit.HoistedHandlerDepth - 1
        if emit.Context.Declined {
            return false
        }

        AppendHoistedHandlerTail(emit, pendingName, branchName)
        return !emit.Context.Declined
    }

    // The hoisted handler's body: release the enumerator and clear the slot, so a second pass through
    // the handler (an abandoned machine unwinding a loop that already exited) releases nothing twice.
    static func AppendAsyncEnumeratorRelease(emit: ColumnarMoveNextEmit, enumPool: int, enumeratorType: Type) {
        skipLabel := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), enumPool)
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), skipLabel)
        LoadThis(emit)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), enumPool)
        emit.Plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), emit.Plan.AddMethod(AsyncDisposableDisposeAsyncMethod()))
        AppendDiscardedAwait(emit, ValueTaskRuntimeType())
        if emit.Context.Declined {
            return
        }
        LoadThis(emit)
        emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), enumPool)
        emit.Plan.AppendMarkLabel(skipLabel)
    }

    static func EmitEnumerableForIn(emit: ColumnarMoveNextEmit, sourceNode: int, bodyNode: int, varName: string): bool {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        enumName := "<>__enum" + emit.NextEnumerator.ToString()
        emit.NextEnumerator = emit.NextEnumerator + 1

        sourceType := typeof(int)
        if !emit.Context.RequiredScope().TryDiscoverValueType(nodes, source, sourceNode, out sourceType) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "the `for..in` source could not be lowered in an iterator body")
            return false
        }
        elementType: Type? = null
        if !TryGetSequenceElementType(sourceType, out elementType) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "`for..in` over '" + sourceType.Name + "' is not a sequence an iterator body can enumerate")
            return false
        }
        enumeratorType := EnumeratorInterfaceTypeOf(elementType)
        enumeratorField: FieldInfo? = null
        if !emit.Context.TryEnsureHoistedField(enumName, enumeratorType, out enumeratorField) {
            emit.Context.Decline("emit.iterator.for-in-unsupported", "the `for..in` enumerator over '" + elementType.Name + "' could not be hoisted")
            return false
        }
        storageType := elementType
        if !TryResolveLoopVariableStorage(emit, varName, elementType, out storageType) {
            return false
        }

        enumPool := FieldPool(emit, enumName)
        getEnumeratorPool := AddSequenceGetEnumerator(emit, elementType)
        moveNextPool := emit.Plan.AddMethod(EnumeratorMoveNextMethod())
        currentPool := AddSequenceCurrentGetter(emit, elementType)
        disposePool := emit.Plan.AddMethod(DisposableDisposeMethod())
        // this.enum = <source>.GetEnumerator()
        LoadThis(emit)
        sequenceType := typeof(int)
        if !AppendValue(emit, sourceNode, out sequenceType) {
            return false
        }
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
        if !AppendLoopVariableConversion(emit, elementType, storageType) {
            return false
        }
        if emit.Context.IsLoopCaptured(varName) {
            if !AppendFreshLoopCaptureBoxFromStack(emit, varName, storageType) {
                return false
            }
        } else {
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), FieldPool(emit, varName))
        }
        // There is no step to run, so `continue` targets the MoveNext condition. `break` targets the
        // label the enumerator is disposed at, which is what makes an early exit release it.
        emit.PushLoop(condLabel, afterLabel, true)
        bodyFalls := EmitStatement(emit, bodyNode)
        emit.PopLoop()
        if bodyFalls {
            emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Br(), condLabel)
        }
        if emit.Context.Declined {
            return false
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

    // THE ELEMENT OF AN ENUMERATED SOURCE, FROM THE SOURCE'S OWN CLR TYPE. A single-dimensional array
    // enumerates its element (arrays implement `IEnumerable<T>` for their element type); a type that IS
    // a constructed `IEnumerable<T>` enumerates `T`; a baked type that IMPLEMENTS exactly one
    // `IEnumerable<T>` enumerates that one. A type with two different `IEnumerable<T>` implementations
    // has no single answer and is refused rather than guessed.
    static func TryGetSequenceElementType(sourceType: Type, out elementType: Type): bool {
        elementType = null
        if sourceType == null || sourceType.get_IsByRef() || sourceType.get_IsPointer() {
            return false
        }
        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(sourceType) {
            elementType = sourceType.GetElementType()
            return elementType != null
        }
        if IsConstructedEnumerable(sourceType) {
            elementType = sourceType.GetGenericArguments()[0]
            return true
        }
        if sourceType.get_IsGenericParameter() {
            return false
        }
        // A CLOSED GENERIC ASKS ITS DEFINITION, NOT ITSELF. `List<TreeNode>` over an emitted type is a
        // generic instantiation whose `GetInterfaces()` throws under persisted emit, but its DEFINITION
        // (`List<>`) is a baked runtime type whose interface list is readable; the element is then the
        // instantiation's own argument at the position the definition's `IEnumerable<T>` names.
        if sourceType.get_IsGenericType() && !sourceType.get_IsGenericTypeDefinition() {
            definition := sourceType.GetGenericTypeDefinition()
            arguments := sourceType.GetGenericArguments()
            if definition != null && !(definition is TypeBuilder) {
                return TryGetEnumerableInterfaceElement(definition.GetInterfaces(), arguments, out elementType)
            }
            return false
        }
        if sourceType is TypeBuilder {
            return false
        }
        return TryGetEnumerableInterfaceElement(sourceType.GetInterfaces(), new Type[](0), out elementType)
    }

    // The single `IEnumerable<T>` an interface list names, with a definition's type PARAMETER mapped
    // back through the instantiation's arguments when one is supplied. Two different `IEnumerable<T>`
    // implementations have no single answer and are refused rather than guessed.
    static func TryGetEnumerableInterfaceElement(interfaces: Type[], arguments: Type[], out elementType: Type): bool {
        elementType = null
        found: Type? = null
        for candidate in interfaces {
            if !IsConstructedEnumerable(candidate) {
                continue
            }
            argument := candidate.GetGenericArguments()[0]
            if argument.get_IsGenericParameter() {
                position := argument.get_GenericParameterPosition()
                if position < 0 || position >= arguments.Length {
                    return false
                }
                argument = arguments[position]
            }
            if found != null && found != argument {
                return false
            }
            found = argument
        }
        if found == null {
            return false
        }
        elementType = found
        return true
    }

    static func IsConstructedEnumerable(candidate: Type): bool {
        if !candidate.get_IsGenericType() || candidate.get_IsGenericTypeDefinition() {
            return false
        }
        definition := candidate.GetGenericTypeDefinition()
        return definition.FullName == "System.Collections.Generic.IEnumerable`1"
    }

    static func IsBuilderBoundElement(elementType: Type): bool {
        return elementType is TypeBuilder || elementType is EnumBuilder || elementType.get_IsGenericParameter()
    }

    // GetEnumerator on IEnumerable<element>: a runtime handle for baked elements, a
    // TypeBuilder.GetMethod rebinding (with the declared signature) for builder-bound elements.
    static func AddSequenceGetEnumerator(emit: ColumnarMoveNextEmit, elementType: Type): int {
        enumerableType := EnumerableInterfaceTypeOf(elementType)
        if IsBuilderBoundElement(elementType) {
            handle := TypeBuilder.GetMethod(enumerableType, OpenSequenceMethod("System.Collections.Generic.IEnumerable`1", "GetEnumerator"))
            noParams := new Type[](0)
            return emit.Plan.AddMethodWithSignature(handle, enumerableType, noParams, EnumeratorInterfaceTypeOf(elementType), false, true)
        }
        method := enumerableType.GetMethod("GetEnumerator")
        if method == null {
            throw new InvalidOperationException("IEnumerable<" + elementType.Name + ">.GetEnumerator was not found.")
        }
        return emit.Plan.AddMethod(method)
    }

    static func AddSequenceCurrentGetter(emit: ColumnarMoveNextEmit, elementType: Type): int {
        enumeratorType := EnumeratorInterfaceTypeOf(elementType)
        if IsBuilderBoundElement(elementType) {
            handle := TypeBuilder.GetMethod(enumeratorType, OpenSequenceMethod("System.Collections.Generic.IEnumerator`1", "get_Current"))
            noParams := new Type[](0)
            return emit.Plan.AddMethodWithSignature(handle, enumeratorType, noParams, elementType, false, true)
        }
        getter := enumeratorType.GetMethod("get_Current")
        if getter == null {
            throw new InvalidOperationException("IEnumerator<" + elementType.Name + ">.get_Current was not found.")
        }
        return emit.Plan.AddMethod(getter)
    }

    // THE ELEMENT OF AN ASYNC SEQUENCE. `await foreach` has no pattern arm and no array arm: N#
    // resolves an async sequence through `IAsyncEnumerable<T>` and nothing else, which is the rule
    // the analyzer states at the front door and this only follows.
    static func TryGetAsyncSequenceElementType(sourceType: Type, out elementType: Type): bool {
        elementType = typeof(object)
        if sourceType == null {
            return false
        }
        if IsConstructedAsyncEnumerable(sourceType) {
            elementType = sourceType.GetGenericArguments()[0]
            return true
        }
        interfaces := sourceType.GetInterfaces()
        found: Type? = null
        i := 0
        while i < interfaces.Length {
            candidate := interfaces[i]
            if IsConstructedAsyncEnumerable(candidate) {
                argument := candidate.GetGenericArguments()[0]
                if found != null && found != argument {
                    return false
                }
                found = argument
            }
            i = i + 1
        }
        if found == null {
            return false
        }
        elementType = found
        return true
    }

    static func IsConstructedAsyncEnumerable(candidate: Type): bool {
        return candidate != null && candidate.get_IsGenericType() && !candidate.get_IsGenericTypeDefinition() && candidate.GetGenericTypeDefinition().FullName == "System.Collections.Generic.IAsyncEnumerable`1"
    }

    static func AsyncSequenceGetAsyncEnumerator(elementType: Type): MethodInfo {
        enumerableType := AsyncEnumerableInterfaceTypeOf(elementType)
        method := enumerableType.GetMethod("GetAsyncEnumerator")
        if method == null {
            throw new InvalidOperationException("IAsyncEnumerable<" + elementType.Name + ">.GetAsyncEnumerator was not found.")
        }
        return method
    }

    static func AsyncEnumeratorMoveNextAsyncMethod(elementType: Type): MethodInfo {
        enumeratorType := AsyncEnumeratorInterfaceTypeOf(elementType)
        method := enumeratorType.GetMethod("MoveNextAsync")
        if method == null {
            throw new InvalidOperationException("IAsyncEnumerator<" + elementType.Name + ">.MoveNextAsync was not found.")
        }
        return method
    }

    static func AsyncEnumeratorCurrentGetter(elementType: Type): MethodInfo {
        enumeratorType := AsyncEnumeratorInterfaceTypeOf(elementType)
        getter := enumeratorType.GetMethod("get_Current")
        if getter == null {
            throw new InvalidOperationException("IAsyncEnumerator<" + elementType.Name + ">.get_Current was not found.")
        }
        return getter
    }

    static func AsyncDisposableDisposeAsyncMethod(): MethodInfo {
        return RequiredMethodOf(RequiredRuntimeType("System.IAsyncDisposable"), "DisposeAsync")
    }

    static func CancellationTokenRuntimeType(): Type {
        return RequiredRuntimeType("System.Threading.CancellationToken")
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

    static func ExceptionDispatchInfoRuntimeType(): Type {
        return RequiredRuntimeType("System.Runtime.ExceptionServices.ExceptionDispatchInfo")
    }

    static func ExceptionDispatchInfoCaptureMethod(): MethodInfo {
        captureTypes := new Type[](1)
        captureTypes[0] = ExceptionRuntimeType()
        method := ExceptionDispatchInfoRuntimeType().GetMethod("Capture", captureTypes)
        if method == null {
            throw new InvalidOperationException("ExceptionDispatchInfo.Capture(Exception) was not found.")
        }
        return method
    }

    static func ExceptionDispatchInfoThrowMethod(): MethodInfo {
        noTypes := new Type[](0)
        method := ExceptionDispatchInfoRuntimeType().GetMethod("Throw", noTypes)
        if method == null {
            throw new InvalidOperationException("ExceptionDispatchInfo.Throw() was not found.")
        }
        return method
    }

    static func ExceptionRuntimeType(): Type {
        return RequiredRuntimeType("System.Exception")
    }
    static func TaskAwaiterRuntimeType(): Type {
        return RequiredRuntimeType("System.Runtime.CompilerServices.TaskAwaiter")
    }
    static func ValueTaskRuntimeType(): Type {
        return RequiredRuntimeType("System.Threading.Tasks.ValueTask")
    }
    static func ValueTaskOfBoolRuntimeType(): Type {
        return BoolClosedRuntimeType("System.Threading.Tasks.ValueTask`1")
    }
    static func PromiseRuntimeType(): Type {
        return BoolClosedRuntimeType("System.Threading.Tasks.TaskCompletionSource`1")
    }

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

    static func AwaiterIsCompletedGetter(): MethodInfo {
        return RequiredMethodOf(TaskAwaiterRuntimeType(), "get_IsCompleted")
    }
    static func AwaiterGetResultMethod(): MethodInfo {
        return RequiredMethodOf(TaskAwaiterRuntimeType(), "GetResult")
    }
    static func AwaiterOnCompletedMethod(): MethodInfo {
        return RequiredMethodOf(TaskAwaiterRuntimeType(), "OnCompleted")
    }
    static func PromiseSetResultMethod(): MethodInfo {
        return RequiredMethodOf(PromiseRuntimeType(), "SetResult")
    }
    static func PromiseTaskGetter(): MethodInfo {
        return RequiredMethodOf(PromiseRuntimeType(), "get_Task")
    }

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

    static func ValueTaskFromTaskConstructor(): ConstructorInfo {
        ctorTypes := new Type[](1)
        ctorTypes[0] = RequiredRuntimeType("System.Threading.Tasks.Task")
        ctor := ValueTaskRuntimeType().GetConstructor(ctorTypes)
        if ctor == null {
            throw new InvalidOperationException("ValueTask(Task) was not found.")
        }
        return ctor
    }

    // TaskCreationOptions.RunContinuationsAsynchronously: promise completions schedule the consumer's
    // continuation instead of running it inline inside the step frame.
    static func RunContinuationsAsynchronouslyFlag(): int {
        return 64
    }

    static func EmitYieldReturn(emit: ColumnarMoveNextEmit, valueNode: int) {
        if emit.IsAsync {
            EmitAsyncYieldReturn(emit, valueNode)
            return
        }
        emit.NextYield = emit.NextYield + 1
        resumeState := emit.NextYield
        currentPool := FieldPool(emit, "<>__current")
        LoadThis(emit)
        if !AppendStoredValue(emit, valueNode, emit.Context.ElementType) {
            return
        }
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), currentPool)
        StoreState(emit, resumeState)
        EmitInt(emit, 1)
        if emit.RegionMode {
            // Suspension inside a protected region: stash the result and branch to the ret outside
            // every region. A `leave` never runs a FAULT handler, so live enumerators survive the
            // suspension; a `finally` the suspension leaves behind is skipped by its own state guard,
            // because the resume state this just stored is not negative.
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), emit.ResultLocal)
            AppendMethodExit(emit, emit.RegionEndLabel)
        } else {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        }
        emit.Plan.AppendMarkLabel(emit.ResumeLabels[resumeState])
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
        AppendDisposeModeExit(emit, resumeState)
    }

    // THE ABANDONMENT PATH. A machine that suspended inside a `try` is resumed by `Dispose` with the
    // dispose flag set: it marks itself running (so every state-guarded `finally` will fire) and
    // branches straight to the end label, which crosses out of every region it was standing in and
    // makes the runtime run each `finally` on the way, innermost first. A resume point in
    // unprotected code has nothing to unwind and carries no check at all.
    static func AppendDisposeModeExit(emit: ColumnarMoveNextEmit, resumeState: int) {
        // A SUSPENSION INSIDE A HOISTED HANDLER IS ALREADY UNWINDING. The handler stands outside the
        // region it releases, so it lives in the ENCLOSING region and its resume state has that
        // region as its home — which would arm the abandonment branch and jump out of the very
        // handler the abandonment exists to run, losing the rest of the release. An awaiting
        // `finally` nested inside a plain one is the shape that measured it: abandoning there
        // observed the outer handler and never the inner one.
        if emit.HoistedHandlerDepth > 0 {
            return
        }
        if emit.Context.Shape.ResumeRegionOf(resumeState) < 0 || !emit.Context.HasHoistedField(ColumnarIteratorPlanner.DisposeModeFieldName()) {
            return
        }
        continueLabel := emit.Plan.DefineLabel()
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, ColumnarIteratorPlanner.DisposeModeFieldName()))
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Brfalse(), continueLabel)
        AppendBodyExit(emit, emit.EndLabel)
        emit.Plan.AppendMarkLabel(continueLabel)
    }

    // Async `yield return`: store current, set the yield-resume state (the SHARED resume counter),
    // complete the pending call with true, and leave the region; the next drive resumes past it.
    static func EmitAsyncYieldReturn(emit: ColumnarMoveNextEmit, valueNode: int) {
        emit.NextResume = emit.NextResume + 1
        resumeState := emit.NextResume
        if !AppendBoundFieldStore(emit, valueNode, FieldPool(emit, "<>__current"), emit.Context.ElementType) {
            return
        }
        StoreState(emit, resumeState)
        EmitAsyncComplete(emit, 1)
        emit.Plan.AppendMarkLabel(emit.ResumeLabels[resumeState])
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
        AppendDisposeModeExit(emit, resumeState)
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

    // A SUSPENSION POINT, FOR ANY AWAITABLE. The operand is an ordinary expression planned by the one
    // expression owner; the awaitable PATTERN is then asked of whatever type it produced — the same
    // four members C# asks for, resolved by ordinary CLR member lookup rather than from a table of
    // known tasks:
    //
    //     this.<>__awaiterK = <operand>.GetAwaiter()
    //     if (awaiter.IsCompleted) goto fast
    //     state = <resume>; ensure the promise; awaiter.OnCompleted(this.<>__continuation); leave
    //   resume:
    //     state = running
    //   fast:
    //     <result> = awaiter.GetResult(); reset the awaiter slot
    //
    // The promise is created with RunContinuationsAsynchronously so a completion never re-enters this
    // frame. `resultType` is what `GetResult()` returned — `System.Void` for a unit await, and the
    // awaited value for a bound one, which is left on the stack for the statement that binds it.
    static func AppendAwait(emit: ColumnarMoveNextEmit, awaitNode: int, out resultType: Type): bool {
        resultType = VoidReturnType()
        operand := emit.Context.Nodes.Child(awaitNode, 0)
        operandType := typeof(int)
        if !emit.Context.RequiredScope().TryDiscoverValueType(emit.Context.Nodes, emit.Context.Source, operand, out operandType) {
            emit.Context.Decline("emit.iterator.async-await-unsupported", "the awaited operand could not be lowered in an async iterator body")
            return false
        }

        LoadThis(emit)
        plannedOperandType := typeof(int)
        if !AppendValue(emit, operand, out plannedOperandType) {
            return false
        }

        return AppendAwaitOfStackValue(emit, operandType, out resultType)
    }

    // THE SUSPENSION ITSELF, over an awaitable ALREADY ON THE STACK. The rows above it are the
    // caller's: this owner's contract is that the plan holds `this` and then the awaitable value,
    // because the first thing a suspension does is store the awaiter into a field of the machine.
    //
    // Splitting the sequence here is what lets a SYNTHESIZED await — the `DisposeAsync()` an
    // `await using` owes its resource, the one an `await foreach` owes its enumerator — go through
    // exactly the same suspension as a written `await`, with no second copy of the awaitable pattern.
    static func AppendAwaitOfStackValue(emit: ColumnarMoveNextEmit, operandType: Type, out resultType: Type): bool {
        resultType = VoidReturnType()
        getAwaiter := ParameterlessMethodOrNull(operandType, "GetAwaiter")
        if getAwaiter == null {
            emit.Context.Decline("emit.iterator.async-await-unsupported", "'" + operandType.Name + "' is not awaitable: it has no `GetAwaiter()`")
            return false
        }
        awaiterType: Type = getAwaiter.get_ReturnType()
        isCompleted := ParameterlessMethodOrNull(awaiterType, "get_IsCompleted")
        getResult := ParameterlessMethodOrNull(awaiterType, "GetResult")
        onCompleted := ActionMethodOrNull(awaiterType, "OnCompleted")
        if isCompleted == null || getResult == null || onCompleted == null {
            emit.Context.Decline("emit.iterator.async-await-unsupported", "'" + awaiterType.Name + "' is not an awaiter: it needs `IsCompleted`, `OnCompleted(Action)` and `GetResult()`")
            return false
        }

        emit.NextResume = emit.NextResume + 1
        resumeState := emit.NextResume
        awaiterName := "<>__awaiter" + emit.NextAwait.ToString()
        emit.NextAwait = emit.NextAwait + 1
        awaiterField: FieldInfo? = null
        if !emit.Context.TryEnsureHoistedField(awaiterName, awaiterType, out awaiterField) {
            emit.Context.Decline("emit.iterator.async-await-unsupported", "the awaiter for '" + operandType.Name + "' could not be hoisted")
            return false
        }
        awPool := FieldPool(emit, awaiterName)
        promPool := FieldPool(emit, "<>__promise")
        byAddress := awaiterType.get_IsValueType()

        // this.<>__awaiterK = <operand>.GetAwaiter() — the receiver and the operand are already down.
        if operandType.get_IsValueType() {
            // An instance call on a STRUCT needs a managed pointer, and the operand is a value on the
            // stack; park it in a temporary and call through its address. The receiver of the store
            // (`this`) is already below it and is untouched.
            operandTemp := emit.Plan.DeclarePlanLocal(emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(operandType), emit.Context.StructuralTypeReferences))
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), operandTemp)
            emit.Plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Ldloca(), operandTemp)
        }
        emit.Plan.AppendMethodInstruction(InstanceCallOpcode(operandType), emit.Plan.AddMethod(getAwaiter))
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), awPool)

        fastLabel := emit.Plan.DefineLabel()
        havePromise := emit.Plan.DefineLabel()
        AppendAwaiterReceiver(emit, awPool, byAddress)
        emit.Plan.AppendMethodInstruction(AwaiterCallOpcode(byAddress), emit.Plan.AddMethod(isCompleted))
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
        AppendAwaiterReceiver(emit, awPool, byAddress)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), FieldPool(emit, "<>__continuation"))
        emit.Plan.AppendMethodInstruction(AwaiterCallOpcode(byAddress), emit.Plan.AddMethod(onCompleted))
        emit.Plan.AppendLabelInstruction(ColumnarCodePlanContract.Leave(), emit.RegionEndLabel)
        emit.Plan.AppendMarkLabel(emit.ResumeLabels[resumeState])
        StoreState(emit, ColumnarIteratorPlanner.RunningState())
        // A CONSUMER CAN ABANDON A MACHINE THAT IS SUSPENDED AT AN `await`, not only at a `yield`,
        // and when that suspension stands inside a protected region the handlers it is standing in
        // still have to run. The check goes BEFORE `GetResult()` on purpose: the unwind is not
        // interested in the awaited value, only in leaving every region on the way out.
        AppendDisposeModeExit(emit, resumeState)
        emit.Plan.AppendMarkLabel(fastLabel)
        AppendAwaiterReceiver(emit, awPool, byAddress)
        emit.Plan.AppendMethodInstruction(AwaiterCallOpcode(byAddress), emit.Plan.AddMethod(getResult))
        resultType = getResult.get_ReturnType()

        // Release whatever the awaiter held: a struct awaiter is re-initialized in place, a reference
        // one is nulled out, so a completed suspension never keeps its continuation state alive.
        if byAddress {
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldflda(), awPool)
            emit.Plan.AppendTypeInstruction(ColumnarCodePlanContract.Initobj(), emit.Plan.AddType(emit.Context.StructuralTypeReferences.SelectRuntimeType(awaiterType), emit.Context.StructuralTypeReferences))
        } else {
            LoadThis(emit)
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), awPool)
        }
        return true
    }

    // A statement-position `await <operand>`: the same suspension, with a result nothing binds.
    static func EmitUnitAwait(emit: ColumnarMoveNextEmit, awaitNode: int) {
        resultType := VoidReturnType()
        if !AppendAwait(emit, awaitNode, out resultType) {
            return
        }
        if !ColumnarCodePlanExecutor.IsVoidType(resultType) {
            emit.Plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Pop())
        }
    }

    // The awaiter as a CALL RECEIVER: a struct awaiter is called through the address of its own
    // field (a copy would throw the continuation state away); a reference awaiter is loaded.
    static func AppendAwaiterReceiver(emit: ColumnarMoveNextEmit, awaiterPool: int, byAddress: bool) {
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction((short)(byAddress ? ColumnarCodePlanContract.Ldflda() : ColumnarCodePlanContract.Ldfld()), awaiterPool)
    }

    static func AwaiterCallOpcode(byAddress: bool): short {
        return (short)(byAddress ? ColumnarCodePlanContract.Call() : ColumnarCodePlanContract.Callvirt())
    }

    static func InstanceCallOpcode(receiverType: Type): short {
        return (short)(receiverType.get_IsValueType() ? ColumnarCodePlanContract.Call() : ColumnarCodePlanContract.Callvirt())
    }

    // A public parameterless instance method, by ordinary CLR lookup. `null` when the type does not
    // have one, which is how "this is not awaitable" is discovered rather than asserted.
    static func ParameterlessMethodOrNull(owner: Type, name: string): MethodInfo? {
        if owner == null || owner.get_IsGenericParameter() {
            return null
        }
        return owner.GetMethod(name, BindingFlags.Public | BindingFlags.Instance, null, new Type[](0), null)
    }

    // A public instance method taking exactly one `System.Action`.
    static func ActionMethodOrNull(owner: Type, name: string): MethodInfo? {
        if owner == null || owner.get_IsGenericParameter() {
            return null
        }
        actionType := typeof(Action)
        parameters := new Type[](1)
        parameters[0] = actionType
        return owner.GetMethod(name, BindingFlags.Public | BindingFlags.Instance, null, parameters, null)
    }

    static func EmitPostfixStep(emit: ColumnarMoveNextEmit, node: int, keepValue: bool) {
        nodes := emit.Context.Nodes
        source := emit.Context.Source
        name := nodes.Text(source, nodes.Child(node, 0))
        fieldType := emit.Context.FieldForName(name).get_FieldType()
        if fieldType != typeof(int) {
            emit.Context.Decline("emit.iterator.unsupported-shape", "a postfix step over '" + name + "' of type '" + fieldType.Name + "' is not yet lowered in an iterator body")
            return
        }
        if emit.Context.IsLoopCaptured(name) {
            boxField: FieldInfo? = null
            if !emit.Context.TryEnsureLoopCaptureBox(name, fieldType, out boxField) || boxField == null {
                return
            }
            boxPool := emit.Plan.AddField(boxField)
            valuePool := emit.Plan.AddField(StrongBoxValueField(boxField.get_FieldType()))
            if keepValue {
                LoadThis(emit)
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), boxPool)
                emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), valuePool)
            }
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), boxPool)
            LoadThis(emit)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), boxPool)
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), valuePool)
            EmitInt(emit, 1)
            emit.Plan.AppendInstructionWithoutOperand((short)(nodes.Text(source, node) == "++" ? ColumnarCodePlanContract.Add() : ColumnarCodePlanContract.Sub()))
            emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), valuePool)
            return
        }
        fieldPool := FieldPool(emit, name)
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
}
