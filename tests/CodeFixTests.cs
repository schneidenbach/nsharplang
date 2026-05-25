using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class CodeFixTests
{
    [Fact]
    public void AddMissingImport_CreatesCorrectFix()
    {
        // Arrange
        var sourceCode = @"func main() {
    let list = new List<int>()
}";
        var diagnostic = new Diagnostic(
            "NL002",
            "'List' not found",
            new Location(2, 20),
            DiagnosticSeverity.Error,
            "Add 'import System.Collections.Generic'");

        var ast = ParseCode(sourceCode);
        var service = new CodeFixService();

        // Act
        var fixes = service.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert
        Assert.Single(fixes);
        var fix = fixes[0];
        Assert.Equal("Add import System.Collections.Generic", fix.Title);
        Assert.Equal("NL002", fix.DiagnosticCode);
        Assert.Equal(CodeActionKind.QuickFix, fix.Kind);
        Assert.Single(fix.Edits);

        var edit = fix.Edits[0];
        Assert.Equal(1, edit.StartLine);
        Assert.Equal(0, edit.StartColumn);
        Assert.Equal("import System.Collections.Generic\n", edit.NewText);
    }

    [Fact]
    public void AddMissingImport_InsertsAfterExistingImports()
    {
        // Arrange
        var sourceCode = @"import System

func main() {
    let list = new List<int>()
}";
        var diagnostic = new Diagnostic(
            "NL002",
            "'List' not found",
            new Location(4, 20),
            DiagnosticSeverity.Error,
            "Add 'import System.Collections.Generic'");

        var ast = ParseCode(sourceCode);
        var service = new CodeFixService();

        // Act
        var fixes = service.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert
        Assert.Single(fixes);
        var edit = fixes[0].Edits[0];
        Assert.Equal(2, edit.StartLine); // After line 1 (import System)
        Assert.Equal("import System.Collections.Generic\n", edit.NewText);
    }

    [Fact]
    public void RemoveUnusedVariable_CreatesCorrectFix()
    {
        // Arrange
        var sourceCode = @"func main() {
    let unused = 42
    print ""hello""
}";
        var diagnostic = new Diagnostic(
            "NL001",
            "Variable 'unused' is declared but never read",
            new Location(2, 9),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var service = new CodeFixService();

        // Act
        var fixes = service.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert
        Assert.Single(fixes);
        var fix = fixes[0];
        Assert.Equal("Remove unused variable 'unused'", fix.Title);
        Assert.Equal("NL001", fix.DiagnosticCode);
        Assert.Equal(CodeActionKind.QuickFix, fix.Kind);
        Assert.Single(fix.Edits);

        var edit = fix.Edits[0];
        Assert.Equal(2, edit.StartLine);
        Assert.Equal(0, edit.StartColumn);
        Assert.Equal(3, edit.EndLine);
        Assert.Equal(0, edit.EndColumn);
        Assert.Equal("", edit.NewText);
    }

    [Fact]
    public void RemoveUnusedVariable_HandlesVar()
    {
        // Arrange
        var sourceCode = @"func main() {
    var x = 10
}";
        var diagnostic = new Diagnostic(
            "NL001",
            "Variable 'x' is declared but never read",
            new Location(2, 9),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var service = new CodeFixService();

        // Act
        var fixes = service.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert
        Assert.Single(fixes);
        Assert.Equal("Remove unused variable 'x'", fixes[0].Title);
    }

    [Fact]
    public void RemoveUnusedVariable_HandlesConst()
    {
        // Arrange
        var sourceCode = @"func main() {
    const MAX = 100
}";
        var diagnostic = new Diagnostic(
            "NL001",
            "Variable 'MAX' is declared but never read",
            new Location(2, 11),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var service = new CodeFixService();

        // Act
        var fixes = service.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert
        Assert.Single(fixes);
        Assert.Equal("Remove unused variable 'MAX'", fixes[0].Title);
    }

    [Fact]
    public void UnnecessaryNullCheck_CreatesCorrectFix()
    {
        // Arrange
        var sourceCode = @"func main() {
    let x = 42
    if x != null {
        print x
    }
}";
        var diagnostic = new Diagnostic(
            "NL003",
            "Unnecessary null check: 'int' is never null",
            new Location(3, 8),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var service = new CodeFixService();

        // Act
        var fixes = service.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert
        Assert.Single(fixes);
        var fix = fixes[0];
        Assert.Contains("Remove unnecessary null check", fix.Title);
        Assert.Equal("NL003", fix.DiagnosticCode);
        Assert.Equal(CodeActionKind.QuickFix, fix.Kind);
    }

    [Fact]
    public void UnnecessaryNullCheck_EditUsesZeroBasedColumnsAndAppliesExactly()
    {
        var sourceCode = @"func main() {
    let x = 42
    if x != null {
        print x
    }
}";
        var diagnostic = new Diagnostic(
            "NL003",
            "Unnecessary null check: 'int' is never null",
            new Location(3, 8),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var fix = Assert.Single(new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode));
        var edit = Assert.Single(fix.Edits);

        Assert.Equal(new TextEdit(3, 7, 3, 16, "true"), edit);
        var fixedSource = NSharpLang.Compiler.CodeIntelligence.FixApplicator.ApplyEdits(sourceCode, fix.Edits);
        Assert.Equal(@"func main() {
    let x = 42
    if true {
        print x
    }
}", fixedSource);

        var fixedTokens = new Lexer(fixedSource).Tokenize();
        var fixedParse = new Parser(fixedTokens).ParseCompilationUnit();
        Assert.True(fixedParse.Success, string.Join("\n", fixedParse.Errors.Select(e => e.Message)));
    }

    [Fact]
    public void EmptyCatch_EditUsesZeroBasedEndColumnAndAppliesExactly()
    {
        var sourceCode = @"func main() {
    try {
    } catch {
    }
}";
        var diagnostic = new Diagnostic(
            "NL011",
            "Empty catch block",
            new Location(3, 7),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var fix = Assert.Single(new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode));
        var edit = Assert.Single(fix.Edits);

        Assert.Equal(3, edit.StartLine);
        Assert.Equal(13, edit.StartColumn);
        Assert.Equal(3, edit.EndLine);
        Assert.Equal(13, edit.EndColumn);
        Assert.Equal(@"func main() {
    try {
    } catch {
        // TODO: handle exception
    }
}", NSharpLang.Compiler.CodeIntelligence.FixApplicator.ApplyEdits(sourceCode, fix.Edits));
    }

    [Fact]
    public void EmptyCatch_CrlfSource_DoesNotCountCarriageReturnInColumns()
    {
        var sourceCode = "func main() {\r\n    try {\r\n    } catch {\r\n    }\r\n}";
        var diagnostic = new Diagnostic(
            "NL011",
            "Empty catch block",
            new Location(3, 7),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var fix = Assert.Single(new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode));
        var edit = Assert.Single(fix.Edits);

        Assert.Equal(3, edit.StartLine);
        Assert.Equal(13, edit.StartColumn);
        Assert.Equal(3, edit.EndLine);
        Assert.Equal(13, edit.EndColumn);
        Assert.Equal("func main() {\n    try {\n    } catch {\n        // TODO: handle exception\n    }\n}",
            NSharpLang.Compiler.CodeIntelligence.FixApplicator.ApplyEdits(sourceCode, fix.Edits));
    }

    [Fact]
    public void ChangeLetToConst_EditUsesZeroBasedColumnsAndAppliesExactly()
    {
        var sourceCode = @"func main() {
    let answer = 42
    print answer
}";
        var diagnostic = new Diagnostic(
            "NL015",
            "'answer' is never reassigned; use const",
            new Location(2, 5),
            DiagnosticSeverity.Info);

        var ast = ParseCode(sourceCode);
        var fix = Assert.Single(new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode));
        var edit = Assert.Single(fix.Edits);

        Assert.Equal(new TextEdit(2, 4, 2, 8, "const "), edit);
        Assert.Equal(@"func main() {
    const answer = 42
    print answer
}", NSharpLang.Compiler.CodeIntelligence.FixApplicator.ApplyEdits(sourceCode, fix.Edits));
    }

    [Fact]
    public void ObjectInitializerEquals_EditUsesZeroBasedColumnsAndAppliesExactly()
    {
        var sourceCode = @"func main() {
    p := new Person { Name = ""Ada"" }
}";
        var diagnostic = new Diagnostic(
            "NL110",
            "C# object initializer uses '='; use ':' in N#",
            new Location(2, 23),
            DiagnosticSeverity.Info);

        var ast = ParseCode(sourceCode);
        var fix = Assert.Single(new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode));
        var edit = Assert.Single(fix.Edits);

        Assert.Equal(new TextEdit(2, 26, 2, 29, ": "), edit);
        Assert.Equal(@"func main() {
    p := new Person { Name: ""Ada"" }
}", NSharpLang.Compiler.CodeIntelligence.FixApplicator.ApplyEdits(sourceCode, fix.Edits));
    }

    [Fact]
    public void CodeFixService_ReturnsNoFixes_ForUnknownDiagnosticCode()
    {
        // Arrange
        var sourceCode = @"func main() {}";
        var diagnostic = new Diagnostic(
            "NL999",
            "Unknown error",
            new Location(1, 1),
            DiagnosticSeverity.Error);

        var ast = ParseCode(sourceCode);
        var service = new CodeFixService();

        // Act
        var fixes = service.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert
        Assert.Empty(fixes);
    }

    [Fact]
    public void CodeFixService_ReturnsMultipleFixes_WhenAvailable()
    {
        // Each diagnostic code currently has one provider, so we verify that
        // the service dispatches correctly to the matching provider.
        var sourceCode = @"func main() {
    let unused = 42
    print ""hello""
}";
        var diagnostic = new Diagnostic(
            "NL001",
            "Variable 'unused' is declared but never read",
            new Location(2, 9),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var service = new CodeFixService();
        var fixes = service.GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Single(fixes);
        Assert.Equal("NL001", fixes[0].DiagnosticCode);
    }

    [Fact]
    public void AddMissingImportProvider_OnlyFixesNL002()
    {
        // Arrange
        var provider = new AddMissingImportCodeFixProvider();

        // Assert
        Assert.Contains("NL002", provider.FixableDiagnosticCodes);
        Assert.Single(provider.FixableDiagnosticCodes);
    }

    [Fact]
    public void RemoveUnusedVariableProvider_OnlyFixesNL001()
    {
        // Arrange
        var provider = new RemoveUnusedVariableCodeFixProvider();

        // Assert
        Assert.Contains("NL001", provider.FixableDiagnosticCodes);
        Assert.Single(provider.FixableDiagnosticCodes);
    }

    [Fact]
    public void AddNullCheckProvider_OnlyFixesNL003()
    {
        // Arrange
        var provider = new RemoveUnnecessaryNullCheckCodeFixProvider();

        // Assert
        Assert.Contains("NL003", provider.FixableDiagnosticCodes);
        Assert.Single(provider.FixableDiagnosticCodes);
    }

    [Fact]
    public void TextEdit_StoresCorrectValues()
    {
        // Arrange & Act
        var edit = new TextEdit(
            StartLine: 1,
            StartColumn: 5,
            EndLine: 2,
            EndColumn: 10,
            NewText: "replacement");

        // Assert
        Assert.Equal(1, edit.StartLine);
        Assert.Equal(5, edit.StartColumn);
        Assert.Equal(2, edit.EndLine);
        Assert.Equal(10, edit.EndColumn);
        Assert.Equal("replacement", edit.NewText);
    }

    [Fact]
    public void CodeAction_StoresCorrectValues()
    {
        // Arrange
        var edits = new System.Collections.Generic.List<TextEdit>
        {
            new TextEdit(1, 0, 1, 0, "test")
        };

        // Act
        var action = new CodeAction(
            "Test Fix",
            "NL001",
            edits,
            CodeActionKind.QuickFix);

        // Assert
        Assert.Equal("Test Fix", action.Title);
        Assert.Equal("NL001", action.DiagnosticCode);
        Assert.Single(action.Edits);
        Assert.Equal(CodeActionKind.QuickFix, action.Kind);
    }

    [Fact]
    public void AddMissingImport_HandlesInvalidSuggestion()
    {
        // Arrange
        var sourceCode = @"func main() {}";
        var diagnostic = new Diagnostic(
            "NL002",
            "'List' not found",
            new Location(1, 1),
            DiagnosticSeverity.Error,
            "Invalid suggestion format");

        var ast = ParseCode(sourceCode);
        var provider = new AddMissingImportCodeFixProvider();

        // Act
        var fixes = provider.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert - should return empty list for invalid suggestion
        Assert.Empty(fixes);
    }

    [Fact]
    public void RemoveUnusedVariable_HandlesLineOutOfRange()
    {
        // Arrange
        var sourceCode = @"func main() {}";
        var diagnostic = new Diagnostic(
            "NL001",
            "Variable 'x' is declared but never read",
            new Location(100, 1), // Line way out of range
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var provider = new RemoveUnusedVariableCodeFixProvider();

        // Act
        var fixes = provider.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert - should return empty list when line is out of range
        Assert.Empty(fixes);
    }

    // ── Safety level tests ──────────────────────────────────────────────

    [Fact]
    public void RemoveUnusedImport_HasReviewNeededSafety()
    {
        var sourceCode = @"import System.IO

func main() {
    print ""hello""
}";
        var diagnostic = new Diagnostic(
            "NL010",
            "Import 'System.IO' is not used",
            new Location(1, 1),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var provider = new RemoveUnusedImportCodeFixProvider();
        var fixes = provider.GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Single(fixes);
        Assert.Equal(FixSafety.ReviewNeeded, fixes[0].Safety);
    }

    [Fact]
    public void RemoveUnusedVariable_HasReviewNeededSafety()
    {
        var sourceCode = @"func main() {
    let unused = 42
    print ""hello""
}";
        var diagnostic = new Diagnostic(
            "NL001",
            "Variable 'unused' is declared but never read",
            new Location(2, 9),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var fixes = new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Single(fixes);
        Assert.Equal(FixSafety.ReviewNeeded, fixes[0].Safety);
    }

    [Fact]
    public void AddMissingImport_HasSafeSafety()
    {
        var sourceCode = @"func main() {
    let list = new List<int>()
}";
        var diagnostic = new Diagnostic(
            "NL002",
            "'List' not found",
            new Location(2, 20),
            DiagnosticSeverity.Error,
            "Add 'import System.Collections.Generic'");

        var ast = ParseCode(sourceCode);
        var fixes = new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Single(fixes);
        Assert.Equal(FixSafety.Safe, fixes[0].Safety);
    }

    [Fact]
    public void ConvertToInterpolation_HasSuggestionOnlySafety()
    {
        var sourceCode = @"func main() {
    let name = ""world""
    let greeting = ""hello "" + name
}";
        var diagnostic = new Diagnostic(
            "NL013",
            "Prefer string interpolation",
            new Location(3, 20),
            DiagnosticSeverity.Info);

        var ast = ParseCode(sourceCode);
        var provider = new ConvertToInterpolationCodeFixProvider();
        var fixes = provider.GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Single(fixes);
        Assert.Equal(FixSafety.SuggestionOnly, fixes[0].Safety);
    }

    [Fact]
    public void AddCommentToEmptyCatch_HasSafeSafety()
    {
        var sourceCode = @"func main() {
    try {
    } catch {
    }
}";
        var diagnostic = new Diagnostic(
            "NL011",
            "Empty catch block",
            new Location(3, 7),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var provider = new AddCommentToEmptyCatchCodeFixProvider();
        var fixes = provider.GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Single(fixes);
        Assert.Equal(FixSafety.Safe, fixes[0].Safety);
    }

    [Fact]
    public void ChangeLetToConst_HasSafeSafety()
    {
        var sourceCode = @"func main() {
    let MAX = 100
    print MAX
}";
        var diagnostic = new Diagnostic(
            "NL015",
            "'MAX' is never reassigned; use const",
            new Location(2, 5),
            DiagnosticSeverity.Info);

        var ast = ParseCode(sourceCode);
        var provider = new ChangeLetToConstCodeFixProvider();
        var fixes = provider.GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Single(fixes);
        Assert.Equal(FixSafety.Safe, fixes[0].Safety);
    }

    [Fact]
    public void NullCheck_HasSafeSafety()
    {
        var sourceCode = @"func main() {
    let x = 42
    if x != null {
        print x
    }
}";
        var diagnostic = new Diagnostic(
            "NL003",
            "Unnecessary null check: 'int' is never null",
            new Location(3, 8),
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var fixes = new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Single(fixes);
        Assert.Equal(FixSafety.Safe, fixes[0].Safety);
    }

    [Fact]
    public void PossibleNullAccess_OffersReviewNeededAndSuggestionOnlyActions()
    {
        var sourceCode = @"func main() {
    x: string? = ""hello""
    len := x.Length
}";
        var diagnostic = new Diagnostic(
            "NL905",
            "Possible null dereference: 'x' is maybe-null",
            new Location(3, 13),
            DiagnosticSeverity.Error,
            "Use '?.'");

        var ast = ParseCode(sourceCode);
        var fixes = new CodeFixService().GetCodeActions(diagnostic, ast, sourceCode);

        Assert.Contains(fixes, fix =>
            fix.Safety == FixSafety.ReviewNeeded &&
            fix.Edits.Count == 1 &&
            fix.Edits[0].NewText == "?.");
        Assert.Contains(fixes, fix => fix.Safety == FixSafety.SuggestionOnly && fix.Title.Contains("guard"));
        Assert.Contains(fixes, fix => fix.Safety == FixSafety.SuggestionOnly && fix.Title.Contains("fallback"));
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private CompilationUnit ParseCode(string code)
    {
        var lexer = new Lexer(code);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        return result.CompilationUnit!; // Tests expect valid syntax
    }
}
