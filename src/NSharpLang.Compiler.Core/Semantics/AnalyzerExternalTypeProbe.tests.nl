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
        ProbeNamespaces(["Nonexistent.Namespace", "System.Text"])
    )
    leading := new AnalyzerExternalTypeProbe(
        ProbeAssemblies(),
        ProbeNamespaces(["System.Text", "Nonexistent.Namespace"])
    )
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
        ProbeNamespaces(["System.Te"])
    )
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

test "the scan's remembered guess never outranks an import the file wrote" {
    assemblies := ProbeAssemblies()
    namespaces := ProbeNamespaces([])
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)

    // Resolved with no imports at all, so this came from the exported-name scan — whichever CoreLib
    // type named `Aes` it meets first — and is remembered under the BARE spelling.
    assert ProbeTypeName(probe.ResolveExternalType("Aes")) == "System.Runtime.Intrinsics.Arm.Aes"

    // A file that IMPORTS the other `Aes` means that one. The remembered guess is asked only after
    // the file's own chain and its imports, so it cannot answer for a file that named a nearer one —
    // before `SimpleNamePrecedence` reached the metadata probe it did, and every later file inherited
    // the first file's guess.
    namespaces.Add("System.Runtime.Intrinsics.X86")
    assert ProbeTypeName(probe.ResolveExternalType("Aes")) == "System.Runtime.Intrinsics.X86.Aes"
}

test "the scan's guess is remembered: it still answers once its assemblies are gone" {
    assemblies := ProbeAssemblies()
    namespaces := ProbeNamespaces([])
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)

    assert ProbeTypeName(probe.ResolveExternalType("Encoding")) == "System.Text.Encoding"

    // Take away everything the probe could resolve FROM. Both live lists are the analyzer's own, so
    // the probe sees the change — and it still answers from what it remembered.
    assemblies.Clear()
    assert ProbeTypeName(probe.ResolveExternalType("Encoding")) == "System.Text.Encoding"

    // A probe with the same (now empty) inputs and no history answers nothing.
    fresh := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    assert fresh.ResolveExternalType("Encoding") == null

    // A MISS is not remembered past the assembly count that proved it, so it is genuinely retried
    // once the inputs come back.
    assert probe.ResolveExternalType("Rune") == null
    assemblies.Add(typeof(object).get_Assembly())
    assert ProbeTypeName(probe.ResolveExternalType("Rune")) == "System.Text.Rune"
}

test "the file's own and enclosing namespaces answer before any import" {
    namespaces := ProbeNamespaces(["System.Runtime.Intrinsics.X86"])
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), namespaces)

    // Rules 1 and 2 of `SimpleNamePrecedence`, over metadata: a file in
    // `System.Runtime.Intrinsics.Arm.Probe` sits inside `System.Runtime.Intrinsics.Arm`, whose `Aes`
    // is nearer than the imported `X86.Aes`.
    probe.BeginAnalysis("System.Runtime.Intrinsics.Arm.Probe")
    assert ProbeTypeName(probe.ResolveExternalType("Aes")) == "System.Runtime.Intrinsics.Arm.Aes"
    // And a qualifier is read through the same chain: `Arm.Aes` inside `System.Runtime.Intrinsics`.
    probe.BeginAnalysis("System.Runtime.Intrinsics.Probe")
    assert ProbeTypeName(probe.ResolveExternalType("Arm.Aes")) == "System.Runtime.Intrinsics.Arm.Aes"
    assert ProbeTypeName(probe.ResolveExternalType("X86.Aes")) == "System.Runtime.Intrinsics.X86.Aes"

    // A file elsewhere has no such chain, so the import answers.
    probe.BeginAnalysis("Elsewhere")
    assert ProbeTypeName(probe.ResolveExternalType("Aes")) == "System.Runtime.Intrinsics.X86.Aes"
    // `NamespaceDeclares` asks exactly one namespace, never widening a bare name into a scan.
    assert probe.NamespaceDeclares("System.Runtime.Intrinsics.Arm", "Aes")
    assert !probe.NamespaceDeclares(null, "Aes")
    assert !probe.NamespaceDeclares("System.Runtime", "Aes")
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

test "an INVISIBLE metadata type is no answer: System.TokenType is internal to CoreLib" {
    // `Assembly.GetType` answers for internal types too. A program cannot spell one, so it must
    // not resolve a qualified spelling and must not make a source `TokenType` ambiguous (NL209).
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces(["System"]))
    assert probe.ResolveExactExternalType("System.TokenType") == null
    assert probe.NamespaceDeclares("System", "TokenType") == false
    assert probe.NamespaceDeclares("System", "TimeSpan") == true
    assert ProbeExactName(probe.ResolveExactExternalType("System.TimeSpan")) == "System.TimeSpan"
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
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "Func")) == "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17"

    // `Action` has no arity-1..16 gap either, but `Action` itself is non-generic, so arity 0 is not
    // in the sweep at all: the sweep starts at 1 and 0 is never a reportable "available arity".
    assert ProbeArityText(probe.KnownGenericHeadArities(null, "Action")) == "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16"

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

test "the imported half answers only for an imported namespace, and never by exported-name scan" {
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces(["System.Text"]))

    // Step 2 alone: an imported namespace supplies the name.
    assert ProbeTypeName(probe.ResolveImportedExternalType("StringBuilder")) == "System.Text.StringBuilder"

    // Step 3 is NOT behind it. `Version` lives in `System`, which nothing here imported, so the
    // ordered probe finds it by exported-name scan and the imported half does not find it at all.
    // That difference is the whole reason the two halves are separate: an import is something the
    // file asked for, and the scan is a project-wide guess.
    assert probe.ResolveImportedExternalType("Version") == null
    assert ProbeTypeName(probe.ResolveExternalType("Version")) == "System.Version"
}

test "one imported namespace is asked at a time, so the caller owns the order and the exclusions" {
    probe := new AnalyzerExternalTypeProbe(ProbeAssemblies(), ProbeNamespaces(["System.Text", "System"]))

    // `StringBuilder` is declared by exactly one of the two imported namespaces, and the question is
    // asked of each namespace on its own: that is what lets NL209's owner skip an import that merely
    // names a lexical namespace, or the one a source declaration already claimed, and still walk the
    // rest in import order.
    assert probe.NamespaceDeclares("System.Text", "StringBuilder")
    assert !probe.NamespaceDeclares("System", "StringBuilder")

    // A name no imported namespace declares answers nothing, whatever the assemblies export — the
    // exported-name scan is `ResolveExternalType`'s last step and is not behind this question.
    assert !probe.NamespaceDeclares("System.Text", "XDocument")
    assert !probe.NamespaceDeclares("System", "XDocument")
}

test "a remembered miss is retried once another assembly is loaded" {
    // The miss memo is what makes the NL209 sweep affordable, and its invalidation is the assembly
    // COUNT: the analyzer's list only grows while a file's imports are processed, so a miss proved
    // against a shorter list must not stand once a longer one could answer.
    assemblies := new List<Assembly>()
    probe := new AnalyzerExternalTypeProbe(assemblies, ProbeNamespaces(["System.Text"]))

    assert !probe.NamespaceDeclares("System.Text", "StringBuilder")

    for loaded in ProbeAssemblies() {
        assemblies.Add(loaded)
    }

    assert probe.NamespaceDeclares("System.Text", "StringBuilder")
}
