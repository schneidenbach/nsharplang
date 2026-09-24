namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar


// THE `<` DISAMBIGUATION AND PER-ELEMENT TUPLE NAMING, STATED AS SHAPES (census wave 3, PARSE2).
//
// Two rules meet in this file, and both are decided in the parser before any type is known:
//
//   (1) A `<` after a name opens a TYPE-ARGUMENT LIST when the matching `>` is followed by a `(`
//       (a generic method call) or by a `.` (a constructed generic type receiver), and is a
//       COMPARISON otherwise. One bounded, pure token scan answers both; the close token is the only
//       difference. The scan used to have NO depth counting, so the first `>` it met ended the list
//       and `Task.FromResult<List<int>?>(null)` -- whose first `>` closes the INNER `List<int` --
//       was read as a comparison and reported `Unexpected token '?' in expression`, NL411, NL301,
//       NL305 and every null-narrowing after it. In the converted LanguageServer that one shape
//       produced roughly 270 of ~340 diagnostics.
//
//   (2) A TUPLE ELEMENT'S NAME is decided per element, in a literal and in a type alike, so
//       `(null, last, IsConstructor: true)` and `(string?, string, IsConstructor: bool)` are
//       ordinary three-element tuples whose third element is named. Both parsers used to run in one
//       of two modes chosen by the FIRST element.
//
// THE ROWS ARE SHAPES, NOT WHOLE TREES. `ColumnarParserCallAccess.tests.nl` pins whole trees for the
// generic-call family and `ColumnarParserAst.tests.nl` for the tuple family; what is new here is
// WHICH READING each ambiguous source gets, and a terse row says that in one line where a golden
// tree says it in thirty. Every source also pins its diagnostic census, so an accepted shape is a
// CLEAN parse rather than a recovered one.

// The statement's initializer expression, rendered as a one-line shape row. Only the distinctions
// this file is about are spelled out; everything else collapses to its node family.
func ScanRow(source: string): string {
    unit := ColumnarParserRecovery.ParseFileAst(source, "test.nl").CompilationUnit
    if unit == null || unit.Declarations.Count != 1 {
        return "<no-unit>"
    }

    function := unit.Declarations[0] as FunctionDeclaration
    if function == null || function.Body == null || function.Body.Statements.Count != 1 {
        return "<no-body>"
    }

    declaration := function.Body.Statements[0] as VariableDeclarationStatement
    if declaration == null || declaration.Initializer == null {
        return "<no-decl>"
    }

    return ScanExpressionRow(declaration.Initializer)
}

func ScanExpressionRow(expression: Expression?): string {
    if expression == null {
        return "<null>"
    }

    identifier := expression as IdentifierExpression
    if identifier != null {
        return identifier.Name
    }

    intLiteral := expression as IntLiteralExpression
    if intLiteral != null {
        return intLiteral.Value
    }

    boolLiteral := expression as BoolLiteralExpression
    if boolLiteral != null {
        return boolLiteral.Value ? "true" : "false"
    }

    if (expression as NullLiteralExpression) != null {
        return "null"
    }

    call := expression as CallExpression
    if call != null {
        return "call[" + ScanExpressionRow(call.Callee) + ScanTypeArgumentRow(call.TypeArguments) + "](" + ScanArgumentRow(call.Arguments) + ")"
    }

    member := expression as MemberAccessExpression
    if member != null {
        return ScanExpressionRow(member.Object) + "." + member.MemberName
    }

    binary := expression as BinaryExpression
    if binary != null {
        return "bin[" + ScanExpressionRow(binary.Left) + " " + ScanOperatorRow(binary.Operator) + " " + ScanExpressionRow(binary.Right) + "]"
    }

    conditional := expression as TernaryExpression
    if conditional != null {
        return "cond[" + ScanExpressionRow(conditional.Condition) + "?" + ScanExpressionRow(conditional.ThenExpression) + ":" + ScanExpressionRow(conditional.ElseExpression) + "]"
    }

    parenthesized := expression as ParenthesizedExpression
    if parenthesized != null {
        return "(" + ScanExpressionRow(parenthesized.Inner) + ")"
    }

    tuple := expression as TupleExpression
    if tuple != null {
        row := "tuple["
        index := 0
        while index < tuple.Elements.Count {
            if index > 0 {
                row = row + ", "
            }

            element := tuple.Elements[index]
            if element.Name != null {
                row = row + element.Name + ": "
            }

            row = row + ScanExpressionRow(element.Value)
            index = index + 1
        }

        return row + "]"
    }

    generic := expression as GenericTypeExpression
    if generic != null {
        return "gtype[" + ScanTypeRow(generic.Type) + "]"
    }

    indexAccess := expression as IndexAccessExpression
    if indexAccess != null {
        return ScanExpressionRow(indexAccess.Object) + "[" + ScanExpressionRow(indexAccess.Index) + "]"
    }

    return "<other-expression>"
}

// The four operators these rows can reach, spelled out: an enum's `ToString` does not emit in the
// compiler-service estate, so the mapping is written rather than reflected.
func ScanOperatorRow(symbol: BinaryOperator): string {
    if symbol == BinaryOperator.Less {
        return "Less"
    }

    if symbol == BinaryOperator.Greater {
        return "Greater"
    }

    if symbol == BinaryOperator.And {
        return "And"
    }

    if symbol == BinaryOperator.Or {
        return "Or"
    }

    return "<other-operator>"
}

func ScanArgumentRow(arguments: List<Argument>?): string {
    if arguments == null {
        return ""
    }

    row := ""
    index := 0
    while index < arguments.Count {
        if index > 0 {
            row = row + ", "
        }

        row = row + ScanExpressionRow(arguments[index].Value)
        index = index + 1
    }

    return row
}

func ScanTypeArgumentRow(typeArguments: List<TypeReference>?): string {
    if typeArguments == null {
        return ""
    }

    row := "<"
    index := 0
    while index < typeArguments.Count {
        if index > 0 {
            row = row + ", "
        }

        row = row + ScanTypeRow(typeArguments[index])
        index = index + 1
    }

    return row + ">"
}

func ScanTypeRow(reference: TypeReference?): string {
    if reference == null {
        return "<null>"
    }

    simple := reference as SimpleTypeReference
    if simple != null {
        return simple.Name
    }

    nullable := reference as NullableTypeReference
    if nullable != null {
        return ScanTypeRow(nullable.InnerType) + "?"
    }

    array := reference as ArrayTypeReference
    if array != null {
        return ScanTypeRow(array.ElementType) + "[]"
    }

    generic := reference as GenericTypeReference
    if generic != null {
        row := generic.Name + "<"
        index := 0
        while index < generic.TypeArguments.Count {
            if index > 0 {
                row = row + ", "
            }

            row = row + ScanTypeRow(generic.TypeArguments[index])
            index = index + 1
        }

        return row + ">"
    }

    tuple := reference as TupleTypeReference
    if tuple != null {
        row := "("
        index := 0
        while index < tuple.Elements.Count {
            if index > 0 {
                row = row + ", "
            }

            element := tuple.Elements[index]
            if element.Name != null {
                row = row + element.Name + ": "
            }

            row = row + ScanTypeRow(element.Type)
            index = index + 1
        }

        return row + ")"
    }

    return "<other-type>"
}

// One statement wrapped in a function, the shape every row below parses.
func ScanSource(statement: string): string {
    return "func Test() {\n    result := " + statement + "\n}\n"
}

func ScanStatementRow(statement: string): string {
    return ScanRow(ScanSource(statement))
}

func ScanStatementCensus(statement: string): string {
    return PsCensus(ScanSource(statement))
}

test "census PARSE2 scan: a nullable type argument closes the list on the OUTER angle, so the call is a generic call and not a comparison" {
    // The shape the census found: the inner `>` of `List<int` is not the close.
    assert ScanStatementCensus("Task.FromResult<List<int>?>(null)") == ""
    assert ScanStatementRow("Task.FromResult<List<int>?>(null)") == "call[Task.FromResult<List<int>?>](null)"

    // The same list without the nullable annotation, which the old scan DID accept -- the control
    // that says the annotation was the whole difference.
    assert ScanStatementRow("Task.FromResult<List<int>>(value)") == "call[Task.FromResult<List<int>>](value)"
}

test "census PARSE2 scan: every type-argument form the type grammar has reaches a call" {
    assert ScanStatementRow("Method<int?>(value)") == "call[Method<int?>](value)"
    assert ScanStatementRow("Method<int[]>(value)") == "call[Method<int[]>](value)"
    assert ScanStatementRow("Method<System.Text.StringBuilder>(value)") == "call[Method<System.Text.StringBuilder>](value)"
    assert ScanStatementRow("Method<Dictionary<string, List<int>>?>(value)") == "call[Method<Dictionary<string, List<int>>?>](value)"
    assert ScanStatementRow("Method<(int, string)>(value)") == "call[Method<(int, string)>](value)"
    assert ScanStatementRow("Method<(Item: int, Label: string)>(value)") == "call[Method<(Item: int, Label: string)>](value)"
    assert ScanStatementRow("Method<(int, string)?>(value)") == "call[Method<(int, string)?>](value)"

    index := 0
    forms := new string[](7)
    forms[0] = "Method<int?>(value)"
    forms[1] = "Method<int[]>(value)"
    forms[2] = "Method<System.Text.StringBuilder>(value)"
    forms[3] = "Method<Dictionary<string, List<int>>?>(value)"
    forms[4] = "Method<(int, string)>(value)"
    forms[5] = "Method<(Item: int, Label: string)>(value)"
    forms[6] = "Method<(int, string)?>(value)"
    while index < forms.Length {
        if ScanStatementCensus(forms[index]) != "" {
            throw new InvalidOperationException("'" + forms[index] + "' did not parse cleanly: " + ScanStatementCensus(forms[index]))
        }

        index += 1
    }
}

test "census PARSE2 scan: the ambiguous comparisons keep their meaning" {
    // A `>` followed by neither `(` nor `.` is a comparison, at any depth.
    assert ScanStatementRow("a < b && c > d") == "bin[bin[a Less b] And bin[c Greater d]]"
    assert ScanStatementRow("x < y.Z") == "bin[x Less y.Z]"
    assert ScanStatementRow("a < values[0]") == "bin[a Less values[0]]"

    // A ONE-ELEMENT parenthesised group is not a tuple type, so this is a comparison -- the rule
    // Roslyn's `ScanTupleType` also applies, and the reason the scan counts a comma per paren group.
    assert ScanStatementRow("a < (b) > (c)") == "bin[bin[a Less (b)] Greater (c)]"

    // A conditional's `:` is not a tuple element name: a colon is admitted only INSIDE a tuple
    // group, so this stays a comparison against a conditional.
    assert ScanStatementRow("a < (b > c ? c : d)") == "bin[a Less (cond[bin[b Greater c]?c:d])]"

    // THE ONE AMBIGUITY THAT IS A CALL, AND STAYS ONE. `a < b > (c)` has its close followed
    // directly by `(`, so C# reads it as `a<b>(c)` and so does this scan -- unchanged by the
    // widening, and pinned here because widening a scan is only safe if the shapes it must not
    // claim, and the shapes it already claimed, both hold still.
    assert ScanStatementRow("a < b > (c)") == "call[a<b>](c)"
}

test "census PARSE2 scan: the `.`-closed twin reads the same grammar" {
    assert ScanStatementCensus("Dictionary<string, List<int>>.Comparer") == ""
    assert ScanStatementRow("Dictionary<string, List<int>>.Comparer") == "gtype[Dictionary<string, List<int>>].Comparer"
    assert ScanStatementRow("List<(int, string)>.Count") == "gtype[List<(int, string)>].Count"

    // Not a receiver: the close is followed by neither `.` nor `(`.
    assert ScanStatementRow("a < b > c.D") == "bin[bin[a Less b] Greater c.D]"
}

test "census PARSE2 tuple literal: naming is per element" {
    assert ScanStatementCensus("(null, last, IsConstructor: true)") == ""
    assert ScanStatementRow("(null, last, IsConstructor: true)") == "tuple[null, last, IsConstructor: true]"
    assert ScanStatementRow("(Head: 1, 2, 3)") == "tuple[Head: 1, 2, 3]"
    assert ScanStatementRow("(First: 1, 2, Last: 3)") == "tuple[First: 1, 2, Last: 3]"
    assert ScanStatementRow("(1, 2)") == "tuple[1, 2]"
    assert ScanStatementRow("(A: 1, B: 2)") == "tuple[A: 1, B: 2]"

    // A single parenthesised expression is still a parenthesized expression, not a one-element tuple.
    assert ScanStatementRow("(1)") == "(1)"

    // A conditional element keeps its own colon: the name is looked for only after the element
    // expression is complete.
    assert ScanStatementRow("(a, c ? x : y)") == "tuple[a, cond[c?x:y]]"
}

test "census PARSE2 tuple type: naming is per element there too, in a return type and in a local" {
    returnType := "func Test(): (string?, string, IsConstructor: bool) {\n    return (null, last, IsConstructor: true)\n}\n"
    assert PsCensus(returnType) == ""

    // A bare typed LOCAL may be annotated with a tuple type: this was the one declared position
    // whose lookahead admitted only a type starting with an identifier, so the annotation fell
    // through to the expression arm and reported NL101 at the `:`.
    local := "func Test() {\n    pair: (Item: string, Count: int) = value\n}\n"
    assert PsCensus(local) == ""
    assert ScanRow(local) == "value"
}
