namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE CALL GRAPH (task 019 slice 14).
//
// The whole territory — the four-level walk and the selection over it — was five PRIVATE or
// snapshot-bound C# members, and its accumulator was a tuple-valued dictionary that never had a
// name. Asking it anything meant loading a project. Here the walk is asked directly, and the
// answers below include SEVEN that were previously unreachable, prose, or asserted only by
// accident:
//   (a) THE MAP'S ITERATION ORDER IS THE ANSWER'S ORDER. The unfiltered arm returns the first
//       `limit` edges in FIRST-DECLARATION order. The C# inherited that from `Dictionary`'s
//       internals; here it is carried explicitly and asserted.
//   (b) TWO FUNCTIONS WITH THE SAME QUALIFIED NAME SHARE ONE BUCKET, appended in file order — so a
//       `Widget.Draw` in two files reports as one caller with both files' edges.
//   (c) THE UNFILTERED ARM RETURNS NO CALLERS, EVER — the list is built and never filled.
//   (d) A LIMIT OF ZERO TRUNCATES BEFORE THE FIRST EDGE, not after it.
//   (e) TRUNCATION IS TESTED ON THE COMBINED COUNT AND THEN HALVES BOTH LISTS, so a limit of 3
//       keeps ONE of each and not two.
//   (f) A CALL RECORDS ITSELF BEFORE ITS ARGUMENTS AND ITS OWN CALLEE, so `Outer(Inner())` reports
//       `Outer` first.
//   (g) AN ASSIGNMENT'S TARGET IS NOT WALKED AND A `for` BODY IS NOT WALKED. Those gaps are the
//       shipped behaviour and are asserted so a change to them cannot be silent.
func CicgAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func CicgId(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 1, 1)
}

func CicgCall(name: string, line: int, column: int): CallExpression {
    return new CallExpression(CicgId(name), new List<Argument>(), null, line, column)
}

func CicgCallOf(callee: Expression, argument: Expression?, line: int, column: int): CallExpression {
    arguments := new List<Argument>()
    if argument != null {
        arguments.Add(new Argument(null, argument))
    }

    return new CallExpression(callee, arguments, null, line, column)
}

func CicgBody(statements: List<Statement>): BlockStatement {
    return new BlockStatement(statements, 1, 1)
}

func CicgCallStatements(names: List<string>): List<Statement> {
    statements := new List<Statement>()
    index := 0
    while index < names.Count {
        statements.Add(new ExpressionStatement(CicgCall(names[index], index + 10, 5), index + 10, 5))
        index = index + 1
    }

    return statements
}

func CicgFunction(name: string, statements: List<Statement>): FunctionDeclaration {
    return new FunctionDeclaration(
        name, new List<Parameter>(), null, CicgBody(statements), null, null, null,
        Modifiers.Public, CicgAttributes(), false, null, false, false, 1, 1)
}

func CicgClass(name: string, members: List<Declaration>): ClassDeclaration {
    return new ClassDeclaration(
        name, null, null, new List<TypeReference>(), members, null,
        Modifiers.Public, CicgAttributes(), 1, 1)
}

func CicgUnit(declarations: List<Declaration>): CompilationUnit {
    return new CompilationUnit(
        null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

func CicgOne(declarations: List<Declaration>): List<CompilationUnit> {
    units := new List<CompilationUnit>()
    units.Add(CicgUnit(declarations))
    return units
}

func CicgFiles(first: string): List<string> {
    files := new List<string>()
    files.Add(first)
    return files
}

func CicgEdgeText(edges: List<CallSiteResult>): string {
    joined := ""
    index := 0
    while index < edges.Count {
        if index > 0 {
            joined = joined + ","
        }

        joined = joined + edges[index].Name
        index = index + 1
    }

    return joined
}

func CicgNames(names: string[]): List<string> {
    result := new List<string>()
    index := 0
    while index < names.Length {
        result.Add(names[index])
        index = index + 1
    }

    return result
}

func CicgTwoFileGraph(functionName: string?, limit: int): CallGraphResult {
    firstMembers := new List<Declaration>()
    firstMembers.Add(CicgFunction("Draw", CicgCallStatements(CicgNames(["First"]))))

    secondMembers := new List<Declaration>()
    secondMembers.Add(CicgFunction("Draw", CicgCallStatements(CicgNames(["Second"]))))

    firstDeclarations := new List<Declaration>()
    firstDeclarations.Add(CicgClass("Widget", firstMembers))
    secondDeclarations := new List<Declaration>()
    secondDeclarations.Add(CicgClass("Widget", secondMembers))

    units := new List<CompilationUnit>()
    units.Add(CicgUnit(firstDeclarations))
    units.Add(CicgUnit(secondDeclarations))

    files := new List<string>()
    files.Add("one.nl")
    files.Add("two.nl")

    return CodeIntelligenceCallGraph.Build(units, files, functionName, limit)
}

test "a free function's calls are its callees, at the CALL's own position" {
    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Main", CicgCallStatements(CicgNames(["Hi", "Bye"]))))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Main", 100)

    assert result.Function == "Main"
    assert CicgEdgeText(result.Callees) == "Hi,Bye"
    assert result.Callees[0].File == "Program.nl"
    assert result.Callees[0].Line == 10
    assert result.Callees[0].Column == 5
    assert result.Callees[1].Line == 11
    assert result.Truncated == false
}

test "a method's caller key is Owner.Name, and a nested type renames again" {
    innerMembers := new List<Declaration>()
    innerMembers.Add(CicgFunction("Tick", CicgCallStatements(CicgNames(["Beep"]))))

    outerMembers := new List<Declaration>()
    outerMembers.Add(CicgClass("Inner", innerMembers))

    declarations := new List<Declaration>()
    declarations.Add(CicgClass("Outer", outerMembers))

    assert CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Inner.Tick", 100).Callees.Count == 1
    // The OUTER name never reaches the key: the nested type replaces it.
    assert CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Outer.Tick", 100).Callees.Count == 0
}

test "a caller is reported under the CALLING function's name at the call site" {
    members := new List<Declaration>()
    members.Add(CicgFunction("Draw", CicgCallStatements(CicgNames(["Paint"]))))

    declarations := new List<Declaration>()
    declarations.Add(CicgClass("Widget", members))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Shapes.nl"), "Paint", 100)

    assert result.Callees.Count == 0
    assert result.Callers.Count == 1
    assert result.Callers[0].Name == "Widget.Draw"
    assert result.Callers[0].File == "Shapes.nl"
    assert result.Callers[0].Line == 10
}

test "(a) THE UNFILTERED ARM RETURNS EDGES IN FIRST-DECLARATION ORDER" {
    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Alpha", CicgCallStatements(CicgNames(["A1", "A2"]))))
    declarations.Add(CicgFunction("Beta", CicgCallStatements(CicgNames(["B1"]))))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), null, 100)

    assert result.Function == null
    assert CicgEdgeText(result.Callees) == "A1,A2,B1"
}

test "(c) THE UNFILTERED ARM RETURNS NO CALLERS, EVER" {
    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Alpha", CicgCallStatements(CicgNames(["Beta"]))))
    declarations.Add(CicgFunction("Beta", CicgCallStatements(CicgNames(["Alpha"]))))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), null, 100)
    assert result.Callers.Count == 0
    assert result.Callees.Count == 2
}

test "(d) A LIMIT OF ZERO TRUNCATES BEFORE THE FIRST EDGE" {
    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Alpha", CicgCallStatements(CicgNames(["A1", "A2"]))))

    zero := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), null, 0)
    assert zero.Callees.Count == 0
    assert zero.Truncated

    one := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), null, 1)
    assert one.Callees.Count == 1
    assert one.Truncated

    exact := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), null, 2)
    assert exact.Callees.Count == 2
    // Reaching the limit exactly is NOT truncation.
    assert exact.Truncated == false
}

test "(e) TRUNCATION IS TESTED ON THE COMBINED COUNT AND HALVES BOTH LISTS" {
    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Target", CicgCallStatements(CicgNames(["T1", "T2"]))))
    declarations.Add(CicgFunction("CallerOne", CicgCallStatements(CicgNames(["Target"]))))
    declarations.Add(CicgFunction("CallerTwo", CicgCallStatements(CicgNames(["Target"]))))

    full := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Target", 100)
    assert full.Callees.Count == 2
    assert full.Callers.Count == 2
    assert full.Truncated == false

    // Four rows against a limit of three: truncated, and each list keeps limit/2 = 1.
    cut := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Target", 3)
    assert cut.Truncated
    assert cut.Callees.Count == 1
    assert cut.Callers.Count == 1
}

test "an unknown function answers empty and untruncated" {
    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Alpha", CicgCallStatements(CicgNames(["Beta"]))))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Nope", 100)
    assert result.Function == "Nope"
    assert result.Callees.Count == 0
    assert result.Callers.Count == 0
    assert result.Truncated == false
}

test "(b) TWO FILES DECLARING THE SAME QUALIFIED NAME SHARE ONE BUCKET, IN FILE ORDER" {
    named := CicgTwoFileGraph("Widget.Draw", 100)
    assert CicgEdgeText(named.Callees) == "First,Second"
    assert named.Callees[0].File == "one.nl"
    assert named.Callees[1].File == "two.nl"

    // And the unfiltered arm sees ONE caller key carrying both files' edges.
    all := CicgTwoFileGraph(null, 100)
    assert CicgEdgeText(all.Callees) == "First,Second"
}

test "(f) A CALL RECORDS ITSELF BEFORE ITS ARGUMENTS AND BEFORE ITS OWN CALLEE" {
    inner := CicgCall("Inner", 20, 9)
    outer := CicgCallOf(CicgId("Outer"), inner, 20, 1)

    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(outer, 20, 1))

    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Main", statements))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Main", 100)
    assert CicgEdgeText(result.Callees) == "Outer,Inner"
}

test "a chained call reports the OUTER member call and then the receiver's call" {
    receiver := CicgCall("Build", 30, 1)
    chained := CicgCallOf(new MemberAccessExpression(receiver, "Render", false, 30, 10), null, 30, 10)

    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(chained, 30, 1))

    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Main", statements))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Main", 100)
    assert CicgEdgeText(result.Callees) == "Render,Build"
}

test "the walk descends through blocks, ifs, whiles, foreaches, returns and initializers" {
    statements := new List<Statement>()
    statements.Add(new ReturnStatement(CicgCall("FromReturn", 40, 1), 40, 1))
    statements.Add(new VariableDeclarationStatement(
        "x", null, CicgCall("FromInit", 41, 1), VariableKind.Let, 41, 1))
    statements.Add(new IfStatement(
        CicgCall("FromCondition", 42, 1),
        new ExpressionStatement(CicgCall("FromThen", 43, 1), 43, 1),
        new ExpressionStatement(CicgCall("FromElse", 44, 1), 44, 1), 42, 1))
    statements.Add(new WhileStatement(
        CicgCall("FromWhileCondition", 45, 1),
        new ExpressionStatement(CicgCall("FromWhileBody", 46, 1), 46, 1), 45, 1))
    statements.Add(new ForeachStatement(
        "item", CicgCall("FromCollection", 47, 1),
        new ExpressionStatement(CicgCall("FromForeachBody", 48, 1), 48, 1), 47, 1))
    statements.Add(CicgBody(CicgCallStatements(CicgNames(["FromNestedBlock"]))))

    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Main", statements))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Main", 100)
    assert CicgEdgeText(result.Callees) ==
        "FromReturn,FromInit,FromCondition,FromThen,FromElse,FromWhileCondition,FromWhileBody,FromCollection,FromForeachBody,FromNestedBlock"
}

test "(g) AN ASSIGNMENT'S VALUE IS WALKED AND ITS TARGET IS NOT" {
    assignment := new AssignmentExpression(
        CicgCall("InTarget", 50, 1), AssignmentOperator.Assign, CicgCall("InValue", 50, 20), 50, 1)

    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(assignment, 50, 1))

    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Main", statements))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Main", 100)
    assert CicgEdgeText(result.Callees) == "InValue"
}

test "(g) A for LOOP'S BODY IS NOT WALKED — a shape the walk does not know" {
    statements := new List<Statement>()
    statements.Add(new ForStatement(
        null, null, null,
        new ExpressionStatement(CicgCall("InFor", 55, 1), 55, 1), 54, 1))

    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Main", statements))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Main", 100)
    assert result.Callees.Count == 0
    // The function still opens a bucket, so it is a known caller with no edges.
    assert result.Function == "Main"
    assert result.Truncated == false
}

test "both sides of a binary expression are walked, and so is an interpolation HOLE" {
    binary := new BinaryExpression(
        CicgCall("Left", 60, 1), BinaryOperator.Add, CicgCall("Right", 60, 20), 60, 1)

    parts := new List<InterpolatedStringPart>()
    parts.Add(new InterpolatedStringText("plain ", 61, 1))
    parts.Add(new InterpolatedStringHole(CicgCall("InHole", 61, 10), null, 61, 10))

    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(binary, 60, 1))
    statements.Add(new ExpressionStatement(new InterpolatedStringExpression(parts, 61, 1), 61, 1))

    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Main", statements))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Main", 100)
    assert CicgEdgeText(result.Callees) == "Left,Right,InHole"
}

test "an EXPRESSION-BODIED function contributes edges too" {
    declaration := new FunctionDeclaration(
        "Compute", new List<Parameter>(), null, null, CicgCall("Helper", 70, 20), null, null,
        Modifiers.Public, CicgAttributes(), false, null, false, false, 70, 1)

    declarations := new List<Declaration>()
    declarations.Add(declaration)

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Compute", 100)
    assert CicgEdgeText(result.Callees) == "Helper"
}

test "an empty project answers an empty unfiltered graph without truncating" {
    result := CodeIntelligenceCallGraph.Build(
        new List<CompilationUnit>(), new List<string>(), null, 100)
    assert result.Function == null
    assert result.Callers.Count == 0
    assert result.Callees.Count == 0
    assert result.Truncated == false
}

test "a struct's, a record's and an interface's members are all walked" {
    members := new List<Declaration>()
    members.Add(CicgFunction("Draw", CicgCallStatements(CicgNames(["Paint"]))))

    structDeclaration := new StructDeclaration(
        "Point", null, new List<TypeReference>(), members, null,
        Modifiers.Public, CicgAttributes(), 1, 1)
    recordDeclaration := new RecordDeclaration(
        "Person", null, new List<TypeReference>(), members, null, false,
        Modifiers.Public, CicgAttributes(), 1, 1)
    interfaceDeclaration := new InterfaceDeclaration(
        "IShape", null, new List<TypeReference>(), members,
        Modifiers.Public, false, CicgAttributes(), 1, 1)

    structDeclarations := new List<Declaration>()
    structDeclarations.Add(structDeclaration)
    recordDeclarations := new List<Declaration>()
    recordDeclarations.Add(recordDeclaration)
    interfaceDeclarations := new List<Declaration>()
    interfaceDeclarations.Add(interfaceDeclaration)

    assert CodeIntelligenceCallGraph.Build(
        CicgOne(structDeclarations), CicgFiles("P.nl"), "Point.Draw", 100).Callees.Count == 1
    assert CodeIntelligenceCallGraph.Build(
        CicgOne(recordDeclarations), CicgFiles("P.nl"), "Person.Draw", 100).Callees.Count == 1
    assert CodeIntelligenceCallGraph.Build(
        CicgOne(interfaceDeclarations), CicgFiles("P.nl"), "IShape.Draw", 100).Callees.Count == 1
}

test "a callee the display text cannot name records no edge" {
    // A call whose callee is a literal has no name, so nothing is recorded — but the argument's
    // call still is, because the walk descends regardless.
    nameless := CicgCallOf(new IntLiteralExpression("3", 80, 1), CicgCall("Inside", 80, 10), 80, 1)

    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(nameless, 80, 1))

    declarations := new List<Declaration>()
    declarations.Add(CicgFunction("Main", statements))

    result := CodeIntelligenceCallGraph.Build(
        CicgOne(declarations), CicgFiles("Program.nl"), "Main", 100)
    assert CicgEdgeText(result.Callees) == "Inside"
}
