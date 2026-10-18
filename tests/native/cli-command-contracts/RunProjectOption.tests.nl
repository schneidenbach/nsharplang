namespace NSharpLang.CliCommandContracts.Tests

import System
import System.IO

// `nlc run --project <dir>` (issue 250): `nlc run` was the one project command without `--project`,
// and read the flag as the source file to run ("File not found: --project").

func WriteRunProject(directory: string, projectName: string, message: string) {
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: " + projectName + "\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\n")
    File.WriteAllText(Path.Combine(directory, "Program.nl"), "import System\n\nfunc main(args: string[]) {\n    print \"" + message + "\"\n    Console.WriteLine(\"args=\" + String.Join(\"|\", args))\n}\n")
}

test "nlc run --project builds and runs a project that is not in the current directory" {
    directory := NewTempDirectory("nlc-run-project")
    try {
        app := Path.Combine(directory, "app")
        Directory.CreateDirectory(app)
        WriteRunProject(app, "RunProjectProbe", "from-app")
        run := Nlc("run --project \"" + app + "\"")
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout.Contains("from-app"), run.Stdout
        assert !run.Stderr.Contains("File not found"), run.Stderr
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc run --project resolves a relative directory against the current directory" {
    directory := NewTempDirectory("nlc-run-project-relative")
    try {
        app := Path.Combine(Path.Combine(directory, "src"), "app")
        Directory.CreateDirectory(app)
        WriteRunProject(app, "RunRelativeProbe", "from-relative")
        run := RunProcess("dotnet", "\"" + CliDll() + "\" run --project src/app", directory)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout.Contains("from-relative"), run.Stdout
    } finally {
        Directory.Delete(directory, true)
    }
}

test "everything after -- reaches the program, including words that are nlc options" {
    directory := NewTempDirectory("nlc-run-program-args")
    try {
        WriteRunProject(directory, "RunArgsProbe", "with-args")
        run := Nlc("run --project \"" + directory + "\" -- --help --project \"two words\" plain")
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout.Contains("args=--help|--project|two words|plain"), run.Stdout
        assert !run.Stdout.Contains("Usage: nlc run"), run.Stdout
    } finally {
        Directory.Delete(directory, true)
    }
}

test "nlc run --project reports a missing directory, a missing project file and a missing value" {
    directory := NewTempDirectory("nlc-run-project-errors")
    try {
        missing := Nlc("run --project \"" + Path.Combine(directory, "nope") + "\"")
        assert missing.ExitCode == 1
        assert missing.Stderr.Contains("Project directory not found"), missing.Stderr

        noProject := Nlc("run --project \"" + directory + "\"")
        assert noProject.ExitCode == 1
        assert noProject.Stderr.Contains("No project.yml found in"), noProject.Stderr

        noValue := Nlc("run --project")
        assert noValue.ExitCode == 1
        assert noValue.Stderr.Contains("--project requires a directory"), noValue.Stderr

        WriteRunProject(directory, "RunConflictProbe", "conflict")
        both := Nlc("run --project \"" + directory + "\" \"" + Path.Combine(directory, "Program.nl") + "\"")
        assert both.ExitCode == 1
        assert both.Stderr.Contains("Cannot combine --project with a source file"), both.Stderr
    } finally {
        Directory.Delete(directory, true)
    }
}
