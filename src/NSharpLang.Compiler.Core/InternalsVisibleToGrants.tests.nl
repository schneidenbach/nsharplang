namespace NSharpLang.Compiler

import System
import System.Reflection


// THE FRIEND RULE ITSELF, pinned where it is decided rather than where it is felt.
//
// The END of this rule — an `internal` type and an `internal` member of a granting reference being
// named, resolved, emitted and RUN — is asserted in `tests/native/census-internals-visible-to`,
// which is compiled as the assembly `Tests` that `LanguageServer.dll` and `Cli.dll` declare as a
// friend. What is asserted HERE is everything that does not need such an assembly: how a friend
// declaration's argument is read, which compiling names it names, what an unnamed compilation is
// granted, and that the nameability answer for an ungranted internal is still "no".
func GrantsCoreAssembly(): Assembly {
    return typeof(object).get_Assembly()
}

// `System.TokenType` is internal to the core library, which declares no friend named by any test
// here — so it is the standing negative for every arm below.
func GrantsInternalCoreType(): Type? {
    return GrantsCoreAssembly().GetType("System.TokenType")
}

func GrantsNamed(assemblyName: string): InternalsVisibleToGrants {
    grants := new InternalsVisibleToGrants()
    grants.SetCompilingAssemblyName(assemblyName)
    return grants
}

test "a friend declaration's simple name is everything before the first comma, trimmed" {
    assert InternalsVisibleToGrants.FriendSimpleName("Tests") == "Tests"
    assert InternalsVisibleToGrants.FriendSimpleName("  Tests  ") == "Tests"
    assert InternalsVisibleToGrants.FriendSimpleName("Tests, PublicKey=00240000048000009400000006020000") == "Tests"
    assert InternalsVisibleToGrants.FriendSimpleName("Contoso.Widgets.Tests, PublicKey=0024") == "Contoso.Widgets.Tests"
    assert InternalsVisibleToGrants.FriendSimpleName("") == ""
    assert InternalsVisibleToGrants.FriendSimpleName(", PublicKey=0024") == ""
}

// ASSEMBLY SIMPLE NAMES COMPARE CASE-INSENSITIVELY — the CLR's own rule, and the one Roslyn's friend
// map applies — so a differently cased grant is still a grant and a merely similar one is not.
test "a grant names a compilation by its whole simple name, without regard to case" {
    assert InternalsVisibleToGrants.NamesCompilation("Tests", "Tests")
    assert InternalsVisibleToGrants.NamesCompilation("TESTS", "tests")
    assert InternalsVisibleToGrants.NamesCompilation("Tests, PublicKey=0024", "Tests")

    assert !InternalsVisibleToGrants.NamesCompilation("Tests", "Tests.Unit")
    assert !InternalsVisibleToGrants.NamesCompilation("Tests", "Test")
    assert !InternalsVisibleToGrants.NamesCompilation("Tests.Unit", "Tests")
    assert !InternalsVisibleToGrants.NamesCompilation("Tests", "Other")
}

// A COMPILATION WITH NO NAME IS THE FRIEND OF NOTHING, and that is the pre-existing behaviour a bare
// `new Analyzer()` and every planner unit test keep.
test "an unnamed compilation is granted nothing and names no internal type" {
    grants := new InternalsVisibleToGrants()

    assert grants.CompilingAssemblyName == ""
    assert !grants.GrantsAccess(GrantsCoreAssembly())
    assert !grants.GrantsAccess(null)
    assert !InternalsVisibleToGrants.NamesCompilation("Tests", "")

    internalType := GrantsInternalCoreType()
    assert internalType != null, "System.TokenType must exist in the core library for this contract"
    assert !grants.IsNameableType(internalType)
}

test "a named compilation the core library does not befriend still cannot name its internals" {
    grants := GrantsNamed("Tests")

    assert grants.CompilingAssemblyName == "Tests"
    assert !grants.GrantsAccess(GrantsCoreAssembly())
    assert !grants.IsNameableType(GrantsInternalCoreType())
    assert !grants.SameAssemblyOrFriend(GrantsInternalCoreType())
}

// THE VISIBLE SURFACE IS NAMEABLE WITH OR WITHOUT A GRANT: the friend arm only ever ADDS to what
// `Type.IsVisible` already answers, so it can never make a public type unnameable.
test "a visible type is nameable whatever the compiling assembly is called" {
    unnamed := new InternalsVisibleToGrants()
    named := GrantsNamed("Tests")

    assert unnamed.IsNameableType(typeof(string))
    assert named.IsNameableType(typeof(string))
    assert unnamed.IsNameableType(typeof(Assembly))
    assert !unnamed.IsNameableType(null)
    assert !named.IsNameableType(null)
}

// RENAMING THE COMPILATION IS THE ONLY INPUT THAT CHANGES AN ANSWER, so it is the only thing that
// drops the per-assembly memo. Setting the same name again is not a change.
test "the compiling name is what the grants are keyed on and re-setting it is idempotent" {
    grants := new InternalsVisibleToGrants()

    grants.SetCompilingAssemblyName("Tests")
    assert grants.CompilingAssemblyName == "Tests"
    assert !grants.GrantsAccess(GrantsCoreAssembly())

    grants.SetCompilingAssemblyName("Tests")
    assert grants.CompilingAssemblyName == "Tests"

    grants.SetCompilingAssemblyName("Other")
    assert grants.CompilingAssemblyName == "Other"
    assert !grants.GrantsAccess(GrantsCoreAssembly())

    grants.SetCompilingAssemblyName(null)
    assert grants.CompilingAssemblyName == ""
}

test "a member with no declaring type is granted nothing" {
    grants := GrantsNamed("Tests")

    assert !grants.GrantsAccessToDeclaringAssemblyOf(null)
    assert !grants.GrantsAccessToAssemblyOf(null)
    assert !grants.SameAssemblyOrFriend(null)
    assert !grants.GrantsAccessToAssemblyOf(typeof(string)) || grants.GrantsAccessToAssemblyOf(typeof(string))
}

// THE BACK END'S SCOPE. It is thread-local and opened for the duration of one emission; with no
// scope open nothing is granted, which is exactly what a planner unit test and a hover must see.
test "the emission scope grants nothing until it is opened, and nothing again once it is closed" {
    InternalsVisibleToEmissionScope.End()

    assert InternalsVisibleToEmissionScope.CompilingAssemblyName() == ""
    assert !InternalsVisibleToEmissionScope.GrantsAccess(GrantsCoreAssembly())
    assert !InternalsVisibleToEmissionScope.GrantsAccessToDeclarer(typeof(string))
    assert !InternalsVisibleToEmissionScope.GrantsAccessToDeclarerOf(null)
    assert !InternalsVisibleToEmissionScope.CanNameType(GrantsInternalCoreType())

    // A VISIBLE type is nameable with no scope at all: the scope only widens.
    assert InternalsVisibleToEmissionScope.CanNameType(typeof(string))
    assert !InternalsVisibleToEmissionScope.CanNameType(null)

    InternalsVisibleToEmissionScope.Begin("Tests")
    try {
        assert InternalsVisibleToEmissionScope.CompilingAssemblyName() == "Tests"
        assert !InternalsVisibleToEmissionScope.GrantsAccess(GrantsCoreAssembly())
        assert !InternalsVisibleToEmissionScope.CanNameType(GrantsInternalCoreType())
        assert InternalsVisibleToEmissionScope.CanNameType(typeof(string))
    } finally {
        InternalsVisibleToEmissionScope.End()
    }

    assert InternalsVisibleToEmissionScope.CompilingAssemblyName() == ""
}

// THE LEVEL RELATION THE BACK-END FILTERS ASK. `public` always; the three assembly-bound levels only
// through a friend; `protected` and `private` never, because a plain read carries no derivation
// relation — the inherited-`protected` path answers those with its own argument.
test "the back end reaches public always, assembly levels only through a friend, and protected never" {
    InternalsVisibleToEmissionScope.End()

    assert InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.Public, typeof(string))
    assert !InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.Assembly, typeof(string))
    assert !InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.FamilyOrAssembly, typeof(string))
    assert !InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.PrivateProtected, typeof(string))
    assert !InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.Family, typeof(string))
    assert !InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.Private, typeof(string))
    assert InternalsVisibleToEmissionScope.ReachesLevel(MemberAccessibility.Public, null)
}
