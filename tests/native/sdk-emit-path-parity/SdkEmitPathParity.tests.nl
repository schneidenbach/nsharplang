namespace NSharpLang.SdkEmitPathParity.Tests

import System
import System.Collections.Generic
import System.IO
import System.Runtime.Loader

// The sample the two doors compile. Every shape in it was measured DECLINING through the SDK and
// EMITTING through `nlc build` at `b4c9ae356`:
//
//   * `builder.AddFile(path)`      -- an extension declared in `Serilog.Extensions.Logging.File`,
//                                     a simple name MSBuild does NOT carry, over a receiver typed
//                                     by `Microsoft.Extensions.Logging.Abstractions`, a simple name
//                                     MSBuild DOES carry (ls6-4);
//   * `options.ConfigureLogging(builder => …)` -- a lambda parameter whose type is INFERRED from
//                                     `Action<ILoggingBuilder>` on an OmniSharp extension, the same
//                                     split across the same line (ls6-3);
//   * `LoggerFactory.Create` / `LogLevel` -- a type whose SIMPLE NAME the MSBuild host also carries
//                                     (`Microsoft.Extensions.Logging`, shipped throughout
//                                     `.../sdk/10.0.x/` at the host's own version), PINNED here at
//                                     the project's 9.0.0. The host's build is the one an emitter
//                                     that asks the default context by simple name gets, so the row
//                                     below requires the emitted `AssemblyRef` to read 9.0.0.0
//                                     through BOTH doors -- an assertion no compile-and-run check
//                                     can make, because the host's build dispatches perfectly well.
//
// `builder.SetMinimumLevel` is reached through `Microsoft.Extensions.Logging.Abstractions`, which
// the project never names, so the row also covers an extension method from a TRANSITIVE package.
func ParitySampleProgram(): string {
    return """
namespace ParitySample

import System
import System.IO
import Microsoft.Extensions.Logging
import OmniSharp.Extensions.LanguageServer.Server

class ParitySampleHost {
    static func ConfigureInferred(options: LanguageServerOptions, logPath: string): LanguageServerOptions {
        return options.ConfigureLogging(builder => {
            builder.AddFile(logPath)
            builder.SetMinimumLevel(LogLevel.Debug)
        })
    }

    static func ConfigureDeclared(builder: ILoggingBuilder, logPath: string) {
        builder.AddFile(logPath)
        builder.SetMinimumLevel(LogLevel.Debug)
    }
}

func main() {
    logPath := Environment.GetEnvironmentVariable("NSHARP_PARITY_LOG") ?? ""
    factory := LoggerFactory.Create(builder => {
        ParitySampleHost.ConfigureDeclared(builder, logPath)
    })
    logger := factory.CreateLogger("Parity")
    logger.LogInformation("parity probe line")
    factory.Dispose()
    logDirectory := Path.GetDirectoryName(logPath) ?? "."
    print "parity|" + (Directory.GetFiles(logDirectory).Length > 0).ToString()
}
"""
}

// THE PIN IS LISTED LAST, AND THAT IS A MEASURED FINDING ABOUT RESOLUTION, NOT A STYLE CHOICE.
// With `Microsoft.Extensions.Logging 9.0.0` written AFTER `OmniSharp.Extensions.LanguageServer`,
// the two doors once bound DIFFERENT versions of it: `dotnet build` bound the pinned 9.0.0.0
// (NuGet's nearest-wins -- a direct reference is at distance zero and beats any transitive one),
// and `nlc build` bound OmniSharp's TRANSITIVE 6.0.0.0, because the CLI resolved each root's
// closure in turn and kept the first version it reached. That was a second, INDEPENDENT parity
// gap between the two doors -- package RESOLUTION rather than reference loading -- and the sample
// once led with the pin to route around it. It leads with OmniSharp now: the CLI selects versions
// in level order, so the ORDER OF THIS LIST IS ITSELF UNDER TEST and the `Version=9.0.0.0`
// assertion below reads both contracts at once.
func ParitySampleProjectYml(): string {
    return """
name: ParitySample
version: 1.0.0
backend: il
outputType: exe
targetFramework: net10.0
dependencies:
  - nuget: OmniSharp.Extensions.LanguageServer
    version: 0.19.9
  - nuget: Serilog.Extensions.Logging.File
    version: 3.0.0
  - nuget: Microsoft.Extensions.Logging
    version: 9.0.0
"""
}

// THE VERSION THE PROJECT PINNED, not the one the host ships. `Microsoft.Extensions.Logging` is the
// exact family the .NET SDK directory carries at its own version, so an emitter that answers a
// reference path from the default context by simple name binds 10.0.0.0 here and everything still
// runs -- which is why the reference set, and not the program's behavior, is what this row reads.
func ParityPinnedLoggingReference(): string {
    return "Microsoft.Extensions.Logging, Version=9.0.0.0"
}

func ParityReferenceStartingWith(references: List<string>, prefix: string): string {
    for reference in references {
        if reference.StartsWith(prefix, StringComparison.Ordinal) {
            return reference
        }
    }

    return ""
}

func ParityWriteSample(projectDirectory: string) {
    Directory.CreateDirectory(projectDirectory)
    File.WriteAllText(Path.Combine(projectDirectory, "ParitySample.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(Path.Combine(projectDirectory, "project.yml"), ParitySampleProjectYml())
    File.WriteAllText(Path.Combine(projectDirectory, "Program.nl"), ParitySampleProgram())
}

// The emitted program is RUN, not merely emitted, and its one line of output says whether the
// Serilog extension it called actually produced a log file. A build that emits a call the runtime
// cannot dispatch would still pass a compile-only row. The sink date-stamps the name it is given,
// so the answer is about the DIRECTORY, which is cleared first.
func ParityRunSample(projectDirectory: string, logPath: string): ParityRun {
    logDirectory := Path.GetDirectoryName(logPath) ?? "."
    if Directory.Exists(logDirectory) {
        Directory.Delete(logDirectory, true)
    }

    Directory.CreateDirectory(logDirectory)

    return ParityRunProcessWith("dotnet", ParityQuote(ParityOutputAssembly(projectDirectory, "ParitySample")), projectDirectory, "NSHARP_PARITY_LOG", logPath)
}

func ParityLogText(directory: string): string {
    if !Directory.Exists(directory) {
        return ""
    }

    // The file sink may date-stamp the name it was given, so every file beside it counts.
    text := ""
    for candidate in Directory.GetFiles(directory) {
        try {
            stream := new FileStream(candidate, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)
            try {
                reader := new StreamReader(stream)
                text = text + reader.ReadToEnd()
            } finally {
                stream.Dispose()
            }

            // nlc:ignore NL011
        } catch {

            // A file another process still holds exclusively contributes nothing; keep reading.
        }
    }

    return text
}

func ParityReferencedAssemblies(assemblyPath: string, contextName: string): List<string> {
    context := new AssemblyLoadContext(contextName, true)
    try {
        loaded := context.LoadFromAssemblyPath(Path.GetFullPath(assemblyPath))
        names := new List<string>()
        for reference in loaded.GetReferencedAssemblies() {
            names.Add(reference.get_FullName())
        }

        names.Sort(StringComparer.Ordinal)
        return names
    } finally {
        context.Unload()
    }
}

func ParityJoin(values: List<string>): string {
    text := ""
    index := 0
    while index < values.Count {
        if index > 0 {
            text = text + "|"
        }

        text = text + values[index]
        index = index + 1
    }

    return text
}

test "one project emits the same program through nlc build and through the SDK emit path" {
    root := ParityRepositoryRoot()
    scratch := Path.Combine(Path.Combine(root, "artifacts"), "sdk-emit-path-parity-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(scratch)
    try {
        sdkPackage := ParityPreparePackage(root, scratch)
        projectDirectory := Path.Combine(scratch, "Sample")
        ParityWriteSample(projectDirectory)
        ParityWriteResolution(projectDirectory, sdkPackage, Path.Combine(scratch, "packages"))

        cliLogDirectory := Path.Combine(scratch, "cli-log")
        sdkLogDirectory := Path.Combine(scratch, "sdk-log")
        Directory.CreateDirectory(cliLogDirectory)
        Directory.CreateDirectory(sdkLogDirectory)
        cliLog := Path.Combine(cliLogDirectory, "parity.log")
        sdkLog := Path.Combine(sdkLogDirectory, "parity.log")

        // ── DOOR ONE: the standalone CLI, which resolves `nuget:` itself ──────────────────────
        cliBuild := ParityRunDotnet(ParityQuote(ParityCliPath(root)) + " build", projectDirectory)
        ParityRequireSuccess(cliBuild, "nlc build of the parity sample")
        assert !cliBuild.Output().Contains("not modeled"), cliBuild.Output()
        cliRun := ParityRunSample(projectDirectory, cliLog)
        ParityRequireSuccess(cliRun, "running the CLI-built parity sample")
        assert cliRun.Stdout.Trim() == "parity|True", cliRun.Output()
        assert ParityLogText(cliLogDirectory).Contains("parity probe line"), "the CLI-built program wrote no log line"

        cliAssembly := Path.Combine(scratch, "ParitySample.cli.dll")
        File.Copy(ParityOutputAssembly(projectDirectory, "ParitySample"), cliAssembly, true)
        ParityDeleteOutput(projectDirectory)

        // ── DOOR TWO: `dotnet build` of a one-line SDK csproj, emitting inside MSBuild ────────
        restore := ParityRunDotnet("restore ParitySample.csproj --disable-build-servers -v q", projectDirectory)
        ParityRequireSuccess(restore, "restore of the parity sample")
        sdkBuild := ParityRunDotnet("build ParitySample.csproj --no-restore --disable-build-servers -v q", projectDirectory)
        assert !sdkBuild.Output().Contains("not modeled"), sdkBuild.Output()
        ParityRequireSuccess(sdkBuild, "dotnet build of the parity sample")
        sdkRun := ParityRunSample(projectDirectory, sdkLog)
        ParityRequireSuccess(sdkRun, "running the SDK-built parity sample")
        assert sdkRun.Stdout.Trim() == cliRun.Stdout.Trim(), sdkRun.Output()
        assert ParityLogText(sdkLogDirectory).Contains("parity probe line"), "the SDK-built program wrote no log line"

        // ── AND THE SAME REFERENCE UNIVERSE, NOT MERELY THE SAME OUTCOME ─────────────────────
        // The defect this row exists for did not change what the emitter was asked to emit; it
        // changed which BUILD of a shared simple name the emitter saw. Two assemblies that agree on
        // their AssemblyRef set agree that the SDK path bound the project's packages and not the
        // MSBuild host's copies of the same names.
        cliReferences := ParityReferencedAssemblies(cliAssembly, "parity-cli")
        sdkReferences := ParityReferencedAssemblies(ParityOutputAssembly(projectDirectory, "ParitySample"), "parity-sdk")
        assert ParityJoin(sdkReferences) == ParityJoin(cliReferences), "cli=" + ParityJoin(cliReferences) + "\nsdk=" + ParityJoin(sdkReferences)
        assert ParityJoin(cliReferences).Contains("Serilog.Extensions.Logging.File"), ParityJoin(cliReferences)
        assert ParityJoin(cliReferences).Contains("Microsoft.Extensions.Logging.Abstractions"), ParityJoin(cliReferences)

        // ── AND THE PINNED VERSION OF A SIMPLE NAME THE HOST ALSO CARRIES ───────────────────
        cliLogging := ParityReferenceStartingWith(cliReferences, "Microsoft.Extensions.Logging,")
        sdkLogging := ParityReferenceStartingWith(sdkReferences, "Microsoft.Extensions.Logging,")
        assert cliLogging.StartsWith(ParityPinnedLoggingReference(), StringComparison.Ordinal), "cli bound " + cliLogging
        assert sdkLogging.StartsWith(ParityPinnedLoggingReference(), StringComparison.Ordinal), "sdk bound " + sdkLogging
    } finally {
        Directory.Delete(scratch, true)
    }
}

// ─── A REFERENCED N# ASSEMBLY'S MEMBER, TYPED BY AN IDENTITY THE COMPILER ITSELF REFERENCES ─────
//
// `ScanResult.Context` is a `MetadataLoadContext?` declared by a LIBRARY the sample references --
// the shape `Compiler.Core` meets once `Compiler.Model` (which declares `ExternalAssemblyScanResult`)
// is its own assembly. Inside MSBuild the compiler runs in a load context of its own, and the
// executable handle a compilation pairs `System.Reflection.MetadataLoadContext` with is the
// COMPILER'S build of it; the library, loaded into the compiler's owned reference context, used to
// resolve its dependency out of the DEFAULT context instead -- the SDK directory's build of the same
// identity. `F(scan.Context)` then declined through `dotnet build` (two `MetadataLoadContext` types,
// one name) while `nlc build` emitted it. Measured against a stage-2 seed built before the fix:
// `context: MetadataLoadContext? = scan.Context` declined `emit.typed-local.type-mismatch` naming the
// same type twice.
func ParityLibraryProjectYml(): string {
    return """
name: ParityScanLibrary
version: 1.0.0
backend: il
outputType: library
targetFramework: net10.0
dependencies:
  - nuget: System.Reflection.MetadataLoadContext
    version: 10.0.5
"""
}

func ParityLibrarySource(): string {
    return """
namespace Parity.Scan

import System.Reflection

class ScanResult {
    Context: MetadataLoadContext?

    constructor(context: MetadataLoadContext?) {
        Context = context
    }
}
"""
}

func ParityScanProjectYml(): string {
    return """
name: ParityScanSample
version: 1.0.0
backend: il
outputType: exe
targetFramework: net10.0
dependencies:
  - project: ../ParityScanLibrary/project.yml
  - nuget: System.Reflection.MetadataLoadContext
    version: 10.0.5
"""
}

func ParityScanProgram(): string {
    return """
namespace Parity.Scan

import System.IO
import System.Reflection
import System.Runtime.InteropServices

func CoreName(scan: ScanResult): string {
    context := scan.Context
    if context == null {
        return "none"
    }
    return Describe(context)
}

func Typed(scan: ScanResult): string {
    context: MetadataLoadContext? = scan.Context
    if context == null {
        return "none"
    }
    return Describe(context)
}

func Describe(loadContext: MetadataLoadContext): string {
    return loadContext.CoreAssembly?.GetName().Name ?? ""
}

func main() {
    paths := Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll")
    loadContext := new MetadataLoadContext(new PathAssemblyResolver(paths), "System.Private.CoreLib")
    try {
        print CoreName(new ScanResult(null)) + "|" + CoreName(new ScanResult(loadContext)) + "|" + Typed(new ScanResult(loadContext))
    } finally {
        loadContext.Dispose()
    }
}
"""
}

func ParityWriteScanSample(scratch: string, sdkPackage: ParityPackage): string {
    libraryDirectory := Path.Combine(scratch, "ParityScanLibrary")
    projectDirectory := Path.Combine(scratch, "ParityScanSample")
    Directory.CreateDirectory(libraryDirectory)
    Directory.CreateDirectory(projectDirectory)
    File.WriteAllText(Path.Combine(libraryDirectory, "ParityScanLibrary.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(Path.Combine(libraryDirectory, "project.yml"), ParityLibraryProjectYml())
    File.WriteAllText(Path.Combine(libraryDirectory, "ScanResult.nl"), ParityLibrarySource())
    File.WriteAllText(Path.Combine(projectDirectory, "ParityScanSample.csproj"), "<Project Sdk=\"NSharpLang.Sdk\" />\n")
    File.WriteAllText(Path.Combine(projectDirectory, "project.yml"), ParityScanProjectYml())
    File.WriteAllText(Path.Combine(projectDirectory, "Program.nl"), ParityScanProgram())
    // One resolution for both projects: the global.json, NuGet.config and props sit above them.
    ParityWriteResolution(scratch, sdkPackage, Path.Combine(scratch, "packages"))
    return projectDirectory
}

test "a referenced N# assembly's member typed by a compiler-referenced identity binds one type through both doors" {
    root := ParityRepositoryRoot()
    scratch := Path.Combine(Path.Combine(root, "artifacts"), "sdk-emit-path-parity-scan-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(scratch)
    try {
        sdkPackage := ParityPreparePackage(root, scratch)
        projectDirectory := ParityWriteScanSample(scratch, sdkPackage)
        expected := "none|System.Private.CoreLib|System.Private.CoreLib"

        // ── DOOR ONE: the standalone CLI ──────────────────────────────────────────────────────
        cliBuild := ParityRunDotnet(ParityQuote(ParityCliPath(root)) + " build", projectDirectory)
        ParityRequireSuccess(cliBuild, "nlc build of the scan sample")
        cliRun := ParityRunDotnet(ParityQuote(ParityOutputAssembly(projectDirectory, "ParityScanSample")), projectDirectory)
        ParityRequireSuccess(cliRun, "running the CLI-built scan sample")
        assert cliRun.Stdout.Trim() == expected, cliRun.Output()
        ParityDeleteOutput(projectDirectory)
        ParityDeleteOutput(Path.Combine(scratch, "ParityScanLibrary"))

        // ── DOOR TWO: `dotnet build`, emitting inside MSBuild ──────────────────────────────────
        restore := ParityRunDotnet("restore ParityScanSample.csproj --disable-build-servers -v q", projectDirectory)
        ParityRequireSuccess(restore, "restore of the scan sample")
        sdkBuild := ParityRunDotnet("build ParityScanSample.csproj --no-restore --disable-build-servers -v q", projectDirectory)
        assert !sdkBuild.Output().Contains("declined"), sdkBuild.Output()
        ParityRequireSuccess(sdkBuild, "dotnet build of the scan sample")
        sdkRun := ParityRunDotnet(ParityQuote(ParityOutputAssembly(projectDirectory, "ParityScanSample")), projectDirectory)
        ParityRequireSuccess(sdkRun, "running the SDK-built scan sample")
        assert sdkRun.Stdout.Trim() == expected, sdkRun.Output()
    } finally {
        Directory.Delete(scratch, true)
    }
}
