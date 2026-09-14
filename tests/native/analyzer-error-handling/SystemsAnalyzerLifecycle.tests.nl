namespace NSharpLang.AnalyzerErrorHandling.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO


// SYSTEMS ANALYZER LIFECYCLE CONTRACTS.
//
// The existing systems corpus exercises the emitted report through CLI processes.  That is the
// correct public-product coverage for policy facts, but a process cannot retain one
// `SystemsAnalyzer` across two calls.  These rows therefore use the existing reflection harness
// to state the two stateful public contracts of the complete owner:
//
//   * `SystemsReport.Functions` is the analyzer's live list, so an older report observes the
//     next `Analyze` reset and repopulation; and
//   * `Analyze` clears that list before `BuildVisibleDeclarationFiles` materializes its
//     case-insensitive full-path dictionary.  Two distinct input keys that normalize to the same
//     path therefore fail after the prior report has been reset.
//
// During this baseline proof the C# owner lives in Compiler.dll.  Once the complete owner moves,
// `SaSystemsAnalyzerType` is mechanically routed to its sole Compiler Core identity; there is
// deliberately no assembly fallback or alternate behavioral path.
func SaPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func SaRequiredType(typeName: string): Type {
    value := Type.GetType(typeName)
    if value == null {
        throw new InvalidOperationException("The production type '" + typeName + "' was not loadable.")
    }

    return value
}

func SaSystemsAnalyzerType(): Type {
    return SaRequiredType("NSharpLang.Compiler.Performance.SystemsAnalyzer, NSharpLang.Compiler.Core")
}

func SaCompilationUnitType(): Type {
    return SaRequiredType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.Core")
}

func SaProjectConfigType(): Type {
    return SaRequiredType("NSharpLang.Compiler.ProjectConfig, NSharpLang.Compiler.Core")
}

func SaPerformanceFactStoreType(): Type {
    return SaRequiredType("NSharpLang.Compiler.Performance.PerformanceFactStore, NSharpLang.Compiler.Core")
}

func SaSemanticModelType(): Type {
    return SaRequiredType("NSharpLang.Compiler.SemanticModel, NSharpLang.Compiler.Core")
}

func SaReadOnlyDictionaryType(valueType: Type): Type {
    definition := Type.GetType("System.Collections.Generic.IReadOnlyDictionary`2")
    if definition == null {
        throw new InvalidOperationException("The IReadOnlyDictionary runtime definition was not loadable.")
    }

    arguments := new Type[](2)
    arguments[0] = typeof(string)
    arguments[1] = valueType
    return definition.MakeGenericType(arguments)
}

func SaNewUnitDictionary(): object {
    definition := typeof(Dictionary<string, int>).GetGenericTypeDefinition()
    arguments := new Type[](2)
    arguments[0] = typeof(string)
    arguments[1] = SaCompilationUnitType()
    closed := definition.MakeGenericType(arguments)
    parameterTypes := new Type[](0)
    constructor := closed.GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("The closed compilation-unit dictionary was not constructible.")
    }

    constructorArguments := new object?[](0)
    dictionary := constructor.Invoke(constructorArguments)
    if dictionary == null {
        throw new InvalidOperationException("The closed compilation-unit dictionary constructor returned null.")
    }

    return dictionary
}

func SaAddUnit(dictionary: object, path: string, source: string) {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = SaCompilationUnitType()
    add := dictionary.GetType().GetMethod("Add", parameterTypes)
    if add == null {
        throw new InvalidOperationException("The closed compilation-unit dictionary exposed no Add method.")
    }

    arguments := new object?[](2)
    SaPut(arguments, 0, path)
    SaPut(arguments, 1, EhParseUnit(source))
    ignored := add.Invoke(dictionary, arguments)
    _ = ignored
}

func SaUnits(path: string, source: string): object {
    dictionary := SaNewUnitDictionary()
    SaAddUnit(dictionary, path, source)
    return dictionary
}

func SaNewAnalyzer(): object {
    analyzerType := SaSystemsAnalyzerType()
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = SaProjectConfigType()
    constructor := analyzerType.GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("The production SystemsAnalyzer constructor was not found.")
    }

    arguments := new object?[](2)
    SaPut(arguments, 0, Path.GetTempPath())
    SaPut(arguments, 1, null)
    analyzer := constructor.Invoke(arguments)
    if analyzer == null {
        throw new InvalidOperationException("The production SystemsAnalyzer constructor returned null.")
    }

    return analyzer
}

func SaAnalyze(analyzer: object, units: object): object {
    parameterTypes := new Type[](3)
    parameterTypes[0] = SaReadOnlyDictionaryType(SaCompilationUnitType())
    parameterTypes[1] = SaPerformanceFactStoreType()
    parameterTypes[2] = SaReadOnlyDictionaryType(SaSemanticModelType())
    analyze := analyzer.GetType().GetMethod("Analyze", parameterTypes)
    if analyze == null {
        throw new InvalidOperationException("The production SystemsAnalyzer Analyze entry point was not found.")
    }

    arguments := new object?[](3)
    SaPut(arguments, 0, units)
    SaPut(arguments, 1, null)
    SaPut(arguments, 2, null)
    report := analyze.Invoke(analyzer, arguments)
    if report == null {
        throw new InvalidOperationException("The production SystemsAnalyzer returned no report.")
    }

    return report
}

func SaFunctions(report: object): IList {
    functions := EhRequiredMember(report, "Functions") as IList
    if functions == null {
        throw new InvalidOperationException("The production SystemsReport Functions member was not an IList.")
    }

    return functions
}

func SaFunctionName(functions: IList, index: int): string {
    item := functions[index]
    if item == null {
        throw new InvalidOperationException("The production SystemsReport contained a null function row.")
    }

    return EhText(item, "Name")
}

func SaExceptionTypeName(error: Exception): string {
    boxed: object = error
    errorType := boxed.GetType()
    fullName := errorType.get_FullName()
    if fullName == null {
        return errorType.get_Name()
    }

    return fullName
}

func SaExceptionShape(error: Exception): string {
    shape := SaExceptionTypeName(error)
    innerBox: object? = error.get_InnerException()
    if innerBox == null {
        return shape
    }

    inner := innerBox as Exception
    if inner == null {
        return shape + "|<non-exception-inner>"
    }

    return shape + "|" + SaExceptionTypeName(inner)
}

test "systems analyzer lifecycle: report Functions remains the live list across a later Analyze reset" {
    analyzer := SaNewAnalyzer()
    first := SaAnalyze(analyzer, SaUnits("/tmp/nsharp-systems-analyzer-first.nl", "func First(): int {\n    return 1\n}\n"))
    firstFunctions := SaFunctions(first)
    assert firstFunctions.Count == 1, firstFunctions.Count
    assert SaFunctionName(firstFunctions, 0) == "First", SaFunctionName(firstFunctions, 0)

    second := SaAnalyze(analyzer, SaUnits("/tmp/nsharp-systems-analyzer-second.nl", "func Second(): int {\n    return 2\n}\n"))
    secondFunctions := SaFunctions(second)
    firstObject: object = firstFunctions
    secondObject: object = secondFunctions
    assert Object.ReferenceEquals(firstObject, secondObject)

    // The first report shares `_functions`, which Analyze clears then repopulates for the second input.
    assert firstFunctions.Count == 1, firstFunctions.Count
    assert SaFunctionName(firstFunctions, 0) == "Second", SaFunctionName(firstFunctions, 0)
}

test "systems analyzer lifecycle: normalized duplicate input paths fail after the prior report has been reset" {
    analyzer := SaNewAnalyzer()
    prior := SaAnalyze(analyzer, SaUnits("/tmp/nsharp-systems-analyzer-prior.nl", "func Prior(): int {\n    return 1\n}\n"))
    priorFunctions := SaFunctions(prior)
    assert priorFunctions.Count == 1, priorFunctions.Count
    assert SaFunctionName(priorFunctions, 0) == "Prior", SaFunctionName(priorFunctions, 0)

    // Dictionary accepts these distinct ordinal keys, while BuildVisibleDeclarationFiles normalizes both
    // through Path.GetFullPath and materializes an OrdinalIgnoreCase ToDictionary.
    duplicateUnits := SaNewUnitDictionary()
    SaAddUnit(duplicateUnits, "/tmp/nsharp-systems-analyzer-duplicate.nl", "func Left(): int {\n    return 1\n}\n")
    SaAddUnit(duplicateUnits, "/tmp/./nsharp-systems-analyzer-duplicate.nl", "func Right(): int {\n    return 2\n}\n")

    failure: Exception? = null
    try {
        SaAnalyze(analyzer, duplicateUnits)
    } catch error: Exception {
        failure = error
    }

    if failure == null {
        throw new InvalidOperationException("Normalized duplicate paths did not fail SystemsAnalyzer.Analyze.")
    }

    captured: Exception = failure
    assert SaExceptionShape(captured) == "System.Reflection.TargetInvocationException|System.ArgumentException", SaExceptionShape(captured)

    // Reset happens before the path materialization throws, and the already-issued report sees that reset.
    assert priorFunctions.Count == 0, priorFunctions.Count
}
