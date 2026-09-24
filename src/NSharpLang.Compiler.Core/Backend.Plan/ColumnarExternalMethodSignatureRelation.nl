namespace NSharpLang.Compiler.Columnar

// Structural substitution for a method signature declared on an external generic type. The open
// declaring definition and the exact declaring context are explicit inputs so reflected external
// winners and iterator known-member bindings share one relation without sharing lookup policy.
class ColumnarExternalMethodSignatureRelation {
    static func DeclaringContextMatchesOpenDefinition(
        openDeclaringType: ColumnarSelectedTypeReference,
        declaringContext: ColumnarSelectedTypeReference
    ): bool {
        openKey := openDeclaringType.Key
        declaringKey := declaringContext.Key
        if openKey == null || declaringKey == null {
            return false
        }
        if declaringKey.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric {
            return declaringKey.ChildCount > 0 && ColumnarStructuralTypeKeyFacts.KeysEqual(openKey, declaringKey.Child(0))
        }
        return ColumnarStructuralTypeKeyFacts.KeysEqual(openKey, declaringKey)
    }

    static func SignatureTypesRelate(
        openSignature: ColumnarExternalMethodSignatureTypeDescriptor,
        effectiveSignature: ColumnarExternalMethodSignatureTypeDescriptor,
        openDeclaringType: ColumnarSelectedTypeReference,
        declaringContext: ColumnarSelectedTypeReference
    ): bool {
        if !KeysRelate(openSignature.Type.Key, effectiveSignature.Type.Key, openDeclaringType.Key, declaringContext.Key) || openSignature.RequiredModifierCount != effectiveSignature.RequiredModifierCount || openSignature.OptionalModifierCount != effectiveSignature.OptionalModifierCount {
            return false
        }
        index := 0
        while index < openSignature.RequiredModifierCount {
            if !KeysRelate(openSignature.RequiredModifier(index).Type.Key, effectiveSignature.RequiredModifier(index).Type.Key, openDeclaringType.Key, declaringContext.Key) {
                return false
            }
            index += 1
        }
        index = 0
        while index < openSignature.OptionalModifierCount {
            if !KeysRelate(openSignature.OptionalModifier(index).Type.Key, effectiveSignature.OptionalModifier(index).Type.Key, openDeclaringType.Key, declaringContext.Key) {
                return false
            }
            index += 1
        }
        return true
    }

    static func KeysRelate(
        openKey: ColumnarStructuralTypeKey?,
        effectiveKey: ColumnarStructuralTypeKey?,
        openDeclaringKey: ColumnarStructuralTypeKey?,
        declaringContextKey: ColumnarStructuralTypeKey?
    ): bool {
        if openKey == null || effectiveKey == null {
            return false
        }
        if openKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter && openKey.GenericOwnerKind == ColumnarStructuralGenericOwnerKind.ExternalType {
            owner := openKey.ExternalGenericOwner
            if owner != null && openDeclaringKey != null && declaringContextKey != null && ColumnarStructuralTypeKeyFacts.KeysEqual(owner.DeclaringType, openDeclaringKey) {
                if declaringContextKey.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric {
                    argumentIndex := openKey.GenericParameterOrdinal + 1
                    return argumentIndex > 0 && argumentIndex < declaringContextKey.ChildCount && ColumnarStructuralTypeKeyFacts.KeysEqual(declaringContextKey.Child(argumentIndex), effectiveKey)
                }
                return ColumnarStructuralTypeKeyFacts.KeysEqual(openKey, effectiveKey)
            }
        }
        if openKey.Kind == effectiveKey.Kind && (openKey.Kind == ColumnarStructuralTypeReferenceKind.ConstructedGeneric || openKey.Kind == ColumnarStructuralTypeReferenceKind.SzArray || openKey.Kind == ColumnarStructuralTypeReferenceKind.ByRef) {
            if openKey.ChildCount != effectiveKey.ChildCount {
                return false
            }
            index := 0
            while index < openKey.ChildCount {
                if !KeysRelate(openKey.Child(index), effectiveKey.Child(index), openDeclaringKey, declaringContextKey) {
                    return false
                }
                index += 1
            }
            return true
        }
        return ColumnarStructuralTypeKeyFacts.KeysEqual(openKey, effectiveKey)
    }
}
