namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import NSharpLang.Compiler


// THE BINDING SCOPE'S OWN ROWS: the external type catalog every file's binding reads through, and
// the columnar binder's built-in spellings against the analyzer's.
test "a prepared external type catalog answers every file from one retained scan" {
    catalog := new ColumnarExternalTypeCatalog()

    // Before Prepare there is no scan and no answer — the catalog never opens one on demand.
    unpreparedResolution := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert !catalog.IsPrepared
    assert !catalog.TryGet(0, "Console", out unpreparedResolution)

    factsById := new Dictionary<int, ColumnarSourceBindingFacts>()
    firstFile := new ColumnarSourceBindingFacts()
    firstFile.UnaliasedNamespaceImports.Add("System")
    secondFile := new ColumnarSourceBindingFacts()
    secondFile.UnaliasedNamespaceImports.Add("System")
    factsById[0] = firstFile
    factsById[1] = secondFile

    catalog.Prepare(null, factsById)
    assert catalog.IsPrepared

    firstResolution := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    secondResolution := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert catalog.TryGet(0, "Console", out firstResolution)
    assert catalog.TryGet(1, "Console", out secondResolution)

    // Two files asking the same question of the same retained scan get the same answer. Before the
    // scan was retained each of these was a whole MetadataLoadContext over every referenced assembly.
    assert firstResolution.Status == ExternalAssemblyTypeLookupStatus.Found
    assert secondResolution.Status == ExternalAssemblyTypeLookupStatus.Found
    assert firstResolution.HasRuntimeType
    assert secondResolution.HasRuntimeType
    firstType := firstResolution.RuntimeType
    secondType := secondResolution.RuntimeType
    assert firstType.get_FullName() == "System.Console"
    assert secondType.get_FullName() == "System.Console"
    assert firstResolution.SemanticTypeIdentity == secondResolution.SemanticTypeIdentity

    // A repeat of an already-cached key is still the same answer, and a re-Prepare replaces the scan
    // without stranding the catalog.
    repeat := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert catalog.TryGet(0, "Console", out repeat)
    repeatType := repeat.RuntimeType
    assert repeatType.get_FullName() == "System.Console"

    catalog.Prepare(null, factsById)
    afterRePrepare := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert catalog.TryGet(0, "Console", out afterRePrepare)
    afterRePrepareType := afterRePrepare.RuntimeType
    assert afterRePrepareType.get_FullName() == "System.Console"

    // A name that resolves nowhere is still a recorded decline, not an exception.
    missing := new ExternalAssemblyTypeResolution(ExternalAssemblyTypeLookupStatus.Unknown, "", typeof(object), false)
    assert catalog.TryGet(0, "NoSuchExternalOwnerName", out missing)
    assert missing.Status == ExternalAssemblyTypeLookupStatus.Missing
}

// THE COLUMNAR BINDER'S GAP, PINNED TO EXACTLY ONE NAME. Every spelling the owner admits must bind
// to a runtime type except `void`, which is not a type a local can hold.
test "analyzer type reference facts pin the columnar void gap to exactly one spelling" {
    // The eighteen spellings the analyzer's owner admits (`AnalyzerTypeReferenceFacts`).
    spellings := ["bool", "byte", "sbyte", "short", "ushort", "int", "uint", "long", "ulong", "nint", "nuint", "char", "float", "double", "decimal", "string", "object", "void"]
    unbound := 0

    index := 0
    while index < spellings.Length {
        name := spellings[index]
        assert AnalyzerTypeReferenceFacts.IsBuiltInTypeName(name), name
        bound := typeof(object)
        if !ColumnarBindingScopeFacts.TryResolveExplicitBuiltin(name, out bound) {
            unbound = unbound + 1
            assert name == "void"
        }

        index = index + 1
    }

    assert unbound == 1
}
