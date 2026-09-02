namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE DECLARATION PROJECTORS (task 019 slice 14).
//
// Both projectors were PRIVATE instance methods on `CodeIntelligenceService`, so the only way to
// ask them anything was to load a project, run an analysis and read the far end of a JSON
// rendering. Every assertion below was previously reachable only that way, and SEVEN of them were
// not reachable at all.
//
// SEVEN THINGS THAT WERE UNREACHABLE, PROSE OR VACUOUS ARE STATED HERE AS CONTRACTS:
//   (a) THE TWO PROJECTIONS DISAGREE ABOUT CHILDREN ON PURPOSE. `query symbols` filters a type's
//       members by the EXPORTED convention; `query outline` shows every member. A lowercase method
//       is absent from one answer and present in the other, from the same declaration.
//   (b) A STATIC FIELD IS A `Field` AND AN INSTANCE FIELD IS A `Property` — in the SYMBOL answer
//       only. The outline calls both a `Property`. The C# spelled the split `HasFlag(Static)`.
//   (c) `Members` IS AN EMPTY ARRAY FOR A CHILDLESS TYPE AND NULL FOR A FUNCTION. Every JSON
//       consumer sees the difference between `[]` and absent.
//   (d) A CONSTRUCTOR'S PARAMETERS CARRY THE `HasDefault` FLAG BUT NEVER THE DEFAULT TEXT, while a
//       function's carry both. One `null` in one arm was the entire record of that.
//   (e) A DEFAULT VALUE'S TEXT IS ITS AST NODE'S RUNTIME TYPE NAME, not the source spelling. That
//       is what ships, and it is preserved rather than fixed.
//   (f) AN ENUM AND A UNION LIST THEIR MEMBERS IN THE SYMBOL ANSWER AND HAVE NO CHILDREN IN THE
//       OUTLINE, and a union's cases are filtered by the EXPORTED convention with no modifiers of
//       their own — so a lowercase case is invisible to `query symbols`.
//   (g) AN ENUM MEMBER IS REPORTED AT LINE 0, COLUMN 0 even though its AST node carries a position.
func CidpAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func CidpSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func CidpFunction(name: string, modifiers: Modifiers, line: int): FunctionDeclaration {
    return new FunctionDeclaration(
        name,
        new List<Parameter>(),
        CidpSimple("int"),
        null,
        null,
        null,
        null,
        modifiers,
        CidpAttributes(),
        false,
        null,
        false,
        false,
        line,
        3
    )
}

func CidpFunctionWithParameters(name: string, parameters: List<Parameter>): FunctionDeclaration {
    return new FunctionDeclaration(
        name,
        parameters,
        null,
        null,
        null,
        null,
        null,
        Modifiers.Public,
        CidpAttributes(),
        false,
        null,
        false,
        false,
        4,
        2
    )
}

func CidpClass(name: string, members: List<Declaration>, modifiers: Modifiers): ClassDeclaration {
    return new ClassDeclaration(
        name,
        null,
        null,
        new List<TypeReference>(),
        members,
        null,
        modifiers,
        CidpAttributes(),
        7,
        1
    )
}

func CidpField(name: string, modifiers: Modifiers): FieldDeclaration {
    return new FieldDeclaration(
        name,
        CidpSimple("string"),
        null,
        modifiers,
        PropertyModifier.None,
        CidpAttributes(),
        11,
        5
    )
}

func CidpParameter(name: string, defaultValue: Expression?): Parameter {
    return new Parameter(name, CidpSimple("int"), defaultValue, false)
}

func CidpChipCount(symbol: SymbolResult): int {
    if symbol.Modifiers == null {
        return -1
    }

    return symbol.Modifiers.Length
}

func CidpMemberNames(symbol: SymbolResult): string {
    if symbol.Members == null {
        return "<null>"
    }

    joined := ""
    index := 0
    while index < symbol.Members.Length {
        if index > 0 {
            joined = joined + ","
        }

        joined = joined + symbol.Members[index].Name
        index = index + 1
    }

    return joined
}

func CidpOutlineNames(entry: OutlineEntry): string {
    if entry.Children == null {
        return "<null>"
    }

    joined := ""
    index := 0
    while index < entry.Children.Length {
        if index > 0 {
            joined = joined + ","
        }

        joined = joined + entry.Children[index].Name
        index = index + 1
    }

    return joined
}

test "a function projects its name, position, return type and chips" {
    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpFunction("Draw", Modifiers.Public, 9),
        "Shapes.nl"
    )
    assert symbol != null
    assert symbol.Name == "Draw"
    assert symbol.Kind == SymbolKind.Function
    assert symbol.File == "Shapes.nl"
    assert symbol.Line == 9
    assert symbol.Column == 3
    assert symbol.TypeName == "int"
    assert CidpChipCount(symbol) == 1
}

test "(c) a function's Members is NULL and a childless type's is an EMPTY ARRAY" {
    functionSymbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpFunction("Draw", Modifiers.Public, 9),
        "Shapes.nl"
    )
    assert functionSymbol.Members == null

    classSymbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpClass("Widget", new List<Declaration>(), Modifiers.Public),
        "Shapes.nl"
    )
    assert classSymbol.Members != null
    assert classSymbol.Members.Length == 0
}

test "(a) THE SYMBOL ANSWER FILTERS A TYPE'S MEMBERS AND THE OUTLINE DOES NOT" {
    members := new List<Declaration>()
    members.Add(CidpFunction("Draw", Modifiers.None, 8))
    members.Add(CidpFunction("hidden", Modifiers.None, 9))

    declaration := CidpClass("Widget", members, Modifiers.Public)

    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(declaration, "Shapes.nl")
    assert CidpMemberNames(symbol) == "Draw"

    entry := CodeIntelligenceDeclarationProjection.OutlineFor(declaration)
    assert CidpOutlineNames(entry) == "Draw,hidden"
}

test "(a) the same disagreement at FILE level: Symbols filters, OutlineEntries does not" {
    declarations := new List<Declaration>()
    declarations.Add(CidpFunction("Draw", Modifiers.None, 3))
    declarations.Add(CidpFunction("helper", Modifiers.None, 5))

    symbols := CodeIntelligenceDeclarationProjection.Symbols(declarations, "Shapes.nl")
    assert symbols.Count == 1
    assert symbols[0].Name == "Draw"

    entries := CodeIntelligenceDeclarationProjection.OutlineEntries(declarations)
    assert entries.Length == 2
    assert entries[0].Name == "Draw"
    assert entries[1].Name == "helper"
}

test "(b) A STATIC FIELD IS A Field AND AN INSTANCE FIELD IS A Property — IN THE SYMBOL ANSWER" {
    staticSymbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpField("Count", Modifiers.Public | Modifiers.Static),
        "Shapes.nl"
    )
    assert staticSymbol.Kind == SymbolKind.Field

    instanceSymbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpField("Count", Modifiers.Public),
        "Shapes.nl"
    )
    assert instanceSymbol.Kind == SymbolKind.Property
}

test "(b) THE OUTLINE CALLS BOTH FIELDS A Property, AND CARRIES THE TYPE INSTEAD OF THE CHIPS" {
    staticEntry := CodeIntelligenceDeclarationProjection.OutlineFor(
        CidpField("Count", Modifiers.Public | Modifiers.Static)
    )
    instanceEntry := CodeIntelligenceDeclarationProjection.OutlineFor(
        CidpField("Count", Modifiers.Public)
    )

    assert staticEntry.Kind == SymbolKind.Property
    assert instanceEntry.Kind == SymbolKind.Property
    assert staticEntry.TypeName == "string"
    assert staticEntry.ReturnType == null
    // A field's outline entry begins and ends on its own line.
    assert staticEntry.Line == 11
    assert staticEntry.EndLine == 11
}

test "(d) A CONSTRUCTOR'S PARAMETERS CARRY THE FLAG BUT NEVER THE DEFAULT TEXT" {
    parameters := new List<Parameter>()
    parameters.Add(CidpParameter("count", new IntLiteralExpression("3", 1, 1)))

    functionSymbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpFunctionWithParameters("Draw", parameters),
        "Shapes.nl"
    )
    assert functionSymbol.Parameters.Length == 1
    assert functionSymbol.Parameters[0].Name == "count"
    assert functionSymbol.Parameters[0].Type == "int"
    assert functionSymbol.Parameters[0].HasDefault
    assert functionSymbol.Parameters[0].DefaultValue != null

    constructorDeclaration := new ConstructorDeclaration(
        parameters,
        new BlockStatement(new List<Statement>(), 1, 1),
        null,
        Modifiers.Public,
        CidpAttributes(),
        6,
        4
    )
    constructorSymbol := CodeIntelligenceDeclarationProjection.SymbolFor(constructorDeclaration, "Shapes.nl")
    assert constructorSymbol.Name == "constructor"
    assert constructorSymbol.Kind == SymbolKind.Constructor
    assert constructorSymbol.Parameters.Length == 1
    assert constructorSymbol.Parameters[0].HasDefault
    assert constructorSymbol.Parameters[0].DefaultValue == null
}

test "(e) A DEFAULT VALUE'S TEXT IS ITS AST NODE'S RUNTIME TYPE NAME" {
    literal := new IntLiteralExpression("3", 1, 1)
    assert CodeIntelligenceDeclarationProjection.DefaultValueText(literal) == "NSharpLang.Compiler.Ast.IntLiteralExpression"

    parameters := new List<Parameter>()
    parameters.Add(CidpParameter("count", literal))
    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpFunctionWithParameters("Draw", parameters),
        "Shapes.nl"
    )
    assert symbol.Parameters[0].DefaultValue == "NSharpLang.Compiler.Ast.IntLiteralExpression"
}

test "a parameter with no default carries neither the flag nor the text" {
    parameters := new List<Parameter>()
    parameters.Add(CidpParameter("count", null))
    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpFunctionWithParameters("Draw", parameters),
        "Shapes.nl"
    )
    assert symbol.Parameters[0].HasDefault == false
    assert symbol.Parameters[0].DefaultValue == null
}

test "(f)(g) AN ENUM LISTS ITS MEMBERS AT LINE 0 IN THE SYMBOL ANSWER AND HAS NO OUTLINE CHILDREN" {
    members := new List<EnumMember>()
    members.Add(new EnumMember("Red", null, 12, 5))
    members.Add(new EnumMember("Green", null, 13, 5))

    declaration := new EnumDeclaration(
        "Colour",
        members,
        EnumType.Int,
        Modifiers.Public,
        CidpAttributes(),
        11,
        1
    )

    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(declaration, "Shapes.nl")
    assert symbol.Kind == SymbolKind.Enum
    assert CidpMemberNames(symbol) == "Red,Green"
    assert symbol.Members[0].Kind == SymbolKind.EnumMember
    assert symbol.Members[0].Line == 0
    assert symbol.Members[0].Column == 0

    entry := CodeIntelligenceDeclarationProjection.OutlineFor(declaration)
    assert entry.Kind == SymbolKind.Enum
    assert entry.Children == null
    assert entry.Line == 11
    assert entry.EndLine == 11
}

test "(f) A UNION'S CASES ARE FILTERED BY THE EXPORTED CONVENTION, AND ITS OUTLINE HAS NO CHILDREN" {
    cases := new List<UnionCase>()
    cases.Add(new UnionCase("Circle", null, 15, 5))
    cases.Add(new UnionCase("square", null, 16, 5))

    declaration := new UnionDeclaration(
        "Shape",
        null,
        cases,
        Modifiers.Public,
        CidpAttributes(),
        14,
        1
    )

    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(declaration, "Shapes.nl")
    assert symbol.Kind == SymbolKind.Union
    assert CidpMemberNames(symbol) == "Circle"

    entry := CodeIntelligenceDeclarationProjection.OutlineFor(declaration)
    assert entry.Kind == SymbolKind.Union
    assert entry.Children == null
}

test "a soa record carries the type name 'soa' in BOTH answers and its columns are fields" {
    columns := new List<SoaColumnDeclaration>()
    columns.Add(new SoaColumnDeclaration("X", CidpSimple("float"), 21, 5))

    declaration := new SoaRecordDeclaration(
        "Points",
        columns,
        Modifiers.Public,
        CidpAttributes(),
        20,
        1
    )

    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(declaration, "Shapes.nl")
    assert symbol.Kind == SymbolKind.Record
    assert symbol.TypeName == "soa"
    assert symbol.Members.Length == 1
    assert symbol.Members[0].Kind == SymbolKind.Field
    assert symbol.Members[0].TypeName == "float"
    // A column keeps its OWN position, unlike an enum member.
    assert symbol.Members[0].Line == 21

    entry := CodeIntelligenceDeclarationProjection.OutlineFor(declaration)
    assert entry.TypeName == "soa"
    assert entry.Children.Length == 1
    assert entry.Children[0].Kind == SymbolKind.Field
    assert entry.Children[0].TypeName == "float"
}

test "an alias, a newtype and a test carry NO modifier chips at all" {
    aliasDeclaration := new TypeAliasDeclaration("Id", CidpSimple("int"), 30, 1)
    aliasSymbol := CodeIntelligenceDeclarationProjection.SymbolFor(aliasDeclaration, "Shapes.nl")
    assert aliasSymbol.Kind == SymbolKind.TypeAlias
    assert aliasSymbol.TypeName == "int"
    assert aliasSymbol.Modifiers == null

    newtypeDeclaration := new NewtypeDeclaration("Metres", CidpSimple("float"), 31, 1)
    newtypeSymbol := CodeIntelligenceDeclarationProjection.SymbolFor(newtypeDeclaration, "Shapes.nl")
    // A newtype is reported as a STRUCT, named by its underlying type.
    assert newtypeSymbol.Kind == SymbolKind.Struct
    assert newtypeSymbol.TypeName == "float"
    assert newtypeSymbol.Modifiers == null
}

test "a test declaration is named by its DESCRIPTION in both answers" {
    declaration := new TestDeclaration(
        "it draws",
        new BlockStatement(new List<Statement>(), 1, 1),
        null,
        null,
        null,
        40,
        1
    )

    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(declaration, "Shapes.nl")
    assert symbol.Name == "it draws"
    assert symbol.Kind == SymbolKind.Test

    entry := CodeIntelligenceDeclarationProjection.OutlineFor(declaration)
    assert entry.Name == "it draws"
    assert entry.Kind == SymbolKind.Test
    assert entry.EndLine == 40
}

test "a declaration neither projection names answers null" {
    directive := new PreprocessorDeclaration("#if DEBUG", 50, 1)
    assert CodeIntelligenceDeclarationProjection.SymbolFor(directive, "Shapes.nl") == null
    assert CodeIntelligenceDeclarationProjection.OutlineFor(directive) == null
}

test "an unprojectable declaration is DROPPED from both file-level answers, not reported as null" {
    declarations := new List<Declaration>()
    declarations.Add(new PreprocessorDeclaration("#if DEBUG", 50, 1))
    declarations.Add(CidpFunction("Draw", Modifiers.None, 51))

    assert CodeIntelligenceDeclarationProjection.Symbols(declarations, "Shapes.nl").Count == 1
    assert CodeIntelligenceDeclarationProjection.OutlineEntries(declarations).Length == 1
}

test "an empty file projects an empty list and an empty array, never null" {
    declarations := new List<Declaration>()
    assert CodeIntelligenceDeclarationProjection.Symbols(declarations, "Shapes.nl").Count == 0
    assert CodeIntelligenceDeclarationProjection.OutlineEntries(declarations).Length == 0
}

test "a type's outline END LINE is estimated from its members, not from its own line" {
    members := new List<Declaration>()
    members.Add(CidpFunction("Draw", Modifiers.None, 19))

    entry := CodeIntelligenceDeclarationProjection.OutlineFor(
        CidpClass("Widget", members, Modifiers.Public)
    )
    assert entry.Line == 7
    assert entry.EndLine == 20

    // With no members at all the estimate falls back to the declaration's own line.
    bare := CodeIntelligenceDeclarationProjection.OutlineFor(
        CidpClass("Widget", new List<Declaration>(), Modifiers.Public)
    )
    assert bare.EndLine == 7
}

test "a struct, a record and an interface each project their own kind" {
    structDeclaration := new StructDeclaration(
        "Point",
        null,
        new List<TypeReference>(),
        new List<Declaration>(),
        null,
        Modifiers.Public,
        CidpAttributes(),
        60,
        1
    )
    recordDeclaration := new RecordDeclaration(
        "Person",
        null,
        new List<TypeReference>(),
        new List<Declaration>(),
        null,
        false,
        Modifiers.Public,
        CidpAttributes(),
        61,
        1
    )
    interfaceDeclaration := new InterfaceDeclaration(
        "IShape",
        null,
        new List<TypeReference>(),
        new List<Declaration>(),
        Modifiers.Public,
        false,
        CidpAttributes(),
        62,
        1
    )

    assert CodeIntelligenceDeclarationProjection.SymbolFor(structDeclaration, "S.nl").Kind == SymbolKind.Struct
    assert CodeIntelligenceDeclarationProjection.SymbolFor(recordDeclaration, "S.nl").Kind == SymbolKind.Record
    assert CodeIntelligenceDeclarationProjection.SymbolFor(interfaceDeclaration, "S.nl").Kind == SymbolKind.Interface
    assert CodeIntelligenceDeclarationProjection.OutlineFor(structDeclaration).Kind == SymbolKind.Struct
    assert CodeIntelligenceDeclarationProjection.OutlineFor(recordDeclaration).Kind == SymbolKind.Record
    assert CodeIntelligenceDeclarationProjection.OutlineFor(interfaceDeclaration).Kind == SymbolKind.Interface
}

test "a property projects its declared type in both answers" {
    declaration := new PropertyDeclaration(
        "Width",
        CidpSimple("int"),
        null,
        null,
        null,
        Modifiers.Public,
        PropertyModifier.None,
        CidpAttributes(),
        70,
        5
    )

    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(declaration, "Shapes.nl")
    assert symbol.Kind == SymbolKind.Property
    assert symbol.TypeName == "int"

    entry := CodeIntelligenceDeclarationProjection.OutlineFor(declaration)
    assert entry.Kind == SymbolKind.Property
    assert entry.TypeName == "int"
    assert entry.ReturnType == null
}

test "a function's outline entry carries its RETURN TYPE and no children" {
    entry := CodeIntelligenceDeclarationProjection.OutlineFor(CidpFunction("Draw", Modifiers.Public, 9))
    assert entry.ReturnType == "int"
    assert entry.TypeName == null
    assert entry.Children == null
}

test "the projections NEST, and the filter applies at every level" {
    inner := new List<Declaration>()
    inner.Add(CidpFunction("Tick", Modifiers.None, 12))
    inner.Add(CidpFunction("tock", Modifiers.None, 13))

    outer := new List<Declaration>()
    outer.Add(CidpClass("Inner", inner, Modifiers.Public))

    symbol := CodeIntelligenceDeclarationProjection.SymbolFor(
        CidpClass("Outer", outer, Modifiers.Public),
        "Shapes.nl"
    )
    assert CidpMemberNames(symbol) == "Inner"
    assert CidpMemberNames(symbol.Members[0]) == "Tick"

    entry := CodeIntelligenceDeclarationProjection.OutlineFor(
        CidpClass("Outer", outer, Modifiers.Public)
    )
    assert CidpOutlineNames(entry) == "Inner"
    assert CidpOutlineNames(entry.Children[0]) == "Tick,tock"
}
