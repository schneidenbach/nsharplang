namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT MAY BE WRITTEN THROUGH — the rule three arms share.
//
// Every member behind these contracts was `private` in `Analyzer.cs`, reachable only by writing a
// program and reading a diagnostic. This is their first DIRECT pinning, and it goes at the decisions
// that are easy to get wrong:
//
// (1) THE OUTERMOST NULL-CONDITIONAL HOP WINS, not the innermost and not the target. `a?.b.c = 1` is
// refused about `a?.b`, because that is the hop that can actually be null.
//
// (2) A COLUMN SLICE IS REFUSED BEFORE THE RECEIVER IS CLASSIFIED. The allocation rule does not care
// what the elements are, so it runs ahead of the string and array arms.
//
// (3) AN ARRAY ELEMENT IS A STORAGE LOCATION AND AN ARRAY SLICE IS NOT. The array arm answers `false`
// unless the access is a RANGE, which is the whole difference between `xs[0] = 1` and `xs[0..2] = ys`.
//
// (4) A NULLABLE'S `HasValue` AND `Value` ARE READ-ONLY BY CONSTRUCTION and are answered without any
// metadata at all — there is no declaration to find.
//
// (5) THE READONLY-FIELD RULE FORKS THREE WAYS ON ONE FACT. Static, instance-in-a-constructor and
// instance-elsewhere produce three different sentences, and the constructor exemption applies only to
// the CURRENT instance — a constructor may not write another object's readonly field.
//
// (6) A PROPERTY OF THE SAME NAME ENDS THE FIELD SEARCH. `count` declared as a property is rule 4's
// business, and the field rule must answer "no" rather than fall through to the base types.
//
// (7) THE CAPTURE TABLE IS KEYED BY NODE IDENTITY. Two structurally identical expression nodes are
// two entries; the key type is `object` and the comparer is the default one, and that IS reference
// identity because every AST node class declares no `Equals` and no `GetHashCode`.

// A REFLECTED PROBE WITH ALL THREE SHAPES THE FIELD RULES DISTINGUISH: an instance `readonly` field
// (which reflects as `initonly`), a MUTABLE instance field, and a PROPERTY, whose whole job here is to
// CLAIM its name and stop the walk.
class WriteTargetReadonlyProbe {
    readonly Total: int
    Mutable: int
    Named: int => 0

    constructor(total: int) {
        Total = total
        Mutable = 0
    }
}

class WriteTargetHarness {
    Targets: AnalyzerWriteTargets
    Errors: List<CompilerError>
    Ambient: AnalyzerAmbientContext
    Scopes: AnalyzerScopeStack
    Context: AnalyzerDeclarationContext

    constructor(targets: AnalyzerWriteTargets, errors: List<CompilerError>, ambient: AnalyzerAmbientContext, scopes: AnalyzerScopeStack, context: AnalyzerDeclarationContext) {
        Targets = targets
        Errors = errors
        Ambient = ambient
        Scopes = scopes
        Context = context
    }
}

func WriteTargetHarnessOf(): WriteTargetHarness {
    errors := new List<CompilerError>()
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
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
    indexAccess := new AnalyzerIndexAccess(sink, spans, context, ambient, nullFlow, soaEscape, memberAccess, constantFacts)
    targets := new AnalyzerWriteTargets(sink, spans, scopes, context, substitution, clrConversion, ambient, soaEscape, memberAccess, indexAccess)
    return new WriteTargetHarness(targets, errors, ambient, scopes, context)
}

// A RECEIVER THAT IS NOT A DECLARED SYMBOL IS READ AS A TYPE NAME. `IsStaticMemberAccessTarget`
// answers `LookupSymbol(name) == null`, so an undeclared identifier receiver takes the STATIC member
// path and every instance rule below it silently finds nothing. Any contract about an INSTANCE
// receiver has to bind the name first.
func WriteTargetDeclare(harness: WriteTargetHarness, name: string, declaredType: TypeInfo) {
    harness.Scopes.Peek().Symbols[name] = declaredType
}

func WriteTargetName(name: string): Expression {
    expression: Expression = new IdentifierExpression(name, 3, 5)
    return expression
}

func WriteTargetMember(receiver: Expression, memberName: string, nullConditional: bool): Expression {
    expression: Expression = new MemberAccessExpression(receiver, memberName, nullConditional, 3, 5)
    return expression
}

func WriteTargetMemberNode(receiver: Expression, memberName: string): MemberAccessExpression {
    return new MemberAccessExpression(receiver, memberName, false, 3, 5)
}

func WriteTargetIndex(receiver: Expression, index: Expression, nullConditional: bool): Expression {
    expression: Expression = new IndexAccessExpression(receiver, index, nullConditional, 3, 5)
    return expression
}

func WriteTargetInt(value: string): Expression {
    expression: Expression = new IntLiteralExpression(value, 3, 9)
    return expression
}

func WriteTargetRange(): Expression {
    expression: Expression = new RangeExpression(WriteTargetInt("0"), WriteTargetInt("2"), 3, 9)
    return expression
}

func WriteTargetTable(name: string, columnName: string): SoaRecordTypeInfo {
    columns := new List<SoaColumnInfo>()
    columns.Add(new SoaColumnInfo(columnName, new SimpleTypeReference("int", 1, 1), 1, 1))
    return new SoaRecordTypeInfo(new SoaRecordDeclarationInfo(name, columns, 1, 1))
}

func WriteTargetTypes(): Dictionary<object, TypeInfo> {
    return new Dictionary<object, TypeInfo>()
}

func WriteTargetCodes(errors: List<CompilerError>): string {
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

// ---- rule 6: which targets need a capture table ---------------------------------------------------

test "a member or index chain needs the capture table and nothing else does" {
    member := WriteTargetMember(WriteTargetName("box"), "count", false)
    index := WriteTargetIndex(WriteTargetName("xs"), WriteTargetInt("0"), false)

    assert AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(member)
    assert AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(index)
    assert !AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(WriteTargetName("n"))
    assert !AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(WriteTargetInt("1"))
}

test "the three transparent wrappers are seen through by the shape question" {
    member := WriteTargetMember(WriteTargetName("box"), "count", false)
    parenthesized: Expression = new ParenthesizedExpression(member, 3, 4)
    checkedForm: Expression = new CheckedExpression(member, 3, 4)
    uncheckedForm: Expression = new UncheckedExpression(member, 3, 4)

    assert AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(parenthesized)
    assert AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(checkedForm)
    assert AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(uncheckedForm)
}

// ---- rule 1: the null-conditional write target ----------------------------------------------------

test "the OUTERMOST null-conditional hop is the one named, not the target" {
    harness := WriteTargetHarnessOf()
    inner := WriteTargetMember(WriteTargetName("a"), "b", true)
    outer := WriteTargetMember(inner, "c", false)

    node: Expression = outer
    kind := ""
    assert AnalyzerWriteTargets.TryFindNullConditionalWriteTarget(outer, out node, out kind)
    assert kind == "member access"
    assert Object.ReferenceEquals(node, inner)

    assert harness.Targets.ReportNullConditionalWriteTargetIfNeeded(outer, "assigned with '='")
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Null-conditional member access can't be assigned with '='"
    assert WriteTargetCodes(harness.Errors) == "103"
}

test "an index hop names itself as an index access and a plain chain refuses nothing" {
    harness := WriteTargetHarnessOf()
    index := WriteTargetIndex(WriteTargetName("xs"), WriteTargetInt("0"), true)

    assert harness.Targets.ReportNullConditionalWriteTargetIfNeeded(index, "used as the out argument")
    assert harness.Errors[0].Message == "Null-conditional index access can't be used as the out argument"

    plain := WriteTargetMember(WriteTargetMember(WriteTargetName("a"), "b", false), "c", false)
    assert !harness.Targets.ReportNullConditionalWriteTargetIfNeeded(plain, "assigned with '='")
    assert harness.Errors.Count == 1
}

// ---- rule 2: the SoA table member mutation ---------------------------------------------------------

test "a table COLUMN and both bookkeeping fields are refused, with two different suggestions" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("table")
    table: TypeInfo = WriteTargetTable("Points", "x")

    columnWrite := WriteTargetMember(receiver, "x", false)
    types := WriteTargetTypes()
    types[receiver] = table
    assert harness.Targets.ReportSoaTableMemberMutationIfNeeded(columnWrite, types, "assigned directly")
    assert harness.Errors[0].Message == "SoA table member 'x' cannot be assigned directly"
    assert harness.Errors[0].Suggestion == "Write individual rows with table[index].column, or construct/wrap the table with the desired column arrays."

    lengthWrite := WriteTargetMember(receiver, "length", false)
    assert harness.Targets.ReportSoaTableMemberMutationIfNeeded(lengthWrite, types, "assigned directly")
    assert harness.Errors[1].Suggestion == "Use add, clear, ensureCapacity, or copyRow so length and capacity stay consistent with the columns."

    capacityWrite := WriteTargetMember(receiver, "capacity", false)
    assert harness.Targets.ReportSoaTableMemberMutationIfNeeded(capacityWrite, types, "assigned directly")
    assert harness.Errors.Count == 3
    assert WriteTargetCodes(harness.Errors) == "103,103,103"
}

test "a name the table does not declare is not a table member mutation, and neither is a missing table" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("table")
    types := WriteTargetTypes()
    types[receiver] = WriteTargetTable("Points", "x")

    other := WriteTargetMember(receiver, "notAColumn", false)
    assert !harness.Targets.ReportSoaTableMemberMutationIfNeeded(other, types, "assigned directly")

    // No capture table at all, and a receiver the table does not know: both decline rather than guess.
    assert !harness.Targets.ReportSoaTableMemberMutationIfNeeded(WriteTargetMember(receiver, "x", false), null, "assigned directly")
    assert !harness.Targets.ReportSoaTableMemberMutationIfNeeded(WriteTargetMember(WriteTargetName("elsewhere"), "x", false), types, "assigned directly")
    assert harness.Errors.Count == 0
}

// ---- rule 3: the unsupported built-in indexed mutation ---------------------------------------------

test "a STRING index and an array SLICE are refused and an array ELEMENT is not" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("text")
    types := WriteTargetTypes()
    types[receiver] = BuiltInTypes.String

    stringWrite := WriteTargetIndex(receiver, WriteTargetInt("0"), false)
    assert harness.Targets.ReportUnsupportedBuiltInIndexedMutationIfNeeded(stringWrite, types, "assigned")
    assert harness.Errors[0].Message == "String characters and slices cannot be assigned"

    arrayReceiver := WriteTargetName("xs")
    arrayTypes := WriteTargetTypes()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    arrayTypes[arrayReceiver] = arrayType

    element := WriteTargetIndex(arrayReceiver, WriteTargetInt("0"), false)
    assert !harness.Targets.ReportUnsupportedBuiltInIndexedMutationIfNeeded(element, arrayTypes, "assigned")

    slice := WriteTargetIndex(arrayReceiver, WriteTargetRange(), false)
    assert harness.Targets.ReportUnsupportedBuiltInIndexedMutationIfNeeded(slice, arrayTypes, "assigned")
    assert harness.Errors[1].Message == "Array slices cannot be assigned"
    assert harness.Errors.Count == 2
}

test "a RANGE-TYPED index is a slice even when the index is not written as a range" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("xs")
    indexNode := WriteTargetName("window")
    types := WriteTargetTypes()
    arrayType: TypeInfo = new ArrayTypeInfo(BuiltInTypes.Int)
    types[receiver] = arrayType
    rangeType: TypeInfo = new SimpleTypeInfo("System.Range")
    types[indexNode] = rangeType

    assert harness.Targets.ReportUnsupportedBuiltInIndexedMutationIfNeeded(WriteTargetIndex(receiver, indexNode, false), types, "assigned")
    assert harness.Errors[0].Message == "Array slices cannot be assigned"
}

test "a receiver the rule does not model refuses nothing" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("map")
    types := WriteTargetTypes()
    dictionaryArguments := new List<TypeInfo>()
    dictionaryArguments.Add(BuiltInTypes.String)
    dictionaryArguments.Add(BuiltInTypes.Int)
    dictionary: TypeInfo = new GenericTypeInfo("Dictionary", dictionaryArguments)
    types[receiver] = dictionary

    assert !harness.Targets.ReportUnsupportedBuiltInIndexedMutationIfNeeded(WriteTargetIndex(receiver, WriteTargetInt("0"), false), types, "assigned")
    assert harness.Errors.Count == 0
}

// ---- rule 4: the read-only property -----------------------------------------------------------------

test "a nullable's HasValue and Value are read-only without any metadata at all" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("maybe")
    types := WriteTargetTypes()
    nullable: TypeInfo = new NullableTypeInfo(BuiltInTypes.Int)
    types[receiver] = nullable

    assert harness.Targets.ReportReadOnlyPropertyWriteTargetIfNeeded(WriteTargetMember(receiver, "Value", false), "=", types)
    assert harness.Errors[0].Message == "Property 'Value' is read-only — it can't be assigned with '='"

    assert harness.Targets.ReportReadOnlyPropertyWriteTargetIfNeeded(WriteTargetMember(receiver, "HasValue", false), "++", types)
    assert harness.Errors[1].Message == "Property 'HasValue' is read-only — it can't be changed with '++'"
}

test "a reflected property with no public setter is read-only and a settable one is not" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("text")
    types := WriteTargetTypes()
    stringType: TypeInfo = new ReflectionTypeInfo(typeof(string))
    types[receiver] = stringType
    WriteTargetDeclare(harness, "text", stringType)

    // `string.Length` has no setter at all.
    assert harness.Targets.ReportReadOnlyPropertyWriteTargetIfNeeded(WriteTargetMember(receiver, "Length", false), "=", types)
    assert harness.Errors[0].Message == "Property 'Length' is read-only — it can't be assigned with '='"

    listReceiver := WriteTargetName("items")
    listTypes := WriteTargetTypes()
    listType: TypeInfo = new ReflectionTypeInfo(typeof(List<int>))
    listTypes[listReceiver] = listType
    WriteTargetDeclare(harness, "items", listType)

    // `List<T>.Capacity` HAS a public setter.
    assert !harness.Targets.ReportReadOnlyPropertyWriteTargetIfNeeded(WriteTargetMember(listReceiver, "Capacity", false), "=", listTypes)
    assert harness.Errors.Count == 1
}

test "a SoA table and a row view are never read-only property targets" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("table")
    types := WriteTargetTypes()
    table: TypeInfo = WriteTargetTable("Points", "x")
    types[receiver] = table

    assert !harness.Targets.TryIsReadOnlyPropertyMember(table, "x", false)
    assert !harness.Targets.ReportReadOnlyPropertyWriteTargetIfNeeded(WriteTargetMember(receiver, "x", false), "=", types)
    assert harness.Errors.Count == 0
}

test "a member access with no capture table entry for its receiver refuses nothing" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("text")

    assert !harness.Targets.ReportReadOnlyPropertyWriteTargetIfNeeded(WriteTargetMember(receiver, "Length", false), "=", null)
    assert !harness.Targets.ReportReadOnlyPropertyWriteTargetIfNeeded(WriteTargetMember(receiver, "Length", false), "=", WriteTargetTypes())
    assert harness.Errors.Count == 0
}

// ---- rule 5: the readonly field, and its three reports -----------------------------------------------

func WriteTargetClassWith(name: string, fieldName: string, modifiers: Modifiers): ClassDeclaration {
    members := new List<Declaration>()
    members.Add(new FieldDeclaration(fieldName, new SimpleTypeReference("int", 2, 5), null, modifiers, PropertyModifier.None, new List<AttributeNode>(), 2, 5))
    return new ClassDeclaration(name, null, null, new List<TypeReference>(), members, null, Modifiers.None, new List<AttributeNode>(), 1, 1)
}

func WriteTargetStructWith(name: string, fieldName: string, modifiers: Modifiers): StructDeclaration {
    members := new List<Declaration>()
    members.Add(new FieldDeclaration(fieldName, new SimpleTypeReference("int", 2, 5), null, modifiers, PropertyModifier.None, new List<AttributeNode>(), 2, 5))
    return new StructDeclaration(name, null, new List<TypeReference>(), members, null, Modifiers.None, new List<AttributeNode>(), 1, 1)
}

// WHAT THE TYPE-DECLARATION WALK ACTUALLY ENTERS, and the reason the bare-name channel is no longer
// class-only: the walk moves the class slot for a CLASS and the MEMBER LIST for a class, a struct and
// a record alike. This helper enters both so a contract drives the same ambient production does; a
// struct or a record enters the member list ALONE, which is exactly what `WriteTargetStructMembers`
// below is for.
func WriteTargetEnterClass(harness: WriteTargetHarness, declaration: ClassDeclaration) {
    harness.Ambient.EnterClassDeclaration(declaration)
    harness.Ambient.EnterTypeMembers(declaration.Members)
}

test "a static readonly field can only be initialized at its declaration, in or out of a constructor" {
    harness := WriteTargetHarnessOf()
    WriteTargetEnterClass(harness, WriteTargetClassWith("Widget", "total", Modifiers.Readonly | Modifiers.Static))

    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("total"), 3, 5, null)
    assert harness.Errors[0].Message == "Field 'total' is static readonly — it can only be initialized at its declaration"
    assert WriteTargetCodes(harness.Errors) == "309"

    harness.Ambient.EnterConstructor()
    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("total"), 3, 5, null)
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "Field 'total' is static readonly — it can only be initialized at its declaration"
}

test "an instance readonly field is exempt ONLY inside a constructor AND only on the current instance" {
    harness := WriteTargetHarnessOf()
    WriteTargetEnterClass(harness, WriteTargetClassWith("Widget", "count", Modifiers.Readonly))

    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert harness.Errors[0].Message == "Field 'count' is readonly — it can only be assigned in a constructor"
    assert harness.Errors[0].Suggestion == "Move this assignment into a constructor, or remove `readonly` if the field needs to change later."

    harness.Ambient.EnterConstructor()
    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert harness.Errors.Count == 1

    // Another INSTANCE — reached through a receiver rather than through the enclosing class — is NOT
    // exempt even inside a constructor, and the sentence says why.
    receiver := WriteTargetName("other")
    types := WriteTargetTypes()
    widget: TypeInfo = new ReflectionTypeInfo(typeof(WriteTargetReadonlyProbe))
    types[receiver] = widget
    WriteTargetDeclare(harness, "other", widget)
    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetMember(receiver, "Total", false), 3, 5, types)
    assert harness.Errors.Count == 2
    assert harness.Errors[1].Message == "Field 'Total' is readonly — constructors can only assign readonly fields on the current instance"
    assert harness.Errors[1].Suggestion == "Assign the current instance field directly, or remove `readonly` if other instances must be mutated."
}

test "a MUTABLE field and a PROPERTY of the same name both end the search with no report" {
    harness := WriteTargetHarnessOf()
    WriteTargetEnterClass(harness, WriteTargetClassWith("Widget", "count", Modifiers.None))
    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert harness.Errors.Count == 0
    // NOT A VACUOUS SILENCE: the same ambient with the field marked `readonly` DOES report, so the
    // zero above is the modifier's doing rather than an empty member list's.
    control := WriteTargetHarnessOf()
    WriteTargetEnterClass(control, WriteTargetClassWith("Widget", "count", Modifiers.Readonly))
    control.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert control.Errors.Count == 1

    propertyMembers := new List<Declaration>()
    propertyMembers.Add(new PropertyDeclaration("count", new SimpleTypeReference("int", 2, 5), null, null, null, Modifiers.Readonly, PropertyModifier.None, new List<AttributeNode>(), 2, 5))
    withProperty := new ClassDeclaration("Widget", null, null, new List<TypeReference>(), propertyMembers, null, Modifiers.None, new List<AttributeNode>(), 1, 1)
    WriteTargetEnterClass(harness, withProperty)
    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert harness.Errors.Count == 0
}

test "the three readonly reports differ only in the sentence they end with" {
    harness := WriteTargetHarnessOf()
    WriteTargetEnterClass(harness, WriteTargetClassWith("Widget", "count", Modifiers.Readonly))

    assert harness.Targets.ReportReadonlyFieldRefOutArgumentIfNeeded(WriteTargetName("count"), "out", null)
    assert harness.Errors[0].Message == "Field 'count' is readonly — it can't be used as a out argument"

    unary := new UnaryExpression(UnaryOperator.PostIncrement, WriteTargetName("count"), 3, 5)
    assert harness.Targets.ReportReadonlyFieldIncrementOrDecrementIfNeeded(unary, null)
    assert harness.Errors[1].Message == "Field 'count' is readonly — it can't be changed with '++'"

    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert harness.Errors[2].Message == "Field 'count' is readonly — it can only be assigned in a constructor"
    assert WriteTargetCodes(harness.Errors) == "309,309,309"
}

// A STRUCT AND A RECORD REACH THE SAME RULE, AND THE CLASS SLOT IS NEVER FILLED FOR EITHER. This is
// the whole of the first NL309 hole this owner carried: the bare-name channel used to read
// `CurrentClass`, whose slot is typed `ClassDeclaration`, so a struct's or a record's own `readonly`
// field could not be found at all and all three reports were silent. Roslyn refuses the same write
// with `CS0191`.
test "a STRUCT's own readonly field is found through the member list alone, with no class declaration current" {
    harness := WriteTargetHarnessOf()
    structDeclaration := WriteTargetStructWith("Point", "count", Modifiers.Readonly)
    harness.Ambient.EnterTypeMembers(structDeclaration.Members)
    assert harness.Ambient.CurrentClass == null

    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Field 'count' is readonly — it can only be assigned in a constructor"

    unary := new UnaryExpression(UnaryOperator.PostIncrement, WriteTargetName("count"), 3, 5)
    assert harness.Targets.ReportReadonlyFieldIncrementOrDecrementIfNeeded(unary, null)
    assert harness.Targets.ReportReadonlyFieldRefOutArgumentIfNeeded(WriteTargetName("count"), "ref", null)
    assert WriteTargetCodes(harness.Errors) == "309,309,309"

    // And the constructor exemption still applies to the struct's OWN instance.
    exempt := WriteTargetHarnessOf()
    exempt.Ambient.EnterTypeMembers(WriteTargetStructWith("Point", "count", Modifiers.Readonly).Members)
    exempt.Ambient.EnterConstructor()
    exempt.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert exempt.Errors.Count == 0
}

// THE SECOND HOLE, FROM THE OTHER SIDE: a bare name a LOCAL or a PARAMETER binds is not the field,
// and the member list cannot tell. `this.count` is never a local and is therefore still reported.
test "a local or parameter binding the same name takes the write, and `this.` qualification is unaffected" {
    harness := WriteTargetHarnessOf()
    WriteTargetEnterClass(harness, WriteTargetClassWith("Widget", "count", Modifiers.Readonly))
    harness.Scopes.Push(new SemanticModel(), new Scope(ScopeKind.Function), 3, 1)
    WriteTargetDeclare(harness, "count", BuiltInTypes.Int)

    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert harness.Errors.Count == 0

    qualified := WriteTargetMember(new ThisExpression(3, 5), "count", false)
    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(qualified, 3, 5, null)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Field 'count' is readonly — it can only be assigned in a constructor"
}

test "with no enclosing class at all nothing is a readonly field target" {
    harness := WriteTargetHarnessOf()
    assert !harness.Targets.ReportReadonlyFieldRefOutArgumentIfNeeded(WriteTargetName("count"), "ref", null)
    harness.Targets.ReportReadonlyFieldAssignmentIfNeeded(WriteTargetName("count"), 3, 5, null)
    assert harness.Errors.Count == 0
}

test "a reflected initonly field is readonly and a mutable one is not" {
    harness := WriteTargetHarnessOf()
    probe: TypeInfo = new ReflectionTypeInfo(typeof(WriteTargetReadonlyProbe))

    resolvedName := ""
    assert harness.Targets.TryFindReadonlyInstanceField(probe, "Total", out resolvedName)
    assert resolvedName == "Total"

    assert !harness.Targets.TryFindReadonlyInstanceField(probe, "Mutable", out resolvedName)

    // A PROPERTY claims the name and answers no, which is what stops the base-type walk.
    assert !harness.Targets.TryFindReadonlyInstanceField(probe, "Named", out resolvedName)
}

// ---- rule 7: the instance-field classification -------------------------------------------------------

test "a field hop answers true, a property hop false, and an unknown receiver stays unresolved" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("probe")
    types := WriteTargetTypes()
    probe: TypeInfo = new ReflectionTypeInfo(typeof(WriteTargetReadonlyProbe))
    types[receiver] = probe

    isField := false
    fieldHop := WriteTargetMemberNode(receiver, "Mutable")
    resolvedField := harness.Targets.TryClassifyInstanceFieldHop(fieldHop, types, out isField)
    assert resolvedField
    assert isField

    propertyHop := WriteTargetMemberNode(receiver, "Named")
    resolvedProperty := harness.Targets.TryClassifyInstanceFieldHop(propertyHop, types, out isField)
    assert resolvedProperty
    assert !isField

    // AN UNRESOLVABLE OWNER IS NOT A "NO". Both callers read the RETURN as "stay silent", which is
    // what keeps the NL322 rule and the ref/out rule from firing on shapes they cannot prove.
    strangerHop := WriteTargetMemberNode(WriteTargetName("elsewhere"), "Mutable")
    resolvedStranger := harness.Targets.TryClassifyInstanceFieldHop(strangerHop, types, out isField)
    assert !resolvedStranger

    resolvedWithoutTable := harness.Targets.TryClassifyInstanceFieldHop(fieldHop, null, out isField)
    assert !resolvedWithoutTable
}

// ---- the capture table's key identity -----------------------------------------------------------------

test "the capture table is keyed by NODE IDENTITY, so two identical nodes are two entries" {
    first := WriteTargetName("a")
    second := WriteTargetName("a")
    types := WriteTargetTypes()
    types[first] = BuiltInTypes.Int
    types[second] = BuiltInTypes.String

    assert types.Count == 2
    firstType: TypeInfo = BuiltInTypes.Unknown
    assert types.TryGetValue(first, out firstType)
    assert BuiltInTypes.Is(firstType, BuiltInTypes.Int)
    secondType: TypeInfo = BuiltInTypes.Unknown
    assert types.TryGetValue(second, out secondType)
    assert BuiltInTypes.Is(secondType, BuiltInTypes.String)
}

test "the ambient write-target slot opens, records, answers and closes" {
    harness := WriteTargetHarnessOf()
    assert !harness.Ambient.InWriteTarget
    assert harness.Ambient.WriteTargetExpressionTypes == null

    // Recording with no table open is a no-op rather than an error.
    harness.Ambient.RecordWriteTargetExpressionType(WriteTargetName("a"), BuiltInTypes.Int)

    saved := harness.Ambient.EnterWriteTargetExpressionTypes()
    assert saved == null
    assert harness.Ambient.InWriteTarget

    node := WriteTargetName("b")
    harness.Ambient.RecordWriteTargetExpressionType(node, BuiltInTypes.String)
    table := harness.Ambient.WriteTargetExpressionTypes
    assert table != null
    assert table.Count == 1

    inner := harness.Ambient.EnterWriteTargetExpressionTypes()
    assert inner != null
    assert harness.Ambient.WriteTargetExpressionTypes.Count == 0
    harness.Ambient.ExitWriteTargetExpressionTypes(inner)
    assert harness.Ambient.WriteTargetExpressionTypes.Count == 1

    harness.Ambient.ClearWriteTargetExpressionTypes()
    assert !harness.Ambient.InWriteTarget
}

// ---- rule 8: the static-field mirror and the ref/out addressability rule --------------------------
//
// (8) THE STATIC MIRROR IS THE SAME QUESTION AT A DIFFERENT BINDING. It answers `true` for a static
// FIELD, `false` for anything else that CLAIMS the name statically, and "unresolved" for an owner it
// cannot read at all — which is the same three-way answer rule 7 gives and the same `Try` shape, for
// the same language reason.
//
// (9) ADDRESSABILITY IS THIS FAMILY'S, NOT THE CALL ARM'S. `ref x` and `out x` hand a callee the
// right to STORE, so "may this be written through" is exactly the question. A bare name always may;
// a member hop may when the chain stays rooted in storage; an array ELEMENT may and a SLICE may not;
// and a receiver the rule cannot prove anything about is left ADDRESSABLE rather than refused.

test "a bare name is always addressable, and parentheses are transparent" {
    harness := WriteTargetHarnessOf()
    types := WriteTargetTypes()

    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetName("total"), types)
    parenthesized: Expression = new ParenthesizedExpression(WriteTargetName("total"), 3, 4)
    assert harness.Targets.IsRefOutArgumentTarget(parenthesized, types)
}

test "a call result and a literal are NOT addressable" {
    harness := WriteTargetHarnessOf()
    types := WriteTargetTypes()
    arguments := new List<Argument>()
    call: Expression = new CallExpression(WriteTargetName("f"), arguments, null, 3, 5)

    assert !harness.Targets.IsRefOutArgumentTarget(call, types)
    assert !harness.Targets.IsRefOutArgumentTarget(WriteTargetInt("1"), types)
}

test "NO CAPTURE TABLE MEANS DO NOT REFUSE — every shape is addressable without one" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("holder")
    member := WriteTargetMember(receiver, "Origin", false)
    indexed := WriteTargetIndex(receiver, WriteTargetInt("0"), false)

    assert harness.Targets.IsRefOutArgumentTarget(member, null)
    assert harness.Targets.IsRefOutArgumentTarget(indexed, null)
}

test "an ARRAY ELEMENT is addressable and a SLICE is not" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("values")
    WriteTargetDeclare(harness, "values", new ArrayTypeInfo(BuiltInTypes.Int))
    types := WriteTargetTypes()
    types[receiver] = new ArrayTypeInfo(BuiltInTypes.Int)

    elementIndex := WriteTargetInt("0")
    types[elementIndex] = BuiltInTypes.Int
    element := WriteTargetIndex(receiver, elementIndex, false)
    assert harness.Targets.IsRefOutArgumentTarget(element, types)

    slice := WriteTargetIndex(receiver, WriteTargetRange(), false)
    assert !harness.Targets.IsRefOutArgumentTarget(slice, types)
}

test "A RANGE-TYPED index refuses even when it is not WRITTEN as a range" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("values")
    types := WriteTargetTypes()
    types[receiver] = new ArrayTypeInfo(BuiltInTypes.Int)
    disguised := WriteTargetName("span")
    types[disguised] = new SimpleTypeInfo("System.Range")

    assert !harness.Targets.IsRefOutArgumentTarget(WriteTargetIndex(receiver, disguised, false), types)
}

test "a System.Index index into an array IS addressable, and a string index is NOT" {
    harness := WriteTargetHarnessOf()
    arrayReceiver := WriteTargetName("values")
    types := WriteTargetTypes()
    types[arrayReceiver] = new ArrayTypeInfo(BuiltInTypes.Int)
    hat := WriteTargetName("hat")
    types[hat] = new SimpleTypeInfo("System.Index")
    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetIndex(arrayReceiver, hat, false), types)

    textReceiver := WriteTargetName("text")
    types[textReceiver] = BuiltInTypes.String
    textIndex := WriteTargetInt("0")
    types[textIndex] = BuiltInTypes.Int
    assert !harness.Targets.IsRefOutArgumentTarget(WriteTargetIndex(textReceiver, textIndex, false), types)
}

test "an array receiver with an INDEX TYPE the table never recorded stays addressable" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("values")
    types := WriteTargetTypes()
    types[receiver] = new ArrayTypeInfo(BuiltInTypes.Int)

    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetIndex(receiver, WriteTargetInt("0"), false), types)
}

test "an index whose RECEIVER the table never recorded stays addressable" {
    harness := WriteTargetHarnessOf()
    types := WriteTargetTypes()

    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetIndex(WriteTargetName("mystery"), WriteTargetInt("0"), false), types)
}

test "a SoA TABLE's own member is refused where a ROW VIEW's COLUMN is addressable" {
    harness := WriteTargetHarnessOf()
    table := WriteTargetTable("Points", "x")
    receiver := WriteTargetName("points")
    WriteTargetDeclare(harness, "points", table)
    types := WriteTargetTypes()
    types[receiver] = table
    assert !harness.Targets.IsRefOutArgumentTarget(WriteTargetMember(receiver, "x", false), types)

    rowReceiver := WriteTargetName("row")
    WriteTargetDeclare(harness, "row", table)
    rowTypes := WriteTargetTypes()
    rowTypes[rowReceiver] = new SoaRowTypeInfo(table.Declaration)
    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetMember(rowReceiver, "x", false), rowTypes)

    // A NAME THE ROW DOES NOT DECLARE falls through to the instance classification, which cannot
    // resolve a row view's members at all — and an UNRESOLVED owner is deliberately PERMISSIVE rather
    // than a refusal, which is the same rule rule 7 states and the one place it is observable here.
    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetMember(rowReceiver, "notAColumn", false), rowTypes)
}

test "an INSTANCE field hop is addressable and a PROPERTY hop is not" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("probe")
    WriteTargetDeclare(harness, "probe", new ReflectionTypeInfo(typeof(WriteTargetReadonlyProbe)))
    types := WriteTargetTypes()
    types[receiver] = new ReflectionTypeInfo(typeof(WriteTargetReadonlyProbe))

    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetMember(receiver, "Mutable", false), types)
    assert !harness.Targets.IsRefOutArgumentTarget(WriteTargetMember(receiver, "Named", false), types)
}

test "a STATIC field hop is addressable and a STATIC PROPERTY hop is not" {
    harness := WriteTargetHarnessOf()
    // AN UNDECLARED RECEIVER IS READ AS A TYPE NAME, which is exactly what a static member access is.
    receiver := WriteTargetName("DateTime")
    types := WriteTargetTypes()
    types[receiver] = new ReflectionTypeInfo(typeof(DateTime))

    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetMember(receiver, "MaxValue", false), types)
    assert !harness.Targets.IsRefOutArgumentTarget(WriteTargetMember(receiver, "Now", false), types)
}

test "the STATIC classifier is a three-way answer, exactly as its instance twin is" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("DateTime")
    types := WriteTargetTypes()
    types[receiver] = new ReflectionTypeInfo(typeof(DateTime))

    isStatic := false
    resolvedField := harness.Targets.TryClassifyStaticFieldHop(WriteTargetMemberNode(receiver, "MaxValue"), types, out isStatic)
    assert resolvedField
    assert isStatic

    resolvedProperty := harness.Targets.TryClassifyStaticFieldHop(WriteTargetMemberNode(receiver, "Now"), types, out isStatic)
    assert resolvedProperty
    assert !isStatic

    // AN OWNER THE TABLE NEVER RECORDED IS UNRESOLVED, not a "no".
    resolvedStranger := harness.Targets.TryClassifyStaticFieldHop(WriteTargetMemberNode(WriteTargetName("elsewhere"), "MaxValue"), types, out isStatic)
    assert !resolvedStranger

    resolvedWithoutTable := harness.Targets.TryClassifyStaticFieldHop(WriteTargetMemberNode(receiver, "MaxValue"), null, out isStatic)
    assert !resolvedWithoutTable
}

test "the reflected static walk finds an INHERITED static field and stops at a claimed name" {
    assert AnalyzerWriteTargets.IsReflectedStaticField(typeof(string), "Empty")
    assert !AnalyzerWriteTargets.IsReflectedStaticField(typeof(string), "Length")
    assert !AnalyzerWriteTargets.IsReflectedStaticField(typeof(string), "NoSuchMemberAnywhere")

    // THE MIRROR IS EXACT: the same name is an INSTANCE field to neither and a static field to one.
    assert !AnalyzerWriteTargets.IsReflectedInstanceField(typeof(string), "Empty")
}

test "an UNRESOLVED static owner leaves the target ADDRESSABLE rather than refused" {
    harness := WriteTargetHarnessOf()
    receiver := WriteTargetName("Unknowable")
    types := WriteTargetTypes()
    types[receiver] = new SimpleTypeInfo("Unknowable")

    assert harness.Targets.IsRefOutArgumentTarget(WriteTargetMember(receiver, "Anything", false), types)
}
