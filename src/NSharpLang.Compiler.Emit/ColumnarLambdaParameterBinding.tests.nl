namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// A LAMBDA WRITTEN WITH A PARAMETER TYPE ITS DELEGATE CANNOT BIND DECLINES AT EMIT.
//
// The synthesized method takes the WRITTEN parameter types, so a target delegate whose `Invoke` takes
// something else would be built over a method whose signature it does not have — unverifiable, and
// wrong the moment it is invoked (issue #216's `(id: int) => …` as `Func<HttpContext, …>`). These
// rows build programs for real: the mismatch declines at `emit.lambda.parameter-type-mismatch`, and
// the reference contravariance N# accepts still emits and runs.
func LambdaParameterBindingEmit(source: string, out bytes: byte[]): bool {
    program := EmitFixtureProgram(["Probe"], [source], "LambdaParameterBinding")
    ColumnarDeclineTrace.Reset()
    bytes = null
    return ColumnarIlEmitter.TryEmitColumnarAssembly("LambdaParameterBinding" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
}

func LambdaParameterBindingDeclined(): bool {
    for reason in ColumnarDeclineTrace.Snapshot() {
        if reason.SiteId == "emit.lambda.parameter-type-mismatch" {
            return true
        }
    }
    return false
}

test "a lambda written with a value type its delegate does not take declines at emit" {
    source := "import System\n\nfunc Widened(): int {\n    f: Func<int, int> = (x: long) => 1\n    return f(2)\n}\n"
    bytes: byte[] = null
    assert !LambdaParameterBindingEmit(source, out bytes)
    assert LambdaParameterBindingDeclined()
}

test "a lambda written with object for a value-type delegate parameter declines at emit" {
    source := "import System\n\nfunc Boxed(): int {\n    f: Func<int, int> = (x: object) => 1\n    return f(2)\n}\n"
    bytes: byte[] = null
    assert !LambdaParameterBindingEmit(source, out bytes)
    assert LambdaParameterBindingDeclined()
}

test "a reference-contravariant written parameter emits and runs" {
    source := "import System\n\nfunc Classify(): int {\n    f: Func<string, int> = (value: object) => 7\n    return f(\"text\")\n}\n"
    bytes: byte[] = null
    assert LambdaParameterBindingEmit(source, out bytes)
    assert !LambdaParameterBindingDeclined()
    owner := Assembly.Load(bytes).GetType("Probe.Program")
    assert owner != null
    method := owner.GetMethod("Classify", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    assert method != null
    answer := method.Invoke(null, new object?[](0))
    assert answer != null
    assert answer.ToString() == "7"
}
