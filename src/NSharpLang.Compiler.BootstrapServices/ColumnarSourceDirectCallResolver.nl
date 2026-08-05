namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Source classification is deliberately part of the result. Once an explicit receiver or
// owner is known to be a source type, a missing or unusable source method is terminal: runtime
// reflection must not bind a same-spelled external member through that source shadow.
enum ColumnarSourceDirectCallStatus {
    NotSourceType,
    Rejected,
    Selected
}

enum ColumnarSourceDirectCallDispatch {
    None,
    Call,
    CallVirtual
}

enum ColumnarDirectCallArgumentFlow {
    None,
    Identity,
    ImplicitNumeric,
    Reference,
    Boxing,
    Null,
    Nullable,
    Constructed,
    UserImplicit
}

// Syntax-sensitive facts that cannot be reconstructed from a CLR Type alone. In particular,
// an unsuffixed integer constant may adopt a small/unsigned declaration target while an int
// variable with the same runtime value may not. Arrays are positional and always match the
// argument-type array supplied to selection.
class ColumnarDirectCallArgumentFacts {
    IsUnsuffixedIntegerLiteral: bool[]
    IsNegativeIntegerLiteral: bool[]
    IntegerLiteralValues: long[]
    IsNullLiteral: bool[]
    SourceTypeDefinitions: IEnumerable<ColumnarStructDef>

    constructor(isUnsuffixedIntegerLiteral: bool[], isNegativeIntegerLiteral: bool[], integerLiteralValues: long[]) {
        if isUnsuffixedIntegerLiteral == null || isNegativeIntegerLiteral == null || integerLiteralValues == null || isUnsuffixedIntegerLiteral.Length != isNegativeIntegerLiteral.Length || isUnsuffixedIntegerLiteral.Length != integerLiteralValues.Length {
            throw new InvalidOperationException("Direct-call argument syntax facts must be non-null and positional.")
        }

        IsUnsuffixedIntegerLiteral = isUnsuffixedIntegerLiteral
        IsNegativeIntegerLiteral = isNegativeIntegerLiteral
        IntegerLiteralValues = integerLiteralValues
        IsNullLiteral = new bool[](isUnsuffixedIntegerLiteral.Length)
        SourceTypeDefinitions = new List<ColumnarStructDef>()
    }

    static func Empty(argumentCount: int): ColumnarDirectCallArgumentFacts {
        if argumentCount < 0 {
            throw new InvalidOperationException("Direct-call argument fact count cannot be negative.")
        }

        return new ColumnarDirectCallArgumentFacts(new bool[](argumentCount), new bool[](argumentCount), new long[](argumentCount))
    }
}

// An immutable-by-convention snapshot of one exact source method selection. ParameterTypes is
// copied from declaration facts (and closed when required), so later declaration-map mutations
// cannot silently change the signature that a planner selected.
class ColumnarSourceDirectCallSelection {
    Status: ColumnarSourceDirectCallStatus
    Dispatch: ColumnarSourceDirectCallDispatch
    SourceDefinition: ColumnarStructDef?
    ReceiverType: Type
    DeclaringType: Type
    Method: MethodInfo?
    ParameterTypes: Type[]
    ReturnType: Type
    ReceiverIsReference: bool
    IsStatic: bool
    IsAbstract: bool

    IsSourceType: bool => Status != ColumnarSourceDirectCallStatus.NotSourceType
    IsSelected: bool => Status == ColumnarSourceDirectCallStatus.Selected

    constructor(status: ColumnarSourceDirectCallStatus, dispatch: ColumnarSourceDirectCallDispatch, sourceDefinition: ColumnarStructDef?, receiverType: Type, declaringType: Type, method: MethodInfo?, parameterTypes: Type[], returnType: Type, receiverIsReference: bool, isStatic: bool, isAbstract: bool) {
        if receiverType == null || declaringType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Source direct-call selection facts cannot be null.")
        }

        if status == ColumnarSourceDirectCallStatus.Selected {
            if sourceDefinition == null || method == null || dispatch == ColumnarSourceDirectCallDispatch.None {
                throw new InvalidOperationException("A selected source direct call requires exact source, method, and dispatch facts.")
            }
        } else if method != null || dispatch != ColumnarSourceDirectCallDispatch.None {
            throw new InvalidOperationException("An unselected source direct call cannot carry executable method facts.")
        }

        Status = status
        Dispatch = dispatch
        SourceDefinition = sourceDefinition
        ReceiverType = receiverType
        DeclaringType = declaringType
        Method = method
        ParameterTypes = parameterTypes
        ReturnType = returnType
        ReceiverIsReference = receiverIsReference
        IsStatic = isStatic
        IsAbstract = isAbstract
    }
}

// Pure method selection for fixed-arity, non-generic source calls. This layer does not inspect
// syntax, emit arguments, mutate a code plan, or fall back to runtime members. Its only job is to
// classify a source receiver/owner and select one exact MethodBuilder identity and closed
// signature according to the legacy source hiding order.
class ColumnarSourceDirectCallResolver {

    // Visibility is intentionally separate from callability. A private, generic, params,
    // ref/out, varargs, abstract-invalid, or type-incompatible declaration still occupies this
    // source name/arity and therefore remains terminal for later planner ownership.
    static func HasInstanceDeclarationAtArity(root: ColumnarStructDef, memberName: string, argumentCount: int): bool {
        ValidateDeclarationQuery(root, memberName, argumentCount)
        ValidateDefinitionGraph(root)
        if memberName.Length == 0 {
            return false
        }

        return HasInstanceDeclarationInChain(root, memberName, argumentCount)
    }

    // Extension fallback remains available only when the source hierarchy has no declaration
    // with this name. A same-named source declaration at another arity still owns the lookup
    // tier and must not leak into runtime/extension binding.
    static func HasInstanceDeclaration(root: ColumnarStructDef, memberName: string): bool {
        ValidateDeclarationQuery(root, memberName, 0)
        ValidateDefinitionGraph(root)
        if memberName.Length == 0 {
            return false
        }

        return HasInstanceDeclarationInChain(root, memberName)
    }

    static func HasStaticDeclarationAtArity(root: ColumnarStructDef, memberName: string, argumentCount: int): bool {
        ValidateDeclarationQuery(root, memberName, argumentCount)
        ValidateDefinitionGraph(root)
        if memberName.Length == 0 {
            return false
        }

        return HasStaticDeclarationInChain(root, memberName, argumentCount)
    }

    // These declarations belong to later call owners. Their presence must keep the planner from
    // turning a valid generic, params, ref/out, extension, or varargs call into a terminal reject.
    static func HasExcludedInstanceDeclaration(root: ColumnarStructDef, memberName: string): bool {
        ValidateDeclarationQuery(root, memberName, 0)
        ValidateDefinitionGraph(root)
        if memberName.Length == 0 {
            return false
        }

        return HasExcludedInstanceDeclarationInChain(root, memberName)
    }

    static func HasExcludedStaticDeclaration(root: ColumnarStructDef, memberName: string): bool {
        ValidateDeclarationQuery(root, memberName, 0)
        ValidateDefinitionGraph(root)
        if memberName.Length == 0 {
            return false
        }

        return HasExcludedStaticDeclarationInChain(root, memberName)
    }

    static func IsExcludedInstanceDefinition(definition: ColumnarInstanceMethodDef): bool {
        if definition == null {
            throw new InvalidOperationException("Excluded source instance-method facts cannot be null.")
        }

        return IsExcludedInstanceMethod(definition)
    }

    static func IsExcludedStaticDefinition(definition: ColumnarStaticMethodDef): bool {
        if definition == null {
            throw new InvalidOperationException("Excluded source static-method facts cannot be null.")
        }

        return IsExcludedStaticMethod(definition)
    }

    static func ExcludedInstanceDefinitionCanOwnArity(definition: ColumnarInstanceMethodDef, argumentCount: int): bool {
        if definition == null || argumentCount < 0 {
            throw new InvalidOperationException("Excluded source instance-method arity facts must be valid.")
        }

        return IsExcludedInstanceMethod(definition) && ExcludedShapeCanOwnArity(definition.Builder, definition.ParamTypes, definition.ParamModifierKinds, argumentCount)
    }

    static func ExcludedStaticDefinitionCanOwnArity(definition: ColumnarStaticMethodDef, argumentCount: int): bool {
        if definition == null || argumentCount < 0 {
            throw new InvalidOperationException("Excluded source static-method arity facts must be valid.")
        }

        return IsExcludedStaticMethod(definition) && ExcludedShapeCanOwnArity(definition.Builder, definition.ParamTypes, definition.ParamModifierKinds, argumentCount)
    }

    static func ResolveExplicitInstance(receiverType: Type, memberName: string, argumentTypes: Type[], sourceDefinitions: IEnumerable<ColumnarStructDef>): ColumnarSourceDirectCallSelection {
        return ResolveExplicitInstance(receiverType, memberName, argumentTypes, sourceDefinitions, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length))
    }

    static func ResolveExplicitInstance(receiverType: Type, memberName: string, argumentTypes: Type[], sourceDefinitions: IEnumerable<ColumnarStructDef>, argumentFacts: ColumnarDirectCallArgumentFacts?): ColumnarSourceDirectCallSelection {
        ValidateExplicitInputs(receiverType, memberName, argumentTypes, sourceDefinitions)
        facts := NormalizeArgumentFacts(argumentTypes, argumentFacts)

        definition: ColumnarStructDef? = null
        closed := false
        if !TryClassifySourceType(receiverType, sourceDefinitions, out definition, out closed) || definition == null {
            return NotSource()
        }

        return ResolveKnownInstance(definition, receiverType, closed, memberName, argumentTypes, facts)
    }

    static func ResolveImplicitInstance(currentDefinition: ColumnarStructDef?, receiverType: Type, memberName: string, argumentTypes: Type[]): ColumnarSourceDirectCallSelection {
        return ResolveImplicitInstance(currentDefinition, receiverType, memberName, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length))
    }

    static func ResolveImplicitInstance(currentDefinition: ColumnarStructDef?, receiverType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts?): ColumnarSourceDirectCallSelection {
        ValidateKnownInputs(receiverType, memberName, argumentTypes)
        facts := NormalizeArgumentFacts(argumentTypes, argumentFacts)
        if currentDefinition == null {
            return NotSource()
        }

        closed := ExactSourceTypeMatch(currentDefinition, receiverType)
        declaredType: Type = currentDefinition.Builder
        if declaredType != receiverType {
            if !closed {
                throw new InvalidOperationException("Implicit source instance facts do not match the exact receiver type.")
            }
        }

        return ResolveKnownInstance(currentDefinition, receiverType, closed, memberName, argumentTypes, facts)
    }

    static func ResolveExplicitStatic(ownerType: Type, memberName: string, argumentTypes: Type[], sourceDefinitions: IEnumerable<ColumnarStructDef>): ColumnarSourceDirectCallSelection {
        return ResolveExplicitStatic(ownerType, memberName, argumentTypes, sourceDefinitions, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length))
    }

    static func ResolveExplicitStatic(ownerType: Type, memberName: string, argumentTypes: Type[], sourceDefinitions: IEnumerable<ColumnarStructDef>, argumentFacts: ColumnarDirectCallArgumentFacts?): ColumnarSourceDirectCallSelection {
        ValidateExplicitInputs(ownerType, memberName, argumentTypes, sourceDefinitions)
        facts := NormalizeArgumentFacts(argumentTypes, argumentFacts)

        definition: ColumnarStructDef? = null
        closed := false
        if !TryClassifySourceType(ownerType, sourceDefinitions, out definition, out closed) || definition == null {
            return NotSource()
        }

        return ResolveKnownStatic(definition, ownerType, closed, memberName, argumentTypes, facts)
    }

    // Explicit static syntax must classify its source spelling before resolving a runtime type.
    // A keyed binding layer supplies that already-classified definition here; null means that the
    // spelling was not a source owner. This keeps source aliases and same-named BCL types from
    // being reconstructed from CLR Type.Name.
    static func ResolveClassifiedStatic(sourceDefinition: ColumnarStructDef?, ownerType: Type, memberName: string, argumentTypes: Type[]): ColumnarSourceDirectCallSelection {
        return ResolveClassifiedStatic(sourceDefinition, ownerType, memberName, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length))
    }

    static func ResolveClassifiedStatic(sourceDefinition: ColumnarStructDef?, ownerType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts?): ColumnarSourceDirectCallSelection {
        ValidateKnownInputs(ownerType, memberName, argumentTypes)
        facts := NormalizeArgumentFacts(argumentTypes, argumentFacts)
        if sourceDefinition == null {
            return NotSource()
        }

        closed := ExactSourceTypeMatch(sourceDefinition, ownerType)
        declaredType: Type = sourceDefinition.Builder
        if declaredType != ownerType {
            if !closed {
                throw new InvalidOperationException("Classified source static facts do not match the exact owner type.")
            }
        }

        return ResolveKnownStatic(sourceDefinition, ownerType, closed, memberName, argumentTypes, facts)
    }

    static func ResolveImplicitStatic(enclosingDefinition: ColumnarStructDef?, ownerType: Type, memberName: string, argumentTypes: Type[]): ColumnarSourceDirectCallSelection {
        return ResolveImplicitStatic(enclosingDefinition, ownerType, memberName, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length))
    }

    static func ResolveImplicitStatic(enclosingDefinition: ColumnarStructDef?, ownerType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts?): ColumnarSourceDirectCallSelection {
        return ResolveClassifiedStatic(enclosingDefinition, ownerType, memberName, argumentTypes, argumentFacts)
    }

    static func ResolveKnownInstance(root: ColumnarStructDef, receiverType: Type, closed: bool, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarSourceDirectCallSelection {
        ValidateDefinitionGraph(root)
        ValidateReceiverShape(root, receiverType)
        if memberName.Length == 0 {
            return Rejected(root, receiverType, false)
        }

        selected := closed ? SelectLocalInstance(root, root, receiverType, true, memberName, argumentTypes, argumentFacts) : SelectInstanceChain(root, root, receiverType, memberName, argumentTypes, argumentFacts)

        if selected.Status == ColumnarSourceDirectCallStatus.NotSourceType {
            return Rejected(root, receiverType, false)
        }

        return selected
    }

    static func ResolveKnownStatic(root: ColumnarStructDef, ownerType: Type, closed: bool, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarSourceDirectCallSelection {
        ValidateDefinitionGraph(root)
        ValidateReceiverShape(root, ownerType)
        if memberName.Length == 0 {
            return Rejected(root, ownerType, true)
        }

        selected := closed ? SelectLocalStatic(root, root, ownerType, true, memberName, argumentTypes, argumentFacts) : SelectStaticChain(root, root, ownerType, memberName, argumentTypes, argumentFacts)

        if selected.Status == ColumnarSourceDirectCallStatus.NotSourceType {
            return Rejected(root, ownerType, true)
        }

        return selected
    }

    // Instance declarations hide by invocation arity. Once a definition has a same-arity fixed
    // declaration, or an excluded params/varargs shape that can accept this argument count, an
    // inaccessible, excluded, type-incompatible, or ambiguous local set blocks every base match.
    static func SelectInstanceChain(root: ColumnarStructDef, current: ColumnarStructDef, receiverType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarSourceDirectCallSelection {
        local := SelectLocalInstance(root, current, receiverType, false, memberName, argumentTypes, argumentFacts)

        if local.Status != ColumnarSourceDirectCallStatus.NotSourceType {
            return local
        }

        if current.IsInterface {
            baseIndex := 0
            while baseIndex < current.InterfaceBases.Count {
                inherited := SelectInstanceChain(root, current.InterfaceBases[baseIndex], receiverType, memberName, argumentTypes, argumentFacts)

                if inherited.Status != ColumnarSourceDirectCallStatus.NotSourceType {
                    return inherited
                }

                baseIndex += 1
            }
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return SelectInstanceChain(root, baseDefinition, receiverType, memberName, argumentTypes, argumentFacts)
        }

        return NoDeclaration()
    }

    static func SelectLocalInstance(root: ColumnarStructDef, owner: ColumnarStructDef, receiverType: Type, closed: bool, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarSourceDirectCallSelection {
        overloads := new List<ColumnarInstanceMethodDef>()
        if !owner.MethodOverloads.TryGetValue(memberName, out overloads) {
            return NoDeclaration()
        }

        if overloads == null {
            throw new InvalidOperationException("Source instance-method overload facts cannot be null.")
        }

        hadArityMatch := false
        hadExcludedShape := false
        compatibleCount := 0
        bestScore := -1
        selected: ColumnarInstanceMethodDef? = null
        selectedParameters := new Type[](0)
        index := 0
        while index < overloads.Count {
            candidate := overloads[index]
            ValidateInstanceMethodFact(owner, memberName, candidate)
            if IsExcludedInstanceMethod(candidate) && ExcludedShapeCanOwnArity(candidate.Builder, candidate.ParamTypes, candidate.ParamModifierKinds, argumentTypes.Length) {
                hadExcludedShape = true
            }

            if candidate.ParamTypes.Length == argumentTypes.Length {
                hadArityMatch = true
                if IsCallableInstanceMethod(root, candidate) {
                    parameters := ResolveParameterTypes(candidate.ParamTypes, receiverType, closed)

                    score := ArgumentsScoreWithFacts(parameters, argumentTypes, argumentFacts)
                    if score > bestScore {
                        bestScore = score
                        compatibleCount = 1
                        selected = candidate
                        selectedParameters = parameters
                    } else if score >= 0 && score == bestScore {
                        compatibleCount += 1
                    }
                }
            }

            index += 1
        }

        // Params expansion and varargs can own this invocation even though their raw CLR
        // parameter count differs. Keep that nearer declaration set terminal instead of
        // leaking through to a fixed base overload.
        if !hadArityMatch && hadExcludedShape {
            return Rejected(owner, receiverType, false)
        }

        if !hadArityMatch {
            return NoDeclaration()
        }

        // An exact non-generic match wins the legacy mixed set. At every weaker tier an
        // excluded generic/params/by-ref/varargs candidate may bind more specifically, so leave
        // the whole set to its later owner instead of guessing from the fixed candidates alone.
        if compatibleCount != 1 || selected == null || hadExcludedShape && bestScore < argumentTypes.Length * 8 {
            return Rejected(owner, receiverType, false)
        }

        return SelectedInstance(root, owner, receiverType, closed, selected, selectedParameters)
    }

    // Static lookup preserves the legacy distinction: a nearer same-name set that cannot accept
    // this argument count does not hide a matching base overload, but a nearer fixed or excluded
    // declaration that can own the invocation is terminal.
    static func SelectStaticChain(root: ColumnarStructDef, current: ColumnarStructDef, ownerType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarSourceDirectCallSelection {
        local := SelectLocalStatic(root, current, ownerType, false, memberName, argumentTypes, argumentFacts)

        if local.Status != ColumnarSourceDirectCallStatus.NotSourceType {
            return local
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return SelectStaticChain(root, baseDefinition, ownerType, memberName, argumentTypes, argumentFacts)
        }

        return NoDeclaration()
    }

    static func SelectLocalStatic(root: ColumnarStructDef, owner: ColumnarStructDef, ownerType: Type, closed: bool, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarSourceDirectCallSelection {
        overloads := new List<ColumnarStaticMethodDef>()
        if !owner.StaticMethods.TryGetValue(memberName, out overloads) {
            return NoDeclaration()
        }

        if overloads == null {
            throw new InvalidOperationException("Source static-method overload facts cannot be null.")
        }

        hadArityMatch := false
        hadExcludedShape := false
        compatibleCount := 0
        bestScore := -1
        selected: ColumnarStaticMethodDef? = null
        selectedParameters := new Type[](0)
        index := 0
        while index < overloads.Count {
            candidate := overloads[index]
            ValidateStaticMethodFact(owner, memberName, candidate)
            if IsExcludedStaticMethod(candidate) && ExcludedShapeCanOwnArity(candidate.Builder, candidate.ParamTypes, candidate.ParamModifierKinds, argumentTypes.Length) {
                hadExcludedShape = true
            }

            if candidate.ParamTypes.Length == argumentTypes.Length {
                hadArityMatch = true
                if IsCallableStaticMethod(candidate) {
                    parameters := ResolveParameterTypes(candidate.ParamTypes, ownerType, closed)

                    score := ArgumentsScoreWithFacts(parameters, argumentTypes, argumentFacts)
                    if score > bestScore {
                        bestScore = score
                        compatibleCount = 1
                        selected = candidate
                        selectedParameters = parameters
                    } else if score >= 0 && score == bestScore {
                        compatibleCount += 1
                    }
                }
            }

            index += 1
        }

        // Params expansion and varargs can own this invocation even though their raw CLR
        // parameter count differs. Keep that nearer declaration set terminal instead of
        // leaking through to a fixed base overload.
        if !hadArityMatch && hadExcludedShape {
            return Rejected(owner, ownerType, true)
        }

        if !hadArityMatch {
            return NoDeclaration()
        }

        if compatibleCount != 1 || selected == null || hadExcludedShape && bestScore < argumentTypes.Length * 8 {
            return Rejected(owner, ownerType, true)
        }

        return SelectedStatic(root, owner, ownerType, closed, selected, selectedParameters)
    }

    static func SelectedInstance(root: ColumnarStructDef, owner: ColumnarStructDef, receiverType: Type, closed: bool, definition: ColumnarInstanceMethodDef, parameterTypes: Type[]): ColumnarSourceDirectCallSelection {
        method: MethodInfo = definition.Builder
        declaringType: Type = owner.Builder
        returnType := definition.ReturnType
        if closed {
            rebound := TypeBuilder.GetMethod(receiverType, method)
            if rebound == null {
                throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact closed source instance method.")
            }

            method = rebound
            declaringType = receiverType
            returnType = SubstituteTypeArguments(definition.ReturnType, receiverType.GetGenericArguments())
        }

        return new ColumnarSourceDirectCallSelection(ColumnarSourceDirectCallStatus.Selected, root.IsReference ? ColumnarSourceDirectCallDispatch.CallVirtual : ColumnarSourceDirectCallDispatch.Call, owner, receiverType, declaringType, method, parameterTypes, returnType, root.IsReference, false, method.get_IsAbstract())
    }

    static func SelectedStatic(root: ColumnarStructDef, owner: ColumnarStructDef, ownerType: Type, closed: bool, definition: ColumnarStaticMethodDef, parameterTypes: Type[]): ColumnarSourceDirectCallSelection {
        method: MethodInfo = definition.Builder
        declaringType: Type = owner.Builder
        returnType := definition.ReturnType
        if closed {
            rebound := TypeBuilder.GetMethod(ownerType, method)
            if rebound == null {
                throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact closed source static method.")
            }

            method = rebound
            declaringType = ownerType
            returnType = SubstituteTypeArguments(definition.ReturnType, ownerType.GetGenericArguments())
        }

        return new ColumnarSourceDirectCallSelection(ColumnarSourceDirectCallStatus.Selected, ColumnarSourceDirectCallDispatch.Call, owner, ownerType, declaringType, method, parameterTypes, returnType, root.IsReference, true, false)
    }

    static func IsCallableInstanceMethod(receiverDefinition: ColumnarStructDef, definition: ColumnarInstanceMethodDef): bool {
        method: MethodInfo = definition.Builder
        if !method.get_IsPublic() || method.get_IsGenericMethod() || IsVarArgs(method) || method.get_IsAbstract() && !receiverDefinition.IsReference || HasUnsupportedModifiers(definition.ParamModifierKinds) || !HasSupportedSignature(definition.ParamTypes, definition.ReturnType) {
            return false
        }

        return true
    }

    static func IsCallableStaticMethod(definition: ColumnarStaticMethodDef): bool {
        method: MethodInfo = definition.Builder
        if !method.get_IsPublic() || method.get_IsAbstract() || method.get_IsGenericMethod() || IsVarArgs(method) || HasUnsupportedModifiers(definition.ParamModifierKinds) || !HasSupportedSignature(definition.ParamTypes, definition.ReturnType) {
            return false
        }

        return true
    }

    static func HasUnsupportedModifiers(modifierKinds: int[]): bool {
        index := 0
        while index < modifierKinds.Length {
            if modifierKinds[index] != 0 {
                return true
            }

            index += 1
        }

        return false
    }

    static func HasSupportedSignature(parameterTypes: Type[], returnType: Type): bool {
        if returnType.get_IsByRef() || returnType.get_IsGenericTypeDefinition() {
            return false
        }

        index := 0
        while index < parameterTypes.Length {
            parameterType := parameterTypes[index]
            if parameterType.get_IsByRef() || parameterType.get_IsGenericTypeDefinition() {
                return false
            }

            index += 1
        }

        return true
    }

    static func IsVarArgs(method: MethodInfo): bool {
        callingConvention := (int)method.get_CallingConvention()
        return (callingConvention & ColumnarCodePlanReflectionContract.VarArgsCallingConventionFlag()) != 0
    }

    static func HasInstanceDeclarationInChain(current: ColumnarStructDef, memberName: string, argumentCount: int): bool {
        overloads := new List<ColumnarInstanceMethodDef>()
        if current.MethodOverloads.TryGetValue(memberName, out overloads) {
            if overloads == null {
                throw new InvalidOperationException("Source instance-method overload facts cannot be null.")
            }

            index := 0
            while index < overloads.Count {
                candidate := overloads[index]
                ValidateInstanceMethodFact(current, memberName, candidate)
                if candidate.ParamTypes.Length == argumentCount {
                    return true
                }

                index += 1
            }
        }

        if current.IsInterface {
            baseIndex := 0
            while baseIndex < current.InterfaceBases.Count {
                if HasInstanceDeclarationInChain(current.InterfaceBases[baseIndex], memberName, argumentCount) {
                    return true
                }

                baseIndex += 1
            }
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return HasInstanceDeclarationInChain(baseDefinition, memberName, argumentCount)
        }

        return false
    }

    static func HasInstanceDeclarationInChain(current: ColumnarStructDef, memberName: string): bool {
        overloads := new List<ColumnarInstanceMethodDef>()
        if current.MethodOverloads.TryGetValue(memberName, out overloads) {
            if overloads == null {
                throw new InvalidOperationException("Source instance-method overload facts cannot be null.")
            }

            index := 0
            while index < overloads.Count {
                ValidateInstanceMethodFact(current, memberName, overloads[index])
                index += 1
            }

            if overloads.Count != 0 {
                return true
            }
        }

        if current.IsInterface {
            baseIndex := 0
            while baseIndex < current.InterfaceBases.Count {
                if HasInstanceDeclarationInChain(current.InterfaceBases[baseIndex], memberName) {
                    return true
                }

                baseIndex += 1
            }
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return HasInstanceDeclarationInChain(baseDefinition, memberName)
        }

        return false
    }

    static func HasStaticDeclarationInChain(current: ColumnarStructDef, memberName: string, argumentCount: int): bool {
        overloads := new List<ColumnarStaticMethodDef>()
        if current.StaticMethods.TryGetValue(memberName, out overloads) {
            if overloads == null {
                throw new InvalidOperationException("Source static-method overload facts cannot be null.")
            }

            index := 0
            while index < overloads.Count {
                candidate := overloads[index]
                ValidateStaticMethodFact(current, memberName, candidate)
                if candidate.ParamTypes.Length == argumentCount {
                    return true
                }

                index += 1
            }
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return HasStaticDeclarationInChain(baseDefinition, memberName, argumentCount)
        }

        return false
    }

    static func HasExcludedInstanceDeclarationInChain(current: ColumnarStructDef, memberName: string): bool {
        overloads := new List<ColumnarInstanceMethodDef>()
        if current.MethodOverloads.TryGetValue(memberName, out overloads) {
            if overloads == null {
                throw new InvalidOperationException("Source instance-method overload facts cannot be null.")
            }

            index := 0
            while index < overloads.Count {
                candidate := overloads[index]
                ValidateInstanceMethodFact(current, memberName, candidate)
                if IsExcludedInstanceMethod(candidate) {
                    return true
                }

                index += 1
            }
        }

        if current.IsInterface {
            baseIndex := 0
            while baseIndex < current.InterfaceBases.Count {
                if HasExcludedInstanceDeclarationInChain(current.InterfaceBases[baseIndex], memberName) {
                    return true
                }

                baseIndex += 1
            }
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return HasExcludedInstanceDeclarationInChain(baseDefinition, memberName)
        }

        return false
    }

    static func HasExcludedStaticDeclarationInChain(current: ColumnarStructDef, memberName: string): bool {
        overloads := new List<ColumnarStaticMethodDef>()
        if current.StaticMethods.TryGetValue(memberName, out overloads) {
            if overloads == null {
                throw new InvalidOperationException("Source static-method overload facts cannot be null.")
            }

            index := 0
            while index < overloads.Count {
                candidate := overloads[index]
                ValidateStaticMethodFact(current, memberName, candidate)
                if IsExcludedStaticMethod(candidate) {
                    return true
                }

                index += 1
            }
        }

        baseDefinition := current.BaseDef
        if baseDefinition != null {
            return HasExcludedStaticDeclarationInChain(baseDefinition, memberName)
        }

        return false
    }

    static func IsExcludedInstanceMethod(definition: ColumnarInstanceMethodDef): bool {
        method: MethodInfo = definition.Builder
        return method.get_IsGenericMethod() || IsVarArgs(method) || HasUnsupportedModifiers(definition.ParamModifierKinds) || HasByRefSignature(definition.ParamTypes, definition.ReturnType)
    }

    static func IsExcludedStaticMethod(definition: ColumnarStaticMethodDef): bool {
        method: MethodInfo = definition.Builder
        return method.get_IsGenericMethod() || IsVarArgs(method) || HasUnsupportedModifiers(definition.ParamModifierKinds) || HasByRefSignature(definition.ParamTypes, definition.ReturnType)
    }

    // Excluded declarations compete only when the legacy call owner could bind the current
    // argument count. Params and varargs accept expansion; generic and by-ref declarations
    // otherwise retain fixed CLR arity. This mirrors ordinary runtime-call classification.
    static func ExcludedShapeCanOwnArity(method: MethodInfo, parameterTypes: Type[], modifierKinds: int[], argumentCount: int): bool {
        if HasParamsModifier(modifierKinds) {
            return argumentCount >= parameterTypes.Length - 1
        }

        if IsVarArgs(method) {
            return argumentCount >= parameterTypes.Length
        }

        return argumentCount == parameterTypes.Length
    }

    static func HasParamsModifier(modifierKinds: int[]): bool {
        index := 0
        while index < modifierKinds.Length {
            if modifierKinds[index] == 3 {
                return true
            }

            index += 1
        }

        return false
    }

    static func HasByRefSignature(parameterTypes: Type[], returnType: Type): bool {
        if returnType.get_IsByRef() {
            return true
        }

        index := 0
        while index < parameterTypes.Length {
            if parameterTypes[index].get_IsByRef() {
                return true
            }

            index += 1
        }

        return false
    }

    static func ArgumentsScore(expected: Type[], actual: Type[]): int {
        return ArgumentsScoreWithFacts(expected, actual, ColumnarDirectCallArgumentFacts.Empty(actual.Length))
    }

    static func ArgumentsScoreWithFacts(expected: Type[], actual: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): int {
        if expected.Length != actual.Length {
            return -1
        }

        ValidateArgumentFacts(actual, argumentFacts)

        score := 0
        index := 0
        while index < expected.Length {
            argumentScore := argumentFacts.IsNullLiteral[index] ? (ColumnarNullableArgumentLowering.CanAdoptNull(expected[index]) ? 4 : -1) : ArgumentFlowScore(expected[index], actual[index], argumentFacts.SourceTypeDefinitions)

            if argumentScore < 0 && argumentFacts.IsUnsuffixedIntegerLiteral[index] && CanAdoptIntegerLiteralArgument(expected[index], argumentFacts.IntegerLiteralValues[index], argumentFacts.IsNegativeIntegerLiteral[index]) {

                // Constant adoption is viable for a sole small/unsigned declaration, but it
                // must rank below the raw Int32 identity so Pick(int) beats Pick(byte) for 1.
                argumentScore = 2
            }

            if argumentScore < 0 {
                return -1
            }

            score += argumentScore
            index += 1
        }

        return score
    }

    static func CanAdoptIntegerLiteralArgument(targetType: Type, value: long, negative: bool): bool {
        if CanAdoptIntegerLiteral(targetType, value, negative) {
            return true
        }

        nullableElement := typeof(int)
        return ColumnarNullableArgumentLowering.TryGetSupportedNullableElement(targetType, out nullableElement) && CanAdoptIntegerLiteral(nullableElement, value, negative)
    }

    static func NormalizeArgumentFacts(argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts?): ColumnarDirectCallArgumentFacts {
        facts := argumentFacts ?? ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length)
        ValidateArgumentFacts(argumentTypes, facts)
        return facts
    }

    static func ValidateArgumentFacts(argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts) {
        if argumentTypes == null || argumentFacts == null || argumentFacts.IsUnsuffixedIntegerLiteral == null || argumentFacts.IsNegativeIntegerLiteral == null || argumentFacts.IntegerLiteralValues == null || argumentFacts.IsNullLiteral == null || argumentFacts.SourceTypeDefinitions == null || argumentFacts.IsUnsuffixedIntegerLiteral.Length != argumentTypes.Length || argumentFacts.IsNegativeIntegerLiteral.Length != argumentTypes.Length || argumentFacts.IntegerLiteralValues.Length != argumentTypes.Length || argumentFacts.IsNullLiteral.Length != argumentTypes.Length {
            throw new InvalidOperationException("Direct-call argument syntax facts must match the argument types.")
        }

        index := 0
        while index < argumentTypes.Length {
            if argumentFacts.IsUnsuffixedIntegerLiteral[index] && (argumentTypes[index] != typeof(int) || argumentFacts.IntegerLiteralValues[index] < -2147483647 || argumentFacts.IntegerLiteralValues[index] > 2147483647) {
                throw new InvalidOperationException("An unsuffixed direct-call integer fact must describe an Int32 literal.")
            }

            if argumentFacts.IsNegativeIntegerLiteral[index] && !argumentFacts.IsUnsuffixedIntegerLiteral[index] {
                throw new InvalidOperationException("A negative direct-call integer fact must describe an integer literal.")
            }

            if argumentFacts.IsUnsuffixedIntegerLiteral[index] && ((argumentFacts.IsNegativeIntegerLiteral[index] && argumentFacts.IntegerLiteralValues[index] > 0) || (!argumentFacts.IsNegativeIntegerLiteral[index] && argumentFacts.IntegerLiteralValues[index] < 0)) {
                throw new InvalidOperationException("Direct-call integer literal signs must match their values.")
            }

            if argumentFacts.IsNullLiteral[index] && (argumentFacts.IsUnsuffixedIntegerLiteral[index] || argumentFacts.IsNegativeIntegerLiteral[index]) {
                throw new InvalidOperationException("A direct-call argument cannot be both null and an integer literal.")
            }

            index += 1
        }
    }

    static func CanAdoptIntegerLiteral(targetType: Type, value: long): bool {
        return CanAdoptIntegerLiteral(targetType, value, false)
    }

    static func CanAdoptIntegerLiteral(targetType: Type, value: long, isNegative: bool): bool {
        if targetType == null {
            throw new InvalidOperationException("Direct-call integer literal target cannot be null.")
        }

        if isNegative || value < 0 {
            if targetType == typeof(byte) || targetType == typeof(ushort) || targetType == typeof(uint) || targetType == typeof(ulong) {
                return false
            }

            if targetType == typeof(sbyte) {
                return value >= -127
            }

            if targetType == typeof(short) {
                return value >= -32767
            }

            return targetType == typeof(long) && value >= -2147483647
        }

        if targetType == typeof(byte) {
            return value <= 255
        }

        if targetType == typeof(sbyte) {
            return value <= 127
        }

        if targetType == typeof(short) {
            return value <= 32767
        }

        if targetType == typeof(ushort) {
            return value <= 65535
        }

        if targetType == typeof(uint) || targetType == typeof(long) || targetType == typeof(ulong) {
            return value <= 2147483647
        }

        return false
    }

    static func CanArgumentFlow(expectedType: Type, actualType: Type): bool {
        return ArgumentFlowScore(expectedType, actualType) >= 0
    }

    static func TryClassifyArgumentFlow(expectedType: Type, actualType: Type, out flow: ColumnarDirectCallArgumentFlow): bool {
        return TryClassifyArgumentFlow(expectedType, actualType, new List<ColumnarStructDef>(), out flow)
    }

    static func TryClassifyArgumentFlow(expectedType: Type, actualType: Type, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, out flow: ColumnarDirectCallArgumentFlow): bool {
        score := ArgumentFlowScore(expectedType, actualType, sourceTypeDefinitions)

        if score == 8 {
            flow = ColumnarDirectCallArgumentFlow.Identity
            return true
        }

        if score == 6 {
            flow = ColumnarDirectCallArgumentFlow.ImplicitNumeric
            return true
        }

        if ColumnarNullableArgumentLowering.CanLiftValue(actualType, expectedType) {
            flow = ColumnarDirectCallArgumentFlow.Nullable
            return true
        }

        if ColumnarDirectCallConstructedConversions.CanConvert(expectedType, actualType) {
            flow = ColumnarDirectCallArgumentFlow.Constructed
            return true
        }

        referenceFlow := ColumnarDirectCallArgumentFlow.None
        if TryClassifyBuiltInReferenceFlow(expectedType, actualType, sourceTypeDefinitions, out referenceFlow) {
            flow = referenceFlow
            return true
        }

        implicitConversion := ColumnarSourceImplicitConversionResolver.ResolveExact(actualType, expectedType, sourceTypeDefinitions)

        if implicitConversion.IsSelected {
            flow = ColumnarDirectCallArgumentFlow.UserImplicit
            return true
        }

        flow = ColumnarDirectCallArgumentFlow.None
        return false
    }

    static func ArgumentFlowScore(expectedType: Type, actualType: Type): int {
        return ArgumentFlowScore(expectedType, actualType, new List<ColumnarStructDef>())
    }

    static func ArgumentFlowScore(expectedType: Type, actualType: Type, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>): int {
        if expectedType == null || actualType == null {
            throw new InvalidOperationException("Source direct-call argument flow types cannot be null.")
        }

        if sourceTypeDefinitions == null {
            throw new InvalidOperationException("Source direct-call conversion definitions cannot be null.")
        }

        if ExactTypeShapeMatches(expectedType, actualType) {
            return 8
        }

        if expectedType.get_IsByRef() || actualType.get_IsByRef() {
            return -1
        }

        if IsImplicitNumericFlow(actualType, expectedType) {
            return 6
        }

        if ColumnarNullableArgumentLowering.CanLiftValue(actualType, expectedType) || ColumnarDirectCallConstructedConversions.CanConvert(expectedType, actualType) {
            return 4
        }

        referenceFlow := ColumnarDirectCallArgumentFlow.None
        if TryClassifyBuiltInReferenceFlow(expectedType, actualType, sourceTypeDefinitions, out referenceFlow) {
            return 4
        }

        implicitConversion := ColumnarSourceImplicitConversionResolver.ResolveExact(actualType, expectedType, sourceTypeDefinitions)

        if implicitConversion.IsSelected {
            return 4
        }

        return -1
    }

    // Built-in reference and boxing conversions are authoritative over a same-ranked
    // user-defined operator. Keep their classification separate from the numeric score so a
    // score of four cannot accidentally erase an op_Implicit call from the persisted plan.
    static func TryClassifyBuiltInReferenceFlow(expectedType: Type, actualType: Type, sourceTypeDefinitions: IEnumerable<ColumnarStructDef>, out flow: ColumnarDirectCallArgumentFlow): bool {
        flow = ColumnarDirectCallArgumentFlow.None

        if expectedType == typeof(object) && actualType.FullName != "System.Void" {
            flow = actualType.get_IsValueType() || actualType.get_IsGenericParameter() ? ColumnarDirectCallArgumentFlow.Boxing : ColumnarDirectCallArgumentFlow.Reference
            return true
        }

        sourceIsReference := false
        if ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(actualType, expectedType, sourceTypeDefinitions, out sourceIsReference) {
            flow = sourceIsReference ? ColumnarDirectCallArgumentFlow.Reference : ColumnarDirectCallArgumentFlow.Boxing
            return true
        }

        // Mutable Reflection.Emit metadata is not a semantic fallback for source interfaces.
        // Every TypeBuilder-backed interface edge must come from the exact declaration registry;
        // otherwise a partially populated or same-spelled builder can become assignable at a
        // different phase and make selection disagree with persisted-plan emission.
        if ColumnarReferenceConversionFacts.IsDynamicDeclarationType(actualType) && expectedType.get_IsInterface() {
            return false
        }

        if actualType.get_IsValueType() || actualType.get_IsGenericParameter() {
            if !expectedType.get_IsValueType() && RuntimeAssignableFrom(expectedType, actualType) {
                flow = ColumnarDirectCallArgumentFlow.Boxing
                return true
            }
            return false
        }

        if expectedType.get_IsValueType() {
            return false
        }

        if RuntimeAssignableFrom(expectedType, actualType) || ColumnarReferenceConversionFacts.IsExactKnownUpcast(actualType, expectedType) {
            flow = ColumnarDirectCallArgumentFlow.Reference
            return true
        }

        return false
    }

    static func IsImplicitNumericFlow(actualType: Type, expectedType: Type): bool {
        if ColumnarNumericFacts.IsIntPromotable(actualType) {
            return expectedType == typeof(int) || expectedType == typeof(long) || expectedType == typeof(float) || expectedType == typeof(double) || expectedType == typeof(decimal)
        }

        if actualType == typeof(long) {
            return expectedType == typeof(float) || expectedType == typeof(double) || expectedType == typeof(decimal)
        }

        return actualType == typeof(float) && expectedType == typeof(double)
    }

    static func RuntimeAssignableFrom(expectedType: Type, actualType: Type): bool {
        try {
            return expectedType.IsAssignableFrom(actualType)
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    static func ResolveParameterTypes(parameterTypes: Type[], receiverType: Type, closed: bool): Type[] {
        resolved := new Type[](parameterTypes.Length)
        arguments := closed ? receiverType.GetGenericArguments() : new Type[](0)

        index := 0
        while index < parameterTypes.Length {
            resolved[index] = closed ? SubstituteTypeArguments(parameterTypes[index], arguments) : parameterTypes[index]

            index += 1
        }

        return resolved
    }

    static func SubstituteTypeArguments(signatureType: Type, arguments: Type[]): Type {
        if signatureType.get_IsGenericParameter() && signatureType.get_DeclaringMethod() == null {
            position := signatureType.get_GenericParameterPosition()
            if position < 0 || position >= arguments.Length {
                throw new InvalidOperationException("Source direct-call generic parameter position is invalid.")
            }

            return arguments[position]
        }

        if signatureType.get_IsSZArray() {
            element := signatureType.GetElementType()
            if element == null {
                throw new InvalidOperationException("Source direct-call array signature has no element type.")
            }

            return SubstituteTypeArguments(element, arguments).MakeArrayType()
        }

        if signatureType.get_IsGenericType() && !signatureType.get_IsGenericTypeDefinition() {
            definition := signatureType.GetGenericTypeDefinition()
            rawArguments := signatureType.GetGenericArguments()
            resolved := new Type[](rawArguments.Length)
            index := 0
            while index < rawArguments.Length {
                resolved[index] = SubstituteTypeArguments(rawArguments[index], arguments)

                index += 1
            }

            return definition.MakeGenericType(resolved)
        }

        if signatureType.get_HasElementType() {
            element := signatureType.GetElementType()
            if element == null {
                throw new InvalidOperationException("Source direct-call compound signature has no element type.")
            }

            if SubstituteTypeArguments(element, arguments) != element {
                throw new InvalidOperationException("Source direct-call compound signature substitution is unsupported.")
            }
        }

        return signatureType
    }

    static func ExactTypeShapeMatches(left: Type, right: Type): bool {
        return ColumnarReferenceConversionFacts.ExactTypeShapeMatches(left, right)
    }

    static func ValidateInstanceMethodFact(owner: ColumnarStructDef, memberName: string, definition: ColumnarInstanceMethodDef) {
        if definition == null || definition.Builder == null || definition.ParamTypes == null || definition.ParamModifierKinds == null || definition.ReturnType == null {
            throw new InvalidOperationException("Source instance-method definition facts cannot be null.")
        }

        ValidateModifierFacts(definition.ParamTypes, definition.ParamModifierKinds, false)

        method: MethodInfo = definition.Builder
        ownerType: Type = owner.Builder
        if method.get_IsAbstract() && !ownerType.get_IsAbstract() {
            throw new InvalidOperationException("An abstract source instance method requires an abstract declaring type.")
        }

        if method.get_IsStatic() || method.get_Name() != memberName || method.get_DeclaringType() != ownerType || !ExactTypeShapeMatches(method.get_ReturnType(), definition.ReturnType) {
            throw new InvalidOperationException("Source instance-method facts do not identify an exact instance declaration.")
        }
    }

    static func ValidateStaticMethodFact(owner: ColumnarStructDef, memberName: string, definition: ColumnarStaticMethodDef) {
        if definition == null || definition.Builder == null || definition.ParamTypes == null || definition.ParamModifierKinds == null || definition.ReturnType == null {
            throw new InvalidOperationException("Source static-method definition facts cannot be null.")
        }

        ValidateModifierFacts(definition.ParamTypes, definition.ParamModifierKinds, true)

        method: MethodInfo = definition.Builder
        ownerType: Type = owner.Builder
        if method.get_IsAbstract() && !ownerType.get_IsAbstract() {
            throw new InvalidOperationException("An abstract source static method requires an abstract declaring type.")
        }

        if !method.get_IsStatic() || method.get_Name() != memberName || method.get_DeclaringType() != ownerType || !ExactTypeShapeMatches(method.get_ReturnType(), definition.ReturnType) {
            throw new InvalidOperationException("Source static-method facts do not identify an exact static declaration.")
        }
    }

    static func ValidateModifierFacts(parameterTypes: Type[], modifierKinds: int[], isStatic: bool) {
        if modifierKinds.Length != 0 && modifierKinds.Length != parameterTypes.Length {
            throw new InvalidOperationException("Source direct-call modifier facts must be empty or match the parameter count.")
        }

        index := 0
        while index < parameterTypes.Length {
            if parameterTypes[index] == null {
                throw new InvalidOperationException("Source direct-call parameter types cannot be null.")
            }

            if modifierKinds.Length != 0 {
                modifier := modifierKinds[index]
                if modifier < 0 || modifier > 4 {
                    throw new InvalidOperationException("Source direct-call parameter modifier fact is invalid.")
                }

                if modifier == 3 && (index != parameterTypes.Length - 1 || !parameterTypes[index].get_IsSZArray()) {
                    throw new InvalidOperationException("A params source-call fact must describe the final array parameter.")
                }

                if modifier == 4 && (!isStatic || index != 0) {
                    throw new InvalidOperationException("A this source-call fact must describe the first static parameter.")
                }
            }

            index += 1
        }
    }

    static func TryClassifySourceType(receiverType: Type, sourceDefinitions: IEnumerable<ColumnarStructDef>, out definition: ColumnarStructDef?, out closed: bool): bool {
        definition = null
        closed = false
        for candidate in sourceDefinitions {
            if candidate == null || candidate.Builder == null {
                throw new InvalidOperationException("Source direct-call type definitions cannot be null.")
            }

            candidateClosed := ExactSourceTypeMatch(candidate, receiverType)
            candidateType: Type = candidate.Builder
            if candidateType == receiverType || candidateClosed {
                if definition != null && definition != candidate {
                    throw new InvalidOperationException("One exact call receiver type cannot map to two source definitions.")
                }

                definition = candidate
                closed = candidateClosed
            }
        }

        return definition != null
    }

    static func ExactSourceTypeMatch(definition: ColumnarStructDef, receiverType: Type): bool {
        definitionType: Type = definition.Builder
        if definitionType.get_IsInterface() != definition.IsInterface {
            throw new InvalidOperationException("Source direct-call interface facts do not match the source type.")
        }

        return receiverType.get_IsGenericType() && !receiverType.get_IsGenericTypeDefinition() && receiverType.GetGenericTypeDefinition() == definitionType
    }

    static func ValidateDefinitionGraph(root: ColumnarStructDef) {
        // The dogfood emitter intentionally does not admit BCL generic containers closed over
        // source types in public IL signatures yet. Object-keyed sets preserve exact reference
        // identity here without widening this resolver's product surface.
        active := new HashSet<object>()
        complete := new HashSet<object>()
        VisitDefinition(root, active, complete)
    }

    static func VisitDefinition(definition: ColumnarStructDef, active: HashSet<object>, complete: HashSet<object>) {
        if definition == null || definition.Builder == null || definition.DeclaredTypeName == null || definition.MethodOverloads == null || definition.StaticMethods == null || definition.InterfaceBases == null {
            throw new InvalidOperationException("Source direct-call type facts cannot be null.")
        }

        if complete.Contains(definition) {
            return
        }

        if active.Contains(definition) {
            throw new InvalidOperationException("Source direct-call type hierarchy contains a cycle.")
        }

        definitionType: Type = definition.Builder
        if definitionType.get_IsValueType() == definition.IsReference || definition.IsInterface && !definition.IsReference {
            throw new InvalidOperationException("Source direct-call reference facts do not match the source type.")
        }

        if !definition.IsInterface && definition.InterfaceBases.Count != 0 {
            throw new InvalidOperationException("Only source interfaces may carry interface-base call facts.")
        }

        active.Add(definition)
        baseDefinition := definition.BaseDef
        if baseDefinition != null {
            VisitDefinition(baseDefinition, active, complete)
        }

        interfaceIndex := 0
        while interfaceIndex < definition.InterfaceBases.Count {
            interfaceBase := definition.InterfaceBases[interfaceIndex]
            if interfaceBase == null || !interfaceBase.IsInterface {
                throw new InvalidOperationException("Source direct-call interface-base facts are invalid.")
            }

            VisitDefinition(interfaceBase, active, complete)
            interfaceIndex += 1
        }

        active.Remove(definition)
        complete.Add(definition)
    }

    static func ValidateReceiverShape(definition: ColumnarStructDef, receiverType: Type) {
        if receiverType.get_IsValueType() == definition.IsReference {
            throw new InvalidOperationException("Source direct-call receiver shape does not match its source definition.")
        }
    }

    static func ValidateExplicitInputs(receiverType: Type, memberName: string, argumentTypes: Type[], sourceDefinitions: IEnumerable<ColumnarStructDef>) {
        if sourceDefinitions == null {
            throw new InvalidOperationException("Source direct-call definition registry cannot be null.")
        }

        ValidateKnownInputs(receiverType, memberName, argumentTypes)
    }

    static func ValidateDeclarationQuery(root: ColumnarStructDef, memberName: string, argumentCount: int) {
        if root == null || memberName == null || argumentCount < 0 {
            throw new InvalidOperationException("Source direct-call declaration query inputs are invalid.")
        }
    }

    static func ValidateKnownInputs(receiverType: Type, memberName: string, argumentTypes: Type[]) {
        if receiverType == null || memberName == null || argumentTypes == null {
            throw new InvalidOperationException("Source direct-call inputs cannot be null.")
        }

        index := 0
        while index < argumentTypes.Length {
            if argumentTypes[index] == null {
                throw new InvalidOperationException("Source direct-call argument types cannot be null.")
            }

            index += 1
        }
    }

    static func NotSource(): ColumnarSourceDirectCallSelection {
        return new ColumnarSourceDirectCallSelection(ColumnarSourceDirectCallStatus.NotSourceType, ColumnarSourceDirectCallDispatch.None, null, typeof(object), typeof(object), null, new Type[](0), typeof(object), false, false, false)
    }

    static func NoDeclaration(): ColumnarSourceDirectCallSelection {
        return NotSource()
    }

    static func Rejected(definition: ColumnarStructDef, receiverType: Type, isStatic: bool): ColumnarSourceDirectCallSelection {
        return new ColumnarSourceDirectCallSelection(ColumnarSourceDirectCallStatus.Rejected, ColumnarSourceDirectCallDispatch.None, definition, receiverType, definition.Builder, null, new Type[](0), typeof(object), definition.IsReference, isStatic, false)
    }
}
