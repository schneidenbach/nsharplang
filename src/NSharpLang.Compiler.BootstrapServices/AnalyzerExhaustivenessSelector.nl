namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast
import System.Collections.Generic

// The PURE FACTS of match exhaustiveness: what a pattern's SHAPE says about coverage, and which of a
// closed set of alternatives a set of flags leaves uncovered.
//
// Nothing here reads the analyzer's state, resolves a type, or reports. Every answer is a function
// of the syntax tree and a declaration, which is what makes this the family's peripheral layer —
// `AnalyzerMatchExhaustiveness` is the reporting core that consumes it.
//
// TWO SHAPE DISTINCTIONS CARRY THE FAMILY, and they are easy to conflate:
// * TOTAL vs CONSTRAINED. A pattern is TOTAL for its case when it places no restriction on the
//   case's payload — no property list at all, or a property list every entry of which binds without
//   testing. A total arm covers its case outright; a constrained one only partially covers it, and
//   the coverage walk has to look inside.
// * CATCH-ALL vs QUALIFIED. An `IdentifierPattern` is a catch-all binding — it matches anything and
//   names it — UNLESS its name is dotted, in which case it is a qualified case name being matched
//   rather than a binding being introduced. That single `.` test is the difference between `other =>`
//   (which makes a match exhaustive on the spot) and `Result.Success =>` (which covers one case).
//
// THE QUALIFIER IS MATCHED LENIENTLY AND DELIBERATELY SO. `Shape.Circle`, `Geometry.Shape.Circle`
// and a bare `Circle` all name the same case of a union declared as `Geometry.Shape`: the qualifier
// may be the declared name, the declared name's last segment, or any suffix-aligned prefix of it.
// A qualifier that matches NONE of those is not this union's case at all, and the lookup fails
// rather than falling back to the bare name — which is what makes `Other.Circle` a reportable
// mistake instead of a silent hit.
public class AnalyzerExhaustivenessSelector {
    public static func SelectMissingEnumMembers(
        members: IEnumerable<EnumMemberInfo>,
        coveredMembers: IEnumerable<string>): List<string> {
        result := new List<string>()

        foreach member in members {
            name := member.Name
            if !AnalyzerExhaustivenessContainsName(coveredMembers, name) {
                result.Add(name)
            }
        }

        return result
    }

    static func AnalyzerExhaustivenessContainsName(names: IEnumerable<string>, target: string): bool {
        foreach name in names {
            if name == target {
                return true
            }
        }

        return false
    }

    public static func SelectMissingUnionCasesFromFlags(
        cases: IReadOnlyList<UnionCase>,
        coveredFlags: int[],
        partialFlags: int[],
        count: int,
        out missingCases: List<string>,
        out partialMissingCases: List<string>,
        out neverCoveredCases: List<string>) {
        missingCases = new List<string>()
        partialMissingCases = new List<string>()
        neverCoveredCases = new List<string>()

        i := 0
        while i < count {
            if coveredFlags[i] == 0 {
                name := cases[i].Name
                missingCases.Add(name)

                if partialFlags[i] != 0 {
                    partialMissingCases.Add(name)
                } else {
                    neverCoveredCases.Add(name)
                }
            }

            i = i + 1
        }
    }

    // A pattern that matches every value of the scrutinee and binds it. `_` is the explicit form;
    // any UNDOTTED identifier is the same thing under a name. A dotted identifier is a qualified
    // case name, not a binding, so it is NOT a catch-all.
    public static func IsCatchAllPattern(pattern: Pattern): bool {
        identifierPattern := pattern as IdentifierPattern
        if identifierPattern == null {
            return false
        }

        return identifierPattern.Name == "_" || !identifierPattern.Name.Contains('.')
    }

    // A property entry that places no restriction on the value it reads: either it only binds
    // (`{ value }`) or the pattern it applies is itself a catch-all (`{ value: v }`).
    public static func IsTotalPropertyPattern(propertyPattern: PropertyPattern): bool {
        if propertyPattern.Pattern == null {
            return true
        }

        return IsCatchAllPattern(propertyPattern.Pattern)
    }

    // A union-case arm that covers its case OUTRIGHT: no property list, an empty one, or one whose
    // every entry is total.
    public static func IsTotalUnionCasePattern(pattern: UnionCasePattern): bool {
        properties := pattern.Properties
        if properties == null || properties.Count == 0 {
            return true
        }

        foreach propertyPattern in properties {
            if !IsTotalPropertyPattern(propertyPattern) {
                return false
            }
        }

        return true
    }

    // The same question asked of a NESTED pattern, where the alternative spelling is in play: a
    // nested union case may be written either as a case pattern with properties or as a dotted
    // identifier, and the dotted identifier — carrying no property list — is always total.
    public static func IsTotalNestedUnionPattern(pattern: Pattern): bool {
        unionCasePattern := pattern as UnionCasePattern
        if unionCasePattern != null {
            return IsTotalUnionCasePattern(unionCasePattern)
        }

        identifierPattern := pattern as IdentifierPattern
        if identifierPattern != null {
            return identifierPattern.Name.Contains('.')
        }

        return false
    }

    // The case name a possibly-qualified pattern name denotes: everything after the last `.`.
    public static func GetUnionCaseName(patternName: string): string {
        if !patternName.Contains('.') {
            return patternName
        }

        return patternName.Substring(patternName.LastIndexOf('.') + 1)
    }

    // Whether a pattern name's QUALIFIER — the part before the last `.` — can name this union. An
    // unqualified name is compatible with any union; a qualified one must be the declared name, its
    // last segment, or a suffix-aligned prefix of the declared name.
    public static func IsUnionCaseQualifierCompatible(unionType: UnionTypeInfo, patternName: string): bool {
        lastDot := patternName.LastIndexOf('.')
        if lastDot < 0 {
            return true
        }

        qualifier := patternName.Substring(0, lastDot)
        declaredName := unionType.Declaration.Name
        simpleName := declaredName
        if declaredName.Contains('.') {
            simpleName = declaredName.Substring(declaredName.LastIndexOf('.') + 1)
        }

        return qualifier == declaredName
            || qualifier == simpleName
            || declaredName.EndsWith("." + qualifier, StringComparison.Ordinal)
    }

    // The union case a pattern name resolves to, or null when this union has none by that name. The
    // qualifier gate runs FIRST: a name qualified by some OTHER type does not resolve here even when
    // its last segment happens to match a case.
    public static func FindUnionCaseForPattern(unionType: UnionTypeInfo, patternName: string): UnionCase? {
        if !IsUnionCaseQualifierCompatible(unionType, patternName) {
            return null
        }

        caseName := GetUnionCaseName(patternName)
        foreach candidate in unionType.Declaration.Cases {
            if candidate.Name == caseName {
                return candidate
            }
        }

        return null
    }

    // The case a NESTED pattern matches, in either spelling, or null when the pattern is not a case
    // reference at all. An UNDOTTED identifier is a binding rather than a case name and answers null.
    public static func GetMatchedUnionCaseName(unionType: UnionTypeInfo, pattern: Pattern): string? {
        nestedUnionPattern := pattern as UnionCasePattern
        if nestedUnionPattern != null {
            matchedCase := FindUnionCaseForPattern(unionType, nestedUnionPattern.CaseName)
            if matchedCase != null {
                return matchedCase.Name
            }

            return null
        }

        nestedIdentifierPattern := pattern as IdentifierPattern
        if nestedIdentifierPattern != null && nestedIdentifierPattern.Name.Contains('.') {
            matchedCase := FindUnionCaseForPattern(unionType, nestedIdentifierPattern.Name)
            if matchedCase != null {
                return matchedCase.Name
            }
        }

        return null
    }

    // The partially-covered half of a non-exhaustive message: each case name, annotated with the
    // FIRST nested arm the walk found missing for it when there is one.
    public static func FormatPartialCoverageCases(
        partialMissingCases: List<string>,
        partialCoverageHints: Dictionary<string, List<string> >): string {
        rendered := new List<string>()

        foreach caseName in partialMissingCases {
            hints := new List<string>()
            if partialCoverageHints.TryGetValue(caseName, out hints) && hints.Count > 0 {
                rendered.Add(caseName + " (missing nested arm: " + hints[0] + ")")
            } else {
                rendered.Add(caseName)
            }
        }

        return string.Join(", ", rendered)
    }
}
