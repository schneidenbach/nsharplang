namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


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
    static func TryPlanBody(nodes: ColumnarNodeTable, source: string, bodyRoot: int, returnType: Type, isVoid: bool, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>, boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?, currentInstance: ColumnarStructDef?, enclosingTypeDefinition: ColumnarStructDef?, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, tupleNames: Dictionary<string, string[]>, enclosingNames: IEnumerable<string>, siblingNames: IEnumerable<string>, visibleLocalFunctionNames: IEnumerable<string>, typeParameters: Dictionary<string, Type>, exactSourceTypes: Dictionary<string, Type>, overflowCheckingEnabled: bool, siblingCallables: Dictionary<string, ColumnarSiblingCallFacts>, plan: ColumnarCodePlan): bool {
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
        bindings := ColumnarFragmentBindings.FromRawFacts(parameterOrdinals, parameterTypes, locals, enums, liftedLocals, boxedCaptures, currentInstance, sourceTypeDefinitions, sourceUnionDefinitions, tupleNames, enclosingNames, siblingNames, visibleLocalFunctionNames, typeParameters)
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
    // THREE owners are entered that way now — the unary-literal owner and `nameof`, which the emitter
    // reaches through their own facade AHEAD of the cascade, and the DIRECT-CALL owner, which the
    // cascade's second arm owns for every call root (015-B7). Byte identity is against one owner apiece.
    // The rest wait for their own diffs. The three binding facts the earlier slices deliberately left
    // unrouted — `ExactSourceTypes`, the overflow flag and the sibling-callable map — ARE routed as of
    // the call claim, because the direct-call owner is what reads two of them and the primitive-binary
    // owner (still declined) is what reads the third.
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
    // The shape is refused WHOLE rather than by reproducing the pre-pass's suffix and range arithmetic.
    // A superset of what the pre-pass claims can only narrow this door — the excess declines and the
    // host emits as ever — while a subset would be a silent divergence, which is the one outcome that
    // must be impossible. `-2.5` (a FLOAT literal child), `-5L` (a suffixed child) and `~3` / `!true`
    // (other operators) are outside the pre-pass and stay claimed in both positions.
    static func IsHostAdoptedReturnShape(nodes: ColumnarNodeTable, source: string, node: int): bool {
        if nodes.Kind(node) != ColumnarExpressionNodeKind.UnaryExpression() || nodes.ChildCount(node) != 1 || nodes.Text(source, node) != "-" {
            return false
        }

        operand := nodes.Child(node, 0)
        return operand >= 0 && operand < nodes.Kinds.Length && nodes.Kind(operand) == ColumnarExpressionNodeKind.IntLiteralExpression()
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
        if kind == ColumnarExpressionNodeKind.CallExpression() {
            if ReadsPlanLocal(nodes, source, node, bindings, 0) {
                return false
            }

            ownership := ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning := false
            return ColumnarDirectCallPlanner.TryAppendRoot(nodes, source, node, bindings, plan, out ownership, out legacyWholeSubtreePlanning, out resultType)
        }
        // Unreachable while the claimed set and the arms above agree, and that agreement is exactly
        // what the estate's partition block asserts. A kind added to the claimed set without its own
        // arm lands here and DECLINES rather than silently taking a neighbouring owner's route.
        return false
    }

    // ⚠ A PLAN LOCAL CANNOT CROSS INTO A CALL'S OWN TYPE DISCOVERY, AND THIS REFUSAL IS A MEASURED
    // HARD-CRASH GUARD RATHER THAN A TASTE. THE CLAIM-CLASS CORPUS PRODUCED THE CRASH; NO REVIEW DID.
    //
    // `ColumnarDirectCallPlanner.TryGetPlannableValueType` discovers each argument's type by planning it
    // into a FRESH schema-v3 SCRATCH plan, and that plan's local pool is EMPTY. The sole identifier
    // owner appends `ldloc <pool index>` for a plan local (`ColumnarBoundIdentifierPlanner:216`), and an
    // index the scratch does not have throws "The opcode does not use this plan-local entry" straight
    // out of the compiler — which is exactly what `n := Callee(3)` followed by `return Callee(n)` did
    // before this guard existed. It is a THROW, not a wrong byte, and it was reachable only once the
    // statement loop (015-B6) and the call claim (015-B7) coexisted: neither slice alone could produce
    // a body where a plan local is read inside a call.
    //
    // MIRRORING THE POOL INTO THE SCRATCH IS *NOT* THE FIX, AND THAT WAS MEASURED TOO.
    // `ColumnarCodePlanExecutor.ValidateAllUsed` demands that EVERY declared plan local be referenced by
    // some row, on both the v3 and the method-body validator, so a mirrored pool with one read fails
    // validation instead of throwing at the append. Making a scratch plan able to REPRESENT a pool it
    // does not emit is a plan-contract change to the shared validator, and it belongs in a slice with
    // its own diff and its own control rather than smuggled in behind a composite claim.
    //
    // Until then a call whose subtree reads a plan local is declined WHOLE. The cost is measured, not
    // guessed: `x := f(1)` followed by `return x` still CLAIMS (the return is an identifier, not a
    // call), `return f(7)` still claims, and only a plan-local read INSIDE a call's subtree — the shape
    // `return g(x)` — is refused.
    static func ReadsPlanLocal(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, depth: int): bool {
        if bindings.PlanLocals.Count == 0 || depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        if nodes.Kind(node) == ColumnarExpressionNodeKind.IdentifierExpression() && bindings.PlanLocals.ContainsKey(nodes.Text(source, node)) {
            return true
        }

        n := 0
        while n < nodes.ChildCount(node) {
            if ReadsPlanLocal(nodes, source, nodes.Child(node, n), bindings, depth + 1) {
                return true
            }

            n = n + 1
        }
        return false
    }

    // The kinds the door takes. Each owner is method-body-schema aware; three of them (unary, `nameof`,
    // direct call) reach that state only through `015-B6`'s nine-gate widening.
    static func IsClaimedExpressionKind(kind: int): bool {
        return ColumnarScalarLiteralPlanner.IsOwnedLiteralKind(kind) || kind == ColumnarExpressionNodeKind.BoolLiteralExpression() || kind == ColumnarExpressionNodeKind.IdentifierExpression() || kind == ColumnarExpressionNodeKind.UnaryExpression() || kind == ColumnarExpressionNodeKind.NameOfExpression() || kind == ColumnarExpressionNodeKind.CallExpression()
    }

    // The kinds the door refuses, named one by one rather than left to a fall-through. The reason is
    // uniform and worth stating once: each is either a COMPOSITE (its owner recurses into the value
    // surface, where the nine un-widened gates throw) or a form whose host lowering is not a plan-row
    // owner at all. None is "not yet supported" — each is a body whose bytes this door cannot promise.
    static func IsDeclinedExpressionKind(kind: int): bool {
        // 5 NullLiteral (the host's target-typed kind-20 pre-pass owns it), 7 Parenthesized (recurses),
        // 8 MemberAccess, 10 IndexAccess — every one a composite that recurses into the shared value
        // dispatcher, whose routing this door does not reproduce. 9 Call LEFT THIS LIST in `015-B7`;
        // parenthesised forms stay here because the owner's own `UnwrapParentheses` is reached through
        // its root facade and this door dispatches on the OUTER kind, so `(f())` is the parenthesis
        // owner's shape rather than the call owner's.
        if kind == ColumnarExpressionNodeKind.NullLiteralExpression() || kind == ColumnarExpressionNodeKind.ParenthesizedExpression() || kind == ColumnarExpressionNodeKind.MemberAccessExpression() || kind == ColumnarExpressionNodeKind.IndexAccessExpression() {
            return true
        }
        // 12 Binary, 13 Ternary, 15 New, 16 Cast, 36 ObjectInitializer, 55 TypeOf, 58 ArrayLiteral,
        // 69 Range — the named composites. Their gates are widened now, but the emitter reaches each of
        // them through `ColumnarRangeIndexPlanner.TryEmitFromFacts`'s eleven-arm ROOT CASCADE, and a
        // claim here must reproduce that arm's exact entry — plus, for the binary and call owners, the
        // three binding facts this driver still does not route. Each arrives with its own corpus diff.
        if kind == ColumnarExpressionNodeKind.BinaryExpression() || kind == ColumnarExpressionNodeKind.TernaryExpression() || kind == ColumnarExpressionNodeKind.NewExpression() || kind == ColumnarExpressionNodeKind.CastExpression() || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression() {
            return true
        }
        if kind == ColumnarExpressionNodeKind.TypeOfExpression() || kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() || kind == ColumnarExpressionNodeKind.RangeExpression() {
            return true
        }
        // The kinds the parser produces in value position that have no named accessor on the ledger
        // class. They are spelled here exactly as `ColumnarIlEmitter.EmitExpressionCore` spells them.
        // 17 Tuple, 18 Match, 39 Lambda, 42 BareNew, 44 PostfixUnary, 45 Must.
        if kind == 17 || kind == 18 || kind == 39 || kind == 42 || kind == 44 || kind == 45 {
            return true
        }
        // 46 Is, 47 As, 52 With, 53 Await, 57 CheckedContext, 59 AnonymousObjectInitializer,
        // 64 SpreadArgument.
        return kind == 46 || kind == 47 || kind == 52 || kind == 53 || kind == 57 || kind == 59 || kind == 64
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
