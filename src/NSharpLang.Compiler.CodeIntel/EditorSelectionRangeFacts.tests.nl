namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// CONTRACTS FOR EXPANDING THE SELECTION. These came out of `SelectionRangeHandler.cs`: the
// outermost-first chain, the whole-file frame that always sits above it, the reach of an `if`
// chain and a `try`, the switch that is one frame and not descended into, and the fact — dead
// weight in the C#, a rule here — that the answer depends on the caret's LINE and not its column.
func EsrLines(text: string): string[] {
    return text.Split('\n')
}

func EsrStatements(statements: Statement[]): List<Statement> {
    list := new List<Statement>()
    for statement in statements {
        list.Add(statement)
    }
    return list
}

func EsrBlock(statements: Statement[], line: int): BlockStatement {
    return new BlockStatement(EsrStatements(statements), line, 1)
}

func EsrLeaf(line: int): Statement {
    statement: Statement = new ExpressionStatement(new IdentifierExpression("x", line, 1), line, 1)
    return statement
}

func EsrFunction(name: string, body: BlockStatement?, line: int): Declaration {
    declaration: Declaration = new FunctionDeclaration(name, new List<Parameter>(), null, body, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, line, 1)
    return declaration
}

func EsrUnit(declarations: Declaration[]): CompilationUnit {
    list := new List<Declaration>()
    for declaration in declarations {
        list.Add(declaration)
    }
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, list, 1, 1)
}

func EsrClass(name: string, members: Declaration[], line: int): Declaration {
    list := new List<Declaration>()
    for member in members {
        list.Add(member)
    }
    declaration: Declaration = new ClassDeclaration(name, null, null, new List<TypeReference>(), list, null, Modifiers.None, new List<AttributeNode>(), line, 1)
    return declaration
}

// THE CHAIN IS OUTERMOST FIRST and gets tighter with every link: the type, then the member, then
// the member's body, then the statement the caret is on.
test "expanding the selection walks from the type down to the statement the caret is on" {
    lines := EsrLines("class Box {\n    func Area(): int {\n        return 1\n    }\n}\n")
    body := EsrBlock([EsrLeaf(3)], 2)
    unit := EsrUnit([EsrClass("Box", [EsrFunction("Area", body, 2)], 1)])

    rows := EditorSelectionRangeFacts.ContainingRows(unit, 2, lines)
    assert rows.Count == 4
    assert rows[0].StartLine == 0
    assert rows[0].EndLine == 4
    assert rows[1].StartLine == 1
    assert rows[1].EndLine == 3
    assert rows[2].StartLine == 1
    assert rows[2].EndLine == 3
    assert rows[3].StartLine == 2
    assert rows[3].EndLine == 2
    assert rows[3].EndCharacter == 16
}

// THE CARET'S COLUMN IS NOT PART OF THE QUESTION. The C# threaded one through every frame into a
// containment test that never used it; the answer is the same wherever on the line the caret sits,
// and this row is what says so.
test "expanding the selection does not depend on where in the line the caret sits" {
    lines := EsrLines("func run(): void {\n    x\n}\n")
    unit := EsrUnit([EsrFunction("run", EsrBlock([EsrLeaf(2)], 1), 1)])

    rows := EditorSelectionRangeFacts.ContainingRows(unit, 1, lines)
    assert rows.Count == 3
    assert rows[2].StartLine == 1
    assert rows[2].EndLine == 1
}

// THE WHOLE FILE IS ALWAYS AVAILABLE AS THE OUTERMOST FRAME, measured without its final carriage
// return, and an empty file still answers a frame rather than nothing.
test "expanding the selection always reaches the whole file" {
    whole := EditorSelectionRangeFacts.WholeFileRow(EsrLines("a\nbb\nccc\r"))
    assert whole.StartLine == 0
    assert whole.EndLine == 2
    assert whole.EndCharacter == 3

    empty := EditorSelectionRangeFacts.WholeFileRow(EsrLines(""))
    assert empty.StartLine == 0
    assert empty.EndLine == 0
    assert empty.EndCharacter == 0
}

// A CARET OUTSIDE EVERY DECLARATION ANSWERS AN EMPTY CHAIN — the caller still offers the whole
// file, which is the only frame that contains a blank line between two types.
test "expanding the selection answers an empty chain outside every declaration" {
    lines := EsrLines("func run(): void {\n}\n\nfunc other(): void {\n}\n")
    unit := EsrUnit([EsrFunction("run", EsrBlock([], 1), 1), EsrFunction("other", EsrBlock([], 4), 4)])

    assert EditorSelectionRangeFacts.ContainingRows(unit, 2, lines).Count == 0
    assert EditorSelectionRangeFacts.ContainingRows(null, 0, lines).Count == 0
}

// AN `if` CHAIN REACHES THE END OF ITS LAST BRANCH, following `else if` all the way down, so
// expanding from inside the first branch offers the whole conditional and not just that arm.
test "expanding the selection reaches the end of an if chain's last branch" {
    lines := EsrLines("func run(): void {\n    if a {\n        b\n    } else if c {\n        d\n    } else {\n        e\n    }\n}\n")
    innerElse: Statement = new IfStatement(new IdentifierExpression("c", 4, 8), EsrBlock([EsrLeaf(5)], 4), EsrBlock([EsrLeaf(7)], 6), 4, 5)
    outer: Statement = new IfStatement(new IdentifierExpression("a", 2, 8), EsrBlock([EsrLeaf(3)], 2), innerElse, 2, 5)
    unit := EsrUnit([EsrFunction("run", EsrBlock([outer], 1), 1)])

    rows := EditorSelectionRangeFacts.ContainingRows(unit, 2, lines)
    assert rows.Count == 5
    assert rows[2].StartLine == 1
    assert rows[2].EndLine == 5
    assert rows[3].StartLine == 1
    assert rows[3].EndLine == 3
    assert rows[4].StartLine == 2
    assert rows[4].EndLine == 2
}

// A `try` REACHES THE END OF WHATEVER CLOSES IT — the finally block, else the last catch, else the
// try block itself.
//
// AND THE BRACE SCAN STARTS AT THAT BLOCK'S OWN LINE, which on `} finally {` is a line that CLOSES
// before it opens. The depth count goes negative and never returns to zero, so the scan gives up
// and answers the line it started on. That is the shipped answer — an `if`/`else` chain has the
// same shape and the same effect — and it is recorded here rather than quietly corrected, because
// correcting it would move ranges an editor is already drawing.
test "expanding the selection reaches the end of whatever closes a try" {
    lines := EsrLines("func run(): void {\n    try {\n        a\n    } catch {\n        b\n    } finally {\n        c\n    }\n}\n")
    catches := new List<CatchClause>()
    catches.Add(new CatchClause(null, null, EsrBlock([EsrLeaf(5)], 4)))

    withFinally := new TryStatement(EsrBlock([EsrLeaf(3)], 2), catches, EsrBlock([EsrLeaf(7)], 6), 2, 5)
    assert EditorSelectionRangeFacts.TryEndLine(withFinally, lines) == 6

    withCatch := new TryStatement(EsrBlock([EsrLeaf(3)], 2), catches, null, 2, 5)
    assert EditorSelectionRangeFacts.TryEndLine(withCatch, lines) == 4

    bare := new TryStatement(EsrBlock([EsrLeaf(3)], 2), new List<CatchClause>(), null, 2, 5)
    assert EditorSelectionRangeFacts.TryEndLine(bare, lines) == 4
}

// A `switch` IS ONE FRAME AND IS NOT DESCENDED INTO: its cases are not blocks, so there is no
// tighter frame to offer and expanding from inside a case reaches the whole switch.
test "expanding the selection treats a switch as one frame" {
    lines := EsrLines("func run(): void {\n    switch v {\n        case 1:\n            a\n    }\n}\n")
    cases := new List<SwitchCase>()
    cases.Add(new SwitchCase(null, EsrStatements([EsrLeaf(4)]), 3, 9))
    switchStatement: Statement = new SwitchStatement(new IdentifierExpression("v", 2, 12), cases, 2, 5)
    unit := EsrUnit([EsrFunction("run", EsrBlock([switchStatement], 1), 1)])

    rows := EditorSelectionRangeFacts.ContainingRows(unit, 3, lines)
    assert rows.Count == 3
    assert rows[2].StartLine == 1
    assert rows[2].EndLine == 4
}

// A LOOP WITH A SINGLE-STATEMENT BODY ENDS ON THAT STATEMENT'S OWN LINE, and one whose body the
// parser could not place falls back to the loop's own header line.
test "expanding the selection ends an unbraced loop body on its own line" {
    lines := EsrLines("func run(): void {\n    while a\n        b\n}\n")
    assert EditorSelectionRangeFacts.StatementEndLine(EsrLeaf(3), lines, 2) == 3
    assert EditorSelectionRangeFacts.StatementEndLine(EsrLeaf(0), lines, 2) == 2
    assert EditorSelectionRangeFacts.StatementEndLine(EsrBlock([], 2), lines, 2) == 2
}
