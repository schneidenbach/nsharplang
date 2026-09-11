namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Runtime.InteropServices


// CONTRACTS FOR WHAT A FAILED DOC LOOKUP SAYS ABOUT UNLOADABLE REFERENCE-PACK ASSEMBLIES.
// The reference packs offer more assemblies than the CLI's runtime carries, so the loader
// skips-and-notes rather than crashing, and `DescribeDocLookupMiss` decides when that note is
// worth surfacing. Three doors are contracted here: a DOCUMENTED type whose documenting assembly
// is unloadable names the type and the assembly; a query that names an unloadable assembly itself
// gets the assembly note; and every other miss says nothing at all — the message must read
// exactly as it always has.
//
// ATTRIBUTION IS RECORDED, NOT INFERRED. The documenting assembly is the XML file that carried
// the doc id, because `.Abstractions`-style assembly names are not namespace prefixes and an
// inference would go silent exactly there — which is what the `IFileProvider` contract pins.
//
// THE NOTE IS DETERMINISTIC BY SORTING. Doc ids arrive in dictionary walk order; the shuffled
// contract holds the wording identical across arrival orders.
func DqkStrings2(first: string, second: string): string[] {
    values := new string[](2)
    values[0] = first
    values[1] = second
    return values
}

func DqkStrings1(only: string): string[] {
    values := new string[](1)
    values[0] = only
    return values
}

test "no unloadable assemblies means no note, whatever the query" {
    docIds := DqkStrings1("T:Microsoft.AspNetCore.HttpLogging.HttpLoggingOptions")
    owners := DqkStrings1("Microsoft.AspNetCore.HttpLogging")

    assert DocQueryKernels.DescribeDocLookupMiss("HttpLoggingOptions", docIds, owners, new string[](0)) == null
}

test "a blank query earns no note even when assemblies are unloadable" {
    docIds := DqkStrings1("T:Microsoft.AspNetCore.HttpLogging.HttpLoggingOptions")
    owners := DqkStrings1("Microsoft.AspNetCore.HttpLogging")
    unloadable := DqkStrings1("Microsoft.AspNetCore.HttpLogging")

    assert DocQueryKernels.DescribeDocLookupMiss("", docIds, owners, unloadable) == null
    assert DocQueryKernels.DescribeDocLookupMiss("   ", docIds, owners, unloadable) == null
}

test "a documented type whose documenting assembly is unloadable names the type and the assembly" {
    docIds := DqkStrings1("T:Microsoft.AspNetCore.HttpLogging.HttpLoggingOptions")
    owners := DqkStrings1("Microsoft.AspNetCore.HttpLogging")
    unloadable := DqkStrings1("Microsoft.AspNetCore.HttpLogging")

    note := DocQueryKernels.DescribeDocLookupMiss("HttpLoggingOptions", docIds, owners, unloadable)
    assert note == "The reference packs document 'Microsoft.AspNetCore.HttpLogging.HttpLoggingOptions' (assembly 'Microsoft.AspNetCore.HttpLogging'), but that assembly is not part of this runtime, so `nlc query doc` cannot describe it."

    qualified := DocQueryKernels.DescribeDocLookupMiss("Microsoft.AspNetCore.HttpLogging.HttpLoggingOptions", docIds, owners, unloadable)
    assert qualified == note
}

test "attribution follows the documenting assembly, not a namespace prefix" {
    docIds := DqkStrings1("T:Microsoft.Extensions.FileProviders.IFileProvider")
    owners := DqkStrings1("Microsoft.Extensions.FileProviders.Abstractions")
    unloadable := DqkStrings1("Microsoft.Extensions.FileProviders.Abstractions")

    note := DocQueryKernels.DescribeDocLookupMiss("IFileProvider", docIds, owners, unloadable)
    assert note != null
    assert note == "The reference packs document 'Microsoft.Extensions.FileProviders.IFileProvider' (assembly 'Microsoft.Extensions.FileProviders.Abstractions'), but that assembly is not part of this runtime, so `nlc query doc` cannot describe it."
}

test "a documented type whose documenting assembly loaded fine earns no note" {
    docIds := DqkStrings1("T:System.Console")
    owners := DqkStrings1("System.Console")
    unloadable := DqkStrings1("Microsoft.AspNetCore.HttpLogging")

    assert DocQueryKernels.DescribeDocLookupMiss("Console", docIds, owners, unloadable) == null
}

test "the dotted-suffix door only opens for a query that contains a dot" {
    docIds := DqkStrings1("T:Microsoft.AspNetCore.Builder.WebSocketOptions")
    owners := DqkStrings1("Microsoft.AspNetCore.WebSockets")
    unloadable := DqkStrings1("Microsoft.AspNetCore.WebSockets")

    assert DocQueryKernels.DescribeDocLookupMiss("Builder.WebSocketOptions", docIds, owners, unloadable) != null
    assert DocQueryKernels.DescribeDocLookupMiss("SocketOptions", docIds, owners, unloadable) == null
}

test "several matches are sorted, capped at three, and counted — in any arrival order" {
    docIds := new string[](4)
    docIds[0] = "T:Zed.Widget"
    docIds[1] = "T:Alpha.Widget"
    docIds[2] = "T:Mid.Widget"
    docIds[3] = "T:Beta.Widget"
    owners := new string[](4)
    owners[0] = "Zed"
    owners[1] = "Alpha"
    owners[2] = "Mid"
    owners[3] = "Beta"
    unloadable := new string[](4)
    unloadable[0] = "Alpha"
    unloadable[1] = "Beta"
    unloadable[2] = "Mid"
    unloadable[3] = "Zed"

    note := DocQueryKernels.DescribeDocLookupMiss("Widget", docIds, owners, unloadable)
    assert note == "The reference packs document matching types whose assemblies are not part of this runtime: 'Alpha.Widget' (assembly 'Alpha'), 'Beta.Widget' (assembly 'Beta'), 'Mid.Widget' (assembly 'Mid'), and 1 more."

    reversedIds := new string[](4)
    reversedIds[0] = "T:Beta.Widget"
    reversedIds[1] = "T:Mid.Widget"
    reversedIds[2] = "T:Alpha.Widget"
    reversedIds[3] = "T:Zed.Widget"
    reversedOwners := new string[](4)
    reversedOwners[0] = "Beta"
    reversedOwners[1] = "Mid"
    reversedOwners[2] = "Alpha"
    reversedOwners[3] = "Zed"

    assert DocQueryKernels.DescribeDocLookupMiss("Widget", reversedIds, reversedOwners, unloadable) == note
}

test "a query that names an unloadable assembly itself gets the assembly note, longest dot-aligned name winning" {
    docIds := new string[](0)
    owners := new string[](0)
    unloadable := DqkStrings2("Microsoft.AspNetCore.Http", "Microsoft.AspNetCore.HttpLogging")

    note := DocQueryKernels.DescribeDocLookupMiss("Microsoft.AspNetCore.HttpLogging.SomethingMissing", docIds, owners, unloadable)
    assert note == "Assembly 'Microsoft.AspNetCore.HttpLogging' is installed as a reference pack but is not part of this runtime, so `nlc query doc` cannot describe its types."

    assert DocQueryKernels.DescribeDocLookupMiss("Microsoft.AspNetCore.Http", docIds, owners, unloadable) != null
    assert DocQueryKernels.DescribeDocLookupMiss("Microsoft.AspNetCore.Httpish.Thing", docIds, owners, unloadable) == null
    assert DocQueryKernels.DescribeDocLookupMiss("Consoel", docIds, owners, unloadable) == null
}

// ─── THE HOVER SENTENCE ──────────────────────────────────────────────────────────────────────
// A hover has room for one sentence and a `nlc query doc` answer has room for the whole summary,
// which is why the cut lives in a kernel rather than in either renderer.

test "a summary is cut at the first sentence-ending period and nowhere else" {
    // The common shape: one sentence, ending the string. Nothing is removed.
    assert DocQueryKernels.GetDocSummarySentence("Returns a non-negative random integer.") == "Returns a non-negative random integer."

    // Two sentences: the second is dropped, the period is KEPT.
    assert DocQueryKernels.GetDocSummarySentence("Copies the elements to a new array. The array is a shallow copy.") == "Copies the elements to a new array."

    // A PERIOD INSIDE A NAME IS NOT A SENTENCE END, because the next character is not whitespace.
    // This is the case that a naive `IndexOf('.')` gets wrong on most of the BCL.
    assert DocQueryKernels.GetDocSummarySentence("Gets the System.Console output writer.") == "Gets the System.Console output writer."
    assert DocQueryKernels.GetDocSummarySentence("Wraps List<T>.Add for the caller. See also Remove.") == "Wraps List<T>.Add for the caller."

    // `!` and `?` end a sentence too.
    assert DocQueryKernels.GetDocSummarySentence("Is the value set? Ask the parent.") == "Is the value set?"

    // NO SENTENCE-ENDING PUNCTUATION AT ALL RETURNS THE WHOLE TEXT rather than truncating at a
    // guess — a summary that does not punctuate is still the best answer available.
    assert DocQueryKernels.GetDocSummarySentence("A cache of loaded assemblies") == "A cache of loaded assemblies"

    // Null in, null out: a member with no documentation must reach hover as "no documentation".
    assert DocQueryKernels.GetDocSummarySentence(null) == null
    assert DocQueryKernels.GetDocSummarySentence("") == ""
}

// ROOT DISCOVERY MUST NOT DEPEND ON `Assembly.Location`. `GetReferencePackDirectories` climbs the FIRST
// non-empty path it is given; every path used to come from `Assembly.Location`, which is the empty
// string under a single-file host, so discovery would have fallen back to `DOTNET_ROOT` alone and
// produced nothing wherever that is unset. `DocQueryTypeIndex` now offers the runtime directory first.
// These blocks pin that the runtime directory IS a viable seed and that an all-empty seed is not.
test "the runtime directory climbs to a dotnet root that carries reference packs" {
    runtimeDirectory := RuntimeEnvironment.GetRuntimeDirectory()
    assert !string.IsNullOrWhiteSpace(runtimeDirectory)
    seeds := new string[](1)
    seeds[0] = runtimeDirectory
    directories := DocQueryKernels.GetReferencePackDirectories(seeds, null)
    assert directories.Length > 0
}

test "an all-empty seed discovers nothing without DOTNET_ROOT, which is the single-file failure" {
    seeds := new string[](2)
    seeds[0] = ""
    seeds[1] = ""
    assert DocQueryKernels.GetReferencePackDirectories(seeds, null).Length == 0

    // The same empty seed WITH a root still works, which is why the old reading degraded quietly
    // rather than failing: on a machine with DOTNET_ROOT set nothing looked wrong.
    runtimeDirectory := RuntimeEnvironment.GetRuntimeDirectory()
    root := DocQueryKernels.FindDotNetRootCandidate(runtimeDirectory)
    assert root != null
    assert DocQueryKernels.GetReferencePackDirectories(seeds, root).Length > 0
}
