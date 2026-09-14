namespace NSharpLang.Compiler

import System.Collections.Generic


// "BETTER FUNCTION MEMBER" (ECMA-334 §12.6.4.3), STATED ONCE FOR BOTH SIGNATURE WORLDS.
//
// Applicability answers WHICH candidates could accept a call. This owner answers the question that
// comes after it — which of two applicable candidates the language PREFERS — and it is the only
// place that answer is spelled. The reflected world (`AnalyzerCallAnalysis`, over CLR `Type`s read
// from a MetadataLoadContext) and the source world (`AnalyzerSyntheticCallWalk`, over `TypeInfo`s
// built from N# declarations) each supply their own conversion oracle, and both fold the answers
// here. Two copies of this rule would disagree the moment either was edited, and the disagreement
// would be invisible: both copies would still pick SOMETHING.
//
// A VERDICT IS A THREE-VALUED ANSWER, not a boolean: -1 the left candidate is better, +1 the right
// one is, 0 NEITHER is. The third value is the whole reason the rule is not a comparison function.
// "Neither" is what makes a call AMBIGUOUS, and a two-valued rule has to invent a winner — which is
// exactly the bug this owner exists to remove: with the SAME score, `Single(IEnumerable): object?`
// used to beat `Single<T>(IEnumerable<T>): T` because it was declared first, and the call's type
// silently became `object?`.
//
// THE PER-ARGUMENT RULE IS "BETTER CONVERSION TARGET" (§12.6.4.5) AND IT HAS TWO CLAUSES, in order:
//
//   1. IDENTITY WINS. When the argument's own type IS one candidate's parameter type and not the
//      other's, that candidate is better — `WriteLine(string)` over `WriteLine(object)` for a
//      `string`, and `Single<T>` over `Single` once `T` is bound to the element type.
//   2. THE MORE SPECIFIC TYPE WINS. Otherwise, when one parameter type converts implicitly to the
//      other and not back, the one that converts is the more specific and therefore the better
//      target — `IEnumerable<Task<int>>` over `IEnumerable<Task>`, `IEnumerable<JsonElement>` over
//      `IEnumerable`, `int` over `long` for a `short` argument.
//
// Anything else — the two parameter types are the same, or neither converts to the other — is 0.
//
// THE FOLD IS ALL-OR-NOTHING (§12.6.4.3). A candidate is better only when NO argument prefers the
// other one and at least one prefers it. A candidate that wins one position and loses another is
// not better, it is INCOMPARABLE, and incomparable is how a genuine ambiguity reaches the reader.
//
// THE TIE-BREAKS RUN ONLY AFTER THE CONVERSIONS, and their order is §12.6.4.3's: a non-generic
// method beats a generic one, a call in NORMAL form beats one that expanded a `params` tail, and
// fewer defaults beats more. The generic rule is gated on the substituted parameter types being
// IDENTICAL, because "non-generic wins" is a tie-break for signatures the conversions could not
// separate — `string.Join(string, IEnumerable<string>)` over `Join<T>(string, IEnumerable<T>)` with
// `T = string` — and must never overturn a better conversion. LAST comes "more specific parameter
// types", the only rule that reads the signatures as WRITTEN rather than as closed; it is spelled in
// `AnalyzerOpenTypeSpecificity` and arrives here as a verdict, because it is the one question a pair
// closing to the IDENTICAL parameter types can still answer.
//
// SELECTION IS A MAXIMAL-SET SEARCH, NOT A SORT. "Better" is a PARTIAL order: A can beat B, B beat
// C, and A and C be incomparable. A sort over a partial order has no defined answer and would make
// the chosen overload depend on the order the candidates arrived in — and a reflected candidate list
// arrives in whatever order the MetadataLoadContext produced. `FindMaximalIndexes` instead answers
// which candidates NOTHING beats, which is the same set however the list was ordered. Exactly one
// maximal candidate is the call's overload; two or more is the ambiguity; NONE at all means the
// supplied verdicts form a cycle, and the caller keeps its existing order rather than inventing one.
//
// This owner reports nothing and records nothing. Every member is a question with an answer.
class AnalyzerOverloadSpecificity {

    // Nobody's parameter is better.
    static NeitherIsBetter: int => 0

    // The left candidate's parameter is the better conversion target.
    static LeftIsBetter: int => -1

    // The right candidate's parameter is the better conversion target.
    static RightIsBetter: int => 1

    // ONE ARGUMENT POSITION'S VERDICT, from the four facts a conversion oracle can answer about it.
    // The two worlds spell those facts over different type representations; the RULE that reads them
    // is this one.
    //
    // `leftIsIdentity` / `rightIsIdentity` — the argument's own type IS that candidate's parameter
    // type. `leftToRight` / `rightToLeft` — an implicit conversion exists BETWEEN the two parameter
    // types, in that direction. Identity is asked first because C# asks it first: a parameter the
    // argument already has beats one the argument merely converts to, even when the second is the
    // more specific of the two.
    static func CompareConversionTargets(leftIsIdentity: bool, rightIsIdentity: bool, leftToRight: bool, rightToLeft: bool): int {
        if leftIsIdentity != rightIsIdentity {
            if leftIsIdentity {
                return LeftIsBetter
            }

            return RightIsBetter
        }

        if leftIsIdentity {
            return NeitherIsBetter
        }

        if leftToRight != rightToLeft {
            if leftToRight {
                return LeftIsBetter
            }

            return RightIsBetter
        }

        return NeitherIsBetter
    }

    // THE ALL-OR-NOTHING FOLD over one candidate pair's per-argument verdicts. A position both
    // candidates fill identically contributes `NeitherIsBetter` and is simply silent; a position
    // only one candidate could be asked about (a lambda with no type of its own, a method group) is
    // left out of the list by the caller rather than guessed at here.
    static func FoldArgumentVerdicts(verdicts: IReadOnlyList<int>): int {
        sawLeft := false
        sawRight := false
        index := 0
        while index < verdicts.Count {
            verdict := verdicts[index]
            if verdict == LeftIsBetter {
                sawLeft = true
            } else if verdict == RightIsBetter {
                sawRight = true
            }

            index = index + 1
        }

        if sawLeft == sawRight {
            return NeitherIsBetter
        }

        if sawLeft {
            return LeftIsBetter
        }

        return RightIsBetter
    }

    // THE TIE-BREAKS, IN §12.6.4.3's ORDER, for a pair the conversions could not separate.
    //
    // `parameterTypesIdentical` gates the generic rule for the reason stated on the class: a
    // non-generic method beats a generic one only where the two signatures denote the same
    // parameter types, never as a way to overturn a conversion.
    //
    // `openTypeVerdict` IS THE LAST TIE-BREAK AND IT IS ALREADY AN ANSWER. It is the one rule that
    // does not read the closed parameter types at all — `AnalyzerOpenTypeSpecificity` compares the
    // signatures as WRITTEN, so a pair that closes to the identical parameter types can still be
    // ordered by which declaration said more (`Func<Task<TResult>>` over `Func<TResult>`). It runs
    // last because C# runs it last: a candidate that wins a conversion, or wins in normal form, or
    // defaults fewer parameters, has already won before the question is asked.
    static func CompareTieBreaks(parameterTypesIdentical: bool, leftIsGeneric: bool, rightIsGeneric: bool, leftUsesParams: bool, rightUsesParams: bool, leftDefaultsUsed: int, rightDefaultsUsed: int, openTypeVerdict: int): int {
        if parameterTypesIdentical && leftIsGeneric != rightIsGeneric {
            if rightIsGeneric {
                return LeftIsBetter
            }

            return RightIsBetter
        }

        if leftUsesParams != rightUsesParams {
            if rightUsesParams {
                return LeftIsBetter
            }

            return RightIsBetter
        }

        if leftDefaultsUsed != rightDefaultsUsed {
            if leftDefaultsUsed < rightDefaultsUsed {
                return LeftIsBetter
            }

            return RightIsBetter
        }

        return openTypeVerdict
    }

    // WHICH CANDIDATES NOTHING BEATS, read off a square verdict matrix in row-major order:
    // `comparisons[row * count + column]` is the verdict of comparing candidate `row` against
    // candidate `column`, so `LeftIsBetter` there means `row` beats `column`.
    //
    // The answer is INDEPENDENT OF THE CANDIDATE ORDER, which is the property the reflected world
    // needs: its candidate list comes out of a MetadataLoadContext in no guaranteed order, and the
    // chosen overload may not depend on that. Indexes are returned ascending, so a caller that names
    // two of them in a diagnostic names the same two every run.
    //
    // A malformed or inconsistent matrix (a cycle, or a count that does not match the array) answers
    // the EMPTY list rather than an arbitrary index: no candidate is maximal, and the caller must say
    // so rather than pick.
    static func FindMaximalIndexes(comparisons: int[], count: int): List<int> {
        maximal := new List<int>()
        if count <= 0 || comparisons.Length != count * count {
            return maximal
        }

        row := 0
        while row < count {
            beaten := false
            column := 0
            while column < count {
                if column != row && comparisons[column * count + row] == LeftIsBetter {
                    beaten = true
                }

                column = column + 1
            }

            if !beaten {
                maximal.Add(row)
            }

            row = row + 1
        }

        return maximal
    }

    // ------------------------------------------------------------------
    // What NL414 says. Both worlds report the same sentence about the same mistake.
    // ------------------------------------------------------------------

    // The one-line summary, which is what a JSON consumer and a terse formatter read.
    static func AmbiguousCallSummary(functionName: string): string {
        return "The call to '" + functionName + "' is ambiguous"
    }

    // The sentence the reader sees above the two signatures.
    static func AmbiguousCallExplanation(functionName: string): string {
        return "The call to `" + functionName + "` is ambiguous — two overloads match it equally well:"
    }

    // WHY THE COMPILER STOPPED, AND THE THREE WAYS OUT. The hint names the disambiguating edits in
    // the order a reader can try them: a cast changes one argument's type, a typed lambda parameter
    // changes a delegate's shape, and an explicit type-argument list closes a generic signature
    // outright.
    static func AmbiguousCallHint(leftSignature: string, rightSignature: string): string {
        return "Both of these match the arguments you wrote:\n  - " + leftSignature + "\n  - " + rightSignature + "\n\nNeither is more specific than the other, so I will not choose one for you.\nSay which you meant: cast an argument to the parameter type that overload declares, annotate a lambda's parameter types, or write the call's type arguments explicitly."
    }
}
