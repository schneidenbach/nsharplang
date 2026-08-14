namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE LINTER'S ENTRY AND ITS DECLARATION WALK (task 019 slice 12). These are the
// semantic assertions that came out of the last of `Linter.cs`: the fourteen extents of the public
// `Linter` and the `LintVisitor` it existed to drive.
//
// THE ENTRY WAS ASSERTABLE ONLY THROUGH A PARSER BEFORE THE MOVE. `LintVisitor` was `internal` and
// every walk member was private, so "an interface opens no member scope" or "a second `Lint` on the
// same `Linter` starts clean" could only be asked by writing a source file, parsing it and reading
// whatever fell out. Below each arm is handed an AST directly — including declaration shapes a parser
// will not put next to each other and a member walk that THROWS part-way through.
//
// FOUR THINGS THAT WERE PROSE, VACUOUS OR UNREACHABLE ARE STATED HERE AS CONTRACTS:
//   (a) ONE `Linter` LINTS MANY FILES, AND EACH FILE STARTS CLEAN. Every piece of per-file state is
//       built inside `Lint`; the object carries only the configuration. Two lints of the same unit
//       return equal answers and separate lists, which is what stops the second file in a `nlc lint`
//       run from inheriting the first file's scopes.
//   (b) AN INTERFACE OPENS NO TYPE-MEMBER SCOPE WHERE A CLASS DOES. The asymmetry was invisible in
//       C# because both arms were private; it is asserted here on the SAME member shape, so the
//       difference is the declaration kind and nothing else.
//   (c) THE TYPE-MEMBER SCOPE IS POPPED BY A `finally`, AND THE THROW THAT PROVES IT IS ONE NO
//       END-TO-END TEST COULD STAGE: a member initializer deep enough to trip the walk's recursion
//       guard. Without the `finally` the next type would read the previous type's member names.
//   (d) THE THREE PHASES OF `Visit` ARE ORDERED. Imports are registered before any declaration is
//       walked, the global scope is checked before it pops, and unused imports are checked after
//       everything — asserted as one diagnostic sequence rather than three independent facts.
func LdwConfig(): LinterConfig {
    return LinterConfig.Default()
}

func LdwState(): LinterWalkState {
    return new LinterWalkState("test.nl", null, LdwConfig())
}

func LdwCodes(diagnostics: List<Diagnostic>): string {
    codes := ""
    for diagnostic in diagnostics {
        codes = codes + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + ";"
    }

    return codes
}

func LdwStateCodes(state: LinterWalkState): string {
    return LdwCodes(state.Diagnostics)
}

func LdwSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func LdwId(name: string, line: int, column: int): IdentifierExpression {
    return new IdentifierExpression(name, line, column)
}

func LdwStatements(): List<Statement> {
    return new List<Statement>()
}

func LdwRead(name: string, line: int, column: int): ExpressionStatement {
    return new ExpressionStatement(LdwId(name, line, column), line, column)
}

func LdwBlock1(statement: Statement, line: int, column: int): BlockStatement {
    statements := LdwStatements()
    statements.Add(statement)
    return new BlockStatement(statements, line, column)
}

func LdwReadBlock(name: string, line: int, column: int): BlockStatement {
    return LdwBlock1(LdwRead(name, line, column), line, column)
}

func LdwDeclarations(): List<Declaration> {
    return new List<Declaration>()
}

func LdwAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func LdwInterfaces(): List<TypeReference> {
    return new List<TypeReference>()
}

func LdwField(name: string, typeName: string, initializer: Expression?): FieldDeclaration {
    return new FieldDeclaration(name, LdwSimple(typeName), initializer, Modifiers.None, PropertyModifier.None, LdwAttributes(), 1, 1)
}

func LdwFunction(name: string, body: BlockStatement?): FunctionDeclaration {
    return new FunctionDeclaration(name, new List<Parameter>(), null, body, null, null, null, Modifiers.None, LdwAttributes(), false, null, false, false, 7, 1)
}

func LdwClass(name: string, members: List<Declaration>): ClassDeclaration {
    return new ClassDeclaration(name, null, null, LdwInterfaces(), members, null, Modifiers.None, LdwAttributes(), 1, 1)
}

func LdwStruct(name: string, members: List<Declaration>): StructDeclaration {
    return new StructDeclaration(name, null, LdwInterfaces(), members, null, Modifiers.None, LdwAttributes(), 1, 1, false)
}

func LdwRecord(name: string, members: List<Declaration>): RecordDeclaration {
    return new RecordDeclaration(name, null, LdwInterfaces(), members, null, false, Modifiers.None, LdwAttributes(), 1, 1)
}

func LdwInterface(name: string, members: List<Declaration>): InterfaceDeclaration {
    return new InterfaceDeclaration(name, null, LdwInterfaces(), members, Modifiers.None, false, LdwAttributes(), 1, 1)
}

func LdwOneMember(member: Declaration): List<Declaration> {
    members := LdwDeclarations()
    members.Add(member)
    return members
}

func LdwUnit(declarations: List<Declaration>): CompilationUnit {
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

func LdwUnitOf(declaration: Declaration): CompilationUnit {
    return LdwUnit(LdwOneMember(declaration))
}

func LdwUnitWithImport(namespaceName: string, declarations: List<Declaration>): CompilationUnit {
    imports := new List<ImportDirective>()
    imports.Add(new ImportDirective(namespaceName, null, 1, 1))
    return new CompilationUnit(null, imports, new List<Statement>(), null, declarations, 1, 1)
}

// A tree deeper than the walk's recursion limit. The only shape that makes a member walk THROW, and
// therefore the only way to ask whether the type-member scope is popped on the exceptional path.
func LdwTooDeep(): Expression {
    node: Expression = LdwId("leaf", 1, 1)
    index := 0
    while index < LinterWalk.MaxRecursionDepth() + 5 {
        elements := new List<Expression>()
        elements.Add(node)
        node = new ArrayLiteralExpression(elements, false, 1, 1)
        index = index + 1
    }

    return node
}

// ── the public entry ─────────────────────────────────────────────────────────────────────────

test "a default Linter lints a unit and reports through the shared catalog" {
    linter := new Linter()
    diagnostics := linter.Lint(LdwUnitOf(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5))), "test.nl", null)
    assert LdwCodes(diagnostics) == "NL002@3:5;"
}

test "an explicitly null config is the default config" {
    // The C# spelled this `config ?? LinterConfig.Default()` in TWO places, because the visitor it
    // constructed re-asked the same question. One place answers it now, and this is that place.
    explicitNull := new Linter(null)
    diagnostics := explicitNull.Lint(LdwUnitOf(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5))), "test.nl", null)
    assert LdwCodes(diagnostics) == "NL002@3:5;"
}

test "(a) ONE Linter LINTS MANY FILES AND EACH ONE STARTS CLEAN" {
    // The per-file state is built inside `Lint`, so the second answer is the first answer and not
    // the first answer twice. A `nlc lint` run over a directory reuses one Linter.
    linter := new Linter(LdwConfig())
    unit := LdwUnitOf(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5)))
    first := linter.Lint(unit, "one.nl", null)
    second := linter.Lint(unit, "two.nl", null)
    assert LdwCodes(first) == "NL002@3:5;"
    assert LdwCodes(second) == "NL002@3:5;"
    assert second.Count == 1
}

test "(a) the two answers are SEPARATE lists, so a caller that keeps one is not editing the other" {
    // Asked by MUTATION rather than by reference identity, and that is the stronger question: a
    // caller that holds the first file's diagnostics must not see them change when the next file is
    // linted. (`object.ReferenceEquals` declines at `emit.call.static-member-unmodeled`.)
    linter := new Linter(LdwConfig())
    unit := LdwUnitOf(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5)))
    first := linter.Lint(unit, "one.nl", null)
    second := linter.Lint(unit, "two.nl", null)
    first.Clear()
    assert first.Count == 0
    assert second.Count == 1
    assert LdwCodes(second) == "NL002@3:5;"
}

test "the configuration is the ONE thing the Linter itself carries" {
    config := LdwConfig()
    config.AddDisabledRule("NL002")
    linter := new Linter(config)
    diagnostics := linter.Lint(LdwUnitOf(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5))), "test.nl", null)
    assert diagnostics.Count == 0
}

test "the source text reaches the suppression parser" {
    // Non-vacuity for the argument itself: the same unit with no source text still reports.
    source := "// nlc:ignore:NL002\nStringBuilder\n"
    linter := new Linter()
    suppressed := linter.Lint(LdwUnitOf(LdwFunction("main", LdwReadBlock("StringBuilder", 2, 1))), "test.nl", source)
    reported := linter.Lint(LdwUnitOf(LdwFunction("main", LdwReadBlock("StringBuilder", 2, 1))), "test.nl", null)
    assert suppressed.Count == 0
    assert LdwCodes(reported) == "NL002@2:1;"
}

// ── the three phases of Visit ────────────────────────────────────────────────────────────────

test "(d) THE IMPORTS ARE REGISTERED BEFORE ANY DECLARATION IS WALKED" {
    // The import must already be known when the function body reads the name, or NL002 fires on a
    // name the file did import.
    state := LdwState()
    walk := new LinterDeclarationWalk(state)
    walk.Visit(LdwUnitWithImport("System.Text", LdwOneMember(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5)))))
    assert state.Diagnostics.Count == 0
}

test "(d) VISIT OPENS ITS OWN GLOBAL SCOPE, SO THE FRAME IT CHECKS IS NOT THE CALLER'S" {
    // A name bound before `Visit` is pushed AWAY by `Visit`'s own `PushScope` and is therefore not
    // the frame `CheckUnusedVariables` reads. The measured answer is silence, and it is stated
    // rather than assumed: the file-level check belongs to the declarations, not to the caller.
    state := LdwState()
    state.DeclareVariable("orphan", 4, 3)
    new LinterDeclarationWalk(state).Visit(LdwUnit(LdwDeclarations()))
    assert state.Diagnostics.Count == 0
}

test "(d) AND THE FRAME IS RESTORED, WHICH IS WHAT MAKES THE SILENCE ABOVE A PUSH AND NOT A LOSS" {
    // Non-vacuity for the contract above: the binding survives `Visit` intact and is still there to
    // report. `PushScope` / `PopScope` bracket the whole declaration walk.
    state := LdwState()
    state.DeclareVariable("orphan", 4, 3)
    new LinterDeclarationWalk(state).Visit(LdwUnit(LdwDeclarations()))
    state.CheckUnusedVariables()
    assert LdwStateCodes(state) == "NL001@4:3;"
}

test "(d) THE UNUSED-IMPORT CHECK IS THE LAST PHASE, SO ITS ROW COMES AFTER THE WALK'S" {
    // The order is observable because the diagnostic list is append-only: the body's NL002 is
    // written while the walk runs and the import's NL010 only after the global scope has closed.
    state := LdwState()
    new LinterDeclarationWalk(state).Visit(LdwUnitWithImport("System.Linq", LdwOneMember(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5)))))
    assert LdwStateCodes(state) == "NL002@3:5;NL010@1:1;"
}

test "(d) VISIT'S OWN GLOBAL UNUSED-VARIABLE CHECK IS MEASURABLY VACUOUS, AND THAT IS RECORDED" {
    // Every declaration arm that can bind a name reaches the state through a walk that opens its
    // own scope first — a function pushes one, and so does every block — so nothing is ever left in
    // the frame `Visit` opens. The call is reproduced from the C# rather than tidied away, and this
    // is the assertion that says so: a unit full of binding declarations still leaves it empty.
    state := LdwState()
    declarations := LdwDeclarations()
    declarations.Add(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5)))
    declarations.Add(new ConstructorDeclaration(new List<Parameter>(), LdwReadBlock("StringBuilder", 8, 3), null, Modifiers.None, LdwAttributes(), 1, 1))
    declarations.Add(new SetupDeclaration(LdwReadBlock("StringBuilder", 12, 5), 1, 1))
    new LinterDeclarationWalk(state).Visit(LdwUnit(declarations))
    assert LdwStateCodes(state) == "NL002@3:5;NL002@8:3;NL002@12:5;"
}

test "an import used only inside a declaration is not an unused import" {
    // Non-vacuity for the phase order above: the same import with nothing reading it IS reported.
    used := LdwState()
    new LinterDeclarationWalk(used).Visit(LdwUnitWithImport("System.Text", LdwOneMember(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5)))))
    unused := LdwState()
    new LinterDeclarationWalk(unused).Visit(LdwUnitWithImport("System.Text", LdwDeclarations()))
    assert used.Diagnostics.Count == 0
    assert LdwStateCodes(unused) == "NL010@1:1;"
}

// ── the declaration arms ─────────────────────────────────────────────────────────────────────

test "the function arm is entered through the walk owner" {
    state := LdwState()
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(LdwFunction("main", LdwReadBlock("StringBuilder", 3, 5))))
    assert LdwStateCodes(state) == "NL002@3:5;"
}

test "a field's initializer is walked" {
    state := LdwState()
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(LdwField("value", "int", LdwId("StringBuilder", 6, 9))))
    assert LdwStateCodes(state) == "NL002@6:9;"
}

test "a field with no initializer is walked no further" {
    state := LdwState()
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(LdwField("value", "int", null)))
    assert state.Diagnostics.Count == 0
}

test "a property's THREE bodies are each walked, in the order the arm reads them" {
    state := LdwState()
    property := new PropertyDeclaration("Value", LdwSimple("int"), LdwReadBlock("StringBuilder", 5, 1), LdwReadBlock("StringBuilder", 6, 1), LdwId("StringBuilder", 4, 1), Modifiers.None, PropertyModifier.None, LdwAttributes(), 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(property))
    assert LdwStateCodes(state) == "NL002@4:1;NL002@5:1;NL002@6:1;"
}

test "a constructor's body is walked" {
    state := LdwState()
    constructor := new ConstructorDeclaration(new List<Parameter>(), LdwReadBlock("StringBuilder", 8, 3), null, Modifiers.None, LdwAttributes(), 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(constructor))
    assert LdwStateCodes(state) == "NL002@8:3;"
}

test "a table test's CASES are walked before its body" {
    state := LdwState()
    row := new List<Expression>()
    row.Add(LdwId("StringBuilder", 3, 3))
    cases := new List<List<Expression>>()
    cases.Add(row)
    parameters := new List<Parameter>()
    parameters.Add(new Parameter("input", LdwSimple("int"), null, false, ParameterModifier.None, null, 1, 1, false, null))
    testDeclaration := new TestDeclaration("a table test", LdwReadBlock("StringBuilder", 9, 5), parameters, cases, null, 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(testDeclaration))
    assert LdwStateCodes(state) == "NL002@3:3;NL002@9:5;"
}

test "a test with no table walks only its body" {
    state := LdwState()
    testDeclaration := new TestDeclaration("a plain test", LdwReadBlock("StringBuilder", 9, 5), null, null, null, 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(testDeclaration))
    assert LdwStateCodes(state) == "NL002@9:5;"
}

test "a setup body and a teardown body are both walked" {
    state := LdwState()
    declarations := LdwDeclarations()
    declarations.Add(new SetupDeclaration(LdwReadBlock("StringBuilder", 2, 5), 1, 1))
    declarations.Add(new TeardownDeclaration(LdwReadBlock("StringBuilder", 12, 5), 1, 1))
    new LinterDeclarationWalk(state).Visit(LdwUnit(declarations))
    assert LdwStateCodes(state) == "NL002@2:5;NL002@12:5;"
}

test "AN ENUM IS MATCHED AND WALKED NO FURTHER, AND ITS MEMBER VALUES PROVE IT" {
    // The empty arm is not decoration: an enum member carries an EXPRESSION, and it is not visited.
    state := LdwState()
    members := new List<EnumMember>()
    members.Add(new EnumMember("First", LdwId("StringBuilder", 3, 7), 3, 5))
    enumDeclaration := new EnumDeclaration("Kind", members, EnumType.Int, Modifiers.None, LdwAttributes(), 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(enumDeclaration))
    assert state.Diagnostics.Count == 0
}

test "a union is matched and walked no further" {
    state := LdwState()
    unionDeclaration := new UnionDeclaration("Shape", null, new List<UnionCase>(), Modifiers.None, LdwAttributes(), 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(unionDeclaration))
    assert state.Diagnostics.Count == 0
}

test "a SoA record's column TYPES are tracked and it has nothing else to walk" {
    // The import is used by the column type alone, so the absence of NL010 is the whole assertion.
    state := LdwState()
    columns := new List<SoaColumnDeclaration>()
    columns.Add(new SoaColumnDeclaration("first", LdwSimple("StringBuilder"), 2, 5))
    soaRecord := new SoaRecordDeclaration("Points", columns, Modifiers.None, LdwAttributes(), 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitWithImport("System.Text", LdwOneMember(soaRecord)))
    assert state.Diagnostics.Count == 0
}

test "a class's base type and interfaces are tracked as used names" {
    state := LdwState()
    interfaces := LdwInterfaces()
    interfaces.Add(LdwSimple("StringBuilder"))
    classDeclaration := new ClassDeclaration("Widget", null, LdwSimple("StringBuilder"), interfaces, LdwDeclarations(), null, Modifiers.None, LdwAttributes(), 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitWithImport("System.Text", LdwOneMember(classDeclaration)))
    assert state.Diagnostics.Count == 0
}

test "an interface's base interfaces are tracked as used names" {
    state := LdwState()
    bases := LdwInterfaces()
    bases.Add(LdwSimple("StringBuilder"))
    interfaceDeclaration := new InterfaceDeclaration("Shape", null, bases, LdwDeclarations(), Modifiers.None, false, LdwAttributes(), 1, 1)
    new LinterDeclarationWalk(state).Visit(LdwUnitWithImport("System.Text", LdwOneMember(interfaceDeclaration)))
    assert state.Diagnostics.Count == 0
}

// ── the type-member scope ────────────────────────────────────────────────────────────────────

test "(b) A CLASS OPENS A TYPE-MEMBER SCOPE" {
    state := LdwState()
    members := LdwDeclarations()
    members.Add(LdwField("StringBuilder", "int", null))
    members.Add(LdwFunction("read", LdwReadBlock("StringBuilder", 5, 9)))
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(LdwClass("Widget", members)))
    assert state.Diagnostics.Count == 0
}

test "(b) A STRUCT OPENS ONE TOO" {
    state := LdwState()
    members := LdwDeclarations()
    members.Add(LdwField("StringBuilder", "int", null))
    members.Add(LdwFunction("read", LdwReadBlock("StringBuilder", 5, 9)))
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(LdwStruct("Point", members)))
    assert state.Diagnostics.Count == 0
}

test "(b) A RECORD OPENS ONE TOO" {
    state := LdwState()
    members := LdwDeclarations()
    members.Add(LdwField("StringBuilder", "int", null))
    members.Add(LdwFunction("read", LdwReadBlock("StringBuilder", 5, 9)))
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(LdwRecord("Pair", members)))
    assert state.Diagnostics.Count == 0
}

test "(b) AN INTERFACE OPENS NONE, ON THE SAME MEMBER SHAPE" {
    // The identical member list under a different declaration kind. This asymmetry lived in the C#
    // as the absence of a call and could not be asserted while both arms were private.
    state := LdwState()
    members := LdwDeclarations()
    members.Add(LdwField("StringBuilder", "int", null))
    members.Add(LdwFunction("read", LdwReadBlock("StringBuilder", 5, 9)))
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(LdwInterface("Shape", members)))
    assert LdwStateCodes(state) == "NL002@5:9;"
}

test "the type-member scope is popped when the type ends" {
    state := LdwState()
    members := LdwDeclarations()
    members.Add(LdwField("StringBuilder", "int", null))
    declarations := LdwDeclarations()
    declarations.Add(LdwClass("Widget", members))
    declarations.Add(LdwFunction("read", LdwReadBlock("StringBuilder", 9, 1)))
    new LinterDeclarationWalk(state).Visit(LdwUnit(declarations))
    assert LdwStateCodes(state) == "NL002@9:1;"
}

test "a NESTED type's member names do not escape to the enclosing type" {
    state := LdwState()
    innerMembers := LdwDeclarations()
    innerMembers.Add(LdwField("StringBuilder", "int", null))
    outerMembers := LdwDeclarations()
    outerMembers.Add(LdwClass("Inner", innerMembers))
    outerMembers.Add(LdwFunction("read", LdwReadBlock("StringBuilder", 9, 1)))
    new LinterDeclarationWalk(state).Visit(LdwUnitOf(LdwClass("Outer", outerMembers)))
    assert LdwStateCodes(state) == "NL002@9:1;"
}

test "(c) THE TYPE-MEMBER SCOPE IS POPPED EVEN WHEN A MEMBER WALK THROWS" {
    // The `finally` the callback used to own. Without it the name declared by the abandoned type
    // would go on silencing NL002 for the rest of the file.
    state := LdwState()
    walk := new LinterDeclarationWalk(state)
    members := LdwDeclarations()
    members.Add(LdwField("StringBuilder", "int", null))
    members.Add(LdwField("deep", "int", LdwTooDeep()))
    assert throws InvalidOperationException {
        walk.VisitClass(LdwClass("Widget", members))
    }

    state.CheckMissingImport(LdwId("StringBuilder", 9, 1))
    assert LdwStateCodes(state) == "NL002@9:1;"
}

test "(c) non-vacuity: without the throw the same name is silenced inside the type" {
    state := LdwState()
    walk := new LinterDeclarationWalk(state)
    members := LdwDeclarations()
    members.Add(LdwField("StringBuilder", "int", null))
    members.Add(LdwFunction("read", LdwReadBlock("StringBuilder", 5, 9)))
    walk.VisitClass(LdwClass("Widget", members))
    assert state.Diagnostics.Count == 0
}
