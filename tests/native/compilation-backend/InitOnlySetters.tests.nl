namespace NSharpLang.CompilationBackend.Tests

import System.IO

// Post-construction writes to a reflected init-only property are a semantic error (NL343).
// Legal object initializers preserve the setter's MemberRef custom modifier and run normally.
// JsonSchemaExporterOptions supplies the reflected shape from the default framework references.
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
        assert said.Contains("NL343")
        assert said.Contains("TreatNullObliviousAsNonNullable")
        assert said.Contains("is declared 'init'")
        assert said.Contains("object initializer")
        assert !said.Contains("NL103")
    } finally {
        DeleteTempDirectory(directory)
    }
}

test "an object initializer that writes an init-only property of a referenced type builds and runs" {
    directory := NewTempDirectory()
    try {
        WriteFile(directory, "project.yml", ProjectYml("InitOnlySetter", "il", "exe"))
        WriteFile(
            directory,
            "Program.nl",
            "namespace InitOnlySetter\n\nimport System.Text.Json.Schema\n\nfunc main() {\n    options := new JsonSchemaExporterOptions { TreatNullObliviousAsNonNullable: true }\n    print options.TreatNullObliviousAsNonNullable\n}\n"
        )

        outputDirectory := Path.Combine(directory, "dist")
        build := Nlc("build -o " + Quote(outputDirectory), directory)
        assert build.ExitCode == 0, build.Stdout + build.Stderr
        executed := DotnetApp(Path.Combine(outputDirectory, "InitOnlySetter.dll"), directory)
        assert executed.ExitCode == 0, executed.Stdout + executed.Stderr
        assert executed.Stdout.Trim() == "True"
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
