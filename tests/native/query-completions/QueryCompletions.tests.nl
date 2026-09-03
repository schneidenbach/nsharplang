namespace NSharpLang.QueryCompletions.Tests

import System
import System.Collections
import System.IO
import NSharpLang.Compiler

// End-to-end regression coverage for `nlc query completions`. In 2026-08 the command hung for tens
// of minutes on multi-file projects: every per-file analysis rebuilt the project-namespace set by
// re-parsing every project source from disk (O(files²) recovery parses), triggered by ordinary
// `import` validation inside CodeIntelligenceService.LoadProject — the exact call the CLI's
// completions handler makes before it can answer anything. These tests drive that same production
// pipeline over a fixture whose imports exercise both the project-namespace probe
// (Regression.Models) and the external one (System), then ask the production CompletionEngine the
// same question `nlc query completions --file Program.nl --pos 8:18` asks. The production types are
// reached by reflection, exactly as the extension-calls suite reaches MultiFileCompiler: this
// project runs through `nlc test`, so the compiler under test is also the compiler that built it.
func SetQueryObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// A three-file project whose analysis walks the paths the hang lived on: a cross-file import that
// only the project-namespace scan can validate, an external import that only the assembly scan can,
// and a member access on a type declared in the OTHER file.
func WriteQueryCompletionsFixture(): string {
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-query-completions-" + Guid.NewGuid().ToString("N")
    )
    Directory.CreateDirectory(fixtureRoot)

    File.WriteAllText(
        Path.Combine(fixtureRoot, "project.yml"),
        "name: CompletionsRegression\nversion: 1.0.0\noutputType: exe\ntargetFramework: net10.0\nentry: Program.nl\n"
    )
    File.WriteAllText(
        Path.Combine(fixtureRoot, "Models.nl"),
        "namespace Regression.Models\n\npublic class Sensor {\n    Name: string = \"\"\n    Reading: double = 0\n    calibration: double = 0\n}\n"
    )

    // The SAME receiver, read from a file that shares the declaring package. It is the control for
    // the visibility filter: `calibration` is unexported, and inside `Regression.Models` reading it
    // compiles, so the completion must keep offering it here while dropping it in `Regression.App`.
    File.WriteAllText(
        Path.Combine(fixtureRoot, "Neighbour.nl"),
        "namespace Regression.Models\n\nfunc Peek(sensor: Sensor): string {\n    return sensor.Name\n}\n"
    )
    File.WriteAllText(
        Path.Combine(fixtureRoot, "Program.nl"),
        "namespace Regression.App\n\nimport System\nimport Regression.Models\n\nfunc Main() {\n    sensor := new Sensor()\n    print sensor.Name\n}\n"
    )

    return fixtureRoot
}

// The production snapshot load — CodeIntelligenceService.LoadProject(projectRoot), the call
// QueryCommand.LoadProjectOrFail makes and the call that used to never return.
func LoadQueryCompletionsSnapshot(fixtureRoot: string): object {
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
    SetQueryObject(loadArguments, 0, fixtureRoot)
    snapshot := loadMethod.Invoke(service, loadArguments)
    if snapshot == null {
        throw new InvalidOperationException("The production project snapshot was not loaded.")
    }

    return snapshot
}

// The production completion question — CompletionEngine.GetCompletions(snapshot, file, line, col,
// includeKeywords), exactly as CompletionsCommand asks it.
func AskQueryCompletions(snapshot: object, sourceFile: string, line: int, column: int): object {
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
    SetQueryObject(completionArguments, 0, snapshot)
    SetQueryObject(completionArguments, 1, sourceFile)
    SetQueryObject(completionArguments, 2, line)
    SetQueryObject(completionArguments, 3, column)
    SetQueryObject(completionArguments, 4, false)
    completionAnswer := completionsMethod.Invoke(engine, completionArguments)
    if completionAnswer == null {
        throw new InvalidOperationException("The production completion engine returned no result.")
    }

    return completionAnswer
}

func QueryCompletionProperty(owner: object, propertyName: string): object? {
    ownerProperty := owner.GetType().GetProperty(propertyName)
    if ownerProperty == null {
        throw new InvalidOperationException("The production completion result has no " + propertyName + " property.")
    }

    return ownerProperty.GetValue(owner)
}

// The names in one completion group, joined with commas — reflection all the way down, so the
// asserts never depend on assembly identity across the test host's load contexts.
func QueryCompletionGroupNames(answer: object, groupKey: string): string {
    completions := QueryCompletionProperty(answer, "Completions")
    if completions == null {
        throw new InvalidOperationException("The production completion result exposed no completions dictionary.")
    }

    keyParameterTypes := new Type[](1)
    keyParameterTypes[0] = typeof(string)
    containsKeyMethod := completions.GetType().GetMethod("ContainsKey", keyParameterTypes)
    itemProperty := completions.GetType().GetProperty("Item")
    if containsKeyMethod == null || itemProperty == null {
        throw new InvalidOperationException("The production completions dictionary contract was incomplete.")
    }

    keyArguments := new object?[](1)
    SetQueryObject(keyArguments, 0, groupKey)
    containsValue := containsKeyMethod.Invoke(completions, keyArguments)
    if containsValue == null || containsValue.ToString() != "True" {
        return ""
    }

    group := itemProperty.GetValue(completions, keyArguments) as IList
    if group == null {
        return ""
    }

    names := ""
    index := 0
    while index < group.Count {
        item := group[index]
        if item != null {
            itemName := QueryCompletionProperty(item, "Name")
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

func QueryCompletionNamesContain(names: string, expected: string): bool {
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

test "loading a multi-file project with imports completes and answers cross-file member completions" {
    fixtureRoot := WriteQueryCompletionsFixture()

    // LoadProject is the call that used to spin for tens of minutes; reaching the asserts below at
    // all is the regression proof, and the answers pin that the analysis was CORRECT, not merely
    // fast — the receiver is resolved through the cross-file import the namespace scan validates.
    snapshot := LoadQueryCompletionsSnapshot(fixtureRoot)
    completionAnswer := AskQueryCompletions(snapshot, "Program.nl", 8, 18)

    context := QueryCompletionProperty(completionAnswer, "Context")
    if context == null {
        throw new InvalidOperationException("The production completion result had no context.")
    }
    assert context.ToString() == "MemberAccess"

    receiver := QueryCompletionProperty(completionAnswer, "Receiver")
    if receiver == null {
        throw new InvalidOperationException("The production completion result had no receiver.")
    }
    assert receiver.ToString() == "sensor"

    propertyNames := QueryCompletionGroupNames(completionAnswer, "properties")
    assert QueryCompletionNamesContain(propertyNames, "Name")
    assert QueryCompletionNamesContain(propertyNames, "Reading")

    // THE VISIBILITY LEAK, END TO END. `calibration` is camelCase — unexported under N#'s Go-shaped
    // rule — and `Program.nl` is in `Regression.App`, another package. Offering it here means
    // offering an NL308: the analyzer refuses the read the moment the editor writes it.
    assert !QueryCompletionNamesContain(propertyNames, "calibration")

    // THE CONTROL, WITHOUT WHICH THE FILTER WOULD BE A REGRESSION. The same field, asked from a file
    // that shares the declaring package, is still offered — because `nlc check` accepts that read.
    neighbourAnswer := AskQueryCompletions(snapshot, "Neighbour.nl", 4, 19)
    neighbourNames := QueryCompletionGroupNames(neighbourAnswer, "properties")
    assert QueryCompletionNamesContain(neighbourNames, "Name")
    assert QueryCompletionNamesContain(neighbourNames, "calibration")

    Directory.Delete(fixtureRoot, true)
}
