namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler

class SystemsFindingDiagnostics {
    static func ToCompilerError(finding: SystemsFinding): CompilerError {
        severity := ErrorSeverity.Warning
        if string.Equals(finding.Severity, "error", StringComparison.OrdinalIgnoreCase) {
            severity = ErrorSeverity.Error
        }

        return new CompilerError(ErrorCode.InvalidSyntax, finding.Message, finding.Line, finding.Column, severity) {
            DiagnosticIdOverride: finding.Code,
            FileName: finding.File,
            Length: finding.Length,
            Suggestion: finding.Suggestion,
            HumanExplanation: "Systems policy '" + PolicyName(finding.Policy) + "' rejected the '" + finding.Effect + "' effect.",
            ContextualHint: CallPathHint(finding.CallPath),
            DocsUrl: "https://docs.n-sharp.dev/errors/" + finding.Code
        }
    }

    static func PolicyName(policy: string?): string {
        if policy == null {
            return "local"
        }

        return policy
    }

    static func CallPathHint(callPath: IReadOnlyList<string>): string? {
        if callPath.Count == 0 {
            return null
        }

        result := callPath[0]
        i := 1
        while i < callPath.Count {
            result = result + " -> " + callPath[i]
            i = i + 1
        }

        return "effect path: " + result
    }
}
