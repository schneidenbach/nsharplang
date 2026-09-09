namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit


// Resolves source members while their declaring types are still unbaked. Every walk observes the
// live definition records directly and searches the nearest declaration first. Interface-method
// lookup preserves the declaration-order depth-first traversal used by the legacy emitter.
class ColumnarSourceMemberChainResolver {
    static func TryFindFieldOnChain(definition: ColumnarStructDef, name: string, out field: FieldBuilder?): bool {
        owner: ColumnarStructDef? = null
        return TryFindFieldOnChain(definition, name, out owner, out field)
    }

    static func TryFindFieldOnChain(definition: ColumnarStructDef, name: string, out owner: ColumnarStructDef?, out field: FieldBuilder?): bool {
        current: ColumnarStructDef? = definition
        while current != null {
            candidate := current
            if candidate.Fields.TryGetValue(name, out field) {
                owner = candidate
                return true
            }
            current = candidate.BaseDef
        }
        owner = null
        field = null
        return false
    }

    static func TryFindMethodOnChain(definition: ColumnarStructDef, name: string, out method: ColumnarInstanceMethodDef?): bool {
        current: ColumnarStructDef? = definition
        while current != null {
            candidate := current
            found: ColumnarInstanceMethodDef? = null
            if candidate.Methods.TryGetValue(name, out found) {
                method = found
                return true
            }
            if candidate.IsInterface && TryFindMethodOnInterfaceBases(candidate, name, out method) {
                return true
            }
            current = candidate.BaseDef
        }
        method = null
        return false
    }

    static func TryFindMethodOnChain(definition: ColumnarStructDef, name: string, argumentCount: int, out method: ColumnarInstanceMethodDef?): bool {
        current: ColumnarStructDef? = definition
        while current != null {
            candidate := current
            overloads: List<ColumnarInstanceMethodDef>? = null
            if candidate.MethodOverloads.TryGetValue(name, out overloads) {
                selected: ColumnarInstanceMethodDef? = null
                if TryFindMethodAtArity(overloads, argumentCount, out selected) {
                    method = selected
                    return true
                }
            }
            if candidate.IsInterface && TryFindMethodOnInterfaceBases(candidate, name, argumentCount, out method) {
                return true
            }
            current = candidate.BaseDef
        }
        method = null
        return false
    }

    static func TryFindMethodOnInterfaceBases(definition: ColumnarStructDef, name: string, out method: ColumnarInstanceMethodDef?): bool {
        enumerator := definition.InterfaceBases.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                baseInterface := enumerator.get_Current()
                found: ColumnarInstanceMethodDef? = null
                if baseInterface.Methods.TryGetValue(name, out found) {
                    method = found
                    return true
                }
                if TryFindMethodOnInterfaceBases(baseInterface, name, out method) {
                    return true
                }
            }
        } finally {
            enumerator.Dispose()
        }
        method = null
        return false
    }

    static func TryFindMethodOnInterfaceBases(definition: ColumnarStructDef, name: string, argumentCount: int, out method: ColumnarInstanceMethodDef?): bool {
        enumerator := definition.InterfaceBases.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                baseInterface := enumerator.get_Current()
                overloads: List<ColumnarInstanceMethodDef>? = null
                if baseInterface.MethodOverloads.TryGetValue(name, out overloads) {
                    selected: ColumnarInstanceMethodDef? = null
                    if TryFindMethodAtArity(overloads, argumentCount, out selected) {
                        method = selected
                        return true
                    }
                }
                if TryFindMethodOnInterfaceBases(baseInterface, name, argumentCount, out method) {
                    return true
                }
            }
        } finally {
            enumerator.Dispose()
        }
        method = null
        return false
    }

    static func TryFindMethodAtArity(overloads: List<ColumnarInstanceMethodDef>, argumentCount: int, out method: ColumnarInstanceMethodDef?): bool {
        enumerator := overloads.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                candidate := enumerator.get_Current()
                if candidate.ParamTypes.Length == argumentCount {
                    method = candidate
                    return true
                }
            }
        } finally {
            enumerator.Dispose()
        }
        method = null
        return false
    }

    static func TryFindStaticFieldOnChain(definition: ColumnarStructDef, name: string, out field: FieldBuilder?): bool {
        current: ColumnarStructDef? = definition
        while current != null {
            candidate := current
            if candidate.StaticFields.TryGetValue(name, out field) {
                return true
            }
            current = candidate.BaseDef
        }
        field = null
        return false
    }

    static func TryFindStaticPropertyOnChain(definition: ColumnarStructDef, name: string, out property: ColumnarPropertyDef?): bool {
        current: ColumnarStructDef? = definition
        while current != null {
            candidate := current
            found: ColumnarPropertyDef? = null
            if candidate.StaticProperties.TryGetValue(name, out found) {
                property = found
                return true
            }
            current = candidate.BaseDef
        }
        property = null
        return false
    }
}
