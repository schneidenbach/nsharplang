namespace NSharpLang.Compiler


// WHAT AN IDENTIFIER IS MADE OF — ONE ANSWER, FOR THE WHOLE ESTATE.
//
// This owner exists because the answer was previously written EIGHT times: six copies of the
// character predicate (`Lexer`, `DiagnosticSpanResolver`, `LinterBlockOwnerSpan`, the columnar
// interpolation splitter, the columnar parser kernels, and the language server's completion
// handler) and two copies of the whole-string predicate (`AnalyzerDeclarationPolicy` and the
// language server's signature-help handler). Every copy agreed, which is precisely what made the
// duplication dangerous: nothing could observe a disagreement, so a copy could drift for a whole
// release without a single test turning red.
//
// THE TWO QUESTIONS ARE NOT INDEPENDENT, AND STATING THAT IS THE POINT OF CONSOLIDATING THEM.
// `IsValid` is DEFINED in terms of `IsStart` and `IsPart` rather than merely agreeing with them by
// coincidence, so the string rule cannot drift away from the character rule at all. Before this
// owner the string predicate inlined its own `char.IsLetter` / `char.IsLetterOrDigit` tests and the
// character predicates inlined theirs; the two families were separate code that happened to say the
// same thing.
//
// THE RULE ITSELF IS THE CLR's, DELIBERATELY NARROWED. `char.IsLetter` and `char.IsLetterOrDigit`
// are Unicode-category tests, so non-ASCII letters are identifier characters — `naïve` and `Ωmega`
// are valid identifiers and always were. What is NOT accepted, and what the CLR would accept, is a
// Unicode connector/formatting character other than `_` (U+2040, U+200C): N# names one connector,
// the underscore, and no others. That narrowing is inherited from every one of the eight copies and
// is preserved here exactly.
class IdentifierText {

    // The first character of an identifier: a letter or the underscore. A digit is not a start
    // character, which is the whole difference between `IsStart` and `IsPart`.
    static func IsStart(ch: char): bool {
        return char.IsLetter(ch) || ch == '_'
    }

    // Any character of an identifier after the first: a letter, a digit, or the underscore.
    static func IsPart(ch: char): bool {
        return char.IsLetterOrDigit(ch) || ch == '_'
    }

    // A whole string. Null and empty are both rejected: an empty segment is what a leading,
    // trailing or doubled dot produces in a dotted name, and callers rely on it answering false
    // rather than throwing.
    static func IsValid(name: string): bool {
        if name == null {
            return false
        }

        if name.Length == 0 {
            return false
        }

        if !IsStart(name[0]) {
            return false
        }

        index := 1
        while index < name.Length {
            if !IsPart(name[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }
}
