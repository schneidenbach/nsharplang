namespace NSharpLang.Cli.Commands

// THE `nlc init` OPTION KERNEL AND THE THREE FILES IT WRITES.
//
// This replaces `InitCommandKernels_SummarizesOptions`, deleted whole from
// `tests/CliCommandTests.cs`. Nothing in that body reached a process or the filesystem.
//
// THE `exe` YAML IS THE SAME TEXT `ProjectFileParser.GenerateTemplate` PRODUCES, and that
// equality is the load-bearing row: `nlc init` and `nlc new` must lay down byte-identical
// project files, or a user who initialised in place gets a subtly different project from one who
// scaffolded. The `library` spelling then differs from it in exactly two ways — no `entry:` line,
// and `outputType: library` — and both are pinned, the absence one as an absence.

test "init option summary reads the name, type, force and help flags" {
    summary := InitCommandKernels.GetOptionSummary(["--name", "MyLib", "--type", "library", "--force", "-h"])

    assert summary.NameOption == "MyLib"
    assert summary.TypeOption == "library"
    assert summary.Force
    assert summary.ShowHelp
}

test "init option values are taken permissively, so a flag can be consumed as a value" {
    summary := InitCommandKernels.GetOptionSummary(["--name", "--force", "--type", "--help"])

    assert summary.NameOption == "--force"
    assert summary.TypeOption == "--help"
    assert summary.Force
    assert summary.ShowHelp
}

test "init asks for help on the bare word and on a trailing short flag" {
    assert InitCommandKernels.GetOptionSummary(["help"]).ShowHelp
    assert InitCommandKernels.GetOptionSummary(["ignored", "-h"]).ShowHelp
}

test "the init help text names the command, its usage and its failure banner" {
    helpText := InitCommandKernels.GetHelpText()

    assert helpText.Contains("N# Init")
    assert helpText.Contains("Usage: nlc init [options]")
    assert helpText.Contains("Initialization failed")
}

test "every init sentence is spelled by a kernel, character for character" {
    assert InitCommandKernels.GetInvalidTypeMessage("service")
        == "Invalid type 'service'. Expected 'exe' or 'library'."
    assert InitCommandKernels.GetProjectFileExistsMessage()
        == "project.yml already exists. Use --force to overwrite."
    assert InitCommandKernels.GetCreatedFileMessage("Program.nl") == "Created: Program.nl"
    assert InitCommandKernels.GetSuccessMessage() == "N# project initialized. Run 'nlc build' to compile."
    assert InitCommandKernels.GetFailedMessage("denied") == "Init failed: denied"
}

test "the exe project.yml init writes is byte-identical to the one nlc new generates" {
    exeYaml := InitCommandKernels.GetProjectYamlText("DemoApp", "exe")

    assert exeYaml == ProjectFileParser.GenerateTemplate("DemoApp")
    assert exeYaml.Contains("entry: Program.nl\n")
    assert exeYaml.Contains("outputType: exe\n")
}

test "the library project.yml drops the entry line and says library, and keeps everything else" {
    libraryYaml := InitCommandKernels.GetProjectYamlText("DemoLib", "library")

    assert libraryYaml.Contains("name: DemoLib\n")
    assert libraryYaml.Contains("outputType: library\n")
    assert !libraryYaml.Contains("entry: Program.nl")
    assert libraryYaml.Contains("# Add your dependencies here\n")
    assert libraryYaml.Contains("  profile: default\n")
}

test "the csproj init writes is the one-line SDK reference, and the program is the hello world" {
    assert InitCommandKernels.GetCsprojText() == "<Project Sdk=\"NSharpLang.Sdk\" />\n"
    assert InitCommandKernels.GetProgramSourceText() == "func main() {\n    print \"Hello, N#!\"\n}"
}
