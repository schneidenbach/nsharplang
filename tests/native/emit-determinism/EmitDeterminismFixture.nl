namespace NSharpLang.EmitDeterminism.Tests

import System
import System.Collections.Generic
import System.IO
import System.Reflection.Metadata
import System.Reflection.PortableExecutable
import System.Text
import NSharpLang.Compiler

// IDENTICAL INPUT, IDENTICAL OUTPUT — asserted over whole files rather than over a masked
// comparison, which is the only form of the claim worth making.
class DeterminismBuild {
    ImplementationPath: string
    ReferencePath: string

    constructor(implementationPath: string, referencePath: string) {
        ImplementationPath = implementationPath
        ReferencePath = referencePath
    }
}

func DeterminismScratch(label: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-emit-determinism-" + label + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

func DeterminismWriteProject(directory: string, source: string) {
    Directory.CreateDirectory(directory)
    File.WriteAllText(
        Path.Combine(directory, "project.yml"),
        "name: Det\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    )
    File.WriteAllText(Path.Combine(directory, "Library.nl"), source)
}

func DeterminismCompile(directory: string, outputDirectory: string): DeterminismBuild {
    config := ProjectFileParser.Parse(Path.Combine(directory, "project.yml"))
    Directory.CreateDirectory(outputDirectory)
    outputPath := Path.Combine(outputDirectory, "Det.dll")
    sources := new List<string>()
    sources.Add(Path.Combine(directory, "Library.nl"))
    compiler := new MultiFileCompiler(sources, directory, config)
    compiler.EmitReferenceAssembly = true
    result := compiler.CompileToIlAssembly("Det", outputPath, false, false)
    if !result.Success {
        throw new InvalidOperationException("Compilation failed: " + DeterminismDescribeErrors(result.Errors))
    }
    return new DeterminismBuild(outputPath, MultiFileCompiler.ReferenceAssemblyPathFor(outputPath))
}

func DeterminismDescribeErrors(errors: IEnumerable<CompilerError>): string {
    builder := new StringBuilder()
    for error in errors {
        if error.Severity == ErrorSeverity.Error {
            builder.Append(error.FormatForMsBuild())
            builder.Append("; ")
        }
    }
    return builder.ToString()
}

func DeterminismBytesEqual(left: byte[], right: byte[]): bool {
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

func DeterminismModuleVersionId(path: string): string {
    stream := File.OpenRead(path)
    try {
        reader := new PEReader(stream)
        try {
            metadata := reader.GetMetadataReader()
            moduleDefinition := metadata.GetModuleDefinition()
            return metadata.GetGuid(moduleDefinition.Mvid).ToString()
        } finally {
            reader.Dispose()
        }
    } finally {
        stream.Dispose()
    }
}

// The COFF header's `TimeDateStamp`, read as four little-endian bytes off the image. A deterministic
// stamp is not a date, and Roslyn marks that by setting its high bit; so does this.
func DeterminismTimestamp(path: string): int {
    image := File.ReadAllBytes(path)
    peHeaderOffset := DeterminismReadInt32(image, 60)
    return DeterminismReadInt32(image, peHeaderOffset + 8)
}

func DeterminismReadInt32(image: byte[], offset: int): int {
    value := 0
    index := 3
    while index >= 0 {
        value = (value * 256) + Convert.ToInt32(image[offset + index])
        index = index - 1
    }
    return value
}

func DeterminismTimestampHighBitSet(path: string): bool {
    image := File.ReadAllBytes(path)
    peHeaderOffset := DeterminismReadInt32(image, 60)
    highByte := Convert.ToInt32(image[peHeaderOffset + 8 + 3])
    return highByte >= 128
}

// RFC 4122 version 4 and the IETF variant, the two fields `BlobContentId.FromHash` sets and the two
// this compiler sets, so an N# module version id is a well-formed GUID and not sixteen hash bytes.
func DeterminismGuidIsVersionFour(guidText: string): bool {
    if guidText.Length != 36 {
        return false
    }
    if guidText[14] != '4' {
        return false
    }
    variant := guidText[19]
    return variant == '8' || variant == '9' || variant == 'a' || variant == 'b' || variant == 'A' || variant == 'B'
}
