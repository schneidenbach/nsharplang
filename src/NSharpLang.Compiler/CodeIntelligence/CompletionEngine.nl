namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO

// Snapshot plumbing for completions. Completion policy remains in the Core completion owners.
class CompletionEngine {
    func GetCompletions(snapshot: ProjectSnapshot, fileName: string, line: int, col: int, includeKeywords: bool = false): CompletionResult {
        unitMatch := CodeIntelligenceNavigation.FindCompilationUnit(snapshot, fileName)
        unit := unitMatch.Unit as CompilationUnit
        if unit == null {
            return emptyResult(CompletionContext.Unknown)
        }

        semanticModel: SemanticModel? = null
        snapshot.SemanticModels.TryGetValue(unitMatch.FilePath, out semanticModel)

        sourceText: string? = null
        if !snapshot.SourceTexts.TryGetValue(unitMatch.FilePath, out sourceText) {
            sourceText = File.ReadAllText(unitMatch.FilePath)
        }

        if sourceText == null {
            return emptyResult(CompletionContext.Unknown)
        }

        beforeCursor: string? = null
        if !CodeIntelligenceSourceTextKernels.TryExtractCompletionPrefix(
            snapshot,
            unitMatch.FilePath,
            sourceText,
            line,
            col,
            out beforeCursor
        ) {
            throw new InvalidOperationException("N# completion prefix kernel rejected the source.")
        }

        if beforeCursor == null {
            return emptyResult(CompletionContext.Unknown)
        }

        completionReceiver := CompletionEngineKernels.ClassifyCompletionReceiver(beforeCursor)
        if completionReceiver.IsMemberAccess {
            models := snapshot.SemanticModels
            modelValues := models.Values
            units := snapshot.CompilationUnits
            unitValues := units.Values
            return CompletionReceiverFacts.GetMemberAccessCompletions(
                unit,
                semanticModel,
                completionReceiver.Receiver,
                line,
                col,
                modelValues,
                unitValues,
                snapshot.FriendGrants
            )
        }

        // The snapshot's other units ride along so the function group can be namespace-wide: a
        // top-level `func` is visible to every file of its namespace whatever its casing.
        identifierUnits := snapshot.CompilationUnits
        identifierUnitValues := identifierUnits.Values
        return CompletionEngineKernels.GetIdentifierCompletions(unit, semanticModel, includeKeywords, line, col, identifierUnitValues)
    }

    private static func emptyResult(context: CompletionContext): CompletionResult {
        return new CompletionResult(context, null, null, new Dictionary<string, List<CompletionItem>>())
    }
}
