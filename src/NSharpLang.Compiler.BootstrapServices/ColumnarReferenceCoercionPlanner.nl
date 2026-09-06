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
            return false
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

    static func TryEmitInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>,
        il: ILGenerator
    ): bool {
        if !CanUseInterfaceUpcast(valueType, targetType, structRegistry) {
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
        if !valueDefinition.IsReference {
            il.Emit(OpCodes.Box, valueBuilder)
        }
        return true
    }

    static func CanUseExternalInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>
    ): bool {
        if !targetType.get_IsInterface() {
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

        externalEnumerator := valueDefinition.ExternalInterfaces.GetEnumerator()
        try {
            while externalEnumerator.MoveNext() {
                externalInterface := externalEnumerator.get_Current()
                if externalInterface == targetType || targetType.IsAssignableFrom(externalInterface) {
                    return true
                }
            }
        } finally {
            externalEnumerator.Dispose()
        }
        return false
    }

    static func TryEmitExternalInterfaceUpcast(
        valueType: Type,
        targetType: Type,
        structRegistry: IReadOnlyDictionary<string, ColumnarStructDef>,
        il: ILGenerator
    ): bool {
        if !CanUseExternalInterfaceUpcast(valueType, targetType, structRegistry) {
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

        externalEnumerator := valueDefinition.ExternalInterfaces.GetEnumerator()
        try {
            while externalEnumerator.MoveNext() {
                externalInterface := externalEnumerator.get_Current()
                if externalInterface == targetType || targetType.IsAssignableFrom(externalInterface) {
                    if !valueDefinition.IsReference {
                        il.Emit(OpCodes.Box, valueBuilder)
                    }
                    return true
                }
            }
        } finally {
            externalEnumerator.Dispose()
        }
        return false
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
