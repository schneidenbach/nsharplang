namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Columnar


// Product-path contracts for VALUES WITH NO TYPE OF THEIR OWN at the places N# infers a type from a
// value and nothing else: a `:=` local (with or without `let`, and as a `for` initializer) and an
// anonymous-object property.
//
// Two shapes used to pass analysis as `unknown` in silence and then be refused by the backend as an
// unsupported shape (NL103): an empty `[]` with no target, and a conditional whose branches convert
// neither way. Both are now the analyzer's — NL203 and NL202 — and the hint names the local or the
// property the value was going to. These parse real N# source and drive the same `Analyzer` entry
// point `nlc check` uses, so what is pinned is what the reader sees.
class InferenceSiteAnalysis {
    Errors: List<CompilerError>

    constructor(errors: List<CompilerError>) {
        Errors = errors
    }
}

func AnalyzeInferenceSites(source: string): InferenceSiteAnalysis {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-inference-sites-" + Guid.NewGuid().ToString("N"))
    filePath := Path.Combine(projectRoot, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    assert parsed.Errors.Count == 0
    unit := parsed.CompilationUnit
    assert unit != null
    Directory.CreateDirectory(projectRoot)
    analyzer := new Analyzer()
    analyzer.LoadSystemAssemblies()
    errors := new List<CompilerError>()
    try {
        result := analyzer.Analyze(unit, filePath, projectRoot, source)
        for error in result.Errors {
            if error.Severity == ErrorSeverity.Error {
                errors.Add(error)
            }
        }
        return new InferenceSiteAnalysis(errors)
    } finally {
        analyzer.Dispose()
        Directory.Delete(projectRoot, true)
    }
}

func InferenceSiteCodes(errors: List<CompilerError>): string {
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

// `body` runs inside `func Run(flag: bool)`, starting on line 9, beside three classes a conditional
// can be built from.
func InferenceSiteProgram(body: string): string {
    return "import System\nclass Animal {}\nclass Dog: Animal {}\nclass Cat: Animal {}\nfunc Take(xs: int[]): int {\n    return xs.Length\n}\nfunc Run(flag: bool) {\n" + body + "}\n"
}

// ---- an empty `[]` --------------------------------------------------------------------------------

test "an empty `[]` on the right of `:=` is NL203 on the literal, and the hint names the local" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    scores := []\n    print scores\n"))

    assert InferenceSiteCodes(analysis.Errors) == "203", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Message == "I can't figure out what type of array '[]' is — it has no elements to infer from, and nothing here says what it should hold"
    assert analysis.Errors[0].Suggestion == "Say what type 'scores' is, for example 'scores: int[] = []'."
    assert analysis.Errors[0].Line == 9
    assert analysis.Errors[0].Column == 15
    assert analysis.Errors[0].Length == 2
}

test "the hint keeps a `let`, and a `for` initializer is a local like any other" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    let names = []\n    print names\n    for i := []; flag; {\n        print i\n    }\n"))

    assert InferenceSiteCodes(analysis.Errors) == "203,203", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Suggestion == "Say what type 'names' is, for example 'let names: int[] = []'."
    assert analysis.Errors[1].Suggestion == "Say what type 'i' is, for example 'i: int[] = []'."
}

// AN ANONYMOUS PROPERTY CANNOT BE ANNOTATED IN PLACE, so its fix declares a typed local first.
test "an empty `[]` as an anonymous-object property is NL203, and the hint declares a typed local" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    order := new { Id: 1, Items: [] }\n    print order\n"))

    assert InferenceSiteCodes(analysis.Errors) == "203", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Suggestion == "Declare it with a type first, for example 'items: int[] = []', then write 'Items: items'."
    assert analysis.Errors[0].Line == 9
    assert analysis.Errors[0].Column == 34
}

// ONE REPORT PER MISSING TYPE. A nested `[]` is reported once, not again as a mismatch against the
// `unknown[]` it answered; one somewhere no site reaches gets the general hint.
test "a nested or lambda-bodied `[]` is reported once, with the general hint" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    grid := [[], [1]]\n    print grid\n    make := () => []\n    print make\n"))

    assert InferenceSiteCodes(analysis.Errors) == "203,203", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Suggestion == "Write the type where the value is declared, for example 'items: int[] = []'."
    assert analysis.Errors[1].Suggestion == "Write the type where the value is declared, for example 'items: int[] = []'."
}

// ---- a conditional whose branches disagree --------------------------------------------------------

test "a conditional whose branches convert neither way is NL202 over the whole conditional" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    label := flag ? 1 : \"x\"\n    print label\n"))

    assert InferenceSiteCodes(analysis.Errors) == "202", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Message == "The two branches of this conditional have different types — 'int' when true and 'string' when false — and neither converts to the other, so I can't tell what type it produces"
    assert analysis.Errors[0].Suggestion == "Make both branches the same type, or name a type both fit. Say what type 'label' is, for example 'label: object = ...'."
    assert analysis.Errors[0].Line == 9
    assert analysis.Errors[0].Column == 14
    assert analysis.Errors[0].Length == 14
}

test "sibling classes with no conversion between them are NL202 too" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    pet := flag ? new Dog() : new Cat()\n    print pet\n"))

    assert InferenceSiteCodes(analysis.Errors) == "202", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Message.Contains("'Dog' when true and 'Cat' when false")
}

test "a null branch beside a value type is told to make the local nullable" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    count := flag ? 1 : null\n    print count\n"))

    assert InferenceSiteCodes(analysis.Errors) == "202", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Message == "This conditional is 'int' when true and 'null' when false, and 'int' can't hold null"
    assert analysis.Errors[0].Suggestion == "Say what type 'count' is, for example 'count: int? = ...'."
}

test "a disagreeing conditional as an anonymous-object property is NL202, and the hint declares a typed local" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    row := new { Mixed: flag ? 1 : \"x\" }\n    print row\n"))

    assert InferenceSiteCodes(analysis.Errors) == "202", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Suggestion == "Make both branches the same type, or name a type both fit. Declare it with a type first, for example 'mixed: object = ...', then write 'Mixed: mixed'."
}

// An empty `[]` as one arm is the literal's report, once; the conditional does not add a second.
test "an empty `[]` arm is reported on the literal, with the local's name, and nowhere else" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram("    picks := flag ? [] : [1]\n    print picks\n"))

    assert InferenceSiteCodes(analysis.Errors) == "203", InferenceSiteCodes(analysis.Errors)
    assert analysis.Errors[0].Suggestion == "Say what type 'picks' is, for example 'picks: int[] = ...'."
}

// ---- what stays clean -----------------------------------------------------------------------------

// A TARGET DECIDES. An annotation, a parameter already chosen and a parameter still being chosen all
// say what the value is; a `null` beside a reference is that reference made nullable; one branch
// converting to the other is the other's type; and a `throw` arm has no type to disagree with. None
// of these is the analyzer's to refuse.
test "targeted values, convertible branches and null beside a reference are not reported" {
    analysis := AnalyzeInferenceSites(InferenceSiteProgram(
        "    xs: int[] = []\n" + "    total := Take([])\n" + "    name := flag ? \"a\" : null\n" + "    pet := flag ? new Dog() : null\n" + "    animal := flag ? new Dog() : new Animal()\n" + "    boxed: object = flag ? 1 : \"x\"\n" + "    one := flag ? 1 : throw new Exception(\"no\")\n" + "    ones := flag ? [1] : [2]\n" + "    print xs.Length + total + one + ones.Length\n" + "    print name\n" + "    print pet\n" + "    print animal\n" + "    print boxed\n"
    ))

    assert InferenceSiteCodes(analysis.Errors) == "", InferenceSiteCodes(analysis.Errors)
}
