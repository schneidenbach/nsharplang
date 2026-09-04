namespace NSharpLang.Compiler


// THE RULES THAT TURN A `where` CLAUSE INTO METADATA, CROSSED WITHOUT AN EMITTER.
//
// These lived inline in `ColumnarIlEmitter`'s FUNCTION arm and nowhere else, which is exactly why a
// `class Box<T> where T: struct` emitted a type parameter with `attrs=None` — the five
// `TypeBuilder.DefineGenericParameters` sites had no rules to apply. Lifting them here is what let one
// C# helper serve the method site and the type sites, and it is what makes them assertable at all: an
// emitter arm can only be crossed by emitting.

// ── The attribute word ──────────────────────────────────────────────────────────────────────────
test "each special constraint maps to its own CLR attribute bit" {
    assert ColumnarGenericConstraintPlanner.AttributeBitsFor(0) == 0
    assert ColumnarGenericConstraintPlanner.AttributeBitsFor(1) == 4
    assert ColumnarGenericConstraintPlanner.AttributeBitsFor(4) == 16
}

test "`struct` IMPLIES the default-constructor bit, and saying `new()` as well changes nothing" {
    // The CLR records both bits for a value-type constraint, because every value type has a
    // parameterless constructor. This is the row that would silently differ if the two were folded.
    structOnly := ColumnarGenericConstraintPlanner.AttributeBitsFor(2)
    assert structOnly == 24

    // `where T: struct, new()` is the same word — not a doubled bit, and not a refusal.
    assert ColumnarGenericConstraintPlanner.AttributeBitsFor(6) == 24
}

test "`class` and `new()` combine, which is the documented `Service<T>` header" {
    // `where T: class, IDisposable, new()` — the type constraint is not a special, so the word is
    // ReferenceType | DefaultConstructor.
    assert ColumnarGenericConstraintPlanner.AttributeBitsFor(5) == 20
}

// ── Base-constraint admissibility ───────────────────────────────────────────────────────────────
test "a type PARAMETER is always an admissible base constraint, whatever else is asked" {
    // `where T: U` is a real constraint. The caller must answer this arm BEFORE touching `IsSZArray`,
    // which throws on a bare parameter under persisted emit — so the other five answers are noise here.
    assert ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(true, false, false, false, false, false)
    assert ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(true, true, true, true, true, true)
}

test "an EMITTED user type is admissible only with reference layout" {
    // A value struct cannot be a base, so a TypeBuilder that is a value type is refused; a reference
    // one is admitted whatever its other answers, because a TypeBuilder answers them structurally.
    assert ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(false, true, false, false, false, false)
    assert !ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(false, true, true, false, false, false)
}

test "a runtime target must be a plain class: not builder-built, not a value type, not an array" {
    // The admitted shape.
    assert ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(false, false, false, false, false, true)

    // Each refusal on its own, so a future change cannot drop one without a named failure.
    assert !ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(false, false, true, false, false, true)
    assert !ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(false, false, false, true, false, true)
    assert !ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(false, false, false, false, true, true)
    assert !ColumnarGenericConstraintPlanner.IsAdmissibleBaseConstraint(false, false, false, false, false, false)
}

// ── The circular-constraint decline ─────────────────────────────────────────────────────────────
test "a constraint chain that re-enters itself is refused, because the CLR refuses it at LOAD" {
    // `where T: T` — the one-parameter cycle.
    selfCycle := new int[](1)
    selfCycle[0] = 0
    assert ColumnarGenericConstraintPlanner.HasCircularConstraint(selfCycle)

    // `where T: U where U: T` — the two-parameter cycle.
    pairCycle := new int[](2)
    pairCycle[0] = 1
    pairCycle[1] = 0
    assert ColumnarGenericConstraintPlanner.HasCircularConstraint(pairCycle)

    // A three-step cycle, so the walk is not merely a two-step comparison.
    triple := new int[](3)
    triple[0] = 1
    triple[1] = 2
    triple[2] = 0
    assert ColumnarGenericConstraintPlanner.HasCircularConstraint(triple)
}

test "an acyclic chain is admitted, however long, and so is a set with no chains at all" {
    // `where T: U where U: V` — a chain that terminates.
    chain := new int[](3)
    chain[0] = 1
    chain[1] = 2
    chain[2] = -1
    assert !ColumnarGenericConstraintPlanner.HasCircularConstraint(chain)

    // No parameter constrains another.
    none := new int[](3)
    none[0] = -1
    none[1] = -1
    none[2] = -1
    assert !ColumnarGenericConstraintPlanner.HasCircularConstraint(none)

    // The empty owner.
    assert !ColumnarGenericConstraintPlanner.HasCircularConstraint(new int[](0))
}

test "constraint rows on a NON-generic owner are malformed" {
    assert ColumnarGenericConstraintPlanner.HasConstraintsWithoutTypeParameters(0, 1, 0)
    assert ColumnarGenericConstraintPlanner.HasConstraintsWithoutTypeParameters(0, 0, 1)
    assert !ColumnarGenericConstraintPlanner.HasConstraintsWithoutTypeParameters(0, 0, 0)
    assert !ColumnarGenericConstraintPlanner.HasConstraintsWithoutTypeParameters(1, 1, 1)
}

test "the where-site bounds guards answer for a parameter past the end of a short row" {
    // THE EXACT SHORT SHAPE, BUILT RATHER THAN DESCRIBED: three type parameters, TWO specials rows and
    // ONE type-constraint row. `SpecialsOrEmpty`/`TypesOrEmpty` normalise NULL but not SHORT, so this
    // reaches emit and an unguarded read would throw.
    specials := new int[](2)
    specials[0] = ColumnarConstraintColumns.ClassFlag()
    specials[1] = ColumnarConstraintColumns.StructFlag()

    assert ColumnarGenericConstraintPlanner.SpecialAt(specials, 0) == ColumnarConstraintColumns.ClassFlag()
    assert ColumnarGenericConstraintPlanner.SpecialAt(specials, 1) == ColumnarConstraintColumns.StructFlag()
    // Past the end: NO special constraint, not a throw and not a missing row.
    assert ColumnarGenericConstraintPlanner.SpecialAt(specials, 2) == 0
    assert ColumnarGenericConstraintPlanner.SpecialAt(specials, 99) == 0
    assert ColumnarGenericConstraintPlanner.SpecialAt(null, 0) == 0

    types := new string[][](1)
    first := new string[](1)
    first[0] = "Sortable"
    types[0] = first

    assert ColumnarGenericConstraintPlanner.TypeConstraintsAt(types, 0).Length == 1
    assert ColumnarGenericConstraintPlanner.TypeConstraintsAt(types, 0)[0] == "Sortable"
    // Past the end: an EMPTY row, so the caller iterates nothing rather than testing for null.
    assert ColumnarGenericConstraintPlanner.TypeConstraintsAt(types, 1).Length == 0
    assert ColumnarGenericConstraintPlanner.TypeConstraintsAt(types, 99).Length == 0
    assert ColumnarGenericConstraintPlanner.TypeConstraintsAt(null, 0).Length == 0

    // And the guarded read composes with the attribute rule: a parameter past the end contributes no bits.
    assert ColumnarGenericConstraintPlanner.AttributeBitsFor(ColumnarGenericConstraintPlanner.SpecialAt(specials, 2)) == 0
}

test "missing type-constraint rows share one empty array and present rows retain their identity" {
    first := ColumnarGenericConstraintPlanner.TypeConstraintsAt(null, 0)
    shortRows := new string[][](1)
    present := new string[](0)
    shortRows[0] = present
    pastEnd := ColumnarGenericConstraintPlanner.TypeConstraintsAt(shortRows, 1)
    repeated := ColumnarGenericConstraintPlanner.TypeConstraintsAt(shortRows, 99)

    assert first.Length == 0
    assert Object.ReferenceEquals(first, pastEnd)
    assert Object.ReferenceEquals(first, repeated)
    assert Object.ReferenceEquals(present, ColumnarGenericConstraintPlanner.TypeConstraintsAt(shortRows, 0))
    assert !Object.ReferenceEquals(present, first)
}
