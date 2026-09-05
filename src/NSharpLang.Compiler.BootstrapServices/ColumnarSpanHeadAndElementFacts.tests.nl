namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// `015-A3` and `015-A4` make `ColumnarTypeOfPlanner` the compiler's SOLE owner of the two span HEADS
// and the two collection-ELEMENT predicates: the C# emitter's four duplicates are deleted in the
// same slice. A grep of the whole estate before the cut found that the two span heads had NO NAMED
// N# OWNER AT ALL (the only mention anywhere was a comment naming the C# pair), and that the two
// collection-element owners were pinned on ONE axis only — three asserts, all of them about
// builder-bound shapes. Nothing pinned the head DISTINCTION the conversion gate reads, and nothing
// pinned the collection-element surface itself: the five heads that return true without asking about
// their arguments, the head list that is NARROWER than the supported-collection list, or the
// `!ContainsBuilderBoundType` tail. These blocks pin the answers the emitter now depends on.

// The span family is not symmetric. `Span<T>` converts implicitly to `ReadOnlySpan<T>` and nothing
// converts the other way; an indexed READ of a ReadOnlySpan lowers through MemoryMarshal.AsBytes
// while a Span read uses the Item getter; and an indexed WRITE is Span-only. The folded
// span-like head cannot answer any of those three questions, which is why two heads are published
// instead of one.
test "the two span heads separate the span family the folded head cannot" {
    spanOfInt := AdmissibilitySpan(typeof(int))
    readOnlyOfInt := AdmissibilityReadOnlySpan(typeof(int))

    assert ColumnarTypeOfPlanner.IsSupportedSpanType(spanOfInt)
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(spanOfInt)
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(readOnlyOfInt)
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(readOnlyOfInt)

    // The conversion gate asks source-is-Span AND target-is-ReadOnlySpan. Exactly one of the four
    // orderings is admitted, and the folded head admits all four.
    assert ColumnarTypeOfPlanner.IsSupportedSpanType(spanOfInt) && ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(readOnlyOfInt)
    assert !(ColumnarTypeOfPlanner.IsSupportedSpanType(readOnlyOfInt) && ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(spanOfInt))
    assert !(ColumnarTypeOfPlanner.IsSupportedSpanType(spanOfInt) && ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(spanOfInt))
    assert !(ColumnarTypeOfPlanner.IsSupportedSpanType(readOnlyOfInt) && ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(readOnlyOfInt))

    // The folded head is exactly the disjunction of the two, on every span shape and on shapes that
    // are not spans at all — so publishing the heads adds a distinction without moving an answer.
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(spanOfInt) == (ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(spanOfInt) || ColumnarTypeOfPlanner.IsSupportedSpanType(spanOfInt))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(readOnlyOfInt) == (ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(readOnlyOfInt) || ColumnarTypeOfPlanner.IsSupportedSpanType(readOnlyOfInt))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(AdmissibilitySpan(typeof(string))) == (ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilitySpan(typeof(string))) || ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(typeof(string))))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(typeof(int)) == (ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(typeof(int)) || ColumnarTypeOfPlanner.IsSupportedSpanType(typeof(int)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanLikeType(typeof(List<int>)) == (ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(typeof(List<int>)) || ColumnarTypeOfPlanner.IsSupportedSpanType(typeof(List<int>)))
}

// A head alone was never the question, and neither head may lose the element constraint the folded
// owner carries — `Span<T>` over a non-blittable element reaches a `GetConstructor` that throws.
test "both span heads carry the blittable element constraint" {
    assert ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(typeof(byte)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(typeof(char)))
    assert ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(typeof(double)))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityReadOnlySpan(typeof(byte)))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityReadOnlySpan(typeof(char)))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityReadOnlySpan(typeof(double)))

    // An enum element is admitted by both, because its underlying integral value is what is stored.
    enumElement := AdmissibilityRuntimeType("System.DayOfWeek")
    assert ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(enumElement))
    assert ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityReadOnlySpan(enumElement))

    // The non-blittable elements stay out of BOTH heads, not just the folded one.
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(typeof(object)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(typeof(decimal)))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilitySpan(typeof(DateTime)))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityReadOnlySpan(typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityReadOnlySpan(typeof(object)))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityReadOnlySpan(typeof(decimal)))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityReadOnlySpan(typeof(int[])))

    // Non-span shapes, the open definitions, and a value that is generic but not a span.
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(typeof(int))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(typeof(int[]))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(typeof(int))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(typeof(int[]))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(typeof(List<int>))
    assert !ColumnarTypeOfPlanner.IsSupportedSpanType(AdmissibilityRuntimeType("System.Span`1"))
    assert !ColumnarTypeOfPlanner.IsSupportedReadOnlySpanType(AdmissibilityRuntimeType("System.ReadOnlySpan`1"))
}

// A collection ELEMENT is a wider surface than a supported VALUE, and the reason is the five-head
// early return: a nested collection is admitted without its arguments being asked about, because the
// nested type's own resolution already vetted them. The head list here is FIVE — narrower than the
// TEN `IsSupportedCollectionType` admits — and the difference is only visible over a builder-bound
// argument, which is exactly the case the emitter's rebind rung exists for.
test "the collection element surface admits the five concrete heads without asking their arguments" {
    sourceStruct := TypeOfCreateBuilder("SpanHeadElementStruct", "SpanHeadElementAsm", 0)

    // The five concrete heads are admitted whatever they close over.
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(List<int>))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(Dictionary<string, int>))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(SortedDictionary<string, int>))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(HashSet<int>))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(Stack<int>))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceStruct)))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(HashSet<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceStruct)))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(Stack<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceStruct)))
    // A catalog-resolved Queue is now an admissible value, including inside the existing heads.
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(AdmissibilityQueueOfInt())
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(AdmissibilityClosed1("System.Collections.Generic.List`1", AdmissibilityQueueOfInt()))

    // The element head list is FIVE, not the ten `IsSupportedCollectionType` carries. Over a baked
    // argument the interface heads still pass — through the supported-value tail, not the early
    // return — and over a BUILDER-BOUND argument the difference shows.
    assert ColumnarTypeOfPlanner.IsSupportedCollectionType(typeof(IReadOnlyList<int>))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(IReadOnlyList<int>))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(IEnumerable<int>))
    assert !ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(IReadOnlyList<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceStruct)))
    assert !ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(IEnumerable<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceStruct)))
}

// The tail is a CONJUNCTION, and both halves are load-bearing: a supported value that is builder-bound
// is not an admissible element, and a builder-bound value that is not a supported value still is when
// it arrives as a bare TypeBuilder. The array case is where the two halves visibly disagree.
test "the collection element tail requires a supported value that is not builder bound" {
    sourceStruct := TypeOfCreateBuilder("SpanHeadTailStruct", "SpanHeadTailAsm", 0)

    // The baked half: supported values pass, unsupported ones do not.
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(int))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(string))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(object))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(DateTime))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(typeof(int[]))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(AdmissibilityRuntimeType("System.Threading.Tasks.TaskScheduler"))
    assert !ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(AdmissibilityRuntimeType("System.Void"))

    // A bare source TypeBuilder is admitted by its own arm, BEFORE the tail is reached.
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(sourceStruct)

    // Its ARRAY reaches the tail instead, is a supported value, and is rejected by the second
    // conjunct alone. Deleting `!ContainsBuilderBoundType` would admit it.
    assert ColumnarTypeOfPlanner.IsSupportedType(sourceStruct.MakeArrayType())
    assert ColumnarTypeOfPlanner.ContainsBuilderBoundType(sourceStruct.MakeArrayType())
    assert !ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(sourceStruct.MakeArrayType())

    // A non-head closed generic over a builder is refused before the tail, by the containment arm.
    assert !ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(AdmissibilityClosed2("System.ValueTuple`2", typeof(int), sourceStruct))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(AdmissibilityClosed2("System.ValueTuple`2", typeof(int), typeof(string)))
}

// The hash-set narrowing is the ONLY thing that separates the two predicates, and the emitter reads
// the difference at every `HashSet<T>` and `IReadOnlySet<T>` resolution: a set element is a KEY, so
// it may not be builder-bound unless it is an enum, whose integral value is what gets hashed.
test "the hash set element narrows the collection element by the non enum builder walk" {
    sourceStruct := TypeOfCreateBuilder("SpanHeadSetStruct", "SpanHeadSetAsm", 0)

    // Baked shapes answer identically on both predicates.
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(typeof(int))
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(typeof(string))
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(typeof(List<int>))
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(typeof(int[]))
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(AdmissibilityQueueOfInt())

    // The five-head early return admits `List<sourceStruct>` as a collection element and the set
    // narrowing takes it back out — the one shape class where the two predicates part company.
    listOfSource := typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceStruct))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(listOfSource)
    assert !ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(listOfSource)
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(sourceStruct)
    assert !ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(sourceStruct)

    // A source ENUM is the exception the second walk exists for: builder-bound, still a set element.
    sourceEnum := ConeEnumParentedBuilder()
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(sourceEnum)
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(sourceEnum)
    listOfSourceEnum := typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(ColumnarTypeAdmissibilityOneType(sourceEnum))
    assert ColumnarTypeOfPlanner.IsAdmissibleCollectionElement(listOfSourceEnum)
    assert ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(listOfSourceEnum)
}
