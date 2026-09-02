namespace NSharpLang.LambdaPlacement.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection

// --- Functional placement + persisted execution -----------------------------------------------------
test "no-capture lambda runs as a program-static method ldftn'd cross-type from an instance method" {
    accumulator := new Accumulator(0)
    input := new List<int>()
    input.Add(3)
    input.Add(4)
    doubled := accumulator.DoubleAll(input)
    assert doubled[0] == 6
    assert doubled[1] == 8
}

test "the same program-static placement serves lambdas written in more than one owning type" {
    scaler := new Scaler()
    input := new List<int>()
    input.Add(2)
    input.Add(5)
    tripled := scaler.TripleAll(input)
    assert tripled[0] == 6
    assert tripled[1] == 15
}

test "this-capture lambda runs bound to the current instance" {
    accumulator := new Accumulator(10)
    input := new List<int>()
    input.Add(1)
    input.Add(2)
    offset := accumulator.OffsetAll(input)
    assert offset[0] == 11
    assert offset[1] == 12
}

test "two lambdas in one body get distinct placements and both run" {
    accumulator := new Accumulator(0)
    input := new List<int>()
    input.Add(5)
    input.Add(9)
    bounds := accumulator.Bounds(input)
    assert bounds.Item1 == 4
    assert bounds.Item2 == 10
}

test "captured-parameter lambda (fenced display residual) still runs correctly" {
    filter := new Filter()
    input := new List<int>()
    input.Add(1)
    input.Add(5)
    input.Add(9)
    kept := filter.AtLeast(5, input)
    assert kept.Count == 2
    assert kept[0] == 5
    assert kept[1] == 9
}

// --- Exact IL accessibility (reflection on the delegate's selected target method) --------------------

test "a no-capture lambda is placed as an assembly-static method" {
    // The delegate's target is the exact method N# selected. Cross-type ldftn requires assembly (internal)
    // visibility — a private static method here would throw MethodAccessException at JIT — and no receiver.
    doubler: Func<int, int> = v => v * 2
    method := doubler.get_Method()
    assert method.get_IsStatic()
    assert method.get_IsAssembly()
    assert !method.get_IsPrivate()
    assert doubler(21) == 42
}

test "a this-capture lambda is placed as a private instance method on the enclosing type" {
    // Placement facts reflected from inside the enclosing instance method:
    // "IsPrivate|IsStatic|DeclaringType|Invoke(5)". A this-capture lambda is a private instance method on
    // the enclosing type (same-type ldftn, so private visibility is sufficient), bound to the receiver.
    accumulator := new Accumulator(100)
    facts := accumulator.InspectThisCapturePlacement()
    assert facts == "True|False|Accumulator|105", facts
}

// --- Invalid placement facts decline ----------------------------------------------------------------

class LambdaFixtureResult {
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
// route (strict lint and the legacy analyzer stay out of the way), and report whether it succeeded.
func CompileLambdaFixture(source: string): LambdaFixtureResult {
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-lambda-placement-" + Guid.NewGuid().ToString("N")
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
    SetFixtureObject(compileArguments, 0, "LambdaPlacementFixture")
    SetFixtureObject(
        compileArguments,
        1,
        Path.Combine(fixtureRoot, "out/LambdaPlacementFixture.dll")
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
    return new LambdaFixtureResult(succeeded, diagnostics)
}

test "a value-type this-capture lambda declines: a value receiver cannot bind a delegate directly" {
    // The lambda calls the bare struct instance method `Bump`, so it needs `this`; a value-type `this`
    // would bind a copy with different mutation semantics, so N# declines the placement and the emit fails.
    result := CompileLambdaFixture(
        """
import System.Collections.Generic
import System.Linq

struct Shifter {
    origin: int

    func Bump(x: int): int {
        return x + origin
    }

    func Shift(values: List<int>): List<int> {
        return values.Select(v => Bump(v)).ToList()
    }
}

func main() {
    shifter := new Shifter { origin: 1 }
    _ := shifter.Shift(new List<int>())
}
"""
    )
    assert !result.Succeeded, result.Diagnostics
    assert result.Diagnostics.Contains("NL103: Columnar emission is required"), result.Diagnostics
    assert result.Diagnostics.Contains("columnar backend declined"), result.Diagnostics
}

test "a non-capturing lambda over a well-formed signature is accepted" {
    result := CompileLambdaFixture(
        """
import System.Collections.Generic
import System.Linq

func main() {
    values := new List<int>()
    values.Add(2)
    doubled := values.Select(v => v * 2).ToList()
}
"""
    )
    assert result.Succeeded, result.Diagnostics
}
