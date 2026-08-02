namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

// WHICH EXTENSION METHOD A MEMBER NAME RESOLVES TO — the analyzer's extension surface.
//
// A member name that is not declared on the receiver's own shape reaches the extension surface, and
// the surface answers with the extension that claims it: a source `func` whose first parameter
// accepts the receiver, or a `[Extension]` static found in a referenced assembly under an imported
// namespace. This owner is SILENT: it reports no diagnostic and records nothing into the semantic
// model.
//
// WHAT IS HERE, AND WHAT IS NOT YET. The APPLICABILITY question — does this source extension accept
// this receiver? — is N#-owned. The two members that consume it, `TryResolveExtensionMethod` and
// `FindExternalExtensionMethods`, cannot move at the pinned toolset: the external scan enumerates a
// referenced assembly with `Assembly.GetTypes()`, which the columnar backend does not model, and
// admitting it is self-consumed catalog surface that only a toolset repin can activate. The rows are
// staged; see `systems-language-closeout/phase-b-member-resolution-contracts.md`.
//
// WHEN THE REST ARRIVES, THE THREE COLLECTIONS CROSS BY REFERENCE, NOT BY VALUE. The analyzer's
// `_extensionMethods`, `_usingNamespaces` and `_mlcAssemblies` are `readonly` fields mutated in
// place — cleared at the start of every `Analyze`, appended to as declarations and imports and
// references are walked, NEVER reassigned — so a stored reference is always the live collection.
// Snapshot none of them: an extension declared later in the same file would then be invisible. The
// containing type name is the opposite case and must NOT be held: `_currentTypeName` is a plain
// mutable field that changes every time the walk enters or leaves a type, so it crosses as a
// parameter, read at the call.
public class AnalyzerExtensionMethodResolution {

    typeResolver: AnalyzerTypeResolver
    assignability: AnalyzerAssignability

    constructor(types: AnalyzerTypeResolver, assignabilityOwner: AnalyzerAssignability) {
        typeResolver = types
        assignability = assignabilityOwner
    }

    // Does this source extension accept this receiver?
    //
    // AN UNCONSTRAINED RECEIVER ACCEPTS EVERYTHING, AND MUST ANSWER BEFORE THE REFERENCE IS
    // RESOLVED. A first parameter spelled with the function's OWN type parameter is a placeholder,
    // not a type: resolving it would answer with whichever type happens to share that name in scope
    // — a real declaration called `T`, or `unknown` — and the extension would then be offered to the
    // wrong receivers or to none. The spelling is therefore checked against the declaration's type
    // parameter list first, and only a spelling that is NOT one of them is resolved.
    //
    // A RESOLVED RECEIVER MATCHES BY IDENTITY OR BY ASSIGNABILITY, IN THAT ORDER. Identity is the
    // exact-shape answer that assignability's conversions would also give but more expensively;
    // assignability is what admits an extension declared on a base type, an interface the receiver
    // implements, or a nullable/oblivious spelling of the same underlying type.
    public func IsExtensionReceiverApplicable(candidate: FunctionDeclaration, targetType: TypeInfo): bool {
        if candidate.Parameters.Count == 0 {
            return false
        }

        receiverTypeReference := candidate.Parameters[0].Type
        simple := receiverTypeReference as SimpleTypeReference
        if simple != null && IsFunctionTypeParameter(candidate, simple.Name) {
            return true
        }

        receiverType := typeResolver.ResolveType(receiverTypeReference)
        return TypeInfoIdentityFacts.AreEqual(receiverType, targetType)
            || assignability.IsAssignable(receiverType, targetType)
    }

    // A declaration with NO type parameter list at all is not a generic function, so no spelling can
    // be one of its type parameters.
    static func IsFunctionTypeParameter(candidate: FunctionDeclaration, name: string): bool {
        typeParameters := candidate.TypeParameters
        if typeParameters == null {
            return false
        }

        index := 0
        while index < typeParameters.Count {
            if typeParameters[index].Name == name {
                return true
            }
            index = index + 1
        }

        return false
    }
}
