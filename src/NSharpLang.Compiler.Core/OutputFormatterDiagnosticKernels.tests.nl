namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar


// `OutputFormatterDiagnosticKernels` AND `CodeIntelligenceResultKernels`: THE SEVERITY ARITHMETIC
// AND THE DUPLICATE RULES EVERY DIAGNOSTIC ANSWER PASSES THROUGH — PLUS THE ONE END-TO-END
// QUESTION THAT PUTS THEM TOGETHER.
//
// NEITHER KERNEL HAD ANY ESTATE COVERAGE BEFORE THIS FILE. `tests/CodeIntelligenceTests.cs` — a C#
// file whose `OutputFormatter` and `CodeIntelligenceService` receivers are both PURE FORWARDERS —
// was their only assertion layer anywhere.
//
// THE LAST TWO CASES IN THIS FILE ARE THE PAIR FINDING 97.6 HELD HOSTAGE. They build a
// `ProjectSnapshot` BY HAND — a real parsed `CompilationUnit`, a hand-seeded `CompilerError`, a
// cached source text — and ask `CodeIntelligenceQueries.Diagnostics`, which runs the compiler-error
// arm AND the real `Linter` over the same file and then applies shadowing suppression across the
// two. Until 020 slice 10 published the `Dictionary<K, V>` → `IReadOnlyDictionary<K, V>` widening,
// the snapshot's three dictionary parameters could not be spelled from N# at all and these two
// contracts could not live here. `CodeIntelligenceDiagnostics.tests.nl` states the BUILD in
// isolation and always passes an EMPTY unit map, so the lint walk never runs there; these two are
// the only contracts anywhere that drive both arms of the same answer.
//
// THREE THINGS THAT WERE IMPLICIT IN THE DELETED C# ARE STATED HERE:
//   (a) SUPPRESSION IS CODE-SCOPED, NOT FILE-SCOPED. A compiler error in a file removes the
//       LINTER's shadowing row for that file and NOTHING ELSE — the unused-parameter lint on the
//       very same file survives a compiler error on it, which is what makes the rule a rule rather
//       than "errors win".
//   (b) THE SEVERITY SUMMARY IGNORES WHAT IT DOES NOT KNOW. A fourth severity is neither counted
//       nor an error; the three counters stay at one apiece.
//   (c) REFERENCE DEDUPLICATION IS BY POSITION AND IT SORTS. Two rows at the same file, line and
//       column collapse to the FIRST — its context survives, the later one's is discarded — and the
//       survivors come back file-then-line ordered regardless of input order.
func OfdkPlainDiagnostic(code: string, severity: string, message: string, fileName: string, line: int, column: int, length: int): DiagnosticResult {
    return new DiagnosticResult(code, severity, message, fileName, line, column, length, null, null, null, null, null, null, null)
}

func OfdkTypedDiagnostic(code: string, severity: string, message: string, fileName: string, line: int, column: int, length: int, expectedType: string, actualType: string): DiagnosticResult {
    return new DiagnosticResult(code, severity, message, fileName, line, column, length, null, null, null, null, expectedType, actualType, null)
}

func OfdkReference(fileName: string, line: int, column: int, length: int, context: string): ReferenceResult {
    return new ReferenceResult(fileName, line, column, length, context, false)
}

func OfdkCodes(results: List<DiagnosticResult>): string {
    text := ""
    index := 0
    while index < results.Count {
        if index > 0 {
            text = text + ","
        }

        text = text + results[index].Code
        index = index + 1
    }

    return text
}

func OfdkHasCode(results: List<DiagnosticResult>, code: string): bool {
    index := 0
    while index < results.Count {
        if results[index].Code == code {
            return true
        }

        index = index + 1
    }

    return false
}

// A real temp project: the file exists on disk because the linter resolves its `.editorconfig`
// from the file's own directory, and the snapshot caches the text so nothing is re-read.
func OfdkTempRoot(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-codeintel-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func OfdkParse(source: string, filePath: string): CompilationUnit {
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    unit := parsed.CompilationUnit
    if unit == null {
        throw new InvalidOperationException("The diagnostic fixture source did not parse.")
    }

    return (CompilationUnit)unit
}

// The snapshot shape `CodeIntelligenceService.LoadProject` freezes, built by hand: three
// case-insensitive dictionaries, the project's errors, its source list, no project index.
func OfdkSnapshot(projectRoot: string, filePath: string, source: string, compilerError: CompilerError): ProjectSnapshot {
    fullPath := Path.GetFullPath(filePath)

    units := new Dictionary<string, CompilationUnit>(StringComparer.OrdinalIgnoreCase)
    units[fullPath] = OfdkParse(source, fullPath)

    models := new Dictionary<string, SemanticModel>(StringComparer.OrdinalIgnoreCase)

    errors := new List<CompilerError>()
    errors.Add(compilerError)

    sourceFiles := new List<string>()
    sourceFiles.Add(fullPath)

    sourceTexts := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    sourceTexts[fullPath] = source

    return new ProjectSnapshot(projectRoot, units, models, errors, sourceFiles, null, sourceTexts, null, null)
}

func OfdkWriteFixture(root: string, source: string): string {
    filePath := Path.Combine(root, "Program.nl")
    File.WriteAllText(filePath, source)
    return filePath
}

// ---- THE SEVERITY ARITHMETIC ---------------------------------------------------------------------

test "the severity summary counts the three known levels and ignores a fourth" {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OfdkPlainDiagnostic("NL101", "error", "Syntax error", "Program.nl", 1, 1, 1))
    diagnostics.Add(OfdkPlainDiagnostic("NL201", "warning", "Warning", "Program.nl", 2, 1, 1))
    diagnostics.Add(OfdkPlainDiagnostic("NL301", "info", "Info", "Program.nl", 3, 1, 1))
    diagnostics.Add(OfdkPlainDiagnostic("NL999", "hint", "Hint", "Program.nl", 4, 1, 1))

    summary := OutputFormatterDiagnosticKernels.SummarizeDiagnosticSeverities(diagnostics)

    assert summary.Errors == 1
    assert summary.Warnings == 1
    assert summary.Info == 1
}

test "a diagnostic summary remembers the three counts it was constructed with" {
    summary := new DiagnosticSummary(3, 2, 1)

    assert summary.Errors == 3
    assert summary.Warnings == 2
    assert summary.Info == 1
}

test "the severity filter is case-insensitive and materialises the matching rows only" {
    diagnostics := new List<DiagnosticResult>()
    diagnostics.Add(OfdkTypedDiagnostic("NL202", "error", "Type mismatch", "Program.nl", 5, 4, 3, "int", "string"))
    diagnostics.Add(OfdkPlainDiagnostic("NL923", "warning", "Reference load failure", "Program.nl", 10, 4, 1))
    diagnostics.Add(OfdkPlainDiagnostic("NL905", "info", "Informational", "Program.nl", 12, 4, 1))

    warnings := OutputFormatterDiagnosticKernels.FilterDiagnosticSeverityResults(diagnostics, "WARNING")

    assert warnings.Count == 1
    assert warnings[0].Code == "NL923"
}

// ---- REFERENCE DEDUPLICATION ---------------------------------------------------------------------

test "reference deduplication collapses by position, keeps the first context and sorts the rest" {
    references := new List<ReferenceResult>()
    references.Add(OfdkReference("Program.nl", 10, 5, 6, "p := Person{}"))
    references.Add(new ReferenceResult("Models.nl", 1, 0, 6, "class Person {", true))
    references.Add(OfdkReference("Program.nl", 10, 5, 6, "duplicate"))
    references.Add(OfdkReference("Program.nl", 2, 8, 6, "let p: Person"))

    deduplicated := CodeIntelligenceResultKernels.DeduplicateReferenceResults(references)

    assert deduplicated.Count == 3
    assert deduplicated[0].File == "Models.nl"
    assert deduplicated[0].IsDefinition
    assert deduplicated[1].Line == 2
    assert deduplicated[2].Line == 10

    // The survivor is the FIRST row at that position; the later row's context is discarded.
    assert deduplicated[2].Context == "p := Person{}"
}

// ---- THE END-TO-END DIAGNOSTIC ANSWER ------------------------------------------------------------

test "a compiler error does not silence an unrelated lint on the same file" {
    root := OfdkTempRoot()
    source := "func Main(unused: int) {\n    Console.WriteLine(undefined)\n}"
    filePath := OfdkWriteFixture(root, source)

    compilerError := CompilerError.WithSnippet(
        ErrorCode.UndefinedVariable,
        "Undefined variable 'undefined'",
        filePath,
        2,
        23,
        "    Console.WriteLine(undefined)",
        9,
        null,
        ErrorSeverity.Error
    )

    diagnostics := CodeIntelligenceQueries.Diagnostics(OfdkSnapshot(root, filePath, source, compilerError), null)

    // The compiler's undefined-variable error and the linter's unused-parameter row both survive.
    assert OfdkHasCode(diagnostics, "NL301")
    assert OfdkHasCode(diagnostics, "NL012")

    Directory.Delete(root, true)
}

test "a compiler shadowing error silences the linter's shadowing row and nothing else" {
    root := OfdkTempRoot()
    source := "func Main(value: int, unused: int) {\n    if true {\n        value := 1\n    }\n}"
    filePath := OfdkWriteFixture(root, source)

    compilerError := CompilerError.WithSnippet(
        ErrorCode.ShadowedDeclaration,
        "Local variable 'value' shadows an existing declaration",
        filePath,
        3,
        9,
        "        value := 1",
        5,
        null,
        ErrorSeverity.Error
    )

    diagnostics := CodeIntelligenceQueries.Diagnostics(OfdkSnapshot(root, filePath, source, compilerError), null)

    // The compiler's own shadowing error stands; the linter's duplicate of it is removed.
    assert OfdkHasCode(diagnostics, "NL316")
    assert !OfdkHasCode(diagnostics, "NL020")

    // Suppression is scoped to the shadowing RULE, not to the file: the unused-parameter lint on
    // the very same file survives the compiler error that removed the shadowing one.
    assert !OfdkCodes(diagnostics).Contains("NL020")
    assert OfdkHasCode(diagnostics, "NL012")
    assert diagnostics.Count > 0

    Directory.Delete(root, true)
}
