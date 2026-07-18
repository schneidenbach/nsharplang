namespace NSharpLang.GenericScopeInvalid.Tests

import System
import System.Collections
import System.IO
import System.Reflection

class GenericScopeCompilationResult {
    Succeeded: bool
    Diagnostics: string

    constructor(succeeded: bool, diagnostics: string) {
        Succeeded = succeeded
        Diagnostics = diagnostics
    }
}

func SetGenericScopeObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func CompileGenericScopeFixture(source: string): GenericScopeCompilationResult {
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-generic-scope-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(fixtureRoot)
    File.WriteAllText(Path.Combine(fixtureRoot, "Program.nl"), source)
    compilerType := Type.GetType("NSharpLang.Compiler.MultiFileCompiler, Compiler")
    projectConfigType := Type.GetType(
        "NSharpLang.Compiler.ProjectConfig, NSharpLang.Compiler.BootstrapServices")
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
    SetGenericScopeObject(constructorArguments, 0, fixtureRoot)
    SetGenericScopeObject(constructorArguments, 1, config)
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
    SetGenericScopeObject(compileArguments, 0, "GenericScopeInvalidFixture")
    SetGenericScopeObject(
        compileArguments,
        1,
        Path.Combine(fixtureRoot, "out/GenericScopeInvalidFixture.dll"))
    SetGenericScopeObject(compileArguments, 2, false)
    SetGenericScopeObject(compileArguments, 3, false)
    // This is the public whole-project emit-only route: strict lint and the legacy analyzer stay out
    // of the way so these fixtures exercise the N#-owned synthesized-method scope checks directly.
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
    if successValue == null || errors == null || errors.Count == 0 {
        throw new InvalidOperationException("The production compilation result values were incomplete.")
    }

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
    SetGenericScopeObject(formatArguments, 0, true)
    SetGenericScopeObject(formatArguments, 1, false)
    formattedValue := formatMethod.Invoke(firstError, formatArguments)
    if formattedValue == null {
        throw new InvalidOperationException("The production diagnostic values were incomplete.")
    }

    succeeded := successValue.ToString() == "True"
    diagnostics := formattedValue.ToString() ?? ""
    Directory.Delete(fixtureRoot, true)
    return new GenericScopeCompilationResult(succeeded, diagnostics)
}

func AssertGenericScopeFixtureRejected(source: string) {
    result := CompileGenericScopeFixture(source)
    assert !result.Succeeded, result.Diagnostics
    assert result.Diagnostics.Contains("NL103: Columnar emission is required"), result.Diagnostics
    assert result.Diagnostics.Contains("columnar backend declined"), result.Diagnostics
}

test "parent method generic is rejected in a static lambda signature" {
    // List<T> keeps the enumerable call modeled until its static lambda signature is validated.
    AssertGenericScopeFixtureRejected("""
import System.Collections.Generic
import System.Linq

func Filter<T>(items: List<T>) {
    filtered := items.Where(item => true)
}
""")
}

test "parent method generic is rejected in a static lambda body" {
    AssertGenericScopeFixtureRejected("""
func Outer<T>(value: T): int {
    make: Func<int> = () => {
        values := new T[1]
        return values.Length
    }

    return make()
}
""")
}

test "parent method generic is rejected in a nongeneric local function body" {
    AssertGenericScopeFixtureRejected("""
func Outer<T>(value: T): int {
    func make(): int {
        values := new T[1]
        return values.Length
    }

    return make()
}
""")
}
