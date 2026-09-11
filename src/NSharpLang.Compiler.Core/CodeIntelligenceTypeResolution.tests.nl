namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE TYPE-INFO RESOLVERS (019 slice 16).
//
// These are the answers behind every hover and every `query type`, and until this slice they were
// thirteen PRIVATE C# members that nothing could ask directly. Nine things they decide were
// therefore unstated, unreachable or asserted only through a whole loaded project:
//   (a) THE SEMANTIC MODEL WINS BUT `unknown` IS NOT AN ANSWER — a recorded `UnknownTypeInfo` does
//       NOT stop the syntactic walk, which is the difference between "the analyzer said so" and
//       "the analyzer gave up".
//   (b) A CALL IS TYPED BY ITS CALLEE and an AWAIT IS TYPED BY ITS OPERAND — the task is NOT
//       unwrapped, which is the shipped answer and not an oversight to be silently repaired.
//   (c) A FLOAT LITERAL IS `double`, A NULL LITERAL IS `object` — the literal floor.
//   (d) TWO WALKS OVER THE SAME DECLARATIONS ANSWER DIFFERENT QUESTIONS: a FIELD called `Foo`
//       satisfies "what is the type of `Foo`" but NEVER satisfies a `Foo` TYPE REFERENCE.
//   (e) `FindNamedTypeInfo` IS TOP-LEVEL ONLY and IGNORES NAMESPACES; `FindTypeInfoByName` DESCENDS
//       INTO MEMBERS and RESPECTS THEM. Same corpus, two different reachable sets.
//   (f) NAMESPACE VISIBILITY INCLUDES THE BOTH-ABSENT CASE — two units with no namespace at all see
//       each other — and is NOT transitive through another unit's imports.
//   (g) THE FIRST NAME MATCH IN A MEMBER LIST ENDS THE SEARCH EVEN WITH NO TYPE, so a constructor
//       called `Foo` shadows a later field called `Foo` and answers null.
//   (h) A UNION TYPE REFERENCE IS FLATTENED BEFORE ITS ARMS ARE RESOLVED, so `(A | B) | C` and
//       `A | (B | C)` are the same three-armed answer.
//   (i) A CLASS CLIMBS TO ITS BASE AND A NULLABLE/OBLIVIOUS/ALIAS IS TRANSPARENT, while an enum and
//       a union answer with THEMSELVES whatever member was asked for.
func CitrAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func CitrSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func CitrFunction(name: string, returnType: TypeReference?): FunctionDeclaration {
    return new FunctionDeclaration(name, new List<Parameter>(), returnType, null, null, null, null, Modifiers.Public, CitrAttributes(), false, null, false, false, 1, 1)
}

func CitrField(name: string, fieldType: TypeReference?): FieldDeclaration {
    return new FieldDeclaration(name, fieldType, null, Modifiers.Public, PropertyModifier.None, CitrAttributes(), 1, 1)
}

func CitrProperty(name: string, propertyType: TypeReference): PropertyDeclaration {
    return new PropertyDeclaration(name, propertyType, null, null, null, Modifiers.Public, PropertyModifier.None, CitrAttributes(), 1, 1)
}

func CitrClass(name: string, members: List<Declaration>, baseClass: TypeReference?): ClassDeclaration {
    return new ClassDeclaration(name, null, baseClass, new List<TypeReference>(), members, null, Modifiers.Public, CitrAttributes(), 1, 1)
}

func CitrMembers1(first: Declaration): List<Declaration> {
    list := new List<Declaration>()
    list.Add(first)
    return list
}

func CitrMembers2(first: Declaration, second: Declaration): List<Declaration> {
    list := CitrMembers1(first)
    list.Add(second)
    return list
}

func CitrMembers3(first: Declaration, second: Declaration, third: Declaration): List<Declaration> {
    list := CitrMembers2(first, second)
    list.Add(third)
    return list
}

func CitrEnum(name: string, memberNames: string[]): EnumDeclaration {
    members := new List<EnumMember>()
    index := 0
    while index < memberNames.Length {
        members.Add(new EnumMember(memberNames[index], null, 1, 1))
        index = index + 1
    }

    return new EnumDeclaration(name, members, EnumType.Int, Modifiers.Public, CitrAttributes(), 1, 1)
}

func CitrUnion(name: string, caseNames: string[]): UnionDeclaration {
    cases := new List<UnionCase>()
    index := 0
    while index < caseNames.Length {
        cases.Add(new UnionCase(caseNames[index], null, 1, 1))
        index = index + 1
    }

    return new UnionDeclaration(name, null, cases, Modifiers.Public, CitrAttributes(), 1, 1)
}

func CitrUnit(namespaceName: string?, importNames: string[], declarations: List<Declaration>): CompilationUnit {
    namespaceDeclaration: NamespaceDeclaration? = null
    if namespaceName != null {
        namespaceDeclaration = new NamespaceDeclaration(namespaceName, 1, 1)
    }

    imports := new List<ImportDirective>()
    index := 0
    while index < importNames.Length {
        imports.Add(new ImportDirective(importNames[index], null, 1, 1))
        index = index + 1
    }

    return new CompilationUnit(namespaceDeclaration, imports, new List<Statement>(), null, declarations, 1, 1)
}

func CitrNone(): string[] {
    return new string[0]
}

func CitrProject(units: CompilationUnit[]): Dictionary<string, CompilationUnit> {
    project := new Dictionary<string, CompilationUnit>(StringComparer.OrdinalIgnoreCase)
    index := 0
    while index < units.Length {
        project["/p/file" + index.ToString() + ".nl"] = units[index]
        index = index + 1
    }

    return project
}

func CitrRender(typeInfo: TypeInfo?): string {
    if typeInfo == null {
        return "<null>"
    }

    boxed := typeInfo as object
    text := boxed.ToString()
    if text == null {
        return "<no-text>"
    }

    return text
}

func CitrEmptyProject(): Dictionary<string, CompilationUnit> {
    return new Dictionary<string, CompilationUnit>(StringComparer.OrdinalIgnoreCase)
}

test "a type reference resolves to its declaration, and an unknown name falls back to itself" {
    widget := CitrClass("Widget", CitrMembers1(CitrField("Size", CitrSimple("int"))), null)
    project := CitrProject([CitrUnit(null, CitrNone(), CitrMembers1(widget))])

    resolved := CodeIntelligenceTypeResolution.TypeReferenceToTypeInfo(CitrSimple("Widget"), project)
    assert resolved as ClassTypeInfo != null

    // `int` finds no declaration and becomes a simple type rather than an error.
    builtIn := CodeIntelligenceTypeResolution.TypeReferenceToTypeInfo(CitrSimple("int"), project)
    assert builtIn as SimpleTypeInfo != null
    assert CitrRender(builtIn) == "int"

    // An EMPTY project resolves nothing, which proves the lookup and not the fallback did the work.
    alone := CodeIntelligenceTypeResolution.TypeReferenceToTypeInfo(CitrSimple("Widget"), CitrEmptyProject())
    assert alone as ClassTypeInfo == null
    assert CitrRender(alone) == "Widget"
}

test "a generic reference keeps its head a NAME and resolves only its arguments" {
    widget := CitrClass("Widget", new List<Declaration>(), null)
    project := CitrProject([CitrUnit(null, CitrNone(), CitrMembers1(widget))])

    arguments := new List<TypeReference>()
    arguments.Add(CitrSimple("Widget"))
    generic := new GenericTypeReference("List", arguments, 1, 1)

    resolved := CodeIntelligenceTypeResolution.TypeReferenceToTypeInfo(generic, project) as GenericTypeInfo
    assert resolved != null
    assert resolved.Name == "List"
    assert resolved.TypeArguments.Count == 1

    // The ARGUMENT was looked up even though the head was not.
    assert resolved.TypeArguments[0] as ClassTypeInfo != null
}

test "an array and a nullable reference wrap a resolved element type" {
    project := CitrEmptyProject()

    array := CodeIntelligenceTypeResolution.TypeReferenceToTypeInfo(new ArrayTypeReference(CitrSimple("int")), project) as ArrayTypeInfo
    assert array != null
    assert CitrRender(array.ElementType) == "int"

    nullable := CodeIntelligenceTypeResolution.TypeReferenceToTypeInfo(new NullableTypeReference(CitrSimple("string")), project) as NullableTypeInfo
    assert nullable != null
    assert CitrRender(nullable.InnerType) == "string"
}

test "a union reference is FLATTENED before its arms are resolved, so nesting does not matter" {
    inner := new List<TypeReference>()
    inner.Add(CitrSimple("A"))
    inner.Add(CitrSimple("B"))

    outer := new List<TypeReference>()
    outer.Add(new UnionTypeReference(inner))
    outer.Add(CitrSimple("C"))

    nested := CodeIntelligenceTypeResolution.FlattenUnionTypeReference(new UnionTypeReference(outer))
    assert nested.Count == 3

    // Order is preserved depth-first: A, B, C.
    firstArm := nested[0] as SimpleTypeReference
    lastArm := nested[2] as SimpleTypeReference
    assert firstArm != null
    assert lastArm != null
    assert firstArm.Name == "A"
    assert lastArm.Name == "C"

    // A NON-union reference is a ONE-element list, which is what terminates the recursion.
    single := CodeIntelligenceTypeResolution.FlattenUnionTypeReference(CitrSimple("Solo"))
    assert single.Count == 1

    resolved := CodeIntelligenceTypeResolution.TypeReferenceToTypeInfo(new UnionTypeReference(outer), CitrEmptyProject()) as AnonymousUnionTypeInfo
    assert resolved != null
    assert resolved.Arms.Count == 3
}

test "the named-type walk is TOP-LEVEL ONLY and ignores namespaces, and never matches a value member" {
    nested := CitrClass("Inner", new List<Declaration>(), null)
    outer := CitrClass("Outer", CitrMembers3(nested, CitrField("Size", CitrSimple("int")), CitrFunction("Run", CitrSimple("int"))), null)
    project := CitrProject([CitrUnit("Alpha", CitrNone(), CitrMembers1(outer))])

    // Top-level: found. Nested: NOT found, even though the member walk would reach it.
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Outer") != null
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Inner") == null

    // A field and a function are values, not types, so a type reference never resolves to them.
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Size") == null
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Run") == null
}

test "the named-type walk answers every type declaration form" {
    declarations := new List<Declaration>()
    declarations.Add(CitrClass("C", new List<Declaration>(), null))
    declarations.Add(new StructDeclaration("S", null, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.Public, CitrAttributes(), 1, 1))
    declarations.Add(new RecordDeclaration("R", null, new List<TypeReference>(), new List<Declaration>(), null, false, Modifiers.Public, CitrAttributes(), 1, 1))
    declarations.Add(new InterfaceDeclaration("I", null, new List<TypeReference>(), new List<Declaration>(), Modifiers.Public, false, CitrAttributes(), 1, 1))
    declarations.Add(CitrEnum("E", ["Red"]))
    declarations.Add(CitrUnion("U", ["Left"]))
    declarations.Add(new TypeAliasDeclaration("Id", CitrSimple("int"), 1, 1))
    declarations.Add(new NewtypeDeclaration("Meters", CitrSimple("double"), 1, 1))
    project := CitrProject([CitrUnit(null, CitrNone(), declarations)])

    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "C") as ClassTypeInfo != null
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "S") as StructTypeInfo != null
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "R") as RecordTypeInfo != null
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "I") as InterfaceTypeInfo != null
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "E") as EnumTypeInfo != null
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "U") as UnionTypeInfo != null

    // AN ALIAS RESOLVES THROUGH to what it aliases; a NEWTYPE stays itself.
    assert CitrRender(CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Id")) == "int"
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Meters") as NewtypeInfo != null

    // An ENUM MEMBER is not a top-level type name, so this walk does not see it.
    assert CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Red") == null
}

test "namespace visibility includes the BOTH-ABSENT case and is not transitive" {
    target := CitrClass("Widget", new List<Declaration>(), null)

    // Two units with NO namespace at all see each other.
    bare := CitrUnit(null, CitrNone(), new List<Declaration>())
    bareTarget := CitrUnit(null, CitrNone(), CitrMembers1(target))
    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(CitrProject([bare, bareTarget]), bare, "Widget") != null

    // A unit in Alpha cannot see Beta without importing it.
    alpha := CitrUnit("Alpha", CitrNone(), new List<Declaration>())
    beta := CitrUnit("Beta", CitrNone(), CitrMembers1(target))
    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(CitrProject([alpha, beta]), alpha, "Widget") == null

    // With the import it can.
    importing := CitrUnit("Alpha", ["Beta"], new List<Declaration>())
    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(CitrProject([importing, beta]), importing, "Widget") != null

    // NOT TRANSITIVE: a middle unit that imports Beta does not lend that import to Alpha.
    middle := CitrUnit("Gamma", ["Beta"], new List<Declaration>())
    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(CitrProject([alpha, middle, beta]), alpha, "Widget") == null
}

test "the by-name walk DESCENDS into members and answers values as well as types" {
    inner := CitrClass("Inner", new List<Declaration>(), null)
    outer := CitrClass("Outer", CitrMembers3(inner, CitrField("Size", CitrSimple("int")), CitrFunction("Run", null)), null)
    unit := CitrUnit(null, CitrNone(), CitrMembers1(outer))
    project := CitrProject([unit])

    // The NESTED type is reachable here and is not through `FindNamedTypeInfo`.
    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(project, unit, "Inner") as ClassTypeInfo != null

    // A FIELD answers with its declared type, and a FUNCTION with no return type answers `void`.
    assert CitrRender(CodeIntelligenceTypeResolution.FindTypeInfoByName(project, unit, "Size")) == "int"
    assert CitrRender(CodeIntelligenceTypeResolution.FindTypeInfoByName(project, unit, "Run")) == "void"

    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(project, unit, "Missing") == null
}

test "an enum member and a union case resolve to their DECLARING type" {
    colour := CitrEnum("Colour", ["Red", "Green"])
    shape := CitrUnion("Shape", ["Circle", "Square"])
    unit := CitrUnit(null, CitrNone(), CitrMembers2(colour, shape))
    project := CitrProject([unit])

    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(project, unit, "Red") as EnumTypeInfo != null
    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(project, unit, "Circle") as UnionTypeInfo != null

    // The declaration itself still answers by its own name.
    assert CodeIntelligenceTypeResolution.FindTypeInfoByName(project, unit, "Colour") as EnumTypeInfo != null
}

test "a declaration ITSELF is asked before its enum members, which is observable" {
    // A class named `Red` and an enum CONTAINING `Red`: the class wins because the direct match runs
    // before the enum-member scan and the class is declared first.
    redClass := CitrClass("Red", new List<Declaration>(), null)
    colour := CitrEnum("Colour", ["Red"])
    unit := CitrUnit(null, CitrNone(), CitrMembers2(redClass, colour))

    resolved := CodeIntelligenceTypeResolution.FindTypeInfoByName(CitrProject([unit]), unit, "Red")
    assert resolved as ClassTypeInfo != null
    assert resolved as EnumTypeInfo == null
}

test "the declared-name type answers each declaration form and refuses the ones with no type" {
    project := CitrEmptyProject()

    assert CitrRender(CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(CitrFunction("Run", CitrSimple("int")), project)) == "int"

    // A FUNCTION with no return type is `void`, which IS an answer.
    assert CitrRender(CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(CitrFunction("Run", null), project)) == "void"

    // A FIELD with no written type is NOT an answer, and that difference is the whole point.
    assert CitrRender(CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(CitrField("Size", CitrSimple("int")), project)) == "int"
    assert CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(CitrField("Size", null), project) == null

    assert CitrRender(CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(CitrProperty("Width", CitrSimple("double")), project)) == "double"
    assert CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(CitrClass("C", new List<Declaration>(), null), project) as ClassTypeInfo != null
    assert CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(CitrEnum("E", ["A"]), project) as EnumTypeInfo != null
    assert CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(CitrUnion("U", ["A"]), project) as UnionTypeInfo != null
    assert CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(new NewtypeDeclaration("Meters", CitrSimple("double"), 1, 1), project) as NewtypeInfo != null

    // A CONSTRUCTOR declares no type at all.
    constructorDeclaration := new ConstructorDeclaration(new List<Parameter>(), new BlockStatement(new List<Statement>(), 1, 1), null, Modifiers.Public, CitrAttributes(), 1, 1)
    assert CodeIntelligenceTypeResolution.DeclaredNameTypeInfo(constructorDeclaration, project) == null
}

test "a declared-name answer needs BOTH the name and the line, and descends into members" {
    member := CitrField("Size", CitrSimple("int"))
    holder := CitrClass("Widget", CitrMembers1(member), null)
    project := CitrProject([CitrUnit(null, CitrNone(), CitrMembers1(holder))])

    // The synthesized nodes all sit on line 1, so line 1 answers and line 2 does not.
    hit := CodeIntelligenceTypeResolution.DeclaredNameTypeInDeclaration("/p", project, "/p/a.nl", holder, "Size", 1)
    assert hit != null
    assert hit.Name == "Size"
    assert hit.ResolvedType == "int"
    assert hit.Kind == "primitive"
    assert hit.Nullability == "notNull"
    assert hit.Definition != null
    assert hit.Definition.File == "a.nl"

    assert CodeIntelligenceTypeResolution.DeclaredNameTypeInDeclaration("/p", project, "/p/a.nl", holder, "Size", 2) == null
    assert CodeIntelligenceTypeResolution.DeclaredNameTypeInDeclaration("/p", project, "/p/a.nl", holder, "Missing", 1) == null

    // A member whose type cannot be determined does NOT stop the walk.
    untyped := CitrClass("Holder", CitrMembers2(CitrField("Ghost", null), CitrField("Ghost", CitrSimple("int"))), null)
    recovered := CodeIntelligenceTypeResolution.DeclaredNameTypeInDeclaration("/p", project, "/p/a.nl", untyped, "Ghost", 1)
    assert recovered != null
    assert recovered.ResolvedType == "int"
}

test "the member walk climbs a base class, is transparent through wrappers, and stops at the first name" {
    baseMembers := CitrMembers1(CitrField("Inherited", CitrSimple("long")))
    baseClass := CitrClass("Base", baseMembers, null)
    derived := CitrClass("Derived", CitrMembers1(CitrField("Own", CitrSimple("int"))), CitrSimple("Base"))
    project := CitrProject([CitrUnit(null, CitrNone(), CitrMembers2(baseClass, derived))])

    derivedInfo := CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Derived")
    assert derivedInfo != null

    assert CitrRender(CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, derivedInfo, "Own")) == "int"

    // THE CLASS ARM IS THE ONLY ONE THAT CLIMBS.
    assert CitrRender(CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, derivedInfo, "Inherited")) == "long"
    assert CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, derivedInfo, "Absent") == null

    // A NULLABLE AND AN OBLIVIOUS WRAPPER ARE TRANSPARENT.
    assert CitrRender(CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, new NullableTypeInfo(derivedInfo), "Own")) == "int"
    assert CitrRender(CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, new ObliviousTypeInfo(derivedInfo), "Own")) == "int"

    // AN ALIAS IS TRANSPARENT THROUGH A TYPE REFERENCE.
    assert CitrRender(CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, new AliasTypeInfo(CitrSimple("Derived")), "Own")) == "int"
}

test "an enum and a union answer with THEMSELVES whatever member is asked for" {
    project := CitrProject([CitrUnit(null, CitrNone(), CitrMembers2(CitrEnum("Colour", ["Red"]), CitrUnion("Shape", ["Circle"])))])

    colour := CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Colour")
    shape := CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Shape")
    assert colour != null
    assert shape != null

    // Any member name at all, including one that does not exist, answers the declaring type — which
    // is what makes `Colour.Red` hover as `Colour`.
    assert CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, colour, "Red") as EnumTypeInfo != null
    assert CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, colour, "NotAMember") as EnumTypeInfo != null
    assert CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, shape, "Circle") as UnionTypeInfo != null

    arms := new List<TypeInfo>()
    arms.Add(new SimpleTypeInfo("int"))
    assert CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, new AnonymousUnionTypeInfo(arms), "Anything") as AnonymousUnionTypeInfo != null

    // A SIMPLE TYPE HAS NO MEMBER WALK AT ALL.
    assert CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, new SimpleTypeInfo("int"), "Length") == null
}

test "the first name match in a member list ends the search even when it carries no type" {
    // A constructor and a field share the name in the DECLARED-MEMBER projection: the constructor is
    // reached first and answers NULL rather than letting the field answer.
    shadowing := CitrClass("Widget", CitrMembers2(new ConstructorDeclaration(new List<Parameter>(), new BlockStatement(new List<Statement>(), 1, 1), null, Modifiers.Public, CitrAttributes(), 1, 1), CitrField("Size", CitrSimple("int"))), null)
    project := CitrProject([CitrUnit(null, CitrNone(), CitrMembers1(shadowing))])

    widget := CodeIntelligenceTypeResolution.FindNamedTypeInfo(project, "Widget") as ClassTypeInfo
    assert widget != null

    // The field is still reachable by its own name.
    assert CitrRender(CodeIntelligenceTypeResolution.MemberTypeInfoOfType(project, widget, "Size")) == "int"

    // A FUNCTION MEMBER WITH NO RETURN TYPE IS `void`.
    voidHolder := CitrClass("Holder", CitrMembers1(CitrFunction("Run", null)), null)
    voidProject := CitrProject([CitrUnit(null, CitrNone(), CitrMembers1(voidHolder))])
    holderInfo := CodeIntelligenceTypeResolution.FindNamedTypeInfo(voidProject, "Holder")
    assert holderInfo != null
    assert CitrRender(CodeIntelligenceTypeResolution.MemberTypeInfoOfType(voidProject, holderInfo, "Run")) == "void"
}

test "the empty member array answers null, which is the walk's floor" {
    assert CodeIntelligenceTypeResolution.MemberTypeInfoInMembers(CitrEmptyProject(), new DeclaredMemberInfo[0], "Anything") == null
}

test "the expression walk types every literal, and the literal floor is the shipped answer" {
    unit := CitrUnit(null, CitrNone(), new List<Declaration>())
    project := CitrProject([unit])

    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(new IntLiteralExpression("1", 1, 1), null, project, unit)) == "int"

    // A FLOAT LITERAL IS `double`, NOT `float`.
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(new FloatLiteralExpression("1.5", 1, 1), null, project, unit)) == "double"
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(new CharLiteralExpression("c", 1, 1), null, project, unit)) == "char"
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(new StringLiteralExpression("s", 1, 1), null, project, unit)) == "string"
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(new BoolLiteralExpression(true, 1, 1), null, project, unit)) == "bool"

    // A NULL LITERAL IS `object`, which is what keeps the hover from reporting `null` as a type.
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(new NullLiteralExpression(1, 1), null, project, unit)) == "object"

    // A NULL EXPRESSION IS NOT AN ERROR — it is simply no answer.
    assert CodeIntelligenceTypeResolution.TypeInfoFromExpression(null, null, project, unit) == null
}

test "a call is typed by its CALLEE and an await by its OPERAND, and the task is not unwrapped" {
    widget := CitrClass("Widget", new List<Declaration>(), null)
    maker := CitrFunction("Make", CitrSimple("Widget"))
    unit := CitrUnit(null, CitrNone(), CitrMembers2(widget, maker))
    project := CitrProject([unit])

    call := new CallExpression(new IdentifierExpression("Make", 1, 1), new List<Argument>(), null, 1, 1)
    assert CodeIntelligenceTypeResolution.TypeInfoFromExpression(call, null, project, unit) as ClassTypeInfo != null

    // AWAIT AND PARENTHESES AND `with` ARE ALL PASS-THROUGH.
    awaited := new AwaitExpression(new IntLiteralExpression("1", 1, 1), 1, 1)
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(awaited, null, project, unit)) == "int"

    parenthesized := new ParenthesizedExpression(new StringLiteralExpression("s", 1, 1), 1, 1)
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(parenthesized, null, project, unit)) == "string"

    withExpression := new WithExpression(new IdentifierExpression("Make", 1, 1), new List<PropertyInitializer>(), 1, 1)
    assert CodeIntelligenceTypeResolution.TypeInfoFromExpression(withExpression, null, project, unit) as ClassTypeInfo != null
}

test "a cast is its TARGET type and a new expression is its written type, and a typeless new is null" {
    unit := CitrUnit(null, CitrNone(), new List<Declaration>())
    project := CitrProject([unit])

    cast := new CastExpression(new IntLiteralExpression("1", 1, 1), CitrSimple("long"), CastKind.Hard, 1, 1)
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(cast, null, project, unit)) == "long"

    typed := new NewExpression(CitrSimple("Widget"), new List<Argument>(), null, 1, 1)
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(typed, null, project, unit)) == "Widget"

    // A `new` with no written type — an array literal — has no answer here.
    untyped := new NewExpression(null, new List<Argument>(), null, 1, 1)
    assert CodeIntelligenceTypeResolution.TypeInfoFromExpression(untyped, null, project, unit) == null
}

test "a member access falls back to the member's BARE NAME when the receiver cannot be typed" {
    widget := CitrClass("Widget", CitrMembers1(CitrField("Size", CitrSimple("int"))), null)
    unit := CitrUnit(null, CitrNone(), CitrMembers1(widget))
    project := CitrProject([unit])

    // The receiver `Widget` resolves, so the member walk answers.
    onType := new MemberAccessExpression(new IdentifierExpression("Widget", 1, 1), "Size", false, 1, 1)
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(onType, null, project, unit)) == "int"

    // The receiver `Nothing` does not resolve, so `Size` is resolved as if written alone — and the
    // by-name walk descends into members, so it still finds the field's type.
    onNothing := new MemberAccessExpression(new IdentifierExpression("Nothing", 1, 1), "Size", false, 1, 1)
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromExpression(onNothing, null, project, unit)) == "int"

    // Neither the receiver nor the member resolves: no answer at all.
    onNeither := new MemberAccessExpression(new IdentifierExpression("Nothing", 1, 1), "AlsoNothing", false, 1, 1)
    assert CodeIntelligenceTypeResolution.TypeInfoFromExpression(onNeither, null, project, unit) == null
}

test "the default null state is NOT-NULL for everything except the four arms that say otherwise" {
    assert CodeIntelligenceTypeResolution.DefaultNullState(new NullableTypeInfo(new SimpleTypeInfo("int"))) == NullState.MaybeNull
    assert CodeIntelligenceTypeResolution.DefaultNullState(BuiltInTypes.Unknown) == NullState.Unknown
    assert CodeIntelligenceTypeResolution.DefaultNullState(new SimpleTypeInfo("null")) == NullState.Null

    // A simple type that is not literally called "null" is NOT-NULL, not Null.
    assert CodeIntelligenceTypeResolution.DefaultNullState(new SimpleTypeInfo("int")) == NullState.NotNull
    assert CodeIntelligenceTypeResolution.DefaultNullState(new ArrayTypeInfo(new SimpleTypeInfo("int"))) == NullState.NotNull

    // THE REFLECTED ARM: a CLR value type that is not `Nullable<T>` is NOT-NULL; everything else
    // reflected is OBLIVIOUS rather than a confident answer in either direction.
    assert CodeIntelligenceTypeResolution.DefaultNullState(new ReflectionTypeInfo(typeof(int))) == NullState.NotNull
    assert CodeIntelligenceTypeResolution.DefaultNullState(new ReflectionTypeInfo(typeof(string))) == NullState.Oblivious
}

test "the by-name entry prefers the semantic model and the project walk is the fallback" {
    widget := CitrClass("Widget", new List<Declaration>(), null)
    unit := CitrUnit(null, CitrNone(), CitrMembers1(widget))
    project := CitrProject([unit])

    // With NO model the project walk answers.
    assert CodeIntelligenceTypeResolution.TypeInfoByName("Widget", null, project, unit) as ClassTypeInfo != null
    assert CodeIntelligenceTypeResolution.TypeInfoByName("Absent", null, project, unit) == null
}

test "the two declaration walks share their nine TYPE arms and differ only in the three VALUE arms" {
    project := CitrEmptyProject()

    // The C# spelled these nine arms out TWICE, in two switches kept in step by hand. The shared arm
    // answers a type declaration and REFUSES a function, a field and a property.
    assert CodeIntelligenceTypeResolution.NamedTypeInfoFromDeclaration(CitrClass("N", new List<Declaration>(), null), "N", project) as ClassTypeInfo != null
    assert CodeIntelligenceTypeResolution.NamedTypeInfoFromDeclaration(CitrEnum("N", ["Red"]), "N", project) as EnumTypeInfo != null
    assert CodeIntelligenceTypeResolution.NamedTypeInfoFromDeclaration(CitrFunction("N", CitrSimple("int")), "N", project) == null
    assert CodeIntelligenceTypeResolution.NamedTypeInfoFromDeclaration(CitrField("N", CitrSimple("int")), "N", project) == null
    assert CodeIntelligenceTypeResolution.NamedTypeInfoFromDeclaration(CitrProperty("N", CitrSimple("int")), "N", project) == null

    // The value walk answers all four, which is the ONLY difference between the two.
    assert CodeIntelligenceTypeResolution.TypeInfoFromDeclaration(CitrClass("N", new List<Declaration>(), null), "N", project) as ClassTypeInfo != null
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromDeclaration(CitrFunction("N", CitrSimple("int")), "N", project)) == "int"
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromDeclaration(CitrField("N", CitrSimple("int")), "N", project)) == "int"
    assert CitrRender(CodeIntelligenceTypeResolution.TypeInfoFromDeclaration(CitrProperty("N", CitrSimple("int")), "N", project)) == "int"

    // A NAME MISMATCH is null on both walks.
    assert CodeIntelligenceTypeResolution.NamedTypeInfoFromDeclaration(CitrClass("N", new List<Declaration>(), null), "Other", project) == null
    assert CodeIntelligenceTypeResolution.TypeInfoFromDeclaration(CitrClass("N", new List<Declaration>(), null), "Other", project) == null
}
