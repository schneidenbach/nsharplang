namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// THE SYNTHESIZED INSTANCE INITIALIZER IS NOT ALL SOURCE TEXT. The field scan writes a store for a
// nullable field that carries no initializer (`Tokens: string?` stores `null`), and that assignment
// node has no operator span, because there is no `=` token behind it. Reading text out of the absent
// span threw `ArgumentOutOfRangeException` from inside `nlc check`, so a class that paired one bare
// nullable field with one initialized field could not be compiled at all — not declined with a
// diagnostic, but crashed.
func FieldInitPlannerProgram(source: string): ColumnarProgramInput {
    sources := new List<string>()
    sources.Add(source)
    names := new List<string>()
    names.Add("/tmp/FieldInitPlannerProbe.nl")
    program: ColumnarProgramInput = null
    assert ColumnarProgramInputBuilder.TryBuildMultiFile(sources, names, "/tmp", out program)
    return program
}

// The one synthesized zero-parameter initializer of the program's first type, with the source text
// its spans index into.
func FieldInitPlannerInitializer(program: ColumnarProgramInput, out source: string): ColumnarConstructorInput {
    structInput := program.Structs[0]
    index := 0
    while index < structInput.Constructors.Count {
        candidate := structInput.Constructors[index]
        if candidate.IsSynthesizedInitializer && candidate.Body.ParamNames.Length == 0 {
            source = program.GetSourceForFileId(candidate.Body.SourceFileId)
            return candidate
        }
        index = index + 1
    }
    source = ""
    assert false, "the probe type must carry a synthesized zero-parameter initializer"
    return structInput.Constructors[0]
}

// Every own-field name the initializer body's top-level stores assign, in source order.
func FieldInitPlannerAssignedNames(source: string): string[] {
    program := FieldInitPlannerProgram(source)
    initializerSource: string = ""
    initializer := FieldInitPlannerInitializer(program, out initializerSource)
    nodes := initializer.Body.BodyNodes
    root := initializer.Body.BodyRoot
    names := new List<string>()
    child := 0
    while child < nodes.ChildCount(root) {
        name := ColumnarFieldInitPlanner.TopLevelFieldAssignmentTarget(nodes, initializerSource, nodes.Child(root, child))
        if name != null {
            names.Add(name)
        }
        child = child + 1
    }
    return names.ToArray()
}

test "a written field initializer names the field its store assigns" {
    names := FieldInitPlannerAssignedNames("class Probe {\n    Count: int = 4\n    Label: string = \"set\"\n}\n")
    assert names.Length == 2
    assert names[0] == "Count"
    assert names[1] == "Label"
}

test "a nullable field with no initializer names the field its synthesized null store assigns" {
    names := FieldInitPlannerAssignedNames("class Probe {\n    Tokens: string?\n    Count: int = 4\n}\n")
    assert names.Length == 2
    assert names[0] == "Tokens"
    assert names[1] == "Count"
}

test "a class pairing a bare nullable field with an initialized one emits instead of throwing" {
    program := FieldInitPlannerProgram("class Probe {\n    Tokens: string?\n    Count: int = 4\n}\n")
    bytes: byte[] = null
    assert ColumnarIlEmitter.TryEmitColumnarAssembly("FieldInitPlanner" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
    assert bytes != null
    assert bytes.Length > 0
}
