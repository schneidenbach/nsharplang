namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE RULES A DECLARED PARAMETER LIST MUST SATISFY BEFORE ANY NAME IN IT EXISTS.
//
// Every declaration in the language that HAS a parameter list runs these: a function, a local
// function, a class, struct or record primary constructor, an indexer, a constructor, and a test
// declaration. They are asked BEFORE the parameters are declared into a scope, so a list that is
// malformed is reported against the LIST rather than against whatever the names later resolve to.
//
// ONLY THE `params` HALF LIVES HERE, AND THAT IS A MEASUREMENT RATHER THAN A PREFERENCE. The
// default-value half asks whether a defaulted parameter's value is something the compiler can
// evaluate, and its SoA arm answers that by RE-ENTERING the analyzer's target-typed expression walk
// and counting the diagnostics it produced — an operation N# cannot perform for itself and which
// none of the eight callers is driven well enough to relay. The `params` half asks two questions that
// are pure functions of the list and of one type REFERENCE: that a `params` parameter comes last, and
// that its declared type is one a `params` may have. Both spans come from the parameter itself when
// it has a position and from the declaration otherwise.
class AnalyzerParameterDeclarations {
    diagnosticsValue: AnalyzerDiagnosticSink

    constructor(diagnostics: AnalyzerDiagnosticSink) {
        diagnosticsValue = diagnostics
    }

    // BOTH `params` RULES, APPLIED TO EVERY `params` PARAMETER IN THE LIST. A list with two of them
    // reports twice, and a single misplaced one with a bad type reports BOTH of its faults — the
    // position rule does not silence the type rule, because they are different mistakes and an
    // author fixing one would otherwise be told about the other only on the next build.
    func ValidateParamsParameters(parameters: List<Parameter>, line: int, column: int) {
        index := 0
        while index < parameters.Count {
            parameter := parameters[index]
            if parameter.Modifier == ParameterModifier.Params {
                span := AnalyzerDiagnosticSpanFacts.GetParameterDiagnosticSpan(parameter, line, column)
                if index != parameters.Count - 1 {
                    diagnosticsValue.Report(ErrorCode.ParamsNotLast, "A 'params' parameter must come last in the parameter list — move it to the end", span.Line, span.Column, null, span.Length)
                }

                if !TypeReferenceFacts.IsValidParamsType(parameter.Type) {
                    typeName := TypeReferenceFacts.GetDisplayName(parameter.Type)
                    diagnosticsValue.Report(ErrorCode.InvalidParameter, "A 'params' parameter must be an array or collection type — '" + typeName + "' is not a valid params type", span.Line, span.Column, null, span.Length)
                }
            }

            index = index + 1
        }
    }
}
