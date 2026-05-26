using System;
using System.Linq;
using NSharpLang.Playground;
using Xunit;

namespace NSharpLang.Tests;

public sealed class PlaygroundCompilerTests
{
    [Fact]
    public void Catalog_StatesBrowserCapabilitiesAndExamples()
    {
        var catalog = new PlaygroundCompiler().GetCatalog();

        Assert.Equal(2, catalog.SchemaVersion);
        Assert.True(catalog.Capabilities.RunsInBrowser);
        Assert.True(catalog.Capabilities.SupportsDiagnostics);
        Assert.True(catalog.Capabilities.SupportsFormatting);
        Assert.True(catalog.Capabilities.SupportsCompletions);
        Assert.True(catalog.Capabilities.SupportsHover);
        Assert.True(catalog.Capabilities.SupportsSyntaxHighlighting);
        Assert.True(catalog.Capabilities.SupportsExecution);
        Assert.Contains(catalog.Examples, example => example.Id == "05-duck-typing");
        Assert.Contains(catalog.Examples, example => example.ExpectedOutput != null);
        Assert.NotEmpty(catalog.Tutorial);
        Assert.True(catalog.EstimatedMinutes >= 15);
    }

    [Fact]
    public void Catalog_TutorialReferencesKnownExamplesAndExerciseValidation()
    {
        var catalog = new PlaygroundCompiler().GetCatalog();
        var exampleIds = catalog.Examples.Select(example => example.Id).ToHashSet();

        Assert.Contains(catalog.Tutorial, step => step.Kind == "info" && step.Validation == null);
        Assert.Contains(catalog.Tutorial, step => step.Kind == "exercise" && step.Validation != null);
        Assert.All(catalog.Tutorial.Where(step => step.ExampleId != null), step =>
            Assert.Contains(step.ExampleId!, exampleIds));
        Assert.All(catalog.Tutorial.Where(step => step.Kind == "exercise"), step =>
        {
            Assert.NotNull(step.Validation);
            Assert.Equal("output", step.Validation!.Type);
            Assert.False(string.IsNullOrWhiteSpace(step.Validation.ExpectedOutput));
            Assert.False(string.IsNullOrWhiteSpace(step.Validation.SuccessMessage));
        });
    }

    [Fact]
    public void Catalog_ExamplesAreCompilerClean()
    {
        var compiler = new PlaygroundCompiler();

        foreach (var example in PlaygroundExamples.All)
        {
            var result = compiler.CheckProject(
                [
                    new PlaygroundFile("Program.nl", example.Code),
                    new PlaygroundFile("Program.tests.nl", example.TestsCode ?? string.Empty)
                ],
                "Program.nl");

            Assert.True(
                result.Ok,
                $"{example.Id}: {string.Join("; ", result.Diagnostics.Select(diagnostic => $"{diagnostic.Code} {diagnostic.Message}"))}");
        }
    }

    [Fact]
    public void Check_ValidProgram_HasNoErrors()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                message := "Hello"
                print message
            }
            """);

        Assert.True(result.Ok);
        Assert.Equal(0, result.Summary.Errors);
        Assert.Equal(2, result.SchemaVersion);
    }

    [Fact]
    public void Check_InvalidProgram_ReturnsCompilerDiagnostic()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                total := 42
                print totla
            }
            """);

        Assert.False(result.Ok);
        Assert.Contains(result.Diagnostics, diagnostic =>
            diagnostic.Code == "NL301" &&
            diagnostic.Severity == "error" &&
            diagnostic.Message.Contains("totla"));
    }

    [Fact]
    public void Format_ValidProgram_ReturnsFormattedCode()
    {
        var result = new PlaygroundCompiler().Format("func main(){print 5}");

        Assert.True(result.Ok);
        Assert.Equal("""
            func main() {
                print 5
            }

            """.Replace("\r\n", "\n"), result.FormattedCode);
        Assert.Equal(0, result.Summary.Errors);
    }

    [Fact]
    public void Check_OversizedProgram_ReturnsBoundedError()
    {
        var result = new PlaygroundCompiler().Check(new string('x', PlaygroundCompiler.MaxSourceLength + 1));

        Assert.False(result.Ok);
        Assert.Contains(result.Diagnostics, diagnostic => diagnostic.Code == "PG001");
    }

    [Fact]
    public void Diagnostics_AreDeduplicated()
    {
        var result = new PlaygroundCompiler().Check("""
            public func main() {
                print missing
            }
            """);

        var duplicates = result.Diagnostics
            .GroupBy(diagnostic => new { diagnostic.Code, diagnostic.Line, diagnostic.Column, diagnostic.Message })
            .Where(group => group.Count() > 1)
            .ToArray();

        Assert.Empty(duplicates);
    }

    [Fact]
    public void Complete_ReturnsKeywordAndSemanticCompletions()
    {
        var result = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", """
                package Playground

                func Add(a: int, b: int): int {
                    return a + b
                }

                func main() {
                    value := Add(1, 2)
                    pri
                }
                """)],
            "Program.nl",
            9,
            7);

        Assert.Contains(result.Items, item => item.Label == "print");
        Assert.Contains(result.Items, item => item.Label == "Add");
    }

    [Fact]
    public void Complete_MemberAccess_ReturnsSourceDefinedMethodsAndProperties()
    {
        const string source = """
            package Playground

            record Todo {
                Id: int
                Title: string
                Done: bool
            }

            class TodoFormatter(prefix: string) {
                func Format(todo: Todo): string {
                    return $"{prefix} #{todo.Id}: {todo.Title}"
                }
            }

            func main() {
                todo := new Todo { Id: 1, Title: "Try N#", Done: false }
                formatter := new TodoFormatter("task")
                print formatter.Format(todo)
                print todo.Id
            }
            """;

        var formatterLine = LineNumberContaining(source, "formatter.Format");
        var formatterResult = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", source)],
            "Program.nl",
            formatterLine,
            ColumnAfter(source, formatterLine, "formatter."));

        var format = Assert.Single(formatterResult.Items.Where(item => item.Label == "Format"));
        Assert.Equal("method", format.Kind);
        Assert.Contains("Todo", format.Detail);
        Assert.Contains("string", format.Detail);

        var todoLine = LineNumberContaining(source, "todo.Id");
        var todoResult = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", source)],
            "Program.nl",
            todoLine,
            ColumnAfter(source, todoLine, "todo."));

        AssertCompletion(todoResult, "Id", "int");
        AssertCompletion(todoResult, "Title", "string");
        AssertCompletion(todoResult, "Done", "bool");
    }

    [Fact]
    public void Complete_MemberAccess_WorksAfterJustTypedDot()
    {
        const string source = """
            package Playground

            class TodoFormatter {
                func Format(): string {
                    return "ok"
                }
            }

            func main() {
                formatter := new TodoFormatter()
                formatter.
            }
            """;

        var line = LineNumberContaining(source, "formatter.");
        var result = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", source)],
            "Program.nl",
            line,
            ColumnAfter(source, line, "formatter."));

        Assert.Contains(result.Items, item => item.Label == "Format" && item.Kind == "method");
    }

    [Fact]
    public void Complete_MemberAccess_ReturnsClrStaticInstanceAndChainedMembers()
    {
        const string source = """
            import System

            package Playground

            func main() {
                message := "hello"
                Console.WriteLine(message)
                print Math.Max(1, 2)
                print message.ToUpper().ToLower()
            }
            """;

        var compiler = new PlaygroundCompiler();
        var files = new[] { new PlaygroundFile("Program.nl", source) };

        var messageLine = LineNumberContaining(source, "message.ToUpper");
        var messageResult = compiler.Complete(files, "Program.nl", messageLine, ColumnAfter(source, messageLine, "message."));
        Assert.Contains(messageResult.Items, item => item.Label == "ToUpper" && item.Kind == "method");
        Assert.Contains(messageResult.Items, item => item.Label == "Contains" && item.Kind == "method");

        var consoleLine = LineNumberContaining(source, "Console.WriteLine");
        var consoleResult = compiler.Complete(files, "Program.nl", consoleLine, ColumnAfter(source, consoleLine, "Console."));
        Assert.Contains(consoleResult.Items, item => item.Label == "WriteLine" && item.Kind == "method");

        var mathLine = LineNumberContaining(source, "Math.Max");
        var mathResult = compiler.Complete(files, "Program.nl", mathLine, ColumnAfter(source, mathLine, "Math."));
        Assert.Contains(mathResult.Items, item => item.Label == "Max" && item.Kind == "method");

        var chainedResult = compiler.Complete(files, "Program.nl", messageLine, ColumnAfter(source, messageLine, "ToUpper()."));
        Assert.Contains(chainedResult.Items, item => item.Label == "ToLower" && item.Kind == "method");
        Assert.Contains(chainedResult.Items, item => item.Label == "Length");
    }

    [Fact]
    public void RunProject_ValidProgram_ProducesStdout()
    {
        var example = PlaygroundExamples.All.First(example => example.Id == "01-hello-world");
        var result = new PlaygroundCompiler().RunProject(
            [new PlaygroundFile("Program.nl", example.Code)],
            "Program.nl");

        Assert.True(result.Ok);
        Assert.Equal(0, result.ExitCode);
        Assert.Equal(example.ExpectedOutput, result.Stdout);
        Assert.Equal(2, result.SchemaVersion);
        Assert.Null(result.UnsupportedReason);
    }

    [Fact]
    public void RunProject_InvalidProgram_SkipsExecution()
    {
        var result = new PlaygroundCompiler().RunProject(
            [new PlaygroundFile("Program.nl", """
                package Playground

                func main() {
                    print missing
                }
                """)],
            "Program.nl");

        Assert.False(result.Ok);
        Assert.Equal(1, result.ExitCode);
        Assert.Contains(result.Diagnostics, diagnostic => diagnostic.Code == "NL301");
        Assert.Contains("compiler errors", result.Stderr);
    }

    [Fact]
    public void RunProject_UnsupportedConstruct_ReturnsPG2xxDiagnostic()
    {
        var result = new PlaygroundCompiler().RunProject(
            [new PlaygroundFile("Program.nl", """
                package Playground

                func main() {
                    while false {
                        print "not reached"
                    }
                }
                """)],
            "Program.nl");

        Assert.False(result.Ok);
        Assert.Equal(2, result.ExitCode);
        Assert.NotNull(result.UnsupportedReason);
        Assert.Contains(result.Diagnostics, diagnostic => diagnostic.Code.StartsWith("PG2"));
    }

    [Fact]
    public void Hover_ReturnsInformationForPrimitiveKeywordFallback()
    {
        var result = new PlaygroundCompiler().Hover(
            [new PlaygroundFile("Program.nl", """
                package Playground

                func main() {
                    name: string = "N#"
                    print name
                }
                """)],
            "Program.nl",
            4,
            11);

        Assert.True(result.Ok);
        Assert.NotNull(result.Hover);
        Assert.Contains("string", result.Hover!.Signature);
    }

    [Fact]
    public void CheckProject_AcceptsTutorialProgramAndTestsFiles()
    {
        var lesson = PlaygroundExamples.All.First(example => example.HasTests);
        var result = new PlaygroundCompiler().CheckProject(
            [
                new PlaygroundFile("Program.nl", lesson.Code),
                new PlaygroundFile("Program.tests.nl", lesson.TestsCode!)
            ],
            "Program.nl");

        Assert.Equal(2, result.SchemaVersion);
        Assert.DoesNotContain(result.Diagnostics, diagnostic => diagnostic.Code == "PG900");
    }

    private static int LineNumberContaining(string source, string text)
    {
        var lines = source.Split('\n');
        for (var index = 0; index < lines.Length; index++)
        {
            if (lines[index].Contains(text))
            {
                return index + 1;
            }
        }

        throw new Xunit.Sdk.XunitException($"Could not find line containing '{text}'.");
    }

    private static int ColumnAfter(string source, int line, string text)
    {
        var lineText = source.Split('\n')[line - 1];
        var index = lineText.IndexOf(text, StringComparison.Ordinal);
        if (index < 0)
        {
            throw new Xunit.Sdk.XunitException($"Could not find '{text}' on line {line}.");
        }

        return index + text.Length;
    }

    private static void AssertCompletion(PlaygroundCompletionResponse result, string label, string detail)
    {
        var completion = Assert.Single(result.Items.Where(item => item.Label == label));
        Assert.Contains(detail, completion.Detail);
    }
}
