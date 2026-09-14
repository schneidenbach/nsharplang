namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// Owns the emitter's exact legacy interface coercion and object-boxing decisions. These rules
// intentionally use direct TypeBuilder identities and the declaration registry rather than the
// broader structural reference-conversion rules used by newer call planning.
class ColumnarReferenceCoercionPlanner {
    static func CanUseInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): bool {
        targetBuilder := targetType as TypeBuilder
        if targetBuilder == null {
            return CanUseClosedSourceInterfaceUpcast(valueType, targetType, structRegistry)
        }
        targetDefinition := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(
            structRegistry.get_Values(),
            targetBuilder
        )
        if targetDefinition == null || !targetDefinition.IsInterface {
            return false
        }

        valueBuilder := valueType as TypeBuilder
        if valueBuilder == null {
            return false
        }
        valueDefinition := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(
            structRegistry.get_Values(),
            valueBuilder
        )
        if valueDefinition == null {
            return false
        }
        return ColumnarGenericConstraintPlanner.AnyInterfaceEqualsOrExtends(
            valueDefinition.ImplementedInterfaces,
            targetBuilder
        )
    }

    // A CLOSED SOURCE INTERFACE IS NOT A `TypeBuilder`, AND THAT IS THE WHOLE DIFFERENCE.
    //
    // `class IntBox: IBox<int>` records `IBox<int>` — a `TypeBuilderInstantiation`, not the
    // `IBox`1` builder — so the cast above answered null and the upcast declined:
    // `b: IBox<int> = new IntBox(5)` was `emit.typed-local.type-mismatch`. The edge is still one the
    // SOURCE declared, so it is read off the declaration rather than from reflection (which refuses
    // the question over an unbaked instantiation): the implementer's own `ImplementedInterfaceTypes`
    // are compared structurally against the target, and the base chain is walked because a base
    // class's interfaces are the derived type's too.
    static func CanUseClosedSourceInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): bool {
        if !targetType.get_IsGenericType() || targetType.get_IsGenericTypeDefinition() {
            return false
        }

        targetDefinitionBuilder := targetType.GetGenericTypeDefinition() as TypeBuilder
        if targetDefinitionBuilder == null {
            return false
        }

        targetDefinition := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(
            structRegistry.get_Values(),
            targetDefinitionBuilder
        )
        if targetDefinition == null || !targetDefinition.IsInterface {
            return false
        }

        // THE IMPLEMENTER IS EITHER BARE OR CLOSED. `class IntBox: IBox<int>` is the builder itself
        // and writes its interface out already closed; `class GenBox<T>: IBox<T>` records the edge in
        // ITS OWN parameters, and a `GenBox<string>` value supplies them by position — that
        // substitution is the whole of what makes `IBox<string>` the right target.
        valueBuilder := valueType as TypeBuilder
        valueArguments := System.Array.Empty<Type>()
        if valueBuilder == null {
            if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
                return false
            }

            valueBuilder = valueType.GetGenericTypeDefinition() as TypeBuilder
            if valueBuilder == null {
                return false
            }

            valueArguments = valueType.GetGenericArguments()
        }

        current := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(
            structRegistry.get_Values(),
            valueBuilder
        )
        depth := 0
        while current != null && depth < 64 {
            index := 0
            while index < current.ImplementedInterfaceTypes.Count {
                candidate := current.ImplementedInterfaceTypes[index]
                if valueArguments.Length > 0 {
                    candidate = ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(candidate, valueArguments)
                }

                if ColumnarReferenceConversionFacts.ExactTypeShapeMatches(candidate, targetType) {
                    return true
                }

                index += 1
            }

            // ONLY THE DECLARATION THAT WROTE THE EDGE. A base class's interface list is spelled in
            // the BASE's parameters, so mapping this instantiation's arguments onto it by position
            // would be a guess across a different parameter list; the bare case keeps the walk, and a
            // constructed one stops here rather than guessing.
            if valueArguments.Length > 0 {
                return false
            }

            current = current.BaseDef
            depth += 1
        }

        return false
    }

    static func TryEmitInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>,
        il: ILGenerator
    ): bool {
        if !CanUseInterfaceUpcast(valueType, targetType, structRegistry) {
            return false
        }

        // A CONSTRUCTED SOURCE IMPLEMENTER — `GenBox<string>` into `IBox<string>` — is not a
        // `TypeBuilder`, so the shape question is asked of its DEFINITION while the `box` (which a
        // value implementer still needs) names the constructed handle the value actually has.
        valueBuilder := valueType as TypeBuilder
        definitionBuilder := valueBuilder
        if definitionBuilder == null {
            if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
                return false
            }

            definitionBuilder = valueType.GetGenericTypeDefinition() as TypeBuilder
            if definitionBuilder == null {
                return false
            }
        }

        valueDefinition := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(
            structRegistry.get_Values(),
            definitionBuilder
        )
        if valueDefinition == null {
            return false
        }
        if !valueDefinition.IsReference {
            il.Emit(OpCodes.Box, valueType)
        }
        return true
    }

    // A SOURCE TYPE FLOWING INTO AN EXTERNAL INTERFACE IT IMPLEMENTS — `Plain` into
    // `IEquatable<Plain>`, `Outcome<int, string>` into `IEquatable<Outcome<int, string>>`,
    // `Node` into `IDisposable`. Whether the edge exists is not this planner's question:
    // `ColumnarReferenceConversionFacts` owns the declaration walk (and reports whether the
    // implementer is a reference), so selection, preflight and emission cannot disagree about it.
    // What is owned here is the EMISSION: a value implementer boxes, a reference implementer needs
    // no instruction at all.
    //
    // Source-declared interface targets keep `CanUseInterfaceUpcast` as their owner; a target that
    // is itself a source declaration is refused here so the two never answer the same question.
    static func TryClassifyExternalInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>,
        out valueIsReference: bool
    ): bool {
        valueIsReference = false
        if !targetType.get_IsInterface() || ColumnarReferenceConversionFacts.IsDynamicDeclarationType(targetType) {
            return false
        }
        return ColumnarReferenceConversionFacts.TryClassifyExactSourceInterfaceUpcast(
            valueType,
            targetType,
            structRegistry.get_Values(),
            out valueIsReference
        )
    }

    static func CanUseExternalInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): bool {
        valueIsReference := false
        return TryClassifyExternalInterfaceUpcast(valueType, targetType, structRegistry, out valueIsReference)
    }

    static func TryEmitExternalInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>,
        il: ILGenerator
    ): bool {
        valueIsReference := false
        if !TryClassifyExternalInterfaceUpcast(valueType, targetType, structRegistry, out valueIsReference) {
            return false
        }
        if !valueIsReference {
            il.Emit(OpCodes.Box, valueType)
        }
        return true
    }

    static func CanUseObjectConversion(source: Type, target: Type): bool {
        return target == typeof(object) && source != ColumnarTypeOfPlanner.RequiredVoidType()
    }

    static func TryEmitObjectConversion(
        source: Type,
        target: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>,
        il: ILGenerator
    ): bool {
        if target != typeof(object) || source == ColumnarTypeOfPlanner.RequiredVoidType() {
            return false
        }
        if source == typeof(object) {
            return true
        }

        sourceBuilder := source as TypeBuilder
        if sourceBuilder != null {
            if ColumnarTypeOfPlanner.IsEnumType(sourceBuilder) {
                il.Emit(OpCodes.Box, sourceBuilder)
                return true
            }

            sourceDefinition := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(
                structRegistry.get_Values(),
                sourceBuilder
            )
            if sourceDefinition != null && !sourceDefinition.IsReference {
                il.Emit(OpCodes.Box, sourceBuilder)
            }
            return true
        }

        if source.get_IsValueType() || source.get_IsGenericParameter() || ColumnarTypeOfPlanner.IsEnumType(source) {
            il.Emit(OpCodes.Box, source)
        }
        return true
    }

    static func RequiresBoxBeforeReferenceTest(
        source: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): bool {
        sourceBuilder := source as TypeBuilder
        if sourceBuilder != null {
            if ColumnarTypeOfPlanner.IsEnumType(sourceBuilder) {
                return true
            }
            sourceDefinition := ColumnarSourceDefinitionResolver.FindByBuilderIdentity(
                structRegistry.get_Values(),
                sourceBuilder
            )
            return sourceDefinition != null && !sourceDefinition.IsReference
        }

        if source.get_IsGenericParameter() {
            try {
                attributes := source.get_GenericParameterAttributes()
                attributeBits := (int)attributes
                // GenericParameterAttributes.ReferenceTypeConstraint is bit 4.
                return (attributeBits & 4) == 0
            } catch ex: NotSupportedException {
                return true
            }
        }
        return source.get_IsValueType() || ColumnarTypeOfPlanner.IsEnumType(source)
    }
}
