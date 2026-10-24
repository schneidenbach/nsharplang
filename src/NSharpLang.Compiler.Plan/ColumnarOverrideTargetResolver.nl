namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

class ColumnarBaseMethodMatchParameter {
    readonly parameterValue: ParameterInfo
    readonly runtimeTypeValue: Type

    Parameter: ParameterInfo => parameterValue
    RuntimeType: Type => runtimeTypeValue

    constructor(parameter: ParameterInfo, runtimeType: Type) {
        if parameter == null || runtimeType == null {
            throw new InvalidOperationException("A base-method match parameter cannot be null.")
        }
        parameterValue = parameter
        runtimeTypeValue = runtimeType
    }
}

// One candidate signature comparison. Reflection reads retain the old order: parameters and arity,
// return type, then parameters from left to right. The successful row keeps the exact ParameterInfo
// and Type values that were compared; a losing row never acquires structural identity.
class ColumnarBaseMethodSignatureMatch {
    readonly targetValue: MethodInfo
    readonly effectiveReturnRuntimeTypeValue: Type
    readonly parametersValue: IReadOnlyList<object>
    readonly parameterCountValue: int
    readonly matchedValue: bool

    Target: MethodInfo => targetValue
    EffectiveReturnRuntimeType: Type => effectiveReturnRuntimeTypeValue
    ParameterCount: int => parameterCountValue
    Matched: bool => matchedValue

    constructor(target: MethodInfo, returnType: Type, parameterTypes: Type[]) {
        effectiveReturn := typeof(object)
        parameters := new List<object>()
        matched := false
        reflectedParameters := target.GetParameters()
        if reflectedParameters != null && reflectedParameters.Length == parameterTypes.Length {
            effectiveReturn = target.ReturnType
            matched = ColumnarBaseMethodMatch.SameTypeIdentity(effectiveReturn, returnType)
            if matched {
                index := 0
                while index < reflectedParameters.Length {
                    parameter := reflectedParameters[index]
                    if parameter == null {
                        matched = false
                        break
                    }
                    effectiveParameter := parameter.ParameterType
                    if !ColumnarBaseMethodMatch.SameTypeIdentity(effectiveParameter, parameterTypes[index]) {
                        matched = false
                        break
                    }
                    parameters.Add(new ColumnarBaseMethodMatchParameter(parameter, effectiveParameter))
                    index += 1
                }
            }
        }

        targetValue = target
        effectiveReturnRuntimeTypeValue = effectiveReturn
        parametersValue = parameters.AsReadOnly()
        parameterCountValue = parameters.Count
        matchedValue = matched
    }

    func EffectiveParameter(index: int): ColumnarBaseMethodMatchParameter {
        parameter := parametersValue.get_Item(index) as ColumnarBaseMethodMatchParameter
        if parameter == null {
            throw new InvalidOperationException("Base-method match parameter storage is invalid.")
        }
        return parameter
    }
}

// The deriving base lookup. It owns the complete policy once: null-base Object fallback, declared
// methods at each level, the public virtual/non-final/non-generic filter, and assembly-qualified-name
// signature equality. A successful attempt records the actual level that supplied the MethodInfo.
class ColumnarBaseMethodMatch {
    readonly targetValue: MethodInfo?
    readonly foundContextValue: Type?
    readonly signatureValue: ColumnarBaseMethodSignatureMatch?
    readonly matchedValue: bool

    Target: MethodInfo? => targetValue
    FoundContext: Type? => foundContextValue
    Signature: ColumnarBaseMethodSignatureMatch? => signatureValue
    Matched: bool => matchedValue

    constructor(baseType: Type?, name: string, returnType: Type, parameterTypes: Type[]) {
        target: MethodInfo? = null
        foundContext: Type? = null
        signature: ColumnarBaseMethodSignatureMatch? = null
        matched := false

        if name != null && name.Length > 0 && returnType != null && parameterTypes != null {
            current := baseType
            if current == null {
                current = typeof(object)
            }

            while current != null && !matched {
                candidates := DeclaredMethodsOrEmpty(current)
                for candidate in candidates {
                    if IsOverridableTarget(candidate, name) {
                        candidateSignature := new ColumnarBaseMethodSignatureMatch(candidate, returnType, parameterTypes)
                        if candidateSignature.Matched {
                            target = candidate
                            foundContext = current
                            signature = candidateSignature
                            matched = true
                            break
                        }
                    }
                }

                if !matched {
                    current = BaseTypeOrNull(current)
                }
            }
        }

        targetValue = target
        foundContextValue = foundContext
        signatureValue = signature
        matchedValue = matched
    }

    func RequiredTarget(): MethodInfo {
        target := targetValue
        if !matchedValue || target == null {
            throw new InvalidOperationException("A successful base-method match requires its target.")
        }
        return target
    }

    func RequiredFoundContext(): Type {
        context := foundContextValue
        if !matchedValue || context == null {
            throw new InvalidOperationException("A successful base-method match requires its found context.")
        }
        return context
    }

    func RequiredSignature(): ColumnarBaseMethodSignatureMatch {
        signature := signatureValue
        if !matchedValue || signature == null || !signature.Matched {
            throw new InvalidOperationException("A successful base-method match requires its observed signature.")
        }
        return signature
    }

    static func DeclaredMethodsOrEmpty(owner: Type): MethodInfo[] {
        if owner is TypeBuilder {
            return new MethodInfo[](0)
        }

        try {
            flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly
            methods := owner.GetMethods(flags)
            if methods == null {
                return new MethodInfo[](0)
            }
            return methods
        } catch {
            return new MethodInfo[](0)
        }
    }

    static func BaseTypeOrNull(owner: Type): Type? {
        try {
            return owner.BaseType
        } catch {
            return null
        }
    }

    // WHICH OF A BASE'S VIRTUAL MEMBERS A DERIVED TYPE MAY TAKE THE SLOT OF.
    //
    // The enumeration above already asks metadata for the non-public ones, and this test then threw
    // every one of them away: `IsPublic`. So `Collection<T>.SetItem` — `protected virtual`, and the
    // whole reason that type is designed to be derived from — reported "no overridable base member
    // matches 'SetItem'", with or without a written `protected`. The rule is the ordinary
    // accessibility relation, asked as a derived type in another assembly asks it: `public`,
    // `protected` and `protected internal` yes, the three assembly-bound levels no, because the base
    // is in a REFERENCED assembly and N# models no `InternalsVisibleTo`.
    static func IsOverridableTarget(candidate: MethodInfo, name: string): bool {
        if candidate == null || candidate.Name != name {
            return false
        }
        if candidate.IsStatic || !candidate.IsVirtual || candidate.IsFinal {
            return false
        }
        if candidate.IsGenericMethod || candidate.IsGenericMethodDefinition {
            return false
        }
        return MemberAccessibility.IsAccessible(MemberAccessibility.LevelOfMethod(candidate), false, true, true, false)
    }

    // The metadata accessibility bits of a matched target, which an `override` that wrote no
    // accessibility word of its own adopts.
    static func AccessibilityAttributesOf(target: MethodBase?): int {
        if target == null {
            return -1
        }

        return (int)target.Attributes & 7
    }

    static func SameTypeIdentity(left: Type, right: Type): bool {
        if left == null || right == null {
            return false
        }
        if Object.ReferenceEquals(left, right) {
            return true
        }
        leftName := left.AssemblyQualifiedName
        rightName := right.AssemblyQualifiedName
        return leftName != null && rightName != null && leftName == rightName
    }
}

// THE SOURCE-BASE OVERRIDE LOOKUP.
//
// `ColumnarBaseMethodMatch` reads the base chain through Reflection, and a base class that is being
// EMITTED IN THIS SAME ASSEMBLY has nothing to read: its `TypeBuilder` is unbaked, so
// `DeclaredMethodsOrEmpty` answers the empty array by design and every `override` of a member the
// program itself declares reported "no overridable base member matches". That is not a missing
// member; it is a missing DOOR. This is the door: the source base's own declaration table, whose
// `MethodBuilder` handles carry the same name, signature and virtual-ness the baked type would.
//
// IT PRODUCES NO `DefineMethodOverride` TARGET, AND THAT IS THE POINT. A class override of a class
// member is matched by the CLR from name and signature once the deriving method is `virtual` and
// does not take a new slot — which is exactly what C# emits, with no MethodImpl row. An explicit
// MethodImpl here would be a second, redundant statement of the same fact, and one that would have
// to name a member of a type that does not exist yet.
class ColumnarSourceBaseMethodMatch {
    readonly targetValue: MethodBuilder?
    readonly ownerValue: ColumnarStructDef?
    readonly matchedValue: bool
    readonly foundNameValue: bool

    Target: MethodBuilder? => targetValue
    Owner: ColumnarStructDef? => ownerValue
    Matched: bool => matchedValue

    // Whether some base level declared a member of this NAME even though none matched the
    // signature. It separates "you misspelled it" from "your signature does not line up", which the
    // analyzer reports for source-visible shapes and the emitter must not contradict.
    FoundName: bool => foundNameValue

    // `baseDefinition` is the overriding type's DIRECT source base — the walk starts AT it, not
    // past it, because the member being overridden is most often declared right there.
    constructor(baseDefinition: ColumnarStructDef?, name: string, returnType: Type, parameterTypes: Type[]) {
        target: MethodBuilder? = null
        owner: ColumnarStructDef? = null
        matched := false
        foundName := false

        if baseDefinition != null && name != null && name.Length > 0 && returnType != null && parameterTypes != null {
            current: ColumnarStructDef? = baseDefinition
            guard := 0
            while current != null && !matched && guard <= 64 {
                overloads: List<ColumnarInstanceMethodDef>? = null
                if current.MethodOverloads.TryGetValue(name, out overloads) && overloads != null {
                    for candidate in overloads {
                        foundName = true
                        if IsOverridableSourceTarget(candidate) && SameSignature(candidate, returnType, parameterTypes) {
                            target = candidate.Builder
                            owner = current
                            matched = true
                            break
                        }
                    }
                }

                current = current.BaseDef
                guard = guard + 1
            }
        }

        targetValue = target
        ownerValue = owner
        matchedValue = matched
        foundNameValue = foundName
    }

    func RequiredTarget(): MethodBuilder {
        target := targetValue
        if !matchedValue || target == null {
            throw new InvalidOperationException("A successful source-base method match requires its target.")
        }
        return target
    }

    // A source base member is overridable on exactly the terms a runtime one is: an instance member
    // that owns a virtual slot and has not sealed it.
    static func IsOverridableSourceTarget(candidate: ColumnarInstanceMethodDef): bool {
        if candidate == null || candidate.Builder == null {
            return false
        }
        builder := candidate.Builder
        if builder.IsStatic || !builder.IsVirtual || builder.IsFinal {
            return false
        }
        return !builder.IsGenericMethod && !builder.IsGenericMethodDefinition
    }

    static func SameSignature(candidate: ColumnarInstanceMethodDef, returnType: Type, parameterTypes: Type[]): bool {
        if candidate.ParamTypes.Length != parameterTypes.Length || !SameSourceTypeIdentity(candidate.ReturnType, returnType) {
            return false
        }
        index := 0
        while index < parameterTypes.Length {
            if !SameSourceTypeIdentity(candidate.ParamTypes[index], parameterTypes[index]) {
                return false
            }
            index = index + 1
        }
        return true
    }

    // A BUILDER HAS NO STABLE ASSEMBLY-QUALIFIED NAME TO COMPARE. Both sides of this comparison come
    // out of the same emission, so an unbaked `TypeBuilder` or a `GenericTypeParameterBuilder` is
    // the SAME type exactly when it is the same object; only complete external identities fall
    // through to the assembly-qualified rule the runtime chain uses.
    static func SameSourceTypeIdentity(left: Type, right: Type): bool {
        if left == null || right == null {
            return false
        }
        if Object.ReferenceEquals(left, right) {
            return true
        }
        if IsBuilderBound(left) || IsBuilderBound(right) {
            return false
        }
        return ColumnarBaseMethodMatch.SameTypeIdentity(left, right)
    }

    static func IsBuilderBound(candidate: Type): bool {
        if candidate is TypeBuilder || candidate.IsGenericParameter {
            return true
        }
        if candidate.HasElementType {
            element := candidate.GetElementType()
            return element != null && IsBuilderBound(element)
        }
        if !candidate.IsGenericType || candidate.IsGenericTypeDefinition {
            return false
        }
        arguments := candidate.GetGenericArguments()
        for argument in arguments {
            if IsBuilderBound(argument) {
                return true
            }
        }
        return false
    }
}

class ColumnarBaseMethodBinding {
    readonly descriptorValue: ColumnarExternalMethodDescriptor
    readonly targetValue: MethodInfo

    Descriptor: ColumnarExternalMethodDescriptor => descriptorValue
    Target: MethodInfo => targetValue

    constructor(matchedBase: ColumnarBaseMethodMatch, table: ColumnarStructuralTypeReferenceTable) {
        if matchedBase == null || table == null || !matchedBase.Matched {
            throw new InvalidOperationException("A base-method binding requires a successful lookup and emission table.")
        }
        target := matchedBase.RequiredTarget()
        descriptor := new ColumnarExternalMethodDescriptor(matchedBase, table)
        if !Object.ReferenceEquals(descriptor.Target, target) {
            throw new InvalidOperationException("A base-method descriptor changed its resolved target.")
        }
        descriptorValue = descriptor
        targetValue = target
    }

    func ValidatedTarget(expectedTable: ColumnarStructuralTypeReferenceTable): MethodInfo {
        if expectedTable == null || !descriptorValue.Validate(expectedTable) || !Object.ReferenceEquals(descriptorValue.Target, targetValue) {
            throw new InvalidOperationException("The base-method binding does not belong to this emission context.")
        }
        return targetValue
    }
}

class ColumnarOverrideTargetResolver {
    static func DeclaredMethodsOrEmpty(owner: Type): MethodInfo[] {
        return ColumnarBaseMethodMatch.DeclaredMethodsOrEmpty(owner)
    }

    static func SameTypeIdentity(left: Type, right: Type): bool {
        return ColumnarBaseMethodMatch.SameTypeIdentity(left, right)
    }

    static func TryFindOverrideTarget(baseType: Type?, name: string, returnType: Type, parameterTypes: Type[], out target: MethodInfo?): bool {
        target = null
        matchedBase := new ColumnarBaseMethodMatch(baseType, name, returnType, parameterTypes)
        if !matchedBase.Matched {
            return false
        }
        target = matchedBase.Target
        return target != null
    }
}

// THE BASE SLOT AN `override` PROPERTY TAKES.
//
// An override replaces each accessor it declares. A bare `override Name: T` declares both, as C#'s
// `public override T Name { get; set; }` does, so the base has to open both: a `get_Name` and a
// `set_Name` that are virtual, not sealed, and typed `T`. A written `override Name: T => expr`
// declares only the getter, as C#'s `public override T Name => expr` does, so only the getter slot is
// needed and a base setter, if any, is inherited untouched. The CLR then binds each accessor to its
// slot by name and signature — no MethodImpl row, which is what C# emits — and that binding is silent
// when it misses: a non-newslot virtual with nothing to reuse simply opens a new slot, and a base-typed
// caller never reaches the override. So the slot is proved here and a miss is a decline that says
// which half is missing, never an emitted type that dispatches to the wrong body.
//
// The walk is the method walk's: a base being emitted in this compilation answers from its own
// declaration table, whose accessor builders carry the virtual-ness the baked type will; past the
// source chain, metadata answers through `ColumnarBaseMethodMatch`, which asks for non-public slots
// too (`protected virtual` is the shape most worth catching).
class ColumnarPropertyOverrideMatch {
    readonly matchedValue: bool
    readonly accessibilityValue: int
    readonly declineMessageValue: string

    Matched: bool => matchedValue
    // The metadata accessibility bits of the base GETTER, which an override that wrote no
    // accessibility word adopts — the slot's accessibility belongs to the type that opened it.
    AccessibilityAttributes: int => accessibilityValue
    DeclineMessage: string => declineMessageValue

    constructor(owner: ColumnarStructDef, name: string, propertyType: Type, voidType: Type, overridesSetter: bool) {
        if owner == null || name == null || propertyType == null || voidType == null {
            throw new InvalidOperationException("A property-override lookup requires its owner, name and type.")
        }

        accessibility := -1
        decline := ""
        getterProven := false
        // A get-only override needs no setter slot; a base setter, if any, is inherited as it is.
        setterProven := !overridesSetter
        typeName := owner.Builder.Name

        // The getter slot is proved at the NEAREST declaration of the name. The setter slot may sit
        // further up: a get-only `override` in between took only the getter, and the setter it
        // inherited is still the slot the type that opened the property declared.
        current: ColumnarStructDef? = owner.BaseDef
        depth := 0
        while current != null && decline == "" && !(getterProven && setterProven) && depth <= 64 {
            property: ColumnarPropertyDef? = null
            if current.Properties.TryGetValue(name, out property) && property != null {
                if !getterProven {
                    if !IsOpenSlot(property.Getter) {
                        decline = "'" + typeName + "." + name + "' overrides '" + current.Builder.Name + "." + name + "', whose getter is not virtual"
                    } else if !SameDeclaredType(owner, property.PropertyType, propertyType, depth) {
                        decline = "'" + typeName + "." + name + "' must have the type of the property it overrides"
                    } else {
                        getterProven = true
                        accessibility = ColumnarBaseMethodMatch.AccessibilityAttributesOf(property.Getter)
                    }
                }
                if decline == "" && !setterProven {
                    setter := property.Setter
                    if setter != null && IsOpenSlot(setter) {
                        setterProven = true
                    } else if setter != null || !ReusesSlot(property.Getter) {
                        decline = "'" + typeName + "." + name + "' declares a setter, but '" + current.Builder.Name + "." + name + "' has no virtual setter to override"
                    }
                }
            } else if !getterProven && (current.SettableAutoProperties.ContainsKey(name) || current.Fields.ContainsKey(name)) {
                decline = "'" + typeName + "." + name + "' overrides '" + current.Builder.Name + "." + name + "', which is not virtual"
            }

            current = current.BaseDef
            depth = depth + 1
        }

        // PAST THE SOURCE CHAIN, METADATA ANSWERS for whichever half is still open. The method walk
        // skips the types being built, so it starts at the exact base and meets the first CLR type.
        if decline == "" && !getterProven {
            getterMatch := new ColumnarBaseMethodMatch(owner.ExactBaseType, "get_" + name, propertyType, new Type[](0))
            if getterMatch.Matched {
                getterProven = true
                accessibility = ColumnarBaseMethodMatch.AccessibilityAttributesOf(getterMatch.RequiredTarget())
            } else {
                decline = "no overridable base property matches '" + name + "' for '" + typeName + "'"
            }
        }

        if decline == "" && !setterProven {
            setterParameters := new Type[](1)
            setterParameters[0] = propertyType
            setterMatch := new ColumnarBaseMethodMatch(owner.ExactBaseType, "set_" + name, voidType, setterParameters)
            if setterMatch.Matched {
                setterProven = true
            } else {
                decline = "'" + typeName + "." + name + "' declares a setter, but the base property '" + name + "' has no overridable setter"
            }
        }

        // A GET-ONLY OVERRIDE INHERITS THE BASE'S SETTER, and a concrete type cannot inherit an abstract
        // one: the CLR refuses to load it. The analyzer reports it (NL324, `Name.set`).
        if decline == "" && !overridesSetter && !owner.Builder.IsAbstract && InheritsAbstractSetter(owner, name, propertyType, voidType) {
            decline = "'" + typeName + "." + name + "' overrides only the getter, so the abstract setter it inherits is left unimplemented"
        }

        matched := decline == "" && getterProven && setterProven
        matchedValue = matched
        accessibilityValue = accessibility
        declineMessageValue = decline
    }

    // Whether a get-only override inherits a setter at all, by the same walk as `InheritsAbstractSetter`.
    static func InheritsSetter(owner: ColumnarStructDef, name: string, propertyType: Type, voidType: Type): bool {
        current: ColumnarStructDef? = owner.BaseDef
        depth := 0
        while current != null && depth <= 64 {
            property: ColumnarPropertyDef? = null
            if current.Properties.TryGetValue(name, out property) && property != null {
                if property.Setter != null {
                    return true
                }
                if !ReusesSlot(property.Getter) {
                    return false
                }
            }
            current = current.BaseDef
            depth = depth + 1
        }

        setterParameters := new Type[](1)
        setterParameters[0] = propertyType
        return new ColumnarBaseMethodMatch(owner.ExactBaseType, "set_" + name, voidType, setterParameters).Matched
    }

    // The setter a get-only override inherits: the nearest declaration of the name with a setter, past
    // get-only overrides, and past the source chain the nearest metadata `set_` slot.
    static func InheritsAbstractSetter(owner: ColumnarStructDef, name: string, propertyType: Type, voidType: Type): bool {
        current: ColumnarStructDef? = owner.BaseDef
        depth := 0
        while current != null && depth <= 64 {
            property: ColumnarPropertyDef? = null
            if current.Properties.TryGetValue(name, out property) && property != null {
                setter := property.Setter
                if setter != null {
                    return ((int)setter.Attributes & 0x0400) != 0
                }
                if !ReusesSlot(property.Getter) {
                    return false
                }
            }
            current = current.BaseDef
            depth = depth + 1
        }

        setterParameters := new Type[](1)
        setterParameters[0] = propertyType
        setterMatch := new ColumnarBaseMethodMatch(owner.ExactBaseType, "set_" + name, voidType, setterParameters)
        return setterMatch.Matched && setterMatch.RequiredTarget().IsAbstract
    }

    // WHETHER AN ACCESSOR TAKES A BASE'S SLOT rather than opening its own: virtual with NewSlot clear,
    // the `override` shape. A member lookup that meets the base's declaration after this one has met
    // the same member again, not a second member that shadows it.
    static func ReusesSlot(accessor: MethodInfo): bool {
        word := (int)accessor.Attributes
        return (word & 0x0040) != 0 && (word & 0x0100) == 0
    }

    // An accessor opens the slot when it is virtual and NOT final — the method walk's test.
    static func IsOpenSlot(accessor: MethodBuilder): bool {
        word := (int)accessor.Attributes
        return (word & 0x0040) != 0 && (word & 0x0020) == 0 && (word & 0x0010) == 0
    }

    // THE BASE PROPERTY'S TYPE, AS THE OVERRIDING TYPE SEES IT. Both sides are builders from this one
    // emission, so identity is object identity — except across a generic base: `class Box: Holder<int>`
    // sees `Holder<T>.Value: T` as `int`, so the DIRECT base's own type parameter is substituted from
    // the overriding type's exact base. A type that mentions a type parameter in any other way
    // (`List<T>`, or a parameter of a base further up) is left to the CLR's own name-and-signature
    // binding; a type with no parameter in it is a definite mismatch.
    static func SameDeclaredType(owner: ColumnarStructDef, baseType: Type, overridingType: Type, depth: int): bool {
        if ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(baseType, overridingType) {
            return true
        }

        if !MentionsTypeParameter(baseType) {
            return false
        }

        exactBase := owner.ExactBaseType
        if depth == 0 && baseType.IsGenericParameter && exactBase != null && exactBase.IsGenericType && !exactBase.IsGenericTypeDefinition {
            arguments := exactBase.GetGenericArguments()
            position := baseType.GenericParameterPosition
            return position >= 0 && position < arguments.Length && ColumnarSourceBaseMethodMatch.SameSourceTypeIdentity(arguments[position], overridingType)
        }

        return true
    }

    static func MentionsTypeParameter(candidate: Type): bool {
        if candidate.IsGenericParameter {
            return true
        }
        if candidate.HasElementType {
            element := candidate.GetElementType()
            return element != null && MentionsTypeParameter(element)
        }
        if !candidate.IsGenericType || candidate is TypeBuilder {
            return false
        }
        for argument in candidate.GetGenericArguments() {
            if MentionsTypeParameter(argument) {
                return true
            }
        }
        return false
    }
}
