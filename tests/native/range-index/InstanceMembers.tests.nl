namespace NSharpLang.RangeIndex.Tests

enum InstanceMemberStatus {
    Ready
}

union InstanceMemberOutcome {
    Ready
    Failed { message: string }
}

struct MutableInstanceMemberCounter {
    value: int

    constructor(initialValue: int) {
        this.value = initialValue
    }

    Next: int => value
}

class MutableReferenceInstanceMemberCounter {
    value: int

    constructor(initialValue: int) {
        this.value = initialValue
    }

    Next: int => value
}

class RuntimeTypeHolder {
    runtimeType: Type

    constructor(value: Type) {
        this.runtimeType = value
    }

    RuntimeType: Type => runtimeType
}

class NestedInstanceMemberHolder {
    leaf: MutableInstanceMemberCounter

    constructor(initialValue: int) {
        this.leaf = new MutableInstanceMemberCounter(initialValue)
    }
}

func IdentityNestedInstanceMember(value: int): int {
    return value
}

func ReadMutableInstanceMemberLocal(initialValue: int): int {
    counter := new MutableInstanceMemberCounter(initialValue)
    counter.value = counter.value + 1
    first := counter.Next
    counter.value = counter.value + 1
    second := counter.Next
    return (first * 10) + second
}

func ReadMutableInstanceMemberParameter(counter: MutableInstanceMemberCounter): int {
    counter.value = counter.value + 1
    first := counter.Next
    counter.value = counter.value + 1
    second := counter.Next
    return (first * 10) + second
}

func ReadMutableInstanceMemberByReference(ref counter: MutableInstanceMemberCounter): int {
    fieldValue := counter.value
    propertyValue := counter.Next
    return (fieldValue * 10) + propertyValue
}

func ReadMutableReferenceInstanceMemberByReference(ref counter: MutableReferenceInstanceMemberCounter): int {
    fieldValue := counter.value
    propertyValue := counter.Next
    return (fieldValue * 10) + propertyValue
}

func ReadMutableReferenceFieldByReference(ref counter: MutableReferenceInstanceMemberCounter): int {
    return counter.value
}

func ReadMutableReferencePropertyByReference(ref counter: MutableReferenceInstanceMemberCounter): int {
    return counter.Next
}

func ReadyInstanceMemberStatus(): Result<InstanceMemberStatus, string> {
    return Ok(InstanceMemberStatus.Ready)
}

test "instance-member plans execute reference and value fields and properties" {
    classReader := new CurrentClassRangeReader(2, 1)
    structReader := new CurrentStructRangeReader(3, 2)

    assert classReader.count == 2
    assert classReader.Count == 2
    assert structReader.count == 3
    assert structReader.Count == 3
}

test "instance-member plans preserve inherited and closed-generic identity" {
    inheritedReader := new InheritedRangeReader(2, 1)
    genericReader := new GenericCurrentClassReader<string>("closed", 2)

    assert inheritedReader.inheritedCount == 2
    assert inheritedReader.InheritedCount == 2
    assert genericReader.value == "closed"
    assert genericReader.Value == "closed"
}

test "instance-member plans preserve source enum types in generic runtime properties" {
    result := ReadyInstanceMemberStatus()

    assert result.OkValue == InstanceMemberStatus.Ready
}

test "instance-member plans own scalar literal receivers" {
    assert "abc".Length == 3
    assert $"abc".Length == 3
}

test "instance-member plans own typeof receivers and recurse through range-index" {
    assert typeof(string).Name == "String"
    assert typeof(string).FullName == "System.String"
    assert typeof(string).Namespace == "System"
    assert !typeof(string).IsNested
    assert typeof(MutableInstanceMemberCounter).Name == "MutableInstanceMemberCounter"
    assert typeof(InstanceMemberStatus).Name == "InstanceMemberStatus"
    assert typeof(InstanceMemberOutcome).Name == "InstanceMemberOutcome"
    assert typeof(string).Name[^1] == 'g'
    assert typeof(string).Name[0..3] == "Str"
}

test "nested runtime Type receivers retain the unclaimed legacy fallback" {
    holder := new RuntimeTypeHolder(typeof(string))

    assert holder.runtimeType.Name == "String"
    assert holder.RuntimeType.FullName == "System.String"
    assert holder.runtimeType.Namespace == "System"
    assert !holder.RuntimeType.IsNested
}

test "nested source receivers preserve preflight and mutable value storage" {
    holder := new NestedInstanceMemberHolder(3)

    assert holder.leaf.value == 3
    assert holder.leaf.Next == 3

    copied := new MutableInstanceMemberCounter(holder.leaf.value)
    assert copied.Next == 3
    assert IdentityNestedInstanceMember(holder.leaf.Next) == 3

    holder.leaf.value = 4
    assert holder.leaf.Next == 4
    holder.leaf.value += 2
    assert holder.leaf.value == 6
    assert holder.leaf.Next == 6
}

test "instance-member value receivers retain mutable storage and recurse through range-index" {
    assert ReadMutableInstanceMemberLocal(0) == 12
    assert ReadMutableInstanceMemberParameter(new MutableInstanceMemberCounter(0)) == 12

    values := [10, 20, 30, 40, 50, 60]
    classReader := new CurrentClassRangeReader(2, 1)
    structReader := new CurrentStructRangeReader(2, 1)

    assert values[^classReader.Count] == 50
    assert values[^structReader.count] == 50

    window := values[structReader.start..^structReader.Count]
    assert window.Length == 3
    assert window[0] == 20
    assert window[^1] == 40
}

test "instance-member plans preserve byref value receiver storage" {
    valueCounter := new MutableInstanceMemberCounter(1)
    assert ReadMutableInstanceMemberByReference(ref valueCounter) == 11
    valueCounter.value = 2
    assert ReadMutableInstanceMemberByReference(ref valueCounter) == 22
    assert valueCounter.value == 2
    assert valueCounter.Next == 2
}

test "instance-member plans read a byref reference receiver field" {
    referenceCounter := new MutableReferenceInstanceMemberCounter(1)

    assert ReadMutableReferenceFieldByReference(ref referenceCounter) == 1
}

test "instance-member plans read a byref reference receiver property" {
    referenceCounter := new MutableReferenceInstanceMemberCounter(1)

    assert ReadMutableReferencePropertyByReference(ref referenceCounter) == 1
}

test "instance-member plans compose byref reference receiver reads" {
    referenceCounter := new MutableReferenceInstanceMemberCounter(1)

    assert ReadMutableReferenceInstanceMemberByReference(ref referenceCounter) == 11
}

test "instance-member plans reread mutated byref reference receiver storage" {
    referenceCounter := new MutableReferenceInstanceMemberCounter(1)
    referenceCounter.value = 2

    assert ReadMutableReferenceInstanceMemberByReference(ref referenceCounter) == 22
}

test "instance-member plans preserve the byref reference receiver after mutation" {
    referenceCounter := new MutableReferenceInstanceMemberCounter(1)
    referenceCounter.value = 2

    assert referenceCounter.value == 2
    assert referenceCounter.Next == 2
}

test "instance-member plans preserve aliases to a byref reference receiver" {
    referenceCounter := new MutableReferenceInstanceMemberCounter(1)
    originalReference := referenceCounter
    referenceCounter.value = 2

    assert originalReference.value == 2
    assert originalReference.Next == 2
}
