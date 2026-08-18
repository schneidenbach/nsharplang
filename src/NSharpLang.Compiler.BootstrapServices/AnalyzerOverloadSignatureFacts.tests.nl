namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR `AnalyzerOverloadSignatureFacts`, IN N#.
//
// These replace `tests/AnalyzerOverloadSignatureFactsTests.cs`, the last canonical C# assertion
// layer over `AnalyzerOverloadSignatureFacts.nl`. The subject decides whether two declared
// overloads COLLIDE, and it decides it on SOURCE syntax rather than on resolved types — because
// overload uniqueness must be answerable before the resolver has run.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. Every input is a constructed `TypeReference`
// tree, and a dependency-assembly constructed object declines at `emit.local.initializer` from a
// `tests/native` project.
//
// WHY THE ARGUMENT LISTS ARE BUILT BY EXPLICIT-ARITY HELPERS. An array literal whose elements are
// two DIFFERENT `TypeReference` subclasses is refused by the estate's own emit at
// `emit.local.initializer`; `…Refs2(a, b)` is the spelling the rest of the estate uses and it
// emits. This is a spelling constraint, not a coverage one.
//
// THE COVERAGE IS ARM-COMPLETE, WHICH THE C# WAS NOT. The deleted file pinned THREE signature
// strings — one nested generic, one tuple, one function — and left five of the eight
// `TypeReference` arms unasserted in isolation. All eight are asserted here, alone and composed.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) THE SIGNATURE IS NOT THE DISPLAY NAME, AND THE DIFFERENCE IS DELIBERATE. `TypeReferenceFacts`
// renders `List<int?[]> | &string` for humans; this kernel renders `List<int?[]>|&string` for
// COMPARISON — no spaces anywhere, `->` for the function arrow, and `|` for the union separator.
// Two strings that differ only in whitespace would make two colliding overloads look distinct.
//
// (2) A TUPLE'S ELEMENT NAMES ARE DROPPED. `(string name, &int)` and `(string, &int)` both signal
// `(string,&int)`, because C#-style tuple element names do not participate in overload identity.
//
// (3) THE COMPARISON IS ORDERED AND ARITY-SENSITIVE, AND A MISSING SIGNATURE IS NOT A MATCH.
// `ParameterSignaturesMatch` answers false when EITHER side has no `SourceParameterTypes` at all —
// two unknowns are not equal — and it compares position by position, so `(int,string)` and
// `(string,int)` are distinct.
//
// (4) `HasDistinctParameterSignature` IS THE NEGATION OF "MATCHES ANY", NOT OF "MATCHES ALL". It
// walks the whole existing set and answers false on the FIRST match, so one collision anywhere in
// the set is enough.

func SigFactsNoRefs(): List<TypeReference> {
    return new List<TypeReference>()
}

func SigFactsRefs1(first: TypeReference): List<TypeReference> {
    items := new List<TypeReference>()
    items.Add(first)
    return items
}

func SigFactsRefs2(first: TypeReference, second: TypeReference): List<TypeReference> {
    items := new List<TypeReference>()
    items.Add(first)
    items.Add(second)
    return items
}

func SigFactsRefs3(first: TypeReference, second: TypeReference, third: TypeReference): List<TypeReference> {
    items := new List<TypeReference>()
    items.Add(first)
    items.Add(second)
    items.Add(third)
    return items
}

func SigFactsTuples1(first: TupleTypeElement): List<TupleTypeElement> {
    items := new List<TupleTypeElement>()
    items.Add(first)
    return items
}

func SigFactsTuples2(first: TupleTypeElement, second: TupleTypeElement): List<TupleTypeElement> {
    items := new List<TupleTypeElement>()
    items.Add(first)
    items.Add(second)
    return items
}

// The C#'s `private static FunctionTypeInfo FunctionWith(params TypeReference[] parameters)`,
// split into explicit arities.
func SigFactsFunctionWith1(first: TypeReference): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SourceParameterTypes = SigFactsRefs1(first)
    return signature
}

func SigFactsFunctionWith2(first: TypeReference, second: TypeReference): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SourceParameterTypes = SigFactsRefs2(first, second)
    return signature
}

func SigFactsFunctionWith0(): FunctionTypeInfo {
    signature := new FunctionTypeInfo()
    signature.SourceParameterTypes = SigFactsNoRefs()
    return signature
}

func SigFactsFunctions1(first: FunctionTypeInfo): List<FunctionTypeInfo> {
    items := new List<FunctionTypeInfo>()
    items.Add(first)
    return items
}

func SigFactsFunctions2(first: FunctionTypeInfo, second: FunctionTypeInfo): List<FunctionTypeInfo> {
    items := new List<FunctionTypeInfo>()
    items.Add(first)
    items.Add(second)
    return items
}

// ---- the signature renderer ----------------------------------------------------------------------

// Successor to AnalyzerOverloadSignatureFacts_FormatsNestedTypeReferenceSignatures — all three of
// its assertions, over the same three trees.
test "overload signature facts render nested type reference signatures" {
    nested := new GenericTypeReference(
        "Dictionary",
        SigFactsRefs2(
            new SimpleTypeReference("string"),
            new ArrayTypeReference(new NullableTypeReference(new SimpleTypeReference("int")))))

    tupled := new TupleTypeReference(
        SigFactsTuples2(
            new TupleTypeElement(new SimpleTypeReference("string"), "name"),
            new TupleTypeElement(new ByRefTypeReference(new SimpleTypeReference("int")), null)))

    signature := new FunctionTypeReference(
        SigFactsRefs2(
            new SimpleTypeReference("int"),
            new UnionTypeReference(SigFactsRefs2(new SimpleTypeReference("string"), new SimpleTypeReference("null")))),
        new SimpleTypeReference("bool"))

    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(nested) == "Dictionary<string,int?[]>"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(tupled) == "(string,&int)"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(signature) == "(int,string|null)->bool"
}

// NOT IN THE DELETED FILE. Each of the eight arms alone, so a broken arm cannot hide inside a
// composed tree that another arm happens to render correctly.
test "overload signature facts render every type reference arm alone" {
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new SimpleTypeReference("int")) == "int"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new ArrayTypeReference(new SimpleTypeReference("int"))) == "int[]"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new NullableTypeReference(new SimpleTypeReference("int"))) == "int?"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new ByRefTypeReference(new SimpleTypeReference("int"))) == "&int"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new GenericTypeReference("List", SigFactsRefs1(new SimpleTypeReference("int")))) == "List<int>"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new UnionTypeReference(SigFactsRefs2(new SimpleTypeReference("int"), new SimpleTypeReference("string")))) == "int|string"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new TupleTypeReference(SigFactsTuples2(new TupleTypeElement(new SimpleTypeReference("int"), null), new TupleTypeElement(new SimpleTypeReference("string"), null)))) == "(int,string)"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new FunctionTypeReference(SigFactsRefs1(new SimpleTypeReference("int")), new SimpleTypeReference("bool"))) == "(int)->bool"
}

// NOT IN THE DELETED FILE. The empty and single-element shapes of the three list-walking arms,
// which is where an off-by-one separator lives.
test "overload signature facts render the empty and single element shapes" {
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new GenericTypeReference("Box", SigFactsNoRefs())) == "Box<>"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new UnionTypeReference(SigFactsNoRefs())) == ""
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new TupleTypeReference(SigFactsTuples1(new TupleTypeElement(new SimpleTypeReference("int"), null)))) == "(int)"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new FunctionTypeReference(SigFactsNoRefs(), new SimpleTypeReference("void"))) == "()->void"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(new GenericTypeReference("Dictionary", SigFactsRefs3(new SimpleTypeReference("a"), new SimpleTypeReference("b"), new SimpleTypeReference("c")))) == "Dictionary<a,b,c>"
}

// NOT IN THE DELETED FILE. Element names are dropped, and this is what makes two differently-named
// tuple parameters collide as overloads.
test "overload signature facts drop tuple element names" {
    named := new TupleTypeReference(
        SigFactsTuples2(
            new TupleTypeElement(new SimpleTypeReference("string"), "first"),
            new TupleTypeElement(new SimpleTypeReference("int"), "second")))
    unnamed := new TupleTypeReference(
        SigFactsTuples2(
            new TupleTypeElement(new SimpleTypeReference("string"), null),
            new TupleTypeElement(new SimpleTypeReference("int"), null)))

    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(named) == "(string,int)"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(unnamed) == "(string,int)"
    assert AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(named) == AnalyzerOverloadSignatureFacts.GetParameterTypeSignature(unnamed)
}

// ---- the comparison ------------------------------------------------------------------------------

// Successor to AnalyzerOverloadSignatureFacts_ComparesSourceParameterSignatures — all six of its
// assertions, over the same three functions.
test "overload signature facts compare source parameter signatures" {
    first := SigFactsFunctionWith2(
        new SimpleTypeReference("int"),
        new GenericTypeReference("List", SigFactsRefs1(new ArrayTypeReference(new SimpleTypeReference("string")))))
    same := SigFactsFunctionWith2(
        new SimpleTypeReference("int"),
        new GenericTypeReference("List", SigFactsRefs1(new ArrayTypeReference(new SimpleTypeReference("string")))))
    different := SigFactsFunctionWith2(
        new SimpleTypeReference("int"),
        new GenericTypeReference("List", SigFactsRefs1(new ArrayTypeReference(new SimpleTypeReference("bool")))))

    assert AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(first)
    assert !AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(new FunctionTypeInfo())
    assert AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(first, same)
    assert !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(first, different)
    assert !AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(same, SigFactsFunctions1(first))
    assert AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(different, SigFactsFunctions1(first))
}

// NOT IN THE DELETED FILE. An absent signature is not a match — not even against another absent
// one — and an EMPTY signature is a real signature that matches itself.
test "overload signature facts refuse to match an absent signature" {
    unknown := new FunctionTypeInfo()
    known := SigFactsFunctionWith1(new SimpleTypeReference("int"))
    empty := SigFactsFunctionWith0()

    assert !AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(unknown)
    assert AnalyzerOverloadSignatureFacts.HasSourceParameterSignature(empty)

    assert !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(unknown, known)
    assert !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(known, unknown)
    assert !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(unknown, unknown)
    assert AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(empty, SigFactsFunctionWith0())
    assert !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(empty, known)
}

// NOT IN THE DELETED FILE. Arity and ORDER are both part of identity.
test "overload signature facts compare by arity and by position" {
    one := SigFactsFunctionWith1(new SimpleTypeReference("int"))
    two := SigFactsFunctionWith2(new SimpleTypeReference("int"), new SimpleTypeReference("string"))
    swapped := SigFactsFunctionWith2(new SimpleTypeReference("string"), new SimpleTypeReference("int"))

    assert !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(one, two)
    assert !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(two, one)
    assert !AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(two, swapped)
    assert AnalyzerOverloadSignatureFacts.ParameterSignaturesMatch(two, SigFactsFunctionWith2(new SimpleTypeReference("int"), new SimpleTypeReference("string")))
}

// NOT IN THE DELETED FILE. The set walk answers on the FIRST collision and admits only a candidate
// that collides with nothing — including against the empty set.
test "overload signature facts answer distinctness against the whole existing set" {
    intOnly := SigFactsFunctionWith1(new SimpleTypeReference("int"))
    stringOnly := SigFactsFunctionWith1(new SimpleTypeReference("string"))
    boolOnly := SigFactsFunctionWith1(new SimpleTypeReference("bool"))
    existing := SigFactsFunctions2(intOnly, stringOnly)

    assert AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(boolOnly, existing)
    assert !AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(SigFactsFunctionWith1(new SimpleTypeReference("int")), existing)
    assert !AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(SigFactsFunctionWith1(new SimpleTypeReference("string")), existing)
    assert AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(intOnly, new List<FunctionTypeInfo>())

    // An unknown signature collides with nothing, because "no signature" never matches.
    assert AnalyzerOverloadSignatureFacts.HasDistinctParameterSignature(new FunctionTypeInfo(), existing)
}
