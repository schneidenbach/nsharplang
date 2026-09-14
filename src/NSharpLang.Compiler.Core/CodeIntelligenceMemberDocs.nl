namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Reflection
import System.Runtime.InteropServices


// THE SENTENCE UNDER THE SIGNATURE, FOR A MEMBER THAT HAS NO SOURCE TO READ IT FROM.
//
// A symbol the PROJECT declares carries its documentation in the file above its declaration, and
// `CodeIntelligenceSourceDoor.DocComment` lifts it. A symbol METADATA declares has no file at all,
// so the only documentation that exists for it is the .NET XML shipped in the REFERENCE PACKS —
// the same text `nlc query doc` prints, and until this chip a hover declined it.
//
// THIS FILE IS THE BRIDGE AND NOTHING ELSE. It turns a `ReflectedMemberHandle` into an ECMA-334
// doc-comment id, hands that to `DocQuery`, and shortens the answer to one sentence. Every piece of
// it already existed for `nlc query doc`: `DocQueryReflectionFacts.GetMethodDocId` writes a method's
// id including its doc-id parameter spelling, `DocQueryKernels.GetDocMemberDocId` writes a
// property's and a field's, and `DocQuery.SummaryForDocId` owns the index. Nothing here restates a
// doc-id rule, because a second spelling of the grammar would drift from the first.
//
// EVERY FAILURE IS A DECLINE, AND THAT IS THE PRODUCT DECISION. A hover that throws is a broken
// editor, and the reference packs are an INSTALL detail: a trimmed SDK, a container image without
// them, a `DOTNET_ROOT` pointing somewhere else. A member with no documentation and a machine with
// no packs answer the same way — the signature alone, exactly as before this chip — so the feature
// can never subtract.
class CodeIntelligenceMemberDocs {

    // The first sentence of the member's XML summary, or null when there is none to be had. The
    // `DocQuery` is the CALLER'S, not a fresh one: its index is what costs, and the snapshot is
    // where it is memoized so that the second hover in a session is free.
    static func SummaryForReflectedMember(docs: DocQuery, handle: ReflectedMemberHandle): string? {
        try {
            docId := DocIdForReflectedMember(handle)
            if docId == null {
                return null
            }

            return DocQueryKernels.GetDocSummarySentence(docs.SummaryForDocId(DeclaringAssemblyLocation(handle), docId ?? ""))
        } catch {
            return null
        }
    }

    // THE PROBE ORDER IS THE HANDLE'S OWN ORDER — property, then field, then method — so the id
    // describes the same member `CodeIntelligenceSignatureKernels` just rendered a signature for.
    // A handle carrying none of the three is a member this file cannot name, and it answers null.
    static func DocIdForReflectedMember(handle: ReflectedMemberHandle): string? {
        property := handle.Property
        if property != null {
            return DocQueryKernels.GetDocMemberDocId("P:", DocQuery.DeclaringFullName(property.get_DeclaringType()), property.get_Name())
        }

        field := handle.Field
        if field != null {
            return DocQueryKernels.GetDocMemberDocId("F:", DocQuery.DeclaringFullName(field.get_DeclaringType()), field.get_Name())
        }

        method := handle.Method
        if method != null {
            // The base-typed local is not a formality: a derived value does not widen into a
            // base-typed slot at a call site, so the `MethodBase` the facts owner takes has to be
            // spelled before it is passed.
            methodBase: MethodBase = method
            return DocQueryReflectionFacts.GetMethodDocId(methodBase)
        }

        return null
    }

    // ONE PATH, USED ONLY TO FIND THE DOTNET ROOT. `DocQueryTypeIndex.SeedReferencePackDirectories`
    // climbs it looking for a directory holding both `packs` and `shared`; the XML is then read out
    // of the packs, never from beside this path.
    //
    // THE RUNTIME DIRECTORY IS THE ANSWER AND THE MEMBER'S OWN LOCATION IS THE FALLBACK, which is
    // the ordering task 022 slice 2d arrived at for the metadata path and for the same measured
    // reason: under a single-file or NativeAOT host `Assembly.get_Location()` is the EMPTY STRING,
    // and an empty seed silently produces no directories at all. `RuntimeEnvironment` is where the
    // host actually is. The member's assembly is still asked second, because a member that came
    // from somewhere else entirely — a package reference outside the shared framework — knows a
    // path the runtime directory does not.
    static func DeclaringAssemblyLocation(handle: ReflectedMemberHandle): string? {
        runtimeDirectory := RuntimeEnvironment.GetRuntimeDirectory()
        if !String.IsNullOrWhiteSpace(runtimeDirectory) {
            return runtimeDirectory
        }

        declaringType := DeclaringTypeOfReflectedMember(handle)
        if declaringType != null {
            assembly := declaringType.get_Assembly()
            return assembly.get_Location()
        }

        return null
    }

    static func DeclaringTypeOfReflectedMember(handle: ReflectedMemberHandle): Type? {
        property := handle.Property
        if property != null {
            return property.get_DeclaringType()
        }

        field := handle.Field
        if field != null {
            return field.get_DeclaringType()
        }

        method := handle.Method
        if method != null {
            return method.get_DeclaringType()
        }

        return null
    }
}
