namespace NSharpLang.Compiler

import System


// THE RULE AN ANNOTATED LOOP VARIABLE ANSWERS TO — `for m: Match in matches`.
//
// C# asks ONE question of `foreach (T x in e)` (ECMA-334 §13.9.5): is there an EXPLICIT conversion
// from the sequence's element type to `T`? It is deliberately weaker than assignment. The loop is
// the place where a sequence typed by its oldest interface — a non-generic `IEnumerable`, whose
// element is `object` — is read at the type its elements actually have, so the DOWNCAST is the
// point of writing the annotation, and refusing it would refuse the only reason the form exists.
//
// THE SET OF EXPLICIT CONVERSIONS IS THE SET OF IMPLICIT ONES PLUS FOUR MORE (§10.3), and this is
// stated as those five questions rather than as a table of pairs:
//
//   1. an IMPLICIT conversion element -> declared. Identity, a numeric widening, a reference upcast
//      and a boxing conversion all arrive here, and the ordinary assignability oracle answers them —
//      the same oracle every assignment and every argument already consults, so the loop inherits
//      exactly one definition of "converts", not a second one written beside it.
//   2. an implicit conversion in the OTHER direction, declared -> element. Every explicit REFERENCE
//      conversion and every UNBOXING conversion is the reverse of an implicit one, so asking the
//      same oracle backwards is what identifies a downcast (`object` -> `Match`) and an unboxing
//      (`object` -> `int`) without a second classification.
//   3. both sides NUMERIC. Every pair of the built-in numeric types converts explicitly, so a
//      narrowing (`long` -> `int`) that neither direction of (1) or (2) admits is admitted here.
//   4. an ENUM with a numeric or another enum on the other side — the enum conversions, which are
//      the numeric ones over the underlying type.
//   5. an INTERFACE on either side. A conversion to or from an interface type is explicit for any
//      type that is not sealed against it, and the analyzer cannot see sealedness for every source
//      of a type, so the interface case is admitted rather than guessed at. Accepting a conversion
//      the runtime will refuse costs an `InvalidCastException` the author asked for by writing the
//      annotation; REFUSING one that is legal would refuse a correct program, and only the second
//      is a compiler bug.
//
// A TYPE NOTHING COULD NAME IS SILENT. An `unknown` on either side means an earlier diagnostic has
// already fired, and an external type the analyzer holds only by NAME carries no relation at all —
// measuring against either would produce a sentence about types the author cannot act on.
class ForeachElementConversionFacts {

    // WHETHER THE ELEMENT CAN REACH THE ANNOTATION AT ALL. `false` is the one answer that reports.
    static func IsConvertible(elementType: TypeInfo, declaredType: TypeInfo, assignability: AnalyzerAssignability): bool {
        if IsSilent(elementType) || IsSilent(declaredType) {
            return true
        }

        if assignability.IsAssignable(declaredType, elementType) {
            return true
        }

        if assignability.IsAssignable(elementType, declaredType) {
            return true
        }

        if IsNumericOrEnum(elementType) && IsNumericOrEnum(declaredType) {
            return true
        }

        return MentionsInterface(elementType) || MentionsInterface(declaredType)
    }

    // A TYPE THE RULE REFUSES TO MEASURE. `unknown` in either of its three flavours is a type an
    // earlier report already collapsed; an `ExternalTypeInfo` is a bare NAME with no members, no
    // base and no interfaces, so every relation it takes part in would be answered "no" for want of
    // information rather than because the conversion is impossible.
    static func IsSilent(candidate: TypeInfo): bool {
        if candidate == null {
            return true
        }

        if (candidate as UnknownTypeInfo) != null {
            return true
        }

        return (candidate as ExternalTypeInfo) != null
    }

    // A BUILT-IN NUMERIC TYPE OR AN ENUM OVER ONE. `bool`, `string`, `object` and `char`'s
    // non-numeric neighbours answer false; `char` itself is numeric, exactly as the CLR's conversion
    // table has it.
    static func IsNumericOrEnum(candidate: TypeInfo): bool {
        if (candidate as EnumTypeInfo) != null {
            return true
        }

        reflection := candidate as ReflectionTypeInfo
        if reflection != null {
            if reflection.Type.get_IsEnum() {
                return true
            }

            return AnalyzerConversionFacts.ClrNumericCode(AnalyzerConversionFacts.NumericTypeFullName(reflection.Type)) != NumericConversionKind.None
        }

        simple := candidate as SimpleTypeInfo
        if simple == null {
            return false
        }

        return AnalyzerConversionFacts.SourceNumericCode(simple.Name) != NumericConversionKind.None
    }

    // WHETHER THE TYPE IS AN INTERFACE — declared in source, or bound through reflection.
    static func MentionsInterface(candidate: TypeInfo): bool {
        if (candidate as InterfaceTypeInfo) != null {
            return true
        }

        reflection := candidate as ReflectionTypeInfo
        if reflection != null {
            return reflection.Type.get_IsInterface()
        }

        generic := candidate as GenericTypeInfo
        if generic != null {
            definition := generic.GenericDefinition
            if definition != null {
                return MentionsInterface(definition)
            }
        }

        return false
    }
}
