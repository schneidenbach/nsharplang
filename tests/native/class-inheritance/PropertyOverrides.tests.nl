namespace NSharpLang.ClassInheritance.Tests

import System
import System.Reflection

func PropertyAccessor(owner: Type, name: string, setter: bool): MethodInfo {
    flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly
    property := owner.GetProperty(name, flags)
    if property == null {
        throw new InvalidOperationException("'" + owner.Name + "' declares no property named '" + name + "'.")
    }
    accessor := setter ? property.GetSetMethod(true) : property.GetGetMethod(true)
    if accessor == null {
        throw new InvalidOperationException("'" + owner.Name + "." + name + "' has no " + (setter ? "setter" : "getter") + ".")
    }
    return accessor
}

func OpensSlot(accessor: MethodInfo): bool => (accessor.Attributes & MethodAttributes.VtableLayoutMask) == MethodAttributes.NewSlot

// ---- dispatch ---------------------------------------------------------------------------------------

test "a written override answers through a base-typed receiver" {
    label: Label = new LoudLabel()
    assert label.Text == "LOUD"
    sealedLabel: Label = new FinalLabel()
    assert sealedLabel.Text == "final"
    displayed: IDisplayText = new LoudLabel()
    assert displayed.Text == "LOUD"
}

test "the declaring type's own bodies dispatch to the override" {
    assert new Label().Render() == "[plain]"
    assert new LoudLabel().Render() == "[LOUD]"
    assert new FinalLabel().Render() == "[final]"
}

test "a getter and setter overridden as a pair dispatch both ways, declared before their base" {
    counter: Counter = new ClampedCounter()
    counter.Count = 25
    assert counter.Count == 10
    counter.Count = 4
    counter.Bump()
    assert counter.Count == 5

    plain := new Counter()
    plain.Count = 25
    plain.Bump()
    assert plain.Count == 26
}

test "an override of Exception.Message is the message every caller reads" {
    error: Exception = new ParseError(7)
    assert error.Message == "parse error at line 7"
    try {
        throw new ParseError(12)
    } catch caught: Exception {
        assert caught.Message == "parse error at line 12"
    }
}

// ---- written and bare members override each other ---------------------------------------------------

test "a written get/set override replaces both accessors of a bare virtual member" {
    gauge: Gauge = new DoubledGauge()
    gauge.Reading = 4
    assert gauge.Reading == 8
    assert gauge.Report() == "reading 8"
}

test "a written get-only override of a bare virtual member inherits its setter" {
    gauge: Gauge = new FixedGauge()
    gauge.Reading = 3
    assert gauge.Reading == 42
    assert gauge.Report() == "reading 42"
    assert gauge.WeightValue() == 9
}

test "a bare override member replaces a written virtual property, declared before its base" {
    titled: Titled = new Subtitled()
    assert titled.Title == "subtitled"
    assert titled.Heading() == "# subtitled"
    titled.Title = "changed"
    assert titled.Heading() == "# changed"
    assert new Titled().Heading() == "# titled"
}

test "a written override fills a bare abstract member's two slots" {
    badge: Badge = new StarBadge()
    assert badge.Show() == "badge star"
    badge.Caption = "gold"
    assert badge.Caption == "GOLD"
}

test "a subclass closing a generic base overrides its written virtual property" {
    assert new FortyTwo().Read() == 42
    assert new Holder<int>().Read() == 0
}

// ---- the metadata -----------------------------------------------------------------------------------

test "a virtual written property opens a slot for each accessor" {
    getter := PropertyAccessor(typeof(Label), "Text", false)
    assert getter.IsVirtual && !getter.IsFinal && OpensSlot(getter)
    assert getter.IsPublic

    countGetter := PropertyAccessor(typeof(Counter), "Count", false)
    countSetter := PropertyAccessor(typeof(Counter), "Count", true)
    assert countGetter.IsVirtual && OpensSlot(countGetter)
    assert countSetter.IsVirtual && OpensSlot(countSetter)
}

test "a written override reuses the base's slot and `sealed override` closes it" {
    getter := PropertyAccessor(typeof(LoudLabel), "Text", false)
    assert getter.IsVirtual && !getter.IsFinal && !OpensSlot(getter)
    assert getter.GetBaseDefinition().DeclaringType == typeof(Label)

    sealedGetter := PropertyAccessor(typeof(FinalLabel), "Text", false)
    assert sealedGetter.IsVirtual && sealedGetter.IsFinal && !OpensSlot(sealedGetter)
    assert sealedGetter.GetBaseDefinition().DeclaringType == typeof(Label)

    messageGetter := PropertyAccessor(typeof(ParseError), "Message", false)
    assert messageGetter.GetBaseDefinition().DeclaringType == typeof(Exception)

    readingGetter := PropertyAccessor(typeof(DoubledGauge), "Reading", false)
    readingSetter := PropertyAccessor(typeof(DoubledGauge), "Reading", true)
    assert readingGetter.GetBaseDefinition().DeclaringType == typeof(Gauge)
    assert readingSetter.GetBaseDefinition().DeclaringType == typeof(Gauge)
}

test "a get-only override declares only the getter" {
    flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly
    reading := must typeof(FixedGauge).GetProperty("Reading", flags)
    assert reading.GetSetMethod(true) == null
}

test "an override with no accessibility word takes the slot's" {
    assert PropertyAccessor(typeof(Gauge), "Weight", false).IsFamily
    assert PropertyAccessor(typeof(FixedGauge), "Weight", false).IsFamily
}
