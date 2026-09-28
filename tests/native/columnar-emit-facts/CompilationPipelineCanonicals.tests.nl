namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.IO
import System.Reflection


// These controls preserve the compiler-facing assertions that surround emission: route refusal,
// analysis-before-emit failures, persisted assembly metadata, decline diagnostics, and preprocessing.
// Each still uses the public MultiFileCompiler entry point and cleans its fixture in a finally block.
test "MultiFileCompiler_ExperimentalSoaDoesNotFallbackToIlWhenColumnarRouteDeclines" {
    compilation := EmitterCanonicalCompileWithSetting(
        "SoaFallbackProject",
        "exe",
        """
soa record NodeTable {
    kind: int
    start: int
}

func main() {
    nodes := new NodeTable(1)
    row := nodes.add()
    nodes[row].kind = 7
    nodes[row].start = 9
    print nodes[row].kind + nodes[row].start + nodes.length
}
""",
        "SoaEnabled",
        true
    )
    try {
        assert !compilation.Succeeded
        assert compilation.OutputAssemblyPath == null
        assert !File.Exists(compilation.OutputPath)
        assert EmitterCanonicalHasErrorText(
            compilation,
            "Message",
            "Columnar SoA emission is required"
        )
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "MultiFileCompiler_ReportsBadReflectionCallBeforeIlEmission" {
    compilation := EmitterCanonicalCompileSingle(
        "BadReflectionCall",
        "exe",
        """
func main() {
    greeting := "hello"
    greeting.CompareTo()
}
"""
    )
    try {
        assert !compilation.Succeeded
        assert EmitterCanonicalHasErrorValue(compilation, "Code", "NoMatchingOverload")
        assert !EmitterCanonicalHasErrorText(compilation, "Message", "Failed to emit IL assembly")
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "MultiFileCompiler_RejectsGenericCollectionFieldInitializerMismatch" {
    compilation := EmitterCanonicalCompileSingle(
        "InitializerMismatch",
        "library",
        """
record Pt {
    X: int
}

record Rs {
    S: string
}

record H {
    Items: List<Pt>
}

func f(): int {
    l := new List<Rs>()
    l.Add(new Rs { S: "abc" })
    h := new H { Items: l }
    return h.Items[0].X
}
"""
    )
    try {
        assert !compilation.Succeeded
        assert EmitterCanonicalHasError(compilation, "TypeMismatch", "List<Pt>", "List<Rs>")
        assert !EmitterCanonicalHasErrorText(compilation, "Message", "Failed to emit IL assembly")
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "MultiFileCompiler_EmitsIlAssemblyWithSdkCompatibleVersion" {
    fileNames := new string[](1)
    contents := new string[](1)
    fileNames[0] = "Library.nl"
    contents[0] = """
namespace Versioned

class Greeter {
    static func Message(): string {
        return "hello"
    }
}
"""
    projectYml := "name: VersionedIlProject\nversion: 1.2.0-beta.1\nbackend: il\noutputType: library\ntargetFramework: net10.0"
    compilation := EmitterCanonicalCompile(
        "VersionedIlProject",
        projectYml,
        fileNames,
        contents,
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        version := AssemblyName.GetAssemblyName(compilation.OutputPath).get_Version()
        if version == null {
            throw new InvalidOperationException("The emitted assembly had no version")
        }
        assert version.ToString() == "1.2.0.0"
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

// THE FIXTURE SHAPE IS A DECLINING ONE, AND WHICH ONE IS INCIDENTAL. These three rows are about the
// REPORT — its site, its message, the file it lands in and the span it covers — so they need any
// shape the backend refuses, and they say which one they used only because the span has to be counted
// from it. TWO EXPRESSIONS HAVE ALREADY BEEN OUTGROWN HERE: `value.GetType().AssemblyQualifiedName`
// stopped declining when ordinary CLR member resolution began answering a member read off a call
// RESULT, and `value.GetType().GUID.ToString()` stopped when the same tier reached one rung further.
// A shape that merely happens to be unreached today is therefore the wrong fixture.
//
// `lanes: Vector<int>[]` is chosen instead because it is a WRITTEN-DOWN limit: an array of a
// constructed external value-type generic is the first bullet under "Current limits" in
// `website/docs/types.md`, so the day it starts compiling is a day the documentation changes with it
// and these rows are revisited on purpose rather than by surprise. The decline site moves with it —
// a typed LOCAL declaration rather than a return expression — and nothing else about the rows does.
test "CompileToIlAssembly_SingleFileDeclineReportsReasonAndSpan" {
    compilation := EmitterCanonicalCompileSingle(
        "SingleDecline",
        "library",
        """
import System.Numerics

func TypeName(value: string): string? {
    lanes: Vector<int>[] = []
    return value + lanes.Length.ToString()
}
"""
    )
    try {
        error := EmitterCanonicalFindSingleError(compilation, "DiagnosticId", "NL103")
        assert !compilation.Succeeded
        assert EmitterCanonicalErrorText(error, "Message").Contains(
            "Declined at emit.typed-local.unsupported-type: typed local declaration type is not supported for 'lanes': Vector<int>[] in 'TypeName' (Program.nl:4:5).",
            StringComparison.Ordinal
        )
        assert Path.GetFullPath(EmitterCanonicalErrorText(error, "FileName")) == Path.GetFullPath(
            Path.Combine(compilation.FixtureRoot, "Program.nl")
        )
        assert EmitterCanonicalErrorInt(error, "Line") == 4
        assert EmitterCanonicalErrorInt(error, "Column") == 5
        assert EmitterCanonicalErrorInt(error, "Length") == 25
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_TwoFileDeclineMapsMergedOffsetToOwningFile" {
    fileNames := new string[](2)
    contents := new string[](2)
    fileNames[0] = "First.nl"
    contents[0] = "func Keep(): int {\n    return 1\n}"
    fileNames[1] = "Second.nl"
    contents[1] = "import System.Numerics\n\nfunc TypeName(value: string): string? {\n    lanes: Vector<int>[] = []\n    return value + lanes.Length.ToString()\n}"
    compilation := EmitterCanonicalCompile(
        "TwoFileDecline",
        EmitterCanonicalProjectYml("TwoFileDecline", "library"),
        fileNames,
        contents,
        true
    )
    try {
        error := EmitterCanonicalFindSingleError(compilation, "DiagnosticId", "NL103")
        assert !compilation.Succeeded
        assert EmitterCanonicalErrorText(error, "Message").Contains("(Second.nl:4:5).", StringComparison.Ordinal)
        assert Path.GetFullPath(EmitterCanonicalErrorText(error, "FileName")) == Path.GetFullPath(
            Path.Combine(compilation.FixtureRoot, "Second.nl")
        )
        assert EmitterCanonicalErrorInt(error, "Line") == 4
        assert EmitterCanonicalErrorInt(error, "Column") == 5
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_TestDeclarationDeclineReportsDeclarationScanReason" {
    fileNames := new string[](1)
    contents := new string[](1)
    fileNames[0] = "Program.tests.nl"
    contents[0] = """
setup {
    x := 1
}

test "x" {
    assert 1 == 1
}
"""
    compilation := EmitterCanonicalCompile(
        "TestDeclDecline",
        EmitterCanonicalProjectYml("TestDeclDecline", "library"),
        fileNames,
        contents,
        true
    )
    try {
        error := EmitterCanonicalFindSingleError(compilation, "DiagnosticId", "NL103")
        assert !compilation.Succeeded
        assert EmitterCanonicalErrorText(error, "Message").Contains("Declined at parse.declaration-scan:", StringComparison.Ordinal)
        assert EmitterCanonicalErrorText(error, "Message").Contains("setup or teardown", StringComparison.Ordinal)
        assert Path.GetFullPath(EmitterCanonicalErrorText(error, "FileName")) == Path.GetFullPath(
            Path.Combine(compilation.FixtureRoot, "Program.tests.nl")
        )
        assert EmitterCanonicalErrorInt(error, "Line") == 1
        assert EmitterCanonicalErrorInt(error, "Column") == 1
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

// `value.ToString()` on a receiver typed `T` used to decline at `emit.call.instance-member-unmodeled`
// (these two rows pinned that it declined rather than crashed). It is now `constrained. !T; callvirt`
// over the parameter's address; `tests/native/census-type-parameter-receivers` owns the shapes.
test "CompileToIlAssembly_ReceiverStyleGenericFunctionCallsObjectMemberOnTypeParameter" {
    compilation := EmitterCanonicalCompileSingle(
        "ReceiverGenericDecline",
        "library",
        """
func Tag<T>(this value: T, note: string): string {
    return note + value.ToString()
}
"""
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        assert compilation.Errors.Count == 0, EmitterCanonicalDiagnostics(compilation)
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

// The BODY of the same function emits through `constrained. !T`, and the CALL binds too: a generic
// receiver-style function called with receiver syntax (`5.Tag("ok")`) is `Tag(5, "ok")` with the
// receiver as argument zero, so `T` is inferred from the receiver and the method is closed on it.
test "CompileToIlAssembly_ExactReceiverGenericCheckFixtureCompilesAndRunsTheReceiverStyleCall" {
    compilation := EmitterCanonicalCompile(
        "ReceiverGenericCheck",
        "name: ReceiverGenericCheck\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

func Tag<T>(this value: T, note: string): string { return note + value.ToString() }
func main() { Console.WriteLine(5.Tag("ok")) }
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        assert compilation.Errors.Count == 0, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "ok5" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleGenericCallInfersAConstructedExactReceiver" {
    compilation := EmitterCanonicalCompile(
        "ReceiverGenericListHead",
        "name: ReceiverGenericListHead\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System
import System.Collections.Generic

func Head<T>(this items: List<T>): T => items[0]

func main() {
    values := new List<int>()
    values.Add(1)
    Console.WriteLine(values.Head())
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "1" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleGenericCallWidensListToIEnumerable" {
    compilation := EmitterCanonicalCompile(
        "ReceiverGenericListEnumerable",
        "name: ReceiverGenericListEnumerable\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System
import System.Collections.Generic

func Joined<T>(this items: IEnumerable<T>, seed: string): string {
    result := seed
    for item in items { result = result + item.ToString() }
    return result
}

func main() {
    values := new List<int>()
    values.Add(1)
    Console.WriteLine(values.Joined("list:"))
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "list:1" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleGenericCallWideningReadsArrayInterfaces" {
    compilation := EmitterCanonicalCompile(
        "ReceiverGenericArrayEnumerable",
        "name: ReceiverGenericArrayEnumerable\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System
import System.Collections.Generic

func Joined<T>(this items: IEnumerable<T>, seed: string): string {
    result := seed
    for item in items { result = result + item.ToString() }
    return result
}

func main() {
    numbers := [3, 4]
    Console.WriteLine(numbers.Joined("array:"))
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "array:34" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleGenericCallWideningReadsSourceInterfaces" {
    compilation := EmitterCanonicalCompile(
        "ReceiverGenericSourceEnumerable",
        "name: ReceiverGenericSourceEnumerable\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System
import System.Collections
import System.Collections.Generic

class SourceSequence<T>: IEnumerable<T>, IEnumerable {
    items: List<T>

    constructor(values: List<T>) {
        items = values
    }

    func GetEnumerator(): IEnumerator<T> {
        generic: IEnumerable<T> = items
        return generic.GetEnumerator()
    }

    func IEnumerable.GetEnumerator(): IEnumerator {
        untyped: IEnumerable = items
        return untyped.GetEnumerator()
    }
}

func Joined<T>(this items: IEnumerable<T>, seed: string): string {
    result := seed
    for item in items { result = result + item.ToString() }
    return result
}

func main() {
    values := new List<int>()
    values.Add(7)
    values.Add(8)
    Console.WriteLine(new SourceSequence<int>(values).Joined("source:"))
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "source:78" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

// VALUE-TYPE receivers close `T` on the value type itself — a literal, a local, a source struct with
// its own `ToString` and one that inherits `object`'s — so the call passes the value, not a box. A
// generic RESULT keeps its closed type (`5.Echo() + 1` is an `int` addition, and `point.Echo().Y`
// reads a member of `Point` through the preflight that picks `WriteLine(int)`), a second `T`
// argument is checked against the receiver's binding, and a receiver typed by the CALLER's own type
// parameter closes the callee on that parameter.
test "CompileToIlAssembly_ReceiverStyleGenericCallBindsTFromValueTypeReceivers" {
    compilation := EmitterCanonicalCompile(
        "ReceiverGenericValues",
        "name: ReceiverGenericValues\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

struct Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        X = x
        Y = y
    }

    override func ToString(): string => "(" + X.ToString() + ", " + Y.ToString() + ")"
}

struct Plain {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

func Tag<T>(this value: T, note: string): string { return note + value.ToString() }
func Echo<T>(this value: T): T { return value }
func Pair<T>(this first: T, second: T): string { return first.ToString() + "," + second.ToString() }
func Outer<U>(value: U): string { return value.Tag("outer:") }

func main() {
    count := 42
    ratio := 2.5
    flag := true
    point := new Point(1, 2)
    plain := new Plain(7)
    Console.WriteLine(5.Tag("literal:"))
    Console.WriteLine(count.Tag("int:"))
    Console.WriteLine(ratio.Tag("double:"))
    Console.WriteLine(flag.Tag("bool:"))
    Console.WriteLine(point.Tag("point:"))
    Console.WriteLine(plain.Tag("plain:"))
    sum := 5.Echo() + 1
    Console.WriteLine(sum)
    Console.WriteLine(point.Echo().Y)
    Console.WriteLine(count.Pair(8))
    Console.WriteLine(Outer(9))
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        nl := Environment.NewLine
        expected := "literal:5" + nl + "int:42" + nl + "double:2.5" + nl + "bool:True" + nl + "point:(1, 2)" + nl + "plain:W.Plain" + nl + "6" + nl + "2" + nl + "42,8" + nl + "outer:9" + nl
        assert run.Stdout == expected, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

// REFERENCE-TYPE receivers close `T` on the reference type — `string`, and a source class whose
// override the constrained call in the body reaches — and a generic result keeps the receiver's type
// for the next link of the chain (`name.Echo().Length`, `named.Echo().Label()`).
test "CompileToIlAssembly_ReceiverStyleGenericCallBindsTFromReferenceTypeReceivers" {
    compilation := EmitterCanonicalCompile(
        "ReceiverGenericRefs",
        "name: ReceiverGenericRefs\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

class Named {
    name: string

    constructor(name: string) {
        this.name = name
    }

    func Label(): string => "label " + name

    override func ToString(): string => "Named(" + name + ")"
}

func Tag<T>(this value: T, note: string): string { return note + value.ToString() }
func Echo<T>(this value: T): T { return value }

func main() {
    name := "abc"
    named := new Named("n")
    Console.WriteLine(name.Tag("string:"))
    Console.WriteLine(named.Tag("class:"))
    Console.WriteLine(name.Echo().Length)
    Console.WriteLine(named.Echo().Label())
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        nl := Environment.NewLine
        assert run.Stdout == "string:abc" + nl + "class:Named(n)" + nl + "3" + nl + "label n" + nl, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

// A LAMBDA ARGUMENT takes its input from the binding the receiver fixed, and its body closes the
// rest: `5.Map(x => x * 2)` fixes `T` to `int` from the receiver and `R` to `int` from the lambda, and
// `"abcd".Map(s => s.Length)` fixes `R` to `int` from a `string` input. A result typed by a type
// parameter is known ahead of emission, so `Console.WriteLine` is chosen by it (`WriteLine(int)`).
test "CompileToIlAssembly_ReceiverStyleGenericCallTypesLambdaArgumentsFromTheReceiver" {
    compilation := EmitterCanonicalCompile(
        "ReceiverGenericLambdas",
        "name: ReceiverGenericLambdas\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

func Map<T, R>(this value: T, f: Func<T, R>): R { return f(value) }
func Apply<T>(this value: T, f: Func<T, T>): T { return f(value) }

func main() {
    Console.WriteLine(5.Map(x => x * 2))
    Console.WriteLine("abcd".Map(s => s.Length))
    Console.WriteLine("hi".Apply(s => s + "!"))
    Console.WriteLine(7.Apply(n => n + 1))
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        nl := Environment.NewLine
        assert run.Stdout == "10" + nl + "4" + nl + "hi!" + nl + "8" + nl, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleSiblingResultTypesANonGenericBinaryOperand" {
    compilation := EmitterCanonicalCompile(
        "ReceiverSiblingBinary",
        "name: ReceiverSiblingBinary\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

func Len(this value: string): int { return value.Length }

func main() {
    name := "abc"
    Console.WriteLine(name.Len() + 1)
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "4" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleSiblingResultTypesAnInferredGenericBinaryOperand" {
    compilation := EmitterCanonicalCompile(
        "ReceiverSiblingGenericBinary",
        "name: ReceiverSiblingGenericBinary\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

func Echo<T>(this value: T): T { return value }

func main() {
    Console.WriteLine(5.Echo() + 1)
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "6" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleSiblingResultTypesAnExplicitGenericCall" {
    compilation := EmitterCanonicalCompile(
        "ReceiverSiblingExplicitGeneric",
        "name: ReceiverSiblingExplicitGeneric\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

func Echo<T>(this value: T): T { return value }

func main() {
    Console.WriteLine(5.Echo<int>() + 2)
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "7" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleSiblingResultTypesComparisonAndIfConditions" {
    compilation := EmitterCanonicalCompile(
        "ReceiverSiblingConditions",
        "name: ReceiverSiblingConditions\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

func Len(this value: string): int { return value.Length }

func main() {
    name := "abc"
    if name.Len() > 2 {
        Console.WriteLine(name.Len() == 3)
    }
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "True" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleSiblingPreservesRealInstanceMemberPrecedence" {
    compilation := EmitterCanonicalCompile(
        "ReceiverSiblingInstancePrecedence",
        "name: ReceiverSiblingInstancePrecedence\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

class Token {
    func Label(): string { return "instance" }
}

func Label(this value: Token): string { return "sibling" }

func main() {
    Console.WriteLine(new Token().Label())
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "instance" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_ReceiverStyleSiblingCallAcceptsAdditionalArguments" {
    compilation := EmitterCanonicalCompile(
        "ReceiverSiblingAdditionalArguments",
        "name: ReceiverSiblingAdditionalArguments\noutputType: exe\ntargetFramework: net10.0",
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            """
namespace W

import System

func Add(this value: int, other: int): int { return value + other }

func main() {
    Console.WriteLine(3.Add(4) * 2)
}
"""
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stdout + run.Stderr
        assert run.Stdout == "14" + Environment.NewLine, run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "CompileToIlAssembly_DeclineLogWritesTraceToTheCompilersWriter" {
    captured := EmitterCanonicalCompileWithDeclineLog(
        "TraceDecline",
        "library",
        """
import System.Numerics

func TypeName(value: string): string? {
    lanes: Vector<int>[] = []
    return value + lanes.Length.ToString()
}
"""
    )
    try {
        assert captured.DeclineTrace.Contains("decline site=emit.typed-local.unsupported-type", StringComparison.Ordinal)
        assert captured.DeclineTrace.Contains("typed local declaration type is not supported for 'lanes': Vector<int>[]", StringComparison.Ordinal)
        assert captured.DeclineTrace.Contains("location=Program.nl:4:5", StringComparison.Ordinal)
    } finally {
        EmitterCanonicalCleanup(captured.Compilation)
    }
}

// THE TWO VARIABLES ARE READ AT THE FRONT DOOR, ONCE. The rows above set the compiler's own
// settings in this process; these two prove the variables still seed them, in a child `nlc build`
// whose environment block alone carries the variable.
test "the columnar decline log variable sends the trace to the front door's stderr" {
    run := EmitterCanonicalCliBuild(
        "TraceDeclineCli",
        """
import System.Numerics

func main() {
    lanes: Vector<int>[] = []
    print lanes.Length
}
""",
        "NSHARP_COLUMNAR_DECLINE_LOG",
        "1"
    )
    assert run.ExitCode != 0, run.Stdout + run.Stderr
    assert run.Stderr.Contains("decline site=emit.typed-local.unsupported-type", StringComparison.Ordinal), run.Stdout + run.Stderr
    assert run.Stderr.Contains("location=Program.nl:4:5", StringComparison.Ordinal), run.Stdout + run.Stderr
}

test "the experimental soa variable turns on the columnar-only route at the front door" {
    run := EmitterCanonicalCliBuild(
        "SoaFallbackCli",
        """
soa record NodeTable {
    kind: int
    start: int
}

func main() {
    nodes := new NodeTable(1)
    row := nodes.add()
    nodes[row].kind = 7
    nodes[row].start = 9
    print nodes[row].kind + nodes[row].start + nodes.length
}
""",
        "NSHARP_EXPERIMENTAL_SOA",
        "1"
    )
    assert run.ExitCode != 0, run.Stdout + run.Stderr
    assert (run.Stdout + run.Stderr).Contains("Columnar SoA emission is required", StringComparison.Ordinal), run.Stdout + run.Stderr
}

test "ConditionalCompilation_EmitsOnlyLiveBranches_BasedOnProjectDefines" {
    projectYml := "name: CondCompile\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndefines:\n  - FEATURE_X"
    compilation := EmitterCanonicalCompile(
        "CondCompile",
        projectYml,
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            "func main() {\n    #if FEATURE_X\n    print \"feature-on\"\n    #else\n    print \"feature-off\"\n    #endif\n\n    #if MISSING_SYM\n    print \"missing-on\"\n    #else\n    print \"missing-off\"\n    #endif\n}"
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        assert File.Exists(compilation.OutputPath), compilation.OutputPath
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert run.Stdout.Contains("feature-on", StringComparison.Ordinal), run.Stdout
        assert !run.Stdout.Contains("feature-off", StringComparison.Ordinal), run.Stdout
        assert run.Stdout.Contains("missing-off", StringComparison.Ordinal), run.Stdout
        assert !run.Stdout.Contains("missing-on", StringComparison.Ordinal), run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "BuildCommand_CliDefineFlagsDriveExactConditionalCompilation" {
    projectYml := "name: CliDefineBuild\nbackend: il\noutputType: exe\ntargetFramework: net10.0"
    compilation := EmitterCanonicalCompileWithCliDefines(
        "CliDefineBuild",
        projectYml,
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            "func main() {\n    #if FEATURE_X\n    print \"feature-on\"\n    #else\n    print \"feature-off\"\n    #endif\n\n    #if SECOND\n    print \"second-on\"\n    #endif\n}"
        ),
        false,
        " FEATURE_X , SECOND ; FEATURE_X "
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        assert compilation.OutputAssemblyPath != null, "successful compilation returned no output assembly path"
        assert File.Exists(compilation.OutputPath), compilation.OutputPath

        definesValue := EmitterCanonicalRequiredProperty(compilation.Config, "Defines")
        defines := definesValue as IList
        if defines == null {
            throw new InvalidOperationException("The effective project defines did not implement IList")
        }
        assert defines.Count == 3, "effective define count was " + defines.Count.ToString()
        debugValue := defines[0]
        debugDefine := debugValue as string
        featureValue := defines[1]
        featureDefine := featureValue as string
        secondValue := defines[2]
        secondDefine := secondValue as string
        assert debugDefine == "DEBUG", "first effective define was " + (debugDefine ?? "<null>")
        assert featureDefine == "FEATURE_X", "second effective define was " + (featureDefine ?? "<null>")
        assert secondDefine == "SECOND", "third effective define was " + (secondDefine ?? "<null>")

        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert run.Stdout == "feature-on" + Environment.NewLine + "second-on" + Environment.NewLine, run.Stdout
        assert !run.Stdout.Contains("feature-off", StringComparison.Ordinal), run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "RegionDirectives_DoNotBlockColumnarConditionalCompilation" {
    projectYml := "name: RegionCondCompile\nbackend: il\noutputType: exe\ntargetFramework: net10.0\ndefines:\n  - FEATURE_X"
    compilation := EmitterCanonicalCompile(
        "RegionCondCompile",
        projectYml,
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(
            "#region Types\nclass Switchboard {\n    value: int = 0\n\n    func SetOn() {\n        value = 1\n    }\n\n    func GetValue(): int {\n        return value\n    }\n}\n#endregion\n\nfunc main() {\n    switchboard := new Switchboard()\n\n    #region Branch\n    #if FEATURE_X\n    switchboard.SetOn()\n    print \"feature-on\"\n    #else\n    print \"feature-off\"\n    #endif\n    #endregion\n\n    print switchboard.GetValue()\n}"
        ),
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert run.Stdout.Contains("feature-on", StringComparison.Ordinal), run.Stdout
        assert !run.Stdout.Contains("feature-off", StringComparison.Ordinal), run.Stdout
        assert run.Stdout.Contains("1", StringComparison.Ordinal), run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}
