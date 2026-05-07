using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class MigrationLintTests
{
    private static List<Diagnostic> LintSource(string source)
    {
        var linter = new Linter();
        return linter.LintSource(source, "test.nl");
    }

    [Fact]
    public void LintSource_FlagsCSharpModifiersWithoutAst()
    {
        var diagnostics = LintSource("""
public partial class UserDto {
    private readonly id: int
    override func ToString(): string => "user"
}
""");

        var modifierDiagnostics = diagnostics.Where(d => d.Code == "NL101").ToList();

        Assert.Contains(modifierDiagnostics, d => d.Message.Contains("public"));
        Assert.Contains(modifierDiagnostics, d => d.Message.Contains("partial"));
        Assert.Contains(modifierDiagnostics, d => d.Message.Contains("private"));
        Assert.Contains(modifierDiagnostics, d => d.Message.Contains("readonly"));
        Assert.Contains(modifierDiagnostics, d => d.Message.Contains("override"));
    }

    [Fact]
    public void LintSource_FlagsCSharpPropertySyntaxAndNullForgivingArtifacts()
    {
        var diagnostics = LintSource("""
class UserDto {
    Name: string { get; set; } = default!
    Email: string = null!
    func Normalize(value: string!) => value!
}
""");

        Assert.Contains(diagnostics, d => d.Code == "NL102" && d.Message.Contains("{ get; set; }"));
        Assert.Contains(diagnostics, d => d.Code == "NL103" && d.Message.Contains("default!"));
        Assert.Contains(diagnostics, d => d.Code == "NL103" && d.Message.Contains("null!"));
        Assert.Contains(diagnostics, d => d.Code == "NL103" && d.Message.Contains("value!"));
    }

    [Fact]
    public void LintSource_FlagsMigrationPatternCandidates()
    {
        var diagnostics = LintSource("""
class UserDto {
    Id: int { get; set; }
    Name: string { get; set; }
}

func Get(id: string): Result {
    try {
        if users.TryGetValue(id, out var user) {
            return Ok(user)
        }
    } catch (ex) {
        return StatusCode(500, ex.Message)
    }
}
""");

        Assert.Contains(diagnostics, d => d.Code == "NL104" && d.Message.Contains("TryGetValue"));
        Assert.Contains(diagnostics, d => d.Code == "NL105" && d.Message.Contains("UserDto"));
        Assert.Contains(diagnostics, d => d.Code == "NL106" && d.Message.Contains("500"));
    }

    [Fact]
    public void MigrationCodeFixes_RemoveTrivialModifierAndNullForgivingArtifacts()
    {
        var ast = new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1);
        var source = """
public class UserDto {
    Name: string = default!
}
""";
        var diagnostics = LintSource(source);
        var fixService = new CodeFixService();

        var actions = diagnostics.SelectMany(d => fixService.GetCodeActions(d, ast, source)).ToList();

        Assert.Contains(actions, a => a.DiagnosticCode == "NL101" && a.Title.Contains("Remove 'public'"));
        Assert.Contains(actions, a => a.DiagnosticCode == "NL103" && a.Title.Contains("Remove null-forgiving"));
        Assert.All(actions.Where(a => a.DiagnosticCode is "NL101" or "NL103"), a => Assert.Equal(FixSafety.ReviewNeeded, a.Safety));
    }
}
