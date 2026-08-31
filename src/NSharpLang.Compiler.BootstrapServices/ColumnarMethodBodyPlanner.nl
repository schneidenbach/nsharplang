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

        value := nodes.Child(statement, 0)
        kind := nodes.Kind(value)
        plan.PrepareMethodBody()
        valueType := typeof(int)
        if ColumnarScalarLiteralPlanner.IsOwnedLiteralKind(kind) {
            if !ColumnarScalarLiteralPlanner.TryAppendLiteral(nodes, source, value, plan, out valueType) {
                return false
            }
        } else if kind == ColumnarExpressionNodeKind.BoolLiteralExpression() {
            if !ColumnarBooleanLiteralPlanner.TryAppendLiteral(nodes, source, value, plan) {
                return false
            }
            valueType = typeof(bool)
        } else if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            bindings := ColumnarFragmentBindings.FromRawFacts(parameterOrdinals, parameterTypes, locals, enums, liftedLocals, boxedCaptures, currentInstance, sourceTypeDefinitions, sourceUnionDefinitions, tupleNames, enclosingNames, siblingNames, visibleLocalFunctionNames, typeParameters)
            bindings.SetEnclosingTypeDefinition(enclosingTypeDefinition)
            if !TryAppendParameterRead(nodes, source, value, bindings, plan, out valueType) {
                return false
            }
        } else {
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

    // THE PARAMETER CLASS (P). `ColumnarBoundIdentifierPlanner` is the SOLE owner of lexical
    // identifier-value reads, and the production expression path already routes every bare identifier
    // through it — `EmitExpressionCore` calls `ColumnarRangeIndexPlanner.TryEmitFromFacts` before its
    // own switch, and that facade admits `IdentifierExpression` unconditionally. So this driver calls
    // the SAME owner rather than reproducing it, which is what makes the claim byte-identical BY
    // CONSTRUCTION rather than by imitation — including the argument narrowing, since both sides reach
    // `ColumnarCodePlanExecutor.EmitArgument` and therefore agree at every ordinal, not just 0..3.
    //
    // The resolve runs FIRST and is pure, so a selection this driver does not claim never mutates the
    // plan. ONLY `Parameter` is claimed: BoxedCapture, LiftedLocal, Local, ByRefParameter, CurrentField
    // and CurrentProperty each decline to the host, because each is its own claim class and owes its
    // own corpus diff.
    static func TryAppendParameterRead(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        selection := ColumnarBoundIdentifierPlanner.EmptySelection()
        if !ColumnarBoundIdentifierPlanner.TryResolve(nodes, source, node, bindings, out selection) {
            return false
        }
        if selection.Kind != ColumnarBoundIdentifierKind.Parameter {
            return false
        }

        return ColumnarBoundIdentifierPlanner.TryAppend(nodes, source, node, bindings, plan, out resultType)
    }
}
