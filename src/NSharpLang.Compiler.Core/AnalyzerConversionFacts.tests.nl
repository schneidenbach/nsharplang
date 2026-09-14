namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast

// The twelve participating built-in numeric types, in the two vocabularies the analyzer sees them
// in. Index i of each list denotes the same CLR type.
func ConversionSourceNames(): string[] {
    names := new string[](12)
    names[0] = "byte"
    names[1] = "sbyte"
    names[2] = "short"
    names[3] = "ushort"
    names[4] = "int"
    names[5] = "uint"
    names[6] = "long"
    names[7] = "ulong"
    names[8] = "char"
    names[9] = "float"
    names[10] = "double"
    names[11] = "decimal"
    return names
}

func ConversionClrTypes(): Type[] {
    types := new Type[](12)
    types[0] = typeof(byte)
    types[1] = typeof(sbyte)
    types[2] = typeof(short)
    types[3] = typeof(ushort)
    types[4] = typeof(int)
    types[5] = typeof(uint)
    types[6] = typeof(long)
    types[7] = typeof(ulong)
    types[8] = typeof(char)
    types[9] = typeof(float)
    types[10] = typeof(double)
    types[11] = typeof(decimal)
    return types
}

// The CLR implicit numeric conversion table, restated independently of the owner as a
// space-delimited target set per source. This is the specification the owner is checked against;
// it is written out longhand on purpose so a table edit cannot silently agree with itself.
func ConversionExpectedTargets(source: string): string {
    if source == "byte" {
        return " short ushort int uint long ulong float double decimal "
    }
    if source == "sbyte" {
        return " short int long float double decimal "
    }
    if source == "short" {
        return " int long float double decimal "
    }
    if source == "ushort" {
        return " int uint long ulong float double decimal "
    }
    if source == "int" {
        return " long float double decimal "
    }
    if source == "uint" {
        return " long ulong float double decimal "
    }
    if source == "long" {
        return " float double decimal "
    }
    if source == "ulong" {
        return " float double decimal "
    }
    if source == "char" {
        return " ushort int uint long ulong float double decimal "
    }
    if source == "float" {
        return " double "
    }
    if source == "double" {
        return " "
    }
    if source == "decimal" {
        return " "
    }
    throw new InvalidOperationException("Unknown conversion source '" + source + "'.")
}

func ConversionFailure(
    vocabulary: string,
    source: string,
    target: string,
    expected: bool
): InvalidOperationException {
    return new InvalidOperationException(
        "Implicit numeric conversion " + vocabulary + " '" + source + "' -> '" + target + "' should be " + (expected ? "admitted" : "rejected") + "."
    )
}

func ConversionRecordType(isStruct: bool): RecordTypeInfo {
    return new RecordTypeInfo(
        "Shape",
        1,
        1,
        isStruct,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func ConversionClassType(): ClassTypeInfo {
    return new ClassTypeInfo(
        "Widget",
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true
    )
}

func ConversionStructType(): StructTypeInfo {
    return new StructTypeInfo(
        "Point",
        1,
        1,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func ConversionInterfaceType(): InterfaceTypeInfo {
    return new InterfaceTypeInfo(
        "IShape",
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func ConversionEnumType(): EnumTypeInfo {
    return new EnumTypeInfo(
        new EnumDeclarationInfo("Color", new List<EnumMemberInfo>(), EnumType.Int)
    )
}

func ConversionUnionType(): UnionTypeInfo {
    return new UnionTypeInfo(
        new UnionDeclarationInfo("Result", null, new List<UnionCase>())
    )
}

func ConversionAnonymousUnionType(): AnonymousUnionTypeInfo {
    arms := new List<TypeInfo>()
    arms.Add(BuiltInTypes.Int)
    arms.Add(BuiltInTypes.String)
    return new AnonymousUnionTypeInfo(arms)
}

func ConversionGenericType(): GenericTypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    return new GenericTypeInfo("List", arguments, new ReflectionTypeInfo(typeof(List<int>)))
}

func ConversionNullableGenericType(): GenericTypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    return new GenericTypeInfo("Nullable", arguments, new ReflectionTypeInfo(typeof(Nullable<int>).GetGenericTypeDefinition()))
}

func ConversionReadOnlyDictionaryGenericType(): GenericTypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.String)
    arguments.Add(BuiltInTypes.String)
    return new GenericTypeInfo("IReadOnlyDictionary", arguments, new ReflectionTypeInfo(typeof(IReadOnlyDictionary<string, string>).GetGenericTypeDefinition()))
}

func ConversionUnresolvedGenericType(): GenericTypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    return new GenericTypeInfo("Box", arguments)
}

// A constructed generic over a VALUE-type definition: `KeyValuePair<int, int>` is a struct, and the
// constructed shape alone carries nothing that separates it from `List<int>`.
func ConversionValueGenericType(): GenericTypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    arguments.Add(BuiltInTypes.Int)
    return new GenericTypeInfo("KeyValuePair", arguments, new ReflectionTypeInfo(typeof(KeyValuePair<int, int>)))
}

// A constructed generic the analyzer never resolved a definition for.
func ConversionDefinitionlessGenericType(): GenericTypeInfo {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.Int)
    return new GenericTypeInfo("List", arguments)
}

func ConversionFunctionType(): FunctionTypeInfo {
    result := new FunctionTypeInfo()
    result.ParameterTypes = new List<TypeInfo>()
    result.ReturnType = BuiltInTypes.Int
    return result
}

test "the implicit numeric conversion table is exact over every N# source type name pair" {
    names := ConversionSourceNames()
    sourceIndex := 0
    while sourceIndex < names.Length {
        expectedTargets := ConversionExpectedTargets(names[sourceIndex])
        targetIndex := 0
        while targetIndex < names.Length {
            expected := expectedTargets.Contains(" " + names[targetIndex] + " ")
            actual := AnalyzerConversionFacts.IsImplicitNumericConversion(
                new SimpleTypeInfo(names[sourceIndex]),
                new SimpleTypeInfo(names[targetIndex])
            )
            if actual != expected {
                throw ConversionFailure(
                    "of source name",
                    names[sourceIndex],
                    names[targetIndex],
                    expected
                )
            }

            targetIndex += 1
        }

        sourceIndex += 1
    }

    // Identity is not a conversion on the source-name path: the caller answers identity first.
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new SimpleTypeInfo("int"),
        new SimpleTypeInfo("int")
    )
}

test "the implicit numeric conversion table is exact over every reflection type pair" {
    types := ConversionClrTypes()
    names := ConversionSourceNames()
    sourceIndex := 0
    while sourceIndex < types.Length {
        expectedTargets := ConversionExpectedTargets(names[sourceIndex])
        targetIndex := 0
        while targetIndex < types.Length {
            expected := sourceIndex == targetIndex || expectedTargets.Contains(" " + names[targetIndex] + " ")
            actual := AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
                types[sourceIndex],
                types[targetIndex]
            )
            if actual != expected {
                throw ConversionFailure(
                    "of reflection type",
                    names[sourceIndex],
                    names[targetIndex],
                    expected
                )
            }

            targetIndex += 1
        }

        sourceIndex += 1
    }
}

test "reflection numeric conversion reads through Nullable and short-circuits on identity" {
    // Nullable<T> is read through to T on BOTH sides before the table is consulted.
    assert AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
        typeof(int?),
        typeof(long)
    )
    assert AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
        typeof(int),
        typeof(long?)
    )
    assert AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
        typeof(int?),
        typeof(long?)
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
        typeof(long?),
        typeof(int?)
    )

    // Identical reflection types short-circuit true even when they are not numeric at all.
    assert AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
        typeof(string),
        typeof(string)
    )
    assert AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
        typeof(DateTime),
        typeof(DateTime)
    )
}

test "non-numeric and cross-vocabulary spellings never convert" {
    // bool, string and object take no part in either direction.
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new SimpleTypeInfo("bool"),
        new SimpleTypeInfo("int")
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new SimpleTypeInfo("int"),
        new SimpleTypeInfo("bool")
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new SimpleTypeInfo("string"),
        new SimpleTypeInfo("object")
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
        typeof(bool),
        typeof(int)
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(
        typeof(string),
        typeof(object)
    )

    // The two vocabularies are disjoint: a CLR spelling is not a source name and vice versa.
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new SimpleTypeInfo("System.Int32"),
        new SimpleTypeInfo("System.Int64")
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new SimpleTypeInfo("System.Int32"),
        new SimpleTypeInfo("long")
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new SimpleTypeInfo("int"),
        new SimpleTypeInfo("System.Int64")
    )

    // Only SimpleTypeInfo participates on the source-name path.
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new ReflectionTypeInfo(typeof(int)),
        new SimpleTypeInfo("long")
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new SimpleTypeInfo("int"),
        new ReflectionTypeInfo(typeof(long))
    )
    assert !AnalyzerConversionFacts.IsImplicitNumericConversion(
        new NullableTypeInfo(new SimpleTypeInfo("int")),
        new SimpleTypeInfo("long")
    )
}

test "reference-type classification covers every built-in simple name" {
    valueNames := ConversionSourceNames()
    index := 0
    while index < valueNames.Length {
        if AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo(valueNames[index])) {
            throw new InvalidOperationException(
                "'" + valueNames[index] + "' must classify as a value type."
            )
        }

        index += 1
    }

    assert !AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo("bool"))
    assert !AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo("void"))
    assert !AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo("null"))
    assert !AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo("never"))

    // Every other simple name is a reference type — string and object included.
    assert AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo("string"))
    assert AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo("object"))
    assert AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo("Int32"))
}

test "reference-type classification covers every type-info family" {
    assert AnalyzerConversionFacts.IsReferenceType(ConversionClassType())
    assert AnalyzerConversionFacts.IsReferenceType(ConversionInterfaceType())
    assert AnalyzerConversionFacts.IsReferenceType(new ArrayTypeInfo(BuiltInTypes.Int))
    assert AnalyzerConversionFacts.IsReferenceType(ConversionFunctionType())
    assert AnalyzerConversionFacts.IsReferenceType(ConversionUnionType())
    assert AnalyzerConversionFacts.IsReferenceType(ConversionAnonymousUnionType())

    // A record is a reference type unless it is declared a record struct.
    assert AnalyzerConversionFacts.IsReferenceType(ConversionRecordType(false))
    assert !AnalyzerConversionFacts.IsReferenceType(ConversionRecordType(true))

    assert !AnalyzerConversionFacts.IsReferenceType(ConversionStructType())
    assert !AnalyzerConversionFacts.IsReferenceType(ConversionEnumType())
    assert !AnalyzerConversionFacts.IsReferenceType(new ByRefTypeInfo(BuiltInTypes.Int))

    // A closed generic instantiation answers FROM ITS DEFINITION: `List<int>` is a class, so it is a
    // reference type and `null` is one of its values; `Nullable<int>` spelled generically is not.
    assert AnalyzerConversionFacts.IsReferenceType(ConversionGenericType())
    assert !AnalyzerConversionFacts.IsReferenceType(ConversionNullableGenericType())
    assert AnalyzerConversionFacts.IsReferenceType(ConversionReadOnlyDictionaryGenericType())

    // An instantiation the analyzer has not resolved to a definition keeps the conservative answer:
    // no definition is an absence of information, not a decision that it is a value type.
    assert !AnalyzerConversionFacts.IsReferenceType(ConversionUnresolvedGenericType())

    // An oblivious shell is an ANNOTATION — metadata written without a nullable context — so it is
    // transparent, and C#'s own rule is that an oblivious reference position admits null.
    assert AnalyzerConversionFacts.IsReferenceType(new ObliviousTypeInfo(BuiltInTypes.String))
    assert AnalyzerConversionFacts.IsReferenceType(new ObliviousTypeInfo(ConversionReadOnlyDictionaryGenericType()))
    assert AnalyzerConversionFacts.IsReferenceType(new ObliviousTypeInfo(new ArrayTypeInfo(new ObliviousTypeInfo(BuiltInTypes.String))))
    assert !AnalyzerConversionFacts.IsReferenceType(new ObliviousTypeInfo(BuiltInTypes.Int))

    // A constructed generic over a VALUE-type definition is not a reference type, and one carrying
    // NO definition keeps the conservative answer.
    assert !AnalyzerConversionFacts.IsReferenceType(ConversionValueGenericType())
    assert !AnalyzerConversionFacts.IsReferenceType(ConversionDefinitionlessGenericType())

    // Reflection types defer to the CLR value-type flag.
    assert AnalyzerConversionFacts.IsReferenceType(new ReflectionTypeInfo(typeof(string)))
    assert AnalyzerConversionFacts.IsReferenceType(new ReflectionTypeInfo(typeof(List<int>)))
    assert !AnalyzerConversionFacts.IsReferenceType(new ReflectionTypeInfo(typeof(int)))
    assert !AnalyzerConversionFacts.IsReferenceType(new ReflectionTypeInfo(typeof(DateTime)))

    // Families with no rule of their own are not reference types.
    assert !AnalyzerConversionFacts.IsReferenceType(BuiltInTypes.Unknown)
    assert !AnalyzerConversionFacts.IsReferenceType(new NullableTypeInfo(BuiltInTypes.Int))
}

test "reflection assignability accepts identity, base chains and interface lists" {
    // Exact identity.
    assert AnalyzerConversionFacts.IsReflectionAssignableFrom(typeof(int), typeof(int))

    // Ordinary CLR assignability.
    assert AnalyzerConversionFacts.IsReflectionAssignableFrom(typeof(object), typeof(string))

    // Interfaces the source implements, generic and non-generic.
    assert AnalyzerConversionFacts.IsReflectionAssignableFrom(
        typeof(IComparable),
        typeof(string)
    )
    assert AnalyzerConversionFacts.IsReflectionAssignableFrom(
        typeof(IEnumerable<int>),
        typeof(List<int>)
    )

    // Base chain of the source, more than one hop up.
    assert AnalyzerConversionFacts.IsReflectionAssignableFrom(
        typeof(Exception),
        typeof(ArgumentNullException)
    )
    assert AnalyzerConversionFacts.IsReflectionAssignableFrom(
        typeof(object),
        typeof(ArgumentNullException)
    )

    // Not assignable in the other direction, and unrelated types stay rejected.
    assert !AnalyzerConversionFacts.IsReflectionAssignableFrom(
        typeof(string),
        typeof(object)
    )
    assert !AnalyzerConversionFacts.IsReflectionAssignableFrom(
        typeof(ArgumentNullException),
        typeof(Exception)
    )
    assert !AnalyzerConversionFacts.IsReflectionAssignableFrom(
        typeof(int),
        typeof(string)
    )

    // Reflection assignability is NOT the numeric table: widening is a separate decision.
    assert !AnalyzerConversionFacts.IsReflectionAssignableFrom(typeof(long), typeof(int))
}

test "the span name gate accepts both spellings of both span types and nothing else" {
    // The four spellings the analyzer can see for the two span types.
    assert AnalyzerConversionFacts.IsSpanTypeName("Span")
    assert AnalyzerConversionFacts.IsSpanTypeName("ReadOnlySpan")
    assert AnalyzerConversionFacts.IsSpanTypeName("System.Span")
    assert AnalyzerConversionFacts.IsSpanTypeName("System.ReadOnlySpan")

    // The match is exact and case-sensitive — no prefix, suffix or arity decoration.
    assert !AnalyzerConversionFacts.IsSpanTypeName("span")
    assert !AnalyzerConversionFacts.IsSpanTypeName("SPAN")
    assert !AnalyzerConversionFacts.IsSpanTypeName("Span<int>")
    assert !AnalyzerConversionFacts.IsSpanTypeName("Spans")
    assert !AnalyzerConversionFacts.IsSpanTypeName("ReadOnlySpanX")
    assert !AnalyzerConversionFacts.IsSpanTypeName("System.ReadOnlySpans")
    assert !AnalyzerConversionFacts.IsSpanTypeName("")

    // The memory family is a different shape and gets no array conversion here.
    assert !AnalyzerConversionFacts.IsSpanTypeName("Memory")
    assert !AnalyzerConversionFacts.IsSpanTypeName("ReadOnlyMemory")
    assert !AnalyzerConversionFacts.IsSpanTypeName("System.Memory")
    assert !AnalyzerConversionFacts.IsSpanTypeName("List")
}

// ── "definitely a non-nullable value type" ──────────────────────────────────────────────────────
//
// A POSITIVE predicate, and the reason it exists is that `!IsReferenceType(x)` is a DIFFERENT
// question. That one answers false for a bare type parameter, a constructed generic, an unknown type
// and everything its tail does not name, so negating it would let a caller REPORT on shapes it knows
// nothing about. The caller here is the null-comparison rule, which accuses source of a mistake, so
// the negatives below are the load-bearing half of this contract.

test "the primitive value-type names answer TRUE, and the three non-types beside them do not" {
    valueNames := ConversionSourceNames()
    index := 0
    while index < valueNames.Length {
        if !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new SimpleTypeInfo(valueNames[index])) {
            throw new InvalidOperationException("'" + valueNames[index] + "' must answer TRUE.")
        }

        index += 1
    }

    assert AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new SimpleTypeInfo("bool"))
    assert AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new SimpleTypeInfo("decimal"))

    // `void`, `null` and `never` are not types a value can have, and comparing one to null is a
    // different nonsense — reporting on them here would cascade off some other mistake.
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new SimpleTypeInfo("void"))
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new SimpleTypeInfo("null"))
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new SimpleTypeInfo("never"))
}

test "A BARE TYPE PARAMETER ANSWERS FALSE, which is the negative the whole predicate exists for" {
    // `T` reaches the analyzer as a `SimpleTypeInfo` named `T`, and `T` may be instantiated with a
    // class — so `value == null` inside `func F<T>(value: T)` must never be accused.
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new SimpleTypeInfo("T"))
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new SimpleTypeInfo("TResult"))

    // ...and `!IsReferenceType` would have said the opposite for it, which is the whole point.
    assert AnalyzerConversionFacts.IsReferenceType(new SimpleTypeInfo("T"))
}

test "a struct, an enum and a record STRUCT answer TRUE; a class, an interface, an array and a record CLASS do not" {
    assert AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionStructType())
    assert AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionEnumType())
    assert AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionRecordType(true))

    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionRecordType(false))
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionClassType())
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionInterfaceType())
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new ArrayTypeInfo(BuiltInTypes.Int))
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionFunctionType())
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionUnionType())
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(ConversionAnonymousUnionType())
}

test "a NULLABLE answers FALSE however it is modelled — as `T?` and as a reflected generic" {
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new NullableTypeInfo(new SimpleTypeInfo("int")))
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new NullableTypeInfo(ConversionStructType()))

    // A reflected `Nullable<int>` is a value type to the CLR, which is exactly why the reflected arm
    // refuses every GENERIC type rather than asking `IsValueType` alone.
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new ReflectionTypeInfo(typeof(int?)))
}

test "a reflected type answers by the CLR, and a reflected GENERIC PARAMETER answers FALSE" {
    assert AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new ReflectionTypeInfo(typeof(int)))
    assert AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new ReflectionTypeInfo(typeof(DateTime)))
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new ReflectionTypeInfo(typeof(string)))
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new ReflectionTypeInfo(typeof(object)))

    // A constructed generic is refused whether its arguments are value types or not.
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(new ReflectionTypeInfo(typeof(List<int>)))
}

test "an UNKNOWN type answers FALSE, so a rule built on this cannot accuse source the analyzer failed to resolve" {
    assert !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(BuiltInTypes.Unknown)
}

// ── DEFINITELY A REFERENCE TYPE ───────────────────────────────────────────
//
// The POSITIVE mirror, and the reason it is not `!IsDefinitelyNonNullableValueType`: that predicate
// names the value kinds it is sure about and answers false for everything else, including
// `List<int>` — so negating it would call every constructed generic a reference type, `int?`
// included. This one follows a constructed generic to its DEFINITION and answers from there.

test "the shapes that are always reference types answer TRUE" {
    assert AnalyzerConversionFacts.IsDefinitelyReferenceType(new SimpleTypeInfo("string"))
    assert AnalyzerConversionFacts.IsDefinitelyReferenceType(new SimpleTypeInfo("object"))
    assert AnalyzerConversionFacts.IsDefinitelyReferenceType(ConversionClassType())
    assert AnalyzerConversionFacts.IsDefinitelyReferenceType(ConversionInterfaceType())
    assert AnalyzerConversionFacts.IsDefinitelyReferenceType(new ArrayTypeInfo(BuiltInTypes.Int))
    assert AnalyzerConversionFacts.IsDefinitelyReferenceType(ConversionRecordType(false))
}

test "every VALUE shape answers FALSE, and so does a nullable of one" {
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(BuiltInTypes.Int)
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(BuiltInTypes.Bool)
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(ConversionStructType())
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(ConversionEnumType())
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(ConversionRecordType(true))
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(new NullableTypeInfo(BuiltInTypes.Int))
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(new NullableTypeInfo(new SimpleTypeInfo("string")))
}

test "a BARE TYPE PARAMETER and an UNKNOWN answer FALSE — the predicate reports only what it is sure of" {
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(new SimpleTypeInfo("T"))
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(BuiltInTypes.Unknown)
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(new SimpleTypeInfo("Widgetry"))
}

test "a CONSTRUCTED GENERIC is answered by its DEFINITION" {
    classArguments := new List<TypeInfo>()
    classArguments.Add(BuiltInTypes.Int)
    referenceGeneric := new GenericTypeInfo("Box", classArguments, ConversionClassType())
    valueGeneric := new GenericTypeInfo("Pair", classArguments, ConversionStructType())
    unknownGeneric := new GenericTypeInfo("Box", classArguments)

    assert AnalyzerConversionFacts.IsDefinitelyReferenceType(referenceGeneric)
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(valueGeneric)
    assert !AnalyzerConversionFacts.IsDefinitelyReferenceType(unknownGeneric)
}

// ── the nullable lift between two inference bounds ────────────────────────────────────────────
test "the CLR half of the lift relation holds exactly one way" {
    assert AnalyzerConversionFacts.IsNullableLiftOf(typeof(int?), typeof(int))
    assert !AnalyzerConversionFacts.IsNullableLiftOf(typeof(int), typeof(int?))
    assert !AnalyzerConversionFacts.IsNullableLiftOf(typeof(long?), typeof(int))
    assert !AnalyzerConversionFacts.IsNullableLiftOf(typeof(string), typeof(string))
}

test "the N# half lifts a reference annotation the CLR cannot see" {
    // `string` and `string?` are one CLR type, so only this half has anything to widen.
    assert AnalyzerConversionFacts.IsNullableLiftOfTypeInfo(new NullableTypeInfo(BuiltInTypes.String), BuiltInTypes.String)
    assert !AnalyzerConversionFacts.IsNullableLiftOfTypeInfo(BuiltInTypes.String, new NullableTypeInfo(BuiltInTypes.String))
}

test "two bounds that are already the same, or that differ by more than the lift, are not a lift" {
    assert !AnalyzerConversionFacts.IsNullableLiftOfTypeInfo(BuiltInTypes.Int, BuiltInTypes.Int)
    assert !AnalyzerConversionFacts.IsNullableLiftOfTypeInfo(new NullableTypeInfo(BuiltInTypes.Int), new NullableTypeInfo(BuiltInTypes.Int))
    assert !AnalyzerConversionFacts.IsNullableLiftOfTypeInfo(new NullableTypeInfo(BuiltInTypes.Long), BuiltInTypes.Int)
    assert !AnalyzerConversionFacts.IsNullableLiftOfTypeInfo(new NullableTypeInfo(BuiltInTypes.String), new SimpleTypeInfo("Widgetry"))
}
