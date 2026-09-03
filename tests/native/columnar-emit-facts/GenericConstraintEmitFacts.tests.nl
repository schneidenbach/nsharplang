namespace NSharpLang.ColumnarEmitFacts.Tests


// A `where` CLAUSE ON EVERY TYPE KEYWORD, PROVEN BY THE ASSEMBLY LOADING AT ALL.
//
// THE PROOF IS THE PROJECT ITSELF, and that is why these declarations live here rather than in a
// string. `tests/native` is compiled by the columnar backend under test and the runner then LOADS the
// emitted assembly to run the blocks below. So every declaration in this file has to survive three
// gates that a source-string harness would not reach: the columnar parser must read the clause, the
// emitter must write the constraint into metadata, and THE CLR MUST ACCEPT WHAT WAS WRITTEN.
//
// THE UNION IS THE ROW THAT EARNS ITS PLACE. A union is TWO generic-parameter owners — the abstract
// base and every nested case, which REDECLARES the same parameters — and the CLR refuses to load a
// case whose parameter is LESS CONSTRAINED than its base's. An emitter that constrained the base and
// forgot the cases would produce an assembly that emits cleanly and then throws `TypeLoadException`
// the moment anything touches it. There is no way to write that as a comment: either this file loads
// or the whole project fails.
//
// Before this arc none of these parsed at all: `class Box<T> where T : struct` answered
// `NL102 Expected '{', got 'where'`, and `website/docs/types.md` documented the feature anyway.
class ConstrainedBox<T> where T: struct {
    Value: T

    constructor(value: T) {
        Value = value
    }
}

struct ConstrainedPair<T> where T: struct {
    First: T

    constructor(first: T) {
        First = first
    }
}

record ConstrainedHolder<T> where T: class {
    Item: T
}

interface ConstrainedRepo<T> where T: class {
    func Fetch(): T
}

interface ConstraintMarker {
    func Mark(): int
}

// A base-type constraint naming a user interface, which is the arm that writes
// `SetInterfaceConstraints` rather than the attribute word.
class ConstrainedByInterface<T> where T: ConstraintMarker {
    Count: int
}

// TWO cases, both redeclaring the constrained parameter. This is the type-load proof.
union ConstrainedMaybe<T> where T: struct {
    Present { value: T }
    Absent
}

func BoxedValue(): int {
    box := new ConstrainedBox<int>(41)
    return box.Value + 1
}

test "a class with a struct constraint emits, loads and runs" {
    assert BoxedValue() == 42
}

test "a constrained struct loads and carries its field" {
    // Written through a constructor rather than a field assignment: a field WRITE on a generic struct
    // local declines at `emit.local.initializer`, which is a surface gap unrelated to constraints.
    pair := new ConstrainedPair<int>(7)
    assert pair.First == 7
}

test "a constrained union with two cases type-loads, which is what the CLR refuses when a case is less constrained than its base" {
    // Constructing either case forces the NESTED type to load, which is where a base/case constraint
    // mismatch throws `TypeLoadException`. Reaching the assertion at all is the contract; the values
    // are incidental, and are only compared because an assert needs something to say.
    present := new ConstrainedMaybe.Present<int> { value: 5 }
    presentLoaded := present != null
    assert presentLoaded

    absent := new ConstrainedMaybe.Absent<int>()
    absentLoaded := absent != null
    assert absentLoaded
}
