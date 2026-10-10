namespace Census.Operands

import System
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

test "G7: a maybe-null referenced class value compares by identity, and a declared == still decides for it" {
    shape := new Shape("s")
    node := new Node(1, 1)
    assert OperandUses.MaybeSameShape(shape, shape)
    assert !OperandUses.MaybeSameShape(new Shape("s"), shape)
    assert !OperandUses.MaybeSameShape(null, shape)
    assert !OperandUses.MaybeNodesDiffer(node, node)
    assert OperandUses.MaybeNodesDiffer(null, node)
    assert !OperandUses.MaybeNodesDiffer(null, null)
    assert OperandUses.MaybeTalliesMatch(new Tally(2), new Tally(2))
    assert !OperandUses.MaybeTalliesMatch(new Tally(2), new Tally(3))
}

test "G8: a conditional with a null arm is a referenced static's or instance method's argument" {
    assert OperandUses.DescribeNullFirst(true, "a") == "none:1"
    assert OperandUses.DescribeNullFirst(false, "a") == "a:1"
    assert OperandUses.DescribeNullSecond(true, "b") == "b:2"
    assert OperandUses.DescribeNullSecond(false, "b") == "none:2"
    alias := new AliasShape("a", new Shape("s"))
    assert OperandUses.NameOfAlias(true, alias) == "<none>"
    assert OperandUses.NameOfAlias(false, alias) == "a"
    assert OperandUses.CountOrAbsent(true, 3) == -1
    assert OperandUses.CountOrAbsent(false, 3) == 3
    labeler := new Labeler("p")
    assert OperandUses.LabelOrPrefix(true, labeler, "!") == "p"
    assert OperandUses.LabelOrPrefix(false, labeler, "!") == "p!"
}

test "G8: a conditional with a default arm takes the referenced parameter's type" {
    assert OperandUses.DescribeDefaultFirst(true, "a") == "none:3"
    assert OperandUses.DescribeDefaultFirst(false, "a") == "a:3"
    assert OperandUses.CountOrDefault(true, 3) == 3
    assert OperandUses.CountOrDefault(false, 3) == -1
    labeler := new Labeler("p")
    assert OperandUses.LabelOrDefault(true, labeler, "!") == "p"
    assert OperandUses.LabelOrDefault(false, labeler, "!") == "p!"
}

test "G8: nested null, default and throw arms target referenced static and instance arguments" {
    assert OperandUses.DescribeNestedNull(true, true, "a", "fallback") == "none:3"
    assert OperandUses.DescribeNestedNull(true, false, "a", "fallback") == "a:3"
    assert OperandUses.DescribeNestedNull(false, true, "a", "fallback") == "fallback:3"
    assert OperandUses.DescribeNestedDefault(true, true, "b", "fallback") == "none:4"
    assert OperandUses.DescribeNestedDefault(true, false, "b", "fallback") == "b:4"
    assert OperandUses.CountNestedDefault(true, true, 7) == -1
    assert OperandUses.CountNestedDefault(true, false, 7) == 7
    assert OperandUses.CountNestedNullElse(false, true, 8) == 6
    assert OperandUses.CountNestedNullElse(false, false, 8) == -1

    labeler := new Labeler("p")
    assert OperandUses.LabelNestedDefault(true, true, labeler, "!") == "p"
    assert OperandUses.LabelNestedDefault(true, false, labeler, "!") == "p!"
    assert OperandUses.DescribeNestedThrow(true, false, "value", "fallback", new InvalidOperationException("not selected")) == "fallback:5"

    failure := new InvalidOperationException("referenced")
    raised := false
    try {
        _ignored := OperandUses.DescribeNestedThrow(false, false, "value", "fallback", failure)
    } catch caught: InvalidOperationException {
        raised = caught.Message == "referenced"
    }
    assert raised
}

test "G9: a &T parameter is passed on by reference to a referenced &T parameter" {
    assert OperandUses.Forwarded() == "6 15"
}

test "G10: a referenced static call takes a referenced static call over a must operand or over a call on an operator" {
    assert OperandUses.MustNested(new Shape("s")) == 1
    assert OperandUses.MustNestedLocal(new AliasShape("abc", new Shape("s"))) == 6
    assert OperandUses.OperatorNested(-2) == 12
    // `Child(index, count - 1)` on the current instance, inside `Facts.Join`, inside `Facts.Both`.
    assert new Cursor("ab").Matches(1, 5)
    assert !new Cursor("ab").Matches(2, 7)
    // A member read over `must` inside the inner call, and the inner call chosen by an overloaded
    // framework method (`StringBuilder.Insert` has a dozen two-argument overloads).
    assert OperandUses.MustMemberNested(new Shape("abc")) == 6
    assert OperandUses.OverloadedOuter(new Shape("s")) == "s|"
}

test "G10: a source static inside a referenced one, a referenced one inside a source one, and a referenced instance call" {
    assert OperandUses.SourceInner(new Shape("s")) == 2
    assert OperandUses.SourceOuter(new Shape("a")) == 101
    assert OperandUses.InstanceOuter(new Shape("s"), new Shape("a")) == "as"
}

test "G11: a referenced struct takes an object initializer, and a member write through a local's address" {
    assert OperandUses.InitializedCounter() == 10
    assert OperandUses.ConstructedThenInitialized() == 12
    assert OperandUses.StoredCounter() == 15
    assert OperandUses.CallerKeepsItsCopy() == "5 4"
    assert OperandUses.NestedStore() == 9
    assert OperandUses.HeldCounter() == 3
    assert OperandUses.GaugeReading() == "kPa 15"
}

test "G11: a referenced class takes an object initializer through its parameterless or all-optional constructor" {
    assert OperandUses.Configured() == "n5o t7 none"
}

test "G11: an initializer whose values only the emitter writes builds the same referenced struct and class" {
    assert OperandUses.Interpolated(4) == "u44 s44none 2"
}

test "G12: short-circuit, unary, comparison and nested conditions type conditional arguments before overload selection" {
    assert OperandUses.AppendAnd(true, true) == "x"
    assert OperandUses.AppendAnd(true, false) == "y"
    assert OperandUses.AppendOr(false, false) == "y"
    assert OperandUses.AppendOr(false, true) == "x"
    assert OperandUses.AppendNot(false) == "x"
    assert OperandUses.AppendNot(true) == "y"
    assert OperandUses.AppendComparison(true, true) == "x"
    assert OperandUses.AppendComparison(true, false) == "y"
    assert OperandUses.AppendNested(true, false, true) == "y"
    assert OperandUses.AppendNested(false, false, true) == "x"
    assert OperandUses.EmitConditionalOpcodeOverload()
}
