namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar


// WHAT THE ANALYZER MAKES OF `Box<int>.Member`, AND THE ANSWERS IT HAS TO GET RIGHT.
//
// The receiver is resolved as a TYPE through the SAME `AnalyzerTypeResolver.ResolveDeclaredType`
// that a type annotation goes through, so everything downstream is the ordinary static-member path
// a bare `Console` receiver already takes. That is the claim these contracts hold: not that a new
// resolution route works, but that the EXISTING one is reached — which is why every assertion below
// is about a diagnostic the analyzer already knew how to report, or about the type it already knew
// how to record.
//
// THE TYPES ARE DECLARED IN THE SOURCE, NOT IMPORTED. This estate runs the analyzer over a bare
// temporary directory with no reference assemblies, so `import System.Numerics` answers "I can't
// find namespace" here and `Vector<int>` never resolves — a measured fact, and the reason the
// BCL-backed half of this feature is stated in `tests/native/generic-type-receivers`, where a real
// project supplies real references and the assertions are on executed IL. What is stated here is
// the part that needs no metadata: the receiver reaches type resolution at all, and the reports it
// produces are the ones a source-declared generic already had.
//
// THE SOURCES GO THROUGH THE REAL ENTRY, `Analyzer.Analyze`, so nothing here is a hand-built tree
// that could disagree with what the parser produces.
func AgtrDiagnostics(source: string): List<CompilerError> {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-generic-receiver-" + Guid.NewGuid().ToString("N"))
    filePath := Path.Combine(projectRoot, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    assert parsed.Errors.Count == 0
    unit := parsed.CompilationUnit
    assert unit != null
    Directory.CreateDirectory(projectRoot)
    errors := new List<CompilerError>()
    analyzer := new Analyzer()
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

func AgtrMessages(source: string): string {
    errors := AgtrDiagnostics(source)
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + "\n"
        }

        text = text + errors[index].Message
        index = index + 1
    }

    return text
}

func AgtrRecordedTypeText(source: string, line: int, column: int): string {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-generic-receiver-" + Guid.NewGuid().ToString("N"))
    filePath := Path.Combine(projectRoot, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    unit := parsed.CompilationUnit
    assert unit != null
    Directory.CreateDirectory(projectRoot)
    text := ""
    analyzer := new Analyzer()
    try {
        result := analyzer.Analyze(unit, filePath, projectRoot, source)
        recorded := result.SemanticModel.LookupTypeAtPosition(line, column)
        if recorded != null {
            boxed := recorded as object
            rendered := boxed.ToString()
            if rendered != null {
                text = rendered
            }
        }
    } finally {
        analyzer.Dispose()
        Directory.Delete(projectRoot, true)
    }

    return text
}

// A one-type-parameter class with one member, which every source below shares.
func AgtrBoxSource(body: string): string {
    return "class Box<T> {\n    Value: T\n}\n\n" + body
}

test "an unknown member on a constructed type is the existing NL303, and it names the CONSTRUCTED type" {
    errors := AgtrDiagnostics(AgtrBoxSource("func Missing(): int {\n    return Box<int>.NoSuchMember\n}\n"))
    assert errors.Count == 1
    assert errors[0].Code == ErrorCode.UndefinedMember
    assert errors[0].Message == "Member 'NoSuchMember' not found on type 'Box<int>'"
}

test "a wrong type-argument COUNT is the existing arity report, at the receiver's own name" {
    errors := AgtrDiagnostics(AgtrBoxSource("func Arity(): int {\n    return Box<int, int>.Value\n}\n"))
    assert errors.Count == 1
    assert errors[0].Code == ErrorCode.InvalidTypeArgument
    assert errors[0].Message == "Generic type 'Box' takes 1 type argument(s), but 2 were provided"
    assert errors[0].Line == 6
    assert errors[0].Column == 12
}

test "a receiver whose head does not resolve is the existing unresolved-type report" {
    errors := AgtrDiagnostics("func Lanes(): int {\n    return NoSuchGenericType<int>.Count\n}\n")
    assert errors.Count >= 1
    assert errors[0].Code == ErrorCode.TypeNotFound
    assert errors[0].Message == "Type 'NoSuchGenericType' not found"
}

test "the member's type is the SUBSTITUTED one — `Box<int>.Value` is an `int`, not a `T`" {
    assert AgtrMessages(AgtrBoxSource("func Ok(): int {\n    return Box<int>.Value\n}\n")) == ""

    assert AgtrMessages(AgtrBoxSource("func Wrong(): string {\n    return Box<int>.Value\n}\n")) == "Function 'Wrong' should return string but returns int"
    assert AgtrMessages(AgtrBoxSource("func Wrong(): int {\n    return Box<string>.Value\n}\n")) == "Function 'Wrong' should return int but returns string"
}

test "an INSTANCE member reached through the type name binds rather than reporting" {
    // N# has no "instance member on a type" diagnostic — `AnalyzerMemberResolution` always includes
    // `BindingFlags.Instance`, so the non-generic `string.Length` binds through the type name too
    // (measured with the shipped CLI; it cannot be stated here because this estate has no reference
    // assemblies and `string` itself does not resolve). The contract is that the constructed
    // receiver behaves the SAME WAY rather than inventing a rule its non-generic sibling does not
    // have; the columnar backend is what refuses to emit it, with the
    // `emit.expression.generic-type-receiver` decline site.
    assert AgtrMessages(AgtrBoxSource("func Value(): int {\n    return Box<int>.Value\n}\n")) == ""
}

test "a comparison chain that only LOOKS like a receiver still type-checks as two comparisons" {
    assert AgtrMessages("func Between(value: int, lower: int, upper: int): bool {\n    return lower < value && value > upper\n}\n") == ""
    assert AgtrMessages("func Shorter(value: int, values: int[]): bool {\n    return value < values.Length\n}\n") == ""
}

test "the receiver's own position records the CONSTRUCTED type, which is what hover reads" {
    source := AgtrBoxSource("func Read(): int {\n    return Box<int>.Value\n}\n")
    // `Box` starts at column 12 of line 6 — the type NAME, which is where the receiver anchors.
    assert AgtrRecordedTypeText(source, 6, 12) == "Box<int>"
}
