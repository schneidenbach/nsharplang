namespace NSharpLang.Compiler

import System
import System.Reflection.Emit
import NSharpLang.Compiler.Ast

// Exact semantic identity for analyzer TypeInfo values. Nominal source types are canonical
// declaration handles and therefore compare by reference; recursively composed types compare
// their shape without falling back to display-name equality for nominal leaves.
public class TypeInfoIdentityFacts {
    public static func AreEqual(left: TypeInfo, right: TypeInfo): bool {
        if Object.ReferenceEquals(left, right) {
            return true
        }
        leftByRef := left as ByRefTypeInfo
        rightByRef := right as ByRefTypeInfo
        if leftByRef != null && rightByRef != null {
            return AreEqual(leftByRef.InnerType, rightByRef.InnerType)
        }

        leftArray := left as ArrayTypeInfo
        rightArray := right as ArrayTypeInfo
        if leftArray != null && rightArray != null {
            return AreEqual(leftArray.ElementType, rightArray.ElementType)
        }

        leftNullable := left as NullableTypeInfo
        rightNullable := right as NullableTypeInfo
        if leftNullable != null && rightNullable != null {
            return AreEqual(leftNullable.InnerType, rightNullable.InnerType)
        }

        leftOblivious := left as ObliviousTypeInfo
        rightOblivious := right as ObliviousTypeInfo
        if leftOblivious != null && rightOblivious != null {
            return AreEqual(leftOblivious.InnerType, rightOblivious.InnerType)
        }

        leftGeneric := left as GenericTypeInfo
        rightGeneric := right as GenericTypeInfo
        if leftGeneric != null && rightGeneric != null {
            if leftGeneric.TypeArguments.Count != rightGeneric.TypeArguments.Count {
                return false
            }

            leftDefinition := leftGeneric.GenericDefinition
            rightDefinition := rightGeneric.GenericDefinition
            if leftDefinition != null || rightDefinition != null {
                if leftDefinition == null || rightDefinition == null
                    || !TypeDefinitionsEqual(leftDefinition, rightDefinition) {
                    return false
                }
            } else if !string.Equals(
                    leftGeneric.Name,
                    rightGeneric.Name,
                    StringComparison.Ordinal) {
                return false
            }

            argumentIndex := 0
            while argumentIndex < leftGeneric.TypeArguments.Count {
                if !AreEqual(
                        leftGeneric.TypeArguments[argumentIndex],
                        rightGeneric.TypeArguments[argumentIndex]) {
                    return false
                }
                argumentIndex = argumentIndex + 1
            }
            return true
        }

        leftTuple := left as TupleTypeInfo
        rightTuple := right as TupleTypeInfo
        if leftTuple != null && rightTuple != null {
            if leftTuple.Elements.Count != rightTuple.Elements.Count {
                return false
            }
            elementIndex := 0
            while elementIndex < leftTuple.Elements.Count {
                leftElement := leftTuple.Elements[elementIndex]
                rightElement := rightTuple.Elements[elementIndex]
                if !AreEqual(leftElement.Type, rightElement.Type) {
                    return false
                }
                elementIndex = elementIndex + 1
            }
            return true
        }

        leftUnion := left as AnonymousUnionTypeInfo
        rightUnion := right as AnonymousUnionTypeInfo
        if leftUnion != null && rightUnion != null {
            if leftUnion.Arms.Count != rightUnion.Arms.Count {
                return false
            }
            armIndex := 0
            while armIndex < leftUnion.Arms.Count {
                if !AreEqual(leftUnion.Arms[armIndex], rightUnion.Arms[armIndex]) {
                    return false
                }
                armIndex = armIndex + 1
            }
            return true
        }

        leftFunction := left as FunctionTypeInfo
        rightFunction := right as FunctionTypeInfo
        if leftFunction != null && rightFunction != null {
            leftParameters := leftFunction.ParameterTypes
            rightParameters := rightFunction.ParameterTypes
            if leftParameters == null || rightParameters == null
                || leftParameters.Count != rightParameters.Count {
                return false
            }
            if !FunctionModifiersWellFormed(leftFunction, leftParameters.Count)
                || !FunctionModifiersWellFormed(rightFunction, rightParameters.Count)
                || leftFunction.HasParamsParameter != rightFunction.HasParamsParameter {
                return false
            }
            parameterIndex := 0
            while parameterIndex < leftParameters.Count {
                if !AreEqual(
                        leftParameters[parameterIndex],
                        rightParameters[parameterIndex])
                    || FunctionParameterModifierAt(leftFunction, parameterIndex)
                        != FunctionParameterModifierAt(rightFunction, parameterIndex) {
                    return false
                }
                parameterIndex = parameterIndex + 1
            }
            leftReturn := leftFunction.ReturnType
            rightReturn := rightFunction.ReturnType
            return leftReturn != null && rightReturn != null
                && AreEqual(leftReturn, rightReturn)
        }

        leftReflection := left as ReflectionTypeInfo
        rightReflection := right as ReflectionTypeInfo
        if leftReflection != null && rightReflection != null {
            return HaveSameReflectionTypeIdentity(
                leftReflection.Type,
                rightReflection.Type)
        }

        leftSimple := left as SimpleTypeInfo
        rightSimple := right as SimpleTypeInfo
        if leftSimple != null && rightSimple != null {
            return string.Equals(
                leftSimple.Name,
                rightSimple.Name,
                StringComparison.Ordinal)
        }

        leftExternal := left as ExternalTypeInfo
        rightExternal := right as ExternalTypeInfo
        if leftExternal != null && rightExternal != null {
            return string.Equals(
                leftExternal.Name,
                rightExternal.Name,
                StringComparison.Ordinal)
        }

        leftUnknown := left as UnknownTypeInfo
        rightUnknown := right as UnknownTypeInfo
        if leftUnknown != null || rightUnknown != null {
            return leftUnknown != null && rightUnknown != null
                && leftUnknown.Kind == rightUnknown.Kind
        }

        leftRow := left as SoaRowTypeInfo
        rightRow := right as SoaRowTypeInfo
        if leftRow != null || rightRow != null {
            return leftRow != null && rightRow != null
                && Object.ReferenceEquals(
                    leftRow.Declaration,
                    rightRow.Declaration)
        }

        if IsNominalSourceType(left) || IsNominalSourceType(right) {
            return false
        }
        return false
    }

    public static func HaveSameReflectionTypeIdentity(left: Type, right: Type): bool {
        if Object.ReferenceEquals(left, right) {
            return true
        }
        if IsBuilderBound(left) || IsBuilderBound(right) {
            return false
        }

        if left.get_IsGenericParameter() || right.get_IsGenericParameter() {
            return HaveSameGenericParameterIdentity(left, right)
        }

        if left.get_IsByRef() || right.get_IsByRef() {
            if !left.get_IsByRef() || !right.get_IsByRef() {
                return false
            }
            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null && rightElement != null
                && HaveSameReflectionTypeIdentity(leftElement, rightElement)
        }

        if left.get_IsArray() || right.get_IsArray() {
            if !left.get_IsArray() || !right.get_IsArray()
                || left.GetArrayRank() != right.GetArrayRank()
                || left.get_IsSZArray() != right.get_IsSZArray() {
                return false
            }
            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null && rightElement != null
                && HaveSameReflectionTypeIdentity(leftElement, rightElement)
        }

        if left.get_IsGenericType() || right.get_IsGenericType() {
            if !left.get_IsGenericType() || !right.get_IsGenericType() {
                return false
            }

            leftDefinition := left
            if !left.get_IsGenericTypeDefinition() {
                leftDefinition = left.GetGenericTypeDefinition()
            }
            rightDefinition := right
            if !right.get_IsGenericTypeDefinition() {
                rightDefinition = right.GetGenericTypeDefinition()
            }
            if !HaveSameNonConstructedReflectionTypeIdentity(
                    leftDefinition,
                    rightDefinition) {
                return false
            }

            if left.get_IsGenericTypeDefinition()
                || right.get_IsGenericTypeDefinition() {
                return left.get_IsGenericTypeDefinition()
                    && right.get_IsGenericTypeDefinition()
            }

            leftArguments := left.GetGenericArguments()
            rightArguments := right.GetGenericArguments()
            if leftArguments.Length != rightArguments.Length {
                return false
            }
            argumentIndex := 0
            while argumentIndex < leftArguments.Length {
                if !HaveSameReflectionTypeIdentity(
                        leftArguments[argumentIndex],
                        rightArguments[argumentIndex]) {
                    return false
                }
                argumentIndex = argumentIndex + 1
            }
            return true
        }

        return HaveSameNonConstructedReflectionTypeIdentity(left, right)
    }

    public static func HasKnownRuntimeGenericDefinition(typeInfo: GenericTypeInfo): bool {
        definition := typeInfo.GenericDefinition as ReflectionTypeInfo
        if definition == null {
            return false
        }

        expectedIdentity := ""
        name := UnqualifiedTypeName(typeInfo.Name)
        if name == "IEnumerable" {
            expectedIdentity = "System.Collections.Generic.IEnumerable`1, System.Private.CoreLib"
        } else if name == "IQueryable" {
            expectedIdentity = "System.Linq.IQueryable`1, System.Linq.Expressions"
        } else if name == "ICollection" {
            expectedIdentity = "System.Collections.Generic.ICollection`1, System.Private.CoreLib"
        } else if name == "IList" {
            expectedIdentity = "System.Collections.Generic.IList`1, System.Private.CoreLib"
        } else if name == "IReadOnlyCollection" {
            expectedIdentity = "System.Collections.Generic.IReadOnlyCollection`1, System.Private.CoreLib"
        } else if name == "IReadOnlyList" {
            expectedIdentity = "System.Collections.Generic.IReadOnlyList`1, System.Private.CoreLib"
        } else if name == "List" {
            expectedIdentity = "System.Collections.Generic.List`1, System.Private.CoreLib"
        } else if name == "HashSet" {
            expectedIdentity = "System.Collections.Generic.HashSet`1, System.Private.CoreLib"
        } else if name == "Queue" {
            expectedIdentity = "System.Collections.Generic.Queue`1, System.Private.CoreLib"
        } else if name == "Stack" {
            expectedIdentity = "System.Collections.Generic.Stack`1, System.Collections"
        } else if name == "LinkedList" {
            expectedIdentity = "System.Collections.Generic.LinkedList`1, System.Collections"
        } else if name == "ISet" {
            expectedIdentity = "System.Collections.Generic.ISet`1, System.Private.CoreLib"
        } else if name == "SortedSet" {
            expectedIdentity = "System.Collections.Generic.SortedSet`1, System.Collections"
        } else if name == "Collection" {
            expectedIdentity = "System.Collections.ObjectModel.Collection`1, System.Private.CoreLib"
        } else if name == "ObservableCollection" {
            expectedIdentity = "System.Collections.ObjectModel.ObservableCollection`1, System.ObjectModel"
        } else {
            return false
        }

        expected := Type.GetType(expectedIdentity)
        return expected != null
            && HaveSameReflectionTypeIdentity(definition.Type, expected)
    }

    // Delegate definitions can arrive either from the runtime load context or from the
    // analyzer's MetadataLoadContext. Runtime Type.IsAssignableFrom cannot compare those
    // two universes, so classify the exact generic definition through its canonical CLR
    // MulticastDelegate base identity instead of through host-runtime Type objects.
    public static func IsRuntimeDelegateDefinition(typeInfo: GenericTypeInfo): bool {
        reflection := typeInfo.GenericDefinition as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        definition := reflection.Type
        if !definition.get_IsGenericType() {
            return false
        }
        if !definition.get_IsGenericTypeDefinition() {
            definition = definition.GetGenericTypeDefinition()
        }
        if definition.GetGenericArguments().Length
            != typeInfo.TypeArguments.Count {
            return false
        }

        baseType := definition.get_BaseType()
        multicastDelegate := Type.GetType(
            "System.MulticastDelegate, System.Private.CoreLib")
        return baseType != null && multicastDelegate != null
            && HaveSameReflectionTypeIdentity(
                baseType,
                multicastDelegate)
    }

    // Span<T> has a single standard widening conversion to ReadOnlySpan<T>. Keep
    // this nominal: same-spelled source types and mismatched element identities
    // must not acquire the runtime conversion accidentally.
    public static func IsRuntimeSpanToReadOnlySpanConversion(
        target: TypeInfo,
        source: TypeInfo): bool {
        targetGeneric := target as GenericTypeInfo
        sourceGeneric := source as GenericTypeInfo
        if targetGeneric == null || sourceGeneric == null
            || targetGeneric.TypeArguments.Count != 1
            || sourceGeneric.TypeArguments.Count != 1 {
            return false
        }

        targetDefinition := targetGeneric.GenericDefinition as ReflectionTypeInfo
        sourceDefinition := sourceGeneric.GenericDefinition as ReflectionTypeInfo
        if targetDefinition == null || sourceDefinition == null {
            return false
        }

        runtimeSpan := Type.GetType(
            "System.Span`1, System.Private.CoreLib")
        runtimeReadOnlySpan := Type.GetType(
            "System.ReadOnlySpan`1, System.Private.CoreLib")
        return runtimeSpan != null && runtimeReadOnlySpan != null
            && HaveSameReflectionTypeIdentity(
                sourceDefinition.Type,
                runtimeSpan)
            && HaveSameReflectionTypeIdentity(
                targetDefinition.Type,
                runtimeReadOnlySpan)
            && AreEqual(
                targetGeneric.TypeArguments[0],
                sourceGeneric.TypeArguments[0])
    }

    public static func IsInt32BackedRuntimeEnum(valueType: Type): bool {
        isRuntimeEnum := valueType.get_IsEnum()
        if !isRuntimeEnum {
            baseType := valueType.get_BaseType()
            isRuntimeEnum = baseType != null
                && baseType.FullName == "System.Enum"
        }
        return isRuntimeEnum
            && Enum.GetUnderlyingType(valueType).FullName == "System.Int32"
    }

    static func FunctionModifiersWellFormed(
        function: FunctionTypeInfo,
        parameterCount: int): bool {
        modifiers := function.ParameterModifiers
        return modifiers == null || modifiers.Count == parameterCount
    }

    static func UnqualifiedTypeName(name: string): string {
        lastDot := name.LastIndexOf(".", StringComparison.Ordinal)
        if lastDot < 0 {
            return name
        }
        return name.Substring(lastDot + 1)
    }

    static func FunctionParameterModifierAt(
        function: FunctionTypeInfo,
        parameterIndex: int): ParameterModifier {
        modifiers := function.ParameterModifiers
        if modifiers == null {
            return ParameterModifier.None
        }
        return modifiers[parameterIndex]
    }

    static func HaveSameGenericParameterIdentity(left: Type, right: Type): bool {
        if !left.get_IsGenericParameter() || !right.get_IsGenericParameter()
            || left.get_GenericParameterPosition()
                != right.get_GenericParameterPosition() {
            return false
        }
        leftMethod := left.get_DeclaringMethod()
        rightMethod := right.get_DeclaringMethod()
        if leftMethod != null || rightMethod != null {
            return leftMethod != null && rightMethod != null
                && leftMethod.Equals(rightMethod)
        }
        leftOwner := left.get_DeclaringType()
        rightOwner := right.get_DeclaringType()
        return leftOwner != null && rightOwner != null
            && HaveSameReflectionTypeIdentity(leftOwner, rightOwner)
    }

    static func IsNominalSourceType(typeInfo: TypeInfo): bool {
        return typeInfo as ClassTypeInfo != null
            || typeInfo as StructTypeInfo != null
            || typeInfo as RecordTypeInfo != null
            || typeInfo as SoaRecordTypeInfo != null
            || typeInfo as SoaRowTypeInfo != null
            || typeInfo as InterfaceTypeInfo != null
            || typeInfo as UnionTypeInfo != null
            || typeInfo as EnumTypeInfo != null
            || typeInfo as NewtypeInfo != null
    }

    static func TypeDefinitionsEqual(left: TypeInfo, right: TypeInfo): bool {
        if Object.ReferenceEquals(left, right) {
            return true
        }
        leftReflection := left as ReflectionTypeInfo
        rightReflection := right as ReflectionTypeInfo
        return leftReflection != null && rightReflection != null
            && HaveSameReflectionTypeIdentity(
                leftReflection.Type,
                rightReflection.Type)
    }

    static func HaveSameNonConstructedReflectionTypeIdentity(
        left: Type,
        right: Type): bool {
        if IsBuilderBound(left) || IsBuilderBound(right) {
            return false
        }
        return string.Equals(
                left.FullName,
                right.FullName,
                StringComparison.Ordinal)
            && string.Equals(
                left.get_Assembly().GetName().get_FullName(),
                right.get_Assembly().GetName().get_FullName(),
                StringComparison.Ordinal)
    }

    static func IsBuilderBound(valueType: Type): bool {
        return valueType is TypeBuilder
            || valueType is GenericTypeParameterBuilder
            || valueType.get_Assembly().IsDynamic
            || valueType.GetType().FullName
                == "System.Reflection.Emit.EnumBuilder"
    }
}
