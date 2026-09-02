namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar


// THE CANONICAL CONTRACTS FOR `CodeFix`, IN N#.
//
// These replace `tests/CodeFixTests.cs`, the last canonical C# assertion layer over `CodeFix.nl`.
// `CodeFixService` is what turns a diagnostic into the light-bulb menu in VS Code and into the
// rewrite `nlc fix` applies: a code, a source file and a location go in, and a list of `CodeAction`s
// — each a title, a safety level and a set of `TextEdit`s — comes out.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. `CodeFixService`, its six providers,
// `CodeFixActionHelpers`, `Diagnostic`, `CodeAction`, `TextEdit`, `FixApplicatorCore` and
// `ColumnarParserRecovery` are all public in this assembly, so the subject, its arguments and the
// assertions are the same assembly's own.
//
// THE MEASURED WALL THIS FILE IS WRITTEN AROUND. Omitting a defaulted parameter declines, so
// `Diagnostic` is spelled with all six arguments and `Location` with all three, where the deleted C#
// relied on C#'s defaults. Same construction, same values.
//
// EVERY EDIT IS PROVED BY APPLYING IT. A fix that reports plausible-looking coordinates and produces
// broken source is the failure mode that matters, so wherever the deleted file asserted an edit's
// four numbers, this file ALSO runs the edit through `FixApplicatorCore.ApplyEdits` and states the
// resulting source in full — and, where the fix rewrites an expression, re-parses the result.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) DIAGNOSTIC COORDINATES ARE ONE-BASED; TEXT EDITS ARE ZERO-BASED IN THE COLUMN AND ONE-BASED IN
// THE LINE. Every provider does that conversion by hand.
//
// (2) A CARRIAGE RETURN IS NOT A COLUMN. `TryGetSourceLine` walks CRLF, LF and bare-CR line endings,
// and the returned line must exclude the terminator or every column past it is off by one.
//
// (3) THE NULL-CHECK FIX IS TWO FIXES. `!= null` becomes `true` and `== null` becomes `false`; the
// replacement text is also spliced into the action's TITLE.
//
// (4) THE MAYBE-NULL FIX ALWAYS OFFERS THREE SUGGESTIONS AND SOMETIMES A FOURTH EDIT. The three
// suggestion-only actions are unconditional; the editing action appears only when an unguarded `.`
// or `[` is found at or before the diagnostic column.
func CodeFixUnit(source: string): CompilationUnit {
    parsed := ColumnarParserRecovery.ParseFileAst(source, null)
    unit := parsed.CompilationUnit
    if unit == null {
        return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1)
    }

    return unit
}

func CodeFixDiagnostic(code: string, message: string, line: int, column: int, severity: DiagnosticSeverity, suggestion: string?): Diagnostic {
    return new Diagnostic(code, message, new Location(line, column, null), severity, suggestion, 1)
}

// The joined form of a provider's fixable-code enumeration. `FixableDiagnosticCodes` is an
// `IEnumerable<string>`, so it is walked rather than indexed.
func CodeFixCodesText(codes: IEnumerable<string>): string {
    joined := ""
    for code in codes {
        if joined != "" {
            joined = joined + ","
        }

        joined = joined + code
    }

    return joined
}

func CodeFixHasEdit(fixes: List<CodeAction>, safety: FixSafety, newText: string): bool {
    index := 0
    while index < fixes.Count {
        candidate := fixes[index]
        if candidate.Safety == safety && candidate.Edits.Count == 1 {
            if candidate.Edits[0].NewText == newText {
                return true
            }
        }

        index = index + 1
    }

    return false
}

func CodeFixHasTitleContaining(fixes: List<CodeAction>, safety: FixSafety, needle: string): bool {
    index := 0
    while index < fixes.Count {
        candidate := fixes[index]
        if candidate.Safety == safety && candidate.Title.Contains(needle) {
            return true
        }

        index = index + 1
    }

    return false
}

func CodeFixTitles(fixes: List<CodeAction>): string {
    joined := ""
    index := 0
    while index < fixes.Count {
        if index > 0 {
            joined = joined + " | "
        }

        joined = joined + fixes[index].Title
        index = index + 1
    }

    return joined
}

// ---- Add missing import -------------------------------------------------------------------------

// Successor to AddMissingImport_CreatesCorrectFix.
test "the missing-import fix inserts the namespace above the first declaration" {
    sourceCode := "func main() {\n    let list = new List<int>()\n}"
    diagnostic := CodeFixDiagnostic("NL002", "'List' not found", 2, 20, DiagnosticSeverity.Error, "Add 'import System.Collections.Generic'")
    ast := CodeFixUnit(sourceCode)
    service := new CodeFixService()

    fixes := service.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    fix := fixes[0]
    assert fix.Title == "Add import System.Collections.Generic"
    assert fix.DiagnosticCode == "NL002"
    assert fix.Kind == CodeActionKind.QuickFix
    assert fix.Edits.Count == 1

    edit := fix.Edits[0]
    assert edit.StartLine == 1
    assert edit.StartColumn == 0
    assert edit.NewText == "import System.Collections.Generic\n"

    // NOT IN THE DELETED FILE: the edit is an INSERTION — its end equals its start — and applying it
    // puts the import on its own line above the first declaration. Four coordinates alone say neither.
    assert edit.EndLine == 1
    assert edit.EndColumn == 0
    assert FixApplicatorCore.ApplyEdits(sourceCode, fix.Edits) == "import System.Collections.Generic\nfunc main() {\n    let list = new List<int>()\n}"
}

// Successor to AddMissingImport_InsertsAfterExistingImports.
test "the missing-import fix inserts after the last existing import" {
    sourceCode := "import System\n\nfunc main() {\n    let list = new List<int>()\n}"
    diagnostic := CodeFixDiagnostic("NL002", "'List' not found", 4, 20, DiagnosticSeverity.Error, "Add 'import System.Collections.Generic'")
    ast := CodeFixUnit(sourceCode)
    service := new CodeFixService()

    fixes := service.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    edit := fixes[0].Edits[0]
    assert edit.StartLine == 2
    assert edit.NewText == "import System.Collections.Generic\n"

    // NOT IN THE DELETED FILE: the insert line is read off the LAST import in the parsed tree, so a
    // second import moves it again — a fix that hard-coded "line 2" would pass the deleted test.
    twoImports := "import System\nimport System.IO\n\nfunc main() {\n    let list = new List<int>()\n}"
    twoFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL002", "'List' not found", 5, 20, DiagnosticSeverity.Error, "Add 'import System.Collections.Generic'"), CodeFixUnit(twoImports), twoImports)
    assert twoFixes[0].Edits[0].StartLine == 3
    assert FixApplicatorCore.ApplyEdits(twoImports, twoFixes[0].Edits) == "import System\nimport System.IO\nimport System.Collections.Generic\n\nfunc main() {\n    let list = new List<int>()\n}"

    // AND THE LAST IMPORT'S LINE IS READ FROM THE TREE, NOT FROM THE TEXT: the same source with no
    // parsed tree behind it falls back to inserting at line 1.
    assert CodeFixActionHelpers.GetLastImportLine(CodeFixUnit(twoImports)) == 2
    assert CodeFixActionHelpers.GetLastImportLine(CodeFixUnit(sourceCode)) == 1
    assert CodeFixActionHelpers.GetLastImportLine(CodeFixUnit("func main() {}")) == 0
}

// Successor to AddMissingImport_HandlesInvalidSuggestion.
test "the missing-import fix declines a suggestion it cannot parse" {
    sourceCode := "func main() {}"
    diagnostic := CodeFixDiagnostic("NL002", "'List' not found", 1, 1, DiagnosticSeverity.Error, "Invalid suggestion format")
    ast := CodeFixUnit(sourceCode)
    provider := new AddMissingImportCodeFixProvider()

    fixes := provider.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 0

    // NOT IN THE DELETED FILE: the three ways the suggestion can be malformed, each of which must
    // decline rather than produce an `import` of the wrong text.
    assert new AddMissingImportCodeFixProvider().GetCodeActions(CodeFixDiagnostic("NL002", "m", 1, 1, DiagnosticSeverity.Error, null), ast, sourceCode).Count == 0
    assert new AddMissingImportCodeFixProvider().GetCodeActions(CodeFixDiagnostic("NL002", "m", 1, 1, DiagnosticSeverity.Error, "Add 'import System.IO"), ast, sourceCode).Count == 0
    assert new AddMissingImportCodeFixProvider().GetCodeActions(CodeFixDiagnostic("NL002", "m", 1, 1, DiagnosticSeverity.Error, "Add 'import '"), ast, sourceCode).Count == 0

    // AND THE WELL-FORMED ONE STILL WORKS THROUGH THE SAME PROVIDER.
    wellFormed := new AddMissingImportCodeFixProvider().GetCodeActions(CodeFixDiagnostic("NL002", "m", 1, 1, DiagnosticSeverity.Error, "Add 'import System.IO'"), ast, sourceCode)
    assert wellFormed[0].Title == "Add import System.IO"
}

// ---- Remove unused variable ----------------------------------------------------------------------

// Successor to RemoveUnusedVariable_CreatesCorrectFix.
test "the unused-variable fix deletes the whole declaration line" {
    sourceCode := "func main() {\n    let unused = 42\n    print \"hello\"\n}"
    diagnostic := CodeFixDiagnostic("NL001", "Variable 'unused' is declared but never read", 2, 9, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    service := new CodeFixService()

    fixes := service.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    fix := fixes[0]
    assert fix.Title == "Remove unused variable 'unused'"
    assert fix.DiagnosticCode == "NL001"
    assert fix.Kind == CodeActionKind.QuickFix
    assert fix.Edits.Count == 1

    edit := fix.Edits[0]
    assert edit.StartLine == 2
    assert edit.StartColumn == 0
    assert edit.EndLine == 3
    assert edit.EndColumn == 0
    assert edit.NewText == ""

    // NOT IN THE DELETED FILE: applying it. A line-deletion edit that spans to the NEXT line's
    // column zero is the only shape that removes the newline too — an off-by-one leaves a blank line
    // or eats the following statement, and neither shows up in the four coordinates.
    assert FixApplicatorCore.ApplyEdits(sourceCode, fix.Edits) == "func main() {\n    print \"hello\"\n}"
    assert ColumnarParserRecovery.ParseFileAst(FixApplicatorCore.ApplyEdits(sourceCode, fix.Edits), null).Success
}

// Successor to RemoveUnusedVariable_HandlesVar.
test "the unused-variable fix recognises a var declaration" {
    sourceCode := "func main() {\n    var x = 10\n}"
    diagnostic := CodeFixDiagnostic("NL001", "Variable 'x' is declared but never read", 2, 9, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    service := new CodeFixService()

    fixes := service.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    assert fixes[0].Title == "Remove unused variable 'x'"

    assert FixApplicatorCore.ApplyEdits(sourceCode, fixes[0].Edits) == "func main() {\n}"
}

// Successor to RemoveUnusedVariable_HandlesConst.
test "the unused-variable fix recognises a const declaration" {
    sourceCode := "func main() {\n    const MAX = 100\n}"
    diagnostic := CodeFixDiagnostic("NL001", "Variable 'MAX' is declared but never read", 2, 11, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    service := new CodeFixService()

    fixes := service.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    assert fixes[0].Title == "Remove unused variable 'MAX'"

    assert FixApplicatorCore.ApplyEdits(sourceCode, fixes[0].Edits) == "func main() {\n}"

    // NOT IN THE DELETED FILE: the three keywords are the WHOLE list. A walrus binding — the most
    // common declaration form in N# — is deliberately NOT offered a deletion, because the provider
    // only recognises the line when it can see one of the three keywords in front of the name.
    walrus := "func main() {\n    x := 10\n}"
    assert new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL001", "Variable 'x' is declared but never read", 2, 5, DiagnosticSeverity.Warning, null), CodeFixUnit(walrus), walrus).Count == 0
}

// Successor to RemoveUnusedVariable_HandlesLineOutOfRange.
test "the unused-variable fix declines a line that is not there" {
    sourceCode := "func main() {}"
    diagnostic := CodeFixDiagnostic("NL001", "Variable 'x' is declared but never read", 100, 1, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    provider := new RemoveUnusedVariableCodeFixProvider()

    fixes := provider.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 0

    // NOT IN THE DELETED FILE: line ZERO and a NEGATIVE line are refused by the same guard, and a
    // line that EXISTS but does not declare the named variable is refused too — the provider
    // verifies the text before it offers to delete it, which is the only thing standing between a
    // stale diagnostic and a deleted statement.
    assert new RemoveUnusedVariableCodeFixProvider().GetCodeActions(CodeFixDiagnostic("NL001", "Variable 'x' is declared but never read", 0, 1, DiagnosticSeverity.Warning, null), ast, sourceCode).Count == 0
    mismatched := "func main() {\n    let other = 1\n}"
    assert new RemoveUnusedVariableCodeFixProvider().GetCodeActions(CodeFixDiagnostic("NL001", "Variable 'x' is declared but never read", 2, 9, DiagnosticSeverity.Warning, null), CodeFixUnit(mismatched), mismatched).Count == 0

    // AND A MESSAGE WITH NO QUOTED NAME IS REFUSED BEFORE THE SOURCE IS EVEN READ.
    assert new RemoveUnusedVariableCodeFixProvider().GetCodeActions(CodeFixDiagnostic("NL001", "Variable is declared but never read", 2, 9, DiagnosticSeverity.Warning, null), CodeFixUnit(mismatched), mismatched).Count == 0
}

// ---- Unnecessary null check ------------------------------------------------------------------------

// Successor to UnnecessaryNullCheck_CreatesCorrectFix.
test "the unnecessary-null-check fix names the constant it folds to" {
    sourceCode := "func main() {\n    let x = 42\n    if x != null {\n        print x\n    }\n}"
    diagnostic := CodeFixDiagnostic("NL003", "Unnecessary null check: 'int' is never null", 3, 8, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    service := new CodeFixService()

    fixes := service.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    fix := fixes[0]
    assert fix.Title.Contains("Remove unnecessary null check")
    assert fix.DiagnosticCode == "NL003"
    assert fix.Kind == CodeActionKind.QuickFix

    // NOT IN THE DELETED FILE: the title carries the folded VALUE, so the light-bulb entry tells the
    // user what the condition is about to become.
    assert fix.Title == "Remove unnecessary null check (always true)"
}

// Successor to UnnecessaryNullCheck_EditUsesZeroBasedColumnsAndAppliesExactly.
test "the unnecessary-null-check edit is zero-based and applies exactly" {
    sourceCode := "func main() {\n    let x = 42\n    if x != null {\n        print x\n    }\n}"
    diagnostic := CodeFixDiagnostic("NL003", "Unnecessary null check: 'int' is never null", 3, 8, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    fixes := new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode)
    assert fixes.Count == 1
    fix := fixes[0]
    assert fix.Edits.Count == 1
    edit := fix.Edits[0]

    assert edit.Equals(new TextEdit(3, 7, 3, 16, "true"))
    fixedSource := FixApplicatorCore.ApplyEdits(sourceCode, fix.Edits)
    assert fixedSource == "func main() {\n    let x = 42\n    if true {\n        print x\n    }\n}"

    fixedParse := ColumnarParserRecovery.ParseFileAst(fixedSource, null)
    assert fixedParse.Success

    // NOT IN THE DELETED FILE: the OTHER polarity. `== null` folds to `false`, with its own title —
    // and the deleted file only ever exercised `!= null`, so a provider that answered "true" for
    // both would have passed.
    equalitySource := "func main() {\n    x: string? = null\n    if x == null {\n        print x\n    }\n}"
    equalityFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL003", "Unnecessary null check", 3, 8, DiagnosticSeverity.Warning, null), CodeFixUnit(equalitySource), equalitySource)
    assert equalityFixes.Count == 1
    assert equalityFixes[0].Title == "Remove unnecessary null check (always false)"
    assert equalityFixes[0].Edits[0].NewText == "false"
    assert FixApplicatorCore.ApplyEdits(equalitySource, equalityFixes[0].Edits) == "func main() {\n    x: string? = null\n    if false {\n        print x\n    }\n}"

    // AND `while` IS A CONDITION TOO, with its own six-character keyword offset.
    whileSource := "func main() {\n    let x = 42\n    while x != null {\n        print x\n    }\n}"
    whileFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL003", "Unnecessary null check", 3, 11, DiagnosticSeverity.Warning, null), CodeFixUnit(whileSource), whileSource)
    assert whileFixes.Count == 1
    assert FixApplicatorCore.ApplyEdits(whileSource, whileFixes[0].Edits) == "func main() {\n    let x = 42\n    while true {\n        print x\n    }\n}"

    // AND A LINE WITH NEITHER KEYWORD IS REFUSED, because the provider has no condition to replace.
    bareSource := "func main() {\n    let x = 42\n    y := x != null\n}"
    assert new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL003", "Unnecessary null check", 3, 8, DiagnosticSeverity.Warning, null), CodeFixUnit(bareSource), bareSource).Count == 0
}

// ---- Empty catch ------------------------------------------------------------------------------------

// Successor to EmptyCatch_EditUsesZeroBasedEndColumnAndAppliesExactly.
test "the empty-catch fix appends a TODO at the end of the catch line" {
    sourceCode := "func main() {\n    try {\n    } catch {\n    }\n}"
    diagnostic := CodeFixDiagnostic("NL011", "Empty catch block", 3, 7, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    fixes := new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode)
    assert fixes.Count == 1
    fix := fixes[0]
    assert fix.Edits.Count == 1
    edit := fix.Edits[0]

    assert edit.StartLine == 3
    assert edit.StartColumn == 13
    assert edit.EndLine == 3
    assert edit.EndColumn == 13
    assert FixApplicatorCore.ApplyEdits(sourceCode, fix.Edits) == "func main() {\n    try {\n    } catch {\n        // TODO: handle exception\n    }\n}"

    // NOT IN THE DELETED FILE: the inserted comment is indented to the CATCH LINE'S OWN indentation
    // plus four, so a nested `catch` gets a deeper comment rather than a fixed one.
    nested := "func main() {\n    if true {\n        try {\n        } catch {\n        }\n    }\n}"
    nestedFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL011", "Empty catch block", 4, 11, DiagnosticSeverity.Warning, null), CodeFixUnit(nested), nested)
    assert FixApplicatorCore.ApplyEdits(nested, nestedFixes[0].Edits) == "func main() {\n    if true {\n        try {\n        } catch {\n            // TODO: handle exception\n        }\n    }\n}"
}

// Successor to EmptyCatch_CrlfSource_DoesNotCountCarriageReturnInColumns.
test "the empty-catch fix does not count a carriage return as a column" {
    sourceCode := "func main() {\r\n    try {\r\n    } catch {\r\n    }\r\n}"
    diagnostic := CodeFixDiagnostic("NL011", "Empty catch block", 3, 7, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    fixes := new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode)
    assert fixes.Count == 1
    fix := fixes[0]
    assert fix.Edits.Count == 1
    edit := fix.Edits[0]

    assert edit.StartLine == 3
    assert edit.StartColumn == 13
    assert edit.EndLine == 3
    assert edit.EndColumn == 13
    assert FixApplicatorCore.ApplyEdits(sourceCode, fix.Edits) == "func main() {\n    try {\n    } catch {\n        // TODO: handle exception\n    }\n}"

    // NOT IN THE DELETED FILE: a BARE carriage return is a line ending too — the classic-Mac form
    // the line walker handles with its own branch, and which nothing anywhere exercised.
    carriageReturns := "func main() {\r    try {\r    } catch {\r    }\r}"
    crFixes := new CodeFixService().GetCodeActions(diagnostic, CodeFixUnit(carriageReturns), carriageReturns)
    assert crFixes.Count == 1
    assert crFixes[0].Edits[0].StartColumn == 13
}

// ---- Service dispatch ------------------------------------------------------------------------------

// Successor to CodeFixService_ReturnsNoFixes_ForUnknownDiagnosticCode.
test "the service answers nothing for a code it does not dispatch" {
    sourceCode := "func main() {}"
    diagnostic := CodeFixDiagnostic("NL999", "Unknown error", 1, 1, DiagnosticSeverity.Error, null)
    ast := CodeFixUnit(sourceCode)
    service := new CodeFixService()

    fixes := service.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 0

    // NOT IN THE DELETED FILE: the dispatch is an ORDINAL comparison on the whole code, so neither a
    // prefix nor a different case reaches a provider.
    assert new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL00", "m", 1, 1, DiagnosticSeverity.Error, null), ast, sourceCode).Count == 0
    assert new CodeFixService().GetCodeActions(CodeFixDiagnostic("nl001", "Variable 'x' is declared but never read", 1, 1, DiagnosticSeverity.Warning, null), ast, sourceCode).Count == 0
    assert new CodeFixService().GetCodeActions(CodeFixDiagnostic("", "m", 1, 1, DiagnosticSeverity.Error, null), ast, sourceCode).Count == 0
}

// Successor to CodeFixService_ReturnsMultipleFixes_WhenAvailable.
test "the service dispatches each code to its own provider" {
    sourceCode := "func main() {\n    let unused = 42\n    print \"hello\"\n}"
    diagnostic := CodeFixDiagnostic("NL001", "Variable 'unused' is declared but never read", 2, 9, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    service := new CodeFixService()
    fixes := service.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    assert fixes[0].DiagnosticCode == "NL001"

    // NOT IN THE DELETED FILE, AND IT IS THE CLAIM THE TEST'S NAME MAKES: the dispatch table has SIX
    // rows, and the deleted file only ever reached FOUR of them through the service — `NL011` and
    // `NL010` were tested through their providers directly, so nothing proved the service knew about
    // them at all. Every row is stated here, by the code the answering action carries back.
    nullCheck := "func main() {\n    let x = 42\n    if x != null {\n        print x\n    }\n}"
    nullCheckFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL003", "Unnecessary null check", 3, 8, DiagnosticSeverity.Warning, null), CodeFixUnit(nullCheck), nullCheck)
    assert nullCheckFixes[0].DiagnosticCode == "NL003"

    imports := "func main() {\n    let list = new List<int>()\n}"
    importFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL002", "'List' not found", 2, 20, DiagnosticSeverity.Error, "Add 'import System.Collections.Generic'"), CodeFixUnit(imports), imports)
    assert importFixes[0].DiagnosticCode == "NL002"

    emptyCatch := "func main() {\n    try {\n    } catch {\n    }\n}"
    emptyCatchFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL011", "Empty catch block", 3, 7, DiagnosticSeverity.Warning, null), CodeFixUnit(emptyCatch), emptyCatch)
    assert emptyCatchFixes[0].DiagnosticCode == "NL011"

    unusedImport := "import System.IO\n\nfunc main() {\n    print \"hello\"\n}"
    unusedImportFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL010", "Import 'System.IO' is not used", 1, 1, DiagnosticSeverity.Warning, null), CodeFixUnit(unusedImport), unusedImport)
    assert unusedImportFixes[0].DiagnosticCode == "NL010"

    maybeNull := "func main() {\n    x: string? = \"hello\"\n    len := x.Length\n}"
    maybeNullFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL905", "Possible null dereference: 'x' is maybe-null", 3, 13, DiagnosticSeverity.Error, "Use '?.'"), CodeFixUnit(maybeNull), maybeNull)
    assert maybeNullFixes[0].DiagnosticCode == "NL905"
}

// ---- The fixable-code declarations --------------------------------------------------------------

// Successor to AddMissingImportProvider_OnlyFixesNL002.
test "the missing-import provider declares only NL002" {
    provider := new AddMissingImportCodeFixProvider()

    assert CodeFixCodesText(provider.FixableDiagnosticCodes) == "NL002"
}

// Successor to RemoveUnusedVariableProvider_OnlyFixesNL001.
test "the unused-variable provider declares only NL001" {
    provider := new RemoveUnusedVariableCodeFixProvider()

    assert CodeFixCodesText(provider.FixableDiagnosticCodes) == "NL001"
}

// Successor to AddNullCheckProvider_OnlyFixesNL003.
test "the unnecessary-null-check provider declares only NL003" {
    provider := new RemoveUnnecessaryNullCheckCodeFixProvider()

    assert CodeFixCodesText(provider.FixableDiagnosticCodes) == "NL003"
}

// NOT IN THE DELETED FILE AT ALL: the other three providers' declarations, and the base class's.
// The deleted file stated three of six, so half the table could have drifted from the service's own
// dispatch without a failure.
test "every provider declares exactly the code the service dispatches to it" {
    assert CodeFixCodesText(new PossibleNullAccessCodeFixProvider().FixableDiagnosticCodes) == "NL905"
    assert CodeFixCodesText(new AddCommentToEmptyCatchCodeFixProvider().FixableDiagnosticCodes) == "NL011"
    assert CodeFixCodesText(new RemoveUnusedImportCodeFixProvider().FixableDiagnosticCodes) == "NL010"

    // The base class declares nothing and answers nothing, which is what makes it safe to derive from.
    inert := new CodeFixProvider()
    assert CodeFixCodesText(inert.FixableDiagnosticCodes) == ""
    assert inert.GetCodeActions(CodeFixDiagnostic("NL001", "m", 1, 1, DiagnosticSeverity.Warning, null), CodeFixUnit("func main() {}"), "func main() {}").Count == 0

    // And the helper the six declarations share builds a single-element array.
    declared := CodeFixActionHelpers.SingleDiagnosticCode("NL042")
    assert declared.Length == 1
    assert declared[0] == "NL042"
}

// ---- The value types ------------------------------------------------------------------------------

// Successor to TextEdit_StoresCorrectValues.
test "a text edit stores its four coordinates and its replacement" {
    edit := new TextEdit(1, 5, 2, 10, "replacement")

    assert edit.StartLine == 1
    assert edit.StartColumn == 5
    assert edit.EndLine == 2
    assert edit.EndColumn == 10
    assert edit.NewText == "replacement"

    // NOT IN THE DELETED FILE: `TextEdit` overrides equality, and every comparison in this file and
    // in the fix applicator depends on it. Each of the five fields must participate, and equal edits
    // must hash alike or a set of edits silently keeps duplicates.
    assert edit.Equals(new TextEdit(1, 5, 2, 10, "replacement"))
    assert edit.GetHashCode() == new TextEdit(1, 5, 2, 10, "replacement").GetHashCode()
    assert !edit.Equals(new TextEdit(9, 5, 2, 10, "replacement"))
    assert !edit.Equals(new TextEdit(1, 9, 2, 10, "replacement"))
    assert !edit.Equals(new TextEdit(1, 5, 9, 10, "replacement"))
    assert !edit.Equals(new TextEdit(1, 5, 2, 99, "replacement"))
    assert !edit.Equals(new TextEdit(1, 5, 2, 10, "other"))
    assert !edit.Equals("not an edit")
}

// Successor to CodeAction_StoresCorrectValues.
test "a code action stores its title, its code, its edits and its kind" {
    edits := new List<TextEdit>()
    edits.Add(new TextEdit(1, 0, 1, 0, "test"))

    action := new CodeAction("Test Fix", "NL001", edits, CodeActionKind.QuickFix)

    assert action.Title == "Test Fix"
    assert action.DiagnosticCode == "NL001"
    assert action.Edits.Count == 1
    assert action.Kind == CodeActionKind.QuickFix

    // NOT IN THE DELETED FILE: the four constructors and what each one DEFAULTS. The deleted file
    // used one of them, so nothing stated that the kind-only overload leaves the safety at `Safe` —
    // the most permissive value, and therefore the one a missing argument must not silently pick.
    assert new CodeAction("t", "NL001", edits).Kind == CodeActionKind.QuickFix
    assert new CodeAction("t", "NL001", edits).Safety == FixSafety.Safe
    assert new CodeAction("t", "NL001", edits, CodeActionKind.Refactor).Safety == FixSafety.Safe
    assert new CodeAction("t", "NL001", edits, FixSafety.ReviewNeeded).Kind == CodeActionKind.QuickFix
    assert new CodeAction("t", "NL001", edits, FixSafety.ReviewNeeded).Safety == FixSafety.ReviewNeeded
    assert new CodeAction("t", "NL001", edits, CodeActionKind.Source, FixSafety.SuggestionOnly).Kind == CodeActionKind.Source
    assert new CodeAction("t", "NL001", edits, CodeActionKind.Source, FixSafety.SuggestionOnly).Safety == FixSafety.SuggestionOnly
}

// Successor to FixApplicatorCore_ValidateAndSortEdits_UsesApplicationOrder.
test "the applicator sorts edits into application order" {
    edits := new List<TextEdit>()
    edits.Add(new TextEdit(1, 0, 1, 0, "line1"))
    edits.Add(new TextEdit(3, 5, 3, 5, "line3-col5-first"))
    edits.Add(new TextEdit(3, 5, 3, 5, "line3-col5-second"))
    edits.Add(new TextEdit(2, 10, 2, 12, "line2"))
    edits.Add(new TextEdit(3, 3, 3, 4, "line3-col3"))

    sorted := FixApplicatorCore.ValidateAndSortEdits(edits)

    assert sorted[0].NewText == "line3-col5-second"
    assert sorted[1].NewText == "line3-col5-first"
    assert sorted[2].NewText == "line3-col3"
    assert sorted[3].NewText == "line2"
    assert sorted[4].NewText == "line1"

    // NOT IN THE DELETED FILE: the sort is LAST-FIRST so that applying an edit never invalidates the
    // coordinates of the ones still to come, and two edits at the SAME position are REVERSED against
    // input order so that applying them in turn leaves them in input order in the text. The deleted
    // file stated the sequence; this states the property it exists for.
    assert sorted.Count == 5

    // The property, demonstrated end to end: two insertions on two different lines are applied
    // last-line-first, and both land where their ORIGINAL coordinates said they would.
    twoEdits := new List<TextEdit>()
    twoEdits.Add(new TextEdit(1, 0, 1, 0, "X"))
    twoEdits.Add(new TextEdit(2, 0, 2, 0, "Y"))
    twoSorted := FixApplicatorCore.ValidateAndSortEdits(twoEdits)
    assert twoSorted[0].NewText == "Y"
    assert FixApplicatorCore.ApplyEdits("ab\ncd\n", twoEdits) == "Xab\nYcd\n"
}

// ---- Safety levels -----------------------------------------------------------------------------------

// Successor to RemoveUnusedImport_HasReviewNeededSafety.
test "removing an unused import needs review" {
    sourceCode := "import System.IO\n\nfunc main() {\n    print \"hello\"\n}"
    diagnostic := CodeFixDiagnostic("NL010", "Import 'System.IO' is not used", 1, 1, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    provider := new RemoveUnusedImportCodeFixProvider()
    fixes := provider.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    assert fixes[0].Safety == FixSafety.ReviewNeeded

    // NOT IN THE DELETED FILE: this is the ONLY action in the product that is not a `QuickFix`. Its
    // kind is what puts it under "Organize Imports" in the editor rather than in the light bulb, and
    // nothing stated it.
    assert fixes[0].Kind == CodeActionKind.SourceOrganizeImports
    assert fixes[0].Title == "Remove unused import"
    assert FixApplicatorCore.ApplyEdits(sourceCode, fixes[0].Edits) == "\nfunc main() {\n    print \"hello\"\n}"

    // AND LINE ZERO IS REFUSED, which is the guard that stops a location-less diagnostic deleting
    // line one.
    assert new RemoveUnusedImportCodeFixProvider().GetCodeActions(CodeFixDiagnostic("NL010", "Import 'System.IO' is not used", 0, 1, DiagnosticSeverity.Warning, null), ast, sourceCode).Count == 0
}

// Successor to RemoveUnusedVariable_HasReviewNeededSafety.
test "removing an unused variable needs review" {
    sourceCode := "func main() {\n    let unused = 42\n    print \"hello\"\n}"
    diagnostic := CodeFixDiagnostic("NL001", "Variable 'unused' is declared but never read", 2, 9, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    fixes := new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    assert fixes[0].Safety == FixSafety.ReviewNeeded
}

// Successor to AddMissingImport_HasSafeSafety.
test "adding a missing import is safe" {
    sourceCode := "func main() {\n    let list = new List<int>()\n}"
    diagnostic := CodeFixDiagnostic("NL002", "'List' not found", 2, 20, DiagnosticSeverity.Error, "Add 'import System.Collections.Generic'")
    ast := CodeFixUnit(sourceCode)
    fixes := new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    assert fixes[0].Safety == FixSafety.Safe
}

// Successor to AddCommentToEmptyCatch_HasSafeSafety.
test "adding a TODO to an empty catch is safe" {
    sourceCode := "func main() {\n    try {\n    } catch {\n    }\n}"
    diagnostic := CodeFixDiagnostic("NL011", "Empty catch block", 3, 7, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    provider := new AddCommentToEmptyCatchCodeFixProvider()
    fixes := provider.GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    assert fixes[0].Safety == FixSafety.Safe

    assert fixes[0].Kind == CodeActionKind.QuickFix
    assert fixes[0].Title == "Add TODO comment to empty catch block"
}

// Successor to NullCheck_HasSafeSafety.
test "folding an unnecessary null check is safe" {
    sourceCode := "func main() {\n    let x = 42\n    if x != null {\n        print x\n    }\n}"
    diagnostic := CodeFixDiagnostic("NL003", "Unnecessary null check: 'int' is never null", 3, 8, DiagnosticSeverity.Warning, null)
    ast := CodeFixUnit(sourceCode)
    fixes := new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode)

    assert fixes.Count == 1
    assert fixes[0].Safety == FixSafety.Safe
}

// Successor to PossibleNullAccess_OffersReviewNeededAndSuggestionOnlyActions.
test "a possible null access offers one edit and three suggestions" {
    sourceCode := "func main() {\n    x: string? = \"hello\"\n    len := x.Length\n}"
    diagnostic := CodeFixDiagnostic("NL905", "Possible null dereference: 'x' is maybe-null", 3, 13, DiagnosticSeverity.Error, "Use '?.'")
    ast := CodeFixUnit(sourceCode)
    fixes := new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode)

    assert CodeFixHasEdit(fixes, FixSafety.ReviewNeeded, "?.")
    assert CodeFixHasTitleContaining(fixes, FixSafety.SuggestionOnly, "guard")
    assert CodeFixHasTitleContaining(fixes, FixSafety.SuggestionOnly, "fallback")

    // NOT IN THE DELETED FILE: the WHOLE menu, in order. The deleted file named two of the three
    // suggestion-only actions and never counted them, so the third — the one that tells a user to
    // assert non-null only after PROVING the value is present, the single most dangerous piece of
    // advice in the list — was unstated, and a fourth spurious entry would have gone unnoticed.
    assert fixes.Count == 4
    assert CodeFixTitles(fixes) == "Use null-conditional access (review result nullability) | Add a guard before using the maybe-null value | Add a fallback with ?? after a safe access | Assert non-null only after proving the value is present"
    assert fixes[0].Edits[0].Equals(new TextEdit(3, 12, 3, 13, "?."))
    assert FixApplicatorCore.ApplyEdits(sourceCode, fixes[0].Edits) == "func main() {\n    x: string? = \"hello\"\n    len := x?.Length\n}"

    // AN INDEX ACCESS IS THE OTHER OPERATOR, with its own replacement and its own title.
    indexSource := "func main() {\n    xs: int[]? = null\n    v := xs[0]\n}"
    indexFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL905", "Possible null dereference", 3, 12, DiagnosticSeverity.Error, "Use '?['"), CodeFixUnit(indexSource), indexSource)
    assert indexFixes.Count == 4
    assert indexFixes[0].Title == "Use null-conditional index access (review result nullability)"
    assert CodeFixHasEdit(indexFixes, FixSafety.ReviewNeeded, "?[")
    assert FixApplicatorCore.ApplyEdits(indexSource, indexFixes[0].Edits) == "func main() {\n    xs: int[]? = null\n    v := xs?[0]\n}"

    // AND AN ACCESS THAT IS ALREADY GUARDED OFFERS THE THREE SUGGESTIONS AND NO EDIT — the provider
    // refuses to rewrite `?.` into `??.`.
    guarded := "func main() {\n    x: string? = \"hello\"\n    len := x?.Length\n}"
    guardedFixes := new CodeFixService().GetCodeActions(CodeFixDiagnostic("NL905", "Possible null dereference", 3, 15, DiagnosticSeverity.Error, "Use '?.'"), CodeFixUnit(guarded), guarded)
    assert guardedFixes.Count == 3
    assert !CodeFixHasEdit(guardedFixes, FixSafety.ReviewNeeded, "?.")
    assert guardedFixes[0].Safety == FixSafety.SuggestionOnly
    assert guardedFixes[0].Edits.Count == 0
}

// ---- The character kernels the providers share ------------------------------------------------------

// NOT IN THE DELETED FILE AT ALL: the five text kernels every provider above runs on, stated
// directly rather than through a rendered fix.
test "the code-fix text kernels scan prefixes, quotes and whitespace" {
    assert CodeFixActionHelpers.CodeFixStartsWith("Add 'import System'", "Add 'import ")
    assert !CodeFixActionHelpers.CodeFixStartsWith("Add", "Add 'import ")
    assert CodeFixActionHelpers.CodeFixStartsWith("abc", "")
    assert !CodeFixActionHelpers.CodeFixStartsWith("abc", "abd")

    assert CodeFixActionHelpers.CodeFixLastIndexOfChar("a'b'c", '\'') == 3
    assert CodeFixActionHelpers.CodeFixLastIndexOfChar("abc", '\'') == -1

    assert CodeFixActionHelpers.CodeFixIndexOfCharFrom("a'b'c", '\'', 2) == 3
    assert CodeFixActionHelpers.CodeFixIndexOfCharFrom("a'b'c", '\'', 0) == 1
    assert CodeFixActionHelpers.CodeFixIndexOfCharFrom("a'b'c", '\'', -5) == 1
    assert CodeFixActionHelpers.CodeFixIndexOfCharFrom("abc", 'z', 0) == -1

    assert CodeFixActionHelpers.CodeFixLeadingWhitespaceCount("    x") == 4
    assert CodeFixActionHelpers.CodeFixLeadingWhitespaceCount("\t\tx") == 2
    assert CodeFixActionHelpers.CodeFixLeadingWhitespaceCount("x") == 0
    assert CodeFixActionHelpers.CodeFixLeadingWhitespaceCount("   ") == 3

    assert CodeFixActionHelpers.CodeFixIsWhitespace(' ')
    assert CodeFixActionHelpers.CodeFixIsWhitespace('\t')
    assert CodeFixActionHelpers.CodeFixIsWhitespace('\n')
    assert CodeFixActionHelpers.CodeFixIsWhitespace('\r')
    assert !CodeFixActionHelpers.CodeFixIsWhitespace('x')
    assert !CodeFixActionHelpers.CodeFixIsWhitespace('~')
    assert !CodeFixActionHelpers.CodeFixIsWhitespace('0')
}
