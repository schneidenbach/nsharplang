namespace NSharpLang.ErrorDocsContract.Tests

import System
import System.Collections.Generic
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
// SEVEN CODES ARE EXEMPT FROM THE PAGE REQUIREMENT, AND EACH ONE IS A HOLE IN THE LANGUAGE, NOT A
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
    rows.Add("NL803|systems-language-closeout/STATUS.md|`new Shape()` on an `abstract class Shape` is accepted in silence; only the unused local is reported, by the linter.")
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
    assert EdcExemptions().Count == 7
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
