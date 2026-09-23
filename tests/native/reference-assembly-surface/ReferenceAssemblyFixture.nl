namespace NSharpLang.ReferenceAssemblySurface.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text
import Mono.Cecil
import NSharpLang.Compiler

// A COMPILATION IN PROCESS, WITH A REAL REFERENCE SET.
//
// These rows are about what the compiler WRITES beside the implementation, so they drive the
// compiler directly rather than through MSBuild: the MSBuild half — the copy into `obj/…/refint/`
// and the up-to-date check it feeds — is `tests/native/sdk-reference-incrementality`'s subject.
// The reference set is the real `Microsoft.NETCore.App.Ref` pack, because the type-reference
// rescope has nothing to rescope to without one.
class SurfaceCompilation {
    Directory: string
    OutputPath: string
    ReferencePath: string

    constructor(directory: string, outputPath: string, referencePath: string) {
        Directory = directory
        OutputPath = outputPath
        ReferencePath = referencePath
    }
}

func SurfaceReferencePackDirectory(): string {
    objectType := typeof(object)
    objectAssemblyInfo := objectType.get_Assembly()
    objectAssembly := objectAssemblyInfo.get_Location()
    runtimeDirectory := Path.GetDirectoryName(objectAssembly) ?? ""
    dotnetRoot := Path.GetFullPath(Path.Combine(runtimeDirectory, "../../.."))
    packsRoot := Path.Combine(Path.Combine(dotnetRoot, "packs"), "Microsoft.NETCore.App.Ref")
    versions := Directory.GetDirectories(packsRoot)
    versionDirectory: string? = null
    versionIndex := 0
    while versionIndex < versions.Length {
        candidate := Path.Combine(Path.Combine(versions[versionIndex], "ref"), "net10.0")
        if versionDirectory == null && Directory.Exists(candidate) {
            versionDirectory = versions[versionIndex]
        }
        versionIndex = versionIndex + 1
    }
    if versionDirectory == null {
        throw new InvalidOperationException("The Microsoft.NETCore.App net10.0 reference pack was not found under " + packsRoot)
    }
    return Path.Combine(Path.Combine(versionDirectory, "ref"), "net10.0")
}

func SurfaceScratch(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-reference-surface-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func SurfaceWriteProject(directory: string, name: string, source: string): string {
    Directory.CreateDirectory(directory)
    File.WriteAllText(
        Path.Combine(directory, "project.yml"),
        "name: " + name + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    sourcePath := Path.Combine(directory, "Library.nl")
    File.WriteAllText(sourcePath, source)
    return sourcePath
}

// Every reference-pack assembly, exactly as the SDK hands `@(ReferencePath)` to the emit task, plus
// whatever extra assemblies a consumer row wants to compile against.
func SurfaceConfigWithReferences(directory: string, extraReferences: IReadOnlyList<string>): ProjectConfig {
    config := ProjectFileParser.Parse(Path.Combine(directory, "project.yml"))
    referencePack := SurfaceReferencePackDirectory()
    packFiles := Directory.GetFiles(referencePack, "*.dll")
    packIndex := 0
    while packIndex < packFiles.Length {
        SurfaceAddDllDependency(config, packFiles[packIndex])
        packIndex = packIndex + 1
    }
    extraIndex := 0
    while extraIndex < extraReferences.Count {
        SurfaceAddDllDependency(config, extraReferences[extraIndex])
        extraIndex = extraIndex + 1
    }
    return config
}

func SurfaceCompile(directory: string, name: string, extraReferences: IReadOnlyList<string>): SurfaceCompilation {
    config := SurfaceConfigWithReferences(directory, extraReferences)

    outputDirectory := Path.Combine(directory, "out")
    Directory.CreateDirectory(outputDirectory)
    outputPath := Path.Combine(outputDirectory, name + ".dll")

    sources := new List<string>()
    sources.Add(Path.Combine(directory, "Library.nl"))
    compiler := new MultiFileCompiler(sources, directory, config)
    compiler.EmitReferenceAssembly = true
    result := compiler.CompileToIlAssembly(name, outputPath, false, false)
    if !result.Success {
        throw new InvalidOperationException("Compilation of '" + name + "' failed: " + SurfaceDescribeErrors(result.Errors))
    }
    return new SurfaceCompilation(directory, outputPath, MultiFileCompiler.ReferenceAssemblyPathFor(outputPath))
}

// ANALYSIS ONLY, against exactly the references the caller names. This is the half of "a consumer
// builds against it" that a reference assembly can answer: the ANALYZER reads metadata through
// `MetadataLoadContext` and binds names out of it, while the columnar EMITTER binds against runtime
// `Type` objects and the CLR refuses `LoadFromAssemblyPath` for an assembly carrying
// `[ReferenceAssembly]` ("Cannot load a reference assembly for execution"). That is why
// `Sdk.targets` keeps handing the emit task `@(ReferencePath)` — the implementations — and changes
// only the target's `Inputs` to the ref-substituted list.
func SurfaceAnalyze(directory: string, extraReferences: IReadOnlyList<string>): List<string> {
    config := SurfaceConfigWithReferences(directory, extraReferences)
    sources := new List<string>()
    sources.Add(Path.Combine(directory, "Library.nl"))
    compiler := new MultiFileCompiler(sources, directory, config)
    compiler.CompileForAnalysis()
    messages := new List<string>()
    for error in compiler.AllErrors {
        if error.Severity == ErrorSeverity.Error {
            messages.Add(error.FormatForMsBuild())
        }
    }
    return messages
}

func SurfaceAddDllDependency(config: ProjectConfig, path: string) {
    reference := new Reference()
    reference.Dll = path
    dependencies := config.Dependencies
    dependencies.Add(reference)
}

func SurfaceNoExtraReferences(): IReadOnlyList<string> {
    return new List<string>()
}

func SurfaceDescribeErrors(errors: IEnumerable<CompilerError>): string {
    builder := new StringBuilder()
    for error in errors {
        if error.Severity == ErrorSeverity.Error {
            builder.Append(error.FormatForMsBuild())
            builder.Append("; ")
        }
    }
    return builder.ToString()
}

func SurfaceReadAssembly(path: string): AssemblyDefinition {
    parameters := new ReaderParameters()
    parameters.ReadingMode = ReadingMode.Immediate
    parameters.InMemory = true
    return AssemblyDefinition.ReadAssembly(path, parameters)
}

func SurfaceTypeNames(path: string): List<string> {
    names := new List<string>()
    assembly := SurfaceReadAssembly(path)
    try {
        for type in assembly.MainModule.Types {
            SurfaceCollectTypeNames(type, names)
        }
    } finally {
        assembly.Dispose()
    }
    return names
}

func SurfaceCollectTypeNames(type: TypeDefinition, names: List<string>) {
    names.Add(type.FullName)
    for nested in type.NestedTypes {
        SurfaceCollectTypeNames(nested, names)
    }
}

func SurfaceMethodNames(path: string, typeFullName: string): List<string> {
    names := new List<string>()
    assembly := SurfaceReadAssembly(path)
    try {
        for type in assembly.MainModule.Types {
            if type.FullName == typeFullName {
                for method in type.Methods {
                    names.Add(method.Name)
                }
            }
        }
    } finally {
        assembly.Dispose()
    }
    return names
}

// `ldnull; throw` is two instructions and nothing else; a body with any other shape means an
// implementation body survived into the surface.
func SurfaceNonThrowNullBodies(path: string): List<string> {
    offenders := new List<string>()
    assembly := SurfaceReadAssembly(path)
    try {
        for type in assembly.MainModule.Types {
            SurfaceCollectNonThrowNullBodies(type, offenders)
        }
    } finally {
        assembly.Dispose()
    }
    return offenders
}

func SurfaceCollectNonThrowNullBodies(type: TypeDefinition, offenders: List<string>) {
    for method in type.Methods {
        if method.HasBody {
            instructions := method.Body.Instructions
            shaped := instructions.Count == 2
            if shaped {
                shaped = instructions[0].OpCode == Mono.Cecil.Cil.OpCodes.Ldnull && instructions[1].OpCode == Mono.Cecil.Cil.OpCodes.Throw
            }
            if !shaped {
                offenders.Add(type.FullName + "::" + method.Name)
            }
        }
    }
    for nested in type.NestedTypes {
        SurfaceCollectNonThrowNullBodies(nested, offenders)
    }
}

func SurfaceAssemblyAttributeNames(path: string): List<string> {
    names := new List<string>()
    assembly := SurfaceReadAssembly(path)
    try {
        for attribute in assembly.CustomAttributes {
            names.Add(attribute.AttributeType.FullName)
        }
    } finally {
        assembly.Dispose()
    }
    return names
}

func SurfaceTypeReferenceScopeNames(path: string): List<string> {
    names := new List<string>()
    assembly := SurfaceReadAssembly(path)
    try {
        for reference in assembly.MainModule.GetTypeReferences() {
            scope := reference.Scope as AssemblyNameReference
            if scope != null {
                names.Add(scope.Name)
            }
        }
    } finally {
        assembly.Dispose()
    }
    return names
}

func SurfaceContains(values: List<string>, value: string): bool {
    for candidate in values {
        if candidate == value {
            return true
        }
    }
    return false
}

func SurfaceCountPrefixed(values: List<string>, prefix: string): int {
    count := 0
    for candidate in values {
        if candidate.StartsWith(prefix, StringComparison.Ordinal) {
            count = count + 1
        }
    }
    return count
}

func SurfaceBytesEqual(left: byte[], right: byte[]): bool {
    if left.Length != right.Length {
        return false
    }
    index := 0
    while index < left.Length {
        if left[index] != right[index] {
            return false
        }
        index = index + 1
    }
    return true
}
