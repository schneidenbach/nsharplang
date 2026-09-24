namespace NSharpLang.Compiler.Columnar

import System
import System.Net.Http
import System.Reflection

func ChtpSetObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func ChtpWritableProperty(receiverType: Type, member: string, seed: PropertyInfo?): object?[] {
    method := typeof(ColumnarIlEmitter).GetMethod(
        "TryGetSupportedBclWritableProperty",
        BindingFlags.Static | BindingFlags.NonPublic
    )
    if method == null {
        throw new InvalidOperationException("The columnar writable-property admission method was not found.")
    }

    arguments := new object?[](3)
    ChtpSetObject(arguments, 0, receiverType)
    ChtpSetObject(arguments, 1, member)
    ChtpSetObject(arguments, 2, seed)
    result := method.Invoke(null, arguments)
    output := new object?[](2)
    ChtpSetObject(output, 0, result)
    ChtpSetObject(output, 1, arguments[2])
    return output
}

// The writable-property admission used to be a TABLE of five APIs, and `HttpClient.Timeout` was one
// row of it — so its SIBLING `BaseAddress`, a public settable instance property of the same type, was
// refused. Admission is ordinary CLR resolution now: the type answers, not the list.
test "an external type's settable instance property is admitted, and the exact handle comes back" {
    timeout := ChtpWritableProperty(typeof(HttpClient), nameof(HttpClient.Timeout), null)
    assert Convert.ToBoolean(timeout[0])
    property := timeout[1] as PropertyInfo
    if property == null {
        throw new InvalidOperationException("HttpClient.Timeout did not return its PropertyInfo.")
    }
    assert property.get_Name() == "Timeout"
    assert property.get_DeclaringType() == typeof(HttpClient)
    assert property.get_PropertyType() == typeof(TimeSpan)
    setter := property.get_SetMethod()
    if setter == null {
        throw new InvalidOperationException("HttpClient.Timeout exposed no public setter.")
    }
    assert !setter.get_IsStatic()

    sentinel := typeof(HttpClient).GetProperty(nameof(HttpClient.Timeout))
    adjacent := ChtpWritableProperty(typeof(HttpClient), nameof(HttpClient.BaseAddress), sentinel)
    assert Convert.ToBoolean(adjacent[0])
    adjacentProperty := adjacent[1] as PropertyInfo
    if adjacentProperty == null {
        throw new InvalidOperationException("HttpClient.BaseAddress did not return its PropertyInfo.")
    }
    assert adjacentProperty.get_Name() == "BaseAddress"
    assert adjacentProperty.get_DeclaringType() == typeof(HttpClient)
}

// WHAT IS STILL REFUSED, and each for a correctness reason rather than for absence from a list: a
// name the type does not declare, a property with no setter, and a VALUE-type receiver, whose write
// would land on the copy the read loaded. Every decline resets the out slot.
test "a missing name, a getter-only property and a value-type receiver are all refused" {
    sentinel := typeof(HttpClient).GetProperty(nameof(HttpClient.Timeout))

    foreign := ChtpWritableProperty(typeof(object), nameof(HttpClient.Timeout), sentinel)
    assert !Convert.ToBoolean(foreign[0])
    assert foreign[1] == null

    getterOnly := ChtpWritableProperty(typeof(HttpClient), nameof(HttpClient.DefaultRequestHeaders), sentinel)
    assert !Convert.ToBoolean(getterOnly[0])
    assert getterOnly[1] == null

    valueReceiver := ChtpWritableProperty(typeof(TimeSpan), nameof(TimeSpan.Ticks), sentinel)
    assert !Convert.ToBoolean(valueReceiver[0])
    assert valueReceiver[1] == null
}
