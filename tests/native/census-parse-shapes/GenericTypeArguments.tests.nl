namespace NSharpLang.CensusParseShapes.Tests

import System
import System.Collections.Generic
import System.Threading.Tasks


// AN EXPLICIT TYPE ARGUMENT IS A WHOLE TYPE.
//
// `Name<...>(` is decided by a bounded, pure token scan, and that scan used to admit far less than the
// type grammar: it had no depth counting at all, so the FIRST `>` it met ended the list. The moment a
// type argument contained a nested generic followed by anything other than `(` -- which is exactly
// what a nullable one looks like, `List<int>?` -- the scan answered "comparison" and the call became a
// parse error. In the converted LanguageServer that ONE shape produced roughly 270 of ~340
// diagnostics: `Unexpected token '?' in expression`, then NL411 "Method 'FromResult' must be called",
// NL301 "Variable 'List' not found", NL305, and every null-narrowing after it in the file.
//
// The rows below are the type grammar, executed. Each calls a REFERENCED assembly's generic method
// with the type argument written out, and asserts both the runtime value and the CLR type the
// instantiation actually produced -- because the two halves of a nullable annotation are different
// facts: a nullable REFERENCE type is an annotation the CLR does not have (`Task<List<int>?>` IS
// `Task<List<int>>`), while a nullable VALUE type is a real construction (`Task<int?>` IS
// `Task<Nullable<int>>`).
func NullableReferenceTypeArgument(): Task<List<int>?> {
    return Task.FromResult<List<int>?>(null)
}

func NullableReferenceTypeArgumentWithValue(): Task<List<int>?> {
    return Task.FromResult<List<int>?>(new List<int>())
}

func NullableValueTypeArgument(): Task<int?> {
    return Task.FromResult<int?>(null)
}

func NestedGenericTypeArgument(): Task<Dictionary<string, List<int>>?> {
    return Task.FromResult<Dictionary<string, List<int>>?>(null)
}

func ArrayTypeArgument(): Task<int[]?> {
    return Task.FromResult<int[]?>(null)
}

func NullableArrayElementTypeArgument(): Task<string?[]?> {
    return Task.FromResult<string?[]?>(null)
}

func QualifiedTypeArgument(): Task<System.Text.StringBuilder?> {
    return Task.FromResult<System.Text.StringBuilder?>(null)
}

func TupleTypeArgument(): Task<(int, string)> {
    return Task.FromResult<(int, string)>((1, "a"))
}

func NamedTupleTypeArgument(): Task<(Item: int, Label: string)> {
    return Task.FromResult<(Item: int, Label: string)>((2, "b"))
}

func NullableTupleTypeArgument(): Task<(int, string)?> {
    return Task.FromResult<(int, string)?>(null)
}

test "a nullable REFERENCE type argument constructs the unannotated CLR type" {
    task := NullableReferenceTypeArgument()
    assert task.Result == null

    // The annotation is not a CLR type: `Task<List<int>?>` and `Task<List<int>>` are one type.
    assert task.GetType() == typeof(Task<List<int>>)

    withValue := NullableReferenceTypeArgumentWithValue()
    rows := withValue.Result
    assert rows != null
    if rows != null {
        assert rows.Count == 0
    }

    assert withValue.GetType() == typeof(Task<List<int>>)
}

test "a nullable VALUE type argument constructs Nullable<T>, which IS a CLR type" {
    task := NullableValueTypeArgument()
    assert !task.Result.HasValue
    assert task.GetType() == typeof(Task<Nullable<int>>)
}

test "a nested generic, an array and a qualified name are all whole type arguments" {
    nested := NestedGenericTypeArgument()
    assert nested.Result == null
    assert nested.GetType() == typeof(Task<Dictionary<string, List<int>>>)

    array := ArrayTypeArgument()
    assert array.Result == null
    assert array.GetType() == typeof(Task<int[]>)

    nullableElements := NullableArrayElementTypeArgument()
    assert nullableElements.Result == null
    assert nullableElements.GetType() == typeof(Task<string[]>)

    qualified := QualifiedTypeArgument()
    assert qualified.Result == null
    assert qualified.GetType() == typeof(Task<System.Text.StringBuilder>)
}

test "a tuple is a type argument, named or not, and a tuple IS its ValueTuple" {
    positional := TupleTypeArgument()
    assert positional.Result.Item1 == 1
    assert positional.Result.Item2 == "a"
    assert positional.GetType() == typeof(Task<ValueTuple<int, string>>)

    // The names are metadata on the DECLARING position, so the constructed task is the same type.
    named := NamedTupleTypeArgument()
    assert named.Result.Item1 == 2
    assert named.Result.Item2 == "b"
    assert named.GetType() == typeof(Task<ValueTuple<int, string>>)

    nullableTuple := NullableTupleTypeArgument()
    assert !nullableTuple.Result.HasValue
    assert nullableTuple.GetType() == typeof(Task<Nullable<ValueTuple<int, string>>>)
}

// THE COMPARISONS THE SAME SCAN MUST STILL READ AS COMPARISONS.
//
// Widening the scan is only correct if the shapes it must NOT claim keep their meaning. These execute
// the ones that sit closest to the boundary: a `<` whose run reaches a `>` that is followed by
// something other than `(` or `.`, a one-element parenthesised group (which is not a tuple type --
// a tuple type needs a comma of its own, the rule Roslyn's `ScanTupleType` also applies), and a
// conditional whose `:` would otherwise look like a tuple element name.

func ChainedComparison(a: int, b: int, c: int, d: int): bool {
    return a < b && c > d
}

func ComparisonAgainstMember(a: int, values: List<int>): bool {
    return a < values.Count
}

func ComparisonOverParenthesisedGroup(a: int, b: int, c: int): bool {
    return a < (b) && (c) > b
}

func ConditionalInsideComparison(a: int, b: int, c: int, d: int): bool {
    return a < (b > c ? c : d)
}

func ComparisonThenIndex(a: int, values: int[]): bool {
    return a < values[0]
}

test "the shapes that are comparisons stay comparisons" {
    values := new List<int>()
    values.Add(1)
    values.Add(2)

    assert ChainedComparison(1, 2, 4, 3)
    assert !ChainedComparison(2, 1, 4, 3)
    assert !ChainedComparison(1, 2, 3, 4)

    assert ComparisonAgainstMember(1, values)
    assert !ComparisonAgainstMember(2, values)

    assert ComparisonOverParenthesisedGroup(1, 2, 3)
    assert !ComparisonOverParenthesisedGroup(3, 2, 3)

    assert ConditionalInsideComparison(1, 5, 4, 9)
    assert !ConditionalInsideComparison(9, 5, 4, 9)

    numbers := new int[](1)
    numbers[0] = 7
    assert ComparisonThenIndex(1, numbers)
    assert !ComparisonThenIndex(9, numbers)
}

// A CONSTRUCTED GENERIC TYPE RECEIVER IS THE SAME SCAN WITH THE OTHER CLOSE TOKEN.
//
// `Vector<int>.Count` is a receiver because the matching `>` is followed by a `.`, and the two
// predicates are now literally the same walk with a different last step -- so a type argument that
// only the widened scan can spell has to work in the receiver position too.

func ReceiverWithNestedArgument(): bool {
    return EqualityComparer<Dictionary<string, List<int>>>.Default != null
}

func ReceiverWithTupleArgument(): bool {
    return EqualityComparer<(int, string)>.Default != null
}

func ReceiverWithNullableArgument(): bool {
    return EqualityComparer<List<int>?>.Default != null
}

test "a receiver's type argument list spells the same grammar" {
    assert ReceiverWithNestedArgument()
    assert ReceiverWithTupleArgument()
    assert ReceiverWithNullableArgument()
}
