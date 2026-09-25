namespace Census.Operands

import System.IO
import System.Reflection
import System.Runtime.InteropServices


// THE ANALYSIS PATH: this project, compiled by `nlc test` with the whole pipeline, running each
// referenced-type shape. Every function lives in `Consumer.nl`; every type in the referenced library.
test "G1: == and != between referenced reference types is identity, for one type, a base and a derived one, and object" {
    shape := new Shape("s")
    alias := new AliasShape("a", shape)
    assert OperandUses.SameShape(shape, shape)
    assert !OperandUses.SameShape(shape, new Shape("s"))
    assert !OperandUses.ResolvedDiffers(alias, alias)
    assert OperandUses.ResolvedDiffers(shape, alias)
    assert OperandUses.SameObject(shape, shape)
    assert !OperandUses.SameObject(shape, alias)
    node := new Node(1, 1)
    assert OperandUses.GuardedIdentity(node, node) == 1
    assert OperandUses.GuardedIdentity(node, new Node(1, 1)) == 0
}

test "G1: a referenced type's own == still decides, identity is not chosen over it" {
    assert OperandUses.TalliesMatch(new Tally(2), new Tally(2))
    assert !OperandUses.TalliesMatch(new Tally(2), new Tally(3))
}

test "G2: an enum == is a referenced constructor's argument, with and without a trailing optional" {
    shape := new Shape("s")
    assert OperandUses.ByRef(shape, Modifier.Out).IsOut
    assert !OperandUses.ByRef(shape, Modifier.Ref).IsOut
    assert OperandUses.ByRef(shape, Modifier.Out).Name == "&s"
    note := OperandUses.NoteFor(Modifier.Params, "t")
    assert note.IsMultiLine
    assert note.Line == 3 && note.Column == 7 && note.Text == "t"
    assert !OperandUses.NoteFor(Modifier.None, "u").IsMultiLine
}

test "G3: a referenced record takes an object initializer over a call and enum arguments" {
    report := OperandUses.Required("Core", "at emit", 4, 9)
    assert report.message == "Emission is required for 'Core'. at emit"
    assert report.code == Modifier.Ref
    assert report.severity == Severity.Error
    assert report.line == 4 && report.column == 9
    assert report.FileName == "Core.nl"
    assert report.Length == 4
    assert report.Explanation == "why Core"
    assert OperandUses.Required("M", null, 1, 1).message == "Emission is required for 'M'."
}

test "G4: an enum cast is a referenced constructor's argument, and the optional is filled when it is not written" {
    assert OperandUses.Constrained("T", 3).Flags == (SpecialFlags.Class | SpecialFlags.Struct)
    assert OperandUses.Unconstrained("U").Flags == SpecialFlags.None
    assert OperandUses.Constrained("T", 3).Parameter == "T"
}

test "G5: nested new, free-call, as and concatenation arguments reach a referenced constructor" {
    depth := OperandUses.Depth(4, 12)
    assert depth.Name == "Depth3"
    assert depth.Line == 12 && depth.Column == 5
    bare := OperandUses.Bare("x")
    assert bare.Line == 0 && bare.Column == 0

    names: string[] = ["zero", "one"]
    statement := OperandUses.Statement(names, 1)
    ident := statement.Expression as Ident
    assert ident != null
    assert ident.Name == "one"
    assert statement.Line == 11 && ident.Line == 11

    loop := OperandUses.Foreach()
    assert loop.Variable == "item"
    assert loop.Declared == null
    assert (loop.Collection as Ident)?.Name == "items"

    guarded := OperandUses.Guarded(OperandUses.EmptyBlock(2))
    assert guarded.Body != null
    assert guarded.Finally == null
    assert OperandUses.Guarded(new ExprStmt(new Ident("x", 1, 1), 1, 1)).Body == null
}

test "G5: the written arguments run left to right before the defaults are filled" {
    loop := OperandUses.Ordered()
    assert OperandUses.Ordering() == "variable,collection,body,line,column"
    assert loop.Line == 4 && loop.Column == 5
    assert loop.Declared == null
}

test "G5: two constructors of one arity are told apart by the written argument" {
    assert OperandUses.PickText("a").Chosen == "text:a!"
    assert OperandUses.PickCount(21).Chosen == "count:42"
}

test "G6: a narrowed nullable member of a third assembly's type is passed on and called through" {
    assert OperandUses.ContextName(new Scan(null, null)) == "none"
    assert OperandUses.LabelLength(new Scan(null, "four")) == 4
    assert OperandUses.LabelLength(new Scan(null, null)) == -1

    paths := Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll")
    context := new MetadataLoadContext(new PathAssemblyResolver(paths), "System.Private.CoreLib")
    try {
        assert OperandUses.ContextName(new Scan(context, null)) == "System.Private.CoreLib"
    } finally {
        context.Dispose()
    }
}
