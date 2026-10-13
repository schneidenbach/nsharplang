namespace NSharpLang.Compiler

import System.Collections.Generic
import System.IO

class LinterFileImportUsage {
    static func IsUsed(
        importSymbol: string,
        importPath: string?,
        currentFilePath: string?,
        codeIdentifiers: HashSet<string>,
        sourceTexts: IReadOnlyDictionary<string, string>? = null
    ): bool {
        if codeIdentifiers.Contains(importSymbol) {
            return true
        }

        // A DOTTED use (`Alias.Type` in a type reference or qualified call) records the dotted
        // identifier, not the bare alias — a prefix match on `<symbol>.` is a use.
        for identifier in codeIdentifiers {
            if identifier.Length > importSymbol.Length + 1 && identifier.StartsWith(importSymbol) && identifier[importSymbol.Length] == '.' {
                return true
            }
        }

        if importPath != null && currentFilePath != null {
            resolvedPath := ResolveFileImportPath(importPath, currentFilePath, sourceTexts)
            if resolvedPath != null {
                exportedSymbols := ExtractExportedSymbols(resolvedPath, sourceTexts)
                if exportedSymbols.Count > 0 {
                    for exportedSymbol in exportedSymbols {
                        if codeIdentifiers.Contains(exportedSymbol) {
                            return true
                        }
                    }

                    return false
                }
            }
        }

        return true
    }

    static func ResolveFileImportPath(importPath: string, currentFilePath: string, sourceTexts: IReadOnlyDictionary<string, string>? = null): string? {
        fileDir := Path.GetDirectoryName(currentFilePath)
        if fileDir == null {
            return null
        }

        candidate := Path.GetFullPath(Path.Combine(fileDir, importPath))
        if SourceTextExists(sourceTexts, candidate) || File.Exists(candidate) {
            return candidate
        }

        candidateWithExtension := Path.GetFullPath(Path.Combine(fileDir, importPath + ".nl"))
        if SourceTextExists(sourceTexts, candidateWithExtension) || File.Exists(candidateWithExtension) {
            return candidateWithExtension
        }

        return null
    }

    private static func SourceTextExists(sourceTexts: IReadOnlyDictionary<string, string>?, filePath: string): bool {
        if sourceTexts == null {
            return false
        }

        text: string? = null
        return sourceTexts.TryGetValue(Path.GetFullPath(filePath), out text)
    }

    private static func ExtractExportedSymbols(filePath: string, sourceTexts: IReadOnlyDictionary<string, string>?): List<string> {
        if sourceTexts != null {
            text: string? = null
            if sourceTexts.TryGetValue(Path.GetFullPath(filePath), out text) && text != null {
                return LinterExportedSymbolExtractor.ExtractFromSource(text, filePath)
            }
        }

        return LinterExportedSymbolExtractor.Extract(filePath)
    }
}
