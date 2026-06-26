namespace NSharpLang.Compiler.CodeIntelligence

public class CodeIntelligenceSignatureKernels {
    public static func GetFallbackSignatureText(kind: string, name: string, typeName: string?): string {
        if typeName != null {
            return kind + " " + name + ": " + typeName
        }

        return kind + " " + name
    }
}
