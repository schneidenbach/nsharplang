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
            for arm in arms {
                armName := Base(arm)
                if armName != null {
                    return armName
                }
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
            for arm in arms {
                armName := Base(arm)
                if armName != null {
                    return BaseNameSpan(arm)
                }
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
            for argument in arguments {
                CollectMentionedNames(argument, into)
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
            for arm in arms {
                CollectMentionedNames(arm, into)
            }

            return
        }

        tuple := typeReference as TupleTypeReference
        if tuple != null {
            elements := tuple.Elements
            for element in elements {
                CollectMentionedNames(element.Type, into)
            }

            return
        }

        functionReference := typeReference as FunctionTypeReference
        if functionReference != null {
            // The written identifier — `Func` — is a name this type MENTIONS, and it is the only one
            // that says which import supplies the delegate itself. A hand-built node answers the empty
            // string and contributes nothing.
            writtenName := functionReference.WrittenName
            if writtenName.Length > 0 {
                into.Add(writtenName)
            }

            CollectMentionedNames(functionReference.ReturnType, into)
            parameterTypes := functionReference.ParameterTypes
            for parameterType in parameterTypes {
                CollectMentionedNames(parameterType, into)
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
            for argument in arguments {
                CollectNamedReferences(argument, into)
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
            for element in elements {
                CollectNamedReferences(element.Type, into)
            }

            return
        }

        functionReference := typeReference as FunctionTypeReference
        if functionReference != null {
            CollectNamedReferences(functionReference.ReturnType, into)
            parameterTypes := functionReference.ParameterTypes
            for parameterType in parameterTypes {
                CollectNamedReferences(parameterType, into)
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

// NL002 — "this name is used without the import that provides it."
//
// THE RULE IS AN ANALYSIS, AND IT USED TO BE A WHITELIST. This owner carried two hand-written tables
// of names the BCL is known to provide — 25 for a bare identifier, 16 for a written type — and spoke
// only when a file wrote one of those without importing the namespace beside it. That made the rule
// silent for every other name in the framework: `OperatingSystem.IsWindows()` with no `import System`
// was accepted without a word, while its mirror — the same file WITH the import — had NL010 report
// the import dead, because NL010's own table had never heard of the name either. Two tables, two
// gaps, one name falling through both.
//
// IT IS NOW THE OTHER READING OF NL010'S FACT. When a simple name resolves, the analyzer records the
// namespace that supplied it (`ImportUsageFacts`). If the file imports that namespace, the import is
// used and NL010 stays quiet; if it does not, this rule speaks. The two cannot disagree, because
// there is one measurement and no list anywhere.
//
// ONLY A METADATA TYPE IS EVER A FINDING, and the analyzer decides that, not this rule. A SOURCE type
// declared in another namespace of the same project resolves with no import at all — that is the
// language's rule, proven by `namespace A` writing a type from `namespace B` and building — so it is
// never recorded as needing one, and demanding `import` for a sibling namespace would be wrong.
//
// THE POSITION IS STILL THE LINTER'S. The analyzer records WHICH import a name needs; where the
// squiggle goes is a span question the walk already answers for every position a type can be written
// in — a `new`, an annotation, a type argument, a bare identifier — and it answers it better than a
// re-derivation from the source line could.
//
// FOUR THINGS SILENCE IT, IN THIS ORDER, AND THE ORDER IS OBSERVABLE. A file that was never analysed
// has no answer at all; a name declared by an enclosing type's own members is not a BCL name; a name
// brought in by a FILE import is already resolved; and a namespace that is already imported needs no
// second import.
class LinterMissingImport {

    // The identifier arm: a bare name written in code. Answers with the namespace that must be
    // imported, or nothing when the rule stays silent.
    static func MissingNamespaceForIdentifier(name: string, usage: ImportUsageFacts?, typeMemberNameScopes: Stack<HashSet<string>>, importedFileSymbols: HashSet<string>, importedNamespaces: List<string>): string? {
        for scope in typeMemberNameScopes {
            if scope.Contains(name) {
                return null
            }
        }

        return MissingNamespace(SupplyingNamespace(usage, name), name, importedFileSymbols, importedNamespaces)
    }

    // The type arm: a name written as a type. It never consults the member scopes — a `new` names a
    // TYPE, and an enclosing type's member cannot shadow one.
    static func MissingNamespaceForTypeName(typeName: string, usage: ImportUsageFacts?, importedFileSymbols: HashSet<string>, importedNamespaces: List<string>): string? {
        return MissingNamespace(SupplyingNamespace(usage, typeName), typeName, importedFileSymbols, importedNamespaces)
    }

    // WHICH NAMESPACE SUPPLIED THIS SPELLING, according to the analysis of this file. Nothing when the
    // file was never analysed, when its analysis did not complete, or when the name did not resolve to
    // a metadata type — a local, a member, a type parameter, a source declaration or a name that did
    // not resolve at all. Each of those is silence rather than a guess.
    static func SupplyingNamespace(usage: ImportUsageFacts?, name: string): string? {
        if usage == null {
            return null
        }

        facts := usage ?? new ImportUsageFacts()
        if !facts.Analyzed {
            return null
        }

        return facts.SupplierFor(name)
    }

    static func MissingNamespace(requiredNamespace: string?, name: string, importedFileSymbols: HashSet<string>, importedNamespaces: List<string>): string? {
        if requiredNamespace == null {
            return null
        }

        if importedFileSymbols.Contains(name) {
            return null
        }

        if importedNamespaces.Contains(requiredNamespace ?? "") {
            return null
        }

        return requiredNamespace
    }

    // ── what the diagnostic says ─────────────────────────────────────────────────────────────

    // The sentence describes the missing import, not a resolution failure. NL002 IS IMPORT HYGIENE:
    // what is true of every finding is that the name is written and the import that provides it is
    // not there, and that is what it says. The SUGGESTION — the useful half, and the one the IDE
    // quick fix applies — is contracted never to break a build.
    static func Message(name: string): string {
        return "'" + name + "' is used without the import that provides it"
    }

    static func Suggestion(requiredNamespace: string): string {
        return "Add 'import " + requiredNamespace + "' at the top of the file"
    }
}
