using System;
using System.IO;
using System.Linq;
using System.Reflection;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public partial class ILCompilerTests
{
    [Theory]
    [InlineData("Name", true)]
    [InlineData("name", false)]
    [InlineData("_Name", false)]
    [InlineData("1Name", false)]
    [InlineData("Éclair", true)]
    [InlineData("", false)]
    public void VisibilityConventions_IsExportedIdentifier_UsesFirstUtf16Char(string name, bool expected)
    {
        Assert.Equal(expected, VisibilityConventions.IsExportedIdentifier(name));
    }

    [Theory]
    [InlineData("name", Modifiers.Public, true)]
    [InlineData("Name", Modifiers.Internal, false)]
    [InlineData("Name", Modifiers.File, false)]
    [InlineData("Name", Modifiers.Protected, false)]
    [InlineData("Name", Modifiers.None, true)]
    [InlineData("name", Modifiers.None, false)]
    public void VisibilityConventions_IsExportedIdentifier_HonorsExplicitVisibilityEscapes(
        string name,
        Modifiers modifiers,
        bool expected)
    {
        Assert.Equal(expected, VisibilityConventions.IsExportedIdentifier(name, modifiers));
    }

    [Fact]
    public void CompilationStubEmitter_UsesCasingForTypesMembersTopLevelFunctionsAndStringEnumCases()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp_visibility_{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var sourcePath = Path.Combine(tempDir, "Visibility.nl");
            File.WriteAllText(sourcePath, """
class Exported {
    Visible: int
    hidden: int

    func Do(): int {
        return 1
    }

    func doIt(): int {
        return 2
    }
}

public class explicitlyPublicCamel {
    public func visibleByModifier(): int {
        return 3
    }
}

class unexported {
}

enum Labels: string {
    Good = "good",
    bad = "bad"
}

union Result {
    Ok { value: int }
    err { message: string }
}

func Helper(): int {
    return 1
}

func helper(): int {
    return 2
}
""");

            var stub = CompilationStubEmitter.Generate(
                new ProjectConfig { OutputType = "library" },
                new[] { sourcePath });

            Assert.Contains("public class Exported", stub);
            Assert.Contains("public class explicitlyPublicCamel", stub);
            Assert.Contains("internal class unexported", stub);
            Assert.Contains("public int Visible;", stub);
            Assert.Contains("internal int hidden;", stub);
            Assert.Contains("public int Do()", stub);
            Assert.Contains("public int visibleByModifier()", stub);
            Assert.Contains("internal int doIt()", stub);
            Assert.Contains("public const string Good", stub);
            Assert.Contains("internal const string bad", stub);
            Assert.Contains("public sealed class Ok", stub);
            Assert.Contains("private sealed class err", stub);
            Assert.Contains("public static int Helper()", stub);
            Assert.Contains("internal static int helper()", stub);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void Analyzer_ExportsCasingAndInteropVisibilityEscapesOnlyAcrossFileImports()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp_visibility_imports_{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var libraryPath = Path.Combine(tempDir, "Library.nl");
            File.WriteAllText(libraryPath, """
public class copiedPublicCamel {
}

private class CopiedPrivatePascal {
}

internal class InternalPascal {
}

class ExportedPascal {
}

class hiddenCamel {
}
""");

            var consumerPath = Path.Combine(tempDir, "Consumer.nl");
            var consumerSource = """
import "./Library.nl"

func UseCopiedPublic(publicValue: copiedPublicCamel): int {
    return 1
}

func UseCopiedPrivate(copiedValue: CopiedPrivatePascal): int {
    return 1
}

func UseExported(exportedValue: ExportedPascal): int {
    return 1
}
""";
            File.WriteAllText(consumerPath, consumerSource);

            var visibleResult = AnalyzeFile(consumerPath, tempDir, consumerSource);
            Assert.Empty(visibleResult.Errors);
            var copiedPublicType = Assert.IsType<ClassTypeInfo>(visibleResult.SemanticModel.Variables["publicValue"]);
            Assert.Equal("copiedPublicCamel", copiedPublicType.Declaration.Name);
            var copiedPrivateType = Assert.IsType<ClassTypeInfo>(visibleResult.SemanticModel.Variables["copiedValue"]);
            Assert.Equal("CopiedPrivatePascal", copiedPrivateType.Declaration.Name);
            var exportedType = Assert.IsType<ClassTypeInfo>(visibleResult.SemanticModel.Variables["exportedValue"]);
            Assert.Equal("ExportedPascal", exportedType.Declaration.Name);

            var blockedSource = """
import "./Library.nl"

func UseInternal(internalValue: InternalPascal): int {
    return 1
}

func UseHidden(hiddenValue: hiddenCamel): int {
    return 1
}
""";
            var blockedPath = Path.Combine(tempDir, "Blocked.nl");
            File.WriteAllText(blockedPath, blockedSource);

            var blockedResult = AnalyzeFile(blockedPath, tempDir, blockedSource);
            Assert.Empty(blockedResult.Errors);
            Assert.IsType<ExternalTypeInfo>(blockedResult.SemanticModel.Variables["internalValue"]);
            Assert.IsType<ExternalTypeInfo>(blockedResult.SemanticModel.Variables["hiddenValue"]);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void Analyzer_ProjectSymbolsUseSharedVisibilityConvention()
    {
        var source = """
public class copiedPublicCamel {
}

private class CopiedPrivatePascal {
}

internal class InternalPascal {
}

class ExportedPascal {
}

class hiddenCamel {
}
""";
        var unit = ParseCompilationUnit(source, "Project.nl");

        var symbols = Analyzer.ExtractProjectSymbols(unit, "Project.nl").ToDictionary(symbol => symbol.Name);

        Assert.True(symbols["CopiedPrivatePascal"].IsExported);
        Assert.True(symbols["ExportedPascal"].IsExported);
        Assert.True(symbols["copiedPublicCamel"].IsExported);
        Assert.False(symbols["InternalPascal"].IsExported);
        Assert.False(symbols["hiddenCamel"].IsExported);
    }

    [Fact]
    public void Analyzer_ProjectSymbolsPreferPackageOverNamespaceForScopeIdentity()
    {
        var source = """
namespace Legacy.Namespace

package ActualPackage

class ExportedPascal {
}
""";
        var unit = ParseCompilationUnit(source, "Project.nl");

        var symbol = Assert.Single(Analyzer.ExtractProjectSymbols(unit, "Project.nl"));

        Assert.Equal("ActualPackage", symbol.Namespace);
    }

    [Fact]
    public void ILCompiler_UsesCasingForTopLevelTypesMembersAndUnionCases()
    {
        var source = """
class Exported {
    Visible: int
    hidden: int

    func Do(): int {
        return 1
    }

    func doIt(): int {
        return 2
    }
}

public class explicitlyPublicCamel {
    public func visibleByModifier(): int {
        return 3
    }
}

class unexported {
}

enum Labels: string {
    Good = "good",
    bad = "bad"
}

union Result {
    Ok { value: int }
    err { message: string }
}
""";

        CompileAndInspect(source, new ProjectConfig { OutputType = "library" }, assembly =>
        {
            var exported = Assert.Single(assembly.GetTypes(), type => type.Name == "Exported");
            var explicitlyPublicCamel = Assert.Single(assembly.GetTypes(), type => type.Name == "explicitlyPublicCamel");
            var unexported = Assert.Single(assembly.GetTypes(), type => type.Name == "unexported");
            Assert.True(exported.IsPublic);
            Assert.True(explicitlyPublicCamel.IsPublic);
            Assert.False(unexported.IsPublic);

            Assert.True(exported.GetField("Visible", BindingFlags.Public | BindingFlags.Instance)!.IsPublic);
            Assert.True(exported.GetField("hidden", BindingFlags.NonPublic | BindingFlags.Instance)!.IsAssembly);
            Assert.True(exported.GetMethod("Do", BindingFlags.Public | BindingFlags.Instance)!.IsPublic);
            Assert.True(explicitlyPublicCamel.GetMethod("visibleByModifier", BindingFlags.Public | BindingFlags.Instance)!.IsPublic);
            Assert.True(exported.GetMethod("doIt", BindingFlags.NonPublic | BindingFlags.Instance)!.IsAssembly);

            var labels = Assert.Single(assembly.GetTypes(), type => type.Name == "Labels");
            Assert.True(labels.GetField("Good", BindingFlags.Public | BindingFlags.Static)!.IsPublic);
            Assert.True(labels.GetField("bad", BindingFlags.NonPublic | BindingFlags.Static)!.IsAssembly);

            var result = Assert.Single(assembly.GetTypes(), type => type.Name == "Result");
            Assert.NotNull(result.GetNestedType("Ok", BindingFlags.Public));
            var errCase = result.GetNestedType("err", BindingFlags.NonPublic);
            Assert.NotNull(errCase);
            Assert.True(errCase!.IsNestedPrivate);
            return 0;
        });
    }

    private static CompilationUnit ParseCompilationUnit(string source, string filePath)
    {
        var lexer = new Lexer(source, filePath);
        var parser = new Parser(lexer.Tokenize(), filePath, source);
        var parseResult = parser.ParseCompilationUnit();
        Assert.Empty(parseResult.Errors);
        return parseResult.CompilationUnit;
    }

    private static AnalysisResult AnalyzeFile(string filePath, string projectRoot, string source)
    {
        var unit = ParseCompilationUnit(source, filePath);
        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(unit, filePath, projectRoot, source);
    }
}
