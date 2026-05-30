using System;
using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Unit tests for <see cref="StructCopyAnalysis"/>, the pure heuristic behind struct-copy
/// elimination. The emitter-level effects are covered by the IL-shape tests; these pin the
/// decision boundaries (readonly, size, kind) directly.
/// </summary>
public class StructCopyAnalysisTests
{
    private readonly record struct SmallReadonly(int X, int Y);

    private readonly record struct LargeReadonly(double A, double B, double C, double D);

    private struct LargeMutable
    {
        public double A;
        public double B;
        public double C;
        public double D;
    }

    private ref struct LargeRefStruct
    {
        public double A;
        public double B;
        public double C;
        public double D;
    }

    [Fact]
    public void LargeReadonlyStruct_PassesByReadOnlyReference()
    {
        Assert.True(StructCopyAnalysis.ShouldPassByReadOnlyReference(typeof(LargeReadonly)));
    }

    [Fact]
    public void SmallReadonlyStruct_StaysByValue()
    {
        Assert.False(StructCopyAnalysis.ShouldPassByReadOnlyReference(typeof(SmallReadonly)));
    }

    [Fact]
    public void LargeMutableStruct_StaysByValue()
    {
        // A mutable struct passed by `in` would force defensive copies; never lower it.
        Assert.False(StructCopyAnalysis.ShouldPassByReadOnlyReference(typeof(LargeMutable)));
    }

    [Fact]
    public void RefStruct_StaysByValue()
    {
        Assert.False(StructCopyAnalysis.ShouldPassByReadOnlyReference(typeof(LargeRefStruct)));
    }

    [Theory]
    [InlineData(typeof(int))]
    [InlineData(typeof(double))]
    [InlineData(typeof(DayOfWeek))]
    [InlineData(typeof(string))]
    [InlineData(typeof(object))]
    public void PrimitivesEnumsAndReferences_StayByValue(Type type)
    {
        Assert.False(StructCopyAnalysis.ShouldPassByReadOnlyReference(type));
    }

    [Fact]
    public void Nullable_StaysByValue()
    {
        Assert.False(StructCopyAnalysis.ShouldPassByReadOnlyReference(typeof(LargeReadonly?)));
    }

    [Fact]
    public void ByRefType_StaysByValue()
    {
        Assert.False(StructCopyAnalysis.ShouldPassByReadOnlyReference(typeof(LargeReadonly).MakeByRefType()));
    }
}
