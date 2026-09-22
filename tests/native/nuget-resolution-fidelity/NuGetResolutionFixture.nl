namespace NSharpLang.NuGetResolutionFidelity.Tests

import System
import System.Diagnostics
import System.IO
import System.Runtime.Loader

// ─── ONE PACKAGES FOLDER, TWO DOORS, AND THE RULES THAT DECIDE WHAT IS IN IT ──────────────────
//
// `nlc build` resolves a project's `nuget:` references itself: it walks the graph, picks a version
// per package id, and unzips whatever it downloads into the SAME global packages folder that
// `dotnet restore` reads. Two contracts follow from that and neither had a row before:
//
//   * WHICH VERSION. NuGet's rule is nearest-wins — a declared reference is at distance zero and
//     beats any transitive occurrence however the list is ordered, and two occurrences equally far
//     out unify on the higher version. Resolving each root's closure in turn and keeping the first
//     version reached instead makes the ORDER of the list decide, so a pin written after a package
//     that already carries that dependency is silently ignored.
//   * WHAT AN INSTALL IS. Unzipping content into `<packages>/<id>/<version>/` does not install a
//     package. NuGet looks for install markers beside the content, and a directory carrying only
//     the extracted files is invisible to `dotnet restore`, which answers NU1101 for a package
//     that is already on disk.
//
// The first row is fully offline: it builds a package graph by hand in a throwaway cache, so it
// measures resolution and nothing else. The second row must install a real package through the
// real download path to have any markers to read — but the ASSERTION is offline, a restore with
// every source cleared, which can only succeed if the cache `nlc build` wrote is a cache NuGet
// understands.
class ResolutionRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }

    func Output(): string {
        return Stdout + Stderr
    }
}

func ResolutionCommandTimeoutMilliseconds(): int {
    return 20 * 60 * 1000
}

func ResolutionRepositoryRoot(): string {
    current: string? = Path.GetFullPath(Environment.CurrentDirectory)
    while current != null {
        candidate := current ?? ""
        if File.Exists(Path.Combine(candidate, "AGENTS.md")) && Directory.Exists(Path.Combine(candidate, "src")) && Directory.Exists(Path.Combine(candidate, "tests")) {
            return candidate
        }

        parent := Path.GetDirectoryName(candidate)
        if parent == null || parent == "" || parent == candidate {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the N# repository root.")
}

func ResolutionCliPath(root: string): string {
    return Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0/Cli.dll")
}

func ResolutionQuote(value: string): string {
    return "\"" + value.Replace("\"", "\\\"") + "\""
}

// Both pipes are drained as tasks before the wait: a chatty child deadlocks against a full pipe
// buffer otherwise, and the gate parses this project's own stdout as JSON, so nothing a child
// prints may reach it.
func ResolutionRunDotnet(arguments: string, workingDirectory: string): ResolutionRun {
    startInfo := new ProcessStartInfo { FileName: "dotnet", Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdoutTask := process.StandardOutput.ReadToEndAsync()
    stderrTask := process.StandardError.ReadToEndAsync()
    if !process.WaitForExit(ResolutionCommandTimeoutMilliseconds()) {
        process.Kill(true)
        process.WaitForExit()
        process.Dispose()
        throw new TimeoutException("Process 'dotnet " + arguments + "' did not complete within " + ResolutionCommandTimeoutMilliseconds().ToString() + " ms.")
    }

    exitCode := process.ExitCode
    process.Dispose()
    return new ResolutionRun(exitCode, stdoutTask.Result, stderrTask.Result)
}

func ResolutionRequireSuccess(result: ResolutionRun, operation: string) {
    if result.ExitCode != 0 {
        throw new InvalidOperationException(operation + " failed with exit " + result.ExitCode.ToString() + ":\n" + result.Output())
    }
}

// The child inherits this process's environment because `UseShellExecute` is false and nothing
// rewrites the child's own block, so pointing `NUGET_PACKAGES` here points BOTH doors at the
// throwaway cache — `nlc build` reads it through the same accessor `dotnet` does.
func ResolutionRunInCache(arguments: string, workingDirectory: string, packagesCache: string): ResolutionRun {
    previous := Environment.GetEnvironmentVariable("NUGET_PACKAGES")
    Environment.SetEnvironmentVariable("NUGET_PACKAGES", packagesCache)
    try {
        return ResolutionRunDotnet(arguments, workingDirectory)
    } finally {
        Environment.SetEnvironmentVariable("NUGET_PACKAGES", previous)
    }
}

func ResolutionOutputDirectory(projectDirectory: string): string {
    return Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), "net10.0")
}

func ResolutionWriteProject(projectDirectory: string, projectYml: string, sourceFileName: string, source: string) {
    Directory.CreateDirectory(projectDirectory)
    File.WriteAllText(Path.Combine(projectDirectory, "project.yml"), projectYml)
    File.WriteAllText(Path.Combine(projectDirectory, sourceFileName), source)
}

// ─── A PACKAGE GRAPH BUILT BY HAND, SO THE ROW NEVER TOUCHES THE NETWORK ─────────────────────
//
// A version directory is `<packages>/<lowercased id>/<lowercased version>/` holding the nuspec and
// the framework-keyed `lib` folders, which is exactly the layout `nlc build` reads. Writing one
// directly is what makes the nearest-wins row offline AND deterministic: no published package has
// to keep carrying the version this row needs.
func ResolutionPackageDirectory(packagesCache: string, packageId: string, version: string): string {
    return Path.Combine(Path.Combine(packagesCache, packageId.ToLowerInvariant()), version.ToLowerInvariant())
}

func ResolutionWriteNuspec(versionDirectory: string, packageId: string, version: string, dependenciesXml: string) {
    Directory.CreateDirectory(versionDirectory)
    text := "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
    text = text + "<package xmlns=\"http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd\">\n"
    text = text + "  <metadata>\n"
    text = text + "    <id>" + packageId + "</id>\n"
    text = text + "    <version>" + version + "</version>\n"
    text = text + "    <authors>nsharp</authors>\n"
    text = text + "    <description>Resolution fidelity fixture.</description>\n"
    text = text + "    <dependencies>\n" + dependenciesXml + "    </dependencies>\n"
    text = text + "  </metadata>\n"
    text = text + "</package>\n"
    File.WriteAllText(Path.Combine(versionDirectory, packageId.ToLowerInvariant() + ".nuspec"), text)
}

func ResolutionInstallLibrary(versionDirectory: string, assemblyPath: string) {
    libDirectory := Path.Combine(Path.Combine(versionDirectory, "lib"), "net10.0")
    Directory.CreateDirectory(libDirectory)
    File.Copy(assemblyPath, Path.Combine(libDirectory, Path.GetFileName(assemblyPath)), true)
}

// WHAT THE EMITTED ASSEMBLY REFERENCES, WHICH IS THE ONLY THING THAT READS BACK THE COMPILE-TIME
// DECISION. Running the program cannot: two builds of one library land on one file name, the
// runtime-asset copy already unifies such a clash on the higher version, and the default load
// context binds a non-strong-named assembly by simple name whatever version the reference asked
// for. So a program compiled against the WRONG version still runs and still prints the right
// answer — the `AssemblyRef` is where the wrong answer is visible.
func ResolutionReferencedAssembly(assemblyPath: string, contextName: string, prefix: string): string {
    context := new AssemblyLoadContext(contextName, true)
    try {
        loaded := context.LoadFromAssemblyPath(Path.GetFullPath(assemblyPath))
        for reference in loaded.GetReferencedAssemblies() {
            name := reference.get_FullName()
            if name.StartsWith(prefix, StringComparison.Ordinal) {
                return name
            }
        }

        return ""
    } finally {
        context.Unload()
    }
}
