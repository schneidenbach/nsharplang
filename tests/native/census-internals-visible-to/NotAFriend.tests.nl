namespace Tests

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler
import NSharpLang.LanguageServer.Handlers


// THE NEGATIVE HALF: A GRANT TO A DIFFERENT NAME IS NOT A GRANT.
//
// Everything next door compiles because this project is called `Tests` and the referenced
// `LanguageServer.dll` declares `InternalsVisibleTo("Tests")`. The rule would be worthless if it
// admitted that assembly's internals to ANY consumer, so the same source is compiled here under
// other names through the production `MultiFileCompiler` — the very entry point `nlc build` uses —
// and the refusal is asserted.
//
// THE ONLY THING THAT DIFFERS BETWEEN THE ARMS IS `name:` IN `project.yml`. Same source, same
// reference, same compiler; the friend declaration names one of them and not the others. That is
// what makes this an assertion about the RULE rather than about a spelling.
//
// THE REFERENCE UNDER TEST IS THE ONE THIS ASSEMBLY IS ALREADY BOUND TO. Asking the loaded
// assembly for its own location is the only spelling that is right wherever the test host puts the
// emitted test assembly; `AppContext.BaseDirectory` is the CLI's directory, not this project's.
//
// THE ANCHOR IS A PUBLIC TYPE ON PURPOSE. All this function wants is WHICH assembly and WHERE; it
// is not the thing under test, so it must not also be a bet on some particular internal surviving.
func NotAFriendLanguageServerPath(): string {
    located := typeof(WorkspaceSymbolHandler).Assembly.Location
    if located.Length > 0 && File.Exists(located) {
        return located
    }

    throw new InvalidOperationException("The referenced LanguageServer assembly had no readable location: '" + located + "'")
}

// ── WHICH INTERNAL NAME THIS FILE STANDS ON, AND WHERE THE REFUSAL COMES FROM ─────────────────
//
// The language server is N# now, so it has no internal TYPE to refuse: N# emits every type and
// every field as CLR public, and the one shape a grant withholds is an UNEXPORTED (camelCase)
// FUNCTION or METHOD. The subject is therefore `WorkspaceSymbolHandler.matchesQuery` — CLR
// `assembly` on a public type, measured in `GrantedInternals.tests.nl` next door.
//
// THERE ARE NOW TWO REFUSALS AND EACH ARM ASSERTS BOTH.
//
// The gap this file used to record under `lsflip` is closed: the ANALYZER reports the refusal, as
// `NL308` — the same code, sentence and three facts (the word, the declaring type, where the access
// was written from) a `private` or `internal` SOURCE member gets — so `nlc check` now tells a
// non-friend author about a visibility rule instead of leaving it to a backend to say
// `NL103 … is not modeled`. These rows therefore assert the ANALYZER diagnostic where they used to
// assert `NL103`, which is a STRENGTHENING: the refusal moves EARLIER and gets a better sentence,
// and the emit-time refusal is still asserted beside it.
//
// THE EMIT-TIME REFUSAL IS THE BACKSTOP AND IS UNCHANGED. The SDK's emit-only path runs no analysis
// at all — it is `CompileToIlAssembly(name, path, false, false)`, and that is exactly what
// `NotAFriendEmitOnly` below drives — so there the emitter's `NL103` is the only thing standing
// between a stranger and a member the CLR would refuse at load. Every negative arm asserts it too,
// which is the half that would silently disappear if someone ever made the emitter lenient because
// "the analyzer catches it".
//
// THE SIMPLE AND THE QUALIFIED SPELLING ARE BOTH WRITTEN, because a qualified name is resolved by
// a different arm and once bound in the back end's own lookup, which answers for internal members
// too. Neither may resolve for a project the grant does not name.
func NotAFriendConsumerSource(): string {
    return "namespace Consumer\n\nimport NSharpLang.LanguageServer.Handlers\n\nfunc CallInternal(): bool {\n    return WorkspaceSymbolHandler.matchesQuery(\"Alpha\", \"a\")\n}\n"
}

func NotAFriendQualifiedSource(): string {
    return "namespace Consumer\n\nfunc CallQualified(): bool {\n    return NSharpLang.LanguageServer.Handlers.WorkspaceSymbolHandler.matchesQuery(\"Alpha\", \"a\")\n}\n"
}

// The reference set is the whole directory the bound assembly came from: `LanguageServer.dll` alone
// cannot be analysed without the assemblies its own signatures name, and listing them by hand would
// pin a dependency list that is not what this file is about.
func NotAFriendReferenceLines(): string {
    directory := Path.GetDirectoryName(NotAFriendLanguageServerPath())
    if directory == null {
        throw new InvalidOperationException("The referenced assembly had no directory.")
    }

    lines := ""
    references := Directory.GetFiles(directory, "*.dll")
    Array.Sort(references)
    index := 0
    while index < references.Length {
        lines = lines + "  - dll: " + references[index] + "\n"
        index = index + 1
    }

    return lines
}

func NotAFriendList(errors: IEnumerable<CompilerError>): List<CompilerError> {
    collected := new List<CompilerError>()
    for error in errors {
        collected.Add(error)
    }

    return collected
}

// BUILD the consumer under a given assembly name, because the refusal is the emitter's. The output
// goes to a path of its own so a successful arm really does produce an assembly.
func NotAFriendBuild(assemblyName: string, source: string): IReadOnlyList<CompilerError> {
    root := Path.Combine(Path.GetTempPath(), "nsharp-ivt-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    File.WriteAllText(
        Path.Combine(root, "project.yml"),
        "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n" + NotAFriendReferenceLines()
    )
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), source)

    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    // COMPILER: lsflip-2. Written inline as the second argument the call declines at
    // `emit.call.instance-member-unmodeled`.
    outputPath := Path.Combine(root, assemblyName + ".dll")
    result := compiler.CompileToIlAssembly(assemblyName, outputPath)
    return NotAFriendList(result.Errors)
}

func NotAFriendCompile(assemblyName: string): IReadOnlyList<CompilerError> {
    return NotAFriendBuild(assemblyName, NotAFriendConsumerSource())
}

// THE SDK'S OWN PATH, which runs NO analysis: `validateStrictLint: false` and
// `validateWithLegacyAnalysis: false` is the emit-only entry `EmitIlAssembly` drives for a
// `<Project Sdk="NSharpLang.Sdk" />` build. The emitter's refusal is the only one there, and it is
// what every negative arm below asserts beside the analyzer's.
func NotAFriendEmitOnly(assemblyName: string, source: string): IReadOnlyList<CompilerError> {
    root := Path.Combine(Path.GetTempPath(), "nsharp-ivt-e-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    File.WriteAllText(
        Path.Combine(root, "project.yml"),
        "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n" + NotAFriendReferenceLines()
    )
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), source)

    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    outputPath := Path.Combine(root, assemblyName + ".dll")
    result := compiler.CompileToIlAssembly(assemblyName, outputPath, false, false)
    return NotAFriendList(result.Errors)
}

// The ANALYSIS entry point, for the two arms that are about the analyzer's own leniency for a
// dotted name rather than about the grant.
func NotAFriendAnalyze(assemblyName: string, source: string): IReadOnlyList<CompilerError> {
    root := Path.Combine(Path.GetTempPath(), "nsharp-ivt-a-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    File.WriteAllText(
        Path.Combine(root, "project.yml"),
        "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n" + NotAFriendReferenceLines()
    )
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), source)

    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.CompileForAnalysis()
    return compiler.AllErrors
}

func NotAFriendCodes(errors: IReadOnlyList<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + " | "
        }

        text = text + errors[index].DiagnosticId + " " + errors[index].Message
        index = index + 1
    }

    return text
}

func NotAFriendCount(errors: IReadOnlyList<CompilerError>, code: string): int {
    matches := 0
    index := 0
    while index < errors.Count {
        if errors[index].DiagnosticId == code {
            matches = matches + 1
        }

        index = index + 1
    }

    return matches
}

test "the internal member of a reference that names this compilation is reached" {
    errors := NotAFriendCompile("Tests")

    assert errors.Count == 0, NotAFriendCodes(errors)
}

test "the same internal name is refused for a compilation the reference does not name" {
    errors := NotAFriendCompile("NotAFriend")

    // The ANALYZER's refusal, which is what `nlc check` now shows the author.
    assert NotAFriendCount(errors, "NL308") == 1, NotAFriendCodes(errors)
    assert NotAFriendCodes(errors).IndexOf("matchesQuery", StringComparison.Ordinal) >= 0, NotAFriendCodes(errors)
    assert NotAFriendCodes(errors).IndexOf("WorkspaceSymbolHandler", StringComparison.Ordinal) >= 0, NotAFriendCodes(errors)
    assert NotAFriendCodes(errors).IndexOf("internal", StringComparison.Ordinal) >= 0, NotAFriendCodes(errors)

    // THE BACKSTOP, through the SDK's own analysis-free path.
    emitOnly := NotAFriendEmitOnly("NotAFriend", NotAFriendConsumerSource())
    assert NotAFriendCount(emitOnly, "NL103") == 1, NotAFriendCodes(emitOnly)
    assert NotAFriendCodes(emitOnly).IndexOf("matchesQuery", StringComparison.Ordinal) >= 0, NotAFriendCodes(emitOnly)
}

// A NEAR MISS IS A MISS. `Tests.Unit` shares the granted name's prefix and `Test` is a prefix of it;
// the comparison is of the whole simple name, so neither is a friend.
test "a name that merely resembles the granted one is not a grant" {
    prefixed := NotAFriendCompile("Tests.Unit")
    assert NotAFriendCount(prefixed, "NL308") == 1, NotAFriendCodes(prefixed)

    truncated := NotAFriendCompile("Test")
    assert NotAFriendCount(truncated, "NL308") == 1, NotAFriendCodes(truncated)

    assert NotAFriendCount(NotAFriendEmitOnly("Tests.Unit", NotAFriendConsumerSource()), "NL103") == 1
    assert NotAFriendCount(NotAFriendEmitOnly("Test", NotAFriendConsumerSource()), "NL103") == 1
}

// ASSEMBLY SIMPLE NAMES ARE COMPARED CASE-INSENSITIVELY, by the CLR and by every compiler that
// reads a friend declaration, so a differently cased spelling of the granted name IS the granted
// name.
test "the granted name is matched without regard to case" {
    errors := NotAFriendCompile("TESTS")

    assert errors.Count == 0, NotAFriendCodes(errors)
}

// ── THE SPELLING MUST NOT DECIDE THE RULE ─────────────────────────────────────────────────────
//
// A name this compilation is not ALLOWED to spell must not become reachable by writing it out in
// full. The qualified source below carries NO import, so the dotted name is the only thing that
// could resolve it, and it is refused exactly as the simple one is.
test "a fully qualified internal name is refused for a non-friend, as the simple one is" {
    errors := NotAFriendBuild("NotAFriend", NotAFriendQualifiedSource())

    assert NotAFriendCount(errors, "NL308") == 1, NotAFriendCodes(errors)
    assert NotAFriendCodes(errors).IndexOf("matchesQuery", StringComparison.Ordinal) >= 0, NotAFriendCodes(errors)

    emitOnly := NotAFriendEmitOnly("NotAFriend", NotAFriendQualifiedSource())
    assert NotAFriendCount(emitOnly, "NL103") == 1, NotAFriendCodes(emitOnly)
}

test "the same fully qualified name is accepted for the compilation the reference names" {
    errors := NotAFriendBuild("Tests", NotAFriendQualifiedSource())

    assert errors.Count == 0, NotAFriendCodes(errors)
}

// THE REFUSAL IS ABOUT THE GRANT, NOT ABOUT THE DOT. A qualified PUBLIC type of the very same
// reference set still resolves for the very same non-friend project, so the leniency every other
// dotted name relies on is untouched.
test "a qualified PUBLIC type of the same references still resolves for a non-friend" {
    errors := NotAFriendAnalyze("NotAFriend", "namespace Consumer\n\nfunc Take(location: NSharpLang.Compiler.Location): int {\n    return location.Line\n}\n")

    assert NotAFriendCount(errors, "NL201") == 0, NotAFriendCodes(errors)
}

// AND A DOTTED NAME NOTHING DECLARES IS STILL LENIENT, which is the pre-existing behaviour this
// change deliberately did not widen: the analyzer reports a dotted miss only when the metadata
// really declares the name and the friend rule is the only reason it was rejected.
test "a dotted name no reference declares at all keeps its pre-existing leniency" {
    errors := NotAFriendAnalyze("NotAFriend", "namespace Consumer\n\nfunc Take(value: Totally.Made.Up.Name): int {\n    return 1\n}\n")

    assert NotAFriendCount(errors, "NL201") == 0, NotAFriendCodes(errors)
}
