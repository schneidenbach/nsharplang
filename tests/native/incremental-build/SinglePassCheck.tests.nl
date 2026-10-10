namespace NSharpLang.IncrementalBuild.Tests

import System
import System.IO
import System.Text
import NSharpLang.Compiler

// `nlc check` ANALYSES ONCE AND WRITES NOTHING. It used to analyse the project for its diagnostics and
// then hand the same project to a second compiler to prove it emits — every file parsed, analysed and
// the whole reference closure loaded twice — and that proof wrote an assembly into a scratch
// directory. It now validates the emission of the compiler that analysed it, in memory
// (`MultiFileCompiler.ValidateAnalyzedEmission`). These rows hold that door to exactly what a fresh
// `CompileToIlAssembly` produces: the same diagnostics, the same image, and no file anywhere.
func SinglePassRender(result: MultiFileCompilationResult): string {
    builder := new StringBuilder()
    for error in result.Errors {
        builder.AppendLine(error.FormatForTooling(true, true))
    }
    return builder.ToString()
}

func SinglePassFilesUnder(directory: string): int {
    return Directory.GetFiles(directory, "*", SearchOption.AllDirectories).Length
}

test "validating the emission of the analysis already run produces a fresh compilation's image and diagnostics, and writes nothing" {
    scratch := IncrementalScratch("single-pass")
    try {
        IncrementalWriteProject(scratch)
        filesBefore := SinglePassFilesUnder(scratch)
        config := ProjectFileParser.Parse(Path.Combine(scratch, "project.yml"))
        analysed := new MultiFileCompiler(scratch, config, null, true)
        analysed.CompileForAnalysis()
        validated := analysed.ValidateAnalyzedEmission("Lib")
        assert SinglePassFilesUnder(scratch) == filesBefore, "validation wrote files into the project tree"
        // Work counters are process-wide and xUnit runs other test classes in parallel. The isolated
        // output path and scratch-tree checks below attribute this no-write contract to this compiler.
        assert validated.OutputAssemblyPath == null, "validation unexpectedly reported an output assembly path"

        fresh := new MultiFileCompiler(scratch, config, null, true)
        full := fresh.CompileToIlAssembly("Lib", Path.Combine(scratch, "b", "Lib.dll"), false, true)

        assert validated.Success, SinglePassRender(validated)
        assert full.Success, SinglePassRender(full)
        assert SinglePassRender(validated) == SinglePassRender(full), "validation diagnostics differ from a fresh emission"
        image := analysed.EmittedImage
        assert image != null, "validation did not retain its emitted image"
        assert ContentHash.OfBytes(image ?? new byte[](0)) == ContentHash.OfFileOrMissing(Path.Combine(scratch, "b", "Lib.dll")), "validation image differs from a fresh emission"
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "an analysis error stops the validation exactly as it stops a fresh compilation" {
    scratch := IncrementalScratch("single-pass-error")
    try {
        IncrementalWriteProject(scratch)
        report := Path.Combine(scratch, "Report.nl")
        File.WriteAllText(report, File.ReadAllText(report).Replace("Twice(", "Thrice("))
        config := ProjectFileParser.Parse(Path.Combine(scratch, "project.yml"))
        analysed := new MultiFileCompiler(scratch, config, null, true)
        analysed.CompileForAnalysis()
        validated := analysed.ValidateAnalyzedEmission("Lib")
        full := new MultiFileCompiler(scratch, config, null, true).CompileToIlAssembly("Lib", Path.Combine(scratch, "b", "Lib.dll"), false, true)

        assert !validated.Success
        assert !full.Success
        assert SinglePassRender(validated) == SinglePassRender(full)
        assert analysed.EmittedImage == null
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "validating before anything was analysed is refused" {
    scratch := IncrementalScratch("single-pass-refused")
    try {
        IncrementalWriteProject(scratch)
        config := ProjectFileParser.Parse(Path.Combine(scratch, "project.yml"))
        compiler := new MultiFileCompiler(scratch, config, null, true)
        refused := false
        try {
            compiler.ValidateAnalyzedEmission("Lib")
        } catch error: InvalidOperationException {
            refused = error.Message.Contains("CompileForAnalysis")
        }
        assert refused
    } finally {
        IncrementalCleanup(scratch)
    }
}
