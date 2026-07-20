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
