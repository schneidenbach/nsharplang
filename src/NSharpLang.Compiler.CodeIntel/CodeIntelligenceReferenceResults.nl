namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler


// THE REFERENCE AND DEFINITION ANSWERS — what `query references`, `query definition`, go-to-definition
// and rename all print.
//
// THE DOOR THESE ANSWERS READ IS `CodeIntelligenceSourceDoor.SourceText`, which slice 13 could not
// move: its `IReadOnlyDictionary<string, string>` parameter was absent from the columnar catalog, so
// the text had to cross the boundary as an already-resolved `string?` and the lookup stayed in C#.
// The row is published now, so the door is N# and the C# has none of it left.
//
// THE DEFINITION ROW IS ALWAYS FIRST AND ALWAYS PRESENT. A reference answer opens with the
// declaration itself (`IsDefinition: true`) even when the binding map holds no usages at all, and
// the usages that FOLLOW are filtered against it twice: a usage at the declaration's exact position
// is dropped, and so is any usage that merely OVERLAPS the declaration's name span — which is how a
// declaration reported at a slightly different column than its own name is not counted twice.
class CodeIntelligenceReferenceResults {

    // ── The reference answer ────────────────────────────────────────────
    static func FromDeclaration(projectRoot: string, sourceTexts: IReadOnlyDictionary<string, string>, bindings: BindingMap?, declaration: SymbolDeclaration): List<ReferenceResult> {
        results := new List<ReferenceResult>()
        results.Add(new ReferenceResult(CodeIntelligenceSourceDoor.RelativePath(projectRoot, declaration.File ?? ""), declaration.Line, declaration.Column, declaration.Name.Length, DeclarationContext(sourceTexts, declaration), true))

        if bindings != null {
            usages := bindings.GetReferences(declaration)
            index := 0
            while index < usages.Count {
                usage := usages[index]
                index = index + 1

                isDefinition := usage.File == declaration.File && usage.Line == declaration.Line && usage.Column == declaration.Column
                overlapsDefinitionName := usage.File == declaration.File && usage.Line == declaration.Line && usage.Column >= declaration.Column && usage.Column < declaration.Column + declaration.Name.Length
                if isDefinition || overlapsDefinitionName {
                    continue
                }

                results.Add(new ReferenceResult(CodeIntelligenceSourceDoor.RelativePath(projectRoot, usage.File ?? ""), usage.Line, usage.Column, usage.Length, UsageContext(sourceTexts, usage), false))
            }
        }

        return CodeIntelligenceResultKernels.DeduplicateReferenceResults(results)
    }

    // A row at line 0 carries NO context and never opens the file — which is why a synthesized
    // declaration with no position does not throw on a path that does not exist.
    static func DeclarationContext(sourceTexts: IReadOnlyDictionary<string, string>, declaration: SymbolDeclaration): string? {
        if declaration.Line > 0 {
            return CodeIntelligenceSourceDoor.SourceContext(CodeIntelligenceSourceDoor.SourceText(sourceTexts, declaration.File), declaration.Line)
        }
        return null
    }

    static func UsageContext(sourceTexts: IReadOnlyDictionary<string, string>, usage: SymbolUsage): string? {
        if usage.Line > 0 {
            return CodeIntelligenceSourceDoor.SourceContext(CodeIntelligenceSourceDoor.SourceText(sourceTexts, usage.File), usage.Line)
        }
        return null
    }

    // ── The definition answer ───────────────────────────────────────────
    // Its LENGTH is the declaration's NAME length and not any recorded span, so a definition row's
    // length is a property of the name rather than of the source.
    static func ToDefinition(projectRoot: string, declaration: SymbolDeclaration): DefinitionResult {
        return new DefinitionResult(declaration.Name, declaration.Kind, CodeIntelligenceSourceDoor.RelativePath(projectRoot, declaration.File ?? ""), declaration.Line, declaration.Column, declaration.Name.Length)
    }
}
