namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Reflection.Metadata
import System.Reflection.PortableExecutable
import System.Runtime.CompilerServices
import System.Runtime.InteropServices
import System.Xml.Linq


// WHAT `Microsoft.NETCore.App` LETS A PROJECT NAME, AND WHICH ASSEMBLIES EACH NAMESPACE NEEDS.
//
// A project compiles against ALL of `Microsoft.NETCore.App`, exactly as `dotnet build` does: the .NET
// SDK references the shared framework in every .NETCoreApp project, and `nlc` mirrors it rather than
// keeping a hand-picked list. Before this owner a project with no `dependencies:` saw 33 assemblies
// (`ExternalAssemblyScan.CommonAssemblyNames`), so `IServiceProvider`, `ClaimsIdentity`,
// `XmlDocument`, `BigInteger`, the immutable collections, channels, `Activity`, `TypeConverter` and
// `DataTable` were NL201/NL704 under `nlc` and compiled under `dotnet build` (issue #215).
//
// WHAT "ALL OF IT" MEANS IS THE REFERENCE PACK'S ANSWER. `dotnet build` compiles against
// `packs/Microsoft.NETCore.App.Ref/<version>/ref/<tfm>/*.dll`, and the list of those assemblies is
// `packs/Microsoft.NETCore.App.Ref/<version>/data/FrameworkList.xml` -- the file the SDK's
// `ResolveTargetingPackAssets` reads. Its `Type="Managed"` rows are the COMPILE SURFACE, and that is
// what decides which namespaces a project may import. Measured on .NET 10.0.7: the 167 managed rows
// are exactly the runtime directory's 172 assemblies minus the five `System.Private.*`
// implementations, so when no reference pack is installed (a runtime-only machine) the same set is
// recovered from the runtime directory by dropping `System.Private.*`.
//
// WHERE THE METADATA IS READ FROM IS STILL THE RUNTIME DIRECTORY, and on purpose. The analyzer's
// `MetadataLoadContext` is cored on the runtime the compiler runs on
// (`AnalyzerMetadataLoadSurface.Open`) and the IL back end emits against that runtime's own types
// (`PersistedAssemblyBuilder` over `typeof(object).Assembly`), so a namespace has to be answered by
// the assemblies that actually DEFINE its types there -- `System.Xml` is defined in
// `System.Private.Xml` at run time and in `System.Xml.ReaderWriter` in the reference pack. The index
// therefore keys VISIBILITY on the reference pack and LOADS from the runtime directory: a namespace is
// importable when a compile-surface assembly declares or forwards a public type in it, and importing
// it loads every runtime assembly that defines a public type in it.
//
// LOADING IS LAZY, BECAUSE MOST OF THE FRAMEWORK IS NEVER NAMED. Reading the type tables of all 172
// assemblies with `System.Reflection.Metadata` costs tens of milliseconds and is done once per
// runtime directory per process (the workspace server and the language server keep it); putting all
// of them in front of the analyzer and the back end costs far more, because every exported-name
// sweep, extension-method scan and namespace probe then walks them all. So nothing is loaded until a
// file imports a namespace (`AnalyzerImports.MappedAssemblies`) or spells a type fully qualified
// (`AnalyzerExternalTypeProbe.TryResolveFullName`), and then only that namespace's assemblies are.
class FrameworkNamespaceIndex {

    // The runtime directory the index was read from: the directory the analyzer resolves from.
    RuntimeDirectory: string

    // `FrameworkList.xml` when the reference pack supplied the compile surface; empty when the
    // runtime directory did.
    CompileSurfaceSource: string

    // The compile surface, by assembly simple name (case-insensitive, as assembly names are).
    CompileAssemblyNames: HashSet<string>

    // Every importable namespace and the runtime assemblies that define its public types, ordered
    // ordinally by assembly name so the load order never depends on the file system's.
    private assembliesByNamespace: Dictionary<string, string[]>

    // The first segment of every importable namespace: where a spelled chain can start.
    private roots: HashSet<string>

    // THE REFERENCE PACK'S OWN TYPE NAMES, for the types a runtime implementation makes public and the
    // pack does not (`IsOnCompileSurface`). The files that carry each namespace are found when the
    // index is built; a namespace's type names are read from them the first time a type in it is
    // asked about. Null when no reference pack is installed.
    private referenceFilesByNamespace: Dictionary<string, List<string>>?

    // The namespaces where the runtime defines MORE public types than the reference pack: the only
    // ones a type can be implementation-only in. The pack is a subset of the runtime it describes, so
    // equal counts mean equal sets and no name ever has to be read for the rest.
    private implementationOnlyNamespaces: HashSet<string>
    private referenceTypeNames: Dictionary<string, HashSet<string>>
    private referenceGate: object

    private static runtimeAssemblyMarks: ConditionalWeakTable<Assembly, object> = new ConditionalWeakTable<Assembly, object>()
    private static runtimeMarker: object = new object()
    private static otherMarker: object = new object()

    private static gate: object = new object()
    private static byRuntimeDirectory: Dictionary<string, FrameworkNamespaceIndex> = new Dictionary<string, FrameworkNamespaceIndex>(StringComparer.Ordinal)
    private static registered: bool = false
    private static host: FrameworkNamespaceIndex? = null

    constructor(runtimeDirectory: string, compileSurfaceSource: string, compileAssemblyNames: HashSet<string>, namespaces: Dictionary<string, string[]>) {
        RuntimeDirectory = runtimeDirectory
        CompileSurfaceSource = compileSurfaceSource
        CompileAssemblyNames = compileAssemblyNames
        assembliesByNamespace = namespaces
        referenceFilesByNamespace = null
        implementationOnlyNamespaces = new HashSet<string>(StringComparer.Ordinal)
        referenceTypeNames = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        referenceGate = new object()
        roots = new HashSet<string>(StringComparer.Ordinal)
        for namespaceName in namespaces.Keys {
            separator := namespaceName.IndexOf('.')
            if separator < 0 {
                roots.Add(namespaceName)
            } else {
                roots.Add(namespaceName.Substring(0, separator))
            }
        }
    }

    NamespaceCount: int => assembliesByNamespace.Count

    // The runtime assemblies to load for `namespaceName`, or null when the framework's compile surface
    // has no such namespace. Namespaces are case-sensitive, as they are in metadata.
    func AssembliesForNamespace(namespaceName: string): string[]? {
        names := new string[](0)
        if assembliesByNamespace.TryGetValue(namespaceName, out names) {
            return names
        }

        return null
    }

    // THE NAMESPACE A FULLY-QUALIFIED SPELLING LIVES IN, as far as the framework can tell: the longest
    // proper dotted prefix of `fullName` that is an importable namespace. `System.Numerics.BigInteger`
    // answers `System.Numerics`; `System.Environment.SpecialFolder` (a nested type) answers `System`.
    // Null when no prefix is a framework namespace.
    func NamespaceOfTypeName(fullName: string): string? {
        if fullName == null {
            return null
        }

        end := fullName.Length
        while end > 0 {
            separator := fullName.LastIndexOf('.', end - 1)
            if separator <= 0 {
                return null
            }

            candidate := fullName.Substring(0, separator)
            if assembliesByNamespace.ContainsKey(candidate) {
                return candidate
            }

            end = separator
        }

        return null
    }

    // THE FRAMEWORK NAMESPACES A SOURCE TEXT SPELLS, imports and qualified names alike: every
    // dotted identifier chain whose first segment is a framework root namespace (`System`,
    // `Microsoft`, ...) or one of the file's namespace aliases, read as the longest prefix that is a
    // framework namespace. It is a pure function of the text, so a compilation's on-demand loads are
    // the same whichever worker analyses which file, whether a file's analysis was reused, and what
    // an earlier compilation in the same process loaded. It over-approximates on purpose -- a chain
    // in a comment or a string counts -- because a load it adds is only ever reached through its own
    // namespace (`FrameworkOnDemandLoads`), so an extra one costs time and never changes an answer.
    func SpelledNamespaces(text: string, aliases: IReadOnlyDictionary<string, string>?): List<string> {
        found := new List<string>()
        seen := new HashSet<string>(StringComparer.Ordinal)
        if text == null {
            return found
        }

        index := 0
        length := text.Length
        while index < length {
            character := text[index]
            if !IsIdentifierStart(character) || (index > 0 && (IsIdentifierPart(text[index - 1]) || text[index - 1] == '.')) {
                index = index + 1
                continue
            }

            start := index
            while index < length && (IsIdentifierPart(text[index]) || (text[index] == '.' && index + 1 < length && IsIdentifierStart(text[index + 1]))) {
                index = index + 1
            }

            chain := text.Substring(start, index - start)
            if chain.IndexOf('.') < 0 {
                continue
            }

            rootEnd := chain.IndexOf('.')
            root := chain.Substring(0, rootEnd)
            expanded := chain
            aliasTarget := ""
            if aliases != null && aliases.TryGetValue(root, out aliasTarget) {
                expanded = aliasTarget + chain.Substring(rootEnd)
            } else if !roots.Contains(root) {
                continue
            }

            namespaceName := LongestNamespacePrefix(expanded)
            if namespaceName != null && seen.Add(namespaceName) {
                found.Add(namespaceName)
            }
        }

        return found
    }

    // The chain itself when it is a framework namespace (an import line), else its longest proper
    // prefix that is one.
    func LongestNamespacePrefix(chain: string): string? {
        if assembliesByNamespace.ContainsKey(chain) {
            return chain
        }

        return NamespaceOfTypeName(chain)
    }

    static func IsIdentifierStart(character: char): bool {
        return char.IsLetter(character) || character == '_'
    }

    static func IsIdentifierPart(character: char): bool {
        return char.IsLetterOrDigit(character) || character == '_'
    }

    // ── THE ONE INDEX PER RUNTIME ─────────────────────────────────────────────────────────────────

    // The index for the runtime this compiler runs on, which is the runtime its analyzer resolves
    // framework assemblies from.
    //
    // Asked on every import and on every fully-qualified miss, so the host's index is held in a field
    // of its own rather than looked up by directory each time.
    static func ForHostRuntime(): FrameworkNamespaceIndex {
        cached := FrameworkNamespaceIndex.host
        if cached != null {
            return cached
        }

        built := ForRuntimeDirectory(RuntimeEnvironment.GetRuntimeDirectory())
        FrameworkNamespaceIndex.host = built
        return built
    }

    // Built once per runtime directory for the life of the process. An installed runtime directory is
    // immutable -- a servicing update installs a NEW versioned directory -- so the index needs no
    // invalidation beyond the warm-state trim.
    static func ForRuntimeDirectory(runtimeDirectory: string): FrameworkNamespaceIndex {
        key := Path.TrimEndingDirectorySeparator(Path.GetFullPath(runtimeDirectory))
        EnsureRegistered()
        lock FrameworkNamespaceIndex.gate {
            cached: FrameworkNamespaceIndex? = null
            if FrameworkNamespaceIndex.byRuntimeDirectory.TryGetValue(key, out cached) && cached != null {
                return cached
            }
        }

        mark := CompilerPhaseTimings.Begin("Microsoft.NETCore.App", "framework-namespace-index")
        built := Build(key)
        CompilerPhaseTimings.End(mark)
        lock FrameworkNamespaceIndex.gate {
            FrameworkNamespaceIndex.byRuntimeDirectory[key] = built
        }

        return built
    }

    static func EnsureRegistered() {
        if FrameworkNamespaceIndex.registered {
            return
        }

        FrameworkNamespaceIndex.registered = true
        WarmStateRegistry.Register(
            "framework-namespace-index",
            path => {
            },
            () => FrameworkNamespaceIndex.Clear(),
            () => FrameworkNamespaceIndex.CachedCount().ToString() + " framework namespace indexes"
        )
    }

    static func CachedCount(): int {
        lock FrameworkNamespaceIndex.gate {
            return FrameworkNamespaceIndex.byRuntimeDirectory.Count
        }
    }

    static func Clear() {
        lock FrameworkNamespaceIndex.gate {
            FrameworkNamespaceIndex.byRuntimeDirectory.Clear()
            FrameworkNamespaceIndex.host = null
        }
    }

    static func Build(runtimeDirectory: string): FrameworkNamespaceIndex {
        return Build(runtimeDirectory, FindReferencePackFrameworkList(runtimeDirectory))
    }

    static func Build(runtimeDirectory: string, frameworkList: string?): FrameworkNamespaceIndex {
        runtimeAssemblyPaths := new string[](0)
        if Directory.Exists(runtimeDirectory) {
            runtimeAssemblyPaths = Directory.GetFiles(runtimeDirectory, "*.dll", SearchOption.TopDirectoryOnly)
        }

        runtimeNames := new List<string>()
        for runtimeAssemblyPath in runtimeAssemblyPaths {
            runtimeNames.Add(Path.GetFileNameWithoutExtension(runtimeAssemblyPath))
        }

        source := ""
        compileNames: HashSet<string>? = null
        if frameworkList != null {
            try {
                compileNames = ParseFrameworkListAssemblyNames(File.ReadAllText(frameworkList))
                source = frameworkList
            } catch {
                // An unreadable list is the same as no reference pack: the runtime directory answers.
                compileNames = null
            }
        }

        if compileNames == null || compileNames.Count == 0 {
            compileNames = RuntimeCompileAssemblyNames(runtimeNames)
            source = ""
        }

        rows := new List<FrameworkNamespaceRow>()
        for runtimeAssemblyPath in runtimeAssemblyPaths {
            ReadNamespaceRows(runtimeAssemblyPath, rows)
        }

        // WITH A REFERENCE PACK, ITS OWN NAMESPACES ARE THE IMPORTABLE ONES and its own type names
        // the nameable ones: `dotnet build` compiles against the pack, so a namespace or type only an
        // implementation carries (`System.Linq.Expressions.Interpreter`, `TreeSet<T>`) is not part of
        // the framework a project sees.
        referenceDirectory: string? = null
        if frameworkList != null && source.Length > 0 {
            referenceDirectory = ReferencePackAssemblyDirectory(frameworkList, Path.GetFileName(Path.TrimEndingDirectorySeparator(runtimeDirectory)) ?? "")
        }

        if referenceDirectory == null {
            return new FrameworkNamespaceIndex(runtimeDirectory, source, compileNames, BuildNamespaceMap(rows, compileNames))
        }

        referenceRows := new List<FrameworkNamespaceRow>()
        referencePaths := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        for referencePath in Directory.GetFiles(referenceDirectory, "*.dll", SearchOption.TopDirectoryOnly) {
            referencePaths[Path.GetFileNameWithoutExtension(referencePath)] = referencePath
            ReadNamespaceRows(referencePath, referenceRows)
        }

        filesByNamespace := new Dictionary<string, List<string>>(StringComparer.Ordinal)
        for referenceRow in referenceRows {
            files: List<string>? = null
            if !filesByNamespace.TryGetValue(referenceRow.NamespaceName, out files) || files == null {
                files = new List<string>()
                filesByNamespace[referenceRow.NamespaceName] = files
            }
            files.Add(referencePaths[referenceRow.AssemblyName])
        }

        index := new FrameworkNamespaceIndex(runtimeDirectory, source, compileNames, BuildNamespaceMapFor(rows, new HashSet<string>(filesByNamespace.Keys, StringComparer.Ordinal)))
        index.referenceFilesByNamespace = filesByNamespace
        index.implementationOnlyNamespaces = ImplementationOnlyNamespaces(rows, referenceRows)
        return index
    }

    static func ImplementationOnlyNamespaces(runtimeRows: List<FrameworkNamespaceRow>, referenceRows: List<FrameworkNamespaceRow>): HashSet<string> {
        runtimeCounts := PublicTypeCounts(runtimeRows)
        referenceCounts := PublicTypeCounts(referenceRows)
        result := new HashSet<string>(StringComparer.Ordinal)
        for entry in runtimeCounts {
            referenceCount := 0
            referenceCounts.TryGetValue(entry.Key, out referenceCount)
            if referenceCount > 0 && entry.Value > referenceCount {
                result.Add(entry.Key)
            }
        }

        return result
    }

    static func PublicTypeCounts(rows: List<FrameworkNamespaceRow>): Dictionary<string, int> {
        counts := new Dictionary<string, int>(StringComparer.Ordinal)
        for row in rows {
            current := 0
            counts.TryGetValue(row.NamespaceName, out current)
            counts[row.NamespaceName] = current + row.PublicTypeCount
        }

        return counts
    }

    // `<pack>/data/FrameworkList.xml` -> `<pack>/ref/net<major>.<minor>`, the folder MSBuild compiles
    // against; null when the pack carries no such folder.
    static func ReferencePackAssemblyDirectory(frameworkList: string, runtimeVersion: string): string? {
        dataDirectory := Path.GetDirectoryName(frameworkList)
        if dataDirectory == null {
            return null
        }

        packDirectory := Path.GetDirectoryName(dataDirectory)
        if packDirectory == null {
            return null
        }

        parts := runtimeVersion.Split('.')
        if parts.Length < 2 {
            return null
        }

        candidate := Path.Combine(Path.Combine(packDirectory, "ref"), "net" + parts[0] + "." + parts[1])
        if Directory.Exists(candidate) {
            return candidate
        }

        return null
    }

    // ── WHAT THE REFERENCE PACK NAMES ─────────────────────────────────────────────────────────────

    HasReferenceSurface: bool => referenceFilesByNamespace != null

    // Whether the reference pack declares (or forwards) the top-level type `namespaceName.name`, in
    // metadata spelling (`TreeSet``1`). True for everything when no pack is installed: the runtime is
    // then the only description of the framework there is.
    func IsOnCompileSurface(namespaceName: string, name: string): bool {
        files := referenceFilesByNamespace
        if files == null {
            return true
        }

        if !files.ContainsKey(namespaceName) {
            return false
        }

        if !implementationOnlyNamespaces.Contains(namespaceName) {
            return true
        }

        lock referenceGate {
            names: HashSet<string>? = null
            if !referenceTypeNames.TryGetValue(namespaceName, out names) || names == null {
                names = ReadReferenceTypeNames(files, namespaceName)
                referenceTypeNames[namespaceName] = names
            }

            return names.Contains(name)
        }
    }

    static func ReadReferenceTypeNames(filesByNamespace: Dictionary<string, List<string>>, namespaceName: string): HashSet<string> {
        names := new HashSet<string>(StringComparer.Ordinal)
        paths: List<string>? = null
        if !filesByNamespace.TryGetValue(namespaceName, out paths) || paths == null {
            return names
        }

        for path in paths {
            ReadTopLevelNamesInNamespace(path, namespaceName, names)
        }

        return names
    }

    // The public top-level type definitions and the forwarders one file carries in one namespace.
    static func ReadTopLevelNamesInNamespace(path: string, namespaceName: string, names: HashSet<string>) {
        stream: Stream? = null
        pe: PEReader? = null
        try {
            stream = File.OpenRead(path)
            pe = new PEReader(stream)
            if !pe.HasMetadata {
                return
            }

            reader := pe.GetMetadataReader()
            current := reader.GetNamespaceDefinitionRoot()
            for segment in namespaceName.Split('.') {
                found := false
                for childHandle in current.NamespaceDefinitions {
                    child := reader.GetNamespaceDefinition(childHandle)
                    if !found && reader.GetString(child.Name) == segment {
                        current = child
                        found = true
                    }
                }

                if !found {
                    return
                }
            }

            for typeHandle in current.TypeDefinitions {
                definition := reader.GetTypeDefinition(typeHandle)
                visibility := (int)definition.Attributes & (int)TypeAttributes.VisibilityMask
                if visibility == (int)TypeAttributes.Public && definition.GetDeclaringType().IsNil {
                    names.Add(reader.GetString(definition.Name))
                }
            }

            for exportedHandle in current.ExportedTypes {
                exported := reader.GetExportedType(exportedHandle)
                if exported.IsForwarder {
                    names.Add(reader.GetString(exported.Name))
                }
            }
        } catch {
            // An unreadable reference file contributes no name; the type is then not on the surface.
            return
        } finally {
            if pe != null {
                pe.Dispose()
            }
            if stream != null {
                stream.Dispose()
            }
        }
    }

    // A PUBLIC TYPE ONLY AN IMPLEMENTATION CARRIES: declared by an assembly of the runtime directory
    // the analyzer reads, in a namespace or under a name the reference pack does not have. It is
    // public in metadata and not nameable from a project, exactly as `dotnet build` (which compiles
    // against the pack) refuses it. `InternalsVisibleToGrants.IsNameableType` asks this.
    static func IsImplementationOnlyType(candidate: Type): bool {
        top := candidate
        while top.IsNested {
            declaring := top.DeclaringType
            if declaring == null {
                return false
            }
            top = declaring
        }

        if !IsHostRuntimeAssembly(top.Assembly) {
            return false
        }

        index := ForHostRuntime()
        if !index.HasReferenceSurface {
            return false
        }

        return !index.IsOnCompileSurface(top.Namespace ?? "", top.Name)
    }

    static func IsHostRuntimeAssembly(assembly: Assembly): bool {
        cached: object? = null
        if FrameworkNamespaceIndex.runtimeAssemblyMarks.TryGetValue(assembly, out cached) {
            return Object.ReferenceEquals(cached, FrameworkNamespaceIndex.runtimeMarker)
        }

        isRuntime := false
        try {
            if !assembly.IsDynamic {
                location := ReferenceImageSnapshotStore.OriginalPathOf(assembly) ?? ""
                if location.Length > 0 {
                    directory := Path.GetDirectoryName(Path.GetFullPath(location)) ?? ""
                    isRuntime = string.Equals(Path.TrimEndingDirectorySeparator(directory), ForHostRuntime().RuntimeDirectory, StringComparison.Ordinal)
                }
            }
        } catch {
            isRuntime = false
        }

        marker := FrameworkNamespaceIndex.otherMarker
        if isRuntime {
            marker = FrameworkNamespaceIndex.runtimeMarker
        }
        FrameworkNamespaceIndex.runtimeAssemblyMarks.AddOrUpdate(assembly, marker)
        return isRuntime
    }

    // ── THE PURE HALF: every decision above, with no file opened ──────────────────────────────────

    // THE COMPILE SURFACE WITHOUT A REFERENCE PACK: every runtime assembly except the
    // `System.Private.*` implementations, which no reference pack has ever listed.
    static func RuntimeCompileAssemblyNames(runtimeAssemblyNames: IEnumerable<string>): HashSet<string> {
        names := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        for name in runtimeAssemblyNames {
            if !name.StartsWith("System.Private.", StringComparison.OrdinalIgnoreCase) {
                names.Add(name)
            }
        }

        return names
    }

    // The `AssemblyName` of every `Type="Managed"` row. `Analyzer` rows are Roslyn source generators,
    // which are not compile references.
    static func ParseFrameworkListAssemblyNames(xmlText: string): HashSet<string> {
        names := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        document := XDocument.Parse(xmlText)
        root := document.Root
        if root == null {
            return names
        }

        for element in root.Elements(XName.Get("File")) {
            typeAttribute := element.Attribute(XName.Get("Type"))
            nameAttribute := element.Attribute(XName.Get("AssemblyName"))
            if typeAttribute != null && nameAttribute != null && string.Equals(typeAttribute.Value, "Managed", StringComparison.Ordinal) {
                names.Add(nameAttribute.Value)
            }
        }

        return names
    }

    // `<root>/shared/Microsoft.NETCore.App/<version>` -> `<root>/packs/Microsoft.NETCore.App.Ref`.
    // Null when the runtime directory is not laid out under a dotnet root.
    static func ReferencePackRoot(runtimeDirectory: string): string? {
        versionDirectory := Path.TrimEndingDirectorySeparator(runtimeDirectory)
        frameworkDirectory := Path.GetDirectoryName(versionDirectory)
        if frameworkDirectory == null {
            return null
        }

        sharedDirectory := Path.GetDirectoryName(frameworkDirectory)
        if sharedDirectory == null || !string.Equals(Path.GetFileName(sharedDirectory), "shared", StringComparison.OrdinalIgnoreCase) {
            return null
        }

        dotnetRoot := Path.GetDirectoryName(sharedDirectory)
        if dotnetRoot == null {
            return null
        }

        return Path.Combine(Path.Combine(dotnetRoot, "packs"), Path.GetFileName(frameworkDirectory) + ".Ref")
    }

    // THE REFERENCE PACK THAT DESCRIBES THIS RUNTIME: the one of the runtime's own version when it is
    // installed (an SDK ships the pack of the runtime it bundles), otherwise the highest pack of the
    // runtime's major version -- the same rule that picks a shared-framework directory for a TFM.
    static func SelectReferencePackVersion(packVersions: string[], runtimeVersion: string): int {
        index := 0
        while index < packVersions.Length {
            if string.Equals(packVersions[index], runtimeVersion, StringComparison.OrdinalIgnoreCase) {
                return index
            }

            index = index + 1
        }

        majorEnd := runtimeVersion.IndexOf('.')
        if majorEnd <= 0 {
            return -1
        }

        targetFramework := "net" + runtimeVersion.Substring(0, majorEnd) + ".0"
        return CompilationReferenceResolverKernels.SelectSharedFrameworkDirectoryIndex(packVersions, CompilationReferenceResolverKernels.ParseTargetFrameworkVersion(targetFramework))
    }

    static func FindReferencePackFrameworkList(runtimeDirectory: string): string? {
        packRoot := ReferencePackRoot(runtimeDirectory)
        if packRoot == null || !Directory.Exists(packRoot) {
            return null
        }

        versionDirectories := Directory.GetDirectories(packRoot)
        versions := new string[](versionDirectories.Length)
        index := 0
        while index < versionDirectories.Length {
            versions[index] = Path.GetFileName(versionDirectories[index]) ?? ""
            index = index + 1
        }

        selected := SelectReferencePackVersion(versions, Path.GetFileName(Path.TrimEndingDirectorySeparator(runtimeDirectory)) ?? "")
        if selected < 0 {
            return null
        }

        frameworkList := Path.Combine(Path.Combine(versionDirectories[selected], "data"), "FrameworkList.xml")
        if File.Exists(frameworkList) {
            return frameworkList
        }

        return null
    }

    // THE MAP. A namespace is IMPORTABLE when a compile-surface assembly declares or forwards a public
    // type in it, and importing it loads every runtime assembly that DEFINES a public type in it,
    // whether or not that assembly is itself on the compile surface: `System.Xml` is importable
    // because `System.Xml.ReaderWriter` forwards it, and it is answered by `System.Private.Xml`, which
    // defines it. A namespace only a `System.Private.*` assembly carries (`Internal`) is not importable.
    static func BuildNamespaceMap(rows: List<FrameworkNamespaceRow>, compileAssemblyNames: HashSet<string>): Dictionary<string, string[]> {
        visible := new HashSet<string>(StringComparer.Ordinal)
        for row in rows {
            if compileAssemblyNames.Contains(row.AssemblyName) {
                visible.Add(row.NamespaceName)
            }
        }

        return BuildNamespaceMapFor(rows, visible)
    }

    // The map over a namespace set already decided: the reference pack's own, or the one the
    // compile-surface assemblies of the runtime directory carry.
    static func BuildNamespaceMapFor(rows: List<FrameworkNamespaceRow>, visible: HashSet<string>): Dictionary<string, string[]> {
        definers := new Dictionary<string, SortedSet<string>>(StringComparer.Ordinal)
        for row in rows {
            if row.Defines {
                existing: SortedSet<string>? = null
                if definers.TryGetValue(row.NamespaceName, out existing) && existing != null {
                    existing.Add(row.AssemblyName)
                } else {
                    created := new SortedSet<string>(StringComparer.Ordinal)
                    created.Add(row.AssemblyName)
                    definers[row.NamespaceName] = created
                }
            }
        }

        map := new Dictionary<string, string[]>(StringComparer.Ordinal)
        for entry in definers {
            if visible.Contains(entry.Key) {
                names := new string[](entry.Value.Count)
                entry.Value.CopyTo(names)
                map[entry.Key] = names
            }
        }

        return map
    }

    // One row per namespace the file carries a PUBLIC top-level type in: `Defines` when it has a type
    // definition there, otherwise a forwarder. It walks the metadata's NAMESPACE TREE rather than the
    // type table, so a namespace costs one name read however many types it holds -- the whole framework
    // is ~640 namespace rows against ~40,000 type definitions -- and a namespace stops being asked the
    // moment one public type answers. A non-public type is nothing a program can import. A file with no
    // readable metadata (a native image) adds no rows.
    static func ReadNamespaceRows(path: string, rows: List<FrameworkNamespaceRow>) {
        assemblyName := Path.GetFileNameWithoutExtension(path)
        stream: Stream? = null
        pe: PEReader? = null
        try {
            stream = File.OpenRead(path)
            pe = new PEReader(stream)
            if !pe.HasMetadata {
                return
            }

            reader := pe.GetMetadataReader()
            pending := new List<NamespaceDefinition>()
            pendingNames := new List<string>()
            pending.Add(reader.GetNamespaceDefinitionRoot())
            pendingNames.Add("")
            while pending.Count > 0 {
                last := pending.Count - 1
                namespaceDefinition := pending[last]
                namespaceName := pendingNames[last]
                pending.RemoveAt(last)
                pendingNames.RemoveAt(last)

                for childHandle in namespaceDefinition.NamespaceDefinitions {
                    child := reader.GetNamespaceDefinition(childHandle)
                    childName := reader.GetString(child.Name)
                    pending.Add(child)
                    if namespaceName.Length == 0 {
                        pendingNames.Add(childName)
                    } else {
                        pendingNames.Add(namespaceName + "." + childName)
                    }
                }

                if namespaceName.Length == 0 {
                    continue
                }

                publicTypes := PublicTypeCount(reader, namespaceDefinition)
                if publicTypes > 0 {
                    row := new FrameworkNamespaceRow(assemblyName, namespaceName, true)
                    row.PublicTypeCount = publicTypes
                    rows.Add(row)
                } else if ForwardsType(reader, namespaceDefinition) {
                    rows.Add(new FrameworkNamespaceRow(assemblyName, namespaceName, false))
                }
            }
        } catch {
            // An unreadable file contributes no namespace; the rest of the framework still answers.
            return
        } finally {
            if pe != null {
                pe.Dispose()
            }
            if stream != null {
                stream.Dispose()
            }
        }
    }

    // How many PUBLIC top-level types the file defines in this namespace: attribute reads only, no
    // name is decoded.
    static func PublicTypeCount(reader: MetadataReader, namespaceDefinition: NamespaceDefinition): int {
        count := 0
        for typeHandle in namespaceDefinition.TypeDefinitions {
            definition := reader.GetTypeDefinition(typeHandle)
            visibility := (int)definition.Attributes & (int)TypeAttributes.VisibilityMask
            if visibility == (int)TypeAttributes.Public && definition.GetDeclaringType().IsNil {
                count = count + 1
            }
        }

        return count
    }

    static func ForwardsType(reader: MetadataReader, namespaceDefinition: NamespaceDefinition): bool {
        for exportedHandle in namespaceDefinition.ExportedTypes {
            if reader.GetExportedType(exportedHandle).IsForwarder {
                return true
            }
        }

        return false
    }
}

// One namespace one framework assembly carries: `Defines` when the assembly has a public type
// definition in it, otherwise it only forwards one there.
class FrameworkNamespaceRow {
    AssemblyName: string
    NamespaceName: string
    Defines: bool

    // The public top-level types the assembly defines in the namespace (zero for a forwarder row).
    PublicTypeCount: int

    constructor(assemblyName: string, namespaceName: string, defines: bool) {
        AssemblyName = assemblyName
        NamespaceName = namespaceName
        Defines = defines
        PublicTypeCount = 0
    }
}
