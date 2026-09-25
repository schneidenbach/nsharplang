namespace NSharpLang.Compiler.Columnar

import System


// THE EMITTER'S OWN WORD ON AN IDENTITY DECLARED TWICE IN ONE NAMESPACE (ported from the
// dazzling-lehmann-330ccb census, 2026-09-13).
//
// The analyzer reports these pairs first — NL306 in each file for a free function, NL339 at the
// later declaration for a type — and these rows pin the refusal for the paths that reach the
// emitter without it. Before them, a second free function of one (namespace, name) overwrote the
// first in every name-keyed view while the holder carried two rows of one signature, and a second
// type of one exact name was a second `DefineType` that `PersistedAssemblyBuilder` accepts, leaving
// two TypeDef rows and every registry keeping the last. Both now decline at
// `emit.declaration.duplicate` before anything is defined.
//
// The programs are built by the planner rows' own helpers (`FreeFunctionScopeProgram`,
// `DeclarationPlanMultiFileProgram` in Backend.Plan); only the emit call belongs to this slice.
test "one namespace declaring a function name twice across files is refused at emit, never silently halved" {
    // The analyzer reports this pair as NL306; this is the emitter's own refusal, for the paths that
    // reach it without the analyzer. Before it, the second row overwrote the first in every view and
    // the holder carried two `Helper` rows of one signature.
    program := FreeFunctionScopeProgram(
        ["X", "X"],
        [
            "func Helper(): string {\n    return \"first\"\n}\n",
            "func Helper(): string {\n    return \"second\"\n}\n"
        ]
    )
    ColumnarDeclineTrace.Reset()
    bytes: byte[] = null
    assert !ColumnarIlEmitter.TryEmitColumnarAssembly("FreeFunctionScopeTwin" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)

    declinedAtDuplicate := false
    for reason in ColumnarDeclineTrace.Snapshot() {
        if reason.SiteId == "emit.declaration.duplicate" && reason.Message.Contains("'Helper'") && reason.Message.Contains("namespace 'X'") {
            declinedAtDuplicate = true
        }
    }
    assert declinedAtDuplicate
}

test "one namespace declaring a type twice across files is refused at emit, never silently halved" {
    program := DeclarationPlanMultiFileProgram(
        ["X", "X"],
        [
            "class Widget {\n    Tag: string = \"first\"\n}\n",
            "class Widget {\n    Tag: string = \"second\"\n}\n"
        ]
    )
    ColumnarDeclineTrace.Reset()
    bytes: byte[] = null
    assert !ColumnarIlEmitter.TryEmitColumnarAssembly("DeclarationPlanTwin" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)

    declinedAtDuplicate := false
    for reason in ColumnarDeclineTrace.Snapshot() {
        if reason.SiteId == "emit.declaration.duplicate" && reason.Message.Contains("type 'Widget'") && reason.Message.Contains("namespace 'X'") {
            declinedAtDuplicate = true
        }
    }
    assert declinedAtDuplicate
}
