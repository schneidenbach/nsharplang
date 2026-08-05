namespace NSharpLang.Compiler.CodeIntelligence

class CodeIntelligenceSignatureKernels {
    static func GetFallbackSignatureText(kind: string, name: string, typeName: string?): string {
        if typeName != null {
            return kind + " " + name + ": " + typeName
        }

        return kind + " " + name
    }
}
