namespace NSharpLang.Cli.Commands

import NSharpLang.Compiler.CodeIntelligence

public class QueryCommandDogfoodKernels {
    public static func WithOutlineFile(result: OutlineResult, outputFile: string): OutlineResult {
        return new OutlineResult(outputFile, result.Imports, result.Outline)
    }
}
