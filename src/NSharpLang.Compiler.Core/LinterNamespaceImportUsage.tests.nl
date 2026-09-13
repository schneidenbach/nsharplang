namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Net.Http
import System.Reflection
import System.Text
import System.Text.Json
import System.Text.RegularExpressions
import System.Threading
import System.Threading.Tasks
import System.Linq
import NSharpLang.Compiler.Ast

// THE IMPORTS ABOVE ARE PART OF THE FIXTURE. `LnieDeclares` resolves against the assemblies this test
// host has LOADED, so a namespace no code in the estate mentions would answer "declares nothing" and
// the fixture would credit nothing for its names. Naming them here is what loads them.
func LnieLoadedNamespaceAnchors(): int {
    return typeof(StringBuilder).Name.Length + typeof(Regex).Name.Length + typeof(HttpClient).Name.Length + typeof(JsonSerializer).Name.Length + typeof(CancellationToken).Name.Length + typeof(Task).Name.Length + typeof(File).Name.Length
}


// CONTRACTS FOR WHAT MAKES A NAMESPACE IMPORT USED.
//
// These replace 633 lines that pinned a TABLE — the exact membership of ten hand-written rows of BCL
// spellings, their ordinal case sensitivity, and the fact that the member half was consulted for
// `System.Linq` and for nothing else. Every one of those assertions was about a list that could not
// be finished: `System` alone has thousands of public types, the row carried 112, and each of the
// missing ones was a FALSE POSITIVE on an ERROR whose `nlc fix` deletes the import. The census found
// one of them in the field — `import System` beside `OperatingSystem.IsWindows()`.
//
// WHAT IS PINNED NOW IS THE MEASUREMENT, AND IT HAS NO LIST IN IT. An import is used when the
// analyzer resolved at least one written name through it, which is recorded as the name resolves;
// the rule reads that and nothing else. So these contracts are about three things: that a credited
// namespace is used, that an uncredited one is not, and that a file with no facts — or with partial
// ones — is answered with silence rather than with a guess.
//
// THE ARITHMETIC THAT PRODUCES THE CREDIT IS PINNED TOO, at the bottom. It is the one piece of the
// rule that can be wrong in a way nothing else would notice, and it is what makes a FULLY QUALIFIED
// spelling credit nothing at all — the fact behind both of the census's `import System` findings.

func LniuFacts(supplied: string[]): ImportUsageFacts {
    facts := new ImportUsageFacts()
    index := 0
    while index < supplied.Length {
        facts.CreditNamespace(supplied[index])
        index = index + 1
    }

    facts.Analyzed = true
    return facts
}

func LniuUnanalyzed(supplied: string[]): ImportUsageFacts {
    facts := new ImportUsageFacts()
    index := 0
    while index < supplied.Length {
        facts.CreditNamespace(supplied[index])
        index = index + 1
    }

    return facts
}

func LniuOneNamespace(namespaceName: string): string[] {
    return [namespaceName]
}

func LniuNoNamespaces(): string[] {
    return new string[](0)
}

// ── whether the question can be asked at all ─────────────────────────────────────────────────

test "a unit with NO facts cannot be judged, and says so" {
    assert !LinterNamespaceImportUsage.HasFacts(null)
}

test "facts whose analysis did not COMPLETE cannot be judged either" {
    // A walk abandoned part-way credited part of the file. The import the missing half would have
    // credited is not an import that has been proven dead.
    assert !LinterNamespaceImportUsage.HasFacts(LniuUnanalyzed(LniuOneNamespace("System.Text")))
}

test "facts from a completed analysis can be judged, even when they credit nothing" {
    // An empty ledger from a COMPLETE analysis is a real answer — it is what a file that uses none of
    // its imports looks like — and it is the answer NL010 exists to report.
    assert LinterNamespaceImportUsage.HasFacts(LniuFacts(LniuNoNamespaces()))
}

// ── the answer ───────────────────────────────────────────────────────────────────────────────

test "a namespace the file bound through is USED" {
    assert LinterNamespaceImportUsage.IsImportUsed("System.Text", LniuFacts(LniuOneNamespace("System.Text")))
}

test "a namespace nothing bound through is NOT used" {
    assert !LinterNamespaceImportUsage.IsImportUsed("System.Text", LniuFacts(LniuOneNamespace("System")))
}

test "NOTHING ABOUT THE NAME MATTERS — a namespace no table ever carried answers the same way" {
    assert LinterNamespaceImportUsage.IsImportUsed("Contoso.Widgets.Internal", LniuFacts(LniuOneNamespace("Contoso.Widgets.Internal")))
    assert !LinterNamespaceImportUsage.IsImportUsed("Contoso.Widgets.Internal", LniuFacts(LniuOneNamespace("Contoso.Widgets")))
}

test "the match is ORDINAL and EXACT: neither a prefix, a child, nor a case variant credits it" {
    supplied := LniuFacts(LniuOneNamespace("System.Text"))
    assert !LinterNamespaceImportUsage.IsImportUsed("System", supplied)
    assert !LinterNamespaceImportUsage.IsImportUsed("System.Text.Json", supplied)
    assert !LinterNamespaceImportUsage.IsImportUsed("system.text", supplied)
}

test "an unjudgeable file answers USED for every import, which is the safe direction" {
    // The gate is asked by the caller, but the rule itself must never answer "unused" without
    // evidence: a false NL010 is a deleted import and a broken build.
    assert LinterNamespaceImportUsage.IsImportUsed("System.Text", null)
    assert LinterNamespaceImportUsage.IsImportUsed("System.Text", LniuUnanalyzed(LniuNoNamespaces()))
}

// ── the ledger itself ────────────────────────────────────────────────────────────────────────

test "an empty or null namespace credits nothing, so a nameless answer cannot mark an import used" {
    facts := new ImportUsageFacts()
    facts.CreditNamespace(null)
    facts.CreditNamespace("")
    assert facts.SuppliedNamespaces.Count == 0
}

test "a credited NAME also credits its namespace, because they are one fact" {
    facts := new ImportUsageFacts()
    facts.CreditName("StringBuilder", "System.Text")
    assert facts.SuppliedBy("System.Text")
    assert facts.SupplierFor("StringBuilder") == "System.Text"
}

test "a name with no namespace, and a namespace with no name, each credit what they can" {
    facts := new ImportUsageFacts()
    facts.CreditName("StringBuilder", null)
    assert facts.SupplierFor("StringBuilder") == null
    assert facts.SuppliedNamespaces.Count == 0

    facts.CreditName("", "System.Text")
    assert facts.SuppliedBy("System.Text")
    assert facts.SupplierFor("") == null
}

// ── the arithmetic behind the credit ─────────────────────────────────────────────────────────

test "a SIMPLE spelling is supplied by the prefix its resolved identity leaves over" {
    assert AnalyzerImportUsageCredit.SupplyingNamespace("StringBuilder", "System.Text.StringBuilder") == "System.Text"
}

test "a PARTIALLY QUALIFIED spelling credits the import that supplied its ROOT" {
    // `import System` beside `Collections.Generic.List<int>` is used, and no per-name table can say
    // so: the name the file wrote is not a name the namespace declares.
    assert AnalyzerImportUsageCredit.SupplyingNamespace("Collections.Generic.List", "System.Collections.Generic.List") == "System"
}

test "a FULLY QUALIFIED spelling credits NOTHING, which is why import System beside System.Type is dead" {
    // Both of the census's `import System` findings are this line. A fully qualified name spells its
    // own identity, so no prefix is left over for an import to have supplied.
    assert AnalyzerImportUsageCredit.SupplyingNamespace("System.Type", "System.Type") == null
}

test "a spelling the identity does not END with credits nothing" {
    // A channel that answered with a type of some other name did not resolve this spelling.
    assert AnalyzerImportUsageCredit.SupplyingNamespace("Widget", "System.Text.StringBuilder") == null
    assert AnalyzerImportUsageCredit.SupplyingNamespace("", "System.Text.StringBuilder") == null
}

test "the boundary is a DOT, so a longer name ending in the spelling is not a match" {
    assert AnalyzerImportUsageCredit.SupplyingNamespace("Builder", "System.Text.StringBuilder") == null
}

test "the two metadata spellings are normalised, because neither is how a developer writes the name" {
    assert AnalyzerImportUsageCredit.NormalizeMetadataName("System.Collections.Generic.List`1") == "System.Collections.Generic.List"
    assert AnalyzerImportUsageCredit.NormalizeMetadataName("Catalog.Outer+Inner") == "Catalog.Outer.Inner"
    assert AnalyzerImportUsageCredit.NormalizeMetadataName("System.Func`2") == "System.Func"
    assert AnalyzerImportUsageCredit.NormalizeMetadataName("System.Text.StringBuilder") == "System.Text.StringBuilder"
}

test "a generic spelling is credited through the normalisation, arity and all" {
    assert AnalyzerImportUsageCredit.SupplyingNamespace("List", "System.Collections.Generic.List`1") == "System.Collections.Generic"
}

test "a NESTED type's written spelling credits the namespace of its outer type" {
    assert AnalyzerImportUsageCredit.SupplyingNamespace("Outer.Inner", "Catalog.Outer+Inner") == "Catalog"
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// END-TO-END CONTRACTS OVER REAL SOURCE
//
// These lint whole source strings through the shipped `Linter`, which is what makes them contracts
// about the WALK — which positions keep an import alive — rather than about the rule's arithmetic.
//
// THE BINDING FACTS ARE A FIXTURE HERE, AND THEY HAVE TO BE. The linter answers both import rules
// from what the ANALYZER resolved, and an analyzer needs a metadata load context, a project and a
// reference set — none of which belongs in a per-file unit contract. So `LnieFacts` states the
// analysis's answer directly: a spelling the source WRITES is credited to the namespace that
// supplies it, and one it does not write is credited to nothing. The analyzer's own half — that it
// really does credit those namespaces, through every channel a name can resolve by — is proven where
// it can be: end-to-end against the shipped compiler in `tests/native/census-import-usage`.
//
// EVERY ABSENCE CLAIM CARRIES A REMOVAL CONTROL — the same source with the one usage that keeps the
// import alive taken out — which must then report the import at a stated line, column and length. The
// claims are whole CENSUSES rather than `Contains` probes, so a diagnostic that appears where none
// was expected fails here even when it is not an NL010.

// THE ANALYZER'S ANSWER, STOOD IN FOR BY REAL RESOLUTION.
//
// The linter answers both import rules from what the ANALYZER resolved, and an analyzer needs a
// metadata load context, a project and a reference set — none of which belongs in a per-file unit
// contract. So the fixture below answers the same question the analyzer answers, by RESOLVING each
// name the source writes against the runtime the estate is already running on: a spelling that names
// a real type under a candidate namespace is credited to that namespace, and one that does not is
// credited to nothing. No list of names anywhere — the same property the production rule has.
//
// The candidate NAMESPACES are a fixture, and they are the one place this differs from production.
// The analyzer probes the file's imports in order and then every loaded assembly's exported types;
// the estate probes the file's imports and a handful of BCL namespaces, which is what the sources
// below write. The analyzer's own half — that it really does credit through every channel a name can
// resolve by — is proven where it can be: end-to-end against the shipped compiler in
// `tests/native/census-import-usage`.

func LnieIsNameChar(value: char): bool {
    return char.IsLetterOrDigit(value) || value == '_'
}

// Every capitalised word the source writes. A type name is capitalised by convention in every source
// below, and a word that names nothing resolvable is credited to nothing anyway.
func LnieWrittenNames(source: string): List<string> {
    names := new List<string>()
    seen := new HashSet<string>(StringComparer.Ordinal)
    index := 0
    while index < source.Length {
        if char.IsUpper(source[index]) && (index == 0 || !LnieIsNameChar(source[index - 1])) {
            end := index
            while end < source.Length && LnieIsNameChar(source[end]) {
                end = end + 1
            }

            word := source.Substring(index, end - index)
            if seen.Add(word) {
                names.Add(word)
            }

            index = end
        } else {
            index = index + 1
        }
    }

    return names
}

// The namespaces the file imports, in written order, followed by the BCL namespaces the analyzer's
// bare-name scan would reach for a file that imports nothing.
func LnieCandidateNamespaces(source: string): List<string> {
    candidates := new List<string>()
    lines := source.Split('\n')
    index := 0
    while index < lines.Length {
        line := lines[index].Trim()
        index = index + 1
        if !line.StartsWith("import ", StringComparison.Ordinal) {
            continue
        }

        rest := line.Substring(7).Trim()
        aliasAt := rest.IndexOf(" as ", StringComparison.Ordinal)
        if aliasAt > 0 {
            rest = rest.Substring(0, aliasAt).Trim()
        }

        if rest.Length > 0 && !rest.StartsWith("\"", StringComparison.Ordinal) {
            candidates.Add(rest)
        }
    }

    candidates.Add("System")
    candidates.Add("System.Text")
    candidates.Add("System.Collections.Generic")
    candidates.Add("System.IO")
    candidates.Add("System.Threading")
    candidates.Add("System.Threading.Tasks")
    candidates.Add("System.Text.RegularExpressions")
    candidates.Add("System.Text.Json")
    candidates.Add("System.Net.Http")
    candidates.Add("System.Linq")
    return candidates
}

// Does any loaded assembly declare `<namespace>.<name>`, at any arity a source might write, under
// either of an attribute's two legal spellings?
func LnieDeclares(namespaceName: string, name: string): bool {
    if LnieDeclaresExactly(namespaceName, name) {
        return true
    }

    // `[Obsolete]` and `[ObsoleteAttribute]` name one type, and only the second is the metadata name.
    return !name.EndsWith("Attribute", StringComparison.Ordinal) && LnieDeclaresExactly(namespaceName, name + "Attribute")
}

func LnieDeclaresExactly(namespaceName: string, name: string): bool {
    if LnieTypeExists(namespaceName + "." + name) {
        return true
    }

    arity := 1
    while arity <= 4 {
        if LnieTypeExists(namespaceName + "." + name + "`" + arity.ToString()) {
            return true
        }

        arity = arity + 1
    }

    return false
}

// THE EXTENSION-METHOD HALF. `import System.Linq` used only as `.Select(...)` writes no type of that
// namespace at all, so the credit comes from the METHOD's declaring type — which is exactly what the
// analyzer credits. The fixture asks the same question of the same metadata: does a static class in
// this namespace declare a method of that name?
func LnieCreditExtensionMethods(facts: ImportUsageFacts, source: string, candidates: List<string>) {
    names := LnieCalledMemberNames(source)
    nameIndex := 0
    while nameIndex < names.Count {
        name := names[nameIndex]
        nameIndex = nameIndex + 1
        candidateIndex := 0
        while candidateIndex < candidates.Count {
            candidate := candidates[candidateIndex]
            candidateIndex = candidateIndex + 1
            if LnieDeclaresStaticMethod(candidate, name) {
                facts.CreditNamespace(candidate)
                break
            }
        }
    }
}

// `System.Linq.Enumerable` and `System.Linq.Queryable` are the two static classes a `.Select(...)`
// can come from; the fixture asks them by name rather than scanning every type in every assembly,
// which is the one shortcut it takes over the analyzer.
func LnieDeclaresStaticMethod(namespaceName: string, methodName: string): bool {
    if namespaceName != "System.Linq" {
        return false
    }

    // The METHODS are scanned rather than asked for by name: `Enumerable.Where` has several
    // overloads and `GetMethod` throws on an ambiguous match.
    methods := typeof(Enumerable).GetMethods()
    index := 0
    while index < methods.Length {
        if methods[index].Name == methodName {
            return true
        }

        index = index + 1
    }

    return false
}

// Every `.Name(` spelling the source calls.
func LnieCalledMemberNames(source: string): List<string> {
    names := new List<string>()
    seen := new HashSet<string>(StringComparer.Ordinal)
    index := source.IndexOf('.')
    while index >= 0 {
        start := index + 1
        end := start
        while end < source.Length && LnieIsNameChar(source[end]) {
            end = end + 1
        }

        if end > start && end < source.Length && source[end] == '(' {
            word := source.Substring(start, end - start)
            if seen.Add(word) {
                names.Add(word)
            }
        }

        index = source.IndexOf('.', index + 1)
    }

    return names
}

func LnieTypeExists(fullName: string): bool {
    if Type.GetType(fullName) != null {
        return true
    }

    assemblies := AppDomain.CurrentDomain.GetAssemblies()
    index := 0
    while index < assemblies.Length {
        if assemblies[index].GetType(fullName) != null {
            return true
        }

        index = index + 1
    }

    return false
}

func LnieFacts(source: string): ImportUsageFacts {
    facts := new ImportUsageFacts()
    candidates := LnieCandidateNamespaces(source)
    names := LnieWrittenNames(source)
    nameIndex := 0
    while nameIndex < names.Count {
        name := names[nameIndex]
        nameIndex = nameIndex + 1
        candidateIndex := 0
        while candidateIndex < candidates.Count {
            candidate := candidates[candidateIndex]
            candidateIndex = candidateIndex + 1
            if LnieDeclares(candidate, name) {
                facts.CreditName(name, candidate)
                break
            }
        }
    }

    LnieCreditExtensionMethods(facts, source, candidates)
    facts.Analyzed = true
    return facts
}

func LnieLint(source: string): List<Diagnostic> {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    unit := parsed.CompilationUnit
    if unit == null {
        throw new InvalidOperationException("the parser answered no compilation unit for: " + source)
    }

    unit.ImportUsage = LnieFacts(source)
    linter := new Linter(LinterConfig.Default())
    return linter.Lint(unit, "test.nl", source)
}

func LnieCensus(source: string): string {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    if parsed.Errors.Count != 0 {
        throw new InvalidOperationException("the source did not parse cleanly: " + source)
    }

    census := ""
    for diagnostic in LnieLint(source) {
        census = census + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + "+" + diagnostic.Length.ToString() + ";"
    }

    return census
}

func LnieMessages(source: string): string {
    census := ""
    for diagnostic in LnieLint(source) {
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

test "A NAMESPACE THE RULE HAS NEVER HEARD OF IS REPORTED LIKE ANY OTHER, WHICH IT WAS NOT" {
    // THE TABLE'S SECOND FAILURE, INVERTED. A namespace with no table row used to be reported USED no
    // matter what, so a dead import of any name outside the ten listed rows — a project's own
    // namespace, `System.Runtime.CompilerServices`, anything a developer writes — was invisible. The
    // rule now asks what the file BOUND, and an unknown namespace that bound nothing is dead.
    assert LnieCensus("\nimport MyCustom.Namespace\n\nfunc main() {\n    x := 5\n    y := x + 1\n}") == "NL001@6:5+1;NL010@2:8+18;"

    // SIBLING CONTROL: a second dead import beside it is reported too, at its own span, so the row
    // above is one finding about one import rather than a blanket answer.
    assert LnieCensus("\nimport MyCustom.Namespace\nimport System\n\nfunc main() {\n    x := 5\n    y := x + 1\n}") == "NL001@7:5+1;NL010@2:8+18;NL010@3:8+6;"
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

// ── an aliased import does BOTH things, so NL010 asks BOTH questions ──────────────────────────
//
// C#'s `using Txt = System.Text;` binds the alias and NOTHING ELSE: `new StringBuilder()` under it is
// CS0246. N#'s `import System.Text as Txt` binds `Txt` AND brings the namespace's names into scope
// unqualified — measured on the tip CLI, a file whose only import is the aliased one BUILDS
// `new StringBuilder()`, and the same file with the import removed is told by NL002 that nothing
// supplies `StringBuilder`. Asking the alias arm ALONE therefore reported an import the build needs as
// dead, at ERROR severity, with a `nlc fix` that deletes it.
//
// The census that found it: the converted `NSharpLang.LanguageServer`'s `CompletionHandler.nl`, whose
// only unqualified use of `import NSharpLang.Compiler.CodeIntelligence as CodeIntel` is a
// `new CompletionEngine()` in a field initializer, every other use being fully qualified.

test "AN ALIASED IMPORT IS ONE IMPORT WITH TWO SPELLINGS, SO IT HAS ONE ANSWER" {
    // C#'s `using Txt = System.Text;` binds the alias and NOTHING ELSE: `new StringBuilder()` under
    // it is CS0246. N#'s `import System.Text as Txt` binds `Txt` AND brings the namespace's names
    // into scope unqualified — measured on the tip CLI, a file whose only import is the aliased one
    // BUILDS `new StringBuilder()`. So both spellings credit the same NAMESPACE as the name resolves,
    // and this rule asks one question rather than two.
    //
    // An earlier arm asked the alias question ALONE and reported an import the build needs as dead,
    // at ERROR severity, with a `nlc fix` that deletes it. The census that found it: the converted
    // language server's `CompletionHandler.nl`, whose only unqualified use of
    // `import NSharpLang.Compiler.CodeIntelligence as CodeIntel` is a `new CompletionEngine()` in a
    // field initializer.
    assert LinterNamespaceImportUsage.IsImportUsed("System.Text", LniuFacts(LniuOneNamespace("System.Text")))
    assert !LinterNamespaceImportUsage.IsImportUsed("System.Text", LniuFacts(LniuOneNamespace("System.Linq")))
}

test "an ALIASED import used only through the namespace's own bare name is NOT reported" {
    assert LnieCensus("\nimport System.Text as Txt\n\nfunc main() {\n    sb := new StringBuilder()\n    print sb.ToString()\n}") == ""

    // SIBLING CONTROL: the alias-qualified spelling was already silent and stays silent, so the
    // answer above is the new arm and not a walk that stopped reporting.
    assert LnieCensus("\nimport System.Text as Txt\n\nfunc main() {\n    sb := new Txt.StringBuilder()\n    print sb.ToString()\n}") == ""

    // REMOVAL CONTROL: neither spelling. The import really is dead and NL010 still says so, at the
    // NAMESPACE's span rather than the alias's.
    assert LnieCensus("\nimport System.Text as Txt\n\nfunc main() {\n    print \"no builder here\"\n}") == "NL010@2:8+11;"
}
