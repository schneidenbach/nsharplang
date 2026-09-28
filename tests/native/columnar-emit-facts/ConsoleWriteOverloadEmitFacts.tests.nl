namespace NSharpLang.ColumnarEmitFacts.Tests

// `Console.Write` AND `Console.WriteLine` ARE ORDINARY STATIC CALLS.
//
// A call the direct-call planner cannot type whole used to reach a hand-written `Console` arm that
// bound `WriteLine(string)`, emitted the argument, and only then checked that the argument WAS a
// string. A `bool` or a `double` argument failed that check with its IL already written, so the arm
// answered no and the statement declined at `emit.expression-statement.call`: `x != null` over a
// `Capture` read through an external indexer, or `.TotalSeconds` over a sum of two
// `ConcurrentDictionary<string, TimeSpan>` reads. Binding the argument to a local first compiled,
// because the planner types a local.
//
// The arm is gone. These calls take the same ordinary static resolution every other external static
// does, which chooses among `WriteLine`'s overloads from the argument's type. Each program runs in its
// own child process, so the output asserted here is the emitted program's, and nothing in this test
// process writes to the console.
test "Console.WriteLine of a null test over an external indexer read prints the boolean" {
    EmitterCanonicalAssertProgramNormalized(
        "ConsoleWriteNullTest",
        """
import System
import System.Text.RegularExpressions

func main() {
    found := Regex.Match("k=v", "(?<k>k)=v")
    present := found.Groups["k"] as Capture
    Console.WriteLine(present != null)
    Console.Write(present == null)
    Console.WriteLine("")
}
""",
        "True\nFalse"
    )
}

test "Console.WriteLine of a double read off a sum of dictionary values prints the double" {
    EmitterCanonicalAssertProgramNormalized(
        "ConsoleWriteDictionarySum",
        """
import System
import System.Collections.Concurrent

func main() {
    durations := new ConcurrentDictionary<string, TimeSpan>()
    durations["a"] = TimeSpan.FromSeconds(1.5)
    durations["b"] = TimeSpan.FromSeconds(2.5)
    Console.WriteLine((durations["a"] + durations["b"]).TotalSeconds)
    Console.Write((durations["a"] + durations["b"]).TotalSeconds)
    Console.WriteLine("")
}
""",
        "4\n4"
    )
}

test "Console.WriteLine of a string read the planner does not type still binds the string overload" {
    EmitterCanonicalAssertProgramNormalized(
        "ConsoleWriteStringRead",
        """
import System
import System.Text.RegularExpressions

func main() {
    found := Regex.Match("k=v", "(?<k>k)=v")
    present := found.Groups["k"] as Capture
    Console.WriteLine(present?.Value ?? "missing")
    Console.Write(found.Groups["k"].Value)
    Console.WriteLine("")
}
""",
        "k\nk"
    )
}

// A static the direct-call planner leaves to the emitter — one with an `in` parameter — has to be
// TYPED before `WriteLine` can choose an overload for it, whether it is the argument itself or the
// receiver of the `ToString()` that is. The arm that answered `WriteLine(string)` without asking hid
// that the static had no preflight answer at all.
test "Console.WriteLine of a static with an in parameter chooses the overload its result needs" {
    EmitterCanonicalAssertProgramNormalized(
        "ConsoleWriteInParameterStatic",
        """
import System

struct Pair {
    A: double
    B: double
}

class Measure {
    static func Product(in p: Pair): double {
        return p.A * p.B
    }
}

func main() {
    p := new Pair { A: 2.0, B: 3.0 }
    Console.WriteLine(Measure.Product(p))
    Console.WriteLine(Measure.Product(in p))
    Console.WriteLine("product = " + Measure.Product(p).ToString())
}
""",
        "6\n6\nproduct = 6"
    )
}
