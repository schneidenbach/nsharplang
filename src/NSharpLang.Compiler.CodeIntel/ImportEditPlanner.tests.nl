namespace NSharpLang.Compiler

import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar

test "import edits share the quick-fix owner and preserve every file header" {
    sources := new string[](5)
    sources[0] = "func Build() {}"
    sources[1] = "namespace Example\nfunc Build() {}"
    sources[2] = "package Example\nfunc Build() {}"
    sources[3] = "import System\nfunc Build() {}"
    sources[4] = "import \"./types.nl\"\nfunc Build() {}"
    expected := new string[](5)
    expected[0] = "import System.Text\nfunc Build() {}"
    expected[1] = "namespace Example\nimport System.Text\nfunc Build() {}"
    expected[2] = "package Example\nimport System.Text\nfunc Build() {}"
    expected[3] = "import System\nimport System.Text\nfunc Build() {}"
    expected[4] = "import \"./types.nl\"\nimport System.Text\nfunc Build() {}"
    i := 0
    while i < sources.Length {
        source := sources[i]
        unit := CodeFixUnit(source)
        edits := ImportEditPlanner.GetEdits(unit, source, "System.Text")
        assert edits.Count == 1
        applied := FixApplicatorCore.ApplyEdits(source, edits)
        assert applied == expected[i], applied
        parsed := ColumnarParserRecovery.ParseFileAst(applied, null)
        assert parsed.Errors.Count == 0
        diagnostic := CodeFixDiagnostic("NL002", "missing", 1, 1, DiagnosticSeverity.Error, "Add 'import System.Text'")
        provider := new AddMissingImportCodeFixProvider()
        fixes := provider.GetCodeActions(diagnostic, unit, source)
        assert fixes.Count == 1
        assert fixes[0].Edits[0].Equals(edits[0])
        i = i + 1
    }
}

test "import edits suppress existing unaliased imports and the current namespace or package" {
    sources := new string[](3)
    sources[0] = "import System.Text\nfunc Build() {}"
    sources[1] = "namespace System.Text\nfunc Build() {}"
    sources[2] = "package System.Text\nfunc Build() {}"
    i := 0
    while i < sources.Length {
        source := sources[i]
        unit := CodeFixUnit(source)
        assert ImportEditPlanner.IsNamespaceInScope(unit, "System.Text")
        assert ImportEditPlanner.GetEdits(unit, source, "System.Text").Count == 0
        assert !ImportEditPlanner.IsNamespaceInScope(unit, "System.Tex")
        assert !ImportEditPlanner.IsNamespaceInScope(unit, "system.text")
        i = i + 1
    }

    aliased := "import System.Text as Text\nfunc Build() {}"
    assert !ImportEditPlanner.IsNamespaceInScope(CodeFixUnit(aliased), "System.Text")
    assert ImportEditPlanner.GetEdits(CodeFixUnit(aliased), aliased, "System.Text").Count == 1
}

test "import edits preserve CRLF and insert after a header without a final newline" {
    source := "namespace Example\r\nfunc Build() {}\r\n"
    edits := ImportEditPlanner.GetEdits(CodeFixUnit(source), source, "System.Text")
    assert edits.Count == 1
    assert edits[0].StartLine == 2
    assert edits[0].StartColumn == 0
    assert edits[0].NewText == "import System.Text\r\n"
    source = "namespace Example\rfunc Build() {}\r"
    edits = ImportEditPlanner.GetEdits(CodeFixUnit(source), source, "System.Text")
    assert edits[0].StartLine == 2
    assert edits[0].StartColumn == 0
    assert edits[0].NewText == "import System.Text\r"
    source = "namespace Example"
    edits = ImportEditPlanner.GetEdits(CodeFixUnit(source), source, "System.Text")
    assert edits[0].StartLine == 1
    assert edits[0].StartColumn == source.Length
    assert edits[0].NewText == "\nimport System.Text\n"
    assert FixApplicatorCore.ApplyEdits(source, edits) == "namespace Example\nimport System.Text\n"
}

test "import edits consume multiline headers and preserve declaration documentation" {
    sources := new string[](5)
    sources[0] = "namespace Example /* header\ncomment */\n/// Factory docs\nfunc Build() {}"
    sources[1] = "namespace Example.\nNested\nfunc Build() {}"
    sources[2] = "import System.\nCollections.Generic as\nCollections\nfunc Build() {}"
    sources[3] = "namespace Example func Build() {}"
    sources[4] = "namespace Example func Build() { /* body\ncomment */ }"
    expected := new string[](5)
    expected[0] = "namespace Example /* header\ncomment */\nimport System.Text\n/// Factory docs\nfunc Build() {}"
    expected[1] = "namespace Example.\nNested\nimport System.Text\nfunc Build() {}"
    expected[2] = "import System.\nCollections.Generic as\nCollections\nimport System.Text\nfunc Build() {}"
    expected[3] = "namespace Example \nimport System.Text\nfunc Build() {}"
    expected[4] = "namespace Example \nimport System.Text\nfunc Build() { /* body\ncomment */ }"
    i := 0
    while i < sources.Length {
        source := sources[i]
        edits := ImportEditPlanner.GetEdits(CodeFixUnit(source), source, "System.Text")
        applied := FixApplicatorCore.ApplyEdits(source, edits)
        assert applied == expected[i], applied
        assert ColumnarParserRecovery.ParseFileAst(applied, null).Errors.Count == 0
        i = i + 1
    }
}

test "import completion edits combine at the first word and replace its entire suffix" {
    source := "StringBuildeWrong"
    planner := new ImportEditPlanner(CodeFixUnit(source), source)
    edits := planner.CompletionEdits("System.Text", "StringBuilder", 1, 12)
    assert edits.Count == 1
    assert edits[0].StartColumn == 0
    assert edits[0].EndColumn == source.Length
    assert FixApplicatorCore.ApplyEdits(source, edits) == "import System.Text\nStringBuilder"
    empty := new ImportEditPlanner(CodeFixUnit(""), "")
    edits = empty.CompletionEdits("System", "Console", 1, 0)
    assert edits.Count == 1
    assert FixApplicatorCore.ApplyEdits("", edits) == "import System\nConsole"
    header := "namespace StringBuilde"
    headerPlanner := new ImportEditPlanner(CodeFixUnit(header), header)
    edits = headerPlanner.CompletionEdits("System.Text", "StringBuilder", 1, header.Length)
    assert edits.Count == 1
    assert FixApplicatorCore.ApplyEdits(header, edits) == "namespace StringBuilder\nimport System.Text\n"
}

test "import edit planning stays available while a file header is incomplete" {
    sources := new string[](4)
    sources[0] = "namespace"
    sources[1] = "package Example."
    sources[2] = "import System as"
    sources[3] = "namespace Example /* unfinished\ncomment"
    i := 0
    while i < sources.Length {
        source := sources[i]
        edits := ImportEditPlanner.GetEdits(CodeFixUnit(source), source, "System.Text")
        assert edits.Count == 1
        assert FixApplicatorCore.ApplyEdits(source, edits).Contains("import System.Text")
        i = i + 1
    }
}
