namespace NSharpLang.AnalyzerErrorHandling.Tests

import System
import System.Collections.Generic
import System.IO


// PUBLIC ANALYZER LIFECYCLE CONTRACTS.
//
// These exercise the public Analyzer boundary through the same reflection route as the existing
// analyzer-native corpus while Analyzer remains in Compiler.dll. They cover three state contracts
// the leaf-owner tests cannot establish: declaration-file snapshots are copies, a later analysis
// clears the error list retained by an earlier AnalysisResult while replacing its model/bindings,
// and SetProjectSourceTexts replaces the complete source snapshot before the next analysis.
//
// When Analyzer moves into BootstrapServices, the one exact owner identity below moves with the
// other analyzer-native lookups. There is deliberately no fallback or dual-assembly path.
func AlAnalyzerType(): Type {
    analyzerType := Type.GetType("NSharpLang.Compiler.Analyzer, Compiler")
    if analyzerType == null {
        throw new InvalidOperationException("The production Analyzer type was not loadable.")
    }
    return analyzerType
}

func AlNewAnalyzer(): object {
    analyzerType := AlAnalyzerType()
    constructorParameterTypes := new Type[](0)
    analyzerConstructor := analyzerType.GetConstructor(constructorParameterTypes)
    if analyzerConstructor == null {
        throw new InvalidOperationException("The production Analyzer was not constructible.")
    }
    constructorArguments := new object?[](0)
    analyzer := analyzerConstructor.Invoke(constructorArguments)
    if analyzer == null {
        throw new InvalidOperationException("The production Analyzer constructor returned no instance.")
    }

    loadParameterTypes := new Type[](0)
    load := analyzerType.GetMethod("LoadSystemAssemblies", loadParameterTypes)
    if load == null {
        throw new InvalidOperationException("The production LoadSystemAssemblies entry point was not found.")
    }
    loadArguments := new object?[](0)
    load.Invoke(analyzer, loadArguments)
    return analyzer
}

func AlAnalyzeAt(analyzer: object, source: string, filePath: string, projectRoot: string?): object {
    unit := EhParseUnit(source)
    unitType := Type.GetType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.BootstrapServices")
    if unitType == null {
        throw new InvalidOperationException("The production CompilationUnit type was not loadable.")
    }

    parameterTypes := new Type[](4)
    parameterTypes[0] = unitType
    parameterTypes[1] = typeof(string)
    parameterTypes[2] = typeof(string)
    parameterTypes[3] = typeof(string)
    analyze := analyzer.GetType().GetMethod("Analyze", parameterTypes)
    if analyze == null {
        throw new InvalidOperationException("The production four-argument Analyze entry point was not found.")
    }

    arguments := new object?[](4)
    SetEhObject(arguments, 0, unit)
    SetEhObject(arguments, 1, filePath)
    SetEhObject(arguments, 2, projectRoot)
    SetEhObject(arguments, 3, source)
    analysis := analyze.Invoke(analyzer, arguments)
    if analysis == null {
        throw new InvalidOperationException("The production Analyzer returned no analysis.")
    }
    return analysis
}

func AlGetTypeDeclarationFiles(analyzer: object): object {
    parameterTypes := new Type[](0)
    getFiles := analyzer.GetType().GetMethod("GetTypeDeclarationFiles", parameterTypes)
    if getFiles == null {
        throw new InvalidOperationException("The production GetTypeDeclarationFiles entry point was not found.")
    }
    arguments := new object?[](0)
    files := getFiles.Invoke(analyzer, arguments)
    if files == null {
        throw new InvalidOperationException("The production Analyzer returned no declaration-file snapshot.")
    }
    return files
}

func AlCount(value: object): int {
    return Convert.ToInt32(EhRequiredMember(value, "Count"))
}

func AlContainsKey(dictionary: object, key: string): bool {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    containsKey := dictionary.GetType().GetMethod("ContainsKey", parameterTypes)
    if containsKey == null {
        throw new InvalidOperationException("The declaration-file snapshot exposed no ContainsKey method.")
    }
    arguments := new object?[](1)
    SetEhObject(arguments, 0, key)
    return Convert.ToBoolean(containsKey.Invoke(dictionary, arguments))
}

func AlClear(dictionary: object) {
    parameterTypes := new Type[](0)
    clear := dictionary.GetType().GetMethod("Clear", parameterTypes)
    if clear == null {
        throw new InvalidOperationException("The declaration-file snapshot exposed no Clear method.")
    }
    arguments := new object?[](0)
    clear.Invoke(dictionary, arguments)
}

func AlReadOnlyStringDictionaryType(): Type {
    definition := Type.GetType("System.Collections.Generic.IReadOnlyDictionary`2")
    if definition == null {
        throw new InvalidOperationException("The IReadOnlyDictionary runtime definition was not found.")
    }
    arguments := new Type[](2)
    arguments[0] = typeof(string)
    arguments[1] = typeof(string)
    return definition.MakeGenericType(arguments)
}

func AlSetProjectSourceTexts(analyzer: object, sourceTexts: Dictionary<string, string>) {
    parameterTypes := new Type[](1)
    parameterTypes[0] = AlReadOnlyStringDictionaryType()
    setSources := analyzer.GetType().GetMethod("SetProjectSourceTexts", parameterTypes)
    if setSources == null {
        throw new InvalidOperationException("The production SetProjectSourceTexts entry point was not found.")
    }
    arguments := new object?[](1)
    SetEhObject(arguments, 0, sourceTexts)
    setSources.Invoke(analyzer, arguments)
}

func AlDispose(analyzer: object) {
    parameterTypes := new Type[](0)
    dispose := analyzer.GetType().GetMethod("Dispose", parameterTypes)
    if dispose == null {
        throw new InvalidOperationException("The production Dispose entry point was not found.")
    }
    arguments := new object?[](0)
    dispose.Invoke(analyzer, arguments)
}

test "analyzer lifecycle: declaration-file snapshots are fresh copies rather than the live declaration map" {
    analyzer := AlNewAnalyzer()
    try {
        source := "class One { }"
        analysis := AlAnalyzeAt(analyzer, source, "/tmp/nsharp-analyzer-lifecycle-one.nl", null)
        assert EhCensus(analysis) == "", EhCensus(analysis)

        first := AlGetTypeDeclarationFiles(analyzer)
        assert AlCount(first) == 1, AlCount(first)
        assert AlContainsKey(first, "One")

        // Mutating the returned dictionary must not mutate the Analyzer's own declaration map.
        AlClear(first)
        second := AlGetTypeDeclarationFiles(analyzer)
        firstObject: object = first
        secondObject: object = second
        assert !Object.ReferenceEquals(firstObject, secondObject)
        assert AlCount(second) == 1, AlCount(second)
        assert AlContainsKey(second, "One")
    } finally {
        AlDispose(analyzer)
    }
}

test "analyzer lifecycle: a later analysis mutates old errors but preserves the old semantic model and binding map" {
    analyzer := AlNewAnalyzer()
    try {
        firstSource := "class First { }"
        first := AlAnalyzeAt(analyzer, firstSource, "/tmp/nsharp-analyzer-lifecycle-first.nl", null)
        firstErrors: object = EhRequiredMember(first, "Errors")
        firstModel: object = EhRequiredMember(first, "SemanticModel")
        firstBindings: object = EhRequiredMember(first, "Bindings")
        assert AlCount(firstErrors) == 0, AlCount(firstErrors)

        secondSource := "func Main() { nope }"
        second := AlAnalyzeAt(analyzer, secondSource, "/tmp/nsharp-analyzer-lifecycle-second.nl", null)
        secondErrors: object = EhRequiredMember(second, "Errors")
        secondModel: object = EhRequiredMember(second, "SemanticModel")
        secondBindings: object = EhRequiredMember(second, "Bindings")

        // The first AnalysisResult shares the mutable error list, so it sees the second call's row.
        assert Object.ReferenceEquals(firstErrors, secondErrors)
        assert AlCount(firstErrors) == 1, AlCount(firstErrors)
        assert EhCensus(second) == "NL301:UndefinedVariable@1:15+4;", EhCensus(second)
        assert EhRow(second, 0) == "UndefinedVariable|Variable 'nope' not found|<null>|Error", EhRow(second, 0)

        // Models and binding maps are replaced per call, and the first result retains its own pair.
        assert !Object.ReferenceEquals(firstModel, secondModel)
        assert !Object.ReferenceEquals(firstBindings, secondBindings)
        assert Object.ReferenceEquals(firstModel, EhRequiredMember(first, "SemanticModel"))
        assert Object.ReferenceEquals(firstBindings, EhRequiredMember(first, "Bindings"))
    } finally {
        AlDispose(analyzer)
    }
}

test "analyzer lifecycle: replacing project source texts removes prior project declarations before the next analysis" {
    root := Path.Combine(Path.GetTempPath(), "nsharp-analyzer-lifecycle-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(root)
    analyzer := AlNewAnalyzer()
    try {
        sharedPath := Path.Combine(root, "shared.nl")
        mainPath := Path.Combine(root, "main.nl")
        sourceTexts := new Dictionary<string, string>()
        sourceTexts[sharedPath] = "class Shared {\n}"
        AlSetProjectSourceTexts(analyzer, sourceTexts)

        mainSource := "func Main() {\n    value: Shared = new Shared()\n}"
        resolved := AlAnalyzeAt(analyzer, mainSource, mainPath, root)
        assert EhCensus(resolved) == "", EhCensus(resolved)
        resolvedFiles := AlGetTypeDeclarationFiles(analyzer)
        assert AlCount(resolvedFiles) == 1, AlCount(resolvedFiles)
        assert AlContainsKey(resolvedFiles, "Shared")

        // Resetting with an empty snapshot clears the cached project unit, so both uses now fail.
        AlSetProjectSourceTexts(analyzer, new Dictionary<string, string>())
        missing := AlAnalyzeAt(analyzer, mainSource, mainPath, root)
        assert EhCensus(missing) == "NL201:TypeNotFound@2:12+6;NL201:TypeNotFound@2:25+6;", EhCensus(missing)
        assert EhRow(missing, 0) == "TypeNotFound|Type 'Shared' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'Shared'.|Error", EhRow(missing, 0)
        assert EhRow(missing, 1) == "TypeNotFound|Type 'Shared' not found|Check the spelling, add the missing 'import', or add the package/project reference that provides 'Shared'.|Error", EhRow(missing, 1)
    } finally {
        AlDispose(analyzer)
        Directory.Delete(root)
    }
}
