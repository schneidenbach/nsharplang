namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// Product-path semantic contracts for `init` and `required`. These parse real N# source and drive
// the same Analyzer entry point `nlc check` uses, so the diagnostics are pinned at their public
// boundary rather than as isolated modifier-bit helpers.
func InitRequiredAnalysisErrors(source: string): List<CompilerError> {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-init-required-" + Guid.NewGuid().ToString("N"))
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

func InitRequiredErrorCodes(errors: List<CompilerError>): string {
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

test "an init-only member cannot be assigned after construction" {
    errors := InitRequiredAnalysisErrors(
        "class Configuration {\n" + "    init Name: string\n" + "}\n" + "func Rename(value: Configuration) {\n" + "    value.Name = \"changed\"\n" + "}\n"
    )

    assert InitRequiredErrorCodes(errors) == "343", InitRequiredErrorCodes(errors)
    assert errors[0].Message == "'Name' is declared 'init' — it can only be set while the object is being created, so it can't be assigned with '='"
    assert errors[0].Line == 5
    assert errors[0].Column == 11
    assert errors[0].Length == 4
}

test "the declaring constructor and a derived constructor may assign an init-only member" {
    errors := InitRequiredAnalysisErrors(
        "class Base {\n" + "    init Name: string\n" + "    constructor(name: string) { Name = name }\n" + "}\n" + "class Derived: Base {\n" + "    constructor(name: string): base(\"base\") { Name = name }\n" + "}\n"
    )

    assert InitRequiredErrorCodes(errors) == "", InitRequiredErrorCodes(errors)
}

test "a creation reports every required member its initializer omits" {
    errors := InitRequiredAnalysisErrors(
        "class User {\n" + "    required Id: string\n" + "    required Name: string\n" + "}\n" + "func Make(): User {\n" + "    return new User { Id: \"u-1\" }\n" + "}\n"
    )

    assert InitRequiredErrorCodes(errors) == "344", InitRequiredErrorCodes(errors)
    assert errors[0].Message == "'Name' is required by 'User', and this creation never sets it"
    assert errors[0].Line == 6
    assert errors[0].Column == 16
    assert errors[0].Length == 4
}

test "a creation that names every required member is accepted" {
    errors := InitRequiredAnalysisErrors(
        "class User {\n" + "    required Id: string\n" + "    required Name: string\n" + "}\n" + "func Make(): User {\n" + "    return new User { Id: \"u-1\", Name: \"Ada\" }\n" + "}\n"
    )

    assert InitRequiredErrorCodes(errors) == "", InitRequiredErrorCodes(errors)
}

test "a required member inherited from a base type is demanded by a derived creation" {
    errors := InitRequiredAnalysisErrors(
        "class Node { required Key: string }\n" + "class Leaf: Node { Payload: int }\n" + "func Make(): Leaf { return new Leaf { Payload: 3 } }\n"
    )

    assert InitRequiredErrorCodes(errors) == "344", InitRequiredErrorCodes(errors)
    assert errors[0].Message == "'Key' is required by 'Leaf', and this creation never sets it"
}

test "init and required are instance creation promises and are refused on static members" {
    errors := InitRequiredAnalysisErrors(
        "class Invalid {\n" + "    static init Name: string\n" + "    static required Code: int\n" + "}\n"
    )

    assert InitRequiredErrorCodes(errors) == "311,311", InitRequiredErrorCodes(errors)
    assert errors[0].Message.Contains("'init static'")
    assert errors[1].Message.Contains("'required static'")
}

test "required members on a closed source generic are still demanded" {
    errors := InitRequiredAnalysisErrors(
        "class Box<T> { required Value: T }\n" + "func Make(): Box<string> { return new Box<string>() }\n"
    )

    assert InitRequiredErrorCodes(errors) == "344", InitRequiredErrorCodes(errors)
    assert errors[0].Message.Contains("Value")
}

test "only the selected same-arity constructor may discharge required members" {
    errors := InitRequiredAnalysisErrors(
        "import System.Diagnostics.CodeAnalysis\n" + "class Selected {\n" + "    required Name: string\n" + "    [SetsRequiredMembers]\n" + "    constructor(name: string) { Name = name }\n" + "    constructor(value: int) { Name = value.ToString() }\n" + "}\n" + "func Missing(): Selected { return new Selected(1) }\n" + "func Valid(): Selected { return new Selected(\"ok\") }\n"
    )

    codes := InitRequiredErrorCodes(errors)
    assert codes.EndsWith("344"), codes
}

test "constructor selection uses ordinary reference specificity before reading SetsRequiredMembers" {
    errors := InitRequiredAnalysisErrors(
        "import System.Diagnostics.CodeAnalysis\n" + "class Animal {}\n" + "class Dog: Animal {}\n" + "class Poodle: Dog {}\n" + "class Selected {\n" + "    required Name: string\n" + "    constructor(value: Animal) { Name = \"animal\" }\n" + "    [SetsRequiredMembers]\n" + "    constructor(value: Dog) { Name = \"dog\" }\n" + "}\n" + "func Make(): Selected { return new Selected(new Poodle()) }\n"
    )

    codes := InitRequiredErrorCodes(errors)
    assert !codes.Contains("344"), codes
}

test "constructor selection uses ordinary numeric specificity before reading SetsRequiredMembers" {
    errors := InitRequiredAnalysisErrors(
        "import System.Diagnostics.CodeAnalysis\n" + "class Selected {\n" + "    required Name: string\n" + "    [SetsRequiredMembers]\n" + "    constructor(value: long) { Name = \"long\" }\n" + "    constructor(value: float) { Name = \"float\" }\n" + "}\n" + "func Make(): Selected { return new Selected(1) }\n"
    )

    codes := InitRequiredErrorCodes(errors)
    assert !codes.Contains("344"), codes
}

test "annotated constructors discharge required members on generic source structs and records" {
    errors := InitRequiredAnalysisErrors(
        "import System.Diagnostics.CodeAnalysis\n" + "struct Packet<T> {\n" + "    required Value: T\n" + "    [SetsRequiredMembers]\n" + "    constructor(value: T) { Value = value }\n" + "}\n" + "record Receipt {\n" + "    required Code: string\n" + "    [SetsRequiredMembers]\n" + "    constructor(code: string) { Code = code }\n" + "}\n" + "func PacketValue(): Packet<int> { return new Packet<int>(1) }\n" + "func ReceiptValue(): Receipt { return new Receipt(\"r\") }\n"
    )

    codes := InitRequiredErrorCodes(errors)
    assert !codes.Contains("344"), codes
}
