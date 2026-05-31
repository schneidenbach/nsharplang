using System;
using System.Collections.Generic;
using System.IO;
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

    private List<Diagnostic> LintWithSource(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var result = parser.ParseCompilationUnit();
        var linter = new Linter();
        return linter.Lint(result.CompilationUnit!, "test.nl", source);
    }

    private void AssertNoDiagnostics(List<Diagnostic> diagnostics)
    {
        Assert.Empty(diagnostics);
    }

    [Fact]
    public void DiagnosticCatalog_RegistersReservedKeywordAsSyntaxDiagnostic()
    {
        Assert.True(DiagnosticCatalog.TryGetDescriptor("NL109", out var descriptor));
        Assert.Equal(DiagnosticSource.Compiler, descriptor.Source);
        Assert.Equal(DiagnosticCategory.Syntax, descriptor.Category);
        Assert.Equal(DiagnosticSeverity.Error, descriptor.DefaultSeverity);
        Assert.True(descriptor.BlocksBuildByDefault);
    }

    [Fact]
    public void DiagnosticCatalog_FallbackDocsUrlUsesPublicDocsDomain()
    {
        Assert.Equal("https://docs.n-sharp.dev/errors/NL9999", DiagnosticCatalog.DocsUrlFor("NL9999"));
    }

    #region NL001: Unused Variable Tests

    [Fact]
    public void NL001_DetectsUnusedVariable()
    {
        var source = "func main() { x := 5 }";
        var diagnostics = Lint(source);

        Assert.Single(diagnostics);
        Assert.Equal("NL001", diagnostics[0].Code);
        Assert.Contains("'x'", diagnostics[0].Message);
        Assert.Contains("never read", diagnostics[0].Message);
        Assert.Equal(DiagnosticSeverity.Error, diagnostics[0].Severity);
    }

    [Fact]
    public void NL001_AllowsUnderscorePrefixedIntentionalUnusedVariable()
    {
        var source = @"
func main() {
    _x := 5
}";
        var diagnostics = Lint(source);

        Assert.DoesNotContain(diagnostics, d => d.Code == "NL001");
    }

    [Fact]
    public void NL012_UsesParameterSpan()
    {
        var source = "func greet(unusedName: string) { print \"hi\" }";
        var diagnostics = LintWithSource(source);

        var diagnostic = Assert.Single(diagnostics, d => d.Code == "NL012");
        Assert.Equal(1, diagnostic.Location.Line);
        Assert.Equal(12, diagnostic.Location.Column);
        Assert.Equal("unusedName".Length, diagnostic.Length);
    }

    [Fact]
    public void NL004_UsesFunctionNameSpan()
    {
        var source = "async func LoadData(): void { print \"hi\" }";
        var diagnostics = LintWithSource(source);

        var diagnostic = Assert.Single(diagnostics, d => d.Code == "NL004");
        Assert.Equal(1, diagnostic.Location.Line);
        Assert.Equal(12, diagnostic.Location.Column);
        Assert.Equal("LoadData".Length, diagnostic.Length);
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

    [Fact]
    public void NL002_NoWarningForTypeImportedFromFile()
    {
        var source = @"
import ""../Models/Task""

class TaskService {
    tasks: List<Task>
}";
        var diagnostics = Lint(source);

        Assert.DoesNotContain(diagnostics, d =>
            d.Code == "NL002" &&
            d.Message.Contains("Task") &&
            d.Suggestion != null &&
            d.Suggestion.Contains("System.Threading.Tasks"));
    }

    [Fact]
    public void NL002_NoWarningForInstanceMemberNamedLikeKnownType()
    {
        var source = @"
class HttpUrl {
    Path: string = ""/api/items""

    func ToDisplayString(): string {
        pathLength := Path.Length
        return $""{Path}:{pathLength}""
    }
}";
        var diagnostics = Lint(source);

        Assert.DoesNotContain(diagnostics, d =>
            d.Code == "NL002" &&
            d.Message.Contains("Path") &&
            d.Suggestion != null &&
            d.Suggestion.Contains("System.IO"));
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

    #region NL006: Unreachable Code Tests

    [Fact]
    public void NL006_UnreachableCode_ErrorsAfterReturn()
    {
        var source = @"
func main() {
    return
    x := 5
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL006");
        Assert.Equal(DiagnosticSeverity.Error, diagnostics.First(d => d.Code == "NL006").Severity);
    }

    [Fact]
    public void NL006_UnreachableCode_NoWarnForNormalFlow()
    {
        var source = @"
func main() {
    x := 5
    return
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL006");
    }

    #endregion

    #region NL011: Empty Catch Tests

    [Fact]
    public void NL011_EmptyCatch_WarnsOnEmptyCatchBlock()
    {
        var source = @"
func main() {
    try {
        x := 5
    } catch {
    }
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL011");
        Assert.Equal(DiagnosticSeverity.Error, diagnostics.First(d => d.Code == "NL011").Severity);
    }

    [Fact]
    public void NL011_EmptyCatch_UsesCatchKeywordSpan()
    {
        var source = """
func main() {
    try {
        print "x"
    } catch {
    }
}
""";
        var diagnostics = LintWithSource(source);

        var diagnostic = Assert.Single(diagnostics, diagnostic => diagnostic.Code == "NL011");
        Assert.Equal(4, diagnostic.Location.Line);
        Assert.Equal(7, diagnostic.Location.Column);
        Assert.Equal("catch".Length, diagnostic.Length);
    }

    [Fact]
    public void NL011_EmptyCatch_NoWarnOnCatchWithStatements()
    {
        var source = @"
import System
func main() {
    try {
        x := 5
    } catch (e: Exception) {
        Console.WriteLine(e.Message)
    }
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL011");
    }

    #endregion

    #region NL012: Unused Parameter Tests

    [Fact]
    public void NL012_UnusedParameter_InfoOnUnusedParam()
    {
        var source = @"
func add(a: int, b: int): int {
    return a
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL012" && d.Message.Contains("'b'"));
        Assert.Equal(DiagnosticSeverity.Error, diagnostics.First(d => d.Code == "NL012").Severity);
    }

    [Fact]
    public void NL012_UnusedParameter_NoInfoOnUsedParam()
    {
        var source = @"
func add(a: int, b: int): int {
    return a + b
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL012");
    }

    [Fact]
    public void NL012_UnusedParameter_NoErrorOnUnderscorePrefixed()
    {
        // Convention: _-prefixed parameter names are an explicit "intentionally unused"
        // signal, so the build-blocking NL012 error must not fire for them.
        var source = @"
func handler(event: int, _context: int) {
    x := event + 1
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL012" && d.Message.Contains("_context"));
    }
    [Fact]
    public void NL012_NoError_WhenParameterReadOnlyInNestedLocalFunction()
    {
        // Regression: a parameter read only inside a nested local function is still a use.
        var source = @"
func outer(value: int): int {
    func inner(): int {
        return value
    }
    return inner()
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL012");
    }

    [Fact]
    public void NL012_NoError_WhenParameterReadOnlyInLambda()
    {
        // Regression: a parameter captured and read only inside a lambda is still a use.
        var source = @"
func outer(value: int): int {
    var f = () => value
    return f()
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL012");
    }

    [Fact]
    public void NL012_StillFlags_GenuinelyUnusedParameter_WithNestedLocalFunction()
    {
        // A parameter never read anywhere (even via a nested function) is still flagged,
        // so the nested-function fix does not over-suppress real unused parameters.
        var source = @"
func outer(used: int, unused: int): int {
    func inner(): int {
        return used
    }
    return inner()
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL012" && d.Message.Contains("'unused'"));
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL012" && d.Message.Contains("'used'"));
    }

    [Fact]
    public void NL012_StillFlags_Parameter_ShadowedByLocalInNestedFunction()
    {
        // Over-suppression guard: the nested function reads its OWN local 'value', not the
        // enclosing parameter, so the parameter is genuinely unused and must still be flagged.
        var source = @"
func outer(value: int): int {
    func inner(): int {
        value := 1
        return value
    }
    return inner()
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL012" && d.Message.Contains("'value'"));
    }

    #endregion

    #region NL020: Shadowed Variable Tests

    [Fact]
    public void NL020_ShadowedVariable_WarnsWhenInnerShadowsOuter()
    {
        var source = @"
func main() {
    x := 5
    if true {
        x := 10
        y := x + 1
    }
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL020" && d.Message.Contains("'x'"));
        Assert.Equal(DiagnosticSeverity.Error, diagnostics.First(d => d.Code == "NL020").Severity);
    }

    [Fact]
    public void NL020_ShadowedVariable_NoWarnForDistinctNames()
    {
        var source = @"
func main() {
    x := 5
    if true {
        y := 10
        z := x + y
    }
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL020");
    }

    [Fact]
    public void NL020_ShadowedVariable_NoWarnForUnderscorePrefixed()
    {
        var source = @"
func main() {
    _x := 5
    if true {
        _x := 10
        y := _x + 1
    }
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL020");
    }

    #endregion

    #region NL010: Unused Import Tests

    [Fact]
    public void NL010_UnusedImport_ErrorsOnUnused()
    {
        // System.Collections.Generic is imported but no List/Dictionary/etc. is used
        var source = @"
import System.Collections.Generic

func Main() {
    x := 5
    y := x + 1
}";
        var diagnostics = Lint(source);
        // x and y are unused (NL001), but the import NL010 should also fire
        Assert.Contains(diagnostics, d => d.Code == "NL010");
        Assert.Equal(DiagnosticSeverity.Error, diagnostics.First(d => d.Code == "NL010").Severity);
    }

    [Fact]
    public void NL010_UnusedImport_SquiggleCoversNamespacePathNotKeyword()
    {
        // Regression for the strictness/squiggle audit (PR #160): the NL010 span
        // must underline the imported namespace path (`System.Linq`), not the
        // `import` keyword. The directive only records the statement column, so
        // the linter steps past the keyword to land on the path.
        var source = @"
import System.Linq

func Main() {
    x := 5
    y := x + 1
}";
        // LintWithSource so the linter has the source line to resolve the span against
        // (matches how the CLI and language server always supply source text).
        var diagnostics = LintWithSource(source);
        var nl010 = diagnostics.Single(d => d.Code == "NL010");

        // `import System.Linq` is the second line; the path starts after `import `.
        var importLine = source.Replace("\r\n", "\n").Split('\n')[nl010.Location.Line - 1];
        var covered = importLine.Substring(nl010.Location.Column - 1, nl010.Length);

        Assert.Equal("System.Linq", covered);
        Assert.Equal("System.Linq".Length, nl010.Length);
    }

    [Fact]
    public void NL010_UnusedImport_NoWarnWhenTypeUsed()
    {
        var source = @"
import System.Collections.Generic

func Main() {
    list := new List<int>()
    x := list
}";
        var diagnostics = Lint(source);
        // List is used, so the import is not unused
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_NoWarnForSystemWhenConsoleUsed()
    {
        // 'import System' is considered used when Console appears as an identifier
        var source = @"
import System

func Main() {
    Console.WriteLine(""hi"")
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_NoWarnForUnknownNamespace()
    {
        // Imports from namespaces we don't track — conservatively marked as used
        var source = @"
import MyCompany.MyLibrary

func Main() {
    x := 5
    y := x + 1
}";
        var diagnostics = Lint(source);
        // We can't determine if the namespace is used — no NL010 should fire
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_NoWarnWhenLinqExtensionMethodUsed()
    {
        // System.Linq should not be flagged when LINQ extension methods are called
        var source = @"
import System.Collections.Generic
import System.Linq

func Main() {
    items := new List<int>()
    filtered := items.Where(x => x > 1)
    result := filtered.Select(x => x * 2)
    _ := result
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_NoWarnWhenToListUsed()
    {
        var source = @"
import System.Collections.Generic
import System.Linq

func Main() {
    items := new List<int>()
    result := items.ToList()
    _ := result
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_NoWarnForGenericInterfaceTypes()
    {
        // IEnumerable<>, IList<>, etc. should count as usage of System.Collections.Generic
        var source = @"
import System.Collections.Generic

func GetItems(): IEnumerable<int> {
    return new List<int>()
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_NoWarnForIAsyncEnumerable()
    {
        var source = @"
import System.Collections.Generic

func GetItems(): IAsyncEnumerable<string> {
    return nil
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_ErrorsWhenLinqNotActuallyUsed()
    {
        // System.Linq should still be flagged when no LINQ methods are called
        var source = @"
import System.Linq

func Main() {
    x := 5
    y := x + 1
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_NoWarnWhenUsedInTestBlock()
    {
        // Imports used only inside test blocks should not be flagged
        var source = @"
import System.Collections.Generic

test ""uses list from import"" {
    items := new List<int>()
    assert items.Count == 0
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL010");
    }

    [Fact]
    public void NL010_UnusedImport_ErrorsWhenUnusedWithTestBlock()
    {
        // Imports not used in test blocks should still be flagged
        var source = @"
import System.Collections.Generic

test ""does not use the import"" {
    x := 5
    assert x == 5
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL010");
    }

    #endregion

    #region NL016: Redundant Null Check Tests

    [Fact]
    public void NL016_RedundantNullCheck_WarnsOnNewExpression()
    {
        // `new` expression directly in the if condition — always non-null
        var source = @"
import System.Collections.Generic

func Main() {
    if new List<int>() != null {
        x := 5
    }
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL016");
        Assert.Equal(DiagnosticSeverity.Error, diagnostics.First(d => d.Code == "NL016").Severity);
    }

    [Fact]
    public void NL016_RedundantNullCheck_WarnsOnArrayLiteralInCondition()
    {
        var source = @"
func Main() {
    if [1, 2, 3] != null {
        x := 5
    }
}";
        var diagnostics = Lint(source);
        Assert.Contains(diagnostics, d => d.Code == "NL016");
    }

    [Fact]
    public void NL016_RedundantNullCheck_NoWarnOnVariableNullCheck()
    {
        // A variable identifier — we can't know if it's null without type info
        var source = @"
func Main() {
    s := GetString()
    if s != null {
        y := s
    }
}

func GetString(): string {
    return ""hello""
}";
        var diagnostics = Lint(source);
        Assert.DoesNotContain(diagnostics, d => d.Code == "NL016");
    }

    #endregion

    #region .editorconfig Configuration Tests

    [Fact]
    public void LinterConfig_DefaultSeverities()
    {
        var config = LinterConfig.Default();

        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL001"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL002"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL003"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL004"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL006"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL010"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL011"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL012"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL016"));
        Assert.Equal(DiagnosticSeverity.Error, config.GetSeverity("NL020"));
    }

    [Fact]
    public void DiagnosticCatalog_HasStrictBuildBlockingLintDefaultsWithoutMigrationDiagnostics()
    {
        var codes = DiagnosticCatalog.Descriptors.Select(descriptor => descriptor.Code).ToList();

        Assert.Equal(codes.Count, codes.Distinct().Count());

        Assert.True(DiagnosticCatalog.TryGetDescriptor("NL001", out var unusedVariable));
        Assert.Equal(DiagnosticSeverity.Error, unusedVariable.DefaultSeverity);
        Assert.True(unusedVariable.BlocksBuildByDefault);

        Assert.True(DiagnosticCatalog.TryGetDescriptor("NL006", out var unreachableCode));
        Assert.Equal(DiagnosticSeverity.Error, unreachableCode.DefaultSeverity);
        Assert.True(unreachableCode.BlocksBuildByDefault);

        Assert.True(DiagnosticCatalog.TryGetDescriptor("NL010", out var unusedImport));
        Assert.Equal(DiagnosticSeverity.Error, unusedImport.DefaultSeverity);
        Assert.True(unusedImport.BlocksBuildByDefault);

        Assert.DoesNotContain(codes, code => code.StartsWith("NLM", StringComparison.Ordinal));
    }

    [Fact]
    public void DiagnosticCatalog_RegistersPerformanceDiagnostics()
    {
        var expected = new[]
        {
            ("NL950", "Allocation here", DiagnosticSeverity.Info),
            ("NL951", "Boxing here", DiagnosticSeverity.Warning),
            ("NL952", "Virtual dispatch not devirtualized", DiagnosticSeverity.Info),
            ("NL953", "Closure allocation", DiagnosticSeverity.Warning),
            ("NL954", "Delegate allocation", DiagnosticSeverity.Warning),
        };

        foreach (var (code, title, severity) in expected)
        {
            Assert.True(
                DiagnosticCatalog.TryGetDescriptor(code, out var descriptor),
                $"Expected performance diagnostic '{code}' to be registered in the catalog.");

            Assert.Equal(title, descriptor.Title);
            Assert.Equal(DiagnosticCategory.Performance, descriptor.Category);
            Assert.Equal(DiagnosticSource.Compiler, descriptor.Source);
            Assert.Equal(severity, descriptor.DefaultSeverity);
            Assert.False(descriptor.BlocksBuildByDefault);
            Assert.False(string.IsNullOrWhiteSpace(descriptor.Explanation));
        }
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

    [Fact]
    public void LinterConfig_DisablesRuleFromEditorConfigNone()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-linter-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            File.WriteAllText(
                Path.Combine(tempDir, ".editorconfig"),
                """
                root = true

                [*.nl]
                dotnet_diagnostic.NL001.severity = none
                """);

            var source = "func main() { x := 5 }";
            var lexer = new Lexer(source, Path.Combine(tempDir, "test.nl"));
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens);
            var result = parser.ParseCompilationUnit();

            var config = LinterConfig.FromEditorConfig(tempDir);
            var linter = new Linter(config);
            var diagnostics = linter.Lint(result.CompilationUnit!, Path.Combine(tempDir, "test.nl"));

            Assert.False(config.IsRuleEnabled("NL001"));
            Assert.DoesNotContain(diagnostics, diagnostic => diagnostic.Code == "NL001");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
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
