namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// EXTERNAL GENERIC METHODS, CLOSED BY INFERENCE FROM THE ARGUMENTS.
//
// The ordinary runtime call resolver owns fixed-arity, NON-generic declarations; a generic method
// definition is an excluded shape there because its signature still mentions its own type parameters
// and cannot be scored or emitted as written. This owner is the tier that closes them:
// `Vector.Sum(block)` binds `T` to `int` from `Vector<int>`, `Vector.Min(a, b)` and
// `Vector.ConditionalSelect(mask, a, b)` bind it from the same shape, and `HashCode.Combine(state, ok)`
// binds one parameter per argument.
//
// IT ANSWERS THE SAME SELECTION TYPE AS THE ORDINARY RESOLVER ON PURPOSE. A closed generic method is
// an ordinary MethodInfo with an ordinary signature, so the planner's existing append path emits it
// with no new arm: the whole difference between the two tiers is how the handle was obtained.
//
// INFERENCE IS ARGUMENT-DRIVEN UNIFICATION (ECMA-334 §12.6.3's first phase). Each parameter is walked
// against its argument: a method type parameter binds to the argument type it meets, an array or
// by-ref shell recurses into its element, and a constructed generic parameter is matched against the
// same definition found anywhere in the argument's own hierarchy -- so `IEnumerable<T>` against
// `List<int>` binds `T` to `int`. A position that carries no information contributes none, and a type
// parameter that two positions bind DIFFERENTLY is refused rather than guessed.
//
// NOTHING IS ACCEPTED ON THE STRENGTH OF INFERENCE ALONE. `CloseOrNull` checks the declared constraints
// before asking reflection to close the method; Reflection.Emit types do not get constraint validation
// from `MakeGenericMethod`. The resulting CLOSED signature is then scored by the same argument-flow
// scorer every other call selection uses. A candidate whose closed parameters do not accept the
// arguments loses exactly as a non-generic one would.
// A generic method definition closed over inferred or written type arguments: the closed handle and the
// SIGNATURE substituted from the definition (never read back from the handle, which reports the
// definition's own parameters when an argument is a type this compilation is still writing).
class ColumnarClosedGenericMethod {
    Method: MethodInfo
    ParameterTypes: Type[]
    ReturnType: Type

    constructor(method: MethodInfo, parameterTypes: Type[], returnType: Type) {
        Method = method
        ParameterTypes = parameterTypes
        ReturnType = returnType
    }
}

enum ColumnarGenericInferenceBoundKind {
    Exact,
    Lower,
    Upper
}

class ColumnarGenericInferenceBound {
    Type: Type
    Kind: ColumnarGenericInferenceBoundKind

    constructor(type: Type, kind: ColumnarGenericInferenceBoundKind) {
        Type = type
        Kind = kind
    }
}

class ColumnarRuntimeGenericMethodCandidate {
    Definition: MethodInfo
    TypeArguments: Type[]
    ParameterTypes: Type[]
    Score: int
    Rejected: bool

    constructor(definition: MethodInfo, typeArguments: Type[], parameterTypes: Type[], score: int) {
        Definition = definition
        TypeArguments = typeArguments
        ParameterTypes = parameterTypes
        Score = score
        Rejected = false
    }
}

class ColumnarRuntimeGenericMethodResolver {
    private static readonly EmptyGenericMethodDefinitions: MethodInfo[] = new MethodInfo[](0)
    private static readonly EmptyGenericModifierKinds: int[] = new int[](0)

    static func Resolve(lookupType: Type, memberName: string, argumentTypes: Type[], expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveWithFacts(lookupType, memberName, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length), expectedStatic)
    }

    static func ResolveWithFacts(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveWithMethodCandidates(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, GenericMethodDefinitionsNamedOrEmpty(lookupType, memberName))
    }

    static func ResolveWithMethodCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidateMethods: MethodInfo[]): ColumnarOrdinaryRuntimeDirectCallSelection {
        if lookupType == null || memberName == null || argumentTypes == null {
            throw new InvalidOperationException("Runtime generic method resolution inputs cannot be null.")
        }
        if candidateMethods == null {
            throw new InvalidOperationException("Runtime generic method candidates cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        // A builder-bound owner's members are only reachable through its open definition, where a
        // generic method's own parameters and the TYPE's parameters would both need closing at once.
        // That pairing has no call site yet and is left to the tier that grows one.
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(lookupType) || lookupType.IsGenericTypeDefinition || lookupType.IsGenericParameter {
            return Unselected(lookupType, expectedStatic)
        }

        if candidateMethods.Length == 0 {
            return Unselected(lookupType, expectedStatic)
        }

        inferredCandidates := new List<ColumnarRuntimeGenericMethodCandidate>()
        for candidate in candidateMethods {
            parameters := InferableParametersOrNull(candidate, lookupType, memberName, argumentTypes.Length, expectedStatic)
            if parameters != null && CanInferAllMethodParameters(candidate, parameters, argumentFacts, false) {
                inferred := InferTypeArgumentsWithParameters(candidate, parameters, argumentTypes, argumentFacts, false)
                if inferred != null {
                    parameterTypes := ClosedParameterTypesOrNull(candidate, inferred, parameters)
                    if parameterTypes == null {
                        continue
                    }
                    modifiers := CandidateModifierKindsForScoring(parameters)
                    score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(parameterTypes, argumentTypes, argumentFacts, modifiers)
                    if score >= 0 {
                        inferredCandidates.Add(new ColumnarRuntimeGenericMethodCandidate(candidate, inferred, parameterTypes, score))
                    }
                }
            }
        }

        while inferredCandidates.Count > 0 {
            bestScore := -1
            for candidate in inferredCandidates {
                if !candidate.Rejected && candidate.Score > bestScore {
                    bestScore = candidate.Score
                }
            }
            if bestScore < 0 {
                return Unselected(lookupType, expectedStatic)
            }

            tied := new List<ColumnarRuntimeGenericMethodCandidate>()
            tiedParameters := new List<Type[]>()
            for candidate in inferredCandidates {
                if !candidate.Rejected && candidate.Score == bestScore {
                    tied.Add(candidate)
                    tiedParameters.Add(candidate.ParameterTypes)
                }
            }
            winner := 0
            if tied.Count > 1 {
                winner = ColumnarSourceDirectCallResolver.SelectMostSpecificParameters(tiedParameters, argumentTypes, argumentFacts)
                if winner < 0 {
                    return Ambiguous(lookupType, expectedStatic)
                }
            }
            selected := tied[winner]
            closedCandidate := CloseForSelectedCandidateOrNull(selected.Definition, selected.TypeArguments, selected.ParameterTypes, argumentFacts.SourceTypeDefinitions)
            if closedCandidate != null {
                return SelectedClosed(lookupType, closedCandidate.Method, closedCandidate.ParameterTypes, closedCandidate.ReturnType, expectedStatic)
            }
            selected.Rejected = true
        }
        return Unselected(lookupType, expectedStatic)
    }

    // C# removes worse members from the complete applicable set, not once per the generic and
    // non-generic families. Resolve each reflected declaration independently so an ambiguous subset
    // remains available for comparison with a better candidate from the other family.
    static func ResolveCombinedWithMethodCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidateMethods: MethodInfo[]): ColumnarOrdinaryRuntimeDirectCallSelection {
        if lookupType == null || memberName == null || argumentTypes == null || candidateMethods == null {
            throw new InvalidOperationException("Combined runtime generic method resolution inputs cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        applicable := new List<ColumnarOrdinaryRuntimeDirectCallSelection>()
        for candidate in candidateMethods {
            if candidate == null {
                continue
            }
            oneCandidate := OneMethodCandidate(candidate)
            selection := ColumnarOrdinaryRuntimeDirectCallResolver.Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
            if candidate.IsGenericMethodDefinition {
                selection = ResolveWithMethodCandidates(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, oneCandidate)
            } else if !candidate.IsGenericMethod {
                selection = ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidatesWithFacts(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, oneCandidate)
            }
            if selection.IsSelected && !selection.IsExpanded {
                AddCombinedSelectionUnlessHidden(applicable, selection)
            }

            // Optional parameters are still normal-form candidates. Compare them in the same set as
            // exact-arity candidates: a better exact conversion must beat an optional overload, and
            // an optional overload with the better conversion must beat a merely applicable exact
            // overload.
            optional := ColumnarRuntimeOptionalCallSelection.None(lookupType)
            if candidate.IsGenericMethodDefinition {
                optional = ResolveOptionalFillWithMethodCandidates(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, oneCandidate)
            } else if !candidate.IsGenericMethod {
                optional = ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFillWithCandidateMethods(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, oneCandidate)
            }
            if optional.IsSelected && optional.Method != null {
                optionalCandidate := ColumnarOrdinaryRuntimeDirectCallResolver.SelectedOptionalFill(lookupType, optional.Method, optional.ParameterTypes, optional.ReturnType, optional.ExplicitArgumentCount, expectedStatic)
                AddCombinedSelectionUnlessHidden(applicable, optionalCandidate)
            }
        }

        if applicable.Count == 0 {
            return Unselected(lookupType, expectedStatic)
        }

        parameterLists := new List<Type[]>()
        methods := new List<MethodInfo>()
        for selection in applicable {
            parameterLists.Add(selection.ParameterTypes)
            method := selection.Method
            if method == null {
                return Unselected(lookupType, expectedStatic)
            }
            methods.Add(method)
        }
        selectedIndex := SelectCombinedExpandedCandidateIndex(applicable, methods, parameterLists, argumentTypes, argumentFacts)
        if selectedIndex < 0 {
            return Ambiguous(lookupType, expectedStatic)
        }
        return applicable[selectedIndex]
    }

    static func ResolveCombinedOptionalFillWithMethodCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidateMethods: MethodInfo[]): ColumnarRuntimeOptionalCallSelection {
        if lookupType == null || memberName == null || argumentTypes == null || candidateMethods == null {
            throw new InvalidOperationException("Combined optional runtime method resolution inputs cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        applicable := new List<ColumnarRuntimeOptionalCallSelection>()
        for candidate in candidateMethods {
            if candidate == null {
                continue
            }
            oneCandidate := OneMethodCandidate(candidate)
            selection := ColumnarRuntimeOptionalCallSelection.None(lookupType)
            if candidate.IsGenericMethodDefinition {
                selection = ResolveOptionalFillWithMethodCandidates(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, oneCandidate)
            } else if !candidate.IsGenericMethod {
                selection = ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFillWithCandidateMethods(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, oneCandidate)
            }
            if selection.IsSelected {
                applicable.Add(selection)
            }
        }

        if applicable.Count == 0 {
            return ColumnarRuntimeOptionalCallSelection.None(lookupType)
        }

        parameterLists := new List<Type[]>()
        methods := new List<MethodInfo>()
        for selection in applicable {
            parameterLists.Add(selection.ParameterTypes)
            method := selection.Method
            if method == null {
                return ColumnarRuntimeOptionalCallSelection.None(lookupType)
            }
            methods.Add(method)
        }
        selectedIndex := SelectCombinedOptionalCandidateIndex(methods, parameterLists, argumentTypes, argumentFacts)
        if selectedIndex < 0 {
            return ColumnarRuntimeOptionalCallSelection.Ambiguous(lookupType, expectedStatic)
        }
        return applicable[selectedIndex]
    }

    static func ResolveCombinedExpandedWithMethodCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidateMethods: MethodInfo[]): ColumnarOrdinaryRuntimeDirectCallSelection {
        if lookupType == null || memberName == null || argumentTypes == null || candidateMethods == null {
            throw new InvalidOperationException("Combined expanded runtime method resolution inputs cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        applicable := new List<ColumnarOrdinaryRuntimeDirectCallSelection>()
        for candidate in candidateMethods {
            if candidate == null {
                continue
            }
            oneCandidate := OneMethodCandidate(candidate)
            selection := ColumnarOrdinaryRuntimeDirectCallResolver.Empty(ColumnarOrdinaryRuntimeDirectCallStatus.NotFound, lookupType, expectedStatic)
            if candidate.IsGenericMethodDefinition {
                selection = ResolveExpandedWithMethodCandidates(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, oneCandidate)
            } else if !candidate.IsGenericMethod {
                selection = ColumnarOrdinaryRuntimeDirectCallResolver.ResolveExpandedFromCandidates(lookupType, lookupType, new Type[](0), memberName, argumentTypes, argumentFacts, expectedStatic, oneCandidate, false, false)
            }
            if selection.IsSelected {
                AddCombinedSelectionUnlessHidden(applicable, selection)
            }
        }

        if applicable.Count == 0 {
            return Unselected(lookupType, expectedStatic)
        }

        parameterLists := new List<Type[]>()
        methods := new List<MethodInfo>()
        for selection in applicable {
            parameterLists.Add(selection.ParameterTypes)
            method := selection.Method
            if method == null {
                return Unselected(lookupType, expectedStatic)
            }
            methods.Add(method)
        }
        selectedIndex := SelectCombinedExpandedCandidateIndex(applicable, methods, parameterLists, argumentTypes, argumentFacts)
        if selectedIndex < 0 {
            return Ambiguous(lookupType, expectedStatic)
        }
        return applicable[selectedIndex]
    }

    static func OneMethodCandidate(candidate: MethodInfo): MethodInfo[] {
        result := new MethodInfo[](1)
        result[0] = candidate
        return result
    }

    static func AddCombinedSelectionUnlessHidden(selections: List<ColumnarOrdinaryRuntimeDirectCallSelection>, candidate: ColumnarOrdinaryRuntimeDirectCallSelection) {
        candidateMethod := candidate.Method
        if candidateMethod == null {
            return
        }
        candidateParameters := candidateMethod.GetParameters()
        for index := 0; index < selections.Count; index += 1 {
            existing := selections[index]
            existingMethod := existing.Method
            if existingMethod == null {
                continue
            }
            existingParameters := existingMethod.GetParameters()
            if ColumnarOrdinaryRuntimeDirectCallResolver.SameCallSignature(existingMethod, existingParameters, candidateMethod, candidateParameters) {
                if ColumnarOrdinaryRuntimeDirectCallResolver.HidesDeclaration(candidateMethod, existingMethod) {
                    selections[index] = candidate
                }
                if ColumnarOrdinaryRuntimeDirectCallResolver.HidesDeclaration(existingMethod, candidateMethod) {
                    return
                }
            }
        }
        selections.Add(candidate)
    }

    static func MaximalCandidateIndexes(parameterLists: List<Type[]>, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): List<int> {
        result := new List<int>()
        count := parameterLists.Count
        if count == 0 {
            return result
        }
        comparisons := new int[count * count]
        for row := 0; row < count; row += 1 {
            for column := 0; column < count; column += 1 {
                if row != column {
                    comparisons[row * count + column] = ColumnarSourceDirectCallResolver.CompareParameterSpecificity(parameterLists[row], parameterLists[column], argumentTypes, argumentFacts)
                }
            }
        }
        return AnalyzerOverloadSpecificity.FindMaximalIndexes(comparisons, count)
    }

    static func SelectCombinedOptionalCandidateIndex(methods: List<MethodInfo>, parameterLists: List<Type[]>, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): int {
        maximal := MaximalCandidateIndexes(parameterLists, argumentTypes, argumentFacts)
        if maximal.Count == 1 {
            return maximal[0]
        }
        if maximal.Count < 2 {
            return -1
        }

        declaredCount := parameterLists[maximal[0]].Length
        for index in maximal {
            if parameterLists[index].Length != declaredCount {
                return -1
            }
        }
        return NonGenericCandidateTieBreak(methods, parameterLists, maximal, argumentTypes.Length)
    }

    static func SelectCombinedExpandedCandidateIndex(selections: List<ColumnarOrdinaryRuntimeDirectCallSelection>, methods: List<MethodInfo>, parameterLists: List<Type[]>, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): int {
        maximal := MaximalCandidateIndexes(parameterLists, argumentTypes, argumentFacts)
        if maximal.Count == 1 {
            return maximal[0]
        }
        if maximal.Count < 2 {
            return -1
        }

        expansionShape: bool? = null
        sameExpansionShape := true
        for index in maximal {
            if expansionShape == null {
                expansionShape = selections[index].IsExpanded
            } else if expansionShape != selections[index].IsExpanded {
                sameExpansionShape = false
            }
        }
        if !sameExpansionShape {
            normalCandidates := new List<int>()
            for index in maximal {
                if !selections[index].IsExpanded {
                    normalCandidates.Add(index)
                }
            }
            if normalCandidates.Count == 0 {
                return -1
            }
            maximal = normalCandidates
        }

        allEffectiveTypesEqual := true
        first := maximal[0]
        for index in maximal {
            if !EquivalentParameterTypes(parameterLists[first], parameterLists[index], argumentTypes.Length) {
                allEffectiveTypesEqual = false
                break
            }
        }
        if !allEffectiveTypesEqual {
            return -1
        }

        sameUsage := true
        firstUsage := ParametersUsedIncludingExpansion(selections[first], argumentTypes.Length)
        for index in maximal {
            if ParametersUsedIncludingExpansion(selections[index], argumentTypes.Length) != firstUsage {
                sameUsage = false
                break
            }
        }
        if !sameUsage {
            exactUsageIndex := -1
            for index in maximal {
                if ParametersUsedIncludingExpansion(selections[index], argumentTypes.Length) == argumentTypes.Length {
                    if exactUsageIndex >= 0 {
                        return -1
                    }
                    exactUsageIndex = index
                }
            }
            return exactUsageIndex
        }

        return NonGenericCandidateTieBreak(methods, parameterLists, maximal, argumentTypes.Length)
    }

    static func NonGenericCandidateTieBreak(methods: List<MethodInfo>, parameterLists: List<Type[]>, maximal: List<int>, suppliedCount: int): int {
        nonGenericIndex := -1
        first := maximal[0]
        for index in maximal {
            if !EquivalentParameterTypes(parameterLists[first], parameterLists[index], suppliedCount) {
                return -1
            }
            if !methods[index].IsGenericMethod {
                if nonGenericIndex >= 0 {
                    return -1
                }
                nonGenericIndex = index
            }
        }
        return nonGenericIndex
    }

    // Most inferred generic methods have no by-reference parameters. Their overload score needs no
    // modifier column, so avoid allocating a zero-filled array for each candidate; the selected call
    // recomputes the full column when it is appended to the plan.
    static func CandidateModifierKindsForScoring(parameters: ParameterInfo[]): int[] {
        for parameter in parameters {
            if parameter.ParameterType.IsByRef {
                return ColumnarOrdinaryRuntimeDirectCallResolver.ReflectedModifierKinds(parameters)
            }
        }
        return EmptyGenericModifierKinds
    }

    static func EquivalentParameterTypes(left: Type[], right: Type[], suppliedCount: int): bool {
        if left == null || right == null || suppliedCount < 0 || left.Length < suppliedCount || right.Length < suppliedCount {
            return false
        }
        index := 0
        while index < suppliedCount {
            if !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(left[index], right[index]) {
                return false
            }
            index = index + 1
        }
        return true
    }

    static func ParametersUsedIncludingExpansion(selection: ColumnarOrdinaryRuntimeDirectCallSelection, suppliedCount: int): int {
        if selection == null || suppliedCount < 0 {
            return -1
        }
        if !selection.IsExpanded {
            return selection.DeclaredParameterTypes.Length
        }
        if suppliedCount < selection.DeclaredParameterTypes.Length {
            return selection.DeclaredParameterTypes.Length - 1
        }
        return suppliedCount
    }

    // The selection a closed generic handle answers with, for a call written in its normal form.
    static func SelectedClosed(lookupType: Type, selected: MethodInfo, parameterTypes: Type[], returnType: Type, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        declaringType := selected.DeclaringType
        if declaringType == null {
            return Unselected(lookupType, expectedStatic)
        }

        receiverIsReference := !expectedStatic && !lookupType.IsValueType
        kind := expectedStatic ? ColumnarExternalCallKind.Call : (receiverIsReference ? ColumnarExternalCallKind.CallVirtual : ColumnarExternalCallKind.Call)
        return new ColumnarOrdinaryRuntimeDirectCallSelection(
            ColumnarOrdinaryRuntimeDirectCallStatus.Selected,
            selected,
            lookupType,
            declaringType,
            parameterTypes,
            returnType,
            kind,
            expectedStatic,
            receiverIsReference,
            selected.IsAbstract,
            null,
            parameterTypes,
            -1
        )
    }

    // INFERRED GENERIC CALLS THAT FILL AN OMITTED OPTIONAL TAIL.
    //
    // `JsonSerializer.Serialize(value)` against `Serialize<TValue>(TValue value, JsonSerializerOptions?
    // options = null)`: the type argument comes from the arguments the site WROTE (ECMA-334 §12.6.3
    // reads only the supplied arguments; an omitted optional parameter is not an argument and cannot
    // bind a type parameter), the omitted tail fills from its metadata default afterwards, and a type
    // parameter that only the omitted tail mentions stays unbound and loses the candidate. It is the
    // optional-fill tier of the ordinary resolver, asked for the generic definitions that tier's
    // excluded-shape rule leaves out, and it answers the same selection type, so the planner's
    // existing optional-fill path emits it.
    static func ResolveOptionalFill(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarRuntimeOptionalCallSelection {
        return ResolveOptionalFillWithMethodCandidates(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, GenericMethodDefinitionsNamedOrEmpty(lookupType, memberName))
    }

    static func ResolveOptionalFillWithMethodCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidateMethods: MethodInfo[]): ColumnarRuntimeOptionalCallSelection {
        if lookupType == null || memberName == null || argumentTypes == null {
            throw new InvalidOperationException("Runtime generic method resolution inputs cannot be null.")
        }
        if candidateMethods == null {
            throw new InvalidOperationException("Runtime generic method candidates cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(lookupType) || lookupType.IsGenericTypeDefinition || lookupType.IsGenericParameter {
            return ColumnarRuntimeOptionalCallSelection.None(lookupType)
        }

        if candidateMethods.Length == 0 {
            return ColumnarRuntimeOptionalCallSelection.None(lookupType)
        }

        argumentCount := argumentTypes.Length
        bestScore := -1
        bestParameterCount := 0
        bestCount := 0
        selected: MethodInfo? = null
        selectedParameters := new Type[](0)
        selectedReturn := typeof(object)
        for candidate in candidateMethods {
            if IsInferableCandidateShape(candidate, lookupType, memberName, expectedStatic) {
                parameters := candidate.GetParameters()
                if parameters != null && parameters.Length > argumentCount && !ColumnarOrdinaryRuntimeDirectCallResolver.HasParamsParameter(parameters) {
                    closed := InferAndClose(candidate, argumentTypes, argumentFacts, false)
                    if closed != null && ColumnarOrdinaryRuntimeDirectCallResolver.OptionalTailFillable(parameters, closed.ParameterTypes, argumentCount) {
                        leadingKinds := ColumnarDirectCallPlanner.ParameterModifierKindSlice(ColumnarOrdinaryRuntimeDirectCallResolver.ReflectedModifierKinds(parameters), 0, argumentCount)
                        score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(ColumnarOrdinaryRuntimeDirectCallResolver.LeadingParameterTypes(closed.ParameterTypes, argumentCount), argumentTypes, argumentFacts, leadingKinds)
                        if score >= 0 {
                            if score > bestScore || (score == bestScore && parameters.Length < bestParameterCount) {
                                bestScore = score
                                bestParameterCount = parameters.Length
                                bestCount = 1
                                selected = closed.Method
                                selectedParameters = closed.ParameterTypes
                                selectedReturn = closed.ReturnType
                            } else if score == bestScore && parameters.Length == bestParameterCount {
                                bestCount = bestCount + 1
                            }
                        }
                    }
                }
            }
        }

        if bestCount == 1 && selected != null {
            return ColumnarRuntimeOptionalCallSelection.Selected(lookupType, selected, selectedParameters, selectedReturn, argumentCount, expectedStatic)
        }
        if bestCount > 1 {
            return ColumnarRuntimeOptionalCallSelection.Ambiguous(lookupType, expectedStatic)
        }
        return ColumnarRuntimeOptionalCallSelection.None(lookupType)
    }

    // INFERRED GENERIC CALLS WHOSE `params` TAIL THE SITE PACKS.
    //
    // `set.FromSqlRaw(sql, n)` against `FromSqlRaw<TEntity>(DbSet<TEntity> source, string sql, params
    // object[] parameters)`. ECMA-334 §12.6.4.2 prefers the NORMAL form (the caller already holds the
    // array) over the expanded one, so each candidate is inferred and scored in its declared shape
    // first, and the expanded form is only asked when no candidate binds that way. In the expanded
    // form every packed argument is unified against the tail's ELEMENT type, which is how `Create(1, 2,
    // 3, 4, 5)` binds `T` from five arguments against one `params T[]`.
    static func ResolveExpanded(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveExpandedWithMethodCandidates(lookupType, memberName, argumentTypes, argumentFacts, expectedStatic, GenericMethodDefinitionsNamedOrEmpty(lookupType, memberName))
    }

    static func ResolveExpandedWithMethodCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, candidateMethods: MethodInfo[]): ColumnarOrdinaryRuntimeDirectCallSelection {
        if lookupType == null || memberName == null || argumentTypes == null {
            throw new InvalidOperationException("Runtime generic method resolution inputs cannot be null.")
        }
        if candidateMethods == null {
            throw new InvalidOperationException("Runtime generic method candidates cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(lookupType) || lookupType.IsGenericTypeDefinition || lookupType.IsGenericParameter {
            return Unselected(lookupType, expectedStatic)
        }

        if candidateMethods.Length == 0 {
            return Unselected(lookupType, expectedStatic)
        }

        argumentCount := argumentTypes.Length
        normalScore := -1
        normalCount := 0
        normalSelected: MethodInfo? = null
        normalParameters := new Type[](0)
        normalReturn := typeof(object)
        expandedScore := -1
        expandedCount := 0
        expandedSelected: MethodInfo? = null
        expandedTypes := new Type[](0)
        expandedDeclared := new Type[](0)
        expandedReturn := typeof(object)
        expandedElement: Type? = null
        expandedFixed := -1
        for candidate in candidateMethods {
            if IsInferableCandidateShape(candidate, lookupType, memberName, expectedStatic) {
                parameters := candidate.GetParameters()
                if parameters != null && parameters.Length > 0 && ColumnarExtensionMethodResolver.IsParamsParameter(parameters[parameters.Length - 1]) {
                    fixedCount := parameters.Length - 1
                    modifierKinds := ColumnarOrdinaryRuntimeDirectCallResolver.ReflectedModifierKinds(parameters)

                    if argumentCount == parameters.Length {
                        normalClosed := InferAndClose(candidate, argumentTypes, argumentFacts, false)
                        if normalClosed != null {
                            score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(normalClosed.ParameterTypes, argumentTypes, argumentFacts, modifierKinds)
                            if score > normalScore {
                                normalScore = score
                                normalCount = 1
                                normalSelected = normalClosed.Method
                                normalParameters = normalClosed.ParameterTypes
                                normalReturn = normalClosed.ReturnType
                            } else if score >= 0 && score == normalScore {
                                normalCount = normalCount + 1
                            }
                        }
                    }

                    if argumentCount >= fixedCount {
                        expandedClosed := InferAndClose(candidate, argumentTypes, argumentFacts, true)
                        if expandedClosed != null {
                            element := ColumnarParamsExpansion.ElementTypeOrNull(parameters, expandedClosed.ParameterTypes)
                            perArgument := ColumnarParamsExpansion.ExpandedParameterTypesOrNull(parameters, expandedClosed.ParameterTypes, 0, argumentCount)
                            if element != null && perArgument != null {
                                score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(perArgument, argumentTypes, argumentFacts)
                                if score > expandedScore {
                                    expandedScore = score
                                    expandedCount = 1
                                    expandedSelected = expandedClosed.Method
                                    expandedTypes = perArgument
                                    expandedDeclared = expandedClosed.ParameterTypes
                                    expandedReturn = expandedClosed.ReturnType
                                    expandedElement = element
                                    expandedFixed = fixedCount
                                } else if score >= 0 && score == expandedScore {
                                    expandedCount = expandedCount + 1
                                }
                            }
                        }
                    }
                }
            }
        }

        if normalCount > 1 {
            return Ambiguous(lookupType, expectedStatic)
        }
        if normalCount == 1 && normalSelected != null && normalScore >= 0 {
            return SelectedClosed(lookupType, normalSelected, normalParameters, normalReturn, expectedStatic)
        }
        if normalCount == 0 && expandedCount == 1 && expandedSelected != null && expandedElement != null && expandedScore >= 0 {
            return ColumnarOrdinaryRuntimeDirectCallResolver.SelectedExpanded(lookupType, expandedSelected, expandedTypes, expandedDeclared, expandedReturn, expandedElement, expandedFixed, expectedStatic)
        }
        if normalCount == 0 && expandedCount > 1 {
            return Ambiguous(lookupType, expectedStatic)
        }
        return Unselected(lookupType, expectedStatic)
    }

    // INFER, CLOSE, SUBSTITUTE: the one sequence every inferred generic call goes through. The return
    // comes from the same substitution the parameters do, not from the closed wrapper's own
    // `ReturnType`, so the plan's declared signature is the shape the CALL SITE sees.
    static func InferAndClose(candidate: MethodInfo, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expanded: bool): ColumnarClosedGenericMethod? {
        return InferAndClose(candidate, argumentTypes, argumentFacts, expanded, true)
    }

    // Extension inference shares the same loop after prepending its receiver, but keeps the
    // extension resolver's exact structural matching policy instead of runtime base/interface
    // widening.
    static func InferAndClose(candidate: MethodInfo, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expanded: bool, allowInferenceWidening: bool): ColumnarClosedGenericMethod? {
        inferred := InferTypeArguments(candidate, argumentTypes, argumentFacts, expanded, allowInferenceWidening)
        if inferred == null {
            return null
        }
        return CloseInferredSubstitutedOrNull(candidate, inferred, argumentFacts.SourceTypeDefinitions)
    }

    // Extension inference supplies its receiver as the first declared slot. Consume that leading
    // type directly instead of manufacturing callTypes and a second argument-facts object for every
    // indexed extension candidate. Most same-named candidates fail on the receiver or a null literal,
    // so avoiding those per-candidate arrays keeps workspace scans bounded.
    static func InferAndCloseWithLeadingArgument(candidate: MethodInfo, declaredParameterTypes: Type[], leadingArgumentType: Type, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, explicitCount: int, expanded: bool, allowInferenceWidening: bool): ColumnarClosedGenericMethod? {
        if candidate == null || declaredParameterTypes == null || leadingArgumentType == null || argumentTypes == null || argumentFacts == null || explicitCount < 0 || explicitCount > argumentTypes.Length {
            return null
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        bindings := new Dictionary<int, List<ColumnarGenericInferenceBound>>()
        if !expanded {
            if explicitCount + 1 > declaredParameterTypes.Length {
                return null
            }
            if !Unify(declaredParameterTypes[0], leadingArgumentType, bindings, allowInferenceWidening) {
                return null
            }
            index := 0
            while index < explicitCount {
                if !argumentFacts.IsNullLiteral[index] && !Unify(declaredParameterTypes[index + 1], argumentTypes[index], bindings, allowInferenceWidening) {
                    return null
                }
                index = index + 1
            }
            inferred := BoundTypeArgumentsOrNull(candidate, bindings, argumentFacts.SourceTypeDefinitions)
            if inferred == null {
                return null
            }
            return CloseInferredSubstitutedOrNull(candidate, inferred, argumentFacts.SourceTypeDefinitions)
        }

        slots := ArgumentSlotTypesOrNull(declaredParameterTypes, 0, explicitCount + 1, expanded)
        if slots == null {
            return null
        }

        if !Unify(slots[0], leadingArgumentType, bindings, allowInferenceWidening) {
            return null
        }
        index := 0
        while index < explicitCount {
            // A null literal contributes no bound; the remaining supplied arguments may still infer
            // the method type parameter, as in `FromSqlRaw(sql, null)`.
            if !argumentFacts.IsNullLiteral[index] && !Unify(slots[index + 1], argumentTypes[index], bindings, allowInferenceWidening) {
                return null
            }
            index = index + 1
        }

        inferred := BoundTypeArgumentsOrNull(candidate, bindings, argumentFacts.SourceTypeDefinitions)
        if inferred == null {
            return null
        }
        return CloseInferredSubstitutedOrNull(candidate, inferred, argumentFacts.SourceTypeDefinitions)
    }

    // Every inferred candidate goes through the same final admission: all method parameters must be
    // bound to usable types, the declaration's constraints must hold, and its closed signature must be
    // substituted from the definition. Extension inference supplies its receiver-aware bindings to
    // this helper too.
    static func CloseInferredSubstitutedOrNull(definition: MethodInfo, inferred: Type[], sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): ColumnarClosedGenericMethod? {
        if definition == null || inferred == null {
            return null
        }

        for inferredArgument in inferred {
            if inferredArgument == null || IsUnbindableInferredType(inferredArgument) {
                return null
            }
        }

        return CloseSubstituted(definition, inferred, sourceTypeDefinitions)
    }

    // The definition closed over `typeArguments`, or null when a declared constraint refuses them or a
    // closed signature type has no call shape. `CloseOrNull` is the constraint arbiter.
    static func CloseSubstituted(definition: MethodInfo, typeArguments: Type[], sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): ColumnarClosedGenericMethod? {
        closedParameters := ClosedParameterTypesOrNull(definition, typeArguments)
        if closedParameters == null {
            return null
        }
        return CloseForSelectedCandidateOrNull(definition, typeArguments, closedParameters, sourceTypeDefinitions)
    }

    // Candidate scoring needs only substituted parameter types. Delay MakeGenericMethod and return
    // substitution until a candidate can beat the best score, because those operations allocate
    // Reflection.Emit wrappers for every applicable overload during whole-workspace scans.
    static func CloseForSelectedCandidateOrNull(definition: MethodInfo, typeArguments: Type[], parameterTypes: Type[], sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): ColumnarClosedGenericMethod? {
        if definition == null || typeArguments == null || parameterTypes == null {
            return null
        }
        closed := CloseOrNull(definition, typeArguments, sourceTypeDefinitions)
        if closed == null {
            return null
        }
        closedReturn := ClosedReturnTypeOrNull(definition, typeArguments)
        if closedReturn == null {
            return null
        }
        return new ColumnarClosedGenericMethod(closed, parameterTypes, closedReturn)
    }

    // Ask Reflection for only the one name group, then retain only generic method definitions. If the
    // name has no generic candidates, return the shared empty array before the resolver allocates its
    // candidate lists or asks inference to inspect any signatures.
    static func GenericMethodDefinitionsNamedOrEmpty(lookupType: Type, memberName: string): MethodInfo[] {
        if lookupType == null || memberName == null {
            return EmptyGenericMethodDefinitions
        }

        try {
            members := lookupType.GetMember(
                memberName,
                MemberTypes.Method,
                BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.FlattenHierarchy
            )
            if members == null {
                return EmptyGenericMethodDefinitions
            }

            genericMethods: List<MethodInfo>? = null
            for member in members {
                method := member as MethodInfo
                if method != null && method.IsGenericMethodDefinition {
                    if genericMethods == null {
                        genericMethods = new List<MethodInfo>()
                    }
                    if genericMethods != null {
                        genericMethods.Add(method)
                    }
                }
            }
            if genericMethods == null {
                return EmptyGenericMethodDefinitions
            }
            return genericMethods.ToArray()
        } catch ex: NotSupportedException {
            return EmptyGenericMethodDefinitions
        } catch ex: NotImplementedException {
            return EmptyGenericMethodDefinitions
        }
    }

    static func IsInferableCandidate(candidate: MethodInfo, lookupType: Type, memberName: string, argumentCount: int, expectedStatic: bool): bool {
        return InferableParametersOrNull(candidate, lookupType, memberName, argumentCount, expectedStatic) != null
    }

    static func InferableParametersOrNull(candidate: MethodInfo, lookupType: Type, memberName: string, argumentCount: int, expectedStatic: bool): ParameterInfo[]? {
        if !IsInferableCandidateShape(candidate, lookupType, memberName, expectedStatic) {
            return null
        }

        parameters := candidate.GetParameters()
        if parameters == null || parameters.Length != argumentCount {
            return null
        }
        for parameter in parameters {
            if parameter == null || parameter.ParameterType == null || ColumnarExtensionMethodResolver.IsParamsParameter(parameter) {
                return null
            }
        }
        return parameters
    }

    // C# inference has no source for a method type parameter that appears only in the return type,
    // an omitted optional parameter, or a position whose expression is a null literal. Reject those
    // candidates before allocating the per-candidate binding dictionary. This is a necessary check:
    // every parameter the full unifier accepts must have at least one supplied, non-null occurrence.
    static func CanInferAllMethodParameters(candidate: MethodInfo, parameters: ParameterInfo[], argumentFacts: ColumnarDirectCallArgumentFacts, expanded: bool): bool {
        genericParameters := candidate.GetGenericArguments()
        argumentCount := argumentFacts.IsNullLiteral.Length
        fixedCount := parameters.Length
        tailElement: Type? = null
        if expanded {
            if parameters.Length == 0 || !ColumnarExtensionMethodResolver.IsParamsParameter(parameters[parameters.Length - 1]) {
                return false
            }
            fixedCount = parameters.Length - 1
            tail := parameters[parameters.Length - 1].ParameterType
            if !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(tail) {
                return false
            }
            tailElement = tail.GetElementType()
            if tailElement == null || argumentCount < fixedCount {
                return false
            }
        }

        genericIndex := 0
        while genericIndex < genericParameters.Length {
            found := false
            argumentIndex := 0
            while argumentIndex < argumentCount {
                if argumentFacts.IsNullLiteral[argumentIndex] {
                    argumentIndex = argumentIndex + 1
                    continue
                }
                parameterType: Type? = null
                if expanded && argumentIndex >= fixedCount {
                    parameterType = tailElement
                } else if argumentIndex < parameters.Length {
                    parameterType = parameters[argumentIndex].ParameterType
                }
                if parameterType != null && ContainsMethodTypeParameter(parameterType, genericIndex) {
                    found = true
                    break
                }
                argumentIndex = argumentIndex + 1
            }
            if !found {
                return false
            }
            genericIndex = genericIndex + 1
        }
        return true
    }

    static func ContainsMethodTypeParameter(signatureType: Type, genericIndex: int): bool {
        if signatureType == null {
            return false
        }
        if signatureType.IsGenericParameter {
            return signatureType.DeclaringMethod != null && signatureType.GenericParameterPosition == genericIndex
        }
        if signatureType.HasElementType {
            element := signatureType.GetElementType()
            if element != null && ContainsMethodTypeParameter(element, genericIndex) {
                return true
            }
        }
        if signatureType.IsGenericType {
            for argument in signatureType.GetGenericArguments() {
                if ContainsMethodTypeParameter(argument, genericIndex) {
                    return true
                }
            }
        }
        return false
    }

    // The half of candidate admission that does not depend on the call site's ARGUMENTS: a public,
    // non-varargs generic method definition of this name and staticness, declared by the lookup type
    // or by something the lookup type derives from. The explicit-type-argument tier asks the same
    // question, so the two tiers cannot disagree about which declarations are reachable.
    static func IsInferableCandidateShape(candidate: MethodInfo?, lookupType: Type, memberName: string, expectedStatic: bool): bool {
        if candidate == null || !candidate.IsPublic || candidate.Name != memberName || candidate.IsStatic != expectedStatic {
            return false
        }
        if !candidate.IsGenericMethodDefinition {
            return false
        }
        if ColumnarSourceOperatorResolver.IsVarArgs(candidate) {
            return false
        }
        declaringType := candidate.DeclaringType
        if declaringType == null {
            return false
        }
        if !ColumnarConstructionPlanner.SameObject(declaringType, lookupType) {
            if declaringType.IsValueType || lookupType.IsValueType || !RuntimeAssignableFrom(declaringType, lookupType) {
                return false
            }
        }
        return true
    }

    static func RuntimeAssignableFrom(declaringType: Type, lookupType: Type): bool {
        try {
            return declaringType.IsAssignableFrom(lookupType)
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    // `expanded` asks the `params` question instead: each fixed argument unifies with its own
    // parameter and every PACKED argument with the tail's element type.
    static func InferTypeArguments(candidate: MethodInfo, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expanded: bool): Type[]? {
        return InferTypeArguments(candidate, argumentTypes, argumentFacts, expanded, true)
    }

    // Extension methods use this same slot loop after their receiver is prepended to the argument
    // list. Their historical rule binds only exact constructed shapes; runtime calls also search
    // base and interface instantiations such as `IEnumerable<T>` on `List<T>`.
    static func InferTypeArguments(candidate: MethodInfo, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expanded: bool, allowInferenceWidening: bool): Type[]? {
        return InferTypeArgumentsWithParameters(candidate, candidate.GetParameters(), argumentTypes, argumentFacts, expanded, allowInferenceWidening)
    }

    static func InferTypeArgumentsWithParameters(candidate: MethodInfo, parameters: ParameterInfo[], argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expanded: bool): Type[]? {
        return InferTypeArgumentsWithParameters(candidate, parameters, argumentTypes, argumentFacts, expanded, true)
    }

    static func InferTypeArgumentsWithParameters(candidate: MethodInfo, parameters: ParameterInfo[], argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expanded: bool, allowInferenceWidening: bool): Type[]? {
        bindings := new Dictionary<int, List<ColumnarGenericInferenceBound>>()
        if !expanded {
            if argumentTypes.Length > parameters.Length {
                return null
            }
            index := 0
            while index < argumentTypes.Length {
                // A `null` literal contributes no bound; another supplied position may still infer the
                // same type parameter.
                if !argumentFacts.IsNullLiteral[index] && !Unify(parameters[index].ParameterType, argumentTypes[index], bindings, allowInferenceWidening) {
                    return null
                }
                index = index + 1
            }
            return BoundTypeArgumentsOrNull(candidate, bindings, argumentFacts.SourceTypeDefinitions)
        }

        declared := new Type[](parameters.Length)
        position := 0
        while position < parameters.Length {
            declared[position] = parameters[position].ParameterType
            position = position + 1
        }

        slots := ArgumentSlotTypesOrNull(declared, 0, argumentTypes.Length, expanded)
        if slots == null {
            return null
        }

        index := 0
        while index < slots.Length {

            // A `null` LITERAL CARRIES NO TYPE, so it contributes nothing to inference — ECMA-334
            // §12.6.3 says the same, and the recorded `object` placeholder is a stand-in for "unknown"
            // rather than an argument type. Unifying it would bind a parameter to `object` and then
            // refuse the position that knows the real answer, which is exactly what
            // `Interlocked.Exchange(ref remove, null)` did: `T` bound to the field's type from the
            // by-ref position and was then contradicted by the null.
            if argumentFacts.IsNullLiteral[index] {
                index = index + 1
                continue
            }

            if !Unify(slots[index], argumentTypes[index], bindings, allowInferenceWidening) {
                return null
            }
            index = index + 1
        }

        return BoundTypeArgumentsOrNull(candidate, bindings, argumentFacts.SourceTypeDefinitions)
    }

    // THE DECLARED PARAMETER TYPE EACH SUPPLIED ARGUMENT LANDS IN, for every inference owner to unify
    // against. `firstArgumentSlot` is the first declared slot represented in `argumentCount`; the
    // extension resolver prepends its receiver and therefore starts at slot 0 too. In the expanded
    // form the arguments past the fixed slots land in the `params` tail's ELEMENT type; null answers a
    // shape that cannot be called that way (too few arguments for fixed slots, or a non-SZ-array tail).
    static func ArgumentSlotTypesOrNull(declaredTypes: Type[], firstArgumentSlot: int, argumentCount: int, expanded: bool): Type[]? {
        available := declaredTypes.Length - firstArgumentSlot
        if firstArgumentSlot < 0 || argumentCount < 0 || available < 0 {
            return null
        }

        slots := new Type[](argumentCount)
        if !expanded {
            if argumentCount > available {
                return null
            }
            index := 0
            while index < argumentCount {
                slots[index] = declaredTypes[firstArgumentSlot + index]
                index = index + 1
            }
            return slots
        }

        fixedCount := available - 1
        if fixedCount < 0 || argumentCount < fixedCount {
            return null
        }
        tail := declaredTypes[declaredTypes.Length - 1]
        if !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(tail) {
            return null
        }
        element := tail.GetElementType()
        if element == null {
            return null
        }
        index := 0
        while index < argumentCount {
            slots[index] = index < fixedCount ? declaredTypes[firstArgumentSlot + index] : element
            index = index + 1
        }
        return slots
    }

    static func BoundTypeArgumentsOrNull(candidate: MethodInfo, bindings: Dictionary<int, List<ColumnarGenericInferenceBound>>, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>): Type[]? {
        genericParameters := candidate.GetGenericArguments()
        typeArguments := new Type[](genericParameters.Length)
        position := 0
        while position < genericParameters.Length {
            bounds := new List<ColumnarGenericInferenceBound>()
            if !bindings.TryGetValue(position, out bounds) || bounds == null || bounds.Count == 0 {
                return null
            }
            fixedType := FixInferenceBoundsOrNull(bounds, sourceTypeDefinitions)
            if fixedType == null {
                return null
            }
            typeArguments[position] = fixedType
            position = position + 1
        }

        return typeArguments
    }

    static func FixInferenceBoundsOrNull(bounds: List<ColumnarGenericInferenceBound>, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>): Type? {
        if bounds == null || bounds.Count == 0 || sourceTypeDefinitions == null {
            return null
        }

        candidates := new List<Type>()
        for bound in bounds {
            if bound == null || bound.Type == null {
                return null
            }
            AddInferenceCandidateClosure(candidates, bound.Type)
        }
        AddNumericInferenceCandidates(candidates)

        viable := new List<Type>()
        for candidate in candidates {
            if SatisfiesInferenceBounds(candidate, bounds, sourceTypeDefinitions) {
                viable.Add(candidate)
            }
        }
        if viable.Count == 0 {
            return null
        }

        best: Type? = null
        for candidate in viable {
            isUniqueBest := true
            for other in viable {
                if RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(candidate, other) {
                    continue
                }
                candidateToOther := InferenceBoundConversionExists(other, candidate, sourceTypeDefinitions)
                otherToCandidate := InferenceBoundConversionExists(candidate, other, sourceTypeDefinitions)
                if !candidateToOther || otherToCandidate {
                    isUniqueBest = false
                    break
                }
            }
            if isUniqueBest {
                if best != null && !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(best, candidate) {
                    return null
                }
                best = candidate
            }
        }
        return best
    }

    static func SatisfiesInferenceBounds(candidate: Type, bounds: List<ColumnarGenericInferenceBound>, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>): bool {
        for bound in bounds {
            if bound.Kind == ColumnarGenericInferenceBoundKind.Exact {
                if !RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(candidate, bound.Type) {
                    return false
                }
            } else if bound.Kind == ColumnarGenericInferenceBoundKind.Lower {
                if !InferenceBoundConversionExists(candidate, bound.Type, sourceTypeDefinitions) {
                    return false
                }
            } else if !InferenceBoundConversionExists(bound.Type, candidate, sourceTypeDefinitions) {
                return false
            }
        }
        return true
    }

    static func InferenceBoundConversionExists(targetType: Type, sourceType: Type, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>): bool {
        if RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(targetType, sourceType) {
            return true
        }
        if ColumnarTypeEquivalenceFacts.IsNullableLiftOf(targetType, sourceType) {
            return true
        }
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(targetType) || RuntimeTypeShapeFacts.ContainsBuilderBoundType(sourceType) {
            return ConstraintAccepts(targetType, sourceType)
        }
        return ColumnarSourceDirectCallResolver.ArgumentFlowScore(targetType, sourceType, sourceTypeDefinitions) >= 0
    }

    static func AddInferenceCandidateClosure(candidates: List<Type>, source: Type) {
        current: Type? = source
        while current != null {
            AddDistinctInferenceCandidate(candidates, current)
            current = BaseTypeOrNull(current)
        }
        for interfaceType in InterfaceListOrEmpty(source) {
            AddDistinctInferenceCandidate(candidates, interfaceType)
        }
    }

    static func AddDistinctInferenceCandidate(candidates: List<Type>, candidate: Type) {
        for existing in candidates {
            if RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(existing, candidate) {
                return
            }
        }
        candidates.Add(candidate)
    }

    static func AddNumericInferenceCandidates(candidates: List<Type>) {
        AddDistinctInferenceCandidate(candidates, typeof(byte))
        AddDistinctInferenceCandidate(candidates, typeof(sbyte))
        AddDistinctInferenceCandidate(candidates, typeof(short))
        AddDistinctInferenceCandidate(candidates, typeof(ushort))
        AddDistinctInferenceCandidate(candidates, typeof(int))
        AddDistinctInferenceCandidate(candidates, typeof(uint))
        AddDistinctInferenceCandidate(candidates, typeof(long))
        AddDistinctInferenceCandidate(candidates, typeof(ulong))
        AddDistinctInferenceCandidate(candidates, typeof(char))
        AddDistinctInferenceCandidate(candidates, typeof(float))
        AddDistinctInferenceCandidate(candidates, typeof(double))
        AddDistinctInferenceCandidate(candidates, typeof(decimal))
    }

    // The candidate closed over those arguments, or null when the declared constraints refuse the
    // instantiation. Closing over a SOURCE TYPE PARAMETER is a supported Reflection.Emit shape: the
    // answer is a `MethodBuilderInstantiation`, which `call` encodes as a MethodSpec over that
    // parameter and the CLR resolves once per constructed type.
    //
    // `MakeGenericMethod` validates constraints for runtime type arguments. It does not validate a
    // TypeBuilder-bound argument while this compilation is still writing that type, so a source
    // `struct` could otherwise close `where T : class` and emit unverifiable IL. Check the declared
    // constraints structurally for every closure before asking Reflection to construct the handle.
    static func CloseOrNull(candidate: MethodInfo, typeArguments: Type[], sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): MethodInfo? {
        try {
            if !SatisfiesConstraints(candidate, typeArguments, sourceTypeDefinitions) {
                return null
            }
            return candidate.MakeGenericMethod(typeArguments)
        } catch ex: ArgumentException {
            return null
        } catch ex: NotSupportedException {
            return null
        } catch ex: InvalidOperationException {
            return null
        } catch ex: NotImplementedException {
            return null
        } catch ex: TypeLoadException {
            return null
        }
    }

    // THE DECLARED CONSTRAINTS OF EVERY TYPE PARAMETER AGAINST ITS ARGUMENT: `class`, `struct` (a
    // non-nullable value type) and `new()` from the parameter's attributes, then each constraint type
    // (substituted, since one may name another type parameter) by assignability.
    static func SatisfiesConstraints(definition: MethodInfo, typeArguments: Type[], sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): bool {
        parameters := definition.GetGenericArguments()
        if parameters.Length != typeArguments.Length {
            return false
        }

        index := 0
        while index < parameters.Length {
            argument := typeArguments[index]
            if argument == null {
                return false
            }
            attributes := parameters[index].GenericParameterAttributes
            if (attributes & GenericParameterAttributes.ReferenceTypeConstraint) != GenericParameterAttributes.None && !HasReferenceTypeGuarantee(argument) {
                return false
            }
            if (attributes & GenericParameterAttributes.NotNullableValueTypeConstraint) != GenericParameterAttributes.None && !HasNonNullableValueTypeGuarantee(argument) {
                return false
            }
            if (attributes & GenericParameterAttributes.DefaultConstructorConstraint) != GenericParameterAttributes.None && !HasPublicParameterlessConstructorGuarantee(argument, sourceTypeDefinitions) {
                return false
            }
            for constraint in parameters[index].GetGenericParameterConstraints() {
                substituted := SubstituteMethodTypeArguments(constraint, typeArguments)
                if substituted == null || !ConstraintAccepts(substituted, argument) {
                    return false
                }
            }
            index = index + 1
        }
        return true
    }

    // A generic argument that is itself a type parameter is admissible only when its declared
    // constraints prove the required promise. `Type.IsValueType` is false for a generic parameter,
    // so treating it as an ordinary reference type would accept `M<T>() where T : class` for an
    // unconstrained `T` and emit an invalid MethodSpec.
    static func HasReferenceTypeGuarantee(argument: Type): bool {
        if argument.IsGenericParameter {
            attributes := argument.GenericParameterAttributes
            if (attributes & GenericParameterAttributes.ReferenceTypeConstraint) != GenericParameterAttributes.None {
                return true
            }
            for constraint in argument.GetGenericParameterConstraints() {
                if constraint.IsGenericParameter && HasReferenceTypeGuarantee(constraint) {
                    return true
                }
                if !constraint.IsInterface && constraint != typeof(object) && constraint != typeof(ValueType) && constraint != typeof(Enum) {
                    return true
                }
            }
            return false
        }

        // An interface type is itself a valid reference-type argument for `where T : class`.
        return !argument.IsValueType
    }

    static func HasNonNullableValueTypeGuarantee(argument: Type): bool {
        if argument.IsGenericParameter {
            return (argument.GenericParameterAttributes & GenericParameterAttributes.NotNullableValueTypeConstraint) != GenericParameterAttributes.None
        }
        return argument.IsValueType && !IsNullableValueType(argument)
    }

    static func HasPublicParameterlessConstructorGuarantee(argument: Type, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): bool {
        if argument.IsGenericParameter {
            attributes := argument.GenericParameterAttributes
            return (attributes & GenericParameterAttributes.NotNullableValueTypeConstraint) != GenericParameterAttributes.None || (attributes & GenericParameterAttributes.DefaultConstructorConstraint) != GenericParameterAttributes.None
        }
        if argument.IsValueType {
            return !IsNullableValueType(argument)
        }
        if argument.IsAbstract || argument.IsInterface {
            return false
        }
        if HasSourcePublicParameterlessConstructor(argument, sourceTypeDefinitions) {
            return true
        }
        if argument is TypeBuilder {
            // An unregistered TypeBuilder has no constructor fact that can prove the promise.
            return false
        }
        try {
            constructors := argument.GetConstructors(BindingFlags.Public | BindingFlags.Instance)
            if constructors == null {
                return false
            }
            for constructor in constructors {
                parameters := constructor.GetParameters()
                if parameters != null && parameters.Length == 0 {
                    return true
                }
            }
            return false
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    static func HasSourcePublicParameterlessConstructor(argument: Type, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>?): bool {
        if argument == null || sourceTypeDefinitions == null {
            return false
        }

        sourceBuilder := argument as TypeBuilder
        if sourceBuilder == null {
            try {
                if argument.IsGenericType {
                    sourceBuilder = argument.GetGenericTypeDefinition() as TypeBuilder
                }
            } catch ex: NotSupportedException {
                return false
            } catch ex: NotImplementedException {
                return false
            }
        }
        if sourceBuilder == null {
            return false
        }

        sourceDefinition := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(sourceTypeDefinitions, sourceBuilder)
        if sourceDefinition == null {
            return false
        }
        if sourceDefinition.DefaultCtor != null && ConstructorHasPublicParameterlessShape(sourceDefinition.DefaultCtor, new Type[](0)) {
            return true
        }
        for constructor in sourceDefinition.Constructors {
            if constructor != null && ConstructorHasPublicParameterlessShape(constructor.Builder, constructor.ParamTypes) {
                return true
            }
        }
        return false
    }

    static func ConstructorHasPublicParameterlessShape(constructor: ConstructorBuilder, parameterTypes: Type[]): bool {
        return constructor != null && parameterTypes != null && parameterTypes.Length == 0 && (constructor.Attributes & MethodAttributes.MemberAccessMask) == MethodAttributes.Public
    }

    static func IsNullableValueType(candidate: Type): bool {
        return Nullable.GetUnderlyingType(candidate) != null
    }

    // Whether `argument` converts to the constraint type by an identity, reference or boxing
    // conversion. Asked structurally (the argument's base chain and interfaces), because
    // `IsAssignableFrom` answers nothing for a type still being written.
    static func ConstraintAccepts(constraint: Type, argument: Type): bool {
        if constraint == typeof(object) || constraint == typeof(ValueType) && argument.IsValueType {
            return true
        }
        if RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(constraint, argument) {
            return true
        }
        if RuntimeAssignableFrom(constraint, argument) {
            return true
        }

        // An open argument satisfies a type constraint only when one of its declared constraints
        // entails it. `U : Stream` can satisfy `T : IDisposable`; an unconstrained `U` cannot.
        if argument.IsGenericParameter {
            for argumentConstraint in GenericParameterConstraintsOrEmpty(argument) {
                if RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(constraint, argumentConstraint) || ConstraintAccepts(constraint, argumentConstraint) {
                    return true
                }
            }
            return false
        }

        // The argument's base chain, and at each link the interfaces THAT link implements: a source
        // `Worker: BackgroundService` reaches `IHostedService` through its external base.
        current: Type? = argument
        while current != null {
            if RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(constraint, current) {
                return true
            }
            if constraint.IsInterface {
                for interfaceItem in InterfaceListOrEmpty(current) {
                    if RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(constraint, interfaceItem) {
                        return true
                    }
                }
            }
            current = BaseTypeOrNull(current)
        }
        return false
    }

    static func GenericParameterConstraintsOrEmpty(argument: Type): Type[] {
        try {
            constraints := argument.GetGenericParameterConstraints()
            return constraints ?? new Type[](0)
        } catch ex: NotSupportedException {
            return new Type[](0)
        } catch ex: NotImplementedException {
            return new Type[](0)
        } catch ex: InvalidOperationException {
            return new Type[](0)
        }
    }

    // The interfaces a type implements: reflection's answer, or the guarded sweep for a type still being
    // written (whose `GetInterfaces` throws).
    static func InterfaceListOrEmpty(candidate: Type): Type[] {
        try {
            found := candidate.GetInterfaces()
            if found != null {
                return found
            }
        } catch ex: NotSupportedException {
            return InterfacesOrEmpty(candidate)
        } catch ex: NotImplementedException {
            return InterfacesOrEmpty(candidate)
        }
        return new Type[](0)
    }

    static func Unify(parameterType: Type, argumentType: Type, bindings: Dictionary<int, List<ColumnarGenericInferenceBound>>, allowInferenceWidening: bool): bool {
        return Unify(parameterType, argumentType, bindings, allowInferenceWidening, ColumnarGenericInferenceBoundKind.Lower)
    }

    static func Unify(parameterType: Type, argumentType: Type, bindings: Dictionary<int, List<ColumnarGenericInferenceBound>>, allowInferenceWidening: bool, boundKind: ColumnarGenericInferenceBoundKind): bool {
        if parameterType == null || argumentType == null {
            return false
        }
        if !parameterType.ContainsGenericParameters {
            return true
        }
        if parameterType.IsByRef {
            if !allowInferenceWidening {
                return false
            }
            element := parameterType.GetElementType()
            if element == null {
                return false
            }
            return Unify(element, StripByRef(argumentType), bindings, allowInferenceWidening, ColumnarGenericInferenceBoundKind.Exact)
        }

        if parameterType.IsGenericParameter {
            // A type parameter of the DECLARING type is already fixed by the owner; only a METHOD type
            // parameter is inferred here.
            if parameterType.DeclaringMethod == null {
                return true
            }
            if IsUnbindableInferredType(argumentType) {
                return false
            }
            position := parameterType.GenericParameterPosition
            bounds := new List<ColumnarGenericInferenceBound>()
            if !bindings.TryGetValue(position, out bounds) {
                bounds = new List<ColumnarGenericInferenceBound>()
                bindings.Add(position, bounds)
            }
            bounds.Add(new ColumnarGenericInferenceBound(argumentType, boundKind))
            return true
        }

        if parameterType.IsArray {
            if !argumentType.IsArray {
                return allowInferenceWidening
            }
            if !allowInferenceWidening && (!ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(parameterType) || !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(argumentType)) {
                return false
            }
            parameterElement := parameterType.GetElementType()
            argumentElement := argumentType.GetElementType()
            if parameterElement == null || argumentElement == null {
                return allowInferenceWidening
            }
            return Unify(parameterElement, argumentElement, bindings, allowInferenceWidening, boundKind)
        }

        if !parameterType.IsGenericType || !parameterType.ContainsGenericParameters {
            return true
        }

        definition := parameterType.GetGenericTypeDefinition()
        matched: Type? = null
        if allowInferenceWidening {
            matched = FindMatchingInstantiation(definition, argumentType)
        } else if IsInstantiationOf(definition, argumentType) {
            matched = argumentType
        } else {
            return false
        }
        if matched == null {
            return allowInferenceWidening
        }

        parameterArguments := parameterType.GetGenericArguments()
        matchedArguments := matched.GetGenericArguments()
        formalArguments := definition.GetGenericArguments()
        if parameterArguments.Length != matchedArguments.Length {
            return true
        }

        position := 0
        while position < parameterArguments.Length {
            nestedBoundKind := BoundKindForVariance(boundKind, formalArguments[position].GenericParameterAttributes)
            if !Unify(parameterArguments[position], matchedArguments[position], bindings, allowInferenceWidening, nestedBoundKind) {
                return false
            }
            position = position + 1
        }
        return true
    }

    static func BoundKindForVariance(boundKind: ColumnarGenericInferenceBoundKind, attributes: GenericParameterAttributes): ColumnarGenericInferenceBoundKind {
        if boundKind == ColumnarGenericInferenceBoundKind.Exact {
            return ColumnarGenericInferenceBoundKind.Exact
        }
        variance := attributes & GenericParameterAttributes.VarianceMask
        if variance == GenericParameterAttributes.None {
            return ColumnarGenericInferenceBoundKind.Exact
        }
        if variance == GenericParameterAttributes.Covariant {
            return boundKind
        }
        if boundKind == ColumnarGenericInferenceBoundKind.Lower {
            return ColumnarGenericInferenceBoundKind.Upper
        }
        return ColumnarGenericInferenceBoundKind.Lower
    }

    // The instantiation of `definition` reachable from the argument type: the type itself, one of its
    // base classes, or one of its interfaces. This is what lets `IEnumerable<T>` infer `T` from a
    // `List<int>` argument.
    static func FindMatchingInstantiation(definition: Type, argumentType: Type): Type? {
        current: Type? = argumentType
        while current != null {
            if IsInstantiationOf(definition, current) {
                return current
            }
            current = BaseTypeOrNull(current)
        }

        interfaces := InterfacesOrEmpty(argumentType)
        for interfaceItem in interfaces {
            if IsInstantiationOf(definition, interfaceItem) {
                return interfaceItem
            }
        }
        return null
    }

    static func IsInstantiationOf(definition: Type, candidate: Type): bool {
        if !candidate.IsGenericType || candidate.IsGenericTypeDefinition {
            return false
        }
        return RuntimeTypeShapeFacts.ExactTypeShapeMatchesWithGenericParameterIdentity(candidate.GetGenericTypeDefinition(), definition)
    }

    // THE ARGUMENT'S INTERFACES, INCLUDING WHEN IT IS CLOSED OVER A TYPE THIS COMPILATION WRITES.
    // `List<Pet>.GetInterfaces()` throws when `Pet` is still being emitted, and an empty list here
    // left `IEnumerable<T>` with nothing to infer `T` from: `string.Join(",", pets)` declined while
    // the same call over a `List<string>` bound `Join<string>`. The receiver-side sweep already
    // answers the question from the argument's generic DEFINITION, and it is asked here too.
    static func InterfacesOrEmpty(argumentType: Type): Type[] {
        try {
            found := ColumnarRuntimeInstanceMemberResolver.InheritedInterfaceSweep(argumentType)
            if found == null {
                return new Type[](0)
            }
            return found
        } catch ex: NotSupportedException {
            return new Type[](0)
        } catch ex: NotImplementedException {
            return new Type[](0)
        }
    }

    static func BaseTypeOrNull(current: Type): Type? {
        try {
            return current.BaseType
        } catch ex: NotSupportedException {
            return null
        } catch ex: NotImplementedException {
            return null
        }
    }

    static func StripByRef(candidate: Type): Type {
        if !candidate.IsByRef {
            return candidate
        }
        element := candidate.GetElementType()
        if element == null {
            return candidate
        }
        return element
    }

    // A type argument the CLR cannot close a method over. `void`, a by-ref or pointer shape and a
    // still-open one are what reach here.
    static func IsUnbindableInferredType(argumentType: Type): bool {
        if argumentType.FullName == "System.Void" || argumentType.IsByRef || argumentType.IsPointer {
            return true
        }
        if IsEmittedTypeParameter(argumentType) {
            return false
        }

        // A SHAPE CLOSED OVER THE DECLARATION BEING EMITTED — `Action<THandler>` inside
        // `NSharpEventSubscription<THandler>`. It is "open" only in the sense that its argument is a
        // parameter of the type currently being written; at every instantiation it is a closed type,
        // and `MakeGenericMethod` over it is the same Reflection.Emit shape a bare source type
        // parameter already is. `CloseOrNull` is the arbiter: if Reflection refuses the
        // instantiation, the candidate is dropped there rather than guessed at here.
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(argumentType) {
            return false
        }

        return argumentType.ContainsGenericParameters
    }

    // A TYPE PARAMETER OF THE DECLARATION BEING EMITTED — `TOk` inside `Result<TOk, TErr>`, or a
    // generic function's own `T`. Reflection.Emit closes a runtime generic method over one, so
    // `HashCode.Combine(state, ok)` inside a generic type is an ordinary MethodSpec rather than a
    // shape with no handle. It is the ONLY open type admitted here: every other unresolved shape
    // would produce a handle with no meaning at the call site.
    static func IsEmittedTypeParameter(candidateType: Type): bool {
        return candidateType != null && candidateType is GenericTypeParameterBuilder
    }

    // THE CLOSED SIGNATURE IS SUBSTITUTED, NOT READ BACK. For a runtime instantiation the two are the
    // same answer, so nothing changes for the tier's existing shapes. For a
    // `MethodBuilderInstantiation` they are not: its `GetParameters` reports the DEFINITION's own
    // `T1, T2`, and scoring a call against those would compare each argument to an unrelated type
    // parameter and select on noise.
    static func ClosedParameterTypesOrNull(definition: MethodInfo, typeArguments: Type[]): Type[]? {
        return ClosedParameterTypesOrNull(definition, typeArguments, definition.GetParameters())
    }

    static func ClosedParameterTypesOrNull(definition: MethodInfo, typeArguments: Type[], parameters: ParameterInfo[]): Type[]? {
        if definition == null || typeArguments == null || parameters == null {
            return null
        }
        result := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameterType := SubstituteMethodTypeArguments(parameters[index].ParameterType, typeArguments)
            if parameterType == null || IsUnsupportedClosedSignatureType(parameterType) {
                return null
            }
            result[index] = parameterType
            index = index + 1
        }

        return result
    }

    static func ClosedReturnTypeOrNull(definition: MethodInfo, typeArguments: Type[]): Type? {
        returnType := SubstituteMethodTypeArguments(definition.ReturnType, typeArguments)
        if returnType == null || returnType.IsByRef || returnType.IsPointer {
            return null
        }
        // A return that is ITSELF a source type parameter is a value the emitter can hold; one that
        // merely CONTAINS an open parameter (`List<T>`) is left to the tier that grows a call site.
        if !IsEmittedTypeParameter(returnType) && returnType.ContainsGenericParameters {
            return null
        }
        return returnType
    }

    // A source type parameter is a legal closed signature type — the CLR resolves it per
    // instantiation. Everything else keeps the ordinary tier's answer.
    static func IsUnsupportedClosedSignatureType(signatureType: Type): bool {
        if IsEmittedTypeParameter(signatureType) {
            return false
        }

        // A closed PARAMETER may be `ref`/`out` — `Interlocked.Exchange<T>(ref T, T)` closes to
        // `(ref Action, Action)` and that is the whole shape. The element is asked the ordinary
        // question; a by-ref of a by-ref is not a signature the CLR can spell.
        return ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedParameterType(signatureType, new Type[](0))
    }

    // The definition's signature rewritten under the inferred arguments. Only the METHOD's own type
    // parameters are rewritten: a candidate is read off a CLOSED lookup type, so the declaring type's
    // parameters are already substituted before this walk sees them.
    static func SubstituteMethodTypeArguments(signatureType: Type?, typeArguments: Type[]): Type? {
        if signatureType == null {
            return null
        }

        if signatureType.IsGenericParameter {
            if signatureType.DeclaringMethod == null {
                return signatureType
            }
            position := signatureType.GenericParameterPosition
            if position < 0 || position >= typeArguments.Length {
                return null
            }
            return typeArguments[position]
        }

        if !signatureType.ContainsGenericParameters {
            return signatureType
        }

        if signatureType.IsByRef {
            byRefElement := SubstituteMethodTypeArguments(signatureType.GetElementType(), typeArguments)
            if byRefElement == null {
                return null
            }
            return byRefElement.MakeByRefType()
        }

        if signatureType.IsArray {
            // A multi-dimensional array is left to the tier that grows a call site for one; its rank
            // would have to be reconstructed, and no shape in the corpus asks for it.
            if !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(signatureType) {
                return null
            }
            arrayElement := SubstituteMethodTypeArguments(signatureType.GetElementType(), typeArguments)
            if arrayElement == null {
                return null
            }
            return arrayElement.MakeArrayType()
        }

        if !signatureType.IsGenericType {
            return null
        }

        arguments := signatureType.GetGenericArguments()
        substituted := new Type[](arguments.Length)
        index := 0
        while index < arguments.Length {
            resolved := SubstituteMethodTypeArguments(arguments[index], typeArguments)
            if resolved == null {
                return null
            }
            substituted[index] = resolved
            index = index + 1
        }

        try {
            return signatureType.GetGenericTypeDefinition().MakeGenericType(substituted)
        } catch ex: ArgumentException {
            return null
        } catch ex: NotSupportedException {
            return null
        }
    }

    static func Ambiguous(lookupType: Type, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return new ColumnarOrdinaryRuntimeDirectCallSelection(
            ColumnarOrdinaryRuntimeDirectCallStatus.Ambiguous,
            null,
            lookupType,
            lookupType,
            new Type[](0),
            typeof(object),
            ColumnarExternalCallKind.None,
            expectedStatic,
            !expectedStatic && !lookupType.IsValueType,
            false,
            null,
            new Type[](0),
            -1
        )
    }
    static func Unselected(lookupType: Type, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return new ColumnarOrdinaryRuntimeDirectCallSelection(
            ColumnarOrdinaryRuntimeDirectCallStatus.NotFound,
            null,
            lookupType,
            lookupType,
            new Type[](0),
            typeof(object),
            ColumnarExternalCallKind.None,
            expectedStatic,
            !expectedStatic && !lookupType.IsValueType,
            false,
            null,
            new Type[](0),
            -1
        )
    }
}

// ONE EXTERNAL METHOD SELECTED FOR A CALL SITE THAT WROTE ITS TYPE ARGUMENTS.
//
// `ExplicitArgumentCount` is how many of `ParameterTypes` the site supplies; every parameter from
// there on is a trailing optional filled from its null metadata default, exactly as the ordinary
// resolver's optional-fill tier does for a non-generic declaration.
class ColumnarExplicitGenericCallSelection {
    IsSelected: bool
    Method: MethodInfo?
    LookupType: Type
    ParameterTypes: Type[]
    ReturnType: Type
    ExplicitArgumentCount: int
    IsStatic: bool
    UsesCallVirtual: bool

    constructor(isSelected: bool, method: MethodInfo?, lookupType: Type, parameterTypes: Type[], returnType: Type, explicitArgumentCount: int, isStatic: bool, usesCallVirtual: bool) {
        if lookupType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Explicit generic call selection facts cannot be null.")
        }
        if isSelected && (method == null || explicitArgumentCount < 0 || explicitArgumentCount > parameterTypes.Length) {
            throw new InvalidOperationException("A selected explicit generic call requires an exact handle and a supplied-argument count within its signature.")
        }
        if !isSelected && (method != null || parameterTypes.Length != 0) {
            throw new InvalidOperationException("An unselected explicit generic call cannot carry executable method facts.")
        }

        IsSelected = isSelected
        Method = method
        LookupType = lookupType
        ParameterTypes = parameterTypes
        ReturnType = returnType
        ExplicitArgumentCount = explicitArgumentCount
        IsStatic = isStatic
        UsesCallVirtual = usesCallVirtual
    }

    static func None(lookupType: Type): ColumnarExplicitGenericCallSelection {
        return new ColumnarExplicitGenericCallSelection(false, null, lookupType, new Type[](0), typeof(object), 0, false, false)
    }
}

// EXTERNAL GENERIC METHODS, CLOSED OVER THE TYPE ARGUMENTS THE CALL SITE WROTE.
//
// This is the explicit twin of the inference tier above, and the ONLY difference between them is
// where the type arguments come from: written by the site instead of unified from the arguments.
// Everything after that is the same answer — `CloseOrNull` checks the declared constraints, the
// closed signature is SUBSTITUTED rather than read back, and the resulting handle is an ordinary
// MethodInfo the call site emits with an ordinary `call`/`callvirt`.
//
// THE WRITTEN COUNT MUST MATCH THE DECLARATION'S ARITY (ECMA-334 §12.6.4.1): a candidate whose own
// arity differs is not a candidate at all, so `Is<int, string>()` on `Is<T>()` never binds and the
// call site reports the ordinary "no overload" arity diagnostic instead of closing something wrong.
class ColumnarExplicitRuntimeGenericMethodResolver {

    // The unique candidate for a site whose ARGUMENT TYPES are not all knowable ahead of emission — a
    // lambda argument has no type until it is bound against the parameter it is passed to. A name
    // that leaves more than one closed candidate at this arity is left to the scored overload below.
    static func Resolve(lookupType: Type, memberName: string, typeArguments: Type[], argumentCount: int, expectedStatic: bool, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): ColumnarExplicitGenericCallSelection {
        candidates := new List<MethodInfo>()
        candidateParameters := new List<Type[]>()
        candidateReturns := new List<Type>()
        if !TryCollect(lookupType, memberName, typeArguments, argumentCount, expectedStatic, candidates, candidateParameters, candidateReturns, sourceTypeDefinitions) {
            return ColumnarExplicitGenericCallSelection.None(lookupType)
        }

        if candidates.Count != 1 {
            return ColumnarExplicitGenericCallSelection.None(lookupType)
        }

        return Selected(lookupType, candidates[0], candidateParameters[0], candidateReturns[0], argumentCount, expectedStatic)
    }

    // EVERY closed candidate the site admits, for a caller that chooses among them by something this
    // resolver cannot see — a lambda argument's arity against each candidate's delegate parameter.
    static func Candidates(lookupType: Type, memberName: string, typeArguments: Type[], argumentCount: int, expectedStatic: bool, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): List<ColumnarExplicitGenericCallSelection> {
        selections := new List<ColumnarExplicitGenericCallSelection>()
        candidates := new List<MethodInfo>()
        candidateParameters := new List<Type[]>()
        candidateReturns := new List<Type>()
        if !TryCollect(lookupType, memberName, typeArguments, argumentCount, expectedStatic, candidates, candidateParameters, candidateReturns, sourceTypeDefinitions) {
            return selections
        }

        index := 0
        while index < candidates.Count {
            selections.Add(Selected(lookupType, candidates[index], candidateParameters[index], candidateReturns[index], argumentCount, expectedStatic))
            index = index + 1
        }
        return selections
    }

    // The same candidate set, ranked by the argument-flow scorer every other call selection uses. A
    // site whose arguments all type ahead of emission gets ordinary overload resolution; a tie is
    // refused rather than guessed.
    static func ResolveWithFacts(lookupType: Type, memberName: string, typeArguments: Type[], argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): ColumnarExplicitGenericCallSelection {
        if argumentTypes == null {
            throw new InvalidOperationException("Explicit generic method resolution inputs cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        candidates := new List<MethodInfo>()
        candidateParameters := new List<Type[]>()
        candidateReturns := new List<Type>()
        if !TryCollect(lookupType, memberName, typeArguments, argumentTypes.Length, expectedStatic, candidates, candidateParameters, candidateReturns, sourceTypeDefinitions ?? argumentFacts.SourceTypeDefinitions) {
            return ColumnarExplicitGenericCallSelection.None(lookupType)
        }

        bestScore := -1
        bestParameterCount := 0
        bestCount := 0
        bestIndex := -1
        index := 0
        while index < candidates.Count {
            parameterTypes := candidateParameters[index]
            leading := LeadingParameterTypes(parameterTypes, argumentTypes.Length)
            modifiers := ColumnarDirectCallPlanner.ParameterModifierKindSlice(ColumnarOrdinaryRuntimeDirectCallResolver.ReflectedModifierKinds(candidates[index].GetParameters()), 0, argumentTypes.Length)
            score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(leading, argumentTypes, argumentFacts, modifiers)
            if score >= 0 {
                parameterCount := parameterTypes.Length
                if score > bestScore || (score == bestScore && parameterCount < bestParameterCount) {
                    bestScore = score
                    bestParameterCount = parameterCount
                    bestCount = 1
                    bestIndex = index
                } else if score == bestScore && parameterCount == bestParameterCount {
                    bestCount = bestCount + 1
                }
            }
            index = index + 1
        }

        if bestCount != 1 || bestIndex < 0 {
            return ColumnarExplicitGenericCallSelection.None(lookupType)
        }

        return Selected(lookupType, candidates[bestIndex], candidateParameters[bestIndex], candidateReturns[bestIndex], argumentTypes.Length, expectedStatic)
    }

    // Every declared generic method of `lookupType` whose name, staticness, own arity and parameter
    // count admit this site, closed over the written type arguments. A candidate whose declared
    // constraints or substituted signature refuse the closure is dropped here, which makes that a
    // "no such call" answer rather than an exception at emit.
    static func TryCollect(lookupType: Type, memberName: string, typeArguments: Type[], argumentCount: int, expectedStatic: bool, candidates: List<MethodInfo>, candidateParameters: List<Type[]>, candidateReturns: List<Type>, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>? = null): bool {
        if lookupType == null || memberName == null || typeArguments == null || typeArguments.Length == 0 || argumentCount < 0 {
            throw new InvalidOperationException("Explicit generic method resolution inputs cannot be null.")
        }

        // The same owner boundary the inference tier keeps: a builder-bound or still-open lookup type
        // has no reachable member table, and closing a method on one would need the TYPE's arguments
        // bound at the same time.
        if RuntimeTypeShapeFacts.ContainsBuilderBoundType(lookupType) || lookupType.IsGenericTypeDefinition || lookupType.IsGenericParameter {
            return false
        }

        for typeArgument in typeArguments {
            if typeArgument == null {
                return false
            }
        }

        declared := ColumnarRuntimeGenericMethodResolver.GenericMethodDefinitionsNamedOrEmpty(lookupType, memberName)
        exactArity := false
        for candidate in declared {
            parameters := AdmittedParameters(candidate, lookupType, memberName, typeArguments.Length, argumentCount, expectedStatic)
            if parameters != null {
                closed := ColumnarRuntimeGenericMethodResolver.CloseSubstituted(candidate, typeArguments, sourceTypeDefinitions)
                if closed != null && TailFillable(parameters, closed.ParameterTypes, argumentCount) {
                    candidates.Add(closed.Method)
                    candidateParameters.Add(closed.ParameterTypes)
                    candidateReturns.Add(closed.ReturnType)
                    if closed.ParameterTypes.Length == argumentCount {
                        exactArity = true
                    }
                }
            }
        }

        // AN EXACTLY-MATCHING ARITY BEATS A FILLED TAIL, which is C#'s rule and the ordinary
        // resolver's: optional-fill is only consulted when nothing takes the arguments as written.
        if exactArity {
            keep := 0
            while keep < candidateParameters.Count {
                if candidateParameters[keep].Length == argumentCount {
                    keep = keep + 1
                } else {
                    candidates.RemoveAt(keep)
                    candidateParameters.RemoveAt(keep)
                    candidateReturns.RemoveAt(keep)
                }
            }
        }

        return candidates.Count > 0
    }

    // The candidate's parameters when its shape admits this site, or null. The exclusions are the
    // inference tier's, plus the written-arity rule.
    static func AdmittedParameters(candidate: MethodInfo?, lookupType: Type, memberName: string, typeArgumentCount: int, argumentCount: int, expectedStatic: bool): ParameterInfo[]? {
        if candidate == null || !ColumnarRuntimeGenericMethodResolver.IsInferableCandidateShape(candidate, lookupType, memberName, expectedStatic) {
            return null
        }
        if candidate.GetGenericArguments().Length != typeArgumentCount {
            return null
        }

        parameters := candidate.GetParameters()
        if parameters == null || parameters.Length < argumentCount {
            return null
        }
        for parameter in parameters {
            if parameter == null || parameter.ParameterType == null || ColumnarExtensionMethodResolver.IsParamsParameter(parameter) {
                return null
            }
        }
        return parameters
    }

    static func TailFillable(parameters: ParameterInfo[], closedParameters: Type[], argumentCount: int): bool {
        if parameters.Length != closedParameters.Length {
            return false
        }
        index := argumentCount
        while index < closedParameters.Length {
            if !ColumnarExtensionMethodResolver.CanFillOptional(parameters[index], closedParameters[index]) {
                return false
            }
            index = index + 1
        }
        return true
    }

    static func LeadingParameterTypes(parameterTypes: Type[], count: int): Type[] {
        if parameterTypes.Length == count {
            return parameterTypes
        }
        leading := new Type[](count)
        index := 0
        while index < count {
            leading[index] = parameterTypes[index]
            index = index + 1
        }
        return leading
    }

    static func Selected(lookupType: Type, method: MethodInfo, parameterTypes: Type[], returnType: Type, argumentCount: int, expectedStatic: bool): ColumnarExplicitGenericCallSelection {
        usesCallVirtual := !expectedStatic && !lookupType.IsValueType
        return new ColumnarExplicitGenericCallSelection(true, method, lookupType, parameterTypes, returnType, argumentCount, expectedStatic, usesCallVirtual)
    }
}
