namespace NSharpLang.Compiler

import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `SmartSuggester` AND `TypeConversionSuggester`, IN N#.
//
// These replace the `SmartSuggester` and `TypeConversionSuggester` halves of
// `tests/ErrorReportingTests.cs`. `SmartSuggester` is what turns a misspelled name into the ranked
// "Did you mean one of these?" list an Elm-style diagnostic prints; `TypeConversionSuggester` is
// what turns a type pair into the "Hint:" paragraph beneath a type mismatch.
//
// WHAT THE DELETED FILE COULD NOT SEE, AND WHY IT MATTERS MOST HERE. Every one of its five
// `SmartSuggester` cases asserted `Contains` or `NotEmpty` — never the RANKED ORDER, never which
// candidates were EXCLUDED, and never that `maxSuggestions` truncates the ranking rather than
// sampling it. A suggester that returned every candidate in input order would have passed all five.
// This file states the whole answer list, in order, for each of them.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) THE SCORE IS TWO TERMS, WEIGHTED 0.7 EDIT DISTANCE AND 0.3 COMMON PREFIX. Two candidates at
// the SAME edit distance rank differently when one shares a prefix — which is the entire reason the
// prefix term exists.
//
// (2) THE THRESHOLD IS STRICTLY ABOVE 0.5, AND IT IS WHAT KEEPS NONSENSE OUT. A suggester with no
// threshold still passes every `Contains` test ever written for it.
//
// (3) TIES KEEP CANDIDATE ORDER. The insertion sort stops at `previousScore >= score`, so equal
// scores are stable — which is what makes a truncated list deterministic.
//
// (4) `TypeConversionSuggester`'s RULES ARE ORDERED. The explicit pairs are matched BEFORE the
// nullable rules, and the nullable rules before the generic numeric fallback; an unordered table
// would answer the wrong paragraph for `int` -> `long`.

func SuggestionNames(candidates: List<string>, typo: string, maxSuggestions: int): string {
    suggester := new SmartSuggester(candidates)
    return string.Join(",", suggester.SuggestSimilarNames(typo, maxSuggestions))
}

func ConversionHint(fromType: string, toType: string): string {
    return TypeConversionSuggester.SuggestConversion(fromType, toType) ?? "<null>"
}

func SuggesterCandidates4(first: string, second: string, third: string, fourth: string): List<string> {
    values := new List<string>()
    values.Add(first)
    values.Add(second)
    values.Add(third)
    values.Add(fourth)
    return values
}

// ---- SmartSuggester --------------------------------------------------------------------------

// Successor to SmartSuggester_FindsTypos.
test "the suggester finds a one-character typo" {
    candidates := new List<string>()
    candidates.Add("Console")
    candidates.Add("System")
    candidates.Add("List")
    candidates.Add("string")
    suggester := new SmartSuggester(candidates)
    suggestions := suggester.SuggestSimilarNames("Consol", 3)

    assert suggestions.Contains("Console")

    // NOT IN THE DELETED FILE: `Console` is the ONLY answer. `Contains` would pass just as well for a
    // suggester that returned all four candidates, which is the failure mode a "did you mean" list
    // actually has.
    assert SuggestionNames(SuggesterCandidates4("Console", "System", "List", "string"), "Consol", 3) == "Console"
}

// Successor to SmartSuggester_RanksByLevenshteinDistance.
test "the suggester ranks by edit distance" {
    candidates := new List<string>()
    candidates.Add("userName")
    candidates.Add("userEmail")
    candidates.Add("userId")
    candidates.Add("name")
    suggester := new SmartSuggester(candidates)
    suggestions := suggester.SuggestSimilarNames("usreName", 3)

    assert suggestions.Count > 0
    assert suggestions.Contains("userName")

    // NOT IN THE DELETED FILE: the other three share the `user` prefix and are STILL excluded,
    // because the prefix term alone cannot carry a candidate over the threshold.
    assert SuggestionNames(SuggesterCandidates4("userName", "userEmail", "userId", "name"), "usreName", 3) == "userName"
}

// Successor to SmartSuggester_ConsidersPrefixMatch.
test "the suggester considers the shared prefix" {
    candidates := new List<string>()
    candidates.Add("getUserName")
    candidates.Add("getUsername")
    candidates.Add("setUserName")
    suggester := new SmartSuggester(candidates)
    suggestions := suggester.SuggestSimilarNames("getUserNam", 3)

    assert suggestions.Count > 0
    assert suggestions.Contains("getUserName")

    // NOT IN THE DELETED FILE: all three clear the threshold, the two `get` spellings TIE, and the
    // tie is broken by CANDIDATE ORDER — so the ranked list is fully determined, and `setUserName`
    // (same edit distance as the second `get` spelling, no shared prefix) sorts last.
    assert SuggestionNames(candidates, "getUserNam", 3) == "getUserName,getUsername,setUserName"
}

// Successor to SmartSuggester_ReturnsEmptyForPoorMatches.
test "the suggester answers nothing when nothing is close" {
    candidates := new List<string>()
    candidates.Add("apple")
    candidates.Add("banana")
    candidates.Add("cherry")
    suggester := new SmartSuggester(candidates)
    suggestions := suggester.SuggestSimilarNames("xyz123", 3)

    assert suggestions.Count == 0

    // NOT IN THE DELETED FILE: an EMPTY candidate set answers nothing rather than throwing, which is
    // the shape the analyser hands it when a name is used before anything is in scope.
    nothingToSuggest := new SmartSuggester(new List<string>())
    assert nothingToSuggest.SuggestSimilarNames("anything", 3).Count == 0
}

// Successor to SmartSuggester_LimitsToMaxSuggestions.
test "the suggester truncates the ranking at the requested maximum" {
    candidates := new List<string>()
    candidates.Add("test1")
    candidates.Add("test2")
    candidates.Add("test3")
    candidates.Add("test4")
    candidates.Add("test5")
    suggester := new SmartSuggester(candidates)
    suggestions := suggester.SuggestSimilarNames("test", 2)

    assert suggestions.Count <= 2

    // NOT IN THE DELETED FILE: all five score IDENTICALLY, so "at most two" is satisfied by any two
    // of them — or by none. The answer is the FIRST two of the ranked list, and asking for three
    // takes the first three, which is what makes a truncated suggestion list reproducible.
    assert SuggestionNames(candidates, "test", 2) == "test1,test2"
    assert SuggestionNames(candidates, "test", 3) == "test1,test2,test3"
    assert SuggestionNames(candidates, "test", 99) == "test1,test2,test3,test4,test5"

    // A non-positive maximum short-circuits before a single candidate is scored.
    assert SuggestionNames(candidates, "test", 0) == ""
    assert SuggestionNames(candidates, "test", -1) == ""
}

// NOT IN THE DELETED FILE AT ALL: the scorer itself, which nothing reached directly.
test "the similarity score weights edit distance and shared prefix separately" {
    // Identical strings score at the top; wholly different ones of equal length score exactly zero.
    assert SmartSuggester.ScoreSimilarity("abc", "abc") > 0.99
    assert SmartSuggester.ScoreSimilarity("abc", "xyz") == 0.0

    // An empty side scores zero without dividing by it.
    assert SmartSuggester.ScoreSimilarity("", "abc") == 0.0
    assert SmartSuggester.ScoreSimilarity("abc", "") == 0.0
    assert SmartSuggester.ScoreSimilarity("", "") == 0.0

    // THE PREFIX TERM PROVABLY PARTICIPATES: both candidates are ONE edit away, so the distance term
    // is identical, and only the shared prefix separates them.
    assert SmartSuggester.ScoreSimilarity("abcd", "abcz") > SmartSuggester.ScoreSimilarity("abcd", "zbcd")

    // The scorer is case-insensitive on BOTH terms.
    assert SmartSuggester.ScoreSimilarity("abc", "ABC") > 0.99
}

// NOT IN THE DELETED FILE AT ALL.
test "the common prefix length is measured case-insensitively" {
    assert SmartSuggester.CommonPrefixLength("ABCdef", "abcXYZ") == 3
    assert SmartSuggester.CommonPrefixLength("abc", "abc") == 3
    assert SmartSuggester.CommonPrefixLength("abc", "xyz") == 0
    assert SmartSuggester.CommonPrefixLength("abc", "") == 0
    assert SmartSuggester.CommonPrefixLength("", "abc") == 0
    assert SmartSuggester.CommonPrefixLength("abcdef", "abc") == 3
    assert SmartSuggester.MaxInt(2, 5) == 5
    assert SmartSuggester.MaxInt(5, 2) == 5
    assert SmartSuggester.MinInt(2, 5) == 2
    assert SmartSuggester.MinInt(5, 2) == 2
}

// ---- TypeConversionSuggester -------------------------------------------------------------------

// Successor to TypeConversionSuggester_StringToInt.
test "converting a string to an int names both parse entry points" {
    hint := TypeConversionSuggester.SuggestConversion("string", "int")

    assert hint != null
    assert (hint ?? "").Contains("int.Parse")
    assert (hint ?? "").Contains("int.TryParse")

    assert (hint ?? "") == "Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
}

// Successor to TypeConversionSuggester_IntToString.
test "converting an int to a string names ToString and interpolation" {
    hint := TypeConversionSuggester.SuggestConversion("int", "string")

    assert hint != null
    assert (hint ?? "").Contains(".ToString()")
    assert (hint ?? "").Contains("$\"{")

    assert (hint ?? "") == "You can convert an integer to a string using .ToString() or string\ninterpolation: $\"{yourNumber}\""
}

// Successor to TypeConversionSuggester_NullableToNonNullable.
test "converting a nullable to a non-nullable names the null case" {
    hint := TypeConversionSuggester.SuggestConversion("int?", "int")

    assert hint != null
    assert (hint ?? "").Contains("nullable")
    assert (hint ?? "").Contains("??")

    assert (hint ?? "") == "You're trying to use a nullable value where a non-nullable is expected.\nYou need to handle the null case, perhaps with 'if (x != null)' or the\nnull-coalescing operator 'x ?? defaultValue'."

    // NOT IN THE DELETED FILE: the rule is `fromType == toType + "?"`, so it holds for ANY type, not
    // only for the built-in the sample used.
    assert ConversionHint("Person?", "Person") == (hint ?? "")
}

// Successor to TypeConversionSuggester_NonNullableToNullable.
test "converting a non-nullable to a nullable is implicit" {
    hint := TypeConversionSuggester.SuggestConversion("int", "int?")

    assert hint != null
    assert (hint ?? "").Contains("implicit")

    assert (hint ?? "") == "This conversion is implicit. Non-nullable values can be assigned to nullable types."
    assert ConversionHint("Person", "Person?") == (hint ?? "")
}

// Successor to TypeConversionSuggester_ArrayToList.
test "converting an array to a list names ToList" {
    hint := TypeConversionSuggester.SuggestConversion("int[]", "List<int>")

    assert hint != null
    assert (hint ?? "").Contains(".ToList()")

    assert (hint ?? "") == "Use .ToList() to convert an array to a List, or use 'new List<T>(array)'."
    assert ConversionHint("Person[]", "List<Person>") == (hint ?? "")
}

// Successor to TypeConversionSuggester_ListToArray.
test "converting a list to an array names ToArray" {
    hint := TypeConversionSuggester.SuggestConversion("List<int>", "int[]")

    assert hint != null
    assert (hint ?? "").Contains(".ToArray()")

    assert (hint ?? "") == "Use .ToArray() to convert a List to an array."
    assert ConversionHint("List<Person>", "Person[]") == (hint ?? "")
}

// Successor to TypeConversionSuggester_DoubleToInt_WarnsAboutTruncation.
test "converting a double to an int warns about truncation" {
    hint := TypeConversionSuggester.SuggestConversion("double", "int")

    assert hint != null
    assert (hint ?? "").Contains("(int)")
    assert (hint ?? "").Contains("truncates")

    assert (hint ?? "") == "Cannot implicitly convert 'double' to 'int'. Use an explicit cast: (int)value\nWarning: This truncates decimals (e.g. 3.7 becomes 3) and may lose data if the value exceeds the target type's range."

    // NOT IN THE DELETED FILE: `double` -> `int` is the ONLY pair that says "truncates". The generic
    // numeric fallback warns about RANGE, not about decimals, so the specific rule is not redundant
    // with the fallback that would otherwise catch the same pair.
    assert !ConversionHint("long", "int").Contains("truncates")
    assert !ConversionHint("float", "decimal").Contains("truncates")
}

// NOT IN THE DELETED FILE AT ALL: the six rules the deleted file never asked for, and the ordering
// that keeps the explicit ones ahead of the fallback.
test "the conversion table answers every remaining pair it names" {
    assert ConversionHint("int", "double") == "Implicit conversion from int to double works automatically."
    assert ConversionHint("string", "double") == "Use double.Parse(yourString) or double.TryParse(yourString, out result)."
    assert ConversionHint("double", "string") == "Use value.ToString() or $\"{value}\""
    assert ConversionHint("int", "long") == "Implicit conversion from int to long works automatically."
    assert ConversionHint("long", "int") == "Cannot implicitly convert 'long' to 'int'. Use an explicit cast: (int)value\nWarning: This conversion may lose data if the value exceeds the target type's range."

    // The generic numeric fallback, reached only when no explicit pair matched.
    assert ConversionHint("float", "decimal") == "Cannot implicitly convert 'float' to 'decimal'. Use an explicit cast: (decimal)value\nWarning: This conversion may lose data if the value exceeds the target type's range."
    assert ConversionHint("byte", "sbyte") == "Cannot implicitly convert 'byte' to 'sbyte'. Use an explicit cast: (sbyte)value\nWarning: This conversion may lose data if the value exceeds the target type's range."

    // AND THE ANSWER FOR A PAIR IT DOES NOT NAME IS NULL, which is what lets the builder fall back to
    // its own sentence instead of printing a wrong hint.
    assert ConversionHint("string", "bool") == "<null>"
    assert ConversionHint("Person", "Customer") == "<null>"
    assert ConversionHint("bool", "bool") == "<null>"

    // AND THE FALLBACK IS DELIBERATELY UNGUARDED ON IDENTITY: two numeric types that are the SAME
    // type still take it, because the suggester is only ever consulted after the analyser has
    // already decided the two types do not match.
    assert ConversionHint("int", "int") == "Cannot implicitly convert 'int' to 'int'. Use an explicit cast: (int)value\nWarning: This conversion may lose data if the value exceeds the target type's range."
}

// NOT IN THE DELETED FILE AT ALL: the twelve names that decide whether the numeric fallback fires.
test "the numeric type table names twelve types and nothing else" {
    assert TypeConversionSuggester.IsNumericType("int")
    assert TypeConversionSuggester.IsNumericType("long")
    assert TypeConversionSuggester.IsNumericType("short")
    assert TypeConversionSuggester.IsNumericType("byte")
    assert TypeConversionSuggester.IsNumericType("sbyte")
    assert TypeConversionSuggester.IsNumericType("ushort")
    assert TypeConversionSuggester.IsNumericType("uint")
    assert TypeConversionSuggester.IsNumericType("ulong")
    assert TypeConversionSuggester.IsNumericType("float")
    assert TypeConversionSuggester.IsNumericType("double")
    assert TypeConversionSuggester.IsNumericType("decimal")
    assert TypeConversionSuggester.IsNumericType("char")

    assert !TypeConversionSuggester.IsNumericType("string")
    assert !TypeConversionSuggester.IsNumericType("bool")
    assert !TypeConversionSuggester.IsNumericType("object")
    assert !TypeConversionSuggester.IsNumericType("Int32")
    assert !TypeConversionSuggester.IsNumericType("INT")
    assert !TypeConversionSuggester.IsNumericType("")
}

// NOT IN THE DELETED FILE AT ALL: the example builder, which exists only because a `$"…"` literal
// cannot be written inside the message it is describing.
test "the interpolated string example renders a quoted hole" {
    assert TypeConversionSuggester.InterpolatedStringExample("value") == "$\"{value}\""
    assert TypeConversionSuggester.InterpolatedStringExample("yourNumber") == "$\"{yourNumber}\""
    assert TypeConversionSuggester.InterpolatedStringExample("") == "$\"{}\""
}
