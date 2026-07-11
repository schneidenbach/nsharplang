namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Diagnostics
import System.Globalization
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Text
import System.Text.Json
import YamlDotNet.Core
import YamlDotNet.Core.Events
import YamlDotNet.Serialization


// Direct schema-v3 owner for the deliberately non-contextual construction surface: exact
// non-generic constructor calls, sized SZ arrays, and nonempty homogeneous array literals.
// Later contextual construction families remain a whole-subtree boundary; malformed syntax in
// this owner's admitted family is terminal and can never be reinterpreted by the legacy emitter.
class ColumnarConstructionPlanner {
    static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        kind := nodes.Kind(candidate)
        return kind == ColumnarExpressionNodeKind.NewExpression()
            || kind == ColumnarExpressionNodeKind.ArrayLiteralExpression()
    }

    // DirectCall's syntax preflight may use this without walking NewExpression's type child as a
    // value. Exact type-shape and semantic rejection remain this planner's responsibility.
    static func IsAdmittedValueSyntax(
        nodes: ColumnarNodeTable,
        node: int,
        depth: int): bool {
        if nodes == null || depth > 200 {
            return false
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }

        kind := nodes.Kind(candidate)
        childStart := 0
        if kind == ColumnarExpressionNodeKind.NewExpression() {
            if nodes.ChildCount(candidate) < 1 {
                return true
            }
            typeNode := nodes.Child(candidate, 0)
            if typeNode < 0 || typeNode >= nodes.Kinds.Length {
                return true
            }
            typeKind := nodes.Kind(typeNode)
            if typeKind != 0 && typeKind != 2 {
                return false
            }
            childStart = 1
        } else if kind != ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            return false
        }

        index := childStart
        while index < nodes.ChildCount(candidate) {
            child := nodes.Child(candidate, index)
            if ColumnarConstructionPlanner.MayPlanRoot(nodes, child) {
                if !IsAdmittedValueSyntax(nodes, child, depth + 1) {
                    return false
                }
            } else if !ColumnarDirectCallPlanner.IsAdmittedValueSyntax(
                    nodes, child, depth + 1) {
                return false
            }
            index += 1
        }
        return true
    }

    static func TryEmit(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        il: ILGenerator,
        out nsharpOwned: bool,
        out legacyWholeSubtreePlanning: bool,
        out resultType: Type): bool {
        ownership := ColumnarDirectCallOwnership.NotOwned
        status := Plan(
            nodes, source, node, bindings, plan,
            out ownership, out legacyWholeSubtreePlanning, out resultType)
        ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
        nsharpOwned = ownership != ColumnarDirectCallOwnership.NotOwned
        if status != ColumnarFragmentPlanStatus.Planned {
            return false
        }

        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    static func TryGetType(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        out nsharpOwned: bool,
        out legacyWholeSubtreePlanning: bool,
        out resultType: Type): bool {
        ownership := ColumnarDirectCallOwnership.NotOwned
        status := Plan(
            nodes, source, node, bindings, plan,
            out ownership, out legacyWholeSubtreePlanning, out resultType)
        ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
        nsharpOwned = ownership != ColumnarDirectCallOwnership.NotOwned
        if status != ColumnarFragmentPlanStatus.Planned {
            return false
        }

        resultType = RequiredResultType(plan)
        return true
    }

    static func Plan(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        out ownership: ColumnarDirectCallOwnership,
        out legacyWholeSubtreePlanning: bool,
        out resultType: Type): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        plan.PrepareV3()

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || !MayPlanRoot(nodes, candidate) {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            fragment := plan.BeginFragment(-1, nodes.Kind(candidate), candidate)
            handles := ColumnarRangeIndexHandles.Resolve()
            if !TryAppend(
                    nodes, source, candidate, bindings, handles, plan,
                    fragment, 0,
                    out ownership,
                    out legacyWholeSubtreePlanning,
                    out resultType) {
                plan.Rollback(checkpoint)
                ValidateOwnershipBoundary(ownership, legacyWholeSubtreePlanning)
                return plan.Status
            }

            plan.CompleteFragment(fragment, resultType)
            plan.CompleteV3(resultType)
            ownership = ColumnarDirectCallOwnership.Planned
            return plan.Status
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    // The caller has already opened the expression fragment. This operation appends only its
    // value rows and leaves fragment completion to the shared recursive planner.
    static func TryAppend(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        out ownership: ColumnarDirectCallOwnership,
        out legacyWholeSubtreePlanning: bool,
        out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.NotOwned
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || handles == null
            || plan == null || node < 0 || node >= nodes.Kinds.Length
            || depth > 200 {
            return false
        }
        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
            || plan.Status != ColumnarFragmentPlanStatus.NotOwned
            || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException(
                "Construction append requires an open schema-v3 plan.")
        }

        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 {
            return false
        }
        kind := nodes.Kind(candidate)
        if kind == ColumnarExpressionNodeKind.ArrayLiteralExpression() {
            ownership = ColumnarDirectCallOwnership.OwnedRejected
            if TryAppendInferredArray(
                    nodes, source, candidate, bindings, handles, plan,
                    fragment, depth,
                    out ownership,
                    out legacyWholeSubtreePlanning,
                    out resultType) {
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            return false
        }
        if kind != ColumnarExpressionNodeKind.NewExpression() {
            return false
        }

        ownership = ColumnarDirectCallOwnership.OwnedRejected
        if nodes.ChildCount(candidate) < 1 {
            return false
        }
        typeNode := nodes.Child(candidate, 0)
        if typeNode < 0 || typeNode >= nodes.Kinds.Length {
            return false
        }

        typeKind := nodes.Kind(typeNode)
        if typeKind == 1 {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }
        if typeKind == 2 {
            if TryAppendSizedArray(
                    nodes, source, candidate, typeNode, bindings, handles,
                    plan, fragment, depth,
                    out ownership,
                    out legacyWholeSubtreePlanning,
                    out resultType) {
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            return false
        }
        if typeKind != 0 || nodes.ChildCount(typeNode) != 0 {
            return false
        }

        canonical := ""
        targetType := typeof(object)
        if !TryBuildTypeCanonical(
                nodes, source, typeNode, 0, out canonical)
            || !TryResolveExactType(
                nodes, canonical, bindings, out targetType) {
            return false
        }

        // These retained families require target context, generic rebinding, or initobj. Their
        // exact roots and all containing expressions remain outside this ownership slice.
        if targetType.get_IsGenericParameter()
            || targetType.get_IsGenericTypeDefinition()
            || IsSourceUnionType(targetType, bindings)
            || targetType == typeof(JsonElement) {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }

        sourceDefinition: ColumnarStructDef? = null
        if TryFindSourceDefinition(targetType, bindings, out sourceDefinition)
            && sourceDefinition != null {
            if !sourceDefinition.IsReference
                && sourceDefinition.Constructors.Count == 0
                && nodes.ChildCount(candidate) == 1 {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }

            if TryAppendSourceConstruction(
                    nodes, source, candidate, bindings, handles, plan,
                    fragment, depth, sourceDefinition, targetType,
                    out ownership,
                    out legacyWholeSubtreePlanning) {
                resultType = targetType
                ownership = ColumnarDirectCallOwnership.Planned
                return true
            }
            return false
        }

        if TryAppendRuntimeConstruction(
                nodes, source, candidate, bindings, handles, plan,
                fragment, depth, targetType,
                out ownership,
                out legacyWholeSubtreePlanning) {
            resultType = targetType
            ownership = ColumnarDirectCallOwnership.Planned
            return true
        }
        return false
    }

    static func TryAppendSizedArray(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        typeNode: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        out ownership: ColumnarDirectCallOwnership,
        out legacyWholeSubtreePlanning: bool,
        out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        if nodes.ChildCount(node) != 2 || nodes.ChildCount(typeNode) != 1 {
            return false
        }

        elementNode := nodes.Child(typeNode, 0)
        elementSyntax := ClassifyExactSizedArrayElementSyntax(
            nodes, elementNode, 0)
        if elementSyntax == 0 {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }
        if elementSyntax < 0 {
            return false
        }

        elementCanonical := ""
        elementType := typeof(object)
        if !TryBuildTypeCanonical(
                nodes, source, elementNode, 0,
                out elementCanonical)
            || !TryResolveExactType(
                nodes, elementCanonical, bindings, out elementType)
            || !IsSupportedArrayElement(elementType, bindings) {
            return false
        }

        lengthNode := nodes.Child(node, 1)
        if !ValueSyntaxIsAdmitted(nodes, lengthNode, depth + 1) {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }
        lengthType := typeof(int)
        nestedOwnership := ColumnarDirectCallOwnership.NotOwned
        if !ColumnarDirectCallPlanner.TryGetPlannableValueType(
                nodes, source, lengthNode, bindings, handles, depth + 1,
                out lengthType, out nestedOwnership) {
            if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = nestedOwnership
            } else {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
            }
            return false
        }
        if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                lengthType, typeof(int)) {
            return false
        }

        emittedLengthType := typeof(int)
        if !ColumnarRangeIndexPlanner.TryAppendPlannableValue(
                nodes, source, lengthNode, bindings, handles, plan,
                fragment, depth + 1, out emittedLengthType,
                out nestedOwnership)
            || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                emittedLengthType, typeof(int)) {
            if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = nestedOwnership
            }
            return false
        }

        elementIndex := plan.AddType(elementType)
        plan.AppendTypeInstruction(
            ColumnarCodePlanContract.Newarr(), elementIndex)
        resultType = elementType.MakeArrayType()
        return true
    }

    static func TryAppendInferredArray(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        out ownership: ColumnarDirectCallOwnership,
        out legacyWholeSubtreePlanning: bool,
        out resultType: Type): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        resultType = typeof(int)
        elementCount := nodes.ChildCount(node)
        if elementCount == 0 {
            ownership = ColumnarDirectCallOwnership.NotOwned
            legacyWholeSubtreePlanning = true
            return false
        }

        elementType := typeof(object)
        index := 0
        while index < elementCount {
            elementNode := nodes.Child(node, index)
            candidate := UnwrapParentheses(nodes, elementNode)
            if candidate < 0 {
                return false
            }
            if nodes.Kind(candidate)
                    == ColumnarExpressionNodeKind.NullLiteralExpression() {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }
            if !ValueSyntaxIsAdmitted(nodes, elementNode, depth + 1) {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }

            currentType := typeof(int)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            if !ColumnarDirectCallPlanner.TryGetPlannableValueType(
                    nodes, source, elementNode, bindings, handles,
                    depth + 1, out currentType, out nestedOwnership) {
                if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    ownership = nestedOwnership
                } else {
                    ownership = ColumnarDirectCallOwnership.NotOwned
                    legacyWholeSubtreePlanning = true
                }
                return false
            }
            if index == 0 {
                if !IsSupportedArrayElement(currentType, bindings) {
                    return false
                }
                elementType = currentType
            } else if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                    elementType, currentType) {
                return false
            }
            index += 1
        }

        countIndex := plan.AddInt32(elementCount)
        plan.AppendInt32Instruction(
            ColumnarCodePlanContract.LdcI4(), countIndex)
        elementTypeIndex := plan.AddType(elementType)
        plan.AppendTypeInstruction(
            ColumnarCodePlanContract.Newarr(), elementTypeIndex)

        index = 0
        while index < elementCount {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.Dup())
            arrayIndex := plan.AddInt32(index)
            plan.AppendInt32Instruction(
                ColumnarCodePlanContract.LdcI4(), arrayIndex)

            emittedType := typeof(int)
            nestedOwnership := ColumnarDirectCallOwnership.NotOwned
            if !ColumnarRangeIndexPlanner.TryAppendPlannableValue(
                    nodes, source, nodes.Child(node, index), bindings, handles,
                    plan, fragment, depth + 1,
                    out emittedType, out nestedOwnership)
                || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                    emittedType, elementType) {
                if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                    ownership = nestedOwnership
                }
                return false
            }
            AppendArrayElementStore(plan, elementType)
            index += 1
        }

        resultType = elementType.MakeArrayType()
        return true
    }

    static func TryAppendSourceConstruction(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        definition: ColumnarStructDef,
        targetType: Type,
        out ownership: ColumnarDirectCallOwnership,
        out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        argumentCount := nodes.ChildCount(node) - 1
        argumentTypes := new Type[](argumentCount)
        argumentFacts := ColumnarDirectCallArgumentFacts.Empty(argumentCount)
        argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
        if !TryGetConstructorArguments(
                nodes, source, node, bindings, handles, depth,
                argumentTypes, argumentFacts,
                out ownership, out legacyWholeSubtreePlanning) {
            return false
        }

        if argumentCount == 0 && definition.IsReference
            && definition.DefaultCtor != null {
            parameters := new Type[](0)
            if !ConstructorBuilderMatches(
                    definition.DefaultCtor, targetType) {
                throw new InvalidOperationException(
                    "Source default-constructor facts do not identify their exact owner.")
            }
            constructorIndex := plan.AddConstructorWithSignature(
                definition.DefaultCtor, targetType, parameters)
            plan.AppendConstructorInstruction(
                ColumnarCodePlanContract.Newobj(), constructorIndex)
            return true
        }

        selected: ColumnarConstructorDef? = null
        if !TrySelectSourceConstructor(
                definition, argumentTypes, argumentFacts, bindings,
                out selected)
            || selected == null {
            return false
        }

        suppliedParameters := PrefixTypes(
            selected.ParamTypes, argumentCount)
        if !ColumnarDirectCallPlanner.AppendArguments(
                nodes, source, node, bindings, handles, plan, fragment,
                depth + 1, argumentTypes, suppliedParameters, argumentFacts) {
            return false
        }

        defaultIndex := argumentCount
        while defaultIndex < selected.ParamTypes.Length {
            if !TryAppendConstructorDefault(
                    plan,
                    selected.ParamTypes[defaultIndex],
                    selected.DefaultKinds[defaultIndex],
                    selected.DefaultTexts[defaultIndex],
                    bindings) {
                return false
            }
            defaultIndex += 1
        }

        constructorIndex := plan.AddConstructorWithSignature(
            selected.Builder, targetType, selected.ParamTypes)
        plan.AppendConstructorInstruction(
            ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryAppendRuntimeConstruction(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        plan: ColumnarCodePlan,
        fragment: int,
        depth: int,
        targetType: Type,
        out ownership: ColumnarDirectCallOwnership,
        out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        argumentCount := nodes.ChildCount(node) - 1
        parameters := new Type[](0)
        constructor: ConstructorInfo? = null
        if !TrySelectRuntimeConstructor(
                targetType, argumentCount, out constructor, out parameters)
            || constructor == null {
            return false
        }

        argumentTypes := new Type[](argumentCount)
        argumentFacts := ColumnarDirectCallArgumentFacts.Empty(argumentCount)
        argumentFacts.SourceTypeDefinitions = bindings.SourceTypeDefinitions
        if !TryGetConstructorArguments(
                nodes, source, node, bindings, handles, depth,
                argumentTypes, argumentFacts,
                out ownership, out legacyWholeSubtreePlanning) {
            return false
        }
        if !ColumnarDirectCallPlanner.AppendArguments(
                nodes, source, node, bindings, handles, plan, fragment,
                depth + 1, argumentTypes, parameters, argumentFacts) {
            return false
        }

        constructorIndex := plan.AddConstructorWithSignature(
            constructor, targetType, parameters)
        plan.AppendConstructorInstruction(
            ColumnarCodePlanContract.Newobj(), constructorIndex)
        return true
    }

    static func TryGetConstructorArguments(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        handles: ColumnarRangeIndexHandles,
        depth: int,
        argumentTypes: Type[],
        argumentFacts: ColumnarDirectCallArgumentFacts,
        out ownership: ColumnarDirectCallOwnership,
        out legacyWholeSubtreePlanning: bool): bool {
        ownership = ColumnarDirectCallOwnership.OwnedRejected
        legacyWholeSubtreePlanning = false
        index := 1
        while index < nodes.ChildCount(node) {
            if !ValueSyntaxIsAdmitted(
                    nodes, nodes.Child(node, index), depth + 1) {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
                return false
            }
            index += 1
        }

        nestedOwnership := ColumnarDirectCallOwnership.NotOwned
        if !ColumnarDirectCallPlanner.TryGetArgumentTypes(
                nodes, source, node, bindings, handles, depth,
                argumentTypes, argumentFacts, out nestedOwnership) {
            if nestedOwnership == ColumnarDirectCallOwnership.OwnedRejected {
                ownership = nestedOwnership
            } else {
                ownership = ColumnarDirectCallOwnership.NotOwned
                legacyWholeSubtreePlanning = true
            }
            return false
        }
        return true
    }

    static func TrySelectSourceConstructor(
        definition: ColumnarStructDef,
        argumentTypes: Type[],
        argumentFacts: ColumnarDirectCallArgumentFacts,
        bindings: ColumnarFragmentBindings,
        out selected: ColumnarConstructorDef?): bool {
        selected = null
        candidates := new List<ColumnarConstructorDef>()
        for candidate in definition.Constructors {
            ValidateSourceConstructor(definition, candidate)
            if candidate.ParamTypes.Length < argumentTypes.Length {
                continue
            }
            defaultsSupported := true
            defaultIndex := argumentTypes.Length
            while defaultIndex < candidate.ParamTypes.Length {
                if !CanUseConstructorDefault(
                        candidate.ParamTypes[defaultIndex],
                        candidate.DefaultKinds[defaultIndex],
                        candidate.DefaultTexts[defaultIndex],
                        bindings) {
                    defaultsSupported = false
                }
                defaultIndex += 1
            }
            if defaultsSupported {
                AddDistinctConstructor(candidates, candidate)
            }
        }
        if candidates.Count == 0 {
            return false
        }

        exact := new List<ColumnarConstructorDef>()
        for candidate in candidates {
            if candidate.ParamTypes.Length == argumentTypes.Length {
                exact.Add(candidate)
            }
        }
        if exact.Count > 0 {
            candidates = exact
        }
        if candidates.Count == 1 {
            selected = candidates[0]
            return true
        }

        for candidate in candidates {
            expected := PrefixTypes(
                candidate.ParamTypes, argumentTypes.Length)
            if ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(
                    expected, argumentTypes, argumentFacts) < 0 {
                continue
            }
            if selected != null {
                selected = null
                return false
            }
            selected = candidate
        }
        return selected != null
    }

    static func AddDistinctConstructor(
        values: List<ColumnarConstructorDef>,
        candidate: ColumnarConstructorDef) {
        for existing in values {
            if SameObject(existing.Builder, candidate.Builder) {
                return
            }
        }
        values.Add(candidate)
    }

    static func ValidateSourceConstructor(
        owner: ColumnarStructDef,
        candidate: ColumnarConstructorDef) {
        if owner == null || candidate == null || candidate.Builder == null
            || candidate.ParamTypes == null || candidate.DefaultKinds == null
            || candidate.DefaultTexts == null
            || candidate.DefaultKinds.Length != candidate.ParamTypes.Length
            || candidate.DefaultTexts.Length != candidate.ParamTypes.Length {
            throw new InvalidOperationException(
                "Source constructor facts must be complete and positional.")
        }
        ownerType: Type = owner.Builder
        if !ConstructorBuilderMatches(candidate.Builder, ownerType) {
            throw new InvalidOperationException(
                "Source constructor facts do not identify their exact owner.")
        }
        index := 0
        while index < candidate.ParamTypes.Length {
            if candidate.ParamTypes[index] == null
                || candidate.DefaultTexts[index] == null {
                throw new InvalidOperationException(
                    "Source constructor signature facts cannot contain null values.")
            }
            index += 1
        }
    }

    static func ConstructorBuilderMatches(
        constructor: ConstructorInfo,
        ownerType: Type): bool {
        if constructor == null || ownerType == null {
            return false
        }
        declaringType := constructor.get_DeclaringType()
        return declaringType != null
            && ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                declaringType, ownerType)
    }

    static func PrefixTypes(values: Type[], count: int): Type[] {
        if values == null || count < 0 || count > values.Length {
            throw new InvalidOperationException(
                "Constructor parameter prefix is invalid.")
        }
        result := new Type[](count)
        index := 0
        while index < count {
            result[index] = values[index]
            index += 1
        }
        return result
    }

    static func TrySelectRuntimeConstructor(
        targetType: Type,
        argumentCount: int,
        out constructor: ConstructorInfo?,
        out parameterTypes: Type[]): bool {
        constructor = null
        parameterTypes = new Type[](0)
        selectedParameterTypes := new Type[](0)

        if targetType == typeof(string) {
            if argumentCount == 2 {
                selectedParameterTypes = Types2(typeof(char), typeof(int))
            } else if argumentCount == 3 {
                selectedParameterTypes = Types3(
                    typeof(char).MakeArrayType(), typeof(int), typeof(int))
            } else {
                return false
            }
        } else if targetType == typeof(StringBuilder) {
            if argumentCount == 0 {
                selectedParameterTypes = new Type[](0)
            } else if argumentCount == 1 {
                selectedParameterTypes = Types1(typeof(int))
            } else {
                return false
            }
        } else if targetType == typeof(Version) {
            if argumentCount != 4 { return false }
            selectedParameterTypes = Types4(
                typeof(int), typeof(int), typeof(int), typeof(int))
        } else if targetType == typeof(object)
            || targetType == typeof(ProcessStartInfo)
            || targetType == typeof(Process)
            || targetType == typeof(JsonSerializerOptions)
            || targetType == typeof(DeserializerBuilder)
            || targetType == typeof(MappingStart)
            || targetType == typeof(MappingEnd) {
            if argumentCount != 0 { return false }
            selectedParameterTypes = new Type[](0)
        } else if targetType == typeof(StreamReader) {
            if argumentCount != 1 { return false }
            selectedParameterTypes = Types1(typeof(Stream))
        } else if targetType == typeof(Scalar) {
            if argumentCount != 1 { return false }
            selectedParameterTypes = Types1(typeof(string))
        } else if IsApprovedExceptionType(targetType) {
            if argumentCount == 0 {
                selectedParameterTypes = new Type[](0)
            } else if argumentCount == 1 {
                selectedParameterTypes = Types1(typeof(string))
            } else if argumentCount == 2 {
                selectedParameterTypes = Types2(typeof(string), typeof(string))
            } else {
                return false
            }
        } else {
            return false
        }

        parameterTypes = selectedParameterTypes
        resolvedConstructor := ColumnarRangeIndexHandles.RequiredConstructor(
            targetType, selectedParameterTypes, targetType.Name)
        if resolvedConstructor.get_DeclaringType() != targetType {
            throw new InvalidOperationException(
                "Construction runtime catalog resolved a constructor on the wrong owner.")
        }
        parameters := resolvedConstructor.GetParameters()
        if parameters.Length != selectedParameterTypes.Length {
            constructor = null
            return false
        }
        index := 0
        while index < parameters.Length {
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                    parameters[index].get_ParameterType(),
                    selectedParameterTypes[index]) {
                constructor = null
                return false
            }
            index += 1
        }
        constructor = resolvedConstructor
        return true
    }

    static func IsApprovedExceptionType(targetType: Type): bool {
        return targetType == typeof(Exception)
            || targetType == typeof(InvalidOperationException)
            || targetType == typeof(ArgumentException)
            || targetType == typeof(ArgumentNullException)
            || targetType == typeof(ArgumentOutOfRangeException)
            || targetType == typeof(FormatException)
            || targetType == typeof(NotSupportedException)
            || targetType == typeof(NotImplementedException)
            || targetType == typeof(TimeoutException)
            || targetType == typeof(DivideByZeroException)
            || targetType == typeof(ArithmeticException)
            || targetType == typeof(OverflowException)
            || targetType == typeof(NullReferenceException)
            || targetType == typeof(IndexOutOfRangeException)
            || targetType == typeof(InvalidCastException)
            || targetType == typeof(FileNotFoundException)
            || targetType == typeof(YamlException)
    }

    static func Types1(first: Type): Type[] {
        result := new Type[](1)
        result[0] = first
        return result
    }

    static func Types2(first: Type, second: Type): Type[] {
        result := new Type[](2)
        result[0] = first
        result[1] = second
        return result
    }

    static func Types3(first: Type, second: Type, third: Type): Type[] {
        result := new Type[](3)
        result[0] = first
        result[1] = second
        result[2] = third
        return result
    }

    static func Types4(
        first: Type,
        second: Type,
        third: Type,
        fourth: Type): Type[] {
        result := new Type[](4)
        result[0] = first
        result[1] = second
        result[2] = third
        result[3] = fourth
        return result
    }

    static func CanUseConstructorDefault(
        expectedType: Type,
        defaultKind: int,
        defaultText: string,
        bindings: ColumnarFragmentBindings): bool {
        if defaultKind == 46 {
            return !expectedType.get_IsValueType()
        }
        if defaultKind == 44 || defaultKind == 45 {
            return expectedType == typeof(bool)
        }
        if defaultKind == 1 {
            value := 0
            return expectedType == typeof(int)
                && Int32.TryParse(defaultText, out value)
        }
        if defaultKind == 4 {
            return expectedType == typeof(string)
        }
        if defaultKind != 1000 {
            return false
        }

        stringValue := ""
        intValue := 0
        return TryResolveStringEnumDefault(
                expectedType, defaultText, bindings, out stringValue)
            || TryResolveNumericEnumDefault(
                expectedType, defaultText, bindings, out intValue)
    }

    static func TryAppendConstructorDefault(
        plan: ColumnarCodePlan,
        expectedType: Type,
        defaultKind: int,
        defaultText: string,
        bindings: ColumnarFragmentBindings): bool {
        if !CanUseConstructorDefault(
                expectedType, defaultKind, defaultText, bindings) {
            return false
        }
        if defaultKind == 46 {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.Ldnull())
            return true
        }
        if defaultKind == 44 {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.LdcI4_1())
            return true
        }
        if defaultKind == 45 {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.LdcI4_0())
            return true
        }
        if defaultKind == 1 {
            intValue := 0
            if !Int32.TryParse(defaultText, out intValue) {
                return false
            }
            valueIndex := plan.AddInt32(intValue)
            plan.AppendInt32Instruction(
                ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }
        if defaultKind == 4 {
            valueIndex := plan.AddString(
                StringLiteralDecoder.Decode(defaultText))
            plan.AppendStringInstruction(
                ColumnarCodePlanContract.Ldstr(), valueIndex)
            return true
        }

        stringValue := ""
        if TryResolveStringEnumDefault(
                expectedType, defaultText, bindings, out stringValue) {
            valueIndex := plan.AddString(stringValue)
            plan.AppendStringInstruction(
                ColumnarCodePlanContract.Ldstr(), valueIndex)
            return true
        }
        intValue := 0
        if TryResolveNumericEnumDefault(
                expectedType, defaultText, bindings, out intValue) {
            valueIndex := plan.AddInt32(intValue)
            plan.AppendInt32Instruction(
                ColumnarCodePlanContract.LdcI4(), valueIndex)
            return true
        }
        return false
    }

    static func TryResolveStringEnumDefault(
        expectedType: Type,
        defaultText: string,
        bindings: ColumnarFragmentBindings,
        out value: string): bool {
        value = ""
        ownerName := ""
        memberName := ""
        if !TrySplitDefaultMember(
                defaultText, out ownerName, out memberName)
            || !bindings.Enums.ContainsKey(ownerName) {
            return false
        }
        definition := bindings.Enums[ownerName]
        constants := definition.StringConstants
        if constants == null
            || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                definition.EnumType, expectedType)
            || !constants.ContainsKey(memberName) {
            return false
        }
        value = constants[memberName]
        return true
    }

    static func TryResolveNumericEnumDefault(
        expectedType: Type,
        defaultText: string,
        bindings: ColumnarFragmentBindings,
        out value: int): bool {
        value = 0
        ownerName := ""
        memberName := ""
        if !TrySplitDefaultMember(
                defaultText, out ownerName, out memberName) {
            return false
        }
        if bindings.Enums.ContainsKey(ownerName) {
            definition := bindings.Enums[ownerName]
            if ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                    definition.EnumType, expectedType)
                && definition.Constants.ContainsKey(memberName) {
                value = definition.Constants[memberName]
                return true
            }
        }

        if expectedType is TypeBuilder
            || expectedType.GetType().FullName
                == "System.Reflection.Emit.EnumBuilder"
            || !expectedType.get_IsEnum()
            || (expectedType.Name != ownerName
                && expectedType.FullName != ownerName)
            || !Enum.IsDefined(expectedType, memberName) {
            return false
        }
        value = Convert.ToInt32(
            Enum.Parse(expectedType, memberName),
            CultureInfo.InvariantCulture)
        return true
    }

    static func TrySplitDefaultMember(
        text: string,
        out ownerName: string,
        out memberName: string): bool {
        ownerName = ""
        memberName = ""
        if text == null {
            return false
        }
        separator := text.LastIndexOf(".", StringComparison.Ordinal)
        if separator <= 0 || separator + 1 >= text.Length {
            return false
        }
        ownerName = text.Substring(0, separator)
        memberName = text.Substring(separator + 1)
        return ownerName.Length > 0 && memberName.Length > 0
    }

    static func AppendArrayElementStore(
        plan: ColumnarCodePlan,
        elementType: Type) {
        if elementType == typeof(bool) {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.StelemI1())
        } else if elementType == typeof(char) {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.StelemI2())
        } else if elementType == typeof(int)
            || elementType == typeof(uint) {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.StelemI4())
        } else if elementType == typeof(long)
            || elementType == typeof(ulong) {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.StelemI8())
        } else if elementType == typeof(float) {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.StelemR4())
        } else if elementType == typeof(double) {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.StelemR8())
        } else if !elementType.get_IsValueType()
            && !elementType.get_IsGenericParameter() {
            plan.AppendInstructionWithoutOperand(
                ColumnarCodePlanContract.StelemRef())
        } else {
            typeIndex := plan.AddType(elementType)
            plan.AppendTypeInstruction(
                ColumnarCodePlanContract.Stelem(), typeIndex)
        }
    }

    static func IsSupportedArrayElement(
        elementType: Type,
        bindings: ColumnarFragmentBindings): bool {
        if elementType == null || elementType.FullName == "System.Void"
            || elementType.get_IsByRef() || elementType.get_IsPointer() {
            return false
        }
        return ColumnarTypeOfPlanner.IsSupportedElementType(
            elementType, bindings)
    }

    static func TryResolveExactType(
        nodes: ColumnarNodeTable,
        canonical: string,
        bindings: ColumnarFragmentBindings,
        out resultType: Type): bool {
        resultType = typeof(object)
        if VisibleTypeParameterHandleIsMissing(
                nodes, canonical, bindings) {
            return false
        }
        scope := nodes.BindingScope
        return scope != null
            && scope.TryResolveExactExplicitType(
                canonical, bindings, out resultType)
    }

    // The immutable node context records the lexical type-parameter names even when a corrupt
    // mechanical caller omits their live handles. Such a spelling is blocked; exact scope must
    // never reinterpret it as a source or runtime type with the same name.
    static func VisibleTypeParameterHandleIsMissing(
        nodes: ColumnarNodeTable,
        canonical: string,
        bindings: ColumnarFragmentBindings): bool {
        baseName := canonical
        while baseName.EndsWith("[]", StringComparison.Ordinal) {
            baseName = baseName.Substring(0, baseName.Length - 2)
        }
        index := 0
        while index < nodes.VisibleTypeParameterNames.Length {
            if nodes.VisibleTypeParameterNames[index] == baseName {
                parameterType := typeof(object)
                return !bindings.TryGetTypeParameter(
                    baseName, out parameterType)
            }
            index += 1
        }
        return false
    }

    static func TryFindSourceDefinition(
        targetType: Type,
        bindings: ColumnarFragmentBindings,
        out selected: ColumnarStructDef?): bool {
        selected = null
        for candidate in bindings.SourceTypeDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException(
                    "Construction source-type facts cannot contain null values.")
            }
            candidateType: Type = candidate.Builder
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                    candidateType, targetType) {
                continue
            }
            if selected != null && !SameObject(selected, candidate) {
                throw new InvalidOperationException(
                    "One exact construction target cannot map to two source definitions.")
            }
            selected = candidate
        }
        return selected != null
    }

    static func IsSourceUnionType(
        targetType: Type,
        bindings: ColumnarFragmentBindings): bool {
        selected: ColumnarUnionDef? = null
        for candidate in bindings.SourceUnionDefinitions {
            if candidate == null || candidate.Base == null {
                throw new InvalidOperationException(
                    "Construction source-union facts cannot contain null values.")
            }
            candidateType: Type = candidate.Base
            if !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(
                    candidateType, targetType) {
                continue
            }
            if selected != null && !SameObject(selected, candidate) {
                throw new InvalidOperationException(
                    "One exact construction target cannot map to two source unions.")
            }
            selected = candidate
        }
        return selected != null
    }

    public static func SameObject(first: object, second: object): bool {
        return Object.ReferenceEquals(first, second)
    }

    static func ValueSyntaxIsAdmitted(
        nodes: ColumnarNodeTable,
        node: int,
        depth: int): bool {
        if MayPlanRoot(nodes, node) {
            return IsAdmittedValueSyntax(nodes, node, depth)
        }
        return ColumnarDirectCallPlanner.IsAdmittedValueSyntax(
            nodes, node, depth)
    }

    // Sized arrays in this slice deliberately admit only an exact simple element spelling, with
    // any number of surrounding array suffixes. Other type families still belong to the legacy
    // whole-subtree planner because they may require target context or richer type
    // binding. A malformed node in the admitted simple/repeated-array family remains terminal.
    //  1: admitted exact syntax, 0: excluded well-formed family, -1: malformed admitted family.
    static func ClassifyExactSizedArrayElementSyntax(
        nodes: ColumnarNodeTable,
        node: int,
        depth: int): int {
        if nodes == null || depth > 200
            || node < 0 || node >= nodes.Kinds.Length {
            return -1
        }

        kind := nodes.Kind(node)
        if kind == 0 {
            return nodes.ChildCount(node) == 0 ? 1 : -1
        }
        if kind == 2 {
            if nodes.ChildCount(node) != 1 {
                return -1
            }
            return ClassifyExactSizedArrayElementSyntax(
                nodes, nodes.Child(node, 0), depth + 1)
        }
        return 0
    }

    static func TryBuildTypeCanonical(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        depth: int,
        out canonical: string): bool {
        canonical = ""
        if depth > 200 || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        kind := nodes.Kind(node)
        if kind == 0 {
            if nodes.ChildCount(node) != 0 {
                return false
            }
            canonical = nodes.Text(source, node)
            return canonical.Length > 0
        }
        if kind == 1 {
            childCount := nodes.ChildCount(node)
            name := nodes.Text(source, node)
            if childCount == 0 || name.Length == 0 {
                return false
            }
            builder := new StringBuilder()
            builder.Append(name)
            builder.Append("<")
            index := 0
            while index < childCount {
                if index > 0 { builder.Append(",") }
                argument := ""
                if !TryBuildTypeCanonical(
                        nodes, source, nodes.Child(node, index), depth + 1,
                        out argument) {
                    return false
                }
                builder.Append(argument)
                index += 1
            }
            builder.Append(">")
            canonical = builder.ToString()
            return true
        }
        if kind == 2 || kind == 3 {
            if nodes.ChildCount(node) != 1 {
                return false
            }
            element := ""
            if !TryBuildTypeCanonical(
                    nodes, source, nodes.Child(node, 0), depth + 1,
                    out element) {
                return false
            }
            canonical = element + (kind == 2 ? "[]" : "?")
            return true
        }
        if kind == 4 {
            childCount := nodes.ChildCount(node)
            if childCount != 2 {
                return false
            }
            builder := new StringBuilder()
            index := 0
            while index < childCount {
                if index > 0 { builder.Append("|") }
                arm := ""
                if !TryBuildTypeCanonical(
                        nodes, source, nodes.Child(node, index), depth + 1,
                        out arm) {
                    return false
                }
                builder.Append(arm)
                index += 1
            }
            canonical = builder.ToString()
            return true
        }
        if kind == 6 {
            childCount := nodes.ChildCount(node)
            if childCount < 2 || childCount > 7 {
                return false
            }
            builder := new StringBuilder()
            builder.Append("ValueTuple<")
            index := 0
            while index < childCount {
                if index > 0 { builder.Append(",") }
                element := ""
                if !TryBuildTypeCanonical(
                        nodes, source, nodes.Child(node, index), depth + 1,
                        out element) {
                    return false
                }
                builder.Append(element)
                index += 1
            }
            builder.Append(">")
            canonical = builder.ToString()
            return true
        }
        if kind == 7 && nodes.ChildCount(node) == 1 {
            return TryBuildTypeCanonical(
                nodes, source, nodes.Child(node, 0), depth + 1,
                out canonical)
        }
        return false
    }

    static func ValidateOwnershipBoundary(
        ownership: ColumnarDirectCallOwnership,
        legacyWholeSubtreePlanning: bool) {
        if legacyWholeSubtreePlanning
            && ownership != ColumnarDirectCallOwnership.NotOwned {
            throw new InvalidOperationException(
                "Legacy whole-subtree construction planning requires NotOwned.")
        }
    }

    static func UnwrapParentheses(
        nodes: ColumnarNodeTable,
        node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length
            && nodes.Kind(node)
                == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }
            node = nodes.Child(node, 0)
            depth += 1
        }
        return node
    }

    static func ValidateInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || plan == null
            || bindings.SourceTypeDefinitions == null
            || bindings.SourceUnionDefinitions == null
            || bindings.Enums == null {
            throw new InvalidOperationException(
                "Construction planning inputs and binding facts cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException(
                "Construction planning received an invalid root node index.")
        }
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException(
                "Planned construction expression has no result type.")
        }
        return resultType
    }
}
