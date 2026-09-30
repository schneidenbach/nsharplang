namespace NSharpLang.CensusPackagePrivateTypes.Tests

import System
import System.Reflection


// THE EMITTED ACCESSIBILITY of every top-level type kind, read out of the assembly this project built.
//
// `Type.IsPublic` is true only for a top-level `public` type; `Type.IsNotPublic` is its complement and
// is what the CLR calls assembly-only. For a NESTED type the questions are `IsNestedPublic` and
// `IsNestedAssembly`, which is why the nested rows ask different predicates — the CLR has two
// vocabularies and a test that used one for both would be asking the wrong question half the time.
class PackagePrivateShapeFacts {
    static func TypeByName(simpleName: string): Type {
        holder := typeof(ExportedClass)
        assembly := holder.Assembly
        return must assembly.GetType("NSharpLang.CensusPackagePrivateTypes.Tests." + simpleName)
    }

    // `public` / `assembly` for a top-level type, asked of both predicates so a type that somehow
    // answered neither (or both) is caught rather than reported as one of them.
    static func Visibility(simpleName: string): string {
        found := TypeByName(simpleName)
        if found.IsPublic && !found.IsNotPublic {
            return "public"
        }

        if found.IsNotPublic && !found.IsPublic {
            return "assembly"
        }

        return "ambiguous"
    }

    static func NestedVisibility(outerName: string, nestedName: string): string {
        outer := TypeByName(outerName)
        nested := must outer.GetNestedType(nestedName, BindingFlags.Public | BindingFlags.NonPublic)
        if nested.IsNestedPublic {
            return "nested-public"
        }

        if nested.IsNestedAssembly {
            return "nested-assembly"
        }

        if nested.IsNestedPrivate {
            return "nested-private"
        }

        return "other"
    }
}

test "a camelCase CLASS is emitted assembly and its PascalCase twin public" {
    assert PackagePrivateShapeFacts.Visibility("ExportedClass") == "public"
    assert PackagePrivateShapeFacts.Visibility("packagePrivateClass") == "assembly"
}

test "a camelCase STRUCT and RECORD follow the same rule as a class" {
    assert PackagePrivateShapeFacts.Visibility("ExportedStruct") == "public"
    assert PackagePrivateShapeFacts.Visibility("packagePrivateStruct") == "assembly"
    assert PackagePrivateShapeFacts.Visibility("ExportedRecord") == "public"
    assert PackagePrivateShapeFacts.Visibility("packagePrivateRecord") == "assembly"
}

test "a camelCase INTERFACE follows it too — the leading letter is the whole rule, not the `I`" {
    assert PackagePrivateShapeFacts.Visibility("IExported") == "public"
    assert PackagePrivateShapeFacts.Visibility("iPackagePrivate") == "assembly"
}

test "a camelCase ENUM follows it" {
    assert PackagePrivateShapeFacts.Visibility("ExportedEnum") == "public"
    assert PackagePrivateShapeFacts.Visibility("packagePrivateEnum") == "assembly"
}

test "a camelCase UNION's BASE type follows it" {
    assert PackagePrivateShapeFacts.Visibility("ExportedUnion") == "public"
    assert PackagePrivateShapeFacts.Visibility("packagePrivateUnion") == "assembly"
}

test "NESTED visibility is UNCHANGED — it answered its own casing before this and still does" {
    assert PackagePrivateShapeFacts.NestedVisibility("ExportedClass", "NestedExported") == "nested-public"

    // MEASURED, AND NARROWER THAN THE PACKAGE RULE. A camelCase nested type is emitted
    // `NestedPrivate` — reachable from its enclosing type only — where a camelCase TOP-LEVEL type is
    // `assembly`. That predates this change (`ColumnarStructInput.NestedVisibilityFor` has answered 3
    // for a lowercase nested name for as long as it has existed) and is pinned here rather than
    // altered, because widening it to `NestedAssembly` is a separate decision about what nesting means
    // in N# and not part of making the TOP-LEVEL rule reach metadata.
    assert PackagePrivateShapeFacts.NestedVisibility("ExportedClass", "nestedHidden") == "nested-private"
}

test "a package-private type is fully usable from the package that declares it" {
    assert PackagePrivateReach.BuildAndRead() == 5
    assert PackagePrivateReach.ReadThroughPackagePrivateInterface() == 7
}

test "and from ANOTHER FILE of the same namespace, which is why there is no file-private tier" {
    assert SecondFileReach.ReadHiddenClass() == 4
    assert SecondFileReach.ReadHiddenStruct() == 11
    assert SecondFileReach.ReadHiddenRecord() == 12
}
