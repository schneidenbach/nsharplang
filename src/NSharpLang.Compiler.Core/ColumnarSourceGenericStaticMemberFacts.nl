namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// THE ONE OWNER OF "WHICH STATIC FIELD OR PROPERTY DOES `Name<Args>.Member` NAME, AND WHICH HANDLE
// READS OR WRITES IT".
//
// A static member of a generic type is declared ONCE, on the OPEN `TypeBuilder`, and the CLR gives
// every constructed instantiation its own storage — `PerTypeState<int>.Count` and
// `PerTypeState<string>.Count` are two slots of one `FieldBuilder`, and the type initializer that
// seeds them runs once per instantiation. Nothing here creates that separation; it is the CLR's by
// construction. What the emitter must do is name the member THROUGH the instantiation, and
// Reflection.Emit spells that as `TypeBuilder.GetField` / `TypeBuilder.GetMethod` over the
// constructed type — the same rebinding `new Box<int>(v)` already does for a constructor and a
// closed instance call already does for a method. A raw `FieldBuilder` token would name the open
// definition, which is not storage any instantiation has.
//
// THE MEMBER TYPE SUBSTITUTES POSITIONALLY: `static Head: T` read through `Stack<int>` is an `int`.
//
// A BASE DECLARATION KEEPS ITS OWN INSTANTIATION. `Derived<T> : Base<T>` reached as `Derived<int>`
// declares nothing itself, so a static member found on `Base` is named through `Base<int>` — the
// recorded base template with the derived instantiation's arguments substituted in, one link at a
// time so a chain of generic bases composes. The STATIC METHOD counterpart of this is not here: an
// invocation is the semantic call planner's, and `ColumnarSourceDirectCallResolver` already selects
// and rebinds a static overload on a closed source receiver.
class ColumnarSourceGenericStaticMemberFacts {

    // The exact type that DECLARES `name`, walking the base chain nearest-first from the receiver's
    // own instantiation. `staticFields` picks which member table the walk asks about, because the
    // walk itself is one algorithm and only the question differs.
    static func TryFindDeclaringType(receiverType: Type, receiverDefinition: ColumnarStructDef, name: string, staticFields: bool, out declaringDefinition: ColumnarStructDef?, out declaringType: Type): bool {
        declaringDefinition = null
        declaringType = typeof(object)
        if receiverType == null || receiverDefinition == null || name == null || name.Length == 0 {
            return false
        }

        current: ColumnarStructDef? = receiverDefinition
        currentType := receiverType
        while current != null {
            candidate := current
            declares := staticFields ? candidate.StaticFields.ContainsKey(name) : candidate.StaticProperties.ContainsKey(name)
            if declares {
                declaringDefinition = candidate
                declaringType = currentType
                return true
            }

            baseDefinition := candidate.BaseDef
            baseTemplate := candidate.ExactBaseType
            if baseDefinition == null || baseTemplate == null {
                return false
            }

            currentArguments := ColumnarTypeOfPlanner.IsClosedSourceGeneric(currentType) ? currentType.GetGenericArguments() : new Type[](0)
            currentType = currentArguments.Length == 0 ? baseTemplate : ColumnarSourceDirectCallResolver.SubstituteTypeArguments(baseTemplate, currentArguments)
            current = baseDefinition
        }

        return false
    }

    // `TypeBuilder.GetField`/`GetMethod` are REQUIRED for a member of a constructed generic
    // `TypeBuilder` type and are INVALID for anything else, so the declaring type's shape decides. A
    // member of a plain source type keeps its own builder handle.
    static func RebindField(declaringType: Type, field: FieldBuilder): FieldInfo {
        if declaringType == null || field == null {
            throw new InvalidOperationException("Source generic static-field rebinding facts cannot be null.")
        }
        if !ColumnarTypeOfPlanner.IsClosedSourceGeneric(declaringType) {
            return field
        }

        rebound := TypeBuilder.GetField(declaringType, field)
        if rebound == null {
            throw new InvalidOperationException("TypeBuilder.GetField returned no exact closed source static field.")
        }
        return rebound
    }

    static func RebindAccessor(declaringType: Type, accessor: MethodBuilder): MethodInfo {
        if declaringType == null || accessor == null {
            throw new InvalidOperationException("Source generic static-accessor rebinding facts cannot be null.")
        }
        if !ColumnarTypeOfPlanner.IsClosedSourceGeneric(declaringType) {
            return accessor
        }

        rebound := TypeBuilder.GetMethod(declaringType, accessor)
        if rebound == null {
            throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact closed source static accessor.")
        }
        return rebound
    }

    static func Substitute(signatureType: Type, declaringType: Type): Type {
        if signatureType == null || declaringType == null {
            throw new InvalidOperationException("Source generic static-member signature facts cannot be null.")
        }
        if !ColumnarTypeOfPlanner.IsClosedSourceGeneric(declaringType) {
            return signatureType
        }
        return ColumnarSourceDirectCallResolver.SubstituteTypeArguments(signatureType, declaringType.GetGenericArguments())
    }

    // A STATIC FIELD reached through a constructed source generic: the rebound handle plus the
    // substituted storage type.
    static func TryFindStaticField(receiverType: Type, receiverDefinition: ColumnarStructDef, name: string, out field: FieldInfo, out fieldType: Type): bool {
        field = null
        fieldType = typeof(object)
        declaringDefinition: ColumnarStructDef? = null
        declaringType := typeof(object)
        if !TryFindDeclaringType(receiverType, receiverDefinition, name, true, out declaringDefinition, out declaringType) {
            return false
        }

        declared: FieldBuilder? = null
        if !declaringDefinition.StaticFields.TryGetValue(name, out declared) || declared == null {
            return false
        }

        field = RebindField(declaringType, declared)
        fieldType = Substitute(declared.get_FieldType(), declaringType)
        return true
    }

    // A STATIC PROPERTY reached through a constructed source generic. Both accessors are rebound so a
    // write through the type name has a setter to call; a get-only property answers a null setter.
    static func TryFindStaticProperty(receiverType: Type, receiverDefinition: ColumnarStructDef, name: string, out getter: MethodInfo, out setter: MethodInfo?, out propertyType: Type): bool {
        getter = null
        setter = null
        propertyType = typeof(object)
        declaringDefinition: ColumnarStructDef? = null
        declaringType := typeof(object)
        if !TryFindDeclaringType(receiverType, receiverDefinition, name, false, out declaringDefinition, out declaringType) {
            return false
        }

        declared: ColumnarPropertyDef? = null
        if !declaringDefinition.StaticProperties.TryGetValue(name, out declared) || declared == null {
            return false
        }

        getter = RebindAccessor(declaringType, declared.Getter)
        if declared.Setter != null {
            setter = RebindAccessor(declaringType, declared.Setter)
        }
        propertyType = Substitute(declared.PropertyType, declaringType)
        return true
    }
}
