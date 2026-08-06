namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT ITERATING A VALUE PRODUCES.
//
// Every member of this family was `private` in `Analyzer.cs`, so nothing named any of them: their
// behaviour was pinned only indirectly, through end-to-end `foreach` diagnostics. This is their first
// DIRECT pinning, and it is written around the three things the family is easy to get wrong.
//
// (1) THE SYNCHRONOUS/ASYNCHRONOUS SPLIT IS NOT SYMMETRIC. An array, a `string`, a `Span<T>`, the
// duck-typed enumerator pattern and the non-generic `IEnumerable` are SYNCHRONOUS-ONLY arms; asking
// them as an async sequence must answer nothing rather than answer anyway. Only the generic arm and
// the reflected interface probe have an async shape at all.
//
// (2) THE METADATA LOAD CONTEXT SPLITS THE REFLECTION ARMS IN HALF, and the split is behaviour rather
// than a bug. The array arm and the `Span`/`ReadOnlySpan` arm are STRUCTURAL or NAME-based, so they
// answer for a type loaded into the analyzer's MetadataLoadContext exactly as they do for its runtime
// twin. The interface probe, the duck-typed pattern and the non-generic fallback all compare RUNTIME
// IDENTITIES — `GetGenericTypeDefinition() == typeof(IEnumerable<>)`, `MoveNext().ReturnType ==
// typeof(bool)`, `typeof(IEnumerable).IsAssignableFrom(...)` — and a metadata type is a different
// object from its runtime twin, so all three answer NO. `Analyzer.cs` behaved this way; these
// contracts pin it so that a later "simplification" to name comparison is a red test rather than a
// silent change in which loops compile.
//
// (3) THE `yield` WALK READS BOTH ESCAPE ANSWERS. Each escape report returns a boolean the walk uses
// to SILENCE the element-type rule. The reports are `AnalyzerSoaEscape`'s and are called directly —
// they were the driver's kinds 2 and 3 until that family moved — so a contract that wants one to fire
// builds a REAL row view or a REAL declared-table column read rather than handing back a boolean.

// ── a runtime type that satisfies the duck-typed enumerator pattern ───────────
//
// Not an `IEnumerable` of any kind: a parameterless `GetEnumerator` whose return type carries a
// parameterless `bool MoveNext()` and a readable `Current`, which is the whole of the pattern.
class LoopProbeEnumerator {
    Current: int => 7

    func MoveNext(): bool {
        return false
    }
}

class LoopProbeSequence {
    func GetEnumerator(): LoopProbeEnumerator {
        return new LoopProbeEnumerator()
    }
}

// A type with a `GetEnumerator` whose enumerator has NO `MoveNext`, which must not satisfy the
// pattern — the probe checks the enumerator, not just the entry point.
class LoopProbeBrokenEnumerator {
    Current: int => 7
}

class LoopProbeBrokenSequence {
    func GetEnumerator(): LoopProbeBrokenEnumerator {
        return new LoopProbeBrokenEnumerator()
    }
}

class LoopHarness {
    Sequence: AnalyzerLoopSequence
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Errors: List<CompilerError>
    Assignability: AnalyzerAssignability
    Model: SemanticModel
    Narrowing: AnalyzerFlowNarrowing

    constructor(sequence: AnalyzerLoopSequence, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, errors: List<CompilerError>, assignability: AnalyzerAssignability, model: SemanticModel, narrowing: AnalyzerFlowNarrowing) {
        Sequence = sequence
        Ambient = ambient
        Scopes = scopes
        Errors = errors
        Assignability = assignability
        Model = model
        Narrowing = narrowing
    }
}

// One replayed step of the `yield` walk, with the error count AS THE STEP WAS HANDED OUT.
class LoopStep {
    Kind: int
    Node: Expression?
    Text: string?
    CarriedType: string
    ErrorsBefore: int

    constructor(kind: int, node: Expression?, text: string?, carriedType: string, errorsBefore: int) {
        Kind = kind
        Node = node
        Text = text
        CarriedType = carriedType
        ErrorsBefore = errorsBefore
    }
}

func LoopPath(): string {
    return Path.GetFullPath("loop-sequence-contract.nl")
}

func LoopHarnessWith(sourceText: string?): LoopHarness {
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    diagnostics.BeginAnalysis(LoopPath(), sourceText)
    spans := new AnalyzerDiagnosticSpans(diagnostics)
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, new List<string>(), new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, diagnostics, new Dictionary<string, string>(StringComparer.Ordinal), new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal), new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal), model, new BindingMap())
    resolver.BeginAnalysis(LoopPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    escape := new AnalyzerSoaEscape(diagnostics, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(diagnostics, spans, escape)
    conditions := new AnalyzerBooleanConditions(diagnostics, spans, escape)
    narrowing := new AnalyzerFlowNarrowing(scopes, resolver, assignability)
    sequence := new AnalyzerLoopSequence(diagnostics, spans, scopes, context, resolver, ambient, escape, conditions)
    return new LoopHarness(sequence, ambient, scopes, errors, assignability, model, narrowing)
}

func LoopDefault(): LoopHarness {
    return LoopHarnessWith(null)
}

func LoopTypeText(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    boxed := candidate as object
    rendered := boxed.ToString()
    if rendered != null {
        return rendered
    }

    return "<blank>"
}

func LoopElement(harness: LoopHarness, candidate: TypeInfo, requireAsync: bool): string {
    return LoopTypeText(harness.Sequence.GetLoopSequenceElementType(candidate, requireAsync))
}

func LoopReflected(clrType: Type): TypeInfo {
    reflected: TypeInfo = new ReflectionTypeInfo(clrType)
    return reflected
}

func LoopTypeArgs(argument: TypeInfo): List<TypeInfo> {
    arguments := new List<TypeInfo>()
    arguments.Add(argument)
    return arguments
}

func LoopGeneric(name: string, argument: TypeInfo): TypeInfo {
    generic: TypeInfo = new GenericTypeInfo(name, LoopTypeArgs(argument))
    return generic
}

func LoopCollection(): Expression {
    return new IdentifierExpression("values", 4, 14)
}

func LoopYield(value: Expression?): YieldStatement {
    return new YieldStatement(value, 6, 5)
}

func LoopValue(): Expression {
    return new IntLiteralExpression("1", 6, 11)
}

func LoopFunction(name: string, returnType: TypeReference?, modifiers: Modifiers): FunctionDeclaration {
    return new FunctionDeclaration(name, new List<Parameter>(), returnType, null, null, null, null, modifiers, new List<AttributeNode>(), false, null, false, false, 3, 1)
}

func LoopErrorText(harness: LoopHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString() + "+" + error.Length.ToString()
}

// ── the `yield` driver, exactly as `Analyzer.cs` writes it ────────────────────
//
// It asks for ONE thing now. Kinds 2 and 3 were the two SoA escape reports, which the walk performs
// itself against the real `AnalyzerSoaEscape` — so a contract that wants an escape to FIRE supplies a
// row-view TYPE or yields a real column read, rather than handing the walk a boolean.
func LoopRunYield(harness: LoopHarness, statement: YieldStatement, answer: TypeInfo?): List<LoopStep> {
    steps := new List<LoopStep>()
    state := harness.Sequence.BeginYield(statement, harness.Assignability)
    step := harness.Sequence.NextStep(state)
    while step != null {
        steps.Add(new LoopStep(step.Kind, step.Node, step.Text, LoopTypeText(step.CarriedType), harness.Errors.Count))

        harness.Sequence.Supply(state, answer)
        step = harness.Sequence.NextStep(state)
    }

    return steps
}

// A table declared in the harness's scope, and a `points.x` read against it — the only way to make
// the direct-column escape fire for real.
func LoopSoaColumns(): List<SoaColumnInfo> {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo("x", new SimpleTypeReference("int", 0, 0), 1, 1))
    return columns
}

func LoopSoaDeclaration(): SoaRecordDeclarationInfo {
    return new SoaRecordDeclarationInfo("Points", LoopSoaColumns(), 1, 1)
}

func LoopSoaRowType(): TypeInfo {
    row: TypeInfo = new SoaRowTypeInfo(LoopSoaDeclaration())
    return row
}

func LoopDeclareSoaTable(harness: LoopHarness) {
    table: TypeInfo = new SoaRecordTypeInfo(LoopSoaDeclaration())
    harness.Scopes.Peek().Symbols["points"] = table
}

func LoopSoaColumnRead(): Expression {
    read: Expression = new MemberAccessExpression(new IdentifierExpression("points", 6, 11), "x", false, 6, 11)
    return read
}

func LoopText(value: string?): string {
    if value == null {
        return "<null>"
    }

    return value
}

func LoopKinds(steps: List<LoopStep>): string {
    rendered := ""
    index := 0
    while index < steps.Count {
        if index > 0 {
            rendered = rendered + ","
        }

        rendered = rendered + steps[index].Kind.ToString()
        index = index + 1
    }

    return rendered
}

// ── the declared arms ─────────────────────────────────────────────────────────

test "AN ARRAY ANSWERS ITS ELEMENT TYPE, AND ONLY FOR A SYNCHRONOUS LOOP" {
    harness := LoopDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    assert LoopElement(harness, arrayType, false) == "int"
    assert LoopElement(harness, arrayType, true) == "<null>"
}

test "A string ANSWERS char, AND ONLY FOR A SYNCHRONOUS LOOP" {
    harness := LoopDefault()
    stringType: TypeInfo = BuiltInTypes.String

    assert LoopElement(harness, stringType, false) == "char"
    assert LoopElement(harness, stringType, true) == "<null>"
}

test "A SIMPLE TYPE THAT IS NOT string ANSWERS NOTHING IN EITHER MODE" {
    harness := LoopDefault()
    intType: TypeInfo = BuiltInTypes.Int

    assert LoopElement(harness, intType, false) == "<null>"
    assert LoopElement(harness, intType, true) == "<null>"
}

test "A DECLARED GENERIC ANSWERS THROUGH THE NAME-BASED SEQUENCE FACTS" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopGeneric("List", BuiltInTypes.Int), false) == "int"
    assert LoopElement(harness, LoopGeneric("IEnumerable", BuiltInTypes.String), false) == "string"
    assert LoopElement(harness, LoopGeneric("Queue", BuiltInTypes.Bool), false) == "bool"
}

test "THE ASYNC QUESTION IS ANSWERED BY IAsyncEnumerable AND BY NOTHING ELSE" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopGeneric("IAsyncEnumerable", BuiltInTypes.Int), true) == "int"
    assert LoopElement(harness, LoopGeneric("IAsyncEnumerable", BuiltInTypes.Int), false) == "<null>"
    assert LoopElement(harness, LoopGeneric("List", BuiltInTypes.Int), true) == "<null>"
}

test "A DECLARED CLASS ANSWERS THROUGH THE INTERFACES IT NAMES, IN DECLARATION ORDER" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopDeclaredSequenceClass(), false) == "int"
    assert LoopElement(harness, LoopDeclaredSequenceClass(), true) == "<null>"
}

test "A DECLARED INTERFACE ANSWERS THROUGH THE INTERFACES IT INHERITS" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopDeclaredSequenceInterface(), false) == "int"
    assert LoopElement(harness, LoopDeclaredSequenceInterface(), true) == "<null>"
}

test "A DECLARED CLASS THAT NAMES NO SEQUENCE ANSWERS NOTHING" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopDeclaredPlainClass(), false) == "<null>"
}

func LoopIntArgument(): List<TypeReference> {
    arguments := new List<TypeReference>()
    argument: TypeReference = new SimpleTypeReference("int", 1, 1)
    arguments.Add(argument)
    return arguments
}

// A declared class whose SECOND interface is the sequence one, so the walk is proven to keep going
// past an interface that answers nothing.
func LoopSequenceInterfaces(): TypeReference[] {
    interfaces := new TypeReference[](2)
    disposable: TypeReference = new SimpleTypeReference("IDisposable", 1, 1)
    sequence: TypeReference = new GenericTypeReference("IEnumerable", LoopIntArgument(), 1, 1)
    interfaces[0] = disposable
    interfaces[1] = sequence
    return interfaces
}

func LoopDeclaredSequenceClass(): TypeInfo {
    declared: TypeInfo = new ClassTypeInfo("Bag", 1, 1, false, null, LoopSequenceInterfaces(), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
    return declared
}

func LoopDeclaredPlainClass(): TypeInfo {
    declared: TypeInfo = new ClassTypeInfo("Plain", 1, 1, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
    return declared
}

func LoopDeclaredSequenceInterface(): TypeInfo {
    declared: TypeInfo = new InterfaceTypeInfo("IBag", 1, 1, false, LoopSequenceInterfaces(), new TypeParameter[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    return declared
}

// ── the shape normaliser ──────────────────────────────────────────────────────

test "THE SHAPE NORMALISER UNWRAPS nullable, oblivious AND ref TO A FIXED POINT" {
    harness := LoopDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new NullableTypeInfo(arrayType))) == "int[]"
    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new ObliviousTypeInfo(arrayType))) == "int[]"
    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new ByRefTypeInfo(arrayType))) == "int[]"
    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new ObliviousTypeInfo(new ByRefTypeInfo(new NullableTypeInfo(arrayType))))) == "int[]"
}

test "A NULLABLE, oblivious OR ref SEQUENCE STILL ANSWERS ITS ELEMENT TYPE" {
    harness := LoopDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    assert LoopElement(harness, new NullableTypeInfo(arrayType), false) == "int"
    assert LoopElement(harness, new ObliviousTypeInfo(arrayType), false) == "int"
    assert LoopElement(harness, new ByRefTypeInfo(arrayType), false) == "int"
}

test "A SIMPLE NAME IS REPLACED BY WHAT THE SCOPE STACK SAYS IT DECLARES" {
    harness := LoopDefault()
    declared: TypeInfo = new ArrayTypeInfo(BuiltInTypes.String)
    harness.Scopes.Peek().Types["Names"] = declared

    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new SimpleTypeInfo("Names"))) == "string[]"
    assert LoopElement(harness, new SimpleTypeInfo("Names"), false) == "string"
}

test "A NAME THE SCOPE STACK DOES NOT KNOW IS ITS OWN ANSWER" {
    harness := LoopDefault()

    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new SimpleTypeInfo("Missing"))) == "Missing"
}

// ── the reflected probes, over RUNTIME types ─────────────────────────────────

test "A REFLECTED ARRAY ANSWERS ITS ELEMENT TYPE, SYNCHRONOUSLY ONLY" {
    harness := LoopDefault()
    arrayType := LoopReflected(typeof(int[]))

    assert LoopElement(harness, arrayType, false) == "int"
    assert LoopElement(harness, arrayType, true) == "<null>"
}

test "A REFLECTED Span AND ReadOnlySpan ANSWER BY DEFINITION NAME" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopReflected(typeof(Span<byte>)), false) == "byte"
    assert LoopElement(harness, LoopReflected(typeof(ReadOnlySpan<byte>)), false) == "byte"
    assert LoopElement(harness, LoopReflected(typeof(Span<byte>)), true) == "<null>"
}

test "A REFLECTED GENERIC SEQUENCE ANSWERS THROUGH THE INTERFACE PROBE" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopReflected(typeof(List<string>)), false) == "string"
    assert LoopElement(harness, LoopReflected(typeof(IEnumerable<int>)), false) == "int"
    assert LoopElement(harness, LoopReflected(typeof(string)), false) == "char"
}

test "A REFLECTED ASYNC SEQUENCE ANSWERS ONLY THE ASYNC QUESTION" {
    harness := LoopDefault()
    asyncSequence := LoopReflected(LoopClose(LoopAsyncSequenceDefinition(), typeof(int)))

    assert LoopElement(harness, asyncSequence, true) == "int"
    assert LoopElement(harness, asyncSequence, false) == "<null>"
    assert LoopElement(harness, LoopReflected(typeof(List<string>)), true) == "<null>"
}

test "A REFLECTED NULLABLE VALUE TYPE IS UNWRAPPED BEFORE THE PROBES RUN" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopReflected(typeof(int?)), false) == "<null>"
    assert LoopElement(harness, LoopReflected(typeof(int)), false) == "<null>"
}

test "THE DUCK-TYPED ENUMERATOR PATTERN ANSWERS Current's TYPE" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopReflected(typeof(LoopProbeSequence)), false) == "int"
    assert LoopElement(harness, LoopReflected(typeof(LoopProbeSequence)), true) == "<null>"
}

test "AN ENUMERATOR WITHOUT MoveNext DOES NOT SATISFY THE PATTERN" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopReflected(typeof(LoopProbeBrokenSequence)), false) == "<null>"
}

test "A NON-GENERIC IEnumerable FALLS BACK TO object" {
    harness := LoopDefault()

    assert LoopElement(harness, LoopReflected(LoopArrayListType()), false) == "object"
    assert LoopElement(harness, LoopReflected(LoopArrayListType()), true) == "<null>"
}

// ── the MetadataLoadContext dimension ────────────────────────────────────────

test "A METADATA ARRAY AND SPAN STILL ANSWER — THOSE ARMS ARE STRUCTURAL AND NAME-BASED" {
    harness := LoopDefault()
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        core := context.LoadFromAssemblyName("System.Runtime")
        metadataInt := core.GetType("System.Int32")
        assert metadataInt != null
        assert metadataInt != typeof(int)

        assert LoopElement(harness, LoopReflected(metadataInt.MakeArrayType()), false) == "int"

        metadataSpan := core.GetType("System.Span`1")
        assert metadataSpan != null
        assert LoopElement(harness, LoopReflected(LoopClose(metadataSpan, metadataInt)), false) == "int"
    } finally {
        scan.Dispose()
    }
}

test "A METADATA SEQUENCE ANSWERS NOTHING — ALL THREE REMAINING ARMS COMPARE RUNTIME IDENTITIES" {
    harness := LoopDefault()
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        context := scan.Context
        assert context != null
        core := context.LoadFromAssemblyName("System.Runtime")
        metadataInt := core.GetType("System.Int32")
        assert metadataInt != null

        // The interface probe: the metadata `IEnumerable<>` is a different OBJECT from the runtime
        // one, so `GetGenericTypeDefinition() == typeof(IEnumerable<>)` is false even though this IS
        // the sequence interface. Its runtime twin answers `int`.
        metadataSequence := core.GetType("System.Collections.Generic.IEnumerable`1")
        assert metadataSequence != null
        assert metadataSequence != typeof(IEnumerable<int>).GetGenericTypeDefinition()
        assert LoopElement(harness, LoopReflected(LoopClose(metadataSequence, metadataInt)), false) == "<null>"
        assert LoopElement(harness, LoopReflected(typeof(IEnumerable<int>)), false) == "int"

        // The duck-typed pattern and the non-generic fallback: the metadata `IEnumerable` declares a
        // parameterless `GetEnumerator`, but its enumerator's `MoveNext` returns the metadata
        // `Boolean` rather than `typeof(bool)`, and `typeof(IEnumerable).IsAssignableFrom` cannot see
        // across the load context either. This is the slice-12B failure mode exactly.
        metadataEnumerable := core.GetType("System.Collections.IEnumerable")
        assert metadataEnumerable != null
        assert LoopElement(harness, LoopReflected(metadataEnumerable), false) == "<null>"
        assert LoopElement(harness, LoopReflected(LoopArrayListType()), false) == "object"

        // And the metadata `string` — a runtime `string` answers `char` through the interface probe.
        metadataString := core.GetType("System.String")
        assert metadataString != null
        assert LoopElement(harness, LoopReflected(metadataString), false) == "<null>"
        assert LoopElement(harness, LoopReflected(typeof(string)), false) == "char"
    } finally {
        scan.Dispose()
    }
}

// The two runtime identities the contracts cannot spell as `typeof`, for the reason the owner
// records: the pinned toolset declines `typeof` on `IAsyncEnumerable<T>` and on the non-generic
// collection types.
func LoopAsyncSequenceDefinition(): Type {
    definition := Type.GetType("System.Collections.Generic.IAsyncEnumerable`1")
    if definition == null {
        throw new InvalidOperationException("System.Collections.Generic.IAsyncEnumerable`1 was not found.")
    }

    return definition
}

func LoopArrayListType(): Type {
    found := Type.GetType("System.Collections.ArrayList")
    if found == null {
        throw new InvalidOperationException("System.Collections.ArrayList was not found.")
    }

    return found
}

func LoopClose(definition: Type, argument: Type): Type {
    arguments := new Type[](1)
    arguments[0] = argument
    return definition.MakeGenericType(arguments)
}

// ── whether a failure is worth reporting ─────────────────────────────────────

test "AN UNKNOWN OR STILL-EXTERNAL COLLECTION IS NOT REPORTED; ANYTHING ELSE IS" {
    harness := LoopDefault()

    assert !harness.Sequence.ShouldReportLoopSequenceTypeMismatch(BuiltInTypes.Unknown)
    assert !harness.Sequence.ShouldReportLoopSequenceTypeMismatch(new ExternalTypeInfo("Widget"))
    assert harness.Sequence.ShouldReportLoopSequenceTypeMismatch(BuiltInTypes.Int)
    assert harness.Sequence.ShouldReportLoopSequenceTypeMismatch(new NullableTypeInfo(BuiltInTypes.Int))
}

// ── the two loop entries ─────────────────────────────────────────────────────

test "A foreach OVER A SEQUENCE ANSWERS THE ELEMENT TYPE AND REPORTS NOTHING" {
    harness := LoopDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    resolved := harness.Sequence.ResolveForeachElementType(LoopCollection(), arrayType)

    assert LoopTypeText(resolved) == "int"
    assert harness.Errors.Count == 0
}

test "A foreach OVER A NON-SEQUENCE ANSWERS unknown AND REPORTS AT THE COLLECTION" {
    harness := LoopDefault()

    resolved := harness.Sequence.ResolveForeachElementType(LoopCollection(), BuiltInTypes.Int)

    assert LoopTypeText(resolved) == "unknown"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "foreach collection must be enumerable, but this collection is 'int'|4:14+6"
    assert harness.Errors[0].Suggestion == "Use an array, Span<T>, or IEnumerable<T> value as the foreach collection."
}

test "AN await foreach OVER A SYNCHRONOUS SEQUENCE REPORTS THE ASYNC WORDING" {
    harness := LoopDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    resolved := harness.Sequence.ResolveAwaitForeachElementType(LoopCollection(), arrayType)

    assert LoopTypeText(resolved) == "unknown"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "await foreach collection must be async enumerable, but this collection is 'int[]'|4:14+6"
    assert harness.Errors[0].Suggestion == "Use an IAsyncEnumerable<T> value as the await foreach collection."
}

test "AN await foreach OVER AN ASYNC SEQUENCE ANSWERS THE ELEMENT TYPE" {
    harness := LoopDefault()

    resolved := harness.Sequence.ResolveAwaitForeachElementType(LoopCollection(), LoopGeneric("IAsyncEnumerable", BuiltInTypes.String))

    assert LoopTypeText(resolved) == "string"
    assert harness.Errors.Count == 0
}

test "AN UNKNOWN COLLECTION ANSWERS unknown SILENTLY IN BOTH LOOPS" {
    harness := LoopDefault()

    assert LoopTypeText(harness.Sequence.ResolveForeachElementType(LoopCollection(), BuiltInTypes.Unknown)) == "unknown"
    assert LoopTypeText(harness.Sequence.ResolveAwaitForeachElementType(LoopCollection(), BuiltInTypes.Unknown)) == "unknown"
    assert harness.Errors.Count == 0
}

// ── the generator façade ─────────────────────────────────────────────────────

test "THE GENERATOR ELEMENT TYPE FOLLOWS THE ENCLOSING FUNCTION'S async MODIFIER" {
    harness := LoopDefault()
    syncSequence := LoopGeneric("IEnumerable", BuiltInTypes.Int)
    asyncSequence := LoopGeneric("IAsyncEnumerable", BuiltInTypes.Int)

    harness.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), BuiltInTypes.Unknown)

    assert LoopTypeText(harness.Sequence.GetGeneratorYieldElementType(syncSequence)) == "int"
    assert LoopTypeText(harness.Sequence.GetGeneratorYieldElementType(asyncSequence)) == "<null>"

    harness.Ambient.EnterFunctionDeclaration(LoopFunction("h", null, Modifiers.Generator | Modifiers.Async), BuiltInTypes.Unknown)

    assert LoopTypeText(harness.Sequence.GetGeneratorYieldElementType(asyncSequence)) == "int"
    assert LoopTypeText(harness.Sequence.GetGeneratorYieldElementType(syncSequence)) == "<null>"
}

// ── the `yield` walk ─────────────────────────────────────────────────────────

test "A BARE yield ASKS FOR NOTHING" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))

    steps := LoopRunYield(harness, LoopYield(null), null)

    assert LoopKinds(steps) == ""
    assert harness.Errors.Count == 0
}

test "A yield WITH A VALUE ASKS FOR THE WALK AND NOTHING ELSE" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))

    steps := LoopRunYield(harness, LoopYield(LoopValue()), BuiltInTypes.Int)

    // The two escape reports were kinds 2 and 3 and are N#-owned calls now.
    assert LoopKinds(steps) == "1"
    assert LoopText(steps[0].Text) == "<null>"
    assert steps[0].CarriedType == "unknown"
    assert harness.Errors.Count == 0
}

test "A yield OUTSIDE A GENERATOR IS REPORTED AT THE KEYWORD, AND THE VALUE IS STILL WALKED" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(LoopFunction("f", null, Modifiers.None), BuiltInTypes.Int)

    steps := LoopRunYield(harness, LoopYield(LoopValue()), BuiltInTypes.String)

    assert LoopKinds(steps) == "1"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "'yield' can only be used inside a generator function|6:5+5"
    // The element-type rule is silent for a non-generator: it has already been told what is wrong.
    assert steps[0].ErrorsBefore == 1
}

test "A yield OF THE WRONG TYPE IS REPORTED AT THE VALUE, WITH BOTH TYPES IN THE WORDING" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))

    LoopRunYield(harness, LoopYield(LoopValue()), BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "Generator yield value is 'string', but the sequence element type is 'int'|6:11+1"
    assert harness.Errors[0].Suggestion == "Yield a value assignable to 'int', or change the generator return type."
}

test "EITHER ESCAPE SILENCES THE ELEMENT-TYPE RULE, AND SPEAKS IN ITS PLACE" {
    // A yielded ROW VIEW: the row escape fires on the answered type, and the mismatch that would
    // otherwise follow (a row view is not an `int`) never speaks.
    rowHarness := LoopDefault()
    rowHarness.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))
    LoopRunYield(rowHarness, LoopYield(LoopValue()), LoopSoaRowType())
    assert rowHarness.Errors.Count == 1
    assert rowHarness.Errors[0].Message == "SoA row views cannot be yielded; use the table and row index instead"

    // A yielded DIRECT COLUMN: decided by the SYNTAX of the value, not by its type, so the answered
    // type is an ordinary mismatching one and the mismatch still does not speak.
    columnHarness := LoopDefault()
    columnHarness.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))
    LoopDeclareSoaTable(columnHarness)
    LoopRunYield(columnHarness, LoopYield(LoopSoaColumnRead()), BuiltInTypes.String)
    assert columnHarness.Errors.Count == 1
    assert columnHarness.Errors[0].Message == "SoA table member 'x' cannot be yielded directly"
}

test "A yield WHOSE VALUE FITS, OR WHOSE SEQUENCE IS UNNAMEABLE, IS SILENT" {
    fitting := LoopDefault()
    fitting.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))
    LoopRunYield(fitting, LoopYield(LoopValue()), BuiltInTypes.Int)
    assert fitting.Errors.Count == 0

    // A return type that names no sequence at all: a different error, reported elsewhere.
    unnameable := LoopDefault()
    unnameable.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), BuiltInTypes.Int)
    LoopRunYield(unnameable, LoopYield(LoopValue()), BuiltInTypes.String)
    assert unnameable.Errors.Count == 0

    // An unknown on either side would make the wording meaningless.
    unknownValue := LoopDefault()
    unknownValue.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))
    LoopRunYield(unknownValue, LoopYield(LoopValue()), BuiltInTypes.Unknown)
    assert unknownValue.Errors.Count == 0
}

test "A yield WITH NO ENCLOSING FUNCTION AT ALL REPORTS ONLY THE GENERATOR RULE" {
    harness := LoopDefault()

    steps := LoopRunYield(harness, LoopYield(LoopValue()), BuiltInTypes.String)

    assert LoopKinds(steps) == "1"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "'yield' can only be used inside a generator function|6:5+5"
}

test "AN UNANSWERED VALUE WALK LEAVES THE YIELDED TYPE unknown RATHER THAN NULL" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))

    steps := LoopRunYield(harness, LoopYield(LoopValue()), null)

    assert LoopKinds(steps) == "1"
    // An unanswered walk leaves `unknown`, which silences the rule rather than reporting nonsense.
    assert harness.Errors.Count == 0
}

// ── the `foreach` / `await foreach` walk ─────────────────────────────────────
//
// These two statements were the LAST `Analyzer.cs` arms in this territory. Their contracts are
// written around the four things the pair is easy to get wrong: the six-step ORDER (the collection
// is asked for before the scope opens, and the loop closes before the scope does), the fact that the
// two arms differ ONLY in a mode flag and therefore must not drift apart, the escape→`unknown`
// collapse that keeps one bad collection to ONE diagnostic, and the body step being a single
// STATEMENT rather than the statement LIST the expression-statement family asks for.
class LoopDriverStep {
    Kind: int
    Node: Expression?
    Body: Statement?
    Name: string?
    CarriedType: string
    Line: int
    Column: int
    InLoop: bool
    ErrorsBefore: int

    constructor(kind: int, node: Expression?, body: Statement?, name: string?, carriedType: string, line: int, column: int, inLoop: bool, errorsBefore: int) {
        Kind = kind
        Node = node
        Body = body
        Name = name
        CarriedType = carriedType
        Line = line
        Column = column
        InLoop = inLoop
        ErrorsBefore = errorsBefore
    }
}

// The foreach driver, exactly as `Analyzer.cs` writes it, with the ambient loop flag sampled at
// every step so that the loop's open/close window is pinned rather than assumed.
func LoopRun(harness: LoopHarness, state: LoopStatementState, answer: TypeInfo?): List<LoopDriverStep> {
    steps := new List<LoopDriverStep>()
    step := harness.Sequence.NextLoopStep(state)
    while step != null {
        steps.Add(new LoopDriverStep(step.Kind, step.Node, step.Body, step.Name, LoopTypeText(step.CarriedType), step.Line, step.Column, harness.Ambient.InLoop, harness.Errors.Count))

        harness.Sequence.SupplyLoop(state, answer)
        step = harness.Sequence.NextLoopStep(state)
    }

    return steps
}

func LoopStepKinds(steps: List<LoopDriverStep>): string {
    rendered := ""
    index := 0
    while index < steps.Count {
        if index > 0 {
            rendered = rendered + ","
        }

        rendered = rendered + steps[index].Kind.ToString()
        index = index + 1
    }

    return rendered
}

func LoopForeachBody(): Statement {
    body: Statement = new BlockStatement(new List<Statement>(), 7, 9)
    return body
}

func LoopForeachOver(collection: Expression, body: Statement): ForeachStatement {
    return new ForeachStatement("item", collection, body, 6, 5)
}

func LoopAwaitForeachOver(collection: Expression, body: Statement): AwaitForEachStatement {
    return new AwaitForEachStatement("item", collection, body, 6, 5)
}

func LoopArrayOf(element: TypeInfo): TypeInfo {
    arrayType: TypeInfo = new ArrayTypeInfo(element)
    return arrayType
}

test "A foreach ASKS FOR SIX STEPS IN ONE FIXED ORDER" {
    harness := LoopDefault()
    state := harness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), LoopForeachBody()))

    steps := LoopRun(harness, state, LoopArrayOf(BuiltInTypes.Int))

    assert LoopStepKinds(steps) == "1,2,3,4,5,6"
    assert harness.Errors.Count == 0
}

test "AN await foreach ASKS FOR THE SAME SIX STEPS — THE ARMS DIFFER ONLY IN A MODE FLAG" {
    harness := LoopDefault()
    state := harness.Sequence.BeginAwaitForeach(LoopAwaitForeachOver(LoopCollection(), LoopForeachBody()))

    steps := LoopRun(harness, state, LoopGeneric("IAsyncEnumerable", BuiltInTypes.String))

    assert LoopStepKinds(steps) == "1,2,3,4,5,6"
    assert steps[2].CarriedType == "string"
    assert harness.Errors.Count == 0
}

test "THE COLLECTION IS ASKED FOR BEFORE THE SCOPE OPENS, AND THE SCOPE OPENS AT THE STATEMENT" {
    harness := LoopDefault()
    collection := LoopCollection()
    state := harness.Sequence.BeginForeach(LoopForeachOver(collection, LoopForeachBody()))

    steps := LoopRun(harness, state, LoopArrayOf(BuiltInTypes.Int))

    // Step 1 carries the collection node itself, and NOTHING has opened yet.
    assert Object.ReferenceEquals(steps[0].Node, collection)
    assert steps[0].CarriedType == "unknown"
    // Step 2 is the scope, at the STATEMENT's position rather than the collection's or the body's.
    assert steps[1].Line == 6
    assert steps[1].Column == 5
    assert LoopText(steps[1].Name) == "<null>"
}

test "THE LOOP VARIABLE IS DECLARED THEN RECORDED, BOTH WITH THE ELEMENT TYPE" {
    harness := LoopDefault()
    state := harness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), LoopForeachBody()))

    steps := LoopRun(harness, state, LoopArrayOf(BuiltInTypes.String))

    assert LoopText(steps[2].Name) == "item"
    assert steps[2].CarriedType == "string"
    // The declaration carries the statement's position; the semantic-model write does not need one.
    assert steps[2].Line == 6
    assert steps[2].Column == 5
    assert LoopText(steps[3].Name) == "item"
    assert steps[3].CarriedType == "string"
    assert steps[3].Line == 0
    assert steps[3].Column == 0
}

test "THE BODY STEP CARRIES THE STATEMENT ITSELF, NOT A LIST AND NOT AN EXPRESSION" {
    harness := LoopDefault()
    body := LoopForeachBody()
    state := harness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), body))

    steps := LoopRun(harness, state, LoopArrayOf(BuiltInTypes.Int))

    assert Object.ReferenceEquals(steps[4].Body, body)
    assert steps[4].Node == null
}

test "THE LOOP IS OPEN FOR THE BODY STEP ALONE, AND CLOSED BEFORE THE SCOPE" {
    harness := LoopDefault()
    state := harness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), LoopForeachBody()))

    steps := LoopRun(harness, state, LoopArrayOf(BuiltInTypes.Int))

    // The collection is NOT inside the loop: a `break` written in it is as illegal as one outside.
    assert !steps[0].InLoop
    assert !steps[1].InLoop
    assert !steps[2].InLoop
    assert !steps[3].InLoop
    assert steps[4].InLoop
    // The loop closes BEFORE the scope does, which is the order `Analyzer.cs` used.
    assert !steps[5].InLoop
    assert !harness.Ambient.InLoop
}

test "A NON-SEQUENCE COLLECTION REPORTS ONCE AND STILL DECLARES THE VARIABLE AS unknown" {
    harness := LoopDefault()
    state := harness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), LoopForeachBody()))

    steps := LoopRun(harness, state, BuiltInTypes.Int)

    assert LoopStepKinds(steps) == "1,2,3,4,5,6"
    assert steps[2].CarriedType == "unknown"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "foreach collection must be enumerable, but this collection is 'int'|4:14+6"
    // The report is already in the list by the time the scope opens.
    assert steps[1].ErrorsBefore == 1
}

test "AN await foreach OVER A SYNCHRONOUS SEQUENCE REPORTS THE ASYNC WORDING FROM THE ARM" {
    harness := LoopDefault()
    state := harness.Sequence.BeginAwaitForeach(LoopAwaitForeachOver(LoopCollection(), LoopForeachBody()))

    steps := LoopRun(harness, state, LoopArrayOf(BuiltInTypes.Int))

    assert steps[2].CarriedType == "unknown"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "await foreach collection must be async enumerable, but this collection is 'int[]'|4:14+6"
}

test "A ROW-VIEW COLLECTION ESCAPES, COLLAPSES TO unknown, AND SPEAKS WITH THE ARM'S ACTION WORD" {
    // The SYNCHRONOUS arm.
    syncHarness := LoopDefault()
    syncState := syncHarness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), LoopForeachBody()))
    syncSteps := LoopRun(syncHarness, syncState, LoopSoaRowType())
    assert syncSteps[2].CarriedType == "unknown"
    // ONE diagnostic, not two: the collapse is what silences the element-type mismatch.
    assert syncHarness.Errors.Count == 1
    assert syncHarness.Errors[0].Message == "SoA row views cannot be used as a foreach collection; use the table and row index instead"

    // The ASYNCHRONOUS arm, whose only difference is the action word.
    asyncHarness := LoopDefault()
    asyncState := asyncHarness.Sequence.BeginAwaitForeach(LoopAwaitForeachOver(LoopCollection(), LoopForeachBody()))
    asyncSteps := LoopRun(asyncHarness, asyncState, LoopSoaRowType())
    assert asyncSteps[2].CarriedType == "unknown"
    assert asyncHarness.Errors.Count == 1
    assert asyncHarness.Errors[0].Message == "SoA row views cannot be used as an async foreach collection; use the table and row index instead"
}

test "A DIRECT COLUMN COLLECTION ESCAPES ON SYNTAX, COLLAPSES, AND KEEPS THE ARM'S ACTION WORD" {
    // Decided by the SYNTAX of the collection, not by its type — so the answered type is an ordinary
    // array that WOULD have iterated cleanly, and the escape is still what speaks.
    syncHarness := LoopDefault()
    LoopDeclareSoaTable(syncHarness)
    syncState := syncHarness.Sequence.BeginForeach(LoopForeachOver(LoopSoaColumnRead(), LoopForeachBody()))
    syncSteps := LoopRun(syncHarness, syncState, LoopArrayOf(BuiltInTypes.Int))
    assert syncSteps[2].CarriedType == "unknown"
    assert syncHarness.Errors.Count == 1
    assert syncHarness.Errors[0].Message == "SoA table member 'x' cannot be used as a foreach collection directly"

    asyncHarness := LoopDefault()
    LoopDeclareSoaTable(asyncHarness)
    asyncState := asyncHarness.Sequence.BeginAwaitForeach(LoopAwaitForeachOver(LoopSoaColumnRead(), LoopForeachBody()))
    asyncSteps := LoopRun(asyncHarness, asyncState, LoopArrayOf(BuiltInTypes.Int))
    assert asyncSteps[2].CarriedType == "unknown"
    assert asyncHarness.Errors.Count == 1
    assert asyncHarness.Errors[0].Message == "SoA table member 'x' cannot be used as an async foreach collection directly"
}

test "AN UNANSWERED COLLECTION WALK LEAVES THE TYPE unknown AND STAYS SILENT" {
    harness := LoopDefault()
    state := harness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), LoopForeachBody()))

    steps := LoopRun(harness, state, null)

    assert LoopStepKinds(steps) == "1,2,3,4,5,6"
    assert steps[2].CarriedType == "unknown"
    // An unknown collection is not worth reporting — it already carries whatever made it unknown.
    assert harness.Errors.Count == 0
}

test "THE WALK'S STATE CARRIES THE OPERANDS, NOT THE NODE — THE TWO ARMS SHARE ONE STATE TYPE" {
    harness := LoopDefault()
    syncState := harness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), LoopForeachBody()))
    asyncState := harness.Sequence.BeginAwaitForeach(LoopAwaitForeachOver(LoopCollection(), LoopForeachBody()))

    assert !syncState.IsAsync
    assert asyncState.IsAsync
    assert syncState.VariableName == "item"
    assert syncState.Line == 6
    assert syncState.Column == 5
    // Nothing has run yet, so neither the loop nor the types have moved.
    assert syncState.LoopFrame == null
    assert LoopTypeText(syncState.CollectionType) == "unknown"
    assert LoopTypeText(syncState.ElementType) == "unknown"
}

// ── `while` AND `for` ─────────────────────────────────────────────────────────
//
// The two condition loops share the request type, the state and the driver with the two iteration
// loops, and the contracts below are written around the FIVE things that sharing makes easy to get
// wrong: that a condition-shaped clause is OPTIONAL for `for` and mandatory for `while`, that the
// narrowing scope exists only when the condition actually proved something, that the ambient loop is
// open for the BODY and for nothing else, that `for`'s outer scope opens at the KEYWORD and closes
// LAST, and that the iterator is a NESTED walk rather than a plain expression.

func LoopWhileOver(condition: Expression, body: Statement): WhileStatement {
    return new WhileStatement(condition, body, 6, 5)
}

func LoopForOver(initializer: Statement?, condition: Expression?, iterator: Expression?, body: Statement): ForStatement {
    return new ForStatement(initializer, condition, iterator, body, 6, 5)
}

// A condition that proves NOTHING — an ordinary identifier read.
func LoopPlainCondition(): Expression {
    plain: Expression = new IdentifierExpression("flag", 6, 11)
    return plain
}

// A condition that PROVES something: `value is int n` declares `n` in the then-branch, which is the
// shortest shape the narrowing extractor answers for without needing a symbol already in scope.
func LoopProvingCondition(): Expression {
    proving: Expression = new IsExpression(new IdentifierExpression("value", 6, 11), new SimpleTypeReference("int", 6, 20), "n", 6, 11)
    return proving
}

func LoopInitializer(): Statement {
    initializer: Statement = new VariableDeclarationStatement("i", null, new IntLiteralExpression("0", 6, 14), VariableKind.Let, 6, 9)
    return initializer
}

func LoopIterator(): Expression {
    iterator: Expression = new UnaryExpression(UnaryOperator.PostIncrement, new IdentifierExpression("i", 6, 30), 6, 30)
    return iterator
}

test "A while ASKS FOR TWO STEPS WHEN THE CONDITION PROVES NOTHING" {
    harness := LoopDefault()
    state := harness.Sequence.BeginWhile(LoopWhileOver(LoopPlainCondition(), LoopForeachBody()), harness.Narrowing)

    steps := LoopRun(harness, state, BuiltInTypes.Bool)

    // The condition, then the body. No scope, because there is nothing to put in one.
    assert LoopStepKinds(steps) == "1,5"
    assert harness.Errors.Count == 0
}

test "A while OPENS A NARROWING SCOPE ONLY WHEN THE CONDITION PROVED SOMETHING" {
    harness := LoopDefault()
    body := LoopForeachBody()
    state := harness.Sequence.BeginWhile(LoopWhileOver(LoopProvingCondition(), body), harness.Narrowing)

    steps := LoopRun(harness, state, BuiltInTypes.Bool)

    // Condition, scope, body, scope close.
    assert LoopStepKinds(steps) == "1,2,5,6"
    // The scope opens at the BODY's position, not at the `while` keyword's — a `while` has no scope
    // of its own to name.
    assert steps[1].Line == 7
    assert steps[1].Column == 9
    assert Object.ReferenceEquals(steps[2].Body, body)
}

test "A while's LOOP IS OPEN FOR THE BODY AND FOR NOTHING ELSE" {
    harness := LoopDefault()
    state := harness.Sequence.BeginWhile(LoopWhileOver(LoopProvingCondition(), LoopForeachBody()), harness.Narrowing)

    steps := LoopRun(harness, state, BuiltInTypes.Bool)

    // The CONDITION is not inside the loop: a `break` written in it is as illegal as one outside.
    assert !steps[0].InLoop
    // The narrowing scope opens after the loop does, so it and the body are both inside.
    assert steps[1].InLoop
    assert steps[2].InLoop
    // The scope closes BEFORE the loop, which is the order `Analyzer.cs` used.
    assert steps[3].InLoop
    assert !harness.Ambient.InLoop
}

test "A NON-BOOLEAN while CONDITION IS REPORTED BY THE WALK, UNDER THE while's OWN OWNER NAME" {
    harness := LoopDefault()
    state := harness.Sequence.BeginWhile(LoopWhileOver(LoopPlainCondition(), LoopForeachBody()), harness.Narrowing)

    steps := LoopRun(harness, state, BuiltInTypes.Int)

    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "The condition in a 'while' loop must be a boolean, but I found 'int'|6:11+4"
    // The report is in the list BEFORE the body runs, which is what an emission-order reader sees.
    assert steps[0].ErrorsBefore == 0
    assert steps[1].ErrorsBefore == 1
}

test "A ROW-VIEW while CONDITION IS TOLD ABOUT THE ESCAPE AND NOT ALSO TOLD IT IS NOT A BOOLEAN" {
    harness := LoopDefault()
    state := harness.Sequence.BeginWhile(LoopWhileOver(LoopPlainCondition(), LoopForeachBody()), harness.Narrowing)

    LoopRun(harness, state, LoopSoaRowType())

    // ONE diagnostic, not two — the escape silences the boolean question.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as a 'while' condition; use the table and row index instead"
}

test "A for WITH ALL THREE CLAUSES ASKS FOR EIGHT STEPS IN ONE FIXED ORDER" {
    harness := LoopDefault()
    state := harness.Sequence.BeginFor(LoopForOver(LoopInitializer(), LoopProvingCondition(), LoopIterator(), LoopForeachBody()), harness.Narrowing)

    steps := LoopRun(harness, state, BuiltInTypes.Bool)

    // Outer scope, initializer, condition, iterator, narrowing scope, body, narrowing close,
    // outer close.
    assert LoopStepKinds(steps) == "2,5,1,7,2,5,6,6"
    assert harness.Errors.Count == 0
}

test "A for's OUTER SCOPE OPENS AT THE KEYWORD AND CLOSES LAST" {
    harness := LoopDefault()
    body := LoopForeachBody()
    state := harness.Sequence.BeginFor(LoopForOver(LoopInitializer(), LoopProvingCondition(), LoopIterator(), body), harness.Narrowing)

    steps := LoopRun(harness, state, BuiltInTypes.Bool)

    // The outer scope opens at the `for` KEYWORD — which is what makes the initializer's variable
    // belong to the loop and not to the enclosing block.
    assert steps[0].Line == 6
    assert steps[0].Column == 5
    // The narrowing scope opens at the BODY.
    assert steps[4].Line == 7
    assert steps[4].Column == 9
    // Nothing runs after the outer close.
    assert steps[7].Kind == 6
    assert !steps[7].InLoop
}

test "A for's INITIALIZER AND ITERATOR RUN OUTSIDE THE LOOP, THE BODY INSIDE IT" {
    harness := LoopDefault()
    state := harness.Sequence.BeginFor(LoopForOver(LoopInitializer(), LoopProvingCondition(), LoopIterator(), LoopForeachBody()), harness.Narrowing)

    steps := LoopRun(harness, state, BuiltInTypes.Bool)

    assert !steps[0].InLoop
    assert !steps[1].InLoop
    assert !steps[2].InLoop
    // The ITERATOR is analysed once, before the body, and outside the loop.
    assert !steps[3].InLoop
    assert steps[4].InLoop
    assert steps[5].InLoop
    assert steps[6].InLoop
    // The loop closes BEFORE the outer scope does.
    assert !steps[7].InLoop
}

test "A for's ITERATOR IS A NESTED WALK, CARRIED AS A NODE AND NOT AS A BODY" {
    harness := LoopDefault()
    iterator := LoopIterator()
    state := harness.Sequence.BeginFor(LoopForOver(null, null, iterator, LoopForeachBody()), harness.Narrowing)

    steps := LoopRun(harness, state, BuiltInTypes.Bool)

    assert LoopStepKinds(steps) == "2,7,5,6"
    assert Object.ReferenceEquals(steps[1].Node, iterator)
    assert steps[1].Body == null
}

test "EVERY for CLAUSE IS OPTIONAL, AND EACH ABSENCE REMOVES EXACTLY ITS OWN STEPS" {
    // No initializer: the initializer step is gone and nothing else moves.
    noInit := LoopDefault()
    noInitState := noInit.Sequence.BeginFor(LoopForOver(null, LoopProvingCondition(), LoopIterator(), LoopForeachBody()), noInit.Narrowing)
    assert LoopStepKinds(LoopRun(noInit, noInitState, BuiltInTypes.Bool)) == "2,1,7,2,5,6,6"

    // No condition: the condition step, the boolean gate AND the narrowing scope all go, because a
    // `for` with no condition proves nothing.
    noCond := LoopDefault()
    noCondState := noCond.Sequence.BeginFor(LoopForOver(LoopInitializer(), null, LoopIterator(), LoopForeachBody()), noCond.Narrowing)
    assert LoopStepKinds(LoopRun(noCond, noCondState, BuiltInTypes.Bool)) == "2,5,7,5,6"
    assert noCond.Errors.Count == 0

    // No iterator: the nested walk goes.
    noIter := LoopDefault()
    noIterState := noIter.Sequence.BeginFor(LoopForOver(LoopInitializer(), LoopProvingCondition(), null, LoopForeachBody()), noIter.Narrowing)
    assert LoopStepKinds(LoopRun(noIter, noIterState, BuiltInTypes.Bool)) == "2,5,1,2,5,6,6"

    // Nothing at all: the outer scope, the body, the close — and the loop still opens around the
    // body alone.
    bare := LoopDefault()
    bareState := bare.Sequence.BeginFor(LoopForOver(null, null, null, LoopForeachBody()), bare.Narrowing)
    bareSteps := LoopRun(bare, bareState, BuiltInTypes.Bool)
    assert LoopStepKinds(bareSteps) == "2,5,6"
    assert !bareSteps[0].InLoop
    assert bareSteps[1].InLoop
    assert !bareSteps[2].InLoop
}

test "A NON-BOOLEAN for CONDITION SPEAKS UNDER THE for's OWN OWNER NAME, NOT THE while's" {
    harness := LoopDefault()
    state := harness.Sequence.BeginFor(LoopForOver(null, LoopPlainCondition(), null, LoopForeachBody()), harness.Narrowing)

    LoopRun(harness, state, BuiltInTypes.String)

    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "The condition in a 'for' loop must be a boolean, but I found 'string'|6:11+4"
}

test "A DIRECT COLUMN READ IN A for CONDITION ESCAPES WITH THE for's ACTION WORD" {
    harness := LoopDefault()
    LoopDeclareSoaTable(harness)
    state := harness.Sequence.BeginFor(LoopForOver(null, LoopSoaColumnRead(), null, LoopForeachBody()), harness.Narrowing)

    LoopRun(harness, state, LoopArrayOf(BuiltInTypes.Int))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be used as a 'for' condition directly"
}

test "ONE STATE AND ONE DRIVER SERVE ALL FIVE STATEMENTS, AND Form IS THE ONLY THING THAT SEPARATES THEM" {
    harness := LoopDefault()
    iteration := harness.Sequence.BeginForeach(LoopForeachOver(LoopCollection(), LoopForeachBody()))
    asyncIteration := harness.Sequence.BeginAwaitForeach(LoopAwaitForeachOver(LoopCollection(), LoopForeachBody()))
    whileLoop := harness.Sequence.BeginWhile(LoopWhileOver(LoopPlainCondition(), LoopForeachBody()), harness.Narrowing)
    forLoop := harness.Sequence.BeginFor(LoopForOver(LoopInitializer(), LoopPlainCondition(), LoopIterator(), LoopForeachBody()), harness.Narrowing)
    conditional := harness.Sequence.BeginIf(LoopIfOver(LoopPlainCondition(), LoopForeachBody(), null), harness.Narrowing)

    // The two iteration arms share a form and are separated by the mode flag alone.
    assert iteration.Form == 0
    assert asyncIteration.Form == 0
    assert whileLoop.Form == 1
    assert forLoop.Form == 2
    assert conditional.Form == 3
    // Each form's phase band starts where its walk does, so a phase number never means two things.
    assert iteration.Phase == 0
    assert whileLoop.Phase == 10
    assert forLoop.Phase == 20
    assert conditional.Phase == 30
    // Exactly the operands each form uses are non-null.
    assert iteration.Collection != null
    assert iteration.Condition == null
    assert iteration.Narrowing == null
    assert whileLoop.Collection == null
    assert whileLoop.Condition != null
    assert whileLoop.Initializer == null
    assert whileLoop.Iterator == null
    assert forLoop.Initializer != null
    assert forLoop.Iterator != null
    assert forLoop.Narrowing != null
    // `if` is the `while` shape plus one optional body, and the else slot is the family's ONLY
    // optional body.
    assert conditional.Condition != null
    assert conditional.Collection == null
    assert conditional.Initializer == null
    assert conditional.Iterator == null
    assert conditional.ElseBody == null
    assert conditional.Narrowing != null
}

// ── `if` ──────────────────────────────────────────────────────────────────────
//
// The conditional joins the family as its third condition form, and the contracts below are written
// around the FIVE things that are easy to get wrong once it shares a walk with the loops: that it
// NEVER opens an ambient loop, that each branch's narrowing scope exists only when THAT branch's own
// list is non-empty and opens at THAT branch's own position, that the two guard-clause arms are not
// symmetric, that the facts a guard clause installs land in the ENCLOSING scope rather than in one of
// its own, and that an `else if` needs no shape of its own because it arrives back through the branch
// step.

func LoopIfOver(condition: Expression, thenStatement: Statement, elseStatement: Statement?): IfStatement {
    return new IfStatement(condition, thenStatement, elseStatement, 6, 5)
}

// A second body at a DIFFERENT position from `LoopForeachBody`'s, so a contract can tell which branch
// a scope was opened for.
func LoopElseBody(): Statement {
    body: Statement = new BlockStatement(new List<Statement>(), 9, 9)
    return body
}

// `x != null` — proves NOT-NULL when true and NULL when false, which is the shortest condition that
// yields BOTH lists non-empty.
func LoopNullCheckCondition(): Expression {
    check: Expression = new BinaryExpression(new IdentifierExpression("x", 6, 8), BinaryOperator.NotEqual, new NullLiteralExpression(6, 13), 6, 8)
    return check
}

// `x == null` — the mirror, and the shape a guard clause is actually written in.
func LoopNullGuardCondition(): Expression {
    guard: Expression = new BinaryExpression(new IdentifierExpression("x", 6, 8), BinaryOperator.Equal, new NullLiteralExpression(6, 13), 6, 8)
    return guard
}

func LoopReturningBranch(): Statement {
    statements := new List<Statement>()
    returnStatement: Statement = new ReturnStatement(null, 7, 9)
    statements.Add(returnStatement)
    body: Statement = new BlockStatement(statements, 7, 9)
    return body
}

// A branch that always leaves, positioned where the ELSE body is, so the two guard-clause arms can be
// told apart by more than their narrowings.
func LoopReturningElseBranch(): Statement {
    statements := new List<Statement>()
    returnStatement: Statement = new ReturnStatement(null, 9, 9)
    statements.Add(returnStatement)
    body: Statement = new BlockStatement(statements, 9, 9)
    return body
}

func LoopDeclareNullable(harness: LoopHarness) {
    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.String)
    harness.Scopes.Peek().Symbols["x"] = nullable
}

func LoopNullFact(harness: LoopHarness): string {
    return NullStateFacts.GetDiagnosticText(harness.Scopes.NullStateOrUnknown("x"))
}

// The `if` driver, exactly as `Analyzer.cs` writes it — and unlike `LoopRun` it performs the SCOPE
// operations for real, because the whole point of a branch's narrowing scope is that the facts it
// carries die when it closes. `trace` records what the scope stack says about `x` immediately BEFORE
// each step, so the window each fact is visible in is pinned rather than assumed.
func LoopRunIf(harness: LoopHarness, state: LoopStatementState, answer: TypeInfo?, trace: List<string>): List<LoopDriverStep> {
    steps := new List<LoopDriverStep>()
    step := harness.Sequence.NextLoopStep(state)
    while step != null {
        trace.Add(LoopNullFact(harness))
        steps.Add(new LoopDriverStep(step.Kind, step.Node, step.Body, step.Name, LoopTypeText(step.CarriedType), step.Line, step.Column, harness.Ambient.InLoop, harness.Errors.Count))

        if step.Kind == 2 {
            harness.Scopes.Push(harness.Model, new Scope(ScopeKind.Block), step.Line, step.Column)
        }

        if step.Kind == 6 {
            harness.Scopes.Pop(harness.Model, 99)
        }

        harness.Sequence.SupplyLoop(state, answer)
        step = harness.Sequence.NextLoopStep(state)
    }

    trace.Add(LoopNullFact(harness))
    return steps
}

func LoopTraceText(trace: List<string>): string {
    rendered := ""
    index := 0
    while index < trace.Count {
        if index > 0 {
            rendered = rendered + ","
        }

        rendered = rendered + trace[index]
        index = index + 1
    }

    return rendered
}

test "AN if WITH NO ELSE AND A CONDITION THAT PROVES NOTHING ASKS FOR TWO STEPS" {
    harness := LoopDefault()
    body := LoopForeachBody()
    state := harness.Sequence.BeginIf(LoopIfOver(LoopPlainCondition(), body, null), harness.Narrowing)

    steps := LoopRunIf(harness, state, BuiltInTypes.Bool, new List<string>())

    // The condition, then the branch. No scope, because there is nothing to put in one.
    assert LoopStepKinds(steps) == "1,5"
    assert Object.ReferenceEquals(steps[1].Body, body)
    assert harness.Errors.Count == 0
}

test "AN if NEVER OPENS AN AMBIENT LOOP — break AND continue ARE NO MORE LEGAL INSIDE IT" {
    harness := LoopDefault()
    LoopDeclareNullable(harness)
    state := harness.Sequence.BeginIf(LoopIfOver(LoopNullCheckCondition(), LoopForeachBody(), LoopElseBody()), harness.Narrowing)

    steps := LoopRunIf(harness, state, BuiltInTypes.Bool, new List<string>())

    index := 0
    while index < steps.Count {
        assert !steps[index].InLoop
        index = index + 1
    }

    assert !harness.Ambient.InLoop
}

test "EACH BRANCH GETS ITS OWN SCOPE, AT ITS OWN POSITION, ONLY WHEN ITS OWN LIST IS NON-EMPTY" {
    harness := LoopDefault()
    LoopDeclareNullable(harness)
    thenBody := LoopForeachBody()
    elseBody := LoopElseBody()
    state := harness.Sequence.BeginIf(LoopIfOver(LoopNullCheckCondition(), thenBody, elseBody), harness.Narrowing)

    steps := LoopRunIf(harness, state, BuiltInTypes.Bool, new List<string>())

    // Condition, then-scope, then-branch, close, else-scope, else-branch, close.
    assert LoopStepKinds(steps) == "1,2,5,6,2,5,6"
    // The then scope opens at the THEN branch's position and the else scope at the ELSE branch's —
    // neither opens at the `if` keyword.
    assert steps[1].Line == 7
    assert steps[1].Column == 9
    assert steps[4].Line == 9
    assert steps[4].Column == 9
    assert Object.ReferenceEquals(steps[2].Body, thenBody)
    assert Object.ReferenceEquals(steps[5].Body, elseBody)
}

test "A BRANCH WHOSE OWN LIST IS EMPTY GETS NO SCOPE, EVEN WHEN THE OTHER BRANCH HAS ONE" {
    harness := LoopDefault()
    LoopDeclareNullable(harness)
    // `x is string s` proves something when TRUE and nothing when FALSE, so the then-branch is
    // scoped and the else-branch is not.
    condition: Expression = new IsExpression(new IdentifierExpression("x", 6, 8), new SimpleTypeReference("string", 6, 13), "s", 6, 8)
    state := harness.Sequence.BeginIf(LoopIfOver(condition, LoopForeachBody(), LoopElseBody()), harness.Narrowing)

    steps := LoopRunIf(harness, state, BuiltInTypes.Bool, new List<string>())

    assert LoopStepKinds(steps) == "1,2,5,6,5"
}

test "A BRANCH'S FACTS ARE VISIBLE FOR THAT BRANCH ALONE AND DIE WITH ITS SCOPE" {
    harness := LoopDefault()
    LoopDeclareNullable(harness)
    trace := new List<string>()
    state := harness.Sequence.BeginIf(LoopIfOver(LoopNullCheckCondition(), LoopForeachBody(), LoopElseBody()), harness.Narrowing)

    LoopRunIf(harness, state, BuiltInTypes.Bool, trace)

    // Before the condition and before each scope opens: nothing is known. Inside the then-branch:
    // not-null. Inside the else-branch: null. After the statement: nothing again — NEITHER branch's
    // facts survive an `if` whose branches both fall through.
    assert LoopTraceText(trace) == "unknown,unknown,not-null,not-null,unknown,null,null,unknown"
}

test "A GUARD CLAUSE HANDS THE SURVIVING FLOW THE FACTS OF THE BRANCH IT DID NOT TAKE" {
    harness := LoopDefault()
    LoopDeclareNullable(harness)
    trace := new List<string>()
    // `if x == null { return }` — the then-branch always leaves, so what survives is the ELSE fact.
    state := harness.Sequence.BeginIf(LoopIfOver(LoopNullGuardCondition(), LoopReturningBranch(), null), harness.Narrowing)

    steps := LoopRunIf(harness, state, BuiltInTypes.Bool, trace)

    // The then-branch is scoped because `x == null` proves NULL when true.
    assert LoopStepKinds(steps) == "1,2,5,6"
    // And the fact that survives is the OPPOSITE one, installed with no scope of its own.
    assert LoopTraceText(trace) == "unknown,unknown,null,null,not-null"
    // A null-check narrowing carries a NULL STATE and no narrowed TYPE, so the declared type of the
    // guarded name is left exactly as it was — the surviving flow learns that `x` is not null, not
    // that it stopped being `string?`.
    stillNullable := harness.Scopes.Peek().Symbols["x"] as NullableTypeInfo
    assert stillNullable != null
}

test "THE MIRROR GUARD CLAUSE INSTALLS THE THEN FACTS WHEN THE ELSE BRANCH LEAVES" {
    harness := LoopDefault()
    LoopDeclareNullable(harness)
    trace := new List<string>()
    // `if x != null { … } else { return }` — the else-branch leaves, so the THEN fact survives.
    state := harness.Sequence.BeginIf(LoopIfOver(LoopNullCheckCondition(), LoopForeachBody(), LoopReturningElseBranch()), harness.Narrowing)

    LoopRunIf(harness, state, BuiltInTypes.Bool, trace)

    assert LoopTraceText(trace) == "unknown,unknown,not-null,not-null,unknown,null,null,not-null"
}

test "WHEN BOTH BRANCHES LEAVE THE SECOND ARM WINS — THE TWO GUARD ARMS ARE NOT SYMMETRIC" {
    harness := LoopDefault()
    LoopDeclareNullable(harness)
    trace := new List<string>()
    state := harness.Sequence.BeginIf(LoopIfOver(LoopNullGuardCondition(), LoopReturningBranch(), LoopReturningElseBranch()), harness.Narrowing)

    LoopRunIf(harness, state, BuiltInTypes.Bool, trace)

    // The FIRST arm additionally requires that the else-branch does NOT leave, so it is refused
    // here and the SECOND arm fires instead — the surviving flow is handed the THEN facts. There is
    // no reachable code left to read them, which is exactly why the asymmetry is invisible in
    // practice and must be pinned here rather than reasoned about at a call site.
    lastIndex := trace.Count - 1
    assert trace[lastIndex] == "null"
}

test "A BRANCH THAT LEAVES INSTALLS NOTHING WHEN THE OTHER BRANCH PROVED NOTHING" {
    harness := LoopDefault()
    trace := new List<string>()
    // A plain identifier condition proves neither list, so there is nothing to hand on however the
    // branches end.
    state := harness.Sequence.BeginIf(LoopIfOver(LoopPlainCondition(), LoopReturningBranch(), null), harness.Narrowing)

    steps := LoopRunIf(harness, state, BuiltInTypes.Bool, trace)

    assert LoopStepKinds(steps) == "1,5"
    assert LoopTraceText(trace) == "unknown,unknown,unknown"
}

test "A NON-BOOLEAN if CONDITION EARNS THE RICH REPORT, NOT THE while's PLAIN WORDING" {
    harness := LoopHarnessWith("    if count {")
    state := harness.Sequence.BeginIf(LoopIfOver(LoopPlainCondition(), LoopForeachBody(), null), harness.Narrowing)

    steps := LoopRunIf(harness, state, BuiltInTypes.Int, new List<string>())

    assert harness.Errors.Count == 1
    // The rich `if` report carries the source line and the underline; the plain wording would have
    // named "an 'if'" and stopped there.
    assert harness.Errors[0].Message.Contains("int", StringComparison.Ordinal)
    assert harness.Errors[0].Line == 6
    // The report is in the list BEFORE the branch runs, which is what an emission-order reader sees.
    assert steps[0].ErrorsBefore == 0
    assert steps[1].ErrorsBefore == 1
}

test "AN if CONDITION WITH NO SOURCE FALLS BACK TO THE PLAIN WORDING UNDER THE if's OWN OWNER NAME" {
    harness := LoopDefault()
    state := harness.Sequence.BeginIf(LoopIfOver(LoopPlainCondition(), LoopForeachBody(), null), harness.Narrowing)

    LoopRunIf(harness, state, BuiltInTypes.Int, new List<string>())

    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0) == "The condition in an 'if' must be a boolean, but I found 'int'|6:11+4"
}

test "A ROW-VIEW if CONDITION IS TOLD ABOUT THE ESCAPE AND NOT ALSO TOLD IT IS NOT A BOOLEAN" {
    harness := LoopDefault()
    state := harness.Sequence.BeginIf(LoopIfOver(LoopPlainCondition(), LoopForeachBody(), null), harness.Narrowing)

    LoopRunIf(harness, state, LoopSoaRowType(), new List<string>())

    // ONE diagnostic, not two — the escape silences the boolean question, and the action word is the
    // `if` arm's own.
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "SoA row views cannot be used as an 'if' condition; use the table and row index instead"
}

test "AN else if NEEDS NO SHAPE OF ITS OWN — IT IS AN if IN THE ELSE SLOT" {
    harness := LoopDefault()
    LoopDeclareNullable(harness)
    inner: Statement = LoopIfOver(LoopPlainCondition(), LoopElseBody(), null)
    state := harness.Sequence.BeginIf(LoopIfOver(LoopNullCheckCondition(), LoopForeachBody(), inner), harness.Narrowing)

    steps := LoopRunIf(harness, state, BuiltInTypes.Bool, new List<string>())

    // The chain is not flattened: the outer walk hands the inner `if` back as ONE branch statement,
    // and the statement dispatch is what re-enters this walk for it.
    assert LoopStepKinds(steps) == "1,2,5,6,2,5,6"
    assert Object.ReferenceEquals(steps[5].Body, inner)
}
