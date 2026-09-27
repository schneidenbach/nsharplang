namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Text


// THE CAST OWNER'S CONTRACT, STATED AS THE FIVE CONVERSIONS AN EXPLICIT CAST IS.
class CcpProbe {

    // The rows one conversion appends, as opcode values in order. An empty array means the
    // conversion costs nothing at all, which is itself a fact worth pinning.
    static func Opcodes(sourceType: Type, targetType: Type): short[] {
        plan := new ColumnarCodePlan()
        plan.PrepareMethodBody()
        if !ColumnarCastConversionPlanner.TryAppendCast(plan, sourceType, targetType, null) {
            return new short[](0 - 1 + 1)
        }
        values := new short[](plan.OperationCount)
        i := 0
        while i < plan.OperationCount {
            values[i] = plan.OpCodeValues[i]
            i = i + 1
        }
        return values
    }

    static func OneOpcode(sourceType: Type, targetType: Type, expected: short): bool {
        rows := Opcodes(sourceType, targetType)
        return rows.Length == 1 && rows[0] == expected
    }
}

test "an identity cast and a reference widening cost no rows at all" {
    assert CcpProbe.Opcodes(typeof(int), typeof(int)).Length == 0
    assert CcpProbe.Opcodes(typeof(string), typeof(object)).Length == 0
    assert CcpProbe.Opcodes(typeof(List<int>), typeof(IEnumerable<int>)).Length == 0
}

test "a boxing conversion boxes the source and an unboxing conversion unboxes the target" {
    assert CcpProbe.OneOpcode(typeof(int), typeof(object), ColumnarCodePlanContract.Box())
    assert CcpProbe.OneOpcode(typeof(DateTime), typeof(object), ColumnarCodePlanContract.Box())
    assert CcpProbe.OneOpcode(typeof(object), typeof(int), ColumnarCodePlanContract.UnboxAny())
}

test "a reference downcast is castclass" {
    assert CcpProbe.OneOpcode(typeof(object), typeof(string), ColumnarCodePlanContract.Castclass())
    assert CcpProbe.OneOpcode(typeof(IEnumerable<int>), typeof(List<int>), ColumnarCodePlanContract.Castclass())
}

// THE NUMERIC TABLE IS DRIVEN BY THE TARGET, and is unchecked: `for v: int in longs` truncates
// exactly as `(int)value` does outside a loop.
test "a numeric conversion is the conv the target selects" {
    assert CcpProbe.OneOpcode(typeof(int), typeof(long), ColumnarCodePlanContract.ConvI8())
    assert CcpProbe.OneOpcode(typeof(long), typeof(int), ColumnarCodePlanContract.ConvI4())
    assert CcpProbe.OneOpcode(typeof(int), typeof(double), ColumnarCodePlanContract.ConvR8())
    assert CcpProbe.OneOpcode(typeof(int), typeof(float), ColumnarCodePlanContract.ConvR4())
    assert CcpProbe.OneOpcode(typeof(int), typeof(byte), ColumnarCodePlanContract.ConvU1())
    assert CcpProbe.OneOpcode(typeof(int), typeof(sbyte), ColumnarCodePlanContract.ConvI1())
    assert CcpProbe.OneOpcode(typeof(int), typeof(short), ColumnarCodePlanContract.ConvI2())
    assert CcpProbe.OneOpcode(typeof(int), typeof(char), ColumnarCodePlanContract.ConvU2())
    assert CcpProbe.OneOpcode(typeof(uint), typeof(ulong), ColumnarCodePlanContract.ConvU8())
    assert CcpProbe.OneOpcode(typeof(int), typeof(ulong), ColumnarCodePlanContract.ConvI8())
}

// AN ENUM'S CONVERSIONS ARE ITS UNDERLYING TYPE'S, which is why they share the numeric arm rather
// than getting a table of their own.
test "an enum converts through its underlying numeric type" {
    assert CcpProbe.OneOpcode(typeof(DayOfWeek), typeof(long), ColumnarCodePlanContract.ConvI8())
    assert CcpProbe.OneOpcode(typeof(int), typeof(DayOfWeek), ColumnarCodePlanContract.ConvI4())
}

// WHAT HAS NO OPCODE DECLINES rather than being guessed at. A by-ref or pointer target is not a
// conversion at all; `string` and `int` share no conversion in either direction; and a value type
// cannot be read at an unrelated value type.
test "a conversion with no rows declines instead of guessing one" {
    assert !ColumnarCastConversionPlanner.CanAppendCast(typeof(string), typeof(int))
    assert !ColumnarCastConversionPlanner.CanAppendCast(typeof(int), typeof(DateTime))
    assert !ColumnarCastConversionPlanner.CanAppendCast(typeof(int), typeof(int).MakeByRefType())
    assert !ColumnarCastConversionPlanner.CanAppendCast(typeof(int), typeof(StringBuilder))
    assert !ColumnarCastConversionPlanner.CanAppendCast(null, typeof(int))
    assert !ColumnarCastConversionPlanner.CanAppendCast(typeof(int), null)
}

// A BOXED VALUE READ AT AN INTERFACE IS STILL A BOX, and a value type read at an interface it
// implements is the same conversion — one arm, not two.
test "a value type read at an interface boxes" {
    assert CcpProbe.OneOpcode(typeof(int), typeof(IComparable), ColumnarCodePlanContract.Box())
}
