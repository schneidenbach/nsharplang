namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE FORMATTER ITSELF (task 019 slice 20). These are the semantic assertions that
// came out of `Formatter.cs` with its last eighteen members — and with the file, which is DELETED.
//
// EVERY ONE OF THESE WAS UNSTATEABLE BEFORE THE MOVE. `Formatter`'s C# surface was two public
// entry points over a whole file, so a rule about ONE declaration arm could only ever be inferred
// from formatted text, and only for the shapes some parser happened to produce. A record with no
// members, an indexer with neither accessor, a union case with no properties, a table-driven test
// missing one of its two halves — each is one line here and was unreachable before.
//
// TWELVE THINGS THAT WERE PROSE, AN ACCIDENT OR UNREACHABLE ARE STATED HERE AS CONTRACTS:
//   (a) THE UNHANDLED DECLARATION ARM THROWS, like the walk's three, so a node the formatter
//       cannot spell never becomes a file that will not parse.
//   (b) THE BRACED BODY IS UNCONDITIONAL ON A RECORD AND AN INDEXER AND CONDITIONAL ON A PROPERTY.
//       Three declarations, three different rules, asserted side by side because only together do
//       they read as decisions rather than as oversights.
//   (c) AN EMPTY PRIMARY CONSTRUCTOR LIST WRITES NO PARENTHESES. `class Foo {` and `class Foo() {`
//       are different source and the empty list means the former.
//   (d) A FIELD WITH AN INITIALIZER AND NO WRITTEN TYPE GETS `:=`; ONE WITH BOTH GETS `=`.
//   (e) THE BASE CLASS AND THE INTERFACES SHARE ONE `:` LIST, base first.
//   (f) `package` IS WRITTEN AFTER THE IMPORTS, which is the grammar's order and not the AST's.
//   (g) THE BLANK-LINE GAP IS MEASURED FROM A DECLARATION'S *END* LINE, so a multi-line body is
//       not a phantom gap — the property that makes formatting idempotent.
//   (h) THE FIRST DECLARATION NEVER GETS A LEADING BLANK LINE, however far down the file it began.
//   (i) AN ENUM'S LAST MEMBER HAS NO TRAILING COMMA, and a string-backed enum announces `: string`.
//   (j) A TEST DESCRIPTION IS QUOTED AND NOT ESCAPED, and a table-driven header needs BOTH halves.
//   (k) `FormatSafe`'s TWO GATES ARE REAL: output that will not re-parse and output that is not
//       idempotent both return the ORIGINAL source with a warning, and neither is reachable by
//       accident.
//   (l) THE STATE IS BORROWED, NOT OWNED. A declaration formatter and the statement arms inside it
//       agree about the indent depth to the character, and the depth a format ends at is the depth
//       it started at.

func FmtConfig(size: int, spaces: bool, maxLine: int): FormatterConfig {
    config := new FormatterConfig()
    config.IndentSize = size
    config.UseSpaces = spaces
    config.MaxLineLength = maxLine
    return config
}

func FmtFormatter(): Formatter {
    return new Formatter(FmtConfig(4, true, 100))
}

// Newlines are compared as a visible token so a failing assertion reads as one line of text.
func FmtShow(builder: StringBuilder): string {
    return builder.ToString().Replace("\r\n", "\n").Replace("\n", "|")
}

func FmtShowText(text: string): string {
    return text.Replace("\r\n", "\n").Replace("\n", "|")
}

func FmtType(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 0, 0)
}

func FmtTypes(names: List<string>): List<TypeReference> {
    result := new List<TypeReference>()
    index := 0
    while index < names.Count {
        result.Add(FmtType(names[index]))
        index = index + 1
    }

    return result
}

func FmtNames(first: string?, second: string?): List<string> {
    result := new List<string>()
    if first != null {
        result.Add(first)
    }

    if second != null {
        result.Add(second)
    }

    return result
}

func FmtNoTypes(): List<TypeReference> {
    return new List<TypeReference>()
}

func FmtNoAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func FmtNoMembers(): List<Declaration> {
    return new List<Declaration>()
}

func FmtNoParameters(): List<Parameter> {
    return new List<Parameter>()
}

func FmtParameter(name: string, typeName: string): Parameter {
    return new Parameter(name, FmtType(typeName), null, false, ParameterModifier.None, null, 0, 0, false, null)
}

func FmtOneParameter(name: string, typeName: string): List<Parameter> {
    result := new List<Parameter>()
    result.Add(FmtParameter(name, typeName))
    return result
}

func FmtIdentifier(name: string): Expression {
    return new IdentifierExpression(name, 0, 0)
}

func FmtInt(value: string): Expression {
    return new IntLiteralExpression(value, 0, 0)
}

func FmtEmptyBlock(): BlockStatement {
    return new BlockStatement(new List<Statement>(), 0, 0)
}

func FmtOneStatementBlock(): BlockStatement {
    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(FmtIdentifier("inner"), 0, 0))
    return new BlockStatement(statements, 0, 0)
}

func FmtMembers(first: Declaration?, second: Declaration?): List<Declaration> {
    result := new List<Declaration>()
    if first != null {
        result.Add(first)
    }

    if second != null {
        result.Add(second)
    }

    return result
}

func FmtField(name: string, typeName: string?, line: int): FieldDeclaration {
    fieldType: TypeReference? = null
    if typeName != null {
        fieldType = FmtType(typeName)
    }

    return new FieldDeclaration(name, fieldType, null, Modifiers.None, PropertyModifier.None, FmtNoAttributes(), line, 1)
}

func FmtClass(name: string, members: List<Declaration>, line: int): ClassDeclaration {
    return new ClassDeclaration(name, null, null, FmtNoTypes(), members, null, Modifiers.None, FmtNoAttributes(), line, 1)
}

func FmtUnit(declarations: List<Declaration>): CompilationUnit {
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 0, 0)
}

func FmtOne(declaration: Declaration): List<Declaration> {
    result := new List<Declaration>()
    result.Add(declaration)
    return result
}

// One declaration, formatted on its own through the public dispatch, with newlines made visible.
func FmtRender(declaration: Declaration): string {
    formatter := FmtFormatter()
    builder := new StringBuilder()
    formatter.FormatDeclaration(declaration, builder)
    return FmtShow(builder)
}

// ---- (a) the unhandled arm ----------------------------------------------------------------------

test "an unhandled declaration throws rather than emitting text that will not parse" {
    formatter := FmtFormatter()
    builder := new StringBuilder()
    assert throws InvalidOperationException {
        formatter.FormatDeclaration(new Declaration(1, 1), builder)
    }
}

// ---- the three inline arms ----------------------------------------------------------------------

test "a type alias is one line and needs no walk" {
    assert FmtRender(new TypeAliasDeclaration("Id", FmtType("int"), 1, 1)) == "type Id = int|"
}

test "a newtype names its underlying type after the newtype keyword" {
    assert FmtRender(new NewtypeDeclaration("Meters", FmtType("double"), 1, 1)) == "type Meters = newtype double|"
}

test "a preprocessor directive is emitted verbatim" {
    assert FmtRender(new PreprocessorDeclaration("#if DEBUG", 1, 1)) == "#if DEBUG|"
}

// ---- (b) the three body rules -------------------------------------------------------------------

test "a record with no members STILL writes its braces, because the grammar requires a body" {
    empty := new RecordDeclaration("Point", null, FmtNoTypes(), FmtNoMembers(), null, false, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(empty) == "record Point {|}|"
}

test "an indexer with NEITHER accessor still writes its braces" {
    indexer := new IndexerDeclaration(FmtOneParameter("i", "int"), FmtType("string"), null, null, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(indexer) == "this[i: int]: string {|}|"
}

test "a property with NEITHER accessor writes NO braces at all — the opposite rule" {
    auto := new PropertyDeclaration("Name", FmtType("string"), null, null, null, Modifiers.None, PropertyModifier.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(auto) == "Name: string|"
}

test "a property with an expression body writes an arrow and no braces" {
    expressionBodied := new PropertyDeclaration("Name", FmtType("string"), null, null, FmtIdentifier("value"), Modifiers.None, PropertyModifier.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(expressionBodied) == "Name: string => value|"
}

test "an accessor body is walked TWO pushes down: the property's and the accessor's own" {
    // The depth agreement this design exists for, stated at its deepest point. A statement inside a
    // `get` is indented by the property's push AND the accessor's, and it reaches that depth through
    // the walk's `FormatterWalkState` — which is the formatter's own object, not the walk's.
    withBody := new PropertyDeclaration("Name", FmtType("string"), FmtOneStatementBlock(), null, null, Modifiers.None, PropertyModifier.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(withBody) == "Name: string {|    get {|        inner|    }|}|"
}

test "a property with only a setter writes the set block and no get block" {
    setOnly := new PropertyDeclaration("Name", FmtType("string"), null, FmtEmptyBlock(), null, Modifiers.None, PropertyModifier.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(setOnly) == "Name: string {|    set {|    }|}|"
}

test "an indexer with only a getter writes the get block and no set block" {
    getOnly := new IndexerDeclaration(FmtOneParameter("i", "int"), FmtType("string"), FmtEmptyBlock(), null, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(getOnly) == "this[i: int]: string {|    get {|    }|}|"
}

// ---- (c) the empty primary constructor list -----------------------------------------------------

test "an EMPTY primary constructor list writes no parentheses" {
    withEmpty := new ClassDeclaration("Foo", null, null, FmtNoTypes(), FmtNoMembers(), FmtNoParameters(), Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(withEmpty) == "class Foo {|}|"
}

test "a NULL primary constructor list writes no parentheses either" {
    withNull := FmtClass("Foo", FmtNoMembers(), 1)
    assert FmtRender(withNull) == "class Foo {|}|"
}

test "a non-empty primary constructor list is written with its parameters" {
    withOne := new ClassDeclaration("Foo", null, null, FmtNoTypes(), FmtNoMembers(), FmtOneParameter("x", "int"), Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(withOne) == "class Foo(x: int) {|}|"
}

test "a record's positional parameters are written the same way" {
    positional := new RecordDeclaration("Point", null, FmtNoTypes(), FmtNoMembers(), FmtOneParameter("x", "int"), false, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(positional) == "record Point(x: int) {|}|"
}

// ---- (d) the two assignment spellings -----------------------------------------------------------

test "a field with an initializer and NO written type gets the inferring assignment" {
    inferred := new FieldDeclaration("count", null, FmtInt("0"), Modifiers.None, PropertyModifier.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(inferred) == "count := 0|"
}

test "a field with an initializer AND a written type gets the plain assignment" {
    stated := new FieldDeclaration("count", FmtType("int"), FmtInt("0"), Modifiers.None, PropertyModifier.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(stated) == "count: int = 0|"
}

test "a field with a type and no initializer writes neither assignment" {
    bare := FmtField("count", "int", 1)
    assert FmtRender(bare) == "count: int|"
}

test "a field with neither a type nor an initializer is just its name" {
    nameOnly := FmtField("count", null, 1)
    assert FmtRender(nameOnly) == "count|"
}

// ---- (e) the one base list ----------------------------------------------------------------------

test "a class writes its base class and its interfaces in ONE list, base first" {
    derived := new ClassDeclaration("Child", null, FmtType("Parent"), FmtTypes(FmtNames("IA", "IB")), FmtNoMembers(), null, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(derived) == "class Child: Parent, IA, IB {|}|"
}

test "a class with interfaces and no base class opens the list with the first interface" {
    implementing := new ClassDeclaration("Child", null, null, FmtTypes(FmtNames("IA", null)), FmtNoMembers(), null, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(implementing) == "class Child: IA {|}|"
}

test "a class with neither writes no colon" {
    assert FmtRender(FmtClass("Child", FmtNoMembers(), 1)) == "class Child {|}|"
}

test "a struct has no base class, so its list is its interfaces" {
    value := new StructDeclaration("V", null, FmtTypes(FmtNames("IA", null)), FmtNoMembers(), null, Modifiers.None, FmtNoAttributes(), 1, 1, false)
    assert FmtRender(value) == "struct V: IA {|}|"
}

test "a ref struct writes TWO keywords where a struct writes one" {
    reference := new StructDeclaration("V", null, FmtNoTypes(), FmtNoMembers(), null, Modifiers.None, FmtNoAttributes(), 1, 1, true)
    assert FmtRender(reference) == "ref struct V {|}|"
}

test "a record struct writes struct as a SECOND keyword, not a different one" {
    valueRecord := new RecordDeclaration("P", null, FmtNoTypes(), FmtNoMembers(), null, true, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(valueRecord) == "record struct P {|}|"
}

test "a duck interface writes its prefix between the modifiers and the keyword" {
    duckInterface := new InterfaceDeclaration("IShape", null, FmtNoTypes(), FmtNoMembers(), Modifiers.None, true, FmtNoAttributes(), 1, 1)
    assert FmtRender(duckInterface) == "duck interface IShape {|}|"
}

test "an interface writes its base interfaces in the same one list" {
    derived := new InterfaceDeclaration("IC", null, FmtTypes(FmtNames("IA", "IB")), FmtNoMembers(), Modifiers.None, false, FmtNoAttributes(), 1, 1)
    assert FmtRender(derived) == "interface IC: IA, IB {|}|"
}

// ---- the type parameters ------------------------------------------------------------------------

test "an empty type parameter list writes no brackets" {
    generic := new ClassDeclaration("Box", new List<TypeParameter>(), null, FmtNoTypes(), FmtNoMembers(), null, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(generic) == "class Box {|}|"
}

test "type parameters are comma separated inside angle brackets" {
    parameters := new List<TypeParameter>()
    parameters.Add(new TypeParameter("T"))
    parameters.Add(new TypeParameter("U"))
    generic := new ClassDeclaration("Box", parameters, null, FmtNoTypes(), FmtNoMembers(), null, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(generic) == "class Box<T, U> {|}|"
}

// ---- the soa record and the union: columns and cases are NOT members ----------------------------

test "a soa record writes one column per line and dispatches none of them" {
    columns := new List<SoaColumnDeclaration>()
    columns.Add(new SoaColumnDeclaration("x", FmtType("float"), 0, 0))
    columns.Add(new SoaColumnDeclaration("y", FmtType("float"), 0, 0))
    soaRecord := new SoaRecordDeclaration("Particles", columns, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(soaRecord) == "soa record Particles {|    x: float|    y: float|}|"
}

test "a soa record with no columns is still a braced body" {
    soaRecord := new SoaRecordDeclaration("Empty", new List<SoaColumnDeclaration>(), Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(soaRecord) == "soa record Empty {|}|"
}

test "a union case with NO properties writes no braces" {
    cases := new List<UnionCase>()
    cases.Add(new UnionCase("None", null, 0, 0))
    unionValue := new UnionDeclaration("Maybe", null, cases, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(unionValue) == "union Maybe {|    None|}|"
}

test "a union case with an EMPTY property list writes no braces either" {
    cases := new List<UnionCase>()
    cases.Add(new UnionCase("None", new List<UnionCaseProperty>(), 0, 0))
    unionValue := new UnionDeclaration("Maybe", null, cases, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(unionValue) == "union Maybe {|    None|}|"
}

test "a union case with properties writes them inline, comma separated, inside spaced braces" {
    properties := new List<UnionCaseProperty>()
    properties.Add(new UnionCaseProperty("value", FmtType("int")))
    properties.Add(new UnionCaseProperty("tag", FmtType("string")))
    cases := new List<UnionCase>()
    cases.Add(new UnionCase("Some", properties, 0, 0))
    unionValue := new UnionDeclaration("Maybe", null, cases, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(unionValue) == "union Maybe {|    Some { value: int, tag: string }|}|"
}

// ---- (i) the enum -------------------------------------------------------------------------------

test "an enum's LAST member has no trailing comma" {
    members := new List<EnumMember>()
    members.Add(new EnumMember("A", null, 0, 0))
    members.Add(new EnumMember("B", null, 0, 0))
    enumeration := new EnumDeclaration("E", members, EnumType.Int, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(enumeration) == "enum E {|    A,|    B|}|"
}

test "a string-backed enum announces its backing type and an int-backed one does not" {
    members := new List<EnumMember>()
    members.Add(new EnumMember("A", null, 0, 0))
    stringBacked := new EnumDeclaration("E", members, EnumType.String, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(stringBacked) == "enum E: string {|    A|}|"

    intBacked := new EnumDeclaration("E", members, EnumType.Int, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(intBacked) == "enum E {|    A|}|"
}

test "an enum member with an explicit value writes it through the expression walk" {
    members := new List<EnumMember>()
    members.Add(new EnumMember("A", FmtInt("7"), 0, 0))
    enumeration := new EnumDeclaration("E", members, EnumType.Int, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(enumeration) == "enum E {|    A = 7|}|"
}

// ---- the constructor ----------------------------------------------------------------------------

test "a constructor has no name and no return type" {
    ctor := new ConstructorDeclaration(FmtOneParameter("x", "int"), FmtEmptyBlock(), null, Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(ctor) == "constructor(x: int) {|}|"
}

test "a constructor initializer is an EXPRESSION and is written after a colon" {
    ctor := new ConstructorDeclaration(FmtNoParameters(), FmtEmptyBlock(), FmtIdentifier("baseCall"), Modifiers.None, FmtNoAttributes(), 1, 1)
    assert FmtRender(ctor) == "constructor(): baseCall {|}|"
}

// ---- (j) the test declarations ------------------------------------------------------------------

test "a test description is quoted and NOT escaped" {
    declaration := new TestDeclaration("a \\\" quote", FmtEmptyBlock(), null, null, null, 1, 1)
    assert FmtRender(declaration) == "test \"a \\\" quote\" {|}|"
}

test "a skip reason is written after the description and before the brace" {
    declaration := new TestDeclaration("d", FmtEmptyBlock(), null, null, "flaky", 1, 1)
    assert FmtRender(declaration) == "test \"d\" skip \"flaky\" {|}|"
}

test "a table-driven header needs BOTH halves — parameters with no cases writes neither" {
    parametersOnly := new TestDeclaration("d", FmtEmptyBlock(), FmtOneParameter("n", "int"), null, null, 1, 1)
    assert FmtRender(parametersOnly) == "test \"d\" {|}|"
}

test "a table-driven header needs BOTH halves — cases with no parameters writes neither" {
    rows := new List<List<Expression>>()
    row := new List<Expression>()
    row.Add(FmtInt("1"))
    rows.Add(row)
    casesOnly := new TestDeclaration("d", FmtEmptyBlock(), null, rows, null, 1, 1)
    assert FmtRender(casesOnly) == "test \"d\" {|}|"
}

test "a table-driven test writes its parameter list and one bracketed row per case" {
    rows := new List<List<Expression>>()
    first := new List<Expression>()
    first.Add(FmtInt("1"))
    first.Add(FmtInt("2"))
    rows.Add(first)
    second := new List<Expression>()
    second.Add(FmtInt("3"))
    second.Add(FmtInt("4"))
    rows.Add(second)
    parameters := FmtOneParameter("a", "int")
    parameters.Add(FmtParameter("b", "int"))
    declaration := new TestDeclaration("d", FmtEmptyBlock(), parameters, rows, null, 1, 1)
    assert FmtRender(declaration) == "test \"d\" with (a: int, b: int) [|    (1, 2),|    (3, 4)|] {|}|"
}

test "setup and teardown are a keyword and a block, with no name and no parameters" {
    assert FmtRender(new SetupDeclaration(FmtEmptyBlock(), 1, 1)) == "setup {|}|"
    assert FmtRender(new TeardownDeclaration(FmtEmptyBlock(), 1, 1)) == "teardown {|}|"
}

// ---- the modifier prefix ------------------------------------------------------------------------

test "a declaration with no surviving modifiers opens with no leading space" {
    assert FmtRender(FmtClass("Foo", FmtNoMembers(), 1)) == "class Foo {|}|"
}

test "a surviving modifier is written with exactly one trailing space" {
    sealedClass := new ClassDeclaration("Foo", null, null, FmtNoTypes(), FmtNoMembers(), null, Modifiers.Sealed, FmtNoAttributes(), 1, 1)
    assert FmtRender(sealedClass) == "sealed class Foo {|}|"
}

test "a redundant public is dropped on a PascalCase name, because the case already says it" {
    exported := new ClassDeclaration("Foo", null, null, FmtNoTypes(), FmtNoMembers(), null, Modifiers.Public, FmtNoAttributes(), 1, 1)
    assert FmtRender(exported) == "class Foo {|}|"
}

// ---- (l) the borrowed state ---------------------------------------------------------------------

test "a nested member body indents by exactly one level per depth" {
    inner := FmtClass("Inner", FmtOne(FmtField("value", "int", 1)), 1)
    outer := FmtClass("Outer", FmtOne(inner), 1)
    assert FmtRender(outer) == "class Outer {|    class Inner {|        value: int|    }|}|"
}

test "a completed format returns the indent depth to where it started" {
    formatter := FmtFormatter()
    builder := new StringBuilder()
    nested := FmtClass("Outer", FmtOne(FmtClass("Inner", FmtOne(FmtField("v", "int", 1)), 1)), 1)
    formatter.FormatDeclaration(nested, builder)
    after := new StringBuilder()
    formatter.FormatDeclaration(FmtField("tail", "int", 1), after)
    assert FmtShow(after) == "tail: int|"
}

// ---- (f) (g) (h) the file head and the declaration gaps ----------------------------------------

test "the package declaration is written AFTER the imports, which is the grammar's order" {
    imports := new List<ImportDirective>()
    imports.Add(new ImportDirective("System", null, 1, 1))
    unit := new CompilationUnit(null, imports, new List<Statement>(), new PackageDeclaration("app", 2, 1), FmtNoMembers(), 0, 0)
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "import System||package app||"
}

test "an import alias is written after the namespace" {
    imports := new List<ImportDirective>()
    imports.Add(new ImportDirective("System.Text", "T", 1, 1))
    unit := new CompilationUnit(null, imports, new List<Statement>(), null, FmtNoMembers(), 0, 0)
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "import System.Text as T||"
}

test "a file import is quoted and keeps its alias" {
    fileImports := new List<Statement>()
    fileImports.Add(new FileImport("./util.nl", "u", 1, 1))
    unit := new CompilationUnit(null, new List<ImportDirective>(), fileImports, null, FmtNoMembers(), 0, 0)
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "import \"./util.nl\" as u||"
}

test "a namespace is followed by exactly one blank line" {
    unit := new CompilationUnit(new NamespaceDeclaration("A.B", 1, 1), new List<ImportDirective>(), new List<Statement>(), null, FmtNoMembers(), 0, 0)
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "namespace A.B||"
}

test "the FIRST declaration never gets a leading blank line, however far down the file it began" {
    unit := FmtUnit(FmtOne(FmtField("a", "int", 40)))
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "a: int|"
}

test "a source gap between two declarations is preserved as ONE blank line" {
    unit := FmtUnit(FmtMembers(FmtField("a", "int", 1), FmtField("b", "int", 5)))
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "a: int||b: int|"
}

test "two adjacent declarations get no blank line between them" {
    unit := FmtUnit(FmtMembers(FmtField("a", "int", 1), FmtField("b", "int", 2)))
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "a: int|b: int|"
}

test "the gap is measured from the previous declaration's END line and not its start" {
    // A class that spans lines 1..10 followed by a field on line 11 is ADJACENT. Measuring from the
    // class's START line would see a nine-line gap and insert a blank line the source did not have,
    // and the second format would then insert another — which is exactly what `FormatSafe`'s
    // idempotence gate exists to catch.
    wide := FmtClass("Wide", FmtNoMembers(), 1)
    wide.EndLine = 10
    unit := FmtUnit(FmtMembers(wide, FmtField("after", "int", 11)))
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "class Wide {|}|after: int|"
}

test "the same class followed by a field two lines later DOES get its blank line" {
    wide := FmtClass("Wide", FmtNoMembers(), 1)
    wide.EndLine = 10
    unit := FmtUnit(FmtMembers(wide, FmtField("after", "int", 12)))
    formatter := FmtFormatter()
    assert FmtShowText(formatter.Format(unit, null)) == "class Wide {|}||after: int|"
}

test "a member list follows the same gap rule inside a body" {
    body := FmtMembers(FmtField("a", "int", 2), FmtField("b", "int", 4))
    assert FmtRender(FmtClass("Holder", body, 1)) == "class Holder {|    a: int||    b: int|}|"
}

// ---- (k) the two safety gates -------------------------------------------------------------------

test "FormatSafe returns the formatted text and no warnings when both gates pass" {
    source := "func f(): int {\n    return 1\n}\n"
    parsed := ColumnarParserRecovery.ParseFileAst(source, "t.nl")
    unit := parsed.CompilationUnit
    assert unit != null
    formatter := FmtFormatter()
    result := formatter.FormatSafe(source, unit ?? FmtUnit(FmtNoMembers()), null, "t.nl")
    assert result.Success
    assert result.Warnings.Count == 0
    assert result.Text == source
}

test "FormatSafe is idempotent over a DEFORMED source: it returns the canonical text, not the input" {
    deformed := "func f(): int {\nreturn 1\n}\n"
    parsed := ColumnarParserRecovery.ParseFileAst(deformed, "t.nl")
    unit := parsed.CompilationUnit
    assert unit != null
    formatter := FmtFormatter()
    result := formatter.FormatSafe(deformed, unit ?? FmtUnit(FmtNoMembers()), null, "t.nl")
    assert result.Success
    assert result.Text == "func f(): int {\n    return 1\n}\n"
}

test "an error diagnostic fails the reparse gate and a warning does not" {
    errors := new List<CompilerError>()
    assert !Formatter.HasReparseError(errors)

    errors.Add(new CompilerError(ErrorCode.UnexpectedToken, "w", 1, 1, ErrorSeverity.Warning))
    assert !Formatter.HasReparseError(errors)

    errors.Add(new CompilerError(ErrorCode.UnexpectedToken, "e", 2, 1, ErrorSeverity.Error))
    assert Formatter.HasReparseError(errors)
}

test "the rejection message names only the ERROR messages, joined with a semicolon" {
    errors := new List<CompilerError>()
    errors.Add(new CompilerError(ErrorCode.UnexpectedToken, "first", 1, 1, ErrorSeverity.Error))
    errors.Add(new CompilerError(ErrorCode.UnexpectedToken, "ignored", 2, 1, ErrorSeverity.Warning))
    errors.Add(new CompilerError(ErrorCode.UnexpectedToken, "second", 3, 1, ErrorSeverity.Error))
    assert Formatter.JoinErrorMessages(errors) == "first; second"
}

test "an empty error list joins to the empty string" {
    assert Formatter.JoinErrorMessages(new List<CompilerError>()) == ""
}

test "the rejected result carries the ORIGINAL source, not the formatted text" {
    warnings := new List<string>()
    warnings.Add("why")
    rejected := Formatter.FailedResult("original", warnings)
    assert !rejected.Success
    assert rejected.Text == "original"
    assert rejected.Warnings.Count == 1
}

// ---- a switch passes both gates ------------------------------------------------------------------
//
// THE REGRESSION THESE PIN: the walk once wrote C# labels (`case 0:`, `default:`) where the
// grammar demands an arrow, so the formatter's own output failed the reparse gate and EVERY file
// containing a switch was rejected — the CLI errored and the LSP handler silently returned null.

test "FormatSafe formats a file containing a switch instead of rejecting its own output" {
    source := "func classify(value: int): string {\n    switch value {\n        case 0 => {\n            return \"zero\"\n        }\n        default => {\n            return \"other\"\n        }\n    }\n}\n"
    parsed := ColumnarParserRecovery.ParseFileAst(source, "t.nl")
    unit := parsed.CompilationUnit
    assert unit != null
    formatter := FmtFormatter()
    result := formatter.FormatSafe(source, unit ?? FmtUnit(FmtNoMembers()), null, "t.nl")
    assert result.Success
    assert result.Warnings.Count == 0
    assert result.Text == source
}

test "an unbraced arrow case is canonicalized to braces without gaining a BlockStatement" {
    source := "func f(value: int): int {\n    switch value {\n        case 0 => return 1\n        default => return 2\n    }\n}\n"
    parsed := ColumnarParserRecovery.ParseFileAst(source, "t.nl")
    unit := parsed.CompilationUnit
    assert unit != null
    formatter := FmtFormatter()
    result := formatter.FormatSafe(source, unit ?? FmtUnit(FmtNoMembers()), null, "t.nl")
    assert result.Success
    assert result.Text == "func f(value: int): int {\n    switch value {\n        case 0 => {\n            return 1\n        }\n        default => {\n            return 2\n        }\n    }\n}\n"
}

test "a formatted switch re-parses and formats again to the same bytes" {
    source := "func classify(value: int): string {\nswitch value {\ncase 0 => {\nreturn \"zero\"\n}\ndefault => {\nreturn \"other\"\n}\n}\n}\n"
    parsed := ColumnarParserRecovery.ParseFileAst(source, "t.nl")
    unit := parsed.CompilationUnit
    assert unit != null
    formatter := FmtFormatter()
    formatted := formatter.Format(unit ?? FmtUnit(FmtNoMembers()), null)
    reparsed := ColumnarParserRecovery.ParseFileAst(formatted, "t.nl")
    reparsedUnit := reparsed.CompilationUnit
    assert reparsedUnit != null
    reformatter := FmtFormatter()
    reformatted := reformatter.Format(reparsedUnit ?? FmtUnit(FmtNoMembers()), null)
    assert reformatted == formatted
}

// ---- the configuration reaches the declaration walk ---------------------------------------------

test "the indent size configured on the formatter is the one the declaration body uses" {
    formatter := new Formatter(FmtConfig(2, true, 100))
    builder := new StringBuilder()
    formatter.FormatDeclaration(FmtClass("Holder", FmtOne(FmtField("a", "int", 1)), 1), builder)
    assert FmtShow(builder) == "class Holder {|  a: int|}|"
}

test "a tab indent is ONE tab per level, not one tab per configured size" {
    formatter := new Formatter(FmtConfig(4, false, 100))
    builder := new StringBuilder()
    formatter.FormatDeclaration(FmtClass("Holder", FmtOne(FmtField("a", "int", 1)), 1), builder)
    assert FmtShow(builder) == "class Holder {|\ta: int|}|"
}

test "a null configuration is the default configuration, which is four spaces" {
    formatter := new Formatter(null)
    builder := new StringBuilder()
    formatter.FormatDeclaration(FmtClass("Holder", FmtOne(FmtField("a", "int", 1)), 1), builder)
    assert FmtShow(builder) == "class Holder {|    a: int|}|"
}
