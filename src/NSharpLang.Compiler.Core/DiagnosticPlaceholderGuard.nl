namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// THE RULE THAT KEEPS THE PARSER'S RECOVERY PLACEHOLDER OUT OF EVERY USER-FACING SENTENCE.
//
// When the recovery parser cannot read a name it does not stop: it mints the synthetic name
// `<error>` and keeps building, so an editor still gets a tree for the rest of the file. That is the
// right call for the LSP and it has one consequence nothing guarded — every later rule that quotes a
// NAME in its message quotes the placeholder. One mistyped parameter produced thirty diagnostics, of
// which twenty read `Identifier '<error>' starts with a non-letter character` or `A type named
// '<error>' already exists`. Not one of them is about anything the user wrote.
//
// THE RULE IS: A DIAGNOSTIC THAT WOULD PRINT THE PLACEHOLDER IS A CASCADE, AND A CASCADE IS
// SUPPRESSED. It is safe to suppress unconditionally, because a placeholder EXISTS only where the
// parser already reported the syntax error that minted it — the user is never left with silence,
// only with the one report that names the text they actually typed.
//
// IT IS ENFORCED AT THE DOORS, NOT AT THE SITES. There are hundreds of places that interpolate a
// name into a sentence and any of them can be handed a placeholder; there are exactly four ways a
// diagnostic reaches a user — `AnalyzerDiagnosticSink`'s `Report`, `Warn` and `ReportBuilt`, and
// `LinterWalkState.AddDiagnostic`. Guarding the doors is what makes the rule impossible to reopen by
// writing a new message.
//
// THE PLACEHOLDER'S SPELLING LIVES HERE and `AnalyzerParserErrorPlaceholders.PlaceholderName`
// forwards to it, so the guard and the tree walk can never disagree about what a placeholder is.
class DiagnosticPlaceholderGuard {

    // The name the recovery parser mints for a token it could not read.
    static func PlaceholderName(): string {
        return "<error>"
    }

    // ORDINAL, and deliberately a SUBSTRING test rather than an equality one: the placeholder reaches
    // a sentence quoted (`'<error>'`), qualified (`Sales.<error>`) and inside a longer suggestion.
    static func TextCarriesPlaceholder(text: string?): bool {
        if text == null {
            return false
        }

        value := text ?? ""
        return value.IndexOf(PlaceholderName(), StringComparison.Ordinal) >= 0
    }

    // EVERY FIELD THE RENDERER PRINTS, not just the message. `nlc check --text` prints the headline,
    // the human explanation, the hint, the expected/actual pair and the suggestion; the JSON schema
    // publishes the same fields. A placeholder in any one of them is the same broken sentence.
    //
    // `SourceSnippet` is deliberately NOT tested: it is the user's own source line, echoed back
    // verbatim, so a file that legitimately contains the characters `<error>` in a string literal
    // must not have its diagnostics silenced.
    static func CarriesPlaceholder(error: CompilerError): bool {
        if TextCarriesPlaceholder(error.Message) {
            return true
        }

        if TextCarriesPlaceholder(error.Suggestion) {
            return true
        }

        if TextCarriesPlaceholder(error.HumanExplanation) {
            return true
        }

        if TextCarriesPlaceholder(error.ContextualHint) {
            return true
        }

        if TextCarriesPlaceholder(error.ExpectedType) {
            return true
        }

        if TextCarriesPlaceholder(error.ActualType) {
            return true
        }

        // `?? new List<string>()` rather than a null guard: a nullable PROPERTY is not narrowed by a
        // preceding test, and an empty list answers the same way a null one does.
        suggestions := error.Suggestions ?? new List<string>()
        index := 0
        while index < suggestions.Count {
            if TextCarriesPlaceholder(suggestions[index]) {
                return true
            }

            index = index + 1
        }

        return false
    }
}
