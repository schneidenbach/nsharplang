namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection.Emit

func BindingNames(first: string): List<string> {
    names := new List<string>()
    names.Add(first)
    return names
}

test "fragment bindings preserve raw maps and blocked-name precedence" {
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterOrdinals["parameter"] = 0
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameterTypes["parameter"] = typeof(int)
    locals := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    enums := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)

    bindings := new ColumnarFragmentBindings(
        parameterOrdinals,
        parameterTypes,
        locals,
        enums,
        BindingNames("lifted"),
        BindingNames("boxed"),
        BindingNames("enclosing"),
        BindingNames("callable"))

    assert bindings.ParameterOrdinals["parameter"] == 0
    assert bindings.ParameterTypes["parameter"] == typeof(int)
    assert bindings.IsValueBinding("parameter")
    assert bindings.IsBlocked("lifted")
    assert bindings.IsBlocked("boxed")
    assert bindings.IsBlocked("enclosing")
    assert !bindings.IsBlocked("parameter")
    assert bindings.IsCallable("callable")
    assert !bindings.IsCallable("parameter")
}
