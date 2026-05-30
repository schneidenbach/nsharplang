using System;
using System.Reflection;
using System.Reflection.Emit;
using NSharpLang.Tests.PerfEvidence;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// Tests for Performance Unit 7: stack-buffer promotion. A non-escaping, fixed-size local
/// array literal of unmanaged primitive elements is stored as a stack-allocated
/// <c>[InlineArray]</c> struct instead of a heap array. These tests cover both behavioral
/// parity (the promoted buffer behaves exactly like a heap array for index/length/foreach/
/// compound-assignment) and IL shape (a promoted buffer emits zero heap <c>newobj</c>, while an
/// escaping buffer still allocates on the heap).
/// </summary>
public class StackallocPromotionTests
{
    // ==================== Behavioral parity ====================

    [Fact]
    public void Promoted_FixedSizeIntBuffer_IndexReadWrite_BehavesLikeArray()
    {
        const string source = @"
func main(): int {
    buf: int[] = [10, 20, 30]
    buf[1] = 99
    return buf[0] + buf[1] + buf[2]
}";

        Assert.Equal(10 + 99 + 30, InvokeMainInt(source));
    }

    [Fact]
    public void Promoted_FixedSizeBuffer_Length_IsConstant()
    {
        const string source = @"
func main(): int {
    buf: int[] = [1, 2, 3, 4, 5]
    return buf.Length
}";

        Assert.Equal(5, InvokeMainInt(source));
    }

    [Fact]
    public void Promoted_FixedSizeBuffer_Foreach_SumsAllElements()
    {
        const string source = @"
func main(): int {
    buf: int[] = [3, 4, 5, 6]
    total := 0
    for x in buf {
        total = total + x
    }
    return total
}";

        Assert.Equal(3 + 4 + 5 + 6, InvokeMainInt(source));
    }

    [Fact]
    public void Promoted_FixedSizeBuffer_CompoundAssignment_Accumulates()
    {
        const string source = @"
func main(): int {
    buf: int[] = [1, 2, 3]
    buf[0] += 100
    buf[2] *= 4
    return buf[0] + buf[1] + buf[2]
}";

        Assert.Equal((1 + 100) + 2 + (3 * 4), InvokeMainInt(source));
    }

    [Fact]
    public void Promoted_DoubleBuffer_BehavesLikeArray()
    {
        const string source = @"
func main(): double {
    buf: double[] = [1.5, 2.5, 3.0]
    return buf[0] + buf[1] + buf[2]
}";

        var result = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");
            return (double)method.Invoke(null, null)!;
        });

        Assert.Equal(7.0, result, 5);
    }

    [Fact]
    public void Promoted_OutOfRangeIndex_ThrowsIndexOutOfRange()
    {
        // The promoted buffer keeps array element-access semantics: an out-of-range index throws.
        const string source = @"
func get(i: int): int {
    buf: int[] = [10, 20, 30]
    return buf[i]
}";

        var ex = Record.Exception(() => ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "get");
            try
            {
                return method.Invoke(null, new object[] { 5 });
            }
            catch (TargetInvocationException tie) when (tie.InnerException is not null)
            {
                throw tie.InnerException;
            }
        }));

        Assert.IsType<IndexOutOfRangeException>(ex);
    }

    [Fact]
    public void Promoted_NegativeIndex_ThrowsIndexOutOfRange()
    {
        const string source = @"
func get(i: int): int {
    buf: int[] = [10, 20, 30]
    return buf[i]
}";

        var ex = Record.Exception(() => ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "get");
            try
            {
                return method.Invoke(null, new object[] { -1 });
            }
            catch (TargetInvocationException tie) when (tie.InnerException is not null)
            {
                throw tie.InnerException;
            }
        }));

        Assert.IsType<IndexOutOfRangeException>(ex);
    }

    // ==================== IL-shape proof: promotion eliminates heap allocation ====================

    [Fact]
    public void IlShape_PromotedBuffer_EmitsNoHeapNewobj()
    {
        // A fixed-size unmanaged buffer used only via index/length should be promoted to a stack
        // [InlineArray]. The promoted path emits no newobj for the buffer (no heap array, and the
        // bounds check throws via a pre-existing exception type only on the failure path, which we
        // don't hit here). We assert the buffer never materialises: zero newinit-style array alloc.
        const string source = @"
func main(): int {
    buf: int[] = [1, 2, 3, 4]
    buf[0] = buf[0] + 1
    return buf[2]
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");

            // No newarr: the heap array is gone.
            Assert.Equal(0, ILShapeInspector.CountOpcode(method, OpCodes.Newarr));

            // The promoted buffer is initialised via initobj on a stack local, not a heap alloc.
            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Initobj) >= 1,
                "Expected the promoted stack buffer to be zero-initialised via initobj.");

            return 0;
        });
    }

    [Fact]
    public void IlShape_EscapingBuffer_StillAllocatesHeapArray()
    {
        // A buffer that escapes (returned to the caller) must NOT be promoted: it stays a heap
        // array, which the emitter creates with newarr.
        const string source = @"
import System.Collections.Generic

func make(): int[] {
    buf: int[] = [1, 2, 3, 4]
    return buf
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "make");

            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Newarr) >= 1,
                "Expected an escaping (returned) buffer to remain a heap array (newarr).");

            return 0;
        });
    }

    [Fact]
    public void IlShape_BufferPassedToCall_StillAllocatesHeapArray()
    {
        // Passing the buffer as an argument escapes it through an opaque callee, so it must stay a
        // heap array.
        const string source = @"
func sink(values: int[]): int {
    return values[0]
}

func main(): int {
    buf: int[] = [7, 8, 9]
    return sink(buf)
}";

        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Newarr) >= 1,
                "Expected a buffer passed to a call to remain a heap array (newarr).");

            return 0;
        });
    }

    [Fact]
    public void IlShape_StringBuffer_NotPromoted_StaysHeapArray()
    {
        // string is a managed reference type: it is NOT an eligible element type for stack
        // promotion (a stack buffer of managed refs would not be GC-tracked). It must stay heap.
        const string source = @"
func main(): string {
    buf: string[] = [""a"", ""b"", ""c""]
    return buf[1]
}";

        var result = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");

            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Newarr) >= 1,
                "Expected a string buffer to remain a heap array (newarr); managed elements are never stack-promoted.");

            return (string)method.Invoke(null, null)!;
        });

        Assert.Equal("b", result);
    }

    // ==================== Escape soundness: these shapes must NOT promote ====================

    [Fact]
    public void IlShape_BufferElementPassedByRef_StaysHeapArray()
    {
        // `ref buf[0]` takes the address of an element. Handing an interior pointer into a stack
        // buffer to an opaque callee could let it escape the frame, so the buffer must stay heap.
        const string source = @"
func bump(ref value: int) {
    value = value + 1
}

func main(): int {
    buf: int[] = [10, 20, 30]
    bump(ref buf[0])
    return buf[0]
}";

        var result = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Newarr) >= 1,
                "Expected a buffer whose element is passed by ref to remain a heap array (newarr).");
            return (int)method.Invoke(null, null)!;
        });

        Assert.Equal(11, result);
    }

    [Fact]
    public void IlShape_BufferElementIncrement_StaysHeapArray()
    {
        // `buf[0]++` mutates the element in place. The emitter has no promoted path for inc/dec on
        // an index access, so the buffer must stay heap to keep codegen correct.
        const string source = @"
func main(): int {
    buf: int[] = [10, 20, 30]
    buf[0]++
    return buf[0]
}";

        var result = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Newarr) >= 1,
                "Expected a buffer with an incremented element to remain a heap array (newarr).");
            return (int)method.Invoke(null, null)!;
        });

        Assert.Equal(11, result);
    }

    [Fact]
    public void IlShape_NestedBlockBuffer_StaysHeapArray()
    {
        // Promotion storage is method-wide and string-keyed and is never scope-restored. A buffer
        // declared inside a nested block is therefore NOT promoted (deferred to heap) to avoid a
        // method-wide key intercepting a different same-named symbol elsewhere.
        const string source = @"
func main(): int {
    total := 0
    if total == 0 {
        buf: int[] = [1, 2, 3]
        total = buf[0] + buf[2]
    }
    return total
}";

        var result = ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");
            Assert.True(
                ILShapeInspector.CountOpcode(method, OpCodes.Newarr) >= 1,
                "Expected a buffer declared inside a nested block to remain a heap array (newarr).");
            return (int)method.Invoke(null, null)!;
        });

        Assert.Equal(4, result);
    }

    [Fact]
    public void IlShape_LocalCollidingWithField_StaysHeapArray()
    {
        // A local whose name collides with an instance field of the enclosing type must not be
        // promoted: the method-wide promoted-buffer key could otherwise intercept `values.Length`
        // / `values[i]` accesses that should bind to the field.
        const string source = @"
class Holder {
    values: int[]

    constructor() {
        values = [0, 0]
    }

    func compute(): int {
        values: int[] = [5, 6, 7]
        return values[0] + values.Length
    }
}";

        var result = ILShapeInspector.Compile(source, assembly =>
        {
            var holderType = assembly.GetType("Holder");
            Assert.NotNull(holderType);
            var method = holderType!.GetMethod(
                "compute",
                System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            Assert.NotNull(method);

            Assert.True(
                ILShapeInspector.CountOpcode(method!, OpCodes.Newarr) >= 1,
                "Expected a local colliding with a field name to remain a heap array (newarr).");

            var instance = Activator.CreateInstance(holderType);
            return (int)method!.Invoke(instance, null)!;
        });

        Assert.Equal(5 + 3, result);
    }

    // ==================== Helpers ====================

    private static int InvokeMainInt(string source) =>
        ILShapeInspector.Compile(source, assembly =>
        {
            var method = ILShapeInspector.GetProgramMethod(assembly, "main");
            return (int)method.Invoke(null, null)!;
        });
}
