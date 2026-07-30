namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// Native contracts for the analyzer's unresolved-type suggestion policy. It was `private` in
// Analyzer.cs and no test named it; its wording reached tests only through end-to-end NL201 output.

func SuggestionCandidates(names: string[]): List<string> {
    candidates := new List<string>()
    index := 0
    while index < names.Length {
        candidates.Add(names[index])
        index = index + 1
    }
    return candidates
}

func SuggestionFallback(name: string): string {
    return "Check the spelling, add the missing 'import', or add the package/project reference that provides '"
        + name + "'."
}

func SuggestionDidYouMean(candidate: string, name: string): string {
    return "Did you mean '" + candidate
        + "'? Otherwise add the 'import' or package reference that provides '" + name + "'."
}

test "a candidate within edit distance two becomes a did-you-mean, and nothing further does" {
    // Distance 1.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widgit", SuggestionCandidates(["Widget"])) == SuggestionDidYouMean("Widget", "Widgit")

    // Distance 2 is still inside the threshold.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widgits", SuggestionCandidates(["Widget"])) == SuggestionDidYouMean("Widget", "Widgits")

    // Distance 3 is not: guessing that far away is worse than saying nothing.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Wxyzits", SuggestionCandidates(["Widget"])) == SuggestionFallback("Wxyzits")

    // Nothing to compare against at all.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widget", SuggestionCandidates([])) == SuggestionFallback("Widget")
}

test "the comparison is case-insensitive but the suggestion keeps the candidate's own spelling" {
    // Distances are measured lower-cased, so a pure case difference is distance ZERO and wins.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "widget", SuggestionCandidates(["Widget"])) == SuggestionDidYouMean("Widget", "widget")
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "WIDGET", SuggestionCandidates(["Widget"])) == SuggestionDidYouMean("Widget", "WIDGET")
}

test "candidates shorter than three characters, and the name itself, are skipped" {
    // At one or two characters almost everything is within distance two of everything else, so short
    // candidates would suggest nonsense.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Ab", SuggestionCandidates(["Ax", "Cd", "Zz"])) == SuggestionFallback("Ab")

    // Exactly three characters IS eligible — the cut is below three, not at it.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Abc", SuggestionCandidates(["Abd"])) == SuggestionDidYouMean("Abd", "Abc")

    // The name is never suggested back to the caller, even when it is in the candidate list — which
    // it can be, since the caller passes every type in scope.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widget", SuggestionCandidates(["Widget"])) == SuggestionFallback("Widget")

    // Skipping the name itself does not stop a DIFFERENT near candidate from winning.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widget", SuggestionCandidates(["Widget", "Widgets"]))
        == SuggestionDidYouMean("Widgets", "Widget")
}

test "the nearest candidate wins, and ties keep the caller's FIRST one" {
    // Strictly nearer beats merely near, regardless of list position.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widgit", SuggestionCandidates(["Widgets", "Widget"]))
        == SuggestionDidYouMean("Widget", "Widgit")
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widgit", SuggestionCandidates(["Widget", "Widgets"]))
        == SuggestionDidYouMean("Widget", "Widgit")

    // A tie is broken by ORDER — the comparison is strictly less-than, so the first candidate at the
    // winning distance keeps it. The caller's order is the scope-chain order, so the suggestion is
    // stable rather than dependent on hash iteration.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widgit", SuggestionCandidates(["Widgot", "Widget"]))
        == SuggestionDidYouMean("Widgot", "Widgit")
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widgit", SuggestionCandidates(["Widget", "Widgot"]))
        == SuggestionDidYouMean("Widget", "Widgit")

    // A far candidate scanned first does not block a near one found later, and the winner is reported
    // even when the list also holds candidates that were skipped for being too short.
    assert AnalyzerDiagnostics.UnresolvedTypeSuggestion(
        "Widgit", SuggestionCandidates(["Zzzzzzzz", "Ab", "Widget", "Qq"]))
        == SuggestionDidYouMean("Widget", "Widgit")
}
