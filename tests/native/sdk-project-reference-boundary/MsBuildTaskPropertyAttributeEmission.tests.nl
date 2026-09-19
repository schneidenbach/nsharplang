namespace NSharpLang.SdkProjectReferenceBoundary.Tests

import System
import System.Reflection
import Microsoft.Build.Framework

// THE MSBUILD MARKERS ARE EMITTED BY ONE WRITER, AND THE COUNT IS THE CONTRACT.
//
// `[Microsoft.Build.Framework.Required]` and `[…Output]` are the two attributes the declaration
// scanner recognizes by hand, and for a while the emitter wrote them TWICE: once from that scanner's
// `ColumnarPropertyRows.HasMsBuild*Attribute` column, and again from the general source-attribute
// queue once attribute attachment reached property rows. Neither attribute is `AllowMultiple`, so two
// rows is invalid metadata, and `Attribute.GetCustomAttribute` — what MSBuild's own task reflection
// reaches for — throws `AmbiguousMatchException` on it.
//
// The estate could not see this. Every estate probe is compiled by the PINNED SEED in `bootstrap/`,
// which predates the second writer, so the duplicate only appeared after a reseed had already
// installed the tip compiler as the seed. The probes below are compiled by the CLI under test, so
// this project answers for the tip compiler's own emission without one.
class MsBuildMarkerProbe {
    private storedValue: string

    constructor() {
        storedValue = ""
    }

    [Microsoft.Build.Framework.Required]
    Input: string {
        get {
            return storedValue
        }
        set {
            storedValue = value
        }
    }

    [Microsoft.Build.Framework.Output]
    Result: string {
        get {
            return storedValue
        }
    }

    // THE SUFFIXED SPELLING AND A STATIC PROPERTY, because the emitter declares a static property
    // down a separate branch from an instance one and both branches carried the second writer.
    [Microsoft.Build.Framework.RequiredAttribute()]
    static Revision: int {
        get {
            return 7
        }
    }

    [Microsoft.Build.Framework.OutputAttribute()]
    static Generation: int {
        get {
            return 9
        }
    }

    // THE IMPORTED SPELLING IS THE SAME ATTRIBUTE. The declaration scanner deliberately refuses it —
    // it matches a fully-qualified name textually and nothing else — so under the old hard-coded
    // writer this property reached the assembly with NO marker at all. The binder resolves it the way
    // it resolves every other attribute name, so it carries exactly one.
    [Required]
    Imported: string {
        get {
            return storedValue
        }
    }
}

func MsBuildMarkerProperty(name: string): PropertyInfo {
    declared: PropertyInfo? = typeof(MsBuildMarkerProbe).GetProperty(
        name,
        BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance
    )
    return must declared
}

func MsBuildMarkerAssertExactlyOne(name: string, attributeType: Type) {
    property := MsBuildMarkerProperty(name)
    assert property.GetCustomAttributes(false).Length == 1, name
    matching := property.GetCustomAttributes(attributeType, false)
    assert matching.Length == 1, name
    // The singular overload is what MSBuild's task reflection calls, and it THROWS on a second row.
    single := property.GetCustomAttribute(attributeType, false)
    assert single != null, name
}

test "a Required marker on a task property is emitted exactly once" {
    MsBuildMarkerAssertExactlyOne("Input", typeof(Microsoft.Build.Framework.RequiredAttribute))
}

test "an Output marker on a task property is emitted exactly once" {
    MsBuildMarkerAssertExactlyOne("Result", typeof(Microsoft.Build.Framework.OutputAttribute))
}

test "a static task property's markers are emitted exactly once in both spellings" {
    MsBuildMarkerAssertExactlyOne("Revision", typeof(Microsoft.Build.Framework.RequiredAttribute))
    MsBuildMarkerAssertExactlyOne("Generation", typeof(Microsoft.Build.Framework.OutputAttribute))
}

test "the imported Required spelling reaches the property row once" {
    MsBuildMarkerAssertExactlyOne("Imported", typeof(Microsoft.Build.Framework.RequiredAttribute))
}

test "a Required marker carries the no-argument constructor and an empty blob" {
    property := MsBuildMarkerProperty("Input")
    data := property.GetCustomAttributesData()
    assert data.get_Count() == 1
    attribute := data.get_Item(0)
    assert attribute.get_AttributeType() == typeof(Microsoft.Build.Framework.RequiredAttribute)
    constructor := attribute.get_Constructor()
    assert constructor.get_DeclaringType() == typeof(Microsoft.Build.Framework.RequiredAttribute)
    assert constructor.GetParameters().Length == 0
    assert attribute.get_ConstructorArguments().get_Count() == 0
    assert attribute.get_NamedArguments().get_Count() == 0
}
