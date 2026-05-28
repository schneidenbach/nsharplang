using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Unit tests for <see cref="UnionValueLayout"/>, the pure-analysis pass that decides
/// whether a union may be lowered to an allocation-free value-struct representation.
/// </summary>
public class UnionValueLayoutTests
{
    private static UnionDeclaration Union(string name, params UnionCase[] cases)
        => new(name, cases.ToList(), Modifiers.None, new List<AttributeNode>(), 1, 1);

    private static UnionCase Case(string name)
        => new(name, Properties: null);

    private static UnionCase CaseWith(string name, params (string Name, string Type)[] properties)
        => new(name, properties.Select(p => new UnionCaseProperty(p.Name, new SimpleTypeReference(p.Type))).ToList());

    [Fact]
    public void PayloadFreeSmallUnion_IsValueStruct()
    {
        var union = Union("Color", Case("Red"), Case("Green"), Case("Blue"));

        var decision = UnionValueLayout.Classify(union);

        Assert.True(decision.IsValueStruct);
        Assert.True(UnionValueLayout.IsValueStructEmittable(union));
    }

    [Fact]
    public void PayloadCarryingUnion_IsEligibleButNotYetEmittable()
    {
        var union = Union(
            "Result",
            CaseWith("Success", ("value", "int")),
            CaseWith("Failure", ("error", "string")));

        var decision = UnionValueLayout.Classify(union);

        // Value-friendly payloads keep the union eligible in principle...
        Assert.True(decision.IsValueStruct);
        // ...but the initial emitter slice only lowers payload-free unions.
        Assert.True(UnionValueLayout.HasPayloads(union));
        Assert.False(UnionValueLayout.IsValueStructEmittable(union));
    }

    [Fact]
    public void EmptyUnion_StaysClassHierarchy()
    {
        var union = Union("Empty");

        var decision = UnionValueLayout.Classify(union);

        Assert.Equal(UnionLayoutKind.ClassHierarchy, decision.Layout);
        Assert.False(UnionValueLayout.IsValueStructEmittable(union));
    }

    [Fact]
    public void TooManyCases_StaysClassHierarchy()
    {
        var cases = Enumerable.Range(0, UnionValueLayout.MaxValueStructCases + 1)
            .Select(i => Case($"Case{i}"))
            .ToArray();
        var union = Union("Big", cases);

        var decision = UnionValueLayout.Classify(union);

        Assert.Equal(UnionLayoutKind.ClassHierarchy, decision.Layout);
        Assert.Contains("cases", decision.Reason);
    }

    [Fact]
    public void AtMaxCases_IsStillValueStruct()
    {
        var cases = Enumerable.Range(0, UnionValueLayout.MaxValueStructCases)
            .Select(i => Case($"Case{i}"))
            .ToArray();
        var union = Union("EdgeMax", cases);

        Assert.True(UnionValueLayout.Classify(union).IsValueStruct);
    }

    [Fact]
    public void NullUnion_StaysClassHierarchy()
    {
        var decision = UnionValueLayout.Classify(null!);

        Assert.Equal(UnionLayoutKind.ClassHierarchy, decision.Layout);
        Assert.False(UnionValueLayout.IsValueStructEmittable(null!));
    }
}
