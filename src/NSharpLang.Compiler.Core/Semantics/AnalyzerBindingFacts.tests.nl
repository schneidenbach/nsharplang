namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar


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

// A BY-REFERENCE PARAMETER'S NAME IS THE STORAGE IT REACHES. `v: &int` and `ref v: int` are one CLR
// `int&`; the `ref` spelling carries its shell in the modifier and binds its name at `int`, and the
// `&` spelling carries it in the type, which is dropped for the NAME only. Anything that is not a
// by-reference shell binds at exactly what it resolved to.
test "a by-reference parameter's name binds at the storage type it reaches" {
    storage: TypeInfo = BuiltInTypes.Int
    byRef: TypeInfo = new ByRefTypeInfo(storage)
    assert Object.ReferenceEquals(AnalyzerBindingFacts.ParameterBindingType(byRef), storage)
    assert Object.ReferenceEquals(AnalyzerBindingFacts.ParameterBindingType(storage), storage)

    node: TypeInfo = BindingFactsClass("Node")
    assert Object.ReferenceEquals(AnalyzerBindingFacts.ParameterBindingType(new ByRefTypeInfo(node)), node)
}

// BY-REFERENCE IS WHAT A PARAMETER IS, NOT HOW IT IS SPELLED: `ref`, `out`, `in` and a `&T` type all
// are, and `params` — a modifier, but an array passed by value — is not.
test "a parameter is by reference in either spelling and params is not" {
    intType := new SimpleTypeReference("int")
    assert AnalyzerBindingFacts.IsByReferenceParameter(new Parameter("v", intType, null, false, ParameterModifier.Ref))
    assert AnalyzerBindingFacts.IsByReferenceParameter(new Parameter("v", intType, null, false, ParameterModifier.Out))
    assert AnalyzerBindingFacts.IsByReferenceParameter(new Parameter("v", intType, null, false, ParameterModifier.In))
    assert AnalyzerBindingFacts.IsByReferenceParameter(new Parameter("v", new ByRefTypeReference(intType), null, false))
    assert !AnalyzerBindingFacts.IsByReferenceParameter(new Parameter("v", intType, null, false))
    assert !AnalyzerBindingFacts.IsByReferenceParameter(new Parameter("v", new ArrayTypeReference(intType), null, false, ParameterModifier.Params))
}

func ByRefBindingErrors(source: string): List<CompilerError> {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-byref-binding-" + Guid.NewGuid().ToString("N"))
    filePath := Path.Combine(projectRoot, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    assert parsed.Errors.Count == 0
    unit := parsed.CompilationUnit
    assert unit != null
    Directory.CreateDirectory(projectRoot)
    analyzer := new Analyzer()
    errors := new List<CompilerError>()
    try {
        result := analyzer.Analyze(unit, filePath, projectRoot, source)
        for error in result.Errors {
            if error.Severity == ErrorSeverity.Error {
                errors.Add(error)
            }
        }
    } finally {
        analyzer.Dispose()
        Directory.Delete(projectRoot, true)
    }

    return errors
}

func ByRefBindingMessages(errors: List<CompilerError>): string {
    text := ""
    for error in errors {
        text += Convert.ToInt32(error.Code).ToString() + " " + error.Message + "\n"
    }

    return text
}

func ByRefBindingCount(errors: List<CompilerError>, code: ErrorCode): int {
    total := 0
    for error in errors {
        if error.Code == code {
            total = total + 1
        }
    }

    return total
}

// THE SAME BODIES IN BOTH SPELLINGS, AND BOTH ARE CLEAN. Each body reads the parameter as its value
// and writes through it: arithmetic, compound assignment and increment, a class reference rebound, a
// struct replaced whole, a string, a copy taken by a read, a value passed on by value, a comparison,
// and a generic swap. The `&` spelling was refused NL202 on every one of these (`'+' doesn't work
// with '&int' and 'int'`, `expected '&Node' but got 'Node'`), and the `ref` spelling never was.
test "a &T parameter reads and writes in value position exactly as a ref parameter does" {
    bodies := new List<string>()
    bodies.Add("func Inc(P: int) {\n    v = v + 1\n}\n")
    bodies.Add("func Add(P: int, amount: int) {\n    v += amount\n    v++\n}\n")
    bodies.Add("class Node {\n    Name: string\n\n    constructor(name: string) {\n        Name = name\n    }\n}\n\nfunc Rename(P: Node) {\n    v = new Node(v.Name + \"!\")\n}\n")
    bodies.Add("struct Point {\n    X: int\n    Y: int\n}\n\nfunc Flip(P: Point) {\n    v = new Point { X: v.Y, Y: v.X }\n}\n")
    bodies.Add("func Exclaim(P: string) {\n    v = v + \"!\"\n}\n")
    bodies.Add("func Twice(value: int): int {\n    return value * 2\n}\n\nfunc ReadCopy(P: int): int {\n    copy := v\n    v = Twice(v)\n    if v > copy {\n        return copy\n    }\n\n    return v\n}\n")
    bodies.Add("func Swap<T>(P: T, b: &T) {\n    t := v\n    v = b\n    b = t\n}\n")
    for body in bodies {
        ampersand := body.Replace("P: ", "v: &")
        byRef := body.Replace("P: ", "ref v: ")
        ampersandErrors := ByRefBindingErrors(ampersand)
        byRefErrors := ByRefBindingErrors(byRef)
        assert ampersandErrors.Count == 0, ampersand + "\n" + ByRefBindingMessages(ampersandErrors)
        assert byRefErrors.Count == 0, byRef + "\n" + ByRefBindingMessages(byRefErrors)
    }
}

// THE REFERENCE IS STILL PASSED ON WITH `ref`, and a member is still reached through it.
test "a &T parameter is forwarded with ref and its members are reached through it" {
    source := "struct Counter {\n    Value: int\n}\n\nfunc Bump(counter: &Counter) {\n    counter.Value = counter.Value + 1\n}\n\nfunc Forward(counter: &Counter) {\n    Bump(ref counter)\n}\n\nfunc ForwardRef(ref counter: Counter) {\n    Bump(ref counter)\n}\n"
    errors := ByRefBindingErrors(source)
    assert errors.Count == 0, ByRefBindingMessages(errors)
}

// A BY-REFERENCE PARAMETER PASSED ON BARE IS REFUSED, like every other bare by-reference argument.
// Inside its body the name is the storage it reaches, so `Bump(counter)` passes a VALUE where a
// reference is expected; the call must say `ref` so a reader sees the callee may write the caller's
// storage. The report names the fix — the keyword and the argument it goes in front of — for a
// forwarded parameter and a local alike, and the `out` parameter's keyword is `out`.
test "a by-reference parameter passed on bare is refused with the keyword to write" {
    source := "func Bump(counter: &int) {\n    counter = counter + 1\n}\n\nfunc Produce(out value: int) {\n    value = 1\n}\n\nfunc Forward(counter: &int) {\n    Bump(counter)\n}\n\nfunc Local() {\n    slot := 0\n    Bump(slot)\n    Produce(slot)\n}\n"
    errors := ByRefBindingErrors(source)
    assert errors.Count == 3, ByRefBindingMessages(errors)
    assert ByRefBindingCount(errors, ErrorCode.TypeMismatch) == 3, ByRefBindingMessages(errors)
    hints := ""
    for error in errors {
        hints += (error.ContextualHint ?? error.Suggestion ?? "") + "\n"
    }

    assert hints.Contains("write `ref` before `counter`"), hints
    assert hints.Contains("write `ref` before `slot`"), hints
    assert hints.Contains("write `out` before `slot`"), hints
}

// NL331 IS ABOUT WHAT A PARAMETER IS. A local function may not read an enclosing `v: &int` any more
// than an enclosing `ref v: int` — both are a pointer into the caller's frame that a closure would
// outlive — and it MAY read an enclosing `params` array, which is an ordinary by-value parameter.
test "a local function may not capture a &T parameter and may capture a params one" {
    ampersand := "func Accumulate(values: int[], total: &int) {\n    func add(value: int) {\n        total = total + value\n    }\n\n    for value in values {\n        add(value)\n    }\n}\n"
    byRef := ampersand.Replace("total: &int", "ref total: int")
    ampersandErrors := ByRefBindingErrors(ampersand)
    byRefErrors := ByRefBindingErrors(byRef)
    assert ByRefBindingCount(ampersandErrors, ErrorCode.ByRefParameterCapturedByLocalFunction) == 2, ByRefBindingMessages(ampersandErrors)
    assert ByRefBindingCount(byRefErrors, ErrorCode.ByRefParameterCapturedByLocalFunction) == 2, ByRefBindingMessages(byRefErrors)
    assert ampersandErrors.Count == byRefErrors.Count, ByRefBindingMessages(ampersandErrors) + ByRefBindingMessages(byRefErrors)

    paramsSource := "func Sum(params values: int[]): int {\n    func at(index: int): int {\n        return values[index]\n    }\n\n    return at(0)\n}\n"
    paramsErrors := ByRefBindingErrors(paramsSource)
    assert paramsErrors.Count == 0, ByRefBindingMessages(paramsErrors)
}

// A CALLEE THAT TAKES THE STORAGE BY REFERENCE MAY WRITE NULL INTO IT, in either spelling. The
// argument is the `string?` STORAGE, not the `string` the `if` narrowed a read of it to, so the call
// is accepted (it was refused NL202, "Cannot pass `&string` ... `&string?`", in BOTH spellings); and
// after it the caller's `text` is whatever `string?` allows, so the narrowing does not survive the
// call and the dereference is NL905 — for `s: &string?` as for `ref s: string?`.
test "a call through a &T? parameter resets the argument's null state as a ref one does" {
    ampersand := "func Clear(s: &string?) {\n    s = null\n}\n\nfunc Use(): int {\n    text: string? = \"a\"\n    if text != null {\n        Clear(ref text)\n        return text.Length\n    }\n\n    return 0\n}\n"
    byRef := ampersand.Replace("s: &string?", "ref s: string?")
    ampersandErrors := ByRefBindingErrors(ampersand)
    byRefErrors := ByRefBindingErrors(byRef)
    assert ByRefBindingCount(byRefErrors, ErrorCode.PossibleNullAccess) == 1, ByRefBindingMessages(byRefErrors)
    assert ByRefBindingCount(ampersandErrors, ErrorCode.PossibleNullAccess) == 1, ByRefBindingMessages(ampersandErrors)
    assert byRefErrors.Count == 1, ByRefBindingMessages(byRefErrors)
    assert ampersandErrors.Count == 1, ByRefBindingMessages(ampersandErrors)
}
