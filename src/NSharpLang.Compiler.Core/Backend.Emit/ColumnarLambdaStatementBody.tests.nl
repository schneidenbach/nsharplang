namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// THE EXPRESSION-STATEMENT LAMBDA (`ColumnarIlEmitter.EmitLambdaBody`). A lambda filling a delegate
// that returns nothing may still be written with an expression body: `x => x.Record(entry)` evaluates
// the call for its effect and drops the value, which is the same reading `x => { x.Record(entry) }`
// gets. Matching the body's type against `void` instead — nothing converts to `void` — declined every
// `Action<T>` configuration callback written the way fluent .NET APIs expect one.
//
// The admitted set is C#'s own (CS0201): only an expression that may STAND AS A STATEMENT qualifies.
// `x => x + 1` against an `Action<int>` still declines, because the value it produces has nowhere to
// go and dropping it silently would hide a real mistake.
func LambdaStatementBodyEmits(source: string): bool {
    sources := new List<string>()
    sources.Add(source)
    names := new List<string>()
    names.Add("/tmp/LambdaStatementBodyProbe.nl")
    program: ColumnarProgramInput = null
    assert ColumnarProgramInputBuilder.TryBuildMultiFile(sources, names, "/tmp", out program)
    bytes: byte[] = null
    return ColumnarIlEmitter.TryEmitColumnarAssembly("LambdaStatementBody" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
}

test "a call as the whole body of a void-returning lambda emits with its value dropped" {
    assert LambdaStatementBodyEmits("import System\nimport System.Text\n\nfunc Configure(action: Action<StringBuilder>) {\n    action(new StringBuilder())\n}\n\nfunc Use() {\n    Configure(target => target.Append(\"hi\"))\n}\n")
}

test "an object creation as the whole body of a void-returning lambda emits" {
    assert LambdaStatementBodyEmits("import System\nimport System.Text\n\nclass Stamp {\n    constructor(builder: StringBuilder) {\n        builder.Append(\"stamp\")\n    }\n}\n\nfunc Configure(action: Action<StringBuilder>) {\n    action(new StringBuilder())\n}\n\nfunc Use() {\n    Configure(target => new Stamp(target))\n}\n")
}

test "the block-bodied spelling of the same lambda still emits" {
    assert LambdaStatementBodyEmits("import System\nimport System.Text\n\nfunc Configure(action: Action<StringBuilder>) {\n    action(new StringBuilder())\n}\n\nfunc Use() {\n    Configure(target => {\n        target.Append(\"hi\")\n    })\n}\n")
}

test "an expression that cannot stand as a statement still declines against a void delegate" {
    assert !LambdaStatementBodyEmits("import System\n\nfunc Configure(action: Action<int>) {\n    action(1)\n}\n\nfunc Use() {\n    Configure(value => value + 1)\n}\n")
}

test "a value-returning delegate still requires its body to produce that value" {
    assert LambdaStatementBodyEmits("import System\n\nfunc Select(projection: Func<int, int>): int {\n    return projection(1)\n}\n\nfunc Use(): int {\n    return Select(value => value + 1)\n}\n")
}
