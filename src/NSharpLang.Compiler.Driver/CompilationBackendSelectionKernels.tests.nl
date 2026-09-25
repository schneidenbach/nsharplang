namespace NSharpLang.Cli

import System
import NSharpLang.Compiler

// THE BACKEND-SELECTION KERNEL BEHIND EVERY COMPILING `nlc` COMMAND.
//
// These blocks replace ONE `[Fact]` deleted from `tests/CliCommandTests.cs`:
// `CompilationBackendSelectionKernels_ValidatesEffectiveBackend` (8 declaration lines, 2
// `Assert.` rows) — the smallest survivor in that file and the one slice 43's finisher sketch
// flagged as possibly unmigratable, because its three calls all pass a `ProjectConfig` and
// `ProjectConfig` is reflection-only on some emit paths.
//
// THE SKETCH'S WORRY WAS PRICED AND IT DOES NOT BIND. The `ProjectConfig`-shaped entry points are
// two thin readers over ONE pure decision function, `EffectiveBackendKind(backendOption,
// projectBackend)`, which takes two plain strings. The whole policy is therefore estate-routable at
// FULL strength, and the `ProjectConfig` arms are covered here as well — measured, not assumed:
// this file constructs a `ProjectConfig` in the estate and emits.
//
// THE DELETED BODY MADE TWO ASSERTIONS AND ONE OF THEM WAS A BARE CALL. `Validate(null, null)` and
// `Validate("  ", config)` asserted nothing at all — they were "does not throw" rows written as
// statements — and only the third row read a message. Every arm is a stated claim below.

// ── the pure decision ─────────────────────────────────────────────────────────
test "an explicit il backend is accepted, in any casing and with any surrounding space" {
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("il", "") == 1
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("IL", "") == 1
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("  il  ", "") == 1
}

test "no backend anywhere is ACCEPTED, not rejected — the empty case is the default" {
    // THE ROW THE DELETED BODY WROTE AS A BARE `Validate(null, null)` STATEMENT. What it was
    // proving is that an unconfigured project is valid, which is a claim about the DEFAULT, not
    // about a missing value being an error.
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("", "") == 1
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("   ", "   ") == 1
}

test "a blank option falls back to the PROJECT's backend, which is the fallback direction" {
    // THE ROW THE DELETED BODY WROTE AS `Validate("  ", config)`. The option is whitespace, so the
    // project's ` il ` is what is judged. A kernel that ignored the project value would still
    // answer 1 here, so the control is the other direction: a blank option over an INVALID
    // project backend must be REJECTED.
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("  ", " il ") == 1
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("  ", "native") == 0
}

test "the OPTION wins over the project's backend, in both directions" {
    // A CONTROL THE DELETED BODY DID NOT HAVE AT ALL. It never passed a non-blank option together
    // with a project backend, so a kernel that always read the project value would have passed it.
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("il", "native") == 1
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("native", "il") == 0
}

test "every backend name that is not il is refused" {
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("native", "") == 0
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("aot", "") == 0
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("ils", "") == 0
    assert CompilationBackendSelectionKernels.EffectiveBackendKind("i", "") == 0
}

// ── the selected value, which is what the message echoes ──────────────────────

test "the selected value is the option when it has content, and the project's otherwise" {
    assert CompilationBackendSelectionKernels.GetSelectedBackendValue("native", null) == "native"
    assert CompilationBackendSelectionKernels.GetSelectedBackendValue(null, null) == null
    assert CompilationBackendSelectionKernels.GetSelectedBackendValue("   ", null) == null
}

// ── the two ProjectConfig-shaped entry points ─────────────────────────────────

test "a validated configuration returns without throwing, for both the null and the il project" {
    // These are the deleted body's two bare-call rows, now stated as claims. A `try` that reaches
    // its last line is the estate's spelling of "did not throw".
    CompilationBackendSelectionKernels.Validate(null, null)

    config := new ProjectConfig()
    config.Backend = " il "
    CompilationBackendSelectionKernels.Validate("  ", config)

    assert CompilationBackendSelectionKernels.GetSelectedBackendValue("  ", config) == " il "
}

test "an invalid project backend throws, and the sentence echoes the value it refused" {
    config := new ProjectConfig()
    config.Backend = "native"

    caught := false
    try {
        CompilationBackendSelectionKernels.Validate(null, config)
    } catch error: InvalidOperationException {
        caught = true
        assert error.Message == "Invalid backend: 'native'. Must be 'il'."
    }

    assert caught
}

test "the refused value in the sentence is the OPTION when the option is what was wrong" {
    // A CONTROL THE DELETED BODY DID NOT HAVE. Its one message row came from a project backend, so
    // a kernel that always echoed `config.Backend` would have passed it. Here the project is valid
    // and the OPTION is not, and the sentence must name the option.
    config := new ProjectConfig()
    config.Backend = "il"

    caught := false
    try {
        CompilationBackendSelectionKernels.Validate("aot", config)
    } catch error: InvalidOperationException {
        caught = true
        assert error.Message == "Invalid backend: 'aot'. Must be 'il'."
    }

    assert caught
}
