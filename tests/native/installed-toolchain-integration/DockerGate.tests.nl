namespace NSharpLang.InstalledToolchainIntegration.Tests

import Xunit

// ─── THE DOCKER GATE, AS A `test`-BLOCK ATTRIBUTE ──────────────────────────────────────────────
//
// The deleted `DockerFactAttribute.cs` was 69 lines of C# for one decision, and the decision is not
// about C#: a row that needs a live Docker daemon must be REPORTED as skipped, with a reason, on a
// machine that has none — never quietly dropped and never green because it ran nothing.
//
// N# expresses that with the shipped mechanism rather than an emulation. A `test "…"` block lowers to
// a method, an attribute above it is an attribute on that method, and the compiler withholds its own
// synthesized `[Fact]` when the test already carries a `[Fact]`-derived one. xunit reads `Skip` off
// the attribute it finds, so `nlc test` reports these rows as `skipped` with the reason in
// `results[].errorMessage` and counts them in its summary. `memory/components/cli-toolchain.md`
// documents exactly this shape; there is no runtime skip emulation here, and NL323 still refuses a
// `skip` clause on a `test` block.
//
// THE THREE STATES ARE THE DELETED ATTRIBUTE'S THREE STATES:
//
//   * `NSHARP_RUN_DOCKER_INTEGRATION=1` (or `true`) ⇒ REQUIRED. No skip is set, so the row runs and a
//     missing daemon becomes a FAILURE. This is what CI sets, and it is the whole reason CI cannot
//     pass by skipping: `.github/workflows/build.yml` and `publish.yml` both set it on the step.
//   * unset, daemon answers `docker info` ⇒ the row runs. A developer who has Docker gets the real
//     evidence without opting in, exactly as before.
//   * unset, no daemon (or no `docker` at all, or a daemon that cannot answer in ten seconds) ⇒
//     skipped, and the reason NAMES which of those three it was.
//
// The message is the deleted attribute's message, word for word, so the reason a reader sees in a
// `nlc test` summary is the reason CI's logs used to carry.
sealed class DockerFactAttribute: FactAttribute {
    public constructor() {
        // WRITTEN ONLY WHEN THERE IS A REASON. `Xunit.FactAttribute.Skip` is not a nullable-annotated
        // property — xunit 2.x ships no annotations, so N# reads it as `string!` and refuses a `null`
        // write — and a row that must RUN has to leave the base's own default in place. xunit reads the
        // property off the constructed attribute and treats a null-or-empty reason as "not skipped",
        // so an unconditional write of `""` would work too; not writing at all is the honest spelling
        // and the one that cannot be broken by a version that tightens that check.
        reason := DockerGateSkipReason()
        if reason.Length > 0 {
            Skip = reason
        }
    }
}

// The environment variable's name, spelled ONCE, because the workflows, the docs and the skip
// sentence all quote it and a second spelling is how they drift apart.
func DockerForceEnvironmentVariableName(): string {
    return "NSHARP_RUN_DOCKER_INTEGRATION"
}

func DockerIntegrationForced(): bool {
    value := (System.Environment.GetEnvironmentVariable(DockerForceEnvironmentVariableName()) ?? "").ToLowerInvariant()
    return value == "1" || value == "true"
}

// THE EMPTY STRING IS "RUN", and the attribute above is what turns that into an unwritten `Skip`.
// The reason a row IS skipped is a sentence, never an empty one: an empty reason in a `nlc test`
// summary tells a reader nothing about which prerequisite was missing.
func DockerGateSkipReason(): string {
    if DockerIntegrationForced() {
        return ""
    }

    probe := ProbeDocker()
    if probe.Available {
        return ""
    }

    return "Docker integration prerequisite unavailable: " + probe.Reason + ". Set " + DockerForceEnvironmentVariableName() + "=1 to require this test."
}
