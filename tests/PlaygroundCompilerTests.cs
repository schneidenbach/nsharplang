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

        Assert.Equal(1, catalog.SchemaVersion);
        Assert.True(catalog.Capabilities.RunsInBrowser);
        Assert.True(catalog.Capabilities.SupportsDiagnostics);
        Assert.True(catalog.Capabilities.SupportsFormatting);
        Assert.True(catalog.Capabilities.SupportsCompletions);
        Assert.True(catalog.Capabilities.SupportsHover);
        Assert.True(catalog.Capabilities.SupportsSyntaxHighlighting);
        Assert.False(catalog.Capabilities.SupportsExecution);
        Assert.Contains(catalog.Examples, example => example.Id == "05-duck-typing");
        Assert.True(catalog.EstimatedMinutes >= 15);
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
        Assert.Equal(1, result.SchemaVersion);
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

        Assert.Equal(1, result.SchemaVersion);
        Assert.DoesNotContain(result.Diagnostics, diagnostic => diagnostic.Code == "PG900");
    }
}
