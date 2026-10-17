namespace NSharpLang.AutoProperties.Tests

import System
import System.Collections.Generic
import System.Linq
import System.Reflection
import System.Runtime.CompilerServices

func Accessor(owner: Type, name: string, setter: bool): MethodInfo {
    property := must owner.GetProperty(name, InstanceMembers())
    if setter {
        return must property.GetSetMethod(true)
    }
    return must property.GetGetMethod(true)
}

// Virtual and not sealed — the test Castle's proxy generator (and so EF Core's) applies to every
// member it overrides.
func IsProxyOverridable(accessor: MethodInfo): bool => accessor.IsVirtual && !accessor.IsFinal

func OpensNewSlot(accessor: MethodInfo): bool => (accessor.Attributes & MethodAttributes.VtableLayoutMask) == MethodAttributes.NewSlot

// ---- the metadata ---------------------------------------------------------------------------------

test "a virtual bare member is C#'s public virtual auto-property" {
    getter := Accessor(typeof(Gauge), "Label", false)
    setter := Accessor(typeof(Gauge), "Label", true)
    assert IsProxyOverridable(getter) && IsProxyOverridable(setter)
    assert OpensNewSlot(getter) && OpensNewSlot(setter)
    assert getter.IsPublic && setter.IsPublic
    assert getter.IsDefined(typeof(CompilerGeneratedAttribute), false)

    // The storage is C#'s private field: no body outside the accessors and the initializer touches it.
    storage := must typeof(Gauge).GetField("<Label>k__BackingField", InstanceMembers())
    assert storage.IsPrivate
    assert typeof(Gauge).GetField("Label", InstanceMembers()) == null
}

test "an override reuses the base's slot and `sealed override` closes it" {
    getter := Accessor(typeof(LoudGauge), "Label", false)
    assert IsProxyOverridable(getter)
    assert !OpensNewSlot(getter)
    assert getter.GetBaseDefinition().DeclaringType == typeof(Gauge)
    assert (must typeof(LoudGauge).GetField("<Label>k__BackingField", InstanceMembers())).IsPrivate

    sealedGetter := Accessor(typeof(FinalGauge), "Label", false)
    assert sealedGetter.IsVirtual && sealedGetter.IsFinal
    assert sealedGetter.GetBaseDefinition().DeclaringType == typeof(Gauge)
}

test "an override with no accessibility word takes the slot's" {
    assert Accessor(typeof(Gauge), "Calibration", false).IsFamily
    assert Accessor(typeof(LoudGauge), "Calibration", false).IsFamily
    assert Accessor(typeof(LoudGauge), "Calibration", true).IsFamily
}

test "an abstract bare member is a pair of slots with no storage" {
    getter := Accessor(typeof(Shape), "Name", false)
    setter := Accessor(typeof(Shape), "Name", true)
    assert getter.IsAbstract && setter.IsAbstract
    assert typeof(Shape).GetField("<Name>k__BackingField", InstanceMembers()) == null
    assert !getter.IsDefined(typeof(CompilerGeneratedAttribute), false)
}

// ---- dispatch -------------------------------------------------------------------------------------

test "a base-typed receiver reaches the override" {
    gauge: Gauge = new LoudGauge()
    assert gauge.Label == "loud"
    assert gauge.Reading == 1000
    gauge.Label = "changed"
    assert gauge.Label == "changed"
    labeled: IGaugeLabel = gauge
    assert labeled.Label == "changed"
}

test "the declaring type's own bodies dispatch: reads, writes, steps, compound assignment and closures" {
    gauge: Gauge = new LoudGauge()
    assert gauge.Describe() == "loud=1000"
    assert gauge.Step() == 1111
    assert gauge.Reader()() == "loud:1111"
    gauge.Rename("renamed")
    assert gauge.Label == "renamed"
    assert gauge.CalibrationValue() == 7
    assert gauge.Notes == null
}

test "an override owns its storage, and `base.` reads the base's" {
    loud := new LoudGauge()
    assert loud.BaseLabel() == "gauge"
    loud.Label = "x"
    assert loud.BaseLabel() == "gauge"

    plain := new Gauge()
    assert plain.Describe() == "gauge=0"
    assert plain.Step() == 111
}

test "an object initializer sets a virtual member through its setter" {
    gauge := new LoudGauge { Label: "set", Reading: 5 }
    assert gauge.Describe() == "set=5"
}

test "an abstract member is filled by the override" {
    shape: Shape = new Square()
    assert shape.Show() == "shape square"
    shape.Name = "round"
    assert shape.Show() == "shape round"
    assert shape.Tag == null
}

test "an override over a generic base and over a BCL base" {
    holder := new IntHolder()
    assert holder.Read() == 42
    assert holder.Value == 42

    error: Exception = new GaugeError()
    assert error.HelpLink == "https://example.test/help"
    error.HelpLink = "elsewhere"
    assert error.HelpLink == "elsewhere"
}

test "a record's virtual members keep `with` and equality" {
    sample := new Sample { Label: "a", Count: 1 }
    assert IsProxyOverridable(Accessor(typeof(Sample), "Label", false))
    copy := sample with { Count: 2 }
    assert copy.Label == "a"
    assert copy.Count == 2
    assert sample.Count == 1
    assert sample.Equals(new Sample { Label: "a", Count: 1 })
    assert !sample.Equals(copy)
}

// ---- EF Core lazy-loading proxies ---------------------------------------------------------------

test "EF Core lazy-loading proxies override virtual navigations, inside the entity's own bodies too" {
    setup := new Library()
    author := new Author { Name: "Le Guin" }
    author.Books.Add(new Book { Title: "The Dispossessed" })
    setup.Authors.Add(author)
    setup.SaveChanges()

    reader := new Library()
    books: IEnumerable<Book> = reader.Books
    loaded := books.Single()
    assert loaded.GetType() != typeof(Book)
    assert loaded.GetType().BaseType == typeof(Book)
    assert loaded.AuthorName() == "Le Guin"
    assert (must loaded.Author).Books.Count == 1
}
