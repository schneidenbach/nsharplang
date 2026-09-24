namespace NSharpLang.Compiler.Columnar

import System
import NSharpLang.Compiler


// 023/1e — THE TWO IMPLICIT CONSTANT CONVERSIONS, IN ONE N#-OWNED PLACE.
//
// C# has two of these and they are DIFFERENT RULES over different domains. Folding them into one
// "any in-range literal converts" would make N# strictly laxer than C# and would silently accept
// `AssemblyFlags = 7` for a flag combination that names nothing:
//
//   ECMA-334 §10.2.4  implicit ENUMERATION conversion — a constant expression of any integer type
//                     WITH THE VALUE ZERO converts to any enum type. Zero and nothing else.
//   ECMA-334 §10.2.11 implicit CONSTANT EXPRESSION conversion — an `int` constant IN RANGE converts
//                     to sbyte/byte/short/ushort/uint, and a `long` constant in range to ulong.
//
// Both answers used to be spelled inside `ColumnarIlEmitter.TryEmitIntLiteralAsType`, in C#, and were
// MIRRORED in N# by `ColumnarMethodBodyPlanner` — which reasons about that function's behaviour to
// decide whether the N# door may claim a body at all — and by
// `ColumnarScalarLiteralPlanner.TryGetTargetTypedIntegerMagnitude`. One rule, three owners, two
// languages. This owner is the single answer all of them consult; the C# host keeps only the
// `_il.Emit` of the value returned here.
//
// THE INTEGER PARSER IS NOT WRITTEN AGAIN. `NumericLiteralFacts.TryParseIntegerLiteral`
// already owns suffix classification (kind 0 unsuffixed, 1 `L`, 2 `UL`) and radix parsing; this owner
// delegates to it and adds only the target-fit decision.
class ConstantConversionFacts {

    // §10.2.4. The value ZERO in any integer literal form converts to any enum type. The suffix does
    // not matter — `0`, `0L` and `0UL` are all constant expressions of an integer type with the value
    // zero — so the MAGNITUDE is the whole test, and a negated zero is not a zero literal.
    static func IsLiteralZero(literalText: string?, negative: bool): bool {
        if literalText == null || negative {
            return false
        }

        literalKind := 0
        magnitude := 0UL
        if !NumericLiteralFacts.TryParseIntegerLiteral(literalText, out literalKind, out magnitude) {
            return false
        }

        return magnitude == 0UL
    }

    // §10.2.11, as the PIPELINE allows it. THE THREE CAPS BELOW ARE NOT THE SPEC'S AND THEY ARE
    // DELIBERATE. The C# host capped three cases below what C# itself permits, each because the LEGACY
    // pipeline mis-evaluates the wider value and the columnar backend declines rather than diverge:
    //   `uint` caps at int.MaxValue, not uint.MaxValue          (defect bundle #12 — `u: uint = 4000000000`
    //                                                            then `u / 2` returned the signed bit pattern)
    //   positive `long`/`ulong` magnitudes ALSO cap at int.MaxValue  (#13 — the pipeline overflows on
    //                                                            any unsuffixed literal beyond int range)
    //   negative magnitudes cap at the target's MAXVALUE magnitude   (#14 — its negation range check is
    //                                                            off by one, so `v: sbyte = -128` is refused)
    // Moving the decision must not move the ANSWER, so the caps move verbatim. They are stated HERE
    // rather than in the emitter because a decline the two owners disagree about is a claim the N# door
    // makes and the host then refuses — the failure `ColumnarMethodBodyPlanner` exists to prevent.
    // FILED, not fixed here: with the decision in one place they are now correctable in one place.
    static func TryGetInRangeIntegralConstant(target: Type?, literalText: string?, negative: bool, out value: long): bool {
        value = 0L
        if target == null || literalText == null {
            return false
        }

        literalKind := 0
        magnitude := 0UL
        if !NumericLiteralFacts.TryParseIntegerLiteral(literalText, out literalKind, out magnitude) {
            return false
        }

        // A suffixed literal carries its own fixed type and does not adopt a target.
        if literalKind != 0 {
            return false
        }

        if negative {
            return TryGetNegativeConstant(target, magnitude, out value)
        }

        return TryGetPositiveConstant(target, magnitude, out value)
    }

    static func TryGetNegativeConstant(target: Type, magnitude: ulong, out value: long): bool {
        value = 0L
        if IsPrimitive(target, "System.Byte") || IsPrimitive(target, "System.UInt16") || IsPrimitive(target, "System.UInt32") || IsPrimitive(target, "System.UInt64") {
            return false
        }

        limit := 2147483647UL
        if IsPrimitive(target, "System.SByte") {
            limit = 127UL
        } else if IsPrimitive(target, "System.Int16") {
            limit = 32767UL
        } else if !IsPrimitive(target, "System.Int32") && !IsPrimitive(target, "System.Int64") {
            return false
        }

        if magnitude > limit {
            return false
        }

        value = 0L - (long)magnitude
        return true
    }

    static func TryGetPositiveConstant(target: Type, magnitude: ulong, out value: long): bool {
        value = 0L
        limit := 0UL
        if IsPrimitive(target, "System.Byte") {
            limit = 255UL
        } else if IsPrimitive(target, "System.SByte") {
            limit = 127UL
        } else if IsPrimitive(target, "System.Int16") {
            limit = 32767UL
        } else if IsPrimitive(target, "System.UInt16") {
            limit = 65535UL
        } else if IsPrimitive(target, "System.UInt32") || IsPrimitive(target, "System.Int64") || IsPrimitive(target, "System.UInt64") {
            limit = 2147483647UL
        } else {
            return false
        }

        if magnitude > limit {
            return false
        }

        value = (long)magnitude
        return true
    }

    // BOTH CONSTANT CONVERSIONS, ASKED OF A CLR TYPE, IN ONE QUESTION.
    //
    // The two rules above are a pair at every position that has a TARGET and a LITERAL: §10.2.4 when the
    // target is an enum, §10.2.11 when it is a narrower integral. The analyzer's assignability owner and
    // the REFLECTION binder both need exactly that pair — one for `b: byte = 0`, the other for
    // `roots.TryAdd(root, 0)` against `ConcurrentDictionary<string, byte>.TryAdd(string, byte)` — and a
    // second spelling of the branch is a second place for the two to drift apart.
    //
    // An OPEN type is refused outright: a constant conversion takes no part in method type inference, so
    // a parameter still mentioning a type parameter must be bound by the standard rules or not at all.
    static func AcceptsIntegerConstant(target: Type?, literalText: string?, negative: bool): bool {
        if target == null || target.ContainsGenericParameters || target.IsByRef {
            return false
        }

        if target.IsEnum {
            return IsLiteralZero(literalText, negative)
        }

        constantValue := 0L
        return TryGetInRangeIntegralConstant(target, literalText, negative, out constantValue)
    }

    // `long` and `ulong` targets take `ldc.i8`; every narrower target is an `ldc.i4` whose stack type is
    // int32, which is what the CLR's storage conversions expect for a `stelem.i1` or a narrower `stfld`.
    static func IsInt64ConstantTarget(target: Type): bool {
        return IsPrimitive(target, "System.Int64") || IsPrimitive(target, "System.UInt64")
    }

    // THE TARGET'S PRIMITIVE IDENTITY, READ FROM ITS NAME RATHER THAN FROM ITS INSTANCE.
    //
    // These tests used to be `target == typeof(byte)`, which is REFERENCE equality over `Type` and is
    // therefore false for the very same `System.Byte` when it arrives from a MetadataLoadContext — and
    // every parameter type the reflection binder asks about arrives from one. The emitter's own runtime
    // `Type`s answer the same way here (`typeof(byte).FullName` IS `"System.Byte"`), so the decision is
    // unchanged where it already worked and now has an answer where it silently had none.
    //
    // A NULLABLE SHELL IS NOT UNWRAPPED. `Nullable<byte>` is a different target from `byte` and keeps
    // the answer it had; lifting a constant conversion through it is a separate rule this owner does
    // not state.
    static func IsPrimitive(target: Type, fullName: string): bool {
        return target.FullName == fullName
    }
}

// The constant an expression carries, for the positions that have the expression in hand when they ask
// whether a value is assignable. `IsAssignable(target, source)` is a TypeInfo-to-TypeInfo predicate with
// 45 call sites and no literal in scope; rather than thread a fact through all 45, the constant-aware
// overload takes this and the two-argument form delegates with `None()`. A position that cannot supply
// the fact keeps today's behaviour by construction.
class ConstantOperandFacts {
    HasIntegerLiteral: bool
    LiteralText: string
    IsNegative: bool

    constructor(hasIntegerLiteral: bool, literalText: string, isNegative: bool) {
        HasIntegerLiteral = hasIntegerLiteral
        LiteralText = literalText
        IsNegative = isNegative
    }

    static func None(): ConstantOperandFacts {
        return new ConstantOperandFacts(false, "", false)
    }

    // A NEGATIVE literal arrives as `Negate` over the bare literal, which is the same shape the emitter
    // unwraps. Anything else — a call, an identifier, a binary expression — carries no constant, and the
    // caller falls back to the ordinary assignability answer.
    static func FromExpression(expression: Expression?): ConstantOperandFacts {
        if expression == null {
            return None()
        }

        negative := false
        candidate := expression
        unary := candidate as UnaryExpression
        if unary != null && unary.Operator == UnaryOperator.Negate {
            negative = true
            candidate = unary.Operand
        }

        literal := candidate as IntLiteralExpression
        if literal == null {
            return None()
        }

        return new ConstantOperandFacts(true, literal.Value, negative)
    }
}
