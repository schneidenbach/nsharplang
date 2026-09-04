namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHAT A TYPE REFERENCE IS CALLED, for the two linter rules that need a bare name out of a written
// type. `List<int>?[]` is called `List`; a tuple, a function type and a pointer are called nothing.
//
// THE UNION RULE IS THE ONE THAT IS NOT OBVIOUS AND IT IS PRESERVED EXACTLY: a union answers with
// its FIRST arm that has a name of its own, not with its first arm — so `(int, int) | List<int>`
// is called `List`, and a union whose every arm is nameless is called nothing. An empty union is
// nameless too, which is what makes the arms loop safe to write as a scan.
//
// The kinds that answer NOTHING are as much of the contract as the kinds that answer something:
// NL002 must not demand an import for a tuple, and NL010 must not record one as a used identifier.
class LinterTypeReferenceName {
    static func Base(typeReference: TypeReference): string? {
        simple := typeReference as SimpleTypeReference
        if simple != null {
            return simple.Name
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            return generic.Name
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return Base(nullable.InnerType)
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return Base(array.ElementType)
        }

        unionReference := typeReference as UnionTypeReference
        if unionReference != null {
            arms := unionReference.Arms
            index := 0
            while index < arms.Count {
                armName := Base(arms[index])
                if armName != null {
                    return armName
                }

                index = index + 1
            }

            return null
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return Base(byRef.InnerType)
        }

        return null
    }

    // WHERE the name `Base` answered with is WRITTEN. `Base` says `List<int>?[]` is called `List`;
    // this says which four columns `List` occupies, so a diagnostic ABOUT the name can land ON the
    // name instead of on whatever syntax happened to enclose it.
    //
    // THE TRAVERSAL IS `Base`'S, ARM FOR ARM, AND THAT IS WHY IT LIVES HERE. The two answer the same
    // question about the same reference — what is this type called, and where is that written — so a
    // caller that got them from two different walks could report one arm's NAME at another arm's
    // COLUMNS. Keeping them adjacent is the same argument this file's header makes for `Base` against
    // `CollectMentionedNames`: the pair is only safe while it is impossible to change one without
    // seeing the other.
    //
    // A reference the parser never stamped — a hand-built tree, a synthesised `var` parameter —
    // answers `SourceSpan.None`, because `NameSpan` folds a zero line or column to `None`. That is
    // not a failure: it is the signal that the caller's own position is the only one there is.
    static func BaseNameSpan(typeReference: TypeReference): SourceSpan {
        simple := typeReference as SimpleTypeReference
        if simple != null {
            return simple.NameSpan
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            return generic.NameSpan
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return BaseNameSpan(nullable.InnerType)
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return BaseNameSpan(array.ElementType)
        }

        unionReference := typeReference as UnionTypeReference
        if unionReference != null {
            arms := unionReference.Arms
            index := 0
            while index < arms.Count {
                armName := Base(arms[index])
                if armName != null {
                    return BaseNameSpan(arms[index])
                }

                index = index + 1
            }

            return SourceSpan.None
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return BaseNameSpan(byRef.InnerType)
        }

        return SourceSpan.None
    }

    // EVERY name a written type mentions, not just the one it is CALLED. `Base` answers with one
    // name and stops; this walks the whole reference and collects them all, so
    // `Dictionary<string, List<Widget>>` mentions four names and not one.
    //
    // THE TWO ARE DIFFERENT QUESTIONS ASKED BY TWO DIFFERENT RULES, and running them together here
    // is what keeps them from drifting apart. NL002 asks what a type is CALLED, because it needs a
    // single name to look up in its table. NL010 asks what a type MENTIONS, because an import is
    // used the moment any name it provides appears anywhere in a written type — including inside a
    // type argument, a tuple element or a function type's parameter list, none of which `Base` ever
    // reaches. A union is where the difference is sharpest: `int | Widget` is CALLED `int`, but it
    // MENTIONS `Widget` too, and dropping that would report a live import as unused.
    //
    // The result is written into a caller-owned set rather than returned, because the linter calls
    // this on every declared field, property, parameter and return type in a file and a per-call
    // allocation would be the walk's dominant cost. `MentionedNames` is the same walk with its own
    // list, for callers that want one.
    static func CollectMentionedNames(typeReference: TypeReference?, into: HashSet<string>) {
        if typeReference == null {
            return
        }

        simple := typeReference as SimpleTypeReference
        if simple != null {
            into.Add(simple.Name)
            return
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            into.Add(generic.Name)
            arguments := generic.TypeArguments
            index := 0
            while index < arguments.Count {
                CollectMentionedNames(arguments[index], into)
                index = index + 1
            }

            return
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            CollectMentionedNames(nullable.InnerType, into)
            return
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            CollectMentionedNames(array.ElementType, into)
            return
        }

        unionReference := typeReference as UnionTypeReference
        if unionReference != null {
            arms := unionReference.Arms
            armIndex := 0
            while armIndex < arms.Count {
                CollectMentionedNames(arms[armIndex], into)
                armIndex = armIndex + 1
            }

            return
        }

        tuple := typeReference as TupleTypeReference
        if tuple != null {
            elements := tuple.Elements
            elementIndex := 0
            while elementIndex < elements.Count {
                CollectMentionedNames(elements[elementIndex].Type, into)
                elementIndex = elementIndex + 1
            }

            return
        }

        functionReference := typeReference as FunctionTypeReference
        if functionReference != null {
            CollectMentionedNames(functionReference.ReturnType, into)
            parameterTypes := functionReference.ParameterTypes
            parameterIndex := 0
            while parameterIndex < parameterTypes.Count {
                CollectMentionedNames(parameterTypes[parameterIndex], into)
                parameterIndex = parameterIndex + 1
            }

            return
        }

        byRefReference := typeReference as ByRefTypeReference
        if byRefReference != null {
            CollectMentionedNames(byRefReference.InnerType, into)
        }
    }

    // The same walk with its own set, for callers that want the answer rather than an accumulator.
    // Ordinal, because a type name differing only in case is a different type.
    static func MentionedNames(typeReference: TypeReference?): HashSet<string> {
        result := new HashSet<string>(StringComparer.Ordinal)
        CollectMentionedNames(typeReference, result)
        return result
    }

    // THE THIRD QUESTION, AND IT IS THE ONE A DIAGNOSTIC NEEDS. `Base` answers one name and where it
    // is written; `CollectMentionedNames` answers every name and no position at all. A rule that
    // reports per name — which NL002 now is — needs every name AND each one's own position, so it
    // needs the REFERENCES, not their names: `Dictionary<string, StringBuilder>` is two findings at
    // two different columns, and neither `Base` nor `MentionedNames` can express that.
    //
    // THE ORDER IS PART OF THE CONTRACT: the reference `Base` would have named comes FIRST. That is
    // what lets a caller give its own fallback position to the base name and to nothing else — the
    // enclosing syntax (`new`, a parameter list) is a sensible place to put a diagnostic about the
    // type as a whole and a nonsensical place to put one about its third type argument. It holds
    // arm for arm: a wrapper yields its inner list, a generic yields itself then its arguments, and
    // a union yields its first NAMED arm's list before the rest. A tuple and a function type have no
    // base name at all — `Base` says so — so their first entry is just their first named part, and
    // the caller checks `Base` before handing out a fallback.
    //
    // Nameless kinds contribute nothing of their own and are not skipped: a tuple is not a type
    // name, but `(int, Widget)` still mentions `Widget` somewhere a user can point at.
    static func CollectNamedReferences(typeReference: TypeReference?, into: List<TypeReference>) {
        if typeReference == null {
            return
        }

        simple := typeReference as SimpleTypeReference
        if simple != null {
            into.Add(simple)
            return
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            into.Add(generic)
            arguments := generic.TypeArguments
            index := 0
            while index < arguments.Count {
                CollectNamedReferences(arguments[index], into)
                index = index + 1
            }

            return
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            CollectNamedReferences(nullable.InnerType, into)
            return
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            CollectNamedReferences(array.ElementType, into)
            return
        }

        byRefReference := typeReference as ByRefTypeReference
        if byRefReference != null {
            CollectNamedReferences(byRefReference.InnerType, into)
            return
        }

        unionReference := typeReference as UnionTypeReference
        if unionReference != null {
            arms := unionReference.Arms
            // The first NAMED arm goes first, because that is the one `Base` answers with. The scan
            // asks `Base` rather than re-deciding what "named" means, so the two cannot disagree.
            named := -1
            armIndex := 0
            while armIndex < arms.Count {
                if named < 0 {
                    if Base(arms[armIndex]) != null {
                        named = armIndex
                    }
                }

                armIndex = armIndex + 1
            }

            if named >= 0 {
                CollectNamedReferences(arms[named], into)
            }

            restIndex := 0
            while restIndex < arms.Count {
                if restIndex != named {
                    CollectNamedReferences(arms[restIndex], into)
                }

                restIndex = restIndex + 1
            }

            return
        }

        tuple := typeReference as TupleTypeReference
        if tuple != null {
            elements := tuple.Elements
            elementIndex := 0
            while elementIndex < elements.Count {
                CollectNamedReferences(elements[elementIndex].Type, into)
                elementIndex = elementIndex + 1
            }

            return
        }

        functionReference := typeReference as FunctionTypeReference
        if functionReference != null {
            CollectNamedReferences(functionReference.ReturnType, into)
            parameterTypes := functionReference.ParameterTypes
            parameterIndex := 0
            while parameterIndex < parameterTypes.Count {
                CollectNamedReferences(parameterTypes[parameterIndex], into)
                parameterIndex = parameterIndex + 1
            }
        }
    }

    // The same walk with its own list, for callers that want the answer rather than an accumulator.
    static func NamedReferences(typeReference: TypeReference?): List<TypeReference> {
        result := new List<TypeReference>()
        CollectNamedReferences(typeReference, result)
        return result
    }
}

// NL002 — "I can't find this name, and it looks like a missing import."
//
// THE RULE IS A WHITELIST, NEVER AN ANALYSIS. It carries a small table of names the BCL is known to
// provide, and it speaks only when a file writes one of those names without importing the namespace
// that provides it. A name the table does not carry is never reported, because "I have not heard of
// this" is not evidence of a missing import — it is evidence of nothing.
//
// IT IS ASKED AT TWO PLACES AND THE TWO TABLES ARE NOT THE SAME, WHICH IS THE POINT OF SPLITTING
// THEM. A bare IDENTIFIER (`DateTime.Now`, `Guid.NewGuid()`) is answered by the 25-name table; a
// TYPE written in a `new` (`new List<int>()`) is answered by a 16-name table that is the first
// sixteen rows of the other one. The nine names that only the identifier table carries — `Encoding`,
// `DateTime`, `TimeSpan`, `Guid`, `Uri`, `Tuple`, `Lazy`, `Action`, `Func` — are the ones a file
// nearly always writes as a STATIC receiver rather than constructs, and the type table's silence on
// them is deliberate: `new Guid()` and `new Action()` are not how those names are used, so demanding
// an import there would be noise. The subset relationship is asserted rather than assumed.
//
// THREE THINGS SILENCE THE RULE, IN THIS ORDER, AND THE ORDER IS OBSERVABLE. A name declared by an
// enclosing type's own members is not a BCL name at all; a name brought in by a FILE import is
// already resolved; and a namespace that is already imported needs no second import. The first
// check runs before the table lookup, so a member called `Task` is silent even though `Task` is a
// table row; the other two run after it, so they can only silence a name the table carries.
class LinterMissingImport {

    // The identifier arm: a bare name written in code. Answers with the namespace that must be
    // imported, or nothing when the rule stays silent.
    static func MissingNamespaceForIdentifier(name: string, typeMemberNameScopes: Stack<HashSet<string>>, importedFileSymbols: HashSet<string>, importedNamespaces: List<string>): string? {
        for scope in typeMemberNameScopes {
            if scope.Contains(name) {
                return null
            }
        }

        return MissingNamespace(RequiredNamespaceForIdentifier(name), name, importedFileSymbols, importedNamespaces)
    }

    // The type arm: a name written as a type. It asks the smaller table and never consults the
    // member scopes — a `new` names a TYPE, and an enclosing type's member cannot shadow one.
    static func MissingNamespaceForTypeName(typeName: string, importedFileSymbols: HashSet<string>, importedNamespaces: List<string>): string? {
        return MissingNamespace(RequiredNamespaceForTypeName(typeName), typeName, importedFileSymbols, importedNamespaces)
    }

    static func MissingNamespace(requiredNamespace: string?, name: string, importedFileSymbols: HashSet<string>, importedNamespaces: List<string>): string? {
        if requiredNamespace == null {
            return null
        }

        if importedFileSymbols.Contains(name) {
            return null
        }

        if importedNamespaces.Contains(requiredNamespace) {
            return null
        }

        return requiredNamespace
    }

    // ── the two tables ───────────────────────────────────────────────────────────────────────

    static func RequiredNamespaceForIdentifier(name: string): string? {
        typeTableAnswer := RequiredNamespaceForTypeName(name)
        if typeTableAnswer != null {
            return typeTableAnswer
        }

        if Contains(TextOnlyIdentifierNames(), name) {
            return "System.Text"
        }

        if Contains(SystemIdentifierNames(), name) {
            return "System"
        }

        return null
    }

    static func RequiredNamespaceForTypeName(typeName: string): string? {
        if Contains(CollectionsGenericNames(), typeName) {
            return "System.Collections.Generic"
        }

        if Contains(TextNames(), typeName) {
            return "System.Text"
        }

        if Contains(RegularExpressionsNames(), typeName) {
            return "System.Text.RegularExpressions"
        }

        if Contains(IoNames(), typeName) {
            return "System.IO"
        }

        if Contains(NetHttpNames(), typeName) {
            return "System.Net.Http"
        }

        if Contains(TextJsonNames(), typeName) {
            return "System.Text.Json"
        }

        if Contains(ThreadingTasksNames(), typeName) {
            return "System.Threading.Tasks"
        }

        if Contains(ThreadingNames(), typeName) {
            return "System.Threading"
        }

        return null
    }

    // The sixteen rows both tables carry.
    static func CollectionsGenericNames(): string[] {
        return ["List", "Dictionary", "HashSet", "Queue", "Stack", "LinkedList"]
    }

    static func TextNames(): string[] {
        return ["StringBuilder"]
    }

    static func RegularExpressionsNames(): string[] {
        return ["Regex"]
    }

    static func IoNames(): string[] {
        return ["File", "Directory", "Path", "Stream"]
    }

    static func NetHttpNames(): string[] {
        return ["HttpClient"]
    }

    static func TextJsonNames(): string[] {
        return ["JsonSerializer"]
    }

    static func ThreadingTasksNames(): string[] {
        return ["Task"]
    }

    static func ThreadingNames(): string[] {
        return ["CancellationToken"]
    }

    // The nine rows the identifier table carries alone. `Encoding` shares `System.Text` with
    // `StringBuilder`, which is why it is a row of its own rather than part of `TextNames`.
    static func TextOnlyIdentifierNames(): string[] {
        return ["Encoding"]
    }

    static func SystemIdentifierNames(): string[] {
        return ["DateTime", "TimeSpan", "Guid", "Uri", "Tuple", "Lazy", "Action", "Func"]
    }

    static func Contains(names: string[], name: string): bool {
        index := 0
        while index < names.Length {
            if names[index] == name {
                return true
            }

            index = index + 1
        }

        return false
    }

    // ── what the diagnostic says ─────────────────────────────────────────────────────────────

    // THE SENTENCE HAD TO STOP CLAIMING THE COMPILER CANNOT FIND THE NAME, BECAUSE IT ALWAYS CAN.
    // Measured on the shipped CLI with the rule silenced: `StringBuilder`, `Task`,
    // `CancellationToken`, `List<int>` and `Stack<int>` BUILD with NO import at all, and the
    // rows that do fail — `Regex`, `HttpClient`, `Queue<int>` — fail IDENTICALLY WITH THEIR IMPORT,
    // because the columnar backend cannot lower those types yet. Not one row of this table is a
    // resolution failure, so "I can't find 'StringBuilder'" was false for every one of them.
    //
    // NL002 IS IMPORT HYGIENE. What is true of every row is that the name is written and the import
    // that provides it is not there, and that is what it now says. The SUGGESTION — the useful half,
    // and the one the IDE quick fix applies — is unchanged, and is contracted never breaking a build.
    static func Message(name: string): string {
        return "'" + name + "' is used without the import that provides it"
    }

    static func Suggestion(requiredNamespace: string): string {
        return "Add 'import " + requiredNamespace + "' at the top of the file"
    }
}
