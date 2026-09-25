namespace NSharpLang.CensusVisibility.Tests

import System
import System.Collections
import System.IO


// THE TOOLING HALF OF THE SAME RULE, over TWO FILES WRITTEN TO DISK AND LOADED AS A PROJECT.
//
// A compiler that resolves a name and an editor that cannot find it are two different products, so
// the ruling is asserted twice: once by the blocks next door, which RUN the emitted code, and once
// here, through the same `CodeIntelligenceService` entry points the `nlc query` commands and the
// language server call. Measured before the fix on a two-file project in namespace `X`:
//
//   query def  B.nl:7:12  -> ok:false, "No symbol found at B.nl:7:12"
//   query refs A.nl:3:6   -> count 2 (both inside A.nl; B.nl's two uses were invisible)
//
// The NEGATIVE half is here too, and it has to be: a cross-namespace reference must still FAIL, and
// the only place an N# test can watch a diagnostic being produced is a real analysis over real
// files. `Compiler.dll` holds `CodeIntelligenceService`, so the route is reflection, exactly as
// `tests/native/query-integration` established.
func SetVisibilityObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func SetVisibilityInt(values: object?[], index: int, value: int) {
    boxed: object = value
    values[index] = boxed
}

func VisibilityServiceType(): Type {
    found := Type.GetType("NSharpLang.Compiler.CodeIntelligence.CodeIntelligenceService, Compiler")
    if found == null {
        throw new InvalidOperationException("The production code-intelligence service type was not loadable.")
    }

    return found
}

func VisibilityService(): object {
    serviceType := VisibilityServiceType()
    serviceConstructor := serviceType.GetConstructor(new Type[](0))
    if serviceConstructor == null {
        throw new InvalidOperationException("The production code-intelligence service was not constructible.")
    }

    return serviceConstructor.Invoke(new object?[](0))
}

func VisibilityInvoke(methodName: string, args: object?[]): object? {
    serviceType := VisibilityServiceType()
    method := serviceType.GetMethod(methodName)
    if method == null {
        throw new InvalidOperationException("The production entry point was not found: " + methodName)
    }

    return method.Invoke(VisibilityService(), args)
}

func VisibilityRequire(value: object?, what: string): object {
    if value == null {
        throw new InvalidOperationException("The production query answered nothing: " + what)
    }

    return value
}

func VisibilityIsNothing(value: object?): bool {
    return value == null
}

func VisibilityProperty(owner: object, propertyName: string): object? {
    ownerType := owner.GetType()
    ownerProperty := ownerType.GetProperty(propertyName)
    if ownerProperty != null {
        return ownerProperty.GetValue(owner)
    }

    ownerField := ownerType.GetField(propertyName)
    if ownerField == null {
        throw new InvalidOperationException("The production result has no " + propertyName + " member.")
    }

    return ownerField.GetValue(owner)
}

func VisibilityText(owner: object, propertyName: string): string {
    value := VisibilityProperty(owner, propertyName)
    if value == null {
        return ""
    }

    return value.ToString() ?? ""
}

func VisibilityInt(owner: object, propertyName: string): int {
    value := VisibilityProperty(owner, propertyName)
    if value == null {
        return -1
    }

    return Convert.ToInt32(value)
}

func VisibilityLoadProject(projectRoot: string): object {
    loadParameterTypes := new Type[](1)
    loadParameterTypes[0] = typeof(string)
    method := VisibilityServiceType().GetMethod("LoadProject", loadParameterTypes)
    if method == null {
        throw new InvalidOperationException("The production LoadProject entry point was not found.")
    }

    args := new object?[](1)
    SetVisibilityObject(args, 0, projectRoot)
    return VisibilityRequire(method.Invoke(VisibilityService(), args), "LoadProject")
}

func VisibilityPositionArgs(snapshot: object, sourceFile: string, line: int, col: int): object?[] {
    args := new object?[](4)
    SetVisibilityObject(args, 0, snapshot)
    SetVisibilityObject(args, 1, sourceFile)
    SetVisibilityInt(args, 2, line)
    SetVisibilityInt(args, 3, col)
    return args
}

func VisibilityFindDefinition(snapshot: object, sourceFile: string, line: int, col: int): object? {
    return VisibilityInvoke("FindDefinition", VisibilityPositionArgs(snapshot, sourceFile, line, col))
}

func VisibilityFindReferences(snapshot: object, sourceFile: string, line: int, col: int): IList {
    answer := VisibilityInvoke("FindReferences", VisibilityPositionArgs(snapshot, sourceFile, line, col))
    list := answer as IList
    if list == null {
        throw new InvalidOperationException("The production FindReferences answered no list.")
    }

    return list
}

func VisibilityGetDiagnostics(snapshot: object, sourceFile: string?): IList {
    args := new object?[](2)
    SetVisibilityObject(args, 0, snapshot)
    SetVisibilityObject(args, 1, sourceFile)
    answer := VisibilityInvoke("GetDiagnostics", args)
    list := answer as IList
    if list == null {
        throw new InvalidOperationException("The production GetDiagnostics answered no list.")
    }

    return list
}

// One row per reference — file name, line and column — joined so the whole answer is stated at once
// rather than probed for the entries a weaker claim expects.
func VisibilityReferenceRows(references: IList): string {
    text := ""
    index := 0
    while index < references.Count {
        item := references[index]
        index = index + 1
        if item == null {
            continue
        }

        if text.Length > 0 {
            text = text + "; "
        }
        text = text + Path.GetFileName(VisibilityText(item, "File")) + ":" + VisibilityInt(item, "Line").ToString() + ":" + VisibilityInt(item, "Column").ToString()
    }

    return text
}

func VisibilityDiagnosticRows(diagnostics: IList): string {
    text := ""
    index := 0
    while index < diagnostics.Count {
        item := diagnostics[index]
        index = index + 1
        if item == null {
            continue
        }

        if text.Length > 0 {
            text = text + "; "
        }
        text = text + VisibilityText(item, "Code") + " " + VisibilityInt(item, "Line").ToString() + ":" + VisibilityInt(item, "Column").ToString() + " " + VisibilityText(item, "Message")
    }

    return text
}

func VisibilityTempRoot(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-visibility-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func VisibilityWriteProject(projectRoot: string) {
    File.WriteAllText(Path.Combine(projectRoot, "project.yml"), "name: VisibilityTemp\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
}

func VisibilityWriteSource(projectRoot: string, fileName: string, source: string) {
    File.WriteAllText(Path.Combine(projectRoot, fileName), source)
}

func VisibilityDeleteTemp(projectRoot: string) {
    if Directory.Exists(projectRoot) {
        Directory.Delete(projectRoot, true)
    }
}

// The declaring half of the fixture: `formatTypeRef` on line 3, column 6, and one use of its own on
// line 8.
func VisibilityDeclaringSource(): string {
    return "namespace X\n\nfunc formatTypeRef(t: string): string {\n    return \"<\" + t + \">\"\n}\n\nfunc Exported(t: string): string {\n    return formatTypeRef(t)\n}\n"
}

// The using half: same namespace, no import. A direct call on line 7 column 12 and a method group
// on line 11 column 25.
func VisibilityUsingSource(): string {
    return "namespace X\n\nimport System.Collections.Generic\nimport System.Linq\n\nfunc UseIt(t: string): string {\n    return formatTypeRef(t)\n}\n\nfunc UseGroup(names: List<string>): List<string> {\n    return names.Select(formatTypeRef).ToList()\n}\n"
}

func VisibilityCompletionEngineType(): Type {
    found := Type.GetType("NSharpLang.Compiler.CodeIntelligence.CompletionEngine, Compiler")
    if found == null {
        throw new InvalidOperationException("The production completion engine type was not loadable.")
    }

    return found
}

func VisibilityCompletionGroupNames(snapshot: object, sourceFile: string, line: int, col: int, groupKey: string): string {
    engineType := VisibilityCompletionEngineType()
    engineConstructor := engineType.GetConstructor(new Type[](0))
    if engineConstructor == null {
        throw new InvalidOperationException("The production completion engine was not constructible.")
    }

    method := engineType.GetMethod("GetCompletions")
    if method == null {
        throw new InvalidOperationException("The production GetCompletions entry point was not found.")
    }

    args := new object?[](5)
    SetVisibilityObject(args, 0, snapshot)
    SetVisibilityObject(args, 1, sourceFile)
    SetVisibilityInt(args, 2, line)
    SetVisibilityInt(args, 3, col)
    falseValue: object = false
    args[4] = falseValue
    answer := VisibilityRequire(method.Invoke(engineConstructor.Invoke(new object?[](0)), args), "GetCompletions")

    groups := VisibilityRequire(VisibilityProperty(answer, "Completions"), "Completions") as IDictionary
    if groups == null {
        throw new InvalidOperationException("The production completion answer carried no groups.")
    }

    if !groups.Contains(groupKey) {
        return "<no-group>"
    }

    items := groups[groupKey] as IList
    if items == null {
        return "<no-group>"
    }

    text := ""
    index := 0
    while index < items.Count {
        item := items[index]
        index = index + 1
        if item == null {
            continue
        }

        if text.Length > 0 {
            text = text + ","
        }
        text = text + VisibilityText(item, "Name")
    }

    return text
}

// The `ImportNamespace` one named row carries, through the SAME production engine call: `<none>` for
// a name already in scope, `<absent>` for a name the list does not offer at all.
func VisibilityCompletionImportNamespace(snapshot: object, sourceFile: string, line: int, col: int, groupKey: string, itemName: string): string {
    engineType := VisibilityCompletionEngineType()
    engineConstructor := engineType.GetConstructor(new Type[](0))
    if engineConstructor == null {
        throw new InvalidOperationException("The production completion engine was not constructible.")
    }

    method := engineType.GetMethod("GetCompletions")
    if method == null {
        throw new InvalidOperationException("The production GetCompletions entry point was not found.")
    }

    args := new object?[](5)
    SetVisibilityObject(args, 0, snapshot)
    SetVisibilityObject(args, 1, sourceFile)
    SetVisibilityInt(args, 2, line)
    SetVisibilityInt(args, 3, col)
    falseValue: object = false
    args[4] = falseValue
    answer := VisibilityRequire(method.Invoke(engineConstructor.Invoke(new object?[](0)), args), "GetCompletions")

    groups := VisibilityRequire(VisibilityProperty(answer, "Completions"), "Completions") as IDictionary
    if groups == null {
        throw new InvalidOperationException("The production completion answer carried no groups.")
    }

    if !groups.Contains(groupKey) {
        return "<absent>"
    }

    items := groups[groupKey] as IList
    if items == null {
        return "<absent>"
    }

    index := 0
    while index < items.Count {
        item := items[index]
        index = index + 1
        if item == null {
            continue
        }

        if VisibilityText(item, "Name") == itemName {
            importNamespace := VisibilityProperty(item, "ImportNamespace")
            if importNamespace == null {
                return "<none>"
            }

            return importNamespace.ToString() ?? "<none>"
        }
    }

    return "<absent>"
}

test "go-to-definition crosses a file boundary to a camelCase function of the same namespace" {
    projectRoot := VisibilityTempRoot()
    try {
        VisibilityWriteProject(projectRoot)
        VisibilityWriteSource(projectRoot, "A.nl", VisibilityDeclaringSource())
        VisibilityWriteSource(projectRoot, "B.nl", VisibilityUsingSource())
        snapshot := VisibilityLoadProject(projectRoot)

        // The DIRECT CALL. Before the fix this answered nothing at all, which the CLI renders as
        // `{"ok": false, "error": {"code": "noSymbol"}}`.
        definition := VisibilityRequire(VisibilityFindDefinition(snapshot, "B.nl", 7, 12), "FindDefinition at the direct call")
        assert VisibilityText(definition, "Name") == "formatTypeRef"
        assert VisibilityText(definition, "Kind") == "function"
        assert Path.GetFileName(VisibilityText(definition, "File")) == "A.nl"
        assert VisibilityInt(definition, "Line") == 3
        assert VisibilityInt(definition, "Column") == 6

        // The METHOD GROUP position answers the same declaration: naming a function is naming it
        // whether or not the name is followed by an argument list.
        groupDefinition := VisibilityRequire(VisibilityFindDefinition(snapshot, "B.nl", 11, 25), "FindDefinition at the method group")
        assert Path.GetFileName(VisibilityText(groupDefinition, "File")) == "A.nl"
        assert VisibilityInt(groupDefinition, "Line") == 3
    } finally {
        VisibilityDeleteTemp(projectRoot)
    }
}

test "find-references over a camelCase function answers the whole namespace, not one file" {
    projectRoot := VisibilityTempRoot()
    try {
        VisibilityWriteProject(projectRoot)
        VisibilityWriteSource(projectRoot, "A.nl", VisibilityDeclaringSource())
        VisibilityWriteSource(projectRoot, "B.nl", VisibilityUsingSource())
        snapshot := VisibilityLoadProject(projectRoot)

        // FOUR rows: the declaration, its own file's use, and BOTH of the other file's — the direct
        // call and the method group. Before the fix this answered two, and a rename driven off it
        // would have silently left B.nl broken.
        references := VisibilityFindReferences(snapshot, "A.nl", 3, 6)
        assert VisibilityReferenceRows(references) == "A.nl:3:6; A.nl:8:12; B.nl:7:12; B.nl:11:25"

        // Asking from the USING file finds the same set: references are a property of the symbol,
        // not of the file the question was asked in.
        fromUse := VisibilityFindReferences(snapshot, "B.nl", 7, 12)
        assert VisibilityReferenceRows(fromUse) == "A.nl:3:6; A.nl:8:12; B.nl:7:12; B.nl:11:25"
    } finally {
        VisibilityDeleteTemp(projectRoot)
    }
}

test "a two-file namespace analyses clean, and a camelCase name from ANOTHER namespace does not" {
    projectRoot := VisibilityTempRoot()
    try {
        VisibilityWriteProject(projectRoot)
        VisibilityWriteSource(projectRoot, "A.nl", VisibilityDeclaringSource())
        VisibilityWriteSource(projectRoot, "B.nl", VisibilityUsingSource())
        snapshot := VisibilityLoadProject(projectRoot)

        // The POSITIVE contract, as the analyzer states it: nothing at all is reported. Before the
        // fix this file reported NL412 at 7:12, NL402 at 11:18 and NL301 at 11:25.
        assert VisibilityDiagnosticRows(VisibilityGetDiagnostics(snapshot, "B.nl")) == ""
        assert VisibilityGetDiagnostics(snapshot, null).Count == 0
    } finally {
        VisibilityDeleteTemp(projectRoot)
    }

    negativeRoot := VisibilityTempRoot()
    try {
        VisibilityWriteProject(negativeRoot)
        VisibilityWriteSource(negativeRoot, "A.nl", VisibilityDeclaringSource())
        // The SAME using file, moved to namespace `Y` and importing `X`. An import does not buy
        // access to what the namespace did not export, so both the camelCase FUNCTION and — the
        // half that always behaved this way — a camelCase TYPE are refused, by code and by message.
        VisibilityWriteSource(negativeRoot, "C.nl", "namespace Y\n\nimport X\n\nfunc UseIt(t: string): string {\n    return formatTypeRef(t)\n}\n")
        negativeSnapshot := VisibilityLoadProject(negativeRoot)

        rows := VisibilityDiagnosticRows(VisibilityGetDiagnostics(negativeSnapshot, "C.nl"))
        assert rows == "NL308 6:12 'formatTypeRef' is not exported from package/namespace 'X' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
    } finally {
        VisibilityDeleteTemp(negativeRoot)
    }
}

test "completion at an identifier position offers the namespace's other files, camelCase included" {
    projectRoot := VisibilityTempRoot()
    try {
        VisibilityWriteProject(projectRoot)
        VisibilityWriteSource(projectRoot, "A.nl", VisibilityDeclaringSource())
        // A caret three characters into a name, in a file that declares one function of its own.
        VisibilityWriteSource(projectRoot, "B.nl", "namespace X\n\nfunc UseIt(t: string): string {\n    return for\n}\n")
        snapshot := VisibilityLoadProject(projectRoot)

        // The file's OWN function first (the semantic model's), then A.nl's in source order — the
        // camelCase one and the exported one alike, because inside the namespace they are equally
        // visible. Before this the answer was `UseIt` alone.
        assert VisibilityCompletionGroupNames(snapshot, "B.nl", 4, 15, "functions") == "UseIt,formatTypeRef,Exported"
    } finally {
        VisibilityDeleteTemp(projectRoot)
    }

    // FROM ANOTHER NAMESPACE THE CAMELCASE ONE IS STILL OFFERED NOWHERE: naming it there is an
    // NL308, and no import line fixes that. The EXPORTED one IS offered — it used not to be, which
    // left the project's own helpers invisible to the one command an LLM has for "what can I call
    // here" — and because `C.nl` already writes `import X`, it is in scope as written and carries no
    // `ImportNamespace` at all.
    strangerRoot := VisibilityTempRoot()
    try {
        VisibilityWriteProject(strangerRoot)
        VisibilityWriteSource(strangerRoot, "A.nl", VisibilityDeclaringSource())
        VisibilityWriteSource(strangerRoot, "C.nl", "namespace Y\n\nimport X\n\nfunc UseIt(t: string): string {\n    return for\n}\n")
        strangerSnapshot := VisibilityLoadProject(strangerRoot)

        assert VisibilityCompletionGroupNames(strangerSnapshot, "C.nl", 6, 15, "functions") == "UseIt,Exported"
    } finally {
        VisibilityDeleteTemp(strangerRoot)
    }

    // AND WITHOUT THE IMPORT LINE, THE SAME EXPORTED FUNCTION CARRIES THE IMPORT IT OWES. `D.nl` is
    // `C.nl` with `import X` removed: writing `Exported(...)` there is NL412 until the line exists,
    // so the offer names the namespace to add rather than silently handing over a broken call.
    unimportedRoot := VisibilityTempRoot()
    try {
        VisibilityWriteProject(unimportedRoot)
        VisibilityWriteSource(unimportedRoot, "A.nl", VisibilityDeclaringSource())
        VisibilityWriteSource(unimportedRoot, "D.nl", "namespace Y\n\nfunc UseIt(t: string): string {\n    return for\n}\n")
        unimportedSnapshot := VisibilityLoadProject(unimportedRoot)

        assert VisibilityCompletionGroupNames(unimportedSnapshot, "D.nl", 4, 15, "functions") == "UseIt,Exported"
        assert VisibilityCompletionImportNamespace(unimportedSnapshot, "D.nl", 4, 15, "functions", "Exported") == "X"
        assert VisibilityCompletionImportNamespace(unimportedSnapshot, "D.nl", 4, 15, "functions", "UseIt") == "<none>"
        assert VisibilityCompletionImportNamespace(unimportedSnapshot, "D.nl", 4, 15, "functions", "formatTypeRef") == "<absent>"
    } finally {
        VisibilityDeleteTemp(unimportedRoot)
    }
}
