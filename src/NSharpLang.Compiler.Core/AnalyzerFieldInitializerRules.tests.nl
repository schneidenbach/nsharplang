namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// THE CONTRACT FOR NL328, END TO END OVER REAL SOURCE.
//
// An instance field initializer runs ahead of the base constructor call, so it may name no part of
// the instance. The rule has to hold for the three spellings that reach one — `this`, `base`, and a
// BARE instance member — and it has to stay off the four shapes that look similar and are not: a
// static field's initializer, a static member named from an instance initializer, a primary
// constructor parameter, and a lambda parameter that shadows a member's name.
func FieldInitializerAnalysisErrors(source: string): List<CompilerError> {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-field-initializer-" + Guid.NewGuid().ToString("N"))
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

func FieldInitializerErrorCodes(errors: List<CompilerError>): string {
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

test "an instance field initializer that names a bare instance field is NL328 at the reference" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "class Dog {\n" + "    Name: string = \"rex\"\n" + "    Greeting: string = Name\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == "328"
    assert errors[0].Line == 5
    assert errors[0].Message.Contains("Name")
    assert errors[0].Message.Contains("Greeting")
}

test "an instance field initializer that uses this is NL328" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "class Dog {\n" + "    Legs: int = 4\n" + "    Tag: int = this.Legs\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == "328"
    assert errors[0].Message.Contains("this")
}

test "an instance field initializer that calls an instance method is NL328 at the callee" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "class Dog {\n" + "    Size: int = Measure()\n" + "\n" + "    func Measure(): int => 2\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == "328"
    assert errors[0].Message.Contains("Measure")
}

test "a static field initializer may name the type's static members and reports nothing" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "class Dog {\n" + "    static Base: int = 2\n" + "    static Doubled: int = Base * 2\n" + "    static Measured: int = Measure()\n" + "\n" + "    static func Measure(): int => 3\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == ""
}

test "an instance field initializer may name the type's static members" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "class Dog {\n" + "    static DefaultName: string = \"rex\"\n" + "    Greeting: string = DefaultName\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == ""
}

test "a primary constructor parameter is not a member, so an initializer over one reports nothing" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "class Box(value: int) {\n" + "    Value: int = value\n" + "    Doubled: int = value * 2\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == ""
}

test "a lambda parameter shadows a member of the same name inside an initializer" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "import System\n" + "\n" + "class Dog {\n" + "    x: int = 1\n" + "    Pick: Func<int, int> = x => x + 1\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == ""
}

test "an instance field initializer on a struct is NL329 and names the struct" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "struct Point {\n" + "    X: double = 1.0\n" + "    Y: double\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == "329"
    assert errors[0].Message.Contains("Point")
    assert errors[0].Message.Contains("X")
}

test "a static field initializer on a struct is accepted" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "struct Point {\n" + "    static Count: int = 3\n" + "    X: double\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == ""
}

test "an instance field initializer on a record struct is NL329 too" {
    errors := FieldInitializerAnalysisErrors(
        "namespace Probe\n" + "\n" + "record struct Pair {\n" + "    Left: int = 1\n" + "    Right: int\n" + "}\n"
    )

    assert FieldInitializerErrorCodes(errors) == "329"
    assert errors[0].Message.Contains("Pair")
}
