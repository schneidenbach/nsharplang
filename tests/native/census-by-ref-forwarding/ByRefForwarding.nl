namespace NSharpLang.CensusByRefForwarding.Tests

import System.Threading


// CENSUS — A BY-REFERENCE PARAMETER PASSED ON BY REFERENCE.
//
// A `&T` parameter names the CALLER'S storage, so `ref p` inside the callee hands that same storage to
// the next callee: on the CLR the argument is `ldarg` of the reference already held, and there is no
// `&&T` to take the address of. The analyzer typed that argument `&&T` and refused it (NL202) — which is
// why `FixApplicatorEditEngine` in Compiler.CodeIntel forwarded its `&T` tables BARE. Every row here
// passes the reference on with `ref`, the spelling every other by-reference argument is written in, and
// every row is observable: the value the OUTERMOST caller reads afterwards is the value the innermost
// callee wrote, which a copy anywhere in the chain would lose.
//
// The rows cover a struct, a primitive and a class (whose REFERENCE is rebound through the chain, not
// merely mutated through it), a chain of two hops, the crossings between the two spellings of a
// by-reference parameter (`p: &T` and `ref p: T`), a FIELD reached through a `&T` struct, an `out`
// argument naming a `&T`, and a reflected framework method (`Interlocked.Increment`) whose own binder
// matches the parameter's `ref int` against the storage the argument reaches.
struct Counter {
    Value: int
}

class Named {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

func BumpBy(counter: &Counter, amount: int) {
    counter.Value = counter.Value + amount
}

func BumpByRef(ref counter: Counter, amount: int) {
    counter.Value = counter.Value + amount
}

func ForwardStruct(counter: &Counter) {
    BumpBy(ref counter, 1)
}

func ForwardStructTwice(counter: &Counter) {
    ForwardStruct(ref counter)
    ForwardStruct(ref counter)
}

func AmpersandToRef(counter: &Counter) {
    BumpByRef(ref counter, 10)
}

func RefToAmpersand(ref counter: Counter) {
    BumpBy(ref counter, 100)
}

func SetTo(slot: &int, value: int) {
    Interlocked.Exchange(ref slot, value)
}

func ForwardInt(slot: &int, value: int) {
    SetTo(ref slot, value)
}

func FieldThroughAmpersand(counter: &Counter, value: int) {
    SetTo(ref counter.Value, value)
}

func IncrementThroughAmpersand(slot: &int): int {
    return Interlocked.Increment(ref slot)
}

func IncrementTwoHops(slot: &int): int {
    return IncrementThroughAmpersand(ref slot)
}

func Rename(ref named: Named, suffix: string) {
    named = new Named(named.Name + suffix)
}

func RenameThroughAmpersand(named: &Named, suffix: string) {
    Rename(ref named, suffix)
}

func RenameTwoHops(named: &Named, suffix: string) {
    RenameThroughAmpersand(ref named, suffix)
}

func Produce(out value: int) {
    value = 42
}

func ProduceThroughAmpersand(slot: &int) {
    Produce(out slot)
}
