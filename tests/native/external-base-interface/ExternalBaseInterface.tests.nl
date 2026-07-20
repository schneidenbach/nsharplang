namespace NSharpLang.ExternalBaseInterface.Tests

import System
import System.Collections
import System.IO
import System.Reflection
import NSharpLang.Compiler

// End-to-end product-route coverage for external base/interface resolution. Each fixture is written
// to a temporary project that references the core framework exactly as `nlc build` does, then driven
// through the real production MultiFileCompiler analysis-plus-emit route. A valid external
// base/interface is admitted only if ColumnarBaseTypePlanner classified it and wired the exact
// TypeBuilder metadata; an inadmissible base declines. The emitted base-type IL is additionally
// ILVerified by the gate over tests/fixtures/external-base-interface.
class ExternalBaseCompilation {
    Succeeded: bool
    Diagnostics: string
    FixtureRoot: string

    constructor(succeeded: bool, diagnostics: string, fixtureRoot: string) {
        Succeeded = succeeded
        Diagnostics = diagnostics
        FixtureRoot = fixtureRoot
    }
}

func SetExternalBaseObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func CoreFrameworkDirectory(): string {
    coreAssembly := typeof(object).get_Assembly()
    coreLocation := coreAssembly.get_Location()
    return Path.GetDirectoryName(coreLocation) ?? ""
}

func CompileExternalBaseFixtureFiles(names: string[], contents: string[]): ExternalBaseCompilation {
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-external-base-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(fixtureRoot)
    fileIndex := 0
    while fileIndex < names.Length {
        filePath := Path.Combine(fixtureRoot, names[fileIndex])
        File.WriteAllText(filePath, contents[fileIndex])
        fileIndex = fileIndex + 1
    }

    // Reference the core framework the same way the CLI's implicit Microsoft.NETCore.App resolution
    // does, so external types (Exception, Attribute, IDisposable, ...) resolve to live runtime
    // handles for both analysis and emission.
    coreDirectory := CoreFrameworkDirectory()
    coreLib := Path.Combine(coreDirectory, "System.Private.CoreLib.dll")
    runtimeDll := Path.Combine(coreDirectory, "System.Runtime.dll")
    projectYml := "name: ExternalBaseFixture\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - dll: "
        + coreLib + "\n  - dll: " + runtimeDll + "\n"
    File.WriteAllText(Path.Combine(fixtureRoot, "project.yml"), projectYml)

    compilerType := Type.GetType("NSharpLang.Compiler.MultiFileCompiler, Compiler")
    projectFileParserType := Type.GetType(
        "NSharpLang.Compiler.ProjectFileParser, NSharpLang.Compiler.BootstrapServices")
    if compilerType == null || projectFileParserType == null {
        throw new InvalidOperationException("The production compiler types were not loadable.")
    }
    parseParameterTypes := new Type[](1)
    parseParameterTypes[0] = typeof(string)
    parseMethod := projectFileParserType.GetMethod("Parse", parseParameterTypes)
    if parseMethod == null {
        throw new InvalidOperationException("The production project parser was not found.")
    }
    parseArguments := new object?[](1)
    SetExternalBaseObject(parseArguments, 0, Path.Combine(fixtureRoot, "project.yml"))
    config := parseMethod.Invoke(null, parseArguments)
    if config == null {
        throw new InvalidOperationException("The production project configuration was not parsed.")
    }
    projectConfigType := config.GetType()

    constructorTypes := new Type[](2)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = projectConfigType
    constructor := compilerType.GetConstructor(constructorTypes)
    if constructor == null {
        throw new InvalidOperationException("The production compiler constructor was not found.")
    }
    constructorArguments := new object?[](2)
    SetExternalBaseObject(constructorArguments, 0, fixtureRoot)
    SetExternalBaseObject(constructorArguments, 1, config)
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

    outputPath := Path.Combine(fixtureRoot, "out/ExternalBaseFixture.dll")
    compileArguments := new object?[](4)
    SetExternalBaseObject(compileArguments, 0, "ExternalBaseFixture")
    SetExternalBaseObject(compileArguments, 1, outputPath)
    // Drive the production build path (analysis + emit), exactly as `nlc build`.
    SetExternalBaseObject(compileArguments, 2, false)
    SetExternalBaseObject(compileArguments, 3, true)
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
    if successValue == null {
        throw new InvalidOperationException("The production compilation result values were incomplete.")
    }

    succeeded := successValue.ToString() == "True"
    diagnostics := FormatFirstDiagnostic(errorsValue as IList)
    return new ExternalBaseCompilation(succeeded, diagnostics, fixtureRoot)
}

func CompileExternalBaseFixture(source: string): ExternalBaseCompilation {
    names := new string[](1)
    names[0] = "Program.nl"
    contents := new string[](1)
    contents[0] = source
    return CompileExternalBaseFixtureFiles(names, contents)
}

func FormatFirstDiagnostic(errors: IList?): string {
    if errors == null || errors.Count == 0 {
        return ""
    }
    firstError := errors[0]
    if firstError == null {
        return ""
    }
    errorType := firstError.GetType()
    formatParameterTypes := new Type[](2)
    formatParameterTypes[0] = typeof(bool)
    formatParameterTypes[1] = typeof(bool)
    formatMethod := errorType.GetMethod("FormatForTooling", formatParameterTypes)
    if formatMethod == null {
        return ""
    }
    formatArguments := new object?[](2)
    SetExternalBaseObject(formatArguments, 0, true)
    SetExternalBaseObject(formatArguments, 1, false)
    formattedValue := formatMethod.Invoke(firstError, formatArguments)
    if formattedValue == null {
        return ""
    }
    return formattedValue.ToString() ?? ""
}

func Cleanup(compilation: ExternalBaseCompilation) {
    if Directory.Exists(compilation.FixtureRoot) {
        Directory.Delete(compilation.FixtureRoot, true)
    }
}

test "source class extends an external runtime base class with a public parameterless constructor" {
    compilation := CompileExternalBaseFixture("""
import System

class DataStore: Exception {
    func Tag(): int {
        return 7
    }
}
""")
    assert compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

test "source class extends an external abstract base with a protected parameterless constructor" {
    // System.Attribute mirrors ControllerBase: a non-sealed public base whose only parameterless
    // constructor is protected. The synthesized default constructor must chain to that family ctor,
    // which is exactly the generated Web API controller's ControllerBase shape.
    compilation := CompileExternalBaseFixture("""
import System

class WeatherTag: Attribute {
    func Count(): int {
        return 3
    }
}
""")
    assert compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

test "source class implements an external runtime interface" {
    compilation := CompileExternalBaseFixture("""
import System

class Resource: IDisposable {
    func Dispose() {
    }
}
""")
    assert compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

test "source class extends an external base and implements an external interface together" {
    compilation := CompileExternalBaseFixture("""
import System

class TrackedResource: Attribute, IDisposable {
    func Dispose() {
    }
}
""")
    assert compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

test "source class extends a source base and implements an external interface" {
    compilation := CompileExternalBaseFixture("""
import System

class Widget {
    Size: int
}

class Gauge: Widget, IDisposable {
    func Dispose() {
    }
}
""")
    assert compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

test "an unresolved base name declines with the base-type diagnostic" {
    compilation := CompileExternalBaseFixture("""
class Broken: NonexistentBaseType {
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    assert compilation.Diagnostics.Contains("could not be resolved"), compilation.Diagnostics
    Cleanup(compilation)
}

test "a sealed external base class is not inheritable and declines" {
    compilation := CompileExternalBaseFixture("""
class Bad: string {
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    assert compilation.Diagnostics.Contains("could not be resolved"), compilation.Diagnostics
    Cleanup(compilation)
}

test "an external value type base is not inheritable and declines" {
    compilation := CompileExternalBaseFixture("""
class Bad: int {
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    assert compilation.Diagnostics.Contains("could not be resolved"), compilation.Diagnostics
    Cleanup(compilation)
}

test "a second class base is rejected" {
    compilation := CompileExternalBaseFixture("""
import System

class Bad: Exception, FormatException {
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

test "a value-type struct cannot inherit an external base" {
    compilation := CompileExternalBaseFixture("""
import System

struct Bad: Attribute {
    Value: int
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

test "an ambiguous cross-namespace base name declines rather than guessing" {
    names := new string[](3)
    names[0] = "First.nl"
    names[1] = "Second.nl"
    names[2] = "Program.nl"
    contents := new string[](3)
    contents[0] = "namespace First\n\npublic class Widget {\n}\n"
    contents[1] = "namespace Second\n\npublic class Widget {\n}\n"
    contents[2] = "namespace Caller\n\nclass Consumer: Widget {\n}\n"
    compilation := CompileExternalBaseFixtureFiles(names, contents)
    assert !compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

// -----------------------------------------------------------------------------------------------
// Inherited external-base-method calls (`Ok(data)` -> ControllerBase.Ok inside a source subclass).
//
// The native test project itself compiles through the columnar pipeline, so the source classes
// below and the bare/explicit-this inherited calls in their bodies ARE the executed emission
// proof: if the inherited-external arm mis-selects an overload, emits the wrong receiver, or picks
// the wrong dispatch instruction, this project fails to build and the executed asserts never run.
// `System.Exception` and `System.Random` are stable CoreLib bases mirroring the generated Web API's
// `WeatherController: ControllerBase` shape (`Ok(data)` -> ControllerBase.Ok(object)).
//
// Decline cases (arity mismatch, generic method) stay on the MultiFileCompiler harness because they
// must fail compilation and so cannot live in this project's own source.
// -----------------------------------------------------------------------------------------------

class TracedException: System.Exception {
    // Bare inherited call: `GetBaseException()` with no receiver binds System.Exception.GetBaseException()
    // through the recorded external base, exactly as `Ok(data)` binds ControllerBase.Ok(object). With
    // no inner exception the method returns the receiver itself.
    func Root(): System.Exception {
        return GetBaseException()
    }

    // Explicit-this form: the parser flattens `this.GetBaseException()` to the same leaf-identifier
    // callee as the bare form, so it must resolve the inherited external method identically.
    func RootThis(): System.Exception {
        return this.GetBaseException()
    }
}

class OverloadRoller: System.Random {
    // Overload selection by arity: System.Random declares Next(), Next(int) and Next(int, int).
    // Next(1) must select Next(int); its result is in [0, 1), i.e. deterministically 0, proving both
    // that the arity-1 overload was chosen and that the emitted call executes.
    func RollZero(): int {
        return Next(1)
    }

    // Next(minValue, maxValue) with minValue == maxValue deterministically returns minValue, proving
    // the arity-2 inherited overload is selected distinctly from the arity-1 one.
    func RollFixed(): int {
        return Next(5, 5)
    }
}

class HidingRoller: System.Random {
    // Source-declaration precedence: a source `Next()` hides the inherited external `Next()` (whose
    // result is never negative). The bare call in Play() must bind this source override, not the
    // external base method — this is the Web API-relevant "source hides external" rule.
    func Next(): int {
        return -777
    }

    func Play(): int {
        return Next()
    }
}

// Explicit-receiver (a local of a source type that extends an external base, NOT `this`) call to a
// method inherited from that external base, mirroring `controller.Ok(data)`. This exercises the
// explicit-member inherited arm, which loads the source receiver and dispatches the inherited method.
func BaseExceptionOf(traced: TracedException): System.Exception {
    return traced.GetBaseException()
}

test "a bare inherited external-base call executes and returns the receiver" {
    traced := new TracedException()
    assert Object.ReferenceEquals(traced, traced.Root()), "The bare inherited GetBaseException() call must return the receiver instance."
}

test "an explicit-this inherited external-base call executes and returns the receiver" {
    traced := new TracedException()
    assert Object.ReferenceEquals(traced, traced.RootThis()), "The explicit-this inherited GetBaseException() call must return the receiver instance."
}

test "an explicit-receiver inherited external-base call executes and returns the receiver" {
    traced := new TracedException()
    assert Object.ReferenceEquals(traced, BaseExceptionOf(traced)), "The explicit-receiver inherited GetBaseException() call must return the receiver instance."
}

test "an inherited external-base overload is selected by argument arity and executes" {
    roller := new OverloadRoller()
    assert roller.RollZero() == 0, "Next(1) must select the inherited Random.Next(int) overload and yield 0."
    assert roller.RollFixed() == 5, "Next(5, 5) must select the inherited Random.Next(int, int) overload and yield 5."
}

test "a source method declaration hides the inherited external overload at runtime" {
    roller := new HidingRoller()
    assert roller.Play() == -777, "The source Next() override must run instead of the inherited external Random.Next()."
}

test "a bare inherited external-base call with a mismatched arity declines" {
    // System.Random has no three-argument Next overload; the call must not bind a different arity.
    compilation := CompileExternalBaseFixture("""
class Dice: System.Random {
    func Bad(): int {
        return Next(1, 2, 3)
    }
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}

test "a generic method inherited from the external base is not bound and declines" {
    // System.Random.Shuffle<T>(T[]) is a generic instance method; the fixed-arity fence excludes it,
    // so the bare inherited call must decline rather than silently binding a generic method.
    compilation := CompileExternalBaseFixture("""
class Dice: System.Random {
    func Mix(items: int[]) {
        Shuffle(items)
    }
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    Cleanup(compilation)
}
