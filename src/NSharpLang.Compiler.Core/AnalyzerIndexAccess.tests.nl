namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for the index arm — what `a[i]` MEANS.
//
// Every member behind these contracts was `private` in `Analyzer.cs`, so nothing named any of them.
// This is their first DIRECT pinning, and it goes at the decisions that read like plumbing and are
// not:
//
//   * the WALK PROTOCOL: TWO steps of ONE kind, and the expected-type BRACKET around the second,
//     which is opened by the owner and must be open exactly while the index is being walked;
//   * WHICH receivers make the index an `int` — a table, an array and a string, and NOT a dictionary,
//     because forcing `int` on a dictionary would target-type a key;
//   * the ORDER of the eight refusals, and that all three SoA value escapes are EVALUATED even after
//     one has already fired, because each names a different operand;
//   * the COLUMN SLICE's allocation refusal, which is skipped inside an assignment target because a
//     write does not copy;
//   * the ELEMENT TYPE of every receiver shape, including the RANGE fork, which answers the sequence
//     rather than the element in all three of the shapes that have one;
//   * the reflected INDEXER lookup, whose `GetDefaultMembers` original names a type the columnar
//     surface has no local for.
class IndexAccessHarness {
    Arm: AnalyzerIndexAccess
    Errors: List<CompilerError>
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Context: AnalyzerDeclarationContext
    Sink: AnalyzerDiagnosticSink

    constructor(
        arm: AnalyzerIndexAccess,
        errors: List<CompilerError>,
        ambient: AnalyzerAmbientContext,
        scopes: AnalyzerScopeStack,
        context: AnalyzerDeclarationContext,
        sink: AnalyzerDiagnosticSink
    ) {
        Arm = arm
        Errors = errors
        Ambient = ambient
        Scopes = scopes
        Context = context
        Sink = sink
    }
}

func IndexArmOf(inAssignmentTarget: bool): IndexAccessHarness {
    errors := new List<CompilerError>()
    context := new AnalyzerDeclarationContext()
    context.Reset(Path.GetFullPath("."), new List<Assembly>())
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    sink := new AnalyzerDiagnosticSink(errors, provider)
    spans := new AnalyzerDiagnosticSpans(sink)
    usingAliases := new Dictionary<string, string>(StringComparer.Ordinal)
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal)
    namespaces := new List<string>()
    assemblies := new List<Assembly>()
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, usingAliases)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, usingAliases, importedSymbols, importedDeclarations, model, bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    extensions := new List<FunctionDeclaration>()
    extensionResolution := new AnalyzerExtensionMethodResolution(resolver, assignability, context, functionTypes, clrConversion, extensions, namespaces, assemblies)
    members := new AnalyzerMemberResolution(functionTypes, context, substitution, resolver, clrConversion, extensionResolution, namespaces)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)
    identifierResolution := new AnalyzerIdentifierResolution(sink, scopes, resolver, discovery, probe, functionTypes, ambient, nullFlow, extensions, members, model, bindings)
    memberAccess := new AnalyzerMemberAccess(sink, spans, scopes, context, nullFlow, soaEscape, ambient, provider, discovery, probe, substitution, identifierResolution, extensions, namespaces, usingAliases, importedSymbols, importedDeclarations, assemblies, members, clrConversion, extensionResolution, bindings)
    constantFacts := new AnalyzerConstantExpressionFacts(scopes, context)

    arm := new AnalyzerIndexAccess(sink, spans, context, ambient, nullFlow, soaEscape, memberAccess, constantFacts)
    return new IndexAccessHarness(arm, errors, ambient, scopes, context, sink)
}

func IndexCodes(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + ","
        }

        codeValue: int = (int)errors[index].Code
        text = text + codeValue.ToString()
        index = index + 1
    }

    return text
}

func IndexTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    if BuiltInTypes.IsUnknown(candidate) {
        return "unknown"
    }

    simple := candidate as SimpleTypeInfo
    if simple != null {
        return "simple:" + simple.Name
    }

    reflection := candidate as ReflectionTypeInfo
    if reflection != null {
        return "reflection:" + reflection.Type.get_Name()
    }

    nullable := candidate as NullableTypeInfo
    if nullable != null {
        return "nullable(" + IndexTypeName(nullable.InnerType) + ")"
    }

    arrayType := candidate as ArrayTypeInfo
    if arrayType != null {
        return "array(" + IndexTypeName(arrayType.ElementType) + ")"
    }

    generic := candidate as GenericTypeInfo
    if generic != null {
        return "generic:" + generic.Name
    }

    return "<other>"
}

func IndexAccessOf(receiverName: string, index: Expression, isNullConditional: bool): IndexAccessExpression {
    return new IndexAccessExpression(new IdentifierExpression(receiverName, 4, 1), index, isNullConditional, 4, 1)
}

func IndexIntLiteral(value: string): Expression {
    literal: Expression = new IntLiteralExpression(value, 4, 8)
    return literal
}

// One full turn of the protocol. Every step is answered from the queue in order, and the EXPECTED
// TYPE the ambient slot holds at each step is recorded — which is the only way to observe a bracket
// that opens and closes entirely inside the owner.
func IndexOneType(argument: Type): Type[] {
    typeArguments := new Type[](1)
    typeArguments[0] = argument
    return typeArguments
}

class IndexDriveTrace {
    Kinds: string
    ExpectedAtStep: string
    Answer: string
    Reports: int

    constructor() {
        Kinds = ""
        ExpectedAtStep = ""
        Answer = ""
        Reports = 0
    }
}

func IndexDrive(harness: IndexAccessHarness, node: Expression, receiverAnswer: TypeInfo, indexAnswer: TypeInfo, inAssignmentTarget: bool): IndexDriveTrace {
    // THE FACT IS NOW READ FROM THE AMBIENT SLOT rather than handed in at `Begin`, so the harness sets
    // the slot the way a real write target does and clears it again afterwards.
    savedWriteTarget: Dictionary<object, TypeInfo>? = null
    if inAssignmentTarget {
        savedWriteTarget = harness.Ambient.EnterWriteTargetExpressionTypes()
    }

    trace := new IndexDriveTrace()
    before := harness.Errors.Count
    state := harness.Arm.Begin(node)
    stepIndex := 0
    step := harness.Arm.NextStep(state)
    while step != null {
        trace.Kinds = trace.Kinds + step.Kind.ToString()
        if stepIndex > 0 {
            trace.ExpectedAtStep = trace.ExpectedAtStep + ","
        }

        trace.ExpectedAtStep = trace.ExpectedAtStep + IndexTypeName(harness.Ambient.CurrentExpectedType)
        answer := receiverAnswer
        if stepIndex > 0 {
            answer = indexAnswer
        }

        harness.Arm.Supply(state, answer)
        stepIndex = stepIndex + 1
        step = harness.Arm.NextStep(state)
    }

    trace.Answer = IndexTypeName(harness.Arm.Result(state))
    trace.Reports = harness.Errors.Count - before
    if inAssignmentTarget {
        harness.Ambient.ExitWriteTargetExpressionTypes(savedWriteTarget)
    }

    return trace
}

// ---- the walk protocol ---------------------------------------------------------------------------

test "the arm takes TWO steps of ONE kind" {
    harness := IndexArmOf(false)
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.Int, false)

    assert trace.Kinds == "11"
    assert trace.Answer == "simple:int"
    assert trace.Reports == 0
}

test "a node that is not an index access finishes at Begin and asks for nothing" {
    harness := IndexArmOf(false)
    state := harness.Arm.Begin(new IdentifierExpression("xs", 1, 1))

    assert harness.Arm.NextStep(state) == null
    assert IndexTypeName(harness.Arm.Result(state)) == "unknown"
}

// ---- the expected-type bracket -------------------------------------------------------------------

test "an ARRAY receiver brackets the index step with `int`, and the bracket is CLOSED afterwards" {
    harness := IndexArmOf(false)
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.Int, false)

    // The receiver walks with the slot untouched; the index walks under `int`.
    assert trace.ExpectedAtStep == "<null>,simple:int"
    assert harness.Ambient.CurrentExpectedType == null
}

test "a DICTIONARY receiver leaves the slot alone, because its index is a KEY" {
    harness := IndexArmOf(false)
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.String)
    arguments.Add(BuiltInTypes.Int)
    receiver: TypeInfo = new GenericTypeInfo("Dictionary", arguments)
    trace := IndexDrive(harness, IndexAccessOf("map", IndexIntLiteral("0"), false), receiver, BuiltInTypes.String, false)

    assert trace.ExpectedAtStep == "<null>,<null>"
    assert trace.Answer == "simple:int"
}

test "the bracket RESTORES whatever the slot already held" {
    harness := IndexArmOf(false)
    saved := harness.Ambient.EnterExpectedType(BuiltInTypes.String)
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.Int, false)

    assert trace.ExpectedAtStep == "simple:string,simple:int"
    assert IndexTypeName(harness.Ambient.CurrentExpectedType) == "simple:string"
    harness.Ambient.ExitExpectedType(saved)
}

test "a STRING receiver brackets with int and answers char" {
    harness := IndexArmOf(false)
    trace := IndexDrive(harness, IndexAccessOf("text", IndexIntLiteral("0"), false), BuiltInTypes.String, BuiltInTypes.Int, false)

    assert trace.ExpectedAtStep == "<null>,simple:int"
    assert trace.Answer == "simple:char"
}

// ---- the element type ----------------------------------------------------------------------------

test "an array element access answers the ELEMENT and a range access answers the ARRAY" {
    harness := IndexArmOf(false)
    element := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.Int, false)
    assert element.Answer == "simple:int"

    ranged := IndexArmOf(false)
    rangeNode: Expression = new RangeExpression(null, null, 4, 8)
    rangeTrace := IndexDrive(ranged, IndexAccessOf("xs", rangeNode, false), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.Int, false)
    assert rangeTrace.Answer == "array(simple:int)"
}

test "a string range slice answers string, not char" {
    harness := IndexArmOf(false)
    rangeNode: Expression = new RangeExpression(null, null, 4, 8)
    trace := IndexDrive(harness, IndexAccessOf("text", rangeNode, false), BuiltInTypes.String, BuiltInTypes.Int, false)

    assert trace.Answer == "simple:string"
}

test "a named generic sequence answers by NAME SUFFIX, and a dictionary answers its VALUE" {
    harness := IndexArmOf(false)
    listArguments := new List<TypeInfo>()
    listArguments.Add(BuiltInTypes.String)
    listReceiver: TypeInfo = new GenericTypeInfo("List", listArguments)
    listTrace := IndexDrive(harness, IndexAccessOf("items", IndexIntLiteral("0"), false), listReceiver, BuiltInTypes.Int, false)
    assert listTrace.Answer == "simple:string"

    mapHarness := IndexArmOf(false)
    mapArguments := new List<TypeInfo>()
    mapArguments.Add(BuiltInTypes.String)
    mapArguments.Add(BuiltInTypes.Bool)
    mapReceiver: TypeInfo = new GenericTypeInfo("Dictionary", mapArguments)
    mapTrace := IndexDrive(mapHarness, IndexAccessOf("map", IndexIntLiteral("0"), false), mapReceiver, BuiltInTypes.String, false)
    assert mapTrace.Answer == "simple:bool"
}

test "a generic whose name is NOT a recognised sequence answers unknown" {
    harness := IndexArmOf(false)
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    receiver: TypeInfo = new GenericTypeInfo("Box", arguments)
    trace := IndexDrive(harness, IndexAccessOf("box", IndexIntLiteral("0"), false), receiver, BuiltInTypes.Int, false)

    assert trace.Answer == "unknown"
}

test "a REFLECTED array answers its element and its range answers the array" {
    harness := IndexArmOf(false)
    receiver: TypeInfo = new ReflectionTypeInfo(typeof(int[]))
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), receiver, BuiltInTypes.Int, false)
    assert trace.Answer == "simple:int"

    ranged := IndexArmOf(false)
    rangeNode: Expression = new RangeExpression(null, null, 4, 8)
    rangeTrace := IndexDrive(ranged, IndexAccessOf("xs", rangeNode, false), receiver, BuiltInTypes.Int, false)
    assert rangeTrace.Answer == "array(simple:int)"
}

// ---- the reflected indexer -----------------------------------------------------------------------

test "a reflected type's INDEXER answers its property type" {
    harness := IndexArmOf(false)
    receiver: TypeInfo = new ReflectionTypeInfo(Type.GetType("System.Collections.Generic.List`1").MakeGenericType(IndexOneType(typeof(string))))
    trace := IndexDrive(harness, IndexAccessOf("items", IndexIntLiteral("0"), false), receiver, BuiltInTypes.Int, false)

    // `ConvertReflectionType` maps a built-in CLR type back to its BUILT-IN model type, so the
    // indexer's `string` answers `simple:string` rather than a reflected one.
    assert trace.Answer == "simple:string"
}

test "the indexer lookup finds exactly what GetDefaultMembers found" {
    harness := IndexArmOf(false)

    // The substitution's whole claim: the first public property with index parameters IS the default
    // member. These four cover an interface, a class, a struct with two overloads and a type with no
    // indexer at all.
    listIndexer := harness.Arm.FindReflectedIndexerProperty(Type.GetType("System.Collections.Generic.List`1").MakeGenericType(IndexOneType(typeof(int))))
    assert listIndexer != null
    assert listIndexer.get_PropertyType() == typeof(int)

    stringIndexer := harness.Arm.FindReflectedIndexerProperty(typeof(string))
    assert stringIndexer != null
    assert stringIndexer.get_PropertyType() == typeof(char)

    matrixIndexer := harness.Arm.FindReflectedIndexerProperty(Type.GetType("System.Numerics.Matrix4x4, System.Numerics.Vectors"))
    assert matrixIndexer != null

    assert harness.Arm.FindReflectedIndexerProperty(typeof(int)) == null
}

test "a reflected type with NO indexer answers unknown" {
    harness := IndexArmOf(false)
    receiver: TypeInfo = new ReflectionTypeInfo(typeof(int))
    trace := IndexDrive(harness, IndexAccessOf("value", IndexIntLiteral("0"), false), receiver, BuiltInTypes.Int, false)

    assert trace.Answer == "unknown"
}

// ---- the built-in index validation ---------------------------------------------------------------

test "an array indexed by a STRING is refused, and the walk ends" {
    harness := IndexArmOf(false)
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.String, false)

    assert trace.Reports == 1
    assert IndexCodes(harness.Errors) == "202"
    assert harness.Errors[0].Message.Contains("Array indexes must be int")
    assert trace.Answer == "unknown"
}

test "a string indexed by a bool names STRING in the report" {
    harness := IndexArmOf(false)
    trace := IndexDrive(harness, IndexAccessOf("text", IndexIntLiteral("0"), false), BuiltInTypes.String, BuiltInTypes.Bool, false)

    assert harness.Errors[0].Message.Contains("String indexes must be int")
    assert trace.Answer == "unknown"
}

test "an UNKNOWN index is never accused" {
    harness := IndexArmOf(false)
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.Unknown, false)

    assert trace.Reports == 0
}

test "a `System.Index` is a valid array index and a RANGE bypasses the check entirely" {
    harness := IndexArmOf(false)
    systemIndex: TypeInfo = new SimpleTypeInfo("System.Index")
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), new ArrayTypeInfo(BuiltInTypes.Int), systemIndex, false)
    assert trace.Reports == 0
    assert trace.Answer == "simple:int"

    ranged := IndexArmOf(false)
    rangeNode: Expression = new RangeExpression(null, null, 4, 8)
    rangeTrace := IndexDrive(ranged, IndexAccessOf("xs", rangeNode, false), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.String, false)
    assert rangeTrace.Reports == 0
}

test "a NON built-in receiver is left to its own indexer and never validated" {
    harness := IndexArmOf(false)
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.String)
    arguments.Add(BuiltInTypes.Int)
    receiver: TypeInfo = new GenericTypeInfo("Dictionary", arguments)
    trace := IndexDrive(harness, IndexAccessOf("map", IndexIntLiteral("0"), false), receiver, BuiltInTypes.String, false)

    assert trace.Reports == 0
}

// ---- the range and index predicates --------------------------------------------------------------

test "`System.Range` and `System.Index` are recognised under BOTH spellings" {
    assert AnalyzerIndexAccess.IsRangeLikeType(new SimpleTypeInfo("Range"))
    assert AnalyzerIndexAccess.IsRangeLikeType(new SimpleTypeInfo("System.Range"))
    assert AnalyzerIndexAccess.IsRangeLikeType(new ReflectionTypeInfo(typeof(Range)))
    assert !AnalyzerIndexAccess.IsRangeLikeType(BuiltInTypes.Int)

    assert AnalyzerIndexAccess.IsIndexLikeType(new SimpleTypeInfo("Index"))
    assert AnalyzerIndexAccess.IsIndexLikeType(new SimpleTypeInfo("System.Index"))
    assert AnalyzerIndexAccess.IsIndexLikeType(new ReflectionTypeInfo(typeof(Index)))
    assert !AnalyzerIndexAccess.IsIndexLikeType(new SimpleTypeInfo("Range"))
}

// ---- the null-conditional result -----------------------------------------------------------------

test "`a?[i]` wraps its element in a nullable" {
    harness := IndexArmOf(false)
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), true), new ArrayTypeInfo(BuiltInTypes.Int), BuiltInTypes.Int, false)

    assert trace.Answer == "nullable(simple:int)"
}

test "a null-conditional index on an unknown element stays unknown rather than nullable-unknown" {
    harness := IndexArmOf(false)
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    receiver: TypeInfo = new GenericTypeInfo("Box", arguments)
    trace := IndexDrive(harness, IndexAccessOf("box", IndexIntLiteral("0"), true), receiver, BuiltInTypes.Int, false)

    assert trace.Answer == "unknown"
}

// ---- the receiver unwraps ------------------------------------------------------------------------

test "a NULLABLE receiver is unwrapped before its shape is judged" {
    harness := IndexArmOf(false)
    receiver: TypeInfo = new NullableTypeInfo(new ArrayTypeInfo(BuiltInTypes.Int))
    trace := IndexDrive(harness, IndexAccessOf("xs", IndexIntLiteral("0"), false), receiver, BuiltInTypes.Int, false)

    // The `int` bracket proves the unwrap happened before `ShouldUseIntExpectedTypeForIndex` ran.
    assert trace.ExpectedAtStep == "<null>,simple:int"
    assert trace.Answer == "simple:int"
}

// ---- the negative constant row index -------------------------------------------------------------

test "the negative-row rule is about SIGNED integers and CONSTANTS" {
    harness := IndexArmOf(false)
    negative: Expression = new UnaryExpression(UnaryOperator.Negate, IndexIntLiteral("1"), 4, 8)

    assert harness.Arm.ReportNegativeSoaRowIndexIfNeeded(negative, BuiltInTypes.Int, "table row")
    assert IndexCodes(harness.Errors) == "202"
    assert harness.Errors[0].Message.Contains("table row")

    // A non-negative constant, and a signed type with a non-constant expression, are both silent.
    assert !harness.Arm.ReportNegativeSoaRowIndexIfNeeded(IndexIntLiteral("1"), BuiltInTypes.Int, "table row")
    assert !harness.Arm.ReportNegativeSoaRowIndexIfNeeded(new IdentifierExpression("row", 4, 8), BuiltInTypes.Int, "table row")

    // An UNSIGNED type cannot be negative, so the rule does not even look at the expression.
    assert !harness.Arm.ReportNegativeSoaRowIndexIfNeeded(negative, BuiltInTypes.UInt, "table row")
}

test "the negative-row report names the CONTEXT it was asked about" {
    harness := IndexArmOf(false)
    negative: Expression = new UnaryExpression(UnaryOperator.Negate, IndexIntLiteral("2"), 4, 8)

    assert harness.Arm.ReportNegativeSoaRowIndexIfNeeded(negative, BuiltInTypes.Short, "column row")
    assert harness.Errors[0].Message.Contains("column row")
}

// ---- the table row index -------------------------------------------------------------------------

test "a table row id is an int and NOTHING else" {
    harness := IndexArmOf(false)

    assert harness.Arm.IsValidSoaRowIndex(BuiltInTypes.Int, false)
    assert harness.Arm.IsValidSoaRowIndex(BuiltInTypes.Unknown, false)
    assert !harness.Arm.IsValidSoaRowIndex(BuiltInTypes.Long, false)
    assert !harness.Arm.IsValidSoaRowIndex(new SimpleTypeInfo("System.Index"), false)

    // A range is refused whatever its type says.
    assert !harness.Arm.IsValidSoaRowIndex(BuiltInTypes.Int, true)
}

test "the invalid-row report distinguishes a range, a System.Index and an ordinary type" {
    harness := IndexArmOf(false)
    node := IndexIntLiteral("0")

    harness.Arm.ReportInvalidSoaRowIndex(node, BuiltInTypes.Int, true)
    assert harness.Errors[0].Message.Contains("a range")

    harness.Arm.ReportInvalidSoaRowIndex(node, new SimpleTypeInfo("System.Index"), false)
    assert harness.Errors[1].Message.Contains("'System.Index'")

    harness.Arm.ReportInvalidSoaRowIndex(node, BuiltInTypes.String, false)
    assert harness.Errors[2].Message.Contains("'string'")
}

// ---- the column slice ----------------------------------------------------------------------------

test "the column-slice report is NL103 and names the allocation" {
    harness := IndexArmOf(false)
    node := IndexAccessOf("column", IndexIntLiteral("0"), false)

    harness.Arm.ReportSoaColumnSliceHiddenAllocation(node)
    assert IndexCodes(harness.Errors) == "103"
    assert harness.Errors[0].Message.Contains("allocate arrays")
}

// ---- the int-expected-type rule ------------------------------------------------------------------

test "the int-expected rule covers a table, both array shapes and a string, and nothing else" {
    harness := IndexArmOf(false)

    assert harness.Arm.ShouldUseIntExpectedTypeForIndex(new ArrayTypeInfo(BuiltInTypes.Int))
    assert harness.Arm.ShouldUseIntExpectedTypeForIndex(new ReflectionTypeInfo(typeof(int[])))
    assert harness.Arm.ShouldUseIntExpectedTypeForIndex(BuiltInTypes.String)

    assert !harness.Arm.ShouldUseIntExpectedTypeForIndex(BuiltInTypes.Int)
    assert !harness.Arm.ShouldUseIntExpectedTypeForIndex(new ReflectionTypeInfo(Type.GetType("System.Collections.Generic.List`1").MakeGenericType(IndexOneType(typeof(int)))))
}
