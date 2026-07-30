namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

// Native contracts for the analyzer's external (MetadataLoadContext) type probe. The two methods it
// absorbed were `private` in Analyzer.cs, so no test named them: their behaviour was pinned only
// indirectly, through end-to-end diagnostics. This is their first DIRECT pinning, and it deliberately
// pins the CACHE's participation in the probe order, which is the part that is easy to mistake for an
// optimisation and delete.

func ProbeAssemblies(): List<Assembly> {
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(object).get_Assembly())
    return assemblies
}

func ProbeNamespaces(names: string[]): List<string> {
    namespaces := new List<string>()
    index := 0
    while index < names.Length {
        namespaces.Add(names[index])
        index = index + 1
    }
    return namespaces
}

func ProbeTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    reflection := candidate as ReflectionTypeInfo
    if reflection == null {
        return "<not-reflection>"
    }

    resolved := reflection.Type
    return resolved.get_FullName()
}

func ProbeExactName(candidate: Type?): string {
    if candidate == null {
        return "<null>"
    }
    return candidate.get_FullName()
}

func ProbeArityText(arities: List<int>): string {
    text := ""
    index := 0
    while index < arities.Count {
        if index > 0 {
            text = text + ","
        }
        text = text + arities[index].ToString()
        index = index + 1
    }
    return text
}

test "every import is tried IN ORDER, and the first one that resolves answers" {
    namespaces := ProbeNamespaces(["System.Text", "System"])
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), namespaces)

    // Each name is found through its own import: `Encoding` under System.Text, `DateTime` under
    // System. So the loop does not stop at the first import — it keeps going until one resolves.
    assert ProbeTypeName(probe.ResolveExternalType("Encoding")) == "System.Text.Encoding"
    assert ProbeTypeName(probe.ResolveExternalType("DateTime")) == "System.DateTime"
    assert ProbeTypeName(probe.ResolveExternalType("StringBuilder")) == "System.Text.StringBuilder"

    // An import that resolves NOTHING does not shadow a later one that does, in either position.
    trailing := new AnalyzerExternalTypeProbe(
        ProbeAssemblies(),
        ProbeNamespaces(["Nonexistent.Namespace", "System.Text"]))
    leading := new AnalyzerExternalTypeProbe(
        ProbeAssemblies(),
        ProbeNamespaces(["System.Text", "Nonexistent.Namespace"]))
    assert ProbeTypeName(trailing.ResolveExternalType("Encoding")) == "System.Text.Encoding"
    assert ProbeTypeName(leading.ResolveExternalType("Encoding")) == "System.Text.Encoding"

    // Import order is the LIST order, so which import wins when two of them could both answer is
    // decided by the loop and nothing else — there is no scoring, no most-specific rule, and no
    // ambiguity diagnostic. `Assembly.GetType` is exact, so the winner is simply the first import
    // whose "<namespace>.<name>" names a real type.
    // The prefix is composed with a single dot and nothing is trimmed: an import that is a PREFIX of
    // the right namespace does not resolve.
    prefixOnly := new AnalyzerExternalTypeProbe(
        ProbeAssemblies(),
        ProbeNamespaces(["System.Te"]))
    assert prefixOnly.ResolveExternalType("xt.Encoding") == null
}

test "a name no import prefixes still resolves by exported simple name or full name" {
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces([]))

    // No imports at all: the only channel left is the exported-type scan, which matches on the
    // simple name OR the full name.
    assert ProbeTypeName(probe.ResolveExternalType("System.DateTime")) == "System.DateTime"
    assert ProbeTypeName(probe.ResolveExternalType("DateTime")) == "System.DateTime"

    // A spelling nothing exports answers null rather than throwing.
    assert probe.ResolveExternalType("Zzzqqqxyz") == null
    assert probe.ResolveExternalType("") == null
    assert probe.ResolveExternalType("Some.Unknown.Thing") == null
}

test "the cache is consulted BEFORE the imports, so a resolved spelling is never reconsidered" {
    assemblies := ProbeAssemblies()
    namespaces := ProbeNamespaces([])
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)

    // Resolved with no imports at all, so this came from the exported-name scan and is now cached
    // under the BARE spelling.
    assert ProbeTypeName(probe.ResolveExternalType("Encoding")) == "System.Text.Encoding"

    // Now take away everything the probe could resolve FROM, and add an import. Both live lists are
    // the analyzer's own, so the probe sees both changes — and it still answers, which is only
    // possible if the cache is consulted before the import loop and before the exported-name scan.
    // That is why this cache cannot be dropped or rebuilt part-way through an analysis: history, not
    // just inputs, decides the answer.
    assemblies.Clear()
    namespaces.Add("System.Text")
    assert ProbeTypeName(probe.ResolveExternalType("Encoding")) == "System.Text.Encoding"

    // A probe with the same (now empty) inputs and no history answers nothing.
    fresh := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    assert fresh.ResolveExternalType("Encoding") == null

    // A MISS is not cached, so it is genuinely retried once the inputs come back.
    assert probe.ResolveExternalType("Rune") == null
    assemblies.Add(typeof(object).get_Assembly())
    assert ProbeTypeName(probe.ResolveExternalType("Rune")) == "System.Text.Rune"
}

test "the assembly list is live: an assembly loaded after construction is visible" {
    assemblies := new List<Assembly>()
    probe := new AnalyzerExternalTypeProbe(assemblies, ProbeNamespaces(["System"]))

    // Nothing loaded yet.
    assert probe.ResolveExternalType("DateTime") == null

    assemblies.Add(typeof(object).get_Assembly())
    assert ProbeTypeName(probe.ResolveExternalType("DateTime")) == "System.DateTime"

    // Clearing it (which the analyzer does on Dispose) takes the answers away again for anything not
    // already cached, while the cached ones remain — the probe holds the reference, not a copy.
    assemblies.Clear()
    assert ProbeTypeName(probe.ResolveExternalType("DateTime")) == "System.DateTime"
    assert probe.ResolveExternalType("TimeSpan") == null
}

test "the exact probe requires a qualified spelling and shares the ordered probe's cache" {
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces(["System"]))

    // Fully qualified: found. Bare: NOT found — the exact probe does no import prefixing and no
    // exported-name scan, which is what makes it usable to tell a namespace from a type.
    assert ProbeExactName(probe.ResolveExactExternalType("System.DateTime")) == "System.DateTime"
    assert probe.ResolveExactExternalType("DateTime") == null
    assert probe.ResolveExactExternalType("System") == null
    assert probe.ResolveExactExternalType("System.Nonexistent") == null

    // One cache, both directions. An exact hit is visible to the ordered probe under the qualified
    // spelling, and an ordered hit is visible to the exact probe under whatever key it cached.
    assert ProbeTypeName(probe.ResolveExternalType("System.TimeSpan")) == "System.TimeSpan"
    assert ProbeExactName(probe.ResolveExactExternalType("System.TimeSpan")) == "System.TimeSpan"

    shared := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces(["System"]))
    assert ProbeExactName(shared.ResolveExactExternalType("System.Guid")) == "System.Guid"
    assert ProbeTypeName(shared.ResolveExternalType("System.Guid")) == "System.Guid"
}

test "each resolution hands back a FRESH ReflectionTypeInfo over the same Type" {
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces(["System"]))

    first := probe.ResolveExternalType("DateTime") as ReflectionTypeInfo
    second := probe.ResolveExternalType("DateTime") as ReflectionTypeInfo
    assert first != null
    assert second != null

    // Different wrappers — callers must never compare these by reference — over one identical Type.
    assert !Object.ReferenceEquals(first, second)
    assert first.Type == second.Type
}

test "known generic head arities sweep the compiler table and the arity-qualified metadata probe" {
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces(["System"]))

    // With no well-known-type facts the table half answers nothing, so every arity found here came
    // from the arity-qualified metadata probe. `Func` exists at 1..17 in the core library.
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "Func"))
        == "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17"

    // `Action` has no arity-1..16 gap either, but `Action` itself is non-generic, so arity 0 is not
    // in the sweep at all: the sweep starts at 1 and 0 is never a reportable "available arity".
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "Action"))
        == "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16"

    // `Tuple` and `ValueTuple` stop at 8, which is what makes the "available arities are ..."
    // diagnostic finite and truthful.
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "Tuple")) == "1,2,3,4,5,6,7,8"
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "ValueTuple")) == "1,2,3,4,5,6,7,8"
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "Nullable")) == "1"

    // A spelling with no generic form at any arity answers empty, and so does a name that resolves
    // only as a NON-generic type: the probe requires an open DEFINITION, not merely a hit.
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "Lst")) == ""
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "DateTime")) == ""
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "")) == ""
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "Zzzqqqxyz")) == ""

    // The 17 ceiling is the CLR's own limit, so nothing above it is ever reported.
    highest := probe.KnownGenericHeadArities(null, "Func")
    assert highest.Count == 17
    assert highest[16] == 17
}

test "the arity sweep answers ascending and each entry names an open definition" {
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces(["System"]))

    arities := probe.KnownGenericHeadArities(null, "Tuple")
    index := 1
    while index < arities.Count {
        assert arities[index - 1] < arities[index]
        index = index + 1
    }

    // Every arity it reported must actually resolve to an open definition of that arity through the
    // same probe, which is what the diagnostic then tells the user.
    check := 0
    while check < arities.Count {
        arity := arities[check]
        resolved := probe.ResolveExternalType("Tuple`" + arity.ToString()) as ReflectionTypeInfo
        assert resolved != null
        resolvedType := resolved.Type
        assert resolvedType.get_IsGenericTypeDefinition()
        assert resolvedType.GetGenericArguments().Length == arity
        check = check + 1
    }
}
