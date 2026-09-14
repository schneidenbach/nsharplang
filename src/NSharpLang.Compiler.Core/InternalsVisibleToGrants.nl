namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// WHICH REFERENCED ASSEMBLIES HAVE MADE THIS COMPILATION A FRIEND, AND WHAT THAT ADMITS.
//
// A referenced assembly declares `[assembly: InternalsVisibleTo("Other")]` to say that the assembly
// COMPILED UNDER THE NAME `Other` may reach the members and types it marked `internal`. The CLR
// enforces the same rule at run time, so an N# program that reaches such a member emits ordinary IL
// and needs no cast, no reflection and no special call shape — the only thing the compiler has to
// do is stop pretending the member is not there.
//
// WHY THIS OWNER EXISTS AT ALL. `Assembly.GetType` answers for internal types too, so before the
// visibility rule landed the analyzer could see EVERY internal type of EVERY reference — which made
// `System.TokenType` (internal to CoreLib) shadow a source `TokenType`. Answering only for
// `Type.IsVisible` fixed that and was right for the ordinary case, but it is one half of C#'s rule:
// C# sees the internals of exactly those assemblies that granted THIS assembly. This owner is the
// other half, and it is deliberately ONE object so that the probe, the exported-name scan, member
// resolution, extension-method discovery, attribute resolution, completion and `nlc query` cannot
// disagree about what this compilation may name.
//
// THE COMPILING ASSEMBLY NAME IS THE PROJECT'S, not a file's and not a namespace's:
// `CompilationReferenceResolverKernels.GetProjectAssemblyName` answers it from `project.yml`'s
// `name:` (falling back to the project directory), which is the name the emitted assembly carries
// and therefore the name a friend declaration has to spell. Until it is set — a bare
// `new Analyzer()` with no project behind it — NOTHING is granted, which is exactly the pre-existing
// behaviour.
//
// THE ATTRIBUTE IS READ FROM METADATA. These assemblies live in a `MetadataLoadContext`, where
// `IsDefined` and `GetCustomAttributes` throw; `GetCustomAttributesData()` is the supported reader
// and the only one used here.
//
// THE ARGUMENT IS AN ASSEMBLY DISPLAY NAME, so it may carry a public key after a comma
// (`"Tests, PublicKey=0024..."`). Only the SIMPLE name is compared, and it is compared
// case-insensitively because assembly simple names are: that is the CLR's own rule and the one
// Roslyn's friend map applies.
class InternalsVisibleToGrants {
    static InternalsVisibleToAttributeFullName: string => "System.Runtime.CompilerServices.InternalsVisibleToAttribute"

    private compilingAssemblyName: string

    // GRANTED-OR-NOT PER ASSEMBLY, KEYED BY ITS DISPLAY NAME. Reading the attribute list is a
    // metadata table walk, and every member lookup against a referenced type would otherwise repeat
    // it. The cache is cleared whenever the compiling name changes, which is the only input that can
    // change an answer: an assembly's own friend declarations are fixed in its metadata.
    private grantsByAssembly: Dictionary<string, bool>

    constructor() {
        compilingAssemblyName = ""
        grantsByAssembly = new Dictionary<string, bool>(StringComparer.Ordinal)
    }

    CompilingAssemblyName: string {
        get {
            return compilingAssemblyName
        }
    }

    func SetCompilingAssemblyName(assemblyName: string?) {
        next := assemblyName ?? ""
        if string.Equals(next, compilingAssemblyName, StringComparison.Ordinal) {
            return
        }

        compilingAssemblyName = next
        grantsByAssembly.Clear()
    }

    // Does this assembly name THIS compilation in an `InternalsVisibleTo`? An assembly with no name
    // to compare against grants nothing.
    func GrantsAccess(assembly: Assembly?): bool {
        if assembly == null || compilingAssemblyName.Length == 0 {
            return false
        }

        key := assembly.get_FullName() ?? ""
        cached := false
        if grantsByAssembly.TryGetValue(key, out cached) {
            return cached
        }

        granted := ReadGrant(assembly)
        grantsByAssembly[key] = granted
        return granted
    }

    func GrantsAccessToDeclaringAssemblyOf(member: MemberInfo?): bool {
        if member == null {
            return false
        }

        declaring := member.get_DeclaringType()
        if declaring != null {
            return GrantsAccess(declaring.get_Assembly())
        }

        return false
    }

    func GrantsAccessToAssemblyOf(candidate: Type?): bool {
        if candidate == null {
            return false
        }

        return GrantsAccess(candidate.get_Assembly())
    }

    // CAN THIS COMPILATION SPELL THIS METADATA TYPE? `Type.IsVisible` already answers for the
    // public-through-its-nesting case, and it walks the whole nesting chain, so the friend arm only
    // has to answer for what it rejects.
    //
    // The friend arm admits `internal` and `protected internal` at every level of the nesting chain
    // and nothing else. `protected` and `private protected` are NOT admitted here even though a
    // friend assembly can reach a `private protected` member, because both require a DERIVATION
    // relation that a naming question does not carry; the derived-type path in
    // `AnalyzerMemberResolution` is what answers those, and it asks this owner for the assembly half.
    func IsNameableType(candidate: Type?): bool {
        if candidate == null {
            return false
        }

        if candidate.get_IsVisible() {
            return true
        }

        if !GrantsAccess(candidate.get_Assembly()) {
            return false
        }

        current: Type? = candidate
        while current != null {
            if !current.get_IsNested() {
                return current.get_IsPublic() || current.get_IsNotPublic()
            }

            if !(current.get_IsNestedPublic() || current.get_IsNestedAssembly() || current.get_IsNestedFamORAssem()) {
                return false
            }

            current = current.get_DeclaringType()
        }

        return false
    }

    // THE ASSEMBLY HALF OF `MemberAccessibility.IsAccessible`. A source member is in the assembly
    // being compiled; a reflected member is in the assembly that declares it, and that counts as
    // "same assembly" for accessibility exactly when that assembly made this compilation a friend.
    func SameAssemblyOrFriend(declaringType: Type?): bool {
        if declaringType == null {
            return false
        }

        return GrantsAccess(declaringType.get_Assembly())
    }

    private func ReadGrant(assembly: Assembly): bool {
        attributes := assembly.GetCustomAttributesData()
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.get_AttributeType()
            if string.Equals(attributeType.FullName ?? "", InternalsVisibleToAttributeFullName, StringComparison.Ordinal) {
                arguments := attribute.get_ConstructorArguments()
                if NullabilityMetadataReflection.SequenceCount(arguments) >= 1 {
                    declared := arguments.get_Item(0).get_Value() as string
                    if declared != null && NamesCompilation(declared, compilingAssemblyName) {
                        return true
                    }
                }
            }

            index = index + 1
        }

        return false
    }

    // The simple name of a friend declaration: everything before the first comma, trimmed. An
    // `InternalsVisibleTo` argument is an assembly DISPLAY name, and the strong-name key that a
    // signed grant carries after the comma is not part of the identity N# compares — N# emits no
    // strong name, so a keyed grant that names this assembly still names it.
    static func FriendSimpleName(declaredName: string): string {
        comma := declaredName.IndexOf(",", StringComparison.Ordinal)
        if comma >= 0 {
            return declaredName.Substring(0, comma).Trim()
        }

        return declaredName.Trim()
    }

    static func NamesCompilation(declaredName: string, compilingAssemblyName: string): bool {
        if compilingAssemblyName.Length == 0 {
            return false
        }

        return string.Equals(FriendSimpleName(declaredName), compilingAssemblyName, StringComparison.OrdinalIgnoreCase)
    }
}
