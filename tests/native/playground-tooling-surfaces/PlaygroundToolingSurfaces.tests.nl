namespace NSharpLang.PlaygroundToolingSurfaces.Tests

import System
import System.Collections
import System.Reflection


// THE PLAYGROUND'S FOUR NON-CHECK RESPONSE RECORDS, IN N#.
//
// These replace the OTHER 14 bodies of `tests/PlaygroundCompilerTests.cs` — the file slice 37
// opened and this slice closes. 14 `[Fact]`s, 307 declaration lines, 61 in-body `Assert.` calls,
// 3 `AssertCompletion` calls and 64 decoded claim rows. The 21 bodies that answer
// `PlaygroundCheckResponse` through `Check(source)` went to the sibling
// `tests/native/playground-diagnostic-spans` instead, because they answer the record that project
// is named for and 18 of the 21 read `Line`, `Column` and `Length` directly.
//
// WHY THIS IS A SIBLING PROJECT AND NOT A SECOND FILE UNDER THAT NAME. ZERO of these 14 bodies is
// span-shaped. They answer FOUR OTHER response records — `PlaygroundCatalogResponse`,
// `PlaygroundCompletionResponse`, `PlaygroundRunResponse`, `PlaygroundFormatResponse` — they reach
// a production type no native project has ever touched (`PlaygroundExamples`, named by three of
// them), and one of the four ENTRY POINTS EXECUTES THE PROGRAM and reads its stdout, which is a
// different capability class from reading a diagnostic's span. A directory named
// `playground-diagnostic-spans` holding the tutorial-validation and stdout contracts would be a
// name that lies about 14 of its contracts. The price is stated rather than hidden: the nine base
// reflection kernels below are duplicated from that project, because a native project cannot
// reference another native project.
//
// FIVE THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//
//   (a) THE COMPLETION LIST OFFERS COMPILER-GENERATED ACCESSORS TO THE USER. Across the nine
//       pinned completion sites, **51 of 339 items are `get_`/`set_`/`add_`/`remove_` accessor
//       methods** — on `Console.` it is 45 of 92, nearly half the list — and on `System.String`
//       `get_Chars` and `get_Length` are offered ALONGSIDE the properties `Chars` and `Length`, so
//       the same member appears twice under two names, one of them a name no N# program can write.
//       The deleted assertions named 9 labels out of 339 and never looked at the rest.
//
//   (b) THE `PG900` ABSENCE CLAIM WAS STRUCTURALLY VACUOUS. `CheckProject_AcceptsTutorialProgram…`
//       asserted `DoesNotContain(Code == "PG900")`. `PG900` occurs in exactly ONE place in the
//       whole repository — that assertion. The shipping playground emits `PG001`, `PG200`–`PG237`
//       and `PG299`, and there is no `PG9xx` code at all, so no code path could ever have produced
//       it. The successor pins the WHOLE census of that response instead, which is EMPTY.
//
//   (c) THE ONE FIXTURE WHOSE COMPLETION SITE IS NOT WHERE ITS NAME SAYS. The deleted
//       `Complete_MemberAccess_ReturnsSourceDefinedMethodsAndProperties` located `todo.Id` with a
//       first-match line scan, which finds it on line 11 INSIDE a string interpolation in the class
//       body — not the `print todo.Id` on line 19 that the method reads as if it drove. T1b pins
//       line 19 as well, and the two sites answer the same three members.
//
//   (d) TWO OF THE FIVE COMPLETION FIXTURES DO NOT COMPILE, AND THE ENGINE ANSWERS ANYWAY. The
//       interpolated-string-literal fixture reports FIVE diagnostics and the just-typed-dot fixture
//       reports one; the deleted assertions read only `Context`, `ReceiverType` and a label.
//
//   (e) THE UNSUPPORTED-CONSTRUCT CODE IS `PG204`, NOT `PG2` — the C# matched a PREFIX. The
//       successor pins the code, the sentence and the `UnsupportedReason` whole.
func SetPgObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// A boxing store into an `object?[]` element DECLINES AT EMIT when the source is an `int`-typed
// PARAMETER written straight into the element; routing it through a typed `object` local emits.
// Found by bisection against `nlc test`, not guessed.
func SetPgInt(values: object?[], index: int, value: int) {
    boxed: object = value
    values[index] = boxed
}

func PgMember(owner: object, memberName: string): object? {
    property := owner.GetType().GetProperty(memberName)
    if property != null {
        return property.GetValue(owner)
    }

    field := owner.GetType().GetField(memberName)
    if field != null {
        return field.GetValue(owner)
    }

    throw new InvalidOperationException("The production type exposed no member named " + memberName)
}

func PgText(owner: object, memberName: string): string {
    value := PgMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

func PgStaticMember(owner: Type, memberName: string): object? {
    property := owner.GetProperty(memberName)
    if property != null {
        return property.GetValue(null)
    }

    field := owner.GetField(memberName)
    if field != null {
        return field.GetValue(null)
    }

    throw new InvalidOperationException("The production type exposed no static member named " + memberName)
}

func PgStaticText(owner: Type, memberName: string): string {
    value := PgStaticMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

func PgCompilerType(): Type {
    compilerType := Type.GetType("NSharpLang.Playground.PlaygroundCompiler, NSharpLang.Playground")
    if compilerType == null {
        throw new InvalidOperationException("The production playground compiler was not loadable.")
    }

    return compilerType
}

func PgExamplesType(): Type {
    examplesType := Type.GetType("NSharpLang.Playground.PlaygroundExamples, NSharpLang.Compiler.BootstrapServices")
    if examplesType == null {
        throw new InvalidOperationException("The production playground examples class was not loadable.")
    }

    return examplesType
}

func PgNewCompiler(): object {
    constructorParameterTypes := new Type[](0)
    constructor := PgCompilerType().GetConstructor(constructorParameterTypes)
    if constructor == null {
        throw new InvalidOperationException("The production playground compiler was not constructible.")
    }

    constructorArguments := new object?[](0)
    return constructor.Invoke(constructorArguments)
}

func PgFileType(): Type {
    fileType := Type.GetType("NSharpLang.Playground.PlaygroundFile, NSharpLang.Compiler.BootstrapServices")
    if fileType == null {
        throw new InvalidOperationException("The production playground file record was not loadable.")
    }

    return fileType
}

func PgNewFile(name: string, code: string): object {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(string)
    constructor := PgFileType().GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("The production playground file record was not constructible.")
    }

    arguments := new object?[](2)
    SetPgObject(arguments, 0, name)
    SetPgObject(arguments, 1, code)
    return constructor.Invoke(arguments)
}

func PgEmptyFileArray(count: int): object {
    return Array.CreateInstance(PgFileType(), count)
}

func PgSetFile(target: object, index: int, value: object) {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(object)
    parameterTypes[1] = typeof(int)
    setMethod := target.GetType().GetMethod("SetValue", parameterTypes)
    if setMethod == null {
        throw new InvalidOperationException("The constructed file array exposed no SetValue entry point.")
    }

    arguments := new object?[](2)
    SetPgObject(arguments, 0, value)
    SetPgInt(arguments, 1, index)
    setMethod.Invoke(target, arguments)
}

// ---- the shared response readers ----

func PgList(owner: object, memberName: string): IList? {
    return PgMember(owner, memberName) as IList
}

func PgListCount(owner: object, memberName: string): int {
    entries := PgList(owner, memberName)
    if entries == null {
        return -1
    }

    return entries.Count
}

func PgEntry(owner: object, memberName: string, index: int): object? {
    entries := PgList(owner, memberName)
    if entries == null {
        return null
    }

    if index >= entries.Count {
        return null
    }

    return entries[index]
}

func PgOk(response: object): string {
    return PgText(response, "Ok")
}

func PgSchemaVersion(response: object): string {
    return PgText(response, "SchemaVersion")
}

func PgFileName(response: object): string {
    return PgText(response, "File")
}

func PgSummary(response: object): string {
    summary := PgMember(response, "Summary")
    if summary == null {
        return "<null>"
    }

    return PgText(summary, "Errors") + "/" + PgText(summary, "Warnings") + "/" + PgText(summary, "Infos")
}

func PgCount(response: object): int {
    return PgListCount(response, "Diagnostics")
}

func PgCensus(response: object): string {
    entries := PgList(response, "Diagnostics")
    if entries == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < entries.Count {
        entry := entries[index]
        if entry != null {
            census = census + PgText(entry, "Code") + "@" + PgText(entry, "Line") + ":" + PgText(entry, "Column") + "+" + PgText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

func PgRow(response: object, index: int): string {
    entry := PgEntry(response, "Diagnostics", index)
    if entry == null {
        return "<no-such-diagnostic>"
    }

    return PgText(entry, "Code") + "|" + PgText(entry, "Severity") + "|" + PgText(entry, "Message") + "|" + PgText(entry, "File") + "|" + PgText(entry, "Line") + "|" + PgText(entry, "Column") + "|" + PgText(entry, "Length")
}

// ---- the CATALOG surface ----

func PgCatalog(): object {
    parameterTypes := new Type[](0)
    catalogMethod := PgCompilerType().GetMethod("GetCatalog", parameterTypes)
    if catalogMethod == null {
        throw new InvalidOperationException("The production GetCatalog entry point was not found.")
    }

    // `new object?[](0)` written INLINE as `Invoke`'s second argument DECLINES AT EMIT; bound to a
    // local it emits. Found by bisection against `nlc test`, not guessed.
    arguments := new object?[](0)
    response := catalogMethod.Invoke(PgNewCompiler(), arguments)
    if response == null {
        throw new InvalidOperationException("The production GetCatalog entry point returned no result.")
    }

    return response
}

func PgCapabilities(catalog: object): string {
    capabilities := PgMember(catalog, "Capabilities")
    if capabilities == null {
        return "<null>"
    }

    return PgText(capabilities, "RunsInBrowser") + "|" + PgText(capabilities, "SupportsDiagnostics") + "|" + PgText(capabilities, "SupportsFormatting") + "|" + PgText(capabilities, "SupportsCompletions") + "|" + PgText(capabilities, "SupportsHover") + "|" + PgText(capabilities, "SupportsSyntaxHighlighting") + "|" + PgText(capabilities, "SupportsExecution") + "|" + PgText(capabilities, "SupportsTests")
}

func PgLimitationCount(catalog: object): int {
    capabilities := PgMember(catalog, "Capabilities")
    if capabilities == null {
        return -1
    }

    return PgListCount(capabilities, "Limitations")
}

func PgLimitation(catalog: object, index: int): string {
    capabilities := PgMember(catalog, "Capabilities")
    if capabilities == null {
        return "<null>"
    }

    entry := PgEntry(capabilities, "Limitations", index)
    if entry == null {
        return "<no-such-limitation>"
    }

    return entry.ToString() ?? "<null>"
}

func PgExampleRow(catalog: object, index: int): string {
    example := PgEntry(catalog, "Examples", index)
    if example == null {
        return "<no-such-example>"
    }

    return PgText(example, "Id") + "|" + PgText(example, "Title") + "|" + PgText(example, "Minutes") + "|" + PgText(example, "HasTests") + "|" + PgText(example, "ExpectedOutput")
}

func PgExampleConcepts(catalog: object, index: int): int {
    example := PgEntry(catalog, "Examples", index)
    if example == null {
        return -1
    }

    return PgListCount(example, "Concepts")
}

func PgExampleIdCensus(catalog: object): string {
    entries := PgList(catalog, "Examples")
    if entries == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < entries.Count {
        entry := entries[index]
        if entry != null {
            census = census + PgText(entry, "Id") + ";"
        }

        index = index + 1
    }

    return census
}

func PgTutorialRow(catalog: object, index: int): string {
    step := PgEntry(catalog, "Tutorial", index)
    if step == null {
        return "<no-such-step>"
    }

    validation := PgMember(step, "Validation")
    validationText := "<null>"
    if validation != null {
        validationText = PgText(validation, "Type") + "/" + PgText(validation, "ExpectedOutput") + "/" + PgText(validation, "RequiredText") + "/" + PgText(validation, "SuccessMessage")
    }

    return PgText(step, "Id") + "|" + PgText(step, "Title") + "|" + PgText(step, "Kind") + "|" + PgText(step, "ExampleId") + "|" + validationText
}

// ---- the EXAMPLE CORPUS, read straight off the production static ----

func PgExamples(): IList {
    entries := PgStaticMember(PgExamplesType(), "All") as IList
    if entries == null {
        throw new InvalidOperationException("The production example corpus was not a list.")
    }

    return entries
}

func PgExample(index: int): object {
    entries := PgExamples()
    entry := entries[index]
    if entry == null {
        throw new InvalidOperationException("The production example corpus had a null entry.")
    }

    return entry
}

func PgExampleCode(index: int): string {
    return PgText(PgExample(index), "Code")
}

// The deleted C# passed `example.TestsCode ?? string.Empty`; ONE of the ten examples has a null
// `TestsCode`, so the coalesce is load-bearing and is reproduced here.
func PgExampleTestsOrEmpty(index: int): string {
    value := PgMember(PgExample(index), "TestsCode")
    if value == null {
        return ""
    }

    return value.ToString() ?? ""
}

func PgFirstExampleWithTests(): int {
    entries := PgExamples()
    index := 0
    while index < entries.Count {
        entry := entries[index]
        if entry != null {
            if PgText(entry, "HasTests") == "True" {
                return index
            }
        }

        index = index + 1
    }

    return -1
}

func PgIndexOfExample(id: string): int {
    entries := PgExamples()
    index := 0
    while index < entries.Count {
        entry := entries[index]
        if entry != null {
            if PgText(entry, "Id") == id {
                return index
            }
        }

        index = index + 1
    }

    return -1
}

// ---- the CHECK entry point, for the example-corpus contracts ----

func PgCheckFiles(files: object, activeFile: string): object {
    checkMethod := PgCompilerType().GetMethod("CheckProject")
    if checkMethod == null {
        throw new InvalidOperationException("The production CheckProject entry point was not found.")
    }

    checkArguments := new object?[](2)
    SetPgObject(checkArguments, 0, files)
    SetPgObject(checkArguments, 1, activeFile)
    response := checkMethod.Invoke(PgNewCompiler(), checkArguments)
    if response == null {
        throw new InvalidOperationException("The production CheckProject entry point returned no result.")
    }

    return response
}

func PgCheckExample(index: int): object {
    files := PgEmptyFileArray(2)
    PgSetFile(files, 0, PgNewFile("Program.nl", PgExampleCode(index)))
    PgSetFile(files, 1, PgNewFile("Program.tests.nl", PgExampleTestsOrEmpty(index)))
    return PgCheckFiles(files, "Program.nl")
}

// ---- the COMPLETION surface ----

func PgComplete(code: string, activeFile: string, line: int, column: int): object {
    files := PgEmptyFileArray(1)
    PgSetFile(files, 0, PgNewFile("Program.nl", code))
    completeMethod := PgCompilerType().GetMethod("Complete")
    if completeMethod == null {
        throw new InvalidOperationException("The production Complete entry point was not found.")
    }

    arguments := new object?[](4)
    SetPgObject(arguments, 0, files)
    SetPgObject(arguments, 1, activeFile)
    SetPgInt(arguments, 2, line)
    SetPgInt(arguments, 3, column)
    response := completeMethod.Invoke(PgNewCompiler(), arguments)
    if response == null {
        throw new InvalidOperationException("The production Complete entry point returned no result.")
    }

    return response
}

func PgItemCount(response: object): int {
    return PgListCount(response, "Items")
}

func PgLabelCensus(response: object): string {
    entries := PgList(response, "Items")
    if entries == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < entries.Count {
        entry := entries[index]
        if entry != null {
            census = census + PgText(entry, "Label") + ";"
        }

        index = index + 1
    }

    return census
}

func PgItem(response: object, index: int): string {
    entry := PgEntry(response, "Items", index)
    if entry == null {
        return "<no-such-item>"
    }

    return PgText(entry, "Label") + "|" + PgText(entry, "Kind") + "|" + PgText(entry, "Detail") + "|" + PgText(entry, "Documentation") + "|" + PgText(entry, "InsertText")
}

// The accessor census. A label that starts with `get_`, `set_`, `add_` or `remove_` is a
// compiler-generated CLR accessor, not a member any N# program can name.
func PgAccessorCount(response: object): int {
    entries := PgList(response, "Items")
    if entries == null {
        return -1
    }

    total := 0
    index := 0
    while index < entries.Count {
        entry := entries[index]
        if entry != null {
            label := PgText(entry, "Label")
            if label.StartsWith("get_") || label.StartsWith("set_") || label.StartsWith("add_") || label.StartsWith("remove_") {
                total = total + 1
            }
        }

        index = index + 1
    }

    return total
}

// ---- the RUN surface, which EXECUTES the program ----

func PgRunFiles(code: string, activeFile: string): object {
    files := PgEmptyFileArray(1)
    PgSetFile(files, 0, PgNewFile("Program.nl", code))
    runMethod := PgCompilerType().GetMethod("RunProject")
    if runMethod == null {
        throw new InvalidOperationException("The production RunProject entry point was not found.")
    }

    arguments := new object?[](2)
    SetPgObject(arguments, 0, files)
    SetPgObject(arguments, 1, activeFile)
    response := runMethod.Invoke(PgNewCompiler(), arguments)
    if response == null {
        throw new InvalidOperationException("The production RunProject entry point returned no result.")
    }

    return response
}

func PgExitCode(response: object): string {
    return PgText(response, "ExitCode")
}

func PgStdout(response: object): string {
    return PgText(response, "Stdout")
}

func PgStderr(response: object): string {
    return PgText(response, "Stderr")
}

func PgUnsupportedReason(response: object): string {
    return PgText(response, "UnsupportedReason")
}

// ---- the FORMAT surface ----

func PgFormat(source: string): object {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(string)
    formatMethod := PgCompilerType().GetMethod("Format", parameterTypes)
    if formatMethod == null {
        throw new InvalidOperationException("The production Format entry point was not found.")
    }

    arguments := new object?[](2)
    SetPgObject(arguments, 0, source)
    SetPgObject(arguments, 1, null)
    response := formatMethod.Invoke(PgNewCompiler(), arguments)
    if response == null {
        throw new InvalidOperationException("The production Format entry point returned no result.")
    }

    return response
}

func PgFormattedCode(response: object): string {
    return PgText(response, "FormattedCode")
}

func PgWarningCount(response: object): int {
    return PgListCount(response, "Warnings")
}

func PgWarning(response: object, index: int): string {
    entry := PgEntry(response, "Warnings", index)
    if entry == null {
        return "<no-such-warning>"
    }

    return entry.ToString() ?? "<null>"
}

// ======== THE MIGRATED CUT — 14 deleted methods ========

test "020 s38 playground tooling surfaces: Catalog StatesBrowserCapabilitiesAndExamples — 10 examples, 7 tutorial steps, 8 capability flags and 4 limitations (was PlaygroundCompilerTests.Catalog_StatesBrowserCapabilitiesAndExamples)" {
    catalog := PgCatalog()
    assert PgText(catalog, "SchemaVersion") == "2"
    assert PgText(catalog, "DefaultExampleId") == "01-hello-world"
    assert PgText(catalog, "EstimatedMinutes") == "15"
    assert PgCapabilities(catalog) == "True|True|True|True|True|True|True|False"
    assert PgLimitationCount(catalog) == 4
    assert PgLimitation(catalog, 0) == "The hosted playground runs compiler analysis, formatting, completions, hover, syntax highlighting, and a bounded execution subset entirely in the browser."
    assert PgLimitation(catalog, 1) == "The Run button supports tutorial-scale code: functions, print, simple control flow, records/classes, object initializers, string/numeric helpers, and selected match patterns."
    assert PgLimitation(catalog, 2) == "Full build, test execution, NuGet restore, filesystem workflows, async, LINQ, and unrestricted .NET interop require the local nlc toolchain."
    assert PgLimitation(catalog, 3) == "External assembly resolution is intentionally bounded for browser reliability."
    assert PgLimitation(catalog, 4) == "<no-such-limitation>"
    assert PgListCount(catalog, "Examples") == 10
    assert PgExampleIdCensus(catalog) == "01-hello-world;02-values-functions;03-types-visibility;04-unions-patterns;05-duck-typing;06-collections-linq;07-error-handling;08-async-interop;09-testing;10-tooling-loop;"
    assert PgExampleRow(catalog, 0) == "01-hello-world|Hello World|2|True|Hello, N#!\n"
    assert PgExampleConcepts(catalog, 0) == 4
    assert PgExampleRow(catalog, 1) == "02-values-functions|Values and Functions|2|True|Coffee: $27\n"
    assert PgExampleConcepts(catalog, 1) == 4
    assert PgExampleRow(catalog, 2) == "03-types-visibility|Types and Visibility|2|True|task #1: Try N# (done)\n"
    assert PgExampleConcepts(catalog, 2) == 5
    assert PgExampleRow(catalog, 3) == "04-unions-patterns|Unions and Match|2|True|Ada: 99\nMissing player #404\n"
    assert PgExampleConcepts(catalog, 3) == 4
    assert PgExampleRow(catalog, 4) == "05-duck-typing|Duck Typing|2|True|Welcome, Ada.\nWELCOME, GRACE!\n"
    assert PgExampleConcepts(catalog, 4) == 4
    assert PgExampleRow(catalog, 5) == "06-collections-linq|Collections and Iteration|1|True|Even sum: 12\nCount: 6\n"
    assert PgExampleConcepts(catalog, 5) == 4
    assert PgExampleRow(catalog, 6) == "07-error-handling|Go-Style Error Capture|1|True|<null>"
    assert PgExampleConcepts(catalog, 6) == 4
    assert PgExampleRow(catalog, 7) == "08-async-interop|Async and .NET Interop|1|False|<null>"
    assert PgExampleConcepts(catalog, 7) == 4
    assert PgExampleRow(catalog, 8) == "09-testing|Testing|1|True|5\n"
    assert PgExampleConcepts(catalog, 8) == 5
    assert PgExampleRow(catalog, 9) == "10-tooling-loop|The Tooling Loop|1|True|nlc check passed\n"
    assert PgExampleConcepts(catalog, 9) == 5
    assert PgExampleRow(catalog, 10) == "<no-such-example>"
    assert PgListCount(catalog, "Tutorial") == 7
}

test "020 s38 playground tooling surfaces: Catalog TutorialReferencesKnownExamplesAndExerciseValidation — every step whole, and every ExampleId is a real example (was PlaygroundCompilerTests.Catalog_TutorialReferencesKnownExamplesAndExerciseValidation)" {
    catalog := PgCatalog()
    assert PgText(catalog, "SchemaVersion") == "2"
    assert PgListCount(catalog, "Examples") == 10
    assert PgListCount(catalog, "Tutorial") == 7
    assert PgTutorialRow(catalog, 0) == "welcome|Welcome|info|01-hello-world|<null>"
    assert PgTutorialRow(catalog, 1) == "print-keyword|The print Keyword|info|01-hello-world|<null>"
    assert PgTutorialRow(catalog, 2) == "print-exercise|Print Exercise|exercise|01-hello-world|output/Hello, Playground!\n/Playground/The output matches the expected greeting."
    assert PgTutorialRow(catalog, 3) == "classes-records|Classes and Records|info|03-types-visibility|<null>"
    assert PgTutorialRow(catalog, 4) == "visibility|Visibility|info|03-types-visibility|<null>"
    assert PgTutorialRow(catalog, 5) == "class-exercise|Class Exercise|exercise|03-types-visibility|output/issue #1: Try N# (done)\n/issue/The formatter now uses the requested prefix."
    assert PgTutorialRow(catalog, 6) == "tooling-loop|The Tooling Loop|info|10-tooling-loop|<null>"
    assert PgTutorialRow(catalog, 7) == "<no-such-step>"
    assert PgExampleIdCensus(catalog) == "01-hello-world;02-values-functions;03-types-visibility;04-unions-patterns;05-duck-typing;06-collections-linq;07-error-handling;08-async-interop;09-testing;10-tooling-loop;"
}

test "020 s38 playground tooling surfaces: Catalog ExamplesAreCompilerClean — all ten shipped examples check clean, each with an EMPTY census (was PlaygroundCompilerTests.Catalog_ExamplesAreCompilerClean)" {
    assert PgExamples().Count == 10
    example0 := PgCheckExample(0)
    assert PgOk(example0) == "True"
    assert PgSchemaVersion(example0) == "2"
    assert PgFileName(example0) == "Program.nl"
    assert PgSummary(example0) == "0/0/0"
    assert PgCount(example0) == 0
    assert PgCensus(example0) == ""
    assert PgRow(example0, 0) == "<no-such-diagnostic>"
    example1 := PgCheckExample(1)
    assert PgOk(example1) == "True"
    assert PgSchemaVersion(example1) == "2"
    assert PgFileName(example1) == "Program.nl"
    assert PgSummary(example1) == "0/0/0"
    assert PgCount(example1) == 0
    assert PgCensus(example1) == ""
    assert PgRow(example1, 0) == "<no-such-diagnostic>"
    example2 := PgCheckExample(2)
    assert PgOk(example2) == "True"
    assert PgSchemaVersion(example2) == "2"
    assert PgFileName(example2) == "Program.nl"
    assert PgSummary(example2) == "0/0/0"
    assert PgCount(example2) == 0
    assert PgCensus(example2) == ""
    assert PgRow(example2, 0) == "<no-such-diagnostic>"
    example3 := PgCheckExample(3)
    assert PgOk(example3) == "True"
    assert PgSchemaVersion(example3) == "2"
    assert PgFileName(example3) == "Program.nl"
    assert PgSummary(example3) == "0/0/0"
    assert PgCount(example3) == 0
    assert PgCensus(example3) == ""
    assert PgRow(example3, 0) == "<no-such-diagnostic>"
    example4 := PgCheckExample(4)
    assert PgOk(example4) == "True"
    assert PgSchemaVersion(example4) == "2"
    assert PgFileName(example4) == "Program.nl"
    assert PgSummary(example4) == "0/0/0"
    assert PgCount(example4) == 0
    assert PgCensus(example4) == ""
    assert PgRow(example4, 0) == "<no-such-diagnostic>"
    example5 := PgCheckExample(5)
    assert PgOk(example5) == "True"
    assert PgSchemaVersion(example5) == "2"
    assert PgFileName(example5) == "Program.nl"
    assert PgSummary(example5) == "0/0/0"
    assert PgCount(example5) == 0
    assert PgCensus(example5) == ""
    assert PgRow(example5, 0) == "<no-such-diagnostic>"
    example6 := PgCheckExample(6)
    assert PgOk(example6) == "True"
    assert PgSchemaVersion(example6) == "2"
    assert PgFileName(example6) == "Program.nl"
    assert PgSummary(example6) == "0/0/0"
    assert PgCount(example6) == 0
    assert PgCensus(example6) == ""
    assert PgRow(example6, 0) == "<no-such-diagnostic>"
    example7 := PgCheckExample(7)
    assert PgOk(example7) == "True"
    assert PgSchemaVersion(example7) == "2"
    assert PgFileName(example7) == "Program.nl"
    assert PgSummary(example7) == "0/0/0"
    assert PgCount(example7) == 0
    assert PgCensus(example7) == ""
    assert PgRow(example7, 0) == "<no-such-diagnostic>"
    example8 := PgCheckExample(8)
    assert PgOk(example8) == "True"
    assert PgSchemaVersion(example8) == "2"
    assert PgFileName(example8) == "Program.nl"
    assert PgSummary(example8) == "0/0/0"
    assert PgCount(example8) == 0
    assert PgCensus(example8) == ""
    assert PgRow(example8, 0) == "<no-such-diagnostic>"
    example9 := PgCheckExample(9)
    assert PgOk(example9) == "True"
    assert PgSchemaVersion(example9) == "2"
    assert PgFileName(example9) == "Program.nl"
    assert PgSummary(example9) == "0/0/0"
    assert PgCount(example9) == 0
    assert PgCensus(example9) == ""
    assert PgRow(example9, 0) == "<no-such-diagnostic>"
}

test "020 s38 playground tooling surfaces: CheckProject AcceptsTutorialProgramAndTestsFiles — the first example WITH tests, census EMPTY, and PG900 is a code the shipping playground does not have (was PlaygroundCompilerTests.CheckProject_AcceptsTutorialProgramAndTestsFiles)" {
    firstWithTests := PgFirstExampleWithTests()
    assert firstWithTests == 0
    assert PgText(PgExample(firstWithTests), "Id") == "01-hello-world"
    assert PgText(PgExample(firstWithTests), "HasTests") == "True"
    response := PgCheckExample(firstWithTests)
    assert PgSchemaVersion(response) == "2"
    assert PgOk(response) == "True"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
}

test "020 s38 playground tooling surfaces: Format ValidProgram ReturnsFormattedCode — and the whole response, not only the text (was PlaygroundCompilerTests.Format_ValidProgram_ReturnsFormattedCode)" {
    source := "func main(){print 5}"
    response := PgFormat(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgFormattedCode(response) == "func main() {\n    print 5\n}\n"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgWarningCount(response) == 0
    assert PgWarning(response, 0) == "<no-such-warning>"
}

test "020 s38 playground tooling surfaces: RunProject MethodGroupUsedAsValue SkipsExecutionWithCompilerDiagnostic — exit 1, NL411@4:20+8; (was PlaygroundCompilerTests.RunProject_MethodGroupUsedAsValue_SkipsExecutionWithCompilerDiagnostic)" {
    source := "package Playground\n\nfunc main() {\n    value := \"asf\".ToString\n    print value\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgExitCode(response) == "1"
    assert PgStdout(response) == ""
    assert PgStderr(response) == "Run skipped because the program has compiler errors."
    assert PgUnsupportedReason(response) == "<null>"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL411@4:20+8;"
    assert PgRow(response, 0) == "NL411|error|Method 'ToString' must be called or passed to a delegate|Program.nl|4|20|8"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
}

test "020 s38 playground tooling surfaces: RunProject InvalidProgram SkipsExecution — exit 1, NL301@4:11+7; (was PlaygroundCompilerTests.RunProject_InvalidProgram_SkipsExecution)" {
    source := "package Playground\n\nfunc main() {\n    print missing\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgExitCode(response) == "1"
    assert PgStdout(response) == ""
    assert PgStderr(response) == "Run skipped because the program has compiler errors."
    assert PgUnsupportedReason(response) == "<null>"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL301@4:11+7;"
    assert PgRow(response, 0) == "NL301|error|Variable 'missing' not found|Program.nl|4|11|7"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
}

test "020 s38 playground tooling surfaces: RunProject UnsupportedConstruct ReturnsPG2xxDiagnostic — exit 2, PG204@1:1+1; (was PlaygroundCompilerTests.RunProject_UnsupportedConstruct_ReturnsPG2xxDiagnostic)" {
    source := "package Playground\n\nfunc main() {\n    while false {\n        print \"not reached\"\n    }\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgExitCode(response) == "2"
    assert PgStdout(response) == ""
    assert PgStderr(response) == "The browser runner does not yet support WhileStatement."
    assert PgUnsupportedReason(response) == "The browser runner does not yet support WhileStatement."
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "PG204@1:1+1;"
    assert PgRow(response, 0) == "PG204|error|The browser runner does not yet support WhileStatement.|Program.nl|1|1|1"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
}

test "020 s38 playground tooling surfaces: RunProject ValidProgram ProducesStdout — the shipped 01-hello-world example RUNS, and its stdout is its own declared ExpectedOutput (was PlaygroundCompilerTests.RunProject_ValidProgram_ProducesStdout)" {
    index := PgIndexOfExample("01-hello-world")
    assert index == 0
    assert PgText(PgExample(index), "ExpectedOutput") == "Hello, N#!\n"
    response := PgRunFiles(PgExampleCode(index), "Program.nl")
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgExitCode(response) == "0"
    assert PgStdout(response) == "Hello, N#!\n"
    assert PgStdout(response) == PgText(PgExample(index), "ExpectedOutput")
    assert PgStderr(response) == "<null>"
    assert PgUnsupportedReason(response) == "<null>"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
}

test "020 s38 playground tooling surfaces: Complete ReturnsKeywordAndSemanticCompletions — 1 site(s), 73 items, 0 of them compiler-generated accessors (was PlaygroundCompilerTests.Complete_ReturnsKeywordAndSemanticCompletions)" {
    source := "package Playground\n\nfunc Add(a: int, b: int): int {\n    return a + b\n}\n\nfunc main() {\n    value := Add(1, 2)\n    pri\n}"
    site := PgComplete(source, "Program.nl", 9, 7)
    assert PgOk(site) == "False"
    assert PgSchemaVersion(site) == "2"
    assert PgFileName(site) == "Program.nl"
    assert PgText(site, "Context") == "Identifier"
    assert PgText(site, "Receiver") == "<null>"
    assert PgText(site, "ReceiverType") == "<null>"
    assert PgSummary(site) == "2/0/0"
    assert PgCensus(site) == "NL001@8:5+5;NL301@9:5+3;"
    assert PgItemCount(site) == 73
    assert PgAccessorCount(site) == 0
    assert PgLabelCensus(site) == "as;assert;async;await;base;break;case;catch;class;continue;else;enum;false;finally;for;foreach;func;if;import;interface;is;lock;match;must;nameof;namespace;new;null;print;record;return;struct;switch;test;this;throw;true;try;typeof;union;when;while;yield;value;Add;main;bool;byte;char;decimal;double;float;int;long;object;sbyte;short;string;uint;ulong;ushort;void;abstract;const;init;override;partial;pub;readonly;required;sealed;static;virtual;"
    assert PgItem(site, 0) == "as|keyword||<null>|as"
    assert PgItem(site, 1) == "assert|keyword||<null>|assert"
    assert PgItem(site, 2) == "async|keyword||<null>|async"
    assert PgItem(site, 3) == "await|keyword||<null>|await"
    assert PgItem(site, 4) == "base|keyword||<null>|base"
    assert PgItem(site, 5) == "break|keyword||<null>|break"
    assert PgItem(site, 6) == "case|keyword||<null>|case"
    assert PgItem(site, 7) == "catch|keyword||<null>|catch"
    assert PgItem(site, 8) == "class|keyword||<null>|class"
    assert PgItem(site, 9) == "continue|keyword||<null>|continue"
    assert PgItem(site, 10) == "else|keyword||<null>|else"
    assert PgItem(site, 11) == "enum|keyword||<null>|enum"
    assert PgItem(site, 12) == "false|keyword||<null>|false"
    assert PgItem(site, 13) == "finally|keyword||<null>|finally"
    assert PgItem(site, 14) == "for|keyword||<null>|for"
    assert PgItem(site, 15) == "foreach|keyword||<null>|foreach"
    assert PgItem(site, 16) == "func|keyword||<null>|func"
    assert PgItem(site, 17) == "if|keyword||<null>|if"
    assert PgItem(site, 18) == "import|keyword||<null>|import"
    assert PgItem(site, 19) == "interface|keyword||<null>|interface"
    assert PgItem(site, 20) == "is|keyword||<null>|is"
    assert PgItem(site, 21) == "lock|keyword||<null>|lock"
    assert PgItem(site, 22) == "match|keyword||<null>|match"
    assert PgItem(site, 23) == "must|keyword||<null>|must"
    assert PgItem(site, 24) == "nameof|keyword||<null>|nameof"
    assert PgItem(site, 25) == "namespace|keyword||<null>|namespace"
    assert PgItem(site, 26) == "new|keyword||<null>|new"
    assert PgItem(site, 27) == "null|keyword||<null>|null"
    assert PgItem(site, 28) == "print|keyword||<null>|print"
    assert PgItem(site, 29) == "record|keyword||<null>|record"
    assert PgItem(site, 30) == "return|keyword||<null>|return"
    assert PgItem(site, 31) == "struct|keyword||<null>|struct"
    assert PgItem(site, 32) == "switch|keyword||<null>|switch"
    assert PgItem(site, 33) == "test|keyword||<null>|test"
    assert PgItem(site, 34) == "this|keyword||<null>|this"
    assert PgItem(site, 35) == "throw|keyword||<null>|throw"
    assert PgItem(site, 36) == "true|keyword||<null>|true"
    assert PgItem(site, 37) == "try|keyword||<null>|try"
    assert PgItem(site, 38) == "typeof|keyword||<null>|typeof"
    assert PgItem(site, 39) == "union|keyword||<null>|union"
    assert PgItem(site, 40) == "when|keyword||<null>|when"
    assert PgItem(site, 41) == "while|keyword||<null>|while"
    assert PgItem(site, 42) == "yield|keyword||<null>|yield"
    assert PgItem(site, 43) == "value|variable|int|<null>|value"
    assert PgItem(site, 44) == "Add|function|(a int, b int) int|<null>|Add"
    assert PgItem(site, 45) == "main|function|() void|<null>|main"
    assert PgItem(site, 46) == "bool|type||<null>|bool"
    assert PgItem(site, 47) == "byte|type||<null>|byte"
    assert PgItem(site, 48) == "char|type||<null>|char"
    assert PgItem(site, 49) == "decimal|type||<null>|decimal"
    assert PgItem(site, 50) == "double|type||<null>|double"
    assert PgItem(site, 51) == "float|type||<null>|float"
    assert PgItem(site, 52) == "int|type||<null>|int"
    assert PgItem(site, 53) == "long|type||<null>|long"
    assert PgItem(site, 54) == "object|type||<null>|object"
    assert PgItem(site, 55) == "sbyte|type||<null>|sbyte"
    assert PgItem(site, 56) == "short|type||<null>|short"
    assert PgItem(site, 57) == "string|type||<null>|string"
    assert PgItem(site, 58) == "uint|type||<null>|uint"
    assert PgItem(site, 59) == "ulong|type||<null>|ulong"
    assert PgItem(site, 60) == "ushort|type||<null>|ushort"
    assert PgItem(site, 61) == "void|type||<null>|void"
    assert PgItem(site, 62) == "abstract|modifier||<null>|abstract"
    assert PgItem(site, 63) == "const|modifier||<null>|const"
    assert PgItem(site, 64) == "init|modifier||<null>|init"
    assert PgItem(site, 65) == "override|modifier||<null>|override"
    assert PgItem(site, 66) == "partial|modifier||<null>|partial"
    assert PgItem(site, 67) == "pub|modifier||<null>|pub"
    assert PgItem(site, 68) == "readonly|modifier||<null>|readonly"
    assert PgItem(site, 69) == "required|modifier||<null>|required"
    assert PgItem(site, 70) == "sealed|modifier||<null>|sealed"
    assert PgItem(site, 71) == "static|modifier||<null>|static"
    assert PgItem(site, 72) == "virtual|modifier||<null>|virtual"
    assert PgItem(site, 73) == "<no-such-item>"
}

test "020 s38 playground tooling surfaces: Complete MemberAccess ReturnsSourceDefinedMethodsAndProperties — 2 site(s), 4 items, 0 of them compiler-generated accessors (was PlaygroundCompilerTests.Complete_MemberAccess_ReturnsSourceDefinedMethodsAndProperties)" {
    source := "package Playground\n\nrecord Todo {\n    Id: int\n    Title: string\n    Done: bool\n}\n\nclass TodoFormatter(prefix: string) {\n    func Format(todo: Todo): string {\n        return $\"{prefix} #{todo.Id}: {todo.Title}\"\n    }\n}\n\nfunc main() {\n    todo := new Todo { Id: 1, Title: \"Try N#\", Done: false }\n    formatter := new TodoFormatter(\"task\")\n    print formatter.Format(todo)\n    print todo.Id\n}"
    formatter := PgComplete(source, "Program.nl", 18, 20)
    assert PgOk(formatter) == "True"
    assert PgSchemaVersion(formatter) == "2"
    assert PgFileName(formatter) == "Program.nl"
    assert PgText(formatter, "Context") == "MemberAccess"
    assert PgText(formatter, "Receiver") == "formatter"
    assert PgText(formatter, "ReceiverType") == "TodoFormatter"
    assert PgSummary(formatter) == "0/0/0"
    assert PgCensus(formatter) == ""
    assert PgItemCount(formatter) == 1
    assert PgAccessorCount(formatter) == 0
    assert PgLabelCensus(formatter) == "Format;"
    assert PgItem(formatter, 0) == "Format|method|(todo Todo) string|<null>|Format"
    assert PgItem(formatter, 1) == "<no-such-item>"
    todo := PgComplete(source, "Program.nl", 11, 33)
    assert PgOk(todo) == "True"
    assert PgSchemaVersion(todo) == "2"
    assert PgFileName(todo) == "Program.nl"
    assert PgText(todo, "Context") == "MemberAccess"
    assert PgText(todo, "Receiver") == "todo"
    assert PgText(todo, "ReceiverType") == "Todo"
    assert PgSummary(todo) == "0/0/0"
    assert PgCensus(todo) == ""
    assert PgItemCount(todo) == 3
    assert PgAccessorCount(todo) == 0
    assert PgLabelCensus(todo) == "Done;Id;Title;"
    assert PgItem(todo, 0) == "Done|property|bool|<null>|Done"
    assert PgItem(todo, 1) == "Id|property|int|<null>|Id"
    assert PgItem(todo, 2) == "Title|property|string|<null>|Title"
    assert PgItem(todo, 3) == "<no-such-item>"
}

test "020 s38 playground tooling surfaces: Complete MemberAccess WorksAfterJustTypedDot — 1 site(s), 1 items, 0 of them compiler-generated accessors (was PlaygroundCompilerTests.Complete_MemberAccess_WorksAfterJustTypedDot)" {
    source := "package Playground\n\nclass TodoFormatter {\n    func Format(): string {\n        return \"ok\"\n    }\n}\n\nfunc main() {\n    formatter := new TodoFormatter()\n    formatter.\n}"
    site := PgComplete(source, "Program.nl", 11, 14)
    assert PgOk(site) == "False"
    assert PgSchemaVersion(site) == "2"
    assert PgFileName(site) == "Program.nl"
    assert PgText(site, "Context") == "MemberAccess"
    assert PgText(site, "Receiver") == "formatter"
    assert PgText(site, "ReceiverType") == "TodoFormatter"
    assert PgSummary(site) == "1/0/0"
    assert PgCensus(site) == "NL102@11:5+9;"
    assert PgItemCount(site) == 1
    assert PgAccessorCount(site) == 0
    assert PgLabelCensus(site) == "Format;"
    assert PgItem(site, 0) == "Format|method|() string|<null>|Format"
    assert PgItem(site, 1) == "<no-such-item>"
}

test "020 s38 playground tooling surfaces: Complete MemberAccess ReturnsStringMembersForInterpolatedStringLiteral — 1 site(s), 39 items, 0 of them compiler-generated accessors (was PlaygroundCompilerTests.Complete_MemberAccess_ReturnsStringMembersForInterpolatedStringLiteral)" {

    // THE DETAIL COLUMN NOW CARRIES THE OVERLOAD COUNT. The label census and the row count are
    // BYTE-IDENTICAL to what this contract pinned before — the playground has always deduplicated
    // by label — so the only thing that moved is what a collapsed row can say about itself:
    // `CompareTo` stands for two declarations and now says so, where before the eleven `Split`s
    // behind one row were simply lost. The rule moved to `CompletionEngineKernels` with this batch,
    // and the CLI and the editor were the two surfaces that had never had it.
    source := "$\"this is a string\"."
    site := PgComplete(source, "Program.nl", 1, 20)
    assert PgOk(site) == "False"
    assert PgSchemaVersion(site) == "2"
    assert PgFileName(site) == "Program.nl"
    assert PgText(site, "Context") == "MemberAccess"
    assert PgText(site, "Receiver") == "$\"this is a string\""
    assert PgText(site, "ReceiverType") == "System.String"
    assert PgSummary(site) == "5/0/0"
    assert PgCensus(site) == "NL101@1:1+19;NL101@1:20+1;NL903@1:20+7;NL306@1:21+7;NL903@1:21+7;"
    assert PgItemCount(site) == 39
    assert PgAccessorCount(site) == 0
    assert PgLabelCensus(site) == "Clone;CompareTo;Contains;CopyTo;EndsWith;EnumerateRunes;Equals;GetEnumerator;GetHashCode;GetPinnableReference;GetType;GetTypeCode;IndexOf;IndexOfAny;Insert;IsNormalized;LastIndexOf;LastIndexOfAny;Normalize;PadLeft;PadRight;Remove;Replace;ReplaceLineEndings;Split;StartsWith;Substring;ToCharArray;ToLower;ToLowerInvariant;ToString;ToUpper;ToUpperInvariant;Trim;TrimEnd;TrimStart;TryCopyTo;Chars;Length;"
    assert PgItem(site, 0) == "Clone|method|object|<null>|Clone"
    assert PgItem(site, 1) == "CompareTo|method|int (+1 overload)|<null>|CompareTo"
    assert PgItem(site, 2) == "Contains|method|bool (+3 overloads)|<null>|Contains"
    assert PgItem(site, 3) == "CopyTo|method|void (+1 overload)|<null>|CopyTo"
    assert PgItem(site, 4) == "EndsWith|method|bool (+3 overloads)|<null>|EndsWith"
    assert PgItem(site, 5) == "EnumerateRunes|method|StringRuneEnumerator|<null>|EnumerateRunes"
    assert PgItem(site, 6) == "Equals|method|bool (+2 overloads)|<null>|Equals"
    assert PgItem(site, 7) == "GetEnumerator|method|CharEnumerator|<null>|GetEnumerator"
    assert PgItem(site, 8) == "GetHashCode|method|int (+1 overload)|<null>|GetHashCode"
    assert PgItem(site, 9) == "GetPinnableReference|method|Char&|<null>|GetPinnableReference"
    assert PgItem(site, 10) == "GetType|method|Type|<null>|GetType"
    assert PgItem(site, 11) == "GetTypeCode|method|TypeCode|<null>|GetTypeCode"
    assert PgItem(site, 12) == "IndexOf|method|int (+9 overloads)|<null>|IndexOf"
    assert PgItem(site, 13) == "IndexOfAny|method|int (+2 overloads)|<null>|IndexOfAny"
    assert PgItem(site, 14) == "Insert|method|string|<null>|Insert"
    assert PgItem(site, 15) == "IsNormalized|method|bool (+1 overload)|<null>|IsNormalized"
    assert PgItem(site, 16) == "LastIndexOf|method|int (+8 overloads)|<null>|LastIndexOf"
    assert PgItem(site, 17) == "LastIndexOfAny|method|int (+2 overloads)|<null>|LastIndexOfAny"
    assert PgItem(site, 18) == "Normalize|method|string (+1 overload)|<null>|Normalize"
    assert PgItem(site, 19) == "PadLeft|method|string (+1 overload)|<null>|PadLeft"
    assert PgItem(site, 20) == "PadRight|method|string (+1 overload)|<null>|PadRight"
    assert PgItem(site, 21) == "Remove|method|string (+1 overload)|<null>|Remove"
    assert PgItem(site, 22) == "Replace|method|string (+3 overloads)|<null>|Replace"
    assert PgItem(site, 23) == "ReplaceLineEndings|method|string (+1 overload)|<null>|ReplaceLineEndings"
    assert PgItem(site, 24) == "Split|method|String[] (+10 overloads)|<null>|Split"
    assert PgItem(site, 25) == "StartsWith|method|bool (+3 overloads)|<null>|StartsWith"
    assert PgItem(site, 26) == "Substring|method|string (+1 overload)|<null>|Substring"
    assert PgItem(site, 27) == "ToCharArray|method|Char[] (+1 overload)|<null>|ToCharArray"
    assert PgItem(site, 28) == "ToLower|method|string (+1 overload)|<null>|ToLower"
    assert PgItem(site, 29) == "ToLowerInvariant|method|string|<null>|ToLowerInvariant"
    assert PgItem(site, 30) == "ToString|method|string (+1 overload)|<null>|ToString"
    assert PgItem(site, 31) == "ToUpper|method|string (+1 overload)|<null>|ToUpper"
    assert PgItem(site, 32) == "ToUpperInvariant|method|string|<null>|ToUpperInvariant"
    assert PgItem(site, 33) == "Trim|method|string (+3 overloads)|<null>|Trim"
    assert PgItem(site, 34) == "TrimEnd|method|string (+3 overloads)|<null>|TrimEnd"
    assert PgItem(site, 35) == "TrimStart|method|string (+3 overloads)|<null>|TrimStart"
    assert PgItem(site, 36) == "TryCopyTo|method|bool|<null>|TryCopyTo"
    assert PgItem(site, 37) == "Chars|property|Char|<null>|Chars"
    assert PgItem(site, 38) == "Length|property|int|<null>|Length"
    assert PgItem(site, 39) == "<no-such-item>"
}

test "020 s38 playground tooling surfaces: Complete MemberAccess ReturnsClrStaticInstanceAndChainedMembers — 4 site(s), 171 items, 0 of them compiler-generated accessors (was PlaygroundCompilerTests.Complete_MemberAccess_ReturnsClrStaticInstanceAndChainedMembers)" {

    // THE DETAIL COLUMN NOW CARRIES THE OVERLOAD COUNT. The label census and the row count are
    // BYTE-IDENTICAL to what this contract pinned before — the playground has always deduplicated
    // by label — so the only thing that moved is what a collapsed row can say about itself:
    // `CompareTo` stands for two declarations and now says so, where before the eleven `Split`s
    // behind one row were simply lost. The rule moved to `CompletionEngineKernels` with this batch,
    // and the CLI and the editor were the two surfaces that had never had it.
    source := "import System\n\npackage Playground\n\nfunc main() {\n    message := \"hello\"\n    Console.WriteLine(message)\n    print Math.Max(1, 2)\n    print message.ToUpper().ToLower()\n}"
    message := PgComplete(source, "Program.nl", 9, 18)
    assert PgOk(message) == "True"
    assert PgSchemaVersion(message) == "2"
    assert PgFileName(message) == "Program.nl"
    assert PgText(message, "Context") == "MemberAccess"
    assert PgText(message, "Receiver") == "message"
    assert PgText(message, "ReceiverType") == "System.String"
    assert PgSummary(message) == "0/0/0"
    assert PgCensus(message) == ""
    assert PgItemCount(message) == 39
    assert PgAccessorCount(message) == 0
    assert PgLabelCensus(message) == "Clone;CompareTo;Contains;CopyTo;EndsWith;EnumerateRunes;Equals;GetEnumerator;GetHashCode;GetPinnableReference;GetType;GetTypeCode;IndexOf;IndexOfAny;Insert;IsNormalized;LastIndexOf;LastIndexOfAny;Normalize;PadLeft;PadRight;Remove;Replace;ReplaceLineEndings;Split;StartsWith;Substring;ToCharArray;ToLower;ToLowerInvariant;ToString;ToUpper;ToUpperInvariant;Trim;TrimEnd;TrimStart;TryCopyTo;Chars;Length;"
    assert PgItem(message, 0) == "Clone|method|object|<null>|Clone"
    assert PgItem(message, 1) == "CompareTo|method|int (+1 overload)|<null>|CompareTo"
    assert PgItem(message, 2) == "Contains|method|bool (+3 overloads)|<null>|Contains"
    assert PgItem(message, 3) == "CopyTo|method|void (+1 overload)|<null>|CopyTo"
    assert PgItem(message, 4) == "EndsWith|method|bool (+3 overloads)|<null>|EndsWith"
    assert PgItem(message, 5) == "EnumerateRunes|method|StringRuneEnumerator|<null>|EnumerateRunes"
    assert PgItem(message, 6) == "Equals|method|bool (+2 overloads)|<null>|Equals"
    assert PgItem(message, 7) == "GetEnumerator|method|CharEnumerator|<null>|GetEnumerator"
    assert PgItem(message, 8) == "GetHashCode|method|int (+1 overload)|<null>|GetHashCode"
    assert PgItem(message, 9) == "GetPinnableReference|method|Char&|<null>|GetPinnableReference"
    assert PgItem(message, 10) == "GetType|method|Type|<null>|GetType"
    assert PgItem(message, 11) == "GetTypeCode|method|TypeCode|<null>|GetTypeCode"
    assert PgItem(message, 12) == "IndexOf|method|int (+9 overloads)|<null>|IndexOf"
    assert PgItem(message, 13) == "IndexOfAny|method|int (+2 overloads)|<null>|IndexOfAny"
    assert PgItem(message, 14) == "Insert|method|string|<null>|Insert"
    assert PgItem(message, 15) == "IsNormalized|method|bool (+1 overload)|<null>|IsNormalized"
    assert PgItem(message, 16) == "LastIndexOf|method|int (+8 overloads)|<null>|LastIndexOf"
    assert PgItem(message, 17) == "LastIndexOfAny|method|int (+2 overloads)|<null>|LastIndexOfAny"
    assert PgItem(message, 18) == "Normalize|method|string (+1 overload)|<null>|Normalize"
    assert PgItem(message, 19) == "PadLeft|method|string (+1 overload)|<null>|PadLeft"
    assert PgItem(message, 20) == "PadRight|method|string (+1 overload)|<null>|PadRight"
    assert PgItem(message, 21) == "Remove|method|string (+1 overload)|<null>|Remove"
    assert PgItem(message, 22) == "Replace|method|string (+3 overloads)|<null>|Replace"
    assert PgItem(message, 23) == "ReplaceLineEndings|method|string (+1 overload)|<null>|ReplaceLineEndings"
    assert PgItem(message, 24) == "Split|method|String[] (+10 overloads)|<null>|Split"
    assert PgItem(message, 25) == "StartsWith|method|bool (+3 overloads)|<null>|StartsWith"
    assert PgItem(message, 26) == "Substring|method|string (+1 overload)|<null>|Substring"
    assert PgItem(message, 27) == "ToCharArray|method|Char[] (+1 overload)|<null>|ToCharArray"
    assert PgItem(message, 28) == "ToLower|method|string (+1 overload)|<null>|ToLower"
    assert PgItem(message, 29) == "ToLowerInvariant|method|string|<null>|ToLowerInvariant"
    assert PgItem(message, 30) == "ToString|method|string (+1 overload)|<null>|ToString"
    assert PgItem(message, 31) == "ToUpper|method|string (+1 overload)|<null>|ToUpper"
    assert PgItem(message, 32) == "ToUpperInvariant|method|string|<null>|ToUpperInvariant"
    assert PgItem(message, 33) == "Trim|method|string (+3 overloads)|<null>|Trim"
    assert PgItem(message, 34) == "TrimEnd|method|string (+3 overloads)|<null>|TrimEnd"
    assert PgItem(message, 35) == "TrimStart|method|string (+3 overloads)|<null>|TrimStart"
    assert PgItem(message, 36) == "TryCopyTo|method|bool|<null>|TryCopyTo"
    assert PgItem(message, 37) == "Chars|property|Char|<null>|Chars"
    assert PgItem(message, 38) == "Length|property|int|<null>|Length"
    assert PgItem(message, 39) == "<no-such-item>"
    console := PgComplete(source, "Program.nl", 7, 12)
    assert PgOk(console) == "True"
    assert PgSchemaVersion(console) == "2"
    assert PgFileName(console) == "Program.nl"
    assert PgText(console, "Context") == "MemberAccess"
    assert PgText(console, "Receiver") == "Console"
    assert PgText(console, "ReceiverType") == "System.Console"
    assert PgSummary(console) == "0/0/0"
    assert PgCensus(console) == ""
    assert PgItemCount(console) == 47
    assert PgAccessorCount(console) == 0
    assert PgLabelCensus(console) == "Beep;Clear;GetCursorPosition;MoveBufferArea;OpenStandardError;OpenStandardInput;OpenStandardOutput;Read;ReadKey;ReadLine;ResetColor;SetBufferSize;SetCursorPosition;SetError;SetIn;SetOut;SetWindowPosition;SetWindowSize;Write;WriteLine;BackgroundColor;BufferHeight;BufferWidth;CapsLock;CursorLeft;CursorSize;CursorTop;CursorVisible;Error;ForegroundColor;In;InputEncoding;IsErrorRedirected;IsInputRedirected;IsOutputRedirected;KeyAvailable;LargestWindowHeight;LargestWindowWidth;NumberLock;Out;OutputEncoding;Title;TreatControlCAsInput;WindowHeight;WindowLeft;WindowTop;WindowWidth;"
    assert PgItem(console, 0) == "Beep|method|void (+1 overload)|<null>|Beep"
    assert PgItem(console, 1) == "Clear|method|void|<null>|Clear"
    assert PgItem(console, 2) == "GetCursorPosition|method|ValueTuple<int, int>|<null>|GetCursorPosition"
    assert PgItem(console, 3) == "MoveBufferArea|method|void (+1 overload)|<null>|MoveBufferArea"
    assert PgItem(console, 4) == "OpenStandardError|method|Stream (+1 overload)|<null>|OpenStandardError"
    assert PgItem(console, 5) == "OpenStandardInput|method|Stream (+1 overload)|<null>|OpenStandardInput"
    assert PgItem(console, 6) == "OpenStandardOutput|method|Stream (+1 overload)|<null>|OpenStandardOutput"
    assert PgItem(console, 7) == "Read|method|int|<null>|Read"
    assert PgItem(console, 8) == "ReadKey|method|ConsoleKeyInfo (+1 overload)|<null>|ReadKey"
    assert PgItem(console, 9) == "ReadLine|method|string|<null>|ReadLine"
    assert PgItem(console, 10) == "ResetColor|method|void|<null>|ResetColor"
    assert PgItem(console, 11) == "SetBufferSize|method|void|<null>|SetBufferSize"
    assert PgItem(console, 12) == "SetCursorPosition|method|void|<null>|SetCursorPosition"
    assert PgItem(console, 13) == "SetError|method|void|<null>|SetError"
    assert PgItem(console, 14) == "SetIn|method|void|<null>|SetIn"
    assert PgItem(console, 15) == "SetOut|method|void|<null>|SetOut"
    assert PgItem(console, 16) == "SetWindowPosition|method|void|<null>|SetWindowPosition"
    assert PgItem(console, 17) == "SetWindowSize|method|void|<null>|SetWindowSize"
    assert PgItem(console, 18) == "Write|method|void (+18 overloads)|<null>|Write"
    assert PgItem(console, 19) == "WriteLine|method|void (+19 overloads)|<null>|WriteLine"
    assert PgItem(console, 20) == "BackgroundColor|property|ConsoleColor|<null>|BackgroundColor"
    assert PgItem(console, 21) == "BufferHeight|property|int|<null>|BufferHeight"
    assert PgItem(console, 22) == "BufferWidth|property|int|<null>|BufferWidth"
    assert PgItem(console, 23) == "CapsLock|property|bool|<null>|CapsLock"
    assert PgItem(console, 24) == "CursorLeft|property|int|<null>|CursorLeft"
    assert PgItem(console, 25) == "CursorSize|property|int|<null>|CursorSize"
    assert PgItem(console, 26) == "CursorTop|property|int|<null>|CursorTop"
    assert PgItem(console, 27) == "CursorVisible|property|bool|<null>|CursorVisible"
    assert PgItem(console, 28) == "Error|property|TextWriter|<null>|Error"
    assert PgItem(console, 29) == "ForegroundColor|property|ConsoleColor|<null>|ForegroundColor"
    assert PgItem(console, 30) == "In|property|TextReader|<null>|In"
    assert PgItem(console, 31) == "InputEncoding|property|Encoding|<null>|InputEncoding"
    assert PgItem(console, 32) == "IsErrorRedirected|property|bool|<null>|IsErrorRedirected"
    assert PgItem(console, 33) == "IsInputRedirected|property|bool|<null>|IsInputRedirected"
    assert PgItem(console, 34) == "IsOutputRedirected|property|bool|<null>|IsOutputRedirected"
    assert PgItem(console, 35) == "KeyAvailable|property|bool|<null>|KeyAvailable"
    assert PgItem(console, 36) == "LargestWindowHeight|property|int|<null>|LargestWindowHeight"
    assert PgItem(console, 37) == "LargestWindowWidth|property|int|<null>|LargestWindowWidth"
    assert PgItem(console, 38) == "NumberLock|property|bool|<null>|NumberLock"
    assert PgItem(console, 39) == "Out|property|TextWriter|<null>|Out"
    assert PgItem(console, 40) == "OutputEncoding|property|Encoding|<null>|OutputEncoding"
    assert PgItem(console, 41) == "Title|property|string|<null>|Title"
    assert PgItem(console, 42) == "TreatControlCAsInput|property|bool|<null>|TreatControlCAsInput"
    assert PgItem(console, 43) == "WindowHeight|property|int|<null>|WindowHeight"
    assert PgItem(console, 44) == "WindowLeft|property|int|<null>|WindowLeft"
    assert PgItem(console, 45) == "WindowTop|property|int|<null>|WindowTop"
    assert PgItem(console, 46) == "WindowWidth|property|int|<null>|WindowWidth"
    assert PgItem(console, 47) == "<no-such-item>"
    math := PgComplete(source, "Program.nl", 8, 15)
    assert PgOk(math) == "True"
    assert PgSchemaVersion(math) == "2"
    assert PgFileName(math) == "Program.nl"
    assert PgText(math, "Context") == "MemberAccess"
    assert PgText(math, "Receiver") == "Math"
    assert PgText(math, "ReceiverType") == "System.Math"
    assert PgSummary(math) == "0/0/0"
    assert PgCensus(math) == ""
    assert PgItemCount(math) == 46
    assert PgAccessorCount(math) == 0
    assert PgLabelCensus(math) == "Abs;Acos;Acosh;Asin;Asinh;Atan;Atan2;Atanh;BigMul;BitDecrement;BitIncrement;Cbrt;Ceiling;Clamp;CopySign;Cos;Cosh;DivRem;Exp;Floor;FusedMultiplyAdd;IEEERemainder;ILogB;Log;Log10;Log2;Max;MaxMagnitude;Min;MinMagnitude;Pow;ReciprocalEstimate;ReciprocalSqrtEstimate;Round;ScaleB;Sign;Sin;SinCos;Sinh;Sqrt;Tan;Tanh;Truncate;E;PI;Tau;"
    assert PgItem(math, 0) == "Abs|method|Int16 (+7 overloads)|<null>|Abs"
    assert PgItem(math, 1) == "Acos|method|double|<null>|Acos"
    assert PgItem(math, 2) == "Acosh|method|double|<null>|Acosh"
    assert PgItem(math, 3) == "Asin|method|double|<null>|Asin"
    assert PgItem(math, 4) == "Asinh|method|double|<null>|Asinh"
    assert PgItem(math, 5) == "Atan|method|double|<null>|Atan"
    assert PgItem(math, 6) == "Atan2|method|double|<null>|Atan2"
    assert PgItem(math, 7) == "Atanh|method|double|<null>|Atanh"
    assert PgItem(math, 8) == "BigMul|method|UInt64 (+5 overloads)|<null>|BigMul"
    assert PgItem(math, 9) == "BitDecrement|method|double|<null>|BitDecrement"
    assert PgItem(math, 10) == "BitIncrement|method|double|<null>|BitIncrement"
    assert PgItem(math, 11) == "Cbrt|method|double|<null>|Cbrt"
    assert PgItem(math, 12) == "Ceiling|method|double (+1 overload)|<null>|Ceiling"
    assert PgItem(math, 13) == "Clamp|method|Byte (+12 overloads)|<null>|Clamp"
    assert PgItem(math, 14) == "CopySign|method|double|<null>|CopySign"
    assert PgItem(math, 15) == "Cos|method|double|<null>|Cos"
    assert PgItem(math, 16) == "Cosh|method|double|<null>|Cosh"
    assert PgItem(math, 17) == "DivRem|method|int (+11 overloads)|<null>|DivRem"
    assert PgItem(math, 18) == "Exp|method|double|<null>|Exp"
    assert PgItem(math, 19) == "Floor|method|double (+1 overload)|<null>|Floor"
    assert PgItem(math, 20) == "FusedMultiplyAdd|method|double|<null>|FusedMultiplyAdd"
    assert PgItem(math, 21) == "IEEERemainder|method|double|<null>|IEEERemainder"
    assert PgItem(math, 22) == "ILogB|method|int|<null>|ILogB"
    assert PgItem(math, 23) == "Log|method|double (+1 overload)|<null>|Log"
    assert PgItem(math, 24) == "Log10|method|double|<null>|Log10"
    assert PgItem(math, 25) == "Log2|method|double|<null>|Log2"
    assert PgItem(math, 26) == "Max|method|Byte (+12 overloads)|<null>|Max"
    assert PgItem(math, 27) == "MaxMagnitude|method|double|<null>|MaxMagnitude"
    assert PgItem(math, 28) == "Min|method|Byte (+12 overloads)|<null>|Min"
    assert PgItem(math, 29) == "MinMagnitude|method|double|<null>|MinMagnitude"
    assert PgItem(math, 30) == "Pow|method|double|<null>|Pow"
    assert PgItem(math, 31) == "ReciprocalEstimate|method|double|<null>|ReciprocalEstimate"
    assert PgItem(math, 32) == "ReciprocalSqrtEstimate|method|double|<null>|ReciprocalSqrtEstimate"
    assert PgItem(math, 33) == "Round|method|Decimal (+7 overloads)|<null>|Round"
    assert PgItem(math, 34) == "ScaleB|method|double|<null>|ScaleB"
    assert PgItem(math, 35) == "Sign|method|int (+7 overloads)|<null>|Sign"
    assert PgItem(math, 36) == "Sin|method|double|<null>|Sin"
    assert PgItem(math, 37) == "SinCos|method|ValueTuple<double, double>|<null>|SinCos"
    assert PgItem(math, 38) == "Sinh|method|double|<null>|Sinh"
    assert PgItem(math, 39) == "Sqrt|method|double|<null>|Sqrt"
    assert PgItem(math, 40) == "Tan|method|double|<null>|Tan"
    assert PgItem(math, 41) == "Tanh|method|double|<null>|Tanh"
    assert PgItem(math, 42) == "Truncate|method|Decimal (+1 overload)|<null>|Truncate"
    assert PgItem(math, 43) == "E|field|double|<null>|E"
    assert PgItem(math, 44) == "PI|field|double|<null>|PI"
    assert PgItem(math, 45) == "Tau|field|double|<null>|Tau"
    assert PgItem(math, 46) == "<no-such-item>"
    chained := PgComplete(source, "Program.nl", 9, 28)
    assert PgOk(chained) == "True"
    assert PgSchemaVersion(chained) == "2"
    assert PgFileName(chained) == "Program.nl"
    assert PgText(chained, "Context") == "MemberAccess"
    assert PgText(chained, "Receiver") == "message.ToUpper()"
    assert PgText(chained, "ReceiverType") == "System.String"
    assert PgSummary(chained) == "0/0/0"
    assert PgCensus(chained) == ""
    assert PgItemCount(chained) == 39
    assert PgAccessorCount(chained) == 0
    assert PgLabelCensus(chained) == "Clone;CompareTo;Contains;CopyTo;EndsWith;EnumerateRunes;Equals;GetEnumerator;GetHashCode;GetPinnableReference;GetType;GetTypeCode;IndexOf;IndexOfAny;Insert;IsNormalized;LastIndexOf;LastIndexOfAny;Normalize;PadLeft;PadRight;Remove;Replace;ReplaceLineEndings;Split;StartsWith;Substring;ToCharArray;ToLower;ToLowerInvariant;ToString;ToUpper;ToUpperInvariant;Trim;TrimEnd;TrimStart;TryCopyTo;Chars;Length;"
    assert PgItem(chained, 0) == "Clone|method|object|<null>|Clone"
    assert PgItem(chained, 1) == "CompareTo|method|int (+1 overload)|<null>|CompareTo"
    assert PgItem(chained, 2) == "Contains|method|bool (+3 overloads)|<null>|Contains"
    assert PgItem(chained, 3) == "CopyTo|method|void (+1 overload)|<null>|CopyTo"
    assert PgItem(chained, 4) == "EndsWith|method|bool (+3 overloads)|<null>|EndsWith"
    assert PgItem(chained, 5) == "EnumerateRunes|method|StringRuneEnumerator|<null>|EnumerateRunes"
    assert PgItem(chained, 6) == "Equals|method|bool (+2 overloads)|<null>|Equals"
    assert PgItem(chained, 7) == "GetEnumerator|method|CharEnumerator|<null>|GetEnumerator"
    assert PgItem(chained, 8) == "GetHashCode|method|int (+1 overload)|<null>|GetHashCode"
    assert PgItem(chained, 9) == "GetPinnableReference|method|Char&|<null>|GetPinnableReference"
    assert PgItem(chained, 10) == "GetType|method|Type|<null>|GetType"
    assert PgItem(chained, 11) == "GetTypeCode|method|TypeCode|<null>|GetTypeCode"
    assert PgItem(chained, 12) == "IndexOf|method|int (+9 overloads)|<null>|IndexOf"
    assert PgItem(chained, 13) == "IndexOfAny|method|int (+2 overloads)|<null>|IndexOfAny"
    assert PgItem(chained, 14) == "Insert|method|string|<null>|Insert"
    assert PgItem(chained, 15) == "IsNormalized|method|bool (+1 overload)|<null>|IsNormalized"
    assert PgItem(chained, 16) == "LastIndexOf|method|int (+8 overloads)|<null>|LastIndexOf"
    assert PgItem(chained, 17) == "LastIndexOfAny|method|int (+2 overloads)|<null>|LastIndexOfAny"
    assert PgItem(chained, 18) == "Normalize|method|string (+1 overload)|<null>|Normalize"
    assert PgItem(chained, 19) == "PadLeft|method|string (+1 overload)|<null>|PadLeft"
    assert PgItem(chained, 20) == "PadRight|method|string (+1 overload)|<null>|PadRight"
    assert PgItem(chained, 21) == "Remove|method|string (+1 overload)|<null>|Remove"
    assert PgItem(chained, 22) == "Replace|method|string (+3 overloads)|<null>|Replace"
    assert PgItem(chained, 23) == "ReplaceLineEndings|method|string (+1 overload)|<null>|ReplaceLineEndings"
    assert PgItem(chained, 24) == "Split|method|String[] (+10 overloads)|<null>|Split"
    assert PgItem(chained, 25) == "StartsWith|method|bool (+3 overloads)|<null>|StartsWith"
    assert PgItem(chained, 26) == "Substring|method|string (+1 overload)|<null>|Substring"
    assert PgItem(chained, 27) == "ToCharArray|method|Char[] (+1 overload)|<null>|ToCharArray"
    assert PgItem(chained, 28) == "ToLower|method|string (+1 overload)|<null>|ToLower"
    assert PgItem(chained, 29) == "ToLowerInvariant|method|string|<null>|ToLowerInvariant"
    assert PgItem(chained, 30) == "ToString|method|string (+1 overload)|<null>|ToString"
    assert PgItem(chained, 31) == "ToUpper|method|string (+1 overload)|<null>|ToUpper"
    assert PgItem(chained, 32) == "ToUpperInvariant|method|string|<null>|ToUpperInvariant"
    assert PgItem(chained, 33) == "Trim|method|string (+3 overloads)|<null>|Trim"
    assert PgItem(chained, 34) == "TrimEnd|method|string (+3 overloads)|<null>|TrimEnd"
    assert PgItem(chained, 35) == "TrimStart|method|string (+3 overloads)|<null>|TrimStart"
    assert PgItem(chained, 36) == "TryCopyTo|method|bool|<null>|TryCopyTo"
    assert PgItem(chained, 37) == "Chars|property|Char|<null>|Chars"
    assert PgItem(chained, 38) == "Length|property|int|<null>|Length"
    assert PgItem(chained, 39) == "<no-such-item>"
}

// ======== SLICE 38's TOOLING CONTROLS — FOUR MINIMAL NEGATIVES AND ONE STATICS PIN ========
//
// Each is a contract the deleted file never had.

test "020 s38 playground tooling surfaces: T0 — the production statics, read through the dll route (T0, a control the C# never had)" {
    assert PgStaticText(PgCompilerType(), "SchemaVersion") == "2"
    assert PgStaticText(PgCompilerType(), "MaxSourceLength") == "65536"
    assert PgStaticText(PgCompilerType(), "MaxProjectSourceLength") == "131072"
    assert PgStaticText(PgExamplesType(), "DefaultId") == "01-hello-world"
    assert PgExamples().Count == 10
    assert PgText(PgExample(0), "Id") == "01-hello-world"
    assert PgText(PgExample(0), "HasTests") == "True"
    assert PgText(PgExample(0), "ExpectedOutput") == "Hello, N#!\n"
    assert PgText(PgExample(1), "Id") == "02-values-functions"
    assert PgText(PgExample(1), "HasTests") == "True"
    assert PgText(PgExample(1), "ExpectedOutput") == "Coffee: $27\n"
    assert PgText(PgExample(2), "Id") == "03-types-visibility"
    assert PgText(PgExample(2), "HasTests") == "True"
    assert PgText(PgExample(2), "ExpectedOutput") == "task #1: Try N# (done)\n"
    assert PgText(PgExample(3), "Id") == "04-unions-patterns"
    assert PgText(PgExample(3), "HasTests") == "True"
    assert PgText(PgExample(3), "ExpectedOutput") == "Ada: 99\nMissing player #404\n"
    assert PgText(PgExample(4), "Id") == "05-duck-typing"
    assert PgText(PgExample(4), "HasTests") == "True"
    assert PgText(PgExample(4), "ExpectedOutput") == "Welcome, Ada.\nWELCOME, GRACE!\n"
    assert PgText(PgExample(5), "Id") == "06-collections-linq"
    assert PgText(PgExample(5), "HasTests") == "True"
    assert PgText(PgExample(5), "ExpectedOutput") == "Even sum: 12\nCount: 6\n"
    assert PgText(PgExample(6), "Id") == "07-error-handling"
    assert PgText(PgExample(6), "HasTests") == "True"
    assert PgText(PgExample(6), "ExpectedOutput") == "<null>"
    assert PgText(PgExample(7), "Id") == "08-async-interop"
    assert PgText(PgExample(7), "HasTests") == "False"
    assert PgText(PgExample(7), "ExpectedOutput") == "<null>"
    assert PgText(PgExample(8), "Id") == "09-testing"
    assert PgText(PgExample(8), "HasTests") == "True"
    assert PgText(PgExample(8), "ExpectedOutput") == "5\n"
    assert PgText(PgExample(9), "Id") == "10-tooling-loop"
    assert PgText(PgExample(9), "HasTests") == "True"
    assert PgText(PgExample(9), "ExpectedOutput") == "nlc check passed\n"
    assert PgExampleTestsOrEmpty(7) == ""
    assert PgIndexOfExample("no-such-example") == -1
}

test "020 s38 playground tooling surfaces: T1 — Complete MemberAccess ReturnsSourceDefinedMethodsAndProperties, with Format renamed to Describe — the label MOVES (T1, a control the C# never had)" {
    source := "package Playground\n\nrecord Todo {\n    Id: int\n    Title: string\n    Done: bool\n}\n\nclass TodoFormatter(prefix: string) {\n    func Describe(todo: Todo): string {\n        return $\"{prefix} #{todo.Id}: {todo.Title}\"\n    }\n}\n\nfunc main() {\n    todo := new Todo { Id: 1, Title: \"Try N#\", Done: false }\n    formatter := new TodoFormatter(\"task\")\n    print formatter.Format(todo)\n    print todo.Id\n}"
    response := PgComplete(source, "Program.nl", 18, 20)
    assert PgText(response, "Context") == "MemberAccess"
    assert PgText(response, "ReceiverType") == "TodoFormatter"
    assert PgItemCount(response) == 1
    assert PgLabelCensus(response) == "Describe;"
    assert PgItem(response, 0) == "Describe|method|(todo Todo) string|<null>|Describe"
}

test "020 s38 playground tooling surfaces: T1b — the SAME todo. completion at line 19, which is where the deleted methods name pointed and NOT where its first-match helper landed (T1b, a control the C# never had)" {
    source := "package Playground\n\nrecord Todo {\n    Id: int\n    Title: string\n    Done: bool\n}\n\nclass TodoFormatter(prefix: string) {\n    func Format(todo: Todo): string {\n        return $\"{prefix} #{todo.Id}: {todo.Title}\"\n    }\n}\n\nfunc main() {\n    todo := new Todo { Id: 1, Title: \"Try N#\", Done: false }\n    formatter := new TodoFormatter(\"task\")\n    print formatter.Format(todo)\n    print todo.Id\n}"
    response := PgComplete(source, "Program.nl", 19, 15)
    assert PgText(response, "Context") == "MemberAccess"
    assert PgText(response, "ReceiverType") == "Todo"
    assert PgItemCount(response) == 3
    assert PgLabelCensus(response) == "Done;Id;Title;"
    assert PgItem(response, 0) == "Done|property|bool|<null>|Done"
    assert PgItem(response, 1) == "Id|property|int|<null>|Id"
    assert PgItem(response, 2) == "Title|property|string|<null>|Title"
}

test "020 s38 playground tooling surfaces: T2 — RunProject UnsupportedConstruct with the while loop removed — the SAME program RUNS and prints (T2, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    print \"reached\"\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "True"
    assert PgExitCode(response) == "0"
    assert PgStdout(response) == "reached\n"
    assert PgStderr(response) == "<null>"
    assert PgUnsupportedReason(response) == "<null>"
    assert PgCensus(response) == ""
}

test "020 s38 playground tooling surfaces: T3 — Format over a source WITH a compiler error — the text comes back unchanged and the skip is stated as a warning (T3, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    print totla\n}"
    response := PgFormat(source)
    assert PgOk(response) == "False"
    assert PgFormattedCode(response) == source
    assert PgSummary(response) == "1/0/0"
    assert PgCensus(response) == "NL301@4:11+5;"
    assert PgWarningCount(response) == 1
    assert PgWarning(response, 0) == "Formatting is skipped while the source has compiler errors."
    assert PgWarning(response, 1) == "<no-such-warning>"
}

// ---- CHIP: PLAYGROUND vs `nlc run` DIVERGENCES (021 slice 11 measured seven; five are pinned here) ----
//
// 021 slice 11 measured fourteen analysis-clean programs on BOTH sides and found SEVEN that answer
// differently. They were pinned AS MEASURED, not endorsed. Five of the seven are playground defects
// and are fixed in `PlaygroundRunFacts`; each block below runs the SAME source the divergence was
// measured on and asserts the playground now answers what `nlc run` answered. Every expected literal
// is a TRANSCRIPT, taken from `dotnet Cli.dll run` in a real `project.yml` project against the
// worktree-built CLI — the command and its output are quoted at each block.
//
// THE TWO NOT PINNED HERE, and why:
//   * `"n=" + 1` — the playground is RIGHT and the COMPILER has the gap. `nlc check` answers
//     `NL103 ... Declined at emit.print.expression`, an emit DECLINE, not a language rule: the
//     analyzer accepts the program. `ColumnarPrimitiveBinaryPlanner` plans `+` as `String.Concat`
//     only when the unified operand type IS `string`, so `string + int`, `int + string`,
//     `string + double` and `string + bool` all decline while `"a" + "b"` and `$"n={n}"` emit. That
//     is a columnar-emit coverage slice, not a playground fix, and copying a decline into the
//     runner would be the second spelling this campaign exists to remove.
//   * union match with SHORTHAND binding `{ Radius }` — owned by the sibling `playground union
//     shorthand` chip and deliberately untouched here.

test "chip playground-vs-nlc-run D1: `6 / 0` reports the CLR's OWN sentence, not the playground's invented `division by zero`" {
    // `nlc run`: exit 134, `Unhandled exception. System.DivideByZeroException: Attempted to divide
    // by zero.` The FRAME cannot be matched in a browser tab (no process to abort, no stack to
    // walk), so the playground keeps `Stderr` + exit 1; the SENTENCE — the part a user reads and
    // searches for — is now identical.
    source := "namespace P\n\nfunc main() {\n    a := 6\n    b := 0\n    print a / b\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "False"
    assert PgExitCode(response) == "1"
    assert PgStdout(response) == ""
    assert PgStderr(response) == "Attempted to divide by zero."
    assert PgStderr(response) != "division by zero"
    assert PgUnsupportedReason(response) == "<null>"
}

test "chip playground-vs-nlc-run D2: a double divided by zero is a DEFINED IEEE value the playground now PRINTS instead of failing on" {
    // `nlc run` on the same three divisions: exit 0, three defined values. The playground used to
    // answer exit 1 / `division by zero` for all three — the only measured divergence that broke a
    // program the compiler runs.
    //
    // THE INFINITY SYMBOL IS A CULTURE EFFECT, NOT A SECOND DIVERGENCE, AND IT WAS MEASURED BOTH
    // WAYS. `nlc run` prints `∞\n-∞\nNaN\n` under this machine's ICU culture and
    // `Infinity\n-Infinity\nNaN\n` under `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` — byte-identical
    // to what the playground answers here. The runner formats under the INVARIANT culture on
    // purpose (see `NumberFormatSpecifier`, so a `de-DE` browser still sees `0.5`), and that
    // deliberate policy predates this chip. The value is the same `Double.PositiveInfinity` on
    // both sides; only the culture that renders it differs.
    source := "namespace P\n\nfunc main() {\n    a := 6.0\n    b := 0.0\n    c := 0.0 - 6.0\n    print a / b\n    print c / b\n    print b / b\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "True"
    assert PgExitCode(response) == "0"
    assert PgStdout(response) == "Infinity\n-Infinity\nNaN\n"
    assert PgStderr(response) == "<null>"
    assert PgStderr(response) != "Attempted to divide by zero."
}

test "chip playground-vs-nlc-run D2b: INTEGER division by zero still fails, and a non-zero divisor still divides — the fault narrowed, it did not vanish" {
    intDivision := PgRunFiles("namespace P\n\nfunc main() {\n    a := 6\n    b := 0\n    print a / b\n}", "Program.nl")
    assert PgExitCode(intDivision) == "1"
    assert PgStderr(intDivision) == "Attempted to divide by zero."

    // `nlc run`: `2` for the truncating integer division, `0.3333333333333333` for the double.
    ordinary := PgRunFiles("namespace P\n\nfunc main() {\n    print 6 / 3\n    print 1.0 / 3.0\n}", "Program.nl")
    assert PgExitCode(ordinary) == "0"
    assert PgStdout(ordinary) == "2\n0.3333333333333333\n"
}

test "chip playground-vs-nlc-run D3: `0.1 + 0.2 == 0.3` answers False, as `nlc run` does — the 1e-7 tolerance is gone" {
    // `nlc run`: exit 0, stdout `False\n`. The playground answered `True\n`, teaching the opposite
    // of how binary floating point works in the surface a learner reaches first.
    source := "namespace P\n\nfunc main() {\n    print 0.1 + 0.2 == 0.3\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "True"
    assert PgExitCode(response) == "0"
    assert PgStdout(response) == "False\n"
    assert PgStdout(response) != "True\n"
}

test "chip playground-vs-nlc-run D3b: exact equality did not break the answers that were already right" {
    // Controls. `nlc run` prints `True\nFalse\nTrue\n` for these three.
    source := "namespace P\n\nfunc main() {\n    print 1.0 == 1.0\n    print 1.0 == 1.001\n    print 2 == 2\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgExitCode(response) == "0"
    assert PgStdout(response) == "True\nFalse\nTrue\n"
}

test "chip playground-vs-nlc-run D4: `print` of a record shows the CLR type name `P.Point`, which is what `nlc run` shows" {
    // `nlc run`: exit 0, stdout `P.Point\n`. `print` lowers to `Console.WriteLine`, which calls
    // `Object.ToString()`, and N# synthesises no `record` override. The playground used to print
    // `Point { X: 1, Y: 2 }` — fields that vanish the moment the same source is built locally.
    source := "namespace P\n\nrecord Point(X: int, Y: int) {\n}\n\nfunc main() {\n    p := new Point(1, 2)\n    print p\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "True"
    assert PgExitCode(response) == "0"
    assert PgStdout(response) == "P.Point\n"
    assert PgStdout(response) != "Point { X: 1, Y: 2 }\n"
}

test "chip playground-vs-nlc-run D5: `print` of a union value shows the NESTED CLR type name `P.Shape+Circle`" {
    // `nlc run`: exit 0, stdout `P.Shape+Circle\n`. A union case is a type nested in its union, and
    // `Type.ToString()` joins the two with `+`. The playground used to print `Shape.Circle(Radius: 3)`.
    source := "namespace P\n\nunion Shape {\n    Circle { Radius: int }\n    Square { Side: int }\n}\n\nfunc main() {\n    s := new Shape.Circle(3)\n    print s\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "True"
    assert PgExitCode(response) == "0"
    assert PgStdout(response) == "P.Shape+Circle\n"
    assert PgStdout(response) != "Shape.Circle(Radius: 3)\n"
}

test "chip playground-vs-nlc-run D4/D5 control: the namespace comes from the COMPILER'S owner, so `package`, a dotted namespace and no header at all each land where `nlc run` lands" {
    // Three transcripts, all measured. `package Tutorial` -> `Tutorial.Point\nTutorial.Shape+Circle\n`;
    // `namespace A.B` -> `A.B.Point\n`; a file with NEITHER header -> the bare `Point\n`. The runner
    // does not decide which header wins — `AnalyzerDeclarationFileFacts.GetUnitNamespace` does.
    packaged := PgRunFiles("package Tutorial\n\nrecord Point(X: int, Y: int) {\n}\n\nunion Shape {\n    Circle { Radius: int }\n}\n\nfunc main() {\n    print new Point(1, 2)\n    print new Shape.Circle(3)\n}", "Program.nl")
    assert PgExitCode(packaged) == "0"
    assert PgStdout(packaged) == "Tutorial.Point\nTutorial.Shape+Circle\n"

    dotted := PgRunFiles("namespace A.B\n\nrecord Point(X: int, Y: int) {\n}\n\nfunc main() {\n    print new Point(1, 2)\n}", "Program.nl")
    assert PgExitCode(dotted) == "0"
    assert PgStdout(dotted) == "A.B.Point\n"

    bare := PgRunFiles("record Point(X: int, Y: int) {\n}\n\nfunc main() {\n    print new Point(1, 2)\n}", "Program.nl")
    assert PgExitCode(bare) == "0"
    assert PgStdout(bare) == "Point\n"
}

test "chip playground-vs-nlc-run: the seventh divergence is NOT fixed here and the playground is the side that is RIGHT — `\"n=\" + 1` still runs in the browser and still declines at `nlc` emit" {
    // Recorded so the remainder cannot be lost. `nlc check --json` on this exact source answers
    // `NL103 ... Declined at emit.print.expression`, an EMIT decline; the analyzer reports nothing,
    // which is why the playground (which runs the analyzer, not the emitter) executes it. Pinning
    // the playground's answer here states the gap rather than papering over it.
    concat := PgRunFiles("namespace P\n\nfunc main() {\n    print \"n=\" + 1\n}", "Program.nl")
    assert PgExitCode(concat) == "0"
    assert PgStdout(concat) == "n=1\n"
    assert PgCensus(concat) == ""

    // The shape that DOES emit, on both sides, as the boundary of the gap: `nlc run` prints `ab\n`.
    strings := PgRunFiles("namespace P\n\nfunc main() {\n    print \"a\" + \"b\"\n}", "Program.nl")
    assert PgExitCode(strings) == "0"
    assert PgStdout(strings) == "ab\n"
}

// EVERY shipped example that DECLARES an `ExpectedOutput`, run through the Run button, rendered as
// `id=MATCH;` or `id=MISMATCH;` in corpus order. An example that declares no output is not in the
// census — the catalog's own text is the only oracle this contract has, and an example without one
// cannot be judged by it.
func PgExpectedOutputCensus(): string {
    entries := PgExamples()
    census := ""
    index := 0
    while index < entries.Count {
        entry := entries[index]
        if entry != null {
            expected := PgText(entry, "ExpectedOutput")
            if expected != "<null>" {
                verdict := "MISMATCH"
                if PgStdout(PgRunFiles(PgExampleCode(index), "Program.nl")) == expected {
                    verdict = "MATCH"
                }

                census = census + PgText(entry, "Id") + "=" + verdict + ";"
            }
        }

        index = index + 1
    }

    return census
}

// ---- the union-case SHORTHAND property pattern: the playground must accept what the compiler accepts ----
//
// 021 slice 11 measured `04-unions-patterns` — a SHIPPED tutorial example carrying a declared
// `ExpectedOutput` — failing `PG208 — could not resolve 'name'` behind a Run button, while `nlc run`
// printed the declared transcript. The cause was a THIRD spelling of one language rule:
// `PatternMatches` declared a binding only when a `PropertyPattern`'s `BindingName` was non-null,
// and NO parser production ever sets it, so the shorthand `Found { name, score }` bound NOTHING
// while `Found { name: n, score: s }` bound correctly — a one-character difference between a
// program that ran and a program that did not. The runner now asks
// `AnalyzerPropertyPatternBinding.BoundName`, the compiler's own owner of that decision, so there is
// one rule and the interpreter cannot disagree with the emitter about it.
//
// EVERY EXPECTED OUTPUT BELOW WAS MEASURED AGAINST `nlc run` ON THE SAME SOURCE, not asserted from
// the runner alone. `nlc run` on the shipped example prints `Ada: 99\nMissing player #404\n` and
// exits 0; on the minimal pair it prints `circle 3\n` for BOTH spellings; and on the two invalid
// spellings it reports the SAME `NL503` sentence at the SAME span the playground reports, because
// both consult the analyzer before either executes anything.

test "chip playground union shorthand: the SHIPPED 04-unions-patterns example RUNS, and its stdout is its own declared ExpectedOutput — the transcript `nlc run` prints for the same source" {
    index := PgIndexOfExample("04-unions-patterns")
    assert index == 3
    assert PgText(PgExample(index), "ExpectedOutput") == "Ada: 99\nMissing player #404\n"
    response := PgRunFiles(PgExampleCode(index), "Program.nl")
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgExitCode(response) == "0"
    assert PgStdout(response) == "Ada: 99\nMissing player #404\n"
    assert PgStdout(response) == PgText(PgExample(index), "ExpectedOutput")
    assert PgStderr(response) == "<null>"
    assert PgUnsupportedReason(response) == "<null>"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
}

test "chip playground union shorthand: the ONE-CHARACTER probe pair that isolated the defect now answers identically — `Shape.Circle { Radius }` and `Shape.Circle { Radius: r }` both print what `nlc run` prints" {
    shorthandSource := "package Tutorial\n\nunion Shape {\n    Circle { Radius: int }\n}\n\nfunc Describe(shape: Shape): string {\n    return match shape {\n        Shape.Circle { Radius } => $\"circle {Radius}\"\n    }\n}\n\nfunc main() {\n    print Describe(new Shape.Circle(3))\n}"
    explicitSource := "package Tutorial\n\nunion Shape {\n    Circle { Radius: int }\n}\n\nfunc Describe(shape: Shape): string {\n    return match shape {\n        Shape.Circle { Radius: r } => $\"circle {r}\"\n    }\n}\n\nfunc main() {\n    print Describe(new Shape.Circle(3))\n}"
    shorthandResponse := PgRunFiles(shorthandSource, "Program.nl")
    explicitResponse := PgRunFiles(explicitSource, "Program.nl")
    assert PgOk(shorthandResponse) == "True"
    assert PgExitCode(shorthandResponse) == "0"
    assert PgStdout(shorthandResponse) == "circle 3\n"
    assert PgStderr(shorthandResponse) == "<null>"
    assert PgUnsupportedReason(shorthandResponse) == "<null>"
    assert PgCensus(shorthandResponse) == ""
    // The two spellings are the SAME program to the compiler, so they must be the same program here.
    assert PgStdout(explicitResponse) == PgStdout(shorthandResponse)
    assert PgExitCode(explicitResponse) == PgExitCode(shorthandResponse)
    assert PgOk(explicitResponse) == PgOk(shorthandResponse)
    assert PgCensus(explicitResponse) == PgCensus(shorthandResponse)
}

test "chip playground union shorthand: EVERY shipped example that declares an ExpectedOutput now PRODUCES it — 8 of the 10, named, in corpus order" {
    assert PgExpectedOutputCensus() == "01-hello-world=MATCH;02-values-functions=MATCH;03-types-visibility=MATCH;04-unions-patterns=MATCH;05-duck-typing=MATCH;06-collections-linq=MATCH;09-testing=MATCH;10-tooling-loop=MATCH;"
}

test "chip playground union shorthand NEGATIVE: a shorthand naming a property the case does not carry is REFUSED with the compiler's own NL503, at the compiler's own span — `nlc run` reports the identical sentence at 10:30+4 and exits 1" {
    source := "package Tutorial\n\nunion LookupResult {\n    Found { name: string, score: int }\n    Missing { id: int }\n}\n\nfunc Describe(result: LookupResult): string {\n    return match result {\n        LookupResult.Found { nope } => \"found\",\n        LookupResult.Missing { id } => $\"Missing player #{id}\"\n    }\n}\n\nfunc main() {\n    print Describe(new LookupResult.Missing(404))\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "False"
    assert PgExitCode(response) == "1"
    assert PgStdout(response) == ""
    // NOT a `PG2xx` — the runner never starts, so the user reads the compiler's diagnostic.
    assert PgStderr(response) == "Run skipped because the program has compiler errors."
    assert PgUnsupportedReason(response) == "<null>"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL503@10:30+4;"
    assert PgRow(response, 0) == "NL503|error|Union case 'Found' doesn't have a property named 'nope' — check the case definition for available properties|Program.nl|10|30|4"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
}

test "chip playground union shorthand NEGATIVE: a shorthand under a case the union does not declare is REFUSED with the compiler's own NL503 — `nlc run` reports the identical sentence at 10:9+17 and exits 1" {
    source := "package Tutorial\n\nunion LookupResult {\n    Found { name: string, score: int }\n    Missing { id: int }\n}\n\nfunc Describe(result: LookupResult): string {\n    return match result {\n        LookupResult.Nope { id } => \"nope\",\n        LookupResult.Found { name, score } => $\"{name}: {score}\",\n        LookupResult.Missing { id } => $\"Missing player #{id}\"\n    }\n}\n\nfunc main() {\n    print Describe(new LookupResult.Missing(404))\n}"
    response := PgRunFiles(source, "Program.nl")
    assert PgOk(response) == "False"
    assert PgExitCode(response) == "1"
    assert PgStdout(response) == ""
    assert PgStderr(response) == "Run skipped because the program has compiler errors."
    assert PgUnsupportedReason(response) == "<null>"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL503@10:9+17;"
    assert PgRow(response, 0) == "NL503|error|'LookupResult.Nope' is not a case of union 'LookupResult' — check the union definition for available cases|Program.nl|10|9|17"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
}
