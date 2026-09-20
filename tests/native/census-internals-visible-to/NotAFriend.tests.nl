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
// other names through the production `MultiFileCompiler` — the very entry point `nlc check` and
// `nlc build` use — and the refusal is asserted.
//
// THE ONLY THING THAT DIFFERS BETWEEN THE ARMS IS `name:` IN `project.yml`. Same source, same
// reference, same compiler; the friend declaration names one of them and not the others. That is
// what makes this an assertion about the RULE rather than about a spelling.
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

// ── WHICH INTERNAL NAMES THIS FILE STANDS ON, AND WHY THOSE ───────────────────────────────────
//
// The refused name has to be a SIMPLE name here, which rules out the entry-point class
// `GrantedInternals.tests.nl` stands on: N# puts a file's free functions in `Program`, so a bare
// `Program` in the consumer source below would resolve to the consumer's OWN `Program` and the
// arms would differ by nothing.
//
// SO THE SUBJECT IS `CallHierarchyProtocol`, an `internal static class` in
// `NSharpLang.LanguageServer.Handlers`. It is the residue the N# ownership lanes PRODUCE rather
// than delete: `EditorCallHierarchyFacts` owns which function is declared where and what it calls,
// and what stays behind in C# is the mapping onto OmniSharp's `CallHierarchyItem` — wire types N#
// does not own. Its predecessor here, `SemanticTokenLocation`, was the opposite kind of thing, an
// incidental helper struct, and a conversion lane deleted it. If this one ever goes too, the
// `LanguageServer.dll` reference and the `InternalsVisibleTo("Tests")` grant this whole project
// reads have gone with it, and the fixture is rewritten whole rather than re-pointed.
//
// THE CONSUMER WRITES AN INTERNAL NAME IN TWO POSITIONS, because an annotation and an expression
// are resolved by different arms: `CallHierarchyProtocol` as a PARAMETER TYPE (refused as NL201
// "type not found") and `LspDiagnosticConverter` as a STATIC RECEIVER (refused as NL301, which is
// exactly the code the census finding reported x23). The parameter is `_`-prefixed because a
// static class has no values to read — the annotation IS what is being written.
func NotAFriendConsumerSource(): string {
    return "namespace Consumer\n\nimport NSharpLang.Compiler\nimport NSharpLang.LanguageServer.Handlers\nimport NSharpLang.LanguageServer.Services\n\nfunc Take(_protocol: CallHierarchyProtocol): int {\n    return 1\n}\n\nfunc Convert(): int {\n    diagnostic := new Diagnostic(\"NL012\", \"message\", new Location(1, 12, \"Program.nl\"), DiagnosticSeverity.Info, \"hint\", 10)\n    converted := LspDiagnosticConverter.FromLinterDiagnostic(diagnostic)\n    return (int)converted.Range.Start.Character\n}\n"
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

func NotAFriendCompile(assemblyName: string): IReadOnlyList<CompilerError> {
    root := Path.Combine(Path.GetTempPath(), "nsharp-ivt-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    File.WriteAllText(
        Path.Combine(root, "project.yml"),
        "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n" + NotAFriendReferenceLines()
    )
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), NotAFriendConsumerSource())

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

test "the internal type of a reference that names this compilation is resolved" {
    errors := NotAFriendCompile("Tests")

    assert errors.Count == 0, NotAFriendCodes(errors)
}

test "the same internal names are refused for a compilation the reference does not name" {
    errors := NotAFriendCompile("NotAFriend")

    assert NotAFriendCount(errors, "NL201") == 1, NotAFriendCodes(errors)
    assert NotAFriendCount(errors, "NL301") == 1, NotAFriendCodes(errors)
    assert NotAFriendCodes(errors).IndexOf("CallHierarchyProtocol", StringComparison.Ordinal) >= 0, NotAFriendCodes(errors)
    assert NotAFriendCodes(errors).IndexOf("LspDiagnosticConverter", StringComparison.Ordinal) >= 0, NotAFriendCodes(errors)
}

// A NEAR MISS IS A MISS. `Tests.Unit` shares the granted name's prefix and `Test` is a prefix of it;
// the comparison is of the whole simple name, so neither is a friend.
test "a name that merely resembles the granted one is not a grant" {
    prefixed := NotAFriendCompile("Tests.Unit")
    assert NotAFriendCount(prefixed, "NL301") == 1, NotAFriendCodes(prefixed)

    truncated := NotAFriendCompile("Test")
    assert NotAFriendCount(truncated, "NL301") == 1, NotAFriendCodes(truncated)
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
// The simple name of an internal type is NL201 for a project no reference befriends. The FULLY
// QUALIFIED spelling of the very same type used to fall through the analyzer's deliberate leniency
// for dotted names — a dotted miss can legitimately resolve through another channel — and then
// BIND in the back end's `Assembly.GetType` lookup, which answers for internal types too. The
// measured result was a successful `NotTests.dll` whose parameter signatures name an internal type
// of the reference: an assembly the CLR refuses at load, produced by a compiler that reported
// nothing.
//
// A name this compilation is not ALLOWED to spell resolves through no channel, so the leniency
// does not apply to it and the qualified spelling is refused exactly as the simple one is.
//
// TWO ANNOTATION POSITIONS, a FIELD's type and a PARAMETER's, because the back-end fall-through
// this guards is per written occurrence and a signature is not the only place a type name lands
// in metadata. Neither is read — the annotation IS the subject — and no import is written, so the
// dotted name is the only thing that could resolve it.
func NotAFriendQualifiedSource(): string {
    return "namespace Consumer\n\nclass Holder {\n    Protocol: NSharpLang.LanguageServer.Handlers.CallHierarchyProtocol?\n}\n\nfunc Take(_protocol: NSharpLang.LanguageServer.Handlers.CallHierarchyProtocol): int {\n    return 1\n}\n"
}

func NotAFriendCompileSource(assemblyName: string, source: string): IReadOnlyList<CompilerError> {
    root := Path.Combine(Path.GetTempPath(), "nsharp-ivt-q-" + Guid.NewGuid().ToString("N"))
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

test "a fully qualified internal name is refused for a non-friend, in every type position" {
    errors := NotAFriendCompileSource("NotAFriend", NotAFriendQualifiedSource())

    // One report per written position — the field's type and the parameter's — with the SAME code
    // and the same sentence the simple spelling gets.
    assert NotAFriendCount(errors, "NL201") == 2, NotAFriendCodes(errors)
    assert NotAFriendCodes(errors).IndexOf("Type 'NSharpLang.LanguageServer.Handlers.CallHierarchyProtocol' not found", StringComparison.Ordinal) >= 0, NotAFriendCodes(errors)
}

test "the same fully qualified name is accepted for the compilation the reference names" {
    errors := NotAFriendCompileSource("Tests", NotAFriendQualifiedSource())

    assert errors.Count == 0, NotAFriendCodes(errors)
}

// THE REFUSAL IS ABOUT THE GRANT, NOT ABOUT THE DOT. A qualified PUBLIC type of the very same
// reference set still resolves for the very same non-friend project, so the leniency every other
// dotted name relies on is untouched.
test "a qualified PUBLIC type of the same references still resolves for a non-friend" {
    errors := NotAFriendCompileSource("NotAFriend", "namespace Consumer\n\nfunc Take(location: NSharpLang.Compiler.Location): int {\n    return location.Line\n}\n")

    assert NotAFriendCount(errors, "NL201") == 0, NotAFriendCodes(errors)
}

// AND A DOTTED NAME NOTHING DECLARES IS STILL LENIENT, which is the pre-existing behaviour this
// change deliberately did not widen: the analyzer reports a dotted miss only when the metadata
// really declares the name and the friend rule is the only reason it was rejected.
test "a dotted name no reference declares at all keeps its pre-existing leniency" {
    errors := NotAFriendCompileSource("NotAFriend", "namespace Consumer\n\nfunc Take(value: Totally.Made.Up.Name): int {\n    return 1\n}\n")

    assert NotAFriendCount(errors, "NL201") == 0, NotAFriendCodes(errors)
}
