namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// These nine facts are the direct MultiFileCompiler portion of the deleted
// ErrorRecoveryPipelineTests.cs suite. Their fixtures retain the original decoded bytes: the two
// verbatim malformed-file pairs keep their leading and trailing LF, raw-string project fixtures
// have neither, and the CRLF case is assembled without a trailing line ending.
func MfcRecoveryTempRoot(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-errrecovery-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func MfcRecoveryDeleteTemp(root: string) {
    if Directory.Exists(root) {
        Directory.Delete(root, true)
    }
}

func MfcRecoveryWrite(root: string, fileName: string, source: string) {
    File.WriteAllText(Path.Combine(root, fileName), source)
}

func MfcRecoveryDescribeErrors(errors: IReadOnlyList<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        error := errors[index]
        if text.Length > 0 {
            text = text + "; "
        }
        text = text + "[" + (error.FileName ?? "") + ":" + error.Line.ToString() + "] " + error.Message
        index = index + 1
    }
    return text
}

func MfcRecoveryCountFileErrors(errors: IReadOnlyList<CompilerError>, fileNameFragment: string): int {
    count := 0
    index := 0
    while index < errors.Count {
        fileName := errors[index].FileName ?? ""
        if fileName.Contains(fileNameFragment, StringComparison.Ordinal) {
            count = count + 1
        }
        index = index + 1
    }
    return count
}

func MfcRecoveryCountCode(errors: IReadOnlyList<CompilerError>, code: ErrorCode): int {
    count := 0
    index := 0
    while index < errors.Count {
        if errors[index].Code == code {
            count = count + 1
        }
        index = index + 1
    }
    return count
}

func MfcRecoveryFirstCode(errors: IReadOnlyList<CompilerError>, code: ErrorCode): CompilerError {
    index := 0
    while index < errors.Count {
        if errors[index].Code == code {
            return errors[index]
        }
        index = index + 1
    }
    return errors[0]
}

func MfcRecoveryTwoDigitFileStem(index: int): string {
    if index < 10 {
        return "F0" + index.ToString()
    }
    return "F" + index.ToString()
}

test "MultiFileCompiler_SyntaxErrorInOneFile_SemanticErrorInOther_BothReported" {
    root := MfcRecoveryTempRoot()
    try {
        MfcRecoveryWrite(root, "FileA.nl", "\nfunc broken() {\n    let x: int = @@\n}\n")
        MfcRecoveryWrite(root, "FileB.nl", "\nfunc valid_syntax_but_bad_semantics() {\n    Console.WriteLine(thisVarDoesNotExist)\n}\n")

        compiler := new MultiFileCompiler(root)
        compiler.CompileForAnalysis()
        errors := compiler.AllErrors

        assert errors.Count >= 2,
            "Expected errors from both files, got " + errors.Count.ToString() + ": " + MfcRecoveryDescribeErrors(errors)
        assert MfcRecoveryCountFileErrors(errors, "FileA") >= 1,
            "Expected at least 1 error from FileA (syntax error)"
        assert MfcRecoveryCountFileErrors(errors, "FileB") >= 1,
            "Expected at least 1 error from FileB (semantic error), got " + MfcRecoveryCountFileErrors(errors, "FileB").ToString() + ". All errors: " + MfcRecoveryDescribeErrors(errors)
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}

test "MultiFileCompiler_AllFilesParsedCleanly_AllSemanticErrorsReported" {
    root := MfcRecoveryTempRoot()
    try {
        MfcRecoveryWrite(root, "FileA.nl", "\nfunc funcA() {\n    Console.WriteLine(undefinedA)\n}\n")
        MfcRecoveryWrite(root, "FileB.nl", "\nfunc funcB() {\n    Console.WriteLine(undefinedB)\n}\n")

        compiler := new MultiFileCompiler(root)
        compiler.CompileForAnalysis()
        errors := compiler.AllErrors

        assert MfcRecoveryCountFileErrors(errors, "FileA") >= 1, "Expected at least 1 error from FileA"
        assert MfcRecoveryCountFileErrors(errors, "FileB") >= 1, "Expected at least 1 error from FileB"
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}

test "MultiFileCompiler_CircularFileImports_ReportOneBoundedCycleDiagnostic" {
    root := MfcRecoveryTempRoot()
    try {
        MfcRecoveryWrite(root, "A.nl", "import \"B\"\n\nclass A {\n}")
        MfcRecoveryWrite(root, "B.nl", "import \"C\"\n\nclass B {\n}")
        MfcRecoveryWrite(root, "C.nl", "import \"A\"\n\nclass C {\n}")

        compiler := new MultiFileCompiler(root)
        compiler.CompileForAnalysis()
        assert MfcRecoveryCountCode(compiler.AllErrors, ErrorCode.CircularImport) == 1,
            "Expected exactly one CircularImport diagnostic: " + MfcRecoveryDescribeErrors(compiler.AllErrors)
        cycle := MfcRecoveryFirstCode(compiler.AllErrors, ErrorCode.CircularImport)

        assert cycle.Message.Contains("A.nl -> B.nl -> C.nl -> A.nl", StringComparison.Ordinal)
        assert cycle.HumanExplanation.Contains("A.nl -> B.nl -> C.nl -> A.nl", StringComparison.Ordinal)
        assert cycle.ContextualHint.Contains("Import path: A.nl -> B.nl -> C.nl -> A.nl", StringComparison.Ordinal)
        assert cycle.Suggestion.Contains("Move shared types", StringComparison.Ordinal)
        assert (cycle.FileName ?? "").EndsWith("C.nl", StringComparison.Ordinal)
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}

test "MultiFileCompiler_TwoFileCircularImports_DeduplicatesAnalyzerCycleDiagnostics" {
    root := MfcRecoveryTempRoot()
    try {
        MfcRecoveryWrite(root, "A.nl", "import \"B\"\n\nclass A {\n}")
        MfcRecoveryWrite(root, "B.nl", "import \"A\"\n\nclass B {\n}")

        compiler := new MultiFileCompiler(root)
        compiler.CompileForAnalysis()
        assert MfcRecoveryCountCode(compiler.AllErrors, ErrorCode.CircularImport) == 1,
            "Expected exactly one CircularImport diagnostic: " + MfcRecoveryDescribeErrors(compiler.AllErrors)
        cycle := MfcRecoveryFirstCode(compiler.AllErrors, ErrorCode.CircularImport)

        assert cycle.Message.Contains("A.nl -> B.nl -> A.nl", StringComparison.Ordinal)
        assert cycle.ContextualHint.Contains("Import path: A.nl -> B.nl -> A.nl", StringComparison.Ordinal)
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}

test "MultiFileCompiler_LongCircularFileImports_BoundsDiagnosticCyclePath" {
    root := MfcRecoveryTempRoot()
    try {
        fileCount := 12
        index := 0
        while index < fileCount {
            current := MfcRecoveryTwoDigitFileStem(index)
            next := MfcRecoveryTwoDigitFileStem((index + 1) % fileCount)
            MfcRecoveryWrite(root, current + ".nl", "import \"" + next + "\"\n\nclass " + current + " {\n}")
            index = index + 1
        }

        compiler := new MultiFileCompiler(root)
        compiler.CompileForAnalysis()
        assert MfcRecoveryCountCode(compiler.AllErrors, ErrorCode.CircularImport) == 1,
            "Expected exactly one CircularImport diagnostic: " + MfcRecoveryDescribeErrors(compiler.AllErrors)
        cycle := MfcRecoveryFirstCode(compiler.AllErrors, ErrorCode.CircularImport)

        assert cycle.Message.Contains("F00.nl -> F01.nl -> F02.nl -> F03.nl -> F04.nl -> F05.nl", StringComparison.Ordinal)
        assert cycle.Message.Contains("... (4 more imports) -> F10.nl -> F11.nl -> F00.nl", StringComparison.Ordinal)
        assert !cycle.Message.Contains("F06.nl -> F07.nl -> F08.nl -> F09.nl", StringComparison.Ordinal)
        assert cycle.ContextualHint.Contains("... (4 more imports)", StringComparison.Ordinal)
        assert cycle.Suggestion.Contains("Move shared types", StringComparison.Ordinal)
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}

test "MultiFileCompiler_DenseCircularFileImports_BoundsDiagnosticCount" {
    root := MfcRecoveryTempRoot()
    try {
        fileCount := 8
        index := 0
        while index < fileCount {
            imports := ""
            nextIndex := 0
            while nextIndex < fileCount {
                if nextIndex != index {
                    if imports.Length > 0 {
                        imports = imports + "\n"
                    }
                    imports = imports + "import \"" + MfcRecoveryTwoDigitFileStem(nextIndex) + "\""
                }
                nextIndex = nextIndex + 1
            }
            current := MfcRecoveryTwoDigitFileStem(index)
            MfcRecoveryWrite(root, current + ".nl", imports + "\n\nclass " + current + " {\n}")
            index = index + 1
        }

        compiler := new MultiFileCompiler(root)
        compiler.CompileForAnalysis()
        cycleCount := MfcRecoveryCountCode(compiler.AllErrors, ErrorCode.CircularImport)

        assert cycleCount > 0
        assert cycleCount <= 20, "Expected bounded cycle diagnostics, got " + cycleCount.ToString() + "."
        errorIndex := 0
        while errorIndex < compiler.AllErrors.Count {
            error := compiler.AllErrors[errorIndex]
            if error.Code == ErrorCode.CircularImport {
                assert error.Message.Contains(" -> ", StringComparison.Ordinal)
            }
            errorIndex = errorIndex + 1
        }
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}

test "MultiFileCompiler_CircularFileImports_UsesSourceTextOverridesAndImportCasing" {
    root := MfcRecoveryTempRoot()
    try {
        aPath := Path.Combine(root, "A.nl")
        bPath := Path.Combine(root, "B.nl")
        overrides := new Dictionary<string, string>()
        overrides[aPath] = "import \"b\"\n\nclass A {\n}"
        overrides[bPath] = "import \"A\"\n\nclass B {\n}"

        config := ProjectFileParser.CreateDefault(null)
        compiler := new MultiFileCompiler(root, config, overrides)
        compiler.CompileForAnalysis()
        assert MfcRecoveryCountCode(compiler.AllErrors, ErrorCode.CircularImport) == 1,
            "Expected exactly one CircularImport diagnostic: " + MfcRecoveryDescribeErrors(compiler.AllErrors)
        cycle := MfcRecoveryFirstCode(compiler.AllErrors, ErrorCode.CircularImport)

        assert cycle.Message.Contains("A.nl -> B.nl -> A.nl", StringComparison.Ordinal)
        assert cycle.SourceSnippet == "import \"A\""
        assert MfcRecoveryCountCode(compiler.AllErrors, ErrorCode.ImportNotFound) == 0
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}

test "MultiFileCompiler_CircularFileImports_CrLfSourceSnippetHasNoTrailingCarriageReturn" {
    root := MfcRecoveryTempRoot()
    try {
        MfcRecoveryWrite(root, "A.nl", "import \"B\"\r\n\r\nclass A {\r\n}")
        MfcRecoveryWrite(root, "B.nl", "import \"A\"\r\n\r\nclass B {\r\n}")

        compiler := new MultiFileCompiler(root)
        compiler.CompileForAnalysis()
        assert MfcRecoveryCountCode(compiler.AllErrors, ErrorCode.CircularImport) == 1,
            "Expected exactly one CircularImport diagnostic: " + MfcRecoveryDescribeErrors(compiler.AllErrors)
        cycle := MfcRecoveryFirstCode(compiler.AllErrors, ErrorCode.CircularImport)

        assert cycle.SourceSnippet == "import \"A\""
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}

test "CompileForAnalysis_SyntaxErrorInOneFile_StillReportsSemanticErrors" {
    root := MfcRecoveryTempRoot()
    try {
        MfcRecoveryWrite(root, "FileA.nl", "\nfunc broken() {\n    let x: int = @@\n}\n")
        MfcRecoveryWrite(root, "FileB.nl", "\nfunc valid_syntax() {\n    Console.WriteLine(noSuchVariable)\n}\n")

        compiler := new MultiFileCompiler(root)
        compiler.CompileForAnalysis()
        errors := compiler.AllErrors

        assert MfcRecoveryCountFileErrors(errors, "FileA") >= 1, "Expected syntax errors from FileA"
        assert MfcRecoveryCountFileErrors(errors, "FileB") >= 1,
            "Expected semantic errors from FileB, got " + MfcRecoveryCountFileErrors(errors, "FileB").ToString() + ". All errors: " + MfcRecoveryDescribeErrors(errors)
    } finally {
        MfcRecoveryDeleteTemp(root)
    }
}
