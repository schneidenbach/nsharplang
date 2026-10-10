namespace Census.Operands

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.Loader
import NSharpLang.Compiler


// THE ANALYSIS-FREE PATH, over the same source.
//
// `Compiler.Core` is built through `CompileToIlAssembly(..., validateWithLegacyAnalysis: false)`: no
// analyzer runs, so the emitter's own reading of each argument and operand is the only one, and every
// gap this project pins was met there first. `Consumer.nl` is compiled again that way here, against the
// SAME referenced library this assembly was built with, then loaded into a collectible context and run:
// its `Digest()` must equal the one this assembly -- the analysis path -- computes. A shape that
// declines fails the emit; a shape that emits the wrong thing fails the comparison.
func OperandsRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            break
        }
        current = parent
    }

    throw new InvalidOperationException("Could not locate the N# repository root from " + AppContext.BaseDirectory + ".")
}

func OperandsText(errors: IEnumerable<CompilerError>): string {
    text := ""
    for error in errors {
        text = text + error.DiagnosticId + " " + error.Message + "\n"
    }
    return text
}

// The consumer compiled emit-only into a fresh directory. The library is referenced by the very file
// this assembly loaded, so both paths read one set of referenced types.
func OperandsEmitOnly(out outputPath: string): MultiFileCompilationResult {
    root := Path.Combine(Path.GetTempPath(), "nsharp-external-operands-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    libraryPath := typeof(Shape).Assembly.Location
    loadContextPath := typeof(MetadataLoadContext).Assembly.Location
    File.WriteAllText(Path.Combine(root, "project.yml"), "name: OperandsEmitOnly\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + libraryPath + "\n  - dll: " + loadContextPath + "\n")
    source := File.ReadAllText(Path.Combine(OperandsRepositoryRoot(), "tests", "native", "census-external-operands", "Consumer.nl"))
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), source)

    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    outputPath = Path.Combine(root, "out", "OperandsEmitOnly.dll")
    return compiler.CompileToIlAssembly("OperandsEmitOnly", outputPath, false, false)
}

test "the analysis-free path emits every referenced-type shape and computes the same answers" {
    let outputPath: string = ""
    result := OperandsEmitOnly(out outputPath)
    assert result.Success, OperandsText(result.Errors)

    context := new AssemblyLoadContext("nsharp-external-operands-" + Guid.NewGuid().ToString("N"), true)
    try {
        emitted := context.LoadFromAssemblyPath(outputPath)
        uses := emitted.GetType("Census.Operands.OperandUses")
        assert uses != null
        digest := uses.GetMethod("Digest")
        assert digest != null
        emittedDigest := digest.Invoke(null, new object?[](0)) as string
        assert emittedDigest == OperandUses.Digest(), (emittedDigest ?? "<null>") + "\n---\n" + OperandUses.Digest()
    } finally {
        context.Unload()
    }
}
