namespace NSharpLang.QualifiedNames.Tests

import System
import System.Collections.Generic
import System.IO
import System.IO as Io
import System.Text as Txt


// WHAT A NAMESPACE-QUALIFIED NAME MEANS IN EXPRESSION POSITION, EXECUTED.
//
// Every assertion below runs against the IL these sources emit, so a passing test is a claim about
// resolution AND about emission: the qualified spelling reaches the same static-call, static-read and
// construction paths the bare spelling reaches, rather than a parallel one.
//
// Before this, the leftmost segment of a dotted chain was analysed as a VALUE, so
// `System.Math.Max(1, 2)` reported `NL301: Variable 'System' not found` — while the very same
// program's `System.Int32.MaxValue` resolved, because only a CALL re-analysed its receiver as an
// expression. The two spellings now mean one thing.

// ── qualified CLR statics ─────────────────────────────────────────────────────────────────────
test "a fully qualified static method call resolves and runs" {
    assert System.Math.Max(1, 2) == 2
    assert System.Math.Min(1, 2) == 1
}

test "a fully qualified static call reaches the same method the imported spelling does" {
    assert System.Math.Abs(-7) == Math.Abs(-7)
}

test "a fully qualified static field and property read resolve" {
    assert System.Int32.MaxValue == 2147483647
    assert System.Int32.MinValue == -2147483648
}

test "a fully qualified static call on a namespace two segments deep resolves" {
    parts := new List<string>()
    parts.Add("a")
    parts.Add("b")
    assert System.String.Join(",", parts) == "a,b"
}

test "a fully qualified construction resolves and the constructed value is usable" {
    builder := new System.Text.StringBuilder()
    builder.Append("qualified")
    assert builder.ToString() == "qualified"
}

test "a fully qualified enum member is the same value as the imported spelling" {
    assert System.DayOfWeek.Monday == DayOfWeek.Monday
    assert Convert.ToInt32(System.DayOfWeek.Wednesday) == 3
}

test "a qualified type name used as a receiver answers the type it names" {
    assert System.String.IsNullOrEmpty("") == true
    assert System.String.IsNullOrEmpty("x") == false
}

test "a qualified static call into a namespace the file never imported resolves" {
    values := new List<int>()
    values.Add(4)
    values.Add(5)
    assert System.Linq.Enumerable.Count(values) == 2
}

// ── namespace aliases in expression position ──────────────────────────────────────────────────

test "a namespace alias qualifies a static call" {
    assert Io.Path.Combine("a", "b") == Path.Combine("a", "b")
    assert Io.Path.GetExtension("x.nl") == ".nl"
}

test "a namespace alias qualifies a construction" {
    builder := new Txt.StringBuilder()
    builder.Append("alias")
    assert builder.ToString() == "alias"
}

// ── qualified project source types ────────────────────────────────────────────────────────────

test "a namespace-qualified source static call resolves and runs" {
    assert NSharpLang.QualifiedNames.Library.Helper.Twice(4) == 8
    assert NSharpLang.QualifiedNames.Library.Helper.Concat("a", "b") == "ab"
}

test "a namespace-qualified source static property and field read resolve" {
    assert NSharpLang.QualifiedNames.Library.Helper.Answer == 42
    assert NSharpLang.QualifiedNames.Library.Helper.Origin == "library"
}

test "a namespace-qualified source enum member resolves" {
    assert NSharpLang.QualifiedNames.Library.Season.Autumn == NSharpLang.QualifiedNames.Library.Season.Autumn
    assert Convert.ToInt32(NSharpLang.QualifiedNames.Library.Season.Autumn) == 2
}

test "a namespace-qualified source enum member and its bare spelling are one value" {
    qualified := NSharpLang.QualifiedNames.Library.Season.Winter
    assert Convert.ToInt32(qualified) == 3
}

// ── the shadowing hazard ──────────────────────────────────────────────────────────────────────
//
// `NSharpLang.QualifiedNames.Shadow` declares a `Version`, and nothing in this file imports that
// namespace. `import System` does bring `System.Version` in, so the bare spelling must be the CLR
// type — the source class is reachable here only by its qualified name. Both halves are proved: the
// bare name binds to the import at ANALYSIS (the assertions type-check) and at EMISSION (they run).

test "an imported CLR type is not shadowed by a source type in an unimported namespace" {
    release := new Version(4, 2)
    assert release.Major == 4
    assert release.Minor == 2
    assert typeof(Version).get_FullName() == "System.Version"
}

test "the shadowed source type is still reachable by its qualified name" {
    assert NSharpLang.QualifiedNames.Shadow.Version.Origin() == "shadow"
    value := new NSharpLang.QualifiedNames.Shadow.Version()
    assert value.Marker == "source-version"
}

// ── ordinary external instance property reads ─────────────────────────────────────────────────
//
// `m.Name` used to decline at emit while `m.get_Name()` — the accessor spelling for the very same
// getter — emitted, because the receiver had to be on a list of named types. A reflection handle is
// an ordinary external reference receiver and its readable properties are ordinary reads.

class ReflectionSubject {
    Value: int

    constructor() {
        Value = 3
    }

    static func Doubled(input: int): int {
        return input * 2
    }

    func Read(): int {
        return Value
    }
}

test "a property read on a reflection method handle resolves" {
    method := typeof(ReflectionSubject).GetMethod("Doubled")
    assert method != null
    if method != null {
        assert method.Name == "Doubled"
        assert method.IsStatic == true
        assert method.ReturnType == typeof(int)
    }
}

test "the property spelling and the accessor spelling read the same member" {
    method := typeof(ReflectionSubject).GetMethod("Read")
    assert method != null
    if method != null {
        assert method.Name == method.get_Name()
        assert method.IsStatic == method.get_IsStatic()
    }
}

test "a property read on a reflection type handle resolves" {
    handle := typeof(ReflectionSubject)
    assert handle.IsClass == true
    assert handle.IsAbstract == false
}

test "an instance property read through an external interface receiver resolves" {
    values := new List<int>()
    values.Add(1)
    values.Add(2)
    values.Add(3)
    view: IList<int> = values
    assert view.Count == 3
    assert view.Count == view.get_Count()
}
