using System.Collections.Generic;
using System.Globalization;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// The one code-intelligence output contract that cannot be stated in N#.
///
/// The other forty-four cases this file used to hold moved to the estate in 020 slice 10, beside
/// the code they describe: <c>OutputFormatterJsonKernels.tests.nl</c> (the versioned JSON
/// envelopes and their exact root keys), <c>OutputFormatterTextBuilders.tests.nl</c> (every
/// <c>--text</c> answer, stated as whole texts) and
/// <c>OutputFormatterDiagnosticKernels.tests.nl</c> (the severity arithmetic, reference
/// deduplication, and the two end-to-end <c>CodeIntelligenceQueries.Diagnostics</c> contracts).
/// <c>OutputFormatter</c> and <c>CodeIntelligenceService</c> are pure forwarders, so those
/// contracts now sit on the N# owners that actually do the work.
///
/// THE WALL, AT ITS EXACT DECLINE SITE. This case is only non-vacuous under a Turkish ambient
/// culture: <c>"idi".ToUpper()</c> under <c>tr-TR</c> produces <c>"\u0130D\u0130"</c>, and the contract is
/// that <see cref="OutputFormatterDiagnosticKernels.DiagnosticUpperInvariant"/> does NOT do that.
/// N# cannot reach <see cref="CultureInfo"/> in either direction, both times at
/// <c>emit.local.initializer</c>:
///
///   * reading the ambient culture — <c>previous := CultureInfo.CurrentCulture</c> — declines, so
///     the swap-and-restore below cannot be spelled; and
///   * constructing one — <c>turkish := new CultureInfo("tr-TR")</c> — declines, so the
///     culture-as-an-argument alternative (<c>value.ToUpper(turkish)</c>) cannot be spelled either.
///
/// An estate contract could therefore only assert <c>DiagnosticUpperInvariant("idi") == "IDI"</c>
/// under the invariant culture, which is strictly weaker than what is written here: it would pass
/// even if the kernel called the culture-sensitive <c>ToUpper()</c>. The case stays in C# until N#
/// can spell a culture.
/// </summary>
public class CodeIntelligenceOutputTests
{
    [Fact]
    public void DiagnosticsToText_UnknownSeverityUsesInvariantFallback()
    {
        var previousCulture = CultureInfo.CurrentCulture;
        CultureInfo.CurrentCulture = new CultureInfo("tr-TR");

        try
        {
            var diagnostics = new List<DiagnosticResult>
            {
                new("NL777", "idi", "Unknown severity edge case", "Program.nl", 1, 1, 1,
                    null, null, null, null, null, null, null)
            };

            var text = OutputFormatter.DiagnosticsToText(diagnostics);

            Assert.Contains("[NL777] IDI", text);
            Assert.DoesNotContain("[NL777] \u0130D\u0130", text);
        }
        finally
        {
            CultureInfo.CurrentCulture = previousCulture;
        }
    }
}
