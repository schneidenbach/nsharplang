namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit


// THE ONE OWNER OF "WHAT DOES A GENERIC TYPE'S OWN CODE CALL ITS OWN METHODS THROUGH".
//
// A `MethodBuilder` on a generic `TypeBuilder` is a METHOD DEFINITION, and a definition token names
// the method of the OPEN type — a type with no instantiation and therefore nothing to execute. The
// CLR says so in as many words when such a token is reached: *"Could not execute the method because
// either the method itself or the containing type is not fully instantiated."* Inside `Box<T>`'s own
// body the receiver is not the open `Box`; it is `Box<T>` — the CURRENT INSTANTIATION, the type
// closed over the definition's own type parameters — and the reference the runtime reads is a member
// reference whose parent is that instantiation. `TypeBuilder.GetMethod` over
// `definition.MakeGenericType(definition.GetGenericArguments())` is how Reflection.Emit spells it,
// and it is the same rebinding `new Box<T>(value)` inside the type already performs for the
// constructor.
//
// THE DECLARING TYPE DECIDES, AND NOTHING ELSE HAS TO. The rule is a property of the handle, not of
// the call site: a member of a non-generic source type, or of any already-constructed type, is
// returned untouched, so every site that emits a source method handle can route through here without
// first asking whether its owner happens to be generic.
class ColumnarSourceSelfInstantiation {

    // The type a generic definition's own code names itself by. A non-generic source type, or an
    // already-constructed one, is its own answer.
    static func Of(ownerType: Type): Type {
        if ownerType == null {
            throw new InvalidOperationException("Source self-instantiation owner type cannot be null.")
        }
        if !(ownerType is TypeBuilder) || !ownerType.get_IsGenericTypeDefinition() {
            return ownerType
        }
        return ownerType.MakeGenericType(ownerType.GetGenericArguments())
    }

    static func Bind(method: MethodBuilder): MethodInfo {
        if method == null {
            throw new InvalidOperationException("Source self-instantiation method handle cannot be null.")
        }

        declaringType := method.get_DeclaringType()
        if declaringType == null {
            return method
        }

        return BindOn(Of(declaringType), method)
    }

    // The same rebinding against an instantiation the caller has ALREADY built. `MakeGenericType`
    // hands back a fresh instantiation object every time, and a plan that records one handle's
    // declaring type while rebinding through another fails its own identity check — so a caller that
    // needs both the type and the member takes the type from `Of` once and passes it here.
    static func BindOn(ownerType: Type, method: MethodBuilder): MethodInfo {
        if ownerType == null || method == null {
            throw new InvalidOperationException("Source self-instantiation method handle cannot be null.")
        }

        if !ColumnarTypeOfPlanner.IsClosedSourceGeneric(ownerType) {
            return method
        }

        rebound := TypeBuilder.GetMethod(ownerType, method)
        if rebound == null {
            throw new InvalidOperationException("TypeBuilder.GetMethod returned no exact self-instantiated source method.")
        }
        return rebound
    }
}
