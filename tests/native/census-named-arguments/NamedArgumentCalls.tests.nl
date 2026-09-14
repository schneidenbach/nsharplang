namespace NSharpLang.CensusNamedArguments

import System
import System.Linq
import System.Reflection
import NSharpLang.CensusNamedArguments.MetadataDefaults

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

test "named constructor arguments may leave optional holes" {
    value := new OptionalConstructorSlots(last: 9)
    assert value.Value == 129
}

test "a constructor overload is still selected beside a named argument" {
    label := new Label(text: "abc")
    assert label.Width == 3
}

test "named instance-method arguments bind by name" {
    label := new Label("mid", 3)
    assert label.Render(suffix: ">", prefix: "<") == "<mid>"
}

test "named instance-method arguments may leave optional holes" {
    value := new OptionalMethodSlots()
    assert value.Read(last: 9) == 129
}

test "named static-method arguments may leave optional holes" {
    assert OptionalStaticSlots.Read(last: 9) == 129
}

test "a derived sparse source method hides its base method" {
    value := new SourceOptionalDerived()
    assert value.Pick(second: 3) == "13derived"
}

test "named arguments bind on extension methods" {
    values: int[] = [1, 2]
    assert values.Contains(value: 2)
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

test "a delegate invoke argument binds by its reflected parameter name" {
    assert InvokeNamed(value: 4, mapper: x => x + 5) == 9
    recorder := new DelegateArgumentRecorder()
    InvokeActionNamed(value: 6, action: recorder.Record)
    assert recorder.Value == 6
    assert InvokeComparisonNamed(left: 2, right: 7, comparison: (x, y) => x - y) == -5
}

test "a params parameter accepts a named direct array" {
    assert ReadParams(values: [4, 2]) == 42
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

test "a reordered out argument preserves its address across later evaluation" {
    target := new ReorderedOutAlias()
    assert target.Parse()
    assert target.Value == 42
}

test "a receiver evaluates before reordered named arguments" {
    recorder := new ReceiverOrderRecorder()
    result := recorder.Receiver().Replace(newValue: recorder.Argument("new", ";"), oldValue: recorder.Argument("old", ","))
    assert result == "a;b"
    assert recorder.Order.Count == 3
    assert recorder.Order[0] == "receiver"
    assert recorder.Order[1] == "new"
    assert recorder.Order[2] == "old"
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

test "explicit generic calls place reordered named arguments before emission" {
    assert GenericFirst<int>(second: 2, first: 40) == 40
}

test "explicit generic calls fill defaults and accept a named params array" {
    assert GenericOptional<int>(first: 40) == 40
    assert GenericParams<int>(values: [1, 2], seed: 40) == 40
    assert GenericParamsCount<int>(seed: 40) == 0
    assert GenericParamsCount<int>(seed: 40, 1, 2) == 2
    values: int[] = [1, 2]
    assert GenericParamsCount<int>(seed: 40, ...values) == 2
}

test "explicit generic ref and out arguments preserve storage and assignment" {
    recorder := new GenericNamedRecorder()
    assert recorder.Set() == 42
    assert recorder.Value == 42
    assert recorder.Order.Count == 1
    assert recorder.Order[0] == "value"

    let result: int
    GenericSetOut<int>(value: 42, target: out result)
    assert result == 42
}

test "a generic source owner keeps enclosing and method type arguments distinct" {
    owner := new GenericNamedOwner<string>()
    assert owner.Pick<int>(value: owner.NoteValue("value", 42), owner: owner.NoteOwner("owner", "text")) == 42
    assert owner.Order.Count == 2
    assert owner.Order[0] == "value"
    assert owner.Order[1] == "owner"
}

test "attribute constructor arguments bind by name" {
    found := typeof(NamedAttributeTarget).GetCustomAttribute(typeof(ObsoleteAttribute), false) as ObsoleteAttribute
    assert found != null
    assert found.Message == "named attribute"
    assert found.IsError
    assert found.DiagnosticId == "named-id"
}

test "source attribute constructor arguments may leave optional holes" {
    found := typeof(SparseAttributeTarget).GetCustomAttribute(typeof(SparseAttribute), false) as SparseAttribute
    assert found != null
    assert found.First == 1
    assert found.Middle == 2
    assert found.Last == 9
}

test "named arguments fill optional holes from referenced metadata" {
    fixtureType := typeof(ReflectedOptionalSlots)
    assert fixtureType.Assembly != typeof(NamedAttributeTarget).Assembly
    reflected := fixtureType.GetMethod("Read")
    assert reflected != null
    parameters := reflected.GetParameters()
    assert parameters.Length == 3
    assert parameters[0].get_IsOptional()
    assert Convert.ToInt32(parameters[0].get_DefaultValue()) == 1
    assert parameters[1].get_IsOptional()
    assert Convert.ToInt32(parameters[1].get_DefaultValue()) == 2
    value := new ReflectedOptionalSlots(last: 9)
    assert value.Value == 129
    assert value.Read(last: 8) == 128
    assert ReflectedOptionalSlots.ReadStatic(last: 7) == 127
}

test "a sparse reflected constructor keeps ordinary overload specificity" {
    value := new ReflectedSparseConstructorChoice(value: "text")
    assert value.Kind == "comparable"
}

test "a sparse reflected constructor preserves a named ref address across later evaluation" {
    recorder := new SparseConstructorOrderRecorder()
    value := recorder.Build()
    assert value.Seen == 927
    assert recorder.Value == 927
}

test "a sparse source constructor carries out metadata through reordered arguments" {
    let result: int
    value := new SourceSparseOutConstructor(target: out result, last: 7)
    assert result == 27
    assert value.Value == 27
}

test "a derived sparse metadata method hides its base method" {
    value := new ReflectedOptionalDerived()
    assert value.Pick(second: 3) == "13derived"
}

test "this constructor chains place named arguments and fill optional holes" {
    value := new SourceThisChain("chain")
    assert value.Value == 229
}

test "source base constructor chains place named arguments and fill optional holes" {
    value := new SourceBaseChain()
    assert value.Value == 428
}

test "reflected base constructor chains place named arguments and fill optional holes" {
    value := new ReflectedBaseChain()
    assert value.Value == 527
}
