namespace NSharpLang.Compiler

import System.Collections.Generic
import System.IO

public class LinterFileImportUsage {
    public static func IsUsed(
        importSymbol: string,
        importPath: string?,
        currentFilePath: string?,
        codeIdentifiers: HashSet<string>): bool {
        if codeIdentifiers.Contains(importSymbol) {
            return true
        }

        // A DOTTED use (`Alias.Type` in a type reference or qualified call) records the dotted
        // identifier, not the bare alias — a prefix match on `<symbol>.` is a use.
        foreach identifier in codeIdentifiers {
            if identifier.Length > importSymbol.Length + 1
                && identifier.StartsWith(importSymbol)
                && identifier[importSymbol.Length] == '.' {
                return true
            }
        }

        if importPath != null && currentFilePath != null {
            resolvedPath := ResolveFileImportPath(importPath, currentFilePath)
            if resolvedPath != null {
                exportedSymbols := LinterExportedSymbolExtractor.Extract(resolvedPath)
                if exportedSymbols.Count > 0 {
                    index := 0
                    while index < exportedSymbols.Count {
                        if codeIdentifiers.Contains(exportedSymbols[index]) {
                            return true
                        }

                        index = index + 1
                    }

                    return false
                }
            }
        }

        return true
    }

    static func ResolveFileImportPath(importPath: string, currentFilePath: string): string? {
        fileDir := Path.GetDirectoryName(currentFilePath)
        if fileDir == null {
            return null
        }

        candidate := Path.GetFullPath(Path.Combine(fileDir, importPath))
        if File.Exists(candidate) {
            return candidate
        }

        candidateWithExtension := Path.GetFullPath(Path.Combine(fileDir, importPath + ".nl"))
        if File.Exists(candidateWithExtension) {
            return candidateWithExtension
        }

        return null
    }
}
