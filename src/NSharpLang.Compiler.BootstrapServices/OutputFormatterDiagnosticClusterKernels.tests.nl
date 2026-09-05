namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler


// `OutputFormatterDiagnosticClusterKernels` AND `OutputFormatterDiagnosticClusterBuilder`: THE
// AI-CONSUMABLE TRIAGE LAYER `nlc check` PUTS IN FRONT OF A WALL OF DIAGNOSTICS.
//
// NEITHER TYPE HAD ANY ESTATE COVERAGE AT ALL BEFORE THIS FILE. `OutputFormatterJsonKernels.tests.nl`
// reached the cluster envelope twice — once for its root keys and once for file-name ordering — and
// stopped at the envelope; nothing anywhere asked what a cluster CONTAINS. The only assertion layer
// for the contents was `tests/DiagnosticClusteringTests.cs`, 137 lines and four `[Fact]`s, and three
// of the four asserted through the C# `OutputFormatter` forwarder rather than the kernels that
// decide.
//
// THE CLASSIFIERS ARE THE PRODUCT AND THEY ARE CROSSED HERE FOR THE FIRST TIME.
// `ClassifyDiagnosticCategory` is a two-tier decision — an exact-code table first, a
// message-substring table second — and the deleted file exercised exactly two of its eight
// categories through the code tier and none at all through the message tier, which is the tier that
// runs for every diagnostic the code table does not name. `InferDiagnosticSourceConstruct` has nine
// arms and the deleted file reached two.
//
// FOUR THINGS THE DELETED FILE LEFT IMPLICIT ARE STATED HERE:
//   (a) THE CATEGORY TABLE IS A PARTITION AND ITS TWO TIERS AGREE. Every category is reachable
//       through both tiers where both tiers can produce it, and the eight category names, eight
//       recipes and three risk levels are stated together so a renamed category cannot drift from
//       its recipe.
//   (b) THE DECLARATION SNIFFER SKIPS MODIFIERS AND ONLY FOR FUNCTIONS. `override async func` is a
//       function declaration; `override async class` is not a class declaration, because the
//       modifier strip is applied to the `func` probe alone. The deleted file's second `[Fact]`
//       asserted the first half and could not see the second.
//   (c) THE NEXT COMMAND QUOTES ITS FILE ARGUMENT WHEN IT HAS TO. A path with a space becomes a
//       quoted, backslash-escaped argument, and an empty path becomes `""` — so the command the
//       cluster hands an agent is always executable. Nothing anywhere stated this.
//   (d) THE MESSAGE PATTERN ERASES BOTH QUOTED TEXT AND DIGITS. Two diagnostics that differ only in
//       the identifier they name, or only in a number, share a pattern and therefore a cluster —
//       which is the mechanism the deleted file's first `[Fact]` depended on without naming.
//
// The text report's own shape lives in `OutputFormatterTextBuilders.tests.nl` beside the other
// eleven `--text` builders; the two cases here that read text state the ORDER of the summary
// against the individual diagnostics, which is a claim about the report as a whole.

// ── Fixtures ────────────────────────────────────────────────────────────────────────────────────
func OfdckMissingSemicolon(fileName: string, line: int, snippet: string): DiagnosticResult {
    return new DiagnosticResult("NL102", "error", "Expected token ';'", fileName, line, 5, 1, snippet, null, "Add ';'", null, null, null, null)
}

func OfdckUndefinedBuilder(fileName: string, line: int): DiagnosticResult {
    return new DiagnosticResult("NL301", "error", "Undefined variable 'StringBuilder'", fileName, line, 10, 13, "sb := new StringBuilder()", null, "Import System.Text or qualify StringBuilder", null, null, null, null)
}

// The deleted file's three-diagnostic fixture: two terminator errors that cluster, and one
// identifier error that does not.
func OfdckThreeDiagnostics(): List<DiagnosticResult> {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OfdckMissingSemicolon("src/A.nl", 40, "let answer = 42"))
    diagnostics.Add(OfdckMissingSemicolon("src/B.nl", 7, "let total = count + 1"))
    diagnostics.Add(OfdckUndefinedBuilder("src/C.nl", 12))
    return diagnostics
}

func OfdckClusters(diagnostics: List<DiagnosticResult>): List<DiagnosticCluster> {
    return OutputFormatterDiagnosticClusterBuilder.BuildDiagnosticClusters(diagnostics)
}

// The comma-joined file list of one cluster.
func OfdckFiles(cluster: DiagnosticCluster): string {
    joined := ""
    index := 0
    while index < cluster.Files.Length {
        if index > 0 {
            joined = joined + ","
        }

        joined = joined + cluster.Files[index]
        index = index + 1
    }

    return joined
}

// ── The migrated cases ──────────────────────────────────────────────────────────────────────────

test "a cluster carries its category, construct, recipe, risk, root location, files and next command" {
    clusters := OfdckClusters(OfdckThreeDiagnostics())

    assert clusters.Count == 2

    first := clusters[0]
    assert first.Category == "syntax-missing-terminator"
    assert first.Count == 2
    assert first.SourceConstruct == "variable-declaration"
    assert first.Recipe == "syntax:statement-boundary"
    assert first.Risk == "high"
    assert OfdckFiles(first) == "src/A.nl,src/B.nl"
    assert first.Files[0] == "src/A.nl"
    assert first.Files[1] == "src/B.nl"
    assert first.RelatedDiagnostics[0].Code == "NL102"

    // The ROOT is the earliest location in the cluster, not the first one supplied: `src/B.nl:7`
    // sorts ahead of `src/A.nl:40` — and the next command points at exactly that root.
    assert first.RootLocation.File == "src/B.nl"
    assert first.RootLocation.Line == 7
    assert first.RootLocation.Column == 5
    assert first.NextCommand == "nlc query inspect --file src/B.nl --pos 7:5"

    assert first.SuggestedNextActions.Length > 0
    assert first.Examples.Length == 2

    second := clusters[1]
    assert second.Category == "identifier-resolution"
    assert second.Count == 1
    assert second.RelatedDiagnostics[0].Code == "NL301"
}

test "a canonical async function declaration is a function declaration through its modifiers" {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OfdckMissingSemicolon("src/A.nl", 12, "async func Load(): Task<int> {"))
    diagnostics.Add(OfdckMissingSemicolon("src/B.nl", 20, "override async func Save(): Task {"))

    clusters := OfdckClusters(diagnostics)
    assert clusters.Count == 1
    assert clusters[0].SourceConstruct == "function-declaration"
}

test "the text report leads with the cluster summary and then prints the individual diagnostics" {
    text := OutputFormatterTextBuilders.DiagnosticsToText(OfdckThreeDiagnostics())

    assert text.Contains("Diagnostic clusters (2 groups, 3 diagnostics)")
    assert text.Contains("  [2x] syntax-missing-terminator / variable-declaration / risk: high")
    assert text.Contains("       recipe: syntax:statement-boundary")
    assert text.Contains("       root: src/B.nl:7:5")
    assert text.Contains("       next command: nlc query inspect --file src/B.nl --pos 7:5")

    summaryAt := text.IndexOf("Diagnostic clusters", StringComparison.Ordinal)
    firstDiagnosticAt := text.IndexOf("── [NL102] ERROR", StringComparison.Ordinal)
    assert summaryAt >= 0
    assert firstDiagnosticAt >= 0
    assert summaryAt < firstDiagnosticAt

    // Exactly two suggested actions are printed per cluster, and they are that category's own.
    assert text.Contains("       next: Fix the earliest statement-boundary parse error first; later syntax diagnostics are often cascades.")
    assert text.Contains("       next: Resolve the first missing identifier by adding the import/qualification or correcting the declaration name.")
}

test "a single cluster and a single diagnostic are described in the singular" {
    single := new List<DiagnosticResult>()
    single.Add(OfdckUndefinedBuilder("src/C.nl", 12))

    text := OutputFormatterTextBuilders.DiagnosticsToText(single)
    assert text.Contains("Diagnostic clusters (1 group, 1 diagnostic)")
    assert !text.Contains("1 groups")
    assert !text.Contains("1 diagnostics")
}

test "diagnostic deduplication keeps the first duplicate and orders the survivors by location" {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OfdckMissingSemicolon("src/B.nl", 10, "first duplicate wins"))
    diagnostics.Add(DiagnosticResultKernels.WithColumn(OfdckUndefinedBuilder("src/A.nl", 2), 3))
    diagnostics.Add(OfdckMissingSemicolon("src/B.nl", 10, "duplicate should be ignored"))
    diagnostics.Add(DiagnosticResultKernels.WithCodeColumnMessage(OfdckMissingSemicolon("src/A.nl", 2, "same file earlier column"), "NL201", 1, "Type is inferred"))
    diagnostics.Add(DiagnosticResultKernels.WithColumn(OfdckUndefinedBuilder("src/A.nl", 2), 3))

    deduplicated := CodeIntelligenceResultKernels.DeduplicateDiagnosticResults(diagnostics)

    assert deduplicated.Count == 3
    assert deduplicated[0].Code == "NL201"
    assert deduplicated[1].Code == "NL301"
    assert deduplicated[2].Code == "NL102"

    // The FIRST of a duplicate pair survives with its own snippet; the later one is discarded.
    assert deduplicated[2].SourceSnippet == "first duplicate wins"

    // The ordering is by file, then line, then column: `src/A.nl:2:1` before `src/A.nl:2:3`
    // before `src/B.nl:10:5`.
    assert deduplicated[0].File == "src/A.nl"
    assert deduplicated[0].Column == 1
    assert deduplicated[1].File == "src/A.nl"
    assert deduplicated[1].Column == 3
    assert deduplicated[2].File == "src/B.nl"
}

// ── The category classifier, both tiers ─────────────────────────────────────────────────────────

test "the code tier of the category classifier names seven of the eight categories" {
    // NL102 splits on the message: a terminator error and a delimiter error share the code.
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL102", "Expected token ';'") == 0
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL102", "missing semicolon") == 0
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL102", "Expected token '}'") == 1

    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL703", "anything") == 2
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL301", "anything") == 3
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL412", "anything") == 3
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL201", "anything") == 4
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL302", "anything") == 4
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL202", "anything") == 5
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL303", "anything") == 6

    // The code tier IGNORES the message for every code except NL102 — a NL202 whose text talks
    // about an undefined variable is still a type mismatch.
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL202", "undefined variable 'x'") == 5
}

test "the message tier of the category classifier runs for every code the table does not name" {
    // This whole tier was unreached. `NL999` is not in the code table, so every row below is decided
    // by its text alone.
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "Expected token ';'") == 0
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "Expected token ')'") == 1
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "missing semicolon here") == 0
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "missing closing brace") == 1
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "circular import detected") == 2
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "Undefined variable 'x'") == 3
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "undefined symbol 'x'") == 3
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "Type not found: Widget") == 4
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "undefined type Widget") == 4
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "cannot resolve type Widget") == 4
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "Type mismatch") == 5
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "no such member") == 6
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "no such method") == 6

    // Nothing matched: the manual-triage bucket, which is the eighth category.
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "something else entirely") == 7
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("", "") == 7

    // The message tier is case-insensitive; the code tier is not.
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("NL999", "TYPE MISMATCH") == 5
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("nl202", "Type mismatch") == 5
    assert OutputFormatterDiagnosticClusterKernels.ClassifyDiagnosticCategory("nl303", "irrelevant") == 7
}

test "each of the eight categories carries its own name, recipe and risk" {
    assert OfdckTraits(0) == "syntax-missing-terminator|syntax:statement-boundary|high"
    assert OfdckTraits(1) == "syntax-missing-delimiter|syntax:delimiter-balancing|high"
    assert OfdckTraits(2) == "import-cycle|architecture:extract-shared-module-or-invert-dependency|high"
    assert OfdckTraits(3) == "identifier-resolution|symbols:missing-import-or-qualification|medium"
    assert OfdckTraits(4) == "type-resolution|types:resolve-type-or-import|medium"
    assert OfdckTraits(5) == "type-mismatch|refactor:signature-or-expression-shape|medium"
    assert OfdckTraits(6) == "member-resolution|members:api-rename-or-extension-import|medium"
    assert OfdckTraits(7) == "diagnostic-message-shape|manual-triage:inspect-root-diagnostic|low"

    // An unknown category id falls into the manual-triage bucket rather than throwing.
    assert OfdckTraits(99) == "diagnostic-message-shape|manual-triage:inspect-root-diagnostic|low"

    // The import-cycle category OVERRIDES the inferred source construct with "import" — the only
    // category that does, and a fact no assertion anywhere held.
    importTraits := DiagnosticClusterModelsTraits(2, 0)
    assert importTraits.SourceConstruct == "import"
    assert DiagnosticClusterModelsTraits(0, 0).SourceConstruct == "variable-declaration"
}

func OfdckTraits(category: int): string {
    traits := DiagnosticClusterModelsTraits(category, 8)
    return traits.Category + "|" + traits.Recipe + "|" + traits.Risk
}

func DiagnosticClusterModelsTraits(category: int, sourceConstruct: int): DiagnosticClusterTraits {
    return OutputFormatterDiagnosticClusterBuilder.CreateDiagnosticClusterTraits(category, sourceConstruct, "pattern")
}

// ── The source-construct sniffer ────────────────────────────────────────────────────────────────

test "the source construct sniffer names all nine constructs from a snippet" {
    assert OfdckConstruct("let answer = 42") == "variable-declaration"
    assert OfdckConstruct("total := count + 1") == "variable-declaration"
    assert OfdckConstruct("func Load(): int {") == "function-declaration"
    assert OfdckConstruct("func* Stream(): int {") == "function-declaration"
    assert OfdckConstruct("class Person {") == "class-declaration"
    assert OfdckConstruct("interface Shape {") == "interface-declaration"
    assert OfdckConstruct("import System") == "import"
    assert OfdckConstruct("using System") == "import"
    assert OfdckConstruct("return value") == "return-statement"
    assert OfdckConstruct("if ready {") == "control-flow"
    assert OfdckConstruct("for item in items {") == "control-flow"
    assert OfdckConstruct("while ready {") == "control-flow"
    assert OfdckConstruct("match value {") == "control-flow"
    assert OfdckConstruct("Console.WriteLine(x)") == "call-or-construction"
    assert OfdckConstruct("x + y") == "unknown-construct"
    assert OfdckConstruct("") == "unknown-construct"
}

test "leading whitespace and declaration modifiers are skipped, and only for the function probe" {
    assert OfdckConstruct("        func Load(): int {") == "function-declaration"
    assert OfdckConstruct("async func Load(): Task<int> {") == "function-declaration"
    assert OfdckConstruct("override async func Save(): Task {") == "function-declaration"
    assert OfdckConstruct("   public   static   func Go(): int {") == "function-declaration"

    // THE ASYMMETRY. The modifier strip feeds the `func` probe alone, so a modifier in front of any
    // OTHER keyword defeats that keyword's own probe — a modified class declaration is not
    // recognised as one. This is the sniffer's honest boundary and nothing stated it.
    assert OfdckConstruct("public class Person {") == "unknown-construct"
    assert OfdckConstruct("        class Person {") == "class-declaration"

    // `:=` beats everything, wherever it appears: an assignment inside a call snippet is a
    // variable declaration, because that probe runs before the declaration probes.
    assert OfdckConstruct("result := Compute(x)") == "variable-declaration"
}

func OfdckConstruct(snippet: string): string {
    return OutputFormatterDiagnosticClusterBuilder.DiagnosticSourceConstructName(
        OutputFormatterDiagnosticClusterKernels.InferDiagnosticSourceConstruct(snippet)
    )
}

// ── The message pattern, the cluster id and the next command ────────────────────────────────────

test "the message pattern erases quoted text and digits so cascades collapse into one cluster" {
    assert OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("Undefined variable 'customer'") == OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("Undefined variable 'order'")

    assert OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("Undefined variable 'x'") == "Undefined variable {value}"
    assert OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("Expected 3 arguments") == "Expected # arguments"
    assert OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("Expected 12 arguments") == "Expected ## arguments"

    // Blank or missing text is a named pattern rather than an empty one.
    assert OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("") == "unknown-message"
    assert OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("   ") == "unknown-message"

    // Two different messages do NOT collapse.
    assert OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("Undefined variable 'x'") != OutputFormatterDiagnosticClusterKernels.NormalizeMessagePattern("Undefined type 'x'")
}

test "the cluster id is a stable lower-case hex digest of the six fields that define a cluster" {
    left := OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId("NL102", "error", "syntax-missing-terminator", "variable-declaration", "syntax:statement-boundary", "Expected token {value}")
    right := OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId("NL102", "error", "syntax-missing-terminator", "variable-declaration", "syntax:statement-boundary", "Expected token {value}")

    assert left == right
    assert left.StartsWith("diag-", StringComparison.Ordinal)
    assert left.Length > 5

    // Every one of the six fields participates: changing any one changes the id.
    assert left != OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId("NL103", "error", "syntax-missing-terminator", "variable-declaration", "syntax:statement-boundary", "Expected token {value}")
    assert left != OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId("NL102", "warning", "syntax-missing-terminator", "variable-declaration", "syntax:statement-boundary", "Expected token {value}")
    assert left != OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId("NL102", "error", "syntax-missing-delimiter", "variable-declaration", "syntax:statement-boundary", "Expected token {value}")
    assert left != OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId("NL102", "error", "syntax-missing-terminator", "function-declaration", "syntax:statement-boundary", "Expected token {value}")
    assert left != OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId("NL102", "error", "syntax-missing-terminator", "variable-declaration", "syntax:delimiter-balancing", "Expected token {value}")
    assert left != OutputFormatterDiagnosticClusterKernels.CreateDiagnosticClusterId("NL102", "error", "syntax-missing-terminator", "variable-declaration", "syntax:statement-boundary", "Expected token {other}")
}

test "the hex digits the cluster id is built from are lower case and have no leading zero" {
    assert OutputFormatterDiagnosticClusterKernels.PositiveIntToLowerHex(0) == "0"
    assert OutputFormatterDiagnosticClusterKernels.PositiveIntToLowerHex(15) == "f"
    assert OutputFormatterDiagnosticClusterKernels.PositiveIntToLowerHex(16) == "10"
    assert OutputFormatterDiagnosticClusterKernels.PositiveIntToLowerHex(255) == "ff"
    assert OutputFormatterDiagnosticClusterKernels.PositiveIntToLowerHex(4096) == "1000"
}

test "the positive modulo is never negative, which is what makes a hash usable as an index" {
    assert OutputFormatterDiagnosticClusterKernels.PositiveModulo(7, 4) == 3
    assert OutputFormatterDiagnosticClusterKernels.PositiveModulo(0, 4) == 0
    assert OutputFormatterDiagnosticClusterKernels.PositiveModulo(-1, 4) == 3
    assert OutputFormatterDiagnosticClusterKernels.PositiveModulo(-4, 4) == 0
    assert OutputFormatterDiagnosticClusterKernels.PositiveModulo(-7, 4) == 1
}

test "the next command quotes a file argument that needs it and never emits a bare empty path" {
    plain := OutputFormatterDiagnosticClusterKernels.BuildDiagnosticClusterNextCommand(OfdckMissingSemicolon("src/A.nl", 40, "let answer = 42"))
    assert plain == "nlc query inspect --file src/A.nl --pos 40:5"

    // A path with a space is quoted, so the printed command stays executable.
    spaced := OutputFormatterDiagnosticClusterKernels.BuildDiagnosticClusterNextCommand(OfdckMissingSemicolon("my project/A.nl", 3, "let x = 1"))
    assert spaced == "nlc query inspect --file \"my project/A.nl\" --pos 3:5"

    // An empty path becomes an explicit empty argument rather than nothing at all.
    empty := OutputFormatterDiagnosticClusterKernels.BuildDiagnosticClusterNextCommand(OfdckMissingSemicolon("", 1, "let x = 1"))
    assert empty == "nlc query inspect --file \"\" --pos 1:5"
}

test "the command argument escaper admits exactly the unquoted character class" {
    assert OutputFormatterDiagnosticClusterKernels.EscapeCommandArgument("src/A.nl") == "src/A.nl"
    assert OutputFormatterDiagnosticClusterKernels.EscapeCommandArgument("a_b-c.9") == "a_b-c.9"

    // A backslash is NOT in the unquoted class, so a Windows-shaped path is quoted and its
    // separators are doubled.
    assert OutputFormatterDiagnosticClusterKernels.EscapeCommandArgument("src\\A.nl") == "\"src\\\\A.nl\""

    // An embedded quote is escaped inside the quotes.
    assert OutputFormatterDiagnosticClusterKernels.EscapeCommandArgument("a\"b") == "\"a\\\"b\""

    assert OutputFormatterDiagnosticClusterKernels.EscapeCommandArgument("") == "\"\""
    assert OutputFormatterDiagnosticClusterKernels.EscapeCommandArgument("   ") == "\"\""
}
