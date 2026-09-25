namespace Census.FreeFunctions.Tests

import System
import System.Collections.Generic
import System.IO
import System.Runtime.Loader
import Census.FreeFunctions.Consumer
import NSharpLang.Compiler


// A FREE FUNCTION IS CALLED ACROSS AN ASSEMBLY BOUNDARY BY ITS BARE NAME.
//
// A namespace's free functions are its members wherever they were compiled, exactly as its types
// are: a referenced N# assembly's `<namespace>.Program` holder (the global `Program` for a file with
// no namespace, `<Program>` where the namespace declares its own `Program`) is asked for a bare call
// at its namespace's place in `SimpleNamePrecedence` -- the caller's own namespace, each enclosing one
// out to the global namespace, then the imports -- in the analyzer (`AnalyzerProjectDiscovery.
// TryResolveVisibleFunction`) and in the emitter (`ColumnarFreeFunctionScope` with
// `ColumnarExternalFreeFunctions`) alike. Before this, a referenced free function was unreachable:
// NL412 in the analyzer and `emit.call.bare-unresolved` in the emitter. Carving `Compiler.Syntax`,
// whose parser kernels are global free functions, out of `Compiler.Core` found it: every Core call
// into them declined.
//
// `Consumer.nl` is this assembly's own source, compiled WITH analysis by `nlc test`; the first row
// runs it. The second compiles the same files again EMIT-ONLY -- the path `Compiler.Core` itself is
// built through -- against the same built library, runs that, and demands the same answer. The rest
// analyse small consumers written for the row.
func FreeRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            break
        }
        current = parent
    }

    throw new InvalidOperationException("Could not locate the N# repository root from " + AppContext.BaseDirectory + ".")
}

func FreeExpectedDigest(): string {
    return "12|3 units|4 items|True41|imported|yielded|enclosing-referenced|22/6|10|18"
}

// The built library this assembly was compiled against, so every compilation below reads the same
// referenced free functions this assembly's own calls bound.
func FreeLibraryPath(): string {
    return typeof(GlobalTally).Assembly.Location
}

func FreeRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-external-free-functions-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    File.WriteAllText(Path.Combine(root, "project.yml"), "name: FreeFunctions" + tag + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + FreeLibraryPath() + "\n")
    return root
}

func FreeCompile(root: string, name: string, analyse: bool): MultiFileCompilationResult {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    return compiler.CompileToIlAssembly(name, Path.Combine(Path.Combine(root, "out"), name + ".dll"), analyse, analyse)
}

func FreeText(errors: IEnumerable<CompilerError>): string {
    text := ""
    for error in errors {
        text = text + error.DiagnosticId + " " + (error.FileName ?? "") + ":" + error.Line.ToString() + " " + error.Message + "\n"
    }
    return text
}

func FreeCodes(errors: IEnumerable<CompilerError>, code: string): int {
    count := 0
    for error in errors {
        if error.DiagnosticId == code {
            count = count + 1
        }
    }
    return count
}

// Runs a static string method of an emitted assembly in a collectible context.
func FreeRun(outputPath: string, typeName: string, methodName: string): string {
    context := new AssemblyLoadContext("nsharp-external-free-functions-" + Guid.NewGuid().ToString("N"), true)
    try {
        emitted := context.LoadFromAssemblyPath(outputPath)
        owner := emitted.GetType(typeName)
        if owner == null {
            return "<no type " + typeName + ">"
        }
        method := owner.GetMethod(methodName)
        if method == null {
            return "<no method " + methodName + ">"
        }
        return (method.Invoke(null, new object?[](0)) as string) ?? "<null>"
    } finally {
        context.Unload()
    }
}

test "a bare call and a method group reach a referenced assembly's global, enclosing, imported and yielded free functions" {
    assert FreeFunctionUses.Digest() == FreeExpectedDigest(), FreeFunctionUses.Digest()
}

test "the analysis-free path binds the same referenced free functions and computes the same answer" {
    root := FreeRoot("EmitOnly")
    consumerDirectory := Path.Combine(Path.Combine(FreeRepositoryRoot(), "tests", "native"), "census-external-free-functions")
    File.Copy(Path.Combine(consumerDirectory, "Consumer.nl"), Path.Combine(root, "Consumer.nl"))

    result := FreeCompile(root, "FreeFunctionsEmitOnly", false)
    assert result.Success, FreeText(result.Errors)
    digest := FreeRun(Path.Combine(Path.Combine(root, "out"), "FreeFunctionsEmitOnly.dll"), "Census.FreeFunctions.Consumer.FreeFunctionUses", "Digest")
    assert digest == FreeExpectedDigest(), digest
}

test "a source function in the caller's own namespace outranks a referenced one in an enclosing namespace" {
    root := FreeRoot("OwnWins")
    File.WriteAllText(Path.Combine(root, "Own.nl"), "namespace Census.FreeFunctions.Consumer\n\nfunc Twice(value: int): int => value * 20\n\nclass OwnUses {\n    static func Answer(): string => Twice(2).ToString() + \"|\" + GlobalScale(1).ToString()\n}\n")

    analysed := FreeCompile(root, "FreeFunctionsOwnWins", true)
    assert analysed.Success, FreeText(analysed.Errors)
    assert FreeRun(Path.Combine(Path.Combine(root, "out"), "FreeFunctionsOwnWins.dll"), "Census.FreeFunctions.Consumer.OwnUses", "Answer") == "40|3"
}

test "a referenced free function in an enclosing namespace outranks an imported source one" {
    root := FreeRoot("Nearest")
    File.WriteAllText(Path.Combine(root, "Rival.nl"), "namespace Census.FreeFunctions.Rival\n\nfunc Nearest(): string => \"imported-source\"\n")
    File.WriteAllText(Path.Combine(root, "Near.nl"), "namespace Census.FreeFunctions.Consumer\n\nimport Census.FreeFunctions.Rival\n\nclass NearUses {\n    static func Answer(): string => Nearest()\n}\n")

    // The enclosing namespace is lexically nearer than any import, so the rival import supplies
    // nothing this file uses -- which the analyzer says as NL010 on exactly that import.
    analysed := FreeCompile(root, "FreeFunctionsNearest", true)
    assert FreeCodes(analysed.Errors, "NL010") == 1, FreeText(analysed.Errors)
    assert FreeText(analysed.Errors).Contains("Census.FreeFunctions.Rival"), FreeText(analysed.Errors)

    emitted := FreeCompile(root, "FreeFunctionsNearestEmit", false)
    assert emitted.Success, FreeText(emitted.Errors)
    assert FreeRun(Path.Combine(Path.Combine(root, "out"), "FreeFunctionsNearestEmit.dll"), "Census.FreeFunctions.Consumer.NearUses", "Answer") == "enclosing-referenced"
}

// A MEMBER OF THE ENCLOSING TYPE HIDES A REFERENCED FREE FUNCTION OF THE SAME NAME, exactly as it
// hides a source one (`ColumnarSiblingHiding`, `AnalyzerIdentifierResolution.EnclosingTypeHasMember`):
// the type is asked before any namespace. The library's `Twice` returns an `int` and the member a
// `string`, so an analysis that bound the free function would not compile; `Nearest` and `Describe`
// return `string` either way, so the answer is what tells the member from the function.
test "a member of the enclosing type hides a referenced assembly's free function of the same name" {
    root := FreeRoot("MemberHides")
    File.WriteAllText(Path.Combine(root, "Hides.nl"), "namespace Census.FreeFunctions.Consumer\n\nclass HidingBase {\n    func Describe(value: int): string => \"inherited \" + value.ToString()\n}\n\nclass MemberHides: HidingBase {\n    func Twice(value: int): string => \"member \" + value.ToString()\n    static func Nearest(): string => \"static member\"\n    func Uses(): string => Twice(2) + \"|\" + Nearest() + \"|\" + Describe(3)\n    static func Answer(): string => new MemberHides().Uses() + \"|\" + Outside.Answer()\n}\n\nclass Outside {\n    static func Answer(): string => Twice(2).ToString() + \"|\" + Nearest()\n}\n")

    analysed := FreeCompile(root, "FreeFunctionsMemberHides", true)
    assert analysed.Success, FreeText(analysed.Errors)
    assert FreeRun(Path.Combine(Path.Combine(root, "out"), "FreeFunctionsMemberHides.dll"), "Census.FreeFunctions.Consumer.MemberHides", "Answer") == "member 2|static member|inherited 3|4|enclosing-referenced"

    emitted := FreeCompile(root, "FreeFunctionsMemberHidesEmit", false)
    assert emitted.Success, FreeText(emitted.Errors)
    assert FreeRun(Path.Combine(Path.Combine(root, "out"), "FreeFunctionsMemberHidesEmit.dll"), "Census.FreeFunctions.Consumer.MemberHides", "Answer") == "member 2|static member|inherited 3|4|enclosing-referenced"
}

test "an unexported referenced free function is not a name another assembly can call" {
    root := FreeRoot("Hidden")
    File.WriteAllText(Path.Combine(root, "Hidden.nl"), "namespace Census.FreeFunctions.Consumer\n\nclass HiddenUses {\n    static func Answer(): int => hiddenHelper()\n}\n")

    analysed := FreeCompile(root, "FreeFunctionsHidden", true)
    assert !analysed.Success, "a camelCase free function of a referenced assembly must not be callable"
    assert FreeCodes(analysed.Errors, "NL412") == 1, FreeText(analysed.Errors)

    emitted := FreeCompile(root, "FreeFunctionsHiddenEmit", false)
    assert !emitted.Success, "the emit-only path must decline the same call"
}

test "two imported namespaces that each export one free function name are NL209 at the bare call" {
    root := FreeRoot("Tie")
    File.WriteAllText(Path.Combine(root, "Tie.nl"), "namespace Census.Tie.Consumer\n\nimport Census.FreeFunctions.Imported\nimport Census.FreeFunctions.OtherImported\n\nclass TieUses {\n    static func Answer(): int => Tie()\n}\n")

    analysed := FreeCompile(root, "FreeFunctionsTie", true)
    assert FreeCodes(analysed.Errors, "NL209") == 1, FreeText(analysed.Errors)
}

test "an argument a referenced free function's signature refuses is reported, not emitted" {
    root := FreeRoot("Refused")
    File.WriteAllText(Path.Combine(root, "Refused.nl"), "namespace Census.FreeFunctions.Consumer\n\nclass RefusedUses {\n    static func Answer(): int => Twice(\"two\")\n}\n")

    // Typed as the holder's reflected method, the call is bound the way any reflected call is, so the
    // refusal is the reflected call's own: no overload of the name accepts the argument.
    analysed := FreeCompile(root, "FreeFunctionsRefused", true)
    assert !analysed.Success, "a string argument for an int parameter must not compile"
    assert FreeCodes(analysed.Errors, "NL402") == 1, FreeText(analysed.Errors)
    assert FreeCodes(analysed.Errors, "NL412") == 0, FreeText(analysed.Errors)
}
