using System.Reflection;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for value-type (struct) constructor codegen. A struct constructor must NOT
/// chain to a base constructor: for a struct, <c>ldarg.0</c> loads the managed address of
/// <c>this</c> (<c>&amp;T</c>), so emitting <c>call object::.ctor(object)</c> produces type-unsafe IL
/// that <c>dotnet ilverify</c> rejects with
/// <c>[StackUnexpected] found address of 'T', expected ref 'object'</c>. Roslyn emits no base call
/// for struct constructors. These tests pin the IL shape so the defect cannot silently return when
/// the (separate) blocking <c>ilverify</c> CI gate is not run locally.
/// </summary>
public class StructConstructorIlShapeTests
{
    private const string StructSource = @"
struct Point {
    x: int
    y: int

    constructor(px: int, py: int) {
        x = px
        y = py
    }
}
";

    private const string ClassSource = @"
class Box {
    value: int

    constructor(v: int) {
        value = v
    }
}
";

    [Fact]
    public void StructConstructor_DoesNotChainToBaseConstructor()
    {
        ILShapeInspector.Compile(StructSource, assembly =>
        {
            var pointType = assembly.GetType("Point");
            Assert.NotNull(pointType);
            Assert.True(pointType!.IsValueType, "Point should be emitted as a value type.");

            var ctor = pointType.GetConstructor(new[] { typeof(int), typeof(int) });
            Assert.NotNull(ctor);

            // The struct ctor must contain no constructor-targeting call (no object/ValueType chaining).
            var chainedCtors = ConstructorCallTargets(ctor!);
            Assert.True(
                chainedCtors.Count == 0,
                $"Struct constructor must not chain to a base constructor, but called: {string.Join(", ", chainedCtors)}");

            // Sanity: the body must still assign both fields (behaviour preserved).
            Assert.Equal(2, ILShapeInspector.CountOpcode(ctor!, System.Reflection.Emit.OpCodes.Stfld));
            return 0;
        });
    }

    [Fact]
    public void ClassConstructor_StillChainsToObjectConstructor()
    {
        // Asymmetry guard: removing the base call for structs must not remove it for classes,
        // which legitimately require an object::.ctor chain.
        ILShapeInspector.Compile(ClassSource, assembly =>
        {
            var boxType = assembly.GetType("Box");
            Assert.NotNull(boxType);
            Assert.False(boxType!.IsValueType, "Box should be emitted as a reference type.");

            var ctor = boxType.GetConstructor(new[] { typeof(int) });
            Assert.NotNull(ctor);

            var chainedCtors = ConstructorCallTargets(ctor!);
            Assert.Contains(chainedCtors, name => name.Contains("System.Object", System.StringComparison.Ordinal));
            return 0;
        });
    }

    /// <summary>
    /// Returns the declaring-type-qualified names of every constructor invoked via <c>call</c>/<c>callvirt</c>
    /// inside <paramref name="method"/> (i.e. base-constructor chaining targets).
    /// </summary>
    private static System.Collections.Generic.List<string> ConstructorCallTargets(ConstructorInfo method)
    {
        var module = method.Module;
        var targets = new System.Collections.Generic.List<string>();
        foreach (var instruction in ILShapeInspector.Decode(method))
        {
            if (instruction.OpCode != System.Reflection.Emit.OpCodes.Call &&
                instruction.OpCode != System.Reflection.Emit.OpCodes.Callvirt)
            {
                continue;
            }

            if (instruction.MetadataToken is not { } token)
            {
                continue;
            }

            ConstructorInfo? resolved;
            try
            {
                resolved = module.ResolveMethod(token) as ConstructorInfo;
            }
            catch (System.ArgumentException)
            {
                continue;
            }

            if (resolved is not null)
            {
                targets.Add(resolved.DeclaringType?.FullName ?? resolved.DeclaringType?.Name ?? "<unknown>");
            }
        }

        return targets;
    }
}
