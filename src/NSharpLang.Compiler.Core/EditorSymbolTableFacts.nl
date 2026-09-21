namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// WHAT KIND OF THING A NAME IS, in the editor's own vocabulary rather than the protocol's.
//
// This is a WIDER set than the outline's `EditorSymbolKind` and deliberately so: the outline shows
// a record as a class and a union as an enum because an outline has icons and no room for
// argument, while the tables below are what navigation, completion and the hierarchy views read,
// and those must be able to say that a record is a record, a union is a union, and that this
// particular name is a parameter rather than a local. The caller maps these to whatever numbers
// its protocol uses.
enum EditorSymbolTableKind {
    Class,
    Struct,
    Record,
    Interface,
    Enum,
    Union,
    Function,
    Method,
    Property,
    Field,
    Parameter,
    LocalVariable,
    EnumMember,
    Constructor
}

// ONE PARAMETER AS THE EDITOR DESCRIBES IT: the name a caller may write, the type as it was
// SPELLED IN SOURCE, and whether the argument may be left out.
//
// The type is nullable because a parameter's type reference answers `ToString` and `ToString`
// answers a nullable string; a parameter whose type does not spell itself carries nothing here
// rather than a stand-in word.
class EditorSymbolParameterRow {
    nameValue: string
    typeNameValue: string?
    hasDefaultValueValue: bool

    Name: string => nameValue
    TypeName: string? => typeNameValue
    HasDefaultValue: bool => hasDefaultValueValue

    constructor(Name: string, TypeName: string?, HasDefaultValue: bool) {
        nameValue = Name
        typeNameValue = TypeName
        hasDefaultValueValue = HasDefaultValue
    }
}

// ONE ENTRY OF THE FILE'S SYMBOL TABLE: what hover, completion and signature help read when they
// have a name and want to know what it is.
//
// MEMBERS NEST ONE LEVEL, which is the shipped depth. A class carries its methods, properties,
// fields and constructor; a method does not carry its locals, because the table is keyed by name
// and a local's name belongs to the location table instead.
class EditorSymbolInfoRow {
    nameValue: string
    kindValue: EditorSymbolTableKind
    typeNameValue: string?
    documentationValue: string?
    parametersValue: List<EditorSymbolParameterRow>
    membersValue: List<EditorSymbolInfoRow>
    modifiersValue: Modifiers

    Name: string => nameValue
    Kind: EditorSymbolTableKind => kindValue
    TypeName: string? => typeNameValue
    Documentation: string? => documentationValue
    Parameters: List<EditorSymbolParameterRow> => parametersValue
    Members: List<EditorSymbolInfoRow> => membersValue
    Modifiers: Modifiers => modifiersValue

    constructor(Name: string, Kind: EditorSymbolTableKind, TypeName: string?, Documentation: string?, Parameters: List<EditorSymbolParameterRow>, Members: List<EditorSymbolInfoRow>, Modifiers: Modifiers) {
        nameValue = Name
        kindValue = Kind
        typeNameValue = TypeName
        documentationValue = Documentation
        parametersValue = Parameters
        membersValue = Members
        modifiersValue = Modifiers
    }
}

// WHERE A DECLARED NAME SITS, in the editor's own 0-based numbering, ready to be jumped to.
//
// THE COLUMN IS NOT THE DECLARATION'S COLUMN. A declaration's recorded column is where the
// construct begins — the `func`, the `class`, the `case` — and the reader who asked to go to a
// definition wants the cursor on the NAME. So the name is found on the line and its column
// reported, with the declaration's own column as the fallback when the search fails.
class EditorSymbolLocationRow {
    nameValue: string
    kindValue: EditorSymbolTableKind
    lineValue: int
    columnValue: int
    lengthValue: int

    Name: string => nameValue
    Kind: EditorSymbolTableKind => kindValue
    Line: int => lineValue
    Column: int => columnValue
    Length: int => lengthValue

    constructor(Name: string, Kind: EditorSymbolTableKind, Line: int, Column: int, Length: int) {
        nameValue = Name
        kindValue = Kind
        lineValue = Line
        columnValue = Column
        lengthValue = Length
    }
}

// THE THREE TABLES THE EDITOR BUILDS EVERY TIME A FILE CHANGES.
//
// One parse produces three different views of the same declarations, and they are three because
// they answer three different questions:
//
//   * THE TYPE CATALOG names every nominal type in the file as the analyzer's own `TypeInfo`, so
//     the editor and the type checker cannot disagree about what a name means.
//   * THE SYMBOL TABLE describes what a name IS — its kind, its declared type, its documentation
//     comment, its parameters, its modifiers — keyed by name, one level of members deep.
//   * THE LOCATION TABLE says where every declared name SITS, including the names no symbol table
//     entry exists for: parameters, locals, loop variables, tuple elements and catch variables.
//
// THE LOCATION WALK DESCENDS INTO BODIES AND THE SYMBOL WALK DOES NOT, except for local
// functions. That asymmetry is the shipped behaviour and it is not an oversight: go-to-definition
// on a local needs a location, and hover on a local reads the semantic model rather than this
// table.
//
// A LATER DECLARATION WITH THE SAME NAME REPLACES AN EARLIER ONE in the symbol table and JOINS it
// in the location table. Both are consequences of what the two tables are for — one name means one
// thing to hover, while navigation should offer every place the name was declared — and both are
// produced here as ORDERED ROWS so that the caller's dictionaries inherit the order rather than
// inventing one.
class EditorSymbolTableFacts {

    // EVERY NOMINAL TYPE DECLARED AT THE TOP LEVEL OF THE FILE, as the analyzer's `TypeInfo`.
    // Functions are not types and do not appear; neither do soa records, which the shipped catalog
    // has never carried.
    static func TypeCatalog(unit: CompilationUnit?): Dictionary<string, TypeInfo> {
        symbols := new Dictionary<string, TypeInfo>()
        if unit == null {
            return symbols
        }

        for declaration in unit.Declarations {
            classDeclaration := declaration as ClassDeclaration
            if classDeclaration != null {
                symbols[classDeclaration.Name] = NominalTypeInfoFactory.FromClassDeclaration(classDeclaration)
                continue
            }

            structDeclaration := declaration as StructDeclaration
            if structDeclaration != null {
                symbols[structDeclaration.Name] = NominalTypeInfoFactory.FromStructDeclaration(structDeclaration)
                continue
            }

            recordDeclaration := declaration as RecordDeclaration
            if recordDeclaration != null {
                symbols[recordDeclaration.Name] = NominalTypeInfoFactory.FromRecordDeclaration(recordDeclaration)
                continue
            }

            interfaceDeclaration := declaration as InterfaceDeclaration
            if interfaceDeclaration != null {
                symbols[interfaceDeclaration.Name] = NominalTypeInfoFactory.FromInterfaceDeclaration(interfaceDeclaration)
                continue
            }

            enumDeclaration := declaration as EnumDeclaration
            if enumDeclaration != null {
                symbols[enumDeclaration.Name] = EnumTypeInfoFactory.FromDeclaration(enumDeclaration)
                continue
            }

            unionDeclaration := declaration as UnionDeclaration
            if unionDeclaration != null {
                symbols[unionDeclaration.Name] = UnionTypeInfoFactory.FromDeclaration(unionDeclaration)
            }
        }

        return symbols
    }

    // THE SYMBOL TABLE AS THE EDITOR HOLDS IT: one entry per NAME, and the LAST row with a name
    // wins, which is exactly what filling a dictionary in row order does. A name declared twice is
    // therefore described by its second declaration.
    static func SymbolInfoTable(unit: CompilationUnit?, text: string?): Dictionary<string, EditorSymbolInfoRow> {
        table := new Dictionary<string, EditorSymbolInfoRow>()

        for row in SymbolInfoRows(unit, text) {
            table[row.Name] = row
        }

        return table
    }

    // THE LOCATION TABLE AS THE EDITOR HOLDS IT, reduced to the FIRST place each name was
    // declared — the editor keeps every location in a list per name and every consumer of that
    // list asks it for the first one.
    static func SymbolLocationTable(unit: CompilationUnit?, text: string?): Dictionary<string, EditorSymbolLocationRow> {
        table := new Dictionary<string, EditorSymbolLocationRow>()

        for row in SymbolLocationRows(unit, text) {
            if !table.ContainsKey(row.Name) {
                table[row.Name] = row
            }
        }

        return table
    }

    // THE SIX KINDS THAT NAME A TYPE. Everything else a table entry can be — a function, a member,
    // a local — is not something a hierarchy, an outline or a workspace search treats as a type.
    static func IsTypeKind(kind: EditorSymbolTableKind): bool {
        if kind == EditorSymbolTableKind.Class {
            return true
        }

        if kind == EditorSymbolTableKind.Struct {
            return true
        }

        if kind == EditorSymbolTableKind.Record {
            return true
        }

        if kind == EditorSymbolTableKind.Interface {
            return true
        }

        if kind == EditorSymbolTableKind.Enum {
            return true
        }

        if kind == EditorSymbolTableKind.Union {
            return true
        }

        return false
    }

    // THE SYMBOL TABLE, AS ORDERED ROWS. A row that repeats a name is a later declaration of it and
    // the caller's table keeps the LAST, which is what a dictionary filled in this order does.
    //
    // A top-level function's LOCAL FUNCTIONS follow it immediately, at the same level, because a
    // local function is callable by name from where it was declared and completion has always
    // offered them.
    static func SymbolInfoRows(unit: CompilationUnit?, text: string?): List<EditorSymbolInfoRow> {
        rows := new List<EditorSymbolInfoRow>()
        if unit == null {
            return rows
        }

        lines := SourceLines(text)

        for declaration in unit.Declarations {
            functionDeclaration := declaration as FunctionDeclaration
            if functionDeclaration != null {
                rows.Add(FunctionRow(functionDeclaration, EditorSymbolTableKind.Function, lines))
                AppendLocalFunctionRows(rows, functionDeclaration.Body, lines)
                continue
            }

            classDeclaration := declaration as ClassDeclaration
            if classDeclaration != null {
                rows.Add(TypeRow(classDeclaration.Name, EditorSymbolTableKind.Class, null, classDeclaration.Line, classDeclaration.Modifiers, MemberRows(classDeclaration.Name, classDeclaration.Members, lines), lines))
                continue
            }

            structDeclaration := declaration as StructDeclaration
            if structDeclaration != null {
                rows.Add(TypeRow(structDeclaration.Name, EditorSymbolTableKind.Struct, null, structDeclaration.Line, structDeclaration.Modifiers, MemberRows(structDeclaration.Name, structDeclaration.Members, lines), lines))
                continue
            }

            recordDeclaration := declaration as RecordDeclaration
            if recordDeclaration != null {
                rows.Add(TypeRow(recordDeclaration.Name, EditorSymbolTableKind.Record, null, recordDeclaration.Line, recordDeclaration.Modifiers, MemberRows(recordDeclaration.Name, recordDeclaration.Members, lines), lines))
                continue
            }

            soaDeclaration := declaration as SoaRecordDeclaration
            if soaDeclaration != null {
                rows.Add(SoaRecordRow(soaDeclaration, lines))
                continue
            }

            interfaceDeclaration := declaration as InterfaceDeclaration
            if interfaceDeclaration != null {
                rows.Add(TypeRow(interfaceDeclaration.Name, EditorSymbolTableKind.Interface, null, interfaceDeclaration.Line, interfaceDeclaration.Modifiers, MemberRows(interfaceDeclaration.Name, interfaceDeclaration.Members, lines), lines))
                continue
            }

            enumDeclaration := declaration as EnumDeclaration
            if enumDeclaration != null {
                rows.Add(EnumRow(enumDeclaration, lines))
                continue
            }

            unionDeclaration := declaration as UnionDeclaration
            if unionDeclaration != null {
                rows.Add(UnionRow(unionDeclaration, lines))
            }
        }

        return rows
    }

    static func FunctionRow(declaration: FunctionDeclaration, kind: EditorSymbolTableKind, lines: string[]): EditorSymbolInfoRow {
        returnType: string? = null
        if declaration.ReturnType != null {
            returnType = declaration.ReturnType.ToString()
        }

        return new EditorSymbolInfoRow(declaration.Name, kind, returnType, LeadingDocumentation(lines, declaration.Line), ParameterRows(declaration.Parameters), NoMembers(), declaration.Modifiers)
    }

    static func TypeRow(name: string, kind: EditorSymbolTableKind, typeName: string?, oneBasedLine: int, modifiers: Modifiers, members: List<EditorSymbolInfoRow>, lines: string[]): EditorSymbolInfoRow {
        return new EditorSymbolInfoRow(name, kind, typeName, LeadingDocumentation(lines, oneBasedLine), NoParameters(), members, modifiers)
    }

    // A SOA RECORD IS A RECORD WHOSE TYPE NAME IS THE WORD `soa`, and its columns are its fields.
    // The columns carry a spelled type and no documentation, which is what a column is.
    static func SoaRecordRow(declaration: SoaRecordDeclaration, lines: string[]): EditorSymbolInfoRow {
        members := new List<EditorSymbolInfoRow>()
        for column in declaration.Columns {
            members.Add(new EditorSymbolInfoRow(column.Name, EditorSymbolTableKind.Field, column.Type.ToString(), null, NoParameters(), NoMembers(), Modifiers.None))
        }

        return new EditorSymbolInfoRow(declaration.Name, EditorSymbolTableKind.Record, "soa", LeadingDocumentation(lines, declaration.Line), NoParameters(), members, declaration.Modifiers)
    }

    // AN ENUM'S MEMBERS ARE TYPED BY THE ENUM ITSELF, so that completion after the enum's name can
    // say what the member is without resolving anything.
    static func EnumRow(declaration: EnumDeclaration, lines: string[]): EditorSymbolInfoRow {
        members := new List<EditorSymbolInfoRow>()
        for member in declaration.Members {
            members.Add(new EditorSymbolInfoRow(member.Name, EditorSymbolTableKind.EnumMember, declaration.Name, null, NoParameters(), NoMembers(), Modifiers.None))
        }

        return new EditorSymbolInfoRow(declaration.Name, EditorSymbolTableKind.Enum, null, LeadingDocumentation(lines, declaration.Line), NoParameters(), members, declaration.Modifiers)
    }

    // A UNION'S CASES ARE CLASSES typed by the union, because that is what they compile to and
    // what the reader sees when the editor offers one.
    static func UnionRow(declaration: UnionDeclaration, lines: string[]): EditorSymbolInfoRow {
        members := new List<EditorSymbolInfoRow>()
        for unionCase in declaration.Cases {
            members.Add(new EditorSymbolInfoRow(unionCase.Name, EditorSymbolTableKind.Class, declaration.Name, null, NoParameters(), NoMembers(), Modifiers.None))
        }

        return new EditorSymbolInfoRow(declaration.Name, EditorSymbolTableKind.Union, null, LeadingDocumentation(lines, declaration.Line), NoParameters(), members, declaration.Modifiers)
    }

    // THE MEMBERS A TYPE CARRIES: methods, properties, fields and constructors, in source order.
    // A CONSTRUCTOR IS NAMED AFTER ITS TYPE rather than after itself, because that is the name a
    // caller writes after `new`.
    static func MemberRows(ownerName: string, members: List<Declaration>, lines: string[]): List<EditorSymbolInfoRow> {
        rows := new List<EditorSymbolInfoRow>()

        for member in members {
            functionDeclaration := member as FunctionDeclaration
            if functionDeclaration != null {
                rows.Add(FunctionRow(functionDeclaration, EditorSymbolTableKind.Method, lines))
                continue
            }

            propertyDeclaration := member as PropertyDeclaration
            if propertyDeclaration != null {
                rows.Add(new EditorSymbolInfoRow(propertyDeclaration.Name, EditorSymbolTableKind.Property, propertyDeclaration.Type.ToString(), LeadingDocumentation(lines, propertyDeclaration.Line), NoParameters(), NoMembers(), propertyDeclaration.Modifiers))
                continue
            }

            fieldDeclaration := member as FieldDeclaration
            if fieldDeclaration != null {
                fieldType: string? = null
                if fieldDeclaration.Type != null {
                    fieldType = fieldDeclaration.Type.ToString()
                }

                rows.Add(new EditorSymbolInfoRow(fieldDeclaration.Name, EditorSymbolTableKind.Field, fieldType, LeadingDocumentation(lines, fieldDeclaration.Line), NoParameters(), NoMembers(), fieldDeclaration.Modifiers))
                continue
            }

            constructorDeclaration := member as ConstructorDeclaration
            if constructorDeclaration != null {
                rows.Add(new EditorSymbolInfoRow(ownerName, EditorSymbolTableKind.Constructor, null, LeadingDocumentation(lines, constructorDeclaration.Line), ParameterRows(constructorDeclaration.Parameters), NoMembers(), constructorDeclaration.Modifiers))
            }
        }

        return rows
    }

    static func ParameterRows(parameters: List<Parameter>): List<EditorSymbolParameterRow> {
        rows := new List<EditorSymbolParameterRow>()
        for parameter in parameters {
            rows.Add(new EditorSymbolParameterRow(parameter.Name, parameter.Type.ToString(), parameter.DefaultValue != null))
        }

        return rows
    }

    static func NoParameters(): List<EditorSymbolParameterRow> {
        return new List<EditorSymbolParameterRow>()
    }

    static func NoMembers(): List<EditorSymbolInfoRow> {
        return new List<EditorSymbolInfoRow>()
    }

    // LOCAL FUNCTIONS ARE FOUND ANYWHERE IN A BODY, at any nesting, and each one's own body is
    // searched in turn. The statements walked here are exactly the statements that can CONTAIN a
    // declaration: a block, both arms of an `if`, a `for` initialiser and body, the body of a
    // `foreach`, an `await foreach`, a `while` and a `lock`, every part of a `try`, both halves of
    // a `using`, and every statement of every `switch` case.
    static func AppendLocalFunctionRows(rows: List<EditorSymbolInfoRow>, body: BlockStatement?, lines: string[]) {
        if body == null {
            return
        }

        for statement in body.Statements {
            AppendLocalFunctionRowsFrom(rows, statement, lines)
        }
    }

    static func AppendLocalFunctionRowsFrom(rows: List<EditorSymbolInfoRow>, statement: Statement, lines: string[]) {
        localFunction := statement as LocalFunctionStatement
        if localFunction != null {
            rows.Add(FunctionRow(localFunction.Function, EditorSymbolTableKind.Function, lines))
            AppendLocalFunctionRows(rows, localFunction.Function.Body, lines)
            return
        }

        block := statement as BlockStatement
        if block != null {
            for nested in block.Statements {
                AppendLocalFunctionRowsFrom(rows, nested, lines)
            }

            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            AppendLocalFunctionRowsFrom(rows, ifStatement.ThenStatement, lines)
            if ifStatement.ElseStatement != null {
                AppendLocalFunctionRowsFrom(rows, ifStatement.ElseStatement, lines)
            }

            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            if forStatement.Initializer != null {
                AppendLocalFunctionRowsFrom(rows, forStatement.Initializer, lines)
            }

            AppendLocalFunctionRowsFrom(rows, forStatement.Body, lines)
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            AppendLocalFunctionRowsFrom(rows, foreachStatement.Body, lines)
            return
        }

        awaitForeachStatement := statement as AwaitForEachStatement
        if awaitForeachStatement != null {
            AppendLocalFunctionRowsFrom(rows, awaitForeachStatement.Body, lines)
            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            AppendLocalFunctionRowsFrom(rows, whileStatement.Body, lines)
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            AppendLocalFunctionRowsFrom(rows, tryStatement.TryBlock, lines)
            for catchClause in tryStatement.CatchClauses {
                AppendLocalFunctionRowsFrom(rows, catchClause.Block, lines)
            }

            if tryStatement.FinallyBlock != null {
                AppendLocalFunctionRowsFrom(rows, tryStatement.FinallyBlock, lines)
            }

            return
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            if usingStatement.Declaration != null {
                AppendLocalFunctionRowsFrom(rows, usingStatement.Declaration, lines)
            }

            if usingStatement.Body != null {
                AppendLocalFunctionRowsFrom(rows, usingStatement.Body, lines)
            }

            return
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            AppendLocalFunctionRowsFrom(rows, lockStatement.Body, lines)
            return
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            for switchCase in switchStatement.Cases {
                for caseStatement in switchCase.Statements {
                    AppendLocalFunctionRowsFrom(rows, caseStatement, lines)
                }
            }
        }
    }

    // THE LOCATION TABLE, AS ORDERED ROWS. Every row names a DECLARED name, never a use, and the
    // rows for one name arrive in source order so the caller's list for that name is in source
    // order too.
    static func SymbolLocationRows(unit: CompilationUnit?, text: string?): List<EditorSymbolLocationRow> {
        rows := new List<EditorSymbolLocationRow>()
        if unit == null {
            return rows
        }

        lines := SourceLines(text)
        for declaration in unit.Declarations {
            AppendDeclarationLocations(rows, declaration, lines)
        }

        return rows
    }

    // A NAME WITH NOTHING IN IT IS NOT A LOCATION. The `_` of a discarded tuple element is dropped
    // by its own walk rather than here, because `_` is a real name everywhere else.
    static func AddLocation(rows: List<EditorSymbolLocationRow>, name: string, kind: EditorSymbolTableKind, oneBasedLine: int, oneBasedColumn: int, lines: string[], forcedNameColumn: int) {
        if String.IsNullOrWhiteSpace(name) {
            return
        }

        line := oneBasedLine - 1
        if line < 0 {
            line = 0
        }

        column := oneBasedColumn - 1
        if column < 0 {
            column = 0
        }

        nameColumn := forcedNameColumn
        if nameColumn < 0 {
            nameColumn = FindNameColumn(lines, line, column, name)
        }

        rows.Add(new EditorSymbolLocationRow(name, kind, line, nameColumn, name.Length))
    }

    static func AppendDeclarationLocations(rows: List<EditorSymbolLocationRow>, declaration: Declaration, lines: string[]) {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            AddLocation(rows, functionDeclaration.Name, EditorSymbolTableKind.Function, functionDeclaration.Line, functionDeclaration.Column, lines, SearchForName)

            // A PARAMETER HAS NO POSITION OF ITS OWN, so the parameters are found left to right
            // along the function's own line, each search beginning where the last name ended. That
            // is what keeps two parameters of the same name apart, and what keeps a parameter from
            // matching the function's own name.
            functionLine := functionDeclaration.Line - 1
            if functionLine < 0 {
                functionLine = 0
            }

            searchFrom := functionDeclaration.Column - 1
            if searchFrom < 0 {
                searchFrom = 0
            }

            for parameter in functionDeclaration.Parameters {
                column := FindNameColumn(lines, functionLine, searchFrom, parameter.Name)
                AddLocation(rows, parameter.Name, EditorSymbolTableKind.Parameter, functionDeclaration.Line, functionDeclaration.Column, lines, column)
                searchFrom = AdvancePast(lines, functionLine, column, parameter.Name)
            }

            AppendBlockLocations(rows, functionDeclaration.Body, lines)
            return
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            AddLocation(rows, classDeclaration.Name, EditorSymbolTableKind.Class, classDeclaration.Line, classDeclaration.Column, lines, SearchForName)
            for member in classDeclaration.Members {
                AppendDeclarationLocations(rows, member, lines)
            }

            return
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            AddLocation(rows, structDeclaration.Name, EditorSymbolTableKind.Struct, structDeclaration.Line, structDeclaration.Column, lines, SearchForName)
            for member in structDeclaration.Members {
                AppendDeclarationLocations(rows, member, lines)
            }

            return
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            AddLocation(rows, recordDeclaration.Name, EditorSymbolTableKind.Record, recordDeclaration.Line, recordDeclaration.Column, lines, SearchForName)
            for member in recordDeclaration.Members {
                AppendDeclarationLocations(rows, member, lines)
            }

            return
        }

        soaDeclaration := declaration as SoaRecordDeclaration
        if soaDeclaration != null {
            AddLocation(rows, soaDeclaration.Name, EditorSymbolTableKind.Record, soaDeclaration.Line, soaDeclaration.Column, lines, SearchForName)
            for column in soaDeclaration.Columns {
                AddLocation(rows, column.Name, EditorSymbolTableKind.Field, column.Line, column.Column, lines, SearchForName)
            }

            return
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            AddLocation(rows, interfaceDeclaration.Name, EditorSymbolTableKind.Interface, interfaceDeclaration.Line, interfaceDeclaration.Column, lines, SearchForName)
            for member in interfaceDeclaration.Members {
                AppendDeclarationLocations(rows, member, lines)
            }

            return
        }

        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            AddLocation(rows, enumDeclaration.Name, EditorSymbolTableKind.Enum, enumDeclaration.Line, enumDeclaration.Column, lines, SearchForName)
            return
        }

        unionDeclaration := declaration as UnionDeclaration
        if unionDeclaration != null {
            AddLocation(rows, unionDeclaration.Name, EditorSymbolTableKind.Union, unionDeclaration.Line, unionDeclaration.Column, lines, SearchForName)
            return
        }

        // A TYPE ALIAS NAVIGATES AS A CLASS, because the thing a reader jumps to is a type.
        typeAliasDeclaration := declaration as TypeAliasDeclaration
        if typeAliasDeclaration != null {
            AddLocation(rows, typeAliasDeclaration.Name, EditorSymbolTableKind.Class, typeAliasDeclaration.Line, typeAliasDeclaration.Column, lines, SearchForName)
            return
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            AddLocation(rows, propertyDeclaration.Name, EditorSymbolTableKind.Property, propertyDeclaration.Line, propertyDeclaration.Column, lines, SearchForName)
            return
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            AddLocation(rows, fieldDeclaration.Name, EditorSymbolTableKind.Field, fieldDeclaration.Line, fieldDeclaration.Column, lines, SearchForName)
        }
    }

    static func AppendBlockLocations(rows: List<EditorSymbolLocationRow>, block: BlockStatement?, lines: string[]) {
        if block == null {
            return
        }

        for statement in block.Statements {
            AppendStatementLocations(rows, statement, lines)
        }
    }

    static func AppendStatementLocations(rows: List<EditorSymbolLocationRow>, statement: Statement, lines: string[]) {
        block := statement as BlockStatement
        if block != null {
            AppendBlockLocations(rows, block, lines)
            return
        }

        // A BINDING'S OWN COLUMN IS ITS NAME'S COLUMN — the construct starts at the name — so this
        // is the one location that is never searched for.
        variableDeclaration := statement as VariableDeclarationStatement
        if variableDeclaration != null {
            column := variableDeclaration.Column - 1
            if column < 0 {
                column = 0
            }

            AddLocation(rows, variableDeclaration.Name, EditorSymbolTableKind.LocalVariable, variableDeclaration.Line, variableDeclaration.Column, lines, column)
            return
        }

        tupleDeconstruction := statement as TupleDeconstructionStatement
        if tupleDeconstruction != null {
            line := tupleDeconstruction.Line - 1
            if line < 0 {
                line = 0
            }

            searchFrom := tupleDeconstruction.Column - 1
            if searchFrom < 0 {
                searchFrom = 0
            }

            for name in tupleDeconstruction.Names {
                if String.Equals(name, "_", StringComparison.Ordinal) {
                    continue
                }

                column := FindNameColumn(lines, line, searchFrom, name)
                AddLocation(rows, name, EditorSymbolTableKind.LocalVariable, tupleDeconstruction.Line, tupleDeconstruction.Column, lines, column)
                searchFrom = AdvancePast(lines, line, column, name)
            }

            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            line := foreachStatement.Line - 1
            if line < 0 {
                line = 0
            }

            searchFrom := foreachStatement.Column - 1
            if searchFrom < 0 {
                searchFrom = 0
            }

            column := FindNameColumn(lines, line, searchFrom, foreachStatement.VariableName)
            AddLocation(rows, foreachStatement.VariableName, EditorSymbolTableKind.LocalVariable, foreachStatement.Line, foreachStatement.Column, lines, column)
            AppendStatementLocations(rows, foreachStatement.Body, lines)
            return
        }

        awaitForeachStatement := statement as AwaitForEachStatement
        if awaitForeachStatement != null {
            line := awaitForeachStatement.Line - 1
            if line < 0 {
                line = 0
            }

            searchFrom := awaitForeachStatement.Column - 1
            if searchFrom < 0 {
                searchFrom = 0
            }

            column := FindNameColumn(lines, line, searchFrom, awaitForeachStatement.VariableName)
            AddLocation(rows, awaitForeachStatement.VariableName, EditorSymbolTableKind.LocalVariable, awaitForeachStatement.Line, awaitForeachStatement.Column, lines, column)
            AppendStatementLocations(rows, awaitForeachStatement.Body, lines)
            return
        }

        localFunction := statement as LocalFunctionStatement
        if localFunction != null {
            AddLocation(rows, localFunction.Function.Name, EditorSymbolTableKind.Function, localFunction.Function.Line, localFunction.Function.Column, lines, SearchForName)
            AppendBlockLocations(rows, localFunction.Function.Body, lines)
            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            AppendStatementLocations(rows, ifStatement.ThenStatement, lines)
            if ifStatement.ElseStatement != null {
                AppendStatementLocations(rows, ifStatement.ElseStatement, lines)
            }

            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            if forStatement.Initializer != null {
                AppendStatementLocations(rows, forStatement.Initializer, lines)
            }

            AppendStatementLocations(rows, forStatement.Body, lines)
            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            AppendStatementLocations(rows, whileStatement.Body, lines)
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            AppendBlockLocations(rows, tryStatement.TryBlock, lines)
            for catchClause in tryStatement.CatchClauses {
                AppendCatchVariableLocation(rows, catchClause, lines)
                AppendBlockLocations(rows, catchClause.Block, lines)
            }

            if tryStatement.FinallyBlock != null {
                AppendBlockLocations(rows, tryStatement.FinallyBlock, lines)
            }

            return
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            if usingStatement.Declaration != null {
                AppendStatementLocations(rows, usingStatement.Declaration, lines)
            }

            if usingStatement.Body != null {
                AppendStatementLocations(rows, usingStatement.Body, lines)
            }

            return
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            AppendBlockLocations(rows, lockStatement.Body, lines)
            return
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            for switchCase in switchStatement.Cases {
                for caseStatement in switchCase.Statements {
                    AppendStatementLocations(rows, caseStatement, lines)
                }
            }
        }
    }

    // A CATCH CLAUSE HAS NO POSITION, only its block does, so the variable is looked for on the
    // line ABOVE the block's first line — which is where `} catch (ex: Exception) {` is written.
    // A block that begins on line one has no line above it and is searched on its own.
    static func AppendCatchVariableLocation(rows: List<EditorSymbolLocationRow>, catchClause: CatchClause, lines: string[]) {
        if String.IsNullOrEmpty(catchClause.VariableName) || catchClause.Block.Line <= 0 {
            return
        }

        catchLine := catchClause.Block.Line - 1
        if catchLine < 0 {
            catchLine = 0
        }

        searchLine := catchLine
        reportedLine := catchClause.Block.Line
        if catchLine > 0 {
            searchLine = catchLine - 1
            reportedLine = catchLine
        }

        column := FindNameColumn(lines, searchLine, 0, catchClause.VariableName)
        AddLocation(rows, catchClause.VariableName, EditorSymbolTableKind.LocalVariable, reportedLine, catchClause.Block.Column, lines, column)
    }

    // THE SEARCH RESUMES AFTER THE NAME THAT WAS JUST FOUND, and never past the end of the line.
    static func AdvancePast(lines: string[], line: int, column: int, name: string): int {
        lineLength := 0
        if line >= 0 && line < lines.Length {
            lineLength = lines[line].Length
        }

        next := column + name.Length
        if next > lineLength {
            return lineLength
        }

        return next
    }

    // WHERE A NAME SITS ON A LINE. The search starts where the caller says and falls back to the
    // whole line, because a declaration's recorded column is sometimes AFTER its own name — a
    // parameter list wraps, an attribute precedes it. When the name is nowhere on the line at all
    // the caller's own column stands.
    static func FindNameColumn(lines: string[], line: int, startColumn: int, name: string): int {
        fallback := startColumn
        if fallback < 0 {
            fallback = 0
        }

        if line < 0 || line >= lines.Length {
            return fallback
        }

        lineText := lines[line]
        if String.IsNullOrEmpty(lineText) {
            return fallback
        }

        start := startColumn
        if start < 0 {
            start = 0
        }

        if start > lineText.Length {
            start = lineText.Length
        }

        index := lineText.IndexOf(name, start, StringComparison.Ordinal)
        if index < 0 && start > 0 {
            index = lineText.IndexOf(name, StringComparison.Ordinal)
        }

        if index >= 0 {
            return index
        }

        return fallback
    }

    // THE COMMENT BLOCK IMMEDIATELY ABOVE A DECLARATION, as the reader wrote it.
    //
    // Walking UPWARDS from the line before the declaration: `///` and `//` lines join the block,
    // BLANK LINES ARE SKIPPED ONLY BEFORE THE BLOCK HAS STARTED — a blank line inside a run of
    // comments ends it — and anything else stops the walk. The marker and the surrounding space are
    // removed from each line; the lines keep their order and their internal blank lines.
    static func LeadingDocumentation(lines: string[], declarationLine: int): string? {
        if declarationLine <= 1 {
            return null
        }

        startIndex := declarationLine - 2
        if startIndex > lines.Length - 1 {
            startIndex = lines.Length - 1
        }

        commentLines := new List<string>()
        index := startIndex
        while index >= 0 {
            trimmed := lines[index].Trim()
            if trimmed.StartsWith("///", StringComparison.Ordinal) {
                commentLines.Insert(0, trimmed.Substring(3).Trim())
            } else if trimmed.StartsWith("//", StringComparison.Ordinal) {
                commentLines.Insert(0, trimmed.Substring(2).Trim())
            } else if String.IsNullOrWhiteSpace(trimmed) && commentLines.Count == 0 {
                index = index - 1
                continue
            } else {
                break
            }

            index = index - 1
        }

        if commentLines.Count == 0 {
            return null
        }

        return String.Join("\n", commentLines).Trim()
    }

    // THE FILE'S LINES, SPLIT ON `\n` AND NOT TRIMMED. A trailing `\r` is part of the line here
    // because every column this owner reports is an index into the line as the editor holds it,
    // and the editor counts that carriage return.
    static func SourceLines(text: string?): string[] {
        if text == null {
            return new string[0]
        }

        return text.Split('\n')
    }

    // The forced-column sentinel: "no column was handed down, go and find the name".
    static SearchForName: int => -1
}
