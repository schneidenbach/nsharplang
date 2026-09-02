namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast

// CONTRACTS FOR THE LINTER CONFIGURATION (020 slice 8).
//
// These came out of `tests/LinterTests.cs`, which is deleted. That file asked four questions of the
// configuration: the ten default severities, one override through the `RuleSeverities` indexer, one
// end-to-end proof that `Linter` honours the override, and one `.editorconfig` with
// `severity = none`.
//
// THE FOUR SURVIVE HERE AND THE SURFACE AROUND THEM IS CROSSED. The deleted file never asked
// whether a rule code is matched case-insensitively (it is — every entry point normalizes through
// `NormalizeRuleCode`), whether an unknown code falls back to the CATALOG rather than to a constant,
// whether `.editorconfig` can RAISE a severity as well as silence a rule, or whether `root = true`
// stops the upward walk. Each of those is a real configuration a user can write, and each was
// unasserted.
//
// THE `.editorconfig` ARMS ARE ASSERTED ON DISK, not on a parsed structure, because
// `FromEditorConfig` walks real directories and the walk is half the behaviour.
func LcfLint(config: LinterConfig, sourceText: string, filePath: string): List<Diagnostic> {
    parsed := ColumnarParserRecovery.ParseFileAst(sourceText, null)
    unit := parsed.CompilationUnit
    if unit != null {
        linter := new Linter(config)
        return linter.Lint(unit, filePath, null)
    }

    // Never an empty list: a silent parse failure would turn every "no diagnostic" contract below
    // into a contract about nothing. The C# hid this behind `!`.
    throw new InvalidOperationException("the parser answered no compilation unit for: " + sourceText)
}

func LcfCountOf(diagnostics: List<Diagnostic>, code: string): int {
    total := 0
    for diagnostic in diagnostics {
        if diagnostic.Code == code {
            total = total + 1
        }
    }

    return total
}

func LcfFirstOf(diagnostics: List<Diagnostic>, code: string): Diagnostic? {
    for diagnostic in diagnostics {
        if diagnostic.Code == code {
            return diagnostic
        }
    }

    return null
}

func LcfRuleCodes(): List<string> {
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

func LcfTempDirectory(tag: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-linter-config-" + tag + "-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    return directory
}

// ── the defaults ──────────────────────────────────────────────────────────────────────────────

test "the default config is an ERROR for every one of the ten lint rules" {
    config := LinterConfig.Default()
    codes := LcfRuleCodes()
    assert codes.Count == 10

    for code in codes {
        assert config.GetSeverity(code) == DiagnosticSeverity.Error
        assert config.IsRuleEnabled(code)
    }
}

test "the default config is seeded FROM the catalog, so it carries exactly the linter rows" {
    config := LinterConfig.Default()
    assert config.RuleSeverities.Count == 10
    assert config.DisabledRules.Count == 0

    for code in LcfRuleCodes() {
        assert config.RuleSeverities.ContainsKey(code)
    }
}

test "a rule code is matched case-insensitively, and an unknown code falls back to the CATALOG" {
    config := LinterConfig.Default()
    assert config.GetSeverity("nl001") == DiagnosticSeverity.Error
    assert config.GetSeverity("Nl010") == DiagnosticSeverity.Error
    assert config.IsRuleEnabled("nl001")

    // Not in the config's own table: the answer comes from the catalog, and for a code that is in
    // neither the answer is the catalog's own fallback.
    assert config.GetSeverity("NL951") == DiagnosticSeverity.Warning
    assert config.GetSeverity("NL109") == DiagnosticSeverity.Error
    assert config.GetSeverity("NL9999") == DiagnosticSeverity.Warning
}

// ── the override ──────────────────────────────────────────────────────────────────────────────

test "a severity written through the RuleSeverities indexer is the severity read back" {
    config := LinterConfig.Default()
    config.RuleSeverities["NL001"] = LinterConfig.SeverityObject(DiagnosticSeverity.Error)
    assert config.GetSeverity("NL001") == DiagnosticSeverity.Error

    config.RuleSeverities["NL001"] = LinterConfig.SeverityObject(DiagnosticSeverity.Warning)
    assert config.GetSeverity("NL001") == DiagnosticSeverity.Warning

    config.RuleSeverities["NL001"] = LinterConfig.SeverityObject(DiagnosticSeverity.Info)
    assert config.GetSeverity("NL001") == DiagnosticSeverity.Info
}

test "THE LINTER STAMPS THE CONFIGURED SEVERITY ONTO THE DIAGNOSTIC IT REPORTS" {
    // The end-to-end half: a config that nothing reads is a config that does nothing.
    config := LinterConfig.Default()
    config.RuleSeverities["NL001"] = LinterConfig.SeverityObject(DiagnosticSeverity.Error)
    reported := LcfFirstOf(LcfLint(config, "func main() { x := 5 }", "test.nl"), "NL001")
    assert reported != null
    if reported != null {
        assert reported.Severity == DiagnosticSeverity.Error
    }

    // Non-vacuity for the stamp: lowered to a warning, the SAME source reports the same rule at the
    // lower severity rather than falling silent.
    lowered := LinterConfig.Default()
    lowered.RuleSeverities["NL001"] = LinterConfig.SeverityObject(DiagnosticSeverity.Warning)
    warned := LcfFirstOf(LcfLint(lowered, "func main() { x := 5 }", "test.nl"), "NL001")
    assert warned != null
    if warned != null {
        assert warned.Severity == DiagnosticSeverity.Warning
    }
}

// ── the disabled-rule list ────────────────────────────────────────────────────────────────────

test "a disabled rule is added once, matched case-insensitively, and removable" {
    config := LinterConfig.Default()
    assert config.IsRuleEnabled("NL001")

    config.AddDisabledRule("NL001")
    assert !config.IsRuleEnabled("NL001")
    assert config.HasDisabledRule("nl001")
    assert config.DisabledRules.Count == 1

    // Adding it again is not a second row.
    config.AddDisabledRule("nl001")
    assert config.DisabledRules.Count == 1

    config.RemoveDisabledRule("nl001")
    assert config.IsRuleEnabled("NL001")
    assert config.DisabledRules.Count == 0
}

test "the severity keyword table, on every keyword it accepts and one it does not" {
    severity := DiagnosticSeverity.Warning
    assert LinterConfig.TryParseSeverity("error", out severity)
    assert severity == DiagnosticSeverity.Error
    assert LinterConfig.TryParseSeverity("ERROR", out severity)
    assert severity == DiagnosticSeverity.Error
    assert LinterConfig.TryParseSeverity("warning", out severity)
    assert severity == DiagnosticSeverity.Warning
    assert LinterConfig.TryParseSeverity("info", out severity)
    assert severity == DiagnosticSeverity.Info
    assert LinterConfig.TryParseSeverity("suggestion", out severity)
    assert severity == DiagnosticSeverity.Info
    assert !LinterConfig.TryParseSeverity("none", out severity)
    assert !LinterConfig.TryParseSeverity("silent", out severity)
    assert !LinterConfig.TryParseSeverity("shout", out severity)

    // `none` and `silent` are not severities at all — they are the disable keywords.
    assert LinterConfig.IsDisabledSeverity("none")
    assert LinterConfig.IsDisabledSeverity("SILENT")
    assert !LinterConfig.IsDisabledSeverity("error")

    assert LinterConfig.NormalizeRuleCode("nl001") == "NL001"
    assert LinterConfig.NormalizeRuleCode("NL001") == "NL001"
}

// ── the case fold is INVARIANT, not the machine's ──────────────────────────────────────────────
//
// MEASURED, NOT ASSUMED: before this fix the block ABOVE failed under `LC_ALL=tr_TR.UTF-8`, on its
// `IsDisabledSeverity("SILENT")` row alone — a Turkish `.ToLower()` sends `I` to the DOTLESS
// lowercase i, so `SILENT` folded to a word that is not `silent`, matched neither disable keyword,
// and the rule the user disabled stayed ON. The rows below state the same fact deliberately: every
// keyword in this table is fixed ASCII, so the fold that recognises it may not consult the culture.
// They answer identically under en-US, de-DE and tr-TR, and the tr-TR run is what makes them
// non-vacuous.

test "the severity keywords fold INVARIANTLY, so a config parses the same on every machine" {
    severity := DiagnosticSeverity.Warning

    // Every capital-I spelling a user may type. Under a Turkish fold each of these folded to a
    // dotless i and stopped being a keyword.
    assert LinterConfig.TryParseSeverity("INFO", out severity)
    assert severity == DiagnosticSeverity.Info
    assert LinterConfig.TryParseSeverity("Info", out severity)
    assert severity == DiagnosticSeverity.Info
    assert LinterConfig.TryParseSeverity("SUGGESTION", out severity)
    assert severity == DiagnosticSeverity.Info
    assert LinterConfig.TryParseSeverity("WARNING", out severity)
    assert severity == DiagnosticSeverity.Warning

    // `SILENT` is the row the tr-TR run caught, and `NONE` is its partner.
    assert LinterConfig.IsDisabledSeverity("SILENT")
    assert LinterConfig.IsDisabledSeverity("Silent")
    assert LinterConfig.IsDisabledSeverity("NONE")

    // A word that is NOT a keyword stays not a keyword, so the fold widened nothing.
    assert !LinterConfig.TryParseSeverity("SHOUT", out severity)
    assert !LinterConfig.IsDisabledSeverity("ERROR")

    // A rule code is the dictionary KEY every severity lookup uses, so its fold is invariant too.
    assert LinterConfig.NormalizeRuleCode("ni001") == "NI001"
    assert LinterConfig.NormalizeRuleCode("nl001") == "NL001"
}

test "AN .editorconfig SEVERITY WRITTEN IN CAPITALS IS THE SEVERITY THE LINTER STAMPS" {
    // The end-to-end half, and the shape a user actually types. Under a Turkish culture the old
    // fold made `= INFO` match no keyword and no disable keyword either, so the line was dropped
    // SILENTLY and NL001 kept its default Error severity — a config the machine's locale decided.
    directory := LcfTempDirectory("invariant-severity")
    File.WriteAllText(Path.Combine(directory, ".editorconfig"), "root = true\n\n[*.nl]\ndotnet_diagnostic.NL001.severity = INFO\ndotnet_diagnostic.NL012.severity = SILENT\n")

    config := LinterConfig.FromEditorConfig(directory)
    assert config.GetSeverity("NL001") == DiagnosticSeverity.Info
    assert config.IsRuleEnabled("NL001")

    reported := LcfFirstOf(LcfLint(config, "func main() { x := 5 }", Path.Combine(directory, "test.nl")), "NL001")
    assert reported != null
    if reported != null {
        assert reported.Severity == DiagnosticSeverity.Info
    }

    // `SILENT` in capitals disables, which is the row that was measured red under tr-TR.
    assert !config.IsRuleEnabled("NL012")

    Directory.Delete(directory, true)
}

// ── .editorconfig, on disk ────────────────────────────────────────────────────────────────────

test "AN .editorconfig `none` DISABLES THE RULE, AND THE LINTER GOES SILENT" {
    directory := LcfTempDirectory("none")
    File.WriteAllText(Path.Combine(directory, ".editorconfig"), "root = true\n\n[*.nl]\ndotnet_diagnostic.NL001.severity = none")

    config := LinterConfig.FromEditorConfig(directory)
    assert !config.IsRuleEnabled("NL001")
    assert !config.RuleSeverities.ContainsKey("NL001")
    assert LcfCountOf(LcfLint(config, "func main() { x := 5 }", Path.Combine(directory, "test.nl")), "NL001") == 0

    // Non-vacuity: the rule NEXT to it is untouched, so the file disabled one rule and not linting.
    assert config.IsRuleEnabled("NL012")
    assert config.GetSeverity("NL012") == DiagnosticSeverity.Error

    Directory.Delete(directory, true)
}

test "an .editorconfig can also SET a severity, which is the arm `none` never reaches" {
    directory := LcfTempDirectory("severity")
    File.WriteAllText(Path.Combine(directory, ".editorconfig"), "root = true\n\n[*.nl]\ndotnet_diagnostic.NL001.severity = warning\ndotnet_diagnostic.nl012.severity = info\n")

    config := LinterConfig.FromEditorConfig(directory)
    assert config.GetSeverity("NL001") == DiagnosticSeverity.Warning
    // The key is lower-cased in the file and still lands on the normalized rule code.
    assert config.GetSeverity("NL012") == DiagnosticSeverity.Info
    assert config.IsRuleEnabled("NL001")

    reported := LcfFirstOf(LcfLint(config, "func main() { x := 5 }", Path.Combine(directory, "test.nl")), "NL001")
    assert reported != null
    if reported != null {
        assert reported.Severity == DiagnosticSeverity.Warning
    }

    Directory.Delete(directory, true)
}

test "the walk climbs to the PARENT directory, and `root = true` is where it stops" {
    parentDirectory := LcfTempDirectory("root")
    childDirectory := Path.Combine(parentDirectory, "child")
    Directory.CreateDirectory(childDirectory)

    File.WriteAllText(Path.Combine(parentDirectory, ".editorconfig"), "root = true\n\n[*.nl]\ndotnet_diagnostic.NL002.severity = info\n")

    // No .editorconfig in the child at all: the parent's settings are the ones that apply.
    inherited := LinterConfig.FromEditorConfig(childDirectory)
    assert inherited.GetSeverity("NL002") == DiagnosticSeverity.Info

    // Now the child declares itself the root. The walk stops there and the parent is never read.
    File.WriteAllText(Path.Combine(childDirectory, ".editorconfig"), "root = true\n\n[*.nl]\ndotnet_diagnostic.NL001.severity = warning\n")
    stopped := LinterConfig.FromEditorConfig(childDirectory)
    assert stopped.GetSeverity("NL001") == DiagnosticSeverity.Warning
    assert stopped.GetSeverity("NL002") == DiagnosticSeverity.Error

    Directory.Delete(parentDirectory, true)
}

test "a section that is not the N# one is ignored" {
    directory := LcfTempDirectory("section")
    File.WriteAllText(Path.Combine(directory, ".editorconfig"), "root = true\n\n[*.cs]\ndotnet_diagnostic.NL001.severity = none\n")

    config := LinterConfig.FromEditorConfig(directory)
    assert config.IsRuleEnabled("NL001")
    assert config.GetSeverity("NL001") == DiagnosticSeverity.Error

    Directory.Delete(directory, true)
}
