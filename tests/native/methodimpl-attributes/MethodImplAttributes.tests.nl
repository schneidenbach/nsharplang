namespace NSharpLang.MethodImplAttributes.Tests

import System
import System.Reflection
import System.Runtime.CompilerServices

// `[MethodImpl(...)]`, PROVED OVER REAL EMITTED METADATA.
//
// `MethodImplAttribute` is a PSEUDO-CUSTOM attribute: the CLR keeps no CustomAttribute row for it
// and instead stores what it says in the method definition row's implementation flags. So there are
// two halves to prove, and both are here: `GetMethodImplementationFlags()` answers exactly what the
// source asked for, and `GetCustomAttributes(...)` answers that the attribute is not there — which
// is what a C#-compiled assembly answers for the same source.
class ImplFacts {
    static func MethodFlags(owner: Type, name: string): int {
        method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static)
        if method == null {
            return -1
        }

        return Convert.ToInt32(method.GetMethodImplementationFlags())
    }

    static func ConstructorFlags(owner: Type): int {
        constructors := owner.GetConstructors()
        if constructors.Length != 1 {
            return -1
        }

        return Convert.ToInt32(constructors[0].GetMethodImplementationFlags())
    }

    // Every custom attribute actually attached to the member, by simple name, so an absence can be
    // asserted as an absence rather than as a count.
    static func MethodAttributeNames(owner: Type, name: string): string {
        method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static)
        if method == null {
            return "<missing>"
        }

        names := ""
        for attribute in method.GetCustomAttributes(false) {
            names = names + attribute.GetType().Name
            names = names + ";"
        }

        return names
    }

    // The free functions of a source file are emitted as static methods of one holder type that
    // nothing in the source names, so the holder is reached the way any other consumer reaches it:
    // through the assembly these tests live in.
    static func FreeFunctionFlags(name: string): int {
        assembly := typeof(Cold).get_Assembly()
        for candidate in assembly.GetTypes() {
            method := candidate.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
            if method != null {
                return Convert.ToInt32(method.GetMethodImplementationFlags())
            }
        }

        return -1
    }

    static func Option(option: MethodImplOptions): int {
        return Convert.ToInt32(option)
    }

    static func Combined(first: MethodImplOptions, second: MethodImplOptions): int {
        return Convert.ToInt32(first | second)
    }
}

// --- Each option, on its own, on each method-like member ------------------------------------------

test "a single AggressiveInlining reaches the emitted implementation flags" {
    assert ImplFacts.MethodFlags(typeof(Hot), "op_Addition") == ImplFacts.Option(MethodImplOptions.AggressiveInlining)
    assert ImplFacts.MethodFlags(typeof(Cold), "Qualified") == ImplFacts.Option(MethodImplOptions.NoInlining)
}

test "NoInlining, NoOptimization, Synchronized and PreserveSig each map to their own bit" {
    assert ImplFacts.MethodFlags(typeof(Hot), "Instance") == ImplFacts.Option(MethodImplOptions.NoInlining)
    assert ImplFacts.MethodFlags(typeof(Hot), "Generic") == ImplFacts.Option(MethodImplOptions.NoOptimization)
    assert ImplFacts.MethodFlags(typeof(Cold), "Locked") == ImplFacts.Option(MethodImplOptions.Synchronized)
    assert ImplFacts.MethodFlags(typeof(Cold), "Preserved") == ImplFacts.Option(MethodImplOptions.PreserveSig)
}

test "a static method carries its own flags" {
    assert ImplFacts.MethodFlags(typeof(Hot), "Make") == ImplFacts.Option(MethodImplOptions.AggressiveOptimization)
}

test "a free function carries its flags, and an unmarked one carries none" {
    assert ImplFacts.FreeFunctionFlags("FreeHot") == ImplFacts.Option(MethodImplOptions.AggressiveInlining)
    assert ImplFacts.FreeFunctionFlags("FreeUnmarked") == 0
}

// --- Combinations ---------------------------------------------------------------------------------

test "a '|' combination sets both bits" {
    expected := ImplFacts.Combined(MethodImplOptions.AggressiveInlining, MethodImplOptions.AggressiveOptimization)
    assert expected == 768, "AggressiveInlining | AggressiveOptimization is 0x300"
    assert ImplFacts.MethodFlags(typeof(Hot), "get_Doubled") == expected
}

// --- Constructors and property accessors ----------------------------------------------------------

test "a constructor carries the implementation flags its attribute asked for" {
    assert ImplFacts.ConstructorFlags(typeof(Hot)) == ImplFacts.Option(MethodImplOptions.AggressiveInlining)
}

test "a property's attribute marks every accessor it declares" {
    expected := ImplFacts.Combined(MethodImplOptions.AggressiveInlining, MethodImplOptions.NoOptimization)
    assert ImplFacts.MethodFlags(typeof(Cold), "get_Slot") == expected
    assert ImplFacts.MethodFlags(typeof(Cold), "set_Slot") == expected
    assert ImplFacts.MethodFlags(typeof(Hot), "get_Tripled") == ImplFacts.Option(MethodImplOptions.NoInlining)
}

test "a static property's accessors carry the flags too" {
    assert ImplFacts.MethodFlags(typeof(Cold), "get_Slots") == ImplFacts.Option(MethodImplOptions.PreserveSig)
    assert ImplFacts.MethodFlags(typeof(Cold), "set_Slots") == ImplFacts.Option(MethodImplOptions.PreserveSig)
}

test "an unattributed property accessor carries no flags" {
    assert ImplFacts.MethodFlags(typeof(Hot), "get_Amount") == 0
}

// --- The zero cases -------------------------------------------------------------------------------

test "an unmarked method reports IL and Managed, which is zero" {
    assert ImplFacts.MethodFlags(typeof(Hot), "Unmarked") == 0
    assert Convert.ToInt32(MethodImplAttributes.IL) == 0, "IL is the default code type"
    assert Convert.ToInt32(MethodImplAttributes.Managed) == 0, "Managed is the default managed-ness"
}

test "a bare [MethodImpl] asks for nothing and reads back the same zero" {
    assert ImplFacts.MethodFlags(typeof(Hot), "Bare") == 0
}

// --- C# parity: the pseudo-custom attribute leaves no custom-attribute row ------------------------

test "MethodImpl never appears as a custom attribute on the member it marked" {
    assert ImplFacts.MethodAttributeNames(typeof(Hot), "Instance") == ""
    assert ImplFacts.MethodAttributeNames(typeof(Hot), "get_Doubled") == ""
    assert ImplFacts.MethodAttributeNames(typeof(Hot), "op_Addition") == ""
    assert ImplFacts.MethodAttributeNames(typeof(Cold), "Qualified") == ""
    assert ImplFacts.MethodAttributeNames(typeof(Hot), "Bare") == ""
}

// --- The declarations still mean what they said ---------------------------------------------------

test "the marked members still compute what they always computed" {
    hot := new Hot(21)
    assert hot.Amount == 21
    assert hot.Doubled == 42
    assert hot.Tripled == 63
    assert hot.Instance() == 21
    made := Hot.Make(5)
    assert made.Amount == 5
    summed := new Hot(2) + new Hot(3)
    assert summed.Amount == 5
    generic := new Hot(9)
    assert generic.Generic<int>(4) == 4
    assert FreeHot() == 7
    cold := new Cold()
    assert cold.Locked() == 2
    assert cold.Preserved() == 3
    assert cold.Qualified() == 1
    assert FreeUnmarked() == 8
    assert hot.Unmarked() == 21
    assert hot.Bare() == 21
}

test "a setter marked with MethodImpl still writes" {
    cold := new Cold()
    cold.Slot = 10
    assert cold.Slot == 10
}

// --- The observable consequence -------------------------------------------------------------------

test "a NoInlining method is the method its own stack frame names" {
    // The GUARANTEED direction only. Whether an `AggressiveInlining` method actually disappears from
    // a frame depends on JIT tier and platform, so the opposite assertion is not written here.
    cold := new Cold()
    assert cold.FrameName() == "FrameName"
}
