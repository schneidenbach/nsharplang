namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection

class EmitterCanonicalCompilation {
    Succeeded: bool
    Errors: IList
    FixtureRoot: string
    OutputPath: string
    OutputAssemblyPath: object?
    Config: object

    constructor(
        succeeded: bool,
        errors: IList,
        fixtureRoot: string,
        outputPath: string,
        outputAssemblyPath: object?,
        config: object
    ) {
        Succeeded = succeeded
        Errors = errors
        FixtureRoot = fixtureRoot
        OutputPath = outputPath
        OutputAssemblyPath = outputAssemblyPath
        Config = config
    }
}

class EmitterCanonicalRunResult {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

class EmitterCanonicalCapturedCompilation {
    Compilation: EmitterCanonicalCompilation
    Stderr: string

    constructor(compilation: EmitterCanonicalCompilation, stderr: string) {
        Compilation = compilation
        Stderr = stderr
    }
}

func EmitterCanonicalPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func EmitterCanonicalProjectYml(projectName: string, outputType: string): string {
    return "name: " + projectName + "\nbackend: il\noutputType: " + outputType + "\ntargetFramework: net10.0"
}

func EmitterCanonicalSingleFileNames(): string[] {
    names := new string[](1)
    names[0] = "Program.nl"
    return names
}

func EmitterCanonicalSingleFileContents(source: string): string[] {
    contents := new string[](1)
    contents[0] = source
    return contents
}

// N# multiline literals retain the newlines beside both delimiters. C# raw literals used by the
// migrated fixtures retain neither. A leading newline identifies the multiline representation, so
// remove exactly that pair while leaving intentional trailing newlines in ordinary strings intact.
func EmitterCanonicalDecodedSource(source: string): string {
    if source.StartsWith("\n", StringComparison.Ordinal) {
        decoded := source.Substring(1)
        if decoded.EndsWith("\n", StringComparison.Ordinal) {
            return decoded.Substring(0, decoded.Length - 1)
        }
        return decoded
    }
    return source
}

func EmitterCanonicalCompilerType(): Type {
    owner := Type.GetType("NSharpLang.Compiler.MultiFileCompiler, Compiler")
    if owner == null {
        throw new InvalidOperationException("The production MultiFileCompiler was not loadable")
    }
    return owner
}

func EmitterCanonicalParseProject(projectFile: string): object {
    owner := Type.GetType(
        "NSharpLang.Compiler.ProjectFileParser, NSharpLang.Compiler.BootstrapServices"
    )
    if owner == null {
        throw new InvalidOperationException("The N# project parser was not loadable")
    }
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    method := owner.GetMethod("Parse", parameterTypes)
    if method == null {
        throw new InvalidOperationException("The N# project parser entry point was not found")
    }
    arguments := new object?[](1)
    EmitterCanonicalPut(arguments, 0, projectFile)
    parsed := method.Invoke(null, arguments)
    if parsed == null {
        throw new InvalidOperationException("The N# project parser returned no ProjectConfig")
    }
    return parsed
}

func EmitterCanonicalNewCompiler(
    fixtureRoot: string,
    config: object,
    sourceFiles: string[],
    useExplicitSourceFiles: bool
): object {
    owner := EmitterCanonicalCompilerType()
    if useExplicitSourceFiles {
        parameterTypes := new Type[](3)
        parameterTypes[0] = typeof(IEnumerable<string>)
        parameterTypes[1] = typeof(string)
        parameterTypes[2] = config.GetType()
        constructor := owner.GetConstructor(parameterTypes)
        if constructor == null {
            throw new InvalidOperationException("The explicit-source MultiFileCompiler constructor was not found")
        }
        arguments := new object?[](3)
        EmitterCanonicalPut(arguments, 0, sourceFiles)
        EmitterCanonicalPut(arguments, 1, fixtureRoot)
        EmitterCanonicalPut(arguments, 2, config)
        compiler := constructor.Invoke(arguments)
        if compiler == null {
            throw new InvalidOperationException("The explicit-source MultiFileCompiler constructor returned null")
        }
        return compiler
    }

    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = config.GetType()
    constructor := owner.GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("The project-root MultiFileCompiler constructor was not found")
    }
    arguments := new object?[](2)
    EmitterCanonicalPut(arguments, 0, fixtureRoot)
    EmitterCanonicalPut(arguments, 1, config)
    compiler := constructor.Invoke(arguments)
    if compiler == null {
        throw new InvalidOperationException("The project-root MultiFileCompiler constructor returned null")
    }
    return compiler
}

func EmitterCanonicalCompile(
    projectName: string,
    projectYml: string,
    fileNames: string[],
    contents: string[],
    useExplicitSourceFiles: bool
): EmitterCanonicalCompilation {
    if fileNames.Length != contents.Length {
        throw new ArgumentException("Canonical fixture file names and contents must have equal lengths")
    }
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-columnar-emitter-canonical-" + Guid.NewGuid().ToString("N")
    )
    Directory.CreateDirectory(fixtureRoot)
    try {
        File.WriteAllText(Path.Combine(fixtureRoot, "project.yml"), projectYml)
        sourceFiles := new string[](fileNames.Length)
        index := 0
        while index < fileNames.Length {
            sourcePath := Path.Combine(fixtureRoot, fileNames[index])
            File.WriteAllText(sourcePath, EmitterCanonicalDecodedSource(contents[index]))
            sourceFiles[index] = sourcePath
            index = index + 1
        }

        config := EmitterCanonicalParseProject(Path.Combine(fixtureRoot, "project.yml"))
        compiler := EmitterCanonicalNewCompiler(
            fixtureRoot,
            config,
            sourceFiles,
            useExplicitSourceFiles
        )
        outputDirectory := Path.Combine(fixtureRoot, "artifacts")
        Directory.CreateDirectory(outputDirectory)
        outputPath := Path.Combine(outputDirectory, projectName + ".dll")

        parameterTypes := new Type[](4)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(string)
        parameterTypes[2] = typeof(bool)
        parameterTypes[3] = typeof(bool)
        compileMethod := EmitterCanonicalCompilerType().GetMethod(
            "CompileToIlAssembly",
            parameterTypes
        )
        if compileMethod == null {
            throw new InvalidOperationException("The public MultiFileCompiler entry point was not found")
        }
        arguments := new object?[](4)
        EmitterCanonicalPut(arguments, 0, projectName)
        EmitterCanonicalPut(arguments, 1, outputPath)
        EmitterCanonicalPut(arguments, 2, false)
        EmitterCanonicalPut(arguments, 3, true)
        result := compileMethod.Invoke(compiler, arguments)
        if result == null {
            throw new InvalidOperationException("MultiFileCompiler returned no compilation result")
        }

        successValue := EmitterCanonicalRequiredProperty(result, "Success")
        errorsValue := EmitterCanonicalRequiredProperty(result, "Errors") as IList
        if errorsValue == null {
            throw new InvalidOperationException("Compilation errors did not implement IList")
        }
        outputAssemblyPath := EmitterCanonicalOptionalProperty(result, "OutputAssemblyPath")
        return new EmitterCanonicalCompilation(
            Convert.ToBoolean(successValue),
            errorsValue,
            fixtureRoot,
            outputPath,
            outputAssemblyPath,
            config
        )
    } catch error: Exception {
        if Directory.Exists(fixtureRoot) {
            Directory.Delete(fixtureRoot, true)
        }
        throw error
    }
}

func EmitterCanonicalCompileSingle(
    projectName: string,
    outputType: string,
    source: string
): EmitterCanonicalCompilation {
    return EmitterCanonicalCompile(
        projectName,
        EmitterCanonicalProjectYml(projectName, outputType),
        EmitterCanonicalSingleFileNames(),
        EmitterCanonicalSingleFileContents(source),
        false
    )
}

func EmitterCanonicalRequiredProperty(target: object, name: string): object {
    field := target.GetType().GetField(name)
    if field != null {
        fieldValue := field.GetValue(target)
        if fieldValue == null {
            throw new InvalidOperationException("Canonical member '" + name + "' was null")
        }
        return fieldValue
    }
    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing canonical member '" + name + "'")
    }
    value := property.GetValue(target)
    if value == null {
        throw new InvalidOperationException("Canonical member '" + name + "' was null")
    }
    return value
}

func EmitterCanonicalOptionalProperty(target: object, name: string): object? {
    field := target.GetType().GetField(name)
    if field != null {
        return field.GetValue(target)
    }
    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing canonical member '" + name + "'")
    }
    return property.GetValue(target)
}

func EmitterCanonicalErrorText(error: object, name: string): string {
    value := EmitterCanonicalOptionalProperty(error, name)
    if value == null {
        return ""
    }
    return Convert.ToString(value) ?? ""
}

func EmitterCanonicalErrorInt(error: object, name: string): int {
    return Convert.ToInt32(EmitterCanonicalRequiredProperty(error, name))
}

func EmitterCanonicalDiagnostics(compilation: EmitterCanonicalCompilation): string {
    text := ""
    index := 0
    while index < compilation.Errors.Count {
        error := compilation.Errors[index]
        if error != null {
            if text.Length > 0 {
                text = text + Environment.NewLine
            }
            text = text + EmitterCanonicalErrorText(error, "Message")
        }
        index = index + 1
    }
    return text
}

func EmitterCanonicalFindSingleError(
    compilation: EmitterCanonicalCompilation,
    propertyName: string,
    expectedValue: string
): object {
    found: object? = null
    count := 0
    index := 0
    while index < compilation.Errors.Count {
        error := compilation.Errors[index]
        if error != null && EmitterCanonicalErrorText(error, propertyName) == expectedValue {
            found = error
            count = count + 1
        }
        index = index + 1
    }
    if found == null || count != 1 {
        throw new InvalidOperationException(
            "Expected one error with " + propertyName + "='" + expectedValue + "', found " + count.ToString()
        )
    }
    return found
}

func EmitterCanonicalHasErrorText(
    compilation: EmitterCanonicalCompilation,
    propertyName: string,
    fragment: string
): bool {
    index := 0
    while index < compilation.Errors.Count {
        error := compilation.Errors[index]
        if error != null && EmitterCanonicalErrorText(error, propertyName).Contains(fragment, StringComparison.Ordinal) {
            return true
        }
        index = index + 1
    }
    return false
}

func EmitterCanonicalHasErrorValue(
    compilation: EmitterCanonicalCompilation,
    propertyName: string,
    expectedValue: string
): bool {
    index := 0
    while index < compilation.Errors.Count {
        error := compilation.Errors[index]
        if error != null && EmitterCanonicalErrorText(error, propertyName) == expectedValue {
            return true
        }
        index = index + 1
    }
    return false
}

func EmitterCanonicalHasError(
    compilation: EmitterCanonicalCompilation,
    code: string,
    expectedType: string,
    actualType: string
): bool {
    index := 0
    while index < compilation.Errors.Count {
        error := compilation.Errors[index]
        if error != null
            && EmitterCanonicalErrorText(error, "Code") == code
            && EmitterCanonicalErrorText(error, "ExpectedType") == expectedType
            && EmitterCanonicalErrorText(error, "ActualType") == actualType {
            return true
        }
        index = index + 1
    }
    return false
}

func EmitterCanonicalCleanup(compilation: EmitterCanonicalCompilation) {
    if Directory.Exists(compilation.FixtureRoot) {
        Directory.Delete(compilation.FixtureRoot, true)
    }
}

func EmitterCanonicalRun(compilation: EmitterCanonicalCompilation): EmitterCanonicalRunResult {
    artifactsType := Type.GetType(
        "NSharpLang.Compiler.CompilationArtifacts, NSharpLang.Compiler.BootstrapServices"
    )
    if artifactsType == null {
        throw new InvalidOperationException("The N# compilation-artifact writer was not loadable")
    }
    artifactParameterTypes := new Type[](2)
    artifactParameterTypes[0] = compilation.Config.GetType()
    artifactParameterTypes[1] = typeof(string)
    writeRuntimeConfig := artifactsType.GetMethod("WriteRuntimeConfig", artifactParameterTypes)
    if writeRuntimeConfig == null {
        throw new InvalidOperationException("The N# runtime-config writer was not found")
    }
    artifactArguments := new object?[](2)
    EmitterCanonicalPut(artifactArguments, 0, compilation.Config)
    EmitterCanonicalPut(artifactArguments, 1, compilation.OutputPath)
    ignoredArtifactResult := writeRuntimeConfig.Invoke(null, artifactArguments)
    _ = ignoredArtifactResult
    runnerType := Type.GetType(
        "NSharpLang.Cli.DotnetRunner, NSharpLang.Compiler.BootstrapServices"
    )
    if runnerType == null {
        throw new InvalidOperationException("The N# dotnet runner was not loadable")
    }
    candidates := runnerType.GetMethods(BindingFlags.Static | BindingFlags.Public)
    runMethod: MethodInfo? = null
    count := 0
    for candidate in candidates {
        if candidate.get_Name() == "Run" && candidate.GetParameters().Length == 4 {
            runMethod = candidate
            count = count + 1
        }
    }
    if runMethod == null || count != 1 {
        throw new InvalidOperationException("The N# dotnet runner entry point was not found exactly once")
    }
    arguments := new object?[](4)
    EmitterCanonicalPut(arguments, 0, "\"" + compilation.OutputPath + "\"")
    EmitterCanonicalPut(arguments, 1, compilation.FixtureRoot)
    EmitterCanonicalPut(arguments, 2, true)
    EmitterCanonicalPut(arguments, 3, null)
    result := runMethod.Invoke(null, arguments)
    if result == null {
        throw new InvalidOperationException("The N# dotnet runner returned no result")
    }
    return new EmitterCanonicalRunResult(
        Convert.ToInt32(EmitterCanonicalRequiredProperty(result, "ExitCode")),
        Convert.ToString(EmitterCanonicalRequiredProperty(result, "Stdout")) ?? "",
        Convert.ToString(EmitterCanonicalRequiredProperty(result, "Stderr")) ?? ""
    )
}

func EmitterCanonicalNormalizedOutput(value: string): string {
    return value.Replace("\r\n", "\n").Trim()
}

func EmitterCanonicalAssertProgramNormalized(
    projectName: string,
    source: string,
    expectedOutput: string
) {
    compilation := EmitterCanonicalCompileSingle(projectName, "exe", source)
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert EmitterCanonicalNormalizedOutput(run.Stdout) == expectedOutput,
            EmitterCanonicalNormalizedOutput(run.Stdout)
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

func EmitterCanonicalAssertProgramTrimmed(
    projectName: string,
    source: string,
    expectedOutput: string
) {
    compilation := EmitterCanonicalCompileSingle(projectName, "exe", source)
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert run.Stdout.Trim() == expectedOutput, run.Stdout.Trim()
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

func EmitterCanonicalAssertProgramContains(
    projectName: string,
    source: string,
    expectedFragment: string
) {
    compilation := EmitterCanonicalCompileSingle(projectName, "exe", source)
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert run.Stdout.Contains(expectedFragment, StringComparison.Ordinal), run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

func EmitterCanonicalAssertProgramFiles(
    projectName: string,
    fileNames: string[],
    contents: string[],
    expectedOutput: string
) {
    compilation := EmitterCanonicalCompile(
        projectName,
        EmitterCanonicalProjectYml(projectName, "exe"),
        fileNames,
        contents,
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert EmitterCanonicalNormalizedOutput(run.Stdout) == expectedOutput,
            EmitterCanonicalNormalizedOutput(run.Stdout)
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

func EmitterCanonicalAssertProgramFilesContain(
    projectName: string,
    fileNames: string[],
    contents: string[],
    expectedFragment: string
) {
    compilation := EmitterCanonicalCompile(
        projectName,
        EmitterCanonicalProjectYml(projectName, "exe"),
        fileNames,
        contents,
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert run.Stdout.Contains(expectedFragment, StringComparison.Ordinal), run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

func EmitterCanonicalCompileWithCapturedStderr(
    projectName: string,
    outputType: string,
    source: string
): EmitterCanonicalCapturedCompilation {
    originalError := Console.Error
    stderr := new StringWriter()
    captured: EmitterCanonicalCapturedCompilation? = null
    Console.SetError(stderr)
    try {
        compilation := EmitterCanonicalCompileSingle(projectName, outputType, source)
        captured = new EmitterCanonicalCapturedCompilation(compilation, stderr.ToString())
    } finally {
        Console.SetError(originalError)
        stderr.Dispose()
    }
    if captured == null {
        throw new InvalidOperationException("The stderr compilation did not produce a result")
    }
    return captured
}

// Native test declarations in this project are emitted onto one NSharpTests class, so xUnit keeps
// these process-wide controls in one collection. Each helper still restores the exact prior state
// in finally so later canonical cases observe the same environment and Console.Error writer.
func EmitterCanonicalCompileWithEnvironment(
    projectName: string,
    outputType: string,
    source: string,
    variable: string,
    setting: string
): EmitterCanonicalCompilation {
    previous := Environment.GetEnvironmentVariable(variable)
    captured: EmitterCanonicalCompilation? = null
    Environment.SetEnvironmentVariable(variable, setting)
    try {
        captured = EmitterCanonicalCompileSingle(projectName, outputType, source)
    } finally {
        Environment.SetEnvironmentVariable(variable, previous)
    }
    if captured == null {
        throw new InvalidOperationException("The environment-scoped compilation did not produce a result")
    }
    return captured
}

func EmitterCanonicalCompileWithCapturedStderrAndEnvironment(
    projectName: string,
    outputType: string,
    source: string,
    variable: string,
    setting: string
): EmitterCanonicalCapturedCompilation {
    previous := Environment.GetEnvironmentVariable(variable)
    originalError := Console.Error
    stderr := new StringWriter()
    captured: EmitterCanonicalCapturedCompilation? = null
    Environment.SetEnvironmentVariable(variable, setting)
    Console.SetError(stderr)
    try {
        compilation := EmitterCanonicalCompileSingle(projectName, outputType, source)
        captured = new EmitterCanonicalCapturedCompilation(compilation, stderr.ToString())
    } finally {
        Console.SetError(originalError)
        Environment.SetEnvironmentVariable(variable, previous)
        stderr.Dispose()
    }
    if captured == null {
        throw new InvalidOperationException("The stderr environment compilation did not produce a result")
    }
    return captured
}
