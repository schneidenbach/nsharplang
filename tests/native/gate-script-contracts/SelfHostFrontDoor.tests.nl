namespace NSharpLang.GateScriptContracts.Tests

import System.Collections.Generic
import System.Text.RegularExpressions

// ─── THE SELF-HOST FRONT DOOR'S OWN STEP (Step 2d of the product gate) ────────────────────────
//
// Every row here reads `tests/scripts/test-all-core.sh` as TEXT. None of them runs the gate, the
// CLI or a check.
//
// Step 2d checks eight projects with the CLI the gate just built and compares each count to a
// ceiling: the compiler's slices lowest first (`src/NSharpLang.Compiler.Model`, `.Syntax`, `.Core`,
// `.Tooling`, `.Driver`), then the `Compiler` facade, the Playground and Build.Tasks. Each is checked with
// `--use-built-references`: its `project:` dependencies are read from the assemblies Step 2 just
// built rather than compiled from source by the check. Before that, a project referencing Core began
// its check by compiling Core, which cannot succeed while Core's own front door reports anything, so
// Compiler, Playground and Driver sat at ceiling -1 -- BLOCKED, counted nowhere. Now every ceiling is
// a measured number, and BLOCKED is left for the one case a check truly cannot run: a dependency
// Step 2 did not build (or built from older sources). That row names the dependency and FAILS the
// step, because an uncounted project is a coverage hole.
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
    return "BLOCKED behind a dependency Step 2 did not build; not counted"
}

func SelfHostCheckInvocation(): string {
    return "dotnet \"$CLI_DLL\" check --use-built-references --project \"$SELF_HOST_PROJECT\" --json"
}

test "the self-host front door checks the compiler's slices lowest first, then the projects above them, each against its dependencies' built assemblies" {
    coreScript := CoreScript()

    projects := SelfHostProjects(coreScript)
    assert projects.Count == 8, "The self-host front door must check eight projects; found " + projects.Count.ToString() + "."
    assert projects[0] == "src/NSharpLang.Compiler.Model"
    assert projects[1] == "src/NSharpLang.Compiler.Syntax"
    assert projects[2] == "src/NSharpLang.Compiler.Core"
    assert projects[3] == "src/NSharpLang.Compiler.Tooling", "Compiler.Tooling, carved out ABOVE Core, is checked right after it."
    assert projects[4] == "src/NSharpLang.Compiler.Driver", "Compiler.Driver, carved out ABOVE Tooling, is checked right after it."
    assert projects.Contains("src/NSharpLang.Compiler")
    assert projects.Contains("src/NSharpLang.Playground")
    assert projects.Contains("src/NSharpLang.Build.Tasks")

    // Every project, not a chosen few: a check that compiles a dependency from source is a check that
    // can be blocked by that dependency's own diagnostics, which is the coverage hole this closes.
    assert coreScript.Contains(SelfHostCheckInvocation()), "Step 2d must check each project against its dependencies' built assemblies."
    assert !coreScript.Contains("dotnet \"$CLI_DLL\" check --project \"$SELF_HOST_PROJECT\" --json"), "No project may be checked by compiling its dependencies from source."

    // The dependencies are built by Step 2, which runs first.
    buildIndex := coreScript.IndexOf("section \"Step 2: Build N# Compiler\"")
    frontDoorIndex := coreScript.IndexOf("section \"Step 2d: Self-Host Front Door\"")
    assert buildIndex >= 0 && frontDoorIndex > buildIndex, "Step 2 must build the dependencies before Step 2d reads them."
    assert coreScript.Contains("dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Cli/Cli.csproj -v q")
    assert coreScript.Contains("dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Playground/NSharpLang.Playground.csproj -v q")
}

test "every self-host ceiling is a measured number, and none of them is the old BLOCKED marker" {
    coreScript := CoreScript()

    ceilings := SelfHostCeilings(coreScript)
    assert ceilings.Count == 8, "The self-host front door must carry eight ceilings; found " + ceilings.Count.ToString() + "."
    assert ceilings[0] == "0", "Compiler.Model's front-door ceiling must stay 0; found '" + ceilings[0] + "'."
    assert ceilings[1] == "0", "Compiler.Syntax's front-door ceiling must stay 0; found '" + ceilings[1] + "'."
    assert ceilings[2] == "1029", "Compiler.Core's front-door ceiling must stay 1029; found '" + ceilings[2] + "'."
    assert ceilings[3] == "0", "Compiler.Tooling's front-door ceiling must stay 0; found '" + ceilings[3] + "'."
    assert ceilings[4] == "0", "Compiler.Driver's front-door ceiling must stay 0; found '" + ceilings[4] + "'."
    assert ceilings[5] == "34", "Compiler's front-door ceiling must stay 34; found '" + ceilings[5] + "'."
    assert ceilings[6] == "0", "Playground's front-door ceiling must stay 0; found '" + ceilings[6] + "'."
    assert ceilings[7] == "0", "Build.Tasks' front-door ceiling must stay 0; found '" + ceilings[7] + "'."
    for ceiling in ceilings {
        assert Regex.IsMatch(ceiling, "^[0-9]+$"), "A self-host ceiling is a count; found '" + ceiling + "'."
    }

    // All three ratchet directions survive verbatim: over the ceiling fails the step, under it
    // demands the ceiling be lowered, and at it passes.
    assert coreScript.Contains("the compiler's own source got WORSE through its own front door.")
    assert coreScript.Contains("below the ceiling of $SELF_HOST_CEILING - lower the ceiling in tests/scripts/test-all-core.sh.")
    assert coreScript.Contains("$SELF_HOST_COUNT diagnostics (at the ceiling).")
    assert coreScript.Contains("check produced no readable JSON"), "An unreadable check must still fail the step rather than count as zero."
}

test "a project is BLOCKED only when a dependency Step 2 did not build, and a BLOCKED project fails the step" {
    coreScript := CoreScript()

    // The reader tells the resolver's two refusals of a built reference apart from any other failure.
    assert coreScript.Contains("if \"has no built assembly at\" in message or \"is out of date:\" in message:")
    assert coreScript.Contains("print(\"blocked: \" + message)")

    guard := RequireMatch(
        coreScript,
        "if \\[\\[ \"\\$SELF_HOST_COUNT\" == blocked:\\* \\]\\]; then\\s*\\n(?<body>.*?)\\n\\s*elif",
        "Could not find Step 2d's BLOCKED row: a check refused for a dependency's missing or stale built assembly."
    )
    body := guard.Groups["body"].Value
    assert body.Contains(BlockedSentence()), "The BLOCKED row must say why nothing was counted."
    assert body.Contains("${SELF_HOST_COUNT#blocked: }"), "The BLOCKED row must carry the resolver's message, which names the dependency."
    assert body.Contains("SELF_HOST_OK=0"), "An uncounted project is a coverage hole: BLOCKED fails the step."

    // BLOCKED has one path, and the old skip keyed on Core's own count is gone.
    assert Regex.Matches(coreScript, Regex.Escape(BlockedSentence())).Count == 1
    assert !coreScript.Contains("SELF_HOST_CORE_COUNT"), "No project's check may depend on another project's front-door count."

    // The guard reads the check it follows.
    checkIndex := coreScript.IndexOf(SelfHostCheckInvocation())
    guardIndex := coreScript.IndexOf("if [[ \"$SELF_HOST_COUNT\" == blocked:* ]]; then")
    assert checkIndex >= 0 && guardIndex > checkIndex
}
