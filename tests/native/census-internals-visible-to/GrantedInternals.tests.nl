namespace Tests

import System.Collections
import System.Reflection
import NSharpLang.Compiler
import NSharpLang.LanguageServer.Handlers
import NSharpLang.LanguageServer.Services


// A REFERENCED ASSEMBLY'S INTERNALS, REACHED BECAUSE IT NAMED THIS ONE A FRIEND.
//
// THIS PROJECT IS CALLED `Tests` ON PURPOSE. The language server's `project.yml` carries
// `internalsVisibleTo: [Tests]` and `Cli.csproj` carries `<InternalsVisibleTo Include="Tests" />`,
// so the assembly this project emits is exactly the one those two declare as a friend — which is
// what makes every block below a real exercise of the rule rather than a re-test of public API.
// Renaming this project would silently turn every positive here into a build error, and
// `NotAFriend.tests.nl` next door asserts precisely that.
//
// WHAT IS BEING ASSERTED IS RUNTIME BEHAVIOUR, not resolution. These blocks compile to ordinary IL
// — `call`, `ldsfld` — and the CLR re-checks the friend grant when it loads the emitted assembly,
// so a block that RUNS is proof that the whole path (naming the type, selecting the member,
// emitting the instruction and passing the runtime's own accessibility check) holds.
//
// ── WHICH INTERNAL MEMBERS THIS FIXTURE STANDS ON, AND WHY THOSE ──────────────────────────────
//
// This file used to stand on C# shapes the language server no longer has: an `internal static
// class` (`LspDiagnosticConverter`), an `internal static` FIELD (`SemanticTokensHandler.TokenTypes`)
// and an `internal` TYPE (`NSharpLang.LanguageServer.Program`). The language server is N# now, and
// N# decides CLR accessibility differently: it emits every TYPE and every FIELD as CLR `public`,
// and a camelCase, unexported FUNCTION or METHOD as CLR `assembly`. `SourceGrants.tests.nl` next
// door MEASURES that rule rather than assuming it, and the last block here measures it again
// against the real `LanguageServer.dll`.
//
// SO THE SUBJECT IS THE ONE SHAPE AN N# GRANT CAN ACTUALLY EXPOSE: an unexported METHOD of a
// PUBLIC type. Two of them, on two different types, so the fixture is about the RULE and not about
// one member surviving:
//   * `WorkspaceSymbolHandler.matchesQuery` — the workspace-symbol subsequence match;
//   * `SemanticTokensHandler.legendIndex` — the semantic-token legend lookup.
//
// Both are pure, both are named in full where a simple name could collide, and both are the
// residue the N# ownership lanes PRODUCE rather than delete: the decisions are owned by
// `EditorWorkspaceSymbolFacts` and `EditorSemanticTokenFacts`, and what stays behind in the server
// is the protocol mapping. If one of them ever goes, the whole `LanguageServer.dll` reference and
// the `internalsVisibleTo: [Tests]` grant this project reads have gone with it.
func GrantedSequenceCount(sequence: object): int {
    values := (IList)sequence
    return values.Count
}

// The legend index the server answers for a kind word. `legendIndex` is camelCase, so this call
// only binds because the reference names this compilation a friend.
func GrantedLegendIndex(kind: string): int {
    return SemanticTokensHandler.legendIndex(kind)
}

test "an internal static method of a public type of a granting reference runs" {
    assert WorkspaceSymbolHandler.matchesQuery("WorkspaceSymbolHandler", "wsh")
    assert WorkspaceSymbolHandler.matchesQuery("Alpha", "")
    assert !WorkspaceSymbolHandler.matchesQuery("Alpha", "zz")
}

// A SECOND INTERNAL MEMBER, ON A DIFFERENT TYPE OF THE SAME REFERENCE. One member could be an
// accident of how that one file was written; two on two types is the grant.
test "a second internal static method, on another type of the same reference, runs" {
    assert GrantedLegendIndex("namespace") == 0
    assert GrantedLegendIndex("enumMember") == 17
    // The owner's fallback: a kind the legend does not carry is painted as "type", index 1.
    assert GrantedLegendIndex("not-a-token-kind") == 1
}

// THE LEGEND ITSELF IS PUBLIC, and that is the point of reading it here: N# emits fields as CLR
// public, so the grant exposes nothing extra at a field and the legend is readable by anyone. The
// INDEX LOOKUP over it is what the grant admits, and the two agree.
test "the public legend and the granted lookup over it agree" {
    tokenTypes := SemanticTokensHandler.TokenTypes
    assert tokenTypes.Length == 18
    assert tokenTypes[0] == "namespace"
    assert tokenTypes[17] == "enumMember"
    assert SemanticTokensHandler.TokenModifiers.Length > 0

    index := 0
    while index < tokenTypes.Length {
        assert GrantedLegendIndex(tokenTypes[index]) == index, tokenTypes[index]
        index = index + 1
    }
}

// THE CLR METADATA HALF. The rule is about what the METADATA says, so the metadata is read back:
// the member really is CLR `assembly` on a type that really is public, and the assembly really does
// carry the friend declaration that makes the blocks above legal. `GetCustomAttributesData()` is
// the reader, exactly as the compiler's own `InternalsVisibleToGrants` uses.
test "the reached member is CLR assembly on a public type, and its assembly names this one a friend" {
    ownerType := typeof(WorkspaceSymbolHandler)
    assert ownerType.IsPublic, "the DECLARING type is public — only the member is withheld"
    assert ownerType.IsVisible

    reached := ownerType.GetMethod("matchesQuery", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
    assert reached != null
    assert reached.IsAssembly, "an unexported N# method is exactly what an InternalsVisibleTo grant admits"
    assert !reached.IsPublic
    assert !reached.IsPrivate

    second := typeof(SemanticTokensHandler).GetMethod("legendIndex", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
    assert second != null
    assert second.IsAssembly

    grants := 0
    attributes := ownerType.Assembly.GetCustomAttributesData()
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

// WHAT THE FLIP CHANGED, MEASURED RATHER THAN REMEMBERED. The C# language server withheld TYPES
// and FIELDS as well, and three of this file's blocks used to stand on that. N# does not: casing
// decides PACKAGE export, which is invisible to the CLR, so every type and every field it emits is
// CLR public and an `internalsVisibleTo:` grant adds nothing at either. This block is the reason
// the subjects above are METHODS and nothing else.
test "the granting assembly emits its types and fields public, so only its unexported methods are withheld" {
    converterType := typeof(LspDiagnosticConverter)
    assert converterType.IsPublic, "N# emits a type as CLR public; the C# `internal static class` is gone"
    assert converterType.IsVisible

    legendField := typeof(SemanticTokensHandler).GetField("TokenTypes", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
    assert legendField != null
    assert legendField.IsPublic, "N# emits fields as CLR public, so a grant exposes nothing extra at a field"

    converted := LspDiagnosticConverter.FromLinterDiagnostic(new Diagnostic(
        "NL012",
        "Parameter 'unusedName' in 'greet' is never read — is it needed?",
        new Location(1, 12, "Program.nl"),
        DiagnosticSeverity.Info,
        "Prefix with '_' if this is intentional",
        10
    ))

    // It is ordinary public API now, and it still answers the same 0-based end-exclusive span.
    assert (int)converted.Range.Start.Character == 11
    assert (int)converted.Range.End.Character == 21
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
