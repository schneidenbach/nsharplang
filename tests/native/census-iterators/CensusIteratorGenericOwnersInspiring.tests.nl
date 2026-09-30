namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic
import System.IO
import System.Reflection


// EXECUTED PROOFS FOR STATIC GENERATORS DECLARED BY GENERIC TYPES. Each generator is enumerated over
// a value-type and a reference-type instantiation where the shape allows it: the machine is shared
// IL, so a reference-only run could not tell a correct instantiation from one that happened to erase.
test "a static generator of a generic type yields its owner's type parameter" {
    words := new List<string>()
    for w in CensusRepeater<string>.Repeat("hi", 3) {
        words.Add(w)
    }
    assert words.Count == 3
    assert words[0] == "hi"
    assert words[2] == "hi"

    numbers := new List<int>()
    for n in CensusRepeater<int>.Repeat(7, 2) {
        numbers.Add(n)
    }
    assert numbers.Count == 2
    assert numbers[1] == 7
}

test "a static generator of a generic type yields nothing for a zero count" {
    n := 0
    for _ in CensusRepeater<int>.Repeat(1, 0) {
        n += 1
    }
    assert n == 0
}

test "a generic static generator of a generic type sees both parameter lists" {
    tags := new List<string>()
    tags.Add("a")
    tags.Add("b")
    tags.Add("c")
    collected := new List<int>()
    for v in CensusRepeater<int>.EchoPerTag<string>(4, tags) {
        collected.Add(v)
    }
    assert collected.Count == 3
    assert collected[2] == 4
}

test "a static generator builds its owner's constructed type inside the machine" {
    values := new List<int>()
    values.Add(3)
    values.Add(5)
    total := 0
    for seeded in CensusRepeater<int>.Seeds(values) {
        total += seeded.Seed
    }
    assert total == 8
}

test "a sibling static member calls the generator without qualification" {
    assert CensusRepeater<string>.CountRepeats("x", 4) == 4
    assert CensusRepeater<long>.CountRepeats(9, 1) == 1
}

test "an instance member calls the generator through its own instantiation" {
    copies := new CensusRepeater<int>(6).Copies(2)
    assert copies.Count == 2
    assert copies[0] == 6
    assert copies[1] == 6
}

test "a generic free function calls the generator over its own type parameter" {
    assert CensusRepeatAny<bool>(true, 3) == 3
    assert CensusRepeatAny<string>("s", 2) == 2
}

test "a generic static generator of a non-generic type instantiates over the method's parameter" {
    collected := new List<string>()
    for v in CensusPlainOwner.Twice<string>("z") {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[1] == "z"
}

test "a static generator of a two-parameter owner yields one of them" {
    map := new Dictionary<string, int>()
    map["a"] = 1
    map["b"] = 2
    keys := new List<string>()
    for key in CensusKeyed<string, int>.KeysOf(map) {
        keys.Add(key)
    }
    assert keys.Count == 2
    assert keys.Contains("a")
    assert keys.Contains("b")
}

test "a static generator of a generic struct yields its owner's type parameter" {
    collected := new List<double>()
    for v in CensusSlot<double>.Pair(1.5, 2.5) {
        collected.Add(v)
    }
    assert collected.Count == 2
    assert collected[0] == 1.5
    assert collected[1] == 2.5
}

test "a constrained owner's static generator yields its constrained parameter" {
    leases := new List<CensusLease>()
    leases.Add(new CensusLease("first"))
    leases.Add(new CensusLease("second"))
    names := new List<string>()
    for lease in CensusDisposingOwner<CensusLease>.Each(leases) {
        names.Add(lease.Name)
    }
    assert names.Count == 2
    assert names[1] == "second"

    values := new List<int>()
    values.Add(8)
    total := 0
    for v in CensusValueOwner<int>.Each(values) {
        total += v
    }
    assert total == 8
}

// THE METADATA HALF. The machine is generic over the owner's parameters first and the method's own
// after them, and every call instantiates it over exactly what the factory saw.
func MachineArguments(sequence: object): Type[] {
    machine := sequence.GetType()
    if !machine.get_IsGenericType() {
        return Type.EmptyTypes
    }
    return machine.GetGenericArguments()
}

test "the machine is instantiated over the owner's parameter" {
    arguments := MachineArguments(CensusRepeater<int>.Repeat(1, 1))
    assert arguments.Length == 1
    assert arguments[0] == typeof(int)

    other := MachineArguments(CensusRepeater<string>.Repeat("a", 1))
    assert other.Length == 1
    assert other[0] == typeof(string)
}

test "the machine lists the owner's parameters before the method's own" {
    tags := new List<string>()
    arguments := MachineArguments(CensusRepeater<int>.EchoPerTag<string>(1, tags))
    assert arguments.Length == 2
    assert arguments[0] == typeof(int)
    assert arguments[1] == typeof(string)

    keyed := MachineArguments(CensusKeyed<string, long>.KeysOf(new Dictionary<string, long>()))
    assert keyed.Length == 2
    assert keyed[0] == typeof(string)
    assert keyed[1] == typeof(long)

    plain := MachineArguments(CensusPlainOwner.Twice<char>('c'))
    assert plain.Length == 1
    assert plain[0] == typeof(char)
}

func MachineParameter(sequence: object, position: int): Type {
    machine := sequence.GetType()
    if !machine.get_IsGenericType() {
        return typeof(object)
    }
    return machine.GetGenericTypeDefinition().GetGenericArguments()[position]
}

test "the machine restates its owner's constraints on its own parameters" {
    // Instantiated over a runtime type: the metadata question is about the machine's DEFINITION,
    // which is the same whatever closes it.
    streams := new List<MemoryStream>()
    disposing := MachineParameter(CensusDisposingOwner<MemoryStream>.Each(streams), 0)
    constraints := disposing.GetGenericParameterConstraints()
    assert constraints.Length == 1
    assert constraints[0] == typeof(IDisposable)

    valued := MachineParameter(CensusValueOwner<int>.Each(new List<int>()), 0)
    valueFlag := GenericParameterAttributes.NotNullableValueTypeConstraint
    assert (valued.get_GenericParameterAttributes() & valueFlag) == valueFlag

    unconstrained := MachineParameter(CensusRepeater<int>.Repeat(1, 1), 0)
    assert unconstrained.GetGenericParameterConstraints().Length == 0
}
