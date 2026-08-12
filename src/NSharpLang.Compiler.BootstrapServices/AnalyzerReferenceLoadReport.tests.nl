namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// Native contracts for WHEN A FAILED REFERENCE LOAD IS WORTH TELLING THE USER ABOUT.
//
// The member this replaces was `private` in `Analyzer.cs` with exactly one caller, and its rule was
// pinned only by whichever end-to-end compilation happened to fail a load AND fail a type lookup at
// the same time — which no test in the suite arranged. This is its first direct pinning, and it is
// written around the four things the rule is easy to get wrong.
//
// (1) THE PAIRING IS THE WHOLE POLICY. Failures alone say nothing; unresolved types alone say
// nothing; only both together produce NL923. A rule that reported on either half would make every
// healthy build noisy.
//
// (2) ONLY ERRORS COUNT, AND ONLY FOUR CODES. A warning carrying one of the four codes must not
// unlock the report, and an error carrying some other code must not either.
//
// (3) THE ANALYZER'S DETAIL BEATS THE RESOLVER'S for the same identity, because it describes the
// failure where the compiler actually needed the assembly.
//
// (4) THE ORDER IS ORDINAL BY IDENTITY, not the order the failures were recorded in — and because
// the order is written out here rather than delegated to a comparer, it is directly assertable.
class ReferenceReportHarness {
    Owner: AnalyzerReferenceLoadReport
    Errors: List<CompilerError>
    Sink: AnalyzerDiagnosticSink
    Failures: Dictionary<string, string>

    constructor(owner: AnalyzerReferenceLoadReport, errors: List<CompilerError>, sink: AnalyzerDiagnosticSink, failures: Dictionary<string, string>) {
        Owner = owner
        Errors = errors
        Sink = sink
        Failures = failures
    }
}

func ReferenceReportHarnessNew(): ReferenceReportHarness {
    errors := new List<CompilerError>()
    provider := new AnalyzerProjectSourceProvider()
    provider.BeginAnalysis("reference-report-root")
    sink := new AnalyzerDiagnosticSink(errors, provider)
    sink.BeginAnalysis("Program.nl", null)
    failures := new Dictionary<string, string>(StringComparer.Ordinal)
    owner := new AnalyzerReferenceLoadReport(sink, failures)
    return new ReferenceReportHarness(owner, errors, sink, failures)
}

// An unresolved-type ERROR of the kind a failed load actually causes.
func ReportUnresolvedType(harness: ReferenceReportHarness) {
    harness.Sink.Report(ErrorCode.TypeNotFound, "type not found", 3, 5, null, 4)
}

func ReferenceWarnings(harness: ReferenceReportHarness): List<CompilerError> {
    found := new List<CompilerError>()
    index := 0
    while index < harness.Errors.Count {
        candidate := harness.Errors[index]
        if candidate.Code == ErrorCode.ReferenceLoadFailure {
            found.Add(candidate)
        }

        index = index + 1
    }

    return found
}

// ---- (1) the pairing rule --------------------------------------------------------------------

test "a failure with no unresolved-type error reports nothing" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Alpha"] = "boom"
    harness.Owner.Report(null)
    assert ReferenceWarnings(harness).Count == 0
}

test "an unresolved-type error with no failure reports nothing" {
    harness := ReferenceReportHarnessNew()
    ReportUnresolvedType(harness)
    harness.Owner.Report(null)
    assert ReferenceWarnings(harness).Count == 0
}

test "a failure AND an unresolved-type error together report once" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Alpha"] = "boom"
    ReportUnresolvedType(harness)
    harness.Owner.Report(null)
    warnings := ReferenceWarnings(harness)
    assert warnings.Count == 1
    assert warnings[0].Message == "Reference assembly 'Alpha' could not be loaded or fully inspected (boom); types from it may be reported as not found."
}

test "the report lands at line 1 column 1, because it belongs to the compilation and not to a line" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Alpha"] = "boom"
    ReportUnresolvedType(harness)
    harness.Owner.Report(null)
    warnings := ReferenceWarnings(harness)
    assert warnings.Count == 1
    assert warnings[0].Line == 1
    assert warnings[0].Column == 1
}

test "the report is a WARNING, not an error" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Alpha"] = "boom"
    ReportUnresolvedType(harness)
    harness.Owner.Report(null)
    warnings := ReferenceWarnings(harness)
    assert warnings.Count == 1
    assert warnings[0].Severity == ErrorSeverity.Warning
}

test "an empty resolver table is the same as no resolver at all" {
    harness := ReferenceReportHarnessNew()
    empty := new Dictionary<string, string>(StringComparer.Ordinal)
    harness.Owner.Report(empty)
    assert ReferenceWarnings(harness).Count == 0
}

// ---- (2) which diagnostics unlock the report ---------------------------------------------------

test "all four unresolved codes unlock the report" {
    codes := new List<ErrorCode>()
    codes.Add(ErrorCode.TypeNotFound)
    codes.Add(ErrorCode.CannotResolveType)
    codes.Add(ErrorCode.UndefinedType)
    codes.Add(ErrorCode.UndefinedVariable)
    index := 0
    while index < codes.Count {
        harness := ReferenceReportHarnessNew()
        harness.Failures["Alpha"] = "boom"
        harness.Sink.Report(codes[index], "unresolved", 1, 1, null, 1)
        harness.Owner.Report(null)
        assert ReferenceWarnings(harness).Count == 1
        index = index + 1
    }
}

test "an error of some OTHER code does not unlock the report" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Alpha"] = "boom"
    harness.Sink.Report(ErrorCode.DuplicateDeclaration, "duplicate", 1, 1, null, 1)
    harness.Owner.Report(null)
    assert ReferenceWarnings(harness).Count == 0
}

test "a WARNING carrying one of the four codes does not unlock the report" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Alpha"] = "boom"
    harness.Sink.Warn(ErrorCode.TypeNotFound, "type not found", 1, 1, null, 1)
    harness.Owner.Report(null)
    assert ReferenceWarnings(harness).Count == 0
}

// ---- (3) the merge, and whose detail wins --------------------------------------------------------

test "a resolver failure alone can unlock and produce the report" {
    harness := ReferenceReportHarnessNew()
    resolver := new Dictionary<string, string>(StringComparer.Ordinal)
    resolver["Beta"] = "probe missed"
    ReportUnresolvedType(harness)
    harness.Owner.Report(resolver)
    warnings := ReferenceWarnings(harness)
    assert warnings.Count == 1
    assert warnings[0].Message == "Reference assembly 'Beta' could not be loaded or fully inspected (probe missed); types from it may be reported as not found."
}

test "for one identity in BOTH tables the ANALYZER's detail wins" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Shared"] = "analyzer detail"
    resolver := new Dictionary<string, string>(StringComparer.Ordinal)
    resolver["Shared"] = "resolver detail"
    ReportUnresolvedType(harness)
    harness.Owner.Report(resolver)
    warnings := ReferenceWarnings(harness)
    assert warnings.Count == 1
    assert warnings[0].Message.Contains("analyzer detail")
    assert !warnings[0].Message.Contains("resolver detail")
}

test "distinct identities from both tables are all reported, once each" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Alpha"] = "a"
    resolver := new Dictionary<string, string>(StringComparer.Ordinal)
    resolver["Beta"] = "b"
    ReportUnresolvedType(harness)
    harness.Owner.Report(resolver)
    assert ReferenceWarnings(harness).Count == 2
}

// ---- (4) the order ---------------------------------------------------------------------------------

test "the reports come out in ORDINAL identity order, not insertion order" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["Zeta"] = "z"
    harness.Failures["Alpha"] = "a"
    harness.Failures["Mid"] = "m"
    ReportUnresolvedType(harness)
    harness.Owner.Report(null)
    warnings := ReferenceWarnings(harness)
    assert warnings.Count == 3
    assert warnings[0].Message.Contains("'Alpha'")
    assert warnings[1].Message.Contains("'Mid'")
    assert warnings[2].Message.Contains("'Zeta'")
}

test "ordinal order is by CODE UNIT, so every uppercase letter sorts before every lowercase one" {
    harness := ReferenceReportHarnessNew()
    harness.Failures["alpha"] = "lower"
    harness.Failures["Zeta"] = "upper"
    ReportUnresolvedType(harness)
    harness.Owner.Report(null)
    warnings := ReferenceWarnings(harness)
    assert warnings.Count == 2
    assert warnings[0].Message.Contains("'Zeta'")
    assert warnings[1].Message.Contains("'alpha'")
}

test "the ordinal comparison answers the three outcomes" {
    assert AnalyzerReferenceLoadReport.CompareOrdinal("a", "b") < 0
    assert AnalyzerReferenceLoadReport.CompareOrdinal("b", "a") > 0
    assert AnalyzerReferenceLoadReport.CompareOrdinal("same", "same") == 0
}

test "a prefix sorts before the longer name it is a prefix of" {
    assert AnalyzerReferenceLoadReport.CompareOrdinal("System", "System.Text") < 0
    assert AnalyzerReferenceLoadReport.CompareOrdinal("System.Text", "System") > 0
    assert AnalyzerReferenceLoadReport.CompareOrdinal("", "a") < 0
}

test "uppercase sorts before lowercase, which is what Ordinal means and what Culture would not give" {
    assert AnalyzerReferenceLoadReport.CompareOrdinal("Z", "a") < 0
    assert AnalyzerReferenceLoadReport.CompareOrdinal("A", "a") < 0
}
