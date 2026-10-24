namespace NSharpLang.ClassInheritance.Tests

import System
import System.Collections.Generic
import System.Reflection
import System.Text.Json

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

// ---- a written property's accessibility -------------------------------------------------------------

func LedgerAccessor(name: string): MethodInfo {
    flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly
    property := typeof(Ledger).GetProperty(name, flags)
    if property == null {
        throw new InvalidOperationException("'Ledger' declares no property named '" + name + "'.")
    }
    return must property.GetGetMethod(true)
}

test "a written property's accessors take its accessibility word, or its casing" {
    assert LedgerAccessor("Plain").IsPublic
    assert LedgerAccessor("open").IsAssembly
    assert LedgerAccessor("Shown").IsPublic
    assert LedgerAccessor("Guarded").IsFamily
    assert LedgerAccessor("Inside").IsAssembly
    assert LedgerAccessor("Secret").IsPrivate
    assert LedgerAccessor("Shared").IsFamilyOrAssembly
    assert LedgerAccessor("Count").IsPublic && LedgerAccessor("Count").IsStatic
    assert LedgerAccessor("Seed").IsFamily && LedgerAccessor("Seed").IsStatic

    flags := BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly
    balance := must typeof(Ledger).GetProperty("Balance", flags)
    assert (must balance.GetSetMethod(true)).IsPrivate
}

test "only the exported properties are part of the type's public surface" {
    publicNames := new List<string>()
    for property in typeof(Ledger).GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly) {
        publicNames.Add(property.Name)
    }
    publicNames.Sort(StringComparer.Ordinal)
    assert string.Join(",", publicNames) == "Count,Plain,Shown"

    // What a serializer in another assembly sees is that same surface.
    assert JsonSerializer.Serialize(new Ledger()) == "{\"Plain\":1,\"Shown\":4}"
}

test "the declaring type's own bodies, closures and async bodies read its non-public properties" {
    ledger := new Ledger()
    assert ledger.Total() == 1 + 2 + 4 + 8 + 16 + 32 + 64 + 128 + 256 + 3
    ledger.Deposit(10)
    assert ledger.SecretReader()() == 32 + 13
    assert ledger.SecretLater().Result == 32 + 8
    assert new AuditedLedger().GuardedReader()() == 8 + 256
}

test "a non-public property fills an interface's value slot" {
    written: ICaption = new InternalCaption()
    assert written.Caption == "internal"
    bare: ICaption = new BareInternalCaption()
    assert bare.Caption == "bare"
    assert PropertyAccessor(typeof(InternalCaption), "Caption", false).IsAssembly
    assert PropertyAccessor(typeof(BareInternalCaption), "Caption", false).IsAssembly
}

// ---- a get-only override inherits the base's setter --------------------------------------------------

test "a get-only override is written through the deriving type with the setter it inherited" {
    gauge := new FixedGauge()
    gauge.Reading = 3
    gauge.Reading += 2
    gauge.Reading++
    assert gauge.Reading == 42
    assert gauge.Report() == "reading 42"

    initialized := new FixedGauge { Reading: 11 }
    assert initialized.Reading == 42

    // Inside the overriding type: a write stores through the base's setter, a read is the override's.
    assert new PinnedGauge().Overwrite() == 100
}

test "a get-only override of a CLR base property inherits that base's setter" {
    linked := new LinkedError()
    linked.HelpLink = "https://example.test/ignored"
    assert linked.HelpLink == "https://example.test/fixed"
    asException: Exception = linked
    assert asException.HelpLink == "https://example.test/fixed"

    plain := new PlainError()
    plain.HelpLink = "https://example.test/plain"
    assert plain.HelpLink == "https://example.test/plain"
}
