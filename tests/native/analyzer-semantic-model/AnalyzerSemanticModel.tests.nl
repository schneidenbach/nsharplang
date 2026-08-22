namespace NSharpLang.AnalyzerSemanticModel.Tests

import System
import System.Collections


// WHAT ANALYSIS PUTS INTO THE SEMANTIC MODEL, IN N#.
//
// These replace the SEMANTIC-MODEL QUERY half of `tests/AnalyzerSemanticModelTests.cs`, which task
// 020 slice 26 deletes. That file's 51 `[Fact]`s split by SUBJECT — decoded from what each body
// CONSTRUCTS AND NAMES, never from its method name — into the 33 recorded here, which read the
// model through `LookupIdentifier`, `LookupIdentifierAtPosition`, `LookupTypeAtPosition`,
// `LookupTypeReferenceAtPosition`, `GetVisibleVariablesAtPosition`, `GetTypeMembers`, `Fields`,
// `Properties`, `Scopes` and `ExpressionTypes`, and 18 that read `SemanticModel.Types[…]` or only
// `result.Errors`. Those 18 stay in C# for slice 27; the ~700-line budget cannot hold both halves.
//
// THE NAME SPLIT WOULD HAVE MISPLACED EXACTLY ONE METHOD.
// `Analyzer_RecordTypes_RecordStructFlagInSemanticModel` is not named `NominalTypes_*` but reads
// `Types["Point"]` and asserts `RecordTypeInfo.IsStruct` — the same instrument as the 265-line
// nominal-source-facts monster and nothing like the query surface. It is in the other half.
//
// WHY THIS IS A NATIVE PROJECT AND NOT AN ESTATE CONTRACT, MEASURED RATHER THAN ASSUMED.
// `SemanticModel` IS N# in the estate, and the estate ALREADY owns its ALGEBRA:
// `SemanticModel.tests.nl` constructs a model directly, hand-records entries and pins the lookup
// ranking, the scope-depth rule and the inclusive bounds. What no estate contract can reach is the
// POPULATION — every claim below is over a model FILLED IN BY `Analyzer.Analyze`, and `Analyzer` is
// the C# class in `Compiler.dll`, which depends on the estate rather than the other way round. The
// route is REFLECTION through `object`, which slice 23 measured to be a constraint of the emitter's
// type resolution rather than a style choice.
//
// THE ENTRY POINT IS THE FOUR-ARGUMENT `Analyze(unit, "test.nl", null, source)`, not the
// single-argument overload slice 25's cluster used.
//
// SEVEN THINGS THE DELETED ASSERTIONS COULD NOT SEE ARE STATED HERE:
//   (a) THREE FIXTURES ARE BYTE-IDENTICAL DUPLICATES. 33 methods use 30 distinct sources: the
//       simplest function fixture is analysed twice (once for `x`, once for the scope count), the
//       two-field class twice (member table, then flat table) and the config class twice
//       (member table, then the properties/fields split). Each pair is pinned identically here, so
//       the duplication is visible instead of being spread across the file.
//   (b) FOUR "CLEAN" FIXTURES ARE NOT CLEAN. Two report `NL903:VisibilityConventionWarning` on a
//       leading-underscore field and one reports `NL316:ShadowedDeclaration`; `HasErrors` is TRUE
//       for all three, on fixtures whose methods never mentioned diagnostics. The undefined-function
//       fixture's single `NL412` is pinned whole as well.
//   (c) A FUNCTION DOES NOT LOOK UP AS ITSELF. The `Functions` table holds a `FunctionTypeInfo`,
//       whose `ToString()` is the CLR NAME `NSharpLang.Compiler.FunctionTypeInfo`; `LookupIdentifier`
//       routes it through `GetFunctionLookupType` and answers the RETURN type. Both are pinned.
//   (d) THE FLAT TABLES COLLIDE ACROSS SCOPES, AND THAT IS WHY THE POSITION TABLES EXIST. Two
//       functions with a parameter of the same name leave ONE row in `Variables`, the second; two
//       overloads leave one row in `Functions`; and shadowing leaves the INNER type flat. Every one
//       of those collisions is pinned beside the position-aware answer that resolves it.
//   (e) EVERY SCOPE'S END COLUMN IS `int.MaxValue`, AND ITS END LINE IS THE LAST NON-BRACE LINE.
//       No deleted assertion stated a scope bound at all; one asserted `Scopes.Count >= 2`, which a
//       model with twenty scopes would satisfy. Every count here is exact and every bound is named.
//   (f) THE ANALYZER OPENS TWELVE SCOPES FOR TWO LAMBDAS. The LINQ chain fixture opens FIFTEEN
//       scopes for one statement — eight at 6:30 and four at 6:49, all holding the same `x=int` —
//       because lambda bodies are re-entered during overload resolution and each entry opens a
//       scope that is never merged. Nothing measured this.
//   (h) `GetVisibleVariablesAtPosition` ANSWERS FUNCTIONS TOO. The deleted method asserted six
//       `ContainsKey`s over names it had declared as locals, so nothing said what else was in the
//       answer; the census names `test=NSharpLang.Compiler.FunctionTypeInfo` at both positions. The
//       perturbation panel found this: a control written against the expected variable-only census
//       was REFUSED because its anchor occurred zero times.
//   (g) THE TWO POSITION TABLES ARE DIFFERENT TABLES. `ExpressionTypes` and `TypeReferenceTypes`
//       are pinned separately for every fixture, so a row appearing in the wrong one is a visible
//       change; the inferred-array fixture pins the type-reference table EMPTY.
//
// EVERY PARSE CENSUS BELOW IS PINNED, AND ALL 33 ARE EMPTY. The deleted helper asserted only
// `Assert.NotNull(parseResult.CompilationUnit)` and discarded `.Errors`, so nothing separated an
// analyzer diagnostic from a recovery artefact carried in from the parse. Pinning the parse silence
// is what makes every row in every analysis census provably the ANALYZER's own.
//
// THE FIXTURES ARE THE DELETED ONES BYTE-FOR-BYTE, decoded by the C# compiler itself: each deleted
// method's fixture-construction prefix was pasted unmodified into a generated console program that
// printed the resulting string's sha256, its LENGTH and its N# spelling — and ran the deleted
// `FindColumn(source, line, needle, occurrence)` helper verbatim for the six cursor columns the
// deleted methods computed at runtime. Every contract asserts its fixture's own byte LENGTH against
// that count before it analyses anything.

func SetSmObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

// The estate models both fields and property accessors, and `FileParseAst.CompilationUnit` is a
// FIELD while `AnalysisResult.Errors` is a property, so every read tries both.
func SmMember(owner: object, memberName: string): object? {
    property := owner.GetType().GetProperty(memberName)
    if property != null {
        return property.GetValue(owner)
    }

    field := owner.GetType().GetField(memberName)
    if field != null {
        return field.GetValue(owner)
    }

    throw new InvalidOperationException("The production type exposed no '" + memberName + "' member.")
}

func SmRequiredMember(owner: object, memberName: string): object {
    value := SmMember(owner, memberName)
    if value == null {
        throw new InvalidOperationException("The production '" + memberName + "' member was null.")
    }

    return value
}

func SmText(owner: object, memberName: string): string {
    value := SmMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

func SmValueText(value: object?): string {
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

// Any collection's `Count`, read as a member rather than through an interface cast: a LOCAL typed
// `ICollection` or `IDictionary` is declined by the columnar emitter.
func SmCount(value: object?): int {
    if value == null {
        return -1
    }

    return Convert.ToInt32(SmMember(value, "Count"))
}

// ---- ordering -----------------------------------------------------------------------------------

// Ordinal comparison spelled out over UTF-16 units rather than delegated to
// `String.Compare(…, StringComparison.Ordinal)`, and sorting over a `string[]` rather than a
// `List<string>`. NEITHER IS A STYLE CHOICE, AND BOTH WERE MEASURED BY BISECTION:
//   * an insertion-sort loop whose condition calls `String.Compare` DECLINES AT EMIT in any file
//     that also casts with `as ICollection` or `as IDictionary`, and
//   * the same loop over a `List<string>` DECLINES when the file also carries a reflective
//     `GetProperty` / `GetField` member walk — while the identical loop over a `string[]` emits.
// Every table census below needs both the dictionary cast and the member walk, so the census rows
// are SORTED as arrays and compare character by character. They are COLLECTED into a
// `List<string>` first, which is also what makes `import System.Collections.Generic` a syntactic
// use: the dictionary walk DECLINES AT EMIT unless that namespace is imported, while `NL010` fails
// the build if the import is never named — so the file has to do both.
func SmOrdinalGreater(left: string, right: string): bool {
    index := 0
    while index < left.Length && index < right.Length {
        leftChar := left[index]
        rightChar := right[index]
        if leftChar != rightChar {
            return leftChar > rightChar
        }

        index = index + 1
    }

    return left.Length > right.Length
}

func SmSortRows(rows: string[]) {
    outer := 1
    while outer < rows.Length {
        current := rows[outer]
        inner := outer
        while inner > 0 && SmOrdinalGreater(rows[inner - 1], current) {
            rows[inner] = rows[inner - 1]
            inner = inner - 1
        }

        rows[inner] = current
        outer = outer + 1
    }
}

func SmJoinRows(rows: string[]): string {
    census := ""
    index := 0
    while index < rows.Length {
        census = census + rows[index] + ";"
        index = index + 1
    }

    return census
}

// ---- the production entry points ------------------------------------------------------------------

// The production recovery parser, asked with the file name `test.nl` — exactly as the deleted
// `Analyze` helper asked it.
func SmParse(source: string): object {
    parserType := Type.GetType("NSharpLang.Compiler.Columnar.ColumnarParserRecovery, NSharpLang.Compiler.BootstrapServices")
    if parserType == null {
        throw new InvalidOperationException("The production recovery parser was not loadable.")
    }

    parseParameterTypes := new Type[](2)
    parseParameterTypes[0] = typeof(string)
    parseParameterTypes[1] = typeof(string)
    parseMethod := parserType.GetMethod("ParseFileAst", parseParameterTypes)
    if parseMethod == null {
        throw new InvalidOperationException("The production ParseFileAst entry point was not found.")
    }

    parseArguments := new object?[](2)
    SetSmObject(parseArguments, 0, source)
    SetSmObject(parseArguments, 1, "test.nl")
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return parsed
}

func SmParseUnit(source: string): object {
    return SmRequiredMember(SmParse(source), "CompilationUnit")
}

// Every PARSE diagnostic of a fixture, in recording order.
func SmParseCensus(source: string): string {
    errors := SmRequiredMember(SmParse(source), "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + SmText(entry, "DiagnosticId") + "@" + SmText(entry, "Line") + ":" + SmText(entry, "Column") + "+" + SmText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

// The production analysis — `new Analyzer()`, `LoadSystemAssemblies()` and the FOUR-ARGUMENT
// `Analyze(unit, "test.nl", null, source)`, which is the overload the deleted helper called. It is
// NOT the single-argument overload slice 25's cluster used: this one is handed the file path and
// the source text as well.
func SmAnalyze(source: string): object {
    unit := SmParseUnit(source)

    analyzerType := Type.GetType("NSharpLang.Compiler.Analyzer, Compiler")
    unitType := Type.GetType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.BootstrapServices")
    if analyzerType == null || unitType == null {
        throw new InvalidOperationException("The production analyzer types were not loadable.")
    }

    analyzerConstructor := analyzerType.GetConstructor(new Type[](0))
    if analyzerConstructor == null {
        throw new InvalidOperationException("The production analyzer was not constructible.")
    }
    analyzer := analyzerConstructor.Invoke(new object?[](0))

    loadParameterTypes := new Type[](0)
    loadMethod := analyzerType.GetMethod("LoadSystemAssemblies", loadParameterTypes)
    if loadMethod == null {
        throw new InvalidOperationException("The production LoadSystemAssemblies entry point was not found.")
    }
    loadArguments := new object?[](0)
    loadMethod.Invoke(analyzer, loadArguments)

    analyzeParameterTypes := new Type[](4)
    analyzeParameterTypes[0] = unitType
    analyzeParameterTypes[1] = typeof(string)
    analyzeParameterTypes[2] = typeof(string)
    analyzeParameterTypes[3] = typeof(string)
    analyzeMethod := analyzerType.GetMethod("Analyze", analyzeParameterTypes)
    if analyzeMethod == null {
        throw new InvalidOperationException("The production four-argument Analyze entry point was not found.")
    }

    analyzeArguments := new object?[](4)
    SetSmObject(analyzeArguments, 0, unit)
    SetSmObject(analyzeArguments, 1, "test.nl")
    SetSmObject(analyzeArguments, 2, null)
    SetSmObject(analyzeArguments, 3, source)
    analysis := analyzeMethod.Invoke(analyzer, analyzeArguments)

    disposeParameterTypes := new Type[](0)
    disposeMethod := analyzerType.GetMethod("Dispose", disposeParameterTypes)
    if disposeMethod != null {
        disposeArguments := new object?[](0)
        disposeMethod.Invoke(analyzer, disposeArguments)
    }

    if analysis == null {
        throw new InvalidOperationException("The production analyzer returned no result.")
    }

    return analysis
}

func SmModel(analysis: object): object {
    return SmRequiredMember(analysis, "SemanticModel")
}

func SmModelIsNull(analysis: object): string {
    if SmMember(analysis, "SemanticModel") == null {
        return "yes"
    }

    return "no"
}

// EVERY diagnostic's id, code name and span, in recording order.
func SmCensus(analysis: object): string {
    errors := SmRequiredMember(analysis, "Errors") as IList
    if errors == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + SmText(entry, "DiagnosticId") + ":" + SmText(entry, "Code") + "@" + SmText(entry, "Line") + ":" + SmText(entry, "Column") + "+" + SmText(entry, "Length") + ";"
        }

        index = index + 1
    }

    return census
}

func SmHasErrors(analysis: object): string {
    return SmText(analysis, "HasErrors")
}

// Every entry of a dictionary, as an array, WITHOUT ever typing a local as a collection interface.
// That is a measured constraint rather than a preference: the columnar emitter declines a LOCAL
// whose type is `System.Collections.IDictionary` OR `System.Collections.IEnumerable`, both at
// `emit.local.unsupported-type`. `IList` locals ARE accepted, which is why the list censuses below
// still use one — but a `Dictionary<,>` is not an `IList`, so its entries are walked through the
// enumerator by reflection and land in an `object?[]`. Each entry is a boxed key/value pair whose
// `Key` and `Value` the same member walk reads.
func SmEntries(value: object): object?[] {
    valueType := value.GetType()
    enumeratorParameterTypes := new Type[](0)
    enumeratorMethod := valueType.GetMethod("GetEnumerator", enumeratorParameterTypes)
    if enumeratorMethod == null {
        throw new InvalidOperationException("The production collection exposed no GetEnumerator.")
    }

    enumeratorArguments := new object?[](0)
    enumerator := enumeratorMethod.Invoke(value, enumeratorArguments)
    if enumerator == null {
        throw new InvalidOperationException("The production collection returned no enumerator.")
    }

    enumeratorType := enumerator.GetType()
    moveNextParameterTypes := new Type[](0)
    moveNextMethod := enumeratorType.GetMethod("MoveNext", moveNextParameterTypes)
    currentProperty := enumeratorType.GetProperty("Current")
    if moveNextMethod == null || currentProperty == null {
        throw new InvalidOperationException("The production enumerator was not walkable.")
    }

    rows := new object?[](SmCount(value))
    filled := 0
    moveNextArguments := new object?[](0)
    while Convert.ToBoolean(moveNextMethod.Invoke(enumerator, moveNextArguments)) {
        rows[filled] = currentProperty.GetValue(enumerator)
        filled = filled + 1
    }

    return rows
}

// ---- the model's tables ---------------------------------------------------------------------------

// Every entry of a `Dictionary<string, TypeInfo>`, sorted ordinally by the whole row. Dictionary
// enumeration order is not contractual, so nothing here depends on it.
//
// THE WALK GOES THROUGH `IEnumerable` AND NOT `IDictionary`, AND THAT IS A MEASURED CONSTRAINT
// RATHER THAN A PREFERENCE: a LOCAL whose type is `System.Collections.IDictionary` is declined by
// the columnar emitter at `emit.local.unsupported-type`. Enumerating the same object as a plain
// `IEnumerable` yields each entry boxed, and its `Key` / `Value` are read by the same member walk
// every other read here uses.
func SmDictionaryCensus(value: object?): string {
    if value == null {
        return "<not-a-dictionary>"
    }

    entries := SmEntries(value)
    rows := new string[](entries.Length)
    index := 0
    while index < entries.Length {
        entry := entries[index]
        if entry == null {
            return "<null-entry>"
        }

        rows[index] = SmValueText(SmMember(entry, "Key")) + "=" + SmValueText(SmMember(entry, "Value"))
        index = index + 1
    }

    SmSortRows(rows)
    return SmJoinRows(rows)
}

func SmTable(model: object, tableName: string): string {
    return SmDictionaryCensus(SmMember(model, tableName))
}

// `TypeMembers` is a dictionary OF dictionaries, so each row carries its own nested census.
func SmTypeMembers(model: object): string {
    entries := SmEntries(SmRequiredMember(model, "TypeMembers"))
    rows := new string[](entries.Length)
    index := 0
    while index < entries.Length {
        entry := entries[index]
        if entry == null {
            return "<null-entry>"
        }

        rows[index] = SmValueText(SmMember(entry, "Key")) + "{" + SmDictionaryCensus(SmMember(entry, "Value")) + "}"
        index = index + 1
    }

    SmSortRows(rows)
    return SmJoinRows(rows)
}

func SmPad(value: string): string {
    padded := value
    while padded.Length < 6 {
        padded = "0" + padded
    }

    return padded
}

// The two POSITION tables are keyed by a named value tuple, so the key is read through reflection
// on its `Item1` / `Item2` fields and the rows are ordered NUMERICALLY by line and then column —
// not by text, which would put line 10 before line 2. Each row carries a twelve-character
// zero-padded sort prefix that the census strips back off, which turns the ordinal row sort into a
// numeric one.
func SmPositionCensus(value: object?): string {
    if value == null {
        return "<not-a-dictionary>"
    }

    entries := SmEntries(value)
    rows := new string[](entries.Length)
    index := 0
    while index < entries.Length {
        entry := entries[index]
        if entry == null {
            return "<null-entry>"
        }

        key := SmMember(entry, "Key")
        if key == null {
            return "<null-position-key>"
        }

        keyType := key.GetType()
        lineField := keyType.GetField("Item1")
        columnField := keyType.GetField("Item2")
        if lineField == null || columnField == null {
            return "<not-a-position-key>"
        }

        line := SmValueText(lineField.GetValue(key))
        column := SmValueText(columnField.GetValue(key))
        rows[index] = SmPad(line) + SmPad(column) + line + ":" + column + "=" + SmValueText(SmMember(entry, "Value"))
        index = index + 1
    }

    SmSortRows(rows)

    census := ""
    ordered := 0
    while ordered < rows.Length {
        census = census + rows[ordered].Substring(12) + ";"
        ordered = ordered + 1
    }

    return census
}

func SmExpressionTypes(model: object): string {
    return SmPositionCensus(SmMember(model, "ExpressionTypes"))
}

func SmTypeReferenceTypes(model: object): string {
    return SmPositionCensus(SmMember(model, "TypeReferenceTypes"))
}

// The scope list is cast at each use site rather than answered by a shared helper: a function
// whose RETURN TYPE is `IList` declines at emit in this file, while an `as IList` LOCAL does not.
func SmScopeCount(model: object): int {
    return SmCount(SmRequiredMember(model, "Scopes"))
}

// Every scope, in recording order — its id, its parent, both bounds, and the names it holds.
func SmScopes(model: object): string {
    scopes := SmRequiredMember(model, "Scopes") as IList
    if scopes == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < scopes.Count {
        entry := scopes[index]
        if entry != null {
            census = census + SmText(entry, "Id") + "<" + SmText(entry, "ParentId") + "|" + SmText(entry, "StartLine") + ":" + SmText(entry, "StartColumn") + "-" + SmText(entry, "EndLine") + ":" + SmText(entry, "EndColumn") + "|v=" + SmDictionaryCensus(SmMember(entry, "Variables")) + "|f=" + SmDictionaryCensus(SmMember(entry, "Functions")) + ";"
        }

        index = index + 1
    }

    return census
}

// ---- the model's queries ---------------------------------------------------------------------------

func SmInvoke(model: object, methodName: string, parameterTypes: Type[], arguments: object?[]): object? {
    method := model.GetType().GetMethod(methodName, parameterTypes)
    if method == null {
        throw new InvalidOperationException("The production '" + methodName + "' entry point was not found.")
    }

    return method.Invoke(model, arguments)
}

func SmLookupIdentifier(model: object, name: string): string {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    arguments := new object?[](1)
    SetSmObject(arguments, 0, name)
    return SmValueText(SmInvoke(model, "LookupIdentifier", parameterTypes, arguments))
}

func SmLookupIdentifierAtPosition(model: object, name: string, line: int, column: int): string {
    parameterTypes := new Type[](3)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(int)
    parameterTypes[2] = typeof(int)
    arguments := new object?[](3)
    SetSmObject(arguments, 0, name)
    SetSmObject(arguments, 1, line)
    SetSmObject(arguments, 2, column)
    return SmValueText(SmInvoke(model, "LookupIdentifierAtPosition", parameterTypes, arguments))
}

func SmPositionQuery(model: object, methodName: string, line: int, column: int): object? {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(int)
    parameterTypes[1] = typeof(int)
    arguments := new object?[](2)
    SetSmObject(arguments, 0, line)
    SetSmObject(arguments, 1, column)
    return SmInvoke(model, methodName, parameterTypes, arguments)
}

func SmLookupTypeAtPosition(model: object, line: int, column: int): string {
    return SmValueText(SmPositionQuery(model, "LookupTypeAtPosition", line, column))
}

func SmLookupTypeReferenceAtPosition(model: object, line: int, column: int): string {
    return SmValueText(SmPositionQuery(model, "LookupTypeReferenceAtPosition", line, column))
}

func SmVisibleVariablesAtPosition(model: object, line: int, column: int): string {
    return SmDictionaryCensus(SmPositionQuery(model, "GetVisibleVariablesAtPosition", line, column))
}

func SmGetTypeMembers(model: object, typeName: string): string {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    arguments := new object?[](1)
    SetSmObject(arguments, 0, typeName)
    members := SmInvoke(model, "GetTypeMembers", parameterTypes, arguments)
    if members == null {
        return "<null>"
    }

    return SmDictionaryCensus(members)
}

func SmGetTypeMemberCount(model: object, typeName: string): int {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    arguments := new object?[](1)
    SetSmObject(arguments, 0, typeName)
    members := SmInvoke(model, "GetTypeMembers", parameterTypes, arguments)
    if members == null {
        return -1
    }

    return SmCount(members)
}

func SmListCensus(value: object?): string {
    list := value as IList
    if list == null {
        return "<null>"
    }

    census := ""
    index := 0
    while index < list.Count {
        census = census + SmValueText(list[index]) + ";"
        index = index + 1
    }

    return census
}

// Each source parameter type as its RUNTIME type name and its `Name`, which is the pair the
// deleted `Assert.Equal("int", Assert.IsType<SimpleTypeReference>(Assert.Single(…)).Name)` made.
func SmTypeReferenceListCensus(value: object?): string {
    list := value as IList
    if list == null {
        return "<null>"
    }

    census := ""
    index := 0
    while index < list.Count {
        entry := list[index]
        if entry == null {
            census = census + "<null>;"
        } else {
            entryType := entry.GetType()
            census = census + entryType.Name + ":" + SmText(entry, "Name") + ";"
        }

        index = index + 1
    }

    return census
}

// The overload-selection row, read off the expression-type table. `ExpressionTypes` is keyed by a
// value tuple that a `.tests.nl` cannot construct, so the read goes through
// `LookupTypeAtPosition`, which the estate's own `SemanticModel.tests.nl` proves reads THAT table
// and no other.
func SmFunctionTypeFacts(model: object, line: int, column: int): string {
    selected := SmPositionQuery(model, "LookupTypeAtPosition", line, column)
    if selected == null {
        return "<null>"
    }

    selectedType := selected.GetType()
    return selectedType.Name + "|" + SmText(selected, "SyntheticName") + "|" + SmValueText(SmMember(selected, "ReturnType")) + "|" + SmListCensus(SmMember(selected, "ParameterNames")) + "|" + SmTypeReferenceListCensus(SmMember(selected, "SourceParameterTypes"))
}

func SmRuntimeTypeName(value: object?): string {
    if value == null {
        return "<null>"
    }

    valueType := value.GetType()
    return valueType.Name
}

// ---- contracts ----

// WHAT THIS ADDS: The deleted method asserted the model was non-null and that `x` looked up as `int`.
// This adds the WHOLE model: the flat variable table, the function table (which holds a
// `FunctionTypeInfo` whose `ToString()` is its CLR NAME, not a signature), the expression type
// recorded at the literal's own column, and all THREE scopes.
test "020 s26 analyzer semantic model: an inferred `int` local is `int` in the flat table AND in the expression table at 3:10, and the analysis is silent (was AnalyzerSemanticModelTests.Analyzer_VariableDeclaration_PopulatesSemanticModel)" {
    source := "\nfunc test() {\n    x := 42\n}"
    assert source.Length == 28
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "x=int;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=int;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-3:2147483647|v=x=int;|f=;"
    assert SmLookupIdentifier(model, "x") == "int"
}

// WHAT THIS ADDS: The deleted method read only `LookupIdentifier("name")`. The two position tables are
// different tables and this fixture fills both — 3:20 in the expression table for the literal, 3:11 in
// the type-reference table for the annotation `string`.
test "020 s26 analyzer semantic model: an explicitly typed `string` local records BOTH an expression type at the literal and a type REFERENCE at the annotation (was AnalyzerSemanticModelTests.Analyzer_VariableWithExplicitType_PopulatesSemanticModel)" {
    source := "\nfunc test() {\n    name: string = \"John\"\n}"
    assert source.Length == 42
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "name=string;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:20=string;"
    assert SmTypeReferenceTypes(model) == "3:11=string;"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-3:2147483647|v=name=string;|f=;"
    assert SmLookupIdentifier(model, "name") == "string"
}

// WHAT THIS ADDS: The deleted method asserted the two flat lookups. The scope census is the find:
// `name` and `age` are recorded in scope 1, the function scope opened at 2:1, while scope 2 — the BODY
// block opened at 2:36 — holds nothing at all.
test "020 s26 analyzer semantic model: both function parameters live in the FUNCTION scope and not in the body scope, and the body scope is empty (was AnalyzerSemanticModelTests.Analyzer_FunctionParameters_PopulateSemanticModel)" {
    source := "\nfunc greet(name: string, age: int) {\n    print(name)\n}"
    assert source.Length == 55
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "age=int;name=string;"
    assert SmTable(model, "Functions") == "greet=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=string;3:11=string;"
    assert SmTypeReferenceTypes(model) == "2:18=string;2:31=int;"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=age=int;name=string;|f=greet=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:36-3:2147483647|v=|f=;"
    assert SmLookupIdentifier(model, "age") == "int"
    assert SmLookupIdentifier(model, "name") == "string"
}

// WHAT THIS ADDS: The deleted method asserted `LookupIdentifier("getNumber")` is `int` and stopped.
// Both sides are pinned here: the `Functions` table row is the CLR name
// `NSharpLang.Compiler.FunctionTypeInfo`, and the LOOKUP answers `int` — so the mapping through
// `GetFunctionLookupType` is visible rather than implied.
test "020 s26 analyzer semantic model: a function name looks up as its RETURN type while the table it comes from holds a `FunctionTypeInfo` (was AnalyzerSemanticModelTests.Analyzer_FunctionReturnType_PopulatesSemanticModel)" {
    source := "\nfunc getNumber(): int {\n    return 42\n}"
    assert source.Length == 40
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == "getNumber=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:12=int;"
    assert SmTypeReferenceTypes(model) == "2:19=int;"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=getNumber=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:23-3:2147483647|v=|f=;"
    assert SmLookupIdentifier(model, "getNumber") == "int"
}

// WHAT THIS ADDS: The deleted method reached `ExpressionTypes.TryGetValue((9, 15))` directly. A
// `.tests.nl` cannot construct the value-tuple key, so the read goes through `LookupTypeAtPosition`,
// which the estate's own contracts prove reads that table and no other. This also pins what the
// deleted assertions were silent about: the flat `Variables` table keeps only `value=string` — the
// SECOND overload's parameter overwrote the first's — and the file opens SEVEN scopes.
test "020 s26 analyzer semantic model: the overload chosen at the call site is recorded IN the expression table with its synthetic name, return type and parameter facts (was AnalyzerSemanticModelTests.Analyzer_TopLevelOverloadCall_RecordsFunctionTypeInfoFacts)" {
    source := "\nfunc Pick(value: int): int {\n    return value\n}\nfunc Pick(value: string): string {\n    return value\n}\nfunc Main() {\n    result := Pick(42)\n}"
    assert source.Length == 141
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "result=int;value=string;"
    assert SmTable(model, "Functions") == "Main=NSharpLang.Compiler.FunctionTypeInfo;Pick=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:12=int;6:12=string;9:15=NSharpLang.Compiler.FunctionTypeInfo;9:19=int;9:20=int;"
    assert SmTypeReferenceTypes(model) == "2:18=int;2:24=int;5:18=string;5:27=string;"
    assert SmScopeCount(model) == 7
    assert SmScopes(model) == "0<-1|1:1-9:2147483647|v=|f=;1<0|2:1-3:2147483647|v=value=int;|f=Pick=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:28-3:2147483647|v=|f=;3<0|5:1-6:2147483647|v=value=string;|f=Pick=NSharpLang.Compiler.FunctionTypeInfo;;4<3|5:34-6:2147483647|v=|f=;5<0|8:1-9:2147483647|v=|f=Main=NSharpLang.Compiler.FunctionTypeInfo;;6<5|8:13-9:2147483647|v=result=int;|f=;"
    assert SmFunctionTypeFacts(model, 9, 15) == "FunctionTypeInfo|Pick|int|value;|SimpleTypeReference:int;"
}

// WHAT THIS ADDS: The deleted method asserted the three flat lookups. The expression table gives each
// literal's column, and all three locals share ONE scope.
test "020 s26 analyzer semantic model: three inferred locals of three different types, each with its own expression type on its own line (was AnalyzerSemanticModelTests.Analyzer_MultipleVariables_AllInSemanticModel)" {
    source := "\nfunc test() {\n    x := 1\n    name := \"test\"\n    active := true\n}"
    assert source.Length == 65
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "active=bool;name=string;x=int;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=int;4:13=string;5:15=bool;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-5:2147483647|v=|f=;1<0|2:1-5:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-5:2147483647|v=active=bool;name=string;x=int;|f=;"
    assert SmLookupIdentifier(model, "active") == "bool"
    assert SmLookupIdentifier(model, "name") == "string"
    assert SmLookupIdentifier(model, "x") == "int"
}

// WHAT THIS ADDS: The deleted method asserted `numbers` is `int[]`. The expression table is the find:
// the array literal itself is `int[]` at 3:22 and each of its three elements is separately recorded as
// `int`.
test "020 s26 analyzer semantic model: an explicit `int[]` annotation records the ARRAY type at the annotation and the ELEMENT type at each literal (was AnalyzerSemanticModelTests.Analyzer_ArrayType_PopulatesSemanticModel)" {
    source := "\nfunc test() {\n    numbers: int[] = [1, 2, 3]\n}"
    assert source.Length == 47
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "numbers=int[];"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:22=int[];3:23=int;3:26=int;3:29=int;"
    assert SmTypeReferenceTypes(model) == "3:14=int[];"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-3:2147483647|v=numbers=int[];|f=;"
    assert SmLookupIdentifier(model, "numbers") == "int[]"
}

// WHAT THIS ADDS: The deleted method asserted `optionalName` is `string?`. The expression table
// records the literal's type as `null` — not `string?` and not absent.
test "020 s26 analyzer semantic model: a nullable annotation keeps its `?` in every table, and the `null` literal's recorded type is the string `null` (was AnalyzerSemanticModelTests.Analyzer_NullableType_PopulatesSemanticModel)" {
    source := "\nfunc test() {\n    optionalName: string? = null\n}"
    assert source.Length == 49
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "optionalName=string?;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:29=null;"
    assert SmTypeReferenceTypes(model) == "3:19=string?;"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-3:2147483647|v=optionalName=string?;|f=;"
    assert SmLookupIdentifier(model, "optionalName") == "string?"
}

// WHAT THIS ADDS: The deleted method asserted the inferred type. The contrast with the annotated
// fixture is the find: the type-reference table is EMPTY here, because there is no annotation to
// anchor one on.
test "020 s26 analyzer semantic model: an inferred array gets the same `int[]` as the annotated one, with NO type-reference row at all (was AnalyzerSemanticModelTests.Analyzer_InferredArrayType_PopulatesSemanticModel)" {
    source := "\nfunc test() {\n    numbers := [1, 2, 3]\n}"
    assert source.Length == 41
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "numbers=int[];"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:16=int[];3:17=int;3:20=int;3:23=int;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-3:2147483647|v=numbers=int[];|f=;"
    assert SmLookupIdentifier(model, "numbers") == "int[]"
}

// WHAT THIS ADDS: The deleted method asserted only that the model and `x` were non-null when analysis
// fails. This names the type — `unknown`, recorded in the flat table AND at both expression positions
// — and pins the single diagnostic whole, which nothing did.
test "020 s26 analyzer semantic model: a call to an undefined function still records the local, as `unknown`, and reports exactly one NL412 (was AnalyzerSemanticModelTests.Analyzer_SemanticModelNotNull_EvenWithErrors)" {
    source := "\nfunc test() {\n    x := unknownFunction()  // This will cause an error\n}"
    assert source.Length == 72
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == "NL412:UndefinedFunction@3:10+15;"
    assert SmHasErrors(analysis) == "True"
    assert SmTable(model, "Variables") == "x=unknown;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=unknown;3:25=unknown;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-3:2147483647|v=x=unknown;|f=;"
    assert SmLookupIdentifier(model, "x") == "unknown"
}

// WHAT THIS ADDS: The deleted method asserted `doubled` is `List<int>`. The scope census is the find:
// two lambdas produce TWELVE scopes, eight at 6:30 and four at 6:49, every one of them holding the
// same `x=int` — the analyzer re-enters lambda bodies during overload resolution and each entry opens
// a scope that is never merged. The expression table also names the intermediate `Where(...)` /
// `Select(...)` / `ToList(...)` method types.
test "020 s26 analyzer semantic model: a LINQ chain infers `List<int>` and opens FIFTEEN scopes for one statement (was AnalyzerSemanticModelTests.Analyzer_LINQMethodChain_InfersConstructedListType)" {
    source := "\nimport System.Linq\n\nfunc test() {\n    numbers: int[] = [1, 2, 3, 4, 5]\n    doubled := numbers.Where(x => x > 2).Select(x => x * 2).ToList()\n}"
    assert source.Length == 142
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "doubled=List<int>;numbers=int[];x=int;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "5:22=int[];5:23=int;5:26=int;5:29=int;5:32=int;5:35=int;6:16=int[];6:23=Where(...);6:29=IEnumerable<int>;6:35=int;6:37=bool;6:39=int;6:41=Select(...);6:48=IEnumerable<int>;6:54=int;6:56=int;6:58=int;6:60=ToList(...);6:67=List<int>;"
    assert SmTypeReferenceTypes(model) == "5:14=int[];"
    assert SmScopeCount(model) == 15
    assert SmScopes(model) == "0<-1|1:1-6:2147483647|v=|f=;1<0|4:1-6:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|4:13-6:2147483647|v=doubled=List<int>;numbers=int[];|f=;3<2|6:30-6:2147483647|v=x=int;|f=;4<2|6:30-6:2147483647|v=x=int;|f=;5<2|6:30-6:2147483647|v=x=int;|f=;6<2|6:30-6:2147483647|v=x=int;|f=;7<2|6:49-6:2147483647|v=x=int;|f=;8<2|6:49-6:2147483647|v=x=int;|f=;9<2|6:30-6:2147483647|v=x=int;|f=;10<2|6:30-6:2147483647|v=x=int;|f=;11<2|6:30-6:2147483647|v=x=int;|f=;12<2|6:30-6:2147483647|v=x=int;|f=;13<2|6:49-6:2147483647|v=x=int;|f=;14<2|6:49-6:2147483647|v=x=int;|f=;"
    assert SmLookupIdentifier(model, "doubled") == "List<int>"
}

// WHAT THIS ADDS: The deleted method asserted `indexed` is `List<int>`. Four scopes are opened at 6:31
// and each holds both `item` and `index`.
test "020 s26 analyzer semantic model: a two-parameter indexed `Select` infers `List<int>` and puts BOTH lambda parameters in every lambda scope (was AnalyzerSemanticModelTests.Analyzer_LINQIndexedSelect_InfersConstructedListType)" {
    source := "\nimport System.Linq\n\nfunc test() {\n    numbers: int[] = [1, 2, 3]\n    indexed := numbers.Select((item, index) => item + index).ToList()\n}"
    assert source.Length == 137
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "index=int;indexed=List<int>;item=int;numbers=int[];"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "5:22=int[];5:23=int;5:26=int;5:29=int;6:16=int[];6:23=Select(...);6:30=IEnumerable<int>;6:48=int;6:53=int;6:55=int;6:61=ToList(...);6:68=List<int>;"
    assert SmTypeReferenceTypes(model) == "5:14=int[];"
    assert SmScopeCount(model) == 7
    assert SmScopes(model) == "0<-1|1:1-6:2147483647|v=|f=;1<0|4:1-6:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|4:13-6:2147483647|v=indexed=List<int>;numbers=int[];|f=;3<2|6:31-6:2147483647|v=index=int;item=int;|f=;4<2|6:31-6:2147483647|v=index=int;item=int;|f=;5<2|6:31-6:2147483647|v=index=int;item=int;|f=;6<2|6:31-6:2147483647|v=index=int;item=int;|f=;"
    assert SmLookupIdentifier(model, "indexed") == "List<int>"
}

// WHAT THIS ADDS: The deleted method looked the read up at 4:10 and asserted `int`. The whole table is
// pinned, so the declaration at 3:10, the read at 4:10, the literal at 4:14 and the binary expression
// at 4:12 are all named and no longer interchangeable.
test "020 s26 analyzer semantic model: an identifier READ has its own expression-table row, distinct from the row at its declaration (was AnalyzerSemanticModelTests.Analyzer_ExpressionType_IsQueryableBySourcePosition)" {
    source := "\nfunc test() {\n    x := 41\n    y := x + 1\n}"
    assert source.Length == 43
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "x=int;y=int;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=int;4:10=int;4:12=int;4:14=int;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-4:2147483647|v=|f=;1<0|2:1-4:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-4:2147483647|v=x=int;y=int;|f=;"
    assert SmLookupTypeAtPosition(model, 4, 10) == "int"
}

// WHAT THIS ADDS: The deleted method asserted no errors and two `int`s. The two tables disagree by
// seven columns — the expression type sits at 3:13 on `sizeof` and the type REFERENCE at 3:20 on `int`
// — and the empty analysis census is now stated as a census rather than as `HasErrors == false`.
test "020 s26 analyzer semantic model: `sizeof(int)` is `int` at the KEYWORD, and the `int` inside the parentheses is a type reference at a different column (was AnalyzerSemanticModelTests.Analyzer_SizeofExpression_RecordsIntType)" {
    source := "\nfunc test() {\n    size := sizeof(int) + 1\n}"
    assert source.Length == 44
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "size=int;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:13=int;3:25=int;3:27=int;"
    assert SmTypeReferenceTypes(model) == "3:20=int;"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-3:2147483647|v=size=int;|f=;"
    assert SmLookupIdentifier(model, "size") == "int"
    assert SmLookupTypeAtPosition(model, 3, 13) == "int"
}

// WHAT THIS ADDS: The deleted method asserted the two `base` reads. The third `base` in the file — the
// `constructor(): base()` initializer at 9:20 — records `unknown`, which nothing asked about; and
// `TypeMembers` is EMPTY for both classes because neither declares a field.
test "020 s26 analyzer semantic model: bare `base` and `base` as a receiver both record the BASE type, and the constructor initializer records `unknown` (was AnalyzerSemanticModelTests.Analyzer_BaseExpression_RecordsBaseType)" {
    source := "\nclass Base {\n    func value(): int {\n        return 1\n    }\n}\n\nclass Derived: Base {\n    constructor(): base() {\n    }\n\n    func selfAsBase(): Base {\n        return base\n    }\n\n    func baseValue(): int {\n        return base.value()\n    }\n}"
    assert source.Length == 241
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == "baseValue=NSharpLang.Compiler.FunctionTypeInfo;selfAsBase=NSharpLang.Compiler.FunctionTypeInfo;value=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == "Base=Base;Derived=Derived;"
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "4:16=int;9:20=unknown;13:16=Base;17:16=Base;17:20=NSharpLang.Compiler.FunctionTypeInfo;17:26=int;"
    assert SmTypeReferenceTypes(model) == "3:19=int;8:16=Base;12:24=Base;16:23=int;"
    assert SmScopeCount(model) == 11
    assert SmScopes(model) == "0<-1|1:1-17:2147483647|v=|f=;1<0|2:1-4:2147483647|v=|f=;2<1|3:5-4:2147483647|v=|f=value=NSharpLang.Compiler.FunctionTypeInfo;;3<2|3:23-4:2147483647|v=|f=;4<0|8:1-17:2147483647|v=|f=;5<4|9:5-9:2147483647|v=|f=;6<5|9:27-9:2147483647|v=|f=;7<4|12:5-13:2147483647|v=|f=selfAsBase=NSharpLang.Compiler.FunctionTypeInfo;;8<7|12:29-13:2147483647|v=|f=;9<4|16:5-17:2147483647|v=|f=baseValue=NSharpLang.Compiler.FunctionTypeInfo;;10<9|16:27-17:2147483647|v=|f=;"
    assert SmLookupTypeAtPosition(model, 13, 16) == "Base"
    assert SmLookupTypeAtPosition(model, 17, 16) == "Base"
}

// WHAT THIS ADDS: The deleted method asserted the member count and the two member types. This adds
// that the same two names are ALSO in the flat `Fields` table, that `Types` holds `Person`, and that
// the type-reference table anchors each annotation.
test "020 s26 analyzer semantic model: a class's two fields reach `TypeMembers` AND the top-level `Fields` table, and nothing else (was AnalyzerSemanticModelTests.Analyzer_ClassFields_RecordedInSemanticModelTypeMembers)" {
    source := "\nclass Person {\n    Name: string\n    Age: int\n}"
    assert source.Length == 47
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == "Age=int;Name=string;"
    assert SmTable(model, "Types") == "Person=Person;"
    assert SmTypeMembers(model) == "Person{Age=int;Name=string;};"
    assert SmExpressionTypes(model) == ""
    assert SmTypeReferenceTypes(model) == "3:11=string;4:10=int;"
    assert SmScopeCount(model) == 2
    assert SmScopes(model) == "0<-1|1:1-2:2147483647|v=|f=;1<0|2:1-2:2147483647|v=|f=;"
    assert SmGetTypeMemberCount(model, "Person") == 2
    assert SmGetTypeMembers(model, "Person") == "Age=int;Name=string;"
}

// WHAT THIS ADDS: The deleted method asserted two `float` members. Pinning both tables shows the
// struct and the class fixtures produce the same shape.
test "020 s26 analyzer semantic model: a struct's fields are recorded exactly as a class's are (was AnalyzerSemanticModelTests.Analyzer_StructFields_RecordedInSemanticModelTypeMembers)" {
    source := "\nstruct Vector {\n    X: float\n    Y: float\n}"
    assert source.Length == 44
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == "X=float;Y=float;"
    assert SmTable(model, "Types") == "Vector=Vector;"
    assert SmTypeMembers(model) == "Vector{X=float;Y=float;};"
    assert SmExpressionTypes(model) == ""
    assert SmTypeReferenceTypes(model) == "3:8=float;4:8=float;"
    assert SmScopeCount(model) == 2
    assert SmScopes(model) == "0<-1|1:1-2:2147483647|v=|f=;1<0|2:1-2:2147483647|v=|f=;"
    assert SmGetTypeMemberCount(model, "Vector") == 2
    assert SmGetTypeMembers(model, "Vector") == "X=float;Y=float;"
}

// WHAT THIS ADDS: The deleted method asserted two `int` members. The three-way agreement is now stated
// rather than spread across three methods.
test "020 s26 analyzer semantic model: a record's fields are recorded exactly as a class's and a struct's are (was AnalyzerSemanticModelTests.Analyzer_RecordFields_RecordedInSemanticModelTypeMembers)" {
    source := "\nrecord Point {\n    X: int\n    Y: int\n}"
    assert source.Length == 39
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == "X=int;Y=int;"
    assert SmTable(model, "Types") == "Point=Point;"
    assert SmTypeMembers(model) == "Point{X=int;Y=int;};"
    assert SmExpressionTypes(model) == ""
    assert SmTypeReferenceTypes(model) == "3:8=int;4:8=int;"
    assert SmScopeCount(model) == 2
    assert SmScopes(model) == "0<-1|1:1-2:2147483647|v=|f=;1<0|2:1-2:2147483647|v=|f=;"
    assert SmGetTypeMemberCount(model, "Point") == 2
    assert SmGetTypeMembers(model, "Point") == "X=int;Y=int;"
}

// WHAT THIS ADDS: The deleted method asserted the two member keys and their types. It never asked
// about diagnostics: the leading-underscore field `_host` reports `NL903:VisibilityConventionWarning`
// at 3:5, and `HasErrors` is therefore TRUE on a fixture the method treated as clean.
test "020 s26 analyzer semantic model: a field and a property of one class land in DIFFERENT flat tables but the SAME member table — and the field draws an NL903 (was AnalyzerSemanticModelTests.Analyzer_ClassProperties_RecordedInSemanticModelTypeMembers)" {
    source := "\nclass Config {\n    _host: string\n\n    Host: string {\n        get { return _host }\n    }\n}"
    assert source.Length == 90
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == "NL903:VisibilityConventionWarning@3:5+5;"
    assert SmHasErrors(analysis) == "True"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == "Host=string;"
    assert SmTable(model, "Fields") == "_host=string;"
    assert SmTable(model, "Types") == "Config=Config;"
    assert SmTypeMembers(model) == "Config{Host=string;_host=string;};"
    assert SmExpressionTypes(model) == "6:22=string;"
    assert SmTypeReferenceTypes(model) == "3:12=string;5:11=string;"
    assert SmScopeCount(model) == 4
    assert SmScopes(model) == "0<-1|1:1-6:2147483647|v=|f=;1<0|2:1-6:2147483647|v=|f=;2<1|5:5-6:2147483647|v=|f=;3<2|6:13-6:2147483647|v=|f=;"
    assert SmGetTypeMemberCount(model, "Config") == 2
    assert SmGetTypeMembers(model, "Config") == "Host=string;_host=string;"
}

// WHAT THIS ADDS: The deleted method asserted `Count == 4` and the four types. The census names which
// table each of the four is in — three in `Fields`, one in `Properties` — and the diagnostic the
// method was silent about.
test "020 s26 analyzer semantic model: four members of one class across two flat tables, with the same NL903 on the underscore field (was AnalyzerSemanticModelTests.Analyzer_MixedFieldsAndProperties_AllRecordedInTypeMembers)" {
    source := "\nclass Entity {\n    _active: bool\n    Id: int\n    Name: string\n\n    Active: bool {\n        get { return _active }\n    }\n}"
    assert source.Length == 121
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == "NL903:VisibilityConventionWarning@3:5+7;"
    assert SmHasErrors(analysis) == "True"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == "Active=bool;"
    assert SmTable(model, "Fields") == "Id=int;Name=string;_active=bool;"
    assert SmTable(model, "Types") == "Entity=Entity;"
    assert SmTypeMembers(model) == "Entity{Active=bool;Id=int;Name=string;_active=bool;};"
    assert SmExpressionTypes(model) == "8:22=bool;"
    assert SmTypeReferenceTypes(model) == "3:14=bool;4:9=int;5:11=string;7:13=bool;"
    assert SmScopeCount(model) == 4
    assert SmScopes(model) == "0<-1|1:1-8:2147483647|v=|f=;1<0|2:1-8:2147483647|v=|f=;2<1|7:5-8:2147483647|v=|f=;3<2|8:13-8:2147483647|v=|f=;"
    assert SmGetTypeMemberCount(model, "Entity") == 4
    assert SmGetTypeMembers(model, "Entity") == "Active=bool;Id=int;Name=string;_active=bool;"
}

// WHAT THIS ADDS: The deleted method asserted each type's members separately. The find is that
// `Fields` is FLAT across types: `Name`, `X` and `Y` sit in one dictionary with no owner, which is
// exactly why `TypeMembers` exists.
test "020 s26 analyzer semantic model: two types keep separate member tables while their fields SHARE one flat table (was AnalyzerSemanticModelTests.Analyzer_MultipleTypes_EachHasOwnTypeMembers)" {
    source := "\nclass Person {\n    Name: string\n}\n\nstruct Point {\n    X: int\n    Y: int\n}"
    assert source.Length == 74
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == "Name=string;X=int;Y=int;"
    assert SmTable(model, "Types") == "Person=Person;Point=Point;"
    assert SmTypeMembers(model) == "Person{Name=string;};Point{X=int;Y=int;};"
    assert SmExpressionTypes(model) == ""
    assert SmTypeReferenceTypes(model) == "3:11=string;7:8=int;8:8=int;"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-6:2147483647|v=|f=;1<0|2:1-2:2147483647|v=|f=;2<0|6:1-6:2147483647|v=|f=;"
    assert SmGetTypeMemberCount(model, "Person") == 1
    assert SmGetTypeMembers(model, "Person") == "Name=string;"
    assert SmGetTypeMemberCount(model, "Point") == 2
    assert SmGetTypeMembers(model, "Point") == "X=int;Y=int;"
}

// WHAT THIS ADDS: The deleted method asserted `members["Home"]` is `Address`. This adds that `Address`
// is in `Types` as a resolved entry and that the type-reference row at 7:11 carries it too.
test "020 s26 analyzer semantic model: a field whose type is another user type resolves to that type, and both types keep their own member table (was AnalyzerSemanticModelTests.Analyzer_FieldWithUserDefinedType_RecordedWithResolvedType)" {
    source := "\nrecord Address {\n    City: string\n}\n\nclass Person {\n    Home: Address\n}"
    assert source.Length == 72
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == "City=string;Home=Address;"
    assert SmTable(model, "Types") == "Address=Address;Person=Person;"
    assert SmTypeMembers(model) == "Address{City=string;};Person{Home=Address;};"
    assert SmExpressionTypes(model) == ""
    assert SmTypeReferenceTypes(model) == "3:11=string;7:11=Address;"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-6:2147483647|v=|f=;1<0|2:1-2:2147483647|v=|f=;2<0|6:1-6:2147483647|v=|f=;"
    assert SmGetTypeMemberCount(model, "Person") == 1
    assert SmGetTypeMembers(model, "Person") == "Home=Address;"
}

// WHAT THIS ADDS: The deleted method is a SECOND method over a BYTE-IDENTICAL fixture — the same 47
// characters as the class-members one — asserting the flat table instead of the member table. Both are
// pinned here, so the duplication is visible.
test "020 s26 analyzer semantic model: the same class fixture read through the top-level `Fields` table gives the same two rows (was AnalyzerSemanticModelTests.Analyzer_ClassFields_RecordedInTopLevelFieldsDict)" {
    source := "\nclass Person {\n    Name: string\n    Age: int\n}"
    assert source.Length == 47
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == "Age=int;Name=string;"
    assert SmTable(model, "Types") == "Person=Person;"
    assert SmTypeMembers(model) == "Person{Age=int;Name=string;};"
    assert SmExpressionTypes(model) == ""
    assert SmTypeReferenceTypes(model) == "3:11=string;4:10=int;"
    assert SmScopeCount(model) == 2
    assert SmScopes(model) == "0<-1|1:1-2:2147483647|v=|f=;1<0|2:1-2:2147483647|v=|f=;"
}

// WHAT THIS ADDS: The deleted method is a SECOND method over a BYTE-IDENTICAL fixture — the same 90
// characters as the class-properties one. The split is the content: `Host` is a property, `_host` is a
// field, and both are in `TypeMembers`.
test "020 s26 analyzer semantic model: the same config fixture read through `Properties` and `Fields` splits the two members by kind (was AnalyzerSemanticModelTests.Analyzer_ClassProperties_RecordedInTopLevelPropertiesDict)" {
    source := "\nclass Config {\n    _host: string\n\n    Host: string {\n        get { return _host }\n    }\n}"
    assert source.Length == 90
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == "NL903:VisibilityConventionWarning@3:5+5;"
    assert SmHasErrors(analysis) == "True"
    assert SmTable(model, "Variables") == ""
    assert SmTable(model, "Functions") == ""
    assert SmTable(model, "Properties") == "Host=string;"
    assert SmTable(model, "Fields") == "_host=string;"
    assert SmTable(model, "Types") == "Config=Config;"
    assert SmTypeMembers(model) == "Config{Host=string;_host=string;};"
    assert SmExpressionTypes(model) == "6:22=string;"
    assert SmTypeReferenceTypes(model) == "3:12=string;5:11=string;"
    assert SmScopeCount(model) == 4
    assert SmScopes(model) == "0<-1|1:1-6:2147483647|v=|f=;1<0|2:1-6:2147483647|v=|f=;2<1|5:5-6:2147483647|v=|f=;3<2|6:13-6:2147483647|v=|f=;"
}

// WHAT THIS ADDS: The deleted method asserted `Scopes.Count >= 2`, which a model with twenty scopes
// would satisfy. The answer is exactly 3 — global, function, body — and the fixture is BYTE-IDENTICAL
// to the first one in this file.
test "020 s26 analyzer semantic model: the scope count of the simplest possible function is EXACTLY three, not merely at least two (was AnalyzerSemanticModelTests.Analyzer_ScopesAreRecorded_ForFunctionAndBlocks)" {
    source := "\nfunc test() {\n    x := 42\n}"
    assert source.Length == 28
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "x=int;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=int;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-3:2147483647|v=x=int;|f=;"
}

// WHAT THIS ADDS: The deleted method asserted the two position-aware answers and that the flat answer
// was non-null. The flat answer is `string` — the INNER binding — which is the whole reason
// position-aware lookup exists; and the shadow reports `NL316` at 5:9, which the method never
// mentioned.
test "020 s26 analyzer semantic model: shadowing keeps the OUTER type at the outer position and the INNER type inside the block, and the flat table keeps only the inner one (was AnalyzerSemanticModelTests.Analyzer_VariableShadowing_PositionAwareLookup)" {
    source := "\nfunc test() {\n    x := 42\n    if true {\n        x := \"hello\"\n    }\n}"
    assert source.Length == 69
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == "NL316:ShadowedDeclaration@5:9+1;"
    assert SmHasErrors(analysis) == "True"
    assert SmTable(model, "Variables") == "x=string;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=int;4:8=bool;5:14=string;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 4
    assert SmScopes(model) == "0<-1|1:1-5:2147483647|v=|f=;1<0|2:1-5:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-5:2147483647|v=x=int;|f=;3<2|4:13-5:2147483647|v=x=string;|f=;"
    assert SmLookupIdentifier(model, "x") == "string"
    assert SmLookupIdentifierAtPosition(model, "x", 3, 5) == "int"
    assert SmLookupIdentifierAtPosition(model, "x", 5, 9) == "string"
}

// WHAT THIS ADDS: The deleted method asserted six non-null lookups and named nothing. Every answer is
// pinned as a TYPE, and the scope census shows the nesting the six lookups were probing: 2 < 3 < 4,
// each holding exactly one name.
test "020 s26 analyzer semantic model: a name declared in an outer scope answers at every inner position, and the three scopes nest by depth (was AnalyzerSemanticModelTests.Analyzer_NestedScopes_VariableVisibility)" {
    source := "\nfunc outer() {\n    a := 1\n    if true {\n        b := 2\n        if true {\n            c := 3\n        }\n    }\n}"
    assert source.Length == 110
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "a=int;b=int;c=int;"
    assert SmTable(model, "Functions") == "outer=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=int;4:8=bool;5:14=int;6:12=bool;7:18=int;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 5
    assert SmScopes(model) == "0<-1|1:1-7:2147483647|v=|f=;1<0|2:1-7:2147483647|v=|f=outer=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:14-7:2147483647|v=a=int;|f=;3<2|4:13-7:2147483647|v=b=int;|f=;4<3|6:17-7:2147483647|v=c=int;|f=;"
    assert SmLookupIdentifierAtPosition(model, "a", 3, 5) == "int"
    assert SmLookupIdentifierAtPosition(model, "a", 5, 9) == "int"
    assert SmLookupIdentifierAtPosition(model, "a", 7, 13) == "int"
    assert SmLookupIdentifierAtPosition(model, "b", 5, 9) == "int"
    assert SmLookupIdentifierAtPosition(model, "b", 7, 13) == "int"
    assert SmLookupIdentifierAtPosition(model, "c", 7, 13) == "int"
}

// WHAT THIS ADDS: The deleted method asserted six `ContainsKey`s. A model that answered every name for
// every position would pass all six; the census states the exact set at both positions — three names
// inside the block and two before it.
test "020 s26 analyzer semantic model: the visible-variable set at a position is the WHOLE set, not merely a superset (was AnalyzerSemanticModelTests.Analyzer_GetVisibleVariables_AtDifferentPositions)" {
    source := "\nfunc test() {\n    x := 1\n    y := \"hello\"\n    if true {\n        z := true\n    }\n}"
    assert source.Length == 82
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "x=int;y=string;z=bool;"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=int;4:10=string;5:8=bool;6:14=bool;"
    assert SmTypeReferenceTypes(model) == ""
    assert SmScopeCount(model) == 4
    assert SmScopes(model) == "0<-1|1:1-6:2147483647|v=|f=;1<0|2:1-6:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-6:2147483647|v=x=int;y=string;|f=;3<2|5:13-6:2147483647|v=z=bool;|f=;"
    assert SmVisibleVariablesAtPosition(model, 4, 5) == "test=NSharpLang.Compiler.FunctionTypeInfo;x=int;y=string;"
    assert SmVisibleVariablesAtPosition(model, 6, 9) == "test=NSharpLang.Compiler.FunctionTypeInfo;x=int;y=string;z=bool;"
}

// WHAT THIS ADDS: The deleted method asserted both position-aware answers. The scope census explains
// them: the parameters are in scope 1, which starts at 2:1, and the body scope 2 holds only `message`.
test "020 s26 analyzer semantic model: the parameters are visible in the body although they are recorded in the FUNCTION scope (was AnalyzerSemanticModelTests.Analyzer_FunctionParameters_RecordedInFunctionScope)" {
    source := "\nfunc greet(name: string, age: int) {\n    message := name\n}"
    assert source.Length == 59
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "age=int;message=string;name=string;"
    assert SmTable(model, "Functions") == "greet=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:16=string;"
    assert SmTypeReferenceTypes(model) == "2:18=string;2:31=int;"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-3:2147483647|v=|f=;1<0|2:1-3:2147483647|v=age=int;name=string;|f=greet=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:36-3:2147483647|v=message=string;|f=;"
    assert SmLookupIdentifierAtPosition(model, "age", 3, 5) == "int"
    assert SmLookupIdentifierAtPosition(model, "name", 3, 5) == "string"
}

// WHAT THIS ADDS: The deleted method asserted `item` is `int` at 5:9. The census shows two scopes are
// opened for one `foreach` — 3 at 4:5 holding `item`, and 4 at 4:27 holding nothing.
test "020 s26 analyzer semantic model: the loop variable lives in the FOREACH scope, and the loop BODY scope is empty (was AnalyzerSemanticModelTests.Analyzer_ForEachVariable_ScopedToLoop)" {
    source := "\nfunc test() {\n    items: int[] = [1, 2, 3]\n    foreach item in items {\n        print(item)\n    }\n}"
    assert source.Length == 99
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "item=int;items=int[];"
    assert SmTable(model, "Functions") == "test=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:20=int[];3:21=int;3:24=int;3:27=int;4:21=int[];5:14=int;5:15=int;"
    assert SmTypeReferenceTypes(model) == "3:12=int[];"
    assert SmScopeCount(model) == 5
    assert SmScopes(model) == "0<-1|1:1-5:2147483647|v=|f=;1<0|2:1-5:2147483647|v=|f=test=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:13-5:2147483647|v=items=int[];|f=;3<2|4:5-5:2147483647|v=item=int;|f=;4<3|4:27-5:2147483647|v=|f=;"
    assert SmLookupIdentifierAtPosition(model, "item", 5, 9) == "int"
}

// WHAT THIS ADDS: The deleted method asserted the two position-aware answers. The flat table holds
// `x=string` alone: the second function's parameter overwrote the first's, which is the collision
// position-aware lookup exists to resolve.
test "020 s26 analyzer semantic model: two functions with the same parameter name answer differently by position while the FLAT table keeps only the second (was AnalyzerSemanticModelTests.Analyzer_TwoFunctions_SameParameterName_DistinctScopes)" {
    source := "\nfunc first(x: int) {\n    print(x)\n}\n\nfunc second(x: string) {\n    print(x)\n}"
    assert source.Length == 77
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "x=string;"
    assert SmTable(model, "Functions") == "first=NSharpLang.Compiler.FunctionTypeInfo;second=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == "3:10=int;3:11=int;7:10=string;7:11=string;"
    assert SmTypeReferenceTypes(model) == "2:15=int;6:16=string;"
    assert SmScopeCount(model) == 5
    assert SmScopes(model) == "0<-1|1:1-7:2147483647|v=|f=;1<0|2:1-3:2147483647|v=x=int;|f=first=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:20-3:2147483647|v=|f=;3<0|6:1-7:2147483647|v=x=string;|f=second=NSharpLang.Compiler.FunctionTypeInfo;;4<3|6:24-7:2147483647|v=|f=;"
    assert SmLookupIdentifierAtPosition(model, "x", 3, 5) == "int"
    assert SmLookupIdentifierAtPosition(model, "x", 7, 5) == "string"
}

// WHAT THIS ADDS: The deleted method asserted both. This adds that the `Types` table stores the
// generic record under the bare name `Box`, and that its field `Value` is recorded with the
// unsubstituted `T`.
test "020 s26 analyzer semantic model: a constructed generic type reference and its ARGUMENT are two separate rows at two columns (was AnalyzerSemanticModelTests.Analyzer_TypeReferencePositions_RecordResolvedTypes)" {
    source := "\nrecord Person {\n    Name: string\n}\n\nrecord Box<T> {\n    Value: T\n}\n\nfunc use(box: Box<Person>) {\n}"
    assert source.Length == 99
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "box=Box<Person>;"
    assert SmTable(model, "Functions") == "use=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == "Name=string;Value=T;"
    assert SmTable(model, "Types") == "Box=Box;Person=Person;"
    assert SmTypeMembers(model) == "Box{Value=T;};Person{Name=string;};"
    assert SmExpressionTypes(model) == ""
    assert SmTypeReferenceTypes(model) == "3:11=string;7:12=T;10:15=Box<Person>;10:19=Person;"
    assert SmScopeCount(model) == 5
    assert SmScopes(model) == "0<-1|1:1-10:2147483647|v=|f=;1<0|2:1-2:2147483647|v=|f=;2<0|6:1-6:2147483647|v=|f=;3<0|10:1-10:2147483647|v=box=Box<Person>;|f=use=NSharpLang.Compiler.FunctionTypeInfo;;4<3|10:28-10:2147483647|v=|f=;"
    assert SmLookupTypeReferenceAtPosition(model, 10, 15) == "Box<Person>"
    assert SmLookupTypeReferenceAtPosition(model, 10, 19) == "Person"
}

// WHAT THIS ADDS: The deleted method asserted the row at 2:17. Pinning the whole table proves there is
// no SECOND row: the wrapper is recorded once, at the column the inner type name starts on.
test "020 s26 analyzer semantic model: a wrapped `int?[]` annotation records ONE row, at the type's START, and no row for the inner `int` (was AnalyzerSemanticModelTests.Analyzer_TypeReferencePositions_RecordWrappedResolvedTypeAtTypeStart)" {
    source := "\nfunc use(items: int?[]) {\n}"
    assert source.Length == 28
    assert SmParseCensus(source) == ""
    analysis := SmAnalyze(source)
    assert SmModelIsNull(analysis) == "no"
    model := SmModel(analysis)
    assert SmCensus(analysis) == ""
    assert SmHasErrors(analysis) == "False"
    assert SmTable(model, "Variables") == "items=int?[];"
    assert SmTable(model, "Functions") == "use=NSharpLang.Compiler.FunctionTypeInfo;"
    assert SmTable(model, "Properties") == ""
    assert SmTable(model, "Fields") == ""
    assert SmTable(model, "Types") == ""
    assert SmTypeMembers(model) == ""
    assert SmExpressionTypes(model) == ""
    assert SmTypeReferenceTypes(model) == "2:17=int?[];"
    assert SmScopeCount(model) == 3
    assert SmScopes(model) == "0<-1|1:1-2:2147483647|v=|f=;1<0|2:1-2:2147483647|v=items=int?[];|f=use=NSharpLang.Compiler.FunctionTypeInfo;;2<1|2:25-2:2147483647|v=|f=;"
    assert SmLookupTypeReferenceAtPosition(model, 2, 17) == "int?[]"
}
