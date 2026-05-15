using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class MigrationLintTests
{
    private static List<Diagnostic> LintSource(string source, string filePath = "test.nl")
    {
        var linter = new Linter();
        return linter.LintSource(source, filePath);
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
    public void LintSource_DoesNotFlagInteropVisibilityEscapeHatches()
    {
        var diagnostics = LintSource("""
internal class HostBridge {
    protected virtual func OnStart() { }
}
""");

        Assert.DoesNotContain(diagnostics, d => d.Code == "NL101" && d.Message.Contains("internal"));
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL101" && d.Message.Contains("protected"));
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
        Assert.Contains(diagnostics, d => d.Code == "NL103" && d.Suggestion!.Contains("real initializer"));
    }

    [Fact]
    public void LintSource_FlagsUnsafeValueAccessAsMigrationDiagnostic()
    {
        var diagnostics = LintSource("""
func Read(result: Result<string>, maybeAge: int?): string {
    name := result.Value
    if maybeAge != null {
        return maybeAge.Value.ToString()
    }
    return "missing"
}
""");

        var valueDiagnostics = diagnostics.Where(d => d.Code == "NL111").ToList();

        Assert.Equal(2, valueDiagnostics.Count);
        Assert.Contains(valueDiagnostics, d => d.Message.Contains("result.Value"));
        Assert.Contains(valueDiagnostics, d => d.Message.Contains("maybeAge.Value"));
        Assert.All(valueDiagnostics, d => Assert.Contains("match", d.Suggestion));
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
    public void LintSource_FlagsCSharpUsingNamespacePackageAndInitializerBlockers()
    {
        var diagnostics = LintSource("""
using System;
namespace Legacy.Api;

class UserDto {
    func Create(): User => new User {
        Name = "A"
    }
}
""", "src/Services/User.nl");

        Assert.Contains(diagnostics, d => d.Code == "NL107" && d.Message.Contains("using"));
        Assert.Contains(diagnostics, d => d.Code == "NL108" && d.Message.Contains("namespace"));
        Assert.Contains(diagnostics, d => d.Code == "NL109" && d.Message.Contains("package Services"));
        Assert.Contains(diagnostics, d => d.Code == "NL110" && d.Message.Contains("object initializer"));
    }

    [Fact]
    public void LintSource_FlagsInlineEqualsStyleObjectInitializerMember()
    {
        var diagnostics = LintSource("""
func Create(): User {
    return new User { Name = "A", Age: 30 }
}
""");

        var diagnostic = Assert.Single(diagnostics.Where(d => d.Code == "NL110"));
        Assert.Equal(2, diagnostic.Location.Line);
        Assert.Equal(23, diagnostic.Location.Column);
        Assert.Contains("Use canonical N# object initialization", diagnostic.Suggestion);
    }

    [Fact]
    public void MigrationCodeFixes_RewriteEqualsStyleObjectInitializerOnlyAtDiagnosticToken()
    {
        var ast = new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1);
        var source = """
func Create(): User {
    return new User { Name = "A", Age = value == 3 }
}
""";
        var diagnostics = LintSource(source).Where(d => d.Code == "NL110").ToList();
        var fixService = new CodeFixService();

        var actions = diagnostics.SelectMany(d => fixService.GetCodeActions(d, ast, source)).ToList();
        Assert.Equal(2, actions.Count);
        Assert.All(actions, a => Assert.Equal(FixSafety.Safe, a.Safety));

        var fixedSource = NSharpLang.Compiler.CodeIntelligence.FixApplicator.ApplyEdits(source, actions.SelectMany(a => a.Edits).ToList());
        Assert.Contains("new User { Name: \"A\", Age: value == 3 }", fixedSource);
    }

    [Fact]
    public void LintSource_DoesNotFlagNormalAssignmentOutsideObjectInitializer()
    {
        var diagnostics = LintSource("""
func Update() {
    name = "A"
    options := new User { Name: "A" }
    name = "B"
}
""");

        Assert.DoesNotContain(diagnostics, d => d.Code == "NL110");
    }

    [Fact]
    public void LintSource_FlagsWrongPackageDeclarationForFileLayout()
    {
        var diagnostics = LintSource("""
package Models

class UserDto {
    Id: int
}
""", "Services/User.nl");

        Assert.Contains(diagnostics, d => d.Code == "NL109" && d.Message.Contains("Models") && d.Message.Contains("Services"));
    }

    [Fact]
    public void LintSource_DoesNotReportPackageLayoutOutsideKnownPackageFolders()
    {
        var diagnostics = LintSource("""
class UserDto {
    Id: int
}
""", "src/Features/User.nl");

        Assert.DoesNotContain(diagnostics, d => d.Code == "NL109");
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

    [Fact]
    public void MigrationCodeFixes_OfferReviewOnlyRewriteForUnsafeValueAccess()
    {
        var ast = new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1);
        var source = """
func Read(result: Result<string>): string {
    return result.Value
}
""";
        var diagnostics = LintSource(source);
        var fixService = new CodeFixService();

        var actions = diagnostics.SelectMany(d => fixService.GetCodeActions(d, ast, source)).ToList();

        var action = Assert.Single(actions, a => a.DiagnosticCode == "NL111");
        Assert.Contains("unsafe .Value", action.Title);
        Assert.Equal(FixSafety.SuggestionOnly, action.Safety);
        Assert.Empty(action.Edits);
    }
}
