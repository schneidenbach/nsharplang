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

    visibleCallables := BindingNames("visibleCallable")
    bindings := new ColumnarFragmentBindings(
        parameterOrdinals,
        parameterTypes,
        locals,
        enums,
        BindingNames("lifted"),
        BindingNames("boxed"),
        BindingNames("enclosing"),
        BindingNames("callable"),
        visibleCallables)

    assert bindings.ParameterOrdinals["parameter"] == 0
    assert bindings.ParameterTypes["parameter"] == typeof(int)
    assert bindings.IsValueBinding("parameter")
    assert bindings.IsBlocked("lifted")
    assert bindings.IsBlocked("boxed")
    assert bindings.IsBlocked("enclosing")
    assert !bindings.IsBlocked("parameter")
    assert bindings.IsCallable("callable")
    assert bindings.IsCallable("visibleCallable")
    assert !bindings.IsCallable("parameter")
}

test "fragment bindings observe live shadow and textual-callable sources" {
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    locals := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    enums := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
    lifted := new HashSet<string>(StringComparer.Ordinal)
    boxed := new HashSet<string>(StringComparer.Ordinal)
    enclosing := new HashSet<string>(StringComparer.Ordinal)
    declaredCallables := new HashSet<string>(StringComparer.Ordinal)
    visibleCallables := new HashSet<string>(StringComparer.Ordinal)

    bindings := new ColumnarFragmentBindings(
        parameterOrdinals,
        parameterTypes,
        locals,
        enums,
        lifted,
        boxed,
        enclosing,
        declaredCallables,
        visibleCallables)

    assert !bindings.IsBlocked("laterLifted")
    assert !bindings.IsBlocked("laterBoxed")
    assert !bindings.IsBlocked("laterEnclosing")
    assert !bindings.IsCallable("laterDeclared")
    assert !bindings.IsCallable("laterVisible")

    lifted.Add("laterLifted")
    boxed.Add("laterBoxed")
    enclosing.Add("laterEnclosing")
    declaredCallables.Add("laterDeclared")
    visibleCallables.Add("laterVisible")

    assert bindings.IsBlocked("laterLifted")
    assert bindings.IsBlocked("laterBoxed")
    assert bindings.IsBlocked("laterEnclosing")
    assert bindings.IsCallable("laterDeclared")
    assert bindings.IsCallable("laterVisible")

    parameterOrdinals["laterParameter"] = 2
    parameterTypes["laterParameter"] = typeof(Index)
    assert bindings.IsValueBinding("laterParameter")
}
