using System.Collections.Generic;
using System.Linq;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Tests;

public class LinterTests
{
    private List<Diagnostic> Lint(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        var linter = new Linter();
        return linter.Lint(result.CompilationUnit!, "test.nl");
    }

    private void AssertHasDiagnostic(List<Diagnostic> diagnostics, string code, string messageSubstring)
    {
        Assert.Contains(diagnostics, d => d.Code == code && d.Message.Contains(messageSubstring));
    }

    private void AssertNoDiagnostics(List<Diagnostic> diagnostics)
    {
        Assert.Empty(diagnostics);
    }

    #region NL001: Unused Variable Tests

    [Fact]
    public void NL001_DetectsUnusedVariable()
    {
        var source = "func main() { x := 5 }";
        var diagnostics = Lint(source);

        Assert.Single(diagnostics);
        Assert.Equal("NL001", diagnostics[0].Code);
        Assert.Contains("unused variable 'x'", diagnostics[0].Message.ToLower());
        Assert.Equal(DiagnosticSeverity.Warning, diagnostics[0].Severity);
    }

    [Fact]
    public void NL001_NoWarningForUsedVariable()
    {
        var source = @"
func main() {
    x := 5
    y := x + 1
}";
        var diagnostics = Lint(source);

        // x is used, but y is not
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL001" && d.Message.Contains("'x'"));
    }

    [Fact]
    public void NL001_DetectsMultipleUnusedVariables()
    {
        var source = @"
func main() {
    x := 5
    y := 10
    z := 15
}";
        var diagnostics = Lint(source);

        var unusedVars = diagnostics.Where(d => d.Code == "NL001").ToList();
        Assert.Equal(3, unusedVars.Count);
        Assert.Contains(unusedVars, d => d.Message.Contains("'x'"));
        Assert.Contains(unusedVars, d => d.Message.Contains("'y'"));
        Assert.Contains(unusedVars, d => d.Message.Contains("'z'"));
    }

    [Fact]
    public void NL001_NoWarningForUsedInExpression()
    {
        var source = @"
func main() {
    x := 5
    y := x + 10
    z := y + 1
}";
        var diagnostics = Lint(source);

        // x and y are used, but z is not
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL001" && d.Message.Contains("'x'"));
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL001" && d.Message.Contains("'y'"));
    }

    [Fact]
    public void NL001_NoWarningForFunctionParameters()
    {
        var source = @"
func add(a: int, b: int): int {
    return a + b
}";
        var diagnostics = Lint(source);

        Assert.DoesNotContain(diagnostics, d => d.Code == "NL001");
    }

    [Fact]
    public void NL001_NoWarningForLoopVariables()
    {
        var source = @"
func main() {
    numbers := [1, 2, 3]
    for i := 0; i < 3; i = i + 1 {
        print(numbers[i])
    }
}";
        var diagnostics = Lint(source);

        // i and numbers are both used
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL001" && d.Message.Contains("'i'"));
        Assert.DoesNotContain(diagnostics, d => d.Message.Contains("'numbers'"));
    }

    [Fact]
    public void NL001_DetectsUnusedInNestedScope()
    {
        var source = @"
func main() {
    x := 5
    if true {
        y := 10
    }
}";
        var diagnostics = Lint(source);

        var unusedVars = diagnostics.Where(d => d.Code == "NL001").ToList();
        // x and y are unused
        Assert.True(unusedVars.Count >= 2);
        Assert.Contains(unusedVars, d => d.Message.Contains("'x'"));
        Assert.Contains(unusedVars, d => d.Message.Contains("'y'"));
    }

    [Fact]
    public void NL001_NoWarningForAssignmentTarget()
    {
        var source = @"
func main() {
    x := 5
    x = 10
    y := x + 1
}";
        var diagnostics = Lint(source);

        Assert.DoesNotContain(diagnostics, d => d.Code == "NL001" && d.Message.Contains("'x'"));
    }

    #endregion

    #region NL002: Missing Import Tests

    [Fact]
    public void NL002_DetectsMissingImportForList()
    {
        var source = @"
func main() {
    list := new List<int>()
}";
        var diagnostics = Lint(source);

        var missingImports = diagnostics.Where(d => d.Code == "NL002").ToList();
        Assert.NotEmpty(missingImports);
        Assert.Contains(missingImports, d => d.Message.Contains("List"));
        Assert.Contains(missingImports, d => d.Suggestion != null && d.Suggestion.Contains("System.Collections.Generic"));
    }

    [Fact]
    public void NL002_NoWarningWhenImportPresent()
    {
        var source = @"
import System.Collections.Generic

func main() {
    list := new List<int>()
}";
        var diagnostics = Lint(source);

        var listImportDiagnostics = diagnostics.Where(d => d.Code == "NL002" && d.Message.Contains("List")).ToList();
        Assert.Empty(listImportDiagnostics);
    }

    [Fact]
    public void NL002_DetectsMissingImportForDictionary()
    {
        var source = @"
func main() {
    dict := new Dictionary<string, int>()
}";
        var diagnostics = Lint(source);

        var missingImports = diagnostics.Where(d => d.Code == "NL002").ToList();
        Assert.NotEmpty(missingImports);
        Assert.Contains(missingImports, d => d.Message.Contains("Dictionary"));
    }

    [Fact]
    public void NL002_DetectsMissingImportForStringBuilder()
    {
        var source = @"
func main() {
    sb := new StringBuilder()
}";
        var diagnostics = Lint(source);

        var missingImports = diagnostics.Where(d => d.Code == "NL002").ToList();
        Assert.NotEmpty(missingImports);
        Assert.Contains(missingImports, d => d.Message.Contains("StringBuilder"));
        Assert.Contains(missingImports, d => d.Suggestion != null && d.Suggestion.Contains("System.Text"));
    }

    [Fact]
    public void NL002_DetectsMissingImportForHttpClient()
    {
        var source = @"
func main() {
    client := new HttpClient()
}";
        var diagnostics = Lint(source);

        var missingImports = diagnostics.Where(d => d.Code == "NL002").ToList();
        Assert.NotEmpty(missingImports);
        Assert.Contains(missingImports, d => d.Message.Contains("HttpClient"));
        Assert.Contains(missingImports, d => d.Suggestion != null && d.Suggestion.Contains("System.Net.Http"));
    }

    [Fact]
    public void NL002_DetectsMissingImportForTask()
    {
        var source = @"
func main() {
    task := new Task(() => {})
}";
        var diagnostics = Lint(source);

        var missingImports = diagnostics.Where(d => d.Code == "NL002").ToList();
        Assert.NotEmpty(missingImports);
        Assert.Contains(missingImports, d => d.Message.Contains("Task"));
        Assert.Contains(missingImports, d => d.Suggestion != null && d.Suggestion.Contains("System.Threading.Tasks"));
    }

    [Fact]
    public void NL002_DetectsMissingImportForIdentifierReference()
    {
        var source = @"
func main() {
    list := List<int>()
}";
        var diagnostics = Lint(source);

        var missingImports = diagnostics.Where(d => d.Code == "NL002").ToList();
        Assert.NotEmpty(missingImports);
        Assert.Contains(missingImports, d => d.Message.Contains("List"));
    }

    #endregion

    #region NL003: Unnecessary Null Check Tests

    [Fact]
    public void NL003_DetectsUnnecessaryNullCheckOnIntLiteral()
    {
        var source = @"
func main() {
    if 5 != null {
        print(""hello"")
    }
}";
        var diagnostics = Lint(source);

        var unnecessaryChecks = diagnostics.Where(d => d.Code == "NL003").ToList();
        Assert.NotEmpty(unnecessaryChecks);
        Assert.Contains(unnecessaryChecks, d => d.Message.Contains("int"));
    }

    [Fact]
    public void NL003_DetectsUnnecessaryNullCheckOnFloatLiteral()
    {
        var source = @"
func main() {
    if 3.14 == null {
        print(""hello"")
    }
}";
        var diagnostics = Lint(source);

        var unnecessaryChecks = diagnostics.Where(d => d.Code == "NL003").ToList();
        Assert.NotEmpty(unnecessaryChecks);
        Assert.Contains(unnecessaryChecks, d => d.Message.Contains("float"));
    }

    [Fact]
    public void NL003_DetectsUnnecessaryNullCheckOnBoolLiteral()
    {
        var source = @"
func main() {
    if true != null {
        print(""hello"")
    }
}";
        var diagnostics = Lint(source);

        var unnecessaryChecks = diagnostics.Where(d => d.Code == "NL003").ToList();
        Assert.NotEmpty(unnecessaryChecks);
        Assert.Contains(unnecessaryChecks, d => d.Message.Contains("bool"));
    }

    [Fact]
    public void NL003_NoWarningForStringNullCheck()
    {
        var source = @"
func main() {
    str := ""hello""
    if str != null {
        y := str + "" world""
    }
}";
        var diagnostics = Lint(source);

        // String null checks are valid - strings are reference types
        var unnecessaryChecks = diagnostics.Where(d => d.Code == "NL003").ToList();
        // We only detect literal value types, so no warning expected here
        Assert.Empty(unnecessaryChecks);
    }

    [Fact]
    public void NL003_DetectsUnnecessaryNullCheckInWhileCondition()
    {
        var source = @"
func main() {
    x := 0
    while 5 == null {
        x = x + 1
    }
}";
        var diagnostics = Lint(source);

        var unnecessaryChecks = diagnostics.Where(d => d.Code == "NL003").ToList();
        Assert.NotEmpty(unnecessaryChecks);
    }

    #endregion

    #region NL004: Async Without Await Tests

    [Fact]
    public void NL004_DetectsAsyncWithoutAwait()
    {
        var source = @"
async func process(): Task {
    x := 5
    return Task.CompletedTask
}";
        var diagnostics = Lint(source);

        var asyncWarnings = diagnostics.Where(d => d.Code == "NL004").ToList();
        Assert.NotEmpty(asyncWarnings);
        Assert.Contains(asyncWarnings, d => d.Message.Contains("process"));
    }

    [Fact]
    public void NL004_NoWarningForAsyncWithAwait()
    {
        var source = @"
async func process(): Task {
    await Task.Delay(100)
}";
        var diagnostics = Lint(source);

        var asyncWarnings = diagnostics.Where(d => d.Code == "NL004").ToList();
        Assert.Empty(asyncWarnings);
    }

    [Fact]
    public void NL004_NoWarningForNonAsyncFunction()
    {
        var source = @"
func process() {
    x := 5
}";
        var diagnostics = Lint(source);

        var asyncWarnings = diagnostics.Where(d => d.Code == "NL004").ToList();
        Assert.Empty(asyncWarnings);
    }

    [Fact]
    public void NL004_DetectsAsyncWithoutAwaitInClass()
    {
        var source = @"
class MyClass {
    async func process(): Task {
        x := 5
        return Task.CompletedTask
    }
}";
        var diagnostics = Lint(source);

        var asyncWarnings = diagnostics.Where(d => d.Code == "NL004").ToList();
        Assert.NotEmpty(asyncWarnings);
    }

    #endregion

    #region .editorconfig Configuration Tests

    [Fact]
    public void LinterConfig_DefaultSeverities()
    {
        var config = LinterConfig.Default();

        Assert.Equal(DiagnosticSeverity.Warning, config.GetSeverity("NL001"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL002"));
        Assert.Equal(DiagnosticSeverity.Warning, config.GetSeverity("NL003"));
        Assert.Equal(DiagnosticSeverity.Warning, config.GetSeverity("NL004"));
        Assert.Equal(DiagnosticSeverity.Info, config.GetSeverity("NL005"));
    }

    [Fact]
    public void LinterConfig_CanOverrideSeverity()
    {
        var config = LinterConfig.Default();
        config.RuleSeverities["NL001"] = DiagnosticSeverity.Error;

        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL001"));
    }

    [Fact]
    public void Linter_UsesSeverityFromConfig()
    {
        var source = "func main() { x := 5 }";
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();

        var config = LinterConfig.Default();
        config.RuleSeverities["NL001"] = DiagnosticSeverity.Error;

        var linter = new Linter(config);
        var diagnostics = linter.Lint(result.CompilationUnit!, "test.nl");

        var unusedVarDiag = diagnostics.FirstOrDefault(d => d.Code == "NL001");
        Assert.NotNull(unusedVarDiag);
        Assert.Equal(DiagnosticSeverity.Error, unusedVarDiag!.Severity);
    }

    #endregion

    #region Integration Tests

    [Fact]
    public void Lint_MultipleRulesAtOnce()
    {
        var source = @"
func main() {
    x := 5
    list := new List<int>()
    if 10 != null {
        y := x + 1
    }
}";
        var diagnostics = Lint(source);

        // Should have all three types of diagnostics
        Assert.Contains(diagnostics, d => d.Code == "NL001"); // Unused variables
        Assert.Contains(diagnostics, d => d.Code == "NL002"); // Missing import for List
        Assert.Contains(diagnostics, d => d.Code == "NL003"); // Unnecessary null check on 10
    }

    [Fact]
    public void Lint_EmptyFileNoDiagnostics()
    {
        var source = "";
        var diagnostics = Lint(source);

        AssertNoDiagnostics(diagnostics);
    }

    [Fact]
    public void Lint_SimpleValidCodeNoDiagnostics()
    {
        var source = @"
import System

func main() {
    message := ""Hello, World!""
    Console.WriteLine(message)
}";
        var diagnostics = Lint(source);

        // Should have no linter diagnostics for this valid code
        Assert.Empty(diagnostics);
    }

    [Fact]
    public void Lint_ClassMembersLinted()
    {
        var source = @"
class MyClass {
    func process() {
        x := 5
        y := 10
        return x + 15
    }
}";
        var diagnostics = Lint(source);

        // Should detect unused variable 'y'
        var unusedVars = diagnostics.Where(d => d.Code == "NL001").ToList();
        Assert.Contains(unusedVars, d => d.Message.Contains("'y'"));
        Assert.DoesNotContain(unusedVars, d => d.Message.Contains("'x'"));
    }

    // Lambda test skipped due to parser limitations with inline lambda syntax
    // The linter correctly handles lambdas when they're in the AST

    [Fact]
    public void Linter_ForeachLoop_CollectionVariableIsNotUnused()
    {
        var source = @"
func test() {
    items := [1, 2, 3]
    foreach x in items {
        print(x)
    }
}";
        var diagnostics = Lint(source);

        // 'items' should NOT be reported as unused because it's used in foreach
        var unusedVars = diagnostics.Where(d => d.Code == "NL001").ToList();
        Assert.DoesNotContain(unusedVars, d => d.Message.Contains("'items'"));
    }

    [Fact]
    public void Linter_ForeachWithLINQResult_DoesNotReportUnused()
    {
        var source = @"
import System
import System.Linq

class Program {
    static func Main() {
        let numbers: int[] = [1, 2, 3, 4, 5]
        doubled := numbers.Select(x => x * 2).ToList()

        foreach num in doubled {
            Console.WriteLine(num)
        }
    }
}";
        var diagnostics = Lint(source);

        // 'doubled' should NOT be reported as unused because it's used in foreach
        var unusedDoubled = diagnostics.Where(d => d.Code == "NL001" && d.Message.Contains("'doubled'")).ToList();
        Assert.Empty(unusedDoubled);
    }

    #endregion
}
