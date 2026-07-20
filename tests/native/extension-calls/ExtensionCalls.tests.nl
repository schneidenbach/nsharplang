namespace NSharpLang.ExtensionCalls.Tests

import System
import System.Collections
import System.IO
import System.Linq
import System.Reflection
import NSharpLang.Compiler

// End-to-end coverage for external extension-method calls. The executed proofs below are compiled
// through the real columnar pipeline (this very project builds with nlc): each `receiver.Method()`
// binds a non-generic BCL extension method, so if the extension resolver mis-selected an overload,
// emitted the wrong receiver, or produced unverifiable IL, this project would fail to build and the
// asserts would never run. Decline cases (no candidate, generic-only candidate) must fail
// compilation and therefore run through the production MultiFileCompiler harness on a fixture that
// references System.Linq exactly as `nlc build` does.

class ExtensionCallCompilation {
    Succeeded: bool
    Diagnostics: string
    FixtureRoot: string

    constructor(succeeded: bool, diagnostics: string, fixtureRoot: string) {
        Succeeded = succeeded
        Diagnostics = diagnostics
        FixtureRoot = fixtureRoot
    }
}

func SetExtensionObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func ExtensionCoreFrameworkDirectory(): string {
    coreAssembly := typeof(object).get_Assembly()
    coreLocation := coreAssembly.get_Location()
    return Path.GetDirectoryName(coreLocation) ?? ""
}

func CompileExtensionCallFixture(source: string): ExtensionCallCompilation {
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-extension-calls-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(fixtureRoot)
    File.WriteAllText(Path.Combine(fixtureRoot, "Program.nl"), source)

    // Reference the core framework and System.Linq the way `nlc build` resolves the implicit
    // Microsoft.NETCore.App framework, so both live extension hosts (Enumerable) and every core type
    // resolve to runtime handles for analysis and emission.
    coreDirectory := ExtensionCoreFrameworkDirectory()
    coreLib := Path.Combine(coreDirectory, "System.Private.CoreLib.dll")
    runtimeDll := Path.Combine(coreDirectory, "System.Runtime.dll")
    linqDll := Path.Combine(coreDirectory, "System.Linq.dll")
    projectYml := "name: ExtensionCallFixture\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - dll: "
        + coreLib + "\n  - dll: " + runtimeDll + "\n  - dll: " + linqDll + "\n"
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
    SetExtensionObject(parseArguments, 0, Path.Combine(fixtureRoot, "project.yml"))
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
    SetExtensionObject(constructorArguments, 0, fixtureRoot)
    SetExtensionObject(constructorArguments, 1, config)
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

    outputPath := Path.Combine(fixtureRoot, "out/ExtensionCallFixture.dll")
    compileArguments := new object?[](4)
    SetExtensionObject(compileArguments, 0, "ExtensionCallFixture")
    SetExtensionObject(compileArguments, 1, outputPath)
    SetExtensionObject(compileArguments, 2, false)
    SetExtensionObject(compileArguments, 3, true)
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
    diagnostics := FormatFirstExtensionDiagnostic(errorsValue as IList)
    return new ExtensionCallCompilation(succeeded, diagnostics, fixtureRoot)
}

func FormatFirstExtensionDiagnostic(errors: IList?): string {
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
    SetExtensionObject(formatArguments, 0, true)
    SetExtensionObject(formatArguments, 1, false)
    formattedValue := formatMethod.Invoke(firstError, formatArguments)
    if formattedValue == null {
        return ""
    }
    return formattedValue.ToString() ?? ""
}

func CleanupExtensionCompilation(compilation: ExtensionCallCompilation) {
    if Directory.Exists(compilation.FixtureRoot) {
        Directory.Delete(compilation.FixtureRoot, true)
    }
}

// -----------------------------------------------------------------------------------------------
// Executed proofs (compiled through the columnar pipeline as this project builds).
// -----------------------------------------------------------------------------------------------

// A single extension call on an interface-typed receiver: `int[]` implements `IEnumerable<int>`, so
// `values.Sum()` binds the non-generic Enumerable.Sum(IEnumerable<int>) extension and executes.
func SumOfNumbers(values: int[]): int {
    return values.Sum()
}

func MaxOfNumbers(values: int[]): int {
    return values.Max()
}

func MinOfNumbers(values: int[]): int {
    return values.Min()
}

func MakeNumbers(): int[] {
    return [4, 8, 15]
}

// A chained receiver: the extension receiver is itself a call result, not a bound local. This
// proves the receiver-value emission handles a composed expression.
func ChainedSum(): int {
    return MakeNumbers().Sum()
}

test "an extension call on an interface-typed array receiver executes" {
    values := [10, 20, 30]
    assert SumOfNumbers(values) == 60, "int[].Sum() must bind Enumerable.Sum and total the array."
    assert MaxOfNumbers(values) == 30, "int[].Max() must bind Enumerable.Max and return the maximum."
    assert MinOfNumbers(values) == 10, "int[].Min() must bind Enumerable.Min and return the minimum."
}

test "a chained extension call on a call-result receiver executes" {
    assert ChainedSum() == 27, "MakeNumbers().Sum() must bind Sum on the call-result receiver."
}

// -----------------------------------------------------------------------------------------------
// Decline cases (must fail compilation, so they run through the MultiFileCompiler harness).
// -----------------------------------------------------------------------------------------------

test "a member call with no matching instance or extension method declines" {
    compilation := CompileExtensionCallFixture("""
import System.Linq

class Consumer {
    func Run(): int {
        numbers := [1, 2, 3]
        return numbers.NonexistentExtensionXyz()
    }
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    CleanupExtensionCompilation(compilation)
}

test "a generic-only extension candidate is not bound and declines" {
    // Enumerable.Distinct<T>(IEnumerable<T>) is generic; the index build excludes generic methods,
    // so the bare `Distinct()` call must decline rather than binding a generic extension.
    compilation := CompileExtensionCallFixture("""
import System.Linq

class Consumer {
    func Run(): int[] {
        numbers := [1, 2, 2, 3]
        return numbers.Distinct()
    }
}
""")
    assert !compilation.Succeeded, compilation.Diagnostics
    CleanupExtensionCompilation(compilation)
}
