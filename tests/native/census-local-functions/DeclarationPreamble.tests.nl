namespace NSharpLang.CensusLocalFunctions.Tests

import System
import System.Reflection
import System.Threading.Tasks


// RUNTIME contracts for the declaration preamble, beside `DeclarationPreamble.nl`.
//
// The failure these pin produced no diagnostic at all: a function that follows an expression-bodied
// one whose body is an `async` lambda inherited the `async`, and the `throw` its local function
// raised became a faulted task nobody awaited. So the assertions are about behaviour — the exception
// arriving at the caller — and about the SIGNATURE reflection reports, because the wrap is the thing
// the analyzer and `build` both called clean.
class PreambleFacts {
    static func Holder(): Type {
        marker: Type = typeof(PreambleFacts)
        assembly := marker.get_Assembly()
        return assembly.GetType("NSharpLang.CensusLocalFunctions.Tests.Program")
    }

    static func Method(name: string): MethodInfo {
        holder := Holder()
        if holder == null {
            return null
        }

        return holder.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    }

    static func ReturnType(name: string): Type {
        method := Method(name)
        if method == null {
            return null
        }

        return method.ReturnType
    }

    // Run `body` and hand back the exception it raised, or null if it raised none. A function that
    // wrongly became `async` raises nothing here — its exception left on a task instead.
    static func Raised(body: Func<string>): Exception {
        let caught: Exception? = null
        try {
            produced := body()
            print produced
        } catch e: Exception {
            caught = e
        }

        return caught
    }
}

test "a local function's throw survives an arrow-bodied async-lambda factory above it" {
    raised := PreambleFacts.Raised(() => RequiredAfterAsyncArrow(null))
    assert raised != null
    assert raised is ArgumentNullException
    assert RequiredAfterAsyncArrow("kept") == "kept"
}

test "the async lambda that used to leak still builds the task it always did" {
    factory := AsyncArrowFactory()
    assert await factory() == 1

    blockFactory := AsyncArrowBlockFactory()
    assert await blockFactory() == 3

    plainFactory := AsyncBlockFactory()
    assert await plainFactory() == 4

    syncFactory := SyncArrowFactory()
    assert syncFactory() == 2
}

test "every local-function body around the leak site throws and returns as written" {
    assert PreambleFacts.Raised(() => RequiredAfterSyncArrow(null)) is ArgumentNullException
    assert RequiredAfterSyncArrow("sync") == "sync"

    assert PreambleFacts.Raised(() => RequiredAfterAsyncArrowBlock(null)) is ArgumentNullException
    assert RequiredAfterAsyncArrowBlock("block") == "block"

    assert PreambleFacts.Raised(() => RequiredBeforeArrowFactories(null)) is ArgumentNullException
    assert RequiredBeforeArrowFactories("before") == "before"

    assert PreambleFacts.Raised(() => RequiredAfterAsyncBlock(null)) is ArgumentNullException
    assert RequiredAfterAsyncBlock("after") == "after"
}

test "a capturing local function after the leak site throws and reads its capture" {
    assert PreambleFacts.Raised(() => CapturingRequiredAfterAsyncArrow("p-", null)) is ArgumentNullException
    assert CapturingRequiredAfterAsyncArrow("p-", "v") == "p-v"
}

// CLR METADATA. The wrap is what a reader of the source could not see: the declared return type is
// `string`, and an inherited `async` would have made it `ValueTask<string>`.
test "a function after an arrow-bodied async-lambda factory keeps its declared return type" {
    assert PreambleFacts.ReturnType("RequiredAfterAsyncArrow") == typeof(string)
    assert PreambleFacts.ReturnType("RequiredAfterSyncArrow") == typeof(string)
    assert PreambleFacts.ReturnType("RequiredAfterAsyncArrowBlock") == typeof(string)
    assert PreambleFacts.ReturnType("CapturingRequiredAfterAsyncArrow") == typeof(string)
    assert PreambleFacts.ReturnType("RequiredAfterAsyncBlock") == typeof(string)
    assert PreambleFacts.ReturnType("AfterConstrainedArrow") == typeof(int)
}

// THE OTHER HALF OF THE RULE: a modifier a declaration after an arrow body really does write still
// reaches it. Ending the run at the body must not eat the next declaration's own preamble.
test "a declared async function after an arrow-bodied function is still async" {
    assert PreambleFacts.ReturnType("DeclaredAsyncAfterArrow") == typeof(ValueTask<int>)
    assert await DeclaredAsyncAfterArrow() == 6
    assert ArrowBeforeAsyncFunction() == 5
}

test "an attribute on a function after an arrow-bodied function still reaches it" {
    method := PreambleFacts.Method("AttributedAfterArrow")
    assert method != null

    obsolete := method.GetCustomAttribute(typeof(ObsoleteAttribute)) as ObsoleteAttribute
    assert obsolete != null
    assert obsolete.Message == "pinned by the preamble contract"
    assert AttributedAfterArrow() == 8
    assert ArrowBeforeAttributedFunction() == 7
}

test "an expression-bodied function with a constraint clause does not swallow the rest of the file" {
    assert ConstrainedArrow<string>("held") == "held"
    assert AfterConstrainedArrow() == 9
}
