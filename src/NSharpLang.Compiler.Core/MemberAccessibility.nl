namespace NSharpLang.Compiler

import System
import System.Reflection


// ONE ACCESSIBILITY RELATION, FOR SOURCE MEMBERS AND REFLECTED ONES ALIKE.
//
// N# has two independent visibility systems and they are easy to confuse, so this file names both
// and answers only the second.
//
// THE PACKAGE RULE is N#'s own: a PascalCase name (or a written `public`) is EXPORTED from its
// package, a camelCase name is not, and a non-exported declaration is unreachable from a file of
// another namespace. `VisibilityConventions` owns that rule, `AnalyzerMemberAccess` reports it as
// NL308, and the CLR knows nothing about it — a package-private member is emitted `Assembly`, which
// is why the rule has to be enforced by the compiler and cannot be left to the runtime.
//
// THE DECLARED RULE is the CLR's, and it is what this file owns: `private` means the declaring type
// and nothing else, `protected` means the declaring type and the types that derive from it,
// `internal` means the assembly. Those words mean the same thing whether they were written in an N#
// source file or read off a `MethodInfo` from a referenced assembly, so ONE relation answers for
// both — a reflected `protected` member of a base class is reachable from a source type that
// derives from it under exactly the rule that a source `protected` member is.
//
// THE LEVELS ARE THE CLR'S SIX, ordered from most restricted to least so that a caller can compare
// them. They are not the `MethodAttributes` bit values: those are a mask, and `Family` (4) is
// numerically larger than `Assembly` (3) while being neither wider nor narrower than it. An
// ORDERING is what callers actually want ("is this at least as visible as…"), so an ordering is
// what is published, and `ColumnarDeclarationPlan` keeps the metadata bits.
//
// THE RECEIVER HALF OF `protected` IS NOT OPTIONAL (C# §7.5.4, and the CLR's own `family` check).
// Being inside a derived type is not enough: `Derived.M()` may read `this.Seed` and `other.Seed`
// where `other: Derived`, but NOT `b.Seed` where `b: Base`, because at run time `b` might be some
// OTHER derived type whose protected state this one has no business touching. Callers supply that
// judgement as `receiverIsAccessingTypeOrDerived`; a static member, and a bare name with no written
// receiver at all, supply `true` because the receiver is the accessing type by construction.
class MemberAccessibility {

    // `private`: the declaring type, and nothing else.
    static Private: int => 0

    // `private protected`: a derived type in the same assembly.
    static PrivateProtected: int => 1

    // `internal`: the assembly.
    static Assembly: int => 2

    // `protected`: the declaring type and the types that derive from it, in any assembly.
    static Family: int => 3

    // `protected internal`: either of the two above.
    static FamilyOrAssembly: int => 4

    // `public`: everyone.
    static Public: int => 5

    // WHAT A SOURCE MEMBER'S WRITTEN WORDS SAY, and nothing about its name. The casing convention is
    // deliberately NOT folded in here: casing decides PACKAGE export, which is a different question
    // with a different owner and a different report, and a camelCase member of a class is reachable
    // from every file of its own package exactly as a PascalCase one is. So a member with no written
    // accessibility word is `public` at this level and the package rule decides the rest.
    static func LevelOfDeclaredModifiers(modifierFlags: int): int {
        if (modifierFlags & 1) != 0 {
            return Public
        }

        if (modifierFlags & 8) != 0 && (modifierFlags & 2) != 0 {
            return PrivateProtected
        }

        if (modifierFlags & 8) != 0 && (modifierFlags & 4) != 0 {
            return FamilyOrAssembly
        }

        if (modifierFlags & 2) != 0 {
            return Private
        }

        if (modifierFlags & 8) != 0 {
            return Family
        }

        if (modifierFlags & 4) != 0 || (modifierFlags & 32768) != 0 {
            return Assembly
        }

        return Public
    }

    // The word a diagnostic should quote back for a level, so the report names what was written.
    static func LevelWord(level: int): string {
        if level == Private {
            return "private"
        }

        if level == PrivateProtected {
            return "private protected"
        }

        if level == Assembly {
            return "internal"
        }

        if level == Family {
            return "protected"
        }

        if level == FamilyOrAssembly {
            return "protected internal"
        }

        return "public"
    }

    // WHAT A REFLECTED MEMBER'S METADATA SAYS. The six CLR flags are mutually exclusive, so the
    // order of these tests is presentational rather than load-bearing; `IsFamilyOrAssembly` and
    // `IsFamilyAndAssembly` are asked BEFORE `IsFamily` and `IsAssembly` anyway, because a reader
    // who saw the narrow ones last would reasonably wonder whether they were reachable at all.
    static func LevelOfMethod(method: MethodBase?): int {
        if method == null {
            return Private
        }

        return LevelOfClrFlags(method.get_IsPublic(), method.get_IsFamilyOrAssembly(), method.get_IsFamilyAndAssembly(), method.get_IsFamily(), method.get_IsAssembly())
    }

    static func LevelOfField(field: FieldInfo?): int {
        if field == null {
            return Private
        }

        return LevelOfClrFlags(field.get_IsPublic(), field.get_IsFamilyOrAssembly(), field.get_IsFamilyAndAssembly(), field.get_IsFamily(), field.get_IsAssembly())
    }

    static func LevelOfClrFlags(isPublic: bool, isFamilyOrAssembly: bool, isFamilyAndAssembly: bool, isFamily: bool, isAssembly: bool): int {
        if isPublic {
            return Public
        }

        if isFamilyOrAssembly {
            return FamilyOrAssembly
        }

        if isFamilyAndAssembly {
            return PrivateProtected
        }

        if isFamily {
            return Family
        }

        if isAssembly {
            return Assembly
        }

        return Private
    }

    // THE RELATION ITSELF.
    //
    // `isDeclaringType` — the access is written inside the very type that declares the member.
    // `derivesFromDeclaringType` — the access is written inside a type that derives from it (the
    //   declaring type itself counts, so a caller never has to pass both).
    // `receiverIsAccessingTypeOrDerived` — the receiver's static type is the accessing type or a
    //   type derived from it, which is the second half of the `protected` rule.
    // `sameAssembly` — the member is declared in the assembly being compiled. Source members always
    //   are; a member read off a referenced assembly never is, because N# models no
    //   `InternalsVisibleTo` and a friend claim it cannot see is one it must not act on.
    static func IsAccessible(level: int, isDeclaringType: bool, derivesFromDeclaringType: bool, receiverIsAccessingTypeOrDerived: bool, sameAssembly: bool): bool {
        if level == Public {
            return true
        }

        if level == Private {
            return isDeclaringType
        }

        if level == Assembly {
            return sameAssembly
        }

        if level == Family {
            return isDeclaringType || (derivesFromDeclaringType && receiverIsAccessingTypeOrDerived)
        }

        if level == PrivateProtected {
            return isDeclaringType || (sameAssembly && derivesFromDeclaringType && receiverIsAccessingTypeOrDerived)
        }

        if level == FamilyOrAssembly {
            return sameAssembly || isDeclaringType || (derivesFromDeclaringType && receiverIsAccessingTypeOrDerived)
        }

        return false
    }

    // WHAT THE DEVELOPER COULD HAVE WRITTEN INSTEAD, in one clause, for the refusal's message. The
    // wording names the DECLARING type because that is the fact the developer has to act on: every
    // level's remedy is either "write this inside that type" or "write this in a type that derives
    // from it".
    static func AllowedFromPhrase(level: int, declaringTypeName: string): string {
        if level == Private {
            return "only code inside '" + declaringTypeName + "' can reach it"
        }

        if level == PrivateProtected {
            return "only '" + declaringTypeName + "' and the types in this project that derive from it can reach it, through a receiver of the deriving type"
        }

        if level == Family {
            return "only '" + declaringTypeName + "' and the types that derive from it can reach it, through a receiver of the deriving type"
        }

        if level == Assembly {
            return "only code compiled into the same assembly as '" + declaringTypeName + "' can reach it"
        }

        if level == FamilyOrAssembly {
            return "only the same assembly, '" + declaringTypeName + "', and the types that derive from it can reach it"
        }

        return "it is reachable from anywhere"
    }
}
