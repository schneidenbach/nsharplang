namespace NSharpLang.LanguageServerDiagnostics.Tests

import System.IO

test "DocumentManager file import alias missing symbol uses requested symbol span" {
    tempRoot := LsdTempRoot("nsharp-lsp-alias-symbol-span-")
    Directory.CreateDirectory(tempRoot)
    try {
        File.WriteAllText(
            Path.Combine(tempRoot, "project.yml"),
            LsdDecodedSource(
                """
name: AliasSymbolSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
"""
            )
        )
        File.WriteAllText(
            Path.Combine(tempRoot, "Helpers.nl"),
            LsdDecodedSource(
                """
func PresentThing(): int {
    return 1
}
"""
            )
        )
        programPath := Path.Combine(tempRoot, "Program.nl")
        source := LsdDecodedSource(
            """
import "./Helpers" as Lib

func main() {
    Lib.MissingThing()
}
"""
        )
        File.WriteAllText(programPath, source)
        uri := LsdFileUri(programPath)
        diagnostic := LsdSingle(LsdCompilerDiagnostics(uri, source), "UndefinedMember", "MissingThing")
        LsdAssertSpan(diagnostic, 4, 9, "MissingThing".Length)
        LsdAssertLspRange(diagnostic, 3, 8, 20)
    } finally {
        if Directory.Exists(tempRoot) {
            Directory.Delete(tempRoot, true)
        }
    }
}

test "DocumentManager missing file import uses quoted path span" {
    tempRoot := LsdTempRoot("nsharp-lsp-missing-import-span-")
    Directory.CreateDirectory(tempRoot)
    try {
        File.WriteAllText(
            Path.Combine(tempRoot, "project.yml"),
            LsdDecodedSource(
                """
name: MissingImportSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
"""
            )
        )
        programPath := Path.Combine(tempRoot, "Program.nl")
        source := LsdDecodedSource(
            """
import "./Missing"

func main() {
}
"""
        )
        File.WriteAllText(programPath, source)
        uri := LsdFileUri(programPath)
        diagnostic := LsdSingle(LsdCompilerDiagnostics(uri, source), "ImportNotFound", null)
        LsdAssertSpan(diagnostic, 1, 8, "\"./Missing\"".Length)
        LsdAssertLspRange(diagnostic, 0, 7, 18)
    } finally {
        if Directory.Exists(tempRoot) {
            Directory.Delete(tempRoot, true)
        }
    }
}

test "DocumentManager file import collision uses duplicate quoted path span" {
    tempRoot := LsdTempRoot("nsharp-lsp-import-collision-span-")
    Directory.CreateDirectory(tempRoot)
    try {
        File.WriteAllText(
            Path.Combine(tempRoot, "project.yml"),
            LsdDecodedSource(
                """
name: ImportCollisionSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
"""
            )
        )
        File.WriteAllText(
            Path.Combine(tempRoot, "A.nl"),
            LsdDecodedSource(
                """
class Shared {
}
"""
            )
        )
        File.WriteAllText(
            Path.Combine(tempRoot, "B.nl"),
            LsdDecodedSource(
                """
class Shared {
}
"""
            )
        )
        programPath := Path.Combine(tempRoot, "Program.nl")
        source := LsdDecodedSource(
            """
import "./A"
import "./B"

func main() {
}
"""
        )
        File.WriteAllText(programPath, source)
        uri := LsdFileUri(programPath)
        diagnostic := LsdSingle(LsdCompilerDiagnostics(uri, source), "ImportCollision", "Shared")
        LsdAssertSpan(diagnostic, 2, 8, "\"./B\"".Length)
        LsdAssertLspRange(diagnostic, 1, 7, 12)
        assert LsdFieldText(diagnostic, "Suggestion").Contains("alias")
        hint := LsdFieldText(diagnostic, "ContextualHint")
        assert hint.Contains("\"./A\"")
        assert hint.Contains("\"./B\"")
    } finally {
        if Directory.Exists(tempRoot) {
            Directory.Delete(tempRoot, true)
        }
    }
}
