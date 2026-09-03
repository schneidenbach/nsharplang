namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR THE WHOLE ANSWER A CARET AFTER A DOT GETS (task 019 slice 4). These assertions came
// out of `CompletionEngine.cs` with the members: the fuzzy column search and its bounds, the
// thirteen expression shapes that can be named as a receiver and the ones that cannot, and the
// three doors a receiver is typed through — recorded type, identifier, literal — in that order.
func CrfUnit(declarations: List<Declaration>): CompilationUnit {
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

// One function whose body is a single expression statement. That is the shortest path the position
// walk takes from a compilation unit to an expression, so it is the shape every position contract
// below is written against.
func CrfUnitWithExpression(expression: Expression, line: int, column: int): CompilationUnit {
    statements := new List<Statement>()
    statement: Statement = new ExpressionStatement(expression, line, column)
    statements.Add(statement)

    body := new BlockStatement(statements, line, 1)
    declaration: Declaration = new FunctionDeclaration("Run", new List<Parameter>(), null, body, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 1, 1)

    declarations := new List<Declaration>()
    declarations.Add(declaration)
    return CrfUnit(declarations)
}

func CrfName(name: string, line: int, column: int): Expression {
    expression: Expression = new IdentifierExpression(name, line, column)
    return expression
}

func CrfAccess(target: Expression, memberName: string, line: int, column: int): MemberAccessExpression {
    return new MemberAccessExpression(target, memberName, false, line, column)
}

func CrfCall(callee: Expression, line: int, column: int): Expression {
    expression: Expression = new CallExpression(callee, new List<Argument>(), null, line, column)
    return expression
}

func CrfColumnText(columns: List<int>): string {
    text := ""
    index := 0
    while index < columns.Count {
        if index > 0 {
            text = text + ","
        }

        text = text + columns[index].ToString()
        index = index + 1
    }

    return text
}

func CrfMember(name: string): DeclaredMemberInfo {
    memberType: TypeReference = new SimpleTypeReference("int")
    parameterNames := new string[](0)
    parameterTypes := new TypeReference[](0)
    parameterModifiers := new ParameterModifier[](0)
    typeParameters := new TypeParameter[](0)
    constraints := new GenericConstraint[](0)
    return new DeclaredMemberInfo(
        name,
        "Owner",
        DeclaredMemberKind.Property,
        "member",
        memberType,
        false,
        false,
        false,
        true,
        0,
        parameterNames,
        parameterTypes,
        parameterModifiers,
        0,
        false,
        false,
        memberType,
        0,
        typeParameters,
        constraints,
        0,
        false,
        false,
        false,
        false,
        "",
        false,
        false,
        1,
        1
    )
}

func CrfNoMembers(): DeclaredMemberInfo[] {
    return new DeclaredMemberInfo[](0)
}

func CrfNoModels(): List<SemanticModel> {
    return new List<SemanticModel>()
}

// No project files, so no package is knowable and the visibility filter fails open — which is what
// these blocks want: they are about WHICH DOOR ANSWERS, not about who is allowed to see the answer.
func CrfNoUnits(): List<CompilationUnit> {
    return new List<CompilationUnit>()
}

func CrfItemNames(result: CompletionResult?, group: string): string {
    if result == null {
        return "<null>"
    }

    completions := result.Completions
    items := new List<CompletionItem>()
    if !completions.TryGetValue(group, out items) {
        return "<no-group>"
    }

    text := ""
    index := 0
    while index < items.Count {
        if index > 0 {
            text = text + ","
        }

        text = text + items[index].Name
        index = index + 1
    }

    return text
}

test "the column search runs nearest first, alternates outward, and never proposes a column at or below zero on the left" {
    // The order IS the contract: a nearer column must never lose to a farther one, so the caret
    // itself comes first and every distance after it is left-then-right.
    assert CrfColumnText(CompletionReceiverFacts.NearbyColumns(10, 3)) == "10,9,11,8,12,7,13"

    // Near the left margin the left-hand candidates fall away one at a time while every right-hand
    // mirror is kept. The AST has no column zero, so proposing one would only waste a walk.
    assert CrfColumnText(CompletionReceiverFacts.NearbyColumns(3, 3)) == "3,2,4,1,5,6"
    assert CrfColumnText(CompletionReceiverFacts.NearbyColumns(2, 3)) == "2,1,3,4,5"
    assert CrfColumnText(CompletionReceiverFacts.NearbyColumns(1, 3)) == "1,2,3,4"

    // A non-positive caret contributes no column of its own and still searches outward.
    assert CrfColumnText(CompletionReceiverFacts.NearbyColumns(0, 3)) == "1,2,3"

    // The distance bound is honoured exactly: zero distance is the caret alone.
    assert CrfColumnText(CompletionReceiverFacts.NearbyColumns(10, 0)) == "10"
    assert CrfColumnText(CompletionReceiverFacts.NearbyColumns(10, 1)) == "10,9,11"
}

test "the search finds a member access up to three columns away and stops there" {
    access: Expression = CrfAccess(CrfName("person", 3, 5), "Name", 3, 5)
    unit := CrfUnitWithExpression(access, 3, 5)

    // The caret exactly on the receiver finds it.
    exact := CompletionReceiverFacts.FindMemberAccessAtPosition(unit, 3, 5)
    assert exact != null
    assert exact.MemberName == "Name"

    // A caret PAST the expression finds it too — that is the ordinary case, because the caret sits
    // after the dot the user just typed.
    assert CompletionReceiverFacts.FindMemberAccessAtPosition(unit, 3, 12) != null

    // A caret up to three columns SHORT of it still finds it, by the outward walk.
    assert CompletionReceiverFacts.FindMemberAccessAtPosition(unit, 3, 4) != null
    assert CompletionReceiverFacts.FindMemberAccessAtPosition(unit, 3, 3) != null
    assert CompletionReceiverFacts.FindMemberAccessAtPosition(unit, 3, 2) != null

    // Four columns short is outside the window and answers nothing. The bound is real.
    assert CompletionReceiverFacts.FindMemberAccessAtPosition(unit, 3, 1) == null

    // A different line answers nothing however close the column is.
    assert CompletionReceiverFacts.FindMemberAccessAtPosition(unit, 9, 5) == null

    // A unit with no declarations at all answers nothing rather than faulting.
    assert CompletionReceiverFacts.FindMemberAccessAtPosition(CrfUnit(new List<Declaration>()), 3, 5) == null
}

test "a call is unwrapped to its callee exactly when that callee is itself a member access" {
    // The call is at column 5 and its callee one column further in, so the position walk answers
    // the CALL and the unwrap arm is the thing under test.
    memberCallee: Expression = CrfAccess(CrfName("list", 3, 6), "Add", 3, 6)
    call := CrfCall(memberCallee, 3, 5)
    unit := CrfUnitWithExpression(call, 3, 5)

    unwrapped := CompletionReceiverFacts.FindMemberAccessAtPosition(unit, 3, 5)
    assert unwrapped != null
    assert unwrapped.MemberName == "Add"

    // A call on a plain identifier is NOT a member access, and the walk keeps looking rather than
    // answering with it.
    plainCall := CrfCall(CrfName("Frobnicate", 3, 6), 3, 5)
    assert CompletionReceiverFacts.FindMemberAccessAtPosition(CrfUnitWithExpression(plainCall, 3, 5), 3, 5) == null
}

test "every nameable receiver shape reads back as the text the user wrote" {
    assert CompletionReceiverFacts.FormatReceiverExpression(CrfName("person", 1, 1)) == "person"

    chain: Expression = CrfAccess(CrfName("person", 1, 1), "Address", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(chain) == "person.Address"

    // A chain of chains keeps every link.
    deeper: Expression = CrfAccess(chain, "City", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(deeper) == "person.Address.City"

    // A call drops its ARGUMENTS and keeps its callee — the receiver is the call's result, and the
    // arguments say nothing about its type.
    assert CompletionReceiverFacts.FormatReceiverExpression(CrfCall(chain, 1, 1)) == "person.Address()"

    // Parentheses are dropped: `(person)` and `person` are the same receiver.
    parenthesized: Expression = new ParenthesizedExpression(CrfName("person", 1, 1), 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(parenthesized) == "person"

    // Every literal answers its own literal text, which is what the literal-typing door reads back.
    stringLiteral: Expression = new StringLiteralExpression("\"abc\"", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(stringLiteral) == "\"abc\""

    charLiteral: Expression = new CharLiteralExpression("'c'", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(charLiteral) == "'c'"

    intLiteral: Expression = new IntLiteralExpression("42", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(intLiteral) == "42"

    floatLiteral: Expression = new FloatLiteralExpression("1.5", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(floatLiteral) == "1.5"

    trueLiteral: Expression = new BoolLiteralExpression(true, 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(trueLiteral) == "true"

    falseLiteral: Expression = new BoolLiteralExpression(false, 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(falseLiteral) == "false"

    nullLiteral: Expression = new NullLiteralExpression(1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(nullLiteral) == "null"

    thisExpression: Expression = new ThisExpression(1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(thisExpression) == "this"

    baseExpression: Expression = new BaseExpression(1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(baseExpression) == "base"
}

test "a shape that cannot be named answers nothing, and so does a call whose own callee cannot be named" {
    // No expression at all — the caller reaches this whenever the position walk found nothing.
    assert CompletionReceiverFacts.FormatReceiverExpression(null) == null

    // A shape outside the thirteen: an index access is not a receiver a completion can name.
    indexed: Expression = new IndexAccessExpression(CrfName("items", 1, 1), CrfName("i", 1, 1), false, 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(indexed) == null

    // The declines COMPOSE: a call over an unnameable callee is unnameable, and so is a member
    // access over one, and so is a parenthesised one.
    assert CompletionReceiverFacts.FormatReceiverExpression(CrfCall(indexed, 1, 1)) == null

    overIndexed: Expression = CrfAccess(indexed, "Length", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(overIndexed) == null

    wrapped: Expression = new ParenthesizedExpression(indexed, 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(wrapped) == null
}

test "a member access with no usable member name answers the receiver without the dot" {
    // THE MID-EDIT CASE. The user has typed the dot, the parser has produced `<error>` for the
    // member, and the completion has to answer `person` — not `person.<error>` and not nothing.
    errored: Expression = CrfAccess(CrfName("person", 1, 1), "<error>", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(errored) == "person"

    empty: Expression = CrfAccess(CrfName("person", 1, 1), "", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(empty) == "person"

    // But a receiver that could not be named is still nothing, error placeholder or not.
    indexed: Expression = new IndexAccessExpression(CrfName("items", 1, 1), CrfName("i", 1, 1), false, 1, 1)
    erroredOverIndexed: Expression = CrfAccess(indexed, "<error>", 1, 1)
    assert CompletionReceiverFacts.FormatReceiverExpression(erroredOverIndexed) == null
}

test "an interpolated string reads back as its own text with every hole collapsed" {
    parts := new List<InterpolatedStringPart>()
    head: InterpolatedStringPart = new InterpolatedStringText("Hello, ", 1, 1)
    parts.Add(head)
    hole: InterpolatedStringPart = new InterpolatedStringHole(CrfName("name", 1, 1), null, 1, 1)
    parts.Add(hole)
    tail: InterpolatedStringPart = new InterpolatedStringText("!", 1, 1)
    parts.Add(tail)

    plain: Expression = new InterpolatedStringExpression(parts, 1, 1, false)
    assert CompletionReceiverFacts.FormatReceiverExpression(plain) == "$\"Hello, {...}!\""

    // The RAW form keeps its three quotes. The receiver's type is `string` either way, so the only
    // thing this changes is whether the text a reader sees matches what they wrote.
    raw: Expression = new InterpolatedStringExpression(parts, 1, 1, true)
    assert CompletionReceiverFacts.FormatReceiverExpression(raw) == "$\"\"\"Hello, {...}!\"\"\""

    // An interpolated string with no parts at all is still a well-formed literal.
    emptyParts: Expression = new InterpolatedStringExpression(new List<InterpolatedStringPart>(), 1, 1, false)
    assert CompletionReceiverFacts.FormatReceiverExpression(emptyParts) == "$\"\""
}

test "a source declaration answers before metadata, and an empty declaration does not win" {
    members := new DeclaredMemberInfo[](1)
    members[0] = CrfMember("Name")
    declared: TypeInfo = CrfTypes.Class("Person", members)

    completions := new Dictionary<string, List<CompletionItem>>()
    answered := CompletionReceiverFacts.ResolveMemberCompletions(declared, "person", CrfNoModels(), completions, CompletionMemberFilter.InstanceOnly, CrfNoUnits(), "")
    assert answered != null
    assert answered.Context == CompletionContext.MemberAccess
    assert answered.Receiver == "person"
    assert answered.ReceiverType == "Person"
    assert CrfItemNames(answered, "properties") == "Name"

    // A DECLARED TYPE WITH NO MEMBERS IS NOT AN ANSWER. It has no metadata twin either, so both
    // doors are silent and the caller is told to try the next way of typing the receiver.
    emptyDeclared: TypeInfo = CrfTypes.Class("Hollow", CrfNoMembers())
    assert CompletionReceiverFacts.ResolveMemberCompletions(emptyDeclared, "hollow", CrfNoModels(), new Dictionary<string, List<CompletionItem>>(), CompletionMemberFilter.InstanceOnly, CrfNoUnits(), "") == null

    // A type no declaration explains falls through to metadata, and the answered type name is the
    // CLR FULL name rather than the display text the declaration door would have used.
    reflected := CompletionReceiverFacts.ResolveMemberCompletions(BuiltInTypes.String, "\"abc\"", CrfNoModels(), new Dictionary<string, List<CompletionItem>>(), CompletionMemberFilter.InstanceOnly, CrfNoUnits(), "")
    assert reflected != null
    assert reflected.ReceiverType == "System.String"
    assert reflected.Receiver == "\"abc\""
}

test "the three doors are tried in order and an empty answer is still a member-access answer" {
    access: Expression = CrfAccess(CrfName("person", 3, 5), "Name", 3, 5)
    unit := CrfUnitWithExpression(access, 3, 5)

    members := new DeclaredMemberInfo[](1)
    members[0] = CrfMember("Name")
    declared: TypeInfo = CrfTypes.Class("Person", members)

    model := new SemanticModel()
    variables := model.Variables
    variables["person"] = declared

    // DOOR 2 — the receiver text as an identifier. No expression type was recorded, so the first
    // door is silent and the identifier lookup answers.
    identifierAnswer := CompletionReceiverFacts.GetMemberAccessCompletions(unit, model, "person", 3, 5, CrfNoModels())
    assert identifierAnswer.Context == CompletionContext.MemberAccess
    assert identifierAnswer.Receiver == "person"
    assert identifierAnswer.ReceiverType == "Person"
    assert CrfItemNames(identifierAnswer, "properties") == "Name"

    // DOOR 3 — a literal, which no model records because no declaration exists.
    literalAnswer := CompletionReceiverFacts.GetMemberAccessCompletions(unit, model, "\"abc\"", 3, 5, CrfNoModels())
    assert literalAnswer.ReceiverType == "System.String"

    // ALL THREE SILENT. The answer is still MemberAccess with an empty group set — the caller asked
    // about a receiver, so "nothing to offer" is the honest reply, not "unknown position".
    emptyAnswer := CompletionReceiverFacts.GetMemberAccessCompletions(unit, model, "nobody", 3, 5, CrfNoModels())
    assert emptyAnswer.Context == CompletionContext.MemberAccess
    assert emptyAnswer.Receiver == null
    assert emptyAnswer.ReceiverType == null
    assert emptyAnswer.Completions.Count == 0

    // NO RECEIVER AND NO MODEL AT ALL is the same empty member-access answer rather than a fault.
    bare := CompletionReceiverFacts.GetMemberAccessCompletions(CrfUnit(new List<Declaration>()), null, null, 3, 5, CrfNoModels())
    assert bare.Context == CompletionContext.MemberAccess
    assert bare.Completions.Count == 0
}

test "a null precomputed receiver is recovered from the member access the caret is in" {
    access: Expression = CrfAccess(CrfName("person", 3, 5), "Name", 3, 5)
    unit := CrfUnitWithExpression(access, 3, 5)

    members := new DeclaredMemberInfo[](1)
    members[0] = CrfMember("Name")
    declared: TypeInfo = CrfTypes.Class("Person", members)

    model := new SemanticModel()
    variables := model.Variables
    variables["person"] = declared

    // The caller passed nothing, so the receiver text comes from the AST — which is the whole
    // reason the position walk and the text rendering live in one file.
    recovered := CompletionReceiverFacts.GetMemberAccessCompletions(unit, model, null, 3, 5, CrfNoModels())
    assert recovered.Receiver == "person"
    assert recovered.ReceiverType == "Person"
}

class CrfTypes {
    static func Class(name: string, members: DeclaredMemberInfo[]): TypeInfo {
        interfaces := new TypeReference[](0)
        typeParameters := new TypeParameter[](0)
        constructorParameters := new ParameterDeclarationInfo[](0)
        nestedTypes := new NestedTypeInfo[](0)
        classType: TypeInfo = new ClassTypeInfo(name, 1, 1, false, null, interfaces, typeParameters, constructorParameters, members, nestedTypes, true)
        return classType
    }
}
