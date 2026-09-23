namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.IO

// A NUGET DEPENDENCY WHOSE SIMPLE NAME THE BUILD HOST ALSO OWNS.
//
// `Microsoft.Extensions.Logging.Abstractions` ships inside the .NET SDK's own MSBuild directory, so
// when the emit task runs as an MSBuild task the default load context already holds that simple
// name at the SDK's version. `Assembly.LoadFrom` of the project's package file therefore used to
// answer with the HOST's assembly, whose identity is not the requested one, and the reference was
// left with no executable handle: every signature naming one of its types declined at
// `emit.declaration.field-type` while the identical project built through `nlc build`.
//
// These rows use a version deliberately older than any SDK-shipped copy and then assert, off the
// EMITTED METADATA, that the assembly reference written into the output is the PROJECT's version.
// That keeps the assertion honest on a host whose own copy happens to match.
func PackageReferenceProjectYaml(): string {
    return "name: SdkPackageRef\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndependencies:\n  - nuget: Microsoft.Extensions.Logging.Abstractions\n    version: 9.0.0\n"
}

func PackageReferenceProgram(): string {
    return "namespace SdkPackageRef\n" + "\n" + "import Microsoft.Extensions.Logging\n" + "import Microsoft.Extensions.Logging.Abstractions\n" + "\n" + "class Probe {\n" + "    readonly plain: ILogger\n" + "    readonly typed: ILogger<Probe>\n" + "\n" + "    constructor(plain: ILogger, typed: ILogger<Probe>) {\n" + "        this.plain = plain\n" + "        this.typed = typed\n" + "    }\n" + "\n" + "    func Describe(): string {\n" + "        if plain.IsEnabled(LogLevel.Debug) {\n" + "            return \"debug-on\"\n" + "        }\n" + "\n" + "        if typed.IsEnabled(LogLevel.Error) {\n" + "            return \"error-on\"\n" + "        }\n" + "\n" + "        return \"quiet\"\n" + "    }\n" + "}\n" + "\n" + "func main() {\n" + "    probe := new Probe(NullLogger.Instance, NullLogger<Probe>.Instance)\n" + "    print probe.Describe()\n" + "}\n"
}

func PackageReferenceAssemblyReferenceVersion(assemblyPath: string, referenceName: string): string? {
    assembly := EmitTaskReadAssembly(assemblyPath)
    try {
        module := EmitTaskObjectProperty(assembly, "MainModule")
        reference := EmitTaskFindAssemblyReference(module, referenceName)
        if reference == null {
            return null
        }

        return Convert.ToString(EmitTaskObjectProperty(reference, "Version"))
    } finally {
        EmitTaskDispose(assembly)
    }
}

test "a project.yml nuget dependency reaches the emitter through the SDK and binds the project's own version" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "package-reference")
    try {
        sdkPackage := SdkBoundaryPreparePackage(root)
        projectDirectory := Path.Combine(scratch, "SdkPackageRef")
        projectPath := IlSdkProject(projectDirectory, "SdkPackageRef", PackageReferenceProjectYaml(), sdkPackage)
        File.WriteAllText(Path.Combine(projectDirectory, "Program.nl"), PackageReferenceProgram())

        build := SdkBoundaryRunDotnet("build " + SdkBoundaryQuote(projectPath) + " -v q --disable-build-servers", projectDirectory)
        SdkBoundaryRequireSuccess(build, "SDK build against a host-owned package name")

        assemblyPath := IlSdkAssembly(projectDirectory, "SdkPackageRef")
        assert File.Exists(assemblyPath)

        // The emitted AssemblyRef is the evidence: the host's copy of this simple name carries a
        // different version, so binding it would have written a different row here.
        assert PackageReferenceAssemblyReferenceVersion(assemblyPath, "Microsoft.Extensions.Logging.Abstractions") == "9.0.0.0"

        run := SdkBoundaryRunDotnet(SdkBoundaryQuote(assemblyPath), projectDirectory)
        SdkBoundaryRequireSuccess(run, "SDK package-reference output")
        assert run.Stdout.Trim() == "quiet", run.Stdout
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "the same package dependency resolves through the standalone CLI and both routes agree" {
    root := SdkBoundaryRepositoryRoot()
    scratch := IlSdkScratch(root, "package-reference-cli")
    try {
        projectDirectory := Path.Combine(scratch, "CliPackageRef")
        Directory.CreateDirectory(projectDirectory)
        File.WriteAllText(Path.Combine(projectDirectory, "project.yml"), PackageReferenceProjectYaml())
        File.WriteAllText(Path.Combine(projectDirectory, "Program.nl"), PackageReferenceProgram())

        cliPath := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0"), "Cli.dll")
        if !File.Exists(cliPath) {
            throw new InvalidOperationException("The built CLI was not found at " + cliPath)
        }

        build := SdkBoundaryRunDotnet(SdkBoundaryQuote(cliPath) + " build", projectDirectory)
        SdkBoundaryRequireSuccess(build, "standalone CLI build against the same package")

        assemblyPath := Path.Combine(Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), "net10.0"), "SdkPackageRef.dll")
        assert File.Exists(assemblyPath)
        assert PackageReferenceAssemblyReferenceVersion(assemblyPath, "Microsoft.Extensions.Logging.Abstractions") == "9.0.0.0"
    } finally {
        Directory.Delete(scratch, true)
    }
}
