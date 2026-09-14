namespace NSharpLang.CensusNamedArguments

import System

test "a free function's single parameter can be written by name" {
    assert Gate(flag: true) == 1
    assert Gate(flag: false) == 0
}

test "named arguments in the declared order bind to the parameters they name" {
    assert Divide(numerator: 10, denominator: 2) == 5
}

test "named arguments bind by name even when written out of the declared order" {
    assert Divide(denominator: 2, numerator: 10) == 5
    assert Between(high: 9, low: 1, value: 5)
    assert !Between(high: 4, low: 1, value: 5)
}

test "a positional argument fills the next parameter no name has claimed" {
    assert Divide(10, denominator: 5) == 2
    assert Between(5, high: 9, low: 1)
}

test "a named argument reaches a parameter that also declares a default" {
    assert Indent(text: "x", width: 4) == "    x"
    assert Indent(width: 1, text: "x") == " x"
}

test "named arguments may omit optional parameters between supplied slots" {
    assert OptionalSlots(last: 9) == 129
    assert OptionalSlots(first: 4, last: 9) == 429
}

test "out-of-order named arguments evaluate in the order they were written" {
    recorder := new CallRecorder()
    quotient := Divide(denominator: recorder.Note("denominator", 2), numerator: recorder.Note("numerator", 10))
    assert quotient == 5
    assert recorder.Order.Count == 2
    assert recorder.Order[0] == "denominator"
    assert recorder.Order[1] == "numerator"
}

test "a three-argument rotation evaluates in the written order and still binds by name" {
    recorder := new CallRecorder()
    inside := Between(high: recorder.Note("high", 9), value: recorder.Note("value", 5), low: recorder.Note("low", 1))
    assert inside
    assert recorder.Order.Count == 3
    assert recorder.Order[0] == "high"
    assert recorder.Order[1] == "value"
    assert recorder.Order[2] == "low"
}

test "named constructor arguments bind by name" {
    label := new Label(width: 4, text: "ok")
    assert label.Text == "ok"
    assert label.Width == 4
}

test "a constructor overload is still selected beside a named argument" {
    label := new Label(text: "abc")
    assert label.Width == 3
}

test "named instance-method arguments bind by name" {
    label := new Label("mid", 3)
    assert label.Render(suffix: ">", prefix: "<") == "<mid>"
}

test "named static-method arguments bind by name" {
    label := Label.Of(width: 7, text: "s")
    assert label.Width == 7
    assert label.Text == "s"
}

test "named argument placement participates in overload applicability" {
    picker := new NamedOverloadPicker()
    assert picker.Pick(left: 7, right: "text") == "text7second"
}

test "a lambda argument can be named" {
    assert ApplyTwice(value: 1, mapper: x => x + 3) == 7
}

test "a named out argument still passes storage" {
    half := 0
    assert TryHalve(value: 8, out half)
    assert half == 4
    assert !TryHalve(value: 7, out half)
}

test "a named out argument on an external member still passes storage" {
    parsed := 0
    assert Int32.TryParse("42", result: out parsed)
    assert parsed == 42
}

test "named arguments bind on an external instance member" {
    assert "a,b,c".Replace(oldValue: ",", newValue: ";") == "a;b;c"
    assert "a,b,c".Replace(newValue: ";", oldValue: ",") == "a;b;c"
}

test "named arguments bind on an external static member" {
    assert String.Concat(str1: "b", str0: "a") == "ab"
    assert Math.Max(val2: 3, val1: 9) == 9
}

test "a named argument names the parameter, so the emitted call keeps the declared parameter order" {
    method := typeof(Divide2Holder).GetMethod("Divide")
    assert method != null
    parameters := method.GetParameters()
    assert parameters.Length == 2
    assert parameters[0].Name == "numerator"
    assert parameters[1].Name == "denominator"
}

class Divide2Holder {
    static func Divide(numerator: int, denominator: int): int {
        return numerator / denominator
    }
}

test "a named argument on a static method of a source type binds by name" {
    assert Divide2Holder.Divide(denominator: 4, numerator: 20) == 5
}
