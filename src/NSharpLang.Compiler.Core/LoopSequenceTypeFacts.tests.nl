namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `LoopSequenceTypeFacts`, IN N#.
//
// The subject answers what a `for x in xs` loop BINDS: given the sequence's type, what is `x`?
//
// THE NAME TABLE THESE CONTRACTS USED TO PIN IS GONE, AND ITS ABSENCE IS THE POINT. The old owner
// answered eighteen unqualified spellings — `List`, `HashSet`, `Queue`, `Span`, five dictionary
// names and the rest — which meant a `Stack<int>` iterated and a `JsonElement.ArrayEnumerator`, a
// `Dictionary<K, V>.KeyCollection`, a `StringBuilder.ChunkEnumerator` and every user type carrying
// the enumerator pattern did not. The rule is now the C# one, it is structural, and these rows
// assert it on types the table never named — which is the only way to see that no table is left.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) THE PATTERN OUTRANKS THE INTERFACE. `List<T>` implements `IEnumerable<T>` AND carries a struct
// `GetEnumerator`; C# binds the struct one, and so does this. The element type agrees either way,
// which is exactly why the ORDER has to be pinned by a type where it would not.
//
// (2) A DICTIONARY DOES NOT ENUMERATE ITS VALUES. `Dictionary<K, V>` answers `KeyValuePair<K, V>`,
// and it answers it because that is what its enumerator's `Current` IS — not because five
// dictionary-shaped names were listed somewhere.
//
// (3) SYNC AND ASYNC ARE SEPARATE DOORS, NOT A FILTER. `requireAsync: true` answers ONLY
// `IAsyncEnumerable<T>`, and `requireAsync: false` never answers for it.
//
// (4) AN OPEN DEFINITION ANSWERS IN ITS OWN PARAMETERS. `List<>` answers the parameter `T` rather
// than a closed type, because the caller rewrites that by POSITION with the arguments the
// instantiation supplied — which is how `Dictionary<string, Widget>` produces a pair over a source
// `Widget` the CLR has no handle for.
func LoopFactsTypeName(value: Type?): string {
    if value == null {
        return "<null>"
    }

    return value.Name
}

func LoopFactsSequenceElementName(collection: Type, requireAsync: bool): string {
    return LoopFactsTypeName(LoopSequenceTypeFacts.SequenceElementType(collection, requireAsync))
}

// A nested type cannot be spelled in a `typeof`, so it is reached through its owner. A nested type
// of a CLOSED generic owner comes back OPEN, and it is closed again over the owner's own arguments —
// `Dictionary<string, int>.KeyCollection` is what a `for key in map.Keys` iterates.
func LoopFactsNested(owner: Type, name: string): Type {
    nested := owner.GetNestedType(name)
    if nested == null {
        throw new InvalidOperationException("The loop sequence contracts require a nested type named " + name + " on " + owner.Name + ".")
    }

    if nested.get_IsGenericTypeDefinition() {
        return nested.MakeGenericType(owner.GetGenericArguments())
    }

    return nested
}

func LoopFactsNonGenericSequenceType(): Type {
    sequence := Type.GetType("System.Collections.IEnumerable")
    if sequence == null {
        throw new InvalidOperationException("The loop sequence contracts require System.Collections.IEnumerable.")
    }

    return sequence
}

// ---- the synchronous door -------------------------------------------------------------------------

test "loop sequence facts answer the element type through the enumerator pattern" {
    assert LoopFactsSequenceElementName(typeof(List<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(HashSet<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(Stack<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(Queue<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(LinkedList<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(SortedSet<string>), false) == "String"
}

test "loop sequence facts answer the element type through the sequence interface" {
    assert LoopFactsSequenceElementName(typeof(IEnumerable<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(IList<string>), false) == "String"
    assert LoopFactsSequenceElementName(typeof(IReadOnlyList<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(IReadOnlyCollection<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(ISet<int>), false) == "Int32"
}

// The shapes the deleted name table could not reach. Each is an ordinary BCL type carrying the
// ordinary pattern, and each was rejected as "not enumerable" until the table went away.
test "loop sequence facts answer shapes no name table listed" {
    assert LoopFactsSequenceElementName(LoopFactsNested(typeof(System.Text.Json.JsonElement), "ArrayEnumerator"), false) == "JsonElement"
    assert LoopFactsSequenceElementName(LoopFactsNested(typeof(System.Text.Json.JsonElement), "ObjectEnumerator"), false) == "JsonProperty"
    assert LoopFactsSequenceElementName(typeof(System.Collections.BitArray), false) == "Object"
    assert LoopFactsSequenceElementName(LoopFactsNested(typeof(System.Text.StringBuilder), "ChunkEnumerator"), false) == "ReadOnlyMemory`1"
}

// A `Span<T>` enumerator's `Current` is a `ref T`, and the loop variable is a COPY of the element:
// the by-ref spelling is the enumerator's way of avoiding a second copy, not part of the type.
test "loop sequence facts strip the by-ref spelling off a span element" {
    assert LoopFactsSequenceElementName(typeof(Span<int>), false) == "Int32"
    assert LoopFactsSequenceElementName(typeof(ReadOnlySpan<char>), false) == "Char"
}

test "loop sequence facts answer a dictionary with its pair, not its value" {
    assert LoopFactsSequenceElementName(typeof(Dictionary<string, int>), false) == "KeyValuePair`2"
    assert LoopFactsSequenceElementName(typeof(SortedDictionary<string, int>), false) == "KeyValuePair`2"
    assert LoopFactsSequenceElementName(typeof(IReadOnlyDictionary<string, int>), false) == "KeyValuePair`2"

    pair := LoopSequenceTypeFacts.SequenceElementType(typeof(Dictionary<string, int>), false)
    assert pair != null
    pairArguments := pair.GetGenericArguments()
    assert pairArguments.Length == 2
    assert pairArguments[0].Name == "String"
    assert pairArguments[1].Name == "Int32"
}

// The key and value COLLECTIONS of a dictionary are their own sequences, and neither was reachable
// by name.
test "loop sequence facts answer a dictionary key and value collection" {
    assert LoopFactsSequenceElementName(LoopFactsNested(typeof(Dictionary<string, int>), "KeyCollection"), false) == "String"
    assert LoopFactsSequenceElementName(LoopFactsNested(typeof(Dictionary<string, int>), "ValueCollection"), false) == "Int32"
}

// The non-generic remainder: a type that names only `IEnumerable` iterates as `object`.
test "loop sequence facts answer the non-generic sequence as object" {
    assert LoopFactsSequenceElementName(LoopFactsNonGenericSequenceType(), false) == "Object"
}

// ---- what does NOT iterate ------------------------------------------------------------------------

test "loop sequence facts refuse what is not a sequence" {
    assert LoopSequenceTypeFacts.SequenceElementType(typeof(int), false) == null
    assert LoopSequenceTypeFacts.SequenceElementType(typeof(IEnumerator<int>), false) == null
    assert LoopSequenceTypeFacts.SequenceElementType(typeof(System.Threading.Tasks.Task<int>), false) == null
}

// AN ARRAY AND A `string` ARE NOT DECIDED HERE, and the reason is not that this owner refuses them:
// `System.Array` carries a non-generic `GetEnumerator` and `string` carries a `CharEnumerator`, so
// both DO answer the pattern. They answer the WRONG THING for a loop — `object` rather than the
// array's element type, and a heap-allocated enumerator rather than an index — which is why the
// walks that type a `foreach` answer them in their own arms BEFORE asking this one.
test "an array and a string answer the pattern, which is why their callers answer them first" {
    assert LoopFactsSequenceElementName(typeof(int[]), false) == "Object"
    assert LoopFactsSequenceElementName(typeof(string), false) == "Char"
}

// ---- the asynchronous door ------------------------------------------------------------------------

test "loop sequence facts keep the async door separate from the sync one" {
    assert LoopFactsSequenceElementName(typeof(IAsyncEnumerable<string>), true) == "String"
    assert LoopSequenceTypeFacts.SequenceElementType(typeof(IAsyncEnumerable<string>), false) == null
    assert LoopSequenceTypeFacts.SequenceElementType(typeof(List<int>), true) == null
    assert LoopSequenceTypeFacts.SequenceElementType(typeof(Span<int>), true) == null
    assert LoopSequenceTypeFacts.SequenceElementType(typeof(Dictionary<string, int>), true) == null
}

// ---- the open definition --------------------------------------------------------------------------

test "loop sequence facts answer an open definition in its own parameters" {
    listElement := LoopSequenceTypeFacts.SequenceElementType(typeof(List<int>).GetGenericTypeDefinition(), false)
    assert listElement != null
    assert listElement.get_IsGenericParameter()
    assert listElement.get_GenericParameterPosition() == 0

    dictionaryElement := LoopSequenceTypeFacts.SequenceElementType(typeof(Dictionary<string, int>).GetGenericTypeDefinition(), false)
    assert dictionaryElement != null
    assert dictionaryElement.Name == "KeyValuePair`2"
    dictionaryArguments := dictionaryElement.GetGenericArguments()
    assert dictionaryArguments.Length == 2
    assert dictionaryArguments[0].get_IsGenericParameter()
    assert dictionaryArguments[0].get_GenericParameterPosition() == 0
    assert dictionaryArguments[1].get_IsGenericParameter()
    assert dictionaryArguments[1].get_GenericParameterPosition() == 1

    spanElement := LoopSequenceTypeFacts.SequenceElementType(typeof(Span<int>).GetGenericTypeDefinition(), false)
    assert spanElement != null
    assert spanElement.get_IsGenericParameter()
    assert spanElement.get_GenericParameterPosition() == 0
}

test "loop sequence facts answer a single type argument only for a one-argument construction" {
    assert LoopFactsTypeName(LoopSequenceTypeFacts.SingleTypeArgument(typeof(IEnumerable<int>))) == "Int32"
    assert LoopSequenceTypeFacts.SingleTypeArgument(typeof(Dictionary<string, int>)) == null
}
