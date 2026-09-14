namespace NSharpLang.Cli

import System
import System.Collections.Generic
import NSharpLang.Compiler


// ── THE SDK'S IL-EMIT TASK, AND THE DECISIONS IT USED TO MAKE ITSELF ─────────────────────────────
//
// `NSharpLang.Build.Tasks.EmitIlAssembly` is the MSBuild task EVERY N# project builds through:
// `Sdk.targets` binds it out of the `tools/` directory the SDK package ships, so a decision made
// here is a decision made for every `dotnet build` of every N# project. It used to answer seventeen
// questions on its own — it was the last file on the CLI/SDK product path that consulted no N#
// owner at all — and this is where those answers live now.
//
// FOUR of them were already answered elsewhere and are DEFINED FROM those owners rather than
// re-spelled here: the `DEBUG` rule and the define list come from `BuildCommandKernels` and
// `DefineArgumentKernels`, the diagnostic id from `CompilerError.DiagnosticId`, and the resolved-
// reference dedupe from `CompilationReferenceResolverKernels.ShouldAddDllReference`.
//
// THE REFERENCE-ASSEMBLY SCOPE REWRITE IS THE LARGEST HALF, AND IT IS NOT TIDYING.
//
// The IL emitter resolves BCL types through the runtime, so an emitted type reference is scoped to
// `System.Private.CoreLib` — the one runtime assembly with NO reference-pack counterpart. That is
// correct for execution and unusable for compilation: a C# project handed such an assembly fails
// with `CS0012: The type 'Object' is defined in an assembly that is not referenced. You must add a
// reference to assembly 'System.Private.CoreLib, Version=10.0.0.0, Culture=neutral,
// PublicKeyToken=7cec85d7bea7798e'.` So the task re-points those references at whichever REFERENCED
// assembly owns the type — `System.Object` at `System.Runtime`, `List<T>` at `System.Collections` —
// and the reference assembly it writes is the whole of N#-to-C# consumability.
//
// The Mono.Cecil calls that carry this out stay in the task: reading a module, walking its type
// references and writing it back are API mechanics with no product choice in them. Every QUESTION
// they ask is here. This owner also outlives the task — when the emitter itself owns reference
// scope (021/10), the emitter reads these same answers and the post-pass disappears.

// The type-name → owning-assembly map the rewrite consults, keyed by Cecil's full name (a nested
// type is `Namespace.Outer/Inner`, so nested types are owned too). It is kept in TWO tables on
// purpose: a reference set contains both assemblies that DEFINE a type and facades that merely
// FORWARD it, the two are discovered in whatever order the reference list happens to hold, and a
// definition must win however late it arrives.
class ReferenceTypeOwners {
    Definitions: Dictionary<string, string>
    Forwarders: Dictionary<string, string>

    constructor() {
        Definitions = new Dictionary<string, string>(StringComparer.Ordinal)
        Forwarders = new Dictionary<string, string>(StringComparer.Ordinal)
    }

    // With nothing known, there is nothing to re-point.
    IsEmpty: bool => Definitions.Count == 0 && Forwarders.Count == 0

    KnownTypeCount: int => Definitions.Count + Forwarders.Count

    // A defining assembly is recorded once; the first one seen keeps the type.
    func RecordDefinition(typeFullName: string, ownerKey: string) {
        if !SdkEmitTaskKernels.ShouldRecordTypeOwner(typeFullName) {
            return
        }

        if !Definitions.ContainsKey(typeFullName) {
            Definitions.Add(typeFullName, ownerKey)
        }
    }

    // A forwarding facade is recorded the same way, in its own table.
    func RecordForwarder(typeFullName: string, ownerKey: string) {
        if !SdkEmitTaskKernels.ShouldRecordTypeOwner(typeFullName) {
            return
        }

        if !Forwarders.ContainsKey(typeFullName) {
            Forwarders.Add(typeFullName, ownerKey)
        }
    }

    // THE PRECEDENCE SENTENCE: a DEFINING assembly outranks a FORWARDING facade, whatever order
    // they were discovered in. Without it `System.Object` could be scoped to `mscorlib` or
    // `netstandard` depending on how the reference list happened to be ordered.
    func Resolve(typeFullName: string): string? {
        definition := ""
        if Definitions.TryGetValue(typeFullName, out definition) {
            return definition
        }

        forwarder := ""
        if Forwarders.TryGetValue(typeFullName, out forwarder) {
            return forwarder
        }

        return null
    }

    func Owns(typeFullName: string): bool {
        return Resolve(typeFullName) != null
    }
}

class SdkEmitTaskKernels {

    // ── CONDITIONAL COMPILATION ─────────────────────────────────────────────────────────────────
    //
    // An MSBuild-driven build must resolve `#if` exactly as `nlc` does, and the only way to promise
    // that is to ask the same owner rather than to restate the same rule. `$(Configuration)` reaches
    // `ShouldApplyDebugDefine`, and `$(DefineConstants)` reaches the very extractor `--define` uses —
    // which is why an MSBuild define list accepts `;` AND `,`, trims both ends of every symbol, drops
    // empty segments and never adds a duplicate.
    static func ApplyMsBuildDefines(config: ProjectConfig, configuration: string?, defineConstants: string?) {
        BuildCommandKernels.ApplyEffectiveDefines(config, BuildCommandKernels.ShouldApplyDebugDefine(configuration ?? ""), null)

        if defineConstants != null {
            DefineArgumentKernels.AddDefineSymbols(config.Defines, defineConstants, 0)
        }
    }

    // ── THE EMITTED ASSEMBLY'S IDENTITY AND ITS ONE MESSAGE ─────────────────────────────────────
    //
    // `project.yml` is the project file; `$(AssemblyVersion)` is only what MSBuild would have used
    // had there been no project file, so it is a fallback and never an override.
    static func ResolveProjectVersion(configVersion: string?, assemblyVersion: string?): string? {
        if !string.IsNullOrWhiteSpace(configVersion ?? "") {
            return configVersion
        }

        if !string.IsNullOrWhiteSpace(assemblyVersion ?? "") {
            return assemblyVersion
        }

        return configVersion
    }

    // The one line a successful `dotnet build` of an N# project prints from the emit task.
    static func GetEmittedAssemblyMessage(targetAssemblyPath: string): string {
        return "Emitted N# IL assembly to " + targetAssemblyPath
    }

    // Legacy analysis gates emission unless a project opts out. `Sdk.targets` spells this default in
    // MSBuild property syntax as well — a property default cannot be defined FROM an owner — so this
    // is the answer the task itself uses when MSBuild passes nothing.
    static func ValidatesWithLegacyAnalysisByDefault(): bool {
        return true
    }

    // ── THE REFERENCE-ASSEMBLY SCOPE REWRITE ────────────────────────────────────────────────────

    // The implementation core library: present at runtime, absent from every reference pack.
    static func ImplementationCoreLibraryName(): string {
        return "System.Private.CoreLib"
    }

    static func IsImplementationCoreLibrary(assemblyName: string?): bool {
        return string.Equals(assemblyName ?? "", ImplementationCoreLibraryName(), StringComparison.Ordinal)
    }

    // `<Module>` is the module pseudo-type. No source can name it, so it owns nothing.
    static func ModuleTypeName(): string {
        return "<Module>"
    }

    static func ShouldRecordTypeOwner(typeFullName: string): bool {
        return typeFullName != ModuleTypeName()
    }

    // A type reference moves ONLY when it points at the implementation core library AND a referenced
    // assembly actually owns the type. A reference the emitter already scoped correctly — the
    // `System.Console` case — is left exactly as it is.
    static func ShouldRescopeTypeReference(scopeName: string?, hasOwner: bool): bool {
        if !hasOwner {
            return false
        }

        return IsImplementationCoreLibrary(scopeName)
    }

    // Nothing known about any reference means nothing to re-point, and the reference assembly is the
    // implementation assembly byte for byte.
    static func ShouldCopyImplementationVerbatim(owners: ReferenceTypeOwners): bool {
        return owners.IsEmpty
    }

    // There is a reference assembly to synchronise only when MSBuild asked for one and the emitter
    // actually produced an implementation assembly to read.
    static func ShouldSynchronizeReferenceAssembly(referenceAssemblyPath: string?, implementationAssemblyExists: bool): bool {
        if !implementationAssemblyExists {
            return false
        }

        return !string.IsNullOrWhiteSpace(referenceAssemblyPath ?? "")
    }

    // Two build outputs are the same output when their full paths match case-insensitively — the
    // file-system rule on the platforms N# ships to, and the reason a project configured to emit its
    // reference assembly over its implementation assembly rewrites nothing.
    static func IsSameOutputPath(left: string, right: string): bool {
        return string.Equals(left, right, StringComparison.OrdinalIgnoreCase)
    }

    // A reference contributes owners when it exists on disk and is not one of the task's own two
    // outputs — a library must never be told that it owns its own types.
    static func ShouldScanReferenceForOwners(referencePath: string?, referenceExists: bool, isOwnOutput: bool): bool {
        if !referenceExists || isOwnOutput {
            return false
        }

        return !string.IsNullOrWhiteSpace(referencePath ?? "")
    }

    // An assembly reference is reused only when BOTH halves of its identity match; a version-only
    // difference is a different assembly, not the same one.
    static func AssemblyReferenceMatches(existingName: string, existingVersion: string, ownerName: string, ownerVersion: string): bool {
        if !string.Equals(existingName, ownerName, StringComparison.Ordinal) {
            return false
        }

        return string.Equals(existingVersion, ownerVersion, StringComparison.Ordinal)
    }

    // Once every type reference has moved, the implementation core library is a reference to an
    // assembly the module no longer mentions. It goes.
    static func ShouldRemoveCoreLibraryReference(hasCoreLibraryTypeReference: bool): bool {
        return !hasCoreLibraryTypeReference
    }
}
