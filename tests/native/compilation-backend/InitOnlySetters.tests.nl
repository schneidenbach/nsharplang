namespace NSharpLang.CompilationBackend.Tests

import System.IO

// ─── WHAT THE IL BACKEND REFUSES RATHER THAN EMITS ────────────────────────────────────────────
//
// FOUND BY CONVERTING tests/LanguageServerTests.cs, WHICH FAILED AT RUN TIME AFTER A CLEAN CHECK.
// `new CompletionParams { Position: p }` — writing an `init`-only property of a REFERENCED type —
// checked clean and then threw
//
//     Method not found: 'Void …TextDocumentPositionParams.set_Position(…Position)'
//
// the first time the emitted assembly ran. `init` is written in metadata as
// `modreq(IsExternalInit)` on the setter's return, and the metadata writer DROPS required custom
// modifiers when it emits a `MemberRef`, so the reference resolved to nothing. That writer
// limitation is already measured and already policy elsewhere in the backend:
// `ColumnarForeachLoopPlanner.IsReferenceablePattern` refuses `ReadOnlySpan<T>`'s enumerator for
// exactly it, with exactly the same "Method not found" symptom, and the planned BCL property-write
// door already refused the shape through `IsInitOnlySetter`. Two doors did not, and both are closed
// now — so the failure is a diagnostic instead of a crash.
//
// THE TWO ROWS BELOW MEASURE THE TWO SPELLINGS, AND THEY DO NOT GET THE SAME SENTENCE. The
// ASSIGNMENT form is refused in the IL emitter, which has a decline channel that carries a message,
// so its diagnostic names the property and says why. The OBJECT-INITIALIZER form is refused earlier,
// in `ColumnarConstructionPlanner`, which has no reason channel at all and can only answer "no" — so
// the user gets the enclosing site (`emit.local.initializer` / `emit.return.expression`) and no
// sentence about the setter. Both are honest; only one is helpful, and the difference is recorded
// here rather than papered over, because giving the construction planner a reason channel is the
// follow-up this asymmetry is asking for.
//
// THE SUBJECT IS A BCL TYPE, DELIBERATELY. `System.Text.Json.Schema.JsonSchemaExporterOptions` has a
// public parameterless constructor and one `init`-only property, and `System.Text.Json` is in the
// default reference set — so these rows need no dependency and cannot go stale because a package
// moved. Every C# `record` is this shape too; the BCL type is simply the one every project can see.
func WriteInitOnlyProbe(directory: string, body: string) {
    WriteFile(directory, "project.yml", ProjectYml("InitOnlySetter", "il", "library"))
    WriteFile(directory, "Probe.nl", "namespace InitOnlySetter\n\nimport System.Text.Json.Schema\n\n" + body)
}

// `nlc check --text` writes its diagnostics to stderr and only its summary to stdout, so a sentence
// is read from BOTH streams joined — the trap tests/native/diagnostic-honesty records, and the
// reason a stdout-only read here would approve anything.
func SaidByCheck(run: ProcessRun): string {
    return run.Stdout + "\n" + run.Stderr
}

test "assigning an init-only property of a referenced type is refused, and the message names the property" {
    directory := NewTempDirectory()
    try {
        WriteInitOnlyProbe(
            directory,
            "func Build(): JsonSchemaExporterOptions {\n    options := new JsonSchemaExporterOptions()\n    options.TreatNullObliviousAsNonNullable = true\n    return options\n}\n"
        )

        run := Nlc("check --project " + Quote(directory) + " --text", directory)

        assert run.ExitCode == 1

        said := SaidByCheck(run)
        assert said.Contains("NL103")
        assert said.Contains("emit.member-assignment.unreferenceable-setter")
        assert said.Contains("JsonSchemaExporterOptions.TreatNullObliviousAsNonNullable")
        assert said.Contains("required custom modifier")
        assert said.Contains("MemberRef")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "an object initializer that writes an init-only property of a referenced type is refused too" {
    directory := NewTempDirectory()
    try {
        WriteInitOnlyProbe(
            directory,
            "func Build(): JsonSchemaExporterOptions {\n    return new JsonSchemaExporterOptions { TreatNullObliviousAsNonNullable: true }\n}\n"
        )

        run := Nlc("check --project " + Quote(directory) + " --text", directory)

        assert run.ExitCode == 1

        // The construction planner has no reason channel, so the site is the enclosing expression and
        // the setter is not named. What this row pins is that the program does NOT build — which is
        // the whole point, because it used to build and then die.
        said := SaidByCheck(run)
        assert said.Contains("NL103")
        assert said.Contains("Columnar emission is required")
    } finally {
        DeleteTempDirectory(directory)
    }
}

// THE NEIGHBOUR THAT KEEPS BOTH ROWS HONEST. An ORDINARY settable property of the same shape of type
// — a referenced class, written both ways — still emits and still runs, so the refusals above are
// about the MODIFIER and not about referenced types, object initializers, or property writes.
test "an ordinary settable property of a referenced type still emits, written either way" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("OrdinarySetter", "il", "exe"))
        WriteFile(
            directory,
            "Program.nl",
            "import System.Text.Json\n\nfunc main() {\n    initialized := new JsonSerializerOptions { WriteIndented: true }\n    assigned := new JsonSerializerOptions()\n    assigned.WriteIndented = true\n    print initialized.WriteIndented.ToString() + \" \" + assigned.WriteIndented.ToString()\n}\n"
        )

        outputDirectory := Path.Combine(directory, "dist")
        run := Nlc("build -o " + Quote(outputDirectory), directory)

        assert run.ExitCode == 0
        assert run.Stdout.Contains("Build successful!")

        executed := DotnetApp(Path.Combine(outputDirectory, "OrdinarySetter.dll"), directory)
        assert executed.ExitCode == 0
        assert executed.Stdout.Contains("True True")
    } finally {
        DeleteTempDirectory(directory)
    }
}
