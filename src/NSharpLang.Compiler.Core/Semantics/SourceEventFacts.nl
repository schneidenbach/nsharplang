namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast


// THE THREE QUESTIONS A SOURCE-DECLARED EVENT ASKS OF ITS OWNER, and nothing else.
//
// An event reads one way inside the type that declared it and another way everywhere else, so every
// owner that resolves one has to ask the same pair: what is the declaring type CALLED, and is the code
// asking currently inside it. Both answers come from the declaration's own recorded name, so the two
// halves of the rule — the resolver that picks the reading and the reporter that names the type in its
// sentence — cannot drift apart.
class SourceEventFacts {

    // WHETHER THE DECLARED EVENT OF THIS NAME CARRIES `abstract`. It is the one event shape with no
    // backing delegate at all, which is why the "inside the declaring type the name IS the field" rule
    // has to ask: there is no field to be.
    static func IsAbstractDeclaredEvent(members: DeclaredMemberInfo[], name: string): bool {
        for member in members {
            if member.Name == name && member.Kind == DeclaredMemberKind.Event {
                return (member.DeclaredModifiers & Convert.ToInt32(Modifiers.Abstract)) != 0
            }
        }

        return false
    }

    // The declaring type's name as the source wrote it, or the empty string for a shape that is not a
    // source type declaration at all (which no event can be declared on).
    static func DeclaringTypeName(owner: TypeInfo?): string {
        classType := owner as ClassTypeInfo
        if classType != null {
            return classType.Name
        }

        structType := owner as StructTypeInfo
        if structType != null {
            return structType.Name
        }

        recordType := owner as RecordTypeInfo
        if recordType != null {
            return recordType.Name
        }

        interfaceType := owner as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Name
        }

        return ""
    }

    // Whether the declaring type is a VALUE type, which is the one shape `on` cannot bind an instance
    // event through: the receiver it would subscribe to is a copy, so the handler would attach to
    // storage the caller never sees again.
    static func DeclaringTypeIsValueType(owner: TypeInfo?): bool {
        if owner as StructTypeInfo != null {
            return true
        }

        recordType := owner as RecordTypeInfo
        return recordType != null && recordType.IsStruct
    }

    // WHETHER THE CODE BEING ANALYSED IS THE DECLARING TYPE'S OWN. C#'s rule exactly: the backing
    // delegate is visible to the declaring type and to nobody else — not even to a derived type, whose
    // code may only subscribe like any other caller. A name that is not a source type's answers no.
    static func IsInsideDeclaringType(owner: TypeInfo?, currentTypeName: string?): bool {
        declaringTypeName := DeclaringTypeName(owner)
        if declaringTypeName.Length == 0 || currentTypeName == null || currentTypeName.Length == 0 {
            return false
        }

        if currentTypeName == declaringTypeName {
            return true
        }

        // The ambient name may be fully qualified (`App.Widget`) where the declaration recorded only
        // the simple name, so a trailing segment match is the same type.
        lastDot := currentTypeName.LastIndexOf('.')
        return lastDot >= 0 && currentTypeName.Substring(lastDot + 1) == declaringTypeName
    }
}
