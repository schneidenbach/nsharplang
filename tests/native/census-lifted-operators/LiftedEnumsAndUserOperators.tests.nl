namespace NSharpLang.CensusLiftedOperators.Tests

import System
import System.Reflection

test "a lifted bitwise operator over a nullable enum answers that enum, absent when either side is" {
    assert CombineAccess(Access.Read, Access.Write) == (Access.Read | Access.Write)
    assert CombineAccess(Access.Read, null) == null
    assert CombineAccess(null, Access.Write) == null
    assert MaskAccess((Access.Read | Access.Write), Access.Write) == Access.Write
    assert MaskAccess(Access.Read, null) == null
    assert ToggleAccess((Access.Read | Access.Write), Access.Write) == Access.Read
    assert ToggleAccess(null, Access.Write) == null
}

test "a lifted `~` over a nullable enum inverts the backing bits and keeps the enum type" {
    assert InvertAccess(Access.None) == ~Access.None
    assert InvertAccess(Access.Read) == ~Access.Read
    assert InvertAccess(null) == null
}

test "a plain enum operand joins a lifted bitwise combination" {
    assert CombineAccessWithValue(Access.Read, Access.Delete) == (Access.Read | Access.Delete)
    assert CombineAccessWithValue(null, Access.Delete) == null
}

test "a user-defined `op_*` is lifted through ordinary operator resolution — decimal" {
    assert AddDecimals(1.5m, 2.25m) == 3.75m
    assert AddDecimals(null, 2.25m) == null
    assert AddDecimals(1.5m, null) == null
    assert SubtractDecimals(3.75m, 1.5m) == 2.25m
    assert SubtractDecimals(null, 1.5m) == null
    assert MultiplyDecimals(1.5m, 4m) == 6m
    assert MultiplyDecimals(1.5m, null) == null
    assert NegateDecimal(1.5m) == -1.5m
    assert NegateDecimal(null) == null
}

test "a user-defined `op_*` is lifted through ordinary operator resolution — TimeSpan" {
    assert AddSpans(TimeSpan.FromMinutes(2), TimeSpan.FromMinutes(3)) == TimeSpan.FromMinutes(5)
    assert AddSpans(null, TimeSpan.FromMinutes(3)) == null
    assert SubtractSpans(TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(3)) == TimeSpan.FromMinutes(2)
    assert SubtractSpans(TimeSpan.FromMinutes(5), null) == null
    assert NegateSpan(TimeSpan.FromMinutes(2)) == TimeSpan.FromMinutes(-2)
    assert NegateSpan(null) == null
}

test "a user-defined ORDERING operator is lifted to a plain bool, false on an absent operand" {
    assert SpanIsShorter(TimeSpan.FromMinutes(2), TimeSpan.FromMinutes(3))
    assert !SpanIsShorter(TimeSpan.FromMinutes(3), TimeSpan.FromMinutes(2))
    assert !SpanIsShorter(null, TimeSpan.FromMinutes(3))
    assert !SpanIsShorter(TimeSpan.FromMinutes(3), null)
    assert DecimalIsSmaller(1.5m, 2.5m)
    assert !DecimalIsSmaller(null, 2.5m)
}

test "the emitted metadata declares a lifted arithmetic result as Nullable<T>" {
    owner := typeof(LiftedSignatures)
    sum := owner.GetMethod("Sum", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    assert sum != null
    assert Nullable.GetUnderlyingType(sum.ReturnType) == typeof(int)
}

test "the emitted metadata declares a lifted ORDERING result as a plain bool" {
    owner := typeof(LiftedSignatures)
    compare := owner.GetMethod("Compare", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    assert compare != null
    assert compare.ReturnType == typeof(bool)
    assert Nullable.GetUnderlyingType(compare.ReturnType) == null
}

test "the emitted metadata keeps a lifted enum combination as Nullable of that enum" {
    owner := typeof(LiftedSignatures)
    combine := owner.GetMethod("Combine", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    assert combine != null
    assert Nullable.GetUnderlyingType(combine.ReturnType) == typeof(Access)
}
