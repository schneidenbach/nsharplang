namespace NSharpLang.MethodImplAttributes.Tests

import System.Diagnostics
import System.Runtime.CompilerServices

// THE DECLARATIONS THE TESTS MEASURE. Every member below says something with `[MethodImpl(...)]`,
// or deliberately says nothing, and `MethodImplAttributes.tests.nl` reads the emitted metadata back.
//
// The options used here are the ones a method WITH A BODY may carry. `InternalCall` and `Unmanaged`
// say the implementation lives outside this assembly, so a member that has IL of its own is refused
// by the type loader and by NL932 before it; they are exercised in the compiler-service tests over
// the flag computation instead, where nothing is emitted. (`ForwardRef` says the same thing and the
// type loader tolerates it, so it is allowed — it is simply not useful to emit.)
struct Hot {
    amount: int

    // A CONSTRUCTOR IS A METHOD-LIKE MEMBER and carries its own implementation flags.
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    constructor(amount: int) {
        this.amount = amount
    }

    Amount: int {
        get {
            return amount
        }
    }

    // AN EXPRESSION-BODIED PROPERTY, PRECEDED BY AN ATTRIBUTE LIST — the shape that used to swallow
    // the NEXT member's `[` as an index into this body.
    [MethodImpl(MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization)]
    Doubled: int => amount * 2

    [MethodImpl(MethodImplOptions.NoInlining)]
    Tripled: int {
        get {
            return amount * 3
        }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    func Instance(): int {
        return amount
    }

    [MethodImpl(MethodImplOptions.AggressiveOptimization)]
    static func Make(seed: int): Hot {
        return new Hot(seed)
    }

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    static func operator +(left: Hot, right: Hot): Hot {
        return new Hot(left.amount + right.amount)
    }

    [MethodImpl(MethodImplOptions.NoOptimization)]
    func Generic<T>(item: T): T {
        return item
    }

    // NOTHING SAID: the flags must stay `IL | Managed`, which is zero.
    func Unmarked(): int {
        return amount
    }

    // `[MethodImpl]` WITH NO ARGUMENTS is legal and asks for nothing, so it must read back the same
    // zero an unmarked method reads back — and, like every other spelling, must leave no custom
    // attribute behind.
    [MethodImpl]
    func Bare(): int {
        return amount
    }
}

class Cold {
    slot: int

    // A PROPERTY WITH BOTH ACCESSORS. N# has no accessor-level attribute position, so the property's
    // attributes are its accessors' attributes: both `get_Slot` and `set_Slot` carry this one.
    [MethodImpl(MethodImplOptions.AggressiveInlining | MethodImplOptions.NoOptimization)]
    Slot: int {
        get {
            return slot
        }
        set {
            slot = value
        }
    }

    static slots: int = 4

    // A STATIC PROPERTY has CLR-static accessors, which the emitter defines on a different path from
    // the instance ones.
    [MethodImpl(MethodImplOptions.PreserveSig)]
    static Slots: int {
        get {
            return Cold.slots
        }
        set {
            Cold.slots = value
        }
    }

    // THE FULLY QUALIFIED SPELLING of both the attribute and the option.
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    func Qualified(): int {
        return 1
    }

    // `Synchronized` takes the method's monitor. It is only legal on a REFERENCE type's method, so it
    // is declared here and not on `Hot`.
    [MethodImpl(MethodImplOptions.Synchronized)]
    func Locked(): int {
        return 2
    }

    [MethodImpl(MethodImplOptions.PreserveSig)]
    func Preserved(): int {
        return 3
    }

    // THE OBSERVABLE CONSEQUENCE OF `NoInlining`: a method that cannot be inlined is the method its
    // own stack frame names. An `AggressiveInlining` twin is deliberately NOT asserted against —
    // whether the JIT takes the hint depends on tier, build and platform, so only the guaranteed
    // direction is a test.
    [MethodImpl(MethodImplOptions.NoInlining)]
    func FrameName(): string {
        trace := new StackTrace(false)
        frame := trace.GetFrame(0)
        if frame == null {
            return ""
        }

        method := frame.GetMethod()
        if method == null {
            return ""
        }

        return method.Name
    }
}

// A FREE FUNCTION is emitted as a static method and carries flags like any other.
[MethodImpl(MethodImplOptions.AggressiveInlining)]
func FreeHot(): int {
    return 7
}

func FreeUnmarked(): int {
    return 8
}
