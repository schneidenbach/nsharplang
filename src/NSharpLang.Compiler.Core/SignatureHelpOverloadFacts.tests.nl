namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR WHAT A CALL BEING TYPED RESOLVES TO. Signature help used to read the open buffer's
// own declaration table, so an external method, an overload set and a type declared in another file
// all answered nothing. These assertions are written against the owner that replaced it: the same
// resolution order completion follows — source before metadata — with the per-overload rows and the
// active-overload rule that a protocol handler now has nothing left to decide.
func ShoParameter(name: string, typeName: string): Parameter {
    return new Parameter(name, new SimpleTypeReference(typeName, 1, 1), null, false)
}

func ShoFunction(name: string, parameters: List<Parameter>, returnTypeName: string?): FunctionDeclaration {
    returnType: TypeReference? = null
    if returnTypeName != null {
        returnType = new SimpleTypeReference(returnTypeName, 1, 1)
    }

    return new FunctionDeclaration(name, parameters, returnType, null, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 1, 1)
}

func ShoUnit(declarations: List<Declaration>, sourceText: string?): SignatureHelpSourceUnit {
    unit := new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
    return new SignatureHelpSourceUnit(unit, sourceText)
}

func ShoUnits(unit: SignatureHelpSourceUnit): List<SignatureHelpSourceUnit> {
    units := new List<SignatureHelpSourceUnit>()
    units.Add(unit)
    return units
}

func ShoOneParameterList(name: string, typeName: string): List<Parameter> {
    parameters := new List<Parameter>()
    parameters.Add(ShoParameter(name, typeName))
    return parameters
}

func ShoOverload(label: string, parameterLabels: List<string>): SignatureHelpOverload {
    return new SignatureHelpOverload(label, null, parameterLabels)
}

func ShoLabels(first: string?, second: string?): List<string> {
    labels := new List<string>()
    if first != null {
        labels.Add(first)
    }

    if second != null {
        labels.Add(second)
    }

    return labels
}

test "a signature label spells the call, its rows and its return type" {
    assert SignatureHelpOverloadFacts.FormatLabel("greet", ShoLabels("name: string", "times: int"), "void") == "greet(name: string, times: int): void"
    assert SignatureHelpOverloadFacts.FormatLabel("getTime", ShoLabels(null, null), "string") == "getTime(): string"
}

test "a source function answers one overload per declaration of its name" {
    declarations := new List<Declaration>()
    first: Declaration = ShoFunction("greet", ShoOneParameterList("name", "string"), "string")
    declarations.Add(first)
    second: Declaration = ShoFunction("other", new List<Parameter>(), "int")
    declarations.Add(second)

    call := new SignatureHelpCallContext(null, "greet", false, "")
    overloads := SignatureHelpOverloadFacts.ResolveOverloads(call, ShoUnits(ShoUnit(declarations, null)), null, null, null, 1, 1)

    assert overloads.Count == 1
    assert overloads[0].Label == "greet(name: string): string"
    assert overloads[0].ParameterLabels.Count == 1
    assert overloads[0].ParameterLabels[0] == "name: string"
}

// A function with no declared return type reads as `void`, which is the answer the editor showed
// before this owner existed and the one a reader of the declaration would give.
test "a source function with no declared return type reads as void" {
    declarations := new List<Declaration>()
    declaration: Declaration = ShoFunction("run", new List<Parameter>(), null)
    declarations.Add(declaration)

    call := new SignatureHelpCallContext(null, "run", false, "")
    overloads := SignatureHelpOverloadFacts.ResolveOverloads(call, ShoUnits(ShoUnit(declarations, null)), null, null, null, 1, 1)

    assert overloads.Count == 1
    assert overloads[0].Label == "run(): void"
}

// THE LEADING COMMENT BLOCK OF THE DECLARATION IS THE DOCUMENTATION, read out of the text the unit
// was parsed from. A unit with no text answers null rather than guessing.
test "a source overload carries the leading comment block of its declaration" {
    declarations := new List<Declaration>()
    declaration: Declaration = new FunctionDeclaration("greet", ShoOneParameterList("name", "string"), new SimpleTypeReference("string", 1, 1), null, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 3, 1)
    declarations.Add(declaration)

    sourceText := "// Greets someone by name.\n// Returns the composed greeting.\nfunc greet(name: string): string\n    return name\n"
    call := new SignatureHelpCallContext(null, "greet", false, "")
    documented := SignatureHelpOverloadFacts.ResolveOverloads(call, ShoUnits(ShoUnit(declarations, sourceText)), null, null, null, 1, 1)

    assert documented.Count == 1
    assert documented[0].Documentation != null
    assert (documented[0].Documentation ?? "").Contains("Greets someone by name.", StringComparison.Ordinal)
    assert (documented[0].Documentation ?? "").Contains("Returns the composed greeting.", StringComparison.Ordinal)

    undocumented := SignatureHelpOverloadFacts.ResolveOverloads(call, ShoUnits(ShoUnit(declarations, null)), null, null, null, 1, 1)
    assert undocumented.Count == 1
    assert undocumented[0].Documentation == null
}

// AN EXTERNAL TYPE NAME ANSWERS FOR ITS STATICS, which is the whole of what `Console.WriteLine(`
// asks and exactly what a current-document table could never hold.
test "an external static receiver answers every overload of the name" {
    call := new SignatureHelpCallContext("Console", "WriteLine", false, "")
    overloads := SignatureHelpOverloadFacts.ResolveOverloads(call, new List<SignatureHelpSourceUnit>(), null, null, null, 1, 1)

    assert overloads.Count > 1
    index := 0
    while index < overloads.Count {
        assert overloads[index].Label.StartsWith("WriteLine(", StringComparison.Ordinal)
        index = index + 1
    }
}

// The reflected rows carry the DECLARED parameter name and type, not a positional placeholder.
test "a reflected overload names its rows" {
    overloads := SignatureHelpOverloadFacts.ClrMethodOverloads(typeof(string), "Substring", false)

    assert overloads.Count > 1
    single := SignatureHelpOverloadFacts.SelectActiveOverload(overloads, 1)
    assert overloads[single].ParameterLabels.Count == 1
    assert overloads[single].ParameterLabels[0] == "startIndex: int"
}

// A synthesised accessor is not a call a reader can write, so it is not a signature. The gate is
// the platform's own special-name flag, which is the same one completion reads.
test "a reflected property accessor is not offered as a signature" {
    assert SignatureHelpOverloadFacts.ClrMethodOverloads(typeof(string), "get_Length", false).Count == 0
}

test "a metadata type answers for its own constructors" {
    overloads := SignatureHelpOverloadFacts.ConstructorOverloads("DateTime", new List<SignatureHelpSourceUnit>(), null, null)

    assert overloads.Count > 1
    index := 0
    while index < overloads.Count {
        assert overloads[index].Label.StartsWith("DateTime(", StringComparison.Ordinal)
        index = index + 1
    }
}

// A CONSTRUCTED TYPE'S REFLECTED NAME CARRIES ITS ARITY, which no caller wrote and no reader wants
// to read back.
test "a reflected type name drops the arity tick" {
    assert SignatureHelpOverloadFacts.ClrTypeSimpleName(typeof(List<string>)) == "List"
    assert SignatureHelpOverloadFacts.ClrTypeSimpleName(typeof(string)) == "String"
}

// A SOURCE DECLARATION WINS OUTRIGHT over a same-spelled type the process happens to have loaded.
// This is the ordering completion already follows, and the reason a project's own type of a BCL
// spelling would be the one a caller sees.
test "a source type declaration answers before metadata for the same spelling" {
    members := new List<Declaration>()
    member: Declaration = new ConstructorDeclaration(ShoOneParameterList("reason", "string"), new BlockStatement(new List<Statement>(), 1, 1), null, Modifiers.None, new List<AttributeNode>(), 2, 1)
    members.Add(member)

    declarations := new List<Declaration>()
    declaration: Declaration = new ClassDeclaration("DateTime", null, null, new List<TypeReference>(), members, null, Modifiers.None, new List<AttributeNode>(), 1, 1)
    declarations.Add(declaration)

    overloads := SignatureHelpOverloadFacts.ConstructorOverloads("DateTime", ShoUnits(ShoUnit(declarations, null)), null, null)

    assert overloads.Count == 1
    assert overloads[0].Label == "DateTime(reason: string): void"
}

// THE OVERLOAD THE ARGUMENTS POINT AT: matched arity first, then the first that could still take
// what is being typed, then the first.
test "the active overload follows the arity written so far" {
    overloads := new List<SignatureHelpOverload>()
    overloads.Add(ShoOverload("f(): void", ShoLabels(null, null)))
    overloads.Add(ShoOverload("f(a: int, b: int): void", ShoLabels("a: int", "b: int")))
    overloads.Add(ShoOverload("f(a: int): void", ShoLabels("a: int", null)))

    assert SignatureHelpOverloadFacts.SelectActiveOverload(overloads, 0) == 0
    assert SignatureHelpOverloadFacts.SelectActiveOverload(overloads, 2) == 1
    assert SignatureHelpOverloadFacts.SelectActiveOverload(overloads, 1) == 2
    // Nothing takes four, so the first row stays on screen rather than none.
    assert SignatureHelpOverloadFacts.SelectActiveOverload(overloads, 4) == 0
    assert SignatureHelpOverloadFacts.SelectActiveOverload(new List<SignatureHelpOverload>(), 0) == 0
}

// THE ROW THE CARET IS IN IS ASKED OF THE OVERLOAD ACTUALLY ON SCREEN, because a named argument
// points at the row wearing that name and the rows differ between overloads.
test "the active parameter is read against the active overload's own rows" {
    overloads := new List<SignatureHelpOverload>()
    overloads.Add(ShoOverload("add(a: int, b: int): int", ShoLabels("a: int", "b: int")))

    assert SignatureHelpOverloadFacts.ActiveParameter(overloads, 0, "1, ") == 1
    assert SignatureHelpOverloadFacts.ActiveParameter(overloads, 0, "b: 1, a: ") == 0
    // An index no overload wears cannot name a row, so the positional answer stands.
    assert SignatureHelpOverloadFacts.ActiveParameter(overloads, 7, "1, ") == 1
}

test "a dotted receiver name is read down to its simple name" {
    assert SignatureHelpOverloadFacts.SimpleName("Catalog.Box") == "Box"
    assert SignatureHelpOverloadFacts.SimpleName("Box") == "Box"
}
