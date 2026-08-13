namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// CONTRACTS FOR WHAT MAKES A NAMESPACE IMPORT USED (task 019 slice 7). These are the semantic
// assertions that came out of `Linter.cs` with the two known-namespace tables and the namespace arm
// of `CheckUnusedImports`, plus the rules the move made checkable rather than implied: the table's
// exact membership, its ordinal case sensitivity, and the fact that the member half is consulted
// for `System.Linq` and for nothing else.
//
// NL010 is BUILD-BLOCKING at `error` severity in the estate's own configuration, so a table row
// silently lost here does not merely under-report — it breaks a build that was green. Every count
// below is therefore an exact equality rather than a lower bound.

func LniuSet(names: string[]): HashSet<string> {
    result := new HashSet<string>(StringComparer.Ordinal)
    index := 0
    while index < names.Length {
        result.Add(names[index])
        index = index + 1
    }

    return result
}

func LniuNone(): HashSet<string> {
    return new HashSet<string>(StringComparer.Ordinal)
}

func LniuOne(name: string): HashSet<string> {
    result := new HashSet<string>(StringComparer.Ordinal)
    result.Add(name)
    return result
}

func LniuHas(names: string[], name: string): bool {
    index := 0
    while index < names.Length {
        if names[index] == name {
            return true
        }

        index = index + 1
    }

    return false
}

func LniuDistinctCount(names: string[]): int {
    seen := new HashSet<string>(StringComparer.Ordinal)
    index := 0
    while index < names.Length {
        seen.Add(names[index])
        index = index + 1
    }

    return seen.Count
}

func LniuTableNamespaces(): string[] {
    return ["System", "System.Collections.Generic", "System.Text", "System.Text.RegularExpressions", "System.IO", "System.Net.Http", "System.Text.Json", "System.Threading.Tasks", "System.Threading", "System.Linq"]
}


// ── the decision: which of the three answers a namespace gets ────────────────────────────────

test "a namespace the table does not name is reported USED, because unknown is not unused" {
    identifiers := LniuOne("Widget")
    members := LniuOne("Frobnicate")

    assert LinterNamespaceImportUsage.IsUsed("Acme.Widgets", identifiers, members)
    assert LinterNamespaceImportUsage.IsUsed("MyApp.Models", identifiers, members)

    // `System.Xml.Linq` is a real BCL namespace that the table does not carry, and it gets the
    // same conservative answer as a user namespace. The table is a whitelist of what NL010 may
    // flag, never a claim about what exists.
    assert LinterNamespaceImportUsage.IsUsed("System.Xml.Linq", identifiers, members)
    assert LinterNamespaceImportUsage.IsUsed("System.Diagnostics", identifiers, members)
}

test "the empty and whitespace spellings are unknown namespaces, so they are reported USED" {
    empty := LniuNone()

    assert LinterNamespaceImportUsage.IsUsed("", empty, empty)
    assert LinterNamespaceImportUsage.IsUsed("   ", empty, empty)
    assert LinterNamespaceImportUsage.IsUsed(".", empty, empty)
    assert LinterNamespaceImportUsage.IsUsed("System.", empty, empty)
}

test "a table namespace whose types are all absent is reported UNUSED" {
    identifiers := LniuOne("Widget")
    members := LniuOne("Frobnicate")

    assert LinterNamespaceImportUsage.IsUsed("System.IO", identifiers, members) == false
    assert LinterNamespaceImportUsage.IsUsed("System.Collections.Generic", identifiers, members) == false
    assert LinterNamespaceImportUsage.IsUsed("System", identifiers, members) == false
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", identifiers, members) == false
}

test "one named type is enough to mark its namespace used" {
    members := LniuNone()

    assert LinterNamespaceImportUsage.IsUsed("System.IO", LniuOne("File"), members)
    assert LinterNamespaceImportUsage.IsUsed("System.Collections.Generic", LniuOne("Dictionary"), members)
    assert LinterNamespaceImportUsage.IsUsed("System.Text", LniuOne("StringBuilder"), members)
    assert LinterNamespaceImportUsage.IsUsed("System.Text.RegularExpressions", LniuOne("Regex"), members)
    assert LinterNamespaceImportUsage.IsUsed("System.Net.Http", LniuOne("HttpClient"), members)
    assert LinterNamespaceImportUsage.IsUsed("System.Text.Json", LniuOne("JsonSerializer"), members)
    assert LinterNamespaceImportUsage.IsUsed("System.Threading.Tasks", LniuOne("Task"), members)
    assert LinterNamespaceImportUsage.IsUsed("System.Threading", LniuOne("CancellationToken"), members)
    assert LinterNamespaceImportUsage.IsUsed("System", LniuOne("Guid"), members)
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuOne("Enumerable"), members)
}

test "System.Linq is used by a CALL alone, with no LINQ type ever named" {
    // This is the whole reason the member half exists: `xs.Select(...)` names no type at all, and
    // without this arm every `import System.Linq` in an idiomatic file would be flagged.
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuNone(), LniuOne("Select"))
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuNone(), LniuOne("Where"))
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuNone(), LniuOne("FirstOrDefault"))
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuNone(), LniuOne("OrderDescending"))
}

test "the member half is consulted for System.Linq and for no other namespace" {
    // `File` is a `System.IO` TYPE. Seeing it as a member-access name — `x.File` — is not a use of
    // the import, and the table has no `System.IO` member row for it to match.
    assert LinterNamespaceImportUsage.IsUsed("System.IO", LniuNone(), LniuOne("File")) == false
    assert LinterNamespaceImportUsage.IsUsed("System.Text", LniuNone(), LniuOne("Encoding")) == false
    assert LinterNamespaceImportUsage.IsUsed("System", LniuNone(), LniuOne("Console")) == false

    // Symmetrically, a LINQ METHOD name appearing as a code identifier is not a type use.
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuOne("Select"), LniuNone()) == false
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuOne("Where"), LniuNone()) == false
}

test "either half alone answers for System.Linq, the one namespace carrying both" {
    typeOnly := LinterNamespaceImportUsage.IsUsed("System.Linq", LniuOne("IGrouping"), LniuNone())
    memberOnly := LinterNamespaceImportUsage.IsUsed("System.Linq", LniuNone(), LniuOne("GroupBy"))
    both := LinterNamespaceImportUsage.IsUsed("System.Linq", LniuOne("IGrouping"), LniuOne("GroupBy"))
    neither := LinterNamespaceImportUsage.IsUsed("System.Linq", LniuOne("Widget"), LniuOne("Frobnicate"))

    assert typeOnly
    assert memberOnly
    assert both
    assert neither == false
}

test "the lookup is ORDINAL: a namespace or name that differs in case does not match" {
    assert LinterNamespaceImportUsage.IsUsed("system.io", LniuOne("File"), LniuNone())
    assert LinterNamespaceImportUsage.IsUsed("SYSTEM", LniuOne("Guid"), LniuNone())

    // Those two are USED only because the namespace spelling missed the table entirely. Inside a
    // namespace that DOES match, a mis-cased type name is not a use.
    assert LinterNamespaceImportUsage.IsUsed("System.IO", LniuOne("file"), LniuNone()) == false
    assert LinterNamespaceImportUsage.IsUsed("System.Collections.Generic", LniuOne("list"), LniuNone()) == false
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuNone(), LniuOne("select")) == false
}

test "an identifier belonging to one namespace does not mark a different one used" {
    identifiers := LniuOne("StringBuilder")

    assert LinterNamespaceImportUsage.IsUsed("System.Text", identifiers, LniuNone())
    assert LinterNamespaceImportUsage.IsUsed("System.IO", identifiers, LniuNone()) == false
    assert LinterNamespaceImportUsage.IsUsed("System", identifiers, LniuNone()) == false
    assert LinterNamespaceImportUsage.IsUsed("System.Text.Json", identifiers, LniuNone()) == false
}

test "a file naming many types marks exactly the namespaces that provide them" {
    identifiers := LniuSet(["List", "Task", "Regex", "Widget"])
    members := LniuSet(["ToList", "Frobnicate"])

    assert LinterNamespaceImportUsage.IsUsed("System.Collections.Generic", identifiers, members)
    assert LinterNamespaceImportUsage.IsUsed("System.Threading.Tasks", identifiers, members)
    assert LinterNamespaceImportUsage.IsUsed("System.Text.RegularExpressions", identifiers, members)
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", identifiers, members)
    assert LinterNamespaceImportUsage.IsUsed("System.IO", identifiers, members) == false
    assert LinterNamespaceImportUsage.IsUsed("System.Net.Http", identifiers, members) == false
    assert LinterNamespaceImportUsage.IsUsed("System", identifiers, members) == false
}


// ── the table itself: exact membership, because a lost row breaks a green build ───────────────

test "the type half names exactly ten namespaces and nothing else" {
    namespaces := LniuTableNamespaces()
    index := 0
    total := 0
    while index < namespaces.Length {
        assert LinterNamespaceImportUsage.KnownTypeNames(namespaces[index]).Length > 0
        total = total + LinterNamespaceImportUsage.KnownTypeNames(namespaces[index]).Length
        index = index + 1
    }

    assert namespaces.Length == 10
    assert total == 112

    // Namespaces that look like table rows but are not.
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Collections").Length == 0
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Net").Length == 0
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Threading.Channels").Length == 0
    assert LinterNamespaceImportUsage.KnownTypeNames("").Length == 0
}

test "each namespace's type row holds exactly the count it was moved with" {
    assert LinterNamespaceImportUsage.KnownTypeNames("System").Length == 43
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Collections.Generic").Length == 22
    assert LinterNamespaceImportUsage.KnownTypeNames("System.IO").Length == 14
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Text.Json").Length == 7
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Linq").Length == 7
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Threading").Length == 6
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Net.Http").Length == 5
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Text.RegularExpressions").Length == 3
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Threading.Tasks").Length == 3
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Text").Length == 2
}

test "the member half is System.Linq alone, with all sixty-six methods" {
    assert LinterNamespaceImportUsage.KnownMemberNames("System.Linq").Length == 66

    namespaces := LniuTableNamespaces()
    index := 0
    rows := 0
    while index < namespaces.Length {
        if LinterNamespaceImportUsage.KnownMemberNames(namespaces[index]).Length > 0 {
            rows = rows + 1
        }

        index = index + 1
    }

    assert rows == 1
    assert LinterNamespaceImportUsage.KnownMemberNames("System").Length == 0
    assert LinterNamespaceImportUsage.KnownMemberNames("System.Collections.Generic").Length == 0
    assert LinterNamespaceImportUsage.KnownMemberNames("Acme.Widgets").Length == 0
}

test "no row repeats a name, so every count is a real membership count" {
    namespaces := LniuTableNamespaces()
    index := 0
    while index < namespaces.Length {
        types := LinterNamespaceImportUsage.KnownTypeNames(namespaces[index])
        assert LniuDistinctCount(types) == types.Length
        index = index + 1
    }

    members := LinterNamespaceImportUsage.KnownMemberNames("System.Linq")
    assert LniuDistinctCount(members) == members.Length
}

test "the rows that shared a source line in the deleted C# all survived the move" {
    // Seven entries were written two- or three-to-a-line in `BuildKnownNamespaceTypes`, which is
    // exactly where a hand transcription loses one.
    json := LinterNamespaceImportUsage.KnownTypeNames("System.Text.Json")
    assert LniuHas(json, "JsonNode")
    assert LniuHas(json, "JsonValueKind")

    system := LinterNamespaceImportUsage.KnownTypeNames("System")
    assert LniuHas(system, "StringComparison")
    assert LniuHas(system, "StringComparer")
    assert LniuHas(system, "ValueTuple")
    assert LniuHas(system, "Version")
    assert LniuHas(system, "Index")
}

test "Index is the one name carried by both halves, in different namespaces" {
    // `System.Index` the range type, and `Enumerable.Index` the net9 method. A file writing
    // `xs.Index()` uses `System.Linq`; a file writing `Index` as a type uses `System`.
    assert LniuHas(LinterNamespaceImportUsage.KnownTypeNames("System"), "Index")
    assert LniuHas(LinterNamespaceImportUsage.KnownMemberNames("System.Linq"), "Index")
    assert LniuHas(LinterNamespaceImportUsage.KnownTypeNames("System.Linq"), "Index") == false

    assert LinterNamespaceImportUsage.IsUsed("System", LniuOne("Index"), LniuNone())
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuNone(), LniuOne("Index"))
    assert LinterNamespaceImportUsage.IsUsed("System.Linq", LniuOne("Index"), LniuNone()) == false
}

test "Lookup and ILookup are System.Linq TYPES, which is what the census hit named" {
    linq := LinterNamespaceImportUsage.KnownTypeNames("System.Linq")
    assert LniuHas(linq, "Lookup")
    assert LniuHas(linq, "ILookup")
    assert LniuHas(LinterNamespaceImportUsage.KnownMemberNames("System.Linq"), "ToLookup")
    assert LniuHas(LinterNamespaceImportUsage.KnownMemberNames("System.Linq"), "Lookup") == false
}

test "the net8 and net9 LINQ additions are present, not just the classic operators" {
    members := LinterNamespaceImportUsage.KnownMemberNames("System.Linq")
    assert LniuHas(members, "SkipLast")
    assert LniuHas(members, "TakeLast")
    assert LniuHas(members, "TryGetNonEnumeratedCount")
    assert LniuHas(members, "CountBy")
    assert LniuHas(members, "AggregateBy")
    assert LniuHas(members, "Order")
    assert LniuHas(members, "OrderDescending")
    assert LniuHas(members, "Chunk")
    assert LniuHas(members, "DistinctBy")
    assert LniuHas(members, "MinBy")
    assert LniuHas(members, "MaxBy")
}

test "the collection interfaces travel with their concrete types" {
    generic := LinterNamespaceImportUsage.KnownTypeNames("System.Collections.Generic")
    assert LniuHas(generic, "IEnumerable")
    assert LniuHas(generic, "IReadOnlyDictionary")
    assert LniuHas(generic, "IAsyncEnumerable")
    assert LniuHas(generic, "IEqualityComparer")
    assert LniuHas(generic, "KeyValuePair")

    // `IEnumerable` is deliberately the GENERIC one: the non-generic sits in
    // `System.Collections`, which the table does not carry at all.
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Collections").Length == 0
    assert LinterNamespaceImportUsage.IsUsed("System.Collections", LniuOne("IEnumerable"), LniuNone())
}

test "the span and memory types are System rows, not System.Buffers ones" {
    system := LinterNamespaceImportUsage.KnownTypeNames("System")
    assert LniuHas(system, "Span")
    assert LniuHas(system, "Memory")
    assert LniuHas(system, "ReadOnlySpan")
    assert LniuHas(system, "ReadOnlyMemory")
    assert LinterNamespaceImportUsage.KnownTypeNames("System.Buffers").Length == 0
}

test "an unknown namespace answers with an empty row from both halves" {
    // This is the encoding the move chose: "absent from the table" and "has an empty row" are the
    // same state, which is sound only because no namespace in the table has an empty row.
    assert LinterNamespaceImportUsage.KnownTypeNames("Acme.Widgets").Length == 0
    assert LinterNamespaceImportUsage.KnownMemberNames("Acme.Widgets").Length == 0
    assert LinterNamespaceImportUsage.NoNames().Length == 0
}

test "ContainsAny is a pure membership scan and never reads order" {
    names := LniuSet(["Beta", "Alpha"])

    assert LinterNamespaceImportUsage.ContainsAny(names, ["Alpha", "Gamma"])
    assert LinterNamespaceImportUsage.ContainsAny(names, ["Gamma", "Alpha"])
    assert LinterNamespaceImportUsage.ContainsAny(names, ["Gamma", "Delta"]) == false
    assert LinterNamespaceImportUsage.ContainsAny(names, LinterNamespaceImportUsage.NoNames()) == false
    assert LinterNamespaceImportUsage.ContainsAny(LniuNone(), ["Alpha"]) == false
}
