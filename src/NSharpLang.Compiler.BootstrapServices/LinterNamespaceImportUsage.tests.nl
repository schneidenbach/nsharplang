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

// ══════════════════════════════════════════════════════════════════════════════════════════════
// END-TO-END NL010 CONTRACTS OVER REAL SOURCE (020 slice 15)
//
// These came out of `tests/ExampleLintTests.cs`, which is deleted. That file linted eighteen source
// strings and asked, of each, whether an `NL010` was present or absent.
//
// TWELVE OF THE EIGHTEEN ASSERTED ONLY ABSENCE, AND NINE OF THOSE TWELVE RAN AGAINST AN ENTIRELY
// EMPTY DIAGNOSTIC LIST. That is measured, not alleged: the census of every one of those nine
// sources is `""`. A linter with the NL010 rule deleted outright would have passed twelve of the
// eighteen. Every absence claim below therefore carries a REMOVAL CONTROL — the same source with
// the one usage that keeps the import alive taken out — which must then report the import at a
// stated line, column and length.
//
// AND THE CLAIMS THEMSELVES ARE WHOLE CENSUSES RATHER THAN `Contains`/`DoesNotContain` PROBES, so
// a diagnostic that appears where none was expected fails here even when it is not an NL010. Two
// of the deleted file's own readings of its sources turn out to have been wrong, and both are
// recorded where they occur.

func LnieCensus(source: string): string {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    unit := parsed.CompilationUnit
    if unit == null {
        throw new InvalidOperationException("the parser answered no compilation unit for: " + source)
    }

    if parsed.Errors.Count != 0 {
        throw new InvalidOperationException("the source did not parse cleanly: " + source)
    }

    linter := new Linter(LinterConfig.Default())
    diagnostics := linter.Lint(unit, "test.nl", source)
    census := ""
    for diagnostic in diagnostics {
        census = census + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + "+" + diagnostic.Length.ToString() + ";"
    }

    return census
}

func LnieMessages(source: string): string {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    unit := parsed.CompilationUnit
    if unit == null {
        throw new InvalidOperationException("the parser answered no compilation unit for: " + source)
    }

    linter := new Linter(LinterConfig.Default())
    diagnostics := linter.Lint(unit, "test.nl", source)
    census := ""
    for diagnostic in diagnostics {
        census = census + diagnostic.Code + "|" + diagnostic.Message + ";"
    }

    return census
}

// ── `print` is a language primitive, so `import System` is not what makes it work ──────────────

test "PRINT ALONE DOES NOT USE `import System`, AND THE IMPORT IS REPORTED WHERE IT IS WRITTEN" {
    // The deleted file asked only whether SOME NL010 exists. The span is stated here: column 8 is
    // where `System` starts on line 2, and 6 is its length — so the squiggle covers the namespace
    // and not the `import` keyword.
    assert LnieCensus("\nimport System\n\nfunc main() {\n    print \"Hello, world!\"\n}") == "NL010@2:8+6;"
    assert LnieMessages("\nimport System\n\nfunc main() {\n    print \"Hello, world!\"\n}") == "NL010|The import 'import System' is not used by any code in this file;"

    // An interpolated `print` over a local is still no use of System.
    assert LnieCensus("\nimport System\n\nfunc main() {\n    name := \"Alice\"\n    print $\"Hello, {name}!\"\n    print \"Done\"\n}") == "NL010@2:8+6;"
}

test "an import nothing names at all is reported, for System and for two other table rows" {
    assert LnieCensus("\nimport System\n\nfunc main() {\n    x := 5\n    y := x + 1\n}") == "NL001@6:5+1;NL010@2:8+6;"
    assert LnieCensus("\nimport System.Collections.Generic\n\nfunc main() {\n    x := 5\n    y := x + 1\n}") == "NL001@6:5+1;NL010@2:8+26;"
    assert LnieCensus("\nimport System.Linq\n\nfunc main() {\n    x := 5\n    y := x + 1\n}") == "NL001@6:5+1;NL010@2:8+11;"
}

// ── the twelve absence claims, each with the control that makes it non-vacuous ────────────────

test "a named generic type keeps System.Collections.Generic alive — and removing it reports" {
    assert LnieCensus("\nimport System.Collections.Generic\n\nfunc main() {\n    items := new List<int>()\n    count := items.Count\n}") == "NL001@6:5+5;"

    // REMOVAL CONTROL: the same shape with `List` gone. Same line count, same unused local, and now
    // the import is reported.
    assert LnieCensus("\nimport System.Collections.Generic\n\nfunc main() {\n    items := 5\n    count := items\n}") == "NL001@6:5+5;NL010@2:8+26;"
}

test "a RETURN TYPE counts as a use, which is the only thing keeping the async example green" {
    assert LnieCensus("\nimport System.Collections.Generic\nimport System.Threading.Tasks\n\nasync func* GetNumbers(): IAsyncEnumerable<int> {\n    await Task.Delay(100)\n    yield 1\n}\n\nfunc main() {\n}") == ""

    // REMOVAL CONTROL: the same file with the return type changed to `Task<int>`. System.Threading
    // .Tasks is still used by `Task.Delay`, so exactly ONE of the two imports goes unused — which
    // also shows the two are tracked separately rather than as a set.
    assert LnieCensus("\nimport System.Collections.Generic\nimport System.Threading.Tasks\n\nasync func GetNumber(): Task<int> {\n    await Task.Delay(100)\n    return 1\n}\n\nfunc main() {\n}") == "NL010@2:8+26;"
}

test "DateTime, Exception, ArgumentException and Environment each keep System alive on their own" {
    assert LnieCensus("\nimport System\n\nfunc main() {\n    now := DateTime.Now\n    print $\"Time: {now}\"\n}") == ""
    assert LnieCensus("\nimport System\n\nfunc main() {\n    throw new Exception(\"error\")\n}") == ""
    assert LnieCensus("\nimport System\n\nfunc Validate(x: int) {\n    if x < 0 {\n        throw new ArgumentException(\"must be non-negative\")\n    }\n}\n\nfunc main() {\n    Validate(1)\n}") == ""
    assert LnieCensus("\nimport System\n\nfunc main() {\n    args := Environment.GetCommandLineArgs()\n    x := args\n}") == "NL001@6:5+1;"

    // FOUR REMOVAL CONTROLS, one per name: the same four files with the System name replaced by a
    // literal. Each reports the import, so each of the four claims above is carried by that name.
    assert LnieCensus("\nimport System\n\nfunc main() {\n    now := 5\n    print $\"Time: {now}\"\n}") == "NL010@2:8+6;"
    assert LnieCensus("\nimport System\n\nfunc main() {\n    print \"error\"\n}") == "NL010@2:8+6;"
    assert LnieCensus("\nimport System\n\nfunc Validate(x: int) {\n    if x < 0 {\n        print \"must be non-negative\"\n    }\n}\n\nfunc main() {\n    Validate(1)\n}") == "NL010@2:8+6;"
    assert LnieCensus("\nimport System\n\nfunc main() {\n    args := 5\n    x := args\n}") == "NL001@6:5+1;NL010@2:8+6;"
}

test "THREE IMPORTS, AND THE CENSUS SAYS WHICH TWO ARE DEAD RATHER THAN THAT AT LEAST ONE IS" {
    // The deleted file asserted `nl010s.Count >= 1` and that ONE of them mentions System.Text. A
    // lower bound cannot see that `System` is dead too, and cannot see that
    // System.Collections.Generic is alive. All three are stated.
    source := "\nimport System\nimport System.Collections.Generic\nimport System.Text\n\nfunc main() {\n    items := new List<int>()\n    count := items.Count\n}"
    assert LnieCensus(source) == "NL001@8:5+5;NL010@2:8+6;NL010@4:8+11;"
    assert LnieMessages(source) == "NL001|Variable 'count' is declared but never read;NL010|The import 'import System' is not used by any code in this file;NL010|The import 'import System.Text' is not used by any code in this file;"

    // SIBLING CONTROL: with the unused local read, the two dead imports are still the same two — so
    // the answer above is about the imports and not about the unused variable next to them.
    assert LnieCensus("\nimport System\nimport System.Collections.Generic\nimport System.Text\n\nfunc main() {\n    items := new List<int>()\n    count := items.Count\n    print count\n}") == "NL010@2:8+6;NL010@4:8+11;"
}

test "an unknown namespace is conservatively USED, and a known one beside it is still reported" {
    assert LnieCensus("\nimport MyCustom.Namespace\n\nfunc main() {\n    x := 5\n    y := x + 1\n}") == "NL001@6:5+1;"

    // SIBLING CONTROL: the same file with `import System` added. The known row is reported at line
    // 3 and the unknown one at line 2 is not — so the silence above is the unknown-namespace rule
    // and not a walk that never looked.
    assert LnieCensus("\nimport MyCustom.Namespace\nimport System\n\nfunc main() {\n    x := 5\n    y := x + 1\n}") == "NL001@7:5+1;NL010@3:8+6;"
}

// ── the real-world shapes the deleted file lifted out of the examples ─────────────────────────

test "A MATCH ARM IS WALKED FOR IMPORT USAGE, WHICH THE UNION EXAMPLE COULD NOT SHOW" {
    // The deleted file's union/match source carried NO IMPORT AT ALL, so its
    // `DoesNotContain(NL010)` was true of a file with nothing to report. The contract it was reaching
    // for is that a name used inside a match arm keeps its import alive; that is a pair.
    assert LnieCensus("\nunion IssueError {\n    NotFound { id: int }\n    InvalidTransition { from: string, to: string }\n    ValidationFailed { field: string, reason: string }\n}\n\nfunc FormatError(err: IssueError): string {\n    return match err {\n        IssueError.NotFound { id } => $\"Issue #{id} not found\",\n        IssueError.InvalidTransition { from, to } => $\"Cannot move from {from} to {to}\",\n        IssueError.ValidationFailed { field, reason } => $\"{field}: {reason}\"\n    }\n}\n\nfunc main() {\n    msg := FormatError(new IssueError.NotFound(1))\n    print msg\n}") == ""

    // USED inside the arm: silent.
    assert LnieCensus("\nimport System.Text\n\nunion IssueError {\n    NotFound { id: int }\n}\n\nfunc FormatError(err: IssueError): string {\n    return match err {\n        IssueError.NotFound { id } => new StringBuilder().Append(id).ToString()\n    }\n}\n\nfunc main() {\n    print FormatError(new IssueError.NotFound(1))\n}") == ""

    // REMOVAL CONTROL: the same union, the same match, the arm's body replaced by a literal.
    assert LnieCensus("\nimport System.Text\n\nunion IssueError {\n    NotFound { id: int }\n}\n\nfunc FormatError(err: IssueError): string {\n    return match err {\n        IssueError.NotFound { id } => \"issue\"\n    }\n}\n\nfunc main() {\n    print FormatError(new IssueError.NotFound(1))\n}") == "NL010@2:8+11;"
}

test "a RECORD METHOD BODY is walked for import usage" {
    assert LnieCensus("\nrecord TaskItem {\n    Id: int\n    Title: string\n\n    func GetInfo(): string {\n        return $\"#{Id}: {Title}\"\n    }\n}\n\nfunc main() {\n    task := new TaskItem { Id: 1, Title: \"Test\" }\n    print task.GetInfo()\n}") == ""

    assert LnieCensus("\nimport System.Text\n\nrecord TaskItem {\n    Id: int\n\n    func GetInfo(): string {\n        return new StringBuilder().Append(Id).ToString()\n    }\n}\n\nfunc main() {\n    task := new TaskItem { Id: 1 }\n    print task.GetInfo()\n}") == ""

    // REMOVAL CONTROL: the same record with the method body's StringBuilder replaced.
    assert LnieCensus("\nimport System.Text\n\nrecord TaskItem {\n    Id: int\n\n    func GetInfo(): string {\n        return \"info\"\n    }\n}\n\nfunc main() {\n    task := new TaskItem { Id: 1 }\n    print task.GetInfo()\n}") == "NL010@2:8+11;"
}

test "a CLASS FIELD TYPE and a CONSTRUCTOR BODY are walked, which the duck-interface example needs" {
    assert LnieCensus("\nimport System.Collections.Generic\n\nduck interface INotifier {\n    func Notify(message: string)\n}\n\nclass ConsoleNotifier {\n    func Notify(message: string) {\n        print message\n    }\n}\n\nclass Hub {\n    notifiers: List<INotifier>\n\n    constructor() {\n        notifiers = new List<INotifier>()\n    }\n\n    func Register(n: ConsoleNotifier) {\n        notifiers.Add(n)\n    }\n}\n\nfunc main() {\n    hub := new Hub()\n    hub.Register(new ConsoleNotifier())\n}") == ""

    // REMOVAL CONTROL: the same three declarations with every `List` gone. The import is reported —
    // and so is the parameter the method now ignores, which is the sibling evidence that the class
    // body really was walked.
    assert LnieCensus("\nimport System.Collections.Generic\n\nduck interface INotifier {\n    func Notify(message: string)\n}\n\nclass ConsoleNotifier {\n    func Notify(message: string) {\n        print message\n    }\n}\n\nclass Hub {\n    count: int\n\n    constructor() {\n        count = 0\n    }\n\n    func Register(n: ConsoleNotifier) {\n        count = count + 1\n    }\n}\n\nfunc main() {\n    hub := new Hub()\n    hub.Register(new ConsoleNotifier())\n}") == "NL012@21:19+1;NL010@2:8+26;"
}

test "a THROW OPERAND and a MEMBER READ off a caught value are walked" {
    assert LnieCensus("\nimport System\n\nfunc Divide(a: int, b: int): int {\n    if b == 0 {\n        throw new Exception(\"Cannot divide by zero\")\n    }\n    return a / b\n}\n\nfunc main() {\n    result, err := Divide(10, 2)\n    if err == null {\n        print $\"Result: {result}\"\n    } else {\n        print $\"Error: {err.Message}\"\n    }\n}") == ""

    // REMOVAL CONTROL: the same error-tuple shape with the Exception construction replaced.
    assert LnieCensus("\nimport System\n\nfunc Divide(a: int, b: int): int {\n    if b == 0 {\n        return 0\n    }\n    return a / b\n}\n\nfunc main() {\n    result, err := Divide(10, 2)\n    if err == null {\n        print $\"Result: {result}\"\n    } else {\n        print \"failed\"\n    }\n}") == "NL010@2:8+6;"
}

test "a STATIC METHOD BODY is walked, which is the task-cli formatter shape" {
    assert LnieCensus("\nimport System.Text\n\nclass Formatter {\n    static func FormatHeader(): string {\n        sb := new StringBuilder()\n        sb.Append(\"ID\".PadRight(5))\n        sb.Append(\"Title\".PadRight(30))\n        return sb.ToString()\n    }\n}\n\nfunc main() {\n    header := Formatter.FormatHeader()\n    print header\n}") == ""

    // REMOVAL CONTROL: the same class with the StringBuilder gone from the static body.
    assert LnieCensus("\nimport System.Text\n\nclass Formatter {\n    static func FormatHeader(): string {\n        return \"ID\".PadRight(5)\n    }\n}\n\nfunc main() {\n    header := Formatter.FormatHeader()\n    print header\n}") == "NL010@2:8+11;"
}
