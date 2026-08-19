namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
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

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE END-TO-END RULE CONTRACTS (020 slice 8).
//
// These came out of `tests/LinterTests.cs`, which is deleted. Everything above asks the declaration
// WALK a question by handing it an AST; everything below asks the whole LINTER a question the way a
// user does — by writing N# source, parsing it, and reading what falls out. Both layers are real:
// the walk contracts can stage shapes a parser will not produce, and these prove the parser, the
// walk, the rule kernels, the suppression parser and the span resolver agree end to end.
//
// The deleted file's three private helpers are reproduced exactly: `Lint` parses with NO file name
// and lints with no source text, `LintWithSource` supplies both (which is the only way spans
// resolve), and `LintFile` reads the file off disk first. A parse that answers no compilation unit
// THROWS here rather than answering an empty list — the C# spelled that `!` and would have turned
// every "no diagnostic" contract into a contract about nothing.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

func LntLint(sourceText: string): List<Diagnostic> {
    parsed := ColumnarParserRecovery.ParseFileAst(sourceText, null)
    unit := parsed.CompilationUnit
    if unit != null {
        linter := new Linter()
        return linter.Lint(unit, "test.nl", null)
    }

    throw new InvalidOperationException("the parser answered no compilation unit")
}

func LntLintWithSource(sourceText: string): List<Diagnostic> {
    parsed := ColumnarParserRecovery.ParseFileAst(sourceText, "test.nl")
    unit := parsed.CompilationUnit
    if unit != null {
        linter := new Linter()
        return linter.Lint(unit, "test.nl", sourceText)
    }

    throw new InvalidOperationException("the parser answered no compilation unit")
}

func LntLintFile(filePath: string): List<Diagnostic> {
    sourceText := File.ReadAllText(filePath)
    parsed := ColumnarParserRecovery.ParseFileAst(sourceText, filePath)
    unit := parsed.CompilationUnit
    if unit != null {
        linter := new Linter()
        return linter.Lint(unit, filePath, sourceText)
    }

    throw new InvalidOperationException("the parser answered no compilation unit")
}

func LntCountOf(diagnostics: List<Diagnostic>, code: string): int {
    total := 0
    for diagnostic in diagnostics {
        if diagnostic.Code == code {
            total = total + 1
        }
    }

    return total
}

func LntHasCode(diagnostics: List<Diagnostic>, code: string): bool {
    return LntCountOf(diagnostics, code) > 0
}

func LntHas(diagnostics: List<Diagnostic>, code: string, messageFragment: string): bool {
    for diagnostic in diagnostics {
        if diagnostic.Code == code && diagnostic.Message.Contains(messageFragment) {
            return true
        }
    }

    return false
}

func LntHasMessage(diagnostics: List<Diagnostic>, messageFragment: string): bool {
    for diagnostic in diagnostics {
        if diagnostic.Message.Contains(messageFragment) {
            return true
        }
    }

    return false
}

func LntHasSuggestion(diagnostics: List<Diagnostic>, code: string, suggestionFragment: string): bool {
    for diagnostic in diagnostics {
        if diagnostic.Code == code {
            suggestion := diagnostic.Suggestion
            if suggestion != null && suggestion.Contains(suggestionFragment) {
                return true
            }
        }
    }

    return false
}

func LntHasBoth(diagnostics: List<Diagnostic>, code: string, messageFragment: string, suggestionFragment: string): bool {
    for diagnostic in diagnostics {
        if diagnostic.Code == code && diagnostic.Message.Contains(messageFragment) {
            suggestion := diagnostic.Suggestion
            if suggestion != null && suggestion.Contains(suggestionFragment) {
                return true
            }
        }
    }

    return false
}

func LntFirstOf(diagnostics: List<Diagnostic>, code: string): Diagnostic {
    for diagnostic in diagnostics {
        if diagnostic.Code == code {
            return diagnostic
        }
    }

    throw new InvalidOperationException("no diagnostic with code " + code)
}

func LntSingleOf(diagnostics: List<Diagnostic>, code: string): Diagnostic {
    matched := new List<Diagnostic>()
    for diagnostic in diagnostics {
        if diagnostic.Code == code {
            matched.Add(diagnostic)
        }
    }

    if matched.Count != 1 {
        throw new InvalidOperationException("expected exactly one " + code + ", found " + matched.Count.ToString())
    }

    return matched[0]
}

func LntTempDirectory(tag: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-linter-" + tag + "-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    return directory
}

// ── NL001: unused variable ────────────────────────────────────────────────────────────────────

test "NL001 reports a variable that is declared and never read" {
    diagnostics := LntLint("func main() { x := 5 }")
    assert diagnostics.Count == 1
    assert diagnostics[0].Code == "NL001"
    assert diagnostics[0].Message.Contains("'x'")
    assert diagnostics[0].Message.Contains("never read")
    assert diagnostics[0].Severity == DiagnosticSeverity.Error
}

test "NL001 allows an underscore-prefixed intentionally unused variable" {
    assert !LntHasCode(LntLint("\nfunc main() {\n    _x := 5\n}"), "NL001")
}

test "NL001 says nothing about a variable that IS read" {
    assert !LntHas(LntLint("\nfunc main() {\n    x := 5\n    y := x + 1\n}"), "NL001", "'x'")
}

test "NL001 reports every unused variable, not just the first" {
    diagnostics := LntLint("\nfunc main() {\n    x := 5\n    y := 10\n    z := 15\n}")
    assert LntCountOf(diagnostics, "NL001") == 3
    assert LntHas(diagnostics, "NL001", "'x'")
    assert LntHas(diagnostics, "NL001", "'y'")
    assert LntHas(diagnostics, "NL001", "'z'")
}

test "NL001 counts a read inside an expression as a use" {
    diagnostics := LntLint("\nfunc main() {\n    x := 5\n    y := x + 10\n    z := y + 1\n}")
    assert !LntHas(diagnostics, "NL001", "'x'")
    assert !LntHas(diagnostics, "NL001", "'y'")
    // …and the one nothing reads is still reported, which is what makes the two above non-vacuous.
    assert LntHas(diagnostics, "NL001", "'z'")
}

test "NL001 is not the rule for parameters" {
    assert !LntHasCode(LntLint("\nfunc add(a: int, b: int): int {\n    return a + b\n}"), "NL001")
}

test "NL001 counts a loop variable and an indexed collection as used" {
    diagnostics := LntLint("\nfunc main() {\n    numbers := [1, 2, 3]\n    for i := 0; i < 3; i = i + 1 {\n        print(numbers[i])\n    }\n}")
    assert !LntHas(diagnostics, "NL001", "'i'")
    assert !LntHasMessage(diagnostics, "'numbers'")
}

test "NL001 reaches into a nested scope" {
    diagnostics := LntLint("\nfunc main() {\n    x := 5\n    if true {\n        y := 10\n    }\n}")
    assert LntHas(diagnostics, "NL001", "'x'")
    assert LntHas(diagnostics, "NL001", "'y'")
}

test "NL001 does not count an ASSIGNMENT as the read that saves a variable" {
    // `x = 10` writes; `y := x + 1` reads. The read is what clears x, and y is left unread.
    diagnostics := LntLint("\nfunc main() {\n    x := 5\n    x = 10\n    y := x + 1\n}")
    assert !LntHas(diagnostics, "NL001", "'x'")
    assert LntHas(diagnostics, "NL001", "'y'")
}

// ── inline and comment suppression ────────────────────────────────────────────────────────────

test "an inline nlc:ignore disables the named diagnostic on the SAME line" {
    diagnostics := LntLintWithSource("func main() {\n    unused := 5 // nlc:ignore NL001\n}")
    assert !LntHas(diagnostics, "NL001", "'unused'")
}

test "a comment nlc:ignore disables the named diagnostic on the NEXT CODE LINE ONLY" {
    diagnostics := LntLintWithSource("func main() {\n    // nlc:ignore NL001\n    suppressed := 5\n    reported := 6\n}")
    assert !LntHas(diagnostics, "NL001", "'suppressed'")
    assert LntHas(diagnostics, "NL001", "'reported'")
}

test "a suppression naming a DIFFERENT code suppresses nothing" {
    // The deleted file only ever suppressed the code that was actually firing, so a suppression
    // parser that ignored the code and silenced the line would have passed it.
    diagnostics := LntLintWithSource("func main() {\n    unused := 5 // nlc:ignore NL010\n}")
    assert LntHas(diagnostics, "NL001", "'unused'")
}

// ── the resolved spans ────────────────────────────────────────────────────────────────────────

test "NL012's span covers the PARAMETER name" {
    diagnostic := LntSingleOf(LntLintWithSource("func greet(unusedName: string) { print \"hi\" }"), "NL012")
    assert diagnostic.Location.Line == 1
    assert diagnostic.Location.Column == 12
    assert diagnostic.Length == "unusedName".Length
}

test "NL004's span covers the FUNCTION name, not the async keyword" {
    diagnostic := LntSingleOf(LntLintWithSource("async func LoadData(): void { print \"hi\" }"), "NL004")
    assert diagnostic.Location.Line == 1
    assert diagnostic.Location.Column == 12
    assert diagnostic.Length == "LoadData".Length
}

// ── NL002: missing import ─────────────────────────────────────────────────────────────────────

test "NL002 reports List with the System.Collections.Generic suggestion" {
    diagnostics := LntLint("\nfunc main() {\n    list := new List<int>()\n}")
    assert LntHas(diagnostics, "NL002", "List")
    assert LntHasSuggestion(diagnostics, "NL002", "System.Collections.Generic")
}

test "NL002 says nothing when the import is already present" {
    diagnostics := LntLint("\nimport System.Collections.Generic\n\nfunc main() {\n    list := new List<int>()\n}")
    assert !LntHas(diagnostics, "NL002", "List")
}

test "NL002 reports Dictionary" {
    assert LntHas(LntLint("\nfunc main() {\n    dict := new Dictionary<string, int>()\n}"), "NL002", "Dictionary")
}

test "NL002 reports StringBuilder with the System.Text suggestion" {
    diagnostics := LntLint("\nfunc main() {\n    sb := new StringBuilder()\n}")
    assert LntHas(diagnostics, "NL002", "StringBuilder")
    assert LntHasSuggestion(diagnostics, "NL002", "System.Text")
}

test "NL002 reports HttpClient with the System.Net.Http suggestion" {
    diagnostics := LntLint("\nfunc main() {\n    client := new HttpClient()\n}")
    assert LntHas(diagnostics, "NL002", "HttpClient")
    assert LntHasSuggestion(diagnostics, "NL002", "System.Net.Http")
}

test "NL002 reports Task with the System.Threading.Tasks suggestion" {
    diagnostics := LntLint("\nfunc main() {\n    task := new Task(() => {})\n}")
    assert LntHas(diagnostics, "NL002", "Task")
    assert LntHasSuggestion(diagnostics, "NL002", "System.Threading.Tasks")
}

test "NL002 fires on a bare identifier reference, not only on `new`" {
    assert LntHas(LntLint("\nfunc main() {\n    list := List<int>()\n}"), "NL002", "List")
}

test "NL002 does not suggest a namespace for a type a FILE import brought in" {
    diagnostics := LntLint("\nimport \"../Models/Task\"\n\nclass TaskService {\n    tasks: List<Task>\n}")
    assert !LntHasBoth(diagnostics, "NL002", "Task", "System.Threading.Tasks")
}

test "NL002 does not mistake an instance member for a known type of the same name" {
    diagnostics := LntLint("\nclass HttpUrl {\n    Path: string = \"/api/items\"\n\n    func ToDisplayString(): string {\n        pathLength := Path.Length\n        return $\"{Path}:{pathLength}\"\n    }\n}")
    assert !LntHasBoth(diagnostics, "NL002", "Path", "System.IO")
}

// ── NL003: unnecessary null check on a value literal ──────────────────────────────────────────

test "NL003 names the literal's type: int" {
    assert LntHas(LntLint("\nfunc main() {\n    if 5 != null {\n        print(\"hello\")\n    }\n}"), "NL003", "int")
}

test "NL003 names the literal's type: float" {
    assert LntHas(LntLint("\nfunc main() {\n    if 3.14 == null {\n        print(\"hello\")\n    }\n}"), "NL003", "float")
}

test "NL003 names the literal's type: bool" {
    assert LntHas(LntLint("\nfunc main() {\n    if true != null {\n        print(\"hello\")\n    }\n}"), "NL003", "bool")
}

test "NL003 leaves a STRING null check alone, because a string is a reference type" {
    diagnostics := LntLint("\nfunc main() {\n    str := \"hello\"\n    if str != null {\n        y := str + \" world\"\n    }\n}")
    assert LntCountOf(diagnostics, "NL003") == 0
}

test "NL003 reads a while condition as well as an if condition" {
    assert LntCountOf(LntLint("\nfunc main() {\n    x := 0\n    while 5 == null {\n        x = x + 1\n    }\n}"), "NL003") > 0
}

// ── NL004: async without await ────────────────────────────────────────────────────────────────

test "NL004 names the async function that never awaits" {
    assert LntHas(LntLint("\nasync func process(): Task {\n    x := 5\n    return Task.CompletedTask\n}"), "NL004", "process")
}

test "NL004 says nothing when the function does await" {
    assert LntCountOf(LntLint("\nasync func process(): Task {\n    await Task.Delay(100)\n}"), "NL004") == 0
}

test "NL004 says nothing about a function that is not async" {
    assert LntCountOf(LntLint("\nfunc process() {\n    x := 5\n}"), "NL004") == 0
}

test "NL004 reaches a method inside a class" {
    assert LntCountOf(LntLint("\nclass MyClass {\n    async func process(): Task {\n        x := 5\n        return Task.CompletedTask\n    }\n}"), "NL004") > 0
}

// ── NL006: unreachable code ───────────────────────────────────────────────────────────────────

test "NL006 errors on a statement after a return" {
    diagnostics := LntLint("\nfunc main() {\n    return\n    x := 5\n}")
    assert LntHasCode(diagnostics, "NL006")
    assert LntFirstOf(diagnostics, "NL006").Severity == DiagnosticSeverity.Error
}

test "NL006 says nothing when the return is last" {
    assert !LntHasCode(LntLint("\nfunc main() {\n    x := 5\n    return\n}"), "NL006")
}

// ── NL011: empty catch ────────────────────────────────────────────────────────────────────────

test "NL011 errors on an empty catch block" {
    diagnostics := LntLint("\nfunc main() {\n    try {\n        x := 5\n    } catch {\n    }\n}")
    assert LntHasCode(diagnostics, "NL011")
    assert LntFirstOf(diagnostics, "NL011").Severity == DiagnosticSeverity.Error
}

test "NL011's span covers the catch KEYWORD" {
    diagnostic := LntSingleOf(LntLintWithSource("func main() {\n    try {\n        print \"x\"\n    } catch {\n    }\n}"), "NL011")
    assert diagnostic.Location.Line == 4
    assert diagnostic.Location.Column == 7
    assert diagnostic.Length == "catch".Length
}

test "NL011 says nothing when the catch has statements in it" {
    assert !LntHasCode(LntLint("\nimport System\nfunc main() {\n    try {\n        x := 5\n    } catch (e: Exception) {\n        Console.WriteLine(e.Message)\n    }\n}"), "NL011")
}

// ── NL012: unused parameter ───────────────────────────────────────────────────────────────────

test "NL012 errors on a parameter that is never read" {
    diagnostics := LntLint("\nfunc add(a: int, b: int): int {\n    return a\n}")
    assert LntHas(diagnostics, "NL012", "'b'")
    assert LntFirstOf(diagnostics, "NL012").Severity == DiagnosticSeverity.Error
}

test "NL012 says nothing when every parameter is read" {
    assert !LntHasCode(LntLint("\nfunc add(a: int, b: int): int {\n    return a + b\n}"), "NL012")
}

test "NL012 respects the underscore convention on parameters" {
    // The convention is an explicit 'intentionally unused' signal, so the build-blocking error must
    // not fire for it.
    assert !LntHas(LntLint("\nfunc handler(event: int, _context: int) {\n    x := event + 1\n}"), "NL012", "_context")
}

test "NL012 counts a read inside a NESTED LOCAL FUNCTION as a use" {
    assert !LntHasCode(LntLint("\nfunc outer(value: int): int {\n    func inner(): int {\n        return value\n    }\n    return inner()\n}"), "NL012")
}

test "NL012 counts a read inside a LAMBDA as a use" {
    assert !LntHasCode(LntLint("\nfunc outer(value: int): int {\n    var f = () => value\n    return f()\n}"), "NL012")
}

test "NL012 still flags a genuinely unused parameter alongside a nested function" {
    diagnostics := LntLint("\nfunc outer(used: int, unused: int): int {\n    func inner(): int {\n        return used\n    }\n    return inner()\n}")
    assert LntHas(diagnostics, "NL012", "'unused'")
    assert !LntHas(diagnostics, "NL012", "'used'")
}

test "NL012 still flags a parameter SHADOWED by a local in the nested function" {
    // Over-suppression guard: `inner` reads its OWN `value`, not the enclosing parameter.
    assert LntHas(LntLint("\nfunc outer(value: int): int {\n    func inner(): int {\n        value := 1\n        return value\n    }\n    return inner()\n}"), "NL012", "'value'")
}

// ── NL020: shadowed variable ──────────────────────────────────────────────────────────────────

test "NL020 errors when an inner binding shadows an outer one" {
    diagnostics := LntLint("\nfunc main() {\n    x := 5\n    if true {\n        x := 10\n        y := x + 1\n    }\n}")
    assert LntHas(diagnostics, "NL020", "'x'")
    assert LntFirstOf(diagnostics, "NL020").Severity == DiagnosticSeverity.Error
}

test "NL020 says nothing for distinct names" {
    assert !LntHasCode(LntLint("\nfunc main() {\n    x := 5\n    if true {\n        y := 10\n        z := x + y\n    }\n}"), "NL020")
}

test "NL020 respects the underscore convention" {
    assert !LntHasCode(LntLint("\nfunc main() {\n    _x := 5\n    if true {\n        _x := 10\n        y := _x + 1\n    }\n}"), "NL020")
}

// ── NL010: unused import ──────────────────────────────────────────────────────────────────────

test "NL010 errors on an import nothing uses" {
    diagnostics := LntLint("\nimport System.Collections.Generic\n\nfunc Main() {\n    x := 5\n    y := x + 1\n}")
    assert LntFirstOf(diagnostics, "NL010").Severity == DiagnosticSeverity.Error
}

test "NL010 counts a BASE TYPE LIST as usage — class" {
    assert LntCountOf(LntLint("import System\n\nclass DataStore: Exception {}"), "NL010") == 0
}

test "NL010 counts a BASE TYPE LIST as usage — struct" {
    assert LntCountOf(LntLint("import System\n\nstruct Buffer: IDisposable {}"), "NL010") == 0
}

test "NL010 counts a BASE TYPE LIST as usage — and still flags the import next to it" {
    assert LntCountOf(LntLint("import System\nimport System.Linq\n\nclass D: Exception {}"), "NL010") == 1
}

test "NL010 counts a TYPEOF OPERAND as usage" {
    assert LntCountOf(LntLint("import System.IO\n\nclass R {\n    func Run() {\n        t := typeof(MemoryStream)\n    }\n}"), "NL010") == 0
}

test "NL010 counts a TYPEOF OPERAND as usage — and still flags the import next to it" {
    assert LntCountOf(LntLint("import System.IO\nimport System.Linq\n\nclass R {\n    func Run() {\n        t := typeof(MemoryStream)\n    }\n}"), "NL010") == 1
}

test "NL010 counts a typeof operand that names an ENUM as usage" {
    assert LntCountOf(LntLint("import System.Text.Json\n\nclass R {\n    func Run() {\n        t := typeof(JsonValueKind)\n    }\n}"), "NL010") == 0
}

test "NL010 counts a POSITIONAL parameter's declared type as usage" {
    assert LntCountOf(LntLint("import System.Collections.Generic\n\nrecord Foo(items: List<int>)"), "NL010") == 0
}

test "NL010 resolves StringComparison to the System namespace" {
    assert LntCountOf(LntLint("import System\n\nfunc Main() {\n    c := StringComparison.Ordinal\n}"), "NL010") == 0
}

test "NL010's SQUIGGLE COVERS THE NAMESPACE PATH, NOT THE import KEYWORD" {
    // Regression for the strictness/squiggle audit (PR #160). The directive records only the
    // statement column, so the linter steps past the keyword to land on the path.
    sourceText := "\nimport System.Linq\n\nfunc Main() {\n    x := 5\n    y := x + 1\n}"
    diagnostic := LntSingleOf(LntLintWithSource(sourceText), "NL010")
    lines := sourceText.Replace("\r\n", "\n").Split('\n')
    importLine := lines[diagnostic.Location.Line - 1]
    covered := importLine.Substring(diagnostic.Location.Column - 1, diagnostic.Length)
    assert covered == "System.Linq"
    assert diagnostic.Length == "System.Linq".Length
}

test "NL010 says nothing when the imported type IS used" {
    assert !LntHasCode(LntLint("\nimport System.Collections.Generic\n\nfunc Main() {\n    list := new List<int>()\n    x := list\n}"), "NL010")
}

test "NL010 counts Console as usage of System" {
    assert !LntHasCode(LntLint("\nimport System\n\nfunc Main() {\n    Console.WriteLine(\"hi\")\n}"), "NL010")
}

test "NL010 counts Char as usage of System" {
    assert !LntHasCode(LntLint("\nimport System\n\nfunc Main(): bool {\n    return Char.IsWhiteSpace(' ')\n}"), "NL010")
}

test "NL010 stays silent on a namespace it does not track" {
    assert !LntHasCode(LntLint("\nimport MyCompany.MyLibrary\n\nfunc Main() {\n    x := 5\n    y := x + 1\n}"), "NL010")
}

test "NL010 counts a LINQ extension method call as usage of System.Linq" {
    assert !LntHasCode(LntLint("\nimport System.Collections.Generic\nimport System.Linq\n\nfunc Main() {\n    items := new List<int>()\n    filtered := items.Where(x => x > 1)\n    result := filtered.Select(x => x * 2)\n    _ := result\n}"), "NL010")
}

test "NL010 counts ToList as usage of System.Linq" {
    assert !LntHasCode(LntLint("\nimport System.Collections.Generic\nimport System.Linq\n\nfunc Main() {\n    items := new List<int>()\n    result := items.ToList()\n    _ := result\n}"), "NL010")
}

test "NL010 counts a GENERIC INTERFACE return type as usage" {
    assert !LntHasCode(LntLint("\nimport System.Collections.Generic\n\nfunc GetItems(): IEnumerable<int> {\n    return new List<int>()\n}"), "NL010")
}

test "NL010 counts IAsyncEnumerable as usage" {
    assert !LntHasCode(LntLint("\nimport System.Collections.Generic\n\nfunc GetItems(): IAsyncEnumerable<string> {\n    return nil\n}"), "NL010")
}

test "NL010 still errors when System.Linq is imported and no LINQ is called" {
    assert LntHasCode(LntLint("\nimport System.Linq\n\nfunc Main() {\n    x := 5\n    y := x + 1\n}"), "NL010")
}

test "NL010 counts usage inside a TEST BLOCK" {
    assert !LntHasCode(LntLint("\nimport System.Collections.Generic\n\ntest \"uses list from import\" {\n    items := new List<int>()\n    assert items.Count == 0\n}"), "NL010")
}

test "NL010 still errors when a test block does NOT use the import" {
    assert LntHasCode(LntLint("\nimport System.Collections.Generic\n\ntest \"does not use the import\" {\n    x := 5\n    assert x == 5\n}"), "NL010")
}

test "NL010 counts a FILE IMPORT whose TOP-LEVEL type is used" {
    directory := LntTempDirectory("fileimport-used")
    File.WriteAllText(Path.Combine(directory, "Models.nl"), "\nclass User {\n    Name: string\n}\n")
    mainPath := Path.Combine(directory, "Program.nl")
    File.WriteAllText(mainPath, "\nimport \"Models\"\n\nfunc Main() {\n    user := new User { Name: \"Ada\" }\n    _ := user\n}\n")

    assert !LntHasCode(LntLintFile(mainPath), "NL010")

    Directory.Delete(directory, true)
}

test "NL010 flags a FILE IMPORT when only a NESTED type of it is named" {
    directory := LntTempDirectory("fileimport-nested")
    File.WriteAllText(Path.Combine(directory, "Models.nl"), "\nclass Outer {\n    class Nested {\n    }\n}\n")
    mainPath := Path.Combine(directory, "Program.nl")
    File.WriteAllText(mainPath, "\nimport \"Models\"\n\nfunc Main() {\n    value := new Nested { }\n    _ := value\n}\n")

    assert LntHasCode(LntLintFile(mainPath), "NL010")

    Directory.Delete(directory, true)
}

// ── NL016: redundant null check on an always-non-null expression ──────────────────────────────

test "NL016 errors on a `new` expression compared to null" {
    diagnostics := LntLint("\nimport System.Collections.Generic\n\nfunc Main() {\n    if new List<int>() != null {\n        x := 5\n    }\n}")
    assert LntHasCode(diagnostics, "NL016")
    assert LntFirstOf(diagnostics, "NL016").Severity == DiagnosticSeverity.Error
}

test "NL016 errors on an ARRAY LITERAL compared to null" {
    assert LntHasCode(LntLint("\nfunc Main() {\n    if [1, 2, 3] != null {\n        x := 5\n    }\n}"), "NL016")
}

test "NL016 leaves a VARIABLE null check alone" {
    assert !LntHasCode(LntLint("\nfunc Main() {\n    s := GetString()\n    if s != null {\n        y := s\n    }\n}\n\nfunc GetString(): string {\n    return \"hello\"\n}"), "NL016")
}

// ── the whole linter at once ──────────────────────────────────────────────────────────────────

test "one lint run reports several DIFFERENT rules over the same file" {
    diagnostics := LntLint("\nfunc main() {\n    x := 5\n    list := new List<int>()\n    if 10 != null {\n        y := x + 1\n    }\n}")
    assert LntHasCode(diagnostics, "NL001")
    assert LntHasCode(diagnostics, "NL002")
    assert LntHasCode(diagnostics, "NL003")
}

test "an EMPTY file has nothing to say" {
    assert LntLint("").Count == 0
}

test "simple valid code has nothing to say" {
    assert LntLint("\nimport System\n\nfunc main() {\n    message := \"Hello, World!\"\n    Console.WriteLine(message)\n}").Count == 0
}

test "class members are linted" {
    diagnostics := LntLint("\nclass MyClass {\n    func process() {\n        x := 5\n        y := 10\n        return x + 15\n    }\n}")
    assert LntHas(diagnostics, "NL001", "'y'")
    assert !LntHas(diagnostics, "NL001", "'x'")
}

test "a foreach collection is a use, not an unused variable" {
    assert !LntHas(LntLint("\nfunc test() {\n    items := [1, 2, 3]\n    foreach x in items {\n        print(x)\n    }\n}"), "NL001", "'items'")
}

test "a foreach over a LINQ result is a use too" {
    assert !LntHas(LntLint("\nimport System\nimport System.Linq\n\nclass Program {\n    static func Main() {\n        let numbers: int[] = [1, 2, 3, 4, 5]\n        doubled := numbers.Select(x => x * 2).ToList()\n\n        foreach num in doubled {\n            Console.WriteLine(num)\n        }\n    }\n}"), "NL001", "'doubled'")
}

// ── the severity of every rule, crossed ───────────────────────────────────────────────────────

test "EVERY ONE OF THE TEN RULES REPORTS AT ERROR SEVERITY BY DEFAULT" {
    // The deleted file asserted this for seven of the ten, one rule at a time. All ten are
    // build-blocking by catalog default, so a rule that quietly reported at Warning would let a
    // broken build through — and for NL002, NL003 and NL004 nothing asserted it at all.
    assert LntFirstOf(LntLint("func main() { x := 5 }"), "NL001").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nfunc main() {\n    sb := new StringBuilder()\n}"), "NL002").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nfunc main() {\n    if 5 != null {\n        print(\"hello\")\n    }\n}"), "NL003").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nasync func process(): Task {\n    x := 5\n    return Task.CompletedTask\n}"), "NL004").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nfunc main() {\n    return\n    x := 5\n}"), "NL006").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nimport System.Linq\n\nfunc Main() {\n    x := 5\n    y := x + 1\n}"), "NL010").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nfunc main() {\n    try {\n        x := 5\n    } catch {\n    }\n}"), "NL011").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nfunc add(a: int, b: int): int {\n    return a\n}"), "NL012").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nfunc Main() {\n    if [1, 2, 3] != null {\n        x := 5\n    }\n}"), "NL016").Severity == DiagnosticSeverity.Error
    assert LntFirstOf(LntLint("\nfunc main() {\n    x := 5\n    if true {\n        x := 10\n        y := x + 1\n    }\n}"), "NL020").Severity == DiagnosticSeverity.Error
}

// ── NL001 AND NL012 POSITIONS, AND THE SUBTREES THE USAGE WALK MUST REACH ─────────────────────
//
// These replace `tests/LinterUnusedVariableTests.cs`, the last canonical C# assertion layer over the
// linter's unused-binding rules. The subject is the public `Linter.Lint` entry end to end: source
// in, positioned diagnostics out, through `LinterWalk.nl`, `LinterWalkState.nl`,
// `LinterInterpolationScan.nl` and `LinterBindingUsageCore.nl`.
//
// THE ONE STRUCTURAL WEAKNESS OF THE DELETED FILE, AND WHAT REPLACES IT. Nineteen of its
// twenty-three cases asserted only `Assert.DoesNotContain(diagnostics, d => …)`. That is the weakest
// assertion form there is: **a linter that reported nothing at all would have passed every one of
// them.** It is not a hypothetical — the census below shows that EIGHTEEN of those nineteen sources
// lint to an entirely EMPTY diagnostic list, so most of the suite was satisfied by silence. The one
// exception is the raw-string case, and its single diagnostic is one the assertion never mentioned.
//
// EVERY NEGATIVE CLAIM HERE THEREFORE CARRIES A CONTROL, and the controls come in two kinds:
//
//   * A REMOVAL CONTROL takes the same source and deletes only the read. If the variable is then
//     reported — at a stated line, column and length — the original silence was a credited read and
//     not an absent rule.
//   * A SIBLING CONTROL adds a genuinely unused variable ALONGSIDE the credited one. If the sibling
//     is reported while the credited one is not, the walk reached the subtree and made a
//     DISTINCTION, rather than bailing out of the enclosing function.
//
// The whole diagnostic list is stated in both directions, so an extra diagnostic is a failure too.
//
// AND ONE CLAIM THE DELETED FILE GOT ACCIDENTALLY RIGHT FOR THE WRONG REASON. Its raw-string case
// asserted that `value` is not reported. It is not — but `message`, the variable HOLDING the raw
// string, IS reported, and `DoesNotContain("'value'")` is equally happy either way. Stated below as
// the two-diagnostic answer it actually is.

func LnuCensus(diagnostics: List<Diagnostic>): string {
    census := ""
    for diagnostic in diagnostics {
        census = census + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + "+" + diagnostic.Length.ToString() + ";"
    }

    return census
}

func LnuCensusOf(sourceText: string): string {
    return LnuCensus(LntLint(sourceText))
}

// The text the reported span actually covers, taken out of the source the linter was given. A
// line/column/length triple that does not land on the identifier is a squiggle in the wrong place.
func LnuSpanText(sourceText: string, diagnostic: Diagnostic): string {
    lines := sourceText.Split('\n')
    line := lines[diagnostic.Location.Line - 1]
    start := diagnostic.Location.Column - 1
    if start < 0 || start + diagnostic.Length > line.Length {
        return "<out of range>"
    }

    return line.Substring(start, diagnostic.Length)
}

// The tree the parser produces when it recovers from a broken array length: everything is real
// except the length expression, which is the `<error>` placeholder. No source text produces this on
// its own, because a real parse reports the syntax error alongside it.
func LnuPlaceholderUnit(lengthName: string): CompilationUnit {
    statements := new List<Statement>()
    statements.Add(new VariableDeclarationStatement(
        "arr",
        null,
        new NewExpression(
            new ArrayTypeReference(new SimpleTypeReference("int", 0, 0)),
            new List<Argument>(),
            null,
            2,
            15,
            new IdentifierExpression(lengthName, 2, 23)),
        VariableKind.Let,
        2,
        9))

    declarations := new List<Declaration>()
    declarations.Add(new FunctionDeclaration(
        "main",
        new List<Parameter>(),
        null,
        new BlockStatement(statements, 1, 13),
        null,
        null,
        null,
        Modifiers.None,
        new List<AttributeNode>(),
        false,
        null,
        false,
        false,
        1,
        1))

    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

// ── the reported position ─────────────────────────────────────────────────────────────────────

// Successor to UnusedVariable_DiagnosticPointsToVariableName_NotKeyword,
// UnusedVariable_InferredDeclaration_DiagnosticPointsToVariableName and
// UnusedVariable_ShorthandDeclaration_DiagnosticPointsToVariableName.
test "NL001's squiggle covers the variable NAME, whichever form declared it" {
    letSource := "func main() { let unused = 42 }"
    letDiagnostic := LntSingleOf(LntLint(letSource), "NL001")
    assert letDiagnostic.Location.Line == 1
    assert letDiagnostic.Location.Column == 19
    assert letDiagnostic.Length == "unused".Length

    inferredSource := "func main() { unused := 42 }"
    inferredDiagnostic := LntSingleOf(LntLint(inferredSource), "NL001")
    assert inferredDiagnostic.Location.Line == 1
    assert inferredDiagnostic.Location.Column == 15
    assert inferredDiagnostic.Length == "unused".Length

    shorthandSource := "func main() {\n    asdf := \"meow\"\n}"
    shorthandDiagnostic := LntSingleOf(LntLint(shorthandSource), "NL001")
    assert shorthandDiagnostic.Location.Line == 2
    assert shorthandDiagnostic.Location.Column == 5
    assert shorthandDiagnostic.Length == "asdf".Length

    // NOT IN THE DELETED FILE: the triple is checked AGAINST THE SOURCE. Three numbers can be
    // individually right and still name a span that lands on a keyword — the deleted file asserted
    // that `19` is the column and separately that `6` is the length, and never that the two of them
    // together cover the word `unused`. A one-column drift would have been invisible.
    assert LnuSpanText(letSource, letDiagnostic) == "unused"
    assert LnuSpanText(inferredSource, inferredDiagnostic) == "unused"
    assert LnuSpanText(shorthandSource, shorthandDiagnostic) == "asdf"

    // And each source produces exactly one diagnostic and nothing else.
    assert LnuCensusOf(letSource) == "NL001@1:19+6;"
    assert LnuCensusOf(inferredSource) == "NL001@1:15+6;"
    assert LnuCensusOf(shorthandSource) == "NL001@2:5+4;"
}

// Successor to TrulyUnusedVariable_ShouldBeDetected.
test "a genuinely unused variable is still reported, beside code that does read" {
    source := "func main() { let unused = 42; print(\"hello\") }"
    diagnostic := LntSingleOf(LntLint(source), "NL001")

    assert diagnostic.Message.Contains("'unused'")
    assert LnuSpanText(source, diagnostic) == "unused"
    assert LnuCensusOf(source) == "NL001@1:19+6;"
}

// ── string interpolation ──────────────────────────────────────────────────────────────────────

// Successor to VariableUsedInStringInterpolation_ShouldNotBeMarkedUnused.
test "a variable read inside an interpolated string is read" {
    assert LnuCensusOf("func main(): void\n    let name = \"Alice\"\n    print($\"Hello {name}\")") == ""

    // REMOVAL CONTROL: drop the hole and `name` is reported at its own position. Without this the
    // claim above is satisfied by a linter with no NL001 rule at all.
    assert LnuCensusOf("func main(): void\n    let name = \"Alice\"\n    print(\"Hello\")") == "NL001@2:9+4;"

    // SIBLING CONTROL: an unused neighbour is still reported while `name` is not, so the scan made a
    // distinction rather than crediting everything in the function.
    assert LnuCensusOf("func main(): void\n    let name = \"Alice\"\n    let spare = 1\n    print($\"Hello {name}\")") == "NL001@3:9+5;"
}

// Successor to VariableUsedInInterpolatedRawString_ShouldNotBeMarkedUnused.
test "a variable read inside an interpolated RAW string is read, and its holder is not" {
    // THE DELETED FILE ASKED THE WRONG QUESTION AND GOT THE RIGHT ANSWER. It asserted only that
    // `value` is absent. It is — but `message`, which holds the raw string and is never read, IS
    // reported, and `DoesNotContain("'value'")` cannot tell the two apart. The whole answer:
    assert LnuCensusOf("func main(): void\n    let value = 42\n    let message = $\"\"\"\n        The value is {value}\n    \"\"\"") == "NL001@3:9+7;"

    // REMOVAL CONTROL: with the hole replaced by a literal, BOTH are reported — so the single
    // diagnostic above is exactly one credited read, not a raw string the scanner skipped whole.
    assert LnuCensusOf("func main(): void\n    let value = 42\n    let message = $\"\"\"\n        The value is 42\n    \"\"\"") == "NL001@2:9+5;NL001@3:9+7;"
}

// Successor to MultipleVariablesInStringInterpolation_ShouldNotBeMarkedUnused.
test "every hole of a multi-hole interpolation credits its own variable" {
    assert LnuCensusOf("func main(): void\n    let first = \"John\"\n    let last = \"Doe\"\n    let age = 30\n    print($\"{first} {last} is {age} years old\")") == ""

    // REMOVAL CONTROL, AND IT IS PER-HOLE. Dropping only the `{age}` hole reports only `age`, so the
    // scan credits each hole separately rather than crediting every name in the file once it finds
    // any interpolation at all.
    assert LnuCensusOf("func main(): void\n    let first = \"John\"\n    let last = \"Doe\"\n    let age = 30\n    print($\"{first} {last} is old\")") == "NL001@4:9+3;"
}

// ── loops ─────────────────────────────────────────────────────────────────────────────────────

// Successor to LoopVariable_Foreach_ShouldNotBeMarkedUnused.
test "a foreach loop variable is exempt from NL001 by construction, not by being read" {
    assert LnuCensusOf("func main(): void\n    let numbers = [1, 2, 3]\n    foreach (num in numbers)\n        print(num)") == ""

    // THE CONTROL CORRECTS THE DELETED FILE'S READING OF ITS OWN TEST. It claimed `num` is silent
    // because the body reads it. Remove the read and `num` is STILL silent — a loop variable is
    // exempt the way a parameter is exempt, and the exemption is what the assertion was really
    // measuring. `numbers`, by contrast, is credited by the loop header: it is reported the moment
    // the loop stops reading it.
    assert LnuCensusOf("func main(): void\n    let numbers = [1, 2, 3]\n    foreach (num in numbers)\n        print(1)") == ""
}

// Successor to VariableUsedInForeachBody_ShouldNotBeMarkedUnused.
test "a variable read only inside a foreach BODY is read" {
    assert LnuCensusOf("func main(): void\n    let multiplier = 2\n    let numbers = [1, 2, 3]\n    foreach (num in numbers)\n        print(num * multiplier)") == ""

    // REMOVAL CONTROL: the body stops reading `multiplier` and it is reported, so the walk descends
    // into the loop body rather than treating the whole loop as opaque.
    assert LnuCensusOf("func main(): void\n    let multiplier = 2\n    let numbers = [1, 2, 3]\n    foreach (num in numbers)\n        print(num)") == "NL001@2:9+10;"
}

// Successor to ForLoop_LoopVariableShouldNotBeMarkedUnused.
test "a for-loop variable is exempt too" {
    assert LnuCensusOf("func main(): void\n    for (let i = 0; i < 10; i++)\n        print(i)") == ""

    // SIBLING CONTROL: a plain local beside the loop is still reported, so the loop does not silence
    // the enclosing scope.
    assert LnuCensusOf("func main(): void\n    for (let i = 0; i < 10; i++)\n        print(i)\n    let spare = 1") == "NL001@4:9+5;"
}

// ── call chains ───────────────────────────────────────────────────────────────────────────────

// Successor to VariableUsedInLINQChain_ShouldNotBeMarkedUnused.
test "a variable read through a LINQ chain is read" {
    assert LnuCensusOf("func main(): void\n    let numbers = [1, 2, 3, 4, 5]\n    let doubled = numbers.Select(x => x * 2).ToList()\n    Console.WriteLine(doubled)") == ""

    // REMOVAL CONTROL: only the final read of `doubled` is dropped. `numbers` stays silent because
    // the chain still reads it, so one source separates the two claims the deleted file made
    // together.
    assert LnuCensusOf("func main(): void\n    let numbers = [1, 2, 3, 4, 5]\n    let doubled = numbers.Select(x => x * 2).ToList()\n    Console.WriteLine(1)") == "NL001@3:9+7;"
}

// Successor to VariableUsedInMethodChain_ShouldNotBeMarkedUnused.
test "a variable read through a method chain is read" {
    assert LnuCensusOf("func main(): void\n    let text = \"hello\"\n    let result = text.ToUpper().Trim()\n    print(result)") == ""

    assert LnuCensusOf("func main(): void\n    let text = \"hello\"\n    let result = text.ToUpper().Trim()\n    print(1)") == "NL001@3:9+6;"
}

// ── test declarations ─────────────────────────────────────────────────────────────────────────

// Successor to VariableUsedInAssertCondition_ShouldNotBeMarkedUnused.
test "a variable read by an assert CONDITION is read" {
    assert LnuCensusOf("test \"assert reads locals\" {\n    first := CreateIssue(\"First\")\n    second := CreateIssue(\"Second\")\n\n    assert first.Id == 1\n    assert second.Id == 2\n}") == ""

    // REMOVAL CONTROL: drop the second assert and only `second` is reported — the conditions are
    // walked one at a time, not as a block that credits everything once any assert is present.
    assert LnuCensusOf("test \"assert reads locals\" {\n    first := CreateIssue(\"First\")\n    second := CreateIssue(\"Second\")\n\n    assert first.Id == 1\n}") == "NL001@3:5+6;"
}

// Successor to VariableUsedInAssertMessage_ShouldNotBeMarkedUnused.
test "a variable read by an assert MESSAGE is read" {
    assert LnuCensusOf("test \"assert reads message\" {\n    expectedMessage := \"should be true\"\n\n    assert true, expectedMessage\n}") == ""

    // REMOVAL CONTROL: the message operand is a SECOND slot on the assert, and dropping it alone
    // reports the variable. Without this the claim is satisfied by a walk that never looks at either
    // operand.
    assert LnuCensusOf("test \"assert reads message\" {\n    expectedMessage := \"should be true\"\n\n    assert true\n}") == "NL001@2:5+15;"
}

// Successor to VariableUsedInAssertThrowsBody_ShouldNotBeMarkedUnused.
test "a variable read inside an assert throws BODY is read" {
    assert LnuCensusOf("test \"assert throws reads locals\" {\n    value := \"bad\"\n\n    assert throws InvalidOperationException {\n        ThrowIfInvalid(value)\n    }\n}") == ""

    assert LnuCensusOf("test \"assert throws reads locals\" {\n    value := \"bad\"\n\n    assert throws InvalidOperationException {\n        ThrowIfInvalid(\"bad\")\n    }\n}") == "NL001@2:5+5;"
}

// ── the subtrees the expression walk used to drop ─────────────────────────────────────────────
//
// Each of these was a FALSE NL001 or NL012 before the walk routed its default arm through
// `AstChildrenCore`, because the enclosing expression had no case of its own and its children were
// never visited. A regression here is a diagnostic against correct code, which is the worst thing a
// linter can do — so each one carries BOTH controls.

// Successor to VariableUsedOnlyAsArrayLength_ShouldNotBeMarkedUnused.
test "a variable read only as an ARRAY LENGTH is read" {
    assert LnuCensusOf("\nfunc main() {\n    n := 4\n    arr := new int[n]\n    print arr.Length\n}") == ""

    // REMOVAL CONTROL: a literal length, and `n` is reported.
    assert LnuCensusOf("\nfunc main() {\n    n := 4\n    arr := new int[4]\n    print arr.Length\n}") == "NL001@3:5+1;"

    // SIBLING CONTROL: the walk reaches the length slot AND still reports an unused neighbour.
    assert LnuCensusOf("\nfunc main() {\n    n := 4\n    spare := 7\n    arr := new int[n]\n    print arr.Length\n}") == "NL001@4:5+5;"
}

// Successor to VariableUsedOnlyAsStackallocLength_ShouldNotBeMarkedUnused.
test "a variable read only as a STACKALLOC LENGTH is read" {
    assert LnuCensusOf("\nfunc main() {\n    len := 16\n    scratch := stackalloc byte[len]\n    print scratch.Length\n}") == ""
    assert LnuCensusOf("\nfunc main() {\n    len := 16\n    scratch := stackalloc byte[16]\n    print scratch.Length\n}") == "NL001@3:5+3;"
    assert LnuCensusOf("\nfunc main() {\n    len := 16\n    spare := 7\n    scratch := stackalloc byte[len]\n    print scratch.Length\n}") == "NL001@4:5+5;"
}

// Successor to VariableUsedOnlyUnderAllocMarker_ShouldNotBeMarkedUnused.
test "a variable read only under an ALLOC marker is read" {
    assert LnuCensusOf("\nfunc main() {\n    n := 4\n    arr := alloc new byte[n]\n    print arr.Length\n}") == ""
    assert LnuCensusOf("\nfunc main() {\n    n := 4\n    arr := alloc new byte[4]\n    print arr.Length\n}") == "NL001@3:5+1;"
    assert LnuCensusOf("\nfunc main() {\n    n := 4\n    spare := 7\n    arr := alloc new byte[n]\n    print arr.Length\n}") == "NL001@4:5+5;"
}

// Successor to VariableUsedOnlyAsIndexerInitializerKey_ShouldNotBeMarkedUnused.
test "a variable read only as an INDEXER-INITIALIZER KEY is read" {
    assert LnuCensusOf("\nimport System.Collections.Generic\n\nfunc main() {\n    key := \"one\"\n    dict := new Dictionary<string, int> {\n        [key] = 1\n    }\n    print dict.Count\n}") == ""
    assert LnuCensusOf("\nimport System.Collections.Generic\n\nfunc main() {\n    key := \"one\"\n    dict := new Dictionary<string, int> {\n        [\"one\"] = 1\n    }\n    print dict.Count\n}") == "NL001@5:5+3;"
    assert LnuCensusOf("\nimport System.Collections.Generic\n\nfunc main() {\n    key := \"one\"\n    spare := 7\n    dict := new Dictionary<string, int> {\n        [key] = 1\n    }\n    print dict.Count\n}") == "NL001@6:5+5;"
}

// Successor to VariableUsedOnlyInOnSubscriptionHandler_ShouldNotBeMarkedUnused.
test "a variable read only inside an ON-SUBSCRIPTION handler is read" {
    assert LnuCensusOf("\nclass Button {\n    event Clicked: System.EventHandler\n}\n\nfunc main() {\n    message := \"clicked\"\n    button := new Button()\n    on button.Clicked (sender, args) => {\n        print message\n    }\n}") == ""
    assert LnuCensusOf("\nclass Button {\n    event Clicked: System.EventHandler\n}\n\nfunc main() {\n    message := \"clicked\"\n    button := new Button()\n    on button.Clicked (sender, args) => {\n        print \"clicked\"\n    }\n}") == "NL001@7:5+7;"
    assert LnuCensusOf("\nclass Button {\n    event Clicked: System.EventHandler\n}\n\nfunc main() {\n    message := \"clicked\"\n    spare := 7\n    button := new Button()\n    on button.Clicked (sender, args) => {\n        print message\n    }\n}") == "NL001@8:5+5;"
}

// Successor to ParameterUsedOnlyInStackallocLength_ShouldNotBeMarkedUnread and
// ParameterUsedOnlyAsArrayLength_ShouldNotBeMarkedUnread.
test "a PARAMETER read only as a stackalloc or array length is read" {
    assert LnuCensusOf("\nfunc Scratch(size: int): int {\n    scratch := stackalloc byte[size]\n    return scratch.Length\n}") == ""
    assert LnuCensusOf("\nfunc Make(count: int): int {\n    arr := new int[count]\n    return arr.Length\n}") == ""

    // REMOVAL CONTROLS — and these report NL012, not NL001, which is the whole reason a parameter
    // needs its own pair of claims. The deleted file asserted the ABSENCE of NL012 and never once
    // showed the rule firing on these shapes.
    assert LnuCensusOf("\nfunc Scratch(size: int): int {\n    scratch := stackalloc byte[16]\n    return scratch.Length\n}") == "NL012@2:14+1;"
    assert LnuCensusOf("\nfunc Make(count: int): int {\n    arr := new int[4]\n    return arr.Length\n}") == "NL012@2:11+1;"

    // SIBLING CONTROLS: a second, genuinely unread parameter is reported while the credited one is
    // not, so the length slot credits one parameter rather than the whole signature.
    assert LnuCensusOf("\nfunc Scratch(size: int, spare: int): int {\n    scratch := stackalloc byte[size]\n    return scratch.Length\n}") == "NL012@2:25+1;"
    assert LnuCensusOf("\nfunc Make(count: int, spare: int): int {\n    arr := new int[count]\n    return arr.Length\n}") == "NL012@2:23+1;"
}

// ── the parser-error placeholder ──────────────────────────────────────────────────────────────

// Successor to ParserErrorPlaceholder_InArrayLength_SuppressesUnusedVariableFollowOn.
test "a parser-error placeholder in an array length suppresses the unused-variable follow-on" {
    // A file that failed to parse must not also be told its variables are unused: the reads the
    // parser could not recover are exactly the reads the linter cannot see. This unit is built by
    // hand because no source text produces it — a real parse would report the syntax error too.
    assert LnuCensus(new Linter().Lint(LnuPlaceholderUnit("<error>"), "test.nl", null)) == ""

    // AND THE CONTROL IS THE POINT. The identical tree with a REAL name in the length slot reports
    // `arr` at its own position, so the suppression is driven by the placeholder and by nothing else
    // about the shape. The deleted file asserted only the absence, which a linter that ignored
    // hand-built trees entirely would also satisfy.
    assert LnuCensus(new Linter().Lint(LnuPlaceholderUnit("n"), "test.nl", null)) == "NL001@2:9+3;"
}
