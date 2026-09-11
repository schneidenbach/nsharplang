namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// CONTRACTS FOR THE PACKAGE-VERSION → ASSEMBLY-VERSION KERNEL (020 slice 15).
//
// These came out of `tests/ProjectFileTests.cs`, which is deleted. That file asked two questions of
// this surface: four `TryGetAssemblyVersion` inputs, and a ten-case differential sweep of
// `AssemblyVersionKernels.TryParseComponent` against `int.TryParse(component, NumberStyles.None,
// CultureInfo.InvariantCulture, out _)`.
//
// THE DIFFERENTIAL SWEEP BECOMES A TABLE, AND THAT IS A STRENGTHENING. `CultureInfo` cannot be
// reached from the estate in either direction, so the oracle cannot be re-run here — but the oracle
// was never the point. The ten answers `int.TryParse` gives under `NumberStyles.None` are FIXED by
// the .NET numeric-parsing specification (no sign, no leading or trailing white space, no
// thousands separator, decimal digits only, and `0` written into the `out` slot on every failure),
// and they are pinned below as constants. A table cannot silently agree with a subject that has
// drifted, which is exactly what an agreement test can do.
//
// WHAT THE DELETED FILE NEVER ASKED, AND IS ASKED HERE: the one-, two- and five-part shapes, the
// empty and whitespace-only spellings, a null package version, the `-` and `+` metadata cut,
// `FindMetadataIndex` on its own, the exact `out` value on every rejection (the deleted file used
// `out _` and could not see it), and `GetAssemblyVersionOrDefault`, which no C# assertion ever
// called.
func AvuTryVersionText(packageVersion: string?): string {
    parsed := AssemblyVersionUtilities.DefaultAssemblyVersion
    if AssemblyVersionUtilities.TryGetAssemblyVersion(packageVersion, out parsed) {
        return parsed.ToString()
    }

    return "<rejected:" + parsed.ToString() + ">"
}

func AvuComponentAnswer(component: string): string {
    value := -1
    if AssemblyVersionKernels.TryParseComponent(component, out value) {
        return "true:" + value.ToString()
    }

    return "false:" + value.ToString()
}

// ── the four inputs the deleted file carried ──────────────────────────────────────────────────

test "a package version's numeric core becomes a four-part assembly version" {
    parsed := AssemblyVersionUtilities.DefaultAssemblyVersion
    assert AssemblyVersionUtilities.TryGetAssemblyVersion("1.2.3-beta.1+build.5", out parsed)

    // The C# asserted `Assert.Equal(new Version(1, 2, 3, 0), version)`. Both halves are stated:
    // the value equality it asserted, and the rendered text it did not.
    expected := new Version(1, 2, 3, 0)
    assert parsed.Equals(expected)
    assert parsed.ToString() == "1.2.3.0"
    assert parsed.Major == 1
    assert parsed.Minor == 2
    assert parsed.Build == 3
    assert parsed.Revision == 0
}

test "a four-part version with zero-padded components loses the padding and keeps the values" {
    padded := AssemblyVersionUtilities.DefaultAssemblyVersion
    assert AssemblyVersionUtilities.TryGetAssemblyVersion("01.002.0003.0004", out padded)
    expectedPadded := new Version(1, 2, 3, 4)
    assert padded.Equals(expectedPadded)
    assert padded.ToString() == "1.2.3.4"
}

test "A REJECTION LEAVES THE DEFAULT IN THE out SLOT, WHICH `out _` COULD NOT SEE" {
    // Both of the deleted file's rejections, plus the slot value neither of them read. A kernel that
    // rejected but wrote a half-parsed version into the slot would have passed the C# and would ship
    // `1.0.0.0` to some callers and `1.0.0.0`-shaped garbage to others.
    assert AvuTryVersionText("1.+2") == "<rejected:1.0.0.0>"
    assert AvuTryVersionText("1.2147483648") == "<rejected:1.0.0.0>"
}

// ── the shapes the deleted file never spelled ─────────────────────────────────────────────────

test "the accepted arities are TWO, THREE and FOUR components and nothing either side" {
    assert AvuTryVersionText("1") == "<rejected:1.0.0.0>"
    assert AvuTryVersionText("1.2") == "1.2.0.0"
    assert AvuTryVersionText("1.2.3") == "1.2.3.0"
    assert AvuTryVersionText("1.2.3.4") == "1.2.3.4"
    assert AvuTryVersionText("1.2.3.4.5") == "<rejected:1.0.0.0>"
}

test "an absent, empty or whitespace-only package version is rejected without being parsed" {
    assert AvuTryVersionText(null) == "<rejected:1.0.0.0>"
    assert AvuTryVersionText("") == "<rejected:1.0.0.0>"
    assert AvuTryVersionText("   ") == "<rejected:1.0.0.0>"

    // Surrounding whitespace is TRIMMED before anything else looks at the text, so the same version
    // with spaces around it is the same version — a real NuGet metadata shape.
    assert AvuTryVersionText("  1.2.3  ") == "1.2.3.0"
}

test "THE METADATA CUT IS THE FIRST `-` OR `+`, AND EITHER ONE ALONE IS ENOUGH" {
    assert AvuTryVersionText("1.2.3-beta") == "1.2.3.0"
    assert AvuTryVersionText("1.2.3+build.5") == "1.2.3.0"
    assert AvuTryVersionText("1.2.3-rc.1+sha.abc") == "1.2.3.0"

    // The cut is taken at the FIRST marker, so a `+` inside a prerelease label cannot re-open the
    // numeric core. Nothing anywhere said so.
    assert AssemblyVersionUtilities.FindMetadataIndex("1.2.3-beta+build") == 5
    assert AssemblyVersionUtilities.FindMetadataIndex("1.2.3+build-beta") == 5
    assert AssemblyVersionUtilities.FindMetadataIndex("1.2.3") == -1
    assert AssemblyVersionUtilities.FindMetadataIndex("") == -1
    assert AssemblyVersionUtilities.FindMetadataIndex("-1.2") == 0

    // A cut that leaves no numeric core at all is a rejection, not an empty version.
    assert AvuTryVersionText("-beta") == "<rejected:1.0.0.0>"
}

test "the default assembly version is 1.0.0.0 and it is what a rejection falls back to" {
    fallbackDefault := AssemblyVersionUtilities.DefaultAssemblyVersion
    assert fallbackDefault.ToString() == "1.0.0.0"

    rejectedCore := AssemblyVersionUtilities.GetAssemblyVersionOrDefault("1.+2")
    assert rejectedCore.ToString() == "1.0.0.0"

    absent := AssemblyVersionUtilities.GetAssemblyVersionOrDefault(null)
    assert absent.ToString() == "1.0.0.0"

    accepted := AssemblyVersionUtilities.GetAssemblyVersionOrDefault("2.3.4-beta")
    assert accepted.ToString() == "2.3.4.0"
}

// ── the component kernel, as a table rather than as an agreement ──────────────────────────────

test "THE COMPONENT KERNEL ANSWERS EXACTLY WHAT `NumberStyles.None` PARSING ANSWERS" {
    // The ten cases the deleted file swept, with the CLR's answers pinned as constants: no sign, no
    // surrounding white space, digits only, and 0 in the slot on every rejection.
    assert AvuComponentAnswer("0") == "true:0"
    assert AvuComponentAnswer("01") == "true:1"
    assert AvuComponentAnswer("2147483647") == "true:2147483647"
    assert AvuComponentAnswer("2147483648") == "false:0"
    assert AvuComponentAnswer("-1") == "false:0"
    assert AvuComponentAnswer("+1") == "false:0"
    assert AvuComponentAnswer(" 1") == "false:0"
    assert AvuComponentAnswer("1 ") == "false:0"
    assert AvuComponentAnswer("12a") == "false:0"
    assert AvuComponentAnswer("") == "false:0"
}

test "the overflow boundary is walked one value at a time, not sampled" {
    // `2147483647` and `2147483648` are the only two the deleted file looked at, and a kernel that
    // rejected everything above 214748364 would have passed both. The two-digit carry arm and the
    // last-digit arm are separate branches in the kernel and are separated here.
    assert AvuComponentAnswer("214748364") == "true:214748364"
    assert AvuComponentAnswer("2147483640") == "true:2147483640"
    assert AvuComponentAnswer("2147483646") == "true:2147483646"
    assert AvuComponentAnswer("2147483649") == "false:0"
    assert AvuComponentAnswer("2147483650") == "false:0"
    assert AvuComponentAnswer("4294967295") == "false:0"
    assert AvuComponentAnswer("99999999999999999999") == "false:0"
}

test "a rejection is decided before the slot is written, at every position in the text" {
    // The kernel writes 0 into the slot FIRST and returns on the first non-digit, so a bad character
    // at the end cannot leave a partially accumulated value behind.
    assert AvuComponentAnswer("a12") == "false:0"
    assert AvuComponentAnswer("1a2") == "false:0"
    assert AvuComponentAnswer("12a") == "false:0"
    assert AvuComponentAnswer("1.2") == "false:0"
    assert AvuComponentAnswer("\t1") == "false:0"
    assert AvuComponentAnswer("0000000000000000000") == "true:0"
}
