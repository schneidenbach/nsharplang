namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// CONTRACTS FOR THE DIAGNOSTIC CATALOG (020 slice 8).
//
// These came out of `tests/LinterTests.cs`, which is deleted. That file was the catalog's ONLY
// assertion layer anywhere in the repo, and it SAMPLED it: one syntax row (NL109), three lint rows
// (NL001 / NL006 / NL010), the five performance rows, one duplicate census and one `NLM` sweep —
// nine of the 99 descriptors, and only two of the four BUILDERS that produce them.
//
// THE SAMPLE IS REPLACED BY THE CROSS. Every descriptor the catalog publishes is walked, and the
// four builders are asserted as a PARTITION: 80 compiler + 5 performance + 4 AOT + 10 linter, no
// row belonging to two builders and no row belonging to none. A rule added to
// `AddLinterRuleDescriptors` and forgotten in the partition guard now FAILS a contract instead of
// passing unnoticed — which is the property the deleted file's duplicate census could not have,
// because a census only sees the rows that are already there.
//
// AND IT REACHES AN ARM THE C# NEVER DID. `DocsUrlFor` has two: a stored `DocsUrl` and the
// synthesized fallback. Only the four AOT descriptors carry a stored URL, and the deleted file
// asserted the fallback on a code that is not in the catalog at all — so the arm that RETURNS the
// stored value was never executed by any test. It is asserted here on all four.
func DctAllDescriptors(): List<DiagnosticDescriptor> {
    descriptors := new List<DiagnosticDescriptor>()
    for descriptorValue in DiagnosticCatalog.Descriptors {
        descriptor := descriptorValue as DiagnosticDescriptor
        if descriptor != null {
            descriptors.Add(descriptor)
        }
    }

    return descriptors
}

func DctLinterOnly(): List<DiagnosticDescriptor> {
    descriptors := new List<DiagnosticDescriptor>()
    for descriptorValue in DiagnosticCatalog.LinterDescriptors {
        descriptor := descriptorValue as DiagnosticDescriptor
        if descriptor != null {
            descriptors.Add(descriptor)
        }
    }

    return descriptors
}

func DctFind(code: string): DiagnosticDescriptor? {
    descriptor := DiagnosticCatalog.EmptyDescriptor()
    if DiagnosticCatalog.TryGetDescriptor(code, out descriptor) {
        return descriptor
    }

    return null
}

func DctCodes(): List<string> {
    codes := new List<string>()
    for descriptor in DctAllDescriptors() {
        codes.Add(descriptor.Code)
    }

    return codes
}

func DctCountBySource(source: DiagnosticSource): int {
    total := 0
    for descriptor in DctAllDescriptors() {
        if descriptor.Source == source {
            total = total + 1
        }
    }

    return total
}

func DctCountByCategory(category: DiagnosticCategory): int {
    total := 0
    for descriptor in DctAllDescriptors() {
        if descriptor.Category == category {
            total = total + 1
        }
    }

    return total
}

func DctLinterRuleCodes(): List<string> {
    codes := new List<string>()
    codes.Add("NL001")
    codes.Add("NL002")
    codes.Add("NL003")
    codes.Add("NL004")
    codes.Add("NL006")
    codes.Add("NL010")
    codes.Add("NL011")
    codes.Add("NL012")
    codes.Add("NL016")
    codes.Add("NL020")
    return codes
}

func DctPerformanceCodes(): List<string> {
    codes := new List<string>()
    codes.Add("NL950")
    codes.Add("NL951")
    codes.Add("NL952")
    codes.Add("NL953")
    codes.Add("NL954")
    return codes
}

func DctAotCodes(): List<string> {
    codes := new List<string>()
    codes.Add("NL960")
    codes.Add("NL961")
    codes.Add("NL962")
    codes.Add("NL963")
    return codes
}

func DctIsDigits(value: string): bool {
    if value.Length == 0 {
        return false
    }

    i := 0
    while i < value.Length {
        if !char.IsDigit(value[i]) {
            return false
        }

        i = i + 1
    }

    return true
}

// ── the row the deleted file opened on ────────────────────────────────────────────────────────

test "NL109 is a build-blocking compiler SYNTAX error" {
    descriptor := DiagnosticCatalog.EmptyDescriptor()
    assert DiagnosticCatalog.TryGetDescriptor("NL109", out descriptor)
    assert descriptor.Source == DiagnosticSource.Compiler
    assert descriptor.Category == DiagnosticCategory.Syntax
    assert descriptor.DefaultSeverity == DiagnosticSeverity.Error
    assert descriptor.BlocksBuildByDefault
    // The title comes from the enum member name through `ToTitle`, which is the only place the
    // catalog turns an identifier into prose. The C# never looked at it.
    assert descriptor.Title == "Reserved Keyword As Name"
}

// ── the docs URL, on BOTH its arms ────────────────────────────────────────────────────────────

test "DocsUrlFor SYNTHESIZES a public docs URL for a code with no stored one" {
    assert DiagnosticCatalog.DocsUrlFor("NL9999") == "https://schneidenbach.github.io/nsharplang/docs/errors/NL9999"
    // The fallback is not reserved for codes outside the catalog: every compiler and lint row is
    // registered WITHOUT a DocsUrl, so they take the same arm.
    assert DiagnosticCatalog.DocsUrlFor("NL001") == "https://schneidenbach.github.io/nsharplang/docs/errors/NL001"
    assert DiagnosticCatalog.DocsUrlFor("NL109") == "https://schneidenbach.github.io/nsharplang/docs/errors/NL109"
    assert DiagnosticCatalog.DocsUrlFor("NL951") == "https://schneidenbach.github.io/nsharplang/docs/errors/NL951"
}

test "DocsUrlFor RETURNS THE STORED URL where one exists — the arm no C# test reached" {
    for code in DctAotCodes() {
        descriptor := DctFind(code)
        assert descriptor != null
        if descriptor != null {
            assert descriptor.DocsUrl == "https://schneidenbach.github.io/nsharplang/docs/errors/" + code
            assert DiagnosticCatalog.DocsUrlFor(code) == "https://schneidenbach.github.io/nsharplang/docs/errors/" + code
        }
    }
}

// ── the whole catalog, as a partition ─────────────────────────────────────────────────────────

test "EVERY code is distinct, and the catalog is exactly its four builders" {
    codes := DctCodes()
    assert codes.Count == 101

    duplicates := 0
    outer := 0
    while outer < codes.Count {
        inner := outer + 1
        while inner < codes.Count {
            if codes[outer] == codes[inner] {
                duplicates = duplicates + 1
            }

            inner = inner + 1
        }

        outer = outer + 1
    }

    assert duplicates == 0

    // The four builders, counted where they are OBSERVABLE: the linter rows are the ones sourced
    // to the linter, the performance and AOT rows are the ones in their own categories, and the
    // rest are the compiler's. 82 + 5 + 4 + 10 = 101, so nothing is uncounted or double-counted.
    linterRows := DctCountBySource(DiagnosticSource.Linter)
    performanceRows := DctCountByCategory(DiagnosticCategory.Performance)
    aotRows := DctCountByCategory(DiagnosticCategory.Aot)
    compilerRows := DctCountBySource(DiagnosticSource.Compiler) - performanceRows - aotRows
    assert linterRows == 10
    assert performanceRows == 5
    assert aotRows == 4
    assert compilerRows == 82
    assert compilerRows + performanceRows + aotRows + linterRows == codes.Count
}

test "EVERY code is well formed: 'NL' and at least three digits, and never a migration code" {
    for code in DctCodes() {
        assert code.StartsWith("NL", StringComparison.Ordinal)
        assert !code.StartsWith("NLM", StringComparison.Ordinal)
        assert code.Length >= 5
        assert DctIsDigits(code.Substring(2))
    }
}

test "EVERY descriptor carries a title, and TryGetDescriptor finds every one of them" {
    for descriptor in DctAllDescriptors() {
        assert !String.IsNullOrWhiteSpace(descriptor.Title)
        found := DctFind(descriptor.Code)
        assert found != null
        if found != null {
            assert found.Code == descriptor.Code
            assert found.Title == descriptor.Title
            assert found.DefaultSeverity == descriptor.DefaultSeverity
        }
    }
}

test "LinterDescriptors is EXACTLY the linter-sourced subset of Descriptors" {
    linterDescriptors := DctLinterOnly()
    assert linterDescriptors.Count == 10

    for descriptor in linterDescriptors {
        assert descriptor.Source == DiagnosticSource.Linter
    }

    // …and nothing sourced to the linter is missing from it.
    seen := 0
    for descriptor in DctAllDescriptors() {
        if descriptor.Source == DiagnosticSource.Linter {
            matched := false
            for linterDescriptor in linterDescriptors {
                if linterDescriptor.Code == descriptor.Code {
                    matched = true
                }
            }

            assert matched
            seen = seen + 1
        }
    }

    assert seen == linterDescriptors.Count
}

// ── the lint rules, crossed where the C# sampled three ────────────────────────────────────────

test "ALL TEN lint rules are build-blocking errors sourced to the linter" {
    codes := DctLinterRuleCodes()
    assert codes.Count == 10

    for code in codes {
        descriptor := DctFind(code)
        assert descriptor != null
        if descriptor != null {
            assert descriptor.Source == DiagnosticSource.Linter
            assert descriptor.DefaultSeverity == DiagnosticSeverity.Error
            assert descriptor.BlocksBuildByDefault
            assert descriptor.IsConfigurable
            assert !String.IsNullOrWhiteSpace(descriptor.Title)
            assert DiagnosticCatalog.GetDefaultSeverity(code) == DiagnosticSeverity.Error
        }
    }
}

test "each lint rule's TITLE and CATEGORY are the ones the catalog publishes" {
    titles := new List<string>()
    titles.Add("Unused variable")
    titles.Add("Missing import")
    titles.Add("Unnecessary null check")
    titles.Add("Async without await")
    titles.Add("Unreachable code")
    titles.Add("Unused import")
    titles.Add("Empty catch")
    titles.Add("Unused parameter")
    titles.Add("Redundant null check")
    titles.Add("Shadowed variable")

    codes := DctLinterRuleCodes()
    i := 0
    while i < codes.Count {
        descriptor := DctFind(codes[i])
        assert descriptor != null
        if descriptor != null {
            assert descriptor.Title == titles[i]
        }

        i = i + 1
    }

    // NL002 and NL010 are the import rules; NL006 is semantic; the other seven are hygiene.
    importDescriptor := DctFind("NL002")
    unusedImportDescriptor := DctFind("NL010")
    unreachableDescriptor := DctFind("NL006")
    unusedVariableDescriptor := DctFind("NL001")
    assert importDescriptor != null
    assert unusedImportDescriptor != null
    assert unreachableDescriptor != null
    assert unusedVariableDescriptor != null
    if importDescriptor != null {
        assert importDescriptor.Category == DiagnosticCategory.Import
    }

    if unusedImportDescriptor != null {
        assert unusedImportDescriptor.Category == DiagnosticCategory.Import
    }

    if unreachableDescriptor != null {
        assert unreachableDescriptor.Category == DiagnosticCategory.Semantic
    }

    if unusedVariableDescriptor != null {
        assert unusedVariableDescriptor.Category == DiagnosticCategory.Hygiene
    }
}

// ── the performance rows ──────────────────────────────────────────────────────────────────────

test "the FIVE performance diagnostics are registered, advisory, and explained" {
    titles := new List<string>()
    titles.Add("Allocation here")
    titles.Add("Boxing here")
    titles.Add("Virtual dispatch not devirtualized")
    titles.Add("Closure allocation")
    titles.Add("Delegate allocation")

    severities := new List<DiagnosticSeverity>()
    severities.Add(DiagnosticSeverity.Info)
    severities.Add(DiagnosticSeverity.Warning)
    severities.Add(DiagnosticSeverity.Info)
    severities.Add(DiagnosticSeverity.Warning)
    severities.Add(DiagnosticSeverity.Warning)

    codes := DctPerformanceCodes()
    i := 0
    while i < codes.Count {
        descriptor := DiagnosticCatalog.EmptyDescriptor()
        assert DiagnosticCatalog.TryGetDescriptor(codes[i], out descriptor)
        assert descriptor.Title == titles[i]
        assert descriptor.Category == DiagnosticCategory.Performance
        assert descriptor.Source == DiagnosticSource.Compiler
        assert descriptor.DefaultSeverity == severities[i]
        assert !descriptor.BlocksBuildByDefault
        assert !String.IsNullOrWhiteSpace(descriptor.Explanation)
        i = i + 1
    }
}

// ── the AOT rows, which the C# never named at all ─────────────────────────────────────────────

test "the FOUR AOT diagnostics are advisory, explained, and the only rows with a stored docs URL" {
    for code in DctAotCodes() {
        descriptor := DctFind(code)
        assert descriptor != null
        if descriptor != null {
            assert descriptor.Category == DiagnosticCategory.Aot
            assert descriptor.Source == DiagnosticSource.Compiler
            assert descriptor.DefaultSeverity == DiagnosticSeverity.Info
            assert !descriptor.BlocksBuildByDefault
            assert descriptor.IsConfigurable
            assert !String.IsNullOrWhiteSpace(descriptor.Explanation)
        }
    }

    stored := 0
    for descriptor in DctAllDescriptors() {
        if descriptor.DocsUrl != null {
            stored = stored + 1
        }
    }

    assert stored == 4
}

// ── the misses ────────────────────────────────────────────────────────────────────────────────

test "an UNKNOWN code is not found, and the out parameter is left EMPTY rather than stale" {
    descriptor := DiagnosticCatalog.EmptyDescriptor()
    assert DiagnosticCatalog.TryGetDescriptor("NL001", out descriptor)
    assert descriptor.Code == "NL001"

    // The same variable, asked again for a code that does not exist: it must be overwritten with
    // the empty descriptor and not left holding NL001.
    assert !DiagnosticCatalog.TryGetDescriptor("NL9999", out descriptor)
    assert descriptor.Code == ""
    assert descriptor.Title == ""

    assert DiagnosticCatalog.GetDefaultSeverity("NL9999") == DiagnosticSeverity.Warning
    assert DiagnosticCatalog.GetDefaultSeverity("NL9999", DiagnosticSeverity.Error) == DiagnosticSeverity.Error
    // A code that IS in the catalog ignores the fallback.
    assert DiagnosticCatalog.GetDefaultSeverity("NL001", DiagnosticSeverity.Info) == DiagnosticSeverity.Error
}
