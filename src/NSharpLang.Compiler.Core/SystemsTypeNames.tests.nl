namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Native contracts for THE TWO NAMES SYSTEMS POLICY DECIDES AGAINST.
//
// Both members were `private static` in `SystemsAnalyzer.cs` and reached from twenty call sites in
// nine different rules, so their behaviour was pinned only indirectly — through whichever rule
// happened to have an end-to-end fixture. This is their first DIRECT pinning, written around the
// four things they are easy to get wrong.
//
// (1) THE ERASED NAME IS NOT THE DISPLAY NAME. `List<int>` must erase to `List`. Substituting
// `TypeReferenceFacts.GetDisplayName` for the whole walk — the obvious "de-duplication" — would
// hand every generic classification the rendered form and silently stop matching every table.
//
// (2) DECORATION SURVIVES ERASURE. `int[]`, `int?` and `&int` keep their marks, because the
// allocation rule reads the `[]` and the ref-like rule reads the `&`. Erasing those too would make
// `new int[4]` look like a value-typed construction.
//
// (3) THE FALLBACK IS THE DISPLAY NAME AND THAT IS EXACT, NOT APPROXIMATE. Tuple, function and
// union references have no constructor name; their C# original fell through to `ToString()`, and
// those three overrides are written in terms of `TypeReferenceFacts`, so the display name is the
// same string by construction. These contracts pin the strings themselves so a future edit to
// either side cannot drift them apart unnoticed.
//
// (4) SIMPLE NAME IS THE LAST SEGMENT, NOT A NAMESPACE STRIP. `A.B.C` is `C`; a trailing dot yields
// the empty string rather than the whole name; and nothing is trimmed, lowered or unquoted.
func StnSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func StnGeneric(name: string, argument: TypeReference): GenericTypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(argument)
    return new GenericTypeReference(name, arguments, 1, 1)
}

func StnGeneric2(name: string, first: TypeReference, second: TypeReference): GenericTypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(first)
    arguments.Add(second)
    return new GenericTypeReference(name, arguments, 1, 1)
}

// ── the last dotted segment ───────────────────────────────────────────────────

test "THE SIMPLE NAME IS THE LAST DOTTED SEGMENT, AND AN UNDOTTED NAME IS ITSELF" {
    assert SystemsTypeNames.SimpleName("int") == "int"
    assert SystemsTypeNames.SimpleName("System.Buffers.ArrayPool") == "ArrayPool"
    assert SystemsTypeNames.SimpleName("A.B") == "B"
}

test "THE SIMPLE NAME TAKES THE LAST DOT, NOT THE FIRST, AND KEEPS EVERYTHING AFTER IT" {
    assert SystemsTypeNames.SimpleName("A.B.C<D.E>") == "E>"
    assert SystemsTypeNames.SimpleName("System.Int32[]") == "Int32[]"
}

test "A TRAILING DOT YIELDS THE EMPTY STRING, AND THE EMPTY STRING YIELDS ITSELF" {
    assert SystemsTypeNames.SimpleName("System.") == ""
    assert SystemsTypeNames.SimpleName("") == ""
    assert SystemsTypeNames.SimpleName(".") == ""
}

test "THE SIMPLE NAME NEVER TRIMS, LOWERS OR UNQUOTES — A CASE DIFFERENCE IS A DIFFERENT TYPE" {
    assert SystemsTypeNames.SimpleName("Int") == "Int"
    assert SystemsTypeNames.SimpleName(" int ") == " int "
}

// ── erasure: the one arm that separates this owner from the display name ─────

test "A GENERIC ERASES TO ITS CONSTRUCTOR NAME, WHICH IS WHAT EVERY SYSTEMS TABLE IS KEYED BY" {
    listOfInt := StnGeneric("List", StnSimple("int"))

    assert SystemsTypeNames.ErasedName(listOfInt) == "List"
    // The display name renders the arguments; the erased name is deliberately NOT that string.
    assert TypeReferenceFacts.GetDisplayName(listOfInt) == "List<int>"
    assert SystemsTypeNames.ErasedName(listOfInt) != TypeReferenceFacts.GetDisplayName(listOfInt)
}

test "ERASURE IS ONE LEVEL DEEP AND IGNORES THE ARGUMENTS ENTIRELY" {
    nested := StnGeneric("Result", StnGeneric("List", StnSimple("string")))

    assert SystemsTypeNames.ErasedName(nested) == "Result"
}

test "A SIMPLE NAME IS ITS OWN ERASURE, DOTS AND ALL" {
    assert SystemsTypeNames.ErasedName(StnSimple("int")) == "int"
    assert SystemsTypeNames.ErasedName(StnSimple("System.IO.FileStream")) == "System.IO.FileStream"
}

// ── decoration survives erasure ──────────────────────────────────────────────

test "AN ARRAY KEEPS ITS BRACKETS AND ERASES ITS ELEMENT" {
    assert SystemsTypeNames.ErasedName(new ArrayTypeReference(StnSimple("int"))) == "int[]"
    assert SystemsTypeNames.ErasedName(new ArrayTypeReference(StnGeneric("List", StnSimple("int")))) == "List[]"
}

test "A NULLABLE KEEPS ITS QUESTION MARK AND A BY-REF KEEPS ITS AMPERSAND" {
    assert SystemsTypeNames.ErasedName(new NullableTypeReference(StnSimple("int"))) == "int?"
    assert SystemsTypeNames.ErasedName(new ByRefTypeReference(StnSimple("int"))) == "&int"
}

test "DECORATION NESTS IN THE ORDER IT IS WRITTEN" {
    arrayOfNullable := new ArrayTypeReference(new NullableTypeReference(StnSimple("int")))
    byRefArray := new ByRefTypeReference(new ArrayTypeReference(StnSimple("byte")))

    assert SystemsTypeNames.ErasedName(arrayOfNullable) == "int?[]"
    assert SystemsTypeNames.ErasedName(byRefArray) == "&byte[]"
}

test "DECORATION AROUND A GENERIC ERASES THE GENERIC AND KEEPS THE MARK" {
    assert SystemsTypeNames.ErasedName(new ByRefTypeReference(StnGeneric("Span", StnSimple("byte")))) == "&Span"
    assert SystemsTypeNames.ErasedName(new NullableTypeReference(StnGeneric2("Result", StnSimple("int"), StnSimple("string")))) == "Result?"
}

// ── the three shapes with no constructor name ────────────────────────────────

test "A UNION HAS NO CONSTRUCTOR NAME, SO ITS ERASURE IS ITS RENDERING — EXACTLY" {
    arms := new List<TypeReference>()
    arms.Add(StnSimple("int"))
    arms.Add(StnSimple("string"))
    unionReference := new UnionTypeReference(arms)

    assert SystemsTypeNames.ErasedName(unionReference) == "int | string"
    assert SystemsTypeNames.ErasedName(unionReference) == TypeReferenceFacts.GetDisplayName(unionReference)
}

test "A TUPLE'S ERASURE IS ITS RENDERING, NAMED ELEMENTS AND ALL" {
    elements := new List<TupleTypeElement>()
    elements.Add(new TupleTypeElement(StnSimple("int"), null))
    elements.Add(new TupleTypeElement(StnSimple("string"), "label"))
    tuple := new TupleTypeReference(elements)

    assert SystemsTypeNames.ErasedName(tuple) == "(int, label: string)"
    assert SystemsTypeNames.ErasedName(tuple) == TypeReferenceFacts.GetDisplayName(tuple)
}

test "A FUNCTION TYPE'S ERASURE IS ITS RENDERING, ARROW AND ALL" {
    parameters := new List<TypeReference>()
    parameters.Add(StnSimple("int"))
    functionReference := new FunctionTypeReference(parameters, StnSimple("bool"))

    assert SystemsTypeNames.ErasedName(functionReference) == "(int) -> bool"
    assert SystemsTypeNames.ErasedName(functionReference) == TypeReferenceFacts.GetDisplayName(functionReference)
}

// ── the composition the rules actually perform ───────────────────────────────

test "SIMPLE-OF-ERASED IS WHAT EVERY CLASSIFICATION ASKS, AND IT IS IMPORT-INSENSITIVE" {
    qualified := StnGeneric("System.Collections.Generic.List", StnSimple("int"))
    bare := StnGeneric("List", StnSimple("int"))

    assert SystemsTypeNames.SimpleName(SystemsTypeNames.ErasedName(qualified)) == "List"
    assert SystemsTypeNames.SimpleName(SystemsTypeNames.ErasedName(bare)) == "List"
}
