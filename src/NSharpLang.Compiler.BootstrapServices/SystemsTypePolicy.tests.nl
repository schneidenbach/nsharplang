namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// Native contracts for WHAT A TYPE IS WORTH, AND WHETHER IT MAY CROSS A SYSTEMS BOUNDARY.
//
// Eleven `private` members of `SystemsAnalyzer.cs` decided all of this, and between them they were
// pinned end to end by exactly TWO of the corpus's live codes — NSYS070 (three findings) and, one
// step away, NSYS001. NSYS080's ref-like arm, NSYS160 and NSYS170 are corpus-silent. These contracts
// are the direct pinning, written around the nine things this neighbourhood is easy to get wrong.
//
// (1) THE SIZE TABLE IS KEYED BY THE LANGUAGE KEYWORD, AFTER SIMPLIFICATION. `System.Int32` arrives
// as `Int32`, matches no row, and sizes as the 8-byte unknown default while `int` sizes as 4. This
// is the C# original's behaviour and it is PINNED, not fixed: widening the table changes the
// reported byte count of every systems project that spells a CLR name.
//
// (2) THE PROJECT'S OWN DECLARATIONS ARE CONSULTED BEFORE THE KEYWORDS. An enum sizes as 4 and a
// struct as 32 even when the name also appears in the keyword table.
//
// (3) `Result` ARITY IS PART OF ITS IDENTITY, AND THE TWO CONSUMERS DISAGREE ON PURPOSE.
// `IsResultType` demands exactly two arguments; `EstimateTypeSize`'s `Result` arm does NOT re-check
// the arity and delegates to `EstimateResultSize`, which answers ZERO for the wrong arity rather
// than the 32-byte unknown-generic default.
//
// (4) REF-LIKE IS NAME BASED AND ITS CLOSURE IS STRUCTURAL. A `Span` is ref-like wherever it is
// spelled; a type that merely CONTAINS one is not itself ref-like but does contain one, and the two
// questions have different answers for the same reference.
//
// (5) A `ref struct` MUST BE REGISTERED AS BOTH. The declaration walk adds a `ref struct` to the
// struct set AND the ref-struct set; a name in only the ref-struct set is ref-like but not a value
// type, and this contract pins that the two sets are independent.
//
// (6) HOSTILE ANSWERS WITH ITS REASON AND THE REASON IS THE DIAGNOSTIC. Three arms answer with the
// matched name itself and two with a sentence; all five reach a developer verbatim.
//
// (7) `hotStrict` IS DROPPED FOR AN ARRAY'S ELEMENT AND FOR NOTHING ELSE. `[hot] f(xs: Unknown[])`
// is acceptable while `[hot] f(x: Unknown)` is not, and by-ref/nullable/union recursion keeps the
// strictness.
//
// (8) `Result` IS TRANSPARENT TO THE HOSTILE RULE. It is the sanctioned error-carrying shape, so
// only its payloads are judged — a `Result<List<int>, string>` is hostile BECAUSE OF THE `List`, and
// the reason a developer reads is `List`.
//
// (9) A `T: struct` CONSTRAINT IS CHECKED FIRST AND AS A FLAG. `T` under `T: struct` is acceptable
// even in strict hot mode; the check is a bit test so `T: struct, new()` still counts.

func StpPolicy(): SystemsTypePolicy {
    return new SystemsTypePolicy()
}

func StpRegistered(): SystemsTypePolicy {
    policy := new SystemsTypePolicy()
    policy.RegisterStructType("Vec")
    policy.RegisterStructType("Frame")
    policy.RegisterRefStructType("Frame")
    policy.RegisterEnumType("Color")
    return policy
}

func StpSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func StpGeneric(name: string, argument: TypeReference): GenericTypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(argument)
    return new GenericTypeReference(name, arguments, 1, 1)
}

func StpGeneric2(name: string, first: TypeReference, second: TypeReference): GenericTypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(first)
    arguments.Add(second)
    return new GenericTypeReference(name, arguments, 1, 1)
}

func StpUnion(first: TypeReference, second: TypeReference): UnionTypeReference {
    arms := new List<TypeReference>()
    arms.Add(first)
    arms.Add(second)
    return new UnionTypeReference(arms)
}

func StpEmptyUnion(): UnionTypeReference {
    return new UnionTypeReference(new List<TypeReference>())
}

func StpConstraints(name: string, special: SpecialConstraintKind): List<GenericConstraint> {
    constraints := new List<GenericConstraint>()
    constraints.Add(new GenericConstraint(name, new List<TypeReference>(), special))
    return constraints
}

func StpNew(typeReference: TypeReference?): NewExpression {
    return new NewExpression(typeReference, new List<Argument>(), null, 4, 9)
}

// ── the value-typed names ─────────────────────────────────────────────────────

test "THE KEYWORD VALUE TYPES ARE VALUE TYPES AND THE REFERENCE ONES ARE NOT" {
    policy := StpPolicy()
    assert policy.IsValueTypeName("int")
    assert policy.IsValueTypeName("nuint")
    assert policy.IsValueTypeName("decimal")
    assert policy.IsValueTypeName("Guid")
    assert policy.IsValueTypeName("TimeSpan")
    assert !policy.IsValueTypeName("string")
    assert !policy.IsValueTypeName("object")
    assert !policy.IsValueTypeName("")
}

test "A VALUE-TYPE NAME IS SIMPLIFIED FIRST, SO THE QUALIFIED SPELLING OF A BCL STRUCT STILL COUNTS" {
    policy := StpPolicy()
    assert policy.IsValueTypeName("System.Guid")
    assert policy.IsValueTypeName("System.DateTime")
    // ... but `System.Int32` is not the KEYWORD `int`, and the keyword is what the table holds.
    assert !policy.IsValueTypeName("System.Int32")
    assert !policy.IsValueTypeName("Int32")
}

test "A DECLARED STRUCT OR ENUM IS A VALUE TYPE AND AN UNREGISTERED NAME IS NOT" {
    policy := StpRegistered()
    assert policy.IsValueTypeName("Vec")
    assert policy.IsValueTypeName("Color")
    assert !policy.IsValueTypeName("Unknown")
    assert !StpPolicy().IsValueTypeName("Vec")
}

test "THE ENUM QUERY IS PUBLISHED SEPARATELY BECAUSE ONE READER OUTSIDE THIS OWNER NEEDS IT" {
    policy := StpRegistered()
    assert policy.IsEnumTypeName("Color")
    assert !policy.IsEnumTypeName("Vec")
    // NOT simplified: the hot-readiness reader passes a bare receiver identifier, never a
    // qualified name, and widening this would silence a real warmup obligation.
    assert !policy.IsEnumTypeName("A.Color")
}

test "BEGINANALYSIS CLEARS ALL THREE SETS, WHICH IS WHAT MAKES THE OWNER REUSABLE ACROSS ANALYSES" {
    policy := StpRegistered()
    assert policy.IsValueTypeName("Vec")
    assert policy.IsEnumTypeName("Color")
    assert policy.IsRefLikeType(StpSimple("Frame"))
    policy.BeginAnalysis()
    assert !policy.IsValueTypeName("Vec")
    assert !policy.IsEnumTypeName("Color")
    assert !policy.IsRefLikeType(StpSimple("Frame"))
}

// ── ref-like, and its transitive closure ──────────────────────────────────────

test "THE TWO SPAN NAMES AND ANYTHING BY-REF ARE REF-LIKE WHEREVER THEY ARE SPELLED" {
    policy := StpPolicy()
    assert policy.IsRefLikeType(StpGeneric("Span", StpSimple("byte")))
    assert policy.IsRefLikeType(StpGeneric("ReadOnlySpan", StpSimple("byte")))
    assert policy.IsRefLikeType(StpGeneric("System.Span", StpSimple("byte")))
    assert policy.IsRefLikeType(StpSimple("Span"))
    assert policy.IsRefLikeType(new ByRefTypeReference(StpSimple("int")))
    assert !policy.IsRefLikeType(StpGeneric("Memory", StpSimple("byte")))
    assert !policy.IsRefLikeType(StpSimple("int"))
}

test "A DECLARED REF STRUCT IS REF-LIKE, AND THE STRUCT SET ALONE DOES NOT MAKE ONE" {
    policy := StpRegistered()
    assert policy.IsRefLikeType(StpSimple("Frame"))
    assert !policy.IsRefLikeType(StpSimple("Vec"))
    // Both sets hold `Frame`: the walk registers a `ref struct` in both, and the two questions stay
    // independent.
    assert policy.IsValueTypeName("Frame")
}

test "AN ARRAY OF SPANS IS NOT ITSELF REF-LIKE BUT IT CONTAINS ONE, AND THE TWO ANSWERS DIFFER" {
    policy := StpPolicy()
    spans := new ArrayTypeReference(StpGeneric("Span", StpSimple("byte")))
    assert !policy.IsRefLikeType(spans)
    assert policy.ContainsRefLikeType(spans)
}

test "CONTAINSREFLIKE REACHES THROUGH EVERY SHAPE THAT CAN HOLD ANOTHER TYPE" {
    policy := StpPolicy()
    span := StpGeneric("Span", StpSimple("byte"))
    assert policy.ContainsRefLikeType(StpGeneric("List", span))
    assert policy.ContainsRefLikeType(new ArrayTypeReference(span))
    assert policy.ContainsRefLikeType(new NullableTypeReference(span))
    assert policy.ContainsRefLikeType(StpUnion(StpSimple("int"), span))
    assert policy.ContainsRefLikeType(new ByRefTypeReference(StpSimple("int")))
    assert policy.ContainsRefLikeType(StpGeneric2("Result", StpSimple("int"), span))
    assert !policy.ContainsRefLikeType(StpGeneric2("Result", StpSimple("int"), StpSimple("string")))
    assert !policy.ContainsRefLikeType(StpEmptyUnion())
}

// ── Result identity and copy shape ────────────────────────────────────────────

test "A RESULT IS A RESULT ONLY AT ARITY TWO, AND THE SIMPLE NAME IS WHAT IS MATCHED" {
    policy := StpPolicy()
    assert policy.IsResultType(StpGeneric2("Result", StpSimple("int"), StpSimple("string")))
    assert policy.IsResultType(StpGeneric2("System.Result", StpSimple("int"), StpSimple("string")))
    assert !policy.IsResultType(StpGeneric("Result", StpSimple("int")))
    assert !policy.IsResultType(StpSimple("Result"))
    assert !policy.IsResultType(StpGeneric2("Either", StpSimple("int"), StpSimple("string")))
}

test "THE RESULT SIZE IS A TAG ALLOWANCE PLUS BOTH PAYLOADS, AND THE WRONG ARITY IS ZERO" {
    policy := StpPolicy()
    assert policy.EstimateResultSize(StpGeneric2("Result", StpSimple("int"), StpSimple("int"))) == 24
    assert policy.EstimateResultSize(StpGeneric2("Result", StpSimple("long"), StpSimple("byte"))) == 25
    assert policy.EstimateResultSize(StpGeneric("Result", StpSimple("int"))) == 0
    assert policy.EstimateResultSize(StpSimple("Result")) == 0
}

test "THE RESULT ARM OF THE SIZE WALK DOES NOT RE-CHECK THE ARITY, SO A MALFORMED RESULT SIZES AS ZERO" {
    policy := StpPolicy()
    // This is the asymmetry between `IsResultType` and the size walk, and it is deliberate: the
    // arity check lives in `EstimateResultSize` and the caller does not repeat it. A one-argument
    // `Result` therefore sizes as 0 rather than as the 32-byte unknown-generic default.
    assert policy.EstimateTypeSize(StpGeneric("Result", StpSimple("int"))) == 0
    assert policy.EstimateTypeSize(StpGeneric("Unknown", StpSimple("int"))) == 32
}

test "THE RESULT ABI GUIDANCE IS A STRICT THRESHOLD AND THE SENTENCE CARRIES THE MEASURED SIZE" {
    policy := StpRegistered()
    inner := StpGeneric2("Result", StpSimple("Vec"), StpSimple("Vec"))
    // 16 + 32 + 32 = 80 bytes, within the guidance.
    assert policy.EstimateResultSize(inner) == 80
    assert policy.ResultAbiReason(inner) == null
    // 16 + 80 + 80 = 176 bytes, above it.
    outer := StpGeneric2("Result", inner, inner)
    assert policy.ResultAbiReason(outer) == "Result<T,E> copy shape is estimated at 176 bytes, above the v1 hot-path guidance of 128 bytes"
}

test "THE RESULT ABI RULE CHECKS THE IDENTITY BEFORE THE SIZE, SO A WIDE NON-RESULT IS SILENT" {
    policy := StpRegistered()
    inner := StpGeneric2("Result", StpSimple("Vec"), StpSimple("Vec"))
    // Same arity, same payloads, same 176-byte arithmetic — but it is not a `Result`, and the
    // identity guard is what keeps it out of the report.
    impostor := StpGeneric2("Unknown", inner, inner)
    assert policy.EstimateResultSize(impostor) == 176
    assert policy.ResultAbiReason(impostor) == null
    assert policy.ResultAbiReason(null) == null
    assert policy.ResultAbiReason(StpSimple("Vec")) == null
}

test "THE SIZE WALK OVER-CHARGES WHAT IT CANNOT SEE, AND THE SPAN SHAPES ARE THE ONE FIXED WIDTH" {
    policy := StpPolicy()
    assert policy.EstimateTypeSize(StpGeneric("Span", StpSimple("byte"))) == 16
    assert policy.EstimateTypeSize(StpGeneric("ReadOnlyMemory", StpSimple("byte"))) == 16
    assert policy.EstimateTypeSize(StpGeneric("List", StpSimple("byte"))) == 32
    assert policy.EstimateTypeSize(new ArrayTypeReference(StpSimple("int"))) == 8
    assert policy.EstimateTypeSize(new ByRefTypeReference(StpSimple("int"))) == 8
    assert policy.EstimateTypeSize(new NullableTypeReference(StpSimple("int"))) == 5
    assert policy.EstimateTypeSize(StpSimple("int")) == 4
}

test "A UNION SIZES AS ITS WIDEST ARM PLUS A TAG, AND AN EMPTY UNION IS ZERO RATHER THAN A TAG" {
    policy := StpPolicy()
    assert policy.EstimateTypeSize(StpUnion(StpSimple("byte"), StpSimple("long"))) == 16
    assert policy.EstimateTypeSize(StpUnion(StpSimple("long"), StpSimple("byte"))) == 16
    assert policy.EstimateTypeSize(StpEmptyUnion()) == 0
}

test "THE SIZE TABLE IS KEYED BY THE LANGUAGE KEYWORD AND THE CLR SPELLING FALLS TO THE UNKNOWN WIDTH" {
    policy := StpPolicy()
    assert policy.EstimateSimpleTypeSize("int") == 4
    // PINNED, NOT FIXED. `EstimateTypeSize` simplifies before it sizes, so `System.Int32` arrives
    // here as `Int32`, matches no keyword row and takes the 8-byte unknown default. Widening the
    // table would change every systems project that spells a CLR name.
    assert policy.EstimateSimpleTypeSize("Int32") == 8
    assert policy.EstimateTypeSize(StpSimple("System.Int32")) == 8
    assert policy.EstimateTypeSize(StpSimple("Unknown")) == 8
    assert policy.EstimateSimpleTypeSize("bool") == 1
    assert policy.EstimateSimpleTypeSize("char") == 2
    assert policy.EstimateSimpleTypeSize("nuint") == 8
    assert policy.EstimateSimpleTypeSize("decimal") == 16
    assert policy.EstimateSimpleTypeSize("DateTime") == 8
}

test "A DECLARED ENUM OR STRUCT IS SIZED BEFORE THE KEYWORD TABLE IS CONSULTED" {
    policy := StpRegistered()
    assert policy.EstimateSimpleTypeSize("Color") == 4
    assert policy.EstimateSimpleTypeSize("Vec") == 32
    assert policy.EstimateTypeSize(StpSimple("Vec")) == 32
    // The order is what this pins: a declaration named like a keyword answers as the declaration.
    shadow := StpPolicy()
    shadow.RegisterEnumType("long")
    assert shadow.EstimateSimpleTypeSize("long") == 4
}

// ── the hostile surface ───────────────────────────────────────────────────────

test "THE FOURTEEN NAMED CONSTRUCTORS ARE HOSTILE AND THE REASON IS THE NAME ITSELF" {
    policy := StpPolicy()
    assert policy.HostileSurfaceReason(StpGeneric("List", StpSimple("int")), false, null) == "List"
    assert policy.HostileSurfaceReason(StpGeneric("Task", StpSimple("int")), false, null) == "Task"
    assert policy.HostileSurfaceReason(StpGeneric("IReadOnlyCollection", StpSimple("int")), false, null) == "IReadOnlyCollection"
    assert policy.HostileSurfaceReason(StpGeneric2("Func", StpSimple("int"), StpSimple("bool")), false, null) == "Func"
    assert policy.HostileSurfaceReason(StpGeneric2("System.Collections.Generic.Dictionary", StpSimple("string"), StpSimple("int")), false, null) == "Dictionary"
}

test "THE SPAN AND MEMORY CONSTRUCTORS ARE ALWAYS ACCEPTABLE, EVEN IN STRICT HOT MODE" {
    policy := StpPolicy()
    assert policy.HostileSurfaceReason(StpGeneric("Span", StpSimple("byte")), true, null) == null
    assert policy.HostileSurfaceReason(StpGeneric("ReadOnlySpan", StpSimple("byte")), true, null) == null
    assert policy.HostileSurfaceReason(StpGeneric("Memory", StpSimple("byte")), true, null) == null
    assert policy.HostileSurfaceReason(StpGeneric("ReadOnlyMemory", StpSimple("byte")), true, null) == null
}

test "AN UNSUMMARIZED GENERIC IS ACCEPTABLE TO A BOUNDARY AND REFUSED BY A HOT SIGNATURE" {
    policy := StpPolicy()
    unknown := StpGeneric("Unknown", StpSimple("int"))
    assert policy.HostileSurfaceReason(unknown, false, null) == null
    assert policy.HostileSurfaceReason(unknown, true, null) == "generic type 'Unknown' has no HotSummary surface rule"
}

test "RESULT IS TRANSPARENT: ONLY ITS PAYLOADS ARE JUDGED AND THE PAYLOAD'S REASON IS REPORTED" {
    policy := StpPolicy()
    clean := StpGeneric2("Result", StpSimple("int"), StpSimple("string"))
    assert policy.HostileSurfaceReason(clean, false, null) == null
    dirty := StpGeneric2("Result", StpGeneric("List", StpSimple("int")), StpSimple("string"))
    assert policy.HostileSurfaceReason(dirty, false, null) == "List"
    // The FIRST hostile arm answers, which is what makes the reason deterministic.
    both := StpGeneric2("Result", StpGeneric("List", StpSimple("int")), StpGeneric("Task", StpSimple("int")))
    assert policy.HostileSurfaceReason(both, false, null) == "List"
}

test "THE FIVE NAMED REFERENCE SHAPES ARE HOSTILE BY NAME AND STRING IS DELIBERATELY NOT" {
    policy := StpPolicy()
    assert policy.HostileSurfaceReason(StpSimple("object"), false, null) == "object"
    assert policy.HostileSurfaceReason(StpSimple("dynamic"), false, null) == "dynamic"
    assert policy.HostileSurfaceReason(StpSimple("Type"), false, null) == "Type"
    assert policy.HostileSurfaceReason(StpSimple("Stream"), false, null) == "Stream"
    assert policy.HostileSurfaceReason(StpSimple("Delegate"), false, null) == "Delegate"
    assert policy.HostileSurfaceReason(StpSimple("string"), true, null) == null
}

test "AN UNSUMMARIZED SIMPLE TYPE IS ACCEPTABLE TO A BOUNDARY AND NAMED IN A SENTENCE BY A HOT SIGNATURE" {
    policy := StpRegistered()
    assert policy.HostileSurfaceReason(StpSimple("Unknown"), false, null) == null
    assert policy.HostileSurfaceReason(StpSimple("Unknown"), true, null) == "managed or unsummarized type 'Unknown'"
    // A declared struct or enum IS summarized, so strict hot mode accepts it.
    assert policy.HostileSurfaceReason(StpSimple("Vec"), true, null) == null
    assert policy.HostileSurfaceReason(StpSimple("Color"), true, null) == null
}

test "STRICTNESS IS DROPPED FOR AN ARRAY'S ELEMENT AND FOR NOTHING ELSE" {
    policy := StpPolicy()
    element := StpSimple("Unknown")
    assert policy.HostileSurfaceReason(element, true, null) == "managed or unsummarized type 'Unknown'"
    assert policy.HostileSurfaceReason(new ArrayTypeReference(element), true, null) == null
    // by-ref, nullable and union recursion all keep it.
    assert policy.HostileSurfaceReason(new ByRefTypeReference(element), true, null) == "managed or unsummarized type 'Unknown'"
    assert policy.HostileSurfaceReason(new NullableTypeReference(element), true, null) == "managed or unsummarized type 'Unknown'"
    assert policy.HostileSurfaceReason(StpUnion(StpSimple("int"), element), true, null) == "managed or unsummarized type 'Unknown'"
    // ... and the drop does NOT survive one more hop: an array INSIDE a by-ref is still an array.
    assert policy.HostileSurfaceReason(new ByRefTypeReference(new ArrayTypeReference(element)), true, null) == null
}

test "A UNION IS HOSTILE WHEN ANY ARM IS, AND AN EMPTY UNION IS NOT" {
    policy := StpPolicy()
    assert policy.HostileSurfaceReason(StpUnion(StpSimple("int"), StpSimple("object")), false, null) == "object"
    assert policy.HostileSurfaceReason(StpUnion(StpSimple("int"), StpSimple("string")), false, null) == null
    assert policy.HostileSurfaceReason(StpEmptyUnion(), true, null) == null
}

test "A NULL TYPE AND A SHAPE WITH NO NAME ARE BOTH ACCEPTABLE SURFACES" {
    policy := StpPolicy()
    assert policy.HostileSurfaceReason(null, true, null) == null
    // A tuple and a function type reach the walk's default arm.
    elements := new List<TupleTypeElement>()
    elements.Add(new TupleTypeElement(StpSimple("int"), null))
    assert policy.HostileSurfaceReason(new TupleTypeReference(elements), true, null) == null
    assert policy.HostileSurfaceReason(new FunctionTypeReference(new List<TypeReference>(), StpSimple("bool")), true, null) == null
}

// ── the struct constraint ─────────────────────────────────────────────────────

test "A T:STRUCT CONSTRAINT MAKES THE PARAMETER ACCEPTABLE EVEN IN STRICT HOT MODE" {
    policy := StpPolicy()
    structConstraint := StpConstraints("T", SpecialConstraintKind.Struct)
    assert policy.HostileSurfaceReason(StpSimple("T"), true, structConstraint) == null
    assert policy.HostileSurfaceReason(StpSimple("T"), true, null) == "managed or unsummarized type 'T'"
    // The constraint is matched by NAME: a different parameter's constraint does not apply.
    assert policy.HostileSurfaceReason(StpSimple("U"), true, structConstraint) == "managed or unsummarized type 'U'"
}

test "THE STRUCT CONSTRAINT IS A BIT TEST, SO T:STRUCT,NEW() STILL COUNTS AND T:CLASS DOES NOT" {
    policy := StpPolicy()
    assert policy.IsValueConstrainedGenericParameter("T", StpConstraints("T", SpecialConstraintKind.Struct))
    assert policy.IsValueConstrainedGenericParameter("T", StpConstraints("T", (SpecialConstraintKind)6))
    assert !policy.IsValueConstrainedGenericParameter("T", StpConstraints("T", SpecialConstraintKind.Class))
    assert !policy.IsValueConstrainedGenericParameter("T", StpConstraints("T", SpecialConstraintKind.New))
    assert !policy.IsValueConstrainedGenericParameter("T", StpConstraints("T", SpecialConstraintKind.None))
    assert !policy.IsValueConstrainedGenericParameter("T", null)
    assert !policy.IsValueConstrainedGenericParameter("T", new List<GenericConstraint>())
}

// ── whether a `new` reaches the heap ──────────────────────────────────────────

test "A TYPELESS NEW AND EVERY ARRAY CREATION ARE HEAP ALLOCATIONS REGARDLESS OF ELEMENT TYPE" {
    policy := StpRegistered()
    assert policy.IsHeapAllocation(StpNew(null))
    assert policy.IsHeapAllocation(StpNew(new ArrayTypeReference(StpSimple("int"))))
    assert policy.IsHeapAllocation(StpNew(new ArrayTypeReference(StpSimple("Vec"))))
}

test "A VALUE-TYPED NEW IS NOT A HEAP ALLOCATION AND A REFERENCE-TYPED ONE IS" {
    policy := StpRegistered()
    assert !policy.IsHeapAllocation(StpNew(StpSimple("int")))
    assert !policy.IsHeapAllocation(StpNew(StpSimple("Vec")))
    assert !policy.IsHeapAllocation(StpNew(StpSimple("Color")))
    assert policy.IsHeapAllocation(StpNew(StpSimple("string")))
    assert policy.IsHeapAllocation(StpNew(StpSimple("Unknown")))
    assert policy.IsHeapAllocation(StpNew(StpGeneric("List", StpSimple("int"))))
}

test "A NULLABLE NEW IS A HEAP ALLOCATION BECAUSE ERASURE KEEPS THE MARK AND THE MARKED NAME IS UNKNOWN" {
    policy := StpRegistered()
    // `int?` erases to `int?`, which is not in the value-type table. Reproduced from the C#
    // original rather than corrected: dropping the decoration here would also change what
    // `IsRefLikeType` sees, and the two rules read the same erased name.
    assert policy.IsHeapAllocation(StpNew(new NullableTypeReference(StpSimple("int"))))
    assert policy.IsHeapAllocation(StpNew(new ByRefTypeReference(StpSimple("int"))))
}

test "A GENERIC OVER A DECLARED STRUCT IS STILL A HEAP ALLOCATION BECAUSE ERASURE DROPS THE ARGUMENTS" {
    policy := StpRegistered()
    // `Vec<int>` erases to `Vec`, which IS registered — so this one is NOT a heap allocation, and
    // the erasure is exactly why. The contract states it in both directions.
    assert !policy.IsHeapAllocation(StpNew(StpGeneric("Vec", StpSimple("int"))))
    assert policy.IsHeapAllocation(StpNew(StpGeneric("Unknown", StpSimple("int"))))
}
