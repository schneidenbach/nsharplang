namespace NSharpLang.Compiler.Columnar


// WHICH NODE KINDS ARE A LAMBDA LITERAL.
//
// A lambda has two kinds because `async` changes what its body MEANS, not what its body looks like:
// kind 39 is `x => …` and kind 78 is `async x => …`, with identical children (the parameter
// identifiers, then the body) and identical spans. Every reader that only wants to know "is this a
// lambda" — the capture scan, the argument-shape tests, the contextual-signature planner, the walkers
// that step over one — asks `IsLambda`, so adding the async spelling could not silently leave one of
// them behind. Only the two places where the difference is real — the body's expected type and the
// method the body is emitted into — ask `IsAsyncLambda`.
class ColumnarLambdaNodeFacts {

    // The lambda literal kinds, as the parser emits them.
    static func IsLambda(kind: int): bool => kind == 39 || kind == 78

    // Whether any argument child of a call node is a lambda literal. Keeping the child walk here
    // makes the explicit generic-call paths use the same lambda shape fact as the rest of the emitter.
    static func ArgumentsCarryLambda(nodes: ColumnarNodeTable, callIndex: int, argumentCount: int): bool {
        if nodes == null || callIndex < 0 || callIndex >= nodes.Kinds.Length || argumentCount <= 0 || argumentCount + 1 > nodes.ChildCount(callIndex) {
            return false
        }

        argumentIndex := 0
        while argumentIndex < argumentCount {
            if IsLambda(nodes.Kind(nodes.Child(callIndex, 1 + argumentIndex))) {
                return true
            }
            argumentIndex = argumentIndex + 1
        }

        return false
    }

    // `async x => …`: the body's value is what the target delegate's task-like return WRAPS, and the
    // body is emitted with an async return shape and a fault guard.
    static func IsAsyncLambda(kind: int): bool => kind == 78
}
