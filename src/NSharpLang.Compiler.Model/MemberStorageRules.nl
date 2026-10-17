namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast


// WHEN A BARE `Name: T` MEMBER IS A PROPERTY, AND WHEN IT IS A FIELD.
//
// N# has one spelling for a value member — `Name: T`, with or without `= initializer` — and the CLR
// has two shapes it can take. The shape is not decoration: EF Core maps properties, System.Text.Json
// serializes properties, ASP.NET model binding binds properties, and a `DbSet<T>` written as a field
// is never populated. So the members another type or another assembly is MEANT TO SEE are
// properties, and the declaring type's own storage stays a field. Concretely, a member is an
// auto-property — `public T Name { get; set; }`, a `<Name>k__BackingField` behind it — when ALL of
// these hold:
//
//   * its type is a REFERENCE type: a `class` or a `record` (not a `record struct`). A value type's
//     members stay fields — a struct is a storage layout first (`[StructLayout]`, P/Invoke,
//     `ref holder.Inner.X`), and `System.Numerics.Vector3` and `ValueTuple` are C#'s precedent;
//   * it is an INSTANCE member. Static state stays a field: `[ThreadStatic]` only exists on a
//     field, `Interlocked.Increment(ref Count)` needs an address, and no serializer, ORM or binder
//     reads statics;
//   * it is not `readonly` or `const` (both CLR FIELD words: `initonly` and literal) and not an
//     `event`;
//   * it is EXPORTED: PascalCase with no written word, or written with a non-private word
//     (`public`, `protected`, `internal`). A camelCase member, or one written `private`, is the
//     type's own storage — C#'s `private int _stock;` — and stays a field.
//
// `init Name: T` is ALWAYS a property — `{ get; init; }` — because the init promise lives on a
// setter and a field has none; that was true before this rule and the rule only names it.
//
// The analyzer (member kinds, hover, NL322, `ref`/`out`) and the emitter (metadata) both ask this
// one function, so what a diagnostic says and what reflection shows cannot disagree.
class MemberStorageRules {

    // THE RULE, over decoded booleans. `modifierFlags` is the `Modifiers` word; only its five
    // visibility bits are read here, so a caller holding a visibility-only column may pass that.
    static func IsAutoPropertyMember(declaringTypeIsReference: bool, name: string?, modifierFlags: int, isStatic: bool, isReadonly: bool, isConst: bool, isEvent: bool, isInit: bool): bool {
        if isStatic || isConst || isEvent {
            return false
        }

        if isInit {
            return true
        }

        if !declaringTypeIsReference || isReadonly {
            return false
        }

        return IsExportedStorage(name, modifierFlags)
    }

    // THE SAME RULE, TAKING THE DECLARATION'S WHOLE `Modifiers` WORD — the analyzer's spelling.
    static func IsAutoPropertyDeclaration(declaringTypeIsReference: bool, name: string?, modifierFlags: int): bool {
        return IsAutoPropertyMember(
            declaringTypeIsReference,
            name,
            modifierFlags,
            (modifierFlags & 16) != 0,
            (modifierFlags & 512) != 0,
            (modifierFlags & 1024) != 0,
            false,
            (modifierFlags & 16384) != 0
        )
    }

    // THE SAME RULE, ASKED OF SYNTAX: is `member`, declared directly in `owner`, an auto-property?
    // Only a `FieldDeclaration` can be one — a `PropertyDeclaration` already wrote its accessors.
    static func IsAutoPropertyField(owner: Declaration?, member: FieldDeclaration): bool {
        return IsAutoPropertyDeclaration(DeclaresReferenceMembers(owner), member.Name, Convert.ToInt32(member.Modifiers))
    }

    // A PRIMARY CONSTRUCTOR'S PARAMETER DECLARES A MEMBER OF ITS OWN NAME, and that member follows the
    // same rule: `record Person(Name: string)` declares the property `Name`, as C#'s positional record
    // does, and `class Service(logger: ILogger)` keeps the private capture `logger` a field.
    static func IsAutoPropertyParameter(owner: Declaration?, parameterName: string?): bool {
        return IsAutoPropertyMember(DeclaresReferenceMembers(owner), parameterName, 0, false, false, false, false, false)
    }

    // A `class`, or a `record` that is not a `record struct`: the declarations whose exported value
    // members are properties. A struct, a union case, an interface and a struct-of-arrays record are not.
    static func DeclaresReferenceMembers(owner: Declaration?): bool {
        classDeclaration := owner as ClassDeclaration
        if classDeclaration != null {
            return true
        }

        recordDeclaration := owner as RecordDeclaration
        return recordDeclaration != null && !recordDeclaration.IsStruct
    }

    // A WRITTEN WORD DECIDES WHEN THERE IS ONE; THE CASING DECIDES WHEN THERE IS NOT. `private` is
    // storage. `public`, `protected` and `internal` each say another type may reach the member,
    // which is exactly what a property is for — so `protected Seed: int` is a protected property,
    // which is what C# recommends over a protected field (CA1051).
    static func IsExportedStorage(name: string?, modifierFlags: int): bool {
        if (modifierFlags & 2) != 0 && (modifierFlags & 8) == 0 {
            return false
        }

        // Public 1 | Internal 4 | Protected 8.
        if (modifierFlags & 13) != 0 {
            return true
        }

        return VisibilityConventions.IsExportedIdentifier(name)
    }
}
