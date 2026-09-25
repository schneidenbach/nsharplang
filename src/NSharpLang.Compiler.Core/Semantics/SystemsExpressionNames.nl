namespace NSharpLang.Compiler.Performance

import NSharpLang.Compiler.Ast


// THE TWO NAMES SYSTEMS POLICY GIVES AN EXPRESSION, AND WHY NEITHER IS THE ONE ANOTHER OWNER ALREADY
// COMPUTES.
//
// `SystemsTypeNames` answers what a TYPE is called; this owner answers what an EXPRESSION is called.
// Every systems rule that classifies a call — is it a pool rent, a concurrency primitive, a
// reflection call, a resource factory — matches a written NAME against a table, and every rule that
// remembers a receiver across statements — the guard proofs, the `TryGetValue` narrowing — needs a
// stable KEY for one. Both answers are lossy in a chosen direction, and neither is a display name.
//
// A CALL TARGET IS THE WHOLE DOTTED PATH, NOT THE LAST SEGMENT. `File.Open` must not classify as
// `Open`, because the tables are keyed by receiver-and-member together and half of them list the
// namespace-qualified spelling beside the bare one. This is what separates `CallTarget` from the
// already-N#-owned `AnalyzerSyntheticCallFacts.GetCallTargetName`, which returns exactly the last
// segment because it is naming a function for a diagnostic sentence. The two agree on a bare
// identifier and DISAGREE on every dotted callee, so they are not interchangeable and neither is
// redundant.
//
// A CALL TARGET IS NULL WHEN THE CALLEE IS NOT WRITTEN AS A NAME. An invoked element of an array of
// delegates, a call on an index expression, a call on a call — none of them names a target, and the
// analyzer reports that as `<dynamic call>` rather than inventing a name for it. Parentheses are
// transparent: `(f)()` targets `f`.
//
// AN EXPRESSION KEY IS TOTAL WHERE A CALL TARGET IS PARTIAL, AND THAT IS THE WHOLE DIFFERENCE. A key
// must exist for every expression, because it is a dictionary key for a receiver the walk will meet
// again; so anything that is not a name falls back to its own SOURCE POSITION, `@line:column`, which
// is unique per site and therefore never collides two different receivers into one fact. `this` keys
// as `this`. Parentheses are NOT transparent here — `(x).Length` and `x.Length` are different sites
// and a position-keyed fallback is only sound if it is taken consistently.
//
// THE TWO INTERLEAVE, AND THE INTERLEAVE IS LOAD-BEARING. `CallTarget` falls back to `ExpressionKey`
// for the RECEIVER of a member access it cannot name, so `buffers[0].Dispose()` targets
// `@7:12.Dispose` rather than nothing: the call is still classified by its member name against every
// table, while the receiver stays distinguishable from any other. Replacing that fallback with a null
// would silence the resource and pool rules on every indexed receiver.
//
// `AnalyzerDiagnosticSpans.TryGetStableNullPath` is the third near-duplicate and also disagrees: it
// returns NULL where this returns a position key, it sees THROUGH parentheses, and it refuses a
// null-conditional hop. Contracts assert all three disagreements rather than describing them.
class SystemsExpressionNames {

    // The name WRITTEN at a call site, dotted receiver included, or null when the callee is not
    // written as a name at all.
    static func CallTarget(callee: Expression): string? {
        identifier := callee as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        member := callee as MemberAccessExpression
        if member != null {
            receiver := CallTarget(member.Object)
            if receiver == null {
                receiver = ExpressionKey(member.Object)
            }

            return receiver + "." + member.MemberName
        }

        parenthesized := callee as ParenthesizedExpression
        if parenthesized != null {
            return CallTarget(parenthesized.Inner)
        }

        return null
    }

    // A stable key for any expression: the written path where there is one, the source position where
    // there is not. Never null.
    static func ExpressionKey(expression: Expression): string {
        identifier := expression as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        member := expression as MemberAccessExpression
        if member != null {
            return ExpressionKey(member.Object) + "." + member.MemberName
        }

        thisExpression := expression as ThisExpression
        if thisExpression != null {
            return "this"
        }

        return "@" + expression.Line.ToString() + ":" + expression.Column.ToString()
    }
}
