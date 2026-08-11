namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT AN ATTRIBUTE MEANS.
//
// The forty-eight members this replaces were all `private` in `Analyzer.cs` and nothing in `src/`,
// `tests/` or `editors/` named any of them, so their behaviour was pinned only through whichever
// end-to-end diagnostic a bad attribute happened to produce. This is their first DIRECT pinning, and
// it is written around the six things this family is easy to get wrong.
//
// (1) THE TWO ARGUMENT TABLES ARE NOT ONE TABLE. Question one answers a coarse KIND over a closed
// family; question four answers a metadata `Type`. They disagree deliberately on `null` (kind
// `Null`, type `object` WITH `isNull` set) and on `typeof` (kind `Type`, type the well-known
// `System.Type`). Folding them together would change which constructor a null argument matches.
//
// (2) THE FOUR-WAY ATTRIBUTE-TYPE DECISION IS ORDERED. CLR attribute, then CLR non-attribute, then
// source-declared (split again by whether it derives from `Attribute`), then not found. Reordering
// changes which sentence a developer reads for the same program.
//
// (3) A REFUSED OPERATOR STILL ANSWERS ITS OPERAND'S KIND. That is what keeps a nested refusal from
// being reported twice, and it is the one thing a naive port drops.
//
// (4) `null` IS COMPATIBLE WITH A PARAMETER, NOT WITH A TYPE. Compatibility for a null argument is
// decided by the PARAMETER alone — anything that is not a non-nullable value type takes it.
//
// (5) AN ARRAY'S ELEMENTS ARE ALL MEASURED EVEN AFTER ONE FAILS, and `null` elements are SKIPPED
// when fixing the element kind — in BOTH tables, for the same reason.
//
// (6) THE SYSTEMS-POLICY NAMES ARE NEVER RESOLVED AS TYPES, and a DOTTED name is never one of them.
//
// TWO HONEST LIMITS OF A CONTRACT HARNESS, BOTH INHERITED FROM SLICE 63 AND BOTH RECORDED RATHER
// THAN PAPERED OVER. The well-known-type bag is absent without a `MetadataLoadContext`, so the
// BUILT-IN KEYWORD probe (`int.MaxValue`) declines here while naming a type in production; the
// EXTERNAL probe is exercised instead, against the core library the harness hands it. And
// `AnalyzerClrTypeConversion` is built with a null well-known bag, so the literal table answers
// through the reflection door rather than through the metadata one.
class AttributeHarness {
    Validator: AnalyzerAttributeValidator
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Context: AnalyzerDeclarationContext
    Model: SemanticModel

    constructor(validator: AnalyzerAttributeValidator, errors: List<CompilerError>, scopes: AnalyzerScopeStack, context: AnalyzerDeclarationContext, model: SemanticModel) {
        Validator = validator
        Errors = errors
        Scopes = scopes
        Context = context
        Model = model
    }
}

func AttributePath(): string {
    return Path.GetFullPath("attribute-contract.nl")
}

func AttributeHarnessOf(errors: List<CompilerError>): AttributeHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    namespaces := new List<string>()
    usingAliases := new Dictionary<string, string>(StringComparer.Ordinal)
    importedSymbols := new Dictionary<string, Dictionary<string, TypeInfo> >(StringComparer.Ordinal)
    importedDeclarations := new Dictionary<string, Dictionary<string, SymbolDeclaration> >(StringComparer.Ordinal)
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, usingAliases)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    sink := new AnalyzerDiagnosticSink(errors, provider)
    sink.BeginAnalysis(AttributePath(), null)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, usingAliases, importedSymbols, importedDeclarations, model, bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    assignability := new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
    spans := new AnalyzerDiagnosticSpans(sink)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    extensions := new List<FunctionDeclaration>()
    extensionResolution := new AnalyzerExtensionMethodResolution(resolver, assignability, context, functionTypes, clrConversion, extensions, namespaces, assemblies)
    members := new AnalyzerMemberResolution(functionTypes, context, substitution, resolver, clrConversion, extensionResolution, namespaces)
    soaEscape := new AnalyzerSoaEscape(sink, spans, scopes, context)
    ambient := new AnalyzerAmbientContext(sink, spans, soaEscape)
    nullFlow := new AnalyzerNullFlow(sink, spans, scopes, context)
    identifierResolution := new AnalyzerIdentifierResolution(sink, scopes, resolver, discovery, probe, functionTypes, ambient, nullFlow, extensions, members, model, bindings)
    memberAccess := new AnalyzerMemberAccess(sink, spans, scopes, context, nullFlow, soaEscape, ambient, provider, discovery, probe, substitution, identifierResolution, extensions, namespaces, usingAliases, importedSymbols, importedDeclarations, assemblies, members, clrConversion, extensionResolution, bindings)
    literals := new AnalyzerLiteralExpressions(ambient, context, soaEscape)
    owner := new AnalyzerAttributeValidator(sink, spans, scopes, context, probe, resolver, memberAccess, literals, clrConversion, null)
    return new AttributeHarness(owner, errors, scopes, context, model)
}

func AttributeHarnessNew(): AttributeHarness {
    return AttributeHarnessOf(new List<CompilerError>())
}

// ── AST builders ───────────────────────────────────────────────────────────────

func AttrId(name: string): Expression {
    return new IdentifierExpression(name, 4, 9)
}

func AttrInt(text: string): Expression {
    return new IntLiteralExpression(text, 4, 9)
}

func AttrString(text: string): Expression {
    return new StringLiteralExpression(text, 4, 9)
}

func AttrBool(value: bool): Expression {
    return new BoolLiteralExpression(value, 4, 9)
}

func AttrNull(): Expression {
    return new NullLiteralExpression(4, 9)
}

func AttrMember(receiver: Expression, name: string, nullConditional: bool): MemberAccessExpression {
    return new MemberAccessExpression(receiver, name, nullConditional, 4, 11)
}

func AttrDotted(owner: string, name: string): MemberAccessExpression {
    return AttrMember(AttrId(owner), name, false)
}

func AttrArray(elements: List<Expression>): Expression {
    return new ArrayLiteralExpression(elements, false, 4, 9)
}

func AttrElements(): List<Expression> {
    return new List<Expression>()
}

func AttrUnary(op: UnaryOperator, operand: Expression): Expression {
    return new UnaryExpression(op, operand, 4, 9)
}

func AttrBinary(left: Expression, op: BinaryOperator, right: Expression): Expression {
    return new BinaryExpression(left, op, right, 4, 9)
}

func AttrArgs(): List<Argument> {
    return new List<Argument>()
}

func AttrArg(arguments: List<Argument>, value: Expression, name: string?) {
    arguments.Add(new Argument(name, value, ArgumentModifier.None))
}

func AttrNode(name: string, arguments: List<Argument>): AttributeNode {
    return new AttributeNode(name, arguments, 3, 1)
}

func AttrNodes(node: AttributeNode): List<AttributeNode> {
    nodes := new List<AttributeNode>()
    nodes.Add(node)
    return nodes
}

func AttrNoTypeReferences(): TypeReference[] {
    return new TypeReference[](0)
}

func AttrNoTypeParameters(): TypeParameter[] {
    return new TypeParameter[](0)
}

func AttrNoParameters(): ParameterDeclarationInfo[] {
    return new ParameterDeclarationInfo[](0)
}

func AttrNoMembers(): DeclaredMemberInfo[] {
    return new DeclaredMemberInfo[](0)
}

func AttrNoNestedTypes(): NestedTypeInfo[] {
    return new NestedTypeInfo[](0)
}

func AttrClass(name: string, baseClass: TypeReference?): ClassTypeInfo {
    return new ClassTypeInfo(name, 1, 1, false, baseClass, AttrNoTypeReferences(), AttrNoTypeParameters(), AttrNoParameters(), AttrNoMembers(), AttrNoNestedTypes(), true)
}

func AttrInterface(name: string): InterfaceTypeInfo {
    return new InterfaceTypeInfo(name, 1, 1, false, AttrNoTypeReferences(), AttrNoTypeParameters(), AttrNoMembers(), AttrNoNestedTypes())
}

func AttrEnum(name: string, memberName: string): EnumTypeInfo {
    members := new List<EnumMemberInfo>()
    members.Add(new EnumMemberInfo(memberName, 1, 1, EnumMemberValueKind.None, null))
    declaration := new EnumDeclarationInfo(name, members, EnumType.Int, 1, 1)
    return new EnumTypeInfo(declaration)
}

// A type the scope stack can find by name. The scope is bound to a local first: the recorded
// chained-write gotcha refuses `stack.Peek().Types[k] = v`.
func AttrDeclare(harness: AttributeHarness, name: string, declared: TypeInfo) {
    types := harness.Scopes.Peek().Types
    types[name] = declared
}

// `typeof(T[])`, `typeof(T?)` and `typeof(SomeEnum)` decline as CALL ARGUMENTS; the reflection door
// names the same runtime types and binds them to a local, which emits.
func AttrRuntimeType(name: string): Type {
    candidate := Type.GetType(name)
    if candidate == null {
        return typeof(object)
    }

    resolved: Type = candidate
    return resolved
}

func AttrTargets(): Type {
    return AttrRuntimeType("System.AttributeTargets")
}

// A registered FILE, which is what makes a written base-type reference resolvable: the declaration
// context resolves a base against its declaring file's facts, and a file it has never been handed
// resolves nothing at all.
func AttrRegisterFile(harness: AttributeHarness) {
    unit := new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1)
    harness.Context.AddCompilationUnit(AttributePath(), unit)
}

func AttrObsolete(): Type {
    return AttrRuntimeType("System.ObsoleteAttribute")
}

func AttrAttributeBase(): Type {
    return AttrRuntimeType("System.Attribute")
}

func AttrArrayOf(elementType: Type): Type {
    return elementType.MakeArrayType()
}

func AttrNullableOf(valueType: Type): Type {
    arguments := new Type[](1)
    arguments[0] = valueType
    candidate := Type.GetType("System.Nullable`1")
    if candidate == null {
        return valueType
    }

    definition: Type = candidate
    return definition.MakeGenericType(arguments)
}

func AttrParameterWith(node: AttributeNode): List<Parameter> {
    parameters := new List<Parameter>()
    parameters.Add(new Parameter("value", new SimpleTypeReference("int", 5, 20), null, false, ParameterModifier.None, AttrNodes(node), 5, 20, false, null))
    return parameters
}

// ── answer renderers ───────────────────────────────────────────────────────────

// The KIND an argument answers, or "<refused>" when it is not a constant — which is the whole answer
// question one gives, in one string.
func AttrKind(harness: AttributeHarness, expression: Expression): string {
    kind := AttributeArgumentConstantKind.Null
    if !harness.Validator.TryValidateAttributeArgumentExpression(expression, out kind) {
        return "<refused>"
    }

    return AttrKindText(kind)
}

// The kind by NAME. An enum's own `ToString` is not on the columnar catalog, and naming the ten
// members out loud is what a contract wants anyway — a renumbered enum must not silently pass.
func AttrKindText(kind: AttributeArgumentConstantKind): string {
    if kind == AttributeArgumentConstantKind.Null {
        return "Null"
    }

    if kind == AttributeArgumentConstantKind.Bool {
        return "Bool"
    }

    if kind == AttributeArgumentConstantKind.Integer {
        return "Integer"
    }

    if kind == AttributeArgumentConstantKind.Floating {
        return "Floating"
    }

    if kind == AttributeArgumentConstantKind.Char {
        return "Char"
    }

    if kind == AttributeArgumentConstantKind.String {
        return "String"
    }

    if kind == AttributeArgumentConstantKind.Type {
        return "Type"
    }

    if kind == AttributeArgumentConstantKind.Enum {
        return "Enum"
    }

    if kind == AttributeArgumentConstantKind.Array {
        return "Array"
    }

    return "UnknownStaticMember"
}

// The CLR type an argument answers, or "<none>" when it names none. The null flag is appended
// because it is half the answer and the two are never read apart.
func AttrClrType(harness: AttributeHarness, expression: Expression): string {
    clrType: Type = typeof(object)
    isNull := false
    if !harness.Validator.TryInferAttributeArgumentClrType(expression, out clrType, out isNull) {
        return "<none>"
    }

    name := clrType.get_FullName()
    if name == null {
        name = clrType.get_Name()
    }

    if isNull {
        return name + "+null"
    }

    return name
}

func AttrCodes(errors: List<CompilerError>): string {
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

func AttrCandidates(name: string): string {
    return string.Join(",", AnalyzerAttributeValidator.GetClrAttributeNameCandidates(name))
}

// ── the systems-policy silence ────────────────────────────────────────────────

test "every systems-policy name is refused as an attribute type before any resolution" {
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("hot", AttrArgs()))
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("boundary", AttrArgs()))
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("alloc", AttrArgs()))
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("allow", AttrArgs()))
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("trusted", AttrArgs()))
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("memory", AttrArgs()))
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("aotSafe", AttrArgs()))
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("MustUse", AttrArgs()))
}

test "a policy name spelled with the Attribute suffix is still a policy name" {
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("hotAttribute", AttrArgs()))
    assert AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("MustUseAttribute", AttrArgs()))
}

test "a DOTTED name is never a policy name however it ends" {
    assert !AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("Foo.hot", AttrArgs()))
    assert !AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("System.MustUse", AttrArgs()))
}

test "a name that merely resembles a policy name is not one" {
    assert !AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("hotpath", AttrArgs()))
    assert !AnalyzerAttributeValidator.IsSystemsPolicyAttribute(AttrNode("Obsolete", AttrArgs()))
}

test "a policy attribute's arguments are never measured, however unconstant they are" {
    harness := AttributeHarnessNew()
    arguments := AttrArgs()
    AttrArg(arguments, AttrId("safe"), null)
    AttrArg(arguments, AttrString("bounds checked"), "reason")

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("allow", arguments)))

    assert harness.Errors.Count == 0
}

// ── the named-argument spelling ───────────────────────────────────────────────

test "a colon-named argument keeps its name and its value" {
    argumentName: string? = null
    valueExpression: Expression = AttrNull()
    AnalyzerAttributeValidator.NormalizeAttributeArgument(new Argument("reason", AttrString("why"), ArgumentModifier.None), out argumentName, out valueExpression)

    assert argumentName == "reason"
    assert valueExpression is StringLiteralExpression
}

test "an assignment to a bare identifier BECOMES a named argument" {
    assignment := new AssignmentExpression(AttrId("DiagnosticId"), AssignmentOperator.Assign, AttrString("NL1"), 4, 9)
    argumentName: string? = null
    valueExpression: Expression = AttrNull()
    AnalyzerAttributeValidator.NormalizeAttributeArgument(new Argument(null, assignment, ArgumentModifier.None), out argumentName, out valueExpression)

    assert argumentName == "DiagnosticId"
    assert valueExpression is StringLiteralExpression
}

test "an assignment to anything OTHER than a bare identifier stays positional" {
    assignment := new AssignmentExpression(AttrDotted("a", "b"), AssignmentOperator.Assign, AttrString("NL1"), 4, 9)
    argumentName: string? = null
    valueExpression: Expression = AttrNull()
    AnalyzerAttributeValidator.NormalizeAttributeArgument(new Argument(null, assignment, ArgumentModifier.None), out argumentName, out valueExpression)

    assert argumentName == null
    assert valueExpression is AssignmentExpression
}

// ── the dotted name an expression spells ──────────────────────────────────────

test "an identifier spells its own name" {
    name := ""
    assert AnalyzerAttributeValidator.TryGetQualifiedName(AttrId("Colors"), out name)
    assert name == "Colors"
}

test "a member-access chain spells a dotted name, outermost last" {
    name := ""
    inner := AttrDotted("System", "AttributeTargets")
    assert AnalyzerAttributeValidator.TryGetQualifiedName(AttrMember(inner, "Class", false), out name)
    assert name == "System.AttributeTargets.Class"
}

test "a NULL-CONDITIONAL link spells nothing" {
    name := "unset"
    assert !AnalyzerAttributeValidator.TryGetQualifiedName(AttrMember(AttrId("a"), "b", true), out name)
    assert name == ""
}

test "an expression that is not a name spells nothing" {
    name := "unset"
    assert !AnalyzerAttributeValidator.TryGetQualifiedName(AttrInt("1"), out name)
    assert name == ""
}

// ── `nameof` targets ──────────────────────────────────────────────────────────

test "nameof admits a name and a dotted path of names" {
    assert AnalyzerAttributeValidator.IsSupportedNameofAttributeTarget(AttrId("Value"))
    assert AnalyzerAttributeValidator.IsSupportedNameofAttributeTarget(AttrDotted("Holder", "Value"))
}

test "nameof refuses a null-conditional link and a non-name" {
    assert !AnalyzerAttributeValidator.IsSupportedNameofAttributeTarget(AttrMember(AttrId("a"), "b", true))
    assert !AnalyzerAttributeValidator.IsSupportedNameofAttributeTarget(AttrInt("1"))
}

// ── QUESTION ONE: the literal kinds ───────────────────────────────────────────

test "every literal shape answers its own kind" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrInt("1")) == "Integer"
    assert AttrKind(harness, new FloatLiteralExpression("1.5", 4, 9)) == "Floating"
    assert AttrKind(harness, new CharLiteralExpression("c", 4, 9)) == "Char"
    assert AttrKind(harness, AttrString("s")) == "String"
    assert AttrKind(harness, AttrBool(true)) == "Bool"
    assert AttrKind(harness, AttrNull()) == "Null"
    assert harness.Errors.Count == 0
}

test "a typeof argument is a Type constant and resolves its written type reference" {
    harness := AttributeHarnessNew()
    typeOfExpression := new TypeOfExpression(new SimpleTypeReference("int", 4, 9), 4, 9)

    assert AttrKind(harness, typeOfExpression) == "Type"
    assert harness.Errors.Count == 0
}

test "a nameof over a supported target is a String constant" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, new NameofExpression(AttrDotted("Holder", "Value"), 4, 9)) == "String"
    assert harness.Errors.Count == 0
}

test "a nameof over an UNSUPPORTED target is refused and names the target" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, new NameofExpression(AttrInt("1"), 4, 9)) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ConstantRequired
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; nameof target is not supported here"
}

test "an argument the table does not name is refused and DESCRIBED" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrId("message")) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; identifier is not supported here"
    assert harness.Errors[0].Suggestion == "Use a literal, typeof(...), nameof(...), enum/static constant, or an array of those constants."
}

test "the description table names an identifier and a member access outright" {
    assert AnalyzerAttributeValidator.DescribeAttributeArgumentForDiagnostic(AttrId("x")) == "identifier"
    assert AnalyzerAttributeValidator.DescribeAttributeArgumentForDiagnostic(AttrDotted("a", "b")) == "member access"
}

// ── QUESTION ONE: arrays ──────────────────────────────────────────────────────

test "a uniform array is an Array constant" {
    harness := AttributeHarnessNew()
    elements := AttrElements()
    elements.Add(AttrString("a"))
    elements.Add(AttrString("b"))

    assert AttrKind(harness, AttrArray(elements)) == "Array"
    assert harness.Errors.Count == 0
}

test "a null element does NOT fix the element kind" {
    harness := AttributeHarnessNew()
    elements := AttrElements()
    elements.Add(AttrNull())
    elements.Add(AttrString("a"))
    elements.Add(AttrNull())

    assert AttrKind(harness, AttrArray(elements)) == "Array"
    assert harness.Errors.Count == 0
}

test "a mixed-type array names the OFFENDING element, once per offender" {
    harness := AttributeHarnessNew()
    elements := AttrElements()
    elements.Add(AttrString("a"))
    elements.Add(AttrInt("1"))
    elements.Add(AttrBool(true))

    assert AttrKind(harness, AttrArray(elements)) == "<refused>"
    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; mixed-type array element is not supported here"
    assert harness.Errors[1].Message == "Attribute arguments must be compile-time constants; mixed-type array element is not supported here"
}

test "every element is measured even after one fails" {
    harness := AttributeHarnessNew()
    elements := AttrElements()
    elements.Add(AttrId("first"))
    elements.Add(AttrId("second"))

    assert AttrKind(harness, AttrArray(elements)) == "<refused>"
    assert harness.Errors.Count == 2
}

test "an empty array is still an Array constant" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrArray(AttrElements())) == "Array"
    assert harness.Errors.Count == 0
}

// ── QUESTION ONE: operators ───────────────────────────────────────────────────

test "the three admissible unary operators keep their operand's kind" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrUnary(UnaryOperator.Negate, AttrInt("1"))) == "Integer"
    assert AttrKind(harness, AttrUnary(UnaryOperator.Negate, new FloatLiteralExpression("1.5", 4, 9))) == "Floating"
    assert AttrKind(harness, AttrUnary(UnaryOperator.Not, AttrBool(true))) == "Bool"
    assert AttrKind(harness, AttrUnary(UnaryOperator.BitwiseNot, AttrInt("1"))) == "Integer"
    assert harness.Errors.Count == 0
}

test "an admissible operator over the WRONG operand kind is refused and NAMES THE OPERATOR" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrUnary(UnaryOperator.Negate, AttrString("s"))) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; operator '-' is not supported here"
}

test "a unary over a REFUSED operand reports once, not twice" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrUnary(UnaryOperator.Negate, AttrId("x"))) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; identifier is not supported here"
}

test "the three bitwise operators combine two integers" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrBinary(AttrInt("1"), BinaryOperator.BitwiseOr, AttrInt("2"))) == "Integer"
    assert AttrKind(harness, AttrBinary(AttrInt("1"), BinaryOperator.BitwiseAnd, AttrInt("2"))) == "Integer"
    assert AttrKind(harness, AttrBinary(AttrInt("1"), BinaryOperator.BitwiseXor, AttrInt("2"))) == "Integer"
    assert harness.Errors.Count == 0
}

test "a NON-bitwise operator is refused and names itself" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrBinary(AttrString("v"), BinaryOperator.Add, AttrString("1"))) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; operator '+' is not supported here"
}

test "a bitwise operator over two STRINGS is refused after both were admitted as constants" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrBinary(AttrString("a"), BinaryOperator.BitwiseOr, AttrString("b"))) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; operator '|' is not supported here"
}

test "BOTH binary operands are measured even when the left one failed" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrBinary(AttrId("a"), BinaryOperator.BitwiseOr, AttrId("b"))) == "<refused>"
    assert harness.Errors.Count == 2
}

// ── QUESTION ONE: static member reads ─────────────────────────────────────────

test "a source enum member is an Enum constant" {
    harness := AttributeHarnessNew()
    AttrDeclare(harness, "Colors", AttrEnum("Colors", "Red"))

    assert AttrKind(harness, AttrDotted("Colors", "Red")) == "Enum"
    assert harness.Errors.Count == 0
}

test "an UNDEFINED source enum member is refused through the member-access reporter" {
    harness := AttributeHarnessNew()
    AttrDeclare(harness, "Colors", AttrEnum("Colors", "Red"))

    assert AttrKind(harness, AttrDotted("Colors", "Purple")) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedMember
}

test "an EXTERNAL static field read names its kind" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrMember(AttrDotted("System", "String"), "Empty", false)) == "String"
    assert harness.Errors.Count == 0
}

test "an UNDEFINED external static member is refused" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrMember(AttrDotted("System", "String"), "Missing", false)) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedMember
}

test "an EXTERNAL enum member is an Enum constant and an unknown one is refused" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrMember(AttrDotted("System", "AttributeTargets"), "Class", false)) == "Enum"
    assert AttrKind(harness, AttrMember(AttrDotted("System", "AttributeTargets"), "Nowhere", false)) == "<refused>"
    assert harness.Errors.Count == 1
}

test "a container that resolved to a non-enum source type is admitted as an unknown static member" {
    harness := AttributeHarnessNew()
    AttrDeclare(harness, "Holder", AttrClass("Holder", null))

    assert AttrKind(harness, AttrDotted("Holder", "Value")) == "UnknownStaticMember"
    assert harness.Errors.Count == 0
}

test "a container that resolved to NOTHING is refused as a member access" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrDotted("Nowhere", "Value")) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; member access is not supported here"
}

test "a member access whose receiver spells no name is refused before any resolution" {
    harness := AttributeHarnessNew()

    assert AttrKind(harness, AttrMember(AttrInt("1"), "Value", false)) == "<refused>"
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Attribute arguments must be compile-time constants; member access is not supported here"
}

test "an UNRESOLVED static member paired with an integer still combines" {
    harness := AttributeHarnessNew()
    AttrDeclare(harness, "Holder", AttrClass("Holder", null))

    assert AttrKind(harness, AttrBinary(AttrDotted("Holder", "A"), BinaryOperator.BitwiseOr, AttrInt("1"))) == "Integer"
    assert harness.Errors.Count == 0
}

// ── the metadata kind table ───────────────────────────────────────────────────

test "the metadata kind table names every CLR shape attribute metadata admits" {
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(typeof(bool)) == AttributeArgumentConstantKind.Bool
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(typeof(int)) == AttributeArgumentConstantKind.Integer
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(typeof(long)) == AttributeArgumentConstantKind.Integer
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(typeof(double)) == AttributeArgumentConstantKind.Floating
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(typeof(char)) == AttributeArgumentConstantKind.Char
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(typeof(string)) == AttributeArgumentConstantKind.String
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(typeof(Type)) == AttributeArgumentConstantKind.Type
}

test "an array and an enum are decided by SHAPE, before the name table is read" {
    stringArray := AttrArrayOf(typeof(string))

    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(stringArray) == AttributeArgumentConstantKind.Array
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(AttrTargets()) == AttributeArgumentConstantKind.Enum
}

test "a CLR type outside the closed set is an unknown static member rather than an error" {
    assert AnalyzerAttributeValidator.ClassifyAttributeRuntimeType(typeof(object)) == AttributeArgumentConstantKind.UnknownStaticMember
}

test "the enum probe answers through IsEnum and a non-enum answers false" {
    assert AnalyzerAttributeValidator.IsRuntimeEnumType(AttrTargets())
    assert !AnalyzerAttributeValidator.IsRuntimeEnumType(typeof(int))
    assert !AnalyzerAttributeValidator.IsRuntimeEnumType(typeof(object))
}

// ── QUESTION TWO: what an attribute type IS ───────────────────────────────────

test "both candidate spellings are tried, written name FIRST" {
    assert AttrCandidates("Obsolete") == "Obsolete,ObsoleteAttribute"
}

test "a name that already ends in Attribute is tried ONCE" {
    assert AttrCandidates("ObsoleteAttribute") == "ObsoleteAttribute"
}

test "the base chain is walked by full name, so a derived attribute answers true" {
    assert AnalyzerAttributeValidator.IsClrAttributeType(AttrObsolete())
    assert AnalyzerAttributeValidator.IsClrAttributeType(AttrAttributeBase())
    assert !AnalyzerAttributeValidator.IsClrAttributeType(typeof(string))
    assert !AnalyzerAttributeValidator.IsClrAttributeType(typeof(object))
}

test "every source-declared shape is an attribute CANDIDATE, including ones that can never be one" {
    assert AnalyzerAttributeValidator.IsSourceDeclaredAttributeCandidate(AttrClass("C", null))
    assert AnalyzerAttributeValidator.IsSourceDeclaredAttributeCandidate(AttrInterface("I"))
    assert AnalyzerAttributeValidator.IsSourceDeclaredAttributeCandidate(AttrEnum("Colors", "Red"))
    assert !AnalyzerAttributeValidator.IsSourceDeclaredAttributeCandidate(BuiltInTypes.Unknown)
    assert !AnalyzerAttributeValidator.IsSourceDeclaredAttributeCandidate(BuiltInTypes.Int)
}

test "a CLR attribute type resolves and a CLR non-attribute type does not" {
    harness := AttributeHarnessNew()
    attributeType: Type = typeof(object)
    assert harness.Validator.TryResolveClrAttributeType("System.Obsolete", out attributeType)
    assert attributeType.get_FullName() == "System.ObsoleteAttribute"

    other: Type = typeof(object)
    assert !harness.Validator.TryResolveClrAttributeType("System.String", out other)
}

test "the non-attribute door resolves what the attribute door refused" {
    harness := AttributeHarnessNew()
    clrType: Type = typeof(object)

    assert harness.Validator.TryResolveNonAttributeClrAttributeCandidate("System.String", out clrType)
    assert clrType.get_FullName() == "System.String"
}

test "a name that resolves to nothing answers neither door" {
    harness := AttributeHarnessNew()
    attributeType: Type = typeof(object)
    nonAttributeType: Type = typeof(object)
    sourceType: TypeInfo = BuiltInTypes.Int

    assert !harness.Validator.TryResolveClrAttributeType("Nonexistent", out attributeType)
    assert !harness.Validator.TryResolveNonAttributeClrAttributeCandidate("Nonexistent", out nonAttributeType)
    assert !harness.Validator.TryResolveSourceAttributeCandidate("Nonexistent", out sourceType)
    assert BuiltInTypes.IsUnknown(sourceType)
}

test "a SOURCE class resolves through the source door, under both spellings" {
    harness := AttributeHarnessNew()
    AttrDeclare(harness, "MarkerAttribute", AttrClass("MarkerAttribute", null))

    first: TypeInfo = BuiltInTypes.Unknown
    second: TypeInfo = BuiltInTypes.Unknown
    assert harness.Validator.TryResolveSourceAttributeCandidate("Marker", out first)
    assert harness.Validator.TryResolveSourceAttributeCandidate("MarkerAttribute", out second)
}

test "a source class whose base is a CLR attribute derives from Attribute" {
    harness := AttributeHarnessNew()
    AttrRegisterFile(harness)
    harness.Context.RegisterCanonicalType(AttributePath(), "Attribute", new ReflectionTypeInfo(AttrAttributeBase()))
    declared := AttrClass("MarkerAttribute", new SimpleTypeReference("Attribute", 1, 1))
    harness.Context.RegisterCanonicalType(AttributePath(), "MarkerAttribute", declared)

    assert harness.Validator.SourceTypeDerivesFromAttribute(declared)
}

test "a source class with NO base does not derive from Attribute" {
    harness := AttributeHarnessNew()
    AttrRegisterFile(harness)
    declared := AttrClass("Plain", null)
    harness.Context.RegisterCanonicalType(AttributePath(), "Plain", declared)

    assert !harness.Validator.SourceTypeDerivesFromAttribute(declared)
    assert !harness.Validator.SourceTypeDerivesFromAttribute(BuiltInTypes.Int)
}

test "a reflection type answers the CLR question directly" {
    harness := AttributeHarnessNew()

    assert harness.Validator.SourceTypeDerivesFromAttribute(new ReflectionTypeInfo(AttrObsolete()))
    assert !harness.Validator.SourceTypeDerivesFromAttribute(new ReflectionTypeInfo(typeof(string)))
}

test "a base chain that CYCLES answers false rather than hanging" {
    harness := AttributeHarnessNew()
    AttrRegisterFile(harness)
    declared := AttrClass("SelfAttribute", new SimpleTypeReference("SelfAttribute", 1, 1))
    harness.Context.RegisterCanonicalType(AttributePath(), "SelfAttribute", declared)

    assert !harness.Validator.SourceTypeDerivesFromAttribute(declared)
}

// ── QUESTION TWO: the four sentences, in order ────────────────────────────────

test "an unknown attribute name is TOLD IT IS NOT FOUND, and told what to name instead" {
    harness := AttributeHarnessNew()

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("Nonexistent", AttrArgs())))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeNotFound
    assert harness.Errors[0].Message == "Attribute type 'Nonexistent' not found"
    assert harness.Errors[0].Suggestion == "Check the spelling, add the missing 'import', or define an attribute class named 'NonexistentAttribute'."
}

test "a CLR type that is not an attribute is told to derive, and named by its CLR name" {
    harness := AttributeHarnessNew()

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("System.String", AttrArgs())))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "Attribute type 'string!' must derive from System.Attribute"
}

test "a SOURCE attribute is told IL emission does not support it yet" {
    harness := AttributeHarnessNew()
    AttrRegisterFile(harness)
    harness.Context.RegisterCanonicalType(AttributePath(), "Attribute", new ReflectionTypeInfo(AttrAttributeBase()))
    declared := AttrClass("MarkerAttribute", new SimpleTypeReference("Attribute", 1, 1))
    harness.Context.RegisterCanonicalType(AttributePath(), "MarkerAttribute", declared)
    AttrDeclare(harness, "MarkerAttribute", declared)

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("Marker", AttrArgs())))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.FeatureNotImplemented
    assert harness.Errors[0].Message == "Source-defined attribute 'Marker' is not supported by IL emission yet"
}

test "a SOURCE class that is not an attribute is told to derive, and named by the TYPE" {
    harness := AttributeHarnessNew()
    AttrRegisterFile(harness)
    declared := AttrClass("Plain", null)
    harness.Context.RegisterCanonicalType(AttributePath(), "Plain", declared)
    AttrDeclare(harness, "Plain", declared)

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("Plain", AttrArgs())))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "Attribute type 'Plain' must derive from System.Attribute"
}

// ── QUESTION THREE: constructors and named members ────────────────────────────

test "a settable property and a settable field are both named members" {
    memberType: Type = typeof(object)
    assert AnalyzerAttributeValidator.TryGetSettableAttributeNamedMemberType(AttrObsolete(), "DiagnosticId", out memberType)
    assert memberType.get_FullName() == "System.String"
}

test "a member the attribute does not declare is not settable" {
    memberType: Type = typeof(string)
    assert !AnalyzerAttributeValidator.TryGetSettableAttributeNamedMemberType(AttrObsolete(), "Nonexistent", out memberType)
    assert memberType == typeof(object)
}

test "a GET-ONLY property is not a settable named member" {
    memberType: Type = typeof(object)
    assert !AnalyzerAttributeValidator.TryGetSettableAttributeNamedMemberType(AttrObsolete(), "Message", out memberType)
}

test "the constructor question is answered by arity and by argument types" {
    positional := new List<AttributeArgumentValidationInfo>()
    positional.Add(new AttributeArgumentValidationInfo(new Argument(null, AttrString("gone"), ArgumentModifier.None), null, AttrString("gone"), typeof(string), false))

    assert AnalyzerAttributeValidator.HasMatchingAttributeConstructor(AttrObsolete(), positional)
}

test "an argument of the WRONG type matches no constructor of the right arity" {
    positional := new List<AttributeArgumentValidationInfo>()
    positional.Add(new AttributeArgumentValidationInfo(new Argument(null, AttrInt("1"), ArgumentModifier.None), null, AttrInt("1"), typeof(int), false))

    assert !AnalyzerAttributeValidator.HasMatchingAttributeConstructor(AttrObsolete(), positional)
}

test "no constructor takes three positional arguments" {
    positional := new List<AttributeArgumentValidationInfo>()
    index := 0
    while index < 3 {
        positional.Add(new AttributeArgumentValidationInfo(new Argument(null, AttrString("x"), ArgumentModifier.None), null, AttrString("x"), typeof(string), false))
        index = index + 1
    }

    assert !AnalyzerAttributeValidator.HasMatchingAttributeConstructor(AttrObsolete(), positional)
}

test "null is compatible with a reference parameter and with a nullable one, never with a bare value type" {
    nullableInt := AttrNullableOf(typeof(int))

    assert AnalyzerAttributeValidator.IsAttributeArgumentCompatible(typeof(string), typeof(object), true)
    assert AnalyzerAttributeValidator.IsAttributeArgumentCompatible(nullableInt, typeof(object), true)
    assert !AnalyzerAttributeValidator.IsAttributeArgumentCompatible(typeof(int), typeof(object), true)
}

test "identity and assignability both satisfy a parameter" {
    assert AnalyzerAttributeValidator.IsAttributeArgumentCompatible(typeof(string), typeof(string), false)
    assert AnalyzerAttributeValidator.IsAttributeArgumentCompatible(typeof(object), typeof(string), false)
    assert !AnalyzerAttributeValidator.IsAttributeArgumentCompatible(typeof(int), typeof(string), false)
}

test "an ENUM parameter also takes its underlying integer, and a non-enum takes none" {
    assert AnalyzerAttributeValidator.IsAttributeArgumentCompatible(AttrTargets(), typeof(int), false)
    assert !AnalyzerAttributeValidator.IsAttributeArgumentCompatible(AttrTargets(), typeof(long), false)
    assert !AnalyzerAttributeValidator.IsAttributeArgumentCompatible(typeof(int), AttrArrayOf(typeof(int)), false)
}

test "arrays are compared element-wise under the same three rules" {
    strings := AttrArrayOf(typeof(string))
    objects := AttrArrayOf(typeof(object))
    targets := AttrArrayOf(AttrTargets())
    integers := AttrArrayOf(typeof(int))

    assert AnalyzerAttributeValidator.IsAttributeArgumentCompatible(strings, strings, false)
    assert AnalyzerAttributeValidator.IsAttributeArgumentCompatible(objects, strings, false)
    assert AnalyzerAttributeValidator.IsAttributeArgumentCompatible(targets, integers, false)
    assert !AnalyzerAttributeValidator.IsAttributeArgumentCompatible(integers, strings, false)
}

test "the display name is the full name" {
    assert AnalyzerAttributeValidator.GetAttributeDisplayName(AttrObsolete()) == "System.ObsoleteAttribute"
}

// ── QUESTION THREE: the three sentences ───────────────────────────────────────

test "an unknown named argument names the attribute and the argument" {
    harness := AttributeHarnessNew()
    arguments := AttrArgs()
    AttrArg(arguments, new AssignmentExpression(AttrId("Nonexistent"), AssignmentOperator.Assign, AttrInt("1"), 4, 9), null)

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("System.Obsolete", arguments)))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.UndefinedMember
    assert harness.Errors[0].Message == "Attribute 'System.ObsoleteAttribute' has no public settable property or field named 'Nonexistent'"
}

test "a named argument of the wrong type names BOTH types" {
    harness := AttributeHarnessNew()
    arguments := AttrArgs()
    AttrArg(arguments, AttrString("gone"), null)
    AttrArg(arguments, new AssignmentExpression(AttrId("DiagnosticId"), AssignmentOperator.Assign, AttrInt("1"), 4, 9), null)

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("System.Obsolete", arguments)))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.TypeMismatch
    assert harness.Errors[0].Message == "Attribute named argument 'DiagnosticId' on 'System.ObsoleteAttribute' expects 'string!' but got 'int'"
}

test "a settable named argument of the right type is silent" {
    harness := AttributeHarnessNew()
    arguments := AttrArgs()
    AttrArg(arguments, AttrString("gone"), null)
    AttrArg(arguments, new AssignmentExpression(AttrId("DiagnosticId"), AssignmentOperator.Assign, AttrString("NL1"), 4, 9), null)

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("System.Obsolete", arguments)))

    assert harness.Errors.Count == 0
}

test "no matching constructor names the count AND the types" {
    harness := AttributeHarnessNew()
    arguments := AttrArgs()
    AttrArg(arguments, AttrInt("1"), null)

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("System.Obsolete", arguments)))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.NoMatchingOverload
    assert harness.Errors[0].Message == "No constructor of attribute 'System.ObsoleteAttribute' accepts 1 positional argument(s) with these types: int"
}

test "ONE non-constant argument suppresses the constructor question entirely" {
    harness := AttributeHarnessNew()
    arguments := AttrArgs()
    AttrArg(arguments, AttrId("message"), null)
    AttrArg(arguments, AttrInt("1"), null)
    AttrArg(arguments, AttrInt("2"), null)

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("System.Obsolete", arguments)))

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.ConstantRequired
}

test "a matching one-argument constructor is silent" {
    harness := AttributeHarnessNew()
    arguments := AttrArgs()
    AttrArg(arguments, AttrString("gone"), null)

    harness.Validator.ValidateAttributeArguments(AttrNodes(AttrNode("System.Obsolete", arguments)))

    assert harness.Errors.Count == 0
}

// ── QUESTION FOUR: the CLR type of a constant ─────────────────────────────────

test "the literal table names a CLR type for every literal shape" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrInt("1")) == "System.Int32"
    assert AttrClrType(harness, AttrString("s")) == "System.String"
    assert AttrClrType(harness, AttrBool(true)) == "System.Boolean"
    assert AttrClrType(harness, new CharLiteralExpression("c", 4, 9)) == "System.Char"
}

test "null types as object AND carries the null flag — the two tables disagree here on purpose" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrNull()) == "System.Object+null"
    assert AttrKind(harness, AttrNull()) == "Null"
}

test "typeof types as System.Type while its KIND is Type" {
    harness := AttributeHarnessNew()
    typeOfExpression := new TypeOfExpression(new SimpleTypeReference("int", 4, 9), 4, 9)

    assert AttrClrType(harness, typeOfExpression) == "System.Type"
}

test "nameof types as a string" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, new NameofExpression(AttrId("Value"), 4, 9)) == "System.String"
}

test "an EXTERNAL enum member types as the ENUM, not as its underlying integer" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrMember(AttrDotted("System", "AttributeTargets"), "Class", false)) == "System.AttributeTargets"
}

test "an external static field types as its own declared type" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrMember(AttrDotted("System", "String"), "Empty", false)) == "System.String"
}

test "a member access whose container resolves to nothing names no type" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrDotted("Nowhere", "Value")) == "<none>"
}

test "a uniform array types as an array of its element type" {
    harness := AttributeHarnessNew()
    elements := AttrElements()
    elements.Add(AttrString("a"))
    elements.Add(AttrString("b"))

    assert AttrClrType(harness, AttrArray(elements)) == "System.String[]"
}

test "an array that is empty or all nulls types as object[]" {
    harness := AttributeHarnessNew()
    nulls := AttrElements()
    nulls.Add(AttrNull())

    assert AttrClrType(harness, AttrArray(AttrElements())) == "System.Object[]"
    assert AttrClrType(harness, AttrArray(nulls)) == "System.Object[]"
}

test "a mixed-type array names no type" {
    harness := AttributeHarnessNew()
    elements := AttrElements()
    elements.Add(AttrString("a"))
    elements.Add(AttrInt("1"))

    assert AttrClrType(harness, AttrArray(elements)) == "<none>"
}

test "a unary constant keeps its operand's type, and only over the admissible shapes" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrUnary(UnaryOperator.Negate, AttrInt("1"))) == "System.Int32"
    assert AttrClrType(harness, AttrUnary(UnaryOperator.Not, AttrBool(true))) == "System.Boolean"
    assert AttrClrType(harness, AttrUnary(UnaryOperator.BitwiseNot, AttrInt("1"))) == "System.Int32"
    assert AttrClrType(harness, AttrUnary(UnaryOperator.Negate, AttrString("s"))) == "<none>"
    assert AttrClrType(harness, AttrUnary(UnaryOperator.Not, AttrInt("1"))) == "<none>"
}

test "a NULL operand types nothing at all" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrUnary(UnaryOperator.Negate, AttrNull())) == "<none>"
}

test "a bitwise combination keeps its operands' SHARED type and refuses a mismatch" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrBinary(AttrInt("1"), BinaryOperator.BitwiseOr, AttrInt("2"))) == "System.Int32"
    assert AttrClrType(harness, AttrBinary(AttrInt("1"), BinaryOperator.BitwiseOr, AttrString("a"))) == "<none>"
    assert AttrClrType(harness, AttrBinary(AttrString("a"), BinaryOperator.BitwiseOr, AttrString("b"))) == "<none>"
}

test "a NON-bitwise operator names no type whatever its operands are" {
    harness := AttributeHarnessNew()

    assert AttrClrType(harness, AttrBinary(AttrInt("1"), BinaryOperator.Add, AttrInt("2"))) == "<none>"
}

test "two EXTERNAL enum members combine to the enum type" {
    harness := AttributeHarnessNew()
    left := AttrMember(AttrDotted("System", "AttributeTargets"), "Class", false)
    right := AttrMember(AttrDotted("System", "AttributeTargets"), "Struct", false)

    assert AttrClrType(harness, AttrBinary(left, BinaryOperator.BitwiseOr, right)) == "System.AttributeTargets"
}

test "the CLR-type identity probe admits identity and full-name equality" {
    assert AnalyzerAttributeValidator.IsClrType(typeof(int), typeof(int))
    assert !AnalyzerAttributeValidator.IsClrType(typeof(int), typeof(long))
}

test "the static member-type probe reads a field, a property, and answers object for neither" {
    fieldType: Type = typeof(object)
    propertyType: Type = typeof(object)
    missingType: Type = typeof(string)

    assert AnalyzerAttributeValidator.TryGetRuntimeStaticAttributeMemberType(typeof(string), "Empty", out fieldType)
    assert fieldType.get_FullName() == "System.String"
    assert AnalyzerAttributeValidator.TryGetRuntimeStaticAttributeMemberType(AttrRuntimeType("System.DateTime"), "Now", out propertyType)
    assert propertyType.get_FullName() == "System.DateTime"
    assert !AnalyzerAttributeValidator.TryGetRuntimeStaticAttributeMemberType(typeof(string), "Nonexistent", out missingType)
    assert missingType == typeof(object)
}

// ── the two shared enum-member probes ─────────────────────────────────────────

test "the source enum-member probe answers by name, ordinally" {
    members := new List<EnumMemberInfo>()
    members.Add(new EnumMemberInfo("Red", 1, 1, EnumMemberValueKind.None, null))
    declared := new EnumTypeInfo(new EnumDeclarationInfo("Colors", members, EnumType.Int, 1, 1))

    assert TypeInfoIdentityFacts.HasSourceEnumMember(declared, "Red")
    assert !TypeInfoIdentityFacts.HasSourceEnumMember(declared, "red")
    assert !TypeInfoIdentityFacts.HasSourceEnumMember(declared, "Purple")
}

test "the runtime enum-member probe reads public statics only" {
    assert TypeInfoIdentityFacts.HasRuntimeEnumMember(AttrTargets(), "Class")
    assert !TypeInfoIdentityFacts.HasRuntimeEnumMember(AttrTargets(), "Nowhere")
    assert !TypeInfoIdentityFacts.HasRuntimeEnumMember(AttrTargets(), "value__")
}

// ── the declaration forms that carry attributes ───────────────────────────────

test "a function's OWN attributes and its PARAMETERS' attributes are both validated" {
    harness := AttributeHarnessNew()
    parameters := AttrParameterWith(AttrNode("Nonexistent", AttrArgs()))
    declared := new FunctionDeclaration("Run", parameters, null, null, null, null, null, Modifiers.None, AttrNodes(AttrNode("AlsoNonexistent", AttrArgs())), false, null, false, false, 5, 1)

    harness.Validator.ValidateDeclarationAttributeArguments(declared)

    assert AttrCodes(harness.Errors) == "201,201"
}

test "a class's own attributes and its PRIMARY-CONSTRUCTOR parameters' attributes are both validated" {
    harness := AttributeHarnessNew()
    primary := AttrParameterWith(AttrNode("Nonexistent", AttrArgs()))
    declared := new ClassDeclaration("Holder", null, null, new List<TypeReference>(), new List<Declaration>(), primary, Modifiers.None, AttrNodes(AttrNode("AlsoNonexistent", AttrArgs())), 5, 1)

    harness.Validator.ValidateDeclarationAttributeArguments(declared)

    assert AttrCodes(harness.Errors) == "201,201"
}

test "a TEST declaration carries no attributes of its own — only its table parameters do" {
    harness := AttributeHarnessNew()
    table := AttrParameterWith(AttrNode("Nonexistent", AttrArgs()))
    declared := new TestDeclaration("a case", new BlockStatement(new List<Statement>(), 5, 20), table, null, null, 5, 1)

    harness.Validator.ValidateDeclarationAttributeArguments(declared)

    assert AttrCodes(harness.Errors) == "201"
}

test "an ENUM declaration's attributes are validated" {
    harness := AttributeHarnessNew()
    declared := new EnumDeclaration("Colors", new List<EnumMember>(), EnumType.Int, Modifiers.None, AttrNodes(AttrNode("Nonexistent", AttrArgs())), 5, 1)

    harness.Validator.ValidateDeclarationAttributeArguments(declared)

    assert AttrCodes(harness.Errors) == "201"
}

test "a declaration shape that carries no attributes is silent" {
    harness := AttributeHarnessNew()

    harness.Validator.ValidateDeclarationAttributeArguments(new SetupDeclaration(new BlockStatement(new List<Statement>(), 5, 20), 5, 1))

    assert harness.Errors.Count == 0
}

test "a null parameter list is not walked" {
    harness := AttributeHarnessNew()

    harness.Validator.ValidateParameterAttributeArguments(null)
    harness.Validator.ValidateAttributeArguments(null)

    assert harness.Errors.Count == 0
}
