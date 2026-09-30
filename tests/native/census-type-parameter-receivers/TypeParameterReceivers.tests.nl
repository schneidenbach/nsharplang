namespace NSharpLang.CensusTypeParameterReceivers.Tests

import System
import System.Reflection

// A RECEIVER TYPED BY A TYPE PARAMETER, RUN FOR BOTH KINDS OF TYPE ARGUMENT.
//
// One instantiation of `Holder<T>.Show` has to be right for `Holder<int>` and `Holder<string>`, and
// the only IL that is right for both is `constrained. !T; callvirt` over the receiver's address. The
// rows below run each shape with a value-type and a reference-type argument and read back what it
// returned; the last rows read the instructions, because "no box" and "the field's own address" are
// claims no return value can make.

// ---- `System.Object`'s MEMBERS -----------------------------------------------------------------
test "ToString on a T field answers for a value-type and a reference-type argument" {
    assert new Holder<int>(3).Show() == "3"
    assert new Holder<string>("s").Show() == "s"
}

test "ToString reaches a struct's own override, a struct's inherited one, and a class's override" {
    assert new Holder<Point>(new Point(1, 2)).Show() == "(1, 2)"
    assert new Holder<Plain>(new Plain(7)).Show() == "NSharpLang.CensusTypeParameterReceivers.Tests.Plain"
    assert new Holder<Named>(new Named("ada")).Show() == "ada"
}

test "GetHashCode on a T field is the argument's own hash" {
    assert new Holder<int>(42).Hash() == 42.GetHashCode()
    assert new Holder<string>("hash").Hash() == "hash".GetHashCode()
}

test "Equals(object) on a T field compares by the argument's own equality" {
    assert new Holder<int>(3).Same(3)
    assert !new Holder<int>(3).Same(4)
    assert new Holder<string>("s").Same("s")
    assert !new Holder<string>("s").Same("t")
}

test "GetType on a T field is the runtime type of the argument" {
    assert new Holder<int>(3).TypeName() == "Int32"
    assert new Holder<string>("s").TypeName() == "String"
}

test "a T parameter, a T local and a T call result all answer ToString" {
    assert ShowParam<int>(5) == "5"
    assert ShowParam<string>("p") == "p"
    assert ShowLocal<int>(6) == "6"
    assert ShowLocal<string>("l") == "l"
    assert ShowFirst<int>([7]) == "7"
    assert ShowFirst<string>(["r"]) == "r"
}

// ---- AN INTERFACE CONSTRAINT'S MEMBER, AND WHOSE STORAGE IT WRITES -------------------------------

test "a struct T field is bumped in place, and a class T field through its shared reference" {
    assert new Bumper<Counter>(new Counter(), new Counter()).BumpField() == 2
    assert new Bumper<CounterBox>(new CounterBox(), new CounterBox()).BumpField() == 2
}

test "a readonly struct T field is copied before each call, and a readonly class T field is not" {
    assert new Bumper<Counter>(new Counter(), new Counter()).BumpReadonly() == 1
    assert new Bumper<CounterBox>(new CounterBox(), new CounterBox()).BumpReadonly() == 2
}

test "a T parameter and a T local are bumped in place" {
    assert BumpParam<Counter>(new Counter()) == 2
    assert BumpParam<CounterBox>(new CounterBox()) == 2
    assert BumpLocal<Counter>(new Counter()) == 2
    assert BumpLocal<CounterBox>(new CounterBox()) == 2
}

test "a T call result has no storage, so a struct element is bumped on a fresh copy each time" {
    assert BumpFirst<Counter>([new Counter()]) == 1
    assert BumpFirst<CounterBox>([new CounterBox()]) == 2
}

test "the caller's struct argument is not changed by a callee that bumps its own parameter" {
    counter := new Counter()
    assert BumpParam<Counter>(counter) == 2
    assert counter.Bump() == 1
}

// ---- THE INSTRUCTIONS ---------------------------------------------------------------------------
//
// Opcode bytes: 0x02 `ldarg.0`, 0x0A `stloc.0`, 0x0F `ldarga.s`, 0x12 `ldloca.s`, 0x7B `ldfld`,
// 0x7C `ldflda`, 0xFE 0x16 `constrained.`, 0x6F `callvirt`, 0x2A `ret`. Every token is four bytes.

func ReceiverIlOf(name: string): byte[] {
    assembly := typeof(Counter).get_Assembly()
    for candidate in assembly.GetTypes() {
        found := candidate.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance | BindingFlags.DeclaredOnly)
        if found != null {
            body := found.GetMethodBody()
            if body == null {
                throw new InvalidOperationException("The method '" + name + "' has no IL body to read.")
            }

            il := body.GetILAsByteArray()
            if il == null {
                throw new InvalidOperationException("The method '" + name + "' has an empty IL body.")
            }

            return il
        }
    }

    throw new InvalidOperationException("No method named '" + name + "' was emitted into this assembly.")
}

test "a T field is called through ldflda and constrained., with no box and no copy" {
    il := ReceiverIlOf("Show")
    assert il.Length == 18
    assert il[0] == 2
    assert il[1] == 124
    assert il[6] == 254
    assert il[7] == 22
    assert il[12] == 111
    assert il[17] == 42
}

test "a T parameter is called through ldarga and constrained." {
    il := ReceiverIlOf("ShowParam")
    assert il.Length == 14
    assert il[0] == 15
    assert il[1] == 0
    assert il[2] == 254
    assert il[3] == 22
    assert il[8] == 111
    assert il[13] == 42
}

test "a mutable T field is bumped through ldflda, and a readonly one through a copy's ldloca" {
    mutableIl := ReceiverIlOf("BumpField")
    assert mutableIl[0] == 2
    assert mutableIl[1] == 124
    assert mutableIl[6] == 254
    assert mutableIl[7] == 22

    readonlyIl := ReceiverIlOf("BumpReadonly")
    assert readonlyIl[0] == 2
    assert readonlyIl[1] == 123
    assert readonlyIl[6] == 10
    assert readonlyIl[7] == 18
    assert readonlyIl[9] == 254
    assert readonlyIl[10] == 22
}
