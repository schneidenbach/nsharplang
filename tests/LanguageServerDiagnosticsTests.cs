using System.Linq;
using Microsoft.Extensions.Logging.Abstractions;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using Xunit;

namespace NSharpLang.Tests;

public class LanguageServerDiagnosticsTests
{
    [Fact]
    public void Diagnostics_InvalidMemberStatementAndBadCall()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///test.nl";

        var source = @"
func main() {
    greeting := ""hello""
    greeting.CompareTo
    greeting.CompareTo()
}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = document!.Diagnostics ?? Enumerable.Empty<CompilerError>();
        Assert.Contains(diagnostics, diagnostic => diagnostic.Code == ErrorCode.InvalidExpressionStatement);
        Assert.Contains(diagnostics, diagnostic => diagnostic.Code == ErrorCode.NoMatchingOverload);
    }

    [Fact]
    public void Diagnostics_NSharpNoMatchingOverload_UsesCallableNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///nsharp-overload-spans.nl";

        var source = """
class Processor {
    func Process(x: int): int { return x }
    func Process(x: string): string { return x }
}

func main() {
    p := new Processor()
    p.Process(true)
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.NoMatchingOverload &&
                          diagnostic.Message.Contains("Process"));

        AssertDiagnosticSpan(diagnostic, line: 8, column: 7, length: "Process".Length);
        AssertLspRange(diagnostic, line0: 7, startCharacter: 6, endCharacter: 13);
        Assert.Contains("Process(x: int): int", diagnostic.ContextualHint);
        Assert.Contains("Process(x: string): string", diagnostic.ContextualHint);
    }

    [Fact]
    public void Diagnostics_PossibleNullDereference_UsesStableCompilerCode()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///nullable.nl";

        var source = @"
func main() {
    x: string? = ""hello""
    len := x.Length
}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = document!.Diagnostics ?? Enumerable.Empty<CompilerError>();
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.PossibleNullAccess &&
            diagnostic.DiagnosticId == "NL905" &&
            diagnostic.Severity == ErrorSeverity.Error &&
            diagnostic.Suggestion != null &&
            diagnostic.Suggestion.Contains("?.", System.StringComparison.Ordinal));
    }

    [Fact]
    public void Diagnostics_SemanticErrors_UseExpectedTokenSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///semantic-spans.nl";

        var source = """
func TakesInt(value: int) {}
func main() {
    maybeCustomerName: string? = "Ada"
    print maybeCustomerName.Length
    TakesInt("oops")
    TakesInt()
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var nullAccess = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.PossibleNullAccess);
        Assert.Equal(4, nullAccess.Line);
        Assert.Equal(11, nullAccess.Column);
        Assert.Equal("maybeCustomerName".Length, nullAccess.Length);

        var wrongArgument = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("Cannot pass"));
        Assert.Equal(5, wrongArgument.Line);
        Assert.Equal(14, wrongArgument.Column);
        Assert.Equal("\"oops\"".Length, wrongArgument.Length);

        var wrongCount = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.WrongArgumentCount);
        Assert.Equal(6, wrongCount.Line);
        Assert.Equal(5, wrongCount.Column);
        Assert.Equal("TakesInt".Length, wrongCount.Length);

        var nullAccessLsp = LspDiagnosticConverter.FromCompilerError(nullAccess);
        Assert.Equal(3, (int)nullAccessLsp.Range.Start.Line);
        Assert.Equal(10, (int)nullAccessLsp.Range.Start.Character);
        Assert.Equal(27, (int)nullAccessLsp.Range.End.Character);

        var wrongArgumentLsp = LspDiagnosticConverter.FromCompilerError(wrongArgument);
        Assert.Equal(4, (int)wrongArgumentLsp.Range.Start.Line);
        Assert.Equal(13, (int)wrongArgumentLsp.Range.Start.Character);
        Assert.Equal(19, (int)wrongArgumentLsp.Range.End.Character);

        var wrongCountLsp = LspDiagnosticConverter.FromCompilerError(wrongCount);
        Assert.Equal(5, (int)wrongCountLsp.Range.Start.Line);
        Assert.Equal(4, (int)wrongCountLsp.Range.Start.Character);
        Assert.Equal(12, (int)wrongCountLsp.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_TypeMismatches_UseOffendingExpressionSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///type-mismatch-spans.nl";

        var source = """
func TakesVoid(): void {
}

func ExpressionBodyMismatch(): int => "bad"

func ExpressionBodyRequiresReturnType() => "bad"

func main(): int {
    declared: int = "hi"
    inferred := TakesVoid()
    if "yes" {
        return "bad"
    }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var expressionBodyMismatch = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("ExpressionBodyMismatch"));
        AssertDiagnosticSpan(expressionBodyMismatch, line: 4, column: 39, length: "\"bad\"".Length);
        AssertLspRange(expressionBodyMismatch, line0: 3, startCharacter: 38, endCharacter: 43);

        var expressionBodyRequiresReturnType = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("ExpressionBodyRequiresReturnType"));
        AssertDiagnosticSpan(expressionBodyRequiresReturnType, line: 6, column: 44, length: "\"bad\"".Length);
        AssertLspRange(expressionBodyRequiresReturnType, line0: 5, startCharacter: 43, endCharacter: 48);

        var localInitializer = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 9 &&
                          diagnostic.Message == "Type mismatch");
        AssertDiagnosticSpan(localInitializer, line: 9, column: 21, length: "\"hi\"".Length);
        AssertLspRange(localInitializer, line0: 8, startCharacter: 20, endCharacter: 24);

        var voidAssignment = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("void"));
        AssertDiagnosticSpan(voidAssignment, line: 10, column: 17, length: "TakesVoid".Length);
        AssertLspRange(voidAssignment, line0: 9, startCharacter: 16, endCharacter: 25);

        var ifCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 11 &&
                          diagnostic.Message == "Type mismatch");
        AssertDiagnosticSpan(ifCondition, line: 11, column: 8, length: "\"yes\"".Length);
        AssertLspRange(ifCondition, line0: 10, startCharacter: 7, endCharacter: 12);

        var returnValue = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("main") &&
                          diagnostic.Message.Contains("returns string"));
        AssertDiagnosticSpan(returnValue, line: 12, column: 16, length: "\"bad\"".Length);
        AssertLspRange(returnValue, line0: 11, startCharacter: 15, endCharacter: 20);
    }

    [Fact]
    public void Diagnostics_EnumMemberInitializerTypeMismatches_UseInitializerValueSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///enum-value-spans.nl";

        var source = """
enum HttpCode: int {
    Ok = "ok"
}

enum Label: string {
    Ready = 1
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var numericValue = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("'Ok'"));
        AssertDiagnosticSpan(numericValue, line: 2, column: 10, length: "\"ok\"".Length);
        AssertLspRange(numericValue, line0: 1, startCharacter: 9, endCharacter: 13);

        var stringValue = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("'Ready'"));
        AssertDiagnosticSpan(stringValue, line: 6, column: 13, length: "1".Length);
        AssertLspRange(stringValue, line0: 5, startCharacter: 12, endCharacter: 13);
    }

    [Fact]
    public void Diagnostics_ControlFlowAndCollectionTypeMismatches_UseOffendingExpressionSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///control-flow-type-mismatch-spans.nl";

        var source = """
func main() {
    while "loop" {
    }

    for i := 0; "loop"; i++ {
    }

    value := 1
    answer := "maybe" ? 1 : 2
    numbers := [1, "two"]
    label := match value {
        n when "guard" => "positive",
        _ => 12345
    }
    print label
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var whileCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("'while'"));
        AssertDiagnosticSpan(whileCondition, line: 2, column: 11, length: "\"loop\"".Length);
        AssertLspRange(whileCondition, line0: 1, startCharacter: 10, endCharacter: 16);

        var forCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("'for'"));
        AssertDiagnosticSpan(forCondition, line: 5, column: 17, length: "\"loop\"".Length);
        AssertLspRange(forCondition, line0: 4, startCharacter: 16, endCharacter: 22);

        var ternaryCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("ternary expression"));
        AssertDiagnosticSpan(ternaryCondition, line: 9, column: 15, length: "\"maybe\"".Length);
        AssertLspRange(ternaryCondition, line0: 8, startCharacter: 14, endCharacter: 21);

        var arrayElement = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("All elements in an array"));
        AssertDiagnosticSpan(arrayElement, line: 10, column: 20, length: "\"two\"".Length);
        AssertLspRange(arrayElement, line0: 9, startCharacter: 19, endCharacter: 24);

        var matchGuard = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.GuardNotBoolean);
        AssertDiagnosticSpan(matchGuard, line: 12, column: 16, length: "\"guard\"".Length);
        AssertLspRange(matchGuard, line0: 11, startCharacter: 15, endCharacter: 22);

        var matchArm = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("All match arms"));
        AssertDiagnosticSpan(matchArm, line: 13, column: 14, length: "12345".Length);
        AssertLspRange(matchArm, line0: 12, startCharacter: 13, endCharacter: 18);
    }

    [Fact]
    public void Diagnostics_LoopControlOutsideLoop_UseFullKeywordSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///loop-control-spans.nl";

        var source = """
func main() {
    break
    continue
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var breakDiagnostic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'break'"));
        AssertDiagnosticSpan(breakDiagnostic, line: 2, column: 5, length: "break".Length);
        AssertLspRange(breakDiagnostic, line0: 1, startCharacter: 4, endCharacter: 9);

        var continueDiagnostic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'continue'"));
        AssertDiagnosticSpan(continueDiagnostic, line: 3, column: 5, length: "continue".Length);
        AssertLspRange(continueDiagnostic, line0: 2, startCharacter: 4, endCharacter: 12);
    }

    [Fact]
    public void Diagnostics_ReturnOutsideFunctionAndTargetlessDefault_UseFullKeywordSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///keyword-semantic-spans.tests.nl";

        var source = """
func main() {
    value := default
}

test "does not return" {
    return
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var targetlessDefault = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.CannotInferType &&
                          diagnostic.Message.Contains("'default'"));
        AssertDiagnosticSpan(targetlessDefault, line: 2, column: 14, length: "default".Length);
        AssertLspRange(targetlessDefault, line0: 1, startCharacter: 13, endCharacter: 20);

        var returnOutsideFunction = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'return' can only"));
        AssertDiagnosticSpan(returnOutsideFunction, line: 6, column: 5, length: "return".Length);
        AssertLspRange(returnOutsideFunction, line0: 5, startCharacter: 4, endCharacter: 10);
    }

    [Fact]
    public void Diagnostics_ReadonlyAssignment_UsesAssignedFieldNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///readonly-assignment-spans.nl";

        var source = """
class Account {
    readonly id: string = "initial"

    func Change() {
        id = "next"
        this.id = "again"
    }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var directAssignment = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ReadonlyAssignment &&
                          diagnostic.Line == 5);
        AssertDiagnosticSpan(directAssignment, line: 5, column: 9, length: "id".Length);
        AssertLspRange(directAssignment, line0: 4, startCharacter: 8, endCharacter: 10);

        var memberAssignment = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ReadonlyAssignment &&
                          diagnostic.Line == 6);
        AssertDiagnosticSpan(memberAssignment, line: 6, column: 14, length: "id".Length);
        AssertLspRange(memberAssignment, line0: 5, startCharacter: 13, endCharacter: 15);
    }

    [Fact]
    public void Diagnostics_UndefinedMember_UsesMemberNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///undefined-member-spans.nl";

        var source = """
func main() {
    print "asdf".ToUp()
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.UndefinedMember &&
                          diagnostic.Message.Contains("ToUp"));

        AssertDiagnosticSpan(diagnostic, line: 2, column: 18, length: "ToUp".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 17, endCharacter: 21);
    }

    [Fact]
    public void Diagnostics_FileImportAliasMissingSymbol_UsesRequestedSymbolSpan()
    {
        var tempRoot = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"nsharp-lsp-alias-symbol-span-{System.Guid.NewGuid():N}");
        System.IO.Directory.CreateDirectory(tempRoot);

        try
        {
            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "project.yml"), """
name: AliasSymbolSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
""");

            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "Helpers.nl"), """
func PresentThing(): int {
    return 1
}
""");

            var programPath = System.IO.Path.Combine(tempRoot, "Program.nl");
            var source = """
import "./Helpers" as Lib

func main() {
    Lib.MissingThing()
}
""";
            System.IO.File.WriteAllText(programPath, source);

            var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
            documentManager.UpdateDocument(new System.Uri(programPath).AbsoluteUri, source, version: 1);

            var document = documentManager.GetDocument(new System.Uri(programPath).AbsoluteUri);
            Assert.NotNull(document);

            var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
                diagnostic => diagnostic.Code == ErrorCode.UndefinedMember &&
                              diagnostic.Message.Contains("MissingThing"));

            AssertDiagnosticSpan(diagnostic, line: 4, column: 9, length: "MissingThing".Length);
            AssertLspRange(diagnostic, line0: 3, startCharacter: 8, endCharacter: 20);
        }
        finally
        {
            if (System.IO.Directory.Exists(tempRoot))
            {
                System.IO.Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    [Fact]
    public void Diagnostics_MissingFileImport_UsesQuotedPathSpan()
    {
        var tempRoot = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"nsharp-lsp-missing-import-span-{System.Guid.NewGuid():N}");
        System.IO.Directory.CreateDirectory(tempRoot);

        try
        {
            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "project.yml"), """
name: MissingImportSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
""");

            var programPath = System.IO.Path.Combine(tempRoot, "Program.nl");
            var source = """
import "./Missing"

func main() {
}
""";
            System.IO.File.WriteAllText(programPath, source);

            var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
            documentManager.UpdateDocument(new System.Uri(programPath).AbsoluteUri, source, version: 1);

            var document = documentManager.GetDocument(new System.Uri(programPath).AbsoluteUri);
            Assert.NotNull(document);

            var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
                diagnostic => diagnostic.Code == ErrorCode.ImportNotFound);

            AssertDiagnosticSpan(diagnostic, line: 1, column: 8, length: "\"./Missing\"".Length);
            AssertLspRange(diagnostic, line0: 0, startCharacter: 7, endCharacter: 18);
        }
        finally
        {
            if (System.IO.Directory.Exists(tempRoot))
            {
                System.IO.Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    [Fact]
    public void Diagnostics_FileImportCollision_UsesDuplicateQuotedPathSpan()
    {
        var tempRoot = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"nsharp-lsp-import-collision-span-{System.Guid.NewGuid():N}");
        System.IO.Directory.CreateDirectory(tempRoot);

        try
        {
            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "project.yml"), """
name: ImportCollisionSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
""");

            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "A.nl"), """
class Shared {
}
""");

            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "B.nl"), """
class Shared {
}
""");

            var programPath = System.IO.Path.Combine(tempRoot, "Program.nl");
            var source = """
import "./A"
import "./B"

func main() {
}
""";
            System.IO.File.WriteAllText(programPath, source);

            var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
            documentManager.UpdateDocument(new System.Uri(programPath).AbsoluteUri, source, version: 1);

            var document = documentManager.GetDocument(new System.Uri(programPath).AbsoluteUri);
            Assert.NotNull(document);

            var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
                diagnostic => diagnostic.Code == ErrorCode.ImportCollision &&
                              diagnostic.Message.Contains("Shared"));

            AssertDiagnosticSpan(diagnostic, line: 2, column: 8, length: "\"./B\"".Length);
            AssertLspRange(diagnostic, line0: 1, startCharacter: 7, endCharacter: 12);
            Assert.NotNull(diagnostic.Suggestion);
            Assert.NotNull(diagnostic.ContextualHint);
            Assert.Contains("alias", diagnostic.Suggestion);
            Assert.Contains("\"./A\"", diagnostic.ContextualHint);
            Assert.Contains("\"./B\"", diagnostic.ContextualHint);
        }
        finally
        {
            if (System.IO.Directory.Exists(tempRoot))
            {
                System.IO.Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    [Fact]
    public void Diagnostics_UnreachableStatement_UsesUnreachableKeywordSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unreachable-statement-spans.nl";

        var source = """
func main() {
    return
    print "after"
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var unreachableDiagnostic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.UnreachableStatement);
        AssertDiagnosticSpan(unreachableDiagnostic, line: 3, column: 5, length: "print".Length);
        AssertLspRange(unreachableDiagnostic, line0: 2, startCharacter: 4, endCharacter: 9);
    }

    [Fact]
    public void Diagnostics_InvalidVariableDeclarations_UseFullNameSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///variable-declaration-spans.nl";

        var source = """
func main() {
    const answer: int
    let value
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var constWithoutInitializer = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'const'"));
        AssertDiagnosticSpan(constWithoutInitializer, line: 2, column: 11, length: "answer".Length);
        AssertLspRange(constWithoutInitializer, line0: 1, startCharacter: 10, endCharacter: 16);

        var unknownVariableType = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("determine the type"));
        AssertDiagnosticSpan(unknownVariableType, line: 3, column: 9, length: "value".Length);
        AssertLspRange(unknownVariableType, line0: 2, startCharacter: 8, endCharacter: 13);
    }

    [Fact]
    public void Diagnostics_InvalidGenericConstraints_UseOffendingConstraintSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///generic-constraint-spans.nl";

        var source = """
func BadClassStruct<T>(value: T): T where T : class, struct {
    return value
}

func BadStructNew<T>(value: T): T where T : struct, new() {
    return value
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var classStructConflict = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("both 'class' and 'struct'"));
        AssertDiagnosticSpan(classStructConflict, line: 1, column: 54, length: "struct".Length);
        AssertLspRange(classStructConflict, line0: 0, startCharacter: 53, endCharacter: 59);

        var structNewConflict = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("Cannot combine 'struct' and 'new()'"));
        AssertDiagnosticSpan(structNewConflict, line: 5, column: 53, length: "new()".Length);
        AssertLspRange(structNewConflict, line0: 4, startCharacter: 52, endCharacter: 57);
    }

    [Fact]
    public void Diagnostics_AssignmentAndOperatorTypeMismatches_UseSpecificExpressionSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///assignment-operator-type-mismatch-spans.nl";

        var source = """
func main() {
    x := 0
    x = "text"

    oneBad := 1 - "two"
    bothBad := "one" - "two"
    logicalRight := true && 1
    logicalBoth := 1 && 2

    print x
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var assignmentValue = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 3 &&
                          diagnostic.Message == "Type mismatch");
        AssertDiagnosticSpan(assignmentValue, line: 3, column: 9, length: "\"text\"".Length);
        AssertLspRange(assignmentValue, line0: 2, startCharacter: 8, endCharacter: 14);

        var arithmeticRightOperand = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 5 &&
                          diagnostic.Message.Contains("right side"));
        AssertDiagnosticSpan(arithmeticRightOperand, line: 5, column: 19, length: "\"two\"".Length);
        AssertLspRange(arithmeticRightOperand, line0: 4, startCharacter: 18, endCharacter: 23);

        var arithmeticOperator = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 6 &&
                          diagnostic.Message.Contains("I found 'string' and 'string'"));
        AssertDiagnosticSpan(arithmeticOperator, line: 6, column: 22, length: "-".Length);
        AssertLspRange(arithmeticOperator, line0: 5, startCharacter: 21, endCharacter: 22);

        var logicalRightOperand = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 7 &&
                          diagnostic.Message.Contains("right side"));
        AssertDiagnosticSpan(logicalRightOperand, line: 7, column: 29, length: "1".Length);
        AssertLspRange(logicalRightOperand, line0: 6, startCharacter: 28, endCharacter: 29);

        var logicalOperator = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 8 &&
                          diagnostic.Message.Contains("I found 'int' and 'int'"));
        AssertDiagnosticSpan(logicalOperator, line: 8, column: 22, length: "&&".Length);
        AssertLspRange(logicalOperator, line0: 7, startCharacter: 21, endCharacter: 23);
    }

    [Fact]
    public void Diagnostics_PatternErrors_UseSpecificPatternSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///pattern-error-spans.nl";

        var source = """
union Result {
    Success { value: int }
    Failure { message: string }
}

record User {
    Name: string
}

func main() {
    r := new Result.Success { value: 42 }
    x := match r {
        Result.Unknown => 0,
        Result.Success { missing: value } => value,
        Result.Failure { message } => 0
    }

    user := new User { Name: "Ada" }
    y := match user {
        { Missing: value } => value,
        _ => "unknown"
    }

    n := 1
    z := match n {
        [first, ..] => first,
        _ => 0
    }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var missingCase = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidPattern &&
                          diagnostic.Line == 13 &&
                          diagnostic.Message.Contains("'Result.Unknown'"));
        AssertDiagnosticSpan(missingCase, line: 13, column: 9, length: "Result.Unknown".Length);
        AssertLspRange(missingCase, line0: 12, startCharacter: 8, endCharacter: 22);

        var missingUnionProperty = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidPattern &&
                          diagnostic.Line == 14 &&
                          diagnostic.Message.Contains("'missing'"));
        AssertDiagnosticSpan(missingUnionProperty, line: 14, column: 26, length: "missing".Length);
        AssertLspRange(missingUnionProperty, line0: 13, startCharacter: 25, endCharacter: 32);

        var missingObjectProperty = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidPattern &&
                          diagnostic.Line == 20 &&
                          diagnostic.Message.Contains("'Missing'"));
        AssertDiagnosticSpan(missingObjectProperty, line: 20, column: 11, length: "Missing".Length);
        AssertLspRange(missingObjectProperty, line0: 19, startCharacter: 10, endCharacter: 17);

        var listPatternMismatch = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.PatternTypeMismatch);
        AssertDiagnosticSpan(listPatternMismatch, line: 26, column: 9, length: "[first, ..]".Length);
        AssertLspRange(listPatternMismatch, line0: 25, startCharacter: 8, endCharacter: 19);
    }

    [Fact]
    public void Diagnostics_DeclarationErrors_UseDeclarationNameSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///declaration-spans.nl";

        var source = """
func Duplicate(value: int): int { return value }

func Duplicate(value: int): int { return value }

class Thing {}
class Thing {}

enum Status {
    Pending,
    Pending
}

union Result {
    Success
    Success
}

func BadParams(params rest: int[], tail: int) {}

func BadOrdering(first: int = 1, second: int) {}

func BadDefault(value: int = makeValue()) {}

func main() {
    value := 1
    value := 2
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var duplicateFunction = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 3 &&
                          diagnostic.Message.Contains("'Duplicate'"));
        AssertDiagnosticSpan(duplicateFunction, line: 3, column: 6, length: "Duplicate".Length);
        AssertLspRange(duplicateFunction, line0: 2, startCharacter: 5, endCharacter: 14);

        var duplicateType = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 6 &&
                          diagnostic.Message.Contains("Thing"));
        AssertDiagnosticSpan(duplicateType, line: 6, column: 7, length: "Thing".Length);

        var duplicateEnumMember = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 10 &&
                          diagnostic.Message.Contains("enum member"));
        AssertDiagnosticSpan(duplicateEnumMember, line: 10, column: 5, length: "Pending".Length);

        var duplicateUnionCase = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 15 &&
                          diagnostic.Message.Contains("union case"));
        AssertDiagnosticSpan(duplicateUnionCase, line: 15, column: 5, length: "Success".Length);

        var paramsNotLast = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ParamsNotLast);
        AssertDiagnosticSpan(paramsNotLast, line: 18, column: 23, length: "rest".Length);

        var requiredAfterOptional = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.RequiredParameterAfterOptional);
        AssertDiagnosticSpan(requiredAfterOptional, line: 20, column: 34, length: "second".Length);

        var invalidDefault = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidDefaultParameterValue);
        AssertDiagnosticSpan(invalidDefault, line: 22, column: 30, length: "makeValue".Length);

        var duplicateLocal = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 26 &&
                          diagnostic.Message.Contains("'value'"));
        AssertDiagnosticSpan(duplicateLocal, line: 26, column: 5, length: "value".Length);
    }

    [Fact]
    public void Diagnostics_OperatorOverloadErrors_UseOperatorKeywordAndSymbolSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///operator-overload-spans.nl";

        var source = """
class Vector {
    X: int

    func operator %(a: Vector, b: Vector, c: Vector): Vector {
        return a
    }

    static func operator true(a: Vector, b: Vector): bool {
        return true
    }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var missingStatic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidOperatorOverload);
        AssertDiagnosticSpan(missingStatic, line: 4, column: 10, length: "operator".Length);
        AssertLspRange(missingStatic, line0: 3, startCharacter: 9, endCharacter: 17);

        var moduloArity = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.OperatorParameterCount &&
                          diagnostic.Message.Contains("'%'"));
        AssertDiagnosticSpan(moduloArity, line: 4, column: 19, length: "%".Length);
        AssertLspRange(moduloArity, line0: 3, startCharacter: 18, endCharacter: 19);

        var trueArity = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.OperatorParameterCount &&
                          diagnostic.Message.Contains("'true'"));
        AssertDiagnosticSpan(trueArity, line: 8, column: 26, length: "true".Length);
        AssertLspRange(trueArity, line0: 7, startCharacter: 25, endCharacter: 29);
    }

    [Fact]
    public void Diagnostics_DuplicateTestLifecycleBlocks_UseFullKeywordSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///duplicate-lifecycle.tests.nl";

        var source = """
setup {
    first := 1
}

setup {
    second := 2
}

teardown {
    Cleanup()
}

teardown {
    CleanupAgain()
}

func Cleanup() {}
func CleanupAgain() {}

test "works" {
    assert true
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var duplicateSetup = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Message.Contains("setup block"));
        AssertDiagnosticSpan(duplicateSetup, line: 5, column: 1, length: "setup".Length);
        AssertLspRange(duplicateSetup, line0: 4, startCharacter: 0, endCharacter: 5);

        var duplicateTeardown = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Message.Contains("teardown block"));
        AssertDiagnosticSpan(duplicateTeardown, line: 13, column: 1, length: "teardown".Length);
        AssertLspRange(duplicateTeardown, line0: 12, startCharacter: 0, endCharacter: 8);
    }

    [Fact]
    public void Diagnostics_ReturnValueWithoutReturnType_ExplainsImplicitVoid()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///return-value.nl";

        var source = @"
func Hi() {
    return 42
}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.TypeMismatch);

        var message = diagnostic.FormatForTooling(includeCode: true, includeLocation: false);
        Assert.Contains("NL202: Function 'Hi' returns int but has no return type", message);
        Assert.Contains("N# treats it as `void`", message);
        Assert.Contains("Add `: int`", message);
        Assert.Contains("return 42", message);
    }

    private static void AssertDiagnosticSpan(CompilerError diagnostic, int line, int column, int length)
    {
        Assert.Equal(line, diagnostic.Line);
        Assert.Equal(column, diagnostic.Column);
        Assert.Equal(length, diagnostic.Length);
    }

    private static void AssertLspRange(CompilerError diagnostic, int line0, int startCharacter, int endCharacter)
    {
        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(line0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(startCharacter, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(endCharacter, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_InvalidMemberCallsAndReturnType_AreAllPublished()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///invalid-member-calls.nl";

        var source = """
package HelloWorld

func Hi() {
    "asdf".toUp()
    asdf := "asdf"
    asdf.sdd()
    return 42
}
""";

        documentManager.MarkEditorOpen(uri);
        documentManager.UpdateDocument(uri, source, version: 1);

        var publications = documentManager.GetDiagnosticsToPublish(uri);
        var diagnostics = Assert.Single(publications).CompilerDiagnostics.ToList();

        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.UndefinedMember &&
            diagnostic.Message.Contains("toUp") &&
            diagnostic.Line == 4);
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.UndefinedMember &&
            diagnostic.Message.Contains("sdd") &&
            diagnostic.Line == 6);
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.TypeMismatch &&
            diagnostic.Message.Contains("returns int but has no return type") &&
            diagnostic.Line == 7);
    }

    [Fact]
    public void Diagnostics_MalformedEditingBuffer_PublishesHighSignalProblems()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///malformed.nl";

        var source = """
class User {
    Name: string
}

func main() {
    first := 1 +
    Console.WriteLine(undefinedFromLsp)
    user := new User { Name = "Ada" }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.ExpectedToken &&
            diagnostic.Line == 6 &&
            diagnostic.Length == 1 &&
            diagnostic.Message.Contains("Expected expression after '+'"));
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.InvalidSyntax &&
            diagnostic.Line == 8 &&
            diagnostic.Length == 1 &&
            diagnostic.Message.Contains("Object initializer member 'Name' uses '='"));
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.UndefinedVariable &&
            diagnostic.Message.Contains("undefinedFromLsp"));
        Assert.DoesNotContain(diagnostics, diagnostic =>
            diagnostic.Message.Contains("<error>", System.StringComparison.Ordinal));
        Assert.True(diagnostics.Count <= 6,
            $"Expected bounded diagnostics, got {diagnostics.Count}: {string.Join("; ", diagnostics.Select(d => $"{d.DiagnosticId} {d.Message}"))}");
    }

    [Fact]
    public void LspCompilerDiagnostic_UsesExactCompilerSpan()
    {
        var error = CompilerError.WithSnippet(
            ErrorCode.InvalidSyntax,
            "Object initializer member 'Name' uses '='; N# uses ':'",
            "Program.nl",
            line: 8,
            column: 29,
            sourceSnippet: "    user := new User { Name = \"Ada\" }",
            length: 1);

        var diagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(7, (int)diagnostic.Range.Start.Line);
        Assert.Equal(28, (int)diagnostic.Range.Start.Character);
        Assert.Equal(7, (int)diagnostic.Range.End.Line);
        Assert.Equal(29, (int)diagnostic.Range.End.Character);
    }

    [Fact]
    public void LspLinterDiagnostic_UsesExactLinterSpan()
    {
        var diagnostic = new Diagnostic(
            "NL012",
            "Parameter 'unusedName' in 'greet' is never read — is it needed?",
            new Location(1, 12, "Program.nl"),
            DiagnosticSeverity.Info,
            "Prefix with '_' if this is intentional",
            "unusedName".Length);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(11, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(21, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_IncompleteMemberAccess_PointsAtTrailingDot()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///member-dot.nl";

        var source = """
func main() {
    name := "Ada"
    name.
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ExpectedToken && d.Message.Contains("Expected member name"));

        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(9, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.Contains("dot", diagnostic.HumanExplanation, System.StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidExpressionStatement ||
                 d.Message.Contains("<error>", System.StringComparison.Ordinal));

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(8, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(9, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_IncompleteMemberAccessBeforeCall_PointsAtDot()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///member-dot-before-call.nl";

        var source = """
func main() {
    name := "Ada"
    name.()
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ExpectedToken && d.Message.Contains("Expected member name"));

        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(9, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.Contains("dot (.)", diagnostic.HumanExplanation);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidExpressionStatement ||
                 d.Message.Contains("<error>", System.StringComparison.Ordinal));

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(8, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(9, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnterminatedStringLiteral_PointsAtLiteralToken()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unterminated-string.nl";

        var source = """
func main() {
    name := "Ada
    print name
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidLiteral && d.Message.Contains("Unterminated string literal"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(4, diagnostic.Length);
        Assert.Contains("closing quote", diagnostic.HumanExplanation, System.StringComparison.OrdinalIgnoreCase);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(12, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(16, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnterminatedStringLiteral_WithEscapedQuote_PointsAtLiteralToken()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unterminated-string-escaped-quote.nl";

        var source = """
func main() {
    name := "Ada\"
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidLiteral && d.Message.Contains("Unterminated string literal"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(6, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(12, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(18, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnterminatedTripleQuoteStringLiteral_PointsAtOpeningDelimiter()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unterminated-triple-string.nl";

        var source = "func main() {\n    text := \"\"\"hello\nworld\n}\n";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidLiteral &&
                 d.Message.Contains("Unterminated triple-quoted string literal"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(3, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(12, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(15, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnterminatedInterpolatedRawStringLiteral_PointsAtOpeningDelimiter()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unterminated-raw-string.nl";

        var source = "func main() {\n    text := $\"\"\"hello {name}\n}\n";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidLiteral &&
                 d.Message.Contains("Unterminated interpolated raw string literal"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(4, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(12, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(16, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingClosingParen_PointsAtInsertionPosition()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-paren.nl";

        var source = """
func main() {
    print("hello"
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.MissingClosingParen && d.Message.Contains("Missing closing ')'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(18, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.Contains("closing ')'", diagnostic.HumanExplanation, System.StringComparison.OrdinalIgnoreCase);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(17, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(18, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnclosedEmptyCallArgumentList_PointsAtInsertionPosition()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-empty-call-paren.nl";

        var source = """
func main() {
    print(
    greeting.CompareTo("ter")
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.MissingClosingParen && d.Message.Contains("Missing closing ')'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(11, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnexpectedToken);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(10, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(11, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnclosedEmptyFunctionParameterList_PointsAtInsertionPosition()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-empty-parameter-paren.nl";

        var source = "func main(\n";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.MissingClosingParen && d.Message.Contains("Missing closing ')'"));

        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(11, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(10, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(11, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingParameterColon_UsesParameterNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-parameter-colon.nl";

        var source = "func greet(name string): string { return name }";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected ':' after parameter name"));

        AssertDiagnosticSpan(diagnostic, line: 1, column: 12, length: "name".Length);
        AssertLspRange(diagnostic, line0: 0, startCharacter: 11, endCharacter: 15);
        Assert.Contains("name: Type", diagnostic.ContextualHint);
    }

    [Fact]
    public void Diagnostics_MissingFieldColon_UsesFieldNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-field-colon.nl";

        var source = """
class User {
    Name string
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected ':' or ':=' after field name"));

        AssertDiagnosticSpan(diagnostic, line: 2, column: 5, length: "Name".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 4, endCharacter: 8);
        Assert.Contains("Name: Type", diagnostic.ContextualHint);
    }

    [Fact]
    public void Diagnostics_MissingFunctionReturnColon_UsesFunctionNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-function-return-colon.nl";

        var source = "func answer() int { return 1 }";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected ':' before return type"));

        AssertDiagnosticSpan(diagnostic, line: 1, column: 6, length: "answer".Length);
        AssertLspRange(diagnostic, line0: 0, startCharacter: 5, endCharacter: 11);
        Assert.Contains("func name(...): Type", diagnostic.ContextualHint);
    }

    [Fact]
    public void Diagnostics_DefaultParserSpan_UsesVisibleTokenSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unsupported-enum-backing-type.nl";

        var source = "enum Status: decimal { Open }";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.UnexpectedToken &&
                          diagnostic.Message.Contains("Unsupported enum backing type"));

        AssertDiagnosticSpan(diagnostic, line: 1, column: 14, length: "decimal".Length);
        AssertLspRange(diagnostic, line0: 0, startCharacter: 13, endCharacter: 20);
    }

    [Fact]
    public void Diagnostics_DefaultSemanticSpan_UsesVisibleTokenSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///explicit-var-type.nl";

        var source = """
func main(): int {
    let value: var = 42
    return value
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'var' is not a type"));

        AssertDiagnosticSpan(diagnostic, line: 2, column: 16, length: "var".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 15, endCharacter: 18);
    }

    [Fact]
    public void LinterDiagnostics_UnusedShorthandVariable_UsesVariableNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unused-shorthand-variable.nl";

        var source = """
func main() {
    asdf := "meow"
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.LinterDiagnostics ?? Enumerable.Empty<Diagnostic>(),
            diagnostic => diagnostic.Code == "NL001" &&
                          diagnostic.Message.Contains("asdf"));

        Assert.Equal(2, diagnostic.Location.Line);
        Assert.Equal(5, diagnostic.Location.Column);
        Assert.Equal("asdf".Length, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(8, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingInitializer_PointsAtVisibleAnchor()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-initializer.nl";

        var source = """
func main() {
    name :=
        greeting := "hi"
    print greeting
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ExpectedToken &&
                 d.Message.Contains("Expected an initializer expression after ':='"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(10, diagnostic.Column);
        Assert.Equal(":=".Length, diagnostic.Length);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnexpectedToken);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UndefinedVariable && d.Message.Contains("greeting"));
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnusedVariable && d.Message.Contains("name"));

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(9, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(11, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingKeywordsAndKeywordExpressions_UseVisibleKeywordSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-keyword-spans.nl";

        var source = """
func main() {
    foreach item items {
        print item
    }

    if {
        print "missing condition"
    }

    print
        value := 1
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var missingIn = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected 'in' between the loop variable and collection"));
        AssertDiagnosticSpan(missingIn, line: 2, column: 5, length: "foreach".Length);
        AssertLspRange(missingIn, line0: 1, startCharacter: 4, endCharacter: 11);

        var missingIfCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected a condition expression after 'if'"));
        AssertDiagnosticSpan(missingIfCondition, line: 6, column: 5, length: "if".Length);
        AssertLspRange(missingIfCondition, line0: 5, startCharacter: 4, endCharacter: 6);

        var missingPrintExpression = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected an expression to print after 'print'"));
        AssertDiagnosticSpan(missingPrintExpression, line: 10, column: 5, length: "print".Length);
        AssertLspRange(missingPrintExpression, line0: 9, startCharacter: 4, endCharacter: 9);
    }
}
