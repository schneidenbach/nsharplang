using System;
using System.IO;
using System.Linq;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Guards the project-wide invariant that the N# compiler emits NO unverifiable IL across the
/// product surface (example projects, single-file examples, and representative fixtures).
///
/// The blocking gate is <c>scripts/ilverify.sh</c>, which runs <c>dotnet ilverify</c> over every
/// emitted assembly and diffs the findings against <c>scripts/ilverify-baseline.txt</c>. Each line
/// in that baseline is an allowlisted (i.e. *known-bad*) finding. After the IL-validity coverage
/// sweep drove that file to zero findings, this test pins it there: any new baselined finding —
/// the only way unverifiable IL can land without failing the gate outright — fails the suite and
/// must be justified by editing this test deliberately.
/// </summary>
public class IlVerifyBaselineEmptyTests
{
    [Fact]
    public void IlVerifyBaseline_HasZeroAllowlistedFindings()
    {
        var baselinePath = Path.Combine(FindRepoRoot(), "scripts", "ilverify-baseline.txt");
        Assert.True(File.Exists(baselinePath), $"ilverify baseline not found at {baselinePath}");

        var findings = File.ReadAllLines(baselinePath)
            .Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith('#'))
            .ToArray();

        Assert.True(
            findings.Length == 0,
            "scripts/ilverify-baseline.txt is expected to contain zero allowlisted IL-verification "
                + "findings, but found the following. Every entry is unverifiable IL the compiler "
                + "emits today — fix the emitter rather than allowlisting it:\n  "
                + string.Join("\n  ", findings));
    }

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
                return dir;
            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException(
            "Could not find repository root (NSharpLang.sln). "
                + $"Searched upward from {AppContext.BaseDirectory}");
    }
}
