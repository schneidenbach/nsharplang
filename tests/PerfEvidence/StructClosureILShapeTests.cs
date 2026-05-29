using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// IL-shape and behavioural evidence for Unit 8 (struct closures). A capturing,
/// non-escaping local function whose captured local is mutated must lower to a
/// value-type display struct passed by managed reference (no closure
/// allocation), while an escaping closure must keep its heap display class.
/// Mutation semantics must be preserved in both cases.
/// </summary>
public class StructClosureILShapeTests
{
    private static bool IsGeneratedStructBox(Type type) =>
        type.IsValueType && type.Name.StartsWith("<>LiftedStruct", StringComparison.Ordinal);

    private static IEnumerable<Type> AllTypes(Assembly assembly)
    {
        foreach (var type in assembly.GetTypes())
        {
            yield return type;
            foreach (var nested in type.GetNestedTypes(BindingFlags.Public | BindingFlags.NonPublic))
            {
                yield return nested;
            }
        }
    }

    [Fact]
    public void NonEscapingMutatedCapture_LowersToStructBox_NoClosureAllocation()
    {
        // `value` is captured by a directly-invoked local function and mutated in the
        // enclosing frame. The closure never escapes, so it must lower to a stack
        // value-type box rather than a heap display class.
        const string source = @"
func main(): int {
    value := 1

    func bump(): int {
        value = value + 41
        return value
    }

    return bump()
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            // A value-type struct box was generated...
            var structBoxes = AllTypes(assembly).Where(IsGeneratedStructBox).ToArray();
            Assert.True(
                structBoxes.Length >= 1,
                "Expected a generated value-type display struct for the non-escaping mutated capture.");

            // ...and no heap display class.
            var displayClasses = ILShapeInspector.FindDisplayClasses(assembly);
            Assert.True(
                displayClasses.Count == 0,
                $"Expected no heap display class for the non-escaping capture but found: " +
                $"{string.Join(", ", displayClasses.Select(t => t.FullName))}.");

            // The closure construction in main allocates nothing on the heap.
            var main = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.Equal(0, ILShapeInspector.CountNewObj(main));
            return 0;
        });
    }

    [Fact]
    public void EscapingClosure_RetainsHeapDisplayClass()
    {
        // The lambda escapes by being returned as a delegate; it must keep its heap
        // display class and not be lowered to a stack struct box.
        const string source = @"
import System

func makeAdder(amount: int): Func<int, int> {
    return (x) => x + amount
}

func main(): int {
    adder := makeAdder(10)
    return adder(5)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var displayClasses = ILShapeInspector.FindDisplayClasses(assembly);
            Assert.True(
                displayClasses.Count >= 1,
                "Expected the escaping closure to retain a heap display class.");

            // No struct-box lowering should have been applied to an escaping closure.
            var structBoxes = AllTypes(assembly).Where(IsGeneratedStructBox).ToArray();
            Assert.True(
                structBoxes.Length == 0,
                "Escaping closures must not be lowered to value-type struct boxes.");
            return 0;
        });
    }
}
