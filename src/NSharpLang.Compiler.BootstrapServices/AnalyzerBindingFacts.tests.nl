namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR `AnalyzerBindingFacts`, IN N#.
//
// These replace `tests/AnalyzerBindingFactsTests.cs`, the last canonical C# assertion layer over
// `AnalyzerBindingFacts.nl`. The subject answers the three questions the binder asks about a name
// it has just resolved: where was its parameter DECLARED, may a later declaration SHADOW it, and
// what KIND of declaration is it — the string the LSP shows and the analyser's shadowing rules
// branch on.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. Every input is a constructed `TypeInfo`, and a
// dependency-assembly constructed object declines at `emit.local.initializer` from a `tests/native`
// project.
//
// WHY THE TYPE SHAPES ARE BUILT BY HELPERS. The declared-type constructors take five to eleven
// arguments, most of them empty arrays; `new T[](0)` is the spelling this estate emits, and an
// array literal of constructed elements is not.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) THE PARAMETER POSITION HAS TWO INDEPENDENT GATES, NOT ONE. Line and column each fall back on
// their OWN `> 0` test, so a parameter that carries a line but no column answers the parameter's
// line with the FALLBACK's column. A single combined gate would answer both-or-neither and would
// pass the deleted file's two assertions unchanged.
//
// (2) `IsValueBinding` REFUSES ON FOUR SEPARATE GROUNDS AND THE FIRST TWO ARE NAMES. `this` and
// `value` are refused by NAME whatever their type; a type binding refuses whatever the name; and
// the two callable shapes — `FunctionTypeInfo` and `NSharpMethodGroupInfo` — are refused because a
// later value may not shadow a method group.
//
// (3) THE KIND CHAIN IS ORDERED, AND TWO ARMS ANSWER THE SAME WORD. `AnonymousUnionTypeInfo` is
// tested BEFORE `UnionTypeInfo` and both answer `"union"`; `FunctionTypeInfo` and
// `NSharpMethodGroupInfo` both answer `"function"`. Everything with no arm at all — every builtin,
// every alias, every newtype, every SoA ROW — answers `"variable"`, which is the default the LSP
// shows for a local.
//
// (4) `IsTypeDeclarationKind` IS A NINE-WORD TABLE OVER THE STRINGS THE CHAIN PRODUCES, PLUS TWO
// THE CHAIN NEVER PRODUCES. `"typeAlias"` and `"newtype"` are accepted as type kinds even though
// `TypeInfoToDeclarationKind` answers `"variable"` for both shapes — the two functions are asked by
// DIFFERENT callers, and the declaration walker supplies those two words itself.
func BindingFactsClass(name: string): ClassTypeInfo {
    return new ClassTypeInfo(
        name,
        0,
        0,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        false
    )
}

func BindingFactsStruct(name: string): StructTypeInfo {
    return new StructTypeInfo(
        name,
        0,
        0,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func BindingFactsRecord(name: string): RecordTypeInfo {
    return new RecordTypeInfo(
        name,
        0,
        0,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func BindingFactsInterface(name: string): InterfaceTypeInfo {
    return new InterfaceTypeInfo(
        name,
        0,
        0,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func BindingFactsSoaRecord(name: string): SoaRecordTypeInfo {
    return new SoaRecordTypeInfo(new SoaRecordDeclarationInfo(name, new List<SoaColumnInfo>(), 1, 1))
}

func BindingFactsSoaRow(name: string): SoaRowTypeInfo {
    return new SoaRowTypeInfo(new SoaRecordDeclarationInfo(name, new List<SoaColumnInfo>(), 1, 1))
}

func BindingFactsEnum(name: string): EnumTypeInfo {
    return new EnumTypeInfo(new EnumDeclarationInfo(name, new List<EnumMemberInfo>(), EnumType.Int, 1, 1))
}

func BindingFactsUnion(name: string): UnionTypeInfo {
    return new UnionTypeInfo(new UnionDeclarationInfo(name, null, new List<UnionCase>(), 1, 1))
}

func BindingFactsAnonymousUnion(first: TypeInfo, second: TypeInfo): AnonymousUnionTypeInfo {
    arms := new List<TypeInfo>()
    arms.Add(first)
    arms.Add(second)
    return new AnonymousUnionTypeInfo(arms)
}

func BindingFactsMethodGroup(): NSharpMethodGroupInfo {
    functions := new List<FunctionTypeInfo>()
    functions.Add(new FunctionTypeInfo())
    return new NSharpMethodGroupInfo(functions)
}

func BindingFactsEmptyMethodGroup(): NSharpMethodGroupInfo {
    return new NSharpMethodGroupInfo(new List<FunctionTypeInfo>())
}

// ---- GetParameterDeclarationPosition --------------------------------------------------------------

// Successor to AnalyzerBindingFacts_ResolvesParameterDeclarationPosition.
test "analyzer binding facts resolve the parameter declaration position" {
    explicitPosition := AnalyzerBindingFacts.GetParameterDeclarationPosition(7, 11, 2, 3)
    fallbackPosition := AnalyzerBindingFacts.GetParameterDeclarationPosition(0, 0, 2, 3)

    assert explicitPosition.Item1 == 7
    assert explicitPosition.Item2 == 11
    assert fallbackPosition.Item1 == 2
    assert fallbackPosition.Item2 == 3
}

// NOT IN THE DELETED FILE. The line and the column fall back INDEPENDENTLY, which the deleted
// file's both-or-neither pair could not see.
test "analyzer binding facts fall back on the line and the column independently" {
    lineOnly := AnalyzerBindingFacts.GetParameterDeclarationPosition(7, 0, 2, 3)
    assert lineOnly.Item1 == 7
    assert lineOnly.Item2 == 3

    columnOnly := AnalyzerBindingFacts.GetParameterDeclarationPosition(0, 11, 2, 3)
    assert columnOnly.Item1 == 2
    assert columnOnly.Item2 == 11
}

// NOT IN THE DELETED FILE. The gate is `> 0`, so a NEGATIVE coordinate is treated as absent — and
// the fallback is handed back verbatim, including when it is itself absent.
test "analyzer binding facts treat non positive parameter coordinates as absent" {
    negative := AnalyzerBindingFacts.GetParameterDeclarationPosition(-4, -9, 2, 3)
    assert negative.Item1 == 2
    assert negative.Item2 == 3

    noFallback := AnalyzerBindingFacts.GetParameterDeclarationPosition(0, 0, 0, 0)
    assert noFallback.Item1 == 0
    assert noFallback.Item2 == 0

    boundary := AnalyzerBindingFacts.GetParameterDeclarationPosition(1, 1, 2, 3)
    assert boundary.Item1 == 1
    assert boundary.Item2 == 1
}

// ---- IsValueBinding -------------------------------------------------------------------------------

// Successor to AnalyzerBindingFacts_ClassifiesValueBindingsForShadowing — all six of its
// assertions, over the same six inputs.
test "analyzer binding facts classify value bindings for shadowing" {
    assert AnalyzerBindingFacts.IsValueBinding("count", BuiltInTypes.Int, false)
    assert !AnalyzerBindingFacts.IsValueBinding("this", BuiltInTypes.Int, false)
    assert !AnalyzerBindingFacts.IsValueBinding("value", BuiltInTypes.Int, false)
    assert !AnalyzerBindingFacts.IsValueBinding("T", BuiltInTypes.Int, true)
    assert !AnalyzerBindingFacts.IsValueBinding("Run", new FunctionTypeInfo(), false)
    assert !AnalyzerBindingFacts.IsValueBinding("Run", BindingFactsMethodGroup(), false)
}

// NOT IN THE DELETED FILE. Each of the four refusals is INDEPENDENT of the others: the two names
// are refused whatever their type, the type binding is refused whatever its name, and an EMPTY
// method group is still a method group.
test "analyzer binding facts refuse a value binding on each ground alone" {
    assert !AnalyzerBindingFacts.IsValueBinding("this", BindingFactsClass("Customer"), false)
    assert !AnalyzerBindingFacts.IsValueBinding("value", new FunctionTypeInfo(), false)
    assert !AnalyzerBindingFacts.IsValueBinding("count", BuiltInTypes.Int, true)
    assert !AnalyzerBindingFacts.IsValueBinding("Widget", BindingFactsClass("Widget"), true)
    assert !AnalyzerBindingFacts.IsValueBinding("Run", BindingFactsEmptyMethodGroup(), false)
}

// NOT IN THE DELETED FILE. Everything that is not a callable and not one of the two reserved names
// IS a value binding — including the declared types, which is what lets a local shadow a type name.
test "analyzer binding facts admit every non callable shape as a value binding" {
    assert AnalyzerBindingFacts.IsValueBinding("Customer", BindingFactsClass("Customer"), false)
    assert AnalyzerBindingFacts.IsValueBinding("Point", BindingFactsStruct("Point"), false)
    assert AnalyzerBindingFacts.IsValueBinding("Order", BindingFactsRecord("Order"), false)
    assert AnalyzerBindingFacts.IsValueBinding("IWorker", BindingFactsInterface("IWorker"), false)
    assert AnalyzerBindingFacts.IsValueBinding("Color", BindingFactsEnum("Color"), false)
    assert AnalyzerBindingFacts.IsValueBinding("Result", BindingFactsUnion("Result"), false)
    assert AnalyzerBindingFacts.IsValueBinding("Rows", BindingFactsSoaRecord("Rows"), false)
    assert AnalyzerBindingFacts.IsValueBinding("text", BuiltInTypes.String, false)
    assert AnalyzerBindingFacts.IsValueBinding("alias", new AliasTypeInfo(new SimpleTypeReference("int")), false)
    assert AnalyzerBindingFacts.IsValueBinding("userId", new NewtypeInfo("UserId", new SimpleTypeReference("int")), false)

    // The two refused names are exact: neither casing nor a suffix is refused.
    assert AnalyzerBindingFacts.IsValueBinding("This", BuiltInTypes.Int, false)
    assert AnalyzerBindingFacts.IsValueBinding("Value", BuiltInTypes.Int, false)
    assert AnalyzerBindingFacts.IsValueBinding("values", BuiltInTypes.Int, false)
    assert AnalyzerBindingFacts.IsValueBinding("thisOne", BuiltInTypes.Int, false)
}

// ---- TypeInfoToDeclarationKind --------------------------------------------------------------------

// Successor to AnalyzerBindingFacts_MapsTypeInfoToBindingDeclarationKind — all thirteen of its
// assertions, over the same thirteen shapes.
test "analyzer binding facts map type info to a binding declaration kind" {
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsClass("Customer")) == "class"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsStruct("Point")) == "struct"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsRecord("Order")) == "record"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsSoaRecord("Rows")) == "soaRecord"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsInterface("IWorker")) == "interface"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsEnum("Color")) == "enum"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsAnonymousUnion(BuiltInTypes.Int, BuiltInTypes.String)) == "union"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsUnion("Result")) == "union"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new FunctionTypeInfo()) == "function"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsMethodGroup()) == "function"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BuiltInTypes.Int) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new AliasTypeInfo(new SimpleTypeReference("int"))) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new NewtypeInfo("UserId", new SimpleTypeReference("int"))) == "variable"
}

// NOT IN THE DELETED FILE. The shapes with no arm — every remaining `TypeInfo` in the model —
// answer `"variable"` rather than throwing or answering the previous arm's word.
test "analyzer binding facts answer variable for every shape with no arm" {
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsSoaRow("Rows")) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new SimpleTypeInfo("Widget")) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new ExternalTypeInfo("System.Guid")) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new GenericTypeInfo("List", new List<TypeInfo>())) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new ObliviousTypeInfo(BuiltInTypes.String)) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new ByRefTypeInfo(BuiltInTypes.Int)) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(new TypeInfo()) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BuiltInTypes.String) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BuiltInTypes.Bool) == "variable"
    assert AnalyzerBindingFacts.TypeInfoToDeclarationKind(BuiltInTypes.Double) == "variable"
}

// NOT IN THE DELETED FILE. Every word the chain can produce is a word the OTHER function accepts,
// except the two it answers for callables and the default — which is exactly the pairing the
// declaration walker relies on.
test "analyzer binding facts produce kinds the type kind table agrees with" {
    assert AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsClass("Customer")))
    assert AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsStruct("Point")))
    assert AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsRecord("Order")))
    assert AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsSoaRecord("Rows")))
    assert AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsInterface("IWorker")))
    assert AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsEnum("Color")))
    assert AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsUnion("Result")))
    assert AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsAnonymousUnion(BuiltInTypes.Int, BuiltInTypes.String)))

    assert !AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(new FunctionTypeInfo()))
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BindingFactsMethodGroup()))
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind(AnalyzerBindingFacts.TypeInfoToDeclarationKind(BuiltInTypes.Int))
}

// ---- IsTypeDeclarationKind ------------------------------------------------------------------------

// Successor to AnalyzerBindingFacts_ClassifiesTypeDeclarationKindStrings — all eleven of its
// assertions, over the same eleven words.
test "analyzer binding facts classify type declaration kind strings" {
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("class")
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("struct")
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("record")
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("soaRecord")
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("interface")
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("enum")
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("union")
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("typeAlias")
    assert AnalyzerBindingFacts.IsTypeDeclarationKind("newtype")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("function")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("variable")
}

// NOT IN THE DELETED FILE. The table is an exact, case-sensitive, ordinal match over nine words —
// so no near-miss and no empty string is admitted.
test "analyzer binding facts match type declaration kinds exactly" {
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("Class")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("CLASS")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("classes")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("soarecord")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("SoaRecord")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("typealias")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("alias")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("delegate")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind("parameter")
    assert !AnalyzerBindingFacts.IsTypeDeclarationKind(" class")
}
