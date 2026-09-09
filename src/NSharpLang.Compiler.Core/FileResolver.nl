namespace NSharpLang.Compiler

import System.IO

class FileResolver {
    projectRootValue: string
    currentFileValue: string
    ProjectRoot: string => projectRootValue
    CurrentFile: string => currentFileValue

    constructor(projectRoot: string, currentFile: string) {
        projectRootValue = Path.GetFullPath(projectRoot)
        currentFileValue = Path.GetFullPath(currentFile)
    }

    func ResolveFilePath(importPath: string): string {
        resolvedImportPath := importPath
        if !resolvedImportPath.EndsWith(".nl") {
            resolvedImportPath = resolvedImportPath + ".nl"
        }

        resolvedPath := ""
        if resolvedImportPath.StartsWith("./") || resolvedImportPath.StartsWith("../") {
            currentDirectory := Path.GetDirectoryName(currentFileValue)
            if currentDirectory == null {
                currentDirectory = projectRootValue
            }

            resolvedPath = Path.GetFullPath(Path.Combine(currentDirectory, resolvedImportPath))
        } else {
            resolvedPath = Path.GetFullPath(Path.Combine(projectRootValue, resolvedImportPath))
        }

        return resolvedPath
    }
}
