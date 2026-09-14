namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// NL209 OVER REAL SOURCE, IN EVERY POSITION A SIMPLE TYPE NAME IS WRITTEN.
//
// `SimpleNamePrecedence` orders the namespaces a bare name is looked up in and
// `AnalyzerProjectTypeDiscovery.TryFindAmbiguousImportedType` decides the tie; what is asserted here
// is that the whole compiler reaches that decision from every position a developer can write the
// name in — an annotation, a `new`, a type argument, a `typeof`, an `is`, an `as`, a static receiver
// and an attribute's brackets — and that it does NOT reach it for a qualified spelling or for a name
// a lexically closer declaration already claims.
//
// THE METADATA HALF IS EXERCISED WITH A REAL REFERENCE ASSEMBLY. Two imported CLR namespaces that
// declare one spelling used to resolve first-import-wins with no diagnostic, which is the census
// finding this file closes; proving it needs an assembly that actually declares the collision, so
// one is EMITTED here and referenced by the project under test. That is also why these contracts run
// through `MultiFileCompiler` rather than a hand-built analyzer: the reference set is part of the
// question.
func ImportAmbiguityRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-import-ambiguity-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func ImportAmbiguityWrite(root: string, relativePath: string, source: string) {
    path := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, source)
}

// A LIBRARY THAT DECLARES ONE SPELLING IN TWO NAMESPACES, emitted so a consumer can reference it.
// The returned path is what the consumer's `project.yml` names.
func ImportAmbiguityEmitTwoNamespaceLibrary(root: string): string {
    libraryRoot := Path.Combine(root, "library")
    Directory.CreateDirectory(libraryRoot)
    ImportAmbiguityWrite(libraryRoot, "project.yml", "name: AmbiguityLib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    // `Marker` is an ordinary class and `TagAttribute` derives from `Attribute`, because the bracket
    // spelling has to be tested at a type that may legally be written there — and at BOTH of the
    // names `[Tag]` may mean.
    ImportAmbiguityWrite(libraryRoot, "Left.nl", "namespace AmbiguityLeft\n\nimport System\n\nclass Marker {\n    func Side(): string {\n        return \"left\"\n    }\n}\n\nclass TagAttribute: Attribute {\n    Note: string = \"left\"\n}\n")
    ImportAmbiguityWrite(libraryRoot, "Right.nl", "namespace AmbiguityRight\n\nimport System\n\nclass Marker {\n    func Side(): string {\n        return \"right\"\n    }\n}\n\nclass TagAttribute: Attribute {\n    Note: string = \"right\"\n}\n")

    config := ProjectFileParser.Parse(Path.Combine(libraryRoot, "project.yml"))
    compiler := new MultiFileCompiler(libraryRoot, config)
    compiler.AotMode = false
    outputPath := Path.Combine(libraryRoot, "AmbiguityLib.dll")
    result := compiler.CompileToIlAssembly("AmbiguityLib", outputPath, false, true)
    assert result.Success
    assert File.Exists(outputPath)
    return outputPath
}

func ImportAmbiguityErrors(root: string): IReadOnlyList<CompilerError> {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.CompileForAnalysis()
    return compiler.AllErrors
}

// The NL209 diagnostics, in report order. Every other code is left out deliberately: these fixtures
// write unused imports and unread parameters on purpose, and a lint rule's opinion about them is not
// what is under test.
func ImportAmbiguityAmbiguities(errors: IReadOnlyList<CompilerError>): List<CompilerError> {
    matches := new List<CompilerError>()
    index := 0
    while index < errors.Count {
        if errors[index].Code == ErrorCode.AmbiguousTypeReference {
            matches.Add(errors[index])
        }
        index = index + 1
    }
    return matches
}

func ImportAmbiguityMessages(errors: IReadOnlyList<CompilerError>): string {
    matches := ImportAmbiguityAmbiguities(errors)
    text := ""
    index := 0
    while index < matches.Count {
        if index > 0 {
            text = text + " | "
        }
        text = text + matches[index].Message
        index = index + 1
    }
    return text
}

// One fixture, one body: the consumer project always imports both halves of the emitted library and
// writes `body` inside a class, so each position under test differs by one line.
func ImportAmbiguityForBody(tag: string, body: string): IReadOnlyList<CompilerError> {
    root := ImportAmbiguityRoot(tag)
    libraryPath := ImportAmbiguityEmitTwoNamespaceLibrary(root)
    ImportAmbiguityWrite(root, "project.yml", "name: AmbiguityConsumer\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + libraryPath + "\n")
    ImportAmbiguityWrite(root, "Consumer.nl", "namespace AmbiguityConsumer\n\nimport AmbiguityLeft\nimport AmbiguityRight\n\nclass Consumer {\n" + body + "\n}\n")
    return ImportAmbiguityErrors(root)
}

test "two imported CLR namespaces that declare one spelling are NL209 at an annotation" {
    errors := ImportAmbiguityForBody("annotation", "    static func Read(marker: Marker): int {\n        return 1\n    }")

    assert ImportAmbiguityAmbiguities(errors).Count == 1, ImportAmbiguityMessages(errors)
    assert ImportAmbiguityMessages(errors) == "'Marker' is ambiguous between 'AmbiguityLeft.Marker' and 'AmbiguityRight.Marker'"
}

test "the same tie is reported at new, typeof, is, as and a static receiver" {
    newErrors := ImportAmbiguityForBody("new", "    static func Make(): int {\n        value := new Marker()\n        return 1\n    }")
    assert ImportAmbiguityAmbiguities(newErrors).Count == 1, ImportAmbiguityMessages(newErrors)

    typeOfErrors := ImportAmbiguityForBody("typeof", "    static func Named(): string {\n        return typeof(Marker).Name\n    }")
    assert ImportAmbiguityAmbiguities(typeOfErrors).Count == 1, ImportAmbiguityMessages(typeOfErrors)

    isErrors := ImportAmbiguityForBody("is", "    static func Test(value: object): bool {\n        return value is Marker\n    }")
    assert ImportAmbiguityAmbiguities(isErrors).Count == 1, ImportAmbiguityMessages(isErrors)

    asErrors := ImportAmbiguityForBody("as", "    static func Test(value: object): bool {\n        return (value as Marker) != null\n    }")
    assert ImportAmbiguityAmbiguities(asErrors).Count == 1, ImportAmbiguityMessages(asErrors)

    // A BARE NAME IN EXPRESSION POSITION reaches the gate through the identifier walk rather than the
    // type walk, so it is asserted separately: the two owners share one decision and must not drift.
    receiverErrors := ImportAmbiguityForBody("receiver", "    static func Read(): int {\n        return Marker.Missing\n    }")
    assert ImportAmbiguityAmbiguities(receiverErrors).Count == 1, ImportAmbiguityMessages(receiverErrors)
}

test "an attribute's bracket spelling reports the tie in both of its legal forms" {
    // `[Tag]` may legally mean `Tag` or `TagAttribute`, and an attribute is looked up through a
    // deliberately POSITIONLESS probe so the validator can own its own "not found" wording. That
    // silence used to swallow the tie as well.
    bareErrors := ImportAmbiguityForBody("attribute-bare", "    [Tag]\n    static func Tagged(): int {\n        return 1\n    }")
    assert ImportAmbiguityAmbiguities(bareErrors).Count == 1, ImportAmbiguityMessages(bareErrors)
    assert ImportAmbiguityMessages(bareErrors) == "'Tag' is ambiguous between 'AmbiguityLeft.TagAttribute' and 'AmbiguityRight.TagAttribute'"

    suffixedErrors := ImportAmbiguityForBody("attribute-suffixed", "    [TagAttribute]\n    static func Tagged(): int {\n        return 1\n    }")
    assert ImportAmbiguityAmbiguities(suffixedErrors).Count == 1, ImportAmbiguityMessages(suffixedErrors)
    assert ImportAmbiguityMessages(suffixedErrors) == "'TagAttribute' is ambiguous between 'AmbiguityLeft.TagAttribute' and 'AmbiguityRight.TagAttribute'"
}

test "a qualified spelling is never ambiguous, however many imports supply the simple name" {
    errors := ImportAmbiguityForBody("qualified", "    static func Read(marker: AmbiguityLeft.Marker): string {\n        return marker.Side()\n    }")

    assert ImportAmbiguityAmbiguities(errors).Count == 0, ImportAmbiguityMessages(errors)
}

test "a declaration in the file's own namespace wins outright over two colliding imports" {
    root := ImportAmbiguityRoot("lexical")
    libraryPath := ImportAmbiguityEmitTwoNamespaceLibrary(root)
    ImportAmbiguityWrite(root, "project.yml", "name: AmbiguityConsumer\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + libraryPath + "\n")
    ImportAmbiguityWrite(root, "Own.nl", "namespace AmbiguityConsumer\n\nclass Marker {\n    func Side(): string {\n        return \"own\"\n    }\n}\n")
    ImportAmbiguityWrite(root, "Consumer.nl", "namespace AmbiguityConsumer\n\nimport AmbiguityLeft\nimport AmbiguityRight\n\nclass Consumer {\n    static func Read(): string {\n        return new Marker().Side()\n    }\n}\n")

    errors := ImportAmbiguityErrors(root)
    assert ImportAmbiguityAmbiguities(errors).Count == 0, ImportAmbiguityMessages(errors)
}

// A CROSS-FILE CONSTRUCTOR PARAMETER IS READ IN THE FILE THAT DECLARES IT.
//
// `new Holder(...)` makes the analyzer read `Holder`'s constructors to type its arguments, and those
// parameter types are `TypeReference`s out of ANOTHER file's syntax tree. Resolving them through the
// CURRENT file's scope got two things wrong at once: the declaring file's spelling was looked up
// through the CONSUMER's imports, so a namespace only the consumer imported could claim it, and the
// NL209 that followed was stamped at the declaring file's line and column against the consumer's
// path — a caret pointing into the middle of a line that never spells the name.
test "a cross-file constructor parameter is not resolved through the calling file's imports" {
    root := ImportAmbiguityRoot("cross-file-constructor")
    ImportAmbiguityWrite(root, "project.yml", "name: AmbiguityConsumer\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    // `Models.nl` imports NEITHER colliding namespace: its `Timer` is its own, unambiguously.
    ImportAmbiguityWrite(root, "Models.nl", "namespace AmbiguityModels\n\nclass Timer {\n    Ticks: int = 0\n}\n\nclass Holder {\n    Kept: Timer\n\n    public constructor(timer: Timer) {\n        Kept = timer\n    }\n}\n")
    // The CONSUMER imports `System.Threading`, which declares its own `Timer`. That import is the
    // consumer's business and must not reach into `Models.nl`'s constructor signature.
    ImportAmbiguityWrite(root, "Consumer.nl", "namespace AmbiguityConsumer\n\nimport System.Threading\nimport AmbiguityModels\n\nclass Consumer {\n    static func Make(): Holder {\n        return new Holder(new AmbiguityModels.Timer())\n    }\n\n    static func Delay(token: CancellationToken): bool {\n        return token.IsCancellationRequested\n    }\n}\n")

    errors := ImportAmbiguityErrors(root)
    assert ImportAmbiguityAmbiguities(errors).Count == 0, ImportAmbiguityMessages(errors)
}

// A MISMATCH BETWEEN TWO TYPES THAT RENDER THE SAME.
//
// Once both halves of a collision are reachable, a diagnostic contrasting them could print the same
// simple name twice — "Cannot pass `Marker` as argument for parameter `marker` of type `Marker`" —
// which states a contradiction and tells the reader nothing. `TypeMismatchDisplay` renders the two
// names as a PAIR and spells both in full when they would otherwise be identical.
func ImportAmbiguityMismatchMessages(errors: IReadOnlyList<CompilerError>): List<CompilerError> {
    matches := new List<CompilerError>()
    index := 0
    while index < errors.Count {
        if errors[index].Code == ErrorCode.TypeMismatch {
            matches.Add(errors[index])
        }
        index = index + 1
    }
    return matches
}

func ImportAmbiguitySingleMismatch(errors: IReadOnlyList<CompilerError>): CompilerError {
    matches := ImportAmbiguityMismatchMessages(errors)
    assert matches.Count == 1, ImportAmbiguityMessages(errors)
    return matches[0]
}

test "a type mismatch between two types of one simple name spells both in full" {
    errors := ImportAmbiguityForBody(
        "mismatch-argument",
        "    static func Take(marker: AmbiguityLeft.Marker): string {\n        return marker.Side()\n    }\n\n    static func Pass(marker: AmbiguityRight.Marker): string {\n        return Take(marker)\n    }"
    )

    mismatch := ImportAmbiguitySingleMismatch(errors)
    assert mismatch.Message == "Cannot pass `AmbiguityRight.Marker` as argument for parameter `marker` of type `AmbiguityLeft.Marker`", mismatch.Message
    assert mismatch.ActualType == "AmbiguityRight.Marker", mismatch.ActualType ?? "<null>"
    assert mismatch.ExpectedType == "AmbiguityLeft.Marker", mismatch.ExpectedType ?? "<null>"
}

test "the qualification reaches inside a generic argument, and is left off when the names already differ" {
    inside := ImportAmbiguityForBody(
        "mismatch-generic",
        "    static func Take(markers: System.Collections.Generic.List<AmbiguityLeft.Marker>): int {\n        return markers.Count\n    }\n\n    static func Pass(markers: System.Collections.Generic.List<AmbiguityRight.Marker>): int {\n        return Take(markers)\n    }"
    )

    // The HEAD keeps the spelling the file wrote — here the fully qualified one — and the ARGUMENT is
    // what the pair had to spell out, because that is where the two types differ.
    nested := ImportAmbiguitySingleMismatch(inside)
    assert nested.ExpectedType == "System.Collections.Generic.List<AmbiguityLeft.Marker>", nested.ExpectedType ?? "<null>"
    assert nested.ActualType == "System.Collections.Generic.List<AmbiguityRight.Marker>", nested.ActualType ?? "<null>"

    // NOTHING IS ADDED WHEN IT WOULD NOT HELP. Two names that already differ are printed exactly as
    // they were, so the rule costs nothing at the diagnostics it does not answer.
    plain := ImportAmbiguityForBody(
        "mismatch-plain",
        "    static func Take(count: int): int {\n        return count\n    }\n\n    static func Pass(marker: AmbiguityLeft.Marker): int {\n        return Take(marker)\n    }"
    )

    unqualified := ImportAmbiguitySingleMismatch(plain)
    assert unqualified.ExpectedType == "int", unqualified.ExpectedType ?? "<null>"
    assert unqualified.ActualType == "Marker", unqualified.ActualType ?? "<null>"
}

test "an assignment, a return and a variable annotation qualify the same pair" {
    assignment := ImportAmbiguityForBody(
        "mismatch-assignment",
        "    static func Store(right: AmbiguityRight.Marker): string {\n        target: AmbiguityLeft.Marker = new AmbiguityLeft.Marker()\n        target = right\n        return target.Side()\n    }"
    )
    assignmentError := ImportAmbiguitySingleMismatch(assignment)
    assert assignmentError.Message == "Type mismatch in assignment — expected 'AmbiguityLeft.Marker' but got 'AmbiguityRight.Marker'", assignmentError.Message

    returned := ImportAmbiguityForBody(
        "mismatch-return",
        "    static func Convert(right: AmbiguityRight.Marker): AmbiguityLeft.Marker {\n        return right\n    }"
    )
    returnedError := ImportAmbiguitySingleMismatch(returned)
    assert returnedError.ExpectedType == "AmbiguityLeft.Marker", returnedError.ExpectedType ?? "<null>"
    assert returnedError.ActualType == "AmbiguityRight.Marker", returnedError.ActualType ?? "<null>"

    declared := ImportAmbiguityForBody(
        "mismatch-variable",
        "    static func Bind(right: AmbiguityRight.Marker): string {\n        held: AmbiguityLeft.Marker = right\n        return held.Side()\n    }"
    )
    declaredError := ImportAmbiguitySingleMismatch(declared)
    assert declaredError.Message == "Variable 'held' is typed as 'AmbiguityLeft.Marker', but the value is 'AmbiguityRight.Marker'", declaredError.Message
}
