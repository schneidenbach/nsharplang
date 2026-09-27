namespace NSharpLang.Compiler.Columnar

import System
import System.Runtime.Loader


// The shape that declined Core's estate on Linux CI: the SAME assembly file loaded into a second load
// context, so one type name is two types. A collectible context holds the second copy and is unloaded.
test "one type name from two loads is named with both files and both load contexts" {
    compilerType := typeof(System.Reflection.MetadataLoadContext)
    second := new AssemblyLoadContext("nsharp-split-identity-probe", true)
    try {
        copy := second.LoadFromAssemblyPath(compilerType.Assembly.Location)
        copyType := copy.GetType("System.Reflection.MetadataLoadContext", true)
        assert !Object.ReferenceEquals(copyType, compilerType)

        detail := ColumnarSplitTypeIdentityFacts.Describe(copyType, compilerType)
        assert detail.StartsWith("'System.Reflection.MetadataLoadContext' is one type name from two loads of '" + compilerType.Assembly.FullName + "': "), detail
        assert detail.Contains("in load context 'nsharp-split-identity-probe' versus "), detail
        assert detail.Contains(compilerType.Assembly.Location), detail
    } finally {
        second.Unload()
    }
}

test "a type and itself, or two different types, are not a split load" {
    assert ColumnarSplitTypeIdentityFacts.Describe(typeof(string), typeof(string)) == ""
    assert ColumnarSplitTypeIdentityFacts.Describe(typeof(string), typeof(int)) == ""
    assert ColumnarSplitTypeIdentityFacts.Describe(null, typeof(int)) == ""
    assert ColumnarSplitTypeIdentityFacts.Describe(typeof(int), null) == ""
}
