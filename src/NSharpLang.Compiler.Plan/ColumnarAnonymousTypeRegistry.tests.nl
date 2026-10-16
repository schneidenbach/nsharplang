namespace NSharpLang.Compiler.Columnar

import System

// The anonymous-object template's TEXT rules — the shape key, the `ToString` composite format, the
// debugger display and the hash seed — pinned on their own, because each is a promise the emitted
// type makes to every program: the rendering C# prints, a key two bodies agree on, and a seed that
// never changes from one build of the same source to the next.

func AnonymousNames(first: string, second: string): string[] {
    names := new string[2]
    names[0] = first
    names[1] = second
    return names
}

test "the shape key is the ordered property names, so order is part of the shape" {
    assert ColumnarAnonymousTypeRegistry.ShapeKey(AnonymousNames("Name", "Age")) == "Name,Age"
    assert ColumnarAnonymousTypeRegistry.ShapeKey(AnonymousNames("Age", "Name")) == "Age,Name"
    assert ColumnarAnonymousTypeRegistry.ShapeKey(new string[0]) == ""
}

test "ToString's composite format escapes its own braces and numbers the holes in written order" {
    format := ColumnarAnonymousTypeRegistry.ToStringFormat(AnonymousNames("Name", "Age"))
    assert format == "{{ Name = {0}, Age = {1} }}"
    assert String.Format(null, format, "Alice", 30) == "{ Name = Alice, Age = 30 }"
}

test "the debugger display names each property as a hole the debugger evaluates" {
    assert ColumnarAnonymousTypeRegistry.DebuggerDisplayText(AnonymousNames("Name", "Age")) == "\\{ Name = {Name}, Age = {Age} }"
    assert ColumnarAnonymousTypeRegistry.DebuggerDisplayText(new string[0]) == "\\{ }"
}

test "the hash seed is a fixed function of the ordered names" {
    seed := ColumnarAnonymousTypeRegistry.HashSeed(AnonymousNames("Name", "Age"))
    assert seed == ColumnarAnonymousTypeRegistry.HashSeed(AnonymousNames("Name", "Age"))
    assert seed != ColumnarAnonymousTypeRegistry.HashSeed(AnonymousNames("Age", "Name"))
    // FNV-1a over "Name,Age," — pinned so a change to the seed is a deliberate one.
    assert seed == -486365001
}
