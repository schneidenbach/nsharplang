namespace NSharpLang.Compiler


// THE COLOUR DECISION, CROSSED WITHOUT A PROCESS.
//
// `Decide` is a pure function of four readings, so every row below is a fact about the POLICY rather
// than about this machine's terminal. The one function that touches the world,
// `ShouldColorizeStandardError`, does nothing but take those four readings and hand them here; it is
// proven end-to-end by `tests/native/cli-command-contracts`, which spawns the shipped `nlc` and
// counts ESC bytes, because only a process can show which stream a sequence reached.
//
// THE PRECEDENCE IS THE WHOLE CONTRACT, so it is crossed as a LADDER: each row below turns on the
// signal above it and proves the higher one still wins. A policy whose rows are only tested in
// isolation is a policy whose precedence is untested.

// ── The stream test, which is the default ───────────────────────────────────────────────────────
test "with no flag and no environment, the stream decides" {
    assert DiagnosticColorPolicy.Decide(null, null, null, false)
    assert !DiagnosticColorPolicy.Decide(null, null, null, true)
}

// ── NO_COLOR beats the stream ───────────────────────────────────────────────────────────────────
test "NO_COLOR disables colour even on a terminal" {
    assert !DiagnosticColorPolicy.Decide(null, "1", null, false)
    assert !DiagnosticColorPolicy.Decide(null, "anything at all", null, false)
    assert !DiagnosticColorPolicy.Decide(null, "0", null, false)
}

test "an EMPTY NO_COLOR is not a request, because that is what an unset variable looks like" {
    // no-color.org: present AND non-empty. A shell that exports every name it knows would otherwise
    // silently disable colour for a user who never asked.
    assert DiagnosticColorPolicy.Decide(null, "", null, false)
    assert !DiagnosticColorPolicy.Decide(null, "", null, true)
}

// ── FORCE_COLOR beats the stream, and NO_COLOR beats FORCE_COLOR ────────────────────────────────
test "FORCE_COLOR colours a redirected stream, which is what a CI log viewer needs" {
    assert DiagnosticColorPolicy.Decide(null, null, "1", true)
    assert DiagnosticColorPolicy.Decide(null, null, "true", true)
}

test "FORCE_COLOR=0 reads as off, not as present-therefore-on" {
    assert !DiagnosticColorPolicy.Decide(null, null, "0", true)
    assert DiagnosticColorPolicy.Decide(null, null, "0", false)
}

test "NO_COLOR WINS over FORCE_COLOR — the user who opted out globally does not ask twice" {
    assert !DiagnosticColorPolicy.Decide(null, "1", "1", false)
    assert !DiagnosticColorPolicy.Decide(null, "1", "1", true)
}

// ── The flag beats everything ───────────────────────────────────────────────────────────────────
test "an explicit flag outranks both environment variables and the stream" {
    // always, over a redirected stream AND over NO_COLOR.
    assert DiagnosticColorPolicy.Decide("--color=always", "1", null, true)
    assert DiagnosticColorPolicy.Decide("--color", "1", null, true)

    // never, over a terminal AND over FORCE_COLOR.
    assert !DiagnosticColorPolicy.Decide("--color=never", null, "1", false)
    assert !DiagnosticColorPolicy.Decide("--no-color", null, "1", false)
}

test "auto and an unrecognised when fall back to the stream rather than failing" {
    assert DiagnosticColorPolicy.Decide("--color=auto", null, null, false)
    assert !DiagnosticColorPolicy.Decide("--color=auto", null, null, true)

    // A colour flag is not worth refusing to compile over, so a typo degrades to the default.
    assert DiagnosticColorPolicy.Decide("--color=purple", null, null, false)
    assert !DiagnosticColorPolicy.Decide("--color=purple", null, null, true)
}

// ── The flag's spellings and how one is found on a command line ─────────────────────────────────
test "the mode parser reads every spelling the help text promises, and the aliases people type" {
    assert DiagnosticColorPolicy.ParseMode(null) == 0
    assert DiagnosticColorPolicy.ParseMode("--color=auto") == 0

    assert DiagnosticColorPolicy.ParseMode("--color") == 1
    assert DiagnosticColorPolicy.ParseMode("--color=always") == 1
    assert DiagnosticColorPolicy.ParseMode("--color=yes") == 1
    assert DiagnosticColorPolicy.ParseMode("--color=force") == 1

    assert DiagnosticColorPolicy.ParseMode("--no-color") == 2
    assert DiagnosticColorPolicy.ParseMode("--color=never") == 2
    assert DiagnosticColorPolicy.ParseMode("--color=no") == 2
    assert DiagnosticColorPolicy.ParseMode("--color=none") == 2
}

test "a flag that is not a colour flag is not read as one" {
    assert !DiagnosticColorPolicy.IsColorOption("--release")
    assert !DiagnosticColorPolicy.IsColorOption("--colors")
    assert !DiagnosticColorPolicy.IsColorOption("colour")
    assert !DiagnosticColorPolicy.IsColorOption("")

    assert DiagnosticColorPolicy.IsColorOption("--color")
    assert DiagnosticColorPolicy.IsColorOption("--no-color")
    assert DiagnosticColorPolicy.IsColorOption("--color=never")

    // `--colors` is not a colour flag, so `ParseMode` must not claim it either.
    assert DiagnosticColorPolicy.ParseMode("--colors") == 0
}

test "the LAST colour flag on the line wins, so an explicit override beats a shell alias" {
    argv := new string[](4)
    argv[0] = "nlc"
    argv[1] = "build"
    argv[2] = "--color=always"
    argv[3] = "--color=never"
    assert DiagnosticColorPolicy.FindColorOption(argv) == "--color=never"
    assert DiagnosticColorPolicy.ParseMode(DiagnosticColorPolicy.FindColorOption(argv)) == 2
}

test "a command line with no colour flag answers null, and so does no command line at all" {
    argv := new string[](3)
    argv[0] = "nlc"
    argv[1] = "build"
    argv[2] = "--release"
    assert DiagnosticColorPolicy.FindColorOption(argv) == null
    assert DiagnosticColorPolicy.FindColorOption(null) == null

    empty := new string[](0)
    assert DiagnosticColorPolicy.FindColorOption(empty) == null
}

// ── The mode ordinals are named, so a caller never spells a bare integer ─────────────────────────
test "the three mode ordinals are the ones the parser answers" {
    assert DiagnosticColorPolicy.ModeAuto() == 0
    assert DiagnosticColorPolicy.ModeAlways() == 1
    assert DiagnosticColorPolicy.ModeNever() == 2
}
