namespace NSharpLang.RecordWith.Tests

import System
import System.Collections
import System.IO
import System.Reflection

// --- Reference-record control ---------------------------------------------------------------------
test "a reference-record with clones and replaces the named member, leaving the source unchanged" {
    p1 := new Point { X: 10, Y: 20, Label: "a" }
    p2 := p1 with { X: 30 }
    assert p2.X == 30
    assert p2.Y == 20
    assert p2.Label == "a"
    // The clone is a distinct object; mutating it did not touch the source.
    assert p1.X == 10
}

// --- Value-record control + mutation isolation (the core value-semantics proof) --------------------

test "a value-record with copies by value: the modified copy is independent of the unchanged source" {
    c1 := new Rgb { R: 255, G: 0, B: 0 }
    c2 := c1 with { G: 128 }
    assert c2.R == 255
    assert c2.G == 128
    assert c2.B == 0
    // CRITICAL: a value-copy `with` must not alias the source. If the lowering wrote through the source
    // address instead of a fresh copy, c1.G would now read 128.
    assert c1.G == 0
}

test "a positional value-record with replaces the primary-constructor member and preserves the source" {
    m1 := new Meters(5)
    m2 := m1 with { value: 12 }
    assert m2.value == 12
    assert m1.value == 5
}

// --- Multiple updates ------------------------------------------------------------------------------

test "a value-record with applies multiple replacements in one expression and preserves untouched members" {
    c := new Rgb { R: 1, G: 2, B: 3 }
    recolored := c with { R: 10, B: 30 }
    assert recolored.R == 10
    assert recolored.G == 2
    assert recolored.B == 30
}

// --- Side-effect ordering --------------------------------------------------------------------------

test "with replacement values are evaluated in source order, left to right" {
    order := new EvaluationOrder()
    result := RecolorOrdered(new Rgb { R: 0, G: 0, B: 0 }, order)
    assert order.Ordinals.Count == 3
    assert order.Ordinals[0] == 1
    assert order.Ordinals[1] == 2
    assert order.Ordinals[2] == 3
    assert result.R == 10
    assert result.G == 20
    assert result.B == 30
}

// --- Persisted execution ---------------------------------------------------------------------------

test "a value-record with result persists through a local and reads back its replaced members" {
    original := new Rgb { R: 7, G: 8, B: 9 }
    updated := WithGreen(original, 88)
    stored := updated
    assert stored.G == 88
    assert stored.R == 7
    // The named-method call received the source by value; the source local is untouched.
    assert original.G == 8
}

test "a reference-record with through a named method persists and leaves the source object unchanged" {
    origin := new Point { X: 1, Y: 2, Label: "o" }
    moved := WithX(origin, 99)
    assert moved.X == 99
    assert moved.Y == 2
    assert origin.X == 1
}

// --- Exact emitted shape (reflection over the strategy N# selected) ---------------------------------

test "a value record carries no <Clone>$ method: its with lowers to a value copy, not a clone virtual" {
    cloneMethod := typeof(Rgb).GetMethod("<Clone>$")
    assert cloneMethod == null, "a record struct must not synthesize a <Clone>$ clone virtual"
}

test "a reference record carries the <Clone>$ clone virtual its with clones through" {
    cloneMethod := typeof(Point).GetMethod("<Clone>$")
    assert cloneMethod != null, "a record class must synthesize a <Clone>$ clone virtual"
    if cloneMethod != null {
        assert cloneMethod.get_ReturnType() == typeof(Point)
    }
}

// --- Invalid members and types are rejected --------------------------------------------------------

class RecordWithFixtureResult {
    Succeeded: bool
    Diagnostics: string

    constructor(succeeded: bool, diagnostics: string) {
        Succeeded = succeeded
        Diagnostics = diagnostics
    }
}

func SetFixtureObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// Drive the real production compiler on a single-file fixture through the public whole-project emit-only
// route and report whether it succeeded plus the first diagnostic.
func CompileRecordWithFixture(source: string): RecordWithFixtureResult {
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-record-with-" + Guid.NewGuid().ToString("N")
    )
    Directory.CreateDirectory(fixtureRoot)
    File.WriteAllText(Path.Combine(fixtureRoot, "Program.nl"), source)

    compilerType := Type.GetType("NSharpLang.Compiler.MultiFileCompiler, Compiler")
    projectConfigType := Type.GetType(
        "NSharpLang.Compiler.ProjectConfig, NSharpLang.Compiler.BootstrapServices"
    )
    if compilerType == null || projectConfigType == null {
        throw new InvalidOperationException("The production compiler types were not loadable.")
    }

    configConstructor := projectConfigType.GetConstructor(new Type[](0))
    if configConstructor == null {
        throw new InvalidOperationException("The production project configuration constructor was not found.")
    }
    config := configConstructor.Invoke(new object?[](0))

    constructorTypes := new Type[](2)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = projectConfigType
    constructor := compilerType.GetConstructor(constructorTypes)
    if constructor == null {
        throw new InvalidOperationException("The production compiler constructor was not found.")
    }
    constructorArguments := new object?[](2)
    SetFixtureObject(constructorArguments, 0, fixtureRoot)
    SetFixtureObject(constructorArguments, 1, config)
    compiler := constructor.Invoke(constructorArguments)

    compileParameterTypes := new Type[](4)
    compileParameterTypes[0] = typeof(string)
    compileParameterTypes[1] = typeof(string)
    compileParameterTypes[2] = typeof(bool)
    compileParameterTypes[3] = typeof(bool)
    compileMethod := compilerType.GetMethod("CompileToIlAssembly", compileParameterTypes)
    if compileMethod == null {
        throw new InvalidOperationException("The production compiler entry point was not found.")
    }
    compileArguments := new object?[](4)
    SetFixtureObject(compileArguments, 0, "RecordWithFixture")
    SetFixtureObject(
        compileArguments,
        1,
        Path.Combine(fixtureRoot, "out/RecordWithFixture.dll")
    )
    SetFixtureObject(compileArguments, 2, false)
    SetFixtureObject(compileArguments, 3, false)
    compilation := compileMethod.Invoke(compiler, compileArguments)
    if compilation == null {
        throw new InvalidOperationException("The production compiler returned no compilation result.")
    }

    compilationType := compilation.GetType()
    successProperty := compilationType.GetProperty("Success")
    errorsProperty := compilationType.GetProperty("Errors")
    if successProperty == null || errorsProperty == null {
        throw new InvalidOperationException("The production compilation result contract was incomplete.")
    }
    successValue := successProperty.GetValue(compilation)
    errorsValue := errorsProperty.GetValue(compilation)
    errors := errorsValue as IList
    if successValue == null || errors == null {
        throw new InvalidOperationException("The production compilation result values were incomplete.")
    }

    diagnostics := ""
    if errors.Count > 0 {
        firstError := errors[0]
        if firstError == null {
            throw new InvalidOperationException("The production compiler returned a null diagnostic.")
        }
        errorType := firstError.GetType()
        formatParameterTypes := new Type[](2)
        formatParameterTypes[0] = typeof(bool)
        formatParameterTypes[1] = typeof(bool)
        formatMethod := errorType.GetMethod("FormatForTooling", formatParameterTypes)
        if formatMethod == null {
            throw new InvalidOperationException("The production diagnostic contract was incomplete.")
        }
        formatArguments := new object?[](2)
        SetFixtureObject(formatArguments, 0, true)
        SetFixtureObject(formatArguments, 1, false)
        formattedValue := formatMethod.Invoke(firstError, formatArguments)
        if formattedValue == null {
            throw new InvalidOperationException("The production diagnostic values were incomplete.")
        }
        diagnostics = formattedValue.ToString() ?? ""
    }

    succeeded := successValue.ToString() == "True"
    Directory.Delete(fixtureRoot, true)
    return new RecordWithFixtureResult(succeeded, diagnostics)
}

// The fixture route compiles emit-only, so the N# planner's OWN member resolution is what rejects an
// unknown member: PlanRecordWith finds no such field and declines, and the with-arm reports it.
test "a with expression naming a member the record does not have is rejected by the planner" {
    result := CompileRecordWithFixture(
        """
record struct Rgb {
    R: int
    G: int
    B: int
}

func main() {
    c := new Rgb { R: 1, G: 2, B: 3 }
    d := c with { Nonexistent: 5 }
    _ := d
}
"""
    )
    assert !result.Succeeded, result.Diagnostics
    assert result.Diagnostics.Contains("emit.with.plan"), result.Diagnostics
}

// A type-mismatched replacement value is rejected by the with-arm's coercion check on the field N# resolved.
test "a with expression whose replacement value is the wrong type is rejected" {
    result := CompileRecordWithFixture(
        """
record struct Rgb {
    R: int
    G: int
    B: int
}

func main() {
    c := new Rgb { R: 1, G: 2, B: 3 }
    d := c with { R: "not an int" }
    _ := d
}
"""
    )
    assert !result.Succeeded, result.Diagnostics
    assert result.Diagnostics.Contains("emit.with.type-mismatch"), result.Diagnostics
}

test "a well-formed value-record with compiles cleanly through the production emitter" {
    result := CompileRecordWithFixture(
        """
record struct Rgb {
    R: int
    G: int
    B: int
}

func main() {
    c := new Rgb { R: 1, G: 2, B: 3 }
    d := c with { G: 20 }
    _ := d
}
"""
    )
    assert result.Succeeded, result.Diagnostics
}
