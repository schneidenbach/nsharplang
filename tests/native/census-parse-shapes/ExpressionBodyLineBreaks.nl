namespace NSharpLang.CensusParseShapes.Tests


func TopLevelArrowBody(): string =>
    "top-level"

func TopLevelOperatorContinuation(): string => "left-" +
    "right"

func LeadingMemberContinuation(): string => "member"
    .ToUpperInvariant()

func LeadingNullConditionalContinuation(value: string?): int =>
    value
        ?.Length ?? 0

class ExpressionBodyOwner {
    func MethodArrowBody(): string =>
        "method"

    func MethodOperatorContinuation(): string => "method-" +
        "body"

    PropertyArrowBody: string =>
        "property"

    PropertyOperatorContinuation: string => "property-" +
        "body"
}

func LocalAndStatementControls(): string {
    func LocalArrowBody(): string =>
        "local"

    statementValue := "statement-" +
        "continuation"
    return LocalArrowBody() + ":" + statementValue
}
