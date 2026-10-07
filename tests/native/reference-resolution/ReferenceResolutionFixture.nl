namespace NSharpLang.ReferenceResolution.Tests

import System
import System.Collections.Generic
import System.Diagnostics
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
    runnerType := Type.GetType("NSharpLang.Cli.DotnetRunner, NSharpLang.Compiler.Driver")
    if runnerType == null {
        throw new InvalidOperationException("The N# DotnetRunner owner was not loadable from Compiler.Driver.")
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

func ResolverRunCliWithWorkers(arguments: string, workingDirectory: string, workers: int): ResolverRun {
    startInfo := new ProcessStartInfo("dotnet", ResolverQuote(ResolverCliDll()) + " " + arguments)
    startInfo.WorkingDirectory = workingDirectory
    startInfo.UseShellExecute = false
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.Environment["NSHARP_COMPILER_WORKERS"] = workers.ToString()
    startInfo.Environment["NLC_NO_DAEMON"] = "1"
    process := Process.Start(startInfo)
    if process == null {
        throw new InvalidOperationException("The N# CLI did not start.")
    }
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(300000) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("The N# CLI did not finish within 300 s: " + arguments)
    }
    exitCode := process.ExitCode
    process.Dispose()
    return new ResolverRun(exitCode, stdoutTask.Result, stderrTask.Result)
}

// The CLI with `NUGET_PACKAGES` pointed at `packagesRoot` in ITS environment block only. The child
// reads the variable at its own entry point; setting it on this process instead would point every
// other resolution this process runs at the throwaway cache for as long as the build took.
func ResolverRunCliInCache(arguments: string, workingDirectory: string, packagesRoot: string): ResolverRun {
    startInfo := new ProcessStartInfo("dotnet", ResolverQuote(ResolverCliDll()) + " " + arguments)
    startInfo.WorkingDirectory = workingDirectory
    startInfo.UseShellExecute = false
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.Environment["NUGET_PACKAGES"] = packagesRoot
    process := Process.Start(startInfo)
    if process == null {
        throw new InvalidOperationException("The N# CLI did not start.")
    }
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(300000) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("The N# CLI did not finish within 300 s: " + arguments)
    }
    exitCode := process.ExitCode
    process.Dispose()
    return new ResolverRun(exitCode, stdoutTask.Result, stderrTask.Result)
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

// SEEDED WHEN THE MACHINE HAS IT, RESTORED WHEN IT DOES NOT. This row runs the program it builds, so
// it needs the real Newtonsoft.Json 13.0.3, not a stand-in. A copy from a local cache saves the
// download; without one the throwaway cache starts empty and the `nlc build` under test restores the
// package into it from nuget.org, as a first build on a clean machine does. The row used to throw
// here instead, so it passed only where an earlier build had happened to restore that version.
func ResolverSeedNewtonsoftCache(destinationRoot: string) {
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

    Directory.CreateDirectory(destinationRoot)
    if source != null {
        ResolverCopyDirectory(source ?? "", Path.Combine(Path.Combine(destinationRoot, "newtonsoft.json"), "13.0.3"))
    }
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
    // THE SHARED SOURCE MUST BE A SHAPE THE COLUMNAR BACKEND DECLINES, because the failure this
    // fixture exists to produce is the AOT path's "requires successful N# columnar emission". It used
    // to be assigning to a struct's own field from its own method, which emits since the call site
    // loads an addressable receiver by address, and then a bare STATIC FIELD as a call receiver,
    // which emits since a static member of the enclosing type is a value binding, and then an
    // `await foreach` inside a generator body. The remaining sentinel is a generic async iterator
    // method: analysis accepts it, while its generic state-machine context is not lowered yet.
    // Replace it when that capability lands rather than deleting this fixture.
    ResolverWrite(
        Path.Combine(sharedDir, "Shared.nl"),
        "import System.Collections.Generic\nimport System.Threading.Tasks\n\nasync func* Pending<T>(value: T): IAsyncEnumerable<T> {\n    await Task.Delay(1)\n    yield value\n}"
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

// A portable two-assembly probe for the compiler-service facade and the ordinary external-member
// route. The active CLI output directory supplies Compiler.dll/Core.dll, so the fixture exercises
// whichever fresh product build is running the native test rather than a checked-in or hardcoded
// candidate. The producer deliberately has no compiler dependency: the consumer proves both the
// external inherited getter/field path and the facade assembly contract independently.
func ResolverWriteFacadeInteropFixture(scratch: string, compilerOutput: string): string {
    producerRoot := Path.Combine(scratch, "producer")
    consumerRoot := Path.Combine(scratch, "consumer")
    producerOutput := Path.Combine(producerRoot, "out")
    consumerOutput := Path.Combine(consumerRoot, "out")
    Directory.CreateDirectory(producerRoot)
    Directory.CreateDirectory(consumerRoot)

    ResolverWrite(
        Path.Combine(producerRoot, "project.yml"),
        "name: FacadeInterop.Library\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    ResolverWrite(
        Path.Combine(producerRoot, "Library.nl"),
        "namespace FacadeInterop.Library\n\npublic class MeterBase {\n    ReadCount: int\n\n    Value: int {\n        get {\n            ReadCount = ReadCount + 1\n            return ReadCount\n        }\n    }\n}\n\npublic class Meter: MeterBase {\n}\n"
    )

    producerDll := Path.Combine(producerOutput, "FacadeInterop.Library.dll")
    compilerDll := Path.Combine(compilerOutput, "Compiler.dll")
    coreDll := Path.Combine(compilerOutput, "NSharpLang.Compiler.Core.dll")
    planDll := Path.Combine(compilerOutput, "NSharpLang.Compiler.Plan.dll")
    emitDll := Path.Combine(compilerOutput, "NSharpLang.Compiler.Emit.dll")
    codeIntelDll := Path.Combine(compilerOutput, "NSharpLang.Compiler.CodeIntel.dll")
    toolingDll := Path.Combine(compilerOutput, "NSharpLang.Compiler.Tooling.dll")
    driverDll := Path.Combine(compilerOutput, "NSharpLang.Compiler.Driver.dll")
    ResolverWrite(
        Path.Combine(consumerRoot, "project.yml"),
        "name: FacadeInterop.Consumer\nversion: 1.0.0\nbackend: il\noutputType: exe\ntargetFramework: net10.0\nentry: Consumer.nl\ndependencies:\n  - dll: " + producerDll + "\n  - dll: " + compilerDll + "\n  - dll: " + coreDll + "\n  - dll: " + planDll + "\n  - dll: " + emitDll + "\n  - dll: " + codeIntelDll + "\n  - dll: " + toolingDll + "\n  - dll: " + driverDll + "\n"
    )
    ResolverWrite(
        Path.Combine(consumerRoot, "Consumer.nl"),
        "namespace FacadeInterop.Consumer\n\nimport System\nimport FacadeInterop.Library\n\nfunc SetInteropObject(values: object?[], index: int, value: object?) {\n    values[index] = value\n}\n\nfunc main() {\n    meter := new Meter()\n    first := meter.Value\n    second := meter.Value\n    reads := meter.ReadCount\n    if first != 1 || second != 2 || reads != 2 {\n        throw new InvalidOperationException(\"Inherited getter/field sequence was not preserved.\")\n    }\n\n    print first\n    print second\n    print reads\n    formatterType := Type.GetType(\"NSharpLang.Compiler.CodeIntelligence.OutputFormatter, NSharpLang.Compiler.Driver\")\n    if formatterType == null {\n        throw new InvalidOperationException(\"Compiler Driver output formatter type was not loadable.\")\n    }\n    formatterMethod := formatterType.GetMethod(\"ErrorToJson\")\n    if formatterMethod == null {\n        throw new InvalidOperationException(\"Compiler Driver output formatter method was not loadable.\")\n    }\n    formatterArgs := new object?[](5)\n    SetInteropObject(formatterArgs, 0, \"interop\")\n    SetInteropObject(formatterArgs, 1, \"ok\")\n    formatterResult := formatterMethod.Invoke(null, formatterArgs)\n    if formatterResult == null {\n        throw new InvalidOperationException(\"Compiler Driver output formatter returned no JSON.\")\n    }\n    print formatterResult.ToString()\n}\n"
    )

    return consumerOutput
}

func ResolverWriteWebFixture(projectRoot: string) {
    sourceRoot := Path.Combine(Path.Combine(ResolverRepositoryRoot(), "examples"), "14-minimal-api")
    File.Copy(Path.Combine(sourceRoot, "project.yml"), Path.Combine(projectRoot, "project.yml"), true)
    File.Copy(Path.Combine(sourceRoot, "Program.nl"), Path.Combine(projectRoot, "Program.nl"), true)
}

func ResolverWriteSharedIdentityWorkspace(scratch: string): string {
    root := Path.Combine(scratch, "workspace")
    firstLibrary := Path.Combine(root, "library-v1")
    secondLibrary := Path.Combine(root, "library-v2")
    firstConsumer := Path.Combine(root, "consumer-v1")
    secondConsumer := Path.Combine(root, "consumer-v2")
    firstOutput := Path.Combine(firstLibrary, "out")
    secondOutput := Path.Combine(secondLibrary, "out")
    Directory.CreateDirectory(root)
    Directory.CreateDirectory(firstLibrary)
    Directory.CreateDirectory(secondLibrary)
    Directory.CreateDirectory(firstConsumer)
    Directory.CreateDirectory(secondConsumer)

    ResolverWrite(Path.Combine(root, "project.yml"), "name: DeterminismWorkspace\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    ResolverWrite(Path.Combine(firstLibrary, "project.yml"), "name: SharedTwin\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    ResolverWrite(Path.Combine(firstLibrary, "Library.nl"), "namespace SharedTwin\n\npublic class Api {\n    public static func Value(): int {\n        return 1\n    }\n}\n")
    ResolverWrite(Path.Combine(secondLibrary, "project.yml"), "name: SharedTwin\nversion: 2.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    ResolverWrite(Path.Combine(secondLibrary, "Library.nl"), "namespace SharedTwin\n\npublic class Api {\n    public static func Value(): int {\n        return 2\n    }\n}\n")

    ResolverWrite(
        Path.Combine(firstConsumer, "project.yml"),
        "name: ConsumerV1\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - dll: " + firstOutput + "/SharedTwin.dll\n"
    )
    ResolverWrite(Path.Combine(firstConsumer, "Consumer.nl"), "namespace ConsumerV1\n\nimport SharedTwin\n\npublic static func Probe(): int {\n    return Api.Value()\n}\n")
    ResolverWrite(
        Path.Combine(secondConsumer, "project.yml"),
        "name: ConsumerV2\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - dll: " + secondOutput + "/SharedTwin.dll\n"
    )
    ResolverWrite(Path.Combine(secondConsumer, "Consumer.nl"), "namespace ConsumerV2\n\nimport SharedTwin\n\npublic static func Probe(): int {\n    return Api.Value()\n}\n")

    firstBuild := ResolverRunCli("build --project " + ResolverQuote(firstLibrary) + " --backend il -o " + ResolverQuote(firstOutput), firstLibrary)
    if firstBuild.ExitCode != 0 {
        throw new InvalidOperationException("Could not build first SharedTwin version: " + firstBuild.Stdout + firstBuild.Stderr)
    }
    secondBuild := ResolverRunCli("build --project " + ResolverQuote(secondLibrary) + " --backend il -o " + ResolverQuote(secondOutput), secondLibrary)
    if secondBuild.ExitCode != 0 {
        throw new InvalidOperationException("Could not build second SharedTwin version: " + secondBuild.Stdout + secondBuild.Stderr)
    }

    return root
}

func ResolverSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}
