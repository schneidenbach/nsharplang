namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// CONTRACTS FOR THE CALL-HIERARCHY VIEW. These came out of `CallHierarchyHandler.cs`, where the
// same nested member walk was written three times over — once per request — and the walk over a
// function's body was reachable only by standing up a document manager: which declaration a name
// and a line together pick out, which function encloses a line, the span arithmetic that keeps a
// node's range legal, and exactly how far the outgoing-call walk reaches.
func EchStatements(statements: Statement[]): List<Statement> {
    list := new List<Statement>()
    for statement in statements {
        list.Add(statement)
    }
    return list
}

func EchBlock(statements: Statement[], line: int): BlockStatement {
    return new BlockStatement(EchStatements(statements), line, 1)
}

func EchCall(name: string, line: int, column: int): Expression {
    callee: Expression = new IdentifierExpression(name, line, column)
    expression: Expression = new CallExpression(callee, new List<Argument>(), null, line, column)
    return expression
}

func EchCallStatement(name: string, line: int, column: int): Statement {
    statement: Statement = new ExpressionStatement(EchCall(name, line, column), line, column)
    return statement
}

func EchFunction(name: string, body: BlockStatement?, line: int, column: int): FunctionDeclaration {
    return new FunctionDeclaration(name, new List<Parameter>(), null, body, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, line, column)
}

func EchDeclaration(declaration: FunctionDeclaration): Declaration {
    result: Declaration = declaration
    return result
}

func EchClass(name: string, members: Declaration[], line: int): Declaration {
    list := new List<Declaration>()
    for member in members {
        list.Add(member)
    }
    declaration: Declaration = new ClassDeclaration(name, null, null, new List<TypeReference>(), list, null, Modifiers.None, new List<AttributeNode>(), line, 1)
    return declaration
}

func EchUnit(declarations: Declaration[]): CompilationUnit {
    list := new List<Declaration>()
    for declaration in declarations {
        list.Add(declaration)
    }
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, list, 1, 1)
}

func EchNames(rows: List<EditorCallSiteRow>): string {
    joined := ""
    index := 0
    while index < rows.Count {
        if index > 0 {
            joined = joined + ","
        }
        joined = joined + rows[index].Name
        index = index + 1
    }
    return joined
}

// A NAME AND A LINE TOGETHER PICK OUT ONE DECLARATION. A name alone is ambiguous across
// overloads; a line alone says nothing about what the reader clicked.
test "the call hierarchy finds a function by its name and its declaration line together" {
    outer := EchFunction("Helper", EchBlock([], 10), 10, 1)
    method := EchFunction("Helper", EchBlock([], 30), 30, 5)
    unit := EchUnit([EchDeclaration(outer), EchClass("Box", [EchDeclaration(method)], 20)])

    topLevel := EditorCallHierarchyFacts.FunctionAtLine(unit, "Helper", 10)
    assert topLevel != null
    assert topLevel.Column == 1

    nested := EditorCallHierarchyFacts.FunctionAtLine(unit, "Helper", 30)
    assert nested != null
    assert nested.Column == 5

    assert EditorCallHierarchyFacts.FunctionAtLine(unit, "Helper", 11) == null
    assert EditorCallHierarchyFacts.FunctionAtLine(unit, "Missing", 10) == null
    assert EditorCallHierarchyFacts.FunctionAtLine(null, "Helper", 10) == null
}

// THE WALK DESCENDS INTO MEMBERS — a method is a function for this purpose — unlike the
// implementation and outline walks, which stay at the top level.
test "the call hierarchy descends into a type's members to find a method" {
    method := EchFunction("Area", EchBlock([], 12), 12, 5)
    unit := EchUnit([EchClass("Box", [EchDeclaration(method)], 10)])

    assert EditorCallHierarchyFacts.FunctionAtLine(unit, "Area", 12) != null
    assert EditorCallHierarchyFacts.EnclosingFunction(unit, 12) != null
}

// A LINE BELONGS TO THE FUNCTION THAT REACHES IT, and the reach is the one estimate every
// consumer shares — so "which function encloses this call" and "how far does this function go"
// cannot disagree.
test "the call hierarchy finds the function a line falls inside" {
    first := EchFunction("First", EchBlock([EchCallStatement("x", 11, 5)], 10), 10, 1)
    second := EchFunction("Second", EchBlock([EchCallStatement("y", 21, 5)], 20), 20, 1)
    unit := EchUnit([EchDeclaration(first), EchDeclaration(second)])

    inFirst := EditorCallHierarchyFacts.EnclosingFunction(unit, 11)
    assert inFirst != null
    assert inFirst.Name == "First"

    inSecond := EditorCallHierarchyFacts.EnclosingFunction(unit, 21)
    assert inSecond != null
    assert inSecond.Name == "Second"

    assert EditorCallHierarchyFacts.EnclosingFunction(unit, 15) == null
    assert EditorCallHierarchyFacts.EnclosingFunction(null, 11) == null
}

// THE NODE'S RANGE MUST NOT END BEFORE IT STARTS. A function that spans lines ends at column
// ZERO of its last line; a one-line function would then end before it began, so its end is pushed
// out to the name's width instead.
test "the call hierarchy keeps a node's range from ending before it starts" {
    multiLine := EchFunction("Helper", EchBlock([EchCallStatement("x", 11, 5)], 10), 10, 1)
    spanning := EditorCallHierarchyFacts.FunctionRange(multiLine, "Helper", 0)
    assert spanning.StartLine == 9
    assert spanning.StartCharacter == 0
    assert spanning.EndLine > spanning.StartLine
    assert spanning.EndCharacter == 0
    assert spanning.SelectionEndCharacter == 6

    oneLine := EchFunction("Helper", EchBlock([], 10), 10, 5)
    tight := EditorCallHierarchyFacts.FunctionRange(oneLine, "Helper", 0)
    assert tight.StartLine == 9
    assert tight.EndLine == 9
    assert tight.StartCharacter == 4
    assert tight.EndCharacter == 10
}

// A CALLER THE WALK COULD NOT FIND STILL GETS A NODE, placed on the line of the call itself —
// which is what keeps a reference in a file the editor has not parsed in the list instead of
// dropping it.
test "the call hierarchy places an unfound caller on the line of its own call" {
    fallback := EditorCallHierarchyFacts.FunctionRange(null, "unknown", 42)

    assert fallback.StartLine == 42
    assert fallback.EndLine == 42
    assert fallback.StartCharacter == 0
    assert fallback.EndCharacter == 7
    assert fallback.SelectionEndCharacter == 7
}

// A CALL IS NAMED BY THE LAST THING IN ITS CALLEE and located where that CALLEE begins — not
// where the argument list opens. A callee the walk cannot name contributes no row.
test "the call hierarchy names a call by its callee and places it there" {
    memberCallee: Expression = new MemberAccessExpression(new IdentifierExpression("box", 5, 9), "Area", false, 5, 13)
    memberCall: Expression = new CallExpression(memberCallee, new List<Argument>(), null, 5, 13)
    plainCall := EchCall("Helper", 6, 9)
    unnameable: Expression = new CallExpression(new CallExpression(new IdentifierExpression("factory", 7, 9), new List<Argument>(), null, 7, 9), new List<Argument>(), null, 7, 20)

    statements := new List<Statement>()
    statements.Add(new ExpressionStatement(memberCall, 5, 9))
    statements.Add(new ExpressionStatement(plainCall, 6, 9))
    statements.Add(new ExpressionStatement(unnameable, 7, 9))
    body := new BlockStatement(statements, 4, 1)

    rows := EditorCallHierarchyFacts.OutgoingCallSites(EchFunction("run", body, 4, 1))
    assert EchNames(rows) == "Area,Helper,factory"
    assert rows[0].Line == 5
    assert rows[0].Column == 13
    assert rows[1].Column == 9
}

// THE STATEMENT WALK IS PARTIAL, AND THIS IS ITS EXACT REACH. A `for` header, a `try`, a `switch`,
// a `using` and a `lock` are not walked, so calls inside them do not appear in the outgoing list.
// Recorded rather than widened: widening it would change what the view shows.
test "the call hierarchy's outgoing walk reaches exactly these statements and no others" {
    reached := EchBlock(
        [
            EchCallStatement("fromExpression", 5, 5),
            new VariableDeclarationStatement("a", null, EchCall("fromBinding", 6, 10), VariableKind.Let, 6, 5),
            new ReturnStatement(EchCall("fromReturn", 7, 12), 7, 5),
            new IfStatement(EchCall("fromCondition", 8, 8), EchBlock([EchCallStatement("fromThen", 9, 9)], 8), EchBlock([EchCallStatement("fromElse", 11, 9)], 10), 8, 5),
            new WhileStatement(EchCall("fromWhileCondition", 13, 11), EchBlock([EchCallStatement("fromWhileBody", 14, 9)], 13), 13, 5),
            new ForeachStatement("item", EchCall("fromForeachCollection", 16, 20), EchBlock([EchCallStatement("fromForeachBody", 17, 9)], 16), 16, 5)
        ],
        4
    )

    assert EchNames(EditorCallHierarchyFacts.OutgoingCallSites(EchFunction("run", reached, 4, 1))) == "fromExpression,fromBinding,fromReturn,fromCondition,fromThen,fromElse,fromWhileCondition,fromWhileBody,fromForeachCollection,fromForeachBody"

    catches := new List<CatchClause>()
    catches.Add(new CatchClause(null, null, EchBlock([EchCallStatement("fromCatch", 22, 9)], 21)))
    notReached := EchBlock(
        [
            new ForStatement(null, EchCall("fromForCondition", 20, 12), EchCall("fromForIterator", 20, 30), EchBlock([EchCallStatement("fromForBody", 21, 9)], 20), 20, 5),
            new TryStatement(EchBlock([EchCallStatement("fromTry", 25, 9)], 24), catches, null, 24, 5)
        ],
        19
    )

    assert EchNames(EditorCallHierarchyFacts.OutgoingCallSites(EchFunction("run", notReached, 19, 1))) == "fromForBody"
}

// AN EXPRESSION BODY IS WALKED TOO, and a chained call reports the OUTER name first because the
// callee is walked after the arguments.
test "the call hierarchy walks an expression body and reports a chain outermost first" {
    innerCallee: Expression = new IdentifierExpression("inner", 3, 12)
    inner: Expression = new CallExpression(innerCallee, new List<Argument>(), null, 3, 12)
    outerCallee: Expression = new MemberAccessExpression(inner, "Outer", false, 3, 20)
    chained: Expression = new CallExpression(outerCallee, new List<Argument>(), null, 3, 20)

    expressionBodied := new FunctionDeclaration("run", new List<Parameter>(), null, null, chained, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 3, 1)
    assert EchNames(EditorCallHierarchyFacts.OutgoingCallSites(expressionBodied)) == "Outer,inner"
}

// A FUNCTION THAT CALLS NOTHING ANSWERS NOTHING, which is an answer and not a failure.
test "the call hierarchy answers no call sites for a function that calls nothing" {
    assert EditorCallHierarchyFacts.OutgoingCallSites(EchFunction("run", EchBlock([], 4), 4, 1)).Count == 0
    assert EditorCallHierarchyFacts.OutgoingCallSites(EchFunction("run", null, 4, 1)).Count == 0
}

// ── Grouping ────────────────────────────────────────────────────────────
//
// The two grouping walks came out of `CallHierarchyHandler.cs`, where they were private methods on
// two handlers and reachable only by standing up a document manager and a project snapshot.
func EchReference(referenceFile: string, line: int, column: int, length: int, context: string?, isDefinition: bool): ReferenceResult {
    return new ReferenceResult(referenceFile, line, column, length, context, isDefinition)
}

func EchSource(fileUri: string, reference: ReferenceResult, enclosing: FunctionDeclaration?): EditorIncomingCallSource {
    return new EditorIncomingCallSource(fileUri, reference, enclosing)
}

func EchSources(sources: EditorIncomingCallSource[]): List<EditorIncomingCallSource> {
    list := new List<EditorIncomingCallSource>()
    for source in sources {
        list.Add(source)
    }

    return list
}

func EchSites(sites: EditorCallSiteRow[]): List<EditorCallSiteRow> {
    list := new List<EditorCallSiteRow>()
    for site in sites {
        list.Add(site)
    }

    return list
}

test "incoming calls group by the caller in the file they were found in" {
    caller := EchFunction("Caller", null, 11, 1)
    other := EchFunction("Other", null, 21, 1)

    groups := EditorCallHierarchyFacts.IncomingCallGroups(EchSources([
        EchSource("file:///a.nl", EchReference("a.nl", 12, 10, 3, "Caller", false), caller),
        EchSource("file:///a.nl", EchReference("a.nl", 13, 10, 3, "Caller", false), caller),
        EchSource("file:///a.nl", EchReference("a.nl", 22, 5, 3, "Other", false), other),
        EchSource("file:///b.nl", EchReference("b.nl", 12, 10, 3, "Caller", false), caller)
    ]))

    assert groups.Count == 3
    assert groups[0].CallerName == "Caller"
    assert groups[0].FileUri == "file:///a.nl"
    assert groups[0].FromRanges.Count == 2
    assert groups[1].CallerName == "Other"
    assert groups[2].FileUri == "file:///b.nl"
    assert groups[2].FromRanges.Count == 1
}

// A DEFINITION IS NOT A CALL: the declaration row a reference search returns is not a caller.
test "incoming calls drop the definition row" {
    groups := EditorCallHierarchyFacts.IncomingCallGroups(EchSources([
        EchSource("file:///a.nl", EchReference("a.nl", 6, 6, 3, "Add", true), null)
    ]))

    assert groups.Count == 0
}

// A CALL FROM A FILE NOTHING COULD PARSE IS STILL SHOWN, named by the search's own context word
// and then by "<unknown>".
test "incoming calls name a caller the parser could not find" {
    groups := EditorCallHierarchyFacts.IncomingCallGroups(EchSources([
        EchSource("file:///a.nl", EchReference("a.nl", 4, 2, 3, "Outer", false), null),
        EchSource("file:///a.nl", EchReference("a.nl", 9, 2, 3, null, false), null)
    ]))

    assert groups.Count == 2
    assert groups[0].CallerName == "Outer"
    assert groups[1].CallerName == "<unknown>"
}

// THE NODE'S EXTENT COMES FROM THE FIRST REFERENCE THAT REACHED IT, and every call site is at
// least one column wide.
test "incoming calls take the node's extent from the first reference" {
    groups := EditorCallHierarchyFacts.IncomingCallGroups(EchSources([
        EchSource("file:///a.nl", EchReference("a.nl", 7, 3, 0, null, false), null),
        EchSource("file:///a.nl", EchReference("a.nl", 30, 1, 4, null, false), null)
    ]))

    assert groups.Count == 1
    assert groups[0].Range.StartLine == 6
    assert groups[0].FromRanges.Count == 2
    assert groups[0].FromRanges[0].Line == 6
    assert groups[0].FromRanges[0].StartCharacter == 2
    assert groups[0].FromRanges[0].EndCharacter == 3
    assert groups[0].FromRanges[1].Line == 29
    assert groups[0].FromRanges[1].EndCharacter == 4
}

test "outgoing calls group by callee in the order they are first called" {
    groups := EditorCallHierarchyFacts.OutgoingCallGroups(EchSites([
        new EditorCallSiteRow("Add", 12, 10),
        new EditorCallSiteRow("Inner", 17, 12),
        new EditorCallSiteRow("Add", 13, 10)
    ]))

    assert groups.Count == 2
    assert groups[0].CalleeName == "Add"
    assert groups[0].FromRanges.Count == 2
    assert groups[1].CalleeName == "Inner"

    assert groups[0].FromRanges[0].Line == 11
    assert groups[0].FromRanges[0].StartCharacter == 9
    assert groups[0].FromRanges[0].EndCharacter == 12
}

// THE HIGHLIGHT IS THE NAME'S OWN LENGTH, and a site reported above the first line or column is
// clamped rather than dropped.
test "outgoing calls clamp a site the walk reported at the edge" {
    groups := EditorCallHierarchyFacts.OutgoingCallGroups(EchSites([
        new EditorCallSiteRow("Add", 0, 0)
    ]))

    assert groups.Count == 1
    assert groups[0].FromRanges[0].Line == 0
    assert groups[0].FromRanges[0].StartCharacter == 0
    assert groups[0].FromRanges[0].EndCharacter == 3
}
