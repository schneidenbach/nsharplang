using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for `with` expression codegen on reference-type records.
///
/// A `with` expression on a reference type used to clone the target by emitting
/// <c>call object::MemberwiseClone()</c>. <c>MemberwiseClone</c> is <c>protected</c> (ECMA-335
/// family access), so calling it on an instance of <em>another</em> type (e.g. from a service
/// method that rewrites a record it holds) is an illegal access that <c>dotnet ilverify</c>
/// rejects with <c>[MethodAccess]</c>. This surfaced across IssueTracker, TaskCli, and
/// RecordsAndInterfaces.
///
/// The fix synthesizes a public <c>&lt;Clone&gt;$</c> method on each reference-type record whose
/// body calls <c>MemberwiseClone</c> on <c>this</c> (a verifiable family access from inside the
/// declaring type). `with` expressions invoke that public method, so cross-type cloning is
/// verifiable. These tests pin the IL shape so the defect cannot silently return when the
/// (separate) blocking <c>ilverify</c> CI gate is not run locally.
/// </summary>
public class WithExpressionCloneIlShapeTests
{
    private const string CloneMethodName = "<Clone>$";

    // A record updated via `with` from a *different* type (Service), reproducing the
    // cross-type protected-access violation that the fix eliminates.
    private const string Source = @"
record Item {
    Id: int
    Name: string
    Done: bool
}

class Service {
    func MarkDone(item: Item): Item {
        return item with { Done: true }
    }
}
";

    [Fact]
    public void ReferenceRecord_HasPublicCloneMethod()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var itemType = assembly.GetType("Item");
            Assert.NotNull(itemType);
            Assert.False(itemType!.IsValueType, "Item should be emitted as a reference type.");

            var clone = itemType.GetMethod(
                CloneMethodName,
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance,
                binder: null,
                types: System.Type.EmptyTypes,
                modifiers: null);

            Assert.NotNull(clone);
            Assert.True(clone!.IsPublic, "The synthesized record clone method must be public so `with` can call it across types.");
            Assert.Same(itemType, clone.ReturnType);

            // The clone body itself legally calls MemberwiseClone on `this` (family access
            // from inside the declaring type), so MemberwiseClone is expected *here*.
            var cloneCalls = CallTargetNames(clone);
            Assert.Contains(cloneCalls, name => name.Contains("MemberwiseClone", System.StringComparison.Ordinal));
            return 0;
        });
    }

    [Fact]
    public void WithExpression_CallsSynthesizedClone_NotProtectedMemberwiseClone()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var serviceType = assembly.GetType("Service");
            Assert.NotNull(serviceType);

            var markDone = serviceType!.GetMethod(
                "MarkDone",
                BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(markDone);

            var callTargets = CallTargetNames(markDone!);

            // The cross-type call site must route through the public clone method...
            Assert.Contains(callTargets, name => name.Contains(CloneMethodName, System.StringComparison.Ordinal));

            // ...and must NOT call the protected object.MemberwiseClone directly (the old,
            // unverifiable IL:MethodAccess shape).
            Assert.DoesNotContain(callTargets, name => name.Contains("MemberwiseClone", System.StringComparison.Ordinal));
            return 0;
        });
    }

    [Fact]
    public void WithExpression_ClonesAndUpdates_PreservingOtherFields()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var itemType = assembly.GetType("Item")!;
            var serviceType = assembly.GetType("Service")!;

            var original = System.Activator.CreateInstance(itemType)!;
            itemType.GetProperty("Id")!.SetValue(original, 7);
            itemType.GetProperty("Name")!.SetValue(original, "task");
            itemType.GetProperty("Done")!.SetValue(original, false);

            var service = System.Activator.CreateInstance(serviceType)!;
            var updated = serviceType.GetMethod("MarkDone")!.Invoke(service, new[] { original })!;

            // `with` produces a new instance...
            Assert.NotSame(original, updated);
            // ...with the target field updated...
            Assert.True((bool)itemType.GetProperty("Done")!.GetValue(updated)!);
            // ...and all other fields copied verbatim.
            Assert.Equal(7, (int)itemType.GetProperty("Id")!.GetValue(updated)!);
            Assert.Equal("task", (string)itemType.GetProperty("Name")!.GetValue(updated)!);
            // ...and the original left unmutated.
            Assert.False((bool)itemType.GetProperty("Done")!.GetValue(original)!);
            return 0;
        });
    }

    /// <summary>
    /// Returns the names of every method invoked via <c>call</c>/<c>callvirt</c> inside
    /// <paramref name="method"/>, qualified as <c>DeclaringType.MethodName</c> where resolvable.
    /// </summary>
    private static List<string> CallTargetNames(MethodInfo method)
    {
        var module = method.Module;
        var targets = new List<string>();
        foreach (var instruction in ILShapeInspector.Decode(method))
        {
            if (instruction.OpCode != OpCodes.Call && instruction.OpCode != OpCodes.Callvirt)
            {
                continue;
            }

            if (instruction.MetadataToken is not { } token)
            {
                continue;
            }

            MethodBase? resolved;
            try
            {
                resolved = module.ResolveMethod(token);
            }
            catch (System.ArgumentException)
            {
                continue;
            }

            if (resolved is not null)
            {
                var declaring = resolved.DeclaringType?.FullName ?? resolved.DeclaringType?.Name ?? "<unknown>";
                targets.Add($"{declaring}.{resolved.Name}");
            }
        }

        return targets;
    }
}
