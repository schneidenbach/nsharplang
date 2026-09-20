namespace Tests

import System.Collections
import NSharpLang.Compiler
import NSharpLang.LanguageServer.Handlers
import NSharpLang.LanguageServer.Services


// A REFERENCED ASSEMBLY'S INTERNALS, REACHED BECAUSE IT NAMED THIS ONE A FRIEND.
//
// THIS PROJECT IS CALLED `Tests` ON PURPOSE. `LanguageServer.csproj` and `Cli.csproj` both carry
// `<InternalsVisibleTo Include="Tests" />`, so the assembly this project emits is exactly the one
// those two declare as a friend — which is what makes every block below a real exercise of the rule
// rather than a re-test of public API. Renaming this project would silently turn every positive here
// into a compile error, and `NotAFriend.tests.nl` next door asserts precisely that.
//
// WHAT IS BEING ASSERTED IS RUNTIME BEHAVIOUR, not resolution. These blocks compile to ordinary IL
// — `call`, `ldsfld`, `newobj` — and the CLR re-checks the friend grant when it loads the emitted
// assembly, so a block that RUNS is proof that the whole path (naming the type, selecting the
// member, emitting the instruction and passing the runtime's own accessibility check) holds.
//
// THE FIXTURES ARE THE REAL SHAPES A FRIEND REACHES:
//   * an `internal static class` whose members are public — `LspDiagnosticConverter`,
//     the type the converted language-server test project reported NL301 x23 on;
//   * an `internal static` METHOD of a PUBLIC type — `WorkspaceSymbolHandler.MatchesQuery`;
//   * an `internal static` FIELD of a PUBLIC type — `SemanticTokensHandler.TokenTypes`;
//   * an `internal` TYPE named in an annotation, constructed and passed —
//     `NSharpLang.LanguageServer.Program`.
//
// ── WHICH INTERNAL TYPE THIS FIXTURE STANDS ON, AND WHY THAT ONE ──────────────────────────────
//
// This block used to stand on `SemanticTokenLocation`, an internal record struct in the language
// server's semantic-token handler. The N# ownership lane moved that walk into
// `EditorSemanticTokenFacts` and deleted the C# type, and the fixture went red — the subject was
// incidental helper surface, which is exactly the surface a conversion lane exists to delete.
//
// THE SUBJECT IS NOW THE LANGUAGE SERVER'S ENTRY-POINT CLASS, `NSharpLang.LanguageServer.Program`,
// which C# makes `internal` by default — and letting a test assembly reach `Program` is the single
// most ordinary reason `[InternalsVisibleTo]` exists in .NET at all. It is not helper surface: an
// executable has an entry point for as long as it is an executable. When it does go, the whole
// `LanguageServer.dll` has gone with it — and so has the `InternalsVisibleTo("Tests")` grant that
// every block in this project reads, so that is the flip where this fixture is rewritten whole,
// not a lane that quietly deletes one type out from under it.
//
// THE NAME IS WRITTEN IN FULL, never as bare `Program`. N# puts this file's free functions in
// `Tests.Program`, so the simple name resolves HERE and would assert nothing about the reference.
// `NotAFriend.tests.nl` next door needs a simple name that cannot collide that way, and stands on
// `CallHierarchyProtocol` for it — read the note there before re-pointing either one.
func GrantedConverterCharacter(line: int, column: int, length: int): int {
    diagnostic := new Diagnostic(
        "NL012",
        "Parameter 'unusedName' in 'greet' is never read — is it needed?",
        new Location(line, column, "Program.nl"),
        DiagnosticSeverity.Info,
        "Prefix with '_' if this is intentional",
        length
    )

    converted := LspDiagnosticConverter.FromLinterDiagnostic(diagnostic)
    return (int)converted.Range.Start.Character
}

func GrantedConverterEndCharacter(line: int, column: int, length: int): int {
    diagnostic := new Diagnostic(
        "NL012",
        "message",
        new Location(line, column, "Program.nl"),
        DiagnosticSeverity.Info,
        "hint",
        length
    )

    converted := LspDiagnosticConverter.FromLinterDiagnostic(diagnostic)
    return (int)converted.Range.End.Character
}

// The internal type is written as a PARAMETER type as well as inside a body, because an annotation
// is a different resolution position from an expression and both had to learn the rule. These two
// are EMITTED, so the parameter's type lands in the produced metadata and the CLR checks it when
// the call is JITted — a signature naming a type this assembly may not see would fail at load.
func GrantedHostTypeName(host: NSharpLang.LanguageServer.Program): string {
    return host.GetType().FullName ?? ""
}

func GrantedHostIsNonPublic(host: NSharpLang.LanguageServer.Program): bool {
    return !host.GetType().IsPublic
}

func GrantedSequenceCount(sequence: object): int {
    values := (IList)sequence
    return values.Count
}

test "an internal static class of a granting reference converts a diagnostic at run time" {
    assert GrantedConverterCharacter(1, 12, 10) == 11
    assert GrantedConverterEndCharacter(1, 12, 10) == 21
    assert GrantedConverterCharacter(1, 1, 1) == 0
    assert GrantedConverterEndCharacter(1, 1, 1) == 1
}

test "an internal static method of a public type of a granting reference runs" {
    assert WorkspaceSymbolHandler.MatchesQuery("WorkspaceSymbolHandler", "wsh")
    assert WorkspaceSymbolHandler.MatchesQuery("Alpha", "")
    assert !WorkspaceSymbolHandler.MatchesQuery("Alpha", "zz")
}

test "an internal static field of a public type of a granting reference reads" {
    tokenTypes := SemanticTokensHandler.TokenTypes
    assert tokenTypes.Length == 18
    assert tokenTypes[0] == "namespace"
    assert tokenTypes[17] == "enumMember"
    assert SemanticTokensHandler.TokenModifiers.Length > 0
}

test "an internal type of a granting reference is constructed and passed at run time" {
    // `newobj` on a type the CLR calls non-public. The runtime resolves the constructor against
    // the friend grant at JIT time, so reaching this line at all is the grant being honoured —
    // and the value then crosses a call whose SIGNATURE names the same internal type.
    host := new NSharpLang.LanguageServer.Program()

    assert GrantedHostTypeName(host) == "NSharpLang.LanguageServer.Program"
    assert GrantedHostIsNonPublic(host)
    assert !host.GetType().IsVisible
}

// THE CLR METADATA HALF. The rule is about what the METADATA says, so the metadata is read back:
// the type really is non-public, and the assembly really does carry the friend declaration that
// makes the blocks above legal. `GetCustomAttributesData()` is the reader, exactly as the compiler's
// own `InternalsVisibleToGrants` uses.
test "the reached type is non-public and its assembly names this one in an InternalsVisibleTo" {
    hostType := typeof(NSharpLang.LanguageServer.Program)
    assert !hostType.IsPublic
    assert hostType.IsNotPublic
    assert !hostType.IsVisible

    converterType := typeof(LspDiagnosticConverter)
    assert !converterType.IsVisible

    grants := 0
    attributes := hostType.Assembly.GetCustomAttributesData()
    count := GrantedSequenceCount(attributes)
    index := 0
    while index < count {
        attribute := attributes.get_Item(index)
        if attribute.AttributeType.FullName == "System.Runtime.CompilerServices.InternalsVisibleToAttribute" {
            declared := attribute.ConstructorArguments.get_Item(0).Value as string
            if declared == "Tests" {
                grants = grants + 1
            }
        }

        index = index + 1
    }

    assert grants == 1, "the referenced LanguageServer assembly must declare InternalsVisibleTo(\"Tests\")"
}

// A PUBLIC MEMBER OF A GRANTING REFERENCE IS STILL AN ORDINARY PUBLIC MEMBER. The widened binding
// flags every friend lookup uses must not change which overload a public call selects, so the same
// reference's public surface is exercised beside its internal one.
test "the public surface of the same granting reference is unchanged" {
    location := new Location(3, 4, "Program.nl")

    assert location.Line == 3
    assert location.Column == 4
    assert location.FilePath == "Program.nl"
}
