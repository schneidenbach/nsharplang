namespace NSharpLang.Compiler

import System


// THE NAMING CONVENTION EVERY DECLARATION IN THE LANGUAGE IS HELD TO, AND THE ONE REPORT IT MAKES.
//
// The rule is the whole of N#'s visibility story at the declaration site: a PascalCase name is
// exported, a camelCase name is not, an explicit visibility modifier opts out of the question
// entirely, and a name the convention can classify as NEITHER — one that starts with a digit, an
// underscore, or any other non-letter — is reported, because such a name has no visibility the reader
// can see. It is asked at TEN declaration sites: the class, struct, record, interface, union, enum and
// field walks, which call it from `AnalyzerTypeDeclarations`, and the top-level function, the local
// function and the property, which call it from `AnalyzerFunctionBodies` and
// `AnalyzerAccessorBodies`. An indexer has no name and never asks; a `soa record` does not ask
// either, and that asymmetry is the shipped behaviour rather than an oversight.
//
// IT IS A TYPE OF ITS OWN BECAUSE IT HAS THREE CALLERS IN THREE OWNERS. Hosting it on any one of them
// would have made the other two depend on that one for a rule none of them owns; hosting it on
// `VisibilityConventions` would have put a REPORT on a pure-facts type whose every other member is a
// question. The facts stay there and the report lives here, over the N#-owned sink.
//
// THIS RULE IS WHAT THE 017 ARC'S FIRST TOOLSET REPIN BOUGHT. `char.IsLower` is load-bearing and no
// published predicate reproduces it: `IsLetter && !IsUpper` admits the title-case, modifier and
// other-category letters this rule refuses, `ToUpperInvariant(c) != c` refuses the eszett this rule
// accepts, and an ASCII range refuses accented lowercase. Every approximation would have SILENTLY
// changed which identifiers get NL903, so the rule stayed in `Analyzer.cs` through slices 46 and 47
// and moved only once the columnar `System.Char` catalog published the predicate.
class AnalyzerDeclarationConventions {

    // THE ORDER OF THE FOUR QUESTIONS IS THE BEHAVIOUR. An empty name is not a convention question at
    // all; an explicit modifier answers it before the spelling is consulted; an exported spelling is
    // the PascalCase arm; and `char.IsLower` is the camelCase arm, asked of the FIRST character only.
    // Anything that reaches the end is a name the convention cannot classify.
    static func CheckVisibilityConvention(diagnostics: AnalyzerDiagnosticSink, name: string?, modifiers: Modifiers, line: int, column: int) {
        if name == null || name.Length == 0 {
            return
        }

        if VisibilityConventions.HasExplicitVisibility(modifiers) {
            return
        }

        if VisibilityConventions.IsExportedIdentifier(name) {
            return
        }

        if char.IsLower(name[0]) {
            return
        }

        diagnostics.Report(ErrorCode.VisibilityConventionWarning, "Identifier '" + name + "' starts with a non-letter character — in N#, PascalCase means public and camelCase means private", line, column, null, Math.Max(1, name.Length))
    }
}
