namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// CONTRACTS FOR NL010 ON A FILE IMPORT (020 slice 15).
//
// These came out of `tests/ExampleLintTests.cs`, which is deleted. That file asked two questions of
// `LinterFileImportUsage`: `import "Models"` with the imported type used is silent, and the same
// import with the type unused is reported.
//
// A FILE IMPORT IS RESOLVED AGAINST THE DISK, which is what makes this owner different from the
// namespace half: the linter opens the sibling `.nl` file, reads the type names it EXPORTS, and
// only then decides whether anything in this file used one. Both halves are asserted on disk below
// — a fabricated in-memory unit would prove nothing about the half that reads.
//
// AND THE SPANS ARE STATED. The deleted file asked only whether some NL010 exists; a file import's
// squiggle covers the QUOTED PATH, quotes included, which is a different length rule from the
// namespace arm's bare name and was written down nowhere.
func LfiTempDirectory(tag: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-file-import-" + tag + "-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    return directory
}

func LfiCensusOfFile(filePath: string): string {
    source := File.ReadAllText(filePath)
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    unit := parsed.CompilationUnit
    if unit == null {
        throw new InvalidOperationException("the parser answered no compilation unit for: " + filePath)
    }

    if parsed.Errors.Count != 0 {
        throw new InvalidOperationException("the source did not parse cleanly: " + filePath)
    }

    linter := new Linter(LinterConfig.Default())
    diagnostics := linter.Lint(unit, filePath, source)
    census := ""
    for diagnostic in diagnostics {
        census = census + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + "+" + diagnostic.Length.ToString() + ";"
    }

    return census
}

func LfiWrite(directory: string, name: string, text: string): string {
    path := Path.Combine(directory, name)
    File.WriteAllText(path, text)
    return path
}

test "A USED FILE IMPORT IS SILENT AND AN UNUSED ONE IS REPORTED OVER ITS QUOTED PATH" {
    directory := LfiTempDirectory("pair")
    LfiWrite(directory, "Models.nl", "\nclass User {\n    Name: string\n}\n")

    used := LfiWrite(directory, "Program.nl", "\nimport \"Models\"\n\nfunc main() {\n    u := new User { Name: \"Alice\" }\n    print u.Name\n}\n")
    assert LfiCensusOfFile(used) == ""

    // REMOVAL CONTROL: the same import, the same sibling file, the USE taken out. Column 8 is the
    // opening quote and 8 is the length of `"Models"` — quotes included.
    unused := LfiWrite(directory, "Program.nl", "\nimport \"Models\"\n\nfunc main() {\n    print \"Hello\"\n}\n")
    assert LfiCensusOfFile(unused) == "NL010@2:8+8;"

    Directory.Delete(directory, true)
}

test "TWO FILE IMPORTS ARE TRACKED SEPARATELY, SO ONE USE DOES NOT COVER THE OTHER" {
    // The deleted file had one import per file, so a linter that reported "some import is unused"
    // whenever ANY import was unused would have passed it. With two imports and one use, exactly
    // the unused one is named, at its own line.
    directory := LfiTempDirectory("sibling")
    LfiWrite(directory, "Models.nl", "\nclass User {\n    Name: string\n}\n")
    LfiWrite(directory, "Helpers.nl", "\nclass Helper {\n    Tag: string\n}\n")

    program := LfiWrite(directory, "Program.nl", "\nimport \"Models\"\nimport \"Helpers\"\n\nfunc main() {\n    u := new User { Name: \"Alice\" }\n    print u.Name\n}\n")
    assert LfiCensusOfFile(program) == "NL010@3:8+9;"

    // The mirror: use the other one instead, and the other row is the one reported.
    mirror := LfiWrite(directory, "Program.nl", "\nimport \"Models\"\nimport \"Helpers\"\n\nfunc main() {\n    h := new Helper { Tag: \"x\" }\n    print h.Tag\n}\n")
    assert LfiCensusOfFile(mirror) == "NL010@2:8+8;"

    // And with both used, neither is reported.
    both := LfiWrite(directory, "Program.nl", "\nimport \"Models\"\nimport \"Helpers\"\n\nfunc main() {\n    u := new User { Name: \"Alice\" }\n    h := new Helper { Tag: \"x\" }\n    print u.Name\n    print h.Tag\n}\n")
    assert LfiCensusOfFile(both) == ""

    Directory.Delete(directory, true)
}

test "an import naming a file that is not there is left alone rather than reported unused" {
    // A file import the resolver cannot open exports NO names, so a rule that decided "no exported
    // name was used" would report it — and would bury the real diagnostic (the missing file) under
    // a spurious unused-import warning. The conservative arm is the same one the unknown-NAMESPACE
    // rule takes, and neither was asserted anywhere.
    directory := LfiTempDirectory("absent")
    program := LfiWrite(directory, "Program.nl", "\nimport \"NotThere\"\n\nfunc main() {\n    print \"Hello\"\n}\n")
    assert LfiCensusOfFile(program) == ""

    // THE CONTROL: create the file it names, keep the body identical, and the import IS reported —
    // so the silence above is the missing file and nothing else about the shape.
    LfiWrite(directory, "NotThere.nl", "\nclass Later {\n    Tag: string\n}\n")
    assert LfiCensusOfFile(program) == "NL010@2:8+10;"

    Directory.Delete(directory, true)
}
