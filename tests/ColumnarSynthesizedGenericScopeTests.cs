using System;
using System.Linq;
using System.Reflection;
using NSharpLang.Compiler.Columnar;
using Xunit;

namespace NSharpLang.Tests;

public class ColumnarSynthesizedGenericScopeTests
{
    [Fact]
    public void ColumnarCompiler_DeclinesParentMethodGenericInStaticLambdaSignature()
    {
        Assert.False(ColumnarCompiler.TryEmitProgram(
            """
import System.Linq

func Filter<T>(items: T[]) {
    filtered := items.Where(item => true)
}
""",
            "ColumnarForeignMethodGenericLambdaSignature",
            "Program",
            out _,
            out _,
            out _));
    }

    [Fact]
    public void ColumnarCompiler_DeclinesParentMethodGenericInStaticLambdaBody()
    {
        Assert.False(ColumnarCompiler.TryEmitProgram(
            """
func Outer<T>(value: T): int {
    make: Func<int> = () => {
        values := new T[1]
        return values.Length
    }

    return make()
}
""",
            "ColumnarForeignMethodGenericLambda",
            "Program",
            out _,
            out _,
            out _));
    }

    [Fact]
    public void ColumnarCompiler_DeclinesParentMethodGenericInNongenericLocalFunctionBody()
    {
        Assert.False(ColumnarCompiler.TryEmitProgram(
            """
func Outer<T>(value: T): int {
    func make(): int {
        values := new T[1]
        return values.Length
    }

    return make()
}
""",
            "ColumnarForeignMethodGenericLocalFunction",
            "Program",
            out _,
            out _,
            out _));
    }

    [Fact]
    public void ColumnarCompiler_PreservesDeclaringTypeGenericInInstanceLambdaBody()
    {
        var emitted = ColumnarCompiler.TryEmitProgram(
            """
class Box<T> {
    Count: int

    func Allocate(): int {
        make: Func<int> = () => {
            values := new T[Count]
            return values.Length
        }

        return make()
    }
}

func Main(): int {
    return 0
}
""",
            "ColumnarOwnedTypeGenericLambda",
            "Program",
            out var assembly,
            out _,
            out _);
        var decline = string.Join(
            Environment.NewLine,
            ColumnarDeclineTrace.Snapshot().Select(reason => reason.SiteId + ": " + reason.Message));
        Assert.True(emitted, decline);

        using var scope = CollectibleAssemblyScope.Load(assembly);
        var boxDefinition = Assert.Single(
            scope.Assembly.GetTypes().Where(type => type.Name.StartsWith("Box", StringComparison.Ordinal)));
        var closedBox = boxDefinition.MakeGenericType(typeof(string));
        var instance = Activator.CreateInstance(closedBox);
        Assert.NotNull(instance);

        var count = closedBox.GetField("Count", BindingFlags.Public | BindingFlags.Instance);
        var allocate = closedBox.GetMethod("Allocate", BindingFlags.Public | BindingFlags.Instance);
        Assert.NotNull(count);
        Assert.NotNull(allocate);
        count.SetValue(instance, 3);

        Assert.Equal(
            3,
            Assert.IsType<int>(allocate.Invoke(instance, null)));
    }
}
