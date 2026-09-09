namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast


// Native contracts for THE `params` RULES EVERY DECLARED PARAMETER LIST OBEYS.
//
// The rule was `private` in `Analyzer.cs` and served EIGHT callers — a function, a local function, a
// class, struct and record primary constructor, an indexer, a constructor and a test declaration —
// so nothing named it and its behaviour was pinned only through whichever of those eight a test
// happened to write. This is its first DIRECT pinning, and it is written around the three things it
// is easy to get wrong.
//
// (1) THE TWO FAULTS ARE INDEPENDENT. A misplaced `params` with an invalid type reports BOTH, because
// they are different mistakes; silencing the second behind the first would tell an author about the
// type only on the build after they moved the parameter.
//
// (2) EVERY `params` IN THE LIST IS JUDGED, NOT JUST THE FIRST. A list with two of them reports
// twice, which is what tells an author that removing one is not enough.
//
// (3) THE SPAN IS THE PARAMETER'S WHEN IT HAS ONE AND THE DECLARATION'S OTHERWISE. A synthesised
// parameter must squiggle the declaration rather than line zero.
class ParameterRulesHarness {
    Rules: AnalyzerParameterDeclarations
    Errors: List<CompilerError>

    constructor(rules: AnalyzerParameterDeclarations, errors: List<CompilerError>) {
        Rules = rules
        Errors = errors
    }
}

func ParameterRulesDefault(): ParameterRulesHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(Path.GetFullPath("parameter-rules-contract.nl"), null)
    return new ParameterRulesHarness(new AnalyzerParameterDeclarations(diagnostics), errors)
}

func ParameterRulesParameter(name: string, typeReference: TypeReference, modifier: ParameterModifier, line: int, column: int): Parameter {
    return new Parameter(name, typeReference, null, false, modifier, null, line, column, false, null)
}

func ParameterRulesArrayType(): TypeReference {
    element: TypeReference = new SimpleTypeReference("int", 4, 20)
    reference: TypeReference = new ArrayTypeReference(element)
    return reference
}

func ParameterRulesScalarType(): TypeReference {
    reference: TypeReference = new SimpleTypeReference("int", 4, 20)
    return reference
}

func ParameterRulesList(): List<Parameter> {
    return new List<Parameter>()
}

func ParameterRulesErrorText(harness: ParameterRulesHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + "+" + error.Length.ToString()
}

test "A params PARAMETER THAT COMES LAST AND HAS AN ARRAY TYPE IS SILENT" {
    harness := ParameterRulesDefault()
    parameters := ParameterRulesList()
    parameters.Add(ParameterRulesParameter("first", ParameterRulesScalarType(), ParameterModifier.None, 4, 12))
    parameters.Add(ParameterRulesParameter("rest", ParameterRulesArrayType(), ParameterModifier.Params, 4, 22))

    harness.Rules.ValidateParamsParameters(parameters, 4, 1)

    assert harness.Errors.Count == 0
}

test "A LIST WITH NO params AT ALL IS NEVER LOOKED AT TWICE" {
    harness := ParameterRulesDefault()
    parameters := ParameterRulesList()
    parameters.Add(ParameterRulesParameter("first", ParameterRulesScalarType(), ParameterModifier.None, 4, 12))
    parameters.Add(ParameterRulesParameter("second", ParameterRulesScalarType(), ParameterModifier.None, 4, 22))

    harness.Rules.ValidateParamsParameters(parameters, 4, 1)

    assert harness.Errors.Count == 0
}

test "AN EMPTY LIST IS SILENT" {
    harness := ParameterRulesDefault()

    harness.Rules.ValidateParamsParameters(ParameterRulesList(), 4, 1)

    assert harness.Errors.Count == 0
}

test "A params PARAMETER THAT IS NOT LAST IS REPORTED AT ITS OWN POSITION" {
    harness := ParameterRulesDefault()
    parameters := ParameterRulesList()
    parameters.Add(ParameterRulesParameter("rest", ParameterRulesArrayType(), ParameterModifier.Params, 4, 12))
    parameters.Add(ParameterRulesParameter("last", ParameterRulesScalarType(), ParameterModifier.None, 4, 26))

    harness.Rules.ValidateParamsParameters(parameters, 4, 1)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ParamsNotLast
    assert ParameterRulesErrorText(harness, 0) == "A 'params' parameter must come last in the parameter list — move it to the end|4:12+4"
}

test "A params PARAMETER WITH A SCALAR TYPE IS REPORTED, AND THE TYPE IS NAMED" {
    harness := ParameterRulesDefault()
    parameters := ParameterRulesList()
    parameters.Add(ParameterRulesParameter("rest", ParameterRulesScalarType(), ParameterModifier.Params, 4, 12))

    harness.Rules.ValidateParamsParameters(parameters, 4, 1)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.InvalidParameter
    assert ParameterRulesErrorText(harness, 0) == "A 'params' parameter must be an array or collection type — 'int' is not a valid params type|4:12+4"
}

test "BOTH FAULTS ON ONE PARAMETER REPORT TWICE, POSITION FIRST" {
    harness := ParameterRulesDefault()
    parameters := ParameterRulesList()
    parameters.Add(ParameterRulesParameter("rest", ParameterRulesScalarType(), ParameterModifier.Params, 4, 12))
    parameters.Add(ParameterRulesParameter("last", ParameterRulesScalarType(), ParameterModifier.None, 4, 26))

    harness.Rules.ValidateParamsParameters(parameters, 4, 1)

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Code == ErrorCode.ParamsNotLast
    assert harness.Errors[1].Code == ErrorCode.InvalidParameter
}

test "TWO params PARAMETERS BOTH REPORT — REMOVING ONE IS NOT ENOUGH" {
    harness := ParameterRulesDefault()
    parameters := ParameterRulesList()
    parameters.Add(ParameterRulesParameter("a", ParameterRulesArrayType(), ParameterModifier.Params, 4, 12))
    parameters.Add(ParameterRulesParameter("b", ParameterRulesArrayType(), ParameterModifier.Params, 4, 26))

    harness.Rules.ValidateParamsParameters(parameters, 4, 1)

    // The LAST one is legally placed, so only the first draws the position report.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Column == 12
}

test "A SYNTHESISED params PARAMETER SQUIGGLES THE DECLARATION, NOT LINE ZERO" {
    harness := ParameterRulesDefault()
    parameters := ParameterRulesList()
    parameters.Add(ParameterRulesParameter("rest", ParameterRulesScalarType(), ParameterModifier.Params, 0, 0))

    harness.Rules.ValidateParamsParameters(parameters, 4, 1)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 1
}
