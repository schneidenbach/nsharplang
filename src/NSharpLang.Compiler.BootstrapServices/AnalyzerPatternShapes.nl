namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// The two SHAPE questions a pattern asks about the value it is matched against — "does this value
// have a list shape, and what does one element of it hold?" and "can these two values be COMPARED
// before IL emission?" — together with the single diagnostic each one produces when the answer is
// no.
//
// Both are pure functions of a TYPE. Neither declares a symbol, re-enters the pattern walk, or reads
// a scope; they sit one layer below `AnalyzePattern`, which is what lets them move ahead of it.
//
// THE LIST QUESTION IS ABOUT LOWERING, NOT ABOUT ITERATION. A list pattern lowers to a length read
// and a sequence of int-indexed reads, so the shape it demands is a stable `Count`/`Length` of type
// `int` PLUS an int indexer — not `IEnumerable<T>`. That is why `[first]` over an `IEnumerable<int>`
// is rejected while the same pattern over an `IReadOnlyList<int>` is accepted, and it is the whole
// content of NL505 on this path.
//
// THE THREE SOURCES OF A LIST SHAPE ARE ASKED IN ORDER AND THEY ARE NOT INTERCHANGEABLE. An ARRAY
// answers its own element type. A GENERIC instantiation answers its first type argument, but only
// for the three names the lowering knows how to index — `List`, `IList`, `IReadOnlyList` — because
// the name test is what stands in for "this instantiation has an int indexer". A REFLECTED type is
// asked its metadata directly, and an interface is asked about its INHERITED interfaces too, because
// `IReadOnlyList<T>`'s own metadata carries the indexer while its `Count` comes from
// `IReadOnlyCollection<T>`.
//
// THE INT IDENTITY TESTS ARE `typeof(int)` REFERENCE TESTS, DELIBERATELY AND MEASURABLY. Everywhere
// else in the analyzer's reflection estate a primitive is recognised by `FullName`, because the
// analyzer reads most metadata through a `MetadataLoadContext` where the projected `System.Int32` is
// not `typeof(int)`. Here the reference test is PRESERVED because it is the behaviour: the two
// spellings were measured against each other on every reachable input (see the slice-26 record) and
// they agree, since the reflected conversion maps every primitive to a `BuiltInTypes` simple type
// before a `ReflectionTypeInfo` can carry one. Swapping in a name test would be a behaviour CHANGE
// dressed as a cleanup, and it belongs to a slice that can prove it.
//
// THE COMPARABILITY QUESTION HAS FOUR INDEPENDENT WAYS TO SAY NO, and their ORDER is not observable
// because they are OR-ed into one report — but their CONTENT is. A relational pattern is rejected
// when either side is nullable, when either side is not an ordered primitive, or when the pattern's
// value is not assignable to the scrutinee. `decimal` is excluded ON PURPOSE even though it is
// numeric — the lowering has no decimal comparison — and `bool` is admitted ONLY under `==` and
// `!=`, which is what `allowBool` carries. An UNKNOWN on either side returns before any of that, so
// a pattern whose value failed to analyse reports once, not twice.
public class AnalyzerPatternShapes {

    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    declarationContextValue: AnalyzerDeclarationContext
    assignabilityValue: AnalyzerAssignability

    constructor(
        diagnostics: AnalyzerDiagnosticSink,
        spans: AnalyzerDiagnosticSpans,
        declarationContext: AnalyzerDeclarationContext,
        assignability: AnalyzerAssignability) {
        diagnosticsValue = diagnostics
        spansValue = spans
        declarationContextValue = declarationContext
        assignabilityValue = assignability
    }

    // THE LIST PATTERN'S ELEMENT TYPE, reported and total. A value with no list shape reports NL505
    // and answers `unknown` rather than failing, so the element patterns are still analysed and a
    // single bad scrutinee does not cascade into one report per element.
    public func ResolveListPatternElementType(listPattern: ListPattern, valueType: TypeInfo): TypeInfo {
        elementType := FindListPatternElementType(valueType)
        if elementType != null {
            return elementType
        }

        valueObject := valueType as object
        span := spansValue.GetListPatternDiagnosticSpan(listPattern)
        diagnosticsValue.Report(
            ErrorCode.PatternTypeMismatch,
            "A list pattern can only match arrays or indexable collections, but this value is '"
                + valueObject.ToString() + "'",
            span.Line,
            span.Column,
            null,
            span.Length)
        return BuiltInTypes.Unknown
    }

    // The element type a list-shaped value holds, or null when the value has no list shape at all.
    public func FindListPatternElementType(valueType: TypeInfo): TypeInfo? {
        resolved := declarationContextValue.ResolveDeclaredAlias(valueType)

        arrayType := resolved as ArrayTypeInfo
        if arrayType != null {
            return arrayType.ElementType
        }

        genericType := resolved as GenericTypeInfo
        if genericType != null && IsIndexableGenericListPatternType(genericType.Name) {
            if genericType.TypeArguments.Count > 0 {
                return genericType.TypeArguments[0]
            }

            unknown: TypeInfo = BuiltInTypes.Unknown
            return unknown
        }

        reflectionType := resolved as ReflectionTypeInfo
        if reflectionType != null {
            return FindReflectionListPatternElementType(reflectionType.Type)
        }

        return null
    }

    // The three instantiations whose lowering knows an int indexer.
    public static func IsIndexableGenericListPatternType(name: string): bool {
        return name == "List" || name == "IList" || name == "IReadOnlyList"
    }

    // The reflected shape probe: an int-typed `Count` or `Length` with a getter, AND an indexer
    // taking exactly one `int`. Both are searched across the type itself and — for an interface —
    // its inherited interfaces, because the two members are declared on different interfaces of the
    // same family.
    public static func FindReflectionListPatternElementType(clrType: Type): TypeInfo? {
        if clrType.get_IsArray() {
            arrayElementType := clrType.GetElementType()
            if arrayElementType == null {
                return null
            }

            reflectedElement: TypeInfo = new ReflectionTypeInfo(arrayElementType)
            return reflectedElement
        }

        bindingFlags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        shapeTypes := GetListPatternShapeTypes(clrType)

        if !HasReflectionListLengthProperty(shapeTypes, bindingFlags) {
            return null
        }

        indexerProperty := FindReflectionListIndexerProperty(shapeTypes, bindingFlags)
        if indexerProperty == null {
            return null
        }

        elementType: TypeInfo = new ReflectionTypeInfo(indexerProperty.get_PropertyType())
        return elementType
    }

    // The FIRST shape type whose `Count` — or, failing that, `Length` — is a readable `int`. A shape
    // type that declares neither contributes nothing and the walk moves on; it does not fail.
    static func HasReflectionListLengthProperty(shapeTypes: List<Type>, bindingFlags: BindingFlags): bool {
        index := 0
        while index < shapeTypes.Count {
            shapeType := shapeTypes[index]
            lengthProperty := shapeType.GetProperty("Count", bindingFlags)
            if lengthProperty == null {
                lengthProperty = shapeType.GetProperty("Length", bindingFlags)
            }

            if lengthProperty != null
                && lengthProperty.get_GetMethod() != null
                && lengthProperty.get_PropertyType() == typeof(int) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The FIRST readable single-`int`-parameter indexer over the shape types, in declaration order
    // within each type and shape order across them.
    static func FindReflectionListIndexerProperty(
        shapeTypes: List<Type>,
        bindingFlags: BindingFlags): PropertyInfo? {
        index := 0
        while index < shapeTypes.Count {
            shapeType := shapeTypes[index]
            properties := shapeType.GetProperties(bindingFlags)
            propertyIndex := 0
            while propertyIndex < properties.Length {
                property := properties[propertyIndex]
                if property.get_GetMethod() != null {
                    parameters := property.GetIndexParameters()
                    if parameters.Length == 1 {
                        indexParameter := parameters[0]
                        if indexParameter.get_ParameterType() == typeof(int) {
                            return property
                        }
                    }
                }

                propertyIndex = propertyIndex + 1
            }

            index = index + 1
        }

        return null
    }

    // The type itself, plus — for an INTERFACE only — every interface it inherits. A class already
    // exposes its base members through its own metadata; an interface does not.
    public static func GetListPatternShapeTypes(clrType: Type): List<Type> {
        shapeTypes := new List<Type>()
        shapeTypes.Add(clrType)

        if !clrType.get_IsInterface() {
            return shapeTypes
        }

        inheritedInterfaces := clrType.GetInterfaces()
        index := 0
        while index < inheritedInterfaces.Length {
            shapeTypes.Add(inheritedInterfaces[index])
            index = index + 1
        }

        return shapeTypes
    }

    // THE RELATIONAL PATTERN'S ONE JUDGEMENT. Asked with the scrutinee's type and the type of the
    // pattern's own value expression, after the SoA escape gates have declined to report.
    public func ValidateRelationalPattern(
        pattern: RelationalPattern,
        valueType: TypeInfo,
        patternValueType: TypeInfo) {
        resolvedValueType := declarationContextValue.ResolveDeclaredAlias(GetNonNullableType(valueType))
        resolvedPatternValueType := declarationContextValue.ResolveDeclaredAlias(
            GetNonNullableType(patternValueType))
        if BuiltInTypes.IsUnknown(resolvedValueType) || BuiltInTypes.IsUnknown(resolvedPatternValueType) {
            return
        }

        allowBool := IsEqualityPatternOperator(pattern.Operator)
        if IsNullableRelationalPatternType(valueType)
            || IsNullableRelationalPatternType(patternValueType)
            || !IsRelationalPatternComparableType(resolvedValueType, allowBool)
            || !IsRelationalPatternComparableType(resolvedPatternValueType, allowBool)
            || !assignabilityValue.IsAssignable(valueType, patternValueType) {
            ReportRelationalPatternTypeMismatch(pattern, valueType, patternValueType)
        }
    }

    // `==` and `!=` are the only two operators a `bool` can take part in.
    public static func IsEqualityPatternOperator(operatorText: string): bool {
        return operatorText == "==" || operatorText == "!="
    }

    // Nullable on EITHER spelling: the N# `T?` and a reflected `System.Nullable<T>`.
    public func IsNullableRelationalPatternType(candidate: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return true
        }

        reflection := resolved as ReflectionTypeInfo
        if reflection != null {
            return Nullable.GetUnderlyingType(reflection.Type) != null
        }

        return false
    }

    // The ordered primitives, in both vocabularies. `decimal` is excluded from BOTH arms because the
    // lowering has no decimal comparison, and `bool` is admitted only under equality.
    public func IsRelationalPatternComparableType(candidate: TypeInfo, allowBool: bool): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(GetNonNullableType(candidate))
        if allowBool && BuiltInTypes.Is(resolved, BuiltInTypes.Bool) {
            return true
        }

        if BuiltInTypes.Is(resolved, BuiltInTypes.Decimal) {
            return false
        }

        if IsSimpleNumericPatternType(resolved) {
            return true
        }

        reflection := resolved as ReflectionTypeInfo
        if reflection != null {
            runtimeType := Nullable.GetUnderlyingType(reflection.Type)
            if runtimeType == null {
                runtimeType = reflection.Type
            }

            if allowBool && runtimeType == typeof(bool) {
                return true
            }

            if runtimeType == typeof(decimal) {
                return false
            }

            return runtimeType == typeof(byte)
                || runtimeType == typeof(sbyte)
                || runtimeType == typeof(short)
                || runtimeType == typeof(ushort)
                || runtimeType == typeof(int)
                || runtimeType == typeof(uint)
                || runtimeType == typeof(long)
                || runtimeType == typeof(ulong)
                || runtimeType == typeof(float)
                || runtimeType == typeof(double)
                || runtimeType == typeof(char)
        }

        return false
    }

    // The analyzer's numeric-simple-type test, which INCLUDES `decimal` — the caller has already
    // excluded it, and the inclusion is what makes `decimal` reach the exclusion rather than fall
    // through to the reflected arm.
    static func IsSimpleNumericPatternType(candidate: TypeInfo): bool {
        return BuiltInTypes.Is(candidate, BuiltInTypes.Int)
            || BuiltInTypes.Is(candidate, BuiltInTypes.Long)
            || BuiltInTypes.Is(candidate, BuiltInTypes.Float)
            || BuiltInTypes.Is(candidate, BuiltInTypes.Double)
            || BuiltInTypes.Is(candidate, BuiltInTypes.Decimal)
            || BuiltInTypes.Is(candidate, BuiltInTypes.Byte)
            || BuiltInTypes.Is(candidate, BuiltInTypes.SByte)
            || BuiltInTypes.Is(candidate, BuiltInTypes.Short)
            || BuiltInTypes.Is(candidate, BuiltInTypes.UShort)
            || BuiltInTypes.Is(candidate, BuiltInTypes.UInt)
            || BuiltInTypes.Is(candidate, BuiltInTypes.ULong)
            || BuiltInTypes.Is(candidate, BuiltInTypes.Char)
    }

    // The alias-resolving non-nullable projection the analyzer uses everywhere: an alias that
    // resolves to `T?` answers `T`, and anything else answers ITSELF — the ORIGINAL spelling, not
    // the resolved one, which is what keeps the diagnostic's rendering unchanged.
    func GetNonNullableType(candidate: TypeInfo): TypeInfo {
        nullable := declarationContextValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
    }

    // NL202 with the relational vocabulary. The span is the OPERATOR, which is the only token the
    // pattern owns that is always written.
    func ReportRelationalPatternTypeMismatch(
        pattern: RelationalPattern,
        valueType: TypeInfo,
        patternValueType: TypeInfo) {
        valueObject := valueType as object
        patternValueObject := patternValueType as object
        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            "Relational pattern '" + pattern.Operator + "' can't compare '" + valueObject.ToString()
                + "' with '" + patternValueObject.ToString() + "' before IL emission",
            pattern.Line,
            pattern.Column,
            "Use numeric operands with a supported common type, use a literal pattern for string equality, or move custom comparisons into a match guard.",
            Math.Max(1, pattern.Operator.Length))
    }
}
