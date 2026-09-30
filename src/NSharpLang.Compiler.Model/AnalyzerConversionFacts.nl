namespace NSharpLang.Compiler

import System


// The analyzer's conversion/assignability CLASSIFICATION TABLES.
//
// These are the leaf policies the assignability decision consults: the CLR implicit
// numeric-widening table, the reference-vs-value classification that decides whether `null` is
// assignable to a target, and the MetadataLoadContext-safe reflection assignability walk. They are
// exact, total functions of their inputs — no analyzer state, no diagnostics, no recovery.
//
// The numeric table is stated ONCE, over an internal widening code, and reached through two
// vocabularies: N# simple type names (`byte`, `sbyte`, ...) for source-declared TypeInfo values and
// CLR full names (`System.Byte`, ...) for reflection-bound values. Each vocabulary maps only its own
// spellings, so a reflection-spelled name never satisfies the source table and vice versa.

// The participating built-in numeric types, in widening order. `None` is every type that takes no
// part in an implicit numeric conversion in either direction.
enum NumericConversionKind {
    None,
    Byte,
    SByte,
    Short,
    UShort,
    Int,
    UInt,
    Long,
    ULong,
    Char,
    Float,
    Double,
    Decimal
}

class AnalyzerConversionFacts {

    // CLR implicit numeric conversion over analyzer TypeInfo values. Only the built-in simple types
    // participate; identical names are NOT a conversion (the caller answers identity first).
    static func IsImplicitNumericConversion(source: TypeInfo, target: TypeInfo): bool {
        sourceSimple := source as SimpleTypeInfo
        targetSimple := target as SimpleTypeInfo
        if sourceSimple == null || targetSimple == null {
            return false
        }

        return IsNumericWidening(SourceNumericCode(sourceSimple.Name), SourceNumericCode(targetSimple.Name))
    }

    // CLR implicit numeric conversion over reflection types. Identical reflection types short-circuit
    // to true, and a Nullable<T> is read through to T on both sides before the table is consulted.
    static func IsImplicitNumericReflectionConversion(sourceType: Type, targetType: Type): bool {
        if sourceType == targetType {
            return true
        }

        return IsNumericWidening(ClrNumericCode(NumericTypeFullName(sourceType)), ClrNumericCode(NumericTypeFullName(targetType)))
    }

    // Returns true when the type is a reference type — that is, when `null` is one of its values.
    // Numeric primitives, bool, char, structs, record structs, enums and byref types are value types.
    //
    // A CLOSED GENERIC INSTANTIATION ANSWERS FROM ITS DEFINITION, NOT FROM ITS SHAPE. This owner used
    // to answer FALSE for every `GenericTypeInfo`, which made `IReadOnlyDictionary<string, string>`
    // and `List<string>` value types as far as the `null` arm of assignability was concerned — so a
    // `null` argument was refused by a reflected `IReadOnlyDictionary<string, string>?` parameter with
    // "No overload accepts 3 arguments with these types", while a bare `string` parameter took one.
    // `List<T>` is a class and `Nullable<T>` is a struct, and the only thing that knows which is the
    // DEFINITION, so that is what is asked. An instantiation that carries no definition keeps the old
    // conservative answer: it is a name the analyzer has not resolved, not a decision.
    //
    // AN OBLIVIOUS SHELL IS AN ANNOTATION, NOT A TYPE. Metadata written without a nullable context
    // reads back as `string![]!` / `IReadOnlyDictionary<string!, string!>!`, and C#'s own rule is that
    // an oblivious reference position ADMITS null. The shell is therefore transparent here, exactly as
    // it is to identity and to variance.
    static func IsReferenceType(candidate: TypeInfo): bool {
        obliviousType := candidate as ObliviousTypeInfo
        if obliviousType != null {
            return IsReferenceType(obliviousType.InnerType)
        }

        simple := candidate as SimpleTypeInfo
        if simple != null {
            name := simple.Name
            if name == "int" || name == "long" || name == "float" || name == "double" || name == "decimal" || name == "byte" || name == "sbyte" || name == "short" || name == "ushort" || name == "uint" || name == "ulong" || name == "char" || name == "bool" || name == "void" || name == "null" || name == "never" {
                return false
            }

            return true
        }

        classType := candidate as ClassTypeInfo
        interfaceType := candidate as InterfaceTypeInfo
        arrayType := candidate as ArrayTypeInfo
        functionType := candidate as FunctionTypeInfo
        unionType := candidate as UnionTypeInfo
        anonymousUnionType := candidate as AnonymousUnionTypeInfo
        if classType != null || interfaceType != null || arrayType != null || functionType != null || unionType != null || anonymousUnionType != null {
            return true
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return !recordType.IsStruct
        }

        structType := candidate as StructTypeInfo
        enumType := candidate as EnumTypeInfo
        byRefType := candidate as ByRefTypeInfo
        if structType != null || enumType != null || byRefType != null {
            return false
        }

        genericType := candidate as GenericTypeInfo
        if genericType != null {
            genericDefinition := genericType.GenericDefinition
            if genericDefinition == null {
                return false
            }

            return IsReferenceType(genericDefinition)
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            return !reflectionType.Type.IsValueType
        }

        return false
    }

    // IS `null` ONE OF THIS TYPE'S VALUES? A nullable annotation says so outright, and every reference
    // type says so by construction. This is the rule the null arm of `IsAssignable` applies, named so
    // that a position which has to decide the same thing without an assignability owner in hand —
    // target-typing a `null` tuple element, say — asks the same question rather than a similar one.
    static func AcceptsNull(candidate: TypeInfo): bool {
        if (candidate as NullableTypeInfo) != null {
            return true
        }

        return IsReferenceType(candidate)
    }

    // DEFINITELY A NON-NULLABLE VALUE TYPE — a POSITIVE test, and that is the whole point of it.
    //
    // `!IsReferenceType(x)` is NOT this question. That predicate answers FALSE for a bare type
    // parameter (a `SimpleTypeInfo` named `T`, which may be instantiated with a class), for a
    // constructed generic, for an unknown type and for everything its tail does not name — so
    // negating it would accuse code that is correct. This one names the kinds it is sure about and
    // answers false for every other shape, which is what lets a caller REPORT on the strength of it.
    //
    // Deliberately NOT in the set: `void`, `null` and `never` (comparing one to null is a different
    // nonsense and reporting here would cascade), tuples and SoA rows (their equality is its own
    // question), by-refs, and any reflected GENERIC type — which is how `Nullable<T>` stays out
    // whichever way the analyzer happened to model it.
    static func IsDefinitelyNonNullableValueType(candidate: TypeInfo): bool {
        simple := candidate as SimpleTypeInfo
        if simple != null {
            name := simple.Name
            return name == "int" || name == "long" || name == "float" || name == "double" || name == "decimal" || name == "byte" || name == "sbyte" || name == "short" || name == "ushort" || name == "uint" || name == "ulong" || name == "char" || name == "bool"
        }

        if (candidate as StructTypeInfo) != null {
            return true
        }

        if (candidate as EnumTypeInfo) != null {
            return true
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return recordType.IsStruct
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            clrType := reflectionType.Type
            if clrType.IsGenericParameter || clrType.IsGenericType {
                return false
            }

            return clrType.IsValueType
        }

        return false
    }

    // DEFINITELY A REFERENCE TYPE — the POSITIVE mirror of the test above, and a positive test for the
    // same reason: a caller REPORTS on the strength of it.
    //
    // `!IsDefinitelyNonNullableValueType(x)` is not this question either. That one answers false for a
    // constructed generic (`List<int>` is a class, `KeyValuePair<int, int>` is a struct, and it names
    // neither) and for everything its tail does not reach, so negating it would accuse a struct field
    // of failing a rule only reference fields have. This one follows a constructed generic to its
    // DEFINITION and answers from there, and answers FALSE for a bare type parameter, for `unknown`,
    // and for every shape it cannot place — which is what makes it safe to report on.
    static func IsDefinitelyReferenceType(candidate: TypeInfo): bool {
        simple := candidate as SimpleTypeInfo
        if simple != null {
            name := simple.Name
            return name == "string" || name == "object"
        }

        if (candidate as ClassTypeInfo) != null {
            return true
        }

        if (candidate as InterfaceTypeInfo) != null {
            return true
        }

        if (candidate as ArrayTypeInfo) != null {
            return true
        }

        if (candidate as FunctionTypeInfo) != null {
            return true
        }

        if (candidate as UnionTypeInfo) != null {
            return true
        }

        if (candidate as AnonymousUnionTypeInfo) != null {
            return true
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return !recordType.IsStruct
        }

        genericType := candidate as GenericTypeInfo
        if genericType != null {
            definition := genericType.GenericDefinition
            return definition != null && IsDefinitelyReferenceType(definition)
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            clrType := reflectionType.Type
            if clrType.IsGenericParameter {
                return false
            }

            return !clrType.IsValueType
        }

        return false
    }

    // The Span family by name, in every spelling the analyzer sees. This gates the implicit
    // array-to-span conversion, so it belongs with the conversion tables rather than with the
    // callable/delegate facts. Note this is a STRICT SUPERSET of the loop-sequence owner's
    // same-named file-private helper, which deliberately matches only the unqualified spellings.
    static func IsSpanTypeName(name: string): bool {
        return name == "Span" || name == "ReadOnlySpan" || name == "System.Span" || name == "System.ReadOnlySpan"
    }

    // TWO INFERENCE BOUNDS FOR ONE TYPE PARAMETER THAT DIFFER ONLY BY THE NULLABLE LIFT.
    //
    // C# fixes a method type parameter to the one bound every other bound converts to, and `X` and
    // `X?` are exactly that pair: `X` converts to `X?` and `X?` does not convert back. So
    // `Assert.Equal(severity, maybeSeverity)` infers `T = X?` rather than refusing the call because
    // its two arguments disagreed. The relation is stated over `Nullable<T>`'s METADATA name, for
    // the same reason `NullableUnderlyingTypeOrNull` is: the analyzer's types come from a
    // MetadataLoadContext whose `System.Nullable´1` is not the runtime's.
    //
    // This is the CLR half of the rule; `TypeInfo` bounds answer the same question in their own
    // spelling, so the two maps that record one inference widen together.
    static func IsNullableLiftOf(candidate: Type, inner: Type): bool {
        underlying := ExternalUserDefinedConversions.NullableUnderlyingTypeOrNull(candidate)
        if underlying == null {
            return false
        }

        return TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(underlying, inner)
    }

    // The same pair in the N# spelling. `X?` over a value type is `Nullable<X>` and over a reference
    // type is the annotation, and both are one `NullableTypeInfo` here — which is why this half of
    // the rule also lifts `string`/`string?` to `string?`, where the CLR half has nothing to widen
    // because the two are one CLR type.
    static func IsNullableLiftOfTypeInfo(candidate: TypeInfo, inner: TypeInfo): bool {
        lifted := candidate as NullableTypeInfo
        if lifted == null || inner as NullableTypeInfo != null {
            return false
        }

        return TypeInfoIdentityFacts.AreEqual(lifted.InnerType, inner)
    }

    // Assignability between two reflection types. `Type.IsAssignableFrom` alone is not sufficient
    // inside the analyzer's MetadataLoadContext: types loaded from different assembly identities are
    // not reference-equal, so the exact-identity comparison is applied to the source's interface list
    // and base chain as well.
    static func IsReflectionAssignableFrom(targetType: Type, sourceType: Type): bool {
        if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(targetType, sourceType) {
            return true
        }

        if targetType.IsAssignableFrom(sourceType) {
            return true
        }

        sourceInterfaces := sourceType.GetInterfaces()
        for sourceInterface in sourceInterfaces {
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(targetType, sourceInterface) {
                return true
            }
        }

        baseType := sourceType.BaseType
        while baseType != null {
            if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(targetType, baseType) {
                return true
            }

            baseType = baseType.BaseType
        }

        return false
    }

    // The widening table, stated once. Kinds are assigned by SourceNumericCode / ClrNumericCode;
    // `None` is every non-participating type and never widens in either direction.
    static func IsNumericWidening(sourceCode: NumericConversionKind, targetCode: NumericConversionKind): bool {
        if sourceCode == NumericConversionKind.None || targetCode == NumericConversionKind.None {
            return false
        }

        if sourceCode == NumericConversionKind.Byte {
            return targetCode == NumericConversionKind.Short || targetCode == NumericConversionKind.UShort || targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.UInt || targetCode == NumericConversionKind.Long || targetCode == NumericConversionKind.ULong || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.SByte {
            return targetCode == NumericConversionKind.Short || targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.Long || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Short {
            return targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.Long || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.UShort {
            return targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.UInt || targetCode == NumericConversionKind.Long || targetCode == NumericConversionKind.ULong || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Int {
            return targetCode == NumericConversionKind.Long || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.UInt {
            return targetCode == NumericConversionKind.Long || targetCode == NumericConversionKind.ULong || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Long || sourceCode == NumericConversionKind.ULong {
            return IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Char {
            return targetCode == NumericConversionKind.UShort || targetCode == NumericConversionKind.Int || targetCode == NumericConversionKind.UInt || targetCode == NumericConversionKind.Long || targetCode == NumericConversionKind.ULong || IsFloatingOrDecimalCode(targetCode)
        }

        if sourceCode == NumericConversionKind.Float {
            return targetCode == NumericConversionKind.Double
        }

        return false
    }

    static func IsFloatingOrDecimalCode(code: NumericConversionKind): bool {
        return code == NumericConversionKind.Float || code == NumericConversionKind.Double || code == NumericConversionKind.Decimal
    }

    // N# source spellings. Anything else — including CLR full names — is not a participant.
    static func SourceNumericCode(name: string): NumericConversionKind {
        if name == "byte" {
            return NumericConversionKind.Byte
        }
        if name == "sbyte" {
            return NumericConversionKind.SByte
        }
        if name == "short" {
            return NumericConversionKind.Short
        }
        if name == "ushort" {
            return NumericConversionKind.UShort
        }
        if name == "int" {
            return NumericConversionKind.Int
        }
        if name == "uint" {
            return NumericConversionKind.UInt
        }
        if name == "long" {
            return NumericConversionKind.Long
        }
        if name == "ulong" {
            return NumericConversionKind.ULong
        }
        if name == "char" {
            return NumericConversionKind.Char
        }
        if name == "float" {
            return NumericConversionKind.Float
        }
        if name == "double" {
            return NumericConversionKind.Double
        }
        if name == "decimal" {
            return NumericConversionKind.Decimal
        }
        return NumericConversionKind.None
    }

    // CLR full names. Anything else — including N# source spellings — is not a participant.
    static func ClrNumericCode(fullName: string?): NumericConversionKind {
        if fullName == null {
            return NumericConversionKind.None
        }
        if fullName == "System.Byte" {
            return NumericConversionKind.Byte
        }
        if fullName == "System.SByte" {
            return NumericConversionKind.SByte
        }
        if fullName == "System.Int16" {
            return NumericConversionKind.Short
        }
        if fullName == "System.UInt16" {
            return NumericConversionKind.UShort
        }
        if fullName == "System.Int32" {
            return NumericConversionKind.Int
        }
        if fullName == "System.UInt32" {
            return NumericConversionKind.UInt
        }
        if fullName == "System.Int64" {
            return NumericConversionKind.Long
        }
        if fullName == "System.UInt64" {
            return NumericConversionKind.ULong
        }
        if fullName == "System.Char" {
            return NumericConversionKind.Char
        }
        if fullName == "System.Single" {
            return NumericConversionKind.Float
        }
        if fullName == "System.Double" {
            return NumericConversionKind.Double
        }
        if fullName == "System.Decimal" {
            return NumericConversionKind.Decimal
        }
        return NumericConversionKind.None
    }

    static func NumericTypeFullName(candidate: Type): string? {
        underlyingType := Nullable.GetUnderlyingType(candidate)
        if underlyingType != null {
            return underlyingType.FullName
        }

        return candidate.FullName
    }
}
