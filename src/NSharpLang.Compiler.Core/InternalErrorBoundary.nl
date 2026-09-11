namespace NSharpLang.Cli

import System
import NSharpLang.Compiler

// The process boundary owns unexpected failures; command-local diagnostic handling stays with
// each command. The action is the entry-point seam, not a second command dispatcher.
class InternalErrorBoundary {
    static func Execute(action: Func<int>): int {
        try {
            return action()
        } catch error: Exception {
            Console.Error.WriteLine(Render(error, ""))
            return ExitCode()
        }
    }

    static func ExitCode(): int {
        return 2
    }

    // The boundary does not guess a source span. Callers with a known source file may supply it;
    // the process entry point has only arguments, so it deliberately supplies no file.
    static func Render(error: Exception, filePath: string): string {
        boxed: object = error
        exceptionType := boxed.GetType()
        headline := "error NL924: Internal compiler error."
        if filePath.Length > 0 {
            headline = filePath + ": " + headline
        }

        return headline + "\nThis is a bug in N#, not in your code.\n" + error.Message + "\nException: " + exceptionType.get_FullName() + "\nReport this failure: " + DiagnosticDocs.UrlFor("NL924")
    }
}
