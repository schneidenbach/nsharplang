namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// Statement kind 20 (`Return`) as an ORDINARY METHOD BODY sees it.
//
// The plan-row IR has owned the `ret` INSTRUCTION for a long time — `ColumnarCodePlanContract.Ret()`
// is 42, `ColumnarCodePlanExecutor` emits it, and `ValidateMethodBodyStack` carries an explicit arm
// that refuses a `ret` inside a protected region and demands stack height 0 for a void result and 1
// for a value one. What it has never had is a body that arrives from USER SYNTAX. Every schema-v4
// producer before this one is SYNTHESIZED: the iterator/async state-machine members, the async entry
// shim, the record value members. None of them has a `return` statement, because none of them was
// ever parsed.
//
// This owner holds the two things an ordinary body needs that are not instructions:
//
//   1. THE TERMINATION RULE — whether a statement always exits via a return. It decides whether a
//      body needs a synthesized trailing `ret` and whether an emitted `if` can fall through. It is
//      the columnar mirror of the diagnostics pass's `AnalyzerStatementTermination.AlwaysReturns`,
//      which asks the same question of AST `Statement` objects; two representations, one rule, and
//      the two are kept verbatim-identical deliberately.
//
//   2. THE DRIVER — the front door that claims a whole body for the plan path, or declines it whole.
//      There is no partial claim: a body the driver accepts produces every byte of its own IL, and a
//      body it declines never touches the plan at all.
//
//   3. THE APPEND-MODE EXPRESSION DOOR — the kind-keyed dispatch that turns ONE expression into rows on
//      an already-open method-body plan. The production expression path cannot do this: it reaches the
//      owners through `ColumnarRangeIndexPlanner.TryEmitFromFacts`, which `PrepareV3()`s the plan and
//      `Execute`s it into the `ILGenerator` on the spot, so it can never contribute rows to an open
//      body. The door is that path's append-mode counterpart, and it prepares, seals and executes
//      nothing.
class ColumnarMethodBodyPlanner {

    // Whether this statement always exits via a return — the same columnar subset as the diagnostics
    // pass (Return; a Block ANY of whose statements returns; an If with an else where both branches
    // return; a Lock whose body returns; a Try under the analyzer's exact rule).
    static func AlwaysReturns(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null {
            throw new InvalidOperationException("Columnar termination analysis requires a node table.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Columnar termination analysis received an invalid node index.")
        }

        kind := nodes.Kind(node)
        // 20 Return, 48 Throw — both exit unconditionally (E1).
        if kind == 20 || kind == 48 {
            return true
        }
        // 72 Yield — a value-less `yield break` (0 children) terminates the iterator exactly like
        // return/throw; a `yield <value>` (1 child) produces a value and continues.
        if kind == 72 {
            return nodes.ChildCount(node) == 0
        }
        if kind == 49 {
            return TryStatementAlwaysReturns(nodes, node)
        }
        // 25 Block.
        if kind == 25 {
            n := 0
            while n < nodes.ChildCount(node) {
                if AlwaysReturns(nodes, nodes.Child(node, n)) {
                    return true
                }
                n = n + 1
            }
            return false
        }
        // 27 If [cond, then, else?] — only an if WITH an else can exit on every path.
        if kind == 27 {
            if nodes.ChildCount(node) != 3 {
                return false
            }
            return AlwaysReturns(nodes, nodes.Child(node, 1)) && AlwaysReturns(nodes, nodes.Child(node, 2))
        }
        // 51 Lock [lockee, body] — exits iff the body exits (probe-pinned: `lock s { return 1 }` with
        // no trailing return satisfies the analyzer).
        if kind == 51 {
            return AlwaysReturns(nodes, nodes.Child(node, 1))
        }
        return false
    }

    // 49 Try — the analyzer's rule VERBATIM: exits iff the TRY block exits AND there is at least ONE
    // catch AND every catch clause's block exits. The FINALLY (a trailing kind-25 child) is IGNORED —
    // probe-pinned: a zero-catch `try { return } finally { }` NEVER satisfies always-returns (the
    // pipeline demands a trailing return, NL305).
    static func TryStatementAlwaysReturns(nodes: ColumnarNodeTable, node: int): bool {
        if !AlwaysReturns(nodes, nodes.Child(node, 0)) {
            return false
        }

        sawCatch := false
        n := 1
        while n < nodes.ChildCount(node) {
            clause := nodes.Child(node, n)
            // 50 CatchClause; anything else at this position is the finally block.
            if nodes.Kind(clause) == 50 {
                sawCatch = true
                if !AlwaysReturns(nodes, nodes.Child(clause, nodes.ChildCount(clause) - 1)) {
                    return false
                }
            }
            n = n + 1
        }
        return sawCatch
    }

    // Whether the subtree rooted at `node` contains a Return statement (kind 20) anywhere. Expression
    // kinds are 0-19, so a kind-20 node only ever appears in statement position and walking every
    // child is safe. The constructor paths use it as their `return`-is-forbidden guard (NL103); it is
    // the same family of pure node-table statement-shape predicate as AlwaysReturns, and it lives
    // beside it for that reason.
    static func ContainsReturnStatement(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null {
            throw new InvalidOperationException("Columnar return-statement search requires a node table.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException("Columnar return-statement search received an invalid node index.")
        }

        if nodes.Kind(node) == 20 {
            return true
        }
        n := 0
        while n < nodes.ChildCount(node) {
            if ContainsReturnStatement(nodes, nodes.Child(node, n)) {
                return true
            }
            n = n + 1
        }
        return false
    }

    // THE ORDINARY-USER-BODY DRIVER.
    //
    // Claims a whole body and plans it as ONE schema-v4 method body, or declines it whole. There is no
    // partial claim: a body this accepts produces every byte of its own IL, and a body it declines is
    // emitted by the host exactly as it always was. `plan` is supplied by the caller and is only
    // meaningful when this returns true; a decline may leave it half-built rather than empty, which is
    // why the caller is expected to discard it.
    //
    // FOUR CLAIM CLASSES, each proved by its own byte-level corpus diff and its own mutation:
    //
    //   L  `{ return <scalar literal> }`  — the scalar owner's rows                        (015-B3)
    //   B  `{ return true }` / `{ return false }` — the boolean owner's row                (015-B4)
    //   P  `{ return <parameter> }` — ColumnarBoundIdentifierPlanner's Parameter selection (015-B4)
    //   V  `{ }` and `{ return }` on a VOID body — a single bare `ret`                     (015-B4)
    //   F  `{ return <instance field> }` — the CurrentField selection                      (015-B5)
    //   R  `{ return <instance property> }` — the CurrentProperty selection                (015-B5)
    //   X  `{ return <ref/out parameter> }` — the ByRefParameter selection                 (015-B5)
    //   U  `{ return <unary over a literal> }` / `nameof` — the first composites           (015-B6)
    //   D  `x := <claimed value>` — the statement loop's plan-local declaration            (015-B6)
    //   C  `{ return <call> }` — the direct-call owner's own root sequence                 (015-B7)
    //   DC `x := <call>` — the same owner in the position that runs no host pre-pass       (015-B7)
    //   PB `{ return <primitive binary> }` — the primitive-binary owner's root sequence    (015-B9)
    //   T  `{ return <ternary> }` / `{ return <a && b> }` — the conditional owner, labels  (015-B12)
    //   K  `{ return checked(<claimed value>) }` — the host's OWN kind-57 arm, no planner  (015-B13)
    //   M  `{ return <instance member> }` — the instance-member owner's root sequence      (015-B14)
    //   X  `{ return <Type>.<static member> }` — the external-static owner's root sequence (015-B15)
    //   G  `{ return (<claimed value>) }` — the host's OWN kind-7 arm, no planner        (015-B16)
    //   Y  `{ return typeof(<T>) }` — the typeof owner's own root sequence               (015-B16)
    //
    // Class C ALSO WIDENED IN `015-B9` WITHOUT GAINING A LETTER: a claimed call may now carry a binary
    // ARGUMENT and an ordinary `arr[0]` argument or receiver. Both are the direct-call owner's own
    // decisions rather than the door's — the door's kind-9 arm is the same one line it was — which is
    // why they are recorded here as a widening of C rather than as new door classes.
    //
    // The value classes all reach the plan through ONE door — `TryAppendReturnValue` — rather than
    // through a chain of special cases, so a class the door does not claim cannot arrive here by
    // accident.
    //
    // THE CLAIM RULE IS TYPE *EQUALITY*, NOT ASSIGNABILITY, AND THAT IS STILL THE POINT. The host's
    // kind-20 arm runs SEVEN target-typed pre-passes before it evaluates the expression and SEVEN
    // coercions after it, and one of the pre-passes — the int-literal adoption that turns `return 5` on
    // a `long` function into `ldc.i8` — would emit DIFFERENT rows than the literal owner does. Equality
    // is what makes all fourteen provably unreached: an unsuffixed integer literal is natural-`int`,
    // and the adoption pre-pass declines a target of `int`; `5L`/`5UL` are natural-`long`/`ulong` but
    // carry a suffix, which the pre-pass also declines. A body outside the claim is not "not yet
    // supported" — it is a body whose bytes this driver cannot promise.
    //
    // SIX OF THE SEVEN PRE-PASSES GATE ON THE NODE KIND; THE SEVENTH GATES ON THE RETURN TYPE, and
    // that one needs an explicit guard rather than an argument — see `IsSupportedNullable` below.
    //
    // The accepted shapes can contain no lambda, no branch and no exception region, so a claimed body
    // needs NO emitter state at all — which is what lets the front door stand ahead of every field the
    // host's body emission would otherwise have to set up first. In particular no claimed shape can
    // produce a LIFTED candidate (lifting requires a lambda), so reading the caller's lifted map before
    // it is computed cannot misresolve a claimed name. Since 015-B6 a claimed body CAN contain locals,
    // and they do not weaken that argument: they are declared in the PLAN's own local pool rather than
    // through the emitter, so the driver still touches none of the host's live state and a declined
    // body leaves every one of the caller's maps exactly as it found them.
    static func TryPlanBody(nodes: ColumnarNodeTable, source: string, bodyRoot: int, returnType: Type, isVoid: bool, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>, boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?, currentInstance: ColumnarStructDef?, enclosingTypeDefinition: ColumnarStructDef?, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, tupleNames: Dictionary<string, string[]>, enclosingNames: IEnumerable<string>, siblingNames: IEnumerable<string>, visibleLocalFunctionNames: IEnumerable<string>, typeParameters: Dictionary<string, Type>, exactSourceTypes: Dictionary<string, Type>, overflowCheckingEnabled: bool, siblingCallables: Dictionary<string, ColumnarSiblingCallFacts>, plan: ColumnarCodePlan, structuralTypeReferences: ColumnarStructuralTypeReferenceTable? = null): bool {
        if nodes == null || source == null || returnType == null || plan == null {
            return false
        }
        if bodyRoot < 0 || bodyRoot >= nodes.Kinds.Length || nodes.Kind(bodyRoot) != 25 {
            return false
        }

        // THE VOID ARITY (class V). Both accepted shapes lower to exactly ONE `ret`: an EMPTY block
        // emits nothing and falls through to the host's trailing `ret`, and a value-less `return`
        // takes kind 20's void arm. The gate is the RETURN TYPE and `isVoid` together, not `isVoid`
        // alone — three of the seven `EmitBody` call sites pass a literal `isVoid: true`, and only the
        // return type reproduces the host's own `_returnType == typeof(void)` test. N# cannot spell
        // `typeof(void)`, so the void marker is the same `IsVoidType` name test the method-body height
        // model itself uses to choose `voidReturn ? 0 : 1`; there is exactly one `System.Void` on the
        // emit path, so the name test and the host's reference test select the same type.
        voidReturn := ColumnarCodePlanExecutor.IsVoidType(returnType)
        if isVoid {
            if !voidReturn || !IsBareVoidBody(nodes, bodyRoot) {
                return false
            }

            plan.PrepareMethodBody()
            plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
            plan.CompleteMethodBody(returnType)
            return true
        }
        if voidReturn {
            return false
        }

        // THE ONE HOST PRE-PASS THAT IS NOT GATED ON THE NODE KIND. `IsSupportedNullable` is tested
        // against the RETURN TYPE, and when it holds the host routes the WHOLE return through its
        // lifted-nullable owner regardless of what the returned expression is. Type equality does not
        // exclude it — `(x: int?): int? { return x }` matches exactly — so the guard is explicit and
        // covers every value class at once. (The literal classes were immune by accident, because no
        // literal's natural type is a Nullable<T>; the parameter class is not.)
        if ColumnarTypeOfPlanner.IsSupportedNullable(returnType) {
            return false
        }

        // THE STATEMENT LOOP (015-B6). A claimed value body is now N declaration statements followed by
        // ONE `return <expression>` — the shape that first makes a body's own name bindings possible.
        // The last statement carries the arity, so it is checked before a single row is appended.
        statementCount := nodes.ChildCount(bodyRoot)
        if statementCount < 1 {
            return false
        }
        statement := nodes.Child(bodyRoot, statementCount - 1)
        if nodes.Kind(statement) != 20 || nodes.ChildCount(statement) != 1 {
            return false
        }

        // The bindings are built ONCE, before the plan is opened, and handed to the expression door.
        // `FromRawFacts` wraps the caller's live dictionaries by reference and copies only the type
        // parameters (a handful of entries at most). The loop REUSES this one binding set across every
        // statement rather than rebuilding it per row, and each claimed declaration publishes its name
        // into the set's OWN plan-local map — a fresh dictionary the bindings allocate, never one of the
        // caller's, so a declined body leaves the emitter's live maps untouched.
        //
        // THE THREE FACTS `015-B5` AND `015-B6` DELIBERATELY LEFT UNROUTED ARE ROUTED HERE (015-B7),
        // because the direct-call claim is the arm that reads them. They are set in the same order and
        // by the same three assignments as `ColumnarRangeIndexPlanner.TryEmitFromFacts`, which is the
        // production expression path's own seam, so the door and the cascade hand their owners
        // IDENTICAL binding state rather than merely similar state:
        //
        //   `ExactSourceTypes`      the declaration-name index `TryResolveSelectedSourceType` consults
        //                           FIRST; without it an aliased or generic-head declaration resolves by
        //                           a live scan that demands exactly one candidate, which is a DIFFERENT
        //                           selection rather than a slower one
        //   `OverflowCheckingEnabled` the checked/unchecked context `ColumnarPrimitiveBinaryPlanner`
        //                           turns into `add`/`add.ovf`. ⚠ It is PROVABLY `false` at every
        //                           `EmitBody` entry — the field starts false, is written only by
        //                           `EmitExpressionWithOverflowChecking` (which restores it in a
        //                           `finally` around ONE kind-57 child), and all seven `EmitBody` call
        //                           sites run on a freshly constructed emitter. It is carried anyway
        //                           rather than assumed, because a door that reproduces a CONCLUSION
        //                           about host state instead of reading the state itself is one refactor
        //                           away from being wrong in bytes
        //   `SiblingCallables`      the plannable top-level sibling facts. THREE of its five consumers in
        //                           `ColumnarDirectCallPlanner` are branch SELECTORS, not guards — an
        //                           empty map sends a bare sibling name down the delegate-invoke or the
        //                           decline arm instead of the sibling arm
        value := nodes.Child(statement, 0)
        bindings := ColumnarFragmentBindings.FromRawFacts(parameterOrdinals, parameterTypes, locals, enums, liftedLocals, boxedCaptures, currentInstance, sourceTypeDefinitions, sourceUnionDefinitions, tupleNames, enclosingNames, siblingNames, visibleLocalFunctionNames, typeParameters, structuralTypeReferences)
        bindings.ExactSourceTypes = exactSourceTypes
        bindings.OverflowCheckingEnabled = overflowCheckingEnabled
        if siblingCallables != null {
            bindings.SiblingCallables = siblingCallables
        }

        bindings.SetEnclosingTypeDefinition(enclosingTypeDefinition)

        plan.PrepareMethodBody()
        i := 0
        while i < statementCount - 1 {
            if !TryAppendLocalDeclaration(nodes, source, nodes.Child(bodyRoot, i), bindings, plan) {
                return false
            }

            i = i + 1
        }

        valueType := typeof(int)
        if !TryAppendReturnValue(nodes, source, value, bindings, plan, out valueType) {
            return false
        }

        if valueType != returnType {
            return false
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(returnType)
        return true
    }

    // STATEMENT KIND 24 (`name := <expression>`) — THE ONE STATEMENT THIS DRIVER CLAIMS BESIDES THE
    // RETURN, AND THE ONLY ONE THAT CREATES A BINDING.
    //
    // It reproduces the host's own kind-24 arm step for step: refuse a name the body can already see
    // (the pipeline's NL316 — shadowing is a diagnostic, not a lowering), emit the initializer, gate the
    // inferred type on the host's exact three-part test, declare a local of that type and store into it.
    // The one difference is the STORAGE HANDLE and it is forced rather than chosen: the host writes
    // `_il.DeclareLocal(initType)` because it holds the live `ILGenerator`; a plan holds none, so the
    // slot is declared in the plan's own local pool and the executor materialises it — in pool order,
    // before the first row replays — with that same `ILGenerator.DeclareLocal`. In a body this driver
    // claims END TO END the plan's locals are the ONLY locals, so pool index i is slot i.
    //
    // ⚠ THE HOST'S TWO OTHER KIND-24 BRANCHES ARE UNREACHABLE HERE, AND NEITHER NEEDS A GUARD. The
    // zero-parameter-lambda branch and the lifted-`StrongBox` branch both require a LAMBDA: the first in
    // the initializer, the second anywhere in the body (a name is a lifted candidate only when some
    // lambda captures it). Expression kind 39 is on the door's DECLINED side, and no kind the door
    // claims can contain a lambda in its subtree — the literal owners take literal operands, the
    // identifier owner takes a bare name, the unary owner takes a literal operand and `nameof` takes an
    // identifier or member-access target. So a body with a lambda anywhere in it cannot be claimed at
    // all, and a whole-body lambda scan would be a check that can never fire.
    //
    // `AlwaysReturns` LIKEWISE GETS NO SECOND CONSUMER HERE, and that is worth stating rather than
    // leaving as an absence: the claimed shape ends in `return <value>`, so the termination rule is
    // satisfied by construction and a call to it could never answer false. It arrives with the first
    // claimed shape that can fall through — a branch — not with this one.
    static func TryAppendLocalDeclaration(nodes: ColumnarNodeTable, source: string, statement: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): bool {
        if statement < 0 || statement >= nodes.Kinds.Length || nodes.Kind(statement) != 24 || nodes.ChildCount(statement) != 1 {
            return false
        }

        name := nodes.Text(source, statement)
        if name.Length == 0 || bindings.IsVisibleBindingName(name) {
            return false
        }

        // The INITIALIZER door, not the return door: the host's kind-24 arm runs no target-typed
        // pre-pass at all, so a shape the kind-20 arm would adopt is claimable here and refused there.
        initializerType := typeof(int)
        if !TryAppendValue(nodes, source, nodes.Child(statement, 0), bindings, plan, out initializerType) {
            return false
        }

        if !IsClaimedLocalType(initializerType) {
            return false
        }

        planLocal := plan.DeclarePlanLocal(plan.AddType(initializerType))
        plan.AppendPlanLocalInstruction(ColumnarCodePlanContract.Stloc(), planLocal)
        bindings.DeclarePlanLocal(name, planLocal, initializerType)
        return true
    }

    // The host's own local-type gate, in its own order (`ColumnarIlEmitter.cs`'s kind-24 arm): an open
    // generic parameter, an array of one, or the modeled supported surface. The two guards ahead of the
    // array arm are not decoration — `Type.IsSZArray` reports TRUE for a builder POINTER and a builder
    // BY-REF and can throw outright on a bare generic parameter under persisted emit, so the generic
    // arm answers first and the pointer/by-ref pair is refused before the array question is asked.
    static func IsClaimedLocalType(valueType: Type): bool {
        if valueType == null || valueType.FullName == "System.Void" || valueType.get_IsByRef() || valueType.get_IsPointer() || valueType.get_IsGenericTypeDefinition() {
            return false
        }
        if valueType.get_IsGenericParameter() {
            return true
        }
        if valueType.get_IsSZArray() {
            element := valueType.GetElementType()
            if element != null && element.get_IsGenericParameter() {
                return true
            }
        }

        return ColumnarTypeOfPlanner.IsSupportedType(valueType)
    }

    // A void body whose whole content is one `ret`: an EMPTY block, or a block whose single statement
    // is a value-less `return`. Anything else — a statement of any other kind, a `return <value>` in a
    // void body (which the host declines as a mismatched arity), or more than one statement — is not
    // this class.
    static func IsBareVoidBody(nodes: ColumnarNodeTable, bodyRoot: int): bool {
        if nodes.ChildCount(bodyRoot) == 0 {
            return true
        }
        if nodes.ChildCount(bodyRoot) != 1 {
            return false
        }

        statement := nodes.Child(bodyRoot, 0)
        return nodes.Kind(statement) == 20 && nodes.ChildCount(statement) == 0
    }

    // THE APPEND-MODE EXPRESSION FRONT DOOR.
    //
    // Turns ONE expression into rows on an already-open schema-v4 method-body plan, or declines it
    // without touching the plan. It dispatches on the EXPRESSION KIND to the owners' own append entries
    // — the same owners the production expression path reaches — so every claim is byte-identical BY
    // CONSTRUCTION rather than by imitation. `ExecuteV3` and `ExecuteMethodBody` share one
    // `EmitInstruction`, so reproducing the ROW SEQUENCE is the whole of reproducing the bytes.
    //
    // THE DOOR IS TOTAL. Every kind in `ExpressionKindLedger` is answered by exactly one of
    // `IsClaimedExpressionKind` and `IsDeclinedExpressionKind` — a partition the estate asserts rather
    // than a property this comment claims. There is no anonymous fall-through: a kind outside the
    // ledger is one the parser does not put in value position, and it declines with the rest.
    //
    // ⚠ THE NINE SCHEMA GATES ARE OPEN NOW (015-B6), AND THAT IS NOT WHAT STILL LIMITS THIS DOOR.
    // Nine owners on the value surface used to assert an open schema-**v3** plan and `throw` on a method
    // body — a HARD CRASH out of the compiler, not a decline. All nine were widened in one move, so a
    // composite is no longer a crash. What limits the claimed set now is REACHABILITY, and it is a
    // different fact: the emitter reaches its composite owners through
    // `ColumnarRangeIndexPlanner.TryEmitFromFacts`, which is an ELEVEN-ARM ROOT CASCADE, not a single
    // dispatcher — construction, direct-call, primitive-binary, conditional, typeof, bound-identifier,
    // external-static-member and instance-member each get their OWN root facade, and only range/index
    // roots fall through to the shared append dispatcher. So a composite claim must call THAT owner's
    // own root sequence; guessing a single entry point would be a second, divergent routing policy.
    // SEVEN owners are entered that way now — the unary-literal owner and `nameof`, which the emitter
    // reaches through their own facade AHEAD of the cascade, the DIRECT-CALL owner, which the cascade's
    // second arm owns for every call root (015-B7), the PRIMITIVE-BINARY owner, which the cascade's
    // third arm owns for every claimed-operator binary root (015-B9), the CONDITIONAL owner, which
    // the cascade's FOURTH arm owns for every ternary root and every `&&`/`||` root (015-B12), the
    // INSTANCE-MEMBER owner, which the cascade's EIGHTH arm owns for the member-access roots its
    // SEVENTH arm does not (015-B14), and the EXTERNAL-STATIC-MEMBER owner, which is that SEVENTH arm
    // (015-B15). Byte identity is against one owner apiece — except kind 8, the one kind TWO cascade
    // arms admit, where it is against whichever arm answers FIRST and the door now owns BOTH. The rest
    // wait for their own diffs.
    //
    // ⚠ AND SINCE `015-B13` ONE CLAIMED KIND HAS NO OWNER AT ALL. Kind 57 (`checked`/`unchecked`) is
    // absent from `FacadeRootMayNeedFacts` and from `TryAppendPlannableValueCore`, so no N# planner has
    // ever seen one; the emitter's own `case 57` is the owner, and it emits NO rows — it saves the
    // overflow flag, sets it, emits the ONE child through the ordinary expression path, and restores.
    // The door's arm is that host arm transcribed, so byte identity there is against this door's own
    // recursion. It is also why kind 57 stays unclaimed in NESTED positions: widening the shared value
    // dispatcher would change the cascade for the whole product, not just for the door.
    //
    // ⚠ THE CONDITIONAL CLAIM IS THE FIRST WHOSE ROWS BRANCH. Every kind claimed before it lowers to a
    // straight line, so `015-B12` is where the plan's LABEL rows first have to survive a method body —
    // a schema question `015-B11`'s FINDING 3 is the standing warning about, answered here by the
    // executor rather than by assumption. The three binding facts the earlier slices deliberately
    // left unrouted — `ExactSourceTypes`, the overflow flag and the sibling-callable map — ARE routed as
    // of the call claim, and as of the binary claim ALL THREE have a live consumer on the claimed
    // surface: the overflow flag is what `ColumnarPrimitiveBinaryPlanner` turns into `add` vs `add.ovf`.
    static func TryAppendReturnValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || node < 0 || node >= nodes.Kinds.Length || IsHostAdoptedReturnShape(nodes, source, node) {
            return false
        }

        return TryAppendValue(nodes, source, node, bindings, plan, out resultType)
    }

    // ⚠ THE RETURN POSITION IS NOT THE VALUE POSITION, AND A BYTE DIFF IS WHAT PROVED IT.
    //
    // The host's kind-20 arm runs seven TARGET-TYPED pre-passes before it evaluates the returned
    // expression; its kind-24 arm runs none and goes straight to `EmitExpression`. So the same
    // expression can lower differently in the two places, and one shape among the kinds this door
    // claims actually does: `TryEmitIntLiteralAsType` takes a unary MINUS over an unsuffixed decimal
    // integer literal and emits the value PRE-NEGATED — `ldc.i4.s -5`, with no `neg` row at all — on
    // every SIGNED target, `int` and `long` included. `015-B5` recorded the pre-passes as "provably
    // unreached" because equality excludes the widening ones; that is true of the POSITIVE arm, which
    // claims only byte/sbyte/short/ushort/uint/long/ulong, and false of the NEGATIVE arm, which has no
    // such target restriction. The corpus said so in bytes before this comment said it in words.
    //
    // ⚠ 015-B11 — THE SHAPE IS NO LONGER REFUSED WHOLE; THE PRE-PASS'S OWN TWO TESTS ARE REPRODUCED,
    // AND EVERY DISAGREEMENT BETWEEN THE TWO SPELLINGS IS BUILT TO FALL ON THE REFUSING SIDE.
    //
    // `015-B5` through `015-B10` refused every `-<int literal>` return because a subset of what the
    // pre-pass claims is a SILENT DIVERGENCE while a superset is only a narrowing. That is still the
    // governing asymmetry; what changed is that the superset is now the TIGHT one rather than the
    // whole shape, and the two halves are priced separately:
    //
    // THE SUFFIX HALF is the host's `text[^1] is 'u' or 'U' or 'l' or 'L' or 'm' or 'M'` transcribed
    // LITERALLY — the last character only. `5UL` and `5LU` both end in a suffix character, so both
    // decline through it exactly as the host does. `NumericLiteralFacts.GetIntegerSuffix` is NOT used
    // here on purpose: it scans a whole suffix run and does not know `m`/`M`, so it would answer a
    // different question than the one the host asks.
    //
    // THE RANGE HALF caps at `int.MaxValue` with NO target threading, and that is a PROOF rather than
    // a simplification. The pre-pass's ceiling is `sbyte.MaxValue` / `short.MaxValue` / `int.MaxValue`
    // by target, and its four unsigned targets adopt nothing at all — so `int.MaxValue` is a superset
    // of the adopted magnitude for EVERY target. It is also the only ceiling this door can ever be
    // asked about: the door claims a body only when `valueType == returnType`, and
    // `ColumnarUnaryLiteralPlanner` types `-<unsuffixed int literal>` as `int` and nothing else, so a
    // return type of `sbyte`/`short`/`long`/anything unsigned fails the equality test before this
    // predicate's answer can matter.
    //
    // AND THE RANGE HALF IS NOT DEAD, BECAUSE ONE MAGNITUDE SITS BETWEEN THE TWO OWNERS.
    // `ColumnarUnaryLiteralPlanner.TryAppendMinimumMagnitude` claims exactly `2147483648`, emitting it
    // PRE-NEGATED as `ldc.i4 -2147483648` with no `neg`; the pre-pass declines that value
    // (`2147483648 > int.MaxValue`) and falls through to its ordinary unary emission, which IS that
    // same owner. `return -2147483648` on an `int` function is therefore claimable and byte-identical.
    //
    // THE PARSE DIMENSION IS A SUPERSET TOO, MEASURED FROM THE TWO PARSERS. The host uses
    // `ulong.TryParse`, which rejects `0x…`/`0b…`/`0o…` and `_` separators;
    // `NumericLiteralFacts.TryParseUnsignedIntegerMagnitude` accepts all four. Every one of those
    // texts therefore parses HERE, compares in range, and REFUSES — the host would have emitted it
    // ordinarily, so the disagreement costs a claim and can never cost bytes. A text that parses in
    // neither also refuses, because an unproven decline is not a decline.
    //
    // `-2.5` (a FLOAT literal child) and `~3` / `!true` (other operators) never reach the pre-pass at
    // all and stay claimed in both positions, as before.
    static func IsHostAdoptedReturnShape(nodes: ColumnarNodeTable, source: string, node: int): bool {
        if nodes.Kind(node) != ColumnarExpressionNodeKind.UnaryExpression() || nodes.ChildCount(node) != 1 || nodes.Text(source, node) != "-" {
            return false
        }

        operand := nodes.Child(node, 0)
        if operand < 0 || operand >= nodes.Kinds.Length || nodes.Kind(operand) != ColumnarExpressionNodeKind.IntLiteralExpression() {
            return false
        }

        // ⚠ THE SPAN GUARD IS THE HOST'S OWN AND IT IS NOT BELT-AND-BRACES. `TryEmitIntLiteralAsType`
        // opens with `_nodes.ValueStart(node) < 0 → return false` for a reason: `ColumnarNodeTable.Text`
        // is a bare `source.Substring(valueStarts[i], valueLengths[i])`, so a literal node carrying no
        // span would THROW out of the compiler rather than decline. Until this slice this predicate
        // never read the OPERAND's text and had no such exposure; reading it is what makes the guard
        // this predicate's own obligation rather than an inherited one. An unreadable span refuses,
        // which is the same safe direction as an unparseable magnitude below.
        valueStart := nodes.ValueStart(operand)
        valueLength := nodes.ValueLengths[operand]
        if valueStart < 0 || valueLength <= 0 || valueLength > source.Length || valueStart > source.Length - valueLength {
            return true
        }

        text := nodes.Text(source, operand)
        length := text.Length
        if length == 0 {
            return true
        }

        last := text[length - 1]
        if last == 'u' || last == 'U' || last == 'l' || last == 'L' || last == 'm' || last == 'M' {
            return false
        }

        magnitude := 0UL
        if !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(text, out magnitude) {
            return true
        }

        return magnitude <= 2147483647UL
    }

    // The kind-keyed dispatcher itself, in the position where no host pre-pass runs: a `:=`
    // initializer. The return door is this function behind the one shape the kind-20 arm adopts.
    static func TryAppendValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if !IsClaimedExpressionKind(kind) {
            return false
        }

        // 0 Int, 1 Float, 2 Char, 3 String — one owner, four kinds, and the decimal suffix inside it.
        if ColumnarScalarLiteralPlanner.IsOwnedLiteralKind(kind) {
            return ColumnarScalarLiteralPlanner.TryAppendLiteral(nodes, source, node, plan, out resultType)
        }
        // 4 Bool — a different owner and therefore a different claim class, not a fifth literal.
        if kind == ColumnarExpressionNodeKind.BoolLiteralExpression() {
            if !ColumnarBooleanLiteralPlanner.TryAppendLiteral(nodes, source, node, plan) {
                return false
            }
            resultType = typeof(bool)
            return true
        }
        // 6 Identifier — five of the sole identifier owner's eight selection kinds.
        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            return TryAppendIdentifierRead(nodes, source, node, bindings, plan, out resultType)
        }
        // 11 Unary — the FIRST composite class this door claims (015-B6). The owner opens a NESTED
        // operand fragment and recurses into the scalar-literal owner, so this arm is what proves the
        // nine-gate widening end to end rather than as dead code.
        if kind == ColumnarExpressionNodeKind.UnaryExpression() {
            return ColumnarUnaryLiteralPlanner.TryAppendRoot(nodes, source, node, plan, out resultType)
        }
        // 62 NameOf — one `ldstr` under a root fragment its own gate demands. A second of the nine.
        if kind == ColumnarExpressionNodeKind.NameOfExpression() {
            return ColumnarNameOfPlanner.TryAppendRoot(nodes, source, node, plan, out resultType)
        }
        // 9 Call — THE DIRECT-CALL COMPOSITE (015-B7), and the first claimed kind whose owner consults
        // the three facts this driver routes. The owner's own root facade is what is called: the
        // emitter reaches it through `ColumnarRangeIndexPlanner.TryEmitFromFacts`'s SECOND cascade arm
        // for every call root, so entering `TryAppendRoot` — the sequence that facade's `Plan` also
        // calls — is what makes the claim byte-identical BY CONSTRUCTION. The two ownership outs are
        // read and DISCARDED on purpose: they steer the host's decline-vs-legacy choice for a call the
        // owner would not plan, and this driver has exactly one answer for all of them, which is to
        // decline the whole body and let the host make that choice itself.
        //
        // 015-B8 LIFTED THIS ARM'S PLAN-LOCAL REFUSAL. `015-B7` declined WHOLE any call whose subtree read
        // a plan local, because the owner types its arguments in a fresh scratch plan whose local pool was
        // empty and the append threw out of the compiler. The scratch now carries the body's local
        // VOCABULARY — see `ColumnarCodePlan.EnablePlanLocalMirror` — so the shape the guard existed to
        // refuse is the shape this arm now claims.
        if kind == ColumnarExpressionNodeKind.CallExpression() {
            ownership := ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning := false
            return ColumnarDirectCallPlanner.TryAppendRoot(nodes, source, node, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
        }
        // 12 Binary — THE PRIMITIVE-BINARY COMPOSITE (015-B9). The owner's own root sequence again, and
        // for a kind the host's kind-20 arm cannot pre-empt: all six of its NODE-KIND-gated pre-passes
        // want 15/36/42/58/0/5 and the seventh gates on the RETURN TYPE, which this driver already
        // refuses through `IsSupportedNullable`. So ZERO pre-passes reach a binary return value and this
        // arm needs no companion to `IsHostAdoptedReturnShape`.
        //
        // `&&`/`||` are NOT this owner's operators — they are the conditional owner's roots — and the
        // owner's own `IsAdmittedSyntax` is what refuses them, so the door does not carry a second copy
        // of that judgement. The overflow flag this driver routes is what the owner turns into
        // `add` vs `add.ovf`; it is the first CONSUMER of that fact on the claimed surface.
        //
        // 015-B12 SPLIT THIS ARM IN TWO ALONG THE OPERATOR'S LENGTH. `&&` and `||` are kind-12 binaries
        // that belong to the CONDITIONAL owner, and until this slice the door sent every kind 12 to the
        // binary owner, whose `IsAdmittedSyntax` then refused them — a decline that was correct but
        // final. The door now asks the same question the emitter's cascade asks, in the same order.
        if kind == ColumnarExpressionNodeKind.BinaryExpression() {
            if ColumnarConditionalPlanner.IsShortCircuitBinary(nodes, source, node) {
                return ColumnarConditionalPlanner.TryAppendRoot(nodes, source, node, bindings, ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
            }
            return ColumnarPrimitiveBinaryPlanner.TryAppendRoot(nodes, source, node, bindings, ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
        }
        // 13 Ternary — THE CONDITIONAL COMPOSITE (015-B12), and the FIRST claimed kind whose rows are not
        // straight-line: the owner appends `DefineLabel`/`Brfalse`/`Br`/`MarkLabel` rows, which every
        // earlier claim avoided entirely. `ColumnarCodePlan.AppendLabelInstruction` admits
        // `Br`/`Brfalse`/`Brtrue` in ANY schema (only `Leave` is method-body-gated) and
        // `ColumnarCodePlanExecutor.ExecuteMethodBodyRows` pre-defines `LabelCount` labels and services
        // `MarkLabelOperation` row for row exactly as `ExecuteRecursiveRows` does — so a branch-merge is
        // a method-body row sequence, not a schema-v3 privilege.
        //
        // Like the binary arm, this one needs no companion to `IsHostAdoptedReturnShape`: the host's
        // kind-20 arm runs seven target-typed pre-passes, six of them gated on the node kind
        // (15/36/42 union construction, 63 target-typed `new`, 11-with-`-`/0 int literal, 58 collection
        // and array literal, 5 null) and the seventh on the RETURN TYPE, which this driver already
        // refuses through `IsSupportedNullable`. Neither 13 nor a short-circuit 12 is in that set, so
        // ZERO pre-passes reach either shape.
        if kind == ColumnarExpressionNodeKind.TernaryExpression() {
            return ColumnarConditionalPlanner.TryAppendRoot(nodes, source, node, bindings, ColumnarRangeIndexHandles.Resolve(), plan, out resultType)
        }
        // 57 CheckedContext — `checked(<expr>)` / `unchecked(<expr>)` (015-B13), and THE FIRST CLAIMED
        // KIND WITH NO OWNER BEHIND IT. Every other arm above calls an N# planner the emitter also
        // reaches; kind 57 has no planner at all — it is absent from
        // `ColumnarRangeIndexPlanner.FacadeRootMayNeedFacts` (so the cascade never sees a `checked`
        // root) and absent from `TryAppendPlannableValueCore` (so no owner plans one in a nested
        // position either). Its owner is `ColumnarIlEmitter.EmitExpressionCore`'s own `case 57`, whose
        // whole body is `EmitExpressionWithOverflowChecking`: save the flag, set it, emit the ONE
        // child through the ordinary expression path, restore in a `finally`. So byte identity here is
        // against THIS door's own recursion, and the arm is that host arm transcribed.
        if kind == ColumnarExpressionNodeKind.CheckedContextExpression() {
            return TryAppendCheckedContext(nodes, source, node, bindings, plan, out resultType)
        }
        // 8 MemberAccess — THE MEMBER-ACCESS COMPOSITE (015-B14, closed in 015-B15), and the ONE
        // claimed kind the cascade answers with TWO owners rather than one. See
        // `TryAppendMemberAccessRoot`: the door asks the cascade's SEVENTH arm (external static) first
        // and its EIGHTH (instance member) second, and since `015-B15` it CLAIMS either answer.
        if kind == ColumnarExpressionNodeKind.MemberAccessExpression() {
            return TryAppendMemberAccessRoot(nodes, source, node, bindings, plan, out resultType)
        }
        // 55 TypeOf — `typeof(T)` (015-B16), and the SMALLEST remaining CASCADE arm. The owner's own
        // root sequence again — `ColumnarTypeOfPlanner.TryAppendRoot`, factored out of its `Plan` by the
        // same `015-B6`/`015-B7`/`015-B14`/`015-B15` move for the fourth time — so the claim is
        // byte-identical to the cascade's FIFTH arm by construction.
        //
        // ⚠ THAT FIFTH ARM IS THE ONLY UNCONDITIONAL ONE IN THE CASCADE:
        // `nsharpOwned = true; return ColumnarTypeOfPlanner.TryEmit(…)`, with no `ClaimsRoot` and no
        // fall-through. So the HOST already answers an unplannable `typeof` root by declining the whole
        // FUNCTION (`EmitExpressionCore`'s `if (nsharpOwned) return false;`), and a decline HERE is
        // strictly a narrowing of the body. That is the opposite risk profile from the EIGHTH arm, and
        // it is why kind 55 was separable while the composed instance-member receiver is not.
        //
        // The rows are `ldtoken <T>` + `call Type.GetTypeFromHandle`, and neither needed a schema
        // answer from this slice: `TryAppendTypeOf`'s own gate has admitted `MethodBodySchemaVersion()`
        // since `015-B6`'s nine-gate widening, and `ColumnarCodePlanExecutor.MethodBodyStackDelta`'s
        // `TypeOperand` arm already returns 1 for `Ldtoken`.
        //
        // ⚠ AND THE APPEND WAS ALREADY REACHABLE FROM THIS DOOR BEFORE THE ARM EXISTED, which is why
        // the arm is a ROOT claim rather than a new capability: `return typeof(int).Name` is a kind-8
        // root whose receiver is one of `TryGetComposedReceiverType`'s five arms, and a marked tip CLI
        // says the door claimed that body already. What kind 55 adds is the root position.
        if kind == ColumnarExpressionNodeKind.TypeOfExpression() {
            return ColumnarTypeOfPlanner.TryAppendRoot(nodes, source, node, bindings, plan, out resultType)
        }
        // 7 Parenthesized — `(<expr>)` (015-B16), and THE SECOND CLAIMED KIND WITH NO PLANNER OF ITS
        // OWN. Like kind 57 it is the HOST's own arm transcribed, and the host's arm is one line:
        // `case 7: return EmitExpression(Child(idx, 0), out type);`. So the arm is a child-count guard
        // and one recursion through THIS dispatcher.
        //
        // ⚠ AND BYTE IDENTITY HERE IS NOT ONLY AGAINST THAT ARM, BECAUSE THE HOST DOES NOT REACH
        // `case 7` FOR MOST OF THE SHAPE. `ColumnarRangeIndexPlanner.FacadeRootMayNeedFacts` OPENS
        // with `node = UnwrapParentheses(nodes, node)`, and ALL EIGHT cascade owners' `MayPlanRoot`
        // unwrap too — construction, direct call, primitive binary, conditional, `typeof`, bound
        // identifier, external static and instance member each open
        // `candidate := UnwrapParentheses(nodes, node)`. So `(a + b)`, `(f())`, `(p.V)`,
        // `(Environment.NewLine)`, `(x)`, `(flag ? 1 : 2)`, `(a && b)`, `(typeof(T))` and `(new T())`
        // reach their OWNER at the OUTER kind-7 node on the host side; `case 7` is reached only by the
        // kinds the facade declines — the four scalar literals, `bool`, an ordinary unary, `nameof`,
        // `checked`/`unchecked` and a nested kind 7.
        //
        // THAT OVERTURN IS WHAT MAKES ONE RECURSION A PROOF RATHER THAN A HOPE. Every one of those
        // owners' `TryAppendRoot` — the factored root-append sequence this door already calls for
        // kinds 8, 9, 12 and 13 — ALSO opens with `UnwrapParentheses`, so `TryAppendRoot(outer)` and
        // `TryAppendRoot(inner)` compute the same `candidate`, open the same
        // `BeginFragment(-1, kind, candidate)` and append the same rows. One arm reproduces both host
        // routes.
        //
        // ⚠ THE RETURN-POSITION PRE-PASS NEEDS NO COMPANION HERE, AND THAT WAS MEASURED IN BYTES
        // BEFORE IT WAS ARGUED. `TryEmitIntLiteralAsType` reads `_nodes.Kind(node)` UNWRAPPED, so a
        // kind-7 outer node declines it on the host side exactly as `IsHostAdoptedReturnShape`'s own
        // `Kind(node) != UnaryExpression` declines it here. The consequence is visible: `return -5` is
        // `ldc.i4.s -5` (adopted, pre-negated) while `return (-5)` is `ldc.i4.5; neg` — the PARENTHESIS
        // changes the host's own lowering, and this arm reproduces the parenthesised one because it
        // recurses into the same `ColumnarUnaryLiteralPlanner` the host's `case 7` reaches. Teaching
        // `IsHostAdoptedReturnShape` to unwrap would be a WRONG narrowing: it would refuse a shape the
        // host does not adopt. Two of the seven pre-passes DO unwrap
        // (`TryEmitTargetTypedNewAsType`, `TryEmitCollectionLiteralAsType`/`CanUseArrayLiteralAsType`)
        // and both gate on kinds 63 and 58, which this door does not claim.
        //
        // ⚠ AND THE CHILD IS DISPATCHED, NOT ADMITTED. `(null)` reaches the kind-5 refusal and
        // declines the body — which is also the only safe answer at a tip where the HOST cannot
        // compile `return (null)` at all (`NL103`, `emit.expression.unhandled-kind`, node kind 5).
        if kind == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if nodes.ChildCount(node) != 1 {
                return false
            }

            return TryAppendValue(nodes, source, nodes.Child(node, 0), bindings, plan, out resultType)
        }
        // Unreachable while the claimed set and the arms above agree, and that agreement is exactly
        // what the estate's partition block asserts. A kind added to the claimed set without its own
        // arm lands here and DECLINES rather than silently taking a neighbouring owner's route.
        return false
    }

    // THE CHECKED/UNCHECKED CONTEXT (015-B13) — the host's `case 57` arm, transcribed.
    //
    // The host reads the KEYWORD out of the node's value span and routes `checked` and `unchecked` to
    // `EmitExpressionWithOverflowChecking(idx, enabled)`, which sets `_overflowCheckingEnabled` around
    // ONE child and restores it. The routed counterpart of that field is `bindings.OverflowCheckingEnabled`,
    // which `TryPlanBody` has carried since `015-B7` and whose ONE production consumer is
    // `ColumnarPrimitiveBinaryPlanner`'s `checkedIntegral` — the `add`/`add.ovf` choice. So the arm's whole
    // job is to flip that field, recurse through the SAME dispatcher the enclosing position used, and put
    // the field back.
    //
    // ⚠ THE RESTORE IS ON THE NORMAL PATH ONLY, AND THAT IS A DELIBERATE DIFFERENCE FROM THE HOST'S
    // `finally`. The bindings object is built fresh inside `TryPlanBody` and is never handed to a second
    // body, so a throw out of the recursion abandons the whole claim and the object with it; there is no
    // later reader for a stale flag to reach. What the restore DOES protect is the ordinary nesting case —
    // `checked(unchecked(x))` and a second statement after a claimed `:=` — and the tip bytes say the
    // INNER keyword wins (`checked(unchecked(a + b))` is `add`, `unchecked(checked(a + b))` is `add.ovf`).
    //
    // ⚠ THE SPAN GUARD IS THIS ARM'S OWN OBLIGATION, NOT AN INHERITED ONE. `ColumnarNodeTable.Text` is a
    // bare `source.Substring(valueStarts[i], valueLengths[i])`, so a kind-57 node carrying no keyword span
    // would THROW out of the compiler rather than decline. The host reads it unguarded because it is
    // already committed to emitting; a front door that crashes is strictly worse than one that declines,
    // and a decline here is a narrowing rather than a divergence.
    //
    // ⚠ THE CHILD IS STILL NOT UNWRAPPED HERE, AND SINCE `015-B16` IT DOES NOT NEED TO BE. `015-B13`
    // wrote that `checked((a + b))`'s child is kind 7, which `IsDeclinedExpressionKind` refuses, "so the
    // body declines exactly as `return (a + b)` already does". BOTH HALVES MOVED TOGETHER and the
    // sentence stays true in its shape: this arm recurses through `TryAppendValue`, whose kind-7 arm now
    // CLAIMS, so `checked((a + b))` is claimed exactly as `return (a + b)` now is. What has NOT happened
    // is a second parenthesis policy — this arm still does no unwrapping of its own; it dispatches its
    // one child and the door's single kind-7 arm answers.
    //
    // ⚠ AND THE ONE SHAPE WHERE `checked` CHANGES A UNARY LOWERING IS UNREACHABLE FROM HERE. The host's
    // `case 11` negation arm, under an active flag, DECLARES A LOCAL and writes
    // `stloc; ldc.i4.0; ldloc; sub.ovf` instead of `neg` — a local the plan never pooled. The door's
    // kind-11 arm is `ColumnarUnaryLiteralPlanner`, which claims only a unary over a LITERAL operand, so
    // `checked(-a)` over a parameter declines the body whole. With a LITERAL operand that same pre-cascade
    // owner claims the node on BOTH sides and consults no flag, so `checked(-5)` is `ldc.i4.5; neg` in
    // both pipelines. The asymmetry exists and the door cannot reach it.
    static func TryAppendCheckedContext(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if nodes.ChildCount(node) != 1 {
            return false
        }

        valueStart := nodes.ValueStart(node)
        valueLength := nodes.ValueLengths[node]
        if valueStart < 0 || valueLength <= 0 || valueLength > source.Length || valueStart > source.Length - valueLength {
            return false
        }

        keyword := nodes.Text(source, node)
        enabled := keyword == "checked"
        if !enabled && keyword != "unchecked" {
            return false
        }

        previous := bindings.OverflowCheckingEnabled
        bindings.OverflowCheckingEnabled = enabled
        appended := TryAppendValue(nodes, source, nodes.Child(node, 0), bindings, plan, out resultType)
        bindings.OverflowCheckingEnabled = previous
        return appended
    }

    // THE MEMBER-ACCESS ROOT (015-B14, CLOSED IN 015-B15) — THE ONE CLAIMED KIND THE CASCADE ANSWERS
    // WITH TWO OWNERS, AND NOW THE DOOR OWNS BOTH.
    //
    // Every arm above reaches ONE owner, because for every kind above exactly one cascade arm admits
    // it. Kind 8 is different: `ColumnarExternalStaticMemberPlanner.MayPlanRoot` and
    // `ColumnarInstanceMemberPlanner.MayPlanRoot` are the SAME unqualified `kind == MemberAccess` test,
    // and `ColumnarRangeIndexPlanner.TryEmitFromFacts` asks the external-static owner at its SEVENTH
    // arm and the instance-member owner at its EIGHTH. Byte identity for a kind-8 root is therefore
    // against whichever owner answers FIRST, and an arm that called only the second would emit the
    // wrong owner's rows for any node both would claim.
    //
    // ⚠ SO THE ARM ASKS BOTH QUESTIONS IN THE CASCADE'S ORDER AND CLAIMS EITHER ANSWER. `015-B14`
    // asked the seventh arm into a SCRATCH plan and DECLINED on a positive answer, because the
    // external-static root was that slice's named remainder. `015-B15` gives that owner its own
    // `TryAppendRoot` — the same `015-B6`/`015-B7`/`015-B14` factoring for the third time — so the
    // question is now asked into the REAL plan and a positive answer is a CLAIM. There is no scratch
    // plan left in this arm and no refusal in it.
    //
    // ⚠ THE ORDER IS THE WHOLE OF THE CORRECTNESS, AND IT IS THE CASCADE'S ORDER RATHER THAN A
    // RE-DERIVATION OF IT. The two owners' claim sets are DISJOINT at this tip — the external-static
    // owner needs `TryGetQualifiedName` on the receiver (an identifier or a dotted chain of them) AND
    // `!bindings.IsValueBinding(root)`, while every receiver `ColumnarInstanceMemberPlanner.ClaimsRoot`
    // types through `TryGetReceiverType` IS a value binding and four of `TryGetComposedReceiverType`'s
    // five arms are shapes `TryGetQualifiedName` refuses outright. The one shape that could satisfy
    // both is `A.B.C` where `A.B` and `A.B.C` are BOTH rows of the external static-member table, which
    // no row shape in that table produces today. Asking in the cascade's order costs nothing while
    // that holds and is the only thing that stays correct when the table grows a dotted owner.
    //
    // ⚠ AND THIS IS THE FIRST DOOR ARM THAT OFFERS **ONE OPEN PLAN TO TWO OWNERS**. In the cascade
    // each owner's `Plan` calls `PrepareV3` and the second call resets the plan; here the plan is an
    // already-open schema-v4 method body and there is no reset. What makes the retry legal is
    // `ColumnarCodePlan.Rollback`: it restores `OperationCount`, every pool count, `FragmentCount` and
    // `OpenFragmentCount`, nulls `ResultType`, and sets `Status` back to `NotOwned` — which is exactly
    // the state `ColumnarInstanceMemberPlanner.TryAppend`'s input gate demands, and without that last
    // line a declined external-static root would make the next owner THROW rather than decline.
    //
    // ⚠ THE INSTANCE OWNER'S ROOT SEQUENCE DECLARES PLAN LOCALS, WHICH IS WHY THE POOL ORDER IS AN
    // ARGUMENT AND NOT AN ASSUMPTION. `AppendTemporaryAddress` spills a value-typed receiver with
    // `stloc; ldloca`, so a claimed body's local pool can now interleave the statement loop's `:=`
    // locals with the expression's own temporaries. The order still agrees with the host's, because
    // the door appends a declaration's INITIALIZER before it declares that declaration's local —
    // exactly the order in which the host emits the initializer (declaring the temporary inside the
    // expression's own v3 plan) and then calls `_il.DeclareLocal` for the named one. `m := a[0].X` is
    // `[temp, m]` on both sides, and `EmitBody` offers this door before the emitter has declared a
    // single local, so pool index i is slot i. The external-static owner declares none at all: its
    // whole append is one `call`, one `ldsfld` or one `ldc.i4`/`ldc.i8`.
    static func TryAppendMemberAccessRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        if ColumnarExternalStaticMemberPlanner.TryAppendRoot(nodes, source, node, bindings, plan, out resultType) {
            return true
        }

        if !ColumnarInstanceMemberPlanner.ClaimsRoot(nodes, source, node, bindings) {
            return false
        }

        return ColumnarInstanceMemberPlanner.TryAppendRoot(nodes, source, node, bindings, plan, out resultType)
    }

    // The kinds the door takes. Each owner is method-body-schema aware; six of them (unary, `nameof`,
    // direct call, primitive binary, conditional, instance member) reach that state only through
    // `015-B6`'s nine-gate widening.
    //
    // ⚠ KIND 12 IS CLAIMED BY TWO OWNERS, NOT ONE, AND THIS PREDICATE DELIBERATELY DOES NOT SAY WHICH.
    // A `&&` binary and a `+` binary are the same kind and different owners; the split lives in
    // `TryAppendValue`'s arm, where the emitter's own cascade makes it. Duplicating the operator test
    // here would be a second copy of that judgement, and the two copies could disagree.
    static func IsClaimedExpressionKind(kind: int): bool {
        return ColumnarScalarLiteralPlanner.IsOwnedLiteralKind(kind) || kind == ColumnarExpressionNodeKind.BoolLiteralExpression() || kind == ColumnarExpressionNodeKind.IdentifierExpression() || kind == ColumnarExpressionNodeKind.UnaryExpression() || kind == ColumnarExpressionNodeKind.NameOfExpression() || kind == ColumnarExpressionNodeKind.CallExpression() || kind == ColumnarExpressionNodeKind.BinaryExpression() || kind == ColumnarExpressionNodeKind.TernaryExpression() || kind == ColumnarExpressionNodeKind.CheckedContextExpression() || kind == ColumnarExpressionNodeKind.MemberAccessExpression() || kind == ColumnarExpressionNodeKind.ParenthesizedExpression() || kind == ColumnarExpressionNodeKind.TypeOfExpression()
    }

    // The kinds the door refuses, named one by one rather than left to a fall-through. The reason is
    // uniform and worth stating once: each is either a COMPOSITE (its owner recurses into the value
    // surface, where the nine un-widened gates throw) or a form whose host lowering is not a plan-row
    // owner at all. None is "not yet supported" — each is a body whose bytes this door cannot promise.
    static func IsDeclinedExpressionKind(kind: int): bool {
        // 5 NullLiteral (the host's target-typed kind-20 pre-pass owns it) and 10 IndexAccess —
        // composites that recurse into the shared value dispatcher, whose routing this door does not
        // reproduce. 9 Call LEFT THIS LIST in `015-B7`, 8 MEMBER-ACCESS in `015-B14`, and
        // 7 PARENTHESIZED in `015-B16`.
        //
        // ⚠ THE PARENTHESIS PARAGRAPH THAT STOOD HERE WAS WRONG ABOUT THE HOST, NOT MERELY
        // CONSERVATIVE. It read: *"parenthesised forms stay here because the owner's own
        // `UnwrapParentheses` is reached through its root facade and this door dispatches on the OUTER
        // kind, so `(f())` and `(p).V` are the parenthesis owner's shape rather than the call or
        // instance-member owner's."* The premise is false: `FacadeRootMayNeedFacts` unwraps BEFORE the
        // cascade and every cascade owner's `MayPlanRoot` unwraps again, so `(f())` IS the call
        // owner's shape on the host side. `015-B16`'s kind-7 arm dispatches the CHILD through this
        // same dispatcher, reaching those owners' `TryAppendRoot` (which unwrap too) and therefore
        // reproducing the host's outer-node route exactly. And `(p).V` was never this kind at all: it
        // parses as `MemberAccess[Parenthesized[Identifier]]`, so its ROOT is kind 8 and `015-B14`
        // claimed it.
        if kind == ColumnarExpressionNodeKind.NullLiteralExpression() || kind == ColumnarExpressionNodeKind.IndexAccessExpression() {
            return true
        }
        // 15 New, 16 Cast, 36 ObjectInitializer, 58 ArrayLiteral, 69 Range — the named
        // composites. Their gates are widened now, but the emitter reaches each of them through
        // `ColumnarRangeIndexPlanner.TryEmitFromFacts`'s eleven-arm ROOT CASCADE, and a claim here must
        // reproduce that arm's exact entry. Each arrives with its own corpus diff. 12 Binary LEFT THIS
        // LIST in `015-B9`, which is also what made the routed overflow flag load-bearing rather than
        // merely carried, and 13 TERNARY left it in `015-B12` through the cascade's FOURTH arm.
        if kind == ColumnarExpressionNodeKind.NewExpression() || kind == ColumnarExpressionNodeKind.CastExpression() || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression() {
            return true
        }
        // 55 TYPEOF LEFT THIS LIST in `015-B16` through the cascade's FIFTH arm, which is the only
        // UNCONDITIONAL one: the host sets `nsharpOwned = true` before it asks, so an unplannable
        // `typeof` root already declines the whole function on the host side and a door decline can
        // only narrow the body.
        if kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() || kind == ColumnarExpressionNodeKind.RangeExpression() {
            return true
        }
        // The kinds the parser produces in value position that have no named accessor on the ledger
        // class. They are spelled here exactly as `ColumnarIlEmitter.EmitExpressionCore` spells them.
        // 17 Tuple, 18 Match, 39 Lambda, 42 BareNew, 44 PostfixUnary, 45 Must.
        if kind == 17 || kind == 18 || kind == 39 || kind == 42 || kind == 44 || kind == 45 {
            return true
        }
        // 46 Is, 47 As, 52 With, 53 Await, 59 AnonymousObjectInitializer, 64 SpreadArgument.
        // 57 CHECKED-CONTEXT LEFT THIS LIST in `015-B13`: it is the one claimed kind whose host arm is
        // not a planner call at all, so the door reproduces it directly.
        return kind == 46 || kind == 47 || kind == 52 || kind == 53 || kind == 59 || kind == 64
    }

    // THE LEDGER THE DOOR PARTITIONS — every node kind the parser can produce in a return-VALUE
    // position, taken from `ColumnarExpressionNodeKind` and from the kinds
    // `ColumnarIlEmitter.EmitExpressionCore` and its pre-switch owners handle. It exists so the
    // totality property is a fact something can assert, not a promise a comment makes: for every kind
    // here, exactly one of `IsClaimedExpressionKind` and `IsDeclinedExpressionKind` holds.
    static func ExpressionKindLedger(): int[] {
        return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 36, 39, 42, 44, 45, 46, 47, 52, 53, 55, 57, 58, 59, 62, 64, 69]
    }

    // THE IDENTIFIER CLASSES. `ColumnarBoundIdentifierPlanner` is the SOLE owner of lexical
    // identifier-value reads, and the production expression path already routes every bare identifier
    // through it — `EmitExpressionCore` calls `ColumnarRangeIndexPlanner.TryEmitFromFacts` before its
    // own switch, and that facade admits `IdentifierExpression` unconditionally. So this door calls
    // the SAME owner rather than reproducing it, which is what makes each claim byte-identical BY
    // CONSTRUCTION — including the argument narrowing, since both sides reach
    // `ColumnarCodePlanExecutor.EmitArgument` and therefore agree at every ordinal, not just 0..3.
    //
    // The resolve runs FIRST and is pure, so a selection this door does not claim never mutates the
    // plan. FIVE of the owner's eight selection kinds are claimed:
    //
    //   P  Parameter        `ldarg <n>`                                   (015-B4)
    //   F  CurrentField     `ldarg.0; ldfld <f>`                          (015-B5)
    //   R  CurrentProperty  `ldarg.0; call|callvirt get_<p>`              (015-B5)
    //   X  ByRefParameter   `ldarg <n>; ldind.<t>`                        (015-B5)
    //   D  PlanLocal        `ldloc <i>`                                   (015-B6)
    //
    // ⚠ `PlanLocal` IS THE ONE THE STATEMENT LOOP CREATED, AND `Local` IS STILL NOT REACHABLE — which
    // is the opposite of what B5 predicted. B5 recorded `Local` as arriving "with the statement loop".
    // It does not: `Local` names an AMBIENT `LocalBuilder` the emitter already created, and a body this
    // driver claims end to end has none, because the driver never had an `ILGenerator` with which to
    // create one. The loop's locals live in the PLAN's own pool, which is a different storage tier and
    // therefore a different selection kind. `Local` becomes reachable only if a claimed body is ever
    // entered with locals the host declared first — which the front door's position ahead of every
    // emitter field makes impossible today.
    //
    // THE OTHER TWO UNCLAIMED ONES ARE UNREACHABLE, NOT UNTRUSTED: `LiftedLocal` needs a lambda to lift
    // into and `BoxedCapture` needs a closure display frame, and no kind on the door's claimed side can
    // contain a lambda anywhere in its subtree.
    //
    // The current-instance pair reads `bindings.CurrentInstance` and NOTHING else beyond what the
    // parameter class already read: `ExactSourceTypes`, the overflow flag and the sibling-callable
    // facts are consumed by `TryResolveSelectedSourceType`, `ColumnarPrimitiveBinaryPlanner` and
    // `ColumnarDirectCallPlanner` respectively. `015-B5` and `015-B6` recorded that they become
    // mandatory when a COMPOSITE class is claimed rather than when this filter widens, and `015-B7` is
    // that moment: the call claim routes all three at `TryPlanBody`, so no identifier selection's
    // behaviour changed — the facts arrived for the arm below this one, not for this one.
    static func TryAppendIdentifierRead(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        selection := ColumnarBoundIdentifierPlanner.EmptySelection()
        if !ColumnarBoundIdentifierPlanner.TryResolve(nodes, source, node, bindings, out selection) {
            return false
        }
        if !IsClaimedIdentifierSelection(selection.Kind) {
            return false
        }

        return ColumnarBoundIdentifierPlanner.TryAppend(nodes, source, node, bindings, plan, out resultType)
    }

    static func IsClaimedIdentifierSelection(selectionKind: ColumnarBoundIdentifierKind): bool {
        return selectionKind == ColumnarBoundIdentifierKind.Parameter || selectionKind == ColumnarBoundIdentifierKind.ByRefParameter || selectionKind == ColumnarBoundIdentifierKind.CurrentField || selectionKind == ColumnarBoundIdentifierKind.CurrentProperty || selectionKind == ColumnarBoundIdentifierKind.PlanLocal
    }
}
