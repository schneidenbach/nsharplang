namespace NSharpLang.Cli.Commands

// THE `nlc pack` MESSAGE KERNELS, STATED AS SENTENCES.
//
// These blocks exist because of ONE `[Fact]` in `tests/CliParityAuditTests.cs`:
// `PackCommand_NoProjectYml_Fails`. That body is the one member of slice 45's thirty that does NOT
// migrate, because the command it drives — `PackCommand` — is still C#-owned
// (`src/NSharpLang.Cli/Commands/PackCommand.cs`). It reached bucket (a) only through a TAUTOLOGY:
// its third row compared `PackCommand`'s stderr against a LIVE CALL to
//
//     ProgramCommandKernels.GetErrorLine(PackCommandKernels.GetMissingProjectFileTextMessage())
//
// so both sides were computed by the same two kernels and agreed by construction. Neither side ever
// said what the sentence IS, and a kernel and a command wrong in the same way would have passed.
//
// The C# body is de-tautologised in place — it now asserts the literal stderr — and the kernels'
// own text is pinned here, independently. The sentence is now stated on both sides and neither can
// drift into agreement with a wrong answer. When `PackCommand.cs` retires, this file stays.
//
// THE PAIR IS THE POINT: `pack` has TWO missing-project sentences, one for humans and one for JSON,
// and they are DIFFERENT. The deleted-in-spirit assertion only ever saw the text one.

// ── the missing-project pair ──────────────────────────────────────────────────

test "the text missing-project sentence is two lines and names the CURRENT DIRECTORY" {
    assert PackCommandKernels.GetMissingProjectFileTextMessage() == "No project.yml found in current directory.\nRun 'nlc new <name>' to create a project."
}

test "the JSON missing-project sentence is ONE line and does NOT name a directory" {
    // A JSON consumer receives a single-line message; embedding the newline the text arm uses would
    // put a raw line break inside an envelope field.
    assert PackCommandKernels.GetMissingProjectFileJsonMessage() == "No project.yml found. Run 'nlc new <name>' to create a project."
}

test "the two missing-project sentences are DIFFERENT, and only one of them wraps" {
    // THE CLAIM THE TAUTOLOGY COULD NOT MAKE. Reading either kernel alone cannot show that the
    // command picks the right one for the mode it is in.
    textMessage := PackCommandKernels.GetMissingProjectFileTextMessage()
    jsonMessage := PackCommandKernels.GetMissingProjectFileJsonMessage()

    assert (textMessage == jsonMessage) == false
    assert textMessage.Contains("\n")
    assert (jsonMessage.Contains("\n")) == false
    // …and both point the user at the same remedy
    assert textMessage.Contains("Run 'nlc new <name>' to create a project.")
    assert jsonMessage.Contains("Run 'nlc new <name>' to create a project.")
}

// ── what the C# body actually observes, composed from both kernels ────────────

test "the stderr line the missing-project failure writes is the error prefix over the text arm" {
    // THE EXACT VALUE the de-tautologised C# body now asserts as a literal. Stated here as a
    // COMPOSITION so the two halves stay connected — and stated there as a LITERAL so neither half
    // can move without one of the two blocks going red.
    assert ProgramCommandKernels.GetErrorLine(PackCommandKernels.GetMissingProjectFileTextMessage())
        == "Error: No project.yml found in current directory.\nRun 'nlc new <name>' to create a project."
}

test "the error prefix is applied once, at the front, and is not repeated per line" {
    // A two-line message gets ONE prefix, not one per line — which is why the literal above has
    // `Error: ` only at the start.
    prefixed := ProgramCommandKernels.GetErrorLine(PackCommandKernels.GetMissingProjectFileTextMessage())

    assert prefixed.StartsWith("Error: ")
    assert prefixed.IndexOf("Error: ", 1, System.StringComparison.Ordinal) < 0
}

// ── the neighbouring failure sentences, which share the same two-arm shape ────

test "the missing-project pair is the ONLY pack pair whose two arms actually differ" {
    // MEASURED, AND IT OVERTURNED THE OBVIOUS READING. `pack` keeps a TEXT kernel and a JSON kernel
    // for each of its three failure families — so the shape suggests three deliberate splits — but
    // only ONE pair carries different words. The other two are the same sentence behind two names,
    // which is a maintenance hazard rather than a contract: an edit to one arm is invisible.
    //
    // Recorded, not fixed. What matters for the de-tautologised C# body is that the pair it names
    // IS one of the differing ones, so picking the wrong arm there is observable.
    assert PackCommandKernels.GetMissingProjectFileTextMessage() != PackCommandKernels.GetMissingProjectFileJsonMessage()

    assert PackCommandKernels.GetMissingVersionTextMessage() == PackCommandKernels.GetMissingVersionJsonMessage()
    assert PackCommandKernels.GetMissingVersionTextMessage() == "Package version is required. Set version in project.yml or pass --version."

    assert PackCommandKernels.GetParseFailedTextMessage("bad indent") == PackCommandKernels.GetParseFailedJsonMessage("bad indent")
    assert PackCommandKernels.GetParseFailedTextMessage("bad indent") == "Failed to parse project.yml: bad indent"
}
