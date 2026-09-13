namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Reflection

test "a value body may end in a call the signature says never returns" {
    assert PickFree(1) == "positive"
    assert PickQualified(1) == "positive"
    assert Guard.PickInside(1) == "positive"
}

test "and taking that path throws whatever the callee throws" {
    assert throws InvalidOperationException {
        PickFree(0)
    }

    assert throws InvalidOperationException {
        PickQualified(0)
    }

    assert throws InvalidOperationException {
        Guard.PickInside(0)
    }
}

test "one branch may end in a never-returning call while the other returns" {
    assert ClassifyOrFail(3) == "non-zero"
    assert throws InvalidOperationException {
        ClassifyOrFail(0)
    }
}

test "a never-returning call inside a try still runs the finally" {
    marker := new string[](1)
    marker[0] = "none"

    assert throws InvalidOperationException {
        FailAfterCleanup(marker)
    }

    assert marker[0] == "cleaned"
}

test "a DoesNotReturnIf(false) argument narrows the flow that survives the call" {
    assert RequiredPlusOne(41) == 42
    assert RequiredLength("abcd") == 4
}

test "and the branch the attribute named throws instead of returning" {
    assert throws ArgumentException {
        RequiredPlusOne(null)
    }

    assert throws ArgumentException {
        RequiredLength(null)
    }
}

test "a DoesNotReturnIf(true) argument narrows the other way" {
    assert RefusedPlusTwo(5) == 7
    assert throws ArgumentException {
        RefusedPlusTwo(null)
    }
}

test "the attribute reaches the emitted metadata on the method and on the parameter" {
    guardType := typeof(Guard)
    fail := guardType.GetMethod("Fail", BindingFlags.Public | BindingFlags.Static)

    assert fail != null
    assert fail.GetCustomAttributes(true).Length > 0

    require := guardType.GetMethod("Require", BindingFlags.Public | BindingFlags.Static)

    assert require != null

    parameters := require.GetParameters()

    assert parameters.Length == 2
    assert parameters[0].GetCustomAttributes(true).Length > 0
}
