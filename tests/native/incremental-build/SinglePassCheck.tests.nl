namespace NSharpLang.IncrementalBuild.Tests

import System
import System.IO
import System.Text
import NSharpLang.Compiler

// `nlc check` ANALYSES ONCE. It used to analyse the project for its diagnostics and then hand the
// same project to a second compiler to prove it emits — every file parsed, analysed and the whole
// reference closure loaded twice. It now emits from the compiler that analysed it
// (`MultiFileCompiler.EmitAnalyzedAssembly`). These rows hold that door to exactly what a fresh
// `CompileToIlAssembly` produces.
func SinglePassRender(result: MultiFileCompilationResult): string {
    builder := new StringBuilder()
    for error in result.Errors {
        builder.AppendLine(error.FormatForTooling(true, true))
    }
    return builder.ToString()
}

test "emitting from the analysis already run produces a fresh compilation's bytes and diagnostics" {
    scratch := IncrementalScratch("single-pass")
    try {
        IncrementalWriteProject(scratch)
        config := ProjectFileParser.Parse(Path.Combine(scratch, "project.yml"))
        analysed := new MultiFileCompiler(scratch, config, null, true)
        analysed.CompileForAnalysis()
        reused := analysed.EmitAnalyzedAssembly("Lib", Path.Combine(scratch, "a", "Lib.dll"))

        fresh := new MultiFileCompiler(scratch, config, null, true)
        full := fresh.CompileToIlAssembly("Lib", Path.Combine(scratch, "b", "Lib.dll"), false, true)

        assert reused.Success, SinglePassRender(reused)
        assert full.Success
        assert SinglePassRender(reused) == SinglePassRender(full)
        assert ContentHash.OfFileOrMissing(Path.Combine(scratch, "a", "Lib.dll")) == ContentHash.OfFileOrMissing(Path.Combine(scratch, "b", "Lib.dll"))
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "an analysis error stops the emission exactly as a fresh compilation's does" {
    scratch := IncrementalScratch("single-pass-error")
    try {
        IncrementalWriteProject(scratch)
        report := Path.Combine(scratch, "Report.nl")
        File.WriteAllText(report, File.ReadAllText(report).Replace("Twice(", "Thrice("))
        config := ProjectFileParser.Parse(Path.Combine(scratch, "project.yml"))
        analysed := new MultiFileCompiler(scratch, config, null, true)
        analysed.CompileForAnalysis()
        reused := analysed.EmitAnalyzedAssembly("Lib", Path.Combine(scratch, "a", "Lib.dll"))
        full := new MultiFileCompiler(scratch, config, null, true).CompileToIlAssembly("Lib", Path.Combine(scratch, "b", "Lib.dll"), false, true)

        assert !reused.Success
        assert !full.Success
        assert SinglePassRender(reused) == SinglePassRender(full)
        assert !File.Exists(Path.Combine(scratch, "a", "Lib.dll"))
    } finally {
        IncrementalCleanup(scratch)
    }
}

test "emitting before anything was analysed is refused" {
    scratch := IncrementalScratch("single-pass-refused")
    try {
        IncrementalWriteProject(scratch)
        config := ProjectFileParser.Parse(Path.Combine(scratch, "project.yml"))
        compiler := new MultiFileCompiler(scratch, config, null, true)
        refused := false
        try {
            compiler.EmitAnalyzedAssembly("Lib", Path.Combine(scratch, "a", "Lib.dll"))
        } catch error: InvalidOperationException {
            refused = error.Message.Contains("CompileForAnalysis")
        }
        assert refused
    } finally {
        IncrementalCleanup(scratch)
    }
}
