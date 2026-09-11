namespace NSharpLang.Compiler

class ColumnarEmissionDiagnostics {
    static func RequiredAotEmissionError(assemblyName: string, detail: string? = null, fileName: string? = null, line: int = 0, column: int = 0, spanLength: int = 1): CompilerError {
        return new CompilerError(ErrorCode.InvalidSyntax, AddDetail("Columnar AOT emission is required for '" + assemblyName + "', but the columnar backend declined.", detail), line, column, ErrorSeverity.Error) {
            FileName: fileName,
            Length: spanLength,
            HumanExplanation: "AOT builds require successful N# columnar emission after analysis passes.",
            Suggestion: "Port the rejected source shape to the columnar backend, or build without --aot while the compiler surface converges."
        }
    }

    static func RequiredEmissionError(assemblyName: string, detail: string? = null, fileName: string? = null, line: int = 0, column: int = 0, spanLength: int = 1): CompilerError {
        return new CompilerError(ErrorCode.InvalidSyntax, AddDetail("Columnar emission is required for '" + assemblyName + "', but the columnar backend declined.", detail), line, column, ErrorSeverity.Error) {
            FileName: fileName,
            Length: spanLength,
            HumanExplanation: "This product path requires successful N# columnar emission after analysis passes.",
            Suggestion: "Port the rejected source shape to the columnar backend before using this product path."
        }
    }

    static func RequiredEmitOnlyEmissionError(assemblyName: string, detail: string? = null, fileName: string? = null, line: int = 0, column: int = 0, spanLength: int = 1): CompilerError {
        return new CompilerError(ErrorCode.InvalidSyntax, AddDetail("Columnar emission is required for '" + assemblyName + "', but the columnar backend declined.", detail), line, column, ErrorSeverity.Error) {
            FileName: fileName,
            Length: spanLength,
            HumanExplanation: "This emit-only path bypasses the legacy C# AST/Analyzer and requires successful N# columnar emission.",
            Suggestion: "Port the rejected source shape to the columnar backend before using this product path."
        }
    }

    static func RequiredSoaEmissionError(assemblyName: string, detail: string? = null, fileName: string? = null, line: int = 0, column: int = 0, spanLength: int = 1): CompilerError {
        return new CompilerError(ErrorCode.InvalidSyntax, AddDetail("Columnar SoA emission is required for '" + assemblyName + "', but the columnar backend declined.", detail), line, column, ErrorSeverity.Error) {
            FileName: fileName,
            Length: spanLength,
            HumanExplanation: "Experimental SoA records are the compiler table migration path and require successful N# columnar emission.",
            Suggestion: "Port the rejected table shape to the columnar backend, or disable NSHARP_EXPERIMENTAL_SOA until that shape is supported."
        }
    }

    static func RequiredEmissionErrorFor(assemblyName: string, aotMode: bool, requiresSoaEmission: bool, emitOnly: bool, detail: string? = null, fileName: string? = null, line: int = 0, column: int = 0, spanLength: int = 1): CompilerError {
        if emitOnly {
            return RequiredEmitOnlyEmissionError(assemblyName, detail, fileName, line, column, spanLength)
        }

        if aotMode {
            return RequiredAotEmissionError(assemblyName, detail, fileName, line, column, spanLength)
        }

        if requiresSoaEmission {
            return RequiredSoaEmissionError(assemblyName, detail, fileName, line, column, spanLength)
        }

        return RequiredEmissionError(assemblyName, detail, fileName, line, column, spanLength)
    }

    static func AddDetail(message: string, detail: string?): string {
        if detail == null || detail.Length == 0 {
            return message
        }

        return message + " " + detail
    }
}
