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
func NotAFriendLanguageServerPath(): string {
    located := typeof(SemanticTokenLocation).Assembly.Location
    if located.Length > 0 && File.Exists(located) {
        return located
    }

    throw new InvalidOperationException("The referenced LanguageServer assembly had no readable location: '" + located + "'")
}

// THE CONSUMER WRITES THE INTERNAL NAME IN TWO POSITIONS, because an annotation and an expression
// are resolved by different arms: `SemanticTokenLocation` as a PARAMETER TYPE (refused as NL201
// "type not found") and `LspDiagnosticConverter` as a STATIC RECEIVER (refused as NL301, which is
// exactly the code the census finding reported x23).
func NotAFriendConsumerSource(): string {
    return "namespace Consumer\n\nimport NSharpLang.Compiler\nimport NSharpLang.LanguageServer.Handlers\nimport NSharpLang.LanguageServer.Services\n\nfunc Take(location: SemanticTokenLocation): int {\n    return location.Line\n}\n\nfunc Convert(): int {\n    diagnostic := new Diagnostic(\"NL012\", \"message\", new Location(1, 12, \"Program.nl\"), DiagnosticSeverity.Info, \"hint\", 10)\n    converted := LspDiagnosticConverter.FromLinterDiagnostic(diagnostic)\n    return (int)converted.Range.Start.Character\n}\n"
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
    assert NotAFriendCodes(errors).IndexOf("SemanticTokenLocation", StringComparison.Ordinal) >= 0, NotAFriendCodes(errors)
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
