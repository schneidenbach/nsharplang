namespace NSharpLang.Compiler.Columnar

import System

// The single-parameter contextual-delegate return-type SELECTION owned by N#
// (ColumnarLambdaPlacementPlanner.PlanSingleParameterContextualReturnType): a selector/predicate
// argument's return type is not written in source; it is the type the argument's body produces. The
// host resolves the two admitted argument forms mechanically — a contextual lambda literal whose body
// it preflights, and a visible local-function method group — each gated to a supported non-void type,
// and passes null for a form that does not apply. N# owns which candidate the return type comes from:
// the lambda form takes precedence, and a pair of null candidates is the standard inference decline.

test "contextual return-type inference prefers the lambda body candidate over the local function" {
    lambdaCandidate := typeof(string)
    localCandidate := typeof(int)
    result := ColumnarLambdaPlacementPlanner.PlanSingleParameterContextualReturnType(lambdaCandidate, localCandidate)
    assert result == typeof(string)
}

test "contextual return-type inference falls back to the local-function candidate when no lambda applies" {
    noLambda: Type? = null
    localCandidate := typeof(int)
    result := ColumnarLambdaPlacementPlanner.PlanSingleParameterContextualReturnType(noLambda, localCandidate)
    assert result == typeof(int)
}

test "contextual return-type inference keeps lambda precedence when only the lambda applies" {
    lambdaCandidate := typeof(bool)
    noLocal: Type? = null
    result := ColumnarLambdaPlacementPlanner.PlanSingleParameterContextualReturnType(lambdaCandidate, noLocal)
    assert result == typeof(bool)
}

test "contextual return-type inference declines when neither argument form applies" {
    noLambda: Type? = null
    noLocal: Type? = null
    result := ColumnarLambdaPlacementPlanner.PlanSingleParameterContextualReturnType(noLambda, noLocal)
    assert result == null
}
