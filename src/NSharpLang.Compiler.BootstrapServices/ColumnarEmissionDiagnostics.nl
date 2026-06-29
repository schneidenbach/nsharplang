namespace NSharpLang.Compiler

public class ColumnarEmissionDiagnostics {
    public static func RequiredAotEmissionError(assemblyName: string): CompilerError {
        return new CompilerError(
            ErrorCode.InvalidSyntax,
            "Columnar AOT emission is required for '" + assemblyName + "', but the columnar backend declined.",
            0,
            0,
            ErrorSeverity.Error) {
            HumanExplanation: "AOT builds require successful N# columnar emission after analysis passes.",
            Suggestion: "Port the rejected source shape to the columnar backend, or build without --aot while the compiler surface converges."
        }
    }

    public static func RequiredEmissionError(assemblyName: string): CompilerError {
        return new CompilerError(
            ErrorCode.InvalidSyntax,
            "Columnar emission is required for '" + assemblyName + "', but the columnar backend declined.",
            0,
            0,
            ErrorSeverity.Error) {
            HumanExplanation: "This product path requires successful N# columnar emission after analysis passes.",
            Suggestion: "Port the rejected source shape to the columnar backend before using this product path."
        }
    }

    public static func RequiredEmitOnlyEmissionError(assemblyName: string): CompilerError {
        return new CompilerError(
            ErrorCode.InvalidSyntax,
            "Columnar emission is required for '" + assemblyName + "', but the columnar backend declined.",
            0,
            0,
            ErrorSeverity.Error) {
            HumanExplanation: "This emit-only path bypasses the legacy C# AST/Analyzer and requires successful N# columnar emission.",
            Suggestion: "Port the rejected source shape to the columnar backend before using this product path."
        }
    }

    public static func RequiredSoaEmissionError(assemblyName: string): CompilerError {
        return new CompilerError(
            ErrorCode.InvalidSyntax,
            "Columnar SoA emission is required for '" + assemblyName + "', but the columnar backend declined.",
            0,
            0,
            ErrorSeverity.Error) {
            HumanExplanation: "Experimental SoA records are the compiler table migration path and require successful N# columnar emission.",
            Suggestion: "Port the rejected table shape to the columnar backend, or disable NSHARP_EXPERIMENTAL_SOA until that shape is supported."
        }
    }
}
