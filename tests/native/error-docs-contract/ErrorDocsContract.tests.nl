namespace NSharpLang.ErrorDocsContract.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO


// A DIAGNOSTIC CODE WITHOUT A DOCUMENTATION PAGE CANNOT BE ADDED.
//
// Every diagnostic `nlc` prints ends with "Read more: " + `DiagnosticDocs.UrlFor(code)`, which
// resolves to `website/docs/errors/<code>.md` on the published site. Nothing checked that the page
// on the other end of that promise existed, and 96 of the catalog's 101 codes did not have one —
// so the compiler's most-repeated sentence was, for 95% of codes, a link to a 404.
//
// THIS IS THE RATCHET. `Descriptors` is walked as the SOURCE OF TRUTH and crossed against the
// directory, in BOTH directions: a code with no page fails, and a page naming no code fails. A row
// added to `ErrorCode.nl` or `AddLinterRuleDescriptors` and forgotten in the docs now fails a
// contract instead of shipping a dead link.
//
// EACH FAILURE NAMES THE CODES. The assertions compare a JOINED CENSUS against "" and pass the
// census as the assert's message, so a red run prints exactly which codes are missing rather than
// "expected true".
class EdcPaths {
    static func RepositoryRoot(): string {
        current: string? = Path.GetFullPath(Environment.CurrentDirectory)
        while current != null {
            value := current ?? ""
            if File.Exists(Path.Combine(value, "AGENTS.md")) && Directory.Exists(Path.Combine(value, "src")) && Directory.Exists(Path.Combine(value, "tests")) {
                return value
            }

            parent := Path.GetDirectoryName(value)
            if parent == null || parent == "" || parent == value {
                current = null
            } else {
                current = parent
            }
        }

        throw new InvalidOperationException("Could not locate the repository root above this test tree.")
    }

    static func ErrorsDirectory(): string {
        root := EdcPaths.RepositoryRoot()
        return Path.Combine(Path.Combine(Path.Combine(root, "website"), "docs"), "errors")
    }

    static func PageFor(code: string): string {
        return Path.Combine(EdcPaths.ErrorsDirectory(), code + ".md")
    }

    // Where the `NSYS` codes live, as literals, because nothing publishes them as descriptors.
    static func SystemsSourceDirectory(): string {
        root := EdcPaths.RepositoryRoot()
        return Path.Combine(Path.Combine(root, "src"), "NSharpLang.Compiler.BootstrapServices")
    }

    static func RepositoryPath(relative: string): string {
        return Path.Combine(EdcPaths.RepositoryRoot(), relative)
    }
}

func EdcCatalogCodes(): List<string> {
    codes := new List<string>()
    published := DiagnosticCatalog.AllCodes()
    i := 0
    while i < published.Count {
        codes.Add(published[i])
        i = i + 1
    }

    return codes
}

func EdcPageCodes(): List<string> {
    codes := new List<string>()
    directory := EdcPaths.ErrorsDirectory()
    if !Directory.Exists(directory) {
        return codes
    }

    paths := Directory.GetFiles(directory, "*.md")
    i := 0
    while i < paths.Length {
        name := Path.GetFileNameWithoutExtension(paths[i])
        if name != "index" {
            codes.Add(name)
        }

        i = i + 1
    }

    codes.Sort()
    return codes
}

// The nineteen `NSYS` codes the systems analyzer can report. There is NO registry for them: unlike
// the `NL` codes, which `DiagnosticCatalog` publishes as descriptors, an `NSYS` code exists only as
// a string literal at the site that reports it, scattered across the `Systems*Policy` kernels. That
// is a real gap and a later slice should give them descriptors — until then this census is DERIVED
// FROM THE SOURCE rather than typed here, so a twentieth code cannot be added without a page.
func EdcSystemsCodes(): List<string> {
    codes := new List<string>()
    directory := EdcPaths.SystemsSourceDirectory()
    if !Directory.Exists(directory) {
        return codes
    }

    paths := Directory.GetFiles(directory, "Systems*.nl")
    i := 0
    while i < paths.Length {
        sourcePath := paths[i]
        if !sourcePath.EndsWith(".tests.nl", StringComparison.Ordinal) {
            EdcCollectSystemsCodes(File.ReadAllText(sourcePath), codes)
        }

        i = i + 1
    }

    codes.Sort()
    return codes
}

// Every `"NSYS<digits>"` literal in one source text, added once. A hand-rolled scan rather than a
// regular expression: the pattern is four characters and a run of digits, and the contract must not
// depend on a library the columnar backend may decline to emit across an assembly boundary.
func EdcCollectSystemsCodes(text: string, codes: List<string>) {
    i := 0
    while i < text.Length - 4 {
        if text[i] == 'N' && text[i + 1] == 'S' && text[i + 2] == 'Y' && text[i + 3] == 'S' {
            j := i + 4
            while j < text.Length && char.IsDigit(text[j]) {
                j = j + 1
            }

            if j > i + 4 {
                code := text.Substring(i, j - i)
                if !EdcContains(codes, code) {
                    codes.Add(code)
                }
            }

            i = j
        } else {
            i = i + 1
        }
    }
}

// Catalog plus systems: every code the product can print, and therefore every code whose printed
// "Read more" link must land on a page.
func EdcDocumentedCodes(): List<string> {
    codes := EdcCatalogCodes()
    systemsCodes := EdcSystemsCodes()
    i := 0
    while i < systemsCodes.Count {
        codes.Add(systemsCodes[i])
        i = i + 1
    }

    return codes
}

// ─── THE EXEMPTION LIST ───────────────────────────────────────────────────────────────────────
//
// SIX CODES ARE EXEMPT FROM THE PAGE REQUIREMENT, AND EACH ONE IS A HOLE IN THE LANGUAGE, NOT A
// DOCUMENTATION GAP. The catalog publishes them, the rule each one names is a rule N# intends to
// enforce, and NOTHING ENFORCES IT — measured by probe through the shipped CLI, not inferred. A
// page for one of them would have to describe a diagnostic the reader can never see, so instead the
// hole is written down here where a contract can hold it.
//
// A row is `code|defect|sentence`:
//   code     - the exempt code, which must still be in the catalog.
//   defect   - a repository path a reader can open. The contract checks the path EXISTS, so an
//              exemption cannot be discharged by deleting the record it points at.
//   sentence - the exact program that is silent today, in one line.
//
// THE EXEMPTION IS NOT A PARKING SPACE. `tests/native/error-docs-contract` fails if a row loses its
// defect or its sentence, and fails if an exempt code leaves the catalog; the repro contract fails
// the day one of these programs starts reporting its code, because at that point the rule exists and
// the code owes the reader a page. Discharging one means writing the page and deleting the row.
func EdcExemptions(): List<string> {
    rows := new List<string>()
    rows.Add("NL204|systems-language-closeout/STATUS.md|`v := 42` then `v as string` is accepted in silence; no conversion check runs on `as` or on a cast between unrelated types.")
    rows.Add("NL307|systems-language-closeout/STATUS.md|Circular inheritance is not diagnosed; it reaches the emitter and fails there as an NL103 columnar decline, which names the backend rather than the cycle.")
    rows.Add("NL502|systems-language-closeout/STATUS.md|A wildcard arm written before a live arm is accepted in silence; the live arm is dead code the compiler never mentions.")
    rows.Add("NL801|systems-language-closeout/STATUS.md|More than one base class is not diagnosed; it reaches the emitter and fails there as an NL103 columnar decline.")
    rows.Add("NL802|systems-language-closeout/STATUS.md|`class Derived : Base` where `Base` is `sealed` is accepted in silence and the whole project checks clean.")
    rows.Add("NL806|systems-language-closeout/STATUS.md|A constructor called with the wrong arity is not diagnosed; it reaches the emitter and fails there as an NL103 columnar decline.")
    return rows
}

func EdcExemptField(row: string, index: int): string {
    remaining := row
    i := 0
    while i < index {
        separator := remaining.IndexOf("|", StringComparison.Ordinal)
        if separator < 0 {
            return ""
        }

        remaining = remaining.Substring(separator + 1)
        i = i + 1
    }

    separator := remaining.IndexOf("|", StringComparison.Ordinal)
    if separator < 0 {
        return remaining
    }

    return remaining.Substring(0, separator)
}

func EdcExemptCodes(): List<string> {
    codes := new List<string>()
    rows := EdcExemptions()
    i := 0
    while i < rows.Count {
        codes.Add(EdcExemptField(rows[i], 0))
        i = i + 1
    }

    return codes
}

func EdcJoin(values: List<string>): string {
    joined := ""
    i := 0
    while i < values.Count {
        if i > 0 {
            joined = joined + " "
        }

        joined = joined + values[i]
        i = i + 1
    }

    return joined
}

func EdcContains(values: List<string>, needle: string): bool {
    i := 0
    while i < values.Count {
        if values[i] == needle {
            return true
        }

        i = i + 1
    }

    return false
}

// Every code the product can print that has no `website/docs/errors/<code>.md`, except the ones on
// the exemption list — whose rule nothing enforces, so there is no diagnostic to document.
func EdcCodesWithoutPage(): string {
    missing := new List<string>()
    exempt := EdcExemptCodes()
    codes := EdcDocumentedCodes()
    i := 0
    while i < codes.Count {
        if !EdcContains(exempt, codes[i]) && !File.Exists(EdcPaths.PageFor(codes[i])) {
            missing.Add(codes[i])
        }

        i = i + 1
    }

    return EdcJoin(missing)
}

// Every page whose name is not a code the product can print.
func EdcPagesWithoutCode(): string {
    documented := EdcDocumentedCodes()
    orphans := new List<string>()
    pageCodes := EdcPageCodes()
    i := 0
    while i < pageCodes.Count {
        if !EdcContains(documented, pageCodes[i]) {
            orphans.Add(pageCodes[i])
        }

        i = i + 1
    }

    return EdcJoin(orphans)
}

// Every exemption row that does not say enough to be acted on, and every exempt code the catalog no
// longer publishes.
func EdcBrokenExemptions(): string {
    broken := new List<string>()
    catalogCodes := EdcCatalogCodes()
    rows := EdcExemptions()
    i := 0
    while i < rows.Count {
        code := EdcExemptField(rows[i], 0)
        defect := EdcExemptField(rows[i], 1)
        sentence := EdcExemptField(rows[i], 2)
        if code.Length == 0 {
            broken.Add("row-" + i.ToString() + ":no-code")
        }

        if defect.Length == 0 {
            broken.Add(code + ":no-defect-reference")
        } else {
            if !File.Exists(EdcPaths.RepositoryPath(defect)) {
                broken.Add(code + ":defect-reference-does-not-exist")
            }
        }

        if sentence.Length < 40 {
            broken.Add(code + ":no-sentence")
        }

        if !EdcContains(catalogCodes, code) {
            broken.Add(code + ":not-in-catalog")
        }

        if File.Exists(EdcPaths.PageFor(code)) {
            broken.Add(code + ":has-a-page-so-delete-the-exemption")
        }

        i = i + 1
    }

    return EdcJoin(broken)
}

// Every page that does not open with the front matter the sidebar and the tab title read.
func EdcPagesWithBadFrontMatter(): string {
    bad := new List<string>()
    pageCodes := EdcPageCodes()
    i := 0
    while i < pageCodes.Count {
        pageCode := pageCodes[i]
        text := File.ReadAllText(EdcPaths.PageFor(pageCode))
        if !text.StartsWith("---\n") {
            bad.Add(pageCode + ":no-front-matter")
        } else {
            if !text.Contains("sidebar_label: " + pageCode) {
                bad.Add(pageCode + ":sidebar_label")
            }

            if !text.Contains("title: \"" + pageCode + ":") {
                bad.Add(pageCode + ":title")
            }

            if !text.Contains("# " + pageCode + ":") {
                bad.Add(pageCode + ":heading")
            }
        }

        i = i + 1
    }

    return EdcJoin(bad)
}

// Every page carrying no runnable repro. The marker is the house style already used by the pages
// that exist: the offending line of an `n#` block ends `// ERROR <code>`. `tests/native/…` reads
// the SAME bytes the reader reads, so a page and its contract cannot drift.
func EdcPagesWithoutRepro(): string {
    missing := new List<string>()
    pageCodes := EdcPageCodes()
    i := 0
    while i < pageCodes.Count {
        text := File.ReadAllText(EdcPaths.PageFor(pageCodes[i]))
        if !text.Contains("// ERROR " + pageCodes[i]) {
            missing.Add(pageCodes[i])
        }

        i = i + 1
    }

    return EdcJoin(missing)
}

// ─── the ratchet, in both directions ──────────────────────────────────────────────────────────

test "EVERY diagnostic code the catalog publishes has a documentation page" {
    assert EdcCodesWithoutPage() == "", EdcCodesWithoutPage()
}

test "EVERY page under website/docs/errors names a code the product can print" {
    assert EdcPagesWithoutCode() == "", EdcPagesWithoutCode()
}

test "the NSYS census is READ OUT OF THE SOURCE, so a new systems code cannot skip its page" {
    systemsCodes := EdcSystemsCodes()

    // Not a typed list: these are the literals the `Systems*Policy` kernels report. If a kernel
    // stops reporting one, it leaves this census and its page becomes an orphan — which the page
    // contract above then names.
    assert systemsCodes.Count == 19, EdcJoin(systemsCodes)
    assert EdcContains(systemsCodes, "NSYS001")
    assert EdcContains(systemsCodes, "NSYS010")
    assert EdcContains(systemsCodes, "NSYS060")
    assert EdcContains(systemsCodes, "NSYS180")
    assert !EdcContains(systemsCodes, "NSYS999")

    // And they take the same documentation host as every NL code — one constant, no second spelling.
    i := 0
    while i < systemsCodes.Count {
        assert DiagnosticDocs.UrlFor(systemsCodes[i]) == "https://schneidenbach.github.io/nsharplang/docs/errors/" + systemsCodes[i], systemsCodes[i]
        i = i + 1
    }
}

test "EVERY exemption names a code the catalog still publishes, a defect that exists, and a sentence" {
    assert EdcBrokenExemptions() == "", EdcBrokenExemptions()

    // The list is small ON PURPOSE. It is the count of language rules N# publishes a code for and
    // does not enforce; it may shrink, and it must never grow without a measured probe behind it.
    assert EdcExemptions().Count == 6
}

test "EVERY page carries the front matter the site and the tab title read" {
    assert EdcPagesWithBadFrontMatter() == "", EdcPagesWithBadFrontMatter()
}

test "EVERY page carries a repro marked with its own code" {
    assert EdcPagesWithoutRepro() == "", EdcPagesWithoutRepro()
}

// ─── the promise the compiler prints ──────────────────────────────────────────────────────────

test "the URL the compiler prints for a code is the page this contract requires" {
    codes := EdcCatalogCodes()
    i := 0
    while i < codes.Count {
        assert DiagnosticCatalog.DocsUrlFor(codes[i]) == DiagnosticDocs.UrlFor(codes[i]), codes[i]
        i = i + 1
    }
}

test "there is exactly ONE documentation host, and it is the published site" {
    assert DiagnosticDocs.UrlFor("") == "https://schneidenbach.github.io/nsharplang/docs/errors/"
    assert DiagnosticDocs.UrlFor("NL320") == "https://schneidenbach.github.io/nsharplang/docs/errors/NL320"
    // NSYS findings take the same constant, not a second spelling.
    assert DiagnosticDocs.UrlFor("NSYS010") == "https://schneidenbach.github.io/nsharplang/docs/errors/NSYS010"
}

// ═══ CONTRACT B — EVERY PUBLISHED EXAMPLE IS RUN ══════════════════════════════════════════════
//
// A documentation page whose example does not reproduce is worse than no page: it teaches a shape
// the compiler does not actually reject, and nothing notices when the compiler changes underneath
// it. So every ```n# block on every page that carries a `// ERROR <code>` marker is EXTRACTED,
// written to a throwaway project, and put through the REAL SHIPPED `nlc check` — the same binary a
// user runs. The marked code must be reported AT THE MARKED LINE, and every error-severity
// diagnostic the run produces must be marked. A page cannot drift from the compiler.
//
// Fenced blocks rather than a fixture tree, deliberately: a directory of `.nl` files under the
// repository would be walked by the root `nlc format --check`, by the compile-time corpus and by
// every estate scan, and the examples are DELIBERATELY malformed. The page is the fixture.
//
// MULTI-FILE EXAMPLES, one rule. Some rules only exist ACROSS files: `NL308` is a visibility rule
// and `NL702` is a collision between two imports, and neither can be stated in a single file. So:
//
//     A ```n# block whose FIRST LINE is `// FILE <name>.nl` is written to the probe project as
//     `<name>.nl`. Consecutive such blocks accumulate; the example is COMPLETED by the block headed
//     `// FILE Program.nl`, or by any block with no `// FILE` header at all, which is the program.
//
// The header is an ordinary comment inside the file that is written, so it occupies line 1 and every
// `// ERROR` line number counts from it — what the page shows is byte-for-byte what ran, with
// nothing synthesised in between and no fixture living outside the page.
//
// A COMPANION OF ANY OTHER KIND is named by its fence, which is also how Docusaurus labels a code
// block with a filename:
//
//     ```json title="hot-summaries.json"
//     { … exact bytes … }
//     ```
//
// The block's bytes are written verbatim to that name, with nothing added — necessary for files
// that cannot carry a comment at all. `NSYS150` needs a JSON sidecar, and `System.Text.Json`
// rejects comments, so a `// FILE` header would make the very file the example is about invalid.
// `title="project.yml"` REPLACES the default project file, which is how a systems page opts in:
// the systems analyzer reports nothing at all unless the project asks for it. A project file
// persists for the WHOLE PAGE once given, so a page may mark more than one example.
class EdbProbe {
    static func CliPath(): string {
        root := EdcPaths.RepositoryRoot()
        cli := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0")
        return Path.Combine(cli, "Cli.dll")
    }

    static func WorkspaceRoot(): string {
        return Path.Combine(Path.GetTempPath(), "nsharp-error-docs-repro")
    }

    // Write `source` as a project and return what `nlc check --text` printed. `library` so an
    // example never has to invent a `main` it would then have to explain. `companions` is zero or
    // more further files, each introduced by its own `// FILE <name>.nl` header line.
    static func Check(name: string, source: string, companions: string, project: string): string {
        directory := Path.Combine(EdbProbe.WorkspaceRoot(), name)
        if Directory.Exists(directory) {
            Directory.Delete(directory, true)
        }

        Directory.CreateDirectory(directory)
        projectText := "name: ErrorDocsRepro\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\n"
        if project.Length > 0 {
            projectText = project
        }

        File.WriteAllText(Path.Combine(directory, "project.yml"), projectText)
        File.WriteAllText(Path.Combine(directory, "Program.nl"), source)
        EdbWriteCompanions(directory, companions)

        arguments := "\"" + EdbProbe.CliPath() + "\" check --project \"" + directory + "\" --text"

        // `DotnetRunner` in the compiler assembly does exactly this and cannot be called: a
        // cross-assembly static returning a user class DECLINES on the columnar emit path. `Process`
        // itself crosses, so the contract spawns the CLI directly rather than routing through it.
        startInfo := new ProcessStartInfo("dotnet", arguments)
        startInfo.RedirectStandardOutput = true
        startInfo.RedirectStandardError = true
        startInfo.UseShellExecute = false
        process := new Process { StartInfo: startInfo }
        process.Start()

        // `nlc check --text` writes its DIAGNOSTICS TO STDERR and its summary to stdout — the Go and
        // Rust convention. Reading only stdout finds no diagnostics at all, and a contract that
        // reads nothing passes everything, so both streams are taken and joined.
        errorText := process.StandardError.ReadToEnd()
        standardText := process.StandardOutput.ReadToEnd()
        process.WaitForExit()
        process.Dispose()
        Directory.Delete(directory, true)
        return errorText + "\n" + standardText
    }
}

// One reported diagnostic, as the shipped renderer prints its header:
//     ── [NL104] ERROR ───────────────────────── Program.nl:1:1 ──
//
// Matched by its CONTENT — a bracketed code, a severity word, and the file position — rather than by
// the box-drawing rule it is padded with, so the match does not depend on how the child process's
// bytes survive the pipe.
func EdbHeaders(output: string): List<string> {
    headers := new List<string>()
    lines := output.Split('\n')
    i := 0
    while i < lines.Length {
        line := lines[i].Replace("\r", "")
        bracket := line.IndexOf("[", StringComparison.Ordinal)
        if bracket >= 0 && line.IndexOf("] ", StringComparison.Ordinal) > bracket && line.IndexOf("Program.nl:", StringComparison.Ordinal) > bracket {
            headers.Add(line.Substring(bracket))
        }

        i = i + 1
    }

    return headers
}

func EdbHeaderCode(header: string): string {
    stop := header.IndexOf("]", StringComparison.Ordinal)
    if stop <= 1 {
        return ""
    }

    return header.Substring(1, stop - 1)
}

func EdbHeaderSeverity(header: string): string {
    stop := header.IndexOf("]", StringComparison.Ordinal)
    if stop < 0 {
        return ""
    }

    rest := header.Substring(stop + 2)
    space := rest.IndexOf(" ", StringComparison.Ordinal)
    if space < 0 {
        return rest
    }

    return rest.Substring(0, space)
}

// The line number out of the trailing `Program.nl:<line>:<column>` of a header.
func EdbHeaderLine(header: string): int {
    marker := "Program.nl:"
    at := header.IndexOf(marker, StringComparison.Ordinal)
    if at < 0 {
        return 0
    }

    rest := header.Substring(at + marker.Length)
    digits := ""
    i := 0
    while i < rest.Length && char.IsDigit(rest[i]) {
        digits = digits + rest[i].ToString()
        i = i + 1
    }

    if digits.Length == 0 {
        return 0
    }

    return Int32.Parse(digits)
}

// One fenced block, with every `// ERROR <code>` it carries. `Marks` is the space-joined set of
// `<code>@<line>` the block claims — a block may mark several lines, and each one is held to its
// own claim.
class EdbExample {
    Page: string
    Source: string
    Companions: string
    Project: string
    Marks: string

    constructor(page: string, source: string, companions: string, project: string, marks: string) {
        Page = page
        Source = source
        Companions = companions
        Project = project
        Marks = marks
    }
}

// The filename a fence declares: ```` ```json title="hot-summaries.json" ```` -> hot-summaries.json.
// Empty for a plain fence.
func EdbFenceTitle(line: string): string {
    if !line.StartsWith("```", StringComparison.Ordinal) {
        return ""
    }

    marker := "title=\""
    at := line.IndexOf(marker, StringComparison.Ordinal)
    if at < 0 {
        return ""
    }

    rest := line.Substring(at + marker.Length)
    stop := rest.IndexOf("\"", StringComparison.Ordinal)
    if stop <= 0 {
        return ""
    }

    return rest.Substring(0, stop)
}

// Split the accumulated companion text back into files on its `// FILE <name>.nl` header lines and
// write each one. The header stays in the file it names, so the bytes on the page are the bytes on
// disk.
func EdbWriteCompanions(directory: string, companions: string) {
    if companions.Length == 0 {
        return
    }

    currentName := ""
    currentText := ""
    lines := companions.Split('\n')
    i := 0
    while i < lines.Length {
        line := lines[i]
        if line.StartsWith("// FILE ", StringComparison.Ordinal) {
            if currentName.Length > 0 {
                File.WriteAllText(Path.Combine(directory, currentName), currentText)
            }

            currentName = line.Substring(8).Trim()
            if currentName.EndsWith(".nl", StringComparison.Ordinal) {
                // An `.nl` companion keeps its `// FILE` line: it is a comment, it is what the page
                // shows, and every `// ERROR` line number on the page counts from it.
                currentText = line + "\n"
            } else {
                // Anything else was named by its fence and gets its bytes and nothing else.
                currentText = ""
            }
        } else {
            if currentName.Length > 0 {
                currentText = currentText + line + "\n"
            }
        }

        i = i + 1
    }

    if currentName.Length > 0 {
        File.WriteAllText(Path.Combine(directory, currentName), currentText)
    }
}

// The marker is the house style the first five pages already used: the offending line of an `n#`
// block ends `// ERROR <code>`. Exactly one marked line per block, and the block is the program.
func EdbExamplesOnPage(pageCode: string, examples: List<EdbExample>) {
    text := File.ReadAllText(EdcPaths.PageFor(pageCode)).Replace("\r", "")
    lines := text.Split('\n')
    inBlock := false
    block := new List<string>()
    pendingCompanions := ""
    pendingProject := ""
    inProject := false
    titledName := ""
    projectBlock := new List<string>()
    i := 0
    while i < lines.Length {
        line := lines[i]
        if inBlock {
            if line.StartsWith("```", StringComparison.Ordinal) {
                inBlock = false
                marks := ""
                j := 0
                while j < block.Count {
                    at := block[j].IndexOf("// ERROR ", StringComparison.Ordinal)
                    if at >= 0 {
                        codes := EdbMarkedCodes(block[j].Substring(at + 9))
                        k := 0
                        while k < codes.Count {
                            if marks.Length > 0 {
                                marks = marks + " "
                            }

                            marks = marks + codes[k] + "@" + (j + 1).ToString()
                            k = k + 1
                        }
                    }

                    j = j + 1
                }

                blockText := EdcJoinLines(block)
                isCompanion := block.Count > 0 && block[0].StartsWith("// FILE ", StringComparison.Ordinal) && !block[0].StartsWith("// FILE Program.nl", StringComparison.Ordinal)
                if isCompanion {
                    // A further file for the NEXT completing block on this page.
                    pendingCompanions = pendingCompanions + blockText
                } else {
                    if marks.Length > 0 {
                        examples.Add(new EdbExample(pageCode, blockText, pendingCompanions, pendingProject, marks))
                    }

                    pendingCompanions = ""
                }

                block = new List<string>()
            } else {
                block.Add(line)
            }
        } else {
            if inProject {
                if line.StartsWith("```", StringComparison.Ordinal) {
                    inProject = false
                    blockBytes := EdcJoinLines(projectBlock)
                    if titledName == "project.yml" {
                        pendingProject = blockBytes
                    } else {
                        pendingCompanions = pendingCompanions + "// FILE " + titledName + "\n" + blockBytes
                    }

                    projectBlock = new List<string>()
                    titledName = ""
                } else {
                    projectBlock.Add(line)
                }
            } else {
                if line.StartsWith("```n#", StringComparison.Ordinal) {
                    inBlock = true
                    block = new List<string>()
                } else {
                    named := EdbFenceTitle(line)
                    if named.Length > 0 {
                        inProject = true
                        titledName = named
                        projectBlock = new List<string>()
                    }
                }
            }
        }

        i = i + 1
    }
}

// The codes a `// ERROR …` marker claims for its line.
//
// `NL324: does not implement …`  -> NL324          (prose after a colon is ignored)
// `NL006, NL312`                 -> NL006, NL312   (a line that genuinely reports both)
//
// The comma form is not a convenience. Some rules CANNOT be reported alone: the linter's
// terminator test is a strict subset of the analyzer's, so every NL006 co-fires with NL312 at the
// same line. Without this, such a code could only be documented by pretending its example is clean
// or by exempting a rule that is fully enforced — both worse than saying what actually happens.
func EdbMarkedCodes(tail: string): List<string> {
    codes := new List<string>()
    head := tail
    colon := head.IndexOf(":", StringComparison.Ordinal)
    if colon >= 0 {
        head = head.Substring(0, colon)
    }

    parts := head.Split(',')
    i := 0
    while i < parts.Length {
        candidate := parts[i].Trim()
        if EdbLooksLikeCode(candidate) {
            codes.Add(candidate)
        }

        i = i + 1
    }

    return codes
}

// `NL006` or `NSYS010`: letters then digits, nothing else.
func EdbLooksLikeCode(value: string): bool {
    if value.Length < 3 {
        return false
    }

    digits := 0
    i := 0
    while i < value.Length {
        c := value[i]
        if char.IsDigit(c) {
            digits = digits + 1
        } else {
            if !char.IsLetter(c) || digits > 0 {
                return false
            }
        }

        i = i + 1
    }

    return digits > 0
}

func EdcJoinLines(lines: List<string>): string {
    joined := ""
    i := 0
    while i < lines.Count {
        joined = joined + lines[i] + "\n"
        i = i + 1
    }

    return joined
}

func EdbAllExamples(): List<EdbExample> {
    examples := new List<EdbExample>()
    pages := EdcPageCodes()
    i := 0
    while i < pages.Count {
        EdbExamplesOnPage(pages[i], examples)
        i = i + 1
    }

    return examples
}

// Every way one published example can be wrong, in one sentence each.
func EdbBrokenExamples(): string {
    broken := new List<string>()
    examples := EdbAllExamples()
    i := 0
    while i < examples.Count {
        example := examples[i]
        label := example.Page + "#" + (i + 1).ToString()
        marks := EdbSplitMarks(example.Marks)
        reported := new List<string>()
        headers := EdbHeaders(EdbProbe.Check("page" + i.ToString(), example.Source, example.Companions, example.Project))
        j := 0
        while j < headers.Count {
            header := headers[j]
            claim := EdbHeaderCode(header) + "@" + EdbHeaderLine(header).ToString()
            if !EdcContains(reported, claim) {
                reported.Add(claim)
            }

            // A diagnostic that stops a build and is not one the page claims makes the example
            // teach something it does not say. Warnings and info are allowed to appear unclaimed.
            if EdbHeaderSeverity(header) == "ERROR" && !EdcContains(marks, claim) {
                broken.Add(label + ":unclaimed-" + claim)
            }

            j = j + 1
        }

        j = 0
        while j < marks.Count {
            if !EdcContains(reported, marks[j]) {
                broken.Add(label + ":claimed-" + marks[j] + "-was-not-reported")
            }

            j = j + 1
        }

        i = i + 1
    }

    return EdcJoin(broken)
}

func EdbSplitMarks(marks: string): List<string> {
    values := new List<string>()
    parts := marks.Split(' ')
    i := 0
    while i < parts.Length {
        if parts[i].Length > 0 {
            values.Add(parts[i])
        }

        i = i + 1
    }

    return values
}

// ─── the exemption list, held to its own claim ────────────────────────────────────────────────
//
// Each exempt code names a program that is SILENT today. These are those programs. If one of them
// ever reports its code, the rule has been implemented — and the exemption has to go, replaced by
// a page, which is exactly what this contract forces. A hole cannot be closed quietly.
func EdbExemptPrograms(): List<string> {
    programs := new List<string>()
    programs.Add("NL204|func Widen(): string {\n    v := 42\n    return v as string ?? \"\"\n}\n")
    programs.Add("NL307|class A : B {\n}\n\nclass B : A {\n}\n")
    programs.Add("NL502|func Classify(n: int): string {\n    return match n {\n        _ => \"any\",\n        1 => \"one\"\n    }\n}\n")
    programs.Add("NL801|class Left {\n}\n\nclass Right {\n}\n\nclass Both : Left, Right {\n}\n")
    programs.Add("NL802|sealed class Base {\n}\n\nclass Derived : Base {\n}\n")
    programs.Add("NL806|class Point {\n    X: int\n\n    constructor(x: int) {\n        X = x\n    }\n}\n\nfunc Make(): Point {\n    return new Point(1, 2)\n}\n")
    return programs
}

func EdbExemptionsThatNowReport(): string {
    landed := new List<string>()
    programs := EdbExemptPrograms()
    i := 0
    while i < programs.Count {
        row := programs[i]
        separator := row.IndexOf("|", StringComparison.Ordinal)
        code := row.Substring(0, separator)
        source := row.Substring(separator + 1)
        headers := EdbHeaders(EdbProbe.Check("exempt" + i.ToString(), source, "", ""))
        j := 0
        while j < headers.Count {
            if EdbHeaderCode(headers[j]) == code {
                landed.Add(code + ":IS-NOW-REPORTED-so-write-its-page-and-delete-the-exemption")
            }

            j = j + 1
        }

        i = i + 1
    }

    return EdcJoin(landed)
}

// Every exemption row must have a program here, and every program an exemption row.
func EdbExemptionProgramMismatch(): string {
    mismatched := new List<string>()
    exemptCodes := EdcExemptCodes()
    programs := EdbExemptPrograms()
    programCodes := new List<string>()
    i := 0
    while i < programs.Count {
        programCodes.Add(programs[i].Substring(0, programs[i].IndexOf("|", StringComparison.Ordinal)))
        i = i + 1
    }

    i = 0
    while i < exemptCodes.Count {
        if !EdcContains(programCodes, exemptCodes[i]) {
            mismatched.Add(exemptCodes[i] + ":exempt-with-no-probe-program")
        }

        i = i + 1
    }

    i = 0
    while i < programCodes.Count {
        if !EdcContains(exemptCodes, programCodes[i]) {
            mismatched.Add(programCodes[i] + ":probe-program-with-no-exemption")
        }

        i = i + 1
    }

    return EdcJoin(mismatched)
}

// ─── contract B ───────────────────────────────────────────────────────────────────────────────

test "the built CLI this contract runs the examples through is present" {
    assert File.Exists(EdbProbe.CliPath()), EdbProbe.CliPath()
}

test "EVERY marked example on EVERY page reports its own code, at its own line, and nothing else" {
    assert EdbBrokenExamples() == "", EdbBrokenExamples()
}

test "EVERY page carrying a code has at least one runnable marked example" {
    missing := new List<string>()
    examples := EdbAllExamples()
    pages := EdcPageCodes()
    i := 0
    while i < pages.Count {
        found := false
        j := 0
        while j < examples.Count {
            if examples[j].Page == pages[i] && examples[j].Marks.Contains(pages[i] + "@") {
                found = true
            }

            j = j + 1
        }

        if !found {
            missing.Add(pages[i])
        }

        i = i + 1
    }

    assert EdcJoin(missing) == "", EdcJoin(missing)
}

test "EVERY exempt code is STILL unenforced, so a landed rule cannot hide behind its exemption" {
    assert EdbExemptionProgramMismatch() == "", EdbExemptionProgramMismatch()
    assert EdbExemptionsThatNowReport() == "", EdbExemptionsThatNowReport()
}
