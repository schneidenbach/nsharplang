namespace NSharpLang.CensusLocalFunctions.Tests

import System
import System.Collections.Generic
import System.Reflection


// RUNTIME contracts for arrow-bodied local functions, beside `ArrowBodies.nl`.
//
// Every one of these declined at `parse.function` before the statement kernel learned that a local
// function's body may open with `=>` — the whole ENCLOSING function was refused, not just the local
// one — so the assembly existing at all is half the contract. The other half is what the emitted IL
// computes, which is what an arrow body silently lowered as the wrong statement would get wrong.
test "a local function's arrow body computes what it says" {
    assert PickOrDefault(null) == "d"
    assert PickOrDefault("kept") == "kept"
    assert SumAcross(20, 22) == 42
    assert TripleIt(14) == 42
    assert MixedBodies(20) == 41
}

test "a void arrow body is performed, not returned" {
    sink := new List<int>()
    assert PushTwice(sink, 5) == 2
    assert sink[0] == 5
    assert sink[1] == 6

    // The same lowering for a FREE function, whose body kernel is the one the local function shares.
    free := new List<int>()
    AppendTo(free, 9)
    assert free.Count == 1
    assert free[0] == 9
}

test "two arrow bodies in one scope call each other" {
    assert IsEvenByArrow(0)
    assert !IsEvenByArrow(1)
    assert IsEvenByArrow(10)
    assert !IsEvenByArrow(7)
}

test "an arrow body captures the enclosing local exactly as a block body does" {
    assert DecorateWith("p-", "v") == "p-v"
}

test "a parameter default that is a lambda belongs to the signature, not the body" {
    assert ApplyOrIdentity(7, null) == 7

    sixfold: Func<int, int> = x => x * 6
    assert ApplyOrIdentity(7, sixfold) == 42
}

test "a call written above an arrow-bodied declaration reaches it" {
    assert CallAboveArrowDeclaration(4) == 40
}

// CLR METADATA. An arrow-bodied local function is lowered to the same synthesized method a
// block-bodied one gets — `<Owner>g__name`-shaped, private, and carrying the DECLARED return type,
// `void` included.
test "an arrow-bodied local function is the same synthesized method a block-bodied one is" {
    assembly := typeof(ArrowBodyFacts).get_Assembly()
    pick := ArrowBodyFacts.SynthesizedFor(assembly, "PickOrDefault")
    assert pick != null
    assert pick.ReturnType == typeof(string)
    assert !pick.IsPublic

    push := ArrowBodyFacts.SynthesizedFor(assembly, "PushTwice")
    assert push != null
    assert push.ReturnType.FullName == "System.Void"
}

class ArrowBodyFacts {

    // The synthesized method a local function of `ownerName` was lowered into. The name carries the
    // owner, which is what makes the lookup exact without naming the mangling scheme in full.
    static func SynthesizedFor(assembly: Assembly, ownerName: string): MethodInfo {
        marker := "<" + ownerName + ">g__"
        for candidate in assembly.GetTypes() {
            for method in candidate.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly) {
                if method.get_Name().StartsWith(marker) {
                    return method
                }
            }
        }

        return null
    }
}

test "a `continue` inside a `for` in a local function's body runs the loop it belongs to" {
    assert CountNonZero([1, 0, 2, 0, 3]) == 3
    assert CountNonZero([0, 0]) == 0
    assert CountNonZero([]) == 0
}

test "an arrow body inside a method reads the enclosing instance" {
    scaler := new ArrowScaler()
    scaler.Factor = 7
    assert scaler.Scale(6) == 42
}

test "an async local function's arrow body answers the task's result" {
    assert await AwaitInner(41) == 42
}

test "a throw arrow body on a local function throws, `void` and valued alike" {
    assert ThrowingLocals(true) == 1

    caught: string? = null
    try {
        ThrowingLocals(false)
    } catch e: InvalidOperationException {
        caught = e.Message
    }

    assert caught == "local void arrow"
}
