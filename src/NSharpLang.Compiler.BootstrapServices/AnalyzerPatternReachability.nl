namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHETHER A TYPE TEST CAN EVER SUCCEED — the analyzer's one reachability judgement — and its two
// diagnostics.
//
// The question is asked at exactly two places and it is the SAME question at both: a `match` arm's
// TYPE PATTERN (`Dog d => …`) and an `is` expression (`value is Dog`). Both answer it about a pair
// of types and neither looks at the value, so the whole judgement is pure over two `TypeInfo`s: it
// declares no symbol, re-enters no walk and reads no scope. What differs is only the MESSAGE and the
// SPAN, which is why the two reporters live here beside it rather than at the call sites.
//
// IT IS A "PROVABLY NEVER" TEST, NOT A "PROBABLY NOT" TEST. Every arm that cannot decide answers
// TRUE, and it answers true FIRST: an unknown operand, a reflected operand, a generic operand, an
// interface on either side, `object` on either side, a nullable on either side and a union on either
// side all return before any negative reasoning starts. That ordering is the whole design — a
// diagnostic that says "this can never match" must never be wrong, so anything the analyzer models
// only partially is admitted rather than rejected.
//
// THE FOUR WAYS TO SAY NO ARE, IN ORDER: two value types that are not the same type; a value tested
// against a reference type it is not assignable to; a reference tested against a value type; and a
// SEALED class tested against another class. The assignability tests run BETWEEN the value/reference
// checks and the sealed checks, in both directions, because either direction makes the test
// meaningful — an upcast is a tautology and a downcast is the ordinary use.
//
// A MEASURED FACT ABOUT THE TWO INNER INTERFACE GUARDS. The value-to-reference and
// reference-to-value arms each re-test their partner for `InterfaceTypeInfo` before refusing. That
// test can never be true: the interface arm above has already returned. Instrumenting the baseline
// over the whole corpus and 94 fixtures confirmed it — the two arms fired 10 times and the inner
// guard blocked ZERO of them, while `int is Shape` took the INTERFACE arm. The guards are preserved
// verbatim because this is an ownership move, not a simplification; a later slice may delete them
// with its own evidence.
class AnalyzerPatternReachability {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    declarationContextValue: AnalyzerDeclarationContext
    assignabilityValue: AnalyzerAssignability

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, declarationContext: AnalyzerDeclarationContext, assignability: AnalyzerAssignability) {
        diagnosticsValue = diagnostics
        spansValue = spans
        declarationContextValue = declarationContext
        assignabilityValue = assignability
    }

    // A `match` arm's type pattern. The span is the pattern's own name; the message names the
    // PATTERN, because that is what the reader wrote.
    func CheckTypePattern(pattern: TypePattern, valueType: TypeInfo, targetType: TypeInfo) {
        if IsPatternPossible(valueType, targetType) {
            return
        }

        valueObject := valueType as object
        targetObject := targetType as object
        valueText := valueObject.ToString()
        targetText := targetObject.ToString()
        span := spansValue.GetPatternNameDiagnosticSpan(pattern)
        diagnosticsValue.Report(ErrorCode.ImpossiblePattern, "This '" + targetText + "' pattern can never match — a '" + valueText + "' is never a '" + targetText + "'", span.Line, span.Column, null, span.Length)
    }

    // An `is` expression. The span is `is` through the tested type name; the message names the TEST
    // and says it is always false, which is the useful reading of a condition that cannot hold.
    func CheckIsExpression(isExpr: IsExpression, sourceType: TypeInfo, targetType: TypeInfo) {
        if IsPatternPossible(sourceType, targetType) {
            return
        }

        sourceObject := sourceType as object
        targetObject := targetType as object
        sourceText := sourceObject.ToString()
        targetText := targetObject.ToString()
        span := spansValue.GetIsExpressionDiagnosticSpan(isExpr)
        diagnosticsValue.Report(ErrorCode.ImpossiblePattern, "This 'is " + targetText + "' check is always false — a '" + sourceText + "' is never a '" + targetText + "'", span.Line, span.Column, null, span.Length)
    }

    // THE JUDGEMENT. True means "a value of `sourceType` might be a `targetType` at run time"; false
    // means the analyzer can PROVE it never is.
    func IsPatternPossible(sourceType: TypeInfo, targetType: TypeInfo): bool {
        resolvedSource := declarationContextValue.ResolveDeclaredAlias(sourceType)
        resolvedTarget := declarationContextValue.ResolveDeclaredAlias(targetType)

        // Everything the analyzer does not fully model is ADMITTED, and admitted first.
        unknownSource := resolvedSource as UnknownTypeInfo
        unknownTarget := resolvedTarget as UnknownTypeInfo
        if unknownSource != null || unknownTarget != null {
            return true
        }

        reflectedSource := resolvedSource as ReflectionTypeInfo
        reflectedTarget := resolvedTarget as ReflectionTypeInfo
        if reflectedSource != null || reflectedTarget != null {
            return true
        }

        genericSource := resolvedSource as GenericTypeInfo
        genericTarget := resolvedTarget as GenericTypeInfo
        if genericSource != null || genericTarget != null {
            return true
        }

        // The same declaration handle, or the same simple type by name.
        if Object.ReferenceEquals(resolvedSource, resolvedTarget) {
            return true
        }

        simpleSource := resolvedSource as SimpleTypeInfo
        simpleTarget := resolvedTarget as SimpleTypeInfo
        if simpleSource != null && simpleTarget != null {
            simpleTargetObject := simpleTarget as object
            if simpleSource.Equals(simpleTargetObject) {
                return true
            }
        }

        // An interface on either side admits any implementor the analyzer has not seen.
        interfaceSource := resolvedSource as InterfaceTypeInfo
        interfaceTarget := resolvedTarget as InterfaceTypeInfo
        if interfaceSource != null || interfaceTarget != null {
            return true
        }

        if BuiltInTypes.Is(resolvedSource, BuiltInTypes.Object) || BuiltInTypes.Is(resolvedTarget, BuiltInTypes.Object) {
            return true
        }

        nullableSource := resolvedSource as NullableTypeInfo
        nullableTarget := resolvedTarget as NullableTypeInfo
        if nullableSource != null || nullableTarget != null {
            return true
        }

        unionSource := resolvedSource as UnionTypeInfo
        unionTarget := resolvedTarget as UnionTypeInfo
        anonymousUnionSource := resolvedSource as AnonymousUnionTypeInfo
        anonymousUnionTarget := resolvedTarget as AnonymousUnionTypeInfo
        if unionSource != null || unionTarget != null || anonymousUnionSource != null || anonymousUnionTarget != null {
            return true
        }

        // From here the answer can be NO.
        sourceIsValue := !AnalyzerConversionFacts.IsReferenceType(resolvedSource)
        targetIsValue := !AnalyzerConversionFacts.IsReferenceType(resolvedTarget)
        if sourceIsValue && targetIsValue {
            return false
        }

        // Either direction is a meaningful test: an upcast is always true and a downcast is the
        // ordinary use, and both mean the test can succeed.
        if assignabilityValue.IsAssignable(resolvedTarget, resolvedSource) {
            return true
        }

        if assignabilityValue.IsAssignable(resolvedSource, resolvedTarget) {
            return true
        }

        if sourceIsValue && !targetIsValue {
            if interfaceTarget == null {
                return false
            }
        }

        if targetIsValue && !sourceIsValue {
            if interfaceSource == null {
                return false
            }
        }

        // A sealed class has no subclass to be the missing link between two unrelated classes.
        sourceClass := resolvedSource as ClassTypeInfo
        targetClass := resolvedTarget as ClassTypeInfo
        if sourceClass != null && sourceClass.IsSealed {
            if targetClass != null {
                return false
            }
        }

        if targetClass != null && targetClass.IsSealed {
            if sourceClass != null {
                return false
            }
        }

        return true
    }
}

// WHETHER A SUBTREE CARRIES A PARSER RECOVERY ARTIFACT.
//
// When the recovery parser cannot read a name it does not stop — it mints a synthetic
// `IdentifierExpression("<error>")` or an `<error>` member name and keeps building, so that an
// editor still gets a tree for the rest of the file. Every such node is a SYNTAX diagnostic that has
// already been reported. This walk exists so the SEMANTIC analyzer never reports a second time about
// the same broken text: a return whose value is an artifact does not count as a return, a condition
// that contains one is not scolded for its type, and a discarded expression that contains one is not
// examined at all.
//
// IT IS THE MOST-EXECUTED MEMBER IN THIS SLICE BY THREE ORDERS OF MAGNITUDE. Measured over the
// 72-target corpus it is entered 392,769 times and answers TRUE not once — the compiler's own
// sources are well-formed — while the fixtures that carry malformed sources answer true 105 times.
// It is a pure walk over the expression and pattern trees with no state, which is why it is static.
//
// THE PATTERN AND PROPERTY-PATTERN ENTRY POINTS ARE PART OF THIS WALK, NOT BESIDE IT. A match arm's
// pattern can hold expressions (a literal pattern's literal, a relational pattern's bound), so the
// expression walk descends into patterns and the pattern walk descends back into expressions. The
// three entry points are one mutually recursive function with three argument shapes.
class AnalyzerParserErrorPlaceholders {

    // The name the recovery parser mints for a token it could not read. One spelling, shared with the
    // guard that keeps it out of user-facing sentences, so the walk and the guard cannot disagree.
    static func PlaceholderName(): string {
        return DiagnosticPlaceholderGuard.PlaceholderName()
    }

    static func ContainsInExpression(expression: Expression): bool {
        identifier := expression as IdentifierExpression
        if identifier != null {
            return identifier.Name == PlaceholderName()
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            if memberAccess.MemberName == PlaceholderName() {
                return true
            }

            return ContainsInExpression(memberAccess.Object)
        }

        interpolatedString := expression as InterpolatedStringExpression
        if interpolatedString != null {
            parts := interpolatedString.Parts
            partIndex := 0
            while partIndex < parts.Count {
                part := parts[partIndex]
                hole := part as InterpolatedStringHole
                if hole != null && ContainsInExpression(hole.Expression) {
                    return true
                }

                partIndex = partIndex + 1
            }

            return false
        }

        range := expression as RangeExpression
        if range != null {
            rangeStart := range.Start
            if rangeStart != null && ContainsInExpression(rangeStart) {
                return true
            }

            rangeEnd := range.End
            return rangeEnd != null && ContainsInExpression(rangeEnd)
        }

        call := expression as CallExpression
        if call != null {
            if ContainsInExpression(call.Callee) {
                return true
            }

            return ContainsInArguments(call.Arguments)
        }

        binary := expression as BinaryExpression
        if binary != null {
            return ContainsInExpression(binary.Left) || ContainsInExpression(binary.Right)
        }

        assignment := expression as AssignmentExpression
        if assignment != null {
            return ContainsInExpression(assignment.Target) || ContainsInExpression(assignment.Value)
        }

        lambda := expression as LambdaExpression
        if lambda != null {
            lambdaBody := lambda.ExpressionBody
            return lambdaBody != null && ContainsInExpression(lambdaBody)
        }

        unary := expression as UnaryExpression
        if unary != null {
            return ContainsInExpression(unary.Operand)
        }

        mustExpression := expression as MustExpression
        if mustExpression != null {
            return ContainsInExpression(mustExpression.Expression)
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return ContainsInExpression(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return ContainsInExpression(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return ContainsInExpression(uncheckedExpression.Expression)
        }

        allocExpression := expression as AllocExpression
        if allocExpression != null {
            return ContainsInExpression(allocExpression.Expression)
        }

        stackAllocExpression := expression as StackAllocExpression
        if stackAllocExpression != null {
            return ContainsInExpression(stackAllocExpression.LengthExpression)
        }

        indexAccess := expression as IndexAccessExpression
        if indexAccess != null {
            return ContainsInExpression(indexAccess.Object) || ContainsInExpression(indexAccess.Index)
        }

        cast := expression as CastExpression
        if cast != null {
            return ContainsInExpression(cast.Expression)
        }

        isExpression := expression as IsExpression
        if isExpression != null {
            return ContainsInExpression(isExpression.Expression)
        }

        awaitExpression := expression as AwaitExpression
        if awaitExpression != null {
            return ContainsInExpression(awaitExpression.Expression)
        }

        throwExpression := expression as ThrowExpression
        if throwExpression != null {
            return ContainsInExpression(throwExpression.Expression)
        }

        ternary := expression as TernaryExpression
        if ternary != null {
            return ContainsInExpression(ternary.Condition) || ContainsInExpression(ternary.ThenExpression) || ContainsInExpression(ternary.ElseExpression)
        }

        array := expression as ArrayLiteralExpression
        if array != null {
            elements := array.Elements
            elementIndex := 0
            while elementIndex < elements.Count {
                element := elements[elementIndex]
                if ContainsInExpression(element) {
                    return true
                }

                elementIndex = elementIndex + 1
            }

            return false
        }

        tuple := expression as TupleExpression
        if tuple != null {
            tupleElements := tuple.Elements
            tupleIndex := 0
            while tupleIndex < tupleElements.Count {
                tupleElement := tupleElements[tupleIndex]
                if ContainsInExpression(tupleElement.Value) {
                    return true
                }

                tupleIndex = tupleIndex + 1
            }

            return false
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            if ContainsInArguments(newExpression.ConstructorArguments) {
                return true
            }

            initializer := newExpression.Initializer
            if initializer != null && ContainsInExpression(initializer) {
                return true
            }

            arrayLength := newExpression.ArrayLengthExpression
            return arrayLength != null && ContainsInExpression(arrayLength)
        }

        objectInitializer := expression as ObjectInitializerExpression
        if objectInitializer != null {
            return ContainsInPropertyInitializers(objectInitializer.Properties)
        }

        withExpression := expression as WithExpression
        if withExpression != null {
            if ContainsInExpression(withExpression.Target) {
                return true
            }

            return ContainsInPropertyInitializers(withExpression.Properties)
        }

        spread := expression as SpreadExpression
        if spread != null {
            return ContainsInExpression(spread.Expression)
        }

        matchExpression := expression as MatchExpression
        if matchExpression != null {
            if ContainsInExpression(matchExpression.Value) {
                return true
            }

            cases := matchExpression.Cases
            caseIndex := 0
            while caseIndex < cases.Count {
                matchCase := cases[caseIndex]
                if ContainsInPattern(matchCase.Pattern) {
                    return true
                }

                guard := matchCase.Guard
                if guard != null && ContainsInExpression(guard) {
                    return true
                }

                if ContainsInExpression(matchCase.Expression) {
                    return true
                }

                caseIndex = caseIndex + 1
            }

            return false
        }

        nameofExpression := expression as NameofExpression
        if nameofExpression != null {
            return ContainsInExpression(nameofExpression.Target)
        }

        return false
    }

    // The pattern entry point. A pattern kind with no expression and no sub-pattern — an identifier,
    // a slice, a type pattern — carries no artifact of its own; the parser records ITS failures in
    // the name, which the pattern's own diagnostics read.
    static func ContainsInPattern(pattern: Pattern): bool {
        literal := pattern as LiteralPattern
        if literal != null {
            return ContainsInExpression(literal.Literal)
        }

        relational := pattern as RelationalPattern
        if relational != null {
            return ContainsInExpression(relational.Value)
        }

        unionCase := pattern as UnionCasePattern
        if unionCase != null {
            unionCaseProperties := unionCase.Properties
            if unionCaseProperties == null {
                return false
            }

            return ContainsInPropertyPatterns(unionCaseProperties)
        }

        objectPattern := pattern as ObjectPattern
        if objectPattern != null {
            return ContainsInPropertyPatterns(objectPattern.Properties)
        }

        listPattern := pattern as ListPattern
        if listPattern != null {
            elements := listPattern.Elements
            elementIndex := 0
            while elementIndex < elements.Count {
                element := elements[elementIndex]
                if ContainsInPattern(element) {
                    return true
                }

                elementIndex = elementIndex + 1
            }

            return false
        }

        andPattern := pattern as AndPattern
        if andPattern != null {
            return ContainsInPattern(andPattern.Left) || ContainsInPattern(andPattern.Right)
        }

        orPattern := pattern as OrPattern
        if orPattern != null {
            return ContainsInPattern(orPattern.Left) || ContainsInPattern(orPattern.Right)
        }

        notPattern := pattern as NotPattern
        if notPattern != null {
            return ContainsInPattern(notPattern.Pattern)
        }

        positional := pattern as PositionalPattern
        if positional != null {
            positionalPatterns := positional.Patterns
            positionalIndex := 0
            while positionalIndex < positionalPatterns.Count {
                nested := positionalPatterns[positionalIndex]
                if ContainsInPattern(nested) {
                    return true
                }

                positionalIndex = positionalIndex + 1
            }

            return false
        }

        return false
    }

    // A property pattern with no nested pattern — `{ Name: n }`, a pure binding — carries nothing.
    static func ContainsInPropertyPattern(property: PropertyPattern): bool {
        nested := property.Pattern
        return nested != null && ContainsInPattern(nested)
    }

    static func ContainsInArguments(arguments: List<Argument>): bool {
        index := 0
        while index < arguments.Count {
            argument := arguments[index]
            if ContainsInExpression(argument.Value) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func ContainsInPropertyInitializers(properties: List<PropertyInitializer>): bool {
        index := 0
        while index < properties.Count {
            property := properties[index]
            indexExpression := property.IndexExpression
            if indexExpression != null && ContainsInExpression(indexExpression) {
                return true
            }

            if ContainsInExpression(property.Value) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func ContainsInPropertyPatterns(properties: List<PropertyPattern>): bool {
        index := 0
        while index < properties.Count {
            property := properties[index]
            if ContainsInPropertyPattern(property) {
                return true
            }

            index = index + 1
        }

        return false
    }
}
