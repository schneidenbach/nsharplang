namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// ONE PIECE OF GHOST TEXT, in the editor's own 0-based numbering. The label already carries the
// `: ` that makes it read as an annotation; nothing about the protocol's hint kind or padding is
// decided here, because those are the same for every hint this owner produces.
class EditorInlayHintRow {
    lineValue: int
    characterValue: int
    labelValue: string

    Line: int => lineValue
    Character: int => characterValue
    Label: string => labelValue

    constructor(Line: int, Character: int, Label: string) {
        lineValue = Line
        characterValue = Character
        labelValue = Label
    }
}

// WHERE THE EDITOR SHOWS AN INFERRED TYPE, and what it says.
//
// ONLY AN INFERRED BINDING GETS A HINT. A declaration that already writes its type down is left
// alone — the hint exists to say what `:=` decided, and repeating an annotation the reader can
// already see is noise. A binding the bound model cannot name gets nothing rather than a guess.
//
// THE POSITION OF A LOOP VARIABLE IS COUNTED FROM THE KEYWORD, not looked up in the source. The
// parser records where `foreach` begins and not where the variable does, so the hint is placed at
// the keyword's column plus the keyword's own width plus the variable's length. A file that wrote
// extra spaces after `foreach` therefore gets its hint a little early; that is the shipped answer,
// and the rows below pin it so it cannot drift without someone saying so.
class EditorInlayHintFacts {
    static ForeachKeyword: string => "foreach "
    static AwaitForeachKeyword: string => "await foreach "

    // Every hint for the lines the editor can see, in source order. `startLine` and `endLine` are
    // the visible range's own 0-based lines, both inclusive.
    static func HintRows(unit: CompilationUnit?, semanticModel: SemanticModel?, startLine: int, endLine: int): List<EditorInlayHintRow> {
        rows := new List<EditorInlayHintRow>()
        if unit == null || semanticModel == null {
            return rows
        }

        for declaration in unit.Declarations {
            AppendFromDeclaration(declaration, semanticModel, startLine, endLine, rows)
        }

        return rows
    }

    // A HINT LIVES IN A BODY, so the declaration walk exists only to reach one. A class, a struct
    // and a record are descended into; an interface and an enum have no bodies to descend into.
    static func AppendFromDeclaration(declaration: Declaration, semanticModel: SemanticModel, startLine: int, endLine: int, rows: List<EditorInlayHintRow>) {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            if functionDeclaration.Body != null {
                AppendFromStatement(functionDeclaration.Body, semanticModel, startLine, endLine, rows)
            }

            return
        }

        members: List<Declaration>? = null
        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            members = classDeclaration.Members
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            members = structDeclaration.Members
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            members = recordDeclaration.Members
        }

        if members != null {
            for member in members {
                AppendFromDeclaration(member, semanticModel, startLine, endLine, rows)
            }
        }
    }

    static func AppendFromStatement(statement: Statement?, semanticModel: SemanticModel, startLine: int, endLine: int, rows: List<EditorInlayHintRow>) {
        if statement == null {
            return
        }

        block := statement as BlockStatement
        if block != null {
            for inner in block.Statements {
                AppendFromStatement(inner, semanticModel, startLine, endLine, rows)
            }

            return
        }

        variableDeclaration := statement as VariableDeclarationStatement
        if variableDeclaration != null {
            AppendVariableRow(variableDeclaration, semanticModel, startLine, endLine, rows)
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            AppendLoopRow(foreachStatement.VariableName, foreachStatement.Line, foreachStatement.Column, ForeachKeyword, semanticModel, startLine, endLine, rows)
            AppendFromStatement(foreachStatement.Body, semanticModel, startLine, endLine, rows)
            return
        }

        awaitForeachStatement := statement as AwaitForEachStatement
        if awaitForeachStatement != null {
            AppendLoopRow(awaitForeachStatement.VariableName, awaitForeachStatement.Line, awaitForeachStatement.Column, AwaitForeachKeyword, semanticModel, startLine, endLine, rows)
            AppendFromStatement(awaitForeachStatement.Body, semanticModel, startLine, endLine, rows)
            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            AppendFromStatement(ifStatement.ThenStatement, semanticModel, startLine, endLine, rows)
            if ifStatement.ElseStatement != null {
                AppendFromStatement(ifStatement.ElseStatement, semanticModel, startLine, endLine, rows)
            }

            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            AppendFromStatement(whileStatement.Body, semanticModel, startLine, endLine, rows)
            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            if forStatement.Initializer != null {
                AppendFromStatement(forStatement.Initializer, semanticModel, startLine, endLine, rows)
            }

            AppendFromStatement(forStatement.Body, semanticModel, startLine, endLine, rows)
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            AppendFromStatement(tryStatement.TryBlock, semanticModel, startLine, endLine, rows)
            for catchClause in tryStatement.CatchClauses {
                AppendFromStatement(catchClause.Block, semanticModel, startLine, endLine, rows)
            }

            if tryStatement.FinallyBlock != null {
                AppendFromStatement(tryStatement.FinallyBlock, semanticModel, startLine, endLine, rows)
            }

            return
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            if usingStatement.Declaration != null {
                AppendVariableRow(usingStatement.Declaration, semanticModel, startLine, endLine, rows)
            }

            if usingStatement.Body != null {
                AppendFromStatement(usingStatement.Body, semanticModel, startLine, endLine, rows)
            }

            return
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            AppendFromStatement(lockStatement.Body, semanticModel, startLine, endLine, rows)
            return
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            for switchCase in switchStatement.Cases {
                for inner in switchCase.Statements {
                    AppendFromStatement(inner, semanticModel, startLine, endLine, rows)
                }
            }

            return
        }

        localFunction := statement as LocalFunctionStatement
        if localFunction != null && localFunction.Function.Body != null {
            AppendFromStatement(localFunction.Function.Body, semanticModel, startLine, endLine, rows)
        }
    }

    // AN ANNOTATED BINDING IS NOT HINTED, and neither is one with nothing on the right to infer
    // from. The hint sits immediately after the name, where an annotation would have been written.
    static func AppendVariableRow(statement: VariableDeclarationStatement, semanticModel: SemanticModel, startLine: int, endLine: int, rows: List<EditorInlayHintRow>) {
        if statement.Type != null || statement.Initializer == null {
            return
        }

        line := statement.Line - 1
        if line < startLine || line > endLine {
            return
        }

        label := HintLabel(semanticModel, statement.Name)
        if label == null {
            return
        }

        rows.Add(new EditorInlayHintRow(line, statement.Column - 1 + statement.Name.Length, label))
    }

    static func AppendLoopRow(variableName: string, oneBasedLine: int, oneBasedColumn: int, keyword: string, semanticModel: SemanticModel, startLine: int, endLine: int, rows: List<EditorInlayHintRow>) {
        line := oneBasedLine - 1
        if line < startLine || line > endLine {
            return
        }

        label := HintLabel(semanticModel, variableName)
        if label == null {
            return
        }

        rows.Add(new EditorInlayHintRow(line, oneBasedColumn - 1 + keyword.Length + variableName.Length, label))
    }

    // NULL MEANS "SAY NOTHING". A name the bound model never resolved, and a resolved type whose
    // display text comes back empty, both produce no hint at all.
    static func HintLabel(semanticModel: SemanticModel, name: string): string? {
        resolved := semanticModel.LookupIdentifier(name)
        if resolved == null {
            return null
        }

        text := TypeHintText(resolved)
        if text == null || text.Length == 0 {
            return null
        }

        return ": " + text
    }

    // THE DISPLAY TEXT OF A BOUND TYPE, and the reason this returns `string?`.
    //
    // Every arm but the last names a type whose spelling is known. The LAST arm is `ToString` on a
    // `TypeInfo` the arms above did not recognise, and `object.ToString` is allowed to answer null
    // — so the honest return type is nullable and the caller above treats null the same way it
    // treats an empty string: no hint. The C# this came from declared a non-null `string` and
    // returned that same expression, which the compiler flagged and nothing enforced.
    static func TypeHintText(typeInfo: TypeInfo): string? {
        simple := typeInfo as SimpleTypeInfo
        if simple != null {
            return simple.Name
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            return generic.ToString()
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            return array.ToString()
        }

        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return nullable.ToString()
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            return TupleHintText(tuple)
        }

        classType := typeInfo as ClassTypeInfo
        if classType != null {
            return classType.Name
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            return structType.Name
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return recordType.Name
        }

        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }

        enumType := typeInfo as EnumTypeInfo
        if enumType != null {
            return enumType.Declaration.Name
        }

        unionType := typeInfo as UnionTypeInfo
        if unionType != null {
            return unionType.Declaration.Name
        }

        reflectionType := typeInfo as ReflectionTypeInfo
        if reflectionType != null {
            return ReflectionHintText(reflectionType.Type)
        }

        externalType := typeInfo as ExternalTypeInfo
        if externalType != null {
            return externalType.Name
        }

        return typeInfo.ToString()
    }

    // A TUPLE READS AS ITS ELEMENTS, and a named element carries its name. An element whose own
    // type has no display text contributes an empty slot rather than dropping the comma, because
    // the reader is being shown the SHAPE and a tuple with a hole is still that shape.
    static func TupleHintText(tuple: TupleTypeInfo): string {
        builder := new StringBuilder()
        builder.Append("(")

        index := 0
        while index < tuple.Elements.Count {
            if index > 0 {
                builder.Append(", ")
            }

            element := tuple.Elements[index]
            if element.Name != null {
                builder.Append(element.Name)
                builder.Append(": ")
            }

            builder.Append(TypeHintText(element.Type))
            index = index + 1
        }

        builder.Append(")")
        return builder.ToString()
    }

    // A CLR TYPE READS IN N#'s OWN WORDS. `Int32` is `int` to someone writing N#, and a generic
    // is written with its arguments rather than with the arity mark the runtime uses.
    static func ReflectionHintText(clrType: Type): string {
        typeName := clrType.Name
        if clrType.IsGenericType {
            arguments := clrType.GetGenericArguments()
            builder := new StringBuilder()
            builder.Append(typeName.Substring(0, typeName.IndexOf("`", StringComparison.Ordinal)))
            builder.Append("<")

            index := 0
            while index < arguments.Length {
                if index > 0 {
                    builder.Append(", ")
                }

                builder.Append(ReflectionHintText(arguments[index]))
                index = index + 1
            }

            builder.Append(">")
            return builder.ToString()
        }

        if typeName == "Int32" {
            return "int"
        }

        if typeName == "Int64" {
            return "long"
        }

        if typeName == "Single" {
            return "float"
        }

        if typeName == "Double" {
            return "double"
        }

        if typeName == "Boolean" {
            return "bool"
        }

        if typeName == "String" {
            return "string"
        }

        if typeName == "Void" {
            return "void"
        }

        if typeName == "Object" {
            return "object"
        }

        return typeName
    }
}
