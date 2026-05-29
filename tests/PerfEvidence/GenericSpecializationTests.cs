using System;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression tests for selective generic specialization (monomorphization). These pin the
/// observable contract of <see cref="GenericSpecializer"/> and the IL backend's specialization
/// hook:
/// <list type="bullet">
/// <item>private/file-private generics over value types are monomorphized into concrete,
/// non-generic methods (no shared-generic instantiation token at the call site, no boxing);</item>
/// <item>public generics keep their generic ABI untouched for C# interop;</item>
/// <item>generics over source-declared (TypeBuilder) structs stay on the shared generic path;</item>
/// <item>specialized programs are behaviourally identical to their generic form.</item>
/// </list>
/// </summary>
public class GenericSpecializationTests
{
    [Fact]
    public void PrivateGenericOverInt_IsMonomorphized_NoBoxing_NoGenericCall()
    {
        const string source = @"
func identityP<T>(value: T): T {
    x := value
    return x
}

func PublicWrap<T>(value: T): T {
    return value
}

func main(): int {
    a := identityP(10)
    b := identityP(20)
    w := PublicWrap(99)
    return a + b + w
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);

            // A concrete, non-generic specialization of the private generic must exist.
            var specialized = FindSpecialization(programType!, "identityP");
            Assert.NotNull(specialized);
            Assert.False(specialized!.IsGenericMethod, "Specialized method must be non-generic.");
            Assert.Equal(typeof(int), specialized.ReturnType);
            Assert.Equal(new[] { typeof(int) }, specialized.GetParameters().Select(p => p.ParameterType).ToArray());
            ILShapeInspector.AssertNoBoxing(specialized);

            // The public generic must NOT be specialized — its generic ABI is preserved for interop.
            Assert.Null(FindSpecialization(programType!, "PublicWrap"));
            var publicGeneric = programType!.GetMethod("PublicWrap", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(publicGeneric);
            Assert.True(publicGeneric!.IsGenericMethodDefinition, "Public generic must stay an open generic definition.");

            // The call sites in main must target the non-generic specialization, not a closed
            // generic instantiation of identityP. The only remaining generic instantiation call is
            // the untouched PublicWrap<int>.
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            var calledGenericInstantiations = ResolveCalledGenericInstantiations(main);
            Assert.DoesNotContain(calledGenericInstantiations, m => m.Name == "identityP");
            Assert.Contains(calledGenericInstantiations, m => m.Name == "PublicWrap");

            // The specialized call should appear as a direct, non-generic call.
            var calledNonGeneric = ResolveCalledMethods(main).Where(m => !m.IsGenericMethod).ToList();
            Assert.Contains(calledNonGeneric, m => m.Name.StartsWith("identityP$", StringComparison.Ordinal));

            return 0;
        });
    }

    [Fact]
    public void SpecializedProgram_ProducesSameResultAsGenericForm()
    {
        const string source = @"
func pick<T>(a: T, b: T, flag: bool): T {
    r := a
    if flag {
        r = b
    }
    return r
}

func main(): int {
    i := pick(1, 2, true)
    j := pick(3, 4, false)
    return i + j
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            var result = main.Invoke(null, null);

            // pick(1,2,true)=2, pick(3,4,false)=3 => 5. Behavioural parity with the generic form.
            Assert.Equal(5, result);

            var programType = assembly.GetType("Program")!;
            var specialized = FindSpecialization(programType, "pick");
            Assert.NotNull(specialized);
            ILShapeInspector.AssertNoBoxing(specialized!);
            return 0;
        });
    }

    [Fact]
    public void GenericOverSourceStruct_StaysShared()
    {
        // Source-declared structs are emitted as TypeBuilders; the specializer conservatively
        // leaves generics over them on the shared generic path to keep IL provably verifiable.
        const string source = @"
struct Vec {
    X: int
    constructor(x: int) { this.X = x }
}

func holdV<T>(value: T): T {
    return value
}

func main(): int {
    v := new Vec(7)
    r := holdV(v)
    return r.X
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var programType = assembly.GetType("Program")!;

            // No specialization of holdV should have been emitted for the struct instantiation.
            Assert.Null(FindSpecialization(programType, "holdV"));

            var holdV = programType.GetMethod("holdV", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(holdV);
            Assert.True(holdV!.IsGenericMethodDefinition, "Generic over a source struct must stay an open generic definition.");
            return 0;
        });
    }

    private static MethodInfo? FindSpecialization(Type programType, string baseName)
    {
        return programType
            .GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            .FirstOrDefault(m => m.Name.StartsWith(baseName + "$", StringComparison.Ordinal));
    }

    private static System.Collections.Generic.IReadOnlyList<MethodBase> ResolveCalledMethods(MethodInfo method)
    {
        var module = method.Module;
        var typeArgs = method.DeclaringType?.GetGenericArguments() ?? Type.EmptyTypes;
        var methodArgs = method.IsGenericMethod ? method.GetGenericArguments() : Type.EmptyTypes;

        var result = new System.Collections.Generic.List<MethodBase>();
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

            try
            {
                if (module.ResolveMethod(token, typeArgs, methodArgs) is { } resolved)
                {
                    result.Add(resolved);
                }
            }
            catch (ArgumentException)
            {
                // Token from another module / unresolvable in this context — ignore.
            }
        }

        return result;
    }

    private static System.Collections.Generic.IReadOnlyList<MethodBase> ResolveCalledGenericInstantiations(MethodInfo method)
    {
        return ResolveCalledMethods(method).Where(m => m.IsGenericMethod).ToList();
    }
}
