namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices


// THE EDITOR'S TYPE UNIVERSE IS THE ANALYZER'S, AND IT GROWS WHILE THE EDITOR IS OPEN.
//
// The first block is the centre of slice 4 and the one nothing in the tree said before. Every other
// block here exists to keep it honest.
//
// A real `MetadataLoadContext` is opened over the shared framework, exactly as the analyzer opens
// one, and the assembly list is handed to the catalog BY REFERENCE — the same seam the analyzer uses
// for `_mlcAssemblies`. Growing that list is what `Analyzer.LoadFromProjectConfig` does when the user
// opens a file from a project directory for the first time, which is AFTER the window is up.
func EtcatContext(): MetadataLoadContext {
    resolver := new PathAssemblyResolver(Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll"))
    return new MetadataLoadContext(resolver, AnalyzerMetadataLoadPolicy.MetadataCoreAssemblyName())
}

func EtcatHolds(values: List<string>, value: string): bool {
    index := 0
    while index < values.Count {
        if values[index] == value {
            return true
        }

        index = index + 1
    }

    return false
}

func EtcatHoldsType(values: List<EditorImportableType>, fullName: string): bool {
    index := 0
    while index < values.Count {
        if values[index].FullName == fullName {
            return true
        }

        index = index + 1
    }

    return false
}

// ── THE CENTRE: the caches are keyed on the universe's identity ───────────────

test "a namespace set computed before an assembly joins is not the answer after it joins" {
    context := EtcatContext()
    assemblies := new List<Assembly>()

    // The pre-project universe. `System.Runtime` is a pure facade and exports NOTHING (022/4a), so
    // the namespace set at this point is the policy owner's seeds and not one type more.
    assemblies.Add(context.LoadFromAssemblyName("System.Runtime"))
    catalog := new EditorTypeCatalog(assemblies)

    // The user types `import System.Text.` before the project's packages have loaded.
    before := catalog.NamespaceSuggestions("System.Text.")
    assert !EtcatHolds(before, "Json")

    // `LoadFromProjectConfig` arrives and appends. The list is the SAME object the catalog holds.
    assemblies.Add(context.LoadFromAssemblyName("System.Text.Json"))

    // THE SECOND COMPLETION MUST SEE IT. A cache filled by the first call and never invalidated
    // would answer the pre-project set forever, which is the exact defect this owner exists to
    // remove: the editor would keep insisting the user's own dependency does not exist.
    after := catalog.NamespaceSuggestions("System.Text.")
    assert EtcatHolds(after, "Json")

    // The seeds are still there — invalidation drops the CACHE, not the policy's floor.
    assert EtcatHolds(after, "RegularExpressions")
}

// MEASURED BY MUTATION, and the reason this block is titled what it is: dropping the identity key
// fails the block ABOVE and not this one. The exported-type tables are parallel to an append-only
// list BY INDEX, so a table loaded for index 0 stays index 0's however far the list grows — they
// need no invalidation. What this block owns is the BEHAVIOUR the slice exists for — an assembly
// that arrives late is visible to the scan-backed answers — and the index-parallel property that
// behaviour rests on.
test "an assembly that arrives late is visible to the scan-backed answers" {
    context := EtcatContext()
    assemblies := new List<Assembly>()

    // INDEX 0 MUST EXPORT SOMETHING for this block to mean anything. Measured by mutation: with the
    // facade at index 0 the exported tables can be mis-keyed and nothing notices, because a table of
    // length zero is refilled every time. `System.Private.CoreLib` exports 1,378 types, so a table
    // that stopped being index-parallel would answer CoreLib's types for the assembly that arrives
    // later and this block would fail.
    assemblies.Add(context.LoadFromAssemblyName("System.Private.CoreLib"))
    catalog := new EditorTypeCatalog(assemblies)

    // A simple-name resolution that MISSES is not remembered as a miss — misses are never memoised,
    // so the second ask is a fresh scan rather than a replay of the first.
    assert catalog.ResolveBySimpleName("JsonSerializer") == null
    assert !EtcatHoldsType(catalog.ImportableTypes("JsonSer"), "System.Text.Json.JsonSerializer")

    assemblies.Add(context.LoadFromAssemblyName("System.Text.Json"))

    assert catalog.ResolveBySimpleName("JsonSerializer") != null
    assert EtcatHoldsType(catalog.ImportableTypes("JsonSer"), "System.Text.Json.JsonSerializer")

    // And the type resolves through the ordinary entry point, which is what hover asks.
    resolved := catalog.ResolveType("JsonSerializer")
    assert resolved != null
    assert resolved.get_FullName() == "System.Text.Json.JsonSerializer"
}

// ── the facade asymmetry the owner is written around (022/4a) ────────────────

test "GetType follows a type forwarder and the exported-type scan does not" {
    context := EtcatContext()
    assemblies := new List<Assembly>()

    // `System.Runtime` alone: a pure facade of forwarders.
    assemblies.Add(context.LoadFromAssemblyName("System.Runtime"))
    catalog := new EditorTypeCatalog(assemblies)

    // BY FULL NAME the facade answers, because a metadata context follows forwarders for `GetType`.
    byFullName := catalog.ResolveByFullName("System.String")
    assert byFullName != null

    // BY SIMPLE NAME it cannot, because `GetExportedTypes` does NOT follow them — the facade exports
    // zero types. This is why the editor's universe depends on `System.Private.CoreLib` being in the
    // analyzer's list, and not merely on `System.Runtime` being there.
    assert catalog.ResolveBySimpleName("String") == null

    assemblies.Add(context.LoadFromAssemblyName("System.Private.CoreLib"))
    assert catalog.ResolveBySimpleName("String") != null
}

test "the analyzer's common-assembly table carries the core library the scan depends on" {
    names := ExternalAssemblyScan.CommonAssemblyNames()
    found := false
    index := 0
    while index < names.Length {
        if names[index] == "System.Private.CoreLib" {
            found = true
        }

        index = index + 1
    }

    // Stated here rather than left implicit: drop this entry and the editor's simple-name completion
    // and namespace list go empty while full-name hover keeps working, which would read as a
    // completion bug and be diagnosed nowhere near its cause.
    assert found
}

// ── the reads the move depends on, over METADATA types ───────────────────────

test "IsPublic is a TOP-LEVEL test and a public nested type answers false" {
    context := EtcatContext()
    assemblies := new List<Assembly>()
    assemblies.Add(context.LoadFromAssemblyName("System.Private.CoreLib"))
    catalog := new EditorTypeCatalog(assemblies)

    topLevel := catalog.ResolveByFullName("System.String")
    assert topLevel != null
    assert topLevel.get_IsPublic()
    assert !topLevel.get_IsNested()

    // A PUBLIC NESTED type: `IsPublic` is FALSE for it, because the CLR spells that `IsNestedPublic`.
    // 022/4a measured 138 of 1,498 exported types answering false here, and 138 was exactly the
    // nested count — so "the exported scan yields public types, therefore IsPublic is true" is a
    // FALSE derivation, and this block is why the owner reads the real property instead.
    nested := catalog.ResolveByFullName("System.Collections.Generic.List`1+Enumerator")
    assert nested != null
    assert nested.get_IsNested()
    assert !nested.get_IsPublic()

    // And it is not offered, which is the behaviour that would have broken.
    assert catalog.Offerable(nested) == null
    assert catalog.Offerable(topLevel) != null
}

test "full-name resolution is case-SENSITIVE, which is a property of the read" {
    context := EtcatContext()
    assemblies := new List<Assembly>()
    assemblies.Add(context.LoadFromAssemblyName("System.Private.CoreLib"))
    catalog := new EditorTypeCatalog(assemblies)

    assert catalog.ResolveByFullName("System.String") != null

    // The C# this replaces spelled `ignoreCase: false` as a named argument and said in its header
    // that exactness is mechanical rather than curated. The one-argument overload IS that read.
    assert catalog.ResolveByFullName("system.string") == null
}

test "an array resolves through its element, one rank per call, and a missing element answers null" {
    context := EtcatContext()
    assemblies := new List<Assembly>()
    assemblies.Add(context.LoadFromAssemblyName("System.Private.CoreLib"))
    catalog := new EditorTypeCatalog(assemblies)

    single := catalog.ResolveType("string[]")
    assert single != null
    assert single.get_FullName() == "System.String[]"

    assert catalog.ResolveType("NSharpLangNoSuchType[]") == null
}

test "a miss is an answer and the curated roster is offered at an empty prefix" {
    context := EtcatContext()
    assemblies := new List<Assembly>()
    assemblies.Add(context.LoadFromAssemblyName("System.Private.CoreLib"))
    catalog := new EditorTypeCatalog(assemblies)

    assert catalog.ResolveType("NSharpLangNoSuchTypeAtAll") == null

    // An empty prefix still answers the roster — general completion stays useful without posting the
    // whole framework — and never exceeds the policy owner's cap.
    empty := catalog.ImportableTypes("")
    assert empty.Count > 0
    assert empty.Count <= EditorTypeCatalogFacts.MaxImportableTypeResults()
    assert EtcatHoldsType(empty, "System.String")

    // A prefix filters, and the cap holds where the scan is wide.
    wide := catalog.ImportableTypes("S")
    assert wide.Count <= EditorTypeCatalogFacts.MaxImportableTypeResults()
}
