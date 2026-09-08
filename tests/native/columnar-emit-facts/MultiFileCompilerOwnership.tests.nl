namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection


func MultiFileOwnerRequiredType(typeName: string): Type {
    found := Type.GetType(typeName)
    if found == null {
        throw new InvalidOperationException("The production type was not loadable: " + typeName)
    }
    return found
}

func MultiFileOwnerRequiredConstructor(value: ConstructorInfo?, description: string): ConstructorInfo {
    if value == null {
        throw new InvalidOperationException("The production constructor was not found: " + description)
    }
    return value
}

func MultiFileOwnerRequiredMethod(value: MethodInfo?, description: string): MethodInfo {
    if value == null {
        throw new InvalidOperationException("The production method was not found: " + description)
    }
    return value
}

func MultiFileOwnerRequiredProperty(value: PropertyInfo?, description: string): PropertyInfo {
    if value == null {
        throw new InvalidOperationException("The production property was not found: " + description)
    }
    return value
}

func MultiFileOwnerRequiredField(value: FieldInfo?, description: string): FieldInfo {
    if value == null {
        throw new InvalidOperationException("The production field was not found: " + description)
    }
    return value
}

func MultiFileOwnerRequiredNestedType(value: Type?, description: string): Type {
    if value == null {
        throw new InvalidOperationException("The production nested type was not found: " + description)
    }
    return value
}

func MultiFileOwnerNewWithNullConfig(projectRoot: string): object {
    owner := EmitterCanonicalCompilerType()
    configType := MultiFileOwnerRequiredType(
        "NSharpLang.Compiler.ProjectConfig, NSharpLang.Compiler.BootstrapServices"
    )
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = configType
    constructor := owner.GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("The project-root optional-config constructor was not found.")
    }
    arguments := new object?[](2)
    EmitterCanonicalPut(arguments, 0, projectRoot)
    EmitterCanonicalPut(arguments, 1, null)
    created := constructor.Invoke(arguments)
    if created == null {
        throw new InvalidOperationException("MultiFileCompiler construction returned null.")
    }
    return created
}

func MultiFileOwnerCompileForAnalysis(compiler: object) {
    parameterTypes := new Type[](0)
    method := EmitterCanonicalCompilerType().GetMethod("CompileForAnalysis", parameterTypes)
    if method == null {
        throw new InvalidOperationException("The public CompileForAnalysis entry point was not found.")
    }
    arguments := new object?[](0)
    ignored := method.Invoke(compiler, arguments)
    _ = ignored
}

func MultiFileOwnerList(compiler: object, propertyName: string): IList {
    value := EmitterCanonicalRequiredProperty(compiler, propertyName) as IList
    if value == null {
        throw new InvalidOperationException(propertyName + " did not expose its live IList backing object.")
    }
    return value
}

func MultiFileOwnerDictionary(compiler: object, propertyName: string): object {
    value := EmitterCanonicalRequiredProperty(compiler, propertyName)
    dictionary := value as IDictionary
    if dictionary == null {
        throw new InvalidOperationException(propertyName + " did not expose its live IDictionary backing object.")
    }
    return value
}

func MultiFileOwnerCount(value: object): int {
    return Convert.ToInt32(EmitterCanonicalRequiredProperty(value, "Count"))
}

// The existing `CompileToIlAssembly_DeclineLogEnvVarWritesTraceToStderr` fact exercises the named
// wide-stack worker and its thread-local trace snapshot through this same public owner. These
// controls cover the remaining public metadata, live-state and pre-emission failure gaps.
test "the N# MultiFileCompiler owns the exact public surface without a Compiler fallback" {
    owner := EmitterCanonicalCompilerType()
    assert owner.get_Assembly().GetName().get_Name() == "NSharpLang.Compiler.BootstrapServices"
    assert Type.GetType("NSharpLang.Compiler.MultiFileCompiler, Compiler") == null
    assert owner.get_IsPublic()
    assert !owner.get_IsSealed()

    threadState := MultiFileOwnerRequiredNestedType(
        owner.GetNestedType("MultiFileCompilerEmissionThreadState", BindingFlags.NonPublic),
        "MultiFileCompilerEmissionThreadState"
    )
    assert threadState.get_IsNestedPrivate()
    assert owner.GetNestedTypes(BindingFlags.Public).Length == 0
    assert owner.GetNestedType(
        "MultiFileCompilerDefaults",
        BindingFlags.Public | BindingFlags.NonPublic
    ) == null
    assert Type.GetType(
        "NSharpLang.Compiler.MultiFileCompilerEmissionThreadState, NSharpLang.Compiler.BootstrapServices"
    ) == null
    assert Type.GetType(
        "NSharpLang.Compiler.MultiFileCompilerDefaults, NSharpLang.Compiler.BootstrapServices"
    ) == null
    assert Type.GetType(
        "NSharpLang.Compiler.MultiFileCompilerSystemsReport, NSharpLang.Compiler.BootstrapServices"
    ) == null

    configType := MultiFileOwnerRequiredType(
        "NSharpLang.Compiler.ProjectConfig, NSharpLang.Compiler.BootstrapServices"
    )
    overridesType := typeof(IReadOnlyDictionary<string, string>)
    sourceFilesType := typeof(IEnumerable<string>)

    rootOptionalTypes := new Type[](2)
    rootOptionalTypes[0] = typeof(string)
    rootOptionalTypes[1] = configType
    rootOptional := MultiFileOwnerRequiredConstructor(
        owner.GetConstructor(rootOptionalTypes),
        "project root plus optional config"
    )
    assert rootOptional.GetParameters()[1].get_IsOptional()
    assert rootOptional.GetParameters()[1].get_DefaultValue() == null

    rootOverrideTypes := new Type[](3)
    rootOverrideTypes[0] = typeof(string)
    rootOverrideTypes[1] = configType
    rootOverrideTypes[2] = overridesType
    assert owner.GetConstructor(rootOverrideTypes) != null

    explicitOptionalTypes := new Type[](3)
    explicitOptionalTypes[0] = sourceFilesType
    explicitOptionalTypes[1] = typeof(string)
    explicitOptionalTypes[2] = configType
    explicitOptional := MultiFileOwnerRequiredConstructor(
        owner.GetConstructor(explicitOptionalTypes),
        "explicit sources plus optional config"
    )
    assert explicitOptional.GetParameters()[2].get_IsOptional()
    assert explicitOptional.GetParameters()[2].get_DefaultValue() == null

    explicitOverrideTypes := new Type[](4)
    explicitOverrideTypes[0] = sourceFilesType
    explicitOverrideTypes[1] = typeof(string)
    explicitOverrideTypes[2] = configType
    explicitOverrideTypes[3] = overridesType
    assert owner.GetConstructor(explicitOverrideTypes) != null
    assert owner.GetConstructors(BindingFlags.Instance | BindingFlags.Public).Length == 4

    privateConstructors := owner.GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic)
    assert privateConstructors.Length == 1
    assert privateConstructors[0].GetParameters().Length == 3

    assert owner.GetProperties(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly).Length == 9
    propertyNames := new string[](9)
    propertyNames[0] = "CompilationUnits"
    propertyNames[1] = "SemanticModels"
    propertyNames[2] = "AllErrors"
    propertyNames[3] = "SourceFiles"
    propertyNames[4] = "SourceTexts"
    propertyNames[5] = "ProjectIndex"
    propertyNames[6] = "PerformanceFacts"
    propertyNames[7] = "SystemsReport"
    propertyNames[8] = "AotMode"
    propertyIndex := 0
    while propertyIndex < propertyNames.Length {
        property := MultiFileOwnerRequiredProperty(
            owner.GetProperty(propertyNames[propertyIndex]),
            propertyNames[propertyIndex]
        )
        assert property.get_CanRead(), propertyNames[propertyIndex]
        if propertyNames[propertyIndex] == "AotMode" {
            assert property.get_CanWrite()
        } else {
            assert !property.get_CanWrite(), propertyNames[propertyIndex]
        }
        propertyIndex = propertyIndex + 1
    }

    analysisTypes := new Type[](0)
    analysis := MultiFileOwnerRequiredMethod(
        owner.GetMethod("CompileForAnalysis", analysisTypes),
        "CompileForAnalysis"
    )
    assert analysis.get_ReturnType().get_FullName() == "System.Void"

    emitTypes := new Type[](4)
    emitTypes[0] = typeof(string)
    emitTypes[1] = typeof(string)
    emitTypes[2] = typeof(bool)
    emitTypes[3] = typeof(bool)
    emit := MultiFileOwnerRequiredMethod(
        owner.GetMethod("CompileToIlAssembly", emitTypes),
        "CompileToIlAssembly"
    )
    emitParameters := emit.GetParameters()
    assert emitParameters[2].get_IsOptional()
    assert !Convert.ToBoolean(emitParameters[2].get_DefaultValue())
    assert emitParameters[3].get_IsOptional()
    assert Convert.ToBoolean(emitParameters[3].get_DefaultValue())

    declaredMethods := owner.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly)
    declaredMethodCount := 0
    declaredMethodIndex := 0
    while declaredMethodIndex < declaredMethods.Length {
        if !declaredMethods[declaredMethodIndex].get_IsSpecialName() {
            declaredMethodCount = declaredMethodCount + 1
        }
        declaredMethodIndex = declaredMethodIndex + 1
    }
    assert declaredMethodCount == 2

    publicFields := owner.GetFields(BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.DeclaredOnly)
    privateFields := owner.GetFields(BindingFlags.Instance | BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.DeclaredOnly)
    assert publicFields.Length == 0
    fieldIndex := 0
    while fieldIndex < privateFields.Length {
        assert privateFields[fieldIndex].get_IsPrivate(), privateFields[fieldIndex].get_Name()
        fieldIndex = fieldIndex + 1
    }
}

test "MultiFileCompiler preserves distinct null configs live views fresh indexes and repeated state" {
    firstRoot := Path.Combine(Path.GetTempPath(), "nsharp-mfc-state-" + Guid.NewGuid().ToString("N"))
    secondRoot := Path.Combine(Path.GetTempPath(), "nsharp-mfc-state-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(firstRoot)
    Directory.CreateDirectory(secondRoot)
    try {
        File.WriteAllText(
            Path.Combine(firstRoot, "Program.nl"),
            "func main() {\n    print missingName\n}"
        )
        first := MultiFileOwnerNewWithNullConfig(firstRoot)
        second := MultiFileOwnerNewWithNullConfig(secondRoot)
        owner := EmitterCanonicalCompilerType()

        configField := MultiFileOwnerRequiredField(
            owner.GetField("_config", BindingFlags.Instance | BindingFlags.NonPublic),
            "_config"
        )
        firstConfig := configField.GetValue(first)
        secondConfig := configField.GetValue(second)
        assert firstConfig != null
        assert secondConfig != null
        assert !Object.ReferenceEquals(firstConfig, secondConfig)

        aot := MultiFileOwnerRequiredProperty(owner.GetProperty("AotMode"), "AotMode")
        assert !Convert.ToBoolean(aot.GetValue(first))
        aot.SetValue(first, true)
        assert Convert.ToBoolean(aot.GetValue(first))

        errors := MultiFileOwnerList(first, "AllErrors")
        sourceFiles := MultiFileOwnerList(first, "SourceFiles")
        sourceTexts := MultiFileOwnerDictionary(first, "SourceTexts")
        compilationUnits := MultiFileOwnerDictionary(first, "CompilationUnits")
        semanticModels := MultiFileOwnerDictionary(first, "SemanticModels")
        performanceFacts := EmitterCanonicalRequiredProperty(first, "PerformanceFacts")
        firstProjectIndex := EmitterCanonicalRequiredProperty(first, "ProjectIndex")
        secondProjectIndex := EmitterCanonicalRequiredProperty(first, "ProjectIndex")
        assert !Object.ReferenceEquals(firstProjectIndex, secondProjectIndex)
        assert sourceFiles.Count == 1
        assert errors.Count == 0
        assert MultiFileOwnerCount(sourceTexts) == 0
        assert MultiFileOwnerCount(compilationUnits) == 0
        assert MultiFileOwnerCount(semanticModels) == 0

        MultiFileOwnerCompileForAnalysis(first)
        assert Object.ReferenceEquals(errors, EmitterCanonicalRequiredProperty(first, "AllErrors"))
        assert Object.ReferenceEquals(sourceFiles, EmitterCanonicalRequiredProperty(first, "SourceFiles"))
        assert Object.ReferenceEquals(sourceTexts, EmitterCanonicalRequiredProperty(first, "SourceTexts"))
        assert Object.ReferenceEquals(compilationUnits, EmitterCanonicalRequiredProperty(first, "CompilationUnits"))
        assert Object.ReferenceEquals(semanticModels, EmitterCanonicalRequiredProperty(first, "SemanticModels"))
        assert Object.ReferenceEquals(performanceFacts, EmitterCanonicalRequiredProperty(first, "PerformanceFacts"))
        assert MultiFileOwnerCount(sourceTexts) == 1
        assert MultiFileOwnerCount(compilationUnits) == 1
        assert MultiFileOwnerCount(semanticModels) == 1
        assert errors.Count > 0
        firstErrorCount := errors.Count

        MultiFileOwnerCompileForAnalysis(first)
        assert errors.Count == firstErrorCount * 2
    } finally {
        if Directory.Exists(firstRoot) {
            Directory.Delete(firstRoot, true)
        }
        if Directory.Exists(secondRoot) {
            Directory.Delete(secondRoot, true)
        }
    }
}

test "MultiFileCompiler validation failure retains live errors and precedes output directory creation" {
    root := Path.Combine(Path.GetTempPath(), "nsharp-mfc-failure-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    try {
        File.WriteAllText(Path.Combine(root, "Program.nl"), "func main() {\n    value := 1 +\n}")
        compiler := MultiFileOwnerNewWithNullConfig(root)
        errors := MultiFileOwnerList(compiler, "AllErrors")
        outputDirectory := Path.Combine(root, "not-created-before-validation")
        outputPath := Path.Combine(outputDirectory, "Failure.dll")

        parameterTypes := new Type[](4)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(string)
        parameterTypes[2] = typeof(bool)
        parameterTypes[3] = typeof(bool)
        method := EmitterCanonicalCompilerType().GetMethod("CompileToIlAssembly", parameterTypes)
        if method == null {
            throw new InvalidOperationException("The public CompileToIlAssembly entry point was not found.")
        }
        arguments := new object?[](4)
        EmitterCanonicalPut(arguments, 0, "Failure")
        EmitterCanonicalPut(arguments, 1, outputPath)
        EmitterCanonicalPut(arguments, 2, false)
        EmitterCanonicalPut(arguments, 3, true)
        result := method.Invoke(compiler, arguments)
        if result == null {
            throw new InvalidOperationException("CompileToIlAssembly returned null.")
        }

        assert !Convert.ToBoolean(EmitterCanonicalRequiredProperty(result, "Success"))
        assert EmitterCanonicalOptionalProperty(result, "OutputAssemblyPath") == null
        assert Object.ReferenceEquals(errors, EmitterCanonicalRequiredProperty(compiler, "AllErrors"))
        assert Object.ReferenceEquals(errors, EmitterCanonicalRequiredProperty(result, "Errors"))
        assert errors.Count > 0
        assert !Directory.Exists(outputDirectory)
        assert !File.Exists(outputPath)
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "MultiFileCompiler AotMode requires columnar emission for the countChars string foreach pipeline" {
    root := Path.Combine(Path.GetTempPath(), "nsharp-mfc-aot-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    try {
        File.WriteAllText(
            Path.Combine(root, "project.yml"),
            "name: AotCheckRequiresColumnar\noutputType: library\ntargetFramework: net10.0"
        )
        File.WriteAllText(
            Path.Combine(root, "Program.nl"),
            "func countChars(s: string): int {\n    n := 0\n    foreach c in s {\n        n = n + 1\n    }\n    return n\n}"
        )
        compiler := MultiFileOwnerNewWithNullConfig(root)
        owner := EmitterCanonicalCompilerType()
        aot := MultiFileOwnerRequiredProperty(owner.GetProperty("AotMode"), "AotMode")
        aot.SetValue(compiler, true)
        assert Convert.ToBoolean(aot.GetValue(compiler))

        outputPath := Path.Combine(root, "artifacts", "AotCheckRequiresColumnar.dll")
        parameterTypes := new Type[](4)
        parameterTypes[0] = typeof(string)
        parameterTypes[1] = typeof(string)
        parameterTypes[2] = typeof(bool)
        parameterTypes[3] = typeof(bool)
        method := MultiFileOwnerRequiredMethod(
            owner.GetMethod("CompileToIlAssembly", parameterTypes),
            "CompileToIlAssembly"
        )
        arguments := new object?[](4)
        EmitterCanonicalPut(arguments, 0, "AotCheckRequiresColumnar")
        EmitterCanonicalPut(arguments, 1, outputPath)
        EmitterCanonicalPut(arguments, 2, false)
        EmitterCanonicalPut(arguments, 3, true)
        result := method.Invoke(compiler, arguments)
        if result == null {
            throw new InvalidOperationException("CompileToIlAssembly returned null.")
        }

        assert !Convert.ToBoolean(EmitterCanonicalRequiredProperty(result, "Success"))
        assert EmitterCanonicalOptionalProperty(result, "OutputAssemblyPath") == null
        assert !File.Exists(outputPath)
        errors := EmitterCanonicalRequiredProperty(result, "Errors") as IList
        if errors == null {
            throw new InvalidOperationException("Compilation errors did not implement IList.")
        }
        foundAotDiagnostic := false
        errorIndex := 0
        while errorIndex < errors.Count {
            error := errors[errorIndex]
            if error != null && EmitterCanonicalErrorText(error, "Message").Contains(
                "Columnar AOT emission is required",
                StringComparison.Ordinal
            ) {
                foundAotDiagnostic = true
            }
            errorIndex = errorIndex + 1
        }
        assert foundAotDiagnostic
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}
