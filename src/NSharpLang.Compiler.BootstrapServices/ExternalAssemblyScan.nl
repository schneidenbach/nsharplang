namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices

enum ExternalAssemblyTypeLookupStatus {
    Missing,
    Found,
    Unknown
}

class ExternalAssemblyTypeResolution {
    Status: ExternalAssemblyTypeLookupStatus
    SemanticTypeIdentity: string
    RuntimeType: Type
    HasRuntimeType: bool

    constructor(status: ExternalAssemblyTypeLookupStatus, semanticTypeIdentity: string, runtimeType: Type, hasRuntimeType: bool) {
        Status = status
        SemanticTypeIdentity = semanticTypeIdentity
        RuntimeType = runtimeType
        HasRuntimeType = hasRuntimeType
    }
}

class ExternalAssemblyCatalogEntry {
    IdentityName: AssemblyName?
    Identity: string
    MetadataPath: string
    MetadataAssembly: Assembly?
    RuntimeAssembly: Assembly?
    IsInspectable: bool

    constructor(identityName: AssemblyName?, identity: string, metadataPath: string, runtimeAssembly: Assembly?, isInspectable: bool) {
        IdentityName = identityName
        Identity = identity
        MetadataPath = metadataPath
        MetadataAssembly = null
        RuntimeAssembly = runtimeAssembly
        IsInspectable = isInspectable
    }

    func AttachRuntimeAssembly(runtimeAssembly: Assembly?) {
        RuntimeAssembly = runtimeAssembly
    }

    func AttachMetadataAssembly(metadataAssembly: Assembly) {
        MetadataAssembly = metadataAssembly
    }

    func MarkUninspectable() {
        IsInspectable = false
        MetadataAssembly = null
    }
}

class ExternalAssemblyScanResult {
    Entries: ExternalAssemblyCatalogEntry[]
    Context: MetadataLoadContext?

    constructor(entries: ExternalAssemblyCatalogEntry[], context: MetadataLoadContext?) {
        Entries = entries
        Context = context
    }

    func Dispose() {
        if Context != null {
            Context.Dispose()
            Context = null
        }
    }
}

// Metadata determines binding; an exact runtime implementation only supplies the Reflection.Emit
// handle. The two identities must match byte-for-byte. Arbitrary AppDomain assemblies never enter
// semantic order, and a broken later slot cannot invalidate an earlier winner.
class ExternalAssemblyScan {
    static func Loaded(): Assembly[] {
        assemblies := AppDomain.CurrentDomain.GetAssemblies()
        loaded := new List<Assembly>()
        index := 0
        while index < assemblies.Length {
            assembly := assemblies[index]
            if !assembly.IsDynamic && !assembly.IsCollectible {
                loaded.Add(assembly)
            }

            index = index + 1
        }

        return loaded.ToArray()
    }

    // The same snapshot `Loaded` returns, keyed by assembly full name in load order so an exact
    // identity is one hash lookup instead of a walk of every loaded assembly per reference path.
    // FIRST WINS, exactly as the walk's first match did; an assembly whose name cannot be read is
    // skipped, exactly as the walk's per-assembly catch skipped it.
    static func LoadedByIdentity(): Dictionary<string, Assembly> {
        byIdentity := new Dictionary<string, Assembly>(StringComparer.Ordinal)
        assemblies := Loaded()
        index := 0
        while index < assemblies.Length {
            assembly := assemblies[index]
            try {
                identity := assembly.GetName().get_FullName()
                if !byIdentity.ContainsKey(identity) {
                    byIdentity[identity] = assembly
                }
            } catch {
            }

            // A hostile loaded assembly is not semantic evidence; keep indexing.

            index = index + 1
        }

        return byIdentity
    }

    static func OpenWithReferences(referenceAssemblyPaths: IReadOnlyList<string>?): ExternalAssemblyScanResult {
        entries := new List<ExternalAssemblyCatalogEntry>()
        searchDirectories := CommonAssemblySearchDirectories(referenceAssemblyPaths)
        commonNames := CommonAssemblyNames()
        commonIndex := 0
        while commonIndex < commonNames.Length {
            name := commonNames[commonIndex]
            try {
                runtimeAssembly := Assembly.Load(name)
                identityName := runtimeAssembly.GetName()
                identity := identityName.get_FullName()
                metadataPath := CommonAssemblyMetadataPath(searchDirectories, name)
                AddSemanticEntry(entries, identityName, identity, metadataPath, runtimeAssembly)
            } catch {
                entries.Add(new ExternalAssemblyCatalogEntry(null, "unresolved-common:" + name, "", null, false))
            }

            commonIndex = commonIndex + 1
        }

        runtimeAssemblies := LoadedByIdentity()
        if referenceAssemblyPaths != null {
            pathIndex := 0
            while pathIndex < referenceAssemblyPaths.Count {
                path := referenceAssemblyPaths[pathIndex]
                if path == null || path.Length == 0 {
                    entries.Add(new ExternalAssemblyCatalogEntry(null, "unresolved-path:" + pathIndex.ToString(), "", null, false))

                    pathIndex = pathIndex + 1
                    continue
                }

                identityName: AssemblyName? = null
                try {
                    identityName = AssemblyName.GetAssemblyName(path)
                } catch {
                    entries.Add(new ExternalAssemblyCatalogEntry(null, "unresolved-path:" + path, "", null, false))

                    pathIndex = pathIndex + 1
                    continue
                }

                identity := identityName.get_FullName()
                existing := FindSemanticIdentity(entries, identityName)
                if existing >= 0 {
                    if entries[existing].Identity == identity && entries[existing].RuntimeAssembly == null {
                        exactRuntime := TryLoadExactRuntimeAssembly(runtimeAssemblies, path, identity)

                        entries[existing].AttachRuntimeAssembly(exactRuntime)
                    }

                    pathIndex = pathIndex + 1
                    continue
                }

                runtimeAssembly := TryLoadExactRuntimeAssembly(runtimeAssemblies, path, identity)

                AddSemanticEntry(entries, identityName, identity, path, runtimeAssembly)

                pathIndex = pathIndex + 1
            }
        }

        resolverPaths := new List<string>()
        entryIndex := 0
        while entryIndex < entries.Count {
            entry := entries[entryIndex]
            if entry.IsInspectable && entry.MetadataPath.Length > 0 {
                resolverPaths.Add(entry.MetadataPath)
            }

            entryIndex = entryIndex + 1
        }

        context: MetadataLoadContext? = null
        try {
            context = CreateMetadataLoadContext(resolverPaths.ToArray())
        } catch {
            entryIndex = 0
            while entryIndex < entries.Count {
                entries[entryIndex].MarkUninspectable()
                entryIndex = entryIndex + 1
            }

            return new ExternalAssemblyScanResult(entries.ToArray(), null)
        }

        entryIndex = 0
        while entryIndex < entries.Count {
            entry := entries[entryIndex]
            if entry.IsInspectable {
                try {
                    metadataAssembly := context.LoadFromAssemblyPath(entry.MetadataPath)
                    entry.AttachMetadataAssembly(metadataAssembly)
                } catch {
                    entry.MarkUninspectable()
                }
            }

            entryIndex = entryIndex + 1
        }

        return new ExternalAssemblyScanResult(entries.ToArray(), context)
    }

    // WHERE A COMMON ASSEMBLY'S METADATA IS, FOUND ON DISK RATHER THAN READ OFF A LOADED ASSEMBLY.
    // `runtimeAssembly.get_Location()` answers the EMPTY STRING under a single-file binary -- measured,
    // not assumed -- and an entry with an empty metadata path is not inspectable, so the metadata
    // context would quietly be handed nothing and every common assembly would drop out of binding with
    // no error anywhere. The path is therefore resolved from DIRECTORIES.
    //
    // The runtime directory comes FIRST deliberately. It is the directory `get_Location()` used to
    // answer out of, so for a framework-dependent host every one of the 27 common names resolves to the
    // byte-identical file the old reading returned, and the change moves nothing. The project's own
    // resolved reference directories come after, as the answer for a name the runtime directory does
    // not carry -- never as an override of one it does, because a reference-pack facade and a runtime
    // implementation of the same name do not carry the same types.
    static func CommonAssemblySearchDirectories(referenceAssemblyPaths: IReadOnlyList<string>?): string[] {
        directories := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        runtimeDirectory := RuntimeEnvironment.GetRuntimeDirectory()
        if runtimeDirectory != null && runtimeDirectory.Length > 0 {
            AddUniquePath(directories, seen, runtimeDirectory)
        }

        if referenceAssemblyPaths != null {
            pathIndex := 0
            while pathIndex < referenceAssemblyPaths.Count {
                path := referenceAssemblyPaths[pathIndex]
                if path != null && path.Length > 0 {
                    directory := Path.GetDirectoryName(path) ?? ""
                    if directory.Length > 0 {
                        AddUniquePath(directories, seen, directory)
                    }
                }

                pathIndex = pathIndex + 1
            }
        }

        return directories.ToArray()
    }

    // First directory that carries `<name>.dll` wins. An empty answer marks the entry uninspectable,
    // exactly as an empty `Location` did -- the difference is that it can now only happen when the file
    // is genuinely absent, not because the host is single-file.
    static func CommonAssemblyMetadataPath(searchDirectories: string[], name: string): string {
        fileName := name + ".dll"
        index := 0
        while index < searchDirectories.Length {
            candidate := Path.Combine(searchDirectories[index], fileName)
            if File.Exists(candidate) {
                return candidate
            }

            index = index + 1
        }

        return ""
    }

    // Existing project.yml DLL references can be relative to the project root. Selection and path
    // normalization live here in N#; MultiFileCompiler only routes the resulting ordered strings.
    static func ResolveReferencePaths(projectRoot: string, dependencies: IReadOnlyList<Reference>?): IReadOnlyList<string> {
        return CanonicalizeReferencePaths(ResolveConfiguredDllPaths(projectRoot, dependencies))
    }

    // Runtime copy-local selection is distinct from metadata selection. Normal DLLs copy
    // themselves; ref/refint inputs copy only an exact paired runtime implementation when one
    // exists. A metadata-only reference remains inspectable but is never deployed as executable IL.
    static func ResolveRuntimeAssetPaths(projectRoot: string, dependencies: IReadOnlyList<Reference>?): IReadOnlyList<string> {
        configuredPaths := ResolveConfiguredDllPaths(projectRoot, dependencies)
        runtimePaths := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        index := 0
        while index < configuredPaths.Count {
            path := configuredPaths[index]
            runtimePath := GetRuntimePathCandidate(path)
            if runtimePath.Length > 0 {
                if IsExactAssemblyPair(path, runtimePath) {
                    AddUniquePath(runtimePaths, seen, runtimePath)
                }
            } else if File.Exists(path) {
                AddUniquePath(runtimePaths, seen, path)
            }

            index = index + 1
        }

        return runtimePaths
    }

    static func ResolveConfiguredDllPaths(projectRoot: string, dependencies: IReadOnlyList<Reference>?): List<string> {
        normalizedPaths := new List<string>()
        if dependencies == null {
            return normalizedPaths
        }

        normalizedProjectRoot := Path.GetFullPath(projectRoot)
        index := 0
        while index < dependencies.Count {
            dependency := dependencies[index]
            if dependency != null && dependency.Type == ReferenceType.Dll && !string.IsNullOrWhiteSpace(dependency.Dll ?? "") {
                path := dependency.Dll ?? ""
                if !Path.IsPathRooted(path) {
                    path = Path.Combine(normalizedProjectRoot, path)
                }

                normalizedPaths.Add(Path.GetFullPath(path))
            }

            index = index + 1
        }

        return normalizedPaths
    }

    // A restored package contributes a reference assembly for binding and a runtime assembly for
    // Reflection.Emit. The CLI resolver already supplies both. MSBuild's ReferencePath supplies
    // only the reference side, so recover the exact paired runtime path from standard NuGet and
    // project-output layouts. Reference metadata remains usable when no runtime pair exists.
    static func CanonicalizeReferencePaths(normalizedPaths: List<string>): IReadOnlyList<string> {
        paths := new List<string>()
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        index := 0
        while index < normalizedPaths.Count {
            path := normalizedPaths[index]
            referencePath := FindReferencePathForRuntime(normalizedPaths, path)

            if referencePath.Length > 0 {
                AddUniquePath(paths, seen, referencePath)
                AddUniquePath(paths, seen, path)
                index = index + 1
                continue
            }

            AddUniquePath(paths, seen, path)
            runtimePath := GetRuntimePathCandidate(path)
            if runtimePath.Length > 0 && IsExactAssemblyPair(path, runtimePath) {
                AddUniquePath(paths, seen, runtimePath)
            }

            index = index + 1
        }

        return paths
    }

    static func FindReferencePathForRuntime(paths: List<string>, runtimePath: string): string {
        index := 0
        while index < paths.Count {
            referencePath := paths[index]
            candidate := GetRuntimePathCandidate(referencePath)
            if candidate.Length > 0 && string.Equals(candidate, runtimePath, StringComparison.OrdinalIgnoreCase) && IsExactAssemblyPair(referencePath, runtimePath) {
                return referencePath
            }

            index = index + 1
        }

        return ""
    }

    static func IsExactAssemblyPair(referencePath: string, runtimePath: string): bool {
        if !File.Exists(referencePath) || !File.Exists(runtimePath) {
            return false
        }

        try {
            referenceIdentity := AssemblyName.GetAssemblyName(referencePath).get_FullName()
            runtimeIdentity := AssemblyName.GetAssemblyName(runtimePath).get_FullName()
            return referenceIdentity != null && runtimeIdentity != null && string.Equals(referenceIdentity, runtimeIdentity, StringComparison.Ordinal)
        } catch {

            // Invalid or hostile images cannot establish an executable pairing.
            return false
        }
    }

    static func GetRuntimePathCandidate(referencePath: string): string {
        fileName := Path.GetFileName(referencePath)
        referenceDirectory := Path.GetDirectoryName(referencePath)
        if string.IsNullOrWhiteSpace(fileName) || string.IsNullOrWhiteSpace(referenceDirectory ?? "") {
            return ""
        }

        // MSBuild project references normally point at
        // obj/<configuration>/<tfm>/{ref,refint}/Assembly.dll.
        referenceDirectoryName := Path.GetFileName(referenceDirectory ?? "")
        if string.Equals(referenceDirectoryName, "ref", StringComparison.OrdinalIgnoreCase) || string.Equals(referenceDirectoryName, "refint", StringComparison.OrdinalIgnoreCase) {
            targetFrameworkDirectory := Path.GetDirectoryName(referenceDirectory ?? "")

            configurationDirectory := Path.GetDirectoryName(targetFrameworkDirectory ?? "")

            objectDirectory := Path.GetDirectoryName(configurationDirectory ?? "")

            projectDirectory := Path.GetDirectoryName(objectDirectory ?? "")
            if string.Equals(Path.GetFileName(objectDirectory ?? ""), "obj", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(projectDirectory ?? "") {
                configuration := Path.GetFileName(configurationDirectory ?? "")

                targetFramework := Path.GetFileName(targetFrameworkDirectory ?? "")

                if !string.IsNullOrWhiteSpace(configuration) && !string.IsNullOrWhiteSpace(targetFramework) {
                    return Path.GetFullPath(Path.Combine(Path.Combine(Path.Combine(projectDirectory ?? "", "bin"), configuration), Path.Combine(targetFramework, fileName)))
                }
            }
        }

        // NuGet compile/runtime pairs use <package>/<version>/ref/<tfm> and lib/<tfm>.
        targetFrameworkDirectory := referenceDirectory ?? ""
        referenceRoot := Path.GetDirectoryName(targetFrameworkDirectory)
        packageVersionDirectory := Path.GetDirectoryName(referenceRoot ?? "")
        if string.Equals(Path.GetFileName(referenceRoot ?? ""), "ref", StringComparison.OrdinalIgnoreCase) && !string.IsNullOrWhiteSpace(packageVersionDirectory ?? "") {
            runtimeRoot := Path.Combine(packageVersionDirectory ?? "", "lib")
            runtimeDirectory := Path.Combine(runtimeRoot, Path.GetFileName(targetFrameworkDirectory))

            return Path.GetFullPath(Path.Combine(runtimeDirectory, fileName))
        }

        return ""
    }

    static func AddUniquePath(paths: List<string>, seen: HashSet<string>, path: string) {
        if seen.Add(path) {
            paths.Add(path)
        }
    }

    static func FindExactType(scan: ExternalAssemblyScanResult, fullName: string): ExternalAssemblyTypeResolution {
        if scan == null || scan.Entries == null || fullName == null || fullName.Length == 0 {
            return UnknownResolution()
        }

        index := 0
        while index < scan.Entries.Length {
            entry := scan.Entries[index]
            if entry == null || !entry.IsInspectable || entry.MetadataAssembly == null {
                return UnknownResolution()
            }

            try {
                candidate := entry.MetadataAssembly.GetType(fullName)
                if candidate != null {
                    return FoundResolution(entry, candidate)
                }
            } catch {
                return UnknownResolution()
            }

            index = index + 1
        }

        return MissingResolution()
    }

    static func FindExactOrNestedType(scan: ExternalAssemblyScanResult, fullName: string): ExternalAssemblyTypeResolution {
        resolution := FindExactType(scan, fullName)
        if resolution.Status != ExternalAssemblyTypeLookupStatus.Missing {
            return resolution
        }

        candidate := fullName
        searchEnd := candidate.Length
        while searchEnd > 0 {
            separator := -1
            index := searchEnd - 1
            while index >= 0 {
                if candidate[index] == '.' {
                    separator = index
                    index = -1
                } else {
                    index = index - 1
                }
            }

            if separator <= 0 {
                return MissingResolution()
            }

            candidate = candidate.Substring(0, separator) + "+" + candidate.Substring(separator + 1)
            resolution = FindExactType(scan, candidate)
            if resolution.Status != ExternalAssemblyTypeLookupStatus.Missing {
                return resolution
            }

            searchEnd = separator
        }

        return MissingResolution()
    }

    static func FindFirstVisibleType(scan: ExternalAssemblyScanResult, name: string): ExternalAssemblyTypeResolution {
        if scan == null || scan.Entries == null || name == null || name.Length == 0 {
            return UnknownResolution()
        }

        index := 0
        while index < scan.Entries.Length {
            entry := scan.Entries[index]
            if entry == null || !entry.IsInspectable || entry.MetadataAssembly == null {
                return UnknownResolution()
            }

            try {
                types := entry.MetadataAssembly.GetExportedTypes()
                typeIndex := 0
                while typeIndex < types.Length {
                    candidate := types[typeIndex]
                    if candidate == null {
                        return UnknownResolution()
                    }

                    if candidate.Name == name || candidate.FullName == name {
                        return FoundResolution(entry, candidate)
                    }

                    typeIndex = typeIndex + 1
                }
            } catch {
                return UnknownResolution()
            }

            index = index + 1
        }

        return MissingResolution()
    }

    static func HasExactTypeIdentity(candidate: Type, identity: string): bool {
        if candidate == null || identity == null || identity.Length == 0 {
            return false
        }

        actual := candidate.get_AssemblyQualifiedName()
        return actual != null && (actual == identity || actual.StartsWith(identity + ",", StringComparison.Ordinal))
    }

    static func SemanticIdentityMatches(semanticIdentity: string, plannedIdentity: string): bool {
        return semanticIdentity != null && plannedIdentity != null && (semanticIdentity == plannedIdentity || semanticIdentity.StartsWith(plannedIdentity + ",", StringComparison.Ordinal))
    }

    static func FoundResolution(entry: ExternalAssemblyCatalogEntry, metadataType: Type): ExternalAssemblyTypeResolution {
        identity := metadataType.get_AssemblyQualifiedName()
        fullName := metadataType.FullName
        if identity == null || fullName == null || identity.Length == 0 || fullName.Length == 0 {
            return UnknownResolution()
        }

        runtimeType := typeof(object)
        hasRuntimeType := false
        if entry.RuntimeAssembly != null {
            try {
                candidate := entry.RuntimeAssembly.GetType(fullName)
                if candidate != null && candidate.get_AssemblyQualifiedName() == identity {
                    runtimeType = candidate
                    hasRuntimeType = true
                }
            } catch {
            }
        }

        // A hostile runtime assembly cannot replace the exact metadata identity.

        return new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Found, identity, runtimeType, hasRuntimeType)
    }

    static func MissingResolution(): ExternalAssemblyTypeResolution {
        return new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Missing, "", typeof(object), false)
    }

    static func UnknownResolution(): ExternalAssemblyTypeResolution {
        return new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    }

    static func AddSemanticEntry(entries: List<ExternalAssemblyCatalogEntry>, identityName: AssemblyName, identity: string, metadataPath: string, runtimeAssembly: Assembly?) {
        if FindSemanticIdentity(entries, identityName) >= 0 {
            return
        }

        entries.Add(new ExternalAssemblyCatalogEntry(identityName, identity, metadataPath, runtimeAssembly, metadataPath.Length > 0))
    }

    static func FindSemanticIdentity(entries: List<ExternalAssemblyCatalogEntry>, identityName: AssemblyName): int {
        index := 0
        while index < entries.Count {
            existing := entries[index].IdentityName
            if existing != null && AssemblyName.ReferenceMatchesDefinition(existing, identityName) {
                return index
            }

            index = index + 1
        }

        return -1
    }

    static func TryLoadExactRuntimeAssembly(runtimeAssemblies: Dictionary<string, Assembly>, path: string, identity: string): Assembly? {
        if runtimeAssemblies.ContainsKey(identity) {
            return runtimeAssemblies[identity]
        }

        try {
            loaded := Assembly.LoadFrom(path)
            loadedName := loaded.GetName()
            if loadedName.get_FullName() == identity {
                return loaded
            }
        } catch {
        }

        // Reference assemblies and incompatible runtime images intentionally remain metadata-only.

        return null
    }

    // DIRECT CONSTRUCTION. This reflected until 022/3a: `GetConstructor` on both types, two `object[]`
    // argument arrays and two `ConstructorInfo.Invoke` calls, written that way because `new` on an
    // external type only emitted for the types on a hand-written allow-list and neither of these was on
    // it. The construction planner now selects any public constructor by argument flow, so the
    // reflection is gone -- and with it `ConstructorInfo::Invoke`, which a `MetadataLoadContext` refuses
    // outright (`Cannot invoke a method on objects loaded by a MetadataLoadContext.`), i.e. the one
    // remaining call shape that could not survive the universe this task is moving the catalog to.
    static func CreateMetadataLoadContext(paths: string[]): MetadataLoadContext {
        resolver := new PathAssemblyResolver(paths)
        return new MetadataLoadContext(resolver, "System.Runtime")
    }

    static func CommonAssemblyNames(): string[] {
        names := new string[](27)
        names[0] = "System.Runtime"
        names[1] = "System.Console"
        names[2] = "System.Collections"
        names[3] = "System.Linq"
        names[4] = "System.Linq.Queryable"
        names[5] = "System.Net.Http"
        names[6] = "System.Text.Json"
        names[7] = "System.Threading"
        names[8] = "System.Threading.Tasks"
        names[9] = "System.IO.FileSystem"
        names[10] = "System.Text.RegularExpressions"
        names[11] = "System.ComponentModel.Annotations"
        names[12] = "System.Collections.Concurrent"
        names[13] = "System.Diagnostics.Debug"
        names[14] = "System.Diagnostics.Process"
        names[15] = "System.Runtime.InteropServices"
        names[16] = "System.ObjectModel"
        names[17] = "System.Linq.Expressions"
        names[18] = "System.Memory"
        names[19] = "System.IO.Pipes"
        names[20] = "System.Net.Primitives"
        names[21] = "System.Net.Sockets"
        names[22] = "System.Security.Cryptography"
        names[23] = "System.Text.Encoding.Extensions"
        names[24] = "System.Xml.ReaderWriter"
        names[25] = "System.Private.CoreLib"
        // LINQ-to-XML, named by its IMPLEMENTATION assembly. The `System.Xml.Linq` a project
        // references is a facade of type forwarders that exports nothing a metadata scan can see, so
        // a facade entry would put a path in the resolver and still resolve no type name. The 23
        // types live here. (`System.Xml.ReaderWriter` above is the same kind of facade and admits
        // nothing either — recorded rather than changed, because nothing depends on it.)
        names[26] = "System.Private.Xml.Linq"
        return names
    }
}
