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
// works on the pair's LEAVES — the named types the two renderings are built from — and asks, of each
// leaf, whether its printed name also stands for a DIFFERENT type somewhere in the pair:
//
//   * no leaf does — nothing changes, and this owner is the identity function. That includes a pair
//     that is the same type, and a pair that differs only in nullability, by-ref-ness or
//     obliviousness: a diagnostic about one `?` is not a diagnostic about identity, and spelling both
//     sides in full would bury the one character that differs;
//   * a leaf does — that leaf, on BOTH sides, is spelled with its namespace. Both, never one, because
//     qualifying a single side reads as though only that side has a home, and a reader comparing two
//     names has to be able to compare them at the same depth. The other leaves keep their simple
//     names: `List` beside `AmbiguityLeft.Marker` has nothing to disambiguate;
//   * the namespace does not tell them apart either — the leaf is spelled with WHERE IT WAS DECLARED,
//     `Entry [Entries.nl:25]`, the bracketed site C# prints for two same-named types from different
//     assemblies. For two source types that is only possible when one namespace declares one name in
//     two files (NL339), so the two sites the reader sees are exactly the two declarations to
//     reconcile; for two metadata types it is the assembly each came from.
//
// THE QUESTION IS ASKED PER LEAF, NOT OF THE WHOLE STRING. `Entry` against `Entry?` already reads
// differently, yet when the two `Entry`s are different types the difference the reader sees — the
// `?` — is not the one that failed. A caller that rendered either side its own way (a delegate as
// `(int) -> bool`, a method group as a phrase) keeps that rendering whenever the two already differ.
//
// QUALIFICATION REACHES INSIDE THE SHAPE, because that is where the collision usually is:
// `List<Range>` against `List<Range>` differs in the type ARGUMENT, so the walk mirrors the
// structural renderings in `TypeInfoModels` — tuple, anonymous union, generic, array, nullable,
// oblivious, by-ref — and qualifies the LEAVES. A leaf that has no namespace or site to add (a
// built-in, a type parameter, an unresolved placeholder) renders exactly as it always did, so a pair
// that cannot be told apart this way is not made longer for nothing.
//
// WHERE A NAMESPACE COMES FROM: metadata carries its own, and a SOURCE declaration's is the
// namespace of the file that declares it — which only the declaration context knows. The context is
// therefore an argument and it is nullable: a shape built by hand has no project behind it, and then
// the source half of the question has no answer and the metadata half still does.
enum TypeMismatchLeafDepth {
    Simple,
    Namespace,
    Site
}

class TypeMismatchDisplay {

    // THE PAIR, WHICH IS THE ONLY ENTRY A DIAGNOSTIC SHOULD USE. Rendering the two sides separately
    // is what produced the contradiction this owner exists to remove.
    static func Pair(declarations: AnalyzerDeclarationContext?, actual: TypeInfo, expected: TypeInfo, out actualText: string, out expectedText: string) {
        Qualify(declarations, actual, expected, Display(actual), Display(expected), out actualText, out expectedText)
    }

    // THE SAME RULE OVER A PAIR THE CALLER HAS ALREADY RENDERED ITS OWN WAY. An argument mismatch
    // spells a delegate as `(int) -> bool` and a method group as a phrase rather than a type name;
    // those renderings are the caller's and are kept whenever the two already read differently.
    static func Qualify(declarations: AnalyzerDeclarationContext?, actual: TypeInfo, expected: TypeInfo, actualDisplay: string, expectedDisplay: string, out actualText: string, out expectedText: string) {
        actualText = actualDisplay
        expectedText = expectedDisplay
        if TypeInfoIdentityFacts.AreEqual(actual, expected) {
            return
        }

        if actualText != expectedText && (actualText != Display(actual) || expectedText != Display(expected)) {
            return
        }

        leafTypes := new List<TypeInfo>()
        leafNames := new List<string>()
        CollectLeaves(actual, leafTypes, leafNames)
        CollectLeaves(expected, leafTypes, leafNames)
        if !AnyLeafCollides(declarations, leafTypes, leafNames) {
            return
        }

        actualText = Rendered(declarations, actual, leafTypes, leafNames)
        expectedText = Rendered(declarations, expected, leafTypes, leafNames)
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

    // THE LEAVES OF A SHAPE, in the order `Rendered` visits them: each named type the rendering is
    // built from, beside the name it is printed under. A generic contributes its HEAD — printed under
    // the name the file wrote — and then its arguments.
    static func CollectLeaves(candidate: TypeInfo, leafTypes: List<TypeInfo>, leafNames: List<string>) {
        nullable := candidate as NullableTypeInfo
        if nullable != null {
            CollectLeaves(nullable.InnerType, leafTypes, leafNames)
            return
        }

        oblivious := candidate as ObliviousTypeInfo
        if oblivious != null {
            CollectLeaves(oblivious.InnerType, leafTypes, leafNames)
            return
        }

        byRef := candidate as ByRefTypeInfo
        if byRef != null {
            CollectLeaves(byRef.InnerType, leafTypes, leafNames)
            return
        }

        array := candidate as ArrayTypeInfo
        if array != null {
            CollectLeaves(array.ElementType, leafTypes, leafNames)
            return
        }

        generic := candidate as GenericTypeInfo
        if generic != null {
            leafTypes.Add(generic)
            leafNames.Add(generic.Name)
            for argument in generic.TypeArguments {
                CollectLeaves(argument, leafTypes, leafNames)
            }

            return
        }

        tuple := candidate as TupleTypeInfo
        if tuple != null {
            for element in tuple.Elements {
                CollectLeaves(element.Type, leafTypes, leafNames)
            }

            return
        }

        anonymousUnion := candidate as AnonymousUnionTypeInfo
        if anonymousUnion != null {
            for arm in anonymousUnion.Arms {
                CollectLeaves(arm, leafTypes, leafNames)
            }

            return
        }

        leafTypes.Add(candidate)
        leafNames.Add(Display(candidate))
    }

    static func AnyLeafCollides(declarations: AnalyzerDeclarationContext?, leafTypes: List<TypeInfo>, leafNames: List<string>): bool {
        index := 0
        while index < leafTypes.Count {
            if LeafDepth(declarations, leafTypes[index], leafNames[index], leafTypes, leafNames) != TypeMismatchLeafDepth.Simple {
                return true
            }

            index = index + 1
        }

        return false
    }

    // HOW MUCH OF ONE LEAF THE PAIR HAS TO PRINT: the least depth at which no OTHER type among the
    // pair's leaves reads the same. Two leaves collide only when they are different types AND their
    // fullest renderings differ — two that print the same even with their declaration sites are two
    // that no rendering can separate (two type parameters called `T`), and that is not a collision
    // this owner can answer.
    static func LeafDepth(declarations: AnalyzerDeclarationContext?, leafType: TypeInfo, leafName: string, leafTypes: List<TypeInfo>, leafNames: List<string>): TypeMismatchLeafDepth {
        identity := LeafText(declarations, leafType, leafName, TypeMismatchLeafDepth.Site)
        simple := LeafText(declarations, leafType, leafName, TypeMismatchLeafDepth.Simple)
        qualified := LeafText(declarations, leafType, leafName, TypeMismatchLeafDepth.Namespace)
        depth := TypeMismatchLeafDepth.Simple
        index := 0
        while index < leafTypes.Count {
            other := leafTypes[index]
            otherName := leafNames[index]
            if !TypeInfoIdentityFacts.AreEqual(leafType, other) && LeafText(declarations, other, otherName, TypeMismatchLeafDepth.Site) != identity {
                if LeafText(declarations, other, otherName, TypeMismatchLeafDepth.Namespace) == qualified {
                    return TypeMismatchLeafDepth.Site
                }

                if LeafText(declarations, other, otherName, TypeMismatchLeafDepth.Simple) == simple {
                    depth = TypeMismatchLeafDepth.Namespace
                }
            }

            index = index + 1
        }

        return depth
    }

    // ONE LEAF AT ONE DEPTH. The site depth drops the namespace for a SOURCE type — the file already
    // says where it lives, and the two it is told apart from share their namespace — and keeps it for
    // a METADATA type, where the bracket names an assembly rather than a place in this project.
    static func LeafText(declarations: AnalyzerDeclarationContext?, leafType: TypeInfo, leafName: string, depth: TypeMismatchLeafDepth): string {
        if depth == TypeMismatchLeafDepth.Simple {
            return leafName
        }

        qualified := QualifiedLeafName(declarations, leafType, leafName)
        if depth == TypeMismatchLeafDepth.Namespace {
            return qualified
        }

        reflection := leafType as ReflectionTypeInfo
        if reflection != null {
            return qualified + AssemblySuffix(reflection)
        }

        if declarations == null || !declarations.ContainsSourceType(leafType) {
            return qualified
        }

        site := declarations.DescribeDeclarationSite(leafType)
        if site.Length == 0 {
            return qualified
        }

        return leafName + " [" + site + "]"
    }

    // ` [AssemblyName]`, or nothing when the metadata cannot name it: a diagnostic's rendering is never
    // allowed to be the thing that fails.
    static func AssemblySuffix(reflection: ReflectionTypeInfo): string {
        try {
            assemblyName := reflection.Type.Assembly.GetName().Name ?? ""
            if assemblyName.Length > 0 {
                return " [" + assemblyName + "]"
            }
        } catch {
        }

        return ""
    }

    // THE SAME RENDERING AS `Display`, WITH EACH LEAF PRINTED AT ITS OWN DEPTH. The structural arms
    // reproduce `TypeInfoModels`' own `ToString` shapes exactly, so the only difference between this
    // and `Display` is how much of each leaf is printed.
    static func Rendered(declarations: AnalyzerDeclarationContext?, candidate: TypeInfo, leafTypes: List<TypeInfo>, leafNames: List<string>): string {
        nullable := candidate as NullableTypeInfo
        if nullable != null {
            return Rendered(declarations, nullable.InnerType, leafTypes, leafNames) + "?"
        }

        oblivious := candidate as ObliviousTypeInfo
        if oblivious != null {
            return Rendered(declarations, oblivious.InnerType, leafTypes, leafNames) + "!"
        }

        byRef := candidate as ByRefTypeInfo
        if byRef != null {
            return "&" + Rendered(declarations, byRef.InnerType, leafTypes, leafNames)
        }

        array := candidate as ArrayTypeInfo
        if array != null {
            return Rendered(declarations, array.ElementType, leafTypes, leafNames) + "[]"
        }

        generic := candidate as GenericTypeInfo
        if generic != null {
            builder := new StringBuilder()
            builder.Append(RenderedLeaf(declarations, generic, generic.Name, leafTypes, leafNames))
            builder.Append("<")
            index := 0
            while index < generic.TypeArguments.Count {
                if index > 0 {
                    builder.Append(", ")
                }

                builder.Append(Rendered(declarations, generic.TypeArguments[index], leafTypes, leafNames))
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

                builder.Append(Rendered(declarations, element.Type, leafTypes, leafNames))
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

                builder.Append(Rendered(declarations, anonymousUnion.Arms[index], leafTypes, leafNames))
                index = index + 1
            }

            return builder.ToString()
        }

        return RenderedLeaf(declarations, candidate, Display(candidate), leafTypes, leafNames)
    }

    static func RenderedLeaf(declarations: AnalyzerDeclarationContext?, leafType: TypeInfo, leafName: string, leafTypes: List<TypeInfo>, leafNames: List<string>): string {
        return LeafText(declarations, leafType, leafName, LeafDepth(declarations, leafType, leafName, leafTypes, leafNames))
    }

    // A LEAF'S NAME WITH ITS NAMESPACE IN FRONT, or the name unchanged when it has none.
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
            return reflection.Type.Namespace ?? ""
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
