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
    // The accepted shapes can contain no lambda, no local, no branch and no exception region, so a
    // claimed body needs NO emitter state at all — which is what lets the front door stand ahead of
    // every field the host's body emission would otherwise have to set up first. In particular no
    // claimed shape can produce a LIFTED candidate (lifting requires a lambda), so reading the
    // caller's lifted map before it is computed cannot misresolve a claimed name.
    static func TryPlanBody(nodes: ColumnarNodeTable, source: string, bodyRoot: int, returnType: Type, isVoid: bool, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>, locals: Dictionary<string, LocalBuilder>, enums: Dictionary<string, ColumnarEnumDef>, liftedLocals: Dictionary<string, (Box: LocalBuilder, ValueType: Type)>, boxedCaptures: Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>?, currentInstance: ColumnarStructDef?, enclosingTypeDefinition: ColumnarStructDef?, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, sourceUnionDefinitions: IEnumerable<ColumnarUnionDef>, tupleNames: Dictionary<string, string[]>, enclosingNames: IEnumerable<string>, siblingNames: IEnumerable<string>, visibleLocalFunctionNames: IEnumerable<string>, typeParameters: Dictionary<string, Type>, plan: ColumnarCodePlan): bool {
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

        if nodes.ChildCount(bodyRoot) != 1 {
            return false
        }
        statement := nodes.Child(bodyRoot, 0)
        if nodes.Kind(statement) != 20 || nodes.ChildCount(statement) != 1 {
            return false
        }

        // The bindings are built ONCE, before the plan is opened, and handed to the expression door.
        // `FromRawFacts` wraps the caller's live dictionaries by reference and copies only the type
        // parameters (a handful of entries at most), so the cost is an allocation on the narrow set of
        // bodies that are already exactly `{ return <expression> }`. The statement loop will reuse this
        // one binding set across every statement rather than rebuilding it per row.
        value := nodes.Child(statement, 0)
        bindings := ColumnarFragmentBindings.FromRawFacts(parameterOrdinals, parameterTypes, locals, enums, liftedLocals, boxedCaptures, currentInstance, sourceTypeDefinitions, sourceUnionDefinitions, tupleNames, enclosingNames, siblingNames, visibleLocalFunctionNames, typeParameters)
        bindings.SetEnclosingTypeDefinition(enclosingTypeDefinition)

        plan.PrepareMethodBody()
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
    // ⚠ WHY EVERY CLAIMED KIND IS A LEAF, AND WHY THAT IS A MEASUREMENT RATHER THAN CAUTION. Nine of
    // the twelve owners on the value surface assert an open schema-**v3** plan in their own
    // `ValidateAppendInputs` and `throw` otherwise — a HARD CRASH out of the compiler, not a decline:
    // `ColumnarConstructionPlanner`, `ColumnarDirectCallPlanner`, `ColumnarExternalStaticMemberPlanner`,
    // `ColumnarInstanceMemberPlanner`, `ColumnarNameOfPlanner`, `ColumnarNullableArgumentLowering`,
    // `ColumnarUnaryLiteralPlanner`, `ColumnarPrimitiveBinaryPlanner` and `ColumnarTypeOfPlanner`. Only
    // `ColumnarScalarLiteralPlanner` and `ColumnarBoundIdentifierPlanner` are widened, and
    // `ColumnarConditionalPlanner` — which has no such gate — recurses its operands straight into the
    // nine. So a COMPOSITE claim (`return a + b`, `return f(x)`, `return cond ? a : b`) cannot be taken
    // until those nine gates are widened together: claiming one and pre-scanning its operands to prove
    // no un-widened owner is reachable would be a SECOND COPY of the dispatcher's routing decision.
    // Every kind claimed here appends its own rows and recurses into nothing.
    static func TryAppendReturnValue(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
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
        // 6 Identifier — four of the sole identifier owner's seven selection kinds.
        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            return TryAppendIdentifierRead(nodes, source, node, bindings, plan, out resultType)
        }
        // Unreachable while the claimed set and the arms above agree, and that agreement is exactly
        // what the estate's partition block asserts. A kind added to the claimed set without its own
        // arm lands here and DECLINES rather than silently taking a neighbouring owner's route.
        return false
    }

    // The kinds the door takes. Each is a LEAF whose owner is already method-body-schema aware.
    static func IsClaimedExpressionKind(kind: int): bool {
        return ColumnarScalarLiteralPlanner.IsOwnedLiteralKind(kind) || kind == ColumnarExpressionNodeKind.BoolLiteralExpression() || kind == ColumnarExpressionNodeKind.IdentifierExpression()
    }

    // The kinds the door refuses, named one by one rather than left to a fall-through. The reason is
    // uniform and worth stating once: each is either a COMPOSITE (its owner recurses into the value
    // surface, where the nine un-widened gates throw) or a form whose host lowering is not a plan-row
    // owner at all. None is "not yet supported" — each is a body whose bytes this door cannot promise.
    static func IsDeclinedExpressionKind(kind: int): bool {
        // 5 NullLiteral (the host's target-typed kind-20 pre-pass owns it), 7 Parenthesized (recurses),
        // 8 MemberAccess, 9 Call, 10 IndexAccess, 11 Unary — every one a composite.
        if kind == ColumnarExpressionNodeKind.NullLiteralExpression() || kind == ColumnarExpressionNodeKind.ParenthesizedExpression() || kind == ColumnarExpressionNodeKind.MemberAccessExpression() || kind == ColumnarExpressionNodeKind.CallExpression() || kind == ColumnarExpressionNodeKind.IndexAccessExpression() || kind == ColumnarExpressionNodeKind.UnaryExpression() {
            return true
        }
        // 12 Binary, 13 Ternary, 15 New, 16 Cast, 36 ObjectInitializer, 55 TypeOf, 58 ArrayLiteral,
        // 62 NameOf, 69 Range — the named composites, plus the two owners whose append entries exist
        // but whose gates are still v3-only.
        if kind == ColumnarExpressionNodeKind.BinaryExpression() || kind == ColumnarExpressionNodeKind.TernaryExpression() || kind == ColumnarExpressionNodeKind.NewExpression() || kind == ColumnarExpressionNodeKind.CastExpression() || kind == ColumnarExpressionNodeKind.ObjectInitializerExpression() {
            return true
        }
        if kind == ColumnarExpressionNodeKind.TypeOfExpression() || kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() || kind == ColumnarExpressionNodeKind.NameOfExpression() || kind == ColumnarExpressionNodeKind.RangeExpression() {
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
    // plan. FOUR of the owner's seven selection kinds are claimed:
    //
    //   P  Parameter        `ldarg <n>`                                   (015-B4)
    //   F  CurrentField     `ldarg.0; ldfld <f>`                          (015-B5)
    //   R  CurrentProperty  `ldarg.0; call|callvirt get_<p>`              (015-B5)
    //   X  ByRefParameter   `ldarg <n>; ldind.<t>`                        (015-B5)
    //
    // THE THREE UNCLAIMED ONES ARE UNREACHABLE, NOT UNTRUSTED, and that is the whole reason they wait:
    // `Local` needs a preceding declaration statement, `LiftedLocal` needs a lambda to lift into, and
    // `BoxedCapture` needs a closure display frame. None can occur in a body whose entire content is
    // one `return <identifier>`, so claiming them here would be a claim no corpus could exercise in
    // either direction. They arrive with the statement loop, which is what first makes them possible.
    //
    // The current-instance pair reads `bindings.CurrentInstance` and NOTHING else beyond what the
    // parameter class already read: `ExactSourceTypes`, the overflow flag and the sibling-callable
    // facts are consumed only by `TryResolveSelectedSourceType`, `ColumnarPrimitiveBinaryPlanner` and
    // `ColumnarDirectCallPlanner` respectively — all of them on the COMPOSITE surface this door
    // declines. So the three deliberately-unrouted facts stay unrouted, and become mandatory when a
    // composite class is claimed rather than when this filter widens.
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
        return selectionKind == ColumnarBoundIdentifierKind.Parameter || selectionKind == ColumnarBoundIdentifierKind.ByRefParameter || selectionKind == ColumnarBoundIdentifierKind.CurrentField || selectionKind == ColumnarBoundIdentifierKind.CurrentProperty
    }
}
