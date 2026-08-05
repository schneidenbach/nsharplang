namespace NSharpLang.Compiler

import System
import System.Collections.Generic

class AnalyzerDiagnostics {

    // The suggestion attached to "type not found". Candidates are the type names the caller can see;
    // the nearest one within an edit distance of 2 becomes a "did you mean", and anything further
    // away is not worth guessing at. Names shorter than three characters are skipped because at that
    // length almost everything is within distance 2 of everything else, and the name itself is
    // skipped because it is not a suggestion. Ties keep the FIRST candidate in the caller's order.
    static func UnresolvedTypeSuggestion(name: string, candidates: List<string>): string {
        bestCandidate: string? = null
        bestDistance := 2147483647

        index := 0
        while index < candidates.Count {
            candidate := candidates[index]
            if candidate.Length >= 3 && candidate != name {
                distance := ErrorSuggestions.LevenshteinDistance(name.ToLowerInvariant(), candidate.ToLowerInvariant())
                if distance < bestDistance {
                    bestDistance = distance
                    bestCandidate = candidate
                }
            }
            index = index + 1
        }

        if bestCandidate != null && bestDistance <= 2 {
            return "Did you mean '" + bestCandidate + "'? Otherwise add the 'import' or package reference that provides '" + name + "'."
        }

        return "Check the spelling, add the missing 'import', or add the package/project reference that provides '" + name + "'."
    }

    static func Create(code: ErrorCode, message: string, currentFilePath: string?, line: int, column: int, sourceSnippet: string?, suggestion: string?, length: int, severity: ErrorSeverity): CompilerError {
        resolvedSuggestion: string? = suggestion
        if resolvedSuggestion == null {
            resolvedSuggestion = ErrorSuggestions.GetSuggestion(code, null, null)
        }

        if sourceSnippet != null && currentFilePath != null {
            return CompilerError.WithSnippet(code, message, currentFilePath, line, column, sourceSnippet, length, resolvedSuggestion, severity)
        }

        return CompilerError.CreateDetailed(code, message, line, column, currentFilePath, length, resolvedSuggestion, null, null, null, severity)
    }

    static func CreateImportCollision(message: string, currentFilePath: string?, duplicateSourcePath: string?, line: int, column: int, sourceSnippet: string?, length: int, suggestion: string, humanExplanation: string, contextualHint: string): CompilerError {
        docsUrl := "https://docs.n-sharp.dev/errors/NL702"
        fileName: string? = currentFilePath
        if fileName == null {
            fileName = duplicateSourcePath
        }

        if sourceSnippet != null && currentFilePath != null {
            return CompilerError.WithSnippetDetailed(ErrorCode.ImportCollision, message, currentFilePath, line, column, sourceSnippet, length, suggestion, ErrorSeverity.Error, humanExplanation, contextualHint, docsUrl)
        }

        return CompilerError.CreateDetailed(ErrorCode.ImportCollision, message, line, column, fileName, length, suggestion, humanExplanation, contextualHint, docsUrl, ErrorSeverity.Error)
    }
}
