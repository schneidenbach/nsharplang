namespace NSharpLang.Compiler.Columnar

import System


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

    // THE FIRST ORDINARY-USER-BODY DRIVER.
    //
    // Claims a body that is a BLOCK (25) whose single statement is a RETURN (20) of ONE scalar literal
    // whose NATURAL type equals the declared return type EXACTLY, and plans it as `<literal rows>; ret`
    // in one schema-v4 method body. `plan` is supplied by the caller and is only meaningful when this
    // returns true; a decline leaves it unusable rather than half-built, which is why the caller is
    // expected to discard it.
    //
    // THE CLAIM RULE IS TYPE *EQUALITY*, NOT ASSIGNABILITY, AND THAT IS THE POINT. The host's kind-20
    // arm runs SEVEN target-typed pre-passes before it evaluates the expression and SEVEN coercions
    // after it, and one of the pre-passes — the int-literal adoption that turns `return 5` on a `long`
    // function into `ldc.i8` — would emit DIFFERENT rows than the literal owner does. Equality is what
    // makes all fourteen provably unreached: an unsuffixed integer literal is natural-`int`, and the
    // adoption pre-pass declines a target of `int`; `5L`/`5UL` are natural-`long`/`ulong` but carry a
    // suffix, which the pre-pass also declines. A body outside the claim is not "not yet supported" —
    // it is a body whose bytes this driver cannot promise, so it declines and the host emits it.
    //
    // The accepted shape can contain no lambda, no local, no branch and no exception region, so a
    // claimed body needs NO emitter state at all — which is what lets the front door stand ahead of
    // every field the host's body emission would otherwise have to set up first.
    static func TryPlanLiteralReturnBody(nodes: ColumnarNodeTable, source: string, bodyRoot: int, returnType: Type, plan: ColumnarCodePlan): bool {
        if nodes == null || source == null || returnType == null || plan == null {
            return false
        }
        if bodyRoot < 0 || bodyRoot >= nodes.Kinds.Length {
            return false
        }
        if nodes.Kind(bodyRoot) != 25 || nodes.ChildCount(bodyRoot) != 1 {
            return false
        }

        statement := nodes.Child(bodyRoot, 0)
        if nodes.Kind(statement) != 20 || nodes.ChildCount(statement) != 1 {
            return false
        }

        value := nodes.Child(statement, 0)
        if !ColumnarScalarLiteralPlanner.IsOwnedLiteralKind(nodes.Kind(value)) {
            return false
        }

        plan.PrepareMethodBody()
        literalType := typeof(int)
        if !ColumnarScalarLiteralPlanner.TryAppendLiteral(nodes, source, value, plan, out literalType) {
            return false
        }
        if literalType != returnType {
            return false
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        plan.CompleteMethodBody(returnType)
        return true
    }
}
