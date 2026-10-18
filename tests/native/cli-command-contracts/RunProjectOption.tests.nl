namespace NSharpLang.CliCommandContracts.Tests

import System
import System.Diagnostics
import System.IO
import System.Security.Cryptography

// `nlc run --project <dir>` AND THE REBUILD THAT MUST NOT TOUCH WHAT A PROCESS HAS OPEN.
//
// Issue 250: `nlc run` was the one project command without `--project`, and read the flag as the
// source file to run ("File not found: --project"). Issue 253: `nlc build` rewrote the output
// assembly in place, so a program still running from it read new bytes through the old mapping.

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

func ProbeArgvProject(directory: string) {
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: ArgvProbe\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\n")
    File.WriteAllText(Path.Combine(directory, "Program.nl"), "import System\n\nfunc main(args: string[]) {\n    for argument in args {\n        Console.WriteLine(\"[\" + argument + \"]\")\n    }\n}\n")
}

test "program arguments reach the program byte for byte, whatever quoting they need" {
    directory := NewTempDirectory("nlc-run-argv")
    try {
        ProbeArgvProject(directory)
        startInfo := new ProcessStartInfo { FileName: "dotnet" }
        startInfo.ArgumentList.Add(CliDll())
        for argument in ["run", "--project", directory, "--", "a\"b", "C:\\dir\\", "", "two words", "--help", "tab\there"] {
            startInfo.ArgumentList.Add(argument)
        }

        startInfo.WorkingDirectory = Path.GetTempPath()
        startInfo.RedirectStandardOutput = true
        startInfo.RedirectStandardError = true
        startInfo.UseShellExecute = false
        process := new Process { StartInfo: startInfo }
        process.Start()
        stdout := process.StandardOutput.ReadToEnd()
        stderr := process.StandardError.ReadToEnd()
        process.WaitForExit()
        exitCode := process.ExitCode
        process.Dispose()

        assert exitCode == 0, stdout + stderr
        expected := "[a\"b]" + Environment.NewLine + "[C:\\dir\\]" + Environment.NewLine + "[]" + Environment.NewLine + "[two words]" + Environment.NewLine + "[--help]" + Environment.NewLine + "[tab\there]" + Environment.NewLine
        assert stdout.EndsWith(expected), stdout
    } finally {
        Directory.Delete(directory, true)
    }
}

func ReadHeldBytes(held: FileStream): byte[] {
    held.Position = 0
    bytes := new byte[]((int)held.Length)
    read := 0
    while read < bytes.Length {
        count := held.Read(bytes, read, bytes.Length - read)
        if count == 0 {
            break
        }

        read = read + count
    }

    return bytes
}

test "rebuilding never changes the bytes of an assembly a process still holds open" {
    directory := NewTempDirectory("nlc-rebuild-held")
    try {
        WriteRunProject(directory, "RebuildHeldProbe", "first")
        first := Nlc("build --project \"" + directory + "\"")
        assert first.ExitCode == 0, first.Stdout + first.Stderr

        assemblyPath := Path.Combine(Path.Combine(Path.Combine(Path.Combine(directory, "bin"), "Debug"), "net10.0"), "RebuildHeldProbe.dll")
        // A FileStream buffer size of 1 avoids its managed read-ahead buffer; the OS may still cache pages.
        // Read | Delete sharing lets Windows replace the path while this handle keeps reading the old file.
        // This matches the loader's sharing behavior for a mapped assembly.
        held := new FileStream(assemblyPath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete, 1)
        try {
            before := ReadHeldBytes(held)
            File.WriteAllText(Path.Combine(directory, "Program.nl"), "func main() {\n    print \"second-build-with-a-longer-message-than-the-first\"\n}\n")
            second := Nlc("build --project \"" + directory + "\"")
            assert second.ExitCode == 0, second.Stdout + second.Stderr

            after := ReadHeldBytes(held)
            assert after.Length == before.Length, "the held assembly changed length"
            assert Convert.ToHexString(SHA256.HashData(after)) == Convert.ToHexString(SHA256.HashData(before)), "the held assembly's bytes changed"
            assert !Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(assemblyPath))).Equals(Convert.ToHexString(SHA256.HashData(before))), "the rebuilt assembly on disk did not change"
        } finally {
            held.Dispose()
        }

        for leftover in Directory.GetFiles(Path.GetDirectoryName(assemblyPath) ?? directory, "*.tmp") {
            assert false, "a temporary file was left beside the output: " + leftover
        }
    } finally {
        Directory.Delete(directory, true)
    }
}
