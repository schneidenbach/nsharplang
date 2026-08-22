namespace NSharpLang.Compiler.Columnar

import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR `AstNodeFinderCore.FindExpressionAtPosition`, IN N#.
//
// These replace the FINDER HALF of `tests/AstNodeFinderTests.cs`, which task 020 slice 23 deletes.
// That file had five `[Fact]`s and 21 `Assert.` occurrences decoding to 30 claim rows; 21 of the 30
// are about the finder and are restated here, and the other 9 — everything its second and third
// methods said about `Analyzer`, `SemanticModel` and `ClassTypeInfo` — moved to
// `tests/native/analyzer-identifier-binding`, because `Analyzer` is a C# type in `Compiler.dll` and
// `Compiler.dll` depends on this assembly rather than the other way round.
//
// THE INVENTORY THIS CORRECTS. Slice 22 recorded `AstNodeFinderTests.cs` as unreachable from the
// estate because it "drives `AstNodeFinder`, a code-intelligence type". Measuring it says otherwise:
// `src/NSharpLang.Compiler/AstNodeFinder.cs` is FIFTEEN lines and its whole body is
// `AstNodeFinderCore.FindExpressionAtPosition(ast, line, column) as Expression`, so the subject of
// three of the five methods, and of 21 of the 30 claim rows, is an N# class that lives HERE.
//
// THE ROUTE IS A WHOLE-LINE SWEEP, AND IT IS STRICTLY STRONGER THAN WHAT IT REPLACES. Every deleted
// method computed ONE cursor column with `line.IndexOf(...)`, asked the finder once and read one or
// two fields off the answer. `AnfSweep` asks EVERY column of the line from 0 to its end and reports
// the answers run-length encoded, so each contract pins the node type, the anchor, the identifying
// field AND the exact columns at which the answer changes. The boundary columns are the part no
// deleted assertion could see: a finder that switched from the receiver to the member access one
// column early or late would have passed all five.
//
// THE FIRST CLAIM IN EVERY CONTRACT IS THE PARSE CENSUS, AND THE DELETED HELPER COULD NOT MAKE IT:
//
//     private static CompilationUnit Parse(string source)
//     {
//         var result = ColumnarParserRecovery.ParseFileAst(source, "test.nl");
//         return result.CompilationUnit!;
//     }
//
// discards `.Errors` outright. MEASURED RESULT: three of the five fixtures parse CLEANLY and two do
// not — both of the `p.` fixtures report exactly one `NL102`, at the bare dot. That is the first
// time in this arc that the clean-parse pin has come back non-empty, and it is non-empty by design:
// the two fixtures exist precisely to ask what the finder answers over a RECOVERED tree.
//
// THE FIXTURES ARE THE DELETED ONES BYTE-FOR-BYTE, decoded by the C# compiler itself rather than by
// a hand-rolled literal reader — four regular `"…"` literals and one verbatim `@"…"`, whose content
// lines are flush-left as the deleted file spelled them. The cursor columns are decoded the same
// way: four of the five were computed at runtime by `line.IndexOf(...)` and are stated here as the
// literals that computation produced (18, 6, 15, 11); the fifth was already a literal 6.
//
// THREE THINGS THE SWEEP MEASURED THAT THE DELETED ASSERTIONS COULD NOT SEE ARE RECORDED PER
// CONTRACT BELOW, AND ONE OF THEM CONTRADICTS A DELETED TEST'S OWN NAME.

func AnfDescribe(node: object?): string {
    if node != null {
        return AnfDescribeNode(node)
    }

    return "<none>"
}

// The three node kinds these fixtures reach, each with its anchor and its identifying field; every
// other kind falls through to its type name and anchor, so a shape change is reported rather than
// silently flattened.
func AnfDescribeNode(node: object): string {
    member := node as MemberAccessExpression
    if member != null {
        return "MemberAccess@" + member.Line.ToString() + ":" + member.Column.ToString() + "|Member=" + member.MemberName + "|Object=" + AnfDescribeNode(member.Object)
    }

    identifier := node as IdentifierExpression
    if identifier != null {
        return "Identifier@" + identifier.Line.ToString() + ":" + identifier.Column.ToString() + "|Name=" + identifier.Name
    }

    call := node as CallExpression
    if call != null {
        return "Call@" + call.Line.ToString() + ":" + call.Column.ToString() + "|Callee=" + AnfDescribeNode(call.Callee)
    }

    return AnfDescribeOther(node)
}

func AnfDescribeOther(node: object): string {
    astNode := node as AstNode
    if astNode != null {
        return node.GetType().Name + "@" + astNode.Line.ToString() + ":" + astNode.Column.ToString()
    }

    return "<not-an-ast-node>"
}

// The production entry point. `line` and `column` are ZERO-BASED here, as they are in the deleted
// C# and in the owner's own `IsAtPosition`, while every anchor the description reports is the AST's
// ONE-BASED position — which is why a cursor at column 17 answers a node anchored at column 18.
func AnfAt(source: string, line: int, column: int): string {
    unit := PsAst(source)
    if unit != null {
        return AnfDescribe(AstNodeFinderCore.FindExpressionAtPosition(unit, line, column))
    }

    return "<no-unit>"
}

func AnfAppendRun(builder: StringBuilder, fromColumn: int, toColumn: int, value: string) {
    builder.Append(fromColumn.ToString())
    builder.Append("-")
    builder.Append(toColumn.ToString())
    builder.Append("=")
    builder.Append(value)
    builder.Append(";")
}

// Every column of one line, run-length encoded. A run boundary is a column at which the finder's
// answer changes, so the encoding states the boundaries explicitly instead of burying them.
func AnfSweep(source: string, line: int, lastColumn: int): string {
    builder := new StringBuilder()
    runStart := 0
    runValue := AnfAt(source, line, 0)
    column := 1
    while column <= lastColumn {
        current := AnfAt(source, line, column)
        if current != runValue {
            AnfAppendRun(builder, runStart, column - 1, runValue)
            runStart = column
            runValue = current
        }

        column = column + 1
    }

    AnfAppendRun(builder, runStart, lastColumn, runValue)
    return builder.ToString()
}


// ---- contracts ----

// WHAT THE SWEEP ADDS HERE: the deleted method asked column 18 and got the member access. The
// boundary is at 17, ONE COLUMN EARLIER — the member access anchors at one-based column 18, and the
// owner admits a node whose zero-based column is `<= targetColumn`. Columns 13-16 answer the
// RECEIVER, and everything left of the initializer answers nothing at all: the variable
// declaration's own name is not an expression and never appears.
test "020 s23 finder: over `value := user.Name` the whole line answers in three runs — nothing up to 12, the receiver `user` from 13, and the member access from 17, one column before the cursor the deleted test computed (was AstNodeFinderTests.PrefersMemberAccessAtMemberCursor)" {
    source := "func main() {\n    value := user.Name\n}"
    assert PsCensus(source) == ""
    assert AnfSweep(source, 1, 22) == "0-12=<none>;13-16=Identifier@2:14|Name=user;17-22=MemberAccess@2:18|Member=Name|Object=Identifier@2:14|Name=user;"
    assert AnfAt(source, 1, 18) == "MemberAccess@2:18|Member=Name|Object=Identifier@2:14|Name=user"
}

// WHAT THE SWEEP ADDS HERE: the recovered member access exists from the DOT onward and the receiver
// alone answers at the identifier's own column, so the two are distinguishable by cursor position
// rather than only by field. And the parse is NOT clean — one `NL102` at the dot — which the
// deleted helper discarded.
test "020 s23 finder: a bare trailing dot recovers a MemberAccess whose MemberName is `<error>` over the identifier receiver, answering from column 5 while column 4 still answers the receiver, and the parse reports exactly one NL102 at the dot (was AstNodeFinderTests.ReturnsIncompleteMemberAccessAtDotCursor, finder half)" {
    source := "\nclass Person {\n    Name: string\n}\n\nfunc main(): void\n    let p = new Person()\n    p."
    assert PsCensus(source) == "NL102@8:5+1;"
    assert AnfSweep(source, 7, 7) == "0-3=<none>;4-4=Identifier@8:5|Name=p;5-7=MemberAccess@8:6|Member=<error>|Object=Identifier@8:5|Name=p;"
    assert AnfAt(source, 7, 6) == "MemberAccess@8:6|Member=<error>|Object=Identifier@8:5|Name=p"
}

// WHAT THE SWEEP ADDS HERE: the three-member class in front of the same trailing dot changes NOTHING
// about the finder's answer — the runs, the boundaries and the recovered shape are identical to the
// one-member fixture five lines up, only the line number moves. The deleted pair could not state
// that, because neither swept and neither compared.
test "020 s23 finder: the completion-source fixture recovers the SAME three runs at the same boundaries as the one-member fixture, with only the line number moved, and reports the same single NL102 at its dot (was AstNodeFinderTests.ReturnsIncompleteMemberAccessForCompletionSource, finder half)" {
    source := "\nclass Person {\n    Name: string\n    Age: int\n\n    func Greet(): string {\n        return \"Hello\"\n    }\n}\n\nfunc main(): void\n    let p = new Person()\n    p."
    assert PsCensus(source) == "NL102@13:5+1;"
    assert AnfSweep(source, 12, 7) == "0-3=<none>;4-4=Identifier@13:5|Name=p;5-7=MemberAccess@13:6|Member=<error>|Object=Identifier@13:5|Name=p;"
    assert AnfAt(source, 12, 6) == "MemberAccess@13:6|Member=<error>|Object=Identifier@13:5|Name=p"
}

// WHAT THE SWEEP ADDS HERE: the deleted method landed on column 15, which is the FIRST column that
// answers anything at all — one to its left the whole line is silent. It reached the identifier
// through a class member's function body and a return statement, and the sweep says the return
// KEYWORD itself contributes no node.
test "020 s23 finder: the walk descends into a class member's function body and its return value, and the identifier answers from column 15 — exactly the first answering column, with the return keyword contributing nothing (was AstNodeFinderTests.TraversesClassFunctionBodies)" {
    source := "class Person {\n    func Speak(): string {\n        return Name\n    }\n}"
    assert PsCensus(source) == ""
    assert AnfSweep(source, 2, 19) == "0-14=<none>;15-19=Identifier@3:16|Name=Name;"
    assert AnfAt(source, 2, 15) == "Identifier@3:16|Name=Name"
}

// WHAT THE SWEEP ADDS HERE, AND IT CONTRADICTS THE DELETED TEST'S OWN NAME: there is no
// `CallExpression` anywhere in this tree. `print(count)` parses as a PRINT STATEMENT whose value is
// a PARENTHESIZED expression, so the single column that answers something other than the identifier
// — column 9, the open paren — answers `ParenthesizedExpression`, and the method named
// "PrefersCallArgumentAtArgumentCursor" was never over a call argument at all. The deleted assertion
// could not see it, because it asked column 11 and read only `.Name`.
test "020 s23 finder: `print(count)` holds NO CallExpression — the open paren answers a ParenthesizedExpression and every column from 10 answers the identifier, so the deleted test's `call argument` name describes a shape the tree does not have (was AstNodeFinderTests.PrefersCallArgumentAtArgumentCursor)" {
    source := "\nfunc main(): void\n    let count = 42\n    print(count)"
    assert PsCensus(source) == ""
    assert AnfSweep(source, 3, 16) == "0-8=<none>;9-9=ParenthesizedExpression@4:10;10-16=Identifier@4:11|Name=count;"
    assert AnfAt(source, 3, 11) == "Identifier@4:11|Name=count"
}

// THE LINE CONTROL. Every contract above sweeps ONE line, so each is consistent with a finder that
// ignored the line entirely and answered by column alone. These four sweeps are over the OTHER
// lines of two of the fixtures — the signature and the closing brace of the first, and the
// signature and the closing brace of the class-body one — and every column of all four answers
// nothing. Nothing in the deleted file asked a second position of any fixture.
test "020 s23 finder: the answer is LINE-SCOPED — every column of the signature line and of the closing-brace line of both the member-access fixture and the class-body fixture answers nothing at all" {
    memberAccessSource := "func main() {\n    value := user.Name\n}"
    classBodySource := "class Person {\n    func Speak(): string {\n        return Name\n    }\n}"

    assert AnfSweep(memberAccessSource, 0, 13) == "0-13=<none>;"
    assert AnfSweep(memberAccessSource, 2, 1) == "0-1=<none>;"
    assert AnfSweep(classBodySource, 1, 25) == "0-25=<none>;"
    assert AnfSweep(classBodySource, 3, 5) == "0-5=<none>;"
}
