using System.Linq;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Regression guard for extension-method codegen. Two defects shipped unverifiable IL
/// (caught by the <c>scripts/ilverify.sh</c> gate, but pinned here so they cannot silently
/// return when the gate is not run locally):
///
/// 1. <b>String <c>+=</c> inside an extension body.</b> <c>result += s</c> on two strings was
///    lowered to the numeric <c>add</c> opcode, which ilverify rejects with
///    <c>[ExpectedNumericType] found ref 'string'</c>. It must lower to
///    <c>string.Concat(string, string)</c>.
///
/// 2. <b>Calling a declared extension method on a user type.</b> <c>GetCallExpressionType</c>
///    returned <c>typeof(object)</c> for an extension call whose receiver is a user-defined
///    class (the method is not a member of the receiver's <c>TypeBuilder</c>). That mistyping
///    made a <i>void</i> extension call statement emit a spurious trailing <c>pop</c>
///    (<c>[StackUnderflow]</c>), and made a <i>bool</i> extension call inside interpolation bind
///    <c>AppendFormatted&lt;object&gt;</c> with an unboxed <c>bool</c> on the stack
///    (<c>[StackUnexpected] found Int32, expected ref 'object'</c>).
/// </summary>
public class ExtensionMethodIlShapeTests
{
    // result += s where both are strings: must concat, not numeric-add.
    private const string StringConcatExtensionSource = @"
func Repeat(this s: string, count: int): string {
    result := """"
    for i := 0; i < count; i++ {
        result += s
    }

    return result
}

func main() {
    x := ""ab"".Repeat(3)
}
";

    // Void extension method on a user class, called as a statement: must be stack-balanced
    // (no trailing pop), and the call-expression type must be inferred as void.
    private const string VoidExtensionSource = @"
class Person {
    Age: int
}

func Bump(this p: Person) {
    p.Age = p.Age + 1
}

func main() {
    alice := new Person { Age: 1 }
    alice.Bump()
}
";

    // Bool extension method on a user class, used inside string interpolation: the value must
    // be boxed (AppendFormatted<object>) or formatted as bool (AppendFormatted<bool>) — never
    // an unboxed bool handed to an object-typed parameter.
    private const string BoolExtensionInterpolationSource = @"
class Person {
    Age: int
}

func IsAdult(this p: Person): bool {
    return p.Age >= 18
}

func main() {
    alice := new Person { Age: 20 }
    print $""adult: {alice.IsAdult()}""
}
";

    [Fact]
    public void StringPlusEqualsInExtensionBody_ConcatenatesInsteadOfNumericAdd()
    {
        ILShapeInspector.Compile(StringConcatExtensionSource, assembly =>
        {
            var repeat = ILShapeInspector.GetProgramMethod(assembly, "Repeat");

            // `result += s` must lower to string.Concat. Emitting the numeric `add` opcode on
            // two string references instead produces unverifiable IL (IL:ExpectedNumericType).
            Assert.True(
                ILShapeInspector.CountCallsTo(repeat, typeof(string), nameof(string.Concat)) >= 1,
                "Expected `result += s` to lower to a string.Concat call.");

            // The only legitimate numeric `add` in the body is the `i++` loop-counter increment;
            // the string concatenation must NOT contribute another `add`.
            Assert.Equal(1, ILShapeInspector.CountOpcode(repeat, OpCodes.Add));
            return 0;
        });
    }

    [Fact]
    public void VoidExtensionMethodCallStatement_IsStackBalanced()
    {
        ILShapeInspector.Compile(VoidExtensionSource, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            var instructions = ILShapeInspector.Decode(main);

            // The void extension call must be present...
            Assert.True(
                ILShapeInspector.CountCallsTo(main, assembly.GetType("Program")!, "Bump") >= 1,
                "Expected a call to the Bump extension method.");

            // ...and there must be no `pop` after it. A void call leaves nothing on the stack,
            // so popping would underflow (IL:StackUnderflow). The only call in main is the void
            // Bump(); any pop would be the spurious one.
            Assert.Equal(0, ILShapeInspector.CountOpcode(instructions, OpCodes.Pop));
            return 0;
        });
    }

    [Fact]
    public void BoolExtensionMethodInInterpolation_BoxesValueForObjectParameter()
    {
        ILShapeInspector.Compile(BoolExtensionInterpolationSource, assembly =>
        {
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            var instructions = ILShapeInspector.Decode(main);

            Assert.True(
                ILShapeInspector.CountCallsTo(main, assembly.GetType("Program")!, "IsAdult") >= 1,
                "Expected a call to the IsAdult extension method.");

            // Whether the interpolation handler binds AppendFormatted<bool> (no box) or
            // AppendFormatted<object> (box required), the emitted IL must be type-safe. The
            // unverifiable case was AppendFormatted<object> with an *unboxed* bool on the stack.
            // Pin that: if any AppendFormatted is bound to object, the bool must be boxed first.
            var appendFormattedToObject = instructions
                .Where(i => i.OpCode == OpCodes.Call || i.OpCode == OpCodes.Callvirt)
                .Count(i => i.MetadataToken is { } token
                    && TryResolveMethod(main.Module, token) is { Name: "AppendFormatted" } m
                    && m.IsGenericMethod
                    && m.GetGenericArguments() is { Length: 1 } args
                    && args[0] == typeof(object));

            if (appendFormattedToObject > 0)
            {
                Assert.True(
                    ILShapeInspector.CountOpcode(instructions, OpCodes.Box) >= 1,
                    "AppendFormatted<object> requires the bool result to be boxed.");
            }

            return 0;
        });
    }

    private static System.Reflection.MethodBase? TryResolveMethod(System.Reflection.Module module, int token)
    {
        try
        {
            return module.ResolveMethod(token);
        }
        catch (System.ArgumentException)
        {
            return null;
        }
    }
}
