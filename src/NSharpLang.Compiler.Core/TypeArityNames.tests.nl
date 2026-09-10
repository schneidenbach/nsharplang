namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast


// THE CONTRACTS FOR TYPE IDENTITY BY (NAME, GENERIC ARITY).
//
// Two things are pinned here, and they are one rule seen from two sides.
//
// (1) THE SPELLING. `TypeArityNames` is the single owner of the `Name``N` key, of the display name
// that a person is shown instead, and of the two sentence fragments the arity diagnostics end with.
// A key composed twice must equal a key composed once, and a name that merely contains a backtick
// must not be mistaken for one that carries an arity.
//
// (2) THE LANGUAGE RULE, END TO END over real source, through the real parser and the real analyzer.
// `Subscription` and `Subscription<T>` are two types on the CLR and may be declared side by side;
// `Subscription<T>: Subscription` derives from its non-generic sibling and is NOT a cycle; NL306
// fires for a repeated (name, arity) and for nothing else; and an arity nobody declared is reported
// with the arities that ARE declared. These are written as source rather than as scope-table pokes
// because the defect they replace was invisible at every level below the whole pipeline: the
// declaration table, the canonical-type cache and the base-chain walk each looked correct on their
// own and collapsed the two declarations into one identity together.
func TypeArityAnalysisErrors(source: string): List<CompilerError> {
    return TypeArityAnalyze(source).Errors
}

func TypeArityErrorCodes(errors: List<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + ","
        }
        codeValue: int = (int)errors[index].Code
        text = text + codeValue.ToString()
        index = index + 1
    }
    return text
}

// The analysis of one source, with its file path and binding map kept, so a contract can ask where
// go-to-definition on a given position lands.
class TypeArityAnalysis {
    Errors: List<CompilerError>
    Bindings: BindingMap?
    Model: SemanticModel
    FilePath: string

    constructor(errors: List<CompilerError>, bindings: BindingMap?, model: SemanticModel, filePath: string) {
        this.Errors = errors
        this.Bindings = bindings
        this.Model = model
        this.FilePath = filePath
    }
}

func TypeArityAnalyze(source: string): TypeArityAnalysis {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-type-arity-" + Guid.NewGuid().ToString("N"))
    filePath := Path.Combine(projectRoot, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    assert parsed.Errors.Count == 0
    unit := parsed.CompilationUnit
    assert unit != null
    Directory.CreateDirectory(projectRoot)
    analyzer := new Analyzer()
    errors := new List<CompilerError>()
    analysis: TypeArityAnalysis? = null
    try {
        result := analyzer.Analyze(unit, filePath, projectRoot, source)
        for error in result.Errors {
            if error.Severity == ErrorSeverity.Error {
                errors.Add(error)
            }
        }
        analysis = new TypeArityAnalysis(errors, result.Bindings, result.SemanticModel, filePath)
    } finally {
        analyzer.Dispose()
        Directory.Delete(projectRoot, true)
    }

    assert analysis != null
    return analysis
}

// ── the spelling ──────────────────────────────────────────────────────────────────────────────

test "an arity key is the bare name at arity 0 and the metadata spelling above it" {
    assert TypeArityNames.Key("Subscription", 0) == "Subscription"
    assert TypeArityNames.Key("Subscription", 1) == "Subscription`1"
    assert TypeArityNames.Key("Example.Handle", 2) == "Example.Handle`2"
}

// An arity nobody could compute must not invent a second identity: -1 answers exactly as 0 does.
test "a negative arity is the bare name, and composing a key twice is composing it once" {
    assert TypeArityNames.Key("Subscription", -1) == "Subscription"
    assert TypeArityNames.Key(TypeArityNames.Key("Subscription", 1), 1) == "Subscription`1"
    assert TypeArityNames.Key(TypeArityNames.Key("Subscription", 1), 2) == "Subscription`1"
}

test "the display name is what a person is shown, and it is the key without its suffix" {
    assert TypeArityNames.Display("Subscription`1") == "Subscription"
    assert TypeArityNames.Display("Subscription") == "Subscription"
    assert TypeArityNames.Display("Example.Handle`2") == "Example.Handle"
}

test "a name that merely contains a backtick carries no arity" {
    assert TypeArityNames.HasArity("Subscription`1") == true
    assert TypeArityNames.HasArity("Subscription") == false
    assert TypeArityNames.HasArity("Subscription`") == false
    assert TypeArityNames.HasArity("Sub`scription") == false
    assert TypeArityNames.HasArity("`1") == false
    assert TypeArityNames.Display("Sub`scription") == "Sub`scription"
}

test "the arity a key encodes is read back from it, and a bare name reads as zero" {
    assert TypeArityNames.ArityOf("Subscription`1") == 1
    assert TypeArityNames.ArityOf("Tuple`12") == 12
    assert TypeArityNames.ArityOf("Subscription") == 0
}

test "the arity list reads as a sentence, and one arity needs no conjunction" {
    one := new List<int>()
    one.Add(1)
    assert TypeArityNames.DescribeArities(one) == "1"

    two := new List<int>()
    two.Add(0)
    two.Add(2)
    assert TypeArityNames.DescribeArities(two) == "0 and 2"

    three := new List<int>()
    three.Add(0)
    three.Add(1)
    three.Add(2)
    assert TypeArityNames.DescribeArities(three) == "0, 1 and 2"

    assert TypeArityNames.DescribeArities(new List<int>()) == ""
}

// The written form is what a suggestion tells the reader to TYPE, so it must be typeable: a single
// type parameter is `T` and several are numbered.
test "the written form of an arity is N# source, not a metadata name" {
    assert TypeArityNames.WrittenForm("Subscription", 0) == "Subscription"
    assert TypeArityNames.WrittenForm("Subscription", 1) == "Subscription<T>"
    assert TypeArityNames.WrittenForm("Pair`2", 2) == "Pair<T1, T2>"
}

test "the written forms of a name read as a list of alternatives" {
    arities := new List<int>()
    arities.Add(0)
    arities.Add(1)
    assert TypeArityNames.DescribeWrittenForms("Subscription", arities) == "'Subscription' or 'Subscription<T>'"
}

// ── the language rule ─────────────────────────────────────────────────────────────────────────

test "a non-generic type and a generic type of the same name may be declared side by side" {
    errors := TypeArityAnalysisErrors("class Subscription {\n}\n\nclass Subscription<T>: Subscription {\n}\n")
    assert TypeArityErrorCodes(errors) == ""
}

// THE DEFECT THIS REPLACES: the base reference resolved to the DECLARING type, so the class read as
// its own base and NL307 fired on a declaration whose header is correct.
test "a generic type deriving from its non-generic sibling is not a cycle" {
    errors := TypeArityAnalysisErrors("class Subscription {\n}\n\nclass Subscription<T>: Subscription {\n}\n\nfunc MakeSubscription(): Subscription {\n    return new Subscription<int>()\n}\n")
    assert TypeArityErrorCodes(errors) == ""
}

test "the base reference may be namespace-qualified and still resolve to the non-generic sibling" {
    errors := TypeArityAnalysisErrors("namespace Example\n\nclass Handle {\n}\n\nclass Handle<T>: Example.Handle {\n}\n")
    assert TypeArityErrorCodes(errors) == ""
}

test "three arities of one name coexist and each reference selects its own" {
    errors := TypeArityAnalysisErrors("class Foo {\n}\n\nclass Foo<T> {\n}\n\nclass Foo<T1, T2> {\n}\n\nfunc Plain(): Foo {\n    return new Foo()\n}\n\nfunc One(): Foo<int> {\n    return new Foo<int>()\n}\n\nfunc Two(): Foo<int, string> {\n    return new Foo<int, string>()\n}\n")
    assert TypeArityErrorCodes(errors) == ""
}

test "a struct and a class of the same name at different arities coexist" {
    errors := TypeArityAnalysisErrors("struct Cell {\n    Value: int\n}\n\nclass Cell<T> {\n}\n")
    assert TypeArityErrorCodes(errors) == ""
}

// ── the duplicate is still a duplicate ────────────────────────────────────────────────────────

test "two non-generic classes of one name are NL306" {
    errors := TypeArityAnalysisErrors("class Subscription {\n}\n\nclass Subscription {\n}\n")
    assert TypeArityErrorCodes(errors) == "306"
    assert errors[0].Message == "A type named 'Subscription' already exists — each type name must be unique"
}

test "two generic classes of one name AND one arity are NL306, and the message names the arity" {
    errors := TypeArityAnalysisErrors("class Subscription<T> {\n}\n\nclass Subscription<U> {\n}\n")
    assert TypeArityErrorCodes(errors) == "306"
    assert errors[0].Message == "A type named 'Subscription<T>' already exists — a type name and its type-parameter count together must be unique"
}

// A class and a struct are one identity when they share a name and an arity: the CLR has one type
// table, not one per declaration keyword.
test "a class and a struct of one name and one arity are NL306" {
    errors := TypeArityAnalysisErrors("class Shape<T> {\n}\n\nstruct Shape<U> {\n}\n")
    assert TypeArityErrorCodes(errors) == "306"
}

// The suggestion is what tells the reader that the rule they tripped has an escape: the SAME name at
// a different type-parameter count is legal, and the file already proves it.
test "the duplicate suggestion names the other arities the file declares" {
    errors := TypeArityAnalysisErrors("class Subscription {\n}\n\nclass Subscription<T> {\n}\n\nclass Subscription<U> {\n}\n")
    assert TypeArityErrorCodes(errors) == "306"
    assert errors[0].Suggestion == "'Subscription' is also declared with 0 type parameter(s), which is allowed — two declarations may share a name only when their type-parameter counts differ. Rename this one, or give it a different type-parameter count."
}

// ── the arity that nobody declared ────────────────────────────────────────────────────────────

test "an arity no declaration has is NL207, and the report names the arities that exist" {
    errors := TypeArityAnalysisErrors("class Subscription {\n}\n\nclass Subscription<T> {\n}\n\nfunc Take(value: Subscription<int, string>) {\n}\n")
    assert TypeArityErrorCodes(errors) == "207"
    assert errors[0].Message == "No type named 'Subscription' takes 2 type argument(s); 'Subscription' is declared with 0 and 1 type parameter(s)"
    assert errors[0].Suggestion == "Write 'Subscription' or 'Subscription<T>', or declare a 'Subscription' with 2 type parameter(s)."
}

// With ONE declaration there is no list to give, so the older, shorter sentence still applies — and
// the suggestion is the spelling that would work.
test "type arguments on a type that has none is still the not-generic report" {
    errors := TypeArityAnalysisErrors("class Subscription {\n}\n\nfunc Take(value: Subscription<int>) {\n}\n")
    assert TypeArityErrorCodes(errors) == "207"
    assert errors[0].Message == "'Subscription' is not generic, but 1 type argument(s) were provided"
    assert errors[0].Suggestion == "Remove the type arguments: 'Subscription'"
}

// ── the cycle check still catches a real cycle ────────────────────────────────────────────────

test "a real base-class cycle between two declarations is still NL307" {
    errors := TypeArityAnalysisErrors("class A: B {\n}\n\nclass B: A {\n}\n")
    assert errors.Count >= 1
    assert errors[0].Code == ErrorCode.CircularDependency
}

// ── what the IDE reads ────────────────────────────────────────────────────────────────────────

// GO-TO-DEFINITION IS PER IDENTITY. The two references below are on the same NAME and must reach two
// different declarations: the return annotation the non-generic class on line 1, the construction the
// generic one on line 4.
test "go-to-definition on a name selects the declaration with the written arity" {
    source := "class Subscription {\n}\n\nclass Subscription<T>: Subscription {\n}\n\nfunc Make(): Subscription {\n    return new Subscription<int>()\n}\n"
    analysis := TypeArityAnalyze(source)
    assert TypeArityErrorCodes(analysis.Errors) == ""

    bindings := analysis.Bindings
    assert bindings != null

    annotation := bindings.GetBindingAt(analysis.FilePath, 7, 14)
    assert annotation != null
    assert annotation.Name == "Subscription"
    assert annotation.Line == 1

    construction := bindings.GetBindingAt(analysis.FilePath, 8, 16)
    assert construction != null
    assert construction.Name == "Subscription"
    assert construction.Line == 4
}

// The semantic model is keyed by identity AND reachable by the written name, which is what a hover
// over a bare spelling and a completion label both read.
test "the semantic model holds both arities, and a bare name answers with the non-generic one" {
    analysis := TypeArityAnalyze("class Subscription {\n}\n\nclass Subscription<T>: Subscription {\n}\n")

    generic := new TypeInfo()
    assert analysis.Model.TypesByIdentity.TryGetValue("Subscription`1", out generic)
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(generic) == 1

    identityPlain := new TypeInfo()
    assert analysis.Model.TypesByIdentity.TryGetValue("Subscription", out identityPlain)
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(identityPlain) == 0

    // The WRITTEN-NAME table carries one row, and the non-generic type owns it: that is what a bare
    // `Subscription` means, and what a hover over one has to show.
    plain := new TypeInfo()
    assert analysis.Model.Types.TryGetValue("Subscription", out plain)
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(plain) == 0
    assert !analysis.Model.Types.ContainsKey("Subscription`1")
}

// A generic type with no non-generic sibling still answers to its bare name, which is what keeps
// every existing hover, completion and `nlc query` answer working.
test "a lone generic type owns the written-name slot" {
    analysis := TypeArityAnalyze("class Box<T> {\n    Value: T\n}\n")

    plain := new TypeInfo()
    assert analysis.Model.Types.TryGetValue("Box", out plain)
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(plain) == 1

    identity := new TypeInfo()
    assert analysis.Model.TypesByIdentity.TryGetValue("Box`1", out identity)
    assert AnalyzerTypeReferenceFacts.GenericHeadArity(identity) == 1
}
