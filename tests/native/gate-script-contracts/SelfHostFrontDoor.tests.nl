namespace NSharpLang.GateScriptContracts.Tests

import System.Collections.Generic
import System.Text.RegularExpressions

// ─── THE SELF-HOST FRONT DOOR'S OWN STEP (Step 2d of the product gate) ────────────────────────
//
// Every row here reads `tests/scripts/test-all-core.sh` as TEXT. None of them runs the gate, the
// CLI or a check.
//
// Step 2d checks five projects with the CLI the gate just built and compares each count to a
// ceiling. `src/NSharpLang.Compiler.Model`, carved out of Core, is checked first at ceiling 0: Core
// takes it as a `project:` reference, so a diagnostic in Model would BLOCK Core's check rather than
// count in it, and the zero is what keeps Core's number a number. Two of the five — `src/NSharpLang.Compiler` and `src/NSharpLang.Playground` — carry the
// ceiling -1, which the step's own comment defines as BLOCKED: `check` resolves references with
// `BuildProjectReferences` on, so checking a project that references Compiler.Core begins by
// building Core from source, and that build cannot succeed while Core's own front door reports
// diagnostics. Those two checks therefore produce an error envelope and no count, at the price of
// a full front-end compile of Core each (~2 minutes apiece, measured).
//
// The step now prints the BLOCKED row WITHOUT starting the build it knows cannot succeed, and only
// while Core's count in the SAME run is a number above zero. These rows pin that guard in both
// directions: the work is skipped only when it is provably unreachable, and nothing about the
// ceilings, the ratchet comparisons or Core's own check moved.
func CoreScript(): string {
    return ReadGateScript("test-all-core.sh")
}

// The `SELF_HOST_CEILINGS=( ... )` array body of the gate script, one entry per line.
func SelfHostCeilings(coreScript: string): List<string> {
    body := RequireMatch(coreScript, "SELF_HOST_CEILINGS=\\(\\s*(?<body>[^)]*)\\)", "Could not find the SELF_HOST_CEILINGS array in tests/scripts/test-all-core.sh.").Groups["body"].Value
    ceilings := new List<string>()
    for line in body.Split('\n') {
        trimmed := line.Trim()
        if trimmed.Length > 0 && !trimmed.StartsWith("#") {
            ceilings.Add(trimmed)
        }
    }

    return ceilings
}

func SelfHostProjects(coreScript: string): List<string> {
    body := RequireMatch(coreScript, "SELF_HOST_PROJECTS=\\(\\s*(?<body>[^)]*)\\)", "Could not find the SELF_HOST_PROJECTS array in tests/scripts/test-all-core.sh.").Groups["body"].Value
    return QuotedStrings(body)
}

func BlockedSentence(): string {
    return "BLOCKED behind Compiler.Core's own front door; not counted yet"
}

test "the self-host front door checks Compiler.Model, then Compiler.Core, and records the count the blocked projects are judged against" {
    coreScript := CoreScript()

    projects := SelfHostProjects(coreScript)
    assert projects.Count == 5, "The self-host front door must check five projects; found " + projects.Count.ToString() + "."
    assert projects[0] == "src/NSharpLang.Compiler.Model", "Compiler.Model must be checked FIRST: Core's check builds it as a project reference, so its own count is what says whether Core's can be read at all."
    assert projects[1] == "src/NSharpLang.Compiler.Core", "Compiler.Core must be checked before the projects that reference it: the skip for them is keyed on the count this run measured for Core, and a later position would leave that count unread."
    assert projects.Contains("src/NSharpLang.Compiler")
    assert projects.Contains("src/NSharpLang.Playground")
    assert projects.Contains("src/NSharpLang.Build.Tasks")

    checkIndex := coreScript.IndexOf("dotnet \"$CLI_DLL\" check --project \"$SELF_HOST_PROJECT\" --json")
    assert checkIndex >= 0, "The self-host front door must still invoke `nlc check` on the projects it counts."

    // Core's count is carried forward under Core's own name, never inferred from the loop index.
    assert coreScript.Contains("if [ \"$SELF_HOST_PROJECT\" = \"src/NSharpLang.Compiler.Core\" ]; then\n            SELF_HOST_CORE_COUNT=\"$SELF_HOST_COUNT\""), "Step 2d must record Compiler.Core's own diagnostic count in SELF_HOST_CORE_COUNT as it checks it."
}

test "a BLOCKED front-door project skips the build that cannot succeed ONLY while Compiler.Core's own count is a number above zero" {
    coreScript := CoreScript()

    guard := RequireMatch(
        coreScript,
        "if \\[ \"\\$SELF_HOST_CEILING\" -lt 0 \\] \\\\\\s*\\n\\s*&& \\[\\[ \"\\$SELF_HOST_CORE_COUNT\" =~ \\^\\[0-9\\]\\+\\$ \\]\\] \\\\\\s*\\n\\s*&& \\[ \"\\$SELF_HOST_CORE_COUNT\" -gt 0 \\]; then\\s*\\n(?<body>.*?)\\n\\s*continue\\s*\\n\\s*fi",
        "Could not find Step 2d's guard for a BLOCKED project. It must require ALL THREE of: the ceiling is negative (the project is declared BLOCKED), Compiler.Core's count in this run is a NUMBER (an unreadable check must never be read as a block), and that number is ABOVE ZERO (a clean Core means the reference build can succeed and the project must be checked for real)."
    )

    body := guard.Groups["body"].Value
    assert body.Contains(BlockedSentence()), "The skipped row must print the same BLOCKED sentence the checked path prints."
    assert body.Contains("not attempted"), "The skipped row must say it did not run the check; the parenthetical of the checked path reports what the check returned, and printing that text without running it would be a lie."
    assert body.Contains("$SELF_HOST_CORE_COUNT"), "The skipped row must carry the number that proves the block."
    assert !body.Contains("dotnet"), "The skip must not invoke anything."

    // The guard is inside the loop and ahead of the invocation it skips.
    loopIndex := coreScript.IndexOf("for ((self_host_index = 0;")
    guardIndex := coreScript.IndexOf("if [ \"$SELF_HOST_CEILING\" -lt 0 ] \\")
    checkIndex := coreScript.IndexOf("dotnet \"$CLI_DLL\" check --project \"$SELF_HOST_PROJECT\" --json")
    assert loopIndex >= 0 && guardIndex > loopIndex, "The guard must live inside the front-door loop."
    assert guardIndex < checkIndex, "The guard must come BEFORE the check it skips, or the check runs anyway."
}

test "skipping the doomed build changes no ceiling and no ratchet comparison in the self-host front door" {
    coreScript := CoreScript()

    ceilings := SelfHostCeilings(coreScript)
    assert ceilings.Count == 5, "The self-host front door must carry five ceilings; found " + ceilings.Count.ToString() + "."
    assert ceilings[0] == "0", "Compiler.Model's front-door ceiling must stay 0; found '" + ceilings[0] + "'."
    assert ceilings[1] == "1279", "Compiler.Core's front-door ceiling must stay 1279; found '" + ceilings[1] + "'."
    assert ceilings[2] == "-1"
    assert ceilings[3] == "-1"
    assert ceilings[4] == "0", "Build.Tasks' front-door ceiling must stay 0; found '" + ceilings[4] + "'."

    // All three ratchet directions survive verbatim: over the ceiling fails the step, under it
    // demands the ceiling be lowered, and at it passes.
    assert coreScript.Contains("the compiler's own source got WORSE through its own front door.")
    assert coreScript.Contains("below the ceiling of $SELF_HOST_CEILING - lower the ceiling in tests/scripts/test-all-core.sh.")
    assert coreScript.Contains("$SELF_HOST_COUNT diagnostics (at the ceiling).")
    assert coreScript.Contains("check produced no readable JSON"), "An unreadable check must still fail the step rather than count as zero."

    // The BLOCKED sentence exists on exactly two paths: the one that skipped the build and the one
    // that ran the check anyway (an unreadable or clean Core). Neither may be deleted.
    blocked := Regex.Matches(coreScript, Regex.Escape(BlockedSentence()))
    assert blocked.Count == 2, "Expected the BLOCKED sentence on exactly two paths (skipped, and checked-for-real); found " + blocked.Count.ToString() + "."
}
