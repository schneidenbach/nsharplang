namespace NSharpLang.Compiler.Performance

import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE TWO NAMES SYSTEMS POLICY DECIDES AGAINST, AND WHY NEITHER IS A DISPLAY NAME.
//
// Every systems rule that classifies a type — is it a value type, is it ref-like, how many bytes
// does one of them cost, is it a hostile surface, is it a disposable — asks the same two questions
// of the source syntax and never of the semantic model: what is this type reference CALLED, and what
// is that name's last segment. Both answers are deliberately lossy, and the loss is the point.
//
// ERASED NAME DROPS THE TYPE ARGUMENTS. `List<int>` erases to `List`, because the systems tables are
// keyed by the type CONSTRUCTOR: `List` is a hostile surface whatever it holds, `Span` is not, and
// `Result` is special-cased by arity elsewhere. This is what separates this owner from
// `TypeReferenceFacts.GetDisplayName`, which renders `List<int>` in full because it is written for
// humans reading a diagnostic. The two agree on simple, array, nullable and by-ref names and differ
// on exactly one arm, so they are NOT interchangeable and neither is redundant.
//
// THE OTHER THREE SHAPES FALL BACK TO THE DISPLAY NAME ON PURPOSE. A tuple, a function type and a
// union have no constructor name to erase to, so the erased name of `(int, int)` is its rendering.
// Those three `ToString()` overrides are themselves implemented in terms of `TypeReferenceFacts`, so
// calling `GetDisplayName` for them is the same string BY CONSTRUCTION rather than by coincidence —
// which is why this owner may call it directly instead of dispatching through `ToString()`, a
// virtual call on a `TypeReference`-typed receiver that the columnar backend declines to emit. A
// bare `TypeReference` carrying no shape at all is not something the parser builds.
//
// SIMPLE NAME IS THE LAST DOTTED SEGMENT, and it is applied to erased names and to call targets
// alike: `System.Buffers.ArrayPool` and `ArrayPool` must classify the same way, because a systems
// project may or may not have imported the namespace, and a policy that changed answer with an
// import would be unusable.
class SystemsTypeNames {

    // The last dotted segment, or the whole string when there is no dot. Never trims, never lowers:
    // a name that differs in case is a different type.
    static func SimpleName(value: string): string {
        index := value.LastIndexOf('.')
        if index >= 0 {
            return value.Substring(index + 1)
        }

        return value
    }

    // The type CONSTRUCTOR's name: type arguments erased, array/nullable/by-ref decoration kept.
    // Decoration is kept because the callers that ask about `int[]` or `&Span` need to see it — the
    // allocation rule reads the `[]`, and the ref-like rule reads the `&`.
    static func ErasedName(typeReference: TypeReference): string {
        simple := typeReference as SimpleTypeReference
        if simple != null {
            return simple.Name
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            return generic.Name
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return ErasedName(array.ElementType) + "[]"
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return ErasedName(nullable.InnerType) + "?"
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return "&" + ErasedName(byRef.InnerType)
        }

        return TypeReferenceFacts.GetDisplayName(typeReference)
    }
}
