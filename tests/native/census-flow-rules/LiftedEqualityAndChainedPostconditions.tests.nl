namespace NSharpLang.CensusFlowRules.Tests

import System.Collections.Generic

func FlowSymbols(): Dictionary<string, FlowSymbolInfo> {
    symbols := new Dictionary<string, FlowSymbolInfo>()
    symbols["Parse"] = new FlowSymbolInfo(1, "Parse")
    symbols["Widget"] = new FlowSymbolInfo(3, "Widget")
    symbols["field"] = new FlowSymbolInfo(9, "field")
    return symbols
}

func FlowLocations(): Dictionary<string, List<string>> {
    locations := new Dictionary<string, List<string>>()
    entries := new List<string>()
    entries.Add("Program.nl:1")
    locations["Parse"] = entries
    locations["empty"] = new List<string>()
    return locations
}

func FlowTraits(): Dictionary<string, List<string>> {
    traits := new Dictionary<string, List<string>>()
    descriptions := new List<string>()
    descriptions.Add("first")
    descriptions.Add("second")
    traits["description"] = descriptions
    return traits
}

func FlowDocument(): FlowDocumentState {
    return new FlowDocumentState(FlowSymbols(), FlowLocations(), FlowTraits())
}

func FlowEmptyDocument(): FlowDocumentState {
    return new FlowDocumentState(null, null, FlowTraits())
}

// ── §2 the property-chain receiver inside `&&` ─────────────────────────────────────────────────

test "a postcondition files against a call whose receiver is a property chain" {
    doc := FlowDocument()

    assert IsFunctionSymbol(doc, "Parse")
    assert !IsFunctionSymbol(doc, "field")
    assert !IsFunctionSymbol(doc, "nothing")
}

test "the second chain in the same function narrows on its own terms" {
    doc := new FlowDocumentState(new Dictionary<string, FlowSymbolInfo>(), FlowLocations(), FlowTraits())

    assert IsFunctionSymbol(doc, "Parse")
    assert !IsFunctionSymbol(doc, "empty")
}

test "a null chain takes neither branch and answers false" {
    assert !IsFunctionSymbol(FlowEmptyDocument(), "Parse")
}

// ── §3 `x?.M(...) == true` ─────────────────────────────────────────────────────────────────────

test "a lifted `== true` decides the call and narrows what it left behind" {
    doc := FlowDocument()

    assert TypeNameOrNone(doc, "Parse") == "Parse"
    assert TypeNameOrNone(doc, "Widget") == "Widget"
    assert TypeNameOrNone(doc, "field") == "none"
    assert TypeNameOrNone(doc, "missing") == "none"

    // The `?.` is what makes the absent receiver answer `none` rather than throw.
    assert TypeNameOrNone(FlowEmptyDocument(), "Parse") == "none"
}

test "a lifted `== false` decides its TRUE branch, receiver included" {
    doc := FlowDocument()

    assert MissingCount(doc, "missing") == 3
    assert MissingCount(doc, "Parse") == -1
    assert MissingCount(FlowEmptyDocument(), "Parse") == -1
}

test "a lifted `!= true` decides its FALSE branch" {
    doc := FlowDocument()

    assert KindOrMissing(doc, "Parse") == 1
    assert KindOrMissing(doc, "field") == 9
    assert KindOrMissing(doc, "missing") == -1
    assert KindOrMissing(FlowEmptyDocument(), "Parse") == -1
}

test "a `?.` invocation is a real call with the callee's own result" {
    doc := FlowDocument()

    assert TraitCount(doc) == 2
    assert TraitCount(FlowEmptyDocument()) == 0
    assert ContainsSymbol(doc, "Parse")
    assert !ContainsSymbol(doc, "missing")
    assert !ContainsSymbol(FlowEmptyDocument(), "Parse")
}

// ── §4 the ternary condition ───────────────────────────────────────────────────────────────────

test "a postcondition in a ternary condition reaches the arm it proved" {
    doc := FlowDocument()

    assert FirstTrait(doc, "description") == "first"
    assert FirstTrait(doc, "missing") == null
    assert TraitOrFallback(doc, "description") == "first"
    assert TraitOrFallback(doc, "missing") == "fallback"
}

// ── lifted equality ────────────────────────────────────────────────────────────────────────────

test "a lifted equality answers bool, and an absent value equals only another absent one" {
    assert LiftedIntEquals(1, 1)
    assert !LiftedIntEquals(2, 1)
    assert !LiftedIntEquals(null, 1)
    assert !LiftedIntEquals(null, 0)

    assert !LiftedIntNotEquals(1, 1)
    assert LiftedIntNotEquals(2, 1)
    assert LiftedIntNotEquals(null, 1)

    assert BothLiftedEquals(null, null)
    assert BothLiftedEquals(4, 4)
    assert !BothLiftedEquals(null, 4)
    assert !BothLiftedEquals(4, null)
    assert !BothLiftedEquals(4, 5)

    assert ValueOnTheLeft(3, 3)
    assert !ValueOnTheLeft(3, null)
}

test "the `default` value of the element never makes an absent value compare equal" {
    // `GetValueOrDefault()` answers 0 for an absent `int?` and false for an absent `bool?`, so a
    // lowering that forgot the `HasValue` half would call these equal.
    assert !LiftedIntEquals(null, 0)
    assert !LiftedBoolIsFalse(null)
    assert !LiftedBoolIsTrue(null)
    assert LiftedBoolIsTrue(true)
    assert !LiftedBoolIsTrue(false)
    assert LiftedBoolIsFalse(false)
    assert !LiftedBoolIsFalse(true)
}

test "the lifted family covers the floating, char and enum elements too" {
    assert LiftedDoubleEquals(1.5, 1.5)
    assert !LiftedDoubleEquals(null, 0.0)
    assert LiftedCharEquals('a', 'a')
    assert LiftedCharEquals(null, null)
    assert !LiftedCharEquals(null, 'a')
    assert LiftedEnumEquals(FlowStage.Middle, FlowStage.Middle)
    assert !LiftedEnumEquals(null, FlowStage.Start)
    assert !LiftedEnumEquals(FlowStage.End, FlowStage.Start)
}

test "a lifted comparison evaluates its operands left to right" {
    log := new FlowOrderLog()
    assert LiftedOrder(log, 5, 5)
    assert log.Text == "LR"
}
