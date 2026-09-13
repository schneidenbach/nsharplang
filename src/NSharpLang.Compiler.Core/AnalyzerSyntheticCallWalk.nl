namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE SOURCE BINDER'S WALK — overload selection, match scoring and generic inference for a call to
// an N#-DECLARED function, plus the span the constraint reports anchor on.
//
// This is the last member of the source-binder family to move. The three walk members are one unit:
// `BindNSharpCall` selects an overload by asking `GetCallMatchScore` for each candidate, and the
// score cannot be computed without the inference `InferGenericBindings` produces, so splitting them
// would put a scoring rule on one side of the boundary and its input on the other.
//
// THE ONE THING THIS OWNER CANNOT COMPUTE, AND WHY IT IS A PARAMETER RATHER THAN A CALLBACK.
// A receiver-style call — `xs.FirstOr(0)`, where `FirstOr` declares `this xs: T[]` — supplies its
// FIRST source parameter from the member-access RECEIVER, not from the argument list. Inference
// therefore has to see the receiver's TYPE, and only the analyzer's own expression walk can answer
// that. The old C# member re-entered that walk in line, once per candidate. It cannot re-enter it
// from here, and a provider handed across the boundary would be a callback, so the receiver type
// arrives as an ordinary VALUE and the DECISION about whether one is needed at all stays here:
// `NeedsReceiverType` IS the guard the walk itself applies, so the caller cannot analyse an
// expression the walk would not have analysed, nor skip one it would.
//
// THE MEASUREMENT THAT SETTLED THE SHAPE. Reading the receiver's type back out of the semantic
// model instead of analysing it is WRONG, and the counterexample is a method group used as a value
// (`Read.Tag("mg")`): the callee walk records the receiver under
// `AllowUnboundCallableReference` and stores a `FunctionTypeInfo`, while the walk's own
// analysis — run with that flag at its outer value — answers `unknown` AND IS THE SOLE PRODUCER of
// the NL411 that says the method must be called. A cache read would return the wrong type and
// delete a user-visible diagnostic.
//
// THE GATE SEQUENCE IS STATED ONCE. `TryGetScoringPlacement` is the arity-and-placement gate a
// candidate must clear before it is scored at all, and BOTH the scorer and the receiver-type
// question read it, so the two can never disagree about which candidates reach the inference walk.
class AnalyzerSyntheticCallWalk {
    typeResolver: AnalyzerTypeResolver
    binder: AnalyzerSyntheticCallBinder
    reporter: AnalyzerSyntheticCallReporter
    overloadScoring: AnalyzerOverloadScoring
    assignability: AnalyzerAssignability
    spans: AnalyzerDiagnosticSpans
    diagnostics: AnalyzerDiagnosticSink

    constructor(resolver: AnalyzerTypeResolver, callBinder: AnalyzerSyntheticCallBinder, callReporter: AnalyzerSyntheticCallReporter, scoring: AnalyzerOverloadScoring, assignabilityOwner: AnalyzerAssignability, spanResolver: AnalyzerDiagnosticSpans, diagnosticSink: AnalyzerDiagnosticSink) {
        typeResolver = resolver
        binder = callBinder
        reporter = callReporter
        overloadScoring = scoring
        assignability = assignabilityOwner
        spans = spanResolver
        diagnostics = diagnosticSink
    }

    // WHETHER THE INFERENCE WALK WILL READ THE MEMBER-ACCESS RECEIVER'S TYPE.
    //
    // This is the walk's own guard, hoisted so the caller can answer it before deciding to analyse
    // an expression. Every clause is one of `InferGenericBindings`' early exits, in the same order:
    // a non-generic signature never infers; a call that wrote out ALL of its type arguments is
    // already closed; a signature with no SOURCE parameter types has nothing to match against; and
    // a start index of zero means the first parameter is supplied positionally, so there is no
    // receiver to read. `GetSyntheticParameterStartIndex` is 1 only for a `this` parameter invoked
    // THROUGH a member access, so the member-access half needs no separate test here.
    static func NeedsReceiverType(functionType: FunctionTypeInfo, call: CallExpression): bool {
        typeParameters := functionType.TypeParameters
        if typeParameters == null || typeParameters.Count == 0 {
            return false
        }

        typeArguments := call.TypeArguments
        if typeArguments != null && typeArguments.Count > 0 {
            if typeArguments.Count >= typeParameters.Count {
                return false
            }
        }

        sourceParameterTypes := functionType.SourceParameterTypes
        if sourceParameterTypes == null || sourceParameterTypes.Count == 0 {
            return false
        }

        return AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call) > 0
    }

    // The same question for an OVERLOAD GROUP: does any candidate that survives the scoring gate
    // reach the inference walk's receiver arm? A candidate the arity tables reject never gets
    // there, so asking `NeedsReceiverType` alone would over-answer and analyse a receiver the
    // current walk never touches.
    func AnyCandidateNeedsReceiverType(candidates: IReadOnlyList<FunctionTypeInfo>, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>): bool {
        index := 0
        while index < candidates.Count {
            candidate := candidates[index]
            placement: int[] = new int[0]
            if TryGetScoringPlacement(candidate, call, argTypes, out placement) {
                if NeedsReceiverType(candidate, call) {
                    return true
                }
            }

            index = index + 1
        }

        return false
    }

    // THE BEST-MATCHING OVERLOAD among N#-declared candidates, or null when none applies.
    //
    // THE APPLICABLE CANDIDATES ARE COLLECTED FIRST AND COMPARED AFTERWARDS, because "better function
    // member" (ECMA-334 §12.6.4.3) is a PARTIAL order and a running best is a total one: a fold that
    // keeps one winner has to decide every pair the language leaves incomparable, and whatever it
    // decides depends on the order the candidates were declared in. The comparison is
    // `AnalyzerOverloadSpecificity`'s, the same owner the reflected world folds into, and the winner
    // is read off it by `FindMaximalIndexes` — the candidates NOTHING beats.
    //
    // The chain, in order: the SCORE decides first, then C#'s better-conversion rule over each
    // argument's expected type, then fewer type parameters bound by inference (an overload that
    // matched a WRITTEN type is more specific than one that matched by binding `T`), then a
    // non-params overload over a params one, then more parameters over fewer (an overload that used
    // defaults is less specific than one that did not). Two candidates still maximal after all of
    // that are AMBIGUOUS and are reported as NL414 rather than resolved by declaration order.
    func BindNSharpCall(candidates: IReadOnlyList<FunctionTypeInfo>, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, receiverType: TypeInfo?): FunctionTypeInfo? {
        applicable := new List<FunctionTypeInfo>()
        scores := new List<int>()
        comparisonsByCandidate := new List<SyntheticArgumentComparison?[]>()

        index := 0
        while index < candidates.Count {
            candidate := candidates[index]
            index = index + 1

            score := GetCallMatchScore(candidate, call, argTypes, receiverType)
            if score < 0 {
                continue
            }

            applicable.Add(candidate)
            scores.Add(score)
            comparisonsByCandidate.Add(GetCallArgumentComparisons(candidate, call, argTypes, receiverType))
        }

        if applicable.Count == 0 {
            return null
        }

        if applicable.Count == 1 {
            return applicable[0]
        }

        count := applicable.Count
        comparisons := new int[count * count]
        row := 0
        while row < count {
            column := 0
            while column < count {
                if row != column {
                    comparisons[row * count + column] = CompareNSharpCandidates(applicable[row], applicable[column], scores[row], scores[column], comparisonsByCandidate[row], comparisonsByCandidate[column], call, argTypes)
                }

                column = column + 1
            }

            row = row + 1
        }

        maximal := AnalyzerOverloadSpecificity.FindMaximalIndexes(comparisons, count)
        if maximal.Count == 0 {
            return applicable[0]
        }

        bestFunction := applicable[maximal[0]]
        if maximal.Count > 1 {
            reporter.ReportAmbiguousCall(bestFunction, applicable[maximal[1]], call)
        }

        return bestFunction
    }

    // THE SOURCE WORLD'S "BETTER FUNCTION MEMBER", answered by supplying this world's conversion
    // oracle — `AnalyzerAssignability` over `TypeInfo` — to `AnalyzerOverloadSpecificity`.
    //
    // The score decides first for the same reason it does in the reflected world: it is the
    // applicability ladder, and specificity separates the candidates it rated the same.
    func CompareNSharpCandidates(left: FunctionTypeInfo, right: FunctionTypeInfo, leftScore: int, rightScore: int, leftComparisons: SyntheticArgumentComparison?[], rightComparisons: SyntheticArgumentComparison?[], call: CallExpression, argTypes: IReadOnlyList<TypeInfo>): int {
        if leftScore != rightScore {
            if leftScore > rightScore {
                return AnalyzerOverloadSpecificity.LeftIsBetter
            }

            return AnalyzerOverloadSpecificity.RightIsBetter
        }

        verdicts := new List<int>()
        index := 0
        while index < leftComparisons.Length && index < rightComparisons.Length {
            currentIndex := index
            index = index + 1

            leftComparison := leftComparisons[currentIndex]
            rightComparison := rightComparisons[currentIndex]
            if leftComparison == null || rightComparison == null {
                continue
            }

            leftExpected := leftComparison.ExpectedType
            rightExpected := rightComparison.ExpectedType
            leftArgument := leftComparison.ArgumentType
            rightArgument := rightComparison.ArgumentType
            if leftExpected == null || rightExpected == null || leftArgument == null || rightArgument == null {
                continue
            }

            // THE TWO CANDIDATES MUST BE ASKED ABOUT THE SAME ARGUMENT. A `params` tail can make one
            // candidate compare a spread's ELEMENT where the other compares the whole array, and a
            // verdict folded from two different questions is not a verdict at all.
            if !TypeInfoIdentityFacts.AreEqual(leftArgument, rightArgument) {
                continue
            }

            if BuiltInTypes.IsUnknown(leftArgument) || BuiltInTypes.IsUnknown(leftExpected) || BuiltInTypes.IsUnknown(rightExpected) {
                continue
            }

            verdicts.Add(AnalyzerOverloadSpecificity.CompareConversionTargets(
                TypeInfoIdentityFacts.AreEqual(leftExpected, leftArgument),
                TypeInfoIdentityFacts.AreEqual(rightExpected, leftArgument),
                assignability.IsAssignable(rightExpected, leftExpected),
                assignability.IsAssignable(leftExpected, rightExpected)
            ))
        }

        conversionVerdict := AnalyzerOverloadSpecificity.FoldArgumentVerdicts(verdicts)
        if conversionVerdict != AnalyzerOverloadSpecificity.NeitherIsBetter {
            return conversionVerdict
        }

        leftGenericParameterCost := AnalyzerSyntheticCallFacts.GetGenericParameterCost(left, call, argTypes)
        rightGenericParameterCost := AnalyzerSyntheticCallFacts.GetGenericParameterCost(right, call, argTypes)
        if leftGenericParameterCost != rightGenericParameterCost {
            if leftGenericParameterCost < rightGenericParameterCost {
                return AnalyzerOverloadSpecificity.LeftIsBetter
            }

            return AnalyzerOverloadSpecificity.RightIsBetter
        }

        leftParameterCount := GetSyntheticSuppliedParameterCount(left, call)
        rightParameterCount := GetSyntheticSuppliedParameterCount(right, call)

        // `CompareTieBreaks` reads the params and default keys; the "more declared parameters wins"
        // rule is expressed as the DEFAULT count each candidate would have to fill, which is what the
        // reflected world counts too.
        return AnalyzerOverloadSpecificity.CompareTieBreaks(false, false, false, HasSyntheticParamsTail(left), HasSyntheticParamsTail(right), Math.Max(0, leftParameterCount - argTypes.Count), Math.Max(0, rightParameterCount - argTypes.Count))
    }

    // How many parameters the CALLER supplies for this candidate — the receiver offset comes off.
    static func GetSyntheticSuppliedParameterCount(functionType: FunctionTypeInfo, call: CallExpression): int {
        parameterTypes := functionType.ParameterTypes
        parameterCount := 0
        if parameterTypes != null {
            parameterCount = parameterTypes.Count
        }

        return Math.Max(0, parameterCount - AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call))
    }

    static func HasSyntheticParamsTail(functionType: FunctionTypeInfo): bool {
        parameterTypes := functionType.ParameterTypes
        parameterCount := 0
        if parameterTypes != null {
            parameterCount = parameterTypes.Count
        }

        return AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, parameterCount) >= 0
    }

    // ONE CANDIDATE'S ARGUMENT COMPARISON PER WRITTEN ARGUMENT, with this candidate's own inference
    // substituted in. It asks the same `GetArgumentComparisonTypes` the scorer asks, so the types the
    // specificity rule compares are exactly the types the score was computed from. A position the
    // placement could not fill, or one the comparison declares carries no information, is left null
    // and the rule asks nothing about it.
    func GetCallArgumentComparisons(functionType: FunctionTypeInfo, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, receiverType: TypeInfo?): SyntheticArgumentComparison?[] {
        comparisons := new SyntheticArgumentComparison?[](call.Arguments.Count)
        parameterIndexByArgument: int[] = new int[0]
        if !TryGetScoringPlacement(functionType, call, argTypes, out parameterIndexByArgument) {
            return comparisons
        }

        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null {
            return comparisons
        }

        expectedCount := parameterTypes.Count
        parameterStartIndex := AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call)
        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, expectedCount)
        genericBindings := InferGenericBindings(functionType, call, argTypes, receiverType)

        argumentIndex := 0
        while argumentIndex < call.Arguments.Count {
            currentArgument := argumentIndex
            argumentIndex = argumentIndex + 1
            parameterIndex := parameterIndexByArgument[currentArgument]
            if parameterIndex < 0 || parameterIndex >= expectedCount {
                continue
            }

            comparison := binder.GetArgumentComparisonTypes(functionType, call, argTypes, currentArgument, parameterIndex, paramsParameterIndex, parameterStartIndex, genericBindings)
            if comparison.Matched {
                comparisons[currentArgument] = comparison
            }
        }

        return comparisons
    }

    // HOW WELL ONE CANDIDATE MATCHES, or -1 when it does not apply at all. Zero is a real score —
    // an applicable overload every one of whose positions carries no comparable type scores zero —
    // so the "does not apply" answer has to live outside the score's range.
    //
    // A position that compares UNKNOWN on either side, or an SoA row, is SKIPPED rather than
    // rejected: the arity tables already admitted the candidate and an unresolvable position must
    // not be turned into a rejection the user cannot act on.
    func GetCallMatchScore(functionType: FunctionTypeInfo, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, receiverType: TypeInfo?): int {
        parameterIndexByArgument: int[] = new int[0]
        if !TryGetScoringPlacement(functionType, call, argTypes, out parameterIndexByArgument) {
            return -1
        }

        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null {
            return -1
        }

        expectedCount := parameterTypes.Count
        parameterStartIndex := AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call)
        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, expectedCount)
        genericBindings := InferGenericBindings(functionType, call, argTypes, receiverType)

        score := 0
        argumentIndex := 0
        while argumentIndex < call.Arguments.Count {
            currentArgument := argumentIndex
            argumentIndex = argumentIndex + 1
            parameterIndex := parameterIndexByArgument[currentArgument]
            if parameterIndex < 0 || parameterIndex >= expectedCount {
                continue
            }

            comparison := binder.GetArgumentComparisonTypes(functionType, call, argTypes, currentArgument, parameterIndex, paramsParameterIndex, parameterStartIndex, genericBindings)
            if !comparison.Matched {
                return -1
            }

            expectedType := comparison.ExpectedType
            argumentType := comparison.ArgumentType
            if expectedType != null && argumentType != null {
                if BuiltInTypes.IsUnknown(expectedType) || BuiltInTypes.IsUnknown(argumentType) {
                    continue
                }

                soaRow := argumentType as SoaRowTypeInfo
                if soaRow != null {
                    continue
                }

                if !assignability.IsAssignable(expectedType, argumentType) {
                    return -1
                }

                score = score + overloadScoring.GetNSharpMatchScore(expectedType, argumentType)
            }
        }

        return score
    }

    // THE ARITY-AND-PLACEMENT GATE, stated once for the scorer and the receiver-type question.
    // A candidate clears it when the argument count is inside the signature's required..expected
    // band (a params tail removes the upper bound), when every written argument reaches a
    // parameter, and when the call did not write MORE type arguments than the signature declares.
    // Placement is asked with `reportErrors: false` — this is a question, not a report.
    func TryGetScoringPlacement(functionType: FunctionTypeInfo, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, out parameterIndexByArgument: int[]): bool {
        parameterIndexByArgument = new int[0]
        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null {
            return false
        }

        expectedCount := parameterTypes.Count
        parameterStartIndex := AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call)
        requiredCount := AnalyzerOverloadFacts.GetSyntheticRequiredArgumentCount(functionType, expectedCount, parameterStartIndex)
        expectedArgumentCount := Math.Max(0, expectedCount - parameterStartIndex)
        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, expectedCount)
        hasParamsParameter := paramsParameterIndex >= 0
        if argTypes.Count < requiredCount {
            return false
        }

        if !hasParamsParameter && argTypes.Count > expectedArgumentCount {
            return false
        }

        functionName := AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call)
        bound: int[] = new int[0]
        if !reporter.TryBindAndReport(functionType, functionName, call, out bound, parameterStartIndex, false) {
            return false
        }

        parameterIndexByArgument = bound
        typeParameters := functionType.TypeParameters
        if typeParameters != null && typeParameters.Count > 0 {
            typeArguments := call.TypeArguments
            if typeArguments != null && typeArguments.Count > typeParameters.Count {
                return false
            }
        }

        return true
    }

    // WHAT EACH TYPE PARAMETER OF AN N#-DECLARED FUNCTION IS BOUND TO FOR THIS CALL, or null when
    // the signature is not generic at all.
    //
    // Explicit type arguments win outright and close the signature when the call wrote all of them.
    // Otherwise every parameter position contributes a BOUND, the receiver position included, and a
    // parameter with several bounds resolves to their least upper bound. A parameter nothing
    // constrained is simply left unbound — an open binding is a better answer than a wrong one,
    // because the positions that DID resolve still check.
    //
    // The params tail infers from its ELEMENT, so `params xs: T[]` called as `f(1, 2)` binds
    // `T = int` rather than `T = int[]`.
    func InferGenericBindings(functionType: FunctionTypeInfo, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, receiverType: TypeInfo?): Dictionary<string, TypeInfo>? {
        typeParameters := functionType.TypeParameters
        if typeParameters == null || typeParameters.Count == 0 {
            return null
        }

        bindings := new Dictionary<string, TypeInfo>()
        allBounds := new Dictionary<string, List<TypeInfo>>()
        boundsIndex := 0
        while boundsIndex < typeParameters.Count {
            allBounds[typeParameters[boundsIndex].Name] = new List<TypeInfo>()
            boundsIndex = boundsIndex + 1
        }

        typeArguments := call.TypeArguments
        if typeArguments != null && typeArguments.Count > 0 {
            if typeArguments.Count > typeParameters.Count {
                return null
            }

            argumentIndex := 0
            while argumentIndex < typeArguments.Count {
                bindings[typeParameters[argumentIndex].Name] = typeResolver.ResolveType(typeArguments[argumentIndex])
                argumentIndex = argumentIndex + 1
            }

            if typeArguments.Count == typeParameters.Count {
                return bindings
            }
        }

        sourceParameterTypes := functionType.SourceParameterTypes
        if sourceParameterTypes == null || sourceParameterTypes.Count == 0 {
            return bindings
        }

        functionName := AnalyzerSyntheticCallFacts.ResolveSyntheticFunctionName(functionType, call)
        parameterStartIndex := AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call)
        if parameterStartIndex > 0 && receiverType != null {
            binder.CollectTypeParameterBounds(sourceParameterTypes[0], receiverType, typeParameters, allBounds)
        }

        parameterIndexByArgument: int[] = new int[0]
        if !reporter.TryBindAndReport(functionType, functionName, call, out parameterIndexByArgument, parameterStartIndex, false) {
            return bindings
        }

        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, sourceParameterTypes.Count)
        walkIndex := 0
        while walkIndex < call.Arguments.Count && walkIndex < argTypes.Count {
            parameterIndex := parameterIndexByArgument[walkIndex]
            if parameterIndex >= 0 && parameterIndex < sourceParameterTypes.Count {
                parameterTypeRef := sourceParameterTypes[parameterIndex]
                argumentType := argTypes[walkIndex]
                if paramsParameterIndex >= 0 && parameterIndex == paramsParameterIndex {
                    parameterTypeRef = AnalyzerOverloadFacts.GetParamsInferenceTypeReference(parameterTypeRef)
                    argumentType = overloadScoring.GetParamsInferenceArgumentType(call.Arguments[walkIndex], argumentType)
                }

                binder.CollectTypeParameterBounds(parameterTypeRef, argumentType, typeParameters, allBounds)
            }

            walkIndex = walkIndex + 1
        }

        resolveIndex := 0
        while resolveIndex < typeParameters.Count {
            name := typeParameters[resolveIndex].Name
            resolveIndex = resolveIndex + 1
            if bindings.ContainsKey(name) {
                continue
            }

            bounds := allBounds[name]
            if bounds.Count == 0 {
                continue
            }

            if bounds.Count == 1 {
                bindings[name] = bounds[0]
            } else {
                bindings[name] = binder.ComputeLeastUpperBound(bounds)
            }
        }

        return bindings
    }

    // WHERE A VIOLATED GENERIC CONSTRAINT POINTS.
    //
    // The best anchor is the ARGUMENT that bound the offending type parameter, because that is the
    // thing the user has to change. It is usable only when exactly ONE written argument fills a
    // parameter declared as that bare type parameter: with none there is nothing to point at, and
    // with two the report would have to pick one arbitrarily. Every other case falls back to the
    // call itself, which is always available and never wrong.
    func GetGenericConstraintDiagnosticSpan(functionType: FunctionTypeInfo, call: CallExpression, typeParameter: string, functionName: string): DiagnosticSpan {
        sourceParameterTypes := functionType.SourceParameterTypes
        if sourceParameterTypes == null || sourceParameterTypes.Count == 0 {
            return spans.GetCallDiagnosticSpan(call, functionName)
        }

        parameterStartIndex := AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call)
        parameterIndexByArgument: int[] = new int[0]
        if !reporter.TryBindAndReport(functionType, functionName, call, out parameterIndexByArgument, parameterStartIndex, false) {
            return spans.GetCallDiagnosticSpan(call, functionName)
        }

        offendingArgument: Expression? = null
        argumentIndex := 0
        while argumentIndex < call.Arguments.Count {
            currentArgument := argumentIndex
            argumentIndex = argumentIndex + 1
            parameterIndex := parameterIndexByArgument[currentArgument]
            if parameterIndex < 0 || parameterIndex >= sourceParameterTypes.Count {
                continue
            }

            simple := sourceParameterTypes[parameterIndex] as SimpleTypeReference
            if simple == null || simple.Name != typeParameter {
                continue
            }

            if offendingArgument != null {
                return spans.GetCallDiagnosticSpan(call, functionName)
            }

            offendingArgument = call.Arguments[currentArgument].Value
        }

        if offendingArgument != null {
            return spans.GetExpressionDiagnosticSpan(offendingArgument)
        }

        return spans.GetCallDiagnosticSpan(call, functionName)
    }
}
