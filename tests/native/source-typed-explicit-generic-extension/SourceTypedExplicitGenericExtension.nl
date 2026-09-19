namespace NSharpLang.SourceTypedExplicitGenericExtension.Tests

import System
import System.Collections.Generic


// AN EXPLICITLY CLOSED EXTENSION CALL WHOSE RECEIVER IS A TYPE THIS COMPILATION IS WRITING.
//
// `Enumerable.OfType<TResult>(this IEnumerable)` and `Cast<TResult>` declare a NON-GENERIC
// `IEnumerable` receiver slot and take NO arguments of their own: the type argument is written at
// the site because there is nothing to infer it from. The compiler's own source writes
//
//     for fileImport in compilationUnit.FileImports.OfType<FileImport>() { ... }
//
// where `FileImports` is a `List<Statement>` over a class the SAME assembly declares. That receiver
// is a builder-bound instantiation: reflection cannot report its interface list, so asking
// `typeof(IEnumerable).IsAssignableFrom(...)` about it answers `false` and the candidate is dropped.
// The relation has to be answered by the same owner that answers it for a GENERIC slot.
//
// Everything here EXECUTES. A declared result type proves nothing on its own; the values and the
// runtime types the calls answer with are what prove the right method was selected.
class Node {
    Name: string
    Weight: int

    constructor(name: string, weight: int) {
        Name = name
        Weight = weight
    }

    func Describe(): string {
        return Name + ":" + Weight.ToString()
    }
}

class Leaf {
    Label: string

    constructor(label: string) {
        Label = label
    }
}

struct Tag {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

// THE COMPILER'S OWN SHAPE: a list of a source BASE-ish element holding mixed source elements,
// reached through a PROPERTY of another source type, exactly like `compilationUnit.FileImports`.
class Unit {
    Items: List<object>
    Nodes: List<Node>
    Names: string[]

    constructor() {
        Items = new List<object>()
        Items.Add(new Node("alpha", 3))
        Items.Add(new Leaf("skip"))
        Items.Add(new Node("gamma", 2))
        Items.Add("not-a-node")
        Nodes = new List<Node>()
        Nodes.Add(new Node("one", 1))
        Nodes.Add(new Node("two", 2))
        Names = ["alpha", "be"]
    }
}

func MakeUnit(): Unit {
    return new Unit()
}

func MixedList(): List<object> {
    values := new List<object>()
    values.Add(new Node("alpha", 3))
    values.Add(7)
    values.Add(new Tag(4))
    values.Add(new Node("gamma", 2))
    return values
}

func NodeList(): List<Node> {
    values := new List<Node>()
    values.Add(new Node("alpha", 3))
    values.Add(new Node("be", 1))
    return values
}

func NodeArray(): Node[] {
    return [new Node("alpha", 3), new Node("be", 1)]
}

func RuntimeTypeOf(value: object): Type {
    return value.GetType()
}
