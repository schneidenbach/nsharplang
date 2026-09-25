namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR THE GHOST TEXT AN EDITOR SHOWS. These came out of `InlayHintHandler.cs`, where a
// live document manager was the only way to reach them: the "annotated bindings are left alone"
// rule, the visible-range filter, the keyword-width arithmetic that places a loop variable's hint,
// and the display text of a bound type — whose LAST arm is `ToString` and may therefore answer
// nothing at all. That last fact is why the text is nullable, and it is asserted here.
func EihModel(names: string[], types: TypeInfo[]): SemanticModel {
    model := new SemanticModel()
    index := 0
    while index < names.Length {
        model.Variables[names[index]] = types[index]
        index = index + 1
    }
    return model
}

func EihSimple(name: string): TypeInfo {
    info: TypeInfo = new SimpleTypeInfo(name)
    return info
}

func EihStatements(statements: Statement[]): List<Statement> {
    list := new List<Statement>()
    for statement in statements {
        list.Add(statement)
    }
    return list
}

func EihBlock(statements: Statement[], line: int): BlockStatement {
    return new BlockStatement(EihStatements(statements), line, 1)
}

func EihBinding(name: string, declaredType: TypeReference?, hasInitializer: bool, line: int, column: int): VariableDeclarationStatement {
    initializer: Expression? = null
    if hasInitializer {
        initializer = new IdentifierExpression("seed", line, column)
    }
    return new VariableDeclarationStatement(name, declaredType, initializer, VariableKind.Let, line, column)
}

func EihUnit(body: BlockStatement): CompilationUnit {
    declarations := new List<Declaration>()
    declaration: Declaration = new FunctionDeclaration("run", new List<Parameter>(), null, body, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 1, 1)
    declarations.Add(declaration)
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

// ONLY AN INFERRED BINDING IS HINTED. An annotation the reader can already see is not repeated,
// and a declaration with nothing to infer from says nothing.
test "an inlay hint is offered only for a binding that inferred its own type" {
    annotated: TypeReference = new SimpleTypeReference("int", 1, 1)
    body := EihBlock(
        [
            EihBinding("total", null, true, 4, 5),
            EihBinding("named", annotated, true, 5, 5),
            EihBinding("bare", null, false, 6, 5)
        ],
        3
    )

    model := EihModel(["total", "named", "bare"], [EihSimple("int"), EihSimple("int"), EihSimple("int")])
    rows := EditorInlayHintFacts.HintRows(EihUnit(body), model, 0, 99)

    assert rows.Count == 1
    assert rows[0].Label == ": int"
    assert rows[0].Line == 3
    assert rows[0].Character == 9
}

// A NAME THE BOUND MODEL NEVER RESOLVED GETS NOTHING, rather than a guess or an empty annotation.
test "an inlay hint is not offered for a binding the bound model cannot name" {
    body := EihBlock([EihBinding("mystery", null, true, 4, 5)], 3)
    assert EditorInlayHintFacts.HintRows(EihUnit(body), EihModel([], []), 0, 99).Count == 0
    assert EditorInlayHintFacts.HintRows(null, EihModel([], []), 0, 99).Count == 0
    assert EditorInlayHintFacts.HintRows(EihUnit(body), null, 0, 99).Count == 0
}

// THE VISIBLE RANGE IS INCLUSIVE AT BOTH ENDS, and a binding outside it costs nothing.
test "an inlay hint is offered only for the lines the editor can see" {
    body := EihBlock(
        [
            EihBinding("a", null, true, 4, 5),
            EihBinding("b", null, true, 10, 5)
        ],
        3
    )
    model := EihModel(["a", "b"], [EihSimple("int"), EihSimple("int")])

    assert EditorInlayHintFacts.HintRows(EihUnit(body), model, 3, 3).Count == 1
    assert EditorInlayHintFacts.HintRows(EihUnit(body), model, 3, 9).Count == 2
    assert EditorInlayHintFacts.HintRows(EihUnit(body), model, 4, 8).Count == 0
}

// A LOOP VARIABLE'S HINT IS PLACED BY COUNTING THE KEYWORD, because the parser records where the
// keyword begins and not where the variable does. The two keywords have different widths and both
// are counted from the statement's own column.
test "an inlay hint after a loop variable is placed by counting the keyword" {
    foreachStatement: Statement = new ForeachStatement("item", new IdentifierExpression("items", 5, 20), EihBlock([], 5), 5, 5)
    awaitStatement: Statement = new AwaitForEachStatement("row", new IdentifierExpression("rows", 8, 26), EihBlock([], 8), 8, 5)
    body := EihBlock([foreachStatement, awaitStatement], 3)
    model := EihModel(["item", "row"], [EihSimple("string"), EihSimple("int")])

    rows := EditorInlayHintFacts.HintRows(EihUnit(body), model, 0, 99)
    assert rows.Count == 2
    assert rows[0].Line == 4
    assert rows[0].Character == 16
    assert rows[0].Label == ": string"
    assert rows[1].Line == 7
    assert rows[1].Character == 21
    assert rows[1].Label == ": int"
}

// THE DISPLAY TEXT IS NULLABLE AND THAT IS NOT AN OVERSIGHT. Every named arm answers a spelling;
// the last arm is `ToString` on a `TypeInfo` none of them recognised, and `object.ToString` may
// answer null. A null text means NO HINT, exactly as an empty one does.
test "an inlay hint's type text is nullable because its last arm is ToString" {
    assert EditorInlayHintFacts.TypeHintText(EihSimple("int")) == "int"

    elements := new List<TupleTypeElementInfo>()
    elements.Add(new TupleTypeElementInfo("Min", EihSimple("int")))
    elements.Add(new TupleTypeElementInfo(null, EihSimple("string")))
    tuple: TypeInfo = new TupleTypeInfo(elements)
    assert EditorInlayHintFacts.TypeHintText(tuple) == "(Min: int, string)"

    classInfo: TypeInfo = new ClassTypeInfo("Greeter", 0, 0, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), false)
    assert EditorInlayHintFacts.TypeHintText(classInfo) == "Greeter"

    interfaceInfo: TypeInfo = new InterfaceTypeInfo("IGreeter", 0, 0, false, new TypeReference[](0), new TypeParameter[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    assert EditorInlayHintFacts.TypeHintText(interfaceInfo) == "IGreeter"
}

// A CLR TYPE READS IN N#'s OWN WORDS, and a generic one is written with its arguments rather than
// with the runtime's arity mark.
test "an inlay hint spells a CLR type the way N# spells it" {
    assert EditorInlayHintFacts.ReflectionHintText(typeof(int)) == "int"
    assert EditorInlayHintFacts.ReflectionHintText(typeof(long)) == "long"
    assert EditorInlayHintFacts.ReflectionHintText(typeof(bool)) == "bool"
    assert EditorInlayHintFacts.ReflectionHintText(typeof(string)) == "string"
    assert EditorInlayHintFacts.ReflectionHintText(typeof(double)) == "double"
    assert EditorInlayHintFacts.ReflectionHintText(typeof(object)) == "object"
    assert EditorInlayHintFacts.ReflectionHintText(typeof(DateTime)) == "DateTime"
    assert EditorInlayHintFacts.ReflectionHintText(typeof(List<string>)) == "List<string>"
    assert EditorInlayHintFacts.ReflectionHintText(typeof(Dictionary<string, List<int>>)) == "Dictionary<string, List<int>>"
}

// THE WALK REACHES A BODY WHEREVER ONE IS, and a nested body is reached through the statement it
// belongs to rather than by a second pass over the file.
test "an inlay hint is found inside a nested body" {
    inner := EihBinding("deep", null, true, 8, 13)
    ifStatement: Statement = new IfStatement(new IdentifierExpression("flag", 7, 8), EihBlock([inner], 7), null, 7, 5)
    body := EihBlock([ifStatement], 3)
    model := EihModel(["deep"], [EihSimple("bool")])

    rows := EditorInlayHintFacts.HintRows(EihUnit(body), model, 0, 99)
    assert rows.Count == 1
    assert rows[0].Line == 7
    assert rows[0].Character == 16
}
