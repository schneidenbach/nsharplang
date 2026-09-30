namespace NSharpLang.Cli

import System
import NSharpLang.Compiler

// One owner for the CLI's single-line failure report. Every command that fails for a reason it can
// name writes exactly this line to STDERR and answers 1, so the sentence and the exit code cannot
// drift apart between commands. The sentence itself belongs to ProgramCommandKernels; this owner
// only decides the stream and the code.
class CliError {
    static func Report(message: string): int {
        Console.Error.WriteLine(ProgramCommandKernels.GetErrorLine(message))
        return 1
    }
}
