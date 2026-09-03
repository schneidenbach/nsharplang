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

// Every catalog code with no `website/docs/errors/<code>.md`.
func EdcCodesWithoutPage(): string {
    missing := new List<string>()
    codes := EdcCatalogCodes()
    i := 0
    while i < codes.Count {
        if !File.Exists(EdcPaths.PageFor(codes[i])) {
            missing.Add(codes[i])
        }

        i = i + 1
    }

    return EdcJoin(missing)
}

// Every page whose name is not a code the catalog publishes.
func EdcPagesWithoutCode(): string {
    catalogCodes := EdcCatalogCodes()
    orphans := new List<string>()
    pageCodes := EdcPageCodes()
    i := 0
    while i < pageCodes.Count {
        if !EdcContains(catalogCodes, pageCodes[i]) {
            orphans.Add(pageCodes[i])
        }

        i = i + 1
    }

    return EdcJoin(orphans)
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

test "EVERY page under website/docs/errors names a code the catalog publishes" {
    assert EdcPagesWithoutCode() == "", EdcPagesWithoutCode()
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
