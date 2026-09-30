namespace NSharpLang.CensusEmitShapes.Tests

import System

test "a value method whose last statement is an external [DoesNotReturn] call emits" {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    tail := typeof(Guard).GetMethod("FailFastTail", parameterTypes)
    if tail == null {
        throw new InvalidOperationException("The [DoesNotReturn]-tailed value method was not emitted.")
    }
    assert tail.ReturnType == typeof(int)
}

test "an external [DoesNotReturnIf] parameter narrows the surviving flow" {
    assert Guard.AssertedLength("alpha") == 5
    assert Guard.AssertedTrimmed("  alpha  ") == "alpha"
}
