namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Columnar


// Product-path semantic contracts for anonymous objects — `new { Name: value, ... }`. These parse real
// N# source and drive the same Analyzer entry point `nlc check` uses, so the type an anonymous object
// has, what its members resolve to, the diagnostics it raises and the bindings go-to-definition reads
// are all pinned at their public boundary.
class AnonymousObjectAnalysis {
    Errors: List<CompilerError>
    Result: AnalysisResult
    FilePath: string

    constructor(errors: List<CompilerError>, result: AnalysisResult, filePath: string) {
        Errors = errors
        Result = result
        FilePath = filePath
    }
}

func AnalyzeAnonymousObjects(source: string): AnonymousObjectAnalysis {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-anonymous-objects-" + Guid.NewGuid().ToString("N"))
    filePath := Path.Combine(projectRoot, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    assert parsed.Errors.Count == 0
    unit := parsed.CompilationUnit
    assert unit != null
    Directory.CreateDirectory(projectRoot)
    analyzer := new Analyzer()
    // The BCL is loaded the way `nlc check` loads it, so `System.Linq` resolves in the probes.
    analyzer.LoadSystemAssemblies()
    errors := new List<CompilerError>()
    try {
        result := analyzer.Analyze(unit, filePath, projectRoot, source)
        for error in result.Errors {
            if error.Severity == ErrorSeverity.Error {
                errors.Add(error)
            }
        }
        return new AnonymousObjectAnalysis(errors, result, filePath)
    } finally {
        analyzer.Dispose()
        Directory.Delete(projectRoot, true)
    }
}

func AnonymousErrorCodes(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + ","
        }
        text = text + Convert.ToInt32(errors[index].Code).ToString()
        index = index + 1
    }
    return text
}

func AnonymousMain(body: string): string {
    return "class Pt {\n    X: int\n}\nfunc main() {\n" + body + "}\n"
}

// ---- the type ------------------------------------------------------------------------------------

test "an anonymous object is typed by its properties, and every use of them is clean" {
    analysis := AnalyzeAnonymousObjects(
        "import System.Linq\n" + "func Echo<T>(value: T): T {\n" + "    return value\n" + "}\n" + "func Show(value: object): string {\n" + "    return value.ToString() ?? \"\"\n" + "}\n" + "func main() {\n" + "    person := new { Name: \"Alice\", Age: 30 }\n" + "    name: string = person.Name\n" + "    next: int = person.Age + 1\n" + "    text: string = person.ToString()\n" + "    same := Echo(person)\n" + "    equal: bool = same.Equals(new { Name: \"Alice\", Age: 30 })\n" + "    hash: int = person.GetHashCode()\n" + "    shown := Show(person)\n" + "    rows := [1, 2].Select(n => new { N: n }).ToList()\n" + "    first: int = rows[0].N\n" + "    older := person with { Age: 31 }\n" + "    print name + next.ToString() + text + same.Name + equal.ToString() + hash.ToString() + shown + first.ToString() + older.Name\n" + "}\n"
    )

    assert AnonymousErrorCodes(analysis.Errors) == "", AnonymousErrorCodes(analysis.Errors)
}

test "an anonymous object prints as the shape it was written with" {
    analysis := AnalyzeAnonymousObjects(AnonymousMain("    person := new { Name: \"Alice\", Age: 30 }\n    wrong: int = person\n"))

    assert AnonymousErrorCodes(analysis.Errors) == "202"
    assert analysis.Errors[0].Message == "Variable 'wrong' is typed as 'int', but the value is 'new { Name: string, Age: int }'"
}

test "`new { ... }` is never target-typed, and the hint names the spelling that is" {
    analysis := AnalyzeAnonymousObjects(AnonymousMain("    point: Pt = new { X: 1 }\n    print point.X\n"))

    assert AnonymousErrorCodes(analysis.Errors) == "202"
    assert analysis.Errors[0].Message == "Variable 'point' is typed as 'Pt', but the value is 'new { X: int }'"
    assert (analysis.Errors[0].ContextualHint ?? "").Contains("`new Pt { ... }`")
}

test "two anonymous objects of the same shape are the same type, and of another shape are not" {
    same := AnalyzeAnonymousObjects(AnonymousMain("    items := [new { A: 1 }, new { A: 2 }]\n    print items.Length\n"))
    assert AnonymousErrorCodes(same.Errors) == "", AnonymousErrorCodes(same.Errors)

    different := AnalyzeAnonymousObjects(AnonymousMain("    first := new { A: 1 }\n    second: object = first\n    third := new { A: \"x\" }\n    first = third\n    print second\n"))
    assert AnonymousErrorCodes(different.Errors) == "202"
}

// ---- the members ---------------------------------------------------------------------------------

test "a property the anonymous object does not have is NL303, with the property it probably meant" {
    analysis := AnalyzeAnonymousObjects(AnonymousMain("    person := new { Name: \"Alice\", Age: 30 }\n    print person.Nmae\n"))

    assert AnonymousErrorCodes(analysis.Errors) == "303"
    assert analysis.Errors[0].Message == "Member 'Nmae' not found on type 'new { Name: string, Age: int }'"
    assert analysis.Errors[0].Line == 6
    assert analysis.Errors[0].Column == 18
}

test "an anonymous property is read-only (NL309), whatever writes it" {
    analysis := AnalyzeAnonymousObjects(AnonymousMain("    person := new { Name: \"Alice\", Age: 30 }\n    person.Name = \"Bob\"\n    person.Age += 1\n"))

    assert AnonymousErrorCodes(analysis.Errors) == "309,309", AnonymousErrorCodes(analysis.Errors)
    assert analysis.Errors[0].Message == "'Name' is a property of an anonymous object, and anonymous objects are read-only — it can't be assigned with '='"
    assert analysis.Errors[0].Line == 6
    assert analysis.Errors[0].Column == 12
}

// ---- the property values -------------------------------------------------------------------------

test "a property cannot take its type from null, a lambda or a call that returns nothing (NL203)" {
    analysis := AnalyzeAnonymousObjects(
        "func Nothing() {\n" + "}\n" + "func main() {\n" + "    a := new { Missing: null }\n" + "    b := new { Handler: (x: int) => x + 1 }\n" + "    c := new { Result: Nothing() }\n" + "    print a\n" + "    print b\n" + "    print c\n" + "}\n"
    )

    assert AnonymousErrorCodes(analysis.Errors) == "203,203,203", AnonymousErrorCodes(analysis.Errors)
    assert analysis.Errors[0].Message == "I can't figure out the type of anonymous-object property 'Missing' from 'null' — an anonymous property takes its type from its value"
    assert analysis.Errors[0].Line == 4
    assert analysis.Errors[0].Column == 25
    assert analysis.Errors[1].Message.Contains("from a lambda")
    assert analysis.Errors[2].Message.Contains("from a call that returns nothing")
}

test "a property named twice is NL306 on the second name" {
    analysis := AnalyzeAnonymousObjects(AnonymousMain("    pair := new { A: 1, A: 2 }\n    print pair.A\n"))

    assert AnonymousErrorCodes(analysis.Errors) == "306"
    assert analysis.Errors[0].Message == "This anonymous object already has a property named 'A'"
    assert analysis.Errors[0].Line == 5
    assert analysis.Errors[0].Column == 25
}

// ---- `with` and patterns -------------------------------------------------------------------------

test "`with` on an anonymous object is held to the object's own properties and their types" {
    analysis := AnalyzeAnonymousObjects(AnonymousMain("    person := new { Name: \"Alice\", Age: 30 }\n    a := person with { Agee: 31 }\n    b := person with { Age: \"x\" }\n    c := person with { Age: 1, Age: 2 }\n    print a\n    print b\n    print c\n"))

    assert AnonymousErrorCodes(analysis.Errors) == "303,202,306", AnonymousErrorCodes(analysis.Errors)
    assert analysis.Errors[0].Message == "Member 'Agee' not found on type 'new { Name: string, Age: int }'"
}

test "a property pattern reads an anonymous object's properties, and refuses one it does not have" {
    good := AnalyzeAnonymousObjects(AnonymousMain("    person := new { Name: \"Alice\", Age: 30 }\n    text := match person {\n        { Age: 30, Name: n } => n,\n        _ => \"other\"\n    }\n    print text\n"))
    assert AnonymousErrorCodes(good.Errors) == "", AnonymousErrorCodes(good.Errors)

    bad := AnalyzeAnonymousObjects(AnonymousMain("    person := new { Name: \"Alice\" }\n    text := match person {\n        { Age: 30 } => \"thirty\",\n        _ => \"other\"\n    }\n    print text\n"))
    assert AnonymousErrorCodes(bad.Errors) == "503"
}

// ---- bindings ------------------------------------------------------------------------------------

test "a property read binds to the name the creation wrote, and the creation's name is the declaration" {
    analysis := AnalyzeAnonymousObjects(AnonymousMain("    person := new { Name: \"Alice\", Age: 30 }\n    print person.Name\n"))
    bindings := analysis.Result.Bindings
    assert bindings != null

    declaration := bindings?.GetBindingAt(analysis.FilePath, 6, 18)
    assert declaration != null
    assert declaration?.Name == "Name"
    assert declaration?.Kind == "property"
    assert declaration?.Line == 5
    assert declaration?.Column == 21

    atCreation := bindings?.GetBindingAt(analysis.FilePath, 5, 21)
    assert atCreation != null
    assert atCreation?.Line == 5
    assert atCreation?.Column == 21
}

test "reading a property whose value already failed is not reported as a missing member" {
    analysis := AnalyzeAnonymousObjects(AnonymousMain("    a := new { Missing: null }\n    print a.Missing\n"))

    assert AnonymousErrorCodes(analysis.Errors) == "203", AnonymousErrorCodes(analysis.Errors)
}
