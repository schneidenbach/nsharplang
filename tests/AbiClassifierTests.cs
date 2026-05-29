using System.Linq;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests;

public class AbiClassifierTests
{
    private static CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        Assert.NotNull(result.CompilationUnit);
        return result.CompilationUnit!;
    }

    private static AbiClassifier ClassifyFromSource(string source, string file = "test.nl")
    {
        var unit = Parse(source);
        return new AbiClassifier(file).Classify(unit);
    }

    private static AbiClassification FindByName(AbiClassifier classifier, string name)
    {
        var matches = classifier.Classifications.Values.Where(c => c.Name == name).ToList();
        Assert.True(matches.Count == 1, $"Expected exactly one declaration named '{name}', found {matches.Count}.");
        return matches[0];
    }

    [Fact]
    public void PascalCaseType_IsClrPublic()
    {
        var classifier = ClassifyFromSource("""
            class Widget {
            }
            """);

        Assert.Equal(AbiBoundary.ClrPublic, FindByName(classifier, "Widget").Boundary);
    }

    [Fact]
    public void ExplicitInternalType_IsClrInternal()
    {
        var classifier = ClassifyFromSource("""
            internal class Gadget {
            }
            """);

        Assert.Equal(AbiBoundary.ClrInternal, FindByName(classifier, "Gadget").Boundary);
    }

    [Fact]
    public void CamelCaseTopLevelType_IsFilePrivate()
    {
        var classifier = ClassifyFromSource("""
            class helper {
            }
            """);

        Assert.Equal(AbiBoundary.FilePrivate, FindByName(classifier, "helper").Boundary);
    }

    [Fact]
    public void FileModifierType_IsFilePrivate()
    {
        var classifier = ClassifyFromSource("""
            file class Internals {
            }
            """);

        Assert.Equal(AbiBoundary.FilePrivate, FindByName(classifier, "Internals").Boundary);
    }

    [Fact]
    public void PascalCaseTopLevelFunction_IsClrPublic()
    {
        var classifier = ClassifyFromSource("""
            func Compute(): int {
                return 1
            }
            """);

        Assert.Equal(AbiBoundary.ClrPublic, FindByName(classifier, "Compute").Boundary);
    }

    [Fact]
    public void CamelCaseTopLevelFunction_IsFilePrivate()
    {
        var classifier = ClassifyFromSource("""
            func compute(): int {
                return 1
            }
            """);

        Assert.Equal(AbiBoundary.FilePrivate, FindByName(classifier, "compute").Boundary);
    }

    [Fact]
    public void LocalFunction_IsLocal()
    {
        var classifier = ClassifyFromSource("""
            func Outer(): int {
                func inner(): int {
                    return 2
                }
                return inner()
            }
            """);

        Assert.Equal(AbiBoundary.ClrPublic, FindByName(classifier, "Outer").Boundary);
        Assert.Equal(AbiBoundary.Local, FindByName(classifier, "inner").Boundary);
    }

    [Fact]
    public void LocalFunctionInsideControlFlow_IsLocal()
    {
        var classifier = ClassifyFromSource("""
            func Outer(): int {
                if true {
                    func nested(): int {
                        return 7
                    }
                    return nested()
                }
                return 0
            }
            """);

        // Local functions nested inside control-flow blocks must still be found.
        Assert.Equal(AbiBoundary.Local, FindByName(classifier, "nested").Boundary);
    }

    [Fact]
    public void CamelCaseMember_IsClrInternal()
    {
        var classifier = ClassifyFromSource("""
            class Widget {
                func helper(): int {
                    return 3
                }
            }
            """);

        // Members default to assembly-internal when unexported (they remain
        // assembly-visible so same-project N# calls work).
        Assert.Equal(AbiBoundary.ClrInternal, FindByName(classifier, "helper").Boundary);
    }

    [Fact]
    public void PublicMember_IsClrPublic()
    {
        var classifier = ClassifyFromSource("""
            class Widget {
                func Helper(): int {
                    return 3
                }
            }
            """);

        Assert.Equal(AbiBoundary.ClrPublic, FindByName(classifier, "Helper").Boundary);
    }

    [Fact]
    public void TryGet_ResolvesBySourcePosition()
    {
        var unit = Parse("""
            class Widget {
            }
            """);
        var classifier = new AbiClassifier("test.nl").Classify(unit);

        var widget = unit.Declarations.OfType<ClassDeclaration>().Single();
        Assert.True(classifier.TryGet(widget.Line, widget.Column, out var classification));
        Assert.Equal("Widget", classification.Name);
        Assert.Equal(AbiBoundary.ClrPublic, classification.Boundary);

        Assert.Equal(AbiBoundary.ClrPublic, classifier.GetBoundary(widget.Line, widget.Column));
        Assert.Null(classifier.GetBoundary(9999, 9999));
    }

    [Fact]
    public void ExplicitPrivatePascalCaseMember_IsClrInternal()
    {
        var classifier = ClassifyFromSource("""
            internal class Container {
                private func Secret(): int {
                    return 4
                }
            }
            """);

        // Explicit private overrides PascalCase export convention, hiding the
        // member from the public CLR surface.
        Assert.Equal(AbiBoundary.ClrInternal, FindByName(classifier, "Secret").Boundary);
    }
}
