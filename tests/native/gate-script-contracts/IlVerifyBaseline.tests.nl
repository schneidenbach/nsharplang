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

// ─── RESOLVING THE VERIFIER ACROSS THE GATE'S ISOLATED HOME ───────────────────────────────────
//
// `dotnet tool install --global dotnet-ilverify` puts the tool in `~/.dotnet/tools`, which is often
// not on PATH, and `tests/scripts/test-all.sh` runs the gate with HOME swapped for a throwaway
// directory. Step 10b once looked only at PATH and the ISOLATED home, so a machine with the tool
// installed failed with "dotnet-ilverify is not installed". The gate now resolves the tool in the
// invoking user's environment and hands the absolute path in as NSHARP_ILVERIFY, which
// `scripts/ilverify.sh` honors first. These rows run both halves for real against stub tools under
// a throwaway HOME; nothing is verified or built.
func IlvInvokingResolver(): string {
    return RequireMatch(
        ReadGateScript("test-all.sh"),
        "(?<body>resolve_invoking_ilverify\\(\\) \\{.*?\\n\\})",
        "Could not find resolve_invoking_ilverify in tests/scripts/test-all.sh."
    ).Groups["body"].Value
}

func IlvRunIlverifyScript(home: string, explicitTool: string): ProcessRun {
    // PATH is pinned to dotnet's own directory plus the system bins, so a verifier the machine
    // really has installed (CI puts `~/.dotnet/tools` on PATH) can never satisfy these rows. The
    // manifest is empty, so a resolution that wrongly succeeds still stops before verifying anything.
    command := "set -u\n"
        + "export PATH=\"$(dirname \"$(command -v dotnet)\"):/usr/bin:/bin\"\n"
        + ": > \"$HOME/empty-manifest.txt\"\n"
        + "scripts/ilverify.sh --built-dirs-file \"$HOME/empty-manifest.txt\"\n"
    launch := BashLaunch(command, 120000)
    launch.WithEnvironment("HOME", home)
    launch.WithEnvironment("DOTNET_CLI_HOME", home)
    if explicitTool == "" {
        launch.ClearedEnvironmentNames.Add("NSHARP_ILVERIFY")
    } else {
        launch.WithEnvironment("NSHARP_ILVERIFY", explicitTool)
    }

    return Run(launch)
}

test "the product gate resolves ilverify in the invoking user's environment before it isolates HOME" {
    gateScript := ReadGateScript("test-all.sh")
    resolvedIndex := gateScript.IndexOf("INVOKING_ILVERIFY=\"$(resolve_invoking_ilverify)\"")
    handedInIndex := gateScript.IndexOf("export NSHARP_ILVERIFY=\"$INVOKING_ILVERIFY\"")
    isolatedIndex := gateScript.IndexOf("export HOME=\"$RUN_HOME\"")
    assert resolvedIndex >= 0, "test-all.sh must resolve the invoking user's ilverify."
    assert handedInIndex >= 0, "test-all.sh must hand the resolved ilverify into the isolated run as NSHARP_ILVERIFY."
    assert isolatedIndex >= 0
    assert resolvedIndex < isolatedIndex && handedInIndex < isolatedIndex, "ilverify must be resolved and exported BEFORE HOME is swapped for the isolated run home."

    home := NewTempDirectory("nsharp-ilverify-resolve")
    try {
        command := IlvInvokingResolver() + "\n"
            + "set -u\n"
            + "unset NSHARP_ILVERIFY\n"
            + "export PATH=/usr/bin:/bin\n"
            + "printf 'none<%s>\\n' \"$(resolve_invoking_ilverify)\"\n"
            + "mkdir -p \"$HOME/.dotnet/tools\" \"$HOME/bin\"\n"
            + "printf '#!/bin/sh\\nexit 0\\n' > \"$HOME/.dotnet/tools/ilverify\"\n"
            + "chmod +x \"$HOME/.dotnet/tools/ilverify\"\n"
            + "printf 'tooldir<%s>\\n' \"$(resolve_invoking_ilverify)\"\n"
            + "cp \"$HOME/.dotnet/tools/ilverify\" \"$HOME/bin/ilverify\"\n"
            + "printf 'path<%s>\\n' \"$(PATH=\"$HOME/bin:$PATH\" resolve_invoking_ilverify)\"\n"
            + "printf 'explicit<%s>\\n' \"$(NSHARP_ILVERIFY=/opt/chosen/ilverify PATH=\"$HOME/bin:$PATH\" resolve_invoking_ilverify)\"\n"
        launch := BashLaunch(command, 60000)
        launch.WithEnvironment("HOME", home)
        result := Run(launch)

        assert result.ExitCode == 0, result.Report()
        assert result.Stdout.Contains("none<>\n"), "With no ilverify anywhere, nothing is handed in.\n" + result.Report()
        assert result.Stdout.Contains("tooldir<" + Path.Combine(Path.Combine(Path.Combine(home, ".dotnet"), "tools"), "ilverify") + ">\n"), "A global tool off PATH must be found in the invoking user's ~/.dotnet/tools.\n" + result.Report()
        assert result.Stdout.Contains("path<" + Path.Combine(Path.Combine(home, "bin"), "ilverify") + ">\n"), "An ilverify on PATH wins over ~/.dotnet/tools, exactly as scripts/ilverify.sh orders them.\n" + result.Report()
        assert result.Stdout.Contains("explicit</opt/chosen/ilverify>\n"), "A caller's own NSHARP_ILVERIFY is passed through untouched.\n" + result.Report()
    } finally {
        DeleteTempDirectory(home)
    }
}

test "scripts/ilverify.sh uses NSHARP_ILVERIFY first and still fails loudly when no verifier is installed" {
    home := NewTempDirectory("nsharp-ilverify-script")
    try {
        missing := IlvRunIlverifyScript(home, "")
        assert missing.ExitCode == 2, missing.Report()
        assert missing.Stdout.Contains("dotnet-ilverify is not installed."), missing.Report()
        assert missing.Stdout.Contains("dotnet tool install --global dotnet-ilverify"), missing.Report()

        absent := Path.Combine(Path.Combine(home, "absent"), "ilverify")
        notThere := IlvRunIlverifyScript(home, absent)
        assert notThere.ExitCode == 2, notThere.Report()
        assert notThere.Stdout.Contains("NSHARP_ILVERIFY is not an executable file: " + absent), notThere.Report()

        tools := Path.Combine(Path.Combine(home, ".dotnet"), "tools")
        Directory.CreateDirectory(tools)
        directory := IlvRunIlverifyScript(home, tools)
        assert directory.ExitCode == 2, directory.Report()
        assert directory.Stdout.Contains("NSHARP_ILVERIFY is not an executable file: " + tools), directory.Report()

        stub := Path.Combine(home, "chosen-ilverify")
        File.WriteAllText(stub, "#!/bin/sh\nexit 0\n")
        File.SetUnixFileMode(stub, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute)
        chosen := IlvRunIlverifyScript(home, stub)
        assert chosen.Stdout.Contains("ilverify    : " + stub), "An executable NSHARP_ILVERIFY is the verifier the gate runs.\n" + chosen.Report()
        assert !chosen.Stdout.Contains("not installed"), chosen.Report()
    } finally {
        DeleteTempDirectory(home)
    }
}
