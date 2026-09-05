namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection.Emit

// Owns live source-definition discovery while source TypeBuilders remain unbaked. The registry is
// still an ordered mutable sequence: every call observes its current rows and returns the first row
// whose builder has CLR Type equality with the requested handle.
class ColumnarSourceDefinitionResolver {
    static func TryFindByBuilderIdentity(
        definitions: IEnumerable<ColumnarStructDef>,
        requestedType: Type,
        out definition: ColumnarStructDef?
    ): bool {
        // Acquisition remains outside the protected enumeration lifetime. The inferred local keeps
        // the exact IEnumerator<ColumnarStructDef>.Current slot; movement and disposal use its
        // inherited nongeneric protocols.
        enumerator := definitions.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            // A null acquisition fails inside the protected lifetime; null disposal is skipped.
            if movement == null {
                throw new NullReferenceException()
            }

            while movement.MoveNext() {
                candidate := enumerator.get_Current()
                candidateBuilder: Type = candidate.Builder
                if candidateBuilder == requestedType {
                    definition = candidate
                    return true
                }
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }

        // A completed miss clears the caller only after successful disposal. Failures before a hit
        // preserve the old value; disposal after a hit observes and leaves the winning assignment.
        definition = null
        return false
    }

    static func FindByBuilderIdentity(
        definitions: IEnumerable<ColumnarStructDef>,
        requestedType: Type
    ): ColumnarStructDef? {
        selected: ColumnarStructDef? = null
        if TryFindByBuilderIdentity(definitions, requestedType, out selected) {
            return selected
        }
        return null
    }

    static func FindDirectType(
        definitions: IReadOnlyDictionary<string, ColumnarStructDef>,
        sourceType: Type
    ): ColumnarStructDef? {
        if !(sourceType is TypeBuilder) {
            return null
        }
        values := definitions.get_Values()
        return FindByBuilderIdentity(values, sourceType)
    }

    static func TryResolveStruct(
        sourceType: Type,
        definitions: IEnumerable<ColumnarStructDef>,
        out definition: ColumnarStructDef?
    ): bool {
        // The direct scan deliberately forwards the caller's out slot and remains outside the
        // reflection catches. Enumeration, equality and disposal failures keep their raw behavior.
        if sourceType is TypeBuilder {
            if TryFindByBuilderIdentity(definitions, sourceType, out definition) {
                return true
            }
        }

        isGenericType := false
        try {
            isGenericType = sourceType.get_IsGenericType()
        } catch ex: NotSupportedException {
            isGenericType = false
        } catch ex: NotImplementedException {
            isGenericType = false
        }

        if isGenericType {
            // The generic-definition read and its scan share the original narrow catch boundary.
            try {
                openType := sourceType.GetGenericTypeDefinition()
                if openType is TypeBuilder {
                    if TryFindByBuilderIdentity(definitions, openType, out definition) {
                        return true
                    }
                }
            } catch ex: NotSupportedException {
            } catch ex: NotImplementedException {
            }
        }
        // Some builder-backed instantiations expose only a narrow reflection surface.

        definition = null
        return false
    }

    static func TryResolveInterface(
        interfaceType: Type,
        definitions: IEnumerable<ColumnarStructDef>,
        out definition: ColumnarStructDef?
    ): bool {
        // Keep the candidate local: an inner failure must not mutate this method's caller slot.
        candidate: ColumnarStructDef? = null
        if TryResolveStruct(interfaceType, definitions, out candidate) {
            if candidate == null {
                throw new NullReferenceException()
            }
            if candidate.IsInterface {
                definition = candidate
                return true
            }
        }

        definition = null
        return false
    }

    static func TryResolveClosedReceiver(
        receiverType: Type,
        definitions: IReadOnlyDictionary<string, ColumnarStructDef>,
        out definition: ColumnarStructDef?,
        out closedArguments: Type[]
    ): bool {
        definition = null
        emptyArguments: Type[] = System.Type.EmptyTypes
        closedArguments = emptyArguments
        if !ColumnarTypeOfPlanner.IsClosedSourceGeneric(receiverType) {
            return false
        }

        // IsClosedSourceGeneric already read the generic definition as part of its guard. Preserve
        // the original second read before acquiring the live registry enumerator.
        openType := receiverType.GetGenericTypeDefinition()
        values := definitions.get_Values()
        enumerator := values.GetEnumerator()
        movement := enumerator as IEnumerator
        try {
            if movement == null {
                throw new NullReferenceException()
            }

            while movement.MoveNext() {
                candidate := enumerator.get_Current()
                candidateBuilder: Type = candidate.Builder
                if candidateBuilder == openType {
                    // Both writes remain inside iteration and before disposal. A late argument read
                    // failure therefore leaves the winning definition and the shared empty array.
                    definition = candidate
                    closedArguments = receiverType.GetGenericArguments()
                    return true
                }
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }

        return false
    }
}
