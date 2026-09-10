namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// Type-reference resolution AS SEEN FROM A DECLARING TYPE: the analyzer's substitution-aware half of
// the resolution surface.
//
// The plain walk (`AnalyzerTypeResolver`) answers a `TypeReference` against the file being analysed.
// That is the wrong question for a member read off a DECLARED type: `class Box<T> { func Get(): T }`
// resolves `T` against `Box`'s own declaration and against the arguments the receiver supplied, not
// against whatever `T` happens to mean where the call is written. This owner is that question —
// which declaration owns a type, what substitution its arguments induce, and how a reference reads
// under one.
//
// THREE FACTS ABOUT THE OWNER LOOKUP, all measured rather than assumed:
// * a generic instantiation carries its own definition almost always (`GenericDefinition` answered
//   every one of the corpus's 6,172 lookups); the scope stack is the fallback for the instantiation
//   that does not;
// * an owner whose definition is a CLR type is NOT substituted — reflection carries its own
//   arguments, and re-substituting would double-apply them;
// * the owner-relative resolution succeeds for every reference the corpus and the suite resolve
//   (22,245 / 0 fallbacks), so the substitution walk below is the SECOND resolution path, reached
//   only when the declaration context does not own the declaring file.
//
// THE SUBSTITUTION WALK IS STRUCTURAL AND ITS ORDER IS BEHAVIOUR. A simple name that the
// substitution BINDS answers with the bound type and stops; a simple name it does not bind falls all
// the way through to the plain walk rather than to the composed arms, because only the composed
// forms below (generic, array, nullable, by-ref, tuple, function, union) have inner references
// worth rewriting. A generic head keeps
// the DEFINITION the plain walk found for it while its arguments are rewritten one by one, so the
// rewritten instantiation is still nominally the same type.
class AnalyzerTypeSubstitution {
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeResolverValue: AnalyzerTypeResolver

    constructor(scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeResolver: AnalyzerTypeResolver) {
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeResolverValue = typeResolver
    }

    // The open definition behind a generic instantiation: the one it carries, or — for an
    // instantiation built without one — the declaration its bare name resolves to in scope.
    func ResolveGenericDefinition(generic: GenericTypeInfo): TypeInfo? {
        carried := generic.GenericDefinition
        if carried != null {
            return carried
        }

        return scopesValue.LookupType(generic.Name)
    }

    // The declaration a value's type is DECLARED BY, plus the substitution its type arguments induce.
    // An alias answers for the type it names. A generic instantiation over an N#-declared definition
    // answers the DEFINITION and hands back the argument binding; every other type — including a
    // generic instantiation over a CLR definition — is its own owner under no substitution.
    func GetSourceDeclarationOwner(candidate: TypeInfo, out substitution: Dictionary<string, TypeInfo>?): TypeInfo {
        substitution = null
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        generic := resolved as GenericTypeInfo
        if generic != null {
            definition := ResolveGenericDefinition(generic)
            if definition != null {
                reflectionDefinition := definition as ReflectionTypeInfo
                if reflectionDefinition == null {
                    substitution = declarationContextValue.CreateGenericSubstitution(definition, generic.TypeArguments)
                    return definition
                }
            }
        }

        return resolved
    }

    // A reference read AGAINST a declaring type. The declaration context answers whenever it owns the
    // declaring file — which is every live case measured — and the substitution walk is the fallback
    // for a reference whose owner the context does not know.
    func ResolveTypeForSourceOwner(typeReference: TypeReference, declarationOwner: TypeInfo, substitution: Dictionary<string, TypeInfo>?): TypeInfo {
        resolved: TypeInfo = BuiltInTypes.Unknown
        if declarationContextValue.TryResolveTypeForOwner(typeReference, declarationOwner, substitution, out resolved) {
            return resolved
        }

        return ResolveTypeWithSubstitution(typeReference, substitution)
    }

    // A reference read under a type-parameter binding. With no binding this is exactly the plain
    // walk; with one, every composed form is rebuilt over rewritten inners, so a binding reaches a
    // type parameter wherever it is spelled — including inside a tuple, a function type, a by-ref
    // and an anonymous union.
    func ResolveTypeWithSubstitution(typeReference: TypeReference, substitution: Dictionary<string, TypeInfo>?): TypeInfo {
        if substitution == null {
            return typeResolverValue.ResolveType(typeReference)
        }

        simple := typeReference as SimpleTypeReference
        if simple != null {
            bound: TypeInfo = BuiltInTypes.Unknown
            if substitution.TryGetValue(simple.Name, out bound) {
                return bound
            }

            return typeResolverValue.ResolveType(typeReference)
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            return ResolveGenericTypeWithSubstitution(generic, substitution)
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return new ArrayTypeInfo(ResolveTypeWithSubstitution(array.ElementType, substitution))
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return new NullableTypeInfo(ResolveTypeWithSubstitution(nullable.InnerType, substitution))
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return new ByRefTypeInfo(ResolveTypeWithSubstitution(byRef.InnerType, substitution))
        }

        // THE PLAIN WALK RUNS FIRST ON THE THREE COMPOSED FORMS BELOW, FOR ITS EFFECTS. It records
        // each reference in the semantic model and it REPORTS the shape rules — an anonymous union
        // with more than two arms, or with a repeated one, is reported there and nowhere else — so
        // rebuilding without it would delete those diagnostics. This is the same order the generic
        // head uses: resolve plainly, then rewrite the inners under the binding.

        // A TUPLE, a FUNCTION type and a UNION mention their inner references at their leaves just
        // as a generic head does — `(T, int)`, `(T) -> TResult`, `T | string` all bind under a
        // substitution — so each is rebuilt over rewritten inners rather than handed to the plain
        // walk, which would resolve the bare parameter names against the reader's own scope.
        tupleReference := typeReference as TupleTypeReference
        if tupleReference != null {
            typeResolverValue.ResolveType(typeReference)
            elements := new List<TupleTypeElementInfo>()
            elementIndex := 0
            while elementIndex < tupleReference.Elements.Count {
                element := tupleReference.Elements[elementIndex]
                elements.Add(new TupleTypeElementInfo(element.Name, ResolveTypeWithSubstitution(element.Type, substitution)))
                elementIndex = elementIndex + 1
            }

            return new TupleTypeInfo(elements)
        }

        functionReference := typeReference as FunctionTypeReference
        if functionReference != null {
            typeResolverValue.ResolveType(typeReference)
            parameterTypes := new List<TypeInfo>()
            parameterModifiers := new List<ParameterModifier>()
            parameterIndex := 0
            while parameterIndex < functionReference.ParameterTypes.Count {
                parameterTypes.Add(ResolveTypeWithSubstitution(functionReference.ParameterTypes[parameterIndex], substitution))
                parameterModifiers.Add(ParameterModifier.None)
                parameterIndex = parameterIndex + 1
            }

            signature := new FunctionTypeInfo()
            signature.ParameterTypes = parameterTypes
            signature.ParameterModifiers = parameterModifiers
            signature.ReturnType = ResolveTypeWithSubstitution(functionReference.ReturnType, substitution)
            return signature
        }

        unionReference := typeReference as UnionTypeReference
        if unionReference != null {
            typeResolverValue.ResolveType(typeReference)
            arms := new List<TypeInfo>()
            armIndex := 0
            while armIndex < unionReference.Arms.Count {
                arms.Add(ResolveTypeWithSubstitution(unionReference.Arms[armIndex], substitution))
                armIndex = armIndex + 1
            }

            return new AnonymousUnionTypeInfo(arms)
        }

        return typeResolverValue.ResolveType(typeReference)
    }

    // A generic head under a binding. The head itself is resolved by the PLAIN walk — that is what
    // records the reference and finds the open definition — and only the arguments are rewritten, so
    // the result keeps the head's nominal identity while its arguments carry the binding.
    func ResolveGenericTypeWithSubstitution(generic: GenericTypeReference, substitution: Dictionary<string, TypeInfo>): TypeInfo {
        resolved := typeResolverValue.ResolveType(generic) as GenericTypeInfo
        genericDefinition: TypeInfo? = null
        if resolved != null {
            genericDefinition = resolved.GenericDefinition
        }

        typeArguments := new List<TypeInfo>()
        index := 0
        while index < generic.TypeArguments.Count {
            typeArguments.Add(ResolveTypeWithSubstitution(generic.TypeArguments[index], substitution))
            index = index + 1
        }

        return new GenericTypeInfo(generic.Name, typeArguments, genericDefinition)
    }
}
