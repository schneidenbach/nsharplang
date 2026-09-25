namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

// A MEMBER WRITE WHOSE RECEIVER IS AN EXPRESSION (`ColumnarIlEmitter.TryResolveMemberWriteChain`).
// The chain's root used to be a bare local or parameter only, so `roster[0].Name = v` and
// `Pick(d).Name = v` passed analysis and then declined at `emit.statement.block-child` — while C#
// compiles both. The root is now also a REFERENCE-typed expression, evaluated once for the object
// that is the write's storage, or a VALUE-typed ARRAY ELEMENT, located by `ldelema` so the write
// changes the array's own slot. A value-typed call or indexer result is a temporary (CS1612; the
// analyzer's NL322) and still declines here, so the emitter never writes into a copy that is then
// thrown away.
func MemberWriteReceiversSource(lines: string[]): string {
    return string.Join("\n", lines) + "\n"
}

func MemberWriteReceiversProgram(source: string): ColumnarProgramInput {
    sources := new List<string>()
    sources.Add(source)
    fileNames := new List<string>()
    fileNames.Add("/tmp/ColumnarMemberWriteReceivers.nl")
    program: ColumnarProgramInput = null
    assert ColumnarProgramInputBuilder.TryBuildMultiFile(sources, fileNames, "/tmp", out program)
    return program
}

func MemberWriteReceiversEmit(source: string, out bytes: byte[]): bool {
    ColumnarDeclineTrace.Reset()
    return ColumnarIlEmitter.TryEmitColumnarAssembly(
        "ColumnarMemberWriteReceivers" + Guid.NewGuid().ToString("N"),
        "Program",
        MemberWriteReceiversProgram(source),
        false,
        out bytes,
        null,
        null
    )
}

func MemberWriteReceiversRun(source: string, functionName: string): string {
    bytes: byte[] = null
    if !MemberWriteReceiversEmit(source, out bytes) {
        throw new InvalidOperationException("The member-write fixture declined: " + MemberWriteReceiversDeclines())
    }
    owner := Assembly.Load(bytes).GetType("Program")
    if owner == null {
        throw new InvalidOperationException("The member-write fixture did not publish Program.")
    }
    method := owner.GetMethod(functionName, Type.EmptyTypes)
    if method == null {
        throw new InvalidOperationException("The member-write fixture did not publish " + functionName + ".")
    }
    result := method.Invoke(null, new object?[](0)) as string
    return result ?? "<null>"
}

// Every recorded decline as `member@site`, so a decline row can name the member that declined and
// where, instead of accepting any failure at all as evidence. A statement that declines is recorded
// at its own site with no member name, and the body that contained it at `emit.body` under the
// member's name.
func MemberWriteReceiversDeclines(): string {
    parts := new List<string>()
    for reason in ColumnarDeclineTrace.Snapshot() {
        parts.Add(reason.MemberName + "@" + reason.SiteId)
    }
    return string.Join(";", parts)
}

func MemberWriteReceiversTypes(): string {
    return MemberWriteReceiversSource([
        "import System.Collections.Generic",
        "",
        "struct Point {",
        "    X: int",
        "    Y: int",
        "}",
        "",
        "struct Segment {",
        "    Start: Point",
        "    End: Point",
        "}",
        "",
        "class Dog {",
        "    Name: string = \"rex\"",
        "    Age: int = 1",
        "    Spot: Point",
        "}",
        "",
        "func Pick(dog: Dog): Dog {",
        "    return dog",
        "}",
        "",
        "func MakePoint(): Point {",
        "    return new Point()",
        "}",
        "",
        "func Bump(ref n: int) {",
        "    n = n + 100",
        "}",
        "",
        "func Swap(ref text: string) {",
        "    text = \"swapped:\" + text",
        "}",
        ""
    ])
}

test "a field write through a reference-typed array element emits and changes the shared object" {
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func Run(): string {",
        "    d := new Dog()",
        "    roster: Dog[] = [new Dog(), d]",
        "    roster[0].Name = \"max\"",
        "    roster[1].Age += 4",
        "    roster[1].Age++",
        "    return roster[0].Name + \",\" + d.Age.ToString()",
        "}"
    ])
    assert MemberWriteReceiversRun(source, "Run") == "max,6"
}

test "a field write through a reference-typed call result emits and changes the returned object" {
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func Run(): string {",
        "    d := new Dog()",
        "    Pick(d).Name = \"bo\"",
        "    Pick(d).Age += 2",
        "    Pick(d).Spot.X = 3",
        "    return d.Name + \",\" + d.Age.ToString() + \",\" + d.Spot.X.ToString()",
        "}"
    ])
    assert MemberWriteReceiversRun(source, "Run") == "bo,3,3"
}

test "a field write through a list indexer's reference-typed result emits" {
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func Run(): string {",
        "    dogs := new List<Dog>()",
        "    dogs.Add(new Dog())",
        "    dogs[0].Name = \"lulu\"",
        "    return dogs[0].Name",
        "}"
    ])
    assert MemberWriteReceiversRun(source, "Run") == "lulu"
}

test "a field write to a value-typed array element writes the slot in place, not a copy" {
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func Run(): string {",
        "    points := new Point[](2)",
        "    before := points[1]",
        "    points[1].X = 7",
        "    points[1].Y += 5",
        "    points[1].Y++",
        "    return points[1].X.ToString() + \",\" + points[1].Y.ToString() + \",\" + points[0].X.ToString() + \",\" + before.X.ToString()",
        "}"
    ])
    assert MemberWriteReceiversRun(source, "Run") == "7,6,0,0"
}

test "a nested value-typed field of an array element is written and read through both addresses" {
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func Run(): string {",
        "    segments := new Segment[](2)",
        "    segments[1].End.X = 9",
        "    return segments[1].End.X.ToString() + \",\" + segments[1].Start.X.ToString() + \",\" + segments[0].End.X.ToString()",
        "}"
    ])
    assert MemberWriteReceiversRun(source, "Run") == "9,0,0"
}

test "a ref argument takes the address of a field behind an expression receiver" {
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func Run(): string {",
        "    points := new Point[](1)",
        "    Bump(ref points[0].X)",
        "    d := new Dog()",
        "    Bump(ref Pick(d).Age)",
        "    return points[0].X.ToString() + \",\" + d.Age.ToString()",
        "}"
    ])
    assert MemberWriteReceiversRun(source, "Run") == "100,101"
}

// A `ref` to a REFERENCE-typed field is the field's slot (`ldflda`), not the object it holds: the
// final link of the chain used to be loaded with `ldfld` like every other reference-typed link, so
// `Swap(ref d.Name)` handed the callee the string itself and failed at run time.
test "a ref argument to a reference-typed field passes the field's slot, whatever the root" {
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func Run(): string {",
        "    d := new Dog()",
        "    Swap(ref d.Name)",
        "    roster: Dog[] = [d]",
        "    Swap(ref roster[0].Name)",
        "    Swap(ref Pick(d).Name)",
        "    return d.Name",
        "}"
    ])
    assert MemberWriteReceiversRun(source, "Run") == "swapped:swapped:swapped:rex"
}

test "a write through a value-typed call result still declines rather than write into a copy" {
    bytes: byte[] = null
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func WriteTemporary() {",
        "    MakePoint().X = 1",
        "}"
    ])
    assert !MemberWriteReceiversEmit(source, out bytes), "the write into a temporary copy emitted"
    declines := MemberWriteReceiversDeclines()
    assert declines.Contains("@emit.statement.block-child") && declines.Contains("WriteTemporary@emit.body"), declines

    // The control: the same write through a local that holds the value emits.
    control := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func WriteLocal(): int {",
        "    p := MakePoint()",
        "    p.X = 1",
        "    return p.X",
        "}"
    ])
    assert MemberWriteReceiversEmit(control, out bytes), MemberWriteReceiversDeclines()
}

test "a write through a value-typed list element still declines, while the reference-typed one emits" {
    bytes: byte[] = null
    source := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func WriteListCopy() {",
        "    points := new List<Point>()",
        "    points.Add(new Point())",
        "    points[0].X = 1",
        "}"
    ])
    assert !MemberWriteReceiversEmit(source, out bytes), "the write into a temporary copy emitted"
    declines := MemberWriteReceiversDeclines()
    assert declines.Contains("@emit.statement.block-child") && declines.Contains("WriteListCopy@emit.body"), declines

    control := MemberWriteReceiversTypes() + MemberWriteReceiversSource([
        "func WriteListElement() {",
        "    dogs := new List<Dog>()",
        "    dogs.Add(new Dog())",
        "    dogs[0].Name = \"x\"",
        "}"
    ])
    assert MemberWriteReceiversEmit(control, out bytes), MemberWriteReceiversDeclines()
}
