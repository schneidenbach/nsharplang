namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Globalization
import System.Reflection


// 023/1a — EXTERNAL ENUM MEMBERS ARE ADMITTED WHOLESALE, MEASURED END TO END.
//
// `ColumnarExternalBindingPlans.GetStaticMemberPlan` used to carry its enums two irreconcilable ways.
// Four rows admitted a WHOLE enum (`BindingFlags`, `StringComparison`, `NullabilityState`,
// `JsonValueKind`); four admitted ONE MEMBER of one (`MethodAttributes.Public`,
// `CallingConventions.Standard`, `SearchOption.TopDirectoryOnly`, `NumberStyles.HexNumber`). The
// consequence was a language a reader could not state: `MethodAttributes.Public` compiled and
// `MethodAttributes.Static` declined the whole assembly at `emit.local.initializer`, naming the LOCAL
// and never the member. The `BindingFlags` row had already written down why the whole type is the only
// coherent answer, and the per-member rows were exactly the decline that comment predicted, moved one
// step later.
//
// These contracts are end to end on purpose. The unit contracts beside the planner pin the SELECTION;
// what a mask costs is only visible when it is COMBINED and then USED, because that is where the
// declines actually landed — a `|` over two members in a local initializer, and the same `|` in an
// argument position. Both are written here, over enums whose types are NOT on
// `IsSupportedRuntimeTypeName`, which is the second half of the measurement: admitting a member does
// not require admitting its type.

func EnumFactsTypeAttributeMask(): int {
    mask := TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed
    return Convert.ToInt32(mask)
}

func EnumFactsTakesMethodAttributes(value: MethodAttributes): int {
    return Convert.ToInt32(value)
}

func EnumFactsTakesGenericParameterAttributes(value: GenericParameterAttributes): int {
    return Convert.ToInt32(value)
}

test "a member the per-member row refused now binds, and carries its own value" {
    // `MethodAttributes.Public` was the ONE member the old row admitted. Every sibling declined.
    // All four are ordinary public static literal fields of the same enum; nothing distinguished them.
    assert Convert.ToInt32(MethodAttributes.Public) == 6
    assert Convert.ToInt32(MethodAttributes.Static) == 16
    assert Convert.ToInt32(MethodAttributes.Family) == 4
    assert Convert.ToInt32(MethodAttributes.Virtual) == 64

    // `CallingConventions.Standard` was the other single-member row.
    assert Convert.ToInt32(CallingConventions.Standard) == 1
    assert Convert.ToInt32(CallingConventions.VarArgs) == 2
}

test "a mask combination binds in a local initializer" {
    // The shape that declined: `|` over two members of an enum with a per-member row. It declined at
    // `emit.local.initializer` and the message named the LOCAL, so the member was never in the text.
    mask := MethodAttributes.Public | MethodAttributes.Static
    assert Convert.ToInt32(mask) == 22

    // A three-way mask over an enum that had NO row at all, and whose type is not on the admitted-type
    // list either: Public(0x1) | Abstract(0x80) | Sealed(0x100).
    assert EnumFactsTypeAttributeMask() == 385
}

test "a mask combination binds in an argument position" {
    // The argument position is a separate emit path from the local initializer and declined separately.
    assert EnumFactsTakesMethodAttributes(MethodAttributes.Public | MethodAttributes.Static) == 22
    assert EnumFactsTakesMethodAttributes(MethodAttributes.Family) == 4
}

test "an enum from an assembly the catalog reaches binds without a row of its own" {
    // `GenericParameterAttributes` and `StringSplitOptions` have no static-member row and no
    // admitted-type row anywhere. They bind because they are enums, which is the whole of the new rule.
    assert Convert.ToInt32(GenericParameterAttributes.Covariant) == 1
    assert EnumFactsTakesGenericParameterAttributes(GenericParameterAttributes.Covariant | GenericParameterAttributes.Contravariant) == 3
    assert Convert.ToInt32(StringSplitOptions.RemoveEmptyEntries) == 1
    assert Convert.ToInt32(StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries) == 3

    // And an enum whose whole type WAS admitted must not have moved.
    assert Convert.ToInt32(BindingFlags.Public | BindingFlags.Static) == 24
    assert Convert.ToInt32(NumberStyles.HexNumber) == 515
    assert Convert.ToInt32(StringComparison.Ordinal) == 4
}
