namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Columnar


// PRODUCT-PATH CONTRACTS FOR THE FIVE EXPLICIT-INTERFACE DIAGNOSTICS.
//
// Real N# source through the same `Analyzer` entry point `nlc check` drives, so each row pins the
// diagnostic at its public boundary — code, message, and the span an editor underlines — rather than
// pinning a helper that nothing in the product calls that way.
//
// EVERY ROW CARRIES ITS CONTROL. A rule that fires on everything is as wrong as one that fires on
// nothing, and four of these five are about a SPELLING, where the difference between right and wrong
// is a few characters. So each `assert` on a code sits beside a near-identical source that reports
// nothing.
func ExplicitInterfaceErrors(source: string): List<CompilerError> {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-explicit-interface-" + Guid.NewGuid().ToString("N"))
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

func ExplicitInterfaceCodes(errors: List<CompilerError>): string {
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

// Two interfaces and nothing else, so every source below differs only in the member it declares.
func ExplicitInterfacePreamble(): string {
    return "interface IPing {\n" + "    func Ping(): int\n" + "}\n" + "interface IPong {\n" + "    func Pong(): int\n" + "}\n"
}

test "NL345: a qualifier naming an interface the type does not implement" {
    errors := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing {\n" + "    func IPing.Ping(): int => 1\n" + "    func IPong.Pong(): int => 2\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(errors) == "345", ExplicitInterfaceCodes(errors)
    assert errors[0].Message == "'Probe' does not implement 'IPong', so it cannot implement 'IPong.Pong' explicitly"
    assert errors[0].Line == 9
    assert errors[0].Column == 5
    assert errors[0].Length == 10

    // THE CONTROL. The same member, with the interface in the list.
    clean := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing, IPong {\n" + "    func IPing.Ping(): int => 1\n" + "    func IPong.Pong(): int => 2\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(clean) == "", ExplicitInterfaceCodes(clean)
}

test "NL346: a member name the named interface does not declare" {
    errors := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing {\n" + "    func IPing.Pung(): int => 1\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(errors) == "346,325", ExplicitInterfaceCodes(errors)
    assert errors[0].Message == "'IPing' declares no member named 'Pung'"
    assert errors[0].Line == 8
    assert errors[0].Column == 5
    assert errors[0].Length == 10

    // THE CONTROL — one character apart, and the `NL325` that rode along above goes with it, because
    // the slot really is filled once the name is right.
    clean := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing {\n" + "    func IPing.Ping(): int => 1\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(clean) == "", ExplicitInterfaceCodes(clean)
}

test "NL347: two spellings of one interface naming one slot" {
    errors := ExplicitInterfaceErrors(
        "namespace Sample\n" + ExplicitInterfacePreamble() + "class Probe: IPing {\n" + "    func IPing.Ping(): int => 1\n" + "    func Sample.IPing.Ping(): int => 2\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(errors) == "347", ExplicitInterfaceCodes(errors)
    assert errors[0].Message == "'Probe' implements the interface member 'Ping' of 'IPing' explicitly more than once"

    // THE CONTROL, AND IT IS THE POINT OF THE RULE'S SHAPE. Two members written with the SAME name
    // are `NL306`'s business, whatever those names are, so this rule deliberately does not also fire
    // on them — one mistake, one diagnostic.
    sameSpelling := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing {\n" + "    func IPing.Ping(): int => 1\n" + "    func IPing.Ping(): int => 2\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(sameSpelling) == "306", ExplicitInterfaceCodes(sameSpelling)
}

test "NL348: a modifier word on a member that has no accessibility to state" {
    errors := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing {\n" + "    public func IPing.Ping(): int => 1\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(errors) == "348", ExplicitInterfaceCodes(errors)
    assert errors[0].Message == "'public' cannot be written on the explicit interface implementation 'IPing.Ping'"

    // EVERY WORD THE FORM REFUSES, not just the one a reader reaches for first. `static` is refused
    // for its own reason: a static method occupies no virtual slot for a MethodImpl row to name.
    staticWord := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing {\n" + "    static func IPing.Ping(): int => 1\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(staticWord) == "348", ExplicitInterfaceCodes(staticWord)
    assert staticWord[0].Message == "'static' cannot be written on the explicit interface implementation 'IPing.Ping'"

    // THE CONTROL. The same member with the word removed is clean — so the rule is about the word and
    // not about the qualified name.
    clean := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing {\n" + "    func IPing.Ping(): int => 1\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(clean) == "", ExplicitInterfaceCodes(clean)
}

test "NL349: a generic interface named without the arguments the list writes" {
    generic := "interface IBox<T> {\n" + "    func Unwrap(): T\n" + "}\n"
    errors := ExplicitInterfaceErrors(
        generic + "class Probe: IBox<string> {\n" + "    func IBox.Unwrap(): string => \"x\"\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(errors) == "349", ExplicitInterfaceCodes(errors)
    assert errors[0].Message == "'IBox' does not name the interface the way 'Probe' implements it"

    // THE CONTROL. The same member written closed, exactly as the implements list writes it.
    clean := ExplicitInterfaceErrors(
        generic + "class Probe: IBox<string> {\n" + "    func IBox<string>.Unwrap(): string => \"x\"\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(clean) == "", ExplicitInterfaceCodes(clean)
}

// WITHOUT THIS, a correctly written explicit implementation would read as an unimplemented
// interface: the completeness walk asks the member table for the slot's own name, and an explicit
// implementation is deliberately not there — its key is the qualified spelling.
test "an explicit implementation discharges the interface obligation" {
    errors := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing, IPong {\n" + "    func IPing.Ping(): int => 1\n" + "    func IPong.Pong(): int => 2\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(errors) == "", ExplicitInterfaceCodes(errors)

    // And it discharges ONLY what it names: drop one and `NL325` returns.
    partialErrors := ExplicitInterfaceErrors(
        ExplicitInterfacePreamble() + "class Probe: IPing, IPong {\n" + "    func IPing.Ping(): int => 1\n" + "}\n"
    )

    assert ExplicitInterfaceCodes(partialErrors) == "325", ExplicitInterfaceCodes(partialErrors)
}
