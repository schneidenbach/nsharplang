namespace NSharpLang.Compiler

import System.Collections.Generic

public class MultiFileCompilationResult {
    successValue: bool
    errorsValue: IEnumerable<CompilerError>
    outputAssemblyPathValue: string?

    Success: bool => successValue
    Errors: IEnumerable<CompilerError> => errorsValue
    OutputAssemblyPath: string? => outputAssemblyPathValue

    constructor(Success: bool, Errors: IEnumerable<CompilerError>, OutputAssemblyPath: string? = null) {
        successValue = Success
        errorsValue = Errors
        outputAssemblyPathValue = OutputAssemblyPath
    }

    public func Deconstruct(out Success: bool, out Errors: IEnumerable<CompilerError>, out OutputAssemblyPath: string?) {
        Success = successValue
        Errors = errorsValue
        OutputAssemblyPath = outputAssemblyPathValue
    }
}
