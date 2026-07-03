using System.Reflection;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class ColumnarDeclarationScanTests
{
    [Fact]
    public void ColumnarCompiler_AcceptsTopLevelTypeAliasBeforeFunction()
    {
        Assert.True(ColumnarCompiler.TryEmitProgram(
            """
type TaskId = int

func Value(): int {
    return 42
}
""",
            "ColumnarTypeAliasDeclaration",
            "Program",
            out var assembly,
            out _,
            out _));

        using var scope = CollectibleAssemblyScope.Load(assembly);
        var type = scope.Assembly.GetType("Program");
        Assert.NotNull(type);
        var method = type.GetMethod("Value", BindingFlags.Public | BindingFlags.Static);
        Assert.NotNull(method);

        Assert.Equal(42, method.Invoke(null, null));
    }
}
