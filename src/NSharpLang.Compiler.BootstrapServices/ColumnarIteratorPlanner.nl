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

    constructor(capacity: int, paramNames: string[], paramCanonicals: string[]) {
        YieldReturnCount = 0
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

        // Element-type inference: only a synchronous IEnumerable<X> return is covered; IAsyncEnumerable is
        // the async-iterator slice, and every other sequence return declines. The element may be one of
        // the function's own type parameters — the state machine then becomes generic with the parameter
        // flowing into the current/value fields (the host mirrors the type-parameter list onto the SM).
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
            // Foreach / `for..in` [source, body], loop-var name in the value span. This slice lowers
            // for..in over a BOUND ARRAY identifier as an index loop over hoisted array/index fields
            // (no enumerator, no fault region); every other source is the enumerator-hoisting slice.
            // Each loop hoists a synthetic `<>__index{k}` int plus the user loop variable, in that
            // order, so the emit walk resolves both by the same counter and name.
            if nodes.ChildCount(node) != 2 {
                state.Decline("emit.iterator.for-in-unsupported", "unsupported for..in statement in an iterator body")
                return false
            }
            sourceNode := nodes.Child(node, 0)
            if nodes.Kind(sourceNode) != 6 {
                state.Decline("emit.iterator.for-in-unsupported",
                    "`for..in` in an iterator body is lowered only over a bound array identifier; other sources are a later slice")
                return false
            }
            sourceName := nodes.Text(source, sourceNode)
            sourceCanonical := state.LookupCanonical(sourceName)
            if sourceCanonical == "" {
                state.Decline("emit.iterator.unsupported-shape",
                    "unbound identifier '" + sourceName + "' in an iterator body")
                return false
            }
            elementCanonical := ArrayElementCanonicalOf(sourceCanonical)
            if elementCanonical != "" {
                if !IsLowerableArrayElementCanonical(elementCanonical) {
                    state.Decline("emit.iterator.for-in-unsupported",
                        "array element type '" + elementCanonical + "' is not yet lowered in an iterator for..in")
                    return false
                }
                state.AddLocal("<>__index" + state.ForInCount.ToString(), "int")
                state.ForInCount = state.ForInCount + 1
                state.AddLocal(nodes.Text(source, node), elementCanonical)
                if state.Declined {
                    return false
                }
                // The empty-array exit edge always falls through; the body result drives dead-code dropping.
                WalkStatement(nodes, source, nodes.Child(node, 1), state)
                return !state.Declined
            }
            // An IEnumerable<X>/List<X> source hoists its enumerator into a `<>__enum{k}` field: the
            // loop lowers to GetEnumerator/MoveNext/get_Current callvirts inside MoveNext's fault
            // region (which disposes live enumerators on exception; Dispose() covers suspension).
            enumerableElement := EnumerableElementCanonicalOf(sourceCanonical)
            if enumerableElement == "" {
                state.Decline("emit.iterator.for-in-unsupported",
                    "`for..in` over a non-sequence value ('" + sourceCanonical + "') in an iterator body is a later slice")
                return false
            }
            if !IsLowerableArrayElementCanonical(enumerableElement) {
                state.Decline("emit.iterator.for-in-unsupported",
                    "sequence element type '" + enumerableElement + "' is not yet lowered in an iterator for..in")
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

    constructor(
        plan: ColumnarCodePlan,
        context: ColumnarIteratorEmitContext,
        thisArg: int,
        stateFieldPool: int,
        resumeLabels: int[],
        endLabel: int,
        regionMode: bool,
        resultLocal: int,
        regionEndLabel: int) {
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
        if kind == 29 {
            // for..in [source, body]: array sources take the index loop, IEnumerable/List sources the
            // hoisted-enumerator loop — decided by the source field's canonical, mirroring the walk.
            sourceCanonical := emit.Context.FieldCanonicalForName(nodes.Text(source, nodes.Child(node, 0)))
            if ColumnarIteratorPlanner.ArrayElementCanonicalOf(sourceCanonical) == "" {
                return EmitEnumerableForIn(emit, node)
            }
            sourceName := nodes.Text(source, nodes.Child(node, 0))
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
        sourceName := nodes.Text(source, nodes.Child(node, 0))
        enumName := "<>__enum" + emit.NextEnumerator.ToString()
        emit.NextEnumerator = emit.NextEnumerator + 1
        varName := nodes.Text(source, node)
        sourcePool := FieldPool(emit, sourceName)
        enumPool := FieldPool(emit, enumName)
        varPool := FieldPool(emit, varName)
        element := emit.Context.FieldCanonicalForName(varName)
        getEnumeratorPool := emit.Plan.AddMethod(EnumerableGetEnumeratorMethodOf(element))
        moveNextPool := emit.Plan.AddMethod(EnumeratorMoveNextMethod())
        currentPool := emit.Plan.AddMethod(EnumeratorCurrentGetterOf(element))
        disposePool := emit.Plan.AddMethod(DisposableDisposeMethod())
        // this.enum = this.source.GetEnumerator()
        LoadThis(emit)
        LoadThis(emit)
        emit.Plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), sourcePool)
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

    static func EnumerableGetEnumeratorMethodOf(elementCanonical: string): MethodInfo {
        method := EnumerableInterfaceTypeOf(RuntimeElementTypeOf(elementCanonical)).GetMethod("GetEnumerator")
        if method == null {
            throw new InvalidOperationException("IEnumerable<" + elementCanonical + ">.GetEnumerator was not found.")
        }
        return method
    }

    static func EnumeratorCurrentGetterOf(elementCanonical: string): MethodInfo {
        method := EnumeratorInterfaceTypeOf(RuntimeElementTypeOf(elementCanonical)).GetMethod("get_Current")
        if method == null {
            throw new InvalidOperationException("IEnumerator<" + elementCanonical + ">.get_Current was not found.")
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
