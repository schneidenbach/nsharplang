namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// Native contracts for project discovery — the source/unit provider and the discovery walk over it.
//
// Every member behind these contracts was `private` in Analyzer.cs, so no test named any of them:
// their behaviour was pinned only indirectly, through end-to-end diagnostics. This is their first
// DIRECT pinning, and it goes at the parts that read like plumbing and are not:
//
//   * the ENUMERATION ORDER, which is the answer whenever two files declare the same name (measured:
//     47 such (namespace, name) pairs in this repository's own root project);
//   * the CACHES — which are cleared per analysis and which deliberately are not, and the fact that
//     a cached NULL is a real answer and not a miss;
//   * the THREE-WAY outcome of the type channel, whose ORDER is the semantics: the inaccessible case
//     is decided BETWEEN the namespace sweep and the unique-exported fallback, and suppresses it;
//   * export visibility, which is what makes a cross-namespace reference resolve or not.
func ProjectSourceOf(namespaceName: string?, body: string): string {
    if namespaceName == null {
        return body
    }

    return "namespace " + namespaceName + "\n\n" + body
}

// A provider holding an in-memory snapshot, added in the given order — which is the order every walk
// then takes.
func ProjectProviderOf(paths: string[], sources: string[]): AnalyzerProjectSourceProvider {
    provider := new AnalyzerProjectSourceProvider()
    index := 0
    while index < paths.Length {
        provider.AddSourceText(paths[index], sources[index])
        index = index + 1
    }

    return provider
}

func ProjectDiscoveryOf(
    provider: AnalyzerProjectSourceProvider,
    imports: string[]
): AnalyzerProjectTypeDiscovery {
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    provider.AddProjectUnitsTo(context)
    usingNamespaces := new List<string>()
    index := 0
    while index < imports.Length {
        usingNamespaces.Add(imports[index])
        index = index + 1
    }

    return new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        usingNamespaces,
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
}

func ProjectPathList(values: List<string>): string {
    text := ""
    index := 0
    while index < values.Count {
        if index > 0 {
            text = text + ","
        }
        text = text + Path.GetFileName(values[index])
        index = index + 1
    }
    return text
}

// ---- the provider ------------------------------------------------------------------------------

test "the snapshot is walked in insertion order, and a repeated path keeps its original position" {
    provider := new AnalyzerProjectSourceProvider()
    provider.AddSourceText("/p/b.nl", "b1")
    provider.AddSourceText("/p/a.nl", "a1")
    provider.AddSourceText("/p/c.nl", "c1")

    // Insertion order, NOT sorted order: two files declaring the same name make "first wins" a
    // decision, so this order is part of the answer.
    assert ProjectPathList(provider.SourceFilePaths()) == "b.nl,a.nl,c.nl"

    // Re-adding a path REPLACES its text and keeps its position, exactly as an indexer assignment
    // into a dictionary that already has the key.
    provider.AddSourceText("/p/a.nl", "a2")
    assert ProjectPathList(provider.SourceFilePaths()) == "b.nl,a.nl,c.nl"
    assert provider.TryGetProjectSourceText("/p/a.nl") == "a2"
}

test "the snapshot is keyed case-insensitively on the FULL path" {
    provider := new AnalyzerProjectSourceProvider()
    provider.AddSourceText("/p/One.nl", "one")

    assert provider.ContainsSourceText(Path.GetFullPath("/p/One.nl"))
    assert provider.ContainsSourceText(Path.GetFullPath("/p/one.nl"))
    assert provider.TryGetProjectSourceText("/p/ONE.NL") == "one"

    // A relative spelling normalises to the same key.
    assert provider.TryGetProjectSourceText("/p/./One.nl") == "one"
    assert provider.TryGetProjectSourceText("/p/Two.nl") == null
    assert !provider.ContainsSourceText(Path.GetFullPath("/p/Two.nl"))
}

test "a snapshot miss means ask the disk, and a missing file means empty rather than a throw" {
    provider := new AnalyzerProjectSourceProvider()
    provider.AddSourceText("/p/known.nl", "in memory")

    // TryGetProjectSourceText answers only from the snapshot: null is "not in the snapshot", which is
    // a different question from "no text".
    assert provider.TryGetProjectSourceText("/p/known.nl") == "in memory"
    assert provider.TryGetProjectSourceText("/p/absent.nl") == null

    // ProjectSourceText resolves it: snapshot, then disk, then empty.
    assert provider.ProjectSourceText("/p/known.nl") == "in memory"
    assert provider.ProjectSourceText("/p/does-not-exist-at-all.nl") == ""

    temporary := Path.Combine(Path.GetTempPath(), "nsharp-project-discovery-" + Guid.NewGuid().ToString() + ".nl")
    File.WriteAllText(temporary, "on disk")
    assert provider.ProjectSourceText(temporary) == "on disk"
    File.Delete(temporary)
}

test "resetting the snapshot takes the parsed units with it, but beginning an analysis does not" {
    provider := new AnalyzerProjectSourceProvider()
    provider.AddSourceText("/p/one.nl", ProjectSourceOf("A", "public class Kept {\n}\n"))
    firstUnit := provider.GetProjectCompilationUnit("/p/one.nl")
    assert firstUnit != null
    assert AnalyzerProjectSourceProvider.UnitNamespace(firstUnit) == "A"

    // A new analysis keeps the parsed unit: the same instance comes back, so the cache survived.
    provider.BeginAnalysis("/p")
    assert Object.ReferenceEquals(provider.GetProjectCompilationUnit("/p/one.nl"), firstUnit)
    assert provider.ProjectRoot == "/p"

    // A new SNAPSHOT does not: the units were parsed from the old texts.
    provider.ResetSourceTexts()
    provider.AddSourceText("/p/one.nl", ProjectSourceOf("B", "public class Kept {\n}\n"))
    secondUnit := provider.GetProjectCompilationUnit("/p/one.nl")
    assert !Object.ReferenceEquals(secondUnit, firstUnit)
    assert AnalyzerProjectSourceProvider.UnitNamespace(secondUnit) == "B"
    assert provider.SourceFilePaths().Count == 1
}

test "a unit is parsed at most once per path, and a package name outranks a namespace name" {
    provider := new AnalyzerProjectSourceProvider()
    provider.AddSourceText("/p/pkg.nl", "package Pack\n\npublic class Inside {\n}\n")
    provider.AddSourceText("/p/plain.nl", "public class Global {\n}\n")

    packUnit := provider.GetProjectCompilationUnit("/p/pkg.nl")
    assert Object.ReferenceEquals(provider.GetProjectCompilationUnit("/p/pkg.nl"), packUnit)
    assert AnalyzerProjectSourceProvider.UnitNamespace(packUnit) == "Pack"

    // No package and no namespace is the GLOBAL namespace — a real candidate, expressed as null.
    assert AnalyzerProjectSourceProvider.UnitNamespace(provider.GetProjectCompilationUnit("/p/plain.nl")) == null
    assert AnalyzerProjectSourceProvider.UnitNamespace(null) == null
}

test "the file-namespace question caches its negative answer and parses at most once per snapshot" {
    provider := new AnalyzerProjectSourceProvider()
    directory := Path.Combine(Path.GetTempPath(), "nsharp-project-ns-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    present := Path.Combine(directory, "present.nl")
    File.WriteAllText(present, ProjectSourceOf("Declared", "public class Here {\n}\n"))
    absent := Path.Combine(directory, "absent.nl")

    assert provider.GetNamespaceForFile(present) == "Declared"
    assert provider.GetNamespaceForFile(absent) == null
    assert provider.GetNamespaceForFile(null) == null
    assert provider.GetNamespaceForFile("") == null

    // The negative answer is CACHED: creating the file afterwards does not change the answer until
    // the next analysis clears the cache. A cached null is an answer, not a miss.
    File.WriteAllText(absent, ProjectSourceOf("Late", "public class Late {\n}\n"))
    assert provider.GetNamespaceForFile(absent) == null
    provider.BeginAnalysis(directory)
    assert provider.GetNamespaceForFile(absent) == "Late"

    // The question goes through the unit cache (rule 3): snapshot text added AFTER the file was
    // parsed does not re-enter it, because only a NEW snapshot re-parses...
    provider.AddSourceText(present, ProjectSourceOf("Snapshot", "public class Here {\n}\n"))
    provider.BeginAnalysis(directory)
    assert provider.GetNamespaceForFile(present) == "Declared"

    // ...and under a new snapshot the SNAPSHOT'S text is the file's text, not the disk's — the same
    // snapshot-first answer every other project question gives.
    provider.ResetSourceTexts()
    provider.AddSourceText(present, ProjectSourceOf("Snapshot", "public class Here {\n}\n"))
    provider.BeginAnalysis(directory)
    assert provider.GetNamespaceForFile(present) == "Snapshot"

    Directory.Delete(directory, true)
}

test "the project-namespace set comes from the root on disk and is empty without a usable root" {
    provider := new AnalyzerProjectSourceProvider()

    // No root at all, a blank root and a root that does not exist all answer NO rather than throwing.
    assert !provider.ProjectNamespaceExists("Anything")
    provider.BeginAnalysis(null)
    assert !provider.ProjectNamespaceExists("Anything")
    provider.BeginAnalysis("   ")
    assert !provider.ProjectNamespaceExists("Anything")
    provider.BeginAnalysis(Path.Combine(Path.GetTempPath(), "nsharp-absent-" + Guid.NewGuid().ToString()))
    assert !provider.ProjectNamespaceExists("Anything")

    directory := Path.Combine(Path.GetTempPath(), "nsharp-project-roots-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "a.nl"), ProjectSourceOf("Alpha", "public class A {\n}\n"))
    File.WriteAllText(Path.Combine(directory, "b.nl"), "package Beta\n\npublic class B {\n}\n")
    File.WriteAllText(Path.Combine(directory, "c.nl"), "public class C {\n}\n")
    provider.BeginAnalysis(directory)

    assert provider.ProjectNamespaceExists("Alpha")
    assert provider.ProjectNamespaceExists("Beta")
    // A file with no namespace contributes nothing, and the match is case-SENSITIVE.
    assert !provider.ProjectNamespaceExists("alpha")
    assert !provider.ProjectNamespaceExists("Gamma")

    Directory.Delete(directory, true)
}

test "a namespace rebuild walks cached units instead of re-parsing the project" {
    provider := new AnalyzerProjectSourceProvider()
    directory := Path.Combine(Path.GetTempPath(), "nsharp-project-rebuild-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    drifting := Path.Combine(directory, "drifting.nl")
    File.WriteAllText(drifting, ProjectSourceOf("Alpha", "public class A {\n}\n"))
    provider.BeginAnalysis(directory)
    assert provider.ProjectNamespaceExists("Alpha")

    // The disk drifting mid-snapshot changes NOTHING: the next analysis rebuilds the namespace set
    // from the cached unit rather than re-reading the file. This is the load-bearing half of
    // rule 3 — a shared analyzer begins one analysis per project file, so a rebuild that re-parsed
    // the project would parse it once per file, O(files²): the 2026-08 `nlc query completions`
    // hang (693 files, ~480k recovery parses, tens of minutes at 100% CPU).
    File.WriteAllText(drifting, ProjectSourceOf("Beta", "public class A {\n}\n"))
    provider.BeginAnalysis(directory)
    assert provider.ProjectNamespaceExists("Alpha")
    assert !provider.ProjectNamespaceExists("Beta")
    assert provider.GetNamespaceForFile(drifting) == "Alpha"

    // A NEW snapshot is the one thing that re-parses (rule 3), and then the disk's new text answers.
    provider.ResetSourceTexts()
    provider.BeginAnalysis(directory)
    assert provider.ProjectNamespaceExists("Beta")
    assert !provider.ProjectNamespaceExists("Alpha")

    Directory.Delete(directory, true)
}

test "the disk fallback is used only when there is no snapshot, and skips nothing it can read" {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-project-disk-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "one.nl"), ProjectSourceOf("Disk", "public class One {\n}\n"))
    File.WriteAllText(Path.Combine(directory, "two.nl"), ProjectSourceOf("Disk", "public class Two {\n}\n"))

    provider := new AnalyzerProjectSourceProvider()
    provider.BeginAnalysis(directory)
    assert provider.SourceFilePaths().Count == 2

    // One snapshot entry takes the whole answer: the snapshot is not merged with the disk.
    provider.AddSourceText("/elsewhere/only.nl", "public class Only {\n}\n")
    assert ProjectPathList(provider.SourceFilePaths()) == "only.nl"

    Directory.Delete(directory, true)
}

// ---- the discovery walk ------------------------------------------------------------------------

test "a type declared by another file in the SAME namespace resolves, exported or not" {
    provider := ProjectProviderOf(
        ["/p/other.nl"],
        [ProjectSourceOf("Same", "public class Exported {\n}\n\nclass notExported {\n}\n")]
    )
    discovery := ProjectDiscoveryOf(provider, [])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null
    assert discovery.ResolveVisibleProjectType(
        "Exported",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert inaccessible == null
    assert declaration != null
    assert declaration.Name == "Exported"
    assert declaration.Kind == "class"

    // Inside its OWN namespace a non-exported declaration is still visible, and finding it there is
    // not an accessibility failure.
    assert discovery.ResolveVisibleProjectType(
        "notExported",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert inaccessible == null
}

test "across namespaces only an EXPORTED declaration resolves, and the rest is the inaccessible case" {
    provider := ProjectProviderOf(
        ["/p/other.nl"],
        [ProjectSourceOf("Other", "public class Exported {\n}\n\nclass notExported {\n}\n")]
    )
    discovery := ProjectDiscoveryOf(provider, ["Other"])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null

    assert discovery.ResolveVisibleProjectType(
        "Exported",
        "Mine",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert inaccessible == null

    // The non-exported one is not resolved AND is reported as inaccessible, with the file that
    // declares it — which is what the diagnostic names.
    assert !discovery.ResolveVisibleProjectType(
        "notExported",
        "Mine",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert inaccessible != null
    assert Path.GetFileName(inaccessible) == "other.nl"
    assert declaration == null
    assert BuiltInTypes.IsUnknown(resolved)
}

test "the inaccessible probe is skipped without a source position, and it SUPPRESSES the fallback" {
    // `Hidden` is non-exported in an imported namespace, so the inaccessible case fires — and the
    // unique-exported fallback, which would otherwise have nothing to offer either, is not reached.
    provider := ProjectProviderOf(
        ["/p/other.nl"],
        [ProjectSourceOf("Other", "class hidden {\n}\n")]
    )
    discovery := ProjectDiscoveryOf(provider, ["Other"])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null

    assert !discovery.ResolveVisibleProjectType(
        "hidden",
        "Mine",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert inaccessible != null

    // Without a position there is nothing to report, so the probe is not even run: the SAME inputs
    // answer "no such type" rather than "inaccessible".
    assert !discovery.ResolveVisibleProjectType(
        "hidden",
        "Mine",
        false,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert inaccessible == null
}

test "the unique-exported fallback resolves a type no visible namespace offers" {
    // `Far` is exported from a namespace that is neither the current one nor imported, so the
    // namespace sweep misses it and the project-wide unique-exported fallback catches it.
    provider := ProjectProviderOf(
        ["/p/far.nl"],
        [ProjectSourceOf("Far", "public class Far {\n}\n")]
    )
    discovery := ProjectDiscoveryOf(provider, [])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null
    assert discovery.ResolveVisibleProjectType(
        "Far",
        "Mine",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert inaccessible == null
    assert declaration != null
    assert Path.GetFileName(declaration.File) == "far.nl"

    // A name nothing declares is simply absent — not inaccessible.
    assert !discovery.ResolveVisibleProjectType(
        "Missing",
        "Mine",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert inaccessible == null
    assert declaration == null
}

test "the enumeration order IS the answer: the first file declaring a function name wins" {
    // The function channel takes the FIRST match, and duplicate function names across files are
    // ordinary rather than pathological — `Main` is declared by 42 files in this repository's own
    // root project. So the order the files are enumerated in decides the answer.
    forward := ProjectProviderOf(
        ["/p/aaa.nl", "/p/zzz.nl"],
        [
            ProjectSourceOf("Same", "public func Twice() {\n}\n"),
            ProjectSourceOf("Same", "public func Twice() {\n}\n")
        ]
    )
    reversed := ProjectProviderOf(
        ["/p/zzz.nl", "/p/aaa.nl"],
        [
            ProjectSourceOf("Same", "public func Twice() {\n}\n"),
            ProjectSourceOf("Same", "public func Twice() {\n}\n")
        ]
    )

    declarationFile: string? = null
    functionDeclaration: FunctionDeclaration? = null
    declaration: SymbolDeclaration? = null

    forwardDiscovery := ProjectDiscoveryOf(forward, [])
    assert forwardDiscovery.TryResolveVisibleProjectFunction(
        "Twice",
        "Same",
        out declarationFile,
        out functionDeclaration,
        out declaration
    )
    assert Path.GetFileName(declarationFile) == "aaa.nl"

    // The SAME two files in the opposite order give a DIFFERENT answer. Insertion order, not any
    // sort of the paths.
    reversedDiscovery := ProjectDiscoveryOf(reversed, [])
    assert reversedDiscovery.TryResolveVisibleProjectFunction(
        "Twice",
        "Same",
        out declarationFile,
        out functionDeclaration,
        out declaration
    )
    assert Path.GetFileName(declarationFile) == "zzz.nl"
}

test "the inaccessible probe names the FIRST file that hides the name" {
    forward := ProjectProviderOf(
        ["/p/aaa.nl", "/p/zzz.nl"],
        [
            ProjectSourceOf("Other", "func hidden() {\n}\n"),
            ProjectSourceOf("Other", "func hidden() {\n}\n")
        ]
    )
    reversed := ProjectProviderOf(
        ["/p/zzz.nl", "/p/aaa.nl"],
        [
            ProjectSourceOf("Other", "func hidden() {\n}\n"),
            ProjectSourceOf("Other", "func hidden() {\n}\n")
        ]
    )

    inaccessible: string? = null
    // The file this names goes into the diagnostic, so the order is user-visible.
    assert ProjectDiscoveryOf(forward, ["Other"]).TryFindInaccessibleVisibleFunction(
        "hidden",
        "Mine",
        out inaccessible
    )
    assert Path.GetFileName(inaccessible) == "aaa.nl"
    assert ProjectDiscoveryOf(reversed, ["Other"]).TryFindInaccessibleVisibleFunction(
        "hidden",
        "Mine",
        out inaccessible
    )
    assert Path.GetFileName(inaccessible) == "zzz.nl"
}

test "two files declaring the SAME type name in one namespace is ambiguous, not first-wins" {
    // The type channel differs from the function channel here, and deliberately: a duplicate type
    // name inside one namespace refuses to resolve rather than picking one. That refusal is what
    // makes the enumeration order irrelevant for THIS channel and decisive for the other two.
    provider := ProjectProviderOf(
        ["/p/aaa.nl", "/p/zzz.nl"],
        [
            ProjectSourceOf("Same", "public class Twice {\n}\n"),
            ProjectSourceOf("Same", "public class Twice {\n}\n")
        ]
    )
    discovery := ProjectDiscoveryOf(provider, [])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null
    assert !discovery.ResolveVisibleProjectType(
        "Twice",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert declaration == null
    assert inaccessible == null

    // One declaration of the name resolves; the duplicate is what refuses.
    single := ProjectProviderOf(
        ["/p/aaa.nl"],
        [ProjectSourceOf("Same", "public class Twice {\n}\n")]
    )
    assert ProjectDiscoveryOf(single, []).ResolveVisibleProjectType(
        "Twice",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert Path.GetFileName(declaration.File) == "aaa.nl"
}

test "the visible-namespace order decides between two namespaces that both declare the name" {
    provider := ProjectProviderOf(
        ["/p/mine.nl", "/p/imported.nl"],
        [
            ProjectSourceOf("Mine", "public class Both {\n}\n"),
            ProjectSourceOf("Imported", "public class Both {\n}\n")
        ]
    )
    discovery := ProjectDiscoveryOf(provider, ["Imported"])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null

    // The file's OWN namespace is the first candidate, ahead of every import.
    assert discovery.ResolveVisibleProjectType(
        "Both",
        "Mine",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert Path.GetFileName(declaration.File) == "mine.nl"

    // From a namespace that declares nothing, the import answers.
    assert discovery.ResolveVisibleProjectType(
        "Both",
        "Elsewhere",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert Path.GetFileName(declaration.File) == "imported.nl"
}

test "one namespace at a time: the current namespace does not require export and others do" {
    provider := ProjectProviderOf(
        ["/p/other.nl"],
        [ProjectSourceOf("Other", "public class Exported {\n}\n\nclass notExported {\n}\n")]
    )
    discovery := ProjectDiscoveryOf(provider, [])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null

    // Asked AS the declaring namespace, export is not required.
    assert discovery.TryResolveProjectTypeInNamespace(
        "notExported",
        "Other",
        "Other",
        out resolved,
        out declaration
    )
    // Asked from anywhere else, it is.
    assert !discovery.TryResolveProjectTypeInNamespace(
        "notExported",
        "Other",
        "Mine",
        out resolved,
        out declaration
    )
    assert discovery.TryResolveProjectTypeInNamespace(
        "Exported",
        "Other",
        "Mine",
        out resolved,
        out declaration
    )
    // A namespace no file declares offers nothing, and the global namespace is a real candidate
    // rather than an absence.
    assert !discovery.TryResolveProjectTypeInNamespace(
        "Exported",
        "Nowhere",
        "Mine",
        out resolved,
        out declaration
    )
    assert !discovery.TryResolveProjectTypeInNamespace(
        "Exported",
        null,
        "Mine",
        out resolved,
        out declaration
    )
}

test "a resolved declaration points at the NAME's column, not the declaration's own column" {
    // The declaration starts at column 1 (`public`); the identifier starts later on the line, and a
    // go-to-definition span has to land on the identifier.
    provider := ProjectProviderOf(
        ["/p/other.nl"],
        [ProjectSourceOf("Same", "public class Located {\n}\n")]
    )
    discovery := ProjectDiscoveryOf(provider, [])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null
    assert discovery.ResolveVisibleProjectType(
        "Located",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert declaration.Line == 3
    assert declaration.Column == 14
}

// The kind of the FIRST declaration in a source, and whether the owner calls it a type.
func ProjectFirstDeclarationKind(body: string, out isType: bool): string {
    provider := new AnalyzerProjectSourceProvider()
    path := "/families/" + Guid.NewGuid().ToString() + ".nl"
    provider.AddSourceText(path, ProjectSourceOf("Fam", body))
    unit := provider.GetProjectCompilationUnit(path)
    if unit == null {
        isType = false
        return "<unparsed>"
    }

    declarations := unit.Declarations
    if declarations.Count == 0 {
        isType = false
        return "<empty>"
    }

    first := declarations[0]
    isType = AnalyzerProjectTypeDiscovery.IsTopLevelTypeDeclaration(first)
    return DeclarationFacts.GetDeclarationKind(first)
}

test "every declared family is a top-level TYPE declaration and a function is not" {
    // Each family is parsed on its own so that one family failing to parse cannot hide behind
    // another's success. Eight families answer YES; a function answers NO.
    isType := false

    assert ProjectFirstDeclarationKind("public class C {\n}\n", out isType) == "class"
    assert isType
    assert ProjectFirstDeclarationKind("public struct S {\n}\n", out isType) == "struct"
    assert isType
    assert ProjectFirstDeclarationKind("public record R(value: int)\n", out isType) == "record"
    assert isType
    assert ProjectFirstDeclarationKind("public interface I {\n}\n", out isType) == "interface"
    assert isType
    assert ProjectFirstDeclarationKind("union U {\n    A { value: int }\n    B\n}\n", out isType) == "union"
    assert isType
    assert ProjectFirstDeclarationKind("public enum E {\n    One\n}\n", out isType) == "enum"
    assert isType
    assert ProjectFirstDeclarationKind("type T = int\n", out isType) == "typeAlias"
    assert isType
    assert ProjectFirstDeclarationKind("type N = newtype int\n", out isType) == "newtype"
    assert isType

    assert ProjectFirstDeclarationKind("public func F() {\n}\n", out isType) == "function"
    assert !isType
}

test "an exported top-level function is visible project-wide and a camelCase one is not" {
    provider := ProjectProviderOf(
        ["/p/funcs.nl"],
        [ProjectSourceOf("Other", "public func Exported() {\n}\n\nfunc notExported() {\n}\n")]
    )
    discovery := ProjectDiscoveryOf(provider, ["Other"])

    declarationFile: string? = null
    functionDeclaration: FunctionDeclaration? = null
    declaration: SymbolDeclaration? = null

    assert discovery.TryResolveVisibleProjectFunction(
        "Exported",
        "Mine",
        out declarationFile,
        out functionDeclaration,
        out declaration
    )
    assert Path.GetFileName(declarationFile) == "funcs.nl"
    assert functionDeclaration != null
    assert functionDeclaration.Name == "Exported"
    assert declaration != null
    assert declaration.Kind == "function"

    // Non-exported stays file-private across namespaces, and instead shows up as the inaccessible
    // case for the identifier path.
    assert !discovery.TryResolveVisibleProjectFunction(
        "notExported",
        "Mine",
        out declarationFile,
        out functionDeclaration,
        out declaration
    )
    assert declarationFile == null
    assert functionDeclaration == null

    inaccessible: string? = null
    assert discovery.TryFindInaccessibleVisibleFunction("notExported", "Mine", out inaccessible)
    assert Path.GetFileName(inaccessible) == "funcs.nl"

    // A name nothing declares is not inaccessible, and neither is one declared in MY OWN namespace.
    assert !discovery.TryFindInaccessibleVisibleFunction("missing", "Mine", out inaccessible)
    assert inaccessible == null
    assert !discovery.TryFindInaccessibleVisibleFunction("notExported", "Other", out inaccessible)
    assert inaccessible == null
}

test "the inaccessible probe does not confuse a type with a function of the same name" {
    provider := ProjectProviderOf(
        ["/p/mixed.nl"],
        [ProjectSourceOf("Other", "class shared {\n}\n\nfunc alsoShared() {\n}\n")]
    )
    discovery := ProjectDiscoveryOf(provider, ["Other"])

    inaccessible: string? = null
    // The FUNCTION probe sees only functions: the non-exported TYPE is invisible to it.
    assert !discovery.TryFindInaccessibleVisibleFunction("shared", "Mine", out inaccessible)
    assert inaccessible == null
    assert discovery.TryFindInaccessibleVisibleFunction("alsoShared", "Mine", out inaccessible)
    assert inaccessible != null

    // And the TYPE channel's own probe sees only types.
    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    typeInaccessible: string? = null
    assert !discovery.ResolveVisibleProjectType(
        "shared",
        "Mine",
        true,
        out resolved,
        out declaration,
        out typeInaccessible
    )
    assert typeInaccessible != null
    assert !discovery.ResolveVisibleProjectType(
        "alsoShared",
        "Mine",
        true,
        out resolved,
        out declaration,
        out typeInaccessible
    )
    assert typeInaccessible == null
}

test "a file that does not parse is skipped by every walk rather than failing it" {
    provider := ProjectProviderOf(
        ["/p/broken.nl", "/p/good.nl"],
        [
            "namespace Same\n\npublic class ((( {\n",
            ProjectSourceOf("Same", "public class Good {\n}\n")
        ]
    )
    discovery := ProjectDiscoveryOf(provider, [])

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null

    // The broken file is enumerated first and contributes nothing; the good one still answers.
    assert provider.SourceFilePaths().Count == 2
    assert discovery.ResolveVisibleProjectType(
        "Good",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert Path.GetFileName(declaration.File) == "good.nl"
}

test "the declaring file of every resolved type is recorded for the project index" {
    provider := ProjectProviderOf(
        ["/p/one.nl", "/p/two.nl"],
        [
            ProjectSourceOf("Same", "public class First {\n}\n"),
            ProjectSourceOf("Far", "public class Second {\n}\n")
        ]
    )
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    provider.AddProjectUnitsTo(context)
    declarationFiles := new Dictionary<string, string>(StringComparer.Ordinal)
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        declarationFiles
    )

    resolved := BuiltInTypes.Unknown as TypeInfo
    declaration: SymbolDeclaration? = null
    inaccessible: string? = null

    // The namespace-sweep hit records...
    assert discovery.ResolveVisibleProjectType(
        "First",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    // ...and so does the unique-exported fallback.
    assert discovery.ResolveVisibleProjectType(
        "Second",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )

    assert declarationFiles.Count == 2
    assert Path.GetFileName(declarationFiles["First"]) == "one.nl"
    assert Path.GetFileName(declarationFiles["Second"]) == "two.nl"

    // A miss records nothing.
    assert !discovery.ResolveVisibleProjectType(
        "Absent",
        "Same",
        true,
        out resolved,
        out declaration,
        out inaccessible
    )
    assert declarationFiles.Count == 2
}

test "the declaration context receives the project units in enumeration order" {
    provider := ProjectProviderOf(
        ["/p/second.nl", "/p/first.nl"],
        [
            ProjectSourceOf("Same", "public class FromSecond {\n}\n"),
            ProjectSourceOf("Same", "public class FromFirst {\n}\n")
        ]
    )
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    provider.AddProjectUnitsTo(context)

    // Every parseable unit arrives, and each is attributed to the file it came from — which is what
    // makes the context's own walks agree with the provider's order.
    selection := new AnalyzerSourceTypeSelection(BuiltInTypes.Unknown, null, null, false)
    assert context.TryResolveProjectTypeInNamespace("FromSecond", "Same", false, out selection)
    assert Path.GetFileName(selection.FilePath) == "second.nl"
    assert context.TryResolveProjectTypeInNamespace("FromFirst", "Same", false, out selection)
    assert Path.GetFileName(selection.FilePath) == "first.nl"
}
