namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// Whether a `match` covers everything its scrutinee can be — and the diagnostic when it does not.
//
// THE SCRUTINEE'S TYPE PICKS THE QUESTION, and the five questions are genuinely different rather
// than five spellings of one. An ANONYMOUS UNION is covered arm-by-arm through ASSIGNABILITY (a
// `string` pattern covers a `string` arm), a DECLARED UNION case-by-case through NAMES, an ENUM
// member-by-member through names AND literal values, a NULLABLE by the two-element set
// {null, present}, and everything else by the mere presence of a catch-all. The order of the five
// tests is behaviour: an anonymous union is asked FIRST, and a declared union is asked before the
// generic instantiation of one, because a closed `Result<int>` is a `GenericTypeInfo` that only
// becomes a union once its definition is resolved.
//
// A GUARDED ARM NEVER COVERS ANYTHING. Every walk below skips `matchCase.Guard != null` before it
// looks at the pattern, in all five questions, because a guard may be false at run time — an arm
// `Circle { r } when r > 0 =>` leaves `Circle` uncovered no matter how total its pattern is.
//
// EXHAUSTIVENESS IS RECORDED ON THE AST, NOT RETURNED. `match.IsExhaustive` is what IL lowering
// reads to decide whether a fall-through arm is needed, so every path that concludes coverage must
// SET it — including the early returns, which is why a wildcard returns immediately rather than
// breaking out of the loop with a flag.
//
// THE PARTIAL-COVERAGE WALK IS THE ONLY PLACE A UNION LOOKS INSIDE ITSELF. When every arm for a
// case constrains one property, the case is not covered outright, but the constraint may still be
// exhaustive over a NESTED union — `Error { kind: Kind.Io }` and `Error { kind: Kind.Parse }`
// together cover `Error` when `Kind` has exactly those two cases. The walk computes that, and when
// it falls short it produces HINTS that name the exact missing nested arm, which is what turns
// "partially covered: Error" into "Error (missing nested arm: Result.Error { kind: Kind.Parse })".
class AnalyzerMatchExhaustiveness {
    diagnosticsValue: AnalyzerDiagnosticSink
    typeSubstitutionValue: AnalyzerTypeSubstitution
    assignabilityValue: AnalyzerAssignability
    typeResolverValue: AnalyzerTypeResolver

    constructor(diagnostics: AnalyzerDiagnosticSink, typeSubstitution: AnalyzerTypeSubstitution, assignability: AnalyzerAssignability, typeResolver: AnalyzerTypeResolver) {
        diagnosticsValue = diagnostics
        typeSubstitutionValue = typeSubstitution
        assignabilityValue = assignability
        typeResolverValue = typeResolver
    }

    // The union a value's type DECLARES, plus the substitution its arguments induce. A union type
    // is its own answer under no substitution; a generic instantiation answers the union its
    // definition names, but only when the definition is generic and the argument count agrees —
    // a mismatch is not a union here rather than a partially-bound one.
    func ResolveDeclaredUnionType(valueType: TypeInfo, out substitution: Dictionary<string, TypeInfo>?): UnionTypeInfo? {
        substitution = null

        direct := valueType as UnionTypeInfo
        if direct != null {
            return direct
        }

        generic := valueType as GenericTypeInfo
        if generic != null {
            resolved := typeSubstitutionValue.ResolveGenericDefinition(generic)
            declared := resolved as UnionTypeInfo
            if declared != null {
                typeParameters := declared.Declaration.TypeParameters
                if typeParameters != null && typeParameters.Count > 0 && typeParameters.Count == generic.TypeArguments.Count {
                    bound := new Dictionary<string, TypeInfo>(StringComparer.Ordinal)
                    i := 0
                    while i < typeParameters.Count {
                        bound[typeParameters[i].Name] = generic.TypeArguments[i]
                        i = i + 1
                    }

                    substitution = bound
                    return declared
                }
            }
        }

        return null
    }

    // THE DISPATCH. Asked once per match, after every arm has been analysed, with the scrutinee's
    // type. The chain's order is behaviour — see the type note above.
    func Check(matchExpression: MatchExpression, valueType: TypeInfo) {
        anonymousUnionType := valueType as AnonymousUnionTypeInfo
        if anonymousUnionType != null {
            CheckAnonymousUnion(matchExpression, anonymousUnionType)
            return
        }

        unionType := valueType as UnionTypeInfo
        if unionType != null {
            CheckUnion(matchExpression, unionType, null)
            return
        }

        genericType := valueType as GenericTypeInfo
        if genericType != null {
            genericUnionSubstitution: Dictionary<string, TypeInfo>? = null
            genericUnionType := ResolveDeclaredUnionType(valueType, out genericUnionSubstitution)
            if genericUnionType != null {
                CheckUnion(matchExpression, genericUnionType, genericUnionSubstitution)
                return
            }
        }

        enumType := valueType as EnumTypeInfo
        if enumType != null {
            CheckEnum(matchExpression, enumType)
            return
        }

        nullableType := valueType as NullableTypeInfo
        if nullableType != null {
            CheckNullable(matchExpression, nullableType)
            return
        }

        // Everything else has no closed set of alternatives to enumerate, so the only thing that can
        // make it exhaustive is an unguarded catch-all. The FIRST one wins and the walk stops.
        for matchCase in matchExpression.Cases {
            if matchCase.Guard != null {
                continue
            }

            identifier := matchCase.Pattern as IdentifierPattern
            if identifier != null && (identifier.Name == "_" || !identifier.Name.Contains('.')) {
                matchExpression.IsExhaustive = true
                return
            }
        }
    }

    // A NULLABLE scrutinee has exactly two alternatives and the arms are read for both. A `null`
    // literal covers the absent case; an undotted binding, a type test, an object, positional or
    // list pattern covers the present one — and an undotted binding covers BOTH only when it is
    // `_`, which returns immediately.
    func CheckNullable(matchExpression: MatchExpression, nullableType: NullableTypeInfo) {
        coversNull := false
        coversPresent := false

        for matchCase in matchExpression.Cases {
            if matchCase.Guard != null {
                continue
            }

            pattern := matchCase.Pattern

            identifier := pattern as IdentifierPattern
            if identifier != null {
                if identifier.Name == "_" {
                    matchExpression.IsExhaustive = true
                    return
                }

                if !identifier.Name.Contains('.') {
                    coversPresent = true
                }

                continue
            }

            literal := pattern as LiteralPattern
            if literal != null {
                nullLiteral := literal.Literal as NullLiteralExpression
                if nullLiteral != null {
                    coversNull = true
                }

                continue
            }

            typePattern := pattern as TypePattern
            objectPattern := pattern as ObjectPattern
            positionalPattern := pattern as PositionalPattern
            listPattern := pattern as ListPattern
            if typePattern != null || objectPattern != null || positionalPattern != null || listPattern != null {
                coversPresent = true
            }
        }

        if coversNull && coversPresent {
            matchExpression.IsExhaustive = true
            return
        }

        missing := new List<string>()
        if !coversNull {
            missing.Add("null")
        }
        if !coversPresent {
            missing.Add("present " + TypeText(nullableType.InnerType))
        }

        missingText := string.Join(" and ", missing)
        diagnosticsValue.Report(ErrorCode.NonExhaustiveMatch, "This nullable match doesn't cover " + missingText + " — handle both 'null' and a non-null value arm", matchExpression.Line, matchExpression.Column, "Use `null => ...` for the absent case and `value => ...` to bind the non-null value.", MatchKeywordLength())
    }

    // An ANONYMOUS UNION is covered by ASSIGNABILITY rather than by name: one `TypePattern` may
    // cover several arms at once (an `object` pattern covers all of them), so every arm is tested
    // against every pattern rather than matched one-to-one.
    func CheckAnonymousUnion(matchExpression: MatchExpression, unionType: AnonymousUnionTypeInfo) {
        covered := new bool[](unionType.Arms.Count)

        for matchCase in matchExpression.Cases {
            if matchCase.Guard != null {
                continue
            }

            identifier := matchCase.Pattern as IdentifierPattern
            if identifier != null {
                if identifier.Name == "_" || !identifier.Name.Contains('.') {
                    matchExpression.IsExhaustive = true
                    return
                }

                continue
            }

            typePattern := matchCase.Pattern as TypePattern
            if typePattern != null {
                patternType := typeResolverValue.ResolveType(typePattern.Type)
                i := 0
                while i < unionType.Arms.Count {
                    if assignabilityValue.IsAssignable(patternType, unionType.Arms[i]) {
                        covered[i] = true
                    }

                    i = i + 1
                }
            }
        }

        missingArms := new List<string>()
        index := 0
        while index < unionType.Arms.Count {
            if !covered[index] {
                missingArms.Add(TypeText(unionType.Arms[index]))
            }

            index = index + 1
        }

        if missingArms.Count == 0 {
            matchExpression.IsExhaustive = true
            return
        }

        diagnosticsValue.Report(ErrorCode.NonExhaustiveMatch, "This match doesn't cover all anonymous union arms — missing: " + string.Join(", ", missingArms), matchExpression.Line, matchExpression.Column, "Add an arm for each missing type, or add a wildcard `_` arm.", MatchKeywordLength())
    }

    // A DECLARED UNION, case by case. Two passes: the first collects the unguarded arms per case
    // (and short-circuits on a catch-all), the second decides each collected case's coverage. A
    // case with NO arm at all is left with its flag clear and is reported as simply missing; a case
    // with arms that all constrain it is flagged PARTIAL, which produces the longer message.
    func CheckUnion(matchExpression: MatchExpression, unionType: UnionTypeInfo, substitution: Dictionary<string, TypeInfo>?) {
        unionDeclaration := unionType.Declaration
        unionCases := unionDeclaration.Cases
        caseCount := unionCases.Count
        coveredFlags := new int[](caseCount)
        partialFlags := new int[](caseCount)

        // Collect all union case names that are covered by UNGUARDED arms.
        caseIndexByName := new Dictionary<string, int>(StringComparer.Ordinal)
        caseIndex := 0
        while caseIndex < caseCount {
            // First declaration wins: a duplicated case name resolves to its first index.
            if !caseIndexByName.ContainsKey(unionCases[caseIndex].Name) {
                caseIndexByName[unionCases[caseIndex].Name] = caseIndex
            }

            caseIndex = caseIndex + 1
        }

        unionCasePatterns := new Dictionary<string, List<UnionCasePattern>>(StringComparer.Ordinal)
        partialCoverageHints := new Dictionary<string, List<string>>(StringComparer.Ordinal)

        for matchCase in matchExpression.Cases {
            // Skip guarded arms — they only partially cover their pattern
            if matchCase.Guard != null {
                continue
            }

            unionPattern := matchCase.Pattern as UnionCasePattern
            if unionPattern != null {
                matchedCase := AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(unionType, unionPattern.CaseName)
                if matchedCase != null {
                    if !unionCasePatterns.ContainsKey(matchedCase.Name) {
                        unionCasePatterns[matchedCase.Name] = new List<UnionCasePattern>()
                    }

                    collected := unionCasePatterns[matchedCase.Name]
                    collected.Add(unionPattern)
                }

                continue
            }

            identPattern := matchCase.Pattern as IdentifierPattern
            if identPattern != null {
                if identPattern.Name == "_" {
                    // Unguarded wildcard pattern covers all remaining cases
                    matchExpression.IsExhaustive = true
                    return
                }

                if identPattern.Name.Contains('.') {
                    // Qualified union case name without properties
                    matchedCase := AnalyzerExhaustivenessSelector.FindUnionCaseForPattern(unionType, identPattern.Name)
                    matchedCaseIndex := 0
                    if matchedCase != null && caseIndexByName.TryGetValue(matchedCase.Name, out matchedCaseIndex) {
                        coveredFlags[matchedCaseIndex] = 1
                    }
                } else {
                    // Unqualified, non-wildcard identifier is a catch-all binding (e.g., `other =>`)
                    // that matches everything at runtime — treat it the same as `_`
                    matchExpression.IsExhaustive = true
                    return
                }
            }
        }

        // Check if all union cases are covered
        caseIndex = 0
        while caseIndex < caseCount {
            unionCase := unionCases[caseIndex]
            patterns := new List<UnionCasePattern>()
            if unionCasePatterns.TryGetValue(unionCase.Name, out patterns) {
                hints := new List<string>()
                if IsUnionCaseCoveredByPatterns(unionType, unionDeclaration.Name, unionCase, patterns, substitution, out hints) {
                    coveredFlags[caseIndex] = 1
                } else {
                    partialFlags[caseIndex] = 1
                    if hints.Count > 0 {
                        partialCoverageHints[unionCase.Name] = hints
                    }
                }
            }

            caseIndex = caseIndex + 1
        }

        missingCases := new List<string>()
        partialMissingCases := new List<string>()
        neverCoveredCases := new List<string>()
        AnalyzerExhaustivenessSelector.SelectMissingUnionCasesFromFlags(unionCases, coveredFlags, partialFlags, caseCount, out missingCases, out partialMissingCases, out neverCoveredCases)

        if missingCases.Count == 0 {
            // All union cases covered by unguarded arms.
            matchExpression.IsExhaustive = true
            return
        }

        if partialMissingCases.Count > 0 {
            ReportPartiallyCoveredUnion(matchExpression, unionDeclaration.Name, missingCases, partialMissingCases, neverCoveredCases, partialCoverageHints)
            return
        }

        ReportMissingUnionCases(matchExpression, missingCases)
    }

    // The LONGER message, reached only when at least one case is partially covered: what is missing
    // outright, what is partial (with the nested hint where the walk found one), and a suggestion
    // per partial case naming the exact arm that would close it.
    func ReportPartiallyCoveredUnion(matchExpression: MatchExpression, unionName: string, missingCases: List<string>, partialMissingCases: List<string>, neverCoveredCases: List<string>, partialCoverageHints: Dictionary<string, List<string>>) {
        messageParts := new List<string>()
        if neverCoveredCases.Count > 0 {
            messageParts.Add("missing: " + string.Join(", ", neverCoveredCases))
        }

        messageParts.Add("partially covered: " + AnalyzerExhaustivenessSelector.FormatPartialCoverageCases(partialMissingCases, partialCoverageHints))

        hintParts := new List<string>()
        for caseName in partialMissingCases {
            hints := new List<string>()
            if partialCoverageHints.TryGetValue(caseName, out hints) && hints.Count > 0 {
                hintParts.Add("add '" + hints[0] + "', an unconstrained '" + unionName + "." + caseName + "' arm, or a wildcard '_' arm")
            } else {
                hintParts.Add("add an unconstrained '" + unionName + "." + caseName + "' arm or a wildcard '_' arm")
            }
        }

        diagnosticsValue.Report(ErrorCode.NonExhaustiveMatch, "This match doesn't cover all cases — " + string.Join("; ", messageParts) + ". " + string.Join("; ", hintParts) + ".", matchExpression.Line, matchExpression.Column, ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, string.Join(", ", missingCases)), MatchKeywordLength())
    }

    // The PLAIN missing-cases message, in its two shapes. The RICH builder is used whenever the
    // analysed file's text is available — it renders the source line, the explanation and the docs
    // link — and the one-line report is the fallback for a diagnostic with no text to point at.
    func ReportMissingUnionCases(matchExpression: MatchExpression, missingCases: List<string>) {
        sourceSnippet := diagnosticsValue.SourceSnippet(matchExpression.Line)
        filePath := diagnosticsValue.CurrentFilePath

        if sourceSnippet != null && filePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.NonExhaustiveMatch(filePath, matchExpression.Line, matchExpression.Column, sourceSnippet, MatchKeywordLength(), missingCases))
            return
        }

        missingCasesText := string.Join(", ", missingCases)
        diagnosticsValue.Report(ErrorCode.NonExhaustiveMatch, "This match doesn't cover all cases — missing: " + missingCasesText, matchExpression.Line, matchExpression.Column, ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, missingCasesText), MatchKeywordLength())
    }

    // AN ENUM, member by member. A member is covered by its QUALIFIED name (whose qualifier must be
    // the enum's own declared name — `Other.Active` covers nothing) or by a LITERAL equal to its
    // declared value, in the value kind the member was declared with.
    func CheckEnum(matchExpression: MatchExpression, enumType: EnumTypeInfo) {
        coveredMembers := new HashSet<string>()

        for matchCase in matchExpression.Cases {
            // Skip guarded arms
            if matchCase.Guard != null {
                continue
            }

            identPattern := matchCase.Pattern as IdentifierPattern
            if identPattern != null {
                if identPattern.Name == "_" {
                    matchExpression.IsExhaustive = true
                    return
                }
                // Wildcard covers all

                // Check for qualified enum member (e.g., Status.Active)
                if identPattern.Name.Contains('.') {
                    parts := identPattern.Name.Split('.')
                    qualifier := parts[0]
                    memberName := parts[parts.Length - 1]
                    // Only count if the qualifier matches the enum type name
                    if qualifier == enumType.Declaration.Name && EnumDeclaresMember(enumType, memberName) {
                        coveredMembers.Add(memberName)
                    }
                } else {
                    // Unqualified non-wildcard identifier — catch-all binding
                    matchExpression.IsExhaustive = true
                    return
                }

                continue
            }

            literalPattern := matchCase.Pattern as LiteralPattern
            if literalPattern != null {
                // Check if literal matches an enum member value
                for member in enumType.Declaration.Members {
                    patternStr := literalPattern.Literal as StringLiteralExpression
                    if member.ValueKind == EnumMemberValueKind.String && patternStr != null && member.ValueText == patternStr.Value {
                        coveredMembers.Add(member.Name)
                        continue
                    }

                    patternInt := literalPattern.Literal as IntLiteralExpression
                    if member.ValueKind == EnumMemberValueKind.Integer && patternInt != null && member.ValueText == patternInt.Value {
                        coveredMembers.Add(member.Name)
                    }
                }
            }
        }

        // Check if all enum members are covered. The missing-member selection is owned by
        // the shared exhaustiveness selector; do not recover with a duplicate.
        missingMembers := AnalyzerExhaustivenessSelector.SelectMissingEnumMembers(enumType.Declaration.Members, coveredMembers)

        if missingMembers.Count == 0 {
            // All enum members covered by unguarded arms.
            matchExpression.IsExhaustive = true
            return
        }

        sourceSnippet := diagnosticsValue.SourceSnippet(matchExpression.Line)
        filePath := diagnosticsValue.CurrentFilePath

        if sourceSnippet != null && filePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.NonExhaustiveMatch(filePath, matchExpression.Line, matchExpression.Column, sourceSnippet, MatchKeywordLength(), missingMembers))
            return
        }

        missingText := string.Join(", ", missingMembers)
        diagnosticsValue.Report(ErrorCode.NonExhaustiveMatch, "This match doesn't cover all enum members — missing: " + missingText, matchExpression.Line, matchExpression.Column, ErrorSuggestions.GetSuggestion(ErrorCode.NonExhaustiveMatch, null, missingText), MatchKeywordLength())
    }

    static func EnumDeclaresMember(enumType: EnumTypeInfo, memberName: string): bool {
        for member in enumType.Declaration.Members {
            if member.Name == memberName {
                return true
            }
        }

        return false
    }

    // WHETHER A CASE'S UNGUARDED ARMS COVER IT. One TOTAL arm settles it outright. Otherwise the
    // walk looks for the ONE shape that can still be exhaustive: every arm constrains exactly one
    // property, that property's type is itself a union, and the constraints between them name every
    // one of its cases TOTALLY. Anything else produces HINTS naming the nested arms still missing.
    func IsUnionCaseCoveredByPatterns(unionType: UnionTypeInfo, unionName: string, unionCase: UnionCase, patterns: List<UnionCasePattern>, substitution: Dictionary<string, TypeInfo>?, out partialCoverageHints: List<string>): bool {
        partialCoverageHints = new List<string>()

        for candidate in patterns {
            if AnalyzerExhaustivenessSelector.IsTotalUnionCasePattern(candidate) {
                return true
            }
        }

        coverageByProperty := new Dictionary<string, AnalyzerNestedUnionCoverage>(StringComparer.Ordinal)
        coverageOrder := new List<string>()

        for pattern in patterns {
            properties := pattern.Properties
            if properties == null {
                continue
            }

            constrainedProperty: PropertyPattern? = null
            constrainedCount := 0
            for property in properties {
                constrainedPattern := property.Pattern
                if constrainedPattern != null && !AnalyzerExhaustivenessSelector.IsCatchAllPattern(constrainedPattern) {
                    constrainedProperty = property
                    constrainedCount = constrainedCount + 1
                }
            }

            if constrainedCount != 1 || constrainedProperty == null {
                continue
            }

            if !OtherPropertiesAreTotal(properties, constrainedProperty) {
                continue
            }

            constrainedPropertyPattern := constrainedProperty.Pattern
            if constrainedPropertyPattern == null {
                continue
            }

            caseProperty := FindCaseProperty(unionCase, constrainedProperty.Name)
            if caseProperty == null {
                continue
            }

            // Apply the scrutinee's generic substitution so a `value: T` property on a
            // Result<Option<int>> scrutinee resolves to the nested union for coverage.
            propertyType := typeSubstitutionValue.ResolveTypeForSourceOwner(caseProperty.Type, unionType, substitution)

            nestedSubstitution: Dictionary<string, TypeInfo>? = null
            nestedUnionType := ResolveDeclaredUnionType(propertyType, out nestedSubstitution)
            if nestedUnionType == null {
                continue
            }

            nestedCaseName := AnalyzerExhaustivenessSelector.GetMatchedUnionCaseName(nestedUnionType, constrainedPropertyPattern)

            if nestedCaseName == null {
                continue
            }

            coverage := EnsureNestedCoverage(coverageByProperty, coverageOrder, constrainedProperty.Name, nestedUnionType)

            coverage.AddCoveredCase(nestedCaseName)
            if !AnalyzerExhaustivenessSelector.IsTotalNestedUnionPattern(constrainedPropertyPattern) {
                coverage.AddConstrainedCase(nestedCaseName)
            }
        }

        for propertyName in coverageOrder {
            coverage := coverageByProperty[propertyName]

            if coverage.AllDeclaredCasesCovered() && coverage.ConstrainedCaseCount() == 0 {
                return true
            }

            for missingNestedCase in coverage.MissingOrConstrainedCases() {
                partialCoverageHints.Add(unionName + "." + unionCase.Name + " { " + propertyName + ": " + coverage.UnionName + "." + missingNestedCase + " }")
            }
        }

        return false
    }

    // The tally for one property, created on first sight with the nested union's cases already
    // enrolled. `coverageOrder` mirrors the dictionary's insertion order, which is the order the
    // hints below are produced in.
    static func EnsureNestedCoverage(coverageByProperty: Dictionary<string, AnalyzerNestedUnionCoverage>, coverageOrder: List<string>, propertyName: string, nestedUnionType: UnionTypeInfo): AnalyzerNestedUnionCoverage {
        if coverageByProperty.ContainsKey(propertyName) {
            return coverageByProperty[propertyName]
        }

        created := new AnalyzerNestedUnionCoverage(nestedUnionType.Declaration.Name)
        for nestedCase in nestedUnionType.Declaration.Cases {
            created.AddDeclaredCase(nestedCase.Name)
        }

        coverageByProperty[propertyName] = created
        coverageOrder.Add(propertyName)
        return created
    }

    static func OtherPropertiesAreTotal(properties: List<PropertyPattern>, constrainedProperty: PropertyPattern): bool {
        for property in properties {
            if Object.ReferenceEquals(property, constrainedProperty) {
                continue
            }

            if !AnalyzerExhaustivenessSelector.IsTotalPropertyPattern(property) {
                return false
            }
        }

        return true
    }

    static func FindCaseProperty(unionCase: UnionCase, name: string): UnionCaseProperty? {
        properties := unionCase.Properties
        if properties == null {
            return null
        }

        for property in properties {
            if property.Name == name {
                return property
            }
        }

        return null
    }

    // The width of the `match` keyword. Every non-exhaustive diagnostic underlines the keyword
    // itself rather than the arms, so the report points at the decision and not at one of its parts.
    static func MatchKeywordLength(): int {
        return 5
    }

    // A resolved type's own display form, read through an `object`-typed local because `ToString`
    // is declared by the BASE of the TypeInfo hierarchy rather than by the hierarchy itself.
    static func TypeText(resolved: TypeInfo): string {
        boxed: object = resolved
        rendered := boxed.ToString()
        if rendered == null {
            return ""
        }

        return rendered
    }
}

// One property's nested-union coverage tally. The three sets are kept as ORDERED, deduplicated
// lists because the hint list they produce is user-visible text whose order is the nested union's
// declaration order followed by the constrained cases in the order the arms introduced them.
class AnalyzerNestedUnionCoverage {
    unionNameValue: string
    declaredCasesValue: List<string>
    declaredCaseSetValue: HashSet<string>
    coveredCasesValue: HashSet<string>
    constrainedCasesValue: List<string>
    constrainedCaseSetValue: HashSet<string>

    UnionName: string => unionNameValue

    constructor(unionName: string) {
        unionNameValue = unionName
        declaredCasesValue = new List<string>()
        declaredCaseSetValue = new HashSet<string>()
        coveredCasesValue = new HashSet<string>()
        constrainedCasesValue = new List<string>()
        constrainedCaseSetValue = new HashSet<string>()
    }

    func AddDeclaredCase(name: string) {
        if declaredCaseSetValue.Add(name) {
            declaredCasesValue.Add(name)
        }
    }

    func AddCoveredCase(name: string) {
        coveredCasesValue.Add(name)
    }

    func AddConstrainedCase(name: string) {
        if constrainedCaseSetValue.Add(name) {
            constrainedCasesValue.Add(name)
        }
    }

    func ConstrainedCaseCount(): int {
        return constrainedCasesValue.Count
    }

    func AllDeclaredCasesCovered(): bool {
        for name in declaredCasesValue {
            if !coveredCasesValue.Contains(name) {
                return false
            }
        }

        return true
    }

    // The declared cases no arm covered, in declaration order, followed by the covered-but-still-
    // constrained ones in arm order. The two are disjoint — a constrained case is by definition a
    // covered one — so no further deduplication is needed.
    func MissingOrConstrainedCases(): List<string> {
        result := new List<string>()

        for name in declaredCasesValue {
            if !coveredCasesValue.Contains(name) {
                result.Add(name)
            }
        }

        for name in constrainedCasesValue {
            result.Add(name)
        }

        return result
    }
}
