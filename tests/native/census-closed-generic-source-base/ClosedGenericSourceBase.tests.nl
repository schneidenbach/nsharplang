namespace NSharpLang.CensusClosedGenericSourceBase.Tests

import System
import System.Collections.Generic
import System.Reflection

test "the program prints every inherited member through its closed base" {
    expected := new System.Text.StringBuilder()
    expected.AppendLine("holder")
    expected.AppendLine("holder")
    expected.AppendLine("holder")
    expected.AppendLine("42")
    expected.AppendLine("7")
    expected.AppendLine("7")
    expected.AppendLine("7")
    expected.AppendLine("kind:Int32")
    expected.AppendLine("kind:Int32")
    expected.AppendLine("holder/kind:List`1/2/2/2")
    expected.AppendLine("holder:kind:String")

    assert Transcript() == expected.ToString()
}

test "a bare call and a this call bind the method the closed base declares" {
    holder := new IntHolder(7)

    assert holder.BareCall() == "holder"
    assert holder.ThisCall() == "holder"
    // The same member reached from OUTSIDE, through an `IntHolder` value rather than `this`.
    assert holder.Describe() == "holder"
}

test "an inherited method's signature is substituted with the base's arguments" {
    holder := new IntHolder(7)

    assert holder.BareEcho() == 42
    assert holder.Echo(5) == 5
}

test "an inherited property reads the same storage bare, through this and through base" {
    holder := new IntHolder(9)

    assert holder.BareProperty() == 9
    assert holder.ThisProperty() == 9
    assert holder.BaseProperty() == 9
    assert holder.Value == 9
    assert holder.BareField() == 9
}

test "an inherited static method runs under the closed base's type argument" {
    holder := new IntHolder(1)

    assert holder.BareStaticCall() == "kind:Int32"
    assert IntHolder.Kind() == "kind:Int32"
    assert Holder<string>.Kind() == "kind:String"
}

test "an inherited static field and property are the closed base's own storage" {
    holder := new IntHolder(1)

    holder.WriteBareStaticField(5)

    assert holder.BareStaticField() == 5
    assert holder.BareStaticProperty() == 5
    assert IntHolder.Made == 5
    assert Holder<int>.Made == 5
    // `Holder<string>` is a different instantiation with its own slot. A write through the open
    // definition's token could not have been read back through `Holder<int>` at all.
    assert Holder<string>.Made == 0
}

test "a two-link chain closes each base over the link below it" {
    items := new List<string>()
    items.Add("x")

    leaf := new Leaf(items)

    assert leaf.Deep() == "holder/kind:List`1/1/1/1"
    assert leaf.DeepBase() == 1
    assert leaf.MidKind() == "kind:List`1"
    assert leaf.Describe() == "holder"
}

test "a generic derived type calls its base through its own type parameter" {
    wrapper := new Wrapper<int>(3)

    assert wrapper.Wrapped() == "holder:kind:Int32"
    assert wrapper.WrappedValue() == 3
    assert wrapper.Round(8) == 8
    assert new Wrapper<string>("s").Round("t") == "t"
}

test "the emitted call names the closed base, not the open definition or the derived type" {
    bare := CalledMethods(typeof(IntHolder), "BareCall")
    assert bare.Count == 1
    assert bare[0].Name == "Describe"
    assert bare[0].DeclaringType == typeof(Holder<int>)

    viaThis := CalledMethods(typeof(IntHolder), "ThisCall")
    assert viaThis.Count == 1
    assert viaThis[0].Name == "Describe"
    assert viaThis[0].DeclaringType == typeof(Holder<int>)

    propertyRead := CalledMethods(typeof(IntHolder), "BareProperty")
    assert propertyRead.Count == 1
    assert propertyRead[0].Name == "get_Value"
    assert propertyRead[0].DeclaringType == typeof(Holder<int>)

    staticCall := CalledMethods(typeof(IntHolder), "BareStaticCall")
    assert staticCall.Count == 1
    assert staticCall[0].DeclaringType == typeof(Holder<int>)
}

// The methods a body calls, read off its IL: every `call` (0x28) or `callvirt` (0x6F) operand that
// resolves to a method. The bodies read here are a handful of bytes, so a byte scan that keeps only
// operands the module resolves is exact for them.
func CalledMethods(owner: Type, name: string): List<MethodBase> {
    result := new List<MethodBase>()
    method := owner.GetMethod(name)
    assert method != null
    body := method.GetMethodBody()
    assert body != null
    il := body.GetILAsByteArray()
    assert il != null

    index := 0
    while index + 4 < il.Length {
        opcode := (int)il[index]
        resolved: MethodBase? = null
        if opcode == 40 || opcode == 111 {
            resolved = TryResolveMethod(owner.Module, BitConverter.ToInt32(il, index + 1))
        }
        if resolved != null {
            result.Add(resolved)
            index = index + 5
        } else {
            index = index + 1
        }
    }

    return result
}

// A byte that merely looks like a call opcode carries an operand that is no method token, and the
// module says so by throwing; that byte is not a call.
func TryResolveMethod(module: Module, token: int): MethodBase? {
    try {
        return module.ResolveMethod(token)
    } catch ex: ArgumentException {
        return null
    }
}
