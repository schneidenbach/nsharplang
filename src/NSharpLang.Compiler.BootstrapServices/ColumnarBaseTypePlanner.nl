namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Base/interface classification is a semantic decision, not an emission mechanic: given a resolved
// base handle for a source type, N# decides whether it is a directly-implemented interface (source
// or runtime), a source base class, or an external runtime base class, applies the CLR-shape
// accessibility rules, and drives the exact TypeBuilder metadata (AddInterfaceImplementation /
// SetParent). The C# assembly owner only resolves the spelling to a live handle and mechanically
// reports the outcome; it never re-derives base-versus-interface identity.
enum ColumnarBaseTypeApplyOutcome {
    Applied,
    Reject,
    Unresolvable
}

class ColumnarBaseTypePlanner {
    def: ColumnarStructDef
    userStructDefs: IReadOnlyList<ColumnarStructDef>
    seenImplementedInterfaces: HashSet<TypeBuilder>

    // One planner instance owns the whole colon-list of one source type. Cross-base state (the single
    // permitted class parent, and the transitively implemented interface builders already emitted)
    // therefore persists across every base name in declaration order.
    constructor(def: ColumnarStructDef, userStructDefs: IReadOnlyList<ColumnarStructDef>) {
        if def == null || userStructDefs == null {
            throw new InvalidOperationException("Base-type planning requires a definition and its sibling source definitions.")
        }
        this.def = def
        this.userStructDefs = userStructDefs
        seenImplementedInterfaces = new HashSet<TypeBuilder>()
    }

    // Classify and apply one already-resolved base handle. Applied mutates the definition and its
    // builder; Reject is a terminal invalid-inheritance shape (the C# owner returns false, matching
    // the historical silent declines); Unresolvable means the handle resolved but is not an
    // admissible base or interface (the C# owner emits emit.declaration.base-type).
    func Apply(resolvedBaseType: Type): ColumnarBaseTypeApplyOutcome {
        if resolvedBaseType == null {
            return ColumnarBaseTypeApplyOutcome.Unresolvable
        }

        userDef := FindUserDef(resolvedBaseType)
        if userDef != null && userDef.IsInterface {
            return ApplyUserInterface(userDef, resolvedBaseType)
        }
        if IsRuntimeInterfaceType(resolvedBaseType) {
            def.ExternalInterfaces.Add(resolvedBaseType)
            def.Builder.AddInterfaceImplementation(resolvedBaseType)
            return ColumnarBaseTypeApplyOutcome.Applied
        }
        if userDef != null {
            return ApplyUserBase(userDef, resolvedBaseType)
        }
        return ApplyExternalBase(resolvedBaseType)
    }

    func ApplyUserInterface(implementedInterfaceDef: ColumnarStructDef, resolvedBaseType: Type): ColumnarBaseTypeApplyOutcome {
        duplicateInterface := false
        interfaceIndex := 0
        while interfaceIndex < def.ImplementedInterfaceTypes.Count {
            if SameInterfaceType(def.ImplementedInterfaceTypes[interfaceIndex], resolvedBaseType) {
                duplicateInterface = true
            }
            interfaceIndex = interfaceIndex + 1
        }
        if duplicateInterface {
            return ColumnarBaseTypeApplyOutcome.Applied
        }

        def.ImplementedInterfaces.Add(implementedInterfaceDef)
        def.ImplementedInterfaceTypes.Add(resolvedBaseType)
        def.Builder.AddInterfaceImplementation(resolvedBaseType)
        seenImplementedInterfaces.Add(implementedInterfaceDef.Builder)

        // A bare (non-constructed) source interface contributes its inherited interfaces to this
        // type's metadata. A closed-generic source interface resolves to a distinct constructed
        // handle, so only the constructed interface itself is added.
        if Object.ReferenceEquals(resolvedBaseType, implementedInterfaceDef.Builder) {
            transitive := new List<ColumnarStructDef>()
            EnumerateInterfaceAndBases(implementedInterfaceDef, transitive)
            transitiveIndex := 0
            while transitiveIndex < transitive.Count {
                implemented := transitive[transitiveIndex]
                if !Object.ReferenceEquals(implemented, implementedInterfaceDef) && seenImplementedInterfaces.Add(implemented.Builder) {
                    def.Builder.AddInterfaceImplementation(implemented.Builder)
                }
                transitiveIndex = transitiveIndex + 1
            }
        }
        return ColumnarBaseTypeApplyOutcome.Applied
    }

    func ApplyUserBase(baseDef: ColumnarStructDef, resolvedBaseType: Type): ColumnarBaseTypeApplyOutcome {
        if !def.IsReference {
            return ColumnarBaseTypeApplyOutcome.Reject
        }
        if def.IsRecord {
            return ColumnarBaseTypeApplyOutcome.Reject
        }
        if !baseDef.IsReference || Object.ReferenceEquals(baseDef, def) {
            return ColumnarBaseTypeApplyOutcome.Reject
        }
        if baseDef.IsRecord {
            return ColumnarBaseTypeApplyOutcome.Reject
        }
        if def.BaseDef != null {
            return ColumnarBaseTypeApplyOutcome.Reject
        }
        def.RecordBase(baseDef, resolvedBaseType)
        def.Builder.SetParent(resolvedBaseType)
        return ColumnarBaseTypeApplyOutcome.Applied
    }

    // An external runtime class (for example ControllerBase) is a legitimate parent for a source
    // class. Value types, records, and multi-parent shapes reject; anything that is not an
    // inheritable, verifiable, default-constructible external class is unresolvable.
    func ApplyExternalBase(resolvedBaseType: Type): ColumnarBaseTypeApplyOutcome {
        if !IsInheritableExternalClass(resolvedBaseType) {
            return ColumnarBaseTypeApplyOutcome.Unresolvable
        }
        if !def.IsReference {
            return ColumnarBaseTypeApplyOutcome.Reject
        }
        if def.IsRecord {
            return ColumnarBaseTypeApplyOutcome.Reject
        }
        if def.BaseDef != null || def.ExactBaseType != null {
            return ColumnarBaseTypeApplyOutcome.Reject
        }
        def.RecordBase(null, resolvedBaseType)
        def.Builder.SetParent(resolvedBaseType)
        return ColumnarBaseTypeApplyOutcome.Applied
    }

    func FindUserDef(resolvedType: Type): ColumnarStructDef? {
        if resolvedType is TypeBuilder {
            return FindDefByBuilder(resolvedType)
        }
        isGeneric := false
        try {
            isGeneric = resolvedType.get_IsGenericType()
        } catch {
            isGeneric = false
        }
        if isGeneric {
            try {
                definition := resolvedType.GetGenericTypeDefinition()
                if definition is TypeBuilder {
                    return FindDefByBuilder(definition)
                }
            } catch {
            }
        }
        // A builder-backed instantiation may expose only a narrow reflection surface.

        return null
    }

    // The builder handle is compared by reference — the emitted source definitions carry their own
    // live TypeBuilder, and the resolver returns that exact handle for a source spelling.
    func FindDefByBuilder(builderType: Type): ColumnarStructDef? {
        index := 0
        while index < userStructDefs.Count {
            candidate := userStructDefs[index]
            if Object.ReferenceEquals(candidate.Builder, builderType) {
                return candidate
            }
            index = index + 1
        }
        return null
    }

    static func IsRuntimeInterfaceType(valueType: Type): bool {
        try {
            return valueType.get_IsInterface()
        } catch {
            return false
        }
    }

    static func EnumerateInterfaceAndBases(interfaceDef: ColumnarStructDef, output: List<ColumnarStructDef>) {
        output.Add(interfaceDef)
        index := 0
        while index < interfaceDef.InterfaceBases.Count {
            EnumerateInterfaceAndBases(interfaceDef.InterfaceBases[index], output)
            index = index + 1
        }
    }

    // Interface dedup for the colon-list only: source interface builders and non-constructed runtime
    // interfaces are reference-identical when they name the same interface, and closed constructed
    // interfaces match structurally. Byref/array/enum shapes never appear as an implemented interface.
    static func SameInterfaceType(a: Type, b: Type): bool {
        if a == b {
            return true
        }
        // Distinct source-interface builders are distinct interfaces; a shared builder (including the
        // open definition of a constructed interface) is already reference-identical above.
        if a is TypeBuilder || b is TypeBuilder {
            return false
        }
        if !a.get_IsGenericType() || !b.get_IsGenericType() || a.get_IsGenericTypeDefinition() || b.get_IsGenericTypeDefinition() {
            return false
        }
        if !SameInterfaceType(a.GetGenericTypeDefinition(), b.GetGenericTypeDefinition()) {
            return false
        }
        aArgs := a.GetGenericArguments()
        bArgs := b.GetGenericArguments()
        if aArgs.Length != bArgs.Length {
            return false
        }
        argIndex := 0
        while argIndex < aArgs.Length {
            if !SameInterfaceType(aArgs[argIndex], bArgs[argIndex]) {
                return false
            }
            argIndex = argIndex + 1
        }
        return true
    }

    // A verifiable external base class must be a visible, non-sealed ordinary class that a source
    // subclass can extend; the synthesized default constructor then chains to the base's accessible
    // (public or protected) parameterless constructor. The CLR's special base types
    // (ValueType/Enum/Delegate/Array) are excluded — a source class inheriting them directly is
    // never valid IL.
    static func IsInheritableExternalClass(valueType: Type): bool {
        if valueType is TypeBuilder || valueType.get_IsGenericParameter() {
            return false
        }
        classShape := false
        try {
            classShape = valueType.get_IsClass() && !valueType.get_IsInterface() && !valueType.get_IsValueType() && !valueType.get_IsSealed() && !valueType.get_IsPointer() && !valueType.get_IsByRef() && !valueType.get_IsArray() && valueType.get_IsVisible()
        } catch {
            return false
        }
        if !classShape {
            return false
        }
        fullName := valueType.get_FullName()
        if fullName == "System.ValueType" || fullName == "System.Enum" || fullName == "System.Delegate" || fullName == "System.MulticastDelegate" || fullName == "System.Array" {
            return false
        }
        return true
    }
}
