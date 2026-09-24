namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Text


// THE STORE OWNER'S OWN CONTRACT. `ClaimsTarget` is the whole of what this owner will look at, and
// it is deliberately narrower than "anything on the left of an `=`": a bare identifier is a binding
// whose storage belongs to whoever owns the binding, and everything else is not a target at all.
class StpNodes {
    static func Member(): int {
        return ColumnarExpressionNodeKind.MemberAccessExpression
    }

    static func Index(): int {
        return ColumnarExpressionNodeKind.IndexAccessExpression
    }

    static func Identifier(): int {
        return ColumnarExpressionNodeKind.IdentifierExpression
    }

    // One node of `kind` with `childCount` children, in a table this owner can read.
    static func SingleNode(kind: int, childCount: int): ColumnarNodeTable {
        kinds := new int[](childCount + 1)
        valueStarts := new int[](childCount + 1)
        valueLengths := new int[](childCount + 1)
        childStarts := new int[](childCount + 1)
        childCounts := new int[](childCount + 1)
        children := new int[](childCount)
        kinds[0] = kind
        valueStarts[0] = 0
        valueLengths[0] = 1
        childStarts[0] = 0
        childCounts[0] = childCount
        c := 0
        while c < childCount {
            kinds[c + 1] = Identifier()
            valueStarts[c + 1] = 0
            valueLengths[c + 1] = 1
            childStarts[c + 1] = 0
            childCounts[c + 1] = 0
            children[c] = c + 1
            c = c + 1
        }
        return new ColumnarNodeTable(kinds, valueStarts, valueLengths, childStarts, childCounts, children)
    }
}

test "the store owner claims a one-child member access and a two-child index access" {
    assert ColumnarStoreTargetPlanner.ClaimsTarget(StpNodes.SingleNode(StpNodes.Member(), 1), 0)
    assert ColumnarStoreTargetPlanner.ClaimsTarget(StpNodes.SingleNode(StpNodes.Index(), 2), 0)
}

test "the store owner claims neither a bare identifier nor a malformed target" {
    assert !ColumnarStoreTargetPlanner.ClaimsTarget(StpNodes.SingleNode(StpNodes.Identifier(), 0), 0)
    assert !ColumnarStoreTargetPlanner.ClaimsTarget(StpNodes.SingleNode(StpNodes.Member(), 2), 0)
    assert !ColumnarStoreTargetPlanner.ClaimsTarget(StpNodes.SingleNode(StpNodes.Index(), 1), 0)
    assert !ColumnarStoreTargetPlanner.ClaimsTarget(StpNodes.SingleNode(StpNodes.Member(), 1), 0 - 1)
}

// A WRITE HAS TO BE OBSERVABLE. A struct reached as a VALUE is a copy: storing into it would compile
// to rows nothing can read back, so the owner refuses rather than emitting a silent no-op. The same
// answer covers a by-ref, a pointer, an array (its element store is the `stelem` arm) and a type
// parameter that might yet be a struct.
test "only a reference receiver can be written through" {
    assert ColumnarStoreTargetPlanner.IsObservableWriteReceiver(typeof(StringBuilder))
    assert ColumnarStoreTargetPlanner.IsObservableWriteReceiver(typeof(List<int>))
    assert !ColumnarStoreTargetPlanner.IsObservableWriteReceiver(typeof(int))
    assert !ColumnarStoreTargetPlanner.IsObservableWriteReceiver(typeof(DateTime))
    assert !ColumnarStoreTargetPlanner.IsObservableWriteReceiver(typeof(int[]))
    assert !ColumnarStoreTargetPlanner.IsObservableWriteReceiver(typeof(int).MakeByRefType())
    assert !ColumnarStoreTargetPlanner.IsObservableWriteReceiver(null)
}

// THE SETTER IS THE GETTER'S TWIN, ON THE SAME DECLARING TYPE. A property the read owner selected by
// its `get_X` is written through the `set_X` beside it; a property that has no setter has no store,
// and that is a decline rather than a different lowering.
test "a settable property resolves its setter from the getter the read selected" {
    getter := typeof(StringBuilder).GetMethod("get_Length", BindingFlags.Public | BindingFlags.Instance)
    selection := new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.Property, true, false, typeof(StringBuilder), typeof(int), null, getter)
    setter := ColumnarStoreTargetPlanner.SetterFor(selection)
    assert setter != null
    assert setter.Name == "set_Length"
    assert setter.DeclaringType == typeof(StringBuilder)
}

test "a get-only property has no setter to store through" {
    getter := typeof(string).GetMethod("get_Length", BindingFlags.Public | BindingFlags.Instance)
    selection := new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.Property, true, false, typeof(string), typeof(int), null, getter)
    assert ColumnarStoreTargetPlanner.SetterFor(selection) == null
}

test "a selection with no getter at all has no setter" {
    selection := new ColumnarInstanceMemberSelection(ColumnarInstanceMemberKind.Property, true, false, typeof(StringBuilder), typeof(int), null, null)
    assert ColumnarStoreTargetPlanner.SetterFor(selection) == null
}
