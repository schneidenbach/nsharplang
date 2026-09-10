namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// THE CONTRACTS FOR `this` AND `base` AS EXPRESSIONS, END TO END OVER REAL SOURCE.
//
// Two rules are pinned here and they are the two halves of one question — "is there an object this
// member was called on?".
//
// (1) WHEN THERE IS ONE, `base.` REACHES THE BASE. `base.Method()` from an override resolves to the
// member the base declares (not to the override, which would recurse), `base.Property` reads the
// base's property, and a name the base does not declare is NL303 about the BASE's type. Nothing
// about `base` itself is reported in any of those.
//
// (2) WHEN THERE IS NONE, NL327 SAYS SO AT THE WORD. A `static` member and a top-level function are
// the two places with no receiver, and the answer is a fact about the enclosing MEMBER rather than
// about the expression: a lambda inherits its enclosing member's answer, and a property accessor is
// a member like any other. That is why these are written as source rather than as ambient-context
// pokes — the ambient slot and the scope stack each look right on their own and only disagree
// together.
func CurrentInstanceAnalysisErrors(source: string): List<CompilerError> {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-current-instance-" + Guid.NewGuid().ToString("N"))
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

func CurrentInstanceErrorCodes(errors: List<CompilerError>): string {
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

// The base source every contract below layers a subclass onto: a class with a virtual method, a
// virtual method that takes an argument and a property, so the three shapes `base.` can name are all
// available.
func CurrentInstanceBaseClassSource(): string {
    return "namespace Probe\n" + "\n" + "class Animal {\n" + "    readonly animalName: string\n" + "\n" + "    public constructor(animalName: string) {\n" + "        this.animalName = animalName\n" + "    }\n" + "\n" + "    Name: string => animalName\n" + "\n" + "    public virtual func Speak(): string {\n" + "        return \"generic\"\n" + "    }\n" + "\n" + "    public virtual func Describe(prefix: string): string {\n" + "        return prefix + animalName\n" + "    }\n" + "}\n" + "\n"
}

// ── when there is a current instance ──────────────────────────────────────────────────────────

test "base.Method() from an override resolves against the base and reports nothing" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "class Dog: Animal {\n" + "    public constructor(name: string): base(name) {\n" + "    }\n" + "\n" + "    public override func Speak(): string {\n" + "        return \"woof \" + base.Speak()\n" + "    }\n" + "\n" + "    public override func Describe(prefix: string): string {\n" + "        return base.Describe(prefix) + \"!\"\n" + "    }\n" + "}\n"
    )

    assert CurrentInstanceErrorCodes(errors) == ""
}

test "base.Property reads the base's property, and base. works from a non-overriding method too" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "class Dog: Animal {\n" + "    public constructor(name: string): base(name) {\n" + "    }\n" + "\n" + "    func BaseName(): string {\n" + "        return base.Name\n" + "    }\n" + "\n" + "    func BaseSpeak(): string {\n" + "        return base.Speak()\n" + "    }\n" + "}\n"
    )

    assert CurrentInstanceErrorCodes(errors) == ""
}

// `base` itself was fine; the NAME after it was not — so this is NL303 about the base's type, not
// NL327, and the message names `Animal` rather than `Dog`.
test "a member the base does not declare is NL303 naming the base type" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "class Dog: Animal {\n" + "    public constructor(name: string): base(name) {\n" + "    }\n" + "\n" + "    func Missing(): string {\n" + "        return base.Bark()\n" + "    }\n" + "}\n"
    )

    assert CurrentInstanceErrorCodes(errors) == "303"
    assert errors[0].Message.Contains("Bark")
    assert errors[0].Message.Contains("Animal")
}

test "this inside an instance member, an instance property and a lambda within one is accepted" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "import System\n" + "\n" + "class Dog: Animal {\n" + "    readonly tag: int = 3\n" + "\n" + "    public constructor(name: string): base(name) {\n" + "    }\n" + "\n" + "    Tag: int => this.tag\n" + "\n" + "    func Later(): Action {\n" + "        return () => {\n" + "            _ = this.tag\n" + "        }\n" + "    }\n" + "}\n"
    )

    assert CurrentInstanceErrorCodes(errors) == ""
}

// ── when there is none ────────────────────────────────────────────────────────────────────────

test "this and base in a static method are both NL327" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "class Dog: Animal {\n" + "    public constructor(name: string): base(name) {\n" + "    }\n" + "\n" + "    static func FromThis(): string {\n" + "        return this.Name\n" + "    }\n" + "\n" + "    static func FromBase(): string {\n" + "        return base.Speak()\n" + "    }\n" + "}\n"
    )

    assert CurrentInstanceErrorCodes(errors) == "327,327"
    assert errors[0].Message == "'this' cannot be used in a static member"
    assert errors[1].Message == "'base' cannot be used in a static member"
}

test "base in a top-level function is NL327 and says the function is outside every type" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "func Loose(): string {\n" + "    return base.Speak()\n" + "}\n"
    )

    assert CurrentInstanceErrorCodes(errors) == "327"
    assert errors[0].Message == "'base' cannot be used outside a type"
}

// The receiver is a fact about the enclosing MEMBER, so a lambda answers with the member's answer
// rather than with its own (it has no declaration of its own to read a `static` modifier off).
test "a lambda inside a static member inherits the member's missing receiver" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "import System\n" + "\n" + "class Dog: Animal {\n" + "    public constructor(name: string): base(name) {\n" + "    }\n" + "\n" + "    static func Later(): Action {\n" + "        return () => {\n" + "            _ = base.Speak()\n" + "        }\n" + "    }\n" + "}\n"
    )

    assert CurrentInstanceErrorCodes(errors) == "327"
    assert errors[0].Message == "'base' cannot be used in a static member"
}

// A property has no `FunctionDeclaration` to read the modifier off either, so its expression body is
// the second shape a derived answer would have missed.
test "a static property's expression body has no receiver" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "class Dog: Animal {\n" + "    public constructor(name: string): base(name) {\n" + "    }\n" + "\n" + "    static Label: string => this.Name\n" + "}\n"
    )

    assert CurrentInstanceErrorCodes(errors) == "327"
    assert errors[0].Message == "'this' cannot be used in a static member"
}

// ── what the report says ──────────────────────────────────────────────────────────────────────

test "NL327 underlines the keyword and carries the explanation, the hint, the advice and the page" {
    errors := CurrentInstanceAnalysisErrors(
        CurrentInstanceBaseClassSource() + "class Dog: Animal {\n" + "    public constructor(name: string): base(name) {\n" + "    }\n" + "\n" + "    static func FromBase(): string {\n" + "        return base.Speak()\n" + "    }\n" + "}\n"
    )

    assert errors.Count == 1
    report := errors[0]
    assert report.Code == ErrorCode.NoCurrentInstance
    assert report.Length == 4
    assert report.HumanExplanation == "`base` names the object the current member was called on, viewed as its base class, and `FromBase` runs without one:"
    assert report.ContextualHint != null
    hint := report.ContextualHint ?? ""
    assert hint.Contains("A `static` member belongs to the type itself")
    assert report.Suggestion == "Drop `static` from `FromBase`, or use a value the member already has instead of `base`."
    assert report.DocsUrl == "https://schneidenbach.github.io/nsharplang/docs/errors/NL327"
}

test "NL327 is a semantic diagnostic the catalog publishes" {
    assert DiagnosticCatalog.AllCodes().Contains("NL327")
    assert DiagnosticCatalog.GetCompilerCategory(ErrorCode.NoCurrentInstance) == DiagnosticCategory.Semantic
}
