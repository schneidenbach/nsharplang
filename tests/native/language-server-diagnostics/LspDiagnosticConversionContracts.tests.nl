namespace NSharpLang.LanguageServerDiagnostics.Tests

import System
import NSharpLang.Compiler

// Conversion-invariant coverage for LspDiagnosticConverter.
//
// These rows drive the converter with hand-built CompilerError / Diagnostic values so the
// 1-based -> 0-based, end-exclusive, length >= 1 and clamp invariants are asserted independently
// of any analyzer raise-site span (which the other suites in this project own).
test "linter diagnostic keeps the exact linter span when converted for the editor" {
    diagnostic := new Diagnostic(
        "NL012",
        "Parameter 'unusedName' in 'greet' is never read — is it needed?",
        new Location(1, 12, "Program.nl"),
        DiagnosticSeverity.Info,
        "Prefix with '_' if this is intentional",
        "unusedName".Length
    )

    LscAssertRange(LscConvertLinterDiagnostic(diagnostic), 0, 11, 21)
}

test "compiler span at line one column one converts to the first character" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 1, 1, ErrorSeverity.Error) {
        Length: 1
    }

    LscAssertRange(LscConvertCompilerError(error), 0, 0, 1)
}

test "mid line compiler span converts to a zero based end exclusive range" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 5, 10, ErrorSeverity.Error) {
        Length: 4
    }

    LscAssertRange(LscConvertCompilerError(error), 4, 9, 13)
}

test "compiler span with zero length still underlines one column" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 3, 3, ErrorSeverity.Error) {
        Length: 0
    }

    LscAssertRange(LscConvertCompilerError(error), 2, 2, 3)
}

test "compiler span with negative length still underlines one column" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 3, 3, ErrorSeverity.Error) {
        Length: -7
    }

    LscAssertRange(LscConvertCompilerError(error), 2, 2, 3)
}

test "compiler span at line zero column zero clamps to the first character" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 0, 0, ErrorSeverity.Error) {
        Length: 1
    }

    LscAssertRange(LscConvertCompilerError(error), 0, 0, 1)
}

test "negative compiler line and column clamp to the first character without throwing" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", -4, -9, ErrorSeverity.Error) {
        Length: 1
    }

    LscAssertRange(LscConvertCompilerError(error), 0, 0, 1)
}

test "large compiler span with no source snippet is left intact" {
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 2, 1, ErrorSeverity.Error) {
        Length: 250
    }

    LscAssertRange(LscConvertCompilerError(error), 1, 0, 250)
}

test "compiler span on the final character of a line ends at the line length" {
    // "abc" is 3 chars; a length-1 span on the final char ('c') ends exactly at the line length.
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 1, 3, ErrorSeverity.Error) {
        Length: 1,
        SourceSnippet: "abc"
    }

    LscAssertRange(LscConvertCompilerError(error), 0, 2, 3)
}

test "overlong compiler span is clamped to the visible line length" {
    // A defective length that would otherwise overflow past the end of the visible line must be
    // clamped to the line length so the squiggle does not bleed into virtual whitespace.
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 2, 5, ErrorSeverity.Error) {
        Length: 100,
        SourceSnippet: "    nums := [1, 2"
    }

    LscAssertRange(LscConvertCompilerError(error), 1, 4, "    nums := [1, 2".Length)
}

test "overlong compiler span starting past the line end never collapses below one column" {
    // Even when the start sits at (or past) the visible end of the line, the clamp must keep the
    // range non-empty: end stays strictly greater than start.
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 1, 6, ErrorSeverity.Error) {
        Length: 50,
        SourceSnippet: "abcd"
    }

    LscAssertRange(LscConvertCompilerError(error), 0, 5, 6)
}

test "multi line snippet clamps the compiler span against its first line only" {
    // SourceSnippet may carry more than the starting line; the span is single-line by contract so
    // the clamp considers only the first physical line and never wraps end onto a later line.
    error := new CompilerError(ErrorCode.InvalidSyntax, "synthetic", 1, 1, ErrorSeverity.Error) {
        Length: 100,
        SourceSnippet: "abc\ndefghijklmnop"
    }

    LscAssertRange(LscConvertCompilerError(error), 0, 0, "abc".Length)
}

test "linter span at line one column one converts to the first character" {
    diagnostic := new Diagnostic(
        "NL012",
        "synthetic",
        new Location(1, 1, "Program.nl"),
        DiagnosticSeverity.Info,
        null,
        1
    )

    LscAssertRange(LscConvertLinterDiagnostic(diagnostic), 0, 0, 1)
}

test "mid line linter span converts to a zero based end exclusive range" {
    diagnostic := new Diagnostic(
        "NL012",
        "synthetic",
        new Location(7, 12, "Program.nl"),
        DiagnosticSeverity.Info,
        null,
        10
    )

    LscAssertRange(LscConvertLinterDiagnostic(diagnostic), 6, 11, 21)
}

test "linter span with zero length still underlines one column" {
    diagnostic := new Diagnostic(
        "NL012",
        "synthetic",
        new Location(3, 3, "Program.nl"),
        DiagnosticSeverity.Info,
        null,
        0
    )

    LscAssertRange(LscConvertLinterDiagnostic(diagnostic), 2, 2, 3)
}

test "linter span at line zero column zero with negative length clamps to the first character" {
    diagnostic := new Diagnostic(
        "NL012",
        "synthetic",
        new Location(0, 0, "Program.nl"),
        DiagnosticSeverity.Info,
        null,
        -3
    )

    LscAssertRange(LscConvertLinterDiagnostic(diagnostic), 0, 0, 1)
}

test "linter error severity maps to the lsp error severity" {
    diagnostic := new Diagnostic(
        "NL001",
        "synthetic",
        new Location(1, 1, "Program.nl"),
        DiagnosticSeverity.Error,
        null,
        1
    )

    lsp := LscConvertLinterDiagnostic(diagnostic)
    assert LscIsError(lsp)
    assert !LscIsWarning(lsp)
    assert !LscIsInformation(lsp)
}

test "linter warning severity maps to the lsp warning severity" {
    diagnostic := new Diagnostic(
        "NL001",
        "synthetic",
        new Location(1, 1, "Program.nl"),
        DiagnosticSeverity.Warning,
        null,
        1
    )

    lsp := LscConvertLinterDiagnostic(diagnostic)
    assert LscIsWarning(lsp)
    assert !LscIsError(lsp)
    assert !LscIsInformation(lsp)
}

test "linter info severity maps to the lsp information severity" {
    diagnostic := new Diagnostic(
        "NL001",
        "synthetic",
        new Location(1, 1, "Program.nl"),
        DiagnosticSeverity.Info,
        null,
        1
    )

    lsp := LscConvertLinterDiagnostic(diagnostic)
    assert LscIsInformation(lsp)
    assert !LscIsError(lsp)
    assert !LscIsWarning(lsp)
}

test "compiler error severity maps to the lsp error severity" {
    error := new CompilerError(ErrorCode.TypeMismatch, "synthetic", 1, 1, ErrorSeverity.Error)

    lsp := LscConvertCompilerError(error)
    assert LscIsError(lsp)
    assert !LscIsWarning(lsp)
    assert !LscIsInformation(lsp)
}

test "compiler warning severity maps to the lsp warning severity" {
    error := new CompilerError(ErrorCode.TypeMismatch, "synthetic", 1, 1, ErrorSeverity.Warning)

    lsp := LscConvertCompilerError(error)
    assert LscIsWarning(lsp)
    assert !LscIsError(lsp)
    assert !LscIsInformation(lsp)
}

// Coverage sweep: every compiler ErrorCode (NL1xx-NL9xx) and every linter rule (NL0xx) must
// produce a deterministic LSP range obeying the conversion invariants. This guards against a new
// diagnostic code being added without the converter being exercised for it.

test "every compiler error code produces a valid lsp range carrying its code and source" {
    line := 4
    column := 7
    length := 5

    values := Enum.GetValues(typeof(ErrorCode))
    assert values.Length > 0

    index := 0
    while index < values.Length {
        code := (ErrorCode)Convert.ToInt32(values.GetValue(index))
        severity := ErrorSeverity.Error
        if code == ErrorCode.VisibilityConventionWarning || code == ErrorCode.ReferenceLoadFailure {
            severity = ErrorSeverity.Warning
        }

        codeNumber: int = (int)code
        error := new CompilerError(code, "synthetic NL" + codeNumber.ToString("D3"), line, column, severity) {
            Length: length
        }

        lsp := LscConvertCompilerError(error)
        assert LscCodeText(lsp) == "NL" + codeNumber.ToString("D3")
        assert LscSourceText(lsp) == "N#"
        LscAssertRange(lsp, line - 1, column - 1, column - 1 + length)

        index = index + 1
    }
}

test "every linter rule descriptor produces a valid lsp range carrying its code and source" {
    line := 4
    column := 7
    length := 5

    descriptorCount := 0
    for descriptor in DiagnosticCatalog.LinterDescriptors {
        diagnostic := new Diagnostic(
            descriptor.Code,
            "synthetic " + descriptor.Code,
            new Location(line, column, "Program.nl"),
            descriptor.DefaultSeverity,
            null,
            length
        )

        lsp := LscConvertLinterDiagnostic(diagnostic)
        assert LscCodeText(lsp) == descriptor.Code
        assert LscSourceText(lsp) == "N#"
        LscAssertRange(lsp, line - 1, column - 1, column - 1 + length)

        descriptorCount = descriptorCount + 1
    }

    assert descriptorCount > 0
}
