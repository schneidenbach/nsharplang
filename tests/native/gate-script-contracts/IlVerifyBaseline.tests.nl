namespace NSharpLang.GateScriptContracts.Tests

import System
import System.Collections.Generic
import System.IO

// ─── THE IL-VERIFICATION BASELINE, AND THE GATE STEP THAT READS IT ────────────────────────────
//
// Replaces `tests/PerfEvidence/IlVerifyBaselineEmptyTests.cs`. Both rows are shell-and-text
// contracts over gate files, which is what this project already owns.
//
// The blocking gate is `scripts/ilverify.sh`, which runs `dotnet ilverify` over every emitted
// assembly and diffs the findings against `scripts/ilverify-baseline.txt`. Every line in that
// baseline is an ALLOWLISTED — that is, known-bad — finding. After the IL-validity coverage sweep
// drove the file to zero findings, the first row pins it there: a new baselined finding is the only
// way unverifiable IL can land without failing the gate outright, so adding one has to fail here and
// be justified by editing this row deliberately.
func IlvBaselineFindings(): List<string> {
    baselinePath := Path.Combine(Path.Combine(RepositoryRoot(), "scripts"), "ilverify-baseline.txt")
    if !File.Exists(baselinePath) {
        throw new InvalidOperationException("ilverify baseline not found at " + baselinePath)
    }

    findings := new List<string>()
    for line in File.ReadAllLines(baselinePath) {
        trimmed := line.Trim()
        if trimmed.Length > 0 && !trimmed.StartsWith("#") {
            findings.Add(trimmed)
        }
    }

    return findings
}

test "the ilverify baseline allowlists zero findings, so no unverifiable IL ships" {
    findings := IlvBaselineFindings()

    // Every entry would be unverifiable IL the compiler emits today — fix the emitter rather than
    // allowlisting it. The joined text is asserted first so a failure names the offenders.
    assert string.Join("\n", findings) == ""
    assert findings.Count == 0
}

// The gate builds the example/template/fixture surface in its own steps and then hands the EXACT
// emitted directories to `scripts/ilverify.sh --built-dirs-file`, so the verification step never
// rebuilds what it verifies. Both halves of that handshake are pinned: the script has to accept the
// flag and say it is reusing the outputs, and the gate has to pass it.
test "the product gate hands ilverify the directories it already built rather than rebuilding them" {
    root := RepositoryRoot()
    ilverifyScript := File.ReadAllText(Path.Combine(Path.Combine(root, "scripts"), "ilverify.sh"))
    gateScript := File.ReadAllText(Path.Combine(Path.Combine(Path.Combine(root, "tests"), "scripts"), "test-all-core.sh"))

    assert ilverifyScript.Contains("--built-dirs-file")
    assert ilverifyScript.Contains("Using existing example/template/fixture build outputs")
    assert gateScript.Contains("ILVERIFY_BUILT_DIRS_FILE")
    assert gateScript.Contains("--built-dirs-file \"$ILVERIFY_BUILT_DIRS_FILE\"")
}
