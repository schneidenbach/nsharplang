namespace NSharpLang.GateScriptContracts.Tests

import System
import System.IO

func Step10CheckerFunctions(coreScript: string): string {
    beginMarker := "# STEP10_CHECK_FUNCTIONS_BEGIN"
    endMarker := "# STEP10_CHECK_FUNCTIONS_END"
    start := coreScript.IndexOf(beginMarker, StringComparison.Ordinal)
    finish := coreScript.IndexOf(endMarker, StringComparison.Ordinal)
    assert start >= 0 && finish > start, "Step 10 must expose its checker functions as one sourceable block."
    return coreScript.Substring(start + beginMarker.Length, finish - start - beginMarker.Length)
}

func MakeStep10Fixture(root: string, name: string, output: string): string {
    directory := Path.Combine(root, name)
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: " + name + "\nversion: 1.0.0\n")
    File.WriteAllText(Path.Combine(directory, "Main.nl"), "namespace Step10Fixture\n")
    File.WriteAllText(Path.Combine(directory, ".nlc-check.json"), output)
    return directory
}

func MakeStep10Dotnet(root: string): string {
    bin := Path.Combine(root, "bin")
    Directory.CreateDirectory(bin)
    dotnet := Path.Combine(bin, "dotnet")
    File.WriteAllText(dotnet, "#!/bin/bash\nproject_dir=\"${3%/}\"\ncat \"$project_dir/.nlc-check.json\"\n")

    chmod := new ProcessLaunch("chmod", RepositoryRoot(), 60000)
    chmod.Arguments.Add("+x")
    chmod.Arguments.Add(dotnet)
    run := Run(chmod)
    if run.ExitCode != 0 {
        throw new InvalidOperationException("Could not make the Step 10 fixture dotnet executable: " + run.Report())
    }

    return bin
}

func RunStep10Fixture(functionsFile: string, bin: string, entry: string, resultsDirectory: string): ProcessRun {
    launch := new ProcessLaunch("bash", RepositoryRoot(), 60000)
    launch.Arguments.Add("-lc")
    launch.Arguments.Add("source \"$1\"; dotnet() { \"$STEP10_FIXTURE_DOTNET\" \"$@\"; }; export -f dotnet; bash -lc \"$STEP10_CHECK_WORKER\" _ \"$2\" \"$3\" fixture-cli")
    launch.Arguments.Add("step10-contract")
    launch.Arguments.Add(functionsFile)
    launch.Arguments.Add(entry)
    launch.Arguments.Add(resultsDirectory)
    launch.WithEnvironment("PATH", bin + ":" + (Environment.GetEnvironmentVariable("PATH") ?? ""))
    launch.WithEnvironment("STEP10_FIXTURE_DOTNET", Path.Combine(bin, "dotnet"))
    return Run(launch)
}

test "the product gate checks every configured example and template project with zero errors and warnings" {
    coreScript := ReadGateScript("test-all-core.sh")

    assert coreScript.Contains("find examples templates -name project.yml"), "Step 10 must enumerate project.yml files under both examples/ and templates/ so nested projects cannot fall through a top-level directory sweep."
    assert coreScript.Contains("summary.get(\"errors\", -1)"), "Step 10 must read the error count from the check JSON."
    assert coreScript.Contains("summary.get(\"warnings\", -1)"), "Step 10 must read the warning count from the check JSON."
    assert coreScript.Contains("summary.get(\"projectFailures\", 0)"), "Step 10 must reject workspace project failures."
    assert coreScript.Contains("[ \"$errors\" = \"0\" ] && [ \"$warnings\" = \"0\" ] && [ \"$project_failures\" = \"0\" ] && [ \"$is_ok\" = \"true\" ]"), "A project passes Step 10 only when it reports zero errors, zero warnings, no project failures, and an ok result."
    assert coreScript.Contains("bash -lc \"$STEP10_CHECK_WORKER\" _ {} \"$CHECK_RESULTS_DIR\" \"$CLI_DLL\""), "The parallel workers must invoke the separately defined Step 10 checker."
    assert !coreScript.Contains("python3 -c \"import sys,json"), "JSON parsing must not be nested inside the quoted xargs worker."
}

test "the Step 10 checker runs through the login-shell worker on passing and failing fixture projects" {
    coreScript := ReadGateScript("test-all-core.sh")
    root := NewTempDirectory("step10-check-project")
    try {
        functionsFile := Path.Combine(root, "step10-functions.sh")
        File.WriteAllText(functionsFile, Step10CheckerFunctions(coreScript))
        bin := MakeStep10Dotnet(root)
        resultsDirectory := Path.Combine(root, "results")
        Directory.CreateDirectory(resultsDirectory)

        directories := [
            MakeStep10Fixture(root, "pass fixture project", "{\"summary\":{\"errors\":0,\"warnings\":0,\"projectFailures\":0},\"ok\":true}\n"),
            MakeStep10Fixture(root, "error fixture project", "{\"summary\":{\"errors\":1,\"warnings\":0,\"projectFailures\":0},\"ok\":false}\n"),
            MakeStep10Fixture(root, "warning fixture project", "{\"summary\":{\"errors\":0,\"warnings\":1,\"projectFailures\":0},\"ok\":true}\n"),
            MakeStep10Fixture(root, "project failure fixture", "{\"summary\":{\"errors\":0,\"warnings\":0,\"projectFailures\":1},\"ok\":false}\n"),
            MakeStep10Fixture(root, "not ok fixture project", "{\"summary\":{\"errors\":0,\"warnings\":0,\"projectFailures\":0},\"ok\":false}\n"),
            MakeStep10Fixture(root, "wrong json types fixture", "{\"summary\":{\"errors\":\"0\",\"warnings\":\"0\",\"projectFailures\":\"0\"},\"ok\":\"true\"}\n")
        ]
        expected := ["0|0|0|true", "1|0|0|false", "0|1|0|true", "0|0|1|false", "0|0|0|false", "?|?|?|false"]

        for index := 0; index < directories.Length; index++ {
            entry := (index + 1).ToString("D4") + "|" + directories[index]
            run := RunStep10Fixture(functionsFile, bin, entry, resultsDirectory)
            assert run.ExitCode == 0, run.Report()
            resultFile := Path.Combine(resultsDirectory, (index + 1).ToString("D4") + ".result")
            assert File.Exists(resultFile), "The Step 10 checker did not record fixture project " + directories[index] + "."
            fields := File.ReadAllText(resultFile).Split('|')
            observed := fields[0] + "|" + fields[1] + "|" + fields[2] + "|" + fields[3]
            assert observed == expected[index], "Unexpected Step 10 result for " + directories[index] + ": " + File.ReadAllText(resultFile)
            assert fields[4] == directories[index], "Step 10 changed the fixture path while carrying it through the worker: " + File.ReadAllText(resultFile)
        }
    } finally {
        DeleteTempDirectory(root)
    }
}

test "Step 10 checks both projects created by the installed console and web API templates" {
    coreScript := ReadGateScript("test-all-core.sh")

    assert coreScript.Contains("$TEMP_DIR/TestConsoleApp")
    assert coreScript.Contains("$TEMP_DIR/TestWebApiApp")
    assert coreScript.Contains("trap cleanup_on_exit EXIT")
    assert coreScript.Contains("rm -rf \"$TEMP_DIR\""), "The generated projects must remain available through Step 10 and be removed when the gate exits, including failure paths."
}
