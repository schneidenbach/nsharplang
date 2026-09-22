namespace NSharpLang.CensusTestRefs

import System
import System.Reflection
import Xunit

// EVERY ASSERTION HERE READS THE EMITTED ASSEMBLY, so a passing row means the compiler bound an
// attribute declared in the SIBLING file, resolved its external `FactAttribute` base out of the test
// reference set, wrote the custom-attribute row, and the CLR decoded it back into a live instance.

// A method carrying a source attribute declared in the other file.
class MarkedTarget {
    [Marker("written in a different file from its declaration")]
    func Marked() {
    }

    func Unmarked() {
    }
}

// THE LOWERED TYPE IS NAMED AFTER THE FILE THAT WROTE THE ROWS, in that file's namespace: the rows
// below live in `TestRefs.tests.nl` under `NSharpLang.CensusTestRefs`, so they land on
// `NSharpLang.CensusTestRefs.TestRefsTests`. `FactAttributes.tests.nl` declares no `test` block and
// therefore contributes no type at all.
func GeneratedTestType(): Type {
    found: Type? = typeof(SlowFactAttribute).Assembly.GetType("NSharpLang.CensusTestRefs.TestRefsTests")
    return must found
}

// A `test "..."` block becomes a method whose name is derived from its sentence, so the method is
// found by the `[Trait("NSharpDescription", ...)]` row that carries the sentence itself.
func TestMethodFor(description: string): MethodInfo {
    methods := GeneratedTestType().GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
    index := 0
    while index < methods.Length {
        traits := methods[index].GetCustomAttributes(typeof(TraitAttribute), false)
        if traits.Length > 0 {
            data := methods[index].GetCustomAttributesData()
            dataIndex := 0
            while dataIndex < data.Count {
                row := data[dataIndex]
                if row.AttributeType == typeof(TraitAttribute) && row.ConstructorArguments.Count == 2 {
                    value := row.ConstructorArguments[1].Value as string
                    if value == description {
                        return methods[index]
                    }
                }

                dataIndex = dataIndex + 1
            }
        }

        index = index + 1
    }

    throw new InvalidOperationException("No generated test method carries the description '" + description + "'.")
}

func FactDerivedAttributeCount(method: MethodInfo): int {
    data := method.GetCustomAttributesData()
    total := 0
    index := 0
    while index < data.Count {
        walked := data[index].AttributeType
        depth := 0
        while depth < 16 {
            if walked == null {
                depth = 16
            } else if walked == typeof(FactAttribute) {
                total = total + 1
                depth = 16
            } else {
                walked = walked.BaseType
                depth = depth + 1
            }
        }

        index = index + 1
    }

    return total
}

// ─── THE CROSS-FILE SOURCE ATTRIBUTE ──────────────────────────────────────────────────────────

test "a source attribute declared in another file binds and reaches metadata" {
    method: MethodInfo? = typeof(MarkedTarget).GetMethod("Marked")
    found := (must method).GetCustomAttribute(typeof(MarkerAttribute), false) as MarkerAttribute

    assert found != null
    assert found.Note == "written in a different file from its declaration"
}

test "an unmarked member carries no attribute, so the row above is a fact about the write" {
    method: MethodInfo? = typeof(MarkedTarget).GetMethod("Unmarked")
    assert (must method).GetCustomAttribute(typeof(MarkerAttribute), false) == null
}

// ─── AN ATTRIBUTE DERIVED FROM THE TEST FRAMEWORK'S OWN ────────────────────────────────────────

test "a fact-derived source attribute resolves its external base out of the test reference set" {
    assert typeof(SlowFactAttribute).BaseType == typeof(FactAttribute)
    assert typeof(UnavailableFactAttribute).BaseType == typeof(FactAttribute)
}

test "a source constructor writes a property its EXTERNAL base declares" {
    // `Skip` is declared by `Xunit.FactAttribute`, not by anything this program wrote. Both the bare
    // and the explicit-`this` spelling reach the same inherited setter.
    unavailable := new UnavailableFactAttribute()
    assert unavailable.Skip == "the census fixture declares this prerequisite unavailable"

    explicitThis := new ExplicitSkipFactAttribute()
    assert explicitThis.Skip == "written through an explicit this"

    // The base's own default is untouched, so the write above is the only thing that set it.
    plain := new SlowFactAttribute()
    assert plain.Skip == null
}

// ─── ATTRIBUTES ON A `test` BLOCK ──────────────────────────────────────────────────────────────

[SlowFact]
test "a test carrying a fact-derived attribute is discovered and run" {
    assert 1 + 1 == 2
}

test "a plain test carries exactly one fact attribute, the synthesized one" {
    method := TestMethodFor("a plain test carries exactly one fact attribute, the synthesized one")

    assert FactDerivedAttributeCount(method) == 1
    assert method.GetCustomAttribute(typeof(FactAttribute), false) != null
}

test "a test that writes its OWN fact carries that one and not a second synthesized one" {
    method := TestMethodFor("a test carrying a fact-derived attribute is discovered and run")

    // XUNIT REFUSES A METHOD WITH TWO. "Test method has multiple [Fact]-derived attributes" is a
    // discovery error, not a failing test, so a second synthesized `[Fact]` would make the row above
    // silently disappear from the run rather than fail.
    assert FactDerivedAttributeCount(method) == 1
    assert method.GetCustomAttribute(typeof(SlowFactAttribute), false) != null

    // The description trait is attached either way — it is what `nlc test` reports as the test's name.
    assert method.GetCustomAttribute(typeof(TraitAttribute), false) != null
}

// THE SKIPPED ROW IS THE CONTRACT. `nlc test` reports it as `skipped`, which is why this project's
// sweep is green with a nonzero skip count: xunit reads `Skip` off the FactAttribute the method
// carries, and the one it carries here is the derived attribute the fixture declared.
[UnavailableFact]
test "a test whose derived fact sets Skip is reported as skipped, never run" {
    throw new InvalidOperationException("A skipped test's body must not run.")
}
