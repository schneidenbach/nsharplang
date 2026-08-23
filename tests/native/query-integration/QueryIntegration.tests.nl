namespace NSharpLang.QueryIntegration.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Text.Json


// THE `nlc query` TOOLCHAIN, IN N#.
//
// These replace `tests/QueryIntegrationTests.cs` WHOLE — 65 `[Fact]`s, 1,000 declaration lines,
// 209 in-body `Assert.` calls and 219 decoded claim rows — against the same fixture corpus the
// deleted file used: the shipped examples (`01-hello-world`, `05-unions`, `06-classes-and-records`,
// `12-multi-file-projects/MultiFileProject`), the `tests/fixtures/issue-tracker` project, and
// temporary projects written and deleted per test block.
//
// WHY THERE IS NO PROCESS KERNEL HERE, WHICH IS THE FINDING THAT DECIDED THIS SLICE. The route
// sketch inherited from slice 38 predicted that this cluster needs PROCESS LAUNCH — that the bodies
// shell out to `nlc` and read stdout. THEY DO NOT. Across 1,322 lines the CODE class contains
// `Process` / `ProcessStartInfo` / `StandardOutput` / `WaitForExit` / `ExitCode` exactly ZERO times;
// the only `nlc` in the file is one doc comment and one expected-value string literal. All 65
// bodies call `CodeIntelligenceService`, `CompletionEngine` and `OutputFormatter` IN PROCESS. A
// spawn kernel would have had no consumer, and task 020 forbids unused infrastructure, so none is
// built. The reflection route below is the one the arc has used since slice 28.
//
// WHY THERE IS NO SHARED FIXTURE CACHE. The deleted class held five `??=` lazy snapshot fields.
// Two facts retire them. First, a mutable static FIELD declines at columnar emit in every form
// tried (`int`, `object?`, `Dictionary<,>`, with and without an initializer), and so does
// `AppDomain.CurrentDomain` as a data-slot escape hatch — both minimised out-of-repo against
// `nlc test`. Second, the cache is not worth having: a timing probe measured `LoadProject` at 4 ms
// (`01-hello-world`) to 81 ms (`issue-tracker`) per call. Loading inside each block costs seconds
// across the whole project and buys HERMETIC blocks, which the shared snapshot did not have.
//
// WHAT THE MIGRATION PINS THAT THE DELETED ASSERTIONS COULD NOT SEE. One of the 65 was
// STRUCTURALLY VACUOUS and the perturbation matrix found it: `Diagnostics_HaveCorrectCodeFormat`
// asserted `All(d => StartsWith("NL", d.Code))` over `GetDiagnostics(HelloWorld)`, and that answer
// is EMPTY — a runtime census measured ZERO diagnostics from all four fixture projects — so
// `Assert.All` ranged over nothing and no code was ever inspected. Its two clean-compile neighbours
// filtered the same empty list by severity. All three are stated as runtime runs below.
//
// Two substitutions are marked at their sites: the two bodies that walked
// `snapshot.CompilationUnits.Keys` only to recover a file path they had just written now compute
// that path directly, and the one body that walked `snapshot.SemanticModels` only to build a
// FAILURE MESSAGE drops the walk, because a message is not a claim.


// ─── THE OBJECT?[] STORES ─────────────────────────────────────────────────────────────────────
// A boxing store into an `object?[]` element declines at emit when the source is an `int`-typed
// PARAMETER written straight into the element; routing it through a typed `object` local emits.

func SetQueryObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func SetQueryInt(values: object?[], index: int, value: int) {
    boxed: object = value
    values[index] = boxed
}

func SetQueryBool(values: object?[], index: int, value: bool) {
    boxed: object = value
    values[index] = boxed
}


// ─── THE CORPUS ON DISK ───────────────────────────────────────────────────────────────────────

func QueryRepositoryRoot(): string {
    current: string? = Path.GetFullPath(Environment.CurrentDirectory)
    while current != null {
        value := current ?? ""
        if File.Exists(Path.Combine(value, "AGENTS.md"))
            && Directory.Exists(Path.Combine(value, "src"))
            && Directory.Exists(Path.Combine(value, "tests")) {
            return value
        }
        parent := Path.GetDirectoryName(value)
        if parent == null || parent == "" || parent == value {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not find the repository root from the runner's working directory.")
}

func QueryExamplesDir(): string {
    candidate := Path.Combine(QueryRepositoryRoot(), "examples")
    if !Directory.Exists(Path.Combine(candidate, "01-hello-world")) {
        throw new InvalidOperationException("Could not find examples directory")
    }

    return candidate
}

func QueryFixturesDir(): string {
    candidate := Path.Combine(QueryRepositoryRoot(), "tests", "fixtures")
    if !Directory.Exists(Path.Combine(candidate, "issue-tracker")) {
        throw new InvalidOperationException("Could not find tests/fixtures directory")
    }

    return candidate
}


// ─── THE PRODUCTION TYPES, REACHED THE WAY EVERY NATIVE PROJECT REACHES THEM ──────────────────

func QueryType(typeName: string): Type {
    found := Type.GetType(typeName)
    if found == null {
        throw new InvalidOperationException("The production type was not loadable: " + typeName)
    }

    return found
}

func QueryServiceType(): Type {
    return QueryType("NSharpLang.Compiler.CodeIntelligence.CodeIntelligenceService, Compiler")
}

func QueryFormatterType(): Type {
    return QueryType("NSharpLang.Compiler.CodeIntelligence.OutputFormatter, Compiler")
}

func QueryCompletionEngineType(): Type {
    return QueryType("NSharpLang.Compiler.CodeIntelligence.CompletionEngine, Compiler")
}

func QueryDiagnosticResultType(): Type {
    return QueryType("NSharpLang.Compiler.CodeIntelligence.DiagnosticResult, NSharpLang.Compiler.BootstrapServices")
}

func QueryService(): object {
    serviceType := QueryServiceType()
    serviceConstructor := serviceType.GetConstructor(new Type[](0))
    if serviceConstructor == null {
        throw new InvalidOperationException("The production code-intelligence service was not constructible.")
    }

    return serviceConstructor.Invoke(new object?[](0))
}

// A user function whose declared RETURN TYPE is `MethodInfo` declines at columnar emit, and so does
// a `GetMethod(name, Type[])` whose type array arrives as a PARAMETER — both minimised out-of-repo
// against `nlc test`. The kernel therefore resolves and invokes in one step, and the two places that
// need overload disambiguation build their `Type[]` as a LOCAL at the call site.
func QueryCall(owner: Type, methodName: string, target: object?, args: object?[]): object? {
    method := owner.GetMethod(methodName)
    if method == null {
        throw new InvalidOperationException("The production entry point was not found: " + methodName)
    }

    return method.Invoke(target, args)
}

func QueryInvoke(methodName: string, args: object?[]): object? {
    return QueryCall(QueryServiceType(), methodName, QueryService(), args)
}

// `assert <object? expression> == null` declines at emit; the comparison lives inside a function,
// which is the same shape `QueryRequire` already uses for the positive case.
func QueryIsNothing(value: object?): bool {
    return value == null
}

func QueryRequire(value: object?, what: string): object {
    if value == null {
        throw new InvalidOperationException("The production query answered nothing: " + what)
    }

    return value
}

func QueryRequireList(value: object?, what: string): IList {
    list := value as IList
    if list == null {
        throw new InvalidOperationException("The production query answered no list: " + what)
    }

    return list
}


// ─── READING A PRODUCTION RESULT ──────────────────────────────────────────────────────────────

// `CallGraphResult`, `CallSiteResult`, `ImplementorsResult` and `ImplementorResult` are RECORDS,
// and a record's positional members are FIELDS rather than properties, so the reader tries both.
func QueryProperty(owner: object, propertyName: string): object? {
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

func QueryText(owner: object, propertyName: string): string {
    value := QueryProperty(owner, propertyName)
    if value == null {
        return ""
    }

    return value.ToString() ?? ""
}

func QueryInt(owner: object, propertyName: string): int {
    value := QueryProperty(owner, propertyName)
    if value == null {
        throw new InvalidOperationException("The production result answered no " + propertyName + ".")
    }

    return Convert.ToInt32(value)
}

func QueryChild(owner: object, propertyName: string): object {
    return QueryRequire(QueryProperty(owner, propertyName), propertyName)
}

func QueryChildList(owner: object, propertyName: string): IList {
    return QueryRequireList(QueryProperty(owner, propertyName), propertyName)
}


// ─── ROWS ─────────────────────────────────────────────────────────────────────────────────────
// Every production collection is flattened to a `List<string>` of pipe-joined rows, so a claim is
// a row match and never a closure the emit route cannot spell.

func QueryRow(parts: List<string>): string {
    text := ""
    index := 0
    while index < parts.Count {
        if index > 0 {
            text = text + "|"
        }
        text = text + parts[index]
        index = index + 1
    }

    return text
}

func QueryRowOf2(first: string, second: string): string {
    parts := new List<string>()
    parts.Add(first)
    parts.Add(second)
    return QueryRow(parts)
}

func RowsHavePrefix(rows: List<string>, prefix: string): bool {
    index := 0
    while index < rows.Count {
        if rows[index].StartsWith(prefix, StringComparison.Ordinal) {
            return true
        }
        index = index + 1
    }

    return false
}

func RowsCountPrefix(rows: List<string>, prefix: string): int {
    seen := 0
    index := 0
    while index < rows.Count {
        if rows[index].StartsWith(prefix, StringComparison.Ordinal) {
            seen = seen + 1
        }
        index = index + 1
    }

    return seen
}

func RowsCountContaining(rows: List<string>, needle: string): int {
    seen := 0
    index := 0
    while index < rows.Count {
        if rows[index].Contains(needle, StringComparison.Ordinal) {
            seen = seen + 1
        }
        index = index + 1
    }

    return seen
}

func RowsCountBoth(rows: List<string>, first: string, second: string): int {
    seen := 0
    index := 0
    while index < rows.Count {
        if rows[index].Contains(first, StringComparison.Ordinal) && rows[index].Contains(second, StringComparison.Ordinal) {
            seen = seen + 1
        }
        index = index + 1
    }

    return seen
}

func RowsHaveExact(rows: List<string>, value: string): bool {
    index := 0
    while index < rows.Count {
        if rows[index] == value {
            return true
        }
        index = index + 1
    }

    return false
}

func RowsCountExact(rows: List<string>, value: string): int {
    seen := 0
    index := 0
    while index < rows.Count {
        if rows[index] == value {
            seen = seen + 1
        }
        index = index + 1
    }

    return seen
}

func RowsEndingWith(rows: List<string>, suffix: string): int {
    seen := 0
    index := 0
    while index < rows.Count {
        if rows[index].EndsWith(suffix, StringComparison.Ordinal) {
            seen = seen + 1
        }
        index = index + 1
    }

    return seen
}

func QueryJoin(rows: List<string>): string {
    text := ""
    index := 0
    while index < rows.Count {
        text = text + rows[index] + "\n"
        index = index + 1
    }

    return text
}


// ─── THE ELEVEN SERVICE ENTRY POINTS ──────────────────────────────────────────────────────────

func QueryLoadProject(projectRoot: string): object {
    loadParameterTypes := new Type[](1)
    loadParameterTypes[0] = typeof(string)
    serviceType := QueryServiceType()
    method := serviceType.GetMethod("LoadProject", loadParameterTypes)
    if method == null {
        throw new InvalidOperationException("The production LoadProject entry point was not found.")
    }

    args := new object?[](1)
    SetQueryObject(args, 0, projectRoot)
    service := QueryService()
    return QueryRequire(method.Invoke(service, args), "LoadProject")
}

// `Enum.Parse` and `System.Text.Json` CANNOT COEXIST in one compilation unit on this emit path —
// minimised out-of-repo to exactly those two spellings — and this project needs both. The enum
// argument is therefore taken from the production answer itself: the boxed `SymbolKind` read off a
// `SymbolResult` IS the value the filter overload wants, so no enum API is spelled at all.
func QueryGetSymbols(snapshot: object, sourceFile: string?, kind: object?): IList {
    args := new object?[](3)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, sourceFile)
    SetQueryObject(args, 2, kind)
    return QueryRequireList(QueryInvoke("GetSymbols", args), "GetSymbols")
}

func QuerySymbolKindValue(symbols: IList, kind: string): object {
    index := 0
    while index < symbols.Count {
        item := symbols[index]
        if item != null && QueryText(item, "Kind") == kind {
            return QueryRequire(QueryProperty(item, "Kind"), "Kind")
        }
        index = index + 1
    }

    throw new InvalidOperationException("The production answer carried no symbol of kind " + kind + ".")
}

func QueryGetOutline(snapshot: object, sourceFile: string): object {
    args := new object?[](2)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, sourceFile)
    return QueryRequire(QueryInvoke("GetOutline", args), "GetOutline")
}

func QueryGetOutlineSingleFile(filePath: string): object {
    args := new object?[](1)
    SetQueryObject(args, 0, filePath)
    return QueryRequire(QueryInvoke("GetOutlineSingleFile", args), "GetOutlineSingleFile")
}

func QueryGetDiagnostics(snapshot: object, sourceFile: string?): IList {
    args := new object?[](2)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, sourceFile)
    return QueryRequireList(QueryInvoke("GetDiagnostics", args), "GetDiagnostics")
}

func QueryGetTypeAtPosition(snapshot: object, sourceFile: string, line: int, col: int): object? {
    args := new object?[](4)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, sourceFile)
    SetQueryInt(args, 2, line)
    SetQueryInt(args, 3, col)
    return QueryInvoke("GetTypeAtPosition", args)
}

func QueryFindDefinition(snapshot: object, sourceFile: string, line: int, col: int): object? {
    args := new object?[](4)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, sourceFile)
    SetQueryInt(args, 2, line)
    SetQueryInt(args, 3, col)
    return QueryInvoke("FindDefinition", args)
}

func QueryFindReferences(snapshot: object, sourceFile: string, line: int, col: int): IList {
    args := new object?[](4)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, sourceFile)
    SetQueryInt(args, 2, line)
    SetQueryInt(args, 3, col)
    return QueryRequireList(QueryInvoke("FindReferences", args), "FindReferences")
}

func QueryGetHoverInfo(snapshot: object, sourceFile: string, line: int, col: int): object? {
    args := new object?[](4)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, sourceFile)
    SetQueryInt(args, 2, line)
    SetQueryInt(args, 3, col)
    return QueryInvoke("GetHoverInfo", args)
}

func QueryGetCallGraph(snapshot: object, functionName: string?): object {
    args := new object?[](3)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, functionName)
    SetQueryInt(args, 2, 100)
    return QueryRequire(QueryInvoke("GetCallGraph", args), "GetCallGraph")
}

func QueryGetImplementors(snapshot: object, interfaceName: string): object {
    args := new object?[](2)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, interfaceName)
    return QueryRequire(QueryInvoke("GetImplementors", args), "GetImplementors")
}

func QueryGetCompletions(snapshot: object, sourceFile: string, line: int, col: int, includeKeywords: bool): object {
    engineType := QueryCompletionEngineType()
    engineConstructor := engineType.GetConstructor(new Type[](0))
    if engineConstructor == null {
        throw new InvalidOperationException("The production completion engine was not constructible.")
    }
    engine := engineConstructor.Invoke(new object?[](0))

    args := new object?[](5)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, sourceFile)
    SetQueryInt(args, 2, line)
    SetQueryInt(args, 3, col)
    SetQueryBool(args, 4, includeKeywords)
    return QueryRequire(QueryCall(engineType, "GetCompletions", engine, args), "GetCompletions")
}


// ─── THE FOUR FORMATTER ENTRY POINTS ──────────────────────────────────────────────────────────

func QueryFormatterJson(methodName: string, results: object?, projectRoot: string?): string {
    args := new object?[](2)
    SetQueryObject(args, 0, results)
    SetQueryObject(args, 1, projectRoot)
    answer := QueryRequire(QueryCall(QueryFormatterType(), methodName, null, args), methodName)
    return answer.ToString() ?? ""
}

func QueryOutlineJson(outline: object): string {
    args := new object?[](1)
    SetQueryObject(args, 0, outline)
    answer := QueryRequire(QueryCall(QueryFormatterType(), "OutlineToJson", null, args), "OutlineToJson")
    return answer.ToString() ?? ""
}


// ─── THE ROW SHAPES ───────────────────────────────────────────────────────────────────────────

func QuerySymbolRows(symbols: IList): List<string> {
    rows := new List<string>()
    index := 0
    while index < symbols.Count {
        item := symbols[index]
        if item != null {
            parts := new List<string>()
            parts.Add(QueryText(item, "Name"))
            parts.Add(QueryText(item, "Kind"))
            parts.Add(QueryText(item, "TypeName"))
            parts.Add(QueryText(item, "File"))
            parts.Add(QueryText(item, "Line"))
            parts.Add(QueryText(item, "Column"))
            rows.Add(QueryRow(parts))
        }
        index = index + 1
    }

    return rows
}

func QuerySymbolNames(symbols: IList): List<string> {
    names := new List<string>()
    index := 0
    while index < symbols.Count {
        item := symbols[index]
        if item != null {
            names.Add(QueryText(item, "Name"))
        }
        index = index + 1
    }

    return names
}

func QuerySymbolNamed(symbols: IList, name: string): object? {
    index := 0
    while index < symbols.Count {
        item := symbols[index]
        if item != null && QueryText(item, "Name") == name {
            return item
        }
        index = index + 1
    }

    return null
}

func QuerySymbolNamedOfKind(symbols: IList, name: string, kind: string): object? {
    index := 0
    while index < symbols.Count {
        item := symbols[index]
        if item != null && QueryText(item, "Name") == name && QueryText(item, "Kind") == kind {
            return item
        }
        index = index + 1
    }

    return null
}

func QueryMemberRows(owner: object): List<string> {
    rows := new List<string>()
    members := QueryProperty(owner, "Members") as IList
    if members == null {
        return rows
    }

    index := 0
    while index < members.Count {
        item := members[index]
        if item != null {
            rows.Add(QueryRowOf2(QueryText(item, "Name"), QueryText(item, "Kind")))
        }
        index = index + 1
    }

    return rows
}

func QueryHasMembers(owner: object): bool {
    return QueryProperty(owner, "Members") != null
}

func QueryOutlineRows(outline: object): List<string> {
    rows := new List<string>()
    entries := QueryProperty(outline, "Outline") as IList
    if entries == null {
        return rows
    }

    index := 0
    while index < entries.Count {
        item := entries[index]
        if item != null {
            parts := new List<string>()
            parts.Add(QueryText(item, "Name"))
            parts.Add(QueryText(item, "Kind"))
            parts.Add(QueryText(item, "Line"))
            rows.Add(QueryRow(parts))
        }
        index = index + 1
    }

    return rows
}

func QueryDiagnosticRows(diagnostics: IList): List<string> {
    rows := new List<string>()
    index := 0
    while index < diagnostics.Count {
        item := diagnostics[index]
        if item != null {
            parts := new List<string>()
            parts.Add(QueryText(item, "Code"))
            parts.Add(QueryText(item, "Severity"))
            parts.Add(QueryText(item, "File"))
            parts.Add(QueryText(item, "Line"))
            parts.Add(QueryText(item, "Column"))
            parts.Add(QueryText(item, "Length"))
            parts.Add(QueryText(item, "Suggestion"))
            rows.Add(QueryRow(parts))
        }
        index = index + 1
    }

    return rows
}

func QueryReferenceRows(references: IList): List<string> {
    rows := new List<string>()
    index := 0
    while index < references.Count {
        item := references[index]
        if item != null {
            parts := new List<string>()
            parts.Add(QueryText(item, "File"))
            parts.Add(QueryText(item, "Line"))
            parts.Add(QueryText(item, "Column"))
            parts.Add(QueryText(item, "IsDefinition"))
            parts.Add(QueryText(item, "Context"))
            rows.Add(QueryRow(parts))
        }
        index = index + 1
    }

    return rows
}

func QueryDefinitionReferenceCount(references: IList): int {
    seen := 0
    index := 0
    while index < references.Count {
        item := references[index]
        if item != null && QueryText(item, "IsDefinition") == "True" {
            seen = seen + 1
        }
        index = index + 1
    }

    return seen
}

func QueryCallSiteRows(owner: object, propertyName: string): List<string> {
    rows := new List<string>()
    sites := QueryChildList(owner, propertyName)
    index := 0
    while index < sites.Count {
        item := sites[index]
        if item != null {
            parts := new List<string>()
            parts.Add(QueryText(item, "Name"))
            parts.Add(QueryText(item, "File"))
            parts.Add(QueryText(item, "Line"))
            parts.Add(QueryText(item, "Column"))
            rows.Add(QueryRow(parts))
        }
        index = index + 1
    }

    return rows
}

func QueryImplementorRows(owner: object): List<string> {
    rows := new List<string>()
    results := QueryChildList(owner, "Results")
    index := 0
    while index < results.Count {
        item := results[index]
        if item != null {
            parts := new List<string>()
            parts.Add(QueryText(item, "TypeName"))
            parts.Add(QueryText(item, "Kind"))
            parts.Add(QueryText(item, "File"))
            parts.Add(QueryText(item, "Line"))
            parts.Add(QueryText(item, "Column"))
            rows.Add(QueryRow(parts))
        }
        index = index + 1
    }

    return rows
}

func QueryCompletionGroups(answer: object): object {
    return QueryRequire(QueryProperty(answer, "Completions"), "Completions")
}

func QueryCompletionHasGroup(answer: object, groupKey: string): bool {
    groups := QueryCompletionGroups(answer)
    keyTypes := new Type[](1)
    keyTypes[0] = typeof(string)
    groupsType := groups.GetType()
    containsKey := groupsType.GetMethod("ContainsKey", keyTypes)
    if containsKey == null {
        throw new InvalidOperationException("The production completions dictionary contract was incomplete.")
    }

    keyArguments := new object?[](1)
    SetQueryObject(keyArguments, 0, groupKey)
    answered := containsKey.Invoke(groups, keyArguments)
    if answered == null {
        return false
    }

    return answered.ToString() == "True"
}

func QueryCompletionNames(answer: object, groupKey: string): List<string> {
    names := new List<string>()
    if !QueryCompletionHasGroup(answer, groupKey) {
        return names
    }

    groups := QueryCompletionGroups(answer)
    groupsType := groups.GetType()
    itemProperty := groupsType.GetProperty("Item")
    if itemProperty == null {
        throw new InvalidOperationException("The production completions dictionary contract was incomplete.")
    }

    keyArguments := new object?[](1)
    SetQueryObject(keyArguments, 0, groupKey)
    group := itemProperty.GetValue(groups, keyArguments) as IList
    if group == null {
        return names
    }

    index := 0
    while index < group.Count {
        item := group[index]
        if item != null {
            names.Add(QueryText(item, "Name"))
        }
        index = index + 1
    }

    return names
}


// ─── THE BINDING MAP ──────────────────────────────────────────────────────────────────────────

func QueryBindings(snapshot: object): object {
    return QueryRequire(QueryProperty(snapshot, "Bindings"), "Bindings")
}

func QueryBindingAt(snapshot: object, filePath: string, line: int, col: int): object? {
    bindings := QueryBindings(snapshot)
    args := new object?[](3)
    SetQueryObject(args, 0, filePath)
    SetQueryInt(args, 1, line)
    SetQueryInt(args, 2, col)
    bindingsType := bindings.GetType()
    return QueryCall(bindingsType, "GetBindingAt", bindings, args)
}

func QueryProjectErrorRows(snapshot: object): List<string> {
    rows := new List<string>()
    errors := QueryChildList(snapshot, "AllErrors")
    index := 0
    while index < errors.Count {
        item := errors[index]
        if item != null {
            rows.Add(QueryRowOf2(QueryText(item, "Severity"), QueryText(item, "Message")))
        }
        index = index + 1
    }

    return rows
}


// ─── THE TWO SOURCE-SCANNING HELPERS THE DELETED FILE OWNED ───────────────────────────────────

func FindLineInFile(filePath: string, needle: string): int {
    return FindLineInFileAt(filePath, needle, 1)
}

func FindLineInFileAt(filePath: string, needle: string, occurrence: int): int {
    lines := File.ReadAllLines(filePath)
    matchesSeen := 0
    index := 0
    while index < lines.Length {
        if lines[index].Contains(needle, StringComparison.Ordinal) {
            matchesSeen = matchesSeen + 1
            if matchesSeen == occurrence {
                return index + 1
            }
        }
        index = index + 1
    }

    throw new InvalidOperationException("Could not find '" + needle + "' in " + filePath)
}

func FindColumnInFile(filePath: string, lineNumber: int, needle: string): int {
    return FindColumnInFileAt(filePath, lineNumber, needle, 1)
}

// The deleted helper carried the file's ONE non-body `Assert.` — a guard that the needle is on the
// line at all. It fires once per call site, which is why the 209 in-body claims decode to 219 rows.
func FindColumnInFileAt(filePath: string, lineNumber: int, needle: string, occurrence: int): int {
    lines := File.ReadAllLines(filePath)
    if lineNumber < 1 || lineNumber > lines.Length {
        throw new InvalidOperationException("Line " + lineNumber.ToString() + " is not in " + filePath)
    }

    line := lines[lineNumber - 1]
    startIndex := 0
    index := -1
    seen := 0
    while seen < occurrence {
        index = line.IndexOf(needle, startIndex, StringComparison.Ordinal)
        if index < 0 {
            throw new InvalidOperationException("Could not find '" + needle + "' on line " + lineNumber.ToString() + ": " + line)
        }
        startIndex = index + needle.Length
        seen = seen + 1
    }

    return index + 1
}

func FirstBlankLineInFile(filePath: string): int {
    lines := File.ReadAllLines(filePath)
    index := 0
    while index < lines.Length {
        if lines[index].Trim() == "" {
            return index + 1
        }
        index = index + 1
    }

    throw new InvalidOperationException("Could not find a blank line in " + filePath)
}


// ─── THE FIXTURE PROJECTS ─────────────────────────────────────────────────────────────────────

func QueryHelloWorld(): object {
    return QueryLoadProject(Path.Combine(QueryExamplesDir(), "01-hello-world"))
}

func QueryHelloWorldProgram(): string {
    return Path.Combine(QueryExamplesDir(), "01-hello-world", "Program.nl")
}

func QueryClassesAndRecords(): object {
    return QueryLoadProject(Path.Combine(QueryExamplesDir(), "06-classes-and-records"))
}

func QueryMultiFile(): object {
    return QueryLoadProject(Path.Combine(QueryExamplesDir(), "12-multi-file-projects", "MultiFileProject"))
}

func QueryMultiFileProgram(): string {
    return Path.Combine(QueryExamplesDir(), "12-multi-file-projects", "MultiFileProject", "Program.nl")
}

func QueryUnions(): object {
    return QueryLoadProject(Path.Combine(QueryExamplesDir(), "05-unions"))
}

func QueryIssueTracker(): object {
    return QueryLoadProject(Path.Combine(QueryFixturesDir(), "issue-tracker"))
}

// `Directory.CreateTempSubdirectory` declines at emit; the estate's temp-fixture shape is a GUID
// directory under `Path.GetTempPath()`, and every block that writes one deletes it.
func QueryTempRoot(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-query-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func QueryWriteProjectYaml(projectRoot: string, projectYaml: string) {
    File.WriteAllText(Path.Combine(projectRoot, "project.yml"), projectYaml)
}

func QueryDefaultProjectYaml(): string {
    return "name: QueryTemp\nversion: 1.0.0\nentry: Program.nl\noutputType: exe\ntargetFramework: net10.0\n"
}

func QueryWriteSource(projectRoot: string, relativePath: string, source: string) {
    fullPath := Path.Combine(projectRoot, relativePath)
    directory := Path.GetDirectoryName(fullPath)
    if directory != null {
        Directory.CreateDirectory(directory ?? "")
    }
    File.WriteAllText(fullPath, source)
}

func QueryDeleteTemp(projectRoot: string) {
    if Directory.Exists(projectRoot) {
        Directory.Delete(projectRoot, true)
    }
}

// The two duplicate-`Widget` corpora the deleted file wrote three times between them.
func QueryWriteDuplicateWidgets(projectRoot: string, fooMember: string, barMember: string) {
    QueryWriteSource(projectRoot, "Foo/Widget.nl", "namespace QueryTemp.Foo\n\nrecord Widget {\n    " + fooMember + "\n}\n")
    QueryWriteSource(projectRoot, "Bar/Widget.nl", "namespace QueryTemp.Bar\n\nrecord Widget {\n    " + barMember + "\n}\n")
}

func QueryWriteEmptyMain(projectRoot: string) {
    QueryWriteSource(projectRoot, "Program.nl", "namespace QueryTemp\n\nfunc Main() {\n}\n")
}


// ─── THE SYMBOL FILTER THE DELETED FILE OWNED ────────────────────────────────────────────────
// A FINDING, RECORDED AT ITS SITE. The deleted `BuildFilterRegex` carried the comment "Duplicate of
// the CLI's BuildSymbolFilterRegex — kept here for service-layer tests", and that CLI function NO
// LONGER EXISTS anywhere in `src/`: the two bodies that used it were pinning a matcher that lived
// only in the test file. Their PRODUCTION claim is that `Circle` and `Square` are both in the
// answered symbol set; the filter half is a test-local matcher either way. `Regex` itself is
// unavailable on this emit path — `new Regex(...)` declines in every arity and so does the static
// `Regex.IsMatch(input, pattern, options)`, while `Regex.Escape` compiles — so the same semantics
// are spelled directly: a case-insensitive anchored glob when the pattern has a `*`, and a
// case-insensitive substring when it does not.

func FilterMatches(name: string, pattern: string): bool {
    lowerName := name.ToLowerInvariant()
    lowerPattern := pattern.ToLowerInvariant()
    if !lowerPattern.Contains("*", StringComparison.Ordinal) {
        return lowerName.Contains(lowerPattern, StringComparison.Ordinal)
    }

    segments := lowerPattern.Split('*')
    position := 0
    index := 0
    while index < segments.Length {
        segment := segments[index]
        if segment != "" {
            found := lowerName.IndexOf(segment, position, StringComparison.Ordinal)
            if found < 0 {
                return false
            }
            if index == 0 && found != 0 {
                return false
            }
            position = found + segment.Length
        }
        index = index + 1
    }

    lastSegment := segments[segments.Length - 1]
    if lastSegment != "" && !lowerName.EndsWith(lastSegment, StringComparison.Ordinal) {
        return false
    }

    return true
}

func FilterNames(names: List<string>, pattern: string): List<string> {
    matched := new List<string>()
    index := 0
    while index < names.Count {
        if FilterMatches(names[index], pattern) {
            matched.Add(names[index])
        }
        index = index + 1
    }

    return matched
}


// A `JsonElement` INDEXER declines at emit; the array is walked with `EnumerateArray` instead,
// which is the spelling `tests/native/ownership-audit` already uses.
func QueryJsonAt(items: JsonElement, wanted: int): JsonElement {
    enumerator := items.EnumerateArray()
    seen := 0
    while enumerator.MoveNext() {
        if seen == wanted {
            return enumerator.Current
        }
        seen = seen + 1
    }

    throw new InvalidOperationException("The JSON array has no element at index " + wanted.ToString() + ".")
}


// THE GOLDEN CLUSTER'S INPUT, BUILT THE ONLY WAY THIS EMIT PATH ALLOWS.
//
// Two walls decided this shape, both minimised out-of-repo. `Activator.CreateInstance(type, args)`
// DECLINES while `type.GetConstructors()[0].Invoke(args)` emits, so the record is built through the
// constructor directly. And `Activator.CreateInstance` over the CLOSED GENERIC
// `List<DiagnosticResult>` declines too, so the list is MINTED BY PRODUCTION: a diagnostics query
// over a file that does not exist answers a fresh, empty `List<DiagnosticResult>` — exactly the
// argument the formatter wants, and one that cannot drift from what `GetDiagnostics` returns.
func QueryEmptyDiagnosticList(): IList {
    args := new object?[](2)
    SetQueryObject(args, 0, QueryHelloWorld())
    SetQueryObject(args, 1, "DoesNotExist.nl")
    return QueryRequireList(QueryInvoke("GetDiagnostics", args), "GetDiagnostics")
}

func QueryGoldenClusterJson(): string {
    diagnosticType := QueryDiagnosticResultType()
    constructors := diagnosticType.GetConstructors()
    if constructors.Length != 1 {
        throw new InvalidOperationException("The production diagnostic record no longer has exactly one constructor.")
    }
    diagnosticConstructor := constructors[0]

    diagnostics := QueryEmptyDiagnosticList()
    firstFields := QueryGoldenDiagnostic("UserManager", 42, "let manager := UserManager.Create()")
    diagnostics.Add(QueryRequire(diagnosticConstructor.Invoke(firstFields), "DiagnosticResult"))
    secondFields := QueryGoldenDiagnostic("RoleManager", 43, "let roles := RoleManager.Create()")
    diagnostics.Add(QueryRequire(diagnosticConstructor.Invoke(secondFields), "DiagnosticResult"))

    return QueryFormatterJson("DiagnosticClustersToJson", diagnostics, "/redacted/sample-project")
}

// ─── THE GOLDEN CLUSTER'S TWO DIAGNOSTICS ─────────────────────────────────────────────────────
// The production `DiagnosticResult` takes FOURTEEN constructor arguments; the deleted body wrote
// them as named arguments and this one writes them positionally, in the same order.

func QueryGoldenDiagnostic(symbolName: string, line: int, snippet: string): object?[] {
    args := new object?[](14)
    SetQueryObject(args, 0, "NL301")
    SetQueryObject(args, 1, "error")
    SetQueryObject(args, 2, "Undefined variable '" + symbolName + "'")
    SetQueryObject(args, 3, "sample-api/AuthController.nl")
    SetQueryInt(args, 4, line)
    SetQueryInt(args, 5, 17)
    SetQueryInt(args, 6, 11)
    SetQueryObject(args, 7, snippet)
    SetQueryObject(args, 8, "The symbol " + symbolName + " is not in scope.")
    SetQueryObject(args, 9, "Add the import or correct the declaration name.")
    SetQueryObject(args, 10, null)
    SetQueryObject(args, 11, null)
    SetQueryObject(args, 12, null)
    SetQueryObject(args, 13, null)
    return args
}


// ═══ SYMBOLS ══════════════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: Symbols HelloWorld FindsMainFunction — Main is a Function in the shipped hello-world project (was QueryIntegrationTests.Symbols_HelloWorld_FindsMainFunction)" {
    rows := QuerySymbolRows(QueryGetSymbols(QueryHelloWorld(), null, null))

    assert RowsHavePrefix(rows, "Main|Function|")
}

test "020 s39 query integration: Symbols HelloWorld MainFunctionHasVoidReturnType — the TypeName of Main is void (was QueryIntegrationTests.Symbols_HelloWorld_MainFunctionHasVoidReturnType)" {
    symbols := QueryGetSymbols(QueryHelloWorld(), null, null)
    main := QuerySymbolNamed(symbols, "Main")
    if main == null {
        throw new InvalidOperationException("The production symbol query did not answer Main.")
    }

    assert QueryText(main, "TypeName") == "void"
}

test "020 s39 query integration: Symbols ClassesAndRecords FindsAllTypeKinds — Point and Vector2D are Records (was QueryIntegrationTests.Symbols_ClassesAndRecords_FindsAllTypeKinds)" {
    rows := QuerySymbolRows(QueryGetSymbols(QueryClassesAndRecords(), null, null))

    assert RowsHavePrefix(rows, "Point|Record|")
    assert RowsHavePrefix(rows, "Vector2D|Record|")
}

test "020 s39 query integration: Symbols ClassesAndRecords RecordHasMembers — Vector2D carries Normalize and Dot (was QueryIntegrationTests.Symbols_ClassesAndRecords_RecordHasMembers)" {
    symbols := QueryGetSymbols(QueryClassesAndRecords(), null, null)
    vector := QuerySymbolNamedOfKind(symbols, "Vector2D", "Record")
    if vector == null {
        throw new InvalidOperationException("The production symbol query did not answer the Vector2D record.")
    }

    assert QueryHasMembers(vector)

    members := QueryMemberRows(vector)
    assert RowsHaveExact(members, "Normalize|Function")
    assert RowsHaveExact(members, "Dot|Function")
}

test "020 s39 query integration: Symbols MultiFile FindsAcrossFiles — Person, PersonService, Main and Status come back from three files (was QueryIntegrationTests.Symbols_MultiFile_FindsAcrossFiles)" {
    rows := QuerySymbolRows(QueryGetSymbols(QueryMultiFile(), null, null))

    assert RowsHavePrefix(rows, "Person|Record|")
    assert RowsHavePrefix(rows, "PersonService|Class|")
    assert RowsHavePrefix(rows, "Main|Function|")
    assert RowsHavePrefix(rows, "Status|Enum|")
}

test "020 s39 query integration: Symbols MultiFile PersonServiceHasMembers — AddPerson and GetPeople hang off the class (was QueryIntegrationTests.Symbols_MultiFile_PersonServiceHasMembers)" {
    symbols := QueryGetSymbols(QueryMultiFile(), null, null)
    service := QuerySymbolNamedOfKind(symbols, "PersonService", "Class")
    if service == null {
        throw new InvalidOperationException("The production symbol query did not answer the PersonService class.")
    }

    assert QueryHasMembers(service)

    members := QueryMemberRows(service)
    assert RowsHaveExact(members, "AddPerson|Function")
    assert RowsHaveExact(members, "GetPeople|Function")
}

test "020 s39 query integration: Symbols FilterByFile OnlyReturnsMatchingFile — Person.nl answers Person and Status and NOT Main or PersonService (was QueryIntegrationTests.Symbols_FilterByFile_OnlyReturnsMatchingFile)" {
    rows := QuerySymbolRows(QueryGetSymbols(QueryMultiFile(), "Person.nl", null))

    assert RowsHavePrefix(rows, "Person|")
    assert RowsHavePrefix(rows, "Status|")
    assert !RowsHavePrefix(rows, "Main|")
    assert !RowsHavePrefix(rows, "PersonService|")
}

test "020 s39 query integration: Symbols FilterByKind OnlyReturnsMatchingKind — every row of a Function filter is a Function (was QueryIntegrationTests.Symbols_FilterByKind_OnlyReturnsMatchingKind)" {
    snapshot := QueryMultiFile()
    all := QueryGetSymbols(snapshot, null, null)
    functionKind := QuerySymbolKindValue(all, "Function")
    rows := QuerySymbolRows(QueryGetSymbols(snapshot, null, functionKind))

    assert rows.Count > 0
    assert RowsCountContaining(rows, "|Function|") == rows.Count
    assert RowsHavePrefix(rows, "Main|Function|")
}

test "020 s39 query integration: Symbols Unions FindsUnionDeclarations — Divide, AlwaysFails and Main in the unions example (was QueryIntegrationTests.Symbols_Unions_FindsUnionDeclarations)" {
    rows := QuerySymbolRows(QueryGetSymbols(QueryUnions(), null, null))

    assert RowsHavePrefix(rows, "Divide|Function|")
    assert RowsHavePrefix(rows, "AlwaysFails|Function|")
    assert RowsHavePrefix(rows, "Main|Function|")
}

test "020 s39 query integration: Symbols PublicSurface UsesGoStyleCasingAndInteropEscapes — casing decides export for types, enum members, union cases and free functions (was QueryIntegrationTests.Symbols_PublicSurface_UsesGoStyleCasingAndInteropEscapes)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, "name: QueryVisibility\nversion: 1.0.0\ntargetFramework: net10.0\noutputType: library\n")
    QueryWriteSource(
        projectRoot,
        "Api.nl",
        "public class copiedPublicSurface {\n    Visible: int\n}\n\nprivate class CopiedPrivateSurface {\n    Visible: int\n}\n\nclass ExportedSurface {\n    Visible: int\n    hidden: int\n}\n\nclass hiddenSurface {\n    Visible: int\n}\n\nenum Labels: string {\n    Good = \"good\",\n    bad = \"bad\"\n}\n\nunion Result {\n    Ok { Value: int }\n    err { message: string }\n}\n\nfunc Helper(): int {\n    return 1\n}\n\nfunc helper(): int {\n    return 2\n}\n")

    snapshot := QueryLoadProject(projectRoot)
    errorRows := QueryProjectErrorRows(snapshot)
    assert RowsCountPrefix(errorRows, "Error|") == 0

    symbols := QueryGetSymbols(snapshot, null, null)
    names := QuerySymbolNames(symbols)

    assert !RowsHaveExact(names, "CopiedPrivateSurface")
    assert RowsHaveExact(names, "ExportedSurface")
    assert RowsHaveExact(names, "Labels")
    assert RowsHaveExact(names, "Result")
    assert RowsHaveExact(names, "Helper")
    assert RowsHaveExact(names, "copiedPublicSurface")
    assert !RowsHaveExact(names, "hiddenSurface")
    assert !RowsHaveExact(names, "helper")

    exported := QuerySymbolNamed(symbols, "ExportedSurface")
    if exported == null {
        throw new InvalidOperationException("The production symbol query did not answer ExportedSurface.")
    }
    assert RowsCountExact(names, "ExportedSurface") == 1
    exportedMembers := QueryMemberRows(exported)
    assert RowsHavePrefix(exportedMembers, "Visible|")
    assert !RowsHavePrefix(exportedMembers, "hidden|")

    labels := QuerySymbolNamed(symbols, "Labels")
    if labels == null {
        throw new InvalidOperationException("The production symbol query did not answer Labels.")
    }
    assert RowsCountExact(names, "Labels") == 1
    labelMembers := QueryMemberRows(labels)
    assert RowsHavePrefix(labelMembers, "Good|")
    assert RowsHavePrefix(labelMembers, "bad|")

    result := QuerySymbolNamed(symbols, "Result")
    if result == null {
        throw new InvalidOperationException("The production symbol query did not answer Result.")
    }
    assert RowsCountExact(names, "Result") == 1
    resultMembers := QueryMemberRows(result)
    assert RowsHavePrefix(resultMembers, "Ok|")
    assert !RowsHavePrefix(resultMembers, "err|")

    QueryDeleteTemp(projectRoot)
}


// ═══ OUTLINE ══════════════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: Outline HelloWorld HasMainFunction — the file outline carries Main as a Function (was QueryIntegrationTests.Outline_HelloWorld_HasMainFunction)" {
    rows := QueryOutlineRows(QueryGetOutline(QueryHelloWorld(), "Program.nl"))

    assert RowsHavePrefix(rows, "Main|Function|")
}

test "020 s39 query integration: Outline MultiFile PersonFileHasRecordAndEnum — Person is a Record and Status an Enum in one file (was QueryIntegrationTests.Outline_MultiFile_PersonFileHasRecordAndEnum)" {
    rows := QueryOutlineRows(QueryGetOutline(QueryMultiFile(), "Person.nl"))

    assert RowsHavePrefix(rows, "Person|Record|")
    assert RowsHavePrefix(rows, "Status|Enum|")
}

test "020 s39 query integration: Outline SingleFileFastPath MatchesProjectOutline — the no-project path finds Main too (was QueryIntegrationTests.Outline_SingleFileFastPath_MatchesProjectOutline)" {
    rows := QueryOutlineRows(QueryGetOutlineSingleFile(QueryHelloWorldProgram()))

    assert RowsHavePrefix(rows, "Main|")
}


// ═══ DIAGNOSTICS ══════════════════════════════════════════════════════════════════════════════

// THE WHOLE CENSUS, NOT A FILTER OVER IT. The deleted body asserted `Empty(where Severity ==
// "error")`, and the perturbation matrix could not move it: the shipped project answers ZERO
// diagnostics of ANY severity, so the severity filter never ran. The successor pins the census.
test "020 s39 query integration: Diagnostics HelloWorld CompileCleanlyNoErrors — the whole census is EMPTY, not merely free of errors (was QueryIntegrationTests.Diagnostics_HelloWorld_CompileCleanlyNoErrors)" {
    rows := QueryDiagnosticRows(QueryGetDiagnostics(QueryHelloWorld(), null))

    assert QueryJoin(rows) == ""
    assert RowsCountContaining(rows, "|error|") == 0
}

test "020 s39 query integration: Diagnostics MultiFile CompileCleanlyNoErrors — the whole census is EMPTY, not merely free of errors (was QueryIntegrationTests.Diagnostics_MultiFile_CompileCleanlyNoErrors)" {
    rows := QueryDiagnosticRows(QueryGetDiagnostics(QueryMultiFile(), null))

    assert QueryJoin(rows) == ""
    assert RowsCountContaining(rows, "|error|") == 0
}

// A FINDING, AND THE RUNTIME RUN THAT REPLACES IT. `Diagnostics_HaveCorrectCodeFormat` asserted
// `All(all, d => StartsWith("NL", d.Code))` over `GetDiagnostics(HelloWorld)` — and that answer is
// EMPTY, measured, so `Assert.All` ranged over nothing and the claim was STRUCTURALLY VACUOUS: it
// never inspected a single diagnostic code. Both halves are stated here instead: the shipped
// project's census is empty, AND a project that really does produce diagnostics has every code
// prefixed `NL`, over a nonempty census.
test "020 s39 query integration: Diagnostics HaveCorrectCodeFormat — the shipped project answers NOTHING, so the prefix claim is made over a census that is not empty (was QueryIntegrationTests.Diagnostics_HaveCorrectCodeFormat)" {
    shippedRows := QueryDiagnosticRows(QueryGetDiagnostics(QueryHelloWorld(), null))
    assert shippedRows.Count == 0

    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteSource(projectRoot, "Program.nl", "func Main() {\n    let first := Missing.Create()\n    let second := AlsoMissing.Create()\n}\n")

    rows := QueryDiagnosticRows(QueryGetDiagnostics(QueryLoadProject(projectRoot), null))
    assert rows.Count > 0
    assert RowsCountPrefix(rows, "NL") == rows.Count

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: DiagnosticClustersToJson EmitsStableIdentifierResolutionClusterGoldenShape — the shipped golden document byte for byte, and the envelope re-parsed (was QueryIntegrationTests.DiagnosticClustersToJson_EmitsStableIdentifierResolutionClusterGoldenShape)" {
    json := QueryGoldenClusterJson()
    goldenPath := Path.Combine(QueryRepositoryRoot(), "docs", "examples", "diagnostic-clusters.sample.json")
    goldenText := File.ReadAllText(goldenPath)
    expected := goldenText.Replace("\r\n", "\n")
    actual := json.Replace("\r\n", "\n")
    assert expected == actual

    document := JsonDocument.Parse(json)
    root := document.RootElement
    clusters := root.GetProperty("clusters")
    assert clusters.GetArrayLength() == 1

    cluster := QueryJsonAt(clusters, 0)
    assert root.GetProperty("schemaVersion").GetInt32() == 1
    assert root.GetProperty("command").GetString() == "diagnostics.clusters"
    assert !root.GetProperty("ok").GetBoolean()
    assert root.GetProperty("projectRoot").GetString() == "/redacted/sample-project"
    assert cluster.GetProperty("category").GetString() == "identifier-resolution"
    assert cluster.GetProperty("recipe").GetString() == "symbols:missing-import-or-qualification"
    assert cluster.GetProperty("risk").GetString() == "medium"
    assert cluster.GetProperty("nextCommand").GetString() == "nlc query inspect --file sample-api/AuthController.nl --pos 42:17"
    files := cluster.GetProperty("files")
    assert files.GetArrayLength() == 1
    firstFile := QueryJsonAt(files, 0)
    assert firstFile.GetString() == "sample-api/AuthController.nl"
    related := cluster.GetProperty("relatedDiagnostics")
    assert related.GetArrayLength() == 2
    firstRelated := QueryJsonAt(related, 0)
    secondRelated := QueryJsonAt(related, 1)
    assert firstRelated.GetProperty("code").GetString() == "NL301"
    assert secondRelated.GetProperty("code").GetString() == "NL301"

    document.Dispose()
}


// ═══ COMPLETIONS ══════════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: Completions IdentifierContext ExcludesKeywordsByDefault — the LLM-facing default drops keywords and primitive types (was QueryIntegrationTests.Completions_IdentifierContext_ExcludesKeywordsByDefault)" {
    answer := QueryGetCompletions(QueryHelloWorld(), "Program.nl", 3, 4, false)

    assert !QueryCompletionHasGroup(answer, "keywords")
    assert !QueryCompletionHasGroup(answer, "primitiveTypes")
}

test "020 s39 query integration: Completions IdentifierContext IncludesKeywordsWhenRequested — includeKeywords=true brings if and return back (was QueryIntegrationTests.Completions_IdentifierContext_IncludesKeywordsWhenRequested)" {
    answer := QueryGetCompletions(QueryHelloWorld(), "Program.nl", 3, 4, true)

    assert QueryCompletionHasGroup(answer, "keywords")

    keywords := QueryCompletionNames(answer, "keywords")
    assert RowsHaveExact(keywords, "if")
    assert RowsHaveExact(keywords, "return")
}


// ═══ JSON ENVELOPES ═══════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: Json Symbols ParsesAsValidJsonWithEnvelope — schemaVersion 1, command symbols, a nonempty results array (was QueryIntegrationTests.Json_Symbols_ParsesAsValidJsonWithEnvelope)" {
    snapshot := QueryHelloWorld()
    args := new object?[](3)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, null)
    SetQueryObject(args, 2, null)
    symbols := QueryRequire(QueryInvoke("GetSymbols", args), "GetSymbols")
    json := QueryFormatterJson("SymbolsToJson", symbols, QueryText(snapshot, "ProjectRoot"))

    document := JsonDocument.Parse(json)
    root := document.RootElement
    assert root.GetProperty("schemaVersion").GetInt32() == 1
    assert root.GetProperty("command").GetString() == "symbols"
    assert root.GetProperty("results").GetArrayLength() >= 1
    document.Dispose()
}

test "020 s39 query integration: Json Diagnostics HasSummaryWithCounts — errors, warnings and info are JSON numbers (was QueryIntegrationTests.Json_Diagnostics_HasSummaryWithCounts)" {
    snapshot := QueryHelloWorld()
    args := new object?[](2)
    SetQueryObject(args, 0, snapshot)
    SetQueryObject(args, 1, null)
    diagnostics := QueryRequire(QueryInvoke("GetDiagnostics", args), "GetDiagnostics")
    json := QueryFormatterJson("DiagnosticsToJson", diagnostics, QueryText(snapshot, "ProjectRoot"))

    document := JsonDocument.Parse(json)
    summary := document.RootElement.GetProperty("summary")
    assert summary.GetProperty("errors").ValueKind == JsonValueKind.Number
    assert summary.GetProperty("warnings").ValueKind == JsonValueKind.Number
    assert summary.GetProperty("info").ValueKind == JsonValueKind.Number
    document.Dispose()
}

test "020 s39 query integration: Nullability DiagnosticsAndTypeQueryExposeMaybeNullState — NL905 with a ?. suggestion, and the type query says maybeNull (was QueryIntegrationTests.Nullability_DiagnosticsAndTypeQueryExposeMaybeNullState)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteSource(projectRoot, "Program.nl", "func Main() {\n    x: string? = \"hello\"\n    len := x.Length\n}\n")
    snapshot := QueryLoadProject(projectRoot)

    rows := QueryDiagnosticRows(QueryGetDiagnostics(snapshot, "Program.nl"))
    assert RowsCountContaining(rows, "?.") > 0
    assert RowsCountPrefix(rows, "NL905|error|") > 0

    filePath := Path.Combine(projectRoot, "Program.nl")
    line := FindLineInFile(filePath, "x.Length")
    column := FindColumnInFile(filePath, line, "x")

    typeResult := QueryGetTypeAtPosition(snapshot, "Program.nl", line, column)
    if typeResult == null {
        throw new InvalidOperationException("The production type query answered nothing.")
    }
    assert QueryText(typeResult, "Nullability") == "maybeNull"

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: Json Outline HasOutlineArray — the outline envelope carries a nonempty array (was QueryIntegrationTests.Json_Outline_HasOutlineArray)" {
    json := QueryOutlineJson(QueryGetOutline(QueryHelloWorld(), "Program.nl"))

    document := JsonDocument.Parse(json)
    assert document.RootElement.GetProperty("outline").GetArrayLength() > 0
    document.Dispose()
}


// ═══ UNHAPPY PATHS ════════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: Outline NonexistentFile ReturnsEmpty — a missing file outlines to nothing (was QueryIntegrationTests.Outline_NonexistentFile_ReturnsEmpty)" {
    rows := QueryOutlineRows(QueryGetOutline(QueryHelloWorld(), "DoesNotExist.nl"))

    assert rows.Count == 0
}

test "020 s39 query integration: Definition AtBogusPosition ReturnsNull — line 999 column 999 defines nothing (was QueryIntegrationTests.Definition_AtBogusPosition_ReturnsNull)" {
    assert QueryIsNothing(QueryFindDefinition(QueryHelloWorld(), "Program.nl", 999, 999))
}

test "020 s39 query integration: Type AtBogusPosition ReturnsNull — line 999 column 999 types to nothing (was QueryIntegrationTests.Type_AtBogusPosition_ReturnsNull)" {
    assert QueryIsNothing(QueryGetTypeAtPosition(QueryHelloWorld(), "Program.nl", 999, 999))
}

test "020 s39 query integration: Symbols NonexistentFile ReturnsEmpty — a missing file has no symbols (was QueryIntegrationTests.Symbols_NonexistentFile_ReturnsEmpty)" {
    symbols := QueryGetSymbols(QueryHelloWorld(), "DoesNotExist.nl", null)

    assert symbols.Count == 0
}

test "020 s39 query integration: Diagnostics NonexistentFile ReturnsEmpty — a missing file has no diagnostics (was QueryIntegrationTests.Diagnostics_NonexistentFile_ReturnsEmpty)" {
    diagnostics := QueryGetDiagnostics(QueryHelloWorld(), "DoesNotExist.nl")

    assert diagnostics.Count == 0
}


// ═══ BINDING MAP ══════════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: BindingMap HelloWorld IsPopulated — the snapshot carries a binding map with bindings in it (was QueryIntegrationTests.BindingMap_HelloWorld_IsPopulated)" {
    bindings := QueryBindings(QueryHelloWorld())

    assert QueryInt(bindings, "BindingCount") > 0
}

test "020 s39 query integration: BindingMap MultiFile HasCrossFileBindings — the multi-file snapshot carries bindings too (was QueryIntegrationTests.BindingMap_MultiFile_HasCrossFileBindings)" {
    bindings := QueryBindings(QueryMultiFile())

    assert QueryInt(bindings, "BindingCount") > 0
}


// ═══ POSITIVE SEMANTIC NAVIGATION ═════════════════════════════════════════════════════════════

test "020 s39 query integration: References FindsPersonUsagesAcrossFiles — the declaration plus cross-file usages, from binding data and not text (was QueryIntegrationTests.References_FindsPersonUsagesAcrossFiles)" {
    references := QueryFindReferences(QueryMultiFile(), "Models/Person.nl", 5, 8)
    rows := QueryReferenceRows(references)

    assert references.Count >= 3
    assert QueryDefinitionReferenceCount(references) >= 1
    assert RowsCountContaining(rows, "Program.nl") + RowsCountContaining(rows, "PersonService.nl") > 0
}

test "020 s39 query integration: References DuplicateCrossFileMemberNames StayBoundToImportedType — Foo.Widget usages only, never the same-spelled Bar.Widget (was QueryIntegrationTests.References_DuplicateCrossFileMemberNames_StayBoundToImportedType)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteDuplicateWidgets(projectRoot, "Value: string", "Value: int")
    QueryWriteSource(projectRoot, "Foo/UseWidget.nl", "namespace QueryTemp.Foo\n\nfunc Read(widget: Widget): string {\n    return widget.Value\n}\n")
    QueryWriteSource(projectRoot, "Bar/UseWidget.nl", "namespace QueryTemp.Bar\n\nfunc Read(widget: Widget): int {\n    return widget.Value\n}\n")
    QueryWriteEmptyMain(projectRoot)

    rows := QueryReferenceRows(QueryFindReferences(QueryLoadProject(projectRoot), "Foo/Widget.nl", 4, 5))

    assert RowsCountContaining(rows, "Foo/Widget.nl|4|") > 0
    assert RowsCountBoth(rows, "Foo/UseWidget.nl|4|", "|False|") > 0
    assert RowsCountContaining(rows, "Foo/Widget.nl|4|5|True") > 0
    assert RowsCountContaining(rows, "Bar/Widget.nl") == 0
    assert RowsCountContaining(rows, "Bar/UseWidget.nl") == 0

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: References SourceContexts AreTrimmedThroughProductionQuerySurface — leading spaces and a leading tab are trimmed off both contexts (was QueryIntegrationTests.References_SourceContexts_AreTrimmedThroughProductionQuerySurface)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteSource(
        projectRoot,
        "Program.nl",
        "namespace QueryTemp\n\n   record Widget {\n    Value: int\n}\n\n\t  func Read(widget: Widget): int {\n    return widget.Value\n}\n")
    snapshot := QueryLoadProject(projectRoot)

    filePath := Path.Combine(projectRoot, "Program.nl")
    declarationLine := FindLineInFile(filePath, "record Widget")
    declarationColumn := FindColumnInFile(filePath, declarationLine, "Widget")

    rows := QueryReferenceRows(QueryFindReferences(snapshot, "Program.nl", declarationLine, declarationColumn))

    assert RowsEndingWith(rows, "|True|record Widget {") > 0
    assert RowsEndingWith(rows, "|False|func Read(widget: Widget): int {") > 0

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: TypeUseNavigation DuplicateTypeNames UsesSemanticBindingForCompositeTypes — definition, type, hover and references all bind the type ARGUMENT to Foo.Widget (was QueryIntegrationTests.TypeUseNavigation_DuplicateTypeNames_UsesSemanticBindingForCompositeTypes)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteDuplicateWidgets(projectRoot, "Value: string", "Value: int")
    QueryWriteSource(
        projectRoot,
        "Foo/UseWidget.nl",
        "namespace QueryTemp.Foo\nimport System.Collections.Generic\n\nfunc Read(items: List<Widget>, maybe: Widget?, many: Widget[], mapper: Func<Widget, string>): string {\n    return \"\"\n}\n")
    QueryWriteSource(
        projectRoot,
        "Bar/UseWidget.nl",
        "namespace QueryTemp.Bar\nimport System.Collections.Generic\n\nfunc Read(items: List<Widget>): int {\n    return 1\n}\n")
    QueryWriteEmptyMain(projectRoot)
    snapshot := QueryLoadProject(projectRoot)

    useWidgetPath := Path.Combine(projectRoot, "Foo", "UseWidget.nl")
    typeArgColumn := FindColumnInFile(useWidgetPath, 4, "Widget")

    definition := QueryFindDefinition(snapshot, "Foo/UseWidget.nl", 4, typeArgColumn)
    if definition == null {
        throw new InvalidOperationException("The production definition query answered nothing.")
    }
    assert QueryText(definition, "Name") == "Widget"
    assert QueryText(definition, "Kind") == "record"
    definitionFile := QueryText(definition, "File")
    assert definitionFile.EndsWith("Foo/Widget.nl", StringComparison.Ordinal)

    typeResult := QueryGetTypeAtPosition(snapshot, "Foo/UseWidget.nl", 4, typeArgColumn)
    if typeResult == null {
        throw new InvalidOperationException("The production type query answered nothing.")
    }
    assert QueryText(typeResult, "Name") == "Widget"
    assert QueryText(typeResult, "Kind") == "record"
    typeDefinition := QueryChild(typeResult, "Definition")
    typeDefinitionFile := QueryText(typeDefinition, "File")
    assert typeDefinitionFile.EndsWith("Foo/Widget.nl", StringComparison.Ordinal)

    hover := QueryGetHoverInfo(snapshot, "Foo/UseWidget.nl", 4, typeArgColumn)
    if hover == null {
        throw new InvalidOperationException("The production hover query answered nothing.")
    }
    assert QueryText(hover, "Kind") == "record"
    hoverSignature := QueryText(hover, "Signature")
    assert hoverSignature.Contains("Widget", StringComparison.Ordinal)

    declarationLine := FindLineInFile(Path.Combine(projectRoot, "Foo", "Widget.nl"), "record Widget")
    rows := QueryReferenceRows(QueryFindReferences(snapshot, "Foo/Widget.nl", declarationLine, 8))

    assert RowsCountContaining(rows, "Foo/Widget.nl|") > 0
    assert RowsCountContaining(rows, "Foo/Widget.nl|" + declarationLine.ToString() + "|8|True") > 0
    assert RowsCountBoth(rows, "Foo/UseWidget.nl|4|", "|False|") > 0
    assert RowsCountContaining(rows, "Bar/Widget.nl") == 0
    assert RowsCountContaining(rows, "Bar/UseWidget.nl") == 0

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: References CommentWord DoesNotUseTextFallback — a word that only occurs in a comment has no references at all (was QueryIntegrationTests.References_CommentWord_DoesNotUseTextFallback)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteSource(
        projectRoot,
        "Program.nl",
        "namespace QueryTemp\n\nfunc Main(): void {\n    let value := 1\n    // value in a comment is not a semantic reference target\n    print(value)\n}\n")

    references := QueryFindReferences(QueryLoadProject(projectRoot), "Program.nl", 5, 8)
    assert references.Count == 0

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: Completions DuplicateCrossFileTypeNames UseReceiverDeclarationNotNameFallback — the receiver's own declaration decides the member list (was QueryIntegrationTests.Completions_DuplicateCrossFileTypeNames_UseReceiverDeclarationNotNameFallback)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteDuplicateWidgets(projectRoot, "FooOnly: string", "BarOnly: int")
    QueryWriteSource(projectRoot, "Foo/UseWidget.nl", "namespace QueryTemp.Foo\n\nfunc Read(widget: Widget): string {\n    return widget.\n}\n")
    QueryWriteEmptyMain(projectRoot)

    answer := QueryGetCompletions(QueryLoadProject(projectRoot), "Foo/UseWidget.nl", 4, 18, false)

    assert QueryCompletionHasGroup(answer, "properties")
    properties := QueryCompletionNames(answer, "properties")
    assert RowsHaveExact(properties, "FooOnly")
    assert !RowsHaveExact(properties, "BarOnly")

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: Completions ChainedMemberAccess DuplicateCrossFileTypeNames UseReturnDeclaration — the RETURN type's declaration decides a chained member list (was QueryIntegrationTests.Completions_ChainedMemberAccess_DuplicateCrossFileTypeNames_UseReturnDeclaration)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteDuplicateWidgets(projectRoot, "FooOnly: string", "BarOnly: int")
    QueryWriteSource(
        projectRoot,
        "Foo/UseWidget.nl",
        "namespace QueryTemp.Foo\n\nclass Factory {\n    func Create(): Widget {\n        return new Widget { FooOnly: \"ok\" }\n    }\n}\n\nfunc Read(factory: Factory): string {\n    return factory.Create().\n}\n")
    QueryWriteEmptyMain(projectRoot)
    snapshot := QueryLoadProject(projectRoot)

    // The deleted body walked `snapshot.CompilationUnits.Keys` to recover the absolute path of the
    // file it had just written; the path is computed here instead, which is the same file.
    useWidgetPath := Path.Combine(projectRoot, "Foo", "UseWidget.nl")
    line := FindLineInFile(useWidgetPath, "factory.Create().")
    sourceLines := File.ReadAllLines(useWidgetPath)
    sourceLine := sourceLines[line - 1]
    col := sourceLine.Length

    answer := QueryGetCompletions(snapshot, "Foo/UseWidget.nl", line, col, false)

    assert QueryCompletionHasGroup(answer, "properties")
    properties := QueryCompletionNames(answer, "properties")
    assert RowsHaveExact(properties, "FooOnly")
    assert !RowsHaveExact(properties, "BarOnly")

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: References HelloWorld FindsMainFunctionDeclaration — the declaration of Main is a reference to itself (was QueryIntegrationTests.References_HelloWorld_FindsMainFunctionDeclaration)" {
    programPath := QueryHelloWorldProgram()
    line := FindLineInFile(programPath, "func Main()")
    column := FindColumnInFile(programPath, line, "Main")

    references := QueryFindReferences(QueryHelloWorld(), "Program.nl", line, column)

    assert references.Count > 0
}

test "020 s39 query integration: BindingMap MultiFile PersonDeclarationFound — the analyzer's first pass recorded declarations (was QueryIntegrationTests.BindingMap_MultiFile_PersonDeclarationFound)" {
    bindings := QueryBindings(QueryMultiFile())
    declarations := QueryChildList(bindings, "AllDeclarations")

    assert declarations.Count > 0
}

test "020 s39 query integration: BindingMap MultiFile ImportedMemberUsage ResolvesToSourceDeclaration — GetPeople binds through the receiver type to PersonService.nl line 18 (was QueryIntegrationTests.BindingMap_MultiFile_ImportedMemberUsage_ResolvesToSourceDeclaration)" {
    programPath := QueryMultiFileProgram()
    memberColumn := FindColumnInFile(programPath, 26, "GetPeople")

    declaration := QueryBindingAt(QueryMultiFile(), programPath, 26, memberColumn)
    if declaration == null {
        throw new InvalidOperationException("The production binding map answered no declaration.")
    }

    assert QueryText(declaration, "Name") == "GetPeople"
    assert QueryText(declaration, "Kind") == "function"
    declarationFile := QueryText(declaration, "File")
    assert declarationFile.EndsWith("PersonService.nl", StringComparison.Ordinal)
    assert QueryInt(declaration, "Line") == 18
}


// ═══ TYPE QUERIES OVER THE ISSUE-TRACKER FIXTURE ══════════════════════════════════════════════

test "020 s39 query integration: Type IssueTracker LocalVariableFromNewExpression Resolves — service is an IssueService class (was QueryIntegrationTests.Type_IssueTracker_LocalVariableFromNewExpression_Resolves)" {
    result := QueryGetTypeAtPosition(QueryIssueTracker(), "Program.nl", 16, 5)
    if result == null {
        throw new InvalidOperationException("The production type query answered nothing.")
    }

    assert QueryText(result, "Name") == "service"
    assert QueryText(result, "ResolvedType") == "IssueService"
    assert QueryText(result, "Kind") == "class"
}

test "020 s39 query integration: Type IssueTracker ClassMethodDeclaration Resolves — the CreateIssue declaration types to its own name (was QueryIntegrationTests.Type_IssueTracker_ClassMethodDeclaration_Resolves)" {
    result := QueryGetTypeAtPosition(QueryIssueTracker(), "Service.nl", 22, 10)
    if result == null {
        throw new InvalidOperationException("The production type query answered nothing.")
    }

    assert QueryText(result, "Name") == "CreateIssue"
}

test "020 s39 query integration: Type IssueTracker LocalVariableFromImportedMethodCall Resolves — store is an IssueStore (was QueryIntegrationTests.Type_IssueTracker_LocalVariableFromImportedMethodCall_Resolves)" {
    // The deleted body walked `snapshot.SemanticModels` only to build a FAILURE MESSAGE; a message
    // is not a claim, so the walk is dropped and the two claims it decorated are kept whole.
    result := QueryGetTypeAtPosition(QueryIssueTracker(), "Program.nl", 15, 5)
    if result == null {
        throw new InvalidOperationException("The production type query answered nothing for store.")
    }

    assert QueryText(result, "Name") == "store"
    assert QueryText(result, "ResolvedType") == "IssueStore"
}

test "020 s39 query integration: Type IssueTracker RecordPropertyUse Resolves — the store field of IssueService is an IssueStore (was QueryIntegrationTests.Type_IssueTracker_RecordPropertyUse_Resolves)" {
    result := QueryGetTypeAtPosition(QueryIssueTracker(), "Service.nl", 11, 5)
    if result == null {
        throw new InvalidOperationException("The production type query answered nothing.")
    }

    assert QueryText(result, "Name") == "store"
    assert QueryText(result, "ResolvedType") == "IssueStore"
}

test "020 s39 query integration: Type QueryableLinqChain ReportsProjectedReturnType — a Where/Select chain over AsQueryable projects to IQueryable<string> (was QueryIntegrationTests.Type_QueryableLinqChain_ReportsProjectedReturnType)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteSource(
        projectRoot,
        "Program.nl",
        "import System.Linq\n\nfunc Main() {\n    source := [1, 2, 3]\n    query := source.AsQueryable()\n    filtered := query.Where(x => x > 1).Select(x => x.ToString())\n}\n")
    snapshot := QueryLoadProject(projectRoot)

    programPath := Path.Combine(projectRoot, "Program.nl")
    filteredLine := FindLineInFile(programPath, "filtered :=")
    filteredColumn := FindColumnInFile(programPath, filteredLine, "filtered")

    result := QueryGetTypeAtPosition(snapshot, "Program.nl", filteredLine, filteredColumn)
    if result == null {
        throw new InvalidOperationException("The production type query answered nothing.")
    }

    assert QueryText(result, "Name") == "filtered"
    assert QueryText(result, "ResolvedType") == "IQueryable<string>"

    QueryDeleteTemp(projectRoot)
}


// ═══ REFERENCES AND DEFINITIONS OVER THE ISSUE-TRACKER FIXTURE ════════════════════════════════

test "020 s39 query integration: References IssueTracker MethodDeclaration IsNotDuplicatedAsUsage — GetAll has references and EXACTLY ONE definition row (was QueryIntegrationTests.References_IssueTracker_MethodDeclaration_IsNotDuplicatedAsUsage)" {
    references := QueryFindReferences(QueryIssueTracker(), "Service.nl", 64, 10)

    assert references.Count >= 1
    assert QueryDefinitionReferenceCount(references) == 1
}

test "020 s39 query integration: Definition IssueTracker MethodUseSite Resolves — GetAll is a function at Service.nl line 64 (was QueryIntegrationTests.Definition_IssueTracker_MethodUseSite_Resolves)" {
    result := QueryFindDefinition(QueryIssueTracker(), "Service.nl", 64, 10)
    if result == null {
        throw new InvalidOperationException("The production definition query answered nothing.")
    }

    assert QueryText(result, "Name") == "GetAll"
    assert QueryText(result, "Kind") == "function"
    assert QueryText(result, "File") == "Service.nl"
    assert QueryInt(result, "Line") == 64
}

test "020 s39 query integration: Definition IssueTracker MethodUseSite ClosingParen SnapsToMember — CreateIssue is a function at Service.nl line 22 (was QueryIntegrationTests.Definition_IssueTracker_MethodUseSite_ClosingParen_SnapsToMember)" {
    result := QueryFindDefinition(QueryIssueTracker(), "Service.nl", 22, 10)
    if result == null {
        throw new InvalidOperationException("The production definition query answered nothing.")
    }

    assert QueryText(result, "Name") == "CreateIssue"
    assert QueryText(result, "Kind") == "function"
    assert QueryText(result, "File") == "Service.nl"
    assert QueryInt(result, "Line") == 22
}

test "020 s39 query integration: Definition MultiFile ImportedMemberUseSite Resolves — GetPeople resolves to PersonService.nl line 18, not a same-spelled call-site guess (was QueryIntegrationTests.Definition_MultiFile_ImportedMemberUseSite_Resolves)" {
    programPath := QueryMultiFileProgram()
    memberColumn := FindColumnInFile(programPath, 26, "GetPeople")

    result := QueryFindDefinition(QueryMultiFile(), "Program.nl", 26, memberColumn)
    if result == null {
        throw new InvalidOperationException("The production definition query answered nothing.")
    }

    assert QueryText(result, "Name") == "GetPeople"
    assert QueryText(result, "Kind") == "function"
    resultFile := QueryText(result, "File")
    assert resultFile.EndsWith("PersonService.nl", StringComparison.Ordinal)
    assert QueryInt(result, "Line") == 18
}

test "020 s39 query integration: Definition IssueTracker RecordDeclaration Resolves — Issue is a record at Models.nl line 35 (was QueryIntegrationTests.Definition_IssueTracker_RecordDeclaration_Resolves)" {
    result := QueryFindDefinition(QueryIssueTracker(), "Models.nl", 35, 8)
    if result == null {
        throw new InvalidOperationException("The production definition query answered nothing.")
    }

    assert QueryText(result, "Name") == "Issue"
    assert QueryText(result, "Kind") == "record"
    assert QueryText(result, "File") == "Models.nl"
    assert QueryInt(result, "Line") == 35
}

test "020 s39 query integration: References IssueTracker LocalVariableUseSite FindsUsages — the IssueService class has usages and one definition (was QueryIntegrationTests.References_IssueTracker_LocalVariableUseSite_FindsUsages)" {
    references := QueryFindReferences(QueryIssueTracker(), "Service.nl", 10, 7)

    assert references.Count >= 1
    assert QueryDefinitionReferenceCount(references) == 1
}

test "020 s39 query integration: References IssueTracker EnumDeclaration FindsUsages — the Priority enum has usages (was QueryIntegrationTests.References_IssueTracker_EnumDeclaration_FindsUsages)" {
    references := QueryFindReferences(QueryIssueTracker(), "Models.nl", 10, 6)

    assert references.Count >= 1
}


// ═══ HOVER ════════════════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: HoverCommand ReturnsSignatureAndDoc — the Hi declaration hovers to a function signature carrying its return type and the file's doc comment (was QueryIntegrationTests.HoverCommand_ReturnsSignatureAndDoc)" {
    programFile := QueryHelloWorldProgram()
    hiLine := FindLineInFile(programFile, "func Hi()")
    hiColumn := FindColumnInFile(programFile, hiLine, "Hi")

    result := QueryGetHoverInfo(QueryHelloWorld(), "Program.nl", hiLine, hiColumn)
    if result == null {
        throw new InvalidOperationException("The production hover query answered nothing.")
    }

    assert QueryText(result, "Kind") == "function"
    signature := QueryText(result, "Signature")
    documentation := QueryText(result, "Documentation")
    assert signature.Contains("Hi", StringComparison.Ordinal)
    assert signature.Contains("int", StringComparison.Ordinal)
    assert documentation.Contains("A simple hello-world program", StringComparison.Ordinal)
}

test "020 s39 query integration: HoverCommand AtCallSite ReturnsHoverInfo — the CALL site of Hi hovers to the same function (was QueryIntegrationTests.HoverCommand_AtCallSite_ReturnsHoverInfo)" {
    programFile := QueryHelloWorldProgram()
    hiLine := FindLineInFile(programFile, "i := Hi()")
    hiColumn := FindColumnInFile(programFile, hiLine, "Hi")

    result := QueryGetHoverInfo(QueryHelloWorld(), "Program.nl", hiLine, hiColumn)
    if result == null {
        throw new InvalidOperationException("The production hover query answered nothing.")
    }

    assert QueryText(result, "Kind") == "function"
    signature := QueryText(result, "Signature")
    assert signature.Contains("Hi", StringComparison.Ordinal)
}

test "020 s39 query integration: HoverAndType ChainedMemberAccess ResolveThroughReceiverExpression — .ToUpper().Length types to int on both surfaces (was QueryIntegrationTests.HoverAndType_ChainedMemberAccess_ResolveThroughReceiverExpression)" {
    projectRoot := QueryTempRoot()
    QueryWriteProjectYaml(projectRoot, QueryDefaultProjectYaml())
    QueryWriteSource(
        projectRoot,
        "Program.nl",
        "func Main(): void\n    let message = \"hello\"\n    let len = message.ToUpper().Length\n")
    snapshot := QueryLoadProject(projectRoot)

    // The deleted body walked `snapshot.CompilationUnits.Keys` to recover this path.
    programPath := Path.Combine(projectRoot, "Program.nl")
    line := FindLineInFile(programPath, "ToUpper().Length")
    col := FindColumnInFile(programPath, line, "Length")

    typeResult := QueryGetTypeAtPosition(snapshot, "Program.nl", line, col)
    if typeResult == null {
        throw new InvalidOperationException("The production type query answered nothing.")
    }
    assert QueryText(typeResult, "Name") == "Length"
    assert QueryText(typeResult, "ResolvedType") == "int"

    hover := QueryGetHoverInfo(snapshot, "Program.nl", line, col)
    if hover == null {
        throw new InvalidOperationException("The production hover query answered nothing.")
    }
    hoverSignature := QueryText(hover, "Signature")
    assert hoverSignature.Contains("Length", StringComparison.Ordinal)
    assert hoverSignature.Contains("int", StringComparison.Ordinal)

    QueryDeleteTemp(projectRoot)
}

test "020 s39 query integration: HoverCommand NoSymbol ReturnsNull — the first blank line of the program hovers to nothing (was QueryIntegrationTests.HoverCommand_NoSymbol_ReturnsNull)" {
    blankLine := FirstBlankLineInFile(QueryHelloWorldProgram())

    assert QueryIsNothing(QueryGetHoverInfo(QueryHelloWorld(), "Program.nl", blankLine, 1))
}


// ═══ CALL GRAPH ═══════════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: CallGraph FindsCallsFromMain — Main is the subject and Hi is one of its callees (was QueryIntegrationTests.CallGraph_FindsCallsFromMain)" {
    result := QueryGetCallGraph(QueryHelloWorld(), "Main")

    assert QueryText(result, "Function") == "Main"
    callees := QueryCallSiteRows(result, "Callees")
    assert RowsHavePrefix(callees, "Hi|")
}

test "020 s39 query integration: CallGraph FindsCallerOfHi — Hi is the subject and Main is one of its callers (was QueryIntegrationTests.CallGraph_FindsCallerOfHi)" {
    result := QueryGetCallGraph(QueryHelloWorld(), "Hi")

    assert QueryText(result, "Function") == "Hi"
    callers := QueryCallSiteRows(result, "Callers")
    assert RowsHavePrefix(callers, "Main|")
}

test "020 s39 query integration: CallGraph UnfilteredReturnsEdges — a null function filter answers every edge (was QueryIntegrationTests.CallGraph_UnfilteredReturnsEdges)" {
    result := QueryGetCallGraph(QueryHelloWorld(), null)

    callees := QueryCallSiteRows(result, "Callees")

    assert callees.Count > 0
}

test "020 s39 query integration: CallGraph UnknownFunction ReturnsEmptyLists — an unknown name answers itself with two empty lists and no truncation (was QueryIntegrationTests.CallGraph_UnknownFunction_ReturnsEmptyLists)" {
    result := QueryGetCallGraph(QueryHelloWorld(), "DoesNotExist")

    assert QueryText(result, "Function") == "DoesNotExist"
    callers := QueryCallSiteRows(result, "Callers")
    callees := QueryCallSiteRows(result, "Callees")
    assert callers.Count == 0
    assert callees.Count == 0
    assert QueryText(result, "Truncated") == "False"
}


// ═══ IMPLEMENTORS ═════════════════════════════════════════════════════════════════════════════

test "020 s39 query integration: Implementors FindsConcreteTypes — IShape is implemented by the class Circle (was QueryIntegrationTests.Implementors_FindsConcreteTypes)" {
    result := QueryGetImplementors(QueryClassesAndRecords(), "IShape")

    assert QueryText(result, "Interface") == "IShape"
    rows := QueryImplementorRows(result)
    assert RowsHavePrefix(rows, "Circle|class|")
}

test "020 s39 query integration: Implementors NoImplementors ReturnsEmptyList — an interface that does not exist answers itself with nothing (was QueryIntegrationTests.Implementors_NoImplementors_ReturnsEmptyList)" {
    result := QueryGetImplementors(QueryHelloWorld(), "INotARealInterface")

    assert QueryText(result, "Interface") == "INotARealInterface"
    rows := QueryImplementorRows(result)

    assert rows.Count == 0
}

test "020 s39 query integration: Implementors ICache FindsMemoryCache — ICache is implemented by MemoryCache (was QueryIntegrationTests.Implementors_ICache_FindsMemoryCache)" {
    result := QueryGetImplementors(QueryClassesAndRecords(), "ICache")

    rows := QueryImplementorRows(result)
    assert RowsHavePrefix(rows, "MemoryCache|")
}


// ═══ THE CLI'S SYMBOL FILTER ══════════════════════════════════════════════════════════════════

test "020 s39 query integration: Symbols WildcardFilter MatchesGlob — *ircle anchors to Circle and rejects Square (was QueryIntegrationTests.Symbols_WildcardFilter_MatchesGlob)" {
    names := QuerySymbolNames(QueryGetSymbols(QueryClassesAndRecords(), null, null))
    assert RowsHaveExact(names, "Circle")

    filtered := FilterNames(names, "*ircle")
    assert RowsHaveExact(filtered, "Circle")
    assert !RowsHaveExact(filtered, "Square")
}

test "020 s39 query integration: Symbols SubstringFilter MatchesSubstring — quare matches Square and not Circle (was QueryIntegrationTests.Symbols_SubstringFilter_MatchesSubstring)" {
    names := QuerySymbolNames(QueryGetSymbols(QueryClassesAndRecords(), null, null))

    filtered := FilterNames(names, "quare")
    assert RowsHaveExact(filtered, "Square")
    assert !RowsHaveExact(filtered, "Circle")
}
