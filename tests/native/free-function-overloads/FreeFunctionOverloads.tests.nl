namespace NSharpLang.FreeFunctionOverloads

import System.Reflection

func FreeFunctionOverloadMethodCount(name: string): int {
    holder := typeof(StaticFormatter).Assembly.GetType("NSharpLang.FreeFunctionOverloads.Program")
    assert holder != null
    methods := holder.GetMethods(BindingFlags.Public | BindingFlags.Static)
    count := 0
    for method in methods {
        if method.Name == name {
            count = count + 1
        }
    }
    return count
}

test "distinct signatures emit distinct CLR methods on the free-function holder" {
    assert FreeFunctionOverloadMethodCount("CountOf") == 2
}

test "type-based top-level overloads use analyzer conversion ranking" {
    assert CountOf(3) == 3
    assert CountOf("abc") == 3
    assert Width(4) == "int"
    assert Width(4L) == "long"
}

test "an overloaded tuple call keeps the selected return labels" {
    assert LabelBy(3).Number == 3
    assert LabelBy("abc").Text == "abc"
}

test "arity and generic top-level overloads select the matching declaration" {
    assert ByArity(7) == "one:7"
    assert ByArity(7, 2) == "two:9"
    assert GenericWidth(6) == 1
    assert GenericWidth(6, 8) == 8
}

test "same-namespace overloads across project files form one call group" {
    assert AcrossFiles(11) == "cross-int:11"
    assert AcrossFiles("cross") == "cross-text:cross"
}

test "overloaded free-function and static method groups bind to delegate parameters" {
    assert ApplyInt(Format) == "int:9"
    assert ApplyText(Format) == "text:ok"
    assert ApplyStaticInt(StaticFormatter.Format) == "static-int:5"
}

test "main runs overloads and prints their selected results" {
    assert MainOutput() == "3\n3\nint\nlong\none:7\ntwo:9\n1\n8\ncross-int:11\ncross-text:cross\nint:9\ntext:ok\nstatic-int:5"
}
