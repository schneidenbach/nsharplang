namespace NSharpLang.Compiler.Columnar

import System

// THE WALKS AND GUARDS EVERY FRAGMENT PLANNER NEEDED, OWNED ONCE.
//
// There is no planner interface — the cascade in `ColumnarMethodBodyPlanner` calls each planner's
// static entry BY NAME, and its order is load-bearing — so every planner grew its own private copy
// of the same few helpers: ten `UnwrapParentheses`, thirteen `RequiredResultType`, three
// `TryGetQualifiedName`, two `TryGetNodeText`. They were not quite identical, and that is the point:
// the ten parenthesis walks had drifted into three spellings, and one of the three qualified-name
// walks had lost an `explicit this` rejection the other two kept.
//
// Nothing here decides anything a planner decides. It holds the shapes that are the SAME question
// for all of them, with every difference that was real turned into an argument rather than erased:
// the two walks that also range-check their answer say so by name, the thirteen "no result type"
// messages keep their own words, and the qualified-name walk takes the `explicit this` rule as a
// parameter instead of silently acquiring or losing it.
//
// This is not the planner interface (that needs explicit interface implementation, and it is the
// cleanup the interface unlocks). It is the part that needs no interface at all.
static class ColumnarPlannerSupport {

    // ── PARENTHESES ───────────────────────────────────────────────────────────
    //
    // `(((x)))` is `x`. The depth cap is 200 and a parenthesized node with anything other than one
    // child is malformed; both answer -1, which every caller already reads as "not a node".
    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }

            node = nodes.Child(node, 0)
            depth = depth + 1
        }

        return node
    }

    // THE SAME WALK, PLUS THE RANGE CHECK THREE OF THE TEN COPIES ALSO DID. The loop stops on a node
    // that is out of range as readily as on one that is not parenthesized, so the plain walk can
    // hand back the out-of-range index it stopped at; these three callers asked for -1 instead. The
    // difference is preserved rather than decided.
    static func UnwrapParenthesesInRange(nodes: ColumnarNodeTable, node: int): int {
        unwrapped := UnwrapParentheses(nodes, node)
        if unwrapped < 0 || unwrapped >= nodes.Kinds.Length {
            return -1
        }

        return unwrapped
    }

    // ── PLANNED RESULTS ───────────────────────────────────────────────────────
    //
    // A plan that reached emission without a result type is a planner defect, and the message names
    // the planner so the defect is attributable. `planned` is that planner's own noun — "boolean
    // literal", "direct call" — so each of the thirteen messages reads exactly as it read before.
    static func RequiredResultType(plan: ColumnarCodePlan, planned: string): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException("Planned " + planned + " has no result type.")
        }

        return resultType
    }

    // ── INPUT GUARDS ──────────────────────────────────────────────────────────
    //
    // The guards take the WHOLE message rather than a subject, because the planners do not agree on
    // one sentence: some say "inputs cannot be null", some "inputs and binding facts cannot be
    // null"; some say "an invalid node index" and some "an invalid root node index". What they agree
    // on is the shape, and the shape is what is owned here.
    static func RequirePresent(present: bool, message: string) {
        if !present {
            throw new InvalidOperationException(message)
        }
    }

    static func RequireNodeInRange(nodes: ColumnarNodeTable, node: int, message: string) {
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException(message)
        }
    }

    // ── NAMES AND TEXT ────────────────────────────────────────────────────────
    //
    // `a.b.c` read off a member-access chain, with the root (`a`) reported separately because every
    // caller then asks the bindings whether the root is a local value or a callable before treating
    // the chain as a type name.
    //
    // `rejectExplicitThis` is the one difference between the three copies: two refused a chain whose
    // root is an explicit `this` and the range/index copy did not. That is a behaviour difference,
    // not a cosmetic one, so it is an argument and each caller keeps the answer it had.
    static func TryGetQualifiedName(nodes: ColumnarNodeTable, source: string, node: int, depth: int, rejectExplicitThis: bool, out qualifiedName: string, out rootName: string): bool {
        qualifiedName = ""
        rootName = ""
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.IdentifierExpression() {
            if nodes.ChildCount(node) != 0 || (rejectExplicitThis && ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, node)) {
                return false
            }

            rootName = nodes.Text(source, node)
            qualifiedName = rootName
            return rootName.Length > 0
        }

        if kind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        prefix := ""
        if !TryGetQualifiedName(nodes, source, nodes.Child(node, 0), depth + 1, rejectExplicitThis, out prefix, out rootName) {
            return false
        }

        member := nodes.Text(source, node)
        if member.Length == 0 {
            return false
        }

        qualifiedName = prefix + "." + member
        return true
    }

    // A node's own source slice, refused rather than clamped when the recorded span does not fit the
    // source it is read against.
    static func TryGetNodeText(nodes: ColumnarNodeTable, source: string, node: int, out text: string): bool {
        text = ""
        start := nodes.ValueStart(node)
        length := nodes.ValueLengths[node]
        if start < 0 || length <= 0 || length > source.Length || start > source.Length - length {
            return false
        }

        text = source.Substring(start, length)
        return true
    }
}
