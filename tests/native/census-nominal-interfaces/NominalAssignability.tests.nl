namespace NSharpLang.CensusNominalInterfaces.Tests

import System
import System.Collections


// THE SOURCE HALF: the production analyzer, over source text. A class that does not name a plain
// interface is not assignable to it — the ordinary `NL202` — and the same class flows to a duck
// interface of the same shape without a word. This is the rule the emitter now agrees with.
//
// The route is reflection through `object`, as in every analyzer-* native project: naming a
// referenced assembly's type in a local, an argument or a `new` declines columnar emission.
func NominalSet(values: object?[], index: int, value: object?) {
    values[index] = value
}

func NominalMember(owner: object, memberName: string): object? {
    property := owner.GetType().GetProperty(memberName)
    if property != null {
        return property.GetValue(owner)
    }

    field := owner.GetType().GetField(memberName)
    if field != null {
        return field.GetValue(owner)
    }

    throw new InvalidOperationException("The production type exposed no '" + memberName + "' member.")
}

func NominalText(owner: object, memberName: string): string {
    value := NominalMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

func NominalParse(source: string): object {
    parserType := Type.GetType("NSharpLang.Compiler.Columnar.ColumnarParserRecovery, NSharpLang.Compiler.Syntax")
    if parserType == null {
        throw new InvalidOperationException("The production recovery parser was not loadable.")
    }

    parseParameterTypes := new Type[](2)
    parseParameterTypes[0] = typeof(string)
    parseParameterTypes[1] = typeof(string)
    parseMethod := parserType.GetMethod("ParseFileAst", parseParameterTypes)
    if parseMethod == null {
        throw new InvalidOperationException("The production ParseFileAst entry point was not found.")
    }

    parseArguments := new object?[](2)
    NominalSet(parseArguments, 0, source)
    NominalSet(parseArguments, 1, null)
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return parsed
}

// Every diagnostic's id, code name and span, in recording order: the parse's first, then the
// analysis's, so a recovery artefact can never pass for an analyzer row.
func NominalCensus(source: string): string {
    parsed := NominalParse(source)
    census := NominalRows(NominalMember(parsed, "Errors") as IList)
    unit := NominalMember(parsed, "CompilationUnit")
    if unit == null {
        throw new InvalidOperationException("The production parse produced no compilation unit.")
    }

    analyzerType := Type.GetType("NSharpLang.Compiler.Analyzer, NSharpLang.Compiler.Core")
    unitType := Type.GetType("NSharpLang.Compiler.Ast.CompilationUnit, NSharpLang.Compiler.Model")
    if analyzerType == null || unitType == null {
        throw new InvalidOperationException("The production analyzer types were not loadable.")
    }

    analyzerConstructor := analyzerType.GetConstructor(new Type[](0))
    if analyzerConstructor == null {
        throw new InvalidOperationException("The production analyzer was not constructible.")
    }
    analyzer := analyzerConstructor.Invoke(new object?[](0))

    loadMethod := analyzerType.GetMethod("LoadSystemAssemblies", new Type[](0))
    if loadMethod == null {
        throw new InvalidOperationException("The production LoadSystemAssemblies entry point was not found.")
    }
    loadMethod.Invoke(analyzer, new object?[](0))

    analyzeParameterTypes := new Type[](1)
    analyzeParameterTypes[0] = unitType
    analyzeMethod := analyzerType.GetMethod("Analyze", analyzeParameterTypes)
    if analyzeMethod == null {
        throw new InvalidOperationException("The production single-argument Analyze entry point was not found.")
    }
    analyzeArguments := new object?[](1)
    NominalSet(analyzeArguments, 0, unit)
    analysis := analyzeMethod.Invoke(analyzer, analyzeArguments)

    disposeMethod := analyzerType.GetMethod("Dispose", new Type[](0))
    if disposeMethod != null {
        disposeMethod.Invoke(analyzer, new object?[](0))
    }

    if analysis == null {
        throw new InvalidOperationException("The production analyzer returned no result.")
    }

    return census + NominalRows(NominalMember(analysis, "Errors") as IList)
}

func NominalRows(errors: IList?): string {
    if errors == null {
        return "<not-a-list>"
    }

    rows := ""
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            rows = rows + NominalText(entry, "DiagnosticId") + ":" + NominalText(entry, "Code") + "@" + NominalText(entry, "Line") + ":" + NominalText(entry, "Column") + ";"
        }

        index = index + 1
    }

    return rows
}

func NominalFixture(interfaceKeyword: string, body: string): string {
    return interfaceKeyword + " IGreeter {\n    func Greet(): string\n}\n\nclass Stranger {\n    func Greet(): string {\n        return \"stranger\"\n    }\n}\n\nfunc Take(greeter: IGreeter): string {\n    return greeter.Greet()\n}\n\nfunc Main() {\n" + body + "\n}\n"
}

test "passing a class that does not name a plain interface is the ordinary argument mismatch" {
    assert NominalCensus(NominalFixture("interface", "    Take(new Stranger())")) == "NL202:TypeMismatch@16:10;"
}

test "assigning a class that does not name a plain interface is the ordinary assignment mismatch" {
    assert NominalCensus(NominalFixture("interface", "    greeter: IGreeter = new Stranger()")) == "NL202:TypeMismatch@16:5;"
}

test "the same class flows to a duck interface of the same shape without a diagnostic" {
    assert NominalCensus(NominalFixture("duck interface", "    Take(new Stranger())")) == ""
    assert NominalCensus(NominalFixture("duck interface", "    greeter: IGreeter = new Stranger()")) == ""
}

test "an empty plain marker is not satisfied by a class that does not name it" {
    source := "interface IMarker {\n}\n\nclass Plain {\n}\n\nfunc Main() {\n    marker: IMarker = new Plain()\n}\n"
    assert NominalCensus(source) == "NL202:TypeMismatch@8:5;"
    declared := "interface IMarker {\n}\n\nclass Plain : IMarker {\n}\n\nfunc Main() {\n    marker: IMarker = new Plain()\n}\n"
    assert NominalCensus(declared) == ""
}
