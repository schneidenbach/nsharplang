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
                if code == "NL102"
                    && QueryInt(diagnostic, "Line") == 6
                    && message.Contains("Expected expression after '+'", StringComparison.Ordinal) {
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
        assert diagnostics.Count <= 6,
            "Expected bounded diagnostics, got " + diagnostics.Count.ToString() + ": " + diagnosticSummary
    } finally {
        QueryDeleteTemp(projectRoot)
    }
}
