namespace NSharpLang.CensusEmitShapes.Tests

import System
import System.Reflection
import NSharpLang.CensusEmitShapes

test "a coalesce fallback that throws raises the exception the source named" {
    probe := new ThrowProbe()
    assert RequiredName(probe, "ada") == "ada"
    assert throws InvalidOperationException {
        RequiredName(probe, null)
    }
}

test "the coalesce left operand is evaluated exactly ONCE on both paths" {
    probe := new ThrowProbe()
    present := RequiredName(probe, "ada")
    assert present == "ada"
    assert probe.Reads == 1

    assert throws InvalidOperationException {
        RequiredName(probe, null)
    }

    assert probe.Reads == 2
}

test "a Nullable<T> coalesce fallback that throws raises on the absent value only" {
    assert RequiredPort(8080) == 8080
    assert throws InvalidOperationException {
        RequiredPort(null)
    }
}

test "an open type parameter coalesce fallback that throws keeps T as the result" {
    assert RequiredValue<string>("here") == "here"
    assert RequiredValue<int>(3) == 3
    absent: string? = null
    assert throws InvalidOperationException {
        RequiredValue<string?>(absent)
    }
}

test "only the TAKEN conditional arm runs, whichever arm is the throw" {
    probe := new ThrowProbe()
    assert PortOrFail(probe, true, "p") == "p"
    assert probe.Reads == 1
    assert throws ArgumentException {
        PortOrFail(probe, false, "p")
    }

    assert probe.Reads == 1

    mirror := new ThrowProbe()
    assert FailOrPort(mirror, false, "q") == "q"
    assert mirror.Reads == 1
    assert throws ArgumentException {
        FailOrPort(mirror, true, "q")
    }

    assert mirror.Reads == 1
}

test "an arrow body that is a throw raises with the message it was given" {
    caught := false
    message := ""
    try {
        NotImplementedYet()
    } catch e: NotImplementedException {
        caught = true
        message = e.Message
    }

    assert caught
    assert message == "later"
}

test "an arrow body that coalesces into a throw keeps both paths" {
    assert TrimmedOrFail("x") == "x"
    assert throws InvalidOperationException {
        TrimmedOrFail(null)
    }
}

test "an arrow-bodied PROPERTY may coalesce into a throw" {
    present := new Settings("configured")
    assert present.Name == "configured"

    absent := new Settings(null)
    assert throws InvalidOperationException {
        ignored := absent.Name
        print ignored
    }
}

test "a lambda whose expression body is a throw raises when it is invoked, not when it is built" {
    rejector := Rejector()
    assert rejector != null
    caught := false
    message := ""
    try {
        rejector(7)
    } catch e: NotSupportedException {
        caught = true
        message = e.Message
    }

    assert caught
    assert message == "rejected 7"
}

test "a void arrow body and a void-delegate lambda may both be a throw" {
    assert throws NotSupportedException {
        AlwaysFails()
    }

    rejector := VoidRejector()
    assert throws NotSupportedException {
        rejector()
    }
}

test "a void arrow body that throws is emitted with a void return type" {
    fails := FindStatic("AlwaysFails")
    assert fails != null
    assert fails.ReturnType.FullName == "System.Void"
}

test "an async body's coalesce throw faults the RETURNED task rather than the caller" {
    completed := LoadName("ada")
    assert completed.Result == "ada"

    faulted := LoadName(null)
    caught := false
    try {
        faulted.Wait()
    } catch e: AggregateException {
        caught = e.InnerException is InvalidOperationException
    }

    assert caught
}

test "an async lambda whose expression body is a throw faults its own task" {
    rejector := AsyncRejector()
    task := rejector()
    caught := false
    try {
        task.Wait()
    } catch e: AggregateException {
        caught = e.InnerException is NotSupportedException
    }

    assert caught
}

test "the lowering is the ordinary one inside a local function too" {
    assert ThroughLocalFunction("v") == "v"
    assert throws InvalidOperationException {
        ThroughLocalFunction(null)
    }
}

test "a conditional throw nested inside a coalesce fallback keeps both branch structures" {
    assert Nested("primary", null, false) == "primary"
    assert Nested(null, "secondary", true) == "secondary"
    assert Nested(null, null, true) == "default"
    assert throws ArgumentException {
        Nested(null, "secondary", false)
    }
}

// THE CLR METADATA SIDE. A throw expression changes no signature: the members below are emitted with
// exactly the return types their sources declare, and the arrow-bodied ones are ordinary methods —
// nothing about "this body only throws" is visible from outside.
test "a member whose body only throws keeps the declared return type in its metadata" {
    notImplemented := FindStatic("NotImplementedYet")
    assert notImplemented != null
    assert notImplemented.ReturnType == typeof(string)
    assert notImplemented.GetParameters().Length == 0

    portMethod := FindStatic("RequiredPort")
    assert portMethod != null
    assert portMethod.ReturnType == typeof(int)
}

test "an arrow-bodied property that throws is still an ordinary property with a getter" {
    property := typeof(Settings).GetProperty("Name")
    assert property != null
    assert property.PropertyType == typeof(string)
    assert property.CanRead
    getter := property.GetGetMethod()
    assert getter != null
    assert getter.ReturnType == typeof(string)
}

func FindStatic(name: string): MethodInfo? {
    assembly := typeof(Settings).Assembly
    for candidate in assembly.GetTypes() {
        method := candidate.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
        if method != null {
            return method
        }
    }

    return null
}
