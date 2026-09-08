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

test "HttpClient Timeout is the exact newly admitted writable property and declines reset the out slot" {
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
    assert !Convert.ToBoolean(adjacent[0])
    assert adjacent[1] == null

    foreign := ChtpWritableProperty(typeof(object), nameof(HttpClient.Timeout), sentinel)
    assert !Convert.ToBoolean(foreign[0])
    assert foreign[1] == null
}
