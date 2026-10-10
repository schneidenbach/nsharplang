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

    // `async x => …`: the body's value is what the target delegate's task-like return WRAPS, and the
    // body is emitted with an async return shape and a fault guard.
    static func IsAsyncLambda(kind: int): bool => kind == 78
}
