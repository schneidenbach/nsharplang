namespace NSharpLang.CensusEmitShapes.Tests

import System.Reflection

test "an array widens to its nullable-element view, and the view is the same array object" {
    values: string[] = ["a", "b"]
    widened := WidenStrings(values)
    assert widened.Length == 2
    assert widened[0] == "a"
    assert Object.ReferenceEquals(widened, values)
    assert CountNonNull(values) == 2
}

test "the object[] widening is the one MethodInfo.Invoke's object?[]? parameter needs" {
    objects: object[] = [1, "two"]
    widened := WidenObjects(objects)
    assert widened.Length == 2
    assert Object.ReferenceEquals(widened, objects)
}

test "the widened view is the same CLR array type, so the conversion emits no copy" {
    values: string[] = ["a"]
    widened := WidenStrings(values)
    assert (widened as object).GetType() == typeof(string[])
}

test "an object[] argument reaches a BCL parameter declared object?[]?" {
    method := typeof(string).GetMethod("Substring", [typeof(int), typeof(int)])
    assert method != null
    arguments: object[] = [1, 3]
    assert InvokeThrough(method, "abcdef", arguments) as string == "bcd"
}
