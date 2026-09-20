namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO

// Snapshot plumbing for signature help. The policy — which declarations a call name means, how each
// overload reads, which one is active and which row the caret is in — lives in
// `SignatureHelpOverloadFacts`; this is the door that hands it the program.
//
// THE PROJECT IS THE UNIT OF ANSWER, exactly as it is for completion. Signature help that read only
// the buffer in front of the caret could not name a BCL method, an overload set, or a type declared
// in the file next door; a snapshot can, because it is the same program the analyzer bound.
//
// The type catalog is held rather than re-made per keystroke: it holds the analyzer's assembly
// registry BY REFERENCE, so one catalog stays current as packages join, and rebuilding it per
// request would pay for the exported-type scan on every character typed.
class SignatureHelpEngine {
    catalog: EditorTypeCatalog?

    // THE EDITOR'S TYPE UNIVERSE, made once from the analyzer that is already answering for this
    // workspace. A caller with no analyzer gets no catalog and therefore no external type-name
    // receivers, which is a smaller answer rather than a wrong one.
    func UseAnalyzer(analyzer: Analyzer?) {
        if catalog == null && analyzer != null {
            catalog = analyzer.CreateEditorTypeCatalog()
        }
    }

    // THE PROJECT DOOR. `fileName` is the path the snapshot knows the caret's file by; line and
    // column are the analyzer's 1-based source coordinates.
    func GetOverloads(snapshot: ProjectSnapshot, fileName: string, call: SignatureHelpCallContext, line: int, col: int): List<SignatureHelpOverload> {
        unitMatch := CodeIntelligenceNavigation.FindCompilationUnit(snapshot, fileName)
        unit := unitMatch.Unit as CompilationUnit

        semanticModel: SemanticModel? = null
        snapshot.SemanticModels.TryGetValue(unitMatch.FilePath, out semanticModel)

        return SignatureHelpOverloadFacts.ResolveOverloads(call, SnapshotUnits(snapshot), unit, semanticModel, catalog, line, col)
    }

    // THE LOOSE-BUFFER DOOR. A buffer with no project behind it still has its own declarations and
    // its own bound model, and a caller typing a call into it is entitled to both.
    func GetOverloads(unit: CompilationUnit?, semanticModel: SemanticModel?, sourceText: string?, call: SignatureHelpCallContext, line: int, col: int): List<SignatureHelpOverload> {
        units := new List<SignatureHelpSourceUnit>()
        if unit != null {
            units.Add(new SignatureHelpSourceUnit(unit, sourceText))
        }

        return SignatureHelpOverloadFacts.ResolveOverloads(call, units, unit, semanticModel, catalog, line, col)
    }

    // Every unit of the snapshot, each paired with the text it was parsed from so a declaration's
    // leading comment block can be read back. A unit whose text the snapshot did not keep is read
    // from disk, which is the same fallback the completion door makes.
    static func SnapshotUnits(snapshot: ProjectSnapshot): List<SignatureHelpSourceUnit> {
        units := new List<SignatureHelpSourceUnit>()
        for entry in snapshot.CompilationUnits {
            sourceText: string? = null
            if !snapshot.SourceTexts.TryGetValue(entry.Key, out sourceText) {
                sourceText = ReadSourceOrNull(entry.Key)
            }

            units.Add(new SignatureHelpSourceUnit(entry.Value, sourceText))
        }

        return units
    }

    static func ReadSourceOrNull(filePath: string): string? {
        try {
            return File.ReadAllText(filePath)
        } catch caught: IOException {
            return null
        }
    }
}
