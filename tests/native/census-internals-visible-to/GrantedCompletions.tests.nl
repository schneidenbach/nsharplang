namespace Tests

import System
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Handlers


// THE COMPLETION LIST SEES WHAT THE FRIEND GRANT ADMITS, NOT MERELY WHAT IS PUBLIC.
//
// The analyzer has bound a granting reference's `internal` members for this project since friends
// landed — the blocks in `GrantedInternals.tests.nl` next door COMPILE AND RUN against them. The
// completion list did not: it asked metadata for `BindingFlags.Public` alone, so the editor offered
// strictly less than the compiler would accept and the developer had to already know the member's
// name to write it. `InternalsVisibleToGrants` is the one owner of the grant and
// `MemberAccessibility.IsAccessible` the one owner of the relation; completion now asks both.
//
// THIS PROJECT IS THE ONLY PLACE THE ASSERTION IS REAL. It is called `Tests`, which is the name
// `LanguageServer.csproj` spells in its `InternalsVisibleTo`, so the grant below is the shipped one
// rather than a fixture.
func GrantedCompletionGrants(): InternalsVisibleToGrants {
    grants := new InternalsVisibleToGrants()
    grants.SetCompilingAssemblyName("Tests")
    return grants
}

func GrantedCompletionItems(grants: InternalsVisibleToGrants?, owner: Type): bool {
    friendAdmits := CompletionReflectionFacts.FriendAdmits(grants, owner)
    flags := CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.All, false, friendAdmits)
    items := CompletionReflectionFacts.BuildReflectionMemberItems(owner, flags, false, friendAdmits, grants)

    index := 0
    while index < items.Count {
        if items[index].Name == "MatchesQuery" {
            return true
        }

        index = index + 1
    }

    return false
}

test "the grant is real: the referenced assembly names THIS assembly a friend" {
    grants := GrantedCompletionGrants()

    assert grants.SameAssemblyOrFriend(typeof(WorkspaceSymbolHandler))
}

test "an internal static member of a granting reference is OFFERED, because the compiler binds it" {
    // `WorkspaceSymbolHandler.MatchesQuery` is `internal static` on a public type, and
    // `GrantedInternals.tests.nl` calls it for real.
    assert GrantedCompletionItems(GrantedCompletionGrants(), typeof(WorkspaceSymbolHandler))
}

test "without the grant the same member is offered NOWHERE, so the grant is doing the work" {
    // A compilation that the reference does NOT name — and one with no project behind it at all —
    // sees the public surface only, which is what every non-friend project still sees.
    stranger := new InternalsVisibleToGrants()
    stranger.SetCompilingAssemblyName("Stranger")

    assert !GrantedCompletionItems(stranger, typeof(WorkspaceSymbolHandler))
    assert !GrantedCompletionItems(null, typeof(WorkspaceSymbolHandler))
}

test "the public surface of the same type is offered either way" {
    grants := GrantedCompletionGrants()
    friendAdmits := CompletionReflectionFacts.FriendAdmits(grants, typeof(WorkspaceSymbolHandler))
    flags := CompletionReflectionFacts.GetReflectionBindingFlags(CompletionMemberFilter.All, false, friendAdmits)
    items := CompletionReflectionFacts.BuildReflectionMemberItems(typeof(WorkspaceSymbolHandler), flags, false, friendAdmits, grants)

    found := false
    index := 0
    while index < items.Count {
        if items[index].Name == "Handle" {
            found = true
        }

        index = index + 1
    }

    assert found, "the public Handle method must still be offered to a friend"
}
