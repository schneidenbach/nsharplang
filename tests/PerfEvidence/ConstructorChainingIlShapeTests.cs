using System.Collections.Generic;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for reference-type constructor-chaining codegen (the
/// <c>: this(...)</c> / <c>: base(...)</c> initializer clause).
///
/// The defect: <c>EmitConstructorBody</c> ignored the declared initializer and always emitted a
/// hardcoded <c>call object::.ctor()</c>. For a derived class this is doubly wrong and produces
/// unverifiable IL: ilverify rejects it with <c>[CallCtor]</c> (the call must target the *direct*
/// base constructor, not <c>object</c>) and <c>[ThisUninitReturn]</c> (because <c>this</c> is never
/// initialized through the proper chain, returning leaves it uninitialized). A <c>this(...)</c>
/// initializer must instead delegate to a sibling constructor (which runs the base chain + field
/// initializers exactly once), and a <c>base(...)</c> initializer must call the matching base ctor.
///
/// These tests pin the IL shape so the defect cannot silently return when the (separate) blocking
/// <c>ilverify</c> CI gate is not run locally.
/// </summary>
public class ConstructorChainingIlShapeTests
{
    private const string Source = @"
class Person {
    readonly Name: string
    readonly Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    constructor(name: string): this(name, 0) {
    }
}

class Employee: Person {
    readonly Department: string

    constructor(name: string, age: int, dept: string): base(name, age) {
        Department = dept
    }

    constructor(name: string, dept: string): this(name, 0, dept) {
    }
}
";

    [Fact]
    public void BaseInitializer_CallsDirectBaseConstructor_NotObject()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var employeeType = assembly.GetType("Employee");
            Assert.NotNull(employeeType);
            var personType = assembly.GetType("Person");
            Assert.NotNull(personType);

            var ctor = employeeType!.GetConstructor(new[] { typeof(string), typeof(int), typeof(string) });
            Assert.NotNull(ctor);

            var targets = ConstructorCallTargets(ctor!);

            // Exactly one chained constructor call, and it must be Person's (the direct base),
            // never object's. Calling object::.ctor here is the [CallCtor]/[ThisUninitReturn] defect.
            Assert.Single(targets);
            Assert.Equal(personType, targets[0].DeclaringType);
            Assert.DoesNotContain(targets, t => t.DeclaringType == typeof(object));

            // The base initializer path still runs this class's field initializer (Department = dept).
            Assert.Equal(1, ILShapeInspector.CountOpcode(ctor!, OpCodes.Stfld));
            return 0;
        });
    }

    [Fact]
    public void ThisInitializer_DelegatesToSiblingConstructor_AndRunsNoBaseChainDirectly()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var employeeType = assembly.GetType("Employee");
            Assert.NotNull(employeeType);

            var ctor = employeeType!.GetConstructor(new[] { typeof(string), typeof(string) });
            Assert.NotNull(ctor);

            var targets = ConstructorCallTargets(ctor!);

            // A `this(...)` initializer delegates to exactly one sibling constructor of the SAME
            // type. It must not call object's ctor directly, and must not call the base type's ctor
            // directly (the sibling owns the base chain).
            Assert.Single(targets);
            Assert.Equal(employeeType, targets[0].DeclaringType);

            // The delegated sibling owns the field initializers, so this constructor must not
            // re-emit them (no Stfld here).
            Assert.Equal(0, ILShapeInspector.CountOpcode(ctor!, OpCodes.Stfld));
            return 0;
        });
    }

    [Fact]
    public void ThisInitializer_OnRootClass_DelegatesToSibling_NotObject()
    {
        ILShapeInspector.Compile(Source, assembly =>
        {
            var personType = assembly.GetType("Person");
            Assert.NotNull(personType);

            var ctor = personType!.GetConstructor(new[] { typeof(string) });
            Assert.NotNull(ctor);

            var targets = ConstructorCallTargets(ctor!);

            // Even when the base is object, a `this(...)` initializer delegates to the sibling
            // Person(string, int) ctor, never directly to object::.ctor.
            Assert.Single(targets);
            Assert.Equal(personType, targets[0].DeclaringType);
            Assert.DoesNotContain(targets, t => t.DeclaringType == typeof(object));
            return 0;
        });
    }

    /// <summary>
    /// Returns the constructors invoked via <c>call</c>/<c>callvirt</c> inside
    /// <paramref name="method"/> (i.e. the constructor-chaining targets).
    /// </summary>
    private static List<ConstructorInfo> ConstructorCallTargets(ConstructorInfo method)
    {
        var module = method.Module;
        var targets = new List<ConstructorInfo>();
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
                targets.Add(resolved);
            }
        }

        return targets;
    }
}
