namespace NSharpLang.Compiler

import System


// WHAT A `where` CLAUSE BECOMES IN METADATA, DECIDED ONCE FOR BOTH GENERIC-PARAMETER OWNERS.
//
// A generic METHOD and a generic TYPE carry the same three CLR facts on each of their parameters —
// an attribute word, at most one base-type constraint, and a set of interface constraints — and the
// rules for deriving them from a `where` clause are identical. They lived inline in the emitter's
// FUNCTION arm and nowhere else, which is why a `class Box<T> where T: struct` emitted a type
// parameter with `attrs=None`: the five `TypeBuilder.DefineGenericParameters` sites had no rules to
// apply. The rules are here now, and the emitter's one CLR helper reads them for all six sites.
class ColumnarGenericConstraintPlanner {

    // `GenericParameterAttributes` (ECMA-335 II.23.1.7), as integers because the emitter's own bits are
    // CLR-side: ReferenceTypeConstraint 4, NotNullableValueTypeConstraint 8, DefaultConstructorConstraint 16.
    static func ReferenceTypeConstraintBit(): int {
        return 4
    }

    static func NotNullableValueTypeConstraintBit(): int {
        return 8
    }

    static func DefaultConstructorConstraintBit(): int {
        return 16
    }

    // THE TWO BOUNDS GUARDS AT THE `where` SITE, AND WHY THEY ARE NOT BELT-AND-BRACES.
    //
    // `ColumnarConstraintColumns.SpecialsOrEmpty` / `TypesOrEmpty` are named as if they normalise, and
    // they DO -- but only for NULL. A non-null array SHORTER than the type-parameter count is returned
    // UNCHANGED, `typeParamCount` unused, so an owner declaring three parameters can reach emit with a
    // two-entry specials row. Reading it unguarded would throw on a shape the emitter accepts today,
    // which is the same class of trap as the field family's readonly flags. The guards are therefore
    // rules with contracts, not defensive noise at a call site.
    //
    // A parameter past the end has NO special constraint (0) and NO type constraints (an empty row) --
    // never a missing row the caller must test for.
    static func SpecialAt(specialRows: int[], index: int): int {
        if specialRows != null && index < specialRows.Length {
            return specialRows[index]
        }
        return 0
    }

    static func TypeConstraintsAt(typeConstraintRows: string[][], index: int): string[] {
        if typeConstraintRows != null && index < typeConstraintRows.Length {
            return typeConstraintRows[index]
        }
        return new string[](0)
    }

    // `SpecialConstraintKind` (Class 1, Struct 2, New 4) to the CLR's attribute word.
    //
    // `struct` IMPLIES the default-constructor bit and the `new()` bit is then redundant — every value
    // type has a parameterless constructor — which is what the CLR itself records and what the legacy
    // emitter set. The `else if` matters: `where T: struct, new()` must not set the ctor bit twice by
    // two routes and must not be refused for saying the same thing twice.
    static func AttributeBitsFor(special: int): int {
        bits := 0
        if (special & 1) != 0 {
            bits = bits | ReferenceTypeConstraintBit()
        }

        if (special & 2) != 0 {
            bits = bits | NotNullableValueTypeConstraintBit() | DefaultConstructorConstraintBit()
        } else if (special & 4) != 0 {
            bits = bits | DefaultConstructorConstraintBit()
        }

        return bits
    }

    // Whether a resolved constraint type is admissible as a BASE-TYPE constraint.
    //
    // The caller answers the four CLR questions (it holds the `Type`); this holds the rule. A type
    // PARAMETER is always admissible — `where T: U` is a real constraint. An emitted user type is
    // admissible only with REFERENCE layout, because a value struct cannot be a base. Everything else
    // must be a plain runtime class: an `AssemblyBuilder` shape (EnumBuilder, TypeBuilderInstantiation),
    // a value type, an array and a non-class are all unmodeled targets.
    static func IsAdmissibleBaseConstraint(isGenericParameter: bool, isTypeBuilder: bool, isValueType: bool, isFromAssemblyBuilder: bool, isSzArray: bool, isClass: bool): bool {
        if isGenericParameter {
            return true
        }

        if isTypeBuilder {
            return !isValueType
        }

        return !isFromAssemblyBuilder && !isValueType && !isSzArray && isClass
    }

    // WHAT ONE RESOLVED CONSTRAINT IS: an interface to add to the set, the single base-type constraint,
    // or a shape the emitter does not model. The caller answers the CLR questions because it holds the
    // `Type`; the DECISION is here, so both generic-parameter owners reach it the same way.
    //
    // A type PARAMETER is a BASE constraint (`where T: U`), never an interface — it is not known to be
    // one, and the CLR records it in the base slot. The caller must pass `false` for the four
    // shape questions when the constraint IS a parameter: `Type.IsSZArray` throws on a bare parameter
    // under persisted emit, so those answers must never be computed for one.
    static func ConstraintKindInterface(): int {
        return 0
    }

    static func ConstraintKindBase(): int {
        return 1
    }

    static func ConstraintKindRefused(): int {
        return -1
    }

    static func ClassifyConstraint(isGenericParameter: bool, isUserInterface: bool, isRuntimeInterface: bool, isTypeBuilder: bool, isValueType: bool, isFromAssemblyBuilder: bool, isSzArray: bool, isClass: bool): int {
        if isGenericParameter {
            return ConstraintKindBase()
        }

        if isUserInterface || isRuntimeInterface {
            return ConstraintKindInterface()
        }

        if IsAdmissibleBaseConstraint(false, isTypeBuilder, isValueType, isFromAssemblyBuilder, isSzArray, isClass) {
            return ConstraintKindBase()
        }

        return ConstraintKindRefused()
    }

    // CIRCULAR type-parameter constraints (`where T: T`, `where T: U where U: T`) emit metadata the CLR
    // REJECTS at load with a TypeLoadException — probe-proven over-accept, so the emitter must decline
    // rather than write it.
    //
    // `baseParamIndices[g]` is the index of the type parameter that g's base constraint names, or -1 when
    // g has no base constraint or names something that is not one of this owner's parameters. Walking
    // more steps than there are parameters means the chain re-entered itself.
    static func HasCircularConstraint(baseParamIndices: int[]): bool {
        g := 0
        while g < baseParamIndices.Length {
            steps := 0
            cursor := g
            while cursor >= 0 && baseParamIndices[cursor] >= 0 {
                cursor = baseParamIndices[cursor]
                steps = steps + 1
                if steps > baseParamIndices.Length {
                    return true
                }
            }

            g = g + 1
        }

        return false
    }

    // A constraint row set is well-formed only when every parameter that carries one is a parameter this
    // owner declared. A non-generic owner with constraint rows is malformed outright.
    static func HasConstraintsWithoutTypeParameters(typeParamCount: int, specialCount: int, typeConstraintCount: int): bool {
        return typeParamCount == 0 && (specialCount > 0 || typeConstraintCount > 0)
    }
}
