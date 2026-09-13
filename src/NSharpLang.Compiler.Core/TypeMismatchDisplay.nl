namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text


// THE TWO TYPE NAMES A MISMATCH DIAGNOSTIC PRINTS, AND THE ONE RULE THAT DECIDES HOW MUCH OF EACH.
//
// "Expected `Range` but got `Range`" is the worst sentence a compiler can write: it states a
// contradiction and hands the reader nothing to act on. It happens because a type's display form is
// its SIMPLE name — the right choice nearly always, and exactly wrong when the two types a
// diagnostic is contrasting share one. C# answers this with minimal qualification: print as little
// as identifies the type, and print more only when less would not.
//
// So every mismatch diagnostic renders its PAIR here rather than calling `ToString` twice. The rule
// is a total function of the pair:
//
//   * the two render differently — nothing changes, and this owner is the identity function;
//   * they render the same AND are the same type — nothing changes either, because a diagnostic
//     about a nullability, by-ref or oblivious difference is not a diagnostic about identity, and
//     spelling both sides in full would bury the one character that differs;
//   * otherwise BOTH are re-rendered with their namespaces — both, never one, because qualifying a
//     single side reads as though only that side has a home, and a reader comparing two names has to
//     be able to compare them at the same depth.
//
// QUALIFICATION REACHES INSIDE THE SHAPE, because that is where the collision usually is:
// `List<Range>` against `List<Range>` differs in the type ARGUMENT, so the walk mirrors the
// structural renderings in `TypeInfoModels` — tuple, anonymous union, generic, array, nullable,
// oblivious, by-ref — and qualifies the LEAVES. A leaf that has no namespace to add (a built-in, a
// type parameter, an unresolved placeholder) renders exactly as it always did, so a pair that cannot
// be told apart by qualification is not made longer for nothing.
//
// WHERE A NAMESPACE COMES FROM: metadata carries its own, and a SOURCE declaration's is the
// namespace of the file that declares it — which only the declaration context knows. The context is
// therefore an argument and it is nullable: a shape built by hand has no project behind it, and then
// the source half of the question has no answer and the metadata half still does.
class TypeMismatchDisplay {

    // THE PAIR, WHICH IS THE ONLY ENTRY A DIAGNOSTIC SHOULD USE. Rendering the two sides separately
    // is what produced the contradiction this owner exists to remove.
    static func Pair(declarations: AnalyzerDeclarationContext?, actual: TypeInfo, expected: TypeInfo, out actualText: string, out expectedText: string) {
        Qualify(declarations, actual, expected, Display(actual), Display(expected), out actualText, out expectedText)
    }

    // THE SAME RULE OVER A PAIR THE CALLER HAS ALREADY RENDERED ITS OWN WAY. An argument mismatch
    // spells a delegate as `(int) -> bool` and a method group as a phrase rather than a type name;
    // those renderings are the caller's and are kept, and the rule only ever asks whether the two
    // ARE the same string. A phrase never collides with a type name, so this arm no-ops for them and
    // stays exact for the case it is for.
    static func Qualify(declarations: AnalyzerDeclarationContext?, actual: TypeInfo, expected: TypeInfo, actualDisplay: string, expectedDisplay: string, out actualText: string, out expectedText: string) {
        actualText = actualDisplay
        expectedText = expectedDisplay
        if actualText != expectedText {
            return
        }

        if TypeInfoIdentityFacts.AreEqual(actual, expected) {
            return
        }

        qualifiedActual := Qualified(declarations, actual)
        qualifiedExpected := Qualified(declarations, expected)
        if qualifiedActual == qualifiedExpected {
            return
        }

        actualText = qualifiedActual
        expectedText = qualifiedExpected
    }

    // A type's ORDINARY display form: its own `ToString`, read through an `object`-typed local
    // because `ToString` is declared by the base of the `TypeInfo` hierarchy rather than by the
    // hierarchy itself. This is the estate's standing idiom and the one every mismatch site used to
    // spell for itself.
    static func Display(candidate: TypeInfo): string {
        boxed := candidate as object
        rendered := boxed.ToString()
        if rendered == null {
            return ""
        }

        return rendered
    }

    // THE SAME RENDERING WITH EVERY LEAF SPELLED IN FULL. The structural arms reproduce
    // `TypeInfoModels`' own `ToString` shapes exactly, so the only difference between this and
    // `Display` is how much of each leaf is printed.
    static func Qualified(declarations: AnalyzerDeclarationContext?, candidate: TypeInfo): string {
        nullable := candidate as NullableTypeInfo
        if nullable != null {
            return Qualified(declarations, nullable.InnerType) + "?"
        }

        oblivious := candidate as ObliviousTypeInfo
        if oblivious != null {
            return Qualified(declarations, oblivious.InnerType) + "!"
        }

        byRef := candidate as ByRefTypeInfo
        if byRef != null {
            return "&" + Qualified(declarations, byRef.InnerType)
        }

        array := candidate as ArrayTypeInfo
        if array != null {
            return Qualified(declarations, array.ElementType) + "[]"
        }

        generic := candidate as GenericTypeInfo
        if generic != null {
            builder := new StringBuilder()
            builder.Append(QualifiedLeafName(declarations, generic, generic.Name))
            builder.Append("<")
            index := 0
            while index < generic.TypeArguments.Count {
                if index > 0 {
                    builder.Append(", ")
                }

                builder.Append(Qualified(declarations, generic.TypeArguments[index]))
                index = index + 1
            }

            builder.Append(">")
            return builder.ToString()
        }

        tuple := candidate as TupleTypeInfo
        if tuple != null {
            builder := new StringBuilder()
            builder.Append("(")
            index := 0
            while index < tuple.Elements.Count {
                if index > 0 {
                    builder.Append(", ")
                }

                element := tuple.Elements[index]
                if element.Name != null {
                    builder.Append(element.Name)
                    builder.Append(": ")
                }

                builder.Append(Qualified(declarations, element.Type))
                index = index + 1
            }

            builder.Append(")")
            return builder.ToString()
        }

        anonymousUnion := candidate as AnonymousUnionTypeInfo
        if anonymousUnion != null {
            builder := new StringBuilder()
            index := 0
            while index < anonymousUnion.Arms.Count {
                if index > 0 {
                    builder.Append(" | ")
                }

                builder.Append(Qualified(declarations, anonymousUnion.Arms[index]))
                index = index + 1
            }

            return builder.ToString()
        }

        return QualifiedLeafName(declarations, candidate, Display(candidate))
    }

    // A LEAF'S NAME WITH ITS NAMESPACE IN FRONT, or the name unchanged when it has none. A generic
    // instantiation hands in its HEAD name rather than its rendering, because the arguments are
    // qualified by the caller's own walk.
    static func QualifiedLeafName(declarations: AnalyzerDeclarationContext?, candidate: TypeInfo, writtenName: string): string {
        qualifier := QualifyingNamespace(declarations, candidate)
        if qualifier.Length == 0 {
            return writtenName
        }

        return qualifier + "." + writtenName
    }

    // WHICH NAMESPACE A TYPE LIVES IN, asked of the only two owners that can answer: metadata for a
    // reflected type, and the declaration context — through the file that declares it — for a source
    // one. Everything else (a built-in, a type parameter, an unresolved placeholder, a hand-built
    // shape with no project behind it) answers the empty string, which is this owner's "there is
    // nothing to add here".
    static func QualifyingNamespace(declarations: AnalyzerDeclarationContext?, candidate: TypeInfo): string {
        reflection := candidate as ReflectionTypeInfo
        if reflection != null {
            return reflection.Type.get_Namespace() ?? ""
        }

        if declarations == null {
            return ""
        }

        if !declarations.ContainsSourceType(candidate) {
            return ""
        }

        return declarations.GetNamespaceForFile(declarations.GetDeclarationFile(candidate)) ?? ""
    }
}
