namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE FIVE THINGS AN EXPLICIT INTERFACE IMPLEMENTATION CAN GET WRONG, ANSWERED BEFORE EMIT.
//
// `func IEnumerable.GetEnumerator(): IEnumerator { … }` is a member whose name names its own slot, and
// a name can be wrong in ways an ordinary member's cannot: the interface may not be one this type
// implements, the interface may declare no such member, two declarations may claim the same slot, a
// modifier word may contradict what an explicit implementation IS, and a generic interface may be
// written open when only a closed one names a slot.
//
// **THEY ARE ANALYZER DIAGNOSTICS AND NOT EMIT DECLINES, and that distinction is the product.** The
// backend refuses all five as well — it has to, because a MethodImpl row naming a method the type does
// not implement emits an assembly the CLR rejects at LOAD — but a decline says "the columnar backend
// declined" at no position. These say which interface, which member, and what to write instead, on the
// declaration itself.
//
// ONE OWNER, BECAUSE THE FIVE SHARE THEIR WHOLE INPUT: the type's written interface list resolved to
// its inherited closure, and the member's qualified name split at its last top-level dot. Splitting
// them would have meant resolving that closure five times.
class AnalyzerExplicitInterfaceImplementation {
    diagnosticsValue: AnalyzerDiagnosticSink
    typeResolverValue: AnalyzerTypeResolver

    constructor(diagnostics: AnalyzerDiagnosticSink, typeResolver: AnalyzerTypeResolver) {
        diagnosticsValue = diagnostics
        typeResolverValue = typeResolver
    }

    // `writtenInterfaces` is the declaration's own base/interface list — positional, so it may hold a
    // base CLASS too; a candidate that does not resolve to an interface is simply not a candidate.
    func Validate(typeName: string, members: List<Declaration>?, writtenInterfaces: List<TypeReference>?) {
        if members == null {
            return
        }

        candidates := ResolveInterfaceClosure(writtenInterfaces)
        claimedSpellings := new HashSet<string>(StringComparer.Ordinal)
        claimedSlots := new HashSet<string>(StringComparer.Ordinal)

        for member in members {
            actualName := DeclaredMemberName(member)
            if !ExplicitInterfaceMemberFacts.IsExplicitMemberName(actualName) {
                continue
            }

            qualifier := ExplicitInterfaceMemberFacts.QualifierOf(actualName)
            simpleName := ExplicitInterfaceMemberFacts.SimpleNameOf(actualName)
            line := member.Line
            column := member.Column
            length := actualName.Length

            // (1) A MODIFIER WORD CONTRADICTS WHAT THIS MEMBER IS. An explicit implementation is
            // private, final, virtual and newslot by construction; there is nothing for a word to
            // decide, and `static` has no slot to fill at all.
            modifierWord := ContradictedModifierWord(DeclaredModifiers(member))
            if modifierWord != "" {
                diagnosticsValue.Report(
                    ErrorCode.ExplicitInterfaceImplementationModifier,
                    "'" + modifierWord + "' cannot be written on the explicit interface implementation '" + actualName + "'",
                    line,
                    column,
                    "Remove '" + modifierWord + "'. An explicit interface implementation is private, final and virtual by construction — it is reached only through '" + qualifier + "', so there is no accessibility to state and no slot for '" + modifierWord + "' to change.",
                    length
                )
                continue
            }

            // (2) TWO DECLARATIONS CANNOT CLAIM ONE SLOT — and the interesting half is the one the
            // ordinary duplicate-member rule cannot see. Two members written with the SAME name are
            // already `NL306`, whatever their names are, so that case is left to it rather than
            // reported twice. What is new here is two DIFFERENT spellings of one slot:
            // `IEnumerable.GetEnumerator` and `System.Collections.IEnumerable.GetEnumerator` are two
            // member names and one interface member, so nothing else in the analyzer can tell.
            if !claimedSpellings.Add(actualName) {
                continue
            }

            matched := MatchByName(candidates, qualifier)
            if matched.Count > 0 && !claimedSlots.Add(SlotKey(matched, ExplicitInterfaceMemberFacts.QualifierArity(qualifier), simpleName)) {
                diagnosticsValue.Report(
                    ErrorCode.DuplicateExplicitInterfaceImplementation,
                    "'" + typeName + "' implements the interface member '" + simpleName + "' of '" + ExplicitInterfaceMemberFacts.QualifierSimpleName(qualifier) + "' explicitly more than once",
                    line,
                    column,
                    "Keep one of them. A slot has one implementation, and two spellings of the same interface — with and without its namespace — name the same slot rather than two.",
                    length
                )
                continue
            }

            if matched.Count == 0 {
                // (3) THE INTERFACE IS NOT ONE THIS TYPE IMPLEMENTS.
                diagnosticsValue.Report(
                    ErrorCode.ExplicitInterfaceNotImplemented,
                    "'" + typeName + "' does not implement '" + qualifier + "', so it cannot implement '" + actualName + "' explicitly",
                    line,
                    column,
                    "Add '" + qualifier + "' to the declaration's interface list, or drop the qualifier so this becomes an ordinary member named '" + simpleName + "'.",
                    length
                )
                continue
            }

            closedMatch := MatchByArity(matched, ExplicitInterfaceMemberFacts.QualifierArity(qualifier))
            if closedMatch == null {
                // (4) A GENERIC INTERFACE NAMES A SLOT ONLY WHEN IT IS CLOSED. `IEnumerable<T>` has as
                // many slot sets as it has instantiations; the qualifier has to say which one, with the
                // same arguments the implements list writes.
                diagnosticsValue.Report(
                    ErrorCode.ExplicitInterfaceQualifierNotClosed,
                    "'" + qualifier + "' does not name the interface the way '" + typeName + "' implements it",
                    line,
                    column,
                    "Write the interface closed, with the same type arguments the declaration's interface list writes — " + ExpectedQualifierList(matched) + ".",
                    length
                )
                continue
            }

            // (5) THE INTERFACE DECLARES NO SUCH MEMBER. Asked by NAME only: the signature is the
            // backend's business, and an interface with no member of this name can never be right.
            if !DeclaresMemberNamed(closedMatch, simpleName) {
                diagnosticsValue.Report(
                    ErrorCode.ExplicitInterfaceMemberNotFound,
                    "'" + qualifier + "' declares no member named '" + simpleName + "'",
                    line,
                    column,
                    "Check the spelling against '" + qualifier + "'. An explicit implementation may only name a member the interface itself declares; an inherited one is implemented by naming the interface that declares it.",
                    length
                )
            }
        }
    }

    // A modifier word that contradicts an explicit implementation, or "" when none was written. The
    // four accessibility words come first because they are the ones a reader reaches for.
    static func ContradictedModifierWord(modifiers: Modifiers): string {
        value := Convert.ToInt32(modifiers)
        if (value & 1) != 0 {
            return "public"
        }
        if (value & 2) != 0 {
            return "private"
        }
        if (value & 4) != 0 {
            return "internal"
        }
        if (value & 8) != 0 {
            return "protected"
        }
        if (value & 16) != 0 {
            return "static"
        }
        if (value & 32) != 0 {
            return "virtual"
        }
        if (value & 64) != 0 {
            return "abstract"
        }
        if (value & 65536) != 0 {
            return "override"
        }
        if (value & 128) != 0 {
            return "sealed"
        }
        return ""
    }

    // The member's declared name, or EMPTY when the declaration has none. Empty rather than null
    // because every caller's next question is about the SPELLING, and a name that is not there is a
    // name that is not qualified.
    static func DeclaredMemberName(member: Declaration): string {
        function := member as FunctionDeclaration
        if function != null {
            return function.Name
        }

        property := member as PropertyDeclaration
        if property != null {
            return property.Name
        }

        field := member as FieldDeclaration
        if field != null {
            return field.Name
        }

        eventMember := member as EventDeclaration
        if eventMember != null {
            return eventMember.Name
        }

        return ""
    }

    static func DeclaredModifiers(member: Declaration): Modifiers {
        function := member as FunctionDeclaration
        if function != null {
            return function.Modifiers
        }

        property := member as PropertyDeclaration
        if property != null {
            return property.Modifiers
        }

        field := member as FieldDeclaration
        if field != null {
            return field.Modifiers
        }

        eventMember := member as EventDeclaration
        if eventMember != null {
            return eventMember.Modifiers
        }

        return Modifiers.None
    }

    // THE WRITTEN INTERFACE LIST, CLOSED OVER WHAT EACH ENTRY INHERITS. A type that writes
    // `IEnumerable<string>` also implements `IEnumerable`, and `IEnumerable.GetEnumerator` is the
    // canonical explicit implementation — so an entry's own inherited interfaces are candidates too.
    func ResolveInterfaceClosure(writtenInterfaces: List<TypeReference>?): List<AnalyzerExplicitInterfaceCandidate> {
        candidates := new List<AnalyzerExplicitInterfaceCandidate>()
        if writtenInterfaces == null {
            return candidates
        }

        for reference in writtenInterfaces {
            resolved := typeResolverValue.ResolveType(reference)
            if resolved == null {
                continue
            }

            AddCandidateClosure(candidates, resolved, 0)
        }

        return candidates
    }

    func AddCandidateClosure(candidates: List<AnalyzerExplicitInterfaceCandidate>, candidate: TypeInfo, depth: int) {
        if depth > 16 {
            return
        }

        generic := candidate as GenericTypeInfo
        definition := candidate
        arity := 0
        if generic != null {
            genericDefinition := generic.GenericDefinition
            if genericDefinition == null {
                return
            }

            definition = genericDefinition
            arity = generic.TypeArguments.Count
        }

        sourceInterface := definition as InterfaceTypeInfo
        if sourceInterface != null {
            candidates.Add(new AnalyzerExplicitInterfaceCandidate(sourceInterface.Name, arity, candidate, definition))
            for baseReference in sourceInterface.BaseInterfaces {
                resolvedBase := typeResolverValue.ResolveType(baseReference)
                if resolvedBase != null {
                    AddCandidateClosure(candidates, resolvedBase, depth + 1)
                }
            }

            return
        }

        reflectionType := definition as ReflectionTypeInfo
        if reflectionType == null {
            return
        }

        if !reflectionType.Type.get_IsInterface() {
            return
        }

        candidates.Add(new AnalyzerExplicitInterfaceCandidate(SimpleReflectedName(reflectionType.Type), ReflectedArity(reflectionType.Type, arity), candidate, definition))
        for inherited in reflectionType.Type.GetInterfaces() {
            candidates.Add(new AnalyzerExplicitInterfaceCandidate(SimpleReflectedName(inherited), inherited.GetGenericArguments().Length, new ReflectionTypeInfo(inherited), new ReflectionTypeInfo(inherited)))
        }
    }

    // A closed generic resolves to a `GenericTypeInfo` whose arity the wrapper carries; an already
    // closed reflected type carries its own. Whichever said it, the count is the number of arguments
    // the qualifier has to write.
    static func ReflectedArity(reflectedType: Type, wrapperArity: int): int {
        if wrapperArity > 0 {
            return wrapperArity
        }

        return reflectedType.GetGenericArguments().Length
    }

    static func SimpleReflectedName(reflectedType: Type): string {
        name := reflectedType.get_Name()
        tick := name.IndexOf('`')
        if tick >= 0 {
            return name.Substring(0, tick)
        }

        return name
    }

    // A written qualifier matches a candidate when their SIMPLE names agree — a qualifier written with
    // its namespace (`System.Collections.IEnumerable`) names the same interface as the bare spelling,
    // and the namespace half is not what distinguishes one implemented interface from another here.
    static func MatchByName(candidates: List<AnalyzerExplicitInterfaceCandidate>, qualifier: string): List<AnalyzerExplicitInterfaceCandidate> {
        writtenName := ExplicitInterfaceMemberFacts.QualifierSimpleName(qualifier)
        matched := new List<AnalyzerExplicitInterfaceCandidate>()
        for candidate in candidates {
            if candidate.SimpleName == writtenName {
                matched.Add(candidate)
            }
        }

        return matched
    }

    // The SLOT's identity, independent of how the qualifier was spelled: the interface's simple name
    // and arity, plus the member's own name.
    static func SlotKey(matched: List<AnalyzerExplicitInterfaceCandidate>, writtenArity: int, simpleName: string): string {
        return matched[0].SimpleName + "`" + writtenArity.ToString() + "." + simpleName
    }

    static func MatchByArity(matched: List<AnalyzerExplicitInterfaceCandidate>, writtenArity: int): AnalyzerExplicitInterfaceCandidate? {
        for candidate in matched {
            if candidate.Arity == writtenArity {
                return candidate
            }
        }

        return null
    }

    static func ExpectedQualifierList(matched: List<AnalyzerExplicitInterfaceCandidate>): string {
        text := ""
        for candidate in matched {
            if text.Length > 0 {
                text = text + " or "
            }

            text = text + "'" + candidate.SimpleName + ArityHint(candidate.Arity) + "'"
        }

        if text.Length == 0 {
            return "with its type arguments"
        }

        return text
    }

    static func ArityHint(arity: int): string {
        if arity == 0 {
            return ""
        }

        hint := "<"
        index := 0
        while index < arity {
            if index > 0 {
                hint = hint + ", "
            }

            hint = hint + "…"
            index = index + 1
        }

        return hint + ">"
    }

    // Whether the interface declares a member of that name. A source interface answers from its own
    // declared members; a reflected one answers from its methods, properties and events, and an
    // accessor is not asked about under its own name because an interface's value member is demanded
    // under the member's name everywhere else in this analyzer.
    static func DeclaresMemberNamed(candidate: AnalyzerExplicitInterfaceCandidate, simpleName: string): bool {
        sourceInterface := candidate.Definition as InterfaceTypeInfo
        if sourceInterface != null {
            for declared in sourceInterface.DeclaredMembers {
                if declared.Name == simpleName {
                    return true
                }
            }

            return false
        }

        reflectionType := candidate.Definition as ReflectionTypeInfo
        if reflectionType == null {
            return true
        }

        reflectedType := reflectionType.Type
        for method in reflectedType.GetMethods() {
            if method.get_Name() == simpleName {
                return true
            }
        }

        for property in reflectedType.GetProperties() {
            if property.get_Name() == simpleName {
                return true
            }
        }

        for declaredEvent in reflectedType.GetEvents() {
            if declaredEvent.get_Name() == simpleName {
                return true
            }
        }

        return false
    }
}

// One interface a type implements, as the qualifier has to name it: its simple name, how many type
// arguments it closes over, the closed form and the definition the members live on.
class AnalyzerExplicitInterfaceCandidate {
    SimpleName: string
    Arity: int
    Closed: TypeInfo
    Definition: TypeInfo

    constructor(simpleName: string, arity: int, closed: TypeInfo, definition: TypeInfo) {
        SimpleName = simpleName
        Arity = arity
        Closed = closed
        Definition = definition
    }
}
