namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// PARALLELISM IS INVISIBLE IN THE OUTPUT. `MultiFileCompiler.Workers` fans the analysis pass and the
// columnar back end's per-file parse out to several threads; whatever the worker count, the
// diagnostics must come back in the same order with the same text and the emitted assembly must be
// byte-for-byte the serial one. These rows compile the same projects at one worker and at several and
// compare everything a caller can read.
//
// The fixtures are shaped to reach the two places a parallel analysis could drift: a namespace import
// that LOADS an assembly the analyzer does not load up front (`System.IO.Compression`), in the first
// file, whose types a later file names without importing them -- a serial analysis carries that load
// into every later file and a worker replays it (`Analyzer.PreloadImportedAssemblies`) -- and
// diagnostics in several files, whose order is the merge's. Two to eight workers over ten files
// exercise both an even split and more workers than a fair share.
func PanRoot(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-parallel-analysis-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func PanWrite(root: string, relativePath: string, source: string) {
    path := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, source)
}

func PanDescribe(errors: IEnumerable<CompilerError>): string {
    text := ""
    for error in errors {
        text = text + error.DiagnosticId + " " + Path.GetFileName(error.FileName ?? "") + ":" + error.Line.ToString() + ":" + error.Column.ToString() + " " + error.Message + "\n"
    }
    return text
}

func PanWriteProject(root: string, withErrors: bool) {
    PanWrite(root, "project.yml", "name: PanApp\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    // `System.IO.Compression` is not among the assemblies an analyzer loads up front, so this import
    // LOADS one -- in the first file, which every later file's analysis inherits. The error fixture
    // names `ZipArchive` without importing it in a late file; the emitted one only imports it.
    levelFunction := ""
    if withErrors {
        levelFunction = "\nfunc Entries(archive: ZipArchive): int {\n    return archive.Entries.Count\n}\n"
    }
    PanWrite(root, "A/Json.nl", "namespace Pan.A\n\nimport System.IO.Compression\n\nfunc Encode(value: int): string {\n    return value.ToString()\n}\n" + levelFunction)
    index := 0
    while index < 9 {
        name := "F" + index.ToString()
        body := "namespace Pan.B\n\nimport System\nimport System.Collections.Generic\nimport Pan.A\n\nunion " + name + "Result {\n    Ok { value: int }\n    Failed { reason: string }\n}\n\nclass " + name + "Service {\n    items: List<int>\n\n    constructor() {\n        items = new List<int>()\n    }\n\n    func Add(value: int): " + name + "Result {\n        if value < 0 {\n            return new " + name + "Result.Failed { reason: Encode(value) }\n        }\n        items.Add(value)\n        return new " + name + "Result.Ok { value: items.Count }\n    }\n}\n\nfunc Score" + name + "(result: " + name + "Result): int {\n    return match result {\n        " + name + "Result.Ok { value } => value,\n        " + name + "Result.Failed { reason } => reason.Length\n    }\n}\n"
        if withErrors && index % 3 == 1 {
            body = body + "\nfunc Broken" + name + "(): int {\n    text: string = 42\n    return Missing" + name + "(text)\n}\n"
        }
        if withErrors && index == 7 {
            body = body + "\nfunc Late" + name + "(archive: ZipArchive): int {\n    return archive.Entries.Count\n}\n"
        }
        PanWrite(root, "B/" + name + ".nl", body)
        index = index + 1
    }
}

func PanCompile(root: string, workers: int, outputPath: string): MultiFileCompilationResult {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    compiler.Workers = workers
    return compiler.CompileToIlAssembly("PanApp", outputPath, false, true)
}

test "parallel analysis emits the serial assembly byte for byte" {
    root := PanRoot()
    try {
        PanWriteProject(root, false)
        serialPath := Path.Combine(root, "out-serial", "PanApp.dll")
        parallelPath := Path.Combine(root, "out-parallel", "PanApp.dll")
        serial := PanCompile(root, 1, serialPath)
        assert serial.Success, PanDescribe(serial.Errors)
        parallel := PanCompile(root, 4, parallelPath)
        assert parallel.Success, PanDescribe(parallel.Errors)
        assert PanDescribe(parallel.Errors) == PanDescribe(serial.Errors)

        serialBytes := File.ReadAllBytes(serialPath)
        parallelBytes := File.ReadAllBytes(parallelPath)
        assert serialBytes.Length == parallelBytes.Length
        index := 0
        while index < serialBytes.Length {
            assert serialBytes[index] == parallelBytes[index], "first differing byte at " + index.ToString()
            index = index + 1
        }
    } finally {
        Directory.Delete(root, true)
    }
}

test "parallel analysis reports the serial diagnostics in the serial order" {
    root := PanRoot()
    try {
        PanWriteProject(root, true)
        serial := PanCompile(root, 1, Path.Combine(root, "out-serial", "PanApp.dll"))
        assert !serial.Success
        serialText := PanDescribe(serial.Errors)
        assert serialText.Split('\n').Length >= 7, serialText
        for workers in [2, 3, 4, 8] {
            parallel := PanCompile(root, workers, Path.Combine(root, "out-" + workers.ToString(), "PanApp.dll"))
            assert !parallel.Success
            parallelText := PanDescribe(parallel.Errors)
            assert parallelText == serialText, "workers=" + workers.ToString() + "\n" + parallelText
        }
    } finally {
        Directory.Delete(root, true)
    }
}

// THE PARSE'S DECLINE TRACE IS THE SERIAL ONE. A later file uses a shape the columnar back end does not
// model, so emission is refused with an NL103 that names the site and the file; with the per-file
// parse fanned out, that file is parsed on a worker whose thread-local trace must be handed back in
// file order -- the refusal has to read exactly as the serial one, and the earlier files' clean
// parses must add nothing to it.
test "parallel columnar parse reports the serial emission refusal" {
    root := PanRoot()
    try {
        PanWriteProject(root, false)
        PanWrite(root, "B/Late.nl", "namespace Pan.B\n\nunion LateResult {\n    Ok { value: int }\n    Failed { reason: string }\n}\n\nfunc ScoreLate(result: LateResult): int {\n    return match result {\n        LateResult.Ok ok => ok.value,\n        _ => 0\n    }\n}\n")
        serial := PanCompile(root, 1, Path.Combine(root, "out-serial", "PanApp.dll"))
        assert !serial.Success
        serialText := PanDescribe(serial.Errors)
        assert serialText.Contains("NL103"), serialText
        for workers in [2, 4, 8] {
            parallel := PanCompile(root, workers, Path.Combine(root, "out-" + workers.ToString(), "PanApp.dll"))
            assert !parallel.Success
            parallelText := PanDescribe(parallel.Errors)
            assert parallelText == serialText, "workers=" + workers.ToString() + "\n" + parallelText
        }
    } finally {
        Directory.Delete(root, true)
    }
}
