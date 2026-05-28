using System;
using System.Reflection;
using NSharpLang.Cli.Commands;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Unit tests for the IL-shape decoder behind <c>nlc bench --explain</c>.
/// Each sample method below has a hand-known IL shape so we can assert that the
/// opcode decoder tallies <c>newobj</c>, <c>box</c>, <c>callvirt</c> vs <c>call</c>,
/// and delegate constructions without running BenchmarkDotNet.
/// </summary>
public class BenchIlShapeTests
{
    // Sample methods. They are intentionally not optimized away by being public and
    // returning values; the decoder reads the *debug* IL of this test assembly.

    public static int Empty() => 0;

    public static object BoxesAnInt()
    {
        // `box` is emitted when a value type is converted to object.
        object o = 42;
        return o;
    }

    public static int CallsStaticAndVirtual(object value)
    {
        // string.Concat(...) is a direct static `call`; GetHashCode() dispatched on
        // an `object` reference is a virtual `callvirt`.
        _ = string.Concat("v=", "x");
        return value.GetHashCode();
    }

    public static Action ConstructsDelegate()
    {
        // Capturing a method group into an Action emits ldftn + newobj on the
        // Action(object, IntPtr) constructor, which derives from System.Delegate.
        return Empty2;
    }

    private static void Empty2()
    {
    }

    private static IlShapeSummaryProbe Probe(string name)
    {
        var method = typeof(BenchIlShapeTests).GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
        var shape = BenchCommand.ComputeIlShape(method);
        Assert.NotNull(shape);
        return new IlShapeSummaryProbe(
            shape!.IlBytes,
            shape.Newobj,
            shape.Box,
            shape.Callvirt,
            shape.Call,
            shape.DelegateCtors);
    }

    private readonly record struct IlShapeSummaryProbe(
        int IlBytes,
        int Newobj,
        int Box,
        int Callvirt,
        int Call,
        int DelegateCtors);

    [Fact]
    public void EmptyMethod_HasNoInterestingOpcodes()
    {
        var shape = Probe(nameof(Empty));
        Assert.True(shape.IlBytes > 0);
        Assert.Equal(0, shape.Newobj);
        Assert.Equal(0, shape.Box);
        Assert.Equal(0, shape.Callvirt);
        Assert.Equal(0, shape.DelegateCtors);
    }

    [Fact]
    public void BoxingMethod_CountsBox()
    {
        var shape = Probe(nameof(BoxesAnInt));
        Assert.Equal(1, shape.Box);
        Assert.Equal(0, shape.Newobj);
    }

    [Fact]
    public void CallSite_DistinguishesCallFromCallvirt()
    {
        var shape = Probe(nameof(CallsStaticAndVirtual));
        // string.Concat is a direct static call; ToString on the int is a callvirt.
        Assert.True(shape.Call >= 1);
        Assert.True(shape.Callvirt >= 1);
    }

    [Fact]
    public void DelegateConstruction_IsCountedAsDelegateCtor()
    {
        var shape = Probe(nameof(ConstructsDelegate));
        Assert.Equal(1, shape.Newobj);
        Assert.Equal(1, shape.DelegateCtors);
    }

    [Fact]
    public void AbstractMethod_HasNoManagedBody_ReturnsNull()
    {
        // Object.ToString has a body, but an interface/abstract method does not.
        var method = typeof(System.Collections.IEnumerable)
            .GetMethod(nameof(System.Collections.IEnumerable.GetEnumerator))!;
        Assert.Null(BenchCommand.ComputeIlShape(method));
    }
}
