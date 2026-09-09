namespace NSharpLang.QueryIntegration.Tests

import System


// CodeIntelligenceService stays in Compiler, so this one integration fact remains in the native
// query estate. The project.yml and Program.nl strings are byte-for-byte the decoded C# raw
// literals from ErrorRecoveryPipelineTests.cs: neither has a leading nor trailing line ending.
test "QueryDiagnostics_MalformedProject_ReturnsSyntaxAndSemanticDiagnosticsWithoutPlaceholderCascade" {
    projectRoot := QueryTempRoot()
    try {
        QueryWriteProjectYaml(
            projectRoot,
            "name: MalformedDiagnostics\noutputType: exe\ntargetFramework: net10.0"
        )
        QueryWriteSource(
            projectRoot,
            "Program.nl",
            "class User {\n    Name: string\n}\n\nfunc main() {\n    first := 1 +\n    Console.WriteLine(undefinedFromQuery)\n}"
        )

        snapshot := QueryLoadProject(projectRoot)
        diagnostics := QueryGetDiagnostics(snapshot, "Program.nl")
        hasExpectedExpression := false
        hasUndefinedName := false
        hasPlaceholder := false
        diagnosticSummary := ""
        index := 0
        while index < diagnostics.Count {
            diagnostic := diagnostics[index]
            if diagnostic != null {
                code := QueryText(diagnostic, "Code")
                message := QueryText(diagnostic, "Message")
                if diagnosticSummary.Length > 0 {
                    diagnosticSummary = diagnosticSummary + "; "
                }
                diagnosticSummary = diagnosticSummary + code + " " + message
                if code == "NL102" && QueryInt(diagnostic, "Line") == 6 && message.Contains("Expected expression after '+'", StringComparison.Ordinal) {
                    hasExpectedExpression = true
                }
                if code == "NL301" && message.Contains("undefinedFromQuery", StringComparison.Ordinal) {
                    hasUndefinedName = true
                }
                if message.Contains("<error>", StringComparison.Ordinal) {
                    hasPlaceholder = true
                }
            }
            index = index + 1
        }

        assert hasExpectedExpression
        assert hasUndefinedName
        assert !hasPlaceholder
        assert diagnostics.Count <= 6, "Expected bounded diagnostics, got " + diagnostics.Count.ToString() + ": " + diagnosticSummary
    } finally {
        QueryDeleteTemp(projectRoot)
    }
}

// These two fixtures are the exact decoded source strings from CliCommandTests. They use the same
// public CodeIntelligenceService path while the C# facts retain the command envelope and rendering.
test "query diagnostics keep the exact malformed CLI fixture bounded without placeholder cascade" {
    projectRoot := QueryTempRoot()
    try {
        QueryWriteProjectYaml(
            projectRoot,
            "name: MalformedDiagnostics\noutputType: exe\ntargetFramework: net10.0"
        )
        QueryWriteSource(
            projectRoot,
            "Program.nl",
            "class User {\n    Name: string\n}\n\nfunc main() {\n    first := 1 +\n    Console.WriteLine(undefinedFromCli)\n}"
        )

        snapshot := QueryLoadProject(projectRoot)
        diagnostics := QueryGetDiagnostics(snapshot, "Program.nl")
        hasExpectedExpression := false
        hasExpectedSuggestion := false
        hasUndefinedName := false
        hasPlaceholder := false
        diagnosticSummary := ""
        index := 0
        while index < diagnostics.Count {
            diagnostic := diagnostics[index]
            if diagnostic != null {
                code := QueryText(diagnostic, "Code")
                message := QueryText(diagnostic, "Message")
                if diagnosticSummary.Length > 0 {
                    diagnosticSummary = diagnosticSummary + "; "
                }
                diagnosticSummary = diagnosticSummary + code + " " + message
                if code == "NL102" && QueryInt(diagnostic, "Line") == 6 && message.Contains("Expected expression after '+'", StringComparison.Ordinal) {
                    hasExpectedExpression = true
                    if QueryText(diagnostic, "Suggestion").Contains("Add an expression after '+'", StringComparison.Ordinal) {
                        hasExpectedSuggestion = true
                    }
                }
                if code == "NL301" && message.Contains("undefinedFromCli", StringComparison.Ordinal) {
                    hasUndefinedName = true
                }
                if message.Contains("<error>", StringComparison.Ordinal) {
                    hasPlaceholder = true
                }
            }
            index = index + 1
        }

        assert hasExpectedExpression
        assert hasExpectedSuggestion
        assert hasUndefinedName
        assert !hasPlaceholder
        assert diagnostics.Count <= 4, "Expected bounded diagnostics, got " + diagnostics.Count.ToString() + ": " + diagnosticSummary
    } finally {
        QueryDeleteTemp(projectRoot)
    }
}

test "query diagnostics include strict lint errors for otherwise valid source" {
    projectRoot := QueryTempRoot()
    try {
        QueryWriteProjectYaml(
            projectRoot,
            "name: LintDiagnostics\noutputType: exe\ntargetFramework: net10.0"
        )
        QueryWriteSource(
            projectRoot,
            "Program.nl",
            "func main() {\n    unused := 42\n}"
        )

        snapshot := QueryLoadProject(projectRoot)
        diagnostics := QueryGetDiagnostics(snapshot, "Program.nl")
        unusedCount := 0
        diagnosticSummary := ""
        index := 0
        while index < diagnostics.Count {
            diagnostic := diagnostics[index]
            if diagnostic != null {
                code := QueryText(diagnostic, "Code")
                severity := QueryText(diagnostic, "Severity")
                message := QueryText(diagnostic, "Message")
                if diagnosticSummary.Length > 0 {
                    diagnosticSummary = diagnosticSummary + "; "
                }
                diagnosticSummary = diagnosticSummary + code + " " + severity + " " + message
                if code == "NL001" {
                    unusedCount = unusedCount + 1
                    assert severity == "error", "Expected NL001 severity error, got " + severity + ": " + diagnosticSummary
                    assert message == "Variable 'unused' is declared but never read", "Unexpected NL001 message: " + message
                }
            }
            index = index + 1
        }

        assert unusedCount == 1, "Expected one NL001 diagnostic, got " + unusedCount.ToString() + ": " + diagnosticSummary
        assert diagnostics.Count == 1, "Expected only the strict-lint diagnostic, got " + diagnostics.Count.ToString() + ": " + diagnosticSummary
    } finally {
        QueryDeleteTemp(projectRoot)
    }
}
