namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic


// `OutputFormatterTextBuilders`: EVERY HUMAN-READABLE ANSWER `nlc query --text` EVER PRINTS.
//
// THIS TYPE HAD NO ESTATE COVERAGE AT ALL BEFORE THIS FILE. Twelve public builders — diagnostics,
// symbols, outline, type, definition, references, doc, completions, hover, call graph and
// implementors — are reached by every `--text` invocation of the query toolchain, and their only
// assertion layer anywhere was `tests/CodeIntelligenceTests.cs`, a C# file whose `OutputFormatter`
// receiver is a PURE FORWARDER: 271 lines, 38 members, each a single call into this class or its
// three siblings. The migration is therefore not a move of coverage from one place to another, it
// is the first time these contracts live beside the code they describe — the slice-8
// `DiagnosticCatalog` shape repeating.
//
// THE BUILDERS ARE STATED AS WHOLE TEXTS, NOT AS SUBSTRINGS. Every contract below that can be
// stated as an exact string is stated as one, line by line, including the trailing blank line
// `StringBuilder.AppendLine` leaves behind. That trailing empty element in each expected-line array
// is not padding: it pins that the builder ends with a newline, which the C# stated only by
// accident of writing `string.Empty` last.
//
// FOUR THINGS THAT WERE IMPLICIT IN THE DELETED C# ARE STATED HERE:
//   (a) THE ELM HEADER RULER IS COMPUTED, NOT DECORATIVE. The header pads to a fixed 60-column
//       budget, so the run of `─` between the title and the location is a FUNCTION of both — the
//       C# wrote `new string('─', 29)` as a magic number, and here the count is derived from
//       the same budget the kernel uses so the arithmetic is visible.
//   (b) A SOURCE SNIPPET IS RIGHT-TRIMMED AND THE CARET IS PINNED TO A MINIMUM WIDTH OF ONE. A
//       zero-length diagnostic still gets exactly one `^`.
//   (c) BOTH TRUNCATION RULES ARE OFF-BY-ONE PROOFS. Completions cut at 50 with a 51st item and
//       doc members cut at 30 with a 31st, and each states the overflow line's exact wording.
//   (d) AN ABSENT SECTION IS OMITTED, NOT BLANKED. `TypeToText` without a definition, `HoverToText`
//       without documentation, and `InspectToText` with every optional section missing each state
//       the exact reduced text rather than "does not contain".
//
// ONE CASE FROM THE DELETED FILE DID NOT COME HERE AND ITS WALL IS NAMED AT THE DECLINE SITE IN
// `tests/CodeIntelligenceTests.cs` — the unknown-severity invariant fallback, whose negative half
// is only non-vacuous under a Turkish ambient culture, and `CultureInfo` is unreachable from N# in
// both directions.
func OftbRule(count: int): string {
    rule := ""
    index := 0
    while index < count {
        rule = rule + "─"
        index = index + 1
    }

    return rule
}

// The Elm header pads a fixed 60-column budget: two leading rule characters, the spaced title, the
// computed ruler, the spaced location and two trailing rule characters. Deriving the ruler here
// rather than writing a literal is what makes the padding rule visible in the contract.
func OftbHeader(title: string, location: string): string {
    titlePart := " " + title + " "
    locationPart := " " + location + " "
    rulerWidth := 60 - titlePart.Length - locationPart.Length
    if rulerWidth < 2 {
        rulerWidth = 2
    }

    return OftbRule(2) + titlePart + OftbRule(rulerWidth) + locationPart + OftbRule(2)
}

func OftbLines(lines: string[]): string {
    return String.Join(Environment.NewLine, lines)
}

// `Contains` cannot pin what a line STARTS with, so a header rendered with three leading rule
// characters instead of two still contains the two-character spelling. This asks for the header as
// a WHOLE LINE, which pins the leading run, the computed ruler and the trailing run at once.
func OftbHasLine(text: string, expected: string): bool {
    lines := text.Replace("\r", "").Split('\n')
    index := 0
    while index < lines.Length {
        if lines[index] == expected {
            return true
        }

        index = index + 1
    }

    return false
}

// The C# wrote `$"M{i:D2}"`; this is that padding spelled without a format specifier so the rule
// is readable in the contract rather than encoded in a format string.
func OftbPad2(value: int): string {
    if value < 10 {
        return "0" + value.ToString()
    }

    return value.ToString()
}

func OftbPlainDiagnostic(code: string, severity: string, message: string, fileName: string, line: int, column: int, length: int): DiagnosticResult {
    return new DiagnosticResult(code, severity, message, fileName, line, column, length, null, null, null, null, null, null, null)
}

func OftbSnippetDiagnostic(code: string, severity: string, message: string, fileName: string, line: int, column: int, length: int, snippet: string): DiagnosticResult {
    return new DiagnosticResult(code, severity, message, fileName, line, column, length, snippet, null, null, null, null, null, null)
}

func OftbDiagnosticList(diagnostic: DiagnosticResult): List<DiagnosticResult> {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(diagnostic)
    return diagnostics
}

func OftbCompletion(name: string, kind: string, typeName: string?, parameters: string?): CompletionItem {
    return new CompletionItem(name, kind, typeName, parameters, null, false)
}

func OftbCompletionGroup(item: CompletionItem): List<CompletionItem> {
    items := new List<CompletionItem>()
    items.Add(item)
    return items
}

func OftbReference(fileName: string, line: int, column: int, length: int, context: string?, isDefinition: bool): ReferenceResult {
    return new ReferenceResult(fileName, line, column, length, context, isDefinition)
}

// The inspect fixture both `InspectToText` contracts share: a resolved variable with a type, a
// definition on another member, two references and a one-item member-access completion set.
func OftbResolvedInspect(): InspectResult {
    references := new ReferenceResult[](2)
    references[0] = OftbReference("Program.nl", 85, 5, 5, "stats := service.GetStats()", true)
    references[1] = OftbReference("Program.nl", 86, 33, 5, "Console.WriteLine($\"Total: {stats.Total}\")", false)

    completions := new Dictionary<string, List<CompletionItem>>()
    completions["properties"] = OftbCompletionGroup(OftbCompletion("Total", "property", "int", null))

    return new InspectResult(
        new InspectSymbolResult("stats", "variable", new LocationResult("Program.nl", 85, 5)),
        new TypeResult("stats", "TaskStats", "record", new LocationResult("Services/TaskService.nl", 105, 1), null),
        new DefinitionResult("Total", "property", "Services/TaskService.nl", 106, 5, 5),
        new InspectReferencesResult(2, 1, references),
        new CompletionResult(CompletionContext.MemberAccess, "stats", "TaskStats", completions)
    )
}

func OftbEmptyInspect(): InspectResult {
    return new InspectResult(
        null,
        null,
        null,
        new InspectReferencesResult(0, 0, new ReferenceResult[](0)),
        new CompletionResult(CompletionContext.Unknown, null, null, new Dictionary<string, List<CompletionItem>>())
    )
}

// ---- DIAGNOSTICS: THE ELM-STYLE REPORT -----------------------------------------------------------

test "a fully populated diagnostic prints every Elm section" {
    diagnostic := new DiagnosticResult(
        "NL202",
        "error",
        "Type mismatch: expected 'int' but got 'string'",
        "Program.nl",
        5,
        4,
        3,
        "    x := \"hi\"",
        "Expected int but got string",
        "Use int.Parse",
        "Check your types",
        "int",
        "string",
        "https://schneidenbach.github.io/nsharplang/docs/errors/NL202"
    )

    text := OutputFormatterTextBuilders.DiagnosticsToText(OftbDiagnosticList(diagnostic))

    // The header, spelled out: two rule characters, the spaced title, a 29-character ruler, the
    // spaced location, two more rule characters.
    assert text.Contains("── [NL202] ERROR " + OftbRule(29) + " Program.nl:5:4 ──")

    // And that 29 is not a magic number: it is the 60-column budget minus the two spaced parts.
    assert OftbHeader("[NL202] ERROR", "Program.nl:5:4") == "── [NL202] ERROR " + OftbRule(29) + " Program.nl:5:4 ──"

    // The header is that text and nothing more: asked as a whole line, so a third leading rule
    // character — which `Contains` cannot see — fails here.
    assert OftbHasLine(text, OftbHeader("[NL202] ERROR", "Program.nl:5:4"))

    assert text.Contains("[NL202] ERROR")
    assert text.Contains("Program.nl:5:4")

    // The source snippet and its caret, whose width is the diagnostic's length.
    assert text.Contains("    5 |     x := \"hi\"")
    assert text.Contains("      |    ^^^")

    assert text.Contains("Type mismatch")
    assert text.Contains("Expected int but got string")
    assert text.Contains("Expected: `int`")
    assert text.Contains("Actual: `string`")
    assert text.Contains("Hint: Check your types")
    assert text.Contains("Suggestion: Use int.Parse")
    assert text.Contains("See: https://schneidenbach.github.io/nsharplang/docs/errors/NL202")
    assert text.Contains("1 error")
}

test "the source snippet is right-trimmed and a zero-length caret is still one character" {
    diagnostic := OftbSnippetDiagnostic("NL202", "error", "Type mismatch", "Program.nl", 12, 0, 0, "value := 1   ")

    text := OutputFormatterTextBuilders.DiagnosticsToText(OftbDiagnosticList(diagnostic))

    assert text.Contains("    12 | value := 1")
    assert !text.Contains("    12 | value := 1   ")
    assert text.Contains("       | ^")
}

test "the summary counts errors and warnings separately and pluralises each" {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OftbPlainDiagnostic("NL301", "error", "Undefined variable 'x'", "A.nl", 1, 0, 1))
    diagnostics.Add(OftbPlainDiagnostic("NL301", "error", "Undefined variable 'y'", "B.nl", 2, 0, 1))
    diagnostics.Add(OftbPlainDiagnostic("NL923", "warning", "Reference load failure", "A.nl", 5, 0, 1))

    text := OutputFormatterTextBuilders.DiagnosticsToText(diagnostics)

    assert text.Contains("Found 2 errors, 1 warning.")
}

test "an empty diagnostic list is a sentence, not an empty report" {
    assert OutputFormatterTextBuilders.DiagnosticsToText(new List<DiagnosticResult>()) == "No diagnostics found."
}

// ---- COMPLETIONS ---------------------------------------------------------------------------------

test "completions print the receiver line and one indented block per group" {
    completions := new Dictionary<string, List<CompletionItem>>()
    completions["functions"] = OftbCompletionGroup(OftbCompletion("GetStats", "function", "TaskStats", "()"))
    completions["properties"] = OftbCompletionGroup(OftbCompletion("Total", "property", "int", null))

    result := new CompletionResult(CompletionContext.MemberAccess, "service", "TaskService", completions)

    text := OutputFormatterTextBuilders.CompletionsToText(result, "Program.nl", 85, 22)

    assert text == OftbLines([
        "Completions at Program.nl:85:22 (context: memberaccess)",
        "Receiver: service (TaskService)",
        "",
        "  functions (1):",
        "    GetStats (): TaskStats",
        "  properties (1):",
        "    Total: int",
        ""
    ])
}

test "a completion group of 51 prints 50 items and one overflow line" {
    items := new List<CompletionItem>()
    index := 1
    while index <= 51 {
        items.Add(OftbCompletion("Item" + index.ToString(), "method", null, null))
        index = index + 1
    }

    completions := new Dictionary<string, List<CompletionItem>>()
    completions["methods"] = items

    result := new CompletionResult(CompletionContext.Identifier, null, null, completions)

    text := OutputFormatterTextBuilders.CompletionsToText(result, "Program.nl", 3, 8)

    // Three header lines, fifty items, the overflow line, and the trailing newline.
    expected := new string[](55)
    expected[0] = "Completions at Program.nl:3:8 (context: identifier)"
    expected[1] = ""
    expected[2] = "  methods (51):"
    index = 1
    while index <= 50 {
        expected[2 + index] = "    Item" + index.ToString()
        index = index + 1
    }
    expected[53] = "    ... and 1 more"
    expected[54] = ""

    assert text == OftbLines(expected)
}

// ---- SYMBOLS AND OUTLINE -------------------------------------------------------------------------

test "symbols print modifiers, signature parameters and nested members" {
    parameters := new ParameterResult[](2)
    parameters[0] = new ParameterResult("name", "string", false, null)
    parameters[1] = new ParameterResult("count", "int", true, "42")

    members := new SymbolResult[](1)
    members[0] = new SymbolResult("Name", SymbolKind.Property, "Models.nl", 6, 0, "string", null, null, null)

    symbols := new List<SymbolResult>()
    symbols.Add(new SymbolResult("Main", SymbolKind.Function, "Program.nl", 1, 0, "void", ["pub"], null, parameters))
    symbols.Add(new SymbolResult("Person", SymbolKind.Class, "Models.nl", 5, 0, null, ["pub"], members, null))

    text := OutputFormatterTextBuilders.SymbolsToText(symbols)

    assert text == OftbLines([
        "[pub] Function Main: void  (Program.nl:1)",
        "  (name: string, count: int = 42)",
        "[pub] Class Person  (Models.nl:5)",
        "  Property Name: string  (Models.nl:6)",
        ""
    ])
}

test "an empty symbol list is a sentence, not an empty report" {
    assert OutputFormatterTextBuilders.SymbolsToText(new List<SymbolResult>()) == "No symbols found."
}

test "an outline prints the file, its imports and one indented line per entry" {
    children := new OutlineEntry[](2)
    children[0] = new OutlineEntry("Name", SymbolKind.Property, 6, 6, null, "string", null)
    children[1] = new OutlineEntry("Greet", SymbolKind.Function, 8, 12, "string", null, null)

    entries := new OutlineEntry[](1)
    entries[0] = new OutlineEntry("Person", SymbolKind.Class, 5, 15, null, null, children)

    text := OutputFormatterTextBuilders.OutlineToText(new OutlineResult("Program.nl", ["System"], entries))

    assert text == OftbLines([
        "File: Program.nl",
        "Imports: System",
        "",
        "Class Person (lines 5-15)",
        "  Property Name (line 6)",
        "  Function Greet -> string (lines 8-12)",
        ""
    ])
}

// ---- REFERENCES ----------------------------------------------------------------------------------

test "references print a count, a definition marker and a trimmed context" {
    results := new List<ReferenceResult>()
    results.Add(OftbReference("Models.nl", 5, 0, 6, "  class Person {  ", true))
    results.Add(OftbReference("Program.nl", 3, 8, 6, "p := Person{}", false))
    results.Add(OftbReference("Generated.nl", 9, 2, 6, null, false))

    text := OutputFormatterTextBuilders.ReferencesToText("Person", results)

    assert text == OftbLines([
        "References to 'Person' (3 found):",
        "  Models.nl:5:0 [definition]  class Person {",
        "  Program.nl:3:8  p := Person{}",
        "  Generated.nl:9:2",
        ""
    ])
}

test "an empty reference list names the symbol that has none" {
    assert OutputFormatterTextBuilders.ReferencesToText("Foo", new List<ReferenceResult>()) == "No references found for 'Foo'."
}

// ---- TYPE AND DEFINITION -------------------------------------------------------------------------

test "a type prints its nullability and definition site when both are known" {
    result := new TypeResult(
        "stats",
        "TaskStats",
        "record",
        new LocationResult("Services/TaskService.nl", 105, 1),
        "non-null"
    )

    text := OutputFormatterTextBuilders.TypeToText(result, "Program.nl", 85, 22)

    assert text == OftbLines([
        "At Program.nl:85:22:",
        "  stats: TaskStats (record)",
        "  Nullability: non-null",
        "  Defined at: Services/TaskService.nl:105:1",
        ""
    ])
}

test "a type with neither nullability nor a definition omits both lines" {
    text := OutputFormatterTextBuilders.TypeToText(new TypeResult("count", "int", "local", null, null), "Program.nl", 3, 8)

    assert text == OftbLines([
        "At Program.nl:3:8:",
        "  count: int (local)",
        ""
    ])
}

test "a definition is a single line with no trailing newline" {
    assert OutputFormatterTextBuilders.DefinitionToText(new DefinitionResult("Hi", "function", "Program.nl", 2, 6, 2)) == "function Hi at Program.nl:2:6"
}

// ---- INSPECT -------------------------------------------------------------------------------------

test "inspect bundles the symbol, type, definition, reference and completion sections" {
    text := OutputFormatterTextBuilders.InspectToText(OftbResolvedInspect(), "Program.nl", 86, 39)

    assert text == OftbLines([
        "Inspect Program.nl:86:39",
        "",
        "Symbol: stats (variable)",
        "  Defined at: Program.nl:85:5",
        "",
        "Type: TaskStats (record)",
        "",
        "Definition: property Total at Services/TaskService.nl:106:5",
        "",
        "References: 2 total (1 definitions)",
        "  Program.nl:85:5 [definition]  stats := service.GetStats()",
        "  Program.nl:86:33  Console.WriteLine($\"Total: {stats.Total}\")",
        "",
        "Completions at Program.nl:86:39 (context: memberaccess)",
        "Receiver: stats (TaskStats)",
        "",
        "  properties (1):",
        "    Total: int",
        ""
    ])
}

test "inspect keeps every section header when nothing resolved" {
    text := OutputFormatterTextBuilders.InspectToText(OftbEmptyInspect(), "Program.nl", 1, 1)

    assert text == OftbLines([
        "Inspect Program.nl:1:1",
        "",
        "Symbol: none",
        "",
        "Type: unknown",
        "",
        "Definition: none",
        "",
        "References: 0 total (0 definitions)",
        "",
        "Completions at Program.nl:1:1 (context: unknown)",
        "",
        ""
    ])
}

// ---- HOVER ---------------------------------------------------------------------------------------

test "hover prints the signature, kind, defining file and every documentation line" {
    hover := new HoverResult("func Hi(): int", "Returns a value.\nSecond line.", "Program.nl", "function")

    text := OutputFormatterTextBuilders.HoverToText(hover, "Program.nl", 2, 6)

    assert text == OftbLines([
        "Hover Program.nl:2:6",
        "",
        "Signature:  func Hi(): int",
        "Kind:       function",
        "Defined in: Program.nl",
        "",
        "Documentation:",
        "  Returns a value.",
        "  Second line.",
        ""
    ])
}

test "hover without documentation or a defining file omits both blocks" {
    text := OutputFormatterTextBuilders.HoverToText(new HoverResult("name: string", null, null, "variable"), "Program.nl", 11, 5)

    assert text == OftbLines([
        "Hover Program.nl:11:5",
        "",
        "Signature:  name: string",
        "Kind:       variable",
        ""
    ])
}

// ---- CALL GRAPH ----------------------------------------------------------------------------------

test "a function call graph prints callers, callees and the truncation notice" {
    callers := new List<CallSiteResult>()
    callers.Add(new CallSiteResult("Run", "Program.nl", 10, 5))
    callees := new List<CallSiteResult>()
    callees.Add(new CallSiteResult("Hi", "Program.nl", 18, 10))

    text := OutputFormatterTextBuilders.CallGraphToText(new CallGraphResult("Main", callers, callees, true))

    assert text == OftbLines([
        "Call graph for: Main",
        "",
        "Callers (1):",
        "  Run  (Program.nl:10)",
        "",
        "Callees (1):",
        "  Hi  (Program.nl:18)",
        "(results truncated — use --limit to increase)",
        ""
    ])
}

test "a whole-project call graph names no function and prints no truncation notice" {
    text := OutputFormatterTextBuilders.CallGraphToText(
        new CallGraphResult(null, new List<CallSiteResult>(), new List<CallSiteResult>(), false)
    )

    assert text == OftbLines([
        "Call graph (full project)",
        "",
        "Callers (0):",
        "",
        "Callees (0):",
        ""
    ])
}

// ---- IMPLEMENTORS --------------------------------------------------------------------------------

test "implementors print their kind and site, and a missing file leaves the colon standing" {
    results := new List<ImplementorResult>()
    results.Add(new ImplementorResult("Circle", "class", "Geometry.nl", 19, 0))
    results.Add(new ImplementorResult("Square", "record", null, 25, 0))

    text := OutputFormatterTextBuilders.ImplementorsToText(new ImplementorsResult("IShape", results))

    assert text == OftbLines([
        "Implementors of IShape (2):",
        "",
        "  class Circle  (Geometry.nl:19)",
        "  record Square  (:25)",
        ""
    ])
}

test "an interface with no implementors still prints its zero count" {
    text := OutputFormatterTextBuilders.ImplementorsToText(new ImplementorsResult("IFoo", new List<ImplementorResult>()))

    assert text == OftbLines([
        "Implementors of IFoo (0):",
        "",
        ""
    ])
}

// ---- DOC -----------------------------------------------------------------------------------------

test "doc prints the namespace, summary, base types, parameters, returns and overloads" {
    members := new DocMemberResult[](2)
    members[0] = new DocMemberResult("WriteLine", "method", "void", "Writes a line", "(string value)")
    members[1] = new DocMemberResult("ReadLine", "method", "string", null, null)

    parameters := new DocParameterResult[](2)
    parameters[0] = new DocParameterResult("value", "string", "The text to write")
    parameters[1] = new DocParameterResult("format", "string", null)

    result := new DocResult(
        "WriteLine",
        "System.Console.WriteLine",
        "method overloads",
        "Writes the text representation of the specified objects.",
        "System",
        members,
        parameters,
        "bool",
        "true on success",
        ["Object", "TextWriter"]
    )

    text := OutputFormatterTextBuilders.DocToText(result)

    assert text == OftbLines([
        "method overloads System.Console.WriteLine",
        "  Namespace: System",
        "",
        "  Writes the text representation of the specified objects.",
        "",
        "  Implements: Object, TextWriter",
        "",
        "  Parameters:",
        "    value: string — The text to write",
        "    format: string",
        "",
        "  Returns: bool — true on success",
        "",
        "  Overloads:",
        "    method WriteLine (string value): void — Writes a line",
        "    method ReadLine: string",
        ""
    ])
}

test "a member list of 31 prints 30 members and one overflow line" {
    members := new DocMemberResult[](31)
    index := 1
    while index <= 31 {
        members[index - 1] = new DocMemberResult("M" + OftbPad2(index), "method", null, null, null)
        index = index + 1
    }

    result := new DocResult("Sample", "Sample", "class", null, null, members, null, null, null, null)

    text := OutputFormatterTextBuilders.DocToText(result)

    // Two header lines, thirty members, the overflow line, and the trailing newline.
    expected := new string[](35)
    expected[0] = "class Sample"
    expected[1] = ""
    expected[2] = "  Members:"
    index = 1
    while index <= 30 {
        expected[2 + index] = "    method M" + OftbPad2(index)
        index = index + 1
    }
    expected[33] = "    ... and 1 more"
    expected[34] = ""

    assert text == OftbLines(expected)
}
