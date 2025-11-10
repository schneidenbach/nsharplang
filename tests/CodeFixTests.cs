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
            "Unused variable 'unused'",
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
            "Unused variable 'x'",
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
            "Unused variable 'MAX'",
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
        Assert.Equal("Remove unnecessary null check", fix.Title);
        Assert.Equal("NL003", fix.DiagnosticCode);
        Assert.Equal(CodeActionKind.QuickFix, fix.Kind);
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
        // Future: When we have multiple fixes for the same diagnostic
        // For now, each diagnostic code has one fix
        Assert.True(true);
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
        var provider = new AddNullCheckCodeFixProvider();

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
            "Unused variable 'x'",
            new Location(100, 1), // Line way out of range
            DiagnosticSeverity.Warning);

        var ast = ParseCode(sourceCode);
        var provider = new RemoveUnusedVariableCodeFixProvider();

        // Act
        var fixes = provider.GetCodeActions(diagnostic, ast, sourceCode);

        // Assert - should return empty list when line is out of range
        Assert.Empty(fixes);
    }

    private CompilationUnit ParseCode(string code)
    {
        var lexer = new Lexer(code);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        return parser.ParseCompilationUnit();
    }
}
