namespace NSharpLang.PlaygroundDiagnosticSpans.Tests

import System
import System.Collections
import System.Reflection


// THE PLAYGROUND CHECK ROUTE'S DIAGNOSTIC SPANS, READ FROM SOURCE TEXT, IN N#.
//
// These replace THE FIRST CUT of `tests/PlaygroundCompilerTests.cs`: the 34 bodies that NAME the
// file's `AssertPlaygroundSpan` helper. 30 `[Fact]`s and 4 `[Theory]`s carrying 25 `InlineData`
// rows, 1,051 declaration lines, 113 in-body `Assert.` calls, 71 `AssertPlaygroundSpan` calls, 57
// source fixtures and 233 decoded claim rows. `AssertPlaygroundSpan` has 71 call sites and every one
// of them is inside the cut, so the helper is deleted with them. Task 020 slice 37 takes this cut;
// the file survives at 35 methods / 745 lines for the slice that closes it.
//
// WHY THIS IS A NATIVE PROJECT AND WHY IT IS A NEW ONE. `PlaygroundCompiler` is a C# class in
// `NSharpLang.Playground.dll`, an assembly NO native project has ever referenced and which no
// `.tests.nl` inside the compiler-service estate can reach: `NSharpLang.Playground` depends on
// `Compiler`, which depends on `NSharpLang.Compiler.BootstrapServices`, never the other way round.
// The capability this slice adds is exactly the `dll:` line in `project.yml` plus the reflection
// walk that follows it, and the gate now builds `NSharpLang.Playground` in the same step it builds
// the CLI so that dependency is DECLARED rather than a side effect of the unit-test step.
//
// THE MODELS ARE ALREADY N#. `PlaygroundFile`, `PlaygroundCheckResponse`, `PlaygroundDiagnostic` and
// `PlaygroundSummary` are records in `src/NSharpLang.Compiler.BootstrapServices/PlaygroundModels.nl`
// — only `PlaygroundCompiler` and `PlaygroundRunner` are still C#. The kernels below construct a
// `PlaygroundFile` through its own two-argument constructor and read every response field by
// member reflection, because a type that arrives through a `dll:` dependency is reflection-only.
//
// FIVE THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//
//   (a) THE PARSER'S INTERNAL `<error>` PLACEHOLDER REACHES USER-FACING SENTENCES, AND THE DELETED
//       FILE WAS GUARDING AGAINST EXACTLY THAT ON TWO OTHER FIXTURES WHILE FIVE OF ITS OWN LEAKED
//       IT. Seventeen pinned rows across five migrating fixtures carry `<error>` in a MESSAGE or a
//       SUGGESTION: `NL903 Identifier '<error>' starts with a non-letter character`, `NL012
//       Parameter '<error>' in 'main' is never read`, `NL201 Type '<error>' not found`, and two
//       suggestions that tell the user to import `<error>`. Two deleted methods asserted
//       `DoesNotContain(… Message.Contains("<error>"))`; nothing looked at the other five.
//
//   (b) THE DELETED CLAIM WAS THREE INTEGERS AND IT IS NOW THE WHOLE RESPONSE. `AssertPlaygroundSpan`
//       read `Line`, `Column` and `Length` of ONE diagnostic the body had already selected by code
//       and message substring. Every contract here pins `Ok`, `SchemaVersion`, `File`, the
//       `Errors/Warnings/Infos` summary, the diagnostic COUNT, the whole census, and for EVERY row
//       its `Code|Severity|Message|File|Line|Column|Length` AND its
//       `SourceSnippet|Explanation|Suggestion|Hint`, plus the `<no-such-diagnostic>` sentinel one
//       past the end.
//
//   (c) THE SECOND ROUTE, WHICH NOT ONE OF THE 34 METHODS DROVE FOR ITS OWN FIXTURE. `Check(source)`
//       hands the text to `CheckProject` as `Program.nl`; presenting the SAME text as
//       `Program.tests.nl` goes through `GetAnalyzableFiles` instead. Both routes are pinned on
//       every fixture. All 233 claims hold on the route the C# drove; EIGHT are false on the other,
//       and all eight belong to the import-collision method, whose subject cannot exist in a
//       single-file route at all.
//
//   (d) THE SUGGESTIONS AND HINTS, WHICH ONLY 12 OF THE 233 CLAIMS TOUCHED. Nine `Assert.Contains`
//       on a `Hint`, two on an `Explanation`, one on a `Suggestion` — against 156 pinned rows whose
//       four detail fields are all stated.
//
//   (e) THE ABSENCE CLAIMS ARE NOT VACUOUS, AND THAT IS MEASURED RATHER THAN ASSERTED. The 13
//       deleted `Assert.DoesNotContain` rows name `NL101`, `NL313` and the `<error>` substring;
//       W1, W2 and W3 below are committed contracts showing the shipping compiler DOES report each
//       of them on a neighbouring source.
//
// THE FIXTURES ARE THE DELETED ONES BYTE FOR BYTE, decoded by the C# compiler itself: all 65
// literal tokens were copied UNMODIFIED into a generated console program that printed each one's
// sha256 and length, and the independent decode reproduces 65 of 65 shas and 65 of 65 lengths with
// ZERO mismatches over 5,399 characters. The 57 SOURCE fixtures total 5,307 characters and 56 of
// them are distinct; the one duplicate is `A.nl` and `B.nl` of the import-collision fixture, whose
// whole subject is that two files declare the same class.


func SetPgObject(values: object?[], index: int, value: object?) {
    values[index] = value
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

func PgCompilerType(): Type {
    compilerType := Type.GetType("NSharpLang.Playground.PlaygroundCompiler, NSharpLang.Playground")
    if compilerType == null {
        throw new InvalidOperationException("The production playground compiler was not loadable.")
    }

    return compilerType
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

// `Array.CreateInstance` DECLINES AT EMIT the moment its result is bound to a LOCAL, so the empty
// array is only ever a RETURN VALUE, and the elements are written through the reflected
// `Array.SetValue` rather than an indexer. Both spellings were found by bisection against
// `nlc test`, not guessed.
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
    SetPgObject(arguments, 1, index)
    setMethod.Invoke(target, arguments)
}

func PgCheck(source: string): object {
    compilerType := PgCompilerType()
    checkParameterTypes := new Type[](2)
    checkParameterTypes[0] = typeof(string)
    checkParameterTypes[1] = typeof(string)
    checkMethod := compilerType.GetMethod("Check", checkParameterTypes)
    if checkMethod == null {
        throw new InvalidOperationException("The production Check entry point was not found.")
    }

    checkArguments := new object?[](2)
    SetPgObject(checkArguments, 0, source)
    SetPgObject(checkArguments, 1, null)
    response := checkMethod.Invoke(PgNewCompiler(), checkArguments)
    if response == null {
        throw new InvalidOperationException("The production Check entry point returned no result.")
    }

    return response
}

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

func PgCheckProject1(name: string, code: string, activeFile: string): object {
    files := PgEmptyFileArray(1)
    PgSetFile(files, 0, PgNewFile(name, code))
    return PgCheckFiles(files, activeFile)
}

func PgCheckProject2(firstName: string, firstCode: string, secondName: string, secondCode: string, activeFile: string): object {
    files := PgEmptyFileArray(2)
    PgSetFile(files, 0, PgNewFile(firstName, firstCode))
    PgSetFile(files, 1, PgNewFile(secondName, secondCode))
    return PgCheckFiles(files, activeFile)
}

func PgCheckProject3(firstName: string, firstCode: string, secondName: string, secondCode: string, thirdName: string, thirdCode: string, activeFile: string): object {
    files := PgEmptyFileArray(3)
    PgSetFile(files, 0, PgNewFile(firstName, firstCode))
    PgSetFile(files, 1, PgNewFile(secondName, secondCode))
    PgSetFile(files, 2, PgNewFile(thirdName, thirdCode))
    return PgCheckFiles(files, activeFile)
}

// THE SECOND ROUTE: the same text presented as a TEST file, which reaches the analyzable-file
// filter the one-argument entry point never touches.
func PgCheckTestFile(source: string): object {
    return PgCheckProject1("Program.tests.nl", source, "Program.tests.nl")
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
    diagnostics := PgMember(response, "Diagnostics") as IList
    if diagnostics == null {
        return -1
    }

    return diagnostics.Count
}

func PgCensus(response: object): string {
    diagnostics := PgMember(response, "Diagnostics") as IList
    if diagnostics == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < diagnostics.Count {
        entry := diagnostics[index]
        if entry != null {
            census = census + PgText(entry, "Code") + "@" + PgText(entry, "Line") + ":" + PgText(entry, "Column") + "+" + PgText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

func PgRow(response: object, index: int): string {
    diagnostics := PgMember(response, "Diagnostics") as IList
    if diagnostics == null {
        return "<not-a-list>"
    }

    if index >= diagnostics.Count {
        return "<no-such-diagnostic>"
    }

    entry := diagnostics[index]
    if entry == null {
        return "<null-diagnostic>"
    }

    return PgText(entry, "Code") + "|" + PgText(entry, "Severity") + "|" + PgText(entry, "Message") + "|" + PgText(entry, "File") + "|" + PgText(entry, "Line") + "|" + PgText(entry, "Column") + "|" + PgText(entry, "Length")
}

func PgDetail(response: object, index: int): string {
    diagnostics := PgMember(response, "Diagnostics") as IList
    if diagnostics == null {
        return "<not-a-list>"
    }

    if index >= diagnostics.Count {
        return "<no-such-diagnostic>"
    }

    entry := diagnostics[index]
    if entry == null {
        return "<null-diagnostic>"
    }

    return PgText(entry, "SourceSnippet") + "|" + PgText(entry, "Explanation") + "|" + PgText(entry, "Suggestion") + "|" + PgText(entry, "Hint")
}


// ======== THE MIGRATED CUT — 55 fixture units over 34 deleted methods ========

test "020 s37 playground diagnostic spans: Check NSharpNoMatchingOverload PreservesCallableNameSpan — NL402@10:7+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_NSharpNoMatchingOverload_PreservesCallableNameSpan)" {
    source := "package Playground\n\nclass Processor {\n    func Process(x: int): int { return x }\n    func Process(x: string): string { return x }\n}\n\nfunc main() {\n    p := new Processor()\n    p.Process(true)\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL402@10:7+7;"
    assert PgRow(response, 0) == "NL402|error|No overload of 'Process' accepts 1 argument with these types|Program.nl|10|7|7"
    assert PgDetail(response, 0) == "    p.Process(true)|I cannot find an overload of `Process` that matches this call:|<null>|This call passes 1 argument: `bool`.\nAvailable overloads:\n  - Process(x: int): int\n  - Process(x: string): string\n\nCheck the argument count and types. If you meant to reference the method itself, use it in a context with a delegate type instead of calling it."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL402@10:7+7;"
    assert PgRow(other, 0) == "NL402|error|No overload of 'Process' accepts 1 argument with these types|Program.tests.nl|10|7|7"
}

test "020 s37 playground diagnostic spans: Check TypeMismatchDiagnostics PreserveOffendingExpressionSpans — NL202@6:39+5;NL202@8:6+32;NL305@10:1+9;NL001@11:5+8;NL202@11:21+4;NL001@12:5+8;NL202@12:17+9;NL202@13:8+5;NL202@14:16+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_TypeMismatchDiagnostics_PreserveOffendingExpressionSpans)" {
    source := "package Playground\n\nfunc TakesVoid(): void {\n}\n\nfunc ExpressionBodyMismatch(): int => \"bad\"\n\nfunc ExpressionBodyRequiresReturnType() => \"bad\"\n\nfunc main(): int {\n    declared: int = \"hi\"\n    inferred := TakesVoid()\n    if \"yes\" {\n        return \"bad\"\n    }\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "9/0/0"
    assert PgCount(response) == 9
    assert PgCensus(response) == "NL202@6:39+5;NL202@8:6+32;NL305@10:1+9;NL001@11:5+8;NL202@11:21+4;NL001@12:5+8;NL202@12:17+9;NL202@13:8+5;NL202@14:16+5;"
    assert PgRow(response, 0) == "NL202|error|Function 'ExpressionBodyMismatch' should return int but returns string|Program.nl|6|39|5"
    assert PgDetail(response, 0) == "func ExpressionBodyMismatch(): int => \"bad\"|This return value does not match `ExpressionBodyMismatch`'s return type:|<null>|Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
    assert PgRow(response, 1) == "NL202|error|Function 'ExpressionBodyRequiresReturnType' returns string but has no return type|Program.nl|8|6|32"
    assert PgDetail(response, 1) == "func ExpressionBodyRequiresReturnType() => \"bad\"|Function `ExpressionBodyRequiresReturnType` has no return type annotation, so N# treats it as `void`:|Add `: string` to `ExpressionBodyRequiresReturnType` or remove the returned value|This code gives back a value of type `string` from a function that currently returns nothing.\nAdd `: string` after the parameter list if `ExpressionBodyRequiresReturnType` should return this value, or remove the value if the function should stay void."
    assert PgRow(response, 2) == "NL305|error|Not all code paths return a value of type 'int'|Program.nl|10|1|9"
    assert PgDetail(response, 2) == "func main(): int {|This function is declared to return `int`, but not all code paths return a value:|Add a `return` statement, or change the return type to `void`|Every code path through this function must end with a `return` statement that\nprovides a `int` value. If you don't need to return anything, change the\nreturn type to `void`."
    assert PgRow(response, 3) == "NL001|error|Variable 'declared' is declared but never read|Program.nl|11|5|8"
    assert PgDetail(response, 3) == "    declared: int = \"hi\"|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_declared'|<null>"
    assert PgRow(response, 4) == "NL202|error|Type mismatch|Program.nl|11|21|4"
    assert PgDetail(response, 4) == "    declared: int = \"hi\"|I am having trouble with this code on line 11:|<null>|Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
    assert PgRow(response, 5) == "NL001|error|Variable 'inferred' is declared but never read|Program.nl|12|5|8"
    assert PgDetail(response, 5) == "    inferred := TakesVoid()|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_inferred'|<null>"
    assert PgRow(response, 6) == "NL202|error|This expression doesn't return a value (it's void) — you can't assign it to a variable|Program.nl|12|17|9"
    assert PgDetail(response, 6) == "    inferred := TakesVoid()|<null>|Ensure types are compatible or add explicit cast|<null>"
    assert PgRow(response, 7) == "NL202|error|Type mismatch|Program.nl|13|8|5"
    assert PgDetail(response, 7) == "    if \"yes\" {|I am having trouble with this code on line 13:|<null>|These types are not compatible. Check if you need to convert or cast."
    assert PgRow(response, 8) == "NL202|error|Function 'main' should return int but returns string|Program.nl|14|16|5"
    assert PgDetail(response, 8) == "        return \"bad\"|This return value does not match `main`'s return type:|<null>|Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
    assert PgRow(response, 9) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 9
    assert PgCensus(other) == "NL202@6:39+5;NL202@8:6+32;NL305@10:1+9;NL001@11:5+8;NL202@11:21+4;NL001@12:5+8;NL202@12:17+9;NL202@13:8+5;NL202@14:16+5;"
    assert PgRow(other, 0) == "NL202|error|Function 'ExpressionBodyMismatch' should return int but returns string|Program.tests.nl|6|39|5"
    assert PgRow(other, 1) == "NL202|error|Function 'ExpressionBodyRequiresReturnType' returns string but has no return type|Program.tests.nl|8|6|32"
    assert PgRow(other, 2) == "NL305|error|Not all code paths return a value of type 'int'|Program.tests.nl|10|1|9"
    assert PgRow(other, 3) == "NL001|error|Variable 'declared' is declared but never read|Program.tests.nl|11|5|8"
    assert PgRow(other, 4) == "NL202|error|Type mismatch|Program.tests.nl|11|21|4"
    assert PgRow(other, 5) == "NL001|error|Variable 'inferred' is declared but never read|Program.tests.nl|12|5|8"
    assert PgRow(other, 6) == "NL202|error|This expression doesn't return a value (it's void) — you can't assign it to a variable|Program.tests.nl|12|17|9"
    assert PgRow(other, 7) == "NL202|error|Type mismatch|Program.tests.nl|13|8|5"
    assert PgRow(other, 8) == "NL202|error|Function 'main' should return int but returns string|Program.tests.nl|14|16|5"
}

test "020 s37 playground diagnostic spans: Check EnumMemberInitializerTypeMismatches PreserveInitializerValueSpans — NL202@4:10+4;NL202@8:13+1;, and the test-file route agrees (was PlaygroundCompilerTests.Check_EnumMemberInitializerTypeMismatches_PreserveInitializerValueSpans)" {
    source := "package Playground\n\nenum HttpCode: int {\n    Ok = \"ok\"\n}\n\nenum Label: string {\n    Ready = 1\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL202@4:10+4;NL202@8:13+1;"
    assert PgRow(response, 0) == "NL202|error|Enum member 'Ok' must have a numeric value — this enum uses int values|Program.nl|4|10|4"
    assert PgDetail(response, 0) == "    Ok = \"ok\"|<null>|Use a numeric value for 'Ok', or change the enum backing type to 'string'|<null>"
    assert PgRow(response, 1) == "NL202|error|Enum member 'Ready' must have a string value — this enum uses string values|Program.nl|8|13|1"
    assert PgDetail(response, 1) == "    Ready = 1|<null>|Use a string value for 'Ready', or change the enum backing type to 'int'|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL202@4:10+4;NL202@8:13+1;"
    assert PgRow(other, 0) == "NL202|error|Enum member 'Ok' must have a numeric value — this enum uses int values|Program.tests.nl|4|10|4"
    assert PgRow(other, 1) == "NL202|error|Enum member 'Ready' must have a string value — this enum uses string values|Program.tests.nl|8|13|1"
}

test "020 s37 playground diagnostic spans: Check ControlFlowAndCollectionTypeMismatches PreserveOffendingExpressionSpans — NL202@4:11+6;NL202@7:17+6;NL001@11:5+6;NL202@11:15+7;NL001@12:5+7;NL202@12:20+5;NL505@14:16+7;NL202@15:14+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_ControlFlowAndCollectionTypeMismatches_PreserveOffendingExpressionSpans)" {
    source := "package Playground\n\nfunc main() {\n    while \"loop\" {\n    }\n\n    for i := 0; \"loop\"; i++ {\n    }\n\n    value := 1\n    answer := \"maybe\" ? 1 : 2\n    numbers := [1, \"two\"]\n    label := match value {\n        n when \"guard\" => \"positive\",\n        _ => 12345\n    }\n    print label\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "8/0/0"
    assert PgCount(response) == 8
    assert PgCensus(response) == "NL202@4:11+6;NL202@7:17+6;NL001@11:5+6;NL202@11:15+7;NL001@12:5+7;NL202@12:20+5;NL505@14:16+7;NL202@15:14+5;"
    assert PgRow(response, 0) == "NL202|error|The condition in a 'while' loop must be a boolean, but I found 'string'|Program.nl|4|11|6"
    assert PgDetail(response, 0) == "    while \"loop\" {|<null>|Ensure types are compatible or add explicit cast|<null>"
    assert PgRow(response, 1) == "NL202|error|The condition in a 'for' loop must be a boolean, but I found 'string'|Program.nl|7|17|6"
    assert PgDetail(response, 1) == "    for i := 0; \"loop\"; i++ {|<null>|Ensure types are compatible or add explicit cast|<null>"
    assert PgRow(response, 2) == "NL001|error|Variable 'answer' is declared but never read|Program.nl|11|5|6"
    assert PgDetail(response, 2) == "    answer := \"maybe\" ? 1 : 2|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_answer'|<null>"
    assert PgRow(response, 3) == "NL202|error|The condition in a ternary expression must be a boolean, but I found 'string'|Program.nl|11|15|7"
    assert PgDetail(response, 3) == "    answer := \"maybe\" ? 1 : 2|<null>|Ensure types are compatible or add explicit cast|<null>"
    assert PgRow(response, 4) == "NL001|error|Variable 'numbers' is declared but never read|Program.nl|12|5|7"
    assert PgDetail(response, 4) == "    numbers := [1, \"two\"]|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_numbers'|<null>"
    assert PgRow(response, 5) == "NL202|error|All elements in an array must be the same type — the first element is 'int' but I found 'string'|Program.nl|12|20|5"
    assert PgDetail(response, 5) == "    numbers := [1, \"two\"]|<null>|Ensure types are compatible or add explicit cast|<null>"
    assert PgRow(response, 6) == "NL505|error|A match guard must be a boolean, but this expression is 'string'|Program.nl|14|16|7"
    assert PgDetail(response, 6) == "        n when \"guard\" => \"positive\",|<null>|Guard expression must be boolean type|<null>"
    assert PgRow(response, 7) == "NL202|error|All match arms must return the same type — the first arm returns 'string', but this arm returns 'int'|Program.nl|15|14|5"
    assert PgDetail(response, 7) == "        _ => 12345|<null>|Ensure types are compatible or add explicit cast|<null>"
    assert PgRow(response, 8) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 8
    assert PgCensus(other) == "NL202@4:11+6;NL202@7:17+6;NL001@11:5+6;NL202@11:15+7;NL001@12:5+7;NL202@12:20+5;NL505@14:16+7;NL202@15:14+5;"
    assert PgRow(other, 0) == "NL202|error|The condition in a 'while' loop must be a boolean, but I found 'string'|Program.tests.nl|4|11|6"
    assert PgRow(other, 1) == "NL202|error|The condition in a 'for' loop must be a boolean, but I found 'string'|Program.tests.nl|7|17|6"
    assert PgRow(other, 2) == "NL001|error|Variable 'answer' is declared but never read|Program.tests.nl|11|5|6"
    assert PgRow(other, 3) == "NL202|error|The condition in a ternary expression must be a boolean, but I found 'string'|Program.tests.nl|11|15|7"
    assert PgRow(other, 4) == "NL001|error|Variable 'numbers' is declared but never read|Program.tests.nl|12|5|7"
    assert PgRow(other, 5) == "NL202|error|All elements in an array must be the same type — the first element is 'int' but I found 'string'|Program.tests.nl|12|20|5"
    assert PgRow(other, 6) == "NL505|error|A match guard must be a boolean, but this expression is 'string'|Program.tests.nl|14|16|7"
    assert PgRow(other, 7) == "NL202|error|All match arms must return the same type — the first arm returns 'string', but this arm returns 'int'|Program.tests.nl|15|14|5"
}

test "020 s37 playground diagnostic spans: Check LoopControlOutsideLoop PreservesFullKeywordSpans — NL103@4:5+5;NL103@5:5+8;, and the test-file route agrees (was PlaygroundCompilerTests.Check_LoopControlOutsideLoop_PreservesFullKeywordSpans)" {
    source := "package Playground\n\nfunc main() {\n    break\n    continue\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL103@4:5+5;NL103@5:5+8;"
    assert PgRow(response, 0) == "NL103|error|'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here|Program.nl|4|5|5"
    assert PgDetail(response, 0) == "    break|<null>|Move this `break` inside a loop, or remove it if there is no loop to exit.|<null>"
    assert PgRow(response, 1) == "NL103|error|'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here|Program.nl|5|5|8"
    assert PgDetail(response, 1) == "    continue|<null>|Move this `continue` inside a loop, or remove it if there is no loop to continue.|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL103@4:5+5;NL103@5:5+8;"
    assert PgRow(other, 0) == "NL103|error|'break' can only be used inside a loop (for, foreach, while) — there's no loop to break out of here|Program.tests.nl|4|5|5"
    assert PgRow(other, 1) == "NL103|error|'continue' can only be used inside a loop (for, foreach, while) — there's no loop to continue here|Program.tests.nl|5|5|8"
}

test "020 s37 playground diagnostic spans: Check ReturnOutsideFunctionAndTargetlessDefault PreserveFullKeywordSpans — NL001@2:5+5;NL203@2:14+7;NL103@6:5+6;, and the string route agrees (was PlaygroundCompilerTests.Check_ReturnOutsideFunctionAndTargetlessDefault_PreserveFullKeywordSpans)" {
    response := PgCheckProject1("Program.tests.nl", "func main() {\n    value := default\n}\n\ntest \"does not return\" {\n    return\n}", "Program.tests.nl")
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.tests.nl"
    assert PgSummary(response) == "3/0/0"
    assert PgCount(response) == 3
    assert PgCensus(response) == "NL001@2:5+5;NL203@2:14+7;NL103@6:5+6;"
    assert PgRow(response, 0) == "NL001|error|Variable 'value' is declared but never read|Program.tests.nl|2|5|5"
    assert PgDetail(response, 0) == "    value := default|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_value'|<null>"
    assert PgRow(response, 1) == "NL203|error|I can't figure out what type 'default' should be here — add a type annotation so I know what you mean (e.g., 'let x: int = default')|Program.tests.nl|2|14|7"
    assert PgDetail(response, 1) == "    value := default|<null>|Add explicit type annotation: 'let x: Type = ...'|<null>"
    assert PgRow(response, 2) == "NL103|error|'return' can only be used inside a function — there's no function to return from here|Program.tests.nl|6|5|6"
    assert PgDetail(response, 2) == "    return|<null>|Move this `return` inside a function, or remove it if there is no function to return from.|<null>"
    assert PgRow(response, 3) == "<no-such-diagnostic>"
    other := PgCheck("func main() {\n    value := default\n}\n\ntest \"does not return\" {\n    return\n}")
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.nl"
    assert PgCount(other) == 3
    assert PgCensus(other) == "NL001@2:5+5;NL203@2:14+7;NL103@6:5+6;"
    assert PgRow(other, 0) == "NL001|error|Variable 'value' is declared but never read|Program.nl|2|5|5"
    assert PgRow(other, 1) == "NL203|error|I can't figure out what type 'default' should be here — add a type annotation so I know what you mean (e.g., 'let x: int = default')|Program.nl|2|14|7"
    assert PgRow(other, 2) == "NL103|error|'return' can only be used inside a function — there's no function to return from here|Program.nl|6|5|6"
}

test "020 s37 playground diagnostic spans: Check ReadonlyAssignment PreservesAssignedFieldNameSpans — NL309@7:9+2;NL309@8:14+2;, and the test-file route agrees (was PlaygroundCompilerTests.Check_ReadonlyAssignment_PreservesAssignedFieldNameSpans)" {
    source := "package Playground\n\nclass Account {\n    readonly id: string = \"initial\"\n\n    func Change() {\n        id = \"next\"\n        this.id = \"again\"\n    }\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL309@7:9+2;NL309@8:14+2;"
    assert PgRow(response, 0) == "NL309|error|Field 'id' is readonly — it can only be assigned in a constructor|Program.nl|7|9|2"
    assert PgDetail(response, 0) == "        id = \"next\"|<null>|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|<null>"
    assert PgRow(response, 1) == "NL309|error|Field 'id' is readonly — it can only be assigned in a constructor|Program.nl|8|14|2"
    assert PgDetail(response, 1) == "        this.id = \"again\"|<null>|Move this assignment into a constructor, or remove `readonly` if the field needs to change later.|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL309@7:9+2;NL309@8:14+2;"
    assert PgRow(other, 0) == "NL309|error|Field 'id' is readonly — it can only be assigned in a constructor|Program.tests.nl|7|9|2"
    assert PgRow(other, 1) == "NL309|error|Field 'id' is readonly — it can only be assigned in a constructor|Program.tests.nl|8|14|2"
}

test "020 s37 playground diagnostic spans: Check UnreachableStatement PreservesUnreachableKeywordSpan — NL312@5:5+5;NL006@5:5+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_UnreachableStatement_PreservesUnreachableKeywordSpan)" {
    source := "package Playground\n\nfunc main() {\n    return\n    print \"after\"\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL312@5:5+5;NL006@5:5+5;"
    assert PgRow(response, 0) == "NL312|error|This code will never run — there's a 'return' or 'throw' above it|Program.nl|5|5|5"
    assert PgDetail(response, 0) == "    print \"after\"|<null>|Remove unreachable code or restructure control flow|<null>"
    assert PgRow(response, 1) == "NL006|error|This code will never run — there's a 'return' or 'throw' above it|Program.nl|5|5|5"
    assert PgDetail(response, 1) == "    print \"after\"|<null>|Remove the unreachable code, or move it before the return/throw if it should execute|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL312@5:5+5;NL006@5:5+5;"
    assert PgRow(other, 0) == "NL312|error|This code will never run — there's a 'return' or 'throw' above it|Program.tests.nl|5|5|5"
    assert PgRow(other, 1) == "NL006|error|This code will never run — there's a 'return' or 'throw' above it|Program.tests.nl|5|5|5"
}

test "020 s37 playground diagnostic spans: Check InvalidVariableDeclarations PreserveFullNameSpans — NL103@4:11+6;NL001@4:11+6;NL103@5:9+5;NL001@5:9+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_InvalidVariableDeclarations_PreserveFullNameSpans)" {
    source := "package Playground\n\nfunc main() {\n    const answer: int\n    let value\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "4/0/0"
    assert PgCount(response) == 4
    assert PgCensus(response) == "NL103@4:11+6;NL001@4:11+6;NL103@5:9+5;NL001@5:9+5;"
    assert PgRow(response, 0) == "NL103|error|A 'const' must have an initial value — the compiler needs to know its value at compile time|Program.nl|4|11|6"
    assert PgDetail(response, 0) == "    const answer: int|<null>|Add an initializer, for example `const answer: int = 42`.|<null>"
    assert PgRow(response, 1) == "NL001|error|Variable 'answer' is declared but never read|Program.nl|4|11|6"
    assert PgDetail(response, 1) == "    const answer: int|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_answer'|<null>"
    assert PgRow(response, 2) == "NL103|error|I can't determine the type of this variable — give it a type annotation or an initial value|Program.nl|5|9|5"
    assert PgDetail(response, 2) == "    let value|<null>|Add a type annotation like `let value: int`, or add an initializer like `let value := 0`.|<null>"
    assert PgRow(response, 3) == "NL001|error|Variable 'value' is declared but never read|Program.nl|5|9|5"
    assert PgDetail(response, 3) == "    let value|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_value'|<null>"
    assert PgRow(response, 4) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 4
    assert PgCensus(other) == "NL103@4:11+6;NL001@4:11+6;NL103@5:9+5;NL001@5:9+5;"
    assert PgRow(other, 0) == "NL103|error|A 'const' must have an initial value — the compiler needs to know its value at compile time|Program.tests.nl|4|11|6"
    assert PgRow(other, 1) == "NL001|error|Variable 'answer' is declared but never read|Program.tests.nl|4|11|6"
    assert PgRow(other, 2) == "NL103|error|I can't determine the type of this variable — give it a type annotation or an initial value|Program.tests.nl|5|9|5"
    assert PgRow(other, 3) == "NL001|error|Variable 'value' is declared but never read|Program.tests.nl|5|9|5"
}

test "020 s37 playground diagnostic spans: Check InvalidGenericConstraints PreserveOffendingConstraintSpans — NL103@3:54+6;NL103@7:53+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_InvalidGenericConstraints_PreserveOffendingConstraintSpans)" {
    source := "package Playground\n\nfunc BadClassStruct<T>(value: T): T where T : class, struct {\n    return value\n}\n\nfunc BadStructNew<T>(value: T): T where T : struct, new() {\n    return value\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL103@3:54+6;NL103@7:53+5;"
    assert PgRow(response, 0) == "NL103|error|Cannot have both 'class' and 'struct' constraints on the same type parameter — they are mutually exclusive|Program.nl|3|54|6"
    assert PgDetail(response, 0) == "func BadClassStruct<T>(value: T): T where T : class, struct {|A type parameter cannot be both a reference type (class) and a value type (struct) at the same time.|<null>|<null>"
    assert PgRow(response, 1) == "NL103|error|Cannot combine 'struct' and 'new()' constraints — 'struct' already implies a parameterless constructor|Program.nl|7|53|5"
    assert PgDetail(response, 1) == "func BadStructNew<T>(value: T): T where T : struct, new() {|The 'struct' constraint already requires a parameterless constructor, so 'new()' is redundant and not permitted in .|<null>|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL103@3:54+6;NL103@7:53+5;"
    assert PgRow(other, 0) == "NL103|error|Cannot have both 'class' and 'struct' constraints on the same type parameter — they are mutually exclusive|Program.tests.nl|3|54|6"
    assert PgRow(other, 1) == "NL103|error|Cannot combine 'struct' and 'new()' constraints — 'struct' already implies a parameterless constructor|Program.tests.nl|7|53|5"
}

test "020 s37 playground diagnostic spans: Check AssignmentAndOperatorTypeMismatches PreserveSpecificExpressionSpans — NL202@5:9+6;NL001@7:5+6;NL202@7:19+5;NL001@8:5+7;NL202@8:22+1;NL001@9:5+12;NL202@9:29+1;NL001@10:5+11;NL202@10:22+2;, and the test-file route agrees (was PlaygroundCompilerTests.Check_AssignmentAndOperatorTypeMismatches_PreserveSpecificExpressionSpans)" {
    source := "package Playground\n\nfunc main() {\n    x := 0\n    x = \"text\"\n\n    oneBad := 1 - \"two\"\n    bothBad := \"one\" - \"two\"\n    logicalRight := true && 1\n    logicalBoth := 1 && 2\n\n    print x\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "9/0/0"
    assert PgCount(response) == 9
    assert PgCensus(response) == "NL202@5:9+6;NL001@7:5+6;NL202@7:19+5;NL001@8:5+7;NL202@8:22+1;NL001@9:5+12;NL202@9:29+1;NL001@10:5+11;NL202@10:22+2;"
    assert PgRow(response, 0) == "NL202|error|Type mismatch|Program.nl|5|9|6"
    assert PgDetail(response, 0) == "    x = \"text\"|I am having trouble with this code on line 5:|<null>|Strings and integers are different types. To convert a string to an int,\nyou can use int.Parse(yourString) or int.TryParse(yourString, out result)."
    assert PgRow(response, 1) == "NL001|error|Variable 'oneBad' is declared but never read|Program.nl|7|5|6"
    assert PgDetail(response, 1) == "    oneBad := 1 - \"two\"|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_oneBad'|<null>"
    assert PgRow(response, 2) == "NL202|error|The '-' operator doesn't work with 'int' and 'string' — both sides need numeric values, but the right side is 'string'|Program.nl|7|19|5"
    assert PgDetail(response, 2) == "    oneBad := 1 - \"two\"|<null>|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|<null>"
    assert PgRow(response, 3) == "NL001|error|Variable 'bothBad' is declared but never read|Program.nl|8|5|7"
    assert PgDetail(response, 3) == "    bothBad := \"one\" - \"two\"|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_bothBad'|<null>"
    assert PgRow(response, 4) == "NL202|error|The '-' operator doesn't work with 'string' and 'string' — both sides need numeric values, but I found 'string' and 'string'|Program.nl|8|22|1"
    assert PgDetail(response, 4) == "    bothBad := \"one\" - \"two\"|<null>|Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.|<null>"
    assert PgRow(response, 5) == "NL001|error|Variable 'logicalRight' is declared but never read|Program.nl|9|5|12"
    assert PgDetail(response, 5) == "    logicalRight := true && 1|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_logicalRight'|<null>"
    assert PgRow(response, 6) == "NL202|error|Both sides of '&&' must be booleans, but the right side is 'int'|Program.nl|9|29|1"
    assert PgDetail(response, 6) == "    logicalRight := true && 1|<null>|Use boolean expressions on both sides of the operator.|<null>"
    assert PgRow(response, 7) == "NL001|error|Variable 'logicalBoth' is declared but never read|Program.nl|10|5|11"
    assert PgDetail(response, 7) == "    logicalBoth := 1 && 2|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_logicalBoth'|<null>"
    assert PgRow(response, 8) == "NL202|error|Both sides of '&&' must be booleans, but I found 'int' and 'int'|Program.nl|10|22|2"
    assert PgDetail(response, 8) == "    logicalBoth := 1 && 2|<null>|Use boolean expressions on both sides of the operator.|<null>"
    assert PgRow(response, 9) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 9
    assert PgCensus(other) == "NL202@5:9+6;NL001@7:5+6;NL202@7:19+5;NL001@8:5+7;NL202@8:22+1;NL001@9:5+12;NL202@9:29+1;NL001@10:5+11;NL202@10:22+2;"
    assert PgRow(other, 0) == "NL202|error|Type mismatch|Program.tests.nl|5|9|6"
    assert PgRow(other, 1) == "NL001|error|Variable 'oneBad' is declared but never read|Program.tests.nl|7|5|6"
    assert PgRow(other, 2) == "NL202|error|The '-' operator doesn't work with 'int' and 'string' — both sides need numeric values, but the right side is 'string'|Program.tests.nl|7|19|5"
    assert PgRow(other, 3) == "NL001|error|Variable 'bothBad' is declared but never read|Program.tests.nl|8|5|7"
    assert PgRow(other, 4) == "NL202|error|The '-' operator doesn't work with 'string' and 'string' — both sides need numeric values, but I found 'string' and 'string'|Program.tests.nl|8|22|1"
    assert PgRow(other, 5) == "NL001|error|Variable 'logicalRight' is declared but never read|Program.tests.nl|9|5|12"
    assert PgRow(other, 6) == "NL202|error|Both sides of '&&' must be booleans, but the right side is 'int'|Program.tests.nl|9|29|1"
    assert PgRow(other, 7) == "NL001|error|Variable 'logicalBoth' is declared but never read|Program.tests.nl|10|5|11"
    assert PgRow(other, 8) == "NL202|error|Both sides of '&&' must be booleans, but I found 'int' and 'int'|Program.tests.nl|10|22|2"
}

test "020 s37 playground diagnostic spans: Check PatternErrors PreserveSpecificPatternSpans — NL001@14:5+1;NL503@15:9+14;NL503@16:26+7;NL301@16:46+5;NL001@21:5+1;NL503@22:11+7;NL301@22:31+5;NL001@27:5+1;NL504@28:9+11;, and the test-file route agrees (was PlaygroundCompilerTests.Check_PatternErrors_PreserveSpecificPatternSpans)" {
    source := "package Playground\n\nunion Result {\n    Success { value: int }\n    Failure { message: string }\n}\n\nrecord User {\n    Name: string\n}\n\nfunc main() {\n    r := new Result.Success { value: 42 }\n    x := match r {\n        Result.Unknown => 0,\n        Result.Success { missing: value } => value,\n        Result.Failure { message } => 0\n    }\n\n    user := new User { Name: \"Ada\" }\n    y := match user {\n        { Missing: value } => value,\n        _ => \"unknown\"\n    }\n\n    n := 1\n    z := match n {\n        [first, ..] => first,\n        _ => 0\n    }\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "9/0/0"
    assert PgCount(response) == 9
    assert PgCensus(response) == "NL001@14:5+1;NL503@15:9+14;NL503@16:26+7;NL301@16:46+5;NL001@21:5+1;NL503@22:11+7;NL301@22:31+5;NL001@27:5+1;NL504@28:9+11;"
    assert PgRow(response, 0) == "NL001|error|Variable 'x' is declared but never read|Program.nl|14|5|1"
    assert PgDetail(response, 0) == "    x := match r {|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_x'|<null>"
    assert PgRow(response, 1) == "NL503|error|'Result.Unknown' is not a case of union 'Result' — check the union definition for available cases|Program.nl|15|9|14"
    assert PgDetail(response, 1) == "        Result.Unknown => 0,|<null>|<null>|<null>"
    assert PgRow(response, 2) == "NL503|error|Union case 'Success' doesn't have a property named 'missing' — check the case definition for available properties|Program.nl|16|26|7"
    assert PgDetail(response, 2) == "        Result.Success { missing: value } => value,|<null>|<null>|<null>"
    assert PgRow(response, 3) == "NL301|error|Variable 'value' not found|Program.nl|16|46|5"
    assert PgDetail(response, 3) == "        Result.Success { missing: value } => value,|I cannot find a `value` variable on line 16:|<null>|Make sure you've declared this variable before using it."
    assert PgRow(response, 4) == "NL001|error|Variable 'y' is declared but never read|Program.nl|21|5|1"
    assert PgDetail(response, 4) == "    y := match user {|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_y'|<null>"
    assert PgRow(response, 5) == "NL503|error|'User' doesn't have a property named 'Missing'|Program.nl|22|11|7"
    assert PgDetail(response, 5) == "        { Missing: value } => value,|<null>|<null>|<null>"
    assert PgRow(response, 6) == "NL301|error|Variable 'value' not found|Program.nl|22|31|5"
    assert PgDetail(response, 6) == "        { Missing: value } => value,|I cannot find a `value` variable on line 22:|<null>|Make sure you've declared this variable before using it."
    assert PgRow(response, 7) == "NL001|error|Variable 'z' is declared but never read|Program.nl|27|5|1"
    assert PgDetail(response, 7) == "    z := match n {|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_z'|<null>"
    assert PgRow(response, 8) == "NL504|error|A list pattern can only match arrays or indexable collections, but this value is 'int'|Program.nl|28|9|11"
    assert PgDetail(response, 8) == "        [first, ..] => first,|<null>|<null>|<null>"
    assert PgRow(response, 9) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 9
    assert PgCensus(other) == "NL001@14:5+1;NL503@15:9+14;NL503@16:26+7;NL301@16:46+5;NL001@21:5+1;NL503@22:11+7;NL301@22:31+5;NL001@27:5+1;NL504@28:9+11;"
    assert PgRow(other, 0) == "NL001|error|Variable 'x' is declared but never read|Program.tests.nl|14|5|1"
    assert PgRow(other, 1) == "NL503|error|'Result.Unknown' is not a case of union 'Result' — check the union definition for available cases|Program.tests.nl|15|9|14"
    assert PgRow(other, 2) == "NL503|error|Union case 'Success' doesn't have a property named 'missing' — check the case definition for available properties|Program.tests.nl|16|26|7"
    assert PgRow(other, 3) == "NL301|error|Variable 'value' not found|Program.tests.nl|16|46|5"
    assert PgRow(other, 4) == "NL001|error|Variable 'y' is declared but never read|Program.tests.nl|21|5|1"
    assert PgRow(other, 5) == "NL503|error|'User' doesn't have a property named 'Missing'|Program.tests.nl|22|11|7"
    assert PgRow(other, 6) == "NL301|error|Variable 'value' not found|Program.tests.nl|22|31|5"
    assert PgRow(other, 7) == "NL001|error|Variable 'z' is declared but never read|Program.tests.nl|27|5|1"
    assert PgRow(other, 8) == "NL504|error|A list pattern can only match arrays or indexable collections, but this value is 'int'|Program.tests.nl|28|9|11"
}

test "020 s37 playground diagnostic spans: Check DeclarationErrors PreserveDeclarationNameSpans — NL306@5:6+9;NL306@8:7+5;NL306@12:5+7;NL306@17:5+7;NL407@20:23+4;NL012@20:23+4;NL012@20:36+4;NL012@22:18+5;NL409@22:34+6;NL012@22:34+6;NL012@24:17+5;NL410@24:30+9;NL306@28:5+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_DeclarationErrors_PreserveDeclarationNameSpans)" {
    source := "package Playground\n\nfunc Duplicate(value: int): int { return value }\n\nfunc Duplicate(value: int): int { return value }\n\nclass Thing {}\nclass Thing {}\n\nenum Status {\n    Pending,\n    Pending\n}\n\nunion Result {\n    Success\n    Success\n}\n\nfunc BadParams(params rest: int[], tail: int) {}\n\nfunc BadOrdering(first: int = 1, second: int) {}\n\nfunc BadDefault(value: int = makeValue()) {}\n\nfunc main() {\n    value := 1\n    value := 2\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "13/0/0"
    assert PgCount(response) == 13
    assert PgCensus(response) == "NL306@5:6+9;NL306@8:7+5;NL306@12:5+7;NL306@17:5+7;NL407@20:23+4;NL012@20:23+4;NL012@20:36+4;NL012@22:18+5;NL409@22:34+6;NL012@22:34+6;NL012@24:17+5;NL410@24:30+9;NL306@28:5+5;"
    assert PgRow(response, 0) == "NL306|error|'Duplicate' is already declared in this scope — each name must be unique within the same scope|Program.nl|5|6|9"
    assert PgDetail(response, 0) == "func Duplicate(value: int): int { return value }|<null>|<null>|<null>"
    assert PgRow(response, 1) == "NL306|error|A type named 'Thing' already exists — each type name must be unique|Program.nl|8|7|5"
    assert PgDetail(response, 1) == "class Thing {}|<null>|<null>|<null>"
    assert PgRow(response, 2) == "NL306|error|Duplicate enum member 'Pending'|Program.nl|12|5|7"
    assert PgDetail(response, 2) == "    Pending|I found a duplicate enum member named `Pending` on line 12:|<null>|The name `Pending` is already defined. Each enum member must have a unique name\nwithin its scope. Rename one of the declarations to fix this."
    assert PgRow(response, 3) == "NL306|error|Duplicate union case 'Success'|Program.nl|17|5|7"
    assert PgDetail(response, 3) == "    Success|I found a duplicate union case named `Success` on line 17:|<null>|The name `Success` is already defined. Each union case must have a unique name\nwithin its scope. Rename one of the declarations to fix this."
    assert PgRow(response, 4) == "NL407|error|A 'params' parameter must come last in the parameter list — move it to the end|Program.nl|20|23|4"
    assert PgDetail(response, 4) == "func BadParams(params rest: int[], tail: int) {}|<null>|<null>|<null>"
    assert PgRow(response, 5) == "NL012|error|Parameter 'rest' in 'BadParams' is never read — is it needed?|Program.nl|20|23|4"
    assert PgDetail(response, 5) == "func BadParams(params rest: int[], tail: int) {}|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_rest'|<null>"
    assert PgRow(response, 6) == "NL012|error|Parameter 'tail' in 'BadParams' is never read — is it needed?|Program.nl|20|36|4"
    assert PgDetail(response, 6) == "func BadParams(params rest: int[], tail: int) {}|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_tail'|<null>"
    assert PgRow(response, 7) == "NL012|error|Parameter 'first' in 'BadOrdering' is never read — is it needed?|Program.nl|22|18|5"
    assert PgDetail(response, 7) == "func BadOrdering(first: int = 1, second: int) {}|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_first'|<null>"
    assert PgRow(response, 8) == "NL409|error|Required parameter 'second' can't come after optional parameters — move it before the optional ones, or give it a default value too|Program.nl|22|34|6"
    assert PgDetail(response, 8) == "func BadOrdering(first: int = 1, second: int) {}|<null>|<null>|<null>"
    assert PgRow(response, 9) == "NL012|error|Parameter 'second' in 'BadOrdering' is never read — is it needed?|Program.nl|22|34|6"
    assert PgDetail(response, 9) == "func BadOrdering(first: int = 1, second: int) {}|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_second'|<null>"
    assert PgRow(response, 10) == "NL012|error|Parameter 'value' in 'BadDefault' is never read — is it needed?|Program.nl|24|17|5"
    assert PgDetail(response, 10) == "func BadDefault(value: int = makeValue()) {}|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_value'|<null>"
    assert PgRow(response, 11) == "NL410|error|The default value for 'value' must be something the compiler can evaluate — use a literal, null, or a simple constant|Program.nl|24|30|9"
    assert PgDetail(response, 11) == "func BadDefault(value: int = makeValue()) {}|<null>|<null>|<null>"
    assert PgRow(response, 12) == "NL306|error|'value' is already declared in this scope — each name must be unique within the same scope|Program.nl|28|5|5"
    assert PgDetail(response, 12) == "    value := 2|<null>|<null>|<null>"
    assert PgRow(response, 13) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 13
    assert PgCensus(other) == "NL306@5:6+9;NL306@8:7+5;NL306@12:5+7;NL306@17:5+7;NL407@20:23+4;NL012@20:23+4;NL012@20:36+4;NL012@22:18+5;NL409@22:34+6;NL012@22:34+6;NL012@24:17+5;NL410@24:30+9;NL306@28:5+5;"
    assert PgRow(other, 0) == "NL306|error|'Duplicate' is already declared in this scope — each name must be unique within the same scope|Program.tests.nl|5|6|9"
    assert PgRow(other, 1) == "NL306|error|A type named 'Thing' already exists — each type name must be unique|Program.tests.nl|8|7|5"
    assert PgRow(other, 2) == "NL306|error|Duplicate enum member 'Pending'|Program.tests.nl|12|5|7"
    assert PgRow(other, 3) == "NL306|error|Duplicate union case 'Success'|Program.tests.nl|17|5|7"
    assert PgRow(other, 4) == "NL407|error|A 'params' parameter must come last in the parameter list — move it to the end|Program.tests.nl|20|23|4"
    assert PgRow(other, 5) == "NL012|error|Parameter 'rest' in 'BadParams' is never read — is it needed?|Program.tests.nl|20|23|4"
    assert PgRow(other, 6) == "NL012|error|Parameter 'tail' in 'BadParams' is never read — is it needed?|Program.tests.nl|20|36|4"
    assert PgRow(other, 7) == "NL012|error|Parameter 'first' in 'BadOrdering' is never read — is it needed?|Program.tests.nl|22|18|5"
    assert PgRow(other, 8) == "NL409|error|Required parameter 'second' can't come after optional parameters — move it before the optional ones, or give it a default value too|Program.tests.nl|22|34|6"
    assert PgRow(other, 9) == "NL012|error|Parameter 'second' in 'BadOrdering' is never read — is it needed?|Program.tests.nl|22|34|6"
    assert PgRow(other, 10) == "NL012|error|Parameter 'value' in 'BadDefault' is never read — is it needed?|Program.tests.nl|24|17|5"
    assert PgRow(other, 11) == "NL410|error|The default value for 'value' must be something the compiler can evaluate — use a literal, null, or a simple constant|Program.tests.nl|24|30|9"
    assert PgRow(other, 12) == "NL306|error|'value' is already declared in this scope — each name must be unique within the same scope|Program.tests.nl|28|5|5"
}

test "020 s37 playground diagnostic spans: Check OperatorOverloadErrors PreserveOperatorKeywordAndSymbolSpans — NL601@6:10+8;NL602@6:19+1;NL012@6:32+1;NL012@6:43+1;NL602@10:26+4;NL012@10:31+1;NL012@10:42+1;, and the test-file route agrees (was PlaygroundCompilerTests.Check_OperatorOverloadErrors_PreserveOperatorKeywordAndSymbolSpans)" {
    source := "package Playground\n\nclass Vector {\n    X: int\n\n    func operator %(a: Vector, b: Vector, c: Vector): Vector {\n        return a\n    }\n\n    static func operator true(a: Vector, b: Vector): bool {\n        return true\n    }\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "7/0/0"
    assert PgCount(response) == 7
    assert PgCensus(response) == "NL601@6:10+8;NL602@6:19+1;NL012@6:32+1;NL012@6:43+1;NL602@10:26+4;NL012@10:31+1;NL012@10:42+1;"
    assert PgRow(response, 0) == "NL601|error|Operator overloads must be declared 'static' — they don't belong to a specific instance|Program.nl|6|10|8"
    assert PgDetail(response, 0) == "    func operator %(a: Vector, b: Vector, c: Vector): Vector {|<null>|Operators must be public static and have correct parameter types|<null>"
    assert PgRow(response, 1) == "NL602|error|Operator '%' requires exactly 2 parameter(s), but you declared 3|Program.nl|6|19|1"
    assert PgDetail(response, 1) == "    func operator %(a: Vector, b: Vector, c: Vector): Vector {|<null>|<null>|<null>"
    assert PgRow(response, 2) == "NL012|error|Parameter 'b' in 'operator %' is never read — is it needed?|Program.nl|6|32|1"
    assert PgDetail(response, 2) == "    func operator %(a: Vector, b: Vector, c: Vector): Vector {|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_b'|<null>"
    assert PgRow(response, 3) == "NL012|error|Parameter 'c' in 'operator %' is never read — is it needed?|Program.nl|6|43|1"
    assert PgDetail(response, 3) == "    func operator %(a: Vector, b: Vector, c: Vector): Vector {|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_c'|<null>"
    assert PgRow(response, 4) == "NL602|error|Operator 'true' requires exactly 1 parameter(s), but you declared 2|Program.nl|10|26|4"
    assert PgDetail(response, 4) == "    static func operator true(a: Vector, b: Vector): bool {|<null>|<null>|<null>"
    assert PgRow(response, 5) == "NL012|error|Parameter 'a' in 'operator true' is never read — is it needed?|Program.nl|10|31|1"
    assert PgDetail(response, 5) == "    static func operator true(a: Vector, b: Vector): bool {|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_a'|<null>"
    assert PgRow(response, 6) == "NL012|error|Parameter 'b' in 'operator true' is never read — is it needed?|Program.nl|10|42|1"
    assert PgDetail(response, 6) == "    static func operator true(a: Vector, b: Vector): bool {|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_b'|<null>"
    assert PgRow(response, 7) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 7
    assert PgCensus(other) == "NL601@6:10+8;NL602@6:19+1;NL012@6:32+1;NL012@6:43+1;NL602@10:26+4;NL012@10:31+1;NL012@10:42+1;"
    assert PgRow(other, 0) == "NL601|error|Operator overloads must be declared 'static' — they don't belong to a specific instance|Program.tests.nl|6|10|8"
    assert PgRow(other, 1) == "NL602|error|Operator '%' requires exactly 2 parameter(s), but you declared 3|Program.tests.nl|6|19|1"
    assert PgRow(other, 2) == "NL012|error|Parameter 'b' in 'operator %' is never read — is it needed?|Program.tests.nl|6|32|1"
    assert PgRow(other, 3) == "NL012|error|Parameter 'c' in 'operator %' is never read — is it needed?|Program.tests.nl|6|43|1"
    assert PgRow(other, 4) == "NL602|error|Operator 'true' requires exactly 1 parameter(s), but you declared 2|Program.tests.nl|10|26|4"
    assert PgRow(other, 5) == "NL012|error|Parameter 'a' in 'operator true' is never read — is it needed?|Program.tests.nl|10|31|1"
    assert PgRow(other, 6) == "NL012|error|Parameter 'b' in 'operator true' is never read — is it needed?|Program.tests.nl|10|42|1"
}

test "020 s37 playground diagnostic spans: Check DuplicateTestLifecycleBlocks PreserveFullKeywordSpans — NL001@2:5+5;NL306@5:1+5;NL001@6:5+6;NL306@13:1+8;, and the string route agrees (was PlaygroundCompilerTests.Check_DuplicateTestLifecycleBlocks_PreserveFullKeywordSpans)" {
    response := PgCheckProject1("Program.tests.nl", "setup {\n    first := 1\n}\n\nsetup {\n    second := 2\n}\n\nteardown {\n    Cleanup()\n}\n\nteardown {\n    CleanupAgain()\n}\n\nfunc Cleanup() {}\nfunc CleanupAgain() {}\n\ntest \"works\" {\n    assert true\n}", "Program.tests.nl")
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.tests.nl"
    assert PgSummary(response) == "4/0/0"
    assert PgCount(response) == 4
    assert PgCensus(response) == "NL001@2:5+5;NL306@5:1+5;NL001@6:5+6;NL306@13:1+8;"
    assert PgRow(response, 0) == "NL001|error|Variable 'first' is declared but never read|Program.tests.nl|2|5|5"
    assert PgDetail(response, 0) == "    first := 1|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_first'|<null>"
    assert PgRow(response, 1) == "NL306|error|Only one setup block is allowed per test file|Program.tests.nl|5|1|5"
    assert PgDetail(response, 1) == "setup {|<null>|<null>|<null>"
    assert PgRow(response, 2) == "NL001|error|Variable 'second' is declared but never read|Program.tests.nl|6|5|6"
    assert PgDetail(response, 2) == "    second := 2|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_second'|<null>"
    assert PgRow(response, 3) == "NL306|error|Only one teardown block is allowed per test file|Program.tests.nl|13|1|8"
    assert PgDetail(response, 3) == "teardown {|<null>|<null>|<null>"
    assert PgRow(response, 4) == "<no-such-diagnostic>"
    other := PgCheck("setup {\n    first := 1\n}\n\nsetup {\n    second := 2\n}\n\nteardown {\n    Cleanup()\n}\n\nteardown {\n    CleanupAgain()\n}\n\nfunc Cleanup() {}\nfunc CleanupAgain() {}\n\ntest \"works\" {\n    assert true\n}")
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.nl"
    assert PgCount(other) == 4
    assert PgCensus(other) == "NL001@2:5+5;NL306@5:1+5;NL001@6:5+6;NL306@13:1+8;"
    assert PgRow(other, 0) == "NL001|error|Variable 'first' is declared but never read|Program.nl|2|5|5"
    assert PgRow(other, 1) == "NL306|error|Only one setup block is allowed per test file|Program.nl|5|1|5"
    assert PgRow(other, 2) == "NL001|error|Variable 'second' is declared but never read|Program.nl|6|5|6"
    assert PgRow(other, 3) == "NL306|error|Only one teardown block is allowed per test file|Program.nl|13|1|8"
}

test "020 s37 playground diagnostic spans: Check ObjectInitializerMissingValue PreservesPropertyNameSpanForMarkers — NL102@8:24+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_ObjectInitializerMissingValue_PreservesPropertyNameSpanForMarkers)" {
    source := "package Playground\n\nclass User {\n    Name: string\n}\n\nfunc main() {\n    user := new User { Name: }\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@8:24+4;"
    assert PgRow(response, 0) == "NL102|error|Expected a value for object initializer member 'Name'|Program.nl|8|24|4"
    assert PgDetail(response, 0) == "    user := new User { Name: }|Object initializer member 'Name' needs a value after ':'.|Add a value after 'Name:'|Write 'Name: value'."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@8:24+4;"
    assert PgRow(other, 0) == "NL102|error|Expected a value for object initializer member 'Name'|Program.tests.nl|8|24|4"
}

test "020 s37 playground diagnostic spans: Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers — NL102@3:1+4;NL903@3:1+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingDeclarationName_PreservesDeclarationKeywordSpanForMarkers InlineData row 0)" {
    source := "package Playground\n\nfunc () {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@3:1+4;NL903@3:1+7;"
    assert PgRow(response, 0) == "NL102|error|Expected function name. Got '('|Program.nl|3|1|4"
    assert PgDetail(response, 0) == "func () {|I was expecting an identifier here, but I found '(' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.nl|3|1|7"
    assert PgDetail(response, 1) == "func () {|<null>|Use PascalCase for public members or camelCase for private members|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@3:1+4;NL903@3:1+7;"
    assert PgRow(other, 0) == "NL102|error|Expected function name. Got '('|Program.tests.nl|3|1|4"
    assert PgRow(other, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.tests.nl|3|1|7"
}

test "020 s37 playground diagnostic spans: Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers — NL102@3:1+5;NL903@3:1+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingDeclarationName_PreservesDeclarationKeywordSpanForMarkers InlineData row 1)" {
    source := "package Playground\n\nclass {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@3:1+5;NL903@3:1+7;"
    assert PgRow(response, 0) == "NL102|error|Expected class name. Got '{'|Program.nl|3|1|5"
    assert PgDetail(response, 0) == "class {|I was expecting an identifier here, but I found '{' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.nl|3|1|7"
    assert PgDetail(response, 1) == "class {|<null>|Use PascalCase for public members or camelCase for private members|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@3:1+5;NL903@3:1+7;"
    assert PgRow(other, 0) == "NL102|error|Expected class name. Got '{'|Program.tests.nl|3|1|5"
    assert PgRow(other, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.tests.nl|3|1|7"
}

test "020 s37 playground diagnostic spans: Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers — NL102@3:1+6;NL903@3:1+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingDeclarationName_PreservesDeclarationKeywordSpanForMarkers InlineData row 2)" {
    source := "package Playground\n\nstruct {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@3:1+6;NL903@3:1+7;"
    assert PgRow(response, 0) == "NL102|error|Expected struct name. Got '{'|Program.nl|3|1|6"
    assert PgDetail(response, 0) == "struct {|I was expecting an identifier here, but I found '{' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.nl|3|1|7"
    assert PgDetail(response, 1) == "struct {|<null>|Use PascalCase for public members or camelCase for private members|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@3:1+6;NL903@3:1+7;"
    assert PgRow(other, 0) == "NL102|error|Expected struct name. Got '{'|Program.tests.nl|3|1|6"
    assert PgRow(other, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.tests.nl|3|1|7"
}

test "020 s37 playground diagnostic spans: Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers — NL102@3:1+6;NL903@3:1+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingDeclarationName_PreservesDeclarationKeywordSpanForMarkers InlineData row 3)" {
    source := "package Playground\n\nrecord {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@3:1+6;NL903@3:1+7;"
    assert PgRow(response, 0) == "NL102|error|Expected record name. Got '{'|Program.nl|3|1|6"
    assert PgDetail(response, 0) == "record {|I was expecting an identifier here, but I found '{' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.nl|3|1|7"
    assert PgDetail(response, 1) == "record {|<null>|Use PascalCase for public members or camelCase for private members|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@3:1+6;NL903@3:1+7;"
    assert PgRow(other, 0) == "NL102|error|Expected record name. Got '{'|Program.tests.nl|3|1|6"
    assert PgRow(other, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.tests.nl|3|1|7"
}

test "020 s37 playground diagnostic spans: Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers — NL102@3:1+9;NL903@3:1+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingDeclarationName_PreservesDeclarationKeywordSpanForMarkers InlineData row 4)" {
    source := "package Playground\n\ninterface {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@3:1+9;NL903@3:1+7;"
    assert PgRow(response, 0) == "NL102|error|Expected interface name. Got '{'|Program.nl|3|1|9"
    assert PgDetail(response, 0) == "interface {|I was expecting an identifier here, but I found '{' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.nl|3|1|7"
    assert PgDetail(response, 1) == "interface {|<null>|Use PascalCase for public members or camelCase for private members|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@3:1+9;NL903@3:1+7;"
    assert PgRow(other, 0) == "NL102|error|Expected interface name. Got '{'|Program.tests.nl|3|1|9"
    assert PgRow(other, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.tests.nl|3|1|7"
}

test "020 s37 playground diagnostic spans: Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers — NL102@3:1+5;NL903@3:1+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingDeclarationName_PreservesDeclarationKeywordSpanForMarkers InlineData row 5)" {
    source := "package Playground\n\nunion {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@3:1+5;NL903@3:1+7;"
    assert PgRow(response, 0) == "NL102|error|Expected union name. Got '{'|Program.nl|3|1|5"
    assert PgDetail(response, 0) == "union {|I was expecting an identifier here, but I found '{' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.nl|3|1|7"
    assert PgDetail(response, 1) == "union {|<null>|Use PascalCase for public members or camelCase for private members|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@3:1+5;NL903@3:1+7;"
    assert PgRow(other, 0) == "NL102|error|Expected union name. Got '{'|Program.tests.nl|3|1|5"
    assert PgRow(other, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.tests.nl|3|1|7"
}

test "020 s37 playground diagnostic spans: Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers — NL102@3:1+4;NL903@3:1+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingDeclarationName_PreservesDeclarationKeywordSpanForMarkers InlineData row 6)" {
    source := "package Playground\n\nenum {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@3:1+4;NL903@3:1+7;"
    assert PgRow(response, 0) == "NL102|error|Expected enum name. Got '{'|Program.nl|3|1|4"
    assert PgDetail(response, 0) == "enum {|I was expecting an identifier here, but I found '{' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.nl|3|1|7"
    assert PgDetail(response, 1) == "enum {|<null>|Use PascalCase for public members or camelCase for private members|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@3:1+4;NL903@3:1+7;"
    assert PgRow(other, 0) == "NL102|error|Expected enum name. Got '{'|Program.tests.nl|3|1|4"
    assert PgRow(other, 1) == "NL903|error|Identifier '<error>' starts with a non-letter character — in N#, PascalCase means public and camelCase means private|Program.tests.nl|3|1|7"
}

test "020 s37 playground diagnostic spans: Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers — NL102@3:1+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingDeclarationName_PreservesDeclarationKeywordSpanForMarkers InlineData row 7)" {
    source := "package Playground\n\ntype = int"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@3:1+4;"
    assert PgRow(response, 0) == "NL102|error|Expected type alias name. Got '='|Program.nl|3|1|4"
    assert PgDetail(response, 0) == "type = int|I was expecting an identifier here, but I found '=' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@3:1+4;"
    assert PgRow(other, 0) == "NL102|error|Expected type alias name. Got '='|Program.tests.nl|3|1|4"
}

test "020 s37 playground diagnostic spans: Check MalformedParameterLists PreserveVisibleTokenSpansForMarkers — NL012@3:11+1;NL102@3:13+6;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MalformedParameterLists_PreserveVisibleTokenSpansForMarkers InlineData row 0)" {
    source := "package Playground\n\nfunc main(: string) {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL012@3:11+1;NL102@3:13+6;"
    assert PgRow(response, 0) == "NL012|error|Parameter '<error>' in 'main' is never read — is it needed?|Program.nl|3|11|1"
    assert PgDetail(response, 0) == "func main(: string) {|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_<error>'|<null>"
    assert PgRow(response, 1) == "NL102|error|Expected parameter name. Got ':'|Program.nl|3|13|6"
    assert PgDetail(response, 1) == "func main(: string) {|I was expecting an identifier here, but I found ':' instead.|<null>|An identifier is a name for a variable, function, or type."
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL012@3:11+1;NL102@3:13+6;"
    assert PgRow(other, 0) == "NL012|error|Parameter '<error>' in 'main' is never read — is it needed?|Program.tests.nl|3|11|1"
    assert PgRow(other, 1) == "NL102|error|Expected parameter name. Got ':'|Program.tests.nl|3|13|6"
}

test "020 s37 playground diagnostic spans: Check MalformedParameterLists PreserveVisibleTokenSpansForMarkers — NL102@3:11+4;NL201@3:11+7;NL012@3:11+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MalformedParameterLists_PreserveVisibleTokenSpansForMarkers InlineData row 1)" {
    source := "package Playground\n\nfunc main(name:) {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "3/0/0"
    assert PgCount(response) == 3
    assert PgCensus(response) == "NL102@3:11+4;NL201@3:11+7;NL012@3:11+4;"
    assert PgRow(response, 0) == "NL102|error|Expected type name. Got ')'|Program.nl|3|11|4"
    assert PgDetail(response, 0) == "func main(name:) {|Parameter 'name' needs a type after ':'.|Add a parameter type after ':'|Write this parameter as `name: Type`."
    assert PgRow(response, 1) == "NL201|error|Type '<error>' not found|Program.nl|3|11|7"
    assert PgDetail(response, 1) == "func main(name:) {|<null>|Check the spelling, add the missing 'import', or add the package/project reference that provides '<error>'.|<null>"
    assert PgRow(response, 2) == "NL012|error|Parameter 'name' in 'main' is never read — is it needed?|Program.nl|3|11|4"
    assert PgDetail(response, 2) == "func main(name:) {|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_name'|<null>"
    assert PgRow(response, 3) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 3
    assert PgCensus(other) == "NL102@3:11+4;NL201@3:11+7;NL012@3:11+4;"
    assert PgRow(other, 0) == "NL102|error|Expected type name. Got ')'|Program.tests.nl|3|11|4"
    assert PgRow(other, 1) == "NL201|error|Type '<error>' not found|Program.tests.nl|3|11|7"
    assert PgRow(other, 2) == "NL012|error|Parameter 'name' in 'main' is never read — is it needed?|Program.tests.nl|3|11|4"
}

test "020 s37 playground diagnostic spans: Check MalformedParameterLists PreserveVisibleTokenSpansForMarkers — NL102@3:11+13;NL012@3:11+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MalformedParameterLists_PreserveVisibleTokenSpansForMarkers InlineData row 2)" {
    source := "package Playground\n\nfunc main(name: string, ) {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@3:11+13;NL012@3:11+4;"
    assert PgRow(response, 0) == "NL102|error|Expected parameter name. Got ')'|Program.nl|3|11|13"
    assert PgDetail(response, 0) == "func main(name: string, ) {|Parameter lists need another parameter after a comma.|Add a parameter after the comma|Add the missing parameter after the comma, or remove the trailing comma."
    assert PgRow(response, 1) == "NL012|error|Parameter 'name' in 'main' is never read — is it needed?|Program.nl|3|11|4"
    assert PgDetail(response, 1) == "func main(name: string, ) {|<null>|If the parameter is required by an interface or override, prefix with '_' to suppress this: '_name'|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@3:11+13;NL012@3:11+4;"
    assert PgRow(other, 0) == "NL102|error|Expected parameter name. Got ')'|Program.tests.nl|3|11|13"
    assert PgRow(other, 1) == "NL012|error|Parameter 'name' in 'main' is never read — is it needed?|Program.tests.nl|3|11|4"
}

test "020 s37 playground diagnostic spans: Check MalformedParameterLists PreserveVisibleTokenSpansForMarkers — NL102@3:10+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MalformedParameterLists_PreserveVisibleTokenSpansForMarkers InlineData row 3)" {
    source := "package Playground\n\nfunc main<T,>() {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@3:10+4;"
    assert PgRow(response, 0) == "NL102|error|Expected type parameter name. Got '>'|Program.nl|3|10|4"
    assert PgDetail(response, 0) == "func main<T,>() {|Generic parameter lists need a type parameter name after each comma.|Add a type parameter name|Write generic parameters as `<T>` or `<T, U>`."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@3:10+4;"
    assert PgRow(other, 0) == "NL102|error|Expected type parameter name. Got '>'|Program.tests.nl|3|10|4"
}

test "020 s37 playground diagnostic spans: Check MalformedParameterLists PreserveVisibleTokenSpansForMarkers — NL102@3:10+2;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MalformedParameterLists_PreserveVisibleTokenSpansForMarkers InlineData row 4)" {
    source := "package Playground\n\nclass Box<> {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@3:10+2;"
    assert PgRow(response, 0) == "NL102|error|Expected type parameter name. Got '>'|Program.nl|3|10|2"
    assert PgDetail(response, 0) == "class Box<> {|Generic parameter lists need a type parameter name after each comma.|Add a type parameter name|Write generic parameters as `<T>` or `<T, U>`."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@3:10+2;"
    assert PgRow(other, 0) == "NL102|error|Expected type parameter name. Got '>'|Program.tests.nl|3|10|2"
}

test "020 s37 playground diagnostic spans: Check AdditionalMalformedConstructs PreserveVisibleTokenSpansForMarkers — NL102@4:5+4;NL201@4:5+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_AdditionalMalformedConstructs_PreserveVisibleTokenSpansForMarkers InlineData row 0)" {
    source := "package Playground\n\nclass User {\n    Name:\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@4:5+4;NL201@4:5+7;"
    assert PgRow(response, 0) == "NL102|error|Expected type name. Got '}'|Program.nl|4|5|4"
    assert PgDetail(response, 0) == "    Name:|Field 'Name' needs a type after ':'.|Add a field type after ':'|Write this field as `Name: Type`."
    assert PgRow(response, 1) == "NL201|error|Type '<error>' not found|Program.nl|4|5|7"
    assert PgDetail(response, 1) == "    Name:|<null>|Check the spelling, add the missing 'import', or add the package/project reference that provides '<error>'.|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@4:5+4;NL201@4:5+7;"
    assert PgRow(other, 0) == "NL102|error|Expected type name. Got '}'|Program.tests.nl|4|5|4"
    assert PgRow(other, 1) == "NL201|error|Type '<error>' not found|Program.tests.nl|4|5|7"
}

test "020 s37 playground diagnostic spans: Check AdditionalMalformedConstructs PreserveVisibleTokenSpansForMarkers — NL102@4:12+6;NL207@4:12+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_AdditionalMalformedConstructs_PreserveVisibleTokenSpansForMarkers InlineData row 1)" {
    source := "package Playground\n\nclass User {\n    Items: List<>\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@4:12+6;NL207@4:12+4;"
    assert PgRow(response, 0) == "NL102|error|Expected type name. Got '>'|Program.nl|4|12|6"
    assert PgDetail(response, 0) == "    Items: List<>|Generic type 'List' needs a type argument between '<' and '>'.|Add a type argument|Write this type as `List<T>` or remove the generic argument list."
    assert PgRow(response, 1) == "NL207|error|Generic type 'List' takes 1 type argument(s), but 0 were provided|Program.nl|4|12|4"
    assert PgDetail(response, 1) == "    Items: List<>|<null>|Match the declaration's type parameter count for 'List'|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@4:12+6;NL207@4:12+4;"
    assert PgRow(other, 0) == "NL102|error|Expected type name. Got '>'|Program.tests.nl|4|12|6"
    assert PgRow(other, 1) == "NL207|error|Generic type 'List' takes 1 type argument(s), but 0 were provided|Program.tests.nl|4|12|4"
}

test "020 s37 playground diagnostic spans: Check AdditionalMalformedConstructs PreserveVisibleTokenSpansForMarkers — NL001@4:5+5;NL102@4:14+3;NL201@4:14+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_AdditionalMalformedConstructs_PreserveVisibleTokenSpansForMarkers InlineData row 2)" {
    source := "package Playground\n\nfunc main() {\n    value := new\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "3/0/0"
    assert PgCount(response) == 3
    assert PgCensus(response) == "NL001@4:5+5;NL102@4:14+3;NL201@4:14+7;"
    assert PgRow(response, 0) == "NL001|error|Variable 'value' is declared but never read|Program.nl|4|5|5"
    assert PgDetail(response, 0) == "    value := new|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_value'|<null>"
    assert PgRow(response, 1) == "NL102|error|Expected type name. Got '}'|Program.nl|4|14|3"
    assert PgDetail(response, 1) == "    value := new|The `new` expression needs a type name, `()`, or an initializer after it.|Add a type name after `new`|Write `new TypeName(...)`, `new()`, or `new { Name: value }`."
    assert PgRow(response, 2) == "NL201|error|Type '<error>' not found|Program.nl|4|14|7"
    assert PgDetail(response, 2) == "    value := new|<null>|Check the spelling, add the missing 'import', or add the package/project reference that provides '<error>'.|<null>"
    assert PgRow(response, 3) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 3
    assert PgCensus(other) == "NL001@4:5+5;NL102@4:14+3;NL201@4:14+7;"
    assert PgRow(other, 0) == "NL001|error|Variable 'value' is declared but never read|Program.tests.nl|4|5|5"
    assert PgRow(other, 1) == "NL102|error|Expected type name. Got '}'|Program.tests.nl|4|14|3"
    assert PgRow(other, 2) == "NL201|error|Type '<error>' not found|Program.tests.nl|4|14|7"
}

test "020 s37 playground diagnostic spans: Check AdditionalMalformedConstructs PreserveVisibleTokenSpansForMarkers — NL102@7:24+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_AdditionalMalformedConstructs_PreserveVisibleTokenSpansForMarkers InlineData row 3)" {
    source := "package Playground\n\nclass User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@7:24+4;"
    assert PgRow(response, 0) == "NL102|error|Expected ':' after object initializer member 'Name'|Program.nl|7|24|4"
    assert PgDetail(response, 0) == "    user := new User { Name }|Object initializer member 'Name' needs ':' before its value.|Add ':' after 'Name'|Write 'Name: value'."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@7:24+4;"
    assert PgRow(other, 0) == "NL102|error|Expected ':' after object initializer member 'Name'|Program.tests.nl|7|24|4"
}

test "020 s37 playground diagnostic spans: Check MissingFieldTypeBeforeNextField PreservesBothOwningSpansForMarkers — NL102@4:5+4;NL201@4:5+7;NL102@5:12+6;NL207@5:12+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingFieldTypeBeforeNextField_PreservesBothOwningSpansForMarkers)" {
    source := "package Playground\n\nclass User {\n    Name:\n    Items: List<>\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "4/0/0"
    assert PgCount(response) == 4
    assert PgCensus(response) == "NL102@4:5+4;NL201@4:5+7;NL102@5:12+6;NL207@5:12+4;"
    assert PgRow(response, 0) == "NL102|error|Expected type name. Got 'Items'|Program.nl|4|5|4"
    assert PgDetail(response, 0) == "    Name:|Field 'Name' needs a type after ':'.|Add a field type after ':'|Write this field as `Name: Type`."
    assert PgRow(response, 1) == "NL201|error|Type '<error>' not found|Program.nl|4|5|7"
    assert PgDetail(response, 1) == "    Name:|<null>|Check the spelling, add the missing 'import', or add the package/project reference that provides '<error>'.|<null>"
    assert PgRow(response, 2) == "NL102|error|Expected type name. Got '>'|Program.nl|5|12|6"
    assert PgDetail(response, 2) == "    Items: List<>|Generic type 'List' needs a type argument between '<' and '>'.|Add a type argument|Write this type as `List<T>` or remove the generic argument list."
    assert PgRow(response, 3) == "NL207|error|Generic type 'List' takes 1 type argument(s), but 0 were provided|Program.nl|5|12|4"
    assert PgDetail(response, 3) == "    Items: List<>|<null>|Match the declaration's type parameter count for 'List'|<null>"
    assert PgRow(response, 4) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 4
    assert PgCensus(other) == "NL102@4:5+4;NL201@4:5+7;NL102@5:12+6;NL207@5:12+4;"
    assert PgRow(other, 0) == "NL102|error|Expected type name. Got 'Items'|Program.tests.nl|4|5|4"
    assert PgRow(other, 1) == "NL201|error|Type '<error>' not found|Program.tests.nl|4|5|7"
    assert PgRow(other, 2) == "NL102|error|Expected type name. Got '>'|Program.tests.nl|5|12|6"
    assert PgRow(other, 3) == "NL207|error|Generic type 'List' takes 1 type argument(s), but 0 were provided|Program.tests.nl|5|12|4"
}

test "020 s37 playground diagnostic spans: Check IncompleteMemberAccessBeforeCall PreservesReceiverSpan — NL102@5:5+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_IncompleteMemberAccessBeforeCall_PreservesReceiverSpan)" {
    source := "package Playground\n\nfunc main() {\n    name := \"Ada\"\n    name.()\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@5:5+4;"
    assert PgRow(response, 0) == "NL102|error|Expected member name. Got '('|Program.nl|5|5|4"
    assert PgDetail(response, 0) == "    name.()|I see a dot (.) operator but no member name after it.|Check if you forgot to finish this line|After dot (.), I need to see a property or method name."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@5:5+4;"
    assert PgRow(other, 0) == "NL102|error|Expected member name. Got '('|Program.tests.nl|5|5|4"
}

test "020 s37 playground diagnostic spans: Check MissingParameterColon PreservesParameterNameSpan — NL102@3:12+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingParameterColon_PreservesParameterNameSpan)" {
    source := "package Playground\n\nfunc greet(name string): string {\n    return name\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@3:12+4;"
    assert PgRow(response, 0) == "NL102|error|Expected ':' after parameter name. Got 'string'|Program.nl|3|12|4"
    assert PgDetail(response, 0) == "func greet(name string): string {|Parameter 'name' needs a ':' before its type.|Add ':' after 'name'|Write this parameter as `name: Type`."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@3:12+4;"
    assert PgRow(other, 0) == "NL102|error|Expected ':' after parameter name. Got 'string'|Program.tests.nl|3|12|4"
}

test "020 s37 playground diagnostic spans: Check MissingFieldColon PreservesFieldNameSpan — NL102@4:5+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingFieldColon_PreservesFieldNameSpan)" {
    source := "package Playground\n\nclass User {\n    Name string\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@4:5+4;"
    assert PgRow(response, 0) == "NL102|error|Expected ':' or ':=' after field name. Got 'string'|Program.nl|4|5|4"
    assert PgDetail(response, 0) == "    Name string|Field 'Name' needs a ':' before its type, or ':=' before an inferred initializer.|Add ':' after 'Name'|Write this field as `Name: Type` or `Name := value`."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@4:5+4;"
    assert PgRow(other, 0) == "NL102|error|Expected ':' or ':=' after field name. Got 'string'|Program.tests.nl|4|5|4"
}

test "020 s37 playground diagnostic spans: Check MissingFunctionReturnColon PreservesFunctionNameSpan — NL102@3:6+6;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingFunctionReturnColon_PreservesFunctionNameSpan)" {
    source := "package Playground\n\nfunc answer() int {\n    return 1\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@3:6+6;"
    assert PgRow(response, 0) == "NL102|error|Expected ':' before return type. Got 'int'|Program.nl|3|6|6"
    assert PgDetail(response, 0) == "func answer() int {|Function 'answer' needs a ':' before its return type.|Add ':' before 'int'|Write the return type as `func name(...): Type { ... }`."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@3:6+6;"
    assert PgRow(other, 0) == "NL102|error|Expected ':' before return type. Got 'int'|Program.tests.nl|3|6|6"
}

test "020 s37 playground diagnostic spans: Check DefaultParserSpan PreservesVisibleTokenSpan — NL101@3:14+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_DefaultParserSpan_PreservesVisibleTokenSpan)" {
    source := "package Playground\n\nenum Status: decimal {\n    Open\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL101@3:14+7;"
    assert PgRow(response, 0) == "NL101|error|Unsupported enum backing type 'decimal'. Only 'int' and 'string' are supported.|Program.nl|3|14|7"
    assert PgDetail(response, 0) == "enum Status: decimal {|<null>|<null>|<null>"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL101@3:14+7;"
    assert PgRow(other, 0) == "NL101|error|Unsupported enum backing type 'decimal'. Only 'int' and 'string' are supported.|Program.tests.nl|3|14|7"
}

test "020 s37 playground diagnostic spans: Check DefaultSemanticSpan PreservesVisibleTokenSpan — NL103@4:16+3;, and the test-file route agrees (was PlaygroundCompilerTests.Check_DefaultSemanticSpan_PreservesVisibleTokenSpan)" {
    source := "package Playground\n\nfunc main(): int {\n    let value: var = 42\n    return value\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL103@4:16+3;"
    assert PgRow(response, 0) == "NL103|error|'var' is not a type; use ':=' for type inference|Program.nl|4|16|3"
    assert PgDetail(response, 0) == "    let value: var = 42|<null>|<null>|<null>"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL103@4:16+3;"
    assert PgRow(other, 0) == "NL103|error|'var' is not a type; use ':=' for type inference|Program.tests.nl|4|16|3"
}

test "020 s37 playground diagnostic spans: Check MissingFileImport PreservesQuotedPathSpan — NL701@1:8+11;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingFileImport_PreservesQuotedPathSpan)" {
    source := "import \"./Missing\"\n\nfunc main() {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL701@1:8+11;"
    assert PgRow(response, 0) == "NL701|error|Cannot find import './Missing'|Program.nl|1|8|11"
    assert PgDetail(response, 0) == "import \"./Missing\"|I cannot find the file you're trying to import on line 1:|<null>|Make sure the file exists at the path './Missing'.\nThe path should be relative to your project root.\n\nCommon issues:\n  - Check for typos in the file path\n  - Make sure the file extension is correct\n  - Verify the file is in the expected directory"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL701@1:8+11;"
    assert PgRow(other, 0) == "NL701|error|Cannot find import './Missing'|Program.tests.nl|1|8|11"
}

test "020 s37 playground diagnostic spans: CheckProject FileImportCollision PreservesDuplicateQuotedPathSpan — NL702@2:8+5;, and the string route DISAGREES (was PlaygroundCompilerTests.CheckProject_FileImportCollision_PreservesDuplicateQuotedPathSpan)" {
    response := PgCheckProject3("Program.nl", "import \"./A\"\nimport \"./B\"\n\nfunc main() {\n}", "A.nl", "class Shared {\n}", "B.nl", "class Shared {\n}", "Program.nl")
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL702@2:8+5;"
    assert PgRow(response, 0) == "NL702|error|Imported symbol 'Shared' is defined by multiple file imports|Program.nl|2|8|5"
    assert PgDetail(response, 0) == "import \"./B\"|The symbol 'Shared' is imported more than once, so N# cannot choose which definition to use.|Add an alias to one import, such as `import \"./B\" as Alias`, and qualify the symbol.|N# found 'Shared' in these file imports: \"./A\", \"./B\".\nUnaliased file imports place their exported symbols directly in scope. Use an alias on one import to make the reference explicit."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheck("import \"./A\"\nimport \"./B\"\n\nfunc main() {\n}")
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL701@1:8+5;NL701@2:8+5;"
    assert PgRow(other, 0) == "NL701|error|Cannot find import './A'|Program.nl|1|8|5"
    assert PgRow(other, 1) == "NL701|error|Cannot find import './B'|Program.nl|2|8|5"
}

test "020 s37 playground diagnostic spans: Check MissingAssignmentValue PreservesTargetSpanForMarkers — NL102@5:5+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingAssignmentValue_PreservesTargetSpanForMarkers)" {
    source := "package Playground\n\nfunc main() {\n    value := 1\n    value =\n    print value\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@5:5+5;"
    assert PgRow(response, 0) == "NL102|error|Expected expression after '='|Program.nl|5|5|5"
    assert PgDetail(response, 0) == "    value =|The '=' operator needs an expression on its right side.|Add an expression after '='|Finish the expression after the operator, or remove the operator if the expression is already complete."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@5:5+5;"
    assert PgRow(other, 0) == "NL102|error|Expected expression after '='|Program.tests.nl|5|5|5"
}

test "020 s37 playground diagnostic spans: Check DanglingBinaryOperator PreservesExpressionSegmentSpanForMarkers — NL102@4:14+3;, and the test-file route agrees (was PlaygroundCompilerTests.Check_DanglingBinaryOperator_PreservesExpressionSegmentSpanForMarkers)" {
    source := "package Playground\n\nfunc main() {\n    value := 1 +\n    print value\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@4:14+3;"
    assert PgRow(response, 0) == "NL102|error|Expected expression after '+'|Program.nl|4|14|3"
    assert PgDetail(response, 0) == "    value := 1 +|The '+' operator needs an expression on its right side.|Add an expression after '+'|Finish the expression after the operator, or remove the operator if the expression is already complete."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@4:14+3;"
    assert PgRow(other, 0) == "NL102|error|Expected expression after '+'|Program.tests.nl|4|14|3"
}

test "020 s37 playground diagnostic spans: Check MissingKeywordsAndKeywordExpressions PreserveVisibleKeywordSpans — NL102@4:5+7;NL301@4:18+5;NL102@8:5+2;NL102@12:5+5;NL102@16:5+5;NL001@17:9+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_MissingKeywordsAndKeywordExpressions_PreserveVisibleKeywordSpans)" {
    source := "package Playground\n\nfunc main() {\n    foreach item items {\n        print item\n    }\n\n    if {\n        print \"missing condition\"\n    }\n\n    while {\n        print \"missing condition\"\n    }\n\n    print\n        value := 1\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "6/0/0"
    assert PgCount(response) == 6
    assert PgCensus(response) == "NL102@4:5+7;NL301@4:18+5;NL102@8:5+2;NL102@12:5+5;NL102@16:5+5;NL001@17:9+5;"
    assert PgRow(response, 0) == "NL102|error|Expected 'in' between the loop variable and collection|Program.nl|4|5|7"
    assert PgDetail(response, 0) == "    foreach item items {|This foreach statement needs the 'in' keyword between the loop variable and the collection.|Add 'in' after 'item'|Write `foreach item in ...`."
    assert PgRow(response, 1) == "NL301|error|Variable 'items' not found|Program.nl|4|18|5"
    assert PgDetail(response, 1) == "    foreach item items {|I cannot find a `items` variable on line 4:|<null>|Make sure you've declared this variable before using it."
    assert PgRow(response, 2) == "NL102|error|Expected a condition expression after 'if'|Program.nl|8|5|2"
    assert PgDetail(response, 2) == "    if {|This if statement needs a condition expression after 'if'.|Add a condition expression after 'if'|Finish the expression before starting the next statement."
    assert PgRow(response, 3) == "NL102|error|Expected a condition expression after 'while'|Program.nl|12|5|5"
    assert PgDetail(response, 3) == "    while {|This while statement needs a condition expression after 'while'.|Add a condition expression after 'while'|Finish the expression before starting the next statement."
    assert PgRow(response, 4) == "NL102|error|Expected an expression to print after 'print'|Program.nl|16|5|5"
    assert PgDetail(response, 4) == "    print|This print statement needs an expression to print after 'print'.|Add an expression to print after 'print'|Finish the expression before starting the next statement."
    assert PgRow(response, 5) == "NL001|error|Variable 'value' is declared but never read|Program.nl|17|9|5"
    assert PgDetail(response, 5) == "        value := 1|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_value'|<null>"
    assert PgRow(response, 6) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 6
    assert PgCensus(other) == "NL102@4:5+7;NL301@4:18+5;NL102@8:5+2;NL102@12:5+5;NL102@16:5+5;NL001@17:9+5;"
    assert PgRow(other, 0) == "NL102|error|Expected 'in' between the loop variable and collection|Program.tests.nl|4|5|7"
    assert PgRow(other, 1) == "NL301|error|Variable 'items' not found|Program.tests.nl|4|18|5"
    assert PgRow(other, 2) == "NL102|error|Expected a condition expression after 'if'|Program.tests.nl|8|5|2"
    assert PgRow(other, 3) == "NL102|error|Expected a condition expression after 'while'|Program.tests.nl|12|5|5"
    assert PgRow(other, 4) == "NL102|error|Expected an expression to print after 'print'|Program.tests.nl|16|5|5"
    assert PgRow(other, 5) == "NL001|error|Variable 'value' is declared but never read|Program.tests.nl|17|9|5"
}

test "020 s37 playground diagnostic spans: Check RecoverySpans AvoidPunctuationOnlyMarkers — NL103@4:5+3;, and the test-file route agrees (was PlaygroundCompilerTests.Check_RecoverySpans_AvoidPunctuationOnlyMarkers InlineData row 0)" {
    source := "package Playground\n\nfunc main() {\n    + 1\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL103@4:5+3;"
    assert PgRow(response, 0) == "NL103|error|Prefix '+' is not supported|Program.nl|4|5|3"
    assert PgDetail(response, 0) == "    + 1|A leading '+' does not change the value in N#, so it is not part of the expression grammar.|Remove the leading '+'|Remove the leading '+'. Numeric literals and variables are already positive unless you subtract or negate them."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL103@4:5+3;"
    assert PgRow(other, 0) == "NL103|error|Prefix '+' is not supported|Program.tests.nl|4|5|3"
}

test "020 s37 playground diagnostic spans: Check RecoverySpans AvoidPunctuationOnlyMarkers — NL102@4:5+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_RecoverySpans_AvoidPunctuationOnlyMarkers InlineData row 1)" {
    source := "package Playground\n\nfunc main() {\n    .Name\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@4:5+5;"
    assert PgRow(response, 0) == "NL102|error|Expected expression before '.'|Program.nl|4|5|5"
    assert PgDetail(response, 0) == "    .Name|I see a dot (.) operator, but there is no receiver expression before it.|Add a receiver before '.'|Put an expression before '.', or remove the member access."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@4:5+5;"
    assert PgRow(other, 0) == "NL102|error|Expected expression before '.'|Program.tests.nl|4|5|5"
}

test "020 s37 playground diagnostic spans: Check RecoverySpans AvoidPunctuationOnlyMarkers — NL102@4:5+2;, and the test-file route agrees (was PlaygroundCompilerTests.Check_RecoverySpans_AvoidPunctuationOnlyMarkers InlineData row 2)" {
    source := "package Playground\n\nfunc main() {\n    if true\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@4:5+2;"
    assert PgRow(response, 0) == "NL102|error|Expected statement body. Got '}'|Program.nl|4|5|2"
    assert PgDetail(response, 0) == "    if true|This control-flow keyword needs a statement or block after its condition.|Add a block body|Add a block like `{ ... }`, or add a single statement after the keyword."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@4:5+2;"
    assert PgRow(other, 0) == "NL102|error|Expected statement body. Got '}'|Program.tests.nl|4|5|2"
}

test "020 s37 playground diagnostic spans: Check RecoverySpans AvoidPunctuationOnlyMarkers — NL102@4:5+3;NL301@4:17+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_RecoverySpans_AvoidPunctuationOnlyMarkers InlineData row 3)" {
    source := "package Playground\n\nfunc main() {\n    for item in items\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@4:5+3;NL301@4:17+5;"
    assert PgRow(response, 0) == "NL102|error|Expected statement body. Got '}'|Program.nl|4|5|3"
    assert PgDetail(response, 0) == "    for item in items|This control-flow keyword needs a statement or block after its condition.|Add a block body|Add a block like `{ ... }`, or add a single statement after the keyword."
    assert PgRow(response, 1) == "NL301|error|Variable 'items' not found|Program.nl|4|17|5"
    assert PgDetail(response, 1) == "    for item in items|I cannot find a `items` variable on line 4:|<null>|Make sure you've declared this variable before using it."
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@4:5+3;NL301@4:17+5;"
    assert PgRow(other, 0) == "NL102|error|Expected statement body. Got '}'|Program.tests.nl|4|5|3"
    assert PgRow(other, 1) == "NL301|error|Variable 'items' not found|Program.tests.nl|4|17|5"
}

test "020 s37 playground diagnostic spans: Check RecoverySpans AvoidPunctuationOnlyMarkers — NL102@4:14+5;, and the test-file route agrees (was PlaygroundCompilerTests.Check_RecoverySpans_AvoidPunctuationOnlyMarkers InlineData row 4)" {
    source := "package Playground\n\nfunc main() {\n    value := await\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@4:14+5;"
    assert PgRow(response, 0) == "NL102|error|Expected an expression to await after 'await'|Program.nl|4|14|5"
    assert PgDetail(response, 0) == "    value := await|This await expression needs an expression to await after 'await'.|Add an expression to await after 'await'|Add an expression to await after 'await', or remove 'await'."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@4:14+5;"
    assert PgRow(other, 0) == "NL102|error|Expected an expression to await after 'await'|Program.tests.nl|4|14|5"
}

test "020 s37 playground diagnostic spans: Check RecoverySpans AvoidPunctuationOnlyMarkers — NL102@4:14+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_RecoverySpans_AvoidPunctuationOnlyMarkers InlineData row 5)" {
    source := "package Playground\n\nfunc main() {\n    value := must\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL102@4:14+4;"
    assert PgRow(response, 0) == "NL102|error|Expected a nullable expression to unwrap after 'must'|Program.nl|4|14|4"
    assert PgDetail(response, 0) == "    value := must|This must expression needs a nullable expression to unwrap after 'must'.|Add a nullable expression to unwrap after 'must'|Add a nullable expression to unwrap after 'must', or remove 'must'."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL102@4:14+4;"
    assert PgRow(other, 0) == "NL102|error|Expected a nullable expression to unwrap after 'must'|Program.tests.nl|4|14|4"
}

test "020 s37 playground diagnostic spans: Check RecoverySpans AvoidPunctuationOnlyMarkers — NL102@4:10+4;NL203@4:10+1;, and the test-file route agrees (was PlaygroundCompilerTests.Check_RecoverySpans_AvoidPunctuationOnlyMarkers InlineData row 6)" {
    source := "package Playground\n\nfunc main() {\n    f := x =>\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@4:10+4;NL203@4:10+1;"
    assert PgRow(response, 0) == "NL102|error|Expected a lambda body expression after '=>'|Program.nl|4|10|4"
    assert PgDetail(response, 0) == "    f := x =>|This lambda expression needs a lambda body expression after '=>'.|Add a lambda body expression after '=>'|Finish the expression before starting the next statement."
    assert PgRow(response, 1) == "NL203|error|I can't figure out the type of lambda parameter 'x' — nothing here names the lambda's delegate type|Program.nl|4|10|1"
    assert PgDetail(response, 1) == "    f := x =>|<null>|Give the lambda a typed home (e.g., 'let f: Func<int, int> = x => ...') or pass it directly where a delegate type is expected.|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@4:10+4;NL203@4:10+1;"
    assert PgRow(other, 0) == "NL102|error|Expected a lambda body expression after '=>'|Program.tests.nl|4|10|4"
    assert PgRow(other, 1) == "NL203|error|I can't figure out the type of lambda parameter 'x' — nothing here names the lambda's delegate type|Program.tests.nl|4|10|1"
}

test "020 s37 playground diagnostic spans: Check RecoverySpans AvoidPunctuationOnlyMarkers — NL102@4:15+15;NL301@4:15+9;, and the test-file route agrees (was PlaygroundCompilerTests.Check_RecoverySpans_AvoidPunctuationOnlyMarkers InlineData row 7)" {
    source := "package Playground\n\nfunc main() {\n    result := condition ? 1 :\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL102@4:15+15;NL301@4:15+9;"
    assert PgRow(response, 0) == "NL102|error|Expected an else expression after ':'|Program.nl|4|15|15"
    assert PgDetail(response, 0) == "    result := condition ? 1 :|This ternary expression needs an else expression after ':'.|Add an else expression after ':'|Finish the expression before starting the next statement."
    assert PgRow(response, 1) == "NL301|error|Variable 'condition' not found|Program.nl|4|15|9"
    assert PgDetail(response, 1) == "    result := condition ? 1 :|I cannot find a `condition` variable on line 4:|<null>|Make sure you've declared this variable before using it."
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL102@4:15+15;NL301@4:15+9;"
    assert PgRow(other, 0) == "NL102|error|Expected an else expression after ':'|Program.tests.nl|4|15|15"
    assert PgRow(other, 1) == "NL301|error|Variable 'condition' not found|Program.tests.nl|4|15|9"
}

test "020 s37 playground diagnostic spans: Check UsingTupleDeconstruction PreservesTuplePatternSpanForMarkers — NL103@8:15+13;NL103@8:32+7;, and the test-file route agrees (was PlaygroundCompilerTests.Check_UsingTupleDeconstruction_PreservesTuplePatternSpanForMarkers)" {
    source := "package Playground\n\nfunc getPair(): (int, int) {\n    return (1, 2)\n}\n\nfunc main() {\n    using let (left, right) := getPair() {\n        print \"ok\"\n    }\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL103@8:15+13;NL103@8:32+7;"
    assert PgRow(response, 0) == "NL103|error|Using statement requires a variable declaration, not tuple deconstruction|Program.nl|8|15|13"
    assert PgDetail(response, 0) == "    using let (left, right) := getPair() {|The 'using' statement can only work with single variable declarations, not tuple deconstruction.|Change from tuple deconstruction to single variable|Use a single variable: using let resource := getResource() { ... }"
    assert PgRow(response, 1) == "NL103|error|Using resource of type 'NSharpLang.Compiler.TupleTypeInfo' must implement IDisposable or provide Dispose(): void|Program.nl|8|32|7"
    assert PgDetail(response, 1) == "    using let (left, right) := getPair() {|<null>|Use a resource type with a parameterless void Dispose method, or remove the using statement.|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL103@8:15+13;NL103@8:32+7;"
    assert PgRow(other, 0) == "NL103|error|Using statement requires a variable declaration, not tuple deconstruction|Program.tests.nl|8|15|13"
    assert PgRow(other, 1) == "NL103|error|Using resource of type 'NSharpLang.Compiler.TupleTypeInfo' must implement IDisposable or provide Dispose(): void|Program.tests.nl|8|32|7"
}

test "020 s37 playground diagnostic spans: Check StringLiteralUnknownMember ReturnsUndefinedMemberDiagnostic — NL303@4:26+4;, and the test-file route agrees (was PlaygroundCompilerTests.Check_StringLiteralUnknownMember_ReturnsUndefinedMemberDiagnostic)" {
    source := "package Playground\n\nfunc main() {\n    print \"asdfasdfasdf\".ToUp()\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL303@4:26+4;"
    assert PgRow(response, 0) == "NL303|error|Member 'ToUp' not found on type 'string'|Program.nl|4|26|4"
    assert PgDetail(response, 0) == "    print \"asdfasdfasdf\".ToUp()|I cannot find a member called `ToUp` on type `string`:|ToUpper|The type `string` does not have a member named `ToUp`.\nCheck for typos, or make sure you're accessing the right type."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL303@4:26+4;"
    assert PgRow(other, 0) == "NL303|error|Member 'ToUp' not found on type 'string'|Program.tests.nl|4|26|4"
}


// ======== THE CONTROLS — 19 contracts the deleted file never had ========
//
// V1-V15 are MINIMAL NEGATIVES: one substitution each, asserted to be a SINGLE occurrence
// in the named fixture before the edit. V10 was a PROVEN NON-MOVER and is replaced by the
// V10b/V10c pair. W1-W3 answer the vacuity question the 13 deleted absence claims raise.

test "020 s37 playground diagnostic spans: V1 — Check NSharpNoMatchingOverload PreservesCallableNameSpan — SILENCE, and the test-file route agrees (V1, a control the C# never had)" {
    source := "package Playground\n\nclass Processor {\n    func Process(x: int): int { return x }\n    func Process(x: string): string { return x }\n}\n\nfunc main() {\n    p := new Processor()\n    p.Process(1)\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V2 — Check UnreachableStatement PreservesUnreachableKeywordSpan — NL001@4:5+5;, and the test-file route agrees (V2, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    value := 1\n    print \"after\"\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL001@4:5+5;"
    assert PgRow(response, 0) == "NL001|error|Variable 'value' is declared but never read|Program.nl|4|5|5"
    assert PgDetail(response, 0) == "    value := 1|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_value'|<null>"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL001@4:5+5;"
    assert PgRow(other, 0) == "NL001|error|Variable 'value' is declared but never read|Program.tests.nl|4|5|5"
}

test "020 s37 playground diagnostic spans: V3 — Check DefaultSemanticSpan PreservesVisibleTokenSpan — SILENCE, and the test-file route agrees (V3, a control the C# never had)" {
    source := "package Playground\n\nfunc main(): int {\n    let value: int = 42\n    return value\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V4 — Check MissingFieldColon PreservesFieldNameSpan — SILENCE, and the test-file route agrees (V4, a control the C# never had)" {
    source := "package Playground\n\nclass User {\n    Name: string\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V5 — Check MissingParameterColon PreservesParameterNameSpan — SILENCE, and the test-file route agrees (V5, a control the C# never had)" {
    source := "package Playground\n\nfunc greet(name: string): string {\n    return name\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V6 — Check MissingFunctionReturnColon PreservesFunctionNameSpan — SILENCE, and the test-file route agrees (V6, a control the C# never had)" {
    source := "package Playground\n\nfunc answer(): int {\n    return 1\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V7 — Check MissingAssignmentValue PreservesTargetSpanForMarkers — SILENCE, and the test-file route agrees (V7, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    value := 1\n    value = 1\n    print value\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V8 — Check DanglingBinaryOperator PreservesExpressionSegmentSpanForMarkers — SILENCE, and the test-file route agrees (V8, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    value := 1 + 2\n    print value\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V9 — Check MissingDeclarationName PreservesDeclarationKeywordSpanForMarkers#0 — SILENCE, and the test-file route agrees (V9, a control the C# never had)" {
    source := "package Playground\n\nfunc named() {\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V11 — Check ObjectInitializerMissingValue PreservesPropertyNameSpanForMarkers — NL001@8:5+4;, and the test-file route agrees (V11, a control the C# never had)" {
    source := "package Playground\n\nclass User {\n    Name: string\n}\n\nfunc main() {\n    user := new User { Name: \"x\" }\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL001@8:5+4;"
    assert PgRow(response, 0) == "NL001|error|Variable 'user' is declared but never read|Program.nl|8|5|4"
    assert PgDetail(response, 0) == "    user := new User { Name: \"x\" }|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_user'|<null>"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL001@8:5+4;"
    assert PgRow(other, 0) == "NL001|error|Variable 'user' is declared but never read|Program.tests.nl|8|5|4"
}

test "020 s37 playground diagnostic spans: V12 — Check RecoverySpans AvoidPunctuationOnlyMarkers#0 — NL103@4:14+3;, and the test-file route agrees (V12, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    value := + 1\n}"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL103@4:14+3;"
    assert PgRow(response, 0) == "NL103|error|Prefix '+' is not supported|Program.nl|4|14|3"
    assert PgDetail(response, 0) == "    value := + 1|A leading '+' does not change the value in N#, so it is not part of the expression grammar.|Remove the leading '+'|Remove the leading '+'. Numeric literals and variables are already positive unless you subtract or negate them."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL103@4:14+3;"
    assert PgRow(other, 0) == "NL103|error|Prefix '+' is not supported|Program.tests.nl|4|14|3"
}

test "020 s37 playground diagnostic spans: V13 — Check IncompleteMemberAccessBeforeCall PreservesReceiverSpan — SILENCE, and the test-file route agrees (V13, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    name := \"Ada\"\n    name()\n}"
    response := PgCheck(source)
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "True"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 0
    assert PgCensus(other) == ""
}

test "020 s37 playground diagnostic spans: V14 — CheckProject FileImportCollision PreservesDuplicateQuotedPathSpan — SILENCE, and the string route DISAGREES (V14, a control the C# never had)" {
    response := PgCheckProject3("Program.nl", "import \"./A\"\nimport \"./B\"\n\nfunc main() {\n}", "A.nl", "class Shared {\n}", "B.nl", "class Separate {\n}", "Program.nl")
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheck("import \"./A\"\nimport \"./B\"\n\nfunc main() {\n}")
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL701@1:8+5;NL701@2:8+5;"
    assert PgRow(other, 0) == "NL701|error|Cannot find import './A'|Program.nl|1|8|5"
    assert PgRow(other, 1) == "NL701|error|Cannot find import './B'|Program.nl|2|8|5"
}

test "020 s37 playground diagnostic spans: V15 — Check DuplicateTestLifecycleBlocks PreserveFullKeywordSpans — NL001@2:5+5;NL306@9:1+8;, and the string route agrees (V15, a control the C# never had)" {
    response := PgCheckProject1("Program.tests.nl", "setup {\n    first := 1\n}\n\nteardown {\n    Cleanup()\n}\n\nteardown {\n    CleanupAgain()\n}\n\nfunc Cleanup() {}\nfunc CleanupAgain() {}\n\ntest \"works\" {\n    assert true\n}", "Program.tests.nl")
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.tests.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL001@2:5+5;NL306@9:1+8;"
    assert PgRow(response, 0) == "NL001|error|Variable 'first' is declared but never read|Program.tests.nl|2|5|5"
    assert PgDetail(response, 0) == "    first := 1|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_first'|<null>"
    assert PgRow(response, 1) == "NL306|error|Only one teardown block is allowed per test file|Program.tests.nl|9|1|8"
    assert PgDetail(response, 1) == "teardown {|<null>|<null>|<null>"
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheck("setup {\n    first := 1\n}\n\nteardown {\n    Cleanup()\n}\n\nteardown {\n    CleanupAgain()\n}\n\nfunc Cleanup() {}\nfunc CleanupAgain() {}\n\ntest \"works\" {\n    assert true\n}")
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL001@2:5+5;NL306@9:1+8;"
    assert PgRow(other, 0) == "NL001|error|Variable 'first' is declared but never read|Program.nl|2|5|5"
    assert PgRow(other, 1) == "NL306|error|Only one teardown block is allowed per test file|Program.nl|9|1|8"
}

test "020 s37 playground diagnostic spans: V10b — Check MissingFileImport PreservesQuotedPathSpan — SILENCE, and the string route DISAGREES (V10b, a control the C# never had)" {
    response := PgCheckProject2("Program.nl", "import \"./Present\"\n\nfunc main() {\n}", "Present.nl", "class Present {\n}", "Program.nl")
    assert PgOk(response) == "True"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "0/0/0"
    assert PgCount(response) == 0
    assert PgCensus(response) == ""
    assert PgRow(response, 0) == "<no-such-diagnostic>"
    other := PgCheck("import \"./Present\"\n\nfunc main() {\n}")
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL701@1:8+11;"
    assert PgRow(other, 0) == "NL701|error|Cannot find import './Present'|Program.nl|1|8|11"
}

test "020 s37 playground diagnostic spans: V10c — Check MissingFileImport PreservesQuotedPathSpan — NL701@1:8+11;, and the string route agrees (V10c, a control the C# never had)" {
    response := PgCheckProject2("Program.nl", "import \"./Missing\"\n\nfunc main() {\n}", "Present.nl", "class Present {\n}", "Program.nl")
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL701@1:8+11;"
    assert PgRow(response, 0) == "NL701|error|Cannot find import './Missing'|Program.nl|1|8|11"
    assert PgDetail(response, 0) == "import \"./Missing\"|I cannot find the file you're trying to import on line 1:|<null>|Make sure the file exists at the path './Missing'.\nThe path should be relative to your project root.\n\nCommon issues:\n  - Check for typos in the file path\n  - Make sure the file extension is correct\n  - Verify the file is in the expected directory"
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheck("import \"./Missing\"\n\nfunc main() {\n}")
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL701@1:8+11;"
    assert PgRow(other, 0) == "NL701|error|Cannot find import './Missing'|Program.nl|1|8|11"
}

test "020 s37 playground diagnostic spans: W1 — NL101-is-producible — NL001@4:5+5;NL101@4:21+1;, and the test-file route agrees (W1, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    value := (1 + 2))\n}\n"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "2/0/0"
    assert PgCount(response) == 2
    assert PgCensus(response) == "NL001@4:5+5;NL101@4:21+1;"
    assert PgRow(response, 0) == "NL001|error|Variable 'value' is declared but never read|Program.nl|4|5|5"
    assert PgDetail(response, 0) == "    value := (1 + 2))|<null>|If this is intentional, prefix it with '_' to indicate it's unused: '_value'|<null>"
    assert PgRow(response, 1) == "NL101|error|Unexpected token ')' in expression|Program.nl|4|21|1"
    assert PgDetail(response, 1) == "    value := (1 + 2))|I was parsing an expression and found ')', which I don't know how to handle here.|<null>|Expressions can be literals (numbers, strings), identifiers, or operators. Check your syntax."
    assert PgRow(response, 2) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 2
    assert PgCensus(other) == "NL001@4:5+5;NL101@4:21+1;"
    assert PgRow(other, 0) == "NL001|error|Variable 'value' is declared but never read|Program.tests.nl|4|5|5"
    assert PgRow(other, 1) == "NL101|error|Unexpected token ')' in expression|Program.tests.nl|4|21|1"
}

test "020 s37 playground diagnostic spans: W2 — NL313-is-producible — NL313@4:7+3;, and the test-file route agrees (W2, a control the C# never had)" {
    source := "package Playground\n\nfunc main() {\n    1 + 2\n}\n"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "1/0/0"
    assert PgCount(response) == 1
    assert PgCensus(response) == "NL313@4:7+3;"
    assert PgRow(response, 0) == "NL313|error|This expression statement has no effect|Program.nl|4|7|3"
    assert PgDetail(response, 0) == "    1 + 2|This expression is written as a statement, but it does not do anything by itself:|Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.|The expression `binary expression` produces a value or names a member, but the value is ignored.\nOnly assignments, calls, increments, decrements, await expressions, and object construction can be used as statements."
    assert PgRow(response, 1) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 1
    assert PgCensus(other) == "NL313@4:7+3;"
    assert PgRow(other, 0) == "NL313|error|This expression statement has no effect|Program.tests.nl|4|7|3"
}

test "020 s37 playground diagnostic spans: W3 — error-placeholder-is-producible — NL102@4:5+4;NL201@4:5+7;NL303@9:16+4;, and the test-file route agrees (W3, a control the C# never had)" {
    source := "package Playground\n\nclass User {\n    Name:\n}\n\nfunc main() {\n    user := new User()\n    print user.Name\n}\n"
    response := PgCheck(source)
    assert PgOk(response) == "False"
    assert PgSchemaVersion(response) == "2"
    assert PgFileName(response) == "Program.nl"
    assert PgSummary(response) == "3/0/0"
    assert PgCount(response) == 3
    assert PgCensus(response) == "NL102@4:5+4;NL201@4:5+7;NL303@9:16+4;"
    assert PgRow(response, 0) == "NL102|error|Expected type name. Got '}'|Program.nl|4|5|4"
    assert PgDetail(response, 0) == "    Name:|Field 'Name' needs a type after ':'.|Add a field type after ':'|Write this field as `Name: Type`."
    assert PgRow(response, 1) == "NL201|error|Type '<error>' not found|Program.nl|4|5|7"
    assert PgDetail(response, 1) == "    Name:|<null>|Check the spelling, add the missing 'import', or add the package/project reference that provides '<error>'.|<null>"
    assert PgRow(response, 2) == "NL303|error|Member 'Name' not found on type 'User'|Program.nl|9|16|4"
    assert PgDetail(response, 2) == "    print user.Name|I cannot find a member called `Name` on type `User`:|Name|The type `User` does not have a member named `Name`.\nCheck for typos, or make sure you're accessing the right type."
    assert PgRow(response, 3) == "<no-such-diagnostic>"
    other := PgCheckTestFile(source)
    assert PgOk(other) == "False"
    assert PgFileName(other) == "Program.tests.nl"
    assert PgCount(other) == 3
    assert PgCensus(other) == "NL102@4:5+4;NL201@4:5+7;NL303@9:16+4;"
    assert PgRow(other, 0) == "NL102|error|Expected type name. Got '}'|Program.tests.nl|4|5|4"
    assert PgRow(other, 1) == "NL201|error|Type '<error>' not found|Program.tests.nl|4|5|7"
    assert PgRow(other, 2) == "NL303|error|Member 'Name' not found on type 'User'|Program.tests.nl|9|16|4"
}
