namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Native contracts for the exhaustiveness family's PURE FACTS.
//
// Every member under test was `private static` in Analyzer.cs, so nothing named it: the shape
// distinctions below were pinned only indirectly, through whichever end-to-end diagnostic happened
// to depend on them. These are their first DIRECT contracts, and they go at the two places the
// measurement said no call site reveals — the CATCH-ALL / QUALIFIED split on an identifier pattern,
// and the LENIENT qualifier match, whose rejection arm (a case name qualified by a foreign type)
// never fired once across the whole 71-target corpus.

func ExhaustivenessCase(name: string): UnionCase {
    return new UnionCase(name, null, 1, 1)
}

func ExhaustivenessCaseWith(name: string, propertyName: string, propertyTypeName: string): UnionCase {
    properties := new List<UnionCaseProperty>()
    properties.Add(new UnionCaseProperty(propertyName, new SimpleTypeReference(propertyTypeName, 1, 1)))
    return new UnionCase(name, properties, 1, 1)
}

func ExhaustivenessUnion(declaredName: string, caseNames: string[]): UnionTypeInfo {
    cases := new List<UnionCase>()
    index := 0
    while index < caseNames.Length {
        cases.Add(ExhaustivenessCase(caseNames[index]))
        index = index + 1
    }

    return new UnionTypeInfo(new UnionDeclarationInfo(declaredName, null, cases, 1, 1))
}

func ExhaustivenessNames2(first: string, second: string): string[] {
    result := new string[](2)
    result[0] = first
    result[1] = second
    return result
}

func ExhaustivenessIdentifier(name: string): Pattern {
    return new IdentifierPattern(name, 1, 1)
}

func ExhaustivenessProperty(name: string, nested: Pattern?): PropertyPattern {
    return new PropertyPattern(name, nested, null, 1, 1)
}

func ExhaustivenessCasePattern(caseName: string, properties: List<PropertyPattern>?): UnionCasePattern {
    return new UnionCasePattern(caseName, properties, 1, 1)
}

func ExhaustivenessProperties(first: PropertyPattern): List<PropertyPattern> {
    result := new List<PropertyPattern>()
    result.Add(first)
    return result
}

test "an identifier pattern is a catch-all unless its name is qualified" {
    // The whole family turns on this one `.` test: `other =>` makes a match exhaustive on the spot,
    // while `Result.Success =>` covers exactly one case. `_` is only the explicit spelling of the
    // first, not a separate kind.
    assert AnalyzerExhaustivenessSelector.IsCatchAllPattern(ExhaustivenessIdentifier("_"))
    assert AnalyzerExhaustivenessSelector.IsCatchAllPattern(ExhaustivenessIdentifier("other"))
    assert !AnalyzerExhaustivenessSelector.IsCatchAllPattern(ExhaustivenessIdentifier("Result.Success"))
    assert !AnalyzerExhaustivenessSelector.IsCatchAllPattern(ExhaustivenessIdentifier("A.B.C"))
}

test "only an identifier pattern can be a catch-all" {
    // A literal, a case pattern and an object pattern all TEST the value, so none of them is a
    // binding that matches everything — the answer is shape-driven, not name-driven.
    assert !AnalyzerExhaustivenessSelector.IsCatchAllPattern(
        new LiteralPattern(new IntLiteralExpression("1", 1, 1), 1, 1))
    assert !AnalyzerExhaustivenessSelector.IsCatchAllPattern(
        ExhaustivenessCasePattern("Success", null))
    assert !AnalyzerExhaustivenessSelector.IsCatchAllPattern(
        new ObjectPattern(new List<PropertyPattern>(), 1, 1))
}

test "a property entry is total when it only binds or applies a catch-all" {
    // `{ value }` and `{ value: v }` place no restriction; `{ value: Kind.Io }` does. This is the
    // distinction that decides whether an arm covers its case outright or only partially.
    assert AnalyzerExhaustivenessSelector.IsTotalPropertyPattern(
        ExhaustivenessProperty("value", null))
    assert AnalyzerExhaustivenessSelector.IsTotalPropertyPattern(
        ExhaustivenessProperty("value", ExhaustivenessIdentifier("v")))
    assert AnalyzerExhaustivenessSelector.IsTotalPropertyPattern(
        ExhaustivenessProperty("value", ExhaustivenessIdentifier("_")))
    assert !AnalyzerExhaustivenessSelector.IsTotalPropertyPattern(
        ExhaustivenessProperty("value", ExhaustivenessIdentifier("Kind.Io")))
}

test "a union-case arm is total with no properties, no property list, or all-total properties" {
    // An arm with NO property list and one with an EMPTY list are both total: neither reads the
    // payload at all.
    assert AnalyzerExhaustivenessSelector.IsTotalUnionCasePattern(
        ExhaustivenessCasePattern("Success", null))
    assert AnalyzerExhaustivenessSelector.IsTotalUnionCasePattern(
        ExhaustivenessCasePattern("Success", new List<PropertyPattern>()))
    assert AnalyzerExhaustivenessSelector.IsTotalUnionCasePattern(
        ExhaustivenessCasePattern("Success", ExhaustivenessProperties(
            ExhaustivenessProperty("value", null))))
    assert !AnalyzerExhaustivenessSelector.IsTotalUnionCasePattern(
        ExhaustivenessCasePattern("Success", ExhaustivenessProperties(
            ExhaustivenessProperty("value", ExhaustivenessIdentifier("Kind.Io")))))
}

test "a nested union pattern is total when it is a dotted identifier or an unconstrained case" {
    // The nested position accepts BOTH spellings, and the dotted identifier — which carries no
    // property list — is unconditionally total. An UNDOTTED identifier is a binding, not a case
    // reference, so it is not total in this sense at all.
    assert AnalyzerExhaustivenessSelector.IsTotalNestedUnionPattern(
        ExhaustivenessIdentifier("Kind.Io"))
    assert !AnalyzerExhaustivenessSelector.IsTotalNestedUnionPattern(
        ExhaustivenessIdentifier("k"))
    assert AnalyzerExhaustivenessSelector.IsTotalNestedUnionPattern(
        ExhaustivenessCasePattern("Io", null))
    assert !AnalyzerExhaustivenessSelector.IsTotalNestedUnionPattern(
        ExhaustivenessCasePattern("Io", ExhaustivenessProperties(
            ExhaustivenessProperty("at", ExhaustivenessIdentifier("Kind.Parse")))))
    assert !AnalyzerExhaustivenessSelector.IsTotalNestedUnionPattern(
        new LiteralPattern(new IntLiteralExpression("1", 1, 1), 1, 1))
}

test "a case name is everything after the last dot" {
    assert AnalyzerExhaustivenessSelector.GetUnionCaseName("Success") == "Success"
    assert AnalyzerExhaustivenessSelector.GetUnionCaseName("Result.Success") == "Success"
    assert AnalyzerExhaustivenessSelector.GetUnionCaseName("A.B.Success") == "Success"
}

test "the qualifier match is lenient in three ways and rejects a foreign qualifier" {
    // A union declared `Geometry.Shape` answers to `Geometry.Shape.Circle`, to `Shape.Circle`, and
    // to a bare `Circle`. It does NOT answer to `Other.Circle` — this is the arm that makes a
    // misspelled qualifier a reportable mistake instead of a silent hit, and the whole 71-target
    // corpus never once reaches it.
    unionType := ExhaustivenessUnion("Geometry.Shape", ExhaustivenessNames2("Circle", "Square"))

    assert AnalyzerExhaustivenessSelector.IsUnionCaseQualifierCompatible(unionType, "Circle")
    assert AnalyzerExhaustivenessSelector.IsUnionCaseQualifierCompatible(unionType, "Shape.Circle")
    assert AnalyzerExhaustivenessSelector.IsUnionCaseQualifierCompatible(unionType, "Geometry.Shape.Circle")
    assert !AnalyzerExhaustivenessSelector.IsUnionCaseQualifierCompatible(unionType, "Other.Circle")
}

test "the qualifier gate runs before the name lookup" {
    // `Other.Circle`'s last segment IS a declared case, so a lookup that stripped the qualifier
    // first would resolve it. The gate is what stops that.
    unionType := ExhaustivenessUnion("Shape", ExhaustivenessNames2("Circle", "Square"))

    matched := AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(unionType, "Shape.Circle")
    assert matched != null
    assert matched.Name == "Circle"

    assert AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(unionType, "Other.Circle") == null
    assert AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(unionType, "Triangle") == null
}

test "a nested case name is read from either spelling and null from a binding" {
    // A dotted identifier and a case pattern both name a case; an undotted identifier is a binding
    // and names none, which is what keeps `Bad { kind: k }` out of the nested-coverage tally.
    unionType := ExhaustivenessUnion("Kind", ExhaustivenessNames2("Io", "Parse"))

    assert AnalyzerExhaustivenessSelector.GetMatchedUnionCaseName(
        unionType, ExhaustivenessIdentifier("Kind.Io")) == "Io"
    assert AnalyzerExhaustivenessSelector.GetMatchedUnionCaseName(
        unionType, ExhaustivenessCasePattern("Parse", null)) == "Parse"
    assert AnalyzerExhaustivenessSelector.GetMatchedUnionCaseName(
        unionType, ExhaustivenessIdentifier("k")) == null
    assert AnalyzerExhaustivenessSelector.GetMatchedUnionCaseName(
        unionType, ExhaustivenessIdentifier("Other.Io")) == null
    assert AnalyzerExhaustivenessSelector.GetMatchedUnionCaseName(
        unionType, new LiteralPattern(new IntLiteralExpression("1", 1, 1), 1, 1)) == null
}

test "partial coverage renders only the FIRST hint for a case" {
    // A case may have several missing nested arms, but the message names one. Rendering all of them
    // would make the message grow with the nested union's size for no extra guidance — the single
    // named arm is enough to unblock the reader.
    hints := new Dictionary<string, List<string> >(StringComparer.Ordinal)
    both := new List<string>()
    both.Add("Outcome.Bad { kind: Kind.Parse }")
    both.Add("Outcome.Bad { kind: Kind.Other }")
    hints["Bad"] = both

    partialCases := new List<string>()
    partialCases.Add("Bad")
    partialCases.Add("Skipped")

    rendered := AnalyzerExhaustivenessSelector.FormatPartialCoverageCases(partialCases, hints)
    assert rendered == "Bad (missing nested arm: Outcome.Bad { kind: Kind.Parse }), Skipped"
}

test "a case with an empty hint list renders bare" {
    // An EMPTY list is not the same as no entry, and both must render the case name alone.
    hints := new Dictionary<string, List<string> >(StringComparer.Ordinal)
    hints["Bad"] = new List<string>()

    partialCases := new List<string>()
    partialCases.Add("Bad")

    assert AnalyzerExhaustivenessSelector.FormatPartialCoverageCases(partialCases, hints) == "Bad"
}

test "missing enum members are selected in DECLARATION order, not covered order" {
    members := new List<EnumMemberInfo>()
    members.Add(new EnumMemberInfo("Pending", 1, 1, EnumMemberValueKind.Integer, "0"))
    members.Add(new EnumMemberInfo("Active", 2, 1, EnumMemberValueKind.Integer, "1"))
    members.Add(new EnumMemberInfo("Done", 3, 1, EnumMemberValueKind.Integer, "2"))

    covered := new List<string>()
    covered.Add("Active")

    missing := AnalyzerExhaustivenessSelector.SelectMissingEnumMembers(members, covered)
    assert missing.Count == 2
    assert missing[0] == "Pending"
    assert missing[1] == "Done"
}

test "flag selection splits missing cases into never-covered and partially covered" {
    // The three lists are what compose the two message shapes: `missing` decides whether anything
    // is reported at all, `partialMissingCases` decides WHICH shape, and `neverCoveredCases` is the
    // first clause of the longer one. A case is in exactly one of the last two.
    cases := new List<UnionCase>()
    cases.Add(ExhaustivenessCase("Ok"))
    cases.Add(ExhaustivenessCase("Bad"))
    cases.Add(ExhaustivenessCase("Skipped"))

    coveredFlags := new int[](3)
    partialFlags := new int[](3)
    coveredFlags[0] = 1
    partialFlags[1] = 1

    missing := new List<string>()
    partialCases := new List<string>()
    never := new List<string>()
    AnalyzerExhaustivenessSelector.SelectMissingUnionCasesFromFlags(
        cases, coveredFlags, partialFlags, 3, out missing, out partialCases, out never)

    assert missing.Count == 2
    assert missing[0] == "Bad"
    assert missing[1] == "Skipped"
    assert partialCases.Count == 1
    assert partialCases[0] == "Bad"
    assert never.Count == 1
    assert never[0] == "Skipped"
}
