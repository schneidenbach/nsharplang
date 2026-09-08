namespace NSharpLang.ReferenceResolution.Tests

import System
import System.Collections.Generic
import System.IO
import System.Reflection

class ResolverRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

func ResolverRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the N# repository root above the native test output.")
}

func ResolverCliDll(): string {
    root := ResolverRepositoryRoot()
    path := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0/Cli.dll")
    if !File.Exists(path) {
        throw new InvalidOperationException("The built N# CLI was not found at " + path)
    }
    return path
}

func ResolverQuote(value: string): string {
    return "\"" + value.Replace("\"", "\\\"") + "\""
}

func ResolverRunProcess(fileName: string, arguments: string, workingDirectory: string): ResolverRun {
    runnerType := Type.GetType("NSharpLang.Cli.DotnetRunner, NSharpLang.Compiler.BootstrapServices")
    if runnerType == null {
        throw new InvalidOperationException("The N# DotnetRunner owner was not loadable from BootstrapServices.")
    }
    methods := runnerType.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly)
    runProcess: MethodInfo? = null
    runProcessCount := 0
    for method in methods {
        if method.get_Name() == "RunProcess" && method.GetParameters().Length == 4 {
            runProcess = method
            runProcessCount = runProcessCount + 1
        }
    }
    if runProcess == null || runProcessCount != 1 {
        throw new InvalidOperationException("Expected exactly one four-parameter DotnetRunner.RunProcess method.")
    }

    invocationArguments := new object?[](4)
    ResolverSetObject(invocationArguments, 0, fileName)
    ResolverSetObject(invocationArguments, 1, arguments)
    ResolverSetObject(invocationArguments, 2, workingDirectory)
    ResolverSetObject(invocationArguments, 3, TimeSpan.FromMinutes(5))
    result := runProcess.Invoke(null, invocationArguments)
    if result == null {
        throw new InvalidOperationException("DotnetRunner.RunProcess returned null.")
    }

    exitCodeField := result.GetType().GetField("ExitCode")
    stdoutField := result.GetType().GetField("Stdout")
    stderrField := result.GetType().GetField("Stderr")
    if exitCodeField == null || stdoutField == null || stderrField == null {
        throw new InvalidOperationException("DotnetRunner.RunProcess result fields were not found.")
    }
    exitCode := Convert.ToInt32(exitCodeField.GetValue(result))
    stdout := Convert.ToString(stdoutField.GetValue(result)) ?? ""
    stderr := Convert.ToString(stderrField.GetValue(result)) ?? ""
    return new ResolverRun(exitCode, stdout, stderr)
}

func ResolverRunCli(arguments: string, workingDirectory: string): ResolverRun {
    return ResolverRunProcess("dotnet", ResolverQuote(ResolverCliDll()) + " " + arguments, workingDirectory)
}

func ResolverNewTempDirectory(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-reference-resolution-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func ResolverWrite(path: string, contents: string) {
    parent := Path.GetDirectoryName(path)
    if parent != null && parent != "" {
        Directory.CreateDirectory(parent)
    }
    File.WriteAllText(path, contents)
}

func ResolverCopyDirectory(source: string, destination: string) {
    Directory.CreateDirectory(destination)
    files := Directory.GetFiles(source, "*", SearchOption.AllDirectories)
    index := 0
    while index < files.Length {
        sourcePath := files[index]
        relative := Path.GetRelativePath(source, sourcePath)
        destinationPath := Path.Combine(destination, relative)
        parent := Path.GetDirectoryName(destinationPath)
        if parent != null && parent != "" {
            Directory.CreateDirectory(parent)
        }
        File.Copy(sourcePath, destinationPath, true)
        index = index + 1
    }
}

func ResolverCandidatePackagesRoots(): string[] {
    roots := new List<string>()
    configured := Environment.GetEnvironmentVariable("NUGET_PACKAGES") ?? ""
    if configured != "" {
        roots.Add(configured)
    }

    profile := Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
    roots.Add(Path.Combine(Path.Combine(profile, ".nuget"), "packages"))
    roots.Add(Path.Combine(Path.Combine(profile, ".nsharp"), "packages"))
    return roots.ToArray()
}

func ResolverPrepareNewtonsoftCache(destinationRoot: string): string {
    roots := ResolverCandidatePackagesRoots()
    source: string? = null
    index := 0
    while index < roots.Length && source == null {
        candidate := Path.Combine(Path.Combine(roots[index], "newtonsoft.json"), "13.0.3")
        if Directory.Exists(candidate) && File.Exists(Path.Combine(Path.Combine(Path.Combine(candidate, "lib"), "net6.0"), "Newtonsoft.Json.dll")) {
            source = candidate
        }
        index = index + 1
    }

    if source == null {
        throw new InvalidOperationException("The installed Newtonsoft.Json 13.0.3 fixture was not found in a local package cache.")
    }

    destination := Path.Combine(Path.Combine(destinationRoot, "newtonsoft.json"), "13.0.3")
    ResolverCopyDirectory(source ?? "", destination)
    return destinationRoot
}

func ResolverWriteProjectReferenceFixture(projectRoot: string) {
    sharedDir := Path.Combine(projectRoot, "Shared")
    Directory.CreateDirectory(sharedDir)
    ResolverWrite(Path.Combine(sharedDir, "SharedLib.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    ResolverWrite(
        Path.Combine(sharedDir, "project.yml"),
        "name: SharedLib\noutputType: library\ntargetFramework: net10.0"
    )
    ResolverWrite(
        Path.Combine(sharedDir, "Shared.nl"),
        "func Greeting(): string {\n    return \"hello from shared\"\n}"
    )

    ResolverWrite(
        Path.Combine(projectRoot, "project.yml"),
        "name: App\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - project: Shared/project.yml\n  - nuget: Newtonsoft.Json\n    version: 13.0.3"
    )
    ResolverWrite(
        Path.Combine(projectRoot, "Program.nl"),
        "import Newtonsoft.Json\n\nfunc main() {\n    print JsonConvert.SerializeObject(Greeting())\n}"
    )
}

func ResolverWriteAotProjectFixture(projectRoot: string, rootOutputType: string) {
    sharedDir := Path.Combine(projectRoot, "Shared")
    Directory.CreateDirectory(sharedDir)
    ResolverWrite(Path.Combine(sharedDir, "SharedLib.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    ResolverWrite(
        Path.Combine(sharedDir, "project.yml"),
        "name: SharedLib\noutputType: library\ntargetFramework: net10.0"
    )
    ResolverWrite(
        Path.Combine(sharedDir, "Shared.nl"),
        "func CountChars(s: string): int {\n    n := 0\n    foreach c in s {\n        n = n + 1\n    }\n    return n\n}"
    )
    ResolverWrite(
        Path.Combine(projectRoot, "project.yml"),
        "name: App\noutputType: " + rootOutputType + "\ntargetFramework: net10.0\ndependencies:\n  - project: Shared/project.yml"
    )
    rootSource := "func Root(): int {\n    return 1\n}"
    if rootOutputType == "exe" {
        rootSource = "func main() {\n    print \"root\"\n}"
    }
    ResolverWrite(Path.Combine(projectRoot, "Program.nl"), rootSource)
}

func ResolverWriteWebFixture(projectRoot: string) {
    sourceRoot := Path.Combine(Path.Combine(ResolverRepositoryRoot(), "examples"), "14-minimal-api")
    File.Copy(Path.Combine(sourceRoot, "project.yml"), Path.Combine(projectRoot, "project.yml"), true)
    File.Copy(Path.Combine(sourceRoot, "Program.nl"), Path.Combine(projectRoot, "Program.nl"), true)
}

func ResolverSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}
