namespace NSharpLang.CensusParseShapes.Tests


test "expression bodies continue after an arrow and a trailing operator across declaration kinds" {
    assert TopLevelArrowBody() == "top-level"
    assert TopLevelOperatorContinuation() == "left-right"
    assert LeadingMemberContinuation() == "MEMBER"
    assert LeadingNullConditionalContinuation(null) == 0
    assert LeadingNullConditionalContinuation("abc") == 3

    owner := new ExpressionBodyOwner()
    assert owner.MethodArrowBody() == "method"
    assert owner.MethodOperatorContinuation() == "method-body"
    assert owner.PropertyArrowBody == "property"
    assert owner.PropertyOperatorContinuation == "property-body"
}

test "local functions and statements keep their existing line continuation behavior" {
    assert LocalAndStatementControls() == "local:statement-continuation"
}
