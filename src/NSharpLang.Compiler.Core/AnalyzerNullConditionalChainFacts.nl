namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// WHERE A `?.` CHAIN BEGINS AND HOW FAR TO THE RIGHT IT REACHES.
//
// `a?.B.C` IS ONE EXPRESSION, NOT TWO. The `?` tests `a`; everything written to its right is the
// chain's CONTINUATION and is evaluated only when that test passed. Two consequences follow, and
// both of them are what this owner exists to answer.
//
// A CONTINUATION LINK IS NOT A DEREFERENCE OF A MAYBE-NULL VALUE. `.C` in `a?.B.C` never runs with
// a null receiver, so NL905 must stay silent on it. Reading `a?.B` as an ordinary maybe-null value
// and then complaining about `.C` describes a program that cannot happen.
//
// THE WHOLE CHAIN'S RESULT IS LIFTED, ONCE. `a?.B.C` is `C?` — the chain produces the member's type
// when the test passed and null when it did not, so a REFERENCE result becomes maybe-null and a
// VALUE result becomes `Nullable<T>`. `s?.Trim()` is `string?` for the same reason: an invocation
// whose callee spine crosses a `?.` is itself part of the chain.
//
// A PARENTHESIS ENDS THE CHAIN, and that is why the walk does not step through one. `(a?.B).C` is
// written as a dereference of a maybe-null value and C# reads it as exactly that; not walking the
// parenthesis is what makes the analyzer agree. The emitter's chain-root test says the same thing
// in the same words, so the two halves of the feature cannot drift apart.
//
// THE WALK IS BOUNDED because it follows a receiver spine that a recovery parse can, in principle,
// hand back cyclic; the bound is the same 64 links the callee-spine test has always used and is far
// past any chain a human writes.
class AnalyzerNullConditionalChainFacts {

    // Whether a null-conditional access anywhere along this expression's RECEIVER SPINE guards it.
    // The walk follows the receiver of a member access, of an index access and of a nested call, and
    // stops at anything else — an identifier, a literal, a parenthesised group — because none of
    // those can carry a `?.` that would guard what follows.
    static func SpineReachesNullGuard(expression: Expression?): bool {
        current := expression
        depth := 0
        while current != null && depth < 64 {
            member := current as MemberAccessExpression
            if member != null {
                if member.IsNullConditional {
                    return true
                }

                current = member.Object
                depth = depth + 1
                continue
            }

            indexAccess := current as IndexAccessExpression
            if indexAccess != null {
                if indexAccess.IsNullConditional {
                    return true
                }

                current = indexAccess.Object
                depth = depth + 1
                continue
            }

            nestedCall := current as CallExpression
            if nestedCall != null {
                current = nestedCall.Callee
                depth = depth + 1
                continue
            }

            return false
        }

        return false
    }

    // Whether a member access is a continuation link — a `.` written to the right of a `?.` in the
    // same chain. Its own `?` is what distinguishes the two: a link that carries one is the guard
    // itself and is judged as such, not as a continuation of an earlier guard.
    static func IsMemberContinuation(member: MemberAccessExpression): bool {
        return !member.IsNullConditional && SpineReachesNullGuard(member.Object)
    }

    // The same question for an index link: `a?.B[0]` indexes a value the chain already proved.
    static func IsIndexContinuation(indexAccess: IndexAccessExpression): bool {
        return !indexAccess.IsNullConditional && SpineReachesNullGuard(indexAccess.Object)
    }
}
