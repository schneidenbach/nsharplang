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
//   * an `internal` TYPE constructed and read through its instance members —
//     `SemanticTokenLocation`, an internal readonly record struct.
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
// is a different resolution position from an expression and both had to learn the rule.
func GrantedLocationLine(location: SemanticTokenLocation): int {
    return location.Line
}

func GrantedLocationText(location: SemanticTokenLocation): string {
    return location.Name + "@" + location.Line.ToString() + ":" + location.Column.ToString()
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

test "an internal type of a granting reference is constructed and read through its instance members" {
    location := new SemanticTokenLocation(7, 12, "binding")

    assert location.Line == 7
    assert location.Column == 12
    assert location.Name == "binding"
    assert GrantedLocationLine(location) == 7
    assert GrantedLocationText(location) == "binding@7:12"
}

// THE CLR METADATA HALF. The rule is about what the METADATA says, so the metadata is read back:
// the type really is non-public, and the assembly really does carry the friend declaration that
// makes the blocks above legal. `GetCustomAttributesData()` is the reader, exactly as the compiler's
// own `InternalsVisibleToGrants` uses.
test "the reached type is non-public and its assembly names this one in an InternalsVisibleTo" {
    locationType := typeof(SemanticTokenLocation)
    assert !locationType.IsPublic
    assert locationType.IsNotPublic
    assert !locationType.IsVisible

    converterType := typeof(LspDiagnosticConverter)
    assert !converterType.IsVisible

    grants := 0
    attributes := locationType.Assembly.GetCustomAttributesData()
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
