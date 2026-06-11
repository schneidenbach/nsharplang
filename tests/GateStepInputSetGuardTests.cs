using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Xunit;

namespace NSharpLang.Tests;

// The product gate (tests/scripts/test-all.sh) may skip a step inside a plain
// fresh development run only when the step's ENTIRE declared input set is
// byte-identical to inputs that previously passed it. That design is sound ONLY
// while every declared input set is a superset of what the step actually reads.
// These guards also ensure commit verification disables per-step skipping; see
// memory/testing.md, "The Product Gate Skips Steps With Unchanged Inputs".
public class GateStepInputSetGuardTests
{
    // Repo files unit tests read and assert on that the Path.Combine scan below
    // cannot discover (non-repo-root anchors), plus the three files whose
    // omission originally made a docs-only --commit skip failing unit tests.
    private static readonly string[] KnownRepoFilesReadByUnitTests =
    {
        // tests/CliCommandTests.cs: CliCommandRegistry_StaysInSyncWithHelpCompletionsAndDocs
        "website/docs/cli-reference.md",
        // tests/QueryIntegrationTests.cs: golden compare anchored at _examplesDir/../docs
        "docs/examples/diagnostic-clusters.sample.json",
        // tests/SystemsNSharpTests.cs: SystemsProofProjects_AreExecutableAndCoveredByAudit
        "docs/audits/systems-proof-project-audit.md",
    };

    [Fact]
    public void UnitInputSet_CoversRepoFilesReadByUnitTests()
    {
        var (_, sets) = ParseInputSets(ReadGateScript("test-all-core.sh"));
        Assert.True(sets.ContainsKey("UNIT"), "Could not find the UNIT entry in the SETS literal of tests/scripts/test-all-core.sh.");
        var unitPrefixes = sets["UNIT"];

        // Wholesale documentation coverage, not per-file allowlists: any future
        // parity test against any docs page must stay covered.
        Assert.Contains("docs/", unitPrefixes);
        Assert.Contains("website/docs/", unitPrefixes);

        var uncovered = KnownRepoFilesReadByUnitTests
            .Where(file => !IsCovered(file, unitPrefixes))
            .ToArray();
        Assert.True(
            uncovered.Length == 0,
            "These repo files are read and asserted on by unit tests but are NOT in the UNIT "
                + "input set of the validated per-step cache (tests/scripts/test-all-core.sh). "
                + "A change to them would skip unit tests in a cached development gate run "
                + "and hide a red test. Add a covering prefix to SETS[\"UNIT\"] — see "
                + "memory/testing.md, \"The Product Gate Skips Steps With Unchanged Inputs\".\n"
                + string.Join("\n", uncovered));
    }

    // Self-discovery: every consecutive-literal path that a test source joins
    // onto the repo root must be covered by a UNIT prefix. New tests that read
    // repo files through the FindRepoRoot()/repoRoot convention are guarded
    // automatically; widen the UNIT entry in SETS when this fires.
    [Fact]
    public void RepoRootPathsInTestSources_AreCoveredByUnitInputSet()
    {
        var repoRoot = FindRepoRoot();
        var (_, sets) = ParseInputSets(ReadGateScript("test-all-core.sh"));
        var unitPrefixes = sets["UNIT"];
        var offenders = new List<string>();

        foreach (var file in Directory.EnumerateFiles(Path.Combine(repoRoot, "tests"), "*.cs", SearchOption.AllDirectories))
        {
            var relativePath = Path.GetRelativePath(repoRoot, file);
            var segments = relativePath.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (segments.Any(segment => segment is "bin" or "obj" or "TestResults"))
            {
                continue;
            }

            foreach (Match match in RepoRootCombine.Matches(File.ReadAllText(file)))
            {
                var joined = string.Join("/", match.Groups["seg"].Captures.Select(capture => capture.Value));
                if (!IsCovered(joined, unitPrefixes))
                {
                    offenders.Add($"{relativePath}: Path.Combine(<repo root>, \"{joined}\")");
                }
            }
        }

        Assert.True(
            offenders.Count == 0,
            "Test sources join these paths onto the repo root, but no UNIT input-set prefix in "
                + "tests/scripts/test-all-core.sh covers them, so changing those files would skip "
                + "unit tests in a cached development gate run. Add a covering prefix to "
                + "SETS[\"UNIT\"] — see memory/testing.md, \"The Product Gate Skips Steps With "
                + "Unchanged Inputs\".\n"
                + string.Join("\n", offenders.Distinct()));
    }

    // The step keys must agree with the whole-gate signature on environment:
    // a marker stored under one behavior-changing environment (columnar backend
    // on, golden regeneration, ...) must never satisfy a run under another.
    [Fact]
    public void StepCacheSalt_IncludesEnvironmentAndIlverifyToolVersion()
    {
        var coreScript = ReadGateScript("test-all-core.sh");
        var gateScript = ReadGateScript("test-all.sh");

        var saltMatch = Regex.Match(coreScript, @"salt = json\.dumps\(\{(?<body>.*?)\}, sort_keys=True\)", RegexOptions.Singleline);
        Assert.True(saltMatch.Success, "Could not find the per-step salt construction in tests/scripts/test-all-core.sh.");
        Assert.Contains("\"ilverify\"", saltMatch.Groups["body"].Value);
        Assert.Contains("\"environment\"", saltMatch.Groups["body"].Value);

        var coreEnvMatch = Regex.Match(coreScript, @"ENV_NAMES\s*=\s*\((?<body>[^)]*)\)", RegexOptions.Singleline);
        Assert.True(coreEnvMatch.Success, "Could not find the ENV_NAMES tuple in tests/scripts/test-all-core.sh.");
        var coreEnvNames = QuotedStrings(coreEnvMatch.Groups["body"].Value);

        var gateEnvMatch = Regex.Match(gateScript, @"env_names\s*=\s*\[(?<body>[^\]]*)\]", RegexOptions.Singleline);
        Assert.True(gateEnvMatch.Success, "Could not find the env_names list in tests/scripts/test-all.sh.");
        var gateEnvNames = QuotedStrings(gateEnvMatch.Groups["body"].Value);

        Assert.Contains("NSHARP_COLUMNAR_BACKEND", coreEnvNames);
        Assert.Contains("NSHARP_COLUMNAR_BACKEND", gateEnvNames);
        Assert.True(
            coreEnvNames.ToHashSet().SetEquals(gateEnvNames),
            "The per-step salt ENV_NAMES (tests/scripts/test-all-core.sh) and the whole-gate "
                + "signature env_names (tests/scripts/test-all.sh) must list the same environment "
                + "variables, or step markers and gate manifests disagree on what \"same "
                + "environment\" means.\n"
                + $"core:  {string.Join(", ", coreEnvNames.OrderBy(n => n, StringComparer.Ordinal))}\n"
                + $"gate:  {string.Join(", ", gateEnvNames.OrderBy(n => n, StringComparer.Ordinal))}");

        // Golden regeneration inside the discarded isolated copy makes golden
        // tests self-satisfying; the isolated env must always strip it.
        Assert.Contains("unset NSHARP_UPDATE_DIAGNOSTIC_GOLDENS", gateScript);
    }

    [Fact]
    public void CommitMode_DisablesPerStepCache()
    {
        var gateScript = ReadGateScript("test-all.sh");
        var commitCase = Regex.Match(
            gateScript,
            @"--commit\|--pre-commit\)(?<body>.*?);;",
            RegexOptions.Singleline);

        Assert.True(commitCase.Success, "Could not find the --commit case in tests/scripts/test-all.sh.");
        Assert.Contains("FORCE_RUN=1", commitCase.Groups["body"].Value);
        Assert.Contains("STEP_CACHE_OFF=1", commitCase.Groups["body"].Value);
    }

    // End-to-end behavior of the embedded hash step: a docs change must move
    // the UNIT key (and only the keys whose sets cover docs), identical inputs
    // must produce identical keys, and salted environment must move every key.
    [Fact]
    public void StepHashes_ChangeForUnitDocsInputs_AndAreStableOtherwise()
    {
        var python = ExtractStepHashPython(ReadGateScript("test-all-core.sh"));
        var workRoot = Directory.CreateTempSubdirectory("nsharp-step-hash-guard-").FullName;
        try
        {
            var pythonPath = Path.Combine(workRoot, "step-hash.py");
            File.WriteAllText(pythonPath, python);

            var fixtureRoot = Path.Combine(workRoot, "repo");
            WriteFixtureFile(fixtureRoot, "src/Compiler.cs", "class Compiler { }");
            WriteFixtureFile(fixtureRoot, "tests/SampleTests.cs", "class SampleTests { }");
            WriteFixtureFile(fixtureRoot, "benchmarks/Bench.cs", "class Bench { }");
            WriteFixtureFile(fixtureRoot, "docs/audits/systems-proof-project-audit.md", "| `24-zero-copy-frame-reader` | executable |");
            WriteFixtureFile(fixtureRoot, "website/docs/cli-reference.md", "nlc build");

            var baseline = RunStepHash(pythonPath, fixtureRoot);
            var rerun = RunStepHash(pythonPath, fixtureRoot);
            Assert.Equal(baseline, rerun);

            WriteFixtureFile(fixtureRoot, "website/docs/cli-reference.md", "nlc build --changed");
            var afterWebsiteDocs = RunStepHash(pythonPath, fixtureRoot);
            Assert.NotEqual(baseline["UNIT"], afterWebsiteDocs["UNIT"]);
            Assert.Equal(baseline["BENCH"], afterWebsiteDocs["BENCH"]);
            Assert.Equal(baseline["INTEROP"], afterWebsiteDocs["INTEROP"]);
            Assert.Equal(baseline["EXAMPLES"], afterWebsiteDocs["EXAMPLES"]);

            WriteFixtureFile(fixtureRoot, "docs/audits/systems-proof-project-audit.md", "| `24-zero-copy-frame-reader` | design-only |");
            var afterDocs = RunStepHash(pythonPath, fixtureRoot);
            Assert.NotEqual(afterWebsiteDocs["UNIT"], afterDocs["UNIT"]);
            Assert.Equal(baseline["BENCH"], afterDocs["BENCH"]);

            var salted = RunStepHash(pythonPath, fixtureRoot, ("NSHARP_COLUMNAR_BACKEND", "1"));
            foreach (var step in afterDocs.Keys)
            {
                Assert.NotEqual(afterDocs[step], salted[step]);
            }
        }
        finally
        {
            Directory.Delete(workRoot, recursive: true);
        }
    }

    // Matches Path.Combine calls anchored at the repo root by convention
    // (FindRepoRoot() or a *repoRoot* identifier) and captures the consecutive
    // leading string-literal segments. Temp-dir anchors (tempRoot, projectRoot,
    // bare root) are deliberately excluded — they routinely reuse repo-like
    // names (project.yml) outside the repository.
    private static readonly Regex RepoRootCombine = new(
        @"Path\.Combine\(\s*(?:FindRepoRoot\(\)|\w*[Rr]epoRoot\w*)\s*(?:,\s*""(?<seg>[^""]+)"")+",
        RegexOptions.Compiled);

    private static bool IsCovered(string relativePath, IReadOnlyCollection<string> prefixes)
    {
        return prefixes.Any(prefix => prefix.EndsWith('/')
            ? relativePath.StartsWith(prefix, StringComparison.Ordinal) || prefix == relativePath + "/"
            : relativePath == prefix);
    }

    private static (string[] Common, Dictionary<string, string[]> Sets) ParseInputSets(string coreScript)
    {
        var commonMatch = Regex.Match(coreScript, @"COMMON\s*=\s*\((?<body>[^)]*)\)", RegexOptions.Singleline);
        Assert.True(commonMatch.Success, "Could not find the COMMON tuple in tests/scripts/test-all-core.sh.");
        var common = QuotedStrings(commonMatch.Groups["body"].Value);

        var setsMatch = Regex.Match(coreScript, @"SETS\s*=\s*\{(?<body>.*?)\n\}", RegexOptions.Singleline);
        Assert.True(setsMatch.Success, "Could not find the SETS literal in tests/scripts/test-all-core.sh.");

        var sets = new Dictionary<string, string[]>();
        foreach (Match entry in Regex.Matches(
            setsMatch.Groups["body"].Value,
            @"""(?<name>\w+)"":\s*COMMON\s*\+\s*\((?<body>[^)]*)\)",
            RegexOptions.Singleline))
        {
            sets[entry.Groups["name"].Value] = common.Concat(QuotedStrings(entry.Groups["body"].Value)).ToArray();
        }

        Assert.True(sets.Count >= 4, "Expected at least the UNIT/BENCH/INTEROP/EXAMPLES entries in the SETS literal.");
        return (common, sets);
    }

    private static string[] QuotedStrings(string tupleBody) =>
        Regex.Matches(tupleBody, @"""(?<value>[^""]+)""").Select(match => match.Groups["value"].Value).ToArray();

    private static string ReadGateScript(string name) =>
        File.ReadAllText(Path.Combine(FindRepoRoot(), "tests", "scripts", name));

    private static string ExtractStepHashPython(string coreScript)
    {
        var lines = coreScript.Split('\n');
        var start = Array.FindIndex(lines, line => line.Contains("STEP_HASH_OUTPUT=\"$(python3", StringComparison.Ordinal));
        Assert.True(start >= 0, "Could not find the STEP_HASH_OUTPUT python heredoc in tests/scripts/test-all-core.sh.");
        var end = Array.FindIndex(lines, start + 1, line => line.TrimEnd() == "PY");
        Assert.True(end > start, "Could not find the PY heredoc terminator in tests/scripts/test-all-core.sh.");
        return string.Join("\n", lines[(start + 1)..end]);
    }

    private static void WriteFixtureFile(string root, string relativePath, string content)
    {
        var path = Path.Combine(root, relativePath.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
    }

    private static Dictionary<string, string> RunStepHash(string pythonPath, string root, params (string Name, string Value)[] environment)
    {
        var startInfo = new ProcessStartInfo("python3")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        startInfo.ArgumentList.Add(pythonPath);
        startInfo.ArgumentList.Add(root);

        // Pin the salted environment so ambient session variables (a dogfood
        // arc exporting NSHARP_COLUMNAR_BACKEND, a gate exporting VSCODE_TESTS)
        // cannot leak into the baseline expectations.
        foreach (var name in SaltedEnvNames())
        {
            startInfo.Environment.Remove(name);
        }
        foreach (var (name, value) in environment)
        {
            startInfo.Environment[name] = value;
        }

        using var process = Process.Start(startInfo)!;
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();
        Assert.True(process.ExitCode == 0, $"step-hash python exited {process.ExitCode}: {stderr}");

        var hashes = stdout
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(line => line.Split('=', 2))
            .Where(parts => parts.Length == 2)
            .ToDictionary(parts => parts[0], parts => parts[1]);
        Assert.True(hashes.Count >= 4, $"Expected one hash per input set, got: {stdout}");
        return hashes;
    }

    private static string[] SaltedEnvNames()
    {
        var coreEnvMatch = Regex.Match(ReadGateScript("test-all-core.sh"), @"ENV_NAMES\s*=\s*\((?<body>[^)]*)\)", RegexOptions.Singleline);
        Assert.True(coreEnvMatch.Success, "Could not find the ENV_NAMES tuple in tests/scripts/test-all-core.sh.");
        return QuotedStrings(coreEnvMatch.Groups["body"].Value);
    }

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
            {
                return dir;
            }

            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException(
            "Could not find repository root (NSharpLang.sln). "
                + $"Searched upward from {AppContext.BaseDirectory}");
    }
}
