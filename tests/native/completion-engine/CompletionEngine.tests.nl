namespace NSharpLang.CompletionEngine.Tests

import System
import System.Collections
import System.IO
import NSharpLang.Compiler


// THE PRODUCTION COMPLETION ENGINE, ASKED THE TWELVE QUESTIONS `tests/CompletionEngineTests.cs`
// ASKED — DRIVEN THROUGH THE CLI'S OWN PROJECT-LOAD PATH.
//
// WHY THIS IS A NATIVE PROJECT AND NOT AN ESTATE CONTRACT. `CompletionEngine`'s inputs need a
// `SemanticModel`, and the only thing that produces one is the C# `Analyzer`, which lives in
// `Compiler.dll` — the assembly that DEPENDS on `NSharpLang.Compiler.BootstrapServices`. A
// `.tests.nl` inside BootstrapServices therefore cannot reach it in any spelling; the dependency
// runs the wrong way. A native project can, because it references both assemblies and reaches the
// production types BY REFLECTION, exactly as `tests/native/query-completions` already does. This
// project runs through `nlc test`, so the compiler under test is also the compiler that built it.
//
// THE ROUTE IS STRICTLY STRONGER THAN THE C# IT REPLACES. The deleted C# built its
// `ProjectSnapshot` BY HAND: it called `Analyzer.Analyze` itself, assembled two dictionaries and
// constructed the snapshot with an EMPTY source-text map and a `ProjectIndex` only when bindings
// happened to exist. Here every fixture is a real project on disk loaded through
// `CodeIntelligenceService.LoadProject` — the same call `QueryCommand.LoadProjectOrFail` makes
// before `nlc query completions` can answer anything — so the snapshot under test is the snapshot
// the product actually builds, source texts and project index included.
//
// TWO THINGS THE C# LEFT IMPLICIT ARE STATED HERE:
//   (a) AN UNKNOWN CONTEXT CARRIES NO GROUPS AT ALL. The three refusal cases (an unknown file, a
//       line past the end, and line zero) each state BOTH that the context is `Unknown` and that
//       the completion dictionary is EMPTY — a refusal is not a context label over a populated map.
//   (b) THE KEYWORD SWITCH IS SYMMETRIC. The same position is asked twice, once with
//       `includeKeywords` true and once false, and the three keyword groups are stated present in
//       the first and absent in the second.

func SetCompletionObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// One single-file project per fixture: the engine reads its source from the snapshot the project
// load produced, so the file has to exist on disk under a real project root.
func WriteCompletionFixture(source: string): string {
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-completion-engine-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(fixtureRoot)

    File.WriteAllText(
        Path.Combine(fixtureRoot, "project.yml"),
        "name: CompletionEngineFixture\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\n")
    File.WriteAllText(Path.Combine(fixtureRoot, "test.nl"), source)

    return fixtureRoot
}

func CompletionFixtureFile(fixtureRoot: string): string {
    return Path.Combine(fixtureRoot, "test.nl")
}

// The production snapshot load — `CodeIntelligenceService.LoadProject(projectRoot)`.
func LoadCompletionSnapshot(fixtureRoot: string): object {
    serviceType := Type.GetType("NSharpLang.Compiler.CodeIntelligence.CodeIntelligenceService, Compiler")
    if serviceType == null {
        throw new InvalidOperationException("The production code-intelligence service type was not loadable.")
    }

    serviceConstructor := serviceType.GetConstructor(new Type[](0))
    if serviceConstructor == null {
        throw new InvalidOperationException("The production code-intelligence service was not constructible.")
    }
    service := serviceConstructor.Invoke(new object?[](0))

    loadParameterTypes := new Type[](1)
    loadParameterTypes[0] = typeof(string)
    loadMethod := serviceType.GetMethod("LoadProject", loadParameterTypes)
    if loadMethod == null {
        throw new InvalidOperationException("The production LoadProject entry point was not found.")
    }

    loadArguments := new object?[](1)
    SetCompletionObject(loadArguments, 0, fixtureRoot)
    snapshot := loadMethod.Invoke(service, loadArguments)
    if snapshot == null {
        throw new InvalidOperationException("The production project snapshot was not loaded.")
    }

    return snapshot
}

// The production completion question — `CompletionEngine.GetCompletions(snapshot, file, line, col,
// includeKeywords)`, exactly as `CompletionsCommand` asks it.
func AskCompletions(snapshot: object, sourceFile: string, line: int, column: int, includeKeywords: bool): object {
    engineType := Type.GetType("NSharpLang.Compiler.CodeIntelligence.CompletionEngine, Compiler")
    snapshotType := Type.GetType("NSharpLang.Compiler.CodeIntelligence.ProjectSnapshot, NSharpLang.Compiler.BootstrapServices")
    if engineType == null || snapshotType == null {
        throw new InvalidOperationException("The production completion types were not loadable.")
    }

    engineConstructor := engineType.GetConstructor(new Type[](0))
    if engineConstructor == null {
        throw new InvalidOperationException("The production completion engine was not constructible.")
    }
    engine := engineConstructor.Invoke(new object?[](0))

    completionParameterTypes := new Type[](5)
    completionParameterTypes[0] = snapshotType
    completionParameterTypes[1] = typeof(string)
    completionParameterTypes[2] = typeof(int)
    completionParameterTypes[3] = typeof(int)
    completionParameterTypes[4] = typeof(bool)
    completionsMethod := engineType.GetMethod("GetCompletions", completionParameterTypes)
    if completionsMethod == null {
        throw new InvalidOperationException("The production GetCompletions entry point was not found.")
    }

    completionArguments := new object?[](5)
    SetCompletionObject(completionArguments, 0, snapshot)
    SetCompletionObject(completionArguments, 1, sourceFile)
    SetCompletionObject(completionArguments, 2, line)
    SetCompletionObject(completionArguments, 3, column)
    SetCompletionObject(completionArguments, 4, includeKeywords)
    completionAnswer := completionsMethod.Invoke(engine, completionArguments)
    if completionAnswer == null {
        throw new InvalidOperationException("The production completion engine returned no result.")
    }

    return completionAnswer
}

func CompletionProperty(owner: object, propertyName: string): object? {
    ownerProperty := owner.GetType().GetProperty(propertyName)
    if ownerProperty == null {
        throw new InvalidOperationException("The production completion result has no " + propertyName + " property.")
    }

    return ownerProperty.GetValue(owner)
}

func CompletionText(owner: object, propertyName: string): string {
    value := CompletionProperty(owner, propertyName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

func CompletionDictionary(answer: object): object {
    completions := CompletionProperty(answer, "Completions")
    if completions == null {
        throw new InvalidOperationException("The production completion result exposed no completions dictionary.")
    }

    return completions
}

func CompletionGroupCount(answer: object): int {
    completions := CompletionDictionary(answer)
    countProperty := completions.GetType().GetProperty("Count")
    if countProperty == null {
        throw new InvalidOperationException("The production completions dictionary exposed no Count.")
    }

    count := countProperty.GetValue(completions)
    if count == null {
        return -1
    }

    return Convert.ToInt32(count)
}

func CompletionHasGroup(answer: object, groupKey: string): bool {
    completions := CompletionDictionary(answer)

    keyParameterTypes := new Type[](1)
    keyParameterTypes[0] = typeof(string)
    containsKeyMethod := completions.GetType().GetMethod("ContainsKey", keyParameterTypes)
    if containsKeyMethod == null {
        throw new InvalidOperationException("The production completions dictionary contract was incomplete.")
    }

    keyArguments := new object?[](1)
    SetCompletionObject(keyArguments, 0, groupKey)
    containsValue := containsKeyMethod.Invoke(completions, keyArguments)
    if containsValue == null {
        return false
    }

    return containsValue.ToString() == "True"
}

func CompletionGroup(answer: object, groupKey: string): IList? {
    if !CompletionHasGroup(answer, groupKey) {
        return null
    }

    completions := CompletionDictionary(answer)
    itemProperty := completions.GetType().GetProperty("Item")
    if itemProperty == null {
        throw new InvalidOperationException("The production completions dictionary has no indexer.")
    }

    keyArguments := new object?[](1)
    SetCompletionObject(keyArguments, 0, groupKey)
    return itemProperty.GetValue(completions, keyArguments) as IList
}

// The names in one completion group, joined with commas — reflection all the way down, so the
// asserts never depend on assembly identity across the test host's load contexts.
func CompletionGroupNames(answer: object, groupKey: string): string {
    group := CompletionGroup(answer, groupKey)
    if group == null {
        return ""
    }

    names := ""
    index := 0
    while index < group.Count {
        item := group[index]
        if item != null {
            itemName := CompletionProperty(item, "Name")
            if itemName != null {
                if names.Length > 0 {
                    names = names + ","
                }
                names = names + itemName.ToString()
            }
        }

        index = index + 1
    }

    return names
}

// The group keys, copied out of the dictionary's key collection rather than walked: a
// `Dictionary<K, V>.KeyCollection` is not a `foreach` collection N# can consume, and its
// `CopyTo(string[], int)` is reached by reflection like everything else here.
func CompletionGroupKeys(answer: object): string[] {
    completions := CompletionDictionary(answer)
    keysProperty := completions.GetType().GetProperty("Keys")
    if keysProperty == null {
        throw new InvalidOperationException("The production completions dictionary exposed no Keys.")
    }

    keys := keysProperty.GetValue(completions)
    if keys == null {
        return new string[](0)
    }

    keyCountProperty := keys.GetType().GetProperty("Count")
    if keyCountProperty == null {
        throw new InvalidOperationException("The production completions key collection exposed no Count.")
    }

    keyCount := keyCountProperty.GetValue(keys)
    if keyCount == null {
        return new string[](0)
    }

    buffer := new string[](Convert.ToInt32(keyCount))

    copyParameterTypes := new Type[](2)
    copyParameterTypes[0] = typeof(string[])
    copyParameterTypes[1] = typeof(int)
    copyMethod := keys.GetType().GetMethod("CopyTo", copyParameterTypes)
    if copyMethod == null {
        throw new InvalidOperationException("The production completions key collection has no CopyTo.")
    }

    copyArguments := new object?[](2)
    SetCompletionObject(copyArguments, 0, buffer)
    SetCompletionObject(copyArguments, 1, 0)
    copyMethod.Invoke(keys, copyArguments)

    return buffer
}

// Every completion name in the answer, across every group.
func CompletionAllNames(answer: object): string {
    keys := CompletionGroupKeys(answer)
    names := ""
    index := 0
    while index < keys.Length {
        groupNames := CompletionGroupNames(answer, keys[index])
        if groupNames.Length > 0 {
            if names.Length > 0 {
                names = names + ","
            }

            names = names + groupNames
        }

        index = index + 1
    }

    return names
}

func CompletionNamesContain(names: string, expected: string): bool {
    parts := names.Split(',')
    index := 0
    while index < parts.Length {
        if parts[index] == expected {
            return true
        }

        index = index + 1
    }

    return false
}

// One field of the first item in a group carrying the given name; `<missing>` when the group has
// no such item and `<null>` when the field itself is null.
func CompletionItemField(answer: object, groupKey: string, itemName: string, fieldName: string): string {
    group := CompletionGroup(answer, groupKey)
    if group == null {
        return "<missing>"
    }

    index := 0
    while index < group.Count {
        item := group[index]
        if item != null {
            name := CompletionProperty(item, "Name")
            if name != null && name.ToString() == itemName {
                return CompletionText(item, fieldName)
            }
        }

        index = index + 1
    }

    return "<missing>"
}

func CompletionLineLength(source: string, line: int): int {
    return source.Split('\n')[line - 1].Length
}


// ── Identifier completions ──────────────────────────────────────────────────────────────────────

test "an identifier position offers the locals declared above it" {
    fixtureRoot := WriteCompletionFixture("func main() {\n    name := \"Spencer\"\n    n\n}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 3, 5, false)

    assert CompletionText(answer, "Context") == "Identifier"
    assert CompletionHasGroup(answer, "variables")
    assert CompletionNamesContain(CompletionGroupNames(answer, "variables"), "name")

    Directory.Delete(fixtureRoot, true)
}

test "an identifier position offers the functions declared in the file" {
    fixtureRoot := WriteCompletionFixture("func helper(): int {\n    return 42\n}\n\nfunc main() {\n    h\n}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 6, 5, false)

    assert CompletionText(answer, "Context") == "Identifier"
    assert CompletionHasGroup(answer, "functions")
    assert CompletionNamesContain(CompletionGroupNames(answer, "functions"), "helper")

    Directory.Delete(fixtureRoot, true)
}

test "an identifier position offers the type declarations in the file" {
    fixtureRoot := WriteCompletionFixture("class Person {\n    Name: string\n}\n\nfunc main() {\n    P\n}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 6, 5, false)

    assert CompletionHasGroup(answer, "types")
    assert CompletionNamesContain(CompletionGroupNames(answer, "types"), "Person")
    assert CompletionItemField(answer, "types", "Person", "Kind") == "class"

    Directory.Delete(fixtureRoot, true)
}

test "every declared type kind appears in the type group" {
    fixtureRoot := WriteCompletionFixture(
        "class Cat {}\nstruct Point {\n    X: int\n    Y: int\n}\nenum Color { Red, Green, Blue }\n\nfunc main() {\n    \n}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 9, 4, false)

    assert CompletionHasGroup(answer, "types")

    typeNames := CompletionGroupNames(answer, "types")
    assert CompletionNamesContain(typeNames, "Cat")
    assert CompletionNamesContain(typeNames, "Point")
    assert CompletionNamesContain(typeNames, "Color")

    assert CompletionItemField(answer, "types", "Cat", "Kind") == "class"
    assert CompletionItemField(answer, "types", "Point", "Kind") == "struct"
    assert CompletionItemField(answer, "types", "Color", "Kind") == "enum"

    Directory.Delete(fixtureRoot, true)
}

test "a function completion carries its return type, parameter list and instance-ness" {
    fixtureRoot := WriteCompletionFixture("func add(a: int, b: int): int {\n    return a + b\n}\n\nfunc main() {\n    a\n}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 6, 5, false)

    assert CompletionHasGroup(answer, "functions")

    // The row exists at all, and its return type is populated rather than null.
    assert CompletionItemField(answer, "functions", "add", "Kind") != "<missing>"
    assert CompletionItemField(answer, "functions", "add", "Type") != "<null>"

    assert CompletionItemField(answer, "functions", "add", "Kind") == "function"
    assert CompletionItemField(answer, "functions", "add", "Type") == "int"
    assert CompletionItemField(answer, "functions", "add", "Parameters") == "(a int, b int)"
    assert CompletionItemField(answer, "functions", "add", "IsStatic") == "False"

    // The same function also appears as a declaration, and that row names both parameters.
    assert CompletionHasGroup(answer, "types")
    declaredParameters := CompletionItemField(answer, "types", "add", "Parameters")
    assert declaredParameters != "<missing>"
    assert declaredParameters != "<null>"
    assert declaredParameters.Contains("a")
    assert declaredParameters.Contains("b")

    Directory.Delete(fixtureRoot, true)
}


// ── Keyword completions ─────────────────────────────────────────────────────────────────────────

test "asking for keywords adds the keyword, primitive-type and modifier groups" {
    fixtureRoot := WriteCompletionFixture("func main() {\n    \n}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 2, 4, true)

    assert CompletionHasGroup(answer, "keywords")
    assert CompletionHasGroup(answer, "primitiveTypes")
    assert CompletionHasGroup(answer, "modifiers")

    assert CompletionNamesContain(CompletionGroupNames(answer, "keywords"), "import")
    assert CompletionNamesContain(CompletionGroupNames(answer, "keywords"), "func")
    assert CompletionNamesContain(CompletionGroupNames(answer, "primitiveTypes"), "int")
    assert CompletionNamesContain(CompletionGroupNames(answer, "primitiveTypes"), "string")
    assert CompletionNamesContain(CompletionGroupNames(answer, "modifiers"), "pub")

    Directory.Delete(fixtureRoot, true)
}

test "the same position without the keyword switch offers none of those three groups" {
    fixtureRoot := WriteCompletionFixture("func main() {\n    \n}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 2, 4, false)

    assert !CompletionHasGroup(answer, "keywords")
    assert !CompletionHasGroup(answer, "primitiveTypes")
    assert !CompletionHasGroup(answer, "modifiers")

    Directory.Delete(fixtureRoot, true)
}


// ── Member access ───────────────────────────────────────────────────────────────────────────────

test "a member access on an N# class offers its fields and its methods" {
    fixtureRoot := WriteCompletionFixture(
        "class Dog {\n    Name: string\n    func Bark(): string {\n        return \"Woof\"\n    }\n}\n\nfunc main() {\n    dog := new Dog { Name: \"Rex\" }\n    dog.\n}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 10, 8, false)

    assert CompletionText(answer, "Context") == "MemberAccess"

    allNames := CompletionAllNames(answer)
    assert allNames.Length > 0
    assert CompletionNamesContain(allNames, "Name")
    assert CompletionNamesContain(allNames, "Bark")

    Directory.Delete(fixtureRoot, true)
}

test "a member access on a call result resolves through the callee's return type" {
    source := "class Dog {\n    Name: string\n    func Bark(): string {\n        return \"Woof\"\n    }\n}\n\nclass Factory {\n    func Create(): Dog {\n        return new Dog { Name: \"Rex\" }\n    }\n}\n\nfunc main() {\n    factory := new Factory {}\n    factory.Create().\n}"
    fixtureRoot := WriteCompletionFixture(source)
    answer := AskCompletions(
        LoadCompletionSnapshot(fixtureRoot),
        CompletionFixtureFile(fixtureRoot),
        16,
        CompletionLineLength(source, 16),
        false)

    assert CompletionText(answer, "Context") == "MemberAccess"
    assert CompletionText(answer, "Receiver") == "factory.Create()"

    allNames := CompletionAllNames(answer)
    assert CompletionNamesContain(allNames, "Name")
    assert CompletionNamesContain(allNames, "Bark")

    Directory.Delete(fixtureRoot, true)
}


test "a BCL receiver offers its members and NOT the accessors the CLR synthesises" {
    source := "func main() {\n    summary := \"warm\"\n    summary.\n}"
    fixtureRoot := WriteCompletionFixture(source)
    answer := AskCompletions(
        LoadCompletionSnapshot(fixtureRoot),
        CompletionFixtureFile(fixtureRoot),
        3,
        CompletionLineLength(source, 3),
        false)

    assert CompletionText(answer, "Context") == "MemberAccess"
    assert CompletionText(answer, "Receiver") == "summary"

    allNames := CompletionAllNames(answer)
    assert CompletionNamesContain(allNames, "ToUpper")
    assert CompletionNamesContain(allNames, "Length")

    // THE CORRECTED CLI OUTPUT. `nlc query completions` on a string receiver used to offer
    // `get_Length` and `get_Chars` beside `Length`, because `GetMethods` hands back the accessor
    // pair the CLR synthesises for every property. The property survives; its accessors do not.
    assert !CompletionNamesContain(allNames, "get_Length")
    assert !CompletionNamesContain(allNames, "get_Chars")

    Directory.Delete(fixtureRoot, true)
}

// ── The three refusals ──────────────────────────────────────────────────────────────────────────

test "a file the snapshot does not hold answers an unknown context and no groups" {
    fixtureRoot := WriteCompletionFixture("func main() {}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), "nonexistent.nl", 1, 1, false)

    assert CompletionText(answer, "Context") == "Unknown"
    assert CompletionGroupCount(answer) == 0

    Directory.Delete(fixtureRoot, true)
}

test "a line past the end of the file answers an unknown context and no groups" {
    fixtureRoot := WriteCompletionFixture("func main() {}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 999, 1, false)

    assert CompletionText(answer, "Context") == "Unknown"
    assert CompletionGroupCount(answer) == 0

    Directory.Delete(fixtureRoot, true)
}

test "line zero is out of range in the other direction and answers the same way" {
    fixtureRoot := WriteCompletionFixture("func main() {}")
    answer := AskCompletions(LoadCompletionSnapshot(fixtureRoot), CompletionFixtureFile(fixtureRoot), 0, 1, false)

    assert CompletionText(answer, "Context") == "Unknown"
    assert CompletionGroupCount(answer) == 0

    Directory.Delete(fixtureRoot, true)
}
