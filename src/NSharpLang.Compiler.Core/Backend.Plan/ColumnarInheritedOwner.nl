namespace NSharpLang.Compiler.Columnar

import System


// HOW A RECEIVER NAMES ONE LINK OF ITS SOURCE BASE CHAIN.
//
// A member a source type inherits from a SOURCE base is declared on that base's builder, and a
// builder that is a generic definition names the OPEN type. `class IntHolder: Holder<int>` inherits
// `Describe` from `Holder<T>`, but the member `IntHolder` actually has is `Holder<int>::Describe` —
// a MemberRef whose parent is the TypeSpec `Holder<int>`. Binding the open definition's method (or
// its self-instantiation `Holder<T>`) against an `IntHolder` receiver is a receiver the plan
// executor rightly refuses: `IntHolder` is not a `Holder<T>` for the definition's own `T`.
//
// SUBSTITUTION IS PER LINK, as in `ColumnarInheritedExternalBase`. A link's declared base
// (`ExactBaseType`) is written in that link's own type parameters, so it is closed over the
// arguments the receiver carries for that link: `Mid<string> : Holder<List<U>>` answers
// `Holder<List<string>>`. A receiver that is a bare builder carries no arguments and substitutes
// nothing, which leaves a base written in the builder's own parameters (`class Derived<U>:
// Holder<U>`) as exactly the instantiation `Derived<U>`'s own code must name.
class ColumnarInheritedOwner {

    // The type the receiver names `baseDefinition` by, given the type it names `current` by. A link
    // with no recorded base handle keeps the base's own builder, which is the pre-existing answer for
    // every non-generic chain.
    static func BaseOwner(current: ColumnarStructDef, currentOwnerType: Type, baseDefinition: ColumnarStructDef): Type {
        if current == null || currentOwnerType == null || baseDefinition == null {
            throw new InvalidOperationException("Inherited source owner facts cannot be null.")
        }

        declaredBase := current.ExactBaseType
        if declaredBase == null {
            return baseDefinition.Builder
        }

        return ColumnarInheritedExternalBase.Substitute(declaredBase, ColumnarInheritedExternalBase.ArgumentsOf(currentOwnerType))
    }

    // The constructed instantiation the receiver names the link declared by `declaringBuilder` through,
    // walking down from `root`, which the receiver names as `rootOwnerType`. Null when that link is
    // named by its own builder (a non-generic base, or the root itself) or the chain never reaches
    // it: the member's own handle is then already the right one.
    static func ConstructedOwnerOf(root: ColumnarStructDef, rootOwnerType: Type, declaringBuilder: Type): Type? {
        if root == null || rootOwnerType == null || declaringBuilder == null {
            throw new InvalidOperationException("Inherited source owner facts cannot be null.")
        }

        current: ColumnarStructDef? = root
        ownerType := rootOwnerType
        guard := 0
        while current != null && guard <= 200 {
            currentBuilder: Type = current.Builder
            if currentBuilder == declaringBuilder {
                return IsConstructedLink(current, ownerType) ? ownerType : null
            }

            baseDefinition := current.BaseDef
            if baseDefinition != null {
                ownerType = BaseOwner(current, ownerType, baseDefinition)
            }
            current = baseDefinition
            guard = guard + 1
        }

        return null
    }

    // Whether `ownerType` is a CONSTRUCTED instantiation of `definition` — a link whose members must
    // be rebound onto that instantiation — rather than the definition's own builder.
    static func IsConstructedLink(definition: ColumnarStructDef, ownerType: Type): bool {
        if definition == null || ownerType == null {
            throw new InvalidOperationException("Inherited source owner facts cannot be null.")
        }

        builderType: Type = definition.Builder
        return ownerType != builderType && ownerType.IsGenericType && !ownerType.IsGenericTypeDefinition
    }
}
