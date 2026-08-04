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
// (3) THE `yield` WALK'S ANSWERS ARE READ. Both escape reports return a boolean the walk uses to
// SILENCE the element-type rule, which is the one thing that distinguishes this driver's kind 2 and 3
// from the `return` walk's.

// ── a runtime type that satisfies the duck-typed enumerator pattern ───────────
//
// Not an `IEnumerable` of any kind: a parameterless `GetEnumerator` whose return type carries a
// parameterless `bool MoveNext()` and a readable `Current`, which is the whole of the pattern.
public class LoopProbeEnumerator {
    Current: int => 7

    public func MoveNext(): bool {
        return false
    }
}

public class LoopProbeSequence {
    public func GetEnumerator(): LoopProbeEnumerator {
        return new LoopProbeEnumerator()
    }
}

// A type with a `GetEnumerator` whose enumerator has NO `MoveNext`, which must not satisfy the
// pattern — the probe checks the enumerator, not just the entry point.
public class LoopProbeBrokenEnumerator {
    Current: int => 7
}

public class LoopProbeBrokenSequence {
    public func GetEnumerator(): LoopProbeBrokenEnumerator {
        return new LoopProbeBrokenEnumerator()
    }
}

class LoopHarness {
    Sequence: AnalyzerLoopSequence
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Errors: List<CompilerError>
    Assignability: AnalyzerAssignability

    constructor(
        sequence: AnalyzerLoopSequence,
        ambient: AnalyzerAmbientContext,
        scopes: AnalyzerScopeStack,
        errors: List<CompilerError>,
        assignability: AnalyzerAssignability) {
        Sequence = sequence
        Ambient = ambient
        Scopes = scopes
        Errors = errors
        Assignability = assignability
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
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        diagnostics,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal),
        model,
        new BindingMap())
    resolver.BeginAnalysis(LoopPath(), null, model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(
        context, facts, structural, substitution, clrConversion, guard)
    ambient := new AnalyzerAmbientContext(diagnostics, spans)
    sequence := new AnalyzerLoopSequence(diagnostics, spans, scopes, context, resolver, ambient)
    return new LoopHarness(sequence, ambient, scopes, errors, assignability)
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
    return new FunctionDeclaration(
        name,
        new List<Parameter>(),
        returnType,
        null,
        null,
        null,
        null,
        modifiers,
        new List<AttributeNode>(),
        false,
        null,
        false,
        false,
        3,
        1)
}

func LoopErrorText(harness: LoopHarness, index: int): string {
    error := harness.Errors[index]
    return error.Message + "|" + error.Line.ToString() + ":" + error.Column.ToString()
        + "+" + error.Length.ToString()
}

// ── the `yield` driver, exactly as `Analyzer.cs` writes it ────────────────────
func LoopRunYield(
    harness: LoopHarness,
    statement: YieldStatement,
    answer: TypeInfo?,
    rowEscape: bool,
    columnEscape: bool): List<LoopStep> {
    steps := new List<LoopStep>()
    state := harness.Sequence.BeginYield(statement, harness.Assignability)
    step := harness.Sequence.NextStep(state)
    while step != null {
        steps.Add(new LoopStep(
            step.Kind,
            step.Node,
            step.Text,
            LoopTypeText(step.CarriedType),
            harness.Errors.Count))

        supplied: TypeInfo? = null
        escaped := false
        if step.Kind == 1 {
            supplied = answer
        }

        if step.Kind == 2 {
            escaped = rowEscape
        }

        if step.Kind == 3 {
            escaped = columnEscape
        }

        harness.Sequence.Supply(state, supplied, escaped)
        step = harness.Sequence.NextStep(state)
    }

    return steps
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
    declared: TypeInfo = new ClassTypeInfo(
        "Bag",
        1,
        1,
        false,
        null,
        LoopSequenceInterfaces(),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true)
    return declared
}

func LoopDeclaredPlainClass(): TypeInfo {
    declared: TypeInfo = new ClassTypeInfo(
        "Plain",
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true)
    return declared
}

func LoopDeclaredSequenceInterface(): TypeInfo {
    declared: TypeInfo = new InterfaceTypeInfo(
        "IBag",
        1,
        1,
        false,
        LoopSequenceInterfaces(),
        new TypeParameter[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0))
    return declared
}

// ── the shape normaliser ──────────────────────────────────────────────────────

test "THE SHAPE NORMALISER UNWRAPS nullable, oblivious AND ref TO A FIXED POINT" {
    harness := LoopDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new NullableTypeInfo(arrayType))) == "int[]"
    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new ObliviousTypeInfo(arrayType))) == "int[]"
    assert LoopTypeText(harness.Sequence.NormalizeShapeType(new ByRefTypeInfo(arrayType))) == "int[]"
    assert LoopTypeText(
        harness.Sequence.NormalizeShapeType(
            new ObliviousTypeInfo(new ByRefTypeInfo(new NullableTypeInfo(arrayType))))) == "int[]"
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
    assert LoopErrorText(harness, 0)
        == "foreach collection must be enumerable, but this collection is 'int'|4:14+6"
    assert harness.Errors[0].Suggestion
        == "Use an array, Span<T>, or IEnumerable<T> value as the foreach collection."
}

test "AN await foreach OVER A SYNCHRONOUS SEQUENCE REPORTS THE ASYNC WORDING" {
    harness := LoopDefault()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)

    resolved := harness.Sequence.ResolveAwaitForeachElementType(LoopCollection(), arrayType)

    assert LoopTypeText(resolved) == "unknown"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0)
        == "await foreach collection must be async enumerable, but this collection is 'int[]'|4:14+6"
    assert harness.Errors[0].Suggestion
        == "Use an IAsyncEnumerable<T> value as the await foreach collection."
}

test "AN await foreach OVER AN ASYNC SEQUENCE ANSWERS THE ELEMENT TYPE" {
    harness := LoopDefault()

    resolved := harness.Sequence.ResolveAwaitForeachElementType(
        LoopCollection(), LoopGeneric("IAsyncEnumerable", BuiltInTypes.String))

    assert LoopTypeText(resolved) == "string"
    assert harness.Errors.Count == 0
}

test "AN UNKNOWN COLLECTION ANSWERS unknown SILENTLY IN BOTH LOOPS" {
    harness := LoopDefault()

    assert LoopTypeText(
        harness.Sequence.ResolveForeachElementType(LoopCollection(), BuiltInTypes.Unknown)) == "unknown"
    assert LoopTypeText(
        harness.Sequence.ResolveAwaitForeachElementType(LoopCollection(), BuiltInTypes.Unknown)) == "unknown"
    assert harness.Errors.Count == 0
}

// ── the generator façade ─────────────────────────────────────────────────────

test "THE GENERATOR ELEMENT TYPE FOLLOWS THE ENCLOSING FUNCTION'S async MODIFIER" {
    harness := LoopDefault()
    syncSequence := LoopGeneric("IEnumerable", BuiltInTypes.Int)
    asyncSequence := LoopGeneric("IAsyncEnumerable", BuiltInTypes.Int)

    harness.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), BuiltInTypes.Unknown)

    assert LoopTypeText(harness.Sequence.GetGeneratorYieldElementType(syncSequence)) == "int"
    assert LoopTypeText(harness.Sequence.GetGeneratorYieldElementType(asyncSequence)) == "<null>"

    harness.Ambient.EnterFunctionDeclaration(
        LoopFunction("h", null, Modifiers.Generator | Modifiers.Async), BuiltInTypes.Unknown)

    assert LoopTypeText(harness.Sequence.GetGeneratorYieldElementType(asyncSequence)) == "int"
    assert LoopTypeText(harness.Sequence.GetGeneratorYieldElementType(syncSequence)) == "<null>"
}

// ── the `yield` walk ─────────────────────────────────────────────────────────

test "A BARE yield ASKS FOR NOTHING" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))

    steps := LoopRunYield(harness, LoopYield(null), null, false, false)

    assert LoopKinds(steps) == ""
    assert harness.Errors.Count == 0
}

test "A yield WITH A VALUE ASKS FOR THE WALK AND BOTH ESCAPE REPORTS, IN THAT ORDER" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))

    steps := LoopRunYield(harness, LoopYield(LoopValue()), BuiltInTypes.Int, false, false)

    assert LoopKinds(steps) == "1,2,3"
    assert LoopText(steps[0].Text) == "<null>"
    assert LoopText(steps[1].Text) == "yielded"
    assert LoopText(steps[2].Text) == "yielded"
    // Kind 2 carries the answered type; kind 1 has nothing to carry yet.
    assert steps[0].CarriedType == "unknown"
    assert steps[1].CarriedType == "int"
    assert harness.Errors.Count == 0
}

test "A yield OUTSIDE A GENERATOR IS REPORTED AT THE KEYWORD, AND THE VALUE IS STILL WALKED" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(
        LoopFunction("f", null, Modifiers.None), BuiltInTypes.Int)

    steps := LoopRunYield(harness, LoopYield(LoopValue()), BuiltInTypes.String, false, false)

    assert LoopKinds(steps) == "1,2,3"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0)
        == "'yield' can only be used inside a generator function|6:5+5"
    // The element-type rule is silent for a non-generator: it has already been told what is wrong.
    assert steps[0].ErrorsBefore == 1
}

test "A yield OF THE WRONG TYPE IS REPORTED AT THE VALUE, WITH BOTH TYPES IN THE WORDING" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))

    LoopRunYield(harness, LoopYield(LoopValue()), BuiltInTypes.String, false, false)

    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0)
        == "Generator yield value is 'string', but the sequence element type is 'int'|6:11+1"
    assert harness.Errors[0].Suggestion
        == "Yield a value assignable to 'int', or change the generator return type."
}

test "EITHER ESCAPE ANSWER SILENCES THE ELEMENT-TYPE RULE" {
    rowHarness := LoopDefault()
    rowHarness.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))
    LoopRunYield(rowHarness, LoopYield(LoopValue()), BuiltInTypes.String, true, false)
    assert rowHarness.Errors.Count == 0

    columnHarness := LoopDefault()
    columnHarness.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))
    LoopRunYield(columnHarness, LoopYield(LoopValue()), BuiltInTypes.String, false, true)
    assert columnHarness.Errors.Count == 0
}

test "A yield WHOSE VALUE FITS, OR WHOSE SEQUENCE IS UNNAMEABLE, IS SILENT" {
    fitting := LoopDefault()
    fitting.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))
    LoopRunYield(fitting, LoopYield(LoopValue()), BuiltInTypes.Int, false, false)
    assert fitting.Errors.Count == 0

    // A return type that names no sequence at all: a different error, reported elsewhere.
    unnameable := LoopDefault()
    unnameable.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), BuiltInTypes.Int)
    LoopRunYield(unnameable, LoopYield(LoopValue()), BuiltInTypes.String, false, false)
    assert unnameable.Errors.Count == 0

    // An unknown on either side would make the wording meaningless.
    unknownValue := LoopDefault()
    unknownValue.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))
    LoopRunYield(unknownValue, LoopYield(LoopValue()), BuiltInTypes.Unknown, false, false)
    assert unknownValue.Errors.Count == 0
}

test "A yield WITH NO ENCLOSING FUNCTION AT ALL REPORTS ONLY THE GENERATOR RULE" {
    harness := LoopDefault()

    steps := LoopRunYield(harness, LoopYield(LoopValue()), BuiltInTypes.String, false, false)

    assert LoopKinds(steps) == "1,2,3"
    assert harness.Errors.Count == 1
    assert LoopErrorText(harness, 0)
        == "'yield' can only be used inside a generator function|6:5+5"
}

test "AN UNANSWERED VALUE WALK LEAVES THE YIELDED TYPE unknown RATHER THAN NULL" {
    harness := LoopDefault()
    harness.Ambient.EnterFunctionDeclaration(
        LoopFunction("g", null, Modifiers.Generator), LoopGeneric("IEnumerable", BuiltInTypes.Int))

    steps := LoopRunYield(harness, LoopYield(LoopValue()), null, false, false)

    assert LoopKinds(steps) == "1,2,3"
    assert steps[1].CarriedType == "unknown"
    assert harness.Errors.Count == 0
}
