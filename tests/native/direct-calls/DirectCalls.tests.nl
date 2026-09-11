namespace NSharpLang.DirectCalls.Tests

test "fixed-arity static calls select exact same-arity overloads independent of declaration order" {
    assert DirectStaticCalls.Select(2, "number first") == 12
    assert DirectStaticCalls.Select("string first", 3) == 23
    assert DirectStaticCalls.SelectBare(4, "bare") == 14
    assert DirectStaticCalls.Scale(1.5) == 3.0
}

test "fixed-arity runtime static and instance calls execute through the product route" {
    assert ParseRuntimeInt("42") == 42
    assert RuntimeTypeAssignable()
    assert RuntimeObjectText("ordinary") == "ordinary"
    assert RuntimeAbsolute(-7) == 7
}

test "fixed-arity reference receiver calls select exact same-arity overloads" {
    receiver := new DirectReferenceReceiver(10)

    assert receiver.Select("string first", 2) == 212
    assert receiver.Select(3, "number first") == 113
    assert receiver.SelectBare(4, "bare") == 114
    assert receiver.SelectExplicit(5, "explicit") == 115
    assert SelectThroughReferenceParameter(receiver) == 113
}

test "fixed-arity value receiver calls preserve local and parameter storage" {
    receiver := new DirectValueReceiver(10)

    assert receiver.Select(2, "local") == 312
    assert SelectThroughValueParameter(receiver) == 314
}

test "fixed-arity calls preserve addressable value fields" {
    holder := new DirectValueFieldHolder(10)

    assert holder.SelectFromField() == 312
}

test "fixed-arity calls own synthesized record value members" {
    assert DirectReferenceRecordEquals(17)
    assert DirectReferenceRecordNotEquals(17)
    assert DirectReferenceRecordHashesMatch(17)
    assert DirectValueRecordEquals(18)
    assert DirectValueRecordNotEquals(18)
    assert DirectValueRecordHashesMatch(19)
}

test "void direct calls preserve static and reference receiver effects" {
    log := new DirectCallLog(0)
    referenceReceiver := new DirectReferenceReceiver(1)

    DirectStaticCalls.Record(log, 7)
    referenceReceiver.Record(8)

    assert log.value == 7
    assert referenceReceiver.value == 8
}

test "instance selection uses the nearest visible declaration while preserving the static receiver type" {
    derivedReceiver := new DirectHiddenDerived()
    baseReceiver: DirectHiddenBase = new DirectHiddenDerived()

    assert derivedReceiver.Select(5, "derived") == 705
    assert baseReceiver.Select(5, "base") == 605
}

test "direct calls recurse through receivers arguments and persisted results" {
    receiver := new DirectReferenceReceiver(10)
    zero := () => 42

    assert ComposeNestedCalls(receiver) == 135
    assert SelectFromCreatedReference() == 113
    assert SelectFromCreatedValue() == 317
    assert RecurseDirectCalls(42) == 42
    assert InvokeFunctionSyntax(value => value * 2, 21) == 42
    assert zero() == 42
    assert RentThroughExactPoolAlias() >= 1
}

test "direct calls compose with already-owned index and range plans" {
    values := [10, 20, 30, 40, 50]
    window := SliceByNestedCalls(values)

    assert ReadByNestedCall(values) == 40
    assert PassIndexedValue(values) == 50
    assert window.Length == 3
    assert window[0] == 20
    assert window[^1] == 40
    assert PassSlicedValue("abcde") == 3
}

test "direct calls close the generic String.Join owner over non-int primitive element arrays" {
    longs: long[] = [10L, 20L, 30L]
    assert DirectJoinLongArray(longs) == "10, 20, 30"

    doubles: double[] = [4.0, 5.0]
    assert DirectJoinDoubleArray(doubles) == "4|5"

    bytes: byte[] = [1, 2, 3]
    assert DirectJoinByteArray(bytes) == "1-2-3"

    chars: char[] = ['a', 'b', 'c']
    assert DirectJoinCharArray(chars) == "a,b,c"
}
