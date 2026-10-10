namespace NSharpLang.CensusUsingStatement.Tests

import System
import System.Reflection

// THE CLAIM THE RUNTIME CANNOT MAKE: a struct resource is released WITHOUT BOXING.
//
// Every observable consequence of boxing can be hidden — a struct that writes to a list it holds by
// reference reports the same thing whether the release ran on the value or on a copy of it — so the
// only honest way to pin the `constrained.` lowering is to read the instructions. The IL of
// `StructResource` must carry the `constrained.` prefix (0xFE 0x16) and must carry no `box` (0x8C)
// anywhere: `box` would mean the release ran on a copy the CLR made, which for a struct whose
// `Dispose` mutates itself is the difference between a resource being released and nothing happening.
func UsingIlOfFreeFunction(name: string): byte[] {
    method := UsingIlFindFreeFunction(name)
    body := method.GetMethodBody()
    if body == null {
        throw new InvalidOperationException("The method '" + name + "' has no IL body to read.")
    }

    il := body.GetILAsByteArray()
    if il == null {
        throw new InvalidOperationException("The method '" + name + "' has an empty IL body.")
    }

    return il
}

// The free functions of this project land on a synthesized holder type, so the method is found by
// searching the assembly rather than by naming a type this source cannot see.
func UsingIlFindFreeFunction(name: string): MethodInfo {
    assembly := typeof(LoggedResource).get_Assembly()
    for candidate in assembly.GetTypes() {
        found := candidate.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance)
        if found != null {
            return found
        }
    }

    throw new InvalidOperationException("No method named '" + name + "' was emitted into this assembly.")
}

func UsingIlContainsByte(il: byte[], value: byte): bool {
    index := 0
    while index < il.Length {
        if il[index] == value {
            return true
        }

        index = index + 1
    }

    return false
}

func UsingIlContainsPair(il: byte[], first: byte, second: byte): bool {
    index := 0
    while index + 1 < il.Length {
        if il[index] == first && il[index + 1] == second {
            return true
        }

        index = index + 1
    }

    return false
}

test "a struct using resource is released through constrained., and the method boxes nothing" {
    il := UsingIlOfFreeFunction("StructResource")

    // 0xFE 0x16 is `constrained.` — the prefix that makes the release run on the value's own address.
    assert UsingIlContainsPair(il, 254, 22)
    // 0x8C is `box`. Its absence is the claim: nothing in this method ever put the struct on the heap.
    assert !UsingIlContainsByte(il, 140)
}

test "a reference using resource is released through a null-checked callvirt, with no constrained. prefix" {
    il := UsingIlOfFreeFunction("InferredBinding")

    // 0x39 is `brfalse` — the null check C# emits and this lowering emits with it.
    assert UsingIlContainsByte(il, 57)
    // No `constrained.`: a class needs no prefix, and emitting one would be a different call.
    assert !UsingIlContainsPair(il, 254, 22)
}
